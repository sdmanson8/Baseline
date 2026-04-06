<#
	.SYNOPSIS
	Validate tweak metadata files under Module/Data.

	.DESCRIPTION
	Checks that JSON payloads load successfully, required entry fields exist,
	duplicate Name|Function keys are not present across files, each SourceRegion
	points at a real region module that actually defines the declared function,
	and curated preset files stay inside their intended manifest tiers.

	.EXAMPLE
	pwsh -File .\Tools\Validate-ManifestData.ps1
#>

[CmdletBinding()]
param (
	[string]$PresetDirectory,
	[switch]$AllowPartialPresetDirectory
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot 'Module'

if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container))
{
	throw "Module directory not found under: $repoRoot"
}

$dataDir = Join-Path $moduleRoot 'Data'
$regionDir = Join-Path $moduleRoot 'Regions'

if (-not (Test-Path -LiteralPath $dataDir))
{
	throw "Data directory not found: $dataDir"
}

if (-not (Test-Path -LiteralPath $regionDir))
{
	throw "Region directory not found: $regionDir"
}

Import-Module -Name (Join-Path $moduleRoot 'SharedHelpers.psm1') -Force -ErrorAction Stop

$issues = New-Object System.Collections.ArrayList
$entryKeys = @{}
$regionFunctions = @{}
$manifestEntriesByFunction = @{}
$totalEntries = 0
$dataFileCount = 0
$validRecoveryLevels = @('Direct', 'DefaultsOnly', 'RestorePoint', 'Manual')
$validCompatibilitySensitivityValues = @('Low', 'Medium', 'High')
$validScenarioTags = @(Get-ValidScenarioTagCatalog)
$validGamingPreviewGroups = @(Get-ValidGamingPreviewGroups)
$validGameModeProfiles = @(Get-ValidGameModeProfileNames)
$validDecisionPromptKeys = @(Get-GameModeDecisionPromptKeyCatalog)
$gameModeAllowlist = @(Get-GameModeAllowlist)
$gameModeReviewedCrossCategoryAllowlist = @(Get-GameModeReviewedCrossCategoryAllowlist)

function Test-PresetCommandIsRemovalOperation
{
	param(
		[string]$CommandLine,
		[object]$ManifestEntry
	)

	if ([string]::IsNullOrWhiteSpace($CommandLine))
	{
		return $false
	}

	$functionName = ([string]$CommandLine -split '\s+', 2)[0].Trim()
	if ($functionName -match '^(?i)(uninstall|remove|delete)')
	{
		return $true
	}

	if ($CommandLine -match '(?i)(?:^|\s)-(?:uninstall|remove|delete)(?=\s|$)')
	{
		return $true
	}

	if (-not $ManifestEntry)
	{
		return $false
	}

	if (-not $ManifestEntry.PSObject.Properties['Type'] -or [string]$ManifestEntry.Type -ne 'Choice')
	{
		return $false
	}

	$selectedOption = $null
	$parts = [string]$CommandLine -split '\s+', 2
	if ($parts.Count -gt 1)
	{
		$selectedOption = $parts[1].Trim()
		if ($selectedOption.StartsWith('-'))
		{
			$selectedOption = $selectedOption.Substring(1).Trim()
		}
	}
	elseif ($ManifestEntry.PSObject.Properties['Default'] -and $null -ne $ManifestEntry.Default)
	{
		$selectedOption = [string]$ManifestEntry.Default
	}

	if ([string]::IsNullOrWhiteSpace($selectedOption))
	{
		return $false
	}

	return ($selectedOption -match '^(?i)(uninstall|remove|delete)$')
}

function Test-ManifestEntryHasNonEmptyPropertyValue
{
	param(
		[object]$Entry,
		[string]$PropertyName
	)

	if (-not $Entry -or -not $Entry.PSObject.Properties[$PropertyName])
	{
		return $false
	}

	$value = $Entry.$PropertyName
	if ($null -eq $value)
	{
		return $false
	}

	return -not [string]::IsNullOrWhiteSpace([string]$value)
}

