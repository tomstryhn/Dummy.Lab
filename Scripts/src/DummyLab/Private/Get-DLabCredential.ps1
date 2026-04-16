# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Auto-resolves credentials for a lab. Reads the lab state if it exists to
# pick up the actual DomainNetbios and DomainName; falls back to defaults
# derived from the lab name plus config DomainSuffix when the state file
# is not there yet (e.g. during New-DLab before the state is initialised).
#
# Returns a bundle object so callers can pick the right credential for the
# stage they are at:
#   - LocalAdmin   for fresh un-promoted VMs (first boot, sysprep, etc.)
#   - DomainAdmin  for joined members and DCs (NetBIOS form)
#   - DomainFQDN   alternative domain cred using the FQDN form
#
# All use the admin password from config. Wait-DLabVM can use DomainAdmin
# as primary and LocalAdmin as alternate to handle the pre/post-join window
# gracefully.

function Get-DLabCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LabName,

        [string]$DomainNetbios = '',
        [string]$DomainName    = '',
        [string]$AdminPassword = ''
    )

    $cfg = Get-DLabConfigInternal

    # Attempt to load authoritative values from the lab state. This is only
    # useful after New-DLab has written state at least once.
    $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName
    if (Test-Path $statePath) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            if (-not $DomainNetbios -and $state.PSObject.Properties['DomainNetbios']) {
                $DomainNetbios = $state.DomainNetbios
            }
            if (-not $DomainName -and $state.PSObject.Properties['DomainName']) {
                $DomainName = $state.DomainName
            }
        } catch { }
    }

    # Fall back to deterministic defaults so credentials can be constructed
    # even before state exists (e.g. during the very first New-DLab call).
    if (-not $DomainNetbios) { $DomainNetbios = $LabName.Substring(0, [Math]::Min($LabName.Length, 15)) }
    if (-not $DomainName)    { $DomainName    = "$($LabName.ToLower()).$($cfg.DomainSuffix)" }
    if (-not $AdminPassword) { $AdminPassword = $cfg.AdminPassword }

    $pw = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

    [PSCustomObject]@{
        PSTypeName    = 'DLab.CredentialBundle'
        LabName       = $LabName
        DomainNetbios = $DomainNetbios
        DomainName    = $DomainName
        LocalAdmin    = [pscredential]::new('Administrator',                   $pw)
        DomainAdmin   = [pscredential]::new("$DomainNetbios\Administrator",    $pw)
        DomainFQDN    = [pscredential]::new("$DomainName\Administrator",       $pw)
    }
}
