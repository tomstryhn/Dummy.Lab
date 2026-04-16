# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Resolve-NetworkBase {
    <#
    .SYNOPSIS
        Returns a conflict-free /24 network base, auto-incrementing the third octet if needed.
    .DESCRIPTION
        Starts at the preferred base (e.g. '10.104.25'), checks for conflicts,
        and increments (10.104.26, 10.104.27 ...) until a free subnet is found,
        up to MaxAttempts tries.
    .PARAMETER PreferredBase
        Preferred network base (first three octets).
    .PARAMETER MaxAttempts
        How many subnets to try. Default: 20.
    .OUTPUTS
        String - the resolved network base, or $null if all attempts fail.
    #>
    param(
        [string]$PreferredBase = '10.104.25',
        [int]$MaxAttempts = 20
    )

    $parts  = $PreferredBase -split '\.'
    $first  = [int]$parts[0]
    $second = [int]$parts[1]
    $third  = [int]$parts[2]

    $hostAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                     Select-Object -ExpandProperty IPAddress

    $nats = Get-NetNat -ErrorAction SilentlyContinue
    $existingNatPrefixes = if ($nats) { $nats.InternalIPInterfaceAddressPrefix } else { @() }

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $octet = $third + $i
        if ($octet -gt 254) {
            break  # Third octet cannot exceed 254 (255 is broadcast)
        }

        $candidate    = "$first.$second.$octet"
        $hostConflict = $hostAddresses | Where-Object { $_ -like "$candidate.*" }
        $natConflict  = $existingNatPrefixes | Where-Object { $_ -like "$candidate.*" }

        if (-not $hostConflict -and -not $natConflict) {
            if ($i -gt 0) {
                Write-Warning "Preferred subnet $PreferredBase.0/24 was in use. Using $candidate.0/24 instead."
            }
            return $candidate
        }
    }

    $maxOctet = [math]::Min($third + $MaxAttempts - 1, 254)
    Write-Error "Could not find a free subnet in range $first.$second.$third-$maxOctet. Specify -PreferredBase or free up a subnet."
    return $null
}
