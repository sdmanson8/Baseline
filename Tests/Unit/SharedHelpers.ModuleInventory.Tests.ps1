Set-StrictMode -Version Latest

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
}

AfterAll {
    Remove-Module SharedHelpers -Force -ErrorAction SilentlyContinue
    foreach ($helperModule in @(Get-Module 'Baseline.SharedHelpers.*'))
    {
        Remove-Module -ModuleInfo $helperModule -Force -ErrorAction SilentlyContinue
    }
}

Describe 'SharedHelpers helper module inventory' {
    BeforeEach {
        Remove-Module SharedHelpers -Force -ErrorAction SilentlyContinue
        foreach ($helperModule in @(Get-Module 'Baseline.SharedHelpers.*'))
        {
            Remove-Module -ModuleInfo $helperModule -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports helper slices as explicit named modules' {
        Import-Module $script:ModulePath -Force

        $helperModules = @(Get-Module 'Baseline.SharedHelpers.*')

        $helperModules.Count | Should -Be 43
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.Manifest'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.GameMode'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.SingleInstance'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.RemoteTarget'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.RemovalPersistence'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.UserApps'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.NetworkHardening'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.BrowserPolicies'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.Json'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.Process'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.CliMode'
        $helperModules.Name | Should -Contain 'Baseline.SharedHelpers.WindowsUpdate'
    }

    It 'surfaces helper exports through Get-Module inventory' {
        Import-Module $script:ModulePath -Force

        $manifestModule = Get-Module 'Baseline.SharedHelpers.Manifest'
        $gameModeModule = Get-Module 'Baseline.SharedHelpers.GameMode'
        $singleInstanceModule = Get-Module 'Baseline.SharedHelpers.SingleInstance'
        $remoteTargetModule = Get-Module 'Baseline.SharedHelpers.RemoteTarget'
        $initialActionsModule = Get-Module 'Baseline.SharedHelpers.InitialActions'
        $windowsUpdateModule = Get-Module 'Baseline.SharedHelpers.WindowsUpdate'
        $schedulerModule = Get-Module 'Baseline.SharedHelpers.Scheduler'
        $cliModeModule = Get-Module 'Baseline.SharedHelpers.CliMode'
        $environmentModule = Get-Module 'Baseline.SharedHelpers.Environment'

        $manifestModule.ExportedCommands.Keys | Should -Contain 'Get-TweakManifestEntryValue'
        $manifestModule.ExportedCommands.Keys | Should -Contain 'Import-TweakManifestFromData'
        $environmentModule.ExportedCommands.Keys | Should -Contain 'Get-BaselineUpdateAsset'
        $environmentModule.ExportedCommands.Keys | Should -Contain 'Get-BaselineUpdateAssetPattern'
        $gameModeModule.ExportedCommands.Keys | Should -Contain 'Get-GameModeProfileDefinitions'
        $gameModeModule.ExportedCommands.Keys | Should -Contain 'Test-GameModeManifestDefaultEnabled'
        $singleInstanceModule.ExportedCommands.Keys | Should -Contain 'Get-BaselineSingleInstanceMutexName'
        $singleInstanceModule.ExportedCommands.Keys | Should -Contain 'Test-BaselineSingleInstanceLockAvailable'
        $singleInstanceModule.ExportedCommands.Keys | Should -Contain 'Resolve-BaselineSingleInstanceDecision'
        (Get-Module 'Baseline.SharedHelpers.PlatformSupport').ExportedCommands.Keys | Should -Contain 'Get-BaselinePlatformFilterOverride'
        (Get-Module 'Baseline.SharedHelpers.PlatformSupport').ExportedCommands.Keys | Should -Contain 'Update-BaselineManifestExecutionSupport'
        $remoteTargetModule.ExportedCommands.Keys | Should -Contain 'Resume-BaselineRemoteOrchestration'
        $initialActionsModule.ExportedCommands.Keys | Should -Contain 'Resolve-BaselineSettingsAppsFeaturesHealthAssessment'
        $initialActionsModule.ExportedCommands.Keys | Should -Contain 'Resolve-BaselineScreenSnippingHealthAssessment'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Get-WindowsUpdateList'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Install-WindowsSecurityUpdates'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Download-WindowsUpdates'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Install-WindowsUpdates'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Get-WindowsUpdateStatus'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Get-WindowsUpdateCompliance'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Invoke-BaselineWindowsUpdateScheduledRun'
        $windowsUpdateModule.ExportedCommands.Keys | Should -Contain 'Get-WindowsUpdateHistory'
        $schedulerModule.ExportedCommands.Keys | Should -Contain 'Register-BaselineWindowsUpdateScheduledRun'
        $cliModeModule.ExportedCommands.Keys | Should -Contain 'Get-BaselinePresetCatalog'
        $cliModeModule.ExportedCommands.Keys | Should -Contain 'Format-BaselinePresetCatalog'
    }

    It 'imports helper slices with fail-fast diagnostics' {
        $content = Get-Content -LiteralPath $script:ModulePath -Raw -Encoding UTF8

        $content | Should -Match 'Import-Module -Name \$helperModulePath.*-ErrorAction Stop'
        $content | Should -Match 'Failed to import shared helper module'
        $content | Should -Match '\$helperModuleName'
        $content | Should -Match '\$helperModulePath'
        $content | Should -Match 'New-Object System\.InvalidOperationException'
    }

    It 'fails startup with helper module context when a helper slice import fails' {
        $sourceModuleRoot = Split-Path -Path $script:ModulePath -Parent
        $testModuleRoot = Join-Path $TestDrive 'Module'
        New-Item -ItemType Directory -Path $testModuleRoot -Force | Out-Null

        Copy-Item -LiteralPath $script:ModulePath -Destination $testModuleRoot -Force
        Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'SharedHelpers') -Destination $testModuleRoot -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $sourceModuleRoot 'SharedHelperModules') -Destination $testModuleRoot -Recurse -Force

        $brokenHelperPath = Join-Path $testModuleRoot 'SharedHelperModules/Baseline.SharedHelpers.Json.psm1'
        Set-Content -LiteralPath $brokenHelperPath -Encoding UTF8 -Value "throw 'broken helper import'"

        { Import-Module (Join-Path $testModuleRoot 'SharedHelpers.psm1') -Force -ErrorAction Stop } |
            Should -Throw "*Failed to import shared helper module 'Baseline.SharedHelpers.Json'*broken helper import*"
    }

    It 'exports one policy-tool resolver that points at the bundled executable' {
        Import-Module $script:ModulePath -Force

        Get-Command -Name Resolve-BaselinePolicyToolPath -CommandType Function | Should -Not -BeNullOrEmpty
        Resolve-BaselinePolicyToolPath | Should -Match '\\Assets\\BaselinePolicyTool\.exe$'
    }

    It 'exports update release asset helpers through SharedHelpers' {
        Import-Module $script:ModulePath -Force

        Get-Command -Name Get-BaselineUpdateAsset -CommandType Function | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-BaselineUpdateAssetPattern -CommandType Function | Should -Not -BeNullOrEmpty

        $moduleRoot = Split-Path -Path $script:ModulePath -Parent
        $manifest = Import-PowerShellDataFile -Path (Join-Path $moduleRoot 'Baseline.psd1')
        $versionText = [string]$manifest.ModuleVersion
        $stableAssetName = 'Baseline-{0}-stable.zip' -f $versionText
        $betaAssetName = 'Baseline-{0}-beta.zip' -f $versionText

        $asset = Get-BaselineUpdateAsset -Assets @(
            [pscustomobject]@{ name = $stableAssetName }
            [pscustomobject]@{ name = $betaAssetName }
        ) -Pattern (Get-BaselineUpdateAssetPattern -Branch Beta)

        [string]$asset.name | Should -Be $betaAssetName
    }

    It 'removes helper slice modules when SharedHelpers is unloaded' {
        Import-Module $script:ModulePath -Force
        @(Get-Module 'Baseline.SharedHelpers.*').Count | Should -Be 43

        Remove-Module SharedHelpers -Force

        @(Get-Module 'Baseline.SharedHelpers.*').Count | Should -Be 0
    }
}
