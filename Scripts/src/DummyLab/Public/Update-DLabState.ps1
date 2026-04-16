# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Update-DLabState {
    <#
    .SYNOPSIS
        Atomically updates a lab state file with infrastructure or custom changes.
    .DESCRIPTION
        Provides two parameter sets for updating lab state:

        1. Resource-based: -LabName X -Resource Switch|NAT|Storage -Value <string>
           Calls Add-InfraToState to record infrastructure resources.

        2. Script-based: -LabName X -UpdateScript <scriptblock>
           Passes the scriptblock to Update-LabStateLocked for custom logic.

        Uses file locking to ensure parallel deployments don't collide.
        Silent by default; use -PassThru to receive the updated state object.
    .PARAMETER LabName
        Lab name.
    .PARAMETER Resource
        Infrastructure resource type: Switch, NAT, or Storage.
        Only used in Resource parameter set.
    .PARAMETER Value
        Resource value (name or path). Only used in Resource parameter set.
    .PARAMETER UpdateScript
        ScriptBlock that receives the state object and returns the modified state.
        Only used in Script parameter set.
    .PARAMETER PassThru
        Emit the updated state object.
    .EXAMPLE
        Update-DLabState -LabName Pipeline -Resource Switch -Value 'Pipeline-vSwitch'
    .EXAMPLE
        Update-DLabState -LabName Pipeline -UpdateScript {
            param($state)
            $state.Notes = 'Custom deployment'
            return $state
        }
    .EXAMPLE
        Update-DLabState -LabName Pipeline -Resource NAT -Value 'Pipeline-NAT' -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('System.Management.Automation.PSCustomObject')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$LabName,

        [Parameter(Mandatory, ParameterSetName = 'Resource')]
        [ValidateSet('Switch', 'NAT', 'Storage')]
        [string]$Resource,

        [Parameter(Mandatory, ParameterSetName = 'Resource')]
        [string]$Value,

        [Parameter(Mandatory, ParameterSetName = 'Script')]
        [scriptblock]$UpdateScript,

        [switch]$PassThru
    )

    process {
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName

        if (-not (Test-Path $statePath)) {
            Write-Error "Lab state not found: $statePath"
            return
        }

        if (-not $PSCmdlet.ShouldProcess("$LabName", 'Update state')) { return }

        # Build the update script based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'Resource') {
            $script = {
                param($state)
                Add-InfraToState -State $state -Resource $Resource -Value $Value
                return $state
            }
            $displayMsg = "$Resource = $Value"
        } else {
            $script = $UpdateScript
            $displayMsg = "custom update"
        }

        try {
            $updatedState = Update-LabStateLocked -Path $statePath -UpdateScript $script

            Write-DLabEvent -Level Ok -Source 'Update-DLabState' `
                -Message "Updated lab state: $displayMsg" `
                -Data @{ LabName = $LabName; Action = $displayMsg }

            if ($PassThru) {
                $updatedState | Write-Output
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'Update-DLabState' `
                -Message "Failed to update state: $($_.Exception.Message)" `
                -Data @{ LabName = $LabName; Error = $_.Exception.Message }
            throw
        }
    }
}
