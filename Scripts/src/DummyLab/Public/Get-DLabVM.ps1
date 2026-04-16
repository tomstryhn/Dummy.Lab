# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabVM {
    <#
    .SYNOPSIS
        Returns VMs that belong to Dummy.Lab labs.
    .DESCRIPTION
        Walks the lab state files and returns a DLab.VM per entry, enriched
        with live Hyper-V state via Get-VM. Does not list VMs that are not
        tracked in a lab state file; use Get-VM for that. This is intentional
        so "my lab's VMs" is a crisp concept.
    .PARAMETER LabName
        Filter to VMs belonging to a specific lab.
    .PARAMETER Name
        Filter by VM name (supports wildcards, matches either full name or short name).
    .PARAMETER Role
        Filter by role (DC or Server).
    .PARAMETER State
        Filter by live Hyper-V state (Running, Off, etc.).
    .EXAMPLE
        Get-DLabVM
    .EXAMPLE
        Get-DLab -Name PipeTest | Get-DLabVM
    .EXAMPLE
        Get-DLabVM -Role DC | Start-DLabVM    # (when Start-DLabVM lands in Phase 2)
    #>
    [CmdletBinding()]
    [OutputType('DLab.VM')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]  # allow DLab.Lab.Name to bind
        [string]$LabName,

        [string]$VMName = '*',

        [ValidateSet('DC', 'Server')]
        [string]$Role,

        [string]$State
    )

    process {
        $labs = if ($LabName) { Get-DLab -Name $LabName } else { Get-DLab }
        foreach ($lab in $labs) {
            foreach ($vm in $lab.VMs) {
                if ($VMName -ne '*' -and $vm.Name -notlike $VMName -and $vm.ShortName -notlike $VMName) { continue }
                if ($Role    -and $vm.Role  -ne $Role)   { continue }
                if ($State   -and $vm.State -ne $State)  { continue }
                $vm
            }
        }
    }
}
