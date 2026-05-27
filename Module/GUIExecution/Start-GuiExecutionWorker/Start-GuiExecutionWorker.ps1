$worker = [powershell]::Create().AddScript({
		try
		{
			$Global:GUIMode = $true
			if ([string]::IsNullOrWhiteSpace([string]$bgOperationMode))
			{
				$bgOperationMode = 'ReadWrite'
			}
			$Global:BaselineOperationMode = [string]$bgOperationMode
			[System.Environment]::SetEnvironmentVariable('BASELINE_OPERATION_MODE', [string]$bgOperationMode, [System.EnvironmentVariableTarget]::Process)
			if ($bgCurrentTheme -is [System.Collections.IDictionary])
			{
				$Global:BaselineCurrentTheme = $bgCurrentTheme
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$bgCurrentThemeName))
			{
				$Global:BaselineCurrentThemeName = [string]$bgCurrentThemeName
			}
			if ($null -ne $bgUseDarkMode)
			{
				$Global:BaselineUseDarkMode = [bool]$bgUseDarkMode
			}
			$Script:RunState = $runState
			function Write-GuiTweakExecutionWorkerStartupNotice
			{
				param(
					[Parameter(Mandatory = $true)]
					[string]$Message,
					[ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
					[string]$Level = 'DEBUG',
					[switch]$Progress
				)

				try
				{
					if ($Script:RunState -and $Script:RunState['LogQueue'])
					{
						$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
							Kind = '_RunNotice'
							Level = $Level
							Message = $Message
							Progress = [bool]$Progress
							Diagnostic = $true
						})
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Worker.EnqueueStartupNotice'
					}
				}
			}
			Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker entered background runspace.' -Progress

			# Load JSON and localization helpers in the background runspace before importing the execution module.
			Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker loading JSON and localization helpers.' -Progress
			$bgModuleRoot = Split-Path $bgLoaderPath -Parent
			$bgJsonHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Json.Helpers.ps1'
			$bgHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Localization.Helpers.ps1'
			. $bgJsonHelperPath
			. $bgHelperPath
			$Global:Localization = Import-BaselineLocalization -BaseDirectory $bgLocDir -UICulture $bgUICulture
			[void](Set-BaselineThreadCulture -UICulture $bgUICulture)

			# Module import must be side-effect-free (no Write-Host, no state mutation)
			# because this runs in a fresh background runspace.
			try
			{
				Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker importing Baseline modules.' -Progress
				$Global:LogFilePath = $bgLogFilePath
				Import-Module $bgLoaderPath -Force -Global -ErrorAction Stop
				if (Get-Command -Name Set-BaselineOperationMode -ErrorAction SilentlyContinue)
				{
					Set-BaselineOperationMode -Mode ([string]$bgOperationMode)
				}
				Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker imported Baseline modules.' -Progress
			}
			catch
			{
				$importError = $_.Exception.Message
				$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind = 'LogWarning'
					Message = "Background module import failed: $importError"
				})
				throw
			}

			$global:LogFilePath = $bgLogFilePath
			Set-LogFile -Path $bgLogFilePath
			Set-LogMode -Mode $bgLogMode
			Set-UILogHandler { param($entry) $Script:RunState['LogQueue'].Enqueue($entry) }
			Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker connected logging pipeline.' -Progress

			function Test-GuiExecutionValuePresent
			{
				param([AllowNull()][object]$Value)

				if ($null -eq $Value)
				{
					return $false
				}

				if ($Value -is [string])
				{
					return (-not [string]::IsNullOrWhiteSpace($Value))
				}

				return $true
			}

			function Add-GuiExecutionExtraArguments
			{
				param(
					[Parameter(Mandatory = $true)]
					[hashtable]$CommandArguments,

					[AllowNull()]
					[object]$Tweak
				)

				if ($Tweak -and (Test-GuiObjectField -Object $Tweak -FieldName 'ExtraArgs') -and $Tweak.ExtraArgs)
				{
					$Tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $CommandArguments[[string]$_.Key] = $_.Value }
				}

				return $CommandArguments
			}

			function New-GuiExecutionNumericRangeCommandArguments
			{
				param(
					[Parameter(Mandatory = $true)]
					[object]$Tweak
				)

				$valueSource = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Value')) { $Tweak.Value } else { $null }
				$acValue = if ((Test-GuiObjectField -Object $Tweak -FieldName 'ACValue')) { $Tweak.ACValue } elseif ((Test-GuiObjectField -Object $valueSource -FieldName 'ACValue')) { $valueSource.ACValue } else { $null }
				$dcValue = if ((Test-GuiObjectField -Object $Tweak -FieldName 'DCValue')) { $Tweak.DCValue } elseif ((Test-GuiObjectField -Object $valueSource -FieldName 'DCValue')) { $valueSource.DCValue } else { $null }
				$hasACValue = Test-GuiExecutionValuePresent -Value $acValue
				$hasDCValue = Test-GuiExecutionValuePresent -Value $dcValue

				if ($hasACValue -and $hasDCValue)
				{
					return Add-GuiExecutionExtraArguments -CommandArguments @{
						ACValue = [int]$acValue
						DCValue = [int]$dcValue
					} -Tweak $Tweak
				}

				if ($hasACValue -or $hasDCValue)
				{
					throw "The numeric range selection for '$($Tweak.Function)' must include both ACValue and DCValue, or a single Value."
				}

				$scalarValue = if ((Test-GuiObjectField -Object $Tweak -FieldName 'NumericValue')) { $Tweak.NumericValue } elseif ((Test-GuiObjectField -Object $Tweak -FieldName 'Value')) { $Tweak.Value } else { $null }
				if (Test-GuiExecutionValuePresent -Value $scalarValue)
				{
					return Add-GuiExecutionExtraArguments -CommandArguments @{ Value = [int]$scalarValue } -Tweak $Tweak
				}

				throw "The numeric range selection for '$($Tweak.Function)' did not include Value, NumericValue, or ACValue/DCValue to execute."
			}

			Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker validating selected tweak functions.' -Progress
			$missingFunctions = @(
				$tweakList |
					ForEach-Object { $_.Function } |
					Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
					Select-Object -Unique |
					Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }
			)
			if ($missingFunctions.Count -gt 0)
			{
				$loadedModules = @(Get-Module | Select-Object -ExpandProperty Name) -join ', '
				throw ("Required tweak functions were not loaded: {0}`nLoaded modules: {1}" -f ($missingFunctions -join ', '), $loadedModules)
			}

			try
			{
				$Script:RunState['PreRunSnapshot'] = $null
				$Script:RunState['PostRunSnapshot'] = $null

				Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker loading pre-run snapshot metadata.' -Progress
				$snapshotDetectScriptblocks = @{}
				$snapshotVisibleIfScriptblocks = @{}
				$detectScriptblocksPath = Join-Path $bgModuleRoot 'GUI\DetectScriptblocks.ps1'
				if (Test-Path -LiteralPath $detectScriptblocksPath)
				{
					. $detectScriptblocksPath
					$detectScriptblocksVariable = Get-Variable -Scope Script -Name 'DetectScriptblocks' -ErrorAction SilentlyContinue
					$visibleIfScriptblocksVariable = Get-Variable -Scope Script -Name 'VisibleIfScriptblocks' -ErrorAction SilentlyContinue
					if ($detectScriptblocksVariable -and $detectScriptblocksVariable.Value -is [hashtable])
					{
						$snapshotDetectScriptblocks = $detectScriptblocksVariable.Value
					}
					if ($visibleIfScriptblocksVariable -and $visibleIfScriptblocksVariable.Value -is [hashtable])
					{
						$snapshotVisibleIfScriptblocks = $visibleIfScriptblocksVariable.Value
					}
				}

				$snapshotManifest = Import-TweakManifestFromData -DetectScriptblocks $snapshotDetectScriptblocks -VisibleIfScriptblocks $snapshotVisibleIfScriptblocks
				try
				{
					Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker checking manifest availability.' -Progress
					$snapshotSystemInfo = Get-BaselineSystemPlatformInfo
					$null = Update-BaselineManifestAvailability -Manifest $snapshotManifest -SystemInfo $snapshotSystemInfo
					$null = Update-BaselineManifestExecutionSupport -Manifest $snapshotManifest
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.PreRunSnapshot.ManifestAvailabilityStamp'
				}

				Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker capturing pre-run system snapshot.' -Progress
				$snapshotTimeoutSeconds = Get-GuiPreRunSnapshotTimeoutSeconds
				$snapshotResult = Invoke-GuiPreRunSnapshotCapture `
					-LoaderPath $bgLoaderPath `
					-LocalizationDirectory $bgLocDir `
					-UICulture $bgUICulture `
					-LogFilePath $bgLogFilePath `
					-LogMode $bgLogMode `
					-OperationMode $bgOperationMode `
					-TimeoutSeconds $snapshotTimeoutSeconds `
					-RunState $Script:RunState

				if ($snapshotResult -and $snapshotResult.Succeeded)
				{
					$preRunSnapshot = $snapshotResult.Snapshot
					$snapshotPath = [string]$snapshotResult.SnapshotPath
					$Script:RunState['PreRunSnapshot'] = $preRunSnapshot
					$Script:RunState['PreRunSnapshotPath'] = $snapshotPath
					$Script:RunState['PreRunSnapshotTimedOut'] = $false
					LogDebug -Message (Get-BaselineBilingualString -Key 'GuiLogExecutionPreRunSnapshotSaved' -Fallback 'Pre-run snapshot saved: {0} entries captured to {1}' -FormatArgs @([int]$snapshotResult.EntryCount, $snapshotPath)) -Always
					Write-GuiTweakExecutionWorkerStartupNotice -Message ("Execution worker captured pre-run snapshot: {0} entries." -f [int]$snapshotResult.EntryCount) -Progress
				}
				elseif ($snapshotResult -and $snapshotResult.Aborted)
				{
					$Script:RunState['AbortedRun'] = $true
					$Script:RunState['PreRunSnapshotAborted'] = $true
					Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker pre-run snapshot capture was aborted.' -Level 'WARNING' -Progress
				}
				elseif ($snapshotResult -and $snapshotResult.TimedOut)
				{
					$lastSnapshotProgress = $snapshotResult.LastProgress
					$lastSnapshotLabel = 'snapshot capture'
					if ($lastSnapshotProgress)
					{
						$stage = if ($lastSnapshotProgress.PSObject.Properties['Stage']) { [string]$lastSnapshotProgress.Stage } else { '' }
						$functionName = if ($lastSnapshotProgress.PSObject.Properties['Function']) { [string]$lastSnapshotProgress.Function } else { '' }
						$entryName = if ($lastSnapshotProgress.PSObject.Properties['Name']) { [string]$lastSnapshotProgress.Name } else { '' }
						if ($stage -eq 'SystemInfo')
						{
							$lastSnapshotLabel = 'system information'
						}
						elseif (-not [string]::IsNullOrWhiteSpace($functionName))
						{
							$lastSnapshotLabel = $functionName
							if (-not [string]::IsNullOrWhiteSpace($entryName) -and $entryName -ne $functionName)
							{
								$lastSnapshotLabel = '{0} ({1})' -f $functionName, $entryName
							}
						}
						elseif (-not [string]::IsNullOrWhiteSpace($entryName))
						{
							$lastSnapshotLabel = $entryName
						}
					}

					$Script:RunState['PreRunSnapshotTimedOut'] = $true
					$Script:RunState['PreRunSnapshotTimeoutSeconds'] = $snapshotTimeoutSeconds
					$Script:RunState['PreRunSnapshotLastProgress'] = $lastSnapshotProgress
					$timeoutMessage = 'Execution worker pre-run snapshot exceeded {0} second(s) while checking {1}; continuing with selected tweaks.' -f $snapshotTimeoutSeconds, $lastSnapshotLabel
					LogDebug -Message $timeoutMessage -Always
					Write-GuiTweakExecutionWorkerStartupNotice -Message $timeoutMessage -Level 'WARNING' -Progress
				}
				else
				{
					$errorMessage = if ($snapshotResult -and -not [string]::IsNullOrWhiteSpace([string]$snapshotResult.ErrorMessage)) { [string]$snapshotResult.ErrorMessage } else { 'Pre-run snapshot capture failed.' }
					LogDebug -Message (Get-BaselineBilingualString -Key 'GuiLogExecutionPreRunSnapshotFailed' -Fallback 'Failed to capture pre-run snapshot: {0}' -FormatArgs @($errorMessage)) -Always
					Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker could not capture pre-run snapshot; continuing with selected tweaks.' -Level 'WARNING' -Progress
				}
			}
			catch
			{
				LogDebug -Message (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-BaselineBilingualString -Key 'GuiLogExecutionPreRunSnapshotFailed' -Fallback 'Failed to capture pre-run snapshot')) -Always
				Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker could not capture pre-run snapshot; continuing with selected tweaks.' -Level 'WARNING' -Progress
			}

			Write-GuiTweakExecutionWorkerStartupNotice -Message 'Execution worker creating action host.' -Progress
			$actionHost = New-GuiExecutionActionHost `
				-LoaderPath $bgLoaderPath `
				-LocalizationDirectory $bgLocDir `
				-UICulture $bgUICulture `
				-LogFilePath $bgLogFilePath `
				-LogMode $bgLogMode `
				-OperationMode $bgOperationMode `
				-LogQueue $Script:RunState['LogQueue']

			$stepIndex = 0
			$stepTotal = $tweakList.Count
			Write-GuiTweakExecutionWorkerStartupNotice -Message ("Execution worker starting selected tweaks: {0} item(s)." -f $stepTotal) -Progress
			foreach ($tweak in $tweakList)
			{
				while ($Script:RunState['Paused'] -and -not $Script:RunState['AbortRequested'])
				{
					Start-Sleep -Milliseconds 250
				}

				if ($Script:RunState['AbortRequested'])
				{
					$Script:RunState['AbortedRun'] = $true
					break
				}

				$stepIndex++
				$Global:CurrentTweakName = $tweak.Name
				$Script:RunState['CurrentTweak'] = $tweak.Name
				$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind = '_TweakStarted'
					Key = $tweak.Key
					Name = $tweak.Name
					StepIndex = $stepIndex
					StepTotal = $stepTotal
				})

				$tweakErrorBaseline = if ($Global:Error) { $Global:Error.Count } else { 0 }
				$tweakErrorMessage = $null
				$tweakFailed = $false

				$availabilityGate = Resolve-GuiExecutionAvailabilityGate -Entry $tweak -ForceUnsupported:$bgForceUnsupported
				if ($availabilityGate.Decision -eq 'Block')
				{
					$skipDetail = if ([string]::IsNullOrWhiteSpace($availabilityGate.Reason)) { 'Not available on this system.' } else { $availabilityGate.Reason }
					LogInfo (Get-BaselineBilingualString -Key 'GuiLogExecutionSkippedNotApplicable' -Fallback 'Skipped - not available on this system: {0} - {1}' -FormatArgs @([string]$tweak.Function, $skipDetail))
					$Script:RunState['SkippedTweaks'][[string]$tweak.Key] = $skipDetail
					$completedCount = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'CompletedCount'
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = 'not applicable'
						Message = $skipDetail
						Count = $completedCount
						StepIndex = $stepIndex
						StepTotal = $stepTotal
					})
					continue
				}
				if ($availabilityGate.Decision -eq 'Force')
				{
					LogWarning (Get-BaselineBilingualString -Key 'GuiLogExecutionForceUnsupportedAvailability' -Fallback 'Forcing execution of unavailable entry: {0} - {1}' -FormatArgs @([string]$tweak.Function, $availabilityGate.Reason))
				}

				$supportsExecutionGate = Resolve-GuiExecutionSupportsExecutionGate -Entry $tweak -ForceUnsupported:$bgForceUnsupported
				if ($supportsExecutionGate.Decision -eq 'Block')
				{
					$skipDetail = if ([string]::IsNullOrWhiteSpace($supportsExecutionGate.Reason)) { 'Execution not supported on this system.' } else { $supportsExecutionGate.Reason }
					LogInfo (Get-BaselineBilingualString -Key 'GuiLogExecutionSkippedNotExecutable' -Fallback 'Skipped - execution not supported on this system: {0}' -FormatArgs @([string]$tweak.Function))
					$Script:RunState['SkippedTweaks'][[string]$tweak.Key] = $skipDetail
					$null = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'NotExecutableCount'
					$completedCount = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'CompletedCount'
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = 'not applicable'
						Message = $skipDetail
						Count = $completedCount
						StepIndex = $stepIndex
						StepTotal = $stepTotal
					})
					continue
				}
				if ($supportsExecutionGate.Decision -eq 'Force')
				{
					LogWarning (Get-BaselineBilingualString -Key 'GuiLogExecutionForceUnsupportedExecution' -Fallback 'Forcing execution of non-executable entry: {0} - {1}' -FormatArgs @([string]$tweak.Function, $supportsExecutionGate.Reason))
				}

				try
				{
					$commandArguments = @{}

					switch ($tweak.Type)
					{
						'Toggle'
						{
							$toggleParam = if (-not [string]::IsNullOrWhiteSpace([string]$tweak.ToggleParam)) { [string]$tweak.ToggleParam } else { [string]$tweak.OnParam }
							if ([string]::IsNullOrWhiteSpace($toggleParam))
							{
								throw "The toggle selection for '$($tweak.Function)' did not include a parameter to execute."
							}
							$commandArguments = @{ $toggleParam = $true }
						}
						'NumericRange'
						{
							$commandArguments = New-GuiExecutionNumericRangeCommandArguments -Tweak $tweak
						}
						'Date'
						{
							$enableParam = if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam)) { [string]$tweak.OnParam } else { 'Enable' }
							$disableParam = if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam)) { [string]$tweak.OffParam } else { 'Disable' }
							if ($tweak.Run)
							{
								$dateParamName = if (-not [string]::IsNullOrWhiteSpace([string]$tweak.DateParam)) { [string]$tweak.DateParam } else { 'StartDate' }
								$dateValue = if ((Test-GuiObjectField -Object $tweak -FieldName 'DateValue') -and -not [string]::IsNullOrWhiteSpace([string]$tweak.DateValue))
								{
									[string]$tweak.DateValue
								}
								elseif ((Test-GuiObjectField -Object $tweak -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$tweak.Value))
								{
									[string]$tweak.Value
								}
								else
								{
									$null
								}

								if ([string]::IsNullOrWhiteSpace($dateValue))
								{
									throw "The date selection for '$($tweak.Function)' did not include a date to execute."
								}

								$commandArguments = @{}
								$commandArguments[$enableParam] = $true
								$commandArguments[$dateParamName] = $dateValue
								if ($tweak.ExtraArgs)
								{
									$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $commandArguments[[string]$_.Key] = $_.Value }
								}
							}
							else
							{
								$commandArguments = @{}
								$commandArguments[$disableParam] = $true
								if ($tweak.ExtraArgs)
								{
									$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $commandArguments[[string]$_.Key] = $_.Value }
								}
							}
						}
						'Choice'
						{
							$choiceParam = [string]$tweak.Value
							if ([string]::IsNullOrWhiteSpace($choiceParam))
							{
								throw "The choice selection for '$($tweak.Function)' did not include a parameter to execute."
							}
							$choiceOptions = @()
							if (Test-GuiObjectField -Object $tweak -FieldName 'Options')
							{
								$choiceOptions = @($tweak.Options | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
							}
							if ($choiceOptions.Count -gt 0 -and $choiceParam -notin $choiceOptions)
							{
								throw "The choice selection for '$($tweak.Function)' is invalid: '$choiceParam'. Expected one of: $($choiceOptions -join ', ')."
							}
							$commandArguments = @{ $choiceParam = $true }
							if ($tweak.ExtraArgs)
							{
								$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $commandArguments[[string]$_.Key] = $_.Value }
							}
						}
						'Action'
						{
							$actionParam = [string]$tweak.OnParam
							if (-not [string]::IsNullOrWhiteSpace($actionParam))
							{
								$commandArguments[$actionParam] = $true
							}
							if ($tweak.ExtraArgs)
							{
								$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $commandArguments[[string]$_.Key] = $_.Value }
							}
						}
						default
						{
							$commandArguments = @{}
						}
					}

					$timeoutSeconds = Get-GuiExecutionActionTimeoutSeconds -Entry $tweak -ExecutionClass 'Tweak'
					$timedInvocation = Invoke-GuiExecutionActionHostCommand `
						-ActionHost $actionHost `
						-CommandName ([string]$tweak.Function) `
						-CommandArguments $commandArguments `
						-TimeoutSeconds $timeoutSeconds `
						-RunState $Script:RunState

					if ($timedInvocation.HostRequiresReset)
					{
						Close-GuiExecutionActionHost -ActionHost $actionHost -NonBlocking
						$actionHost = New-GuiExecutionActionHost `
							-LoaderPath $bgLoaderPath `
							-LocalizationDirectory $bgLocDir `
							-UICulture $bgUICulture `
							-LogFilePath $bgLogFilePath `
							-LogMode $bgLogMode `
							-OperationMode $bgOperationMode `
							-LogQueue $Script:RunState['LogQueue']
					}

					if ($timedInvocation.Aborted)
					{
						$Script:RunState['AbortedRun'] = $true
						break
					}

					if ($timedInvocation.TimedOut)
					{
						$isCriticalAction = Test-GuiExecutionCriticalAction -Entry $tweak
						$tweakFailed = $true
						$tweakErrorMessage = if ($isCriticalAction)
						{
							"Timed out after $timeoutSeconds second(s). This action is marked critical, so the run will abort."
						}
						else
						{
							"Timed out after $timeoutSeconds second(s), continuing to the next item."
						}

						Write-GuiExecutionTimeoutRecord `
							-ActionId ([string]$tweak.Key) `
							-ActionName ([string]$tweak.Name) `
							-ActionType 'Tweak' `
							-TimeoutSeconds $timeoutSeconds `
							-StartedAt $timedInvocation.StartedAt `
							-EndedAt $timedInvocation.EndedAt `
							-CommandName ([string]$tweak.Function) `
							-Continued:(-not $isCriticalAction) `
							-Aborted:$isCriticalAction `
							-Result 'Timed Out' `
							-Message $tweakErrorMessage

						if ($isCriticalAction)
						{
							$Script:RunState['AbortedRun'] = $true
						}
					}
					elseif (-not $timedInvocation.Succeeded)
					{
						$tweakFailed = $true
						$tweakErrorMessage = $timedInvocation.ErrorMessage
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUIExecution\Start-GuiExecutionWorker\Start-GuiExecutionWorker.ps1:548' -Severity Debug }

					$tweakFailed = $true
					$tweakErrorMessage = $_.Exception.Message
				}

				if ($Script:RunState['AbortedRun'] -and $tweakFailed -and $tweakErrorMessage -match 'Timed out after')
				{
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_RunNotice'
						Level = 'WARNING'
						Message = $tweakErrorMessage
					})
				}

				if (-not $tweakFailed)
				{
					$newErrors = @(Get-NewUnhandledErrorRecords -BaselineCount $tweakErrorBaseline)
					if ($newErrors.Count -gt 0)
					{
						$tweakFailed = $true
						$tweakErrorMessage = $newErrors[0].Exception.Message
					}
				}

				$Global:CurrentTweakName = $null

				if (-not $tweakFailed)
				{
					$Script:RunState['AppliedFunctions'].Add($tweak.Function)
					$completedCount = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'CompletedCount'
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = 'success'
						Count = $completedCount
						StepIndex = $stepIndex
						StepTotal = $stepTotal
					})
				}
				else
				{
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakFailed'
						Key = $tweak.Key
						Name = $tweak.Name
						Error = $tweakErrorMessage
						StepIndex = $stepIndex
						StepTotal = $stepTotal
					})
					$null = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'ErrorCount'
					$completedCount = Update-GuiRunStateCounter -RunState $Script:RunState -Key 'CompletedCount'
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakCompleted'
						Key = $tweak.Key
						Name = $tweak.Name
						Status = $(if ($tweakErrorMessage -match '^Timed out after ') { 'Timed Out' } else { 'failed' })
						Message = $tweakErrorMessage
						Count = $completedCount
						StepIndex = $stepIndex
						StepTotal = $stepTotal
					})

					if ($Script:RunState['AbortedRun'] -and $tweakErrorMessage -match '^Timed out after ')
					{
						break
					}
				}
			}

			if (-not $Script:RunState['AbortedRun'])
			{
				PostActions
				Errors
			}
			else
			{
				LogWarning (Get-BaselineBilingualString -Key 'GuiLogExecutionAbortedByUser' -Fallback '{0} execution aborted by user before all selected tweaks finished.' -FormatArgs @($executionMode))
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUIExecution\Start-GuiExecutionWorker\Start-GuiExecutionWorker.ps1:629' -Severity Debug }

			$fatalMessage = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Unexpected fatal run error.' } else { [string]$_.Exception.Message }
			$diagnosticLines = [System.Collections.Generic.List[string]]::new()
			if ($Script:RunState -and -not [string]::IsNullOrWhiteSpace([string]$Script:RunState['CurrentTweak']))
			{
				[void]$diagnosticLines.Add(("Current tweak: {0}" -f [string]$Script:RunState['CurrentTweak']))
			}
			if ($_.Exception)
			{
				[void]$diagnosticLines.Add(("Exception type: {0}" -f $_.Exception.GetType().FullName))
			}
			if ($_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace([string]$_.InvocationInfo.PositionMessage))
			{
				[void]$diagnosticLines.Add('Invocation:')
				[void]$diagnosticLines.Add([string]$_.InvocationInfo.PositionMessage.Trim())
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace))
			{
				[void]$diagnosticLines.Add('Script stack trace:')
				[void]$diagnosticLines.Add([string]$_.ScriptStackTrace.Trim())
			}

			$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
				Kind = '_RunError'
				Error = $fatalMessage
				Diagnostic = ($diagnosticLines -join "`n")
			})
		}
		finally
		{
			if ($actionHost)
			{
				Close-GuiExecutionActionHost -ActionHost $actionHost -NonBlocking
			}
			Clear-LogMode
			$Script:RunState['Done'] = $true
		}
	})
