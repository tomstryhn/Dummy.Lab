# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 6 of the golden-image build: Finalize.
#
# Removes the temp VM. The switch (DLab-Internal) and NAT (DLab-NAT) are
# shared infrastructure and are intentionally left in place — other labs and
# future builds use them.
#
# Compacts the VHDX to reclaim the free-space zeroing done by the guest prep
# script. Applies the read-only + deny-delete ACL so the image cannot be
# mutated or accidentally deleted. Writes the latest-<GoldenPrefix>.txt
# pointer so Get-LatestGoldenImage returns this as current for the OSKey.
#
# Returns the finalized metadata the orchestrator uses to build its result object.

function Complete-GoldenImageBuild {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    Write-LabLog 'Phase 6: Finalize' -Level Step

    # Remove the temp VM only. DLab-Internal and DLab-NAT are shared and must
    # not be removed here — they serve all labs and golden-image builds.
    Remove-VM -Name $Plan.TempVMName -Force -ErrorAction SilentlyContinue
    Write-LabLog 'Removed temp VM' -Level Info

    # Compact. Full mode is preferred; fall back to Quick on a read-only mount
    # failure so we still reclaim something rather than leaving a bloated VHDX.
    $preSizeGB = [math]::Round((Get-Item $Plan.VHDXPath).Length / 1GB, 2)
    Write-LabLog "Compacting VHDX (before: ${preSizeGB} GB)..." -Level Info
    try {
        Mount-VHD    -Path $Plan.VHDXPath -ReadOnly  -ErrorAction Stop    | Out-Null
        Optimize-VHD -Path $Plan.VHDXPath -Mode Full -ErrorAction Stop    | Out-Null
        Dismount-VHD -Path $Plan.VHDXPath            -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Dismount-VHD -Path $Plan.VHDXPath -ErrorAction SilentlyContinue | Out-Null
        try {
            Optimize-VHD -Path $Plan.VHDXPath -Mode Quick -ErrorAction Stop | Out-Null
        } catch {
            Write-LabLog "VHDX compaction failed: $($_.Exception.Message)" -Level Warn
        }
    }
    $postSizeGB = [math]::Round((Get-Item $Plan.VHDXPath).Length / 1GB, 2)
    $savedGB    = [math]::Round($preSizeGB - $postSizeGB, 2)
    if ($savedGB -gt 0) {
        Write-LabLog "Compacted: ${preSizeGB} GB -> ${postSizeGB} GB (saved ${savedGB} GB)" -Level OK
    } else {
        Write-LabLog "VHDX at ${postSizeGB} GB (already optimal)" -Level OK
    }

    # Protect and publish.
    Protect-GoldenImage -Path $Plan.VHDXPath
    Write-LabLog 'Golden image protected (read-only + deny-delete)' -Level OK

    $pointerFile = Join-Path $Plan.ImageStorePath "latest-$($Plan.OSEntry.GoldenPrefix).txt"
    "$($Plan.ImageName).vhdx" | Set-Content -Path $pointerFile -Encoding UTF8
    Write-LabLog "Updated pointer: $(Split-Path $pointerFile -Leaf) -> $($Plan.ImageName).vhdx" -Level OK

    $duration = (Get-Date) - $Plan.BuildStart

    @{
        ImagePath   = $Plan.VHDXPath
        ImageName   = "$($Plan.ImageName).vhdx"
        SizeGB      = $postSizeGB
        DurationMin = [math]::Round($duration.TotalMinutes, 1)
    }
}

# Best-effort teardown for use by the orchestrator's failure path. Never
# throws; leaves the disk in place if it exists so the operator can
# investigate. DLab-Internal and DLab-NAT are shared and are not touched.
function Stop-GoldenImageBuildCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    Stop-VM   -Name $Plan.TempVMName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $Plan.TempVMName -Force          -ErrorAction SilentlyContinue
}
