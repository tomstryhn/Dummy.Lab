# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Import-DLabGoldenImage {
    <#
    .SYNOPSIS
        Registers an external VHDX as a Dummy.Lab golden image.
    .DESCRIPTION
        Use cases:
          - Recover golden images after a fresh install
          - Bring images from backup storage
          - Onboard images built elsewhere (e.g. another host)
          - Share images between team members

        Validates the source VHDX, copies (or moves) it into the image store,
        optionally renames to match catalog conventions, applies protection,
        and optionally updates the latest-<prefix>.txt pointer so
        New-DLab / Add-DLabVM will pick it up as the default.

        OSKey is inferred from filename prefix when possible; pass -OSKey
        explicitly for arbitrary names.

        Silent on success by default. Use -PassThru to receive the
        DLab.GoldenImage record.
    .PARAMETER SourcePath
        Path to the external VHDX to import.
    .PARAMETER OSKey
        OS catalog key. When omitted, the cmdlet tries to infer from the
        source filename using catalog GoldenPrefix matching.
    .PARAMETER NewName
        Rename the image during import. Recommended when importing from a
        source with a non-catalog name. Default: keep the source filename.
    .PARAMETER Move
        Move the source file rather than copy. Default: copy (source preserved).
    .PARAMETER AsLatest
        Update the latest-<GoldenPrefix>.txt pointer to this image so it
        becomes the default for New-DLab / Add-DLabVM.
    .PARAMETER Force
        Overwrite an existing image with the same target name.
    .PARAMETER PassThru
        Emit the imported DLab.GoldenImage.
    .EXAMPLE
        Import-DLabGoldenImage -SourcePath D:\Backups\WS2025-DC-2026.04.01.vhdx -AsLatest
    .EXAMPLE
        Import-DLabGoldenImage -SourcePath '\\server\share\myimage.vhdx' `
            -OSKey WS2025_DC -NewName 'WS2025-DC-2026.04.14-custom.vhdx'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.GoldenImage')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Path', 'FullName')]
        [string]$SourcePath,

        [string]$OSKey   = '',
        [string]$NewName = '',
        [switch]$Move,
        [switch]$AsLatest,
        [switch]$Force,
        [switch]$PassThru
    )

    begin {
        $cfg = Get-DLabConfigInternal
        $imageStore = Get-DLabStorePath -Kind Images

        # Build catalog lookup for OSKey inference and pointer filenames
        $catalog = @{}
        foreach ($entry in (Get-DLabCatalog)) {
            $catalog[$entry.OSKey] = @{
                DisplayName  = $entry.DisplayName
                GoldenPrefix = $entry.GoldenPrefix
                AliasFor     = $entry.AliasFor
            }
        }
    }

    process {
        if (-not (Test-Path $SourcePath)) {
            Write-Error "Source VHDX not found: $SourcePath"
            return
        }

        $srcLeaf    = Split-Path $SourcePath -Leaf
        $targetName = if ($NewName) { $NewName } else { $srcLeaf }
        $targetPath = Join-Path $imageStore $targetName

        # --- Validate the source parses as a standalone VHDX -------------
        try {
            $vhdInfo = Get-VHD -Path $SourcePath -ErrorAction Stop
            if ($vhdInfo.ParentPath) {
                Write-Error "Source is a differencing disk (parent: $($vhdInfo.ParentPath)). Golden images must be standalone."
                return
            }
        } catch {
            Write-Error "Source is not a readable VHDX: $($_.Exception.Message)"
            return
        }

        # --- Infer OSKey from filename when not provided -----------------
        if (-not $OSKey) {
            $bestPrefixLen = 0
            foreach ($k in $catalog.Keys) {
                $p = $catalog[$k].GoldenPrefix
                if (-not $p) { continue }
                if ($targetName.StartsWith($p) -and $p.Length -gt $bestPrefixLen) {
                    $OSKey = $k
                    $bestPrefixLen = $p.Length
                }
            }
        } else {
            # Normalise + alias-resolve
            $OSKey = $OSKey -replace '-', '_'
            if ($catalog.ContainsKey($OSKey) -and $catalog[$OSKey].AliasFor) {
                $OSKey = $catalog[$OSKey].AliasFor
            }
        }
        if (-not $OSKey) {
            Write-Warning "OSKey could not be inferred from '$targetName'. Pass -OSKey to tag explicitly. Importing anyway."
        }

        # --- Conflict handling --------------------------------------------
        if ((Test-Path $targetPath) -and -not $Force) {
            Write-Error "Target already exists: $targetPath. Use -Force to overwrite."
            return
        }

        if (-not $PSCmdlet.ShouldProcess($targetPath, "$(if ($Move) { 'Move' } else { 'Copy' }) from $SourcePath")) { return }

        Write-DLabEvent -Level Step -Source 'Import-DLabGoldenImage' `
            -Message "Importing $srcLeaf -> $targetName" `
            -Data @{ SourcePath = $SourcePath; TargetPath = $targetPath; OSKey = $OSKey; Move = [bool]$Move }

        # If target exists and -Force, clear protection ACL so we can overwrite
        if (Test-Path $targetPath) {
            try { (Get-Item $targetPath).IsReadOnly = $false } catch { }
            try {
                $acl = Get-Acl $targetPath
                $denyRules = $acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }
                foreach ($r in $denyRules) { $null = $acl.RemoveAccessRule($r) }
                Set-Acl -Path $targetPath -AclObject $acl
            } catch { }
            Remove-Item $targetPath -Force
        }

        if (-not (Test-Path $imageStore)) {
            New-Item -ItemType Directory -Path $imageStore -Force | Out-Null
        }

        try {
            if ($Move) {
                Move-Item -Path $SourcePath -Destination $targetPath -Force -ErrorAction Stop
            } else {
                Copy-Item -Path $SourcePath -Destination $targetPath -Force -ErrorAction Stop
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'Import-DLabGoldenImage' `
                -Message "Transfer failed: $($_.Exception.Message)" `
                -Data @{ SourcePath = $SourcePath; TargetPath = $targetPath }
            throw
        }

        # Apply protection
        try {
            Protect-GoldenImage -Path $targetPath
        } catch {
            Write-Warning "Import succeeded but protection failed: $($_.Exception.Message)"
        }

        # Optionally update the latest-*.txt pointer
        if ($AsLatest -and $OSKey -and $catalog.ContainsKey($OSKey) -and $catalog[$OSKey].GoldenPrefix) {
            $prefix = $catalog[$OSKey].GoldenPrefix
            $pointerPath = Join-Path $imageStore "latest-$prefix.txt"
            try {
                Set-Content -Path $pointerPath -Value $targetName -Encoding UTF8 -Force
                Write-DLabEvent -Level Ok -Source 'Import-DLabGoldenImage' `
                    -Message "Updated pointer: latest-$prefix.txt -> $targetName" `
                    -Data @{ PointerPath = $pointerPath; Target = $targetName }
            } catch {
                Write-Warning "Pointer update failed: $($_.Exception.Message)"
            }
        }

        Write-DLabEvent -Level Ok -Source 'Import-DLabGoldenImage' `
            -Message "Imported $targetName" `
            -Data @{ TargetPath = $targetPath; OSKey = $OSKey }

        if ($PassThru) {
            Get-DLabGoldenImage -Name $targetName
        }
    }
}
