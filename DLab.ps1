# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -Version 5.1
<#
.SYNOPSIS
    Dummy.Lab reference cheat sheet. Prints the cmdlet commands for common
    operator workflows so users can copy-paste and learn the module API.

.DESCRIPTION
    This script does NOT execute lab operations. It is a reference tool that
    shows the exact Get/New/Add/Remove/Test/Export cmdlets from the DummyLab
    module that perform each task, with example parameters.

    The DummyLab module is the API. Run those cmdlets directly; they return
    typed objects, emit structured events, and pipe cleanly. This script
    exists to help people discover the cmdlets and recall the right syntax.

    Usage:

        .\DLab.ps1             quickstart cheat sheet for common workflows
        .\DLab.ps1 all         every DLab cmdlet grouped by tier
        .\DLab.ps1 build       golden-image workflow
        .\DLab.ps1 lab         lab lifecycle workflow
        .\DLab.ps1 health      health and observability workflow
        .\DLab.ps1 teardown    destructive operations workflow
        .\DLab.ps1 report      reporting workflow

.EXAMPLE
    .\DLab.ps1
    # Prints the quickstart cheat sheet

.EXAMPLE
    .\DLab.ps1 build
    # Prints the golden-image build workflow commands

.NOTES
    For live automation, import the module and use the cmdlets directly:

        Import-Module C:\Dummy.Lab\Scripts\Modules\DummyLab\DummyLab.psd1
        Get-Command -Module DummyLab
        Get-Help <cmdlet> -Full
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('quickstart', 'all', 'build', 'lab', 'health', 'teardown', 'report', 'help')]
    [string]$Topic = 'quickstart'
)

Set-StrictMode -Version Latest

# DLab.ps1 does not execute cmdlets - but if it ever did in the future, it
# could opt into banner-style rendering by setting:
#   $global:DLabRenderToHost = $true
# Write-DLabEvent checks both script-scope and global-scope flags.

function Write-Heading {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "  $('-' * $Text.Length)" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "  # $Text" -ForegroundColor DarkGray
}

function Write-Cmd {
    param([string]$Text)
    Write-Host "    $Text" -ForegroundColor Green
}

function Write-Note {
    param([string]$Text)
    Write-Host "    $Text" -ForegroundColor DarkGray
}

function Show-Banner {
    Write-Host ""
    Write-Host "  Dummy.Lab - Cmdlet Reference" -ForegroundColor Cyan
    Write-Host "  Module: DummyLab  |  51 cmdlets  |  Use 'Get-Help <name> -Full' for detail" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  First, load the module in your session:" -ForegroundColor DarkGray
    Write-Cmd "Import-Module C:\Dummy.Lab\Scripts\Modules\DummyLab\DummyLab.psd1"
    Write-Host ""
}

function Show-Quickstart {
    Show-Banner
    Write-Heading "Quickstart"

    Write-Step "Check host prerequisites (admin, Hyper-V, RAM)"
    Write-Cmd "Test-DLabHost"

    Write-Step "Build a golden image (8-12 min unpatched, 30-60 min with updates)"
    Write-Cmd "New-DLabGoldenImage -OSKey WS2025_DC -SkipUpdates"

    Write-Step "Create a lab with its first Domain Controller"
    Write-Cmd "New-DLab                                  # uses default LabName ('Dummy')"
    Write-Cmd "New-DLab -LabName Demo                    # or name it explicitly"

    Write-Step "Add a member server to the lab"
    Write-Cmd "Add-DLabVM -Role Server                   # targets the default lab"
    Write-Cmd "Add-DLabVM -LabName Demo -Role Server     # or target a specific lab"

    Write-Step "Full pipeline: build + new lab + member server in one line"
    Write-Cmd "Get-DLabGoldenImage -OSKey WS2025_DC | Sort-Object BuildDate -Descending | Select-Object -First 1 |"
    Write-Cmd "    New-DLab -LabName Demo |"
    Write-Cmd "    Add-DLabVM -Role Server"

    Write-Step "Inspect the state"
    Write-Cmd "Get-DLab"
    Write-Cmd "Get-DLabVM -LabName Demo"
    Write-Cmd "Test-DLab -Name Demo"

    Write-Step "Tear down when done"
    Write-Cmd "Remove-DLab -Name Demo -Confirm:`$false"

    Write-Host ""
    Write-Note "More detail:"
    Write-Note "    .\DLab.ps1 build      -  golden image workflow"
    Write-Note "    .\DLab.ps1 lab        -  lab lifecycle"
    Write-Note "    .\DLab.ps1 health     -  health and observability"
    Write-Note "    .\DLab.ps1 teardown   -  destructive operations"
    Write-Note "    .\DLab.ps1 report     -  reporting and audit"
    Write-Note "    .\DLab.ps1 all        -  full cmdlet inventory"
    Write-Host ""
}

