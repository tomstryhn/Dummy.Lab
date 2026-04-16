# Dummy.Lab - Design Document

**Project:** Dummy.Lab
**Author:** Tom Stryhn
**Status:** v1.0.0
**Last updated:** 2026-04-14

---

## 1. Purpose

A Hyper-V lab automation platform that deploys isolated Windows Server AD lab environments from a single command. Uses golden images (sysprepped VHDXs built from ISOs) as parents for fast differencing disks. Multiple labs can coexist, each fully isolated with its own network.

---

## 2. Design Principles

- **Composable** - create a lab, then add VMs as needed. No rigid scenarios.
- **Pipeline-native** - typed output from every cmdlet; one-line end-to-end pipelines work.
- **Multi-version** - mix Server 2016, 2019, 2022, and 2025 in the same lab.
- **Golden image pattern** - build once, deploy many. Differencing disks make VM creation near-instant.
- **Idempotent** - every cmdlet is safe to re-run. State is detected, not assumed.
- **Isolated by default** - each lab has its own Hyper-V Internal switch and /27 subnet. Labs cannot reach each other. Internet access is on by default and can be disabled at creation (`-NoInternet`) or toggled on running labs (`Set-DLabInternet`).
- **Conflict-safe** - pre-flight validation checks VM names, switch names, IP ranges, and NAT objects.
- **One module** - single `DummyLab` module, no nested modules, no peer modules.
- **Source-to-build** - module functions live as individual files in `src/`. Run `Scripts\Build-DummyLab.ps1` to assemble.
- **Parallel deploys** - file-locked state allows adding multiple VMs simultaneously.
- **Edition-aware** - each ISO exposes all available editions (DC, DC Core, Standard, Standard Core). One ISO, many golden images.
- **Cached discovery** - ISO scan results cached per-file. First scan mounts; subsequent calls are instant.
- **Historical images** - date-stamped golden images allow reproducing specific patch levels for troubleshooting.
- **Central audit trail** - every operation becomes a `DLab.Operation` document, every narrative line becomes a `DLab.Event` in a JSONL log. Both survive lab teardown.

---

## 3. Workflow

### First-time setup

```powershell
# 1. Install (one-liner)
Invoke-Expression (Invoke-WebRequest 'https://raw.githubusercontent.com/tomstryhn/Dummy.Lab/main/Install-Dummy.Lab.ps1' -UseBasicParsing).Content

# 2. Load the module
Import-Module C:\Dummy.Lab\Scripts\Modules\DummyLab\DummyLab.psd1

# 3. Host preflight
Test-DLabHost

# 4. Place ISOs and build golden images
#    Copy ISOs to C:\Dummy.Lab\ISOs\
Find-DLabISO
New-DLabGoldenImage -OSKey WS2025_DC -SkipUpdates
```

### Deploy and manage labs

```powershell
# Create the default lab (named 'Dummy') with a DC
New-DLab

# Or create a named lab
New-DLab -LabName ProdTest

# Add VMs as needed - uses the default lab when -LabName is omitted
Add-DLabVM -Role Server
Add-DLabVM -LabName ProdTest -Role Server -VMName SRV02

# One-line end-to-end composition
Get-DLabGoldenImage -OSKey WS2025_DC | Sort-Object BuildDate -Descending | Select-Object -First 1 |
    New-DLab -LabName Demo |
    Add-DLabVM -Role Server

# Inspect
Get-DLab
Get-DLabVM -LabName ProdTest
Test-DLab -Name ProdTest

# Remove a single VM (cleans up AD object too). Remove-* cmdlets do NOT
# fall back to the default LabName - destructive ops must always name
# their target explicitly.
Remove-DLabVM -LabName ProdTest -Name SRV02 -Confirm:$false

# Tear down entire lab (golden images preserved)
Remove-DLab -Name ProdTest -Confirm:$false
```

For the full cmdlet cheat-sheet, run `.\DLab.ps1 all` from the installed root.

---

