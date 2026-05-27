Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $actionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $actionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $errorHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/ErrorHandling.Helpers.ps1'
    $environmentHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $bootstrapPath = Join-Path $PSScriptRoot '../../Bootstrap/Baseline.ps1'
    $initialActionsPath = Join-Path $PSScriptRoot '../../Module/Regions/InitialActions.psm1'
    $initialSetupPath = Join-Path $PSScriptRoot '../../Module/Regions/InitialSetup.psm1'
    $initialSetupManifestPath = Join-Path $PSScriptRoot '../../Module/Data/InitialSetup.json'
    $buildPrimaryTabsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildPrimaryTabs.ps1'
    $tabManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/TabManagement.ps1'
    $detectScriptblocksPath = Join-Path $PSScriptRoot '../../Module/GUI/DetectScriptblocks.ps1'

    $guiContent = Get-BaselineTestSourceText -Path $guiPath
    $actionHandlersContent = Get-BaselineTestSourceText -Path @(
        $actionHandlersPath
        (Join-Path $actionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $errorHelpersContent = Get-BaselineTestSourceText -Path $errorHelpersPath
    $environmentHelpersContent = Get-BaselineTestSourceText -Path $environmentHelpersPath
    $bootstrapContent = Get-BaselineTestSourceText -Path $bootstrapPath
    $initialActionsContent = Get-BaselineTestSourceText -Path $initialActionsPath
    $initialSetupContent = Get-BaselineTestSourceText -Path $initialSetupPath
    $buildPrimaryTabsContent = Get-BaselineTestSourceText -Path $buildPrimaryTabsPath
    $tabManagementContent = Get-BaselineTestSourceText -Path $tabManagementPath
    $detectScriptblocksContent = Get-BaselineTestSourceText -Path $detectScriptblocksPath
    $initialSetupManifest = Get-BaselineTestSourceText -Path $initialSetupManifestPath | ConvertFrom-Json -ErrorAction Stop
    $initialSetupAst = [System.Management.Automation.Language.Parser]::ParseFile($initialSetupPath, [ref]$null, [ref]$null)
    $initialSetupBootstrapFunction = $initialSetupAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Initialize-PackageManagersBootstrap'
    }, $true) | Select-Object -First 1
    $initialSetupCheckWinGetFunction = $initialSetupAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'CheckWinGet'
    }, $true) | Select-Object -First 1
}

