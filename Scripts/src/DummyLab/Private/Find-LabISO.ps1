# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Find-LabISO {
    <#
    .SYNOPSIS
        Finds an ISO matching an OS catalog entry by reading cached WIM metadata.
    .DESCRIPTION
        Uses Invoke-ISOScan (with caching) to find ISOs matching the requested
        edition. Returns the ISO path and resolved WIM image index.

        If no cache exists, Invoke-ISOScan will mount and scan the ISOs
        (creating cache for future calls). Subsequent calls are fast.

    .PARAMETER CatalogKey
        The catalog key to match (e.g. 'WS2019_DC').
    .PARAMETER CatalogEntry
        Hashtable from OS.Catalog.psd1 for the requested edition.
    .PARAMETER CatalogEntries
        Full catalog hashtable (editions only, no aliases) for Invoke-ISOScan.
    .PARAMETER SearchPaths
        Array of folder paths to search recursively for .iso files.
    .OUTPUTS
        PSCustomObject with Path and ImageIndex, or $null if no match found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CatalogKey,

        [Parameter(Mandatory)]
        [hashtable]$CatalogEntry,

        [Parameter(Mandatory)]
        [hashtable]$CatalogEntries,

        [string[]]$SearchPaths = @()
    )

    # Use Invoke-ISOScan (reads from cache if available, mounts only if needed)
    $scanResults = @(Invoke-ISOScan -SearchPaths $SearchPaths -CatalogEntries $CatalogEntries)

    # Find an ISO that has our specific edition
    foreach ($scan in $scanResults) {
        if ($scan.Error) { continue }
        $edMatch = $scan.MatchedEditions | Where-Object { $_.Key -eq $CatalogKey } | Select-Object -First 1
        if ($edMatch) {
            return [PSCustomObject]@{
                Path       = $scan.ISOPath
                ImageIndex = $edMatch.WIMIndex
            }
        }
    }

    return $null
}
