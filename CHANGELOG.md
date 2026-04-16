# Changelog

All notable changes to Dummy.Lab are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/). Versioning follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-04-14

First public release. Dummy.Lab is a Hyper-V lab automation platform for building, inspecting, and monitoring isolated Windows Server AD lab environments.

### Headline

Single-line end-to-end composition:

```powershell
Get-DLabGoldenImage -OSKey WS2025_DC |
    New-DLab -LabName Demo |
    Add-DLabVM -Role Server |
    Add-DLabVM -Role Server
```

Every operation is recorded as a `DLab.Operation` document with per-step durations. Every narrative line is a `DLab.Event` in a JSONL log. Both are central, survive lab teardown, and are queryable via `Get-DLabOperation` / `Get-DLabEventLog`.

### Cmdlet surface (52 public)

**Configuration and discovery (6)**: `Get-DLabConfig`, `Set-DLabConfig`, `Test-DLabConfig`, `Get-DLabCatalog`, `Find-DLabISO`, `Get-DLabISOCatalog`

**Inventory (4)**: `Get-DLab`, `Get-DLabVM`, `Get-DLabNetwork`, `Get-DLabGoldenImage`

**State primitives (5)**: `Get-DLabState`, `Update-DLabState`, `New-DLabVMSlot`, `Complete-DLabVMSlot`, `Remove-DLabVMSlot`

**Network primitives (7)**: `Get-DLabNetworkConfig`, `Get-DLabNAT`, `Find-DLabFreeSubnet`, `New-DLabSwitch`, `Remove-DLabSwitch`, `Set-DLabNAT`, `Remove-DLabNAT`

**Storage primitives (3)**: `New-DLabVHDX`, `Optimize-DLabVHDX`, `New-DLabDifferencingDisk`

**Host preflight (2)**: `Test-DLabHost`, `Invoke-DLabPreflight`

**VM primitives (6)**: `New-DLabVM`, `Start-DLabVM`, `Stop-DLabVM`, `Wait-DLabVM`, `New-DLabCheckpoint`, `Test-DLabVM`

**Guest execution (2)**: `Send-DLabGuestFile`, `Invoke-DLabGuestScript`

**Golden images (6)**: `New-DLabGoldenImage`, `Remove-DLabGoldenImage`, `Protect-DLabGoldenImage`, `Test-DLabGoldenImage`, `Import-DLabGoldenImage`, `Export-DLabGoldenImage`

**Composition (6)**: `New-DLab`, `Add-DLabVM`, `Remove-DLabVM`, `Remove-DLab`, `Test-DLab`, `Set-DLabInternet`

**Observability (5)**: `Get-DLabOperation`, `Get-DLabEventLog`, `Watch-DLabOperation`, `Get-DLabMetrics`, `Export-DLabReport`

### Architecture principles

1. **Live off the land.** Every Tier 2/3 primitive wraps a Microsoft cmdlet (`New-VM`, `New-VMSwitch`, `New-VHD`, `Checkpoint-VM`, `Optimize-VHD`, etc.), enriching with lab context, event emission, and typed output. Nothing is reimplemented.
2. **Composition, not duplication.** High-level actions (`New-DLab`, `Add-DLabVM`, `New-DLabGoldenImage`) are scripts that call primitives. One thing per cmdlet.
3. **Data delivery, not live API.** Events and operations written to disk as JSONL / JSON. SIEMs, log shippers, dashboards pull on their own schedule.
4. **Central audit trail.** Operations and events stored in `<storage>/Operations/` and `<storage>/Events/` respectively. Survives lab teardown. Failed builds, destroyed labs, and orphaned state all leave a retrievable record.
5. **One module.** No peer modules, no NestedModules. Everything inside `DummyLab`.

### User-facing entry points

- **Module** (`Import-Module DummyLab`) is the API. 52 public cmdlets, automation-friendly.
- **`DLab.ps1`** is an in-terminal reference / cheat-sheet printer. Shows the actual DLab cmdlets users should run for each workflow; does not execute them. Topics: `quickstart` (default), `build`, `lab`, `health`, `teardown`, `report`, `all`.

### Defaults worth knowing

- `DomainSuffix` default is `internal` (IANA-reserved 2024 private-use TLD).
- `LabName` defaults to `Dummy`. `New-DLab`, `Add-DLabVM`, and `Test-DLab` all fall back to the configured `LabName` when neither the parameter nor a pipeline input is supplied. `Remove-DLab` and `Remove-DLabVM` keep their mandatory `-Name` / `-LabName` by design - destructive operations must always name their target explicitly.
- Event log at `<storage>/Events/dlab-events-<yyyy-MM>.jsonl` (local-time ISO 8601).
- Operations at `<storage>/Operations/*.json` (central, one file per run).
- Override bundled config via `%APPDATA%\DummyLab\config.psd1` or the `DUMMYLAB_CONFIG` environment variable.

### Known limitations

- Multi-host / cluster deployment is out of scope.
- Non-Windows guests are out of scope.
- No retention policy on the Operations folder yet. Manually archive old files if the folder grows beyond your audit window.

### Requirements

- Windows Server or Windows with the Hyper-V role and the Hyper-V PowerShell module.
- PowerShell 5.1 or PowerShell 7.
- Administrator elevation.
- Minimum 4 GB RAM on the host (8 GB+ recommended for running multi-VM labs).
