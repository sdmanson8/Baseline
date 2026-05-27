
	<#
	    .SYNOPSIS
	#>

	function Set-RunAbortDisposition
	{
		param (
			[string]$Disposition = $null
		)

		$resolvedDisposition = if ([string]::IsNullOrWhiteSpace([string]$Disposition))
		{
			$null
		}
		else
		{
			[string]$Disposition.Trim()
		}

		$Script:RunAbortDisposition = $resolvedDisposition
		if ($Script:RunState)
		{
			$Script:RunState['AbortDisposition'] = $resolvedDisposition
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-RunAbortDisposition
	{
		$stateDisposition = $null
		if ($Script:RunState -and $Script:RunState.ContainsKey('AbortDisposition'))
		{
			$stateDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunState['AbortDisposition']))
			{
				$null
			}
			else
			{
				[string]$Script:RunState['AbortDisposition']
			}
		}

		$scriptDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition))
		{
			$null
		}
		else
		{
			[string]$Script:RunAbortDisposition
		}

		$resolvedDisposition = if (-not [string]::IsNullOrWhiteSpace([string]$stateDisposition))
		{
			$stateDisposition
		}
		else
		{
			$scriptDisposition
		}

		if ([string]::IsNullOrWhiteSpace([string]$resolvedDisposition))
		{
			return 'Return'
		}

		return [string]$resolvedDisposition
	}

	<#
	    .SYNOPSIS
	#>

	function Reset-RunAbortState
	{
		$Script:AbortRequested = $false
		Set-RunAbortDisposition -Disposition $null
	}

	function Build-WhatChangedSummaryText
	{
		<#
		.SYNOPSIS
			Builds the "What happened" summary string from execution insight counts.
		.DESCRIPTION
			Shared helper that eliminates duplicated whatChangedText construction
			between the Defaults-mode and standard/GameMode completion paths.
		#>
		param (
			[string]$OpeningLine,
			[string]$Noun,
			[object]$Insights,
			[int]$RestartPendingCount,
			[int]$NotRunCount,
			[string]$AlreadyDesiredPhrase,
			[string]$RestartPendingPhrase,
			[string]$NotApplicableSingularPhrase,
			[string]$NotApplicablePluralPhrase,
			[string]$PolicySkippedSingularPhrase,
			[string]$PolicySkippedPluralPhrase,
			[string]$RecoverableSingularPhrase = ' qualifies for a safe retry',
			[string]$RecoverablePluralPhrase = 's qualify for a safe retry',
			[string]$ManualSingularPhrase = ' still needs manual review',
			[string]$ManualPluralPhrase = 's still need manual review'
		)

		$text = $OpeningLine
		if ($Insights.AlreadyDesiredCount -gt 0)
		{
			$text += " $($Insights.AlreadyDesiredCount) $Noun$(if ($Insights.AlreadyDesiredCount -eq 1) { '' } else { 's' }) $AlreadyDesiredPhrase."
		}
		if ($RestartPendingCount -gt 0)
		{
			$text += " $RestartPendingCount $Noun$(if ($RestartPendingCount -eq 1) { '' } else { 's' }) $RestartPendingPhrase."
		}
		if ($Insights.NotApplicableCount -gt 0)
		{
			$text += " $($Insights.NotApplicableCount) $Noun$(if ($Insights.NotApplicableCount -eq 1) { $NotApplicableSingularPhrase } else { $NotApplicablePluralPhrase })."
		}
		if ($Insights.PolicySkippedCount -gt 0)
		{
			$text += " $($Insights.PolicySkippedCount) $Noun$(if ($Insights.PolicySkippedCount -eq 1) { $PolicySkippedSingularPhrase } else { $PolicySkippedPluralPhrase })."
		}
		if ($Insights.RecoverableFailedCount -gt 0)
		{
			$text += " $($Insights.RecoverableFailedCount) $Noun$(if ($Insights.RecoverableFailedCount -eq 1) { $RecoverableSingularPhrase } else { $RecoverablePluralPhrase })."
		}
		if ($Insights.ManualFailedCount -gt 0)
		{
			$text += " $($Insights.ManualFailedCount) $Noun$(if ($Insights.ManualFailedCount -eq 1) { $ManualSingularPhrase } else { $ManualPluralPhrase })."
		}
		if ($NotRunCount -gt 0)
		{
			$text += " $NotRunCount $Noun$(if ($NotRunCount -eq 1) { '' } else { 's' }) did not run."
		}
		return $text
	}

	<#
	    .SYNOPSIS
	#>

	function Invoke-GuiExecutionCompletionToast
	{
		[CmdletBinding()]
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[Parameter(Mandatory)]
			[string]$Title,
			[Parameter(Mandatory)]
			[string]$Body
		)

		if ($Mode -ne 'Run')
		{
			return
		}

		if (-not (Get-Command -Name 'Show-BaselineToast' -CommandType Function -ErrorAction SilentlyContinue))
		{
			return
		}

		if (-not (Get-Command -Name 'Test-BaselineToastRuntimeAvailable' -CommandType Function -ErrorAction SilentlyContinue))
		{
			return
		}

		if (-not (Test-BaselineToastRuntimeAvailable))
		{
			return
		}

		try
		{
			$null = Show-BaselineToast -Title $Title -Body $Body -AppId 'Baseline' -Duration 'Short'
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionOrchestration.RunCompletion.Toast'
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiTweakRunListPrimaryTab
	{
		param ([object]$Tweak)

		if (-not $Tweak)
		{
			return $null
		}

		if (Get-Command -Name 'Resolve-GuiPrimaryTabForTweak' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$primaryTab = Resolve-GuiPrimaryTabForTweak -Tweak $Tweak
			if (-not [string]::IsNullOrWhiteSpace([string]$primaryTab))
			{
				return [string]$primaryTab
			}
		}

		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('Category') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak['Category']))
			{
				return [string]$Tweak['Category']
			}
			return $null
		}

		if ($Tweak.PSObject -and $Tweak.PSObject.Properties['Category'] -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Category))
		{
			return [string]$Tweak.Category
		}

		return $null
	}

	function Test-GuiTweakRunListItemBelongsToUpdates
	{
		param ([object]$Tweak)

		$primaryTab = Get-GuiTweakRunListPrimaryTab -Tweak $Tweak
		return [string]::Equals([string]$primaryTab, 'Updates', [System.StringComparison]::OrdinalIgnoreCase)
	}

	function Test-GuiTweakRunListItemBelongsToGaming
	{
		param ([object]$Tweak)

		$primaryTab = Get-GuiTweakRunListPrimaryTab -Tweak $Tweak
		return [string]::Equals([string]$primaryTab, 'Gaming', [System.StringComparison]::OrdinalIgnoreCase)
	}

	function Select-GuiModeScopedTweakRunList
	{
		param ([object[]]$SelectedTweaks)

		$updatesModeActive = [bool]$Script:UpdatesModeActive
		$gamingModeActive = [bool]$Script:GamingModeActive
		$scopedTweaks = [System.Collections.Generic.List[object]]::new()

		foreach ($selectedTweak in @($SelectedTweaks))
		{
			if (-not $selectedTweak) { continue }

			$isUpdatesTweak = Test-GuiTweakRunListItemBelongsToUpdates -Tweak $selectedTweak
			$isGamingTweak = Test-GuiTweakRunListItemBelongsToGaming -Tweak $selectedTweak
			if (($updatesModeActive -and $isUpdatesTweak) -or ($gamingModeActive -and $isGamingTweak) -or (-not $updatesModeActive -and -not $gamingModeActive -and -not $isUpdatesTweak -and -not $isGamingTweak))
			{
				[void]$scopedTweaks.Add($selectedTweak)
			}
		}

		return $scopedTweaks.ToArray()
	}

	<#
	    .SYNOPSIS
	#>

	function Get-ActiveTweakRunList
	{
		$allSelectedTweaks = @(Get-SelectedTweakRunList)
		$selectedTweaks = @(Select-GuiModeScopedTweakRunList -SelectedTweaks $allSelectedTweaks)
		if ($allSelectedTweaks.Count -ne $selectedTweaks.Count -and (Get-Command -Name 'LogDebug' -CommandType Function -ErrorAction SilentlyContinue))
		{
			$modeName = if ([bool]$Script:GamingModeActive) { 'Gaming' } elseif ([bool]$Script:UpdatesModeActive) { 'Windows Updates' } else { 'Optimize' }
			LogDebug -Message ('Scoped selected tweak run list for {0} mode: kept {1} of {2} selected item(s).' -f $modeName, $selectedTweaks.Count, $allSelectedTweaks.Count)
		}

		if (-not [bool]$Script:GameMode)
		{
			return $selectedTweaks
		}

		$allowlistLookup = @{}
		foreach ($allowlistFunction in @($Script:GameModeAllowlist))
		{
			$allowlistName = [string]$allowlistFunction
			if (-not [string]::IsNullOrWhiteSpace($allowlistName))
			{
				$allowlistLookup[$allowlistName] = $true
			}
		}

		$selectedGameModeScoped = @(
			$selectedTweaks | Where-Object {
				if (-not $_) { return $false }
				$selectedFunction = if ((Test-GuiObjectField -Object $_ -FieldName 'Function')) { [string]$_.Function } else { $null }
				if ([string]::IsNullOrWhiteSpace($selectedFunction)) { return $false }
				return $allowlistLookup.ContainsKey($selectedFunction)
			}
		)

		$gameModePlan = @(Get-GameModePlan)
		if ($gameModePlan.Count -eq 0)
		{
			return $selectedGameModeScoped
		}

		# Merge gaming-scoped manual selections with the active Game Mode plan.
		# If both contain the same function, Game Mode plan entry wins.
		$mergedRunList = [System.Collections.Generic.List[object]]::new()
		$indexByFunction = @{}

		foreach ($selectedEntry in $selectedGameModeScoped)
		{
			if (-not $selectedEntry)
			{
				continue
			}

			[void]$mergedRunList.Add($selectedEntry)

			$selectedFunction = if ((Test-GuiObjectField -Object $selectedEntry -FieldName 'Function')) { [string]$selectedEntry.Function } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($selectedFunction))
			{
				$indexByFunction[$selectedFunction] = $mergedRunList.Count - 1
			}
		}

		foreach ($planEntry in $gameModePlan)
		{
			if (-not $planEntry)
			{
				continue
			}

			$planFunction = if ((Test-GuiObjectField -Object $planEntry -FieldName 'Function')) { [string]$planEntry.Function } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($planFunction) -and $indexByFunction.ContainsKey($planFunction))
			{
				$mergedRunList[[int]$indexByFunction[$planFunction]] = $planEntry
				continue
			}

			[void]$mergedRunList.Add($planEntry)
			if (-not [string]::IsNullOrWhiteSpace($planFunction))
			{
				$indexByFunction[$planFunction] = $mergedRunList.Count - 1
			}
		}

		return @($mergedRunList)
	}

	function Get-GuiScopedRunActionAvailability
	{
		$runInProgress = $false
		if ($Script:TestGuiRunInProgressScript -is [scriptblock])
		{
			$runInProgress = [bool](& $Script:TestGuiRunInProgressScript)
		}
		elseif (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$runInProgress = [bool](Test-GuiRunInProgress)
		}

		$hasScopedSelection = $false
		if (-not [bool]$Script:AppsModeActive -and -not [bool]$Script:DeploymentMediaModeActive)
		{
			$hasScopedSelection = (@(Get-ActiveTweakRunList).Count -gt 0)
		}

		return [pscustomobject]@{
			RunInProgress     = $runInProgress
			HasScopedSelection = $hasScopedSelection
			PreviewEnabled    = ((-not $runInProgress) -and $hasScopedSelection)
			RunEnabled        = ($runInProgress -or $hasScopedSelection)
			MenuRunEnabled    = ((-not $runInProgress) -and $hasScopedSelection)
		}
	}

	function Update-GuiScopedRunActionAvailability
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		try
		{
			$availability = Get-GuiScopedRunActionAvailability
			if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.IsEnabled = [bool]$availability.PreviewEnabled }
			if ($Script:BtnRun) { $Script:BtnRun.IsEnabled = [bool]$availability.RunEnabled }
			if ($Script:MenuActionsPreviewRun) { $Script:MenuActionsPreviewRun.IsEnabled = [bool]$availability.PreviewEnabled }
			if ($Script:MenuActionsRunTweaks) { $Script:MenuActionsRunTweaks.IsEnabled = [bool]$availability.MenuRunEnabled }
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionStateSummary.Update-GuiScopedRunActionAvailability'
			}
			if ($Script:BtnPreviewRun) { $Script:BtnPreviewRun.IsEnabled = $false }
			if ($Script:BtnRun) { $Script:BtnRun.IsEnabled = $false }
			if ($Script:MenuActionsPreviewRun) { $Script:MenuActionsPreviewRun.IsEnabled = $false }
			if ($Script:MenuActionsRunTweaks) { $Script:MenuActionsRunTweaks.IsEnabled = $false }
		}
	}
