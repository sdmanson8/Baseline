
	#region System scan state
	$buildTabContentCommand = Get-GuiRuntimeCommand -Name 'Build-TabContent' -CommandType 'Function'
	$hasField = {
		param (
			[object]$Object,
			[string]$FieldName
		)

		if ($null -eq $Object)
		{
			return $false
		}

		if ($Object -is [System.Collections.IDictionary])
		{
			return $Object.Contains($FieldName)
		}

		return ($null -ne $Object.PSObject.Properties[$FieldName])
	}.GetNewClosure()
	Register-GuiEventHandler -Source $ChkScan -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:ScanEnabled = $false
		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			if ($sctl -and (& $hasField -Object $sctl -FieldName 'IsEnabled')) { $sctl.IsEnabled = $true }
		}
		& $setGuiStatusTextCommand -Text '' -Tone 'muted'
		if ($Script:CurrentPrimaryTab) { & $buildTabContentCommand -PrimaryTab $Script:CurrentPrimaryTab }
	}) | Out-Null
	#endregion

	# Style buttons directly
	$bc = [System.Windows.Media.BrushConverter]::new()

	<#
	    .SYNOPSIS
	#>

	function Sync-UxActionButtonText
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if ($Script:AppsModeActive -or $Script:DeploymentMediaModeActive)
		{
			if ($Script:BtnRun) { $Script:BtnRun.Visibility = [System.Windows.Visibility]::Collapsed }
			if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.Visibility = [System.Windows.Visibility]::Collapsed }
			if ($Script:BtnDefaults) { $Script:BtnDefaults.Visibility = [System.Windows.Visibility]::Collapsed }
			if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = if ($Script:DeploymentMediaModeActive) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }
			if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = if ($Script:DeploymentMediaModeActive) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed } }
			return
		}

		$updatesModeActive = [bool]$Script:UpdatesModeActive

		if ($Script:BtnDeploymentMediaPreviewPlan) { $Script:BtnDeploymentMediaPreviewPlan.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($Script:BtnDeploymentMediaStartBuild) { $Script:BtnDeploymentMediaStartBuild.Visibility = [System.Windows.Visibility]::Collapsed }

		if ($Script:BtnRun)
		{
			$Script:BtnRun.Visibility = [System.Windows.Visibility]::Visible
		}
		if ($Script:BtnRun -and -not (& $Script:TestGuiRunInProgressScript))
		{
			Set-GuiButtonIconContent -Button $Script:BtnRun -IconName 'RunTweaks' -Text (Get-UxRunActionLabel) -ToolTip (Get-UxRunActionToolTip)
		}

		if ($Script:BtnRestoreSnapshot)
		{
			$Script:BtnRestoreSnapshot.Content = Get-UxUndoSelectionActionLabel
			$Script:BtnRestoreSnapshot.ToolTip = if (Test-IsSafeModeUX) {
				Get-UxLocalizedString -Key 'GuiActionUndoSelectionTooltipSafe' -Fallback 'Undo the last preset or imported selection change by restoring the previous GUI snapshot.'
			}
			else {
				Get-UxLocalizedString -Key 'GuiActionUndoSelectionTooltip' -Fallback 'Restore the last captured UI snapshot before an import or preset change.'
			}
		}

		if ($Script:BtnPreviewRun)
		{
			$Script:BtnPreviewRun.Visibility = [System.Windows.Visibility]::Visible
			Set-GuiButtonIconContent -Button $Script:BtnPreviewRun -IconName 'PreviewRun' -Text (Get-UxPreviewButtonLabel) -ToolTip (Get-UxPreviewButtonToolTip)
		}

		if ($Script:BtnStartHere)
		{
			Set-GuiButtonIconContent -Button $Script:BtnStartHere -IconName 'QuickStart' -Text (Get-UxStartGuideButtonLabel) -ToolTip (Get-UxLocalizedString -Key 'GuiActionStartGuideTooltip' -Fallback 'Open the getting started guide.')
		}

		if ($Script:BtnHelp)
		{
			Set-GuiButtonIconContent -Button $Script:BtnHelp -IconName 'Help' -Text (Get-UxHelpButtonLabel) -ToolTip (Get-UxLocalizedString -Key 'GuiActionOpenHelpTooltip' -Fallback 'Open help and usage guidance.')
		}

		if ($Script:BtnDefaults)
		{
			$Script:BtnDefaults.Visibility = if ($updatesModeActive) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
		}

		Update-RunPathContextLabel
	}

	<#
	    .SYNOPSIS
	#>

	function Update-RunPathContextLabel
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $Script:RunPathContextLabel) { return }

		$pathContext = Get-UxRunPathContext
		$labelText = switch ($pathContext.Path)
		{
			'Preset'          { "Preset: $($pathContext.Label)" }
			'Troubleshooting' { 'Troubleshooting' }
			'GameMode'        { $pathContext.Label }
			default           { $pathContext.Label }
		}

		$Script:RunPathContextLabel.Text = $labelText
		$Script:RunPathContextLabel.Visibility = [System.Windows.Visibility]::Visible

		if ($Script:SharedBrushConverter)
		{
			$toneColor = Get-GuiStatusToneColor -Tone $pathContext.Tone
			if ($toneColor)
			{
				try
				{
					$Script:RunPathContextLabel.Foreground = $Script:SharedBrushConverter.ConvertFromString([string]$toneColor)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.UpdateRunPathContextLabel.Foreground'
					}
				}
			}
		}
	}

	# Settings profile buttons live alongside the defaults action so users can
	# export, import, and roll back the current GUI state.
	$secondaryActionGroup = New-Object System.Windows.Controls.Border
	$secondaryActionGroup.Margin = [System.Windows.Thickness]::new(4, 8, 4, 0)
	$secondaryActionGroup.Padding = [System.Windows.Thickness]::new(6, 4, 6, 4)
	$secondaryActionGroup.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$secondaryActionGroup.BorderThickness = [System.Windows.Thickness]::new(1)
	$secondaryActionGroup.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
	$secondaryActionGroup.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
	$secondaryActionBar = New-Object System.Windows.Controls.WrapPanel
	$secondaryActionBar.Orientation = 'Horizontal'
	$secondaryActionGroup.Child = $secondaryActionBar
	$Script:SecondaryActionGroupBorder = $secondaryActionGroup
	$setSecondaryActionGroupMaxWidth = {
		if (-not $ActionButtonBar -or -not $secondaryActionGroup) { return }
		$availableWidth = [double]$ActionButtonBar.ActualWidth
		if ($availableWidth -gt 0)
		{
			$secondaryActionGroup.MaxWidth = [Math]::Max(0, $availableWidth - 12)
		}
	}.GetNewClosure()
	& $setSecondaryActionGroupMaxWidth
	Register-GuiEventHandler -Source $ActionButtonBar -EventName 'SizeChanged' -Handler ({
		& $setSecondaryActionGroupMaxWidth
	}.GetNewClosure()) | Out-Null
	[void]($ActionButtonBar.Children.Add($secondaryActionGroup))
	$BtnExportSettings = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterExportSettings' -Fallback 'Export Settings') -Variant 'Subtle' -Compact -Muted
	$BtnExportSettings.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportSettings.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportSettingsTooltip' -Fallback 'Export the current GUI selections to a JSON profile.')
	[void]($secondaryActionBar.Children.Add($BtnExportSettings))
	$Script:BtnExportSettings = $BtnExportSettings
	$BtnImportSettings = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterImportSettings' -Fallback 'Import Settings') -Variant 'Subtle' -Compact -Muted
	$BtnImportSettings.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnImportSettings.ToolTip = (Get-UxLocalizedString -Key 'GuiActionImportSettingsTooltip' -Fallback 'Import a saved JSON profile and restore the selected GUI state.')
	[void]($secondaryActionBar.Children.Add($BtnImportSettings))
	$Script:BtnImportSettings = $BtnImportSettings
	$BtnRestoreSnapshot = New-PresetButton -Label (Get-UxUndoSelectionActionLabel) -Variant 'Secondary' -Compact
	$BtnRestoreSnapshot.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnRestoreSnapshot.ToolTip = (Get-UxLocalizedString -Key 'GuiActionUndoSelectionTooltip' -Fallback 'Restore the last captured UI snapshot before an import or preset change.')
	[void]($secondaryActionBar.Children.Add($BtnRestoreSnapshot))
	$Script:BtnRestoreSnapshot = $BtnRestoreSnapshot
	$exportGuiSettingsProfileCommand = Get-GuiRuntimeCommand -Name 'Export-GuiSettingsProfile' -CommandType 'Function'
	$importGuiSettingsProfileCommand = Get-GuiRuntimeCommand -Name 'Import-GuiSettingsProfile' -CommandType 'Function'
	$restoreGuiSnapshotCommand = Get-GuiRuntimeCommand -Name 'Restore-GuiSnapshot' -CommandType 'Function'
	$setGuiStatusTextCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	$testIsSafeModeUxCommand = Get-GuiRuntimeCommand -Name 'Test-IsSafeModeUX' -CommandType 'Function'
	$getUxUndoSelectionActionLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxUndoSelectionActionLabel' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportSettings -EventName 'Click' -Handler ({
		$null = & $exportGuiSettingsProfileCommand
	}) | Out-Null

	Register-GuiEventHandler -Source $BtnImportSettings -EventName 'Click' -Handler ({
		$null = & $importGuiSettingsProfileCommand
	}) | Out-Null

	Register-GuiEventHandler -Source $BtnRestoreSnapshot -EventName 'Click' -Handler ({
		try
		{
			if (-not (& $restoreGuiSnapshotCommand))
			{
				[void](Show-ThemedDialog -Title (& $getUxUndoSelectionActionLabelCommand) -Message $(if (& $testIsSafeModeUxCommand) { & $getUxLocalizedStringCapture -Key 'GuiActionUndoNoSnapshotSafe' -Fallback 'No preset or imported selection change is available to undo yet.' } else { & $getUxLocalizedStringCapture -Key 'GuiActionUndoNoSnapshot' -Fallback 'No previous GUI snapshot has been captured yet.' }) -Buttons @('OK') -AccentButton 'OK')
				return
			}
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to restore GUI snapshot')
			[void](Show-ThemedDialog -Title (& $getUxUndoSelectionActionLabelCommand) -Message $(if (& $testIsSafeModeUxCommand) { (& $getUxLocalizedStringCapture -Key 'GuiActionUndoFailedSafe' -Fallback "Failed to undo the previous selection change.`n`n{0}") -f $_.Exception.Message } else { (& $getUxLocalizedStringCapture -Key 'GuiActionUndoFailed' -Fallback "Failed to restore the previous snapshot.`n`n{0}") -f $_.Exception.Message }) -Buttons @('OK') -AccentButton 'OK')
			return
		}

		& $setGuiStatusTextCommand -Text $(if (& $testIsSafeModeUxCommand) { & $getUxLocalizedStringCapture -Key 'GuiActionUndoSuccessSafe' -Fallback 'Last selection change undone.' } else { & $getUxLocalizedStringCapture -Key 'GuiActionUndoSuccess' -Fallback 'Previous GUI snapshot restored.' }) -Tone 'accent'
		LogInfo $(if (& $testIsSafeModeUxCommand) { (Get-UxBilingualLocalizedString -Key 'GuiLogUndoSnapshotSafe' -Fallback 'Undid previous GUI selection change via snapshot restore.') } else { (Get-UxBilingualLocalizedString -Key 'GuiLogUndoSnapshot' -Fallback 'Restored previous GUI snapshot') })
	}) | Out-Null

	# Capture file-dialog function for use inside .GetNewClosure() handlers
	# (.GetNewClosure() captures variables but not functions from the parent scope).
	$showGuiFileSaveDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileSaveDialog' -CommandType 'Function'

	# Export System State button
	$BtnExportSystemState = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterExportSystemState' -Fallback 'Export System State') -Variant 'Subtle' -Compact -Muted
	$BtnExportSystemState.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportSystemState.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportStateTooltip' -Fallback 'Capture a snapshot of current system settings and save to a JSON file.')
	[void]($secondaryActionBar.Children.Add($BtnExportSystemState))
	$Script:BtnExportSystemState = $BtnExportSystemState
	$exportSystemStateSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportSystemState -EventName 'Click' -Handler ({
		try
		{
			& $exportSystemStateSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionExportStateCapturing' -Fallback 'Capturing system state snapshot...') -Tone 'accent'
			$snapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest
			$defaultFileName = 'Baseline-SystemState-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
			$savePath = & $showGuiFileSaveDialogCommand -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportStateDialogTitle' -Fallback 'Export System State Snapshot') `
				-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
				-DefaultExtension 'json' `
				-FileName $defaultFileName
			if ([string]::IsNullOrWhiteSpace($savePath))
			{
				& $exportSystemStateSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionExportStateCancelled' -Fallback 'System state export cancelled.') -Tone 'accent'
				return
			}
			Export-SystemStateSnapshot -Snapshot $snapshot -Path $savePath
			& $exportSystemStateSetStatusCommand -Text ((& $getUxLocalizedStringCapture -Key 'GuiActionExportStateSuccess' -Fallback 'System state exported: {0} entries saved to {1}') -f $snapshot.Entries.Count, $savePath) -Tone 'success'
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExportSystemStateSuccess' -Fallback 'Exported system state snapshot: {0} entries to {1}' -FormatArgs @($snapshot.Entries.Count, $savePath))
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export system state')
			[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportStateTitle' -Fallback 'Export System State') -Message ((& $getUxLocalizedStringCapture -Key 'GuiActionExportStateFailed' -Fallback "Failed to export system state.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}) | Out-Null

	# Export Configuration Profile button
	$BtnExportConfigProfile = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterExportConfigProfile' -Fallback 'Export Config Profile') -Variant 'Subtle' -Compact -Muted
	$BtnExportConfigProfile.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportConfigProfile.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportProfileTooltip' -Fallback 'Export current tweak selections and queued app changes as a portable configuration profile.')
	[void]($secondaryActionBar.Children.Add($BtnExportConfigProfile))
	$Script:BtnExportConfigProfile = $BtnExportConfigProfile
	$exportConfigProfileGetRunListCommand = Get-GuiRuntimeCommand -Name 'Get-ActiveTweakRunList' -CommandType 'Function'
	$exportConfigProfileSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportConfigProfile -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		try
		{
			$tweakList = & $exportConfigProfileGetRunListCommand
			$queuedAppActions = if ($getQueuedAppsProfileActionsCommand) { @(& $getQueuedAppsProfileActionsCommand) } else { @() }
			$tweakCount = @($tweakList).Count
			$appActionCount = @($queuedAppActions).Count
			if ($tweakCount -eq 0 -and $appActionCount -eq 0)
			{
				Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileTitle' -Fallback 'Export Configuration Profile') `
					-Message (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileNoTweaks' -Fallback 'Select at least one tweak or queue at least one app action before exporting a configuration profile.') `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			$baselineVersion = $null
			try { $baselineVersion = Get-BaselineDisplayVersion } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ExportConfigProfile.GetDisplayVersion' }
			if ([string]::IsNullOrWhiteSpace($baselineVersion)) { $baselineVersion = 'unknown' }

			# Snapshot user-added external software entries so the profile is
			# portable: importing on another machine can restore the catalog
			# definitions, not just selection state.
			$userAppSnapshot = @()
			if (Get-Command -Name 'Get-BaselineUserAppEntries' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try
				{
					$userAppResult = Get-BaselineUserAppEntries
					if ($userAppResult -and $userAppResult.PSObject.Properties['Entries'])
					{
						$userAppSnapshot = @($userAppResult.Entries)
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ExportConfigProfile.UserApps'
					}
					$userAppSnapshot = @()
				}
			}
			$userAppCount = @($userAppSnapshot).Count

			$includePaths = @()
			$includePathCmd = Get-Command -Name 'Get-HeadlessPresetIncludedTweakLibraryPathSet' -CommandType Function -ErrorAction SilentlyContinue
			if ($includePathCmd)
			{
				$includePaths = @(& $includePathCmd)
			}

			$profile = New-ConfigurationProfile `
				-Name ('Baseline-Profile-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) `
				-Selections @($tweakList) `
				-AppActions @($queuedAppActions) `
				-UserApps @($userAppSnapshot) `
				-IncludePaths $includePaths `
				-BaselineVersion $baselineVersion `
				-AppsPackageSourcePreference $Script:AppsPackageSourcePreference

			$defaultFileName = 'Baseline-ConfigProfile-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
			$savePath = & $showGuiFileSaveDialogCommand -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileTitle' -Fallback 'Export Configuration Profile') `
				-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
				-DefaultExtension 'json' `
				-FileName $defaultFileName

			if ([string]::IsNullOrWhiteSpace($savePath))
			{
				& $exportConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileCancelled' -Fallback 'Configuration profile export cancelled.') -Tone 'accent'
				return
			}

			Export-ConfigurationProfile -Profile $profile -FilePath $savePath
			if ($tweakCount -gt 0 -and $appActionCount -gt 0)
			{
				& $exportConfigProfileSetStatusCommand -Text ("Configuration profile exported: {0} tweak(s) and {1} app action(s) saved to {2}" -f $tweakCount, $appActionCount, $savePath) -Tone 'success'
				LogInfo ("Exported configuration profile: {0} tweak(s) and {1} app action(s) to {2}" -f $tweakCount, $appActionCount, $savePath)
			}
			elseif ($tweakCount -gt 0)
			{
				& $exportConfigProfileSetStatusCommand -Text ("Configuration profile exported: {0} tweak(s) saved to {1}" -f $tweakCount, $savePath) -Tone 'success'
				LogInfo ("Exported configuration profile: {0} tweak(s) to {1}" -f $tweakCount, $savePath)
			}
			else
			{
				& $exportConfigProfileSetStatusCommand -Text ("Configuration profile exported: {0} app action(s) saved to {1}" -f $appActionCount, $savePath) -Tone 'success'
				LogInfo ("Exported configuration profile: {0} app action(s) to {1}" -f $appActionCount, $savePath)
			}
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export configuration profile')
			[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileTitle' -Fallback 'Export Configuration Profile') -Message ((& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileFailed' -Fallback "Failed to export configuration profile.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure()) | Out-Null

	# Export First-Logon Command button
	$BtnExportFirstLogonCommand = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterExportFirstLogonCommand' -Fallback 'Export First-Logon Command') -Variant 'Subtle' -Compact -Muted
	$BtnExportFirstLogonCommand.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportFirstLogonCommand.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportFirstLogonTooltip' -Fallback 'Export an autounattend FirstLogonCommands XML snippet that runs Baseline with a saved configuration profile.')
	[void]($secondaryActionBar.Children.Add($BtnExportFirstLogonCommand))
	$Script:BtnExportFirstLogonCommand = $BtnExportFirstLogonCommand
	$exportFirstLogonCommandShowOpenDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileOpenDialog' -CommandType 'Function'
	$exportFirstLogonCommandShowSaveDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileSaveDialog' -CommandType 'Function'
	$exportFirstLogonCommandExportCommand = Get-GuiRuntimeCommand -Name 'Export-BaselineFirstLogonCommandSnippet' -CommandType 'Function'
	$exportFirstLogonCommandSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportFirstLogonCommand -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		try
		{
			$configPath = & $exportFirstLogonCommandShowOpenDialogCommand -Title 'Select Configuration Profile' -Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' -InitialDirectory (Get-GuiSettingsProfileDirectory -AppName 'Baseline')
			if ([string]::IsNullOrWhiteSpace([string]$configPath))
			{
				& $exportFirstLogonCommandSetStatusCommand -Text 'First-logon command export cancelled.' -Tone 'accent'
				return
			}

			$configPath = [System.IO.Path]::GetFullPath([string]$configPath)
			if (-not (Test-Path -LiteralPath $configPath -PathType Leaf))
			{
				throw "Configuration profile not found: $configPath"
			}

			$configStem = [System.IO.Path]::GetFileNameWithoutExtension($configPath)
			if ([string]::IsNullOrWhiteSpace([string]$configStem))
			{
				$configStem = 'Baseline-ConfigProfile'
			}

			$savePath = & $exportFirstLogonCommandShowSaveDialogCommand -Title 'Export First-Logon Command' -Filter 'XML Files (*.xml)|*.xml|All Files (*.*)|*.*' -DefaultExtension 'xml' -FileName ('Baseline-FirstLogonCommand-{0}.xml' -f $configStem) -InitialDirectory (Split-Path -Path $configPath -Parent)
			if ([string]::IsNullOrWhiteSpace([string]$savePath))
			{
				& $exportFirstLogonCommandSetStatusCommand -Text 'First-logon command export cancelled.' -Tone 'accent'
				return
			}

			$exportResult = & $exportFirstLogonCommandExportCommand -ConfigPath $configPath -FilePath $savePath
			& $exportFirstLogonCommandSetStatusCommand -Text ("First-logon command exported to {0}" -f $exportResult.FilePath) -Tone 'success'
			LogInfo ("Exported first-logon command snippet for {0} to {1}" -f $exportResult.ConfigPath, $exportResult.FilePath)
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export first-logon command')
			[void](Show-ThemedDialog -Title 'Export First-Logon Command' -Message ("Failed to export first-logon command.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure()) | Out-Null

	# Import Configuration Profile button - file -> review-mode dialog -> apply.
	$BtnImportConfigProfile = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterImportConfigProfile' -Fallback 'Import Config Profile') -Variant 'Subtle' -Compact -Muted
	$BtnImportConfigProfile.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnImportConfigProfile.ToolTip = (Get-UxLocalizedString -Key 'GuiActionImportProfileTooltip' -Fallback 'Load a portable configuration profile, review the per-row diff, and apply the accepted changes.')
	[void]($secondaryActionBar.Children.Add($BtnImportConfigProfile))
	$Script:BtnImportConfigProfile = $BtnImportConfigProfile
	$importConfigProfileGetRunListCommand = Get-GuiRuntimeCommand -Name 'Get-ActiveTweakRunList' -CommandType 'Function'
	$importConfigProfileSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	$importConfigProfileShowOpenDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileOpenDialog' -CommandType 'Function'
	$importConfigProfileImportCommand = Get-GuiRuntimeCommand -Name 'Import-ConfigurationProfile' -CommandType 'Function'
	$importConfigProfileNewCommand = Get-GuiRuntimeCommand -Name 'New-ConfigurationProfile' -CommandType 'Function'
	$importConfigProfileToRunListCommand = Get-GuiRuntimeCommand -Name 'ConvertFrom-BaselineConfigProfileToRunList' -CommandType 'Function'
	$importConfigProfileTestCompatCommand = Get-GuiRuntimeCommand -Name 'Test-ConfigurationProfileCompatibility' -CommandType 'Function'
	$importConfigProfilePromptForRunCommand = Get-GuiRuntimeCommand -Name 'Invoke-GuiReviewModePromptForRun' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnImportConfigProfile -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$importTitle = (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileTitle' -Fallback 'Import Configuration Profile')
		try
		{
			if (-not $importConfigProfileImportCommand -or -not $importConfigProfileToRunListCommand -or -not $importConfigProfilePromptForRunCommand)
			{
				throw 'Import-ConfigurationProfile / ConvertFrom-BaselineConfigProfileToRunList / Invoke-GuiReviewModePromptForRun not available.'
			}

			$openPath = & $importConfigProfileShowOpenDialogCommand -Title $importTitle -Filter 'Baseline Config Profile (*.json)|*.json|All Files (*.*)|*.*'
			if ([string]::IsNullOrWhiteSpace($openPath))
			{
				& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileCancelled' -Fallback 'Configuration profile import cancelled.') -Tone 'accent'
				return
			}

			$importedProfile = & $importConfigProfileImportCommand -FilePath $openPath

			if ($importConfigProfileTestCompatCommand)
			{
				$compat = & $importConfigProfileTestCompatCommand -Profile $importedProfile
				if ($compat -and -not [bool]$compat.Compatible)
				{
					$warningText = ($compat.Warnings -join "`n")
					$choice = Show-ThemedDialog -Title $importTitle -Message ((& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileIncompatible' -Fallback "This profile is not fully compatible with the current system:`n`n{0}`n`nProceed anyway?") -f $warningText) -Buttons @('OK','Cancel') -AccentButton 'OK'
					if ($choice -ne 'OK')
					{
						& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileCancelled' -Fallback 'Configuration profile import cancelled.') -Tone 'accent'
						return
					}
				}
				elseif ($compat -and @($compat.Warnings).Count -gt 0)
				{
					LogWarning ("Import-ConfigProfile compatibility warnings: {0}" -f (@($compat.Warnings) -join '; '))
				}
			}

			$baselineVersion = $null
			try { $baselineVersion = Get-BaselineDisplayVersion } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ImportConfigProfile.GetDisplayVersion' }
			if ([string]::IsNullOrWhiteSpace($baselineVersion)) { $baselineVersion = 'unknown' }

			# If the profile carries inlined custom user-app definitions, offer
			# to restore them to the local user-apps directory before walking
			# the tweak run-list. Skip silently when the profile predates
			# SchemaVersion 3 or carries an empty UserApps array.
			$profileUserApps = @()
			if ($importedProfile -and $importedProfile.PSObject.Properties['UserApps'] -and $null -ne $importedProfile.UserApps)
			{
				$profileUserApps = @($importedProfile.UserApps)
			}
			$userAppRestoreSummary = $null
			if (@($profileUserApps).Count -gt 0 -and (Get-Command -Name 'Save-BaselineUserAppEntriesFromProfile' -CommandType Function -ErrorAction SilentlyContinue))
			{
				$userAppNames = @($profileUserApps | ForEach-Object {
					if ($_ -and $_.PSObject.Properties['Name']) { [string]$_.Name } else { '<unnamed>' }
				})
				$userAppPromptMessage = (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileUserAppsPrompt' -Fallback "This profile carries {0} custom external software definition(s):`n`n{1}`n`nRestore them to your user apps directory? Existing entries with the same Name / WinGetId / ChocoId will be skipped.") -f @($profileUserApps).Count, ((@($userAppNames) | Select-Object -First 20) -join ', ')
				$userAppChoice = Show-ThemedDialog -Title $importTitle -Message $userAppPromptMessage -Buttons @('Yes','No','Cancel') -AccentButton 'Yes'
				if ($userAppChoice -eq 'Cancel')
				{
					& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileCancelled' -Fallback 'Configuration profile import cancelled.') -Tone 'accent'
					return
				}
				if ($userAppChoice -eq 'Yes')
				{
					try
					{
						$userAppRestoreSummary = Save-BaselineUserAppEntriesFromProfile -Profile $importedProfile
						$importedCount = @($userAppRestoreSummary.Imported).Count
						$skippedCount = @($userAppRestoreSummary.Skipped).Count
						$failedCount = @($userAppRestoreSummary.Failed).Count
						LogInfo ('Import config profile user-app restore: {0} imported, {1} skipped, {2} failed.' -f $importedCount, $skippedCount, $failedCount)
						if ($importedCount -gt 0 -and (Get-Command -Name 'Get-BaselineApplicationsCatalog' -CommandType Function -ErrorAction SilentlyContinue))
						{
							try { $null = Get-BaselineApplicationsCatalog -Force } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ImportConfigProfile.RefreshUserAppsCatalog' }
							$Script:AppsViewBuildSignature = $null
							if ($Script:AppsModeActive -and (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue))
							{
								Build-AppsViewCards
							}
						}
					}
					catch
					{
						LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to restore user apps from imported profile')
					}
				}
			}

			$currentTweakList = @(& $importConfigProfileGetRunListCommand)
			$currentQueuedAppActions = if ($getQueuedAppsProfileActionsCommand) { @(& $getQueuedAppsProfileActionsCommand) } else { @() }
			$currentProfile = & $importConfigProfileNewCommand `
				-Name ('Baseline-Current-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')) `
				-Selections $currentTweakList `
				-AppActions $currentQueuedAppActions `
				-BaselineVersion $baselineVersion `
				-AppsPackageSourcePreference $Script:AppsPackageSourcePreference

			$importedRunList = @(& $importConfigProfileToRunListCommand -Profile $importedProfile -Manifest $Script:TweakManifest)
			if (@($importedRunList).Count -eq 0)
			{
				# UserApps-only profile is a legitimate use case - show a
				# success message reflecting what was restored rather than
				# the generic "no matching tweaks" warning.
				if ($userAppRestoreSummary -and @($userAppRestoreSummary.Imported).Count -gt 0)
				{
					$importedCount = @($userAppRestoreSummary.Imported).Count
					& $importConfigProfileSetStatusCommand -Text (("Imported {0} custom app definition(s) from profile." -f $importedCount)) -Tone 'success'
					return
				}
				[void](Show-ThemedDialog -Title $importTitle -Message (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileEmpty' -Fallback 'The imported profile contains no entries that match this Baseline build.') -Buttons @('OK') -AccentButton 'OK')
				& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileEmptyStatus' -Fallback 'No matching tweaks in imported profile.') -Tone 'accent'
				return
			}

			$promptArgs = @{
				CurrentProfile  = $currentProfile
				ImportedProfile = $importedProfile
				TweakList       = $importedRunList
				Title           = $importTitle
				Subtitle        = (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileSubtitle' -Fallback 'Review the imported profile against current state. Accept the rows you want to apply, then click Apply.')
			}
			$filteredTweaks = @(& $importConfigProfilePromptForRunCommand @promptArgs)
			if ($null -eq $filteredTweaks -or @($filteredTweaks).Count -eq 0)
			{
				& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileCancelled' -Fallback 'Configuration profile import cancelled.') -Tone 'accent'
				LogInfo ('Import config profile cancelled or accepted nothing for {0}' -f $openPath)
				return
			}

			$warningChoice = & $confirmHighRiskTweakRunCommand -SelectedTweaks $filteredTweaks
			if (-not $warningChoice -or $warningChoice -eq 'Cancel')
			{
				& $importConfigProfileSetStatusCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileCancelled' -Fallback 'Configuration profile import cancelled.') -Tone 'accent'
				return
			}

			$runTitle = ((& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileRunTitle' -Fallback 'Apply imported configuration profile ({0})') -f ([System.IO.Path]::GetFileName($openPath)))
			LogInfo ('Applying imported config profile {0}: {1} accepted tweak(s).' -f $openPath, @($filteredTweaks).Count)
			& $startGuiExecutionRunCommand -TweakList $filteredTweaks -Mode 'Run' -ExecutionTitle $runTitle
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to import configuration profile')
			[void](Show-ThemedDialog -Title $importTitle -Message ((& $getUxLocalizedStringCapture -Key 'GuiActionImportProfileFailed' -Fallback "Failed to import configuration profile.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure()) | Out-Null

	function Get-GuiSupportBundleSessionLogChoices
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$choices = [System.Collections.Generic.List[object]]::new()
		$seen = @{}
		$rootSeen = @{}
		$logRoots = [System.Collections.Generic.List[string]]::new()
		$addChoice = {
			param (
				[string]$Path,
				[switch]$Current
			)

			if ([string]::IsNullOrWhiteSpace($Path)) { return }

			$resolvedPath = $null
			try { $resolvedPath = [System.IO.Path]::GetFullPath([string]$Path) }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.Get-GuiSupportBundleSessionLogChoices:catch600' -Severity Debug }
			 return }

			$key = $resolvedPath.ToLowerInvariant()
			if ($seen.ContainsKey($key)) { return }

			$item = Get-Item -LiteralPath $resolvedPath -ErrorAction SilentlyContinue
			if (-not $item -or $item.PSIsContainer) { return }

			$timestampText = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
			$fileName = [System.IO.Path]::GetFileName($resolvedPath)
			$displayName = if ($Current)
			{
				'Current session log - {0} - {1}' -f $timestampText, $fileName
			}
			else
			{
				'{0} - {1}' -f $timestampText, $fileName
			}

			$seen[$key] = $true
			[void]$choices.Add([pscustomobject]@{
				DisplayName   = $displayName
				Path          = $resolvedPath
				FileName      = $fileName
				LastWriteTime = $item.LastWriteTime
				IsCurrent     = [bool]$Current
			})
		}.GetNewClosure()

		$currentLogPath = $null
		$globalLogFileVariable = Get-Variable -Name 'LogFilePath' -Scope Global -ErrorAction SilentlyContinue
		if ($globalLogFileVariable -and $globalLogFileVariable.Value)
		{
			$currentLogPath = [string]$globalLogFileVariable.Value
			& $addChoice -Path $currentLogPath -Current
		}

		$addRoot = {
			param ([string]$Root)
			if ([string]::IsNullOrWhiteSpace($Root)) { return }
			try { $resolvedRoot = [System.IO.Path]::GetFullPath([string]$Root) }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.Get-GuiSupportBundleSessionLogChoices:catch641' -Severity Debug }
			 return }
			$key = $resolvedRoot.ToLowerInvariant()
			if (-not $rootSeen.ContainsKey($key))
			{
				$rootSeen[$key] = $true
				[void]$logRoots.Add($resolvedRoot)
			}
		}.GetNewClosure()

		if (-not [string]::IsNullOrWhiteSpace($currentLogPath))
		{
			$currentLogDirectory = Split-Path -Path $currentLogPath -Parent
			& $addRoot $currentLogDirectory
			if (-not [string]::IsNullOrWhiteSpace($currentLogDirectory))
			{
				$currentLogDirectoryLeaf = Split-Path -Path $currentLogDirectory -Leaf
				if ($currentLogDirectoryLeaf -match '^\d{4}-\d{2}-\d{2}$')
				{
					& $addRoot (Split-Path -Path $currentLogDirectory -Parent)
				}
			}
		}

		$defaultLogDirectory = $null
		if (Get-Command -Name 'Get-BaselineLogDirectory' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { $defaultLogDirectory = [string](Get-BaselineLogDirectory) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.Get-GuiSupportBundleSessionLogChoices:catch667' -Severity Debug }
			 $defaultLogDirectory = $null }
		}
		& $addRoot $defaultLogDirectory

		if (-not [string]::IsNullOrWhiteSpace($defaultLogDirectory) -and (Get-Command -Name 'Get-BaselineConfiguredLogDirectory' -CommandType Function -ErrorAction SilentlyContinue))
		{
			try { & $addRoot ([string](Get-BaselineConfiguredLogDirectory -DefaultDirectory $defaultLogDirectory)) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ConfiguredLogDirectory' }
		}

		foreach ($root in @($logRoots))
		{
			if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }

			$candidateDirectories = [System.Collections.Generic.List[string]]::new()
			[void]$candidateDirectories.Add($root)
			try
			{
				foreach ($childDirectory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue))
				{
					[void]$candidateDirectories.Add($childDirectory.FullName)
				}
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.EnumerateLogDirectories'
			}

			foreach ($candidateDirectory in @($candidateDirectories))
			{
				try
				{
					foreach ($logFile in @(Get-ChildItem -LiteralPath $candidateDirectory -File -Filter '*.log' -ErrorAction SilentlyContinue))
					{
						& $addChoice -Path $logFile.FullName
					}
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.EnumerateLogFiles'
				}
			}
		}

		return @($choices | Sort-Object -Property @{ Expression = 'IsCurrent'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } | Select-Object -First 60)
	}

	function Show-GuiSupportBundleSessionLogDialog
	{
		param (
			[Parameter(Mandatory = $true)]
			[object[]]$Choices
		)

		$availableChoices = @($Choices | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Path) })
		if ($availableChoices.Count -eq 0)
		{
			[void](Show-ThemedDialog -Title 'Export Support Bundle' -Message 'No Baseline session logs were found to include in the support bundle.' -Buttons @('OK') -AccentButton 'OK')
			return $null
		}

		$window = New-Object System.Windows.Window
		$window.Title = 'Export Support Bundle'
		$window.Width = 760
		$window.Height = 420
		$window.MinWidth = 560
		$window.MinHeight = 320
		$window.WindowStartupLocation = 'CenterOwner'
		$window.ResizeMode = 'CanResizeWithGrip'
		if ($Script:MainForm) { $window.Owner = $Script:MainForm }

		$layout = New-Object System.Windows.Controls.Grid
		$layout.Margin = New-Object System.Windows.Thickness 18
		foreach ($height in @('Auto', '*', 'Auto', 'Auto'))
		{
			$rowDefinition = New-Object System.Windows.Controls.RowDefinition
			if ($height -eq '*')
			{
				$rowDefinition.Height = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
			}
			else
			{
				$rowDefinition.Height = [System.Windows.GridLength]::Auto
			}
			[void]$layout.RowDefinitions.Add($rowDefinition)
		}

		$prompt = New-Object System.Windows.Controls.TextBlock
		$prompt.Text = 'Select the session log to include in the support bundle.'
		$prompt.FontSize = 15
		$prompt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$prompt.Margin = New-Object System.Windows.Thickness 0, 0, 0, 12
		[System.Windows.Controls.Grid]::SetRow($prompt, 0)
		[void]$layout.Children.Add($prompt)

		$listBox = New-Object System.Windows.Controls.ListBox
		$listBox.DisplayMemberPath = 'DisplayName'
		$listBox.ItemsSource = $availableChoices
		$listBox.SelectedIndex = 0
		$listBox.MinHeight = 180
		[System.Windows.Controls.Grid]::SetRow($listBox, 1)
		[void]$layout.Children.Add($listBox)

		$pathText = New-Object System.Windows.Controls.TextBlock
		$pathText.Margin = New-Object System.Windows.Thickness 0, 10, 0, 14
		$pathText.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$pathText.FontSize = 12
		$pathText.Opacity = 0.78
		$pathText.Text = [string]$availableChoices[0].Path
		[System.Windows.Controls.Grid]::SetRow($pathText, 2)
		[void]$layout.Children.Add($pathText)

		$buttonPanel = New-Object System.Windows.Controls.StackPanel
		$buttonPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
		$buttonPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
		[System.Windows.Controls.Grid]::SetRow($buttonPanel, 3)
		[void]$layout.Children.Add($buttonPanel)

		$cancelButton = New-Object System.Windows.Controls.Button
		$cancelButton.Content = 'Cancel'
		$cancelButton.MinWidth = 92
		$cancelButton.Margin = New-Object System.Windows.Thickness 0, 0, 8, 0
		$cancelButton.IsCancel = $true
		[void]$buttonPanel.Children.Add($cancelButton)

		$exportButton = New-Object System.Windows.Controls.Button
		$exportButton.Content = 'Continue'
		$exportButton.MinWidth = 104
		$exportButton.IsDefault = $true
		[void]$buttonPanel.Children.Add($exportButton)

		$listBox.Add_SelectionChanged({
			if ($listBox.SelectedItem)
			{
				$pathText.Text = [string]$listBox.SelectedItem.Path
			}
		}.GetNewClosure())

		$selectAndClose = {
			if ($listBox.SelectedItem)
			{
				$window.Tag = $listBox.SelectedItem
				$window.DialogResult = $true
			}
		}.GetNewClosure()
		$exportButton.Add_Click($selectAndClose)
		$listBox.Add_MouseDoubleClick($selectAndClose)

		$window.Content = $layout
		if ($window.ShowDialog() -eq $true -and $window.Tag)
		{
			return $window.Tag
		}

		return $null
	}

	function Invoke-GuiSupportBundleProgressDialogRender
	{
		param (
			[AllowNull()]
			[object]$ProgressDialog
		)

		if (-not $ProgressDialog -or -not $ProgressDialog.Window) { return }

		try
		{
			$dispatcher = $ProgressDialog.Window.Dispatcher
			if ($dispatcher)
			{
				$dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
				$dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ProgressDialogRender'
			}
		}
	}

	function Show-GuiSupportBundleProgressDialog
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$OutputPath
		)

		try
		{
			$theme = if ($Script:CurrentTheme) { $Script:CurrentTheme } else { @{} }
			$bc = if ($Script:SharedBrushConverter) { $Script:SharedBrushConverter } else { [System.Windows.Media.BrushConverter]::new() }
			$getThemeColor = {
				param(
					[string]$Name,
					[string]$Default
				)

				if ($theme -and $theme -is [System.Collections.IDictionary] -and $theme.Contains($Name) -and -not [string]::IsNullOrWhiteSpace([string]$theme[$Name]))
				{
					return [string]$theme[$Name]
				}
				if ($theme -and $theme.PSObject.Properties[$Name] -and -not [string]::IsNullOrWhiteSpace([string]$theme.$Name))
				{
					return [string]$theme.$Name
				}
				return $Default
			}.GetNewClosure()

			$title = 'Export Support Bundle'
			$outputName = [System.IO.Path]::GetFileName($OutputPath)
			$window = New-Object System.Windows.Window
			$window.Title = $title
			$window.Width = 460
			$window.SizeToContent = [System.Windows.SizeToContent]::Height
			$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
			$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
			$window.ShowInTaskbar = $false
			$window.WindowStyle = [System.Windows.WindowStyle]::None
			$window.AllowsTransparency = $true
			$window.Background = [System.Windows.Media.Brushes]::Transparent
			if ($Form) { try { $window.Owner = $Form } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ProgressDialogOwner' } }

			$rootBorder = New-Object System.Windows.Controls.Border
			$rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
			$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
			$rootBorder.Background = $bc.ConvertFromString((& $getThemeColor -Name 'WindowBg' -Default '#FFFFFF'))
			$rootBorder.BorderBrush = $bc.ConvertFromString((& $getThemeColor -Name 'BorderColor' -Default '#D8DEE8'))

			$layout = New-Object System.Windows.Controls.DockPanel
			$layout.LastChildFill = $true

			$titleBar = New-Object System.Windows.Controls.Border
			$titleBar.Background = $bc.ConvertFromString((& $getThemeColor -Name 'HeaderBg' -Default '#F7F8FA'))
			$titleBar.BorderBrush = $bc.ConvertFromString((& $getThemeColor -Name 'BorderColor' -Default '#D8DEE8'))
			$titleBar.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
			$titleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
			$titleBar.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
			$titleBlock = New-Object System.Windows.Controls.TextBlock
			$titleBlock.Text = $title
			$titleBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			$titleBlock.FontSize = 12
			$titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$titleBlock.Foreground = $bc.ConvertFromString((& $getThemeColor -Name 'TextPrimary' -Default '#111827'))
			$titleBar.Child = $titleBlock
			$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() }.GetNewClosure())
			[System.Windows.Controls.DockPanel]::SetDock($titleBar, [System.Windows.Controls.Dock]::Top)
			[void]$layout.Children.Add($titleBar)

			$content = New-Object System.Windows.Controls.StackPanel
			$content.Margin = [System.Windows.Thickness]::new(22, 18, 22, 20)
			$message = New-Object System.Windows.Controls.TextBlock
			$message.Text = 'Creating ZIP archive. Keep this window open until the export completes.'
			$message.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$message.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			$message.FontSize = 13
			$message.Foreground = $bc.ConvertFromString((& $getThemeColor -Name 'TextPrimary' -Default '#111827'))
			[void]$content.Children.Add($message)

			$statusText = New-Object System.Windows.Controls.TextBlock
			$statusText.Text = if ([string]::IsNullOrWhiteSpace($outputName)) { 'Exporting support bundle...' } else { "Exporting $outputName..." }
			$statusText.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$statusText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			$statusText.FontSize = 12
			$statusText.Foreground = $bc.ConvertFromString((& $getThemeColor -Name 'TextMuted' -Default '#6B7280'))
			$statusText.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]$content.Children.Add($statusText)

			$progressBar = New-Object System.Windows.Controls.ProgressBar
			$progressBar.Height = 14
			$progressBar.Minimum = 0
			$progressBar.Maximum = 1
			$progressBar.Value = 0
			$progressBar.IsIndeterminate = $true
			$progressBar.Foreground = $bc.ConvertFromString((& $getThemeColor -Name 'ProgressGreen' -Default '#10B981'))
			$progressBar.Background = $bc.ConvertFromString((& $getThemeColor -Name 'ProgressGreenTrack' -Default '#D1FAE5'))
			try
			{
				if (Get-Command -Name 'New-GuiExecutionProgressBarTemplate' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$progressBar.Template = New-GuiExecutionProgressBarTemplate
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ProgressBarTemplate' }
			[void]$content.Children.Add($progressBar)
			[void]$layout.Children.Add($content)
			$rootBorder.Child = $layout
			$window.Content = $rootBorder

			try { [void](Set-GuiWindowChromeTheme -Window $window -UseDarkMode ($Script:CurrentThemeName -eq 'Dark')) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ProgressWindowChrome' }
			$window.Show()

			$dialog = [pscustomobject]@{
				Window      = $window
				StatusText  = $statusText
				ProgressBar = $progressBar
			}
			Invoke-GuiSupportBundleProgressDialogRender -ProgressDialog $dialog
			return $dialog
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ShowProgressDialog'
			}
			return $null
		}
	}

	function Close-GuiSupportBundleProgressDialog
	{
		param (
			[AllowNull()]
			[object]$ProgressDialog
		)

		if (-not $ProgressDialog -or -not $ProgressDialog.Window) { return }
		try
		{
			$ProgressDialog.ProgressBar.IsIndeterminate = $false
			$ProgressDialog.ProgressBar.Value = 1
			$ProgressDialog.Window.Close()
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.CloseProgressDialog'
			}
		}
	}

	$Script:CloseGuiSupportBundleProgressDialogScript = ${function:Close-GuiSupportBundleProgressDialog}

	function Set-GuiSupportBundleProgressDialogStatus
	{
		param (
			[AllowNull()]
			[object]$ProgressDialog,

			[string]$Status,

			[switch]$Completed
		)

		if (-not $ProgressDialog -or -not $ProgressDialog.Window) { return }
		try
		{
			if ($ProgressDialog.StatusText -and -not [string]::IsNullOrWhiteSpace([string]$Status))
			{
				$ProgressDialog.StatusText.Text = [string]$Status
			}
			if ($ProgressDialog.ProgressBar -and $Completed)
			{
				$ProgressDialog.ProgressBar.IsIndeterminate = $false
				$ProgressDialog.ProgressBar.Value = 1
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.ProgressDialogStatus'
			}
		}
	}

	function Stop-GuiSupportBundleExportWorker
	{
		[CmdletBinding()]
		param (
			[string]$Reason = 'Support bundle export stopped.',

			[switch]$StopPowerShell,

			[switch]$SkipEndInvoke
		)

		$workerVariable = Get-Variable -Scope Script -Name 'SupportBundleExportWorker' -ErrorAction SilentlyContinue
		if (-not $workerVariable -or -not $workerVariable.Value)
		{
			$Script:SupportBundleExportInProgress = $false
			return
		}

		$worker = $workerVariable.Value
		$Script:SupportBundleExportWorker = $null
		$Script:SupportBundleExportInProgress = $false

		if ($worker.PSObject.Properties['Timer'] -and $worker.Timer)
		{
			try { $worker.Timer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.StopTimer' }
		}

		if ($worker.PSObject.Properties['ProgressDialog'] -and $worker.ProgressDialog)
		{
			$closeProgressDialogScript = $Script:CloseGuiSupportBundleProgressDialogScript
			if ($closeProgressDialogScript)
			{
				& $closeProgressDialogScript -ProgressDialog $worker.ProgressDialog
			}
		}

		if ($StopPowerShell -and $worker.PSObject.Properties['PowerShell'] -and $worker.PowerShell)
		{
			try
			{
				$null = $worker.PowerShell.BeginStop($null, $null)
			}
			catch
			{
				try { $worker.PowerShell.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.StopPowerShell' }
			}
		}

		if ($worker.PSObject.Properties['AsyncResult'] -and $worker.AsyncResult -and -not $worker.AsyncResult.IsCompleted)
		{
			try { [void]$worker.AsyncResult.AsyncWaitHandle.WaitOne(1000) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.WaitForStop' }
		}
		$workerStillRunning = ($worker.PSObject.Properties['AsyncResult'] -and $worker.AsyncResult -and -not $worker.AsyncResult.IsCompleted)

		if (-not $SkipEndInvoke -and $worker.PSObject.Properties['AsyncResult'] -and $worker.AsyncResult -and $worker.AsyncResult.IsCompleted -and $worker.PSObject.Properties['PowerShell'] -and $worker.PowerShell)
		{
			try { $null = $worker.PowerShell.EndInvoke($worker.AsyncResult) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.EndInvokeDuringCleanup' }
		}

		if ($worker.PSObject.Properties['MenuItem'] -and $worker.MenuItem)
		{
			$menuWasEnabled = $true
			if ($worker.PSObject.Properties['MenuWasEnabled']) { $menuWasEnabled = [bool]$worker.MenuWasEnabled }
			try { $worker.MenuItem.IsEnabled = $menuWasEnabled } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.RestoreMenuItem' }
		}

		if ($worker.PSObject.Properties['SessionStatePath'] -and -not [string]::IsNullOrWhiteSpace([string]$worker.SessionStatePath) -and (Test-Path -LiteralPath ([string]$worker.SessionStatePath)))
		{
			try { Remove-Item -LiteralPath ([string]$worker.SessionStatePath) -Force -ErrorAction SilentlyContinue }
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ExportSupportBundle.RemoveSessionStatePath' }
		}

		if ($worker.PSObject.Properties['PowerShell'] -and $worker.PowerShell)
		{
			if (-not $workerStillRunning)
			{
				try { $worker.PowerShell.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.DisposePowerShell' }
			}
		}

		if ($worker.PSObject.Properties['Runspace'] -and $worker.Runspace)
		{
			try
			{
				if ($worker.Runspace.RunspaceStateInfo -and $worker.Runspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened)
				{
					if ($StopPowerShell -and $workerStillRunning)
					{
						$worker.Runspace.CloseAsync()
					}
					else
					{
						$worker.Runspace.Close()
					}
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.CloseRunspace' }
			if (-not $workerStillRunning)
			{
				try { $worker.Runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.DisposeRunspace' }
			}
		}

		if ($StopPowerShell -and -not [string]::IsNullOrWhiteSpace($Reason) -and (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue))
		{
			LogWarning $Reason
		}
	}

	$Script:StopGuiSupportBundleExportWorkerScript = ${function:Stop-GuiSupportBundleExportWorker}

	function Start-GuiSupportBundleExportAsync
	{
		[CmdletBinding()]
		param (
			[Parameter(Mandatory = $true)]
			[string]$OutputPath,

			[Parameter(Mandatory = $true)]
			[string]$SessionStatePath,

			[Parameter(Mandatory = $true)]
			[string]$SessionLogPath,

			[AllowNull()]
			[object]$PreSnapshot,

			[AllowNull()]
			[object]$PostSnapshot,

			[Parameter()]
			[AllowEmptyCollection()]
			[object[]]$ConnectivityResults = @(),

			[AllowNull()]
			[object]$ProgressDialog,

			[AllowNull()]
			[object]$MenuItem,

			[bool]$MenuWasEnabled = $true,

			[AllowNull()]
			[object]$SetStatusTextCommand,

			[Parameter(Mandatory = $true)]
			[scriptblock]$SetProgressDialogStatus,

			[Parameter(Mandatory = $true)]
			[scriptblock]$CloseProgressDialog,

			[Parameter(Mandatory = $true)]
			[scriptblock]$ShowDialog
		)

		$moduleRoot = [string]$Script:GuiModuleBasePath
		if ([string]::IsNullOrWhiteSpace($moduleRoot))
		{
			throw 'GUI module path is unavailable.'
		}

		$sharedHelpersPath = Join-Path -Path $moduleRoot -ChildPath 'SharedHelpers.psm1'
		if (-not (Test-Path -LiteralPath $sharedHelpersPath))
		{
			throw "Shared helpers module is missing: $sharedHelpersPath"
		}

		$Script:SupportBundleExportInProgress = $true
		if ($MenuItem) { try { $MenuItem.IsEnabled = $false } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.DisableMenuItem' } }

		$syncHash = [hashtable]::Synchronized(@{
			Status = 'Preparing support bundle export...'
			OutputPath = ''
		})
		$runspace = $null
		$ps = $null
		$asyncResult = $null
		$timer = $null

		try
		{
			$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
			$runspace.ApartmentState = [System.Threading.ApartmentState]::MTA
			$runspace.Open()
			$ps = [System.Management.Automation.PowerShell]::Create()
			$ps.Runspace = $runspace

			$null = $ps.AddScript({
				param (
					[string]$SharedHelpersPath,
					[string]$ModuleRoot,
					[string]$OutputPath,
					[string]$ProfilePath,
					[string]$SessionLogPath,
					[object]$PreSnapshot,
					[object]$PostSnapshot,
					[object[]]$ConnectivityResults,
					[hashtable]$Sync
				)

				$ErrorActionPreference = 'Stop'
				$Global:GUIMode = $true
				$Sync.Status = 'Loading support bundle helpers...'
				Import-Module -Name $SharedHelpersPath -Force -Global -ErrorAction Stop

				$Sync.Status = 'Preparing support bundle diagnostics...'
				$progressCallback = {
					param(
						[string]$Stage,
						[string]$Message
					)

					if (-not [string]::IsNullOrWhiteSpace($Message))
					{
						$Sync.Status = $Message
					}
				}.GetNewClosure()
				$exportArgs = @{
					OutputPath = $OutputPath
					ProfilePath = $ProfilePath
					SessionLogPath = $SessionLogPath
					PreSnapshot = $PreSnapshot
					PostSnapshot = $PostSnapshot
					IncludeAuditLog = $true
					IncludeTestReport = $true
					ConnectivityResults = @($ConnectivityResults)
					ProgressCallback = $progressCallback
				}
				$result = Export-BaselineSupportBundle @exportArgs
				$Sync.OutputPath = [string]$result.OutputPath
				$Sync.Status = 'Support bundle export complete.'
				return $result
			}).AddArgument($sharedHelpersPath).AddArgument($moduleRoot).AddArgument($OutputPath).AddArgument($SessionStatePath).AddArgument($SessionLogPath).AddArgument($PreSnapshot).AddArgument($PostSnapshot).AddArgument(@($ConnectivityResults)).AddArgument($syncHash)

			$asyncResult = $ps.BeginInvoke()
			$timer = [System.Windows.Threading.DispatcherTimer]::new()
			$timer.Interval = [TimeSpan]::FromMilliseconds(150)
			$Script:SupportBundleExportWorker = [pscustomobject]@{
				PowerShell       = $ps
				Runspace         = $runspace
				AsyncResult      = $asyncResult
				Timer            = $timer
				ProgressDialog   = $ProgressDialog
				MenuItem         = $MenuItem
				MenuWasEnabled   = $MenuWasEnabled
				SessionStatePath = $SessionStatePath
				OutputPath        = $OutputPath
			}
			$lastStatus = ''
			$timer.Add_Tick({
				$currentStatus = [string]$syncHash.Status
				if (-not [string]::IsNullOrWhiteSpace($currentStatus) -and $currentStatus -ne $lastStatus)
				{
					$lastStatus = $currentStatus
					& $SetProgressDialogStatus -ProgressDialog $ProgressDialog -Status $currentStatus
					if ($SetStatusTextCommand)
					{
						try { & $SetStatusTextCommand -Text $currentStatus -Tone 'accent' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.StatusTextUpdate' }
					}
				}

				if (-not $asyncResult.IsCompleted)
				{
					return
				}

				$timer.Stop()
				try
				{
					$resultItems = @($ps.EndInvoke($asyncResult))
					$result = if ($resultItems.Count -gt 0) { $resultItems[0] } else { $null }
					$outputPathValue = [string]$syncHash.OutputPath
					if ([string]::IsNullOrWhiteSpace($outputPathValue) -and $result -and $result.PSObject.Properties['OutputPath'])
					{
						$outputPathValue = [string]$result.OutputPath
					}
					if ([string]::IsNullOrWhiteSpace($outputPathValue))
					{
						$outputPathValue = [string]$OutputPath
					}

					& $SetProgressDialogStatus -ProgressDialog $ProgressDialog -Status 'Support bundle export complete.' -Completed
					& $CloseProgressDialog -ProgressDialog $ProgressDialog
					if ($SetStatusTextCommand)
					{
						& $SetStatusTextCommand -Text ("Support bundle exported: {0}" -f $outputPathValue) -Tone 'success'
					}
					LogInfo ("Exported support bundle to {0} using session log {1}" -f $outputPathValue, [string]$SessionLogPath)
					[void](Invoke-UserLaunch -FilePath 'explorer.exe' -ArgumentList @('/select,"{0}"' -f $outputPathValue) -Description 'support bundle output')
				}
				catch
				{
					& $CloseProgressDialog -ProgressDialog $ProgressDialog
					if ($SetStatusTextCommand)
					{
						try { & $SetStatusTextCommand -Text ("Support bundle export failed: {0}" -f $_.Exception.Message) -Tone 'danger' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SystemScanFooterHandlers.SupportBundle.StatusTextFailure' }
					}
					LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export support bundle')
					[void](& $ShowDialog -Title 'Export Support Bundle' -Message ("Failed to export support bundle.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				}
				finally
				{
					$stopSupportBundleExportScript = $Script:StopGuiSupportBundleExportWorkerScript
					if ($stopSupportBundleExportScript)
					{
						& $stopSupportBundleExportScript -Reason 'Support bundle export completed.' -SkipEndInvoke
					}
				}
			}.GetNewClosure())
			$timer.Start()
		}
		catch
		{
			if (-not $Script:SupportBundleExportWorker -and ($ps -or $runspace -or $timer))
			{
				$Script:SupportBundleExportWorker = [pscustomobject]@{
					PowerShell       = $ps
					Runspace         = $runspace
					AsyncResult      = $asyncResult
					Timer            = $timer
					ProgressDialog   = $ProgressDialog
					MenuItem         = $MenuItem
					MenuWasEnabled   = $MenuWasEnabled
					SessionStatePath = $SessionStatePath
					OutputPath        = $OutputPath
				}
			}
			$stopSupportBundleExportScript = $Script:StopGuiSupportBundleExportWorkerScript
			if ($stopSupportBundleExportScript)
			{
				& $stopSupportBundleExportScript -Reason 'Support bundle export failed before it could start.' -StopPowerShell -SkipEndInvoke
			}
			throw
		}
	}

	$getSupportBundleSessionLogChoicesCommand = Get-GuiRuntimeCommand -Name 'Get-GuiSupportBundleSessionLogChoices' -CommandType 'Function'
	$showSupportBundleSessionLogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiSupportBundleSessionLogDialog' -CommandType 'Function'
	$showSupportBundleProgressDialogCommand = Get-GuiFunctionCapture -Name 'Show-GuiSupportBundleProgressDialog'
	$closeSupportBundleProgressDialogCommand = Get-GuiFunctionCapture -Name 'Close-GuiSupportBundleProgressDialog'
	$setSupportBundleProgressDialogStatusCommand = Get-GuiFunctionCapture -Name 'Set-GuiSupportBundleProgressDialogStatus'
	$startSupportBundleExportAsyncCommand = Get-GuiFunctionCapture -Name 'Start-GuiSupportBundleExportAsync'
	$showThemedDialogCommand = Get-GuiFunctionCapture -Name 'Show-ThemedDialog'
	if (-not $showSupportBundleProgressDialogCommand) { throw 'Show-GuiSupportBundleProgressDialog not found.' }
	if (-not $closeSupportBundleProgressDialogCommand) { throw 'Close-GuiSupportBundleProgressDialog not found.' }
	if (-not $setSupportBundleProgressDialogStatusCommand) { throw 'Set-GuiSupportBundleProgressDialogStatus not found.' }
	if (-not $startSupportBundleExportAsyncCommand) { throw 'Start-GuiSupportBundleExportAsync not found.' }
	if (-not $showThemedDialogCommand) { throw 'Show-ThemedDialog not found.' }
	if (-not (Get-Variable -Scope Script -Name 'SupportBundleExportInProgress' -ErrorAction SilentlyContinue))
	{
		$Script:SupportBundleExportInProgress = $false
	}
	if (-not (Get-Variable -Scope Script -Name 'SupportBundleExportWorker' -ErrorAction SilentlyContinue))
	{
		$Script:SupportBundleExportWorker = $null
	}

	# Export Support Bundle action
	if ($MenuToolsExportSupportBundle)
	{
		Register-GuiEventHandler -Source $MenuToolsExportSupportBundle -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			if ($Script:SupportBundleExportInProgress)
			{
				& $setGuiStatusTextCommand -Text 'Support bundle export is already running.' -Tone 'accent'
				return
			}
			try
			{
				$selectedSessionLog = & $showSupportBundleSessionLogDialogCommand -Choices @(& $getSupportBundleSessionLogChoicesCommand)
				if ($null -eq $selectedSessionLog)
				{
					& $setGuiStatusTextCommand -Text 'Support bundle export cancelled.' -Tone 'accent'
					return
				}

				$defaultFileName = 'Baseline_SupportBundle_{0}_{1}.zip' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), (Get-BaselineRunId)
				$savePath = & $showGuiFileSaveDialogCommand -Title 'Export Support Bundle' `
					-Filter 'ZIP Archives (*.zip)|*.zip|All Files (*.*)|*.*' `
					-DefaultExtension 'zip' `
					-FileName $defaultFileName
				if ([string]::IsNullOrWhiteSpace($savePath))
				{
					& $setGuiStatusTextCommand -Text 'Support bundle export cancelled.' -Tone 'accent'
					return
				}

				$progressDialog = & $showSupportBundleProgressDialogCommand -OutputPath $savePath
				& $setGuiStatusTextCommand -Text 'Preparing support bundle export...' -Tone 'accent'

				$sessionStatePath = $null
				try
				{
					$sessionSnapshot = & $getGuiSettingsSnapshotCommand
					$sessionStatePath = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineSupportBundleSession_{0}.json' -f [guid]::NewGuid().ToString('N'))
					$sessionPayload = [ordered]@{
						Schema = 'Baseline.GuiSession'
						SchemaVersion = 1
						SavedAt = (Get-Date).ToString('o')
						State = $sessionSnapshot
						SupportBundle = [ordered]@{
							SelectedSessionLogPath = [string]$selectedSessionLog.Path
							SelectedSessionLogName = [string]$selectedSessionLog.FileName
						}
					}
					($sessionPayload | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $sessionStatePath -Encoding UTF8 -Force

					$preRunSnapshot = $null
					$postRunSnapshot = $null
					try
					{
						if ($Script:RunState)
						{
							if ($Script:RunState.ContainsKey('PreRunSnapshot') -and $Script:RunState['PreRunSnapshot']) { $preRunSnapshot = $Script:RunState['PreRunSnapshot'] }
							if ($Script:RunState.ContainsKey('PostRunSnapshot') -and $Script:RunState['PostRunSnapshot']) { $postRunSnapshot = $Script:RunState['PostRunSnapshot'] }
						}

						if (($null -eq $preRunSnapshot -or $null -eq $postRunSnapshot) -and $Script:LastRunProfile)
						{
							if ($null -eq $preRunSnapshot -and (& $hasField -Object $Script:LastRunProfile -FieldName 'PreRunSnapshot')) { $preRunSnapshot = $Script:LastRunProfile.PreRunSnapshot }
							if ($null -eq $postRunSnapshot -and (& $hasField -Object $Script:LastRunProfile -FieldName 'PostRunSnapshot')) { $postRunSnapshot = $Script:LastRunProfile.PostRunSnapshot }
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1460' -Severity Debug }

						$preRunSnapshot = $null
						$postRunSnapshot = $null
					}

					$connectivityResults = @()
					try
					{
						$ctx = & $getRemoteTargetContextCommand
						if ($ctx -and (& $hasField -Object $ctx -FieldName 'LastConnectivityResults'))
						{
							$connectivityResults = @($ctx.LastConnectivityResults)
						}
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1475' -Severity Debug }
					 $connectivityResults = @() }

					$menuWasEnabled = $true
					try { $menuWasEnabled = [bool]$MenuToolsExportSupportBundle.IsEnabled } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1478' -Severity Debug }
					 $menuWasEnabled = $true }
					& $startSupportBundleExportAsyncCommand -OutputPath $savePath -SessionStatePath $sessionStatePath -SessionLogPath ([string]$selectedSessionLog.Path) -PreSnapshot $preRunSnapshot -PostSnapshot $postRunSnapshot -ConnectivityResults @($connectivityResults) -ProgressDialog $progressDialog -MenuItem $MenuToolsExportSupportBundle -MenuWasEnabled $menuWasEnabled -SetStatusTextCommand $setGuiStatusTextCommand -SetProgressDialogStatus $setSupportBundleProgressDialogStatusCommand -CloseProgressDialog $closeSupportBundleProgressDialogCommand -ShowDialog $showThemedDialogCommand
				}
				catch
				{
					& $closeSupportBundleProgressDialogCommand -ProgressDialog $progressDialog
					if (-not [string]::IsNullOrWhiteSpace($sessionStatePath) -and (Test-Path -LiteralPath $sessionStatePath))
					{
						try
						{
							Remove-Item -LiteralPath $sessionStatePath -Force -ErrorAction SilentlyContinue
						}
						catch
						{
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
							{
								Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.ExportSupportBundle.RemoveSessionStatePath'
							}
						}
					}
					throw
				}
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export support bundle')
				[void](& $showThemedDialogCommand -Title 'Export Support Bundle' -Message ("Failed to export support bundle.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	# Remote target approval action
	if ($MenuToolsApproveRemoteTargets)
	{
		Register-GuiEventHandler -Source $MenuToolsApproveRemoteTargets -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$context = $null
				try { $context = & $getRemoteTargetContextCommand } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1517' -Severity Debug }
				 $context = $null }
				if (-not $context -or -not $context.Connected -or $context.TargetComputers.Count -eq 0)
				{
					[void](Show-ThemedDialog -Title 'Approve Target List' -Message 'Connect to at least one remote computer before approving a target list.' -Buttons @('OK') -AccentButton 'OK')
					return
				}

				$targetLabel = ($context.TargetComputers -join ', ')
				if ($testRemoteTargetApprovalCommand -and (& $testRemoteTargetApprovalCommand -ComputerName @($context.TargetComputers)))
				{
					[void](Show-ThemedDialog -Title 'Approve Target List' -Message ("The current target list is already approved for this session.`n`nTargets: {0}" -f $targetLabel) -Buttons @('OK') -AccentButton 'OK')
					return
				}

				$confirm = Show-ThemedDialog -Title 'Approve Target List' -Message ("Approve this exact target list for the current session?`n`nTargets: {0}`n`nFuture remote applies must match this list exactly until disconnect." -f $targetLabel) -Buttons @('Cancel', 'Approve') -AccentButton 'Approve'
				if ($confirm -ne 'Approve') { return }

				if ($setRemoteTargetApprovalCommand)
				{
					& $setRemoteTargetApprovalCommand -ComputerName @($context.TargetComputers) -ApprovalMessage 'Remote target list approved for this session.'
				}
				& $setGuiStatusTextCommand -Text ("Approved remote targets: {0}" -f $targetLabel) -Tone 'success'
				LogInfo ("Approved remote target list: {0}" -f $targetLabel)
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to approve remote target list')
				[void](Show-ThemedDialog -Title 'Approve Target List' -Message ((& $getUxLocalizedStringCapture -Key 'GuiRemoteTargetApprovalFailed' -Fallback "Failed to approve remote target list.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	# Remote approval policy actions
	if ($MenuToolsSaveRemoteApprovalPolicy)
	{
		Register-GuiEventHandler -Source $MenuToolsSaveRemoteApprovalPolicy -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			if (-not $exportRemoteTargetApprovalPolicyCommand)
			{
				[void](Show-ThemedDialog -Title 'Save Remote Approval Policy' -Message 'Remote approval policy export is unavailable in this runtime.' -Buttons @('OK') -AccentButton 'OK')
				return
			}
			try
			{
				$null = & $exportRemoteTargetApprovalPolicyCommand
				& $setGuiStatusTextCommand -Text 'Remote approval policy saved.' -Tone 'success'
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to save remote approval policy')
				[void](Show-ThemedDialog -Title 'Save Remote Approval Policy' -Message ("Failed to save remote approval policy.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuToolsLoadRemoteApprovalPolicy)
	{
		Register-GuiEventHandler -Source $MenuToolsLoadRemoteApprovalPolicy -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			if (-not $importRemoteTargetApprovalPolicyCommand)
			{
				[void](Show-ThemedDialog -Title 'Load Remote Approval Policy' -Message 'Remote approval policy import is unavailable in this runtime.' -Buttons @('OK') -AccentButton 'OK')
				return
			}
			try
			{
				$null = & $importRemoteTargetApprovalPolicyCommand
				& $setGuiStatusTextCommand -Text 'Remote approval policy loaded.' -Tone 'success'
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to load remote approval policy')
				[void](Show-ThemedDialog -Title 'Load Remote Approval Policy' -Message ("Failed to load remote approval policy.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	if ($MenuToolsRemoteConsole)
	{
		Register-GuiEventHandler -Source $MenuToolsRemoteConsole -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$null = & $showGuiRemoteConsoleDialogCommand
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to open remote console')
				[void](Show-ThemedDialog -Title 'Remote Console' -Message ("Failed to open remote console.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	if ($MenuToolsOperatorConsole)
	{
		Register-GuiEventHandler -Source $MenuToolsOperatorConsole -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$null = & $showGuiOperatorConsoleDialogCommand
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to open operator console')
				[void](Show-ThemedDialog -Title 'Operator Console' -Message ("Failed to open operator console.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	if ($MenuToolsRemovalPersistence)
	{
		Register-GuiEventHandler -Source $MenuToolsRemovalPersistence -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$removalPersistenceDialogCommand = $showGuiRemovalPersistenceDialogCommand
				if (-not $removalPersistenceDialogCommand)
				{
					$removalPersistenceDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiRemovalPersistenceDialog' -CommandType 'Function'
				}
				if (-not $removalPersistenceDialogCommand)
				{
					throw 'Removal Persistence dialog command is not available.'
				}
				$null = & $removalPersistenceDialogCommand
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to open removal persistence')
				[void](Show-ThemedDialog -Title 'Removal Persistence' -Message ("Failed to open removal persistence.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	# Remote session status action
	if ($MenuToolsRemoteSessionStatus)
	{
		Register-GuiEventHandler -Source $MenuToolsRemoteSessionStatus -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$context = $null
				try { $context = & $getRemoteTargetContextCommand } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1658' -Severity Debug }
				 $context = $null }
				$sessions = @()
				if ($getRemoteSessionSummaryCommand)
				{
					try { $sessions = @(& $getRemoteSessionSummaryCommand) } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1662' -Severity Debug }
					 $sessions = @() }
				}

				$lines = [System.Collections.Generic.List[string]]::new()
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiRemoteSessionStatusTitle' -Fallback 'Remote Session Status'))
				[void]$lines.Add(' ')
				if ($context -and $context.Connected -and $context.TargetComputers.Count -gt 0)
				{
					[void]$lines.Add(('Connected target(s): {0}' -f ($context.TargetComputers -join ', ')))
					if ($context.ConnectedAt) { [void]$lines.Add(('Connected at (UTC): {0}' -f $context.ConnectedAt)) }
					if ($context.StatusMessage) { [void]$lines.Add(('Status: {0}' -f $context.StatusMessage)) }
					if ($context.ApprovedTargetComputers -and $context.ApprovedTargetComputers.Count -gt 0)
					{
						[void]$lines.Add(('Approved target list: {0}' -f ($context.ApprovedTargetComputers -join ', ')))
						if ($context.ApprovedAt) { [void]$lines.Add(('Approved at (UTC): {0}' -f $context.ApprovedAt)) }
					}
				}
				else
				{
					[void]$lines.Add((Get-UxLocalizedString -Key 'GuiRemoteSessionStatusNone' -Fallback 'No remote target is currently connected.'))
				}

				[void]$lines.Add(' ')
				if ($sessions.Count -gt 0)
				{
					[void]$lines.Add((Get-UxLocalizedString -Key 'GuiRemoteSessionStatusCacheHeader' -Fallback 'Cached sessions:'))
					foreach ($session in @($sessions))
					{
						if (-not $session) { continue }
						$transportSuffix = ''
						if ($session.PSObject.Properties['TransportKey'] -and -not [string]::IsNullOrWhiteSpace([string]$session.TransportKey) -and [string]$session.TransportKey -ne '<default>')
						{
							$transportSuffix = ' (transport: {0})' -f ([string]$session.TransportKey).Substring(0, [Math]::Min(8, ([string]$session.TransportKey).Length))
						}
						[void]$lines.Add((' - {0} [{1}]{2}' -f $session.ComputerName, $session.State, $transportSuffix))
					}
				}
				else
				{
					[void]$lines.Add((Get-UxLocalizedString -Key 'GuiRemoteSessionStatusCacheEmpty' -Fallback 'Cached sessions: none'))
				}

				[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiRemoteSessionStatusTitle' -Fallback 'Remote Session Status') -Message ($lines -join [Environment]::NewLine) -Buttons @('OK') -AccentButton 'OK')
				LogInfo 'Viewed remote session status.'
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to view remote session status')
				[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiRemoteSessionStatusTitle' -Fallback 'Remote Session Status') -Message ((& $getUxLocalizedStringCapture -Key 'GuiRemoteSessionStatusFailed' -Fallback "Failed to view remote session status.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}.GetNewClosure()) | Out-Null
	}

	# Undo Last Run button
	$Script:LastRunProfile = Import-GuiLastRunProfile
	$Script:InterruptedRunProfile = Import-GuiInterruptedRunProfile
	$BtnUndoLastRun = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run') -Variant 'Secondary' -Compact
	$BtnUndoLastRun.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnUndoLastRun.ToolTip = (Get-UxLocalizedString -Key 'GuiActionUndoLastRunTooltip' -Fallback 'Reverse the changes from your most recent run')
	$BtnUndoLastRun.IsEnabled = ($null -ne $Script:LastRunProfile -and $Script:LastRunProfile.PSObject.Properties['RollbackCommands'] -and @($Script:LastRunProfile.RollbackCommands).Count -gt 0)
	[void]($secondaryActionBar.Children.Add($BtnUndoLastRun))
	$Script:BtnUndoLastRun = $BtnUndoLastRun
	$undoLastRunStartCommand = Get-GuiRuntimeCommand -Name 'Start-GuiExecutionRun' -CommandType 'Function'
	$undoLastRunClearCommand = Get-GuiRuntimeCommand -Name 'Clear-GuiLastRunProfile' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnUndoLastRun -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$lastRunProfile = $Script:LastRunProfile
		if (-not $lastRunProfile -or -not (& $hasField -Object $lastRunProfile -FieldName 'RollbackCommands'))
		{
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run') -Message (& $getUxLocalizedStringCapture -Key 'GuiActionUndoNoRun' -Fallback 'No previous run is available to undo.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$rollbackCommands = @($lastRunProfile.RollbackCommands)
		if ($rollbackCommands.Count -eq 0)
		{
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run') -Message (& $getUxLocalizedStringCapture -Key 'GuiActionUndoNoChanges' -Fallback 'No undoable changes were found in the last run.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$timestampText = if ((& $hasField -Object $lastRunProfile -FieldName 'Timestamp') -and -not [string]::IsNullOrWhiteSpace([string]$lastRunProfile.Timestamp))
		{
			try { " from $(([datetime]$lastRunProfile.Timestamp).ToString('g'))" } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1744' -Severity Debug }
			 '' }
		}
		else { '' }

		$undoChangesLabel = (& $getUxLocalizedStringCapture -Key 'GuiActionUndoButton' -Fallback 'Undo Changes')
		$undoConfirmMsg = if ($rollbackCommands.Count -eq 1) { (& $getUxLocalizedStringCapture -Key 'GuiActionUndoConfirmSingular' -Fallback "This will undo {0} change{1}.`n`nDo you want to continue?") -f $rollbackCommands.Count, $timestampText } else { (& $getUxLocalizedStringCapture -Key 'GuiActionUndoConfirmPlural' -Fallback "This will undo {0} changes{1}.`n`nDo you want to continue?") -f $rollbackCommands.Count, $timestampText }
		$confirmResult = Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run') `
			-Message $undoConfirmMsg `
			-Buttons @('Cancel', $undoChangesLabel) `
			-DestructiveButton $undoChangesLabel
		if ($confirmResult -ne $undoChangesLabel) { return }

		# Build tweak list from rollback commands
		$undoTweakList = [System.Collections.Generic.List[hashtable]]::new()
		$order = 0
		foreach ($commandLine in $rollbackCommands)
		{
			if ([string]::IsNullOrWhiteSpace([string]$commandLine)) { continue }
			$parts = ([string]$commandLine).Trim() -split '\s+', 2
			$functionName = $parts[0]
			$paramName = if ($parts.Count -gt 1) { $parts[1].TrimStart('-') } else { $null }
			if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

			$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function $functionName
			if (-not $manifestEntry) { continue }

			$order++
			$undoTweakList.Add(@{
				Key             = [string]$order
				Index           = $order
				Name            = [string]$manifestEntry.Name
				Function        = $functionName
				Type            = 'Toggle'
				TypeKind        = 'Toggle'
				TypeLabel       = 'Undo'
				TypeTone        = 'Caution'
				TypeBadgeLabel  = 'Undo'
				Category        = [string]$manifestEntry.Category
				Risk            = [string]$manifestEntry.Risk
				Restorable      = $manifestEntry.Restorable
				RecoveryLevel   = if ((& $hasField -Object $manifestEntry -FieldName 'RecoveryLevel')) { [string]$manifestEntry.RecoveryLevel } else { 'Direct' }
				RequiresRestart = [bool]$manifestEntry.RequiresRestart
				Impact          = $manifestEntry.Impact
				PresetTier      = $manifestEntry.PresetTier
				Selection       = if ($paramName) { $paramName } else { 'Undo' }
				ToggleParam     = $paramName
				OnParam         = [string]$manifestEntry.OnParam
				OffParam        = [string]$manifestEntry.OffParam
				IsChecked       = $true
				CurrentState    = (& $getUxLocalizedStringCapture -Key 'GuiActionUndoState' -Fallback 'Undoing previous change')
				CurrentStateTone = 'Caution'
				StateDetail     = (& $getUxLocalizedStringCapture -Key 'GuiActionUndoDetail' -Fallback 'Reverting to the state before the last run.')
				MatchesDesired  = $false
				ScenarioTags    = @()
				ReasonIncluded  = (& $getUxLocalizedStringCapture -Key 'GuiActionUndoReason' -Fallback 'Included as part of Undo Last Run.')
				BlastRadius     = ''
				IsRemoval       = $false
				ExtraArgs       = $null
				GamingPreviewGroup = $null
				TroubleshootingOnly = $false
			})
		}

		if ($undoTweakList.Count -eq 0)
		{
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run') -Message (& $getUxLocalizedStringCapture -Key 'GuiActionUndoNoResolvable' -Fallback 'Could not resolve any undoable changes from the last run.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogUndoLastRunReversing' -Fallback 'Undo Last Run: reversing {0} change(s).' -FormatArgs @($undoTweakList.Count))
		& $undoLastRunStartCommand -TweakList @($undoTweakList) -Mode 'Defaults' -ExecutionTitle (& $getUxLocalizedStringCapture -Key 'GuiActionUndoTitle' -Fallback 'Undoing Last Run')

		# Clear the last run profile after undo
		& $undoLastRunClearCommand
		$BtnUndoLastRun.IsEnabled = $false
	}.GetNewClosure()) | Out-Null

	# Resume Interrupted Run button
	$BtnResumeInterruptedRun = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterResumeInterruptedRun' -Fallback 'Resume Interrupted Run') -Variant 'Secondary' -Compact
	$BtnResumeInterruptedRun.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnResumeInterruptedRun.ToolTip = (Get-UxLocalizedString -Key 'GuiActionResumeInterruptedTooltip' -Fallback 'Resume the remaining items from the most recent interrupted run')
	$BtnResumeInterruptedRun.IsEnabled = ($null -ne $Script:InterruptedRunProfile -and $Script:InterruptedRunProfile.PSObject.Properties['ResumeCandidates'] -and @($Script:InterruptedRunProfile.ResumeCandidates).Count -gt 0)
	[void]($secondaryActionBar.Children.Add($BtnResumeInterruptedRun))
	$Script:BtnResumeInterruptedRun = $BtnResumeInterruptedRun
	$resumeInterruptedStartCommand = Get-GuiRuntimeCommand -Name 'Start-GuiExecutionRun' -CommandType 'Function'
	$resumeInterruptedClearCommand = Get-GuiRuntimeCommand -Name 'Clear-GuiInterruptedRunProfile' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnResumeInterruptedRun -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$interruptedRunProfile = $Script:InterruptedRunProfile
		if (-not $interruptedRunProfile -or -not (& $hasField -Object $interruptedRunProfile -FieldName 'ResumeCandidates'))
		{
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterResumeInterruptedRun' -Fallback 'Resume Interrupted Run') -Message (& $getUxLocalizedStringCapture -Key 'GuiActionResumeInterruptedNoRun' -Fallback 'No interrupted run is available to resume.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$resumeCandidates = @($interruptedRunProfile.ResumeCandidates)
		if ($resumeCandidates.Count -eq 0)
		{
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterResumeInterruptedRun' -Fallback 'Resume Interrupted Run') -Message (& $getUxLocalizedStringCapture -Key 'GuiActionResumeInterruptedNoChanges' -Fallback 'No resumable items were found in the interrupted run.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$timestampText = if ((& $hasField -Object $interruptedRunProfile -FieldName 'Timestamp') -and -not [string]::IsNullOrWhiteSpace([string]$interruptedRunProfile.Timestamp))
		{
			try { " from $(([datetime]$interruptedRunProfile.Timestamp).ToString('g'))" } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\SystemScanFooterHandlers.ps1:1848' -Severity Debug }
			 '' }
		}
		else { '' }

		$resumeLabel = (& $getUxLocalizedStringCapture -Key 'GuiFooterResumeInterruptedRun' -Fallback 'Resume Interrupted Run')
		$resumeConfirmMsg = if ($resumeCandidates.Count -eq 1) { (& $getUxLocalizedStringCapture -Key 'GuiActionResumeInterruptedConfirmSingular' -Fallback "This will resume {0} interrupted item{1}.`n`nDo you want to continue?") -f $resumeCandidates.Count, $timestampText } else { (& $getUxLocalizedStringCapture -Key 'GuiActionResumeInterruptedConfirmPlural' -Fallback "This will resume {0} interrupted items{1}.`n`nDo you want to continue?") -f $resumeCandidates.Count, $timestampText }
		$confirmResult = Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiFooterResumeInterruptedRun' -Fallback 'Resume Interrupted Run') `
			-Message $resumeConfirmMsg `
			-Buttons @('Cancel', $resumeLabel) `
			-AccentButton $resumeLabel
		if ($confirmResult -ne $resumeLabel) { return }

		LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogResumeInterruptedRun' -Fallback 'Resuming interrupted run: Count={0}.' -FormatArgs @($resumeCandidates.Count))
		& $resumeInterruptedStartCommand -TweakList @($resumeCandidates) -Mode 'Run' -ExecutionTitle (& $getUxLocalizedStringCapture -Key 'GuiExecTitleResumingInterruptedRun' -Fallback 'Resuming Interrupted Run')

		& $resumeInterruptedClearCommand
		$BtnResumeInterruptedRun.IsEnabled = $false
	}.GetNewClosure()) | Out-Null

	# Check Compliance button
	$BtnCheckCompliance = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterCheckCompliance' -Fallback 'Check Compliance') -Variant 'Subtle' -Compact -Muted
	$BtnCheckCompliance.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnCheckCompliance.ToolTip = (Get-UxLocalizedString -Key 'GuiActionComplianceTooltip' -Fallback 'Check current system state against a saved profile or snapshot for compliance drift.')
	[void]($secondaryActionBar.Children.Add($BtnCheckCompliance))
	$Script:BtnCheckCompliance = $BtnCheckCompliance
	$showComplianceDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ComplianceDialog' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnCheckCompliance -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		& $showComplianceDialogCommand
	}) | Out-Null

	# Audit Log button
	$BtnAuditLog = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiFooterAuditLog' -Fallback 'Audit Log') -Variant 'Subtle' -Compact -Muted
	$BtnAuditLog.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnAuditLog.ToolTip = (Get-UxLocalizedString -Key 'GuiActionAuditTooltip' -Fallback 'View the audit trail of all Baseline execution runs and compliance checks.')
	[void]($secondaryActionBar.Children.Add($BtnAuditLog))
	$Script:BtnAuditLog = $BtnAuditLog
	$showAuditLogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-AuditLogDialog' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnAuditLog -EventName 'Click' -Handler ({
		& $showAuditLogDialogCommand
	}) | Out-Null

