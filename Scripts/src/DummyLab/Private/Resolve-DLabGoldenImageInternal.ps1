# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Resolves a golden image for deployment. Accepts an explicit VHDX path (from
# -GoldenImage) or an OSKey and looks up the latest image via the legacy
# Get-LatestGoldenImage. Returns a hashtable shaped for the legacy deployment
# functions which expect { Path = <vhdx>; Entry = <catalog-entry> }.
#
# Wraps the legacy Resolve-GoldenImage but uses the config-aware image store
# path and OS catalog paths so it honors environment overrides.

function Resolve-DLabGoldenImageInternal {
    [CmdletBinding()]
    param(
        [string]$OSKey        = '',
        [string]$ExplicitPath = ''
    )

    $cfg = Get-DLabConfigInternal

    # Build catalog as a hashtable for the legacy Resolve-GoldenImage shape
    $catalog = @{}
    foreach ($entry in (Get-DLabCatalog)) {
        $catalog[$entry.OSKey] = @{
            DisplayName     = $entry.DisplayName
            GoldenPrefix    = $entry.GoldenPrefix
            EditionLabel    = $entry.EditionLabel
            DefaultMemoryGB = $entry.DefaultMemoryGB
            DefaultCPU      = $entry.DefaultCPU
            AliasFor        = $entry.AliasFor
        }
    }

    # 1. Normalise explicit OSKey (dash to underscore) and resolve aliases
    if ($OSKey) {
        $OSKey = $OSKey -replace '-', '_'
        if ($catalog.ContainsKey($OSKey) -and $catalog[$OSKey].AliasFor) {
            $OSKey = $catalog[$OSKey].AliasFor
        }
    }

    # 2. If the user supplied an explicit VHDX path but no OSKey, try to
    #    infer OSKey from the filename by matching against catalog prefixes.
    #    Use longest-prefix-wins so WS2016-DC-CORE wins over WS2016-DC.
    if (-not $OSKey -and $ExplicitPath) {
        $leaf = Split-Path $ExplicitPath -Leaf
        $bestPrefixLen = 0
        foreach ($k in $catalog.Keys) {
            $prefix = $catalog[$k].GoldenPrefix
            if (-not $prefix) { continue }
            if ($leaf.StartsWith($prefix) -and $prefix.Length -gt $bestPrefixLen) {
                $OSKey = $k
                $bestPrefixLen = $prefix.Length
            }
        }
    }

    # 3. Ultimate fallback: config's DefaultServerOS
    if (-not $OSKey) {
        $OSKey = $cfg.DefaultServerOS
    }

    $imageStore = Get-DLabStorePath -Kind Images
    $result = Resolve-GoldenImage -OSKey $OSKey -Catalog $catalog -ImageStorePath $imageStore -ExplicitPath $ExplicitPath

    # Surface the resolved OSKey so callers can pass it through to
    # Reserve-VMSlot and pipeline output without re-deriving it.
    if ($result) {
        $result['OSKey'] = $OSKey
    }
    return $result
}
