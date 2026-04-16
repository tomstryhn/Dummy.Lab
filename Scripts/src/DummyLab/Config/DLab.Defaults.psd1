# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.
#
# Dummy.Lab 1.0.0 default configuration.
#
# This file is the single source of truth for module defaults. It is read by
# Get-DLabConfig (via Get-DLabConfigInternal) and consumed by every cmdlet
# that needs a default value (including the golden-image build phases).
#
# Override any value by creating %APPDATA%\DummyLab\config.psd1 with just the
# keys you want to change, or by setting the DUMMYLAB_CONFIG environment
# variable to a .psd1 file path.

@{
    # --- Storage ---
    LabStorageRoot       = 'C:\Dummy.Lab'
    LabsFolderName       = 'Labs'
    ImageStoreName       = 'GoldenImages'
    EventsFolderName     = 'Events'
    OperationsFolderName = 'Operations'
    ReportsFolderName    = 'Reports'
    ISOFolderName        = 'ISOs'
    ExtraISOPaths        = @()  # Additional ISO search paths (e.g. @('D:\ISOs', 'E:\WindowsMedia'))

    # --- Naming ---
    # LabName is the default lab that New-DLab, Add-DLabVM, Test-DLab, and
    # Invoke-DLabPreflight operate on when -LabName / -Name is not supplied.
    # Remove-DLab and Remove-DLabVM intentionally do NOT fall back to this
    # default: destructive actions must always name their target explicitly.
    LabName          = 'Dummy'

    # DomainSuffix 'internal' is an IANA-reserved private-use TLD (2024).
    # It will never be delegated publicly and works cleanly in AD.
    # Override to your own registered domain if you want to test public CAs.
    DomainSuffix     = 'internal'

    # --- Shared network infrastructure ---
    # A single Hyper-V internal switch and NAT serve all labs and the
    # golden-image staging segment. The supernet 10.74.18.0/23 (512 addresses)
    # is divided into 16 /27 segments of 32 addresses each.
    #
    #   Segment 0  (10.74.18.0/27)   : Staging - golden-image builds
    #   Segments 1-15                 : Labs (one per New-DLab)
    #
    # All DLab resources are prefixed 'DLab-' to make them easy to identify.
    SharedSwitchName   = 'DLab-Internal'
    SharedNATName      = 'DLab-NAT'
    SharedNetworkCIDR  = '10.74.18.0/23'
    SharedGatewayIP    = '10.74.18.1'
    StagingSegment     = 0             # reserved for golden-image builds
    LabSegmentFirst    = 1             # labs start at this segment index

    # Within each /27 segment, IP offsets from the segment base:
    #   base+0         : network address
    #   base+1         : gateway (host adapter, NAT)
    #   base+2  to +5  : DCs (4 slots)
    #   base+6  to +21 : servers (16 slots)
    #   base+22 to +30 : DHCP dynamic pool
    #   base+31        : broadcast
    DCStartOffset      = 2             # first DC IP = base + 2
    ServerStartOffset  = 6             # first server IP = base + 6

    DHCPLeaseDurationH = 8
    DNSForwarder       = '1.1.1.1'

    # --- VM sizing (golden image defaults override) ---
    DefaultMemoryGB  = 4
    DefaultCPU       = 2

    # --- Image defaults ---
    DefaultServerOS  = 'WS2025_DC'
    VHDXSizeGB       = 60

    # --- Locale ('auto' = detect from host) ---
    UILanguage       = 'en-US'
    TimeZone         = 'auto'
    InputLocale      = 'auto'
    UserLocale       = 'auto'
    SystemLocale     = 'en-US'

    # --- Credentials (lab only, plaintext intentional for automation) ---
    AdminPassword    = 'Qwerty*12345'
    SafeModePassword = 'Qwerty*12345'

    # --- AD ---
    DisableIPv6      = $true

    # --- Updates ---
    InstallUpdates   = $true
    UpdateTimeoutMin = 60

    # --- Observability ---
    EventLogRetentionMonths     = 6
    OperationLogRetentionMonths = 12
}
