$restoredSelectionFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$legacyExplicitSelectionFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ((Test-GuiObjectField -Object $Snapshot -FieldName 'ExplicitSelections'))
{
	foreach ($functionName in @($Snapshot.ExplicitSelections))
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
		{
			[void]$legacyExplicitSelectionFunctions.Add([string]$functionName)
		}
	}
}

if ((Test-GuiObjectField -Object $Snapshot -FieldName 'ExplicitSelectionDefinitions') -and $null -ne $Snapshot.ExplicitSelectionDefinitions)
		{
			foreach ($selectionDefinition in @($Snapshot.ExplicitSelectionDefinitions))
			{
				$functionName = if ($selectionDefinition -and (Test-GuiObjectField -Object $selectionDefinition -FieldName 'Function')) { [string]$selectionDefinition.Function } else { $null }
				if (-not [string]::IsNullOrWhiteSpace($functionName))
				{
					Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition $selectionDefinition
					[void]$restoredSelectionFunctions.Add($functionName)
				}
			}
		}
		elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'ExplicitSelections'))
		{
			foreach ($functionName in @($legacyExplicitSelectionFunctions))
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
				{
					[void]$Script:ExplicitPresetSelections.Add([string]$functionName)
				}
			}
		}

		function Convert-GuiSnapshotControlStateToSelectionDefinition
		{
			param (
				[Parameter(Mandatory = $true)]
				[object]$Manifest,

				[Parameter(Mandatory = $true)]
				[object]$State,

				[System.Collections.Generic.HashSet[string]]$LegacyExplicitSelectionFunctions
			)

			$functionName = if ((Test-GuiObjectField -Object $Manifest -FieldName 'Function')) { [string]$Manifest.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($functionName)) { return $null }

			switch ([string]$Manifest.Type)
			{
				'Toggle'
				{
					if (-not (Test-GuiObjectField -Object $State -FieldName 'IsChecked')) { return $null }
					$isChecked = [bool]$State.IsChecked
					if (-not $isChecked -and -not $LegacyExplicitSelectionFunctions.Contains($functionName)) { return $null }

					return [pscustomobject]@{
						Function = $functionName
						Type = 'Toggle'
						State = if ($isChecked) { 'On' } else { 'Off' }
						Source = 'Session'
					}
				}
				'Action'
				{
					if (-not (Test-GuiObjectField -Object $State -FieldName 'IsChecked') -or -not [bool]$State.IsChecked) { return $null }

					return [pscustomobject]@{
						Function = $functionName
						Type = 'Action'
						Run = $true
						Source = 'Session'
					}
				}
				'Choice'
				{
					$selectedValue = $null
					if ((Test-GuiObjectField -Object $State -FieldName 'SelectedValue') -and -not [string]::IsNullOrWhiteSpace([string]$State.SelectedValue))
					{
						$selectedValue = [string]$State.SelectedValue
					}
					elseif ((Test-GuiObjectField -Object $State -FieldName 'SelectedIndex') -and (Test-GuiObjectField -Object $Manifest -FieldName 'Options') -and $Manifest.Options)
					{
						$selectedIndex = [int]$State.SelectedIndex
						$options = @($Manifest.Options)
						if ($selectedIndex -ge 0 -and $selectedIndex -lt $options.Count)
						{
							$selectedValue = [string]$options[$selectedIndex]
						}
					}
					if ([string]::IsNullOrWhiteSpace($selectedValue)) { return $null }

					return [pscustomobject]@{
						Function = $functionName
						Type = 'Choice'
						Value = $selectedValue
						Source = 'Session'
					}
				}
				'Date'
				{
					$isChecked = if ((Test-GuiObjectField -Object $State -FieldName 'IsChecked')) { [bool]$State.IsChecked } else { $false }
					$selectedDate = if ((Test-GuiObjectField -Object $State -FieldName 'SelectedDate') -and -not [string]::IsNullOrWhiteSpace([string]$State.SelectedDate)) { [string]$State.SelectedDate } else { $null }
					if (-not $isChecked -and [string]::IsNullOrWhiteSpace($selectedDate)) { return $null }

					$definition = [ordered]@{
						Function = $functionName
						Type = 'Date'
						Run = $true
						Source = 'Session'
					}
					if (-not [string]::IsNullOrWhiteSpace($selectedDate))
					{
						$definition.Value = $selectedDate
					}
					return [pscustomobject]$definition
				}
				'NumericRange'
				{
					$hasNumericValue = (Test-GuiObjectField -Object $State -FieldName 'NumericValue') -and $null -ne $State.NumericValue
					$hasACValue = (Test-GuiObjectField -Object $State -FieldName 'ACValue') -and $null -ne $State.ACValue
					$hasDCValue = (Test-GuiObjectField -Object $State -FieldName 'DCValue') -and $null -ne $State.DCValue
					if (-not $hasNumericValue -and -not $hasACValue -and -not $hasDCValue) { return $null }

					$definition = [ordered]@{
						Function = $functionName
						Type = 'NumericRange'
						Source = 'Session'
					}
					if ($hasNumericValue) { $definition.NumericValue = $State.NumericValue }
					if ($hasACValue) { $definition.ACValue = $State.ACValue }
					if ($hasDCValue) { $definition.DCValue = $State.DCValue }
					if ((Test-GuiObjectField -Object $State -FieldName 'Units') -and -not [string]::IsNullOrWhiteSpace([string]$State.Units))
					{
						$definition.Units = [string]$State.Units
					}
					return [pscustomobject]$definition
				}
			}

			return $null
		}

		function Convert-GuiSelectionDefinitionToSnapshotControlState
		{
			param (
				[Parameter(Mandatory = $true)]
				[object]$Manifest,

				[Parameter(Mandatory = $true)]
				[object]$Definition
			)

			$functionName = if ((Test-GuiObjectField -Object $Manifest -FieldName 'Function')) { [string]$Manifest.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($functionName)) { return $null }
			if (-not (Test-GuiObjectField -Object $Definition -FieldName 'Type')) { return $null }

			$state = [ordered]@{
				Function = $functionName
				Type = [string]$Manifest.Type
			}

			switch ([string]$Definition.Type)
			{
				'Toggle'
				{
					$state.IsChecked = ((Test-GuiObjectField -Object $Definition -FieldName 'State') -and [string]$Definition.State -eq 'On')
				}
				'Action'
				{
					$state.IsChecked = ((Test-GuiObjectField -Object $Definition -FieldName 'Run') -and [bool]$Definition.Run)
				}
				'Choice'
				{
					$selectedValue = if ((Test-GuiObjectField -Object $Definition -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$Definition.Value)) { [string]$Definition.Value } else { $null }
					$selectedIndex = -1
					if (-not [string]::IsNullOrWhiteSpace($selectedValue) -and (Test-GuiObjectField -Object $Manifest -FieldName 'Options') -and $Manifest.Options)
					{
						$selectedIndex = [array]::IndexOf(@($Manifest.Options), $selectedValue)
					}
					$state.SelectedIndex = [int]$selectedIndex
					$state.SelectedValue = $selectedValue
				}
				'Date'
				{
					$runState = if ((Test-GuiObjectField -Object $Definition -FieldName 'Run')) { [bool]$Definition.Run } else { $false }
					$selectedDate = $null
					foreach ($dateFieldName in @('DateValue', 'Value', 'SelectedDate'))
					{
						if ((Test-GuiObjectField -Object $Definition -FieldName $dateFieldName) -and -not [string]::IsNullOrWhiteSpace([string]$Definition.$dateFieldName))
						{
							$selectedDate = [string]$Definition.$dateFieldName
							break
						}
					}
					$state.IsChecked = [bool]($runState -or -not [string]::IsNullOrWhiteSpace($selectedDate))
					$state.SelectedDate = $selectedDate
				}
				'NumericRange'
				{
					$state.IsChecked = $true
					foreach ($fieldName in @('NumericValue', 'ACValue', 'DCValue', 'Units', 'Value'))
					{
						if ((Test-GuiObjectField -Object $Definition -FieldName $fieldName))
						{
							$state[$fieldName] = $Definition.$fieldName
						}
					}
				}
				default
				{
					return $null
				}
			}

			return [pscustomobject]$state
		}

		foreach ($manifest in @($Script:TweakManifest))
		{
			if (-not $manifest -or -not (Test-GuiObjectField -Object $manifest -FieldName 'Function')) { continue }
			$functionName = [string]$manifest.Function
			if ([string]::IsNullOrWhiteSpace($functionName) -or $restoredSelectionFunctions.Contains($functionName)) { continue }
			if (-not $controlStates.ContainsKey($functionName)) { continue }

			$derivedDefinition = Convert-GuiSnapshotControlStateToSelectionDefinition -Manifest $manifest -State $controlStates[$functionName] -LegacyExplicitSelectionFunctions $legacyExplicitSelectionFunctions
			if ($derivedDefinition)
			{
				Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition $derivedDefinition
				[void]$restoredSelectionFunctions.Add($functionName)
			}
		}

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			if (-not $control) { continue }

			$state = $controlStates[$manifest.Function]
			if (-not $state)
			{
				$restoredDefinition = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$manifest.Function)
				if ($restoredDefinition)
				{
					$state = Convert-GuiSelectionDefinitionToSnapshotControlState -Manifest $manifest -Definition $restoredDefinition
				}
			}
			if (-not $state) { continue }

			switch ($manifest.Type)
			{
				'Date'
				{
					$isChecked = if ((Test-GuiObjectField -Object $state -FieldName 'IsChecked')) { [bool]$state.IsChecked } else { $false }
					$selectedDate = $null
					if ((Test-GuiObjectField -Object $state -FieldName 'SelectedDate') -and -not [string]::IsNullOrWhiteSpace([string]$state.SelectedDate))
					{
						$parsedDate = [datetime]::MinValue
						if (-not [datetime]::TryParseExact([string]$state.SelectedDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate))
						{
							throw "Invalid GUI session date value for '$([string]$manifest.Function)': '$([string]$state.SelectedDate)'."
						}
						$selectedDate = $parsedDate
					}

					if ((Test-GuiObjectField -Object $control -FieldName 'IsRestoring'))
					{
						$control.IsRestoring = $true
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'CheckBox') -and $control.CheckBox)
					{
						$control.CheckBox.IsChecked = [bool]$isChecked
					}
					elseif ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$control.IsChecked = [bool]$isChecked
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'DatePicker') -and $control.DatePicker)
					{
						$control.DatePicker.SelectedDate = $selectedDate
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'SelectedDate'))
					{
						$control.SelectedDate = $selectedDate
					}
					if ((Test-GuiObjectField -Object $control -FieldName 'IsRestoring'))
					{
						$control.IsRestoring = $false
					}
				}
				'Choice'
				{
					if ((Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						$selectedIndex = -1
						if ($manifest.Options -and (Test-GuiObjectField -Object $state -FieldName 'SelectedValue') -and -not [string]::IsNullOrWhiteSpace([string]$state.SelectedValue))
						{
							$selectedIndex = [array]::IndexOf(@($manifest.Options), [string]$state.SelectedValue)
						}
						if ($selectedIndex -lt 0 -and (Test-GuiObjectField -Object $state -FieldName 'SelectedIndex'))
						{
							$selectedIndex = [int]$state.SelectedIndex
						}
						$optCount = if ($manifest.Options) { $manifest.Options.Count } else { 0 }
						if ($selectedIndex -ge $optCount) { $selectedIndex = -1 }
						[int]$idx = $selectedIndex
						$control.SelectedIndex = $idx
					}
				}
				default
				{
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$control.IsChecked = [bool]$state.IsChecked
					}
				}
			}
		}
