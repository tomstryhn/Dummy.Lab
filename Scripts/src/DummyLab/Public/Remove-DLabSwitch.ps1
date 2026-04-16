# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLabSwitch {
    <#
    .SYNOPSIS
        Removes a Hyper-V virtual switch with event emission.
    .DESCRIPTION
        Engineer-facing primitive for tearing down switches outside
        Remove-DLab orchestration. Use with care; switches backing active
        VMs will refuse removal.
    .PARAMETER Name
        Switch name.
    .EXAMPLE
        Remove-DLabSwitch -Name SharedInternal -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('SwitchName')][string]$Name
    )
    process {
        if (-not (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue)) {
            Write-Warning "Switch '$Name' does not exist."
            return
        }
        if (-not $PSCmdlet.ShouldProcess($Name, 'Remove virtual switch')) { return }

        Write-DLabEvent -Level Step -Source 'Remove-DLabSwitch' -Message "Removing switch '$Name'"
        try {
            Remove-VMSwitch -Name $Name -Force -ErrorAction Stop | Out-Null
            Write-DLabEvent -Level Ok -Source 'Remove-DLabSwitch' -Message "Switch '$Name' removed"
        } catch {
            Write-DLabEvent -Level Error -Source 'Remove-DLabSwitch' -Message "Failed: $($_.Exception.Message)"
            throw
        }
    }
}
