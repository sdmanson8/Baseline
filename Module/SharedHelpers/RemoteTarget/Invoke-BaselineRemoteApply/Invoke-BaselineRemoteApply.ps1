foreach ($computer in @($ComputerName))
	{
		if (-not $cancelEngaged -and $policyGate.Allowed)
		{
			try
			{
				$midRunGate = Test-BaselineRemoteOrchestrationAllowed -Operation 'RemoteApply'
				if (-not $midRunGate.Allowed) { $cancelEngaged = $true }
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Invoke-BaselineRemoteApply.PolicyGate'
				throw
			}
		}

		if ($cancelEngaged)
		{
			$checkpointTargetStates[[string]$computer] = 'Cancelled'
			[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteApply cancellation state for target '{0}' in run '{1}'" -f $computer, $orchestrationRunId) -Action {
				$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteApply' -TargetStates @{ ([string]$computer) = 'Cancelled' } -Status 'Interrupted' -InterruptReason 'Kill switch engaged during run.'
			})
			continue
		}

		$runId = [guid]::NewGuid().ToString('N')
		$startedAt = [datetime]::UtcNow
		$status = 'Unknown'
		$sessionReused = $false
		$sessionState = 'NotConnected'
		$targetStateHistory = [System.Collections.Generic.List[pscustomobject]]::new()
		[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State 'Pending' -Phase 'Queued' -Timestamp $startedAt -Reason 'Target queued for remote apply.')
		$entry = [pscustomobject]@{
			ComputerName    = $computer
			RunId           = $runId
			AttemptCount    = 1
			RetryCount      = 0
			Applied         = $false
			AppliedCount    = 0
			FailedCount     = 0
			Status          = $status
			TerminalState   = 'Unknown'
			LifecycleState  = if ($policyGate.Allowed) { 'Pending' } else { 'BlockedByPolicy' }
			FailureCategory = $null
			Retryable       = $false
			RetryReason     = $null
			BlockedByPolicy = (-not $policyGate.Allowed)
			SessionReused   = $sessionReused
			SessionState    = $sessionState
			HistoryPath     = $null
			DurationSeconds = 0
			RetryAnalytics  = $null
			Errors          = @()
		}

		$session = $null
		try
		{
			if ($policyGate.Allowed)
			{
				$sessionSummaryBefore = @()
				try { $sessionSummaryBefore = @(Get-BaselineRemoteSessionSummary -ComputerName $computer) } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteApply\Invoke-BaselineRemoteApply.ps1:62' -Severity Debug }
				 $sessionSummaryBefore = @() }
				$sessionReused = $sessionSummaryBefore.Count -gt 0
				# Open or reuse a cached remote session.
				$session = Get-BaselineRemoteSession -ComputerName $computer -Credential $Credential -MaxRetryCount $MaxRetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
				if ($session) { $sessionState = [string]$session.State }
				[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State 'Connecting' -Phase 'Connecting' -Timestamp ([datetime]::UtcNow) -Reason 'Remote session requested.')
				[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State 'Connected' -Phase 'Connected' -Timestamp ([datetime]::UtcNow) -Reason 'Remote session opened.')

				# Create a temp staging directory on the remote machine.
				$remoteTempDir = Invoke-Command -Session $session -ScriptBlock {
					$dir = Join-Path ([System.IO.Path]::GetTempPath()) "Baseline_$([guid]::NewGuid().ToString('N'))"
					$null = New-Item -Path $dir -ItemType Directory -Force
					return $dir
				}

				# Copy profile file to the remote temp directory.
				$remoteProfilePath = Join-Path $remoteTempDir (Split-Path $ProfilePath -Leaf)
				Copy-Item -Path $ProfilePath -Destination $remoteProfilePath -ToSession $session -Force

				# Copy the Module directory to the remote temp directory.
				$remoteModuleDir = Join-Path $remoteTempDir 'Module'
				Copy-Item -Path $moduleRoot -Destination $remoteModuleDir -ToSession $session -Recurse -Force

				# Copy the Localizations directory (required by the module).
				$localizationsDir = Join-Path $repoRoot 'Localizations'
				if (Test-Path -LiteralPath $localizationsDir)
				{
					$remoteLocDir = Join-Path $remoteTempDir 'Localizations'
					Copy-Item -Path $localizationsDir -Destination $remoteLocDir -ToSession $session -Recurse -Force
				}

				# Copy the relocated entry script for headless execution.
				$baselineScript = Join-Path $repoRoot 'Bootstrap/Baseline.ps1'
				if (Test-Path -LiteralPath $baselineScript)
				{
					$remoteBootstrapDir = Join-Path $remoteTempDir 'Bootstrap'
					Invoke-Command -Session $session -ArgumentList $remoteBootstrapDir -ScriptBlock {
						param ($dir)
						$null = New-Item -Path $dir -ItemType Directory -Force
					}
					Copy-Item -Path $baselineScript -Destination $remoteBootstrapDir -ToSession $session -Force
				}
				[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State 'PreviewReady' -Phase 'PreviewReady' -Timestamp ([datetime]::UtcNow) -Reason 'Remote command list staged and ready.')

				# Run the profile application on the remote machine.
				[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State 'Running' -Phase 'Running' -Timestamp ([datetime]::UtcNow) -Reason 'Remote apply started.')
				$remoteResult = Invoke-Command -Session $session -ArgumentList $remoteProfilePath, $remoteModuleDir, $remoteTempDir -ScriptBlock {
				param ($profilePath, $moduleDir, $baseDir)

				$errors = [System.Collections.Generic.List[string]]::new()
				$appliedCount = 0
				$failedCount  = 0

				try
				{
					# Import the SharedHelpers module from the staged directory.
					$sharedHelpersPath = Join-Path $moduleDir 'SharedHelpers.psm1'
					Import-Module -Name $sharedHelpersPath -Force -ErrorAction Stop

					# Import the main Baseline module.
					$baselineModulePath = Join-Path $moduleDir 'Baseline.psd1'
					if (Test-Path -LiteralPath $baselineModulePath)
					{
						Import-Module -Name $baselineModulePath -Force -ErrorAction Stop
					}

					# Load the profile.
					$profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
					$profile = $profileContent | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop

					$profileEntries = @()
					if ($profile.PSObject.Properties['Entries'] -and $profile.Entries)
					{
						$profileEntries = @($profile.Entries)
					}

					$entryResults = [System.Collections.Generic.List[pscustomobject]]::new()
					foreach ($profileEntry in @($profileEntries))
					{
						if (-not $profileEntry) { continue }

						$functionName = $null
						$paramValue   = $null
						$entryType    = 'Toggle'

						if ($profileEntry.PSObject.Properties['Function'])
						{
							$functionName = [string]$profileEntry.Function
						}
						if ($profileEntry.PSObject.Properties['Type'])
						{
							$entryType = [string]$profileEntry.Type
						}

						if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

						# Resolve the parameter to pass.
						switch ($entryType)
						{
							'Choice'
							{
								if ($profileEntry.PSObject.Properties['Value'] -and
									-not [string]::IsNullOrWhiteSpace([string]$profileEntry.Value))
								{
									$paramValue = [string]$profileEntry.Value
								}
							}
							default
							{
								if ($profileEntry.PSObject.Properties['Param'] -and
									-not [string]::IsNullOrWhiteSpace([string]$profileEntry.Param))
								{
									$paramValue = [string]$profileEntry.Param
								}
							}
						}

						$entryAttempt = Invoke-BaselineRemoteEntryWithRetry -EntryName $functionName -MaxRetryCount $MaxRetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds -Action {
							$cmd = Get-Command -Name $functionName -ErrorAction SilentlyContinue
							if (-not $cmd)
							{
								throw "Command not found: $functionName"
							}

							if ($paramValue)
							{
								& $functionName -$paramValue
							}
							else
							{
								& $functionName
							}
						}

						if ($entryAttempt.Success)
						{
							$appliedCount++
						}
						else
						{
							$failedCount++
							foreach ($message in @($entryAttempt.Errors))
							{
								if (-not [string]::IsNullOrWhiteSpace([string]$message))
								{
									$errors.Add("Failed to apply $functionName : $message")
								}
							}
						}

						$entryResults.Add([pscustomobject]@{
							Function    = $functionName
							Type        = $entryType
							Attempts    = $entryAttempt.Attempts
							RetryCount  = $entryAttempt.RetryCount
							Success     = [bool]$entryAttempt.Success
							Retryable   = [bool]$entryAttempt.Retryable
							RetryReason = [string]$entryAttempt.RetryReason
							Errors      = @($entryAttempt.Errors)
						})
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteApply\Invoke-BaselineRemoteApply.ps1:224' -Severity Debug }

					$errors.Add($_.Exception.Message)
				}

					return @{
						AppliedCount = $appliedCount
						FailedCount  = $failedCount
						Errors       = @($errors)
						Entries      = @($entryResults)
					}
				}

				# Process remote results.
				$entry.AppliedCount = $remoteResult.AppliedCount
				$entry.FailedCount  = $remoteResult.FailedCount
				$entry.Applied      = ($remoteResult.FailedCount -eq 0 -and $remoteResult.AppliedCount -gt 0)
				if ($remoteResult.Entries -and $remoteResult.Entries.Count -gt 0)
				{
					$entry.AttemptCount = [int](($remoteResult.Entries | ForEach-Object { if ($_.Attempts) { [int]$_.Attempts } else { 1 } }) | Measure-Object -Sum).Sum
					$entry.RetryCount = [int](($remoteResult.Entries | ForEach-Object { if ($_.RetryCount) { [int]$_.RetryCount } else { 0 } }) | Measure-Object -Sum).Sum
					$failureCategoryCounts = [ordered]@{}
					foreach ($entryResult in @($remoteResult.Entries))
					{
						$cat = if ($entryResult.Success) { 'Success' } elseif ($entryResult.FailureCategory) { [string]$entryResult.FailureCategory } else { 'Unknown' }
						if (-not $failureCategoryCounts.ContainsKey($cat))
						{
							$failureCategoryCounts[$cat] = 0
						}
						$failureCategoryCounts[$cat]++
					}
					$entry.RetryAnalytics = [pscustomobject]@{
						TotalAttempts         = $entry.AttemptCount
						TotalRetries          = $entry.RetryCount
						RetryableFailures     = @($remoteResult.Entries | Where-Object { [bool]$_.Retryable }).Count
						NonRetryableFailures  = @($remoteResult.Entries | Where-Object { -not [bool]$_.Success -and -not [bool]$_.Retryable }).Count
						FailureCategoryCounts = $failureCategoryCounts
						EntrySummaries        = @($remoteResult.Entries | ForEach-Object {
							[ordered]@{
								Function        = [string]$_.Function
								Attempts        = [int]$_.Attempts
								RetryCount      = [int]$_.RetryCount
								Success         = [bool]$_.Success
								Retryable       = [bool]$_.Retryable
								FailureCategory = [string]$_.FailureCategory
							}
						})
					}
				}
				else
				{
					$entry.AttemptCount = 1
					$entry.RetryCount = 0
				}

				if ($remoteResult.Errors -and $remoteResult.Errors.Count -gt 0)
				{
					$entry.Errors = @($remoteResult.Errors)
				}

				# Clean up temp files on the remote machine.
				Invoke-Command -Session $session -ArgumentList $remoteTempDir -ScriptBlock {
					param ($dir)
					if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
				}
			}
			else
			{
				$entry.Errors = @($policyGate.Reason)
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteApply\Invoke-BaselineRemoteApply.ps1:295' -Severity Debug }

			$entry.Errors = @($entry.Errors + $_.Exception.Message)
		}
		finally
		{
			$completedAt = [datetime]::UtcNow
			$entry.SessionReused = $sessionReused
			$entry.SessionState = $sessionState
			if ($entry.Errors.Count -gt 0)
			{
				$status = 'Failed'
			}
			elseif ($entry.AppliedCount -gt 0 -and $entry.FailedCount -eq 0)
			{
				$status = 'Applied'
			}
			elseif ($entry.AppliedCount -gt 0 -and $entry.FailedCount -gt 0)
			{
				$status = 'Partial'
			}
			elseif ($entry.AppliedCount -eq 0 -and $entry.FailedCount -gt 0)
			{
				$status = 'Failed'
			}
			elseif ($entry.AppliedCount -eq 0 -and $entry.FailedCount -eq 0)
			{
				$status = 'Skipped'
			}
			else
			{
				$status = 'Unknown'
			}

			$entry.Applied = ($status -eq 'Applied')
			$entry.Status = $status
			$failureProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($entry.Errors) -Status $status
			$entry.FailureCategory = $failureProfile.Category
			$entry.Retryable = $failureProfile.Retryable
			$entry.RetryReason = $failureProfile.RetryReason
			$entry.LifecycleState = Get-BaselineRemoteTargetLifecycleState -Operation 'RemoteApply' -Status $status -Retryable $failureProfile.Retryable -Blocked $entry.BlockedByPolicy
			$entry.TerminalState = if ($entry.BlockedByPolicy) { 'Skipped' } elseif ($entry.Applied) { 'Succeeded' } elseif ($status -eq 'Skipped') { 'Skipped' } elseif ($status -eq 'Partial') { if ($failureProfile.Retryable) { 'Retrying' } else { 'Failed' } } elseif ($failureProfile.Retryable) { 'Retrying' } else { 'Failed' }
			$entry.TargetState = Get-BaselineRemoteTargetState -Operation 'RemoteApply' -Status $status -Retryable $failureProfile.Retryable -Blocked $entry.BlockedByPolicy
			[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteApply' -State $entry.TargetState -Phase 'Completed' -Status $status -Timestamp $completedAt -Reason $entry.RetryReason)
			$entry.DurationSeconds = [math]::Round(($completedAt - $startedAt).TotalSeconds, 2)
			$record = Write-BaselineRemoteOrchestrationRecord -Record @{
				RecordKind       = 'Target'
				RunId             = $runId
				Operation         = 'RemoteApply'
				ComputerName      = $computer
				RemoteTargetLabel = $computer
				Status            = $status
				TargetState       = $entry.TargetState
				TerminalState     = $entry.TerminalState
				LifecycleState    = $entry.LifecycleState
				SessionReused     = $sessionReused
				SessionState      = $sessionState
				AppliedCount      = $entry.AppliedCount
				FailedCount       = $entry.FailedCount
				AttemptCount      = $entry.AttemptCount
				RetryCount        = $entry.RetryCount
				BlockedByPolicy   = $entry.BlockedByPolicy
				Errors            = @($entry.Errors)
				FailureCategory   = $failureProfile.Category
				Retryable         = $failureProfile.Retryable
				RetryReason       = $failureProfile.RetryReason
				StartedAt         = $startedAt
				CompletedAt       = $completedAt
				DurationSeconds   = $entry.DurationSeconds
				TargetStateHistory = @($targetStateHistory)
				RetryAnalytics    = if ($entry.RetryAnalytics) {
					[ordered]@{
						TotalAttempts         = $entry.RetryAnalytics.TotalAttempts
						TotalRetries          = $entry.RetryAnalytics.TotalRetries
						RetryableFailures     = $entry.RetryAnalytics.RetryableFailures
						NonRetryableFailures  = $entry.RetryAnalytics.NonRetryableFailures
						FailureCategoryCounts = $entry.RetryAnalytics.FailureCategoryCounts
					}
				} else { $null }
				Details           = [ordered]@{
					Applied        = [bool]$entry.Applied
					EntrySummaries = if ($entry.RetryAnalytics -and $entry.RetryAnalytics.EntrySummaries) { @($entry.RetryAnalytics.EntrySummaries) } else { @() }
				}
			}

			$entry.HistoryPath = $record.HistoryPath
		}

		$results.Add($entry)
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteApply target state for '{0}' in run '{1}'" -f $computer, $orchestrationRunId) -Action {
			$checkpointTargetStates[[string]$computer] = [string]$entry.TerminalState
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteApply' -TargetStates @{ ([string]$computer) = [string]$entry.TerminalState } -Status 'Running'
		})
	}
