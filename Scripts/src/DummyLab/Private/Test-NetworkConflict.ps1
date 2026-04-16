# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-NetworkConflict {
    <#
    .SYNOPSIS
        Checks whether the planned /24 subnet overlaps any existing host IP assignments.
    .PARAMETER NetworkBase
        First three octets, e.g. '10.104.25'
    #>
    param([string]$NetworkBase)

    $hostAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                     Select-Object -ExpandProperty IPAddress

    $conflicts = $hostAddresses | Where-Object { $_ -like "$NetworkBase.*" }

    if ($conflicts) {
        return New-ValidationResult -Check 'NetworkConflict' -Passed $false `
            -Message "Subnet $NetworkBase.0/24 already in use on host: $($conflicts -join ', ')" `
            -Detail 'Use -NetworkBase to specify a different subnet, or run Resolve-NetworkBase for auto-suggestion.'
    }

    $existingNat = Get-NetNat -ErrorAction SilentlyContinue |
                   Where-Object { $_.InternalIPInterfaceAddressPrefix -like "$NetworkBase.*" }
    if ($existingNat) {
        return New-ValidationResult -Check 'NetworkConflict' -Passed $false `
            -Message "A NetNat already uses $NetworkBase.0/24: $($existingNat.Name)" `
            -Detail 'Remove the existing NAT or choose a different subnet.'
    }

    New-ValidationResult -Check 'NetworkConflict' -Passed $true `
        -Message "Subnet $NetworkBase.0/24 is available."
}
