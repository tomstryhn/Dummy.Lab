# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-SwitchNameConflict {
    <#
    .SYNOPSIS
        Checks if a Hyper-V virtual switch with the planned name already exists.
    .PARAMETER SwitchName
        The planned switch name.
    .PARAMETER AllowReuse
        If true, an existing Internal switch is accepted (returns Passed=$true with note).
    #>
    param(
        [string]$SwitchName,
        [bool]$AllowReuse = $true
    )

    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $existing) {
        return New-ValidationResult -Check 'SwitchNameConflict' -Passed $true `
            -Message "Switch name '$SwitchName' is available."
    }

    if ($AllowReuse -and $existing.SwitchType -eq 'Internal') {
        return New-ValidationResult -Check 'SwitchNameConflict' -Passed $true `
            -Message "Switch '$SwitchName' already exists (Internal) - will be reused." `
            -Detail 'Existing VMs on this switch may share the lab network.'
    }

    New-ValidationResult -Check 'SwitchNameConflict' -Passed $false `
        -Message "Switch '$SwitchName' exists (type: $($existing.SwitchType)) and cannot be safely reused." `
        -Detail 'Choose a different -LabName or remove the existing switch.'
}
