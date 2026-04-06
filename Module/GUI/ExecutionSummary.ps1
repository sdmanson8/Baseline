# Execution summary classification, insights, retry policy, and dialog cards

	function New-ExecutionSummaryRecord
	{
		param (
			[Parameter(Mandatory = $true)][int]$Order,
			[Parameter(Mandatory = $true)][object]$Tweak
		)

		return [PSCustomObject]@{
			Key       = [string]$Tweak.Key
			Order     = $Order
			Name      = [string]$Tweak.Name
			Function  = [string]$Tweak.Function
			Category  = [string]$Tweak.Category
			Risk      = [string]$Tweak.Risk
			Type      = [string]$Tweak.Type
			TypeKind  = [string]$Tweak.TypeKind
			TypeLabel = [string]$Tweak.TypeLabel
			TypeBadgeLabel = if ((Test-GuiObjectField -Object $Tweak -FieldName 'TypeBadgeLabel')) { [string]$Tweak.TypeBadgeLabel } else { [string]$Tweak.TypeLabel }
			TypeTone  = [string]$Tweak.TypeTone
			Selection = [string]$Tweak.Selection
			ToggleParam = if ((Test-GuiObjectField -Object $Tweak -FieldName 'ToggleParam')) { [string]$Tweak.ToggleParam } else { $null }
			Restorable = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Restorable')) { $Tweak.Restorable } else { $null }
			RequiresRestart = if ((Test-GuiObjectField -Object $Tweak -FieldName 'RequiresRestart')) { [bool]$Tweak.RequiresRestart } else { $false }
			CurrentState = [string]$Tweak.CurrentState
			CurrentStateTone = [string]$Tweak.CurrentStateTone
			StateDetail = [string]$Tweak.StateDetail
			MatchesDesired = if ((Test-GuiObjectField -Object $Tweak -FieldName 'MatchesDesired')) { [bool]$Tweak.MatchesDesired } else { $false }
			ScenarioTags = if ((Test-GuiObjectField -Object $Tweak -FieldName 'ScenarioTags')) { @($Tweak.ScenarioTags) } else { @() }
			ReasonIncluded = if ((Test-GuiObjectField -Object $Tweak -FieldName 'ReasonIncluded')) { [string]$Tweak.ReasonIncluded } else { $null }
			BlastRadius = [string]$Tweak.BlastRadius
			IsRemoval = if ((Test-GuiObjectField -Object $Tweak -FieldName 'IsRemoval')) { [bool]$Tweak.IsRemoval } else { $false }
			RecoveryLevel = if ((Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel')) { [string]$Tweak.RecoveryLevel } else { $null }
			GamingPreviewGroup = if ((Test-GuiObjectField -Object $Tweak -FieldName 'GamingPreviewGroup')) { [string]$Tweak.GamingPreviewGroup } else { $null }
			TroubleshootingOnly = if ((Test-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly')) { [bool]$Tweak.TroubleshootingOnly } else { $false }
			FromGameMode = if ((Test-GuiObjectField -Object $Tweak -FieldName 'FromGameMode')) { [bool]$Tweak.FromGameMode } else { $false }
			GameModeProfile = if ((Test-GuiObjectField -Object $Tweak -FieldName 'GameModeProfile')) { [string]$Tweak.GameModeProfile } else { $null }
			GameModeOperation = if ((Test-GuiObjectField -Object $Tweak -FieldName 'GameModeOperation')) { [string]$Tweak.GameModeOperation } else { 'Apply' }
			Impact = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Impact')) { [string]$Tweak.Impact } else { $null }
			PresetTier = if ((Test-GuiObjectField -Object $Tweak -FieldName 'PresetTier')) { [string]$Tweak.PresetTier } else { $null }
			OutcomeState = $null
			OutcomeReason = $null
			FailureCategory = $null
			FailureCode = $null
			IsRecoverable = $false
			RetryAvailability = $null
			RetryReason = $null
			RecoveryHint = $null
			Status    = 'Pending'
			Detail    = $null
		}
	}

	function Initialize-ExecutionSummary
	{
		param ([object[]]$SelectedTweaks)

		$Script:ExecutionSummaryRecords = New-Object System.Collections.ArrayList
		$Script:ExecutionSummaryLookup = @{}
		$Script:ExecutionCurrentSummaryKey = $null

		$order = 0
		foreach ($tweak in @($SelectedTweaks))
		{
			$order++
			$record = New-ExecutionSummaryRecord -Order $order -Tweak $tweak
			[void]$Script:ExecutionSummaryRecords.Add($record)
			$Script:ExecutionSummaryLookup[[string]$tweak.Key] = $record
		}
	}

	function Get-ExecutionSummaryClassification
	{
		param (
			[string]$Status,
			[string]$Detail,
			[string]$RecoveryLevel = $null,
			$Restorable = $null,
			[string]$TypeKind = $null,
			[bool]$IsRemoval = $false,
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode = 'Run'
		)

		$statusText = if ([string]::IsNullOrWhiteSpace($Status)) { 'Pending' } else { [string]$Status.Trim() }
		$detailText = if ($null -eq $Detail) { '' } else { [string]$Detail }
		$combinedText = ("{0} {1}" -f $statusText, $detailText).Trim()
		$recoveryText = if ([string]::IsNullOrWhiteSpace($RecoveryLevel)) { '' } else { [string]$RecoveryLevel.Trim() }

		$classification = [ordered]@{
			OutcomeState = $statusText
			OutcomeReason = $null
			FailureCategory = $null
			FailureCode = $null
			IsRecoverable = $false
			RetryAvailability = $null
			RetryReason = $null
			RecoveryHint = $null
		}

		# Classification switch: ordered from most-specific to least-specific.
		# The outer switch matches $statusText exactly (anchored regexes).
		# Inside the 'Failed' branch, $combinedText is tested against an
		# ordered if/elseif chain - first match wins. The chain is ordered
		# by specificity: access-denied > reboot > dependency > unsupported >
		# blocked-state > network > partial > manual > general (catch-all).
		# Adding new failure patterns: insert BEFORE the general_failure else
		# branch and add corresponding unit tests in ExecutionSummary.Tests.ps1.
		switch -Regex ($statusText)
		{
			'^(Success)$'
			{
				$classification.OutcomeReason = if ($Mode -eq 'Defaults') {
					'Restored to Windows default.'
				} else {
					'Baseline applied the requested change successfully.'
				}
				if ($recoveryText -eq 'Direct')
				{
					$classification.OutcomeState = 'Success'
					$classification.IsRecoverable = $true
				}
				return [pscustomobject]$classification
			}
			'^(Restart pending)$'
			{
				$classification.OutcomeState = 'Restart pending'
				$classification.OutcomeReason = if ($Mode -eq 'Defaults') {
					'Restored to Windows default, but a restart is required before the change is fully finished.'
				} else {
					'Baseline applied this change, but a restart is required before it is fully finished.'
				}
				$classification.FailureCategory = 'Restart required'
				$classification.FailureCode = 'restart_required'
				$classification.IsRecoverable = $true
				$classification.RecoveryHint = 'Restart Windows, then retry if the tweak still needs to settle.'
				return [pscustomobject]$classification
			}
			'^(Not Run)$'
			{
				$classification.OutcomeState = 'Not run'
				$classification.OutcomeReason = 'This item never started because the run stopped before it could execute.'
				$classification.FailureCategory = 'Not run'
				$classification.FailureCode = 'not_run'
				$classification.RecoveryHint = 'This tweak did not execute because the run ended early.'
				return [pscustomobject]$classification
			}
			'^(Not applicable)$'
			{
				$classification.OutcomeState = 'Not applicable on this system'
				$classification.OutcomeReason = 'This change does not apply to this PC or this version of Windows.'
				$classification.FailureCategory = 'Not applicable'
				$classification.FailureCode = 'not_applicable'
				$classification.RecoveryHint = 'No action is needed. This item does not apply on the current system.'
				return [pscustomobject]$classification
			}
			'^(Skipped)$'
			{
				if ($combinedText -match '(?i)\balready (applied|in desired state|matches desired state|at default|at windows default)\b')
				{
					if ($Mode -eq 'Defaults')
					{
						$classification.OutcomeState = 'Already at Windows default'
						$classification.OutcomeReason = 'This PC already matches the Windows default for this setting.'
						$classification.FailureCategory = 'Already at Windows default'
						$classification.FailureCode = 'already_at_default'
						$classification.RecoveryHint = 'No action is needed.'
					}
					else
					{
						$classification.OutcomeState = 'Already in desired state'
						$classification.OutcomeReason = 'Nothing needed to change because this PC already matched what you asked for.'
						$classification.FailureCategory = 'Already in desired state'
						$classification.FailureCode = 'already_in_desired_state'
						$classification.RecoveryHint = 'No action is needed.'
					}
				}
				elseif ($combinedText -match '(?i)\b(not applicable|not supported|unsupported|unsupported build|windows server)\b')
				{
					$classification.OutcomeState = 'Not applicable on this system'
					$classification.OutcomeReason = if ($Mode -eq 'Defaults') {
						'Not applicable on this PC or this version of Windows.'
					} else {
						'Baseline skipped this item because it does not apply to this Windows build, edition, or device.'
					}
					$classification.FailureCategory = 'Unsupported environment'
					$classification.FailureCode = 'unsupported_environment'
					$classification.RecoveryHint = 'No action is needed. This item does not apply on the current system.'
				}
				else
				{
					if ($Mode -eq 'Defaults')
					{
						$classification.OutcomeState = 'Not supported by in-app restore'
						$classification.OutcomeReason = 'This item is not supported by in-app restore.'
						$classification.FailureCategory = 'Not supported by in-app restore'
						$classification.FailureCode = 'not_supported_restore'
						$classification.RecoveryHint = 'This change is permanent or not directly reversible in Baseline.'
					}
					else
					{
						$classification.OutcomeState = 'Skipped by preset or selection'
						$classification.OutcomeReason = 'Baseline skipped this item because it was not included in the current preset, filter, or manual selection.'
						$classification.FailureCategory = 'Skipped by preset policy'
						$classification.FailureCode = 'skipped_by_policy'
						$classification.RecoveryHint = 'This item was intentionally left out by the active preset, filter, or selection. Run it directly if you want to include it next time.'
					}
				}
				return [pscustomobject]$classification
			}
			'^(Failed)$'
			{
				$classification.OutcomeReason = 'Baseline tried to apply this change, but Windows returned an error before it could finish.'
				$classification.FailureCategory = 'General failure'
				$classification.FailureCode = 'general_failure'
				$classification.RecoveryHint = 'Open the detailed log and correct the current system state before deciding on any manual follow-up.'

				if ($combinedText -match '(?i)\b(access denied|permission denied|unauthorized)\b')
				{
					$classification.OutcomeReason = 'Windows blocked this change because Baseline did not have enough permission to finish it.'
					$classification.FailureCategory = 'Access denied'
					$classification.FailureCode = 'access_denied'
				}
				elseif ($combinedText -match '(?i)\b(reboot required|restart required|pending reboot|reboot and retry)\b')
				{
					$classification.OutcomeReason = 'Windows reported that a restart is required before this step can finish properly.'
					$classification.FailureCategory = 'Reboot required'
					$classification.FailureCode = 'reboot_required'
				}
				elseif ($combinedText -match '(?i)\b(missing dependency|dependency missing|not found|missing required|missing package|module not found)\b')
				{
					$classification.OutcomeReason = 'This step could not continue because something it depends on was missing.'
					$classification.FailureCategory = 'Missing dependency'
					$classification.FailureCode = 'missing_dependency'
				}
				elseif ($combinedText -match '(?i)\b(unsupported|not supported|unsupported build|windows build|windows version|server edition)\b')
				{
					$classification.OutcomeReason = 'This change is not supported on the current version or build of Windows.'
					$classification.FailureCategory = 'Unsupported OS/build'
					$classification.FailureCode = 'unsupported_os_build'
				}
				elseif ($combinedText -match '(?i)\b(blocked by current system state|current system state|pending state|pending operation|in use by another process|blocked by policy|policy prevented|busy)\b')
				{
					$classification.OutcomeReason = 'Another app, a pending Windows change, or current system policy blocked this step from finishing.'
					$classification.FailureCategory = 'Blocked by current system state'
					$classification.FailureCode = 'blocked_by_system_state'
				}
				elseif ($combinedText -match '(?i)\b(network|download|timeout|connection|dns|webrequest|http 4|403|404|cloudflare|internet)\b')
				{
					$classification.OutcomeReason = 'This step could not finish because a download or network request failed.'
					$classification.FailureCategory = 'Network/download failure'
					$classification.FailureCode = 'network_download_failure'
				}
				elseif ($combinedText -match '(?i)\b(partial success|partially|some but not all|incomplete|partial)\b')
				{
					$classification.OutcomeReason = 'Part of this step worked, but one or more sub-steps did not finish.'
					$classification.FailureCategory = 'Partial success'
					$classification.FailureCode = 'partial_success'
				}
				elseif ($recoveryText -eq 'Manual')
				{
					$classification.OutcomeReason = 'Baseline could not finish this step automatically. Manual recovery is required.'
					$classification.FailureCategory = 'Manual intervention required'
					$classification.FailureCode = 'manual_intervention_required'
				}

				$retryPolicy = Get-ExecutionRetryPolicy `
					-Status $statusText `
					-FailureCode $classification.FailureCode `
					-RecoveryLevel $recoveryText `
					-Restorable $Restorable `
					-TypeKind $TypeKind `
					-IsRemoval:$IsRemoval
				$classification.IsRecoverable = [bool]$retryPolicy.IsRecoverable
				$classification.RetryAvailability = if ([string]::IsNullOrWhiteSpace([string]$retryPolicy.RetryAvailability)) { $null } else { [string]$retryPolicy.RetryAvailability }
				$classification.RetryReason = if ([string]::IsNullOrWhiteSpace([string]$retryPolicy.RetryReason)) { $null } else { [string]$retryPolicy.RetryReason }
				if (-not [string]::IsNullOrWhiteSpace([string]$retryPolicy.SuggestedRecoveryHint))
				{
					$classification.RecoveryHint = [string]$retryPolicy.SuggestedRecoveryHint
				}

				$classification.OutcomeState = if ($classification.IsRecoverable) { 'Failed and recoverable' } else { 'Failed and manual intervention required' }
				return [pscustomobject]$classification
			}
			default
			{
				return [pscustomobject]$classification
			}
		}
	}

	function Get-RestoreDefaultsOutcomeText
	{
		<#
		.SYNOPSIS
			Maps internal execution outcome codes to restore-specific, beginner-clear user-facing text.
		.DESCRIPTION
			Centralised helper for defaults-restore messaging. Translates FailureCode or OutcomeState
			into wording appropriate for the "Restore to Windows Defaults" workflow.
		#>
		param (
			[string]$FailureCode,
			[string]$OutcomeState = $null,
			[string]$TypeKind = $null
		)

		$isPackage = $TypeKind -in @('Package', 'AppPackage', 'UWPApp')
		$normalizedFailureCode = if ([string]::IsNullOrWhiteSpace($FailureCode)) { $null } else { [string]$FailureCode.Trim() }
		$normalizedOutcomeState = if ([string]::IsNullOrWhiteSpace($OutcomeState)) { $null } else { [string]$OutcomeState.Trim() }

		switch ($normalizedFailureCode)
		{
			'already_at_default'         { return 'Already at Windows default.' }
			'already_in_desired_state'   { return 'Already at Windows default.' }
			'not_applicable'             { return 'Not applicable on this PC or this version of Windows.' }
			'unsupported_environment'    { return 'Not applicable on this PC or this version of Windows.' }
			'not_supported_restore'      { return 'This item is not supported by in-app restore.' }
			'skipped_by_policy'          { return 'This item is not supported by in-app restore.' }
			'restart_required'           { return 'Restored to Windows default. Restart required to finish.' }
			'not_run'                    { return 'Did not run because the restore stopped early.' }
			'general_failure'            {
				if ($isPackage) { return 'This app may require package or Store follow-up to fully restore.' }
				return 'Restore failed. Open the detailed log for more information.'
			}
			'network_download_failure'   { return 'Restore failed due to a network or download issue.' }
			'access_denied'              { return 'Restore blocked - insufficient permissions.' }
			'reboot_required'            { return 'Restart required before this item can be restored.' }
			'missing_dependency'         { return 'Restore could not continue because a dependency is missing.' }
			'blocked_by_system_state'    { return 'Restore blocked by current system state or another process.' }
			'partial_success'            { return 'Partially restored. Some sub-steps did not finish.' }
			'manual_intervention_required' {
				if ($isPackage) { return 'This app may require package or Store follow-up to fully restore.' }
				return 'Manual recovery required to finish restoring this item.'
			}
		}

		switch -Regex ($normalizedOutcomeState)
		{
			'^(Success)$'                              { return 'Restored to Windows default.' }
			'^(Restart pending)$'                      { return 'Restored to Windows default. Restart required to finish.' }
			'^(Already at Windows default|Already in desired state)$' { return 'Already at Windows default.' }
			'^(Not applicable on this system)$'        { return 'Not applicable on this PC or this version of Windows.' }
			'^(Not supported by in-app restore|Skipped by preset or selection)$' { return 'This item is not supported by in-app restore.' }
			'^(Not run)$'                              { return 'Did not run because the restore stopped early.' }
			'^(Failed and recoverable)$' {
				if ($isPackage) { return 'This app may require package or Store follow-up to fully restore.' }
				return 'Restore did not finish. Review the hint below, then retry if appropriate.'
			}
			'^(Failed and manual intervention required)$' {
				if ($isPackage) { return 'This app may require package or Store follow-up to fully restore.' }
				return 'Manual recovery required to finish restoring this item.'
			}
			default {
				if ($isPackage) { return 'This app may require package or Store follow-up to fully restore.' }
				if (-not [string]::IsNullOrWhiteSpace($normalizedOutcomeState)) { return $normalizedOutcomeState }
				return 'Restore outcome unknown.'
			}
		}
	}

	function Get-ExecutionRetryPolicy
	{
		param (
			[string]$Status,
			[string]$FailureCode,
			[string]$RecoveryLevel = $null,
			$Restorable = $null,
			[string]$TypeKind = $null,
			[bool]$IsRemoval = $false
		)

		$policy = [ordered]@{
			IsRecoverable = $false
			RetryAvailability = $null
			RetryReason = $null
			SuggestedRecoveryHint = $null
		}

		if ($Status -ne 'Failed')
		{
			return [pscustomobject]$policy
		}

		$policy.RetryAvailability = 'Retry not offered'
		$failureKey = if ([string]::IsNullOrWhiteSpace($FailureCode)) { 'general_failure' } else { [string]$FailureCode.Trim() }
		$recoveryKey = if ([string]::IsNullOrWhiteSpace($RecoveryLevel)) { $null } else { [string]$RecoveryLevel.Trim() }
		$typeKey = if ([string]::IsNullOrWhiteSpace($TypeKind)) { 'Action' } else { [string]$TypeKind.Trim() }

		$retryableFailureDetails = @{
			'access_denied' = [pscustomobject]@{
				RetryReason = 'Retry is available because this is a direct, fully restorable setting change and the failure was a permission problem you can correct first.'
				RetryHint = 'Correct the permission issue, then retry this setting.'
				ManualHint = 'If you fix the permission problem, review the detailed log and confirm this item still needs manual follow-up before rerunning it.'
			}
			'reboot_required' = [pscustomobject]@{
				RetryReason = 'Retry is available because this is a direct, fully restorable setting change and Windows only needs a restart before it can finish.'
				RetryHint = 'Restart Windows, then retry this setting.'
				ManualHint = 'Restart Windows, then review the detailed log and confirm this item still needs manual follow-up before rerunning it.'
			}
			'missing_dependency' = [pscustomobject]@{
				RetryReason = 'Retry is available because this is a direct, fully restorable setting change and the missing dependency can be fixed before rerunning it.'
				RetryHint = 'Install the missing dependency, then retry this setting.'
				ManualHint = 'Install the missing dependency, then review the detailed log before deciding whether to rerun this item manually.'
			}
			'blocked_by_system_state' = [pscustomobject]@{
				RetryReason = 'Retry is available because this is a direct, fully restorable setting change and the blocker is the current system state, not the change itself.'
				RetryHint = 'Clear the blocking app, policy, or pending system change, then retry this setting.'
				ManualHint = 'Clear the blocking app or pending system change, then review the detailed log before deciding whether to rerun this item manually.'
			}
			'network_download_failure' = [pscustomobject]@{
				RetryReason = 'Retry is available because this is a direct, fully restorable setting change and the failure came from a network or download dependency that can recover.'
				RetryHint = 'Retry this setting after connectivity or the download source recovers.'
				ManualHint = 'Restore connectivity, then review the detailed log before deciding whether to rerun this item manually.'
			}
		}

		if (-not $retryableFailureDetails.ContainsKey($failureKey))
		{
			switch ($failureKey)
			{
				'unsupported_os_build'
				{
					$policy.RetryReason = 'Retry is not offered because this change is unsupported on the current Windows version or build.'
					$policy.SuggestedRecoveryHint = 'No retry is offered because this change is not supported on the current Windows build.'
				}
				'partial_success'
				{
					$policy.RetryReason = 'Retry is not offered because this item only partially completed, so rerunning it automatically is not a trustworthy next step.'
					$policy.SuggestedRecoveryHint = 'Open the detailed log and confirm the current end state before making more changes.'
				}
				'manual_intervention_required'
				{
					$policy.RetryReason = 'Retry is not offered because this item already requires manual correction before it can be attempted again.'
					$policy.SuggestedRecoveryHint = 'Review the detailed log and correct the system state manually before trying anything else.'
				}
				default
				{
					$policy.RetryReason = 'Retry is not offered because the failure does not clearly point to a transient, retry-safe problem.'
					$policy.SuggestedRecoveryHint = 'Open the detailed log and correct the current system state before deciding on any manual follow-up.'
				}
			}

			return [pscustomobject]$policy
		}

		$retryableDetail = $retryableFailureDetails[$failureKey]
		if ($IsRemoval)
		{
			$policy.RetryReason = 'Retry is not offered because this is a removal or uninstall-style change, so automatically rerunning it is not trustworthy.'
			$policy.SuggestedRecoveryHint = [string]$retryableDetail.ManualHint
			return [pscustomobject]$policy
		}
		if ($typeKey -eq 'Action')
		{
			$policy.RetryReason = 'Retry is not offered because this is a one-time action rather than a direct setting change.'
			$policy.SuggestedRecoveryHint = [string]$retryableDetail.ManualHint
			return [pscustomobject]$policy
		}
		if ($null -eq $Restorable)
		{
			$policy.RetryReason = 'Retry is not offered because the manifest does not mark this change as fully restorable.'
			$policy.SuggestedRecoveryHint = [string]$retryableDetail.ManualHint
			return [pscustomobject]$policy
		}
		if (-not [bool]$Restorable)
		{
			$policy.RetryReason = 'Retry is not offered because this change requires manual recovery.'
			$policy.SuggestedRecoveryHint = [string]$retryableDetail.ManualHint
			return [pscustomobject]$policy
		}
		if ($recoveryKey -ne 'Direct')
		{
			$policy.RetryReason = switch ($recoveryKey)
			{
				'DefaultsOnly' { 'Retry is not offered because this item relies on defaults restore instead of a direct retry path.'; break }
				'RestorePoint' { 'Retry is not offered because this item depends on restore-point recovery instead of a direct retry path.'; break }
				'Manual' { 'Retry is not offered because this item depends on manual recovery instead of a direct retry path.'; break }
				default { 'Retry is not offered because the manifest does not mark it as a direct-recovery setting.' }
			}
			$policy.SuggestedRecoveryHint = [string]$retryableDetail.ManualHint
			return [pscustomobject]$policy
		}

		$policy.IsRecoverable = $true
		$policy.RetryAvailability = 'Retry available'
		$policy.RetryReason = [string]$retryableDetail.RetryReason
		$policy.SuggestedRecoveryHint = [string]$retryableDetail.RetryHint
		return [pscustomobject]$policy
	}

	function Test-ExecutionSummaryPackageOperationRecord
	{
		param ([object]$Record)

		if (-not $Record) { return $false }

		$labelsToCheck = @(
			$(if ((Test-GuiObjectField -Object $Record -FieldName 'TypeLabel')) { [string]$Record.TypeLabel } else { $null }),
			$(if ((Test-GuiObjectField -Object $Record -FieldName 'TypeBadgeLabel')) { [string]$Record.TypeBadgeLabel } else { $null }),
			$(if ((Test-GuiObjectField -Object $Record -FieldName 'Type')) { [string]$Record.Type } else { $null })
		)

		return (@($labelsToCheck | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -match '^(?i)package / app' }).Count -gt 0)
	}

	function Get-ExecutionSummaryInsights
	{
		param (
			[object[]]$Results,
			[string]$FatalError = $null
		)

		$results = @($Results | Where-Object { $_ })
		$alreadyDesiredResults = @($results | Where-Object { [string]$_.OutcomeState -in @('Already in desired state', 'Already at Windows default') })
		$notApplicableResults = @($results | Where-Object {
			$outcomeState = if ((Test-GuiObjectField -Object $_ -FieldName 'OutcomeState')) { [string]$_.OutcomeState } else { '' }
			$outcomeState -in @('Not applicable', 'Not applicable on this system')
		})
		$policySkippedResults = @($results | Where-Object { [string]$_.OutcomeState -in @('Skipped by preset or selection', 'Not supported by in-app restore') })
		$packageOperationResults = @($results | Where-Object { Test-ExecutionSummaryPackageOperationRecord -Record $_ })
		$recoverableFailedResults = @($results | Where-Object {
			[string]$_.Status -eq 'Failed' -and
			(Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and
			[bool]$_.IsRecoverable
		})
		$manualFailedResults = @($results | Where-Object {
			[string]$_.Status -eq 'Failed' -and
			-not ((Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and [bool]$_.IsRecoverable)
		})
		$notRunResults = @($results | Where-Object { [string]$_.Status -eq 'Not Run' })
		$failedPackageResults = @($packageOperationResults | Where-Object { [string]$_.Status -eq 'Failed' })
		$partialSuccessResults = @($results | Where-Object {
			(Test-GuiObjectField -Object $_ -FieldName 'FailureCode') -and
			[string]$_.FailureCode -eq 'partial_success'
		})
		$generalFailureResults = @($results | Where-Object {
			[string]$_.Status -eq 'Failed' -and
			(Test-GuiObjectField -Object $_ -FieldName 'FailureCode') -and
			[string]$_.FailureCode -eq 'general_failure'
		})

		$needsLogReview = $false
		if (-not [string]::IsNullOrWhiteSpace($FatalError) -or $notRunResults.Count -gt 0 -or $manualFailedResults.Count -gt 0 -or $partialSuccessResults.Count -gt 0 -or $generalFailureResults.Count -gt 0)
		{
			$needsLogReview = $true
		}

		$reviewLogHint = $null
		if ($needsLogReview)
		{
			if (-not [string]::IsNullOrWhiteSpace($FatalError))
			{
				$reviewLogHint = 'Open the detailed log if you need the exact failing step or exception text from the fatal stop.'
			}
			elseif ($notRunResults.Count -gt 0)
			{
				$reviewLogHint = 'Open the detailed log if you need the exact point where the run stopped before the remaining items could start.'
			}
			elseif ($manualFailedResults.Count -gt 0)
			{
				$reviewLogHint = 'Open the detailed log if you need the exact registry path, package, or helper step that still needs manual correction.'
			}
			elseif ($partialSuccessResults.Count -gt 0)
			{
				$reviewLogHint = 'Open the detailed log if you need the specific sub-step that only completed partially.'
			}
			else
			{
				$reviewLogHint = 'Open the detailed log if you need exact execution details beyond the summary.'
			}
		}

		return [pscustomobject]@{
			AlreadyDesiredCount = $alreadyDesiredResults.Count
			NotApplicableCount = $notApplicableResults.Count
			PolicySkippedCount = $policySkippedResults.Count
			PackageOperationCount = $packageOperationResults.Count
			PackageFailedCount = $failedPackageResults.Count
			RecoverableFailedCount = $recoverableFailedResults.Count
			ManualFailedCount = $manualFailedResults.Count
			NotRunCount = $notRunResults.Count
			NeedsAttentionCount = $recoverableFailedResults.Count + $manualFailedResults.Count + $notRunResults.Count
			NeedsLogReview = $needsLogReview
			ReviewLogHint = $reviewLogHint
		}
	}

	function Get-ExecutionSummaryCountsText
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[object]$SummaryPayload,
			[object]$Insights
		)

		# Safe Mode: simplified counts
		$safeText = Get-UxPostRunCountsText -Mode $Mode -SummaryPayload $SummaryPayload -Insights $Insights
		if ($null -ne $safeText) { return $safeText }

		$parts = @()
		$isRestore = ($Mode -eq 'Defaults')
		$appliedLabel = if ($isRestore) { 'Restored' } else { 'Applied' }
		$alreadyLabel = if ($isRestore) { 'Already at default' } else { 'Already set' }
		$skippedLabel = if ($isRestore) { 'Not supported by in-app restore' } else { 'Skipped by selection' }
		$packageLabel = if ($isRestore) { 'Package/app follow-up' } else { 'Package changes' }
		$parts += "${appliedLabel}: $($SummaryPayload.AppliedCount)"
		if ($SummaryPayload.RestartPendingCount -gt 0) { $parts += "Restart required: $($SummaryPayload.RestartPendingCount)" }
		if ($Insights.AlreadyDesiredCount -gt 0) { $parts += "${alreadyLabel}: $($Insights.AlreadyDesiredCount)" }
		if ($Insights.NotApplicableCount -gt 0) { $parts += "Not applicable: $($Insights.NotApplicableCount)" }
		if ($Insights.PolicySkippedCount -gt 0) { $parts += "${skippedLabel}: $($Insights.PolicySkippedCount)" }
		if ($Insights.PackageOperationCount -gt 0) { $parts += "${packageLabel}: $($Insights.PackageOperationCount)" }
		if ($Insights.RecoverableFailedCount -gt 0) { $parts += "Retry offered: $($Insights.RecoverableFailedCount)" }
		if ($Insights.ManualFailedCount -gt 0) { $parts += "Manual review: $($Insights.ManualFailedCount)" }
		if ($SummaryPayload.NotRunCount -gt 0) { $parts += "Not run: $($SummaryPayload.NotRunCount)" }
		return (($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '. ') + '.'
	}

	function Get-ExecutionSummaryNextStepsText
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[object]$SummaryPayload,
			[object]$Insights
		)

		# Safe Mode: simplified next-steps
		$safeText = Get-UxPostRunNextStepsText -Mode $Mode -SummaryPayload $SummaryPayload -Insights $Insights
		if ($null -ne $safeText) { return $safeText }

		$isRestore = ($Mode -eq 'Defaults')
		$modeLabel = if ($isRestore) { 'defaults restore' } else { 'run' }
		$steps = New-Object System.Collections.Generic.List[string]

		if ($SummaryPayload.RestartPendingCount -gt 0)
		{
			[void]$steps.Add("Restart required to finish settling $($SummaryPayload.RestartPendingCount) item$(if ($SummaryPayload.RestartPendingCount -eq 1) { '' } else { 's' }) from this $modeLabel.")
		}
		if ($Insights.RecoverableFailedCount -gt 0)
		{
			[void]$steps.Add("Retry $($Insights.RecoverableFailedCount) safe item$(if ($Insights.RecoverableFailedCount -eq 1) { '' } else { 's' }) after following the recovery hint on each result.")
		}
		if ($Insights.ManualFailedCount -gt 0)
		{
			$manualText = if ($isRestore) {
				"$($Insights.ManualFailedCount) item$(if ($Insights.ManualFailedCount -eq 1) { '' } else { 's' }) still need manual follow-up before the restore is complete."
			} else {
				"$($Insights.ManualFailedCount) item$(if ($Insights.ManualFailedCount -eq 1) { '' } else { 's' }) still need manual review before retrying."
			}
			[void]$steps.Add($manualText)
		}
		if ($Insights.PackageFailedCount -gt 0)
		{
			$packageText = if ($isRestore) {
				"$($Insights.PackageFailedCount) package/app item$(if ($Insights.PackageFailedCount -eq 1) { '' } else { 's' }) may require Store, winget, or manual reinstall follow-up to fully restore."
			} else {
				"$($Insights.PackageFailedCount) package/app operation$(if ($Insights.PackageFailedCount -eq 1) { '' } else { 's' }) may still need Microsoft Store, winget, or manual reinstall follow-up."
			}
			[void]$steps.Add($packageText)
		}
		if ($Insights.NotApplicableCount -gt 0)
		{
			$naText = if ($isRestore) {
				"$($Insights.NotApplicableCount) item$(if ($Insights.NotApplicableCount -eq 1) { ' does' } else { 's do' }) not apply on this PC or this version of Windows."
			} else {
				"$($Insights.NotApplicableCount) item$(if ($Insights.NotApplicableCount -eq 1) { '' } else { 's' }) were skipped cleanly because they do not apply on this system."
			}
			[void]$steps.Add($naText)
		}
		if ($Insights.PolicySkippedCount -gt 0)
		{
			$skippedText = if ($isRestore) {
				"$($Insights.PolicySkippedCount) item$(if ($Insights.PolicySkippedCount -eq 1) { ' is' } else { 's are' }) not supported by in-app restore."
			} else {
				"$($Insights.PolicySkippedCount) item$(if ($Insights.PolicySkippedCount -eq 1) { '' } else { 's' }) were intentionally left out by the current preset, filter, or selection."
			}
			[void]$steps.Add($skippedText)
		}
		if ($Insights.AlreadyDesiredCount -gt 0)
		{
			$alreadyText = if ($isRestore) {
				"$($Insights.AlreadyDesiredCount) item$(if ($Insights.AlreadyDesiredCount -eq 1) { '' } else { 's' }) already matched the Windows default and did not need changes."
			} else {
				"$($Insights.AlreadyDesiredCount) item$(if ($Insights.AlreadyDesiredCount -eq 1) { '' } else { 's' }) already matched the requested state and did not need changes."
			}
			[void]$steps.Add($alreadyText)
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$Insights.ReviewLogHint))
		{
			[void]$steps.Add([string]$Insights.ReviewLogHint)
		}

		return (($steps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ')
	}

	function Get-ExecutionSummaryDialogCards
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[object]$SummaryPayload,
			[object]$Insights
		)

		$isRestore = ($Mode -eq 'Defaults')
		$appliedLabel = if ($isRestore) { 'Restored' } else { 'Applied' }
		$appliedDetail = if ($isRestore) { 'Returned to Windows defaults' } else { 'Completed successfully' }
		$restartDetail = if ($isRestore) { 'Restart required to finish restoring' } else { 'Restart required to finish applying changes' }
		$cards = @(
			[pscustomobject]@{
				Label = $appliedLabel
				Value = $SummaryPayload.AppliedCount
				Detail = $appliedDetail
				Tone = $(if ($SummaryPayload.AppliedCount -gt 0) { 'Success' } else { 'Muted' })
			},
			[pscustomobject]@{
				Label = 'Needs attention'
				Value = $Insights.NeedsAttentionCount
				Detail = $(if ($isRestore) { 'Failed, manual follow-up, or not-run items' } else { 'Failed, manual-review, or not-run items' })
				Tone = $(if ($Insights.NeedsAttentionCount -gt 0) { 'Danger' } else { 'Muted' })
			},
			[pscustomobject]@{
				Label = 'Restart required'
				Value = $SummaryPayload.RestartPendingCount
				Detail = $restartDetail
				Tone = $(if ($SummaryPayload.RestartPendingCount -gt 0) { 'Caution' } else { 'Muted' })
			}
		)

		if ($Insights.AlreadyDesiredCount -gt 0)
		{
			$alreadyLabel = if ($isRestore) { 'Already at default' } else { 'Already set' }
			$alreadyDetail = if ($isRestore) { 'Already at Windows default' } else { 'No change needed' }
			$cards += [pscustomobject]@{
				Label = $alreadyLabel
				Value = $Insights.AlreadyDesiredCount
				Detail = $alreadyDetail
				Tone = 'Success'
			}
		}
		if ($Insights.NotApplicableCount -gt 0)
		{
			$naDetail = if ($isRestore) { 'Not applicable on this PC' } else { 'Clean skip on this system' }
			$cards += [pscustomobject]@{
				Label = 'Not applicable'
				Value = $Insights.NotApplicableCount
				Detail = $naDetail
				Tone = 'Muted'
			}
		}
		if ($Insights.PolicySkippedCount -gt 0 -and $isRestore)
		{
			$cards += [pscustomobject]@{
				Label = 'Not supported by in-app restore'
				Value = $Insights.PolicySkippedCount
				Detail = 'Permanent or not directly reversible'
				Tone = 'Muted'
			}
		}
		if ($Insights.PackageOperationCount -gt 0)
		{
			$packageLabel = if ($isRestore) { 'Package/app follow-up' } else { 'Package changes' }
			$packageDetail = if ($isRestore) { 'May require Store or manual reinstall follow-up' } else { 'Install, uninstall, or restore style actions' }
			$cards += [pscustomobject]@{
				Label = $packageLabel
				Value = $Insights.PackageOperationCount
				Detail = $packageDetail
				Tone = $(if ($Insights.PackageFailedCount -gt 0) { 'Danger' } else { 'Caution' })
			}
		}
		if ($Insights.RecoverableFailedCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = 'Retry offered'
				Value = $Insights.RecoverableFailedCount
				Detail = 'Safe to retry after follow-up'
				Tone = 'Caution'
			}
		}
		if ($Insights.ManualFailedCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = $(if ($isRestore) { 'Manual follow-up' } else { 'Manual review' })
				Value = $Insights.ManualFailedCount
				Detail = $(if ($isRestore) { 'Needs manual steps outside Baseline' } else { 'Needs manual correction' })
				Tone = 'Danger'
			}
		}

		return @($cards)
	}

	function Update-ExecutionSummaryClassification
	{
		param ([object]$Record)

		if (-not $Record) { return }

		$effectiveMode = if (-not [string]::IsNullOrWhiteSpace($Script:ExecutionMode)) { $Script:ExecutionMode } else { 'Run' }
		$effectiveTypeKind = if ((Test-GuiObjectField -Object $Record -FieldName 'TypeKind') -and -not [string]::IsNullOrWhiteSpace([string]$Record.TypeKind)) { [string]$Record.TypeKind } elseif ((Test-GuiObjectField -Object $Record -FieldName 'Type')) { [string]$Record.Type } else { $null }

		$class = Get-ExecutionSummaryClassification `
			-Status ([string]$Record.Status) `
			-Detail ([string]$Record.Detail) `
			-RecoveryLevel $(if ((Test-GuiObjectField -Object $Record -FieldName 'RecoveryLevel')) { [string]$Record.RecoveryLevel } else { $null }) `
			-Restorable $(if ((Test-GuiObjectField -Object $Record -FieldName 'Restorable')) { $Record.Restorable } else { $null }) `
			-TypeKind $effectiveTypeKind `
			-IsRemoval $(if ((Test-GuiObjectField -Object $Record -FieldName 'IsRemoval')) { [bool]$Record.IsRemoval } else { $false }) `
			-Mode $effectiveMode
		$Record.OutcomeState = [string]$class.OutcomeState
		$Record.OutcomeReason = if ([string]::IsNullOrWhiteSpace([string]$class.OutcomeReason)) { $null } else { [string]$class.OutcomeReason }
		if ($effectiveMode -eq 'Defaults')
		{
			$restoreOutcomeReason = Get-RestoreDefaultsOutcomeText `
				-FailureCode $class.FailureCode `
				-OutcomeState $class.OutcomeState `
				-TypeKind $effectiveTypeKind
			if (-not [string]::IsNullOrWhiteSpace([string]$restoreOutcomeReason))
			{
				$Record.OutcomeReason = [string]$restoreOutcomeReason
			}
		}
		$Record.FailureCategory = if ([string]::IsNullOrWhiteSpace([string]$class.FailureCategory)) { $null } else { [string]$class.FailureCategory }
		$Record.FailureCode = if ([string]::IsNullOrWhiteSpace([string]$class.FailureCode)) { $null } else { [string]$class.FailureCode }
		$Record.IsRecoverable = [bool]$class.IsRecoverable
		$Record.RetryAvailability = if ([string]::IsNullOrWhiteSpace([string]$class.RetryAvailability)) { $null } else { [string]$class.RetryAvailability }
		$Record.RetryReason = if ([string]::IsNullOrWhiteSpace([string]$class.RetryReason)) { $null } else { [string]$class.RetryReason }
		$Record.RecoveryHint = if ([string]::IsNullOrWhiteSpace([string]$class.RecoveryHint)) { $null } else { [string]$class.RecoveryHint }
	}

	function Get-ExecutionResultLiveLogEntry
	{
		param ([object]$Record)

		if (-not $Record)
		{
			return $null
		}

		$nameText = if ((Test-GuiObjectField -Object $Record -FieldName 'Name')) { [string]$Record.Name } else { $null }
		$cleanName = ($nameText -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
		if ([string]::IsNullOrWhiteSpace($cleanName))
		{
			return $null
		}

		$statusText = if ((Test-GuiObjectField -Object $Record -FieldName 'Status')) { [string]$Record.Status } else { '' }
		$outcomeText = if ((Test-GuiObjectField -Object $Record -FieldName 'OutcomeState')) { [string]$Record.OutcomeState } else { '' }
		$detailText = if ((Test-GuiObjectField -Object $Record -FieldName 'Detail')) { [string]$Record.Detail } else { $null }
		$outcomeReasonText = if ((Test-GuiObjectField -Object $Record -FieldName 'OutcomeReason')) { [string]$Record.OutcomeReason } else { $null }
		$reasonText = if (-not [string]::IsNullOrWhiteSpace($detailText)) { $detailText } else { $outcomeReasonText }
		$reasonText = if ([string]::IsNullOrWhiteSpace($reasonText)) { $null } else { ($reasonText -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim() }

		$resultLabel = 'success'
		$logLevel = 'SUCCESS'
		$includeReason = $false

		switch -Regex ($statusText)
		{
			'^(Failed)$'
			{
				$resultLabel = 'failed'
				$logLevel = 'ERROR'
				$includeReason = $true
				break
			}
			'^(Skipped|Not applicable|Not Run)$'
			{
				$resultLabel = 'skipped'
				$logLevel = 'SKIP'
				$includeReason = $true
				break
			}
			'^(Restart pending)$'
			{
				$resultLabel = 'success'
				$logLevel = 'WARNING'
				$includeReason = $true
				break
			}
			'^(Success)$'
			{
				if ($outcomeText -eq 'Restart pending')
				{
					$resultLabel = 'success'
					$logLevel = 'WARNING'
					$includeReason = $true
				}
				break
			}
			default
			{
				switch -Regex ($outcomeText)
				{
					'^(Failed)' 
					{
						$resultLabel = 'failed'
						$logLevel = 'ERROR'
						$includeReason = $true
						break
					}
					'^(Restart pending)$'
					{
						$resultLabel = 'success'
						$logLevel = 'WARNING'
						$includeReason = $true
						break
					}
					'^(Not run|Not applicable on this system|Already in desired state|Already at Windows default|Skipped by preset or selection|Not supported by in-app restore)$'
					{
						$resultLabel = 'skipped'
						$logLevel = 'SKIP'
						$includeReason = $true
						break
					}
				}
			}
		}

		$messageText = if ($includeReason -and -not [string]::IsNullOrWhiteSpace($reasonText))
		{
			"{0} - {1} ({2})" -f $cleanName, $resultLabel, $reasonText
		}
		else
		{
			"{0} - {1}" -f $cleanName, $resultLabel
		}

		return [pscustomobject]@{
			Message = $messageText
			Level = $logLevel
		}
	}

	function Set-ExecutionSummaryStatus
	{
		param (
			[string]$Key,
			[string]$Status,
			[string]$Detail = $null
		)

		if ([string]::IsNullOrWhiteSpace($Key)) { return }
		$record = $Script:ExecutionSummaryLookup[$Key]
		if (-not $record) { return }

		$record.Status = $Status
		if (-not [string]::IsNullOrWhiteSpace($Detail))
		{
			$record.Detail = $Detail.Trim()
		}
		elseif ($Status -eq 'Success')
		{
			$record.Detail = $null
		}
		elseif ($Status -eq 'Skipped' -and [string]::IsNullOrWhiteSpace([string]$record.Detail))
		{
			$record.Detail = 'Skipped because the system already matched the requested state.'
		}

		Update-ExecutionSummaryClassification -Record $record
	}

	function Complete-ExecutionSummary
	{
		param (
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null
		)

		foreach ($record in @($Script:ExecutionSummaryRecords))
		{
			if ($record.Status -in @('Pending', 'Running'))
			{
				$record.Status = 'Not Run'
				if ([string]::IsNullOrWhiteSpace([string]$record.Detail))
				{
					$record.Detail = if ($AbortedRun) {
						'Run was aborted before this tweak completed.'
					}
					elseif (-not [string]::IsNullOrWhiteSpace($FatalError)) {
						'Run stopped before this tweak could complete because of a fatal error.'
					}
					else {
						'This tweak did not produce a final result.'
					}
				}
			}
			Update-ExecutionSummaryClassification -Record $record
		}
	}

	function Get-ExecutionSummaryResults
	{
		return @($Script:ExecutionSummaryRecords | Sort-Object Order)
	}

	function Write-ExecutionSummaryToLog
	{
		param (
			[object[]]$Results,
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null
		)

		$results = @($Results)
		$isRestore = ($Script:ExecutionMode -eq 'Defaults')
		$summaryPayload = GUIExecution\Get-GuiExecutionSummaryPayload -Results $results
		$successCount = $summaryPayload.SuccessCount
		$restartPendingCount = $summaryPayload.RestartPendingCount
		$failedCount = $summaryPayload.FailedCount
		$skippedCount = $summaryPayload.SkippedCount
		$notApplicableCount = $summaryPayload.NotApplicableCount
		$notRunCount = $summaryPayload.NotRunCount
		$recoverableFailedCount = @($results | Where-Object {
			[string]$_.Status -eq 'Failed' -and (Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and [bool]$_.IsRecoverable
		}).Count
		$manualFailedCount = @($results | Where-Object {
			[string]$_.Status -eq 'Failed' -and (-not ((Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and [bool]$_.IsRecoverable))
		}).Count

		$summaryLine = if ($isRestore) {
			"Defaults restore summary: Success=$successCount, RestartPending=$restartPendingCount, Failed=$failedCount (RetryOffered=$recoverableFailedCount, ManualFollowUp=$manualFailedCount), Skipped=$skippedCount, NotApplicable=$notApplicableCount, NotRun=$notRunCount."
		} else {
			"Execution summary: Success=$successCount, RestartPending=$restartPendingCount, Failed=$failedCount (RetryOffered=$recoverableFailedCount, Manual=$manualFailedCount), Skipped=$skippedCount, NotApplicable=$notApplicableCount, NotRun=$notRunCount."
		}
		if ($AbortedRun)
		{
			LogWarning ($summaryLine + $(if ($isRestore) { ' Defaults restore aborted by user.' } else { ' Run aborted by user.' }))
		}
		elseif (-not [string]::IsNullOrWhiteSpace($FatalError))
		{
			LogError "$summaryLine Fatal error: $FatalError"
		}
		elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
		{
			LogWarning $summaryLine
		}
		else
		{
			LogInfo $summaryLine
		}

		foreach ($result in $results)
		{
			$detailSuffix = if ([string]::IsNullOrWhiteSpace([string]$result.Detail)) { '' } else { " | $($result.Detail)" }
			$selectionLabel = if ([string]::IsNullOrWhiteSpace([string]$result.Selection)) { '' } else { " | $($result.Selection)" }
			$typeLabel = if ((Test-GuiObjectField -Object $result -FieldName 'TypeBadgeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeBadgeLabel)) { " | Type: $($result.TypeBadgeLabel)" } elseif ((Test-GuiObjectField -Object $result -FieldName 'TypeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeLabel)) { " | Type: $($result.TypeLabel)" } elseif ((Test-GuiObjectField -Object $result -FieldName 'Type') -and -not [string]::IsNullOrWhiteSpace([string]$result.Type)) { " | Type: $($result.Type)" } else { '' }
			$stateLabel = if ((Test-GuiObjectField -Object $result -FieldName 'CurrentState') -and -not [string]::IsNullOrWhiteSpace([string]$result.CurrentState)) { " | State: $($result.CurrentState)" } else { '' }
			$reasonLabel = if ((Test-GuiObjectField -Object $result -FieldName 'ReasonIncluded') -and -not [string]::IsNullOrWhiteSpace([string]$result.ReasonIncluded)) { " | Why: $($result.ReasonIncluded)" } else { '' }
			$outcomeLabel = if ((Test-GuiObjectField -Object $result -FieldName 'OutcomeState') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeState)) { " | Outcome: $($result.OutcomeState)" } else { '' }
			$outcomeReasonLabel = if ((Test-GuiObjectField -Object $result -FieldName 'OutcomeReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeReason)) { " | OutcomeReason: $($result.OutcomeReason)" } else { '' }
			$failureCategoryLabel = if ((Test-GuiObjectField -Object $result -FieldName 'FailureCategory') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCategory)) { " | FailureCategory: $($result.FailureCategory)" } else { '' }
			$failureCodeLabel = if ((Test-GuiObjectField -Object $result -FieldName 'FailureCode') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCode)) { " | FailureCode: $($result.FailureCode)" } else { '' }
			$retryAvailabilityLabel = if ((Test-GuiObjectField -Object $result -FieldName 'RetryAvailability') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryAvailability)) { " | RetryPolicy: $($result.RetryAvailability)" } else { '' }
			$retryReasonLabel = if ((Test-GuiObjectField -Object $result -FieldName 'RetryReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryReason)) { " | RetryWhy: $($result.RetryReason)" } else { '' }
			$recoverableLabel = if ((Test-GuiObjectField -Object $result -FieldName 'IsRecoverable')) { " | Recoverable: $([bool]$result.IsRecoverable)" } else { '' }
			$recoveryHintLabel = if ((Test-GuiObjectField -Object $result -FieldName 'RecoveryHint') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryHint)) { " | RecoveryHint: $($result.RecoveryHint)" } else { '' }
			$linePrefix = if ($isRestore) { 'Restore summary' } else { 'Run summary' }
			$line = "$linePrefix | $($result.Status) | [$($result.Category)] $($result.Name)$selectionLabel$typeLabel$stateLabel$reasonLabel$outcomeLabel$outcomeReasonLabel$failureCategoryLabel$failureCodeLabel$retryAvailabilityLabel$retryReasonLabel$recoverableLabel$recoveryHintLabel$detailSuffix"
			switch ($result.Status)
			{
				'Failed' { LogError $line }
				'Restart pending' { LogWarning $line }
				'Skipped' { LogWarning $line }
				'Not Run' { LogWarning $line }
				default { LogInfo $line }
			}
		}
	}

	function Sync-DefaultsControlsFromExecutionSummary
	{
		param ([object[]]$Results)

		foreach ($result in @($Results | Where-Object { $_.Status -in @('Success', 'Restart pending') }))
		{
			if ([string]::IsNullOrWhiteSpace([string]$result.Key)) { continue }

			$ctlKey = [int]$result.Key
			$ctl = $Script:Controls[$ctlKey]
			$twk = $Script:TweakManifest[$ctlKey]
			if (-not $ctl -or -not $twk) { continue }

			if ((Test-GuiObjectField -Object $ctl -FieldName 'IsChecked'))
			{
				$ctl.IsChecked = [bool]$twk.WinDefault
			}
			elseif ((Test-GuiObjectField -Object $ctl -FieldName 'SelectedIndex'))
			{
				$winDefIdx = [array]::IndexOf($twk.Options, $twk.WinDefault)
				if ($winDefIdx -ge 0) { $ctl.SelectedIndex = [int]$winDefIdx }
			}
		}
	}

