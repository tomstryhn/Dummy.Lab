# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Set-DLabConfig {
    <#
    .SYNOPSIS
        Persists a configuration override to the user's config file.
    .DESCRIPTION
        Writes a configuration key-value pair to %APPDATA%\DummyLab\config.psd1.
        Loads the existing config (if present), sets the key, and saves it back
        as a PowerShell data file. Emits a Write-DLabEvent to record the change.
    .PARAMETER Name
        Configuration key name (e.g., 'LabStorePath', 'ISOStorePath').
    .PARAMETER Value
        Value to set. Can be any object that ConvertTo-Json supports.
    .EXAMPLE
        Set-DLabConfig -Name LabStorePath -Value 'D:\Labs'
    .EXAMPLE
        Set-DLabConfig -Name ISOStorePath -Value 'E:\ISOs'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [object]$Value
    )

    process {
        $appDataPath = [Environment]::GetFolderPath('ApplicationData')
        $configDir = Join-Path $appDataPath 'DummyLab'
        $configFile = Join-Path $configDir 'config.psd1'

        # Load existing config or create empty hashtable
        $config = @{}
        if (Test-Path $configFile) {
            try {
                $config = Import-PowerShellDataFile -Path $configFile -ErrorAction Stop
                if ($null -eq $config) { $config = @{} }
            } catch {
                Write-DLabEvent -Level Warn -Source 'Set-DLabConfig' `
                    -Message "Failed to load existing config from $configFile : $($_.Exception.Message)"
                $config = @{}
            }
        }

        if (-not $PSCmdlet.ShouldProcess("$Name = $Value", 'Set config')) { return }

        # Set the value
        $config[$Name] = $Value

        # Ensure directory exists
        if (-not (Test-Path $configDir)) {
            try {
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            } catch {
                Write-DLabEvent -Level Error -Source 'Set-DLabConfig' `
                    -Message "Failed to create config directory $configDir : $($_.Exception.Message)" `
                    -Data @{ ConfigDir = $configDir; Error = $_.Exception.Message }
                Write-Error "Failed to create config directory $configDir : $_"
                return
            }
        }

        # Serialize back to PSD1 format
        try {
            $psd1Content = '@{'
            foreach ($key in $config.Keys | Sort-Object) {
                $val = $config[$key]
                # Simple serialization for strings and numbers
                if ($val -is [string]) {
                    $psd1Content += "`n    '$key' = '$($val.Replace("'", "''"))'"
                } elseif ($val -is [int] -or $val -is [double] -or $val -is [bool]) {
                    $psd1Content += "`n    '$key' = $val"
                } else {
                    # For complex objects, use ConvertTo-Json
                    $jsonVal = $val | ConvertTo-Json -Compress
                    $psd1Content += "`n    '$key' = '$($jsonVal.Replace("'", "''"))'"
                }
            }
            $psd1Content += "`n}`n"

            Set-Content -Path $configFile -Value $psd1Content -Encoding UTF8 -ErrorAction Stop

            Write-DLabEvent -Level Ok -Source 'Set-DLabConfig' `
                -Message "Config updated: $Name = $Value" `
                -Data @{ ConfigKey = $Name; ConfigValue = $Value; ConfigFile = $configFile }
        } catch {
            Write-DLabEvent -Level Error -Source 'Set-DLabConfig' `
                -Message "Failed to write config to $configFile : $($_.Exception.Message)" `
                -Data @{ ConfigKey = $Name; ConfigFile = $configFile; Error = $_.Exception.Message }
            Write-Error "Failed to write config to $configFile : $_"
        }
    }
}
