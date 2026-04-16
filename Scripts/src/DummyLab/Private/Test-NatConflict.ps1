# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-NatConflict {
    <#
    .SYNOPSIS
        Checks for conflicting NetNat objects when NAT is requested.
    .PARAMETER NatName
        Planned NAT object name.
    .PARAMETER NetworkBase
        Planned subnet base.
    #>
    param(
        [string]$NatName,
        [string]$NetworkBase
    )

    $prefix  = "$NetworkBase.0/24"
    $byName  = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    $byRange = Get-NetNat -ErrorAction SilentlyContinue |
               Where-Object { $_.InternalIPInterfaceAddressPrefix -eq $prefix }

    if ($byName) {
        if ($byName.InternalIPInterfaceAddressPrefix -eq $prefix) {
            return New-ValidationResult -Check 'NatConflict' -Passed $true `
                -Message "NetNat '$NatName' already exists with correct prefix - will be reused."
        }
        return New-ValidationResult -Check 'NatConflict' -Passed $false `
            -Message "NetNat '$NatName' exists with a DIFFERENT prefix ($($byName.InternalIPInterfaceAddressPrefix))." `
            -Detail "Remove it: Remove-NetNat -Name '$NatName'"
    }

    if ($byRange) {
        return New-ValidationResult -Check 'NatConflict' -Passed $false `
            -Message "A different NAT object ($($byRange.Name)) already covers $prefix." `
            -Detail 'Only one NAT per prefix is allowed. Remove it or choose a different subnet.'
    }

    New-ValidationResult -Check 'NatConflict' -Passed $true `
        -Message "No conflicting NAT objects for $prefix."
}
