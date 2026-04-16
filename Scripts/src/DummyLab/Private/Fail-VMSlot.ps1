# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Fail-VMSlot {
    <#
    .SYNOPSIS
        Marks a reserved VM slot as Failed if deployment errors out.
    .PARAMETER StatePath
        Path to lab.state.json.
    .PARAMETER VMName
        Full VM name (e.g. ProdTest-DC01).
    #>
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string]$VMName
    )
    $null = Update-LabStateLocked -Path $StatePath -UpdateScript {
        param($state)
        foreach ($vm in $state.VMs) {
            if ($vm.Name -eq $VMName) {
                $vm.Status = 'Failed'
            }
        }
        return $state
    }
}
