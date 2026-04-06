	# Capture functions into $Script: variables so WPF event handler delegates can resolve them.
	$Script:SetSearchInputStyleScript = ${function:Set-SearchInputStyle}
	$Script:SetSafeModeStateScript = ${function:Set-SafeModeState}
	$Script:SetAdvancedModeStateScript = ${function:Set-AdvancedModeState}
	$Script:SetGameModeStateScript = ${function:Set-GameModeState}
	$Script:SaveCurrentTabScrollOffsetScript = ${function:Save-CurrentTabScrollOffset}
	$Script:UpdateMainContentPanelWidthScript = ${function:Update-MainContentPanelWidth}
	$testGuiRunInProgressCapture = $Script:TestGuiRunInProgressScript

	$searchRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
	$searchRefreshTimer.Interval = [TimeSpan]::FromMilliseconds($Script:SearchRefreshDelayMs)
	$refreshSearchContentForTimer = $refreshSearchContent
	$null = Register-GuiEventHandler -Source $searchRefreshTimer -EventName 'Tick' -Handler ({
		$searchRefreshTimer.Stop()
		& $refreshSearchContentForTimer
	})
	$Script:SearchRefreshTimer = $searchRefreshTimer

	Set-SearchInputStyle
	Set-FilterControlStyle
	# Cache the icon content command once to avoid Get-Command on every filter click.
	$Script:HasLabeledIconContent = [bool](Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue)
	# Filter toggle button - shows/hides the collapsible filter options panel
	$null = Register-GuiEventHandler -Source $BtnFilterToggle -EventName 'Click' -Handler ({
		if ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
		else
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Collapsed
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25B8)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25B8)" }
			)
		}
	})
	$TxtSearch.Text = $Script:SearchText
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'GotKeyboardFocus' -Handler ({
		Invoke-CapturedFunction -Name 'Set-SearchInputStyle'
	})
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'LostKeyboardFocus' -Handler ({
		Invoke-CapturedFunction -Name 'Set-SearchInputStyle'
	})
	$null = Register-GuiEventHandler -Source $TxtSearch -EventName 'TextChanged' -Handler ({
		if (& $testGuiRunInProgressCapture) { return }
		$Script:SearchText = $TxtSearch.Text
		& $Script:SetSearchInputStyleScript
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
		$selectedRisk = if ($CmbRiskFilter.SelectedItem) { [string]$CmbRiskFilter.SelectedItem } else { 'All' }
		& $Script:GuiState.Set 'RiskFilter' $selectedRisk
		if ($selectedRisk -ne 'All' -and $FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $CmbCategoryFilter -EventName 'SelectionChanged' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		$selectedCat = if ($CmbCategoryFilter.SelectedItem) { [string]$CmbCategoryFilter.SelectedItem } else { 'All' }
		& $Script:GuiState.Set 'CategoryFilter' $selectedCat
		if ($selectedCat -ne 'All' -and $FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $ChkSelectedOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'SelectedOnlyFilter' $true
		if ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $ChkSelectedOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'SelectedOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkHighRiskOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'HighRiskOnlyFilter' $true
		if ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $ChkHighRiskOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'HighRiskOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkRestorableOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'RestorableOnlyFilter' $true
		if ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $ChkRestorableOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'RestorableOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkGamingOnly -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'GamingOnlyFilter' $true
		if ($FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Collapsed)
		{
			$FilterOptionsPanel.Visibility = [System.Windows.Visibility]::Visible
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$(Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters') $([char]0x25BE)" }
			)
		}
	})
	$null = Register-GuiEventHandler -Source $ChkGamingOnly -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:GuiState.Set 'GamingOnlyFilter' $false
	})
	$null = Register-GuiEventHandler -Source $ChkSafeMode -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:SetSafeModeStateScript -Enabled $true
	})
	$null = Register-GuiEventHandler -Source $ChkSafeMode -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:SetAdvancedModeStateScript -Enabled $true
	})
	$null = Register-GuiEventHandler -Source $ChkGameMode -EventName 'Checked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:SetGameModeStateScript -Enabled $true
	})
	$null = Register-GuiEventHandler -Source $ChkGameMode -EventName 'Unchecked' -Handler ({
		if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
		& $Script:SetGameModeStateScript -Enabled $false
	})
	$null = Register-GuiEventHandler -Source $BtnClearSearch -EventName 'Click' -Handler ({
		$TxtSearch.Text = ''
		[void]($TxtSearch.Focus())
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

