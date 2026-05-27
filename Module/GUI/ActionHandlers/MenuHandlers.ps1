
	#region Top Menu Bar handlers
	# Menu items route to existing buttons by raising their Click event, reusing all existing logic.
	$raiseButtonClick = {
		param($Button)
		if ($null -eq $Button) { return }
		try
		{
			if (-not $Button.IsEnabled) { return }
			$evt = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
			$Button.RaiseEvent($evt)
		}
		catch
		{
			try
			{
				LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Menu click routing failed')
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuClickRouting.LogWarning'
				}
			}
		}
	}

	$setAppPackageSourcePreferenceStateCommand = Get-GuiRuntimeCommand -Name 'Set-AppPackageSourcePreferenceState' -CommandType 'Function'
	$convertToAppPackageSourcePreferenceCommand = Get-GuiRuntimeCommand -Name 'ConvertTo-AppPackageSourcePreference' -CommandType 'Function'
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

	# File menu
	if ($MenuFileImportSettings)
	{
		Register-GuiEventHandler -Source $MenuFileImportSettings -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnImportSettings
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuFileExportSettings)
	{
		Register-GuiEventHandler -Source $MenuFileExportSettings -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnExportSettings
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuFileSettings)
	{
		Register-GuiEventHandler -Source $MenuFileSettings -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$defaultLogFileDirectory = if (Get-Command -Name 'Get-BaselineLogDirectory' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[string](Get-BaselineLogDirectory)
				}
				else
				{
					[System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'Baseline', 'UserState', 'Logs')
				}
				$customLogFileDirectory = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[string](Get-BaselineUserPreference -Key 'LogFileDirectory' -Default '')
				}
				else
				{
					if ($Script:LogFileDirectory) { [string]$Script:LogFileDirectory } else { '' }
				}
				$runtimeDebugLoggingEnabled = if (Get-Command -Name 'Get-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[bool](Get-BaselineDebugLogging)
				}
				else
				{
					if ($null -ne $Script:DebugLoggingEnabled) { [bool]$Script:DebugLoggingEnabled } else { $false }
				}
				$debugLoggingEnabled = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[bool](Get-BaselineUserPreference -Key 'DebugLoggingEnabled' -Default $runtimeDebugLoggingEnabled)
				}
				else
				{
					$runtimeDebugLoggingEnabled
				}
				$runtimeLogLevel = if ($Script:LogLevel) { [string]$Script:LogLevel } else { 'All' }
				if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$runtimeLogLevel = Normalize-GuiLogLevel -Level $runtimeLogLevel
				}
				$logLevel = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[string](Get-BaselineUserPreference -Key 'LogLevel' -Default $runtimeLogLevel)
				}
				else
				{
					$runtimeLogLevel
				}
				if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$logLevel = Normalize-GuiLogLevel -Level $logLevel
				}
				$runtimeAppsPackageSourcePreference = if ($Script:AppsPackageSourcePreference) { [string]$Script:AppsPackageSourcePreference } else { 'auto' }
				$appsPackageSourcePreference = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
				{
					[string](Get-BaselineUserPreference -Key 'AppsPackageSourcePreference' -Default $runtimeAppsPackageSourcePreference)
				}
				else
				{
					$runtimeAppsPackageSourcePreference
				}
				if ([string]::IsNullOrWhiteSpace($appsPackageSourcePreference)) { $appsPackageSourcePreference = 'auto' }
				$updateSettings = if (Get-Command -Name 'Get-BaselineUpdateSettings' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Get-BaselineUpdateSettings
				}
				else
				{
					[pscustomobject]@{
						AutoCheckUpdates = if ($null -ne $Script:AutoCheckUpdates) { [bool]$Script:AutoCheckUpdates } else { $true }
						CheckFrequency = if ($Script:UpdateCheckFrequency) { [string]$Script:UpdateCheckFrequency } else { 'Startup' }
						UpdateBranch = if ($Script:UpdateBranch) { [string]$Script:UpdateBranch } elseif (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
						IncludePrereleaseBuilds = if ($null -ne $Script:IncludePrereleaseUpdates) { [bool]$Script:IncludePrereleaseUpdates } else { $false }
					}
				}
				$updateCheckState = if (Get-Command -Name 'Get-BaselineUpdateCheckState' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Get-BaselineUpdateCheckState
				}
				else
				{
					[pscustomobject]@{
						LastCheckedUtc = $null
						Status = 'Not checked'
						LatestVersion = ''
					}
				}
				$currentPrefs = @{
					Language = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
					DefaultStartupMode = if ($Script:DefaultStartupMode) { [string]$Script:DefaultStartupMode } else { 'Safe' }
					RestoreLastSession = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) {
						[bool](Get-BaselineUserPreference -Key 'RestoreLastSession' -Default $true)
					}
					else
					{
						if ($null -ne $Script:RestoreLastSession) { [bool]$Script:RestoreLastSession } else { $true }
					}
					AutoScanOnLaunch = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'AutoScanOnLaunch' -Default $false) } else { [bool]$Script:AutoScanOnLaunch }
					HideUnavailableItems = if ($null -ne $Script:HideUnavailableItems) { [bool]$Script:HideUnavailableItems } elseif (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'HideUnavailableItems' -Default $true) } else { $true }
					StartupRunInitialActions = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupRunInitialActions' -Default $true) } elseif ($null -ne $Script:StartupRunInitialActions) { [bool]$Script:StartupRunInitialActions } else { $true }
					StartupCheckWinGet = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupCheckWinGet' -Default $true) } elseif ($null -ne $Script:StartupCheckWinGet) { [bool]$Script:StartupCheckWinGet } else { $true }
					StartupWinGetCheckFrequency = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineUserPreference -Key 'StartupWinGetCheckFrequency' -Default 'Startup') } elseif ($Script:StartupWinGetCheckFrequency) { [string]$Script:StartupWinGetCheckFrequency } else { 'Startup' }
					StartupCheckChocolatey = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'StartupCheckChocolatey' -Default $true) } elseif ($null -ne $Script:StartupCheckChocolatey) { [bool]$Script:StartupCheckChocolatey } else { $true }
					StartupChocolateyCheckFrequency = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineUserPreference -Key 'StartupChocolateyCheckFrequency' -Default 'Startup') } elseif ($Script:StartupChocolateyCheckFrequency) { [string]$Script:StartupChocolateyCheckFrequency } else { 'Startup' }
					AutoCheckUpdates = [bool]$updateSettings.AutoCheckUpdates
					UpdateCheckFrequency = [string]$updateSettings.CheckFrequency
					UpdateBranch = if ($updateSettings -and $updateSettings.PSObject.Properties['UpdateBranch'] -and -not [string]::IsNullOrWhiteSpace([string]$updateSettings.UpdateBranch)) { [string]$updateSettings.UpdateBranch } elseif (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
					IncludePrereleaseUpdates = if ($updateSettings -and $updateSettings.PSObject.Properties['IncludePrereleaseBuilds']) { [bool]$updateSettings.IncludePrereleaseBuilds } elseif ($null -ne $Script:IncludePrereleaseUpdates) { [bool]$Script:IncludePrereleaseUpdates } else { $false }
					UpdateLastCheckedUtc = $updateCheckState.LastCheckedUtc
					UpdateCheckStatus = [string]$updateCheckState.Status
					UpdateLatestVersion = [string]$updateCheckState.LatestVersion
					CurrentVersion = if (Get-Command -Name 'Get-BaselineDisplayVersion' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineDisplayVersion) } elseif ($Script:CurrentAppVersion) { [string]$Script:CurrentAppVersion } else { '0.0.0' }
					Theme = if ($Script:ThemePreference) { [string]$Script:ThemePreference } else { 'System' }
					UIDensity = if (Get-Command -Name 'Get-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineUiDensity } elseif ($Script:UIDensity) { [string]$Script:UIDensity } else { 'Comfort' }
					SafeMode = [bool]$Script:SafeMode
					RequireRunConfirmation = if ($null -ne $Script:RequireRunConfirmation) { [bool]$Script:RequireRunConfirmation } else { $true }
					PreviewBeforeRunDefault = [bool]$Script:PreviewBeforeRunDefault
					AuditRetentionDays = if ($Script:AuditRetentionDays) { [int]$Script:AuditRetentionDays } else { 90 }
					AppsPackageSourcePreference = $appsPackageSourcePreference
					AppsSilentInstall = if ($null -ne $Script:AppsSilentInstall) { [bool]$Script:AppsSilentInstall } else { $true }
					AppsAutoUpdate = [bool]$Script:AppsAutoUpdate
					LoggingEnabled = if ($null -ne $Script:LoggingEnabled) { [bool]$Script:LoggingEnabled } else { $true }
					DebugLoggingEnabled = $debugLoggingEnabled
					LogLevel = $logLevel
					LogFilePath = if ($Script:LogFilePath) { [string]$Script:LogFilePath } else { '' }
					DefaultLogFileDirectory = $defaultLogFileDirectory
					LogFileDirectory = $customLogFileDirectory
					AdvancedMode = [bool]$Script:AdvancedMode
					DesignMode = if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue) { [bool](Get-BaselineUserPreference -Key 'DesignMode' -Default $false) } else { [bool]$Script:DesignMode }
				}

				$result = & $showGuiSettingsDialogCommand -Current $currentPrefs
				if (-not $result) { return }

				$runUpdateBranchCheckNow = $false
				if ($result.ContainsKey('UpdateBranch'))
				{
					$defaultUpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
					$previousUpdateBranch = if ($currentPrefs.ContainsKey('UpdateBranch') -and -not [string]::IsNullOrWhiteSpace([string]$currentPrefs.UpdateBranch)) { [string]$currentPrefs.UpdateBranch } else { $defaultUpdateBranch }
					$requestedUpdateBranch = if (-not [string]::IsNullOrWhiteSpace([string]$result.UpdateBranch)) { [string]$result.UpdateBranch } else { $defaultUpdateBranch }
					if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$previousUpdateBranch = ConvertTo-BaselineUpdateBranch -Branch $previousUpdateBranch
						$requestedUpdateBranch = ConvertTo-BaselineUpdateBranch -Branch $requestedUpdateBranch
					}

					if (-not [string]::Equals($previousUpdateBranch, $requestedUpdateBranch, [System.StringComparison]::OrdinalIgnoreCase))
					{
						$branchPromptTitle = Get-UxLocalizedString -Key 'GuiSettingsUpdateBranchPromptTitle' -Fallback 'Change Update Channel'
						$branchPromptMessage = Get-UxLocalizedString -Key 'GuiSettingsUpdateBranchPromptMessage' -Fallback "Switch update channel from {0} to {1}?`n`nSwitching channels may change which releases Baseline offers in future update checks."
						$branchChangeNowLabel = Get-UxLocalizedString -Key 'GuiSettingsUpdateBranchChangeNow' -Fallback 'Continue'
						$branchNextReleaseLabel = Get-UxLocalizedString -Key 'GuiSettingsUpdateBranchNextRelease' -Fallback 'Switch On Next Release'
						$branchCancelLabel = Get-UxLocalizedString -Key 'GuiCancelButton' -Fallback 'Cancel'
						$branchChoice = if ($showThemedDialogCommand)
						{
							& $showThemedDialogCommand `
								-Title $branchPromptTitle `
								-Message ($branchPromptMessage -f $previousUpdateBranch, $requestedUpdateBranch) `
								-Buttons @($branchCancelLabel, $branchNextReleaseLabel, $branchChangeNowLabel) `
								-AccentButton $branchChangeNowLabel
						}
						else
						{
							$branchCancelLabel
						}
						$runUpdateBranchCheckNow = [string]::Equals([string]$branchChoice, [string]$branchChangeNowLabel, [System.StringComparison]::OrdinalIgnoreCase)
						$deferUpdateBranchSwitch = [string]::Equals([string]$branchChoice, [string]$branchNextReleaseLabel, [System.StringComparison]::OrdinalIgnoreCase)
						if (-not ($runUpdateBranchCheckNow -or $deferUpdateBranchSwitch))
						{
							return
						}
					}
				}

				# Wired preferences (affect behavior now):
				if ($result.ContainsKey('Theme'))
				{
					if (Get-Command -Name 'Apply-BaselineThemePreference' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Apply-BaselineThemePreference -Preference ([string]$result.Theme) }
						catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Apply-BaselineThemePreference failed') }
					}
					elseif ($ChkTheme)
					{
						$wantLight = ([string]$result.Theme -eq 'Light')
						if ($ChkTheme.IsChecked -ne $wantLight) { $ChkTheme.IsChecked = $wantLight }
					}
				}
				# Apply Safe / Expert mode transitions on save. Settings is the
				# visible mode selector, so call the transition functions directly.
				$wantAdvanced = $result.ContainsKey('AdvancedMode') -and [bool]$result.AdvancedMode
				$wantSafe = $result.ContainsKey('SafeMode') -and [bool]$result.SafeMode
				if ($result.ContainsKey('DefaultStartupMode') -and ([string]$result.DefaultStartupMode -eq 'Expert'))
				{
					$wantAdvanced = $true
					$wantSafe = $false
				}
				$Script:SafeMode = $wantSafe
				$Script:AdvancedMode = $wantAdvanced
				if ($wantAdvanced -and (Get-Command -Name 'Set-AdvancedModeState' -CommandType Function -ErrorAction SilentlyContinue))
				{
					try { Set-AdvancedModeState -Enabled $true } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-AdvancedModeState failed') }
				}
				elseif ($wantSafe -and (Get-Command -Name 'Set-SafeModeState' -CommandType Function -ErrorAction SilentlyContinue))
				{
					try { Set-SafeModeState -Enabled $true } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-SafeModeState failed') }
				}
				elseif ((-not $wantSafe) -and (-not $wantAdvanced))
				{
					if (Get-Command -Name 'Set-SafeModeState' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Set-SafeModeState -Enabled $false } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-SafeModeState off failed') }
					}
				}
				if ($result.ContainsKey('AuditRetentionDays'))
				{
					$Script:AuditRetentionDays = [int]$result.AuditRetentionDays
					if ($Script:Ctx -and $Script:Ctx.UI)
					{
						$Script:Ctx.UI.AuditRetentionDays = [int]$result.AuditRetentionDays
					}
				}
				if ($result.ContainsKey('AppsPackageSourcePreference'))
				{
					$appsPackageSourcePreferenceWanted = [string]$result.AppsPackageSourcePreference
					if ($convertToAppPackageSourcePreferenceCommand)
					{
						try { $appsPackageSourcePreferenceWanted = [string](& $convertToAppPackageSourcePreferenceCommand -Source $appsPackageSourcePreferenceWanted) }
						catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Normalize AppsPackageSourcePreference failed') }
					}
					if ([string]::IsNullOrWhiteSpace($appsPackageSourcePreferenceWanted)) { $appsPackageSourcePreferenceWanted = 'auto' }
					if ($setAppPackageSourcePreferenceStateCommand)
					{
						try
						{
							& $setAppPackageSourcePreferenceStateCommand -Source $appsPackageSourcePreferenceWanted
							if ($Script:AppsPackageSourcePreference) { $appsPackageSourcePreferenceWanted = [string]$Script:AppsPackageSourcePreference }
						}
						catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-AppPackageSourcePreferenceState failed') }
					}
					else
					{
						$Script:AppsPackageSourcePreference = $appsPackageSourcePreferenceWanted
					}
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'AppsPackageSourcePreference' -Value $appsPackageSourcePreferenceWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist AppsPackageSourcePreference failed') }
					}
				}

				# Stub preferences (persisted only):
				if ($result.ContainsKey('Language'))
				{
					$desiredLanguage = [string]$result.Language
					$currentLanguage = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
					if (-not [string]::Equals($desiredLanguage, $currentLanguage, [System.StringComparison]::OrdinalIgnoreCase))
					{
						if ($Script:SetSelectedGuiLanguageScript)
						{
							& $Script:SetSelectedGuiLanguageScript -langCode $desiredLanguage
						}
						else
						{
							$Script:SelectedLanguage = $desiredLanguage
						}
					}
				}
				if ($result.ContainsKey('DefaultStartupMode'))
				{
					$Script:DefaultStartupMode = [string]$result.DefaultStartupMode
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'DefaultStartupMode' -Value $Script:DefaultStartupMode } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist DefaultStartupMode failed') }
					}
				}
				if ($result.ContainsKey('RestoreLastSession'))
				{
					$restoreLastSessionWanted = [bool]$result.RestoreLastSession
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'RestoreLastSession' -Value $restoreLastSessionWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist RestoreLastSession failed') }
					}
					$Script:RestoreLastSession = $restoreLastSessionWanted
				}
				if ($result.ContainsKey('AutoScanOnLaunch'))
				{
					$autoScanWanted = [bool]$result.AutoScanOnLaunch
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'AutoScanOnLaunch' -Value $autoScanWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist AutoScanOnLaunch failed') }
					}
					$Script:AutoScanOnLaunch = $autoScanWanted
				}
				if ($result.ContainsKey('HideUnavailableItems'))
				{
					$hideUnavailWanted = [bool]$result.HideUnavailableItems
					if (Get-Command -Name 'Set-HideUnavailableItemsState' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Set-HideUnavailableItemsState -HideUnavailableItems $hideUnavailWanted | Out-Null } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-HideUnavailableItemsState failed') }
					}
					else
					{
						$Script:HideUnavailableItems = $hideUnavailWanted
					}
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'HideUnavailableItems' -Value $hideUnavailWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist HideUnavailableItems failed') }
					}
					if ($Script:ChkHideUnavailableItems -and ($Script:ChkHideUnavailableItems.IsChecked -ne $hideUnavailWanted))
					{
						$Script:ChkHideUnavailableItems.IsChecked = $hideUnavailWanted
					}
					if (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Update-CurrentTabContent -SkipIdlePrebuild } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Refresh after HideUnavailableItems change failed') }
					}
				}
				if ($result.ContainsKey('StartupRunInitialActions'))
				{
					$startupRunInitialActionsWanted = [bool]$result.StartupRunInitialActions
					$Script:StartupRunInitialActions = $startupRunInitialActionsWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'StartupRunInitialActions' -Value $startupRunInitialActionsWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist StartupRunInitialActions failed') }
					}
				}
				if ($result.ContainsKey('StartupCheckWinGet'))
				{
					$startupCheckWinGetWanted = [bool]$result.StartupCheckWinGet
					$Script:StartupCheckWinGet = $startupCheckWinGetWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'StartupCheckWinGet' -Value $startupCheckWinGetWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist StartupCheckWinGet failed') }
					}
				}
				if ($result.ContainsKey('StartupWinGetCheckFrequency'))
				{
					$startupWinGetCheckFrequencyWanted = [string]$result.StartupWinGetCheckFrequency
					if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$startupWinGetCheckFrequencyWanted = ConvertTo-BaselineUpdateCheckFrequency -Frequency $startupWinGetCheckFrequencyWanted
					}
					$Script:StartupWinGetCheckFrequency = $startupWinGetCheckFrequencyWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'StartupWinGetCheckFrequency' -Value $startupWinGetCheckFrequencyWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist StartupWinGetCheckFrequency failed') }
					}
				}
				if ($result.ContainsKey('StartupCheckChocolatey'))
				{
					$startupCheckChocolateyWanted = [bool]$result.StartupCheckChocolatey
					$Script:StartupCheckChocolatey = $startupCheckChocolateyWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'StartupCheckChocolatey' -Value $startupCheckChocolateyWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist StartupCheckChocolatey failed') }
					}
				}
				if ($result.ContainsKey('StartupChocolateyCheckFrequency'))
				{
					$startupChocolateyCheckFrequencyWanted = [string]$result.StartupChocolateyCheckFrequency
					if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$startupChocolateyCheckFrequencyWanted = ConvertTo-BaselineUpdateCheckFrequency -Frequency $startupChocolateyCheckFrequencyWanted
					}
					$Script:StartupChocolateyCheckFrequency = $startupChocolateyCheckFrequencyWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'StartupChocolateyCheckFrequency' -Value $startupChocolateyCheckFrequencyWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist StartupChocolateyCheckFrequency failed') }
					}
				}
				try
				{
					LogDebug ('Settings startup preferences persisted. RunInitialActions={0}; CheckWinGet={1}; WinGetFrequency="{2}"; CheckChocolatey={3}; ChocolateyFrequency="{4}"' -f [bool]$Script:StartupRunInitialActions, [bool]$Script:StartupCheckWinGet, [string]$Script:StartupWinGetCheckFrequency, [bool]$Script:StartupCheckChocolatey, [string]$Script:StartupChocolateyCheckFrequency)
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'MenuHandlers.Settings.StartupPreferencesPersisted.LogDebug' -Severity Warning
				}
				if ($result.ContainsKey('AutoCheckUpdates'))
				{
					$autoCheckUpdatesWanted = [bool]$result.AutoCheckUpdates
					$Script:AutoCheckUpdates = $autoCheckUpdatesWanted
					if (-not $autoCheckUpdatesWanted -and (Get-Command -Name 'Set-BaselineUpdateCheckState' -CommandType Function -ErrorAction SilentlyContinue))
					{
						try { Set-BaselineUpdateCheckState -Status 'Disabled' -PreserveLastChecked } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist update disabled state failed') }
					}
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'AutoCheckUpdates' -Value $autoCheckUpdatesWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist AutoCheckUpdates failed') }
					}
				}
				if ($result.ContainsKey('UpdateCheckFrequency'))
				{
					$updateCheckFrequencyWanted = [string]$result.UpdateCheckFrequency
					if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$updateCheckFrequencyWanted = ConvertTo-BaselineUpdateCheckFrequency -Frequency $updateCheckFrequencyWanted
					}
					$Script:UpdateCheckFrequency = $updateCheckFrequencyWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'UpdateCheckFrequency' -Value $updateCheckFrequencyWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist UpdateCheckFrequency failed') }
					}
				}
				if ($result.ContainsKey('UpdateBranch'))
				{
					$updateBranchWanted = [string]$result.UpdateBranch
					if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$updateBranchWanted = ConvertTo-BaselineUpdateBranch -Branch $updateBranchWanted
					}
					$Script:UpdateBranch = $updateBranchWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'UpdateBranch' -Value $updateBranchWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist UpdateBranch failed') }
					}
				}
				if ($result.ContainsKey('IncludePrereleaseUpdates'))
				{
					$includePrereleaseWanted = [bool]$result.IncludePrereleaseUpdates
					$Script:IncludePrereleaseUpdates = $includePrereleaseWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'IncludePrereleaseUpdates' -Value $includePrereleaseWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist IncludePrereleaseUpdates failed') }
					}
				}
				if ($result.ContainsKey('UIDensity'))
				{
					if (Get-Command -Name 'Set-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUiDensity -Density ([string]$result.UIDensity) } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-BaselineUiDensity failed') }
					}
					else
					{
						$Script:UIDensity = [string]$result.UIDensity
					}
				}
				if ($result.ContainsKey('RequireRunConfirmation'))
				{
					$requireRunConfirmationWanted = [bool]$result.RequireRunConfirmation
					$Script:RequireRunConfirmation = $requireRunConfirmationWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'RequireRunConfirmation' -Value $requireRunConfirmationWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist RequireRunConfirmation failed') }
					}
				}
				if ($result.ContainsKey('PreviewBeforeRunDefault')) { $Script:PreviewBeforeRunDefault = [bool]$result.PreviewBeforeRunDefault }
				if ($result.ContainsKey('AppsSilentInstall')) { $Script:AppsSilentInstall = [bool]$result.AppsSilentInstall }
				if ($result.ContainsKey('AppsAutoUpdate')) { $Script:AppsAutoUpdate = [bool]$result.AppsAutoUpdate }
				if ($result.ContainsKey('LoggingEnabled')) { $Script:LoggingEnabled = [bool]$result.LoggingEnabled }
				if ($result.ContainsKey('DebugLoggingEnabled'))
				{
					$debugWanted = [bool]$result.DebugLoggingEnabled
					$Script:DebugLoggingEnabled = $debugWanted
					if (Get-Command -Name 'Set-BaselineDebugLogging' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineDebugLogging -Enabled $debugWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-BaselineDebugLogging failed') }
					}
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'DebugLoggingEnabled' -Value $debugWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist DebugLoggingEnabled failed') }
					}
					if (Get-Command -Name 'Set-GuiPerfTraceState' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Set-GuiPerfTraceState -Enabled $debugWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-GuiPerfTraceState failed') }
					}
				}
				if ($result.ContainsKey('LogLevel'))
				{
					$logLevelWanted = [string]$result.LogLevel
					if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue)
					{
						$logLevelWanted = Normalize-GuiLogLevel -Level $logLevelWanted
					}
					$Script:LogLevel = $logLevelWanted
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'LogLevel' -Value $logLevelWanted } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist LogLevel failed') }
					}
				}
				if ($result.ContainsKey('LogFileDirectory'))
				{
					$requestedLogDirectory = [string]$result.LogFileDirectory
					$defaultDirectory = if (Get-Command -Name 'Get-BaselineLogDirectory' -CommandType Function -ErrorAction SilentlyContinue)
					{
						[string](Get-BaselineLogDirectory)
					}
					else
					{
						[System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'Baseline', 'UserState', 'Logs')
					}
					$targetLogDirectory = if (Get-Command -Name 'Resolve-BaselineLogDirectory' -CommandType Function -ErrorAction SilentlyContinue)
					{
						[string](Resolve-BaselineLogDirectory -RequestedDirectory $requestedLogDirectory -DefaultDirectory $defaultDirectory)
					}
					elseif ([string]::IsNullOrWhiteSpace($requestedLogDirectory))
					{
						$defaultDirectory
					}
					else
					{
						[string]$requestedLogDirectory
					}

					$persistedLogDirectory = if ([string]::IsNullOrWhiteSpace($requestedLogDirectory)) { '' } else { $targetLogDirectory }
					$Script:LogFileDirectory = $persistedLogDirectory
					if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
					{
						try { Set-BaselineUserPreference -Key 'LogFileDirectory' -Value $persistedLogDirectory } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist LogFileDirectory failed') }
					}

					if (Get-Command -Name 'Set-LogFile' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try
						{
							$currentLogPath = if ($global:LogFilePath) { [string]$global:LogFilePath } elseif ($Script:LogFilePath) { [string]$Script:LogFilePath } else { '' }
							$nextLogPath = $null
							if (-not [string]::IsNullOrWhiteSpace($currentLogPath))
							{
								$currentFileName = [System.IO.Path]::GetFileName($currentLogPath)
								$currentParent = [System.IO.Path]::GetDirectoryName($currentLogPath)
								$currentDateFolder = if (-not [string]::IsNullOrWhiteSpace($currentParent)) { [System.IO.Path]::GetFileName($currentParent) } else { (Get-Date).ToString('yyyy-MM-dd') }
								$nextLogPath = [System.IO.Path]::Combine($targetLogDirectory, $currentDateFolder, $currentFileName)
							}
							elseif (Get-Command -Name 'New-BaselineSessionLogPath' -CommandType Function -ErrorAction SilentlyContinue)
							{
								$osNameForLog = if (Get-Command -Name 'Get-OSInfo' -CommandType Function -ErrorAction SilentlyContinue) { (Get-OSInfo).OSName } else { 'Windows' }
								$nextLogPath = New-BaselineSessionLogPath -LogDirectory $targetLogDirectory -OsName $osNameForLog
							}

							if (-not [string]::IsNullOrWhiteSpace($nextLogPath) -and -not [string]::Equals($currentLogPath, $nextLogPath, [System.StringComparison]::OrdinalIgnoreCase))
							{
								$nextLogParent = [System.IO.Path]::GetDirectoryName($nextLogPath)
								if (-not [System.IO.Directory]::Exists($nextLogParent)) { [void][System.IO.Directory]::CreateDirectory($nextLogParent) }
								if (-not [string]::IsNullOrWhiteSpace($currentLogPath) -and [System.IO.File]::Exists($currentLogPath) -and -not [System.IO.File]::Exists($nextLogPath))
								{
									[System.IO.File]::Copy($currentLogPath, $nextLogPath, $false)
								}
								$global:LogFilePath = $nextLogPath
								$Script:LogFilePath = $nextLogPath
								Set-LogFile -Path $global:LogFilePath
								LogInfo ("Settings dialog: active log folder set to '{0}'." -f $targetLogDirectory)
							}
						}
						catch
						{
							LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Apply LogFileDirectory failed')
						}
					}
				}
				if ($result.ContainsKey('DesignMode'))
				{
					$desiredDesignMode = [bool]$result.DesignMode
					if (Get-Command -Name 'Set-DesignModeState' -CommandType Function -ErrorAction SilentlyContinue)
					{
						try { Set-DesignModeState -Enabled $desiredDesignMode } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Set-DesignModeState failed') }
					}
					else
					{
						$Script:DesignMode = $desiredDesignMode
						if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
						{
							try { Set-BaselineUserPreference -Key 'DesignMode' -Value $desiredDesignMode } catch { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Persist DesignMode failed') }
						}
					}
				}

				& $setGuiStatusTextCommand -Text (Get-UxLocalizedString -Key 'GuiSettingsSavedStatus' -Fallback 'Settings saved.') -Tone 'success'
				LogInfo 'Settings dialog: preferences saved.'
				if ($runUpdateBranchCheckNow)
				{
					$updateCheckCommand = if ($showUpdateCheckDialogCommand) { $showUpdateCheckDialogCommand } else { Get-GuiRuntimeCommand -Name 'Show-BaselineUpdateCheckDialog' -CommandType 'Function' }
					if ($updateCheckCommand)
					{
						& $updateCheckCommand
					}
				}
			}
			catch
			{
				$fullErr = $_.Exception
				$chain = [System.Collections.Generic.List[string]]::new()
				while ($fullErr)
				{
					[void]$chain.Add(('{0}: {1}' -f $fullErr.GetType().FullName, $fullErr.Message))
					$fullErr = $fullErr.InnerException
				}
				$scriptTrace = if ($_.ScriptStackTrace) { [string]$_.ScriptStackTrace } else { '(no script trace)' }
				$posMsg = if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) { [string]$_.InvocationInfo.PositionMessage } else { '' }
				$detail = "{0}`n{1}`n{2}" -f ($chain -join "`n"), $scriptTrace, $posMsg
				LogError (Get-UxBilingualLocalizedString -Key 'GuiLogSettingsFailed' -Fallback 'Failed to update settings: {0}' -FormatArgs @($detail))
				[void](Show-ThemedDialog -Title 'Settings' -Message ("Failed to update settings.`n`n{0}" -f $detail) -Buttons @('OK') -AccentButton 'OK')
			}
		}) | Out-Null
	}
	if ($MenuFileAuditSettings)
	{
		Register-GuiEventHandler -Source $MenuFileAuditSettings -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$initialRetentionDays = if ($Script:AuditRetentionDays) { [int]$Script:AuditRetentionDays } else { 90 }
				$selectedRetentionDays = & $showGuiAuditSettingsDialogCommand -InitialRetentionDays $initialRetentionDays
				if ($null -eq $selectedRetentionDays) { return }

				$Script:AuditRetentionDays = [int]$selectedRetentionDays
				if ($Script:Ctx -and $Script:Ctx.UI)
				{
					$Script:Ctx.UI.AuditRetentionDays = [int]$selectedRetentionDays
				}
				& $setGuiStatusTextCommand -Text ("Audit settings saved. Retention window: {0} day(s)." -f [int]$selectedRetentionDays) -Tone 'success'
				LogInfo ("Updated audit retention window via GUI: {0} day(s)" -f [int]$selectedRetentionDays)
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogAuditSettingsFailed' -Fallback 'Failed to update audit settings'))
				[void](Show-ThemedDialog -Title 'Audit Settings' -Message ("Failed to update audit settings.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}) | Out-Null
	}
	if ($MenuFileExportConfigProfile)
	{
		Register-GuiEventHandler -Source $MenuFileExportConfigProfile -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnExportConfigProfile
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuFileExportSystemState)
	{
		Register-GuiEventHandler -Source $MenuFileExportSystemState -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnExportSystemState
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuFileExit)
	{
		Register-GuiEventHandler -Source $MenuFileExit -EventName 'Click' -Handler ({
			try
			{
				$Script:MainForm.Close()
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuFileExit.CloseMainForm'
				}
			}
		}) | Out-Null
	}

	# Actions menu
	if ($MenuActionsConnectToComputer)
	{
		Register-GuiEventHandler -Source $MenuActionsConnectToComputer -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				$connectionRequest = & $promptRemoteTargetConnectionCommand
				if (-not $connectionRequest) { return }
				$requestMethod = if ((& $hasField -Object $connectionRequest -FieldName 'ConnectionMethod') -and $connectionRequest.ConnectionMethod) { [string]$connectionRequest.ConnectionMethod } else { 'WinRM' }
				$context = & $setRemoteTargetContextCommand -ComputerName $connectionRequest.ComputerName -Credential $connectionRequest.Credential -StatusMessage 'Remote target connected.' -ConnectionMethod $requestMethod
				$targetLabel = if ($context.TargetComputers.Count -gt 0) { $context.TargetComputers -join ', ' } else { 'unknown target' }
				& $setGuiStatusTextCommand -Text ("Remote: {0}" -f $targetLabel) -Tone 'accent'
				LogInfo ("Connected remote target context: {0}" -f $targetLabel)
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogRemoteConnectFailed' -Fallback 'Failed to connect to remote target'))
				[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiRemoteConnectTitle' -Fallback 'Connect to Computer') -Message ((& $getUxLocalizedStringCapture -Key 'GuiRemoteConnectFailed' -Fallback "Failed to connect to remote target.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}) | Out-Null
	}
	if ($MenuActionsDisconnect)
	{
		Register-GuiEventHandler -Source $MenuActionsDisconnect -EventName 'Click' -Handler ({
			if (& $testGuiRunInProgressCapture) { return }
			try
			{
				if (-not (& $testRemoteTargetConnectedCommand))
				{
					[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiRemoteDisconnectTitle' -Fallback 'Disconnect') -Message (& $getUxLocalizedStringCapture -Key 'GuiRemoteDisconnectNone' -Fallback 'No remote target is currently connected.') -Buttons @('OK') -AccentButton 'OK')
					return
				}

				$context = & $getRemoteTargetContextCommand
				if ($clearRemoteSessionCacheCommand)
				{
					& $clearRemoteSessionCacheCommand -ComputerName @($context.TargetComputers)
				}
				& $clearRemoteTargetContextCommand
				$targetLabel = if ($context.TargetComputers.Count -gt 0) { $context.TargetComputers -join ', ' } else { 'remote target' }
				LogInfo ("Disconnected remote target context: {0}" -f $targetLabel)
				& $setGuiStatusTextCommand -Text (Get-UxLocalizedString -Key 'GuiRemoteDisconnected' -Fallback 'Remote target disconnected.') -Tone 'muted'
			}
			catch
			{
				LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogRemoteDisconnectFailed' -Fallback 'Failed to disconnect remote target'))
				[void](Show-ThemedDialog -Title (& $getUxLocalizedStringCapture -Key 'GuiRemoteDisconnectTitle' -Fallback 'Disconnect') -Message ((& $getUxLocalizedStringCapture -Key 'GuiRemoteDisconnectFailed' -Fallback "Failed to disconnect remote target.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
			}
		}) | Out-Null
	}
	if ($Script:BtnRemoteModeBannerDisconnect)
	{
		Register-GuiEventHandler -Source $Script:BtnRemoteModeBannerDisconnect -EventName 'Click' -Handler ({
			# Banner button shares the menu's Disconnect handler — raise its Click
			# so any wiring (telemetry / future hooks) flows through one path.
			if ($Script:MenuActionsDisconnect)
			{
				try { $Script:MenuActionsDisconnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent)) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuActionsDisconnect.RaiseEvent' }
			}
		}) | Out-Null
	}
	if ($MenuActionsPreviewRun)
	{
		Register-GuiEventHandler -Source $MenuActionsPreviewRun -EventName 'Click' -Handler ({
			& $raiseButtonClick $BtnPreviewRun
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuActionsRunTweaks)
	{
		Register-GuiEventHandler -Source $MenuActionsRunTweaks -EventName 'Click' -Handler ({
			& $raiseButtonClick $BtnRun
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuActionsUndoLastRun)
	{
		Register-GuiEventHandler -Source $MenuActionsUndoLastRun -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnUndoLastRun
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuActionsRestoreDefaults)
	{
		Register-GuiEventHandler -Source $MenuActionsRestoreDefaults -EventName 'Click' -Handler ({
			& $raiseButtonClick $BtnDefaults
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuActionsCheckCompliance)
	{
		Register-GuiEventHandler -Source $MenuActionsCheckCompliance -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnCheckCompliance
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuActionsAuditLog)
	{
		Register-GuiEventHandler -Source $MenuActionsAuditLog -EventName 'Click' -Handler ({
			& $raiseButtonClick $Script:BtnAuditLog
		}.GetNewClosure()) | Out-Null
	}
	# Scan System - matches ChkScan checkbox
	if ($MenuActionsScanSystem -and $ChkScan)
	{
		try { $MenuActionsScanSystem.IsChecked = [bool]$ChkScan.IsChecked } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuActionsScanSystem.SetChecked' }
		Register-GuiEventHandler -Source $MenuActionsScanSystem -EventName 'Click' -Handler ({
			try { $ChkScan.IsChecked = [bool]$MenuActionsScanSystem.IsChecked } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuActionsScanSystem.SyncClick' }
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $ChkScan -EventName 'Checked' -Handler ({
			try { $MenuActionsScanSystem.IsChecked = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuActionsScanSystem.Checked' }
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $ChkScan -EventName 'Unchecked' -Handler ({
			try { $MenuActionsScanSystem.IsChecked = $false } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuActionsScanSystem.Unchecked' }
		}.GetNewClosure()) | Out-Null
	}

	if ($MenuViewFilters -and $BtnFilterToggle)
	{
		Register-GuiEventHandler -Source $MenuViewFilters -EventName 'Click' -Handler ({
			& $raiseButtonClick $BtnFilterToggle
			try { $MenuViewFilters.IsChecked = ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Visible) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuViewFilters.SetChecked' }
		}.GetNewClosure()) | Out-Null
	}
	# Open Logs - opens the log dialog (BtnLog handler)
	if ($MenuViewLogsPanel)
	{
		Register-GuiEventHandler -Source $MenuViewLogsPanel -EventName 'Click' -Handler ({
			& $raiseButtonClick $BtnLog
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuViewTheme -and $ChkTheme)
	{
		try { $MenuViewTheme.IsChecked = [bool]$ChkTheme.IsChecked } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuViewTheme.SetChecked' }
		Register-GuiEventHandler -Source $MenuViewTheme -EventName 'Click' -Handler ({
			try { $ChkTheme.IsChecked = [bool]$MenuViewTheme.IsChecked } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuViewTheme.SyncClick' }
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $ChkTheme -EventName 'Checked' -Handler ({
			try { $MenuViewTheme.IsChecked = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuViewTheme.Checked' }
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $ChkTheme -EventName 'Unchecked' -Handler ({
			try { $MenuViewTheme.IsChecked = $false } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuViewTheme.Unchecked' }
		}.GetNewClosure()) | Out-Null
	}

	# Tools menu
	if ($MenuToolsAppsManager -and $NavModeApps)
	{
		Register-GuiEventHandler -Source $MenuToolsAppsManager -EventName 'Click' -Handler ({
			try { $NavModeApps.IsChecked = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuToolsAppsManager.Checked' }
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuToolsUpdateAllApps -and $BtnUpdateAllApps)
	{
		Register-GuiEventHandler -Source $MenuToolsUpdateAllApps -EventName 'Click' -Handler ({
			try { $NavModeApps.IsChecked = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.SyncMenuState.MenuToolsUpdateAllApps.Checked' }
			& $raiseButtonClick $BtnUpdateAllApps
		}.GetNewClosure()) | Out-Null
	}
	if (Get-Command -Name 'Initialize-GuiDeveloperDiagnosticsMenu' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Initialize-GuiDeveloperDiagnosticsMenu
	}
	# Help menu
	if ($MenuHelpHelp)
	{
		$openHelpDialogFromMenu = {
			try
			{
				if ($showHelpDialogCommand)
				{
					& $showHelpDialogCommand
					& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiHelpOpened' -Fallback 'Help opened.') -Tone 'accent'
					return
				}

				$runtimeHelpDialogCommand = Get-GuiRuntimeCommand -Name 'Show-HelpDialog' -CommandType 'Function'
				if ($runtimeHelpDialogCommand)
				{
					& $runtimeHelpDialogCommand
					& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiHelpOpened' -Fallback 'Help opened.') -Tone 'accent'
					return
				}

				throw 'Show-HelpDialog not found.'
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Help menu open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpHelp.LogWarning'
					}
				}
				if ($showThemedDialogCommand)
				{
					try
					{
						[void](& $showThemedDialogCommand -Title 'Help' -Message 'The Help dialog could not be opened. Check the log for details.' -Buttons @('OK') -AccentButton 'OK')
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
						{
							Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpHelp.ShowFailureDialog'
						}
					}
				}
			}
		}.GetNewClosure()
		$MenuHelpHelp.Add_Click($openHelpDialogFromMenu)
	}
	if ($MenuHelpStartGuide)
	{
		Register-GuiEventHandler -Source $MenuHelpStartGuide -EventName 'Click' -Handler ({
			try
			{
				& $raiseButtonClick $Script:BtnStartHere
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Quick Start menu open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpGettingStarted.LogWarning'
					}
				}
			}
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuHelpReadme)
	{
		Register-GuiEventHandler -Source $MenuHelpReadme -EventName 'Click' -Handler ({
			try
			{
				if ($showReadmeDialogCommand)
				{
					& $showReadmeDialogCommand
				}
				else
				{
					throw 'Show-ReadmeDialog not found.'
				}
				& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiMenuHelpReadmeOpened' -Fallback 'Readme opened in the themed popup.') -Tone 'accent'
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Readme open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpReadme.LogWarning'
					}
				}
				if ($showThemedDialogCommand)
				{
					try
					{
						$errTitle = & $getUxLocalizedStringCapture -Key 'GuiMenuHelpReadme' -Fallback 'Readme'
						$errMsg = & $getUxLocalizedStringCapture -Key 'GuiMenuHelpReadmeFailed' -Fallback 'Unable to open the README popup. Check the installed directory for README.md.'
						[void](& $showThemedDialogCommand -Title $errTitle -Message $errMsg -Buttons @('OK') -AccentButton 'OK')
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
						{
							Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpReadme.ShowThemedDialog'
						}
					}
				}
			}
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuHelpFAQ)
	{
		Register-GuiEventHandler -Source $MenuHelpFAQ -EventName 'Click' -Handler ({
			try
			{
				if ($showGuiFaqDialogCommand)
				{
					& $showGuiFaqDialogCommand
				}
				else
				{
					throw 'Show-GuiFaqDialog not found.'
				}
				& $setGuiStatusTextCommand -Text (& $getUxLocalizedStringCapture -Key 'GuiMenuHelpFAQOpened' -Fallback 'FAQ opened in the themed popup.') -Tone 'accent'
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'FAQ open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpFAQ.LogWarning'
					}
				}
			}
		}.GetNewClosure()) | Out-Null
	}
	if ($MenuHelpChangelog)
	{
		Register-GuiEventHandler -Source $MenuHelpChangelog -EventName 'Click' -Handler ({
			try
			{
				if ($showChangelogDialogCommand)
				{
					& $showChangelogDialogCommand
				}
				else
				{
					[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiMenuHelpChangelog' -Fallback 'Changelog') -Message (Get-UxLocalizedString -Key 'GuiMenuHelpChangelogMissing' -Fallback 'Changelog file not found.') -Buttons @('OK') -AccentButton 'OK')
				}
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Changelog open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpChangelog.LogWarning'
					}
				}
			}
		}) | Out-Null
	}
	if ($MenuHelpCheckForUpdate)
	{
		Register-GuiEventHandler -Source $MenuHelpCheckForUpdate -EventName 'Click' -Handler ({
			try
			{
				if ($showUpdateCheckDialogCommand)
				{
					& $showUpdateCheckDialogCommand
				}
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Update check open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpUpdateCheck.LogWarning'
					}
				}
			}
		}) | Out-Null
	}
	if ($MenuHelpReleaseStatus)
	{
		Register-GuiEventHandler -Source $MenuHelpReleaseStatus -EventName 'Click' -Handler ({
			try
			{
				if ($showGuiReleaseStatusDialogCommand)
				{
					& $showGuiReleaseStatusDialogCommand
				}
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Release status open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpReleaseStatus.LogWarning'
					}
				}
			}
		}) | Out-Null
	}
	if ($MenuHelpTroubleshooting)
	{
		Register-GuiEventHandler -Source $MenuHelpTroubleshooting -EventName 'Click' -Handler ({
			try
			{
				if ($showGuiTroubleshootingGuideDialogCommand)
				{
					& $showGuiTroubleshootingGuideDialogCommand
				}
			}
			catch
			{
				try
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Troubleshooting guide open failed')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpTroubleshooting.LogWarning'
					}
				}
			}
		}) | Out-Null
	}
	if ($MenuHelpAbout)
	{
		Register-GuiEventHandler -Source $MenuHelpAbout -EventName 'Click' -Handler ({
			try
			{
				$aboutTitle = Get-UxLocalizedString -Key 'GuiMenuHelpAbout' -Fallback 'About Baseline'
				$version = 'unknown'
				try { $version = Get-BaselineDisplayVersion } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpAbout.GetDisplayVersion' }
				$msg = "Baseline`nVersion: $version`n`nA Windows utility for system configuration and optimization."
				[void](Show-ThemedDialog -Title $aboutTitle -Message $msg -Buttons @('OK') -AccentButton 'OK')
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'ActionHandlers.MenuHelpAbout.ShowThemedDialog'
				}
			}
		}) | Out-Null
	}

	# Apply localization to menu headers
	if ($MenuFile)                     { $MenuFile.Header                     = (Get-UxLocalizedString -Key 'GuiMenuFile' -Fallback '_File') }
	if ($MenuActions)                  { $MenuActions.Header                  = (Get-UxLocalizedString -Key 'GuiMenuActions' -Fallback '_Actions') }
	if ($MenuView)                     { $MenuView.Header                     = (Get-UxLocalizedString -Key 'GuiMenuView' -Fallback '_View') }
	if ($MenuTools)                    { $MenuTools.Header                    = (Get-UxLocalizedString -Key 'GuiMenuTools' -Fallback '_Tools') }
	if ($MenuHelp)                     { $MenuHelp.Header                     = (Get-UxLocalizedString -Key 'GuiMenuHelp' -Fallback '_Help') }
	if ($MenuFileImportSettings)       { $MenuFileImportSettings.Header       = (Get-UxLocalizedString -Key 'GuiMenuFileImportSettings' -Fallback 'Import Settings...') }
	if ($MenuFileExportSettings)       { $MenuFileExportSettings.Header       = (Get-UxLocalizedString -Key 'GuiMenuFileExportSettings' -Fallback 'Export Settings...') }
	if ($MenuFileAuditSettings)        { $MenuFileAuditSettings.Header        = (Get-UxLocalizedString -Key 'GuiMenuFileAuditSettings' -Fallback 'Audit Settings...') }
	if ($MenuFileExportConfigProfile)  { $MenuFileExportConfigProfile.Header  = (Get-UxLocalizedString -Key 'GuiMenuFileExportConfigProfile' -Fallback 'Export Config Profile...') }
	if ($MenuFileExportSystemState)    { $MenuFileExportSystemState.Header    = (Get-UxLocalizedString -Key 'GuiMenuFileExportSystemState' -Fallback 'Export System State...') }
	if ($MenuFileExit)                 { $MenuFileExit.Header                 = (Get-UxLocalizedString -Key 'GuiMenuFileExit' -Fallback 'E_xit') }
	if ($MenuActionsPreviewRun)        { $MenuActionsPreviewRun.Header        = (Get-UxLocalizedString -Key 'GuiMenuActionsPreviewRun' -Fallback 'Preview Run') }
	if ($MenuActionsRunTweaks)         { $MenuActionsRunTweaks.Header         = (Get-UxRunActionLabel) }
	if ($MenuActionsUndoLastRun)       { $MenuActionsUndoLastRun.Header       = (Get-UxLocalizedString -Key 'GuiMenuActionsUndoLastRun' -Fallback 'Undo Last Run') }
	if ($MenuActionsRestoreDefaults)   { $MenuActionsRestoreDefaults.Header   = (Get-UxLocalizedString -Key 'GuiMenuActionsRestoreDefaults' -Fallback 'Restore Defaults') }
	if ($MenuActionsCheckCompliance)   { $MenuActionsCheckCompliance.Header   = (Get-UxLocalizedString -Key 'GuiMenuActionsCheckCompliance' -Fallback 'Check Compliance...') }
	if ($MenuActionsScanSystem)        { $MenuActionsScanSystem.Header        = (Get-UxLocalizedString -Key 'GuiMenuActionsScanSystem' -Fallback 'Scan System') }
	if ($MenuActionsAuditLog)          { $MenuActionsAuditLog.Header          = (Get-UxLocalizedString -Key 'GuiMenuActionsAuditLog' -Fallback 'Audit Log...') }
	if ($MenuViewFilters)              { $MenuViewFilters.Header              = (Get-UxLocalizedString -Key 'GuiMenuViewFilters' -Fallback 'Show Filters Panel') }
	if ($MenuViewLogsPanel)            { $MenuViewLogsPanel.Header            = (Get-UxLocalizedString -Key 'GuiMenuViewOpenLogs' -Fallback 'Open Logs') }
	if ($MenuViewTheme)
	{
		$MenuViewTheme.Header = if ($ChkTheme -and $ChkTheme.IsChecked -eq $true)
		{
			(Get-UxLocalizedString -Key 'GuiMenuViewSwitchToDarkMode' -Fallback 'Switch to Dark Mode')
		}
		else
		{
			(Get-UxLocalizedString -Key 'GuiMenuViewSwitchToLightMode' -Fallback 'Switch to Light Mode')
		}
	}
	if ($MenuToolsAppsManager)         { $MenuToolsAppsManager.Header         = (Get-UxLocalizedString -Key 'GuiMenuToolsAppsManager' -Fallback 'Apps Manager') }
	if ($MenuToolsUpdateAllApps)       { $MenuToolsUpdateAllApps.Header       = (Get-UxLocalizedString -Key 'GuiMenuToolsUpdateAllApps' -Fallback 'Update All Applications') }
	if ($MenuToolsDeveloperDiagnostics) { $MenuToolsDeveloperDiagnostics.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnostics' -Fallback 'Developer Diagnostics') }
	if ($MenuToolsDeveloperDiagnosticsGenerateReport) { $MenuToolsDeveloperDiagnosticsGenerateReport.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsGenerateReport' -Fallback 'Generate Test Report') }
	if ($MenuToolsDeveloperDiagnosticsSourceQuality) { $MenuToolsDeveloperDiagnosticsSourceQuality.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsSourceQuality' -Fallback 'Run Source Quality Guards') }
	if ($MenuToolsDeveloperDiagnosticsUnitTests) { $MenuToolsDeveloperDiagnosticsUnitTests.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsUnitTests' -Fallback 'Run Unit Tests') }
	if ($MenuToolsDeveloperDiagnosticsGuiComposition) { $MenuToolsDeveloperDiagnosticsGuiComposition.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsGuiComposition' -Fallback 'Run GUI Composition Tests') }
	if ($MenuToolsDeveloperDiagnosticsOpenLatestReport) { $MenuToolsDeveloperDiagnosticsOpenLatestReport.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsOpenLatestReport' -Fallback 'Open Latest Test Report') }
	if ($MenuToolsDeveloperDiagnosticsCopyCommands) { $MenuToolsDeveloperDiagnosticsCopyCommands.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsCopyCommands' -Fallback 'Copy PowerShell Commands') }
	if ($MenuToolsDeveloperDiagnosticsIntegrationTests) { $MenuToolsDeveloperDiagnosticsIntegrationTests.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsIntegrationTests' -Fallback 'Run Integration Tests...') }
	if ($MenuToolsExportSupportBundle) { $MenuToolsExportSupportBundle.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsExportSupportBundle' -Fallback 'Export Support Bundle...') }
	if ($MenuToolsApproveRemoteTargets){ $MenuToolsApproveRemoteTargets.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsApproveRemoteTargets' -Fallback 'Approve Target List...') }
	if ($MenuToolsSaveRemoteApprovalPolicy){ $MenuToolsSaveRemoteApprovalPolicy.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsSaveRemoteApprovalPolicy' -Fallback 'Save Remote Approval Policy...') }
	if ($MenuToolsLoadRemoteApprovalPolicy){ $MenuToolsLoadRemoteApprovalPolicy.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsLoadRemoteApprovalPolicy' -Fallback 'Load Remote Approval Policy...') }
	if ($MenuToolsRemoteConsole)       { $MenuToolsRemoteConsole.Header       = (Get-UxLocalizedString -Key 'GuiMenuToolsRemoteConsole' -Fallback 'Remote Console...') }
	if ($MenuToolsOperatorConsole)     { $MenuToolsOperatorConsole.Header     = (Get-UxLocalizedString -Key 'GuiMenuToolsOperatorConsole' -Fallback 'Operator Console...') }
	if ($MenuToolsRemoteSessionStatus) { $MenuToolsRemoteSessionStatus.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsRemoteSessionStatus' -Fallback 'Remote Session Status...') }
	if ($MenuHelpHelp)                 { $MenuHelpHelp.Header                 = (Get-UxLocalizedString -Key 'GuiMenuHelpHelp' -Fallback 'Help') }
	if ($MenuHelpStartGuide)           { $MenuHelpStartGuide.Header           = (Get-UxLocalizedString -Key 'GuiMenuHelpStartGuide' -Fallback 'Quick Start') }
	if ($MenuHelpReadme)               { $MenuHelpReadme.Header               = (Get-UxLocalizedString -Key 'GuiMenuHelpReadme' -Fallback 'Readme') }
	if ($MenuHelpFAQ)                  { $MenuHelpFAQ.Header                  = (Get-UxLocalizedString -Key 'GuiMenuHelpFAQ' -Fallback 'FAQ') }
	if ($MenuHelpChangelog)            { $MenuHelpChangelog.Header            = (Get-UxLocalizedString -Key 'GuiMenuHelpChangelog' -Fallback 'Changelog') }
	if ($MenuHelpCheckForUpdate)       { $MenuHelpCheckForUpdate.Header       = (Get-UxLocalizedString -Key 'GuiMenuHelpCheckForUpdate' -Fallback 'Check for Updates...') }
	if ($MenuHelpReleaseStatus)       { $MenuHelpReleaseStatus.Header       = (Get-UxLocalizedString -Key 'GuiMenuHelpReleaseStatus' -Fallback 'Release Status...') }
	if ($MenuHelpTroubleshooting)     { $MenuHelpTroubleshooting.Header     = (Get-UxLocalizedString -Key 'GuiMenuHelpTroubleshooting' -Fallback 'Troubleshooting Guide...') }
	if ($MenuHelpAbout)                { $MenuHelpAbout.Header                = (Get-UxLocalizedString -Key 'GuiMenuHelpAbout' -Fallback 'About Baseline') }

	# Hide duplicated toolbar/header buttons now that menus expose them (Phase 2 cleanup).
	# Kept in tree (not removed) so all existing wiring / theming / snapshots continue to work.
	Update-GuiDuplicateActionVisibility
	#endregion Top Menu Bar handlers
