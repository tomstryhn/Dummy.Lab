# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabISOCatalog {
    <#
    .SYNOPSIS
        Returns WIM index information from ISOs in the ISO store.
    .DESCRIPTION
        Scans all ISOs in the configured storage directory and returns
        detailed WIM image information (build numbers, image names, sizes).
        Results are cached per-ISO to avoid repeated mounts.

        Emits typed DLab.ISOCatalog objects for each ISO found.
    .PARAMETER ForceRescan
        Ignore cached scan results and re-mount all ISOs.
    .EXAMPLE
        Get-DLabISOCatalog
    .EXAMPLE
        Get-DLabISOCatalog -ForceRescan | Where-Object { $_.BuildNumber -eq 26100 }
    #>
    [CmdletBinding()]
    [OutputType('DLab.ISOCatalog')]
    param(
        [switch]$ForceRescan
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
        $scanResults = @(Invoke-ISOScan -SearchPaths @($isoStorePath) `
                                       -CatalogEntries $editionCatalog `
                                       -ForceRescan:$ForceRescan)

        Write-DLabEvent -Level Info -Source 'Get-DLabISOCatalog' `
            -Message "Scanned $($scanResults.Count) ISO files" `
            -Data @{ Count = $scanResults.Count; Path = $isoStorePath }

        foreach ($scan in $scanResults) {
            [PSCustomObject]@{
                PSTypeName      = 'DLab.ISOCatalog'
                ISOPath         = $scan.ISOPath
                ISOName         = $scan.ISOName
                Identified      = $scan.Identified
                OSKey           = $scan.OSKey
                BuildNumber     = $scan.BuildNumber
                MatchedEditions = $scan.MatchedEditions
                WIMImages       = $scan.WIMImages
                Error           = $scan.Error
            } | Write-Output
        }
    }
}
