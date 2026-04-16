# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabGoldenImage {
    <#
    .SYNOPSIS
        Builds a new golden image from a Windows Server ISO.
    .DESCRIPTION
        Orchestrates the six build phases, each wrapped in its own
        DLab.OperationStep so a failed run can be diagnosed down to the
        exact phase that broke. Phase helpers live in the Private tier and
        are not intended for direct use.

        Phases:
          1. Plan      Normalize OS key, resolve ISO, compute paths.
          2. ApplyWIM  Create VHDX from ISO with unattend injection.
          3. Boot      Temp switch/NAT, create VM, boot, wait for PS Direct.
          4. Patch     Windows Update rounds (skipped when -SkipUpdates).
          5. Sysprep   Guest prep + shutdown.
          6. Finalize  Remove temp resources, compact, protect, pointer.

        Typical runtime: 8 to 15 min unpatched, 30 to 60 min with updates.

        On success, re-emits the finished image via Get-DLabGoldenImage so
        downstream pipelines (New-DLab, Add-DLabVM) bind cleanly. On
        failure, the operation is marked Failed with the phase that broke
        and temp resources are best-effort cleaned up.
    .PARAMETER OSKey
        OS catalog key (e.g. WS2025_DC, or the dashed form WS2025-DC).
    .PARAMETER ISO
        Specific ISO file to use. Auto-detected from the catalog if omitted.
    .PARAMETER SkipUpdates
        Skip Windows Update rounds. Produces an *-unpatched.vhdx suitable
        for dev/testing.
    .PARAMETER ImageIndex
        Override the WIM image index. Default comes from the catalog entry.
    .EXAMPLE
        New-DLabGoldenImage -OSKey WS2025_DC -SkipUpdates
    .EXAMPLE
        New-DLabGoldenImage -OSKey WS2022_STD | New-DLab -LabName Demo
    .NOTES
        Author : Tom Stryhn
        Version : 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.GoldenImage')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('OS')]
        [string]$OSKey,

        [string]$ISO = '',

        [switch]$SkipUpdates,

        [int]$ImageIndex = 0
    )

    process {
        if (-not $PSCmdlet.ShouldProcess("OS $OSKey", 'Build golden image')) { return }

        # Turn on host echo so Write-LabLog narrative surfaces for the operator
        # for the duration of the build. Reset in finally.
        $priorRender = $script:DLabRenderToHost
        $script:DLabRenderToHost = $true

        $op = New-DLabOperation -Kind 'New-DLabGoldenImage' -Target $OSKey `
                                -Parameters @{
                                    OSKey       = $OSKey
                                    ISO         = $ISO
                                    SkipUpdates = [bool]$SkipUpdates
                                    ImageIndex  = $ImageIndex
                                }

        Write-DLabEvent -Level Step -Source 'New-DLabGoldenImage' `
            -Message "Building golden image for $OSKey$(if ($SkipUpdates) { ' (unpatched)' })" `
            -OperationId $op.OperationId `
            -Data @{ OSKey = $OSKey; SkipUpdates = [bool]$SkipUpdates }

        $plan  = $null
        $boot  = $null

        try {
            # --- Phase 1: Plan ------------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Plan'
            try {
                $plan = Resolve-GoldenImagePlan -OSKey $OSKey -ISO $ISO `
                                                -SkipUpdates:$SkipUpdates -ImageIndex $ImageIndex
                $step | Complete-DLabOperationStep -Status Succeeded -Message "Plan -> $($plan.ImageName).vhdx"
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # Short-circuit: already built today.
            if ($plan.Skip) {
                Write-Host "  [~] Build skipped - image already exists for today: $(Split-Path $plan.VHDXPath -Leaf)" -ForegroundColor DarkGray
                Write-DLabEvent -Level Info -Source 'New-DLabGoldenImage' `
                    -Message 'Build skipped - reusing existing image' `
                    -OperationId $op.OperationId `
                    -Data @{ ImagePath = $plan.VHDXPath; Status = 'AlreadyExists' }
                $null = $op | Complete-DLabOperation -Status Succeeded -Result @{
                    OSKey     = $plan.OSKey
                    ImagePath = $plan.VHDXPath
                    Status    = 'AlreadyExists'
                }
                return Get-DLabGoldenImage -Name (Split-Path $plan.VHDXPath -Leaf) | Select-Object -First 1
            }

            # --- Phase 2: ApplyWIM --------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'ApplyWIM'
            try {
                New-GoldenImageVHDX -Plan $plan
                $step | Complete-DLabOperationStep -Status Succeeded
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # --- Phase 3: Boot ------------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Boot'
            try {
                Start-GoldenImageBuildVM -Plan $plan
                $boot = $true
                $step | Complete-DLabOperationStep -Status Succeeded
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # --- Phase 4: Patch -----------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Patch'
            try {
                $patchStatus = Invoke-GoldenImageUpdate -Plan $plan
                $termStatus  = if ($patchStatus -eq 'Skipped') { 'Skipped' } else { 'Succeeded' }
                $step | Complete-DLabOperationStep -Status $termStatus -Message "Patch: $patchStatus"
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # --- Phase 5: Sysprep ---------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Sysprep'
            try {
                Invoke-GoldenImageSysprep -Plan $plan
                $step | Complete-DLabOperationStep -Status Succeeded
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # --- Phase 6: Finalize --------------------------------------------
            $step = Add-DLabOperationStep -Operation $op -Name 'Finalize'
            try {
                $final = Complete-GoldenImageBuild -Plan $plan
                $step | Complete-DLabOperationStep -Status Succeeded -Message "$($final.ImageName) ($($final.SizeGB) GB)"
            } catch {
                $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
                throw
            }

            # Success: complete the operation and re-emit the image.
            $null = $op | Complete-DLabOperation -Status Succeeded -Result @{
                OSKey       = $plan.OSKey
                ImagePath   = $final.ImagePath
                ImageName   = $final.ImageName
                SizeGB      = $final.SizeGB
                DurationMin = $final.DurationMin
                Updates     = if ($plan.InstallUpdates) { 'Installed' } else { 'Skipped' }
            }

            Write-DLabEvent -Level Ok -Source 'New-DLabGoldenImage' `
                -Message "Built $($plan.OSKey) -> $($final.ImageName) ($($final.SizeGB) GB, $($final.DurationMin) min)" `
                -OperationId $op.OperationId `
                -Data @{
                    ImagePath   = $final.ImagePath
                    SizeGB      = $final.SizeGB
                    DurationMin = $final.DurationMin
                }

            Get-DLabGoldenImage -Name $final.ImageName | Select-Object -First 1

        } catch {
            Write-DLabEvent -Level Error -Source 'New-DLabGoldenImage' `
                -Message "Build failed for ${OSKey}: $($_.Exception.Message)" `
                -OperationId $op.OperationId `
                -Data @{ OSKey = $OSKey; Error = $_.Exception.Message }

            # Best-effort temp-resource cleanup so a failed build does not leak
            # Hyper-V artifacts or NetNat entries that would collide with the
            # next attempt.
            if ($plan -and $boot) {
                try { Stop-GoldenImageBuildCleanup -Plan $plan } catch { }
            }

            $null = $op | Complete-DLabOperation -Status Failed -ErrorMessage $_.Exception.Message
            throw
        } finally {
            $script:DLabRenderToHost = $priorRender
        }
    }
}
