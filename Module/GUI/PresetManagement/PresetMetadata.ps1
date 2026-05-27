
	<#
	    .SYNOPSIS
	#>

	function Get-PrimaryTabManifestIndexes
	{
		param ([string]$PrimaryTab)

		$indexes = @()
		if ([string]::IsNullOrWhiteSpace($PrimaryTab)) { return $indexes }

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			if ((Resolve-GuiPrimaryTabForTweak -Tweak $Script:TweakManifest[$i]) -eq $PrimaryTab)
			{
				$indexes += $i
			}
		}

		return $indexes
	}

	<#
	    .SYNOPSIS
	#>

	function Get-PresetTierRank
	{
		param ([string]$Tier)

		$normalizedTier = if ([string]::IsNullOrWhiteSpace($Tier)) { 'Basic' } else { [string]$Tier }
		# 'safe' is a legacy alias for 'basic' (renamed in v2.0). 'aggressive' is an alias for 'advanced'.
		switch -Regex ($normalizedTier.Trim())
		{
			'^\s*(aggressive|advanced)\s*$' { return 4 }
			'^\s*standard\s*$'              { return 4 }
			'^\s*balanced\s*$'              { return 3 }
			'^\s*(basic|safe)\s*$'          { return 2 }
			'^\s*minimal\s*$'               { return 1 }
			default                         { return 2 }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiPresetPolicyIssues
	{
		param (
			[string]$PresetName,
			[object[]]$PresetEntries,
			[hashtable]$ManifestByFunction = @{}
		)

		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		switch -Regex ($normalizedPresetName.Trim())
		{
			'^\s*(basic|safe)\s*$'          { $normalizedPresetName = 'Basic'; break }
			'^\s*minimal\s*$'               { $normalizedPresetName = 'Minimal'; break }
			'^\s*balanced\s*$'              { $normalizedPresetName = 'Balanced'; break }
			'^\s*(advanced|aggressive)\s*$' { $normalizedPresetName = 'Advanced'; break }
		}

		$basicAllowlistedActions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach (
			$approvedFunction in @(
				'CheckWinGet'
				'DesktopRegistry'
				'AutoRun'
				'DismissMSAccount'
				'DismissSmartScreenFilter'
				'Windows11SMBUpdateIssue'
				'UnpinTaskbarShortcuts'
			)
		)
		{
			[void]$basicAllowlistedActions.Add($approvedFunction)
		}

		$issues = [System.Collections.Generic.List[object]]::new()
		foreach ($presetEntry in @($PresetEntries))
		{
			if (-not $presetEntry) { continue }

			$commandLine = ''
			if ((Test-GuiObjectField -Object $presetEntry -FieldName 'RawLine') -and -not [string]::IsNullOrWhiteSpace([string]$presetEntry.RawLine))
			{
				$commandLine = [string]$presetEntry.RawLine
			}
			elseif (-not [string]::IsNullOrWhiteSpace([string]$presetEntry.FunctionName))
			{
				$commandLine = '{0} {1}' -f [string]$presetEntry.FunctionName, [string]$presetEntry.ArgumentText
			}

			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $ManifestByFunction.ContainsKey($functionName))
			{
				continue
			}

			$tweak = $ManifestByFunction[$functionName]
			$riskValue = [string]$tweak.Risk
			$typeValue = [string]$tweak.Type
			$presetTierValue = [string]$tweak.PresetTier
			$workflowSensitivityValue = [string]$tweak.WorkflowSensitivity
			$restorableValue = $null
			if ((Test-GuiObjectField -Object $tweak -FieldName 'Restorable'))
			{
				$restorableValue = $tweak.Restorable
			}
			$isRemovalOperation = ($functionName -match '^(?i)(uninstall|remove|delete)')
			if (-not $isRemovalOperation -and $typeValue -eq 'Choice')
			{
				$optionValues = @($tweak.Options | ForEach-Object { [string]$_ })
				if ($optionValues | Where-Object { $_ -match '^(?i)(uninstall|remove|delete)$' })
				{
					$isRemovalOperation = $true
				}
			}
			$issueReason = $null

			switch ($normalizedPresetName)
			{
				'Basic'
				{
					if ($riskValue -eq 'High' -or $presetTierValue -eq 'Advanced' -or $workflowSensitivityValue -eq 'High')
					{
						$issueReason = 'Basic cannot include high-risk, advanced-tier, or strongly workflow-sensitive changes.'
					}
					elseif ($presetTierValue -eq 'Balanced')
					{
						$issueReason = 'Basic cannot include balanced-tier changes.'
					}
					elseif ($typeValue -eq 'Action' -and $null -ne $restorableValue -and -not [bool]$restorableValue -and -not $basicAllowlistedActions.Contains($functionName))
					{
						$issueReason = 'Basic cannot include non-restorable action items unless explicitly allowlisted.'
					}
					elseif ($isRemovalOperation -and -not $basicAllowlistedActions.Contains($functionName))
					{
						$issueReason = 'Basic cannot include removal-style actions unless explicitly allowlisted.'
					}
				}
				'Balanced'
				{
					if ($riskValue -eq 'High' -or $presetTierValue -eq 'Advanced' -or $workflowSensitivityValue -eq 'High')
					{
						$issueReason = 'Balanced cannot include high-risk, advanced-tier, or strongly workflow-sensitive changes.'
					}
					elseif ($isRemovalOperation)
					{
						$issueReason = 'Balanced cannot include removal-style actions.'
					}
				}
			}

			if ($issueReason)
			{
				[void]$issues.Add([pscustomobject]@{
					PresetName = $normalizedPresetName
					Function = $functionName
					Command = $commandLine
					Type = $typeValue
					Risk = $riskValue
					PresetTier = $presetTierValue
					WorkflowSensitivity = $workflowSensitivityValue
					Restorable = $restorableValue
					Reason = $issueReason
				})
			}
		}

		return [pscustomobject]@{
			PresetName = $normalizedPresetName
			IsCompliant = ($issues.Count -eq 0)
			Issues = [object[]]$issues
		}
	}

	<#
	    .SYNOPSIS
	#>

	function ConvertTo-GuiPresetName
	{
		param ([string]$PresetName)

		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
		switch -Regex ($normalizedPresetName.Trim())
		{
			'^\s*minimal\s*$'               { return 'Minimal' }
			'^\s*balanced\s*$'              { return 'Balanced' }
			'^\s*(basic|safe)\s*$'          { return 'Basic' }
			'^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
			default                         { return 'Basic' }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiPresetNumericRangeArgumentText
	{
		param ([object]$Entry)

		if (-not $Entry)
		{
			return $null
		}

		$valueSource = $null
		if ((Test-GuiObjectField -Object $Entry -FieldName 'Value'))
		{
			$valueSource = $Entry.Value
		}
		elseif ((Test-GuiObjectField -Object $Entry -FieldName 'NumericValue'))
		{
			$valueSource = $Entry.NumericValue
		}
		else
		{
			$valueSource = $Entry
		}

		$hasChannelValues = ((Test-GuiObjectField -Object $Entry -FieldName 'ACValue') -or (Test-GuiObjectField -Object $Entry -FieldName 'DCValue'))
		if (-not $hasChannelValues -and $valueSource)
		{
			$hasChannelValues = ((Test-GuiObjectField -Object $valueSource -FieldName 'ACValue') -or (Test-GuiObjectField -Object $valueSource -FieldName 'DCValue'))
		}

		if ($hasChannelValues)
		{
			$acValue = if ((Test-GuiObjectField -Object $Entry -FieldName 'ACValue')) { $Entry.ACValue } elseif ((Test-GuiObjectField -Object $valueSource -FieldName 'ACValue')) { $valueSource.ACValue } else { $null }
			$dcValue = if ((Test-GuiObjectField -Object $Entry -FieldName 'DCValue')) { $Entry.DCValue } elseif ((Test-GuiObjectField -Object $valueSource -FieldName 'DCValue')) { $valueSource.DCValue } else { $null }

			$argumentParts = [System.Collections.Generic.List[string]]::new()
			if ($null -ne $acValue)
			{
				[void]$argumentParts.Add('-ACValue')
				[void]$argumentParts.Add([string]$acValue)
			}
			if ($null -ne $dcValue)
			{
				[void]$argumentParts.Add('-DCValue')
				[void]$argumentParts.Add([string]$dcValue)
			}

			if ($argumentParts.Count -gt 0)
			{
				return ($argumentParts -join ' ')
			}
		}

		$scalarValue = $null
		foreach ($fieldName in @('NumericValue', 'Value'))
		{
			if ((Test-GuiObjectField -Object $Entry -FieldName $fieldName))
			{
				$fieldValue = $Entry.$fieldName
				if ($null -ne $fieldValue)
				{
						if ($fieldValue -is [System.Collections.IDictionary] -or $fieldValue -is [pscustomobject])
					{
						foreach ($nestedField in @('NumericValue', 'Value'))
						{
							if ((Test-GuiObjectField -Object $fieldValue -FieldName $nestedField) -and $null -ne $fieldValue.$nestedField)
							{
								$scalarValue = $fieldValue.$nestedField
								break
							}
						}
						if ($null -ne $scalarValue)
						{
							break
						}
					}
					else
					{
						$scalarValue = $fieldValue
						break
					}
				}
			}
		}

		if ($null -eq $scalarValue)
		{
			return $null
		}

		return ('-Value {0}' -f [string]$scalarValue)
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakMatchesPresetTier
	{
		param (
			[hashtable]$Tweak,
			[string]$Tier
		)

		if (-not $Tweak) { return $false }
		$getPresetTierRankScript = ${function:Get-PresetTierRank}
		if (-not $getPresetTierRankScript) { return $false }
		return ((& $getPresetTierRankScript -Tier $Tweak.PresetTier) -le (& $getPresetTierRankScript -Tier $Tier))
	}

