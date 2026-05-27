function Script:Get-GuiAppProgressOutcomeRank
{
	param(
		[string]$Status
	)

	if ([string]::IsNullOrWhiteSpace($Status)) { return -1 }

	switch -Regex ([string]$Status)
	{
		'^(Failed|Error|Timed Out / Unknown Final State)$' { return 40 }
		'^(Partial|Warning|Timed Out)$' { return 30 }
		'^(Skipped|Already Removed|Already Installed)$' { return 10 }
		'^(Running)$' { return 0 }
		'^(Success|Updated)$' { return 0 }
		default { return 20 }
	}
}

function Script:Set-GuiAppProgressOutcome
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$RunState,

		[string]$Status
	)

	if ([string]::IsNullOrWhiteSpace($Status)) { return }

	$currentStatus = if ($RunState.ContainsKey('AppOutcome')) { [string]$RunState['AppOutcome'] } else { $null }
	if ([string]::IsNullOrWhiteSpace($currentStatus))
	{
		$RunState['AppOutcome'] = [string]$Status
		return
	}

	if ((Get-GuiAppProgressOutcomeRank -Status $Status) -ge (Get-GuiAppProgressOutcomeRank -Status $currentStatus))
	{
		$RunState['AppOutcome'] = [string]$Status
	}
}

function Script:Get-GuiAppExecutionProgressVerb
{
	param(
		[string]$Action
	)

	switch ([string]$Action)
	{
		'Install' { return 'Installing' }
		'Uninstall' { return 'Uninstalling' }
		'Update' { return 'Updating' }
		'UpdateAll' { return 'Updating' }
		default { return 'Processing' }
	}
}

function Script:Get-GuiAppExecutionStatusLevel
{
	param(
		[string]$Status
	)

	switch -Regex ([string]$Status)
	{
		'^(Success|Updated)$' { return 'SUCCESS' }
		'^(Running)$' { return 'INFO' }
		'^(Timed Out|Timed Out / Unknown Final State|Warning)$' { return 'WARNING' }
		'^(Skipped|Already Removed|Already Installed)$' { return 'SKIP' }
		default { return 'ERROR' }
	}
}

function Script:Get-GuiAppExecutionStatusLabel
{
	param(
		[string]$Status
	)

	switch -Regex ([string]$Status)
	{
		'^(Success|Updated)$' { return 'success' }
		'^(Already Removed|Already Installed|Skipped)$' { return 'skip' }
		'^(Running)$' { return $null }
		'^(Timed Out|Timed Out / Unknown Final State|Warning)$' { return 'warning' }
		default { return 'error' }
	}
}

function Script:Write-GuiAppExecutionProgressLog
{
	param(
		[string]$Action,

		[string]$Name,

		[string]$Status = $null,

		[switch]$Started
	)

	$progressVerb = Get-GuiAppExecutionProgressVerb -Action $Action
	$appName = if (-not [string]::IsNullOrWhiteSpace([string]$Name)) { [string]$Name } else { 'Application' }
	if ($Started)
	{
		$message = '{0} {1}' -f $progressVerb, $appName
		$null = LogInfo $message
		return $message
	}

	$statusLabel = Get-GuiAppExecutionStatusLabel -Status $Status
	$level = Get-GuiAppExecutionStatusLevel -Status $Status
	$message = if ([string]::IsNullOrWhiteSpace([string]$statusLabel))
	{
		'{0} {1}' -f $progressVerb, $appName
	}
	else
	{
		'{0} {1} - {2}' -f $progressVerb, $appName, $statusLabel
	}
	switch ($level)
	{
		'INFO' { $null = LogInfo $message }
		'SUCCESS' { $null = LogInfo $message }
		'SKIP' { $null = LogWarning $message }
		'WARNING' { $null = LogWarning $message }
		default { $null = LogError $message }
	}

	return $message
}

function Script:Get-GuiAppExecutionLiveLogKey
{
	param(
		[int]$StepIndex,

		[int]$StepTotal
	)

	return '{0}/{1}' -f $StepIndex, $StepTotal
}