function ConvertTo-NormalizedManifestParameterName
{
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

function Test-ManifestEntryHasReversibleToggleParameters
{
	param(
		[object]$Entry
	)

	return (
		$Entry -and
		[string]$Entry.Type -eq 'Toggle' -and
		(Test-ManifestEntryHasNonEmptyPropertyValue -Entry $Entry -PropertyName 'OnParam') -and
		(Test-ManifestEntryHasNonEmptyPropertyValue -Entry $Entry -PropertyName 'OffParam')
	)
}

function Test-ManifestEntryHasReversibleChoiceDefaults
{
	param(
		[object]$Entry
	)

	if (-not $Entry -or [string]$Entry.Type -ne 'Choice')
	{
		return $false
	}

	$choiceValues = New-Object System.Collections.Generic.List[string]
	if ($Entry.PSObject.Properties['Options'] -and $null -ne $Entry.Options)
	{
		foreach ($option in @($Entry.Options))
		{
			$optionText = [string]$option
			if (-not [string]::IsNullOrWhiteSpace($optionText))
			{
				[void]$choiceValues.Add($optionText.Trim())
			}
		}
	}

	foreach ($propertyName in @('Default', 'WinDefault'))
	{
		if ($Entry.PSObject.Properties[$propertyName] -and $null -ne $Entry.$propertyName)
		{
			$valueText = [string]$Entry.$propertyName
			if (-not [string]::IsNullOrWhiteSpace($valueText))
			{
				[void]$choiceValues.Add($valueText.Trim())
			}
		}
	}

	# Package-style install/remove choices can still expose Default/WinDefault values
	# without providing a direct or defaults-only recovery path.
	if (@($choiceValues | Where-Object { $_ -match '^(?i)(install|uninstall|remove|delete|update|repair)$' }).Count -gt 0)
	{
		return $false
	}

	return (
		(Test-ManifestEntryHasNonEmptyPropertyValue -Entry $Entry -PropertyName 'Default') -and
		(Test-ManifestEntryHasNonEmptyPropertyValue -Entry $Entry -PropertyName 'WinDefault')
	)
}

function Get-GameModeEntryScopeCategory
{
	param(
		[object]$Entry,
		[string]$FallbackCategory
	)

	if ($Entry -and $Entry.PSObject.Properties['SourceRegion'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.SourceRegion))
	{
		return [string]$Entry.SourceRegion
	}

	if (-not [string]::IsNullOrWhiteSpace($FallbackCategory))
	{
		return [string]$FallbackCategory
	}

	return $null
}

function Test-GameModeEntryReviewedForAllowlist
{
	param(
		[object]$Entry,
		[string]$FallbackCategory
	)

	if (-not $Entry -or [string]::IsNullOrWhiteSpace([string]$Entry.Function))
	{
		return $false
	}

	$scopeCategory = Get-GameModeEntryScopeCategory -Entry $Entry -FallbackCategory $FallbackCategory
	if ([string]::IsNullOrWhiteSpace($scopeCategory) -or $scopeCategory -eq 'Gaming')
	{
		return $true
	}

	return ($gameModeReviewedCrossCategoryAllowlist -contains [string]$Entry.Function)
}

function Test-GameModeEntryHasEnabledDefaults
{
	param(
		[object]$Entry
	)

	if (-not $Entry)
	{
		return $false
	}

	if ($Entry.PSObject.Properties['GameModeDefault'] -and [bool]$Entry.GameModeDefault)
	{
		return $true
	}

	if ($Entry.PSObject.Properties['GameModeDefaultByProfile'] -and $null -ne $Entry.GameModeDefaultByProfile)
	{
		foreach ($property in $Entry.GameModeDefaultByProfile.PSObject.Properties)
		{
			if ([bool]$property.Value)
			{
				return $true
			}
		}
	}

	return $false
}

function Test-GameModeEntryEligibleForProfileDefaults
{
	param(
		[object]$Entry,
		[string]$FallbackCategory
	)

	if (-not (Test-GameModeEntryReviewedForAllowlist -Entry $Entry -FallbackCategory $FallbackCategory))
	{
		return $false
	}

	if ([string]$Entry.Type -ne 'Toggle')
	{
		return $false
	}

	if ([string]$Entry.Risk -ne 'Low')
	{
		return $false
	}

	if (-not ($Entry.PSObject.Properties['Safe'] -and [bool]$Entry.Safe))
	{
		return $false
	}

	$workflowSensitivityValue = if ($Entry.PSObject.Properties['WorkflowSensitivity']) { [string]$Entry.WorkflowSensitivity } else { 'Low' }
	if ([string]::IsNullOrWhiteSpace($workflowSensitivityValue))
	{
		$workflowSensitivityValue = 'Low'
	}

	return ($workflowSensitivityValue -eq 'Low')
}

foreach ($regionFile in (Get-ChildItem -LiteralPath $regionDir -Filter '*.psm1' -File | Sort-Object BaseName))
{
	$regionName = $regionFile.BaseName
	$rawContent = Get-Content -LiteralPath $regionFile.FullName -Raw -Encoding UTF8
	$functionMatches = [regex]::Matches($rawContent, '(?im)^\s*function\s+([A-Za-z0-9_.-]+)\b')
	$functionNames = [System.Collections.Generic.List[string]]::new()
	foreach ($m in $functionMatches)
	{
		$fn = $m.Groups[1].Value
		if (-not [string]::IsNullOrWhiteSpace($fn)) { [void]$functionNames.Add($fn) }
	}

	# Also scan extracted sub-module directories (e.g. Module/Regions/System/*.psm1)
	$subModuleDir = Join-Path $regionDir $regionName
	if (Test-Path -LiteralPath $subModuleDir -PathType Container)
	{
		foreach ($subFile in (Get-ChildItem -LiteralPath $subModuleDir -Filter '*.psm1' -File))
		{
			$subContent = Get-Content -LiteralPath $subFile.FullName -Raw -Encoding UTF8
			$subMatches = [regex]::Matches($subContent, '(?im)^\s*function\s+([A-Za-z0-9_.-]+)\b')
			foreach ($sm in $subMatches)
			{
				$sfn = $sm.Groups[1].Value
				if (-not [string]::IsNullOrWhiteSpace($sfn)) { [void]$functionNames.Add($sfn) }
			}
		}
	}

	$regionFunctions[$regionName] = @($functionNames | Sort-Object -Unique)
}

foreach ($dataFile in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' -File | Sort-Object Name))
{
	$dataFileCount++

	try
	{
		$payload = Get-Content -LiteralPath $dataFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'InvalidJson'
			File = $dataFile.Name
			Entry = $null
			Message = $_.Exception.Message
		})
		continue
	}

	if (-not $payload.PSObject.Properties['Entries'])
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'MissingEntries'
			File = $dataFile.Name
			Entry = $null
			Message = 'Top-level Entries array is missing.'
		})
		continue
	}

	$entryIndex = 0
	foreach ($entry in @($payload.Entries))
	{
		$entryIndex++
		if (-not $entry)
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'NullEntry'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = 'Encountered a null entry in the manifest.'
			})
			continue
		}

		$totalEntries++
		$name = [string]$entry.Name
		$functionName = [string]$entry.Function
		$typeName = [string]$entry.Type
		$sourceRegion = if ($entry.PSObject.Properties['SourceRegion']) { [string]$entry.SourceRegion } else { '' }

		foreach ($field in @(
			[PSCustomObject]@{ Name = 'Name'; Value = $name },
			[PSCustomObject]@{ Name = 'Function'; Value = $functionName },
			[PSCustomObject]@{ Name = 'Type'; Value = $typeName },
			[PSCustomObject]@{ Name = 'SourceRegion'; Value = $sourceRegion }
		))
		{
			if ([string]::IsNullOrWhiteSpace([string]$field.Value))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingField'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "Required field '$($field.Name)' is missing."
				})
			}
		}

		# Validate metadata fields exist (Risk, Tags, Impact, Safe, RequiresRestart, WhyThisMatters)
		foreach ($metaField in @('Risk', 'Tags', 'Impact', 'Safe', 'RequiresRestart', 'WhyThisMatters', 'Restorable', 'RecoveryLevel', 'CompatibilitySensitivity'))
		{
			if (-not $entry.PSObject.Properties[$metaField])
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingMetadata'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "Metadata field '$metaField' is missing on '$name'."
				})
			}
		}

		# Validate CompatibilitySensitivity value
		if ($entry.PSObject.Properties['CompatibilitySensitivity'])
		{
			$compatSensitivity = [string]$entry.CompatibilitySensitivity
			if ([string]::IsNullOrWhiteSpace($compatSensitivity))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingCompatibilitySensitivity'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is missing a CompatibilitySensitivity value."
				})
			}
			elseif ($validCompatibilitySensitivityValues -notcontains $compatSensitivity)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'InvalidCompatibilitySensitivity'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' uses invalid CompatibilitySensitivity '$compatSensitivity'. Valid values: $($validCompatibilitySensitivityValues -join ', ')."
				})
			}
		}

		if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($functionName))
		{
			$key = '{0}|{1}' -f $name.Trim(), $functionName.Trim()
			if (-not $entryKeys.ContainsKey($key))
			{
				$entryKeys[$key] = New-Object System.Collections.ArrayList
			}

			[void]$entryKeys[$key].Add(('{0}#Entry{1}' -f $dataFile.Name, $entryIndex))
		}

		if (-not [string]::IsNullOrWhiteSpace($functionName) -and -not $manifestEntriesByFunction.ContainsKey($functionName))
		{
			$manifestEntriesByFunction[$functionName] = [PSCustomObject]@{
				Name       = $name
				Function   = $functionName
				Risk       = if ($entry.PSObject.Properties['Risk']) { [string]$entry.Risk } else { $null }
				Safe       = if ($entry.PSObject.Properties['Safe']) { [bool]$entry.Safe } else { $false }
				PresetTier = if ($entry.PSObject.Properties['PresetTier']) { [string]$entry.PresetTier } else { $null }
				Type       = $typeName
				Default    = if ($entry.PSObject.Properties['Default']) { $entry.Default } else { $null }
				OnParam    = if ($entry.PSObject.Properties['OnParam']) { [string]$entry.OnParam } else { $null }
				OffParam   = if ($entry.PSObject.Properties['OffParam']) { [string]$entry.OffParam } else { $null }
				Options    = if ($entry.PSObject.Properties['Options'] -and $null -ne $entry.Options) { @($entry.Options) } else { $null }
			}
		}

		$hasToggleUndoParams = Test-ManifestEntryHasReversibleToggleParameters -Entry $entry
		$hasReversibleChoiceDefaults = Test-ManifestEntryHasReversibleChoiceDefaults -Entry $entry
		$requiresExplicitRecoveryMetadata = $hasToggleUndoParams -or $hasReversibleChoiceDefaults
		$restorablePropertyExists = [bool]$entry.PSObject.Properties['Restorable']
			$recoveryLevelPropertyExists = [bool]$entry.PSObject.Properties['RecoveryLevel']
			$recoveryLevel = if ($recoveryLevelPropertyExists) { [string]$entry.RecoveryLevel } else { '' }
			if ($typeName -eq 'Toggle' -and -not $hasToggleUndoParams)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'ToggleMissingParameters'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is a Toggle but is missing required OnParam/OffParam metadata."
				})
			}
			if ($entry.PSObject.Properties['Restorable'] -and $null -eq $entry.Restorable)
			{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'RestorableAuditPending'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = $(if ($hasToggleUndoParams) {
					"'$name' is a toggle with OnParam/OffParam but Restorable is still null. Replace with true or false after audit."
				}
				elseif ($hasReversibleChoiceDefaults) {
					"'$name' is a choice with Default/WinDefault but Restorable is still null. Replace with true or false after audit."
				}
				else {
					"'$name' still has Restorable = null. Replace with true or false after audit."
				})
			})
		}

		if ($recoveryLevelPropertyExists)
		{
			if ([string]::IsNullOrWhiteSpace($recoveryLevel))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingRecoveryLevel'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is missing a RecoveryLevel value."
				})
			}
			elseif ($validRecoveryLevels -notcontains $recoveryLevel)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'InvalidRecoveryLevel'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' uses invalid RecoveryLevel '$recoveryLevel'."
				})
			}
		}

		if ($typeName -eq 'Action')
		{
			if ($restorablePropertyExists -and $true -eq $entry.Restorable)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'ActionRecoveryClassification'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is an Action but is marked Restorable = true. Actions must not be classified as directly restorable."
				})
			}

			if ($recoveryLevelPropertyExists -and @('Direct', 'DefaultsOnly') -contains $recoveryLevel)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'ActionRecoveryClassification'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is an Action but uses RecoveryLevel '$recoveryLevel'. Actions must use a non-direct recovery classification."
				})
			}
		}

		if ($requiresExplicitRecoveryMetadata)
		{
			$recoveryShape = if ($hasToggleUndoParams) { 'toggle with OnParam/OffParam' } else { 'choice with Default/WinDefault' }

			if ($restorablePropertyExists -and $null -ne $entry.Restorable -and $true -ne $entry.Restorable)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'ReversibleRecoveryClassification'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is a reversible $recoveryShape but Restorable is not true."
				})
			}

			if ($recoveryLevelPropertyExists -and -not [string]::IsNullOrWhiteSpace($recoveryLevel) -and @('Direct', 'DefaultsOnly') -notcontains $recoveryLevel)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'ReversibleRecoveryClassification'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is a reversible $recoveryShape but uses RecoveryLevel '$recoveryLevel' instead of Direct or DefaultsOnly."
				})
			}
		}

		if ($entry.PSObject.Properties['ScenarioTags'] -and $null -ne $entry.ScenarioTags)
		{
			foreach ($scenarioTag in @($entry.ScenarioTags))
			{
				$scenarioTagValue = [string]$scenarioTag
				if ([string]::IsNullOrWhiteSpace($scenarioTagValue)) { continue }
				if ($validScenarioTags -notcontains $scenarioTagValue.ToLowerInvariant())
				{
					[void]$issues.Add([PSCustomObject]@{
						Type = 'UnknownScenarioTag'
						File = $dataFile.Name
						Entry = $entryIndex
						Message = "'$name' uses unknown ScenarioTag '$scenarioTagValue'."
					})
				}
			}
		}

		if ($entry.PSObject.Properties['GamingPreviewGroup'] -and $null -ne $entry.GamingPreviewGroup)
		{
			$gamingPreviewGroup = [string]$entry.GamingPreviewGroup
			if (-not [string]::IsNullOrWhiteSpace($gamingPreviewGroup) -and $validGamingPreviewGroups -notcontains $gamingPreviewGroup)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'InvalidGamingPreviewGroup'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' uses invalid GamingPreviewGroup '$gamingPreviewGroup'."
				})
			}
			elseif (-not [string]::IsNullOrWhiteSpace($gamingPreviewGroup) -and (-not $entry.PSObject.Properties['ScenarioTags'] -or @($entry.ScenarioTags).Count -eq 0))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'GamingPreviewGroupMissingScenarioTags'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' uses GamingPreviewGroup without ScenarioTags."
				})
			}
		}

		if ($entry.PSObject.Properties['GameModeDefaultByProfile'] -and $null -ne $entry.GameModeDefaultByProfile)
		{
			foreach ($profileKey in $entry.GameModeDefaultByProfile.PSObject.Properties.Name)
			{
				if ($validGameModeProfiles -notcontains [string]$profileKey)
				{
					[void]$issues.Add([PSCustomObject]@{
						Type = 'InvalidGameModeProfileKey'
						File = $dataFile.Name
						Entry = $entryIndex
						Message = "'$name' uses invalid GameModeDefaultByProfile key '$profileKey'."
					})
				}
			}
		}

		if ($entry.PSObject.Properties['DecisionPromptKey'] -and $null -ne $entry.DecisionPromptKey)
		{
			$decisionPromptKey = [string]$entry.DecisionPromptKey
			if (-not [string]::IsNullOrWhiteSpace($decisionPromptKey) -and $validDecisionPromptKeys -notcontains $decisionPromptKey)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'InvalidDecisionPromptKey'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' uses invalid DecisionPromptKey '$decisionPromptKey'."
				})
			}
		}

		$hasTroubleshootingScenarioTag = $false
		if ($entry.PSObject.Properties['ScenarioTags'] -and $null -ne $entry.ScenarioTags)
		{
			foreach ($scenarioTag in @($entry.ScenarioTags))
			{
				if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
				if ([string]$scenarioTag -match '^\s*troubleshooting\s*$')
				{
					$hasTroubleshootingScenarioTag = $true
					break
				}
			}
		}

		if ($entry.PSObject.Properties['TroubleshootingOnly'] -and [bool]$entry.TroubleshootingOnly -and [string]$entry.Risk -eq 'Low' -and -not $hasTroubleshootingScenarioTag)
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'TroubleshootingRiskMismatch'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = "'$name' is marked TroubleshootingOnly but does not include a troubleshooting ScenarioTag."
			})
		}

		if ($gameModeAllowlist -contains $functionName)
		{
			if (-not (Test-GameModeEntryReviewedForAllowlist -Entry $entry -FallbackCategory $payload.Tab))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'GameModeCrossCategoryReviewRequired'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' is a cross-category Game Mode allowlist entry and must be added to the reviewed cross-category allowlist explicitly."
				})
			}

			if ((Test-GameModeEntryHasEnabledDefaults -Entry $entry) -and -not (Test-GameModeEntryEligibleForProfileDefaults -Entry $entry -FallbackCategory $payload.Tab))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'GameModeDefaultEligibility'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "'$name' enables a Game Mode default but is not a reviewed low-risk, workflow-safe toggle."
				})
			}
		}

		if ($dataFile.Name -eq 'Gaming.json')
		{
			foreach ($requiredGamingField in @('ScenarioTags', 'GamingPreviewGroup', 'GameModeDefault', 'GameModeDefaultByProfile', 'TroubleshootingOnly', 'DecisionPromptKey'))
			{
				if (-not $entry.PSObject.Properties[$requiredGamingField])
				{
					[void]$issues.Add([PSCustomObject]@{
						Type = 'MissingGamingMetadata'
						File = $dataFile.Name
						Entry = $entryIndex
						Message = "'$name' is missing required gaming metadata field '$requiredGamingField'."
					})
				}
			}
		}

		if ([string]::IsNullOrWhiteSpace($sourceRegion))
		{
			continue
		}

		if (-not $regionFunctions.ContainsKey($sourceRegion))
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'MissingRegionModule'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = "SourceRegion '$sourceRegion' does not match any file in Module/Regions."
			})
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($functionName) -and ($regionFunctions[$sourceRegion] -notcontains $functionName))
		{
			$otherOwners = @(
				$regionFunctions.GetEnumerator() |
					Where-Object { $_.Key -ne $sourceRegion -and $_.Value -contains $functionName } |
					Select-Object -ExpandProperty Key
			)

			[void]$issues.Add([PSCustomObject]@{
				Type = if ($otherOwners.Count -gt 0) { 'OwnershipDrift' } else { 'MissingFunction' }
				File = $dataFile.Name
				Entry = $entryIndex
				Message = if ($otherOwners.Count -gt 0) {
					"Function '$functionName' is not defined in SourceRegion '$sourceRegion'. Found in: $($otherOwners -join ', ')."
				}
				else {
					"Function '$functionName' is not defined in SourceRegion '$sourceRegion' or any other region module."
				}
			})
		}
	}
}

