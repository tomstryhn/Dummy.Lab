# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Invoke-GuestScript {
    <#
    .SYNOPSIS
        Executes a script inside a VM via PowerShell Direct.
    .PARAMETER VMName
        Target VM.
    .PARAMETER Credential
        VM local admin credentials.
    .PARAMETER ScriptPath
        Path to the script INSIDE the VM (after Send-GuestScript).
    .PARAMETER Arguments
        Hashtable of parameter name -> value pairs.
    .PARAMETER WaitForReboot
        If true, waits for VM to come back up after a reboot.
    .PARAMETER Verbose
        If true, show guest script output on host console.
    #>
    param(
        [string]$VMName,
        [PSCredential]$Credential,
        [string]$ScriptPath,
        [hashtable]$Arguments   = @{},
        [switch]$WaitForReboot,
        [switch]$ShowOutput
    )

    $argString = ($Arguments.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [bool]) { "-$($_.Key):`$$($_.Value.ToString().ToLower())" }
        else { "-$($_.Key) '$($_.Value)'" }
    }) -join ' '

    $session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
    $sessionDropped = $false
    try {
        $output = Invoke-Command -Session $session -ScriptBlock {
            param($path, $argStr)
            $cmd = "& '$path' $argStr"
            $result = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
            [PSCustomObject]@{ Output = $result; ExitCode = $LASTEXITCODE }
        } -ArgumentList $ScriptPath, $argString -ErrorAction Stop

        if ($ShowOutput -and $output.Output) {
            $output.Output | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        }

        # Surface non-zero exit codes with captured output so silent failures are visible
        if ($output.ExitCode -and $output.ExitCode -ne 0) {
            Write-Warning "Guest script exited with code $($output.ExitCode)."
            if ($output.Output) {
                Write-Host "      --- Guest script output ---" -ForegroundColor Yellow
                $output.Output | Select-Object -Last 20 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor Yellow
                }
                Write-Host "      ---------------------------" -ForegroundColor Yellow
            }
        }
    } catch {
        if ($_.Exception.Message -match 'pipeline|broken|closed|reboot') {
            # Session dropped - expected during reboot
            $sessionDropped = $true
        } else {
            Write-Warning "Script error: $($_.Exception.Message)"
        }
    } finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }

    if ($WaitForReboot) {
        Start-Sleep -Seconds 15
        $null = Wait-LabVMReady -VMName $VMName -Credential $Credential
    }
}
