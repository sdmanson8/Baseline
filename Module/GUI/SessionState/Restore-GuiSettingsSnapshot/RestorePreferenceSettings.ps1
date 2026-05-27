try
		{
			$Script:AutoScanOnLaunch = $desiredAutoScanOnLaunch
			$Script:RestoreLastSession = $desiredRestoreLastSession
			$Script:StartupRunInitialActions = $desiredStartupRunInitialActions
			$Script:StartupCheckWinGet = $desiredStartupCheckWinGet
			$Script:StartupWinGetCheckFrequency = $desiredStartupWinGetCheckFrequency
			$Script:StartupCheckChocolatey = $desiredStartupCheckChocolatey
			$Script:StartupChocolateyCheckFrequency = $desiredStartupChocolateyCheckFrequency
			$Script:AutoCheckUpdates = $desiredAutoCheckUpdates
			$Script:UpdateCheckFrequency = $desiredUpdateCheckFrequency
			$Script:UpdateBranch = $desiredUpdateBranch
			$Script:IncludePrereleaseUpdates = $desiredIncludePrereleaseUpdates
			$Script:ScanEnabled = $desiredScan
			$Script:EnvironmentRecommendationData = $null
			$Script:EnvironmentSummaryText = $null
			if ($ChkScan)
			{
				if ($ChkScan.IsChecked -ne $desiredScan)
				{
					$ChkScan.IsChecked = $desiredScan
				}
			}

			$desiredViewMode = if ($desiredSafe) { 'Safe' } elseif ($desiredAdvanced) { 'Expert' } else { 'Standard' }
			if (Get-Command -Name 'Set-GuiMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiMode -ViewMode $desiredViewMode -GameMode $desiredGameMode
			}
			else
			{
				$Script:SafeMode = $desiredSafe
				$Script:AdvancedMode = $desiredAdvanced
				$Script:GameMode = $desiredGameMode
				if ($Script:Ctx)
				{
					if (-not $Script:Ctx.ContainsKey('Mode'))
					{
						$Script:Ctx['Mode'] = @{ Safe = $false; Expert = $false; Game = $false; Design = $false; Scenario = $null }
					}
					$Script:Ctx.Mode.Safe = $desiredSafe
					$Script:Ctx.Mode.Expert = $desiredAdvanced
					$Script:Ctx.Mode.Game = $desiredGameMode
				}
			}
			$Script:DefaultStartupMode = $desiredDefaultStartupMode
			if (Get-Command -Name 'Set-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { Set-BaselineUserPreference -Key 'Theme' -Value $desiredTheme } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveThemePreference' }
				try { Set-BaselineUserPreference -Key 'DefaultStartupMode' -Value $Script:DefaultStartupMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveDefaultStartupModePreference' }
				try { Set-BaselineUserPreference -Key 'UIDensity' -Value $desiredUiDensity } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveUIDensityPreference' }
				try { Set-BaselineUserPreference -Key 'DebugLoggingEnabled' -Value $desiredDebugLoggingEnabled } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveDebugLoggingPreference' }
				try { Set-BaselineUserPreference -Key 'LogLevel' -Value $desiredLogLevel } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveLogLevelPreference' }
				try { Set-BaselineUserPreference -Key 'StartupRunInitialActions' -Value $desiredStartupRunInitialActions } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveStartupRunInitialActionsPreference' }
				try { Set-BaselineUserPreference -Key 'StartupCheckWinGet' -Value $desiredStartupCheckWinGet } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveStartupCheckWinGetPreference' }
				try { Set-BaselineUserPreference -Key 'StartupWinGetCheckFrequency' -Value $desiredStartupWinGetCheckFrequency } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveStartupWinGetCheckFrequencyPreference' }
				try { Set-BaselineUserPreference -Key 'StartupCheckChocolatey' -Value $desiredStartupCheckChocolatey } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveStartupCheckChocolateyPreference' }
				try { Set-BaselineUserPreference -Key 'StartupChocolateyCheckFrequency' -Value $desiredStartupChocolateyCheckFrequency } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveStartupChocolateyCheckFrequencyPreference' }
				if ($hasSnapshotUpdateSettings -and -not $preserveDurablePreferences)
				{
					try { Set-BaselineUserPreference -Key 'AutoCheckUpdates' -Value $desiredAutoCheckUpdates } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveAutoCheckUpdatesPreference' }
					try { Set-BaselineUserPreference -Key 'UpdateCheckFrequency' -Value $desiredUpdateCheckFrequency } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveUpdateCheckFrequencyPreference' }
					try { Set-BaselineUserPreference -Key 'UpdateBranch' -Value $desiredUpdateBranch } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveUpdateBranchPreference' }
					try { Set-BaselineUserPreference -Key 'IncludePrereleaseUpdates' -Value $desiredIncludePrereleaseUpdates } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SessionState.RestoreGuiSettingsSnapshot.SaveIncludePrereleaseUpdatesPreference' }
				}
			}
			$Script:UIDensity = $desiredUiDensity
			$Script:RowContextShared = $null
			$Script:RowContextSharedTheme = $null
			$Script:RowContextSharedDensity = $null
			if (Get-Command -Name 'Set-TweakRowFactoryDensityTokens' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-TweakRowFactoryDensityTokens
			}
			if ($ExpertModeBanner)
			{
				$ExpertModeBanner.Visibility = if ($desiredAdvanced) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			}
			$modeHidden = if ($desiredSafe) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			if ($BtnLog) { $BtnLog.Visibility = [System.Windows.Visibility]::Collapsed }
			if ($BtnFilterToggle) { $BtnFilterToggle.Visibility = $modeHidden }
			if ($ChkScan) { $ChkScan.Visibility = $modeHidden }
			if ($Script:MenuTools) { $Script:MenuTools.Visibility = [System.Windows.Visibility]::Visible }
			if ($Script:MenuToolsAppsManager) { $Script:MenuToolsAppsManager.Visibility = [System.Windows.Visibility]::Visible }
			if ($Script:MenuToolsUpdateAllApps) { $Script:MenuToolsUpdateAllApps.Visibility = [System.Windows.Visibility]::Visible }
			if ($Script:MenuToolsApproveRemoteTargets) { $Script:MenuToolsApproveRemoteTargets.Visibility = $modeHidden }
			if ($Script:MenuToolsSaveRemoteApprovalPolicy) { $Script:MenuToolsSaveRemoteApprovalPolicy.Visibility = $modeHidden }
			if ($Script:MenuToolsLoadRemoteApprovalPolicy) { $Script:MenuToolsLoadRemoteApprovalPolicy.Visibility = $modeHidden }
			if ($Script:MenuToolsRemoteConsole) { $Script:MenuToolsRemoteConsole.Visibility = $modeHidden }
			if ($Script:MenuToolsOperatorConsole) { $Script:MenuToolsOperatorConsole.Visibility = $modeHidden }
			if ($Script:MenuToolsRemoteSessionStatus) { $Script:MenuToolsRemoteSessionStatus.Visibility = $modeHidden }
			if ($Script:MenuToolsRemovalPersistence) { $Script:MenuToolsRemovalPersistence.Visibility = $modeHidden }
			if ($Script:MenuToolsSepApps) { $Script:MenuToolsSepApps.Visibility = $modeHidden }
			if ($Script:MenuToolsExportSupportBundle) { $Script:MenuToolsExportSupportBundle.Visibility = [System.Windows.Visibility]::Visible }
			if ($Script:MenuActionsCheckCompliance) { $Script:MenuActionsCheckCompliance.Visibility = $modeHidden }
			if ($Script:MenuActionsScanSystem) { $Script:MenuActionsScanSystem.Visibility = $modeHidden }
			if ($Script:MenuActionsAuditLog) { $Script:MenuActionsAuditLog.Visibility = $modeHidden }
			if ($Script:MenuViewFilters) { $Script:MenuViewFilters.Visibility = $modeHidden }
			if ($Script:MenuFileExportSystemState) { $Script:MenuFileExportSystemState.Visibility = $modeHidden }
			if ($Script:MenuFileExportConfigProfile) { $Script:MenuFileExportConfigProfile.Visibility = $modeHidden }

			$Script:GameMode = $desiredGameMode
			$Script:GameModeProfile = if ([string]::IsNullOrWhiteSpace($desiredGameModeProfile)) { $null } else { $desiredGameModeProfile }
			$Script:GameModeCorePlan = @($desiredGameModeCorePlan)
			$Script:GameModePlan = @($desiredGameModePlan)
			$Script:GameModeDecisionOverrides = @{}
			foreach ($overrideKey in @($desiredGameModeDecisionOverrides.Keys))
			{
				if ([string]::IsNullOrWhiteSpace([string]$overrideKey)) { continue }
				$Script:GameModeDecisionOverrides[[string]$overrideKey] = [string]$desiredGameModeDecisionOverrides[$overrideKey]
			}
			$Script:GameModeAdvancedSelections = @{}
			foreach ($advSelKey in @($desiredGameModeAdvancedSelections.Keys))
			{
				if ([string]::IsNullOrWhiteSpace([string]$advSelKey)) { continue }
				$Script:GameModeAdvancedSelections[[string]$advSelKey] = [bool]$desiredGameModeAdvancedSelections[$advSelKey]
			}

			$Script:RiskFilter = $desiredRisk
			if ($CmbRiskFilter)
			{
				if ($Script:RiskFilterInternalValues -and $Script:RiskFilterInternalValues.Contains($desiredRisk))
				{
					$found = $Script:RiskFilterInternalValues.IndexOf($desiredRisk)
					if ($found -ge 0) { $CmbRiskFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbRiskFilter.SelectedIndex = $idx
					$Script:RiskFilter = 'All'
				}
			}

			$Script:PlatformFilter = $desiredPlatform
			$Script:HideUnavailableItems = $desiredHideUnavailableItems
			if ($ChkHideUnavailableItems) { $ChkHideUnavailableItems.IsChecked = $desiredHideUnavailableItems }
			$Script:SelectedOnlyFilter = $desiredSelectedOnly
			if ($ChkSelectedOnly) { $ChkSelectedOnly.IsChecked = $desiredSelectedOnly }
			$Script:HighRiskOnlyFilter = $desiredHighRiskOnly
			if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsChecked = $desiredHighRiskOnly }
			$Script:RestorableOnlyFilter = $desiredRestorableOnly
			if ($ChkRestorableOnly) { $ChkRestorableOnly.IsChecked = $desiredRestorableOnly }
			$Script:GamingOnlyFilter = $desiredGamingOnly
			if ($ChkGamingOnly) { $ChkGamingOnly.IsChecked = $desiredGamingOnly }
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
