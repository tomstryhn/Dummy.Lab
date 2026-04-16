# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabEventLog {
    <#
    .SYNOPSIS
        Reads the Dummy.Lab structured event log.
    .DESCRIPTION
        Parses the JSONL event log files under <storage>/Events/ and emits
        DLab.Event objects. Supports filtering by level, source, operation,
        and time window. Suitable for interactive inspection and for piping
        into external tools (ConvertTo-Json, Out-GridView, etc.).
    .PARAMETER Level
        Filter by level (Info, Ok, Warn, Error, Step, Debug). Multiple values
        allowed.
    .PARAMETER Source
        Filter by the emitting cmdlet or component.
    .PARAMETER OperationId
        Return only events tied to a specific operation.
    .PARAMETER Since
        DateTime or shorthand ('1h', '24h', '7d').
    .PARAMETER Last
        Return the N most recent events after filtering.
    .EXAMPLE
        Get-DLabEventLog -Level Error -Since 24h
    .EXAMPLE
        Get-DLabEventLog -Source New-DLab -Last 20
    .EXAMPLE
        Get-DLabOperation -Status Failed -Last 1 | ForEach-Object {
            Get-DLabEventLog -OperationId $_.OperationId
        }
    #>
    [CmdletBinding()]
    [OutputType('DLab.Event')]
    param(
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step', 'Debug')]
        [string[]]$Level,
        [string]$Source,
        [guid]$OperationId,
        [object]$Since,
        [int]$Last
    )

    # Resolve -Since
    $sinceDate = $null
    if ($Since) {
        if ($Since -is [datetime]) {
            $sinceDate = $Since
        } elseif ($Since -is [string] -and $Since -match '^(\d+)([hdm])$') {
            $n = [int]$matches[1]; $unit = $matches[2]
            $now = Get-Date
            $sinceDate = switch ($unit) {
                'h' { $now.AddHours(-$n) }
                'd' { $now.AddDays(-$n) }
                'm' { $now.AddMinutes(-$n) }
            }
        } else {
            try { $sinceDate = [datetime]$Since } catch {
                Write-Warning "Could not parse -Since value: $Since"
            }
        }
    }

    $eventsDir = Get-DLabStorePath -Kind Events
    if (-not (Test-Path $eventsDir)) {
        Write-Verbose "Event log directory not present: $eventsDir"
        return
    }

    $files = Get-ChildItem -Path $eventsDir -Filter 'dlab-events-*.jsonl' -File -ErrorAction SilentlyContinue |
             Sort-Object Name

    $results = foreach ($f in $files) {
        $lines = Get-Content -Path $f.FullName -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if (-not $line.Trim()) { continue }
            $doc = $null
            try { $doc = $line | ConvertFrom-Json } catch { continue }

            $ts = ConvertFrom-DLabJsonDate $doc.t
            if ($sinceDate -and $ts -and $ts -lt $sinceDate) { continue }
            if ($Level -and $doc.lvl -notin $Level)          { continue }
            if ($Source -and $doc.src -ne $Source)           { continue }
            if ($OperationId -and $doc.op -ne $OperationId.ToString()) { continue }

            [PSCustomObject]@{
                PSTypeName  = 'DLab.Event'
                Timestamp   = $ts
                Level       = $doc.lvl
                Source      = $doc.src
                OperationId = if ($doc.op) { try { [guid]$doc.op } catch { $null } } else { $null }
                Message     = $doc.msg
                Data        = $doc.data
            }
        }
    }

    $sorted = $results | Sort-Object Timestamp -Descending
    if ($Last) { $sorted | Select-Object -First $Last } else { $sorted }
}