function Show-Build {
    Show-Banner
    Write-Heading "Golden Image Workflow"

    Write-Step "Drop Windows Server ISOs into the ISOs folder"
    Write-Note "Copy .iso files to: C:\Dummy.Lab\ISOs\"

    Write-Step "List the OS catalog"
    Write-Cmd "Get-DLabCatalog"

    Write-Step "See what ISOs are available"
    Write-Cmd "Find-DLabISO"
    Write-Cmd "Get-DLabISOCatalog"

    Write-Step "Build a golden image (auto-detects ISO)"
    Write-Cmd "New-DLabGoldenImage -OSKey WS2025_DC -SkipUpdates"
    Write-Cmd "New-DLabGoldenImage -OSKey WS2022_STD"

    Write-Step "List existing golden images"
    Write-Cmd "Get-DLabGoldenImage"
    Write-Cmd "Get-DLabGoldenImage -OSKey WS2025_DC"

    Write-Step "Validate an image"
    Write-Cmd "Get-DLabGoldenImage | Test-DLabGoldenImage"

    Write-Step "Import an image from backup or another host"
    Write-Cmd "Import-DLabGoldenImage -SourcePath D:\Backups\WS2025-DC-2026.04.01.vhdx -AsLatest"

    Write-Step "Export an image for backup"
    Write-Cmd "Get-DLabGoldenImage | Export-DLabGoldenImage -Destination \\backup\share -IncludeMetadata"

    Write-Step "Re-protect an image (read-only + deny-delete ACL)"
    Write-Cmd "Get-DLabGoldenImage | Protect-DLabGoldenImage"

    Write-Step "Remove an old image (blocks if labs depend on it, override with -Force)"
    Write-Cmd "Remove-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2022-DC-2026.03.15.vhdx -WhatIf"
    Write-Host ""
}

function Show-Lab {
    Show-Banner
    Write-Heading "Lab Lifecycle"

    Write-Step "Preflight before creating a lab (checks host + lab namespace)"
    Write-Cmd "Invoke-DLabPreflight -LabName Demo"

    Write-Step "Create a lab with its first DC"
    Write-Cmd "New-DLab -LabName Demo"
    Write-Cmd "New-DLab -LabName Demo -OSKey WS2022_DC -EnableNAT"

    Write-Step "Add VMs"
    Write-Cmd "Add-DLabVM -LabName Demo -Role Server"
    Write-Cmd "Add-DLabVM -LabName Demo -Role Server -VMName SRV02"
    Write-Cmd "Add-DLabVM -LabName Demo -Role DC"

    Write-Step "Pipeline composition from image to member server"
    Write-Cmd "Get-DLabGoldenImage -OSKey WS2025_DC | Select-Object -First 1 |"
    Write-Cmd "    New-DLab -LabName Prod |"
    Write-Cmd "    Add-DLabVM -Role Server |"
    Write-Cmd "    Add-DLabVM -Role Server"

    Write-Step "Inspect"
    Write-Cmd "Get-DLab"
    Write-Cmd "Get-DLab -Name Demo"
    Write-Cmd "Get-DLabVM -LabName Demo"
    Write-Cmd "Get-DLabNetwork -LabName Demo"
    Write-Cmd "Get-DLabState -LabName Demo"

    Write-Step "VM lifecycle (stop, start, wait for ready)"
    Write-Cmd "Stop-DLabVM  -Name Demo-SRV01"
    Write-Cmd "Start-DLabVM -Name Demo-SRV01"
    Write-Cmd "`$cred = [pscredential]::new('Demo\Administrator', (ConvertTo-SecureString 'Qwerty*12345' -AsPlainText -Force))"
    Write-Cmd "Wait-DLabVM -Name Demo-DC01 -Credential `$cred"

    Write-Step "Guest script execution"
    Write-Cmd "Send-DLabGuestFile -Name Demo-SRV01 -Credential `$cred -LocalPath C:\tools\setup.ps1"
    Write-Cmd "Invoke-DLabGuestScript -Name Demo-SRV01 -Credential `$cred -ScriptPath C:\LabScripts\setup.ps1"

    Write-Step "Checkpoints"
    Write-Cmd "New-DLabCheckpoint -VMName Demo-DC01 -SnapshotName 'Before upgrade'"

    Write-Step "Find a free subnet for pre-planning"
    Write-Cmd "Find-DLabFreeSubnet"
    Write-Host ""
}

