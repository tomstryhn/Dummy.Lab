# ISO Management

ISOs are not included in Dummy.Lab. You provide your own - the framework discovers them by pattern.

---

## Where to Put ISOs

**Default location**: `C:\Dummy.Lab\ISOs\` (created automatically on first run)

To search additional folders (e.g. an existing ISO library on another drive), override `ExtraISOPaths` in `%APPDATA%\DummyLab\config.psd1`:

```powershell
@{
    ExtraISOPaths = @('D:\ISOs', 'E:\WindowsMedia')
}
```

All paths are searched recursively. ISOs can live anywhere - just configure the paths.

---

## Discovering Available ISOs

```powershell
Find-DLabISO           # auto-detected matches
Get-DLabISOCatalog     # full scan with WIM metadata
```

These cmdlets scan every configured path, match ISOs against the OS catalog patterns, and show what can be built immediately and what's missing.

---

## Supported OS Catalog (default)

| OS Key | Display Name | Build Number | ISO Source |
| ------ | ------------ | ------------ | ---------- |
| WS2025 | Windows Server 2025 | 26100 | [Eval Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025) |
| WS2022 | Windows Server 2022 | 20348 | [Eval Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) |
| WS2019 | Windows Server 2019 | 17763 | [Eval Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019) |
| WS2016 | Windows Server 2016 | 14393 | [Eval Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2016) |

ISOs are identified by WIM build number (read from ISO metadata), not by filename. This works with evaluation, volume license, and renamed ISOs. Each OS version supports multiple editions (Datacenter, Standard, Core, Desktop Experience) from a single ISO.

Microsoft evaluation editions are free, time-limited (180 days), and fully functional for lab use.

---

## Using a Renamed or Custom ISO

If your ISO has a non-standard filename (renamed copy, volume license, internal distribution), bypass auto-discovery with the explicit `-ISO` parameter:

```powershell
New-DLabGoldenImage -OSKey WS2025_DC -ISO 'D:\MyISOs\MyServer2025-Custom.iso'
```

This skips pattern matching entirely and uses the file you specify directly. The `-OS` key still selects the catalog entry (WIM index, naming prefix, etc.).

---

## Adding a New OS

To support a Windows Server version not in the default catalog, add entries to `Config/OS.Catalog.psd1`:

```powershell
WS2019_DC = @{
    BuildNumber      = 17763
    WIMImageName     = 'Windows Server 2019 Datacenter*'
    WIMImageExclude  = ''
    GoldenPrefix     = 'WS2019-DC'
    DefaultMemoryGB  = 4
    DefaultCPU       = 2
}
```

Then run `New-DLabGoldenImage -OSKey WS2019-DC`. No code changes required - the catalog drives everything.
