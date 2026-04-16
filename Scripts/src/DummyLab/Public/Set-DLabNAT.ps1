# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Set-DLabNAT {
    <#
    .SYNOPSIS
        Configures host NAT for a lab switch.
    .DESCRIPTION
        Assigns the network gateway IP to the host vEthernet adapter and
        creates a NetNat object to enable IP translation for the lab network.

        Wraps the legacy Set-LabNAT helper. Idempotent: if the NAT is already
        configured, the cmdlet reports that and succeeds.

        Supports -WhatIf for a dry run. Emits Write-DLabEvent for each step.
    .PARAMETER Name
        NAT configuration name (e.g., 'Pipeline-NAT').
    .PARAMETER InternalIPInterfaceAddressPrefix
        Network CIDR (e.g., '10.104.25.0/24').
    .PARAMETER SwitchName
        Hyper-V switch name (e.g., 'Pipeline-vSwitch'). Used to locate the
        vEthernet adapter.
    .EXAMPLE
        Set-DLabNAT -Name 'Pipeline-NAT' -InternalIPInterfaceAddressPrefix '10.104.25.0/24' -SwitchName 'Pipeline-vSwitch'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$InternalIPInterfaceAddressPrefix,

        [Parameter(Mandatory, Position = 2)]
        [string]$SwitchName
    )

    process {
        if (-not $PSCmdlet.ShouldProcess($Name, 'Configure NAT')) { return }

        # Parse the CIDR to extract network address and prefix length
        $cidrParts = $InternalIPInterfaceAddressPrefix -split '/'
        $ipPart    = $cidrParts[0]
        $prefixLen = if ($cidrParts.Count -gt 1) { [int]$cidrParts[1] } else { 24 }

        # Gateway = network address + 1 (last octet)
        $octets      = $ipPart -split '\.'
        $lastOctet   = [int]$octets[3] + 1
        $gateway     = "$($octets[0]).$($octets[1]).$($octets[2]).$lastOctet"

        # Build network config object for Set-LabNAT
        $netConfig = [PSCustomObject]@{
            NetworkBase  = $ipPart
            Subnet       = $InternalIPInterfaceAddressPrefix
            PrefixLength = $prefixLen
            Gateway      = $gateway
        }

        try {
            Write-DLabEvent -Level Step -Source 'Set-DLabNAT' `
                -Message "Configuring NAT: $Name for $InternalIPInterfaceAddressPrefix" `
                -Data @{ NATName = $Name; Subnet = $InternalIPInterfaceAddressPrefix; Switch = $SwitchName }

            # Call the legacy helper (it handles all the adapter and NetNat logic)
            Set-LabNAT -SwitchName $SwitchName -NatName $Name -NetConfig $netConfig -WhatIf:$PSBoundParameters.ContainsKey('WhatIf')

            Write-DLabEvent -Level Ok -Source 'Set-DLabNAT' `
                -Message "NAT configured: $Name" `
                -Data @{ NATName = $Name; Subnet = $InternalIPInterfaceAddressPrefix }
        } catch {
            Write-DLabEvent -Level Error -Source 'Set-DLabNAT' `
                -Message "Failed to configure NAT: $($_.Exception.Message)" `
                -Data @{ NATName = $Name; Error = $_.Exception.Message }
            throw
        }
    }
}
