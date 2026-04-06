# Preset/scenario UI builder functions: button definitions, panels, filters, selection bars, and recommendation display

	function Register-GuiCommandButtonAction
	{
		param (
			[object]$Button,
			[string]$DebugContext,
			[string]$DebugMessage,
			[scriptblock]$Action,
			[object]$WriteGuiPresetDebugCommand
		)

		$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
		Register-GuiEventHandler -Source $Button -EventName 'Click' -Handler ({
			try
			{
				if ($WriteGuiPresetDebugCommand -and -not [string]::IsNullOrWhiteSpace($DebugMessage))
				{
					& $WriteGuiPresetDebugCommand -Context $DebugContext -Message $DebugMessage
				}
				& $Action
			}
			catch
			{
				if ($showGuiRuntimeFailureScript)
				{
					& $showGuiRuntimeFailureScript -Context $DebugContext -Exception $_.Exception -ShowDialog
				}
				else
				{
					Write-Warning "GUI event failed [$DebugContext]: $($_.Exception.Message)"
				}
			}
		}.GetNewClosure()) | Out-Null
	}

	function Get-TabPresetButtonDefinitions
	{
		param ([bool]$IsSafeUx)

		if ($IsSafeUx)
		{
			return @(
				[pscustomobject]@{
					Label = (New-PresetButtonContent -PrimaryText 'Quick Start' -SecondaryText 'Privacy essentials only')
					Variant = 'Secondary'
					PresetName = 'Minimal'
					ToolTip = 'Recommended for most users. Small, low-risk starting point for your first run.'
					Muted = $false
				}
				[pscustomobject]@{
					Label = (New-PresetButtonContent -PrimaryText 'Recommended' -SecondaryText 'Broader privacy + performance')
					Variant = 'Secondary'
					PresetName = 'Basic'
					ToolTip = 'Broader low-risk follow-up when you want more cleanup and privacy changes.'
					Muted = $false
				}
				[pscustomobject]@{
					Label = 'Balanced'
					Variant = 'Subtle'
					PresetName = 'Balanced'
					ToolTip = 'For experienced users. Turn off Safe Mode to use Balanced with full visibility.'
					Muted = $true
					Collapsed = $true
				}
				[pscustomobject]@{
					Label = 'Advanced'
					Variant = 'Subtle'
					PresetName = 'Advanced'
					ToolTip = 'Expert-only. Turn off Safe Mode and enable Expert Mode first.'
					Muted = $true
					Collapsed = $true
				}
			)
		}

		return @(
			[pscustomobject]@{
				Label = 'Minimal'
				Variant = 'Secondary'
				PresetName = 'Minimal'
				ToolTip = 'Small, low-risk starting point. Good when you want a very conservative baseline.'
				Muted = $false
			}
			[pscustomobject]@{
				Label = 'Basic'
				Variant = 'Secondary'
				PresetName = 'Basic'
				ToolTip = 'Recommended default for most users. Selects broadly safe, low-risk tweaks.'
				Muted = $false
			}
			[pscustomobject]@{
				Label = 'Balanced'
				Variant = 'Secondary'
				PresetName = 'Balanced'
				ToolTip = 'For enthusiasts who accept moderate tradeoffs. Includes broader tuning than Basic.'
				Muted = $false
			}
			[pscustomobject]@{
				Label = 'Advanced'
				Variant = 'Secondary'
				PresetName = 'Advanced'
				ToolTip = 'Expert preset for experienced users. High-risk changes may affect compatibility and recovery. Restore point recommended.'
				Muted = $false
			}
		)
	}

	function Get-ScenarioRecommendationLookup
	{
		$recommendationLookup = @{}
		if ($Script:EnvironmentRecommendationData -and $Script:EnvironmentRecommendationData.PSObject.Properties['Recommendations'])
		{
			foreach ($recommendation in @($Script:EnvironmentRecommendationData.Recommendations))
			{
				if ($recommendation -and -not [string]::IsNullOrWhiteSpace([string]$recommendation.Name))
				{
					$recommendationLookup[[string]$recommendation.Name] = $recommendation
				}
			}
		}

		return $recommendationLookup
	}

	function Sync-ActivePresetButtonChrome
	{
		$activePresetName = [string](Get-GuiActivePreset)
		$activeScenarios = if ($Script:ActiveScenarioNames -is [hashtable]) { $Script:ActiveScenarioNames } else { @{} }

		# Iterate ALL tabs' preset button refs so every tab's buttons stay in sync
		# (not just whichever tab was built last).
		$allPresetRefs = @(if ($Script:PresetButtonRefsByTab -is [hashtable]) { foreach ($tabRefs in $Script:PresetButtonRefsByTab.Values) { $tabRefs } })
		foreach ($presetRef in $allPresetRefs)
		{
			if (-not $presetRef -or -not $presetRef.Button) { continue }

			$defaultVariant = if ((Test-GuiObjectField -Object $presetRef -FieldName 'DefaultVariant') -and -not [string]::IsNullOrWhiteSpace([string]$presetRef.DefaultVariant))
			{
				[string]$presetRef.DefaultVariant
			}
			else
			{
				'Secondary'
			}
			$defaultMuted = ((Test-GuiObjectField -Object $presetRef -FieldName 'DefaultMuted') -and [bool]$presetRef.DefaultMuted)
			Set-ButtonChrome -Button $presetRef.Button -Variant $defaultVariant -Muted:([bool]$defaultMuted)

			if ([string]$presetRef.PresetName -eq $activePresetName)
			{
				Set-ButtonChrome -Button $presetRef.Button -Variant 'Selection'
			}
		}

		# Scenarios accumulate — multiple can be active simultaneously.
		$allScenarioRefs = @(if ($Script:ScenarioButtonRefsByTab -is [hashtable]) { foreach ($tabRefs in $Script:ScenarioButtonRefsByTab.Values) { $tabRefs } })
		foreach ($scenarioRef in $allScenarioRefs)
		{
			if (-not $scenarioRef -or -not $scenarioRef.Button) { continue }

			$defaultVariant = if ((Test-GuiObjectField -Object $scenarioRef -FieldName 'DefaultVariant') -and -not [string]::IsNullOrWhiteSpace([string]$scenarioRef.DefaultVariant))
			{
				[string]$scenarioRef.DefaultVariant
			}
			else
			{
				'Secondary'
			}
			Set-ButtonChrome -Button $scenarioRef.Button -Variant $defaultVariant

			if ($activeScenarios.Count -gt 0 -and $activeScenarios.ContainsKey([string]$scenarioRef.ScenarioName))
			{
				Set-ButtonChrome -Button $scenarioRef.Button -Variant 'Selection'
			}
		}
	}

	function New-TabPresetButtonsPanel
	{
		param ([object]$BuildContext)

		$presetBar = New-Object System.Windows.Controls.WrapPanel
		$presetBar.Orientation = 'Horizontal'
		$presetBar.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		if (-not ($Script:PresetButtonRefsByTab -is [hashtable])) { $Script:PresetButtonRefsByTab = @{} }
		$tabPresetRefs = [System.Collections.Generic.List[object]]::new()
		$Script:PresetButtonRefsByTab[[string]$BuildContext.PrimaryTab] = $tabPresetRefs
		foreach ($presetDefinition in @(Get-TabPresetButtonDefinitions -IsSafeUx:(Test-IsSafeModeUX)))
		{
			$button = New-PresetButton -Label $presetDefinition.Label -Variant ([string]$presetDefinition.Variant) -Muted:([bool]$presetDefinition.Muted)
			if (-not $button)
			{
				throw ("New-PresetButton returned null for preset '{0}'." -f [string]$presetDefinition.PresetName)
			}

			# Apply icon to preset button if available
			if ((Get-Command -Name 'Get-GuiPresetIconName' -CommandType Function -ErrorAction SilentlyContinue) -and (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue))
			{
				$presetIconName = Get-GuiPresetIconName -PresetName ([string]$presetDefinition.PresetName)
				if ($presetIconName -and ($presetDefinition.Label -is [string]))
				{
					Set-GuiButtonIconContent -Button $button -IconName $presetIconName -Text ([string]$presetDefinition.Label) -IconSize 14 -Gap 6 -TextFontSize 11
				}
			}

			$button.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
			$button.ToolTip = [string]$presetDefinition.ToolTip
			if ((Test-GuiObjectField -Object $presetDefinition -FieldName 'Collapsed') -and [bool]$presetDefinition.Collapsed)
			{
				$button.Visibility = [System.Windows.Visibility]::Collapsed
			}

			[void]($tabPresetRefs.Add([pscustomobject]@{
				Button = $button
				PresetName = [string]$presetDefinition.PresetName
				DefaultVariant = [string]$presetDefinition.Variant
				DefaultMuted = [bool]$presetDefinition.Muted
			}))

			# If this preset is the currently active one, highlight it immediately.
			if ([string]$presetDefinition.PresetName -eq (Get-GuiActivePreset))
			{
				Set-ButtonChrome -Button $button -Variant 'Selection'
			}

			$requestedPreset = [string]$presetDefinition.PresetName
			$debugContext = 'Build-TabContent/Preset/{0}' -f $requestedPreset
			Register-GuiCommandButtonAction -Button $button -DebugContext $debugContext -DebugMessage ("Preset button clicked. CurrentPrimaryTab='{0}', requestedPreset='{1}'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }), $requestedPreset) -WriteGuiPresetDebugCommand $BuildContext.WriteGuiPresetDebugCommand -Action ({
				& $BuildContext.SetGuiPresetSelectionCommand -PresetName $requestedPreset
			}.GetNewClosure())
			[void]($presetBar.Children.Add($button))
		}

		return $presetBar
	}

	function New-ScenarioProfileButtonsPanel
	{
		param (
			[object]$BuildContext,
			[hashtable]$ScenarioRecommendationLookup = @{}
		)

		$scenarioBar = New-Object System.Windows.Controls.WrapPanel
		$scenarioBar.Orientation = 'Horizontal'
		$scenarioBar.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		if (-not ($Script:ScenarioButtonRefsByTab -is [hashtable])) { $Script:ScenarioButtonRefsByTab = @{} }
		$tabScenarioRefs = [System.Collections.Generic.List[object]]::new()
		$Script:ScenarioButtonRefsByTab[[string]$BuildContext.PrimaryTab] = $tabScenarioRefs
		foreach ($scenarioDefinition in @(Get-ScenarioProfileDefinitions))
		{
			$scenarioName = [string]$scenarioDefinition.Name
			$isRecommended = ($ScenarioRecommendationLookup -and $ScenarioRecommendationLookup.ContainsKey($scenarioName))
			$defaultVariant = 'Secondary'
			$button = New-PresetButton -Label ([string]$scenarioDefinition.Label) -Variant $defaultVariant
			if (-not $button)
			{
				throw ("New-PresetButton returned null for scenario '{0}'." -f [string]$scenarioDefinition.Label)
			}

			$button.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
			$recommendationReason = if ($isRecommended) { [string]$ScenarioRecommendationLookup[$scenarioName].Reason } else { $null }
			$button.ToolTip = if ([string]::IsNullOrWhiteSpace([string]$recommendationReason))
			{
				[string]$scenarioDefinition.Summary
			}
			else
			{
				"{0}`n`nRecommended after scan: {1}" -f [string]$scenarioDefinition.Summary, $recommendationReason
			}

			[void]($tabScenarioRefs.Add([pscustomobject]@{
				Button = $button
				ScenarioName = $scenarioName
				DefaultVariant = $defaultVariant
			}))

			# If this scenario is currently active, highlight it immediately.
			if ($Script:ActiveScenarioNames -is [hashtable] -and $Script:ActiveScenarioNames.ContainsKey($scenarioName))
			{
				Set-ButtonChrome -Button $button -Variant 'Selection'
			}

			$requestedScenario = $scenarioName
			$debugContext = 'Build-TabContent/Scenario/{0}' -f $requestedScenario
			Register-GuiCommandButtonAction -Button $button -DebugContext $debugContext -DebugMessage ("Scenario button clicked. CurrentPrimaryTab='{0}', requestedScenario='{1}'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }), $requestedScenario) -WriteGuiPresetDebugCommand $BuildContext.WriteGuiPresetDebugCommand -Action ({
				& $BuildContext.SetGuiScenarioProfileSelectionCommand -ProfileName $requestedScenario
			}.GetNewClosure())
			[void]($scenarioBar.Children.Add($button))
		}

		return $scenarioBar
	}

	function New-ScenarioRecommendationPanel
	{
		param ([hashtable]$ScenarioRecommendationLookup = @{})

		if (-not $ScenarioRecommendationLookup -or $ScenarioRecommendationLookup.Count -eq 0)
		{
			return $null
		}

		$scenarioRecommendationItems = @(
			foreach ($recommendation in @($Script:EnvironmentRecommendationData.Recommendations))
			{
				if ($null -eq $recommendation) { continue }
				$name = [string]$recommendation.Name
				if ([string]::IsNullOrWhiteSpace($name) -or -not $ScenarioRecommendationLookup.ContainsKey($name)) { continue }

				[pscustomobject]@{
					Label = $name
					Tone = 'Success'
					ToolTip = [string]$recommendation.Reason
				}
			}
		)

		if (-not $scenarioRecommendationItems -or $scenarioRecommendationItems.Count -eq 0)
		{
			return $null
		}

		$scenarioRecommendationPanel = GUICommon\New-DialogMetadataPillPanel -Theme $Script:CurrentTheme -Items $scenarioRecommendationItems
		if ($scenarioRecommendationPanel)
		{
			$scenarioRecommendationPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		}

		return $scenarioRecommendationPanel
	}

	function New-SystemScanActionRow
	{
		param ([object]$BuildContext)

		$actionRow = New-Object System.Windows.Controls.WrapPanel
		$actionRow.Orientation = 'Horizontal'
		$actionRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)

		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$buttonLabel = & $getUxLocalizedStringCapture -Key 'GuiSystemScanButton' -Fallback 'System Scan'
		$systemScanButton = New-PresetButton -Label $buttonLabel -Variant 'Secondary'
		if (-not $systemScanButton)
		{
			throw ("New-PresetButton returned null for {0}." -f $buttonLabel)
		}
		$systemScanButton.ToolTip = 'Scans your system and recommends tweaks based on detected configuration.'
		$scanCheckBox = $ChkScan
		Register-GuiCommandButtonAction -Button $systemScanButton -DebugContext 'Build-TabContent/Preset/SystemScan' -DebugMessage ("Preset button clicked. CurrentPrimaryTab='{0}', enabling system scan." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' })) -WriteGuiPresetDebugCommand $BuildContext.WriteGuiPresetDebugCommand -Action ({
			$scanCheckBox.IsChecked = $true
			$Script:PresetStatusMessage = & $getUxLocalizedStringCapture -Key 'GuiSystemScanEnabled' -Fallback 'System scan enabled.'
			if ($Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
			{
				$Script:PresetStatusBadge.Child.Text = $Script:PresetStatusMessage
			}
		}.GetNewClosure())
		[void]($actionRow.Children.Add($systemScanButton))

		return $actionRow
	}

	function New-TabPresetPanel
	{
		param ([object]$BuildContext)

		$presetPanel = New-Object System.Windows.Controls.Border
		$presetPanel.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBg)
		$presetPanel.BorderBrush = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBorder)
		$presetPanel.BorderThickness = [System.Windows.Thickness]::new(1.5)
		$presetPanel.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.BorderRadiusLarge)
		$presetPanel.Margin = [System.Windows.Thickness]::new(8, 14, 8, 10)
		$presetPanel.Padding = [System.Windows.Thickness]::new(18, 16, 18, 14)
		# Subtle drop shadow for elevation
		$presetPanelShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
		$presetPanelShadow.BlurRadius = 12
		$presetPanelShadow.ShadowDepth = 2
		$presetPanelShadow.Opacity = 0.25
		$presetPanelShadow.Color = [System.Windows.Media.Colors]::Black
		if ($presetPanelShadow.CanFreeze) { $presetPanelShadow.Freeze() }
		$presetPanel.Effect = $presetPanelShadow

		$presetPanelStack = New-Object System.Windows.Controls.StackPanel
		$presetPanelStack.Orientation = 'Vertical'

		$presetHeader = New-Object System.Windows.Controls.TextBlock
		$presetHeader.Text = Get-UxLocalizedString -Key 'GuiPresetPanelHeading' -Fallback 'Recommended Selections'
		$presetHeader.FontSize = $Script:GuiLayout.FontSizeSection
		$presetHeader.FontWeight = [System.Windows.FontWeights]::Bold
		$presetHeader.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		[void]($presetPanelStack.Children.Add($presetHeader))

		$presetSubheading = New-Object System.Windows.Controls.TextBlock
		$presetSubheading.Text = Get-UxPresetEmphasisText
		$presetSubheading.FontSize = $Script:GuiLayout.FontSizeLabel
		$presetSubheading.TextWrapping = 'Wrap'
		$presetSubheading.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$presetSubheading.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($presetPanelStack.Children.Add($presetSubheading))
		[void]($presetPanelStack.Children.Add((New-TabPresetButtonsPanel -BuildContext $BuildContext)))

		$presetSummary = New-Object System.Windows.Controls.TextBlock
		$presetSummary.Text = Get-UxPresetSummaryText
		$presetSummary.TextWrapping = 'Wrap'
		$presetSummary.FontSize = $Script:GuiLayout.FontSizeSmall
		$presetSummary.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		$presetSummary.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($presetPanelStack.Children.Add($presetSummary))

		$scenarioHeader = New-Object System.Windows.Controls.TextBlock
		$scenarioHeader.Text = Get-UxScenarioHeading
		$scenarioHeader.FontSize = $Script:GuiLayout.FontSizeSubheading
		$scenarioHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
		$scenarioHeader.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		$scenarioHeader.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		[void]($presetPanelStack.Children.Add($scenarioHeader))

		$scenarioSubheading = New-Object System.Windows.Controls.TextBlock
		$scenarioSubheading.Text = 'Focused bundles stay separate from the main preset ladder. Run System Scan to surface environment-based recommendations. Those recommendations stay advisory and never change selections automatically.'
		$scenarioSubheading.FontSize = $Script:GuiLayout.FontSizeSmall
		$scenarioSubheading.TextWrapping = 'Wrap'
		$scenarioSubheading.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$scenarioSubheading.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($presetPanelStack.Children.Add($scenarioSubheading))

		$scenarioRecommendationLookup = Get-ScenarioRecommendationLookup
		[void]($presetPanelStack.Children.Add((New-ScenarioProfileButtonsPanel -BuildContext $BuildContext -ScenarioRecommendationLookup $scenarioRecommendationLookup)))
		$scenarioRecommendationPanel = New-ScenarioRecommendationPanel -ScenarioRecommendationLookup $scenarioRecommendationLookup
		if ($scenarioRecommendationPanel)
		{
			[void]($presetPanelStack.Children.Add($scenarioRecommendationPanel))
		}

		[void]($presetPanelStack.Children.Add((New-SystemScanActionRow -BuildContext $BuildContext)))
		$Script:PresetStatusBadge = New-StatusPill -Text $Script:PresetStatusMessage
		if ($Script:PresetStatusBadge)
		{
			[void]($presetPanelStack.Children.Add($Script:PresetStatusBadge))
		}

		# Small progress bar shown only while a preset is being applied.
		$Script:PresetProgressBar = New-Object System.Windows.Controls.ProgressBar
		$Script:PresetProgressBar.Height = 3
		$Script:PresetProgressBar.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$Script:PresetProgressBar.Minimum = 0
		$Script:PresetProgressBar.Maximum = 100
		$Script:PresetProgressBar.Value = 0
		$Script:PresetProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
		$Script:PresetProgressBar.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBorder)
		$Script:PresetProgressBar.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.AccentBlue)
		[void]($presetPanelStack.Children.Add($Script:PresetProgressBar))

		$reassuranceNote = New-Object System.Windows.Controls.TextBlock
		$reassuranceNote.Text = 'No changes are made until you click Run Tweaks. You can preview everything first.'
		$reassuranceNote.FontSize = $Script:GuiLayout.FontSizeSmall
		$reassuranceNote.TextWrapping = 'Wrap'
		$reassuranceNote.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		$reassuranceNote.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$reassuranceNote.Opacity = 0.7
		[void]($presetPanelStack.Children.Add($reassuranceNote))

		$presetPanel.Child = $presetPanelStack
		return $presetPanel
	}

	function Add-TabContentLeadPanel
	{
		param ([object]$BuildContext)

		if ($BuildContext.IsSearchResultsTab)
		{
			try
			{
				[void]($BuildContext.MainPanel.Children.Add((New-SearchResultsSummary -Query $BuildContext.SearchQuery -MatchCount $BuildContext.MatchCount)))
				return
			}
			catch
			{
				throw "Build-TabContent/SearchResultsSummary for tab '$($BuildContext.PrimaryTab)' failed: $($_.Exception.Message)"
			}
		}

		if ($BuildContext.PrimaryTab -eq 'Gaming')
		{
			try
			{
				$gameModeBar = New-Object System.Windows.Controls.Border
				$gameModeBar.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.HeaderBg)
				$gameModeBar.BorderBrush = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.AccentBlue)
				$gameModeBar.BorderThickness = [System.Windows.Thickness]::new(1.5)
				$gameModeBar.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
				$gameModeBar.Margin = [System.Windows.Thickness]::new(8, 8, 8, 6)
				$gameModeBar.Padding = [System.Windows.Thickness]::new(16, 10, 16, 10)
				$gameModeShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
				$gameModeShadow.BlurRadius = 8
				$gameModeShadow.ShadowDepth = 1
				$gameModeShadow.Opacity = 0.2
				$gameModeShadow.Color = [System.Windows.Media.Colors]::Black
				if ($gameModeShadow.CanFreeze) { $gameModeShadow.Freeze() }
				$gameModeBar.Effect = $gameModeShadow

				$gameModeBarGrid = New-Object System.Windows.Controls.Grid
				$col0 = New-Object System.Windows.Controls.ColumnDefinition
				$col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				$col1 = New-Object System.Windows.Controls.ColumnDefinition
				$col1.Width = [System.Windows.GridLength]::Auto
				[void]$gameModeBarGrid.ColumnDefinitions.Add($col0)
				[void]$gameModeBarGrid.ColumnDefinitions.Add($col1)

				$gameModeLabel = New-Object System.Windows.Controls.TextBlock
				$gameModeLabel.Text = 'GAME MODE'
				$gameModeLabel.FontSize = $Script:GuiLayout.FontSizeSubheading
				$gameModeLabel.FontWeight = [System.Windows.FontWeights]::Bold
				$gameModeLabel.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.AccentBlue)
				$gameModeLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				[System.Windows.Controls.Grid]::SetColumn($gameModeLabel, 0)
				[void]$gameModeBarGrid.Children.Add($gameModeLabel)

				$gameModeToggle = New-Object System.Windows.Controls.CheckBox
				$gameModeToggle.Content = if ([bool]$Script:GameMode) { 'On' } else { 'Off' }
				$gameModeToggle.IsChecked = [bool]$Script:GameMode
				$gameModeToggle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				Set-HeaderToggleStyle -CheckBox $gameModeToggle -Palette Mode
				[System.Windows.Controls.Grid]::SetColumn($gameModeToggle, 1)
				[void]$gameModeBarGrid.Children.Add($gameModeToggle)

				$setGameModeCapture = $Script:SetGameModeStateScript
				$testGuiRunInProgressCapture = $Script:TestGuiRunInProgressScript
				$gameModeToggle.Add_Checked({
					if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
					& $setGameModeCapture -Enabled $true
				}.GetNewClosure())
				$gameModeToggle.Add_Unchecked({
					if ($Script:FilterUiUpdating -or (& $testGuiRunInProgressCapture)) { return }
					& $setGameModeCapture -Enabled $false
				}.GetNewClosure())

				$gameModeBar.Child = $gameModeBarGrid
				[void]($BuildContext.MainPanel.Children.Add($gameModeBar))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/GameModeToggle' -Message ("Game Mode toggle bar failed for Gaming tab: {0}" -f $_.Exception.Message)
			}

			# "Reset Gaming Tweaks" button — restores Gaming-tab entries to Windows defaults
			# Placed before the Game Mode landing panel so it stays visible regardless
			# of whether Game Mode is on or off.
			try
			{
				$resetGamingButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiResetGamingTweaks' -Fallback 'Reset Gaming Tweaks') -Variant 'DangerSubtle' -Compact
				$resetGamingButton.Margin = [System.Windows.Thickness]::new(8, 4, 8, 4)
				$resetGamingButton.FontSize = $Script:GuiLayout.FontSizeSmall
				$resetGamingButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
				$resetGamingButton.ToolTip = 'Restore all Gaming tab tweaks to Windows defaults'

				$getWindowsDefaultRunListCapture = if ($Script:GetWindowsDefaultRunListScript) { $Script:GetWindowsDefaultRunListScript } else { ${function:Get-WindowsDefaultRunList} }
				$startGuiExecutionRunCapture = if ($Script:StartGuiExecutionRunScript) { $Script:StartGuiExecutionRunScript } else { ${function:Start-GuiExecutionRun} }
				$showThemedDialogCapture = if ($Script:ShowThemedDialogScript) { $Script:ShowThemedDialogScript } else { ${function:Show-ThemedDialog} }
				$null = Register-GuiEventHandler -Source $resetGamingButton -EventName 'Click' -Handler ({
					$confirmResult = & $showThemedDialogCapture -Title 'Reset Gaming Tweaks' `
						-Message 'This will restore all Gaming tab tweaks to their Windows default state. Your other settings are not affected.' `
						-Buttons @('Reset Gaming', 'Cancel') `
						-DestructiveButton 'Reset Gaming'
					if ($confirmResult -ne 'Reset Gaming') { return }

					$allDefaults = @(& $getWindowsDefaultRunListCapture)
					$gamingDefaults = @($allDefaults | Where-Object { [string]$_.Category -eq 'Gaming' })
					if ($gamingDefaults.Count -eq 0)
					{
						& $showThemedDialogCapture -Title 'Reset Gaming Tweaks' `
							-Message 'No restorable Gaming tweaks found.' `
							-Buttons @('OK') -AccentButton 'OK'
						return
					}
					& $startGuiExecutionRunCapture -TweakList $gamingDefaults -Mode 'Defaults' -ExecutionTitle 'Resetting Gaming Tweaks to Windows Defaults'
				}.GetNewClosure())
				[void]($BuildContext.MainPanel.Children.Add($resetGamingButton))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/ResetGamingButton' -Message ("Reset Gaming button failed: {0}" -f $_.Exception.Message)
			}

			if ([bool]$Script:GameMode)
			{
				try
				{
					[void]($BuildContext.MainPanel.Children.Add((New-GameModeLandingPanel)))
					return
				}
				catch
				{
					throw "Build-TabContent/GameModeLandingPanel for tab '$($BuildContext.PrimaryTab)' failed: $($_.Exception.Message)"
				}
			}
		}

		try
		{
			[void]($BuildContext.MainPanel.Children.Add((New-TabPresetPanel -BuildContext $BuildContext)))
		}
		catch
		{
			throw "Build-TabContent/PresetPanel for tab '$($BuildContext.PrimaryTab)' failed: $($_.Exception.Message)"
		}
	}

	function Get-ActiveTabFilterItems
	{
		param ([object]$BuildContext)

		try
		{
			return @(Get-CurrentFilterSummaryItems -SearchQuery $BuildContext.SearchQuery)
		}
		catch
		{
			Write-GuiRuntimeWarning -Context 'Build-TabContent/FilterSummary' -Message ("Filter summary generation failed for tab '{0}': {1}" -f $BuildContext.PrimaryTab, $_.Exception.Message)
			return @()
		}
	}

	function New-ActiveFiltersBanner
	{
		param (
			[object]$BuildContext,
			[object[]]$ActiveFilterItems
		)

		$filterBanner = New-Object System.Windows.Controls.Border
		$filterBanner.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBg)
		$filterBanner.BorderBrush = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBorder)
		$filterBanner.BorderThickness = [System.Windows.Thickness]::new(1)
		$filterBanner.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$filterBanner.Margin = [System.Windows.Thickness]::new(8, 6, 8, 8)
		$filterBanner.Padding = [System.Windows.Thickness]::new(14, 10, 14, 10)

		$filterStack = New-Object System.Windows.Controls.StackPanel
		$filterStack.Orientation = 'Vertical'

		$filterTitle = New-Object System.Windows.Controls.TextBlock
		$filterTitle.Text = Get-UxLocalizedString -Key 'GuiActiveFiltersHeading' -Fallback 'Active filters'
		$filterTitle.FontSize = $Script:GuiLayout.FontSizeLabel
		$filterTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
		$filterTitle.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		[void]($filterStack.Children.Add($filterTitle))

		$filterPills = GUICommon\New-DialogMetadataPillPanel -Theme $Script:CurrentTheme -Items $ActiveFilterItems
		if ($filterPills)
		{
			$filterPills.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			[void]($filterStack.Children.Add($filterPills))
		}

		$filterBanner.Child = $filterStack
		return $filterBanner
	}

	function New-EmptyTabStateCard
	{
		param (
			[object]$BuildContext,
			[bool]$HasActiveFilters
		)

		$emptyState = New-Object System.Windows.Controls.Border
		$emptyState.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBg)
		$emptyState.BorderBrush = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBorder)
		$emptyState.BorderThickness = [System.Windows.Thickness]::new(1)
		$emptyState.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$emptyState.Margin = [System.Windows.Thickness]::new(8, 12, 8, 8)
		$emptyState.Padding = [System.Windows.Thickness]::new(20, 18, 20, 18)

		$emptyText = New-Object System.Windows.Controls.TextBlock
		$emptyText.Text = Get-UxEmptyTabStateMessage -IsSearchResultsTab:$BuildContext.IsSearchResultsTab -SearchQuery $BuildContext.SearchQuery -HasActiveFilters:$HasActiveFilters
		$emptyText.TextWrapping = 'Wrap'
		$emptyText.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$emptyState.Child = $emptyText
		return $emptyState
	}

	function Get-TabContentIndexArray
	{
		param ([System.Collections.IDictionary]$CategoryTweaks)

		$allTabIndexesList = [System.Collections.Generic.List[int]]::new()
		foreach ($subKey in $CategoryTweaks.Keys)
		{
			$allTabIndexesList.AddRange([System.Collections.Generic.List[int]]$CategoryTweaks[$subKey])
		}

		return [int[]]$allTabIndexesList.ToArray()
	}

	function New-TabSelectionBar
	{
		param ([int[]]$AllTabIndexes)

		$selectionBar = New-Object System.Windows.Controls.WrapPanel
		$selectionBar.Orientation = 'Horizontal'
		$selectionBar.Margin = [System.Windows.Thickness]::new(8, 8, 8, 2)

		$selectAllButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All') -Variant 'Subtle' -Compact
		$controlsRefForSelect = $Script:Controls
		$capturedSelectIndexes = [int[]]$AllTabIndexes
		Register-GuiEventHandler -Source $selectAllButton -EventName 'Click' -Handler ({
			foreach ($index in $capturedSelectIndexes)
			{
				$control = $controlsRefForSelect[$index]
				if ($control -and $control.IsEnabled -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
				{
					$control.IsChecked = $true
				}
			}
		}.GetNewClosure()) | Out-Null
		[void]($selectionBar.Children.Add($selectAllButton))

		$unselectAllButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiUnselectAll' -Fallback 'Unselect All') -Variant 'Subtle' -Compact
		$controlsRefForUnselect = $Script:Controls
		$tweakManifestRefForUnselect = $Script:TweakManifest
		$capturedUnselectIndexes = [int[]]$AllTabIndexes
		$removeExplicitSelectionDefinition = ${function:Remove-GuiExplicitSelectionDefinition}
		Register-GuiEventHandler -Source $unselectAllButton -EventName 'Click' -Handler ({
			foreach ($index in $capturedUnselectIndexes)
			{
				$manifestEntry = $null
				if ($tweakManifestRefForUnselect -and $index -ge 0 -and $index -lt $tweakManifestRefForUnselect.Count)
				{
					$manifestEntry = $tweakManifestRefForUnselect[$index]
				}
				if ($manifestEntry -and -not [string]::IsNullOrWhiteSpace([string]$manifestEntry.Function))
				{
					& $removeExplicitSelectionDefinition -FunctionName ([string]$manifestEntry.Function)
				}
				$control = $controlsRefForUnselect[$index]
				if ($control -and $control.IsEnabled -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
				{
					$control.IsChecked = $false
				}
				elseif ($control -and $control.IsEnabled -and (Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
				{
					[int]$clearIndex = -1
					$control.SelectedIndex = $clearIndex
				}
			}
		}.GetNewClosure()) | Out-Null
		[void]($selectionBar.Children.Add($unselectAllButton))

		return $selectionBar
	}

