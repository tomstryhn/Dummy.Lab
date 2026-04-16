# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabState {
    <#
    .SYNOPSIS
        Returns the raw lab state object for a lab.
    .DESCRIPTION
        Loads lab.state.json for the named lab and returns the raw state
        object. Lower-level than Get-DLab which wraps state in DLab.Lab and
        cross-references live Hyper-V. Use when automation needs the
        as-written state (including next-octet counters, Infrastructure
        records, raw VM entries).
    .PARAMETER LabName
        Lab name. Accepts pipeline from DLab.Lab.
    .EXAMPLE
        Get-DLabState -LabName Pipeline
    .EXAMPLE
        Get-DLabState -LabName Pipeline | ConvertTo-Json -Depth 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$LabName
    )
    process {
        $path = Get-DLabStorePath -Kind LabState -LabName $LabName
        if (-not (Test-Path $path)) {
            Write-Error "Lab state not found: $path"
            return
        }
        Read-LabState -Path $path
    }
}
