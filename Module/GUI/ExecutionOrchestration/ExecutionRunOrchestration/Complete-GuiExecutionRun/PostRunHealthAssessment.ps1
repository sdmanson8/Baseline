if (
			$Mode -eq 'Run' -and
			-not $RemoteExecution -and
			-not $AbortedRun -and
			-not $FatalError -and
			$failedCount -eq 0 -and
			$notRunCount -eq 0 -and
			$restartPendingCount -eq 0 -and
			$appliedCount -gt 0 -and
			(Get-Command -Name 'Resolve-BaselineSettingsAppsFeaturesHealthAssessment' -CommandType Function -ErrorAction SilentlyContinue)
		)
		{
			try
			{
				$settingsAppsFeaturesHealthAssessment = Resolve-BaselineSettingsAppsFeaturesHealthAssessment
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionOrchestration.RunCompletion.SettingsAppsFeaturesHealthAssessment'
			}

			if ($settingsAppsFeaturesHealthAssessment -and -not [bool]$settingsAppsFeaturesHealthAssessment.Healthy)
			{
				$healthCheckFailed = $true
			}
		}
		if (
			$Mode -eq 'Run' -and
			-not $RemoteExecution -and
			-not $AbortedRun -and
			-not $FatalError -and
			$failedCount -eq 0 -and
			$notRunCount -eq 0 -and
			$restartPendingCount -eq 0 -and
			$appliedCount -gt 0 -and
			(Get-Command -Name 'Resolve-BaselineScreenSnippingHealthAssessment' -CommandType Function -ErrorAction SilentlyContinue)
		)
		{
			try
			{
				$screenSnippingHealthAssessment = Resolve-BaselineScreenSnippingHealthAssessment
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionOrchestration.RunCompletion.ScreenSnippingHealthAssessment'
			}

			if ($screenSnippingHealthAssessment -and -not [bool]$screenSnippingHealthAssessment.Healthy)
			{
				$healthCheckFailed = $true
				if ($Script:ExecutionSummaryLookup.ContainsKey('PrtScnSnippingTool'))
				{
					Set-ExecutionSummaryStatus -Key 'PrtScnSnippingTool' -Status 'Failed' -Detail ([string]$screenSnippingHealthAssessment.Message)
					$summaryNeedsRefresh = $true
				}
			}
		}

		if ($summaryNeedsRefresh)
		{
			$summaryPayload = GUIExecution\Get-GuiExecutionSummaryPayload -Results $executionSummary
			if ($Script:RunState)
			{
				$Script:RunState['SummaryPayload'] = $summaryPayload
			}
			$restartPendingCount = $summaryPayload.RestartPendingCount
			$appliedCount = $summaryPayload.AppliedCount
			$failedCount = $summaryPayload.FailedCount
			$skippedCount = $summaryPayload.SkippedCount
			$notApplicableCount = $summaryPayload.NotApplicableCount
			$notRunCount = $summaryPayload.NotRunCount
			$CompletedCount = $summaryPayload.TotalCount - $notRunCount
			$recoverableFailedResults = @($executionSummary | Where-Object {
				[string]$_.Status -eq 'Failed' -and (Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and [bool]$_.IsRecoverable
			})
			$executionInsights = Get-ExecutionSummaryInsights -Results $executionSummary -FatalError $FatalError
			$summaryCountsText = Get-ExecutionSummaryCountsText -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
			$summaryNextStepsText = Get-ExecutionSummaryNextStepsText -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
			$summaryCards = Get-ExecutionSummaryDialogCards -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
			$shouldOfferLogReview = [bool]$executionInsights.NeedsLogReview
			$displayLogPath = if ($shouldOfferLogReview) { $LogPath } else { $null }
		}
