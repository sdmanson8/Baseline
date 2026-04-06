# Shared helper slice for Baseline.

function Convert-JsonManifestValue
{
	<# .SYNOPSIS Recursively converts JSON manifest values to native PowerShell types. #>
	[CmdletBinding()]
	param($Value)

	if ($null -eq $Value) { return $null }

	if ($Value -is [System.Collections.IDictionary])
	{
		$hash = @{}
		foreach ($key in $Value.Keys)
		{
			$hash[$key] = Convert-JsonManifestValue $Value[$key]
		}
		return $hash
	}

	if ($Value -is [pscustomobject])
	{
		$hash = @{}
		foreach ($prop in $Value.PSObject.Properties)
		{
			$hash[$prop.Name] = Convert-JsonManifestValue $prop.Value
		}
		return $hash
	}

	if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]))
	{
		$items = [System.Collections.Generic.List[object]]::new()
		foreach ($item in $Value)
		{
			$items.Add((Convert-JsonManifestValue $item))
		}
		return ,$items.ToArray()
	}

	return $Value
}

function ConvertTo-NormalizedParameterName
{
	<# .SYNOPSIS Trims and removes leading dashes from parameter names. #>
	param([object]$Value)

	if ($null -eq $Value)
	{
		return $null
	}

	$text = [string]$Value
	if ([string]::IsNullOrWhiteSpace($text))
	{
		return $null
	}

	return $text.Trim().TrimStart('-')
}

function ConvertTo-TweakRiskLevel
{
	<# .SYNOPSIS Normalizes risk level strings to Low, Medium, or High. #>
	param([object]$Value)

	if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value))
	{
		return 'Low'
	}

	switch -Regex ([string]$Value)
	{
		'^\s*high\s*$'   { return 'High' }
		'^\s*medium\s*$' { return 'Medium' }
		default          { return 'Low' }
	}
}

function ConvertTo-TweakPresetTier
{
	<# .SYNOPSIS Normalizes preset tier strings to Minimal, Basic, Balanced, or Advanced. #>
	param (
		[object]$Value,
		[string]$Risk = 'Low',
		[bool]$Impact = $false
	)

	if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value))
	{
		switch -Regex ([string]$Value)
		{
			'^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
			'^\s*balanced\s*$'              { return 'Balanced' }
			'^\s*minimal\s*$'               { return 'Minimal' }
			'^\s*(basic|safe)\s*$'          { return 'Basic' }
			default                         { return 'Basic' }
		}
	}

	if ($Impact -or $Risk -eq 'High')
	{
		return 'Advanced'
	}
	if ($Risk -eq 'Medium')
	{
		return 'Balanced'
	}

	return 'Basic'
}

function ConvertTo-TweakWorkflowSensitivity
{
	<# .SYNOPSIS Normalizes workflow sensitivity strings to Low, Moderate, or High. #>
	param (
		[object]$Value,
		[string[]]$Tags = @()
	)

	if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value))
	{
		switch -Regex ([string]$Value)
		{
			'^\s*high\s*$' { return 'High' }
			'^\s*(medium|moderate)\s*$' { return 'Moderate' }
			'^\s*low\s*$' { return 'Low' }
			default { return 'Low' }
		}
	}

	return 'Low'
}

function Convert-ToWhyThisMattersText
{
	<# .SYNOPSIS Extracts the first sentence and truncates to 180 characters. #>
	param ([string]$Text)

	if ([string]::IsNullOrWhiteSpace($Text))
	{
		return $null
	}

	$normalized = (($Text -replace '\s+', ' ').Trim())
	if ([string]::IsNullOrWhiteSpace($normalized))
	{
		return $null
	}

	$firstSentence = $normalized
	if ($normalized -match '^(.+?[.!?])(?:\s+|$)')
	{
		$firstSentence = $matches[1].Trim()
	}

	if ($firstSentence.Length -gt 180)
	{
		return ($firstSentence.Substring(0, 177).TrimEnd() + '...')
	}

	return $firstSentence
}

function Write-ManifestValidationWarning
{
	<# .SYNOPSIS Writes a manifest validation warning via LogWarning or Write-Warning. #>
	param ([string]$Message)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	$logWarningCommand = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
	if ($logWarningCommand)
	{
		LogWarning $Message
		return
	}

	Write-Warning $Message
}

