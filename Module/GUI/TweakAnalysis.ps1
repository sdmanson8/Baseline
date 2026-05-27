# Pure logic functions for tweak analysis: removal detection, scenario signals, selection state

	<#
	    .SYNOPSIS
	#>

	function Get-TweakAnalysisFieldValue
	{
		param(
			[object]$Tweak,
			[string]$FieldName
		)

		if ($null -eq $Tweak) { return $null }
		if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains($FieldName)) { return $Tweak[$FieldName] }
			return $null
		}

		$property = $Tweak.PSObject.Properties[$FieldName]
		if ($property) { return $property.Value }
		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakAnalysisRuntimeCommand
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Name
		)

		$cacheVariable = Get-Variable -Name 'TweakAnalysisRuntimeCommandCache' -Scope Script -ErrorAction SilentlyContinue
		if (-not $cacheVariable -or -not ($cacheVariable.Value -is [hashtable]))
		{
			$Script:TweakAnalysisRuntimeCommandCache = @{}
		}

		if (-not $Script:TweakAnalysisRuntimeCommandCache.ContainsKey($Name))
		{
			$command = @(
				Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
			) | Select-Object -First 1

			$Script:TweakAnalysisRuntimeCommandCache[$Name] = $command
		}

		return $Script:TweakAnalysisRuntimeCommandCache[$Name]
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakAnalysisTweakAvailable
	{
		param ([object]$Tweak)

		$availabilityTest = Get-TweakAnalysisRuntimeCommand -Name 'Test-GuiTweakAvailableOnCurrentSystem'
		if (-not $availabilityTest)
		{
			return $true
		}

		return [bool](& $availabilityTest -Tweak $Tweak)
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakRemovalOperation
	{
		param ([object]$Tweak)

		if (-not $Tweak) { return $false }

		$tagValues = @((Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Tags') | ForEach-Object { [string]$_ })
		$searchParts = @(
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Name'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Description'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Detail'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'WhyThisMatters'),
			($tagValues -join ' ')
		) -join ' '

		if ([string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Type') -eq 'Choice')
		{
			$optionValues = @((Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Options') | ForEach-Object { [string]$_ })
			if ($optionValues | Where-Object { $_ -match '^(?i)(uninstall|remove|delete)$' })
			{
				return $true
			}
		}

		return ($searchParts -match '(?i)\b(uninstall|remove|delete)\b')
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakPackageOperation
	{
		param ([object]$Tweak)

		if (-not $Tweak) { return $false }

		$tagValues = @((Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Tags') | ForEach-Object { [string]$_ })
		$optionValues = @((Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Options') | ForEach-Object { [string]$_ })
		$haystack = @(
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Name'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Function'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Description'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Detail'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'WhyThisMatters'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'CautionReason'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SubCategory'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SourceRegion'),
			($tagValues -join ' ')
		) -join ' '

		if ([string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SubCategory') -eq 'App Management') { return $true }
		if ([string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SourceRegion') -eq 'OneDrive') { return $true }
		if ($tagValues -contains 'package-manager') { return $true }
		if (@($optionValues | Where-Object { $_ -match '^(?i)(install|uninstall|update|restore)$' }).Count -gt 0)
		{
			return $true
		}

		return ($haystack -match '(?i)\b(package manager|winget|microsoft store|store app|appx|msix|powershell 7|onedrive|copilot)\b')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakScenarioSignals
	{
		param (
			[object]$Tweak,
			[object]$IsRemoval = $null
		)

		if (-not $Tweak) { return @() }

		$signals = New-Object System.Collections.Generic.List[string]
		$addSignal = {
			param ([string]$Label)

			if ([string]::IsNullOrWhiteSpace($Label)) { return }
			if (-not ($signals -contains $Label))
			{
				[void]$signals.Add($Label)
			}
		}.GetNewClosure()

		$tagValues = @((Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Tags') | ForEach-Object { [string]$_ })
		$haystack = @(
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Name'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Description'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Detail'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'WhyThisMatters'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'CautionReason'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Category'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SubCategory'),
			[string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'SourceRegion'),
			($tagValues -join ' ')
		) -join ' '
		$tagText = $tagValues -join ' '

		if ($haystack -match '(?i)\b(gaming|game\s*bar|xbox|fullscreen|anti-?cheat|raw\s+mouse\s+input)\b' -or
			$tagText -match '(?i)\b(gaming|xbox)\b')
		{
			& $addSignal 'Gaming'
		}

		if ($haystack -match '(?i)\b(privacy|telemetry|tracking|advertis|bing search|web search|activity history|location|camera|microphone|tips|suggestions|personalized)\b' -or
			$tagText -match '(?i)\b(privacy|telemetry|tracking|advertising|bing|websearch|activity|location|camera|microphone)\b')
		{
			& $addSignal 'Privacy'
		}

		$isRemovalOperation = if ($null -ne $IsRemoval) { [bool]$IsRemoval } else { Test-TweakRemovalOperation -Tweak $Tweak }
		if ($isRemovalOperation -or
			$haystack -match '(?i)\b(cleanup|debloat|uninstall|remove|delete|clear recent|recent files|recent shortcuts)\b' -or
			$tagText -match '(?i)\b(cleanup|debloat|uninstall|remove|delete)\b')
		{
			& $addSignal 'Cleanup'
		}

		if ($haystack -match '(?i)\b(compatibility|onedrive|office|adobe|network sharing|sharing wizard|network discovery|printer|remote access|store app|uwp|sync)\b' -or
			$tagText -match '(?i)\b(compatibility|onedrive|office|adobe|networking|sharing|discovery|printer|store|uwp|remote)\b')
		{
			& $addSignal 'Compatibility'
		}

		if ($haystack -match '(?i)\b(performance|latency|speed|power plan|gpu scheduling|multiplane overlay|visual effects|mouse acceleration|raw input|faster)\b' -or
			$tagText -match '(?i)\b(performance|gpu|cpu|latency|power|speed|visualfx)\b')
		{
			& $addSignal 'Performance'
		}

		if ($haystack -match '(?i)\b(security|hardening|defender|firewall|credential|cipher|protocol|winrm|smartscreen|lsa|smb1|netbios|llmnr|bitlocker)\b' -or
			$tagText -match '(?i)\b(security|hardening|defender|firewall|smb|protocol)\b')
		{
			& $addSignal 'Hardening'
		}

		if ($haystack -match '(?i)\b(repair|recover|recovery|troubleshoot|troubleshooting|diagnostic|fix|rollback)\b' -or
			$tagText -match '(?i)\b(repair|recovery|troubleshooting|diagnostic|fix)\b')
		{
			& $addSignal 'Troubleshooting'
		}

		return @($signals)
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakIsSelected
	{
		param (
			[object]$Tweak,
			[object]$StateSource
		)

		if (-not $Tweak) { return $false }
		if (-not (Test-TweakAnalysisTweakAvailable -Tweak $Tweak)) { return $false }
		$source = if ($StateSource) { $StateSource } else { $Tweak }
		if (-not $source) { return $false }

		switch ([string]$Tweak.Type)
		{
			'Choice' { return ((Test-GuiObjectField -Object $source -FieldName 'SelectedIndex') -and [int]$source.SelectedIndex -ge 0) }
			'NumericRange'
			{
				$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
				if ($explicitSelection -and [string]$explicitSelection.Type -eq 'NumericRange')
				{
					if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'ACValue') -or (Test-GuiObjectField -Object $explicitSelection -FieldName 'DCValue') -or (Test-GuiObjectField -Object $explicitSelection -FieldName 'NumericValue') -or (Test-GuiObjectField -Object $explicitSelection -FieldName 'Value'))
					{
						return $true
					}
				}

				if ((Test-GuiObjectField -Object $source -FieldName 'IsChecked'))
				{
					return [bool]$source.IsChecked
				}

				if ((Test-GuiObjectField -Object $source -FieldName 'ACValue') -or (Test-GuiObjectField -Object $source -FieldName 'DCValue') -or (Test-GuiObjectField -Object $source -FieldName 'NumericValue') -or (Test-GuiObjectField -Object $source -FieldName 'Value'))
				{
					return $true
				}

				return $false
			}
			'Date'
			{
				$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
				if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Date')
				{
					if (Test-GuiObjectField -Object $explicitSelection -FieldName 'Run')
					{
						return [bool]$explicitSelection.Run
					}
					if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'SelectedDate') -and $explicitSelection.SelectedDate)
					{
						return $true
					}
					if ((Test-GuiObjectField -Object $explicitSelection -FieldName 'Value') -and -not [string]::IsNullOrWhiteSpace([string]$explicitSelection.Value))
					{
						return $true
					}
				}
				if ((Test-GuiObjectField -Object $source -FieldName 'SelectedDate') -and $source.SelectedDate)
				{
					return $true
				}
				return ((Test-GuiObjectField -Object $source -FieldName 'IsChecked') -and [bool]$source.IsChecked)
			}
			'Toggle'
			{
				$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
				if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Toggle')
				{
					return $true
				}
				return ((Test-GuiObjectField -Object $source -FieldName 'IsChecked') -and [bool]$source.IsChecked)
			}
			'Action' { return ((Test-GuiObjectField -Object $source -FieldName 'IsChecked') -and [bool]$source.IsChecked) }
			default
			{
				return (
					((Test-GuiObjectField -Object $source -FieldName 'IsChecked') -and [bool]$source.IsChecked) -or
					((Test-GuiObjectField -Object $source -FieldName 'SelectedIndex') -and [int]$source.SelectedIndex -ge 0)
				)
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiToggleGoalState
	{
		param (
			[object]$Tweak
		)

		if ($Tweak -and (Test-GuiObjectField -Object $Tweak -FieldName 'Default'))
		{
			return [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default')
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiToggleDetectedState
	{
		param (
			[object]$Tweak
		)

		if (-not [bool]$Script:ScanEnabled -or -not $Tweak -or -not (Test-GuiObjectField -Object $Tweak -FieldName 'Detect') -or -not $Tweak.Detect)
		{
			return [pscustomobject]@{
				Known = $false
				Value = $null
			}
		}

		$goalState = Get-GuiToggleGoalState -Tweak $Tweak
		$functionName = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Function') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Function)) { [string]$Tweak.Function } else { $null }

		$appliedTweaksVariable = Get-Variable -Scope Script -Name 'AppliedTweaks' -ErrorAction SilentlyContinue
		$appliedTweaks = if ($appliedTweaksVariable) { $appliedTweaksVariable.Value } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($functionName) -and $appliedTweaks -and $appliedTweaks.Contains($functionName))
		{
			if (Get-Command -Name 'Set-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { Set-CachedDetection -Function $functionName -Value ([bool]$goalState) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakAnalysis.GetGuiToggleDetectedState.SetAppliedCache' }
			}
			return [pscustomobject]@{
				Known = $true
				Value = [bool]$goalState
			}
		}

		if (-not [string]::IsNullOrWhiteSpace($functionName) -and (Get-Command -Name 'Get-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue))
		{
			try
			{
				$cachedValue = Get-CachedDetection -Function $functionName
				if ($null -ne $cachedValue)
				{
					return [pscustomobject]@{
						Known = $true
						Value = [bool]$cachedValue
					}
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakAnalysis.GetGuiToggleDetectedState.GetCachedDetection' }
		}

		$detectedValue = [bool](Invoke-GuiDetectScriptblock -Detect $Tweak.Detect -DefaultValue $goalState)
		if (-not [string]::IsNullOrWhiteSpace($functionName) -and (Get-Command -Name 'Set-CachedDetection' -CommandType Function -ErrorAction SilentlyContinue))
		{
			try { Set-CachedDetection -Function $functionName -Value $detectedValue } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakAnalysis.GetGuiToggleDetectedState.SetCachedDetection' }
		}

		return [pscustomobject]@{
			Known = $true
			Value = $detectedValue
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiToggleDisplayState
	{
		param (
			[object]$Tweak,
			[object]$StateSource = $null
		)

		$goalState = Get-GuiToggleGoalState -Tweak $Tweak
		$detected = Get-GuiToggleDetectedState -Tweak $Tweak
		$isSelected = Test-TweakIsSelected -Tweak $Tweak -StateSource $StateSource
		$matchesDesired = ([bool]$detected.Known -and [bool]$detected.Value -eq [bool]$goalState)

		if ($matchesDesired)
		{
			return [pscustomobject]@{
				StateLabel = Get-UxLocalizedString -Key 'GuiTweakStateAlreadySet' -Fallback 'Already Set'
				StateTone = 'Muted'
				StateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailDetectedMatchesGoal' -Fallback 'Detected state matches the configured goal.'
				MatchesDesired = $true
				DetectedState = [bool]$detected.Value
				GoalState = [bool]$goalState
				IsSelected = [bool]$isSelected
			}
		}

		if ($isSelected)
		{
			return [pscustomobject]@{
				StateLabel = Get-UxLocalizedString -Key 'GuiTweakStateWillChange' -Fallback 'Will Change'
				StateTone = 'Primary'
				StateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailWillChange' -Fallback 'Selected and will change the system state when run.'
				MatchesDesired = $false
				DetectedState = if ([bool]$detected.Known) { [bool]$detected.Value } else { $null }
				GoalState = [bool]$goalState
				IsSelected = $true
			}
		}

		return [pscustomobject]@{
			StateLabel = Get-UxLocalizedString -Key 'GuiTweakStateNotApplied' -Fallback 'Not Applied'
			StateTone = 'Muted'
			StateDetail = Get-UxLocalizedString -Key 'GuiTweakStateDetailNotApplied' -Fallback 'Not selected for this run.'
			MatchesDesired = $false
			DetectedState = if ([bool]$detected.Known) { [bool]$detected.Value } else { $null }
			GoalState = [bool]$goalState
			IsSelected = $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Test-TweakIsRestorable
	{
		param ([object]$Tweak)

		if (-not $Tweak) { return $false }
		return -not (
			(Test-GuiObjectField -Object $Tweak -FieldName 'Restorable') -and
			$null -ne $Tweak.Restorable -and
			-not [bool]$Tweak.Restorable
		)
	}

	function Test-TweakIsGamingRelated
	{
		param ([object]$Tweak)

		if (-not $Tweak) { return $false }
		return (@(Get-TweakScenarioSignals -Tweak $Tweak) -contains 'Gaming')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakFocusGroup
	{
		param (
			[object]$Tweak,
			[string[]]$ScenarioSignals
		)

		if (-not $Tweak) { return 'General' }

		$signals = @($ScenarioSignals)
		if ($signals.Count -eq 0)
		{
			$signals = @(Get-TweakScenarioSignals -Tweak $Tweak)
		}

		foreach ($candidate in @('Troubleshooting', 'Gaming', 'Privacy', 'Cleanup', 'Compatibility', 'Performance', 'Hardening'))
		{
			if ($signals -contains $candidate)
			{
				return $candidate
			}
		}

		if (Test-TweakRemovalOperation -Tweak $Tweak)
		{
			return 'Cleanup'
		}

		return 'General'
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakInclusionReason
	{
		param (
			[object]$Tweak,
			[string]$FocusGroup,
			[string[]]$ScenarioSignals
		)

		if (-not $Tweak) { return $null }

		$presetTier = [string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'PresetTier')
		$tier = if ([string]::IsNullOrWhiteSpace($presetTier)) { 'Basic' } else { $presetTier }
		$tierText = switch ($tier)
		{
			'Minimal' { 'Included because it is a very small, low-risk change.'; break }
			'Basic' { 'Included because it is a low-risk change.'; break }
			'Safe' { 'Included because it is a low-risk change.'; break }
			'Balanced' { 'Included because it offers a moderate change with limited tradeoffs.'; break }
			'Advanced' { 'Included because it is an expert-level change intended for the Advanced expert preset.'; break }
			default { 'Included because it matches the preset policy.' }
		}

		$group = if ([string]::IsNullOrWhiteSpace([string]$FocusGroup)) { Get-TweakFocusGroup -Tweak $Tweak -ScenarioSignals $ScenarioSignals } else { [string]$FocusGroup }
		$groupText = switch ($group)
		{
			'Gaming' { 'It is gaming-related and helps keep latency or overlay behavior under control.'; break }
			'Privacy' { 'It supports privacy and telemetry cleanup.'; break }
			'Cleanup' { 'It removes clutter or unwanted components.'; break }
			'Compatibility' { 'It helps keep common workflows, apps, or devices working as expected.'; break }
			'Performance' { 'It targets responsiveness or latency improvements.'; break }
			'Hardening' { 'It tightens security defaults.'; break }
			'Troubleshooting' { 'It is a targeted fix or troubleshooting aid.'; break }
			default { 'It fits the current baseline policy.' }
		}

		return ('{0} {1}' -f $tierText, $groupText).Trim()
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TweakBlastRadiusText
	{
		param (
			[object]$Tweak,
			[string]$TypeLabel,
			[string[]]$ScenarioTags,
			[bool]$MatchesDesired = $false,
			[object]$IsRemoval = $null,
			[object]$IsPackageOperation = $null
		)

		if ($MatchesDesired)
		{
			return (Get-UxLocalizedString -Key 'GuiTweakAlreadySetMessage' -Fallback 'Already set. No change is expected from this selection.')
		}

		$isPackageOperation = if ($null -ne $IsPackageOperation) { [bool]$IsPackageOperation } else { Test-TweakPackageOperation -Tweak $Tweak }
		$isRemovalOperation = if ($null -ne $IsRemoval) { [bool]$IsRemoval } else { Test-TweakRemovalOperation -Tweak $Tweak }
		$risk = [string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Risk')
		$impact = [string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'Impact')
		$cautionReason = [string](Get-TweakAnalysisFieldValue -Tweak $Tweak -FieldName 'CautionReason')
		$riskLevel = if ([string]::IsNullOrWhiteSpace($risk)) { 'Low' } else { $risk }
		$impactLevel = if (-not [string]::IsNullOrWhiteSpace($impact)) { $impact } else { $riskLevel }

		$focusNotes = New-Object System.Collections.Generic.List[string]
		foreach ($tag in @($ScenarioTags))
		{
			switch ([string]$tag)
			{
				'Gaming' { if ($focusNotes -notcontains 'gaming / overlays / input latency') { [void]$focusNotes.Add('gaming / overlays / input latency') } }
				'Networking' { if ($focusNotes -notcontains 'network sharing and SMB workflows') { [void]$focusNotes.Add('network sharing and SMB workflows') } }
				'SMB' { if ($focusNotes -notcontains 'network sharing and SMB workflows') { [void]$focusNotes.Add('network sharing and SMB workflows') } }
				'OneDrive' { if ($focusNotes -notcontains 'OneDrive sync workflows') { [void]$focusNotes.Add('OneDrive sync workflows') } }
				'Adobe' { if ($focusNotes -notcontains 'Adobe licensing and cloud workflows') { [void]$focusNotes.Add('Adobe licensing and cloud workflows') } }
				'Updates' { if ($focusNotes -notcontains 'update and reboot behavior') { [void]$focusNotes.Add('update and reboot behavior') } }
				'Hardening' { if ($focusNotes -notcontains 'security and hardening defaults') { [void]$focusNotes.Add('security and hardening defaults') } }
				'Privacy' { if ($focusNotes -notcontains 'telemetry and tracking behavior') { [void]$focusNotes.Add('telemetry and tracking behavior') } }
				'Security' { if ($focusNotes -notcontains 'security and access-control behavior') { [void]$focusNotes.Add('security and access-control behavior') } }
			}
		}

		$severityText = switch ($riskLevel)
		{
			'High' { 'High blast radius.'; break }
			'Medium' { 'Moderate blast radius.'; break }
			default { 'Low blast radius.' }
		}

		$details = New-Object System.Collections.Generic.List[string]
		[void]$details.Add($severityText)

		if ($isPackageOperation)
		{
			if ($isRemovalOperation)
			{
				[void]$details.Add('This package/app change can remove software components and may need Store, winget, or manual reinstall follow-up.')
			}
			else
			{
				[void]$details.Add('This package/app change can download, register, or update Windows software and may need network, admin, or Store follow-up.')
			}
		}
		elseif ($TypeLabel -eq 'Uninstall / Remove')
		{
			[void]$details.Add('This is a removal-style change and may be harder to reverse.')
		}

		if ($focusNotes.Count -gt 0)
		{
			[void]$details.Add(('May affect {0}.' -f (($focusNotes | Select-Object -Unique) -join ', ')))
		}
		elseif ($impactLevel -eq 'High')
		{
			[void]$details.Add('Review the linked description before running.')
		}
		elseif (-not [string]::IsNullOrWhiteSpace($cautionReason))
		{
			[void]$details.Add($cautionReason.Trim().TrimEnd('.') + '.')
		}
		else
		{
			[void]$details.Add('Review the linked description before running.')
		}

		return ('Blast radius: {0}' -f ($details -join ' '))
	}
