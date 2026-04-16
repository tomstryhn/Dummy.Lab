# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-DLab {
    <#
    .SYNOPSIS
        Runs comprehensive health checks against a Dummy.Lab lab.
    .DESCRIPTION
        Two-layer health assessment:
          1. Infrastructure checks (read-only, fast): state file readable,
             switch exists, NAT exists if declared, storage folder present.
          2. Per-VM checks (per Test-DLabVM): runs health probes inside each
             VM in parallel via Invoke-Command sessions.

        Rolls up into a single DLab.HealthStatus per lab where the Checks
        collection includes both infrastructure checks and one aggregate
        per-VM check plus the nested VM health status objects.

        Safe to run on healthy or broken labs. Does not mutate state.
    .PARAMETER Name
        Lab name to test. Defaults to the LabName configured in
        DLab.Defaults.psd1 ('Dummy' out of the box) when neither the
        parameter nor a pipeline input is supplied. Accepts pipeline input
        from DLab.Lab.Name.
    .PARAMETER IncludeUpdateStatus
        Passed through to Test-DLabVM for Windows Update status queries.
    .EXAMPLE
        Test-DLab -Name Pipeline
    .EXAMPLE
        Get-DLab | Test-DLab | Where-Object OverallStatus -ne 'Healthy'
    .EXAMPLE
        Test-DLab -Name Pipeline | Select-Object -ExpandProperty Checks |
            Format-Table Name, Status, Message -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('DLab.HealthStatus')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LabName')]
        [string]$Name,

        [switch]$IncludeUpdateStatus
    )

    process {
        # Fall back to the configured default lab when neither the parameter
        # nor a pipeline binding supplied a name.
        if (-not $Name) {
            $Name = [string](Get-DLabConfigInternal).LabName
            if (-not $Name) {
                throw "Name is required and no default is configured in DLab.Defaults.psd1."
            }
        }

        $labName = $Name
        $checks  = @()

        # --- Check: state file readable -----------------------------------
        $statePath = Get-DLabStorePath -Kind LabState -LabName $labName
        $stateOk = Test-Path $statePath
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Lab state file'
            Status     = if ($stateOk) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($stateOk) { $statePath } else { "Not found: $statePath" }
        }
        if (-not $stateOk) {
            return [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $labName
                Timestamp     = Get-Date
                OverallStatus = 'Unhealthy'
                Checks        = $checks
                VMHealth      = @()
            }
        }

        $state = Get-Content $statePath -Raw | ConvertFrom-Json

        # --- Check: switch exists -----------------------------------------
        $switchName = if ($state.PSObject.Properties['Infrastructure'] -and $state.Infrastructure.SwitchName) {
            $state.Infrastructure.SwitchName
        } else { $state.Network.SwitchName }
        $liveSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Virtual switch'
            Status     = if ($liveSwitch) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($liveSwitch) { "$switchName (type: $($liveSwitch.SwitchType))" } else { "Missing: $switchName" }
        }

        # --- Check: NAT (only if declared) --------------------------------
        if ($state.PSObject.Properties['Infrastructure'] -and $state.Infrastructure.NATName) {
            $natName = $state.Infrastructure.NATName
            $liveNat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
            $checks += [PSCustomObject]@{
                PSTypeName = 'DLab.HealthCheck'
                Name       = 'NAT'
                Status     = if ($liveNat) { 'Healthy' } else { 'Degraded' }
                Message    = if ($liveNat) { "$natName ($($liveNat.InternalIPInterfaceAddressPrefix))" } else { "Missing: $natName" }
            }
        }

        # --- Check: storage folder ----------------------------------------
        $labDir = Get-DLabStorePath -Kind LabDir -LabName $labName
        $storageOk = Test-Path $labDir
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Lab storage folder'
            Status     = if ($storageOk) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($storageOk) { $labDir } else { "Not found: $labDir" }
        }

        # --- Per-VM health ------------------------------------------------
        $vmHealth = @()
        if ($state.VMs) {
            foreach ($entry in $state.VMs) {
                $vmHealth += Test-DLabVM -LabName $labName -Name $entry.Name -IncludeUpdateStatus:$IncludeUpdateStatus
            }
        }

        $vmUnhealthy = @($vmHealth | Where-Object OverallStatus -eq 'Unhealthy').Count
        $vmDegraded  = @($vmHealth | Where-Object OverallStatus -eq 'Degraded').Count
        $vmHealthy   = @($vmHealth | Where-Object OverallStatus -eq 'Healthy').Count
        $vmTotal     = $vmHealth.Count

        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'VM health aggregate'
            Status     = if ($vmUnhealthy -gt 0) { 'Unhealthy' } elseif ($vmDegraded -gt 0) { 'Degraded' } elseif ($vmTotal -eq 0) { 'Degraded' } else { 'Healthy' }
            Message    = "$vmHealthy healthy, $vmDegraded degraded, $vmUnhealthy unhealthy (of $vmTotal)"
        }

        # --- Roll up overall ---------------------------------------------
        $overall = 'Healthy'
        if ($checks.Status -contains 'Unhealthy')    { $overall = 'Unhealthy' }
        elseif ($checks.Status -contains 'Degraded') { $overall = 'Degraded' }

        [PSCustomObject]@{
            PSTypeName    = 'DLab.HealthStatus'
            Target        = $labName
            Timestamp     = Get-Date
            OverallStatus = $overall
            Checks        = $checks
            VMHealth      = $vmHealth
        }
    }
}
