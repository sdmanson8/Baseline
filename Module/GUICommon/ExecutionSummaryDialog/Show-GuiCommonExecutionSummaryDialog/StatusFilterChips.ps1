if (-not $isPreviewModeForFilter -and @($Results).Count -gt 0)
	{
		# Count results by status category for filter pills
		$statusCounts = [ordered]@{
			'Success'         = @(@($Results) | Where-Object { [string]$_.Status -eq 'Success' }).Count
			'Skipped'         = @(@($Results) | Where-Object { [string]$_.Status -eq 'Skipped' -or [string]$_.Status -eq 'Not applicable' -or [string]$_.Status -eq 'Not Run' }).Count
			'Failed'          = @(@($Results) | Where-Object { [string]$_.Status -eq 'Failed' }).Count
			'Restart pending' = @(@($Results) | Where-Object { [string]$_.Status -eq 'Restart pending' }).Count
		}

		$filterBarBorder = New-Object System.Windows.Controls.Border
		$filterBarBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$filterBarBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		$filterBarBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$filterBarBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$filterBarBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
		$filterBarBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)

		$filterBarPanel = New-Object System.Windows.Controls.WrapPanel
		$filterBarPanel.Orientation = 'Horizontal'
		$filterBarPanel.HorizontalAlignment = 'Left'

		# "All" pill
		$allPillBtn = New-Object System.Windows.Controls.Button
		$allResultsLabel = if ($Strings.ContainsKey('AllResultsPrefix')) { [string]$Strings.AllResultsPrefix } else { 'All' }
		$allPillBtn.Content = "{0}: {1}" -f $allResultsLabel, $Results.Count
		$allPillBtn.Margin = [System.Windows.Thickness]::new(0, 2, 8, 2)
		$allPillBtn.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
		$allPillBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		$allPillBtn.FontSize = $Script:GuiLayout.FontSizeLabel
		$allPillBtn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$allPillBtn.BorderThickness = [System.Windows.Thickness]::new(1)
		& $ApplyButtonChrome -Button $allPillBtn -Variant 'Primary'
		$filterPillButtons['All'] = $allPillBtn
		[void]($filterBarPanel.Children.Add($allPillBtn))

		$filterPillColorMap = @{
			'Success'         = @{ Bg = $Theme.LowRiskBadgeBg; Border = $Theme.LowRiskBadge; Fg = $Theme.LowRiskBadge }
			'Skipped'         = @{ Bg = $Theme.TabBg; Border = $Theme.BorderColor; Fg = $Theme.TextSecondary }
			'Failed'          = @{ Bg = $Theme.RiskHighBadgeBg; Border = $Theme.RiskHighBadge; Fg = $Theme.RiskHighBadge }
			'Restart pending' = @{ Bg = $Theme.RiskMediumBadgeBg; Border = $Theme.RiskMediumBadge; Fg = $Theme.RiskMediumBadge }
		}

		foreach ($filterKey in $statusCounts.Keys)
		{
			$count = $statusCounts[$filterKey]
			if ($count -eq 0) { continue }
			$pillBtn = New-Object System.Windows.Controls.Button
			$displayLabel = $filterKey.ToUpperInvariant()
			$pillBtn.Content = "${displayLabel}: $count"
			$pillBtn.Margin = [System.Windows.Thickness]::new(0, 2, 8, 2)
			$pillBtn.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
			$pillBtn.Cursor = [System.Windows.Input.Cursors]::Hand
			$pillBtn.FontSize = $Script:GuiLayout.FontSizeLabel
			$pillBtn.FontWeight = [System.Windows.FontWeights]::SemiBold
			$pillBtn.BorderThickness = [System.Windows.Thickness]::new(1)
			$pillColors = $filterPillColorMap[$filterKey]
			$pillBtn.Background = $bc.ConvertFromString($pillColors.Bg)
			$pillBtn.BorderBrush = $bc.ConvertFromString($pillColors.Border)
			$pillBtn.Foreground = $bc.ConvertFromString($pillColors.Fg)
			$filterPillButtons[$filterKey] = $pillBtn
			[void]($filterBarPanel.Children.Add($pillBtn))
		}

		$filterBarBorder.Child = $filterBarPanel
		[void]($listStack.Children.Add($filterBarBorder))

		# Wire up click handlers (after all pills created so closures can reference them)
		$capturedFilterActiveRef = $statusFilterActiveRef
		$capturedFilterPillButtons = $filterPillButtons
		$capturedAllResultCards = $allResultCards
		$capturedAllResultStatusMap = $allResultStatusMap
		$capturedApplyChrome = $ApplyButtonChrome
		$capturedFilterPillColorMap = $filterPillColorMap
		$capturedBcFilter = $bc

		$applyFilterAction = {
			param([string]$SelectedFilter)
			# Update active filter
			if ($SelectedFilter -eq 'All' -or $capturedFilterActiveRef.Value -eq $SelectedFilter)
			{
				$capturedFilterActiveRef.Value = $null
			}
			else
			{
				$capturedFilterActiveRef.Value = $SelectedFilter
			}

			# Restyle pills: active filter gets Primary chrome, others revert
			foreach ($key in @($capturedFilterPillButtons.Keys))
			{
				$btn = $capturedFilterPillButtons[$key]
				if ($key -eq 'All')
				{
					if ($null -eq $capturedFilterActiveRef.Value)
					{
						& $capturedApplyChrome -Button $btn -Variant 'Primary'
					}
					else
					{
						& $capturedApplyChrome -Button $btn -Variant 'Subtle'
					}
				}
				else
				{
					$colors = $capturedFilterPillColorMap[$key]
					if ($key -eq $capturedFilterActiveRef.Value)
					{
						# Active: brighter border
						$btn.Background = $capturedBcFilter.ConvertFromString($colors.Border)
						$btn.Foreground = $capturedBcFilter.ConvertFromString('#FFFFFF')
						$btn.BorderBrush = $capturedBcFilter.ConvertFromString($colors.Border)
					}
					else
					{
						$btn.Background = $capturedBcFilter.ConvertFromString($colors.Bg)
						$btn.Foreground = $capturedBcFilter.ConvertFromString($colors.Fg)
						$btn.BorderBrush = $capturedBcFilter.ConvertFromString($colors.Border)
					}
				}
			}

			# Show/hide result cards based on filter
			for ($fi = 0; $fi -lt $capturedAllResultCards.Count; $fi++)
			{
				$card = $capturedAllResultCards[$fi]
				$cardStatus = $capturedAllResultStatusMap[$fi]
				if ($null -eq $capturedFilterActiveRef.Value -or $cardStatus -eq $capturedFilterActiveRef.Value)
				{
					$card.Visibility = [System.Windows.Visibility]::Visible
				}
				else
				{
					$card.Visibility = [System.Windows.Visibility]::Collapsed
				}
			}
		}

		$capturedApplyFilter = $applyFilterAction

		# "All" pill click
		$allPillBtn.Add_Click({
			& $capturedApplyFilter 'All'
		}.GetNewClosure())

		# Status pill clicks
		foreach ($filterKey in $statusCounts.Keys)
		{
			$count = $statusCounts[$filterKey]
			if ($count -eq 0) { continue }
			$btn = $filterPillButtons[$filterKey]
			$capturedKey = $filterKey
			$btn.Add_Click({
				& $capturedApplyFilter $capturedKey
			}.GetNewClosure())
		}
	}
