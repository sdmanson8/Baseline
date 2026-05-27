
	<#
	    .SYNOPSIS
	#>

	function Initialize-GuiSelectionStateStores
	{
		if (-not $Script:ExplicitPresetSelections)
		{
			$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
				[System.StringComparer]::OrdinalIgnoreCase
			)
		}
		if (-not $Script:ExplicitPresetSelectionDefinitions)
		{
			$Script:ExplicitPresetSelectionDefinitions = @{}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Copy-GuiExplicitSelectionDefinition
	{
		param (
			[object]$Definition,
			[string]$FunctionName = $null,
			[string]$Source = $null
		)

		if (-not $Definition) { return $null }

		$resolvedFunction = if (-not [string]::IsNullOrWhiteSpace([string]$FunctionName))
		{
			[string]$FunctionName
		}
		elseif ((Test-GuiObjectField -Object $Definition -FieldName 'Function') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Function))
		{
			[string]$Definition.Function
		}
		else
		{
			$null
		}
		if ([string]::IsNullOrWhiteSpace($resolvedFunction)) { return $null }

		$copy = [ordered]@{
			Function = $resolvedFunction
			Type = if ((Test-GuiObjectField -Object $Definition -FieldName 'Type')) { [string]$Definition.Type } else { $null }
		}

		if ((Test-GuiObjectField -Object $Definition -FieldName 'State') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.State))
		{
			$copy.State = [string]$Definition.State
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'Value'))
		{
			$copy.Value = $Definition.Value
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'NumericValue'))
		{
			$copy.NumericValue = $Definition.NumericValue
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'ACValue'))
		{
			$copy.ACValue = $Definition.ACValue
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'DCValue'))
		{
			$copy.DCValue = $Definition.DCValue
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'Units') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Units))
		{
			$copy.Units = [string]$Definition.Units
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'DateParam') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.DateParam))
		{
			$copy.DateParam = [string]$Definition.DateParam
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'Run'))
		{
			$copy.Run = [bool]$Definition.Run
		}
		if ((Test-GuiObjectField -Object $Definition -FieldName 'ExtraArgs') -and $null -ne $Definition.ExtraArgs)
		{
			$extraArgsCopy = @{}
			$extraArgsSource = $Definition.ExtraArgs
			if ($extraArgsSource -is [System.Collections.IDictionary])
			{
				foreach ($entry in $extraArgsSource.GetEnumerator())
				{
					$extraArgsCopy[[string]$entry.Key] = $entry.Value
				}
			}
			elseif ($extraArgsSource.PSObject)
			{
				foreach ($property in $extraArgsSource.PSObject.Properties)
				{
					$extraArgsCopy[[string]$property.Name] = $property.Value
				}
			}
			if ($extraArgsCopy.Count -gt 0)
			{
				$copy.ExtraArgs = $extraArgsCopy
			}
		}

		$resolvedSource = if (-not [string]::IsNullOrWhiteSpace([string]$Source))
		{
			[string]$Source
		}
		elseif ((Test-GuiObjectField -Object $Definition -FieldName 'Source') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Source))
		{
			[string]$Definition.Source
		}
		else
		{
			$null
		}
		if (-not [string]::IsNullOrWhiteSpace($resolvedSource))
		{
			$copy.Source = $resolvedSource
		}

		return [pscustomobject]$copy
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiExplicitSelectionDefinition
	{
		param ([string]$FunctionName)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return $null }
		if (-not $Script:ExplicitPresetSelectionDefinitions.ContainsKey([string]$FunctionName)) { return $null }
		$definition = $Script:ExplicitPresetSelectionDefinitions[[string]$FunctionName]
		if ($definition -and (Test-GuiObjectField -Object $definition -FieldName 'Source') -and [string]$definition.Source -eq 'GameMode' -and -not [bool]$Script:GameMode)
		{
			return $null
		}
		return $definition
	}

	function Set-GuiExplicitSelectionDefinition
	{
		param (
			[Parameter(Mandatory = $true)][string]$FunctionName,
			[Parameter(Mandatory = $true)][object]$Definition
		)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return }

		$copy = Copy-GuiExplicitSelectionDefinition -Definition $Definition -FunctionName ([string]$FunctionName)
		if (-not $copy) { return }

		$Script:ExplicitPresetSelectionDefinitions[[string]$FunctionName] = $copy
		[void]$Script:ExplicitPresetSelections.Add([string]$FunctionName)
	}

	<#
	    .SYNOPSIS
	#>

	function Remove-GuiExplicitSelectionDefinition
	{
		param ([string]$FunctionName)

		Initialize-GuiSelectionStateStores
		if ([string]::IsNullOrWhiteSpace([string]$FunctionName)) { return }

		[void]($Script:ExplicitPresetSelectionDefinitions.Remove([string]$FunctionName))
		[void]($Script:ExplicitPresetSelections.Remove([string]$FunctionName))
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiSelectionDefinitionFromCommands
	{
		param (
			[Parameter(Mandatory = $true)][string]$Name,
			[string[]]$CommandLines = @(),
			[string]$SourcePath,
			[string]$ModeKind = 'Preset',
			[string]$StatusMessagePrefix = 'Preset applied',
			[string]$RestoreGuidance = $null,
			[string]$Summary = $null
		)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$manifestByFunction = @{}
		foreach ($tweak in @($Script:TweakManifest))
		{
			if ($tweak -and -not [string]::IsNullOrWhiteSpace([string]$tweak.Function))
			{
				$manifestByFunction[[string]$tweak.Function] = $tweak
			}
		}

		$selectionMap = @{}
		$unmatchedEntries = [System.Collections.Generic.List[object]]::new()
		$lineNumber = 0
		foreach ($rawCommandLine in @($CommandLines))
		{
			$lineNumber++
			$commandLine = [string]$rawCommandLine
			if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $manifestByFunction.ContainsKey($functionName))
			{
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = "No manifest entry matches '$functionName'."
				})
				continue
			}

			$tweak = $manifestByFunction[$functionName]
			$argName = $null
			if ($tokens.Count -gt 1 -and $tokens[1].StartsWith('-'))
			{
				$argName = $tokens[1].Substring(1)
			}

			$matchedEntry = $null
			switch ([string]$tweak.Type)
			{
				'Toggle'
				{
					$state = $null
					if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam) -and $argName -eq [string]$tweak.OnParam)
					{
						$state = 'On'
					}
					elseif (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam) -and $argName -eq [string]$tweak.OffParam)
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Enable' -or $argName -eq 'Show')
					{
						$state = 'On'
					}
					elseif ($argName -eq 'Disable' -or $argName -eq 'Hide')
					{
						$state = 'Off'
					}

					if ($state)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Toggle'
							State = $state
						}
					}
				}
					'Choice'
					{
						$optList = if ($null -ne $tweak.Options -and $tweak.Options -is [System.Collections.IEnumerable] -and -not ($tweak.Options -is [string])) { [string[]]$tweak.Options } elseif ($null -ne $tweak.Options) { [string[]]@([string]$tweak.Options) } else { [string[]]@() }
						if (-not [string]::IsNullOrWhiteSpace([string]$argName) -and $optList -contains $argName)
						{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Choice'
							Value = $argName
							}
						}
					}
					'NumericRange'
					{
						$acValue = $null
						$dcValue = $null
						$scalarValue = $null

						for ($i = 1; $i -lt $tokens.Count; $i++)
						{
							$token = [string]$tokens[$i]
							if (-not $token.StartsWith('-'))
							{
								continue
							}

							$tokenName = $token.TrimStart('-')
							$tokenValue = if ($i + 1 -lt $tokens.Count) { [string]$tokens[$i + 1] } else { $null }
							switch ($tokenName)
							{
								'Value' { $scalarValue = $tokenValue }
								'NumericValue' { $scalarValue = $tokenValue }
								'ACValue' { $acValue = $tokenValue }
								'DCValue' { $dcValue = $tokenValue }
							}
						}

						$numericSelection = [ordered]@{
							Function = $functionName
							Type = 'NumericRange'
						}
						if ((Test-GuiObjectField -Object $tweak -FieldName 'NumericRange') -and (Test-GuiObjectField -Object $tweak.NumericRange -FieldName 'Units') -and -not [string]::IsNullOrWhiteSpace([string]$tweak.NumericRange.Units))
						{
							$numericSelection.Units = [string]$tweak.NumericRange.Units
						}

						if ($null -ne $acValue -or $null -ne $dcValue)
						{
							if ($null -ne $acValue)
							{
								$numericSelection.ACValue = $acValue
							}
							if ($null -ne $dcValue)
							{
								$numericSelection.DCValue = $dcValue
							}

							$channelValues = [ordered]@{}
							if ($null -ne $acValue)
							{
								$channelValues.ACValue = $acValue
							}
							if ($null -ne $dcValue)
							{
								$channelValues.DCValue = $dcValue
							}
							$numericSelection.Value = [pscustomobject]$channelValues
							$matchedEntry = [pscustomobject]$numericSelection
							$debugMessage = "Line {0}: {1} -> NumericRange {2}." -f $lineNumber, $commandLine, (Format-GuiPowerSchemeValueText -Value ([pscustomobject]$channelValues) -NumericRange $tweak.NumericRange)
						}
						elseif (-not [string]::IsNullOrWhiteSpace($scalarValue))
						{
							$numericSelection.Value = $scalarValue
							$numericSelection.NumericValue = $scalarValue
							$matchedEntry = [pscustomobject]$numericSelection
							$debugMessage = "Line {0}: {1} -> NumericRange {2}." -f $lineNumber, $commandLine, (Format-GuiNumericRangeValueText -Value $scalarValue -NumericRange $tweak.NumericRange)
						}
					}
					'Date'
					{
						if ($argName -eq 'Enable' -or $argName -eq 'On')
						{
						$dateValue = $null
						for ($i = 1; $i -lt $tokens.Count - 1; $i++)
						{
							if ($tokens[$i].TrimStart('-') -eq 'StartDate')
							{
								$dateValue = [string]$tokens[$i + 1]
								break
							}
						}

						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Date'
							Run = $true
							Value = $dateValue
							DateParam = if ((Test-GuiObjectField -Object $tweak -FieldName 'DateParam')) { [string]$tweak.DateParam } else { 'StartDate' }
						}
					}
					elseif ($argName -eq 'Disable' -or $argName -eq 'Off' -or $argName -eq 'Clear')
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Date'
							Run = $false
							DateParam = if ((Test-GuiObjectField -Object $tweak -FieldName 'DateParam')) { [string]$tweak.DateParam } else { 'StartDate' }
						}
					}
				}
				'Action'
				{
					$matchedEntry = [pscustomobject]@{
						Function = $functionName
						Type = 'Action'
						Run = $true
					}
				}
			}

			if ($matchedEntry)
			{
				$selectionMap[$functionName] = $matchedEntry
			}
			else
			{
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = "Command did not map cleanly onto tweak type '$([string]$tweak.Type)'."
				})
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiSelectionDefinitionFromCommands' -Message ("Selection definition '{0}' resolved to {1} matched entr{2} and {3} unmatched entr{4}." -f $Name, $selectionMap.Count, $(if ($selectionMap.Count -eq 1) { 'y' } else { 'ies' }), $unmatchedEntries.Count, $(if ($unmatchedEntries.Count -eq 1) { 'y' } else { 'ies' }))
		}

		return [pscustomobject]@{
			Name = $Name
			Tier = $Name
			SelectionMode = 'Explicit'
			Entries = $selectionMap
			UnmatchedEntries = [object[]]$unmatchedEntries.ToArray()
			PolicyIssues = @()
			SourcePath = $SourcePath
			ModeKind = $ModeKind
			StatusMessagePrefix = $StatusMessagePrefix
			RestoreGuidance = $RestoreGuidance
			Summary = $Summary
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiPresetSelection
	{
		param([Parameter(Mandatory = $true)][string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Received preset request '{0}' on current tab '{1}'." -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
		}
		if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab) -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Ignoring preset '{0}' because there is no active primary tab or the search-results tab is selected." -f $PresetName)
			}
			return
		}

		$setTabPresetScript = ${function:Set-TabPreset}
		if (-not $setTabPresetScript)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Could not dispatch preset '{0}' because Set-TabPreset is unavailable." -f $PresetName)
			}
			return
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Dispatching preset '{0}' to Set-TabPreset for tab '{1}'." -f $PresetName, $Script:CurrentPrimaryTab)
		}
		try
		{
			& $setTabPresetScript -PrimaryTab $Script:CurrentPrimaryTab -PresetTier $PresetName
		}
		catch
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Set-TabPreset failed for preset '{0}' on tab '{1}': {2}" -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }), $_.Exception.Message)
			}
			throw
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Completed preset dispatch for '{0}'." -f $PresetName)
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiScenarioProfileSelection
	{
		param([Parameter(Mandatory = $true)][string]$ProfileName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab) -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			return
		}

		$setTabPresetScript = ${function:Set-TabPreset}
		if (-not $setTabPresetScript)
		{
			return
		}

		$scenarioDefinition = @(
			Get-ScenarioProfileDefinitions |
				Where-Object { [string]$_.Name -eq [string]$ProfileName } |
				Select-Object -First 1
		)
		if (-not $scenarioDefinition)
		{
			throw "Scenario profile '$ProfileName' was not found."
		}

		$commandList = @(Get-ScenarioProfileCommandList -Manifest $Script:TweakManifest -ProfileName $ProfileName)
		if (-not $commandList -or $commandList.Count -eq 0)
		{
			throw "Scenario profile '$ProfileName' did not resolve to any commands."
		}

		$selectionDefinition = Get-GuiSelectionDefinitionFromCommands `
			-Name ([string]$scenarioDefinition.Name) `
			-CommandLines $commandList `
			-SourcePath ("ScenarioProfile::{0}" -f [string]$scenarioDefinition.Name) `
			-ModeKind 'Scenario' `
			-StatusMessagePrefix 'Scenario mode applied' `
			-RestoreGuidance $(if ([string]$scenarioDefinition.Name -eq 'Recovery') { 'Recovery mode adds a restore point action plus recovery and startup helpers before you need them.' } else { $null }) `
			-Summary ([string]$scenarioDefinition.Summary)

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiScenarioProfileSelection' -Message ("Dispatching scenario profile '{0}' with {1} command(s)." -f $ProfileName, $commandList.Count)
		}

		& $setTabPresetScript -PrimaryTab $Script:CurrentPrimaryTab -PresetTier $ProfileName -SelectionDefinition $selectionDefinition
	}

	<#
	    .SYNOPSIS
	#>

	function Set-FilterSelections
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Risk = 'All',
			[string]$Category = 'All',
			[bool]$SelectedOnly = $false,
			[bool]$HighRiskOnly = $false,
			[bool]$RestorableOnly = $false,
			[bool]$GamingOnly = $false
		)

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:RiskFilter = if ([string]::IsNullOrWhiteSpace($Risk)) { 'All' } else { $Risk }
			if ($CmbRiskFilter)
			{
				if ($Script:RiskFilterInternalValues -and $Script:RiskFilterInternalValues.Contains($Script:RiskFilter))
				{
					$found = $Script:RiskFilterInternalValues.IndexOf($Script:RiskFilter)
					if ($found -ge 0) { $CmbRiskFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbRiskFilter.SelectedIndex = $idx
					$Script:RiskFilter = 'All'
				}
			}

			$Script:CategoryFilter = if ([string]::IsNullOrWhiteSpace($Category)) { 'All' } else { $Category }
			if ($CmbCategoryFilter)
			{
				if ($Script:CategoryFilterInternalValues -and $Script:CategoryFilterInternalValues.Contains($Script:CategoryFilter))
				{
					$found = $Script:CategoryFilterInternalValues.IndexOf($Script:CategoryFilter)
					if ($found -ge 0) { $CmbCategoryFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbCategoryFilter.SelectedIndex = $idx
					$Script:CategoryFilter = 'All'
				}
			}

			$Script:SelectedOnlyFilter = [bool]$SelectedOnly
			if ($ChkSelectedOnly) { $ChkSelectedOnly.IsChecked = $Script:SelectedOnlyFilter }

			$Script:HighRiskOnlyFilter = [bool]$HighRiskOnly
			if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsChecked = $Script:HighRiskOnlyFilter }

			$Script:RestorableOnlyFilter = [bool]$RestorableOnly
			if ($ChkRestorableOnly) { $ChkRestorableOnly.IsChecked = $Script:RestorableOnlyFilter }

			$Script:GamingOnlyFilter = [bool]$GamingOnly
			if ($ChkGamingOnly) { $ChkGamingOnly.IsChecked = $Script:GamingOnlyFilter }
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Clear-InvisibleSelectionState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$testTweakVisibleInCurrentModeScript = ${function:Test-TweakVisibleInCurrentMode}
		if (-not $testTweakVisibleInCurrentModeScript -or -not $Script:TweakManifest -or -not $Script:Controls)
		{
			return 0
		}

		$clearedCount = 0
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$tweak = $Script:TweakManifest[$i]
			if (-not $tweak) { continue }
			if (& $testTweakVisibleInCurrentModeScript -Tweak $tweak) { continue }

			$control = $Script:Controls[$i]
			$wasSelected = $false

			switch ($tweak.Type)
			{
				'Toggle'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
					{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						IsChecked = $false
						IsEnabled = $false
					}
				}
				'Choice'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'SelectedIndex') -and [int]$control.SelectedIndex -ge 0)
					{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						SelectedIndex = [int]-1
						IsEnabled = $false
					}
				}
				'Date'
				{
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
					{
						$wasSelected = $true
					}
					elseif ($control -and (Test-GuiObjectField -Object $control -FieldName 'SelectedDate') -and $control.SelectedDate)
					{
						$wasSelected = $true
					}
						$Script:Controls[$i] = [pscustomobject]@{
							IsChecked = $false
							SelectedDate = $null
							IsEnabled = $false
						}
					}
					'NumericRange'
					{
						$currentACValue = if ($control) { Get-GuiNumericRangeChannelValue -Value $control -Channel 'AC' -NumericRange $tweak.NumericRange } else { $null }
						$currentDCValue = if ($control) { Get-GuiNumericRangeChannelValue -Value $control -Channel 'DC' -NumericRange $tweak.NumericRange } else { $null }
						if ($control -and ((Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked -or $null -ne $currentACValue -or $null -ne $currentDCValue))
						{
							$wasSelected = $true
						}
						$Script:Controls[$i] = [pscustomobject]@{
							IsChecked = $false
							IsEnabled = $false
							Value = $null
							NumericValue = $null
							ACValue = $null
							DCValue = $null
						}
					}
					'Action'
					{
						if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
						{
						$wasSelected = $true
					}
					$Script:Controls[$i] = [pscustomobject]@{
						IsChecked = $false
						IsEnabled = $false
					}
				}
			}

			Remove-GuiExplicitSelectionDefinition -FunctionName ([string]$tweak.Function)

			if ($wasSelected)
			{
				$clearedCount++
			}
		}

		return $clearedCount
	}

