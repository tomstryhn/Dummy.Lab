# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Set-DLabInternet {
    <#
    .SYNOPSIS
        Enables or disables internet access for a lab.
    .DESCRIPTION
        Controls internet access by setting or removing the default gateway on
        the lab's DC and the DHCP Router option (Option 3) on the DHCP scope.

        When enabled:
          - DC gets a default route via its segment gateway (base+1).
          - DHCP Option 3 is set so clients receive the gateway on next renewal.
          - DNS forwarder is configured on the DC (so external names resolve).

        When disabled:
          - Default route is removed from the DC.
          - DHCP Option 3 is removed so clients lose their gateway on renewal.
          - Existing clients keep their current lease until it expires or they
            run ipconfig /renew / reboot.

        The DLab-NAT covers the full 10.74.18.0/23 supernet and is never
        touched by this cmdlet. Internet is controlled purely by whether VMs
        have a default gateway configured - without one, traffic never reaches
        the host NAT engine.
    .PARAMETER LabName
        Target lab. Defaults to LabName in DLab.Defaults.psd1.
    .PARAMETER Enabled
        $true to enable internet, $false to disable.
    .EXAMPLE
        Set-DLabInternet -LabName Demo -Enabled $true
    .EXAMPLE
        Set-DLabInternet -LabName Demo -Enabled $false
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Lab-only credentials - intentional plaintext for automation')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$LabName,

        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    begin {
        $cfg = Get-DLabConfigInternal
    }

    process {
        if (-not $LabName) {
            $LabName = [string]$cfg.LabName
            if (-not $LabName) { throw "LabName is required." }
        }

        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName
        if (-not (Test-Path $statePath)) {
            throw "Lab '$LabName' not found. Create it first with New-DLab."
        }
        $state = Read-LabState -Path $statePath

        $dcEntry = $state.VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
        if (-not $dcEntry) {
            throw "Lab '$LabName' has no DC recorded in state. Deploy the DC first."
        }

        $dcVMName = $dcEntry.Name
        $gateway  = $state.Network.Gateway        # segment base+1, always stored
        $scopeId  = $state.Network.NetworkBase     # 4-octet network address
        $netbios  = $state.DomainNetbios
        $dns      = $state.Network.DNSForwarder

        $action = if ($Enabled) { 'Enable' } else { 'Disable' }
        if (-not $PSCmdlet.ShouldProcess($LabName, "$action internet access")) { return }

        $domCred = New-Object PSCredential("$netbios\Administrator",
                       (ConvertTo-SecureString $cfg.AdminPassword -AsPlainText -Force))

        Write-LabLog "$action internet for lab '$LabName' (DC: $dcVMName)..." -Level Step

        if ($Enabled) {
            $null = Invoke-Command -VMName $dcVMName -Credential $domCred -ErrorAction Stop -ScriptBlock {
                param($Gateway, $ScopeId, $DNSForwarder)

                # Default route on DC
                $adapter = Get-NetAdapter |
                    Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' } |
                    Sort-Object ifIndex | Select-Object -First 1
                if ($adapter) {
                    $existing = Get-NetRoute -InterfaceIndex $adapter.ifIndex `
                                    -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
                    if (-not $existing) {
                        New-NetRoute -InterfaceIndex $adapter.ifIndex `
                                     -DestinationPrefix '0.0.0.0/0' `
                                     -NextHop $Gateway -RouteMetric 1 -ErrorAction Stop | Out-Null
                    }
                }

                # DHCP Option 3
                Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 3 `
                    -Value $Gateway -Force -ErrorAction Stop

                # DNS forwarder
                if ($DNSForwarder) {
                    try {
                        $existing = Get-DnsServerForwarder -ErrorAction SilentlyContinue
                        if ($existing.IPAddress -notcontains $DNSForwarder) {
                            Add-DnsServerForwarder -IPAddress $DNSForwarder -ErrorAction Stop | Out-Null
                        }
                    } catch { Write-Warning "Could not set DNS forwarder: $_" }
                }
            } -ArgumentList $gateway, $scopeId, $dns

        } else {
            $null = Invoke-Command -VMName $dcVMName -Credential $domCred -ErrorAction Stop -ScriptBlock {
                param($ScopeId)

                # Remove default route from DC
                Remove-NetRoute -DestinationPrefix '0.0.0.0/0' `
                    -Confirm:$false -ErrorAction SilentlyContinue

                # Remove DHCP Option 3
                try {
                    Remove-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 3 -ErrorAction Stop
                } catch { Write-Warning "Could not remove DHCP Option 3: $_" }
            } -ArgumentList $scopeId
        }

        # Update HasInternet in state
        $internetEnabled = $Enabled   # captured by the scriptblock closure
        $null = Update-LabStateLocked -Path $statePath -UpdateScript {
            param($s)
            if ($s.PSObject.Properties['HasInternet']) {
                $s.HasInternet = $internetEnabled
            } else {
                $s | Add-Member -NotePropertyName HasInternet -NotePropertyValue $internetEnabled -Force
            }
            $s
        }

        Write-LabLog "Internet $($action.ToLower())d for '$LabName'." -Level OK
        Write-LabLog "Note: existing DHCP clients need ipconfig /renew or a reboot to pick up the change." -Level Info
    }
}
