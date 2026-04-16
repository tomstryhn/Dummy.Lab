# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 1 of the golden-image build: Plan.
#
# Inputs come from New-DLabGoldenImage parameters. Output is a DLab.GoldenImagePlan
# object that every subsequent phase consumes. Defaults come from
# Get-DLabConfig (single source of truth, honours user overrides via
# %APPDATA%\DummyLab\config.psd1 or $env:DUMMYLAB_CONFIG). OS catalog comes
# from OS.Catalog.psd1 which is loaded directly because the build path
# needs the raw hashtable (aliases + ContainsKey lookups), not the
# projected collection that Get-DLabCatalog returns.
#
# If an image for this OS + patch status already exists for today, the plan
# is returned with Skip=$true and VHDXPath pointing at the existing file.
# The orchestrator treats this as a non-fatal short-circuit.

function Resolve-GoldenImagePlan {
    [CmdletBinding()]
    [OutputType('DLab.GoldenImagePlan')]
    param(
        [Parameter(Mandatory)][string]$OSKey,
        [string]$ISO = '',
        [switch]$SkipUpdates,
        [int]$ImageIndex = 0
    )

    # Merged defaults (bundled DLab.Defaults.psd1 + user overrides + env).
    $cfg = Get-DLabConfig -Refresh

    # OS catalog: loaded direct from the canonical path because the build
    # path needs alias resolution and ContainsKey on the raw hashtable.
    $installRoot = Get-DLabStorePath -Kind Root
    $scriptsPath = Join-Path $installRoot 'Scripts'
    $catalogPath = Join-Path $scriptsPath 'Config\OS.Catalog.psd1'
    if (-not (Test-Path $catalogPath)) {
        throw "OS catalog not found at $catalogPath."
    }
    $catalog = Import-PowerShellDataFile -Path $catalogPath

    # Catalog entries that are real editions (not aliases).
    $catalogEditions = @{}
    foreach ($k in $catalog.Keys) {
        if (-not $catalog[$k].ContainsKey('AliasFor')) {
            $catalogEditions[$k] = $catalog[$k]
        }
    }

    # Resolve OS key: normalize dashes to underscores, resolve aliases.
    $resolvedKey = Normalize-OSKey -Key $OSKey
    $resolvedKey = Resolve-CatalogAlias -Key $resolvedKey -Catalog $catalog

    if (-not $catalog.ContainsKey($resolvedKey)) {
        $validKeys = ($catalog.Keys | Sort-Object) -join ', '
        throw "Unknown OS key '$OSKey'. Valid keys: $validKeys."
    }

    $osEntry = $catalog[$resolvedKey]
    if ($osEntry.ContainsKey('AliasFor')) {
        throw "'$resolvedKey' is still an alias after resolution. Catalog is inconsistent."
    }

    # Merge runtime settings.
    $installUpdates = -not $SkipUpdates.IsPresent -and [bool]$cfg.InstallUpdates
    $updateTimeout  = if ($cfg.PSObject.Properties['UpdateTimeoutMin']) { [int]$cfg.UpdateTimeoutMin } else { 60 }
    $storageRoot    = $cfg.LabStorageRoot
    $imageStorePath = Join-Path $storageRoot $cfg.ImageStoreName
    $isoFolderName  = if ($cfg.PSObject.Properties['ISOFolderName']) { [string]$cfg.ISOFolderName } else { 'ISOs' }
    $extraISOPaths  = if ($cfg.PSObject.Properties['ExtraISOPaths']) { @($cfg.ExtraISOPaths) }       else { @() }
    $guestPath      = Join-Path $scriptsPath 'GuestScripts'
    $unattendPath   = Join-Path $scriptsPath 'Config\unattend-server.xml'

    # Locale: 'auto' means detect from host.
    $timeZone     = $cfg.TimeZone
    $inputLocale  = $cfg.InputLocale
    $userLocale   = $cfg.UserLocale
    $systemLocale = $cfg.SystemLocale
    if ($timeZone    -eq 'auto') { $timeZone = (Get-TimeZone).Id }
    if ($inputLocale -eq 'auto') {
        $hostLang = Get-WinUserLanguageList | Select-Object -First 1
        if ($hostLang -and $hostLang.InputMethodTips) {
            $inputLocale = $hostLang.InputMethodTips[0]
        } else {
            $inputLocale = (Get-Culture).Name
        }
    }
    if ($userLocale   -eq 'auto') { $userLocale   = (Get-Culture).Name }
    if ($systemLocale -eq 'auto') { $systemLocale = 'en-US' }

    # ISO resolution: explicit path wins, otherwise auto-discover via WIM scan.
    $isoPath            = $ISO
    $resolvedImageIndex = if ($ImageIndex -gt 0) { $ImageIndex } else { $osEntry.ImageIndex }
    if (-not $isoPath) {
        $isoFolder   = Join-Path $storageRoot $isoFolderName
        $searchPaths = @($isoFolder) + @($extraISOPaths)
        if (-not (Test-Path $isoFolder)) {
            New-Item -ItemType Directory -Path $isoFolder -Force | Out-Null
        }
        $isoMatch = Find-LabISO -CatalogKey $resolvedKey -CatalogEntry $osEntry `
                                -CatalogEntries $catalogEditions -SearchPaths $searchPaths
        if ($isoMatch) {
            $isoPath            = $isoMatch.Path
            $resolvedImageIndex = $isoMatch.ImageIndex
        } else {
            throw "No ISO found for '$resolvedKey'. Place a matching ISO in '$isoFolder' or pass -ISO."
        }
    }

    # Naming and paths.
    $dateStamp   = Get-Date -Format 'yyyy.MM.dd'
    $patchSuffix = if ($installUpdates) { '' } else { '-unpatched' }
    $imageName   = "$($osEntry.GoldenPrefix)-${dateStamp}${patchSuffix}"
    $vhdxPath    = Join-Path $imageStorePath "${imageName}.vhdx"

    # Ensure the image store exists before we plan a path inside it.
    if (-not (Test-Path $imageStorePath)) {
        New-Item -ItemType Directory -Path $imageStorePath -Force | Out-Null
    }

    # Short-circuit: image already built today.
    $skip = $false
    $skipReason = $null
    if (Test-Path $vhdxPath) {
        $skip = $true
        $skipReason = 'AlreadyExists'
    }

    [pscustomobject]@{
        PSTypeName       = 'DLab.GoldenImagePlan'
        OSKey            = $resolvedKey
        OSEntry          = $osEntry
        Catalog          = $catalog
        Defaults         = $cfg
        ISOPath          = $isoPath
        ImageIndex       = $resolvedImageIndex
        ImageName        = $imageName
        PatchSuffix      = $patchSuffix
        ImageStorePath   = $imageStorePath
        VHDXPath         = $vhdxPath
        UnattendPath     = $unattendPath
        GuestPath        = $guestPath
        AdminPassword    = $cfg.AdminPassword
        TimeZone         = $timeZone
        InputLocale      = $inputLocale
        UserLocale       = $userLocale
        SystemLocale     = $systemLocale
        InstallUpdates   = $installUpdates
        UpdateTimeoutMin = $updateTimeout
        VHDXSizeGB       = [int]$cfg.VHDXSizeGB
        TempVMName       = "GoldenBuild-${resolvedKey}-temp"
        # Shared infrastructure — DLab-Internal and DLab-NAT are created once by
        # Ensure-DLabSharedInfrastructure and used by all builds and labs.
        TempSwitchName   = 'DLab-Internal'
        TempNatName      = 'DLab-NAT'
        # Staging segment (segment 0): 10.74.18.0/27
        TempNetBase      = '10.74.18'
        TempGateway      = '10.74.18.1'
        TempVMIP         = '10.74.18.2'
        TempSubnet       = '10.74.18.0/23'    # NAT covers the full supernet
        TempVMIPPrefix   = 27                  # guest NIC prefix for the staging /27
        BuildStart       = Get-Date
        Skip             = $skip
        SkipReason       = $skipReason
    }
}