function Show-Health {
    Show-Banner
    Write-Heading "Health and Observability"

    Write-Step "Host preflight"
    Write-Cmd "Test-DLabHost"
    Write-Cmd "(Test-DLabHost).Checks | Format-Table Name, Status, Message"

    Write-Step "Lab health (runs Test-DLabVM on every VM in the lab)"
    Write-Cmd "Test-DLab -Name Demo"
    Write-Cmd "(Test-DLab -Name Demo).Checks | Format-Table Name, Status, Message"
    Write-Cmd "(Test-DLab -Name Demo).VMHealth | Format-Table Target, OverallStatus"

    Write-Step "Per-VM health probe"
    Write-Cmd "Test-DLabVM -LabName Demo -Name DC01"
    Write-Cmd "Get-DLabVM -LabName Demo | Test-DLabVM"

    Write-Step "Query operations (persistent JSON records)"
    Write-Cmd "Get-DLabOperation -Last 10"
    Write-Cmd "Get-DLabOperation -LabName Demo"
    Write-Cmd "Get-DLabOperation -Status Failed -Since 24h"
    Write-Cmd "Get-DLabOperation -Last 1 | Select-Object -ExpandProperty Steps | Format-Table Name, Status, DurationSec"

    Write-Step "Query events (JSONL log, one line per step/ok/warn/error)"
    Write-Cmd "Get-DLabEventLog -Since 1h"
    Write-Cmd "Get-DLabEventLog -Level Error, Warn"
    Write-Cmd "Get-DLabEventLog -Source New-DLab -Last 20"

    Write-Step "Metrics for dashboards (JSON-friendly)"
    Write-Cmd "Get-DLabMetrics"
    Write-Cmd "(Get-DLabMetrics).ByKind     | Format-Table Kind, Total, Succeeded, Failed, AvgSec"
    Write-Cmd "(Get-DLabMetrics).StepTimings | Sort AvgSec -Descending | Select -First 5"
    Write-Cmd "Get-DLabMetrics | ConvertTo-Json -Depth 10 | Out-File C:\Dashboard\metrics.json"

    Write-Step "Live tail (second console window)"
    Write-Cmd "Watch-DLabOperation"
    Write-Cmd "Watch-DLabOperation -Level Error, Warn"
    Write-Cmd "Get-DLabOperation -Status Running -Last 1 | ForEach-Object { Watch-DLabOperation -OperationId `$_.OperationId }"
    Write-Host ""
}

function Show-Teardown {
    Show-Banner
    Write-Heading "Destructive Operations"

    Write-Step "Always preview with -WhatIf before running destructive cmdlets"

    Write-Step "Remove one VM from a lab"
    Write-Cmd "Remove-DLabVM -LabName Demo -Name SRV01 -WhatIf"
    Write-Cmd "Remove-DLabVM -LabName Demo -Name SRV01 -Confirm:`$false"

    Write-Step "Pipeline remove: all member servers in a lab"
    Write-Cmd "Get-DLabVM -LabName Demo -Role Server | Remove-DLabVM -Confirm:`$false"

    Write-Step "Full lab teardown (VMs, switch, NAT, storage)"
    Write-Cmd "Remove-DLab -Name Demo -WhatIf"
    Write-Cmd "Remove-DLab -Name Demo -Confirm:`$false"
    Write-Cmd "Remove-DLab -Name Demo -KeepStorage -Confirm:`$false   # keeps lab folder"

    Write-Step "VM power control (non-destructive, for completeness)"
    Write-Cmd "Stop-DLabVM  -Name Demo-SRV01"
    Write-Cmd "Stop-DLabVM  -Name Demo-SRV01 -TurnOff -Force   # hard power-off"
    Write-Cmd "Start-DLabVM -Name Demo-SRV01"

    Write-Step "Remove a golden image (blocks if any lab references it)"
    Write-Cmd "Remove-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2022-DC-2026.03.15.vhdx -WhatIf"
    Write-Cmd "Remove-DLabGoldenImage -Path <path> -Force   # overrides the in-use check"

    Write-Step "Note: operations and events survive teardown"
    Write-Note "After Remove-DLab, Get-DLabOperation -LabName <removed> still returns"
    Write-Note "the history - files live in C:\Dummy.Lab\Operations\"
    Write-Host ""
}