function Script:Get-GuiAppExecutionLiveLogMessage
{
	param(
		[int]$StepIndex,

		[int]$StepTotal,

		[string]$Message
	)

	$cleanMessage = ([string]$Message -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
	if ([string]::IsNullOrWhiteSpace($cleanMessage)) { return $null }

	if ($StepIndex -gt 0 -and $StepTotal -gt 0)
	{
		return '[{0}/{1}] {2}' -f $StepIndex, $StepTotal, $cleanMessage
	}

	return $cleanMessage
}

function Script:Get-GuiAppExecutionSummaryFieldValue
{
	param(
		[AllowNull()]
		[object]$Object,

		[Parameter(Mandatory = $true)]
		[string]$FieldName
	)

	if (-not (Test-GuiObjectField -Object $Object -FieldName $FieldName))
	{
		return $null
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return $Object[$FieldName]
	}

	return $Object.$FieldName
}

function Script:Write-GuiAppExecutionSummaryToLog
{
	param(
		[string]$Action,

		[AllowNull()]
		[object]$Result,

		[bool]$AbortedRun = $false
	)

	if (-not $Result)
	{
		return
	}

	$successfulApps = @((Get-GuiAppExecutionSummaryFieldValue -Object $Result -FieldName 'SuccessfulApps') | Where-Object { $_ })
	$failedApps = @((Get-GuiAppExecutionSummaryFieldValue -Object $Result -FieldName 'FailedApps') | Where-Object { $_ })
	$successCount = if (Test-GuiObjectField -Object $Result -FieldName 'SuccessCount') { [int]$Result.SuccessCount } else { $successfulApps.Count }
	$failureCount = if (Test-GuiObjectField -Object $Result -FieldName 'FailureCount') { [int]$Result.FailureCount } else { $failedApps.Count }
	$totalCount = if (Test-GuiObjectField -Object $Result -FieldName 'TotalCount') { [int]$Result.TotalCount } else { $successCount + $failureCount }
	$outcome = if (Test-GuiObjectField -Object $Result -FieldName 'Outcome') { [string]$Result.Outcome } else { 'Success' }

	$summaryMessage = 'App execution summary: Success={0}, Failed={1}, Total={2}, Outcome={3}, Aborted={4}.' -f $successCount, $failureCount, $totalCount, $outcome, $AbortedRun
	if ($failureCount -gt 0 -and $successCount -gt 0)
	{
		LogWarning $summaryMessage
	}
	elseif ($failureCount -gt 0)
	{
		LogError $summaryMessage
	}
	else
	{
		LogInfo $summaryMessage
	}

	foreach ($appEntry in $successfulApps)
	{
		$name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Name')
		if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'PackageId') }
		if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'SelectionKey') }
		if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Application' }

		$selectedSource = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'SelectedSource')
		$packageId = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'PackageId')
		$route = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Route')
		LogInfo ('Run summary | Success | [Apps] {0} | {1} | Type: Application | Source: {2} | Package: {3} | Route: {4} | Outcome: Success' -f $name, $Action, $(if ([string]::IsNullOrWhiteSpace($selectedSource)) { 'n/a' } else { $selectedSource }), $(if ([string]::IsNullOrWhiteSpace($packageId)) { 'n/a' } else { $packageId }), $(if ([string]::IsNullOrWhiteSpace($route)) { 'n/a' } else { $route }))
	}

	foreach ($appEntry in $failedApps)
	{
		$name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Name')
		if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'PackageId') }
		if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'SelectionKey') }
		if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Application' }

		$selectedSource = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'SelectedSource')
		$packageId = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'PackageId')
		$route = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Route')
		$errorText = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Error')
		LogError ('Run summary | Failed | [Apps] {0} | {1} | Type: Application | Source: {2} | Package: {3} | Route: {4} | Outcome: Failed | {5}' -f $name, $Action, $(if ([string]::IsNullOrWhiteSpace($selectedSource)) { 'n/a' } else { $selectedSource }), $(if ([string]::IsNullOrWhiteSpace($packageId)) { 'n/a' } else { $packageId }), $(if ([string]::IsNullOrWhiteSpace($route)) { 'n/a' } else { $route }), $(if ([string]::IsNullOrWhiteSpace($errorText)) { 'No detailed error was reported.' } else { $errorText }))
	}
}

function Script:Get-GuiAppExecutionSummaryActionLabel
{
	param(
		[string]$Action
	)

	switch ([string]$Action)
	{
		'Install' { return 'Install' }
		'Uninstall' { return 'Uninstall' }
		'Update' { return 'Update' }
		'UpdateAll' { return 'Update All' }
		default { return 'App Action' }
	}
}

function Script:Get-GuiAppExecutionSummarySuccessLabel
{
	param(
		[string]$Action
	)

	switch ([string]$Action)
	{
		'Install' { return 'Installed' }
		'Uninstall' { return 'Uninstalled' }
		'Update' { return 'Updated' }
		'UpdateAll' { return 'Updated' }
		default { return 'Succeeded' }
	}
}

function Script:Get-GuiAppExecutionSummaryCounts
{
	param(
		[AllowNull()]
		[object]$Result
	)

	$successfulApps = @((Get-GuiAppExecutionSummaryFieldValue -Object $Result -FieldName 'SuccessfulApps') | Where-Object { $_ })
	$failedApps = @((Get-GuiAppExecutionSummaryFieldValue -Object $Result -FieldName 'FailedApps') | Where-Object { $_ })
	$successCount = if (Test-GuiObjectField -Object $Result -FieldName 'SuccessCount') { [int]$Result.SuccessCount } else { $successfulApps.Count }
	$failureCount = if (Test-GuiObjectField -Object $Result -FieldName 'FailureCount') { [int]$Result.FailureCount } else { $failedApps.Count }
	$totalCount = if (Test-GuiObjectField -Object $Result -FieldName 'TotalCount') { [int]$Result.TotalCount } else { $successCount + $failureCount }
	$outcome = if (Test-GuiObjectField -Object $Result -FieldName 'Outcome') { [string]$Result.Outcome } else { $(if ($failureCount -gt 0) { 'Failed' } else { 'Success' }) }
	$message = if (Test-GuiObjectField -Object $Result -FieldName 'Message') { [string]$Result.Message } else { $null }

	return [pscustomobject]@{
		SuccessfulApps = @($successfulApps)
		FailedApps     = @($failedApps)
		SuccessCount   = $successCount
		FailureCount   = $failureCount
		TotalCount     = $totalCount
		Outcome        = $outcome
		Message        = $message
	}
}

function Script:Get-GuiAppExecutionSummaryEntryName
{
	param(
		[AllowNull()]
		[object]$Entry
	)

	foreach ($fieldName in @('Name', 'PackageId', 'WinGetId', 'ChocoId', 'SelectionKey'))
	{
		$value = [string](Get-GuiAppExecutionSummaryFieldValue -Object $Entry -FieldName $fieldName)
		if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
	}

	return 'Application'
}

