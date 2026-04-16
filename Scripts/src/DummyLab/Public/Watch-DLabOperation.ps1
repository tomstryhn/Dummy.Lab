# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Watch-DLabOperation {
    <#
    .SYNOPSIS
        Tails the Dummy.Lab event log in real time.
    .DESCRIPTION
        Polls the current month's event log file for new entries and renders
        them as they arrive. Useful for watching long-running operations
        (New-DLab, Add-DLabVM, New-DLabGoldenImage) from a second shell
        without tailing the raw JSONL yourself.

        Filter by OperationId to see only one operation's narrative, by
        Level to focus on errors, or by Source to watch one cmdlet.

        Press Ctrl+C to stop. When -OperationId is specified, automatically
        exits when the operation reaches a terminal status (Succeeded, Failed,
        Cancelled).
    .PARAMETER OperationId
        Follow one specific operation. Exits when the operation completes.
    .PARAMETER Level
        Filter to specific event levels. Multiple values allowed.
    .PARAMETER Source
        Filter to events from a specific cmdlet.
    .PARAMETER LabName
        Filter to events associated with an operation targeting this lab.
    .PARAMETER ShowPast
        Seconds of history to render before starting the live tail. Default 60.
    .PARAMETER PollSeconds
        How often to check for new events. Default 1.
    .EXAMPLE
        Watch-DLabOperation
    .EXAMPLE
        # From a second shell, tail a running New-DLab by operation id
        $op = Get-DLabOperation -Status Running -Last 1
        Watch-DLabOperation -OperationId $op.OperationId
    .EXAMPLE
        Watch-DLabOperation -Level Error, Warn
    #>
    [CmdletBinding()]
    param(
        [guid]$OperationId,

        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step', 'Debug')]
        [string[]]$Level,

        [string]$Source,
        [string]$LabName,

        [int]$ShowPast    = 60,
        [int]$PollSeconds = 1
    )

    $eventsDir = Get-DLabStorePath -Kind Events
    if (-not (Test-Path $eventsDir)) {
        New-Item -ItemType Directory -Path $eventsDir -Force | Out-Null
    }

    # Walk through candidate month files starting with the current month.
    # If the watcher is started near midnight on month-boundary, also tail
    # the previous month briefly so early minutes are not missed.
    $currentMonthFile = Join-Path $eventsDir ("dlab-events-{0}.jsonl" -f (Get-Date -Format 'yyyy-MM'))

    # If we are filtering by LabName, we need a fast lookup of which OperationIds
    # belong to that lab. Rebuild the set occasionally in case new operations
    # are added during the watch.
    $labOpIds = $null
    if ($LabName) {
        $labOpIds = @{}
        foreach ($op in (Get-DLabOperation -LabName $LabName)) {
            $labOpIds[$op.OperationId.ToString()] = $true
        }
    }

    function _Render {
        param([PSCustomObject]$Evt)
        $ts    = if ($Evt.Timestamp) { $Evt.Timestamp.ToString('HH:mm:ss') } else { '--:--:--' }
        $tag   = switch ($Evt.Level) {
            'Ok'    { '+' }
            'Step'  { '-' }
            'Info'  { '~' }
            'Warn'  { '!' }
            'Error' { 'X' }
            'Debug' { 'd' }
            default { '?' }
        }
        $color = switch ($Evt.Level) {
            'Ok'    { 'Green' }
            'Step'  { 'Cyan' }
            'Info'  { 'Gray' }
            'Warn'  { 'Yellow' }
            'Error' { 'Red' }
            'Debug' { 'DarkGray' }
            default { 'White' }
        }
        Write-Host ("  [{0}] {1}  {2,-24} {3}" -f $tag, $ts, $Evt.Source, $Evt.Message) -ForegroundColor $color
    }

    function _EventMatches {
        param([PSCustomObject]$Evt)
        if ($OperationId -and ($Evt.OperationId -ne $OperationId)) { return $false }
        if ($Level      -and ($Evt.Level -notin $Level))           { return $false }
        if ($Source     -and ($Evt.Source -ne $Source))            { return $false }
        if ($LabName    -and $labOpIds -and -not $labOpIds.ContainsKey(($Evt.OperationId.ToString()))) { return $false }
        return $true
    }

    Write-Host ""
    Write-Host "  Watching $eventsDir (Ctrl+C to stop)" -ForegroundColor DarkGray
    if ($OperationId) { Write-Host "  OperationId: $OperationId (auto-exit on completion)" -ForegroundColor DarkGray }
    Write-Host ""

    # Prime the cursor: read existing file up to the "-ShowPast seconds ago" point
    $lastLen = 0
    if (Test-Path $currentMonthFile) {
        $cutoff = (Get-Date).AddSeconds(-$ShowPast)
        $recent = Get-DLabEventLog -Since $cutoff
        # Filter and render in chronological order
        $recent | Sort-Object Timestamp | ForEach-Object {
            if (_EventMatches $_) { _Render $_ }
        }
        $lastLen = (Get-Item $currentMonthFile).Length
    }

    $seenCompleted = $false
    try {
        while (-not $seenCompleted) {
            Start-Sleep -Seconds $PollSeconds

            # Month file might rotate during the watch if we cross month-end.
            $currentMonthFile = Join-Path $eventsDir ("dlab-events-{0}.jsonl" -f (Get-Date -Format 'yyyy-MM'))
            if (-not (Test-Path $currentMonthFile)) { continue }

            $size = (Get-Item $currentMonthFile).Length
            if ($size -eq $lastLen) { continue }

            # Read new bytes only. Fall back to full read if the file shrank
            # (manual truncation - rare, but don't crash).
            $stream = [System.IO.File]::Open($currentMonthFile, 'Open', 'Read', 'ReadWrite')
            try {
                if ($size -lt $lastLen) { $lastLen = 0 }
                $null = $stream.Seek($lastLen, 'Begin')
                $reader = New-Object System.IO.StreamReader($stream)
                $new = $reader.ReadToEnd()
                $reader.Dispose()
            } finally {
                $stream.Close()
            }
            $lastLen = $size

            foreach ($line in $new -split "`r?`n") {
                if (-not $line.Trim()) { continue }
                $doc = $null
                try { $doc = $line | ConvertFrom-Json } catch { continue }
                $ts = ConvertFrom-DLabJsonDate $doc.t

                $evt = [PSCustomObject]@{
                    PSTypeName  = 'DLab.Event'
                    Timestamp   = $ts
                    Level       = $doc.lvl
                    Source      = $doc.src
                    OperationId = if ($doc.op) { try { [guid]$doc.op } catch { $null } } else { $null }
                    Message     = $doc.msg
                    Data        = $doc.data
                }

                if (_EventMatches $evt) { _Render $evt }

                # Auto-exit when the watched operation completes
                if ($OperationId -and $evt.OperationId -eq $OperationId) {
                    # The final event for an operation is always an Ok or Error
                    # emitted after Complete-DLabOperation has written the record.
                    # Check the operation's Status on disk rather than inferring
                    # from event level, since step failures also emit Error.
                    $op = Get-DLabOperation | Where-Object OperationId -eq $OperationId | Select-Object -First 1
                    if ($op -and $op.Status -in 'Succeeded', 'Failed', 'Cancelled') {
                        Write-Host ""
                        Write-Host ("  Operation {0} ({1}, {2}s)" -f $op.Status, $op.Kind, $op.DurationSec) `
                                   -ForegroundColor $(if ($op.Status -eq 'Succeeded') { 'Green' } else { 'Red' })
                        $seenCompleted = $true
                        break
                    }
                }
            }
        }
    } catch [System.Management.Automation.PipelineStoppedException] {
        # Ctrl+C
    }
}
