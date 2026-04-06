# Tab content building, caching, scroll offset persistence, and grouped tweak resolution

	function Save-CurrentTabScrollOffset
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $ContentScroll -or -not $Script:CurrentPrimaryTab) { return }
		$Script:TabScrollOffsets[$Script:CurrentPrimaryTab] = [double]$ContentScroll.VerticalOffset
	}

	function Restore-CurrentTabScrollOffset
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$TabKey)
		if (-not $ContentScroll -or [string]::IsNullOrWhiteSpace($TabKey)) { return }
		$offset = if ($Script:TabScrollOffsets.ContainsKey($TabKey)) { [double]$Script:TabScrollOffsets[$TabKey] } else { 0 }
		$null = Invoke-GuiDispatcherAction -Dispatcher $ContentScroll.Dispatcher -PriorityUsage 'RenderRefresh' -Action {
			try { $ContentScroll.ScrollToVerticalOffset($offset) } catch { $null = $_ }
		}
	}

	function Update-MainContentPanelWidth
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.FrameworkElement]$Panel
		)

		if (-not $Panel -or -not $ContentScroll) { return }

		# Use Stretch + Margin instead of a fixed Width so the panel
		# resizes automatically when the window is maximized / restored.
		$Panel.Width = [double]::NaN
		$Panel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
		$Panel.Margin = [System.Windows.Thickness]::new(12, 0, 12, 0)
	}

	function Clear-TabContentCache
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$PrimaryTab
		)

		if (-not [string]::IsNullOrWhiteSpace($PrimaryTab))
		{
			# Selective invalidation: only evict the specified tab.
			if ($Script:TabContentCache -and $Script:TabContentCache.ContainsKey($PrimaryTab))
			{
				[void]$Script:TabContentCache.Remove($PrimaryTab)
			}
			if ($Script:CategoryFilterListCache)
			{
				$staleFilterKeys = @($Script:CategoryFilterListCache.Keys | Where-Object { [string]$_ -and ([string]$_).StartsWith("$PrimaryTab|") })
				foreach ($staleFilterKey in $staleFilterKeys)
				{
					[void]$Script:CategoryFilterListCache.Remove($staleFilterKey)
				}
			}
			if ($Script:LastCategoryFilterPopulateKey -and $Script:LastCategoryFilterPopulateKey.StartsWith("$PrimaryTab|"))
			{
				$Script:LastCategoryFilterPopulateKey = $null
			}
		}
		else
		{
			$Script:TabContentCache = @{}
			$Script:CategoryFilterListCache = @{}
			$Script:LastCategoryFilterPopulateKey = $null
		}
	}

	function Sync-GuiControlState
	{
		param (
			[object]$Source,
			[object]$Target
		)

		if (-not $Source -or -not $Target) { return }

		if ((Test-GuiObjectField -Object $Target -FieldName 'IsEnabled') -and (Test-GuiObjectField -Object $Source -FieldName 'IsEnabled'))
		{
			$sourceEnabled = [bool]$Source.IsEnabled
			if ([bool]$Target.IsEnabled -ne $sourceEnabled)
			{
				$Target.IsEnabled = $sourceEnabled
			}
		}

		if ((Test-GuiObjectField -Object $Target -FieldName 'IsChecked') -and (Test-GuiObjectField -Object $Source -FieldName 'IsChecked'))
		{
			$sourceChecked = [bool]$Source.IsChecked
			if ([bool]$Target.IsChecked -ne $sourceChecked)
			{
				$Target.IsChecked = $sourceChecked
			}
		}

		if ((Test-GuiObjectField -Object $Target -FieldName 'SelectedIndex') -and (Test-GuiObjectField -Object $Source -FieldName 'SelectedIndex'))
		{
			$sourceIndex = [int]$Source.SelectedIndex
			if ([int]$Target.SelectedIndex -ne $sourceIndex)
			{
				$Target.SelectedIndex = $sourceIndex
			}
		}
	}

	function Restore-CachedTabContent
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[Parameter(Mandatory = $true)]
			[string]$PrimaryTab
		)

		if (-not $ContentScroll -or -not $Script:TabContentCache.ContainsKey($PrimaryTab))
		{
			return $false
		}

		$cacheEntry = $Script:TabContentCache[$PrimaryTab]
		if (-not $cacheEntry -or -not $cacheEntry.Panel)
		{
			[void]($Script:TabContentCache.Remove($PrimaryTab))
			return $false
		}

		# Evict stale entries whose filter generation no longer matches the current state.
		if ($null -ne $cacheEntry.FilterGeneration -and $cacheEntry.FilterGeneration -ne $Script:FilterGeneration)
		{
			[void]($Script:TabContentCache.Remove($PrimaryTab))
			return $false
		}

		if ($cacheEntry.ControlRefs -is [System.Collections.IDictionary])
		{
			foreach ($indexKey in @($cacheEntry.ControlRefs.Keys))
			{
				$index = [int]$indexKey
				$cachedControl = $cacheEntry.ControlRefs[$indexKey]
				if (-not $cachedControl) { continue }

				$currentState = if ($Script:Controls.ContainsKey($index)) { $Script:Controls[$index] } else { $null }
				if ($currentState)
				{
					Sync-GuiControlState -Source $currentState -Target $cachedControl
				}

				$Script:Controls[$index] = $cachedControl
			}
		}

		$Script:PresetStatusBadge = $cacheEntry.PresetStatusBadge
		if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:PresetStatusBadge.Child.Text = [string]$Script:PresetStatusMessage
		}

		$ContentScroll.Content = $cacheEntry.Panel
		Update-MainContentPanelWidth -Panel $cacheEntry.Panel
		Restore-CurrentTabScrollOffset -TabKey $PrimaryTab
		return $true
	}

	function New-TabContentMainPanel
	{
		param ([object]$BrushConverter)

		$mainPanel = New-Object System.Windows.Controls.StackPanel
		$mainPanel.Orientation = 'Vertical'
		$mainPanel.Background = $BrushConverter.ConvertFromString($Script:CurrentTheme.PanelBg)
		$mainPanel.Margin = [System.Windows.Thickness]::new(0)
		$mainPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
		return $mainPanel
	}

	function Get-TabContentGroupedTweaks
	{
		param (
			[string]$PrimaryTab,
			[string]$SearchQuery,
			[bool]$IsSearchResultsTab
		)

		$categoryTweaks = [ordered]@{}
		$matchCount = 0
		for ($index = 0; $index -lt $Script:TweakManifest.Count; $index++)
		{
			$tweak = $Script:TweakManifest[$index]
			if (-not $tweak) { continue }

			$stateSource = if ($Script:Controls -and $Script:Controls.ContainsKey($index)) { $Script:Controls[$index] } else { $null }
			if (-not (Test-TweakMatchesCurrentFilters -Tweak $tweak -PrimaryTab $PrimaryTab -SearchQuery $SearchQuery -StateSource $stateSource -IsSearchResultsTab:$IsSearchResultsTab -TweakIndex $index))
			{
				continue
			}

			$primaryCategory = if ($CategoryToPrimary.ContainsKey([string]$tweak.Category))
			{
				[string]$CategoryToPrimary[[string]$tweak.Category]
			}
			else
			{
				[string]$tweak.Category
			}

			$focusGroup = 'General'
			$focusGroupCandidate = Get-TweakFocusGroup -Tweak $tweak
			if (-not [string]::IsNullOrWhiteSpace([string]$focusGroupCandidate))
			{
				$focusGroup = [string]$focusGroupCandidate
			}

			$groupKey = if ($IsSearchResultsTab)
			{
				'{0} | {1}' -f $primaryCategory, $focusGroup
			}
			else
			{
				$focusGroup
			}
			if ([string]::IsNullOrWhiteSpace([string]$groupKey))
			{
				$groupKey = 'General'
			}

			$normalizedGroupKey = [string]$groupKey
			if (-not $categoryTweaks.Contains($normalizedGroupKey))
			{
				$categoryTweaks[$normalizedGroupKey] = [System.Collections.Generic.List[int]]::new()
			}
			$categoryTweaks[$normalizedGroupKey].Add($index)
			$matchCount++
		}

		return [pscustomobject]@{
			CategoryTweaks = $categoryTweaks
			MatchCount     = $matchCount
		}
	}

	function New-TabContentBuildContext
	{
		param ([string]$PrimaryTab)

		$brushConverter = New-SafeBrushConverter -Context 'Build-TabContent'
		$isSearchResultsTab = ($PrimaryTab -eq $Script:SearchResultsTabTag)
		$setGuiPresetSelectionCommand = Get-GuiRuntimeCommand -Name 'Set-GuiPresetSelection' -CommandType 'Function'
		$setGuiScenarioProfileSelectionCommand = Get-GuiRuntimeCommand -Name 'Set-GuiScenarioProfileSelection' -CommandType 'Function'
		$writeGuiPresetDebugCommand = Get-GuiRuntimeCommand -Name 'Write-GuiPresetDebug' -CommandType 'Function'
		if (-not $setGuiPresetSelectionCommand)
		{
			throw "Build-TabContent could not resolve function 'Set-GuiPresetSelection'."
		}

		$searchQuery = [string]$Script:SearchText
		if ($null -eq $searchQuery) { $searchQuery = '' }
		$searchQuery = $searchQuery.Trim()

		$groupedTweaks = Get-TabContentGroupedTweaks -PrimaryTab $PrimaryTab -SearchQuery $searchQuery -IsSearchResultsTab:$isSearchResultsTab
		return [pscustomobject]@{
			PrimaryTab                         = $PrimaryTab
			BrushConverter                     = $brushConverter
			IsSearchResultsTab                 = $isSearchResultsTab
			SearchQuery                        = $searchQuery
			CategoryTweaks                     = $groupedTweaks.CategoryTweaks
			MatchCount                         = $groupedTweaks.MatchCount
			MainPanel                          = New-TabContentMainPanel -BrushConverter $brushConverter
			SetGuiPresetSelectionCommand       = $setGuiPresetSelectionCommand
			SetGuiScenarioProfileSelectionCommand = $setGuiScenarioProfileSelectionCommand
			WriteGuiPresetDebugCommand         = $writeGuiPresetDebugCommand
		}
	}

