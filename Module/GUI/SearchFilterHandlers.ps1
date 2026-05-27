	# Capture functions into $Script: variables so WPF event handler delegates can resolve them.
	$Script:SetSearchInputStyleScript = ${function:Set-SearchInputStyle}
	$Script:SyncSearchInputChromeScript = ${function:Sync-GuiSearchInputChrome}
	$Script:SetSafeModeStateScript = ${function:Set-SafeModeState}
	$Script:SetAdvancedModeStateScript = ${function:Set-AdvancedModeState}
	$Script:SetDesignModeStateScript = ${function:Set-DesignModeState}
	$Script:SaveCurrentTabScrollOffsetScript = ${function:Save-CurrentTabScrollOffset}
	$Script:UpdateMainContentPanelWidthScript = ${function:Update-MainContentPanelWidth}
	function Get-GuiScriptControlValue
	{
		param (
			[string]$Name
		)

		$variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
		if ($variable) { return $variable.Value }
		return $null
	}

	function Test-GuiFilterPanelExpanded
	{
		param (
			[object]$Panel
		)

		return ($null -ne $Panel -and $Panel.Visibility -eq [System.Windows.Visibility]::Visible)
	}

	function New-GuiFilterToggleContent
	{
		param (
			[string]$LabelKey,
			[string]$Fallback,
			[bool]$Expanded
		)

		$arrow = if ($Expanded) { [char]0x25BE } else { [char]0x25B8 }
		$label = Get-UxLocalizedString -Key $LabelKey -Fallback $Fallback
		$text = "{0} {1}" -f $label, $arrow
		$hasLabeledIconContent = [bool](Get-GuiScriptControlValue -Name 'HasLabeledIconContent')
		if (-not $hasLabeledIconContent)
		{
			$hasLabeledIconContent = [bool](Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue)
			if ($hasLabeledIconContent) { $Script:HasLabeledIconContent = $true }
		}
		if ($hasLabeledIconContent)
		{
			$content = New-GuiLabeledIconContent -IconName 'Filter' -Text $text -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback
			if ($content) { return $content }
		}
		return $text
	}

	function Set-GuiFilterPanelExpandedState
	{
		param (
			[ValidateSet('Optimize', 'Apps')]
			[string]$Scope,

			[bool]$Expanded
		)

		if ($Scope -eq 'Apps')
		{
			$panel = Get-GuiScriptControlValue -Name 'AppsFilterOptionsPanel'
			$button = Get-GuiScriptControlValue -Name 'BtnAppsFilterToggle'
			$labelKey = 'GuiBtnAppsFilterToggle'
			$fallback = 'Filter'
		}
		else
		{
			$panel = Get-GuiScriptControlValue -Name 'FilterOptionsPanel'
			$button = Get-GuiScriptControlValue -Name 'BtnFilterToggle'
			$labelKey = 'GuiBtnFilterToggle'
			$fallback = 'Filters'
		}

		if ($panel)
		{
			$panel.Visibility = if ($Expanded) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
		if ($button)
		{
			$button.Content = New-GuiFilterToggleContent -LabelKey $labelKey -Fallback $fallback -Expanded $Expanded
		}
		if ($Scope -eq 'Optimize')
		{
			$menu = Get-GuiScriptControlValue -Name 'MenuViewFilters'
			if ($menu)
			{
				try { $menu.IsChecked = [bool]$Expanded } catch { Write-SwallowedException -ErrorRecord $_ -Source 'SearchFilterHandlers.SetGuiFilterPanelExpandedState.MenuViewFilters' }
			}
		}
	}

	$Script:TestGuiFilterPanelExpandedScript = ${function:Test-GuiFilterPanelExpanded}
	$Script:SetGuiFilterPanelExpandedStateScript = ${function:Set-GuiFilterPanelExpandedState}
	$testGuiRunInProgressCapture = $Script:TestGuiRunInProgressScript
	$syncSearchInputChrome = {
		if ($Script:SyncSearchInputChromeScript)
		{
			& $Script:SyncSearchInputChromeScript
			return
		}
		if (Get-Command -Name 'Sync-GuiSearchInputChrome' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-GuiSearchInputChrome
		}
	}

	$searchRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
	$searchRefreshTimer.Interval = [TimeSpan]::FromMilliseconds($Script:SearchRefreshDelayMs)
	$refreshSearchContentForTimer = $refreshSearchContent
	$null = Register-GuiEventHandler -Source $searchRefreshTimer -EventName 'Tick' -Handler ({
		$searchRefreshTimer.Stop()
		& $refreshSearchContentForTimer
	})
	$Script:SearchRefreshTimer = $searchRefreshTimer

	$Script:PendingFilterValues = @{}
	$filterRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
	$filterRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(120)
	$null = Register-GuiEventHandler -Source $filterRefreshTimer -EventName 'Tick' -Handler ({
		$filterRefreshTimer.Stop()
		$pending = $Script:PendingFilterValues
		if (-not $pending -or $pending.Count -eq 0) { return }

		$keys = @($pending.Keys)
		foreach ($key in $keys)
		{
			try { & $Script:GuiState.Set $key $pending[$key] }
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'SearchFilterHandlers.ApplyPendingFilter' }
		}
		$pending.Clear()
	})
	$Script:FilterRefreshTimer = $filterRefreshTimer

	Set-SearchInputStyle
	Set-FilterControlStyle
	# Cache the icon content command once to avoid Get-Command on every filter click.
	$Script:HasLabeledIconContent = [bool](Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue)
	# Filter toggle button - shows/hides the collapsible filter options panel
	$null = Register-GuiEventHandler -Source $BtnFilterToggle -EventName 'Click' -Handler ({
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded:(-not (Test-GuiFilterPanelExpanded -Panel $FilterOptionsPanel))
	})
	$TxtSearch.Text = if ($Script:AppsModeActive) { [string]$Script:AppsSearchText } else { [string]$Script:SearchText }
	& $syncSearchInputChrome
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'GotKeyboardFocus' -Handler ({
		Invoke-CapturedFunction -Name 'Set-SearchInputStyle'
	})
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'LostKeyboardFocus' -Handler ({
		Invoke-CapturedFunction -Name 'Set-SearchInputStyle'
	})
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'TextChanged' -Handler ({
		if ((& $testGuiRunInProgressCapture) -or $Script:SearchUiUpdating) { return }
		$currentText = [string]$TxtSearch.Text
		if ($Script:AppsModeActive)
		{
			$Script:AppsSearchText = $currentText
		}
		else
		{
			$Script:SearchText = $currentText
		}
		& $syncSearchInputChrome
		if ($Script:SearchRefreshTimer)
		{
			$Script:SearchRefreshTimer.Stop()
			$Script:SearchRefreshTimer.Start()
		}
		else
		{
			& $refreshSearchContent
		}
	})
	$null = Register-GuiEventHandler -Source $CmbRiskFilter -EventName 'SelectionChanged' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		$selectedRisk = if ($CmbRiskFilter.SelectedIndex -ge 0 -and $Script:RiskFilterInternalValues -and $CmbRiskFilter.SelectedIndex -lt $Script:RiskFilterInternalValues.Count) { $Script:RiskFilterInternalValues[$CmbRiskFilter.SelectedIndex] } else { 'All' }
		if ($Script:FilterRefreshTimer)
		{
			$Script:PendingFilterValues['RiskFilter'] = $selectedRisk
			$Script:FilterRefreshTimer.Stop()
			$Script:FilterRefreshTimer.Start()
		}
		else
		{
			& $Script:GuiState.Set 'RiskFilter' $selectedRisk
		}
		if ($selectedRisk -ne 'All') { Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true }
	})
	$null = Register-GuiEventHandler -Source $CmbCategoryFilter -EventName 'SelectionChanged' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		$selectedCat = if ($CmbCategoryFilter.SelectedIndex -ge 0 -and $Script:CategoryFilterInternalValues -and $CmbCategoryFilter.SelectedIndex -lt $Script:CategoryFilterInternalValues.Count) { $Script:CategoryFilterInternalValues[$CmbCategoryFilter.SelectedIndex] } else { 'All' }
		if ($Script:FilterRefreshTimer)
		{
			$Script:PendingFilterValues['CategoryFilter'] = $selectedCat
			$Script:FilterRefreshTimer.Stop()
			$Script:FilterRefreshTimer.Start()
		}
		else
		{
			& $Script:GuiState.Set 'CategoryFilter' $selectedCat
		}
		if ($selectedCat -ne 'All') { Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true }
	})
	$null = Register-GuiEventHandler -Source $CmbPlatformFilter -EventName 'SelectionChanged' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		$selectedPlatform = if ($CmbPlatformFilter.SelectedIndex -ge 0 -and $Script:PlatformFilterInternalValues -and $CmbPlatformFilter.SelectedIndex -lt $Script:PlatformFilterInternalValues.Count) { $Script:PlatformFilterInternalValues[$CmbPlatformFilter.SelectedIndex] } else { 'ThisDevice' }
		Set-PlatformFilterState -PlatformFilter $selectedPlatform
		if ($Script:UpdateCurrentTabContentScript)
		{
			& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
		}
		elseif (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-CurrentTabContent -SkipIdlePrebuild
		}
		if ($selectedPlatform -ne 'ThisDevice') { Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true }
	})
	if ($Script:AppsCategoryTabs)
	{
		$null = Register-GuiEventHandler -Source $Script:AppsCategoryTabs -EventName 'SelectionChanged' -Handler ({
			param($appsTabSender, $appsTabEventArgs)
			if (-not $appsTabEventArgs) { return }
			if ($appsTabEventArgs.Source -ne $Script:AppsCategoryTabs) { return }
			if ($Script:AppsFilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
			$selectedAppTab = $Script:AppsCategoryTabs.SelectedItem
			$selectedAppCategory = if ($selectedAppTab -and $selectedAppTab.Tag) { [string]$selectedAppTab.Tag } else { 'All' }
			Set-AppCategoryFilterState -Category $selectedAppCategory
		})
	}
	if ($Script:BtnAppsFilterToggle -and $Script:AppsFilterOptionsPanel)
	{
		$null = Register-GuiEventHandler -Source $Script:BtnAppsFilterToggle -EventName 'Click' -Handler ({
			Set-GuiFilterPanelExpandedState -Scope 'Apps' -Expanded:(-not (Test-GuiFilterPanelExpanded -Panel $Script:AppsFilterOptionsPanel))
		})
	}
	$null = Register-GuiEventHandler -Source $CmbAppsStatusFilter -EventName 'SelectionChanged' -Handler ({
		if ($Script:AppsFilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		$selectedAppStatus = if ($CmbAppsStatusFilter.SelectedIndex -ge 0 -and $Script:AppsStatusFilterInternalValues -and $CmbAppsStatusFilter.SelectedIndex -lt $Script:AppsStatusFilterInternalValues.Count) { $Script:AppsStatusFilterInternalValues[$CmbAppsStatusFilter.SelectedIndex] } else { 'All' }
		Set-AppStatusFilterState -Status $selectedAppStatus
		if ($selectedAppStatus -ne 'All') { Set-GuiFilterPanelExpandedState -Scope 'Apps' -Expanded $true }
	})
	$null = Register-GuiEventHandler -Source $ChkSelectedOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'SelectedOnlyFilter' $true
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true
	})
	$null = Register-GuiEventHandler -Source $ChkSelectedOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'SelectedOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkHideUnavailableItems -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		Set-HideUnavailableItemsState -HideUnavailableItems $true
		if ($Script:UpdateCurrentTabContentScript)
		{
			& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
		}
		elseif (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-CurrentTabContent -SkipIdlePrebuild
		}
	})
	$null = Register-GuiEventHandler -Source $ChkHideUnavailableItems -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		Set-HideUnavailableItemsState -HideUnavailableItems $false
		if ($Script:UpdateCurrentTabContentScript)
		{
			& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
		}
		elseif (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-CurrentTabContent -SkipIdlePrebuild
		}
	})
	$null = Register-GuiEventHandler -Source $ChkHighRiskOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'HighRiskOnlyFilter' $true
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true
	})
	$null = Register-GuiEventHandler -Source $ChkHighRiskOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'HighRiskOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkRestorableOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'RestorableOnlyFilter' $true
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true
	})
	$null = Register-GuiEventHandler -Source $ChkRestorableOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'RestorableOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkGamingOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'GamingOnlyFilter' $true
		Set-GuiFilterPanelExpandedState -Scope 'Optimize' -Expanded $true
	})
	$null = Register-GuiEventHandler -Source $ChkGamingOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'GamingOnlyFilter' $false
	})
	if ($ChkDesignMode)
	{
		$null = Register-GuiEventHandler -Source $ChkDesignMode -EventName 'Checked' -Handler ({
			if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
			& $Script:SetDesignModeStateScript -Enabled $true
		})
		$null = Register-GuiEventHandler -Source $ChkDesignMode -EventName 'Unchecked' -Handler ({
			if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
			& $Script:SetDesignModeStateScript -Enabled $false
		})
	}
	$null = Register-GuiEventHandler -Source $BtnClearSearch -EventName 'Click' -Handler ({
		$Script:SearchUiUpdating = $true
		try
		{
			$Script:SearchText = ''
			$Script:AppsSearchText = ''
			$TxtSearch.Text = ''
		}
		finally
		{
			$Script:SearchUiUpdating = $false
		}
		& $syncSearchInputChrome
		[void]($TxtSearch.Focus())
		if ($Script:SearchRefreshTimer)
		{
			$Script:SearchRefreshTimer.Stop()
		}

		if ($Script:AppsModeActive)
		{
			if (Get-Command -Name 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Build-AppsViewCards
			}
			return
		}

		if ($Script:TabContentCache -and $Script:SearchResultsTabTag -and $Script:TabContentCache.ContainsKey($Script:SearchResultsTabTag))
		{
			[void]$Script:TabContentCache.Remove($Script:SearchResultsTabTag)
		}
		Update-SearchResultsTabState
		if (Get-Command -Name 'Update-CurrentTabContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-CurrentTabContent -SkipIdlePrebuild
		}
	})
	# Enable pixel-based smooth scrolling
	[System.Windows.Controls.ScrollViewer]::SetCanContentScroll($ContentScroll, $false)
	[System.Windows.Controls.ScrollViewer]::SetIsDeferredScrollingEnabled($ContentScroll, $false)
	$scrollSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
	$scrollSaveTimer.Interval = [TimeSpan]::FromMilliseconds(100)
	$null = Register-GuiEventHandler -Source $scrollSaveTimer -EventName 'Tick' -Handler ({
		$scrollSaveTimer.Stop()
		Invoke-CapturedFunction -Name 'Save-CurrentTabScrollOffset'
	})
	$null = Register-GuiEventHandler -Source $ContentScroll -EventName 'ScrollChanged' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$scrollSaveTimer.Stop()
		$scrollSaveTimer.Start()
	})
	$null = Register-GuiEventHandler -Source $ContentScroll -EventName 'SizeChanged' -Handler ({
		if ($ContentScroll.Content -is [System.Windows.FrameworkElement])
		{
			& $Script:UpdateMainContentPanelWidthScript -Panel $ContentScroll.Content
		}
	})