foreach ($entryKey in $entryKeys.GetEnumerator() | Sort-Object Key)
{
	$locations = @($entryKey.Value | Sort-Object -Unique)
	if ($locations.Count -gt 1)
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'DuplicateEntry'
			File = $null
			Entry = $null
			Message = "Duplicate manifest key '$($entryKey.Key)' found in: $($locations -join ', ')."
		})
	}
}

foreach ($scenarioIssue in @(Get-ScenarioProfileValidationIssues -Manifest @($manifestEntriesByFunction.Values)))
{
	[void]$issues.Add([PSCustomObject]@{
		Type = 'ScenarioProfileValidation'
		File = 'Module/SharedHelpers/ScenarioMode.Helpers.ps1'
		Entry = $null
		Message = $scenarioIssue
	})
}

$presetDir = if ([string]::IsNullOrWhiteSpace($PresetDirectory))
{
	Join-Path $dataDir 'Presets'
}
else
{
	$PresetDirectory
}
	if (Test-Path -LiteralPath $presetDir)
	{
		$minimalPresetRule = @{
			AllowedTiers         = @('Minimal', 'Safe')
			DenyFunctions        = @()
			RequireSafe          = $false
			DenyRiskValues       = @('High')
			DenyWorkflowSensitivityValues = @('High')
			DenyRemovalOperations = $true
		}
			$basicPresetRule = @{
				AllowedTiers         = @('Minimal', 'Safe', 'Basic')
				DenyFunctions        = @('XboxGameBar', 'XboxGameTips', 'OpenWindowsTerminalAdminContext')
				RequireSafe          = $true
				AllowUnsafeTiers     = @('Minimal')
				DenyRiskValues       = @('High')
				DenyWorkflowSensitivityValues = @('High')
				DenyRemovalOperations = $true
		}
		$presetRules = @{
		'Minimal' = $minimalPresetRule
		'Basic' = $basicPresetRule
		'Safe' = $basicPresetRule
				'Balanced' = @{
					AllowedTiers         = @('Minimal', 'Safe', 'Basic', 'Balanced')
					DenyFunctions        = @()
					RequireSafe          = $true
					AllowUnsafeTiers     = @('Minimal')
					DenyRiskValues       = @('High')
					DenyWorkflowSensitivityValues = @('High')
					DenyRemovalOperations = $true
			}
		}

	foreach ($presetFile in (Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File | Sort-Object Name))
	{
		try
		{
			$presetPayload = Get-Content -LiteralPath $presetFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
		}
		catch
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'InvalidPresetJson'
				File = $presetFile.Name
				Entry = $null
				Message = $_.Exception.Message
			})
			continue
		}

		$presetName = [string]$presetPayload.Name
		if ([string]::IsNullOrWhiteSpace($presetName))
		{
			$presetName = [System.IO.Path]::GetFileNameWithoutExtension($presetFile.Name)
		}

		$presetRule = $presetRules[$presetName]
		$presetEntries = @()
		if ($presetPayload.PSObject.Properties['Entries'] -and $null -ne $presetPayload.Entries)
		{
			$presetEntries = @($presetPayload.Entries)
		}

		$entryIndex = 0
		foreach ($rawEntry in $presetEntries)
		{
			$entryIndex++
			if ($null -eq $rawEntry) { continue }

			$commandLine = [string]$rawEntry
			if ([string]::IsNullOrWhiteSpace($commandLine))
			{
				continue
			}

			$functionName = ([string]$commandLine -split '\s+', 2)[0].Trim()
			if ([string]::IsNullOrWhiteSpace($functionName))
			{
				continue
			}

			if (-not $manifestEntriesByFunction.ContainsKey($functionName))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'PresetMissingManifest'
					File = $presetFile.Name
					Entry = $entryIndex
					Message = "Preset '$presetName' references '$functionName', but no manifest entry defines that function."
				})
				continue
			}

			if (-not $presetRule)
			{
				continue
			}

					$manifestEntry = $manifestEntriesByFunction[$functionName]
					$presetTierValue = [string]$manifestEntry.PresetTier
					$riskValue = [string]$manifestEntry.Risk
					$workflowSensitivityValue = if ($manifestEntry.PSObject.Properties['WorkflowSensitivity']) { [string]$manifestEntry.WorkflowSensitivity } else { 'Low' }
					$requiresSafeEntry = (-not $presetRule.ContainsKey('RequireSafe') -or [bool]$presetRule.RequireSafe)
					$allowUnsafeTiers = if ($presetRule.ContainsKey('AllowUnsafeTiers') -and $null -ne $presetRule.AllowUnsafeTiers) { @($presetRule.AllowUnsafeTiers) } else { @() }
					$isSafeValue = if ($requiresSafeEntry) { [bool]$manifestEntry.Safe -or ($allowUnsafeTiers -contains $presetTierValue) } else { $true }
					$isAllowedTier = if ($presetRule.ContainsKey('AllowedTiers') -and @($presetRule.AllowedTiers).Count -gt 0) { $presetRule.AllowedTiers -contains $presetTierValue } else { $true }
				$isDeniedFunction = $presetRule.DenyFunctions -contains $functionName
				$isDeniedRisk = $presetRule.ContainsKey('DenyRiskValues') -and @($presetRule.DenyRiskValues).Count -gt 0 -and ($presetRule.DenyRiskValues -contains $riskValue)
				$isDeniedWorkflowSensitivity = $presetRule.ContainsKey('DenyWorkflowSensitivityValues') -and @($presetRule.DenyWorkflowSensitivityValues).Count -gt 0 -and ($presetRule.DenyWorkflowSensitivityValues -contains $workflowSensitivityValue)
				$isRemovalOperation = $false
				if ($presetRule.ContainsKey('DenyRemovalOperations') -and [bool]$presetRule.DenyRemovalOperations)
				{
					$isRemovalOperation = Test-PresetCommandIsRemovalOperation -CommandLine $commandLine -ManifestEntry $manifestEntry
				}

				if (-not $isAllowedTier -or -not $isSafeValue -or $isDeniedFunction -or $isDeniedRisk -or $isDeniedWorkflowSensitivity -or $isRemovalOperation)
				{
					$reasonParts = New-Object System.Collections.Generic.List[string]
					if (-not $isAllowedTier)
					{
						[void]$reasonParts.Add("tier '$presetTierValue' is not allowed")
				}
				if (-not $isSafeValue)
				{
					[void]$reasonParts.Add('manifest Safe flag is false')
				}
					if ($isDeniedFunction)
					{
						[void]$reasonParts.Add('function is explicitly excluded from this preset')
					}
					if ($isDeniedRisk)
					{
						[void]$reasonParts.Add("risk '$riskValue' is not allowed")
					}
					if ($isDeniedWorkflowSensitivity)
					{
						[void]$reasonParts.Add("workflow sensitivity '$workflowSensitivityValue' is not allowed")
					}
					if ($isRemovalOperation)
					{
						[void]$reasonParts.Add('preset includes uninstall/remove/delete behavior')
				}

				[void]$issues.Add([PSCustomObject]@{
					Type = 'PresetTierViolation'
					File = $presetFile.Name
					Entry = $entryIndex
					Message = "Preset '$presetName' includes '$functionName' ($($reasonParts -join '; '))."
				})
			}
		}
	}
}

