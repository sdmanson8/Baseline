# Preset/scenario UI builder functions: button definitions, panels, filters, selection bars, and recommendation display

	<#
	    .SYNOPSIS
	#>

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
					Write-Warning "GUI event failed: $DebugContext - $($_.Exception.Message)"
				}
			}
		}.GetNewClosure()) | Out-Null
	}

	<#
	    .SYNOPSIS
	#>

	function Get-PresetButtonLabel
	{
		param (
			[string]$PresetName
		)

		switch ([string]$PresetName)
		{
			'Minimal' { Get-UxLocalizedString -Key 'GuiChoiceMinimal' -Fallback 'Minimal' }
			'Basic' { Get-UxLocalizedString -Key 'GuiChoiceBasic' -Fallback 'Basic' }
			'Balanced' { Get-UxLocalizedString -Key 'GuiChoiceBalanced' -Fallback 'Balanced' }
			'Advanced' { Get-UxLocalizedString -Key 'GuiChoiceAdvanced' -Fallback 'Advanced' }
			default { [string]$PresetName }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-PresetButtonTooltip
	{
		param (
			[string]$PresetName,
			[bool]$IsSafeUx
		)

		switch ([string]$PresetName)
		{
			'Minimal' { Get-UxLocalizedString -Key 'GuiPresetMinimalTooltip' -Fallback 'Small, low-risk starting point. Good when you want a very conservative baseline.' }
			'Basic' { Get-UxLocalizedString -Key 'GuiPresetBasicTooltip' -Fallback 'Recommended default for most users. Selects broadly safe, low-risk tweaks.' }
			'Balanced'
			{
				if ($IsSafeUx)
				{
					Get-UxLocalizedString -Key 'GuiPresetBalancedSafeTooltip' -Fallback 'For experienced users. Turn off Safe Mode to use Balanced with full visibility.'
				}
				else
				{
					Get-UxLocalizedString -Key 'GuiPresetBalancedTooltip' -Fallback 'For enthusiasts who accept moderate tradeoffs. Includes broader tuning than Basic.'
				}
			}
			'Advanced'
			{
				if ($IsSafeUx)
				{
					Get-UxLocalizedString -Key 'GuiPresetAdvancedSafeTooltip' -Fallback 'Expert-only. Turn off Safe Mode and enable Expert Mode first.'
				}
				else
				{
					Get-UxLocalizedString -Key 'GuiPresetAdvancedTooltip' -Fallback 'Expert preset for experienced users. High-risk changes may affect compatibility and recovery. Restore point recommended.'
				}
			}
			default { [string]$PresetName }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Test-ShouldShowQuickStartPresetButton
	{
		param (
			[string]$PrimaryTab
		)

		$normalizedPrimaryTab = if ([string]::IsNullOrWhiteSpace([string]$PrimaryTab)) { '' } else { [string]$PrimaryTab.Trim() }
		return [string]::Equals($normalizedPrimaryTab, 'Initial Setup', [System.StringComparison]::OrdinalIgnoreCase)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-TabPresetButtonDefinitions
	{
		param (
			[bool]$IsSafeUx,
			[string]$PrimaryTab = $null
		)

		if ($IsSafeUx)
		{
			$definitions = [System.Collections.Generic.List[object]]::new()
			if (Test-ShouldShowQuickStartPresetButton -PrimaryTab $PrimaryTab)
			{
				[void]$definitions.Add([pscustomobject]@{
					Label = (New-PresetButtonContent -PrimaryText (Get-UxLocalizedString -Key 'GuiPresetQuickStart' -Fallback 'Quick Start') -SecondaryText (Get-UxLocalizedString -Key 'GuiPresetQuickStartDesc' -Fallback 'Privacy essentials only'))
					Variant = 'Secondary'
					PresetName = 'Minimal'
					ToolTip = (Get-UxLocalizedString -Key 'GuiPresetQuickStartDesc' -Fallback 'Privacy essentials only')
					Muted = $false
				})
			}
			[void]$definitions.Add([pscustomobject]@{
					Label = (New-PresetButtonContent -PrimaryText (Get-UxLocalizedString -Key 'GuiPresetRecommended' -Fallback 'Recommended') -SecondaryText (Get-UxLocalizedString -Key 'GuiPresetRecommendedDesc' -Fallback 'Broader privacy + performance'))
					Variant = 'Secondary'
					PresetName = 'Basic'
					ToolTip = (Get-UxLocalizedString -Key 'GuiPresetRecommendedDesc' -Fallback 'Broader privacy + performance')
					Muted = $false
			})
			[void]$definitions.Add([pscustomobject]@{
					Label = (Get-PresetButtonLabel -PresetName 'Balanced')
					Variant = 'Subtle'
					PresetName = 'Balanced'
					ToolTip = (Get-PresetButtonTooltip -PresetName 'Balanced' -IsSafeUx:$true)
					Muted = $true
					Collapsed = $true
			})
			[void]$definitions.Add([pscustomobject]@{
					Label = (Get-PresetButtonLabel -PresetName 'Advanced')
					Variant = 'Subtle'
					PresetName = 'Advanced'
					ToolTip = (Get-PresetButtonTooltip -PresetName 'Advanced' -IsSafeUx:$true)
					Muted = $true
					Collapsed = $true
			})
			return $definitions.ToArray()
		}

		return @(
			[pscustomobject]@{
				Label = (Get-PresetButtonLabel -PresetName 'Minimal')
				Variant = 'Secondary'
				PresetName = 'Minimal'
				ToolTip = (Get-PresetButtonTooltip -PresetName 'Minimal' -IsSafeUx:$false)
				Muted = $false
			}
			[pscustomobject]@{
				Label = (Get-PresetButtonLabel -PresetName 'Basic')
				Variant = 'Secondary'
				PresetName = 'Basic'
				ToolTip = (Get-PresetButtonTooltip -PresetName 'Basic' -IsSafeUx:$false)
				Muted = $false
			}
			[pscustomobject]@{
				Label = (Get-PresetButtonLabel -PresetName 'Balanced')
				Variant = 'Secondary'
				PresetName = 'Balanced'
				ToolTip = (Get-PresetButtonTooltip -PresetName 'Balanced' -IsSafeUx:$false)
				Muted = $false
			}
			[pscustomobject]@{
				Label = (Get-PresetButtonLabel -PresetName 'Advanced')
				Variant = 'Secondary'
				PresetName = 'Advanced'
				ToolTip = (Get-PresetButtonTooltip -PresetName 'Advanced' -IsSafeUx:$false)
				Muted = $false
			}
		)
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function Initialize-GuiRecommendationDisclosureState
	{
		if (-not ($Script:RecommendedSelectionsCollapsedByScope -is [System.Collections.IDictionary]))
		{
			$Script:RecommendedSelectionsCollapsedByScope = @{}
		}
		if (-not ($Script:RecommendationDisclosureRefsByKey -is [System.Collections.IDictionary]))
		{
			$Script:RecommendationDisclosureRefsByKey = @{}
		}
		if (-not ($Script:RecommendationCompactStripRefsByKey -is [System.Collections.IDictionary]))
		{
			$Script:RecommendationCompactStripRefsByKey = @{}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Test-GuiRecommendationHasManualCollapseState
	{
		param ([string]$Scope)

		Initialize-GuiRecommendationDisclosureState
		if ([string]::IsNullOrWhiteSpace([string]$Scope)) { return $false }
		return $Script:RecommendedSelectionsCollapsedByScope.Contains([string]$Scope)
	}

	<#
	    .SYNOPSIS
	#>

	function Test-GuiRecommendationHasSelection
	{
		param ([string]$Scope)

		if ([string]$Scope -eq 'GamingProfiles')
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { return $true }
			return ($Script:GameModePlan -and @($Script:GameModePlan).Count -gt 0)
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:ActivePresetName)) { return $true }
		if ($Script:ActiveScenarioNames -is [System.Collections.IDictionary])
		{
			foreach ($scenarioEntry in $Script:ActiveScenarioNames.GetEnumerator())
			{
				if ([bool]$scenarioEntry.Value) { return $true }
			}
		}
		if ($Script:ExplicitPresetSelections -is [System.Collections.IDictionary] -and $Script:ExplicitPresetSelections.Count -gt 0) { return $true }

		foreach ($control in @($Script:Controls))
		{
			if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked') -and [bool]$control.IsChecked)
			{
				return $true
			}
		}

		return $false
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationDefaultCollapsedState
	{
		param ([string]$Scope)

		if (Test-IsSafeModeUX) { return $false }
		if (-not (Test-GuiRecommendationHasSelection -Scope $Scope)) { return $false }
		if (Test-IsExpertModeUX) { return $true }
		return $true
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationCollapsedState
	{
		param ([string]$Scope)

		Initialize-GuiRecommendationDisclosureState
		if ((Test-GuiRecommendationHasManualCollapseState -Scope $Scope))
		{
			return [bool]$Script:RecommendedSelectionsCollapsedByScope[[string]$Scope]
		}

		return (Get-GuiRecommendationDefaultCollapsedState -Scope $Scope)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationProfileLabel
	{
		param (
			[string]$ProfileName,
			[string]$PrimaryTab = $null
		)

		if ([string]::IsNullOrWhiteSpace([string]$ProfileName)) { return $null }
		if ((Test-IsSafeModeUX) -and [string]$PrimaryTab -eq 'Initial Setup')
		{
			switch ([string]$ProfileName)
			{
				'Minimal' { return (Get-UxLocalizedString -Key 'GuiPresetQuickStart' -Fallback 'Quick Start') }
				'Basic' { return (Get-UxLocalizedString -Key 'GuiPresetRecommended' -Fallback 'Recommended') }
			}
		}
		if (Get-Command -Name 'Get-UxPresetDisplayName' -CommandType Function -ErrorAction SilentlyContinue)
		{
			return (Get-UxPresetDisplayName -PresetName ([string]$ProfileName))
		}
		return (Get-PresetButtonLabel -PresetName ([string]$ProfileName))
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationScenarioLabel
	{
		param ([string]$ScenarioName)

		if ([string]::IsNullOrWhiteSpace([string]$ScenarioName)) { return $null }
		foreach ($scenarioDefinition in @(Get-ScenarioProfileDefinitions))
		{
			if ([string]$scenarioDefinition.Name -eq [string]$ScenarioName)
			{
				return (Get-UxLocalizedString -Key "GuiScenarioLabel$ScenarioName" -Fallback ([string]$scenarioDefinition.Label))
			}
		}
		return [string]$ScenarioName
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiGamingProfileLabel
	{
		param ([string]$ProfileName)

		if ([string]::IsNullOrWhiteSpace([string]$ProfileName)) { return $null }
		foreach ($profileDefinition in @(Get-GameModeProfileDefinitions))
		{
			if ([string]$profileDefinition.Name -ne [string]$ProfileName) { continue }
			$profileLocKeyBase = switch ([string]$profileDefinition.Name)
			{
				'Casual' { 'GuiProfileCasualGaming' }
				'Competitive' { 'GuiProfileCompetitiveGaming' }
				'Streaming' { 'GuiProfileStreamingContent' }
				'Troubleshooting' { 'GuiProfileTroubleshooting' }
				default { $null }
			}
			if ($profileLocKeyBase)
			{
				return (Get-UxLocalizedString -Key $profileLocKeyBase -Fallback ([string]$profileDefinition.Label))
			}
			return [string]$profileDefinition.Label
		}

		return [string]$ProfileName
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationSelectedSummaryText
	{
		param (
			[string]$Scope,
			[string]$PrimaryTab = $null
		)

		if ([string]$Scope -eq 'GamingProfiles')
		{
			$profileLabel = Get-GuiGamingProfileLabel -ProfileName ([string]$Script:GameModeProfile)
			if (-not [string]::IsNullOrWhiteSpace([string]$profileLabel))
			{
				return (Get-UxLocalizedString -Key 'GuiRecommendationSelectedSuffix' -Fallback '{0} selected' -FormatArgs @($profileLabel))
			}
			return $null
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:ActivePresetName))
		{
			$presetLabel = Get-GuiRecommendationProfileLabel -ProfileName ([string]$Script:ActivePresetName) -PrimaryTab $PrimaryTab
			if (-not [string]::IsNullOrWhiteSpace([string]$presetLabel))
			{
				return (Get-UxLocalizedString -Key 'GuiRecommendationSelectedSuffix' -Fallback '{0} selected' -FormatArgs @($presetLabel))
			}
		}

		$activeScenarioLabels = @(
			if ($Script:ActiveScenarioNames -is [System.Collections.IDictionary])
			{
				$Script:ActiveScenarioNames.GetEnumerator() |
					Where-Object { [bool]$_.Value -and -not [string]::IsNullOrWhiteSpace([string]$_.Key) } |
					Sort-Object Key |
					ForEach-Object { Get-GuiRecommendationScenarioLabel -ScenarioName ([string]$_.Key) }
			}
		) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

		if ($activeScenarioLabels.Count -gt 0)
		{
			$scenarioText = $activeScenarioLabels -join ' + '
			return (Get-UxLocalizedString -Key 'GuiRecommendationSelectedSuffix' -Fallback '{0} selected' -FormatArgs @($scenarioText))
		}

		return $null
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationDisclosureHeaderText
	{
		param (
			[string]$Scope,
			[string]$Title,
			[string]$PrimaryTab = $null,
			[bool]$Collapsed
		)

		$prefix = if ($Collapsed) { [string][char]0x25B6 } else { [string][char]0x25BC }
		$summary = Get-GuiRecommendationSelectedSummaryText -Scope $Scope -PrimaryTab $PrimaryTab
		if (-not [string]::IsNullOrWhiteSpace([string]$summary))
		{
			return ('{0} {1} ({2})' -f $prefix, $Title, $summary)
		}

		return ('{0} {1}' -f $prefix, $Title)
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiRecommendationDisclosureHeaders
	{
		Initialize-GuiRecommendationDisclosureState
		foreach ($disclosureRef in @($Script:RecommendationDisclosureRefsByKey.Values))
		{
			if (-not $disclosureRef -or -not $disclosureRef.HeaderTextBlock) { continue }
			$collapsed = Get-GuiRecommendationCollapsedState -Scope ([string]$disclosureRef.Scope)
			$headerText = Get-GuiRecommendationDisclosureHeaderText -Scope ([string]$disclosureRef.Scope) -Title ([string]$disclosureRef.Title) -PrimaryTab ([string]$disclosureRef.PrimaryTab) -Collapsed:$collapsed
			$disclosureRef.HeaderTextBlock.Text = $headerText
			if ($disclosureRef.HeaderButton)
			{
				[System.Windows.Automation.AutomationProperties]::SetName($disclosureRef.HeaderButton, $headerText)
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiRecommendationDisclosureVisualState
	{
		param (
			[object]$DisclosureRef,
			[bool]$Collapsed,
			[switch]$Animate
		)

		if (-not $DisclosureRef -or -not $DisclosureRef.BodyPanel) { return }
		$bodyPanel = $DisclosureRef.BodyPanel
		$scaleTransform = $DisclosureRef.ScaleTransform
		$duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(170))

		if (-not $Animate)
		{
			$bodyPanel.Visibility = if ($Collapsed) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$bodyPanel.Opacity = if ($Collapsed) { 0.0 } else { 1.0 }
			if ($scaleTransform)
			{
				$scaleTransform.ScaleY = if ($Collapsed) { 0.96 } else { 1.0 }
			}
			return
		}

		if ($Collapsed)
		{
			$opacityAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new()
			$opacityAnimation.To = 0.0
			$opacityAnimation.Duration = $duration
			$opacityAnimation.Add_Completed({
				$bodyPanel.Visibility = [System.Windows.Visibility]::Collapsed
			}.GetNewClosure())
			$bodyPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $opacityAnimation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)

			if ($scaleTransform)
			{
				$scaleAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new()
				$scaleAnimation.To = 0.96
				$scaleAnimation.Duration = $duration
				$scaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
			}
			return
		}

		$bodyPanel.Visibility = [System.Windows.Visibility]::Visible
		$bodyPanel.Opacity = 0.0
		if ($scaleTransform) { $scaleTransform.ScaleY = 0.96 }
		$showOpacityAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new()
		$showOpacityAnimation.To = 1.0
		$showOpacityAnimation.Duration = $duration
		$bodyPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $showOpacityAnimation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)

		if ($scaleTransform)
		{
			$showScaleAnimation = [System.Windows.Media.Animation.DoubleAnimation]::new()
			$showScaleAnimation.To = 1.0
			$showScaleAnimation.Duration = $duration
			$scaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $showScaleAnimation, [System.Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiRecommendationDisclosureScopeState
	{
		param (
			[string]$Scope,
			[bool]$Collapsed,
			[switch]$Animate
		)

		Initialize-GuiRecommendationDisclosureState
		if ([string]::IsNullOrWhiteSpace([string]$Scope)) { return }
		$Script:RecommendedSelectionsCollapsedByScope[[string]$Scope] = [bool]$Collapsed
		foreach ($disclosureRef in @($Script:RecommendationDisclosureRefsByKey.Values))
		{
			if (-not $disclosureRef -or [string]$disclosureRef.Scope -ne [string]$Scope) { continue }
			Set-GuiRecommendationDisclosureVisualState -DisclosureRef $disclosureRef -Collapsed:$Collapsed -Animate:$Animate
		}
		Update-GuiRecommendationDisclosureHeaders
	}

	<#
	    .SYNOPSIS
	#>

	function New-GuiRecommendationDisclosurePanel
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Scope,
			[Parameter(Mandatory = $true)]
			[string]$Title,
			[Parameter(Mandatory = $true)]
			[object]$Body,
			[Parameter(Mandatory = $true)]
			[object]$BrushConverter,
			[string]$PrimaryTab = $null,
			[string]$InstanceKey = $null,
			[object]$DefaultCollapsed = $null,
			[double]$BorderThickness = 1.5,
			[int]$CornerRadius = 10,
			[System.Windows.Thickness]$Margin = $null,
			[System.Windows.Thickness]$Padding = $null,
			[switch]$Compact,
			[switch]$UseShadow
		)

		Initialize-GuiRecommendationDisclosureState
		if ([string]::IsNullOrWhiteSpace([string]$InstanceKey))
		{
			$InstanceKey = [string]$Scope
		}
		if ($null -ne $DefaultCollapsed -and -not (Test-GuiRecommendationHasManualCollapseState -Scope $Scope))
		{
			$Script:RecommendedSelectionsCollapsedByScope[[string]$Scope] = [bool]$DefaultCollapsed
		}
		if ($null -eq $Margin) { $Margin = if ($Compact) { [System.Windows.Thickness]::new(8, 6, 8, 6) } else { [System.Windows.Thickness]::new(8, 14, 8, 10) } }
		if ($null -eq $Padding) { $Padding = if ($Compact) { [System.Windows.Thickness]::new(10, 7, 10, 7) } else { [System.Windows.Thickness]::new(16, 12, 16, 14) } }

		$collapsed = Get-GuiRecommendationCollapsedState -Scope $Scope
		$outerBorder = New-Object System.Windows.Controls.Border
		$outerBorder.Background = $BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBg)
		$outerBorder.BorderBrush = $BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBorder)
		$outerBorder.BorderThickness = [System.Windows.Thickness]::new($BorderThickness)
		$outerBorder.CornerRadius = [System.Windows.CornerRadius]::new($CornerRadius)
		$outerBorder.Margin = $Margin
		$outerBorder.Padding = $Padding
		if ($UseShadow)
		{
			$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
			$shadow.BlurRadius = 12
			$shadow.ShadowDepth = 2
			$shadow.Opacity = 0.25
			$shadow.Color = [System.Windows.Media.Colors]::Black
			if ($shadow.CanFreeze) { $shadow.Freeze() }
			$outerBorder.Effect = $shadow
		}

		$container = New-Object System.Windows.Controls.StackPanel
		$container.Orientation = 'Vertical'

		$headerButton = New-Object System.Windows.Controls.Button
		$headerButton.Background = [System.Windows.Media.Brushes]::Transparent
		$headerButton.BorderThickness = [System.Windows.Thickness]::new(0)
		$headerButton.Padding = [System.Windows.Thickness]::new(0)
		$headerButton.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
		$headerButton.Cursor = [System.Windows.Input.Cursors]::Hand
		$headerButton.Focusable = $true
		$headerButton.ToolTip = Get-UxLocalizedString -Key 'GuiRecommendationCollapseTooltip' -Fallback 'Show or hide recommended selections.'

		$headerPanel = New-Object System.Windows.Controls.DockPanel
		$headerPanel.LastChildFill = $true
		$headerTextBlock = New-Object System.Windows.Controls.TextBlock
		$headerTextBlock.Text = Get-GuiRecommendationDisclosureHeaderText -Scope $Scope -Title $Title -PrimaryTab $PrimaryTab -Collapsed:$collapsed
		$headerTextBlock.FontSize = if ($Compact) { $Script:GuiLayout.FontSizeLabel } else { $Script:GuiLayout.FontSizeSection }
		$headerTextBlock.FontWeight = [System.Windows.FontWeights]::Bold
		$headerTextBlock.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$headerTextBlock.TextWrapping = 'Wrap'
		[void]($headerPanel.Children.Add($headerTextBlock))
		$headerButton.Content = $headerPanel
		[System.Windows.Automation.AutomationProperties]::SetName($headerButton, [string]$headerTextBlock.Text)
		[System.Windows.Automation.AutomationProperties]::SetHelpText($headerButton, (Get-UxLocalizedString -Key 'GuiRecommendationCollapseHelp' -Fallback 'Press Enter or Space to expand or collapse the recommendation section.'))
		[void]($container.Children.Add($headerButton))

		$bodyPanel = $Body
		$bodyPanel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$bodyPanel.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.0)
		$scaleTransform = [System.Windows.Media.ScaleTransform]::new(1.0, $(if ($collapsed) { 0.96 } else { 1.0 }))
		$bodyPanel.RenderTransform = $scaleTransform
		$bodyPanel.Visibility = if ($collapsed) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
		$bodyPanel.Opacity = if ($collapsed) { 0.0 } else { 1.0 }
		[void]($container.Children.Add($bodyPanel))

		$disclosureRef = [pscustomobject]@{
			Scope = [string]$Scope
			PrimaryTab = [string]$PrimaryTab
			Title = [string]$Title
			HeaderButton = $headerButton
			HeaderTextBlock = $headerTextBlock
			BodyPanel = $bodyPanel
			ScaleTransform = $scaleTransform
		}
		$Script:RecommendationDisclosureRefsByKey[[string]$InstanceKey] = $disclosureRef
		$getRecommendationCollapsedStateScript = ${function:Get-GuiRecommendationCollapsedState}
		$toggleRecommendationScopeScript = ${function:Set-GuiRecommendationDisclosureScopeState}
		$null = Register-GuiEventHandler -Source $headerButton -EventName 'Click' -Handler ({
			$newCollapsed = -not (& $getRecommendationCollapsedStateScript -Scope $Scope)
			& $toggleRecommendationScopeScript -Scope $Scope -Collapsed:$newCollapsed -Animate
		}.GetNewClosure())

		$outerBorder.Child = $container
		return $outerBorder
	}

	<#
	    .SYNOPSIS
	#>

	function New-GuiRecommendationPanelContainer
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Title,
			[Parameter(Mandatory = $true)]
			[object]$Body,
			[Parameter(Mandatory = $true)]
			[object]$BrushConverter,
			[double]$BorderThickness = 1.5,
			[int]$CornerRadius = 10,
			[System.Windows.Thickness]$Margin = $null,
			[System.Windows.Thickness]$Padding = $null,
			[switch]$UseShadow
		)

		if ($null -eq $Margin) { $Margin = [System.Windows.Thickness]::new(8, 14, 8, 10) }
		if ($null -eq $Padding) { $Padding = [System.Windows.Thickness]::new(18, 14, 18, 14) }

		$outerBorder = New-Object System.Windows.Controls.Border
		$outerBorder.Background = $BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBg)
		$outerBorder.BorderBrush = $BrushConverter.ConvertFromString($Script:CurrentTheme.PresetPanelBorder)
		$outerBorder.BorderThickness = [System.Windows.Thickness]::new($BorderThickness)
		$outerBorder.CornerRadius = [System.Windows.CornerRadius]::new($CornerRadius)
		$outerBorder.Margin = $Margin
		$outerBorder.Padding = $Padding
		if ($UseShadow)
		{
			$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
			$shadow.BlurRadius = 12
			$shadow.ShadowDepth = 2
			$shadow.Opacity = 0.25
			$shadow.Color = [System.Windows.Media.Colors]::Black
			if ($shadow.CanFreeze) { $shadow.Freeze() }
			$outerBorder.Effect = $shadow
		}

		$container = New-Object System.Windows.Controls.StackPanel
		$container.Orientation = 'Vertical'
		$titleBlock = New-Object System.Windows.Controls.TextBlock
		$titleBlock.Text = $Title
		$titleBlock.FontSize = $Script:GuiLayout.FontSizeSection
		$titleBlock.FontWeight = [System.Windows.FontWeights]::Bold
		$titleBlock.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$titleBlock.TextWrapping = 'Wrap'
		[void]($container.Children.Add($titleBlock))

		$Body.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		[void]($container.Children.Add($Body))
		$outerBorder.Child = $container
		return $outerBorder
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRecommendationCompactStatusText
	{
		param (
			[string]$Scope = 'RecommendedSelections',
			[string]$PrimaryTab = $null
		)

		if (Test-IsSafeModeUX)
		{
			$safeSummary = Get-GuiRecommendationSelectedSummaryText -Scope $Scope -PrimaryTab $PrimaryTab
			if (-not [string]::IsNullOrWhiteSpace([string]$safeSummary))
			{
				return (Get-UxLocalizedString -Key 'GuiSafeModeCompactBannerWithSelection' -Fallback 'Safe Mode is enabled - {0}' -FormatArgs @($safeSummary))
			}
			return (Get-UxLocalizedString -Key 'GuiSafeModeCompactBanner' -Fallback 'Safe Mode is enabled. Advanced presets are hidden.')
		}

		$summary = Get-GuiRecommendationSelectedSummaryText -Scope $Scope -PrimaryTab $PrimaryTab
		if (-not [string]::IsNullOrWhiteSpace([string]$summary))
		{
			return (Get-UxLocalizedString -Key 'GuiRecommendationsCompactActive' -Fallback 'Recommendations active - {0}' -FormatArgs @($summary))
		}

		return (Get-UxLocalizedString -Key 'GuiRecommendationsCompactInitialSetup' -Fallback 'Presets and recommendations are on Initial Setup.')
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiRecommendationCompactStripState
	{
		param ([object]$StripRef)

		if (-not $StripRef -or -not $StripRef.StatusTextBlock) { return }
		$stripScope = [string]$StripRef.Scope
		$primaryTab = [string]$StripRef.PrimaryTab
		$isSafeMode = Test-IsSafeModeUX
		$hasSelection = Test-GuiRecommendationHasSelection -Scope $stripScope

		$StripRef.StatusTextBlock.Text = Get-GuiRecommendationCompactStatusText -Scope $stripScope -PrimaryTab $primaryTab
		$StripRef.StatusTextBlock.FontWeight = if ($isSafeMode -or $hasSelection) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal }

		if ($StripRef.Border -and $StripRef.BrushConverter)
		{
			$hasStateAccent = ($Script:CurrentTheme -is [System.Collections.IDictionary]) -and $Script:CurrentTheme.Contains('StateAccent')
			$borderColor = if ($isSafeMode -and $hasStateAccent) { [string]$Script:CurrentTheme['StateAccent'] } elseif ($hasSelection) { [string]$Script:CurrentTheme.ActiveTabBorder } else { [string]$Script:CurrentTheme.CardBorder }
			if ([string]::IsNullOrWhiteSpace([string]$borderColor)) { $borderColor = '#D8E0EC' }
			$StripRef.Border.BorderBrush = $StripRef.BrushConverter.ConvertFromString($borderColor)
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiRecommendationCompactStrips
	{
		Initialize-GuiRecommendationDisclosureState
		foreach ($stripRef in @($Script:RecommendationCompactStripRefsByKey.Values))
		{
			Set-GuiRecommendationCompactStripState -StripRef $stripRef
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Invoke-GuiInitialSetupTabNavigation
	{
		$targetTabTag = 'Initial Setup'
		$targetTab = $null
		if ($Script:GetPrimaryTabItemScript)
		{
			$targetTab = & $Script:GetPrimaryTabItemScript -Tag $targetTabTag
		}
		elseif ($PrimaryTabs)
		{
			foreach ($tab in $PrimaryTabs.Items)
			{
				if (($tab -is [System.Windows.Controls.TabItem]) -and [string]$tab.Tag -eq $targetTabTag)
				{
					$targetTab = $tab
					break
				}
			}
		}

		if ($PrimaryTabs -and $targetTab)
		{
			if ($PrimaryTabs.SelectedItem -ne $targetTab)
			{
				$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = $true
				$PrimaryTabs.SelectedItem = $targetTab
			}
			elseif ($Script:UpdateCurrentTabContentScript)
			{
				& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
			}
			return
		}

		$Script:CurrentPrimaryTab = $targetTabTag
		if ($Script:UpdateCurrentTabContentScript)
		{
			& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
		}
	}

	<#
	    .SYNOPSIS
	#>

	function New-GuiRecommendationCompactStrip
	{
		param (
			[Parameter(Mandatory = $true)]
			[object]$BuildContext,
			[string]$Scope = 'RecommendedSelections',
			[string]$InstanceKey = $null,
			[switch]$ShowChangeButton
		)

		Initialize-GuiRecommendationDisclosureState
		if ([string]::IsNullOrWhiteSpace([string]$InstanceKey))
		{
			$InstanceKey = ('{0}:{1}' -f [string]$Scope, [string]$BuildContext.PrimaryTab)
		}

		$strip = New-Object System.Windows.Controls.Border
		$strip.Background = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CardBg)
		$strip.BorderThickness = [System.Windows.Thickness]::new(1)
		$strip.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$strip.Margin = [System.Windows.Thickness]::new(8, 6, 8, 6)
		$strip.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)

		$dockPanel = New-Object System.Windows.Controls.DockPanel
		$dockPanel.LastChildFill = $true
		if ($ShowChangeButton)
		{
			$changeButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiRecommendationsChange' -Fallback 'Change') -Variant 'Subtle' -Compact -Muted
			$changeButton.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
			$changeButton.ToolTip = Get-UxLocalizedString -Key 'GuiRecommendationsChangeTooltip' -Fallback 'Open Initial Setup to change presets and recommendations.'
			[System.Windows.Automation.AutomationProperties]::SetName($changeButton, (Get-UxLocalizedString -Key 'GuiRecommendationsChangeAutomation' -Fallback 'Change recommendations'))
			[System.Windows.Controls.DockPanel]::SetDock($changeButton, [System.Windows.Controls.Dock]::Right)
			$navigateToInitialSetupScript = ${function:Invoke-GuiInitialSetupTabNavigation}
			$null = Register-GuiEventHandler -Source $changeButton -EventName 'Click' -Handler ({
				& $navigateToInitialSetupScript
			}.GetNewClosure())
			[void]($dockPanel.Children.Add($changeButton))
		}

		$statusText = New-Object System.Windows.Controls.TextBlock
		$statusText.FontSize = $Script:GuiLayout.FontSizeSmall
		$statusText.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$statusText.TextWrapping = 'Wrap'
		$statusText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		[void]($dockPanel.Children.Add($statusText))
		$strip.Child = $dockPanel

		$stripRef = [pscustomobject]@{
			Scope = [string]$Scope
			PrimaryTab = [string]$BuildContext.PrimaryTab
			Border = $strip
			StatusTextBlock = $statusText
			BrushConverter = $BuildContext.BrushConverter
		}
		$Script:RecommendationCompactStripRefsByKey[[string]$InstanceKey] = $stripRef
		Set-GuiRecommendationCompactStripState -StripRef $stripRef
		return $strip
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

		# Scenarios accumulate - multiple can be active simultaneously.
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

		Update-GuiRecommendationDisclosureHeaders
		Update-GuiRecommendationCompactStrips
	}

	<#
	    .SYNOPSIS
	#>

	function New-TabPresetButtonsPanel
	{
		param ([object]$BuildContext)

		$presetBar = New-Object System.Windows.Controls.WrapPanel
		$presetBar.Orientation = 'Horizontal'
		$presetBar.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		if (-not ($Script:PresetButtonRefsByTab -is [hashtable])) { $Script:PresetButtonRefsByTab = @{} }
		$tabPresetRefs = [System.Collections.Generic.List[object]]::new()
		$Script:PresetButtonRefsByTab[[string]$BuildContext.PrimaryTab] = $tabPresetRefs
		foreach ($presetDefinition in @(Get-TabPresetButtonDefinitions -IsSafeUx:(Test-IsSafeModeUX) -PrimaryTab ([string]$BuildContext.PrimaryTab)))
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

	<#
	    .SYNOPSIS
	#>

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
			$localizedScenarioLabel = Get-UxLocalizedString -Key "GuiScenarioLabel$scenarioName" -Fallback ([string]$scenarioDefinition.Label)
			$button = New-PresetButton -Label $localizedScenarioLabel -Variant $defaultVariant
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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function New-SystemScanActionRow
	{
		param ([object]$BuildContext)

		$actionRow = New-Object System.Windows.Controls.WrapPanel
		$actionRow.Orientation = 'Horizontal'
		$actionRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)

		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$invokeGuiSystemScanCommand = Get-GuiRuntimeCommand -Name 'Invoke-GuiSystemScan' -CommandType 'Function'
		$buttonLabel = & $getUxLocalizedStringCapture -Key 'GuiSystemScanButton' -Fallback 'System Scan'
		$systemScanButton = New-PresetButton -Label $buttonLabel -Variant 'Secondary'
		if (-not $systemScanButton)
		{
			throw ("New-PresetButton returned null for {0}." -f $buttonLabel)
		}
		$systemScanButton.ToolTip = 'Scan the current system state and refresh supported recommendations.'
		Register-GuiCommandButtonAction -Button $systemScanButton -DebugContext 'Build-TabContent/Preset/SystemScan' -DebugMessage ("Preset button clicked. CurrentPrimaryTab='{0}', running system scan." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' })) -WriteGuiPresetDebugCommand $BuildContext.WriteGuiPresetDebugCommand -Action ({
			& $invokeGuiSystemScanCommand
		}.GetNewClosure())
		[void]($actionRow.Children.Add($systemScanButton))

		return $actionRow
	}

	<#
	    .SYNOPSIS
	#>

	function New-TabPresetPanel
	{
		param ([object]$BuildContext)

		$presetPanelStack = New-Object System.Windows.Controls.StackPanel
		$presetPanelStack.Orientation = 'Vertical'

		$presetSubheading = New-Object System.Windows.Controls.TextBlock
		$presetSubheading.Text = Get-UxPresetEmphasisText
		$presetSubheading.FontSize = $Script:GuiLayout.FontSizeLabel
		$presetSubheading.TextWrapping = 'Wrap'
		$presetSubheading.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
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
		$scenarioSubheading.Text = Get-UxString -Key 'GuiPresetPanelDescText' -Fallback 'Focused bundles stay separate from the main preset ladder. Run System Scan to surface environment-based recommendations. Those recommendations stay advisory and never change selections automatically.'
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

		# Small shared progress bar shown only while a preset is being applied.
		$sharedPresetProgress = New-SharedProgressBarHost -Maximum 100 -Value 0 -Height 3
		$Script:PresetProgressHost = $sharedPresetProgress.Host
		$Script:PresetProgressBar = $sharedPresetProgress.ProgressBar
		$Script:PresetProgressHost.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$Script:PresetProgressHost.Visibility = [System.Windows.Visibility]::Collapsed
		[void]($presetPanelStack.Children.Add($Script:PresetProgressHost))

		$reassuranceNote = New-Object System.Windows.Controls.TextBlock
		$reassuranceNote.Text = Get-UxString -Key 'GuiPresetPanelRunNote' -Fallback ('No changes are made until you click {0}. You can preview everything first.' -f (Get-UxRunActionLabel))
		$reassuranceNote.FontSize = $Script:GuiLayout.FontSizeSmall
		$reassuranceNote.TextWrapping = 'Wrap'
		$reassuranceNote.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		$reassuranceNote.Foreground = $BuildContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$reassuranceNote.Opacity = 0.7
		[void]($presetPanelStack.Children.Add($reassuranceNote))

		return (New-GuiRecommendationPanelContainer `
			-Title (Get-UxLocalizedString -Key 'GuiPresetPanelHeading' -Fallback 'Recommended Selections') `
			-Body $presetPanelStack `
			-BrushConverter $BuildContext.BrushConverter `
			-BorderThickness 1.5 `
			-CornerRadius $Script:GuiLayout.BorderRadiusLarge `
			-Margin ([System.Windows.Thickness]::new(8, 14, 8, 10)) `
			-Padding ([System.Windows.Thickness]::new(18, 14, 18, 14)) `
			-UseShadow)
	}

	<#
	    .SYNOPSIS
	#>

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

		if ($BuildContext.PrimaryTab -eq 'Updates')
		{
			try
			{
				$updatesLeadPanelCommand = Get-GuiRuntimeCommand -Name 'New-GuiWindowsUpdateLeadCardsPanel' -CommandType 'Function'
				if (-not $updatesLeadPanelCommand)
				{
					throw 'New-GuiWindowsUpdateLeadCardsPanel is not available.'
				}
				$updatesLeadPanel = & $updatesLeadPanelCommand
				if ($updatesLeadPanel)
				{
					[void]($BuildContext.MainPanel.Children.Add($updatesLeadPanel))
				}
			}
			catch
			{
				throw "Build-TabContent/UpdatesLeadCardsPanel for tab '$($BuildContext.PrimaryTab)' failed: $($_.Exception.Message)"
			}
		}

		if ($BuildContext.PrimaryTab -eq 'Gaming')
		{
			# "Reset Gaming Tweaks" button - restores Gaming-tab entries to recorded defaults
			try
			{
				$resetGamingButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiResetGamingTweaks' -Fallback 'Reset Gaming Tweaks') -Variant 'DangerSubtle' -Compact
				$resetGamingButton.Margin = [System.Windows.Thickness]::new(8, 4, 8, 4)
				$resetGamingButton.FontSize = $Script:GuiLayout.FontSizeSmall
				$resetGamingButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
				$resetGamingButton.ToolTip = (Get-UxLocalizedString -Key 'GuiResetGamingTooltipRecorded' -Fallback 'Restore all Gaming tab tweaks to recorded default values')

				$getWindowsDefaultRunListCapture = if ($Script:GetWindowsDefaultRunListScript) { $Script:GetWindowsDefaultRunListScript } else { ${function:Get-WindowsDefaultRunList} }
				$startGuiExecutionRunCapture = if ($Script:StartGuiExecutionRunScript) { $Script:StartGuiExecutionRunScript } else { ${function:Start-GuiExecutionRun} }
				$showThemedDialogCapture = if ($Script:ShowThemedDialogScript) { $Script:ShowThemedDialogScript } else { ${function:Show-ThemedDialog} }
				$resetGamingTitleLocalized = Get-UxLocalizedString -Key 'GuiResetGamingTitle' -Fallback 'Reset Gaming Tweaks'
				$resetGamingMsgLocalized = Get-UxLocalizedString -Key 'GuiResetGamingMessageRecorded' -Fallback 'This will restore all Gaming tab tweaks to recorded default values. Your other settings are not affected.'
				$resetGamingBtnLocalized = Get-UxLocalizedString -Key 'GuiResetGamingBtn' -Fallback 'Reset Gaming'
				$resetGamingCancelLocalized = Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel'
				$resetGamingNoTweaksLocalized = Get-UxLocalizedString -Key 'GuiResetGamingNoTweaks' -Fallback 'No restorable Gaming tweaks found.'
				$resetGamingOkLocalized = Get-UxLocalizedString -Key 'GuiBtnOk' -Fallback 'OK'
				$resetGamingExecTitleLocalized = Get-UxLocalizedString -Key 'GuiResetGamingExecTitleRecorded' -Fallback 'Resetting Gaming Tweaks to Defaults'
				$null = Register-GuiEventHandler -Source $resetGamingButton -EventName 'Click' -Handler ({
					$confirmResult = & $showThemedDialogCapture -Title $resetGamingTitleLocalized `
						-Message $resetGamingMsgLocalized `
						-Buttons @($resetGamingBtnLocalized, $resetGamingCancelLocalized) `
						-DestructiveButton $resetGamingBtnLocalized
					if ($confirmResult -ne $resetGamingBtnLocalized) { return }

					$allDefaults = @(& $getWindowsDefaultRunListCapture)
					$gamingDefaults = @($allDefaults | Where-Object { [string]$_.Category -eq 'Gaming' })
					if ($gamingDefaults.Count -eq 0)
					{
						& $showThemedDialogCapture -Title $resetGamingTitleLocalized `
							-Message $resetGamingNoTweaksLocalized `
							-Buttons @($resetGamingOkLocalized) -AccentButton $resetGamingOkLocalized
						return
					}
					& $startGuiExecutionRunCapture -TweakList $gamingDefaults -Mode 'Defaults' -ExecutionTitle $resetGamingExecTitleLocalized
				}.GetNewClosure())
				[void]($BuildContext.MainPanel.Children.Add($resetGamingButton))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/ResetGamingButton' -Message ("Reset Gaming button failed: {0}" -f $_.Exception.Message)
			}

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

		if ($BuildContext.PrimaryTab -notin @('Gaming', 'Initial Setup'))
		{
			try
			{
				$pageCategory = [string]$BuildContext.PrimaryTab
				$resetPageButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiResetPageTweaks' -Fallback ('Reset {0} to defaults' -f $pageCategory) -FormatArgs @($pageCategory)) -Variant 'DangerSubtle' -Compact
				$resetPageButton.Margin = [System.Windows.Thickness]::new(8, 4, 8, 4)
				$resetPageButton.FontSize = $Script:GuiLayout.FontSizeSmall
				$resetPageButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
				$resetPageButton.ToolTip = (Get-UxLocalizedString -Key 'GuiResetPageTooltipRecorded' -Fallback ('Restore all tweaks on the {0} page to recorded default values.' -f $pageCategory))
				$invokePageResetToDefaultsCapture = if ($Script:InvokePageResetToDefaultsScript) { $Script:InvokePageResetToDefaultsScript } else { ${function:Invoke-PageResetToDefaults} }
				if (-not $invokePageResetToDefaultsCapture) { throw 'Invoke-PageResetToDefaults not found.' }
				$null = Register-GuiEventHandler -Source $resetPageButton -EventName 'Click' -Handler ({
					& $invokePageResetToDefaultsCapture -Category $pageCategory
				}.GetNewClosure())
				[void]($BuildContext.MainPanel.Children.Add($resetPageButton))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/ResetPageButton' -Message ("Reset page button failed for tab '{0}': {1}" -f $BuildContext.PrimaryTab, $_.Exception.Message)
			}
		}

		try
		{
			if ($BuildContext.PrimaryTab -eq 'Initial Setup')
			{
				[void]($BuildContext.MainPanel.Children.Add((New-TabPresetPanel -BuildContext $BuildContext)))
			}
			elseif ($BuildContext.PrimaryTab -ne 'Gaming' -and $BuildContext.PrimaryTab -ne 'Updates')
			{
				[void]($BuildContext.MainPanel.Children.Add((New-GuiRecommendationCompactStrip -BuildContext $BuildContext -ShowChangeButton)))
			}
		}
		catch
		{
			throw "Build-TabContent/RecommendationContext for tab '$($BuildContext.PrimaryTab)' failed: $($_.Exception.Message)"
		}
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function Clear-GuiTweakSelectionControl
	{
		param ([object]$Control)

		if (-not $Control) { return }

		$hasField = {
			param (
				[object]$Object,
				[string]$FieldName
			)

			if ($null -eq $Object)
			{
				return $false
			}

			if ($Object -is [System.Collections.IDictionary])
			{
				return $Object.Contains($FieldName)
			}

			return ($null -ne $Object.PSObject.Properties[$FieldName])
		}.GetNewClosure()

		$clearTarget = {
			param ([object]$Target)

			if (-not $Target) { return }
			if (& $hasField -Object $Target -FieldName 'IsChecked')
			{
				$Target.IsChecked = $false
			}
			if (& $hasField -Object $Target -FieldName 'SelectedIndex')
			{
				$Target.SelectedIndex = [int]-1
			}
			if (& $hasField -Object $Target -FieldName 'SelectedDate')
			{
				$Target.SelectedDate = $null
			}
			if (& $hasField -Object $Target -FieldName 'SelectedValue')
			{
				$Target.SelectedValue = $null
			}
			if (& $hasField -Object $Target -FieldName 'Value')
			{
				$Target.Value = $null
			}
		}.GetNewClosure()

		& $clearTarget -Target $Control
		foreach ($childField in @('CheckBox', 'ComboBox', 'RadioButton', 'DatePicker'))
		{
			if ((& $hasField -Object $Control -FieldName $childField) -and $Control.$childField)
			{
				& $clearTarget -Target $Control.$childField
			}
		}
	}

	function Get-GuiBulkSelectionObjectField
	{
		param (
			[object]$Object,
			[string]$FieldName
		)

		if ($null -eq $Object -or [string]::IsNullOrWhiteSpace([string]$FieldName))
		{
			return $null
		}

		if ($Object -is [System.Collections.IDictionary])
		{
			if ($Object.Contains($FieldName))
			{
				return $Object[$FieldName]
			}
			return $null
		}

		$property = $Object.PSObject.Properties[$FieldName]
		if ($property)
		{
			return $property.Value
		}

		return $null
	}

	function Get-GuiBulkSelectableActionPath
	{
		param (
			[object]$Selection,
			[object]$ActionPicker
		)

		if (-not $Selection -or -not $ActionPicker)
		{
			return $null
		}

		$parameterName = [string](Get-GuiBulkSelectionObjectField -Object $ActionPicker -FieldName 'ParameterName')
		if (-not [string]::IsNullOrWhiteSpace($parameterName))
		{
			$extraArgs = Get-GuiBulkSelectionObjectField -Object $Selection -FieldName 'ExtraArgs'
			if ($extraArgs)
			{
				$extraValue = Get-GuiBulkSelectionObjectField -Object $extraArgs -FieldName $parameterName
				if (-not [string]::IsNullOrWhiteSpace([string]$extraValue))
				{
					return [string]$extraValue
				}
			}
		}

		foreach ($fieldName in @('Value', 'Selection', 'SelectedValue'))
		{
			$value = Get-GuiBulkSelectionObjectField -Object $Selection -FieldName $fieldName
			if (-not [string]::IsNullOrWhiteSpace([string]$value))
			{
				return [string]$value
			}
		}

		return $null
	}

	function New-GuiBulkSelectableControlTestScript
	{
		$getField = {
			param (
				[object]$Object,
				[string]$FieldName
			)

			if ($null -eq $Object -or [string]::IsNullOrWhiteSpace([string]$FieldName))
			{
				return $null
			}

			if ($Object -is [System.Collections.IDictionary])
			{
				if ($Object.Contains($FieldName))
				{
					return $Object[$FieldName]
				}
				return $null
			}

			$property = $Object.PSObject.Properties[$FieldName]
			if ($property)
			{
				return $property.Value
			}

			return $null
		}.GetNewClosure()

		$getActionPath = {
			param (
				[object]$Selection,
				[object]$ActionPicker
			)

			if (-not $Selection -or -not $ActionPicker)
			{
				return $null
			}

			$parameterName = [string](& $getField -Object $ActionPicker -FieldName 'ParameterName')
			if (-not [string]::IsNullOrWhiteSpace($parameterName))
			{
				$extraArgs = & $getField -Object $Selection -FieldName 'ExtraArgs'
				if ($extraArgs)
				{
					$extraValue = & $getField -Object $extraArgs -FieldName $parameterName
					if (-not [string]::IsNullOrWhiteSpace([string]$extraValue))
					{
						return [string]$extraValue
					}
				}
			}

			foreach ($fieldName in @('Value', 'Selection', 'SelectedValue'))
			{
				$value = & $getField -Object $Selection -FieldName $fieldName
				if (-not [string]::IsNullOrWhiteSpace([string]$value))
				{
					return [string]$value
				}
			}

			return $null
		}.GetNewClosure()

		return {
			param (
				[object]$Control,
				[object]$ManifestEntry = $null,
				[object]$ExplicitSelectionDefinition = $null
			)

			if (-not $Control)
			{
				return $false
			}

			$actionPicker = & $getField -Object $Control -FieldName 'ActionPicker'
			if (-not $actionPicker -and $ManifestEntry)
			{
				$actionPicker = & $getField -Object $ManifestEntry -FieldName 'ActionPicker'
			}
			if (-not $actionPicker)
			{
				return $true
			}

			$selectedPath = & $getActionPath -Selection $Control -ActionPicker $actionPicker
			if ([string]::IsNullOrWhiteSpace([string]$selectedPath) -and $ExplicitSelectionDefinition)
			{
				$selectedPath = & $getActionPath -Selection $ExplicitSelectionDefinition -ActionPicker $actionPicker
			}

			return (-not [string]::IsNullOrWhiteSpace([string]$selectedPath))
		}.GetNewClosure()
	}

	function Test-GuiBulkSelectableControl
	{
		param (
			[object]$Control,
			[object]$ManifestEntry = $null,
			[object]$ExplicitSelectionDefinition = $null
		)

		$testBulkSelectableControl = New-GuiBulkSelectableControlTestScript
		return [bool](& $testBulkSelectableControl -Control $Control -ManifestEntry $ManifestEntry -ExplicitSelectionDefinition $ExplicitSelectionDefinition)
	}

	function New-TabSelectionBar
	{
		param ([int[]]$AllTabIndexes)

		$selectionBar = New-Object System.Windows.Controls.WrapPanel
		$selectionBar.Orientation = 'Horizontal'
		$selectionBar.Margin = [System.Windows.Thickness]::new(8, 8, 8, 2)

		$selectAllButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiSelectAll' -Fallback 'Select All') -Variant 'Subtle' -Compact
		$controlsRefForSelect = $Script:Controls
		$tweakManifestRefForSelect = $Script:TweakManifest
		$capturedSelectIndexes = [int[]]$AllTabIndexes
		$getExplicitSelectionDefinition = ${function:Get-GuiExplicitSelectionDefinition}
		$testBulkSelectableControl = New-GuiBulkSelectableControlTestScript
		$enterSelectionBulkUpdate = Get-GuiFunctionCapture -Name 'Enter-GuiSelectionBulkUpdate'
		$exitSelectionBulkUpdate = Get-GuiFunctionCapture -Name 'Exit-GuiSelectionBulkUpdate'
		$hasField = {
			param (
				[object]$Object,
				[string]$FieldName
			)

			if ($null -eq $Object)
			{
				return $false
			}

			if ($Object -is [System.Collections.IDictionary])
			{
				return $Object.Contains($FieldName)
			}

			return ($null -ne $Object.PSObject.Properties[$FieldName])
		}.GetNewClosure()
		Register-GuiEventHandler -Source $selectAllButton -EventName 'Click' -Handler ({
			$selectionBulkPreviousState = $false
			if ($enterSelectionBulkUpdate)
			{
				$selectionBulkPreviousState = [bool](& $enterSelectionBulkUpdate)
			}
			try
			{
				foreach ($index in $capturedSelectIndexes)
				{
					$control = $controlsRefForSelect[$index]
					$manifestEntry = $null
					$explicitSelectionDefinition = $null
					if ($getExplicitSelectionDefinition -and $tweakManifestRefForSelect -and $index -ge 0 -and $index -lt $tweakManifestRefForSelect.Count)
					{
						$manifestEntry = $tweakManifestRefForSelect[$index]
						if ($manifestEntry -and -not [string]::IsNullOrWhiteSpace([string]$manifestEntry.Function))
						{
							$explicitSelectionDefinition = & $getExplicitSelectionDefinition -FunctionName ([string]$manifestEntry.Function)
						}
					}
					if ($control -and $control.IsEnabled -and (& $hasField -Object $control -FieldName 'IsChecked') -and (& $testBulkSelectableControl -Control $control -ManifestEntry $manifestEntry -ExplicitSelectionDefinition $explicitSelectionDefinition))
					{
						$control.IsChecked = $true
					}
				}
			}
			finally
			{
				if ($exitSelectionBulkUpdate)
				{
					& $exitSelectionBulkUpdate -PreviousState $selectionBulkPreviousState
				}
			}
		}.GetNewClosure()) | Out-Null
		[void]($selectionBar.Children.Add($selectAllButton))

		$unselectAllButton = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiUnselectAll' -Fallback 'Unselect All') -Variant 'Subtle' -Compact
		$controlsRefForUnselect = $Script:Controls
		$tweakManifestRefForUnselect = $Script:TweakManifest
		$capturedUnselectIndexes = [int[]]$AllTabIndexes
		$removeExplicitSelectionDefinition = ${function:Remove-GuiExplicitSelectionDefinition}
		$clearTweakSelectionControl = ${function:Clear-GuiTweakSelectionControl}
		Register-GuiEventHandler -Source $unselectAllButton -EventName 'Click' -Handler ({
			$selectionBulkPreviousState = $false
			if ($enterSelectionBulkUpdate)
			{
				$selectionBulkPreviousState = [bool](& $enterSelectionBulkUpdate)
			}
			try
			{
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
					& $clearTweakSelectionControl -Control $control
				}
			}
			finally
			{
				if ($exitSelectionBulkUpdate)
				{
					& $exitSelectionBulkUpdate -PreviousState $selectionBulkPreviousState
				}
			}
		}.GetNewClosure()) | Out-Null
		[void]($selectionBar.Children.Add($unselectAllButton))

		return $selectionBar
	}
