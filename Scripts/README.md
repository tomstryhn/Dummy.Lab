# Scripts

This folder contains the Dummy.Lab framework internals.

| Folder/File | Purpose |
| ----------- | ------- |
| `Build-DummyLab.ps1` | Rebuilds the `DummyLab` module from `src\DummyLab\`. Run with `-Validate` to syntax-check and `Test-ModuleManifest` the output. |
| `Config/` | Shared OS catalog (`OS.Catalog.psd1`) and the Windows unattend template. Module defaults live in `src\DummyLab\Config\DLab.Defaults.psd1`, not here. |
| `GuestScripts/` | PowerShell scripts that run inside VMs via PowerShell Direct. |
| `Modules/DummyLab/` | Built module output - this is what `Import-Module` loads. |
| `src/DummyLab/` | Module source (manifest, public/private functions, format views, bundled defaults). |

## Modifying the module

Edit files in `src\DummyLab\Public\` or `src\DummyLab\Private\`, then run:

```powershell
.\Scripts\Build-DummyLab.ps1 -Validate
```

from the project root. The build concatenates every `.ps1` under `Private/` and `Public/` into `Scripts\Modules\DummyLab\DummyLab.psm1`, copies the manifest, format file, and bundled defaults, and optionally runs syntax and manifest validation.

## Overriding config

Do not edit `DLab.Defaults.psd1` directly. Override specific keys at install-time via:

- `%APPDATA%\DummyLab\config.psd1` (per-user override)
- `$env:DUMMYLAB_CONFIG` (path to a `.psd1` file, takes precedence)

See `docs\DESIGN.md` section 4 for the full override mechanism.