function Import-TweakManifestFromData
{
	<# .SYNOPSIS Loads tweak manifest JSON files with priority-based categorization. #>
	[CmdletBinding()]
	param (
		[hashtable]$DetectScriptblocks = @{},
		[hashtable]$VisibleIfScriptblocks = @{},
		[string]$ModuleRoot
	)

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$dataDir = Join-Path $resolvedRoot 'Data'
	if (-not (Test-Path -LiteralPath $dataDir))
	{
		throw "Module/Data directory not found: $dataDir"
	}

	$categoryPriority = @{
		'Initial Setup'        = 0
		'OS Hardening'         = 1
		'Privacy & Telemetry'  = 2
		'System Tweaks'        = 3
		'UI & Personalization' = 4
		'OneDrive'             = 5
		'System'               = 6
		'UWP Apps'             = 7
		'Gaming'               = 8
		'Security'             = 9
		'Context Menu'         = 10
		'Taskbar Clock'        = 11
		'Cursors'              = 12
		'Start Menu Apps'      = 13
		'Start Menu'           = 90
		'Taskbar'              = 91
	}

	$buckets = @{}
	$entryOrder = 0
	foreach ($dataFile in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' | Sort-Object Name))
	{
		$rawJson = Get-Content -LiteralPath $dataFile.FullName -Raw -ErrorAction Stop
		if ([string]::IsNullOrWhiteSpace($rawJson)) { continue }

		$payload = $rawJson | ConvertFrom-Json -ErrorAction Stop
		$category = if ($payload.PSObject.Properties['Tab'] -and -not [string]::IsNullOrWhiteSpace($payload.Tab))
		{
			[string]$payload.Tab
		}
		else
		{
			[System.IO.Path]::GetFileNameWithoutExtension($dataFile.Name)
		}
		$priority = if ($categoryPriority.ContainsKey($category)) { $categoryPriority[$category] } else { 50 }

		foreach ($entry in @($payload.Entries))
		{
			if (-not $entry) { continue }
			if ([string]::IsNullOrWhiteSpace($entry.Name) -or [string]::IsNullOrWhiteSpace($entry.Function)) { continue }
			$entryOrder++

			$riskValue = ConvertTo-TweakRiskLevel -Value $(if ($entry.PSObject.Properties['Risk']) { $entry.Risk } else { $null })

			$tagValues = @()
			if ($entry.PSObject.Properties['Tags'] -and $null -ne $entry.Tags)
			{
				$tagValues = @(
					@(Convert-JsonManifestValue $entry.Tags) |
						ForEach-Object { [string]$_ } |
						Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
						ForEach-Object { $_.Trim().ToLowerInvariant() } |
						Select-Object -Unique
				)
			}

			$impactValue = if ($entry.PSObject.Properties['Impact']) { [bool]$entry.Impact } else { [bool]$entry.Caution }
			$safeValue = if ($entry.PSObject.Properties['Safe']) { [bool]$entry.Safe } else { ($riskValue -eq 'Low' -and -not $impactValue) }
			$requiresRestartValue = if ($entry.PSObject.Properties['RequiresRestart']) { [bool]$entry.RequiresRestart } else { $false }
			$presetTierValue = ConvertTo-TweakPresetTier -Value $(if ($entry.PSObject.Properties['PresetTier']) { $entry.PresetTier } else { $null }) -Risk $riskValue -Impact $impactValue
			$workflowSensitivityValue = ConvertTo-TweakWorkflowSensitivity -Value $(if ($entry.PSObject.Properties['WorkflowSensitivity']) { $entry.WorkflowSensitivity } else { $null }) -Tags $tagValues
			if ($presetTierValue -eq 'Advanced' -and $tagValues -notcontains 'advanced')
			{
				$tagValues += 'advanced'
			}
			$whyThisMattersValue = Convert-ToWhyThisMattersText -Text $(if ($entry.PSObject.Properties['WhyThisMatters'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.WhyThisMatters)) {
				[string]$entry.WhyThisMatters
			}
			elseif ($entry.PSObject.Properties['Detail']) {
				[string]$entry.Detail
			}
			else {
				$null
			})

			$tweakEntry = [ordered]@{
				Name            = [string]$entry.Name
				Category        = $category
				Function        = [string]$entry.Function
				Type            = [string]$entry.Type
				Default         = Convert-JsonManifestValue $entry.Default
				WinDefault      = Convert-JsonManifestValue $entry.WinDefault
				Description     = if ($entry.PSObject.Properties['Description']) { [string]$entry.Description } else { '' }
				Caution         = if ($entry.PSObject.Properties['Caution']) { [bool]$entry.Caution } else { $false }
				Risk            = $riskValue
				Tags            = $tagValues
				Impact          = $impactValue
				Safe            = $safeValue
				RequiresRestart = $requiresRestartValue
				PresetTier      = $presetTierValue
				WorkflowSensitivity = $workflowSensitivityValue
				WhyThisMatters  = $whyThisMattersValue
			}

			foreach ($propName in @('WinDefaultDesc', 'Detail', 'CautionReason', 'LinkedWith', 'Scannable', 'Restorable', 'RecoveryLevel', 'OnParam', 'OffParam', 'SubCategory', 'GamingPreviewGroup', 'GameModeDefault', 'TroubleshootingOnly', 'DecisionPromptKey'))
			{
				if ($entry.PSObject.Properties[$propName] -and $null -ne $entry.$propName)
				{
					$tweakEntry[$propName] = Convert-JsonManifestValue $entry.$propName
				}
			}

			foreach ($arrayProp in @('Options', 'DisplayOptions', 'ScenarioTags'))
			{
				if ($entry.PSObject.Properties[$arrayProp] -and $null -ne $entry.$arrayProp)
				{
					# Convert-JsonManifestValue already returns arrays via unary comma;
					# wrapping in @() would double-nest and collapse to "A B" on [string[]] cast.
					$tweakEntry[$arrayProp] = Convert-JsonManifestValue $entry.$arrayProp
				}
			}

			if ($entry.PSObject.Properties['ExtraArgs'] -and $null -ne $entry.ExtraArgs)
			{
				$tweakEntry['ExtraArgs'] = Convert-JsonManifestValue $entry.ExtraArgs
			}

			if ($entry.PSObject.Properties['GameModeDefaultByProfile'] -and $null -ne $entry.GameModeDefaultByProfile)
			{
				$tweakEntry['GameModeDefaultByProfile'] = Convert-JsonManifestValue $entry.GameModeDefaultByProfile
			}

			$fn = $tweakEntry.Function
			if ($DetectScriptblocks.ContainsKey($fn))
			{
				$tweakEntry['Detect'] = $DetectScriptblocks[$fn]
			}
			if ($VisibleIfScriptblocks.ContainsKey($fn))
			{
				$tweakEntry['VisibleIf'] = $VisibleIfScriptblocks[$fn]
			}

			$key = '{0}|{1}' -f $tweakEntry.Name, $tweakEntry.Function
			if ((-not $buckets.ContainsKey($key)) -or ($priority -lt $buckets[$key].Priority))
			{
				$buckets[$key] = [ordered]@{
					Entry    = $tweakEntry
					Priority = $priority
					Order    = $entryOrder
				}
			}
		}
	}

	$sorted = $buckets.Values | Sort-Object { $_.Priority }, { $_.Order }
	$manifest = New-Object System.Collections.ArrayList
	foreach ($bucket in $sorted)
	{
		[void]$manifest.Add($bucket.Entry)
	}

	return ,@($manifest)
}

function Test-TweakManifestEntryField
{
	<# .SYNOPSIS Tests whether a manifest entry has a specific field. #>
	param (
		[object]$Entry,
		[string]$FieldName
	)

	if ($null -eq $Entry -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $false
	}

	if ($Entry -is [System.Collections.IDictionary])
	{
		return [bool]$Entry.Contains($FieldName)
	}

	if ($Entry.PSObject -and $Entry.PSObject.Properties[$FieldName])
	{
		return $true
	}

	return $false
}

function Get-TweakManifestEntryValue
{
	<# .SYNOPSIS Retrieves a value from a manifest entry by field name. #>
	param (
		[object]$Entry,
		[string]$FieldName
	)

	if (-not (Test-TweakManifestEntryField -Entry $Entry -FieldName $FieldName))
	{
		return $null
	}

	if ($Entry -is [System.Collections.IDictionary])
	{
		return $Entry[$FieldName]
	}

	return $Entry.$FieldName
}

function Get-TweakManifestDefaultCommand
{
	<# .SYNOPSIS Generates the default command line for a manifest entry. #>
	[CmdletBinding()]
	param (
		[object]$Entry
	)

	if ($null -eq $Entry)
	{
		return $null
	}

	$functionName = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Function')
	if ([string]::IsNullOrWhiteSpace($functionName))
	{
		return $null
	}

	$typeValue = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Type')
	switch ($typeValue)
	{
		'Toggle'
		{
			$defaultValue = $false
			if ((Test-TweakManifestEntryField -Entry $Entry -FieldName 'Default') -and $null -ne (Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Default'))
			{
				$defaultValue = [bool](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Default')
			}

				$paramName = if ($defaultValue)
				{
					ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $Entry -FieldName 'OnParam')
				}
				else
				{
					ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $Entry -FieldName 'OffParam')
				}

			if ([string]::IsNullOrWhiteSpace($paramName))
			{
				$paramName = if ($defaultValue) { 'Enable' } else { 'Disable' }
			}

			return ('{0} -{1}' -f $functionName, $paramName)
		}
		'Choice'
		{
			$defaultChoice = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Default'
			if ($null -eq $defaultChoice)
			{
				return $functionName
			}

			$choiceValue = [string]$defaultChoice
			if ([string]::IsNullOrWhiteSpace($choiceValue))
			{
				return $functionName
			}

			return ('{0} -{1}' -f $functionName, $choiceValue)
		}
		default
		{
			return $functionName
		}
	}
}

function Get-ManifestEntryByFunction
{
	<# .SYNOPSIS Searches the manifest for an entry matching a function name. #>
	[CmdletBinding()]
	param (
		[array]$Manifest,
		[string]$Function
	)

	if (-not $Manifest -or [string]::IsNullOrWhiteSpace($Function))
	{
		return $null
	}

	foreach ($entry in @($Manifest))
	{
		$entryFunction = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function')
		if ([string]::IsNullOrWhiteSpace($entryFunction)) { continue }
		if ($entryFunction.Equals($Function, [System.StringComparison]::OrdinalIgnoreCase))
		{
			return $entry
		}
	}

	return $null
}

function Get-ValidScenarioTagCatalog
{
	<# .SYNOPSIS Returns the set of valid scenario tags. #>
	$catalog = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($tag in @(
		'gaming'
		'privacy'
		'cleanup'
		'compatibility'
		'performance'
		'hardening'
		'security'
		'office'
		'network'
		'networking'
		'defender'
		'update'
		'updates'
		'ui'
		'recovery'
		'repair'
		'quality-of-life'
		'power'
	))
	{
		[void]$catalog.Add($tag)
	}

	foreach ($definition in @(Get-GameModeProfileDefinitions))
	{
		if ($definition -and -not [string]::IsNullOrWhiteSpace([string]$definition.Name))
		{
			[void]$catalog.Add(([string]$definition.Name).ToLowerInvariant())
		}
	}

	foreach ($definition in @(Get-ScenarioProfileDefinitions))
	{
		if ($definition -and -not [string]::IsNullOrWhiteSpace([string]$definition.Name))
		{
			[void]$catalog.Add(([string]$definition.Name).ToLowerInvariant())
		}
	}

	return @($catalog | Sort-Object)
}

function Get-ValidGamingPreviewGroups
{
	<# .SYNOPSIS Returns the array of valid Gaming preview group names. #>
	return @(
		'Core Performance'
		'Xbox & Overlay'
		'Compatibility & Troubleshooting'
		'Background & Notifications'
		'Advanced: Compatibility'
		'Advanced: Performance'
		'Advanced: Session Behavior'
		'Advanced: Overlay'
	)
}

function Get-ValidGameModeProfileNames
{
	<# .SYNOPSIS Returns the array of valid Game Mode profile names. #>
	return @(
		Get-GameModeProfileDefinitions |
			ForEach-Object { [string]$_.Name } |
			Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
	)
}

function Test-TweakManifestIntegrity
{
	<# .SYNOPSIS Validates manifest structure, required fields, and value constraints. #>
	param (
		[array]$Manifest
	)

	if (-not $Manifest -or $Manifest.Count -eq 0)
	{
		Write-ManifestValidationWarning 'Manifest validation: manifest is empty'
		return
	}

	$requiredFields = @('Name', 'Function', 'Type', 'Category', 'Risk', 'PresetTier')
	$validTypes = @('Toggle', 'Action', 'Choice')
	$validRisks = @('Low', 'Medium', 'High')
	# Safe remains as a legacy alias while the preset tier naming settles on Basic.
	$validTiers = @('Minimal', 'Basic', 'Safe', 'Balanced', 'Advanced')
	$validWorkflowSensitivities = @('Low', 'Moderate', 'High')
	$validRecoveryLevels = @('Direct', 'DefaultsOnly', 'RestorePoint', 'Manual')
	$validScenarioTags = @(Get-ValidScenarioTagCatalog)
	$validGamingPreviewGroups = @(Get-ValidGamingPreviewGroups)
	$validGameModeProfiles = @(Get-ValidGameModeProfileNames)
	$validDecisionPromptKeys = @(Get-GameModeDecisionPromptKeyCatalog)
	$issues = [System.Collections.ArrayList]::new()

	foreach ($tweak in $Manifest)
	{
		$typeValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Type')
		$riskValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Risk')
		$presetTierValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'PresetTier')
		$label = if ((Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Function')) { $tweak.Function } else { $tweak.Name }
		foreach ($field in $requiredFields)
		{
			if (-not (Test-TweakManifestEntryField -Entry $tweak -FieldName $field) -or [string]::IsNullOrWhiteSpace([string](Get-TweakManifestEntryValue -Entry $tweak -FieldName $field)))
			{
				[void]$issues.Add("$label : missing $field")
			}
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'Type') -and $validTypes -notcontains $typeValue)
		{
			[void]$issues.Add("$label : invalid Type '$typeValue'")
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'Risk') -and $validRisks -notcontains $riskValue)
		{
			[void]$issues.Add("$label : invalid Risk '$riskValue'")
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'PresetTier') -and $validTiers -notcontains $presetTierValue)
		{
			[void]$issues.Add("$label : invalid PresetTier '$presetTierValue'")
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'WorkflowSensitivity'))
		{
			$workflowSensitivityValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'WorkflowSensitivity')
			if ([string]::IsNullOrWhiteSpace($workflowSensitivityValue))
			{
				[void]$issues.Add("$label : missing WorkflowSensitivity")
			}
			elseif ($validWorkflowSensitivities -notcontains $workflowSensitivityValue)
			{
				[void]$issues.Add("$label : invalid WorkflowSensitivity '$workflowSensitivityValue'")
			}
		}
		$hasToggleUndoParams = (
			$typeValue -eq 'Toggle' -and
			(Test-TweakManifestEntryField -Entry $tweak -FieldName 'OnParam') -and
			(Test-TweakManifestEntryField -Entry $tweak -FieldName 'OffParam') -and
			-not [string]::IsNullOrWhiteSpace([string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'OnParam')) -and
			-not [string]::IsNullOrWhiteSpace([string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'OffParam'))
		)
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'Restorable') -and $null -eq (Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Restorable'))
		{
			[void]$issues.Add($(if ($hasToggleUndoParams) {
				"$label : toggle has OnParam/OffParam but Restorable is still null and needs an explicit audit result"
			}
			else {
				"$label : Restorable is still null and needs an explicit audit result"
			}))
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'RecoveryLevel'))
		{
			$recoveryLevelValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'RecoveryLevel')
			if ([string]::IsNullOrWhiteSpace($recoveryLevelValue))
			{
				[void]$issues.Add("$label : missing RecoveryLevel")
			}
			elseif ($validRecoveryLevels -notcontains $recoveryLevelValue)
			{
				[void]$issues.Add("$label : invalid RecoveryLevel '$recoveryLevelValue'")
			}
		}
		$scenarioTags = @(Get-TweakManifestEntryValue -Entry $tweak -FieldName 'ScenarioTags')
		foreach ($scenarioTag in $scenarioTags)
		{
			$scenarioTagValue = [string]$scenarioTag
			if ([string]::IsNullOrWhiteSpace($scenarioTagValue)) { continue }
			if ($validScenarioTags -notcontains $scenarioTagValue.ToLowerInvariant())
			{
				[void]$issues.Add("$label : unknown ScenarioTag '$scenarioTagValue'")
			}
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'GamingPreviewGroup'))
		{
			$gamingPreviewGroupValue = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'GamingPreviewGroup')
			if (-not [string]::IsNullOrWhiteSpace($gamingPreviewGroupValue) -and $validGamingPreviewGroups -notcontains $gamingPreviewGroupValue)
			{
				[void]$issues.Add("$label : invalid GamingPreviewGroup '$gamingPreviewGroupValue'")
			}
			elseif (-not [string]::IsNullOrWhiteSpace($gamingPreviewGroupValue) -and $scenarioTags.Count -eq 0)
			{
				[void]$issues.Add("$label : GamingPreviewGroup requires ScenarioTags")
			}
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'GameModeDefaultByProfile'))
		{
			$profileDefaults = Get-TweakManifestEntryValue -Entry $tweak -FieldName 'GameModeDefaultByProfile'
			if ($null -eq $profileDefaults)
			{
				[void]$issues.Add("$label : GameModeDefaultByProfile is null")
			}
			else
			{
				foreach ($profileKey in $profileDefaults.Keys)
				{
					if ($validGameModeProfiles -notcontains [string]$profileKey)
					{
						[void]$issues.Add("$label : invalid GameMode profile key '$profileKey'")
					}
				}
			}
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'DecisionPromptKey'))
		{
			$decisionPromptKey = [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'DecisionPromptKey')
			if (-not [string]::IsNullOrWhiteSpace($decisionPromptKey) -and $validDecisionPromptKeys -notcontains $decisionPromptKey)
			{
				[void]$issues.Add("$label : invalid DecisionPromptKey '$decisionPromptKey'")
			}
		}
		$hasTroubleshootingScenarioTag = $false
		foreach ($scenarioTag in $scenarioTags)
		{
			if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
			if ([string]$scenarioTag -match '^\s*troubleshooting\s*$')
			{
				$hasTroubleshootingScenarioTag = $true
				break
			}
		}
		if ((Test-TweakManifestEntryField -Entry $tweak -FieldName 'TroubleshootingOnly') -and [bool](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'TroubleshootingOnly') -and $riskValue -eq 'Low' -and -not $hasTroubleshootingScenarioTag)
		{
			[void]$issues.Add("$label : TroubleshootingOnly is true but no troubleshooting ScenarioTag is present")
		}
		if ((@(Get-GameModeAllowlist) -contains [string](Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Function')) -and -not (Test-GameModeAllowlistEntryReviewed -Entry $tweak))
		{
			[void]$issues.Add("$label : cross-category Game Mode allowlist entries must be added to the reviewed cross-category allowlist")
		}
		if ((Test-GameModeManifestDefaultEnabled -Entry $tweak) -and -not (Test-GameModeProfileDefaultEligible -Entry $tweak))
		{
			[void]$issues.Add("$label : Game Mode defaults require a reviewed allowlist entry with Type=Toggle, Risk=Low, Safe=true, and WorkflowSensitivity=Low")
		}
		if ($typeValue -eq 'Choice' -and (-not (Test-TweakManifestEntryField -Entry $tweak -FieldName 'Options') -or @((Get-TweakManifestEntryValue -Entry $tweak -FieldName 'Options')).Count -eq 0))
		{
			[void]$issues.Add("$label : Choice tweak missing Options")
		}
		if ($typeValue -eq 'Toggle' -and -not (Test-TweakManifestEntryField -Entry $tweak -FieldName 'Default'))
		{
			[void]$issues.Add("$label : Toggle tweak missing Default")
		}
	}

	if ($issues.Count -gt 0)
	{
		Write-ManifestValidationWarning ("Manifest validation: {0} issue(s) found" -f $issues.Count)
		foreach ($issue in $issues)
		{
			Write-ManifestValidationWarning "  $issue"
		}
	}
}

function Get-TweakRestartGroups
{
	<# .SYNOPSIS Groups a run list into restart-required and no-restart collections. #>
	[CmdletBinding()]
	param ([object[]]$RunList)

	$restartRequired = [System.Collections.Generic.List[object]]::new()
	$noRestart = [System.Collections.Generic.List[object]]::new()
	$categoryGroups = @{}

	foreach ($item in @($RunList | Where-Object { $_ }))
	{
		$needsRestart = (Test-GuiObjectField -Object $item -FieldName 'RequiresRestart') -and [bool]$item.RequiresRestart
		if ($needsRestart)
		{
			[void]$restartRequired.Add($item)
			$cat = if ((Test-GuiObjectField -Object $item -FieldName 'Category') -and -not [string]::IsNullOrWhiteSpace([string]$item.Category)) { [string]$item.Category }
				elseif ((Test-GuiObjectField -Object $item -FieldName 'SourceRegion') -and -not [string]::IsNullOrWhiteSpace([string]$item.SourceRegion)) { [string]$item.SourceRegion }
				else { 'General' }
			if (-not $categoryGroups.ContainsKey($cat))
			{
				$categoryGroups[$cat] = [System.Collections.Generic.List[object]]::new()
			}
			[void]$categoryGroups[$cat].Add($item)
		}
		else
		{
			[void]$noRestart.Add($item)
		}
	}

	return [pscustomobject]@{
		RestartRequired = @($restartRequired)
		NoRestart       = @($noRestart)
		RestartCount    = $restartRequired.Count
		ByCategory      = $categoryGroups
	}
}

function Get-TweakDependencyInfo
{
	<# .SYNOPSIS Aggregates dependency and impact metadata from a single manifest entry. #>
	[CmdletBinding()]
	param ([object]$Entry)

	if (-not $Entry) { return $null }

	$requiresRestart = if ((Test-GuiObjectField -Object $Entry -FieldName 'RequiresRestart')) { [bool]$Entry.RequiresRestart } else { $false }
	$whyThisMatters = if ((Test-GuiObjectField -Object $Entry -FieldName 'WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Entry.WhyThisMatters)) { [string]$Entry.WhyThisMatters } else { $null }
	$impact = if ((Test-GuiObjectField -Object $Entry -FieldName 'Impact') -and -not [string]::IsNullOrWhiteSpace([string]$Entry.Impact)) { [string]$Entry.Impact } else { 'Low' }
	$cautionReason = if ((Test-GuiObjectField -Object $Entry -FieldName 'CautionReason') -and -not [string]::IsNullOrWhiteSpace([string]$Entry.CautionReason)) { [string]$Entry.CautionReason } else { $null }

	# Derive feature dependencies from Detail/Description text patterns
	$dependsOnFeatures = [System.Collections.Generic.List[string]]::new()
	$searchText = @(
		$(if ((Test-GuiObjectField -Object $Entry -FieldName 'Detail')) { [string]$Entry.Detail } else { '' }),
		$(if ((Test-GuiObjectField -Object $Entry -FieldName 'Description')) { [string]$Entry.Description } else { '' }),
		$(if ($whyThisMatters) { $whyThisMatters } else { '' })
	) -join ' '

	$featurePatterns = @(
		@{ Pattern = '(?i)requires?\s+Windows\s+Feature\s+Experience\s+Pack'; Label = 'Windows Feature Experience Pack' },
		@{ Pattern = '(?i)requires?\s+Xbox\s+Game\s+Bar'; Label = 'Xbox Game Bar' },
		@{ Pattern = '(?i)requires?\s+\.NET'; Label = '.NET Framework' },
		@{ Pattern = '(?i)requires?\s+Windows\s+Subsystem'; Label = 'Windows Subsystem for Linux' },
		@{ Pattern = '(?i)requires?\s+Hyper-?V'; Label = 'Hyper-V' },
		@{ Pattern = '(?i)requires?\s+BitLocker'; Label = 'BitLocker' },
		@{ Pattern = '(?i)requires?\s+TPM'; Label = 'TPM' },
		@{ Pattern = '(?i)requires?\s+winget'; Label = 'winget' },
		@{ Pattern = '(?i)requires?\s+Microsoft\s+Store'; Label = 'Microsoft Store' }
	)
	foreach ($fp in $featurePatterns)
	{
		if ($searchText -match $fp.Pattern -and -not ($dependsOnFeatures -contains $fp.Label))
		{
			[void]$dependsOnFeatures.Add($fp.Label)
		}
	}

	# Check ConflictsWith for implicit dependencies
	if ((Test-GuiObjectField -Object $Entry -FieldName 'ConflictsWith') -and $Entry.ConflictsWith)
	{
		foreach ($conflict in @($Entry.ConflictsWith))
		{
			if ((Test-GuiObjectField -Object $conflict -FieldName 'Function') -and -not [string]::IsNullOrWhiteSpace([string]$conflict.Function))
			{
				$depLabel = [string]$conflict.Function
				if (-not ($dependsOnFeatures -contains $depLabel))
				{
					[void]$dependsOnFeatures.Add($depLabel)
				}
			}
		}
	}

	return [pscustomobject]@{
		RequiresRestart   = $requiresRestart
		WhyThisMatters    = $whyThisMatters
		Impact            = $impact
		CautionReason     = $cautionReason
		DependsOnFeatures = @($dependsOnFeatures)
	}
}
