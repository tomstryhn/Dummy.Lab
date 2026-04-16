# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLabVMSlot {
    <#
    .SYNOPSIS
        Marks a VM slot as Failed, or removes the entry entirely.
    .DESCRIPTION
        Called when a deployment fails before VM creation completes, or to
        clean up orphaned state entries.

        By default, marks the slot status as 'Failed'. With -Force, removes
        the entry entirely from the state file.

        Uses file-locked state update for consistency. Silent by default.
    .PARAMETER LabName
        Lab name.
    .PARAMETER VMName
        Full VM name (e.g., Pipeline-DC01).
    .PARAMETER Force
        Remove the entry entirely rather than mark it as Failed.
    .EXAMPLE
        Remove-DLabVMSlot -LabName Pipeline -VMName Pipeline-SRV01
    .EXAMPLE
        Remove-DLabVMSlot -LabName Pipeline -VMName Pipeline-SRV01 -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$LabName,

        [Parameter(Mandatory, Position = 1)]
        [string]$VMName,

        [switch]$Force
    )

    process {
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName

        if (-not (Test-Path $statePath)) {
            Write-Error "Lab state not found: $statePath"
            return
        }

        $action = if ($Force) { 'Remove entry' } else { 'Mark as Failed' }
        if (-not $PSCmdlet.ShouldProcess($VMName, $action)) { return }

        try {
            if ($Force) {
                # Remove the entry entirely
                Update-LabStateLocked -Path $statePath -UpdateScript {
                    param($state)
                    $state.VMs = @($state.VMs | Where-Object { $_.Name -ne $VMName })
                    return $state
                } | Out-Null

                Write-DLabEvent -Level Ok -Source 'Remove-DLabVMSlot' `
                    -Message "Removed slot entry: $VMName" `
                    -Data @{ LabName = $LabName; VMName = $VMName; Action = 'Removed' }
            } else {
                Fail-VMSlot -StatePath $statePath -VMName $VMName

                Write-DLabEvent -Level Warn -Source 'Remove-DLabVMSlot' `
                    -Message "Marked slot as Failed: $VMName" `
                    -Data @{ LabName = $LabName; VMName = $VMName; Action = 'Failed' }
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'Remove-DLabVMSlot' `
                -Message "Failed to remove/mark slot: $($_.Exception.Message)" `
                -Data @{ LabName = $LabName; VMName = $VMName; Error = $_.Exception.Message }
            throw
        }
    }
}
