$ctxIncidentPack.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if ($selected -and (Test-GuiObjectField -Object $selected -FieldName 'BundlePath') -and -not [string]::IsNullOrWhiteSpace($selected.BundlePath))
			{
				try
				{
					$incidentPackCmd = Get-GuiRuntimeCommand -Name 'New-IncidentReproductionPack' -CommandType 'Function'
					if ($incidentPackCmd)
					{
						& $incidentPackCmd -SupportBundlePath $selected.BundlePath
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:13' -Severity Debug }

					& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to generate incident reproduction pack.`n`n{0}" -f $_.Exception.Message)
				}
			}
		}.GetNewClosure())

		$ctxExportDeepLinkedBundle.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if (-not $selected) { return }
			if (-not (Test-GuiObjectField -Object $selected -FieldName 'RunId') -or [string]::IsNullOrWhiteSpace([string]$selected.RunId)) { return }
			if (-not (Test-GuiObjectField -Object $selected -FieldName 'FailedCount') -or [int]$selected.FailedCount -le 0) { return }
			if (-not $exportSupportBundleCommand -or -not $showGuiFileSaveDialogCommand)
			{
				& $showRemoteConsoleError -Title 'Remote Console' -Message 'Support bundle export is unavailable in this runtime.'
				return
			}

			try
			{
				$defaultFileName = 'Baseline-SupportBundle-{0}-{1}.zip' -f ((Get-Date -Format 'yyyyMMdd-HHmmss')), ([string]$selected.ComputerName -replace '[^A-Za-z0-9._-]', '_')
				$savePath = & $showGuiFileSaveDialogCommand -Title 'Export Deep-Linked Support Bundle' -Filter 'ZIP Files (*.zip)|*.zip|All Files (*.*)|*.*' -DefaultExtension 'zip' -FileName $defaultFileName
				if ([string]::IsNullOrWhiteSpace($savePath)) { return }

				$sessionSnapshot = $null
				try { if ($getGuiSettingsSnapshotCommand) { $sessionSnapshot = & $getGuiSettingsSnapshotCommand } } catch { $sessionSnapshot = $null; Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.LoadSessionSnapshot' }
				$sessionStatePath = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineSupportBundleSession_{0}.json' -f [guid]::NewGuid().ToString('N'))
				try
				{
					$sessionPayload = [ordered]@{
						Schema = 'Baseline.GuiSession'
						SchemaVersion = 1
						SavedAt = (Get-Date).ToString('o')
						State = $sessionSnapshot
					}
					($sessionPayload | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $sessionStatePath -Encoding UTF8 -Force

					$systemSnapshot = $null
					try { $systemSnapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest } catch { $systemSnapshot = $null; Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.LoadSystemSnapshot' }

					$connectivityResults = @()
					try
					{
						$ctx = Invoke-CapturedFunction -Name 'Get-GuiRemoteTargetContext'
						if ($ctx -and (Test-GuiObjectField -Object $ctx -FieldName 'LastConnectivityResults'))
						{
							$connectivityResults = @($ctx.LastConnectivityResults)
						}
					}
					catch
					{
						$connectivityResults = @()
						Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.LoadConnectivityResults'
					}

					$result = & $exportSupportBundleCommand -OutputPath $savePath -ProfilePath $sessionStatePath -SystemSnapshot $systemSnapshot -Manifest $Script:TweakManifest -IncludeAuditLog -IncludeTestReport -ConnectivityResults $connectivityResults -DeepLinkRunId @([string]$selected.RunId) -DeepLinkComputerName @([string]$selected.ComputerName) -DeepLinkOperation @([string]$selected.Operation)
					LogInfo ("Exported deep-linked support bundle to {0}" -f $result.OutputPath)
					try { [System.Diagnostics.Process]::Start('explorer.exe', "/select,`"$($result.OutputPath)`"") | Out-Null } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.StartExplorer' }
				}
				finally
				{
					if (Test-Path -LiteralPath $sessionStatePath)
					{
						try { Remove-Item -LiteralPath $sessionStatePath -Force -ErrorAction SilentlyContinue } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiRemoteConsoleDialog.RemoveSessionStatePath' }
					}
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:80' -Severity Debug }

				& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to export deep-linked support bundle.`n`n{0}" -f $_.Exception.Message)
			}
		}.GetNewClosure())

		$ctxRetryFailed.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if ($selected -and (Test-GuiObjectField -Object $selected -FieldName 'FailedCount') -and $selected.FailedCount -gt 0)
			{
				$targets = if (Test-GuiObjectField -Object $selected -FieldName 'FailedTargets') { @($selected.FailedTargets) } else { @() }
				if ($targets.Count -gt 0)
				{
					try
					{
						$ctx = Invoke-CapturedFunction -Name 'Get-GuiRemoteTargetContext'
						$cred = if ($ctx) { $ctx.Credential } else { $null }
						$null = Invoke-CapturedFunction -Name 'Set-GuiRemoteTargetContext' -Parameters @{
							ComputerName = $targets
							Credential = $cred
							StatusMessage = 'Context updated to retry failed targets.'
						}
						& $refreshConsole
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:104' -Severity Debug }

						& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to stage retry targets.`n`n{0}" -f $_.Exception.Message)
					}
				}
				else
				{
					& $showRemoteConsoleError -Title 'Remote Console' -Message "Failed target list not available in this summary."
				}
			}
		}.GetNewClosure())

		$ctxExportFailed.Add_Click({
			$selected = $lstRecentRemoteRuns.SelectedItem
			if ($selected -and (Test-GuiObjectField -Object $selected -FieldName 'FailedCount') -and $selected.FailedCount -gt 0)
			{
				$targets = if (Test-GuiObjectField -Object $selected -FieldName 'FailedTargets') { @($selected.FailedTargets) } else { @() }
				if ($targets.Count -gt 0)
				{
					$dialog = New-Object Microsoft.Win32.SaveFileDialog
					$dialog.Title = 'Export Failed Targets'
					$dialog.Filter = 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*'
					$dialog.DefaultExt = 'txt'
					$dialog.FileName = ('FailedTargets-{0}.txt' -f $selected.Timestamp.ToString('yyyyMMdd-HHmmss'))
					if ($dialog.ShowDialog($dlg) -eq $true)
					{
						try { [System.IO.File]::WriteAllLines($dialog.FileName, $targets) } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:130' -Severity Debug }
						 & $showRemoteConsoleError -Title 'Export Failed' -Message ("Failed to write file.`n`n{0}" -f $_.Exception.Message) }
					}
				}
				else { & $showRemoteConsoleError -Title 'Remote Console' -Message "Failed target list not available in this summary." }
			}
		}.GetNewClosure())

		$refreshConsole = {
			$context = $null
			try { $context = Invoke-CapturedFunction -Name 'Get-GuiRemoteTargetContext' } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:139' -Severity Debug }
			 $context = $null }
			$sessions = @()
			try { $sessions = @((Invoke-CapturedFunction -Name 'Get-BaselineRemoteSessionSummary')) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:141' -Severity Debug }
			 $sessions = @() }
			$recentRuns = @()
			try
			{
				if ($getRemoteRunSummariesCommand)
				{
					$recentRuns = @((Invoke-CapturedFunction -Name 'Get-BaselineRemoteRunSummaries' -Parameters @{ MaxRecords = 5 }))
				}
				elseif (Get-GuiFunctionCapture -Name 'Get-BaselineRemoteOrchestrationDetails')
				{
					$recentRuns = @((Invoke-CapturedFunction -Name 'Get-BaselineRemoteOrchestrationDetails' -Parameters @{ MaxRecords = 5 }))
				}
				else
				{
					$recentRuns = @((Invoke-CapturedFunction -Name 'Get-BaselineRemoteOrchestrationSummary' -Parameters @{ MaxRecords = 5 }))
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:158' -Severity Debug }

				$recentRuns = @()
			}

			$recentRunRows = @()
			if ($recentRuns.Count -gt 0)
			{
				$recentRunRows = @($recentRuns | ForEach-Object {
					$timestamp = $null
					try { $timestamp = [datetime]::Parse([string]$_.Timestamp) } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\IncidentReproductionPackContextMenu.ps1:168' -Severity Debug }
					 $timestamp = [datetime]::UtcNow }
					$succeededCount = if ($_.PSObject.Properties['SucceededCount']) { [int]$_.SucceededCount } else { 0 }
					$failedCount = if ($_.PSObject.Properties['FailedCount']) { [int]$_.FailedCount } else { 0 }
					$skippedCount = if ($_.PSObject.Properties['SkippedCount']) { [int]$_.SkippedCount } else { 0 }
					$retryingCount = if ($_.PSObject.Properties['RetryingCount']) { [int]$_.RetryingCount } else { 0 }
					$cancelledCount = if ($_.PSObject.Properties['CancelledCount']) { [int]$_.CancelledCount } else { 0 }
					$attempts = if ($_.PSObject.Properties['TotalAttempts']) { [int]$_.TotalAttempts } else { 0 }
					$retries = if ($_.PSObject.Properties['TotalRetries']) { [int]$_.TotalRetries } else { 0 }

					[pscustomobject]@{
						Timestamp      = $timestamp
						Operation      = if ($_.PSObject.Properties['Operation']) { [string]$_.Operation } else { 'Remote' }
						TerminalState  = if ($_.PSObject.Properties['TerminalState']) { [string]$_.TerminalState } else { 'Unknown' }
						TargetCount    = if ($_.PSObject.Properties['TargetCount']) { [int]$_.TargetCount } else { 0 }
						FailedCount    = $failedCount
						FailedTargets  = if ($_.PSObject.Properties['FailedTargets']) { @($_.FailedTargets) } else { @() }
						CountsSummary  = ('Success={0}, Failed={1}, Skipped={2}, Retrying={3}, Cancelled={4}, Attempts={5}, Retries={6}' -f $succeededCount, $failedCount, $skippedCount, $retryingCount, $cancelledCount, $attempts, $retries)
						Summary        = if ($_.PSObject.Properties['Summary']) { [string]$_.Summary } else { ('{0} | {1} | Run {2}' -f $timestamp.ToString('yyyy-MM-dd HH:mm:ss'), (if ($_.PSObject.Properties['Operation']) { [string]$_.Operation } else { 'Remote' }), (if ($_.PSObject.Properties['RunId']) { [string]$_.RunId } else { 'n/a' })) }
						LogPath        = if ($_.PSObject.Properties['LogPath']) { [string]$_.LogPath } else { $null }
						BundlePath     = if ($_.PSObject.Properties['BundlePath']) { [string]$_.BundlePath } else { $null }
					}
				})
			}

			if ($txtFilterRuns -and -not [string]::IsNullOrWhiteSpace($txtFilterRuns.Text))
			{
				$filter = $txtFilterRuns.Text
				$recentRunRows = @($recentRunRows | Where-Object {
					$_.Operation -match $filter -or
					$_.TerminalState -match $filter -or
					$_.Summary -match $filter
				})
			}

			if ($txtConnectedTargets)
			{
				if ($context -and $context.Connected -and $context.TargetComputers.Count -gt 0)
				{
					$txtConnectedTargets.Text = ('Connected targets: {0}' -f ($context.TargetComputers -join ', '))
				}
				else
				{
					$txtConnectedTargets.Text = 'Connected targets: none'
				}
			}

			if ($txtApprovedTargets)
			{
				if ($context -and $context.ApprovedTargetComputers -and $context.ApprovedTargetComputers.Count -gt 0)
				{
					$txtApprovedTargets.Text = ('Approved targets: {0}' -f ($context.ApprovedTargetComputers -join ', '))
				}
				else
				{
					$txtApprovedTargets.Text = 'Approved targets: none'
				}
			}

			if ($txtConnectedAt)
			{
				$txtConnectedAt.Text = if ($context -and $context.ConnectedAt) { ('Connected at (UTC): {0}' -f $context.ConnectedAt) } else { 'Connected at (UTC): n/a' }
			}

			if ($txtApprovalMessage)
			{
				$txtApprovalMessage.Text = if ($context -and $context.ApprovalMessage) { ('Approval message: {0}' -f $context.ApprovalMessage) } else { 'Approval message: n/a' }
			}

			if ($txtCachedSessions)
			{
				if ($sessions.Count -gt 0)
				{
					$txtCachedSessions.Text = ('Cached sessions: {0}' -f (($sessions | ForEach-Object { '{0} [{1}]' -f $_.ComputerName, $_.State }) -join '; '))
				}
				else
				{
					$txtCachedSessions.Text = 'Cached sessions: none'
				}
			}

			if ($lstRecentRemoteRuns)
			{
				$lstRecentRemoteRuns.ItemsSource = $recentRunRows
				if ($recentRunRows.Count -eq 0)
				{
					$lstRecentRemoteRuns.IsEnabled = $false
				}
				else
				{
					$lstRecentRemoteRuns.IsEnabled = $true
				}
			}

			if ($txtConsoleHint)
			{
				$txtConsoleHint.Text = 'Use the controls below to connect, approve, save policy, and load policy for the current remote context.'
			}

			if ($btnDisconnect) { $btnDisconnect.IsEnabled = [bool]($context -and $context.Connected -and $context.TargetComputers.Count -gt 0) }
			if ($btnApprove) { $btnApprove.IsEnabled = [bool]($context -and $context.Connected -and $context.TargetComputers.Count -gt 0) }
			if ($btnSavePolicy) { $btnSavePolicy.IsEnabled = [bool]($context -and $context.Connected -and $context.TargetComputers.Count -gt 0 -and $context.ApprovedTargetComputers.Count -gt 0) }
			if ($btnLoadPolicy) { $btnLoadPolicy.IsEnabled = [bool]($context -and $context.Connected -and $context.TargetComputers.Count -gt 0) }
			if ($btnPreflight) { $btnPreflight.IsEnabled = [bool]($context -and $context.Connected -and $context.TargetComputers.Count -gt 0) }
		}.GetNewClosure()
