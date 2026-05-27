try
		{
			$gameModeOperation = if ($gameModeContext -and (Test-GuiObjectField -Object $gameModeContext -FieldName 'Operation') -and -not [string]::IsNullOrWhiteSpace([string]$gameModeContext.Operation)) { [string]$gameModeContext.Operation } else { 'Apply' }
			if ($gameModeContext -and $gameModeOperation -ne 'Undo')
			{
				$gameModeUndoList = @(Get-GameModeUndoRunList -Results $executionSummary -ProfileName $gameModeContext.Profile)
			}

			$dlgTitle = if ($gameModeContext -and $gameModeOperation -eq 'Undo') {
				if ($FatalError) {
					Get-UxLocalizedString -Key 'GuiDlgGameModeUndoFailed' -Fallback 'Game Mode Undo Failed'
				} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
					Get-UxLocalizedString -Key 'GuiDlgGameModeUndoPartiallyCompleted' -Fallback 'Game Mode Undo Partially Completed'
				} elseif ($restartPendingCount -gt 0) {
					Get-UxLocalizedString -Key 'GuiDlgGameModeUndoRestartPending' -Fallback 'Game Mode Undo Restart Pending'
				} else {
					Get-UxLocalizedString -Key 'GuiDlgGameModeUndoComplete' -Fallback 'Game Mode Undo Complete'
				}
			} elseif ($FatalError) {
				Get-UxLocalizedString -Key 'GuiDlgRunFailed' -Fallback 'Run Failed'
			} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				Get-UxLocalizedString -Key 'GuiDlgRunPartiallyCompleted' -Fallback 'Run Partially Completed'
			} elseif ($restartPendingCount -gt 0) {
				Get-UxLocalizedString -Key 'GuiDlgRunCompleteRestartPending' -Fallback 'Run Complete (Restart Pending)'
			} else {
				Get-UxLocalizedString -Key 'GuiDlgRunComplete' -Fallback 'Run Complete'
			}
			$whatChangedOpeningLine = if ($gameModeContext -and $gameModeOperation -eq 'Undo') {
				"What happened: $appliedCount gaming change$(if ($appliedCount -eq 1) { '' } else { 's' }) rolled back successfully."
			} else {
				"What happened: $appliedCount tweak$(if ($appliedCount -eq 1) { '' } else { 's' }) applied successfully."
			}
			# Safe Mode: show human-readable list of what changed instead of technical summary
			$humanReadableSummary = $null
			if ((Test-IsSafeModeUX) -and -not ($gameModeContext -and $gameModeOperation -eq 'Undo'))
			{
				$humanReadableSummary = Get-UxHumanReadableSummary -Results $executionSummary
			}
			$whatChangedText = if ($humanReadableSummary)
			{
				"$whatChangedOpeningLine`n`n$humanReadableSummary"
			}
			else
			{
				Build-WhatChangedSummaryText `
					-OpeningLine $whatChangedOpeningLine `
					-Noun 'tweak' `
					-Insights $executionInsights `
					-RestartPendingCount $restartPendingCount `
					-NotRunCount $notRunCount `
					-AlreadyDesiredPhrase 'already matched the requested state' `
					-RestartPendingPhrase 'still need a restart to finish applying' `
					-NotApplicableSingularPhrase ' did not apply on this system' `
					-NotApplicablePluralPhrase 's did not apply on this system' `
					-PolicySkippedSingularPhrase ' was intentionally skipped by the current selection' `
					-PolicySkippedPluralPhrase 's were intentionally skipped by the current selection'
			}
			$gamingSummaryText = $null
			if ($gameModeContext)
			{
				$restartGuidance = if ($restartPendingCount -gt 0) {
					'Restart guidance: a reboot is recommended after this Game Mode run so graphics and overlay changes can fully settle.'
				}
				else {
					'Restart guidance: no restart-specific gaming actions were queued in this run.'
				}
				if ($gameModeOperation -eq 'Undo')
				{
					$gamingSummaryText = "Game Mode undo summary: profile $($gameModeContext.Profile) rollback finished.`n`n$restartGuidance`n`nYou can rerun Game Mode with a different profile whenever you want to rebuild the focused gaming workflow."
				}
				else
				{
					$decisionText = if ((Test-GuiObjectField -Object $gameModeContext -FieldName 'DecisionOverrides')) { Get-GameModeDecisionOverridesText -Overrides $gameModeContext.DecisionOverrides } else { 'none' }
					$undoOptionsLabel = if (Test-IsSafeModeUX) { 'Undo options' } else { 'Rollback options' }
					$rollbackText = if ($gameModeUndoList.Count -gt 0)
					{
						"{0}: {1} gaming change{2} can be undone directly from the post-run summary." -f $undoOptionsLabel, $gameModeUndoList.Count, $(if ($gameModeUndoList.Count -eq 1) { '' } else { 's' })
					}
					else
					{
						"$undoOptionsLabel`: no directly undoable gaming changes were applied in this run."
					}
					$gamingSummaryText = "Game Mode summary: profile $($gameModeContext.Profile) completed under the focused gaming workflow.`n`nDecision overrides: $decisionText.`n`n$restartGuidance`n`n$rollbackText"
					LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionGameModePostRunSummary' -Fallback 'Game Mode post-run summary: Profile={0}, Applied={1}, RestartPending={2}, DirectUndoEligible={3}, Decisions={4}' -FormatArgs @($gameModeContext.Profile, $appliedCount, $restartPendingCount, $gameModeUndoList.Count, $decisionText))
				}
			}

			$dlgMsg = if ($FatalError) {
				"$whatChangedText`n`nThe run stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
			} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks partially completed.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} elseif ($restartPendingCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks have finished running, but a restart is still recommended to finish applying some changes.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} elseif ($skippedCount -gt 0 -or $notApplicableCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks have finished running.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} elseif ($healthCheckFailed) {
				"$whatChangedText`n`nSelected tweaks have finished running, but the Settings appsfeatures health check needs attention.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} else {
				"$whatChangedText`n`nSelected tweaks have finished running successfully.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$gamingSummaryText))
			{
				$dlgMsg += "`n`n$gamingSummaryText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$summaryNextStepsText))
			{
				$dlgMsg += "`n`nNext steps: $summaryNextStepsText"
			}
			if (-not ($gameModeContext -and $gameModeOperation -eq 'Undo'))
			{
				$rollbackCommandList = @(Get-ExecutionRollbackCommandList -Results $executionSummary)
			}

			# Post-run snapshot comparison
			if ($Script:PreRunSnapshot)
			{
				try
				{
					$postRunSnapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest
					$snapshotComparison = Compare-SystemStateSnapshots -Before $Script:PreRunSnapshot -After $postRunSnapshot
					$summaryPayload | Add-Member -NotePropertyName 'SnapshotChangedCount' -NotePropertyValue $snapshotComparison.Changed.Count -Force
					$summaryPayload | Add-Member -NotePropertyName 'SnapshotComparison' -NotePropertyValue $snapshotComparison -Force
					if ($Script:RunState)
					{
						$Script:RunState['PostRunSnapshot'] = $postRunSnapshot
						$Script:RunState['SnapshotComparison'] = $snapshotComparison
					}
					LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionPostRunSnapshotComparison' -Fallback 'Post-run snapshot comparison: {0} changed, {1} unchanged, {2} added, {3} removed' -FormatArgs @($snapshotComparison.Changed.Count, $snapshotComparison.Unchanged.Count, $snapshotComparison.Added.Count, $snapshotComparison.Removed.Count))
				}
				catch
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionPostRunSnapshotFailed' -Fallback 'Failed to capture post-run snapshot'))
				}
			}

			# Auto-save last run for Undo Last Run feature and support-bundle
			# snapshot export. Snapshot payloads are retained even when the
			# undo command list is empty so the latest run's diff can still be
			# exported later.
			if (($Mode -eq 'Run' -or $Mode -eq 'Defaults') -and ($rollbackCommandList.Count -gt 0 -or $Script:PreRunSnapshot))
			{
				try
				{
					$lastRunPath = GUICommon\Get-GuiLastRunFilePath
					$lastRunPayload = @{
						Schema = 'Baseline.LastRun'
						Timestamp = (Get-Date -Format 'o')
						AppliedCount = $appliedCount
						RollbackCommands = $rollbackCommandList
						State = (Get-GuiSettingsSnapshot)
						PreRunSnapshot = $Script:PreRunSnapshot
						PostRunSnapshot = if ($Script:RunState -and $Script:RunState.ContainsKey('PostRunSnapshot')) { $Script:RunState['PostRunSnapshot'] } else { $null }
					}
					[System.IO.File]::WriteAllText($lastRunPath, ($lastRunPayload | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
					$Script:LastRunProfile = [pscustomobject]$lastRunPayload
					if ((Test-GuiObjectField -Object $Script:BtnUndoLastRun -FieldName 'IsEnabled')) { $Script:BtnUndoLastRun.IsEnabled = ($rollbackCommandList.Count -gt 0) }
					LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAutoSavedLastRunProfile' -Fallback 'Auto-saved last run profile with {0} rollback command(s).' -FormatArgs @($rollbackCommandList.Count))
				}
				catch
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionAutoSaveLastRunProfileFailed' -Fallback 'Failed to auto-save last run profile'))
				}
			}
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionSummaryFailed' -Fallback 'Failed to build execution summary details'))
			# Fall through to show the summary dialog with whatever we have
		}
