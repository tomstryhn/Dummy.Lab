# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 2 of the golden-image build: Apply WIM.
#
# Creates the VHDX on disk by applying the selected WIM image from the ISO
# and injecting an unattend file for first-boot automation. Delegates the
# heavy lifting to the existing New-LabVHDXFromISO private helper.
#
# Post-condition: a bootable, un-protected VHDX exists at $Plan.VHDXPath.

function New-GoldenImageVHDX {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    Write-LabLog "Phase 2: Apply WIM to VHDX" -Level Step

    $null = New-LabVHDXFromISO -ISOPath         $Plan.ISOPath `
                               -VHDXPath         $Plan.VHDXPath `
                               -ImageIndex       $Plan.ImageIndex `
                               -SizeGB           $Plan.VHDXSizeGB `
                               -UnattendTemplate $Plan.UnattendPath `
                               -AdminPassword    $Plan.AdminPassword `
                               -TimeZone         $Plan.TimeZone `
                               -InputLocale      $Plan.InputLocale `
                               -UserLocale       $Plan.UserLocale `
                               -SystemLocale     $Plan.SystemLocale

    Write-LabLog "VHDX created: $(Split-Path $Plan.VHDXPath -Leaf)" -Level OK
}