Describe 'First-run startup command wiring' {
        It 'resolves first-run GUI commands before startup handlers run' {
                $guiContent | Should -Match "Get-Item function:Show-ThemedDialog"
                $guiContent | Should -Match "Get-Item function:Show-FirstRunWelcomeDialog"
                $guiContent | Should -Match "Get-UxFirstRunWelcomeMessage"
                $guiContent | Should -Match "Get-Command 'Show-HelpDialog'"
                $guiContent | Should -Match "Get-Command 'Set-GuiPresetSelection'"
                $guiContent | Should -Match "Get-Command 'Set-GuiStatusText'"
                $guiContent | Should -Match "Get-Command 'Get-UxRecommendedPresetName'"
                $guiContent | Should -Match "Get-Command 'Get-GuiFirstRunWelcomeMarkerPath'"
    }

    It 'uses the same runtime-command pattern for the New Start Here action' {
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-ThemedDialog'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-HelpDialog'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Set-GuiPresetSelection'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxRecommendedPresetName'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxPresetLoadedStatusText'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxFirstRunPrimaryActionLabel'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxFirstRunWelcomeMessage'"
        $actionHandlersContent | Should -Not -Match '\$welcomeMessage\s*=\s*Get-UxFirstRunWelcomeMessage'
        $actionHandlersContent | Should -Not -Match '\$choice\s*=\s*Show-ThemedDialog\s+-Title\s+''Welcome to Baseline'''
        $actionHandlersContent | Should -Match "Show-HelpDialog not found\."
    }

    It 'persists restore-last-session through the GUI preference store' {
        $actionHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''RestoreLastSession'' -Default \$true'
        $actionHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''RestoreLastSession'' -Value \$restoreLastSessionWanted'
    }

    It 'maps a missing help dialog function to the startup-command error code' {
        $errorHelpersContent | Should -Match "'\*Show-HelpDialog not found\*' \{ return 'GUI-STARTUP-004' \}"
    }

    It 'boots the package managers from the bootstrap scheduler after GUI startup decisions' {
        $bootstrapContent | Should -Match 'Invoke-BaselinePackageManagerStartupChecks -SkipWinGetCheck:\$skipStartupWinGetCheck -SkipChocolateyCheck:\$skipStartupChocolateyCheck'
        $initialActionsContent | Should -Not -Match 'Initialize-PackageManagersBootstrap\s+-LoadingSplash\s+\$Global:LoadingSplash'
        $initialActionsContent | Should -Not -Match 'CheckWinGet\s+-LoadingSplash\s+\$Global:LoadingSplash'
        $initialSetupContent | Should -Match '\[bool\]\s+\$IncludeChocolatey = \$true'
        $initialSetupContent | Should -Match 'if \(\$IncludeChocolatey\)'
    }

    It 'honors startup splash preferences before opening the GUI' {
        $bootstrapContent | Should -Match 'Get-BaselineStartupSplashSettings'
        $bootstrapContent | Should -Match 'RunInitialActions = \$true'
        $bootstrapContent | Should -Match 'WinGetCheckFrequency = ''Startup'''
        $bootstrapContent | Should -Match 'ChocolateyCheckFrequency = ''Startup'''
        $bootstrapContent | Should -Match 'function Get-BaselineBootstrapSplashStepOrder'
        $bootstrapContent | Should -Match 'Get-BaselineBootstrapSplashStepOrder -StartupSettings \$Script:StartupSplashSettings -IncludeUpdates:\$shouldPrimeUpdatesPulse'
        $bootstrapContent | Should -Match 'Show-BootstrapLoadingSplash[\s\S]*-StepOrder \$bootstrapSplashStepOrder'
        $bootstrapContent | Should -Match 'Get-BaselineStartupPackageManagerCheckDecision'' -CommandType Function -ErrorAction Stop'
        $bootstrapContent | Should -Match 'PackageManager ''WinGet'' -Enabled:\$startupWinGetEnabled -Frequency \$startupWinGetFrequency'
        $bootstrapContent | Should -Match 'PackageManager ''Chocolatey'' -Enabled:\$startupChocolateyEnabled -Frequency \$startupChocolateyFrequency'
        $bootstrapContent | Should -Match 'Test-BaselineStartupPackageManagerCheckDue -PackageManager ''WinGet'''
        $bootstrapContent | Should -Match 'Test-BaselineStartupPackageManagerCheckDue -PackageManager ''Chocolatey'''
        $bootstrapContent | Should -Match 'if \(\$Script:StartupSplashSettings -and \[bool\]\$Script:StartupSplashSettings.RunInitialActions\)'
        $bootstrapContent | Should -Match 'InitialActions skipped by startup splash settings\.'
        $bootstrapContent | Should -Match 'Invoke-BaselinePackageManagerStartupChecks -SkipWinGetCheck:\$skipStartupWinGetCheck -SkipChocolateyCheck:\$skipStartupChocolateyCheck'
        $bootstrapContent | Should -Match 'Invoke-BaselineInitialActions -SkipWinGetCheck:\$skipStartupWinGetCheck -SkipChocolateyCheck:\$skipStartupChocolateyCheck'
        $bootstrapContent | Should -Match 'Set-BaselineStartupPackageManagerChecksCompleted -WinGet:\$runStartupWinGetCheck -Chocolatey:\$runStartupChocolateyCheck'
        $initialActionsContent | Should -Match '\[switch\]\s+\$SkipWinGetCheck'
        $initialActionsContent | Should -Match '\[switch\]\s+\$SkipChocolateyCheck'
    }

    It 'starts the system splash step as initial checks begin' {
        $initialActionsContent | Should -Match 'function Start-BaselineInitialActionsSplashSystemStep'
        $initialActionsContent.Contains("Set-BootstrapLoadingSplashStep -Splash `$LoadingSplash -StepId 'system' -Status 'in_progress' -SubAction ''") | Should -BeTrue
        $initialActionsContent.Contains("Set-BootstrapLoadingSplashStep -Splash `$Global:LoadingSplash -StepId 'system'") | Should -BeFalse

        $beginChecksIndex = $initialActionsContent.IndexOf("LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_BeginningInitialChecks'")
        $systemStepIndex = $initialActionsContent.IndexOf('Start-BaselineInitialActionsSplashSystemStep', $beginChecksIndex)
        $clearErrorIndex = $initialActionsContent.IndexOf('$Global:Error.Clear()', $beginChecksIndex)

        $beginChecksIndex | Should -BeGreaterThan 0
        $systemStepIndex | Should -BeGreaterThan 0
        $clearErrorIndex | Should -BeGreaterThan 0
        $beginChecksIndex | Should -BeLessThan $systemStepIndex
        $systemStepIndex | Should -BeLessThan $clearErrorIndex
    }

    It 'restores the neutral splash loading text after startup bootstrap' {
        $environmentHelpersContent | Should -Match "GuiSplashLoading' -Fallback 'Please Wait\.\.\.'"
        $environmentHelpersContent | Should -Not -Match "GuiSplashLoading' -Fallback 'Please wait - opening GUI\.\.\.'"
    }

    It 'starts splash progress at zero with calmer live motion' {
        $environmentHelpersContent | Should -Not -Match 'LogoHeartbeat'
        $environmentHelpersContent | Should -Not -Match 'Storyboard\.TargetName="SplashCenterIcon"\s+Storyboard\.TargetProperty="Opacity"'
        $environmentHelpersContent | Should -Not -Match 'SubActionSpinnerRotate'
        $environmentHelpersContent | Should -Not -Match 'Name="SubActionSpinner"'
        $environmentHelpersContent | Should -Match '(?s)Storyboard\.TargetName="SplashSheenT".*?Duration="0:0:1\.4"'
        $environmentHelpersContent | Should -Match 'Set-BootstrapLoadingSplashState'' \$bootstrapLoadingSplashStateScriptBlock'
        $environmentHelpersContent | Should -Match '\$progressBarControl = if \(\$syncHash\.ContainsKey\(''ProgressBar''\)\) \{ \$syncHash\[''ProgressBar''\] \} else \{ \$null \}'
        $environmentHelpersContent | Should -Match '\$fillTo = \(\(\[double\]\$activeIdx \+ 0\.35\) / \$stepCount\) \* \$barWidth'
        $environmentHelpersContent | Should -Match 'Bootstrap splash initial progress failed'
        $environmentHelpersContent | Should -Match '\$sxa\.From = 1\.0; \$sxa\.To = 1\.4'
        $environmentHelpersContent | Should -Match '\$sxa\.Duration = New-Object System\.Windows\.Duration \(\[TimeSpan\]::FromMilliseconds\(360\)\)'
        $environmentHelpersContent | Should -Match '\$fillTo = \(\(\[double\]\$activeIdx \+ 0\.35\) / \$stepCount\) \* \$barWidth'
        $environmentHelpersContent | Should -Match '\$fillDurationMs = 2200'
        $environmentHelpersContent | Should -Match '\$fillDurationMs = 24000'
        $environmentHelpersContent | Should -Match '\$handoffCeiling = \$barWidth \* 0\.97'
    }

    It 'keeps the advisory tweaker probes non-fatal during startup' {
        $initialActionsContent | Should -Match '\$InvokeOptionalProbe\s*=\s*\{\s*param\(\[scriptblock\]\$ScriptBlock\)'
        $initialActionsContent | Should -Match '\$AutoSettingsPS\s*=\s*&\s*\$InvokeOptionalProbe'
        $initialActionsContent | Should -Match '\$Flibustier\s*=\s*&\s*\$InvokeOptionalProbe'
    }

    It 'keeps WinGet active in the startup bootstrap helper' {
        $wingetCommands = @($initialSetupBootstrapFunction.Body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.Extent.Text -match 'WinGetBootstrap'
        }, $true))
        $wingetCommands | Should -Not -BeNullOrEmpty

        $chocolateyCommands = @($initialSetupBootstrapFunction.Body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.Extent.Text -match 'ChocolateyBootstrap'
        }, $true))
        $chocolateyCommands | Should -Not -BeNullOrEmpty
    }

    It 'queues the Chocolatey startup bootstrap job whenever Chocolatey is missing' {
        $initialSetupContent | Should -Not -Match "Get-Command -Name 'Test-ChocolateyBootstrapApproved'"
        $initialSetupContent | Should -Not -Match '\$chocolateyBootstrapApproved'
        $initialSetupContent | Should -Not -Match '\$skipMessage'
        $initialSetupContent | Should -Match "Start-Job\s+-Name\s+'ChocolateyBootstrap'"
    }

    It 'bounds startup bootstrap jobs with explicit timeout tracking' {
        $initialSetupContent | Should -Match '\$bootstrapTimeoutSeconds = 900'
        $initialSetupContent | Should -Match '\$jobStartedAt = @\{\}'
        $initialSetupContent | Should -Match 'Invoke-WinGetBootstrap -TimeoutSeconds \$TimeoutSeconds'
        $initialSetupContent | Should -Match 'Invoke-ChocolateyBootstrap -TimeoutSeconds \$TimeoutSeconds'
        $initialSetupContent | Should -Match 'Package manager bootstrap job ''\{0\}'' timed out after \{1\} seconds'
        $initialSetupContent | Should -Match 'Stop-Job -Job \$runningJob -Force -ErrorAction SilentlyContinue'
    }

    It 'logs startup package-manager checks under component scopes instead of transient status text' {
        $initialSetupContent | Should -Match '\$packageManagerLogScope = ''PackageManager'''
        $initialSetupContent | Should -Match '\$wingetLogScope = ''Winget'''
        $initialSetupContent | Should -Match '\$chocolateyLogScope = ''Chocolatey'''
        $initialSetupContent | Should -Match 'Write-ConsoleStatus -Action \$checkingStatusText -Scope \$packageManagerLogScope'
        $initialSetupContent | Should -Match 'Bootstrap_PackageManagerAlreadyInstalled[\s\S]*-Scope \$wingetLogScope'
        $initialSetupContent | Should -Match 'Bootstrap_PackageManagerAlreadyInstalled[\s\S]*-Scope \$chocolateyLogScope'
        $initialSetupContent | Should -Not -Match "-Scope 'Checking installation status"
    }

        It 'uses the shared reviewed WinGet bootstrap metadata instead of duplicating the release pin' {
        $initialSetupContent | Should -Match 'Get-WinGetBootstrapInstallerMetadata'
        $initialSetupContent | Should -Not -Match '\$installerVersion\s*=\s*''5\.3\.1'''
        $initialSetupContent | Should -Not -Match '\$installerSha256\s*=\s*''029094EFD9D26A83AEA184B16D15C772D35D64E1288010741F50FD33A1E1F40F'''
    }

    It 'uses the shared generic WinGet bootstrap arguments so Server 2019 stays on the Baseline-defined path' {
        $initialSetupContent | Should -Match 'Get-WinGetBootstrapInstallerArguments'
        $initialSetupContent | Should -Not -Match "'-AlternateInstallMethod'"
    }

    It 'keeps CheckWinGet hidden while preserving the preset and headless hook' {
        $initialSetupCheckWinGetFunction | Should -Not -BeNullOrEmpty
        $detectScriptblocksContent | Should -Match '''CheckWinGet''\s*=\s*\{\s*\$false\s*\}'
        $tabManagementContent | Should -Match 'function Get-PrimaryTabVisibleTweakCount'
        $tabManagementContent | Should -Match 'Test-TweakMatchesCurrentFilters'
        $buildPrimaryTabsContent | Should -Match 'Get-PrimaryTabVisibleTweakCount\s+-PrimaryTab\s+\$pKey'

        $checkWinGetEntry = @($initialSetupManifest.Entries | Where-Object { [string]$_.Function -eq 'CheckWinGet' })
        $checkWinGetEntry | Should -Not -BeNullOrEmpty
        [string]$checkWinGetEntry[0].Name | Should -Be 'Check WinGet'
        [string]$checkWinGetEntry[0].Description | Should -Not -BeNullOrEmpty

        $packageManagerEntries = @(
            $initialSetupManifest.Entries | Where-Object {
                [string]$_.Name -eq 'Check and Install Package Managers' -or
                [string]$_.Function -eq 'Initialize-PackageManagers'
            }
        )
        $packageManagerEntries | Should -BeNullOrEmpty
    }
}
