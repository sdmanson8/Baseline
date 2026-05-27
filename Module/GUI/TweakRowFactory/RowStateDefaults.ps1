
	<#
	    .SYNOPSIS
	#>

	function Ensure-PendingLinkedStateCollections
	{
		if (-not ($Script:PendingLinkedChecks -is [System.Collections.Generic.HashSet[string]]))
		{
			$Script:PendingLinkedChecks = [System.Collections.Generic.HashSet[string]]::new()
		}
		if (-not ($Script:PendingLinkedUnchecks -is [System.Collections.Generic.HashSet[string]]))
		{
			$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakRowFactoryRuntimeCommand
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Name
		)

		$cacheVariable = Get-Variable -Name 'TweakRowFactoryRuntimeCommandCache' -Scope Script -ErrorAction SilentlyContinue
		if (-not $cacheVariable -or -not ($cacheVariable.Value -is [hashtable]))
		{
			$Script:TweakRowFactoryRuntimeCommandCache = @{}
		}

		if (-not $Script:TweakRowFactoryRuntimeCommandCache.ContainsKey($Name))
		{
			$command = @(
				Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
			) | Select-Object -First 1

			$Script:TweakRowFactoryRuntimeCommandCache[$Name] = $command
		}

		return $Script:TweakRowFactoryRuntimeCommandCache[$Name]
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakRowFactoryTweakAvailable
	{
		param ([object]$Tweak)

		$availabilityTest = Get-TweakRowFactoryRuntimeCommand -Name 'Test-GuiTweakAvailableOnCurrentSystem'
		if (-not $availabilityTest)
		{
			return $true
		}

		return [bool](& $availabilityTest -Tweak $Tweak)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakRowFactoryHideUnavailableItems
	{
		$preferenceCommand = Get-TweakRowFactoryRuntimeCommand -Name 'Get-BaselineUserPreference'
		if (-not $preferenceCommand)
		{
			return $true
		}

		try
		{
			return [bool](& $preferenceCommand -Key 'HideUnavailableItems' -Default $true)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'RowStateDefaults.Get-TweakRowFactoryHideUnavailableItems' -Severity Debug
			}

			return $true
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Remove-TweakRowFactoryExplicitSelectionDefinition
	{
		param ([string]$FunctionName)

		if ([string]::IsNullOrWhiteSpace($FunctionName)) { return }

		$removeSelectionCommand = Get-TweakRowFactoryRuntimeCommand -Name 'Remove-GuiExplicitSelectionDefinition'
		if ($removeSelectionCommand)
		{
			& $removeSelectionCommand -FunctionName $FunctionName
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakRowVisible
	{
		param ([object]$Tweak)

		if ($null -eq $Tweak)
		{
			return $false
		}

		$visibleIf = $null
		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('VisibleIf')) { $visibleIf = $Tweak['VisibleIf'] }
		}
		elseif ($Tweak.PSObject -and $Tweak.PSObject.Properties['VisibleIf'])
		{
			$visibleIf = $Tweak.VisibleIf
		}

		if ($visibleIf)
		{
			try
			{
				if (-not [bool](& $visibleIf)) { return $false }
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RowStateDefaults.Test-TweakRowVisible:catch47' -Severity Debug }

				return $false
			}
		}

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			if (Get-TweakRowFactoryHideUnavailableItems) { return $false }
		}

		return $true
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakDefaultToggleState
	{
		param ([object]$Tweak)

		if (Test-GuiObjectField -Object $Tweak -FieldName 'Default')
		{
			return [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default')
		}
		if (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		{
			return [bool](Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		}
		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakDefaultChoiceSelectedIndex
	{
		param ([object]$Tweak)

		$choiceOptions = if ($Tweak.Options) { [object[]]@($Tweak.Options) } else { [object[]]@() }
		$defaultValue = $null
		if (Test-GuiObjectField -Object $Tweak -FieldName 'Default')
		{
			$defaultValue = [string](Get-GuiObjectField -Object $Tweak -FieldName 'Default')
		}
		elseif (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		{
			$defaultValue = [string](Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		}

		if ([string]::IsNullOrWhiteSpace([string]$defaultValue) -or $choiceOptions.Count -eq 0)
		{
			return -1
		}

		$defaultIndex = [array]::IndexOf($choiceOptions, [string]$defaultValue)
		if ($defaultIndex -ge 0)
		{
			return $defaultIndex
		}

		return -1
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakDefaultNumericRangeValues
	{
		param (
			[object]$Tweak,
			[object]$NumericRange
		)

		$defaultSource = $null
		if (Test-GuiObjectField -Object $Tweak -FieldName 'Default')
		{
			$defaultSource = Get-GuiObjectField -Object $Tweak -FieldName 'Default'
		}
		elseif (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		{
			$defaultSource = Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault'
		}

		$defaultAC = $null
		$defaultDC = $null
		if ($null -ne $defaultSource)
		{
			$defaultAC = Get-GuiNumericRangeChannelValue -Value $defaultSource -Channel 'AC' -NumericRange $NumericRange
			$defaultDC = Get-GuiNumericRangeChannelValue -Value $defaultSource -Channel 'DC' -NumericRange $NumericRange
		}

		return [pscustomobject]@{
			ACValue = $defaultAC
			DCValue = $defaultDC
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakDefaultDateSelection
	{
		param ([object]$Tweak)

		$defaultRun = if (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default') } elseif (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault') } else { $false }
		$defaultDate = $null
		foreach ($candidateField in @('DefaultDate', 'DefaultValue', 'Value'))
		{
			if (Test-GuiObjectField -Object $Tweak -FieldName $candidateField)
			{
				$candidateValue = [string](Get-GuiObjectField -Object $Tweak -FieldName $candidateField)
				if (-not [string]::IsNullOrWhiteSpace($candidateValue))
				{
					$defaultDate = $candidateValue
					break
				}
			}
		}

		return [pscustomobject]@{
			Run = [bool]$defaultRun
			Value = $defaultDate
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakDefaultActionState
	{
		param ([object]$Tweak)

		if (Test-GuiObjectField -Object $Tweak -FieldName 'Default')
		{
			return [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default')
		}
		if (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		{
			return [bool](Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault')
		}
		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GameModePlanEntryForTweak
	{
		param ([object]$Tweak)

		$currentPlan = Get-GameModePlan
		if (-not [bool]$Script:GameMode -or -not $currentPlan -or @($currentPlan).Count -eq 0)
		{
			return $null
		}

		foreach ($planEntry in @($currentPlan))
		{
			if ($planEntry -and (Test-GuiObjectField -Object $planEntry -FieldName 'Function') -and [string]$planEntry.Function -eq [string]$Tweak.Function)
			{
				return $planEntry
			}
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Get-ToggleInitialCheckedState
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			return $false
		}

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			$planToggle = if ((Test-GuiObjectField -Object $planMatch -FieldName 'ToggleParam')) { [string]$planMatch.ToggleParam } elseif ((Test-GuiObjectField -Object $planMatch -FieldName 'Selection')) { [string]$planMatch.Selection } else { $null }
			return (-not [string]::IsNullOrWhiteSpace($planToggle) -and [string]$planToggle -eq [string]$Tweak.OnParam)
		}

		# Explicit preset selections must survive tab rebuilds even when the target
		# tab has not been materialized into live controls yet.
		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Toggle')
		{
			return ([string]$explicitSelection.State -eq 'On')
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-ActionInitialCheckedState
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			return $false
		}

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			return $true
		}

		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Action')
		{
			return [bool]$explicitSelection.Run
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-ChoiceInitialSelectedIndex
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object[]]$ChoiceOptions = @(),
			[object]$RowContext = $null
		)

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			return -1
		}

		if ($RowContext -and (Test-GuiObjectField -Object $RowContext -FieldName 'GetExplicitSelectionDefinition') -and $RowContext.GetExplicitSelectionDefinition)
		{
			$explicitSelection = & $RowContext.GetExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
			if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Choice' -and -not [string]::IsNullOrWhiteSpace([string]$explicitSelection.Value))
			{
				$explicitIndex = [array]::IndexOf($ChoiceOptions, [string]$explicitSelection.Value)
				if ($explicitIndex -ge 0)
				{
					return $explicitIndex
				}
			}
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'SelectedIndex'))
		{
			return [int]$placeholder.SelectedIndex
		}

		return -1
	}

	<#
	    .SYNOPSIS
	#>

	function Get-NumericRangeInitialCheckedState
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object]$RowContext = $null
		)

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			return $false
		}

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			return $true
		}

		$explicitSelection = if ($RowContext -and (Test-GuiObjectField -Object $RowContext -FieldName 'GetExplicitSelectionDefinition') -and $RowContext.GetExplicitSelectionDefinition)
		{
			& $RowContext.GetExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		}
		else
		{
			Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		}
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'NumericRange')
		{
			return $true
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-NumericRangeInitialValue
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[string]$Channel = 'AC',
			[object]$NumericRange = $null,
			[object]$RowContext = $null
		)

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			$planValue = Get-GuiNumericRangeChannelValue -Value $planMatch -Channel $Channel -NumericRange $NumericRange
			if ($null -ne $planValue)
			{
				return $planValue
			}
		}

		$explicitSelection = if ($RowContext -and (Test-GuiObjectField -Object $RowContext -FieldName 'GetExplicitSelectionDefinition') -and $RowContext.GetExplicitSelectionDefinition)
		{
			& $RowContext.GetExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		}
		else
		{
			Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		}
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'NumericRange')
		{
			$explicitValue = Get-GuiNumericRangeChannelValue -Value $explicitSelection -Channel $Channel -NumericRange $NumericRange
			if ($null -ne $explicitValue)
			{
				return $explicitValue
			}
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder)
		{
			$placeholderValue = Get-GuiNumericRangeChannelValue -Value $placeholder -Channel $Channel -NumericRange $NumericRange
			if ($null -ne $placeholderValue)
			{
				return $placeholderValue
			}
		}

		foreach ($candidateField in @('Default', 'WinDefault'))
		{
			if (Test-GuiObjectField -Object $Tweak -FieldName $candidateField)
			{
				$initialValue = Get-GuiNumericRangeChannelValue -Value (Get-GuiObjectField -Object $Tweak -FieldName $candidateField) -Channel $Channel -NumericRange $NumericRange
				if ($null -ne $initialValue)
				{
					return $initialValue
				}
			}
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function ConvertTo-GuiDateTimeValue
	{
		param ([object]$Value)

		if ($null -eq $Value)
		{
			return $null
		}

		if ($Value -is [datetime])
		{
			return [datetime]$Value
		}

		$rawValue = [string]$Value
		if ([string]::IsNullOrWhiteSpace($rawValue))
		{
			return $null
		}

		$parsedDate = [datetime]::MinValue
		if ([datetime]::TryParseExact($rawValue, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate))
		{
			return $parsedDate
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Get-DateInitialRunState
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		if (-not (Test-TweakRowFactoryTweakAvailable -Tweak $Tweak))
		{
			return $false
		}

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			if (Test-GuiObjectField -Object $planMatch -FieldName 'Run')
			{
				return [bool]$planMatch.Run
			}
			if ((Test-GuiObjectField -Object $planMatch -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$planMatch.Value))
			{
				return $true
			}
			if ((Test-GuiObjectField -Object $planMatch -FieldName 'DateValue') -and -not [string]::IsNullOrWhiteSpace([string]$planMatch.DateValue))
			{
				return $true
			}
		}

		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Date')
		{
			if (Test-GuiObjectField -Object $explicitSelection -FieldName 'Run')
			{
				return [bool]$explicitSelection.Run
			}
			if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$explicitSelection.Value))
			{
				return $true
			}
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		if (Test-GuiObjectField -Object $Tweak -FieldName 'Default')
		{
			return [bool]$Tweak.Default
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-DateInitialSelectedDate
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			foreach ($fieldName in @('DateValue', 'Value', 'SelectedDate'))
			{
				if (Test-GuiObjectField -Object $planMatch -FieldName $fieldName)
				{
					$dateValue = ConvertTo-GuiDateTimeValue -Value (Get-GuiObjectField -Object $planMatch -FieldName $fieldName)
					if ($dateValue)
					{
						return $dateValue
					}
				}
			}
		}

		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Date')
		{
			foreach ($fieldName in @('DateValue', 'Value', 'SelectedDate'))
			{
				if (Test-GuiObjectField -Object $explicitSelection -FieldName $fieldName)
				{
					$dateValue = ConvertTo-GuiDateTimeValue -Value (Get-GuiObjectField -Object $explicitSelection -FieldName $fieldName)
					if ($dateValue)
					{
						return $dateValue
					}
				}
			}
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder)
		{
			if ((Test-GuiObjectField -Object $placeholder -FieldName 'SelectedDate') -and $placeholder.SelectedDate)
			{
				$dateValue = ConvertTo-GuiDateTimeValue -Value $placeholder.SelectedDate
				if ($dateValue)
				{
					return $dateValue
				}
			}
			if ((Test-GuiObjectField -Object $placeholder -FieldName 'DatePicker') -and $placeholder.DatePicker -and (Test-GuiObjectField -Object $placeholder.DatePicker -FieldName 'SelectedDate') -and $placeholder.DatePicker.SelectedDate)
			{
				$dateValue = ConvertTo-GuiDateTimeValue -Value $placeholder.DatePicker.SelectedDate
				if ($dateValue)
				{
					return $dateValue
				}
			}
		}

		foreach ($candidateField in @('DefaultDate', 'DefaultValue', 'Value'))
		{
			if (Test-GuiObjectField -Object $Tweak -FieldName $candidateField)
			{
				$dateValue = ConvertTo-GuiDateTimeValue -Value (Get-GuiObjectField -Object $Tweak -FieldName $candidateField)
				if ($dateValue)
				{
					return $dateValue
				}
			}
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Apply-PendingLinkedToggleState
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[string]$FunctionName
		)

		Ensure-PendingLinkedStateCollections

		if ($Script:PendingLinkedChecks -and $Script:PendingLinkedChecks.Contains($FunctionName))
		{
			$CheckBox.IsChecked = $true
			[void]($Script:PendingLinkedChecks.Remove($FunctionName))
		}
		elseif ($Script:PendingLinkedUnchecks -and $Script:PendingLinkedUnchecks.Contains($FunctionName))
		{
			$CheckBox.IsChecked = $false
			[void]($Script:PendingLinkedUnchecks.Remove($FunctionName))
		}
	}

