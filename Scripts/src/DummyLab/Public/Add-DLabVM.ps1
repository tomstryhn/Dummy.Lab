# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Add-DLabVM {
    <#
    .SYNOPSIS
        Adds a VM to an existing Dummy.Lab lab.
    .DESCRIPTION
        Reserves a slot
        atomically (so parallel calls don't collide on name or IP), creates
        the differencing disk, deploys either a DC (additional) or a member
        Server, and joins the domain.

        Accepts pipeline input from New-DLab's DLab.Lab so typical chains
        work without boilerplate:
            New-DLab -LabName Demo | Add-DLabVM -Role Server | Add-DLabVM -Role Server
        LabName and OSKey flow through via property-name binding.
    .PARAMETER LabName
        Target lab. Defaults to the LabName configured in DLab.Defaults.psd1
        ('Dummy' out of the box) when neither the parameter nor a pipeline
        input is supplied. Accepts pipeline input from DLab.Lab.Name.
    .PARAMETER Role
        DC or Server. Default: Server.
    .PARAMETER Name
        Optional short name (e.g. SRV02). Auto-generated when omitted.
    .PARAMETER OSKey
        OS catalog key. Falls back to the lab's OSKey (from state) when
        omitted, so member servers match the DC's OS by default.
    .PARAMETER GoldenImage
        Explicit golden image VHDX path. Overrides OSKey lookup.
    .PARAMETER MemoryGB, CPU
        Override default VM sizing from the OS catalog.
    .PARAMETER FixNLA
        Apply the NLA dependency fix (DC role only).
    .EXAMPLE
        Add-DLabVM -LabName Demo -Role Server
    .EXAMPLE
        New-DLab -LabName Demo | Add-DLabVM -Role Server -Name SRV01
    .EXAMPLE
        New-DLab -LabName Demo | Add-DLabVM -Role Server | Add-DLabVM -Role Server
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Lab-only credentials - intentional plaintext for automation')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.VM')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('Name')]                       # binds from DLab.Lab.Name
        [string]$LabName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('DC', 'Server')]
        [string]$Role             = 'Server',

        [string]$VMName           = '',       # short name (SRV01 etc)

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('OS')]
        [string]$OSKey            = '',

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ImagePath')]
        [string]$GoldenImage      = '',

        [int]$MemoryGB            = 0,
        [int]$CPU                 = 0,

        [switch]$FixNLA
    )

    begin {
        $cfg = Get-DLabConfigInternal
    }

    process {
        # Fall back to the configured default lab when neither the parameter
        # nor a pipeline binding supplied a name.
        if (-not $LabName) {
            $LabName = [string]$cfg.LabName
            if (-not $LabName) {
                throw "LabName is required and no default is configured in DLab.Defaults.psd1."
            }
        }

        # -----------------------------------------------------------------
        # Load lab state - must exist
        # -----------------------------------------------------------------
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName
        if (-not (Test-Path $statePath)) {
            throw "Lab '$LabName' not found. Create it first with New-DLab -LabName $LabName."
        }
        $state = Read-LabState -Path $statePath

        # Inherit lab's OS if caller didn't specify one
        if (-not $OSKey -and $state.VMs) {
            $dcEntry = $state.VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
            if ($dcEntry -and $dcEntry.OS) { $OSKey = $dcEntry.OS }
        }

        $labDir       = Get-DLabStorePath -Kind LabDir -LabName $LabName
        $vmPath       = Join-Path $labDir 'VMs'
        $diskPath     = Join-Path $labDir 'Disks'
        $scriptsPath  = Join-Path (Get-DLabStorePath -Kind Root) 'Scripts'
        $unattendPath = Join-Path $scriptsPath 'Config\unattend-server.xml'
        $guestPath    = Join-Path $scriptsPath 'GuestScripts'
        # Labs connect to the shared switch. Network.SwitchName is the authoritative
        # value; fall back to the config default if the state predates this field.
        $switchName   = if ($state.PSObject.Properties['Network'] -and
                            $state.Network -and
                            $state.Network.PSObject.Properties['SwitchName'] -and
                            $state.Network.SwitchName) {
                          $state.Network.SwitchName
                        } else {
                          $cfg.SharedSwitchName
                        }

        $adminPwd    = $cfg.AdminPassword
        $safeModePwd = $cfg.SafeModePassword
        $netbios     = if ($state.PSObject.Properties['DomainNetbios']) { $state.DomainNetbios } else { $LabName }
        $domain      = if ($state.PSObject.Properties['DomainName'])    { $state.DomainName }    else { "$($LabName.ToLower()).$($cfg.DomainSuffix)" }

        # Locale
        $timeZone    = if ($cfg.TimeZone    -eq 'auto') { (Get-TimeZone).Id }    else { $cfg.TimeZone }
        $inputLocale = if ($cfg.InputLocale -eq 'auto') {
            $hostLang = Get-WinUserLanguageList | Select-Object -First 1
            if ($hostLang -and $hostLang.InputMethodTips) { $hostLang.InputMethodTips[0] } else { (Get-Culture).Name }
        } else { $cfg.InputLocale }
        $userLocale   = if ($cfg.UserLocale   -eq 'auto') { (Get-Culture).Name } else { $cfg.UserLocale }
        $systemLocale = if ($cfg.SystemLocale -eq 'auto') { (Get-Culture).Name } else { $cfg.SystemLocale }

        # Determine additional-DC context from the state as it exists before
        # the new slot is reserved (Reserve-VMSlot hasn't run yet, so $state.VMs
        # reflects only previously committed VMs).
        $existingDCs    = @($state.VMs | Where-Object { $_.Role -eq 'DC' -and $_.Status -eq 'Ready' })
        $isAdditionalDC = $Role -eq 'DC' -and $existingDCs.Count -gt 0
        $primaryDCIP    = if ($isAdditionalDC) { $state.Network.DCIP } else { '' }
        $labHasInternet = if ($state.PSObject.Properties['HasInternet']) { [bool]$state.HasInternet } else { $true }

        $target = if ($VMName) { "$LabName-$VMName" } else { "$LabName-<auto>" }
        if (-not $PSCmdlet.ShouldProcess($target, "Add $Role VM to lab $LabName")) { return }

        # -----------------------------------------------------------------
        # Start the operation
        # -----------------------------------------------------------------
        $op = New-DLabOperation -Kind 'Add-DLabVM' -Target $target -LabName $LabName `
                                -Parameters @{
                                    LabName     = $LabName
                                    Role        = $Role
                                    VMName      = $VMName
                                    OSKey       = $OSKey
                                    GoldenImage = $GoldenImage
                                }
        Write-DLabEvent -Level Step -Source 'Add-DLabVM' `
            -Message "Adding $Role to lab '$LabName'" `
            -OperationId $op.OperationId `
            -Data @{ LabName = $LabName; Role = $Role }

        try {
            # ---- Step: resolve golden image -----------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Resolve golden image'
            $goldenInfo = Resolve-DLabGoldenImageInternal -OSKey $OSKey -ExplicitPath $GoldenImage
            if (-not $goldenInfo) { throw "No golden image resolved for OSKey '$OSKey'." }
            # Pick up the resolved OSKey so Reserve-VMSlot has a concrete value
            $OSKey = $goldenInfo.OSKey
            $step | Complete-DLabOperationStep -Message "$($goldenInfo.OSKey) -> $(Split-Path $goldenInfo.Path -Leaf)"

            # ---- Step: reserve slot atomically --------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Reserve VM slot'
            $slot = Reserve-VMSlot -StatePath $statePath -Role $Role -RequestedName $VMName `
                                   -OSKey $OSKey -LabName $LabName
            if (-not $slot) { throw "Slot reservation failed for $Role in $LabName" }
            $op.Target = $slot.VMName   # update target now we have a concrete name
            $step | Complete-DLabOperationStep -Message "$($slot.VMName) at $($slot.IP)"

            # Pre-flight: no VM already has this name
            if (Get-VM -Name $slot.VMName -ErrorAction SilentlyContinue) {
                Fail-VMSlot -StatePath $statePath -VMName $slot.VMName
                throw "VM '$($slot.VMName)' already exists in Hyper-V. Remove it first with Remove-DLabVM."
            }

            $diskFullPath = Join-Path $diskPath "$($slot.VMName)-osdisk.vhdx"

            # ---- Step: create differencing disk -------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Create differencing disk'
            $null = New-DifferencingDisk -ParentPath $goldenInfo.Path `
                                         -DestinationPath $diskFullPath `
                                         -UnattendPath    $unattendPath `
                                         -ComputerName    $slot.ShortName `
                                         -AdminPassword   $adminPwd `
                                         -TimeZone        $timeZone `
                                         -InputLocale     $inputLocale `
                                         -UserLocale      $userLocale `
                                         -SystemLocale    $systemLocale
            $step | Complete-DLabOperationStep

            # ---- Step: deploy VM (role-dependent) -----------------------
            $step = Add-DLabOperationStep -Operation $op -Name "Deploy $Role ($($slot.VMName))"
            try {
                if ($Role -eq 'Server') {
                    $dcEntry = $state.VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
                    if (-not $dcEntry) { throw "Cannot add Server: lab has no DC. Run New-DLab first." }
                    $dcIP = $state.Network.DCIP
                    $null = Deploy-LabMember -VMName $slot.VMName -ShortName $slot.ShortName `
                                             -VHDXPath $diskFullPath -MemberIP $slot.IP `
                                             -NetConfig $state.Network -OSEntry $goldenInfo.Entry -DCIP $dcIP `
                                             -SwitchName $switchName -VMPath $vmPath -AdminPassword $adminPwd `
                                             -DomainName $domain -DomainNetbios $netbios `
                                             -GuestScriptPath $guestPath -Defaults $cfg `
                                             -MemoryGB $MemoryGB -CPU $CPU
                } else {   # DC
                    $null = Deploy-LabDC -VMName $slot.VMName -ShortName $slot.ShortName `
                                         -VHDXPath $diskFullPath -DCIP $slot.IP `
                                         -NetConfig $state.Network -OSEntry $goldenInfo.Entry `
                                         -SwitchName $switchName -VMPath $vmPath -AdminPassword $adminPwd `
                                         -DomainName $domain -DomainNetbios $netbios `
                                         -SafeModePassword $safeModePwd -GuestScriptPath $guestPath `
                                         -LabName $LabName -Defaults $cfg `
                                         -MemoryGB $MemoryGB -CPU $CPU -FixNLA:$FixNLA `
                                         -NoInternet:(-not $labHasInternet) `
                                         -AdditionalDC:$isAdditionalDC `
                                         -PrimaryDCIP $primaryDCIP
                }
                Complete-VMSlot -StatePath $statePath -VMName $slot.VMName
                $step | Complete-DLabOperationStep
            } catch {
                Fail-VMSlot -StatePath $statePath -VMName $slot.VMName
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # ---- Finalise ------------------------------------------------
            $null = $op | Complete-DLabOperation -Status Succeeded `
                          -Result @{ VMName = $slot.VMName; Role = $Role; IP = $slot.IP }
            Write-DLabEvent -Level Ok -Source 'Add-DLabVM' `
                -Message "$Role $($slot.VMName) added ($($slot.IP))" `
                -OperationId $op.OperationId

            # Emit via the same read path consumers use
            Get-DLabVM -LabName $LabName -VMName $slot.VMName

        } catch {
            Write-DLabEvent -Level Error -Source 'Add-DLabVM' `
                -Message "Add-DLabVM failed: $($_.Exception.Message)" `
                -OperationId $op.OperationId `
                -Data @{ Error = $_.Exception.Message }
            $null = $op | Complete-DLabOperation -Status Failed -ErrorMessage $_.Exception.Message
            throw
        }
    }
}
