# Dummy.Lab

**Hyper-V lab automation for Windows Server Active Directory environments.**

Deploy isolated lab networks with Domain Controllers and member servers in minutes using a PowerShell module with 52 composable cmdlets, pipeline-first design, and a central audit trail of every operation and event.

---

## Quick Install

```powershell
$remoteURL = 'https://raw.githubusercontent.com/tomstryhn/Dummy.Lab/main/Install-Dummy.Lab.ps1'
$remoteCode = (Invoke-WebRequest -Uri $remoteURL -UseBasicParsing).Content
Invoke-Expression -Command $remoteCode
```

Installs to `C:\Dummy.Lab\` by default, builds the `DummyLab` module, and places a `DLab.ps1` cheat-sheet printer in the install root.

---

## Quick Start

```powershell
Import-Module DummyLab

# 1. Build a golden image (once per OS)
New-DLabGoldenImage -OSKey WS2025_DC

# 2. Stand up a lab end-to-end in a single pipeline
Get-DLabGoldenImage -OSKey WS2025_DC |
    New-DLab -LabName MyLab |
    Add-DLabVM -Role Server

# 3. Inspect
Get-DLab -Name MyLab
Get-DLabVM -LabName MyLab
Test-DLab -Name MyLab

# 4. Audit
Get-DLabOperation -LabName MyLab | Format-Table StartedAt, Kind, Target, Status, DurationSec
Get-DLabEventLog -Since 1h | Measure-Object
Export-DLabReport -Format Html -IncludeHealth

# 5. Tear down when done (golden images preserved, operation records retained)
Remove-DLab -Name MyLab
```

Every mutating cmdlet is idempotent. Every call records a `DLab.Operation` document with per-step durations, and every narrative line becomes a `DLab.Event` in the month's JSONL log.

---

## What It Does

- **One PowerShell module, 52 public cmdlets.** Automation-friendly surface for building, inspecting, and tearing down labs. Composes through the pipeline.
- **Live off the land.** Every primitive wraps a Microsoft Hyper-V / Network / Storage cmdlet (`New-VM`, `New-VMSwitch`, `New-VHD`, `Checkpoint-VM`, `Optimize-VHD`). Nothing is reimplemented. Wrappers add lab context, structured event emission, and typed output.
- **Golden image pattern.** Build a sysprepped VHDX once, deploy many labs using differencing disks (near-instant VM creation).
- **Multi-version.** Mix Windows Server 2016, 2019, 2022, and 2025 in the same lab by selecting the right catalog key per VM.
- **Isolated by default.** Each lab gets its own Hyper-V Internal switch and /27 subnet. Labs cannot reach each other. Internet access is on by default and can be disabled at creation or toggled on a running lab with `Set-DLabInternet`.
- **Structured observability.** Operations and events go to disk as JSON and JSONL. External systems (SIEM, dashboard, scheduled audit job) pull on their own cadence; no push or broker. Audit trail survives lab teardown.
- **`DLab.ps1` cheat sheet.** Running `DLab.ps1 quickstart|build|lab|health|teardown|report|all` prints the actual module commands for each workflow. It is a reference printer, not a dispatcher.

---

## Background

My work with Windows Server started to take real form around 2014-2016, and the first experiences with Hyper-V come from around that time. Back then it was a different scale entirely. I would often have a dedicated computer running Windows Server, where I could test and experiment. But as I started working more focused with deployments, configurations, and different versions of Windows Server, especially in the defence sector, where development and testing was something you did on your own test environment, I began building scripts and solutions to deploy my environments faster and consistently.

I was very much into PowerShell, but also limited in external access most of the time. Ironically, it was not until I attended some courses several years after I had already built my own `Dummy.local` solutions, that I learned about PSAutoLab through Pluralsight, and when diving deeper, also AutomatedLab. But as I kept developing my own setup, I also kept learning more about PowerShell and automation. In the later years, I have actually returned to my old code on several occasions, because it is a lot easier to use what you know than to learn something new from scratch.

So not long ago I decided to refine the old `Dummy.local` solution and bring it up to date, so I could keep using it for testing baselines, reproducing issues from real-world environments, and finding fixes. After going through old code and hundreds of deployment scripts and functions that I have redesigned way too many times, I rebooted it into Dummy.Lab.

The idea is simple: if you need a Windows Active Directory domain to test on, you spin one up. You need servers? Add them. When you are done, remove it. Because of the golden image design you can keep images at specific patch levels, deploy an environment at a specific point in time, reproduce a problem, test the effect of a patch, and verify a fix before applying it to your operational environment.

This is a tool for any operational or security engineer who likes to dig into things, but would rather save a bit of space and time when deploying.

---

## Requirements

- **Host OS**: Windows 10/11 or Windows Server 2016+
- **Hyper-V**: role enabled, including the Hyper-V PowerShell module
- **PowerShell**: 5.1 or 7, run as Administrator
- **RAM**: 8 GB+ recommended (4 GB minimum for single-VM labs)
- **Disk**: 100 GB free recommended (golden images are ~15 GB each, lab VMs run as differencing disks off them)
- **ISOs**: Windows Server evaluation editions (free from Microsoft) dropped into `C:\Dummy.Lab\ISOs\`

---

## Architecture

See the [documentation](docs/) for:
- [DESIGN.md](docs/DESIGN.md) - module layout, storage, observability pipeline
- [SECURITY.md](docs/SECURITY.md) - credential handling and isolation model
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - common issues and recovery paths

---

## License

CC BY-NC 4.0. See [LICENSE](LICENSE) for details.

---

## Author

Tom Stryhn

GitHub: [tomstryhn/Dummy.Lab](https://github.com/tomstryhn/Dummy.Lab)