function Script:Get-GuiAppExecutionSummaryEntryDetail
{
	param(
		[AllowNull()]
		[object]$Entry
	)

	$parts = [System.Collections.Generic.List[string]]::new()
	foreach ($fieldSpec in @(
		@{ Label = 'Source'; Field = 'SelectedSource' },
		@{ Label = 'Package'; Field = 'PackageId' },
		@{ Label = 'WinGet'; Field = 'WinGetId' },
		@{ Label = 'Chocolatey'; Field = 'ChocoId' },
		@{ Label = 'Route'; Field = 'Route' }
	))
	{
		$value = [string](Get-GuiAppExecutionSummaryFieldValue -Object $Entry -FieldName ([string]$fieldSpec.Field))
		if (-not [string]::IsNullOrWhiteSpace($value))
		{
			[void]$parts.Add(('{0}: {1}' -f [string]$fieldSpec.Label, $value))
		}
	}

	return ($parts -join ' | ')
}

function Script:New-GuiAppExecutionSummaryRow
{
	param(
		[AllowNull()]
		[object]$Entry,

		[string]$Action,

		[ValidateSet('Success', 'Failed', 'Not Run')]
		[string]$Status,

		[string]$OutcomeReason = $null,

		[string]$Detail = $null
	)

	$actionLabel = Get-GuiAppExecutionSummaryActionLabel -Action $Action
	$entryDetail = Get-GuiAppExecutionSummaryEntryDetail -Entry $Entry
	$detailText = if (-not [string]::IsNullOrWhiteSpace($Detail)) { $Detail } else { $entryDetail }
	$outcomeState = switch ($Status)
	{
		'Success' { Get-GuiAppExecutionSummarySuccessLabel -Action $Action; break }
		'Not Run' { 'Not run'; break }
		default { 'Failed and manual intervention required' }
	}

	return [pscustomobject]@{
		Name          = Get-GuiAppExecutionSummaryEntryName -Entry $Entry
		Status        = $Status
		Category      = 'Apps'
		Selection     = $actionLabel
		Type          = 'Application'
		TypeLabel     = 'Application'
		OutcomeState  = $outcomeState
		OutcomeReason = $OutcomeReason
		Detail        = $detailText
	}
}

function Script:ConvertTo-GuiAppExecutionSummaryResults
{
	param(
		[string]$Action,

		[AllowNull()]
		[object]$Result,

		[bool]$AbortedRun = $false
	)

	$counts = Get-GuiAppExecutionSummaryCounts -Result $Result
	$rows = [System.Collections.Generic.List[object]]::new()
	foreach ($appEntry in @($counts.SuccessfulApps))
	{
		[void]$rows.Add((New-GuiAppExecutionSummaryRow -Entry $appEntry -Action $Action -Status 'Success'))
	}
	foreach ($appEntry in @($counts.FailedApps))
	{
		$errorText = [string](Get-GuiAppExecutionSummaryFieldValue -Object $appEntry -FieldName 'Error')
		[void]$rows.Add((New-GuiAppExecutionSummaryRow -Entry $appEntry -Action $Action -Status 'Failed' -OutcomeReason $errorText))
	}

	if ($rows.Count -eq 0)
	{
		$status = if ($AbortedRun) { 'Not Run' } elseif ($counts.FailureCount -gt 0 -or [string]$counts.Outcome -eq 'Failed') { 'Failed' } else { 'Success' }
		[void]$rows.Add((New-GuiAppExecutionSummaryRow -Entry $Result -Action $Action -Status $status -OutcomeReason $counts.Message -Detail $counts.Message))
	}

	return @($rows)
}

function Script:Get-GuiAppExecutionSummaryTitle
{
	param(
		[string]$Action,

		[object]$Counts,

		[bool]$AbortedRun = $false
	)

	$actionLabel = Get-GuiAppExecutionSummaryActionLabel -Action $Action
	if ($AbortedRun) { return ('App {0} Aborted' -f $actionLabel) }
	if ($Counts.FailureCount -gt 0 -and $Counts.SuccessCount -gt 0) { return ('App {0} Partially Completed' -f $actionLabel) }
	if ($Counts.FailureCount -gt 0) { return ('App {0} Failed' -f $actionLabel) }
	return ('App {0} Complete' -f $actionLabel)
}

function Script:Get-GuiAppExecutionSummaryText
{
	param(
		[string]$Action,

		[object]$Counts,

		[bool]$AbortedRun = $false
	)

	$message = if (-not [string]::IsNullOrWhiteSpace([string]$Counts.Message)) { [string]$Counts.Message } else { $null }
	$countText = 'Successful: {0}. Failed: {1}. Total: {2}.' -f [int]$Counts.SuccessCount, [int]$Counts.FailureCount, [int]$Counts.TotalCount
	if ($AbortedRun)
	{
		$actionLabel = (Get-GuiAppExecutionSummaryActionLabel -Action $Action).ToLowerInvariant()
		$abortText = 'The app {0} run was aborted.' -f $actionLabel
		return $(if ([string]::IsNullOrWhiteSpace($message)) { '{0} {1}' -f $abortText, $countText } else { '{0} {1} {2}' -f $abortText, $message, $countText })
	}

	return $(if ([string]::IsNullOrWhiteSpace($message)) { $countText } else { '{0} {1}' -f $message, $countText })
}

