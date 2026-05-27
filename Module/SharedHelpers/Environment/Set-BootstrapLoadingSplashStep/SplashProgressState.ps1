if ($Splash -is [hashtable])
	{
		if ($Status -eq 'in_progress')
		{
			$Splash['ChecklistProgressActive'] = $true
		}
		elseif ($StepId -eq 'finalize' -and $Status -eq 'completed')
		{
			$Splash['ChecklistProgressActive'] = $false
			$Splash['CompletionAnimationDeadlineUtc'] = [datetime]::UtcNow.AddMilliseconds(360)
		}
	}
