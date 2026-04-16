# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Export-DLabGoldenImage {
    <#
    .SYNOPSIS
        Copies a golden image out of the image store for backup or transfer.
    .DESCRIPTION
        Produces a portable copy of a golden image suitable for moving to
        backup storage, another host, or a teammate. The source image stays
        in place with its protection intact; the destination copy is writable
        by default so the receiving end can re-protect it during Import.

        Optionally also writes a metadata sidecar (<image>.meta.json) next to
        the destination containing OSKey, BuildDate, Protected flag, and the
        original ImagePath, so Import-DLabGoldenImage on the other side can
        reconstruct full context.

        The export is wrapped in a DLab.Operation record, so it appears in
        Get-DLabOperation history alongside other golden-image lifecycle
        events.
    .PARAMETER Path
        Source golden image VHDX path. Accepts pipeline from DLab.GoldenImage.
    .PARAMETER Destination
        Directory to copy the image to. Created if it does not exist.
    .PARAMETER IncludeMetadata
        Also write a <image>.meta.json file alongside the copy.
    .PARAMETER Force
        Overwrite existing files in the destination.
    .PARAMETER PassThru
        Emit the DLab.Operation record describing the export.
    .EXAMPLE
        Export-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2025-DC-2026.04.14-unpatched.vhdx `
            -Destination D:\Backups\Dummy.Lab -IncludeMetadata
    .EXAMPLE
        Get-DLabGoldenImage | Where-Object Patched | Export-DLabGoldenImage `
            -Destination \\backup\share -IncludeMetadata
    .NOTES
        Author : Tom Stryhn
        Version : 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('DLab.Operation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ImagePath', 'FullName')]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$Destination,

        [switch]$IncludeMetadata,
        [switch]$Force,
        [switch]$PassThru
    )

    process {
        if (-not (Test-Path $Path)) {
            Write-DLabEvent -Level Error -Source 'Export-DLabGoldenImage' `
                -Message "Source golden image not found: $Path" `
                -Data @{ SourcePath = $Path }
            Write-Error "Source golden image not found: $Path"
            return
        }

        $leaf     = Split-Path $Path -Leaf
        $destFile = Join-Path $Destination $leaf

        if (-not $PSCmdlet.ShouldProcess($destFile, "Export golden image from $leaf")) { return }

        $op = New-DLabOperation -Kind 'Export-DLabGoldenImage' -Target $leaf `
                                -Parameters @{
                                    Path            = $Path
                                    Destination     = $Destination
                                    IncludeMetadata = [bool]$IncludeMetadata
                                    Force           = [bool]$Force
                                }

        try {
            # Ensure destination directory exists
            if (-not (Test-Path $Destination)) {
                try {
                    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
                } catch {
                    throw "Cannot create destination directory: $($_.Exception.Message)"
                }
            }

            if ((Test-Path $destFile) -and -not $Force) {
                throw "Destination already exists: $destFile. Use -Force to overwrite."
            }

            Write-DLabEvent -Level Step -Source 'Export-DLabGoldenImage' `
                -Message "Exporting $leaf to $Destination" `
                -OperationId $op.OperationId `
                -Data @{ SourcePath = $Path; DestFile = $destFile; IncludeMetadata = [bool]$IncludeMetadata }

            $start = Get-Date
            Copy-Item -Path $Path -Destination $destFile -Force -ErrorAction Stop

            # Clear any protection flags on the destination copy so the receiver
            # can re-protect or modify during Import. Source stays protected.
            try { (Get-Item $destFile).IsReadOnly = $false } catch { }

            $metaPath = $null
            if ($IncludeMetadata) {
                # Pull current metadata from Get-DLabGoldenImage rather than
                # re-parsing the filename, so we stay consistent with how the
                # catalog would describe this image.
                $current = Get-DLabGoldenImage -Name $leaf | Select-Object -First 1
                $meta = [PSCustomObject]@{
                    SchemaVersion     = 1
                    ExportedAt        = (Get-Date).ToString('o')
                    OriginalPath      = $Path
                    OriginalHost      = $env:COMPUTERNAME
                    ImageName         = $leaf
                    OSKey             = if ($current) { $current.OSKey }     else { '' }
                    OSName            = if ($current) { $current.OSName }    else { '' }
                    SizeGB            = if ($current) { $current.SizeGB }    else { (Get-Item $destFile).Length / 1GB }
                    BuildDate         = if ($current) { $current.BuildDate.ToString('o') } else { (Get-Item $Path).LastWriteTime.ToString('o') }
                    Patched           = if ($current) { $current.Patched }   else { $null }
                    ProtectedAtSource = if ($current) { $current.Protected } else { $null }
                }
                $metaPath = "$destFile.meta.json"
                try {
                    $meta | ConvertTo-Json -Depth 10 | Set-Content -Path $metaPath -Encoding UTF8 -Force
                } catch {
                    # Metadata sidecar failure is not fatal to the export. Log a warn
                    # event and continue; downstream Import can still read the VHDX.
                    Write-DLabEvent -Level Warn -Source 'Export-DLabGoldenImage' `
                        -Message "Metadata sidecar write failed: $($_.Exception.Message)" `
                        -OperationId $op.OperationId `
                        -Data @{ MetadataPath = $metaPath }
                    $metaPath = $null
                }
            }

            $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
            Write-DLabEvent -Level Ok -Source 'Export-DLabGoldenImage' `
                -Message "Exported $leaf ($elapsed s)" `
                -OperationId $op.OperationId `
                -Data @{ DestFile = $destFile; MetadataPath = $metaPath; DurationSec = $elapsed }

            $result = [pscustomobject]@{
                PSTypeName   = 'DLab.ExportResult'
                SourcePath   = $Path
                Destination  = $destFile
                MetadataPath = $metaPath
                DurationSec  = $elapsed
            }

            $finalOp = $op | Complete-DLabOperation -Status Succeeded -Result $result
        } catch {
            Write-DLabEvent -Level Error -Source 'Export-DLabGoldenImage' `
                -Message "Export failed: $($_.Exception.Message)" `
                -OperationId $op.OperationId `
                -Data @{ SourcePath = $Path; DestFile = $destFile }
            $finalOp = $op | Complete-DLabOperation -Status Failed -ErrorMessage $_.Exception.Message
            throw
        }

        if ($PassThru) { $finalOp }
    }
}
