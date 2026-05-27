if ($btnClearCache)
		{
			$btnClearCache.Add_Click({
				try
				{
					$selection = & $showGuiClearCacheDialog `
						-Theme $theme `
						-Title $settingsClearCacheDialogTitle `
						-Message $settingsClearCacheDialogMessage `
						-TemporaryCacheFilesLabel $settingsClearCacheTemporaryFilesLabel `
						-WorkingFilesLabel $settingsClearCacheWorkingFilesLabel `
						-LogsLabel $settingsClearCacheLogsLabel `
						-AuditHistoryLabel $settingsClearCacheAuditHistoryLabel `
						-SavedSessionStateLabel $settingsClearCacheSavedSessionLabel `
						-SavedSessionStateDescription $settingsClearCacheSavedSessionDescription `
						-CancelLabel $cancelLabel `
						-ClearSelectedLabel $settingsClearSelectedLabel
					if (-not $selection) { return }

					$result = & $clearGuiBaselineStorageCache `
						-TemporaryCacheFiles ([bool]$selection.TemporaryCacheFiles) `
						-WorkingFiles ([bool]$selection.WorkingFiles) `
						-Logs ([bool]$selection.Logs) `
						-AuditHistory ([bool]$selection.AuditHistory) `
						-SavedSessionState ([bool]$selection.SavedSessionState) `
						-LogDirectory (& $getEffectiveLogDirectory)

					& $refreshStorageDisplay
					$reclaimed = [Int64]$result.Before - [Int64]$result.After
					if ($reclaimed -lt 0) { $reclaimed = 0 }
					[void](& $showThemedDialog -Title $settingsClearCacheLabel -Message ($settingsClearCacheRemoved -f (& $formatGuiStorageSize -Bytes $reclaimed)) -Buttons @($okLabel) -AccentButton $okLabel)
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.ClearCache'
					[void](& $showThemedDialog -Title $settingsClearCacheLabel -Message ($settingsClearCacheFailed -f $_.Exception.Message) -Buttons @($okLabel) -AccentButton $okLabel)
				}
			}.GetNewClosure())
		}

		$syncStartupMode = {
			param ([switch]$InitialLoad)
			if (-not $cmbDefaultStartupMode -or -not $cmbDefaultStartupMode.SelectedItem) { return }
			$selectedMode = [string]$cmbDefaultStartupMode.SelectedItem.Tag
			if ($selectedMode -eq 'Expert')
			{
				if ($chkSafeModeDefault)
				{
					$chkSafeModeDefault.IsEnabled = $false
					if (-not $InitialLoad) { $chkSafeModeDefault.IsChecked = $false }
				}
				if ($chkAdvancedMode -and -not $InitialLoad) { $chkAdvancedMode.IsChecked = $true }
			}
			else
			{
				if ($chkSafeModeDefault) { $chkSafeModeDefault.IsEnabled = $true }
				if (-not $InitialLoad)
				{
					if ($chkSafeModeDefault) { $chkSafeModeDefault.IsChecked = $true }
					if ($chkAdvancedMode) { $chkAdvancedMode.IsChecked = $false }
				}
			}
		}.GetNewClosure()
