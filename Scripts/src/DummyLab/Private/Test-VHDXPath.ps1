# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-VHDXPath {
    <#
    .SYNOPSIS
        Verifies a VHDX file exists and is accessible.
    .PARAMETER Path
        Full path to the VHDX file.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return New-ValidationResult -Check 'VHDXPath' -Passed $false `
            -Message 'No VHDX path specified.'
    }

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return New-ValidationResult -Check 'VHDXPath' -Passed $false `
            -Message "VHDX not found: $Path"
    }

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Close()
    } catch {
        return New-ValidationResult -Check 'VHDXPath' -Passed $false `
            -Message "VHDX is locked or inaccessible: $Path" `
            -Detail $_.Exception.Message
    }

    New-ValidationResult -Check 'VHDXPath' -Passed $true -Message "VHDX OK: $(Split-Path $Path -Leaf)"
}
