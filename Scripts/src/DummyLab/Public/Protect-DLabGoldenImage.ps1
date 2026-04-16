# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Protect-DLabGoldenImage {
    <#
    .SYNOPSIS
        Applies read-only + deny-delete protection to a golden image.
    .DESCRIPTION
        Wraps the legacy Protect-GoldenImage. Sets the VHDX file read-only
        and adds an ACL deny-rule against Delete/DeleteSubdirectoriesAndFiles
        for Everyone. Hyper-V can still use read-only VHDXs as differencing
        disk parents.
    .PARAMETER Path
        Full path to the golden image VHDX. Accepts pipeline from
        DLab.GoldenImage.ImagePath.
    .PARAMETER PassThru
        Emit the DLab.GoldenImage after protection is applied.
    .EXAMPLE
        Protect-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2025-DC-2026.04.14.vhdx
    .EXAMPLE
        Get-DLabGoldenImage | Where-Object { -not $_.Protected } | Protect-DLabGoldenImage
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('DLab.GoldenImage')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ImagePath', 'FullName')]
        [string]$Path,

        [switch]$PassThru
    )

    process {
        if (-not (Test-Path $Path)) {
            Write-Error "Golden image not found: $Path"
            return
        }
        if (-not $PSCmdlet.ShouldProcess($Path, 'Apply read-only + deny-delete protection')) { return }

        Write-DLabEvent -Level Step -Source 'Protect-DLabGoldenImage' `
            -Message "Protecting $(Split-Path $Path -Leaf)" `
            -Data @{ Path = $Path }

        try {
            Protect-GoldenImage -Path $Path
            Write-DLabEvent -Level Ok -Source 'Protect-DLabGoldenImage' `
                -Message "Protected $(Split-Path $Path -Leaf)" `
                -Data @{ Path = $Path }
        } catch {
            Write-DLabEvent -Level Error -Source 'Protect-DLabGoldenImage' `
                -Message "Protection failed: $($_.Exception.Message)" `
                -Data @{ Path = $Path; Error = $_.Exception.Message }
            throw
        }

        if ($PassThru) {
            Get-DLabGoldenImage -Name (Split-Path $Path -Leaf)
        }
    }
}
