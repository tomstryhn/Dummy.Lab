# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepares a Windows Server VM for use as a golden image.

.DESCRIPTION
    State-machine script - run repeatedly:

      State 1 - OOBE not complete    -> Wait (unattend.xml handles this).
      State 2 - Updates pending      -> Install all updates, reboot if needed.
      State 3 - Updates done         -> Cleanup + Sysprep. VM shuts down.

    After sysprep shutdown, the VHDX is the golden image.

.PARAMETER InstallUpdates
    Whether to run Windows Update. Default: true.
.PARAMETER UpdateTimeoutMin
    Max minutes to spend on Windows Update. Default: 60.
.PARAMETER Phase
    Which phase to run: 'Updates', 'Sysprep', or 'All'. Default: 'All'.

.NOTES
    Author  : Tom Stryhn
    Version : 1.0.0
    Target  : Windows Server 2022/2025, clean from ISO + unattend
#>

[CmdletBinding()]
param (
    [bool]$InstallUpdates    = $true,
    [int]$UpdateTimeoutMin   = 60,
    [string]$Phase           = 'All'
)

function Write-Phase { param([string]$Message); Write-Host "`n>> $Message" -ForegroundColor Cyan }

#region Phase: Windows Update
if ($Phase -eq 'All' -or $Phase -eq 'Updates') {
    if ($InstallUpdates) {
        Write-Phase "Installing Windows Updates"

        # Use the Windows Update COM API (no external modules needed)
        $updateSession  = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        $deadline = (Get-Date).AddMinutes($UpdateTimeoutMin)
        $round = 0
        $totalInstalled = 0

        while ((Get-Date) -lt $deadline) {
            $round++
            Write-Host "   Update round $round, searching..." -ForegroundColor DarkGray

            try {
                $searchResult = $updateSearcher.Search("IsInstalled=0 AND IsHidden=0")
            } catch {
                Write-Warning "Update search failed: $($_.Exception.Message)"
                break
            }

            if ($searchResult.Updates.Count -eq 0) {
                Write-Host "   No more updates available." -ForegroundColor Green
                break
            }

            Write-Host "   Found $($searchResult.Updates.Count) update(s):" -ForegroundColor Cyan
            $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($update in $searchResult.Updates) {
                Write-Host "     - $($update.Title)" -ForegroundColor DarkGray
                if (-not $update.EulaAccepted) { $update.AcceptEula() }
                $updatesToInstall.Add($update) | Out-Null
            }

            # Download
            Write-Host "   Downloading..." -ForegroundColor DarkGray
            $downloader = $updateSession.CreateUpdateDownloader()
            $downloader.Updates = $updatesToInstall
            try {
                $null = $downloader.Download()
            } catch {
                Write-Warning "Download failed: $($_.Exception.Message)"
                break
            }

            # Install
            Write-Host "   Installing..." -ForegroundColor Cyan
            $installer = $updateSession.CreateUpdateInstaller()
            $installer.Updates = $updatesToInstall
            try {
                $installResult = $installer.Install()
                $totalInstalled += $updatesToInstall.Count
                Write-Host "   Installed $($updatesToInstall.Count) update(s). Result: $($installResult.ResultCode)" -ForegroundColor Green
            } catch {
                Write-Warning "Install failed: $($_.Exception.Message)"
                break
            }

            # Check if reboot is required
            $systemInfo = New-Object -ComObject Microsoft.Update.SystemInfo
            if ($systemInfo.RebootRequired) {
                Write-Host "   Reboot required. Re-run to continue." -ForegroundColor Yellow
                Write-Host "   REBOOT_NEEDED" -ForegroundColor Yellow
                Restart-Computer -Force
                exit 0
            }
        }

        Write-Host "   Total updates installed: $totalInstalled" -ForegroundColor Green

        # Mark updates as done
        $markerPath = 'C:\LabScripts\.updates-done'
        Set-Content -Path $markerPath -Value "Updates completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    } else {
        Write-Host "   Skipping Windows Update (InstallUpdates=false)." -ForegroundColor DarkGray
    }
}

#endregion Phase: Windows Update

