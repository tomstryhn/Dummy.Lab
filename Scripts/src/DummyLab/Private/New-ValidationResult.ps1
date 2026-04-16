# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-ValidationResult {
    param(
        [bool]$Passed,
        [string]$Check,
        [string]$Message,
        [string]$Detail = ''
    )
    [PSCustomObject]@{
        Check   = $Check
        Passed  = $Passed
        Message = $Message
        Detail  = $Detail
    }
}
