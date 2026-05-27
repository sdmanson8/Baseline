# Tweak visualization helpers: visual metadata, chip panels, section headers, caution sections, execution log, file-save dialog

	<#
	    .SYNOPSIS
	#>

	function Get-TweakVisualMetadata
	{
		param (
			[object]$Tweak,
			[object]$StateSource
		)

		if (-not $Tweak) { return $null }

		$source = if ($StateSource) { $StateSource } else { $Tweak }
		$typeKind = if (-not [string]::IsNullOrWhiteSpace([string]$Tweak.Type)) { [string]$Tweak.Type } else { 'Action' }
		$isRemoval = Test-TweakRemovalOperation -Tweak $Tweak
		$isPackageOperation = Test-TweakPackageOperation -Tweak $Tweak

		$typeKey = if ($isPackageOperation)
		{
			switch ($typeKind)
			{
				'Action' { 'PackageSetup' }
				default { 'PackageChange' }
			}
		}
			else
			{
				switch ($typeKind)
				{
					'Toggle' { 'Toggle' }
					'Choice' { if ($isRemoval) { 'Uninstall' } else { 'Choice' } }
					'NumericRange' { if ($isRemoval) { 'Uninstall' } else { 'NumericRange' } }
					'Date' { 'Date' }
					'Action' { if ($isRemoval) { 'Uninstall' } else { 'Action' } }
					default { if ($isRemoval) { 'Uninstall' } else { 'Other' } }
				}
			}
		$typeLabel = switch ($typeKey)
		{
			'PackageSetup' { Get-UxLocalizedString -Key 'GuiTweakTypePackageSetup' -Fallback 'Package / app setup' }
			'PackageChange' { Get-UxLocalizedString -Key 'GuiTweakTypePackageChange' -Fallback 'Package / app change' }
			'Uninstall' { Get-UxLocalizedString -Key 'GuiTweakTypeUninstall' -Fallback 'Uninstall / Remove' }
				'Toggle' { Get-UxLocalizedString -Key 'GuiTweakTypeToggle' -Fallback 'Toggle' }
				'Choice' { Get-UxLocalizedString -Key 'GuiTweakTypeChoice' -Fallback 'Choice' }
				'NumericRange' { Get-UxLocalizedString -Key 'GuiTweakTypeNumericRange' -Fallback 'Numeric range' }
				'Date' { Get-UxLocalizedString -Key 'GuiTweakTypeDate' -Fallback 'Date' }
				'Action' { Get-UxLocalizedString -Key 'GuiTweakTypeAction' -Fallback 'Action' }
				default { $typeKind }
			}

		$typeTone = switch ($typeKey)
		{
			'PackageSetup' { if ([string]$Tweak.Risk -eq 'High') { 'Danger' } else { 'Caution' } }
			'PackageChange' { if ($isRemoval -or [string]$Tweak.Risk -eq 'High') { 'Danger' } else { 'Caution' } }
			'Uninstall' { 'Danger' }
				'Toggle' { 'Success' }
				'Choice' { 'Primary' }
				'NumericRange' { 'Primary' }
				'Date' { 'Primary' }
				'Action' { 'Muted' }
				default { 'Muted' }
			}
		$typeBadgeLabel = switch ($typeKey)
		{
			'PackageSetup' { Get-UxLocalizedString -Key 'GuiTweakBadgePackageSetup' -Fallback 'Package setup' }
			'PackageChange' { Get-UxLocalizedString -Key 'GuiTweakBadgePackageChange' -Fallback 'Package change' }
				'Toggle' { Get-UxLocalizedString -Key 'GuiTweakBadgeToggle' -Fallback 'Toggle setting' }
				'Choice' { Get-UxLocalizedString -Key 'GuiTweakBadgeChoice' -Fallback 'Choice option' }
				'NumericRange' { Get-UxLocalizedString -Key 'GuiTweakBadgeNumericRange' -Fallback 'Numeric range' }
				'Date' { Get-UxLocalizedString -Key 'GuiTweakBadgeDate' -Fallback 'Date control' }
				'Action' { Get-UxLocalizedString -Key 'GuiTweakBadgeAction' -Fallback 'One-time action' }
				'Uninstall' { Get-UxLocalizedString -Key 'GuiTweakBadgeUninstall' -Fallback 'Remove / uninstall' }
				default { $typeLabel }
		}

		if ([string]::IsNullOrWhiteSpace([string]$typeLabel))
		{
			$typeLabel = if (-not [string]::IsNullOrWhiteSpace([string]$typeBadgeLabel))
			{
				[string]$typeBadgeLabel
			}
			elseif (-not [string]::IsNullOrWhiteSpace([string]$typeKind))
			{
				[string]$typeKind
			}
			else
			{
				'Numeric range'
			}
		}

		if ([string]::IsNullOrWhiteSpace([string]$typeBadgeLabel))
		{
			$typeBadgeLabel = $typeLabel
		}

		$stateLabel = $null
		$stateTone = 'Muted'
		$stateDetail = $null
		$matchesDesired = $false
		$defaultValueText = $null
		$detectedState = $null
		$goalState = $null
		$isSelected = $false

		switch ($typeKind)
		{
			'Toggle'
			{
				$toggleDisplay = Get-GuiToggleDisplayState -Tweak $Tweak -StateSource $source
				$stateLabel = [string]$toggleDisplay.StateLabel
				$stateTone = [string]$toggleDisplay.StateTone
				$matchesDesired = [bool]$toggleDisplay.MatchesDesired
				$stateDetail = [string]$toggleDisplay.StateDetail
				$detectedState = $toggleDisplay.DetectedState
				$goalState = [bool]$toggleDisplay.GoalState
				$isSelected = [bool]$toggleDisplay.IsSelected
				$defaultValueText = if ($goalState) { Get-UxLocalizedString -Key 'GuiTweakDefaultEnabled' -Fallback 'Enabled' } else { Get-UxLocalizedString -Key 'GuiTweakDefaultDisabled' -Fallback 'Disabled' }
			}
				'Choice'
				{
					$displayOpts = if ($Tweak.DisplayOptions) { @($Tweak.DisplayOptions) } else { @($Tweak.Options) }
					$selectedIndex = if (Test-GuiObjectField -Object $source -FieldName 'SelectedIndex') { [int](Get-GuiObjectField -Object $source -FieldName 'SelectedIndex') } else { -1 }
				$selectedValue = if ($selectedIndex -ge 0 -and $selectedIndex -lt $displayOpts.Count) { [string]$displayOpts[$selectedIndex] } else { $null }
				$defaultIndex = -1
				if ((Test-GuiObjectField -Object $Tweak -FieldName 'Default') -and $Tweak.Options)
				{
					$defaultIndex = [array]::IndexOf(@($Tweak.Options), $Tweak.Default)
				}
				$defaultValue = if ($defaultIndex -ge 0 -and $defaultIndex -lt $displayOpts.Count) { [string]$displayOpts[$defaultIndex] } elseif (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'Default') } else { $null }

				if ($selectedIndex -lt 0)
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateAlreadySet' -Fallback 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailNoChoice' -Fallback 'No explicit choice selected.'
				}
				elseif (($defaultIndex -ge 0 -and $selectedIndex -eq $defaultIndex) -or ([string]$selectedValue -eq [string]$defaultValue))
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateAlreadySet' -Fallback 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = if ($selectedValue) { (Get-UxLocalizedString -Key 'GuiTweakStateDetailAlreadySetValue' -Fallback 'Already set to the manifest default: {0}.') -f $selectedValue } else { Get-UxLocalizedString -Key 'GuiTweakStateDetailAlreadySet' -Fallback 'Already set to the manifest default.' }
				}
				else
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateCustom' -Fallback 'Custom'
					$stateTone = 'Primary'
						$stateDetail = if ($selectedValue) { (Get-UxLocalizedString -Key 'GuiTweakStateDetailCurrentChoice' -Fallback 'Current choice: {0}.') -f $selectedValue } else { Get-UxLocalizedString -Key 'GuiTweakStateDetailNonDefault' -Fallback 'A non-default choice is selected.' }
					}
				$defaultValueText = if (-not [string]::IsNullOrWhiteSpace([string]$defaultValue)) { [string]$defaultValue } else { Get-UxLocalizedString -Key 'GuiTweakDefaultNoSelection' -Fallback 'No selection' }
				}
				'NumericRange'
				{
					$numericRange = if (Test-GuiObjectField -Object $Tweak -FieldName 'NumericRange') { Get-GuiObjectField -Object $Tweak -FieldName 'NumericRange' } else { $null }
					$defaultSource = $null
					if ((Test-GuiObjectField -Object $Tweak -FieldName 'Default'))
					{
						$defaultSource = Get-GuiObjectField -Object $Tweak -FieldName 'Default'
					}
					elseif ((Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault'))
					{
						$defaultSource = Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault'
					}

					$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
					$selected = $false
					if ((Test-GuiObjectField -Object $source -FieldName 'IsChecked'))
					{
						$selected = [bool]$source.IsChecked
					}
					elseif ($explicitSelection -and [string]$explicitSelection.Type -eq 'NumericRange')
					{
						$selected = $true
					}
					elseif ((Test-GuiObjectField -Object $source -FieldName 'ACValue') -or (Test-GuiObjectField -Object $source -FieldName 'DCValue') -or (Test-GuiObjectField -Object $source -FieldName 'NumericValue') -or (Test-GuiObjectField -Object $source -FieldName 'Value'))
					{
						$selected = $true
					}

					$currentValueSource = if ($explicitSelection -and [string]$explicitSelection.Type -eq 'NumericRange') { $explicitSelection } else { $source }
					$currentAC = Get-GuiNumericRangeChannelValue -Value $currentValueSource -Channel 'AC' -NumericRange $numericRange
					$currentDC = Get-GuiNumericRangeChannelValue -Value $currentValueSource -Channel 'DC' -NumericRange $numericRange
					$defaultAC = if ($null -ne $defaultSource) { Get-GuiNumericRangeChannelValue -Value $defaultSource -Channel 'AC' -NumericRange $numericRange } else { $null }
					$defaultDC = if ($null -ne $defaultSource) { Get-GuiNumericRangeChannelValue -Value $defaultSource -Channel 'DC' -NumericRange $numericRange } else { $null }
					$currentText = if ($null -ne $currentAC -or $null -ne $currentDC) { Format-GuiPowerSchemeValueText -Value ([pscustomobject]@{ ACValue = $currentAC; DCValue = $currentDC }) -NumericRange $numericRange } else { $null }
					$defaultText = if ($null -ne $defaultAC -or $null -ne $defaultDC) { Format-GuiPowerSchemeValueText -Value ([pscustomobject]@{ ACValue = $defaultAC; DCValue = $defaultDC }) -NumericRange $numericRange } else { $null }

					if (-not $selected)
					{
						$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateDisabled' -Fallback 'Disabled'
						$stateTone = 'Muted'
						$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailDisabled' -Fallback 'Disabled in the current selection.'
					}
					elseif ($null -ne $currentText -and $null -ne $defaultText -and [string]$currentText -eq [string]$defaultText)
					{
						$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateAlreadySet' -Fallback 'Already set'
						$stateTone = 'Muted'
						$matchesDesired = $true
						$stateDetail = (Get-UxLocalizedString -Key 'GuiTweakStateDetailAlreadySetValue' -Fallback 'Already set to the manifest default: {0}.') -f $currentText
					}
					else
					{
						$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateCustom' -Fallback 'Custom'
						$stateTone = 'Primary'
						if ($null -ne $currentText)
						{
							$stateDetail = (Get-UxLocalizedString -Key 'GuiTweakStateDetailCurrentChoice' -Fallback 'Current choice: {0}.') -f $currentText
						}
						else
						{
							$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailNonDefault' -Fallback 'A custom numeric range is selected.'
						}
					}
					$defaultValueText = if (-not [string]::IsNullOrWhiteSpace([string]$defaultText)) { [string]$defaultText } else { Get-UxLocalizedString -Key 'GuiTweakDefaultNoSelection' -Fallback 'No selection' }
				}
				'Date'
				{
					$defaultRun = if (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default') } else { $false }
					$currentRun = $false
				$currentDate = $null
				if ((Test-GuiObjectField -Object $source -FieldName 'SelectedDate') -and $source.SelectedDate)
				{
					$currentRun = $true
					$currentDate = ([datetime]$source.SelectedDate).ToString('yyyy-MM-dd')
				}
				elseif (Test-GuiObjectField -Object $source -FieldName 'IsChecked')
				{
					$currentRun = [bool]$source.IsChecked
				}
				$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
				if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Date')
				{
					if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'Run'))
					{
						$currentRun = [bool]$explicitSelection.Run
					}
					if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$explicitSelection.Value))
					{
						$currentDate = [string]$explicitSelection.Value
					}
				}

				if ($currentRun -eq $defaultRun -and (([string]::IsNullOrWhiteSpace($currentDate) -and [string]::IsNullOrWhiteSpace([string](Get-GuiObjectField -Object $Tweak -FieldName 'DefaultDate'))) -or ([string]$currentDate -eq [string](Get-GuiObjectField -Object $Tweak -FieldName 'DefaultDate'))))
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateAlreadySet' -Fallback 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailAlreadySet' -Fallback 'Already set to the manifest default.'
				}
				elseif ($currentRun)
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateEnabled' -Fallback 'Enabled'
					$stateTone = 'Success'
					$stateDetail = if (-not [string]::IsNullOrWhiteSpace($currentDate)) { (Get-UxLocalizedString -Key 'GuiTweakStateDetailCurrentChoice' -Fallback 'Current choice: {0}.') -f $currentDate } else { 'Pause start date selected.' }
				}
				else
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateDisabled' -Fallback 'Disabled'
					$stateTone = 'Muted'
					$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailDisabled' -Fallback 'Disabled in the current selection.'
				}
				$defaultValueText = if ($defaultRun)
				{
					$defaultDateText = if (Test-GuiObjectField -Object $Tweak -FieldName 'DefaultDate') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'DefaultDate') } elseif (Test-GuiObjectField -Object $Tweak -FieldName 'DefaultValue') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'DefaultValue') } elseif (Test-GuiObjectField -Object $Tweak -FieldName 'Value') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'Value') } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($defaultDateText)) { $defaultDateText } else { Get-UxLocalizedString -Key 'GuiTweakDefaultEnabled' -Fallback 'Enabled' }
				}
				else
				{
					Get-UxLocalizedString -Key 'GuiTweakDefaultDisabled' -Fallback 'Disabled'
				}
			}
			'Action'
			{
				$isSelected = if (Test-GuiObjectField -Object $source -FieldName 'IsChecked') { [bool](Get-GuiObjectField -Object $source -FieldName 'IsChecked') } else { $false }
				if ($isSelected)
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateQueued' -Fallback 'Queued'
					$stateTone = 'Primary'
					$stateDetail = (Get-UxLocalizedString -Key 'GuiTweakStateDetailQueued' -Fallback 'This one-time action will run when you click {0}.') -f (Get-UxRunActionLabel)
				}
				else
				{
					$stateLabel = Get-UxLocalizedString -Key 'GuiTweakStateIdle' -Fallback 'Idle'
					$stateTone = 'Muted'
					$stateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailIdle' -Fallback 'This one-time action is not selected.'
				}
				$defaultValueText = Get-UxLocalizedString -Key 'GuiTweakDefaultNotSelected' -Fallback 'Not selected'
			}
		}

		$scenarioTags = New-Object System.Collections.Generic.List[string]
		foreach ($scenarioTag in @($Tweak.ScenarioTags))
		{
			if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
			$normalizedScenarioTag = Format-TweakScenarioTag -Tag $scenarioTag
			if ([string]::IsNullOrWhiteSpace($normalizedScenarioTag)) { continue }
			if ($scenarioTags -contains $normalizedScenarioTag) { continue }
			[void]$scenarioTags.Add($normalizedScenarioTag)
		}
		foreach ($tag in @($Tweak.Tags))
		{
			$formattedTag = Format-TweakScenarioTag -Tag $tag
			if ([string]::IsNullOrWhiteSpace($formattedTag)) { continue }
			if ($scenarioTags -contains $formattedTag) { continue }
			[void]$scenarioTags.Add($formattedTag)
		}

		$scenarioSignals = @(Get-TweakScenarioSignals -Tweak $Tweak -IsRemoval $isRemoval)
		foreach ($signal in $scenarioSignals)
		{
			if ([string]::IsNullOrWhiteSpace([string]$signal)) { continue }
			if ($scenarioTags -contains $signal) { continue }
			[void]$scenarioTags.Add([string]$signal)
		}

		$focusGroup = Get-TweakFocusGroup -Tweak $Tweak -ScenarioSignals $scenarioSignals
		$reasonIncluded = Get-TweakInclusionReason -Tweak $Tweak -FocusGroup $focusGroup -ScenarioSignals $scenarioSignals
		$blastRadius = Get-TweakBlastRadiusText -Tweak $Tweak -TypeLabel $typeLabel -ScenarioTags @($scenarioTags) -MatchesDesired $matchesDesired -IsRemoval $isRemoval -IsPackageOperation $isPackageOperation

		return [pscustomobject]@{
			TypeKind = $typeKind
			TypeLabel = $typeLabel
			TypeBadgeLabel = $typeBadgeLabel
			TypeTone = $typeTone
			StateLabel = $stateLabel
			StateTone = $stateTone
			StateDetail = $stateDetail
			DefaultValueText = $defaultValueText
			MatchesDesired = $matchesDesired
			DetectedState = $detectedState
			GoalState = $goalState
			IsSelected = $isSelected
			ScenarioTags = @($scenarioTags)
			FocusGroup = $focusGroup
			ReasonIncluded = $reasonIncluded
			BlastRadius = $blastRadius
			IsRemoval = $isRemoval
			RecoveryLevel = if (Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') } else { $null }
			TroubleshootingOnly = if (Test-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly') } else { $false }
		}
	}

		<#
		    .SYNOPSIS
		#>

		function New-TweakMetadataChipPanel
		{
			param(
				[object]$Metadata,
				[bool]$IncludeType = $true,
				[bool]$IncludeState = $true,
				[bool]$IncludeRestart = $true,
				[bool]$IncludeRestorable = $true,
				[bool]$IncludeRecoveryLevel = $true,
				[bool]$UseCompactRecoveryLevelLabel = $false,
				[bool]$IncludeScenarioTags = $false,
				[int]$MaxScenarioTags = 4,
				[bool]$IncludeTroubleshooting = $true
			)

		if (-not $Metadata) { return $null }

		$panel = New-Object System.Windows.Controls.WrapPanel
		$panel.Orientation = 'Horizontal'
		$panel.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$panel.HorizontalAlignment = 'Stretch'

		$chipItems = New-Object System.Collections.Generic.List[object]
		$typeBadgeText = if ((Test-GuiObjectField -Object $Metadata -FieldName 'TypeBadgeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.TypeBadgeLabel)) { [string]$Metadata.TypeBadgeLabel } else { [string]$Metadata.TypeLabel }
		if ($IncludeType -and -not [string]::IsNullOrWhiteSpace($typeBadgeText))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $typeBadgeText
				Tone = if ((Test-GuiObjectField -Object $Metadata -FieldName 'TypeTone') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.TypeTone)) { [string]$Metadata.TypeTone } else { 'Muted' }
				ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipType' -Fallback 'Type of tweak'
			})
		}

		if ($IncludeState -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateLabel))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$Metadata.StateLabel
				Tone = if ((Test-GuiObjectField -Object $Metadata -FieldName 'StateTone') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateTone)) { [string]$Metadata.StateTone } else { 'Muted' }
				ToolTip = if ((Test-GuiObjectField -Object $Metadata -FieldName 'StateDetail') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateDetail)) { [string]$Metadata.StateDetail } else { Get-UxLocalizedString -Key 'GuiTweakChipTooltipState' -Fallback 'Current state in the GUI' }
			})
		}

		if ($IncludeRestart -and (Test-GuiObjectField -Object $Metadata -FieldName 'RequiresRestart') -and [bool]$Metadata.RequiresRestart)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = Get-UxLocalizedString -Key 'GuiTweakChipRestartRequired' -Fallback 'Restart required'
				Tone = 'Caution'
				ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipRestart' -Fallback 'This change requires a restart to take effect.'
			})
		}

		if ($IncludeRestorable -and (Test-GuiObjectField -Object $Metadata -FieldName 'Restorable') -and $null -ne $Metadata.Restorable -and -not [bool]$Metadata.Restorable)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = Get-UxLocalizedString -Key 'GuiTweakChipManualRecovery' -Fallback 'Manual recovery'
				Tone = 'Danger'
				ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipManualRecovery' -Fallback 'This change cannot be fully rolled back automatically.'
			})
		}

		if ($IncludeRecoveryLevel -and (Test-GuiObjectField -Object $Metadata -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.RecoveryLevel))
		{
			$recoveryLevelLabel = [string]$Metadata.RecoveryLevel
			$recoveryTone = switch ($recoveryLevelLabel)
			{
				'Direct' { 'Success'; break }
				'DefaultsOnly' { 'Primary'; break }
				'RestorePoint' { 'Caution'; break }
				'Manual' { 'Danger'; break }
				default { 'Muted' }
				}
				$localizedRecoveryLabel = switch ($recoveryLevelLabel)
				{
					'Direct'       { Get-UxLocalizedString -Key 'GuiRecoveryLevelDirect' -Fallback 'Direct'; break }
					'DefaultsOnly' { Get-UxLocalizedString -Key 'GuiRecoveryLevelDefaultsOnly' -Fallback 'Defaults Only'; break }
					'RestorePoint' { Get-UxLocalizedString -Key 'GuiRecoveryLevelRestorePoint' -Fallback 'Restore Point'; break }
					'Manual'       { Get-UxLocalizedString -Key 'GuiRecoveryLevelManual' -Fallback 'Manual'; break }
					default        { $recoveryLevelLabel }
				}
				[void]$chipItems.Add([pscustomobject]@{
					Label = $(if ($UseCompactRecoveryLevelLabel) { $localizedRecoveryLabel } else { (Get-UxLocalizedString -Key 'GuiTweakChipRecoveryFormat' -Fallback 'Recovery: {0}') -f $localizedRecoveryLabel })
					Tone = $recoveryTone
					ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipRecovery' -Fallback 'Recommended recovery path for this tweak.'
				})
			}

		if ($IncludeTroubleshooting -and (Test-GuiObjectField -Object $Metadata -FieldName 'TroubleshootingOnly') -and [bool]$Metadata.TroubleshootingOnly)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = Get-UxLocalizedString -Key 'GuiTweakChipTroubleshooting' -Fallback 'Troubleshooting only'
				Tone = 'Caution'
				ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipTroubleshooting' -Fallback 'Use this only when diagnosing game compatibility, overlay, or display issues.'
			})
		}

		if ($IncludeScenarioTags -and (Test-GuiObjectField -Object $Metadata -FieldName 'ScenarioTags') -and $Metadata.ScenarioTags)
		{
			$scenarioTags = @($Metadata.ScenarioTags)
			foreach ($tag in @($scenarioTags | Select-Object -First $MaxScenarioTags))
			{
				if ([string]::IsNullOrWhiteSpace([string]$tag)) { continue }
				[void]$chipItems.Add([pscustomobject]@{
					Label = [string]$tag
					Tone = 'Muted'
					ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipScenarioTag' -Fallback 'Scenario tag'
				})
			}
			if ($scenarioTags.Count -gt $MaxScenarioTags)
			{
				[void]$chipItems.Add([pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiTweakChipMoreFormat' -Fallback '+{0} more') -f ($scenarioTags.Count - $MaxScenarioTags)
					Tone = 'Muted'
					ToolTip = Get-UxLocalizedString -Key 'GuiTweakChipTooltipMoreTags' -Fallback 'Additional scenario tags are present in the manifest.'
				})
			}
		}

		foreach ($chip in $chipItems)
		{
			[void]($panel.Children.Add((GUICommon\New-DialogMetadataPill `
				-Theme $Script:CurrentTheme `
				-Label $chip.Label `
				-Tone $chip.Tone `
				-ToolTip $chip.ToolTip)))
		}

		if ($panel.Children.Count -eq 0)
		{
			return $null
		}

		return $panel
	}

	<#
	    .SYNOPSIS
	#>

	function New-SectionHeader
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Text)
		$lbl = New-Object System.Windows.Controls.TextBlock
		$lbl.Text = $Text.ToUpper()
		$lbl.FontSize = 11
		$lbl.FontWeight = [System.Windows.FontWeights]::Bold
		$lbl.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.SectionLabel -Context 'New-SectionHeader/Foreground'
		$lbl.Margin = [System.Windows.Thickness]::new(12, 12, 0, 6)
		return $lbl
	}

	function New-SearchResultsSummary
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Query,
			[int]$MatchCount
		)

		$bc = New-SafeBrushConverter -Context 'New-SearchResultsSummary'

		# Use AccentBlue as the banner background for a distinctive inline look.
		$accentBlue = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.AccentBlue)) { [string]$Script:CurrentTheme.AccentBlue } else { '#3B82F6' }

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($accentBlue)
		$border.BorderBrush = $bc.ConvertFromString($accentBlue)
		$border.BorderThickness = [System.Windows.Thickness]::new(0)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$border.Margin = [System.Windows.Thickness]::new(8, 10, 8, 6)
		$border.Padding = [System.Windows.Thickness]::new(16, 10, 16, 10)

		# Horizontal layout: text on the left, clear button on the right.
		$grid = New-Object System.Windows.Controls.Grid
		$colText = New-Object System.Windows.Controls.ColumnDefinition
		$colText.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		[void]($grid.ColumnDefinitions.Add($colText))
		$colBtn = New-Object System.Windows.Controls.ColumnDefinition
		$colBtn.Width = [System.Windows.GridLength]::Auto
		[void]($grid.ColumnDefinitions.Add($colBtn))

		$textStack = New-Object System.Windows.Controls.StackPanel
		$textStack.Orientation = 'Vertical'
		$textStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		[System.Windows.Controls.Grid]::SetColumn($textStack, 0)

		$summaryText = if ($MatchCount -eq 1) { (Get-UxLocalizedString -Key 'GuiTweakSearchResultsSingular' -Fallback "Showing 1 result for '{0}'") -f $Query } else { (Get-UxLocalizedString -Key 'GuiTweakSearchResultsPlural' -Fallback "Showing {0} results for '{1}'") -f $MatchCount, $Query }
		$searchIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Search' -Text $summaryText -IconSize 16 -Gap 8 -TextFontSize 13 -Foreground ($bc.ConvertFromString('#FFFFFF')) -AllowTextOnlyFallback -Bold } else { $null }
		if ($searchIconContent)
		{
			$searchIconContent.Margin = [System.Windows.Thickness]::new(0)
			[void]($textStack.Children.Add($searchIconContent))
		}
		else
		{
			$summary = New-Object System.Windows.Controls.TextBlock
			$summary.Text = $summaryText
			$summary.TextWrapping = 'Wrap'
			$summary.FontSize = 13
			$summary.FontWeight = [System.Windows.FontWeights]::SemiBold
			$summary.Foreground = $bc.ConvertFromString('#FFFFFF')
			[void]($textStack.Children.Add($summary))
		}
		[void]($grid.Children.Add($textStack))

		# "Clear" button to dismiss search results inline.
		$clearBtn = New-Object System.Windows.Controls.Button
		$clearBtnText = Get-UxLocalizedString -Key 'GuiBtnClearSearch' -Fallback 'Clear'
		$clearBtn.FontSize = 12
		$clearBtn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$clearBtn.Padding = [System.Windows.Thickness]::new(14, 5, 14, 5)
		$clearBtn.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
		$clearBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		$clearBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		Set-ButtonChrome -Button $clearBtn -Variant 'Subtle' -Compact
		$clearIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Clear' -Text $clearBtnText -IconSize 14 -Gap 6 -TextFontSize 12 -Foreground $clearBtn.Foreground -AllowTextOnlyFallback } else { $null }
		$clearBtn.Content = if ($clearIconContent) { $clearIconContent } else { $clearBtnText }
		[System.Windows.Controls.Grid]::SetColumn($clearBtn, 1)

		# When clicked, clear the search text box to dismiss the inline results.
		# Capture $TxtSearch from the parent scope so the closure resolves correctly.
		$searchBox = $TxtSearch
		Register-GuiEventHandler -Source $clearBtn -EventName 'Click' -Handler ({
			if ($searchBox) { $searchBox.Text = '' ; [void]($searchBox.Focus()) }
		}.GetNewClosure()) | Out-Null
		[void]($grid.Children.Add($clearBtn))

		$border.Child = $grid
		return $border
	}

	<#
	    .SYNOPSIS
	#>

	function New-CautionSection
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([array]$CautionTweaks)
		if ($CautionTweaks.Count -eq 0) { return $null }
		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersBlock'

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CautionBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CautionBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$border.Margin = [System.Windows.Thickness]::new(8, 10, 8, 6)
		$border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = "Vertical"

		$headerGrid = New-Object System.Windows.Controls.Grid
		$headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		$headerStack = New-Object System.Windows.Controls.StackPanel
		$headerStack.Orientation = 'Vertical'
		[System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

		$cautionHeaderText = (Get-UxLocalizedString -Key 'GuiTweakCautionHeader' -Fallback 'CAUTION').ToUpper()
		$cautionIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Warning' -Text $cautionHeaderText -IconSize 14 -Gap 6 -TextFontSize 12 -Foreground (ConvertTo-GuiBrush -Color $Script:CurrentTheme.CautionText -Context 'New-CautionSection/Header') -AllowTextOnlyFallback -Bold } else { $null }
		if ($cautionIconContent)
		{
			[void]($headerStack.Children.Add($cautionIconContent))
		}
		else
		{
			$header = New-Object System.Windows.Controls.TextBlock
			$header.Text = $cautionHeaderText
			$header.FontSize = 12
			$header.FontWeight = [System.Windows.FontWeights]::Bold
			$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
			[void]($headerStack.Children.Add($header))
		}
		$summary = New-Object System.Windows.Controls.TextBlock
		$summary.Text = if ($CautionTweaks.Count -eq 1) { Get-UxLocalizedString -Key 'GuiTweakCautionSummarySingular' -Fallback '1 tweak needs extra care in this section.' } else { (Get-UxLocalizedString -Key 'GuiTweakCautionSummaryPlural' -Fallback '{0} tweaks need extra care in this section.') -f $CautionTweaks.Count }
		$summary.FontSize = 11
		$summary.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$summary.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		[void]($headerStack.Children.Add($summary))
		[void]($headerGrid.Children.Add($headerStack))
		$toggleButton = New-Object System.Windows.Controls.Button
		$toggleButton.Content = Get-UxLocalizedString -Key 'GuiShowDetails' -Fallback 'Show details'
		$toggleButton.FontSize = 11
		$toggleButton.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$toggleButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$toggleButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		Set-ButtonChrome -Button $toggleButton -Variant 'Subtle' -Compact
		[System.Windows.Controls.Grid]::SetColumn($toggleButton, 1)
		[void]($headerGrid.Children.Add($toggleButton))
		[void]($stack.Children.Add($headerGrid))
		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$detailsPanel = New-Object System.Windows.Controls.StackPanel
		$detailsPanel.Orientation = 'Vertical'
		$detailsPanel.Visibility = [System.Windows.Visibility]::Collapsed

		foreach ($ct in $CautionTweaks)
		{
			$reason = if ($ct.CautionReason) { $ct.CautionReason } else { Get-UxLocalizedString -Key 'GuiTweakCautionDefaultReason' -Fallback 'This tweak may have unintended side effects. Use with care.' }
			$item = New-Object System.Windows.Controls.TextBlock
			$item.TextWrapping = "Wrap"
			$item.Margin = [System.Windows.Thickness]::new(0, 2, 0, 4)
			$item.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)

			$bold = New-Object System.Windows.Documents.Run
			$bold.Text = "$($ct.Name): "
			$bold.FontWeight = [System.Windows.FontWeights]::SemiBold
			$bold.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			[void]($item.Inlines.Add($bold))
			$desc = New-Object System.Windows.Documents.Run
			$desc.Text = $reason
			[void]($item.Inlines.Add($desc))
			[void]($detailsPanel.Children.Add($item))
		}

		Register-GuiEventHandler -Source $toggleButton -EventName 'Click' -Handler ({
			$showDetails = ($detailsPanel.Visibility -ne [System.Windows.Visibility]::Visible)
			$detailsPanel.Visibility = if ($showDetails) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			$toggleButton.Content = if ($showDetails) {
				& $getUxLocalizedStringCapture -Key 'GuiHideDetails' -Fallback 'Hide details'
			}
			else {
				& $getUxLocalizedStringCapture -Key 'GuiShowDetails' -Fallback 'Show details'
			}
		}.GetNewClosure()) | Out-Null

		[void]($stack.Children.Add($detailsPanel))
		$border.Child = $stack
		return $border
	}

		<#
		    .SYNOPSIS
		#>

		function Add-ExecutionLogLine
		{
		param (
			[string]$Text,
			[string]$Level = 'INFO'
		)

		if ([string]::IsNullOrWhiteSpace($Text) -or -not $Script:ExecutionLogBox -or -not $Script:ExecutionLogBox.Document) { return }

		$bc = New-SafeBrushConverter -Context 'Add-ExecutionLogLine'
		$timestamp = Get-Date -Format 'HH:mm:ss'
		$getLogColor = {
			param (
				[string]$ColorName,
				[string]$FallbackColor
			)

			if ($Script:CurrentTheme -and $Script:CurrentTheme.ContainsKey($ColorName) -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme[$ColorName]))
			{
				return [string]$Script:CurrentTheme[$ColorName]
			}

			return $FallbackColor
		}.GetNewClosure()

		$para = New-Object System.Windows.Documents.Paragraph
		$para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
		$para.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
		$para.FontSize = 12

		$tsRun = New-Object System.Windows.Documents.Run
		$tsRun.Text = "[$timestamp] "
		$tsRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($para.Inlines.Add($tsRun))
		# Icon glyph prefix for log level
		$logIconKind = switch ($Level.ToUpperInvariant())
		{
			'ERROR'   { 'Failed' }
			'WARNING' { 'Warning' }
			'SUCCESS' { 'Success' }
			'SKIP'    { 'Skipped' }
			default   { 'Info' }
		}
		$logIconGlyph = if (Get-Command -Name 'Get-GuiIconGlyph' -CommandType Function -ErrorAction SilentlyContinue) { Get-GuiIconGlyph -Name $logIconKind } else { $null }
		if ((Get-Command -Name 'Test-GuiIconsAvailable' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-GuiIconsAvailable) -and $logIconGlyph)
		{
			$iconRun = New-Object System.Windows.Documents.Run
			$iconRun.Text = "$logIconGlyph "
			$iconRun.FontFamily = $Script:GuiIconFontFamily
			$iconRun.FontSize = 12
			$logIconColor = switch ($Level.ToUpperInvariant())
			{
				'ERROR'   { & $getLogColor -ColorName 'LogError' -FallbackColor $Script:CurrentTheme.CautionText }
				'WARNING' { & $getLogColor -ColorName 'LogWarning' -FallbackColor $Script:CurrentTheme.RiskMediumBadge }
				'SUCCESS' { & $getLogColor -ColorName 'LogSuccess' -FallbackColor $Script:CurrentTheme.LowRiskBadge }
				'DEBUG'   { & $getLogColor -ColorName 'LogDebug' -FallbackColor $Script:CurrentTheme.TextMuted }
				default   { & $getLogColor -ColorName 'LogInfo' -FallbackColor $Script:CurrentTheme.TextMuted }
			}
			$iconRun.Foreground = $bc.ConvertFromString($logIconColor)
			[void]($para.Inlines.Add($iconRun))
		}
		$levelRun = New-Object System.Windows.Documents.Run
		$levelRun.Text = "[$($Level.ToUpperInvariant())] "
		$levelRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($para.Inlines.Add($levelRun))
		$contentRun = New-Object System.Windows.Documents.Run
		$contentRun.Text = $Text
		$contentColor = switch ($Level.ToUpperInvariant())
		{
			'ERROR'   { & $getLogColor -ColorName 'LogError' -FallbackColor $Script:CurrentTheme.CautionText }
			'WARNING' { & $getLogColor -ColorName 'LogWarning' -FallbackColor $Script:CurrentTheme.RiskMediumBadge }
			'SUCCESS' { & $getLogColor -ColorName 'LogSuccess' -FallbackColor $Script:CurrentTheme.LowRiskBadge }
			'INFO'    { & $getLogColor -ColorName 'LogInfo' -FallbackColor $Script:CurrentTheme.AccentBlue }
			'DEBUG'   { & $getLogColor -ColorName 'LogDebug' -FallbackColor $Script:CurrentTheme.TextMuted }
			default   { & $getLogColor -ColorName 'LogDefault' -FallbackColor $Script:CurrentTheme.TextPrimary }
		}
		$contentRun.Foreground = $bc.ConvertFromString($contentColor)
		[void]($para.Inlines.Add($contentRun))
		[void]($Script:ExecutionLogBox.Document.Blocks.Add($para))
		$vO = $Script:ExecutionLogBox.VerticalOffset
		$vH = $Script:ExecutionLogBox.ViewportHeight
		$eH = $Script:ExecutionLogBox.ExtentHeight
		if (($vO + $vH) -ge ($eH - 30))
		{
			$Script:ExecutionLogBox.ScrollToEnd()
		}
			$null = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'RenderRefresh' -Synchronous -Action {}
		}

		<#
		    .SYNOPSIS
		#>

		function Test-ExecutionSkipMessage
		{
			param(
				[string]$Message
			)

			if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

			return ($Message -match '(?i)\bskipping\b|\bskipped\b|\bnot applicable\b|\bnot supported\b|\bunsupported\b')
		}

	function Show-GuiFileSaveDialog
	{
		param (
			[string]$Title = 'Save File',
			[string]$Filter = 'All Files (*.*)|*.*',
			[string]$DefaultExtension = 'json',
			[string]$FileName = 'Baseline-export.json',
			[string]$InitialDirectory
		)

		$saveDialog = New-Object Microsoft.Win32.SaveFileDialog
		$saveDialog.Title = $Title
		$saveDialog.Filter = $Filter
		$saveDialog.DefaultExt = $DefaultExtension
		$saveDialog.AddExtension = $true
		$saveDialog.FileName = $FileName
		if ([string]::IsNullOrWhiteSpace($InitialDirectory))
		{
			$InitialDirectory = GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline'
		}
		$saveDialog.InitialDirectory = $InitialDirectory

		$owner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($saveDialog.ShowDialog($owner) -eq $true)
		{
			return $saveDialog.FileName
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>
	function Show-GuiFolderPickerDialog
	{
		param (
			[string]$Description = 'Select a folder',
			[string]$InitialDirectory
		)

		Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

		$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
		$folderDialog.Description = $Description
		$folderDialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
		$folderDialog.ShowNewFolderButton = $true

		if ([string]::IsNullOrWhiteSpace($InitialDirectory))
		{
			$InitialDirectory = GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline'
		}

		if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory))
		{
			$folderDialog.SelectedPath = $InitialDirectory
		}

		try
		{
			if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
			{
				return $folderDialog.SelectedPath
			}
		}
		finally
		{
			if ($folderDialog) { $folderDialog.Dispose() }
		}

		return $null
	}
