# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.
#
# Module manifest for DummyLab. This is the source manifest. The build script
# copies it to the assembled module directory alongside the concatenated .psm1.

@{
    RootModule        = 'DummyLab.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e2f5b7d1-4c5a-4f2b-9f8c-8a0b6d3e9f11'
    Author            = 'Tom Stryhn'
    CompanyName       = 'Tom Stryhn'
    Copyright         = '(c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.'
    Description       = 'Dummy.Lab - Hyper-V lab automation platform. Composable cmdlets for building, inspecting, and monitoring isolated Windows Server AD lab environments.'

    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Format file for typed output rendering
    FormatsToProcess  = @('DummyLab.Format.ps1xml')

    # All public cmdlets from Scripts/src/DummyLab/Public/*.ps1. Grouped by
    # tier to match docs/CMDLET-MAP.md and DLab.ps1 Show-All.
    FunctionsToExport = @(
        # Configuration and discovery
        'Get-DLabConfig'
        'Set-DLabConfig'
        'Get-DLabCatalog'
        'Find-DLabISO'
        'Get-DLabISOCatalog'
        # Inventory
        'Get-DLab'
        'Get-DLabVM'
        'Get-DLabNetwork'
        'Get-DLabGoldenImage'
        # State primitives
        'Get-DLabState'
        'Update-DLabState'
        'New-DLabVMSlot'
        'Complete-DLabVMSlot'
        'Remove-DLabVMSlot'
        # Network primitives
        'Get-DLabNetworkConfig'
        'Get-DLabNAT'
        'Find-DLabFreeSubnet'
        'New-DLabSwitch'
        'Remove-DLabSwitch'
        'Set-DLabNAT'
        'Remove-DLabNAT'
        # Storage primitives
        'New-DLabVHDX'
        'Optimize-DLabVHDX'
        'New-DLabDifferencingDisk'
        # Host preflight
        'Test-DLabHost'
        'Test-DLabConfig'
        'Invoke-DLabPreflight'
        # VM primitives
        'New-DLabVM'
        'Start-DLabVM'
        'Stop-DLabVM'
        'Wait-DLabVM'
        'New-DLabCheckpoint'
        'Test-DLabVM'
        # Guest execution
        'Send-DLabGuestFile'
        'Invoke-DLabGuestScript'
        # Golden images
        'New-DLabGoldenImage'
        'Remove-DLabGoldenImage'
        'Protect-DLabGoldenImage'
        'Test-DLabGoldenImage'
        'Import-DLabGoldenImage'
        'Export-DLabGoldenImage'
        # Composition
        'New-DLab'
        'Add-DLabVM'
        'Remove-DLabVM'
        'Remove-DLab'
        'Test-DLab'
        'Set-DLabInternet'
        # Observability and reporting
        'Get-DLabOperation'
        'Get-DLabEventLog'
        'Watch-DLabOperation'
        'Get-DLabMetrics'
        'Export-DLabReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('HyperV', 'Lab', 'ActiveDirectory', 'Automation', 'Windows')
            LicenseUri   = 'https://creativecommons.org/licenses/by-nc/4.0/'
            ProjectUri   = 'https://github.com/tomstryhn/Dummy.Lab'
            ReleaseNotes = 'Dummy.Lab 1.0.0. Single DummyLab module with 52 public cmdlets. Full lifecycle (build, deploy, inspect, teardown), central operation + event ledgers, pipeline composition. See CHANGELOG.md for details.'
        }
    }
}
