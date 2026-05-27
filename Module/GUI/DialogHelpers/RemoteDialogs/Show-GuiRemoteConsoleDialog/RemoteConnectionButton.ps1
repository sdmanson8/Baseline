if ($btnConnect)
		{
			$btnConnect.Content = (Get-UxLocalizedString -Key 'GuiRemoteConnectTitle' -Fallback 'Connect to Computer')
			Set-ButtonChrome -Button $btnConnect -Variant 'Secondary' -Compact
			$btnConnect.Add_Click({
				try
				{
					$request = Invoke-CapturedFunction -Name 'Prompt-GuiRemoteTargetConnection'
					if (-not $request) { return }
					$null = Invoke-CapturedFunction -Name 'Set-GuiRemoteTargetContext' -Parameters @{
						ComputerName = $request.ComputerName
						Credential = $request.Credential
						StatusMessage = 'Remote target connected.'
					}
					& $refreshConsole
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:17' -Severity Debug }

					& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to connect to remote target.`n`n{0}" -f $_.Exception.Message)
				}
			}.GetNewClosure())
		}
		if ($btnDisconnect)
		{
			$btnDisconnect.Content = (Get-UxLocalizedString -Key 'GuiRemoteDisconnectTitle' -Fallback 'Disconnect')
			Set-ButtonChrome -Button $btnDisconnect -Variant 'Secondary' -Compact
			$btnDisconnect.Add_Click({
				try
				{
					$null = Invoke-CapturedFunction -Name 'Clear-GuiRemoteTargetContext'
					& $refreshConsole
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:33' -Severity Debug }

					& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to disconnect remote target.`n`n{0}" -f $_.Exception.Message)
				}
			}.GetNewClosure())
		}
		if ($btnApprove)
		{
			$btnApprove.Content = (Get-UxLocalizedString -Key 'GuiMenuToolsApproveRemoteTargets' -Fallback 'Approve Target List...')
			Set-ButtonChrome -Button $btnApprove -Variant 'Secondary' -Compact
			$btnApprove.Add_Click({
				try
				{
					$context = Invoke-CapturedFunction -Name 'Get-GuiRemoteTargetContext'
					if (-not $context -or -not $context.Connected -or $context.TargetComputers.Count -eq 0) { return }
					$targets = @($context.TargetComputers)
					$null = Invoke-CapturedFunction -Name 'Set-GuiRemoteTargetApprovalList' -Parameters @{
						ComputerName = $targets
						ApprovalMessage = 'Remote target list approved from Remote Console.'
					}
					& $refreshConsole
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:55' -Severity Debug }

					& $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to approve target list.`n`n{0}" -f $_.Exception.Message)
				}
			}.GetNewClosure())
		}
		if ($btnSavePolicy)
		{
			$btnSavePolicy.Content = (Get-UxLocalizedString -Key 'GuiMenuToolsSaveRemoteApprovalPolicy' -Fallback 'Save Remote Approval Policy...')
			Set-ButtonChrome -Button $btnSavePolicy -Variant 'Secondary' -Compact
			if (-not $exportRemoteTargetApprovalPolicyCommand) { $btnSavePolicy.IsEnabled = $false }
			$btnSavePolicy.Add_Click({
				if (-not $exportRemoteTargetApprovalPolicyCommand)
				{
					& $showRemoteConsoleError -Title 'Remote Console' -Message 'Remote approval policy export is unavailable in this runtime.'
					return
				}
				try { $null = Invoke-CapturedFunction -Name 'Export-GuiRemoteTargetApprovalPolicy' } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:72' -Severity Debug }
				 & $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to save remote approval policy.`n`n{0}" -f $_.Exception.Message) }
			}.GetNewClosure())
		}
		if ($btnLoadPolicy)
		{
			$btnLoadPolicy.Content = (Get-UxLocalizedString -Key 'GuiMenuToolsLoadRemoteApprovalPolicy' -Fallback 'Load Remote Approval Policy...')
			Set-ButtonChrome -Button $btnLoadPolicy -Variant 'Secondary' -Compact
			if (-not $importRemoteTargetApprovalPolicyCommand) { $btnLoadPolicy.IsEnabled = $false }
			$btnLoadPolicy.Add_Click({
				if (-not $importRemoteTargetApprovalPolicyCommand)
				{
					& $showRemoteConsoleError -Title 'Remote Console' -Message 'Remote approval policy import is unavailable in this runtime.'
					return
				}
				try { $null = Invoke-CapturedFunction -Name 'Import-GuiRemoteTargetApprovalPolicy'; & $refreshConsole } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:86' -Severity Debug }
				 & $showRemoteConsoleError -Title 'Remote Console' -Message ("Failed to load remote approval policy.`n`n{0}" -f $_.Exception.Message) }
			}.GetNewClosure())
		}
		if ($btnPreflight)
		{
			$btnPreflight.Content = $preflightLabel
			Set-ButtonChrome -Button $btnPreflight -Variant 'Secondary' -Compact
			$btnPreflight.Add_Click({
				try
				{
					$context = Invoke-CapturedFunction -Name 'Get-GuiRemoteTargetContext'
					if (-not $context -or -not $context.Connected -or $context.TargetComputers.Count -eq 0) { return }
					if (-not (Get-GuiFunctionCapture -Name 'Invoke-PreflightChecks')) { throw 'Preflight helper is not available.' }

					$results = Invoke-CapturedFunction -Name 'Invoke-PreflightChecks' -Parameters @{
						RemoteTargets = @($context.TargetComputers)
					}
					$lines = [System.Collections.Generic.List[string]]::new()
					[void]$lines.Add('Remote preflight results:')
					if ($results -and $results.SupportedEnvironmentClassification -and $results.SupportedEnvironmentClassification.Summary)
					{
						[void]$lines.Add($results.SupportedEnvironmentClassification.Summary)
					}
					if ($results -and $results.WinRMReachability -and $results.WinRMReachability.Summary)
					{
						[void]$lines.Add(('WinRM reachability: {0}' -f $results.WinRMReachability.Summary))
					}
					if ($results -and $results.Credentials -and $results.Credentials.Summary)
					{
						[void]$lines.Add(('Credentials: {0}' -f $results.Credentials.Summary))
					}
					if ($results -and $results.PolicyConflictSignals -and $results.PolicyConflictSignals.Summary)
					{
						[void]$lines.Add(('Policy signals: {0}' -f $results.PolicyConflictSignals.Summary))
					}

					$remoteCategories = @()
					if ($results -and $results.PSObject.Properties['RiskCategories'] -and $results.RiskCategories)
					{
						$remoteCategories = @($results.RiskCategories | Where-Object { $_ -and [string]$_.Status -ne 'Passed' })
					}
					elseif ($results -and $results.PolicyConflictSignals -and $results.PolicyConflictSignals.PSObject.Properties['Categories'])
					{
						$remoteCategories = @($results.PolicyConflictSignals.Categories | Where-Object { $_ -and [string]$_.Status -ne 'Passed' })
					}
					if ($remoteCategories.Count -gt 0)
					{
						[void]$lines.Add(' ')
						[void]$lines.Add('Risk categories:')
						foreach ($cat in $remoteCategories)
						{
							$statusMark = if ([string]$cat.Status -eq 'Failed') { '!' } else { '*' }
							[void]$lines.Add(('{0} {1} ({2}): {3}' -f $statusMark, $cat.Name, $cat.Status, $cat.Summary))
							if ($cat.RemediationActions -and @($cat.RemediationActions).Count -gt 0)
							{
								foreach ($action in $cat.RemediationActions)
								{
									if (-not [string]::IsNullOrWhiteSpace([string]$action))
									{
										[void]$lines.Add(('    -> {0}' -f [string]$action))
									}
								}
							}
							if (-not [string]::IsNullOrWhiteSpace([string]$cat.DocumentationPath))
							{
								[void]$lines.Add(('    Remediation guide: {0}' -f [string]$cat.DocumentationPath))
							}
							if (-not [string]::IsNullOrWhiteSpace([string]$cat.LogHint))
							{
								[void]$lines.Add(('    Logs: {0}' -f [string]$cat.LogHint))
							}
						}
					}

					[void]$lines.Add(' ')
					[void]$lines.Add('Checks:')
					foreach ($result in @($results.AllResults))
					{
						if (-not $result) { continue }
						$line = '{0} -> {1}: {2}' -f $result.Name, $result.Status, $result.Message
						if ($result.PSObject.Properties['Key'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Key))
						{
							$line += " | Key: $($result.Key)"
						}
						if ($result.PSObject.Properties['Category'] -and -not [string]::IsNullOrWhiteSpace([string]$result.Category))
						{
							$line += " | Category: $($result.Category)"
						}
						if ($result.PSObject.Properties['RemediationActions'] -and $result.RemediationActions)
						{
							$actions = @($result.RemediationActions)
							if ($actions.Count -gt 0)
							{
								$line += " | Remediation: $($actions -join '; ')"
							}
						}
						[void]$lines.Add($line)

						if ($result.PSObject.Properties['Details'] -and $result.Details)
						{
							if ($result.Details -is [System.Collections.IDictionary])
							{
								foreach ($detailKey in @($result.Details.Keys | Sort-Object))
								{
									[void]$lines.Add(('  - {0}: {1}' -f $detailKey, $result.Details[$detailKey]))
								}
							}
							elseif ($result.Details.PSObject.Properties.Count -gt 0)
							{
								foreach ($detailProp in @($result.Details.PSObject.Properties | Sort-Object Name))
								{
									[void]$lines.Add(('  - {0}: {1}' -f $detailProp.Name, $detailProp.Value))
								}
							}
						}
					}
					[void](Show-ThemedDialog -Title 'Remote Console Preflight' -Message ($lines -join [Environment]::NewLine) -Buttons @('OK') -AccentButton 'OK')
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\RemoteDialogs\Show-GuiRemoteConsoleDialog\RemoteConnectionButton.ps1:204' -Severity Debug }

					& $showRemoteConsoleError -Title 'Remote Console Preflight' -Message ("Failed to run remote preflight.`n`n{0}" -f $_.Exception.Message)
				}
			}.GetNewClosure())
		}
