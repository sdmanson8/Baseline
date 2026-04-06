# Game Mode profile definitions, plan builders, and UI state management

	function Update-GameModeStatusText
	{
		param (
			[string]$Message,
			[ValidateSet('Accent', 'Muted', 'Toggle')]
			[string]$Tone = 'Accent'
		)

		$ctl = $Script:StatusTextControl
		$mappedTone = switch ($Tone)
		{
			'Muted'  { 'muted' }
			'Toggle' { 'success' }
			default  { 'accent' }
		}

		if (Get-Command -Name 'Set-GuiStatusText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Set-GuiStatusText -Text $Message -Tone $mappedTone
			return
		}

		if (-not $ctl) { return }
		$color = switch ($Tone)
		{
			'Muted'  { $Script:CurrentTheme.TextSecondary }
			'Toggle' { $Script:CurrentTheme.ToggleOn }
			default  { $Script:CurrentTheme.AccentBlue }
		}
		$ctl.Text = $Message
		$ctl.Foreground = (& $Script:NewSafeBrushConverterScript -Context 'GameModeUI').ConvertFromString($color)
	}

	function Get-GameModeManifestEntries
	{
		param (
			$TweakManifest = $null,
			$Allowlist = $null
		)
		$resolvedManifest = if ($null -ne $TweakManifest) { $TweakManifest } else { $Script:TweakManifest }
		$resolvedAllowlist = if ($null -ne $Allowlist) { $Allowlist } else { $Script:GameModeAllowlist }

		$allowlistLookup = @{}
		for ($i = 0; $i -lt $resolvedAllowlist.Count; $i++)
		{
			$allowlistLookup[[string]$resolvedAllowlist[$i]] = $i
		}

		return @(
			$resolvedManifest |
				Where-Object {
					$allowlistLookup.ContainsKey([string]$_.Function) -and
					(Test-GameModeAllowlistEntryReviewed -Entry $_)
				} |
				Sort-Object @{ Expression = { $allowlistLookup[[string]$_.Function] } }
		)
	}

	function Get-GamingPreviewGroupSortOrder
	{
		param ([string]$GroupName)

		switch ([string]$GroupName)
		{
			'Core Performance' { return 0 }
			'Input' { return 1 }
			'Capture & Overlay' { return 2 }
			'Compatibility & Troubleshooting' { return 3 }
			'Restart-Required Items' { return 4 }
			'Advanced: Compatibility' { return 10 }
			'Advanced: Performance' { return 11 }
			'Advanced: Session Behavior' { return 12 }
			'Advanced: Overlay' { return 13 }
			default {
				if ([string]$GroupName -like 'Advanced:*') { return 14 }
				return 99
			}
		}
	}

	function Get-GameModePreviewSectionInfo
	{
		param (
			[object]$Tweak
		)

		if (-not $Tweak -or -not (Test-GuiObjectField -Object $Tweak -FieldName 'FromGameMode') -or -not [bool]$Tweak.FromGameMode)
		{
			return [pscustomobject]@{
				Header = $null
				SortOrder = 99
			}
		}

		if ((Test-GuiObjectField -Object $Tweak -FieldName 'RequiresRestart') -and [bool]$Tweak.RequiresRestart)
		{
			return [pscustomobject]@{
				Header = 'Restart-Required Items'
				SortOrder = Get-GamingPreviewGroupSortOrder -GroupName 'Restart-Required Items'
			}
		}

		$groupName = if ((Test-GuiObjectField -Object $Tweak -FieldName 'GamingPreviewGroup')) { [string]$Tweak.GamingPreviewGroup } else { $null }
		return [pscustomobject]@{
			Header = $groupName
			SortOrder = Get-GamingPreviewGroupSortOrder -GroupName $groupName
		}
	}

	function Get-GameModeToggleStateLabel
	{
		param ([string]$ActionParam)

		switch -Regex ([string]$ActionParam)
		{
			'^\s*Enable\s*$' { return 'Enabled' }
			'^\s*Disable\s*$' { return 'Disabled' }
			'^\s*Show\s*$' { return 'Visible' }
			'^\s*Hide\s*$' { return 'Hidden' }
			default { return [string]$ActionParam }
		}
	}

	function Get-GameModeProfileDefaultSelection
	{
		param (
			[object]$Tweak,
			[string]$ProfileName
		)

		if (-not $Tweak -or [string]::IsNullOrWhiteSpace($ProfileName))
		{
			return $false
		}

		if (-not (Test-GameModeProfileDefaultEligible -Entry $Tweak))
		{
			return $false
		}

		if ((Test-GuiObjectField -Object $Tweak -FieldName 'GameModeDefaultByProfile') -and $null -ne $Tweak.GameModeDefaultByProfile)
		{
			$profileDefaults = $Tweak.GameModeDefaultByProfile
			if ($profileDefaults -is [System.Collections.IDictionary] -and $profileDefaults.Contains($ProfileName))
			{
				return [bool]$profileDefaults[$ProfileName]
			}
			if ($profileDefaults.PSObject -and $profileDefaults.PSObject.Properties[$ProfileName])
			{
				return [bool]$profileDefaults.$ProfileName
			}
		}

		if ((Test-GuiObjectField -Object $Tweak -FieldName 'GameModeDefault'))
		{
			return [bool]$Tweak.GameModeDefault
		}

		return $false
	}

	function New-GameModePlanEntry
	{
		param (
			[Parameter(Mandatory = $true)][hashtable]$Tweak,
			[Parameter(Mandatory = $true)][string]$ProfileName,
			[Parameter(Mandatory = $true)][string]$ToggleParam,
			[string]$ReasonIncluded,
			[ValidateSet('Apply', 'Undo')]
			[string]$Operation = 'Apply',
			[switch]$IsAdvanced,
			[string]$AdvancedCategory
		)

		$visual = Get-TweakVisualMetadata -Tweak $Tweak
		$scenarioTags = if ((Test-GuiObjectField -Object $Tweak -FieldName 'ScenarioTags') -and $Tweak.ScenarioTags) { @($Tweak.ScenarioTags) } else { @($visual.ScenarioTags) }
		$stateLabel = Get-GameModeToggleStateLabel -ActionParam $ToggleParam
		$stateDetail = "Game Mode will run '$ToggleParam' for this setting."
		$blastRadius = Get-TweakBlastRadiusText -Tweak $Tweak -TypeLabel $visual.TypeLabel -ScenarioTags $scenarioTags -MatchesDesired:$false
		$previewGroup = if ([bool]$IsAdvanced -and -not [string]::IsNullOrWhiteSpace($AdvancedCategory))
		{
			"Advanced: $AdvancedCategory"
		}
		elseif ((Test-GuiObjectField -Object $Tweak -FieldName 'GamingPreviewGroup'))
		{
			[string]$Tweak.GamingPreviewGroup
		}
		else
		{
			'Gaming'
		}

		return @{
			Key               = "gamemode::$([string]$Tweak.Function)"
			Index             = [string]$Tweak.Function
			Name              = [string]$Tweak.Name
			Function          = [string]$Tweak.Function
			Type              = if (-not [string]::IsNullOrWhiteSpace([string]$Tweak.Type)) { [string]$Tweak.Type } else { 'Toggle' }
			TypeKind          = [string]$visual.TypeKind
			TypeLabel         = [string]$visual.TypeLabel
			TypeBadgeLabel    = [string]$visual.TypeBadgeLabel
			TypeTone          = [string]$visual.TypeTone
			Category          = [string]$Tweak.Category
			Risk              = [string]$Tweak.Risk
			Restorable        = $Tweak.Restorable
			RecoveryLevel     = if ((Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel')) { [string]$Tweak.RecoveryLevel } else { $null }
			RequiresRestart   = [bool]$Tweak.RequiresRestart
			Impact            = $Tweak.Impact
			PresetTier        = $Tweak.PresetTier
			Selection         = [string]$ToggleParam
			ToggleParam       = [string]$ToggleParam
			OnParam           = [string]$Tweak.OnParam
			OffParam          = [string]$Tweak.OffParam
			IsChecked         = ([string]$ToggleParam -eq [string]$Tweak.OnParam)
			DefaultValue      = [bool]$Tweak.Default
			CurrentState      = $stateLabel
			CurrentStateTone  = 'Primary'
			StateDetail       = $stateDetail
			MatchesDesired    = $false
			ScenarioTags      = $scenarioTags
			ReasonIncluded    = if ([string]::IsNullOrWhiteSpace($ReasonIncluded)) { "Included by Game Mode ($ProfileName)." } else { $ReasonIncluded }
			BlastRadius       = [string]$blastRadius
			IsRemoval         = [bool]$visual.IsRemoval
			ExtraArgs         = $null
			GamingPreviewGroup = $previewGroup
			TroubleshootingOnly = if ((Test-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly')) { [bool]$Tweak.TroubleshootingOnly } else { $false }
			IsAdvanced        = [bool]$IsAdvanced
			AdvancedCategory  = if ([bool]$IsAdvanced) { $AdvancedCategory } else { $null }
			FromGameMode      = $true
			GameModeProfile   = [string]$ProfileName
			GameModeOperation = [string]$Operation
		}
	}

	function Get-GameModeUndoRunList
	{
		param (
			[object[]]$Results,
			[string]$ProfileName
		)

		$undoList = [System.Collections.Generic.List[hashtable]]::new()
		foreach ($result in @($Results | Where-Object {
			$_.Status -in @('Success', 'Restart pending') -and
			(Test-GuiObjectField -Object $_ -FieldName 'FromGameMode') -and
			[bool]$_.FromGameMode
		}))
		{
			$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function ([string]$result.Function)
			if (-not $manifestEntry) { continue }

			$undoParam = Get-DirectUndoCommandForEntry -Entry $result -ManifestEntry $manifestEntry
			if ([string]::IsNullOrWhiteSpace([string]$undoParam)) { continue }

			$reasonIncluded = if (-not [string]::IsNullOrWhiteSpace([string]$result.Selection))
			{
				"Reversible here: undo requested after Game Mode applied '$([string]$result.Selection)'."
			}
			else
			{
				'Reversible here: undo requested after the previous Game Mode run.'
			}

			[void]$undoList.Add((New-GameModePlanEntry -Tweak $manifestEntry -ProfileName $ProfileName -ToggleParam $undoParam -ReasonIncluded $reasonIncluded -Operation 'Undo'))
		}

		return @($undoList)
	}

	function Build-GameModeAdvancedPlanEntries
	{
		param (
			[string]$ProfileName,
			$TweakManifest = $null,
			$Selections = $null
		)

		if ([string]::IsNullOrWhiteSpace($ProfileName)) { return @() }

		$resolvedManifest = if ($null -ne $TweakManifest) { $TweakManifest } else { $Script:TweakManifest }
		$resolvedSelections = if ($null -ne $Selections) { $Selections } else { $Script:GameModeAdvancedSelections }

		$advancedEntries = @(Import-GameModeAdvancedData)
		$plan = [System.Collections.Generic.List[hashtable]]::new()

		foreach ($advEntry in $advancedEntries)
		{
			$fn = [string]$advEntry.Function
			if ([string]::IsNullOrWhiteSpace($fn)) { continue }
			if (-not $resolvedSelections.ContainsKey($fn) -or -not [bool]$resolvedSelections[$fn])
			{
				continue
			}

			$manifestEntry = Get-ManifestEntryByFunction -Manifest $resolvedManifest -Function $fn
			if (-not $manifestEntry) { continue }

			$applyValue = [string]$advEntry.ApplyValue
			$toggleParam = switch ($applyValue)
			{
				'Enable'  { [string]$manifestEntry.OnParam; break }
				'Disable' { [string]$manifestEntry.OffParam; break }
				default   { $applyValue }
			}
			if ([string]::IsNullOrWhiteSpace($toggleParam)) { continue }

			$advCategory = if ((Test-GuiObjectField -Object $advEntry -FieldName 'Category')) { [string]$advEntry.Category } else { 'Advanced' }
			$reasonIncluded = "Advanced option ($advCategory) added to the $ProfileName profile."

			[void]$plan.Add((New-GameModePlanEntry -Tweak $manifestEntry -ProfileName $ProfileName -ToggleParam $toggleParam -ReasonIncluded $reasonIncluded -IsAdvanced -AdvancedCategory $advCategory))
		}

		return @($plan)
	}

	function Build-GameModePlan
	{
		param (
			[ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
			[string]$ProfileName,
			$TweakManifest = $null,
			$Allowlist = $null
		)

		$resolvedManifest = if ($null -ne $TweakManifest) { $TweakManifest } else { $Script:TweakManifest }
		$plan = [System.Collections.Generic.List[hashtable]]::new()
		$decisionOverrides = @{}
		$showThemedDialogScript = if ($Script:ShowThemedDialogScript) { $Script:ShowThemedDialogScript } else { ${function:Show-ThemedDialog} }
		$advancedFunctions = @(Get-GameModeAdvancedFunctions)
		$advancedFunctionLookup = @{}
		foreach ($af in $advancedFunctions) { $advancedFunctionLookup[$af] = $true }
		$effectiveAllowlist = if ($null -ne $Allowlist) { @($Allowlist) } else { @($Script:GameModeAllowlist) }

		foreach ($promptDefinition in @(Get-GameModeDecisionPromptDefinitions -Manifest $resolvedManifest -ProfileName $ProfileName -Allowlist $effectiveAllowlist))
		{
			if (-not $promptDefinition) { continue }

			$promptKey = if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'Key')) { [string]$promptDefinition.Key } else { $null }
			if ([string]::IsNullOrWhiteSpace($promptKey)) { continue }

			$buttonSet = if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'Buttons')) { [string[]]@($promptDefinition.Buttons) } else { [string[]]@() }
			if ($buttonSet.Count -eq 0) { continue }

			$selectedChoice = & $showThemedDialogScript `
				-Title $(if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'Title')) { [string]$promptDefinition.Title } else { "Game Mode | $promptKey" }) `
				-Message $(if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'Message')) { [string]$promptDefinition.Message } else { 'Choose how Game Mode should handle this gaming setting.' }) `
				-Buttons $buttonSet `
				-AccentButton $(if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'AccentButton')) { [string]$promptDefinition.AccentButton } else { $null }) `
				-DestructiveButton $(if ((Test-GuiObjectField -Object $promptDefinition -FieldName 'DestructiveButton')) { [string]$promptDefinition.DestructiveButton } else { $null })

			if (-not [string]::IsNullOrWhiteSpace([string]$selectedChoice))
			{
				$decisionOverrides[$promptKey] = [string]$selectedChoice
			}
		}

		foreach ($selection in @(Get-GameModeSelectionSet -Manifest $resolvedManifest -ProfileName $ProfileName -DecisionOverrides $decisionOverrides -Allowlist $effectiveAllowlist))
		{
			if (-not $selection -or -not $selection.Entry) { continue }

			# Skip entries handled by the advanced options panel.
			if ($advancedFunctionLookup.ContainsKey([string]$selection.Function)) { continue }

			$reasonIncluded = switch ([string]$selection.SelectionSource)
			{
				'DecisionOverride'
				{
					"Included by Game Mode ($ProfileName) after you chose the '$([string]$selection.DecisionChoice)' path."
					break
				}
				default
				{
					"Included by Game Mode ($ProfileName) as part of the profile default plan."
					break
				}
			}

			[void]$plan.Add((New-GameModePlanEntry -Tweak $selection.Entry -ProfileName $ProfileName -ToggleParam ([string]$selection.ToggleParam) -ReasonIncluded $reasonIncluded))
		}

		$Script:GameModeDecisionOverrides = $decisionOverrides
		& $Script:SyncGameModeContextStateScript

		return @($plan)
	}

	function Test-TweakEditableInGameModeTab
	{
		param (
			[object]$Tweak
		)

		if (-not $Tweak)
		{
			return $false
		}

		$functionName = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Function')) { [string]$Tweak.Function } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($functionName) -and $Script:GamingCrossTabFunctions -and $Script:GamingCrossTabFunctions.Contains($functionName))
		{
			return $true
		}

		$categoryName = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Category')) { [string]$Tweak.Category } else { $null }
		if ([string]::IsNullOrWhiteSpace($categoryName))
		{
			return $false
		}

		$primaryTab = if ($CategoryToPrimary -and $CategoryToPrimary.ContainsKey($categoryName))
		{
			[string]$CategoryToPrimary[$categoryName]
		}
		else
		{
			$categoryName
		}

		return ([string]$primaryTab -eq 'Gaming')
	}

	function Sync-GameModePlanToGamingControls
	{
		param (
			[object[]]$Plan = $null
		)

		if (-not $Script:TweakManifest -or -not $Script:Controls)
		{
			return
		}

		$Script:GameModeControlSyncInProgress = $true
		try
		{
			$resolvedPlan = if ($null -ne $Plan) { @($Plan) } else { @($Script:GameModePlan) }
			$planLookup = @{}
			foreach ($planEntry in $resolvedPlan)
			{
				if (-not $planEntry) { continue }
				$functionName = if ((Test-GuiObjectField -Object $planEntry -FieldName 'Function')) { [string]$planEntry.Function } else { $null }
				if ([string]::IsNullOrWhiteSpace($functionName)) { continue }
				$planLookup[$functionName] = $planEntry
			}

			for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
			{
				$tweak = $Script:TweakManifest[$i]
				if (-not $tweak) { continue }
				if (-not (Test-TweakEditableInGameModeTab -Tweak $tweak)) { continue }

				$control = $Script:Controls[$i]
				if (-not $control) { continue }

				$functionName = [string]$tweak.Function
				$hasPlanEntry = $planLookup.ContainsKey($functionName)
				$planEntry = if ($hasPlanEntry) { $planLookup[$functionName] } else { $null }

				switch ([string]$tweak.Type)
				{
					'Toggle'
					{
						$targetChecked = $false
						if ($hasPlanEntry)
						{
							$targetToggleParam = if ((Test-GuiObjectField -Object $planEntry -FieldName 'ToggleParam')) { [string]$planEntry.ToggleParam } elseif ((Test-GuiObjectField -Object $planEntry -FieldName 'Selection')) { [string]$planEntry.Selection } else { $null }
							if (-not [string]::IsNullOrWhiteSpace($targetToggleParam))
							{
								$targetChecked = ([string]$targetToggleParam -eq [string]$tweak.OnParam)
							}
						}

						if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
						{
							$control.IsChecked = [bool]$targetChecked
						}

						if ($hasPlanEntry)
						{
							Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition ([pscustomobject]@{
								Function = $functionName
								Type = 'Toggle'
								State = $(if ($targetChecked) { 'On' } else { 'Off' })
								Source = 'GameMode'
							})
						}
						else
						{
							$existingDefinition = Get-GuiExplicitSelectionDefinition -FunctionName $functionName
							if ($existingDefinition -and (Test-GuiObjectField -Object $existingDefinition -FieldName 'Source') -and [string]$existingDefinition.Source -eq 'GameMode')
							{
								Remove-GuiExplicitSelectionDefinition -FunctionName $functionName
							}
						}
					}
					'Choice'
					{
						$targetSelectedIndex = -1
						if ($hasPlanEntry)
						{
							$targetValue = if ((Test-GuiObjectField -Object $planEntry -FieldName 'ToggleParam')) { [string]$planEntry.ToggleParam } elseif ((Test-GuiObjectField -Object $planEntry -FieldName 'Value')) { [string]$planEntry.Value } elseif ((Test-GuiObjectField -Object $planEntry -FieldName 'Selection')) { [string]$planEntry.Selection } else { $null }
							if (-not [string]::IsNullOrWhiteSpace($targetValue) -and $tweak.Options)
							{
								$targetSelectedIndex = [array]::IndexOf(@($tweak.Options), $targetValue)
							}
						}

						if ((Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
						{
							$control.SelectedIndex = [int]$targetSelectedIndex
						}

						if ($hasPlanEntry -and $targetSelectedIndex -ge 0)
						{
							Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition ([pscustomobject]@{
								Function = $functionName
								Type = 'Choice'
								Value = [string]@($tweak.Options)[$targetSelectedIndex]
								Source = 'GameMode'
							})
						}
						else
						{
							$existingDefinition = Get-GuiExplicitSelectionDefinition -FunctionName $functionName
							if ($existingDefinition -and (Test-GuiObjectField -Object $existingDefinition -FieldName 'Source') -and [string]$existingDefinition.Source -eq 'GameMode')
							{
								Remove-GuiExplicitSelectionDefinition -FunctionName $functionName
							}
						}
					}
					'Action'
					{
						if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
						{
							$control.IsChecked = [bool]$hasPlanEntry
						}

						if ($hasPlanEntry)
						{
							Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition ([pscustomobject]@{
								Function = $functionName
								Type = 'Action'
								Run = $true
								Source = 'GameMode'
							})
						}
						else
						{
							$existingDefinition = Get-GuiExplicitSelectionDefinition -FunctionName $functionName
							if ($existingDefinition -and (Test-GuiObjectField -Object $existingDefinition -FieldName 'Source') -and [string]$existingDefinition.Source -eq 'GameMode')
							{
								Remove-GuiExplicitSelectionDefinition -FunctionName $functionName
							}
						}
					}
				}
			}
		}
		finally
		{
			$Script:GameModeControlSyncInProgress = $false
		}
	}

	function Sync-GameModePlanFromGamingControls
	{
		# IMPORTANT: This function reads and writes WPF controls directly -
		# it must be called on the UI (dispatcher) thread. All current call
		# sites invoke it from UI-thread event handlers or timer callbacks.
		# Do NOT call from a background runspace or ThreadPool work item.
		if (-not [bool]$Script:GameMode -or [string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile))
		{
			return
		}
		if ($Script:GameModeControlSyncInProgress)
		{
			return
		}
		if (-not $Script:TweakManifest -or -not $Script:Controls)
		{
			return
		}

		$selectedGamingEntries = [System.Collections.Generic.List[hashtable]]::new()
		$selectedGamingLookup = @{}
		$currentPlanLookup = @{}
		foreach ($existingPlanEntry in @($Script:GameModePlan))
		{
			if (-not $existingPlanEntry) { continue }
			$existingFunction = if ((Test-GuiObjectField -Object $existingPlanEntry -FieldName 'Function')) { [string]$existingPlanEntry.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($existingFunction)) { continue }
			$currentPlanLookup[$existingFunction] = $existingPlanEntry
		}

		foreach ($selected in @(Get-SelectedTweakRunList -TweakManifest $Script:TweakManifest -Controls $Script:Controls))
		{
			if (-not $selected) { continue }
			if (-not (Test-TweakEditableInGameModeTab -Tweak $selected)) { continue }

			$functionName = if ((Test-GuiObjectField -Object $selected -FieldName 'Function')) { [string]$selected.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

			$reasonIncluded = if ((Test-GuiObjectField -Object $selected -FieldName 'ReasonIncluded') -and -not [string]::IsNullOrWhiteSpace([string]$selected.ReasonIncluded))
			{
				[string]$selected.ReasonIncluded
			}
			else
			{
				"Included by manual Gaming tab selection while Game Mode ($([string]$Script:GameModeProfile)) is active."
			}

			$planEntry = @{
				Key                = "gamemode::$functionName"
				Index              = $functionName
				Name               = if ((Test-GuiObjectField -Object $selected -FieldName 'Name')) { [string]$selected.Name } else { $functionName }
				Function           = $functionName
				Type               = if ((Test-GuiObjectField -Object $selected -FieldName 'Type')) { [string]$selected.Type } else { 'Toggle' }
				TypeKind           = if ((Test-GuiObjectField -Object $selected -FieldName 'TypeKind')) { [string]$selected.TypeKind } else { $null }
				TypeLabel          = if ((Test-GuiObjectField -Object $selected -FieldName 'TypeLabel')) { [string]$selected.TypeLabel } else { $null }
				TypeBadgeLabel     = if ((Test-GuiObjectField -Object $selected -FieldName 'TypeBadgeLabel')) { [string]$selected.TypeBadgeLabel } elseif ((Test-GuiObjectField -Object $selected -FieldName 'TypeLabel')) { [string]$selected.TypeLabel } else { $null }
				TypeTone           = if ((Test-GuiObjectField -Object $selected -FieldName 'TypeTone')) { [string]$selected.TypeTone } else { $null }
				Category           = if ((Test-GuiObjectField -Object $selected -FieldName 'Category')) { [string]$selected.Category } else { $null }
				Risk               = if ((Test-GuiObjectField -Object $selected -FieldName 'Risk')) { [string]$selected.Risk } else { 'Low' }
				Restorable         = if ((Test-GuiObjectField -Object $selected -FieldName 'Restorable')) { $selected.Restorable } else { $null }
				RecoveryLevel      = if ((Test-GuiObjectField -Object $selected -FieldName 'RecoveryLevel')) { [string]$selected.RecoveryLevel } else { $null }
				RequiresRestart    = if ((Test-GuiObjectField -Object $selected -FieldName 'RequiresRestart')) { [bool]$selected.RequiresRestart } else { $false }
				Impact             = if ((Test-GuiObjectField -Object $selected -FieldName 'Impact')) { $selected.Impact } else { $null }
				PresetTier         = if ((Test-GuiObjectField -Object $selected -FieldName 'PresetTier')) { $selected.PresetTier } else { $null }
				Selection          = if ((Test-GuiObjectField -Object $selected -FieldName 'Selection')) { [string]$selected.Selection } else { $null }
				ToggleParam        = if ((Test-GuiObjectField -Object $selected -FieldName 'ToggleParam')) { [string]$selected.ToggleParam } else { $null }
				OnParam            = if ((Test-GuiObjectField -Object $selected -FieldName 'OnParam')) { [string]$selected.OnParam } else { $null }
				OffParam           = if ((Test-GuiObjectField -Object $selected -FieldName 'OffParam')) { [string]$selected.OffParam } else { $null }
				IsChecked          = if ((Test-GuiObjectField -Object $selected -FieldName 'IsChecked')) { [bool]$selected.IsChecked } else { $false }
				DefaultValue       = if ((Test-GuiObjectField -Object $selected -FieldName 'DefaultValue')) { $selected.DefaultValue } else { $null }
				CurrentState       = if ((Test-GuiObjectField -Object $selected -FieldName 'CurrentState')) { [string]$selected.CurrentState } else { $null }
				CurrentStateTone   = if ((Test-GuiObjectField -Object $selected -FieldName 'CurrentStateTone')) { [string]$selected.CurrentStateTone } else { $null }
				StateDetail        = if ((Test-GuiObjectField -Object $selected -FieldName 'StateDetail')) { [string]$selected.StateDetail } else { $null }
				MatchesDesired     = if ((Test-GuiObjectField -Object $selected -FieldName 'MatchesDesired')) { [bool]$selected.MatchesDesired } else { $false }
				ScenarioTags       = if ((Test-GuiObjectField -Object $selected -FieldName 'ScenarioTags')) { @($selected.ScenarioTags) } else { @() }
				ReasonIncluded     = $reasonIncluded
				BlastRadius        = if ((Test-GuiObjectField -Object $selected -FieldName 'BlastRadius')) { [string]$selected.BlastRadius } else { $null }
				IsRemoval          = if ((Test-GuiObjectField -Object $selected -FieldName 'IsRemoval')) { [bool]$selected.IsRemoval } else { $false }
				ExtraArgs          = if ((Test-GuiObjectField -Object $selected -FieldName 'ExtraArgs')) { $selected.ExtraArgs } else { $null }
				GamingPreviewGroup = if ((Test-GuiObjectField -Object $selected -FieldName 'GamingPreviewGroup')) { [string]$selected.GamingPreviewGroup } else { 'Gaming' }
				TroubleshootingOnly = if ((Test-GuiObjectField -Object $selected -FieldName 'TroubleshootingOnly')) { [bool]$selected.TroubleshootingOnly } else { $false }
				FromGameMode       = $true
				GameModeProfile    = [string]$Script:GameModeProfile
				GameModeOperation  = 'Apply'
			}

			if ((Test-GuiObjectField -Object $selected -FieldName 'Value'))
			{
				$planEntry.Value = [string]$selected.Value
			}
			if ((Test-GuiObjectField -Object $selected -FieldName 'SelectedIndex'))
			{
				$planEntry.SelectedIndex = [int]$selected.SelectedIndex
			}
			if ((Test-GuiObjectField -Object $selected -FieldName 'SelectedValue'))
			{
				$planEntry.SelectedValue = [string]$selected.SelectedValue
			}

			if ($currentPlanLookup.ContainsKey($functionName))
			{
				$currentEntry = $currentPlanLookup[$functionName]
				if ((Test-GuiObjectField -Object $currentEntry -FieldName 'IsAdvanced'))
				{
					$planEntry.IsAdvanced = [bool]$currentEntry.IsAdvanced
				}
				if ((Test-GuiObjectField -Object $currentEntry -FieldName 'AdvancedCategory'))
				{
					$planEntry.AdvancedCategory = $currentEntry.AdvancedCategory
				}
			}

			$selectedGamingLookup[$functionName] = $true
			[void]$selectedGamingEntries.Add($planEntry)
		}

		$mergedPlan = [System.Collections.Generic.List[object]]::new()
		foreach ($existingPlanEntry in @($Script:GameModePlan))
		{
			if (-not $existingPlanEntry)
			{
				continue
			}

			$functionName = if ((Test-GuiObjectField -Object $existingPlanEntry -FieldName 'Function')) { [string]$existingPlanEntry.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($functionName))
			{
				[void]$mergedPlan.Add($existingPlanEntry)
				continue
			}

			$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function $functionName
			if (-not $manifestEntry)
			{
				if (-not $selectedGamingLookup.ContainsKey($functionName))
				{
					[void]$mergedPlan.Add($existingPlanEntry)
				}
				continue
			}

			if (-not (Test-TweakEditableInGameModeTab -Tweak $manifestEntry))
			{
				[void]$mergedPlan.Add($existingPlanEntry)
			}
		}

		foreach ($manualGamingEntry in $selectedGamingEntries)
		{
			[void]$mergedPlan.Add($manualGamingEntry)
		}

		$Script:GameModePlan = @($mergedPlan)
		& $Script:SyncGameModeContextStateScript

		$restartCount = @($Script:GameModePlan | Where-Object RequiresRestart).Count
		$message = if ($Script:GameModePlan.Count -gt 0) {
			"Game Mode profile ready: $($Script:GameModeProfile) ($($Script:GameModePlan.Count) action$(if ($Script:GameModePlan.Count -eq 1) { '' } else { 's' }) selected)."
		}
		else {
			"Game Mode profile selected: $($Script:GameModeProfile). No gaming changes were queued."
		}
		if ($restartCount -gt 0)
		{
			$message += " $restartCount change$(if ($restartCount -eq 1) { '' } else { 's' }) - restart required."
		}

		$Script:PresetStatusMessage = $message
		if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:PresetStatusBadge.Child.Text = $message
		}
		Update-GameModeStatusText -Message $message -Tone 'Accent'
	}

	function Clear-GameModePlan
	{
		param ([switch]$Quiet)

		& $Script:ResetGameModeStateScript
		& $Script:SyncGameModePlanToGamingControlsScript -Plan @()

		if ($Quiet) { return }

		$message = 'Game Mode plan cleared. Choose a profile to build a new gaming workflow.'
		$Script:PresetStatusMessage = $message
		if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:PresetStatusBadge.Child.Text = $message
		}
		& $Script:UpdateGameModeStatusTextScript -Message $message -Tone 'Muted'
	}

	function Set-GameModeProfile
	{
		param (
			[ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
			[string]$ProfileName
		)

		& $Script:SaveGuiUndoSnapshotScript
		$plan = @(& $Script:BuildGameModePlanScript -ProfileName $ProfileName)
		$Script:GameModeProfile = $ProfileName
		$Script:GameModeCorePlan = $plan
		$Script:GameModePlan = $plan

		# Initialize advanced selections: only Troubleshooting pre-checks items from DefaultCheckedByProfile.
		$Script:GameModeAdvancedSelections = @{}
		$advancedEntries = @(Import-GameModeAdvancedData)
		foreach ($advEntry in $advancedEntries)
		{
			$fn = [string]$advEntry.Function
			if ([string]::IsNullOrWhiteSpace($fn)) { continue }
			$isPreChecked = $false
			if ($ProfileName -eq 'Troubleshooting' -and (Test-GuiObjectField -Object $advEntry -FieldName 'DefaultCheckedByProfile') -and $advEntry.DefaultCheckedByProfile.PSObject.Properties[$ProfileName])
			{
				$isPreChecked = [bool]$advEntry.DefaultCheckedByProfile.$ProfileName
			}
			$Script:GameModeAdvancedSelections[$fn] = $isPreChecked
		}

		# Add pre-checked advanced items to the plan, replacing any core entries they override.
		$advancedPlanEntries = @(& $Script:BuildGameModeAdvancedPlanEntriesScript -ProfileName $ProfileName)
		if ($advancedPlanEntries.Count -gt 0)
		{
			$advFunctionLookup = @{}
			foreach ($ae in $advancedPlanEntries) { $advFunctionLookup[[string]$ae.Function] = $true }

			$merged = [System.Collections.Generic.List[object]]::new()
			foreach ($cp in @($Script:GameModeCorePlan))
			{
				if (-not $advFunctionLookup.ContainsKey([string]$cp.Function))
				{
					[void]$merged.Add($cp)
				}
			}
			foreach ($ae in $advancedPlanEntries) { [void]$merged.Add($ae) }
			$Script:GameModePlan = @($merged)
		}
		& $Script:SyncGameModeContextStateScript

		$restartCount = @($Script:GameModePlan | Where-Object RequiresRestart).Count
		$message = if ($Script:GameModePlan.Count -gt 0) {
			"Game Mode profile ready: $ProfileName ($($Script:GameModePlan.Count) action$(if ($Script:GameModePlan.Count -eq 1) { '' } else { 's' }) selected)."
		}
		else {
			"Game Mode profile selected: $ProfileName. No gaming changes were queued."
		}
		if ($restartCount -gt 0)
		{
			$message += " $restartCount change$(if ($restartCount -eq 1) { '' } else { 's' }) - restart required."
		}

		LogInfo ("Game Mode plan built: Profile={0}, Actions={1}, AdvancedActive={2}, Decisions={3}" -f $ProfileName, $Script:GameModePlan.Count, @($Script:GameModeAdvancedSelections.Values | Where-Object { $_ }).Count, (Get-GameModeDecisionOverridesText -Overrides $Script:GameModeDecisionOverrides))

		$Script:PresetStatusMessage = $message
		& $Script:SyncGameModeContextStateScript

		# Rebuild the tab and set status via unified orchestration.
		# Build-TweakRow reads $Script:GameModePlan directly to initialize checkbox state,
		# so the plan must be set before this call.
		& $Script:InvokeGuiStateTransitionScript -Context 'GameMode' `
			-ClearCache -RebuildTab -UpdatePresetBadge `
			-StatusMessage $message -StatusTone 'Accent'

		# Sync explicit selection definitions to the freshly-built controls.
		& $Script:SyncGameModePlanToGamingControlsScript
		& $Script:UpdateRunPathContextLabelScript
	}

	function Set-GameModeState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)

		# Use $Script: captures set during late-bind initialization in GUI.psm1.
		# Local ${function:} captures fail here because the WPF event handler
		# context can't resolve Show-TweakGUI's local-scope functions.

		$previousState = Test-GuiModeActive -Mode 'Game'
		$Script:FilterUiUpdating = $true
		try
		{
			$Script:GameMode = $Enabled
			# Track game mode state in session statistics
			Update-SessionStatistics -Values @{
				GameModeActive  = [bool]$Enabled
				GameModeProfile = if ($Enabled -and -not [string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { [string]$Script:GameModeProfile } else { $null }
			}
			if ($ChkGameMode)
			{
				$ChkGameMode.IsChecked = $Enabled
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		if ($previousState -eq $Enabled)
		{
			return
		}

		& $Script:ClearTabContentCacheScript

		if ($Enabled)
		{
			& $Script:SaveGuiUndoSnapshotScript
			if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag -and [string]$PrimaryTabs.SelectedItem.Tag -ne 'Gaming')
			{
				$Script:GameModePreviousPrimaryTab = [string]$PrimaryTabs.SelectedItem.Tag
			}

			$gamingTab = & $Script:GetPrimaryTabItemScript -Tag 'Gaming'
			if ($gamingTab)
			{
				if ($PrimaryTabs.SelectedItem -ne $gamingTab)
				{
					$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = $true
					$PrimaryTabs.SelectedItem = $gamingTab
				}
				else
				{
					& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
				}
			}
			else
			{
				& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
			}

			if ($PrimaryTabs)
			{
				foreach ($tab in $PrimaryTabs.Items)
				{
					if (($tab -is [System.Windows.Controls.TabItem]) -and [string]$tab.Tag -ne 'Gaming')
					{
						$tab.IsEnabled = $false
					}
				}
			}

			$message = "$([char]0x25C9) GAME MODE ACTIVE $([char]0x2014) only the Gaming plan can be edited or run. Turn off Game Mode to use other tabs."
		}
		else
		{
			if ($PrimaryTabs)
			{
				foreach ($tab in $PrimaryTabs.Items)
				{
					if ($tab -is [System.Windows.Controls.TabItem])
					{
						$tab.IsEnabled = $true
					}
				}
			}

			& $Script:ClearGameModePlanScript -Quiet
			$restoreTab = if ($Script:GameModePreviousPrimaryTab) { & $Script:GetPrimaryTabItemScript -Tag $Script:GameModePreviousPrimaryTab } else { $null }
			if ($restoreTab -and $PrimaryTabs.SelectedItem -and [string]$PrimaryTabs.SelectedItem.Tag -eq 'Gaming')
			{
				$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = $true
				$PrimaryTabs.SelectedItem = $restoreTab
			}
			else
			{
				& $Script:ClearTabContentCacheScript
				& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
			}

			$message = 'Game Mode disabled. Standard tweak selection restored.'
		}

		$Script:PresetStatusMessage = $message
		& $Script:SyncGameModeContextStateScript
		if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:PresetStatusBadge.Child.Text = $message
		}
		& $Script:UpdateGameModeStatusTextScript -Message $message -Tone $(if ($Enabled) { 'Toggle' } else { 'Muted' })
		if ($StatusText)
		{
			$StatusText.FontWeight = if ($Enabled) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal }
		}
		if ($BtnRun)
		{
			$BtnRun.ToolTip = if ($Enabled) { Get-UxRunActionToolTip } else { $null }
		}
		& $Script:UpdateRunPathContextLabelScript
	}

	function New-GameModeAdvancedPanel
	{
		param ([string]$ProfileName)

		if ([string]::IsNullOrWhiteSpace($ProfileName)) { return $null }

		$advancedEntries = @(Import-GameModeAdvancedData)
		if ($advancedEntries.Count -eq 0) { return $null }

		# Build lookup of core plan functions and their raw toggle params for overlap detection.
		# Entries already in the core plan with the same action direction are hidden from
		# the advanced panel. Entries with a different action (overrides) are shown.
		$corePlanActionLookup = @{}
		foreach ($cp in @($Script:GameModeCorePlan))
		{
			if (-not $cp) { continue }
			$hasFunction = $false
			$hasToggleParam = $false

			if ($cp -is [System.Collections.IDictionary])
			{
				$hasFunction = $cp.Contains('Function')
				$hasToggleParam = $cp.Contains('ToggleParam')
			}
			elseif ($cp.PSObject -and $cp.PSObject.Properties)
			{
				$hasFunction = [bool](Test-GuiObjectField -Object $cp -FieldName 'Function')
				$hasToggleParam = [bool](Test-GuiObjectField -Object $cp -FieldName 'ToggleParam')
			}

			if ($hasFunction -and $hasToggleParam)
			{
				$corePlanActionLookup[[string]$cp.Function] = [string]$cp.ToggleParam
			}
		}

		# Filter to entries that should be visible in the advanced panel for this profile.
		$visibleEntries = [System.Collections.Generic.List[object]]::new()
		foreach ($advEntry in $advancedEntries)
		{
			$fn = [string]$advEntry.Function
			if ([string]::IsNullOrWhiteSpace($fn)) { continue }

			if ($corePlanActionLookup.ContainsKey($fn))
			{
				# Core plan already includes this function - check if the advanced entry is an override.
				# Compare ApplyValue directly against the core plan's raw ToggleParam.
				# For Toggle entries, both use "Enable"/"Disable". For Choice entries, both use
				# the same choice value string (e.g., "Disable", "High").
				if ([string]$advEntry.ApplyValue -eq $corePlanActionLookup[$fn])
				{
					# Same action already in core plan - skip (already covered).
					continue
				}
			}

			[void]$visibleEntries.Add($advEntry)
		}

		if ($visibleEntries.Count -eq 0) { return $null }

		$bc = & $Script:NewSafeBrushConverterScript -Context 'New-GameModeAdvancedPanel'

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$border.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
		$border.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)

		$outerStack = New-Object System.Windows.Controls.StackPanel
		$outerStack.Orientation = 'Vertical'

		# Header row with title and toggle button.
		$headerGrid = New-Object System.Windows.Controls.Grid
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))

		$headerStack = New-Object System.Windows.Controls.StackPanel
		$headerStack.Orientation = 'Vertical'
		[System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

		$header = New-Object System.Windows.Controls.TextBlock
		$header.Text = 'ADVANCED GAME MODE OPTIONS'
		$header.FontSize = $Script:GuiLayout.FontSizeLabel
		$header.FontWeight = [System.Windows.FontWeights]::Bold
		$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($headerStack.Children.Add($header))

		$activeCount = @($Script:GameModeAdvancedSelections.Values | Where-Object { $_ }).Count
		$summaryLine = New-Object System.Windows.Controls.TextBlock
		$summaryLine.Text = "$($visibleEntries.Count) advanced option$(if ($visibleEntries.Count -eq 1) { '' } else { 's' }) available$(if ($activeCount -gt 0) { ", $activeCount active" } else { '' })."
		$summaryLine.FontSize = $Script:GuiLayout.FontSizeSmall
		$summaryLine.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$summaryLine.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		[void]($headerStack.Children.Add($summaryLine))
		[void]($headerGrid.Children.Add($headerStack))

		$toggleButton = New-Object System.Windows.Controls.Button
		$toggleButton.Content = Get-UxLocalizedString -Key 'GuiShowOptions' -Fallback 'Show options'
		$toggleButton.FontSize = $Script:GuiLayout.FontSizeLabel
		$toggleButton.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$toggleButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$toggleButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		Set-ButtonChrome -Button $toggleButton -Variant 'Subtle' -Compact
		[System.Windows.Controls.Grid]::SetColumn($toggleButton, 1)
		[void]($headerGrid.Children.Add($toggleButton))
		[void]($outerStack.Children.Add($headerGrid))

		# Collapsible details panel.
		$detailsPanel = New-Object System.Windows.Controls.StackPanel
		$detailsPanel.Orientation = 'Vertical'
		$detailsPanel.Visibility = [System.Windows.Visibility]::Collapsed
		$detailsPanel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)

		$noteText = New-Object System.Windows.Controls.TextBlock
		$noteText.Text = 'These options are not part of the standard profile plan. Check the ones you want to include.'
		$noteText.TextWrapping = 'Wrap'
		$noteText.FontSize = $Script:GuiLayout.FontSizeSmall
		$noteText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$noteText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($detailsPanel.Children.Add($noteText))

		# Group visible entries by Category.
		$groupedEntries = @{}
		$categoryOrder = [System.Collections.Generic.List[string]]::new()
		foreach ($advEntry in $visibleEntries)
		{
			$cat = if ((Test-GuiObjectField -Object $advEntry -FieldName 'Category')) { [string]$advEntry.Category } else { 'Other' }
			if (-not $groupedEntries.ContainsKey($cat))
			{
				$groupedEntries[$cat] = [System.Collections.Generic.List[object]]::new()
				[void]$categoryOrder.Add($cat)
			}
			[void]$groupedEntries[$cat].Add($advEntry)
		}

		$clearTabContentCacheScript = $Script:ClearTabContentCacheScript
		$updateCurrentTabContentScript = $Script:UpdateCurrentTabContentScript
		$buildAdvancedPlanEntriesScript = $Script:BuildGameModeAdvancedPlanEntriesScript
		$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
		$syncGameModeContextStateScript = $Script:SyncGameModeContextStateScript
		$syncGameModePlanToGamingControlsScript = $Script:SyncGameModePlanToGamingControlsScript
		$gameModeAdvancedSelectionsRef = $Script:GameModeAdvancedSelections
		$gameModeCorePlanRef = $Script:GameModeCorePlan
		# Getter/setter bound to module scope — .GetNewClosure() closures can't
		# access $Script:GameModePlan directly because $Script: targets the dynamic module.
		$getGameModePlanScript = { @($Script:GameModePlan) }
		$setGameModePlanScript = { param($NewPlan) $Script:GameModePlan = $NewPlan }

		foreach ($cat in $categoryOrder)
		{
			$catHeader = New-Object System.Windows.Controls.TextBlock
			$catHeader.Text = [string]$cat
			$catHeader.FontSize = $Script:GuiLayout.FontSizeLabel
			$catHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
			$catHeader.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			$catHeader.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
			[void]($detailsPanel.Children.Add($catHeader))

			foreach ($advEntry in $groupedEntries[$cat])
			{
				$fn = [string]$advEntry.Function
				if ([string]::IsNullOrWhiteSpace($fn)) { continue }

				$entryPanel = New-Object System.Windows.Controls.StackPanel
				$entryPanel.Orientation = 'Vertical'
				$entryPanel.Margin = [System.Windows.Thickness]::new(4, 2, 0, 6)

				$chk = New-Object System.Windows.Controls.CheckBox
				$chk.FontSize = $Script:GuiLayout.FontSizeLabel
				$chk.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)

				# Build label with optional recommended indicator.
				$isChecked = if ($Script:GameModeAdvancedSelections.ContainsKey($fn)) { [bool]$Script:GameModeAdvancedSelections[$fn] } else { $false }
				$isRecommended = $false
				if ((Test-GuiObjectField -Object $advEntry -FieldName 'DefaultCheckedByProfile') -and $advEntry.DefaultCheckedByProfile.PSObject.Properties[$ProfileName])
				{
					$isRecommended = [bool]$advEntry.DefaultCheckedByProfile.$ProfileName
				}

				$label = [string]$advEntry.Label
				$isOverride = $corePlanActionLookup.ContainsKey($fn)
				if ($isOverride)
				{
					$label += '  (overrides profile default)'
				}
				elseif ($isRecommended -and -not $isChecked)
				{
					$label += '  (recommended)'
				}
				$chk.Content = $label
				$chk.IsChecked = $isChecked

				$risk = if ((Test-GuiObjectField -Object $advEntry -FieldName 'Risk')) { [string]$advEntry.Risk } else { 'Low' }
				if ($risk -eq 'High')
				{
					$chk.ToolTip = "[High risk] $([string]$advEntry.Description)"
				}
				else
				{
					$chk.ToolTip = [string]$advEntry.Description
				}

				$capturedFunction = $fn
				$capturedProfileName = $ProfileName
				$null = Register-GuiEventHandler -Source $chk -EventName 'Checked' -Handler ({
					try
					{
						$gameModeAdvancedSelectionsRef[$capturedFunction] = $true

						# Rebuild plan from current live plan (preserving manual Gaming-tab
						# selections) + advanced entries, with override support.
						$advPlan = @(& $buildAdvancedPlanEntriesScript -ProfileName $capturedProfileName)
						$advFnLookup = @{}
						foreach ($ap in $advPlan) { $advFnLookup[[string]$ap.Function] = $true }

						$currentLivePlan = @(& $getGameModePlanScript)
						$merged = [System.Collections.Generic.List[object]]::new()
							foreach ($cp in $currentLivePlan)
							{
								if (-not $cp) { continue }
								# Drop old advanced entries (they'll be rebuilt) and entries
								# whose function is being overridden by a new advanced entry.
								$isOldAdvanced = (Test-GuiObjectField -Object $cp -FieldName 'IsAdvanced') -and [bool]$cp.IsAdvanced
								if ($isOldAdvanced) { continue }
								$cpFn = if ((Test-GuiObjectField -Object $cp -FieldName 'Function')) { [string]$cp.Function } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($cpFn) -and $advFnLookup.ContainsKey($cpFn)) { continue }
								[void]$merged.Add($cp)
							}
							foreach ($ap in $advPlan) { [void]$merged.Add($ap) }
							& $setGameModePlanScript -NewPlan @($merged)
							& $syncGameModeContextStateScript
							& $syncGameModePlanToGamingControlsScript

						& $clearTabContentCacheScript
						& $updateCurrentTabContentScript
					}
					catch
					{
						if ($showGuiRuntimeFailureScript) { & $showGuiRuntimeFailureScript -Context 'AdvancedPanel/Checked' -Exception $_.Exception }
					}
				}.GetNewClosure())

				$null = Register-GuiEventHandler -Source $chk -EventName 'Unchecked' -Handler ({
					try
					{
						$gameModeAdvancedSelectionsRef[$capturedFunction] = $false

						# Rebuild plan from current live plan (preserving manual Gaming-tab
						# selections) + remaining advanced entries, restoring overridden entries.
						$advPlan = @(& $buildAdvancedPlanEntriesScript -ProfileName $capturedProfileName)
						$advFnLookup = @{}
						foreach ($ap in $advPlan) { $advFnLookup[[string]$ap.Function] = $true }

						$currentLivePlan = @(& $getGameModePlanScript)
						$merged = [System.Collections.Generic.List[object]]::new()
							foreach ($cp in $currentLivePlan)
							{
								if (-not $cp) { continue }
								# Drop old advanced entries (they'll be rebuilt) and entries
								# whose function is being overridden by a new advanced entry.
								$isOldAdvanced = (Test-GuiObjectField -Object $cp -FieldName 'IsAdvanced') -and [bool]$cp.IsAdvanced
								if ($isOldAdvanced) { continue }
								$cpFn = if ((Test-GuiObjectField -Object $cp -FieldName 'Function')) { [string]$cp.Function } else { $null }
								if (-not [string]::IsNullOrWhiteSpace($cpFn) -and $advFnLookup.ContainsKey($cpFn)) { continue }
								[void]$merged.Add($cp)
							}
							# When an advanced item is unchecked and it was overriding a core plan entry,
							# restore the original core entry so the profile default is not lost.
							foreach ($corePlanEntry in @($gameModeCorePlanRef))
							{
								if (-not $corePlanEntry) { continue }
								$coreFn = if ((Test-GuiObjectField -Object $corePlanEntry -FieldName 'Function')) { [string]$corePlanEntry.Function } else { $null }
								if ([string]::IsNullOrWhiteSpace($coreFn)) { continue }
								# Only restore if this function was removed (was overridden by the advanced entry being unchecked)
								# and is not already present in the merged plan.
								$alreadyInMerged = $false
								foreach ($m in $merged) {
									if ($m -and (Test-GuiObjectField -Object $m -FieldName 'Function') -and [string]$m.Function -eq $coreFn) { $alreadyInMerged = $true; break }
								}
								if (-not $alreadyInMerged -and -not $advFnLookup.ContainsKey($coreFn))
								{
									[void]$merged.Add($corePlanEntry)
								}
							}
							foreach ($ap in $advPlan) { [void]$merged.Add($ap) }
							& $setGameModePlanScript -NewPlan @($merged)
							& $syncGameModeContextStateScript
							& $syncGameModePlanToGamingControlsScript

						& $clearTabContentCacheScript
						& $updateCurrentTabContentScript
					}
					catch
					{
						if ($showGuiRuntimeFailureScript) { & $showGuiRuntimeFailureScript -Context 'AdvancedPanel/Unchecked' -Exception $_.Exception }
					}
				}.GetNewClosure())

				[void]($entryPanel.Children.Add($chk))

				$desc = New-Object System.Windows.Controls.TextBlock
				$desc.Text = [string]$advEntry.Description
				$desc.TextWrapping = 'Wrap'
				$desc.FontSize = $Script:GuiLayout.FontSizeSmall
				$desc.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
				$desc.Margin = [System.Windows.Thickness]::new(20, 0, 0, 0)
				[void]($entryPanel.Children.Add($desc))

				if ((Test-GuiObjectField -Object $advEntry -FieldName 'TroubleshootingOnly') -and [bool]$advEntry.TroubleshootingOnly)
				{
					$troubleLabel = New-Object System.Windows.Controls.TextBlock
					$troubleLabel.Text = 'Troubleshooting only'
					$troubleLabel.FontSize = $Script:GuiLayout.FontSizeTiny
					$troubleLabel.FontStyle = [System.Windows.FontStyles]::Italic
					$troubleLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
					$troubleLabel.Margin = [System.Windows.Thickness]::new(20, 2, 0, 0)
					[void]($entryPanel.Children.Add($troubleLabel))
				}

				[void]($detailsPanel.Children.Add($entryPanel))
			}
		}

		$getUxLocalizedStringScript = ${function:Get-UxLocalizedString}
		$null = Register-GuiEventHandler -Source $toggleButton -EventName 'Click' -Handler ({
			$showDetails = ($detailsPanel.Visibility -ne [System.Windows.Visibility]::Visible)
			$detailsPanel.Visibility = if ($showDetails) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			$toggleButton.Content = if ($showDetails) { (& $getUxLocalizedStringScript -Key 'GuiHideOptions' -Fallback 'Hide options') } else { (& $getUxLocalizedStringScript -Key 'GuiShowOptions' -Fallback 'Show options') }
		}.GetNewClosure())

		[void]($outerStack.Children.Add($detailsPanel))
		$border.Child = $outerStack
		return $border
	}

	function New-GameModeLandingPanel
	{
		$bc = & $Script:NewSafeBrushConverterScript -Context 'New-GameModeLandingPanel'
		$panel = New-Object System.Windows.Controls.Border
		$panel.Background = $bc.ConvertFromString($Script:CurrentTheme.PresetPanelBg)
		$panel.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.PresetPanelBorder)
		$panel.BorderThickness = [System.Windows.Thickness]::new(1)
		$panel.CornerRadius = [System.Windows.CornerRadius]::new(10)
		$panel.Margin = [System.Windows.Thickness]::new(8, 12, 8, 8)
		$panel.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'

		$header = New-Object System.Windows.Controls.TextBlock
		$header.Text = (Get-UxLocalizedString -Key 'GuiGameModeHeader' -Fallback 'Game Mode')
		$header.FontSize = $Script:GuiLayout.FontSizeTitle
		$header.FontWeight = [System.Windows.FontWeights]::Bold
		$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		[void]($stack.Children.Add($header))
		$subheader = New-Object System.Windows.Controls.TextBlock
		$subheader.Text = 'Choose a gaming profile, answer a few focused prompts, then preview a manifest-backed gaming plan before you run anything.'
		$subheader.FontSize = $Script:GuiLayout.FontSizeLabel
		$subheader.TextWrapping = 'Wrap'
		$subheader.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$subheader.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($stack.Children.Add($subheader))
		$scopeNote = New-Object System.Windows.Controls.TextBlock
		$scopeNote.Text = 'Profiles build a focused plan from core gaming items plus reviewed cross-category entries. Advanced options are available in a separate expander for experienced users.'
		$scopeNote.FontSize = $Script:GuiLayout.FontSizeSmall
		$scopeNote.TextWrapping = 'Wrap'
		$scopeNote.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$scopeNote.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($stack.Children.Add($scopeNote))
		$recommendationNote = New-Object System.Windows.Controls.TextBlock
		$recommendationNote.Text = 'System Scan can highlight Game Mode when it sees gaming-related hardware or software, but those detections only adjust recommendation copy in v1 and never change profile defaults automatically.'
		$recommendationNote.FontSize = $Script:GuiLayout.FontSizeSmall
		$recommendationNote.TextWrapping = 'Wrap'
		$recommendationNote.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$recommendationNote.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($stack.Children.Add($recommendationNote))
		$profileCards = New-Object System.Windows.Controls.WrapPanel
		$profileCards.Orientation = 'Horizontal'
		$profileCards.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
		$setGameModeProfileScript = $Script:SetGameModeProfileScript

		foreach ($profileDefinition in @(Get-GameModeProfileDefinitions))
		{
			$card = New-Object System.Windows.Controls.Border
			$isActiveProfile = ([string]$Script:GameModeProfile -eq [string]$profileDefinition.Name)
			$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
			$card.BorderBrush = $bc.ConvertFromString($(if ($isActiveProfile) { $Script:CurrentTheme.ActiveTabBorder } else { $Script:CurrentTheme.PresetPanelBorder }))
			$card.BorderThickness = [System.Windows.Thickness]::new($(if ($isActiveProfile) { 2 } else { 1 }))
			$card.CornerRadius = [System.Windows.CornerRadius]::new(10)
			$card.Padding = [System.Windows.Thickness]::new(12, 12, 12, 12)
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 12, 12)
			$card.MinWidth = 210
			$card.MaxWidth = 250

			$cardStack = New-Object System.Windows.Controls.StackPanel
			$cardStack.Orientation = 'Vertical'

			$title = New-Object System.Windows.Controls.TextBlock
			$title.Text = [string]$profileDefinition.Label
			$title.FontSize = $Script:GuiLayout.FontSizeSubheading
			$title.FontWeight = [System.Windows.FontWeights]::SemiBold
			$title.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			[void]($cardStack.Children.Add($title))
			$summary = New-Object System.Windows.Controls.TextBlock
			$summary.Text = [string]$profileDefinition.Summary
			$summary.TextWrapping = 'Wrap'
			$summary.FontSize = $Script:GuiLayout.FontSizeSmall
			$summary.Margin = [System.Windows.Thickness]::new(0, 6, 0, 10)
			$summary.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
			[void]($cardStack.Children.Add($summary))
			$button = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiBuildProfile' -Fallback 'Build Profile') -Variant $(if ([string]$Script:GameModeProfile -eq [string]$profileDefinition.Name) { 'Primary' } else { 'Secondary' }) -Compact
			$profileName = [string]$profileDefinition.Name
			$null = Register-GuiEventHandler -Source $button -EventName 'Click' -Handler ({
				try
				{
					& $setGameModeProfileScript -ProfileName $profileName
				}
				catch
				{
					$errorLog = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline_GameMode_Error.log'
					$logLines = @(
						"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] GameMode/BuildProfile($profileName)"
						"Message: $($_.Exception.Message)"
						"Type: $($_.Exception.GetType().FullName)"
						"Script stack trace:"
						$_.ScriptStackTrace
						"---"
					)
					$logLines -join "`r`n" | Out-File -FilePath $errorLog -Encoding utf8 -Force
					Write-Warning ("Game Mode error logged to: $errorLog")
					throw
				}
			}.GetNewClosure())
			[void]($cardStack.Children.Add($button))
			$card.Child = $cardStack
			[void]($profileCards.Children.Add($card))
		}

		[void]($stack.Children.Add($profileCards))
		$planBorder = New-Object System.Windows.Controls.Border
		$planBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$planBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$planBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$planBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$planBorder.Padding = [System.Windows.Thickness]::new(12, 12, 12, 12)
		$planBorder.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)

		$planStack = New-Object System.Windows.Controls.StackPanel
		$planStack.Orientation = 'Vertical'

		$planHeader = New-Object System.Windows.Controls.TextBlock
		$planHeader.Text = 'Current Game Mode Plan'
		$planHeader.FontSize = $Script:GuiLayout.FontSizeSubheading
		$planHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
		$planHeader.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		[void]($planStack.Children.Add($planHeader))
		if ($Script:GameModePlan -and @($Script:GameModePlan).Count -gt 0)
		{
			$planSummary = Get-TweakSelectionSummary -SelectedTweaks @($Script:GameModePlan)
			$summaryText = New-Object System.Windows.Controls.TextBlock
			$summaryText.Text = "Profile: $($Script:GameModeProfile). $(@($Script:GameModePlan).Count) action$(if (@($Script:GameModePlan).Count -eq 1) { '' } else { 's' }) queued."
			$summaryText.TextWrapping = 'Wrap'
			$summaryText.FontSize = $Script:GuiLayout.FontSizeSmall
			$summaryText.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
			$summaryText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
			[void]($planStack.Children.Add($summaryText))
			$impactItems = New-Object System.Collections.Generic.List[object]
			[void]$impactItems.Add([pscustomobject]@{
				Label = "Selected: $($planSummary.SelectedCount)"
				Tone = 'Primary'
				ToolTip = 'Actions in the current Game Mode plan'
			})
			[void]$impactItems.Add([pscustomobject]@{
				Label = "Restart required: $($planSummary.RestartRequiredCount)"
				Tone = 'Caution'
				ToolTip = 'Changes that need a reboot'
			})
			[void]$impactItems.Add([pscustomobject]@{
				Label = "High risk: $($planSummary.HighRiskCount)"
				Tone = $(if ($planSummary.HighRiskCount -gt 0) { 'Danger' } else { 'Muted' })
				ToolTip = 'High-risk changes in this profile'
			})
			[void]$impactItems.Add([pscustomobject]@{
				Label = "Reversible here: $($planSummary.DirectUndoEligibleCount)"
				Tone = 'Success'
				ToolTip = 'Changes that are reversible here in Baseline'
			})
			[void]$impactItems.Add([pscustomobject]@{
				Label = "Restore point: $(if ($planSummary.ShouldRecommendRestorePoint) { 'Yes' } else { 'No' })"
				Tone = $(if ($planSummary.ShouldRecommendRestorePoint) { if ($planSummary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
				ToolTip = $(if ($planSummary.ShouldRecommendRestorePoint) { [string]$planSummary.RestoreRecommendation } else { 'Not recommended for this plan.' })
			})
			$impactPanel = GUICommon\New-DialogMetadataPillPanel -Theme $Script:CurrentTheme -Items $impactItems
			if ($impactPanel)
			{
				$impactPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
				[void]($planStack.Children.Add($impactPanel))
			}

			if ($planSummary.ShouldRecommendRestorePoint -and -not [string]::IsNullOrWhiteSpace([string]$planSummary.RestoreRecommendation))
			{
				$restoreBanner = New-Object System.Windows.Controls.Border
				$restoreBanner.Background = $bc.ConvertFromString($Script:CurrentTheme.PanelBg)
				$restoreBanner.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CautionBorder)
				$restoreBanner.BorderThickness = [System.Windows.Thickness]::new(1)
				$restoreBanner.CornerRadius = [System.Windows.CornerRadius]::new(8)
				$restoreBanner.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
				$restoreBanner.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)

				$restoreBannerText = New-Object System.Windows.Controls.TextBlock
				$restoreBannerText.Text = [string]$planSummary.RestoreRecommendation
				$restoreBannerText.TextWrapping = 'Wrap'
				$restoreBannerText.FontSize = $Script:GuiLayout.FontSizeSmall
				$restoreBannerText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$restoreBanner.Child = $restoreBannerText
				[void]($planStack.Children.Add($restoreBanner))
			}

			$groupSummaryItems = New-Object System.Collections.Generic.List[object]
			foreach ($planGroup in @($Script:GameModePlan | Group-Object GamingPreviewGroup | Sort-Object @{ Expression = { Get-GamingPreviewGroupSortOrder -GroupName ([string]$_.Name) } }, Name))
			{
				[void]$groupSummaryItems.Add([pscustomobject]@{
					Label = ('{0}: {1}' -f [string]$planGroup.Name, [int]$planGroup.Count)
					Tone = 'Primary'
					ToolTip = 'Grouped preview count'
				})
			}
			$groupSummaryPanel = GUICommon\New-DialogMetadataPillPanel -Theme $Script:CurrentTheme -Items $groupSummaryItems
			if ($groupSummaryPanel)
			{
				$groupSummaryPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
				[void]($planStack.Children.Add($groupSummaryPanel))
			}

			$actionRow = New-Object System.Windows.Controls.WrapPanel
			$actionRow.Orientation = 'Horizontal'
			$actionRow.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)

			$showSelectedTweakPreviewScript = $Script:ShowSelectedTweakPreviewScript
			$getGameModePlanScript = { @($Script:GameModePlan) }
			$previewButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiPreviewGameMode' -Fallback 'Preview Game Mode') -Variant 'Primary' -Compact
			if (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiButtonIconContent -Button $previewButton -IconName 'PreviewRun' -Text (Get-UxLocalizedString -Key 'GuiPreviewGameMode' -Fallback 'Preview Game Mode') -ToolTip 'Preview the current Game Mode plan.'
			}
			$null = Register-GuiEventHandler -Source $previewButton -EventName 'Click' -Handler ({
				& $showSelectedTweakPreviewScript -SelectedTweaks (& $getGameModePlanScript)
			}.GetNewClosure())
			[void]($actionRow.Children.Add($previewButton))
			$clearGameModePlanScript = $Script:ClearGameModePlanScript
			$updateCurrentTabContentScript = $Script:UpdateCurrentTabContentScript
			$clearButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiClearPlan' -Fallback 'Clear Plan') -Variant 'Subtle' -Compact -Muted
			if (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiButtonIconContent -Button $clearButton -IconName 'Clear' -Text (Get-UxLocalizedString -Key 'GuiClearPlan' -Fallback 'Clear Plan') -ToolTip 'Clear the current Game Mode plan.'
			}
			$clearButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
			$null = Register-GuiEventHandler -Source $clearButton -EventName 'Click' -Handler ({
				& $clearGameModePlanScript
				& $updateCurrentTabContentScript -SkipIdlePrebuild
			}.GetNewClosure())
			[void]($actionRow.Children.Add($clearButton))
			[void]($planStack.Children.Add($actionRow))
		}
		else
		{
			$emptyText = New-Object System.Windows.Controls.TextBlock
			$emptyText.Text = 'No gaming plan is active yet. Pick a profile above to answer the decision prompts and generate a preview-ready selection set.'
			$emptyText.TextWrapping = 'Wrap'
			$emptyText.FontSize = $Script:GuiLayout.FontSizeSmall
			$emptyText.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
			$emptyText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
			[void]($planStack.Children.Add($emptyText))
		}

		$planBorder.Child = $planStack
		[void]($stack.Children.Add($planBorder))

		# Advanced Options expander - collapsed by default, shown when a profile is selected.
		# Gated in Safe Mode: expert-only advanced options are hidden for beginners.
		if (-not (Test-IsSafeModeUX) -and -not [string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile))
		{
			$advancedPanel = New-GameModeAdvancedPanel -ProfileName ([string]$Script:GameModeProfile)
			if ($advancedPanel)
			{
				[void]($stack.Children.Add($advancedPanel))
			}
		}

		# Profile comparison section - collapsible expander below profile cards.
		$newGameModeComparisonPanelScript = if ($Script:NewGameModeComparisonPanelScript) { $Script:NewGameModeComparisonPanelScript } else { ${function:New-GameModeComparisonPanel} }
		if ($newGameModeComparisonPanelScript)
		{
			$comparisonPanel = & $newGameModeComparisonPanelScript
			if ($comparisonPanel)
			{
				[void]($stack.Children.Add($comparisonPanel))
			}
		}

		$panel.Child = $stack
		return $panel
	}

	function New-GameModeComparisonPanel
	{
		$bc = & $Script:NewSafeBrushConverterScript -Context 'New-GameModeComparisonPanel'
		$profiles = @(Get-GameModeProfileDefinitions)
		if ($profiles.Count -lt 2) { return $null }

		$manifestEntries = @(Get-GameModeManifestEntries)
		$advancedData = Import-GameModeAdvancedData
		if ($manifestEntries.Count -eq 0) { return $null }

		# Outer expander border
		$expanderBorder = New-Object System.Windows.Controls.Border
		$expanderBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$expanderBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$expanderBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$expanderBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$expanderBorder.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
		$expanderBorder.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)

		$expanderStack = New-Object System.Windows.Controls.StackPanel
		$expanderStack.Orientation = 'Vertical'

		# Header row (clickable to toggle)
		$headerRow = New-Object System.Windows.Controls.DockPanel
		$headerRow.Cursor = [System.Windows.Input.Cursors]::Hand

		$headerText = New-Object System.Windows.Controls.TextBlock
		$headerText.Text = 'Compare Profiles'
		$headerText.FontSize = $Script:GuiLayout.FontSizeSubheading
		$headerText.FontWeight = [System.Windows.FontWeights]::SemiBold
		$headerText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		[System.Windows.Controls.DockPanel]::SetDock($headerText, [System.Windows.Controls.Dock]::Left)
		[void]($headerRow.Children.Add($headerText))

		$toggleText = New-Object System.Windows.Controls.TextBlock
		$toggleText.Text = 'Show'
		$toggleText.FontSize = $Script:GuiLayout.FontSizeSmall
		$toggleText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.AccentBlue)
		$toggleText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
		$toggleText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		[void]($headerRow.Children.Add($toggleText))

		[void]($expanderStack.Children.Add($headerRow))

		# Content area (initially collapsed)
		$contentPanel = New-Object System.Windows.Controls.StackPanel
		$contentPanel.Orientation = 'Vertical'
		$contentPanel.Visibility = [System.Windows.Visibility]::Collapsed
		$contentPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)

		# Profile selectors
		$selectorRow = New-Object System.Windows.Controls.WrapPanel
		$selectorRow.Orientation = 'Horizontal'
		$selectorRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

		$leftLabel = New-Object System.Windows.Controls.TextBlock
		$leftLabel.Text = 'Profile A:'
		$leftLabel.FontSize = $Script:GuiLayout.FontSizeLabel
		$leftLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		$leftLabel.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
		$leftLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($selectorRow.Children.Add($leftLabel))

		$leftCombo = New-Object System.Windows.Controls.ComboBox
		$leftCombo.Width = $Script:GuiLayout.ComboBoxCompareWidth
		$leftCombo.Height = $Script:GuiLayout.ComboBoxCompareHeight
		$leftCombo.FontSize = $Script:GuiLayout.FontSizeLabel
		foreach ($p in $profiles) { [void]$leftCombo.Items.Add([string]$p.Label) }
		$leftCombo.SelectedIndex = 0
		[void]($selectorRow.Children.Add($leftCombo))

		$vsLabel = New-Object System.Windows.Controls.TextBlock
		$vsLabel.Text = 'vs.'
		$vsLabel.FontSize = $Script:GuiLayout.FontSizeLabel
		$vsLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
		$vsLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		$vsLabel.Margin = [System.Windows.Thickness]::new(12, 0, 12, 0)
		$vsLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($selectorRow.Children.Add($vsLabel))

		$rightLabel = New-Object System.Windows.Controls.TextBlock
		$rightLabel.Text = 'Profile B:'
		$rightLabel.FontSize = $Script:GuiLayout.FontSizeLabel
		$rightLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		$rightLabel.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
		$rightLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($selectorRow.Children.Add($rightLabel))

		$rightCombo = New-Object System.Windows.Controls.ComboBox
		$rightCombo.Width = $Script:GuiLayout.ComboBoxCompareWidth
		$rightCombo.Height = $Script:GuiLayout.ComboBoxCompareHeight
		$rightCombo.FontSize = $Script:GuiLayout.FontSizeLabel
		foreach ($p in $profiles) { [void]$rightCombo.Items.Add([string]$p.Label) }
		$rightCombo.SelectedIndex = [Math]::Min(1, $profiles.Count - 1)
		[void]($selectorRow.Children.Add($rightCombo))

		[void]($contentPanel.Children.Add($selectorRow))

		# Comparison cards container
		$cardsContainer = New-Object System.Windows.Controls.StackPanel
		$cardsContainer.Orientation = 'Vertical'
		[void]($contentPanel.Children.Add($cardsContainer))

		# Build comparison data
		$profileLookup = @{}
		foreach ($p in $profiles) { $profileLookup[[string]$p.Label] = [string]$p.Name }

		# Capture $Script: variables into locals before .GetNewClosure() — closures
		# create a dynamic module scope where $Script: no longer references GUI.psm1.
		$newSafeBrushConverterCapture = $Script:NewSafeBrushConverterScript
		$guiLayoutCapture = $Script:GuiLayout
		$getGameModeProfileDefaultSelectionScript = $Script:GetGameModeProfileDefaultSelectionScript
		$getGamingPreviewGroupSortOrderScript = $Script:GetGamingPreviewGroupSortOrderScript

		$buildComparisonCards = {
			param ($CardsContainer, $LeftCombo, $RightCombo, $ProfileLookup, $ManifestEntries, $AdvancedData, $Profiles, $Theme)

			$CardsContainer.Children.Clear()
			$bc2 = & $newSafeBrushConverterCapture -Context 'ComparisonCards'

			$leftProfile = $ProfileLookup[[string]$LeftCombo.SelectedItem]
			$rightProfile = $ProfileLookup[[string]$RightCombo.SelectedItem]
			if ([string]::IsNullOrWhiteSpace($leftProfile) -or [string]::IsNullOrWhiteSpace($rightProfile)) { return }

			if ($leftProfile -eq $rightProfile)
			{
				$sameNote = New-Object System.Windows.Controls.TextBlock
				$sameNote.Text = 'Select two different profiles to compare.'
				$sameNote.FontSize = $guiLayoutCapture.FontSizeSmall
				$sameNote.Foreground = $bc2.ConvertFromString($Theme.TextMuted)
				$sameNote.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
				[void]($CardsContainer.Children.Add($sameNote))
				return
			}

			# Build per-group comparison rows from manifest (core items)
			$comparisonItems = New-Object System.Collections.Generic.List[object]
			foreach ($entry in $ManifestEntries)
			{
				$fn = [string]$entry.Function
				$name = if ((Test-GuiObjectField -Object $entry -FieldName 'Name') -and -not [string]::IsNullOrWhiteSpace([string]$entry.Name)) { [string]$entry.Name } else { $fn }
				$group = if ((Test-GuiObjectField -Object $entry -FieldName 'GamingPreviewGroup')) { [string]$entry.GamingPreviewGroup } else { 'Other' }
				$leftIncluded = & $getGameModeProfileDefaultSelectionScript -Tweak $entry -ProfileName $leftProfile
				$rightIncluded = & $getGameModeProfileDefaultSelectionScript -Tweak $entry -ProfileName $rightProfile
				$hasPrompt = (Test-GuiObjectField -Object $entry -FieldName 'DecisionPromptKey') -and -not [string]::IsNullOrWhiteSpace([string]$entry.DecisionPromptKey)

				$leftAction = if ($leftIncluded) { if ($hasPrompt) { 'User decides' } else { 'Included' } } else { 'Not included' }
				$rightAction = if ($rightIncluded) { if ($hasPrompt) { 'User decides' } else { 'Included' } } else { 'Not included' }

				[void]$comparisonItems.Add([pscustomobject]@{
					Name         = $name
					Function     = $fn
					Group        = $group
					LeftIncluded = $leftIncluded
					RightIncluded = $rightIncluded
					LeftAction   = $leftAction
					RightAction  = $rightAction
					IsAdvanced   = $false
				})
			}

			# Advanced items
			if ($AdvancedData)
			{
				foreach ($adv in $AdvancedData)
				{
					$fn = [string]$adv.Function
					$name = if ((Test-GuiObjectField -Object $adv -FieldName 'Label') -and -not [string]::IsNullOrWhiteSpace([string]$adv.Label)) { [string]$adv.Label } else { $fn }
					$group = if ((Test-GuiObjectField -Object $adv -FieldName 'Category')) { "Advanced: $([string]$adv.Category)" } else { 'Advanced' }

					$leftChecked = $false
					$rightChecked = $false
					if ((Test-GuiObjectField -Object $adv -FieldName 'DefaultCheckedByProfile') -and $null -ne $adv.DefaultCheckedByProfile)
					{
						$defaults = $adv.DefaultCheckedByProfile
						if ($defaults -is [System.Collections.IDictionary])
						{
							if ($defaults.Contains($leftProfile)) { $leftChecked = [bool]$defaults[$leftProfile] }
							if ($defaults.Contains($rightProfile)) { $rightChecked = [bool]$defaults[$rightProfile] }
						}
						elseif ($defaults.PSObject)
						{
							if ($defaults.PSObject.Properties[$leftProfile]) { $leftChecked = [bool]$defaults.$leftProfile }
							if ($defaults.PSObject.Properties[$rightProfile]) { $rightChecked = [bool]$defaults.$rightProfile }
						}
					}

					# Skip items that are not checked in either profile
					if (-not $leftChecked -and -not $rightChecked) { continue }

					[void]$comparisonItems.Add([pscustomobject]@{
						Name         = $name
						Function     = $fn
						Group        = $group
						LeftIncluded = $leftChecked
						RightIncluded = $rightChecked
						LeftAction   = if ($leftChecked) { 'Pre-checked' } else { 'Not checked' }
						RightAction  = if ($rightChecked) { 'Pre-checked' } else { 'Not checked' }
						IsAdvanced   = $true
					})
				}
			}

			# Summary counts
			$sameCount = @($comparisonItems | Where-Object { $_.LeftIncluded -eq $_.RightIncluded }).Count
			$differCount = @($comparisonItems | Where-Object { $_.LeftIncluded -ne $_.RightIncluded }).Count

			$summaryText = New-Object System.Windows.Controls.TextBlock
			$summaryText.FontSize = $guiLayoutCapture.FontSizeSmall
			$summaryText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			$summaryText.Foreground = $bc2.ConvertFromString($Theme.TextSecondary)
			$summaryText.Text = "$sameCount item$(if ($sameCount -ne 1) { 's' }) shared, $differCount difference$(if ($differCount -ne 1) { 's' })."
			[void]($CardsContainer.Children.Add($summaryText))

			# Group and render
			$grouped = $comparisonItems | Group-Object Group | Sort-Object @{ Expression = { & $getGamingPreviewGroupSortOrderScript -GroupName ([string]$_.Name) } }, Name

			foreach ($group in $grouped)
			{
				# Group header (with icon if available)
				$groupIconContent = $null
				if (Get-Command -Name 'New-GamingGroupHeader' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$groupIconContent = New-GamingGroupHeader -GroupName ([string]$group.Name)
				}
				if ($groupIconContent)
				{
					$groupIconContent.Margin = [System.Windows.Thickness]::new(0, 8, 0, 4)
					[void]($CardsContainer.Children.Add($groupIconContent))
				}
				else
				{
					$groupHeader = New-Object System.Windows.Controls.TextBlock
					$groupHeader.Text = [string]$group.Name
					$groupHeader.FontSize = $guiLayoutCapture.FontSizeSmall
					$groupHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
					$groupHeader.Foreground = $bc2.ConvertFromString($Theme.TextSecondary)
					$groupHeader.Margin = [System.Windows.Thickness]::new(0, 8, 0, 4)
					[void]($CardsContainer.Children.Add($groupHeader))
				}

				foreach ($item in @($group.Group))
				{
					$rowBorder = New-Object System.Windows.Controls.Border
					$isSame = ($item.LeftIncluded -eq $item.RightIncluded)
					$rowBorder.Background = $bc2.ConvertFromString($(if ($isSame) { $Theme.PanelBg } else { $Theme.PresetPanelBg }))
					$rowBorder.BorderBrush = $bc2.ConvertFromString($(if ($isSame) { $Theme.CardBorder } else { $Theme.CautionBorder }))
					$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)
					$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
					$rowBorder.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
					$rowBorder.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)

					$rowGrid = New-Object System.Windows.Controls.Grid
					$col1 = New-Object System.Windows.Controls.ColumnDefinition
					$col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
					$col2 = New-Object System.Windows.Controls.ColumnDefinition
					$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
					$col3 = New-Object System.Windows.Controls.ColumnDefinition
					$col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
					[void]($rowGrid.ColumnDefinitions.Add($col1))
					[void]($rowGrid.ColumnDefinitions.Add($col2))
					[void]($rowGrid.ColumnDefinitions.Add($col3))

					# Name column
					$nameBlock = New-Object System.Windows.Controls.TextBlock
					$nameBlock.Text = [string]$item.Name
					$nameBlock.FontSize = $guiLayoutCapture.FontSizeSmall
					$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
					$nameBlock.Foreground = $bc2.ConvertFromString($Theme.TextPrimary)
					$nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
					$nameBlock.TextWrapping = 'Wrap'
					[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
					[void]($rowGrid.Children.Add($nameBlock))

					# Left profile column
					$leftBlock = New-Object System.Windows.Controls.TextBlock
					$leftTone = if ($item.LeftIncluded) { $Theme.ToggleOn } else { $Theme.TextMuted }
					$leftBlock.Text = [string]$item.LeftAction
					$leftBlock.FontSize = $guiLayoutCapture.FontSizeSmall
					$leftBlock.Foreground = $bc2.ConvertFromString($leftTone)
					$leftBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
					$leftBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
					[System.Windows.Controls.Grid]::SetColumn($leftBlock, 1)
					[void]($rowGrid.Children.Add($leftBlock))

					# Right profile column
					$rightBlock = New-Object System.Windows.Controls.TextBlock
					$rightTone = if ($item.RightIncluded) { $Theme.ToggleOn } else { $Theme.TextMuted }
					$rightBlock.Text = [string]$item.RightAction
					$rightBlock.FontSize = $guiLayoutCapture.FontSizeSmall
					$rightBlock.Foreground = $bc2.ConvertFromString($rightTone)
					$rightBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
					$rightBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
					[System.Windows.Controls.Grid]::SetColumn($rightBlock, 2)
					[void]($rowGrid.Children.Add($rightBlock))

					$rowBorder.Child = $rowGrid
					[void]($CardsContainer.Children.Add($rowBorder))
				}
			}
		}.GetNewClosure()

		# Column headers for the comparison table
		$columnHeaderGrid = New-Object System.Windows.Controls.Grid
		$columnHeaderGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
		$chCol1 = New-Object System.Windows.Controls.ColumnDefinition
		$chCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		$chCol2 = New-Object System.Windows.Controls.ColumnDefinition
		$chCol2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		$chCol3 = New-Object System.Windows.Controls.ColumnDefinition
		$chCol3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		[void]($columnHeaderGrid.ColumnDefinitions.Add($chCol1))
		[void]($columnHeaderGrid.ColumnDefinitions.Add($chCol2))
		[void]($columnHeaderGrid.ColumnDefinitions.Add($chCol3))

		$chItem = New-Object System.Windows.Controls.TextBlock
		$chItem.Text = 'Item'
		$chItem.FontSize = $Script:GuiLayout.FontSizeSmall
		$chItem.FontWeight = [System.Windows.FontWeights]::SemiBold
		$chItem.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[System.Windows.Controls.Grid]::SetColumn($chItem, 0)
		[void]($columnHeaderGrid.Children.Add($chItem))

		$chLeft = New-Object System.Windows.Controls.TextBlock
		$chLeft.FontSize = $Script:GuiLayout.FontSizeSmall
		$chLeft.FontWeight = [System.Windows.FontWeights]::SemiBold
		$chLeft.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$chLeft.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		$chLeft.Tag = 'LeftHeader'
		$chLeft.Text = [string]$profiles[0].Label
		[System.Windows.Controls.Grid]::SetColumn($chLeft, 1)
		[void]($columnHeaderGrid.Children.Add($chLeft))

		$chRight = New-Object System.Windows.Controls.TextBlock
		$chRight.FontSize = $Script:GuiLayout.FontSizeSmall
		$chRight.FontWeight = [System.Windows.FontWeights]::SemiBold
		$chRight.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$chRight.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		$chRight.Tag = 'RightHeader'
		$chRight.Text = [string]$profiles[[Math]::Min(1, $profiles.Count - 1)].Label
		[System.Windows.Controls.Grid]::SetColumn($chRight, 2)
		[void]($columnHeaderGrid.Children.Add($chRight))

		# Insert column headers before the cards container
		[void]($contentPanel.Children.Add($columnHeaderGrid))
		# Re-add cardsContainer since it was added before column headers - fix ordering
		$contentPanel.Children.Remove($cardsContainer)
		[void]($contentPanel.Children.Add($cardsContainer))

		# Initial build
		$currentThemeCapture = $Script:CurrentTheme
		& $buildComparisonCards $cardsContainer $leftCombo $rightCombo $profileLookup $manifestEntries $advancedData $profiles $currentThemeCapture

		# Wire up combo box change events
		$null = Register-GuiEventHandler -Source $leftCombo -EventName 'SelectionChanged' -Handler ({
			$chLeft.Text = [string]$leftCombo.SelectedItem
			& $buildComparisonCards $cardsContainer $leftCombo $rightCombo $profileLookup $manifestEntries $advancedData $profiles $currentThemeCapture
		}.GetNewClosure())

		$null = Register-GuiEventHandler -Source $rightCombo -EventName 'SelectionChanged' -Handler ({
			$chRight.Text = [string]$rightCombo.SelectedItem
			& $buildComparisonCards $cardsContainer $leftCombo $rightCombo $profileLookup $manifestEntries $advancedData $profiles $currentThemeCapture
		}.GetNewClosure())

		# Toggle expand/collapse
		$null = Register-GuiEventHandler -Source $headerRow -EventName 'MouseLeftButtonDown' -Handler ({
			if ($contentPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
			{
				$contentPanel.Visibility = [System.Windows.Visibility]::Visible
				$toggleText.Text = 'Hide'
			}
			else
			{
				$contentPanel.Visibility = [System.Windows.Visibility]::Collapsed
				$toggleText.Text = 'Show'
			}
		}.GetNewClosure())

		[void]($expanderStack.Children.Add($contentPanel))
		$expanderBorder.Child = $expanderStack
		return $expanderBorder
	}