## 4. Source-to-Build Workflow

Module source lives in `Scripts\src\DummyLab\`. The assembled module in `Scripts\Modules\DummyLab\` is **build output**.

```text
Scripts\src\DummyLab\
    DummyLab.psd1                     <- Source manifest
    Config\DLab.Defaults.psd1         <- Bundled defaults
    Formats\DummyLab.Format.ps1xml    <- Typed output formatter
    Private\                          <- Internal helpers (one function per file)
    Public\                           <- Exported cmdlets (one function per file)
```

```powershell
.\Scripts\Build-DummyLab.ps1              # Build the module
.\Scripts\Build-DummyLab.ps1 -Validate    # Build, syntax-check, Test-ModuleManifest
.\Scripts\Build-DummyLab.ps1 -Clean       # Remove output dir before building
```

**Rule:** Edit in `src/`, run `Build-DummyLab.ps1`. Never hand-edit `Scripts\Modules\DummyLab\DummyLab.psm1`.

### Configuration

`DummyLab` has a single source of truth for defaults: `Scripts\src\DummyLab\Config\DLab.Defaults.psd1` (built to `Scripts\Modules\DummyLab\DLab.Defaults.psd1`). Every cmdlet that needs a default value reads it via `Get-DLabConfig`, including the golden-image build path.

Do not edit the bundled defaults. Override at install-time by creating either of:

- `%APPDATA%\DummyLab\config.psd1` - user override, picked up automatically.
- `$env:DUMMYLAB_CONFIG` - path to a `.psd1` file, takes precedence over the user override.

The override file only needs the keys you want to change. Unspecified keys fall through to the bundled defaults.

OS-specific data (build numbers, WIM patterns, golden prefixes) lives in `Scripts\Config\OS.Catalog.psd1`. That file is a separate concern and is consumed by `Get-DLabCatalog`, `Find-DLabISO`, and the golden-image build plan.

---

## 5. Supported Operating Systems

Defined in `Scripts\Config\OS.Catalog.psd1`. ISOs are identified by WIM build number (read from ISO metadata, not filename). Each OS version supports multiple editions from a single ISO.

### Edition keys

Each OS version has 4 edition keys plus a short alias that defaults to Datacenter with GUI:

| Alias | Resolves to | Edition |
| ----- | ----------- | ------- |
| `WS2025` | `WS2025-DC` | Datacenter (Desktop Experience) |
| | `WS2025-DC-CORE` | Datacenter (Server Core) |
| | `WS2025-STD` | Standard (Desktop Experience) |
| | `WS2025-STD-CORE` | Standard (Server Core) |

Same pattern for WS2022, WS2019, WS2016. Users type dashes (`-OSKey WS2019-DC-CORE`), internally normalized to underscores for PSD1 compatibility.

### Build numbers

| OS | Build | Editions |
| -- | ----- | -------- |
| Windows Server 2025 | 26100 | 4 (DC, DC-CORE, STD, STD-CORE) |
| Windows Server 2022 | 20348 | 4 |
| Windows Server 2019 | 17763 | 4 |
| Windows Server 2016 | 14393 | 4 |

### WIM image matching

Each catalog entry has a `WIMImageName` wildcard pattern matched against WIM `ImageName`. Wildcards handle naming differences across ISO types (Evaluation ISOs include "Evaluation" in the image name, e.g. "Datacenter Evaluation (Desktop Experience)"). Core editions use `WIMImageExclude` to exclude Desktop Experience images.

### ISO scan caching

First scan mounts each ISO and reads WIM metadata. Results are cached per-ISO in `.scan-cache\` as JSON files, validated by ISO file size + last-modified date. Subsequent calls read from cache (no mounting).

### Adding a new OS

1. Place the ISO in `C:\Dummy.Lab\ISOs\`.
2. Add edition entries to `Scripts\Config\OS.Catalog.psd1` with: `BuildNumber`, `WIMImageName`, `GoldenPrefix`.
3. Run `Find-DLabISO` to verify detection.
4. Run `New-DLabGoldenImage -OSKey <newkey>` to build.

No code changes required.

---

## 6. Network Layout

The shared supernet is `10.74.18.0/23`. One `DLab-NAT` NetNat object covers the entire CIDR. Windows only supports one user-created NetNat, so a single shared NAT serves all segments.

The supernet divides into 16 /27 segments (32 addresses each):

| Segment | CIDR | Role |
| ------- | ---- | ---- |
| 0 | `10.74.18.0/27` | Staging (golden-image builds) |
| 1 | `10.74.18.32/27` | Lab 1 |
| 2 | `10.74.18.64/27` | Lab 2 |
| ... | ... | ... |
| 15 | `10.74.19.224/27` | Lab 15 |

Address layout within each /27 (base = segment network address):

| Offset | Role |
| ------ | ---- |
| base+0 | Network address |
| base+1 | Gateway (host vEthernet adapter) |
| base+2 to base+5 | Domain Controllers (static, 4 slots) |
| base+6 to base+21 | Member Servers (static, 16 slots) |
| base+22 to base+30 | DHCP pool (9 addresses) |
| base+31 | Broadcast |

Static IPs fall below the DHCP pool. No DHCP exclusion ranges are needed.

Each lab gets a dedicated Hyper-V Internal switch named `DLab-{LabName}`, with the host adapter assigned `base+1/27`. The `DLab-Internal` switch serves segment 0 for golden-image builds only and is shared infrastructure, not owned by any lab. Lab switches are isolated from each other. Internet access works because every segment falls within the `DLab-NAT` supernet. A VM with a default gateway sends traffic to the host and out through NAT. A VM without a gateway stays isolated inside its /27.

Internet access is on by default. Disable it at creation time or toggle it on a running lab:

```powershell
# Create a lab with no internet
New-DLab -LabName Isolated -NoInternet

