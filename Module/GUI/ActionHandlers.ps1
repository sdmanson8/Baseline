	#region Theme toggle handler
	Register-GuiEventHandler -Source $ChkTheme -EventName 'Checked' -Handler ({
		Invoke-CapturedFunction -Name 'Set-GUITheme' -Parameters @{ Theme = $Script:LightTheme }
	}) | Out-Null
	Register-GuiEventHandler -Source $ChkTheme -EventName 'Unchecked' -Handler ({
		Invoke-CapturedFunction -Name 'Set-GUITheme' -Parameters @{ Theme = $Script:DarkTheme }
	}) | Out-Null
	#endregion

	#region Button handlers
		$getActiveTweakRunListCommand = Get-GuiRuntimeCommand -Name 'Get-ActiveTweakRunList' -CommandType 'Function'
		$showSelectedTweakPreviewCommand = Get-GuiRuntimeCommand -Name 'Show-SelectedTweakPreview' -CommandType 'Function'
		$setGuiStatusTextCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
		$confirmHighRiskTweakRunCommand = Get-GuiRuntimeCommand -Name 'Confirm-HighRiskTweakRun' -CommandType 'Function'
		$testIsGameModeRunCommand = Get-GuiRuntimeCommand -Name 'Test-IsGameModeRun' -CommandType 'Function'
		$getTweakSelectionSummaryCommand = Get-GuiRuntimeCommand -Name 'Get-TweakSelectionSummary' -CommandType 'Function'
		$getGameModeProfileCommand = Get-GuiRuntimeCommand -Name 'Get-GameModeProfile' -CommandType 'Function'
		$getGameModeDecisionOverridesTextCommand = Get-GuiRuntimeCommand -Name 'Get-GameModeDecisionOverridesText' -CommandType 'Function'
		$getGameModeDecisionOverridesCommand = Get-GuiRuntimeCommand -Name 'Get-GameModeDecisionOverrides' -CommandType 'Function'
		$createRestorePointCommand = Get-GuiRuntimeCommand -Name 'CreateRestorePoint' -CommandType 'Function'
		$startGuiExecutionRunCommand = Get-GuiRuntimeCommand -Name 'Start-GuiExecutionRun' -CommandType 'Function'
		$getWindowsDefaultRunListCommand = Get-GuiRuntimeCommand -Name 'Get-WindowsDefaultRunList' -CommandType 'Function'
		$showHelpDialogCommand = Get-GuiRuntimeCommand -Name 'Show-HelpDialog' -CommandType 'Function'
		$showLogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-LogDialog' -CommandType 'Function'
		$getUxRunActionLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxRunActionLabel' -CommandType 'Function'
		$getUxPreviewButtonLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxPreviewButtonLabel' -CommandType 'Function'
		$getUxRestoreDefaultsConfirmationCommand = Get-GuiRuntimeCommand -Name 'Get-UxRestoreDefaultsConfirmation' -CommandType 'Function'
		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$testGuiRunInProgressCapture = $Script:TestGuiRunInProgressScript
		Register-GuiEventHandler -Source $BtnPreviewRun -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }

		$tweakList = & $getActiveTweakRunListCommand
		if (-not $tweakList -or $tweakList.Count -eq 0) { return }

		$warningChoice = & $confirmHighRiskTweakRunCommand -SelectedTweaks $tweakList
		if (-not $warningChoice -or $warningChoice -eq 'Cancel') { return }

		$previewActionLabel = if ($getUxPreviewButtonLabelCommand) { & $getUxPreviewButtonLabelCommand } else { 'Preview Run' }
		switch ($warningChoice)
		{
			'PreviewRequired'
			{
				& $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList -AllowApply
			}
			$previewActionLabel
			{
				& $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList
			}
			'Preview Run'
			{
				& $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList
			}
			'Continue Anyway'
			{
				& $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList
			}
			'Create Restore Point'
			{
				& $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList
			}
		}
	}) | Out-Null

		Register-GuiEventHandler -Source $BtnRun -EventName 'Click' -Handler ({
			if ((& $testGuiRunInProgressCapture) -and $Script:RunState)
			{
				if ($Script:RunState['Paused'])
				{
					$Script:RunState['Paused'] = $false
					$BtnRun.Content = "Pause"
					& $setGuiStatusTextCommand -Text $(if ($Script:ExecutionMode -eq 'Defaults') { 'Restoring Windows defaults...' } else { 'Running selected tweaks...' }) -Tone 'accent'
				}
				else
				{
					$Script:RunState['Paused'] = $true
					$BtnRun.Content = "Resume"
					& $setGuiStatusTextCommand -Text 'Run paused...' -Tone 'caution'
				}
				return
			}

			$tweakList = & $getActiveTweakRunListCommand
			if (-not $tweakList) { return }
			if ($tweakList.Count -eq 0)
			{
				$emptyRunMessage = if (Test-GuiModeActive -Mode 'Game') {
					'Choose a Game Mode profile before starting a gaming run.'
				}
				else {
					'Select at least one tweak before starting a run.'
				}
				Show-ThemedDialog -Title $(if (Test-GuiModeActive -Mode 'Game') { 'Game Mode' } else { & $getUxRunActionLabelCommand }) `
					-Message $emptyRunMessage `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			$isGameModeRun = & $testIsGameModeRunCommand -TweakList $tweakList
			if ($isGameModeRun)
			{
				$runSummary = & $getTweakSelectionSummaryCommand -SelectedTweaks $tweakList
				LogInfo ("Game Mode run requested: Profile={0}, Actions={1}, RestorePointRecommended={2}, Decisions={3}" -f (& $getGameModeProfileCommand), $tweakList.Count, $runSummary.ShouldRecommendRestorePoint, (& $getGameModeDecisionOverridesTextCommand -Overrides (& $getGameModeDecisionOverridesCommand)))
			}

			# Plan Summary: show pre-run overview with pre-flight checks (including restore point)
			$planPreflightResults = $null
			try { $planPreflightResults = Invoke-PreflightChecks } catch { $planPreflightResults = $null }
			$planChoice = Show-PlanSummaryDialog -SelectedTweaks $tweakList -PreflightResults $planPreflightResults
			if ($planChoice -ne 'Run Tweaks')
			{
				if ($isGameModeRun)
				{
					LogInfo "Game Mode run cancelled from plan summary."
				}
				return
			}

			# Restore point creation is now handled by the pre-flight checks system.
			# See Test-PreflightRestorePointCreation in PreflightChecks.ps1.

			& $startGuiExecutionRunCommand -TweakList $tweakList -Mode 'Run' -ExecutionTitle $(if (& $testIsGameModeRunCommand -TweakList $tweakList) { 'Running Game Mode Workflow' } else { 'Running Selected Tweaks' })
		}) | Out-Null

	Register-GuiEventHandler -Source $BtnDefaults -EventName 'Click' -Handler ({
			# Confirmation dialog for destructive action - wording adapts to current UX mode
			$restoreUx = & $getUxRestoreDefaultsConfirmationCommand
		$result = Show-ThemedDialog -Title $restoreUx.Title `
			-Message $restoreUx.Message `
			-Buttons $restoreUx.Buttons `
			-DestructiveButton $restoreUx.DestructiveButton
		if ($result -ne 'Restore Defaults') { return }

			$defaultsTweakList = & $getWindowsDefaultRunListCommand
			if ($defaultsTweakList.Count -eq 0)
			{
				Show-ThemedDialog -Title 'Restore to Windows Defaults' `
					-Message 'No restorable tweaks with Windows default actions are currently available.' `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			& $startGuiExecutionRunCommand -TweakList $defaultsTweakList -Mode 'Defaults' -ExecutionTitle 'Restoring Windows Defaults'
		}) | Out-Null

	Register-GuiEventHandler -Source $BtnHelp -EventName 'Click' -Handler ({
		& $showHelpDialogCommand
		& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiHelpOpened' -Fallback 'Help opened.') -Tone 'accent'
	}) | Out-Null

	if ($BtnStartHere)
	{
		$startHereShowThemedDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ThemedDialog' -CommandType 'Function'
		$startHereShowHelpDialogCommand = Get-GuiRuntimeCommand -Name 'Show-HelpDialog' -CommandType 'Function'
		$startHereSetGuiPresetSelectionCommand = Get-GuiRuntimeCommand -Name 'Set-GuiPresetSelection' -CommandType 'Function'
		$startHereGetRecommendedPresetCommand = Get-GuiRuntimeCommand -Name 'Get-UxRecommendedPresetName' -CommandType 'Function'
		$startHereGetPresetLoadedStatusTextCommand = Get-GuiRuntimeCommand -Name 'Get-UxPresetLoadedStatusText' -CommandType 'Function'
		$startHereGetPrimaryActionLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxFirstRunPrimaryActionLabel' -CommandType 'Function'
		$startHereGetDialogTitleCommand = Get-GuiRuntimeCommand -Name 'Get-UxFirstRunDialogTitle' -CommandType 'Function'
		$startHereGetOpenHelpActionLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxOpenHelpActionLabel' -CommandType 'Function'
		$startHereGetWelcomeMessageCommand = Get-GuiRuntimeCommand -Name 'Get-UxFirstRunWelcomeMessage' -CommandType 'Function'
		if (-not $startHereShowThemedDialogCommand) { throw "Show-ThemedDialog not found." }
		if (-not $startHereShowHelpDialogCommand) { throw "Show-HelpDialog not found." }
		if (-not $startHereSetGuiPresetSelectionCommand) { throw "Set-GuiPresetSelection not found." }
		if (-not $startHereGetRecommendedPresetCommand) { throw "Get-UxRecommendedPresetName not found." }
		if (-not $startHereGetPresetLoadedStatusTextCommand) { throw "Get-UxPresetLoadedStatusText not found." }
		if (-not $startHereGetPrimaryActionLabelCommand) { throw "Get-UxFirstRunPrimaryActionLabel not found." }
		if (-not $startHereGetWelcomeMessageCommand) { throw "Get-UxFirstRunWelcomeMessage not found." }
		Register-GuiEventHandler -Source $BtnStartHere -EventName 'Click' -Handler ({
			$recommendedPreset = & $startHereGetRecommendedPresetCommand
			$chooseButton = & $startHereGetPrimaryActionLabelCommand
			$dialogTitle = if ($startHereGetDialogTitleCommand) { & $startHereGetDialogTitleCommand } else { 'Welcome to Baseline' }
			$openHelpActionLabel = if ($startHereGetOpenHelpActionLabelCommand) { & $startHereGetOpenHelpActionLabelCommand } else { 'Open Help' }
			$welcomeMessage = & $startHereGetWelcomeMessageCommand
			$choice = & $startHereShowThemedDialogCommand -Title $dialogTitle `
				-Message $welcomeMessage `
				-Buttons @('Close', $openHelpActionLabel, $chooseButton) `
				-AccentButton $chooseButton

			if ([string]::IsNullOrWhiteSpace([string]$choice) -or [string]$choice -eq 'Close')
			{
				& $setGuiStatusTextCommand -Text 'Start guide closed.' -Tone 'muted'
				return
			}

			if ([string]$choice -eq [string]$openHelpActionLabel)
			{
				& $startHereShowHelpDialogCommand
				return
			}

			if ([string]$choice -eq [string]$chooseButton)
			{
				if ([bool]$Script:GameMode)
				{
					$gamingTab = Get-PrimaryTabItem -Tag 'Gaming'
					if ($gamingTab -and $PrimaryTabs)
					{
						$PrimaryTabs.SelectedItem = $gamingTab
					}
					& $setGuiStatusTextCommand -Text 'Game Mode active. Review the gaming plan, then use Preview Run before Run Tweaks.' -Tone 'accent'
				}
				else
				{
					& $startHereSetGuiPresetSelectionCommand -PresetName $recommendedPreset
					$presetLoadedStatusText = & $startHereGetPresetLoadedStatusTextCommand -PresetName $recommendedPreset
					& $setGuiStatusTextCommand -Text $presetLoadedStatusText -Tone 'accent'
				}
			}
		}.GetNewClosure()) | Out-Null
	}

	Register-GuiEventHandler -Source $BtnLog -EventName 'Click' -Handler ({
		$logPath = $Global:LogFilePath
		if ($logPath -and (Test-Path -LiteralPath $logPath -ErrorAction SilentlyContinue))
		{
			& $showLogDialogCommand -LogPath $logPath
		}
		else
		{
			Show-ThemedDialog -Title 'Open Log' `
				-Message "Log file not found.`n$logPath" `
				-Buttons @('OK') `
				-AccentButton 'OK'
		}
	}) | Out-Null
	#endregion Button handlers

	#region System scan toggle
	$invokeGuiSystemScanCommand = Get-GuiRuntimeCommand -Name 'Invoke-GuiSystemScan' -CommandType 'Function'
	$buildTabContentCommand = Get-GuiRuntimeCommand -Name 'Build-TabContent' -CommandType 'Function'
	Register-GuiEventHandler -Source $ChkScan -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		& $invokeGuiSystemScanCommand
	}) | Out-Null
	Register-GuiEventHandler -Source $ChkScan -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:ScanEnabled = $false
		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			if ($sctl) { $sctl.IsEnabled = $true }
		}
		& $setGuiStatusTextCommand -Text '' -Tone 'muted'
		if ($Script:CurrentPrimaryTab) { & $buildTabContentCommand -PrimaryTab $Script:CurrentPrimaryTab }
	}) | Out-Null
	#endregion

	# Style buttons directly
	$bc = [System.Windows.Media.BrushConverter]::new()

	function Sync-UxActionButtonText
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if ($BtnRun -and -not (& $Script:TestGuiRunInProgressScript))
		{
			$btnRunContent = [string]$BtnRun.Content
			if ($btnRunContent -notin @('Pause', 'Resume', 'Stopping...', 'Exiting...'))
			{
				Set-GuiButtonIconContent -Button $BtnRun -IconName 'RunTweaks' -Text (Get-UxRunActionLabel) -ToolTip (Get-UxRunActionToolTip)
			}
		}

		if ($BtnRestoreSnapshot)
		{
			$BtnRestoreSnapshot.Content = Get-UxUndoSelectionActionLabel
			$BtnRestoreSnapshot.ToolTip = if (Test-IsSafeModeUX) {
				'Undo the last preset or imported selection change by restoring the previous GUI snapshot.'
			}
			else {
				'Restore the last captured UI snapshot before an import or preset change.'
			}
		}

		if ($BtnPreviewRun)
		{
			Set-GuiButtonIconContent -Button $BtnPreviewRun -IconName 'PreviewRun' -Text (Get-UxPreviewButtonLabel) -ToolTip (Get-UxPreviewButtonToolTip)
		}

		if ($BtnStartHere)
		{
			Set-GuiButtonIconContent -Button $BtnStartHere -IconName 'QuickStart' -Text (Get-UxStartGuideButtonLabel) -ToolTip 'Open the getting started guide.'
		}

		if ($BtnHelp)
		{
			Set-GuiButtonIconContent -Button $BtnHelp -IconName 'Help' -Text (Get-UxHelpButtonLabel) -ToolTip 'Open help and usage guidance.'
		}

		Update-RunPathContextLabel
	}

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
				try { $Script:RunPathContextLabel.Foreground = $Script:SharedBrushConverter.ConvertFromString([string]$toneColor) } catch { }
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
	[void]($ActionButtonBar.Children.Add($secondaryActionGroup))
	$BtnExportSettings = New-PresetButton -Label 'Export Settings' -Variant 'Subtle' -Compact -Muted
	$BtnExportSettings.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportSettings.ToolTip = 'Export the current GUI selections to a JSON profile.'
	[void]($secondaryActionBar.Children.Add($BtnExportSettings))
	$BtnImportSettings = New-PresetButton -Label 'Import Settings' -Variant 'Subtle' -Compact -Muted
	$BtnImportSettings.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnImportSettings.ToolTip = 'Import a saved JSON profile and restore the selected GUI state.'
	[void]($secondaryActionBar.Children.Add($BtnImportSettings))
	$BtnRestoreSnapshot = New-PresetButton -Label (Get-UxUndoSelectionActionLabel) -Variant 'Secondary' -Compact
	$BtnRestoreSnapshot.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnRestoreSnapshot.ToolTip = 'Restore the last captured UI snapshot before an import or preset change.'
	[void]($secondaryActionBar.Children.Add($BtnRestoreSnapshot))
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
				[void](Show-ThemedDialog -Title (& $getUxUndoSelectionActionLabelCommand) -Message $(if (& $testIsSafeModeUxCommand) { 'No preset or imported selection change is available to undo yet.' } else { 'No previous GUI snapshot has been captured yet.' }) -Buttons @('OK') -AccentButton 'OK')
				return
			}
		}
		catch
		{
			LogError "Failed to restore GUI snapshot: $($_.Exception.Message)"
			[void](Show-ThemedDialog -Title (& $getUxUndoSelectionActionLabelCommand) -Message $(if (& $testIsSafeModeUxCommand) { "Failed to undo the previous selection change.`n`n$($_.Exception.Message)" } else { "Failed to restore the previous snapshot.`n`n$($_.Exception.Message)" }) -Buttons @('OK') -AccentButton 'OK')
			return
		}

		& $setGuiStatusTextCommand -Text $(if (& $testIsSafeModeUxCommand) { 'Last selection change undone.' } else { 'Previous GUI snapshot restored.' }) -Tone 'accent'
		LogInfo $(if (& $testIsSafeModeUxCommand) { 'Undid previous GUI selection change via snapshot restore.' } else { 'Restored previous GUI snapshot' })
	}) | Out-Null

	# Capture file-dialog function for use inside .GetNewClosure() handlers
	# (.GetNewClosure() captures variables but not functions from the parent scope).
	$showGuiFileSaveDialogCommand = ${function:Show-GuiFileSaveDialog}

	# Export System State button
	$BtnExportSystemState = New-PresetButton -Label 'Export System State' -Variant 'Subtle' -Compact -Muted
	$BtnExportSystemState.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportSystemState.ToolTip = 'Capture a snapshot of current system settings and save to a JSON file.'
	[void]($secondaryActionBar.Children.Add($BtnExportSystemState))
	$exportSystemStateSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportSystemState -EventName 'Click' -Handler ({
		try
		{
			& $exportSystemStateSetStatusCommand -Text 'Capturing system state snapshot...' -Tone 'accent'
			$snapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest
			$defaultFileName = 'Baseline-SystemState-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
			$savePath = & $showGuiFileSaveDialogCommand -Title 'Export System State Snapshot' `
				-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
				-DefaultExtension 'json' `
				-FileName $defaultFileName
			if ([string]::IsNullOrWhiteSpace($savePath))
			{
				& $exportSystemStateSetStatusCommand -Text 'System state export cancelled.' -Tone 'accent'
				return
			}
			Export-SystemStateSnapshot -Snapshot $snapshot -Path $savePath
			& $exportSystemStateSetStatusCommand -Text ("System state exported: {0} entries saved to {1}" -f $snapshot.Entries.Count, $savePath) -Tone 'success'
			LogInfo ("Exported system state snapshot: {0} entries to {1}" -f $snapshot.Entries.Count, $savePath)
		}
		catch
		{
			LogError "Failed to export system state: $($_.Exception.Message)"
			[void](Show-ThemedDialog -Title 'Export System State' -Message "Failed to export system state.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK')
		}
	}) | Out-Null

	# Export Configuration Profile button
	$BtnExportConfigProfile = New-PresetButton -Label 'Export Config Profile' -Variant 'Subtle' -Compact -Muted
	$BtnExportConfigProfile.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnExportConfigProfile.ToolTip = 'Export current tweak selections as a portable configuration profile.'
	[void]($secondaryActionBar.Children.Add($BtnExportConfigProfile))
	$exportConfigProfileGetRunListCommand = Get-GuiRuntimeCommand -Name 'Get-ActiveTweakRunList' -CommandType 'Function'
	$exportConfigProfileSetStatusCommand = Get-GuiRuntimeCommand -Name 'Set-GuiStatusText' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnExportConfigProfile -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		try
		{
			$tweakList = & $exportConfigProfileGetRunListCommand
			if (-not $tweakList -or @($tweakList).Count -eq 0)
			{
				Show-ThemedDialog -Title 'Export Configuration Profile' `
					-Message 'Select at least one tweak before exporting a configuration profile.' `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			$baselineVersion = $null
			try { $baselineVersion = Get-BaselineDisplayVersion } catch { }
			if ([string]::IsNullOrWhiteSpace($baselineVersion)) { $baselineVersion = 'unknown' }

			$profile = New-ConfigurationProfile `
				-Name ('Baseline-Profile-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) `
				-Selections @($tweakList) `
				-BaselineVersion $baselineVersion

			$defaultFileName = 'Baseline-ConfigProfile-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
			$savePath = & $showGuiFileSaveDialogCommand -Title 'Export Configuration Profile' `
				-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
				-DefaultExtension 'json' `
				-FileName $defaultFileName

			if ([string]::IsNullOrWhiteSpace($savePath))
			{
				& $exportConfigProfileSetStatusCommand -Text 'Configuration profile export cancelled.' -Tone 'accent'
				return
			}

			Export-ConfigurationProfile -Profile $profile -FilePath $savePath
			& $exportConfigProfileSetStatusCommand -Text ("Configuration profile exported: {0} entries saved to {1}" -f @($tweakList).Count, $savePath) -Tone 'success'
			LogInfo ("Exported configuration profile: {0} entries to {1}" -f @($tweakList).Count, $savePath)
		}
		catch
		{
			LogError "Failed to export configuration profile: $($_.Exception.Message)"
			[void](Show-ThemedDialog -Title 'Export Configuration Profile' -Message "Failed to export configuration profile.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure()) | Out-Null

	# Undo Last Run button
	$Script:LastRunProfile = Import-GuiLastRunProfile
	$BtnUndoLastRun = New-PresetButton -Label 'Undo Last Run' -Variant 'Secondary' -Compact
	$BtnUndoLastRun.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnUndoLastRun.ToolTip = 'Reverse the changes from your most recent run'
	$BtnUndoLastRun.IsEnabled = ($null -ne $Script:LastRunProfile -and $Script:LastRunProfile.PSObject.Properties['RollbackCommands'] -and @($Script:LastRunProfile.RollbackCommands).Count -gt 0)
	[void]($secondaryActionBar.Children.Add($BtnUndoLastRun))
	$Script:BtnUndoLastRun = $BtnUndoLastRun
	$undoLastRunStartCommand = Get-GuiRuntimeCommand -Name 'Start-GuiExecutionRun' -CommandType 'Function'
	$undoLastRunClearCommand = Get-GuiRuntimeCommand -Name 'Clear-GuiLastRunProfile' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnUndoLastRun -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$lastRunProfile = $Script:LastRunProfile
		if (-not $lastRunProfile -or -not (Test-GuiObjectField -Object $lastRunProfile -FieldName 'RollbackCommands'))
		{
			Show-ThemedDialog -Title 'Undo Last Run' -Message 'No previous run is available to undo.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$rollbackCommands = @($lastRunProfile.RollbackCommands)
		if ($rollbackCommands.Count -eq 0)
		{
			Show-ThemedDialog -Title 'Undo Last Run' -Message 'No undoable changes were found in the last run.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$timestampText = if ((Test-GuiObjectField -Object $lastRunProfile -FieldName 'Timestamp') -and -not [string]::IsNullOrWhiteSpace([string]$lastRunProfile.Timestamp))
		{
			try { " from $(([datetime]$lastRunProfile.Timestamp).ToString('g'))" } catch { '' }
		}
		else { '' }

		$confirmResult = Show-ThemedDialog -Title 'Undo Last Run' `
			-Message "This will undo $($rollbackCommands.Count) change$(if ($rollbackCommands.Count -eq 1) { '' } else { 's' })$timestampText.`n`nDo you want to continue?" `
			-Buttons @('Cancel', 'Undo Changes') `
			-DestructiveButton 'Undo Changes'
		if ($confirmResult -ne 'Undo Changes') { return }

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
				RecoveryLevel   = if ((Test-GuiObjectField -Object $manifestEntry -FieldName 'RecoveryLevel')) { [string]$manifestEntry.RecoveryLevel } else { 'Direct' }
				RequiresRestart = [bool]$manifestEntry.RequiresRestart
				Impact          = $manifestEntry.Impact
				PresetTier      = $manifestEntry.PresetTier
				Selection       = if ($paramName) { $paramName } else { 'Undo' }
				ToggleParam     = $paramName
				OnParam         = [string]$manifestEntry.OnParam
				OffParam        = [string]$manifestEntry.OffParam
				IsChecked       = $true
				CurrentState    = 'Undoing previous change'
				CurrentStateTone = 'Caution'
				StateDetail     = 'Reverting to the state before the last run.'
				MatchesDesired  = $false
				ScenarioTags    = @()
				ReasonIncluded  = 'Included as part of Undo Last Run.'
				BlastRadius     = ''
				IsRemoval       = $false
				ExtraArgs       = $null
				GamingPreviewGroup = $null
				TroubleshootingOnly = $false
			})
		}

		if ($undoTweakList.Count -eq 0)
		{
			Show-ThemedDialog -Title 'Undo Last Run' -Message 'Could not resolve any undoable changes from the last run.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		LogInfo ("Undo Last Run: reversing {0} change(s)." -f $undoTweakList.Count)
		& $undoLastRunStartCommand -TweakList @($undoTweakList) -Mode 'Defaults' -ExecutionTitle 'Undoing Last Run'

		# Clear the last run profile after undo
		& $undoLastRunClearCommand
		$BtnUndoLastRun.IsEnabled = $false
	}.GetNewClosure()) | Out-Null

	# Check Compliance button
	$BtnCheckCompliance = New-PresetButton -Label 'Check Compliance' -Variant 'Subtle' -Compact -Muted
	$BtnCheckCompliance.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnCheckCompliance.ToolTip = 'Check current system state against a saved profile or snapshot for compliance drift.'
	[void]($secondaryActionBar.Children.Add($BtnCheckCompliance))
	$showComplianceDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ComplianceDialog' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnCheckCompliance -EventName 'Click' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		& $showComplianceDialogCommand
	}) | Out-Null

	# Audit Log button
	$BtnAuditLog = New-PresetButton -Label 'Audit Log' -Variant 'Subtle' -Compact -Muted
	$BtnAuditLog.FontSize = $Script:GuiLayout.FontSizeSmall
	$BtnAuditLog.ToolTip = 'View the audit trail of all Baseline execution runs and compliance checks.'
	[void]($secondaryActionBar.Children.Add($BtnAuditLog))
	$showAuditLogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-AuditLogDialog' -CommandType 'Function'
	Register-GuiEventHandler -Source $BtnAuditLog -EventName 'Click' -Handler ({
		& $showAuditLogDialogCommand
	}) | Out-Null
