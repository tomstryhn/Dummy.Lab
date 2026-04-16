# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabSwitch {
    <#
    .SYNOPSIS
        Creates a Hyper-V virtual switch with Dummy.Lab event emission.
    .DESCRIPTION
        Engineer-facing primitive that wraps the legacy New-LabSwitch logic.
        Useful when pre-creating network resources outside New-DLab's
        orchestration (e.g. shared switches across multiple labs, or custom
        switch types not produced by New-DLab).
    .PARAMETER Name
        Switch name.
    .PARAMETER SwitchType
        Internal (default), Private, or External.
    .EXAMPLE
        New-DLabSwitch -Name SharedInternal
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet('Internal', 'Private', 'External')][string]$SwitchType = 'Internal'
    )

    if (Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue) {
        Write-Warning "Switch '$Name' already exists."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Create $SwitchType switch")) { return }

    Write-DLabEvent -Level Step -Source 'New-DLabSwitch' -Message "Creating $SwitchType switch '$Name'"
    try {
        New-VMSwitch -Name $Name -SwitchType $SwitchType -ErrorAction Stop | Out-Null
        Write-DLabEvent -Level Ok -Source 'New-DLabSwitch' -Message "Switch '$Name' created"
    } catch {
        Write-DLabEvent -Level Error -Source 'New-DLabSwitch' -Message "Failed: $($_.Exception.Message)"
        throw
    }
}
