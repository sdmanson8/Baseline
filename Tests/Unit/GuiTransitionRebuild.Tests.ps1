Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $appsModulePath = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule.ps1'
    $appsModuleSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule'
    $showTweakGuiSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/Show-TweakGUI'
    $buildPrimaryTabsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildPrimaryTabs.ps1'
    $buildTabContentPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildTabContent.ps1'
    $buildTweakControlsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildTweakControls.ps1'
    $applyThemePath = Join-Path $PSScriptRoot '../../Module/GUI/ApplyTheme.ps1'
    $contentManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/ContentManagement.ps1'
    $styledControlsSetupPath = Join-Path $PSScriptRoot '../../Module/GUI/StyledControlsSetup.ps1'
    $dialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $mainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $stylePath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $applicationsViewPath = Join-Path $PSScriptRoot '../../Module/GUI/ApplicationsView.ps1'
    $deploymentMediaBuilderViewPath = Join-Path $PSScriptRoot '../../Module/GUI/DeploymentMediaBuilderView.ps1'
    $presetUiPath = Join-Path $PSScriptRoot '../../Module/GUI/PresetUI.ps1'
    $actionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $actionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $categoryInitializationPath = Join-Path $showTweakGuiSplitRoot 'WpfCategoryInitialization.ps1'
    $categoryPathMappingPath = Join-Path $showTweakGuiSplitRoot 'CategoryPathMapping.ps1'
    $availabilityStateOverridesPath = Join-Path $showTweakGuiSplitRoot 'AvailabilityStateOverrides.ps1'
    $stateTransitionPath = Join-Path $PSScriptRoot '../../Module/GUI/StateTransitions.ps1'
    $sessionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $gameModePath = Join-Path $PSScriptRoot '../../Module/GUI/GameModeUI.ps1'
    $presetSelectionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/PresetManagement/PresetSelectionState.ps1'
    $updatesPanelPath = Join-Path $PSScriptRoot '../../Module/GUI/UpdatesPanel.ps1'
    $searchFilterHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/SearchFilterHandlers.ps1'

    $script:GuiContent = @(
        Get-BaselineTestSourceText -Path $mainWindowPath
        Get-BaselineTestSourceText -Path $guiPath
        Get-BaselineTestSourceText -Path $deploymentMediaBuilderViewPath
        Get-BaselineTestSourceText -Path @(
            (Join-Path $showTweakGuiSplitRoot 'ContentRenderedStartupCompletion.ps1')
            (Join-Path $showTweakGuiSplitRoot 'FirstRunAndSplashHandoff.ps1')
            (Join-Path $showTweakGuiSplitRoot 'ShowDialogErrorHandling.ps1')
        )
        Get-BaselineTestSourceText -Path @(
            $appsModulePath
            (Join-Path $appsModuleSplitRoot 'CatalogHelpers.ps1')
            (Join-Path $appsModuleSplitRoot 'SelectionQueueState.ps1')
            (Join-Path $appsModuleSplitRoot 'ProgressNavChrome.ps1')
        )
        Get-BaselineTestSourceText -Path $buildPrimaryTabsPath
        Get-BaselineTestSourceText -Path $buildTabContentPath
        Get-BaselineTestSourceText -Path $buildTweakControlsPath
        Get-BaselineTestSourceText -Path $applyThemePath
        Get-BaselineTestSourceText -Path $updatesPanelPath
        Get-BaselineTestSourceText -Path $searchFilterHandlersPath
    ) -join "`n"
    $script:MainWindowContent = Get-BaselineTestSourceText -Path $mainWindowPath
    $script:BuildPrimaryTabsContent = Get-BaselineTestSourceText -Path $buildPrimaryTabsPath
    $script:BuildTabContentContent = Get-BaselineTestSourceText -Path $buildTabContentPath
    $script:StyleContent = Get-BaselineTestSourceText -Path $stylePath
    $script:ApplicationsViewContent = Get-BaselineTestSourceText -Path $applicationsViewPath
    $script:DeploymentMediaBuilderViewContent = Get-BaselineTestSourceText -Path $deploymentMediaBuilderViewPath
    $script:ContentManagementContent = Get-BaselineTestSourceText -Path $contentManagementPath
    $script:StyledControlsSetupContent = Get-BaselineTestSourceText -Path $styledControlsSetupPath
    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path $dialogHelpersPath
    $script:PresetUiContent = Get-BaselineTestSourceText -Path $presetUiPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $actionHandlersPath
        (Join-Path $actionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $actionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:CategoryInitializationContent = Get-BaselineTestSourceText -Path $categoryInitializationPath
    $script:CategoryPathMappingContent = Get-BaselineTestSourceText -Path $categoryPathMappingPath
    $script:AvailabilityStateOverridesContent = Get-BaselineTestSourceText -Path $availabilityStateOverridesPath
    $script:StateTransitionContent = Get-BaselineTestSourceText -Path $stateTransitionPath
    $script:SessionStateContent = Get-BaselineTestSourceText -Path $sessionStatePath
    $script:GameModeContent = Get-BaselineTestSourceText -Path $gameModePath
    $script:PresetSelectionStateContent = Get-BaselineTestSourceText -Path $presetSelectionStatePath
    $script:UpdatesPanelContent = Get-BaselineTestSourceText -Path $updatesPanelPath
}

