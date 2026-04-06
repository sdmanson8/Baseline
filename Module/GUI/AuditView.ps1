# Audit Log Viewer: displays a scrollable timeline of audit log entries
# with filtering and export/clear capabilities.

function Show-AuditLogDialog
{
	$bc = $Script:SharedBrushConverter
	$theme = $Script:CurrentTheme
	$layout = $Script:GuiLayout

	$dlg = New-Object System.Windows.Window
	$dlg.Title = 'Audit Log'
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

	try { if ($Form) { $dlg.Owner = $Form } } catch { }
	$roundedParts = ConvertTo-RoundedWindow -Window $dlg -Theme $theme
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:($Script:CurrentThemeName -eq 'Dark'))

	$rootPanel = New-Object System.Windows.Controls.DockPanel
	$rootPanel.LastChildFill = $true
	$rootPanel.Margin = [System.Windows.Thickness]::new(16)

	# --- Top: filter + action buttons ---
	$topPanel = New-Object System.Windows.Controls.StackPanel
	$topPanel.Orientation = 'Horizontal'
	$topPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	[System.Windows.Controls.DockPanel]::SetDock($topPanel, [System.Windows.Controls.Dock]::Top)

	$filterLabel = New-Object System.Windows.Controls.TextBlock
	$filterLabel.Text = 'Filter:'
	$filterLabel.VerticalAlignment = 'Center'
	$filterLabel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$filterLabel.Foreground = $bc.ConvertFromString($theme.TextPrimary)

	$filterCombo = New-Object System.Windows.Controls.ComboBox
	$filterCombo.MinWidth = 160
	$filterCombo.Height = $layout.ButtonHeight
	$filterCombo.VerticalContentAlignment = 'Center'
	[void]$filterCombo.Items.Add('All')
	[void]$filterCombo.Items.Add('Runs Only')
	[void]$filterCombo.Items.Add('Compliance Only')
	$filterCombo.SelectedIndex = 0

	$btnExport = New-Object System.Windows.Controls.Button
	$btnExport.Content = 'Export Report'
	$btnExport.MinWidth = $layout.ButtonMinWidth
	$btnExport.Height = $layout.ButtonHeight
	$btnExport.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
	$btnExport.FontWeight = [System.Windows.FontWeights]::SemiBold
	Set-ButtonChrome -Button $btnExport -Variant 'Primary'

	$btnClear = New-Object System.Windows.Controls.Button
	$btnClear.Content = 'Clear Old Entries'
	$btnClear.MinWidth = $layout.ButtonMinWidth
	$btnClear.Height = $layout.ButtonHeight
	$btnClear.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
	$btnClear.FontWeight = [System.Windows.FontWeights]::SemiBold
	Set-ButtonChrome -Button $btnClear -Variant 'Danger'

	[void]$topPanel.Children.Add($filterLabel)
	[void]$topPanel.Children.Add($filterCombo)
	[void]$topPanel.Children.Add($btnExport)
	[void]$topPanel.Children.Add($btnClear)
	[void]$rootPanel.Children.Add($topPanel)

	# --- Bottom: close button ---
	$bottomPanel = New-Object System.Windows.Controls.StackPanel
	$bottomPanel.Orientation = 'Horizontal'
	$bottomPanel.HorizontalAlignment = 'Right'
	$bottomPanel.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
	[System.Windows.Controls.DockPanel]::SetDock($bottomPanel, [System.Windows.Controls.Dock]::Bottom)

	$btnClose = New-Object System.Windows.Controls.Button
	$btnClose.Content = 'Close'
	$btnClose.MinWidth = $layout.ButtonMinWidth
	$btnClose.Height = $layout.ButtonHeight
	$btnClose.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnClose.IsCancel = $true
	Set-ButtonChrome -Button $btnClose -Variant 'Secondary'
	$btnClose.Add_Click({ $dlg.Close() })

	[void]$bottomPanel.Children.Add($btnClose)
	[void]$rootPanel.Children.Add($bottomPanel)

	# --- Center: scrollable timeline ---
	$scrollViewer = New-Object System.Windows.Controls.ScrollViewer
	$scrollViewer.VerticalScrollBarVisibility = 'Auto'
	$scrollViewer.HorizontalScrollBarVisibility = 'Disabled'

	$timelinePanel = New-Object System.Windows.Controls.StackPanel
	$timelinePanel.Orientation = 'Vertical'
	$scrollViewer.Content = $timelinePanel

	[void]$rootPanel.Children.Add($scrollViewer)

	Complete-RoundedWindow -Window $dlg -ContentElement $rootPanel -RoundBorder $roundedParts.RoundBorder -DockPanel $roundedParts.DockPanel

	# --- Populate timeline function ---
	$populateTimeline = {
		param ([string]$FilterMode)

		$timelinePanel.Children.Clear()

		$getParams = @{ MaxRecords = 500 }
		$filterAction = $null
		switch ($FilterMode)
		{
			'Runs Only'       { $getParams['Action'] = 'Run' }
			'Compliance Only' { $getParams['Action'] = 'Compliance' }
		}

		$records = @(Get-AuditLog @getParams)

		if ($records.Count -eq 0)
		{
			$emptyLabel = New-Object System.Windows.Controls.TextBlock
			$emptyLabel.Text = 'No audit log entries found.'
			$emptyLabel.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$emptyLabel.HorizontalAlignment = 'Center'
			$emptyLabel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)
			[void]$timelinePanel.Children.Add($emptyLabel)
			return
		}

		# Show records in reverse chronological order (newest first)
		$sortedRecords = @($records | Sort-Object { try { [datetime]::Parse($_.Timestamp) } catch { [datetime]::MinValue } } -Descending)

		foreach ($rec in $sortedRecords)
		{
			$card = New-Object System.Windows.Controls.Border
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
			$card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
			$card.CornerRadius = [System.Windows.CornerRadius]::new($layout.CardCornerRadius)
			$card.BorderThickness = [System.Windows.Thickness]::new(1)
			$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$card.Background = $bc.ConvertFromString($theme.PanelBg)

			$cardStack = New-Object System.Windows.Controls.StackPanel
			$cardStack.Orientation = 'Vertical'

			# Header row: timestamp + action + mode
			$headerRow = New-Object System.Windows.Controls.StackPanel
			$headerRow.Orientation = 'Horizontal'

			$tsText = '(unknown)'
			if ($rec.Timestamp)
			{
				try { $tsText = ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch { $tsText = [string]$rec.Timestamp }
			}

			$tsBlock = New-Object System.Windows.Controls.TextBlock
			$tsBlock.Text = $tsText
			$tsBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$tsBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$tsBlock.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)

			$actionBlock = New-Object System.Windows.Controls.TextBlock
			$actionBlock.Text = [string]$rec.Action
			$actionBlock.Foreground = $bc.ConvertFromString($theme.AccentBlue)
			$actionBlock.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)

			$modeBlock = New-Object System.Windows.Controls.TextBlock
			$modeBlock.Text = "Mode: $([string]$rec.Mode)"
			$modeBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$modeBlock.FontSize = $layout.FontSizeSmall

			[void]$headerRow.Children.Add($tsBlock)
			[void]$headerRow.Children.Add($actionBlock)
			[void]$headerRow.Children.Add($modeBlock)
			[void]$cardStack.Children.Add($headerRow)

			# Details row: applied/failed counts, duration
			$detailParts = [System.Collections.Generic.List[string]]::new()
			if ($rec.Results)
			{
				$applied = [int]$(if ($rec.Results.PSObject.Properties['AppliedCount']) { $rec.Results.AppliedCount } else { 0 })
				$failed = [int]$(if ($rec.Results.PSObject.Properties['FailedCount']) { $rec.Results.FailedCount } else { 0 })
				[void]$detailParts.Add("Applied: $applied")
				[void]$detailParts.Add("Failed: $failed")
			}
			if ($rec.DurationSeconds)
			{
				[void]$detailParts.Add("Duration: $($rec.DurationSeconds)s")
			}
			if ($rec.PresetName)
			{
				[void]$detailParts.Add("Preset: $($rec.PresetName)")
			}

			if ($detailParts.Count -gt 0)
			{
				$detailBlock = New-Object System.Windows.Controls.TextBlock
				$detailBlock.Text = ($detailParts -join '  |  ')
				$detailBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				$detailBlock.FontSize = $layout.FontSizeSmall
				$detailBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
				[void]$cardStack.Children.Add($detailBlock)
			}

			$card.Child = $cardStack
			[void]$timelinePanel.Children.Add($card)
		}
	}.GetNewClosure()

	# Initial populate
	& $populateTimeline -FilterMode 'All'

	# --- Filter change handler ---
	$filterCombo.Add_SelectionChanged({
		$selected = [string]$filterCombo.SelectedItem
		& $populateTimeline -FilterMode $selected
	}.GetNewClosure())

	# --- Export handler ---
	$btnExport.Add_Click({
		$saveDialog = New-Object Microsoft.Win32.SaveFileDialog
		$saveDialog.Title = 'Export Audit Report'
		$saveDialog.Filter = 'Markdown Files (*.md)|*.md|HTML Files (*.html)|*.html|All Files (*.*)|*.*'
		$saveDialog.DefaultExt = 'md'
		$saveDialog.FileName = 'Baseline-AuditReport-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss')

		$dlgOwner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($saveDialog.ShowDialog($dlgOwner) -ne $true) { return }

		$outputPath = $saveDialog.FileName
		$format = if ($outputPath -match '\.html$') { 'Html' } else { 'Markdown' }

		try
		{
			Export-AuditReport -OutputPath $outputPath -Format $format
			Show-ThemedDialog -Title 'Export Report' -Message "Audit report exported to:`n$outputPath" -Buttons @('OK') -AccentButton 'OK'
		}
		catch
		{
			Show-ThemedDialog -Title 'Export Report' -Message "Failed to export audit report.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	# --- Clear Old Entries handler ---
	$btnClear.Add_Click({
		$confirmResult = Show-ThemedDialog -Title 'Clear Old Entries' `
			-Message "This will remove audit log entries older than 30 days.`n`nDo you want to continue?" `
			-Buttons @('Cancel', 'Clear Old Entries') `
			-DestructiveButton 'Clear Old Entries'
		if ($confirmResult -ne 'Clear Old Entries') { return }

		try
		{
			$cutoff = (Get-Date).AddDays(-30)
			Clear-AuditLog -OlderThan $cutoff
			& $populateTimeline -FilterMode ([string]$filterCombo.SelectedItem)
			Show-ThemedDialog -Title 'Clear Old Entries' -Message 'Entries older than 30 days have been removed.' -Buttons @('OK') -AccentButton 'OK'
		}
		catch
		{
			Show-ThemedDialog -Title 'Clear Old Entries' -Message "Failed to clear old entries.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	[void]$dlg.ShowDialog()
}
