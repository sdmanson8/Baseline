# ──────────────────────────────────────────────────────────────────
# DiffView.ps1
# Visual diff dialog showing "Current State -> After Run" for each
# selected tweak.  Dot-sourced inside Show-TweakGUI so all $Script:
# and local UI variables remain in scope.
# ──────────────────────────────────────────────────────────────────

	function Build-TweakDiffData
	{
		<# .SYNOPSIS Computes diff data for each selected tweak: current value, planned value, and whether it will change. #>
		param (
			[Parameter(Mandatory = $true)]
			[object[]]$SelectedTweaks
		)

		$diffItems = [System.Collections.Generic.List[pscustomobject]]::new()

		foreach ($tweak in @($SelectedTweaks | Where-Object { $_ }))
		{
			$tweakName     = if (Test-GuiObjectField -Object $tweak -FieldName 'Name') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Name') } else { 'Unknown' }
			$tweakFunction = if (Test-GuiObjectField -Object $tweak -FieldName 'Function') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Function') } else { '' }
			$tweakType     = if (Test-GuiObjectField -Object $tweak -FieldName 'Type') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Type') } else { 'Action' }
			$tweakCategory = if (Test-GuiObjectField -Object $tweak -FieldName 'Category') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Category') } else { 'General' }
			$matchesDesired = if (Test-GuiObjectField -Object $tweak -FieldName 'MatchesDesired') { [bool](Get-GuiObjectField -Object $tweak -FieldName 'MatchesDesired') } else { $false }
			$requiresRestart = if (Test-GuiObjectField -Object $tweak -FieldName 'RequiresRestart') { [bool](Get-GuiObjectField -Object $tweak -FieldName 'RequiresRestart') } else { $false }
			$currentState  = if (Test-GuiObjectField -Object $tweak -FieldName 'CurrentState') { [string](Get-GuiObjectField -Object $tweak -FieldName 'CurrentState') } else { $null }
			$typeBadge     = if (Test-GuiObjectField -Object $tweak -FieldName 'TypeBadgeLabel') { [string](Get-GuiObjectField -Object $tweak -FieldName 'TypeBadgeLabel') } else { $tweakType }
			$typeTone      = if (Test-GuiObjectField -Object $tweak -FieldName 'TypeTone') { [string](Get-GuiObjectField -Object $tweak -FieldName 'TypeTone') } else { 'Muted' }

			# Derive current display value
			$currentDisplay = $null
			switch ($tweakType)
			{
				'Toggle'
				{
					$toggleParam = if (Test-GuiObjectField -Object $tweak -FieldName 'ToggleParam') { [string](Get-GuiObjectField -Object $tweak -FieldName 'ToggleParam') } else { $null }
					$onParam     = if (Test-GuiObjectField -Object $tweak -FieldName 'OnParam') { [string](Get-GuiObjectField -Object $tweak -FieldName 'OnParam') } else { $null }

					if (-not [string]::IsNullOrWhiteSpace($currentState) -and $currentState -ne 'Already set')
					{
						$currentDisplay = $currentState
					}
					else
					{
						# Infer from whether the planned toggle is flipping
						if (-not [string]::IsNullOrWhiteSpace($toggleParam) -and -not [string]::IsNullOrWhiteSpace($onParam))
						{
							$selectedIsOn = ($toggleParam -eq $onParam)
							if ($matchesDesired)
							{
								$currentDisplay = if ($selectedIsOn) { 'Enabled' } else { 'Disabled' }
							}
							else
							{
								$currentDisplay = if ($selectedIsOn) { 'Disabled' } else { 'Enabled' }
							}
						}
						else
						{
							$currentDisplay = 'Unknown'
						}
					}
				}
				'Choice'
				{
					if (-not [string]::IsNullOrWhiteSpace($currentState) -and $currentState -ne 'Already set')
					{
						$currentDisplay = $currentState
					}
					else
					{
						$defaultValue = if (Test-GuiObjectField -Object $tweak -FieldName 'DefaultValue') { [string](Get-GuiObjectField -Object $tweak -FieldName 'DefaultValue') } else { $null }
						$currentDisplay = if (-not [string]::IsNullOrWhiteSpace($defaultValue)) { $defaultValue } else { 'Current setting' }
					}
				}
				'Action'
				{
					$currentDisplay = 'Not run'
				}
				default
				{
					$currentDisplay = if (-not [string]::IsNullOrWhiteSpace($currentState)) { $currentState } else { 'Unknown' }
				}
			}

			# Derive planned/target display value
			$plannedDisplay = $null
			$plannedState = $null

			$getTweakPlannedCmd = Get-Command -Name 'Get-TweakPlannedStateValue' -CommandType Function -ErrorAction SilentlyContinue
			if ($getTweakPlannedCmd)
			{
				try { $plannedState = Get-TweakPlannedStateValue -RunListItem $tweak } catch { $plannedState = $null }
			}

			switch ($tweakType)
			{
				'Toggle'
				{
					if ($null -ne $plannedState -and (Test-GuiObjectField -Object $plannedState -FieldName 'PlannedState'))
					{
						$plannedBool = Get-GuiObjectField -Object $plannedState -FieldName 'PlannedState'
						if ($null -ne $plannedBool)
						{
							$plannedDisplay = if ([bool]$plannedBool) { 'Enabled' } else { 'Disabled' }
						}
					}

					if ([string]::IsNullOrWhiteSpace($plannedDisplay))
					{
						$toggleParam = if (Test-GuiObjectField -Object $tweak -FieldName 'ToggleParam') { [string](Get-GuiObjectField -Object $tweak -FieldName 'ToggleParam') } else { $null }
						$onParam     = if (Test-GuiObjectField -Object $tweak -FieldName 'OnParam') { [string](Get-GuiObjectField -Object $tweak -FieldName 'OnParam') } else { $null }
						if (-not [string]::IsNullOrWhiteSpace($toggleParam) -and -not [string]::IsNullOrWhiteSpace($onParam))
						{
							$plannedDisplay = if ($toggleParam -eq $onParam) { 'Enabled' } else { 'Disabled' }
						}
						else
						{
							$plannedDisplay = 'Toggle applied'
						}
					}
				}
				'Choice'
				{
					if ($null -ne $plannedState -and (Test-GuiObjectField -Object $plannedState -FieldName 'Selection'))
					{
						$plannedDisplay = [string](Get-GuiObjectField -Object $plannedState -FieldName 'Selection')
					}

					if ([string]::IsNullOrWhiteSpace($plannedDisplay))
					{
						$selection = if (Test-GuiObjectField -Object $tweak -FieldName 'Selection') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Selection') } else { $null }
						$plannedDisplay = if (-not [string]::IsNullOrWhiteSpace($selection)) { $selection } else { 'Selected option' }
					}
				}
				'Action'
				{
					$plannedDisplay = $tweakName
				}
				default
				{
					$plannedDisplay = if (-not [string]::IsNullOrWhiteSpace([string]$tweak.Selection)) { [string]$tweak.Selection } else { 'Applied' }
				}
			}

			# Determine whether a real change will occur
			$willChange = -not $matchesDesired

			[void]$diffItems.Add([pscustomobject]@{
				Name            = $tweakName
				Function        = $tweakFunction
				Type            = $tweakType
				TypeBadge       = $typeBadge
				TypeTone        = $typeTone
				Category        = $tweakCategory
				CurrentDisplay  = $currentDisplay
				PlannedDisplay  = $plannedDisplay
				WillChange      = $willChange
				MatchesDesired  = $matchesDesired
				RequiresRestart = $requiresRestart
			})
		}

		# Sort by category then name
		$sorted = @($diffItems | Sort-Object -Property @{ Expression = { $_.Category } }, @{ Expression = { $_.Name } })
		return $sorted
	}

	function Show-DiffViewDialog
	{
		<# .SYNOPSIS Opens a modal WPF dialog showing current-state-to-target-state diff for selected tweaks. #>
		param (
			[Parameter(Mandatory = $true)]
			[object[]]$DiffData
		)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DiffView'
		$layout = $Script:GuiLayout

		$items = @($DiffData | Where-Object { $_ })
		if ($items.Count -eq 0) { return 'Close' }

		# Compute summary counts
		$willChangeCount   = @($items | Where-Object { $_.WillChange }).Count
		$alreadySetCount   = @($items | Where-Object { -not $_.WillChange }).Count
		$restartCount      = @($items | Where-Object { $_.RequiresRestart -and $_.WillChange }).Count

		# ── Build dialog window ──
		$dlg = New-Object System.Windows.Window
		$dlg.Title = 'Diff View: Current State vs. After Run'
		$dlg.Width = $layout.DialogLargeWidth
		$dlg.Height = $layout.DialogLargeHeight
		$dlg.MinWidth = $layout.DialogLargeMinWidth
		$dlg.MinHeight = $layout.DialogLargeMinHeight
		$dlg.ResizeMode = 'CanResize'
		$dlg.WindowStartupLocation = 'CenterOwner'
		$dlg.Foreground = $bc.ConvertFromString($theme.TextPrimary)
		$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
		$dlg.FontSize = $layout.FontSizeBody
		$dlg.ShowInTaskbar = $false

		try
		{
			if ($Form) { $dlg.Owner = $Form }
		}
		catch { <# non-fatal #> }
		$roundedParts = ConvertTo-RoundedWindow -Window $dlg -Theme $theme
		[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		# ── Outer grid: header / scroll content / button bar ──
		$outerGrid = New-Object System.Windows.Controls.Grid
		[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
		[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))

		# ── Row 0: Header with summary bar ──
		$headerBorder = New-Object System.Windows.Controls.Border
		$headerBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 16)
		$headerBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
		$headerBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
		[System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

		$headerStack = New-Object System.Windows.Controls.StackPanel
		$headerStack.Orientation = 'Vertical'

		$titleText = New-Object System.Windows.Controls.TextBlock
		$titleText.Text = 'Change Preview'
		$titleText.FontSize = $layout.FontSizeHeading
		$titleText.FontWeight = [System.Windows.FontWeights]::Bold
		$titleText.Foreground = $bc.ConvertFromString($theme.TextPrimary)
		[void]($headerStack.Children.Add($titleText))

		$subtitleText = New-Object System.Windows.Controls.TextBlock
		$subtitleText.Text = 'What will change when you run the selected tweaks.'
		$subtitleText.TextWrapping = 'Wrap'
		$subtitleText.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$subtitleText.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		$subtitleText.FontSize = $layout.FontSizeBody
		[void]($headerStack.Children.Add($subtitleText))

		# Summary bar: color-coded counts
		$summaryPanel = New-Object System.Windows.Controls.WrapPanel
		$summaryPanel.Orientation = 'Horizontal'
		$summaryPanel.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)

		$buildSummaryPill = {
			param([string]$Label, [int]$Count, [string]$BgColor, [string]$FgColor, [string]$BorderColor)
			$pillBorder = New-Object System.Windows.Controls.Border
			$pillBorder.CornerRadius = [System.Windows.CornerRadius]::new($layout.PillCornerRadius)
			$pillBorder.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
			$pillBorder.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
			$pillBorder.Background = $bc.ConvertFromString($BgColor)
			$pillBorder.BorderBrush = $bc.ConvertFromString($BorderColor)
			$pillBorder.BorderThickness = [System.Windows.Thickness]::new(1)

			$pillPanel = New-Object System.Windows.Controls.StackPanel
			$pillPanel.Orientation = 'Horizontal'

			$countBlock = New-Object System.Windows.Controls.TextBlock
			$countBlock.Text = [string]$Count
			$countBlock.FontWeight = [System.Windows.FontWeights]::Bold
			$countBlock.FontSize = $layout.FontSizeBody
			$countBlock.Foreground = $bc.ConvertFromString($FgColor)
			$countBlock.Margin = [System.Windows.Thickness]::new(0, 0, 5, 0)
			[void]($pillPanel.Children.Add($countBlock))

			$labelBlock = New-Object System.Windows.Controls.TextBlock
			$labelBlock.Text = $Label
			$labelBlock.FontSize = $layout.FontSizeLabel
			$labelBlock.Foreground = $bc.ConvertFromString($FgColor)
			$labelBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
			[void]($pillPanel.Children.Add($labelBlock))

			$pillBorder.Child = $pillPanel
			return $pillBorder
		}

		[void]($summaryPanel.Children.Add((& $buildSummaryPill -Label 'Will change' -Count $willChangeCount -BgColor $theme.StatusPillBg -FgColor $theme.StatusPillText -BorderColor $theme.StatusPillBorder)))
		[void]($summaryPanel.Children.Add((& $buildSummaryPill -Label 'Already set' -Count $alreadySetCount -BgColor $theme.LowRiskBadgeBg -FgColor $theme.LowRiskBadge -BorderColor $theme.LowRiskBadge)))
		if ($restartCount -gt 0)
		{
			[void]($summaryPanel.Children.Add((& $buildSummaryPill -Label 'Requires restart' -Count $restartCount -BgColor $theme.RiskMediumBadgeBg -FgColor $theme.RiskMediumBadge -BorderColor $theme.RiskMediumBadge)))
		}

		[void]($headerStack.Children.Add($summaryPanel))
		$headerBorder.Child = $headerStack
		[void]($outerGrid.Children.Add($headerBorder))

		# ── Row 1: Scrollable tweak diff list ──
		$listScroll = New-Object System.Windows.Controls.ScrollViewer
		$listScroll.VerticalScrollBarVisibility = 'Auto'
		$listScroll.HorizontalScrollBarVisibility = 'Disabled'
		$listScroll.Margin = [System.Windows.Thickness]::new(0)
		[System.Windows.Controls.Grid]::SetRow($listScroll, 1)

		$listStack = New-Object System.Windows.Controls.StackPanel
		$listStack.Orientation = 'Vertical'
		$listStack.Margin = [System.Windows.Thickness]::new(18, 16, 18, 16)

		# Pre-compute brushes for performance
		$brushCardBg        = $bc.ConvertFromString($theme.CardBg)
		$brushCardBorder    = $bc.ConvertFromString($theme.CardBorder)
		$brushTextPrimary   = $bc.ConvertFromString($theme.TextPrimary)
		$brushTextSecondary = $bc.ConvertFromString($theme.TextSecondary)
		$brushTextMuted     = $bc.ConvertFromString($theme.TextMuted)
		$brushSectionLabel  = $bc.ConvertFromString($theme.SectionLabel)
		$brushAccentBlue    = $bc.ConvertFromString($theme.AccentBlue)
		$brushToggleOn      = $bc.ConvertFromString($theme.ToggleOn)
		$brushStateDisabled = $bc.ConvertFromString($theme.StateDisabled)
		$brushCautionBorder = $bc.ConvertFromString($theme.CautionBorder)
		$brushCautionText   = $bc.ConvertFromString($theme.CautionText)

		# Green tint for rows that will change
		$brushChangeBg      = $bc.ConvertFromString($theme.LowRiskBadgeBg)
		$brushChangeBorder  = $bc.ConvertFromString($theme.LowRiskBadge)
		# Orange accent for restart-required
		$brushRestartBorder = $bc.ConvertFromString($theme.RiskMediumBadge)
		# Muted background for already-set rows
		$brushAlreadyBg     = $bc.ConvertFromString($theme.TabBg)
		$brushAlreadyBorder = $bc.ConvertFromString($theme.BorderColor)

		# Type badge color map
		$typeBadgeBrushes = @{
			'Success' = @{ Bg = $bc.ConvertFromString($theme.LowRiskBadgeBg); Fg = $bc.ConvertFromString($theme.LowRiskBadge); Border = $bc.ConvertFromString($theme.LowRiskBadge) }
			'Primary' = @{ Bg = $bc.ConvertFromString($theme.StatusPillBg); Fg = $bc.ConvertFromString($theme.StatusPillText); Border = $bc.ConvertFromString($theme.StatusPillBorder) }
			'Caution' = @{ Bg = $bc.ConvertFromString($theme.RiskMediumBadgeBg); Fg = $bc.ConvertFromString($theme.RiskMediumBadge); Border = $bc.ConvertFromString($theme.RiskMediumBadge) }
			'Danger'  = @{ Bg = $bc.ConvertFromString($theme.RiskHighBadgeBg); Fg = $bc.ConvertFromString($theme.RiskHighBadge); Border = $bc.ConvertFromString($theme.RiskHighBadge) }
			'Muted'   = @{ Bg = $bc.ConvertFromString($theme.TabBg); Fg = $bc.ConvertFromString($theme.TextSecondary); Border = $bc.ConvertFromString($theme.BorderColor) }
		}

		# Arrow glyph used between current and target states
		$arrowGlyph = [char]0x2192  # Unicode right arrow

		# Group items by category
		$grouped = $items | Group-Object -Property Category | Sort-Object -Property Name

		try { $listStack.BeginInit() } catch { <# non-fatal #> }

		foreach ($group in $grouped)
		{
			# ── Category section header (collapsible) ──
			$sectionExpander = New-Object System.Windows.Controls.Expander
			$sectionExpander.IsExpanded = $true
			$sectionExpander.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

			# Custom header with category name and count
			$sectionHeaderPanel = New-Object System.Windows.Controls.StackPanel
			$sectionHeaderPanel.Orientation = 'Horizontal'

			$sectionLabel = New-Object System.Windows.Controls.TextBlock
			$sectionLabel.Text = ([string]$group.Name).ToUpperInvariant()
			$sectionLabel.FontSize = $layout.FontSizeLabel
			$sectionLabel.FontWeight = [System.Windows.FontWeights]::Bold
			$sectionLabel.Foreground = $brushSectionLabel
			$sectionLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
			[void]($sectionHeaderPanel.Children.Add($sectionLabel))

			$sectionCountLabel = New-Object System.Windows.Controls.TextBlock
			$sectionCountLabel.Text = " ($($group.Count))"
			$sectionCountLabel.FontSize = $layout.FontSizeLabel
			$sectionCountLabel.Foreground = $brushTextMuted
			$sectionCountLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
			[void]($sectionHeaderPanel.Children.Add($sectionCountLabel))

			$sectionExpander.Header = $sectionHeaderPanel

			# Content stack for this category's tweaks
			$categoryStack = New-Object System.Windows.Controls.StackPanel
			$categoryStack.Orientation = 'Vertical'
			$categoryStack.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)

			foreach ($diff in $group.Group)
			{
				# ── Individual tweak row ──
				$rowBorder = New-Object System.Windows.Controls.Border
				$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new($layout.CardCornerRadius)
				$rowBorder.Padding = [System.Windows.Thickness]::new(14, 10, 14, 10)
				$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

				if ($diff.WillChange)
				{
					$rowBorder.Background = $brushChangeBg
					if ($diff.RequiresRestart)
					{
						$rowBorder.BorderBrush = $brushRestartBorder
						$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1, 1, 1, 1)
					}
					else
					{
						$rowBorder.BorderBrush = $brushChangeBorder
						$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)
					}
				}
				else
				{
					$rowBorder.Background = $brushAlreadyBg
					$rowBorder.BorderBrush = $brushAlreadyBorder
					$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)
				}

				$rowStack = New-Object System.Windows.Controls.StackPanel
				$rowStack.Orientation = 'Vertical'

				# Top row: Name + Type badge
				$topGrid = New-Object System.Windows.Controls.Grid
				[void]($topGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
				[void]($topGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))

				$nameBlock = New-Object System.Windows.Controls.TextBlock
				$nameBlock.Text = [string]$diff.Name
				$nameBlock.FontSize = $layout.FontSizeBody
				$nameBlock.FontWeight = [System.Windows.FontWeights]::Bold
				$nameBlock.TextWrapping = 'Wrap'
				$nameBlock.Foreground = $brushTextPrimary
				$nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
				[void]($topGrid.Children.Add($nameBlock))

				# Type badge pill
				$badgeBorder = New-Object System.Windows.Controls.Border
				$badgeBorder.CornerRadius = [System.Windows.CornerRadius]::new($layout.PillCornerRadius)
				$badgeBorder.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
				$badgeBorder.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
				$badgeBorder.BorderThickness = [System.Windows.Thickness]::new(1)

				$badgeToneKey = if ($typeBadgeBrushes.ContainsKey([string]$diff.TypeTone)) { [string]$diff.TypeTone } else { 'Muted' }
				$badgeBrushSet = $typeBadgeBrushes[$badgeToneKey]
				$badgeBorder.Background = $badgeBrushSet.Bg
				$badgeBorder.BorderBrush = $badgeBrushSet.Border

				$badgeText = New-Object System.Windows.Controls.TextBlock
				$badgeText.Text = [string]$diff.TypeBadge
				$badgeText.FontSize = $layout.FontSizeTiny
				$badgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
				$badgeText.Foreground = $badgeBrushSet.Fg
				$badgeBorder.Child = $badgeText

				[System.Windows.Controls.Grid]::SetColumn($badgeBorder, 1)
				[void]($topGrid.Children.Add($badgeBorder))
				[void]($rowStack.Children.Add($topGrid))

				# State transition row: Current -> Target
				$transitionPanel = New-Object System.Windows.Controls.WrapPanel
				$transitionPanel.Orientation = 'Horizontal'
				$transitionPanel.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)

				if ($diff.WillChange)
				{
					switch ($diff.Type)
					{
						'Toggle'
						{
							$currentBlock = New-Object System.Windows.Controls.TextBlock
							$currentBlock.Text = [string]$diff.CurrentDisplay
							$currentBlock.FontSize = $layout.FontSizeLabel
							$currentBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
							$currentBlock.Foreground = $brushStateDisabled
							$currentBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($currentBlock))

							$arrowBlock = New-Object System.Windows.Controls.TextBlock
							$arrowBlock.Text = " $arrowGlyph "
							$arrowBlock.FontSize = $layout.FontSizeBody
							$arrowBlock.Foreground = $brushAccentBlue
							$arrowBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($arrowBlock))

							$targetBlock = New-Object System.Windows.Controls.TextBlock
							$targetBlock.Text = [string]$diff.PlannedDisplay
							$targetBlock.FontSize = $layout.FontSizeLabel
							$targetBlock.FontWeight = [System.Windows.FontWeights]::Bold
							$targetBlock.Foreground = $brushToggleOn
							$targetBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($targetBlock))
						}
						'Choice'
						{
							$currentLabel = New-Object System.Windows.Controls.TextBlock
							$currentLabel.Text = "Current: "
							$currentLabel.FontSize = $layout.FontSizeLabel
							$currentLabel.Foreground = $brushTextMuted
							$currentLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($currentLabel))

							$currentVal = New-Object System.Windows.Controls.TextBlock
							$currentVal.Text = [string]$diff.CurrentDisplay
							$currentVal.FontSize = $layout.FontSizeLabel
							$currentVal.FontWeight = [System.Windows.FontWeights]::SemiBold
							$currentVal.Foreground = $brushStateDisabled
							$currentVal.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($currentVal))

							$arrowBlock = New-Object System.Windows.Controls.TextBlock
							$arrowBlock.Text = " $arrowGlyph "
							$arrowBlock.FontSize = $layout.FontSizeBody
							$arrowBlock.Foreground = $brushAccentBlue
							$arrowBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($arrowBlock))

							$targetLabel = New-Object System.Windows.Controls.TextBlock
							$targetLabel.Text = "Target: "
							$targetLabel.FontSize = $layout.FontSizeLabel
							$targetLabel.Foreground = $brushTextMuted
							$targetLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($targetLabel))

							$targetVal = New-Object System.Windows.Controls.TextBlock
							$targetVal.Text = [string]$diff.PlannedDisplay
							$targetVal.FontSize = $layout.FontSizeLabel
							$targetVal.FontWeight = [System.Windows.FontWeights]::Bold
							$targetVal.Foreground = $brushToggleOn
							$targetVal.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($targetVal))
						}
						'Action'
						{
							$actionLabel = New-Object System.Windows.Controls.TextBlock
							$actionLabel.Text = "Will run: "
							$actionLabel.FontSize = $layout.FontSizeLabel
							$actionLabel.Foreground = $brushTextMuted
							$actionLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($actionLabel))

							$actionName = New-Object System.Windows.Controls.TextBlock
							$actionName.Text = [string]$diff.PlannedDisplay
							$actionName.FontSize = $layout.FontSizeLabel
							$actionName.FontWeight = [System.Windows.FontWeights]::Bold
							$actionName.Foreground = $brushAccentBlue
							$actionName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($actionName))
						}
						default
						{
							$genericCurrent = New-Object System.Windows.Controls.TextBlock
							$genericCurrent.Text = [string]$diff.CurrentDisplay
							$genericCurrent.FontSize = $layout.FontSizeLabel
							$genericCurrent.Foreground = $brushStateDisabled
							$genericCurrent.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($genericCurrent))

							$arrowBlock = New-Object System.Windows.Controls.TextBlock
							$arrowBlock.Text = " $arrowGlyph "
							$arrowBlock.FontSize = $layout.FontSizeBody
							$arrowBlock.Foreground = $brushAccentBlue
							$arrowBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($arrowBlock))

							$genericTarget = New-Object System.Windows.Controls.TextBlock
							$genericTarget.Text = [string]$diff.PlannedDisplay
							$genericTarget.FontSize = $layout.FontSizeLabel
							$genericTarget.FontWeight = [System.Windows.FontWeights]::Bold
							$genericTarget.Foreground = $brushToggleOn
							$genericTarget.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
							[void]($transitionPanel.Children.Add($genericTarget))
						}
					}

					# Restart badge if required
					if ($diff.RequiresRestart)
					{
						$restartBadge = New-Object System.Windows.Controls.Border
						$restartBadge.CornerRadius = [System.Windows.CornerRadius]::new($layout.PillCornerRadius)
						$restartBadge.Padding = [System.Windows.Thickness]::new(7, 2, 7, 2)
						$restartBadge.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
						$restartBadge.Background = $bc.ConvertFromString($theme.RiskMediumBadgeBg)
						$restartBadge.BorderBrush = $brushCautionBorder
						$restartBadge.BorderThickness = [System.Windows.Thickness]::new(1)

						$restartText = New-Object System.Windows.Controls.TextBlock
						$restartText.Text = 'Restart'
						$restartText.FontSize = $layout.FontSizeTiny
						$restartText.FontWeight = [System.Windows.FontWeights]::SemiBold
						$restartText.Foreground = $brushCautionText
						$restartBadge.Child = $restartText
						[void]($transitionPanel.Children.Add($restartBadge))
					}
				}
				else
				{
					# Already set - muted display
					$alreadyBlock = New-Object System.Windows.Controls.TextBlock
					$alreadyBlock.Text = 'Already set (no change)'
					$alreadyBlock.FontSize = $layout.FontSizeLabel
					$alreadyBlock.FontStyle = [System.Windows.FontStyles]::Italic
					$alreadyBlock.Foreground = $brushTextMuted
					$alreadyBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
					[void]($transitionPanel.Children.Add($alreadyBlock))
				}

				[void]($rowStack.Children.Add($transitionPanel))
				$rowBorder.Child = $rowStack
				[void]($categoryStack.Children.Add($rowBorder))
			}

			$sectionExpander.Content = $categoryStack
			[void]($listStack.Children.Add($sectionExpander))
		}

		try { $listStack.EndInit() } catch { <# non-fatal #> }
		$listScroll.Content = $listStack
		[void]($outerGrid.Children.Add($listScroll))

		# ── Row 2: Button bar ──
		$buttonBorder = New-Object System.Windows.Controls.Border
		$buttonBorder.Background = $bc.ConvertFromString($theme.PanelBg)
		$buttonBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
		$buttonBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
		$buttonBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
		[System.Windows.Controls.Grid]::SetRow($buttonBorder, 2)

		$buttonPanel = New-Object System.Windows.Controls.StackPanel
		$buttonPanel.Orientation = 'Horizontal'
		$buttonPanel.HorizontalAlignment = 'Right'

		$btnClose = New-Object System.Windows.Controls.Button
		$btnClose.Content = 'Close'
		$btnClose.MinWidth = $layout.ButtonMinWidth
		$btnClose.Height = $layout.ButtonHeight
		$btnClose.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btnClose.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)
		$btnClose.IsDefault = $true
		$btnClose.IsCancel = $true
		Set-ButtonChrome -Button $btnClose -Variant 'Primary'

		$dlgRef = $dlg
		$btnClose.Add_Click({ $dlgRef.Close() }.GetNewClosure())
		[void]($buttonPanel.Children.Add($btnClose))

		$buttonBorder.Child = $buttonPanel
		[void]($outerGrid.Children.Add($buttonBorder))

		Complete-RoundedWindow -Window $dlg -ContentElement $outerGrid -RoundBorder $roundedParts.RoundBorder -DockPanel $roundedParts.DockPanel
		[void]($dlg.ShowDialog())
		return 'Close'
	}

	function Show-DiffViewFromSelection
	{
		<# .SYNOPSIS Convenience wrapper: builds diff data from the current selection and opens the diff dialog. #>
		param (
			[Parameter(Mandatory = $true)]
			[object[]]$SelectedTweaks
		)

		$diffData = Build-TweakDiffData -SelectedTweaks $SelectedTweaks
		if ($diffData.Count -eq 0)
		{
			Show-ThemedDialog -Title 'Diff View' -Message 'No tweaks selected to compare.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		Show-DiffViewDialog -DiffData $diffData
	}
