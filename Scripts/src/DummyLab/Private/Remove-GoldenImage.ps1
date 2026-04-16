# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-GoldenImage {
    <#
    .SYNOPSIS
        Safely removes a golden image VHDX and updates pointer references.
    .DESCRIPTION
        Removes a golden image with full dependency checking:
          1. Scans all lab differencing disks to detect active parent references.
          2. Blocks deletion if the image is in use (unless -Force).
          3. Reverses ACL protection set by Protect-GoldenImage.
          4. Deletes the VHDX file.
          5. Updates the pointer file (latest-{prefix}.txt) to the next-newest
             image, or removes the pointer if this was the last one.

        Without this function, manually deleting a golden image breaks:
          - Pointer files that reference the deleted image
          - Running labs whose differencing disks have it as a parent
    .PARAMETER Path
        Full path to the golden image VHDX to remove.
    .PARAMETER ImageStorePath
        Path to the golden image store (default: derived from config).
        Used for pointer file updates and sibling image discovery.
    .PARAMETER LabsRoot
        Path to the Labs root folder. Used to scan for active differencing disks.
        Default: sibling 'Labs' folder next to the image store's parent.
    .PARAMETER Force
        Skip the active-use check and remove even if labs reference this image.
        The caller is responsible for handling orphaned differencing disks.
    .PARAMETER WhatIf
        Show what would happen without making changes.
    .OUTPUTS
        None. Writes status to the console via Write-Host/Write-LabLog.
    .EXAMPLE
        Remove-GoldenImage -Path 'C:\Dummy.Lab\GoldenImages\WS2025-DC-2026.04.01.vhdx'
    .EXAMPLE
        Remove-GoldenImage -Path 'C:\Dummy.Lab\GoldenImages\WS2025-DC-2026.04.01.vhdx' -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ImageStorePath = '',
        [string]$LabsRoot      = '',
        [switch]$Force
    )

    # -- Validate target ---------------------------------------------
    if (-not (Test-Path $Path)) {
        Write-Warning "Golden image not found: $Path"
        return
    }

    $resolvedPath   = (Resolve-Path $Path).Path
    $imageName      = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    $imageFile      = [System.IO.Path]::GetFileName($resolvedPath)

    # Derive ImageStorePath from the file's parent if not specified
    if (-not $ImageStorePath) {
        $ImageStorePath = Split-Path $resolvedPath -Parent
    }

    # Derive LabsRoot from sibling 'Labs' folder if not specified
    if (-not $LabsRoot) {
        $storageRoot = Split-Path $ImageStorePath -Parent
        $LabsRoot    = Join-Path $storageRoot 'Labs'
    }

    Write-Host ""
    Write-Host "  [~] Remove-GoldenImage: $imageFile" -ForegroundColor Cyan

    # -- Extract golden prefix from filename --------------------------
    # Pattern: {GoldenPrefix}-{date}[-unpatched].vhdx
    # Examples: WS2025-DC-2026.04.13.vhdx, WS2025-DC-2026.04.13-unpatched.vhdx
    # GoldenPrefix can contain hyphens (e.g. WS2025-DC-CORE), so we match
    # everything up to the date pattern.
    if ($imageName -match '^(.+)-(\d{4}\.\d{2}\.\d{2})(-unpatched)?$') {
        $goldenPrefix = $Matches[1]
    } else {
        Write-Warning "Cannot determine golden prefix from filename: $imageFile"
        Write-Warning "Expected pattern: {Prefix}-{YYYY.MM.DD}[-unpatched].vhdx"
        return
    }

    # -- Check for active differencing disk children ------------------
    if (-not $Force -and (Test-Path $LabsRoot)) {
        Write-Host "  [~] Scanning labs for active references..." -ForegroundColor DarkGray

        $activeRefs = @()
        $diskFiles = @(Get-ChildItem -Path $LabsRoot -Filter '*.vhdx' -Recurse -ErrorAction SilentlyContinue)

        foreach ($disk in $diskFiles) {
            try {
                $vhdInfo = Get-VHD -Path $disk.FullName -ErrorAction Stop
                if ($vhdInfo.ParentPath -and
                    $vhdInfo.ParentPath -eq $resolvedPath) {
                    $activeRefs += $disk.FullName
                }
            } catch {
                # Not a valid VHD or access denied  - skip
            }
        }

        if ($activeRefs.Count -gt 0) {
            Write-Host "  [X] Cannot remove: image is in use by $($activeRefs.Count) differencing disk(s):" -ForegroundColor Red
            foreach ($ref in $activeRefs) {
                Write-Host "      - $ref" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "  Remove those labs first, or use -Force to override." -ForegroundColor Yellow
            return
        }

        Write-Host "  [+] No active references found." -ForegroundColor DarkGray
    }

    # -- WhatIf gate --------------------------------------------------
    if (-not $PSCmdlet.ShouldProcess($resolvedPath, 'Remove golden image')) {
        return
    }

    # -- Reverse ACL protection ---------------------------------------
    Write-Host "  [~] Removing file protection..." -ForegroundColor DarkGray

    try {
        # Clear read-only attribute
        $file = Get-Item $resolvedPath
        if ($file.IsReadOnly) {
            $file.IsReadOnly = $false
        }

        # Remove the Deny Delete rule for Everyone
        $acl = Get-Acl $resolvedPath
        $rulesToRemove = @($acl.Access | Where-Object {
            $_.IdentityReference.Value -eq 'Everyone' -and
            $_.AccessControlType -eq 'Deny' -and
            ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Delete)
        })
        foreach ($rule in $rulesToRemove) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }
        Set-Acl -Path $resolvedPath -AclObject $acl
    } catch {
        Write-Warning "Failed to remove file protection: $($_.Exception.Message)"
        Write-Warning "Try running as Administrator."
        return
    }

    # -- Delete the VHDX ----------------------------------------------
    try {
        Remove-Item -Path $resolvedPath -Force -ErrorAction Stop
        Write-Host "  [+] Deleted: $imageFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete golden image: $($_.Exception.Message)"
        return
    }

    # -- Update pointer file ------------------------------------------
    $pointerFile = Join-Path $ImageStorePath "latest-${goldenPrefix}.txt"

    if (Test-Path $pointerFile) {
        $pointerContent = (Get-Content $pointerFile -Raw -ErrorAction SilentlyContinue).Trim()

        # Only update if this pointer actually references the deleted image
        $pointerPointsHere = ($pointerContent -eq $imageFile) -or
                             ($pointerContent -eq $imageName)

        if ($pointerPointsHere) {
            # Find the next-newest sibling image with the same prefix
            $escapedPrefix = [regex]::Escape($goldenPrefix)
            $siblings = @(Get-ChildItem -Path $ImageStorePath -Filter "${goldenPrefix}-*.vhdx" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match "^${escapedPrefix}-\d" } |
                        Sort-Object Name -Descending)

            if ($siblings.Count -gt 0) {
                # Point to next-newest
                $newTarget = $siblings[0].Name
                Set-Content -Path $pointerFile -Value $newTarget -Encoding UTF8
                Write-Host "  [+] Pointer updated: latest-${goldenPrefix}.txt -> $newTarget" -ForegroundColor Green
            } else {
                # Last image for this prefix  - remove pointer
                Remove-Item -Path $pointerFile -Force -ErrorAction SilentlyContinue
                Write-Host "  [~] Pointer removed: latest-${goldenPrefix}.txt (no images remain)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [~] Pointer unchanged (references a different image)." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [~] No pointer file found for prefix '${goldenPrefix}'." -ForegroundColor DarkGray
    }

    Write-Host "  [+] Golden image removed successfully." -ForegroundColor Green
    Write-Host ""
}
