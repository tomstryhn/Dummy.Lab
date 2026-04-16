# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Installs Dummy.Lab from GitHub.

.DESCRIPTION
    Downloads and sets up the Dummy.Lab Hyper-V lab automation framework.
    Default install path: C:\Dummy.Lab

    Run once on a fresh machine. Re-run to upgrade.

.PARAMETER TargetPath
    Installation directory. Default: C:\Dummy.Lab

.PARAMETER Branch
    GitHub branch. Default: main

.PARAMETER SkipValidation
    Skip Hyper-V and RAM checks.

.PARAMETER SkipBuild
    Download only, don't run Scripts\Build-DummyLab.ps1.

.EXAMPLE
    # Standard install
    irm https://raw.githubusercontent.com/tomstryhn/Dummy.Lab/main/Install-Dummy.Lab.ps1 | iex

.EXAMPLE
    # Custom path
    .\Install-Dummy.Lab.ps1 -TargetPath D:\Labs\Dummy.Lab

.NOTES
    Author  : Tom Stryhn
    Project : https://github.com/tomstryhn/Dummy.Lab
    License : CC BY-NC 4.0
    Requires: Hyper-V role, PowerShell 5.1+, run as Administrator
#>

[CmdletBinding()]
param(
    [string]$TargetPath     = 'C:\Dummy.Lab',
    [string]$Branch         = 'main',
    [string]$LocalSource    = '',     # Skip GitHub download, copy from local path instead
    [switch]$SkipValidation,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Console Output Functions

function Write-Success { param([string]$Message) Write-Host "  [+]  $Message" -ForegroundColor Green }
function Write-Info    { param([string]$Message) Write-Host "  [-]  $Message" -ForegroundColor Gray }
function Write-Warn    { param([string]$Message) Write-Host "  [!]  $Message" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Message) Write-Host "  [x]  $Message" -ForegroundColor Red }
function Write-Step    { param([string]$Message) Write-Host "`n  >>   $Message" -ForegroundColor Cyan }

#endregion Console Output Functions

#region Banner

Write-Host ""
Write-Host "  Dummy.Lab Installer  v1.0.0" -ForegroundColor Cyan
Write-Host "  Target : $TargetPath"
if ($LocalSource) {
    Write-Host "  Source : $LocalSource (local)"
} else {
    Write-Host "  Source : github.com/tomstryhn/Dummy.Lab  [$Branch]"
}
Write-Host ""

#endregion Banner

#region Step 1: Prerequisite Checks

if (-not $SkipValidation) {
    Write-Step "Checking prerequisites"

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Fail "Must run as Administrator."
        exit 1
    }

    $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
    if (-not $hyperVModule) {
        Write-Fail "Hyper-V PowerShell module not found."
        Write-Host ""
        Write-Host "    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }

    $vmmsService = Get-Service vmms -ErrorAction SilentlyContinue
    if (-not $vmmsService -or $vmmsService.Status -ne 'Running') {
        Write-Warn "Hyper-V service not running - restart Windows if you just enabled Hyper-V."
    }

    $totalRAM = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB
    if ($totalRAM -lt 4) {
        Write-Fail "Insufficient RAM ($([math]::Round($totalRAM,1)) GB). Minimum 4 GB required."
        exit 1
    }
    if ($totalRAM -lt 8) {
        Write-Warn "RAM: $([math]::Round($totalRAM,1)) GB detected - 8 GB+ recommended."
    }

    Write-Success "Hyper-V OK  |  RAM: $([math]::Round($totalRAM,1)) GB  |  Admin: yes"
}

#endregion Step 1: Prerequisite Checks

#region Step 2: Determine Install Path

Write-Step "Preparing install path"

$pathExists     = Test-Path $TargetPath
# An existing install is recognised by either the assembled DummyLab module
# on disk or the DLab.ps1 cheat-sheet printer at the root.
$dlabModuleExists = Test-Path (Join-Path $TargetPath 'Scripts\Modules\DummyLab\DummyLab.psm1')
$dlabPs1Exists    = Test-Path (Join-Path $TargetPath 'DLab.ps1')

