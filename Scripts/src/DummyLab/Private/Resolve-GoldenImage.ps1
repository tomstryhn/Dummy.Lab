# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Resolve-GoldenImage {
    <#
    .SYNOPSIS
        Resolves the golden image VHDX for a given OS key.
        If an explicit path is provided, validates it exists.
        Otherwise, finds the latest golden image by prefix in the image store.
    .PARAMETER OSKey
        The normalized OS catalog key (e.g. WS2025_DC).
    .PARAMETER Catalog
        The OS catalog hashtable (from OS.Catalog.psd1).
    .PARAMETER ImageStorePath
        Path to the golden images folder (e.g. C:\Dummy.Lab\GoldenImages).
    .PARAMETER ExplicitPath
        Optional explicit VHDX path. If provided, bypasses auto-resolve.
    .OUTPUTS
        Hashtable with Path and Entry keys, or $null on failure.
    #>
    param(
        [Parameter(Mandatory)][string]$OSKey,
        [Parameter(Mandatory)][hashtable]$Catalog,
        [Parameter(Mandatory)][string]$ImageStorePath,
        [string]$ExplicitPath = ''
    )

    if (-not $Catalog.ContainsKey($OSKey)) {
        Write-LabLog "Unknown OS '$OSKey'. Run Get-DLabCatalog to see valid keys." -Level Error
        return $null
    }
    $entry = $Catalog[$OSKey]

    if ($ExplicitPath) {
        # User specified a golden image - validate it exists
        if (-not (Test-Path $ExplicitPath)) {
            Write-LabLog "Golden image not found: $ExplicitPath" -Level Error
            return $null
        }
        Write-LabLog "Using specified golden image: $ExplicitPath" -Level Info
        return @{ Path = $ExplicitPath; Entry = $entry }
    }

    $image = Get-LatestGoldenImage -ImageStorePath $ImageStorePath -GoldenPrefix $entry.GoldenPrefix
    if (-not $image) {
        Write-LabLog "No golden image for '$OSKey'. Build one with: New-DLabGoldenImage -OSKey $OSKey" -Level Error
        return $null
    }
    return @{ Path = $image; Entry = $entry }
}

