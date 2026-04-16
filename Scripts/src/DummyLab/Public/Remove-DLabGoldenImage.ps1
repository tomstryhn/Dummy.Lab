# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLabGoldenImage {
    <#
    .SYNOPSIS
        Removes a golden image with full dependency checking.
    .DESCRIPTION
        Wraps the legacy Remove-GoldenImage. Scans all lab differencing disks
        for active parent references and blocks deletion if any lab VM
        depends on this image. Reverses protection ACLs, deletes the VHDX,
        and updates the latest-*.txt pointer to the next-newest image (or
        removes the pointer if this was the last one).

        Silent on success by default. Use -PassThru to receive the
        DLab.Operation record.
    .PARAMETER Path
        Full path to the golden image VHDX. Accepts pipeline input.
    .PARAMETER Force
        Skip the active-use check. The caller is responsible for any orphan
        differencing disks that result.
    .PARAMETER PassThru
        Emit the DLab.Operation for the removal.
    .EXAMPLE
        Remove-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2022-DC-2026.03.15.vhdx -WhatIf
    .EXAMPLE
        Get-DLabGoldenImage | Where-Object Patched -eq $false | Remove-DLabGoldenImage -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('DLab.Operation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ImagePath', 'FullName')]
        [string]$Path,

        [switch]$Force,
        [switch]$PassThru
    )

    process {
        if (-not (Test-Path $Path)) {
            Write-Error "Golden image not found: $Path"
            return
        }
        $imageName = Split-Path $Path -Leaf
        if (-not $PSCmdlet.ShouldProcess($imageName, 'Remove golden image')) { return }

        $imageStore = Get-DLabStorePath -Kind Images
        $labsRoot   = Get-DLabStorePath -Kind Labs

        $op = New-DLabOperation -Kind 'Remove-DLabGoldenImage' -Target $imageName `
                                -Parameters @{ Path = $Path; Force = [bool]$Force }

        try {
            Write-DLabEvent -Level Step -Source 'Remove-DLabGoldenImage' `
                -Message "Removing $imageName" `
                -OperationId $op.OperationId
            Remove-GoldenImage -Path $Path -ImageStorePath $imageStore -LabsRoot $labsRoot -Force:$Force -Confirm:$false
            Write-DLabEvent -Level Ok -Source 'Remove-DLabGoldenImage' `
                -Message "$imageName removed" `
                -OperationId $op.OperationId

            $finalOp = $op | Complete-DLabOperation -Status Succeeded -Result @{ Path = $Path; ImageName = $imageName }
        } catch {
            Write-DLabEvent -Level Error -Source 'Remove-DLabGoldenImage' `
                -Message "Remove failed: $($_.Exception.Message)" `
                -OperationId $op.OperationId
            $finalOp = $op | Complete-DLabOperation -Status Failed -ErrorMessage $_.Exception.Message
            throw
        }

        if ($PassThru) { $finalOp }
    }
}
