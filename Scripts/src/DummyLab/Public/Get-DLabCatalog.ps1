# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabCatalog {
    <#
    .SYNOPSIS
        Returns the OS catalog as an object.
    .DESCRIPTION
        Loads Scripts\Config\OS.Catalog.psd1 from the legacy location so 2.0
        cmdlets share the catalog with 1.0.x scripts. Catalog format unchanged.
    .EXAMPLE
        Get-DLabCatalog | Where-Object OSKey -match 'WS2025'
    #>
    [CmdletBinding()]
    param()

    # The catalog lives in the legacy Scripts\Config folder. Paths are resolved
    # relative to the loaded module location (assembled: ...\Scripts\Modules\DummyLab\;
    # from source: ...\Scripts\src\DummyLab\Public\).
    $candidates = @(
        (Join-Path $PSScriptRoot '..\..\Config\OS.Catalog.psd1'),     # assembled: ...\Modules\DummyLab\ -> ...\Scripts\Config\
        (Join-Path $PSScriptRoot '..\..\..\Config\OS.Catalog.psd1'),  # source dev: ...\src\DummyLab\Public\ -> ...\Scripts\Config\
        (Join-Path $PSScriptRoot 'OS.Catalog.psd1'),                  # bundled (future standalone distribution)
        (Join-Path $PSScriptRoot '..\Config\OS.Catalog.psd1')         # alternate source layout
    )
    $catalogPath = $null
    foreach ($c in $candidates) {
        $resolved = Resolve-Path -Path $c -ErrorAction SilentlyContinue
        if ($resolved) { $catalogPath = $resolved.Path; break }
    }
    if (-not $catalogPath) {
        Write-Warning "OS.Catalog.psd1 not found. Checked: $($candidates -join '; ')"
        return
    }

    $catalog = Import-PowerShellDataFile -Path $catalogPath
    foreach ($key in ($catalog.Keys | Sort-Object)) {
        $entry = $catalog[$key]
        if ($entry -isnot [hashtable]) { continue }

        $obj = [PSCustomObject]@{
            PSTypeName    = 'DLab.CatalogEntry'
            OSKey         = $key
            DisplayName   = if ($entry.ContainsKey('DisplayName')) { $entry.DisplayName } else { $key }
            AliasFor      = if ($entry.ContainsKey('AliasFor')) { $entry.AliasFor } else { $null }
            EditionLabel  = if ($entry.ContainsKey('EditionLabel')) { $entry.EditionLabel } else { $null }
            GoldenPrefix  = if ($entry.ContainsKey('GoldenPrefix')) { $entry.GoldenPrefix } else { $null }
            DefaultMemoryGB = if ($entry.ContainsKey('DefaultMemoryGB')) { $entry.DefaultMemoryGB } else { $null }
            DefaultCPU    = if ($entry.ContainsKey('DefaultCPU')) { $entry.DefaultCPU } else { $null }
        }
        $obj
    }
}
