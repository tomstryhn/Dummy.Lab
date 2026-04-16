# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Coalesce {
    <#
    .SYNOPSIS
        Returns the first non-empty, non-null value. Used for config default resolution.
    .PARAMETER a
        Primary value (user-supplied or explicit).
    .PARAMETER b
        Fallback value (config default).
    #>
    param($a, $b)
    if ($null -ne $a -and $a -ne '' -and ($a -ne 0 -or $b -eq 0)) { $a } else { $b }
}
