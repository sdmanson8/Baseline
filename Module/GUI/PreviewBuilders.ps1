# Preview run list builders, selection summaries, and preview narrative generation

	function Get-SelectedTweakRunList
	{
		param (
			$TweakManifest = $null,
			$Controls = $null
		)
		$resolvedManifest = if ($null -ne $TweakManifest) { $TweakManifest } else { $Script:TweakManifest }
		$resolvedControls = if ($null -ne $Controls) { $Controls } else { $Script:Controls }

		$selectedTweaks = [System.Collections.Generic.List[hashtable]]::new()

		for ($ri = 0; $ri -lt $resolvedManifest.Count; $ri++)
		{
			$rt = $resolvedManifest[$ri]
			$rctl = $resolvedControls[$ri]
			if (-not $rctl -or -not $rctl.IsEnabled) { continue }

			switch ($rt.Type)
			{
				'Toggle'
				{
					$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$rt.Function)
					$selectedParam = $null
					$selectedState = $null
					$isChecked = $false

					if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Toggle')
					{
						$selectedState = if ([string]$explicitSelection.State -eq 'Off') { 'Off' } else { 'On' }
						$selectedParam = if ($selectedState -eq 'Off') { [string]$rt.OffParam } else { [string]$rt.OnParam }
						$isChecked = ($selectedState -eq 'On')
					}
					elseif ($rctl.IsChecked)
					{
						$selectedState = 'On'
						$selectedParam = [string]$rt.OnParam
						$isChecked = [bool]$rctl.IsChecked
					}

					if (-not [string]::IsNullOrWhiteSpace([string]$selectedParam))
					{
						$visual = Get-TweakVisualMetadata -Tweak $rt -StateSource $rctl
						$selectedTweaks.Add(@{
							Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Toggle'
							TypeKind  = [string]$visual.TypeKind
							TypeLabel = [string]$visual.TypeLabel
							TypeTone  = [string]$visual.TypeTone
							TypeBadgeLabel = [string]$visual.TypeBadgeLabel
							Category  = $rt.Category
							Risk      = $rt.Risk
							Restorable = $rt.Restorable
							RecoveryLevel = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
							RequiresRestart = [bool]$rt.RequiresRestart
							Impact    = $rt.Impact
							PresetTier = $rt.PresetTier
							Selection = [string]$selectedParam
							ToggleParam = [string]$selectedParam
							OnParam   = [string]$rt.OnParam
							OffParam  = [string]$rt.OffParam
							IsChecked = [bool]$isChecked
							DefaultValue = [bool]$rt.Default
							CurrentState = [string]$visual.StateLabel
							CurrentStateTone = [string]$visual.StateTone
							StateDetail = [string]$visual.StateDetail
							MatchesDesired = [bool]$visual.MatchesDesired
							ScenarioTags = @($visual.ScenarioTags)
							ReasonIncluded = [string]$visual.ReasonIncluded
							BlastRadius = [string]$visual.BlastRadius
							IsRemoval = [bool]$visual.IsRemoval
							ExtraArgs = $null
							GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
							TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
						})
					}
				}
				'Choice'
				{
					$explicitChoiceSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$rt.Function)
					$selIdx = -1
					if ($explicitChoiceSelection -and [string]$explicitChoiceSelection.Type -eq 'Choice' -and -not [string]::IsNullOrWhiteSpace([string]$explicitChoiceSelection.Value))
					{
						$choiceOpts = if ($rt.Options) { [object[]]@($rt.Options) } else { [object[]]@() }
						$explicitIdx = [array]::IndexOf($choiceOpts, [string]$explicitChoiceSelection.Value)
						if ($explicitIdx -ge 0 -and $explicitIdx -lt $choiceOpts.Count)
						{
							$selIdx = $explicitIdx
						}
					}
					if ($selIdx -lt 0)
					{
						$selIdx = $rctl.SelectedIndex
					}
					if ($selIdx -ge 0)
					{
						$visual = Get-TweakVisualMetadata -Tweak $rt -StateSource $rctl
						$displayOpts = if ($rt.DisplayOptions) { $rt.DisplayOptions } else { $rt.Options }
						$selectedTweaks.Add(@{
							Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Choice'
							TypeKind  = [string]$visual.TypeKind
							TypeLabel = [string]$visual.TypeLabel
							TypeTone  = [string]$visual.TypeTone
							TypeBadgeLabel = [string]$visual.TypeBadgeLabel
							Category  = $rt.Category
							Risk      = $rt.Risk
							Restorable = $rt.Restorable
							RecoveryLevel = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
							RequiresRestart = [bool]$rt.RequiresRestart
							Impact    = $rt.Impact
							PresetTier = $rt.PresetTier
							Selection = [string]$displayOpts[$selIdx]
							Value     = $rt.Options[$selIdx]
							SelectedIndex = [int]$selIdx
							SelectedValue = [string]$displayOpts[$selIdx]
							DefaultIndex = $(if ($rt.Options) { [array]::IndexOf(@($rt.Options), $rt.Default) } else { -1 })
							DefaultValue = $(if ((Test-GuiObjectField -Object $rt -FieldName 'Default')) { [string]$rt.Default } else { $null })
							CurrentState = [string]$visual.StateLabel
							CurrentStateTone = [string]$visual.StateTone
							StateDetail = [string]$visual.StateDetail
							MatchesDesired = [bool]$visual.MatchesDesired
							ScenarioTags = @($visual.ScenarioTags)
							ReasonIncluded = [string]$visual.ReasonIncluded
							BlastRadius = [string]$visual.BlastRadius
							IsRemoval = [bool]$visual.IsRemoval
							ExtraArgs = $rt.ExtraArgs
							GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
							TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
						})
					}
				}
				'Action'
				{
					if ($rctl.IsChecked)
					{
						$visual = Get-TweakVisualMetadata -Tweak $rt -StateSource $rctl
						$selectedTweaks.Add(@{
							Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Action'
							TypeKind  = [string]$visual.TypeKind
							TypeLabel = [string]$visual.TypeLabel
							TypeTone  = [string]$visual.TypeTone
							TypeBadgeLabel = [string]$visual.TypeBadgeLabel
							Category  = $rt.Category
							Risk      = $rt.Risk
							Restorable = $rt.Restorable
							RecoveryLevel = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
							RequiresRestart = [bool]$rt.RequiresRestart
							Impact    = $rt.Impact
							PresetTier = $rt.PresetTier
							Selection = if ($rt.Name) { [string]$rt.Name } else { 'Run action' }
							IsChecked = [bool]$rctl.IsChecked
							CurrentState = [string]$visual.StateLabel
							CurrentStateTone = [string]$visual.StateTone
							StateDetail = [string]$visual.StateDetail
							MatchesDesired = [bool]$visual.MatchesDesired
							ScenarioTags = @($visual.ScenarioTags)
							ReasonIncluded = [string]$visual.ReasonIncluded
							BlastRadius = [string]$visual.BlastRadius
							IsRemoval = [bool]$visual.IsRemoval
							ExtraArgs = $rt.ExtraArgs
							GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
							TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
						})
					}
				}
			}
		}

		return $selectedTweaks
	}

	function Get-WindowsDefaultRunList
	{
		param (
			$TweakManifest = $null,
			$Controls = $null
		)
		$resolvedManifest = if ($null -ne $TweakManifest) { $TweakManifest } else { $Script:TweakManifest }
		$resolvedControls = if ($null -ne $Controls) { $Controls } else { $Script:Controls }

		$defaultTweaks = [System.Collections.Generic.List[hashtable]]::new()

		for ($ri = 0; $ri -lt $resolvedManifest.Count; $ri++)
		{
			$rt = $resolvedManifest[$ri]
			$rctl = $resolvedControls[$ri]
			if (-not $rctl) { continue }
			if ($null -ne $rt.Restorable -and -not $rt.Restorable) { continue }

			switch ($rt.Type)
			{
				'Toggle'
				{
					$visual = Get-TweakVisualMetadata -Tweak $rt
					$defaultParam = if ([bool]$rt.WinDefault) { $rt.OnParam } else { $rt.OffParam }
					if ([string]::IsNullOrWhiteSpace([string]$defaultParam)) { continue }

					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Toggle'
						TypeKind        = [string]$visual.TypeKind
						TypeLabel       = [string]$visual.TypeLabel
						TypeTone        = [string]$visual.TypeTone
						TypeBadgeLabel  = [string]$visual.TypeBadgeLabel
						Category        = $rt.Category
						Risk            = $rt.Risk
						Restorable      = $rt.Restorable
						RecoveryLevel   = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
						RequiresRestart = [bool]$rt.RequiresRestart
						Impact          = $rt.Impact
						PresetTier      = $rt.PresetTier
						Selection       = if ([bool]$rt.WinDefault) { 'Windows default: Enabled' } else { 'Windows default: Disabled' }
						ToggleParam     = $defaultParam
						OnParam         = [string]$rt.OnParam
						OffParam        = [string]$rt.OffParam
						WinDefault      = [bool]$rt.WinDefault
						IsChecked       = [bool]$rt.WinDefault
						DefaultValue    = [bool]$rt.Default
						CurrentState    = 'Windows default'
						CurrentStateTone = 'Primary'
						StateDetail     = 'This run restores Windows default toggle behavior where possible.'
						MatchesDesired  = $false
						ScenarioTags    = @($visual.ScenarioTags)
						ReasonIncluded  = 'Included because this run restores the Windows default toggle behavior where possible.'
						BlastRadius     = [string]$visual.BlastRadius
						IsRemoval       = [bool]$visual.IsRemoval
						ExtraArgs       = $null
						GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
						TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
					})
				}
				'Choice'
				{
					$visual = Get-TweakVisualMetadata -Tweak $rt
					if ([string]::IsNullOrWhiteSpace([string]$rt.WinDefault)) { continue }
					$defaultIndex = [array]::IndexOf($rt.Options, $rt.WinDefault)
					if ($defaultIndex -lt 0) { continue }

					$displayOpts = if ($rt.DisplayOptions) { $rt.DisplayOptions } else { $rt.Options }
					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Choice'
						TypeKind        = [string]$visual.TypeKind
						TypeLabel       = [string]$visual.TypeLabel
						TypeTone        = [string]$visual.TypeTone
						TypeBadgeLabel  = [string]$visual.TypeBadgeLabel
						Category        = $rt.Category
						Risk            = $rt.Risk
						Restorable      = $rt.Restorable
						RecoveryLevel   = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
						RequiresRestart = [bool]$rt.RequiresRestart
						Impact          = $rt.Impact
						PresetTier      = $rt.PresetTier
						Selection       = "Windows default: $([string]$displayOpts[$defaultIndex])"
						Value           = $rt.Options[$defaultIndex]
						WinDefault      = [string]$rt.WinDefault
						WinDefaultIndex = $defaultIndex
						DefaultValue    = $(if ((Test-GuiObjectField -Object $rt -FieldName 'Default')) { [string]$rt.Default } else { $null })
						CurrentState    = 'Windows default'
						CurrentStateTone = 'Primary'
						StateDetail     = 'This run restores the Windows default choice where possible.'
						MatchesDesired  = $false
						ScenarioTags    = @($visual.ScenarioTags)
						ReasonIncluded  = 'Included because this run restores the Windows default choice where possible.'
						BlastRadius     = [string]$visual.BlastRadius
						IsRemoval       = [bool]$visual.IsRemoval
						ExtraArgs       = $rt.ExtraArgs
						GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
						TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
					})
				}
				'Action'
				{
					if (-not $rt.WinDefault) { continue }
					$visual = Get-TweakVisualMetadata -Tweak $rt

					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Action'
						TypeKind        = [string]$visual.TypeKind
						TypeLabel       = [string]$visual.TypeLabel
						TypeTone        = [string]$visual.TypeTone
						TypeBadgeLabel  = [string]$visual.TypeBadgeLabel
						Category        = $rt.Category
						Risk            = $rt.Risk
						Restorable      = $rt.Restorable
						RecoveryLevel   = if ((Test-GuiObjectField -Object $rt -FieldName 'RecoveryLevel')) { [string]$rt.RecoveryLevel } else { $null }
						RequiresRestart = [bool]$rt.RequiresRestart
						Impact          = $rt.Impact
						PresetTier      = $rt.PresetTier
						Selection       = 'Run Windows default action'
						WinDefault      = [bool]$rt.WinDefault
						CurrentState    = 'Windows default'
						CurrentStateTone = 'Primary'
						StateDetail     = 'This run restores the default action flow.'
						MatchesDesired  = $false
						ScenarioTags    = @($visual.ScenarioTags)
						ReasonIncluded  = 'Included because this run restores the default action flow.'
						BlastRadius     = [string]$visual.BlastRadius
						IsRemoval       = [bool]$visual.IsRemoval
						ExtraArgs       = $rt.ExtraArgs
						GamingPreviewGroup = if ((Test-GuiObjectField -Object $rt -FieldName 'GamingPreviewGroup')) { [string]$rt.GamingPreviewGroup } else { $null }
						TroubleshootingOnly = if ((Test-GuiObjectField -Object $rt -FieldName 'TroubleshootingOnly')) { [bool]$rt.TroubleshootingOnly } else { $false }
					})
				}
			}
		}

		return $defaultTweaks
	}

	function Get-TweakSelectionSummary
	{
		param ([object[]]$SelectedTweaks)

		$selected = @($SelectedTweaks | Where-Object { $_ })
		$categorySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		$mediumRiskCount = 0
		$highRiskCount = 0
		$advancedTierCount = 0
		$restartRequiredCount = 0
		$notFullyRestorableCount = 0
		$directUndoEligibleCount = 0
		$restorePointRecoveryCount = 0
		$manualRecoveryCount = 0
		$defaultsOnlyRecoveryCount = 0

		foreach ($tweak in $selected)
		{
			$risk = if (Test-GuiObjectField -Object $tweak -FieldName 'Risk') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Risk') } else { $null }
			if ($risk -eq 'Medium')
			{
				$mediumRiskCount++
			}
			elseif ($risk -eq 'High')
			{
				$highRiskCount++
			}

			$presetTier = if (Test-GuiObjectField -Object $tweak -FieldName 'PresetTier') { [string](Get-GuiObjectField -Object $tweak -FieldName 'PresetTier') } else { $null }
			if ($presetTier -eq 'Advanced')
			{
				$advancedTierCount++
			}

			if ((Test-GuiObjectField -Object $tweak -FieldName 'RequiresRestart') -and [bool](Get-GuiObjectField -Object $tweak -FieldName 'RequiresRestart'))
			{
				$restartRequiredCount++
			}

			$hasRestorable = Test-GuiObjectField -Object $tweak -FieldName 'Restorable'
			$restorable = if ($hasRestorable) { Get-GuiObjectField -Object $tweak -FieldName 'Restorable' } else { $null }
			if ($hasRestorable -and $null -ne $restorable -and -not [bool]$restorable)
			{
				$notFullyRestorableCount++
			}

			$recoveryLevel = if (Test-GuiObjectField -Object $tweak -FieldName 'RecoveryLevel') { [string](Get-GuiObjectField -Object $tweak -FieldName 'RecoveryLevel') } else { $null }
			if ($hasRestorable -and [bool]$restorable -and $recoveryLevel -eq 'Direct')
			{
				$directUndoEligibleCount++
			}
			switch ($recoveryLevel)
			{
				'RestorePoint' { $restorePointRecoveryCount++ }
				'Manual' { $manualRecoveryCount++ }
				'DefaultsOnly' { $defaultsOnlyRecoveryCount++ }
			}

			$category = if (Test-GuiObjectField -Object $tweak -FieldName 'Category') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Category') } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($category))
			{
				[void]$categorySet.Add($category)
			}
		}

		$categories = @($categorySet) | Sort-Object
		$categoryText = if ($categories.Count -eq 0)
		{
			'None'
		}
		elseif ($categories.Count -le 3)
		{
			$categories -join ', '
		}
		else
		{
			('{0} +{1} more' -f (($categories | Select-Object -First 3) -join ', '), ($categories.Count - 3))
		}

		$riskLevel = 'Low'
		if ($highRiskCount -gt 0 -or $notFullyRestorableCount -gt 0)
		{
			$riskLevel = 'High'
		}
		elseif ($mediumRiskCount -gt 0)
		{
			$riskLevel = 'Medium'
		}

		$restoreGuidance = Test-ShouldRecommendRestorePoint -SelectedTweaks $selected
		$restoreRecommendation = if ($restoreGuidance.ShouldRecommend)
		{
			[string]$restoreGuidance.Message
		}
		else
		{
			switch ($riskLevel)
			{
				'High'   { 'Restore point recommended before continuing.'; break }
				'Medium' { 'Restore point recommended before continuing.'; break }
				default  { $null }
			}
		}
		if ($manualRecoveryCount -gt 0 -and [string]::IsNullOrWhiteSpace([string]$restoreRecommendation))
		{
			$restoreRecommendation = 'Some selected items rely on manual recovery steps. Review the preview carefully before continuing.'
		}

		return [pscustomobject]@{
			SelectedCount = $selected.Count
			MediumRiskCount = $mediumRiskCount
			HighRiskCount = $highRiskCount
			AdvancedTierCount = $advancedTierCount
			RestartRequiredCount = $restartRequiredCount
			NotFullyRestorableCount = $notFullyRestorableCount
			DirectUndoEligibleCount = $directUndoEligibleCount
			RestorePointRecoveryCount = $restorePointRecoveryCount
			ManualRecoveryCount = $manualRecoveryCount
			DefaultsOnlyRecoveryCount = $defaultsOnlyRecoveryCount
			Categories = $categories
			CategoryText = $categoryText
			RiskLevel = $riskLevel
			ShouldRecommendRestorePoint = [bool]$restoreGuidance.ShouldRecommend
			RestoreRecommendationSeverity = [string]$restoreGuidance.Severity
			RestoreRecommendationReasons = @($restoreGuidance.Reasons)
			RestoreRecommendation = $restoreRecommendation
		}
	}

	function Show-SelectedTweakPreview
	{
		param (
			[object[]]$SelectedTweaks,
			[switch]$AllowApply
		)

		$selected = @($SelectedTweaks | Where-Object { $_ })
		if ($selected.Count -eq 0)
		{
			$okLabel = Get-UxLocalizedString -Key 'GuiBtnOk' -Fallback 'OK'
			$emptyMessage = if ([bool]$Script:GameMode) {
				(Get-UxLocalizedString -Key 'GuiPreviewEmptyMessageGameMode' -Fallback 'Choose a Game Mode profile before previewing the gaming workflow.')
			}
			else {
				(Get-UxLocalizedString -Key 'GuiPreviewEmptyMessage' -Fallback 'Select at least one tweak before previewing a run.')
			}
			Show-ThemedDialog -Title $(if ([bool]$Script:GameMode) { (Get-UxLocalizedString -Key 'GuiPreviewGameMode' -Fallback 'Preview Game Mode') } else { (Get-UxPreviewButtonLabel) }) `
				-Message $emptyMessage `
				-Buttons @($okLabel) `
				-AccentButton $okLabel
			return
		}

		$gameModePreview = ([bool]$Script:GameMode -and @($selected | Where-Object { (Test-GuiObjectField -Object $_ -FieldName 'FromGameMode') -and [bool]$_.FromGameMode }).Count -gt 0)

		# Show wait cursor while computing the preview to signal responsiveness.
		$previousCursor = $null
		try
		{
			if ($Script:Form) { $previousCursor = $Script:Form.Cursor; $Script:Form.Cursor = [System.Windows.Input.Cursors]::Wait }
			[System.Windows.Input.Mouse]::UpdateCursor()
		}
		catch { <# non-fatal #> }

		# Track this preview run in session statistics
		Add-SessionStatistic -Name 'PreviewRunCount'

		$summary = Get-TweakSelectionSummary -SelectedTweaks $selected
		$previewResults = @(Get-ExecutionPreviewResults -SelectedTweaks $selected)
		$previewActionLabel = Get-UxPreviewButtonLabel
		try
		{
			Set-LogMode -Mode $(if ($gameModePreview) { 'Game' } else { $null })
			Write-ExecutionPreviewToLog -Results $previewResults
		}
		finally
		{
			Clear-LogMode
		}
		$alreadyDesiredCount = @($previewResults | Where-Object Status -eq 'Already in desired state').Count
		$willChangeCount = @($previewResults | Where-Object Status -eq 'Will change').Count
		$requiresRestartCount = @($previewResults | Where-Object Status -eq 'Requires restart').Count
		$highRiskPreviewCount = @($previewResults | Where-Object Status -eq 'High-risk changes').Count
		$notFullyRestorablePreviewCount = @($previewResults | Where-Object Status -eq 'Not fully restorable').Count
		$advancedTierCount = if ((Test-GuiObjectField -Object $summary -FieldName 'AdvancedTierCount')) { [int]$summary.AdvancedTierCount } else { 0 }

		$summaryCards = @(Get-UxPreviewSummaryCards `
			-Summary $summary `
			-AlreadyDesiredCount $alreadyDesiredCount `
			-WillChangeCount $willChangeCount `
			-HighRiskPreviewCount $highRiskPreviewCount `
			-RequiresRestartCount $requiresRestartCount `
			-NotFullyRestorablePreviewCount $notFullyRestorablePreviewCount `
			-AdvancedTierCount $advancedTierCount)

		$summaryParts = @(Get-UxPreviewSummaryParts `
			-Summary $summary `
			-IsGameModePreview $gameModePreview `
			-AlreadyDesiredCount $alreadyDesiredCount `
			-WillChangeCount $willChangeCount `
			-RequiresRestartCount $requiresRestartCount `
			-NotFullyRestorablePreviewCount $notFullyRestorablePreviewCount `
			-AdvancedTierCount $advancedTierCount `
			-SelectedTweaks $selected)

		$displayResults = @(Get-LocalizedPreviewResults -Results $previewResults)
		$viewChangesLabel = Get-UxLocalizedString -Key 'GuiBtnViewChanges' -Fallback 'View Changes'
		$cancelLabel = Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
		$previewButtons = if ($AllowApply) {
			$applyLabel = Get-UxRunActionLabel
			@($viewChangesLabel, $cancelLabel, $applyLabel)
		}
		else {
			@($viewChangesLabel, $closeLabel)
		}
		# Restore cursor before showing the modal dialog.
		try
		{
			if ($Script:Form) { $Script:Form.Cursor = $previousCursor }
			[System.Windows.Input.Mouse]::UpdateCursor()
		}
		catch { <# non-fatal #> }

		$previewDialogResult = $null
		do
		{
			$previewDialogResult = Show-ExecutionSummaryDialog -Title $(if ($gameModePreview) { (Get-UxLocalizedString -Key 'GuiPreviewGameMode' -Fallback 'Preview Game Mode') } else { $previewActionLabel }) `
				-SummaryText ($summaryParts -join ' ') `
				-SummaryCards $summaryCards `
				-Results $displayResults `
				-LogPath $Global:LogFilePath `
				-Buttons $previewButtons

			if ($previewDialogResult -eq $viewChangesLabel)
			{
				Show-DiffViewFromSelection -SelectedTweaks $selected
			}
		}
		while ($previewDialogResult -eq $viewChangesLabel)

		if ($AllowApply)
		{
			return $previewDialogResult
		}
		$previewStatusText = if ($gameModePreview) {
			"Previewed Game Mode ($($Script:GameModeProfile)) with $($summary.SelectedCount) action$(if ($summary.SelectedCount -eq 1) { '' } else { 's' }). No changes were applied."
		}
		else {
			"$previewActionLabel completed for $($summary.SelectedCount) tweak$(if ($summary.SelectedCount -eq 1) { '' } else { 's' }). No changes were applied."
		}
		Set-GuiStatusText -Text $previewStatusText -Tone 'accent'
	}

	function Get-LocalizedPreviewResults
	{
		param ([object[]]$Results)

		$statusLabelMap = @{
			'Already in desired state' = (Get-UxLocalizedString -Key 'GuiPreviewStatusAlreadySet' -Fallback 'Already set')
			'Will change' = (Get-UxLocalizedString -Key 'GuiPreviewStatusWillChange' -Fallback 'Will change')
			'Requires restart' = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestartRequired' -Fallback 'Restart required')
			'High-risk changes' = (Get-UxLocalizedString -Key 'GuiPreviewStatusHighRisk' -Fallback 'High risk')
			'Not fully restorable' = (Get-UxLocalizedString -Key 'GuiPreviewStatusManualRecovery' -Fallback 'Manual recovery')
			'Preview' = (Get-UxPreviewButtonLabel)
		}

		$displayResults = New-Object System.Collections.ArrayList
		foreach ($result in @($Results))
		{
			if ($null -eq $result) { continue }

			$displayResult = [pscustomobject]@{}
			foreach ($property in $result.PSObject.Properties)
			{
				$displayResult | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
			}

			$displayStatus = [string]$result.Status
			if ($statusLabelMap.ContainsKey($displayStatus))
			{
				$displayStatus = [string]$statusLabelMap[$displayStatus]
			}
			$displayResult.Status = $displayStatus

			$displayGroupHeader = if ((Test-GuiObjectField -Object $result -FieldName 'PreviewGroupHeader')) { [string]$result.PreviewGroupHeader } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($displayGroupHeader) -and $statusLabelMap.ContainsKey($displayGroupHeader))
			{
				$displayResult.PreviewGroupHeader = [string]$statusLabelMap[$displayGroupHeader]
			}

			[void]$displayResults.Add($displayResult)
		}

		return @($displayResults)
	}

	function Confirm-HighRiskTweakRun
	{
		param ([object[]]$SelectedTweaks)

		$summary = Get-TweakSelectionSummary -SelectedTweaks $SelectedTweaks
		if ($summary.SelectedCount -eq 0)
		{
			return $null
		}

		$isGameModeRun = ([bool]$Script:GameMode -and @($SelectedTweaks | Where-Object { (Test-GuiObjectField -Object $_ -FieldName 'FromGameMode') -and [bool]$_.FromGameMode }).Count -gt 0)
		$advancedTierCount = if ((Test-GuiObjectField -Object $summary -FieldName 'AdvancedTierCount')) { [int]$summary.AdvancedTierCount } else { 0 }
		# Low-risk runs with no restore-point recommendation skip the dialog entirely.
		if ($summary.RiskLevel -eq 'Low' -and -not $summary.ShouldRecommendRestorePoint -and -not $isGameModeRun -and $advancedTierCount -eq 0)
		{
			# Safe Mode: require mandatory preview before any apply
			if (Test-IsSafeModeUX)
			{
				return 'PreviewRequired'
			}
			return 'Continue Anyway'
		}

		# Expert Mode: skip medium-risk confirmation when no high-risk/advanced/restore-point flags
		if (Test-UxShouldSkipLowRiskConfirmation -Summary $summary -AdvancedTierCount $advancedTierCount)
		{
			return 'Continue Anyway'
		}

		$runPathContext = Get-UxRunPathContext
		$title = if ($isGameModeRun) {
			'Game Mode Run Review'
		}
		elseif ($runPathContext.Path -eq 'Troubleshooting') {
			'Troubleshooting Run Review'
		}
		elseif ($summary.RiskLevel -eq 'High' -or $advancedTierCount -gt 0) {
			if ($runPathContext.Path -eq 'Preset') { "$($runPathContext.Label) Preset Warning" } else { 'Advanced Selection Warning' }
		}
		elseif (Test-IsSafeModeUX) {
			'Review Before Running'
		}
		elseif ($runPathContext.Path -eq 'Preset') {
			"$($runPathContext.Label) Preset Review"
		}
		elseif ($runPathContext.Path -eq 'Manual') {
			'Custom Selection Review'
		}
		else {
			'Run Review'
		}

		# Build summary cards - Safe Mode gets a smaller set
		if (Test-IsSafeModeUX)
		{
			$summaryCards = @(
				[pscustomobject]@{
					Label = 'Selected'
					Value = $summary.SelectedCount
					Detail = 'Tweaks in this run'
					Tone = 'Primary'
				}
			)
			if ($summary.HighRiskCount -gt 0)
			{
				$summaryCards += [pscustomobject]@{
					Label = 'High risk'
					Value = $summary.HighRiskCount
					Detail = 'May affect how some apps work'
					Tone = 'Danger'
				}
			}
			if ($summary.RestartRequiredCount -gt 0)
			{
				$summaryCards += [pscustomobject]@{
					Label = 'Restart'
					Value = $summary.RestartRequiredCount
					Detail = 'May need a reboot'
					Tone = 'Caution'
				}
			}
			$summaryCards += [pscustomobject]@{
				Label = 'Restore point'
				Value = $(if ($summary.ShouldRecommendRestorePoint) { 'Yes' } else { 'No' })
				Detail = $(if ($summary.ShouldRecommendRestorePoint) { [string]$summary.RestoreRecommendation } else { 'Not needed for this run.' })
				Tone = $(if ($summary.ShouldRecommendRestorePoint) { if ($summary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
			}
		}
		else
		{
			$summaryCards = @(
				[pscustomobject]@{
					Label = 'Selected'
					Value = $summary.SelectedCount
					Detail = 'Tweaks in this run'
					Tone = 'Primary'
				}
				[pscustomobject]@{
					Label = 'Medium risk'
					Value = $summary.MediumRiskCount
					Detail = 'Moderate tradeoffs'
					Tone = 'Caution'
				}
				[pscustomobject]@{
					Label = 'High risk'
					Value = $summary.HighRiskCount
					Detail = 'Harder to undo'
					Tone = 'Danger'
				}
				[pscustomobject]@{
					Label = 'Restart required'
					Value = $summary.RestartRequiredCount
					Detail = 'Needs a reboot'
					Tone = 'Muted'
				}
				[pscustomobject]@{
					Label = 'Reversible here'
					Value = $summary.DirectUndoEligibleCount
					Detail = 'Can be rolled back in-app'
					Tone = 'Success'
				}
				[pscustomobject]@{
					Label = 'Manual recovery'
					Value = $summary.NotFullyRestorableCount
					Detail = 'One-way or partial rollback'
					Tone = 'Danger'
				}
				[pscustomobject]@{
					Label = 'Restore point'
					Value = $(if ($summary.ShouldRecommendRestorePoint) { 'Yes' } else { 'No' })
					Detail = $(if ($summary.ShouldRecommendRestorePoint) { [string]$summary.RestoreRecommendation } else { 'Not recommended for this run.' })
					Tone = $(if ($summary.ShouldRecommendRestorePoint) { if ($summary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
				}
				[pscustomobject]@{
					Label = 'Categories'
					Value = $summary.Categories.Count
					Detail = $summary.CategoryText
					Tone = 'Muted'
				}
			)
			if ($advancedTierCount -gt 0)
			{
				$summaryCards += [pscustomobject]@{
					Label = 'Advanced tier'
					Value = $advancedTierCount
					Detail = 'Expert-only changes'
					Tone = 'Danger'
				}
			}
		}

		$messageParts = @(Get-UxConfirmationMessage -Summary $summary -IsGameModeRun $isGameModeRun -AdvancedTierCount $advancedTierCount)
		$previewActionLabel = Get-UxPreviewButtonLabel

		return (Show-RiskDecisionDialog -Title $title `
			-Message ($messageParts -join "`n`n") `
			-SummaryCards $summaryCards `
			-Buttons @('Cancel', 'Create Restore Point', $previewActionLabel, 'Continue Anyway') `
			-AccentButton 'Create Restore Point' `
			-DestructiveButton 'Continue Anyway')
	}

	function Get-ExecutionPreviewResults
	{
		param ([object[]]$SelectedTweaks)

		function Get-TweakPreviewNarrative
		{
			param (
				[object]$Tweak,
				[object]$Visual
			)

			$detailParts = New-Object System.Collections.Generic.List[string]
			$whyThisMatters = if ((Test-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) {
				[string]$Tweak.WhyThisMatters
			}
			elseif ((Test-GuiObjectField -Object $Tweak -FieldName 'Detail') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Detail)) {
				[string]$Tweak.Detail
			}
			else {
				$null
			}

			switch ([string]$Tweak.Type)
			{
				'Toggle'
				{
					$selectedIsOn = $false
					$tweakToggleParam = if (Test-GuiObjectField -Object $Tweak -FieldName 'ToggleParam') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'ToggleParam') } else { $null }
					$tweakIsChecked = if (Test-GuiObjectField -Object $Tweak -FieldName 'IsChecked') { Get-GuiObjectField -Object $Tweak -FieldName 'IsChecked' } else { $null }
					$tweakDefault = if (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { Get-GuiObjectField -Object $Tweak -FieldName 'Default' } else { $null }

					if (-not [string]::IsNullOrWhiteSpace($tweakToggleParam)) {
						$selectedIsOn = ($tweakToggleParam -eq [string]$Tweak.OnParam)
					} elseif ($null -ne $tweakIsChecked) {
						$selectedIsOn = [bool]$tweakIsChecked
					} elseif ($null -ne $tweakDefault) {
						$selectedIsOn = [bool]$tweakDefault
					}

					$stateWord = if ($selectedIsOn) { 'enabled' } else { 'disabled' }
					$matchesWindowsDefault = $null
					if ((Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault') -and $null -ne $Tweak.WinDefault)
					{
						$matchesWindowsDefault = ([bool]$selectedIsOn -eq [bool]$Tweak.WinDefault)
					}

					[void]$detailParts.Add($(if ($matchesWindowsDefault -eq $true) {
						"{0} will remain {1}." -f [string]$Tweak.Name, $stateWord
					}
					else {
						"{0} will be {1}." -f [string]$Tweak.Name, $stateWord
					}))

					if ((Test-GuiObjectField -Object $Tweak -FieldName 'WinDefaultDesc') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WinDefaultDesc))
					{
						[void]$detailParts.Add(("Windows default: {0}." -f ([string]$Tweak.WinDefaultDesc).TrimEnd('.')))
					}
				}
				'Choice'
				{
					$selectionLabel = if (-not [string]::IsNullOrWhiteSpace([string]$Tweak.Selection)) { [string]$Tweak.Selection } else { 'the selected option' }
					[void]$detailParts.Add(("{0} will be set to {1}." -f [string]$Tweak.Name, $selectionLabel))
				}
				'Action'
				{
					[void]$detailParts.Add(("{0} will run once during the real run." -f [string]$Tweak.Name))
				}
				default
				{
					if (-not [string]::IsNullOrWhiteSpace([string]$Tweak.Selection))
					{
						[void]$detailParts.Add(("{0} will apply {1}." -f [string]$Tweak.Name, [string]$Tweak.Selection))
					}
				}
			}

			if (-not [string]::IsNullOrWhiteSpace($whyThisMatters))
			{
				[void]$detailParts.Add($whyThisMatters)
			}
			elseif (-not [string]::IsNullOrWhiteSpace([string]$Visual.StateDetail))
			{
				[void]$detailParts.Add([string]$Visual.StateDetail)
			}

			if ((Test-GuiObjectField -Object $Tweak -FieldName 'FromGameMode') -and [bool]$Tweak.FromGameMode -and [bool]$Tweak.RequiresRestart -and (Test-GuiObjectField -Object $Tweak -FieldName 'GamingPreviewGroup') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.GamingPreviewGroup))
			{
				[void]$detailParts.Add(("Primary bucket: {0}." -f [string]$Tweak.GamingPreviewGroup))
			}

			if ([bool]$Tweak.RequiresRestart)
			{
				[void]$detailParts.Add('Restart required after running.')
			}
			if ([string]$Tweak.Risk -eq 'High')
			{
				[void]$detailParts.Add('This change may affect compatibility with some apps or games.')
			}
			if ((Test-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly') -and [bool]$Tweak.TroubleshootingOnly)
			{
				[void]$detailParts.Add('Use this only for troubleshooting compatibility, overlay, or display problems.')
			}
			if ((Test-GuiObjectField -Object $Tweak -FieldName 'Restorable') -and $null -ne $Tweak.Restorable -and -not [bool]$Tweak.Restorable)
			{
				[void]$detailParts.Add('This change cannot be automatically undone. Make sure you are comfortable before proceeding.')
			}
			if ((Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.RecoveryLevel))
			{
				[void]$detailParts.Add(("Recovery path: {0}." -f [string]$Tweak.RecoveryLevel))
			}

			return (@($detailParts) -join ' ')
		}

		$previewResults = New-Object System.Collections.ArrayList
		$order = 0
		foreach ($tweak in @($SelectedTweaks))
		{
			$order++
			# Use the tweak entry itself as the state source. For Game Mode plan
			# entries this ensures the preview reflects the plan's ToggleParam
			# even when the GUI control has not been synced yet.  For regular
			# entries the selected-tweak hashtable already carries IsChecked /
			# SelectedIndex, so the result is the same.
			$stateSource = $tweak
			$visual = Get-TweakVisualMetadata -Tweak $tweak -StateSource $stateSource
			$previewStatus = if ($visual.MatchesDesired -and $visual.TypeKind -ne 'Action')
			{
				'Already in desired state'
			}
			elseif ($visual.IsRemoval -or [string]$tweak.Risk -eq 'High')
			{
				'High-risk changes'
			}
			elseif ((Test-GuiObjectField -Object $tweak -FieldName 'Restorable') -and $null -ne $tweak.Restorable -and -not [bool]$tweak.Restorable)
			{
				'Not fully restorable'
			}
			elseif ([bool]$tweak.RequiresRestart)
			{
				'Requires restart'
			}
			else
			{
				'Will change'
			}
			$previewSection = Get-GameModePreviewSectionInfo -Tweak $tweak
			$detailText = Get-TweakPreviewNarrative -Tweak $tweak -Visual $visual

			[void]$previewResults.Add([PSCustomObject]@{
				Key             = [string]$tweak.Key
				Order           = $order
				Name            = [string]$tweak.Name
				Category        = [string]$tweak.Category
				Risk            = [string]$tweak.Risk
				Type            = [string]$tweak.Type
				TypeKind        = [string]$visual.TypeKind
				TypeLabel       = [string]$visual.TypeLabel
				TypeBadgeLabel  = [string]$visual.TypeBadgeLabel
				TypeTone        = [string]$visual.TypeTone
				Selection       = [string]$tweak.Selection
				CurrentState    = [string]$visual.StateLabel
				CurrentStateTone = [string]$visual.StateTone
				StateDetail     = [string]$visual.StateDetail
				MatchesDesired  = [bool]$visual.MatchesDesired
				ScenarioTags    = @($visual.ScenarioTags)
				ReasonIncluded  = [string]$visual.ReasonIncluded
				BlastRadius     = [string]$visual.BlastRadius
				IsRemoval       = [bool]$visual.IsRemoval
				RequiresRestart = [bool]$tweak.RequiresRestart
				Restorable      = $tweak.Restorable
				RecoveryLevel   = if ((Test-GuiObjectField -Object $tweak -FieldName 'RecoveryLevel')) { [string]$tweak.RecoveryLevel } else { $null }
				GamingPreviewGroup = if ((Test-GuiObjectField -Object $tweak -FieldName 'GamingPreviewGroup')) { [string]$tweak.GamingPreviewGroup } else { $null }
				TroubleshootingOnly = if ((Test-GuiObjectField -Object $tweak -FieldName 'TroubleshootingOnly')) { [bool]$tweak.TroubleshootingOnly } else { $false }
				PreviewGroupHeader = [string]$previewSection.Header
				PreviewGroupSortOrder = [int]$previewSection.SortOrder
				Status          = $previewStatus
				Detail          = $detailText
			})
		}

		# Check for conflicts between selected tweaks
		$selectedFunctionLookup = @{}
		foreach ($tweak in @($SelectedTweaks))
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$tweak.Function))
			{
				$selectedFunctionLookup[[string]$tweak.Function] = $tweak
			}
		}
		foreach ($tweak in @($SelectedTweaks))
		{
			$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function ([string]$tweak.Function)
			if (-not $manifestEntry -or -not (Test-GuiObjectField -Object $manifestEntry -FieldName 'ConflictsWith') -or -not $manifestEntry.ConflictsWith) { continue }

			foreach ($conflict in @($manifestEntry.ConflictsWith))
			{
				$targetFunction = [string]$conflict.Function
				if (-not $selectedFunctionLookup.ContainsKey($targetFunction)) { continue }

				$targetTweak = $selectedFunctionLookup[$targetFunction]
				$thisSelection = [string]$tweak.Selection
				$targetSelection = [string]$targetTweak.Selection

				$thisMatches = ($thisSelection -eq [string]$conflict.WhenThisIs)
				$targetMatches = ($targetSelection -eq [string]$conflict.AndTargetIs)
				if (-not $thisMatches -or -not $targetMatches) { continue }

				# Append conflict warning to affected preview result
				$affectedResult = $previewResults | Where-Object { [string]$_.Name -eq [string]$tweak.Name } | Select-Object -First 1
				if ($affectedResult)
				{
					$affectedResult.Detail = [string]$affectedResult.Detail + ' ' + [string]$conflict.Resolution
				}
			}
		}

		return @($previewResults | Sort-Object Order)
	}

	function Write-ExecutionPreviewToLog
	{
		param ([object[]]$Results)

		$results = @($Results)
		$selectedCount = $results.Count
			$mediumRiskCount = @($results | Where-Object Risk -eq 'Medium').Count
			$alreadyInDesiredCount = @($results | Where-Object Status -eq 'Already in desired state').Count
			$willChangeCount = @($results | Where-Object Status -eq 'Will change').Count
			$requiresRestartCount = @($results | Where-Object Status -eq 'Requires restart').Count
			$highRiskCountPreview = @($results | Where-Object Status -eq 'High-risk changes').Count
			$notFullyRestorablePreviewCount = @($results | Where-Object Status -eq 'Not fully restorable').Count
		$categoryNames = @($results | ForEach-Object { [string]$_.Category } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

		LogInfo "Preview summary: Selected=$selectedCount, AlreadyDesired=$alreadyInDesiredCount, WillChange=$willChangeCount, MediumRisk=$mediumRiskCount, HighRisk=$highRiskCountPreview, NotFullyRestorable=$notFullyRestorablePreviewCount, RequiresRestart=$requiresRestartCount, Categories=$($categoryNames.Count). No changes were applied."
	}



