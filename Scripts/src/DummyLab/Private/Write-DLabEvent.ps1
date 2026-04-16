# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Emits a structured event on two channels:
#   1. PowerShell Information stream (channel 6) - for live consumption by UI
#      layers and -InformationVariable capture.
#   2. Append-only JSONL event log on disk - for historical analysis and
#      external dashboard ingestion.
#
# The Information stream carries a typed DLab.Event object with tags so
# downstream renderers can filter, colour, and format without regex parsing.

function Write-DLabEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step', 'Debug')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Message,

        [guid]$OperationId = [guid]::Empty,

        [hashtable]$Data = @{}
    )

    $now = Get-Date
    $evt = [PSCustomObject]@{
        PSTypeName  = 'DLab.Event'
        Timestamp   = $now
        Level       = $Level
        Source      = $Source
        OperationId = if ($OperationId -eq [guid]::Empty) { $null } else { $OperationId }
        Message     = $Message
        Data        = $Data
    }

    # Information stream with typed tags. The tag list lets filters match
    # by level or source without inspecting the message body.
    $tags = @('DLab', "DLab.$Level", "DLab.Source.$Source")
    Write-Information -MessageData $evt -Tags $tags

    # Durable append to JSONL. Failures here must not break the operation
    # we're trying to narrate, so we swallow errors silently.
    try {
        $eventsDir = Get-DLabStorePath -Kind Events
        if (-not (Test-Path $eventsDir)) {
            New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
        }
        $monthFile = Join-Path $eventsDir ("dlab-events-{0}.jsonl" -f $now.ToString('yyyy-MM'))

        # Short-field schema keeps the log compact. See docs/DESIGN.md section 10.
        # Timestamps are written in local time with offset (ISO 8601 'o' format)
        # so filters and display both stay locale-consistent. Operations use the
        # same convention.
        $line = [PSCustomObject]@{
            t    = $now.ToString('o')
            lvl  = $Level
            src  = $Source
            op   = if ($null -eq $evt.OperationId) { '' } else { $evt.OperationId.ToString() }
            msg  = $Message
            data = $Data
        } | ConvertTo-Json -Compress -Depth 10

        Add-Content -Path $monthFile -Value $line -Encoding UTF8
    } catch {
        # Swallow. A broken event log must never break a deployment.
    }
}
