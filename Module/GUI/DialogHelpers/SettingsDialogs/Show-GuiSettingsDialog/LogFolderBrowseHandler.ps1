if ($btnLogFolderBrowse)
		{
			$btnLogFolderBrowse.Add_Click({
				try
				{
					Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
					$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
					$folderDialog.Description = $settingsLogFolderBrowseDescription
					$folderDialog.ShowNewFolderButton = $true
					$selectedPath = & $getEffectiveLogDirectory
					if (-not [string]::IsNullOrWhiteSpace($selectedPath) -and [System.IO.Directory]::Exists($selectedPath))
					{
						$folderDialog.SelectedPath = $selectedPath
					}
					if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
					{
						$settingsLogState.CustomDirectory = [string]$folderDialog.SelectedPath
						& $refreshLogFolderDisplay
					}
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.LogFolderBrowse'
					[void](& $settingsShowThemedDialog -Title $settingsLoggingSection -Message ($settingsLogFolderChooseFailed -f $_.Exception.Message) -Buttons @($okLabel) -AccentButton $okLabel)
				}
			}.GetNewClosure())
		}

		if ($btnOpenLogFolder)
		{
			$btnOpenLogFolder.Add_Click({
				try
				{
					$folderPath = & $getEffectiveLogDirectory
					if ([string]::IsNullOrWhiteSpace($folderPath)) { return }
					if (-not [System.IO.Directory]::Exists($folderPath)) { [void][System.IO.Directory]::CreateDirectory($folderPath) }
					Invoke-UserLaunch -FilePath 'explorer.exe' -ArgumentList @($folderPath) -Description 'Baseline log folder' | Out-Null
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.OpenLogFolder'
					[void](& $settingsShowThemedDialog -Title $settingsLoggingSection -Message ($settingsLogFolderOpenFailed -f $_.Exception.Message) -Buttons @($okLabel) -AccentButton $okLabel)
				}
			}.GetNewClosure())
		}

		if ($btnCopyLogFolderPath)
		{
			$btnCopyLogFolderPath.Add_Click({
				try
				{
					$folderPath = & $getEffectiveLogDirectory
					if (-not [string]::IsNullOrWhiteSpace($folderPath))
					{
						[System.Windows.Clipboard]::SetText($folderPath)
					}
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.CopyLogFolderPath'
					[void](& $settingsShowThemedDialog -Title $settingsLoggingSection -Message ($settingsLogFolderCopyFailed -f $_.Exception.Message) -Buttons @($okLabel) -AccentButton $okLabel)
				}
			}.GetNewClosure())
		}

		if ($btnClearOldLogs)
		{
			$btnClearOldLogs.Add_Click({
				try
				{
					$folderPath = & $getEffectiveLogDirectory
					if ([string]::IsNullOrWhiteSpace($folderPath) -or -not [System.IO.Directory]::Exists($folderPath)) { return }
					$confirm = & $settingsShowThemedDialog -Title $settingsClearOldLogsLabel -Message ($settingsClearOldLogsPrompt -f $folderPath) -Buttons @($settingsClearOldLogsConfirm, $cancelLabel) -DestructiveButton $settingsClearOldLogsConfirm
					if ($confirm -ne $settingsClearOldLogsConfirm) { return }

					$currentLogPath = if ($global:LogFilePath) { [System.IO.Path]::GetFullPath([string]$global:LogFilePath) } else { '' }
					$removedCount = 0
					foreach ($logFile in @(Get-ChildItem -LiteralPath $folderPath -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue))
					{
						$logPath = [System.IO.Path]::GetFullPath([string]$logFile.FullName)
						if (-not [string]::IsNullOrWhiteSpace($currentLogPath) -and [string]::Equals($logPath, $currentLogPath, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
						Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
						$removedCount++
					}
					[void](& $settingsShowThemedDialog -Title $settingsClearOldLogsLabel -Message ($settingsClearOldLogsRemoved -f $removedCount) -Buttons @($okLabel) -AccentButton $okLabel)
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.ClearOldLogs'
					[void](& $settingsShowThemedDialog -Title $settingsClearOldLogsLabel -Message ($settingsClearOldLogsFailed -f $_.Exception.Message) -Buttons @($okLabel) -AccentButton $okLabel)
				}
			}.GetNewClosure())
		}
