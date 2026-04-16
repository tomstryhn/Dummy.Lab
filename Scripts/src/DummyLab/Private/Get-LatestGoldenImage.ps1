# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-LatestGoldenImage {
    <#
    .SYNOPSIS
        Returns the path to the latest golden image for a given OS.
    .DESCRIPTION
        Reads the pointer file (e.g. latest-WS2025-Datacenter.txt) in the Images folder.
        Falls back to finding the newest VHDX by filename pattern if no pointer exists.
    .PARAMETER ImageStorePath
        Full path to the Images folder (LabStorageRoot\Images\).
    .PARAMETER GoldenPrefix
        Golden image filename prefix from the OS catalog (e.g. 'WS2025-Datacenter').
    .OUTPUTS
        String - full path to the golden image VHDX, or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ImageStorePath,

        [Parameter(Mandatory)]
        [string]$GoldenPrefix
    )

    if (-not (Test-Path $ImageStorePath)) {
        return $null
    }

    # Try pointer file first
    $pointerFile = Join-Path $ImageStorePath "latest-${GoldenPrefix}.txt"
    if (Test-Path $pointerFile) {
        $pointerContent = (Get-Content $pointerFile -Raw).Trim()
        $targetPath = Join-Path $ImageStorePath $pointerContent
        if (Test-Path $targetPath) {
            return $targetPath
        }
        Write-Warning "Pointer file references missing image: $pointerContent"
    }

    # Fall back: find newest matching VHDX by name pattern
    # Post-filter ensures exact prefix match (next char after prefix-dash must be a digit,
    # so WS2019-DC- doesn't accidentally match WS2019-DC-CORE-)
    $pattern = "${GoldenPrefix}-*.vhdx"
    $escapedPrefix = [regex]::Escape($GoldenPrefix)
    $images = Get-ChildItem -Path $ImageStorePath -Filter $pattern -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match "^${escapedPrefix}-\d" } |
              Sort-Object Name -Descending
    if ($images) {
        return $images[0].FullName
    }

    return $null
}