# -- M-8: Validate that the Advanced preset exists and contains all entries from lower presets --
$advancedPresetPath = Join-Path $presetDir 'Advanced.json'
if (-not (Test-Path -LiteralPath $advancedPresetPath))
{
	if (-not $AllowPartialPresetDirectory)
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'MissingAdvancedPreset'
			File = 'Advanced.json'
			Entry = $null
			Message = "Advanced preset file does not exist at '$advancedPresetPath'."
		})
	}
}
else
{
	try
	{
		$advancedPayload = Get-Content -LiteralPath $advancedPresetPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
		$advancedEntries = @()
		if ($advancedPayload.PSObject.Properties['Entries'] -and $null -ne $advancedPayload.Entries)
		{
			$advancedEntries = @($advancedPayload.Entries)
		}

		$advancedFunctions = @($advancedEntries | ForEach-Object {
			$line = [string]$_
			if (-not [string]::IsNullOrWhiteSpace($line)) { ($line -split '\s+', 2)[0].Trim() }
		})

		$lowerPresetNames = @('Minimal', 'Basic', 'Balanced')
		foreach ($lowerName in $lowerPresetNames)
		{
			$lowerPath = Join-Path $presetDir "$lowerName.json"
			if (-not (Test-Path -LiteralPath $lowerPath)) { continue }

			try
			{
				$lowerPayload = Get-Content -LiteralPath $lowerPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
				$lowerEntries = @()
				if ($lowerPayload.PSObject.Properties['Entries'] -and $null -ne $lowerPayload.Entries)
				{
					$lowerEntries = @($lowerPayload.Entries)
				}

				foreach ($lowerEntry in $lowerEntries)
				{
					$lowerLine = [string]$lowerEntry
					if ([string]::IsNullOrWhiteSpace($lowerLine)) { continue }
					$lowerFunction = ($lowerLine -split '\s+', 2)[0].Trim()
					if ($advancedFunctions -notcontains $lowerFunction)
					{
						[void]$issues.Add([PSCustomObject]@{
							Type = 'AdvancedPresetMissingEntry'
							File = 'Advanced.json'
							Entry = $null
							Message = "Advanced preset is missing '$lowerFunction' which is present in the $lowerName preset."
						})
					}
				}
			}
			catch
			{
				# Lower preset JSON error already reported by earlier validation; skip here.
			}
		}
	}
	catch
	{
		# Advanced preset JSON parse error already reported by earlier validation; skip here.
	}
}

