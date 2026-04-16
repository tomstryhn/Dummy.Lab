# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Write-LabState {
    <#
    .SYNOPSIS
        Serializes a lab state object to JSON and writes it to disk.
    .PARAMETER State
        The lab state PSCustomObject.
    .PARAMETER Path
        Full path to lab.state.json.
    #>
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Path
    )
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}
