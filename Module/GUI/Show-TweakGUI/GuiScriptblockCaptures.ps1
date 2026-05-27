# Purpose: late handler captures, initial theme, and action icon wiring.
$Script:ClearTabContentCacheScript = ${function:Clear-TabContentCache}
	$Script:BuildTabContentScript = ${function:Build-TabContent}
	$Script:UpdateCurrentTabContentScript = ${function:Update-CurrentTabContent}
	$Script:UpdatePrimaryTabVisualsScript = ${function:Update-PrimaryTabVisuals}
	$Script:SaveGuiUndoSnapshotScript = ${function:Save-GuiUndoSnapshot}
	$Script:GetPrimaryTabItemScript = ${function:Get-PrimaryTabItem}
	$Script:ClearGameModePlanScript = ${function:Clear-GameModePlan}
	$Script:SetGameModeProfileScript = ${function:Set-GameModeProfile}
	$Script:ResetGameModeStateScript = ${function:Reset-GameModeState}
	$Script:BuildGameModePlanScript = ${function:Build-GameModePlan}
	$Script:BuildGameModeAdvancedPlanEntriesScript = ${function:Build-GameModeAdvancedPlanEntries}
	$Script:GetGameModeProfileDefaultSelectionScript = (Get-Item function:Get-GameModeProfileDefaultSelection -ErrorAction Stop).ScriptBlock
	$Script:GetGamingPreviewGroupSortOrderScript = (Get-Item function:Get-GamingPreviewGroupSortOrder -ErrorAction Stop).ScriptBlock
	$Script:NewGameModeComparisonPanelScript = ${function:New-GameModeComparisonPanel}
	$Script:SyncGameModeContextStateScript = ${function:Sync-GameModeContextState}
	$Script:SyncGameModePlanToGamingControlsScript = ${function:Sync-GameModePlanToGamingControls}
	$Script:UpdateGameModeStatusTextScript = ${function:Update-GameModeStatusText}
	$Script:SetButtonChromeScript = ${function:Set-GuiButtonChrome}
	$Script:ShowThemedDialogScript = ${function:Show-ThemedDialog}
	$Script:ShowSelectedTweakPreviewScript = ${function:Show-SelectedTweakPreview}
	$Script:GetUxRunActionLabelScript = ${function:Get-UxRunActionLabel}
	$Script:UpdateRunPathContextLabelScript = ${function:Update-RunPathContextLabel}
	$Script:InvokeGuiStateTransitionScript = ${function:Invoke-GuiStateTransition}
	$Script:SyncUxActionButtonTextScript = ${function:Sync-UxActionButtonText}
	$Script:ClearInvisibleSelectionStateScript = ${function:Clear-InvisibleSelectionState}
	$Script:UpdateHeaderModeStateTextScript = ${function:Update-HeaderModeStateText}
	$invokeGuiSystemScanOnLaunchScript = ${function:Invoke-GuiSystemScan}

	# Apply initial theme from the saved preference. First launch defaults to
	# System, which resolves to the current Windows app theme.
	$initialThemePreference = 'System'
	try
	{
		if (Get-Command -Name 'Get-BaselineStartupThemePreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$initialThemePreference = Get-BaselineStartupThemePreference
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\Show-TweakGUI\GuiScriptblockCaptures.ps1:40' -Severity Debug }

		$null = $_
	}
	Apply-BaselineThemePreference -Preference $initialThemePreference -SkipContentRebuild
	Set-StaticButtonStyle
	& $traceGuiStartup 'Initial theme applied'

	# Wire icon content for primary action buttons
	if ($Script:BtnPreviewRun) { Set-GuiButtonIconContent -Button $Script:BtnPreviewRun -IconName 'PreviewRun'      -Text (Get-UxPreviewButtonLabel) -ToolTip (Get-UxPreviewButtonToolTip) }
	if ($Script:BtnRun)        { Set-GuiButtonIconContent -Button $Script:BtnRun        -IconName 'RunTweaks'       -Text (Get-UxRunActionLabel) -ToolTip (Get-UxRunActionToolTip) }
if ($Script:BtnDefaults)   { Set-GuiButtonIconContent -Button $Script:BtnDefaults   -IconName 'RestoreDefaults' -Text (Get-UxLocalizedString -Key 'GuiBtnRestoreAllTweaksRecorded' -Fallback 'Restore all tweaks to default values') -ToolTip (Get-UxLocalizedString -Key 'GuiActionRestoreDefaultsTooltipRecorded' -Fallback 'Restore supported settings to recorded default values.') }
	if ($BtnLog)        { Set-GuiButtonIconContent -Button $BtnLog        -IconName 'OpenLog'         -Text (Get-UxLocalizedString -Key 'GuiBtnLog' -Fallback 'Open Log') -ToolTip (Get-UxLocalizedString -Key 'GuiActionLogTooltip' -Fallback 'Open the detailed execution log.') }
	if ($Script:BtnStartHere)  { Set-GuiButtonIconContent -Button $Script:BtnStartHere  -IconName 'QuickStart'     -Text (Get-UxStartGuideButtonLabel) -ToolTip (Get-UxLocalizedString -Key 'GuiActionStartGuideTooltip' -Fallback 'Open the getting started guide.') }
	if ($Script:BtnHelp)       { Set-GuiButtonIconContent -Button $Script:BtnHelp       -IconName 'Help'           -Text (Get-UxHelpButtonLabel) -ToolTip (Get-UxLocalizedString -Key 'GuiActionOpenHelpTooltip' -Fallback 'Open help and usage guidance.') }
	if ($BtnLanguage)   { Set-GuiButtonIconContent -Button $BtnLanguage   -IconName 'Language'       -Text (Get-UxLocalizedString -Key 'GuiBtnLanguage' -Fallback 'Language') -ToolTip (Get-UxLocalizedString -Key 'GuiBtnLanguageTooltip' -Fallback 'Change language') -IconSize 14 -Gap 6 -TextFontSize 11 }
	if ($Script:BtnClearSearch) { Set-GuiButtonIconContent -Button $Script:BtnClearSearch -IconName 'Clear'         -Text (Get-UxLocalizedString -Key 'GuiBtnClearSearch' -Fallback 'Clear') -ToolTip (Get-UxLocalizedString -Key 'GuiActionClearSearchTooltip' -Fallback 'Clear search text and active filters.') -IconSize 14 -Gap 6 -TextFontSize 11 }
	if ($Script:BtnApplyQueuedActions) { Set-GuiButtonIconContent -Button $Script:BtnApplyQueuedActions -IconName 'RunTweaks' -Text (Get-UxLocalizedString -Key 'GuiAppsApplyQueued' -Fallback 'Apply Changes') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsApplyQueuedTip' -Fallback 'Apply queued install and uninstall changes.') -IconSize 14 -Gap 6 -TextFontSize 11 }
	if ($Script:BtnClearQueuedActions) { Set-GuiButtonIconContent -Button $Script:BtnClearQueuedActions -IconName 'Clear' -Text (Get-UxLocalizedString -Key 'GuiAppsReset' -Fallback 'Reset') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsResetTip' -Fallback 'Clear all queued changes and checked applications.') -IconSize 14 -Gap 6 -TextFontSize 11 }
	if ($Script:BtnScanInstalledApps) { Set-GuiButtonIconContent -Button $Script:BtnScanInstalledApps -IconName 'Search' -Text (Get-UxLocalizedString -Key 'GuiAppsScanInstalledApps' -Fallback 'Scan Installed Apps') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsScanInstalledAppsTip' -Fallback 'Scan installed apps to update install status.') -IconSize 14 -Gap 6 -TextFontSize 11 }
	& $traceGuiStartup 'Primary action icons wired'


