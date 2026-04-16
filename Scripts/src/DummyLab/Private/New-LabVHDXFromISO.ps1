# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-LabVHDXFromISO {
    <#
    .SYNOPSIS
        Creates a bootable Gen2 VHDX from a Windows Server ISO with unattend.xml injected.
    .DESCRIPTION
        Steps:
          1. Create a dynamic VHDX
          2. Partition it (EFI System + MSR + Windows)
          3. Mount the ISO and apply install.wim (specified image index)
          4. Inject unattend.xml with lab credentials
          5. Run bcdboot to make it bootable
        The result is a VHDX that boots straight to the desktop, no OOBE.
    .PARAMETER ISOPath
        Full path to the Windows Server ISO.
    .PARAMETER VHDXPath
        Full path for the output VHDX file.
    .PARAMETER ImageIndex
        WIM image index. Default: 4 (Datacenter Desktop Experience).
    .PARAMETER SizeGB
        VHDX size in GB. Default: 60 (dynamic, so actual file is much smaller).
    .PARAMETER UnattendTemplate
        Path to the unattend.xml template. Tokens are replaced at injection time.
    .PARAMETER AdminPassword
        Administrator password baked into unattend.xml.
    .PARAMETER TimeZone
        Windows time zone string. Default: UTC.
    .PARAMETER WhatIf
        Dry run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ISOPath,

        [Parameter(Mandatory)]
        [string]$VHDXPath,

        [int]$ImageIndex        = 4,
        [int]$SizeGB            = 60,
        [string]$UnattendTemplate = '',
        [string]$AdminPassword  = 'Qwerty*12345',
        [string]$TimeZone       = 'UTC',
        [string]$InputLocale    = 'en-US',
        [string]$UserLocale     = 'en-US',
        [string]$SystemLocale   = 'en-US',
        [switch]$WhatIf
    )

    if (-not (Test-Path $ISOPath)) {
        throw "ISO not found: $ISOPath"
    }

    if (Test-Path $VHDXPath) {
        # Validate the existing VHDX is not corrupt (e.g. from an interrupted previous build)
        $existingFile = Get-Item $VHDXPath
        if ($existingFile.Length -lt 1MB) {
            Write-Warning "Existing VHDX appears corrupt (${([math]::Round($existingFile.Length / 1KB, 1))} KB). Removing and rebuilding: $VHDXPath"
            Remove-Item $VHDXPath -Force
        } else {
            try {
                $null = Get-VHD -Path $VHDXPath -ErrorAction Stop
                Write-Host "  [~] VHDX already exists and is valid: $VHDXPath" -ForegroundColor DarkGray
                return $VHDXPath
            } catch {
                Write-Warning "Existing VHDX is unreadable. Removing and rebuilding: $VHDXPath"
                Remove-Item $VHDXPath -Force
            }
        }
    }

    # Ensure output directory exists
    $vhdxDir = Split-Path $VHDXPath -Parent
    if (-not (Test-Path $vhdxDir)) {
        New-Item -ItemType Directory -Path $vhdxDir -Force | Out-Null
    }

    if ($WhatIf) {
        Write-Host "  [?] WhatIf: Would create VHDX from ISO:" -ForegroundColor DarkCyan
        Write-Host "        ISO   : $ISOPath" -ForegroundColor DarkCyan
        Write-Host "        VHDX  : $VHDXPath" -ForegroundColor DarkCyan
        Write-Host "        Image : Index $ImageIndex | ${SizeGB}GB dynamic" -ForegroundColor DarkCyan
        return $VHDXPath
    }

    Write-Host "  [+] Creating VHDX from ISO..." -ForegroundColor Cyan
    Write-Host "        ISO   : $ISOPath"
    Write-Host "        VHDX  : $VHDXPath"
    Write-Host "        Image : Index $ImageIndex | ${SizeGB}GB dynamic"

    $isoMounted  = $false
    $vhdxMounted = $false
    $efiMount    = $null
    $winMount    = $null

    # Stop ShellHWDetection for the duration of all mount/partition operations so
    # Explorer does not show the ISO, EFI, or Windows partitions while they are
    # being worked on. Restarted unconditionally in finally.
    $shellHW = Get-Service ShellHWDetection -ErrorAction SilentlyContinue
    $shellHWWasRunning = $shellHW -and $shellHW.Status -eq 'Running'
    if ($shellHWWasRunning) {
        Stop-Service ShellHWDetection -Force -ErrorAction SilentlyContinue
    }

    try {
        # =====================================================
        # Step 1: Create and partition the VHDX
        # =====================================================
        Write-Host "      Creating ${SizeGB}GB dynamic VHDX..." -ForegroundColor DarkGray
        $null = New-VHD -Path $VHDXPath -SizeBytes ($SizeGB * 1GB) -Dynamic -ErrorAction Stop

        Write-Host "      Mounting VHDX..." -ForegroundColor DarkGray
        Mount-VHD -Path $VHDXPath -NoDriveLetter -ErrorAction Stop
        $vhdxMounted = $true

        $vhdDisk = Get-VHD -Path $VHDXPath
        $diskNumber = $vhdDisk.DiskNumber

        Write-Host "      Initializing disk $diskNumber (GPT)..." -ForegroundColor DarkGray
        Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop

        # EFI System Partition (260 MB) - no drive letter, use temp mount path
        $efiPartition = New-Partition -DiskNumber $diskNumber -Size 260MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
        Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
        $efiMount = Join-Path $env:TEMP "lab-efi-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $efiMount -Force | Out-Null
        $efiPartition | Add-PartitionAccessPath -AccessPath $efiMount

        # MSR (16 MB) - Microsoft Reserved, required for GPT
        New-Partition -DiskNumber $diskNumber -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null

        # Windows partition (rest of disk) - no drive letter, use temp mount path
        $winPartition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
        Format-Volume -Partition $winPartition -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null
        $winMount = Join-Path $env:TEMP "lab-win-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $winMount -Force | Out-Null
        $winPartition | Add-PartitionAccessPath -AccessPath $winMount

        Write-Host "      Partitions ready." -ForegroundColor DarkGray

        # =====================================================
        # Step 2: Mount ISO and apply WIM
        # =====================================================
        Write-Host "      Mounting ISO..." -ForegroundColor DarkGray
        $isoMount = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
        $isoMounted = $true
        $isoLetter = ($isoMount | Get-Volume).DriveLetter

        $wimPath = "${isoLetter}:\sources\install.wim"
        if (-not (Test-Path $wimPath)) {
            throw "install.wim not found at $wimPath - is this a valid Windows ISO?"
        }

        Write-Host "      Applying install.wim (Index $ImageIndex) - this takes a few minutes..." -ForegroundColor Cyan
        $null = Expand-WindowsImage -ImagePath $wimPath -Index $ImageIndex -ApplyPath "$winMount\" -ErrorAction Stop
        Write-Host "      Image applied." -ForegroundColor Green

        # =====================================================
        # Step 3: Inject unattend.xml
        # =====================================================
        if ($UnattendTemplate -and (Test-Path $UnattendTemplate)) {
            Write-Host "      Injecting unattend.xml..." -ForegroundColor DarkGray
            $pantherDir = Join-Path $winMount 'Windows\Panther'
            if (-not (Test-Path $pantherDir)) {
                New-Item -ItemType Directory -Path $pantherDir -Force | Out-Null
            }

            $xml = Get-Content $UnattendTemplate -Raw
            # Use .Replace() instead of -replace to avoid regex interpretation of password/locale values
            $xml = $xml.Replace('@@ADMIN_PASSWORD@@', $AdminPassword)
            $xml = $xml.Replace('@@COMPUTERNAME@@', '*')
            $xml = $xml.Replace('@@TIMEZONE@@', $TimeZone)
            $xml = $xml.Replace('@@INPUT_LOCALE@@', $InputLocale)
            $xml = $xml.Replace('@@USER_LOCALE@@', $UserLocale)
            $xml = $xml.Replace('@@SYSTEM_LOCALE@@', $SystemLocale)
            $xml | Set-Content -Path (Join-Path $pantherDir 'unattend.xml') -Encoding UTF8
            $xml | Set-Content -Path (Join-Path $winMount 'unattend.xml') -Encoding UTF8

            Write-Host "      unattend.xml injected." -ForegroundColor Green
        } else {
            Write-Warning "No unattend template found - VM will show OOBE on first boot."
        }

        # =====================================================
        # Step 4: Make it bootable (bcdboot)
        # bcdboot requires drive letters - assign temporarily
        # =====================================================
        Write-Host "      Running bcdboot..." -ForegroundColor DarkGray

        $winPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
        $winLetter = ($winPartition | Get-Partition).DriveLetter
        $efiPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
        $efiLetter = ($efiPartition | Get-Partition).DriveLetter

        # Use bcdboot from the applied image (avoids cross-version issues)
        $imageBcdboot = "${winLetter}:\Windows\System32\bcdboot.exe"
        $bcdResult = & $imageBcdboot "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "      Image bcdboot failed ($LASTEXITCODE), trying host bcdboot..." -ForegroundColor DarkGray
            $bcdResult = & bcdboot "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "bcdboot failed: $bcdResult"
            }
        }

        # Remove temporary drive letters
        $winPartition | Remove-PartitionAccessPath -AccessPath "${winLetter}:\" -ErrorAction SilentlyContinue
        $efiPartition | Remove-PartitionAccessPath -AccessPath "${efiLetter}:\" -ErrorAction SilentlyContinue

        Write-Host "      Boot files written to EFI partition." -ForegroundColor Green

    } finally {
        # =====================================================
        # Cleanup: remove access paths, dismount everything
        # =====================================================
        if ($efiMount -and $efiPartition) {
            $efiPartition | Remove-PartitionAccessPath -AccessPath $efiMount -ErrorAction SilentlyContinue
            Remove-Item $efiMount -Force -ErrorAction SilentlyContinue
        }
        if ($winMount -and $winPartition) {
            $winPartition | Remove-PartitionAccessPath -AccessPath $winMount -ErrorAction SilentlyContinue
            Remove-Item $winMount -Force -ErrorAction SilentlyContinue
        }
        if ($isoMounted) {
            Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue | Out-Null
        }
        if ($vhdxMounted) {
            Dismount-VHD -Path $VHDXPath -ErrorAction SilentlyContinue
        }
        if ($shellHWWasRunning) {
            Start-Service ShellHWDetection -ErrorAction SilentlyContinue
        }
    }

    $fileSize = [math]::Round((Get-Item $VHDXPath).Length / 1GB, 2)
    Write-Host "  [+] VHDX created: $VHDXPath (${fileSize} GB on disk)" -ForegroundColor Green
    return $VHDXPath
}
