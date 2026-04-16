# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DifferencingDisk {
    <#
    .SYNOPSIS
        Creates a differencing VHDX from a golden image parent, with unattend.xml injected.
    .DESCRIPTION
        The differencing disk inherits the parent's base blocks (read-only).
        Only changes made inside the VM are written to the diff disk.
        After creation, mounts the diff disk and injects an unattend.xml so the
        sysprepped image boots straight to the desktop without OOBE.
    .PARAMETER ParentPath
        Full path to the golden image (parent VHDX).
    .PARAMETER DestinationPath
        Full path for the new differencing VHDX.
    .PARAMETER UnattendPath
        Path to the unattend.xml template. Tokens are replaced at injection time.
    .PARAMETER ComputerName
        Computer name for unattend.xml token replacement. Default: * (random).
    .PARAMETER AdminPassword
        Admin password for unattend.xml token replacement.
    .PARAMETER TimeZone
        Time zone for unattend.xml token replacement.
    .PARAMETER InputLocale
        Input locale for unattend.xml token replacement.
    .PARAMETER UserLocale
        User locale for unattend.xml token replacement.
    .PARAMETER SystemLocale
        System locale for unattend.xml token replacement.
    .PARAMETER DomainName
        Domain name for unattend.xml domain join block. If empty, no domain join.
    .PARAMETER WhatIf
        Dry run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ParentPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [string]$UnattendPath   = '',
        [string]$ComputerName   = '*',
        [string]$AdminPassword  = '',
        [string]$TimeZone       = '',
        [string]$InputLocale    = '',
        [string]$UserLocale     = '',
        [string]$SystemLocale   = '',
        [string]$DomainName     = '',
        [switch]$WhatIf
    )

    if (-not (Test-Path $ParentPath)) {
        throw "Parent golden image not found: $ParentPath"
    }

    if (Test-Path $DestinationPath) {
        # Validate the existing differencing disk is not corrupt (e.g. from an interrupted previous build)
        $existingFile = Get-Item $DestinationPath
        if ($existingFile.Length -lt 1MB) {
            Write-Warning "Existing differencing disk appears corrupt (${([math]::Round($existingFile.Length / 1KB, 1))} KB). Removing and recreating: $DestinationPath"
            Remove-Item $DestinationPath -Force
        } else {
            try {
                $null = Get-VHD -Path $DestinationPath -ErrorAction Stop
                Write-Host "  [~] Differencing disk already exists and is valid: $DestinationPath" -ForegroundColor DarkGray
                return $DestinationPath
            } catch {
                Write-Warning "Existing differencing disk is unreadable. Removing and recreating: $DestinationPath"
                Remove-Item $DestinationPath -Force
            }
        }
    }

    # Ensure destination directory exists
    $destDir = Split-Path $DestinationPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    if ($WhatIf) {
        Write-Host "  [?] WhatIf: Would create differencing disk:" -ForegroundColor DarkCyan
        Write-Host "        Parent : $ParentPath" -ForegroundColor DarkCyan
        Write-Host "        Diff   : $DestinationPath" -ForegroundColor DarkCyan
        Write-Host "        Name   : $ComputerName" -ForegroundColor DarkCyan
        return $null
    }

    # Step 1: Create the differencing VHDX
    Write-LabLog "Creating differencing disk..." -Level Step
    Write-LabLog "  Parent : $ParentPath" -Level Info
    Write-LabLog "  Dest   : $DestinationPath" -Level Info

    New-VHD -Path $DestinationPath -ParentPath $ParentPath -Differencing -ErrorAction Stop | Out-Null
    Write-LabLog "Differencing disk created" -Level OK

    # Step 2: Inject unattend.xml if template provided
    if ($UnattendPath -and (Test-Path $UnattendPath)) {
        Write-LabLog "Injecting unattend.xml (ComputerName: $ComputerName)..." -Level Step

        # Read the template
        $unattendContent = Get-Content -Path $UnattendPath -Raw -Encoding UTF8

        # Replace tokens - use .Replace() to avoid regex interpretation of password/name values
        $unattendContent = $unattendContent.Replace('@@ADMIN_PASSWORD@@', $AdminPassword)
        $unattendContent = $unattendContent.Replace('@@COMPUTERNAME@@', $ComputerName)
        $unattendContent = $unattendContent.Replace('@@TIMEZONE@@', $TimeZone)
        $unattendContent = $unattendContent.Replace('@@INPUT_LOCALE@@', $InputLocale)
        $unattendContent = $unattendContent.Replace('@@USER_LOCALE@@', $UserLocale)
        $unattendContent = $unattendContent.Replace('@@SYSTEM_LOCALE@@', $SystemLocale)

        # Domain join block - empty if no domain specified at this stage
        # (DC promotion and domain join are handled by guest scripts, not unattend)
        $unattendContent = $unattendContent.Replace('@@DOMAIN_JOIN@@', '')

        # Mount the differencing disk to inject unattend.
        # Stop ShellHWDetection first so Explorer does not show the partition
        # as a removable drive during the mount. Restarted unconditionally in finally.
        $shellHW = Get-Service ShellHWDetection -ErrorAction SilentlyContinue
        $shellHWWasRunning = $shellHW -and $shellHW.Status -eq 'Running'
        if ($shellHWWasRunning) {
            Stop-Service ShellHWDetection -Force -ErrorAction SilentlyContinue
        }

        $mountResult = $null
        try {
            $mountResult = Mount-VHD -Path $DestinationPath -Passthru -ErrorAction Stop
            $disk = $mountResult | Get-Disk
            # Find the Windows partition (largest NTFS partition)
            $winPartition = $disk | Get-Partition |
                Where-Object { $_.Type -ne 'System' -and $_.Type -ne 'Reserved' -and $_.Size -gt 1GB } |
                Sort-Object Size -Descending |
                Select-Object -First 1

            if (-not $winPartition) {
                throw "Could not find Windows partition on differencing disk"
            }

            $driveLetter = $winPartition.DriveLetter
            if (-not $driveLetter) {
                # Assign a drive letter if none
                $winPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
                $winPartition = $disk | Get-Partition |
                    Where-Object { $_.Type -ne 'System' -and $_.Type -ne 'Reserved' -and $_.Size -gt 1GB } |
                    Sort-Object Size -Descending |
                    Select-Object -First 1
                $driveLetter = $winPartition.DriveLetter
            }

            if (-not $driveLetter) {
                throw "Failed to assign drive letter to Windows partition"
            }

            # Write unattend.xml to the Panther directory
            $pantherPath = "${driveLetter}:\Windows\Panther"
            if (-not (Test-Path $pantherPath)) {
                New-Item -ItemType Directory -Path $pantherPath -Force | Out-Null
            }

            $unattendDest = Join-Path $pantherPath 'unattend.xml'
            Set-Content -Path $unattendDest -Value $unattendContent -Encoding UTF8 -Force

            # Also place in the root Sysprep expected location
            $sysprepUnattend = "${driveLetter}:\Windows\System32\Sysprep\unattend.xml"
            Set-Content -Path $sysprepUnattend -Value $unattendContent -Encoding UTF8 -Force

            Write-LabLog "Unattend.xml injected" -Level OK

        } finally {
            if ($mountResult) {
                Dismount-VHD -Path $DestinationPath -ErrorAction SilentlyContinue
            }
            if ($shellHWWasRunning) {
                Start-Service ShellHWDetection -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-LabLog "No unattend template - skipping injection" -Level Info
    }

    return $DestinationPath
}
