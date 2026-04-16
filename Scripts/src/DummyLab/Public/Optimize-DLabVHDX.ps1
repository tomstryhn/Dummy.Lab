# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Optimize-DLabVHDX {
    <#
    .SYNOPSIS
        Compacts a VHDX file to reclaim disk space.
    .DESCRIPTION
        Wraps the native Optimize-VHD cmdlet with event instrumentation and
        size reporting. Mounts the VHDX, optimizes it, and dismounts it.

        Live-off-the-land: does not reimplement compression or defragmentation;
        delegates entirely to Optimize-VHD.
    .PARAMETER Path
        Full path to the VHDX file to optimize.
    .PARAMETER PassThru
        Return a PSCustomObject with PreSizeGB, PostSizeGB, and SizeReclaimed.
        By default, the cmdlet produces no output.
    .EXAMPLE
        Optimize-DLabVHDX -Path C:\Dummy.Lab\Parent\WS2022.vhdx
    .EXAMPLE
        Optimize-DLabVHDX -Path C:\Dummy.Lab\Parent\WS2022.vhdx -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('DLab.VHDXOptimization')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('VHDXPath')]
        [string]$Path,

        [switch]$PassThru
    )

    process {
        if (-not (Test-Path $Path)) {
            Write-Error "VHDX not found: $Path"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Path, 'Optimize VHDX')) { return }

        # Capture pre-optimization size
        $preSize = (Get-Item $Path).Length
        $preSizeGB = [math]::Round($preSize / 1GB, 2)

        Write-DLabEvent -Level Step -Source 'Optimize-DLabVHDX' `
            -Message "Optimizing VHDX (current size: ${preSizeGB}GB)" `
            -Data @{ Path = $Path; PreSizeGB = $preSizeGB }

        try {
            # Mount, optimize, dismount
            Mount-VHD -Path $Path -NoDriveLetter -ErrorAction Stop
            Optimize-VHD -Path $Path -Mode Full -ErrorAction Stop
            Dismount-VHD -Path $Path -ErrorAction Stop

            # Capture post-optimization size
            $postSize = (Get-Item $Path).Length
            $postSizeGB = [math]::Round($postSize / 1GB, 2)
            $reclaimedGB = [math]::Round(($preSize - $postSize) / 1GB, 2)

            Write-DLabEvent -Level Ok -Source 'Optimize-DLabVHDX' `
                -Message "VHDX optimized: ${postSizeGB}GB (reclaimed ${reclaimedGB}GB)" `
                -Data @{ Path = $Path; PostSizeGB = $postSizeGB; ReclaimedGB = $reclaimedGB }

            if ($PassThru) {
                [PSCustomObject]@{
                    PSTypeName      = 'DLab.VHDXOptimization'
                    Path            = $Path
                    PreSizeGB       = $preSizeGB
                    PostSizeGB      = $postSizeGB
                    ReclaimedGB     = $reclaimedGB
                }
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'Optimize-DLabVHDX' `
                -Message "Failed to optimize VHDX: $($_.Exception.Message)" `
                -Data @{ Path = $Path; Error = $_.Exception.Message }
            throw
        }
    }
}