function Show-Report {
    Show-Banner
    Write-Heading "Reporting and Audit"

    Write-Step "Point-in-time snapshot (HTML for humans)"
    Write-Cmd "Export-DLabReport -Format Html"
    Write-Cmd "Export-DLabReport -Format Html -IncludeHealth"
    Write-Cmd "Invoke-Item (Get-ChildItem C:\Dummy.Lab\Reports\*.html | Select -Last 1).FullName"

    Write-Step "JSON snapshot (for dashboards / scheduled audit jobs)"
    Write-Cmd "Export-DLabReport -Format Json"
    Write-Cmd "Export-DLabReport -Format Json -PassThru | ConvertTo-Json -Depth 10"

    Write-Step "Operations search (failed runs in the last day)"
    Write-Cmd "Get-DLabOperation -Status Failed -Since 24h | Format-Table Kind, Target, Error"

    Write-Step "Events search (errors in the last hour, with context)"
    Write-Cmd "Get-DLabEventLog -Level Error -Since 1h | Format-Table Timestamp, Source, Message -AutoSize"

    Write-Step "Reconstruct one operation's timeline"
    Write-Cmd "`$op = Get-DLabOperation -Last 1"
    Write-Cmd "`$op.Steps | Format-Table Name, Status, DurationSec, Message"
    Write-Cmd "Get-DLabEventLog -OperationId `$op.OperationId"

    Write-Step "Metrics as JSON for an external dashboard"
    Write-Cmd "Get-DLabMetrics -Since 7d | ConvertTo-Json -Depth 10 | Out-File C:\Dashboard\dlab-weekly.json"

    Write-Step "Persistence layout"
    Write-Note "  C:\Dummy.Lab\Events\dlab-events-YYYY-MM.jsonl   one JSON per line, append-only"
    Write-Note "  C:\Dummy.Lab\Operations\<timestamp>-<lab>-<opid>.json   one file per run"
    Write-Note "  C:\Dummy.Lab\Reports\                          exported HTML/JSON snapshots"
    Write-Note "  Both Events and Operations survive lab teardown."
    Write-Host ""
}

function Show-All {
    Show-Banner
    Write-Heading "All Cmdlets by Tier"

    Write-Step "Tier 0 - Configuration and discovery"
    Write-Cmd "Get-DLabConfig, Set-DLabConfig, Test-DLabConfig, Get-DLabCatalog, Find-DLabISO, Get-DLabISOCatalog"

    Write-Step "Tier 1 - State primitives"
    Write-Cmd "Get-DLabState, Update-DLabState, New-DLabVMSlot, Complete-DLabVMSlot, Remove-DLabVMSlot"

    Write-Step "Tier 2a - Network primitives"
    Write-Cmd "Get-DLabNetwork, Get-DLabNetworkConfig, Get-DLabNAT, Find-DLabFreeSubnet,"
    Write-Cmd "New-DLabSwitch, Remove-DLabSwitch, Set-DLabNAT, Remove-DLabNAT"

    Write-Step "Tier 2b - Storage primitives"
    Write-Cmd "New-DLabVHDX, Optimize-DLabVHDX, New-DLabDifferencingDisk"

    Write-Step "Tier 2c - Preflight"
    Write-Cmd "Test-DLabHost, Test-DLabConfig, Invoke-DLabPreflight"

    Write-Step "Tier 3 - VM lifecycle"
    Write-Cmd "New-DLabVM, Start-DLabVM, Stop-DLabVM, Wait-DLabVM, New-DLabCheckpoint, Test-DLabVM"

    Write-Step "Tier 4 - Guest execution"
    Write-Cmd "Send-DLabGuestFile, Invoke-DLabGuestScript"

    Write-Step "Tier 5 - Golden images"
    Write-Cmd "Get-DLabGoldenImage, New-DLabGoldenImage, Remove-DLabGoldenImage,"
    Write-Cmd "Protect-DLabGoldenImage, Test-DLabGoldenImage,"
    Write-Cmd "Import-DLabGoldenImage, Export-DLabGoldenImage"

    Write-Step "Tier 6 - Lab composition"
    Write-Cmd "Get-DLab, Get-DLabVM, New-DLab, Add-DLabVM,"
    Write-Cmd "Remove-DLabVM, Remove-DLab, Test-DLab"

    Write-Step "Tier 7 - Observability and reporting"
    Write-Cmd "Get-DLabOperation, Get-DLabEventLog, Watch-DLabOperation,"
    Write-Cmd "Get-DLabMetrics, Export-DLabReport"

    Write-Host ""
    Write-Note "See docs/CMDLET-MAP.md for composition diagrams (who calls whom)."
    Write-Note "See docs/DESIGN.md for architecture principles and storage layout."
    Write-Note "Every cmdlet supports Get-Help <name> -Full for detailed help."
    Write-Host ""
}

# Dispatch
switch ($Topic) {
    'quickstart' { Show-Quickstart }
    'all'        { Show-All }
    'build'      { Show-Build }
    'lab'        { Show-Lab }
    'health'     { Show-Health }
    'teardown'   { Show-Teardown }
    'report'     { Show-Report }
    'help'       { Show-Quickstart }
}
