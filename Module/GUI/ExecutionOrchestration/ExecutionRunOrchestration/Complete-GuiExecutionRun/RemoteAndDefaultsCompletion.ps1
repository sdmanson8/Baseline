if ($RemoteExecution)
		{
			$remoteLabel = if (-not [string]::IsNullOrWhiteSpace([string]$RemoteTargetLabel)) { [string]$RemoteTargetLabel } else { 'remote target' }
			$remoteTargetCount = @($executionSummary).Count
			$finalLabel = if ($AbortedRun) { Get-UxLocalizedString -Key 'GuiProgressAborted' -Fallback 'Aborted' } elseif ($FatalError) { Get-UxLocalizedString -Key 'GuiProgressFailed' -Fallback 'Failed' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { Get-UxLocalizedString -Key 'GuiProgressPartiallyComplete' -Fallback 'Partially Complete' } else { Get-UxLocalizedString -Key 'GuiProgressDone' -Fallback 'Done' }
			& $Script:UpdateProgressFn -Completed $CompletedCount -Total $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }) -CurrentAction $finalLabel

			$statusMsg = if ($AbortedRun)
			{
				Get-UxBilingualLocalizedString -Key 'GuiStatusRunAborted' -Fallback 'Remote run aborted. Completed {0} of {1}. {2}' -FormatArgs @($CompletedCount, $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }), $summaryCountsText)
			}
			elseif ($FatalError)
			{
				Get-UxBilingualLocalizedString -Key 'GuiStatusRunFailed' -Fallback 'Remote run failed. Completed {0} of {1}. {2} Open the summary for next steps.' -FormatArgs @($CompletedCount, $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }), $summaryCountsText)
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
			{
				Get-UxBilingualLocalizedString -Key 'GuiStatusRunPartial' -Fallback 'Remote run partially completed. Completed {0} of {1}. {2} Open the summary for next steps.' -FormatArgs @($CompletedCount, $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }), $summaryCountsText)
			}
			else
			{
				Get-UxBilingualLocalizedString -Key 'GuiStatusRunComplete' -Fallback 'Remote run complete. Completed {0} of {1}. {2}' -FormatArgs @($CompletedCount, $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }), $summaryCountsText)
			}
			Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusRunSummary' -Fallback '{0}' -FormatArgs @($statusMsg)) -Tone $(if ($AbortedRun -or $FatalError -or $failedCount -gt 0 -or $notRunCount -gt 0 -or $healthCheckFailed) { 'caution' } elseif ($restartPendingCount -gt 0) { 'danger' } else { 'success' })

			$dlgTitle = if ($FatalError) { "Remote Run Failed - $remoteLabel" } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { "Remote Run Partially Completed - $remoteLabel" } elseif ($restartPendingCount -gt 0) { "Remote Run Complete (Restart Pending) - $remoteLabel" } else { "Remote Run Complete - $remoteLabel" }
			$whatChangedText = "What happened: $successCount remote target$(if ($successCount -eq 1) { '' } else { 's' }) completed successfully."
			if ($restartPendingCount -gt 0)
			{
				$whatChangedText += " $restartPendingCount remote target$(if ($restartPendingCount -eq 1) { '' } else { 's' }) still need a restart to finish."
			}
			if ($failedCount -gt 0)
			{
				$whatChangedText += " $failedCount remote target$(if ($failedCount -eq 1) { '' } else { 's' }) failed."
			}
			if ($skippedCount -gt 0)
			{
				$whatChangedText += " $skippedCount remote target$(if ($skippedCount -eq 1) { '' } else { 's' }) were skipped."
			}
			if ($notApplicableCount -gt 0)
			{
				$whatChangedText += " $notApplicableCount remote target$(if ($notApplicableCount -eq 1) { '' } else { 's' }) were not applicable."
			}
			if ($notRunCount -gt 0)
			{
				$whatChangedText += " $notRunCount remote target$(if ($notRunCount -eq 1) { '' } else { 's' }) did not run."
			}

			$dlgMessage = if ($FatalError)
			{
				"$whatChangedText`n`nThe remote run stopped because of an unexpected error.`n`nCompleted $CompletedCount of $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }).`n$summaryCountsText`n`nFatal error:`n$FatalError"
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
			{
				"$whatChangedText`n`nRemote execution partially completed.`n`nCompleted $CompletedCount of $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }).`n$summaryCountsText"
			}
			else
			{
				"$whatChangedText`n`nRemote execution completed successfully.`n`nCompleted $CompletedCount of $(if ($remoteTargetCount -gt 0) { $remoteTargetCount } else { 1 }).`n$summaryCountsText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$summaryNextStepsText))
			{
				$dlgMessage += "`n`nNext steps: $summaryNextStepsText"
			}
			$summaryButtons = @()
			if ($shouldOfferLogReview) { $summaryButtons += 'Open Detailed Log' }
			$summaryButtons += 'Close'
			$nextStep = Show-ExecutionSummaryDialog -Title $dlgTitle `
				-SummaryText $dlgMessage `
				-Results $executionSummary `
				-LogPath $displayLogPath `
				-SummaryCards $summaryCards `
				-Buttons $summaryButtons

			if ($nextStep -eq 'Open Detailed Log')
			{
				Exit-ExecutionView
				Show-LogDialog -LogPath $LogPath
				Invoke-GuiExecutionCompletionToast -Mode $Mode -Title $dlgTitle -Body $summaryCountsText
				Set-ExecutionGameModeContext -Context $null
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}

			Exit-ExecutionView
			Invoke-GuiExecutionCompletionToast -Mode $Mode -Title $dlgTitle -Body $summaryCountsText
			Set-ExecutionGameModeContext -Context $null
			$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
		}

		if ($Mode -eq 'Defaults')
		{
			Sync-DefaultsControlsFromExecutionSummary -Results $executionSummary
			if ($Script:CurrentPrimaryTab)
			{
				Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
			}

			$finalLabel = if ($AbortedRun) { Get-UxLocalizedString -Key 'GuiProgressAborted' -Fallback 'Aborted' } elseif ($FatalError) { Get-UxLocalizedString -Key 'GuiProgressFailed' -Fallback 'Failed' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { Get-UxLocalizedString -Key 'GuiProgressPartiallyComplete' -Fallback 'Partially Complete' } else { Get-UxLocalizedString -Key 'GuiProgressDone' -Fallback 'Done' }
			& $Script:UpdateProgressFn -Completed $CompletedCount -Total $Script:TotalRunnableTweaks -CurrentAction $finalLabel

			if ($AbortedRun)
			{
				$rawRunAbortDisposition = if ($null -eq $Script:RunAbortDisposition) { '<null>' } else { [string]$Script:RunAbortDisposition }
				$runAbortDisposition = Get-RunAbortDisposition
				LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionCompleteDefaultsAborted' -Fallback '[Complete-Defaults] AbortedRun=true, RunAbortDisposition={0}, EffectiveDisposition={1}' -FormatArgs @($rawRunAbortDisposition, $runAbortDisposition))
				Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusDefaultsAborted' -Fallback '' -FormatArgs @($CompletedCount, $Script:TotalRunnableTweaks, $summaryCountsText)) -Tone 'caution'

				if ($runAbortDisposition -eq 'Exit')
				{
					Close-GuiMainWindow -Reason 'Defaults restore abort disposition requested exit.'
				}
				else
				{
					Set-RunAbortDisposition -Disposition 'Return'
					Exit-ExecutionView
				}
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}

			if ($FatalError)
			{
				Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusDefaultsFailed' -Fallback '' -FormatArgs @($CompletedCount, $Script:TotalRunnableTweaks, $summaryCountsText)) -Tone 'caution'
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
			{
				Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusDefaultsPartial' -Fallback '' -FormatArgs @($CompletedCount, $Script:TotalRunnableTweaks, $summaryCountsText)) -Tone 'caution'
			}
			elseif ($restartPendingCount -gt 0)
			{
				Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusDefaultsCompleteRestart' -Fallback '' -FormatArgs @($CompletedCount, $Script:TotalRunnableTweaks, $summaryCountsText)) -Tone 'danger'
			}
			else
			{
				Set-GuiStatusText -Text (Get-UxLocalizedString -Key 'GuiStatusDefaultsComplete' -Fallback '' -FormatArgs @($CompletedCount, $Script:TotalRunnableTweaks, $summaryCountsText)) -Tone 'success'
			}

			$dlgTitle = if ($FatalError) { Get-UxLocalizedString -Key 'GuiDlgDefaultsRestoreFailed' -Fallback 'Defaults Restore Failed' } elseif ($restartPendingCount -gt 0 -and $failedCount -eq 0 -and $notRunCount -eq 0) { Get-UxLocalizedString -Key 'GuiDlgDefaultsRestoreRestartPending' -Fallback 'Defaults Restore Restart Pending' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { Get-UxLocalizedString -Key 'GuiDlgDefaultsRestorePartiallyCompleted' -Fallback 'Defaults Restore Partially Completed' } else { Get-UxLocalizedString -Key 'GuiDlgDefaultsRestoreComplete' -Fallback 'Defaults Restore Complete' }
			$whatChangedText = Build-WhatChangedSummaryText `
				-OpeningLine "What happened: $appliedCount item$(if ($appliedCount -eq 1) { '' } else { 's' }) restored to recorded defaults." `
				-Noun 'item' `
				-Insights $executionInsights `
				-RestartPendingCount $restartPendingCount `
				-NotRunCount $notRunCount `
				-AlreadyDesiredPhrase 'already matched the recorded default' `
				-RestartPendingPhrase 'still need a restart to finish restoring' `
				-NotApplicableSingularPhrase ' does not apply on this PC or this version of Windows' `
				-NotApplicablePluralPhrase 's do not apply on this PC or this version of Windows' `
				-PolicySkippedSingularPhrase ' is not supported by in-app restore' `
				-PolicySkippedPluralPhrase 's are not supported by in-app restore' `
				-RecoverableSingularPhrase ' qualifies for a safe restore retry' `
				-RecoverablePluralPhrase 's qualify for a safe restore retry' `
				-ManualSingularPhrase ' still needs manual follow-up' `
				-ManualPluralPhrase 's still need manual follow-up'
			$dlgMessage = if ($FatalError) {
				"$whatChangedText`n`nThe defaults restore stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				"$whatChangedText`n`nRecorded defaults restore partially completed.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			else {
				"$whatChangedText`n`nRecorded defaults restored successfully.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$summaryNextStepsText))
			{
				$dlgMessage += "`n`nNext steps: $summaryNextStepsText"
			}
			$summaryButtons = @()
			if ($recoverableFailedResults.Count -gt 0) { $summaryButtons += 'Retry Safe Restore Failures' }
			$resumeInterruptedResults = @(Get-ExecutionResumeCandidateList -Results $executionSummary)
			if ($abortedRun -and $resumeInterruptedResults.Count -gt 0) { $summaryButtons += 'Resume Interrupted Run' }
			if ($shouldOfferLogReview) { $summaryButtons += 'Open Detailed Log' }
			$summaryButtons += 'Close'
			$nextStep = Show-ExecutionSummaryDialog -Title $dlgTitle `
				-SummaryText $dlgMessage `
				-Results $executionSummary `
				-LogPath $displayLogPath `
				-SummaryCards $summaryCards `
				-Buttons $summaryButtons

			if ($nextStep -eq 'Retry Safe Restore Failures')
			{
				LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionRetryingSafeDefaultsFailures' -Fallback 'Retrying safe defaults failures: Count={0}' -FormatArgs @($recoverableFailedResults.Count))
				Start-GuiExecutionRun -TweakList $recoverableFailedResults -Mode 'Defaults' -ExecutionTitle (Get-UxLocalizedString -Key 'GuiExecTitleRetryingSafeRestore' -Fallback 'Retrying Safe Restore Failures') -ForceUnsupported:$ForceUnsupported
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}
			if ($nextStep -eq 'Resume Interrupted Run')
			{
				LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionResumingInterruptedDefaultsRun' -Fallback 'Resuming interrupted defaults run: Count={0}' -FormatArgs @($resumeInterruptedResults.Count))
				Start-GuiExecutionRun -TweakList $resumeInterruptedResults -Mode 'Defaults' -ExecutionTitle (Get-UxLocalizedString -Key 'GuiExecTitleResumingInterruptedRun' -Fallback 'Resuming Interrupted Run') -ForceUnsupported:$ForceUnsupported
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}
			if ($nextStep -eq 'Open Detailed Log')
			{
				Exit-ExecutionView
				Show-LogDialog -LogPath $LogPath
				Set-ExecutionGameModeContext -Context $null
				$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
			}

			Exit-ExecutionView
			Set-ExecutionGameModeContext -Context $null
			$__baselineExtractedPartHasReturnValue = $false; $__baselineExtractedPartDidReturn = $true; return
		}