Describe 'Focused GUI rebuilds' {
    It 'keeps idle startup work guarded and cancels hidden tab builds outside Optimize mode' {
        $script:GuiContent | Should -Match 'function Build-TabContent'
        $script:GuiContent | Should -Match '\[switch\]\$SkipIdlePrebuild'
        $script:BuildTabContentContent | Should -Match 'function Stop-GuiTabContentBackgroundBuilds'
        $script:BuildTabContentContent | Should -Match 'function Test-GuiIdleTabPrebuildAllowed'
        $script:BuildTabContentContent | Should -Match 'Stop-GuiTabContentBackgroundBuilds'
        $script:BuildTabContentContent | Should -Match 'if \(\$SkipIdlePrebuild -or -not \$PrimaryTabs -or -not \$PrimaryTabs\.Dispatcher -or -not \(Test-GuiIdleTabPrebuildAllowed\)\)'
        $script:BuildTabContentContent | Should -Not -Match 'foreach \(\$tabItem in \$PrimaryTabs\.Items\)[\s\S]{0,500}Build-TabContent -PrimaryTab \$capturedTag -BackgroundBuild'
        $script:GuiContent | Should -Match '\[System\.Windows\.Threading\.DispatcherPriority\]::ApplicationIdle'
    }

    It 'keeps primary tab ownership maps in script state for deferred row hydration' {
        $script:CategoryInitializationContent | Should -Match '\$Script:PrimaryCategories = \[ordered\]@\{'
        $script:CategoryInitializationContent | Should -Match '\$PrimaryCategories = \$Script:PrimaryCategories'
        $script:CategoryInitializationContent | Should -Match '\$Script:CategoryToPrimary = @\{\}'
        $script:CategoryPathMappingContent | Should -Match '\$CategoryToPrimary = \$Script:CategoryToPrimary'
        $script:AvailabilityStateOverridesContent | Should -Match '\$categoryMap = if \(\$Script:CategoryToPrimary -is \[hashtable\]\)'
        $script:AvailabilityStateOverridesContent | Should -Match '\$categoryMap\.ContainsKey\(\$categoryName\)'
        $script:GameModeContent | Should -Match '\$categoryMap = if \(\$Script:CategoryToPrimary -is \[hashtable\]\)'
    }

    It 'keeps the splash until startup tab content is hydrated' {
        $script:GuiContent | Should -Match '# Signal GuiReady NOW'
        $script:GuiContent | Should -Match 'Set-BootstrapLoadingSplashStep'' -CommandType Function'
        $script:GuiContent | Should -Match "-StepId 'finalize' -Status 'completed'"
        $script:GuiContent | Should -Match '\$Splash\.GuiReady = \$true'
        $script:GuiContent | Should -Match '\$null = Invoke-GuiDispatcherAction -Dispatcher \$PrimaryTabs\.Dispatcher -PriorityUsage ''Immediate'' -Action \{'
        $script:GuiContent | Should -Match '\$PrimaryTabs\.Dispatcher\.BeginInvoke\(\s*\[System\.Action\]\$initialTabBuildAction,\s*\[System\.Windows\.Threading\.DispatcherPriority\]::Background'
        $script:GuiContent | Should -Match 'if \(-not \$startupRestoreSessionPending\)'
        $script:BuildPrimaryTabsContent | Should -Not -Match '\$Global:LoadingSplash\.GuiReady = \$true'
        $script:BuildPrimaryTabsContent | Should -Not -Match '\$Script:MainForm\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:BuildTabContentContent | Should -Not -Match '\$MainForm\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:BuildTabContentContent | Should -Not -Match '\$MainForm\.ShowInTaskbar = \$true'
        $script:BuildTabContentContent | Should -Not -Match '\$MainForm\.Opacity = 1'
        $script:BuildTabContentContent | Should -Match 'WPF requires the window to stay hidden until ShowDialog\(\)'
        $script:BuildTabContentContent | Should -Match 'Test-GuiStartupSplashAbortRequested -Splash \$Splash'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent aborted before GuiReady because startup splash was closed'
        $script:GuiContent | Should -Match '\$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Start-GuiPerfScope'''
        $script:GuiContent | Should -Match '\$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Stop-GuiPerfScope'''
    }

    It 'releases the splash when cached startup tab content short-circuits the build' {
        $script:BuildTabContentContent | Should -Match '(?s)if \(Restore-CachedTabContent -PrimaryTab \$PrimaryTab\)\s*\{\s*Invoke-GuiStartupReadySignal'
    }

    It 'releases the splash when restored top navigation modes are already active' {
        $script:GuiContent | Should -Match 'if \(\$Script:AppsModeActive -or \$Script:DeploymentMediaModeActive\)'
        $script:GuiContent | Should -Match 'Test-GuiStartupSplashLive -Splash \$startupSplash'
        $script:GuiContent | Should -Match "Get-Command -Name 'Invoke-GuiStartupReadySignal'"
        $script:GuiContent | Should -Match '& \$startupReadySignalScript'
    }

    It 'initializes perf tracing before the dialog helpers load' {
        $script:DialogHelpersContent | Should -Match '\. \(Join-Path \$Script:DialogHelpersRoot ''PerfTrace\.ps1''\)'
        $script:DialogHelpersContent | Should -Match 'Initialize-GuiPerfTrace'
    }

    It 'loads the durable user preference store before settings-dependent GUI modules' {
        $script:GuiContent | Should -Match '(?s)\. \(Join-Path \$Script:GuiExtractedRoot ''UxPolicy\.ps1''\)\s*\. \(Join-Path \$Script:GuiExtractedRoot ''UserPreferences\.ps1''\)\s*\. \(Join-Path \$Script:GuiExtractedRoot ''UIDensity\.ps1''\)\s*\. \(Join-Path \$Script:GuiExtractedRoot ''SessionState\.ps1''\)'
    }

    It 'threads the focused rebuild flag through the current-tab refresh path' {
        $script:GuiContent | Should -Match 'function Update-CurrentTabContent'
        $script:GuiContent | Should -Match '& \$buildTabContentScript -PrimaryTab \$targetTab -SkipIdlePrebuild:\$SkipIdlePrebuild'
        $script:GuiContent | Should -Match '\$skipIdlePrebuild = \[bool\]\$Script:SkipIdlePrebuildOnNextPrimaryTabSelection'
        $script:GuiContent | Should -Match '& \$updateCurrentTabContentScript -SkipIdlePrebuild:\$skipIdlePrebuild'
    }

    It 'hydrates tab rows progressively without blocking the dispatcher for a full tab' {
        $script:BuildTabContentContent | Should -Match 'function Start-ProgressiveTabSectionsHydration'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent\.ProgressiveHydration'
        $script:BuildTabContentContent | Should -Match '\$chunkWatch = \[System\.Diagnostics\.Stopwatch\]::StartNew\(\)'
        $script:BuildTabContentContent | Should -Match '\$rowsAdded -ge 1 -or \$chunkWatch\.ElapsedMilliseconds -ge 35'
        $script:BuildTabContentContent | Should -Match '\[System\.Windows\.Threading\.DispatcherPriority\]::Loaded'
        $script:BuildTabContentContent | Should -Match 'Action = \$null'
        $script:BuildTabContentContent | Should -Match '\$state\.Action = \[System\.Action\]\$chunkAction'
        $script:BuildTabContentContent | Should -Match '\$dispatcher\.BeginInvoke\(\$state\.Action, \$priority\)'
        $script:BuildTabContentContent | Should -Match '(?s)if \(\$BackgroundBuild\)\s*\{\s*\$null = \$dispatcher\.BeginInvoke\(\$state\.Action, \$priority\)\s*\}\s*else\s*\{\s*\$state\.Action\.Invoke\(\)\s*\}'
        $script:BuildTabContentContent | Should -Match 'Complete-TabContentBuild -BuildContext \$BuildContext'
        $script:BuildTabContentContent | Should -Match 'Show-TabContentBuildPanel -BuildContext \$buildContext'
        $script:BuildTabContentContent | Should -Match 'Start-GuiIdleTabPrebuilds -PrimaryTab \$primaryTab -SkipIdlePrebuild:\$SkipIdlePrebuild'
        $script:BuildTabContentContent | Should -Match 'Add-TabSectionsToPanel -BuildContext \$buildContext -CooperativeYield -YieldEveryNRows 2'
        $script:BuildTabContentContent | Should -Match 'Complete-TabContentBuild -BuildContext \$buildContext -AllTabIndexes \$allTabIndexes -BuildGeneration \$buildGeneration -BuildToken \$buildToken -SkipIdlePrebuild:\$SkipIdlePrebuild -AlreadyDisplayed'
        $script:BuildTabContentContent | Should -Match '(?s)if \(\$BackgroundBuild\)\s*\{\s*Start-ProgressiveTabSectionsHydration -BuildContext \$buildContext -AllTabIndexes \$allTabIndexes'
        $script:BuildTabContentContent | Should -Match 'Test-TabContentBuildTokenCurrent -PrimaryTab \$primaryTab -BuildToken \$BuildToken'
        $script:BuildTabContentContent | Should -Match 'function Test-TabContentHydrationCurrent'
        $script:BuildTabContentContent | Should -Match 'Test-TabContentHydrationCurrent -PrimaryTab \$primaryTab -BuildGeneration \$BuildGeneration -BuildToken \$BuildToken'
        $script:BuildTabContentContent | Should -Match '\$hydrated = Add-TabSectionsToPanel -BuildContext \$buildContext'
        $script:BuildTabContentContent | Should -Match 'if \(-not \$hydrated\)'
        $script:BuildTabContentContent | Should -Match '\$Script:TabContentBuildTokens\[\$PrimaryTab\] = \$buildToken'
        $script:BuildTabContentContent | Should -Match 'function Resolve-TabContentBuildPrimaryTab'
        $script:BuildTabContentContent | Should -Match '\$PrimaryTab = Resolve-TabContentBuildPrimaryTab -PrimaryTab \$PrimaryTab'
        $script:BuildTabContentContent | Should -Match 'Build-TabContent requires a non-empty primary tab'
        $script:BuildTabContentContent | Should -Match '\$visiblePrimaryMatches = \(\[string\]\$Script:VisibleTabContentPrimaryTab -eq \$PrimaryTab\)'
        $script:BuildTabContentContent | Should -Match '\$PrimaryTab -eq ''Updates'''
        $script:BuildTabContentContent | Should -Match '\[bool\]\$Script:GamingModeActive -or \[bool\]\$Script:UpdatesModeActive'
        $script:BuildTabContentContent | Should -Match 'if \(\[string\]::IsNullOrWhiteSpace\(\[string\]\$PrimaryTab\) -or \[string\]::IsNullOrWhiteSpace\(\[string\]\$BuildToken\)\)'
        $script:BuildTabContentContent | Should -Match '\[int\]\$YieldEveryNRows = 3'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent\.AddRow\.DispatcherYield'
        $script:BuildTabContentContent | Should -Match '\$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Start-GuiPerfScope'''
        $script:BuildTabContentContent | Should -Match '\$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Stop-GuiPerfScope'''
        $script:BuildTabContentContent | Should -Match '\$chunkAction = \$mod\.NewBoundScriptBlock\(\$chunkAction\)'
        $script:BuildTabContentContent | Should -Not -Match '(?m)^\s*Stop-GuiPerfScope -Scope'
    }

    It 'invokes page reset through a captured script-scope handler for WPF events' {
        $script:ActionHandlersContent | Should -Match '\$Script:InvokePageResetToDefaultsScript = \{'
        $script:ActionHandlersContent | Should -Match '& \$Script:InvokePageResetToDefaultsScript -Category \$Category'
        $script:PresetUiContent | Should -Match '\$invokePageResetToDefaultsCapture = if \(\$Script:InvokePageResetToDefaultsScript\)'
        $script:PresetUiContent | Should -Match '& \$invokePageResetToDefaultsCapture -Category \$pageCategory'
        $script:PresetUiContent | Should -Not -Match 'Invoke-PageResetToDefaults -Category \$pageCategory'
    }

    It 'keeps the Safe UX Quick Start preset scoped to Initial Setup' {
        $script:PresetUiContent | Should -Match 'function Test-ShouldShowQuickStartPresetButton'
        $script:PresetUiContent | Should -Match 'return \[string\]::Equals\(\$normalizedPrimaryTab, ''Initial Setup'''
        $script:PresetUiContent | Should -Match 'Get-TabPresetButtonDefinitions -IsSafeUx:\(Test-IsSafeModeUX\) -PrimaryTab \(\[string\]\$BuildContext\.PrimaryTab\)'
        $script:PresetUiContent | Should -Match 'if \(Test-ShouldShowQuickStartPresetButton -PrimaryTab \$PrimaryTab\)'
    }

    It 'uses focused rebuilds for theme and shared mode transitions' {
        $script:GuiContent | Should -Match 'Build-TabContent -PrimaryTab \$Script:CurrentPrimaryTab -SkipIdlePrebuild'
        $script:StateTransitionContent | Should -Match '& \$Script:UpdateCurrentTabContentScript -SkipIdlePrebuild'
    }

    It 'skips duplicate content rebuild during initial startup theme application' {
        $script:GuiContent | Should -Match 'Apply-BaselineThemePreference -Preference \$initialThemePreference -SkipContentRebuild'
        $script:GuiContent | Should -Match 'param \(\s*\[hashtable\]\$Theme,\s*\[switch\]\$SkipContentRebuild\s*\)'
        $script:GuiContent | Should -Match 'if \(-not \$SkipContentRebuild\)\s*\{\s*# Rebuild content for current tab to pick up new theme colors\.'
    }

    It 'hydrates the restored startup tab before the GUI is revealed' {
        $script:SessionStateContent | Should -Match '\$refreshCurrentTabContentScript = \$\{function:Update-CurrentTabContent\}'
        $script:SessionStateContent | Should -Match '\$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Start-GuiPerfScope'''
        $script:SessionStateContent | Should -Match '\$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name ''Stop-GuiPerfScope'''
        $script:SessionStateContent | Should -Match '\$__perf = if \(\$startGuiPerfScopeScript\) \{ & \$startGuiPerfScopeScript -Name ''RestoreGuiSessionState\.TabHydrate'' \} else \{ \$null \}'
        $script:SessionStateContent | Should -Match '& \$refreshCurrentTabContentScript -SkipIdlePrebuild'
        $script:SessionStateContent | Should -Match '\$Script:StartupRestoreSessionPending = \$false'
        $script:SessionStateContent | Should -Not -Match '\$Script:MainForm\.Dispatcher\.BeginInvoke\(\s*\[System\.Action\]\$refreshCurrentTabContentAction'
    }

    It 'keeps restored inline search results as the active refresh target' {
        $script:GuiContent | Should -Match '\$activeSearchQuery = if \(\$null -eq \$Script:SearchText\)'
        $script:GuiContent | Should -Match '\$activeSearchQuery = \$activeSearchQuery\.Trim\(\)'
        $script:GuiContent | Should -Match 'if \(-not \[string\]::IsNullOrWhiteSpace\(\$activeSearchQuery\)\)'
        $script:GuiContent | Should -Match '\$targetTab = \$Script:SearchResultsTabTag'
    }

    It 'clears inline search results back to the selected tweak tab immediately' {
        $script:GuiContent | Should -Match '\$Script:SearchText\s*=\s*'''''
        $script:GuiContent | Should -Match '\$Script:SearchRefreshTimer\.Stop\(\)'
        $script:GuiContent | Should -Match 'Update-SearchResultsTabState'
        $script:GuiContent | Should -Match 'Update-CurrentTabContent -SkipIdlePrebuild'
    }

    It 'loads the AppData startup session snapshot before primary tab hydration' {
        $script:GuiContent | Should -Match '\$Script:StartupSessionSnapshot = \$null'
        $script:GuiContent | Should -Match 'GUICommon\\Read-GuiSessionStateDocument -AppName ''Baseline'' -ExpectedSchema ''Baseline\.GuiSettings'''
        $script:GuiContent | Should -Match '\$Script:UIDensity = if \(Get-Command -Name ''Normalize-BaselineUiDensity'''
        $script:GuiContent | Should -Match '\$Script:StartupHydratePrimaryTab = \$desiredTab'
        $script:GuiContent | Should -Match '\$Script:StartupHydratePrimaryTab = \$desiredLast'
        $script:GuiContent | Should -Match '\$startupHydratePrimaryTab = if \(-not \[string\]::IsNullOrWhiteSpace\(\[string\]\$Script:StartupHydratePrimaryTab\)\)'
        $script:GuiContent | Should -Match '\$startupRestoreSessionPending = \[bool\]\$Script:StartupRestoreSessionPending'
    }

    It 'restores the startup session before the splash can close' {
        $script:GuiContent | Should -Match '\$restoredSessionAction = \{'
        $script:GuiContent | Should -Not -Match 'Regions\.GUI\.RestoreLastSessionAsync'
        $script:GuiContent | Should -Not -Match '\$Form\.Dispatcher\.BeginInvoke\(\s*\[System\.Action\]\$restoredSessionAction'
        $script:GuiContent | Should -Match '\$restoredSessionStatusText = Get-UxLocalizedString -Key ''GuiLogSessionRestoredPreviousState'''
        $script:GuiContent | Should -Match '\$restoreGuiSessionStateScript = Get-GuiFunctionCapture -Name ''Restore-GuiSessionState'''
        $script:GuiContent | Should -Match '\$setGuiStatusTextScript = Get-GuiFunctionCapture -Name ''Set-GuiStatusText'''
        $script:GuiContent | Should -Match '& \$restoreGuiSessionStateScript -Snapshot \$Script:StartupSessionSnapshot -PreserveDurablePreferences'
        $script:SessionStateContent | Should -Match '\[object\]\s*\$Snapshot = \$null'
        $script:SessionStateContent | Should -Match '\[switch\]\s*\$PreserveDurablePreferences'
    }

    It 'routes Build-TabContent cleanup failures through Write-SwallowedException' {
        $script:BuildTabContentContent | Should -Match "BuildTabContent\.ProgressiveHydration"
        $script:BuildTabContentContent | Should -Match 'Clear-TabContentBuildToken -PrimaryTab \$primaryTab -BuildToken \$BuildToken'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''BuildTabContent\.Update-PrimaryTabHeaders'''
    }

    It 'captures the startup orchestrator before deferring it to the dispatcher' {
        $script:GuiContent | Should -Match '\$invokeBaselineStartupOrchestratorScript = Get-GuiFunctionCapture -Name ''Invoke-BaselineStartupOrchestrator'''
        $script:GuiContent | Should -Match '& \$invokeBaselineStartupOrchestratorScript -TweakManifest'
    }

    It 'routes dispatcher-yield failures in state transitions through Write-SwallowedException' {
        $script:StateTransitionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StateTransitions\.Invoke-GuiStateTransition\.DispatcherYield'''
	}

	It 'routes nav-mode chrome and theme status lookups through Write-SwallowedException' {
		$script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Set-GuiNavModeCheckedState\.UpdateGuiNavModeChrome'''
		$script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.UpdateAppsPackageManagerBanner'''
		$script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Set-GuiAppsMode\.UpdateAppsPackageManagerBanner'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Set-AppsActionControlsEnabled\.ControlEnabled'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplyTheme\.Set-GUITheme\.UpdateGuiNavModeChrome'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplyTheme\.Set-GUITheme\.ReadStatusText'''
    }

    It 'routes apps cache refresh and view cleanup failures through Write-SwallowedException' {
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Get-ApplicationCacheSnapshot\.CacheSnapshot'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Get-BaselineApplicationsCatalog\.TestWinGetAvailable'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Get-BaselineApplicationsCatalog\.TestChocolateyAvailable'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.SetButtonChrome\.Primary'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.SetButtonChrome\.Update'''
        $script:GuiContent | Should -Match '\$showGuiRuntimeFailureCommand = Get-GuiFunctionCapture -Name ''Invoke-GuiRuntimeFailureReport'''
        $script:GuiContent | Should -Match 'if \(-not \$showGuiRuntimeFailureCommand\) \{ throw ''Invoke-GuiRuntimeFailureReport not found\.'' \}'
        $script:GuiContent | Should -Match '& \$showGuiRuntimeFailureCommand -Context ''AppPrimaryButton'''
        $script:GuiContent | Should -Match '& \$showGuiRuntimeFailureCommand -Context ''AppUpdateButton'''
        $script:GuiContent | Should -Not -Match '\$Script:ShowGuiRuntimeFailureScript -Context ''AppPrimaryButton'''
        $script:GuiContent | Should -Not -Match '\$Script:ShowGuiRuntimeFailureScript -Context ''AppUpdateButton'''
        $script:GuiContent | Should -Match '\$getUxBilingualLocalizedStringCapture = Get-GuiFunctionCapture -Name ''Get-UxBilingualLocalizedString'''
        $script:GuiContent | Should -Match '& \$getUxBilingualLocalizedStringCapture -Key ''GuiLogExecutionAppQueueStateFailed'''
        $script:GuiContent | Should -Match '\$startAppsModuleBatchActionAsyncCommand = Get-GuiRuntimeCommand -Name ''Start-AppsModuleBatchActionAsync'''
        $script:GuiContent | Should -Match '\$clearAppsQueuedActionsCommand = Get-GuiRuntimeCommand -Name ''Clear-AppsQueuedActions'''
        $script:GuiContent | Should -Match '& \$startAppsModuleBatchActionAsyncCommand -Action \$action -SelectedApps \$apps'
        $script:GuiContent | Should -Match '& \$clearAppsQueuedActionsCommand'
        $script:GuiContent | Should -Not -Match '(?m)^\s*Start-AppsModuleBatchActionAsync -Action \$action -SelectedApps \$apps'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Start-AppsModuleQueuedActionAsync\.TimerStop'''
        $script:GuiContent | Should -Not -Match 'AppsModule\.Start-AppsModuleQueuedActionAsync\.TimerDispose'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Clear-AppSelectionState\.SelectionControlIsCheckedFalse'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.UpdateAppsCategoryTabCounts'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.AddCardHoverEffects'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Build-AppsViewCards\.DispatcherYield'''
        $script:GuiContent | Should -Match '\$installedCacheSnapshot = Get-ApplicationCacheSnapshot -CacheState \$Script:InstalledAppsCache'
        $script:GuiContent | Should -Match '\$installedWingetCache = \$installedCacheSnapshot\.WinGet'
        $script:GuiContent | Should -Match '\$installedChocolateyCache = \$installedCacheSnapshot\.Chocolatey'
        $script:GuiContent | Should -Match '\$wingetUpdateCache = \$installedCacheSnapshot\.WinGetUpdates'
        $script:GuiContent | Should -Match '\$chocolateyUpdateCache = \$installedCacheSnapshot\.ChocolateyUpdates'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Start-AppsCacheRefresh\.WriteEntryTrace'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Start-AppsCacheRefresh\.LogWarning'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Start-AppsCacheRefresh\.DisposePowerShell'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AppsModule\.Start-AppsCacheRefresh\.DisposeRunspace'''
    }

    It 'uses contrast-aware chrome for queued app badges' {
        $script:GuiContent | Should -Match 'function Get-GuiAppsQueuedBadgeColorSet'
        $script:GuiContent | Should -Match 'Get-GuiReadableForegroundColor -BackgroundColor \$backgroundColor'
        $script:GuiContent | Should -Match 'Set-GuiAppsQueuedBadgeChrome -Badge \$queuedBadge -BadgeText \$queuedBadgeText'
        $script:GuiContent | Should -Not -Match 'ButtonPrimaryFg'
    }

    It 'restores app scan busy state when refresh setup or worker failure exits early' {
        $script:GuiContent | Should -Match "LogInfo 'Scanning installed apps\.\.\.'"
        $script:GuiContent | Should -Match '\$appsLogInfoCommand = Get-Command ''LogInfo'' -CommandType Function, Alias'
        $script:GuiContent | Should -Match '\$appsFormatBaselineErrorForLogCommand = Get-Command ''Format-BaselineErrorForLog'''
        $script:GuiContent | Should -Match '\$syncHash\.Error[\s\S]*?\$appsSetActionControlsEnabledCommand -Enabled \$true[\s\S]*?return'
        $script:GuiContent | Should -Match 'catch[\s\S]*?\$Script:AppsCacheRefreshInProgress = \$false[\s\S]*?Set-AppsActionControlsEnabled -Enabled \$true[\s\S]*?throw'
        $script:GuiContent | Should -Match '& \$appsLogInfoCommand \(\[string\]\$syncHash\.PhaseComplete\)'
        $script:GuiContent | Should -Match '& \$appsLogErrorCommand \(& \$appsFormatBaselineErrorForLogCommand -ErrorObject \$_ -Prefix \$cacheRefreshErrorPrefix\)'
    }

    It 'routes ContentManagement scroll failures through Write-SwallowedException' {
        $script:ContentManagementContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ContentManagement\.ScrollToVerticalOffset'''
    }

    It 'routes force-close cleanup failures through Write-SwallowedException' {
        $script:StyledControlsSetupContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyledControlsSetup\.ForceCloseExecutionFn\.TimerStop'''
        $script:StyledControlsSetupContent | Should -Not -Match 'StyledControlsSetup\.ForceCloseExecutionFn\.TimerDispose'
        $script:StyledControlsSetupContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyledControlsSetup\.ForceCloseExecutionFn\.StopResponsivenessWatchdog'''
        $script:StyledControlsSetupContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyledControlsSetup\.ForceCloseExecutionFn\.CloseMainWindow'''
        $script:StyledControlsSetupContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyledControlsSetup\.ForceCloseExecutionFn\.ShutdownApplication'''
        $script:StyledControlsSetupContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyledControlsSetup\.ForceCloseExecutionFn\.FallbackCloseMainWindow'''
    }

    It 'routes GUI region search refresh and splash-close cleanup through logged paths' {
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.SearchRefreshTimer\.Stop'''
        $script:GuiContent | Should -Match 'function Test-GuiStartupSplashLive'
        $script:GuiContent | Should -Match 'function Test-GuiStartupSplashAbortRequested'
        $script:GuiContent | Should -Match 'function Stop-GuiStartupSplashAbortProcess'
        $script:GuiContent | Should -Match 'function Start-GuiStartupSplashAbortWatchdog'
        $script:GuiContent | Should -Match 'if \(Test-GuiStartupSplashAbortRequested -Splash \$Splash\) \{ return \$false \}'
        $script:GuiContent | Should -Match 'if \(-not \[bool\]\$Splash\.IsAlive\) \{ return \$false \}'
        $script:GuiContent | Should -Match 'if \(\$Splash\.ContainsKey\(''WasRendered''\) -and \[bool\]\$Splash\.WasRendered\) \{ return \$true \}'
        $script:GuiContent | Should -Match 'if \(\$Splash\.ContainsKey\(''Dispatcher''\) -and \$null -ne \$Splash\.Dispatcher\) \{ return \$true \}'
        $script:GuiContent | Should -Match '\$testGuiStartupSplashLiveBlock = \(Get-Item function:Test-GuiStartupSplashLive -ErrorAction Stop\)\.ScriptBlock'
        $script:GuiContent | Should -Match '\$testGuiStartupSplashAbortBlock = \(Get-Item function:Test-GuiStartupSplashAbortRequested -ErrorAction Stop\)\.ScriptBlock'
        $script:GuiContent | Should -Match '\$hasLiveStartupSplash = & \$testGuiStartupSplashLiveBlock -Splash \$startupSplashHandle'
        $script:GuiContent | Should -Match 'Start-GuiStartupSplashAbortWatchdog -Splash \$startupSplashHandle'
        $script:GuiContent | Should -Match '\$startupSplashMaximizeMirrorTimer = \[System\.Windows\.Threading\.DispatcherTimer\]::new\(\[System\.Windows\.Threading\.DispatcherPriority\]::Send, \$Form\.Dispatcher\)'
        $script:GuiContent | Should -Match '\$startupSplashMaximizeMirrorTimer\.Interval = \[TimeSpan\]::FromMilliseconds\(50\)'
        $script:GuiContent | Should -Match '\$startupSplashHandle\[''WindowMaximized''\]'
        $script:GuiContent | Should -Match '\$startupSplashHandle\[''ProgrammaticClose''\]'
        $script:GuiContent | Should -Match 'Set-GuiMainWindowWorkAreaMaximized -Window \$Form -Maximized \$true -PreserveRestoreBounds'
        $script:GuiContent | Should -Match 'Set-GuiMainWindowWorkAreaMaximized -Window \$Form -Maximized \$false'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.StartupSplashMaximizeMirror\.Tick'''
        $script:GuiContent | Should -Match '\$applyStartupSplashMainWindowStateAction = \[System\.Action\[bool\]\]\(\{'
        $script:GuiContent | Should -Match 'SetVariable\(''applyStartupSplashMainWindowStateAction'', \$applyStartupSplashMainWindowStateAction\)'
        $script:GuiContent | Should -Match '\$splashWindowMaximizedAtReveal = \[bool\]\$splash\[''WindowMaximized''\]'
        $script:GuiContent | Should -Match '\$applyStartupSplashMainWindowStateAction\.Invoke\(\$true\)'
        $script:GuiContent | Should -Not -Match '\$applyMainWindowWorkAreaMaximize = \{'
        $script:GuiContent | Should -Not -Match '& \$applyMainWindowWorkAreaMaximize -Window \$mainWindow'
        $script:GuiContent | Should -Match 'SplashClose runspace: WindowMaximized at reveal = \{0\}'
        $script:GuiContent | Should -Match 'SplashClose runspace: mainWindow maximize handoff failed'
        $script:GuiContent | Should -Match '\$Form\.ShowInTaskbar = \$true'
        $script:GuiContent | Should -Match '\$Form\.Opacity = 1'
        $script:GuiContent | Should -Match '\$Form\.WindowState = \[System\.Windows\.WindowState\]::Normal'
        $script:GuiContent | Should -Match '\$startupSplashHandle\.ContainsKey\(''WindowMaximized''\)'
        $script:GuiContent | Should -Match '\$startupSplashMaximized = \[bool\]\$startupSplashHandle\[''WindowMaximized''\]'
        $script:GuiContent | Should -Match 'Set-GuiMainWindowWorkAreaMaximized -Window \$Form -Maximized \$true -PreserveRestoreBounds'
        $script:GuiContent | Should -Match '\$Script:MainWindowPendingWorkAreaMaximize = \$true'
        $script:GuiContent | Should -Not -Match '\$Form\.ShowInTaskbar = \$false'
        $script:GuiContent | Should -Not -Match '\$Form\.Opacity = 0'
        $script:GuiContent | Should -Match 'if \(& \$testGuiStartupSplashLiveBlock -Splash \$splashHandle\)'
        $script:GuiContent | Should -Match 'Show-TweakGUI aborted before ShowDialog because startup splash was closed'
        $script:GuiContent | Should -Match 'StartupSplashAbortWatchdog: startup splash closed before GuiReady; aborting process'
        $script:GuiContent | Should -Match 'SplashClose runspace: startup splash closed before GuiReady; aborting process'
        $script:GuiContent | Should -Match '\[System\.Diagnostics\.Process\]::GetCurrentProcess\(\)\.Kill\(\)'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.StartupVisibility\.Apply'''
        $script:GuiContent | Should -Match '\$Form\.ShowActivated = -not \[bool\]\$hasLiveStartupSplash'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.StartupSplashAbortWatchdog\.RunspaceDispose'''
        $script:GuiContent | Should -Match '\$setMainWindowPresentation = \{'
        $script:GuiContent | Should -Not -Match '\$mainWindow\.WindowState = \[System\.Windows\.WindowState\]::Maximized'
        $script:GuiContent | Should -Match '\$mainWindow\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:GuiContent | Should -Match '\$mainWindow\.WindowState = \[System\.Windows\.WindowState\]::Normal'
        $script:GuiContent | Should -Match '\$splashWindowActiveAtReveal = \[bool\]\$splash\[''WindowActive''\]'
        $script:GuiContent | Should -Match 'SplashClose runspace: WindowActive at reveal = \{0\}'
        $script:GuiContent | Should -Match '\$mainWindow\.ShowActivated = \[bool\]\$splashWindowActiveAtReveal'
        $script:GuiContent | Should -Not -Match '\$mainWindowInterop\.EnsureHandle\(\)'
        $script:GuiContent | Should -Not -Match '\[WinAPI\.ForegroundWindow\]::ShowWindowAsync'
        $script:GuiContent | Should -Not -Match '\[WinAPI\.ForegroundWindow\]::SetWindowPos'
        $script:GuiContent | Should -Not -Match '\[WinAPI\.ForegroundWindow\]::SetForegroundWindow'
        $script:GuiContent | Should -Not -Match '\$mainWindow\.Topmost = \$true'
        $script:GuiContent | Should -Not -Match 'Start-Sleep -Milliseconds 900'
        $script:GuiContent | Should -Not -Match '\$mainWindow\.Topmost = \$false'
        $script:GuiContent | Should -Not -Match '\$null = \$mainWindow\.Activate\(\)'
        $script:GuiContent | Should -Not -Match '\$null = \$mainWindow\.Focus\(\)'
        $script:GuiContent | Should -Match 'SplashClose runspace: mainWindow presentation transition failed'
        $script:GuiContent | Should -Match 'SplashClose runspace: mainWindow left at inherited activation state'
        $script:GuiContent | Should -Not -Match 'SplashClose runspace: mainWindow activated after splash close'
        $script:GuiContent | Should -Match 'SplashClose runspace: dispatcher InvokeShutdown failed'
        $script:GuiContent | Should -Match 'SplashClose runspace: PowerShell\.EndInvoke failed'
        $script:GuiContent | Should -Match 'SplashClose runspace: Runspace\.Dispose failed'
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.SplashClose\.LogWarning\.Orchestration'''
        $script:GuiContent | Should -Match '\$stream\.Write\(\$bytes, 0, \$bytes\.Length\)'
        $script:GuiContent | Should -Match 'finally \{ \$stream\.Dispose\(\) \}'
    }

    It 'routes GUI module-base resolution fallbacks through Write-SwallowedException' {
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.ResolveModuleBase\.ModuleBase'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.ResolveModuleBase\.PSCommandPath'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.ResolveModuleBase\.MyInvocationPath'''
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.ResolveModuleBase\.PSScriptRoot'''
    }

    It 'routes GUI DPI initialization failures through Write-SwallowedException' {
        $script:GuiContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Regions\.GUI\.ShowTweakGUI\.InitializeGuiDpiAwareness'''
    }

    It 'preserves primitive WPF setter values when unwrapping PSObjects' {
        $script:GuiContent | Should -Match '\$unwrappedValue = \$resolvedValue\.psobject\.BaseObject'
        $script:GuiContent | Should -Match 'if \(\$null -ne \$unwrappedValue\)'
        $script:GuiContent | Should -Not -Match '\$resolvedValue = \$resolvedValue\.BaseObject'
    }

    It 'uses focused rebuilds for game mode refreshes' {
        $script:GameModeContent | Should -Match '& \$Script:UpdateCurrentTabContentScript -SkipIdlePrebuild'
        $script:GameModeContent | Should -Match '& \$updateCurrentTabContentScript -SkipIdlePrebuild'
        $script:GameModeContent | Should -Match '\$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = \$true'
    }

    It 'does not auto-refresh the apps cache when entering Apps mode' {
        $script:GuiContent | Should -Match 'function Set-GuiAppsMode'
        $script:GuiContent | Should -Not -Match 'function Set-GuiAppsMode[\s\S]*Start-AppsCacheRefresh'
    }

    It 'lazy-loads Software and Apps categories from the selected category only' {
        $script:GuiContent | Should -Match 'function Get-AppsDefaultCatalogCategory'
        $script:GuiContent | Should -Match "return 'Browsers'"
        $script:GuiContent | Should -Not -Match 'AppsProgressContainer'
        $script:GuiContent | Should -Match 'function New-GuiExecutionProgressBarTemplate'
        $script:GuiContent | Should -Match '\$progressBar = New-Object System\.Windows\.Controls\.ProgressBar'
        $script:GuiContent | Should -Match '\$progressBar\.Template = New-GuiExecutionProgressBarTemplate'
        $script:GuiContent | Should -Not -Match 'New-SharedProgressBarHost[\s\S]{0,900}WindowsFormsHost'
        $script:GuiContent | Should -Match 'function Get-AppsCatalogFilesForCategory'
        $script:GuiContent | Should -Match '\$catalogFiles = @\(Get-AppsCatalogFilesForCategory -Category \$effectiveCategory\)'
        $script:GuiContent | Should -Match '\$Script:BaselineApplicationsCatalogByCategory'
        $script:GuiContent | Should -Match '\$Script:AppsCategoryFilter = Resolve-AppsCatalogCategory -Category \$Script:AppsCategoryFilter'
        $script:ApplicationsViewContent | Should -Match 'Get-AppsCatalogCategoryNames'
        $script:ApplicationsViewContent | Should -Not -Match 'Get-AppCategoryFilterValues[\s\S]{0,500}Get-BaselineApplicationsCatalog'
        $script:SessionStateContent | Should -Match 'AppsCategoryFilter = if \(\$Script:AppsCategoryFilter\) \{ \[string\]\$Script:AppsCategoryFilter \} else \{ ''Browsers'' \}'
        $script:SessionStateContent | Should -Match 'NavigationMode = \$currentNavigationMode'
        $script:SessionStateContent | Should -Match '\$desiredNavigationMode = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''NavigationMode''\)'
        $script:SessionStateContent | Should -Match '\$desiredSearchText = if \(\$desiredNavigationMode -eq ''Apps''\)'
        $script:SessionStateContent | Should -Match 'Set-GuiAppsMode -Enable:\$true'
        $script:SessionStateContent | Should -Match 'Set-GuiUpdatesMode -Enable:\$true'
    }

    It 'shows Apps category counts for every category tab without changing the active catalog' {
        $script:GuiContent | Should -Match '\[string\]\$SearchQuery = \$null,\s*\[string\]\$Category = \$null'
        $script:GuiContent | Should -Match "Get-Variable -Name 'BaselineApplicationsCatalog' -Scope Script"
        $script:GuiContent | Should -Match 'Get-BaselineApplicationsCatalog -Category \$Category -SkipPackageManagerAvailabilityRefresh:\$SkipPackageManagerAvailabilityRefresh'
        $script:ApplicationsViewContent | Should -Match '\$categoryCounts = \[System\.Collections\.Generic\.Dictionary\[string, int\]\]::new'
        $script:ApplicationsViewContent | Should -Match 'Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery \$activeSearchQuery -Category \$tag -SkipPackageManagerAvailabilityRefresh'
        $script:ApplicationsViewContent | Should -Match '\$headerText = ''\{0\} \(\{1\}\)'' -f \$displayName, \$categoryCounts\[\$tag\]'
        $script:ApplicationsViewContent | Should -Not -Match '\$headerText = if \(\$tag -eq \$currentCategory\)'
        $script:GuiContent | Should -Match '(?s)if \(\$Script:AppsWrapPanel\.Children\.Count -gt 0 -and \$Script:AppsViewBuildSignature -eq \$renderSignature\)\s*\{\s*if \(Get-Command -Name ''Update-AppsCategoryTabCounts'''
    }

    It 'keeps the visible window title version-free and leaves the version for Help content' {
        $script:StyleContent | Should -Not -Match '\$headerTitle = "\{0\} \{1\}" -f \$windowTitle, \$Script:GuiDisplayVersion'
        $script:GuiContent | Should -Not -Match '\$headerTitle = "\{0\} \{1\}" -f \$headerTitle, \$Script:GuiDisplayVersion'
    }

    It 'routes the dedicated system scan button directly to the scan command instead of the scan checkbox' {
        $script:PresetUiContent | Should -Match 'function New-SystemScanActionRow'
        $script:PresetUiContent | Should -Match '& \$invokeGuiSystemScanCommand'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$BtnScanInstalledApps -EventName ''Click'''
    }

    It 'keeps full recommendations on Initial Setup and uses compact context elsewhere' {
        $script:PresetUiContent | Should -Match 'function New-GuiRecommendationDisclosurePanel'
        $script:PresetUiContent | Should -Match 'function New-GuiRecommendationPanelContainer'
        $script:PresetUiContent | Should -Match 'function New-GuiRecommendationCompactStrip'
        $script:PresetUiContent | Should -Match 'RecommendedSelectionsCollapsedByScope'
        $script:PresetUiContent | Should -Match 'RecommendationCompactStripRefsByKey'
        $script:PresetUiContent | Should -Match '\[System\.Windows\.Media\.Animation\.DoubleAnimation\]::new\(\)'
        $script:PresetUiContent | Should -Match 'FromMilliseconds\(170\)'
        $script:PresetUiContent | Should -Match 'Register-GuiEventHandler -Source \$headerButton -EventName ''Click'''
        $script:PresetUiContent | Should -Match '\[System\.Windows\.Automation\.AutomationProperties\]::SetName\(\$headerButton'
        $script:PresetUiContent | Should -Match 'if \(\$BuildContext\.PrimaryTab -eq ''Initial Setup''\)'
        $script:PresetUiContent | Should -Match 'New-TabPresetPanel -BuildContext \$BuildContext'
        $script:PresetUiContent | Should -Match 'elseif \(\$BuildContext\.PrimaryTab -ne ''Gaming'' -and \$BuildContext\.PrimaryTab -ne ''Updates''\)'
        $script:PresetUiContent | Should -Match 'New-GuiRecommendationCompactStrip -BuildContext \$BuildContext -ShowChangeButton'
        $script:PresetUiContent | Should -Not -Match 'RecommendedSelections:Gaming'
        $script:PresetUiContent | Should -Not -Match 'GamingRecommendationContextStrip'
        $script:GameModeContent | Should -Match "Scope 'GamingProfiles'"
        $script:GameModeContent | Should -Match 'DefaultCollapsed \$true'
        $script:GameModeContent | Should -Match '\-Compact'
        $script:GameModeContent | Should -Match 'return \$rootStack'
        $script:SessionStateContent | Should -Match 'RecommendationPanelCollapseState = Convert-JsonManifestValue \$currentRecommendationPanelCollapseState'
        $script:SessionStateContent | Should -Match '\$Script:RecommendedSelectionsCollapsedByScope = Copy-GuiRecommendationPanelCollapseState -State \$desiredRecommendationPanelCollapseState'
    }

    It 'keeps shared filters available in Gaming and Updates while preserving collapsed state' {
        $script:GuiContent | Should -Match 'function Set-GuiOptimizeFilterChromeVisible'
        $script:GuiContent | Should -Match 'Set-GuiOptimizeFilterChromeVisible -Visible \$true'
        $script:GuiContent | Should -Match 'Set-GuiOptimizeFilterChromeVisible -Visible:\(-not \$Enable\)'
        $script:GuiContent | Should -Not -Match 'foreach \(\$control in @\(\$Script:BtnFilterToggle, \$Script:FilterOptionsPanel\)\)[\s\S]{0,140}\$control\.Visibility = if \(\$Enable\) \{ \$collapsed \} else \{ \$visible \}'
        $script:SessionStateContent | Should -Match 'RestoreNavigationMode\.ps1'
        $script:SessionStateContent | Should -Match 'if \(\$desiredNavigationMode -ne ''Apps'' -and \$desiredNavigationMode -ne ''DeploymentMedia''\)'
        $script:SessionStateContent | Should -Match 'SetGuiFilterPanelExpandedState.*-Scope ''Optimize'''
    }

    It 'wires the Updates tab runtime workflow outside manifest execution' {
        $script:GuiContent | Should -Match "UpdatesPanel\.ps1"
        $script:PresetUiContent | Should -Match "Get-GuiRuntimeCommand -Name 'New-GuiWindowsUpdateLeadCardsPanel'"
        $script:UpdatesPanelContent | Should -Match 'function script:New-GuiUpdatesRuntimePanel'
        $script:UpdatesPanelContent | Should -Match 'function script:Show-GuiWindowsUpdateRuntimeView'
        $script:UpdatesPanelContent | Should -Match 'GUICommon\\Add-GuiSharedScrollBarResources -Target \$window -Theme \$theme'
        $script:UpdatesPanelContent | Should -Match '\$scrollViewer\.HorizontalScrollBarVisibility = \[System\.Windows\.Controls\.ScrollBarVisibility\]::Auto'
        $script:UpdatesPanelContent | Should -Match '\[void\]\$window\.Show\(\)\s*\r?\n\s*\$startGuiWindowsUpdateOperationScript = \$\{function:Start-GuiWindowsUpdateOperation\}\s*\r?\n\s*& \$startGuiWindowsUpdateOperationScript -Action ''History'''
        $script:UpdatesPanelContent | Should -Match 'function script:New-GuiWindowsUpdateLeadCardsPanel'
        $script:UpdatesPanelContent | Should -Match 'function script:Set-GuiWindowsUpdatePresetSelection'
		$script:UpdatesPanelContent | Should -Match 'function script:Start-GuiWindowsUpdateOperation'
		$script:UpdatesPanelContent | Should -Match 'function script:Write-GuiWindowsUpdateDiagnostic'
		$script:UpdatesPanelContent | Should -Match 'LogDebug -Message \$Message -Scope ''GUI'''
		$script:UpdatesPanelContent | Should -Not -Match 'LogDebug -Message \$Message -Scope ''GUI'' -Always'
		$script:UpdatesPanelContent | Should -Match 'function script:Test-GuiWindowsUpdateCheckBoxChecked'
        $script:UpdatesPanelContent | Should -Match 'function script:Set-GuiWindowsUpdateOperationInProgress'
        $script:UpdatesPanelContent | Should -Match 'function script:Get-GuiWindowsUpdateSelectionSnapshot'
        $script:UpdatesPanelContent | Should -Match 'function script:Sync-GuiWindowsUpdateSelectionEntry'
        $script:UpdatesPanelContent | Should -Match "SharedHelpers\\WindowsUpdate\.Helpers\.ps1"
        $script:UpdatesPanelContent | Should -Match 'Get-WindowsUpdateList'
        $script:UpdatesPanelContent | Should -Match 'Download-WindowsUpdates'
        $script:UpdatesPanelContent | Should -Match 'Install-WindowsUpdates'
        $script:UpdatesPanelContent | Should -Match 'Get-WindowsUpdateHistory'
        $script:UpdatesPanelContent | Should -Match 'Scan for Updates'
        $script:UpdatesPanelContent | Should -Match 'Download Only'
        $script:UpdatesPanelContent | Should -Match 'Install Selected'
        $script:UpdatesPanelContent | Should -Match '\$Script:WindowsUpdateSelectionState = \[System\.Collections\.Generic\.Dictionary\[string, bool\]\]::new'
        $script:UpdatesPanelContent | Should -Match 'function script:Get-GuiWindowsUpdateIdentityKey'
        $script:UpdatesPanelContent | Should -Match '\$Update\.Identity\.UpdateID'
        $script:UpdatesPanelContent | Should -Match '\$Update\.Identity\.RevisionNumber'
        $script:UpdatesPanelContent | Should -Match 'function script:Sync-GuiWindowsUpdateSelectionStateWithAvailableUpdates'
        $script:UpdatesPanelContent | Should -Match 'function script:Get-GuiWindowsUpdateSelectionState'
        $script:UpdatesPanelContent | Should -Match 'function script:Set-GuiWindowsUpdateSelectionState'
        $script:UpdatesPanelContent | Should -Match '\$selected = Get-GuiWindowsUpdateSelectionState -Update \$Update'
        $script:UpdatesPanelContent | Should -Match '\$checkBox\.IsThreeState = \$false'
        $script:UpdatesPanelContent | Should -Match '\$checkBox\.IsChecked = \$selected'
        $script:UpdatesPanelContent | Should -Match 'Selected = \$selected'
        $script:UpdatesPanelContent | Should -Match '\$checkBox\.Add_Click\(\{'
        $script:UpdatesPanelContent | Should -Match '\$testGuiWindowsUpdateCheckBoxCheckedScript = \$\{function:Test-GuiWindowsUpdateCheckBoxChecked\}'
        $script:UpdatesPanelContent | Should -Match '\$writeGuiWindowsUpdateDiagnosticScript = \$\{function:Write-GuiWindowsUpdateDiagnostic\}'
        $script:UpdatesPanelContent | Should -Match '\$selectionEntry\.Selected = & \$testGuiWindowsUpdateCheckBoxCheckedScript -CheckBox \$checkBox'
        $script:UpdatesPanelContent | Should -Match '\$setGuiWindowsUpdateSelectionStateScript = \$\{function:Set-GuiWindowsUpdateSelectionState\}'
        $script:UpdatesPanelContent | Should -Match '& \$setGuiWindowsUpdateSelectionStateScript -Update \$selectionEntry\.Update -Selected'
        $script:UpdatesPanelContent | Should -Match 'Windows Update row toggle changed'
        $script:UpdatesPanelContent | Should -Match 'Windows Update row added'
        $script:UpdatesPanelContent | Should -Match '\$updateGuiWindowsUpdateActionStateScript = \$\{function:Update-GuiWindowsUpdateActionState\}\s*\r?\n\s*\$setGuiWindowsUpdateSelectionStateScript = \$\{function:Set-GuiWindowsUpdateSelectionState\}\s*\r?\n\s*\$testGuiWindowsUpdateCheckBoxCheckedScript = \$\{function:Test-GuiWindowsUpdateCheckBoxChecked\}\s*\r?\n\s*\$writeGuiWindowsUpdateDiagnosticScript = \$\{function:Write-GuiWindowsUpdateDiagnostic\}\s*\r?\n\s*\$checkBox\.Add_Click'
        $script:UpdatesPanelContent | Should -Match '& \$updateGuiWindowsUpdateActionStateScript'
        $script:UpdatesPanelContent | Should -Not -Match '\$isSelected = \[bool\]\$checkBox\.IsChecked'
        $script:UpdatesPanelContent | Should -Not -Match 'Set-GuiWindowsUpdateSelectionState `\s*\r?\n\s*-Update \$selectionEntry\.Update `\s*\r?\n\s*-Selected \$isSelected'
        $script:UpdatesPanelContent | Should -Not -Match 'Register-GuiEventHandler -Source \$checkBox -EventName ''Checked'''
        $script:UpdatesPanelContent | Should -Not -Match 'Register-GuiEventHandler -Source \$checkBox -EventName ''Unchecked'''
        $script:UpdatesPanelContent | Should -Not -Match 'Register-GuiEventHandler -Source \$checkBox -EventName ''Click'''
        $script:UpdatesPanelContent | Should -Match 'function script:Set-GuiWindowsUpdateActionButtonState'
        $script:UpdatesPanelContent | Should -Match '\$selectedCount = 0'
        $script:UpdatesPanelContent | Should -Match '\$selectionSnapshot = Get-GuiWindowsUpdateSelectionSnapshot'
        $script:UpdatesPanelContent | Should -Match '\$controlCount = \[int\]\$selectionSnapshot\.ControlCount'
        $script:UpdatesPanelContent | Should -Match 'for \(\$index = 0; \$index -lt \$controlCount; \$index\+\+\)'
        $script:UpdatesPanelContent | Should -Match '\$checkBox = \$entry\.CheckBox'
        $script:UpdatesPanelContent | Should -Match 'Test-GuiWindowsUpdateCheckBoxChecked -CheckBox \$checkBox'
        $script:UpdatesPanelContent | Should -Match '\$selectedCount\+\+'
        $script:UpdatesPanelContent | Should -Match '\$canRunSelectedUpdateAction = \(-not \$busy\) -and \(\$selectedCount -gt 0\)'
        $script:UpdatesPanelContent | Should -Match 'Windows Update action state: controls='
        $script:UpdatesPanelContent | Should -Match 'Set-GuiWindowsUpdateActionButtonState -Button \$Script:BtnWindowsUpdateDownload -Enabled \$canRunSelectedUpdateAction -EnabledVariant ''Primary'' -DisabledVariant ''Secondary'''
        $script:UpdatesPanelContent | Should -Match 'Set-GuiWindowsUpdateActionButtonState -Button \$Script:BtnWindowsUpdateInstall -Enabled \$canRunSelectedUpdateAction -EnabledVariant ''Primary'' -DisabledVariant ''Secondary'''
        $script:UpdatesPanelContent | Should -Match 'Set-ButtonChrome -Button \$Button -Variant \$variant -Compact'
        $script:UpdatesPanelContent | Should -Match 'Windows Update button state: label='
        $script:UpdatesPanelContent | Should -Match 'Windows Update action-state refresh failed'
        $script:UpdatesPanelContent | Should -Match 'Windows Update scan complete: available='
        $script:UpdatesPanelContent | Should -Match 'Scan complete\. \{0\} available update\(s\)\. \{1\} selected\.'
        $script:UpdatesPanelContent | Should -Not -Match 'Set-GuiWindowsUpdateSelectionState -Update \$SelectionEntry\.Update -Selected'
        $script:UpdatesPanelContent | Should -Not -Match 'Set-GuiWindowsUpdateSelectionState -Update \$Update -Selected \(\[bool\]\$checkBox\.IsChecked\)'
        $script:UpdatesPanelContent | Should -Match 'function Get-PortableWindowsUpdateIdentityKey'
        $script:UpdatesPanelContent | Should -Match 'Get-PortableWindowsUpdateIdentityKey -Update \$selection'
        $script:UpdatesPanelContent | Should -Match 'Get-PortableWindowsUpdateIdentityKey -Update \$_'
        $script:UpdatesPanelContent | Should -Not -Match 'foreach \(\$entry in @\(\$Script:WindowsUpdateSelectionControls\)\)'
        $script:UpdatesPanelContent | Should -Not -Match '\$entry\.CheckBox -and \[bool\]\$entry\.CheckBox\.IsChecked -and \$entry\.Update'
        $script:UpdatesPanelContent | Should -Not -Match 'for \(\$index = 0; \$selectionControls -and \$index -lt \$selectionControls\.Count; \$index\+\+\)'
        $script:UpdatesPanelContent | Should -Not -Match '\$selectedCount = @\('
        $script:UpdatesPanelContent | Should -Not -Match '\$selectedCount = @\(Get-GuiWindowsUpdateSelectedItems\)\.Count'
        $script:UpdatesPanelContent | Should -Match 'Open Update Runner'
        $script:UpdatesPanelContent | Should -Match 'Disable Updates'
        $script:UpdatesPanelContent | Should -Match 'Load Disable Selection'
        $script:UpdatesPanelContent | Should -Match 'Update Settings Presets'
        $script:UpdatesPanelContent | Should -Match "WindowsUpdateDisableAll -Enable"
        $script:UpdatesPanelContent | Should -Match "WindowsUpdateDisableAll -Disable"
        $script:UpdatesPanelContent | Should -Match "QualityUpdateDeferral -FourDays"
        $script:UpdatesPanelContent | Should -Match 'ButtonVariant ''DangerSubtle'''
        $script:UpdatesPanelContent | Should -Match 'BorderColor \$theme\.DangerText'
        $script:UpdatesPanelContent | Should -Match 'Temporarily enabling Windows Update service for manual update run'
        $script:UpdatesPanelContent | Should -Match 'Disabling Windows Update service after manual update run'
        $script:UpdatesPanelContent | Should -Match 'function Set-BaselineWindowsUpdateManualRunServiceState'
        $script:UpdatesPanelContent | Should -Match 'function Set-PortableWindowsUpdateProgressStatus'
        $script:UpdatesPanelContent | Should -Match 'function Select-PortableWindowsUpdatePostInstallUpdates'
        $script:UpdatesPanelContent | Should -Match '\$remainingAfterInstall = @\(Select-PortableWindowsUpdatePostInstallUpdates -AvailableUpdates \$availableAfterInstall -Selections \$SelectedIdentities\)'
        $script:UpdatesPanelContent | Should -Match '\$postInstallUpdates = @\(\$remainingAfterInstall \| ForEach-Object \{ ConvertTo-PortableWindowsUpdateRecord -Update \$_ \}\)'
        $script:UpdatesPanelContent | Should -Match 'Refreshing Windows Update state'
        $script:UpdatesPanelContent | Should -Match '\$downloadProgressCallback = \{'
        $script:UpdatesPanelContent | Should -Match '\$installProgressCallback = \{'
        $script:UpdatesPanelContent | Should -Match '\$Sync\.Status = \(''\{0\}\.\.\. \{1\}%'' -f \$ActionText, \$percentComplete\)'
        $script:UpdatesPanelContent | Should -Match 'ActionText ''Downloading selected Windows updates'''
        $script:UpdatesPanelContent | Should -Match 'ActionText ''Installing selected Windows updates'''
        $script:UpdatesPanelContent | Should -Match 'Download-WindowsUpdates -Updates \$selectedUpdates -ProgressCallback \$downloadProgressCallback'
        $script:UpdatesPanelContent | Should -Match 'Install-WindowsUpdates -Updates \$selectedUpdates -ProgressCallback \$installProgressCallback'
        $script:UpdatesPanelContent | Should -Match '\$invokeGuiSafeActionScript = \$\{function:Invoke-GuiSafeAction\}'
        $script:UpdatesPanelContent | Should -Match '& \$invokeGuiSafeActionScript -Context ''WindowsUpdate\.RuntimePanel'''
        $script:UpdatesPanelContent | Should -Match '& \$invokeGuiSafeActionScript -Context \(''WindowsUpdate\.Card\.\{0\}'''
        $script:UpdatesPanelContent | Should -Match '& \$invokeGuiSafeActionScript -Context \(''WindowsUpdate\.Preset\.\{0\}'''
        $script:UpdatesPanelContent | Should -Match '\$showGuiWindowsUpdateRuntimeViewScript = \$\{function:Show-GuiWindowsUpdateRuntimeView\}'
        $script:UpdatesPanelContent | Should -Match '\$openUpdateRunnerAction = \{[\s\S]*& \$showGuiWindowsUpdateRuntimeViewScript'
        $script:UpdatesPanelContent | Should -Match '\$setGuiWindowsUpdatePresetSelectionScript = \$\{function:Set-GuiWindowsUpdatePresetSelection\}'
        $script:UpdatesPanelContent | Should -Match '\$applyPresetAction = \{[\s\S]*& \$setGuiWindowsUpdatePresetSelectionScript -PresetName \$presetName'
        $script:UpdatesPanelContent | Should -Match '\$loadDisableUpdatesPresetAction = \{[\s\S]*& \$setGuiWindowsUpdatePresetSelectionScript -PresetName ''DisableAll'''
        $script:UpdatesPanelContent | Should -Match '-ShowDialog -Action \$applyPresetAction'
        $script:UpdatesPanelContent | Should -Match '\$setGuiWindowsUpdateStatusScript = \$\{function:Set-GuiWindowsUpdateStatus\}'
        $script:UpdatesPanelContent | Should -Match '\$completeGuiWindowsUpdateOperationScript = \$\{function:Complete-GuiWindowsUpdateOperation\}'
        $script:UpdatesPanelContent | Should -Match '\$setGuiWindowsUpdateOperationInProgressScript = \$\{function:Set-GuiWindowsUpdateOperationInProgress\}'
        $script:UpdatesPanelContent | Should -Match '\$updateGuiWindowsUpdateActionStateScript = \$\{function:Update-GuiWindowsUpdateActionState\}'
        $script:UpdatesPanelContent | Should -Match '\$startGuiWindowsUpdateOperationScript = \$\{function:Start-GuiWindowsUpdateOperation\}'
        $script:UpdatesPanelContent | Should -Match '\$Script:GuiWindowsUpdateOperationInvoker = \{'
        $script:UpdatesPanelContent | Should -Match '& \$startGuiWindowsUpdateOperationScript -Action \$Action'
        $script:UpdatesPanelContent | Should -Not -Match '\sStart-GuiWindowsUpdateOperation -Action \$Action'
        $script:UpdatesPanelContent | Should -Match '& \$setGuiWindowsUpdateStatusScript -Message'
        $script:UpdatesPanelContent | Should -Match '& \$setGuiWindowsUpdateOperationInProgressScript -InProgress \$false\s*\r?\n\s*& \$completeGuiWindowsUpdateOperationScript -Payload'
        $script:UpdatesPanelContent | Should -Match '& \$completeGuiWindowsUpdateOperationScript -Payload'
        $script:UpdatesPanelContent | Should -Match '& \$updateGuiWindowsUpdateActionStateScript'
        $script:UpdatesPanelContent | Should -Match '& \$Script:GuiWindowsUpdateOperationInvoker -Action'
        $script:UpdatesPanelContent | Should -Match 'Restart Windows to finish applying updates\.'
        $script:UpdatesPanelContent | Should -Match '\$Script:WindowsUpdateAvailableUpdates\.Clear\(\)'
        $script:UpdatesPanelContent | Should -Match '\$Payload\.PSObject\.Properties\[''RebootRequired''\]'
        $script:UpdatesPanelContent | Should -Match '\[object\[\]\]\$Script:WindowsUpdateAvailableUpdates\.ToArray\(\)'
        $script:UpdatesPanelContent | Should -Match '\[object\[\]\]\$Script:WindowsUpdateHistoryEntries\.ToArray\(\)'
        $script:UpdatesPanelContent | Should -Not -Match '\$Script:TweakManifest'
    }

    It 'keeps GUI error and warning logs from collapsing exceptions to message-only text' {
        $guiSource = Get-BaselineTestSourceText -Path @(
            (Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1')
            (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../../Module/GUI') -Recurse -File -Include '*.ps1','*.psm1' | Select-Object -ExpandProperty FullName)
        )

        $guiSource | Should -Not -Match 'LogWarning[ \t]*\([^\r\n]*Exception\.Message'
        $guiSource | Should -Not -Match 'LogError[ \t]*\([^\r\n]*Exception\.Message'
        $guiSource | Should -Not -Match 'Write-Warning[ \t]*\([^\r\n]*Exception\.Message'
        $script:GuiContent | Should -Match "Get-Command -Name 'Write-BaselineError' -CommandType Function"
        $script:GuiContent | Should -Match '& \$writeBaselineErrorCommand -Message \$errorText -Scope \$Context'
        $guiSource | Should -Not -Match 'GUI event failed \['
        $script:GuiContent | Should -Not -Match 'GuiLogRuntimeFailureEventFailed'
    }

    It 'routes GUI preset debug through the standard debug logger' {
        $script:GuiContent | Should -Match 'function Write-GuiPresetDebug'
        $script:GuiContent | Should -Match '\[Context=\{0\}\] \{1\}'
        $script:GuiContent | Should -Match 'GUI event failed: \{0\}'
        $script:GuiContent | Should -Not -Match 'GUI event failed \[\{0\}\]: \{1\}'
        $script:GuiContent | Should -Match '\$debugTrailText = "\[GUIPreset\] \{0\}"'
        $script:GuiContent | Should -Match 'LogDebug -Message \$debugMessage -Scope ''GUIPreset'''
        $script:GuiContent | Should -Match 'Write-BaselineDebug -Message \$debugMessage -Scope ''GUIPreset'''
        $script:GuiContent | Should -Not -Match 'GUI preset debug \[\{0\}\]: \{1\}'
        $script:GuiContent | Should -Not -Match '\[Scope=GUIPreset\]'
        $script:GuiContent | Should -Not -Match "Get-Date -Format 'HH:mm:ss\.fff'"
    }

    It 'exposes Windows Updates as a top navigation mode rather than a primary tab' {
        $updatesModeStart = $script:GuiContent.IndexOf('function Set-GuiUpdatesMode')
        $updatesModeEnd = $script:GuiContent.IndexOf('function Set-GuiDeploymentMediaMode', $updatesModeStart)
        $updatesModeSource = $script:GuiContent.Substring($updatesModeStart, $updatesModeEnd - $updatesModeStart)
        $syncButtonsStart = $script:ActionHandlersContent.IndexOf('function Sync-UxActionButtonText')
        $syncButtonsEnd = $script:ActionHandlersContent.IndexOf('function Update-RunPathContextLabel', $syncButtonsStart)
        $syncButtonsSource = $script:ActionHandlersContent.Substring($syncButtonsStart, $syncButtonsEnd - $syncButtonsStart)

        $script:GuiContent | Should -Match 'Name="NavModeUpdates"'
        $script:GuiContent | Should -Match '(?s)Name="NavModeTweaks".*Name="NavModeGaming".*Name="NavModeUpdates".*Name="NavModeDeploymentMedia".*Name="NavModeApps"'
        $script:GuiContent | Should -Match 'function Set-GuiUpdatesMode'
        $script:GuiContent | Should -Match 'Build-TabContent -PrimaryTab ''Updates'' -SkipIdlePrebuild'
        $script:GuiContent | Should -Match 'if \(\$Script:UpdatesModeActive\)\s*\{\s*\$targetTab = ''Updates'''
        $script:GuiContent | Should -Match '\$Script:ModeSubtitle\.HorizontalAlignment = \[System\.Windows\.HorizontalAlignment\]::Center'
        $script:GuiContent | Should -Match '\$Script:PrimaryTabHost\.Visibility = if \(\$Enable\) \{ \$collapsed \} else \{ \$visible \}'
        $script:GuiContent | Should -Not -Match 'SafeModeGroup'
        $updatesModeSource | Should -Match '\$Script:BtnPreviewRun\.Visibility = \$visible'
        $updatesModeSource | Should -Match '\$Script:BtnRun\.Visibility = \$visible'
        $updatesModeSource | Should -Match '\$Script:BtnDeploymentMediaPreviewPlan\.Visibility = \$collapsed'
        $updatesModeSource | Should -Match '\$Script:BtnDeploymentMediaStartBuild\.Visibility = \$collapsed'
        $updatesModeSource | Should -Not -Match '\$Script:BtnPreviewRun\.Visibility = if \(\$Enable\)'
        $updatesModeSource | Should -Not -Match '\$Script:BtnRun\.Visibility = if \(\$Enable\)'
        $syncButtonsSource | Should -Match 'if \(\$Script:AppsModeActive -or \$Script:DeploymentMediaModeActive\)'
        $syncButtonsSource | Should -Match '\$Script:BtnDeploymentMediaPreviewPlan\.Visibility = if \(\$Script:DeploymentMediaModeActive\) \{ \[System\.Windows\.Visibility\]::Visible \} else \{ \[System\.Windows\.Visibility\]::Collapsed \}'
        $syncButtonsSource | Should -Match '\$Script:BtnDeploymentMediaStartBuild\.Visibility = if \(\$Script:DeploymentMediaModeActive\) \{ \[System\.Windows\.Visibility\]::Visible \} else \{ \[System\.Windows\.Visibility\]::Collapsed \}'
        $syncButtonsSource | Should -Not -Match '\$Script:AppsModeActive -or \$Script:UpdatesModeActive'
        $syncButtonsSource | Should -Not -Match 'UpdatesModeActive -or'
        $syncButtonsSource | Should -Match '\$Script:BtnDefaults\.Visibility = if \(\$updatesModeActive\) \{ \[System\.Windows\.Visibility\]::Collapsed \} else \{ \[System\.Windows\.Visibility\]::Visible \}'
        $script:ActionHandlersContent | Should -Not -Match 'if \(\$Script:UpdatesModeActive\) \{ return \}'
        $script:GuiContent | Should -Not -Match '"Updates"\s+=\s+@\(\)'
    }

    It 'exposes Gaming as a standalone top navigation mode' {
        $gamingModeStart = $script:GuiContent.IndexOf('function Set-GuiGamingMode')
        $gamingModeEnd = $script:GuiContent.IndexOf('function Set-GuiUpdatesMode', $gamingModeStart)
        $gamingModeSource = $script:GuiContent.Substring($gamingModeStart, $gamingModeEnd - $gamingModeStart)
        $gamingNavStart = $script:ActionHandlersContent.IndexOf('if ($NavModeGaming)')
        $gamingNavEnd = $script:ActionHandlersContent.IndexOf('if ($NavModeApps)', $gamingNavStart)
        $gamingNavSource = $script:ActionHandlersContent.Substring($gamingNavStart, $gamingNavEnd - $gamingNavStart)
        $gamingLeadStart = $script:PresetUiContent.IndexOf("if (`$BuildContext.PrimaryTab -eq 'Gaming')")
        $gamingLeadEnd = $script:PresetUiContent.IndexOf("if (`$BuildContext.PrimaryTab -notin @('Gaming', 'Initial Setup'))", $gamingLeadStart)
        $gamingLeadSource = $script:PresetUiContent.Substring($gamingLeadStart, $gamingLeadEnd - $gamingLeadStart)

        $script:GuiContent | Should -Match 'Name="NavModeGaming"'
        $script:GuiContent | Should -Match 'function Set-GuiGamingMode'
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:NavModeGaming -IconName ''Games'''
        $script:GuiContent | Should -Match 'if \(\[string\]\$pKey -eq ''Gaming''\)\s*\{\s*continue\s*\}'
        $script:GuiContent | Should -Match 'if \(\$Script:GamingModeActive\)\s*\{\s*\$targetTab = ''Gaming'''
        $gamingModeSource | Should -Not -Match 'Set-GameModeState'
        $gamingModeSource | Should -Match 'Set-GuiGamingRuntimeState -Enabled:\$true'
        $gamingModeSource | Should -Match '\[switch\]\$SkipContentRestore'
        $gamingModeSource | Should -Match 'Build-TabContent -PrimaryTab ''Gaming'' -SkipIdlePrebuild'
        $gamingModeSource | Should -Match '\$Script:PrimaryTabHost\.Visibility = if \(\$Enable\) \{ \$collapsed \} else \{ \$visible \}'
        $script:BuildTabContentContent | Should -Match '(?s)Add-TabContentLeadPanel -BuildContext \$buildContext\s*\$contentAlreadyDisplayed = \$false\s*if \(\$PrimaryTab -eq ''Gaming'' -and -not \$BackgroundBuild\)'
        $script:BuildTabContentContent | Should -Match 'Show-TabContentBuildPanel -BuildContext \$buildContext'
        $script:BuildTabContentContent | Should -Match '\$Script:VisibleTabContentPrimaryTab = \[string\]\$BuildContext.PrimaryTab'
        $script:ContentManagementContent | Should -Match '\$Script:VisibleTabContentPrimaryTab = \$PrimaryTab'
        $script:BuildTabContentContent | Should -Match 'Test-TabContentBuildStillCurrent -PrimaryTab \$PrimaryTab -BuildGeneration \$buildGeneration'
        $script:BuildTabContentContent | Should -Match 'Start-ProgressiveTabSectionsHydration -BuildContext \$buildContext -AllTabIndexes \$allTabIndexes'
        $script:BuildTabContentContent | Should -Match 'Save-TabContentCacheEntry -BuildContext \$BuildContext -AllTabIndexes \$AllTabIndexes -CacheOnly:\(\$AlreadyDisplayed -or -not \$displayBuiltContent\)'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent\.GamingLeadPanel\.RenderYield'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent\.ProgressiveHydration'
        $script:ContentManagementContent | Should -Not -Match '\$groupedTweaks = if \(\$PrimaryTab -eq ''Gaming''\)'
        $gamingNavSource | Should -Match 'Set-GuiGamingMode -Enable:\$true'
        $gamingNavSource | Should -Not -Match 'Set-GuiUpdatesMode|Set-GuiDeploymentMediaMode|Set-GuiAppsMode'
        $script:ActionHandlersContent | Should -Match 'Set-GuiGamingMode -Enable:\$false -SkipContentRestore'
        $gamingLeadSource | Should -Match 'New-GameModeLandingPanel'
        $gamingLeadSource | Should -Match '(?s)New-GameModeLandingPanel\)\)\)\s*return'
        $gamingLeadSource | Should -Not -Match 'New-TabPresetPanel'
        $script:GuiContent | Should -Not -Match 'ChkGameMode'
        $script:StyleContent | Should -Not -Match 'ChkGameMode'
        $script:PresetUiContent | Should -Not -Match '\$gameModeToggle|Build-TabContent/GameModeToggle'
    }

    It 'clears visible Gaming content immediately when another top mode is selected' {
        $gamingModeStart = $script:GuiContent.IndexOf('function Set-GuiGamingMode')
        $gamingModeEnd = $script:GuiContent.IndexOf('function Set-GuiUpdatesMode', $gamingModeStart)
        $gamingModeSource = $script:GuiContent.Substring($gamingModeStart, $gamingModeEnd - $gamingModeStart)

        $script:GuiContent | Should -Match 'function Clear-GuiTabContentIfOwnedBy'
        $script:GuiContent | Should -Match '\[string\]\$Script:VisibleTabContentPrimaryTab -ne \$PrimaryTab'
        $script:GuiContent | Should -Match '\$Script:TabContentBuildGeneration = \[int\]\$Script:TabContentBuildGeneration \+ 1'
        $script:GuiContent | Should -Match '\$ContentScroll.Content = \$null'
        $script:GuiContent | Should -Match '\$Script:VisibleTabContentPrimaryTab = \$null'
        $script:GuiContent | Should -Match 'AppsModule\.Clear-GuiTabContentIfOwnedBy'
        $gamingModeSource | Should -Match 'Clear-GuiTabContentIfOwnedBy -PrimaryTab ''Gaming'''
    }

    It 'restores standard Optimize selections when leaving Gaming mode' {
        $gamingModeStart = $script:GuiContent.IndexOf('function Set-GuiGamingMode')
        $gamingModeEnd = $script:GuiContent.IndexOf('function Set-GuiUpdatesMode', $gamingModeStart)
        $gamingModeSource = $script:GuiContent.Substring($gamingModeStart, $gamingModeEnd - $gamingModeStart)

        $script:GuiContent | Should -Match 'function Save-GuiStandardSelectionStateForGaming'
        $script:GuiContent | Should -Match 'function Restore-GuiStandardSelectionStateAfterGaming'
        $script:GuiContent | Should -Match 'function Copy-GuiControlSelectionState'
        $script:GuiContent | Should -Match 'function Set-GuiControlSelectionState'
        $script:GuiContent | Should -Match 'function Clear-GuiControlSelectionState'
        $script:GuiContent | Should -Match '\$Script:StandardSelectionStateBeforeGaming = \[pscustomobject\]@\{'
        $script:GuiContent | Should -Match 'Copy-GuiExplicitSelectionDefinition -Definition \$definition -FunctionName \(\[string\]\$definitionKey\)'
        $script:GuiContent | Should -Match '\[string\]\$definition.Source -eq ''GameMode'''
        $script:GuiContent | Should -Match 'Remove-GuiExplicitSelectionDefinition -FunctionName \(\[string\]\$definitionKey\)'
        $script:GuiContent | Should -Match 'Set-GuiExplicitSelectionDefinition -FunctionName \(\[string\]\$definitionKey\) -Definition \$explicitDefinitions\[\$definitionKey\]'
        $script:PresetSelectionStateContent | Should -Match "\[string\]\`$definition.Source -eq 'GameMode' -and -not \[bool\]\`$Script:GameMode"
        $gamingModeSource | Should -Match 'Save-GuiStandardSelectionStateForGaming'
        $gamingModeSource | Should -Match 'Restore-GuiStandardSelectionStateAfterGaming'
        $gamingModeSource | Should -Match '& \$Script:SyncGameModePlanToGamingControlsScript'
    }

    It 'suppresses recursive top navigation events during programmatic mode synchronization' {
        $script:GuiContent | Should -Match 'function Set-GuiNavModeCheckedState'
        $script:GuiContent | Should -Match '\$Script:SuppressNavModeSelectionChanged = \$true'
        $script:GuiContent | Should -Match '\$Script:SuppressNavModeSelectionChanged = \$previousSuppressNavModeSelectionChanged'
        $script:GuiContent | Should -Match 'Set-GuiNavModeCheckedState'
        $script:ActionHandlersContent | Should -Match 'if \(\$Script:SuppressNavModeSelectionChanged\) \{ return \}'
        $script:GuiContent | Should -Not -Match 'AppsModule\.Set-GuiGamingMode\.UpdateGuiNavModeChrome'
        $script:GuiContent | Should -Not -Match 'AppsModule\.Set-GuiUpdatesMode\.UpdateGuiNavModeChrome'
        $script:GuiContent | Should -Not -Match 'AppsModule\.Set-GuiDeploymentMediaMode\.UpdateGuiNavModeChrome'
        $script:GuiContent | Should -Not -Match 'AppsModule\.Set-GuiAppsMode\.UpdateGuiNavModeChrome'
    }

    It 'keeps top menu options visible across navigation modes' {
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuFile"'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuActions"'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuView"'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuTools"'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuHelp"'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuToolsAppsManager" Header="Apps Manager"/>'
        $script:MainWindowContent | Should -Match '<MenuItem Name="MenuToolsUpdateAllApps" Header="Update All Applications"/>'
        $script:MainWindowContent | Should -Match '<Separator Name="MenuToolsSepApps"/>'
        $script:GuiContent | Should -Not -Match '\$tweaksOnlyMenu|\$appsOnlyMenu'
        $script:GuiContent | Should -Not -Match 'MenuActionsPreviewRun[\s\S]{0,300}\.Visibility = if \(\$Enable\)'
        $script:GuiContent | Should -Not -Match 'MenuToolsAppsManager[\s\S]{0,300}\.Visibility = if \(\$Enable\)'
    }

    It 'exposes Deployment Media Builder as a top navigation GUI without view-level search or filters' {
        $script:GuiContent | Should -Match 'Name="NavModeDeploymentMedia"'
        $script:GuiContent | Should -Match 'Name="DeploymentMediaView"'
        $script:GuiContent | Should -Match 'function Set-GuiDeploymentMediaMode'
        $script:GuiContent | Should -Match 'Initialize-GuiDeploymentMediaBuilderView'
        $script:GuiContent | Should -Match 'Sync-GuiDeploymentMediaBuilderViewText'
        $script:GuiContent | Should -Match '\$Script:TxtSearch, \$Script:TxtSearchPlaceholder, \$Script:BtnClearSearch'
        $script:GuiContent | Should -Match 'Name="BtnDeploymentMediaDetectIso"'
        $script:GuiContent | Should -Match 'Name="BtnDeploymentMediaPreviewPlan"'
        $script:GuiContent | Should -Match 'Name="BtnDeploymentMediaStartBuild"'
        $script:GuiContent | Should -Match 'Name="BtnDeploymentMediaCreateAutounattend"'
        $script:GuiContent | Should -Match '(?s)<WrapPanel Name="BottomActionBar".*Name="BtnDeploymentMediaPreviewPlan".*Name="BtnDeploymentMediaStartBuild"'
        $script:GuiContent | Should -Match 'Set-ButtonChrome -Button \$Script:BtnDeploymentMediaPreviewPlan -Variant ''Preview'''
        $script:GuiContent | Should -Match 'Set-ButtonChrome -Button \$Script:BtnDeploymentMediaStartBuild -Variant ''Primary'''
        $script:GuiContent | Should -Not -Match 'Set-ButtonChrome -Button \$Script:BtnDeploymentMediaPreviewPlan -Variant ''Preview'' -Compact'
        $script:GuiContent | Should -Not -Match 'Set-ButtonChrome -Button \$Script:BtnDeploymentMediaStartBuild -Variant ''Primary'' -Compact'
        $script:DeploymentMediaBuilderViewContent | Should -Match 'Show-GuiDeploymentMediaUnattendGeneratorDialog'
        $script:DeploymentMediaBuilderViewContent | Should -Match 'Get-GuiDeploymentMediaUnattendOptionGroups'
        $script:DeploymentMediaBuilderViewContent | Should -Match 'New-GuiDeploymentMediaUnattendXmlDocument'
        $script:DeploymentMediaBuilderViewContent | Should -Not -Match 'New-Object System\.Windows\.Controls\.WebBrowser'
        $script:DeploymentMediaBuilderViewContent | Should -Not -Match '\[Uri\]'
        $script:DeploymentMediaBuilderViewContent | Should -Not -Match '\.Navigate\('

        $idxStart = $script:MainWindowContent.IndexOf('<Grid Name="DeploymentMediaView"')
        $idxStart | Should -BeGreaterThan -1
        $idxEnd = $script:MainWindowContent.IndexOf('<Grid Name="AppsView"', $idxStart)
        $idxEnd | Should -BeGreaterThan $idxStart
        $deploymentViewXaml = $script:MainWindowContent.Substring($idxStart, $idxEnd - $idxStart)
        $deploymentViewXaml | Should -Match 'Setup checklist'
        $deploymentViewXaml | Should -Match 'Name="DeploymentMediaChecklistExpander"'
        $deploymentViewXaml.IndexOf('Setup checklist') | Should -BeLessThan $deploymentViewXaml.IndexOf('Choose source ISO')
        $deploymentViewXaml | Should -Not -Match 'TxtDeploymentMediaPlanPreview'
        $deploymentViewXaml | Should -Not -Match 'Search'
        $deploymentViewXaml | Should -Not -Match 'Filter'
        $deploymentViewXaml | Should -Not -Match 'Name="BtnDeploymentMediaPreviewPlan"'
        $deploymentViewXaml | Should -Not -Match 'Name="BtnDeploymentMediaStartBuild"'
    }

    It 'themes the platform filter ComboBox with the same popup style as other filters' {
        $script:StyleContent | Should -Match 'if \(\$CmbPlatformFilter\) \{ Set-ChoiceComboStyle -Combo \$CmbPlatformFilter \}'
    }

    It 'reapplies shared combo styling to live tweak-row dropdowns during theme refresh' {
        $script:StyleContent | Should -Match 'function Update-ChoiceComboStyles'
        $script:StyleContent | Should -Match '\$entry -is \[System\.Windows\.Controls\.ComboBox\]'
        $script:StyleContent | Should -Match 'Test-GuiObjectField -Object \$entry -FieldName ''ComboBox'''
        $script:StyleContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyleManagement\.Update-ChoiceComboStyles\.SetChoiceComboStyle'''
        $script:StyleContent | Should -Match 'if \(\$CmbAppsStatusFilter\) \{ Set-ChoiceComboStyle -Combo \$CmbAppsStatusFilter \}\s*Update-ChoiceComboStyles'
    }

    It 'captures apps callbacks through runtime commands instead of raw function names' {
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Start-AppsCacheRefresh'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Set-AppPackageSourcePreferenceState'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Start-AppsModuleActionAsync'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Start-AppsModuleBatchActionAsync'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Clear-AppSelectionState'"
        $script:GuiContent | Should -Match "Get-GuiRuntimeCommand -Name 'Set-AppSelectionState'"
        $script:GuiContent | Should -Match "Get-GuiRuntimeCommand -Name 'Start-AppsModuleActionAsync'"
        $script:GuiContent | Should -Match '& \$setAppSelectionStateCommand'
        $script:ActionHandlersContent | Should -Match '& \$startAppsModuleActionAsyncCommand'
    }

    It 'routes menu-state sync fallbacks through Write-SwallowedException' {
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuActionsScanSystem\.SetChecked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuActionsScanSystem\.SyncClick'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuActionsScanSystem\.Checked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuActionsScanSystem\.Unchecked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuViewFilters\.SetChecked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuViewTheme\.SetChecked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuViewTheme\.SyncClick'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuViewTheme\.Checked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuViewTheme\.Unchecked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuToolsAppsManager\.Checked'
        $script:ActionHandlersContent | Should -Match 'ActionHandlers\.SyncMenuState\.MenuToolsUpdateAllApps\.Checked'
    }

    It 'routes add-custom-app refresh and disconnect relay failures through Write-SwallowedException' {
        $script:ActionHandlersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.AddCustomApp\.RefreshCatalog'''
        $script:ActionHandlersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.SyncMenuState\.MenuActionsDisconnect\.RaiseEvent'''
    }

    It 'exposes a dedicated apps scan button instead of repurposing the main run button' {
        $script:GuiContent | Should -Match '<Button Name="BtnScanInstalledApps"'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$BtnScanInstalledApps -EventName ''Click'''
        $script:ActionHandlersContent | Should -Not -Match 'Set-GuiButtonIconContent -Button \$Script:BtnRun -IconName ''ArrowSync'''
    }

    It 'uses the neutral installed-status prompt while the cache is cold' {
        $script:ApplicationsViewContent | Should -Match 'GuiAppsCacheRefreshRequired'
        $script:ApplicationsViewContent | Should -Match 'Installed status not scanned'
    }

    It 'includes the installed-app cache in the apps render signature' {
        $script:ApplicationsViewContent | Should -Match 'function Get-ApplicationCacheSignature'
        $script:ApplicationsViewContent | Should -Match '"Cache=\$cacheSignature"'
    }

    It 'includes package-manager availability in the apps render signature' {
        $script:ApplicationsViewContent | Should -Match 'function Get-AppsPackageManagerAvailabilityState'
        $script:ApplicationsViewContent | Should -Match 'function Update-AppsPackageManagerBanner'
        $script:ApplicationsViewContent | Should -Match '"PackageManagers=\$packageManagerAvailabilitySignature"'
    }

    It 'routes ApplicationsView UI-state catches through Write-SwallowedException' {
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsPackageManagerBanner\.Visibility'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsPackageManagerBanner\.Text'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsSourceFilterControls\.All'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsSourceFilterControls\.WinGet'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsSourceFilterControls\.Chocolatey'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsViewModeControls\.Cards'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsViewModeControls\.List'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsCategoryTabs\.Foreground'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppsCategoryTabs\.Background'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppStatusFilterList\.SetChoiceComboStyle'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppStatusFilterList\.Foreground'''
        $script:ApplicationsViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ApplicationsView\.Update-AppStatusFilterList\.ForegroundProperty'''
    }

    It 'renders an Apps-tab banner for when both package managers are unavailable' {
        $script:GuiContent | Should -Match '<Border Name="AppsPackageManagerBanner" Visibility="Collapsed"'
        $script:GuiContent | Should -Match '<TextBlock Name="TxtAppsPackageManagerBanner" VerticalAlignment="Center" TextWrapping="Wrap"/>'
        $script:GuiContent | Should -Match 'AppsPackageManagerBanner\.Background = \$bc\.ConvertFromString\(\$Theme\.CautionBg\)'
        $script:GuiContent | Should -Match 'TxtAppsPackageManagerBanner\.Foreground = \$bc\.ConvertFromString\(\$Theme\.CautionText\)'
    }

    It 'labels a cold apps cache without implying install is blocked' {
        $script:GuiContent | Should -Match 'Installed status not scanned'
    }

    It 'returns early when the installed-app cache has not been scanned yet' {
        $script:GuiContent | Should -Match 'if \(\-not \$cacheReady\)'
        $script:GuiContent | Should -Match '\$cacheRefreshPrompt ='
        $script:GuiContent | Should -Match 'Update-AppsSelectionSummary'
        $script:GuiContent | Should -Match 'return'
    }

    It 'keeps the per-app install action available before the installed-app cache has been scanned' {
        $script:GuiContent | Should -Match '\$primaryActionKind = if \(\$isInstalled\) \{ ''Uninstall'' \} else \{ ''Install'' \}'
        $script:GuiContent | Should -Match '\$primaryActionRequiresCache = \(\$primaryActionKind -ne ''Install''\)'
        $script:GuiContent | Should -Match '\$primaryButton\.IsEnabled = \(\-not \$Script:AppsOperationInProgress\) -and \(\-not \$Script:AppsCacheRefreshInProgress\) -and \(\-not \$isAppActionBusy\) -and \(\(\-not \$primaryActionRequiresCache\) -or \$cacheReady\)'
    }
}
