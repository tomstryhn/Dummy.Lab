# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Creates a new DLab.Operation record and persists it. Used by mutating
# cmdlets to track long-running work. The operation is Running until a
# later Complete-DLabOperation call flips the status. Lab-specific operations
# are written under the lab's folder; lab-less operations (e.g. golden image
# build/export) go into the global <LabStorageRoot>\Operations folder.

function New-DLabOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Target,
        [hashtable]$Parameters = @{},
        [string]$LabName
    )

    $op = [PSCustomObject]@{
        PSTypeName   = 'DLab.Operation'
        OperationId  = [guid]::NewGuid()
        Kind         = $Kind
        Target       = $Target
        Status       = 'Running'
        StartedAt    = Get-Date
        CompletedAt  = $null
        DurationSec  = $null
        Parameters   = $Parameters
        Steps        = @()
        Result       = $null
        Error        = $null
        LogPath      = $null
    }

    # Persist. Operations live under the lab they belong to; lab-less operations
    # (e.g. golden image builds) go into the global Operations folder.
    if ($LabName) {
        $opsDir = Get-DLabStorePath -Kind LabOperations -LabName $LabName
    } else {
        $opsDir = Get-DLabStorePath -Kind Operations
    }
    if (-not (Test-Path $opsDir)) {
        New-Item -ItemType Directory -Path $opsDir -Force | Out-Null
    }

    $fileName = "{0}-{1}.json" -f $op.StartedAt.ToString('yyyyMMdd-HHmmss'), $op.OperationId
    $op.LogPath = Join-Path $opsDir $fileName
    Save-DLabOperationDocument -Operation $op

    return $op
}
