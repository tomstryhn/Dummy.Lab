# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Renders a DLab.Report object as a self-contained HTML document.
# Deliberately single-file with inline CSS so the output is portable -
# email it, drop it on a share, open it directly. No external assets.

function ConvertTo-DLabReportHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Report
    )

    function _EscapeHtml {
        param([string]$s)
        if ($null -eq $s) { return '' }
        return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
    }

    function _StatusBadge {
        param([string]$s)
        $color = switch ($s) {
            'Healthy'   { '#2e7d32' }
            'Degraded'  { '#ed6c02' }
            'Unhealthy' { '#c62828' }
            'Succeeded' { '#2e7d32' }
            'Failed'    { '#c62828' }
            'Running'   { '#0277bd' }
            default     { '#616161' }
        }
        return "<span style='background:$color;color:#fff;padding:2px 8px;border-radius:10px;font-size:0.85em;'>$s</span>"
    }

    $generated = $Report.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')
    $hostName  = _EscapeHtml $Report.Host

    $labsRows = foreach ($lab in $Report.Labs) {
        $domain = _EscapeHtml $lab.DomainName
        $oskey  = _EscapeHtml $lab.OSKey
        $status = _StatusBadge $lab.Status
        "<tr><td>$($lab.Name)</td><td>$domain</td><td>$oskey</td><td>$($lab.VMs.Count)</td><td>$status</td></tr>"
    }

    $vmsRows = foreach ($lab in $Report.Labs) {
        foreach ($vm in $lab.VMs) {
            $state  = _StatusBadge $vm.State
            $status = _StatusBadge $vm.Status
            "<tr><td>$($vm.LabName)</td><td>$($vm.Name)</td><td>$($vm.Role)</td><td>$($vm.IP)</td><td>$state</td><td>$status</td></tr>"
        }
    }

    $imgRows = foreach ($img in $Report.GoldenImages) {
        $latest = if ($img.PointerPath) { '&#10003;' } else { '' }
        $prot   = if ($img.Protected) { '&#10003;' } else { '' }
        "<tr><td>$(_EscapeHtml $img.OSKey)</td><td>$(_EscapeHtml $img.ImageName)</td><td>$($img.SizeGB)</td><td>$(if ($img.BuildDate) { $img.BuildDate.ToString('yyyy-MM-dd') })</td><td>$(if ($img.Patched) { 'Yes' } else { 'No' })</td><td>$prot</td><td>$latest</td></tr>"
    }

    $opRows = foreach ($op in $Report.Operations) {
        $status = _StatusBadge $op.Status
        $when   = if ($op.StartedAt) { $op.StartedAt.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        "<tr><td>$when</td><td>$(_EscapeHtml $op.Kind)</td><td>$(_EscapeHtml $op.Target)</td><td>$status</td><td>$(if ($op.DurationSec) { $op.DurationSec })</td></tr>"
    }

    $kindRows = foreach ($k in $Report.Metrics.ByKind) {
        "<tr><td>$(_EscapeHtml $k.Kind)</td><td>$($k.Total)</td><td>$($k.Succeeded)</td><td>$($k.Failed)</td><td>$($k.AvgSec)</td><td>$($k.MaxSec)</td></tr>"
    }

    $stepRows = foreach ($s in ($Report.Metrics.StepTimings | Select-Object -First 10)) {
        "<tr><td>$(_EscapeHtml $s.StepName)</td><td>$($s.Count)</td><td>$($s.AvgSec)</td><td>$($s.MaxSec)</td><td>$($s.FailedRate)%</td></tr>"
    }

    $healthSection = ''
    if ($Report.Health -and $Report.Health.Count -gt 0) {
        $healthRows = foreach ($h in $Report.Health) {
            $status = _StatusBadge $h.OverallStatus
            "<tr><td>$(_EscapeHtml $h.Target)</td><td>$status</td><td>$($h.Checks.Count)</td><td>$($h.VMHealth.Count)</td></tr>"
        }
        $healthSection = @"
<h2>Health</h2>
<table>
<thead><tr><th>Lab</th><th>Overall</th><th>Checks</th><th>VMs probed</th></tr></thead>
<tbody>
$($healthRows -join "`n")
</tbody>
</table>
"@
    }

    $css = @'
body { font-family: 'Segoe UI', system-ui, sans-serif; margin: 24px; color: #222; }
h1 { border-bottom: 2px solid #0277bd; padding-bottom: 6px; }
h2 { margin-top: 28px; color: #0277bd; }
table { border-collapse: collapse; width: 100%; margin-bottom: 16px; background: #fff; }
th, td { padding: 6px 10px; text-align: left; border-bottom: 1px solid #e0e0e0; }
th { background: #f5f5f5; font-weight: 600; }
tr:hover td { background: #fafafa; }
.meta { color: #666; font-size: 0.9em; }
.empty { color: #999; font-style: italic; }
'@

    @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Dummy.Lab Report - $generated</title>
<style>$css</style></head><body>
<h1>Dummy.Lab Report</h1>
<p class="meta">Host: $hostName &bull; Generated: $generated &bull; Schema: $($Report.SchemaVersion)</p>

<h2>Labs</h2>
<table><thead><tr><th>Name</th><th>Domain</th><th>OS</th><th>VMs</th><th>Status</th></tr></thead>
<tbody>
$(if ($labsRows) { $labsRows -join "`n" } else { '<tr><td colspan="5" class="empty">No labs</td></tr>' })
</tbody></table>

<h2>Virtual Machines</h2>
<table><thead><tr><th>Lab</th><th>Name</th><th>Role</th><th>IP</th><th>State</th><th>Status</th></tr></thead>
<tbody>
$(if ($vmsRows) { $vmsRows -join "`n" } else { '<tr><td colspan="6" class="empty">No VMs</td></tr>' })
</tbody></table>

<h2>Golden Images</h2>
<table><thead><tr><th>OSKey</th><th>Image</th><th>Size (GB)</th><th>Built</th><th>Patched</th><th>Protected</th><th>Latest</th></tr></thead>
<tbody>
$(if ($imgRows) { $imgRows -join "`n" } else { '<tr><td colspan="7" class="empty">No images</td></tr>' })
</tbody></table>

<h2>Operations (recent)</h2>
<table><thead><tr><th>Started</th><th>Kind</th><th>Target</th><th>Status</th><th>Duration (s)</th></tr></thead>
<tbody>
$(if ($opRows) { $opRows -join "`n" } else { '<tr><td colspan="5" class="empty">No operations</td></tr>' })
</tbody></table>

<h2>Metrics - by kind</h2>
<p class="meta">$(_EscapeHtml $Report.Metrics.Scope) / $(_EscapeHtml $Report.Metrics.Window) / Success rate: $(if ($Report.Metrics.SuccessRate) { "$($Report.Metrics.SuccessRate)%" } else { 'n/a' })</p>
<table><thead><tr><th>Kind</th><th>Total</th><th>Succeeded</th><th>Failed</th><th>Avg (s)</th><th>Max (s)</th></tr></thead>
<tbody>
$(if ($kindRows) { $kindRows -join "`n" } else { '<tr><td colspan="6" class="empty">No operations in sample</td></tr>' })
</tbody></table>

<h2>Step timings (top 10 by avg duration)</h2>
<table><thead><tr><th>Step</th><th>Count</th><th>Avg (s)</th><th>Max (s)</th><th>Failed %</th></tr></thead>
<tbody>
$(if ($stepRows) { $stepRows -join "`n" } else { '<tr><td colspan="5" class="empty">No step data</td></tr>' })
</tbody></table>

$healthSection

</body></html>
"@
}
