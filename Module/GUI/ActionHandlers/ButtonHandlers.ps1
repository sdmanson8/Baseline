
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
		$showThemedDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ThemedDialog' -CommandType 'Function'
		$testGuiModeActiveCommand = Get-GuiRuntimeCommand -Name 'Test-GuiModeActive' -CommandType 'Function'
		$invokePreflightChecksCommand = Get-GuiRuntimeCommand -Name 'Invoke-PreflightChecks' -CommandType 'Function'
		$showPlanSummaryDialogCommand = Get-GuiRuntimeCommand -Name 'Show-PlanSummaryDialog' -CommandType 'Function'
		$showReadmeDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ReadmeDialog' -CommandType 'Function'
		$showGuiFaqDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFaqDialog' -CommandType 'Function'
		$showUpdateCheckDialogCommand = Get-GuiRuntimeCommand -Name 'Show-BaselineUpdateCheckDialog' -CommandType 'Function'
		$showLogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-LogDialog' -CommandType 'Function'
		$showChangelogDialogCommand = Get-GuiRuntimeCommand -Name 'Show-ChangelogDialog' -CommandType 'Function'
		$showGuiAuditSettingsDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiAuditSettingsDialog' -CommandType 'Function'
		$showGuiSettingsDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiSettingsDialog' -CommandType 'Function'
		$showGuiRemoteConsoleDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiRemoteConsoleDialog' -CommandType 'Function'
		$showGuiOperatorConsoleDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiOperatorConsoleDialog' -CommandType 'Function'
		$showGuiReleaseStatusDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiReleaseStatusDialog' -CommandType 'Function'
		$showGuiTroubleshootingGuideDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiTroubleshootingGuideDialog' -CommandType 'Function'
		$showGuiRemovalPersistenceDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiRemovalPersistenceDialog' -CommandType 'Function'
		$showGuiDeploymentMediaBuilderDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiDeploymentMediaBuilderDialog' -CommandType 'Function'
		$showWslInstallDialogCommand = Get-GuiRuntimeCommand -Name 'Show-WslInstallDialog' -CommandType 'Function'
		$invokeWslInstallFlowCommand = Get-GuiRuntimeCommand -Name 'Invoke-BaselineWslInstallFlow' -CommandType 'Function'
		$exportSupportBundleCommand = Get-GuiRuntimeCommand -Name 'Export-BaselineSupportBundle' -CommandType 'Function'
		$getGuiSettingsSnapshotCommand = Get-GuiRuntimeCommand -Name 'Get-GuiSettingsSnapshot' -CommandType 'Function'
		$getRemoteSessionSummaryCommand = Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteSessionSummary' -CommandType 'Function'
		$promptRemoteTargetConnectionCommand = Get-GuiRuntimeCommand -Name 'Prompt-GuiRemoteTargetConnection' -CommandType 'Function'
		$getRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Get-GuiRemoteTargetContext' -CommandType 'Function'
		$setRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Set-GuiRemoteTargetContext' -CommandType 'Function'
		$setRemoteTargetApprovalCommand = Get-GuiRuntimeCommand -Name 'Set-GuiRemoteTargetApprovalList' -CommandType 'Function'
		$testRemoteTargetApprovalCommand = Get-GuiRuntimeCommand -Name 'Test-GuiRemoteTargetApproval' -CommandType 'Function'
		$exportRemoteTargetApprovalPolicyCommand = Get-GuiRuntimeCommand -Name 'Export-GuiRemoteTargetApprovalPolicy' -CommandType 'Function'
		$importRemoteTargetApprovalPolicyCommand = Get-GuiRuntimeCommand -Name 'Import-GuiRemoteTargetApprovalPolicy' -CommandType 'Function'
		$clearRemoteTargetContextCommand = Get-GuiRuntimeCommand -Name 'Clear-GuiRemoteTargetContext' -CommandType 'Function'
		$clearRemoteSessionCacheCommand = Get-GuiRuntimeCommand -Name 'Clear-BaselineRemoteSessionCache' -CommandType 'Function'
		$testRemoteTargetConnectedCommand = Get-GuiRuntimeCommand -Name 'Test-GuiRemoteTargetConnected' -CommandType 'Function'
		$getUxRunActionLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxRunActionLabel' -CommandType 'Function'
		$getUxPreviewButtonLabelCommand = Get-GuiRuntimeCommand -Name 'Get-UxPreviewButtonLabel' -CommandType 'Function'
		$getUxRestoreDefaultsConfirmationCommand = Get-GuiRuntimeCommand -Name 'Get-UxRestoreDefaultsConfirmation' -CommandType 'Function'
		$testIsDesignModeUxCommand = Get-GuiRuntimeCommand -Name 'Test-IsDesignModeUX' -CommandType 'Function'
		$showGuiFileSaveDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiFileSaveDialog' -CommandType 'Function'
		$newConfigurationProfileCommand = Get-GuiRuntimeCommand -Name 'New-ConfigurationProfile' -CommandType 'Function'
		$exportConfigurationProfileCommand = Get-GuiRuntimeCommand -Name 'Export-ConfigurationProfile' -CommandType 'Function'
		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$getUxBilingualLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxBilingualLocalizedString'
		if ($getUxBilingualLocalizedStringCapture)
		{
			Set-Item -Path function:Get-UxBilingualLocalizedString -Value $getUxBilingualLocalizedStringCapture
		}
		$testGuiRunInProgressCapture = $Script:TestGuiRunInProgressScript
		$startAppsCacheRefreshCommand = Get-GuiRuntimeCommand -Name 'Start-AppsCacheRefresh' -CommandType 'Function'
		$setAppPackageSourcePreferenceStateCommand = Get-GuiRuntimeCommand -Name 'Set-AppPackageSourcePreferenceState' -CommandType 'Function'
		$setAppSourceFilterStateCommand = Get-GuiRuntimeCommand -Name 'Set-AppSourceFilterState' -CommandType 'Function'
		$startAppsModuleActionAsyncCommand = Get-GuiRuntimeCommand -Name 'Start-AppsModuleActionAsync' -CommandType 'Function'
		$startAppsModuleBatchActionAsyncCommand = Get-GuiRuntimeCommand -Name 'Start-AppsModuleBatchActionAsync' -CommandType 'Function'
		$clearAppSelectionStateCommand = Get-GuiRuntimeCommand -Name 'Clear-AppSelectionState' -CommandType 'Function'
		$startAppsModuleQueuedActionAsyncCommand = Get-GuiRuntimeCommand -Name 'Start-AppsModuleQueuedActionAsync' -CommandType 'Function'
		$clearAppsQueuedActionsCommand = Get-GuiRuntimeCommand -Name 'Clear-AppsQueuedActions' -CommandType 'Function'
		$setAppQueuedActionCommand = Get-GuiRuntimeCommand -Name 'Set-AppQueuedAction' -CommandType 'Function'
		$getQueuedAppsProfileActionsCommand = Get-GuiRuntimeCommand -Name 'Get-QueuedAppsProfileActions' -CommandType 'Function'
		if (-not $startAppsCacheRefreshCommand) { throw 'Start-AppsCacheRefresh not found.' }
		if (-not $setAppPackageSourcePreferenceStateCommand) { throw 'Set-AppPackageSourcePreferenceState not found.' }
		if (-not $startAppsModuleActionAsyncCommand) { throw 'Start-AppsModuleActionAsync not found.' }
		if (-not $startAppsModuleBatchActionAsyncCommand) { throw 'Start-AppsModuleBatchActionAsync not found.' }
		if (-not $clearAppSelectionStateCommand) { throw 'Clear-AppSelectionState not found.' }
		if (-not $showThemedDialogCommand) { throw 'Show-ThemedDialog not found.' }
		if (-not $testGuiModeActiveCommand) { throw 'Test-GuiModeActive not found.' }
		if (-not $invokePreflightChecksCommand) { throw 'Invoke-PreflightChecks not found.' }
		if (-not $showPlanSummaryDialogCommand) { throw 'Show-PlanSummaryDialog not found.' }
		if (-not $showGuiAuditSettingsDialogCommand) { throw 'Show-GuiAuditSettingsDialog not found.' }
		if (-not $showGuiSettingsDialogCommand) { throw 'Show-GuiSettingsDialog not found.' }
		if (-not $showGuiFileSaveDialogCommand) { throw 'Show-GuiFileSaveDialog not found.' }
		if (-not $newConfigurationProfileCommand) { throw 'New-ConfigurationProfile not found.' }
		if (-not $exportConfigurationProfileCommand) { throw 'Export-ConfigurationProfile not found.' }
		if (-not $showGuiRemoteConsoleDialogCommand) { throw 'Show-GuiRemoteConsoleDialog not found.' }
		if (-not $showGuiReleaseStatusDialogCommand) { throw 'Show-GuiReleaseStatusDialog not found.' }
		if (-not $showGuiTroubleshootingGuideDialogCommand) { throw 'Show-GuiTroubleshootingGuideDialog not found.' }
		if (-not $showGuiFaqDialogCommand) { throw 'Show-GuiFaqDialog not found.' }
		if (-not $showGuiDeploymentMediaBuilderDialogCommand) { throw 'Show-GuiDeploymentMediaBuilderDialog not found.' }
		if (-not $exportRemoteTargetApprovalPolicyCommand)
		{
			LogWarning 'Export-GuiRemoteTargetApprovalPolicy not found; remote approval policy save actions will be disabled.'
			if ($MenuToolsSaveRemoteApprovalPolicy) { $MenuToolsSaveRemoteApprovalPolicy.IsEnabled = $false }
		}
		if (-not $importRemoteTargetApprovalPolicyCommand)
		{
			LogWarning 'Import-GuiRemoteTargetApprovalPolicy not found; remote approval policy load actions will be disabled.'
			if ($MenuToolsLoadRemoteApprovalPolicy) { $MenuToolsLoadRemoteApprovalPolicy.IsEnabled = $false }
		}

		function Invoke-GuiConfigurationProfileExport
		{
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
			param (
				[string]$Context = 'ExportConfigProfile'
			)

			try
			{
				$tweakList = @(& $getActiveTweakRunListCommand)
				$queuedAppActions = if ($getQueuedAppsProfileActionsCommand) { @(& $getQueuedAppsProfileActionsCommand) } else { @() }
				$tweakCount = @($tweakList).Count
				$appActionCount = @($queuedAppActions).Count
				$title = (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileTitle' -Fallback 'Export Configuration Profile')

				if ($tweakCount -eq 0 -and $appActionCount -eq 0)
				{
					Show-ThemedDialog -Title $title `
						-Message (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileNoTweaks' -Fallback 'Select at least one tweak or queue at least one app action before exporting a configuration profile.') `
						-Buttons @('OK') `
						-AccentButton 'OK'
					return $false
				}

				$baselineVersion = $null
				try { $baselineVersion = Get-BaselineDisplayVersion } catch { Write-SwallowedException -ErrorRecord $_ -Source ('ActionHandlers.{0}.GetDisplayVersion' -f $Context) }
				if ([string]::IsNullOrWhiteSpace($baselineVersion)) { $baselineVersion = 'unknown' }

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
							Write-SwallowedException -ErrorRecord $_ -Source ('ActionHandlers.{0}.UserApps' -f $Context)
						}
						$userAppSnapshot = @()
					}
				}

				$includePaths = @()
				$includePathCmd = Get-Command -Name 'Get-HeadlessPresetIncludedTweakLibraryPathSet' -CommandType Function -ErrorAction SilentlyContinue
				if ($includePathCmd)
				{
					$includePaths = @(& $includePathCmd)
				}

				$profile = & $newConfigurationProfileCommand `
					-Name ('Baseline-Profile-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) `
					-Selections @($tweakList) `
					-AppActions @($queuedAppActions) `
					-UserApps @($userAppSnapshot) `
					-IncludePaths $includePaths `
					-BaselineVersion $baselineVersion `
					-AppsPackageSourcePreference $Script:AppsPackageSourcePreference

				$defaultFileName = 'Baseline-ConfigProfile-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
				$savePath = & $showGuiFileSaveDialogCommand -Title $title `
					-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
					-DefaultExtension 'json' `
					-FileName $defaultFileName

				if ([string]::IsNullOrWhiteSpace($savePath))
				{
					& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileCancelled' -Fallback 'Configuration profile export cancelled.') -Tone 'accent'
					return $false
				}

				& $exportConfigurationProfileCommand -Profile $profile -FilePath $savePath
				if ($tweakCount -gt 0 -and $appActionCount -gt 0)
				{
					& $setGuiStatusTextCommand -Text ("Configuration profile exported: {0} tweak(s) and {1} app action(s) saved to {2}" -f $tweakCount, $appActionCount, $savePath) -Tone 'success'
					LogInfo ("Exported configuration profile: {0} tweak(s) and {1} app action(s) to {2}" -f $tweakCount, $appActionCount, $savePath)
				}
				elseif ($tweakCount -gt 0)
				{
					& $setGuiStatusTextCommand -Text ("Configuration profile exported: {0} tweak(s) saved to {1}" -f $tweakCount, $savePath) -Tone 'success'
					LogInfo ("Exported configuration profile: {0} tweak(s) to {1}" -f $tweakCount, $savePath)
				}
				else
				{
					& $setGuiStatusTextCommand -Text ("Configuration profile exported: {0} app action(s) saved to {1}" -f $appActionCount, $savePath) -Tone 'success'
					LogInfo ("Exported configuration profile: {0} app action(s) to {1}" -f $appActionCount, $savePath)
				}

				return $true
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to export configuration profile')
				[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileTitle' -Fallback 'Export Configuration Profile') -Message ((& $getUxLocalizedStringCapture -Key 'GuiActionExportProfileFailed' -Fallback "Failed to export configuration profile.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
				return $false
			}
		}

		$exportGuiConfigurationProfileCommand = ${function:Invoke-GuiConfigurationProfileExport}
		Register-GuiEventHandler -Source $BtnPreviewRun -EventName 'Click' -Handler ({
			if ($Script:AppsModeActive) { return }
			if (& $testGuiRunInProgressCapture) { return }

		$tweakList = & $getActiveTweakRunListCommand
		if (-not $tweakList -or $tweakList.Count -eq 0) { return }

		$warningChoice = & $confirmHighRiskTweakRunCommand -SelectedTweaks $tweakList
		if (-not $warningChoice -or $warningChoice -eq 'Cancel') { return }

		$previewActionLabel = if ($getUxPreviewButtonLabelCommand) { & $getUxPreviewButtonLabelCommand } else { 'Preview Run' }
		$previewResult = $null
		switch ($warningChoice)
		{
			'PreviewRequired'
			{
				$previewResult = & $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList -AllowApply
			}
			$previewActionLabel
			{
				$previewResult = & $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList -AllowApply
			}
			'Preview Run'
			{
				$previewResult = & $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList -AllowApply
			}
			'Run Anyway'
			{
				$previewResult = & $showSelectedTweakPreviewCommand -SelectedTweaks $tweakList -AllowApply
			}
		}

		if ($previewResult -and $previewResult -eq (& $getUxRunActionLabelCommand))
		{
			& $startGuiExecutionRunCommand -TweakList $tweakList -Mode 'Run' -ExecutionTitle $(if (& $testIsGameModeRunCommand -TweakList $tweakList) { & $getUxLocalizedStringCapture -Key 'GuiExecTitleRunningGameMode' -Fallback 'Running Game Mode Workflow' } else { & $getUxLocalizedStringCapture -Key 'GuiExecTitleRunning' -Fallback 'Running Selected Tweaks' })
			return
		}
	}) | Out-Null

		Register-GuiEventHandler -Source $BtnRun -EventName 'Click' -Handler ({
				if ($Script:AppsModeActive) { return }
			if ((& $testGuiRunInProgressCapture) -and $Script:RunState)
			{
				if ($Script:RunState['Paused'])
				{
					$Script:RunState['Paused'] = $false
					$BtnRun.Content = (& $getUxLocalizedStringCapture -Key 'GuiPauseButton' -Fallback 'Pause')
					& $setGuiStatusTextCommand -Text $(if ($Script:ExecutionMode -eq 'Defaults') { & $getUxLocalizedStringCapture -Key 'GuiStatusRestoringDefaultValues' -Fallback 'Restoring default values...' } else { & $getUxLocalizedStringCapture -Key 'GuiStatusRunningTweaks' -Fallback 'Running selected tweaks...' }) -Tone 'accent'
				}
				else
				{
					$Script:RunState['Paused'] = $true
					$BtnRun.Content = (& $getUxLocalizedStringCapture -Key 'GuiResumeButton' -Fallback 'Resume')
					& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiRunPaused' -Fallback 'Run paused...') -Tone 'caution'
				}
				return
			}

			if ($testIsDesignModeUxCommand -and (& $testIsDesignModeUxCommand))
			{
				$null = & $exportGuiConfigurationProfileCommand -Context 'DesignModeSaveConfig'
				return
			}

			$tweakList = & $getActiveTweakRunListCommand
			if (-not $tweakList) { return }
			if ($tweakList.Count -eq 0)
			{
				$isGameModeActiveForEmptyRun = if ($testGuiModeActiveCommand) { [bool](& $testGuiModeActiveCommand -Mode 'Game') } else { $false }
				$emptyRunMessage = if ($isGameModeActiveForEmptyRun) {
					(& $getUxLocalizedStringCapture -Key 'GuiActionEmptyRunGameMode' -Fallback 'Choose a Game Mode profile before starting a gaming run.')
				}
				else {
					(& $getUxLocalizedStringCapture -Key 'GuiActionEmptyRunNormal' -Fallback 'Select at least one tweak before starting a run.')
				}
				& $showThemedDialogCommand -Title $(if ($isGameModeActiveForEmptyRun) { & $getUxLocalizedStringCapture -Key 'GuiGameModeHeader' -Fallback 'Game Mode' } else { & $getUxRunActionLabelCommand }) `
					-Message $emptyRunMessage `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			$isGameModeRun = & $testIsGameModeRunCommand -TweakList $tweakList
			if ($isGameModeRun)
			{
				$runSummary = & $getTweakSelectionSummaryCommand -SelectedTweaks $tweakList
				LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogGameModeRunRequested' -Fallback 'Game Mode run requested: Profile={0}, Actions={1}, RestorePointRecommended={2}, Decisions={3}' -FormatArgs @((& $getGameModeProfileCommand), $tweakList.Count, $runSummary.ShouldRecommendRestorePoint, (& $getGameModeDecisionOverridesTextCommand -Overrides (& $getGameModeDecisionOverridesCommand))))
			}

			$requireRunConfirmation = $true
			$requireRunConfirmationVariable = Get-Variable -Scope Script -Name 'RequireRunConfirmation' -ErrorAction SilentlyContinue
			if ($requireRunConfirmationVariable)
			{
				$requireRunConfirmation = [bool]$requireRunConfirmationVariable.Value
			}

			if ($requireRunConfirmation)
			{
				# Plan Summary: show pre-run overview with pre-flight checks.
				$planPreflightResults = $null
				try { if ($invokePreflightChecksCommand) { $planPreflightResults = & $invokePreflightChecksCommand } } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\ButtonHandlers.ps1:307' -Severity Debug }
				 $planPreflightResults = $null }
				$planChoice = & $showPlanSummaryDialogCommand -SelectedTweaks $tweakList -PreflightResults $planPreflightResults
				if ($planChoice -ne (& $getUxRunActionLabelCommand))
				{
					if ($isGameModeRun)
					{
						LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogGameModeRunCancelled' -Fallback 'Game Mode run cancelled from plan summary.')
					}
					return
				}
			}

			$executionTitle = if ($isGameModeRun) { & $getUxLocalizedStringCapture -Key 'GuiExecTitleRunningGameMode' -Fallback 'Running Game Mode Workflow' } else { & $getUxLocalizedStringCapture -Key 'GuiExecTitleRunning' -Fallback 'Running Selected Tweaks' }
			$startConfirmedRunCommand = $startGuiExecutionRunCommand
			$startConfirmedTweakList = @($tweakList)
			$startConfirmedExecutionTitle = $executionTitle
			$startConfirmedRun = {
				& $startConfirmedRunCommand -TweakList $startConfirmedTweakList -Mode 'Run' -ExecutionTitle $startConfirmedExecutionTitle
			}.GetNewClosure()

			$runDispatcher = if ($Form -and $Form.Dispatcher) { $Form.Dispatcher } elseif ($Script:MainForm -and $Script:MainForm.Dispatcher) { $Script:MainForm.Dispatcher } else { $null }
			if ($requireRunConfirmation -and $runDispatcher)
			{
				$null = $runDispatcher.BeginInvoke([System.Action]$startConfirmedRun, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
				return
			}

			& $startConfirmedRun
		}) | Out-Null

		if ($BtnUpdateAllApps)
		{
			Register-GuiEventHandler -Source $BtnUpdateAllApps -EventName 'Click' -Handler ({
				if ($Script:AppsModeActive)
				{
					$confirmation = Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiUpdateAllAppsConfirmTitle' -Fallback 'Update All Installed Apps') `
						-Message (Get-UxLocalizedString -Key 'GuiUpdateAllAppsConfirmMessage' -Fallback 'Are you sure you want to update all installed apps?') `
						-Buttons @('Cancel', 'Update All') `
						-AccentButton 'Update All'
					if ($confirmation -ne 'Update All') { return }
					try
					{
						& $startAppsModuleActionAsyncCommand -Action 'UpdateAll'
					}
					catch
					{
						throw
					}
				}
			}) | Out-Null
		}

		# Source filter pills are RadioButtons in one group, so we still route
		# clicks through Set-AppSourceFilterState to keep the source filter state
		# normalized and to refresh the app list consistently.
		if ($BtnAppsSourceFilterAll)
		{
			Register-GuiEventHandler -Source $BtnAppsSourceFilterAll -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive -or $Script:AppsSourceFilterUiUpdating) { return }
				if ([string]$Script:AppsSourceFilter -eq 'All')
				{
					$Script:AppsSourceFilterUiUpdating = $true
					try { $Script:BtnAppsSourceFilterAll.IsChecked = $true } finally { $Script:AppsSourceFilterUiUpdating = $false }
					return
				}
				& $setAppSourceFilterStateCommand -Source 'All'
			}) | Out-Null
		}

		if ($BtnAppsSourceFilterWinGet)
		{
			Register-GuiEventHandler -Source $BtnAppsSourceFilterWinGet -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive -or $Script:AppsSourceFilterUiUpdating) { return }
				if ([string]$Script:AppsSourceFilter -eq 'winget')
				{
					$Script:AppsSourceFilterUiUpdating = $true
					try { $Script:BtnAppsSourceFilterWinGet.IsChecked = $true } finally { $Script:AppsSourceFilterUiUpdating = $false }
					return
				}
				& $setAppSourceFilterStateCommand -Source 'winget'
			}) | Out-Null
		}

		if ($BtnAppsSourceFilterChocolatey)
		{
			Register-GuiEventHandler -Source $BtnAppsSourceFilterChocolatey -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive -or $Script:AppsSourceFilterUiUpdating) { return }
				if ([string]$Script:AppsSourceFilter -eq 'choco')
				{
					$Script:AppsSourceFilterUiUpdating = $true
					try { $Script:BtnAppsSourceFilterChocolatey.IsChecked = $true } finally { $Script:AppsSourceFilterUiUpdating = $false }
					return
				}
				& $setAppSourceFilterStateCommand -Source 'choco'
			}) | Out-Null
		}

		if ($BtnAppsViewCards)
		{
			Register-GuiEventHandler -Source $BtnAppsViewCards -EventName 'Click' -Handler ({
				if ($Script:AppsViewModeUiUpdating) { return }
				if ([string]$Script:AppsViewMode -eq 'Cards')
				{
					$Script:AppsViewModeUiUpdating = $true
					try { $Script:BtnAppsViewCards.IsChecked = $true } finally { $Script:AppsViewModeUiUpdating = $false }
					return
				}
				$Script:AppsViewMode = 'Cards'
				$Script:AppsViewBuildSignature = $null
				if (Get-Command -Name 'Update-AppsViewModeControls' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Update-AppsViewModeControls
				}
				if ($Script:AppsModeActive -and (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue))
				{
					Build-AppsViewCards
				}
			}) | Out-Null
		}

		if ($BtnAppsViewList)
		{
			Register-GuiEventHandler -Source $BtnAppsViewList -EventName 'Click' -Handler ({
				if ($Script:AppsViewModeUiUpdating) { return }
				if ([string]$Script:AppsViewMode -eq 'List')
				{
					$Script:AppsViewModeUiUpdating = $true
					try { $Script:BtnAppsViewList.IsChecked = $true } finally { $Script:AppsViewModeUiUpdating = $false }
					return
				}
				$Script:AppsViewMode = 'List'
				$Script:AppsViewBuildSignature = $null
				if (Get-Command -Name 'Update-AppsViewModeControls' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Update-AppsViewModeControls
				}
				if ($Script:AppsModeActive -and (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue))
				{
					Build-AppsViewCards
				}
			}) | Out-Null
		}

		if ($BtnAppsAddCustom)
		{
			Register-GuiEventHandler -Source $BtnAppsAddCustom -EventName 'Click' -Handler ({
				if (-not (Get-Command -Name 'Show-GuiAddCustomAppDialog' -CommandType Function -ErrorAction SilentlyContinue))
				{
					return
				}
				$result = $null
				try { $result = Show-GuiAddCustomAppDialog }
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.AddCustomApp'
					}
					return
				}
				if (-not $result -or -not $result.Saved) { return }

				if (Get-Command -Name 'Get-BaselineApplicationsCatalog' -CommandType Function -ErrorAction SilentlyContinue)
				{
					try { $null = Get-BaselineApplicationsCatalog -Force } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.AddCustomApp.RefreshCatalog' }
				}
				$Script:AppsViewBuildSignature = $null
				if ($Script:AppsModeActive -and (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue))
				{
					Build-AppsViewCards
				}
			}) | Out-Null
		}

		if ($BtnInstallSelectedApps)
		{
			Register-GuiEventHandler -Source $BtnInstallSelectedApps -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				if (-not $Script:SelectedAppIds) { return }
				foreach ($id in @($Script:SelectedAppIds))
				{
					if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
					try { Set-AppQueuedAction -AppId $id -Action 'Install' } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\ButtonHandlers.ps1:489' -Severity Debug }
					 $null = $_ }
				}
			}) | Out-Null
		}

		if ($BtnUninstallSelectedApps)
		{
			Register-GuiEventHandler -Source $BtnUninstallSelectedApps -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				if (-not $Script:SelectedAppIds) { return }
				foreach ($id in @($Script:SelectedAppIds))
				{
					if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
					try { Set-AppQueuedAction -AppId $id -Action 'Uninstall' } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\ButtonHandlers.ps1:502' -Severity Debug }
					 $null = $_ }
				}
			}) | Out-Null
		}

		if ($BtnUpdateSelectedApps)
		{
			Register-GuiEventHandler -Source $BtnUpdateSelectedApps -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				if (-not $Script:SelectedAppIds) { return }
				foreach ($id in @($Script:SelectedAppIds))
				{
					if ([string]::IsNullOrWhiteSpace([string]$id)) { continue }
					try { Set-AppQueuedAction -AppId $id -Action 'Update' } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ActionHandlers\ButtonHandlers.ps1:515' -Severity Debug }
					 $null = $_ }
				}
			}) | Out-Null
		}

		if ($BtnScanInstalledApps)
		{
			Register-GuiEventHandler -Source $BtnScanInstalledApps -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				try
				{
					& $startAppsCacheRefreshCommand
				}
				catch
				{
					throw
				}
			}) | Out-Null
		}

		# Per-app queued-action apply button: executes the Install/Uninstall queue that
		# individual app rows can populate via Set-AppQueuedAction.
		if ($BtnApplyQueuedActions)
		{
			Register-GuiEventHandler -Source $BtnApplyQueuedActions -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				if ($startAppsModuleQueuedActionAsyncCommand)
				{
					& $startAppsModuleQueuedActionAsyncCommand
				}
			}) | Out-Null
		}

		# Reset: clear queued actions and uncheck all selected apps in one go.
		if ($BtnClearQueuedActions)
		{
			Register-GuiEventHandler -Source $BtnClearQueuedActions -EventName 'Click' -Handler ({
				if (-not $Script:AppsModeActive) { return }
				if ($clearAppsQueuedActionsCommand) { & $clearAppsQueuedActionsCommand }
				if ($clearAppSelectionStateCommand) { & $clearAppSelectionStateCommand }
			}) | Out-Null
		}

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
				Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiBtnDefaultsRecorded' -Fallback 'Restore Defaults') `
					-Message (& $getUxLocalizedStringCapture -Key 'GuiActionRestoreDefaultsNoTweaksRecorded' -Fallback 'No restorable tweaks with default restore actions are currently available.') `
					-Buttons @('OK') `
					-AccentButton 'OK'
				return
			}

			try
			{
				& $startGuiExecutionRunCommand -TweakList $defaultsTweakList -Mode 'Defaults' -ExecutionTitle (& $getUxLocalizedStringCapture -Key 'GuiExecTitleRestoringDefaultValues' -Fallback 'Restoring default values')
			}
			catch
			{
				throw
			}
		}) | Out-Null

	# Per-page "Reset to defaults" buttons.
	# Each button must be named BtnPageReset_<CategoryName> in the XAML, or the
	# page view can call Invoke-PageResetToDefaults with the category string.
	# Here we register a generic handler factory so any button following the
	# BtnPageReset_* naming convention is wired automatically.
	$getCategoryDefaultRunListCommand = Get-GuiRuntimeCommand -Name 'Get-CategoryDefaultRunList' -CommandType 'Function'
	if ($getCategoryDefaultRunListCommand)
	{
		foreach ($pageResetButton in @($Script:Controls | Where-Object { $_ -and $_.Name -match '^BtnPageReset_' }))
		{
			$pageCategory = $pageResetButton.Name -replace '^BtnPageReset_', '' -replace '_', ' '
			$capturedButton = $pageResetButton
			$capturedCategory = $pageCategory
			$capturedGetCategoryDefaultRunListCommand = $getCategoryDefaultRunListCommand
			$capturedStartGuiExecutionRunCommand = $startGuiExecutionRunCommand
			$pageResetHandler = {
				param ()
				$categoryTweakList = & $capturedGetCategoryDefaultRunListCommand -Category $capturedCategory
				if (-not $categoryTweakList -or $categoryTweakList.Count -eq 0)
				{
					Show-ThemedDialog -Title 'Reset to Defaults' -Message 'No restorable tweaks with recorded default values found for this page.' -Buttons @('OK') -AccentButton 'OK'
					return
				}
				$result = Show-ThemedDialog -Title 'Reset page to defaults' -Message ('Reset ' + $capturedCategory + ' (' + $categoryTweakList.Count + ' tweaks) to recorded default values?') -Buttons @('Cancel','Reset to Defaults') -DestructiveButton 'Reset to Defaults'
				if ($result -ne 'Reset to Defaults') { return }
				& $capturedStartGuiExecutionRunCommand -TweakList $categoryTweakList -Mode 'Defaults' -ExecutionTitle ('Resetting ' + $capturedCategory + ' to defaults')
			}.GetNewClosure()
			Register-GuiEventHandler -Source $capturedButton -EventName 'Click' -Handler $pageResetHandler | Out-Null
		}
	}

	# Public helper: call this from any page/tab to trigger a category-scoped
	# defaults restore without needing a named button.
	<#
	    .SYNOPSIS
	#>

	$Script:InvokePageResetToDefaultsScript = {
		[CmdletBinding()]
		param (
			[Parameter(Mandatory)]
			[string]$Category
		)

		$categoryDefaultRunListCommand = if ($getCategoryDefaultRunListCommand) { $getCategoryDefaultRunListCommand } else { Get-GuiRuntimeCommand -Name 'Get-CategoryDefaultRunList' -CommandType 'Function' }
		$executionRunCommand = if ($startGuiExecutionRunCommand) { $startGuiExecutionRunCommand } else { Get-GuiRuntimeCommand -Name 'Start-GuiExecutionRun' -CommandType 'Function' }
		$dialogCommand = if ($showThemedDialogCommand) { $showThemedDialogCommand } else { Get-GuiRuntimeCommand -Name 'Show-ThemedDialog' -CommandType 'Function' }

		if (-not $categoryDefaultRunListCommand) { throw 'Get-CategoryDefaultRunList not found.' }
		if (-not $executionRunCommand) { throw 'Start-GuiExecutionRun not found.' }
		if (-not $dialogCommand) { throw 'Show-ThemedDialog not found.' }

		$tweakList = & $categoryDefaultRunListCommand -Category $Category
		if (-not $tweakList -or $tweakList.Count -eq 0)
		{
			& $dialogCommand -Title 'Reset to Defaults' -Message "No restorable tweaks with recorded default values found for '$Category'." -Buttons @('OK') -AccentButton 'OK'
			return
		}
		$result = & $dialogCommand -Title 'Reset page to defaults' `
			-Message "Reset $Category ($($tweakList.Count) tweaks) to recorded default values?" `
			-Buttons @('Cancel', 'Reset to Defaults') `
			-DestructiveButton 'Reset to Defaults'
		if ($result -ne 'Reset to Defaults') { return }
		& $executionRunCommand -TweakList $tweakList -Mode 'Defaults' -ExecutionTitle "Resetting $Category to defaults"
	}.GetNewClosure()

	function Invoke-PageResetToDefaults
	{
		[CmdletBinding()]
		param (
			[Parameter(Mandatory)]
			[string]$Category
		)

		& $Script:InvokePageResetToDefaultsScript -Category $Category
	}

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
		$startHereGuidedSetupWizardCommand = Get-GuiRuntimeCommand -Name 'Show-GuidedSetupWizard' -CommandType 'Function'
		if (-not $startHereShowThemedDialogCommand) { throw "Show-ThemedDialog not found." }
		if (-not $startHereShowHelpDialogCommand) { throw "Show-HelpDialog not found." }
		if (-not $startHereSetGuiPresetSelectionCommand) { throw "Set-GuiPresetSelection not found." }
		if (-not $startHereGetRecommendedPresetCommand) { throw "Get-UxRecommendedPresetName not found." }
		if (-not $startHereGetPresetLoadedStatusTextCommand) { throw "Get-UxPresetLoadedStatusText not found." }
		if (-not $startHereGetPrimaryActionLabelCommand) { throw "Get-UxFirstRunPrimaryActionLabel not found." }
		if (-not $startHereGetWelcomeMessageCommand) { throw "Get-UxFirstRunWelcomeMessage not found." }
		Register-GuiEventHandler -Source $BtnStartHere -EventName 'Click' -Handler ({
			$recommendedPreset   = & $startHereGetRecommendedPresetCommand
			$chooseButton        = & $startHereGetPrimaryActionLabelCommand
			$dialogTitle         = if ($startHereGetDialogTitleCommand) { & $startHereGetDialogTitleCommand } else { (& $getUxLocalizedStringCapture -Key 'GuiFirstRunDialogTitle' -Fallback 'Welcome to Baseline') }
			$openHelpActionLabel = if ($startHereGetOpenHelpActionLabelCommand) { & $startHereGetOpenHelpActionLabelCommand } else { (& $getUxLocalizedStringCapture -Key 'GuiOpenHelpActionLabel' -Fallback 'Open Help') }
			$welcomeMessage      = & $startHereGetWelcomeMessageCommand
			$closeLabel          = & $getUxLocalizedStringCapture -Key 'GuiCloseButton' -Fallback 'Close'
			$guidedSetupLabel    = & $getUxLocalizedStringCapture -Key 'GuiGuidedSetupButton' -Fallback 'Guided Setup'

			$choice = & $startHereShowThemedDialogCommand -Title $dialogTitle `
				-Message $welcomeMessage `
				-Buttons @($closeLabel, $openHelpActionLabel, $chooseButton, $guidedSetupLabel) `
				-AccentButton $guidedSetupLabel

			if ([string]::IsNullOrWhiteSpace([string]$choice) -or [string]$choice -eq $closeLabel)
			{
				& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionStartGuideClosed' -Fallback 'Start guide closed.') -Tone 'muted'
				return
			}

			if ([string]$choice -eq [string]$openHelpActionLabel)
			{
				& $startHereShowHelpDialogCommand
				return
			}

			if ([string]$choice -eq [string]$guidedSetupLabel -and $startHereGuidedSetupWizardCommand)
			{
				& $startHereGuidedSetupWizardCommand `
					-ShowThemedDialogCapture $startHereShowThemedDialogCommand `
					-SetGuiPresetSelectionAction { param($PresetName) & $startHereSetGuiPresetSelectionCommand -PresetName $PresetName } `
					-SetGuiStatusTextAction { param($Text, $Tone) & $setGuiStatusTextCommand -Text $Text -Tone $Tone } `
					-Theme $Script:CurrentTheme `
					-ApplyButtonChrome ${function:Set-ButtonChrome} `
					-OwnerWindow $Script:MainForm `
					-UseDarkMode ($Script:CurrentThemeName -eq 'Dark')
				return
			}

			if ([string]$choice -eq [string]$chooseButton)
			{
				if ([bool]$Script:GameMode)
				{
					if ($Script:NavModeGaming)
					{
						$Script:NavModeGaming.IsChecked = $true
					}
					elseif (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Set-GuiGamingMode -Enable:$true
					}
					& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiActionGameModeActive' -Fallback ('Game Mode active. Review the gaming plan, then use Preview Run before {0}.' -f (& $getUxRunActionLabelCommand))) -Tone 'accent'
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
			Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiBtnLog' -Fallback 'Open Log') `
				-Message ((& $getUxLocalizedStringCapture -Key 'GuiActionLogNotFound' -Fallback "Log file not found.`n{0}") -f $logPath) `
				-Buttons @('OK') `
				-AccentButton 'OK'
		}
	}) | Out-Null
	#endregion Button handlers
