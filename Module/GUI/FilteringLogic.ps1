# Tweak filtering, visibility, and category filter management

	function Test-TweakVisibleInSafeMode
	{
		param (
			[object]$Tweak
		)

		if (-not $Tweak) { return $false }

		$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
		if ($riskLevel -ne 'Low') { return $false }

		# Gaming tweaks are exempt from PresetTier filtering so the Gaming tab is usable in Safe Mode.
		$isGaming = ([string]$Tweak.Category -eq 'Gaming')
		$presetTier = if ([string]::IsNullOrWhiteSpace([string]$Tweak.PresetTier)) { 'Basic' } else { [string]$Tweak.PresetTier }
		if (-not $isGaming -and @('Minimal', 'Basic', 'Safe') -notcontains $presetTier) { return $false }

		if ((Test-GuiObjectField -Object $Tweak -FieldName 'Safe') -and $null -ne $Tweak.Safe -and -not [bool]$Tweak.Safe) { return $false }

		# Initial setup and other low-risk action items are intentionally one-way
		# but still belong in the conservative starting view.
		$isLowRiskAction = ([string]$Tweak.Type -eq 'Action')
		if (
			-not $isLowRiskAction -and
			(Test-GuiObjectField -Object $Tweak -FieldName 'Restorable') -and
			$null -ne $Tweak.Restorable -and
			-not [bool]$Tweak.Restorable
		)
		{
			return $false
		}

		if (Test-TweakRemovalOperation -Tweak $Tweak) { return $false }

		return $true
	}

	function Test-TweakVisibleInCurrentMode
	{
		param (
			[object]$Tweak,
			[int]$LeftIndent = 28
		)
		if (-not $Tweak) { return $false }

		# Game Mode allowlist entries are always visible regardless of Safe Mode or standard filtering
		if ($Script:GameMode -and $Script:GameModeAllowlist)
		{
			$tweakFunction = [string]$Tweak.Function
			if (-not [string]::IsNullOrWhiteSpace($tweakFunction) -and $Script:GameModeAllowlist -contains $tweakFunction)
			{
				return $true
			}
		}

		if ($Script:SafeMode)
		{
			return (Test-TweakVisibleInSafeMode -Tweak $Tweak)
		}
		if ($Script:AdvancedMode) { return $true }

		$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
		if ($riskLevel -eq 'High') { return $false }

		$tagValues = @($Tweak.Tags | ForEach-Object { [string]$_ })
		if ($tagValues -contains 'advanced') { return $false }

		return $true
	}

	function Get-AvailableCategoryFilters
	{
		param (
			[string]$PrimaryTab,
			[string]$SearchQuery
		)

		$effectiveSearchQuery = if ($null -eq $SearchQuery) { '' } else { [string]$SearchQuery.Trim() }
		$cacheKey = "$PrimaryTab|$effectiveSearchQuery|$Script:RiskFilter|$([int][bool]$Script:SafeMode)|$([int][bool]$Script:AdvancedMode)|$([int][bool]$Script:GamingOnlyFilter)|$([int][bool]$Script:SelectedOnlyFilter)|$([int][bool]$Script:HighRiskOnlyFilter)|$([int][bool]$Script:RestorableOnlyFilter)"
		if ($Script:CategoryFilterListCache -and $Script:CategoryFilterListCache.ContainsKey($cacheKey))
		{
			return $Script:CategoryFilterListCache[$cacheKey]
		}

		$categorySet = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
		$isSearchContext = ($PrimaryTab -eq $Script:SearchResultsTabTag)
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$tweak = $Script:TweakManifest[$i]
			if (-not (Test-TweakVisibleInCurrentMode -Tweak $tweak)) { continue }
			$stateSource = if ($Script:Controls -and $Script:Controls.Count -gt $i) { $Script:Controls[$i] } else { $null }
			if (-not (Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab $PrimaryTab -SearchQuery $effectiveSearchQuery -StateSource $stateSource -IsSearchResultsTab:$isSearchContext -IgnoreCategoryFilter:$true -TweakIndex $i))
			{
				continue
			}
			if ([string]::IsNullOrWhiteSpace([string]$tweak.Category)) { continue }
			[void]$categorySet.Add([string]$tweak.Category)
		}

		$result = @($categorySet)
		if ($Script:CategoryFilterListCache)
		{
			$Script:CategoryFilterListCache[$cacheKey] = $result
		}
		return $result
	}

	function Update-CategoryFilterList
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$PrimaryTab)
		if (-not $CmbCategoryFilter) { return }

		$targetTab = if (-not [string]::IsNullOrWhiteSpace($PrimaryTab)) {
			$PrimaryTab
		}
		elseif ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}

		$currentValue = if ($CmbCategoryFilter.SelectedItem) { [string]$CmbCategoryFilter.SelectedItem } elseif ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
		$searchQuery = if ($null -eq $Script:SearchText) { '' } else { [string]$Script:SearchText.Trim() }

		# Skip the ComboBox clear+repopulate when the same tab/filter state was already rendered.
		# This avoids per-tab-switch WPF layout invalidations when nothing has changed.
		$populateKey = "$targetTab|$searchQuery|$Script:RiskFilter|$([int][bool]$Script:SafeMode)|$([int][bool]$Script:AdvancedMode)|$([int][bool]$Script:GamingOnlyFilter)|$([int][bool]$Script:SelectedOnlyFilter)|$([int][bool]$Script:HighRiskOnlyFilter)|$([int][bool]$Script:RestorableOnlyFilter)|$currentValue"
		if ($Script:LastCategoryFilterPopulateKey -eq $populateKey) { return }
		$Script:LastCategoryFilterPopulateKey = $populateKey

		$values = if ($targetTab) { @(Get-AvailableCategoryFilters -PrimaryTab $targetTab -SearchQuery $searchQuery) } else { @() }

		$Script:FilterUiUpdating = $true
		try
		{
			$CmbCategoryFilter.Items.Clear()
			[void]$CmbCategoryFilter.Items.Add('All')
			foreach ($value in $values)
			{
				[void]$CmbCategoryFilter.Items.Add($value)
			}

			if ($currentValue -and $currentValue -ne 'All' -and $values -contains $currentValue)
			{
				$found = $CmbCategoryFilter.Items.IndexOf($currentValue)
				if ($found -ge 0) { $CmbCategoryFilter.SelectedIndex = [int]$found }
				$Script:CategoryFilter = $currentValue
			}
			else
			{
				[int]$idx = 0
				$CmbCategoryFilter.SelectedIndex = $idx
				$Script:CategoryFilter = 'All'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	function Get-CurrentFilterSummaryItems
	{
		param (
			[string]$SearchQuery = ''
		)

		$items = [System.Collections.Generic.List[object]]::new()
		$effectiveSearchQuery = if ([string]::IsNullOrWhiteSpace($SearchQuery)) { '' } else { ([string]$SearchQuery).Trim() }
		$effectiveRiskFilter = if ($null -eq $Script:RiskFilter) { 'All' } else { ([string]$Script:RiskFilter).Trim() }
		$effectiveCategoryFilter = if ($null -eq $Script:CategoryFilter) { 'All' } else { ([string]$Script:CategoryFilter).Trim() }
		$selectedOnly = ($Script:SelectedOnlyFilter -eq $true)
		$safeMode = ($Script:SafeMode -eq $true)
		$advancedMode = ($Script:AdvancedMode -eq $true)
		$highRiskOnly = ($Script:HighRiskOnlyFilter -eq $true)
		$restorableOnly = ($Script:RestorableOnlyFilter -eq $true)
		$gamingOnly = ($Script:GamingOnlyFilter -eq $true)

		if (-not [string]::IsNullOrWhiteSpace($effectiveSearchQuery))
		{
			[void]$items.Add([pscustomobject]@{
				Label = "Search: $effectiveSearchQuery"
				Tone = 'Muted'
				ToolTip = 'Quick filter search text'
			})
		}

		if (-not [string]::IsNullOrWhiteSpace($effectiveRiskFilter) -and $effectiveRiskFilter -ne 'All')
		{
			$riskTone = switch ($effectiveRiskFilter)
			{
				'High' { 'Danger'; break }
				'Medium' { 'Caution'; break }
				'Low' { 'Success'; break }
				default { 'Primary' }
			}
			[void]$items.Add([pscustomobject]@{
				Label = "Risk: $effectiveRiskFilter"
				Tone = $riskTone
				ToolTip = 'Risk filter'
			})
		}

		if (-not [string]::IsNullOrWhiteSpace($effectiveCategoryFilter) -and $effectiveCategoryFilter -ne 'All')
		{
			[void]$items.Add([pscustomobject]@{
				Label = "Category: $effectiveCategoryFilter"
				Tone = 'Primary'
				ToolTip = 'Category filter'
			})
		}

		if ($selectedOnly)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'Selected only'
				Tone = 'Success'
				ToolTip = 'Shows only currently selected tweaks'
			})
		}

		if ($safeMode)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'Safe mode'
				Tone = 'Success'
				ToolTip = 'Shows only safe tweaks and hides dangerous ones'
			})
		}

		if ($advancedMode)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'Expert mode'
				Tone = 'Danger'
				ToolTip = 'Shows advanced and high-risk tweaks'
			})
		}

		if ($highRiskOnly)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'High-risk only'
				Tone = 'Danger'
				ToolTip = 'Shows only high-risk tweaks'
			})
		}

		if ($restorableOnly)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'Restorable only'
				Tone = 'Success'
				ToolTip = 'Hides tweaks that require manual recovery'
			})
		}

		if ($gamingOnly)
		{
			[void]$items.Add([pscustomobject]@{
				Label = 'Gaming-related'
				Tone = 'Primary'
				ToolTip = 'Shows tweaks that are relevant to gaming'
			})
		}

		return @($items)
	}

	function Test-TweakMatchesCurrentFilters
	{
		param (
			[object]$Tweak,
			[string]$PrimaryTab,
			[string]$SearchQuery,
			[object]$StateSource,
			[bool]$IsSearchResultsTab = $false,
			[bool]$IgnoreCategoryFilter = $false,
			[int]$TweakIndex = -1
		)

		if (-not (Test-TweakVisibleInCurrentMode -Tweak $Tweak)) { return $false }

		$owningPrimary = $CategoryToPrimary[$Tweak.Category]
		if (-not $IsSearchResultsTab -and $owningPrimary -ne $PrimaryTab)
		{
			# Cross-tab entries: allow specific tweaks from other tabs to appear in Gaming
			if ($PrimaryTab -eq 'Gaming' -and $Script:GamingCrossTabFunctions -and $Script:GamingCrossTabFunctions.Contains([string]$Tweak.Function))
			{
				# Allow through — this entry belongs to another tab but is cross-listed in Gaming
			}
			else
			{
				return $false
			}
		}
		$stateSource = if ($StateSource) { $StateSource } else { $Tweak }

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:RiskFilter) -and $Script:RiskFilter -ne 'All')
		{
			$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
			if ($riskLevel -ne $Script:RiskFilter) { return $false }
		}

		if (-not $IgnoreCategoryFilter -and -not [string]::IsNullOrWhiteSpace([string]$Script:CategoryFilter) -and $Script:CategoryFilter -ne 'All')
		{
			if ([string]$Tweak.Category -ne [string]$Script:CategoryFilter) { return $false }
		}

		if ([bool]$Script:SelectedOnlyFilter)
		{
			if (-not (Test-TweakIsSelected -Tweak $Tweak -StateSource $stateSource)) { return $false }
		}

		if ([bool]$Script:HighRiskOnlyFilter)
		{
			$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
			if ($riskLevel -ne 'High') { return $false }
		}

		if ([bool]$Script:RestorableOnlyFilter)
		{
			if (-not (Test-TweakIsRestorable -Tweak $Tweak)) { return $false }
		}

		if ([bool]$Script:GamingOnlyFilter)
		{
			if (-not (Test-TweakIsGamingRelated -Tweak $Tweak)) { return $false }
		}

		$effectiveQuery = if ($null -eq $SearchQuery) { '' } else { $SearchQuery.Trim() }
		if (-not [string]::IsNullOrWhiteSpace($effectiveQuery))
		{
			# Use the pre-computed haystack when available (avoids array/pipeline overhead per call).
			$haystack = if ($TweakIndex -ge 0 -and $Script:TweakSearchHaystacks -and $Script:TweakSearchHaystacks.ContainsKey($TweakIndex))
			{
				$Script:TweakSearchHaystacks[$TweakIndex]
			}
			else
			{
				$searchParts = @(
					$Tweak.Name, $Tweak.Description, $Tweak.Detail, $Tweak.WhyThisMatters,
					$Tweak.Category, $Tweak.SubCategory, $Tweak.Function, $owningPrimary,
					$Tweak.Risk, $Tweak.PresetTier, ($Tweak.Tags -join ' '),
					$(if ($Tweak.Safe) { 'safe' } else { 'not-safe' }),
					$(if ($Tweak.Impact) { 'impact' } else { 'standard' }),
					$(if ($Tweak.RequiresRestart) { 'restart reboot requires-restart' } else { 'no-restart' })
				)
				($searchParts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
			}
			# Plain-text IndexOf is 5-10x faster than regex for literal queries.
			if ($haystack.IndexOf($effectiveQuery, [System.StringComparison]::OrdinalIgnoreCase) -lt 0)
			{
				return $false
			}
		}

		return $true
	}