# Toggle internet on a running lab
Set-DLabInternet -LabName Demo -Enabled $true
Set-DLabInternet -LabName Demo -Enabled $false
```

IPv6 is disabled on all lab VMs by default.

---

## 7. Storage Layout

The installer creates this structure automatically under `LabStorageRoot` (default: `C:\Dummy.Lab\`):

```text
C:\Dummy.Lab\
    ISOs\                             <- YOU: drop Windows Server ISOs here
        .scan-cache\                  <- FRAMEWORK: per-ISO scan cache (JSON, auto-managed)
    GoldenImages\                     <- FRAMEWORK: golden VHDXs (read-only, protected)
        WS2019-DC-2026.04.12.vhdx
        WS2019-DC-2026.04.12-unpatched.vhdx
        WS2019-DC-CORE-2026.04.12-unpatched.vhdx
        WS2019-STD-2026.03.15.vhdx    <- Historical image for patch reproduction
        latest-WS2019-DC.txt          <- Pointer to current image
    Labs\                             <- FRAMEWORK: lab instances
        MyLab\                        <- one folder per lab (teardown deletes this)
            Disks\                    <- Differencing disks (tiny, fast)
            VMs\                      <- Hyper-V VM configs
            Operations\               <- Per-lab operation documents
            lab.state.json            <- Lab state tracking
    Events\                           <- FRAMEWORK: central JSONL event log (survives teardown)
        dlab-events-2026-04.jsonl
    Operations\                       <- FRAMEWORK: central operation documents (survives teardown)
        2026-04-14T12-00-00-Demo-<opid>.json
    Reports\                          <- Export-DLabReport output

    [project files]
    DLab.ps1                          <- Cheat-sheet printer
    Install-Dummy.Lab.ps1             <- Installer
    Scripts\
        Build-DummyLab.ps1
        Config\
        GuestScripts\
        Modules\DummyLab\             <- Assembled module (Import-Module this)
        src\DummyLab\                 <- Module source (kept for contributors)
