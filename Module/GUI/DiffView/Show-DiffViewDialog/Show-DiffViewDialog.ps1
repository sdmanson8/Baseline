foreach ($group in $grouped)
		{
			# -- Category section header (collapsible) --
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
				# -- Individual tweak row --
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

				$rowIconName = if ($diff.WillChange)
				{
					if ($diff.RequiresRestart) { 'RestartRequired' } else { 'WillChange' }
				}
				else
				{
					'AlreadySet'
				}

				$namePanel = New-Object System.Windows.Controls.StackPanel
				$namePanel.Orientation = 'Horizontal'
				$namePanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				$namePanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch

				$nameIcon = New-GuiIconTextBlock -IconName $rowIconName -Size 16 -Foreground $brushTextPrimary -VerticalAlignment 'Center'
				if ($nameIcon)
				{
					$nameIcon.Margin = [System.Windows.Thickness]::new(0, 1, 8, 0)
					[void]($namePanel.Children.Add($nameIcon))
				}

				$nameBlock = New-Object System.Windows.Controls.TextBlock
				$nameBlock.Text = [string]$diff.Name
				$nameBlock.FontSize = $layout.FontSizeBody
				$nameBlock.FontWeight = [System.Windows.FontWeights]::Bold
				$nameBlock.TextWrapping = 'Wrap'
				$nameBlock.Foreground = $brushTextPrimary
				$nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				[void]($namePanel.Children.Add($nameBlock))

				[System.Windows.Controls.Grid]::SetColumn($namePanel, 0)
				[void]($topGrid.Children.Add($namePanel))

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
							$currentLabel.Text = (Get-UxLocalizedString -Key 'GuiDiffCurrentPrefix' -Fallback 'Current: ')
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
							$targetLabel.Text = (Get-UxLocalizedString -Key 'GuiDiffTargetPrefix' -Fallback 'Target: ')
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
							$actionLabel.Text = (Get-UxLocalizedString -Key 'GuiDiffWillRunPrefix' -Fallback 'Will run: ')
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
						$restartText.Text = (Get-UxLocalizedString -Key 'GuiDiffRestart' -Fallback 'Restart')
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
					$alreadyBlock.Text = (Get-UxLocalizedString -Key 'GuiDiffAlreadySetNoChange' -Fallback 'Already set (no change)')
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
