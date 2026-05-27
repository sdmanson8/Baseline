if ($btnSave)
		{
			$btnSave.Content = $saveLabel
			Set-ButtonChrome -Button $btnSave -Variant 'Primary'
			$btnSave.IsDefault = $true
			$btnSave.Add_Click({
				$getTag = {
					param ($combo, $default)
					if ($combo -and $combo.SelectedItem -and $null -ne $combo.SelectedItem.Tag)
					{
						return $combo.SelectedItem.Tag
					}
					return $default
				}

				$selectedLanguage = if ($settingsLanguageState -and $settingsLanguageState.Code) { [string]$settingsLanguageState.Code } else { 'en' }
				$defaultUpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
				$resultRef.Value = @{
					Language = $selectedLanguage
					DefaultStartupMode = [string](& $getTag $cmbDefaultStartupMode 'Safe')
					RestoreLastSession = [bool]$chkRestoreLastSession.IsChecked
					AutoScanOnLaunch = [bool]$chkAutoScanOnLaunch.IsChecked
					HideUnavailableItems = if ($chkHideUnavailableItems) { [bool]$chkHideUnavailableItems.IsChecked } else { $true }
					StartupRunInitialActions = if ($chkStartupRunInitialActions) { [bool]$chkStartupRunInitialActions.IsChecked } else { $true }
					StartupCheckWinGet = if ($chkStartupCheckWinGet) { [bool]$chkStartupCheckWinGet.IsChecked } else { $true }
					StartupWinGetCheckFrequency = [string](& $getTag $cmbStartupWinGetCheckFrequency 'Startup')
					StartupCheckChocolatey = if ($chkStartupCheckChocolatey) { [bool]$chkStartupCheckChocolatey.IsChecked } else { $true }
					StartupChocolateyCheckFrequency = [string](& $getTag $cmbStartupChocolateyCheckFrequency 'Startup')
					AutoCheckUpdates = if ($chkAutoCheckUpdates) { [bool]$chkAutoCheckUpdates.IsChecked } else { $true }
					UpdateCheckFrequency = [string](& $getTag $cmbUpdateFrequency 'Startup')
					UpdateBranch = [string](& $getTag $cmbUpdateBranch $defaultUpdateBranch)
					IncludePrereleaseUpdates = if ($chkIncludePrereleaseUpdates) { [bool]$chkIncludePrereleaseUpdates.IsChecked } else { $false }
					Theme = [string](& $getTag $cmbTheme 'System')
					UIDensity = [string](& $getTag $cmbUIDensity 'Comfort')
					SafeMode = [bool]$chkSafeModeDefault.IsChecked
					RequireRunConfirmation = [bool]$chkRequireRunConfirmation.IsChecked
					PreviewBeforeRunDefault = [bool]$chkPreviewBeforeRunDefault.IsChecked
					AuditRetentionDays = [int](& $getTag $cmbAuditRetention 90)
					AppsPackageSourcePreference = [string](& $getTag $cmbPackageSource 'auto')
					AppsSilentInstall = [bool]$chkAppsSilentInstall.IsChecked
					AppsAutoUpdate = [bool]$chkAppsAutoUpdate.IsChecked
					LoggingEnabled = [bool]$chkLoggingEnabled.IsChecked
					DebugLoggingEnabled = [bool]$chkDebugLogging.IsChecked
					LogLevel = [string](& $getTag $cmbLogLevel 'All')
					LogFileDirectory = if ($chkAdvancedMode -and [bool]$chkAdvancedMode.IsChecked -and -not [string]::IsNullOrWhiteSpace([string]$settingsLogState.CustomDirectory)) { [string]$settingsLogState.CustomDirectory } else { '' }
					AdvancedMode = [bool]$chkAdvancedMode.IsChecked
					DesignMode = [bool]$chkDesignMode.IsChecked
				}
				try
				{
					LogDebug ('Settings dialog startup controls captured. RunInitialActions={0}; CheckWinGet={1}; WinGetFrequency="{2}"; CheckChocolatey={3}; ChocolateyFrequency="{4}"' -f [bool]$resultRef.Value.StartupRunInitialActions, [bool]$resultRef.Value.StartupCheckWinGet, [string]$resultRef.Value.StartupWinGetCheckFrequency, [bool]$resultRef.Value.StartupCheckChocolatey, [string]$resultRef.Value.StartupChocolateyCheckFrequency)
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'SettingsDialog.Save.StartupControls.LogDebug' -Severity Warning
				}
				$dlg.Close()
			}.GetNewClosure())
		}
