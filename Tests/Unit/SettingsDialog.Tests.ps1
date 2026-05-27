Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:DialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $script:DialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $script:MenuHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers/MenuHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:BuildPrimaryTabsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildPrimaryTabs.ps1'
    $script:WindowSetupPath = Join-Path $PSScriptRoot '../../Module/GUI/WindowSetup.ps1'
    $script:EnUsLocalizationPath = Join-Path $PSScriptRoot '../../Localizations/English (United States)/en-US.json'

    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $script:DialogHelpersPath
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
    $script:SettingsDialogContent = Get-BaselineTestSourceText -Path (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')

    $script:MenuHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:MenuHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path $script:WindowSetupPath
    $script:BuildPrimaryTabsContent = Get-BaselineTestSourceText -Path $script:BuildPrimaryTabsPath
    $script:EnUsLocalizationContent = Get-BaselineTestSourceText -Path $script:EnUsLocalizationPath
}

Describe 'Settings dialog wiring' {
    It 'restores the tabbed settings dialog and searchable language picker' {
        $script:DialogHelpersContent | Should -Match 'function Show-GuiSettingsDialog'
        $script:DialogHelpersContent | Should -Match 'TabControl Name="SettingsTabs"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsGeneral"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsAppearance"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsSafety"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsApps"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsLogging"'
        $script:DialogHelpersContent | Should -Match 'Name="TabSettingsAdvanced"'
        $script:DialogHelpersContent | Should -Match 'Set-GuiTabHeaderWithIcon -Tab \$tab -IconName'
        $script:DialogHelpersContent | Should -Match "Icon = 'WindowSettings'"
        $script:DialogHelpersContent | Should -Match "Icon = 'Theme'"
        $script:DialogHelpersContent | Should -Match "Icon = 'Shield'"
        $script:DialogHelpersContent | Should -Match "Icon = 'AppsTab'"
        $script:DialogHelpersContent | Should -Match "Icon = 'OpenLog'"
        $script:DialogHelpersContent | Should -Match "Icon = 'Advanced'"
        $script:DialogHelpersContent | Should -Match 'TextElement\.Foreground="\{TemplateBinding Foreground\}"'
        $script:DialogHelpersContent | Should -Match 'Name="BtnSettingsLanguage"'
        $script:DialogHelpersContent | Should -Match 'Name="SettingsLanguagePopup"'
        $script:DialogHelpersContent | Should -Match '<Popup Name="SettingsLanguagePopup"[^>]*StaysOpen="True"'
        $script:DialogHelpersContent | Should -Match 'Name="SettingsLanguageListPanel"'
        $script:DialogHelpersContent | Should -Match 'Name="ChkDesignMode"'
        $script:DialogHelpersContent | Should -Match '\$settingsLanguageState\.Code = ''en-US'''
        $script:DialogHelpersContent | Should -Match '\$nativeBlock\.Text = \[string\]\$entry\.NativeName'
        $script:DialogHelpersContent | Should -Match '\$engBlock\.Text = \[string\]\$entry\.EnglishName'
        $script:DialogHelpersContent | Should -Match '\$langBtn\.Template = \$langTemplate'
        $script:DialogHelpersContent | Should -Match '\$searchIndex\.IndexOf\(\$normalizedFilter, \[System\.StringComparison\]::OrdinalIgnoreCase\) -ge 0'
        $script:DialogHelpersContent | Should -Match '\$txtSettingsLanguageSearch\.Add_TextChanged'
        $script:DialogHelpersContent | Should -Match '& \$languageUiState\.Render \(\[string\]\$txtSettingsLanguageSearch\.Text\)'
        $script:DialogHelpersContent | Should -Match '\$getUxLocalizedStringCapture = \$\{function:Get-UxLocalizedString\}'
        $script:DialogHelpersContent | Should -Match '& \$getUxLocalizedStringCapture -Key ''GuiLanguageSearchNoResults'''
        $script:BuildPrimaryTabsContent | Should -Match '\$Script:SetSelectedGuiLanguageScript = \$setSelectedGuiLanguageCommand'
        $script:MenuHandlersContent | Should -Match '& \$Script:SetSelectedGuiLanguageScript -langCode \$desiredLanguage'
        $script:DialogHelpersContent | Should -Not -Match '\[string\]\$textSender\.Text'
        $script:DialogHelpersContent | Should -Not -Match 'Name="CmbLanguage"'
        $script:DialogHelpersContent | Should -Not -Match '\[string\]\$_\.SearchIndex -like "\*\$normalizedFilter\*"'
    }

    It 'themes settings input controls through the shared surface tokens' {
        $script:SettingsDialogContent | Should -Match '\$surfaceControl = if \(\$theme\.InputBg\)'
        $script:SettingsDialogContent | Should -Match '\$controlBorder = if \(\$theme\.BorderStrong\)'
        $script:SettingsDialogContent | Should -Match '\$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme \$theme'
        $script:SettingsDialogContent | Should -Match '\$scrollBarStyleXaml'
        $script:SettingsDialogContent | Should -Match '<SolidColorBrush x:Key="\{x:Static SystemColors\.WindowBrushKey\}" Color="\$surfaceControl"/>'
        $script:SettingsDialogContent | Should -Match '<SolidColorBrush x:Key="\{x:Static SystemColors\.ControlTextBrushKey\}" Color="\$textPrimary"/>'
        $script:SettingsDialogContent | Should -Match '(?s)<Style TargetType="ComboBox" x:Key="SettingsCombo">.*<Setter Property="Background" Value="\$surfaceControl"/>.*<Setter Property="Foreground" Value="\$textPrimary"/>.*<Setter Property="BorderBrush" Value="\$controlBorder"/>.*<Setter Property="OverridesDefaultStyle" Value="True"/>.*<Setter Property="ItemContainerStyle" Value="\{StaticResource SettingsComboItem\}"/>.*<ControlTemplate TargetType="\{x:Type ComboBox\}">.*<ToggleButton x:Name="DropDownToggle".*IsChecked="\{Binding IsDropDownOpen, RelativeSource=\{RelativeSource TemplatedParent\}, Mode=TwoWay\}".*<Popup x:Name="Popup"'
        $script:SettingsDialogContent | Should -Match '(?s)<Style TargetType="TextBox" x:Key="SettingsTextBox">.*<Setter Property="Background" Value="\$surfaceControl"/>.*<Setter Property="Foreground" Value="\$textPrimary"/>.*<Setter Property="BorderBrush" Value="\$controlBorder"/>.*<Setter Property="CaretBrush" Value="\$textPrimary"/>.*<Trigger Property="IsEnabled" Value="False">.*<Setter Property="Opacity" Value="1"/>'
        $script:SettingsDialogContent | Should -Match 'ConvertTo-GuiBrush -Color \$surfaceControl -Context ''DialogHelpers\.ShowGuiSettingsDialog\.InputBg'''
        $script:SettingsDialogContent | Should -Match 'ConvertTo-GuiBrush -Color \$selectionSurface -Context ''DialogHelpers\.ShowGuiSettingsDialog\.Selection'''
        $script:SettingsDialogContent | Should -Match '\$control\.Resources\[\[System\.Windows\.SystemColors\]::WindowBrushKey\] = \$settingsInputBgBrush'
        $script:SettingsDialogContent | Should -Match '\$control\.Resources\[\[System\.Windows\.SystemColors\]::ControlTextBrushKey\] = \$settingsTextPrimaryBrush'
        $script:SettingsDialogContent | Should -Match '\$control\.OverridesDefaultStyle = \$true'
        $script:SettingsDialogContent | Should -Match '(?s)<Style TargetType="\{x:Type ComboBoxItem\}" x:Key="SettingsComboItem">.*TextElement\.Foreground="\{TemplateBinding Foreground\}"'
        $script:SettingsDialogContent | Should -Match '(?s)<ContentPresenter x:Name="ContentSite".*TextElement\.Foreground="\{TemplateBinding Foreground\}"'
        $script:SettingsDialogContent | Should -Not -Match 'Set-ChoiceComboStyle -Combo \$control'
        $script:SettingsDialogContent | Should -Match '& \$applySettingsComboItemTheme \$ci'
        $script:SettingsDialogContent | Should -Match 'HorizontalScrollBarVisibility="Auto"'
        $script:SettingsDialogContent | Should -Not -Match 'Background="#FFFFFF"|Foreground="#1A1C2E"|BorderBrush="#A7B0C0"|CaretBrush="#1A1C2E"|#CCE4F7|#EDF2FA'
    }

    It 'threads design mode through the settings save handler' {
        $script:SettingsDialogContent | Should -Match '\$chkDesignMode = \$dlg\.FindName\(''ChkDesignMode''\)'
        $script:SettingsDialogContent | Should -Match 'if \(\$chkDesignMode\) \{ \$chkDesignMode\.IsEnabled = \$true \}'
        $script:MenuHandlersContent | Should -Match "DesignMode = if \(Get-Command -Name 'Get-BaselineUserPreference'"
        $script:MenuHandlersContent | Should -Match 'if \(\$result.ContainsKey\(''DesignMode''\)\)'
        $script:MenuHandlersContent | Should -Match 'Set-DesignModeState -Enabled \$desiredDesignMode'
    }

    It 'shows log folder actions and gates custom log folders behind Expert mode' {
        $script:SettingsDialogContent | Should -Match 'Name="TxtLogFolderPath"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnOpenLogFolder"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnCopyLogFolderPath"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnClearOldLogs"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnLogFolderBrowse".*Visibility="Collapsed"'
        $script:SettingsDialogContent | Should -Match '\$btnLogFolderBrowse\.Visibility = if \(\$expertEnabled\)'
        $script:SettingsDialogContent | Should -Match 'LogFileDirectory = if \(\$chkAdvancedMode'
        $script:SettingsDialogContent | Should -Not -Match 'Name="TxtLogFilePath"'
    }

    It 'routes settings message dialogs through the owner-aware themed dialog helper' {
        $script:SettingsDialogContent | Should -Match '\$settingsShowThemedDialog = \{'
        $script:SettingsDialogContent | Should -Match 'GUICommon\\Show-GuiCommonThemedDialog'
        $script:SettingsDialogContent | Should -Match '\$showThemedDialog = \$settingsShowThemedDialog'
        $script:SettingsDialogContent | Should -Not -Match '(?m)(?<!GUICommon\\)Show-(?:GuiCommon)?ThemedDialog -Title'
    }

    It 'persists custom log folders and applies them to the active logger' {
        $script:MenuHandlersContent | Should -Match "Get-BaselineUserPreference -Key 'LogFileDirectory'"
        $script:MenuHandlersContent | Should -Match "Set-BaselineUserPreference -Key 'LogFileDirectory'"
        $script:MenuHandlersContent | Should -Match 'Resolve-BaselineLogDirectory -RequestedDirectory \$requestedLogDirectory'
        $script:MenuHandlersContent | Should -Match '\$global:LogFilePath = \$nextLogPath'
        $script:MenuHandlersContent | Should -Match 'Set-LogFile -Path \$global:LogFilePath'
    }

    It 'restores persisted debug mode instead of reopening settings from runtime-only state' {
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''DebugLoggingEnabled'' -Default \$runtimeDebugLoggingEnabled'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''DebugLoggingEnabled'' -Value \$debugWanted'
        $script:MenuHandlersContent | Should -Match '\$Script:DebugLoggingEnabled = \$debugWanted'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''DebugLoggingEnabled'' -Default \$false'
        $script:WindowSetupContent | Should -Match 'Set-BaselineDebugLogging -Enabled \(\[bool\]\$Script:DebugLoggingEnabled\)'
        $script:WindowSetupContent | Should -Match 'Set-GuiPerfTraceState -Enabled \(\[bool\]\$Script:DebugLoggingEnabled\)'
        $script:MenuHandlersContent | Should -Match 'Set-GuiPerfTraceState -Enabled \$debugWanted'
    }

    It 'defaults log level to All and persists the selected value' {
        $script:SettingsDialogContent | Should -Match '\$settingsLogLevelAll = Get-UxLocalizedString -Key ''GuiRiskAll'' -Fallback ''All'''
        $script:SettingsDialogContent | Should -Match '& \$addComboItem \$cmbLogLevel \$settingsLogLevelAll ''All'''
        $script:SettingsDialogContent | Should -Match '\$selectedLogLevel = if \(\$Current\.ContainsKey\(''LogLevel''\).*else \{ ''All'' \}'
        $script:SettingsDialogContent | Should -Match 'LogLevel = \[string\]\(& \$getTag \$cmbLogLevel ''All''\)'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''LogLevel'' -Default \$runtimeLogLevel'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''LogLevel'' -Value \$logLevelWanted'
        $script:WindowSetupContent | Should -Match '\$Script:LogLevel = ''All'''
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''LogLevel'' -Default ''All'''
    }

    It 'persists package source preference and reopens settings from stored state' {
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''AppsPackageSourcePreference'' -Default \$runtimeAppsPackageSourcePreference'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''AppsPackageSourcePreference'' -Value \$appsPackageSourcePreferenceWanted'
        $script:MenuHandlersContent | Should -Match '\$appsPackageSourcePreference = if \(Get-Command -Name ''Get-BaselineUserPreference'''
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''AppsPackageSourcePreference'' -Default \$Script:AppsPackageSourcePreference'
    }

    It 'persists default startup mode from Settings save' {
        $script:MenuHandlersContent | Should -Match '\$Script:DefaultStartupMode = \[string\]\$result\.DefaultStartupMode'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''DefaultStartupMode'' -Value \$Script:DefaultStartupMode'
    }

    It 'applies hide-unavailable changes to live filter state before session snapshots are saved' {
        $script:SettingsDialogContent | Should -Match 'Name="ChkHideUnavailableItems"'
        $script:MenuHandlersContent | Should -Match 'HideUnavailableItems = if \(\$null -ne \$Script:HideUnavailableItems\) \{ \[bool\]\$Script:HideUnavailableItems \}'
        $script:MenuHandlersContent | Should -Match '\$hideUnavailWanted = \[bool\]\$result\.HideUnavailableItems'
        $script:MenuHandlersContent | Should -Match 'Set-HideUnavailableItemsState -HideUnavailableItems \$hideUnavailWanted'
        $script:MenuHandlersContent | Should -Match '\$Script:HideUnavailableItems = \$hideUnavailWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''HideUnavailableItems'' -Value \$hideUnavailWanted'
        $script:MenuHandlersContent | Should -Match '\$Script:ChkHideUnavailableItems\.IsChecked = \$hideUnavailWanted'
        $script:MenuHandlersContent | Should -Match 'Update-CurrentTabContent -SkipIdlePrebuild'
    }

    It 'persists launch system scan as an opt-in user preference' {
        $script:SettingsDialogContent | Should -Match 'Name="ChkAutoScanOnLaunch"'
        $script:SettingsDialogContent | Should -Match 'Scan system state on launch'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''AutoScanOnLaunch'' -Default \$false'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''AutoScanOnLaunch'' -Value \$autoScanWanted'
        $script:WindowSetupContent | Should -Match '\$Script:AutoScanOnLaunch = \$false'
        $script:WindowSetupContent | Should -Match '\$Script:ScanEnabled = \$false'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''AutoScanOnLaunch'' -Default \$false'
    }

    It 'persists startup splash work preferences and reloads them on startup' {
        $script:SettingsDialogContent | Should -Match 'Name="ChkStartupRunInitialActions"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkStartupCheckWinGet"'
        $script:SettingsDialogContent | Should -Match 'Name="CmbStartupWinGetCheckFrequency"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkStartupCheckChocolatey"'
        $script:SettingsDialogContent | Should -Match 'Name="CmbStartupChocolateyCheckFrequency"'
        $script:SettingsDialogContent | Should -Match 'StartupRunInitialActions = if \(\$chkStartupRunInitialActions\)'
        $script:SettingsDialogContent | Should -Match 'StartupWinGetCheckFrequency = \[string\]\(& \$getTag \$cmbStartupWinGetCheckFrequency ''Startup''\)'
        $script:SettingsDialogContent | Should -Match 'StartupChocolateyCheckFrequency = \[string\]\(& \$getTag \$cmbStartupChocolateyCheckFrequency ''Startup''\)'
        $script:SettingsDialogContent | Should -Match '\$syncStartupSplashPackageManagerControls = \{'
        $script:SettingsDialogContent | Should -Not -Match '\$startupChecksEnabled = \(-not \$chkStartupRunInitialActions\)'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupRunInitialActions'' -Default \$true'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckWinGet'' -Default \$true'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupWinGetCheckFrequency'' -Default ''Startup'''
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckChocolatey'' -Default \$true'
        $script:MenuHandlersContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupChocolateyCheckFrequency'' -Default ''Startup'''
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupRunInitialActions'' -Value \$startupRunInitialActionsWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupCheckWinGet'' -Value \$startupCheckWinGetWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupWinGetCheckFrequency'' -Value \$startupWinGetCheckFrequencyWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupCheckChocolatey'' -Value \$startupCheckChocolateyWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''StartupChocolateyCheckFrequency'' -Value \$startupChocolateyCheckFrequencyWanted'
        $script:WindowSetupContent | Should -Match '\$Script:StartupRunInitialActions = \$true'
        $script:WindowSetupContent | Should -Match '\$Script:StartupWinGetCheckFrequency = ''Startup'''
        $script:WindowSetupContent | Should -Match '\$Script:StartupChocolateyCheckFrequency = ''Startup'''
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupRunInitialActions'' -Default \$true'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckWinGet'' -Default \$true'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupWinGetCheckFrequency'' -Default ''Startup'''
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupCheckChocolatey'' -Default \$true'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''StartupChocolateyCheckFrequency'' -Default ''Startup'''
    }

    It 'persists run confirmation preference and reloads it on startup' {
        $script:SettingsDialogContent | Should -Match 'Name="ChkRequireRunConfirmation"'
        $script:MenuHandlersContent | Should -Match '\$requireRunConfirmationWanted = \[bool\]\$result\.RequireRunConfirmation'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''RequireRunConfirmation'' -Value \$requireRunConfirmationWanted'
        $script:WindowSetupContent | Should -Match '\$Script:RequireRunConfirmation = \$true'
        $script:WindowSetupContent | Should -Match 'Get-BaselineUserPreference -Key ''RequireRunConfirmation'' -Default \$true'
    }

    It 'exposes update behavior controls and persists them through settings' {
        $script:SettingsDialogContent | Should -Match 'Name="ChkAutoCheckUpdates"'
        $script:SettingsDialogContent | Should -Match 'Name="CmbUpdateFrequency"'
        $script:SettingsDialogContent | Should -Match 'Name="CmbUpdateBranch"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkIncludePrereleaseUpdates"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtUpdatesAutomationHelper"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtUpdateLastCheckedValue"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtUpdateBranchValue"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtUpdateStatusValue"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtUpdateCurrentVersionValue"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnSettingsCheckNow"'
        $script:SettingsDialogContent | Should -Match 'Invoke-BaselineUpdateCheck -CurrentVersion \$currentVersionText -UpdateBranch \$updateBranch -IncludePrerelease:\$includePrerelease'
        $script:SettingsDialogContent | Should -Match 'GuiSettingsCurrentBranchLabel'
        $script:SettingsDialogContent | Should -Match "Fallback 'Update channel'"
        $script:SettingsDialogContent | Should -Match "Fallback 'Current channel'"
        $script:SettingsDialogContent | Should -Match "Fallback 'Stable'"
        $script:SettingsDialogContent | Should -Match "Fallback 'Beta'"
        $script:SettingsDialogContent | Should -Match '\$selectedUpdateBranch = \$defaultUpdateBranch'
        $script:SettingsDialogContent | Should -Match '\$getCurrentUpdateBranch = \{'
        $script:SettingsDialogContent | Should -Match 'return \[string\]\s*\(& \$getUpdateBranchSelection\)'
        $script:SettingsDialogContent | Should -Match '\$refreshUpdateAutomationControls = \{'
        $script:SettingsDialogContent | Should -Match '\$control\.IsEnabled = \$automationEnabled'
        $script:SettingsDialogContent | Should -Match 'Used when automatic update checks are enabled\.'
        $script:SettingsDialogContent | Should -Match 'Name="BtnSettingsCheckNow" Content="\$settingsCheckNowLabel" Width="120" Height="30" Margin="0,8,0,0"'
        $script:SettingsDialogContent | Should -Not -Match 'Stable - https://github\.com/sdmanson8/Baseline'
        $script:SettingsDialogContent | Should -Not -Match 'Beta - https://github\.com/sdmanson8/Baseline'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''AutoCheckUpdates'' -Value \$autoCheckUpdatesWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''UpdateCheckFrequency'' -Value \$updateCheckFrequencyWanted'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''UpdateBranch'' -Value \$updateBranchWanted'
        $script:MenuHandlersContent | Should -Match "Fallback 'Change Update Channel'"
        $script:MenuHandlersContent | Should -Match 'Switch update channel from \{0\} to \{1\}\?'
        $script:MenuHandlersContent | Should -Match 'Switching channels may change which releases Baseline offers in future update checks\.'
        $script:MenuHandlersContent | Should -Match "Fallback 'Continue'"
        $script:MenuHandlersContent | Should -Match "Fallback 'Switch On Next Release'"
        $script:MenuHandlersContent | Should -Match '\$branchCancelLabel = Get-UxLocalizedString -Key ''GuiCancelButton'''
        $script:MenuHandlersContent | Should -Match '-Buttons @\(\$branchCancelLabel, \$branchNextReleaseLabel, \$branchChangeNowLabel\)'
        $script:MenuHandlersContent | Should -Match '\$previousUpdateBranch = if \(\$currentPrefs\.ContainsKey\(''UpdateBranch''\)'
        $script:MenuHandlersContent | Should -Match '\$runUpdateBranchCheckNow = \[string\]::Equals'
        $script:MenuHandlersContent | Should -Match '\$deferUpdateBranchSwitch = \[string\]::Equals'
        $script:MenuHandlersContent | Should -Match '-not \(\$runUpdateBranchCheckNow -or \$deferUpdateBranchSwitch\)'
        $script:MenuHandlersContent | Should -Match '& \$updateCheckCommand'
        $script:MenuHandlersContent | Should -Match 'Set-BaselineUserPreference -Key ''IncludePrereleaseUpdates'' -Value \$includePrereleaseWanted'
        $script:WindowSetupContent | Should -Match '\$Script:AutoCheckUpdates = \$true'
        $script:WindowSetupContent | Should -Match '\$Script:UpdateCheckFrequency = ''Startup'''
        $script:WindowSetupContent | Should -Match 'Get-BaselineDefaultUpdateBranch'
    }

    It 'adds Advanced storage and cache controls with safe clear defaults' {
        $script:SettingsDialogContent | Should -Match 'Name="TxtStorageUsage"'
        $script:SettingsDialogContent | Should -Match 'Name="TxtStorageLocation"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnRefreshStorageUsage"'
        $script:SettingsDialogContent | Should -Match 'Name="BtnClearCache"'
        $script:SettingsDialogContent | Should -Match 'function Show-GuiClearCacheDialog'
        $script:SettingsDialogContent | Should -Match 'Name="ChkTemporaryCacheFiles" Content="\$temporaryCacheFilesLabelXaml" IsChecked="True"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkWorkingFiles" Content="\$workingFilesLabelXaml" IsChecked="True"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkLogs" Content="\$logsLabelXaml" IsChecked="False"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkAuditHistory" Content="\$auditHistoryLabelXaml" IsChecked="False"'
        $script:SettingsDialogContent | Should -Match 'Name="ChkSavedSessionState" Content="\$savedSessionStateLabelXaml" IsChecked="False"'
        $script:SettingsDialogContent | Should -Match 'Set-ButtonChrome -Button \$btnClearCache -Variant ''Secondary'''
        $script:SettingsDialogContent | Should -Match '\$applyButtonChrome = \$\{function:Set-ButtonChrome\}'
        $script:SettingsDialogContent | Should -Match '& \$applyButtonChrome -Button \$btnClearSelected -Variant ''Danger'''
        $script:SettingsDialogContent | Should -Match '& \$applyButtonChrome -Button \$btnClearSelected -Variant ''Primary'''
        $script:SettingsDialogContent | Should -Match '\$removeGuiWorkingCache = \{'
        $script:SettingsDialogContent | Should -Match '\$Script:GuiExtractedRoot'
        $script:SettingsDialogContent | Should -Match '\$getGuiBaselineTempStorageRoot = \{'
        $script:SettingsDialogContent | Should -Match '& \$removeGuiWorkingCache -Root \$tempRoot'
        $script:SettingsDialogContent | Should -Match 'GuiSettingsStorageUsageAppData'
        $script:SettingsDialogContent | Should -Match 'GuiSettingsStorageUsageTemp'
        $script:SettingsDialogContent | Should -Match 'GuiSettingsStorageUsageTotal'
        $script:SettingsDialogContent | Should -Not -Match 'Backups / restore points'
    }

    It 'routes visible settings dialog copy through en-US localization keys' {
        foreach ($key in @(
            'GuiSettingsGeneralSection',
            'GuiSettingsLanguageLabel',
            'GuiSettingsAutoScanOnLaunchLabel',
            'GuiSettingsStartupSplashSection',
            'GuiSettingsStartupSplashSubtitle',
            'GuiSettingsStartupRunInitialActionsLabel',
            'GuiSettingsStartupCheckWinGetLabel',
            'GuiSettingsStartupWinGetCheckFrequencyLabel',
            'GuiSettingsStartupCheckChocolateyLabel',
            'GuiSettingsStartupChocolateyCheckFrequencyLabel',
            'GuiSettingsStartupSplashHelper',
            'GuiSettingsHideUnavailableLabel',
            'GuiSettingsUpdatesSection',
            'GuiSettingsAutoCheckUpdatesLabel',
            'GuiSettingsUpdateFrequencyLabel',
            'GuiSettingsUpdateBranchLabel',
            'GuiSettingsCurrentBranchLabel',
            'GuiSettingsOptionUpdateBranchStable',
            'GuiSettingsOptionUpdateBranchBeta',
            'GuiSettingsIncludePrereleaseLabel',
            'GuiSettingsLastCheckedLabel',
            'GuiSettingsCurrentVersionLabel',
            'GuiSettingsUpdateStatusLabel',
            'GuiSettingsCheckNowLabel',
            'GuiSettingsUpdatesAutomationHelper',
            'GuiSettingsUiDensityLabel',
            'GuiSettingsPackageSourceLabel',
            'GuiSettingsLoggingEnabledLabel',
            'GuiSettingsOpenLogFolderLabel',
            'GuiSettingsClearOldLogsLabel',
            'GuiSettingsAdvancedModeLabel',
            'GuiSettingsDesignModeLabel',
            'GuiSettingsStorageCacheSection',
            'GuiSettingsStorageUsageHeader',
            'GuiSettingsStorageUsageAppData',
            'GuiSettingsStorageUsageTemp',
            'GuiSettingsStorageUsageTotal',
            'GuiSettingsStorageLocationHeader',
            'GuiSettingsStorageRefreshLabel',
            'GuiSettingsClearCacheLabel',
            'GuiSettingsClearCacheDialogTitle',
            'GuiSettingsClearCacheTemporaryFilesLabel',
            'GuiSettingsClearCacheWorkingFilesLabel',
            'GuiSettingsClearCacheLogsLabel',
            'GuiSettingsClearCacheAuditHistoryLabel',
            'GuiSettingsClearCacheSavedSessionLabel',
            'GuiSettingsClearCacheSavedSessionDescription',
            'GuiSettingsClearSelectedLabel'
        )) {
            $script:SettingsDialogContent | Should -Match "Get-UxLocalizedString -Key '$key'"
            $script:EnUsLocalizationContent | Should -Match "`"$key`":"
        }

        $script:SettingsDialogContent | Should -Not -Match 'Text="General preferences"'
        $script:SettingsDialogContent | Should -Not -Match 'Content="Scan system state on launch"'
        $script:SettingsDialogContent | Should -Not -Match 'Content="Open Log Folder"'
    }
}
