# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabGoldenImage {
    <#
    .SYNOPSIS
        Lists available golden images in the image store.
    .DESCRIPTION
        Enumerates VHDX files in the GoldenImages folder and projects them as
        DLab.GoldenImage objects. Cross-references the OS catalog to populate
        OSKey and OSName. Detects pointer files (latest-*.txt) so pipeline
        consumers can identify which image the auto-resolver will pick.

        Live-off-the-land: this wraps Get-ChildItem plus Get-Content for the
        pointer files. No custom VHDX inspection needed at this layer.
    .PARAMETER OSKey
        Filter to a specific OS catalog key (e.g. WS2025_DC).
    .PARAMETER Name
        Filter by image file name (supports wildcards).
    .PARAMETER OnlyProtected
        Return only images that have read-only protection applied.
    .EXAMPLE
        Get-DLabGoldenImage
    .EXAMPLE
        Get-DLabGoldenImage -OSKey WS2025_DC | Sort-Object BuildDate -Descending | Select -First 1
    .EXAMPLE
        Get-DLabGoldenImage | Where-Object { -not $_.Patched }
    #>
    [CmdletBinding()]
    [OutputType('DLab.GoldenImage')]
    param(
        [string]$OSKey,
        [string]$Name,
        [switch]$OnlyProtected
    )

    $imageStore = Get-DLabStorePath -Kind Images
    if (-not (Test-Path $imageStore)) {
        Write-Verbose "Image store not present: $imageStore"
        return
    }

    # Build catalog lookup once
    $catalog = @{}
    try {
        foreach ($entry in (Get-DLabCatalog)) {
            $catalog[$entry.OSKey] = @{
                DisplayName     = $entry.DisplayName
                GoldenPrefix    = $entry.GoldenPrefix
                EditionLabel    = $entry.EditionLabel
                DefaultMemoryGB = $entry.DefaultMemoryGB
                DefaultCPU      = $entry.DefaultCPU
            }
        }
    } catch {
        Write-Verbose "Catalog unavailable: $($_.Exception.Message)"
    }

    # Map pointer files (latest-<prefix>.txt -> image filename)
    $pointers = @{}
    Get-ChildItem -Path $imageStore -Filter 'latest-*.txt' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $target = (Get-Content -Path $_.FullName -Raw -ErrorAction Stop).Trim()
                if ($target) { $pointers[$target] = $_.FullName }
            } catch { }
        }

    $files = Get-ChildItem -Path $imageStore -Filter '*.vhdx' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $pointerPath = if ($pointers.ContainsKey($f.Name)) { $pointers[$f.Name] } else { '' }
        $obj = New-DLabGoldenImageObject -File $f -Catalog $catalog -PointerPath $pointerPath

        if ($OSKey -and $obj.OSKey -ne $OSKey) { continue }
        if ($Name  -and $obj.ImageName -notlike $Name) { continue }
        if ($OnlyProtected -and -not $obj.Protected)   { continue }

        $obj
    }
}
