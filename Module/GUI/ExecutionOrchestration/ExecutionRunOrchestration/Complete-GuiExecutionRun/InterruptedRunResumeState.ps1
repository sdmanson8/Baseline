if ($AbortedRun)
		{
			$resumeCandidates = @(Get-ExecutionResumeCandidateList -Results $executionSummary)
			if ($resumeCandidates.Count -gt 0)
			{
				$null = Save-GuiInterruptedRunProfile -ResumeCandidates $resumeCandidates -Mode $Mode -Reason 'Interrupted run'
			}
			else
			{
				$null = Clear-GuiInterruptedRunProfile
			}
		}
		else
		{
			$null = Clear-GuiInterruptedRunProfile
		}
