# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Resolves well-known storage paths from the merged config.
# All callers go through this so path layout is centralised. Every folder
# name (Labs, GoldenImages, Events, Operations, Reports, ISOs) is sourced
# from DLab.Defaults.psd1 and can be overridden via the user config without
# touching code.

function Get-DLabStorePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Root', 'Labs', 'Images', 'Events', 'Operations', 'Reports', 'LabDir', 'LabState', 'LabOperations')]
        [string]$Kind,

        [string]$LabName
    )

    $cfg = Get-DLabConfigInternal
    $root = $cfg.LabStorageRoot

    # OperationsFolderName was added in 1.0.0 as a first-class config key.
    # Fall back to 'Operations' if an older user-override psd1 doesn't set it.
    $operationsFolder = if ($cfg.ContainsKey('OperationsFolderName') -and $cfg.OperationsFolderName) {
        $cfg.OperationsFolderName
    } else {
        'Operations'
    }

    switch ($Kind) {
        'Root'          { return $root }
        'Labs'          { return (Join-Path $root $cfg.LabsFolderName) }
        'Images'        { return (Join-Path $root $cfg.ImageStoreName) }
        'Events'        { return (Join-Path $root $cfg.EventsFolderName) }
        'Operations'    { return (Join-Path $root $operationsFolder) }
        'Reports'       { return (Join-Path $root $cfg.ReportsFolderName) }
        'LabDir'        {
            if (-not $LabName) { throw "LabName is required for LabDir." }
            return (Join-Path (Join-Path $root $cfg.LabsFolderName) $LabName)
        }
        'LabState'      {
            if (-not $LabName) { throw "LabName is required for LabState." }
            return (Join-Path (Join-Path (Join-Path $root $cfg.LabsFolderName) $LabName) 'lab.state.json')
        }
        'LabOperations' {
            if (-not $LabName) { throw "LabName is required for LabOperations." }
            return (Join-Path (Join-Path (Join-Path $root $cfg.LabsFolderName) $LabName) $operationsFolder)
        }
    }
}
