# Troubleshooting Guide - Dummy.Lab

## Hyper-V Not Available

**Problem**: `Test-HyperVAvailable` fails or "Hyper-V module not found"

**Cause**: Hyper-V role not installed, or running in a VM without nested virtualization enabled

**Fix**:
```powershell
# Install Hyper-V role (Windows 10/11/Server)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All

# Reboot is required
Restart-Computer
```

If you're running Dummy.Lab inside a VM (nested), enable nested virt on the parent:
```powershell
# On the parent Hyper-V host, for your nested VM:
Set-VMProcessor -VMName "YourVM" -ExposeVirtualizationExtensions $true
```

---

## PowerShell Direct Timeout (Wait-LabVMReady)

**Problem**: Deployment hangs at "Waiting for VM to be ready..." for more than 10 minutes

**Cause**: VM still booting, unattend.xml still running, or PowerShell Direct not yet responding

**Fix**:
- Give it time. Default wait is ~10 minutes. Some builds (especially with Windows Update) take longer.
- Open Hyper-V Manager, right-click the VM, select "Connect" to see the console. Watch for:
  - Still at the Windows login screen? Unattend hasn't finished.
  - Blue screen or error? Golden image may be corrupted.
  - Stuck at a specific step? Check the VM event logs via console.
- If it never connects: verify your golden image was built correctly. Re-run `New-DLabGoldenImage -OSKey <YourOSKey>`.

---

## Golden Image Build Fails During Windows Update

**Problem**: `New-DLabGoldenImage` times out or VM loses connection mid-update

**Cause**: Heavy update batches, slow disk I/O, or the unattend timeout is too short

**Fix**:
```powershell
# Build unpatched image for speed
New-DLabGoldenImage -OSKey WS2025_DC -SkipUpdates

# Or allow more time for updates by overriding the default (60 min) in
# %APPDATA%\DummyLab\config.psd1:
#   @{ UpdateTimeoutMin = 240 }
# then rerun:
New-DLabGoldenImage -OSKey WS2025_DC
```

If updates consistently fail, check:
- Available disk space on the host (VHDX expansion can fail silently if full)
- Host CPU and RAM load
- Consider running the build on a less-busy time

---

## NAT Conflict

**Problem**: `New-DLab` or `Ensure-DLabSharedInfrastructure` fails with a message about an existing NetNat, or all lab segments (1-15) are in use

**Cause**: Another NAT rule from a previous install or third-party software is already bound on the host, or all 15 lab slots are occupied

**Fix**:
```powershell
# Check for conflicting NAT rules
Get-NetNat

# Remove a conflicting rule (replace the name with the one shown):
Remove-NetNat -Name 'OldNatName' -Confirm:$false

# Check which /27 segments are active (one host adapter per lab)
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -like 'vEthernet (DLab-*' } |
    Format-Table InterfaceAlias, IPAddress, PrefixLength

# Free a segment by tearing down a lab
Remove-DLab -Name UnusedLab -Confirm:$false
```

Windows only supports one user-created NetNat. `DLab-NAT` covers `10.74.18.0/23` and serves all 15 lab segments. If a different NetNat already exists on the host, remove it before creating the first lab.

---

## State File Lock Contention

**Problem**: "Could not acquire state lock" error and deployment stops

**Cause**: Another DummyLab cmdlet (`New-DLab`, `Add-DLabVM`, `Remove-DLabVM`, or similar) is running against the same lab, or a previous run crashed mid-write to `lab.state.json` and left a stale `.lock` file

**Fix**:
```powershell
# 1. Check if another deployment is still running (check Task Manager for powershell.exe)

# 2. If no other process is running, the lock is stale - delete it:
Remove-Item 'C:\Dummy.Lab\Labs\YourLab\lab.state.json.lock' -Force

# 3. Retry your deployment
```

The lock timeout is 30 seconds. If another deployment is legitimately running, wait for it to finish before retrying.

---

## VM Doesn't Domain Join (Member Server)

**Problem**: Member server deployment completes but VM shows "not a domain member" or DNS lookup fails

**Cause**: DC not fully ready when the member tries to join; AD DS or DNS still initializing

**Fix**:
```powershell
# The deployment script has built-in retry logic, but if it fails:
# 1. Wait 2-3 minutes for the DC to be fully ready (check Services in Hyper-V console)
# 2. Re-run the add command:

Add-DLabVM -LabName Dummy -Role Server -VMName SRV01
```

Verify the DC is ready by checking:
- AD DS service is running
- DNS service is running
- DHCP is active on the DC

---

## VHDX Path Not Found / Golden Image Missing

**Problem**: "No golden image found for WS2025" or similar error

**Cause**: Golden image never built, or `LabStorageRoot` is pointing to wrong location

**Fix**:
```powershell
# List available golden images
Get-DLabGoldenImage

# List supported OS keys
Get-DLabCatalog

# Scan ISOs to see which OS keys can be built
Find-DLabISO
Get-DLabISOCatalog

# Build the missing image
New-DLabGoldenImage -OSKey WS2025_DC
```

Verify the effective config has the correct `LabStorageRoot`:
```powershell
(Get-DLabConfig).LabStorageRoot
```

To override, edit `%APPDATA%\DummyLab\config.psd1`:
```powershell
@{ LabStorageRoot = 'D:\Dummy.Lab' }
```

---

## Installation Script Fails

**Problem**: `Install-Dummy.Lab.ps1` download fails or extraction errors

**Cause**: Network connectivity, GitHub API rate limiting, or antivirus blocking

**Fix**:
```powershell
# Download ZIP manually from GitHub
# https://github.com/tomstryhn/Dummy.Lab/archive/refs/heads/main.zip

# Extract to C:\Dummy.Lab

# Then run the build manually:
cd C:\Dummy.Lab
.\Scripts\Build-DummyLab.ps1 -Validate
```

If antivirus blocks the download, whitelist the project folder before running the installer again.
