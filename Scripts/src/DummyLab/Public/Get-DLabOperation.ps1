# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabOperation {
    <#
    .SYNOPSIS
        Returns persisted operation records.
    .DESCRIPTION
        Walks the per-lab Operations\ folders and the global Operations\ folder
        and returns DLab.Operation objects. Supports filtering by lab, status,
        kind, and time window.

        In Phase 1 only a few cmdlets write operations; most Get-* cmdlets do
        not. This surface is here so dashboards can query history from day 1
        and Phase 2 only has to emit, not add new query cmdlets.
    .PARAMETER LabName
        Filter to operations tied to a specific lab.
    .PARAMETER Status
        Filter by status (Running, Succeeded, Failed, Cancelled).
    .PARAMETER Kind
        Filter by operation kind (e.g. New-DLab, Add-DLabVM).
    .PARAMETER Since
        Return operations started on or after this time. Accepts a DateTime or
        a shorthand string like '1h', '24h', '7d'.
    .PARAMETER Last
        Return the N most-recent operations after filtering.
    .EXAMPLE
        Get-DLabOperation -Status Failed -Since 24h
    .EXAMPLE
        Get-DLabOperation -LabName PipeTest | Sort-Object StartedAt -Descending | Select-Object -First 5
    #>
    [CmdletBinding()]
    [OutputType('DLab.Operation')]
    param(
        [string]$LabName,
        [ValidateSet('Running', 'Succeeded', 'Failed', 'Cancelled')]
        [string]$Status,
        [string]$Kind,
        [object]$Since,
        [int]$Last
    )

    # Resolve -Since shorthand
    $sinceDate = $null
    if ($Since) {
        if ($Since -is [datetime]) {
            $sinceDate = $Since
        } elseif ($Since -is [string] -and $Since -match '^(\d+)([hdm])$') {
            $n    = [int]$matches[1]
            $unit = $matches[2]
            $now  = Get-Date
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

    # Collect candidate operation files
    $files = @()

    # Per-lab
    $labsRoot = Get-DLabStorePath -Kind Labs
    if (Test-Path $labsRoot) {
        $labDirs = if ($LabName) {
            Get-ChildItem -Path $labsRoot -Directory -Filter $LabName -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -Path $labsRoot -Directory -ErrorAction SilentlyContinue
        }
        # Per-lab operations directory name comes from config (same folder
        # name as the global store, e.g. 'Operations').
        $cfg = Get-DLabConfigInternal
        $opsFolderName = if ($cfg.ContainsKey('OperationsFolderName') -and $cfg.OperationsFolderName) {
            $cfg.OperationsFolderName
        } else {
            'Operations'
        }
        foreach ($d in $labDirs) {
            $opsDir = Join-Path $d.FullName $opsFolderName
            if (Test-Path $opsDir) {
                $files += Get-ChildItem -Path $opsDir -Filter '*.json' -File -ErrorAction SilentlyContinue
            }
        }
    }

    # Global (lab-less operations, e.g. golden image builds)
    if (-not $LabName) {
        $globalOps = Get-DLabStorePath -Kind Operations
        if (Test-Path $globalOps) {
            $files += Get-ChildItem -Path $globalOps -Filter '*.json' -File -ErrorAction SilentlyContinue
        }
    }

    $results = foreach ($f in $files) {
        try {
            $doc = Get-Content $f.FullName -Raw | ConvertFrom-Json
        } catch {
            Write-Verbose "Skipping unreadable op file: $($f.FullName)"
            continue
        }

        # Normalise date fields. ISO 8601 strings (new format), DateTime objects
        # (PS 7 auto-parse), and /Date(xxx)/ legacy strings are all accepted.
        $started   = ConvertFrom-DLabJsonDate $doc.StartedAt
        $completed = ConvertFrom-DLabJsonDate $doc.CompletedAt

        if ($Status    -and $doc.Status -ne $Status) { continue }
        if ($Kind      -and $doc.Kind   -ne $Kind)   { continue }
        if ($sinceDate -and $started    -and $started -lt $sinceDate) { continue }

        [PSCustomObject]@{
            PSTypeName  = 'DLab.Operation'
            OperationId = [guid]$doc.OperationId
            Kind        = $doc.Kind
            Target      = $doc.Target
            Status      = $doc.Status
            StartedAt   = $started
            CompletedAt = $completed
            DurationSec = $doc.DurationSec
            Parameters  = $doc.Parameters
            Steps       = $doc.Steps
            Result      = $doc.Result
            Error       = $doc.Error
            LogPath     = $f.FullName
        }
    }

    $sorted = $results | Sort-Object StartedAt -Descending
    if ($Last) { $sorted | Select-Object -First $Last } else { $sorted }
}
