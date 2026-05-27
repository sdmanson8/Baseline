Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $script:SessionStateContent = Get-BaselineTestSourceText -Path $filePath
    $restorePreferencePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState/Restore-GuiSettingsSnapshot/RestorePreferenceSettings.ps1'
    $script:RestorePreferenceContent = Get-BaselineTestSourceText -Path $restorePreferencePath
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            if ($fn.Name -in @(
            'Resolve-GuiModePreference',
            'Enter-GuiSelectionBulkUpdate',
            'Test-GuiSelectionBulkUpdateInProgress',
            'Exit-GuiSelectionBulkUpdate',
            'Get-GuiFirstRunWelcomeMarkerPath',
            'Test-GuiFirstRunWelcomePending',
            'Complete-GuiFirstRunWelcome',
            'Copy-GuiRecommendationPanelCollapseState',
            'Get-GuiSettingsSnapshot'
        )) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    function Test-GuiObjectField {
        param(
            [object]$Object,
            [string]$FieldName
        )

        return ($null -ne $Object -and $Object.PSObject.Properties[$FieldName])
    }

    function Convert-JsonManifestValue {
        param([object]$Value)
        return $Value
    }

    function Copy-GuiExplicitSelectionDefinition {
        param(
            [object]$Definition,
            [string]$FunctionName,
            [string]$Source = $null
        )

        if (-not $Definition) { return $null }
        $copy = [ordered]@{}
        foreach ($property in $Definition.PSObject.Properties) {
            $copy[$property.Name] = $property.Value
        }
        if (-not [string]::IsNullOrWhiteSpace($FunctionName)) {
            $copy['Function'] = $FunctionName
        }
        if (-not [string]::IsNullOrWhiteSpace($Source)) {
            $copy['Source'] = $Source
        }
        return [pscustomobject]$copy
    }
}

Describe 'Resolve-GuiModePreference' {
    It 'keeps Safe Mode active when Safe Mode is requested' {
        $result = Resolve-GuiModePreference -SafeMode $true -AdvancedMode $false

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }

    It 'keeps Expert Mode active when Expert Mode is requested' {
        $result = Resolve-GuiModePreference -SafeMode $false -AdvancedMode $true

        $result.SafeMode | Should -Be $false
        $result.AdvancedMode | Should -Be $true
    }

    It 'prefers Safe Mode when an old snapshot tries to restore both modes off' {
        $result = Resolve-GuiModePreference -SafeMode $false -AdvancedMode $false

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }

    It 'lets Safe Mode win if both flags are somehow true' {
        $result = Resolve-GuiModePreference -SafeMode $true -AdvancedMode $true

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }
}

