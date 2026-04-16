# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Builders that produce typed DLab.* PSCustomObjects with correct PSTypeName.
# Consumers (Get-DLab, Get-DLabVM, etc.) compose these from live Hyper-V data
# and persisted state files. Keeping construction centralised means schema
# changes land in one place.

function New-DLabVMObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$StateEntry,
        [Parameter(Mandatory)][string]$LabName,
        $LiveVM = $null
    )

    $state = 'Missing'
    $memGB = 0.0
    $cpu   = 0
    if ($LiveVM) {
        $state = $LiveVM.State.ToString()
        $memGB = [math]::Round($LiveVM.MemoryAssigned / 1GB, 2)
        $cpu   = $LiveVM.ProcessorCount
    }

    [PSCustomObject]@{
        PSTypeName     = 'DLab.VM'
        Name           = $StateEntry.Name
        ShortName      = if ($StateEntry.PSObject.Properties['ShortName']) { $StateEntry.ShortName } else { $StateEntry.Name -replace "^$LabName-", '' }
        LabName        = $LabName
        Role           = if ($StateEntry.PSObject.Properties['Role']) { $StateEntry.Role } else { 'Unknown' }
        OSKey          = if ($StateEntry.PSObject.Properties['OS']) { $StateEntry.OS } else { '' }
        IP             = if ($StateEntry.PSObject.Properties['IP']) { $StateEntry.IP } else { '' }
        State          = $state
        MemoryGB       = $memGB
        ProcessorCount = $cpu
        Status         = if ($StateEntry.PSObject.Properties['Status']) { $StateEntry.Status } else { 'Unknown' }
        AddedAt        = if ($StateEntry.PSObject.Properties['AddedAt'] -and $StateEntry.AddedAt) {
                           ConvertFrom-DLabJsonDate $StateEntry.AddedAt
                         } else { $null }
    }
}

function New-DLabNetworkObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][PSCustomObject]$State,
        $LiveSwitch = $null,
        $LiveNat    = $null
    )

    $net      = $State.Network
    $subnet   = if ($net.PSObject.Properties['Subnet']) { $net.Subnet } else { '' }
    $gateway  = if ($net.PSObject.Properties['Gateway']) { $net.Gateway } else { '' }
    $dcIP     = if ($net.PSObject.Properties['DCIP']) { $net.DCIP } else { '' }
    $swName   = if ($net.PSObject.Properties['SwitchName']) { $net.SwitchName } else { '' }
    $swType   = if ($LiveSwitch) { $LiveSwitch.SwitchType.ToString() } else { 'Missing' }
    $natName  = if ($State.PSObject.Properties['Infrastructure'] -and $State.Infrastructure.PSObject.Properties['NATName']) {
                    $State.Infrastructure.NATName
                } else { $null }
    $natOn    = [bool]($natName -and $LiveNat)

    [PSCustomObject]@{
        PSTypeName  = 'DLab.Network'
        LabName     = $LabName
        SwitchName  = $swName
        SwitchType  = $swType
        Subnet      = $subnet
        Gateway     = $gateway
        DCIP        = $dcIP
        NATName     = $natName
        NATEnabled  = $natOn
    }
}

function New-DLabGoldenImageObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [hashtable]$Catalog = @{},
        [string]$PointerPath = ''
    )

    # Best-effort OSKey inference from filename. Golden images follow the pattern
    # <prefix>-<date>[-unpatched].vhdx where <prefix> matches a catalog entry's
    # GoldenPrefix (e.g. WS2025-DC, WS2022-STD-CORE).
    $name     = $File.BaseName
    $osKey    = ''
    $osName   = ''
    $patched  = $true
    $buildDate = $File.LastWriteTime

    if ($name -match '-unpatched$') { $patched = $false }

    # Match non-empty GoldenPrefix only. Alias catalog entries have no prefix
    # (null), and "".StartsWith($null) returns true in .NET which would match
    # everything and pick the first alias in hashtable-enumeration order.
    # Also prefer longer prefixes so "WS2016-DC-CORE" wins over "WS2016-DC"
    # when both would match.
    $bestPrefixLen = 0
    foreach ($k in $Catalog.Keys) {
        $entry = $Catalog[$k]
        if ($entry -isnot [hashtable]) { continue }
        $prefix = $entry['GoldenPrefix']
        if (-not $prefix) { continue }
        if ($name.StartsWith($prefix) -and $prefix.Length -gt $bestPrefixLen) {
            $osKey = $k
            if ($entry.ContainsKey('DisplayName')) { $osName = $entry.DisplayName }
            $bestPrefixLen = $prefix.Length
        }
    }

    # Try to parse date from filename
    if ($name -match '(\d{4}[-.]?\d{2}[-.]?\d{2})') {
        try {
            $parsed = [datetime]::ParseExact(($matches[1] -replace '[-.]', ''), 'yyyyMMdd', $null)
            $buildDate = $parsed
        } catch { }
    }

    [PSCustomObject]@{
        PSTypeName   = 'DLab.GoldenImage'
        OSKey        = $osKey
        OSName       = $osName
        ImageName    = $File.Name
        ImagePath    = $File.FullName
        SizeGB       = [math]::Round($File.Length / 1GB, 2)
        BuildDate    = $buildDate
        Patched      = $patched
        Protected    = $File.IsReadOnly
        Checksum     = $null
        PointerPath  = $PointerPath
    }
}

function New-DLabLabObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][PSCustomObject]$State,
        [Parameter(Mandatory)][string]$StatePath,
        # $VMs is an array of DLab.VM PSCustomObjects. We do not strongly-type
        # the parameter because DLab.VM is a PSTypeName, not a .NET type, and
        # strict binding would fail at call time.
        [object[]]$VMs      = @(),
        $Network            = $null,
        [string]$Status     = 'Unknown'
    )

    # Derive OSKey and ImagePath from the DC entry, if present. This is what
    # flows into Add-DLabVM via the pipeline so member servers inherit the
    # lab's OS unless explicitly overridden.
    $osKey     = ''
    $imagePath = ''
    $dc = $VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
    if ($dc) { $osKey = $dc.OSKey }
    if ($State.PSObject.Properties['ImagePath']) { $imagePath = $State.ImagePath }

    $domain    = if ($State.PSObject.Properties['DomainName']) { $State.DomainName } else { '' }
    $netbios   = if ($State.PSObject.Properties['DomainNetbios']) { $State.DomainNetbios } else { '' }
    $createdAt = $null
    if ($State.PSObject.Properties['CreatedAt'] -and $State.CreatedAt) {
        $createdAt = ConvertFrom-DLabJsonDate $State.CreatedAt
    }

    [PSCustomObject]@{
        PSTypeName     = 'DLab.Lab'
        Name           = $LabName
        DomainName     = $domain
        DomainNetbios  = $netbios
        OSKey          = $osKey
        ImagePath      = $imagePath
        CreatedAt      = $createdAt
        Network        = $Network
        VMs            = $VMs
        StatePath      = $StatePath
        Status         = $Status
    }
}
