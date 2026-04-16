# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabVHDX {
    <#
    .SYNOPSIS
        Creates a VHDX from a Windows Server ISO and applies a Windows image.
    .DESCRIPTION
        Wraps the legacy New-LabVHDXFromISO helper to provide a clean,
        event-instrumented public interface. Creates a dynamic VHDX, partitions it
        (EFI + Windows), mounts the ISO, applies the WIM image at the specified
        index, injects unattend.xml with lab-aware credentials and locale settings,
        and makes it bootable via bcdboot.

        The resulting VHDX boots straight to the desktop without OOBE. It is
        idempotent: if the VHDX already exists and is valid, it is reused.

        Live-off-the-land: the heavy lifting is done by New-LabVHDXFromISO.
        This cmdlet adds event instrumentation and parameter normalization.
    .PARAMETER ISOPath
        Full path to a Windows Server ISO file.
    .PARAMETER VHDXPath
        Full path for the output VHDX file.
    .PARAMETER ImageIndex
        WIM image index within the ISO (e.g. 4 for Datacenter Desktop Experience).
        Default: 4.
    .PARAMETER SizeGB
        VHDX virtual size in GB. Disk is created dynamic, so actual file size is
        much smaller. Default: read from lab config.
    .PARAMETER UnattendTemplate
        Optional path to an unattend.xml template. If provided, tokens are replaced
        with lab defaults before injection. Tokens recognized:
          @@ADMIN_PASSWORD@@ @@TIMEZONE@@ @@INPUT_LOCALE@@ @@USER_LOCALE@@ @@SYSTEM_LOCALE@@
        If omitted, the VHDX will show OOBE on first boot.
    .PARAMETER AdminPassword
        Administrator password to bake into unattend.xml. If omitted, reads from
        lab config or uses a hardcoded default.
    .PARAMETER TimeZone
        Windows time zone string (e.g. 'Eastern Standard Time'). Default: lab config.
    .PARAMETER InputLocale
        Input locale (e.g. 'en-US'). Default: lab config.
    .PARAMETER UserLocale
        User locale (e.g. 'en-US'). Default: lab config.
    .PARAMETER SystemLocale
        System locale (e.g. 'en-US'). Default: lab config.
    .PARAMETER PassThru
        Return a DLab.VHDX object with Path and SizeGB. By default, the cmdlet
        produces no output.
    .EXAMPLE
        New-DLabVHDX -ISOPath C:\ISOs\WS2022.iso -VHDXPath C:\Dummy.Lab\Parent\WS2022.vhdx -ImageIndex 4
    .EXAMPLE
        New-DLabVHDX -ISOPath C:\ISOs\WS2022.iso -VHDXPath C:\Dummy.Lab\Parent\WS2022.vhdx `
            -UnattendTemplate C:\Dummy.Lab\unattend-server.xml -TimeZone 'Eastern Standard Time' -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.VHDX')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ISOPath,

        [Parameter(Mandatory, Position = 1)]
        [string]$VHDXPath,

        [int]$ImageIndex = 4,

        [int]$SizeGB = 0,  # 0 means use config default

        [string]$UnattendTemplate = '',

        [string]$AdminPassword = '',

        [string]$TimeZone = '',

        [string]$InputLocale = '',

        [string]$UserLocale = '',

        [string]$SystemLocale = '',

        [switch]$PassThru
    )

    # Normalize defaults from config if not provided
    $config = Get-DLabConfigInternal
    if ($SizeGB -le 0) { $SizeGB = $config.Storage.VHDXSizeGB }
    if (-not $AdminPassword) { $AdminPassword = $config.Credentials.AdminPassword }
    if (-not $TimeZone) { $TimeZone = $config.Locale.TimeZone }
    if (-not $InputLocale) { $InputLocale = $config.Locale.InputLocale }
    if (-not $UserLocale) { $UserLocale = $config.Locale.UserLocale }
    if (-not $SystemLocale) { $SystemLocale = $config.Locale.SystemLocale }

    if (-not $PSCmdlet.ShouldProcess($VHDXPath, 'Create VHDX from ISO')) { return }

    Write-DLabEvent -Level Step -Source 'New-DLabVHDX' `
        -Message "Creating VHDX from ISO (Index $ImageIndex, ${SizeGB}GB)" `
        -Data @{ ISOPath = $ISOPath; VHDXPath = $VHDXPath; ImageIndex = $ImageIndex; SizeGB = $SizeGB }

    try {
        $resultPath = New-LabVHDXFromISO `
            -ISOPath $ISOPath `
            -VHDXPath $VHDXPath `
            -ImageIndex $ImageIndex `
            -SizeGB $SizeGB `
            -UnattendTemplate $UnattendTemplate `
            -AdminPassword $AdminPassword `
            -TimeZone $TimeZone `
            -InputLocale $InputLocale `
            -UserLocale $UserLocale `
            -SystemLocale $SystemLocale

        Write-DLabEvent -Level Ok -Source 'New-DLabVHDX' `
            -Message "VHDX created successfully: $resultPath" `
            -Data @{ VHDXPath = $resultPath }

        if ($PassThru) {
            $fileSize = [math]::Round((Get-Item $resultPath).Length / 1GB, 2)
            [PSCustomObject]@{
                PSTypeName = 'DLab.VHDX'
                Path       = $resultPath
                SizeGB     = $fileSize
            }
        }
    } catch {
        Write-DLabEvent -Level Error -Source 'New-DLabVHDX' `
            -Message "Failed to create VHDX: $($_.Exception.Message)" `
            -Data @{ ISOPath = $ISOPath; VHDXPath = $VHDXPath; Error = $_.Exception.Message }
        throw
    }
}