Describe 'First-run welcome state' {
    BeforeEach {
        $script:TestGuiSettingsProfileDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-welcome-tests-{0}" -f ([guid]::NewGuid().ToString('N')))

        <#
            .SYNOPSIS
        #>

        function Get-BaselineGuiSettingsProfileDirectory {
            param ([string]$AppName = 'Baseline')
            return $script:TestGuiSettingsProfileDirectory
        }

        <#
            .SYNOPSIS
        #>
        function LogWarning {
            param ([string]$Message)
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestGuiSettingsProfileDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineGuiSettingsProfileDirectory -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'treats a missing welcome marker as pending' {
        Test-GuiFirstRunWelcomePending | Should -Be $true
    }

    It 'marks the welcome as completed after the first successful display' {
        $markerPath = Get-GuiFirstRunWelcomeMarkerPath

        Complete-GuiFirstRunWelcome | Should -Be $true
        (Test-Path -LiteralPath $markerPath) | Should -Be $true
        Test-GuiFirstRunWelcomePending | Should -Be $false
    }
}

Describe 'GUI session snapshots' {
    BeforeEach {
        $script:CurrentThemeName = 'Dark'
        $script:ThemePreference = $null
        $script:ChkTheme = $null
        $script:PrimaryTabs = $null
        $script:SelectedLanguage = $null
        $script:CurrentPrimaryTab = $null
        $script:SearchResultsTabTag = '__SearchResults'
        $script:SearchText = ''
        $script:AppsSearchText = ''
        $script:FilterOptionsPanel = $null
        $script:AppsFilterOptionsPanel = $null
        $script:UIDensity = 'Compact'
        $script:AuditRetentionDays = 90
        $script:AppsPackageSourcePreference = 'auto'
        $script:AppsSourceFilter = 'All'
        $script:PinnedBaselineVersion = $null
        $script:AppsQueuedActions = [System.Collections.Generic.Dictionary[string,string]]::new()
        $script:ExplicitPresetSelections = @()
        $script:ExplicitPresetSelectionDefinitions = [ordered]@{}
        $script:TweakManifest = @()
        $script:Controls = @()
        $script:AdvancedMode = $false
        $script:SafeMode = $false
        $script:GameMode = $false
        $script:GameModeProfile = $null
        $script:GameModeCorePlan = @()
        $script:GameModePlan = @()
        $script:GameModeDecisionOverrides = $null
        $script:GameModeAdvancedSelections = $null
        $script:DesignMode = $true
        $script:AppsModeActive = $false
        $script:GamingModeActive = $false
        $script:UpdatesModeActive = $false
        $script:DeploymentMediaModeActive = $false
        $script:AutoScanOnLaunch = $true
        $script:RestoreLastSession = $false
        $script:AutoCheckUpdates = $false
        $script:UpdateCheckFrequency = 'Weekly'
        $script:UpdateBranch = 'Beta'
        $script:IncludePrereleaseUpdates = $true
        $script:RequireRunConfirmation = $false
        $script:PreviewBeforeRunDefault = $true
        $script:AppsAutoUpdate = $true
        $script:AppsSilentInstall = $false
        $script:LoggingEnabled = $false
        $script:DebugLoggingEnabled = $true
        $script:LogLevel = 'Debug'
        $script:RiskFilter = 'All'
        $script:CategoryFilter = 'All'
        $script:PlatformFilter = 'ThisDevice'
        $script:AppsCategoryFilter = 'All'
        $script:AppsStatusFilter = 'All'
        $script:SelectedOnlyFilter = $false
        $script:HideUnavailableItems = $true
        $script:HighRiskOnlyFilter = $false
        $script:RestorableOnlyFilter = $false
        $script:GamingOnlyFilter = $false
        $script:LastStandardPrimaryTab = $null
        $script:GameModePreviousPrimaryTab = $null
        $script:ActivePresetName = $null
        $script:ActiveScenarioNames = @{}
        $script:RecommendedSelectionsCollapsedByScope = @{}
        $script:Ctx = @{
            Mode = @{
                Safe = $script:SafeMode
                Expert = $script:AdvancedMode
                Game = $script:GameMode
                Design = $script:DesignMode
            }
            UI = @{}
        }
    }

    It 'captures GUI preference fields in the GUI snapshot' {
        $script:SearchText = 'powershell'
        $script:AppsSearchText = 'chrome'
        $script:FilterOptionsPanel = [pscustomobject]@{ Visibility = 'Visible' }
        $script:AppsFilterOptionsPanel = [pscustomobject]@{ Visibility = 'Collapsed' }

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.SchemaVersion | Should -Be 20
        $snapshot.SearchText | Should -Be 'powershell'
        $snapshot.AppsSearchText | Should -Be 'chrome'
        $snapshot.FilterPanelExpanded | Should -Be $true
        $snapshot.AppsFilterPanelExpanded | Should -Be $false
        $snapshot.NavigationMode | Should -Be 'Optimize'
        $snapshot.UIDensity | Should -Be 'Compact'
        $snapshot.AutoScanOnLaunch | Should -Be $true
        $snapshot.RestoreLastSession | Should -Be $false
        $snapshot.DefaultStartupMode | Should -Be 'Safe'
        $snapshot.AutoCheckUpdates | Should -Be $false
        $snapshot.UpdateCheckFrequency | Should -Be 'Weekly'
        $snapshot.UpdateBranch | Should -Be 'Beta'
        $snapshot.IncludePrereleaseUpdates | Should -Be $true
        $snapshot.RequireRunConfirmation | Should -Be $false
        $snapshot.PreviewBeforeRunDefault | Should -Be $true
        $snapshot.AppsAutoUpdate | Should -Be $true
        $snapshot.AppsSilentInstall | Should -Be $false
        $snapshot.LoggingEnabled | Should -Be $false
        $snapshot.DebugLoggingEnabled | Should -Be $true
        $snapshot.LogLevel | Should -Be 'Debug'
        $snapshot.DesignMode | Should -Be $true
        $snapshot.HideUnavailableItems | Should -Be $true
    }

    It 'captures active preset and scenario identity in the GUI snapshot' {
        $script:ActivePresetName = 'Balanced'
        $script:ActiveScenarioNames = @{ Gaming = $true }

        $presetSnapshot = Get-GuiSettingsSnapshot

        $presetSnapshot.ActivePresetName | Should -Be 'Balanced'
        @($presetSnapshot.ActiveScenarioNames) | Should -HaveCount 1
        $presetSnapshot.ActiveScenarioNames[0] | Should -Be 'Gaming'

        $script:ActivePresetName = $null
        $script:ActiveScenarioNames = @{
            Gaming = $true
            Streaming = $false
            Laptop = $true
        }

        $scenarioSnapshot = Get-GuiSettingsSnapshot

        $scenarioSnapshot.ActivePresetName | Should -BeNullOrEmpty
        @($scenarioSnapshot.ActiveScenarioNames) | Should -Be @('Gaming', 'Laptop')
    }

    It 'captures recommendation panel collapse state in the GUI snapshot' {
        $script:RecommendedSelectionsCollapsedByScope = @{
            RecommendedSelections = $true
            GamingProfiles = $false
        }

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.RecommendationPanelCollapseState['RecommendedSelections'] | Should -BeTrue
        $snapshot.RecommendationPanelCollapseState['GamingProfiles'] | Should -BeFalse
    }

    It 'captures the active top-level navigation mode in the GUI snapshot' {
        $script:AppsModeActive = $true

        $appsSnapshot = Get-GuiSettingsSnapshot

        $appsSnapshot.NavigationMode | Should -Be 'Apps'

        $script:AppsModeActive = $false
        $script:GamingModeActive = $true

        $gamingSnapshot = Get-GuiSettingsSnapshot

        $gamingSnapshot.NavigationMode | Should -Be 'Gaming'

        $script:GamingModeActive = $false
        $script:UpdatesModeActive = $true

        $updatesSnapshot = Get-GuiSettingsSnapshot

        $updatesSnapshot.NavigationMode | Should -Be 'Updates'

        $script:UpdatesModeActive = $false
        $script:DeploymentMediaModeActive = $true

        $deploymentMediaSnapshot = Get-GuiSettingsSnapshot

        $deploymentMediaSnapshot.NavigationMode | Should -Be 'DeploymentMedia'
    }

    It 'captures Expert Mode from the canonical GUI mode context' {
        $script:SafeMode = $true
        $script:AdvancedMode = $false
        $script:Ctx.Mode.Safe = $false
        $script:Ctx.Mode.Expert = $true

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.SafeMode | Should -Be $false
        $snapshot.AdvancedMode | Should -Be $true
    }

    It 'does not persist disabled already-set display checks as pending selections' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'AlreadySetToggle'
                Type = 'Toggle'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{
                IsChecked = $true
                IsEnabled = $false
            }
        )

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.Controls[0].IsChecked | Should -BeFalse
    }

    It 'persists disabled selected controls when an explicit selection definition owns the state' {
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'ExplicitToggle'
                Type = 'Toggle'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{
                IsChecked = $true
                IsEnabled = $false
            }
        )
        $script:ExplicitPresetSelectionDefinitions['ExplicitToggle'] = [pscustomobject]@{
            Function = 'ExplicitToggle'
            Type = 'Toggle'
            State = 'On'
            Source = 'Preset'
        }

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.Controls[0].IsChecked | Should -BeTrue
        @($snapshot.ExplicitSelectionDefinitions).Count | Should -Be 1
        $snapshot.ExplicitSelectionDefinitions[0].Function | Should -Be 'ExplicitToggle'
    }

    It 'records checked inline search result controls as session selection definitions' {
        $script:SearchText = 'defender'
        $script:CurrentPrimaryTab = $script:SearchResultsTabTag
        $script:LastStandardPrimaryTab = 'Privacy'
        $script:PrimaryTabs = [pscustomobject]@{
            SelectedItem = [pscustomobject]@{ Tag = 'System' }
        }
        $script:TweakManifest = @(
            [pscustomobject]@{
                Function = 'SearchToggle'
                Type = 'Toggle'
            }
        )
        $script:Controls = @(
            [pscustomobject]@{
                IsChecked = $true
                IsEnabled = $true
            }
        )

        $snapshot = Get-GuiSettingsSnapshot

        $snapshot.CurrentPrimaryTab | Should -Be $script:SearchResultsTabTag
        $snapshot.LastStandardPrimaryTab | Should -Be 'Privacy'
        @($snapshot.ExplicitSelectionDefinitions).Count | Should -Be 1
        $snapshot.ExplicitSelectionDefinitions[0].Function | Should -Be 'SearchToggle'
        $snapshot.ExplicitSelectionDefinitions[0].Type | Should -Be 'Toggle'
        $snapshot.ExplicitSelectionDefinitions[0].State | Should -Be 'On'
        $snapshot.ExplicitSelectionDefinitions[0].Source | Should -Be 'Session'
    }
}

