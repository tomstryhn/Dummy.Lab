# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabDifferencingDisk {
    <#
    .SYNOPSIS
        Creates a differencing VHDX from a golden image parent with unattend injection.
    .DESCRIPTION
        Wraps the legacy New-DifferencingDisk helper to provide a clean,
        event-instrumented public interface. Creates a differencing disk that
        inherits the parent's base blocks (read-only) and stores only deltas.
        Mounts the disk and injects unattend.xml with VM-specific settings
        (computer name, locale, etc.).

        The differencing disk boots the sysprepped image straight to the desktop
        without OOBE. It is idempotent: if the disk already exists and is valid,
        it is reused.

        Live-off-the-land: wraps New-DifferencingDisk and Mount-VHD.
    .PARAMETER ParentPath
        Full path to the golden image parent VHDX.
    .PARAMETER DestinationPath
        Full path for the new differencing VHDX.
    .PARAMETER UnattendPath
        Optional path to an unattend.xml template. If provided, tokens are replaced
        with VM-specific settings before injection. Tokens recognized:
          @@ADMIN_PASSWORD@@ @@COMPUTERNAME@@ @@TIMEZONE@@ @@INPUT_LOCALE@@
          @@USER_LOCALE@@ @@SYSTEM_LOCALE@@ @@DOMAIN_JOIN@@
        If omitted, unattend.xml is not injected (VM may show OOBE).
    .PARAMETER ComputerName
        Computer name for token replacement. Default: * (random).
    .PARAMETER AdminPassword
        Administrator password for token replacement.
    .PARAMETER TimeZone
        Windows time zone string. Default: lab config.
    .PARAMETER InputLocale
        Input locale. Default: lab config.
    .PARAMETER UserLocale
        User locale. Default: lab config.
    .PARAMETER SystemLocale
        System locale. Default: lab config.
    .PARAMETER PassThru
        Return the destination path as a string. By default, the cmdlet
        produces no output.
    .EXAMPLE
        New-DLabDifferencingDisk -ParentPath C:\Dummy.Lab\Parent\WS2022.vhdx `
            -DestinationPath C:\Dummy.Lab\Labs\MyLab\VMs\DC01.vhdx `
            -ComputerName DC01 -AdminPassword 'P@ssw0rd'
    .EXAMPLE
        New-DLabDifferencingDisk -ParentPath C:\Dummy.Lab\Parent\WS2022.vhdx `
            -DestinationPath C:\Dummy.Lab\Labs\MyLab\VMs\SRV01.vhdx `
            -UnattendPath C:\Dummy.Lab\unattend-server.xml `
            -ComputerName SRV01 -AdminPassword 'P@ssw0rd' -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ParentPath,

        [Parameter(Mandatory, Position = 1)]
        [string]$DestinationPath,

        [string]$UnattendPath = '',

        [string]$ComputerName = '*',

        [string]$AdminPassword = '',

        [string]$TimeZone = '',

        [string]$InputLocale = '',

        [string]$UserLocale = '',

        [string]$SystemLocale = '',

        [switch]$PassThru
    )

    # Normalize defaults from config if not provided
    $config = Get-DLabConfigInternal
    if (-not $AdminPassword) { $AdminPassword = $config.Credentials.AdminPassword }
    if (-not $TimeZone) { $TimeZone = $config.Locale.TimeZone }
    if (-not $InputLocale) { $InputLocale = $config.Locale.InputLocale }
    if (-not $UserLocale) { $UserLocale = $config.Locale.UserLocale }
    if (-not $SystemLocale) { $SystemLocale = $config.Locale.SystemLocale }

    if (-not $PSCmdlet.ShouldProcess($DestinationPath, 'Create differencing disk')) { return }

    Write-DLabEvent -Level Step -Source 'New-DLabDifferencingDisk' `
        -Message "Creating differencing disk from parent (ComputerName: $ComputerName)" `
        -Data @{ ParentPath = $ParentPath; DestinationPath = $DestinationPath; ComputerName = $ComputerName }

    try {
        $resultPath = New-DifferencingDisk `
            -ParentPath $ParentPath `
            -DestinationPath $DestinationPath `
            -UnattendPath $UnattendPath `
            -ComputerName $ComputerName `
            -AdminPassword $AdminPassword `
            -TimeZone $TimeZone `
            -InputLocale $InputLocale `
            -UserLocale $UserLocale `
            -SystemLocale $SystemLocale

        Write-DLabEvent -Level Ok -Source 'New-DLabDifferencingDisk' `
            -Message "Differencing disk created: $resultPath" `
            -Data @{ DestinationPath = $resultPath }

        if ($PassThru) {
            $resultPath
        }
    } catch {
        Write-DLabEvent -Level Error -Source 'New-DLabDifferencingDisk' `
            -Message "Failed to create differencing disk: $($_.Exception.Message)" `
            -Data @{ DestinationPath = $DestinationPath; Error = $_.Exception.Message }
        throw
    }
}