# -- M-9: Validate GameMode data files are valid and loadable --
$gameModeDir = Join-Path $dataDir 'GameMode'
if (Test-Path -LiteralPath $gameModeDir -PathType Container)
{
	foreach ($gameModeFile in (Get-ChildItem -LiteralPath $gameModeDir -Filter '*.json' -File | Sort-Object Name))
	{
		try
		{
			$gameModePayload = Get-Content -LiteralPath $gameModeFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
		}
		catch
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'InvalidGameModeJson'
				File = $gameModeFile.Name
				Entry = $null
				Message = "GameMode file failed to parse: $($_.Exception.Message)"
			})
			continue
		}

		if (-not $gameModePayload.PSObject.Properties['Name'] -or [string]::IsNullOrWhiteSpace([string]$gameModePayload.Name))
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'GameModeFileMissingName'
				File = $gameModeFile.Name
				Entry = $null
				Message = "GameMode file is missing a top-level 'Name' property."
			})
		}

		if (-not $gameModePayload.PSObject.Properties['Entries'])
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'GameModeFileMissingEntries'
				File = $gameModeFile.Name
				Entry = $null
				Message = "GameMode file is missing a top-level 'Entries' array."
			})
			continue
		}

		$gmEntryIndex = 0
		foreach ($gmEntry in @($gameModePayload.Entries))
		{
			$gmEntryIndex++
			if ($null -eq $gmEntry)
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'GameModeNullEntry'
					File = $gameModeFile.Name
					Entry = $gmEntryIndex
					Message = 'Encountered a null entry in GameMode file.'
				})
				continue
			}

			$gmFunction = if ($gmEntry.PSObject.Properties['Function']) { [string]$gmEntry.Function } else { '' }
			if ([string]::IsNullOrWhiteSpace($gmFunction))
			{
				# Profile definition entries (e.g., GameModeProfiles) use Name instead of Function; skip Function check for those.
				if (-not $gmEntry.PSObject.Properties['Name'])
				{
					[void]$issues.Add([PSCustomObject]@{
						Type = 'GameModeMissingFunction'
						File = $gameModeFile.Name
						Entry = $gmEntryIndex
						Message = "GameMode entry $gmEntryIndex is missing a 'Function' field."
					})
				}
				continue
			}

			if (-not $manifestEntriesByFunction.ContainsKey($gmFunction) -and $gameModeAllowlist -notcontains $gmFunction)
			{
				# Only warn if the function is not in the main manifest and not in the GameMode allowlist;
				# allowlist entries from cross-category sources are expected here.
			}
		}
	}
}

