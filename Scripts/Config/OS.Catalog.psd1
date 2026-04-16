# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.
#
# Dummy.Lab - OS Image Catalog
# Maps OS keys to WIM metadata, golden image naming, and defaults.
# Consumed by Get-DLabCatalog, Find-DLabISO, and the golden-image build
# plan in Resolve-GoldenImagePlan.
#
# BuildNumber  : Extracted from WIM Version field (10.0.BuildNumber.x format).
#                Reliable across ISO types (Evaluation, Volume License, etc).
# WIMImageName : Wildcard match against WIM ImageName. Wildcards (*) allow
#                matching across ISO types (Evaluation ISOs add "Evaluation"
#                to the image name, e.g. "Datacenter Evaluation (Desktop Experience)").
# WIMImageExclude : If set, images matching this pattern are excluded.
#                Used for Core variants to exclude "Desktop Experience" images.
# ImageIndex   : Fallback WIM index if WIMImageName doesn't match.
# AliasFor     : If set, this key resolves to another key. Lets you type
#                '-OS WS2019' and get Datacenter Desktop Experience.
#
# Naming convention (underscores required by PSD1 format):
#   WS2019          = alias -> WS2019_DC (default: Datacenter Desktop Experience)
#   WS2019_DC       = Datacenter (Desktop Experience / GUI)
#   WS2019_DC_CORE  = Datacenter (Server Core / no GUI)
#   WS2019_STD      = Standard (Desktop Experience / GUI)
#   WS2019_STD_CORE = Standard (Server Core / no GUI)
#
# Users can type dashes on the command line (-OS WS2019-DC-CORE)
# and they'll be normalized to underscores automatically.

@{
    # =================================================================
    #  Windows Server 2025
    # =================================================================
    WS2025 = @{
        AliasFor = 'WS2025_DC'
    }
    WS2025_DC = @{
        DisplayName      = 'Windows Server 2025 Datacenter'
        BuildNumber      = '26100'
        WIMImageName     = 'Datacenter*(Desktop Experience)'
        ImageIndex       = 4
        GoldenPrefix     = 'WS2025-DC'
        EditionLabel     = 'Datacenter'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2025_DC_CORE = @{
        DisplayName      = 'Windows Server 2025 Datacenter (Core)'
        BuildNumber      = '26100'
        WIMImageName     = 'Datacenter*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 3
        GoldenPrefix     = 'WS2025-DC-CORE'
        EditionLabel     = 'Datacenter Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2025_STD = @{
        DisplayName      = 'Windows Server 2025 Standard'
        BuildNumber      = '26100'
        WIMImageName     = 'Standard*(Desktop Experience)'
        ImageIndex       = 2
        GoldenPrefix     = 'WS2025-STD'
        EditionLabel     = 'Standard'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }
    WS2025_STD_CORE = @{
        DisplayName      = 'Windows Server 2025 Standard (Core)'
        BuildNumber      = '26100'
        WIMImageName     = 'Standard*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 1
        GoldenPrefix     = 'WS2025-STD-CORE'
        EditionLabel     = 'Standard Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }

    # =================================================================
    #  Windows Server 2022
    # =================================================================
    WS2022 = @{
        AliasFor = 'WS2022_DC'
    }
    WS2022_DC = @{
        DisplayName      = 'Windows Server 2022 Datacenter'
        BuildNumber      = '20348'
        WIMImageName     = 'Datacenter*(Desktop Experience)'
        ImageIndex       = 4
        GoldenPrefix     = 'WS2022-DC'
        EditionLabel     = 'Datacenter'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2022_DC_CORE = @{
        DisplayName      = 'Windows Server 2022 Datacenter (Core)'
        BuildNumber      = '20348'
        WIMImageName     = 'Datacenter*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 3
        GoldenPrefix     = 'WS2022-DC-CORE'
        EditionLabel     = 'Datacenter Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2022_STD = @{
        DisplayName      = 'Windows Server 2022 Standard'
        BuildNumber      = '20348'
        WIMImageName     = 'Standard*(Desktop Experience)'
        ImageIndex       = 2
        GoldenPrefix     = 'WS2022-STD'
        EditionLabel     = 'Standard'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }
    WS2022_STD_CORE = @{
        DisplayName      = 'Windows Server 2022 Standard (Core)'
        BuildNumber      = '20348'
        WIMImageName     = 'Standard*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 1
        GoldenPrefix     = 'WS2022-STD-CORE'
        EditionLabel     = 'Standard Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }

    # =================================================================
    #  Windows Server 2019
    # =================================================================
    WS2019 = @{
        AliasFor = 'WS2019_DC'
    }
    WS2019_DC = @{
        DisplayName      = 'Windows Server 2019 Datacenter'
        BuildNumber      = '17763'
        WIMImageName     = 'Datacenter*(Desktop Experience)'
        ImageIndex       = 4
        GoldenPrefix     = 'WS2019-DC'
        EditionLabel     = 'Datacenter'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2019_DC_CORE = @{
        DisplayName      = 'Windows Server 2019 Datacenter (Core)'
        BuildNumber      = '17763'
        WIMImageName     = 'Datacenter*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 3
        GoldenPrefix     = 'WS2019-DC-CORE'
        EditionLabel     = 'Datacenter Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2019_STD = @{
        DisplayName      = 'Windows Server 2019 Standard'
        BuildNumber      = '17763'
        WIMImageName     = 'Standard*(Desktop Experience)'
        ImageIndex       = 2
        GoldenPrefix     = 'WS2019-STD'
        EditionLabel     = 'Standard'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }
    WS2019_STD_CORE = @{
        DisplayName      = 'Windows Server 2019 Standard (Core)'
        BuildNumber      = '17763'
        WIMImageName     = 'Standard*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 1
        GoldenPrefix     = 'WS2019-STD-CORE'
        EditionLabel     = 'Standard Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }

    # =================================================================
    #  Windows Server 2016
    # =================================================================
    WS2016 = @{
        AliasFor = 'WS2016_DC'
    }
    WS2016_DC = @{
        DisplayName      = 'Windows Server 2016 Datacenter'
        BuildNumber      = '14393'
        WIMImageName     = 'Datacenter*(Desktop Experience)'
        ImageIndex       = 4
        GoldenPrefix     = 'WS2016-DC'
        EditionLabel     = 'Datacenter'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2016_DC_CORE = @{
        DisplayName      = 'Windows Server 2016 Datacenter (Core)'
        BuildNumber      = '14393'
        WIMImageName     = 'Datacenter*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 3
        GoldenPrefix     = 'WS2016-DC-CORE'
        EditionLabel     = 'Datacenter Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('DC', 'Server')
    }
    WS2016_STD = @{
        DisplayName      = 'Windows Server 2016 Standard'
        BuildNumber      = '14393'
        WIMImageName     = 'Standard*(Desktop Experience)'
        ImageIndex       = 2
        GoldenPrefix     = 'WS2016-STD'
        EditionLabel     = 'Standard'
        DefaultMemoryGB  = 4
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }
    WS2016_STD_CORE = @{
        DisplayName      = 'Windows Server 2016 Standard (Core)'
        BuildNumber      = '14393'
        WIMImageName     = 'Standard*'
        WIMImageExclude  = 'Desktop Experience'
        ImageIndex       = 1
        GoldenPrefix     = 'WS2016-STD-CORE'
        EditionLabel     = 'Standard Core'
        DefaultMemoryGB  = 2
        DefaultCPU       = 2
        SupportedRoles   = @('Server')
    }
}