function Script:Get-GuiAppExecutionSummaryCards
{
	param(
		[string]$Action,

		[object]$Counts
	)

	$successLabel = Get-GuiAppExecutionSummarySuccessLabel -Action $Action
	return @(
		[pscustomobject]@{
			Label = $successLabel
			Value = [int]$Counts.SuccessCount
			Detail = 'Completed successfully'
			Tone = $(if ([int]$Counts.SuccessCount -gt 0) { 'Success' } else { 'Muted' })
		},
		[pscustomobject]@{
			Label = 'Failed'
			Value = [int]$Counts.FailureCount
			Detail = 'Needs attention'
			Tone = $(if ([int]$Counts.FailureCount -gt 0) { 'Danger' } else { 'Muted' })
		},
		[pscustomobject]@{
			Label = 'Total'
			Value = [int]$Counts.TotalCount
			Detail = Get-GuiAppExecutionSummaryActionLabel -Action $Action
			Tone = 'Muted'
		}
	)
}

function Script:Show-GuiAppExecutionSummaryDialog
{
	param(
		[string]$Action,

		[AllowNull()]
		[object]$Result,

		[bool]$AbortedRun = $false,

		[string]$LogPath = $null
	)

	$counts = Get-GuiAppExecutionSummaryCounts -Result $Result
	$summaryResults = @(ConvertTo-GuiAppExecutionSummaryResults -Action $Action -Result $Result -AbortedRun:$AbortedRun)
	$summaryTitle = Get-GuiAppExecutionSummaryTitle -Action $Action -Counts $counts -AbortedRun:$AbortedRun
	$summaryText = Get-GuiAppExecutionSummaryText -Action $Action -Counts $counts -AbortedRun:$AbortedRun
	$summaryCards = @(Get-GuiAppExecutionSummaryCards -Action $Action -Counts $counts)
	$displayLogPath = if (($AbortedRun -or [int]$counts.FailureCount -gt 0) -and -not [string]::IsNullOrWhiteSpace([string]$LogPath)) { [string]$LogPath } else { $null }
	$summaryButtons = @()
	if (-not [string]::IsNullOrWhiteSpace($displayLogPath))
	{
		$summaryButtons += 'Open Detailed Log'
	}
	$summaryButtons += @('Close', 'Exit')

	return (Show-ExecutionSummaryDialog -Title $summaryTitle -SummaryText $summaryText -Results $summaryResults -LogPath $displayLogPath -SummaryCards $summaryCards -Buttons $summaryButtons)
}

