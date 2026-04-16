# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Find-DLabISO {
    <#
    .SYNOPSIS
        Locates an ISO file in the configured ISO store by catalog key.
    .DESCRIPTION
        Scans the ISO storage directory for .iso files and uses WIM catalog
        metadata to identify matching editions. Supports optional -OSKey filter
        to narrow results.

        This is a thin wrapper over Find-LabISO (private helper) that handles
        path resolution and event emission.
    .PARAMETER OSKey
        Optional OS catalog key filter (e.g., 'WS2025_DC', 'WS2019_STD').
        If omitted, returns all recognized ISOs.
    .EXAMPLE
        Find-DLabISO -OSKey WS2025_DC
    .EXAMPLE
        Find-DLabISO | Select-Object ISOPath, OSKey
    #>
    [CmdletBinding()]
    [OutputType('DLab.ISOInfo')]
    param(
        [string]$OSKey
    )

    process {
        $cfg = Get-DLabConfigInternal
        $isoStorePath = Join-Path $cfg.LabStorageRoot $cfg.ISOFolderName

        if (-not (Test-Path $isoStorePath)) {
            Write-Error "ISO store path not found: $isoStorePath"
            return
        }

        # Load raw catalog — Invoke-ISOScan needs the raw hashtable with
        # BuildNumber/WIMImageName/etc., not the projected PSCustomObject
        # that Get-DLabCatalog returns.
        $installRoot = Get-DLabStorePath -Kind Root
        $catalogPath = Join-Path $installRoot 'Scripts\Config\OS.Catalog.psd1'
        if (-not (Test-Path $catalogPath)) {
            Write-Error "OS catalog not found: $catalogPath"
            return
        }
        $rawCatalog = Import-PowerShellDataFile -Path $catalogPath
        $editionCatalog = @{}
        foreach ($k in $rawCatalog.Keys) {
            if (-not $rawCatalog[$k].ContainsKey('AliasFor')) {
                $editionCatalog[$k] = $rawCatalog[$k]
            }
        }

        # Scan ISOs
        $scanResults = @(Invoke-ISOScan -SearchPaths @($isoStorePath) -CatalogEntries $editionCatalog)

        # Filter and emit results
        foreach ($scan in $scanResults) {
            if ($scan.Error) {
                Write-DLabEvent -Level Warn -Source 'Find-DLabISO' `
                    -Message "ISO scan error: $($scan.ISOPath) - $($scan.Error)"
                continue
            }

            if (-not $scan.Identified) {
                Write-DLabEvent -Level Info -Source 'Find-DLabISO' `
                    -Message "ISO not identified: $($scan.ISOName)"
                continue
            }

            # If -OSKey filter is specified, only emit matching editions
            $matchingEditions = if ($OSKey) {
                @($scan.MatchedEditions | Where-Object { $_.Key -eq $OSKey })
            } else {
                $scan.MatchedEditions
            }

            foreach ($edition in $matchingEditions) {
                [PSCustomObject]@{
                    PSTypeName = 'DLab.ISOInfo'
                    ISOPath    = $scan.ISOPath
                    ISOName    = $scan.ISOName
                    OSKey      = $edition.Key
                    WIMIndex   = $edition.WIMIndex
                } | Write-Output
            }
        }

        Write-DLabEvent -Level Info -Source 'Find-DLabISO' `
            -Message "ISO search complete in $isoStorePath" `
            -Data @{ SearchPath = $isoStorePath; Filter = $OSKey }
    }
}
