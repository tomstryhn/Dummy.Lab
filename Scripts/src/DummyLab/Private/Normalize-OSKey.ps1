# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Normalize-OSKey {
    <#
    .SYNOPSIS
        Converts dashes to underscores in OS catalog keys.
        Users type WS2019-DC-CORE but PSD1 keys use WS2019_DC_CORE
        (PSD1 restricted language mode does not support quoted keys with dashes).
    .PARAMETER Key
        The OS key string to normalize.
    #>
    param([Parameter(Mandatory)][string]$Key)
    return $Key -replace '-', '_'
}
