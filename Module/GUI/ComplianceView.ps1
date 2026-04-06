# Compliance Dashboard: drift detection view accessible from the GUI.
# Provides a dialog to select a profile/snapshot, run compliance checks,
# view results, and optionally fix drifted entries via a GUI execution run.

function Show-ComplianceDialog
{
	$bc = $Script:SharedBrushConverter
	$theme = $Script:CurrentTheme
	$layout = $Script:GuiLayout

	$dlg = New-Object System.Windows.Window
	$dlg.Title = 'Check Compliance'
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

	# --- Top: file picker + check button ---
	$topPanel = New-Object System.Windows.Controls.StackPanel
	$topPanel.Orientation = 'Vertical'
	$topPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	[System.Windows.Controls.DockPanel]::SetDock($topPanel, [System.Windows.Controls.Dock]::Top)

	$fileRow = New-Object System.Windows.Controls.DockPanel
	$fileRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

	$btnBrowse = New-Object System.Windows.Controls.Button
	$btnBrowse.Content = 'Browse...'
	$btnBrowse.MinWidth = 90
	$btnBrowse.Height = $layout.ButtonHeight
	$btnBrowse.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
	$btnBrowse.FontWeight = [System.Windows.FontWeights]::SemiBold
	Set-ButtonChrome -Button $btnBrowse -Variant 'Secondary'
	[System.Windows.Controls.DockPanel]::SetDock($btnBrowse, [System.Windows.Controls.Dock]::Right)

	$txtFilePath = New-Object System.Windows.Controls.TextBox
	$txtFilePath.IsReadOnly = $true
	$txtFilePath.Height = $layout.ButtonHeight
	$txtFilePath.VerticalContentAlignment = 'Center'
	$txtFilePath.Padding = [System.Windows.Thickness]::new(8, 0, 8, 0)
	$txtFilePath.Background = $bc.ConvertFromString($theme.PanelBg)
	$txtFilePath.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	$txtFilePath.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
	$txtFilePath.Text = '(Select a configuration profile or snapshot...)'

	[void]$fileRow.Children.Add($btnBrowse)
	[void]$fileRow.Children.Add($txtFilePath)
	[void]$topPanel.Children.Add($fileRow)

	$actionRow = New-Object System.Windows.Controls.StackPanel
	$actionRow.Orientation = 'Horizontal'
	$actionRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

	$btnCheck = New-Object System.Windows.Controls.Button
	$btnCheck.Content = 'Check Compliance'
	$btnCheck.MinWidth = $layout.ButtonMinWidth
	$btnCheck.Height = $layout.ButtonHeight
	$btnCheck.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnCheck.IsEnabled = $false
	Set-ButtonChrome -Button $btnCheck -Variant 'Primary'

	$btnFixDrift = New-Object System.Windows.Controls.Button
	$btnFixDrift.Content = 'Fix Drift'
	$btnFixDrift.MinWidth = $layout.ButtonMinWidth
	$btnFixDrift.Height = $layout.ButtonHeight
	$btnFixDrift.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
	$btnFixDrift.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnFixDrift.IsEnabled = $false
	Set-ButtonChrome -Button $btnFixDrift -Variant 'Danger'

	[void]$actionRow.Children.Add($btnCheck)
	[void]$actionRow.Children.Add($btnFixDrift)
	[void]$topPanel.Children.Add($actionRow)

	# --- Summary label ---
	$summaryLabel = New-Object System.Windows.Controls.TextBlock
	$summaryLabel.Text = ''
	$summaryLabel.FontSize = $layout.FontSizeSection
	$summaryLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
	$summaryLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
	$summaryLabel.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	[void]$topPanel.Children.Add($summaryLabel)

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

	# --- Center: scrollable results list ---
	$scrollViewer = New-Object System.Windows.Controls.ScrollViewer
	$scrollViewer.VerticalScrollBarVisibility = 'Auto'
	$scrollViewer.HorizontalScrollBarVisibility = 'Disabled'

	$resultsList = New-Object System.Windows.Controls.StackPanel
	$resultsList.Orientation = 'Vertical'
	$scrollViewer.Content = $resultsList

	[void]$rootPanel.Children.Add($scrollViewer)

	Complete-RoundedWindow -Window $dlg -ContentElement $rootPanel -RoundBorder $roundedParts.RoundBorder -DockPanel $roundedParts.DockPanel

	# --- Shared state ---
	$complianceState = @{
		FilePath         = $null
		Report           = $null
		ProfileData      = $null
	}

	# --- Browse handler ---
	$btnBrowse.Add_Click({
		$openDialog = New-Object Microsoft.Win32.OpenFileDialog
		$openDialog.Title = 'Select Configuration Profile or Snapshot'
		$openDialog.Filter = 'JSON Files (*.json)|*.json|All Files (*.*)|*.*'
		$openDialog.DefaultExt = 'json'

		$dlgOwner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($openDialog.ShowDialog($dlgOwner) -eq $true)
		{
			$complianceState.FilePath = $openDialog.FileName
			$txtFilePath.Text = $openDialog.FileName
			$btnCheck.IsEnabled = $true
			$summaryLabel.Text = ''
			$resultsList.Children.Clear()
			$btnFixDrift.IsEnabled = $false
			$complianceState.Report = $null
		}
	}.GetNewClosure())

	# --- Check Compliance handler ---
	$btnCheck.Add_Click({
		$filePath = $complianceState.FilePath
		if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath -ErrorAction SilentlyContinue))
		{
			Show-ThemedDialog -Title 'Check Compliance' -Message 'Please select a valid profile or snapshot file.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$resultsList.Children.Clear()
		$summaryLabel.Text = 'Checking compliance...'
		# Flush dispatcher so 'Checking compliance...' renders before the blocking work.
		# Uses direct dispatcher call because .GetNewClosure() doesn't capture functions.
		try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch { }

		try
		{
			$raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8 -ErrorAction Stop
			$profileData = $raw | ConvertFrom-Json -ErrorAction Stop
			$complianceState.ProfileData = $profileData
		}
		catch
		{
			$summaryLabel.Text = 'Failed to load profile.'
			Show-ThemedDialog -Title 'Check Compliance' -Message "Failed to read profile file.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK'
			return
		}

		try
		{
			$report = Test-SystemCompliance -Profile $profileData -Manifest $Script:TweakManifest
			$complianceState.Report = $report
		}
		catch
		{
			$summaryLabel.Text = 'Compliance check failed.'
			Show-ThemedDialog -Title 'Check Compliance' -Message "Compliance check failed.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK'
			return
		}

		# Update summary
		$summaryLabel.Text = "Compliant: $($report.Compliant) | Drifted: $($report.Drifted) | Unknown: $($report.Unknown)"

		# Enable Fix Drift only if drifted items exist
		$btnFixDrift.IsEnabled = ($report.Drifted -gt 0)

		# Populate results list
		$resultsList.Children.Clear()
		foreach ($entry in @($report.Entries))
		{
			if (-not $entry) { continue }

			$card = New-Object System.Windows.Controls.Border
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
			$card.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
			$card.CornerRadius = [System.Windows.CornerRadius]::new($layout.BorderRadiusSmall)
			$card.BorderThickness = [System.Windows.Thickness]::new(1)
			$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$card.Background = $bc.ConvertFromString($theme.PanelBg)

			$cardGrid = New-Object System.Windows.Controls.Grid
			$col1 = New-Object System.Windows.Controls.ColumnDefinition
			$col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			$col2 = New-Object System.Windows.Controls.ColumnDefinition
			$col2.Width = [System.Windows.GridLength]::new(100)
			$col3 = New-Object System.Windows.Controls.ColumnDefinition
			$col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			[void]$cardGrid.ColumnDefinitions.Add($col1)
			[void]$cardGrid.ColumnDefinitions.Add($col2)
			[void]$cardGrid.ColumnDefinitions.Add($col3)

			# Name
			$nameBlock = New-Object System.Windows.Controls.TextBlock
			$nameBlock.Text = [string]$entry.Name
			$nameBlock.VerticalAlignment = 'Center'
			$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$nameBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$nameBlock.TextTrimming = 'CharacterEllipsis'
			[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)

			# Status badge
			$statusBlock = New-Object System.Windows.Controls.TextBlock
			$statusBlock.Text = [string]$entry.Status
			$statusBlock.HorizontalAlignment = 'Center'
			$statusBlock.VerticalAlignment = 'Center'
			$statusBlock.FontWeight = [System.Windows.FontWeights]::Bold
			$statusColor = switch ([string]$entry.Status)
			{
				'Compliant' { '#22C55E' }
				'Drifted'   { '#EF4444' }
				default     { '#9CA3AF' }
			}
			$statusBlock.Foreground = $bc.ConvertFromString($statusColor)
			[System.Windows.Controls.Grid]::SetColumn($statusBlock, 1)

			# Values: current vs desired
			$valuesBlock = New-Object System.Windows.Controls.TextBlock
			$desiredText = if ($null -ne $entry.DesiredState) { [string]$entry.DesiredState } else { '(null)' }
			$actualText = if ($null -ne $entry.ActualState) { [string]$entry.ActualState } else { '(null)' }
			$valuesBlock.Text = "Current: $actualText | Desired: $desiredText"
			$valuesBlock.VerticalAlignment = 'Center'
			$valuesBlock.FontSize = $layout.FontSizeSmall
			$valuesBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$valuesBlock.TextTrimming = 'CharacterEllipsis'
			$valuesBlock.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
			[System.Windows.Controls.Grid]::SetColumn($valuesBlock, 2)

			[void]$cardGrid.Children.Add($nameBlock)
			[void]$cardGrid.Children.Add($statusBlock)
			[void]$cardGrid.Children.Add($valuesBlock)
			$card.Child = $cardGrid
			[void]$resultsList.Children.Add($card)
		}

		if ($report.Entries.Count -eq 0)
		{
			$emptyLabel = New-Object System.Windows.Controls.TextBlock
			$emptyLabel.Text = 'No entries found in the selected profile.'
			$emptyLabel.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$emptyLabel.HorizontalAlignment = 'Center'
			$emptyLabel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)
			[void]$resultsList.Children.Add($emptyLabel)
		}
	}.GetNewClosure())

	# --- Fix Drift handler ---
	$btnFixDrift.Add_Click({
		$report = $complianceState.Report
		if (-not $report -or $report.Drifted -eq 0)
		{
			Show-ThemedDialog -Title 'Fix Drift' -Message 'No drifted entries to fix.' -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$confirmResult = Show-ThemedDialog -Title 'Fix Drift' `
			-Message "This will apply changes to fix $($report.Drifted) drifted setting$(if ($report.Drifted -eq 1) { '' } else { 's' }).`n`nDo you want to continue?" `
			-Buttons @('Cancel', 'Fix Drift') `
			-DestructiveButton 'Fix Drift'
		if ($confirmResult -ne 'Fix Drift') { return }

		try
		{
			$fixCommands = Get-ComplianceFixList -ComplianceReport $report -Manifest $Script:TweakManifest
			if (-not $fixCommands -or @($fixCommands).Count -eq 0)
			{
				Show-ThemedDialog -Title 'Fix Drift' -Message 'Could not resolve any fix actions from the drifted entries.' -Buttons @('OK') -AccentButton 'OK'
				return
			}

			# Build tweak list from fix commands
			$fixTweakList = [System.Collections.Generic.List[hashtable]]::new()
			$order = 0
			foreach ($commandLine in @($fixCommands))
			{
				if ([string]::IsNullOrWhiteSpace([string]$commandLine)) { continue }
				$parts = ([string]$commandLine).Trim() -split '\s+', 2
				$functionName = $parts[0]
				$paramName = if ($parts.Count -gt 1) { $parts[1].TrimStart('-') } else { $null }
				if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

				$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function $functionName
				if (-not $manifestEntry) { continue }

				$order++
				$fixTweakList.Add(@{
					Key             = [string]$order
					Index           = $order
					Name            = [string]$manifestEntry.Name
					Function        = $functionName
					Type            = 'Toggle'
					TypeKind        = 'Toggle'
					TypeLabel       = 'Fix'
					TypeTone        = 'Caution'
					TypeBadgeLabel  = 'Fix'
					Category        = [string]$manifestEntry.Category
					Risk            = [string]$manifestEntry.Risk
					Restorable      = $manifestEntry.Restorable
					RecoveryLevel   = if ((Test-GuiObjectField -Object $manifestEntry -FieldName 'RecoveryLevel')) { [string]$manifestEntry.RecoveryLevel } else { 'Direct' }
					RequiresRestart = [bool]$manifestEntry.RequiresRestart
					Impact          = $manifestEntry.Impact
					PresetTier      = $manifestEntry.PresetTier
					Selection       = if ($paramName) { $paramName } else { 'Fix' }
					ToggleParam     = $paramName
					OnParam         = [string]$manifestEntry.OnParam
					OffParam        = [string]$manifestEntry.OffParam
					IsChecked       = $true
					CurrentState    = 'Drifted from desired state'
					CurrentStateTone = 'Caution'
					StateDetail     = 'Fixing drift to match the compliance profile.'
					MatchesDesired  = $false
					ScenarioTags    = @()
					ReasonIncluded  = 'Included as part of compliance drift fix.'
					BlastRadius     = ''
					IsRemoval       = $false
					ExtraArgs       = $null
					GamingPreviewGroup = $null
					TroubleshootingOnly = $false
				})
			}

			if ($fixTweakList.Count -eq 0)
			{
				Show-ThemedDialog -Title 'Fix Drift' -Message 'Could not resolve any fixable changes from the drifted entries.' -Buttons @('OK') -AccentButton 'OK'
				return
			}

			$dlg.Close()
			LogInfo ("Compliance Fix Drift: applying {0} fix(es)." -f $fixTweakList.Count)
			Start-GuiExecutionRun -TweakList @($fixTweakList) -Mode 'Run' -ExecutionTitle 'Fixing Compliance Drift'
		}
		catch
		{
			LogError "Compliance fix drift failed: $($_.Exception.Message)"
			Show-ThemedDialog -Title 'Fix Drift' -Message "Failed to build fix list.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	[void]$dlg.ShowDialog()
}
