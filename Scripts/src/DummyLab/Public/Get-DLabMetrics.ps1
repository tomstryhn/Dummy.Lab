# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabMetrics {
    <#
    .SYNOPSIS
        Aggregates operation and event data into summary metrics.
    .DESCRIPTION
        Computes dashboard-friendly statistics from the persisted operation
        documents and event log: total operations, success rate, per-kind
        breakdown with mean duration, recent failures, step-level timings
        across operations (which stages take longest on average).

        Output is a single DLab.Metrics object. Pipe through ConvertTo-Json
        for dashboard ingestion, or access individual properties for direct
        use.
    .PARAMETER LabName
        Scope metrics to one lab. Omit for a host-wide rollup.
    .PARAMETER Since
        Time window for the sample. DateTime or shorthand ('24h', '7d', '1m').
        Default: everything on disk.
    .EXAMPLE
        Get-DLabMetrics
    .EXAMPLE
        Get-DLabMetrics -Since 7d | ConvertTo-Json -Depth 10 |
            Out-File C:\Dashboard\dlab-metrics.json -Encoding UTF8
    .EXAMPLE
        (Get-DLabMetrics).StepTimings | Format-Table StepName, Count, AvgSec -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('DLab.Metrics')]
    param(
        [string]$LabName,
        [object]$Since
    )

    # Collect operations via existing Get-DLabOperation so filtering is
    # consistent with interactive use.
    $opsParams = @{}
    if ($LabName) { $opsParams['LabName'] = $LabName }
    if ($Since)   { $opsParams['Since']   = $Since }
    $ops = @(Get-DLabOperation @opsParams)

    $total       = $ops.Count
    $running     = @($ops | Where-Object Status -eq 'Running').Count
    $succeeded   = @($ops | Where-Object Status -eq 'Succeeded').Count
    $failed      = @($ops | Where-Object Status -eq 'Failed').Count
    $cancelled   = @($ops | Where-Object Status -eq 'Cancelled').Count
    $completed   = $succeeded + $failed + $cancelled
    $successRate = if ($completed -gt 0) { [math]::Round($succeeded / $completed * 100, 1) } else { $null }

    # Per-kind breakdown (grouped summary)
    $kindStats = foreach ($g in ($ops | Group-Object Kind)) {
        $completedInKind = @($g.Group | Where-Object Status -in 'Succeeded','Failed','Cancelled')
        $durations = @($completedInKind | Where-Object { $null -ne $_.DurationSec } |
                        ForEach-Object { [double]$_.DurationSec })
        [PSCustomObject]@{
            PSTypeName   = 'DLab.KindMetric'
            Kind         = $g.Name
            Total        = $g.Count
            Succeeded    = @($g.Group | Where-Object Status -eq 'Succeeded').Count
            Failed       = @($g.Group | Where-Object Status -eq 'Failed').Count
            Running      = @($g.Group | Where-Object Status -eq 'Running').Count
            AvgSec       = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Average).Average, 2) } else { $null }
            MinSec       = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Minimum).Minimum, 2) } else { $null }
            MaxSec       = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Maximum).Maximum, 2) } else { $null }
        }
    }

    # Step-level timings across all operations. Reveals which deployment
    # stage tends to dominate wall-clock time (usually Deploy DC).
    $allSteps = foreach ($op in $ops) {
        if ($op.Steps) {
            foreach ($s in $op.Steps) { $s }
        }
    }
    $stepStats = foreach ($g in ($allSteps | Group-Object Name)) {
        $durations = @($g.Group | Where-Object { $null -ne $_.DurationSec } |
                        ForEach-Object { [double]$_.DurationSec })
        [PSCustomObject]@{
            PSTypeName = 'DLab.StepMetric'
            StepName   = $g.Name
            Count      = $g.Count
            AvgSec     = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Average).Average, 2) } else { $null }
            MaxSec     = if ($durations.Count -gt 0) { [math]::Round(($durations | Measure-Object -Maximum).Maximum, 2) } else { $null }
            FailedRate = if ($g.Count -gt 0) {
                [math]::Round((@($g.Group | Where-Object Status -eq 'Failed').Count / $g.Count) * 100, 1)
            } else { 0 }
        }
    }

    # Recent failures with enough context to diagnose
    $recentFailures = @($ops | Where-Object Status -eq 'Failed' |
                         Sort-Object StartedAt -Descending | Select-Object -First 10 |
                         ForEach-Object {
                             [PSCustomObject]@{
                                 PSTypeName  = 'DLab.FailureSummary'
                                 OperationId = $_.OperationId
                                 Kind        = $_.Kind
                                 Target      = $_.Target
                                 StartedAt   = $_.StartedAt
                                 DurationSec = $_.DurationSec
                                 Error       = $_.Error
                             }
                         })

    [PSCustomObject]@{
        PSTypeName     = 'DLab.Metrics'
        GeneratedAt    = Get-Date
        Scope          = if ($LabName) { "Lab: $LabName" } else { 'All labs' }
        Window         = if ($Since)   { "Since $Since" } else { 'All time' }
        TotalOps       = $total
        Running        = $running
        Succeeded      = $succeeded
        Failed         = $failed
        Cancelled      = $cancelled
        SuccessRate    = $successRate
        ByKind         = @($kindStats | Sort-Object AvgSec -Descending)
        StepTimings    = @($stepStats | Sort-Object AvgSec -Descending)
        RecentFailures = $recentFailures
    }
}
