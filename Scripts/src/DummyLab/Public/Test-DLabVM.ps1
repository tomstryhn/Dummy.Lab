# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-DLabVM {
    <#
    .SYNOPSIS
        Runs a health check against a Dummy.Lab VM.
    .DESCRIPTION
        Opens a PowerShell Direct session and runs a series of role-aware
        checks. Returns a DLab.HealthStatus with per-check detail suitable
        for dashboards, alerting, or interactive triage.

        Checks performed:
          - VM exists in Hyper-V and is Running
          - PS Direct session succeeds with auto-resolved credentials
          - Time skew between host and guest is within 5 minutes (Kerberos
            threshold)
          - System drive has >= 2 GB free
          - For DCs: NTDS and DNS services Running; optional DHCP if declared
          - For member servers: PartOfDomain is true and Domain matches the
            lab's declared domain (catches the local-SAM-fallback
            false-positive we saw in Phase 2a)

        Does not mutate state. Safe to run repeatedly or in parallel.
    .PARAMETER LabName
        Lab containing the VM. Required when using -Name. Binds from DLab.VM.
    .PARAMETER Name
        Short or full VM name. Binds from DLab.VM.
    .PARAMETER IncludeUpdateStatus
        Also query Windows Update status inside the guest (slower, requires
        the PSWindowsUpdate module or sconfig). Default off.
    .EXAMPLE
        Test-DLabVM -LabName Pipeline -Name DC01
    .EXAMPLE
        Get-DLabVM | Test-DLabVM | Where-Object OverallStatus -ne 'Healthy'
    #>
    [CmdletBinding()]
    [OutputType('DLab.HealthStatus')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$LabName,

        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('ShortName', 'VMName')]
        [string]$Name,

        [switch]$IncludeUpdateStatus
    )

    process {
        $fullName = if ($Name -like "$LabName-*") { $Name } else { "$LabName-$Name" }
        $checks = @()

        # --- Check 1: Hyper-V presence + state ---------------------------
        $hvVM = Get-VM -Name $fullName -ErrorAction SilentlyContinue
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Hyper-V VM exists'
            Status     = if ($hvVM) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($hvVM) { "State: $($hvVM.State)" } else { "VM not found: $fullName" }
        }
        if (-not $hvVM) {
            return [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $fullName
                Timestamp     = Get-Date
                OverallStatus = 'Unhealthy'
                Checks        = $checks
            }
        }

        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'VM Running'
            Status     = if ($hvVM.State -eq 'Running') { 'Healthy' } else { 'Degraded' }
            Message    = "State: $($hvVM.State)"
        }
        if ($hvVM.State -ne 'Running') {
            return [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $fullName
                Timestamp     = Get-Date
                OverallStatus = 'Degraded'
                Checks        = $checks
            }
        }

        # --- Load lab state for role + domain context --------------------
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName
        if (-not (Test-Path $statePath)) {
            $checks += [PSCustomObject]@{
                PSTypeName = 'DLab.HealthCheck'
                Name       = 'Lab state readable'
                Status     = 'Unhealthy'
                Message    = "State file missing: $statePath"
            }
            return [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $fullName
                Timestamp     = Get-Date
                OverallStatus = 'Unhealthy'
                Checks        = $checks
            }
        }
        $state = Get-Content $statePath -Raw | ConvertFrom-Json
        $vmEntry = $state.VMs | Where-Object { $_.Name -eq $fullName } | Select-Object -First 1
        $role = if ($vmEntry) { $vmEntry.Role } else { 'Unknown' }

        # --- Build credentials via helper (no hand-constructed PSCredential)
        $creds = Get-DLabCredential -LabName $LabName
        $primaryCred   = if ($role -eq 'DC') { $creds.DomainAdmin } else { $creds.DomainAdmin }
        $fallbackCred  = $creds.LocalAdmin

        # --- Check: PS Direct reachable ----------------------------------
        $session = $null
        $usedDomain = $false
        try {
            $session = New-PSSession -VMName $fullName -Credential $primaryCred -ErrorAction Stop
            $usedDomain = $true
        } catch {
            try {
                $session = New-PSSession -VMName $fullName -Credential $fallbackCred -ErrorAction Stop
            } catch { }
        }
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'PS Direct reachable'
            Status     = if ($session) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($session) { "via $(if ($usedDomain) { 'domain' } else { 'local' }) credentials" } else { 'Could not authenticate with domain or local credentials' }
        }
        if (-not $session) {
            return [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $fullName
                Timestamp     = Get-Date
                OverallStatus = 'Unhealthy'
                Checks        = $checks
            }
        }

        try {
            # One Invoke-Command gathers everything so we take one session
            # round-trip instead of N. Fast and low overhead.
            $probe = Invoke-Command -Session $session -ScriptBlock {
                $cs = Get-CimInstance Win32_ComputerSystem
                $os = Get-CimInstance Win32_OperatingSystem
                $freeGB = [math]::Round((Get-PSDrive -Name C).Free / 1GB, 2)

                $services = @{}
                foreach ($svc in @('NTDS', 'DNS', 'DHCPServer')) {
                    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    if ($s) { $services[$svc] = $s.Status.ToString() }
                }

                [PSCustomObject]@{
                    GuestTime       = Get-Date
                    PartOfDomain    = $cs.PartOfDomain
                    Domain          = $cs.Domain
                    ComputerName    = $cs.Name
                    FreeGB          = $freeGB
                    OSName          = $os.Caption
                    LastBootTime    = $os.LastBootUpTime
                    Services        = $services
                }
            }

            # --- Check: time skew ----------------------------------------
            $skew = [math]::Abs(((Get-Date) - $probe.GuestTime).TotalMinutes)
            $checks += [PSCustomObject]@{
                PSTypeName = 'DLab.HealthCheck'
                Name       = 'Time skew'
                Status     = if ($skew -lt 5) { 'Healthy' } elseif ($skew -lt 30) { 'Degraded' } else { 'Unhealthy' }
                Message    = ('{0:N1} min from host' -f $skew)
            }

            # --- Check: free disk space ----------------------------------
            $checks += [PSCustomObject]@{
                PSTypeName = 'DLab.HealthCheck'
                Name       = 'System drive free space'
                Status     = if ($probe.FreeGB -ge 2) { 'Healthy' } elseif ($probe.FreeGB -ge 1) { 'Degraded' } else { 'Unhealthy' }
                Message    = ('{0} GB free on C:' -f $probe.FreeGB)
            }

            # --- Role-specific checks ------------------------------------
            if ($role -eq 'DC') {
                foreach ($svc in @('NTDS', 'DNS')) {
                    $svcState = $probe.Services[$svc]
                    $checks += [PSCustomObject]@{
                        PSTypeName = 'DLab.HealthCheck'
                        Name       = "Service: $svc"
                        Status     = if ($svcState -eq 'Running') { 'Healthy' } elseif ($svcState) { 'Degraded' } else { 'Unhealthy' }
                        Message    = if ($svcState) { "Status: $svcState" } else { 'Service not present' }
                    }
                }
                # DHCP is optional (only first DC has it in our default layout)
                if ($probe.Services.ContainsKey('DHCPServer')) {
                    $checks += [PSCustomObject]@{
                        PSTypeName = 'DLab.HealthCheck'
                        Name       = 'Service: DHCPServer'
                        Status     = if ($probe.Services['DHCPServer'] -eq 'Running') { 'Healthy' } else { 'Degraded' }
                        Message    = "Status: $($probe.Services['DHCPServer'])"
                    }
                }
            } elseif ($role -eq 'Server') {
                $expectedDomain = $state.DomainName
                $domainOk = $probe.PartOfDomain -and ($probe.Domain -eq $expectedDomain)
                $checks += [PSCustomObject]@{
                    PSTypeName = 'DLab.HealthCheck'
                    Name       = 'Domain membership'
                    Status     = if ($domainOk) { 'Healthy' } else { 'Unhealthy' }
                    Message    = "PartOfDomain=$($probe.PartOfDomain), Domain=$($probe.Domain), Expected=$expectedDomain"
                }
            }

            # --- Optional: Windows Update status -------------------------
            if ($IncludeUpdateStatus) {
                try {
                    $updates = Invoke-Command -Session $session -ScriptBlock {
                        $searcher = New-Object -ComObject Microsoft.Update.Searcher
                        $result   = $searcher.Search("IsInstalled=0 AND IsHidden=0")
                        $result.Updates.Count
                    } -ErrorAction Stop
                    $checks += [PSCustomObject]@{
                        PSTypeName = 'DLab.HealthCheck'
                        Name       = 'Pending Windows Updates'
                        Status     = if ($updates -eq 0) { 'Healthy' } elseif ($updates -lt 10) { 'Degraded' } else { 'Unhealthy' }
                        Message    = "$updates update(s) pending"
                    }
                } catch {
                    $checks += [PSCustomObject]@{
                        PSTypeName = 'DLab.HealthCheck'
                        Name       = 'Pending Windows Updates'
                        Status     = 'Unknown'
                        Message    = "Query failed: $($_.Exception.Message)"
                    }
                }
            }
        } finally {
            Remove-PSSession $session -ErrorAction SilentlyContinue
        }

        # --- Roll up overall status --------------------------------------
        $overall = 'Healthy'
        if ($checks.Status -contains 'Unhealthy')    { $overall = 'Unhealthy' }
        elseif ($checks.Status -contains 'Degraded') { $overall = 'Degraded' }

        [PSCustomObject]@{
            PSTypeName    = 'DLab.HealthStatus'
            Target        = $fullName
            Timestamp     = Get-Date
            OverallStatus = $overall
            Checks        = $checks
        }
    }
}
