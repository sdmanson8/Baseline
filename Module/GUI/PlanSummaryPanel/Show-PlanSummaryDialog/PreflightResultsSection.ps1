if ($null -ne $PreflightResults -and $null -ne $PreflightResults.AllResults)
	{
		$preflightLabel = New-Object System.Windows.Controls.TextBlock
		$preflightLabel.Text = (Get-UxLocalizedString -Key 'GuiPlanPreflightChecks' -Fallback 'PRE-FLIGHT CHECKS')
		$preflightLabel.FontSize = $Script:GuiLayout.FontSizeLabel
		$preflightLabel.FontWeight = [System.Windows.FontWeights]::Bold
		$preflightLabel.Foreground = $bc.ConvertFromString($theme.SectionLabel)
		$preflightLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($bodyStack.Children.Add($preflightLabel))

		$preflightPanel = New-Object System.Windows.Controls.WrapPanel
		$preflightPanel.Orientation = 'Horizontal'
		$preflightPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)

		foreach ($check in $PreflightResults.AllResults)
		{
			$indicatorBorder = New-Object System.Windows.Controls.Border
			$indicatorBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.BorderRadiusSmall)
			$indicatorBorder.Padding = [System.Windows.Thickness]::new(10, 5, 10, 5)
			$indicatorBorder.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
			$indicatorBorder.BorderThickness = [System.Windows.Thickness]::new(1)

			$indicatorText = New-Object System.Windows.Controls.TextBlock
			$indicatorText.FontSize = $Script:GuiLayout.FontSizeLabel
			$indicatorText.FontWeight = [System.Windows.FontWeights]::SemiBold

			switch ($check.Status)
			{
				'Passed'
				{
					$indicatorBorder.Background = $bc.ConvertFromString($theme.LowRiskBadgeBg)
					$indicatorBorder.BorderBrush = $bc.ConvertFromString($theme.LowRiskBadge)
					$indicatorText.Foreground = $bc.ConvertFromString($theme.LowRiskBadge)
				}
				'Failed'
				{
					$indicatorBorder.Background = $bc.ConvertFromString($theme.RiskHighBadgeBg)
					$indicatorBorder.BorderBrush = $bc.ConvertFromString($theme.RiskHighBadge)
					$indicatorText.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				}
				'Warning'
				{
					$indicatorBorder.Background = $bc.ConvertFromString($theme.RiskMediumBadgeBg)
					$indicatorBorder.BorderBrush = $bc.ConvertFromString($theme.RiskMediumBadge)
					$indicatorText.Foreground = $bc.ConvertFromString($theme.RiskMediumBadge)
				}
			}

			# Use Fluent icon glyph if available, otherwise fall back to Unicode symbols
			$preflightGlyph = $null
			if (Get-Command -Name 'Get-GuiPreflightIconGlyph' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$preflightGlyph = Get-GuiPreflightIconGlyph -Status ([string]$check.Status)
			}
			if ((Get-Command -Name 'Test-GuiIconsAvailable' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-GuiIconsAvailable) -and $preflightGlyph)
			{
				$iconContent = New-GuiLabeledIconContent -IconName $(switch ($check.Status) { 'Passed' { 'Success' } 'Failed' { 'Failed' } 'Warning' { 'Warning' } }) -Text $check.Name -IconSize 12 -Gap 4 -TextFontSize $Script:GuiLayout.FontSizeLabel -Foreground $indicatorText.Foreground -AllowTextOnlyFallback
				if ($iconContent)
				{
					$indicatorBorder.ToolTip = $check.Message
					$indicatorBorder.Child = $iconContent
					[void]($preflightPanel.Children.Add($indicatorBorder))
					continue
				}
			}
			$fallbackSymbol = switch ($check.Status) { 'Passed' { [char]0x2713 } 'Failed' { [char]0x2717 } 'Warning' { [char]0x26A0 } default { '' } }
			$indicatorText.Text = "$fallbackSymbol $($check.Name)"
			$indicatorBorder.ToolTip = $check.Message
			$indicatorBorder.Child = $indicatorText
			[void]($preflightPanel.Children.Add($indicatorBorder))
		}

		[void]($bodyStack.Children.Add($preflightPanel))

		$sepPreImpact = New-Object System.Windows.Controls.Separator
		$sepPreImpact.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
		$sepPreImpact.Background = $bc.ConvertFromString($theme.BorderColor)
		[void]($bodyStack.Children.Add($sepPreImpact))
	}
