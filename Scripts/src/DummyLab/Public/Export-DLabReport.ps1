# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Export-DLabReport {
    <#
    .SYNOPSIS
        Produces a snapshot report of Dummy.Lab state.
    .DESCRIPTION
        Aggregates the current view of the Dummy.Lab environment into a
        single report document suitable for archival, audit, or dashboard
        ingestion. Contents:

          - Generation metadata (timestamp, host, schema version)
          - All labs with their VMs and networks
          - All golden images with size and protection status
          - Recent operations (default last 20)
          - Operation metrics (from Get-DLabMetrics)
          - Optional: health check results for every lab (-IncludeHealth,
            takes 10-30s per lab)

        Two output formats:
          - Json (default): machine-readable, shape-stable per the
            SchemaVersion in the output
          - Html: operator-friendly single-page rendering with tables

        Saves to the Reports folder by default; override with -Path.
    .PARAMETER Path
        Output file path. Default: <storage>/Reports/<timestamp>-dlab.(json|html).
    .PARAMETER Format
        Json or Html. Default Json.
    .PARAMETER IncludeHealth
        Also run Test-DLab on every lab and include the results. Slower
        but gives a full health snapshot.
    .PARAMETER OperationLimit
        How many recent operations to include. Default 20.
    .PARAMETER PassThru
        Emit the in-memory report object as well as writing it to disk.
    .EXAMPLE
        Export-DLabReport
    .EXAMPLE
        Export-DLabReport -Format Html -IncludeHealth -PassThru
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [ValidateSet('Json', 'Html')][string]$Format = 'Json',
        [switch]$IncludeHealth,
        [int]$OperationLimit = 20,
        [switch]$PassThru
    )

    # Resolve output path. In both the auto-path and explicit-path cases we
    # must ensure the parent directory exists; otherwise Set-Content throws
    # DirectoryNotFoundException as a non-terminating error, which slips past
    # the try/catch below and leaves the 'Report saved' event claiming
    # success over a phantom file.
    if (-not $Path) {
        $reportsDir = Get-DLabStorePath -Kind Reports
        $ext  = if ($Format -eq 'Html') { 'html' } else { 'json' }
        $Path = Join-Path $reportsDir ("dlab-report-{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $ext)
    }
    $parentDir = Split-Path -Path $Path -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Write-DLabEvent -Level Step -Source 'Export-DLabReport' `
        -Message "Building report to $Path" `
        -Data @{ Path = $Path; Format = $Format; IncludeHealth = [bool]$IncludeHealth }

    # Gather
    $labs    = @(Get-DLab)
    $images  = @(Get-DLabGoldenImage)
    $recent  = @(Get-DLabOperation -Last $OperationLimit)
    $metrics = Get-DLabMetrics
    $health  = @()
    if ($IncludeHealth -and $labs) {
        $health = @($labs | Test-DLab)
    }

    $report = [PSCustomObject]@{
        PSTypeName    = 'DLab.Report'
        SchemaVersion = 1
        GeneratedAt   = Get-Date
        Host          = $env:COMPUTERNAME
        Config        = Get-DLabConfig
        Labs          = $labs
        GoldenImages  = $images
        Operations    = $recent
        Metrics       = $metrics
        Health        = $health
    }

    # Write out. Force Set-Content failures to terminate so the catch below
    # actually fires; otherwise a non-terminating file-system error would
    # slip past and the 'Report saved' event would lie.
    try {
        if ($Format -eq 'Json') {
            $report | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        } else {
            ConvertTo-DLabReportHtml -Report $report | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        }
    } catch {
        Write-DLabEvent -Level Error -Source 'Export-DLabReport' `
            -Message "Report write failed: $($_.Exception.Message)" `
            -Data @{ Path = $Path }
        throw
    }

    Write-DLabEvent -Level Ok -Source 'Export-DLabReport' `
        -Message "Report saved: $Path" `
        -Data @{ Path = $Path; Labs = $labs.Count; Images = $images.Count }

    if ($PassThru) { $report }
}
