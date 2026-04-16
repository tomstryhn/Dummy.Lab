# Security Model - Dummy.Lab

This document covers the security design decisions in Dummy.Lab. Read this before deploying labs on networks you care about.

## Default Credentials

| Credential | Value | Purpose |
|---|---|---|
| **Administrator Password** | `Qwerty*12345` | All VMs (golden image, DC, member servers) |
| **Domain Name** | `{LabName}.internal` | AD domain (e.g., `Dummy.internal`) |

The default password is intentionally simple. This is a lab tool, not a vault. Override it immediately if your lab touches any network outside localhost:

```powershell
# In %APPDATA%\DummyLab\config.psd1 (user override):
@{
    AdminPassword = 'Your$SecurePasswordHere'
}

# Or at runtime:
New-DLab -LabName Demo -AdminPassword 'Your$SecurePasswordHere'
```

## Network Isolation

Each lab runs on its own Hyper-V Internal switch (`DLab-{LabName}`). Labs cannot reach each other, and external traffic cannot reach lab VMs.

A single shared `DLab-NAT` covers the full `10.74.18.0/23` supernet. VMs that have a default gateway configured can reach the internet via NAT. VMs without a gateway stay isolated inside their /27 segment.

Internet access is on by default. Control it at creation time or on a running lab:

```powershell
# Create a lab with no internet access
New-DLab -LabName Isolated -NoInternet

# Disable or enable internet on a running lab
Set-DLabInternet -LabName Demo -Enabled $false
Set-DLabInternet -LabName Demo -Enabled $true
```

If your lab does not need internet access, pass `-NoInternet` to `New-DLab`. No gateway will be configured on the DC or distributed to clients via DHCP.

## Golden Image Protection

Golden VHDX files are protected after build:

- **Read-only**: `icacls` set to `(DENY EVERYONE MODIFY, WRITE, DELETE)`
- **How**: `Protect-GoldenImage` runs at end of build
- **What it does**: Prevents accidental or malicious modification of the master image
- **What it doesn't do**: Doesn't prevent privileged users from taking ownership or a hypervisor host from bypassing the OS. Use file system permissions or separate storage if you need cryptographic protection.

## PowerShell Direct

All VM configuration uses PowerShell Direct (PS Direct):

- **No network exposure**: Communication is local, via the Hyper-V socket
- **No WinRM overhead**: Direct code execution in the VM via hypervisor
- **Isolation**: Cannot be intercepted by network tools
- **Failure mode**: If a VM doesn't respond to PS Direct, the deployment waits and retries. Check the Hyper-V Manager console if it hangs beyond the timeout.

## Unattend.xml and Admin Password

Windows unattend automation stores the admin password in plaintext in `Unattend.xml`:

```xml
<Password>Qwerty*12345</Password>
```

This is standard Windows automation practice. The unattend file is embedded in the VHDX before the VM boots. If you extract the VHDX (e.g., mount it on another machine), the password is readable.

**Implications**: Treat VHDX files (especially in the golden image store) as sensitive. If the VHDX is compromised, the VM's admin password is known.

## Production Use Warning

Dummy.Lab is a lab tool. Do not use it for production workloads or anything connected to untrusted networks without:

1. Changing all default passwords immediately
2. Using `-NoInternet` on `New-DLab` or `Set-DLabInternet -Enabled $false` if external connectivity is not needed
3. Validating the network isolation is appropriate for your threat model
4. Reviewing golden image contents before deployment (no malware, no backdoors)

If you deploy a lab on a network with other systems, treat the lab like any other trusted infrastructure. Isolation is not a substitute for credential security.

## Reporting Security Issues

Found a vulnerability? Report it responsibly:

- **GitHub Issues**: https://github.com/tomstryhn/Dummy.Lab/issues (public, for non-sensitive issues)
- **Email**: Contact via GitHub (for sensitive issues)

Include reproduction steps, affected version, and impact. Do not publish exploits publicly before the maintainer has a chance to patch.