try
		{
			if ($wasAppsModeActive)
			{
				Set-GuiAppsMode -Enable:$false
			}

			if ($Script:GuiState)
			{
				& $Script:GuiState.Set 'RunInProgress' $true
			}
			else
			{
				$Script:RunInProgress = $true
			}

			Enter-ExecutionView -Title $executionTitle -ShowAbortButton:$true
			$Script:ExecutionMode = 'Apps'
			if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
			{
				if ([bool]$Script:RunState['AppProgressIndeterminate'])
				{
					Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Indeterminate -CurrentAction $initialActionText
				}
				else
				{
					Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed 0 -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $initialActionText
				}
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$initialActionText))
			{
				LogInfo $initialActionText
			}
			$Script:AppExecutionLiveLogBlocks = @{}
			$Script:AppendLogFn = { param($Text, $Level = 'INFO', [switch]$PassThru) Add-GuiExecutionRunLogLine -Text $Text -Level $Level -PassThru:$PassThru }

			$bgLocDir      = $LocalizationDirectory
			$bgUICulture   = $UICulture
			$bgLogFilePath = $LogFilePath

			$appExecutionSource = if ([string]::IsNullOrWhiteSpace([string]$PreferredSource)) { 'auto' } else { [string]$PreferredSource }
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogAppExecutionStarting' -Fallback 'Starting app execution (action: {0}, selected: {1}, source: {2})' -FormatArgs @($Action, $(if ($selectedCount -gt 0) { $selectedCount } else { 1 }), $appExecutionSource))
			LogDebug -Message ("Execution startup: dispatching background worker. mode=Apps; action={0}; selected={1}; loader={2}; log={3}" -f $Action, $(if ($selectedCount -gt 0) { $selectedCount } else { 1 }), $LoaderPath, $bgLogFilePath) -Always
			$workerStartPerf = Start-GuiPerfScope -Name 'Execution.WorkerStart' -Note ("mode=Apps; action={0}; selected={1}" -f $Action, $(if ($selectedCount -gt 0) { $selectedCount } else { 1 }))
			try
			{
				$Script:ExecutionWorker = GUIExecution\Start-GuiAppExecutionWorker `
					-Action $Action `
					-LoaderPath $LoaderPath `
					-LocalizationDirectory $bgLocDir `
					-UICulture $bgUICulture `
					-LogFilePath $bgLogFilePath `
					-LogMode $LogMode `
					-RunState $Script:RunState `
					-WinGetId $resolvedWinGetId `
					-ChocoId $resolvedChocoId `
					-DisplayName $resolvedDisplayName `
					-Application $Application `
					-SelectedApps @($selectedApps) `
					-PreferredSource $PreferredSource `
					-PackageManagerAvailabilityState $PackageManagerAvailabilityState
			}
			finally
			{
				Stop-GuiPerfScope -Scope $workerStartPerf
			}
			if (-not $Script:ExecutionWorker -or -not $Script:ExecutionWorker.AsyncResult)
			{
				throw 'App execution startup failed: background worker did not return an async handle.'
			}
			$Script:BgPS = $Script:ExecutionWorker.PowerShell
			$Script:BgAsync = $Script:ExecutionWorker.AsyncResult
			$Script:ExecutionRunspace = $Script:ExecutionWorker.Runspace
			$Script:ExecutionRunPowerShell = $Script:ExecutionWorker.PowerShell
			LogDebug -Message ("Execution startup: background worker started. asyncCompleted={0}; runspaceState={1}" -f [bool]$Script:BgAsync.IsCompleted, $(if ($Script:ExecutionRunspace) { [string]$Script:ExecutionRunspace.RunspaceStateInfo.State } else { '<null>' })) -Always

			$Script:AppDrainQueue = {
				param([switch]$Final)

				$qEntry = $null
				while ($Script:RunState['LogQueue'].TryDequeue([ref]$qEntry))
				{
					try
					{
						Update-ExecutionActivityHeartbeat -RunState $Script:RunState
						switch ($qEntry.Kind)
						{
							'_AppStarted'
							{
								$Script:RunState['AppUseStructuredProgress'] = $true
								$appName = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Name')) { [string]$qEntry.Name } else { [string]$Script:RunState['CurrentAction'] }
								$stepIndex = if ((Test-GuiObjectField -Object $qEntry -FieldName 'StepIndex')) { [int]$qEntry.StepIndex } else { ([int]$Script:RunState['AppCompletedCount'] + 1) }
								$stepTotal = if ((Test-GuiObjectField -Object $qEntry -FieldName 'StepTotal')) { [int]$qEntry.StepTotal } else { [int]$Script:RunState['AppProgressTotal'] }
								$stepTotal = [Math]::Max($stepTotal, 1)
								$appProgressMessage = Write-GuiAppExecutionProgressLog -Action ([string]$qEntry.Action) -Name $appName -Started
								$Script:RunState['CurrentAction'] = $appProgressMessage
								$Script:RunState['AppCurrentProgressCount'] = [Math]::Min([Math]::Max($stepIndex, 1), $stepTotal)
								$Script:ExecutionLastConsoleAction = $null
								$appLiveLogMessage = Get-GuiAppExecutionLiveLogMessage -StepIndex $stepIndex -StepTotal $stepTotal -Message $appProgressMessage
								if (-not [string]::IsNullOrWhiteSpace($appLiveLogMessage))
								{
									$appLiveLogKey = Get-GuiAppExecutionLiveLogKey -StepIndex $stepIndex -StepTotal $stepTotal
									$Script:AppExecutionLiveLogBlocks[$appLiveLogKey] = & $Script:AppendLogFn $appLiveLogMessage 'INFO' -PassThru
								}
								if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
								{
									$appActiveProgressText = $appProgressMessage
									Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCurrentProgressCount']) -Total $stepTotal -CurrentAction $appActiveProgressText
								}
							}
							'_AppCompleted'
							{
								$Script:RunState['AppUseStructuredProgress'] = $true
								$appStatus = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Status')) { [string]$qEntry.Status } else { 'Success' }
								$appMessage = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Message') -and -not [string]::IsNullOrWhiteSpace([string]$qEntry.Message)) { [string]$qEntry.Message } else { [string]$qEntry.Name }
								$appLevel = Get-GuiAppExecutionStatusLevel -Status $appStatus
								$displayName = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Name') -and -not [string]::IsNullOrWhiteSpace([string]$qEntry.Name)) { [string]$qEntry.Name } else { [string]$Script:RunState['CurrentAction'] }
								$appProgressMessage = Write-GuiAppExecutionProgressLog -Action ([string]$qEntry.Action) -Name $displayName -Status $appStatus
								$stepTotal = if ((Test-GuiObjectField -Object $qEntry -FieldName 'StepTotal')) { [int]$qEntry.StepTotal } else { [int]$Script:RunState['AppProgressTotal'] }
								$completedCount = if ((Test-GuiObjectField -Object $qEntry -FieldName 'StepIndex')) { [int]$qEntry.StepIndex } else { ([int]$Script:RunState['AppCompletedCount'] + 1) }
								$appLiveLogMessage = Get-GuiAppExecutionLiveLogMessage -StepIndex $completedCount -StepTotal $stepTotal -Message $appProgressMessage
								if (-not [string]::IsNullOrWhiteSpace($appLiveLogMessage))
								{
									$appLiveLogKey = Get-GuiAppExecutionLiveLogKey -StepIndex $completedCount -StepTotal $stepTotal
									if ($Script:AppExecutionLiveLogBlocks -and $Script:AppExecutionLiveLogBlocks.ContainsKey($appLiveLogKey) -and $Script:AppExecutionLiveLogBlocks[$appLiveLogKey])
									{
										Set-GuiExecutionRunLogLine -Block $Script:AppExecutionLiveLogBlocks[$appLiveLogKey] -Text $appLiveLogMessage -Level $appLevel
										$null = $Script:AppExecutionLiveLogBlocks.Remove($appLiveLogKey)
									}
									else
									{
										& $Script:AppendLogFn $appLiveLogMessage $appLevel
									}
								}

								$Script:RunState['AppCompletedCount'] = [Math]::Min($completedCount, [int]$Script:RunState['AppProgressTotal'])
								$Script:RunState['AppCurrentProgressCount'] = [int]$Script:RunState['AppCompletedCount']
								if (-not [string]::IsNullOrWhiteSpace($appStatus))
								{
									Set-GuiAppProgressOutcome -RunState $Script:RunState -Status $appStatus
								}
								if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
								{
									Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $appProgressMessage
								}
								$Script:ExecutionLastConsoleAction = $null
							}
							'Log'
							{
								# Raw logger entries belong in the file log. The live app console is driven
								# by structured app events so it matches tweak-run behavior.
								$null = $qEntry
							}
							'ConsoleAction'
							{
								$currentAction = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Action')) { [string]$qEntry.Action } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($currentAction))
								{
									$Script:ExecutionLastConsoleAction = $currentAction
									if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
									{
										if ([bool]$Script:RunState['AppUseStructuredProgress'])
										{
											Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $currentAction
										}
										elseif ([bool]$Script:RunState['AppProgressIndeterminate'] -and [int]$Script:RunState['AppCompletedCount'] -eq 0)
										{
											Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Indeterminate -CurrentAction $currentAction
										}
										else
										{
											Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $currentAction
										}
									}
								}
							}
							'ConsoleStatus'
							{
								$status = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Status')) { [string]$qEntry.Status } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($status))
								{
									Set-GuiAppProgressOutcome -RunState $Script:RunState -Status $status
								}
								if (-not [bool]$Script:RunState['AppUseStructuredProgress'])
								{
									$Script:RunState['AppCompletedCount'] = [Math]::Min(([int]$Script:RunState['AppCompletedCount'] + 1), [int]$Script:RunState['AppProgressTotal'])
								}
								if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
								{
									$currentAction = if (-not [string]::IsNullOrWhiteSpace([string]$Script:ExecutionLastConsoleAction)) { [string]$Script:ExecutionLastConsoleAction } else { [string]$Script:RunState['CurrentAction'] }
									Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $currentAction
								}
								$Script:ExecutionLastConsoleAction = $null
							}
							'ConsoleComplete'
							{
								$status = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Status')) { [string]$qEntry.Status } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($status))
								{
									Set-GuiAppProgressOutcome -RunState $Script:RunState -Status $status
								}
								if (-not [bool]$Script:RunState['AppUseStructuredProgress'])
								{
									$Script:RunState['AppCompletedCount'] = [Math]::Min(([int]$Script:RunState['AppCompletedCount'] + 1), [int]$Script:RunState['AppProgressTotal'])
								}
								if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
								{
									$currentAction = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Action') -and -not [string]::IsNullOrWhiteSpace([string]$qEntry.Action)) { [string]$qEntry.Action } else { [string]$Script:RunState['CurrentAction'] }
									Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $currentAction
								}
								$Script:ExecutionLastConsoleAction = $null
							}
							'_RunError'
							{
								$fatalMessage = if ([string]::IsNullOrWhiteSpace([string]$qEntry.Error)) { 'Unexpected fatal app run error.' } else { [string]$qEntry.Error }
								$Script:RunState['AppOutcome'] = 'Failed'
								& $Script:AppendLogFn ("Fatal app error: {0}" -f $fatalMessage) 'ERROR'
								try
								{
									LogError ("Fatal app error: {0}" -f $fatalMessage)
								}
								catch
								{
									if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
									{
										Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionOrchestration.RunLoop.FatalAppError.LogError'
									}
								}
								$diagnosticText = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Diagnostic')) { [string]$qEntry.Diagnostic } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($diagnosticText))
								{
									foreach ($diagnosticLine in @($diagnosticText -split "(`r`n|`n|`r)"))
									{
										if (-not [string]::IsNullOrWhiteSpace([string]$diagnosticLine))
										{
											& $Script:AppendLogFn $diagnosticLine 'ERROR'
											try
											{
												LogError $diagnosticLine
											}
											catch
											{
												if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
												{
													Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionOrchestration.RunLoop.FatalAppDiagnostic.LogError'
												}
											}
										}
									}
								}
							}
							'_RunNotice'
							{
								$noticeMessage = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Message')) { [string]$qEntry.Message } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($noticeMessage))
								{
									$level = if ((Test-GuiObjectField -Object $qEntry -FieldName 'Level') -and [string]$qEntry.Level -in @('INFO', 'WARNING', 'ERROR', 'DEBUG')) { [string]$qEntry.Level } else { 'INFO' }
									$noticeDiagnostic = ((Test-GuiObjectField -Object $qEntry -FieldName 'Diagnostic') -and [bool]$qEntry.Diagnostic) -or $level -eq 'DEBUG'
									$noticeProgressOnly = ((Test-GuiObjectField -Object $qEntry -FieldName 'ProgressOnly') -and [bool]$qEntry.ProgressOnly)
									if ($noticeDiagnostic)
									{
										if (-not $noticeProgressOnly)
										{
											LogDebug -Message $noticeMessage -Always
										}
									}
									else
									{
										switch ($level)
										{
											'ERROR' { LogError $noticeMessage }
											'WARNING' { LogWarning $noticeMessage }
											default { LogInfo $noticeMessage }
										}
									}
									if ((Test-GuiObjectField -Object $qEntry -FieldName 'Progress') -and [bool]$qEntry.Progress -and ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText))
									{
										Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $noticeMessage
									}
								}
							}
						}
					}
					catch
					{
						$appQueueEntryKind = if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Kind')) { [string]$qEntry.Kind } else { '<unknown>' }
						$appQueueEntryError = if ($_.Exception) { [string]$_.Exception.Message } else { [string]$_ }
						LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAppTimerQueueEntryFailed' -Fallback '[AppTimer] Queue entry failed [{0}]: {1}' -FormatArgs @($appQueueEntryKind, $appQueueEntryError)))
					}
					finally
					{
						$qEntry = $null
					}
				}
			}

			$Script:ExecutionPumpTickFn = {
				try
				{
					if (-not (& $Script:TestGuiRunInProgressScript) -or -not $Script:RunState) { return }

					if ($Script:AbortRequested -and -not $Script:RunState['AbortRequested'])
					{
						$Script:RunState['AbortRequested'] = $true
						$Script:RunState['AbortRequestedAt'] = Get-Date
					}

					if (
						$Script:RunState['AbortRequested'] -and
						-not $Script:RunState['Done'] -and
						-not $Script:RunState['ForceStopIssued']
					)
					{
						$Script:RunState['ForceStopIssued'] = $true
						$Script:RunState['AbortedRun'] = $true
						$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
							Kind = '_RunNotice'
							Level = 'WARNING'
							Message = 'Abort requested - stopping the current app operation now.'
						})
						$bgPsToStop = $Script:BgPS
						if ($bgPsToStop)
						{
							GUIExecution\Request-GuiExecutionWorkerStop -PowerShellInstance $bgPsToStop
						}
					}

					& $Script:AppDrainQueue
					Invoke-ExecutionIdleWatchdogPrompt -RunState $Script:RunState

					if ($Script:BgAsync -and -not $Script:BgAsync.IsCompleted -and -not $Script:RunState['Done']) { return }

					if ($Script:ExecutionRunTimer)
					{
						try { $Script:ExecutionRunTimer.Stop() } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:859' -Severity Debug }
						 $null = $_ }
					}

					& $Script:AppDrainQueue

					GUIExecution\Complete-GuiExecutionWorker -Worker $Script:ExecutionWorker
					if ($Script:RunState['AppResult'] -and (Test-GuiObjectField -Object $Script:RunState['AppResult'] -FieldName 'Outcome') -and -not [string]::IsNullOrWhiteSpace([string]$Script:RunState['AppResult'].Outcome))
					{
						$Script:RunState['AppOutcome'] = [string]$Script:RunState['AppResult'].Outcome
					}
					$Script:ExecutionWorker = $null
					$Script:ExecutionRunspace = $null
					$Script:ExecutionRunPowerShell = $null
					$Script:ExecutionRunTimer = $null
					$Script:ExecutionPumpTickFn = $null
					$Script:BgPS = $null
					$Script:BgAsync = $null

					$appOutcome = if (-not [string]::IsNullOrWhiteSpace([string]$Script:RunState['AppOutcome'])) { [string]$Script:RunState['AppOutcome'] } else { 'Success' }
					$appCompletedCount = [int]$Script:RunState['AppCompletedCount']
					$appAbortedRun = [bool]$Script:RunState['AbortedRun']
					LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionRunDone' -Fallback '[Timer] Run done. mode={0}, aborted={1}, disposition={2}, completed={3}' -FormatArgs @($Script:ExecutionMode, $appAbortedRun, '', $appCompletedCount))
					Write-GuiAppExecutionSummaryToLog -Action ([string]$Script:RunState['Action']) -Result $Script:RunState['AppResult'] -AbortedRun:$appAbortedRun
					$finalLabel = if ([bool]$Script:RunState['AbortedRun'])
					{
						Get-UxLocalizedString -Key 'GuiProgressAborted' -Fallback 'Aborted'
					}
					else
					{
						switch ($appOutcome.ToLowerInvariant())
						{
							'partial' { Get-UxLocalizedString -Key 'GuiProgressPartiallyComplete' -Fallback 'Partially Complete' }
							'warning' { Get-UxLocalizedString -Key 'GuiProgressPartiallyComplete' -Fallback 'Partially Complete' }
							'failed'  { Get-UxLocalizedString -Key 'GuiProgressFailed' -Fallback 'Failed' }
							default   { Get-UxLocalizedString -Key 'GuiProgressDone' -Fallback 'Done' }
						}
					}
					if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
					{
						Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed ([int]$Script:RunState['AppCompletedCount']) -Total ([int]$Script:RunState['AppProgressTotal']) -CurrentAction $finalLabel
					}

					Clear-UILogHandler
					Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue

					if ($Script:GuiState)
					{
						& $Script:GuiState.Set 'RunInProgress' $false
					}
					else
					{
						$Script:RunInProgress = $false
					}

					$Script:AppsOperationInProgress = $false
					$Script:ExecutionMode = $null

					$runAction = [string]$Script:RunState['Action']
					$runApplication = $Script:RunState['Application']
					$runSelectedApps = @($Script:RunState['SelectedApps'])
					$runPreferredSource = [string]$Script:RunState['PreferredSource']
					$runWasAppsModeActive = [bool]$Script:RunState['WasAppsModeActive']
					$runAppResult = $Script:RunState['AppResult']
					$appSummaryChoice = 'Close'
					try
					{
						$appSummaryChoice = Show-GuiAppExecutionSummaryDialog -Action $runAction -Result $runAppResult -AbortedRun:$appAbortedRun -LogPath $Global:LogFilePath
					}
					catch
					{
						LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAppSummaryDialogFailed' -Fallback 'Failed to show app execution summary'))
					}

					Exit-ExecutionView

					if ((Get-Command -Name 'Sync-AppActionStatesFromExecutionResult' -CommandType Function -ErrorAction SilentlyContinue) -and $runAction -in @('Install', 'Uninstall', 'Update'))
					{
						try
						{
							Sync-AppActionStatesFromExecutionResult -Action $runAction -Application $runApplication -SelectedApps @($runSelectedApps) -Result $runAppResult -PreferredSource $runPreferredSource
						}
						catch
						{
							LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAppStateSyncFailed' -Fallback 'Failed to sync app action state after execution'))
						}
					}

					if ($runWasAppsModeActive)
					{
						if ($runAction -in @('Install', 'Uninstall', 'Update', 'UpdateAll'))
						{
							Start-AppsCacheRefresh
						}
						else
						{
							$Script:AppsViewDirty = $true
						}

						Set-GuiAppsMode -Enable:$true
					}

					$Script:RunState = $null
					if ($appSummaryChoice -eq 'Open Detailed Log' -and -not [string]::IsNullOrWhiteSpace([string]$Global:LogFilePath))
					{
						Show-LogDialog -LogPath $Global:LogFilePath
					}
					elseif ($appSummaryChoice -eq 'Exit')
					{
						Close-GuiMainWindow -Reason 'App execution summary exit requested.'
					}
				}
				catch
				{
					$appExecutionUpdateError = if ($_.Exception) { [string]$_.Exception.Message } else { [string]$_ }
					LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAppTimerUpdateFailed' -Fallback '[AppTimer] Execution UI update failed: {0}' -FormatArgs @($appExecutionUpdateError)))
					try { Clear-UILogHandler } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:974' -Severity Debug }
					 $null = $_ }
					try { Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:975' -Severity Debug }
					 $null = $_ }
					try { Exit-ExecutionView } catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:976' -Severity Debug }
					 $null = $_ }
					try
					{
						$runCatchAction = if ($Script:RunState) { [string]$Script:RunState['Action'] } else { $null }
						$runCatchWasAppsModeActive = if ($Script:RunState) { [bool]$Script:RunState['WasAppsModeActive'] } else { $false }
						if ($runCatchWasAppsModeActive)
						{
							if ($runCatchAction -in @('Install', 'Uninstall', 'Update', 'UpdateAll'))
							{
								Start-AppsCacheRefresh
							}
							else
							{
								$Script:AppsViewDirty = $true
							}

							Set-GuiAppsMode -Enable:$true
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:995' -Severity Debug }

						$null = $_
					}
					$Script:AppsOperationInProgress = $false
					if ($Script:GuiState)
					{
						& $Script:GuiState.Set 'RunInProgress' $false
					}
					else
					{
						$Script:RunInProgress = $false
					}
					$Script:ExecutionWorker = $null
					$Script:ExecutionRunspace = $null
					$Script:ExecutionRunPowerShell = $null
					$Script:ExecutionRunTimer = $null
					$Script:ExecutionPumpTickFn = $null
					$Script:BgPS = $null
					$Script:BgAsync = $null
					$Script:ExecutionMode = $null
					$Script:RunState = $null
				}
			}

			$executionPumpTickFn = $Script:ExecutionPumpTickFn
			$runTimer = New-Object System.Windows.Threading.DispatcherTimer
			$runTimer.Interval = [TimeSpan]::FromMilliseconds(100)
			$runTimer.Add_Tick({
				& $executionPumpTickFn
			}.GetNewClosure())
			$Script:ExecutionRunTimer = $runTimer
			LogDebug -Message 'Execution startup: starting dispatcher pump.' -Always
			$timerStartPerf = Start-GuiPerfScope -Name 'Execution.TimerStart' -Note ("mode=Apps; action={0}; selected={1}" -f $Action, $(if ($selectedCount -gt 0) { $selectedCount } else { 1 }))
			$runTimer.Start()
			Stop-GuiPerfScope -Scope $timerStartPerf -ExtraNote 'started'
			LogDebug -Message 'Execution startup: dispatcher pump started; invoking first tick.' -Always
			& $executionPumpTickFn
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:1034' -Severity Debug }

			try { Clear-UILogHandler } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:1036' -Severity Debug }
			 $null = $_ }
			try { Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:1037' -Severity Debug }
			 $null = $_ }
			try { Exit-ExecutionView } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:1038' -Severity Debug }
			 $null = $_ }
			try
			{
				if ($wasAppsModeActive)
				{
					Set-GuiAppsMode -Enable:$true
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ExecutionOrchestration\ExecutionRunOrchestration\Start-GuiAppExecutionRun\Start-GuiAppExecutionRun.ps1:1046' -Severity Debug }

				$null = $_
			}
			$Script:AppsOperationInProgress = $false
			if ($Script:GuiState)
			{
				& $Script:GuiState.Set 'RunInProgress' $false
			}
			else
			{
				$Script:RunInProgress = $false
			}
			$Script:ExecutionWorker = $null
			$Script:ExecutionRunspace = $null
			$Script:ExecutionRunPowerShell = $null
			$Script:ExecutionRunTimer = $null
			$Script:ExecutionPumpTickFn = $null
			$Script:BgPS = $null
			$Script:BgAsync = $null
			$Script:ExecutionMode = $null
			$Script:RunState = $null
			$null = & $Script:ShowGuiRuntimeFailureScript -Context 'Start-GuiAppExecutionRun' -Exception $_.Exception -ShowDialog
		}
