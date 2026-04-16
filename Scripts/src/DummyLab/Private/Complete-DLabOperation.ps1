# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Marks an operation as finished and persists the final state. Accepts
# either 'Succeeded' or 'Failed' status. Computes duration and writes the
# result or error message onto the record.

function Complete-DLabOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$Operation,
        [ValidateSet('Succeeded', 'Failed', 'Cancelled')][string]$Status = 'Succeeded',
        [object]$Result,
        [string]$ErrorMessage
    )

    process {
        $Operation.CompletedAt = Get-Date
        $Operation.DurationSec = [math]::Round(($Operation.CompletedAt - $Operation.StartedAt).TotalSeconds, 2)
        $Operation.Status      = $Status
        if ($null -ne $Result)    { $Operation.Result = $Result }
        if ($ErrorMessage)        { $Operation.Error  = $ErrorMessage }

        if ($Operation.LogPath -and (Test-Path (Split-Path $Operation.LogPath -Parent))) {
            Save-DLabOperationDocument -Operation $Operation
        }

        return $Operation
    }
}
