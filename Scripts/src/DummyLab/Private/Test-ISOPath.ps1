# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-ISOPath {
    <#
    .SYNOPSIS
        Verifies an ISO file exists and is accessible.
    .PARAMETER Path
        Full path to the ISO file.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-ValidationResult -Check 'ISOPath' -Passed $false `
            -Message 'No ISO path specified.' `
            -Detail 'Use -ISO to specify a path directly, or run Find-DLabISO to list ISOs the catalog recognises.'
    }

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return New-ValidationResult -Check 'ISOPath' -Passed $false `
            -Message "ISO not found: $Path"
    }

    if ($Path -notmatch '\.iso$') {
        return New-ValidationResult -Check 'ISOPath' -Passed $false `
            -Message "File is not an ISO: $Path"
    }

    New-ValidationResult -Check 'ISOPath' -Passed $true -Message "ISO OK: $(Split-Path $Path -Leaf)"
}
