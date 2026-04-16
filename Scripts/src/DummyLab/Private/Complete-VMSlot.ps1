# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Complete-VMSlot {
    <#
    .SYNOPSIS
        Marks a reserved VM slot as Ready after successful deployment.
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
                $vm.Status = 'Ready'
            }
        }
        return $state
    }
}