Describe 'GUI session restore mode wiring' {
    It 'restores Safe or Expert through Set-GuiMode instead of only script flags' {
        $script:SessionStateContent | Should -Match '\$desiredViewMode = if \(\$desiredSafe\) \{ ''Safe'' \} elseif \(\$desiredAdvanced\) \{ ''Expert'' \} else \{ ''Standard'' \}'
        $script:SessionStateContent | Should -Match 'Set-GuiMode -ViewMode \$desiredViewMode -GameMode \$desiredGameMode'
        $script:SessionStateContent | Should -Match '\$Script:DefaultStartupMode = \$desiredDefaultStartupMode'
    }

    It 'round-trips explicit default startup mode through session restore' {
        $script:SessionStateContent | Should -Match 'DefaultStartupMode = \$currentDefaultStartupMode'
        $script:SessionStateContent | Should -Match '\$desiredDefaultStartupMode = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''DefaultStartupMode''\)'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''DefaultStartupMode'' -Default ''Safe'''
    }

    It 'round-trips active preset and scenario identity through session restore' {
        $script:SessionStateContent | Should -Match 'ActivePresetName = \$currentActivePresetName'
        $script:SessionStateContent | Should -Match 'ActiveScenarioNames = @\(\$currentActiveScenarioNames\)'
        $script:SessionStateContent | Should -Match 'RecommendationPanelCollapseState = Convert-JsonManifestValue \$currentRecommendationPanelCollapseState'
        $script:SessionStateContent | Should -Match 'function Copy-GuiRecommendationPanelCollapseState'
        $script:SessionStateContent | Should -Match '\$desiredRecommendationPanelCollapseState = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''RecommendationPanelCollapseState''\)\)'
        $script:SessionStateContent | Should -Match '\$Script:ActivePresetName = \$desiredActivePresetName'
        $script:SessionStateContent | Should -Match '\$Script:ActiveScenarioNames = @\{\}'
        $script:SessionStateContent | Should -Match '\$Script:RecommendedSelectionsCollapsedByScope = Copy-GuiRecommendationPanelCollapseState -State \$desiredRecommendationPanelCollapseState'
        $script:SessionStateContent | Should -Match 'Sync-ActivePresetButtonChrome'
    }

    It 'round-trips filter panel expanded state through session restore' {
        $script:SessionStateContent | Should -Match 'FilterPanelExpanded = \[bool\]\$currentFilterPanelExpanded'
        $script:SessionStateContent | Should -Match 'AppsFilterPanelExpanded = \[bool\]\$currentAppsFilterPanelExpanded'
        $script:SessionStateContent | Should -Match '\$desiredFilterPanelExpanded = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''FilterPanelExpanded''\)\)'
        $script:SessionStateContent | Should -Match '\$desiredAppsFilterPanelExpanded = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''AppsFilterPanelExpanded''\)\)'
        $script:SessionStateContent | Should -Match "Get-GuiFunctionCapture -Name 'Set-GuiFilterPanelExpandedState'"
        $script:SessionStateContent | Should -Match 'SetGuiFilterPanelExpandedStateScript -Scope ''Optimize'' -Expanded \(\[bool\]\(\$desiredFilterPanelExpanded -and -not \$desiredSafe\)\)'
        $script:SessionStateContent | Should -Match 'SetGuiFilterPanelExpandedStateScript -Scope ''Apps'' -Expanded \(\[bool\]\$desiredAppsFilterPanelExpanded\)'
    }

    It 'persists restored theme and explicit startup mode preferences' {
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''Theme'' -Value \$desiredTheme'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''DefaultStartupMode'' -Value \$Script:DefaultStartupMode'
    }

    It 'round-trips update behavior settings through session restore' {
        $script:SessionStateContent | Should -Match 'AutoCheckUpdates = if \(\$null -ne \$Script:AutoCheckUpdates\)'
        $script:SessionStateContent | Should -Match 'UpdateCheckFrequency = if \(\$Script:UpdateCheckFrequency\)'
        $script:SessionStateContent | Should -Match 'UpdateBranch = if \(\$Script:UpdateBranch\)'
        $script:SessionStateContent | Should -Match 'IncludePrereleaseUpdates = if \(\$null -ne \$Script:IncludePrereleaseUpdates\)'
        $script:SessionStateContent | Should -Match '\[switch\]\s*\$PreserveDurablePreferences'
        $script:SessionStateContent | Should -Match '\$preserveDurablePreferences = \[bool\]\$PreserveDurablePreferences'
        $script:SessionStateContent | Should -Match '\$desiredAutoCheckUpdates = if \(\$preserveDurablePreferences -and \$hasUserPreferenceReader\)'
        $script:SessionStateContent | Should -Match 'elseif \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''AutoCheckUpdates''\)\)'
        $script:SessionStateContent | Should -Match '\$desiredUpdateCheckFrequency = if \(\$preserveDurablePreferences -and \$hasUserPreferenceReader\)'
        $script:SessionStateContent | Should -Match 'elseif \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''UpdateCheckFrequency''\)'
        $script:SessionStateContent | Should -Match '\$desiredUpdateBranch = if \(\$preserveDurablePreferences -and \$hasUserPreferenceReader\)'
        $script:SessionStateContent | Should -Match 'elseif \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''UpdateBranch''\)'
        $script:SessionStateContent | Should -Match '\$desiredIncludePrereleaseUpdates = if \(\$preserveDurablePreferences -and \$hasUserPreferenceReader\)'
        $script:SessionStateContent | Should -Match 'elseif \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''IncludePrereleaseUpdates''\)\)'
        $script:SessionStateContent | Should -Match '\$Script:AutoCheckUpdates = \$desiredAutoCheckUpdates'
        $script:SessionStateContent | Should -Match '\$Script:UpdateCheckFrequency = \$desiredUpdateCheckFrequency'
        $script:SessionStateContent | Should -Match '\$Script:UpdateBranch = \$desiredUpdateBranch'
        $script:SessionStateContent | Should -Match '\$Script:IncludePrereleaseUpdates = \$desiredIncludePrereleaseUpdates'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''AutoCheckUpdates'' -Value \$desiredAutoCheckUpdates'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''UpdateCheckFrequency'' -Value \$desiredUpdateCheckFrequency'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''UpdateBranch'' -Value \$desiredUpdateBranch'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''IncludePrereleaseUpdates'' -Value \$desiredIncludePrereleaseUpdates'
        $script:RestorePreferenceContent | Should -Match 'if \(\$hasSnapshotUpdateSettings -and -not \$preserveDurablePreferences\)'
    }

    It 'uses persistent startup splash preferences with session snapshot defaults' {
        $script:SessionStateContent | Should -Match 'StartupRunInitialActions = if \(Get-Variable -Name ''StartupRunInitialActions'' -Scope Script -ErrorAction SilentlyContinue\)'
        $script:SessionStateContent | Should -Match 'StartupCheckWinGet = if \(Get-Variable -Name ''StartupCheckWinGet'' -Scope Script -ErrorAction SilentlyContinue\)'
        $script:SessionStateContent | Should -Match 'StartupWinGetCheckFrequency = if \(Get-Variable -Name ''StartupWinGetCheckFrequency'' -Scope Script -ErrorAction SilentlyContinue\)'
        $script:SessionStateContent | Should -Match 'StartupCheckChocolatey = if \(Get-Variable -Name ''StartupCheckChocolatey'' -Scope Script -ErrorAction SilentlyContinue\)'
        $script:SessionStateContent | Should -Match 'StartupChocolateyCheckFrequency = if \(Get-Variable -Name ''StartupChocolateyCheckFrequency'' -Scope Script -ErrorAction SilentlyContinue\)'
        $script:SessionStateContent | Should -Match '\$snapshotStartupRunInitialActions = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''StartupRunInitialActions''\)\)'
        $script:SessionStateContent | Should -Match '\$snapshotStartupCheckWinGet = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''StartupCheckWinGet''\)\)'
        $script:SessionStateContent | Should -Match '\$snapshotStartupWinGetCheckFrequency = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''StartupWinGetCheckFrequency''\)'
        $script:SessionStateContent | Should -Match '\$snapshotStartupCheckChocolatey = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''StartupCheckChocolatey''\)\)'
        $script:SessionStateContent | Should -Match '\$snapshotStartupChocolateyCheckFrequency = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''StartupChocolateyCheckFrequency''\)'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupRunInitialActions'' -Default \$snapshotStartupRunInitialActions'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckWinGet'' -Default \$snapshotStartupCheckWinGet'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupWinGetCheckFrequency'' -Default \$snapshotStartupWinGetCheckFrequency'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckChocolatey'' -Default \$snapshotStartupCheckChocolatey'
        $script:SessionStateContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupChocolateyCheckFrequency'' -Default \$snapshotStartupChocolateyCheckFrequency'
        $script:SessionStateContent | Should -Match '\$Script:StartupRunInitialActions = \$desiredStartupRunInitialActions'
        $script:SessionStateContent | Should -Match '\$Script:StartupCheckWinGet = \$desiredStartupCheckWinGet'
        $script:SessionStateContent | Should -Match '\$Script:StartupWinGetCheckFrequency = \$desiredStartupWinGetCheckFrequency'
        $script:SessionStateContent | Should -Match '\$Script:StartupCheckChocolatey = \$desiredStartupCheckChocolatey'
        $script:SessionStateContent | Should -Match '\$Script:StartupChocolateyCheckFrequency = \$desiredStartupChocolateyCheckFrequency'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupRunInitialActions'' -Value \$desiredStartupRunInitialActions'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupCheckWinGet'' -Value \$desiredStartupCheckWinGet'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupWinGetCheckFrequency'' -Value \$desiredStartupWinGetCheckFrequency'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupCheckChocolatey'' -Value \$desiredStartupCheckChocolatey'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupChocolateyCheckFrequency'' -Value \$desiredStartupChocolateyCheckFrequency'
    }

    It 'restores Expert Mode banner visibility from the restored mode' {
        $script:SessionStateContent | Should -Match '\$ExpertModeBanner\.Visibility = if \(\$desiredAdvanced\)'
    }

    It 'restores saved search state during session restore while events are suppressed' {
        $script:SessionStateContent | Should -Match '\$desiredSearch = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''SearchText''\)\)'
        $script:SessionStateContent | Should -Match '\$desiredAppsSearch = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''AppsSearchText''\)\)'
        $script:SessionStateContent | Should -Match '\$Script:SearchUiUpdating = \$true'
        $script:SessionStateContent | Should -Match "Get-Command -Name 'Sync-GuiSearchInputChrome'"
        $script:SessionStateContent | Should -Match 'Sync-GuiSearchInputChrome'
    }

    It 'replays explicit selection state after restored mode and filter preferences are in place' {
        $preferenceRestoreIndex = $script:SessionStateContent.IndexOf("RestorePreferenceSettings.ps1")
        $selectionRestoreIndex = $script:SessionStateContent.IndexOf("RestoreExplicitSelectionState.ps1")

        $preferenceRestoreIndex | Should -BeGreaterThan -1
        $selectionRestoreIndex | Should -BeGreaterThan -1
        $selectionRestoreIndex | Should -BeGreaterThan $preferenceRestoreIndex
    }

    It 'replays explicit selection state inside a bulk selection update' {
        $script:SessionStateContent | Should -Match '\$selectionBulkPreviousState = Enter-GuiSelectionBulkUpdate'
        $script:SessionStateContent | Should -Match "RestoreExplicitSelectionState.ps1"
        $script:SessionStateContent | Should -Match 'Exit-GuiSelectionBulkUpdate -PreviousState \$selectionBulkPreviousState'
    }

    It 'flushes deferred game mode sync when the outer bulk selection update exits' {
        $script:GuiSelectionBulkUpdateInProgress = $false
        $script:GameModePlanSyncPending = $true
        $script:GameModeSyncCount = 0

        function Sync-GameModePlanFromGamingControls {
            $script:GameModeSyncCount++
        }

        $outerState = Enter-GuiSelectionBulkUpdate
        $innerState = Enter-GuiSelectionBulkUpdate

        Exit-GuiSelectionBulkUpdate -PreviousState $innerState

        $script:GuiSelectionBulkUpdateInProgress | Should -BeTrue
        $script:GameModeSyncCount | Should -Be 0

        Exit-GuiSelectionBulkUpdate -PreviousState $outerState

        $script:GuiSelectionBulkUpdateInProgress | Should -BeFalse
        $script:GameModePlanSyncPending | Should -BeFalse
        $script:GameModeSyncCount | Should -Be 1
    }

    It 'reports whether a selection bulk update is active' {
        $script:GuiSelectionBulkUpdateInProgress = $false
        Test-GuiSelectionBulkUpdateInProgress | Should -BeFalse

        $previousState = Enter-GuiSelectionBulkUpdate
        try
        {
            Test-GuiSelectionBulkUpdateInProgress | Should -BeTrue
        }
        finally
        {
            Exit-GuiSelectionBulkUpdate -PreviousState $previousState
        }
    }

    It 'restores UI density without forcing a system scan' {
        $script:SessionStateContent | Should -Match 'UIDensity = if \(Get-Command -Name ''Get-BaselineUiDensity'''
        $script:SessionStateContent | Should -Match '\$desiredUiDensity = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''UIDensity''\)'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''UIDensity'' -Value \$desiredUiDensity'
        $script:SessionStateContent | Should -Match 'Set-TweakRowFactoryDensityTokens'
        $script:SessionStateContent | Should -Not -Match "Get-Command -Name 'Invoke-GuiSystemScan'"
        $script:SessionStateContent | Should -Not -Match 'Invoke-GuiSystemScan'
        $script:SessionStateContent | Should -Match 'Set-GuiStatusText -Text \(Get-UxLocalizedString -Key ''GuiLogSessionRestoredPreviousState'''
    }

    It 'restores HideUnavailableItems from the session snapshot instead of the default preference' {
        $script:SessionStateContent | Should -Match '\$desiredHideUnavailableItems = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''HideUnavailableItems''\)\) \{ \[bool\]\$Snapshot\.HideUnavailableItems \}'
        $script:SessionStateContent | Should -Match '\$Script:HideUnavailableItems = \$desiredHideUnavailableItems'
        $script:SessionStateContent | Should -Match '\$ChkHideUnavailableItems\.IsChecked = \$desiredHideUnavailableItems'
        $script:SessionStateContent | Should -Match 'Set-HideUnavailableItemsState -HideUnavailableItems \$desiredHideUnavailableItems'
    }

    It 'restores log level and debug logging from the session snapshot' {
        $script:SessionStateContent | Should -Match 'DebugLoggingEnabled = if \(\$null -ne \$Script:DebugLoggingEnabled\)'
        $script:SessionStateContent | Should -Match 'LogLevel = if \(\$Script:LogLevel\)'
        $script:SessionStateContent | Should -Match '\$desiredDebugLoggingEnabled = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''DebugLoggingEnabled''\)\)'
        $script:SessionStateContent | Should -Match '\$desiredLogLevel = if \(\(Test-GuiObjectField -Object \$Snapshot -FieldName ''LogLevel''\)'
        $script:SessionStateContent | Should -Match '\$Script:DebugLoggingEnabled = \$desiredDebugLoggingEnabled'
        $script:SessionStateContent | Should -Match '\$Script:LogLevel = \$desiredLogLevel'
        $script:SessionStateContent | Should -Match 'Set-BaselineUserPreference -Key ''LogLevel'' -Value \$desiredLogLevel'
    }
}
