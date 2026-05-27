foreach ($computer in @($ComputerName))
	{
		if (-not $cancelEngaged -and $policyGate.Allowed)
		{
			try
			{
				$midRunGate = Test-BaselineRemoteOrchestrationAllowed -Operation 'RemoteCompliance'
				if (-not $midRunGate.Allowed) { $cancelEngaged = $true }
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'RemoteTarget.Invoke-BaselineRemoteCompliance.PolicyGate'
				throw
			}
		}

		if ($cancelEngaged)
		{
			$checkpointTargetStates[[string]$computer] = 'Cancelled'
			[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteCompliance cancellation state for target '{0}' in run '{1}'" -f $computer, $orchestrationRunId) -Action {
				$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteCompliance' -TargetStates @{ ([string]$computer) = 'Cancelled' } -Status 'Interrupted' -InterruptReason 'Kill switch engaged during run.'
			})
			continue
		}

		$runId = [guid]::NewGuid().ToString('N')
		$startedAt = [datetime]::UtcNow
		$status = 'Unknown'
		$sessionReused = $false
		$sessionState = 'NotConnected'
		$attemptHistory = [System.Collections.Generic.List[pscustomobject]]::new()
		$targetStateHistory = [System.Collections.Generic.List[pscustomobject]]::new()
		[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteCompliance' -State 'Pending' -Phase 'Queued' -Timestamp $startedAt -Reason 'Target queued for remote compliance check.')
		$entry = [pscustomobject]@{
			ComputerName    = $computer
			RunId           = $runId
			AttemptCount    = 1
			RetryCount      = 0
			Compliant       = $false
			DriftedCount    = 0
			TotalChecked    = 0
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
			AttemptHistory  = $null
			RetryAnalytics  = $null
			Errors          = @()
		}

		$session = $null
		try
		{
			if ($policyGate.Allowed)
			{
				$payloadAttempt = 0
				$payloadRetry = $false
				do
				{
					$payloadAttempt++
					$payloadRetry = $false
					$remoteTempDir = $null
					$attemptStartedAt = [datetime]::UtcNow
					$attemptStatus = 'Unknown'
					[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteCompliance' -State 'Connecting' -Phase 'Connecting' -Timestamp $attemptStartedAt -Reason ("Attempt {0} started." -f $payloadAttempt))
					$entry.Errors = @()
					$entry.Compliant = $false
					$entry.DriftedCount = 0
					$entry.TotalChecked = 0

					try
					{
						$sessionSummaryBefore = @()
						try { $sessionSummaryBefore = @(Get-BaselineRemoteSessionSummary -ComputerName $computer) } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteCompliance\Invoke-BaselineRemoteCompliance.ps1:81' -Severity Debug }
						 $sessionSummaryBefore = @() }
						$sessionReused = $sessionSummaryBefore.Count -gt 0
						# Open or reuse a cached remote session.
						$session = Get-BaselineRemoteSession -ComputerName $computer -Credential $Credential -MaxRetryCount $MaxRetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
						if ($session) { $sessionState = [string]$session.State }
						[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteCompliance' -State 'Connected' -Phase 'Connected' -Timestamp ([datetime]::UtcNow) -Reason 'Remote session opened.')

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

						# Run the compliance check on the remote machine.
						[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteCompliance' -State 'Running' -Phase 'Running' -Timestamp ([datetime]::UtcNow) -Reason 'Remote compliance check started.')
						$remoteResult = Invoke-Command -Session $session -ArgumentList $remoteProfilePath, $remoteModuleDir -ScriptBlock {
							param ($profilePath, $moduleDir)

							$errors = [System.Collections.Generic.List[string]]::new()
							$report = $null

							try
							{
								# Import the SharedHelpers module from the staged directory.
								$sharedHelpersPath = Join-Path $moduleDir 'SharedHelpers.psm1'
								Import-Module -Name $sharedHelpersPath -Force -ErrorAction Stop

								# Load the profile.
								$profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
								$profile = $profileContent | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop

								# Load the manifest.
								$manifest = @(Import-TweakManifestFromData)
								if (-not $manifest -or $manifest.Count -eq 0)
								{
									$errors.Add('Failed to load tweak manifest on remote machine.')
								}
								else
								{
									$report = Test-SystemCompliance -Profile $profile -Manifest $manifest
								}
							}
							catch
							{
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteCompliance\Invoke-BaselineRemoteCompliance.ps1:140' -Severity Debug }

								$errors.Add($_.Exception.Message)
							}

							return @{
								Report = $report
								Errors = @($errors)
							}
						}

						# Process remote results.
						if ($remoteResult.Report)
						{
							$report = $remoteResult.Report
							$entry.TotalChecked = $report.TotalChecked
							$entry.DriftedCount = $report.Drifted
							$entry.Compliant    = ($report.Drifted -eq 0)
						}

						if ($remoteResult.Errors -and $remoteResult.Errors.Count -gt 0)
						{
							$entry.Errors = @($remoteResult.Errors)
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteCompliance\Invoke-BaselineRemoteCompliance.ps1:165' -Severity Debug }

						$entry.Errors = @($entry.Errors + $_.Exception.Message)
					}
					finally
					{
						if ($remoteTempDir)
						{
							Invoke-Command -Session $session -ArgumentList $remoteTempDir -ScriptBlock {
								param ($dir)
								if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
							}
						}
					}

					$attemptCompletedAt = [datetime]::UtcNow
					$attemptStatus = if ($entry.Errors.Count -gt 0) { 'Failed' } elseif ($entry.Compliant) { 'Compliant' } elseif ($entry.DriftedCount -gt 0) { 'Drifted' } else { 'Unknown' }
					$attemptFailureProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($entry.Errors) -Status $attemptStatus
					$attemptRecord = New-BaselineRemoteAttemptRecord -ComputerName $computer -AttemptIndex $payloadAttempt -StartedUtc $attemptStartedAt -CompletedUtc $attemptCompletedAt -Status $attemptStatus -Errors @($entry.Errors) -FailureProfile $attemptFailureProfile
					[void]$attemptHistory.Add($attemptRecord)
					$null = Write-BaselineRemoteAttemptHistoryRecord -RunId $runId -Operation 'RemoteCompliance' -AttemptRecord $attemptRecord

					if ($entry.Errors.Count -gt 0)
					{
						$payloadProfile = $attemptFailureProfile
						if ($payloadProfile.Retryable -and $payloadAttempt -lt ([math]::Max(1, $MaxRetryCount + 1)))
						{
							$payloadRetry = $true
							Invoke-BaselineRemoteRetryDelay -Attempt $payloadAttempt -BaseDelayMilliseconds $RetryDelayMilliseconds
						}
					}
				}
				while ($payloadRetry)

				$retryAnalytics = Get-BaselineRemoteRetryAnalytics -AttemptRecords @($attemptHistory)
				$entry.AttemptCount = $payloadAttempt
				$entry.RetryCount = [math]::Max(0, $payloadAttempt - 1)
				$entry.AttemptHistory = @($attemptHistory)
				$entry.RetryAnalytics = $retryAnalytics
			}
			else
			{
				$entry.Errors = @($policyGate.Reason)
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\SharedHelpers\RemoteTarget\Invoke-BaselineRemoteCompliance\Invoke-BaselineRemoteCompliance.ps1:210' -Severity Debug }

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
			elseif ($entry.Compliant)
			{
				$status = 'Compliant'
			}
			elseif ($entry.TotalChecked -gt 0 -and $entry.DriftedCount -gt 0)
			{
				$status = 'Drifted'
			}
			elseif ($entry.TotalChecked -eq 0)
			{
				$status = 'Skipped'
			}
			else
			{
				$status = 'Unknown'
			}

			$entry.Status = $status
			$failureProfile = Get-BaselineRemoteFailureProfile -ErrorMessages @($entry.Errors) -Status $status
			$entry.FailureCategory = $failureProfile.Category
			$entry.Retryable = $failureProfile.Retryable
			$entry.RetryReason = $failureProfile.RetryReason
			$entry.LifecycleState = Get-BaselineRemoteTargetLifecycleState -Operation 'RemoteCompliance' -Status $status -Retryable $failureProfile.Retryable -Blocked $entry.BlockedByPolicy
			$entry.TerminalState = if ($entry.BlockedByPolicy) { 'Skipped' } elseif ($entry.Compliant) { 'Succeeded' } elseif ($status -eq 'Skipped') { 'Skipped' } elseif ($status -eq 'Drifted') { 'Failed' } elseif ($failureProfile.Retryable) { 'Retrying' } else { 'Failed' }
			$entry.TargetState = Get-BaselineRemoteTargetState -Operation 'RemoteCompliance' -Status $status -Retryable $failureProfile.Retryable -Blocked $entry.BlockedByPolicy
			[void](Add-BaselineRemoteTargetStateTransition -Transitions $targetStateHistory -Operation 'RemoteCompliance' -State $entry.TargetState -Phase 'Completed' -Status $status -Timestamp $completedAt -Reason $entry.RetryReason)
			$entry.DurationSeconds = [math]::Round(($completedAt - $startedAt).TotalSeconds, 2)
			$record = Write-BaselineRemoteOrchestrationRecord -Record @{
				RecordKind       = 'Target'
				RunId             = $runId
				Operation         = 'RemoteCompliance'
				ComputerName      = $computer
				RemoteTargetLabel = $computer
				Status            = $status
				TargetState       = $entry.TargetState
				TerminalState     = $entry.TerminalState
				LifecycleState    = $entry.LifecycleState
				SessionReused     = $sessionReused
				SessionState      = $sessionState
				DriftedCount      = $entry.DriftedCount
				TotalChecked      = $entry.TotalChecked
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
						RetryDurationMs       = $entry.RetryAnalytics.RetryDurationMs
						FailureCategoryCounts = $entry.RetryAnalytics.FailureCategoryCounts
					}
				} else { $null }
				Details           = [ordered]@{
					Compliant        = [bool]$entry.Compliant
					AttemptSummaries = if ($entry.AttemptHistory) {
						@($entry.AttemptHistory | ForEach-Object {
							[ordered]@{
								AttemptIndex    = [int]$_.AttemptIndex
								DurationMs      = [int]$_.DurationMs
								Status          = [string]$_.Status
								FailureCategory = [string]$_.FailureCategory
								Retryable       = [bool]$_.Retryable
							}
						})
					} else { @() }
				}
			}

			$entry.HistoryPath = $record.HistoryPath
		}

		$results.Add($entry)
		[void](Invoke-BaselineRemoteCheckpointAction -Description ("persist RemoteCompliance target state for '{0}' in run '{1}'" -f $computer, $orchestrationRunId) -Action {
			$checkpointTargetStates[[string]$computer] = [string]$entry.TerminalState
			$null = Save-BaselineRemoteResumeCheckpoint -RunId $orchestrationRunId -Operation 'RemoteCompliance' -TargetStates @{ ([string]$computer) = [string]$entry.TerminalState } -Status 'Running'
		})
	}