# -- M-11: Validate preset parameters against manifest OnParam/OffParam/Options --
if (Test-Path -LiteralPath $presetDir)
{
	foreach ($presetFile in (Get-ChildItem -LiteralPath $presetDir -Filter '*.json' -File | Sort-Object Name))
	{
		try
		{
			$presetPayload = Get-Content -LiteralPath $presetFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
		}
		catch
		{
			# JSON parse errors already reported in earlier preset validation.
			continue
		}

		$presetName = [string]$presetPayload.Name
		if ([string]::IsNullOrWhiteSpace($presetName))
		{
			$presetName = [System.IO.Path]::GetFileNameWithoutExtension($presetFile.Name)
		}

		$presetEntries = @()
		if ($presetPayload.PSObject.Properties['Entries'] -and $null -ne $presetPayload.Entries)
		{
			$presetEntries = @($presetPayload.Entries)
		}

		$paramEntryIndex = 0
		foreach ($rawEntry in $presetEntries)
		{
			$paramEntryIndex++
			if ($null -eq $rawEntry) { continue }

			$commandLine = [string]$rawEntry
			if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

			$parts = [string]$commandLine -split '\s+', 2
			$functionName = $parts[0].Trim()
			if ([string]::IsNullOrWhiteSpace($functionName)) { continue }
			if (-not $manifestEntriesByFunction.ContainsKey($functionName)) { continue }

			$manifestEntry = $manifestEntriesByFunction[$functionName]
			$entryType = [string]$manifestEntry.Type

			# Extract the parameter value from the preset command (everything after the function name).
			$paramValue = $null
			if ($parts.Count -gt 1)
			{
					$paramValue = ConvertTo-NormalizedManifestParameterName -Value $parts[1].Trim()
				}

			# Action entries take no parameters; skip validation if no param is supplied.
			if ($entryType -eq 'Action')
			{
				continue
			}

			if ([string]::IsNullOrWhiteSpace($paramValue))
			{
				# No parameter supplied for a Toggle/Choice entry - the function may accept a default, skip.
				continue
			}

			if ($entryType -eq 'Toggle')
			{
					$validToggleParams = @()
					if (-not [string]::IsNullOrWhiteSpace($manifestEntry.OnParam))
					{
						$validToggleParams += (ConvertTo-NormalizedManifestParameterName -Value $manifestEntry.OnParam)
					}
					if (-not [string]::IsNullOrWhiteSpace($manifestEntry.OffParam))
					{
						$validToggleParams += (ConvertTo-NormalizedManifestParameterName -Value $manifestEntry.OffParam)
					}

				if ($validToggleParams.Count -gt 0 -and $validToggleParams -notcontains $paramValue)
				{
					[void]$issues.Add([PSCustomObject]@{
						Type = 'PresetParameterMismatch'
						File = $presetFile.Name
						Entry = $paramEntryIndex
						Message = "Preset '$presetName' passes parameter '$paramValue' to toggle '$functionName', but manifest declares OnParam='$($manifestEntry.OnParam)' / OffParam='$($manifestEntry.OffParam)'."
					})
				}
			}
			elseif ($entryType -eq 'Choice')
			{
				if ($null -ne $manifestEntry.Options -and @($manifestEntry.Options).Count -gt 0)
				{
					# Handle compound parameters like "-Shortcuts Edge, Store" by extracting the first token.
					$firstToken = ($paramValue -split '\s+', 2)[0].Trim()
					$optionValues = @($manifestEntry.Options | ForEach-Object { [string]$_ })
					if ($optionValues -notcontains $firstToken)
					{
						[void]$issues.Add([PSCustomObject]@{
							Type = 'PresetParameterMismatch'
							File = $presetFile.Name
							Entry = $paramEntryIndex
							Message = "Preset '$presetName' passes parameter '$paramValue' to choice '$functionName', but manifest Options are: $($optionValues -join ', ')."
						})
					}
				}
			}
		}
	}
}

if ($issues.Count -gt 0)
{
	# Write-Host: intentional — test/tooling console output
	Write-Host ''
	Write-Host 'Manifest validation failed:' -ForegroundColor Red
	foreach ($issue in @($issues))
	{
		$location = if ($issue.File) {
			if ($null -ne $issue.Entry) { "$($issue.File) entry $($issue.Entry)" } else { $issue.File }
		}
		else {
			'global'
		}
		Write-Host ("- [{0}] {1}: {2}" -f $issue.Type, $location, $issue.Message) -ForegroundColor Yellow
	}
	Write-Host ''
	throw 'Manifest validation failed.'
}

Write-Host ("Validated {0} data file(s), {1} entry(s), and {2} region module(s)." -f $dataFileCount, $totalEntries, $regionFunctions.Count) -ForegroundColor Green
Write-Host 'No duplicate manifest keys, orphaned SourceRegion values, or region ownership drift found.' -ForegroundColor Green
