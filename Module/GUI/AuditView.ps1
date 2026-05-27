# Audit Log Viewer: displays a scrollable timeline of audit log entries
# with filtering and export/clear capabilities.

<#
    .SYNOPSIS
#>

function Show-AuditLogDialog
{
	$bc = $Script:SharedBrushConverter
	$theme = $Script:CurrentTheme
	$layout = $Script:GuiLayout

	$dlg = New-Object System.Windows.Window
	$dlg.Title = (Get-UxLocalizedString -Key 'GuiAuditTitle' -Fallback 'Audit Log')
	$dlg.Width = $layout.DialogLargeWidth
	$dlg.Height = $layout.DialogLargeHeight
	$dlg.MinWidth = $layout.DialogLargeMinWidth
	$dlg.MinHeight = $layout.DialogLargeMinHeight
	$dlg.ResizeMode = 'CanResize'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('FluentSystemIcons')
	$dlg.FontSize = $layout.FontSizeBody
	$dlg.ShowInTaskbar = $false

	try { if ($Form) { $dlg.Owner = $Form } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.ShowAuditLogDialog.SetOwner' }
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
	$filterLabel.Text = (Get-UxLocalizedString -Key 'GuiAuditFilter' -Fallback 'Filter:')
	$filterLabel.VerticalAlignment = 'Center'
	$filterLabel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$filterLabel.Foreground = $bc.ConvertFromString($theme.TextPrimary)

	$filterCombo = New-Object System.Windows.Controls.ComboBox
	$filterCombo.MinWidth = 160
	$filterCombo.Height = $layout.ButtonHeight
	$filterCombo.VerticalContentAlignment = 'Center'
	[void]$filterCombo.Items.Add((Get-UxLocalizedString -Key 'GuiAuditFilterAll' -Fallback 'All'))
	[void]$filterCombo.Items.Add((Get-UxLocalizedString -Key 'GuiAuditFilterRunsOnly' -Fallback 'Runs Only'))
	[void]$filterCombo.Items.Add((Get-UxLocalizedString -Key 'GuiAuditFilterComplianceOnly' -Fallback 'Compliance Only'))
	$filterCombo.SelectedIndex = 0

	$retentionLabel = New-Object System.Windows.Controls.TextBlock
	$retentionLabel.Text = (Get-UxLocalizedString -Key 'GuiAuditRetention' -Fallback 'Retention:')
	$retentionLabel.VerticalAlignment = 'Center'
	$retentionLabel.Margin = [System.Windows.Thickness]::new(18, 0, 8, 0)
	$retentionLabel.Foreground = $bc.ConvertFromString($theme.TextPrimary)

	$retentionCombo = New-Object System.Windows.Controls.ComboBox
	$retentionCombo.MinWidth = 160
	$retentionCombo.Height = $layout.ButtonHeight
	$retentionCombo.VerticalContentAlignment = 'Center'
	[void]$retentionCombo.Items.Add('30 days')
	[void]$retentionCombo.Items.Add('90 days')
	[void]$retentionCombo.Items.Add('180 days')
	[void]$retentionCombo.Items.Add('365 days')
	$initialRetentionDays = if ($Script:AuditRetentionDays) { [int]$Script:AuditRetentionDays } else { 90 }
	switch ($initialRetentionDays)
	{
		30 { $retentionCombo.SelectedIndex = 0 }
		90 { $retentionCombo.SelectedIndex = 1 }
		180 { $retentionCombo.SelectedIndex = 2 }
		365 { $retentionCombo.SelectedIndex = 3 }
		default { $retentionCombo.SelectedIndex = 1 }
	}

	$btnExport = New-Object System.Windows.Controls.Button
	$btnExport.Content = (Get-UxLocalizedString -Key 'GuiAuditExportReport' -Fallback 'Export Report')
	$btnExport.MinWidth = $layout.ButtonMinWidth
	$btnExport.Height = $layout.ButtonHeight
	$btnExport.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
	$btnExport.FontWeight = [System.Windows.FontWeights]::SemiBold
	Set-ButtonChrome -Button $btnExport -Variant 'Primary'

	$btnClear = New-Object System.Windows.Controls.Button
	$btnClear.Content = (Get-UxLocalizedString -Key 'GuiAuditClearOldEntries' -Fallback 'Clear Old Entries')
	$btnClear.MinWidth = $layout.ButtonMinWidth
	$btnClear.Height = $layout.ButtonHeight
	$btnClear.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
	$btnClear.FontWeight = [System.Windows.FontWeights]::SemiBold
	Set-ButtonChrome -Button $btnClear -Variant 'Danger'

	[void]$topPanel.Children.Add($filterLabel)
	[void]$topPanel.Children.Add($filterCombo)
	[void]$topPanel.Children.Add($retentionLabel)
	[void]$topPanel.Children.Add($retentionCombo)
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
	$btnClose.Content = (Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close')
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

	# --- Localization capture for closures ---
	$getLocalizedString = ${function:Get-UxLocalizedString}
	$localizedRunsOnly = (Get-UxLocalizedString -Key 'GuiAuditFilterRunsOnly' -Fallback 'Runs Only')
	$localizedComplianceOnly = (Get-UxLocalizedString -Key 'GuiAuditFilterComplianceOnly' -Fallback 'Compliance Only')

	$getSelectedRetentionDays = {
		$selectedText = [string]$retentionCombo.SelectedItem
		if ([string]::IsNullOrWhiteSpace($selectedText))
		{
			return 90
		}

		$match = [regex]::Match($selectedText, '\d+')
		if ($match.Success)
		{
			try { return [int]$match.Value } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.Show-AuditLogDialog:catch151' -Severity Debug }
			 return 90 }
		}

		return 90
	}.GetNewClosure()

	$retentionCombo.Add_SelectionChanged({
		$Script:AuditRetentionDays = & $getSelectedRetentionDays
		if ($Script:Ctx -and $Script:Ctx.ContainsKey('UI'))
		{
			$Script:Ctx.UI.AuditRetentionDays = [int]$Script:AuditRetentionDays
		}
	}.GetNewClosure())

	# --- Populate timeline function ---
	$populateTimeline = {
		param ([string]$FilterMode)

		$timelinePanel.Children.Clear()

		$getParams = @{ MaxRecords = 500 }
		$filterAction = $null
		switch ($FilterMode)
		{
			$localizedRunsOnly       { $getParams['Action'] = 'Run' }
			$localizedComplianceOnly { $getParams['Action'] = 'Compliance' }
		}

		$retentionDaysForList = & $getSelectedRetentionDays
		$retentionSinceForList = (Get-Date).AddDays(-1 * [int]$retentionDaysForList)
		$records = @(Get-AuditLog -Since $retentionSinceForList @getParams)

		if ($records.Count -eq 0)
		{
			$emptyLabel = New-Object System.Windows.Controls.TextBlock
			$emptyLabel.Text = (& $getLocalizedString -Key 'GuiAuditNoEntries' -Fallback 'No audit log entries found.')
			$emptyLabel.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$emptyLabel.HorizontalAlignment = 'Center'
			$emptyLabel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)
			[void]$timelinePanel.Children.Add($emptyLabel)
			return
		}

		# Show records in reverse chronological order (newest first)
		$sortedRecords = @($records | Sort-Object { try { [datetime]::Parse($_.Timestamp) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.Show-AuditLogDialog:catch195' -Severity Debug }
		 [datetime]::MinValue } } -Descending)

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

			$tsText = (& $getLocalizedString -Key 'GuiAuditTimestampUnknown' -Fallback '(unknown)')
			if ($rec.Timestamp)
			{
				try { $tsText = ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.Show-AuditLogDialog:catch217' -Severity Debug }
				 $tsText = [string]$rec.Timestamp }
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

			$modeIconName = switch ([string]$rec.Mode)
			{
				'Run' { 'RunTweaks' }
				'Defaults' { 'RestoreDefaults' }
				'GameMode' { 'GameMode' }
				'Compliance' { 'Shield' }
				default { 'Archive' }
			}

			$modeBlock = New-GuiLabeledIconContent -IconName $modeIconName `
				-Text ((& $getLocalizedString -Key 'GuiAuditModeFormat' -Fallback 'Mode: {0}') -f [string]$rec.Mode) `
				-IconSize 12 -Gap 5 -TextFontSize $layout.FontSizeSmall `
				-Foreground $bc.ConvertFromString($theme.TextSecondary) `
				-AllowTextOnlyFallback
			if ($modeBlock)
			{
				$modeBlock.VerticalAlignment = 'Center'
			}

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
				[void]$detailParts.Add((& $getLocalizedString -Key 'GuiAuditAppliedFormat' -Fallback 'Applied: {0}') -f $applied)
				[void]$detailParts.Add((& $getLocalizedString -Key 'GuiAuditFailedFormat' -Fallback 'Failed: {0}') -f $failed)
			}
			if ($rec.DurationSeconds)
			{
				[void]$detailParts.Add((& $getLocalizedString -Key 'GuiAuditDurationFormat' -Fallback 'Duration: {0}s') -f $rec.DurationSeconds)
			}
			if ($rec.PresetName)
			{
				[void]$detailParts.Add((& $getLocalizedString -Key 'GuiAuditPresetFormat' -Fallback 'Preset: {0}') -f $rec.PresetName)
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
		$saveDialog.Title = (& $getLocalizedString -Key 'GuiAuditExportTitle' -Fallback 'Export Audit Report')
		$saveDialog.Filter = 'Markdown Files (*.md)|*.md|HTML Files (*.html)|*.html|All Files (*.*)|*.*'
		$saveDialog.DefaultExt = 'md'
		$saveDialog.FileName = 'Baseline-AuditReport-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss')

		$dlgOwner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($saveDialog.ShowDialog($dlgOwner) -ne $true) { return }

		$outputPath = $saveDialog.FileName
		$format = if ($outputPath -match '\.html$') { 'Html' } else { 'Markdown' }
		$retentionDays = & $getSelectedRetentionDays
		$retentionSince = (Get-Date).AddDays(-1 * [int]$retentionDays)

		try
		{
			Export-AuditReport -OutputPath $outputPath -Format $format -Since $retentionSince
			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiAuditExportReport' -Fallback 'Export Report') -Message ((& $getLocalizedString -Key 'GuiAuditExportSuccess' -Fallback "Audit report exported to:`n{0}") -f $outputPath) -Buttons @('OK') -AccentButton 'OK'
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.Show-AuditLogDialog:catch318' -Severity Debug }

			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiAuditExportReport' -Fallback 'Export Report') -Message ((& $getLocalizedString -Key 'GuiAuditExportFailed' -Fallback "Failed to export audit report.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	# --- Clear Old Entries handler ---
	$btnClear.Add_Click({
		$clearLabel = (& $getLocalizedString -Key 'GuiAuditClearOldEntries' -Fallback 'Clear Old Entries')
		$retentionDays = & $getSelectedRetentionDays
		$confirmResult = Show-ThemedDialog -Title $clearLabel `
			-Message ((& $getLocalizedString -Key 'GuiAuditClearConfirm' -Fallback "This will remove audit log entries older than {0} days.`n`nDo you want to continue?") -f $retentionDays) `
			-Buttons @('Cancel', $clearLabel) `
			-DestructiveButton $clearLabel
		if ($confirmResult -ne $clearLabel) { return }

		try
		{
			$cutoff = (Get-Date).AddDays(-1 * [int]$retentionDays)
			Clear-AuditLog -OlderThan $cutoff
			& $populateTimeline -FilterMode ([string]$filterCombo.SelectedItem)
			Show-ThemedDialog -Title $clearLabel -Message ((& $getLocalizedString -Key 'GuiAuditClearSuccess' -Fallback "Entries older than {0} days have been removed.") -f $retentionDays) -Buttons @('OK') -AccentButton 'OK'
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditView.Show-AuditLogDialog:catch341' -Severity Debug }

			Show-ThemedDialog -Title $clearLabel -Message ((& $getLocalizedString -Key 'GuiAuditClearFailed' -Fallback "Failed to clear old entries.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	[void]$dlg.ShowDialog()
}
