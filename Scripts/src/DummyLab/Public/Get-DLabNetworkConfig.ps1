# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabNetworkConfig {
    <#
    .SYNOPSIS
        Returns the IP layout for a given /27 segment within the shared DLab supernet.
    .DESCRIPTION
        The shared DLab supernet is 10.74.18.0/23, divided into 16 /27 segments
        of 32 addresses each:
          Segment 0  (10.74.18.0/27)  : Staging - golden-image builds
          Segments 1-15               : Labs (one per New-DLab)

        Returns a DLab.SegmentConfig object with NetworkBase, Gateway, DCIP,
        DHCPScopeStart, DHCPScopeEnd, SubnetMask, and other routing fields.

        Pass no argument to see the first available lab segment.
    .PARAMETER Segment
        Segment index (0-15). Defaults to the next free lab segment.
    .EXAMPLE
        Get-DLabNetworkConfig            # show next free segment config
    .EXAMPLE
        Get-DLabNetworkConfig -Segment 1 # show segment 1 config
    .EXAMPLE
        0..15 | ForEach-Object { Get-DLabNetworkConfig -Segment $_ } | Format-Table Segment, NetworkCIDR, Gateway
    #>
    [CmdletBinding()]
    [OutputType('DLab.SegmentConfig')]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(0, 15)]
        [int]$Segment = -1
    )

    process {
        if ($Segment -lt 0) {
            $labsRoot = Get-DLabStorePath -Kind Labs
            $Segment  = Get-Free27Segment -LabsRoot $labsRoot
            if ($null -eq $Segment) {
                Write-Warning "All 15 lab segments (1-15) are in use."
                return
            }
        }
        Get-27SegmentConfig -Segment $Segment
    }
}
