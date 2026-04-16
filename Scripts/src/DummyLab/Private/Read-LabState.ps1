# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Read-LabState {
    <#
    .SYNOPSIS
        Loads a lab state from its JSON file.
    .PARAMETER Path
        Full path to lab.state.json.
    .OUTPUTS
        PSCustomObject with lab state, or $null if file does not exist.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        return Get-Content $Path -Raw | ConvertFrom-Json
    }
    return $null
}
