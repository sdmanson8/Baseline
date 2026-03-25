# Shared helper slice for Baseline.

function Convert-JsonManifestValue
{
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
		$items = @()
		foreach ($item in $Value)
		{
			$items += ,(Convert-JsonManifestValue $item)
		}
		return $items
	}

	return $Value
}

function ConvertTo-TweakRiskLevel
{
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
			'^\s*balanced\s*$'   { return 'Balanced' }
			default              { return 'Safe' }
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

	return 'Safe'
}

function Convert-ToWhyThisMattersText
{
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
	param (
		[hashtable]$DetectScriptblocks = @{},
		[hashtable]$VisibleIfScriptblocks = @{}
	)

	$dataDir = Join-Path $Script:SharedHelpersModuleRoot 'Data'
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
				WhyThisMatters  = $whyThisMattersValue
			}

			foreach ($propName in @('WinDefaultDesc', 'Detail', 'CautionReason', 'LinkedWith', 'Scannable', 'Restorable', 'OnParam', 'OffParam', 'SubCategory'))
			{
				if ($entry.PSObject.Properties[$propName] -and $null -ne $entry.$propName)
				{
					$tweakEntry[$propName] = Convert-JsonManifestValue $entry.$propName
				}
			}

			foreach ($arrayProp in @('Options', 'DisplayOptions'))
			{
				if ($entry.PSObject.Properties[$arrayProp] -and $null -ne $entry.$arrayProp)
				{
					$tweakEntry[$arrayProp] = @(Convert-JsonManifestValue $entry.$arrayProp)
				}
			}

			if ($entry.PSObject.Properties['ExtraArgs'] -and $null -ne $entry.ExtraArgs)
			{
				$tweakEntry['ExtraArgs'] = Convert-JsonManifestValue $entry.ExtraArgs
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

function Test-TweakManifestIntegrity
{
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
	$validTiers = @('Minimal', 'Safe', 'Balanced', 'Advanced')
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
