# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Add-InfraToState {
    <#
    .SYNOPSIS
        Records infrastructure resources in the state file as they are created.
        Called via Update-LabStateLocked so parallel processes see updates immediately.
    .PARAMETER State
        The lab state object (passed by Update-LabStateLocked).
    .PARAMETER Resource
        The infrastructure type: Switch, NAT, or Storage.
    .PARAMETER Value
        The resource name or path.
    #>
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][ValidateSet('Switch', 'NAT', 'Storage')][string]$Resource,
        [Parameter(Mandatory)][string]$Value
    )
    switch ($Resource) {
        'Switch'  { $State.Infrastructure.SwitchName  = $Value }
        'NAT'     { $State.Infrastructure.NATName     = $Value }
        'Storage' { $State.Infrastructure.StoragePath = $Value }
    }
    return $State
}