```

Golden images are protected with read-only + deny-delete ACL. `Remove-DLab` only removes `Labs\{LabName}\`; operations and events at the root survive.

---

## 8. Project Structure

```text
Dummy.Lab\
    DLab.ps1                          <- In-terminal cheat-sheet printer
    Install-Dummy.Lab.ps1             <- Bootstrap installer (one-liner entry point)
    CHANGELOG.md
    README.md
    LICENSE
    manifest.json                     <- Machine-readable project structure

    docs\
        DESIGN.md                     <- This document
        CMDLET-MAP.md                 <- Composition diagrams (who calls whom)
        SECURITY.md
        TEST-GUIDE.md
        TROUBLESHOOTING.md

    ISOs\
        README.md                     <- Instructions for adding ISOs

    Scripts\                          <- Framework internals
        Build-DummyLab.ps1            <- Assembles the module
        Config\
            OS.Catalog.psd1           <- OS definitions (build numbers, WIM patterns, prefixes)
            unattend-server.xml       <- Unattend template for Server OS
        GuestScripts\                 <- Scripts that run inside VMs via PowerShell Direct
            Install-DC.ps1            <- DC promotion state machine
            Install-DHCP.ps1          <- DHCP server setup on DC
            Install-MemberServer.ps1  <- Member server domain join
            Add-LabUsers.ps1          <- Optional test OUs, users, groups
            Invoke-GoldenImagePrep.ps1 <- Updates + cleanup + sysprep
        Modules\DummyLab\             <- Assembled module (build output)
        src\DummyLab\                 <- Module source
            DummyLab.psd1
            Config\DLab.Defaults.psd1
            Formats\DummyLab.Format.ps1xml
            Private\*.ps1
            Public\*.ps1