#region Phase: Cleanup + Sysprep
if ($Phase -eq 'All' -or $Phase -eq 'Sysprep') {
    Write-Phase "Preparing for Sysprep - disk optimization"

    # Helper: report free space on C:
    function Get-FreeGB {
        [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    }

    $startFreeGB = Get-FreeGB
    Write-Host "   Free space before cleanup: ${startFreeGB} GB" -ForegroundColor Gray

    # -----------------------------------------------------------------
    # 1. Temp files (user + system) - typically 100-500 MB
    # -----------------------------------------------------------------
    Write-Host "   [1/5] Cleaning temp files..." -ForegroundColor DarkGray
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\Windows\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\Users\*\AppData\Local\Temp\*' -Recurse -Force -ErrorAction SilentlyContinue
    $afterTemp = Get-FreeGB
    Write-Host "   Freed: $([math]::Round($afterTemp - $startFreeGB, 2)) GB" -ForegroundColor DarkGray

    # -----------------------------------------------------------------
    # 2. Windows Update cache - 500 MB to 2 GB after patching
    # -----------------------------------------------------------------
    Write-Host "   [2/5] Cleaning Windows Update cache..." -ForegroundColor DarkGray
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\Windows\SoftwareDistribution\Download\*' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\Windows\SoftwareDistribution\DataStore\*' -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    $afterWU = Get-FreeGB
    Write-Host "   Freed: $([math]::Round($afterWU - $afterTemp, 2)) GB" -ForegroundColor DarkGray

    # -----------------------------------------------------------------
    # 3. DISM component store - removes superseded update components (GBs with patches)
    #    /ResetBase makes rollback impossible but massively shrinks WinSxS.
    #    This is the single biggest space saver on patched images.
    # -----------------------------------------------------------------
    Write-Host "   [3/5] DISM /StartComponentCleanup /ResetBase..." -ForegroundColor DarkGray
    & dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
    $afterDISM = Get-FreeGB
    Write-Host "   Freed: $([math]::Round($afterDISM - $afterWU, 2)) GB" -ForegroundColor DarkGray

    # -----------------------------------------------------------------
    # 4. Optimize-Volume - defrag consolidates data, retrim marks free
    #    blocks so the VHDX layer knows they're empty.
    # -----------------------------------------------------------------
    Write-Host "   [4/5] Optimize-Volume (defrag + retrim)..." -ForegroundColor DarkGray
    try {
        Optimize-Volume -DriveLetter C -Defrag -ReTrim -ErrorAction Stop
        Write-Host "   Volume optimized (defrag + retrim)." -ForegroundColor DarkGray
    } catch {
        try {
            Optimize-Volume -DriveLetter C -Defrag -ErrorAction Stop
            Write-Host "   Volume defragmented." -ForegroundColor DarkGray
        } catch {
            Write-Host "   Optimize-Volume skipped: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }

    # -----------------------------------------------------------------
    # 5. Zero-fill free space - writes zeros over all free clusters so
    #    Optimize-VHD on the host can reclaim them. This is what makes
    #    the VHDX file physically shrink.
    # -----------------------------------------------------------------
    Write-Host "   [5/5] Zeroing free space for VHDX compaction..." -ForegroundColor DarkGray
    $zeroFile = "$env:SystemDrive\zero.tmp"
    try {
        $fs = [System.IO.File]::Create($zeroFile)
        $zeros = New-Object byte[] (1MB)
        try {
            while ($true) { $fs.Write($zeros, 0, $zeros.Length) }
        } catch {
            # Expected: disk full
        } finally {
            $fs.Close()
        }
        Remove-Item $zeroFile -Force -ErrorAction SilentlyContinue
        Write-Host "   Free space zeroed." -ForegroundColor DarkGray
    } catch {
        Remove-Item $zeroFile -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------
    # After zero-fill, free space is near 0 (expected, zeros reclaimed by host Optimize-VHD)
    Write-Host ""
    Write-Host "   Cleanup + zero-fill complete." -ForegroundColor Green
    Write-Host "   Free space was: ${startFreeGB} GB (now zeroed for VHDX compaction)" -ForegroundColor Green

    # Remove lab scripts and leftover unattend (not needed in golden image)
    Remove-Item -Path 'C:\LabScripts' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path 'C:\unattend.xml' -Force -ErrorAction SilentlyContinue

    # -----------------------------------------------------------------
    # Sysprep
    # -----------------------------------------------------------------
    Write-Phase "Running Sysprep (generalize + oobe + shutdown)"
    Write-Host "   VM will shut down when Sysprep completes." -ForegroundColor Yellow

    & "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /quiet
    # Sysprep shuts down the VM - script ends here
}
#endregion Phase: Cleanup + Sysprep
