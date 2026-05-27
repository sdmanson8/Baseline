if ($resultIndex -eq $initialBatchLimit -and $totalResultCount -gt $initialBatchLimit)
	{
		$remainingCount = $totalResultCount - $initialBatchLimit
		$remainingResults = @($displayResults | Select-Object -Skip $initialBatchLimit)
		$showAllBtn = New-Object System.Windows.Controls.Button
		$showAllResultsFormat = if ($Strings.ContainsKey('ShowAllResultsFormat')) { [string]$Strings.ShowAllResultsFormat } else { 'Show all {0} results ({1} more)' }
		$showAllBtn.Content = ($showAllResultsFormat -f $totalResultCount, $remainingCount)
		$showAllBtn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
		$showAllBtn.Margin = [System.Windows.Thickness]::new(0, 4, 0, 10)
		$showAllBtn.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
		$showAllBtn.FontSize = $Script:GuiLayout.FontSizeBody
		$showAllBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		& $ApplyButtonChrome -Button $showAllBtn -Variant 'Subtle'

		# Capture all the pre-computed brush/layout variables for the deferred build.
		$capturedListStack = $listStack
		$capturedBc = $bc
		$capturedTheme = $Theme
		$capturedIsPreviewMode = $isPreviewMode
		$capturedHasPreviewGroups = $hasPreviewGroups
		$capturedLastPreviewSection = $lastPreviewSection
		$capturedPreStatusBrushes = $preStatusBrushes
		$capturedPreDefaultStatusBrushes = $preDefaultStatusBrushes
		$capturedPreThickness1 = $preThickness1
		$capturedPreBrushCardBg = $preBrushCardBg
		$capturedPreBrushCardBorder = $preBrushCardBorder
		$capturedPreBrushTextPrimary = $preBrushTextPrimary
		$capturedPreBrushTextSecondary = $preBrushTextSecondary
		$capturedPreBrushTextMuted = $preBrushTextMuted
		$capturedPreBrushSectionLabel = $preBrushSectionLabel
		$capturedPreBrushCautionText = $preBrushCautionText

		$showAllBtn.Add_Click({
			$showAllBtn.Visibility = [System.Windows.Visibility]::Collapsed

			# Alias captured variables for the same names used in the card-building code.
			$bc = $capturedBc
			$Theme = $capturedTheme
			$isPreviewMode = $capturedIsPreviewMode
			$hasPreviewGroups = $capturedHasPreviewGroups
			$lastPreviewSection = $capturedLastPreviewSection
			$preStatusBrushes = $capturedPreStatusBrushes
			$preDefaultStatusBrushes = $capturedPreDefaultStatusBrushes
			$preThickness1 = $capturedPreThickness1
			$preBrushCardBg = $capturedPreBrushCardBg
			$preBrushCardBorder = $capturedPreBrushCardBorder
			$preBrushTextPrimary = $capturedPreBrushTextPrimary
			$preBrushTextSecondary = $capturedPreBrushTextSecondary
			$preBrushTextMuted = $capturedPreBrushTextMuted
			$preBrushSectionLabel = $capturedPreBrushSectionLabel
			$preBrushCautionText = $capturedPreBrushCautionText

			try { $capturedListStack.BeginInit() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionSummaryDialog.Show-GuiCommonExecutionSummaryDialog.CapturedListStackBeginInit' }
			foreach ($result in $remainingResults)
			{
				if ($isPreviewMode)
				{
					$sectionLabel = if ($hasPreviewGroups -and (Test-GuiCommonObjectField -Object $result -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$result.PreviewGroupHeader)) {
						[string]$result.PreviewGroupHeader
					}
					elseif ([string]::IsNullOrWhiteSpace([string]$result.Status)) {
						'Will change'
					}
					else {
						[string]$result.Status
					}
					if ($sectionLabel -ne $lastPreviewSection)
					{
						$sectionHeader = New-Object System.Windows.Controls.TextBlock
						$sectionHeader.Text = $sectionLabel.ToUpperInvariant()
						$sectionHeader.FontSize = $Script:GuiLayout.FontSizeLabel
						$sectionHeader.FontWeight = [System.Windows.FontWeights]::Bold
						$sectionHeader.Foreground = $preBrushSectionLabel
						$sectionHeader.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
						[void]($capturedListStack.Children.Add($sectionHeader))
						$lastPreviewSection = $sectionLabel
					}
				}

				$rowBorder = New-Object System.Windows.Controls.Border
				$rowBorder.Background = $preBrushCardBg
				$rowBorder.BorderBrush = $preBrushCardBorder
				$rowBorder.BorderThickness = $preThickness1
				$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
				$rowBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
				$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

				$rowStack = New-Object System.Windows.Controls.StackPanel
				$rowStack.Orientation = 'Vertical'

				$nameBlock = New-Object System.Windows.Controls.TextBlock
				$nameBlock.Text = [string]$result.Name
				$nameBlock.FontSize = 13
				$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameBlock.TextWrapping = 'Wrap'
				$nameBlock.Foreground = $preBrushTextPrimary
				[void]($rowStack.Children.Add($nameBlock))

				$statusKey = [string]$result.Status
				$statusBrushSet = if ($preStatusBrushes.ContainsKey($statusKey)) { $preStatusBrushes[$statusKey] } else { $preDefaultStatusBrushes }
				$statusText = New-Object System.Windows.Controls.TextBlock
				$statusText.Text = $statusKey
				$statusText.FontSize = $Script:GuiLayout.FontSizeLabel
				$statusText.Foreground = $statusBrushSet.Fg
				$statusText.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
				[void]($rowStack.Children.Add($statusText))

				if (-not [string]::IsNullOrWhiteSpace([string]$result.Detail))
				{
					$detailBlock = New-Object System.Windows.Controls.TextBlock
					$detailBlock.Text = [string]$result.Detail
					$detailBlock.TextWrapping = 'Wrap'
					$detailBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
					$detailBlock.FontSize = $Script:GuiLayout.FontSizeLabel
					$detailBlock.Foreground = $preBrushTextSecondary
					[void]($rowStack.Children.Add($detailBlock))
				}

				$rowBorder.Child = $rowStack
				[void]($capturedListStack.Children.Add($rowBorder))
			}
			try { $capturedListStack.EndInit() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionSummaryDialog.Show-GuiCommonExecutionSummaryDialog.CapturedListStackEndInit' }
		}.GetNewClosure())

		[void]($listStack.Children.Add($showAllBtn))
	}
