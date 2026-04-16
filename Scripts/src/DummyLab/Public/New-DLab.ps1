# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLab {
    <#
    .SYNOPSIS
        Creates a new Dummy.Lab lab with its first Domain Controller.
    .DESCRIPTION
        Allocates a /27 segment from the shared DLab supernet (10.74.18.0/23),
        ensures the shared switch (DLab-Internal) and NAT (DLab-NAT) exist,
        creates the lab's storage layout, initial state file, then reserves
        and deploys DC01 from a golden image.

        Accepts pipeline input from New-DLabGoldenImage / Get-DLabGoldenImage
        so chains like:
            Get-DLabGoldenImage -OSKey WS2025_DC | Select -First 1 | New-DLab -LabName Demo
        bind cleanly through OSKey and ImagePath property names.

        Every orchestration step is recorded as a DLab.OperationStep; the
        whole run is a DLab.Operation queryable via Get-DLabOperation.
    .PARAMETER LabName
        Name of the lab to create. Defaults to the LabName configured in
        DLab.Defaults.psd1 ('Dummy' out of the box) when neither the
        parameter nor a pipeline input is supplied. Used for storage path,
        domain derivation (when DomainName is not explicit), and VM naming
        prefix.
    .PARAMETER OSKey
        OS catalog key (e.g. WS2025_DC). Resolves to the latest matching
        golden image. Binds from pipeline by property name (alias: OS).
    .PARAMETER GoldenImage
        Explicit path to a golden image VHDX. Overrides OSKey lookup.
        Binds from pipeline by property name as ImagePath.
    .PARAMETER Segment
        Override the /27 segment number (0-15). When omitted, the next free
        segment starting at LabSegmentFirst (1) is auto-selected.
        Segment 0 is reserved for staging (golden-image builds).
    .PARAMETER MemoryGB, CPU
        Override default VM sizing from the OS catalog.
    .PARAMETER DomainName, DomainNetbios
        Override the default domain naming (derived from LabName + config
        DomainSuffix).
    .PARAMETER AdminPassword, SafeModePassword
        Override the admin and DSRM passwords from config.
    .PARAMETER FixNLA
        Apply the NLA dependency workaround during DC promotion.
    .EXAMPLE
        New-DLab -LabName Demo
    .EXAMPLE
        New-DLab -LabName Prod -OSKey WS2025_DC
    .EXAMPLE
        Get-DLabGoldenImage -OSKey WS2025_DC | Sort BuildDate -Descending |
            Select-Object -First 1 | New-DLab -LabName Demo
    .EXAMPLE
        # Full pipeline
        New-DLab -LabName Demo | Add-DLabVM -Role Server | Add-DLabVM -Role Server
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Lab-only credentials - intentional plaintext for automation')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.Lab')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [string]$LabName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('OS')]
        [string]$OSKey            = '',

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ImagePath')]
        [string]$GoldenImage      = '',

        [int]$MemoryGB            = 0,
        [int]$CPU                 = 0,

        [string]$DomainName       = '',
        [string]$DomainNetbios    = '',

        [int]$Segment             = -1,    # -1 = auto-select

        [string]$AdminPassword    = '',
        [string]$SafeModePassword = '',

        [switch]$NoInternet,
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

        if (-not $PSCmdlet.ShouldProcess($LabName, "Create lab with DC01")) { return }

        # -----------------------------------------------------------------
        # Parameter resolution (merging explicit values with config defaults)
        # -----------------------------------------------------------------
        $adminPwd    = if ($AdminPassword)    { $AdminPassword }    else { $cfg.AdminPassword }
        $safeModePwd = if ($SafeModePassword) { $SafeModePassword } else { $cfg.SafeModePassword }

        $domain  = if ($DomainName)    { $DomainName }    else { "$($LabName.ToLower()).$($cfg.DomainSuffix)" }
        $netbios = if ($DomainNetbios) { $DomainNetbios } else { $LabName.Substring(0, [Math]::Min($LabName.Length, 15)) }

        $labsRoot    = Get-DLabStorePath -Kind Labs
        $labDir      = Get-DLabStorePath -Kind LabDir -LabName $LabName
        $vmPath      = Join-Path $labDir 'VMs'
        $diskPath    = Join-Path $labDir 'Disks'
        $statePath   = Get-DLabStorePath -Kind LabState -LabName $LabName
        $scriptsPath = Join-Path (Get-DLabStorePath -Kind Root) 'Scripts'
        $unattendPath = Join-Path $scriptsPath 'Config\unattend-server.xml'
        $guestPath   = Join-Path $scriptsPath 'GuestScripts'

        # Locale (auto = detect from host)
        $timeZone    = if ($cfg.TimeZone    -eq 'auto') { (Get-TimeZone).Id }    else { $cfg.TimeZone }
        $inputLocale = if ($cfg.InputLocale -eq 'auto') {
            $hostLang = Get-WinUserLanguageList | Select-Object -First 1
            if ($hostLang -and $hostLang.InputMethodTips) { $hostLang.InputMethodTips[0] } else { (Get-Culture).Name }
        } else { $cfg.InputLocale }
        $userLocale   = if ($cfg.UserLocale   -eq 'auto') { (Get-Culture).Name } else { $cfg.UserLocale }
        $systemLocale = if ($cfg.SystemLocale -eq 'auto') { (Get-Culture).Name } else { $cfg.SystemLocale }

        # -----------------------------------------------------------------
        # Pre-flight: lab doesn't already exist
        # -----------------------------------------------------------------
        $existingVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^$LabName-(DC|SRV)" })
        if ($existingVMs.Count -gt 0) {
            throw "Lab '$LabName' already exists ($($existingVMs.Count) VM(s) with the '$LabName-' prefix). Tear it down first with: Remove-DLab -Name $LabName -Confirm:`$false  -- or pick a different -LabName."
        }
        if (Test-Path $statePath) {
            throw @"
Lab '$LabName' state file already exists at: $statePath
This usually means a previous New-DLab failed mid-flight and the partial state was not rolled back.
Clean up with: Remove-DLab -Name $LabName -Confirm:`$false
That will honour whatever the partial state recorded (storage folder, VMs) and remove only those pieces.
"@
        }

        # -----------------------------------------------------------------
        # Start the operation
        # -----------------------------------------------------------------
        $op = New-DLabOperation -Kind 'New-DLab' -Target $LabName -LabName $LabName `
                                -Parameters @{
                                    LabName     = $LabName
                                    OSKey       = $OSKey
                                    GoldenImage = $GoldenImage
                                    Segment     = $Segment
                                }
        Write-DLabEvent -Level Step -Source 'New-DLab' `
            -Message "Creating lab '$LabName' ($domain)" `
            -OperationId $op.OperationId `
            -Data @{ LabName = $LabName; DomainName = $domain }

        try {
            # ---- Step: ensure shared infrastructure ----------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Ensure shared infrastructure'
            Ensure-DLabSharedInfrastructure
            $step | Complete-DLabOperationStep -Message 'DLab-Internal switch + DLab-NAT ready'

            # ---- Step: allocate /27 segment ------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Allocate network segment'
            $segIndex = if ($Segment -ge 0) { $Segment } else {
                Get-Free27Segment -LabsRoot $labsRoot
            }
            if ($null -eq $segIndex) {
                throw "No free /27 segment available (all 15 lab segments 1-15 are in use)."
            }
            $segConfig = Get-27SegmentConfig -Segment $segIndex
            $step | Complete-DLabOperationStep -Message "Segment $segIndex -> $($segConfig.NetworkCIDR)"

            # ---- Step: create per-lab network switch --------------------
            $labSwitchName = "DLab-$LabName"
            $step = Add-DLabOperationStep -Operation $op -Name 'Create lab network switch'
            Write-LabLog "Creating switch '$labSwitchName'..." -Level Info
            $existingLabSwitch = Get-VMSwitch -Name $labSwitchName -ErrorAction SilentlyContinue
            if ($existingLabSwitch) {
                Write-LabLog "Switch '$labSwitchName' already present." -Level Detail
            } else {
                New-VMSwitch -Name $labSwitchName -SwitchType Internal -ErrorAction Stop | Out-Null
            }
            $labAdapterName = "vEthernet ($labSwitchName)"
            for ($i = 0; $i -lt 10; $i++) {
                if (Get-NetAdapter -Name $labAdapterName -ErrorAction SilentlyContinue) { break }
                Start-Sleep -Seconds 1
            }
            $existingGW = Get-NetIPAddress -InterfaceAlias $labAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                          Where-Object { $_.IPAddress -eq $segConfig.Gateway -and $_.PrefixLength -eq 27 }
            if (-not $existingGW) {
                Get-NetIPAddress -InterfaceAlias $labAdapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceAlias $labAdapterName `
                                 -IPAddress $segConfig.Gateway -PrefixLength 27 `
                                 -ErrorAction Stop | Out-Null
            }
            $step | Complete-DLabOperationStep -Message "$labSwitchName @ $($segConfig.Gateway)/27"

            # ---- Step: resolve golden image -----------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Resolve golden image'
            $goldenInfo = Resolve-DLabGoldenImageInternal -OSKey $OSKey -ExplicitPath $GoldenImage
            if (-not $goldenInfo) { throw "No golden image resolved. Run New-DLabGoldenImage or specify -GoldenImage." }
            $OSKey = $goldenInfo.OSKey
            $step | Complete-DLabOperationStep -Message "$($goldenInfo.OSKey) -> $(Split-Path $goldenInfo.Path -Leaf)"

            # ---- Step: create storage folders ---------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Create storage folders'
            @($labsRoot, $labDir, $vmPath, $diskPath) | ForEach-Object {
                if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
            }
            $step | Complete-DLabOperationStep

            # ---- Step: initialise state ---------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Initialise lab state'
            $labState = New-LabState -Lab $LabName -Domain $domain -DomainNetbios $netbios `
                                     -SegConfig $segConfig -LabSwitchName $labSwitchName `
                                     -HasInternet (-not $NoInternet.IsPresent) `
                                     -DNSForwarder $cfg.DNSForwarder
            Write-LabState -State $labState -Path $statePath
            $null = Update-LabStateLocked -Path $statePath -UpdateScript {
                param($s) Add-InfraToState -State $s -Resource 'Storage' -Value $labDir
            }
            $step | Complete-DLabOperationStep -Message "Segment $segIndex | $($segConfig.NetworkCIDR) | gateway $($segConfig.Gateway)"

            # ---- Step: reserve DC slot ----------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Reserve DC slot'
            $dcSlot = Reserve-VMSlot -StatePath $statePath -Role 'DC' -RequestedName 'DC01' `
                                     -OSKey $OSKey -LabName $LabName
            $step | Complete-DLabOperationStep -Message "$($dcSlot.VMName) at $($dcSlot.IP)"

            # ---- Step: create differencing disk -------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Create differencing disk'
            $diskFullPath = Join-Path $diskPath "$($dcSlot.VMName)-osdisk.vhdx"
            $null = New-DifferencingDisk -ParentPath $goldenInfo.Path `
                                         -DestinationPath $diskFullPath `
                                         -UnattendPath    $unattendPath `
                                         -ComputerName    $dcSlot.ShortName `
                                         -AdminPassword   $adminPwd `
                                         -TimeZone        $timeZone `
                                         -InputLocale     $inputLocale `
                                         -UserLocale      $userLocale `
                                         -SystemLocale    $systemLocale
            $step | Complete-DLabOperationStep

            # ---- Step: deploy DC ----------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name "Deploy DC ($($dcSlot.VMName))"
            $null = Deploy-LabDC -VMName $dcSlot.VMName -ShortName $dcSlot.ShortName `
                                 -VHDXPath $diskFullPath -DCIP $dcSlot.IP `
                                 -NetConfig $segConfig -OSEntry $goldenInfo.Entry `
                                 -SwitchName $labSwitchName -VMPath $vmPath `
                                 -AdminPassword $adminPwd `
                                 -DomainName $domain -DomainNetbios $netbios `
                                 -SafeModePassword $safeModePwd -GuestScriptPath $guestPath `
                                 -LabName $LabName -Defaults $cfg `
                                 -MemoryGB $MemoryGB -CPU $CPU -FixNLA:$FixNLA -NoInternet:$NoInternet
            Complete-VMSlot -StatePath $statePath -VMName $dcSlot.VMName
            $step | Complete-DLabOperationStep

            # ---- Finalise and emit DLab.Lab ----------------------------
            $null = $op | Complete-DLabOperation -Status Succeeded `
                          -Result @{ LabName = $LabName; DomainName = $domain; DCIP = $dcSlot.IP; Segment = $segIndex }

            Write-DLabEvent -Level Ok -Source 'New-DLab' `
                -Message "Lab '$LabName' ready ($domain) on segment $segIndex ($($segConfig.NetworkCIDR))" `
                -OperationId $op.OperationId

            Get-DLab -Name $LabName

        } catch {
            Write-DLabEvent -Level Error -Source 'New-DLab' `
                -Message "New-DLab failed: $($_.Exception.Message)" `
                -OperationId $op.OperationId `
                -Data @{ Error = $_.Exception.Message }
            $null = $op | Complete-DLabOperation -Status Failed -ErrorMessage $_.Exception.Message
            throw
        }
    }
}
