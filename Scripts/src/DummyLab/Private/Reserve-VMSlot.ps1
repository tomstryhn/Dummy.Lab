# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Reserve-VMSlot {
    <#
    .SYNOPSIS
        Atomically reserves a VM name + IP in the state file.
        Must be called BEFORE deployment so parallel -Add commands don't collide.
    .DESCRIPTION
        Picks the lowest unused IP within the role's range in the lab's /27
        segment. Holes left behind by Remove-DLabVM are reused on the next
        reservation, so the address space never leaks.

        Layout within each /27 segment (offsets from segment base):
          base+0  : network
          base+1  : gateway
          base+2..+5  : DCs     (4 slots)
          base+6..+21 : Servers (16 slots)
          base+22..+30: DHCP pool
          base+31 : broadcast

        Naming is deterministic and tied to slot position: the first slot in
        the role's range is DC01 / SRV01, the second is DC02 / SRV02, etc.
        This keeps names stable when holes are reused.
    .PARAMETER StatePath
        Path to lab.state.json.
    .PARAMETER Role
        VM role: DC or Server.
    .PARAMETER RequestedName
        Optional short name (e.g. SRV01). Auto-generated if empty.
        A requested name that collides with an existing VM throws.
    .PARAMETER OSKey
        OS catalog key (e.g. WS2025_DC).
    .PARAMETER LabName
        Lab name (used to construct full VM name).
    .OUTPUTS
        PSCustomObject with ShortName, VMName, and IP.
    #>
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][ValidateSet('DC', 'Server')][string]$Role,
        [string]$RequestedName = '',
        [Parameter(Mandatory)][string]$OSKey,
        [Parameter(Mandatory)][string]$LabName
    )

    $null = Update-LabStateLocked -Path $StatePath -UpdateScript {
        param($state)

        $prefix      = if ($Role -eq 'DC') { 'DC' } else { 'SRV' }
        $startOffset = if ($Role -eq 'DC') { 2 }    else { 6 }
        $slotCount   = if ($Role -eq 'DC') { 4 }    else { 16 }

        # Segment base octet is encoded in NetworkBase (e.g. '10.74.18.32').
        $parts       = ($state.Network.NetworkBase -split '\.')
        $ipPrefix    = "$($parts[0]).$($parts[1]).$($parts[2])"
        $segmentBase = [int]$parts[3]
        $startOctet  = $segmentBase + $startOffset
        $endOctet    = $startOctet + $slotCount - 1

        # Build the set of last-octets currently in use (across all roles, so
        # nothing can ever step on another role's slot either).
        $usedOctets  = @{}
        $usedNames   = @{}
        if ($state.VMs) {
            foreach ($vm in $state.VMs) {
                if ($vm.IP) {
                    $octet = [int]($vm.IP -split '\.')[3]
                    $usedOctets[$octet] = $true
                }
                if ($vm.ShortName) { $usedNames[$vm.ShortName] = $true }
            }
        }

        # Lowest free octet in the role's range. Throws if the range is full.
        $chosenOctet = $null
        for ($o = $startOctet; $o -le $endOctet; $o++) {
            if (-not $usedOctets.ContainsKey($o)) {
                $chosenOctet = $o
                break
            }
        }
        if ($null -eq $chosenOctet) {
            throw "No free $Role slot in segment $($state.Network.Segment) (range $startOctet..$endOctet, all in use)."
        }

        # Slot index = position within the role's range. Tied to IP, not to
        # the count of existing VMs, so DC02 always lives at base+3 even when
        # other slots are holes.
        $slotIndex = $chosenOctet - $startOctet + 1

        if ($RequestedName) {
            if ($usedNames.ContainsKey($RequestedName)) {
                throw "Requested name '$RequestedName' already exists in lab '$LabName'."
            }
            $shortName = $RequestedName
        } else {
            $shortName = "{0}{1:D2}" -f $prefix, $slotIndex
            if ($usedNames.ContainsKey($shortName)) {
                throw "Auto-generated name '$shortName' collides with existing VM. Pass -VMName explicitly."
            }
        }

        $ip     = "$ipPrefix.$chosenOctet"
        $vmName = "$LabName-$shortName"

        $entry = [PSCustomObject]@{
            Name      = $vmName
            ShortName = $shortName
            Role      = $Role
            OS        = $OSKey
            IP        = $ip
            Status    = 'Deploying'
            AddedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        $state.VMs = @($state.VMs) + @($entry)

        $script:_reservedSlot = [PSCustomObject]@{
            ShortName = $shortName
            VMName    = $vmName
            IP        = $ip
        }

        return $state
    }

    return $script:_reservedSlot
}
