
# Plan Summary Panel - pre-run "what will happen" dialog shown after the user
# clicks Run but before tweaks execute.  Provides a category breakdown,
# impact summary cards, pre-flight status, and a scrollable tweak list.

<#
    .SYNOPSIS
#>

function Show-PlanSummaryDialog
{
	<#
	.SYNOPSIS
		Displays a plan summary dialog showing what will happen during the run.
	.DESCRIPTION
		Shows selected tweaks grouped by category, impact summary cards,
		optional pre-flight check results, and a scrollable tweak list.
		Returns the active run-label or 'Back'.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[object[]]$SelectedTweaks,

		[pscustomobject]$PreflightResults
	)

	$theme = $Script:CurrentTheme
	if (-not $theme) { return (Get-UxRunActionLabel) }
	$bc = $Script:SharedBrushConverter
	if (-not $bc) { $bc = New-SafeBrushConverter -Context 'Show-PlanSummaryDialog' }
	$useDarkMode = ($Script:CurrentThemeName -eq 'Dark')

	$selected = @($SelectedTweaks | Where-Object { $_ })
	if ($selected.Count -eq 0) { return (Get-UxRunActionLabel) }

	# -- Compute metrics ----------------------------------------------
	$willChangeCount = 0
	$alreadySetCount = 0
	$restartCount = 0
	$highRiskCount = 0
	$categoryGroups = [ordered]@{}

	$catOther = Get-UxLocalizedString -Key 'GuiPlanCategoryOther' -Fallback 'Other'
	foreach ($tweak in $selected)
	{
		# Category grouping
		$cat = if (Test-GuiObjectField -Object $tweak -FieldName 'Category') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Category') } else { $catOther }
		if ([string]::IsNullOrWhiteSpace($cat)) { $cat = $catOther }
		if (-not $categoryGroups.Contains($cat)) { $categoryGroups[$cat] = [System.Collections.Generic.List[object]]::new() }
		$categoryGroups[$cat].Add($tweak)

		# Impact counters
		if ((Test-GuiObjectField -Object $tweak -FieldName 'MatchesDesired') -and [bool](Get-GuiObjectField -Object $tweak -FieldName 'MatchesDesired'))
		{
			$alreadySetCount++
		}
		else
		{
			$willChangeCount++
		}
		if ((Test-GuiObjectField -Object $tweak -FieldName 'RequiresRestart') -and [bool](Get-GuiObjectField -Object $tweak -FieldName 'RequiresRestart'))
		{
			$restartCount++
		}
		$risk = if (Test-GuiObjectField -Object $tweak -FieldName 'Risk') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Risk') } else { $null }
		if ($risk -eq 'High')
		{
			$highRiskCount++
		}
	}

	# -- Window -------------------------------------------------------
	$dlg = New-Object System.Windows.Window
	$dlg.Title = (Get-UxLocalizedString -Key 'GuiPlanSummaryTitle' -Fallback 'Plan Summary')
	$dlg.Width = $Script:GuiLayout.DialogLargeWidth
	$dlg.Height = $Script:GuiLayout.DialogLargeHeight
	$dlg.MinWidth = $Script:GuiLayout.DialogLargeMinWidth
	$dlg.MinHeight = $Script:GuiLayout.DialogLargeMinHeight
	$dlg.ResizeMode = 'CanResize'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('FluentSystemIcons')
	$dlg.FontSize = $Script:GuiLayout.FontSizeBody
	$dlg.ShowInTaskbar = $false

	try { if ($Form) { $dlg.Owner = $Form } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PlanSummaryPanel.ShowPlanSummaryPanel.SetOwner' }
	$roundedParts = ConvertTo-RoundedWindow -Window $dlg -Theme $theme
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$useDarkMode)

	# -- Outer grid: header / scrollable body / button footer ---------
	$outerGrid = New-Object System.Windows.Controls.Grid
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))

	# -- Header -------------------------------------------------------
	$headerBorder = New-Object System.Windows.Controls.Border
	$headerBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 16)
	$headerBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
	$headerBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
	[System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

	$headerStack = New-Object System.Windows.Controls.StackPanel
	$headerStack.Orientation = 'Vertical'

	$tweakNoun = if ($selected.Count -eq 1) { (Get-UxLocalizedString -Key 'GuiPlanTweakSingular' -Fallback 'tweak selected') } else { (Get-UxLocalizedString -Key 'GuiPlanTweakPlural' -Fallback 'tweaks selected') }
	$planTitle = Get-UxLocalizedString -Key 'GuiPlanSummaryTitle' -Fallback 'Plan Summary'
	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.Text = "$planTitle  $([char]0x2014)  $($selected.Count) $tweakNoun"
	$titleText.FontSize = $Script:GuiLayout.FontSizeHeading
	$titleText.FontWeight = [System.Windows.FontWeights]::Bold
	$titleText.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	[void]($headerStack.Children.Add($titleText))

	$subtitleText = New-Object System.Windows.Controls.TextBlock
	$subtitleText.Text = (Get-UxLocalizedString -Key 'GuiPlanSubtitle' -Fallback 'Review what will happen before continuing.')
	$subtitleText.TextWrapping = 'Wrap'
	$subtitleText.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
	$subtitleText.Foreground = $bc.ConvertFromString($theme.TextSecondary)
	[void]($headerStack.Children.Add($subtitleText))

	$headerBorder.Child = $headerStack
	[void]($outerGrid.Children.Add($headerBorder))

	# -- Scrollable body ----------------------------------------------
	$bodyScroll = New-Object System.Windows.Controls.ScrollViewer
	$bodyScroll.VerticalScrollBarVisibility = 'Auto'
	$bodyScroll.HorizontalScrollBarVisibility = 'Disabled'
	[System.Windows.Controls.Grid]::SetRow($bodyScroll, 1)

	$bodyStack = New-Object System.Windows.Controls.StackPanel
	$bodyStack.Orientation = 'Vertical'
	$bodyStack.Margin = [System.Windows.Thickness]::new(24, 16, 24, 16)

	# -- Pre-flight status section ------------------------------------
		. (Join-Path $PSScriptRoot 'PlanSummaryPanel\Show-PlanSummaryDialog\PreflightResultsSection.ps1')

	# -- Impact summary cards -----------------------------------------
	$impactIconContent = $null
	if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$impactIconContent = New-GuiLabeledIconContent -IconName 'PreviewRun' -Text (Get-UxLocalizedString -Key 'GuiPlanImpactSummary' -Fallback 'IMPACT SUMMARY') -IconSize 14 -Gap 6 -TextFontSize $Script:GuiLayout.FontSizeLabel -Foreground (ConvertTo-GuiBrush -Color $theme.SectionLabel -Context 'PlanSummary/ImpactLabel') -AllowTextOnlyFallback -Bold
	}
	if ($impactIconContent)
	{
		$impactIconContent.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($bodyStack.Children.Add($impactIconContent))
	}
	else
	{
		$impactLabel = New-Object System.Windows.Controls.TextBlock
		$impactLabel.Text = (Get-UxLocalizedString -Key 'GuiPlanImpactSummary' -Fallback 'IMPACT SUMMARY')
		$impactLabel.FontSize = $Script:GuiLayout.FontSizeLabel
		$impactLabel.FontWeight = [System.Windows.FontWeights]::Bold
		$impactLabel.Foreground = $bc.ConvertFromString($theme.SectionLabel)
		$impactLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($bodyStack.Children.Add($impactLabel))
	}

	$summaryCards = @(
		@{ Label = (Get-UxLocalizedString -Key 'GuiPlanWillChange' -Fallback 'Will Change'); Value = $willChangeCount; Tone = $(if ($willChangeCount -gt 0) { 'Primary' } else { 'Muted' }) }
		@{ Label = (Get-UxLocalizedString -Key 'GuiPlanAlreadySet' -Fallback 'Already Set'); Value = $alreadySetCount; Tone = $(if ($alreadySetCount -gt 0) { 'Success' } else { 'Muted' }) }
		@{ Label = (Get-UxLocalizedString -Key 'GuiPlanRequiresRestart' -Fallback 'Requires Restart'); Value = $restartCount; Tone = $(if ($restartCount -gt 0) { 'Caution' } else { 'Muted' }) }
		@{ Label = (Get-UxLocalizedString -Key 'GuiPlanHighRisk' -Fallback 'High Risk'); Value = $highRiskCount; Tone = $(if ($highRiskCount -gt 0) { 'Danger' } else { 'Muted' }) }
	)

	$cardsBorder = New-Object System.Windows.Controls.Border
	$cardsBorder.Background = $bc.ConvertFromString($theme.PanelBg)
	$cardsBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
	$cardsBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	$cardsBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
	$cardsBorder.Padding = [System.Windows.Thickness]::new(12, 12, 12, 4)
	$cardsBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
	$cardsBorder.Child = (GUICommon\New-DialogSummaryCardsPanel -Theme $theme -SummaryCards $summaryCards)
	[void]($bodyStack.Children.Add($cardsBorder))

	$sepImpactCat = New-Object System.Windows.Controls.Separator
	$sepImpactCat.Margin = [System.Windows.Thickness]::new(0, 4, 0, 8)
	$sepImpactCat.Background = $bc.ConvertFromString($theme.BorderColor)
	[void]($bodyStack.Children.Add($sepImpactCat))

	# -- Category breakdown -------------------------------------------
	$catLabel = New-Object System.Windows.Controls.TextBlock
	$catLabel.Text = (Get-UxLocalizedString -Key 'GuiPlanCategories' -Fallback 'CATEGORIES')
	$catLabel.FontSize = $Script:GuiLayout.FontSizeLabel
	$catLabel.FontWeight = [System.Windows.FontWeights]::Bold
	$catLabel.Foreground = $bc.ConvertFromString($theme.SectionLabel)
	$catLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
	[void]($bodyStack.Children.Add($catLabel))

	$catBorder = New-Object System.Windows.Controls.Border
	$catBorder.Background = $bc.ConvertFromString($theme.CardBg)
	$catBorder.BorderBrush = $bc.ConvertFromString($theme.CardBorder)
	$catBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	$catBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
	$catBorder.Padding = [System.Windows.Thickness]::new(14, 10, 14, 10)
	$catBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)

	$catStack = New-Object System.Windows.Controls.StackPanel
	$catStack.Orientation = 'Vertical'

	foreach ($catName in $categoryGroups.Keys)
	{
		$catItems = $categoryGroups[$catName]
		$catRow = New-Object System.Windows.Controls.Grid
		[void]($catRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($catRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))

		$catNameBlock = New-Object System.Windows.Controls.TextBlock
		$catNameBlock.Text = $catName
		$catNameBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
		$catNameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
		$catNameBlock.VerticalAlignment = 'Center'
		$catNameBlock.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
		[System.Windows.Controls.Grid]::SetColumn($catNameBlock, 0)
		[void]($catRow.Children.Add($catNameBlock))

		$catCountBorder = New-Object System.Windows.Controls.Border
		$catCountBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
		$catCountBorder.Background = $bc.ConvertFromString($theme.StatusPillBg)
		$catCountBorder.BorderBrush = $bc.ConvertFromString($theme.StatusPillBorder)
		$catCountBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$catCountBorder.Padding = [System.Windows.Thickness]::new(10, 2, 10, 2)
		$catCountBorder.VerticalAlignment = 'Center'

		$catCountText = New-Object System.Windows.Controls.TextBlock
		$catCountText.Text = [string]$catItems.Count
		$catCountText.Foreground = $bc.ConvertFromString($theme.StatusPillText)
		$catCountText.FontSize = $Script:GuiLayout.FontSizeLabel
		$catCountText.FontWeight = [System.Windows.FontWeights]::SemiBold
		$catCountBorder.Child = $catCountText
		[System.Windows.Controls.Grid]::SetColumn($catCountBorder, 1)
		[void]($catRow.Children.Add($catCountBorder))

		[void]($catStack.Children.Add($catRow))
	}

	$catBorder.Child = $catStack
	[void]($bodyStack.Children.Add($catBorder))

	$sepCatTweaks = New-Object System.Windows.Controls.Separator
	$sepCatTweaks.Margin = [System.Windows.Thickness]::new(0, 4, 0, 8)
	$sepCatTweaks.Background = $bc.ConvertFromString($theme.BorderColor)
	[void]($bodyStack.Children.Add($sepCatTweaks))

	# -- Tweak list ---------------------------------------------------
	$tweakListLabel = New-Object System.Windows.Controls.TextBlock
	$tweakListLabel.Text = (Get-UxLocalizedString -Key 'GuiPlanSelectedTweaks' -Fallback 'SELECTED TWEAKS')
	$tweakListLabel.FontSize = $Script:GuiLayout.FontSizeLabel
	$tweakListLabel.FontWeight = [System.Windows.FontWeights]::Bold
	$tweakListLabel.Foreground = $bc.ConvertFromString($theme.SectionLabel)
	$tweakListLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
	[void]($bodyStack.Children.Add($tweakListLabel))

	# Pre-compute brushes for the tweak rows
	$brushCardBg = $bc.ConvertFromString($theme.CardBg)
	$brushCardBorder = $bc.ConvertFromString($theme.CardBorder)
	$brushTextPrimary = $bc.ConvertFromString($theme.TextPrimary)
	$brushTextMuted = $bc.ConvertFromString($theme.TextMuted)
	$thickness1 = [System.Windows.Thickness]::new(1)

	# Sort tweaks by category then name for a consistent display
	$sortedTweaks = @($selected | Sort-Object @{ Expression = { [string]$_.Category } }, @{ Expression = { [string]$_.Name } })

		. (Join-Path $PSScriptRoot 'PlanSummaryPanel\Show-PlanSummaryDialog\TweakPlanRows.ps1')

	$bodyScroll.Content = $bodyStack
	[void]($outerGrid.Children.Add($bodyScroll))

	# -- Button footer ------------------------------------------------
	$buttonBorder = New-Object System.Windows.Controls.Border
	$buttonBorder.Background = $bc.ConvertFromString($theme.PanelBg)
	$buttonBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
	$buttonBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$buttonBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	[System.Windows.Controls.Grid]::SetRow($buttonBorder, 2)

	$buttonPanel = New-Object System.Windows.Controls.StackPanel
	$buttonPanel.Orientation = 'Horizontal'
	$buttonPanel.HorizontalAlignment = 'Right'

	$resultRef = @{ Value = 'Back' }

	# Back button
	$btnBack = New-Object System.Windows.Controls.Button
	$btnBack.Content = (Get-UxLocalizedString -Key 'GuiPlanBack' -Fallback 'Back')
	$btnBack.MinWidth = $Script:GuiLayout.ButtonMinWidth
	$btnBack.Height = $Script:GuiLayout.ButtonHeight
	$btnBack.Margin = [System.Windows.Thickness]::new(0, 4, 6, 4)
	$btnBack.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnBack.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)
	$btnBack.IsCancel = $true
	Set-ButtonChrome -Button $btnBack -Variant 'Secondary'

	$dlgRefBack = $dlg
	$resRefBack = $resultRef
	$btnBack.Add_Click({
		$resRefBack.Value = 'Back'
		$dlgRefBack.Close()
	}.GetNewClosure())
	[void]($buttonPanel.Children.Add($btnBack))

	# Continue button
	$continueLabel = Get-UxRunActionLabel
	$btnContinue = New-Object System.Windows.Controls.Button
	$btnContinue.Content = $continueLabel
	$btnContinue.MinWidth = $Script:GuiLayout.ButtonMinWidth
	$btnContinue.Height = $Script:GuiLayout.ButtonHeight
	$btnContinue.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
	$btnContinue.FontWeight = [System.Windows.FontWeights]::SemiBold
	$btnContinue.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)
	$btnContinue.IsDefault = $true
	Set-ButtonChrome -Button $btnContinue -Variant 'Primary'

	$dlgRefContinue = $dlg
	$resRefContinue = $resultRef
	$continueLabelRef = $continueLabel
	$btnContinue.Add_Click({
		$resRefContinue.Value = $continueLabelRef
		$dlgRefContinue.Close()
	}.GetNewClosure())
	[void]($buttonPanel.Children.Add($btnContinue))

	$buttonBorder.Child = $buttonPanel
	[void]($outerGrid.Children.Add($buttonBorder))

	Complete-RoundedWindow -Window $dlg -ContentElement $outerGrid -RoundBorder $roundedParts.RoundBorder -DockPanel $roundedParts.DockPanel
	[void]($dlg.ShowDialog())
	return $resultRef.Value
}
