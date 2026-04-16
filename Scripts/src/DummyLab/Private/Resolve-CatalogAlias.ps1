# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Resolve-CatalogAlias {
    <#
    .SYNOPSIS
        Resolves alias entries in the OS catalog. Keys with AliasFor point to another key.
        e.g. WS2025 -> WS2025_DC.
    .PARAMETER Key
        The OS key to resolve.
    .PARAMETER Catalog
        The OS catalog hashtable.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][hashtable]$Catalog
    )
    $resolved = $Key
    if ($Catalog.ContainsKey($resolved) -and $Catalog[$resolved].ContainsKey('AliasFor')) {
        $resolved = $Catalog[$resolved].AliasFor
    }
    return $resolved
}
