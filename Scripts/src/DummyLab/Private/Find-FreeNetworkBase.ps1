# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Find-FreeNetworkBase {
    <#
    .SYNOPSIS
        Finds the next free /24 subnet by scanning every host-side source that
        could already be using one: lab state files, existing NetNat entries,
        and live IPv4 addresses bound to any network adapter. Starts from the
        default (e.g. 10.104.25) and increments the third octet.
    .DESCRIPTION
        Three independent sources are consulted so a residual vEthernet
        binding from a prior (partially cleaned-up) lab cannot be mistaken
        for a free subnet:

          1. Lab state files under LabsRoot (Network.Subnet field).
          2. Host NetNat entries (InternalIPInterfaceAddressPrefix).
          3. Host NetIPAddress IPv4 bindings on ANY adapter (not just
             vEthernet - Hyper-V guests, WSL, VPN clients, and physical
             NICs can all pin a /24 and would otherwise collide with
             New-NetIPAddress when the adapter is reconfigured).

        If any source lists the candidate base, it is skipped.
    .PARAMETER DefaultBase
        The preferred network base to start from (e.g. 10.104.25).
    .PARAMETER LabsRoot
        Path to the Labs folder containing lab state files.
    .OUTPUTS
        String - the first free network base (e.g. 10.104.26), or $null if none found.
    #>
    param(
        [Parameter(Mandatory)][string]$DefaultBase,
        [Parameter(Mandatory)][string]$LabsRoot
    )

    $usedBases = [System.Collections.Generic.List[string]]::new()

    # Source 1: lab state files.
    if (Test-Path $LabsRoot) {
        $stateFiles = Get-ChildItem -Path $LabsRoot -Filter 'lab.state.json' -Recurse -ErrorAction SilentlyContinue
        foreach ($sf in $stateFiles) {
            try {
                $state = Get-Content $sf.FullName -Raw | ConvertFrom-Json
                if ($state.PSObject.Properties['Network'] -and
                    $state.Network -and
                    $state.Network.PSObject.Properties['Subnet'] -and
                    $state.Network.Subnet) {
                    # "10.104.25.0/24" -> "10.104.25"
                    $usedBases.Add(($state.Network.Subnet -replace '\.0/24$', ''))
                }
            } catch { }
        }
    }

    # Source 2: active NetNat entries.
    foreach ($nat in (Get-NetNat -ErrorAction SilentlyContinue)) {
        if ($nat.InternalIPInterfaceAddressPrefix) {
            $usedBases.Add(($nat.InternalIPInterfaceAddressPrefix -replace '\.0/24$', ''))
        }
    }

    # Source 3: live IPv4 bindings on any adapter. This catches residual
    # vEthernet adapters whose IPs were never removed (e.g. a previous
    # lab teardown removed the NetNat but left the switch+IP bound).
    # Link-local (169.254.x.x) and loopback (127.x.x.x) are ignored.
    foreach ($ip in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
        $addr = [string]$ip.IPAddress
        if ($addr.StartsWith('127.') -or $addr.StartsWith('169.254.')) { continue }
        $parts = $addr -split '\.'
        if ($parts.Count -eq 4) {
            $usedBases.Add("$($parts[0]).$($parts[1]).$($parts[2])")
        }
    }

    $usedSet = @($usedBases | Where-Object { $_ } | Select-Object -Unique)

    # Parse the default base into octets.
    $parts = $DefaultBase -split '\.'
    $o1 = [int]$parts[0]
    $o2 = [int]$parts[1]
    $o3 = [int]$parts[2]

    # Try the default first, then increment the third octet.
    for ($i = $o3; $i -le 254; $i++) {
        $candidate = "$o1.$o2.$i"
        if ($candidate -notin $usedSet) {
            return $candidate
        }
    }

    return $null
}
