# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabNetwork {
    <#
    .SYNOPSIS
        Returns the network definition for each Dummy.Lab lab.
    .DESCRIPTION
        One DLab.Network per lab, cross-referenced with live Get-VMSwitch and
        Get-NetNat state. Detects when a switch has been removed out of band
        (SwitchType shows 'Missing').
    .PARAMETER LabName
        Filter to a specific lab.
    .EXAMPLE
        Get-DLabNetwork
    .EXAMPLE
        Get-DLab -Name PipeTest | Get-DLabNetwork
    #>
    [CmdletBinding()]
    [OutputType('DLab.Network')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$LabName
    )

    process {
        $labs = if ($LabName) { Get-DLab -Name $LabName } else { Get-DLab }
        foreach ($lab in $labs) {
            if ($lab.Network) { $lab.Network }
        }
    }
}