```

---

## 9. Module Surface

`DummyLab` exports 52 public cmdlets across 11 tiers. For the full list and examples, run `.\DLab.ps1 all` or see `docs\CMDLET-MAP.md`.

| Tier | Cmdlets |
| ---- | ------- |
| Configuration and discovery | `Get-DLabConfig`, `Set-DLabConfig`, `Test-DLabConfig`, `Get-DLabCatalog`, `Find-DLabISO`, `Get-DLabISOCatalog` |
| Inventory | `Get-DLab`, `Get-DLabVM`, `Get-DLabNetwork`, `Get-DLabGoldenImage` |
| State | `Get-DLabState`, `Update-DLabState`, `New-DLabVMSlot`, `Complete-DLabVMSlot`, `Remove-DLabVMSlot` |
| Network | `Get-DLabNetworkConfig`, `Get-DLabNAT`, `Find-DLabFreeSubnet`, `New-DLabSwitch`, `Remove-DLabSwitch`, `Set-DLabNAT`, `Remove-DLabNAT` |
| Storage | `New-DLabVHDX`, `Optimize-DLabVHDX`, `New-DLabDifferencingDisk` |
| Preflight | `Test-DLabHost`, `Invoke-DLabPreflight` |
| VM | `New-DLabVM`, `Start-DLabVM`, `Stop-DLabVM`, `Wait-DLabVM`, `New-DLabCheckpoint`, `Test-DLabVM` |
| Guest | `Send-DLabGuestFile`, `Invoke-DLabGuestScript` |
| Golden images | `New-DLabGoldenImage`, `Remove-DLabGoldenImage`, `Protect-DLabGoldenImage`, `Test-DLabGoldenImage`, `Import-DLabGoldenImage`, `Export-DLabGoldenImage` |
| Composition | `New-DLab`, `Add-DLabVM`, `Remove-DLabVM`, `Remove-DLab`, `Test-DLab`, `Set-DLabInternet` |
| Observability | `Get-DLabOperation`, `Get-DLabEventLog`, `Watch-DLabOperation`, `Get-DLabMetrics`, `Export-DLabReport` |

Every cmdlet supports `Get-Help <name> -Full` for detailed help.

---

## 10. Observability

### Events

Every narrative line emitted by the module is a `DLab.Event` written on two channels:

- PowerShell Information stream (channel 6) as a typed `DLab.Event` with tags (`DLab`, `DLab.<Level>`, `DLab.Source.<Cmdlet>`) for live capture.
- Append-only JSONL at `<LabStorageRoot>\Events\dlab-events-<yyyy-MM>.jsonl` for historical analysis.

Levels: `Info`, `Ok`, `Warn`, `Error`, `Step`, `Debug`.

Schema (one JSON line per event):

```json
{
  "t":    "<ISO 8601 local time with offset>",
  "lvl":  "<Level>",
  "src":  "<cmdlet name>",
  "op":   "<OperationId or empty>",
  "msg":  "<human-readable message>",
  "data": { "<arbitrary structured fields>" }
}
```

### Operations

Multi-step cmdlets (`New-DLab`, `Add-DLabVM`, `Remove-DLab`, `Remove-DLabVM`, `New-DLabGoldenImage`, `Remove-DLabGoldenImage`, `Import-DLabGoldenImage`, `Export-DLabGoldenImage`) wrap their work in a `DLab.Operation` record persisted to `<LabStorageRoot>\Operations\<timestamp>-<lab>-<opid>.json`. Each Operation has a list of `DLab.OperationStep` entries with per-step durations and status.

Query via `Get-DLabOperation`, `Get-DLabEventLog`, `Watch-DLabOperation`, `Get-DLabMetrics`, and `Export-DLabReport`.

### Retention

1.0.0 ships with no retention policy. Archive or delete old files under `Events\` and `Operations\` manually to match your audit window.

### Classification rubric (when to use what)

The Event and Operation stores solve different problems. Contributors adding new cmdlets should classify their logging using the rules below so the two stores stay coherent.

**Use a `DLab.Operation` when** the cmdlet has two or more logically distinct phases whose per-phase duration and per-phase outcome matter for forensics. One Operation file per run; each phase is an `Add-DLabOperationStep` / `Complete-DLabOperationStep` pair. Weeks later you can reconstruct "got through phase 3, failed at phase 4 after 02:11".

**Use only `DLab.Event`s (no Operation) when** the cmdlet is a single-shot primitive: one named action, atomic from the user's point of view, with no meaningful sub-steps. These often sit inside a larger wrapping Operation (a `Step` event from the outer Operation correlates them via `OperationId`), but they also work standalone.

**Emit nothing on the happy path when** the cmdlet is read-only with no disk side effect. Reads do not pollute the log. There is one exception: if a read detects corruption or drift (a referenced resource that is missing, a state file that won't parse, a VM in state that Hyper-V doesn't have), emit a `Warn` event so the finding survives past the current console session.

**Event levels carry specific meanings:**

| Level | When | Example |
| ----- | ---- | ------- |
| `Step` | "About to do X" - phase boundary marker | Emitted by `Add-DLabOperationStep` at phase entry |
| `Ok` | A named thing succeeded | "Removed NAT: Prod-NAT" |
| `Info` | Benign context, not a direct action outcome | "Build skipped - reusing existing image" |
| `Warn` | Problem that did not abort; partial success, drift, or corruption | "Corrupt state file skipped", "Undocumented VM matches lab pattern" |
| `Error` | Hard failure, typically paired with a `throw` | "Copy failed: access denied" |
| `Debug` | Developer-only diagnostics, off by default | Cache hits, internal decision points |

**Source attribution.** The `Source` field on every event is the top-level cmdlet that owns the action, not the private helper doing the work. `New-DLab` emits events with `Source='New-DLab'` even when the code that emits them runs inside `Deploy-LabDC`. The `Write-LabLog` forwarder auto-attributes via `Get-PSCallStack`.

**OperationId correlation.** Every event emitted during an Operation's lifetime carries that `OperationId`. Events from standalone primitives leave it empty. `Get-DLabEventLog -OperationId <guid>` reconstructs a full run from the event stream alone.

**Decision test (apply in order):**

1. Does the cmdlet have named phases a future operator would want to see timed separately? Use an Operation.
2. Does it mutate a documented resource or the lab state? Use Events (and an Operation if multi-phase).
3. Is it a single-shot atomic primitive? Events only.
4. Is it read-only? No logging on the happy path; `Warn` only on detected drift.

---

## 11. Golden Image Pipeline

`New-DLabGoldenImage` orchestrates six named phases. Each phase is wrapped in a `DLab.OperationStep` with its own start/complete event, so a failed build tells you exactly which phase broke via `(Get-DLabOperation -Last 1).Steps`.

| Phase | Private helper | Responsibility |
| ----- | -------------- | -------------- |
| Plan     | `Resolve-GoldenImagePlan`    | Normalize OS key, resolve ISO, compute output paths, merge settings, short-circuit if today's image already exists. |
| ApplyWIM | `New-GoldenImageVHDX`        | Create VHDX from ISO (WIM apply + unattend injection + bcdboot). |
| Boot     | `Start-GoldenImageBuildVM`   | Ensure shared `DLab-Internal` switch and `DLab-NAT` exist, create VM on staging segment, start, wait for PowerShell Direct, verify internet when patching. |
| Patch    | `Invoke-GoldenImageUpdate`   | Windows Update rounds with internet re-verification between reboots (skipped when `-SkipUpdates`). |
| Sysprep  | `Invoke-GoldenImageSysprep`  | Run guest cleanup + `sysprep /generalize /oobe /shutdown`; wait for VM to power off. |
| Finalize | `Complete-GoldenImageBuild`  | Remove temp VM/switch/NAT, compact VHDX (`Optimize-VHD`), apply protection ACL, update `latest-<GoldenPrefix>.txt` pointer. |

Shared helper: `Confirm-GoldenImageInternet` (used by Boot and Patch) configures the VM's static IP over PowerShell Direct and verifies outbound reachability.

If internet cannot be established in Boot, the plan flips to the `-unpatched` variant and Patch reports `Skipped`. If an unpatched image already exists for today, the build aborts rather than producing a duplicate.

---

## 12. Server Deployment Flow

### DC (first VM in a lab)

1. Resolve network config, reserve DC slot, create differencing disk (ComputerName in unattend).
2. Boot VM, unattend handles OOBE + admin password.
3. PowerShell Direct: `Install-DC.ps1` state 1 (set static IP, install AD DS role, promote to DC - triggers reboot).
4. Wait for DC to come back with domain credentials.
5. PowerShell Direct: `Install-DC.ps1` state 2 (post-promotion config - DNS forwarder).
6. PowerShell Direct: `Install-DHCP.ps1` (DHCP scope).
7. Verify: NTDS and DNS services running; lab state persisted.

### Member Server (added to existing lab)

1. Reserve VM slot, create differencing disk (ComputerName + domain join in unattend).
2. Boot VM, unattend handles OOBE + rename + domain join automatically.
3. PowerShell Direct: `Install-MemberServer.ps1` (set static IP, verify domain membership).
4. Finalise slot, persist lab state.

---

## 13. Locale Settings

- **UILanguage**: Always `en-US`
- **InputLocale**: Auto-detected from host (e.g. Danish keyboard)
- **UserLocale**: Auto-detected from host (e.g. `da-DK`)
- **SystemLocale**: `en-US`
- **TimeZone**: Auto-detected from host

All configurable via `%APPDATA%\DummyLab\config.psd1` (user override) with `'auto'` as the default. See section 4 for the full override mechanism.

---

## 14. Teardown

```powershell
Remove-DLab -Name ProdTest -Confirm:$false
```

Removes: all VMs, the per-lab `DLab-{LabName}` switch, and lab storage folder (`Labs\ProdTest\`). The shared `DLab-NAT` and `DLab-Internal` switch are not removed (they serve other labs and the staging segment).
Preserves: golden images in `GoldenImages\`, ISOs in `ISOs\`, other labs, operation documents in `Operations\`, event logs in `Events\`.
