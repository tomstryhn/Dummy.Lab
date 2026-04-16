# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Complete-DLabVMSlot {
    <#
    .SYNOPSIS
        Marks a reserved VM slot as Ready after successful deployment.
    .DESCRIPTION
        Updates the VM state from 'Deploying' to 'Ready' in the lab state file.
        Called after the VM has been created and configured successfully.

        Uses file-locked state update to ensure consistency. Silent by default.
    .PARAMETER LabName
        Lab name.
    .PARAMETER VMName
        Full VM name (e.g., Pipeline-DC01).
    .EXAMPLE
        Complete-DLabVMSlot -LabName Pipeline -VMName Pipeline-DC01
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$LabName,

        [Parameter(Mandatory, Position = 1)]
        [string]$VMName
    )

    process {
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName

        if (-not (Test-Path $statePath)) {
            Write-Error "Lab state not found: $statePath"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($VMName, 'Mark as Ready')) { return }

        try {
            Complete-VMSlot -StatePath $statePath -VMName $VMName

            Write-DLabEvent -Level Ok -Source 'Complete-DLabVMSlot' `
                -Message "Marked $VMName as Ready" `
                -Data @{ LabName = $LabName; VMName = $VMName }
        } catch {
            Write-DLabEvent -Level Error -Source 'Complete-DLabVMSlot' `
                -Message "Failed to mark slot as Ready: $($_.Exception.Message)" `
                -Data @{ LabName = $LabName; VMName = $VMName; Error = $_.Exception.Message }
            throw
        }
    }
}
