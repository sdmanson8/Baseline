
# Compliance Dashboard: drift detection view accessible from the GUI.
# Provides a dialog to select a profile/snapshot, run compliance checks,
# view results, and optionally fix drifted entries via a GUI execution run.

<#
    .SYNOPSIS
#>

function Show-ComplianceDialog
{
	$bc = $Script:SharedBrushConverter
	$theme = $Script:CurrentTheme
	$layout = $Script:GuiLayout

	$dlg = New-Object System.Windows.Window
	$dlg.Title = (Get-UxLocalizedString -Key 'GuiComplianceTitle' -Fallback 'Check Compliance')
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

	try { if ($Form) { $dlg.Owner = $Form } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ComplianceView.ShowComplianceDialog.SetOwner' }
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
	$btnBrowse.Content = (Get-UxLocalizedString -Key 'GuiComplianceBrowse' -Fallback 'Browse...')
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
	$txtFilePath.Text = (Get-UxLocalizedString -Key 'GuiComplianceFilePlaceholder' -Fallback '(Select a configuration profile or snapshot...)')

	[void]$fileRow.Children.Add($btnBrowse)
	[void]$fileRow.Children.Add($txtFilePath)
	[void]$topPanel.Children.Add($fileRow)

	$actionRow = New-Object System.Windows.Controls.StackPanel
	$actionRow.Orientation = 'Horizontal'
	$actionRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

	$btnCheck = New-Object System.Windows.Controls.Button
	$btnCheck.Content = (Get-UxLocalizedString -Key 'GuiComplianceCheckButton' -Fallback 'Check Compliance')
	$btnCheck.MinWidth = $layout.ButtonMinWidth
	$btnCheck.Height = $layout.ButtonHeight
	$btnCheck.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnCheck.IsEnabled = $false
	Set-ButtonChrome -Button $btnCheck -Variant 'Primary'

	$btnFixDrift = New-Object System.Windows.Controls.Button
	$btnFixDrift.Content = (Get-UxLocalizedString -Key 'GuiComplianceFixDrift' -Fallback 'Fix Drift')
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
	$btnClose.Content = (Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close')
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

	# --- Localization capture for closures ---
	$getLocalizedString = ${function:Get-UxLocalizedString}

	# --- Shared state ---
	$complianceState = @{
		FilePath         = $null
		Report           = $null
		ProfileData      = $null
	}

	# --- Browse handler ---
		. (Join-Path $PSScriptRoot 'ComplianceView\Show-ComplianceDialog\Show-ComplianceDialog.ps1')

	# --- Fix Drift handler ---
	$btnFixDrift.Add_Click({
		$report = $complianceState.Report
		if (-not $report -or $report.Drifted -eq 0)
		{
			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiComplianceFixDrift' -Fallback 'Fix Drift') -Message (& $getLocalizedString -Key 'GuiComplianceNoDrifted' -Fallback 'No drifted entries to fix.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$fixDriftLabel = (& $getLocalizedString -Key 'GuiComplianceFixDrift' -Fallback 'Fix Drift')
		$fixConfirmMsg = if ($report.Drifted -eq 1) { (& $getLocalizedString -Key 'GuiComplianceFixConfirmSingular' -Fallback "This will apply changes to fix {0} drifted setting.`n`nDo you want to continue?") -f $report.Drifted } else { (& $getLocalizedString -Key 'GuiComplianceFixConfirmPlural' -Fallback "This will apply changes to fix {0} drifted settings.`n`nDo you want to continue?") -f $report.Drifted }
		$confirmResult = Show-ThemedDialog -Title $fixDriftLabel `
			-Message $fixConfirmMsg `
			-Buttons @('Cancel', $fixDriftLabel) `
			-DestructiveButton $fixDriftLabel
		if ($confirmResult -ne $fixDriftLabel) { return }

		try
		{
			$fixCommands = Get-ComplianceFixList -ComplianceReport $report -Manifest $Script:TweakManifest
			if (-not $fixCommands -or @($fixCommands).Count -eq 0)
			{
				Show-ThemedDialog -Title $fixDriftLabel -Message (& $getLocalizedString -Key 'GuiComplianceFixNoActions' -Fallback 'Could not resolve any fix actions from the drifted entries.') -Buttons @('OK') -AccentButton 'OK'
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
					CurrentState    = (& $getLocalizedString -Key 'GuiComplianceDriftedState' -Fallback 'Drifted from desired state')
					CurrentStateTone = 'Caution'
					StateDetail     = (& $getLocalizedString -Key 'GuiComplianceFixingDetail' -Fallback 'Fixing drift to match the compliance profile.')
					MatchesDesired  = $false
					ScenarioTags    = @()
					ReasonIncluded  = (& $getLocalizedString -Key 'GuiComplianceFixReason' -Fallback 'Included as part of compliance drift fix.')
					BlastRadius     = ''
					IsRemoval       = $false
					ExtraArgs       = $null
					GamingPreviewGroup = $null
					TroubleshootingOnly = $false
				})
			}

			if ($fixTweakList.Count -eq 0)
			{
				Show-ThemedDialog -Title $fixDriftLabel -Message (& $getLocalizedString -Key 'GuiComplianceFixNoChanges' -Fallback 'Could not resolve any fixable changes from the drifted entries.') -Buttons @('OK') -AccentButton 'OK'
				return
			}

			$dlg.Close()
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogComplianceFixDriftApplying' -Fallback 'Compliance Fix Drift: applying {0} fix(es).' -FormatArgs @($fixTweakList.Count))
			Start-GuiExecutionRun -TweakList @($fixTweakList) -Mode 'Run' -ExecutionTitle (& $getLocalizedString -Key 'GuiComplianceFixTitle' -Fallback 'Fixing Compliance Drift')
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogComplianceFixDriftFailed' -Fallback 'Compliance fix drift failed'))
			Show-ThemedDialog -Title $fixDriftLabel -Message ((& $getLocalizedString -Key 'GuiComplianceFixBuildFailed' -Fallback "Failed to build fix list.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
		}
	}.GetNewClosure())

	[void]$dlg.ShowDialog()
}