if ($pathExists -and ($dlabModuleExists -or $dlabPs1Exists)) {
    Write-Warn "Dummy.Lab already installed at: $TargetPath"
    Write-Host ""
    Write-Host "    [U]pgrade  - overwrite files (keeps Scripts\Config)" -ForegroundColor Gray
    Write-Host "    [A]bort    - cancel" -ForegroundColor Gray
    Write-Host ""
    $choice = (Read-Host "  Choice (U)pgrade / (A)bort").ToUpper()
    if ($choice -ne 'U') { Write-Info "Cancelled."; exit 0 }
    Write-Success "Upgrade mode"
} elseif ($pathExists) {
    Write-Warn "Directory exists but contains no Dummy.Lab install: $TargetPath"
    $confirm = (Read-Host "  Continue? (Y)es / (N)o").ToUpper()
    if ($confirm -ne 'Y') { Write-Info "Cancelled."; exit 0 }
} else {
    $null = New-Item -ItemType Directory -Path $TargetPath -Force
    Write-Success "Created: $TargetPath"
}

#endregion Step 2: Determine Install Path

#region Step 3 & 4: Get Files (GitHub download OR local copy)

# Files/folders that exist in the repo but have no place in an installed runtime
$repoOnlyItems = @('.git', '.gitignore', '.github', '.gitattributes', '.editorconfig')

# Helper: copy source folder to target, skipping repo-only items
function Copy-InstallFiles {
    param([string]$SourcePath, [string]$DestPath)
    Get-ChildItem -Path $SourcePath |
        Where-Object { $_.Name -notin $repoOnlyItems } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $DestPath -Recurse -Force
        }
}

if ($LocalSource) {

    # ── Local copy ────────────────────────────────────────────────────────────
    Write-Step "Copying files from local source"

    if (-not (Test-Path $LocalSource)) {
        Write-Fail "LocalSource not found: $LocalSource"
        exit 1
    }

    $configPath   = Join-Path $TargetPath 'Scripts\Config'
    $configBackup = $null

    if ((Test-Path $configPath) -and (Get-ChildItem $configPath -ErrorAction SilentlyContinue)) {
        $configBackup = Join-Path $env:TEMP "Dummy.Lab-Config-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $configPath -Destination $configBackup -Recurse -Force
    }

    $keepFolders = @('ISOs', 'GoldenImages', 'Labs', 'Logs')
    Get-ChildItem -Path $TargetPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $keepFolders } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    try {
        Copy-InstallFiles -SourcePath $LocalSource -DestPath $TargetPath
    } catch {
        Write-Fail "Copy failed: $_"
        exit 1
    }

    if ($configBackup -and (Test-Path $configBackup)) {
        Copy-Item -Path "$configBackup\*" -Destination $configPath -Recurse -Force
        Write-Success "Scripts\Config restored from backup"
    }

    Write-Success "Files copied"

} else {

    # ── GitHub download ───────────────────────────────────────────────────────
    Write-Step "Downloading from GitHub"

    $zipUrl  = "https://github.com/tomstryhn/Dummy.Lab/archive/refs/heads/$Branch.zip"
    $zipPath = Join-Path $env:TEMP "Dummy.Lab-$Branch.zip"

    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Fail "Download failed. Check internet connectivity and that the repo exists."
        exit 1
    }

    Write-Step "Extracting files"

    $extractPath = Join-Path $env:TEMP "Dummy.Lab-Extract-$(Get-Random)"

    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        $sourceFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

        if (-not $sourceFolder) { Write-Fail "Extraction failed - no folder found."; exit 1 }

        $configPath   = Join-Path $TargetPath 'Scripts\Config'
        $configBackup = $null

        if ((Test-Path $configPath) -and (Get-ChildItem $configPath -ErrorAction SilentlyContinue)) {
            $configBackup = Join-Path $env:TEMP "Dummy.Lab-Config-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -Path $configPath -Destination $configBackup -Recurse -Force
        }

        $keepFolders = @('ISOs', 'GoldenImages', 'Labs', 'Logs')
        Get-ChildItem -Path $TargetPath -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $keepFolders } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Copy-InstallFiles -SourcePath $sourceFolder.FullName -DestPath $TargetPath

        if ($configBackup -and (Test-Path $configBackup)) {
            Copy-Item -Path "$configBackup\*" -Destination $configPath -Recurse -Force
            Write-Success "Scripts\Config restored from backup"
        }

        Write-Success "Files extracted"

    } catch {
        Write-Fail "Extraction failed: $_"
        exit 1
    } finally {
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath     -Force         -ErrorAction SilentlyContinue
    }
}

