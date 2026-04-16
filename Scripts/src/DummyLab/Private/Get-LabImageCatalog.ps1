# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-LabImageCatalog {
    <#
    .SYNOPSIS
        Scans the Images folder and returns available golden images with catalog metadata.
    .DESCRIPTION
        Discovers actual .vhdx files in the Images folder and scans available ISOs
        by reading their WIM metadata. Returns a combined view showing what's built
        (Ready), what can be built (Buildable), and what's missing (NoISO).

        Edition-aware: multiple catalog entries with the same BuildNumber each get
        their own status based on whether a matching WIM image exists in the ISO.

    .PARAMETER ImageStorePath
        Full path to the Images folder (LabStorageRoot\Images\).
    .PARAMETER CatalogEntries
        Hashtable from OS.Catalog.psd1 (excluding alias entries).
    .PARAMETER ISOSearchPaths
        Paths to search for ISOs (to determine what's buildable).
    .OUTPUTS
        Array of [PSCustomObject] with:
            Key, DisplayName, Status, GoldenImage, ImageName, SizeGB,
            ISOPath, ISOName, CatalogEntry
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ImageStorePath,

        [Parameter(Mandatory)]
        [hashtable]$CatalogEntries,

        [string[]]$ISOSearchPaths = @()
    )

    # Scan all available ISOs
    $scanResults = @(Invoke-ISOScan -SearchPaths $ISOSearchPaths -CatalogEntries $CatalogEntries)

    $results = @()

    foreach ($key in $CatalogEntries.Keys | Sort-Object) {
        $entry = $CatalogEntries[$key]

        # Check for existing golden image
        $goldenImage = $null
        if (Test-Path $ImageStorePath) {
            $goldenImage = Get-LatestGoldenImage -ImageStorePath $ImageStorePath -GoldenPrefix $entry.GoldenPrefix
        }

        # Find matching ISO from scan results using MatchedEditions
        $isoPath = $null
        $isoName = $null
        if ($scanResults.Count -gt 0) {
            foreach ($scan in $scanResults) {
                if ($scan.Error) { continue }
                $edMatch = $scan.MatchedEditions | Where-Object { $_.Key -eq $key } | Select-Object -First 1
                if ($edMatch) {
                    $isoPath = $scan.ISOPath
                    $isoName = $scan.ISOName
                    break
                }
            }
        }

        $status = if ($goldenImage) {
            'Ready'
        } elseif ($isoPath) {
            'Buildable'
        } else {
            'NoISO'
        }

        $sizeGB = if ($goldenImage) {
            [math]::Round((Get-Item $goldenImage).Length / 1GB, 2)
        } else { 0 }

        $results += [PSCustomObject]@{
            Key          = $key
            DisplayName  = $entry.DisplayName
            Status       = $status
            GoldenImage  = $goldenImage
            ImageName    = if ($goldenImage) { Split-Path $goldenImage -Leaf } else { $null }
            SizeGB       = $sizeGB
            ISOPath      = $isoPath
            ISOName      = $isoName
            CatalogEntry = $entry
        }
    }

    return $results
}
