# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-LabSwitch {
    <#
    .SYNOPSIS
        Creates an Internal Hyper-V virtual switch for the lab.
        If an Internal switch with the same name already exists, it is reused.
    .PARAMETER SwitchName
        Name of the virtual switch.
    .PARAMETER EnableNAT
        Also configure the host vEthernet adapter and create a NetNat object.
    .PARAMETER NetConfig
        Network config object from Get-LabNetworkConfig.
    .PARAMETER NatName
        Name for the NetNat object (used only when EnableNAT is true).
    .PARAMETER WhatIf
        Dry run.
    #>
    param(
        [string]$SwitchName,
        [bool]$EnableNAT,
        [PSCustomObject]$NetConfig,
        [string]$NatName = "$SwitchName-NAT",
        [switch]$WhatIf
    )

    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "  [~] Switch '$SwitchName' already exists ($($existing.SwitchType)) - reusing." -ForegroundColor DarkGray
    } else {
        if ($WhatIf) {
            Write-Host "  [?] WhatIf: Would create VMSwitch '$SwitchName' (Internal)" -ForegroundColor DarkCyan
        } else {
            Write-Host "  [+] Creating VMSwitch '$SwitchName' (Internal)..." -ForegroundColor Cyan
            New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop | Out-Null
            Write-Host "      Done." -ForegroundColor Green
        }
    }

    if ($EnableNAT) {
        Set-LabNAT -SwitchName $SwitchName -NatName $NatName -NetConfig $NetConfig -WhatIf:$WhatIf
    }
}
