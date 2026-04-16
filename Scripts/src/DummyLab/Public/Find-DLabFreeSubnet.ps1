# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Find-DLabFreeSubnet {
    <#
    .SYNOPSIS
        Returns the next available /27 segment for a new lab.
    .DESCRIPTION
        Scans existing lab state files and host adapter bindings on
        DLab-Internal to determine which /27 segments are already allocated,
        then returns the segment index and CIDR of the first free slot.

        The shared supernet is 10.74.18.0/23, divided into 16 /27 segments:
          Segment 0  (10.74.18.0/27)   : Staging - reserved for golden builds
          Segments 1-15                 : Labs (auto-allocated by New-DLab)
    .EXAMPLE
        Find-DLabFreeSubnet
    #>
    [CmdletBinding()]
    [OutputType('DLab.SegmentConfig')]
    param()

    $labsRoot = Get-DLabStorePath -Kind Labs
    $freeIdx  = Get-Free27Segment -LabsRoot $labsRoot

    if ($null -eq $freeIdx) {
        Write-Warning "All 15 lab segments (1-15) are in use. No free /27 available."
        return
    }

    Get-27SegmentConfig -Segment $freeIdx
}
