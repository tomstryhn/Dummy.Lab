# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-LabState {
    <#
    .SYNOPSIS
        Creates the initial lab state object with metadata and empty VM list.
    .PARAMETER Lab
        Lab name.
    .PARAMETER Domain
        Fully qualified domain name (e.g. mylab.internal).
    .PARAMETER DomainNetbios
        NetBIOS domain name.
    .PARAMETER SegConfig
        Segment config object from Get-27SegmentConfig for this lab's /27 segment.
    .PARAMETER LabSwitchName
        Name of the per-lab Hyper-V switch (e.g. 'DLab-Dummy'). Recorded in
        Infrastructure.SwitchName so Remove-DLab can tear it down.
    .PARAMETER HasInternet
        Whether internet access (NAT via default gateway) is enabled. Default: $true.
        When $false, VMs have no default gateway - isolated to their /27 segment.
    .PARAMETER DNSForwarder
        DNS forwarder IP for the DC (from config).
    #>
    param(
        [Parameter(Mandatory)][string]$Lab,
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$DomainNetbios,
        [Parameter(Mandatory)][PSCustomObject]$SegConfig,
        [Parameter(Mandatory)][string]$LabSwitchName,
        [bool]$HasInternet    = $true,
        [string]$DNSForwarder = '1.1.1.1'
    )
    [PSCustomObject]@{
        LabName        = $Lab
        DomainName     = $Domain
        DomainNetbios  = $DomainNetbios
        CreatedAt      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        HasInternet    = $HasInternet
        Infrastructure = [PSCustomObject]@{
            SwitchName   = $LabSwitchName  # owned by this lab, removed on teardown
            NATName      = ''              # shared - not owned by this lab
            StoragePath  = ''
        }
        Network        = [PSCustomObject]@{
            SwitchName       = $LabSwitchName
            Segment          = $SegConfig.Segment
            Subnet           = $SegConfig.NetworkCIDR
            NetworkBase      = $SegConfig.NetworkBase
            PrefixLength     = $SegConfig.PrefixLength
            SubnetMask       = $SegConfig.SubnetMask
            Gateway          = $SegConfig.Gateway
            DCIP             = $SegConfig.DCStartIP
            DHCPScopeStart   = $SegConfig.DHCPScopeStart
            DHCPScopeEnd     = $SegConfig.DHCPScopeEnd
            DHCPExcludeStart = $SegConfig.DHCPExcludeStart
            DHCPExcludeEnd   = $SegConfig.DHCPExcludeEnd
            DNSForwarder     = $DNSForwarder
        }
        VMs              = @()
    }
}
