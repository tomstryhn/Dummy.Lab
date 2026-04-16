# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Golden-image build internet probe. Used by both the Boot and Patch phases
# to make sure the temp VM can reach Windows Update. Idempotent: inspects
# current VM network state first, reconfigures only when necessary, then
# verifies an actual outbound echo before returning success.
#
# Kept as a module-private helper so the Start-GoldenImageBuildVM and
# Invoke-GoldenImageUpdate phase helpers can share the same probe logic.

function Confirm-GoldenImageInternet {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$IP,
        [Parameter(Mandatory)][string]$Gateway,
        [string]$DNS = '8.8.8.8',
        [int]$PrefixLength = 27,
        [int]$MaxRetries = 3
    )

    $ensureNetworkBlock = {
        param($IP, $GW, $DNS, $Prefix)

        $adapter = $null
        for ($wait = 0; $wait -lt 6; $wait++) {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if ($adapter) { break }
            Start-Sleep -Seconds 5
        }
        if (-not $adapter) { return 'NO_ADAPTER' }

        $currentIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -eq $IP }
        if ($currentIP) {
            $currentGW  = (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).NextHop
            $currentDNS = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
            if ($currentGW -eq $GW -and $currentDNS -contains $DNS) {
                return 'OK'
            }
        }

        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -ne '127.0.0.1' } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($DNS)
        return 'CONFIGURED'
    }

    $testInternetBlock = {
        Test-Connection -ComputerName '8.8.8.8' -Count 2 -Quiet -ErrorAction SilentlyContinue
    }

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        $netStatus = Invoke-Command -VMName $VMName -Credential $Credential `
            -ScriptBlock $ensureNetworkBlock -ArgumentList $IP, $Gateway, $DNS, $PrefixLength -ErrorAction SilentlyContinue

        if ($netStatus -eq 'NO_ADAPTER') {
            Write-LabLog "No active network adapter in VM (attempt $retry/$MaxRetries)" -Level Warn
            Start-Sleep -Seconds 10
            continue
        }

        if ($netStatus -eq 'CONFIGURED') {
            Write-LabLog 'Network configuration applied' -Level Info
        }

        $hasInternet = Invoke-Command -VMName $VMName -Credential $Credential `
            -ScriptBlock $testInternetBlock -ErrorAction SilentlyContinue

        if ($hasInternet) {
            if ($retry -gt 1 -or $netStatus -eq 'CONFIGURED') {
                Write-LabLog "Internet access confirmed (attempt $retry)" -Level OK
            } else {
                Write-LabLog 'Internet access confirmed' -Level OK
            }
            return $true
        }

        Write-LabLog "No internet access after config (attempt $retry/$MaxRetries)" -Level Warn
        Start-Sleep -Seconds 5
    }

    return $false
}
