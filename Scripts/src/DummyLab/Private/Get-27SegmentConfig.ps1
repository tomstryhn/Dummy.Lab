# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-27SegmentConfig {
    <#
    .SYNOPSIS
        Returns the IP layout for a given /27 segment within the shared DLab supernet.
    .DESCRIPTION
        The shared DLab supernet is 10.74.18.0/23 (512 addresses).
        It is divided into 16 /27 segments (32 addresses each):
          Segment  0: 10.74.18.0/27   - Staging / golden-image builds
          Segment  1: 10.74.18.32/27  - Lab 1
          Segment  2: 10.74.18.64/27  - Lab 2
          ...
          Segment 15: 10.74.19.224/27 - Lab 15

        Address layout within each segment (base = segment network address):
          base + 0         : Network address
          base + 1         : Gateway (host vEthernet DLab-Internal)
          base + 2  to + 5 : DC range     (4 slots)
          base + 6  to +21 : Server range (16 slots)
          base +22  to +30 : DHCP dynamic pool (9 addresses)
          base +31         : Broadcast

        Static IPs are all below +22, so no DHCP exclusions are required.

        Since all segments are 32-aligned, adding offsets 0-31 to the last
        octet of the base never overflows the octet, regardless of segment.
    .PARAMETER Segment
        Segment index (0-15). 0 is the staging segment.
    .OUTPUTS
        DLab.SegmentConfig
    #>
    [CmdletBinding()]
    [OutputType('DLab.SegmentConfig')]
    param(
        [Parameter(Mandatory)][int]$Segment
    )

    if ($Segment -lt 0 -or $Segment -gt 15) {
        throw "Segment must be 0-15 (got $Segment). The shared supernet 10.74.18.0/23 supports 16 /27 segments."
    }

    # Supernet base as a 32-bit integer
    # 10.74.18.0 = (10 << 24) | (74 << 16) | (18 << 8) | 0
    $baseInt = (10 * 16777216) + (74 * 65536) + (18 * 256) + 0

    # Segment base = supernet base + segment * 32
    $segInt = $baseInt + $Segment * 32

    # Split back to dotted notation
    $n1 = [math]::Floor($segInt / 16777216) -band 255
    $n2 = [math]::Floor($segInt / 65536)    -band 255
    $n3 = [math]::Floor($segInt / 256)      -band 255
    $n4 = $segInt -band 255

    # All per-segment IPs are last-octet offsets from n4.
    # Safe: n4 is always a multiple of 32 (0, 32, 64, … 224),
    # max offset is 31, so n4 + 31 <= 255 in all cases.
    $networkBase = "$n1.$n2.$n3.$n4"
    $gateway     = "$n1.$n2.$n3.$($n4 + 1)"
    $dcStartIP   = "$n1.$n2.$n3.$($n4 + 2)"    # DCs:     offsets 2-5  (4 slots)
    $srvStartIP  = "$n1.$n2.$n3.$($n4 + 6)"    # Servers: offsets 6-21 (16 slots)
    $dhcpStart   = "$n1.$n2.$n3.$($n4 + 22)"   # DHCP:    offsets 22-30 (9 addresses)
    $dhcpEnd     = "$n1.$n2.$n3.$($n4 + 30)"
    $broadcastIP = "$n1.$n2.$n3.$($n4 + 31)"

    [PSCustomObject]@{
        PSTypeName       = 'DLab.SegmentConfig'
        Segment          = $Segment
        NetworkCIDR      = "$networkBase/27"
        NetworkBase      = $networkBase          # 4-octet network address
        PrefixLength     = 27
        SubnetMask       = '255.255.255.224'
        Gateway          = $gateway
        DCStartIP        = $dcStartIP
        ServerStartIP    = $srvStartIP
        DHCPScopeStart   = $dhcpStart
        DHCPScopeEnd     = $dhcpEnd
        DHCPExcludeStart = ''                    # no exclusions needed: statics are all below DHCP range
        DHCPExcludeEnd   = ''
        BroadcastIP      = $broadcastIP
        # Absolute last-octet values for use in Reserve-VMSlot (NextDCOctet / NextServerOctet)
        DCStartOctet     = $n4 + 2
        ServerStartOctet = $n4 + 6
    }
}