# Remove any .gitkeep placeholder files that were copied from the repo
Get-ChildItem -Path $TargetPath -Filter '.gitkeep' -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

#endregion Step 3 & 4: Get Files (GitHub download OR local copy)

#region Step 5: Create runtime folder structure

Write-Step "Creating data folders"

foreach ($name in @('ISOs', 'GoldenImages', 'Labs', 'Events', 'Operations', 'Reports')) {
    $p = Join-Path $TargetPath $name
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}
Write-Success "ISOs\  GoldenImages\  Labs\  Events\  Operations\  Reports\"

#endregion Step 5: Create runtime folder structure

#region Step 6: Run Build-DummyLab.ps1

if (-not $SkipBuild) {
    # --- Build the DummyLab module -------------------------------------------
    # Source lives at Scripts\src\DummyLab\, the assembled module lands in
    # Scripts\Modules\DummyLab\. Build-DummyLab.ps1 does the concatenation
    # and runs Test-ModuleManifest via -Validate.
    $dlabBuildScript = Join-Path $TargetPath 'Scripts\Build-DummyLab.ps1'
    $dlabSrc         = Join-Path $TargetPath 'Scripts\src\DummyLab'

    if (-not ((Test-Path $dlabBuildScript) -and (Test-Path $dlabSrc))) {
        Write-Fail "DummyLab source not found at $dlabSrc. Install is incomplete."
        exit 1
    }

    Write-Step "Building DummyLab module"
    try {
        & $dlabBuildScript -Validate
    } catch {
        Write-Fail "DummyLab build failed: $_"
        Write-Host "    PS version : $($PSVersionTable.PSVersion)" -ForegroundColor Gray
        Write-Host "    Target     : $TargetPath" -ForegroundColor Gray
        exit 1
    }

    # --- Post-build cleanup: remove source tree once the assembled module is
    # in place. Runtime only needs Scripts\Modules\DummyLab\*,
    # Scripts\GuestScripts\*, and Scripts\Config\*. Source stays if the
    # manifest fails to validate so users can recover.
    $modulesPath  = Join-Path $TargetPath 'Scripts\Modules'
    $dlabPsm1     = Join-Path $modulesPath 'DummyLab\DummyLab.psm1'
    $dlabManifest = Join-Path $modulesPath 'DummyLab\DummyLab.psd1'
    $dlabBuilt            = (Test-Path $dlabPsm1) -and (Test-Path $dlabManifest)
    $dlabManifestValid    = $false
    if ($dlabBuilt) {
        try {
            $null = Test-ModuleManifest -Path $dlabManifest -ErrorAction Stop
            $dlabManifestValid = $true
        } catch {
            Write-Warn "DummyLab manifest invalid: $($_.Exception.Message)"
        }
    }

    if ($dlabBuilt -and $dlabManifestValid) {
        Write-Step "Cleaning up source files"
        $srcPath       = Join-Path $TargetPath 'Scripts\src'
        $dlabBuildFile = Join-Path $TargetPath 'Scripts\Build-DummyLab.ps1'
        if (Test-Path $srcPath)       { Remove-Item $srcPath       -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dlabBuildFile) { Remove-Item $dlabBuildFile -Force          -ErrorAction SilentlyContinue }
        Write-Success "Scripts\src\ and Build-DummyLab.ps1 removed (module already compiled)"
    } else {
        Write-Warn "Build may be incomplete - keeping source files for recovery."
        Write-Warn "Re-run: .\Scripts\Build-DummyLab.ps1 -Validate"
    }
}

#endregion Step 6: Run Build-DummyLab.ps1

#region Step 7: Done

Write-Host ""
Write-Host "  Installed  -->  $TargetPath" -ForegroundColor Green
Write-Host ""
Write-Host "  Next:"
Write-Host "    1. Drop a Windows Server ISO in   $TargetPath\ISOs\"
Write-Host "    2. Import the module              Import-Module DummyLab"
Write-Host "    3. Build a golden image           New-DLabGoldenImage -OSKey WS2025_DC"
Write-Host "    4. Stand up a lab                 Get-DLabGoldenImage -OSKey WS2025_DC |"
Write-Host "                                          New-DLab -LabName MyLab |"
Write-Host "                                          Add-DLabVM -Role Server"
Write-Host ""
Write-Host "  Cheat sheet: .\DLab.ps1  (topics: quickstart, build, lab, health, teardown, report, all)"
Write-Host ""
#endregion Step 7: Done
