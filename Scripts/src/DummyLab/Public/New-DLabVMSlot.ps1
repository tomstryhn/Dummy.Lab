# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabVMSlot {
    <#
    .SYNOPSIS
        Reserves a VM name and IP address atomically in the lab state.
    .DESCRIPTION
        Atomically reserves a VM slot in the lab state file before deployment.
        Ensures that parallel deployments do not collide on VM names or IPs.

        IP allocation is segment-based: the /27 segment and next-octet counters
        are read from the lab state, so no NetworkBase parameter is required.
        Wraps the private Reserve-VMSlot helper.
    .PARAMETER LabName
        Lab name.
    .PARAMETER Role
        VM role: DC or Server.
    .PARAMETER RequestedName
        Optional short name (e.g., SRV01). Auto-generated as SRV01, SRV02, etc.
        if omitted.
    .PARAMETER OSKey
        OS catalog key (e.g., WS2025_DC).
    .EXAMPLE
        New-DLabVMSlot -LabName Pipeline -Role DC -OSKey WS2025_DC
    .EXAMPLE
        New-DLabVMSlot -LabName Pipeline -Role Server -RequestedName SRV01 -OSKey WS2025_STD -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('System.Management.Automation.PSCustomObject')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$LabName,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('DC', 'Server')]
        [string]$Role,

        [Parameter(Mandatory, Position = 2)]
        [string]$OSKey,

        [string]$RequestedName = '',

        [switch]$PassThru
    )

    process {
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName

        if (-not (Test-Path $statePath)) {
            Write-Error "Lab state not found: $statePath"
            return
        }

        if (-not $PSCmdlet.ShouldProcess("$LabName : $Role VM", 'Reserve slot')) { return }

        try {
            $slot = Reserve-VMSlot -StatePath $statePath `
                                   -Role $Role `
                                   -RequestedName $RequestedName `
                                   -OSKey $OSKey `
                                   -LabName $LabName

            Write-DLabEvent -Level Ok -Source 'New-DLabVMSlot' `
                -Message "Reserved slot: $($slot.VMName) ($($slot.IP))" `
                -Data @{ LabName = $LabName; VMName = $slot.VMName; IP = $slot.IP; Role = $Role }

            if ($PassThru) {
                $slot | Write-Output
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'New-DLabVMSlot' `
                -Message "Failed to reserve slot: $($_.Exception.Message)" `
                -Data @{ LabName = $LabName; Role = $Role; Error = $_.Exception.Message }
            throw
        }
    }
}
