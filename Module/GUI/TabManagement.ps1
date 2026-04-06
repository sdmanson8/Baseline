# Primary tab visual management, hover effects, search results tab lifecycle, localized tab headers

	function Get-LocalizedTabHeader
	{
		param ([string]$PrimaryTab)
		$keyMap = @{
			'Initial Setup'        = 'GuiTabInitialSetup'
			'Privacy & Telemetry'  = 'GuiTabPrivacyTelemetry'
			'Security'             = 'GuiTabSecurity'
			'System'               = 'GuiTabSystem'
			'UI & Personalization' = 'GuiTabUIPersonalization'
			'UWP Apps'             = 'GuiTabUWPApps'
			'Gaming'               = 'GuiTabGaming'
			'Context Menu'         = 'GuiTabContextMenu'
		}
		$locKey = $keyMap[$PrimaryTab]
		if ($locKey)
		{
			return (Get-UxLocalizedString -Key $locKey -Fallback $PrimaryTab)
		}
		return $PrimaryTab
	}

	function Update-PrimaryTabHeaders
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		foreach ($tab in $PrimaryTabs.Items)
		{
			if (-not ($tab -is [System.Windows.Controls.TabItem])) { continue }
			$pKey = [string]$tab.Tag
			if ([string]::IsNullOrWhiteSpace($pKey) -or $pKey -eq $Script:SearchResultsTabTag) { continue }

			# Count tweaks for this tab
			$tweakCount = 0
			for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
			{
				if ($CategoryToPrimary[$Script:TweakManifest[$i].Category] -eq $pKey)
				{
					$tweakCount++
				}
			}

			$displayName = Get-LocalizedTabHeader -PrimaryTab $pKey
			$tabIconName = Get-GuiPrimaryTabIconName -PrimaryTab $pKey
			if ($tabIconName)
			{
				$tab.Header = New-GuiLabeledIconContent -IconName $tabIconName -Text "$displayName ($tweakCount)" -IconSize 16 -Gap 6 -AllowTextOnlyFallback
			}
			else
			{
				$tab.Header = "$displayName ($tweakCount)"
			}
		}
	}


	function Update-PrimaryTabVisuals
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$bc = New-SafeBrushConverter -Context 'Update-PrimaryTabVisuals'
		foreach ($tab in $PrimaryTabs.Items)
		{
			if (-not ($tab -is [System.Windows.Controls.TabItem])) { continue }
			$tab.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
			$tab.Padding = [System.Windows.Thickness]::new(14, 7, 14, 7)
			if ($tab -eq $PrimaryTabs.SelectedItem)
			{
				$tab.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
				$tab.Foreground = $bc.ConvertFromString('#FFFFFF')
				$tab.FontWeight = [System.Windows.FontWeights]::SemiBold
				$tab.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.ActiveTabIndicator)
				$tab.BorderThickness = [System.Windows.Thickness]::new(0, 3, 0, 3)
			}
			else
			{
				$tab.Background = $bc.ConvertFromString($Script:CurrentTheme.TabBg)
				$tab.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
				$tab.FontWeight = [System.Windows.FontWeights]::Normal
				$tab.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.BorderColor)
			}
		}
	}

	function Add-PrimaryTabHoverEffects
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([System.Windows.Controls.TabItem]$Tab)
		if (-not $Tab) { return }
		$setGuiControlPropertyScript = ${function:Set-GuiControlProperty}
		$invokeGuiSafeActionScript = ${function:Invoke-GuiSafeAction}
		$newSafeBrushConverterScript = $Script:NewSafeBrushConverterScript
		$newSafeThicknessScript = ${function:New-SafeThickness}
		$updatePrimaryTabVisualsScript = ${function:Update-PrimaryTabVisuals}

		$mouseEnterHandler = {
			if ($Tab -eq $PrimaryTabs.SelectedItem) { return }
			$bc = & $newSafeBrushConverterScript -Context 'Add-PrimaryTabHoverEffects/MouseEnter'

			$hoverBgColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.TabHoverBg)) { [string]$Script:CurrentTheme.TabHoverBg } else { '#3670B8' }
			$textPrimaryColor = '#FFFFFF'
			$focusRingColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.FocusRing)) { [string]$Script:CurrentTheme.FocusRing } else { '#C9DEFF' }

			[void](& $setGuiControlPropertyScript -Control $Tab -PropertyName 'Background' -Value ($bc.ConvertFromString($hoverBgColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/Background')
			[void](& $setGuiControlPropertyScript -Control $Tab -PropertyName 'Foreground' -Value ($bc.ConvertFromString($textPrimaryColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/Foreground')
			[void](& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderBrush' -Value ($bc.ConvertFromString($focusRingColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/BorderBrush')
		}.GetNewClosure()
		Register-GuiEventHandler -Source $Tab -EventName 'MouseEnter' -Handler ({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/MouseEnter' -Action $mouseEnterHandler
		}.GetNewClosure())

		$refreshTabVisualsHandler = {
			& $updatePrimaryTabVisualsScript
		}.GetNewClosure()
		Register-GuiEventHandler -Source $Tab -EventName 'MouseLeave' -Handler ({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/MouseLeave' -Action $refreshTabVisualsHandler
		}.GetNewClosure())

		$gotFocusHandler = {
			if ($Tab -eq $PrimaryTabs.SelectedItem) { return }
			$bc = & $newSafeBrushConverterScript -Context 'Add-PrimaryTabHoverEffects/GotFocus'
			$focusRingColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.FocusRing)) { [string]$Script:CurrentTheme.FocusRing } else { '#C9DEFF' }
			[void](& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderBrush' -Value ($bc.ConvertFromString($focusRingColor)) -Context 'Add-PrimaryTabHoverEffects/GotFocus/BorderBrush')
			[void](& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderThickness' -Value (& $newSafeThicknessScript -Bottom 3) -Context 'Add-PrimaryTabHoverEffects/GotFocus/BorderThickness')
		}.GetNewClosure()
		Register-GuiEventHandler -Source $Tab -EventName 'GotKeyboardFocus' -Handler ({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/GotFocus' -Action $gotFocusHandler
		}.GetNewClosure())

		Register-GuiEventHandler -Source $Tab -EventName 'LostKeyboardFocus' -Handler ({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/LostFocus' -Action $refreshTabVisualsHandler
		}.GetNewClosure())
	}

	function Get-PrimaryTabItem
	{
		param ([string]$Tag)
		foreach ($tab in $PrimaryTabs.Items)
		{
			if (($tab -is [System.Windows.Controls.TabItem]) -and ([string]$tab.Tag -eq $Tag))
			{
				return $tab
			}
		}
		return $null
	}

	function Initialize-SearchResultsTab
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		# Legacy stub: no longer creates a TabItem. Inline search results are
		# rendered directly into the current tab's ContentScroll instead.
		return $null
	}

	function Remove-SearchResultsTab
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		# Legacy stub: clean up any leftover Search Results tab that may exist
		# from a previous version or mid-session upgrade.
		$searchTab = Get-PrimaryTabItem -Tag $Script:SearchResultsTabTag
		if ($searchTab)
		{
			$PrimaryTabs.Items.Remove($searchTab)
			Update-PrimaryTabVisuals
		}
	}

	function Update-SearchResultsTabState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		# Remove any leftover Search Results tab from the tab bar (inline banner replaces it).
		Remove-SearchResultsTab

		$searchQuery = if ($null -eq $Script:SearchText) { '' } else { $Script:SearchText.Trim() }
		if (-not [string]::IsNullOrWhiteSpace($searchQuery))
		{
			# Remember the real tab the user was on before search activated.
			$selectedTag = if ($PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) { [string]$PrimaryTabs.SelectedItem.Tag } else { $null }
			if ($selectedTag -and $selectedTag -ne $Script:SearchResultsTabTag)
			{
				$Script:LastStandardPrimaryTab = $selectedTag
			}

			# Build cross-tab search results inline (no tab switch).
			# This sets ContentScroll.Content to the search results panel and
			# sets $Script:CurrentPrimaryTab to the search sentinel tag.
			Build-TabContent -PrimaryTab $Script:SearchResultsTabTag
			return
		}

		# Search was cleared -- restore the previous real tab content.
		$wasShowingSearchResults = ($Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)

		# Evict search-results cache entry so it is rebuilt fresh next time.
		if ($Script:TabContentCache -and $Script:TabContentCache.ContainsKey($Script:SearchResultsTabTag))
		{
			[void]$Script:TabContentCache.Remove($Script:SearchResultsTabTag)
		}

		if ($wasShowingSearchResults)
		{
			$restoreTag = $Script:LastStandardPrimaryTab
			if (-not $restoreTag -or -not (Get-PrimaryTabItem -Tag $restoreTag))
			{
				foreach ($tab in $PrimaryTabs.Items)
				{
					if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
					{
						$restoreTag = [string]$tab.Tag
						break
					}
				}
			}

			if ($restoreTag)
			{
				Build-TabContent -PrimaryTab $restoreTag
			}
			return
		}

		if ($Script:CurrentPrimaryTab -and $Script:CurrentPrimaryTab -ne $Script:SearchResultsTabTag)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	}

