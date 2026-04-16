# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Ensure-DLabSharedInfrastructure {
    <#
    .SYNOPSIS
        Idempotently creates the shared Hyper-V switch and NAT used by the
        golden-image staging segment, and the single NetNat covering the full
        DLab supernet.
    .DESCRIPTION
        Creates, if not already present:
          - VMSwitch 'DLab-Internal' (Internal type) - staging segment only
          - Host IP 10.74.18.1/27 on vEthernet (DLab-Internal)
          - NetNat 'DLab-NAT' covering 10.74.18.0/23 (all 16 segments)

        'DLab-Internal' is the staging switch for golden-image builds (segment 0).
        Each lab gets its own per-lab switch ('DLab-<LabName>') created by
        New-DLab, with its own /27 gateway IP on the host adapter. All lab
        switches are isolated from each other (Hyper-V Internal type) while
        the single DLab-NAT provides internet access across the full /23
        supernet for every segment.

        Windows only supports one user-created NetNat, so DLab-NAT covers
        10.74.18.0/23 (all 16 /27 segments) rather than one entry per lab.

        This function is intentionally silent on success when everything already
        exists. It only writes to the host when it creates something new.
    .PARAMETER SwitchName
        Override the staging switch name. Default: 'DLab-Internal'.
    .PARAMETER NatName
        Override the NAT name. Default: 'DLab-NAT'.
    .PARAMETER GatewayIP
        Override the staging segment gateway IP. Default: '10.74.18.1'.
    .PARAMETER SupernetCIDR
        Override the supernet CIDR for the NAT. Default: '10.74.18.0/23'.
    .PARAMETER GatewayPrefixLength
        Override the prefix length for the host gateway adapter IP. Default: 27.
    #>
    [CmdletBinding()]
    param(
        [string]$SwitchName          = 'DLab-Internal',
        [string]$NatName             = 'DLab-NAT',
        [string]$GatewayIP           = '10.74.18.1',
        [string]$SupernetCIDR        = '10.74.18.0/23',
        [int]   $GatewayPrefixLength  = 27
    )

    # --- 1. VMSwitch ---
    $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if ($existingSwitch) {
        if ($existingSwitch.SwitchType -ne 'Internal') {
            throw "Switch '$SwitchName' exists but is type '$($existingSwitch.SwitchType)'. Expected Internal."
        }
        Write-LabLog "Shared switch '$SwitchName' already present." -Level Detail
    } else {
        Write-LabLog "Creating shared switch '$SwitchName' (Internal)..." -Level Info
        New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop | Out-Null
        Write-LabLog "Switch '$SwitchName' created." -Level OK
    }

    # --- 2. Host adapter IP ---
    $adapterName = "vEthernet ($SwitchName)"

    # Wait briefly for the adapter to appear after switch creation.
    $adapter = $null
    for ($i = 0; $i -lt 10; $i++) {
        $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        if ($adapter) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $adapter) {
        throw "Adapter '$adapterName' not found after switch creation."
    }

    $existingIP = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -eq $GatewayIP -and $_.PrefixLength -eq $GatewayPrefixLength }

    if ($existingIP) {
        Write-LabLog "Host IP $GatewayIP/$GatewayPrefixLength already on '$adapterName'." -Level Detail
    } else {
        # Remove any stale IPs (e.g. APIPA or wrong-prefixlength) first.
        Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne '127.0.0.1' } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        Write-LabLog "Assigning $GatewayIP/$GatewayPrefixLength to '$adapterName'..." -Level Info
        New-NetIPAddress -InterfaceAlias $adapterName `
                         -IPAddress $GatewayIP `
                         -PrefixLength $GatewayPrefixLength `
                         -ErrorAction Stop | Out-Null
        Write-LabLog "Host IP assigned." -Level OK
    }

    # --- 3. NetNat ---
    $existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if ($existingNat) {
        if ($existingNat.InternalIPInterfaceAddressPrefix -ne $SupernetCIDR) {
            Write-Warning "NetNat '$NatName' exists but covers '$($existingNat.InternalIPInterfaceAddressPrefix)' instead of '$SupernetCIDR'. Remove it manually if this is incorrect: Remove-NetNat -Name '$NatName' -Confirm:`$false"
        } else {
            Write-LabLog "Shared NAT '$NatName' ($SupernetCIDR) already present." -Level Detail
        }
    } else {
        # Windows only allows one user-created NetNat. Warn if a conflicting
        # NAT already exists under a different name (e.g. from a previous lab).
        $conflictingNat = Get-NetNat -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -ne $NatName -and $_.InternalIPInterfaceAddressPrefix }
        if ($conflictingNat) {
            $names = ($conflictingNat | ForEach-Object { "'$($_.Name)' ($($_.InternalIPInterfaceAddressPrefix))" }) -join ', '
            Write-Warning "Found existing NetNat(s) that may conflict: $names`nWindows supports only one user-created NetNat. Remove conflicting entries before DLab-NAT can be created."
        }

        Write-LabLog "Creating shared NAT '$NatName' ($SupernetCIDR)..." -Level Info
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $SupernetCIDR -ErrorAction Stop | Out-Null
        Write-LabLog "NAT '$NatName' created." -Level OK
    }
}
