# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Invoke-ISOScan {
    <#
    .SYNOPSIS
        Scans ISO files and reads WIM metadata to identify Windows Server versions.
    .DESCRIPTION
        Mounts each ISO file and reads Get-WindowsImage output to extract version,
        build number, and available WIM images. Matches against catalog entries to
        identify available editions.

        Supports per-ISO caching: scan results are stored as JSON files in a
        .scan-cache folder next to the ISOs. Cache is valid when the ISO file
        size and last-modified date match. Use -ForceRescan to ignore cache.

        With edition-aware catalogs, a single ISO can match multiple edition keys
        (e.g. WS2019_DC, WS2019_DC_CORE, WS2019_STD, WS2019_STD_CORE).

    .PARAMETER SearchPaths
        Array of folder paths to search recursively for .iso files.
    .PARAMETER CatalogEntries
        Hashtable from OS.Catalog.psd1 (excluding alias entries).
    .PARAMETER ForceRescan
        If set, ignores cache and re-mounts all ISOs.
    .OUTPUTS
        Array of [PSCustomObject] with properties:
            ISOPath, ISOName, Identified, OSKey, MatchedEditions,
            BuildNumber, WIMImages, Error
    #>
    param(
        [string[]]$SearchPaths = @(),
        [hashtable]$CatalogEntries = @{},
        [switch]$ForceRescan
    )

    if ($SearchPaths.Count -eq 0) {
        $SearchPaths = @((Get-Location).Path)
    }

    # Collect all ISO files
    $allISOs = @()
    foreach ($path in $SearchPaths) {
        if (-not $path -or -not (Test-Path $path)) { continue }
        $allISOs += @(Get-ChildItem -Path $path -Filter '*.iso' -Recurse -ErrorAction SilentlyContinue)
    }

    $results = @()

    foreach ($isoFile in $allISOs) {
        $isoPath = $isoFile.FullName
        $isoName = $isoFile.Name

        # Try reading from cache first (unless forced rescan)
        $cachedData = $null
        if (-not $ForceRescan) {
            $cachedData = Read-ISOScanCache -ISOFile $isoFile
        }

        if ($cachedData) {
            # Rebuild result from cache - re-match against current catalog
            $wimImageList = @($cachedData.WIMImages | ForEach-Object {
                [PSCustomObject]@{
                    Index       = [int]$_.Index
                    Name        = $_.Name
                    Description = $_.Description
                    SizeBytes   = [long]$_.SizeBytes
                }
            })

            $buildNumber = $cachedData.BuildNumber
            $matchedEditions = @(Resolve-EditionMatches -BuildNumber $buildNumber `
                -WIMImages $wimImageList -CatalogEntries $CatalogEntries)

            $primaryKey = if ($matchedEditions.Count -gt 0) { $matchedEditions[0].Key } else { $null }

            $results += [PSCustomObject]@{
                ISOPath         = $isoPath
                ISOName         = $isoName
                Identified      = ($matchedEditions.Count -gt 0)
                OSKey           = $primaryKey
                MatchedEditions = $matchedEditions
                BuildNumber     = $buildNumber
                WIMImages       = $wimImageList
                Error           = ''
            }
            continue
        }

        # No valid cache - mount and scan the ISO
        $mountResult = $null
        $wimImageList = @()
        $buildNumber = $null
        $scanError = $null
        $matchedEditions = @()

        # Stop ShellHWDetection before mounting so Windows never fires AutoPlay.
        # The service is always restarted in the finally block.
        $shellHW = Get-Service ShellHWDetection -ErrorAction SilentlyContinue
        $shellHWWasRunning = $shellHW -and $shellHW.Status -eq 'Running'
        if ($shellHWWasRunning) {
            Stop-Service ShellHWDetection -Force -ErrorAction SilentlyContinue
        }

        try {
            $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction SilentlyContinue
            if (-not $mountResult) {
                $scanError = "Failed to mount ISO"
            } else {
                $volume = $mountResult | Get-Volume -ErrorAction SilentlyContinue
                if (-not $volume -or -not $volume.DriveLetter) {
                    $scanError = "Failed to get drive letter from mounted ISO"
                } else {
                    $driveLetter = $volume.DriveLetter

                    $wimPath = "${driveLetter}:\sources\install.wim"
                    $esdPath = "${driveLetter}:\sources\install.esd"

                    $imagePath = $null
                    if (Test-Path $wimPath) {
                        $imagePath = $wimPath
                    } elseif (Test-Path $esdPath) {
                        $imagePath = $esdPath
                    }

                    if (-not $imagePath) {
                        $scanError = "install.wim or install.esd not found in ISO"
                    } else {
                        try {
                            $rawImages = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop)

                            if ($rawImages.Count -eq 0) {
                                $scanError = "No images found in WIM file"
                            } else {
                                $wimImageList = @($rawImages | ForEach-Object {
                                    [PSCustomObject]@{
                                        Index       = $_.ImageIndex
                                        Name        = $_.ImageName
                                        Description = $_.ImageDescription
                                        SizeBytes   = $_.ImageSize
                                    }
                                })

                                $detail = Get-WindowsImage -ImagePath $imagePath `
                                    -Index $rawImages[0].ImageIndex -ErrorAction Stop

                                if ($detail.Version -match '^\d+\.\d+\.(\d+)\.\d+$') {
                                    $buildNumber = $matches[1]

                                    $matchedEditions = @(Resolve-EditionMatches -BuildNumber $buildNumber `
                                        -WIMImages $wimImageList -CatalogEntries $CatalogEntries)
                                } else {
                                    $scanError = "Could not extract build number from WIM version: $($detail.Version)"
                                }
                            }
                        } catch {
                            $scanError = "Failed to read WIM images: $($_.Exception.Message)"
                        }
                    }
                }
            }
        } catch {
            $scanError = "Error scanning ISO: $($_.Exception.Message)"
        } finally {
            if ($mountResult) {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
            }
            if ($shellHWWasRunning) {
                Start-Service ShellHWDetection -ErrorAction SilentlyContinue
            }
        }

        # Write cache (even on error, so we don't re-try every time)
        if ($buildNumber -or $scanError) {
            Write-ISOScanCache -ISOFile $isoFile -BuildNumber $buildNumber `
                -WIMImages $wimImageList -Error $scanError
        }

        $primaryKey = if ($matchedEditions.Count -gt 0) { $matchedEditions[0].Key } else { $null }

        $results += [PSCustomObject]@{
            ISOPath         = $isoPath
            ISOName         = $isoName
            Identified      = ($matchedEditions.Count -gt 0)
            OSKey           = $primaryKey
            MatchedEditions = $matchedEditions
            BuildNumber     = $buildNumber
            WIMImages       = $wimImageList
            Error           = $scanError
        }
    }

    # Clean up stale cache files (ISOs that no longer exist)
    Clean-ISOScanCache -SearchPaths $SearchPaths -CurrentISOs $allISOs

    return $results
}

# --- Private helper functions ---

function Resolve-EditionMatches {
    <# Matches WIM images against catalog entries for a given build number. #>
    param(
        [string]$BuildNumber,
        [array]$WIMImages,
        [hashtable]$CatalogEntries
    )

    $editions = @()
    foreach ($key in $CatalogEntries.Keys | Sort-Object) {
        $entry = $CatalogEntries[$key]
        if ($entry.BuildNumber -ne $BuildNumber) { continue }

        $wimIndex = $null
        $wimName = $null

        if ($entry.ContainsKey('WIMImageName') -and $entry.WIMImageName) {
            foreach ($img in $WIMImages) {
                $nameMatch = $img.Name -like "*$($entry.WIMImageName)*"
                $excluded = $false
                if ($nameMatch -and $entry.ContainsKey('WIMImageExclude') -and $entry.WIMImageExclude) {
                    $excluded = $img.Name -like "*$($entry.WIMImageExclude)*"
                }
                if ($nameMatch -and -not $excluded) {
                    $wimIndex = $img.Index
                    $wimName = $img.Name
                    break
                }
            }
        }

        if (-not $wimIndex -and $entry.ContainsKey('ImageIndex')) {
            $fallbackImg = $WIMImages | Where-Object { $_.Index -eq $entry.ImageIndex } | Select-Object -First 1
            if ($fallbackImg) {
                $wimIndex = $fallbackImg.Index
                $wimName = $fallbackImg.Name
            }
        }

        if ($wimIndex) {
            $editions += [PSCustomObject]@{
                Key         = $key
                DisplayName = $entry.DisplayName
                WIMIndex    = $wimIndex
                WIMName     = $wimName
            }
        }
    }

    return $editions
}

function Get-ISOScanCachePath {
    <# Returns the cache file path for an ISO file. #>
    param([System.IO.FileInfo]$ISOFile)
    $cacheDir = Join-Path $ISOFile.DirectoryName '.scan-cache'
    return Join-Path $cacheDir "$($ISOFile.Name).json"
}

function Read-ISOScanCache {
    <# Reads cached scan data if cache is valid (size + lastwrite match). Returns $null if stale. #>
    param([System.IO.FileInfo]$ISOFile)

    $cachePath = Get-ISOScanCachePath -ISOFile $ISOFile
    if (-not (Test-Path $cachePath)) { return $null }

    try {
        $json = Get-Content -Path $cachePath -Raw -ErrorAction Stop
        $cache = $json | ConvertFrom-Json

        # Validate cache freshness
        if ($cache.ISOSize -eq $ISOFile.Length -and
            $cache.ISOLastWrite -eq $ISOFile.LastWriteTimeUtc.ToString('o')) {
            return $cache
        }
    } catch {
        # Corrupt cache file - will be overwritten
    }

    return $null
}

function Write-ISOScanCache {
    <# Writes scan results to a per-ISO cache file. #>
    param(
        [System.IO.FileInfo]$ISOFile,
        [string]$BuildNumber,
        [array]$WIMImages,
        [string]$Error
    )

    $cachePath = Get-ISOScanCachePath -ISOFile $ISOFile
    $cacheDir = Split-Path $cachePath -Parent

    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $cacheData = @{
        ISOPath      = $ISOFile.FullName
        ISOName      = $ISOFile.Name
        ISOSize      = $ISOFile.Length
        ISOLastWrite = $ISOFile.LastWriteTimeUtc.ToString('o')
        CachedAt     = (Get-Date).ToUniversalTime().ToString('o')
        BuildNumber  = $BuildNumber
        WIMImages    = @($WIMImages | ForEach-Object {
            @{
                Index       = $_.Index
                Name        = $_.Name
                Description = $_.Description
                SizeBytes   = $_.SizeBytes
            }
        })
        Error        = $Error
    }

    $cacheData | ConvertTo-Json -Depth 4 | Set-Content -Path $cachePath -Encoding UTF8
}

function Clean-ISOScanCache {
    <# Removes cache files for ISOs that no longer exist. #>
    param(
        [string[]]$SearchPaths,
        [array]$CurrentISOs
    )

    $currentNames = @($CurrentISOs | ForEach-Object { "$($_.Name).json" })

    foreach ($path in $SearchPaths) {
        if (-not $path -or -not (Test-Path $path)) { continue }
        $cacheDir = Join-Path $path '.scan-cache'
        if (-not (Test-Path $cacheDir)) { continue }

        $cacheFiles = @(Get-ChildItem -Path $cacheDir -Filter '*.json' -ErrorAction SilentlyContinue)
        foreach ($cf in $cacheFiles) {
            if ($cf.Name -notin $currentNames) {
                Remove-Item $cf.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
