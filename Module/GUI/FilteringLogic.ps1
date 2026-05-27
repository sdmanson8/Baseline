# Tweak filtering, visibility, and category filter management

	<#
	    .SYNOPSIS
	#>

	function Test-TweakVisibleByManifestGate
	{
		param (
			[object]$Tweak
		)

		if (-not $Tweak) { return $false }

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
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Test-TweakVisibleByManifestGate:catch31' -Severity Debug }

				return $false
			}
		}

		return $true
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function Test-TweakVisibleInCurrentMode
	{
		param (
			[object]$Tweak,
			[int]$LeftIndent = 28
		)
		if (-not $Tweak) { return $false }
		if (-not (Test-TweakVisibleByManifestGate -Tweak $Tweak)) { return $false }

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

	<#
	    .SYNOPSIS
	#>

	function Get-AvailableCategoryFilters
	{
		param (
			[string]$PrimaryTab,
			[string]$SearchQuery
		)

		$effectiveSearchQuery = if ($null -eq $SearchQuery) { '' } else { [string]$SearchQuery.Trim() }
		$cacheKey = "$PrimaryTab|$effectiveSearchQuery|$Script:RiskFilter|$Script:PlatformFilter|$([int][bool]$Script:HideUnavailableItems)|$([int][bool]$Script:SafeMode)|$([int][bool]$Script:AdvancedMode)|$([int][bool]$Script:GamingOnlyFilter)|$([int][bool]$Script:SelectedOnlyFilter)|$([int][bool]$Script:HighRiskOnlyFilter)|$([int][bool]$Script:RestorableOnlyFilter)"
		if ($Script:CategoryFilterListCache -and $Script:CategoryFilterListCache.ContainsKey($cacheKey))
		{
			return $Script:CategoryFilterListCache[$cacheKey]
		}

		$categorySet = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
		$isSearchContext = ($PrimaryTab -eq $Script:SearchResultsTabTag)

		$candidateIndices = $null
		$tweakIndexMap = Get-Variable -Name TweakIndicesByPrimaryTab -Scope Script -ValueOnly -ErrorAction SilentlyContinue
		if (
			-not $isSearchContext -and
			$tweakIndexMap -and
			$tweakIndexMap.ContainsKey($PrimaryTab)
		)
		{
			$candidateIndices = $tweakIndexMap[$PrimaryTab]
		}

		if ($null -ne $candidateIndices)
		{
			foreach ($i in $candidateIndices)
			{
				$tweak = $Script:TweakManifest[$i]
				if ([string]::IsNullOrWhiteSpace([string]$tweak.Category)) { continue }
				$stateSource = if ($Script:Controls -and $Script:Controls.Count -gt $i) { $Script:Controls[$i] } else { $null }
				if (-not (Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab $PrimaryTab -SearchQuery $effectiveSearchQuery -StateSource $stateSource -IsSearchResultsTab:$isSearchContext -IgnoreCategoryFilter:$true -TweakIndex $i))
				{
					continue
				}
				[void]$categorySet.Add([string]$tweak.Category)
			}
		}
		else
		{
			for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
			{
				$tweak = $Script:TweakManifest[$i]
				if ([string]::IsNullOrWhiteSpace([string]$tweak.Category)) { continue }
				$stateSource = if ($Script:Controls -and $Script:Controls.Count -gt $i) { $Script:Controls[$i] } else { $null }
				if (-not (Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab $PrimaryTab -SearchQuery $effectiveSearchQuery -StateSource $stateSource -IsSearchResultsTab:$isSearchContext -IgnoreCategoryFilter:$true -TweakIndex $i))
				{
					continue
				}
				[void]$categorySet.Add([string]$tweak.Category)
			}
		}

		$result = @($categorySet)
		if ($Script:CategoryFilterListCache)
		{
			$Script:CategoryFilterListCache[$cacheKey] = $result
		}
		return $result
	}

	<#
	    .SYNOPSIS
	#>

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

		$currentValue = if ($Script:CategoryFilterInternalValues -and $CmbCategoryFilter.SelectedIndex -ge 0 -and $CmbCategoryFilter.SelectedIndex -lt $Script:CategoryFilterInternalValues.Count) { $Script:CategoryFilterInternalValues[$CmbCategoryFilter.SelectedIndex] } elseif ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
		$searchQuery = if ($null -eq $Script:SearchText) { '' } else { [string]$Script:SearchText.Trim() }

		# Skip the ComboBox clear+repopulate when the rendered item set is unchanged.
		# The signature deliberately omits the current selection: user selection movement
		# should not force a full ComboBox rebuild.
		$manifestCount = 0
		try { $manifestCount = [int]$Script:TweakManifest.Count } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-CategoryFilterList:catch217' -Severity Debug }
		 $manifestCount = 0 }
		$signature = "{0}|{1}|{2}|{3}|{4}" -f `
			[int]$Script:FilterGeneration, `
			[string]$Script:SelectedLanguage, `
			[string]$targetTab, `
			$searchQuery, `
			$manifestCount
		if ($Script:LastCategoryFilterSignature -eq $signature) { return }

		# Secondary guard for callers that invalidate the older populate key directly.
		$populateKey = "$targetTab|$searchQuery|$Script:RiskFilter|$Script:PlatformFilter|$([int][bool]$Script:HideUnavailableItems)|$([int][bool]$Script:SafeMode)|$([int][bool]$Script:AdvancedMode)|$([int][bool]$Script:GamingOnlyFilter)|$([int][bool]$Script:SelectedOnlyFilter)|$([int][bool]$Script:HighRiskOnlyFilter)|$([int][bool]$Script:RestorableOnlyFilter)|$Script:SelectedLanguage|$Script:FilterGeneration"
		if ($Script:LastCategoryFilterPopulateKey -eq $populateKey)
		{
			$Script:LastCategoryFilterSignature = $signature
			return
		}
		$Script:LastCategoryFilterPopulateKey = $populateKey
		$Script:LastCategoryFilterSignature = $signature

		$values = if ($targetTab) { @(Get-AvailableCategoryFilters -PrimaryTab $targetTab -SearchQuery $searchQuery) } else { @() }

		$Script:FilterUiUpdating = $true
		try
		{
			$CmbCategoryFilter.Items.Clear()
			$Script:CategoryFilterInternalValues = [System.Collections.Generic.List[string]]::new()
			$catLocKeyMap = @{
				'Initial Setup'       = 'GuiTabInitialSetup'
				'Privacy & Telemetry' = 'GuiTabPrivacyTelemetry'
				'Security'            = 'GuiTabSecurity'
				'System'              = 'GuiTabSystem'
				'Updates'             = 'GuiTabUpdates'
				'UI & Personalization'= 'GuiTabUIPersonalization'
				'UWP Apps'            = 'GuiTabUWPApps'
				'Gaming'              = 'GuiTabGaming'
				'Context Menu'        = 'GuiTabContextMenu'
				'Cursors'             = 'GuiTabCursors'
				'OS Hardening'        = 'GuiTabOSHardening'
				'OneDrive'            = 'GuiTabOneDrive'
				'Start Menu'          = 'GuiTabStartMenu'
				'Start Menu Apps'     = 'GuiTabStartMenuApps'
				'System Tweaks'       = 'GuiTabSystemTweaks'
				'Taskbar'             = 'GuiTabTaskbar'
				'Taskbar Clock'       = 'GuiTabTaskbarClock'
			}
			[void]$CmbCategoryFilter.Items.Add((Get-UxLocalizedString -Key 'GuiCategoryAll' -Fallback 'All'))
			[void]$Script:CategoryFilterInternalValues.Add('All')
			foreach ($value in $values)
			{
				$locKey = if ($catLocKeyMap.ContainsKey($value)) { $catLocKeyMap[$value] } else { $null }
				$displayValue = if ($locKey) { Get-UxLocalizedString -Key $locKey -Fallback $value } else { $value }
				[void]$CmbCategoryFilter.Items.Add($displayValue)
				[void]$Script:CategoryFilterInternalValues.Add($value)
			}

			if ($currentValue -and $currentValue -ne 'All' -and $values -contains $currentValue)
			{
				$found = $Script:CategoryFilterInternalValues.IndexOf($currentValue)
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

	<#
	    .SYNOPSIS
	#>

	function Update-RiskFilterList
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $CmbRiskFilter) { return }

		$currentValue = if ($Script:RiskFilterInternalValues -and $CmbRiskFilter.SelectedIndex -ge 0 -and $CmbRiskFilter.SelectedIndex -lt $Script:RiskFilterInternalValues.Count)
		{
			$Script:RiskFilterInternalValues[$CmbRiskFilter.SelectedIndex]
		}
		elseif ($Script:RiskFilter)
		{
			[string]$Script:RiskFilter
		}
		else
		{
			'All'
		}

		$Script:FilterUiUpdating = $true
		try
		{
			$CmbRiskFilter.Items.Clear()
			$riskDisplayAll = Get-UxLocalizedString -Key 'GuiRiskAll' -Fallback 'All'
			$riskDisplayLow = Get-UxLocalizedString -Key 'GuiRiskLowShort' -Fallback 'Low'
			$riskDisplayMedium = Get-UxLocalizedString -Key 'GuiRiskMediumShort' -Fallback 'Medium'
			$riskDisplayHigh = Get-UxLocalizedString -Key 'GuiRiskHighShort' -Fallback 'High'
			$Script:RiskFilterInternalValues = @('All', 'Low', 'Medium', 'High')
			foreach ($riskOption in @($riskDisplayAll, $riskDisplayLow, $riskDisplayMedium, $riskDisplayHigh))
			{
				[void]$CmbRiskFilter.Items.Add($riskOption)
			}

			$idx = 0
			if ($currentValue -and $Script:RiskFilterInternalValues)
			{
				$found = $Script:RiskFilterInternalValues.IndexOf($currentValue)
				if ($found -ge 0) { $idx = $found }
			}
			try
			{
				$CmbRiskFilter.SelectedIndex = [int]$idx
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-RiskFilterList:catch338' -Severity Debug }

				$CmbRiskFilter.SelectedIndex = 0
			}

			if ($Script:RiskFilterInternalValues -and $CmbRiskFilter.SelectedIndex -ge 0 -and $CmbRiskFilter.SelectedIndex -lt $Script:RiskFilterInternalValues.Count)
			{
				$Script:RiskFilter = $Script:RiskFilterInternalValues[$CmbRiskFilter.SelectedIndex]
			}
			else
			{
				$Script:RiskFilter = 'All'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-PlatformFilterDisplayName
	{
		param (
			[string]$PlatformFilter
		)

		switch ((Get-BaselinePlatformFilterOverride -Filter $PlatformFilter).Mode)
		{
			'AllSupported' { return 'All supported' }
			'Windows10'    { return 'Windows 10' }
			'Windows11'    { return 'Windows 11' }
			'Server'       { return 'Server' }
			default        { return 'This device' }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-PlatformFilterAvailability
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$PlatformFilter = $Script:PlatformFilter
		)

		if (-not $Script:TweakManifest) { return }

		$resolved = Get-BaselinePlatformFilterOverride -Filter $PlatformFilter
		$mode = if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Mode)) { [string]$resolved.Mode } else { 'ThisDevice' }
		$Script:PlatformFilter = $mode

		$Script:FilterGeneration++
		if (Get-Command -Name 'Clear-TabContentCache' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Clear-TabContentCache
		}

		if ($mode -eq 'AllSupported')
		{
			if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { $Script:BaselineSystemPlatformInfo = Get-BaselineSystemPlatformInfo } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-PlatformFilterAvailability:catch405' -Severity Debug }
				 $Script:BaselineSystemPlatformInfo = $null }
			}
			if (Get-Command -Name 'Set-BaselineManifestAllAvailable' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$null = Set-BaselineManifestAllAvailable -Manifest $Script:TweakManifest
			}
			if (Get-Command -Name 'Update-BaselineManifestExecutionSupport' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$null = Update-BaselineManifestExecutionSupport -Manifest $Script:TweakManifest
			}
			return $mode
		}

		$systemInfo = $null
		if ($resolved -and $resolved.Override -and (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -CommandType Function -ErrorAction SilentlyContinue))
		{
			try { $systemInfo = Get-BaselineSystemPlatformInfo -Override $resolved.Override } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-PlatformFilterAvailability:catch421' -Severity Debug }
			 $systemInfo = $null }
		}
		elseif (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { $systemInfo = Get-BaselineSystemPlatformInfo } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-PlatformFilterAvailability:catch425' -Severity Debug }
			 $systemInfo = $null }
		}

		$Script:BaselineSystemPlatformInfo = $systemInfo
		if ($systemInfo -and (Get-Command -Name 'Update-BaselineManifestAvailability' -CommandType Function -ErrorAction SilentlyContinue))
		{
			$null = Update-BaselineManifestAvailability -Manifest $Script:TweakManifest -SystemInfo $systemInfo
		}
		if (Get-Command -Name 'Update-BaselineManifestExecutionSupport' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$null = Update-BaselineManifestExecutionSupport -Manifest $Script:TweakManifest
		}

		return $mode
	}

	<#
	    .SYNOPSIS
	#>

	function Set-PlatformFilterState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$PlatformFilter = 'ThisDevice'
		)

		$resolved = Get-BaselinePlatformFilterOverride -Filter $PlatformFilter
		$mode = if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Mode)) { [string]$resolved.Mode } else { 'ThisDevice' }
		$Script:PlatformFilter = $mode
		$null = Update-PlatformFilterAvailability -PlatformFilter $mode
		if ($CmbPlatformFilter)
		{
			Update-PlatformFilterList
		}
		return $mode
	}

	<#
	    .SYNOPSIS
	#>

	function Set-HideUnavailableItemsState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[bool]$HideUnavailableItems = $true
		)

		$normalized = [bool]$HideUnavailableItems
		$Script:HideUnavailableItems = $normalized
		if (Get-Command -Name 'Set-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { Set-BaselineUserPreference -Key 'HideUnavailableItems' -Value $normalized } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Set-HideUnavailableItemsState:catch478' -Severity Debug }
			 $null = $_ }
		}

		$Script:FilterGeneration++
		if (Get-Command -Name 'Clear-TabContentCache' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Clear-TabContentCache
		}

		return $normalized
	}

	<#
	    .SYNOPSIS
	#>

	function Update-PlatformFilterList
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $CmbPlatformFilter) { return }

		$currentValue = if (-not [string]::IsNullOrWhiteSpace([string]$Script:PlatformFilter))
		{
			[string]$Script:PlatformFilter
		}
		elseif ($Script:PlatformFilterInternalValues -and $CmbPlatformFilter.SelectedIndex -ge 0 -and $CmbPlatformFilter.SelectedIndex -lt $Script:PlatformFilterInternalValues.Count)
		{
			$Script:PlatformFilterInternalValues[$CmbPlatformFilter.SelectedIndex]
		}
		else
		{
			'ThisDevice'
		}

		$resolved = Get-BaselinePlatformFilterOverride -Filter $currentValue
		$currentMode = if ($resolved -and -not [string]::IsNullOrWhiteSpace([string]$resolved.Mode)) { [string]$resolved.Mode } else { 'ThisDevice' }
		$populateKey = $currentMode
		if ($Script:LastPlatformFilterPopulateKey -eq $populateKey) { return }
		$Script:LastPlatformFilterPopulateKey = $populateKey

		$Script:FilterUiUpdating = $true
		try
		{
			$CmbPlatformFilter.Items.Clear()
			$Script:PlatformFilterInternalValues = [System.Collections.Generic.List[string]]::new()

			$values = @('ThisDevice', 'AllSupported', 'Windows10', 'Windows11', 'Server')
			foreach ($value in $values)
			{
				[void]$CmbPlatformFilter.Items.Add((Get-PlatformFilterDisplayName -PlatformFilter $value))
				[void]$Script:PlatformFilterInternalValues.Add($value)
			}

			$idx = 0
			if ($Script:PlatformFilterInternalValues -and $Script:PlatformFilterInternalValues.Contains($currentMode))
			{
				$found = $Script:PlatformFilterInternalValues.IndexOf($currentMode)
				if ($found -ge 0) { $idx = $found }
			}
			try
			{
				$CmbPlatformFilter.SelectedIndex = [int]$idx
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Update-PlatformFilterList:catch543' -Severity Debug }

				$CmbPlatformFilter.SelectedIndex = 0
			}

			if ($Script:PlatformFilterInternalValues -and $CmbPlatformFilter.SelectedIndex -ge 0 -and $CmbPlatformFilter.SelectedIndex -lt $Script:PlatformFilterInternalValues.Count)
			{
				$Script:PlatformFilter = $Script:PlatformFilterInternalValues[$CmbPlatformFilter.SelectedIndex]
			}
			else
			{
				$Script:PlatformFilter = 'ThisDevice'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-CurrentFilterSummaryItems
	{
		param (
			[string]$SearchQuery = ''
		)

		$items = [System.Collections.Generic.List[object]]::new()
		$effectiveSearchQuery = if ([string]::IsNullOrWhiteSpace($SearchQuery)) { '' } else { ([string]$SearchQuery).Trim() }
		$effectiveRiskFilter = if ($null -eq $Script:RiskFilter) { 'All' } else { ([string]$Script:RiskFilter).Trim() }
		$effectiveCategoryFilter = if ($null -eq $Script:CategoryFilter) { 'All' } else { ([string]$Script:CategoryFilter).Trim() }
		$effectivePlatformFilter = if ($null -eq $Script:PlatformFilter) { 'ThisDevice' } else { ([string]$Script:PlatformFilter).Trim() }
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
			$riskDisplay = switch ($effectiveRiskFilter)
			{
				'High' { Get-UxLocalizedString -Key 'GuiRiskHighShort' -Fallback 'High' }
				'Medium' { Get-UxLocalizedString -Key 'GuiRiskMediumShort' -Fallback 'Medium' }
				'Low' { Get-UxLocalizedString -Key 'GuiRiskLowShort' -Fallback 'Low' }
				default { Get-UxLocalizedString -Key 'GuiRiskAll' -Fallback 'All' }
			}
			[void]$items.Add([pscustomobject]@{
				Label = ('{0}: {1}' -f (Get-UxLocalizedString -Key 'GuiRiskFilterLabel' -Fallback 'Risk'), $riskDisplay)
				Tone = $riskTone
				ToolTip = (Get-UxLocalizedString -Key 'GuiRiskFilterLabel' -Fallback 'Risk')
			})
		}

		if (-not [string]::IsNullOrWhiteSpace($effectiveCategoryFilter) -and $effectiveCategoryFilter -ne 'All')
		{
			$categoryLocKeyMap = @{
				'Initial Setup'       = 'GuiTabInitialSetup'
				'Privacy & Telemetry' = 'GuiTabPrivacyTelemetry'
				'Security'            = 'GuiTabSecurity'
				'System'              = 'GuiTabSystem'
				'Updates'             = 'GuiTabUpdates'
				'UI & Personalization'= 'GuiTabUIPersonalization'
				'UWP Apps'            = 'GuiTabUWPApps'
				'Gaming'              = 'GuiTabGaming'
				'Context Menu'        = 'GuiTabContextMenu'
				'Cursors'             = 'GuiTabCursors'
				'OS Hardening'        = 'GuiTabOSHardening'
				'OneDrive'            = 'GuiTabOneDrive'
				'Start Menu'          = 'GuiTabStartMenu'
				'Start Menu Apps'     = 'GuiTabStartMenuApps'
				'System Tweaks'       = 'GuiTabSystemTweaks'
				'Taskbar'             = 'GuiTabTaskbar'
				'Taskbar Clock'       = 'GuiTabTaskbarClock'
			}
			$categoryDisplay = $effectiveCategoryFilter
			$categoryLocKey = if ($categoryLocKeyMap.ContainsKey($effectiveCategoryFilter)) { $categoryLocKeyMap[$effectiveCategoryFilter] } else { $null }
			if ($categoryLocKey)
			{
				$categoryDisplay = Get-UxLocalizedString -Key $categoryLocKey -Fallback $effectiveCategoryFilter
			}
			[void]$items.Add([pscustomobject]@{
				Label = ('{0}: {1}' -f (Get-UxLocalizedString -Key 'GuiCategoryFilterLabel' -Fallback 'Category'), $categoryDisplay)
				Tone = 'Primary'
				ToolTip = (Get-UxLocalizedString -Key 'GuiCategoryFilterLabel' -Fallback 'Category')
			})
		}

		if (-not [string]::IsNullOrWhiteSpace($effectivePlatformFilter) -and $effectivePlatformFilter -ne 'ThisDevice')
		{
			$platformDisplay = Get-PlatformFilterDisplayName -PlatformFilter $effectivePlatformFilter
			[void]$items.Add([pscustomobject]@{
				Label = "Platform: $platformDisplay"
				Tone = 'Primary'
				ToolTip = 'Preview entry availability on a selected Windows platform'
			})
		}

		if ($Script:HideUnavailableItems -ne $null)
		{
			[void]$items.Add([pscustomobject]@{
				Label = if ($Script:HideUnavailableItems) { 'Unavailable hidden' } else { 'Unavailable shown' }
				Tone = 'Muted'
				ToolTip = if ($Script:HideUnavailableItems) { 'Unavailable tweaks are hidden from the list' } else { 'Unavailable tweaks remain visible and greyed out' }
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

	<#
	    .SYNOPSIS
	#>

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

		$owningPrimary = Resolve-GuiPrimaryTabForTweak -Tweak $Tweak
		if (-not [bool]$Script:GamingModeActive -and $owningPrimary -eq 'Gaming')
		{
			return $false
		}
		if (-not $IsSearchResultsTab -and $owningPrimary -ne $PrimaryTab)
		{
			# Cross-tab entries: allow specific tweaks from other tabs to appear in Gaming
			if ($PrimaryTab -eq 'Gaming' -and $Script:GamingCrossTabFunctions -and $Script:GamingCrossTabFunctions.Contains([string]$Tweak.Function))
			{
				# Allow through - this entry belongs to another tab but is cross-listed in Gaming
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

		$hideUnavailableItems = $true
		if ($null -ne $Script:HideUnavailableItems)
		{
			$hideUnavailableItems = [bool]$Script:HideUnavailableItems
		}
		elseif (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { $hideUnavailableItems = [bool](Get-BaselineUserPreference -Key 'HideUnavailableItems' -Default $true) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'FilteringLogic.Test-TweakMatchesCurrentFilters:catch778' -Severity Debug }
			 $hideUnavailableItems = $true }
		}

		if ($hideUnavailableItems)
		{
			$availability = $null
			if ($Tweak -is [System.Collections.IDictionary])
			{
				if ($Tweak.Contains('Availability')) { $availability = $Tweak['Availability'] }
			}
			elseif ($Tweak.PSObject -and $Tweak.PSObject.Properties['Availability'])
			{
				$availability = $Tweak.Availability
			}

			$hasAvailabilityFlag = $false
			$isAvailable = $true
			if ($availability -is [System.Collections.IDictionary])
			{
				if ($availability.Contains('Available'))
				{
					$hasAvailabilityFlag = $true
					$isAvailable = [bool]$availability['Available']
				}
			}
			elseif ($availability -and $availability.PSObject -and $availability.PSObject.Properties['Available'])
			{
				$hasAvailabilityFlag = $true
				$isAvailable = [bool]$availability.Available
			}

			if ($hasAvailabilityFlag -and -not $isAvailable) { return $false }
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
