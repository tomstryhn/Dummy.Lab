# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Set-LabNAT {
    <#
    .SYNOPSIS
        Assigns the gateway IP to the host vEthernet adapter and creates a NetNat object.
    #>
    param(
        [string]$SwitchName,
        [string]$NatName,
        [PSCustomObject]$NetConfig,
        [switch]$WhatIf
    )

    $adapterName = "vEthernet ($SwitchName)"
    $adapter     = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue

    if (-not $adapter) {
        Write-Warning "Adapter '$adapterName' not found - switch may not have been created yet."
        return
    }

    # Host adapter IP
    $existingIP = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -eq $NetConfig.Gateway }

    if ($existingIP) {
        Write-Host "  [~] Gateway IP $($NetConfig.Gateway) already on '$adapterName'." -ForegroundColor DarkGray
    } else {
        if ($WhatIf) {
            Write-Host "  [?] WhatIf: Would set $($NetConfig.Gateway)/$($NetConfig.PrefixLength) on '$adapterName'" -ForegroundColor DarkCyan
        } else {
            Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

            Write-Host "  [+] Assigning $($NetConfig.Gateway) to '$adapterName'..." -ForegroundColor Cyan
            New-NetIPAddress -InterfaceAlias $adapterName `
                             -IPAddress $NetConfig.Gateway `
                             -PrefixLength $NetConfig.PrefixLength `
                             -ErrorAction Stop | Out-Null
            Write-Host "      Done." -ForegroundColor Green
        }
    }

    # NetNat object
    $existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue

    if ($existingNat -and $existingNat.InternalIPInterfaceAddressPrefix -eq $NetConfig.Subnet) {
        Write-Host "  [~] NetNat '$NatName' already exists for $($NetConfig.Subnet)." -ForegroundColor DarkGray
    } elseif ($existingNat) {
        Write-Warning "NetNat '$NatName' exists but covers a different prefix ($($existingNat.InternalIPInterfaceAddressPrefix))."
        Write-Warning "Remove it manually: Remove-NetNat -Name '$NatName' -Confirm:`$false"
    } else {
        if ($WhatIf) {
            Write-Host "  [?] WhatIf: Would create NetNat '$NatName' for $($NetConfig.Subnet)" -ForegroundColor DarkCyan
        } else {
            Write-Host "  [+] Creating NetNat '$NatName' for $($NetConfig.Subnet)..." -ForegroundColor Cyan
            New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NetConfig.Subnet -ErrorAction Stop | Out-Null
            Write-Host "      Done." -ForegroundColor Green
        }
    }
}
