$worker = [powershell]::Create().AddScript({
		$bgTracePath = Join-Path $env:TEMP 'Baseline-AppWorker-trace.txt'
		function Write-BgTrace
		{
			param([string]$Message)
			try
			{
				"$([DateTime]::UtcNow.ToString('o'))`t$Message" | Out-File -FilePath $bgTracePath -Append -Encoding UTF8 -Force
			}
			catch
			{
				Write-Warning ("GUIExecution worker trace write failed: " + $_.Exception.Message)
			}
		}

		function Enqueue-AppExecutionEvent
		{
			param (
				[string]$Kind,
				[string]$Name = $null,
				[string]$Status = $null,
				[string]$Message = $null,
				[int]$StepIndex = 0,
				[int]$StepTotal = 0,
				[string]$Action = $null
			)

			if (-not $Script:RunState -or -not $Script:RunState['LogQueue'])
			{
				return
			}

			$payload = [ordered]@{
				Kind = $Kind
			}
			if (-not [string]::IsNullOrWhiteSpace($Name)) { $payload['Name'] = $Name }
			if (-not [string]::IsNullOrWhiteSpace($Status)) { $payload['Status'] = $Status }
			if (-not [string]::IsNullOrWhiteSpace($Message)) { $payload['Message'] = $Message }
			if ($StepIndex -gt 0) { $payload['StepIndex'] = $StepIndex }
			if ($StepTotal -gt 0) { $payload['StepTotal'] = $StepTotal }
			if (-not [string]::IsNullOrWhiteSpace($Action)) { $payload['Action'] = $Action }

			$Script:RunState['LogQueue'].Enqueue([pscustomobject]$payload)
		}

		function Add-AppExecutionResultEntry
		{
			param (
				[System.Collections.Generic.List[object]]$Collection,
				[object]$Route,
				[string]$Error = $null
			)

			if ($null -eq $Collection -or $null -eq $Route)
			{
				return
			}

			$entry = New-GuiExecutionAppBatchEntry -Route $Route -Error $Error
			if ($entry)
			{
				[void]$Collection.Add($entry)
			}
		}

		Write-BgTrace "--- worker start ---"
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
			function Write-GuiAppExecutionWorkerStartupNotice
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
					Write-BgTrace ("Failed to enqueue app worker startup notice: {0}" -f $_.Exception.Message)
				}
			}
			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker entered background runspace.' -Progress
			Write-BgTrace "GUIMode set, RunState assigned"

			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker loading JSON and localization helpers.' -Progress
			$bgModuleRoot = Split-Path -Parent (Split-Path -Parent $bgLoaderPath)
			$bgHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Localization.Helpers.ps1'
			$bgJsonHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Json.Helpers.ps1'
			Write-BgTrace ("bgLoaderPath={0}" -f $bgLoaderPath)
			Write-BgTrace ("bgModuleRoot={0}" -f $bgModuleRoot)
			Write-BgTrace ("bgHelperPath={0} exists={1}" -f $bgHelperPath, (Test-Path $bgHelperPath))
			Write-BgTrace ("bgJsonHelperPath={0} exists={1}" -f $bgJsonHelperPath, (Test-Path $bgJsonHelperPath))
			# Import-BaselineLocalization calls ConvertFrom-BaselineJson, which
			# lives in Json.Helpers.ps1. It must be available first, otherwise
			# the worker dies with "CommandNotFoundException: ConvertFrom-BaselineJson"
			# before reaching Invoke-ApplicationAction.
			. $bgJsonHelperPath
			Write-BgTrace "Json.Helpers ready"
			. $bgHelperPath
			Write-BgTrace "Localization.Helpers ready"
			$Global:Localization = Import-BaselineLocalization -BaseDirectory $bgLocDir -UICulture $bgUICulture
			Write-BgTrace "Import-BaselineLocalization done"
			[void](Set-BaselineThreadCulture -UICulture $bgUICulture)
			Write-BgTrace "Set-BaselineThreadCulture done"

			if ([string]::IsNullOrWhiteSpace([string]$bgGuiExecutionModulePath))
			{
				throw 'GUI execution helper module path was not supplied to the app worker runspace.'
			}
			if ([string]::IsNullOrWhiteSpace([string]$bgActionHostLoaderPath))
			{
				throw 'Action host loader path was not supplied to the app worker runspace.'
			}

			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker importing GUI execution helpers.' -Progress
			Write-BgTrace ("Import-Module GUIExecution.psm1 START path={0}" -f $bgGuiExecutionModulePath)
			Import-Module $bgGuiExecutionModulePath -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
			Write-BgTrace ("Import-Module GUIExecution.psm1 DONE actionHostLoader={0}" -f $bgActionHostLoaderPath)
			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker imported GUI execution helpers.' -Progress

			# Module import must be side-effect-free (no Write-Host, no state mutation)
			# because this runs in a fresh background runspace.
			try
			{
				Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker importing application modules.' -Progress
				Write-BgTrace "Import-Module Applications.psm1 START"
				$Global:LogFilePath = $bgLogFilePath
				Import-Module $bgLoaderPath -Force -Global -ErrorAction Stop
				if (Get-Command -Name Set-BaselineOperationMode -ErrorAction SilentlyContinue)
				{
					Set-BaselineOperationMode -Mode ([string]$bgOperationMode)
				}
				Write-BgTrace "Import-Module Applications.psm1 DONE"
				Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker imported application modules.' -Progress
			}
			catch
			{
				$importError = $_.Exception.Message
				Write-BgTrace ("Import-Module FAILED: {0}" -f $importError)
				if ($Script:RunState -and $Script:RunState['LogQueue'])
				{
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = 'LogWarning'
						Message = "Background app module import failed: $importError"
					})
				}
				throw
			}

			$global:LogFilePath = $bgLogFilePath
			Set-LogFile -Path $bgLogFilePath
			Set-LogMode -Mode $bgLogMode
			if ($Script:RunState -and $Script:RunState['LogQueue'])
			{
				Set-UILogHandler { param($entry) $Script:RunState['LogQueue'].Enqueue($entry) }
			}
			else
			{
				Clear-UILogHandler
			}
			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker connected logging pipeline.' -Progress
			Write-BgTrace ("Log plumbing configured. runAction={0} winget={1} choco={2} displayName={3} appPresent={4} selCount={5}" -f $runAction, $packageId, $chocolateyId, $displayName, ($null -ne $application), @($selectedApps).Count)

			Write-GuiAppExecutionWorkerStartupNotice -Message 'Execution worker creating action host.' -Progress
			$actionHost = New-GuiExecutionActionHost `
				-LoaderPath $bgActionHostLoaderPath `
				-LocalizationDirectory $bgLocDir `
				-UICulture $bgUICulture `
				-LogFilePath $bgLogFilePath `
				-LogMode $bgLogMode `
				-OperationMode $bgOperationMode `
				-LogQueue $null

			try
			{
				$actionVerb = Get-GuiExecutionAppActionVerb -Action $runAction
				$successfulApps = [System.Collections.Generic.List[object]]::new()
				$failedApps = [System.Collections.Generic.List[object]]::new()
				$appTargets = @()
				if ($selectedApps -and @($selectedApps).Count -gt 0 -and $runAction -in @('Install', 'Uninstall', 'Update'))
				{
					$appTargets = @($selectedApps | Where-Object { $_ })
				}
				elseif ($application -and $runAction -in @('Install', 'Uninstall', 'Update'))
				{
					$appTargets = @($application)
				}

				if ($appTargets.Count -gt 0)
				{
					$uniqueIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
					$queuedApps = [System.Collections.Generic.List[object]]::new()
					foreach ($appTarget in @($appTargets))
					{
						$route = Resolve-ApplicationExecutionRoute -Application $appTarget -PreferredSource $preferredSource -PackageManagerAvailabilityState $packageManagerAvailabilityState -Action $runAction
						$identityKey = if (-not [string]::IsNullOrWhiteSpace([string]$route.IdentityKey)) { [string]$route.IdentityKey } else { [string]([guid]::NewGuid()) }
						if (-not $uniqueIds.Add($identityKey))
						{
							continue
						}

						[void]$queuedApps.Add([pscustomobject]@{
							Application = $appTarget
							Route = $route
							TimeoutSeconds = Get-GuiExecutionActionTimeoutSeconds -Entry $appTarget -ExecutionClass 'App'
						})
					}

					$stepTotal = [Math]::Max($queuedApps.Count, 1)
					if ($Script:RunState)
					{
						$Script:RunState['AppProgressTotal'] = $stepTotal
						$Script:RunState['AppProgressIndeterminate'] = $false
					}
					Write-GuiAppExecutionWorkerStartupNotice -Message ("Execution worker starting selected apps: {0} item(s)." -f $queuedApps.Count) -Progress

					$stepIndex = 0
					foreach ($queuedApp in @($queuedApps))
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
						$route = $queuedApp.Route
						$appName = if (-not [string]::IsNullOrWhiteSpace([string]$route.DisplayName)) { [string]$route.DisplayName } else { 'Application' }
						$timeoutSeconds = [int]$queuedApp.TimeoutSeconds
						$Script:RunState['CurrentAction'] = $appName
						Enqueue-AppExecutionEvent -Kind '_AppStarted' -Name $appName -Action $runAction -StepIndex $stepIndex -StepTotal $stepTotal

						if ($route.Route -eq 'unsupported')
						{
							$failureMessage = if (-not [string]::IsNullOrWhiteSpace([string]$route.Reason)) { [string]$route.Reason } else { "$actionVerb $appName - failed." }
							Add-AppExecutionResultEntry -Collection $failedApps -Route $route -Error $failureMessage
							Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $appName -Action $runAction -Status 'Failed' -Message $failureMessage -StepIndex $stepIndex -StepTotal $stepTotal
							continue
						}

						$timedInvocation = Invoke-GuiExecutionActionHostCommand `
							-ActionHost $actionHost `
							-CommandName 'Invoke-ApplicationAction' `
							-CommandArguments @{
								Action = $runAction
								Application = $queuedApp.Application
								PreferredSource = $preferredSource
								PackageManagerAvailabilityState = $packageManagerAvailabilityState
								TimeoutSeconds = $timeoutSeconds
							} `
							-TimeoutSeconds $timeoutSeconds `
							-RunState $Script:RunState

						if ($timedInvocation.HostRequiresReset)
						{
							Close-GuiExecutionActionHost -ActionHost $actionHost
							$actionHost = New-GuiExecutionActionHost `
								-LoaderPath $bgActionHostLoaderPath `
								-LocalizationDirectory $bgLocDir `
								-UICulture $bgUICulture `
								-LogFilePath $bgLogFilePath `
								-LogMode $bgLogMode `
								-OperationMode $bgOperationMode `
								-LogQueue $null
						}

						if ($timedInvocation.Aborted)
						{
							$Script:RunState['AbortedRun'] = $true
							break
						}

						if (Test-GuiExecutionInvocationTimedOut -InvocationResult $timedInvocation)
						{
							$timeoutNotice = "{0} {1} - timed out after {2} second(s); verifying final state." -f $actionVerb, $appName, $timeoutSeconds
							Enqueue-AppExecutionEvent -Kind '_RunNotice' -Name $appName -Action $runAction -Status 'Timed Out' -Message $timeoutNotice -StepIndex $stepIndex -StepTotal $stepTotal

							$verificationTimeoutSeconds = [Math]::Min([Math]::Max($timeoutSeconds, 60), 300)
							$verificationInvocation = Invoke-GuiExecutionActionHostCommand `
								-ActionHost $actionHost `
								-CommandName 'Resolve-GuiAppTimeoutVerification' `
								-CommandArguments @{
									Action = $runAction
									Application = $queuedApp.Application
									PreferredSource = $preferredSource
									PackageManagerAvailabilityState = $packageManagerAvailabilityState
									TimeoutSeconds = $verificationTimeoutSeconds
								} `
								-TimeoutSeconds $verificationTimeoutSeconds `
								-RunState $Script:RunState

							if ($verificationInvocation.HostRequiresReset)
							{
								Close-GuiExecutionActionHost -ActionHost $actionHost
								$actionHost = New-GuiExecutionActionHost `
									-LoaderPath $bgActionHostLoaderPath `
									-LocalizationDirectory $bgLocDir `
									-UICulture $bgUICulture `
									-LogFilePath $bgLogFilePath `
									-LogMode $bgLogMode `
									-OperationMode $bgOperationMode `
									-LogQueue $null
							}

							$verificationAttempted = $false
							$verificationResultLabel = 'Unavailable'
							$resolvedStatus = 'Timed Out / Unknown Final State'
							$resolvedMessage = ("{0} {1} - timed out; final state could not be verified." -f $actionVerb, $appName)
							if ($verificationInvocation.Succeeded -and @($verificationInvocation.Output).Count -gt 0)
							{
								$verificationResult = @($verificationInvocation.Output)[0]
								$verificationAttempted = if ((Test-GuiExecutionObjectField -Object $verificationResult -FieldName 'VerificationAttempted')) { [bool]$verificationResult.VerificationAttempted } else { $false }
								$verificationResultLabel = if ((Test-GuiExecutionObjectField -Object $verificationResult -FieldName 'VerificationResult')) { [string]$verificationResult.VerificationResult } else { 'Unavailable' }
								if ((Test-GuiExecutionObjectField -Object $verificationResult -FieldName 'ResolvedStatus') -and -not [string]::IsNullOrWhiteSpace([string]$verificationResult.ResolvedStatus))
								{
									$resolvedStatus = [string]$verificationResult.ResolvedStatus
								}
								if ((Test-GuiExecutionObjectField -Object $verificationResult -FieldName 'Message') -and -not [string]::IsNullOrWhiteSpace([string]$verificationResult.Message))
								{
									$resolvedMessage = [string]$verificationResult.Message
								}
							}
							elseif (Test-GuiExecutionInvocationTimedOut -InvocationResult $verificationInvocation)
							{
								$verificationAttempted = $true
								$verificationResultLabel = 'TimedOut'
								$resolvedMessage = ("{0} {1} - timed out; verification also timed out before Baseline could confirm the final state." -f $actionVerb, $appName)
							}
							elseif (-not [string]::IsNullOrWhiteSpace([string]$verificationInvocation.ErrorMessage))
							{
								$verificationAttempted = $true
								$verificationResultLabel = if ((Test-GuiExecutionObjectField -Object $verificationInvocation -FieldName 'ErrorTypeName') -and -not [string]::IsNullOrWhiteSpace([string]$verificationInvocation.ErrorTypeName)) { [string]$verificationInvocation.ErrorTypeName } else { 'Failed' }
								$resolvedMessage = ("{0} {1} - timed out; verification failed ({2})." -f $actionVerb, $appName, [string]$verificationInvocation.ErrorMessage)
							}

							Write-GuiExecutionTimeoutRecord `
								-ActionId $(if (-not [string]::IsNullOrWhiteSpace([string]$route.IdentityKey)) { [string]$route.IdentityKey } else { [string]$appName }) `
								-ActionName $appName `
								-ActionType ("App{0}" -f $runAction) `
								-TimeoutSeconds $timeoutSeconds `
								-StartedAt $timedInvocation.StartedAt `
								-EndedAt $timedInvocation.EndedAt `
								-CommandName 'Invoke-ApplicationAction' `
								-VerificationAttempted:$verificationAttempted `
								-VerificationResult $verificationResultLabel `
								-Continued:$true `
								-Aborted:$false `
								-Result $resolvedStatus `
								-Message $resolvedMessage

							if ($resolvedStatus -in @('Success', 'Updated', 'Already Removed'))
							{
								Add-AppExecutionResultEntry -Collection $successfulApps -Route $route
							}
							else
							{
								Add-AppExecutionResultEntry -Collection $failedApps -Route $route -Error $resolvedMessage
							}

							Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $appName -Action $runAction -Status $resolvedStatus -Message $resolvedMessage -StepIndex $stepIndex -StepTotal $stepTotal
							continue
						}

						if (-not $timedInvocation.Succeeded)
						{
							$failureMessage = if (-not [string]::IsNullOrWhiteSpace([string]$timedInvocation.ErrorMessage))
							{
								[string]$timedInvocation.ErrorMessage
							}
							else
							{
								"{0} {1} - failed." -f $actionVerb, $appName
							}

							Add-AppExecutionResultEntry -Collection $failedApps -Route $route -Error $failureMessage
							Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $appName -Action $runAction -Status 'Failed' -Message $failureMessage -StepIndex $stepIndex -StepTotal $stepTotal
							continue
						}

						Add-AppExecutionResultEntry -Collection $successfulApps -Route $route
						$successStatus = if ($runAction -eq 'Update') { 'Updated' } else { 'Success' }
						$successMessage = "{0} {1} - success" -f $actionVerb, $appName
						Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $appName -Action $runAction -Status $successStatus -Message $successMessage -StepIndex $stepIndex -StepTotal $stepTotal
					}

					$appBatchResult = New-GuiExecutionAppBatchResult -Action $runAction -SuccessfulApps @($successfulApps) -FailedApps @($failedApps)
					if ($Script:RunState)
					{
						$Script:RunState['AppResult'] = $appBatchResult
						$Script:RunState['AppOutcome'] = [string]$appBatchResult.Outcome
						$Script:RunState['AppMessage'] = [string]$appBatchResult.Message
					}
				}
				else
				{
					Write-GuiAppExecutionWorkerStartupNotice -Message ("Execution worker starting app action: {0}." -f $runAction) -Progress
					$legacyTimeoutSeconds = Get-GuiExecutionActionTimeoutSeconds -Entry $application -ExecutionClass 'App'
					$legacyName = if (-not [string]::IsNullOrWhiteSpace([string]$displayName)) { [string]$displayName } else { [string]$runAction }
					Enqueue-AppExecutionEvent -Kind '_AppStarted' -Name $legacyName -Action $runAction -StepIndex 1 -StepTotal 1

					$legacyCommandName = switch ($runAction)
					{
						'Install' { 'AppInstall' }
						'Uninstall' { 'AppInstall' }
						'Update' { 'AppUpdate' }
						'UpdateAll' { 'AppUpdate' }
						default { throw "Unsupported app action '$runAction'." }
					}
					$legacyArguments = @{
						PackageManagerAvailabilityState = $packageManagerAvailabilityState
					}
					switch ($runAction)
					{
						'Install'
						{
							$legacyArguments['Install'] = $true
							$legacyArguments['WinGetId'] = $packageId
							$legacyArguments['ChocoId'] = $chocolateyId
							$legacyArguments['DisplayName'] = $displayName
							$legacyArguments['PreferredSource'] = $preferredSource
							$legacyArguments['TimeoutSeconds'] = $legacyTimeoutSeconds
						}
						'Uninstall'
						{
							$legacyArguments['Uninstall'] = $true
							$legacyArguments['WinGetId'] = $packageId
							$legacyArguments['ChocoId'] = $chocolateyId
							$legacyArguments['DisplayName'] = $displayName
							$legacyArguments['PreferredSource'] = $preferredSource
							$legacyArguments['TimeoutSeconds'] = $legacyTimeoutSeconds
						}
						'Update'
						{
							$legacyArguments['WinGetId'] = $packageId
							$legacyArguments['ChocoId'] = $chocolateyId
							$legacyArguments['DisplayName'] = $displayName
							$legacyArguments['PreferredSource'] = $preferredSource
							$legacyArguments['TimeoutSeconds'] = $legacyTimeoutSeconds
						}
						'UpdateAll'
						{
							$legacyArguments['All'] = $true
							$legacyArguments['TimeoutSeconds'] = $legacyTimeoutSeconds
						}
					}

					$legacyInvocation = Invoke-GuiExecutionActionHostCommand `
						-ActionHost $actionHost `
						-CommandName $legacyCommandName `
						-CommandArguments $legacyArguments `
						-TimeoutSeconds $legacyTimeoutSeconds `
						-RunState $Script:RunState

					if (Test-GuiExecutionInvocationTimedOut -InvocationResult $legacyInvocation)
					{
						$legacyTimeoutMessage = "{0} {1} - timed out after {2} second(s); Baseline continued." -f $actionVerb, $legacyName, $legacyTimeoutSeconds
						Write-GuiExecutionTimeoutRecord `
							-ActionId $legacyName `
							-ActionName $legacyName `
							-ActionType ("App{0}" -f $runAction) `
							-TimeoutSeconds $legacyTimeoutSeconds `
							-StartedAt $legacyInvocation.StartedAt `
							-EndedAt $legacyInvocation.EndedAt `
							-CommandName $legacyCommandName `
							-Continued:$true `
							-Aborted:$false `
							-Result 'Timed Out / Unknown Final State' `
							-Message $legacyTimeoutMessage
						if ($Script:RunState)
						{
							$Script:RunState['AppOutcome'] = 'Failed'
							$Script:RunState['AppResult'] = [pscustomobject]@{
								Action = $runAction
								Outcome = 'Failed'
								Message = $legacyTimeoutMessage
							}
						}
						Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $legacyName -Action $runAction -Status 'Timed Out / Unknown Final State' -Message $legacyTimeoutMessage -StepIndex 1 -StepTotal 1
					}
					elseif (-not $legacyInvocation.Succeeded)
					{
						$legacyFailureMessage = if (-not [string]::IsNullOrWhiteSpace([string]$legacyInvocation.ErrorMessage)) { [string]$legacyInvocation.ErrorMessage } else { "{0} {1} - failed." -f $actionVerb, $legacyName }
						if ($Script:RunState)
						{
							$Script:RunState['AppOutcome'] = 'Failed'
							$Script:RunState['AppResult'] = [pscustomobject]@{
								Action = $runAction
								Outcome = 'Failed'
								Message = $legacyFailureMessage
							}
						}
						Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $legacyName -Action $runAction -Status 'Failed' -Message $legacyFailureMessage -StepIndex 1 -StepTotal 1
					}
					else
					{
						if ($Script:RunState -and [string]::IsNullOrWhiteSpace([string]$Script:RunState['AppOutcome']))
						{
							$Script:RunState['AppOutcome'] = 'Success'
						}
						Enqueue-AppExecutionEvent -Kind '_AppCompleted' -Name $legacyName -Action $runAction -Status $(if ($runAction -eq 'Update') { 'Updated' } else { 'Success' }) -Message ("{0} {1} - success" -f $actionVerb, $legacyName) -StepIndex 1 -StepTotal 1
					}
				}

				if ($Script:RunState -and [string]::IsNullOrWhiteSpace([string]$Script:RunState['AppOutcome']))
				{
					$Script:RunState['AppOutcome'] = 'Success'
				}
			}
			finally
			{
				Close-GuiExecutionActionHost -ActionHost $actionHost
			}
		}
		catch
		{
			Write-BgTrace ("FATAL CATCH: type={0} msg={1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
			if ($_.ScriptStackTrace) { Write-BgTrace ("ScriptStackTrace: {0}" -f [string]$_.ScriptStackTrace) }
			if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) { Write-BgTrace ("PositionMessage: {0}" -f [string]$_.InvocationInfo.PositionMessage) }
			if ($Script:RunState -and [string]::IsNullOrWhiteSpace([string]$Script:RunState['AppOutcome']))
			{
				$Script:RunState['AppOutcome'] = 'Failed'
			}
			$fatalMessage = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Unexpected fatal app run error.' } else { [string]$_.Exception.Message }
			$diagnosticLines = [System.Collections.Generic.List[string]]::new()
			if ($Script:RunState -and -not [string]::IsNullOrWhiteSpace([string]$runAction))
			{
				[void]$diagnosticLines.Add(("Action: {0}" -f [string]$runAction))
			}
			if ($Script:RunState -and -not [string]::IsNullOrWhiteSpace([string]$packageId))
			{
				[void]$diagnosticLines.Add(("WinGet ID: {0}" -f [string]$packageId))
			}
			if ($Script:RunState -and -not [string]::IsNullOrWhiteSpace([string]$chocolateyId))
			{
				[void]$diagnosticLines.Add(("Chocolatey ID: {0}" -f [string]$chocolateyId))
			}
			if ($Script:RunState -and -not [string]::IsNullOrWhiteSpace([string]$displayName))
			{
				[void]$diagnosticLines.Add(("Display name: {0}" -f [string]$displayName))
			}
			if ($Script:RunState -and $application)
			{
				if ($application.PSObject.Properties['EntityType'] -and -not [string]::IsNullOrWhiteSpace([string]$application.EntityType))
				{
					[void]$diagnosticLines.Add(("Entity type: {0}" -f [string]$application.EntityType))
				}
				if ($application.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$application.Name))
				{
					[void]$diagnosticLines.Add(("Application: {0}" -f [string]$application.Name))
				}
			}
			if ($Script:RunState -and $selectedApps)
			{
				[void]$diagnosticLines.Add(("Selected apps: {0}" -f @($selectedApps).Count))
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
			if ($Script:RunState -and $Script:RunState['LogQueue'])
			{
				$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind = '_RunError'
					Error = $fatalMessage
					Diagnostic = ($diagnosticLines -join "`n")
				})
			}
			throw
		}
		finally
		{
			Clear-LogMode
			if ($Script:RunState)
			{
				$Script:RunState['Done'] = $true
			}
		}
	}.GetNewClosure())
