# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-LabNetworkConfig {
    <#
    .SYNOPSIS
        Builds and returns the resolved network configuration object.
    .PARAMETER NetworkBase
        First three octets, e.g. '10.104.25'
    .PARAMETER Config
        The merged lab config hashtable (from Get-DLabConfig).
    #>
    param(
        [string]$NetworkBase,
        [hashtable]$Config
    )

    [PSCustomObject]@{
        NetworkBase      = $NetworkBase
        Subnet           = "$NetworkBase.0/24"
        PrefixLength     = 24
        Gateway          = "$NetworkBase.$($Config.GatewayLastOctet)"
        DCBase           = "$NetworkBase.$($Config.DCStartOctet)"
        MemberBase       = "$NetworkBase.$($Config.MemberStartOctet)"
        DHCPScopeStart   = "$NetworkBase.$($Config.DHCPScopeStart)"
        DHCPScopeEnd     = "$NetworkBase.$($Config.DHCPScopeEnd)"
        DHCPExcludeStart = "$NetworkBase.1"
        DHCPExcludeEnd   = "$NetworkBase.63"
        DNSPrimary       = "$NetworkBase.$($Config.DCStartOctet)"
        DNSForwarder     = $Config.DNSForwarder
    }
}
