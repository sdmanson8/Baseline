
# NOTE: This function is ~700 lines and contains duplicated status-styling logic
#   1. A status-styling lookup table (OutcomeState -> color/icon/label)
#   2. A card/row builder helper to reduce per-status boilerplate
#   3. Filter/grouping logic into a separate function
# The current implementation works correctly; the concern is maintainability.
<#
    .SYNOPSIS
#>
function Show-GuiCommonExecutionSummaryDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[object[]]$Results,
		[string]$Title = $null,
		[string]$SummaryText,
		[string]$LogPath,
		[object[]]$SummaryCards = @(),
		[string[]]$Buttons = @('Close'),
		[hashtable]$Strings = @{},
		[object]$UseDarkMode = $true
	)

	$bc = $Script:SharedBrushConverter
	$results = @($Results)
	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Show-GuiCommonExecutionSummaryDialog'

	# Localization helper: resolve at runtime, fall back to English if not available
	$getLocalStr = Get-Command -Name 'Get-UxLocalizedString' -CommandType Function -ErrorAction SilentlyContinue
	$L = { param([string]$Key, [string]$Fallback) if ($getLocalStr) { & $getLocalStr -Key $Key -Fallback $Fallback } else { $Fallback } }

	if ([string]::IsNullOrWhiteSpace($Title)) { $Title = (& $L 'GuiCommonExecutionSummary' 'Execution Summary') }

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = $Script:GuiLayout.DialogLargeWidth
	$dlg.Height = $Script:GuiLayout.DialogLargeHeight
	$dlg.MinWidth = $Script:GuiLayout.DialogLargeMinWidth
	$dlg.MinHeight = $Script:GuiLayout.DialogLargeMinHeight
	$dlg.ResizeMode = 'CanResizeWithGrip'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('FluentSystemIcons')
	$dlg.FontSize = $Script:GuiLayout.FontSizeBody
	$dlg.ShowInTaskbar = $false
	$dlg.WindowStyle = 'None'
	$dlg.AllowsTransparency = $true
	$dlg.Background = [System.Windows.Media.Brushes]::Transparent

	try
	{
		if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
	}
	catch
	{
		Write-GuiCommonWarning ("Failed to assign dialog owner for '{0}': {1}" -f $(if ($Title) { $Title } else { 'execution summary' }), $_.Exception.Message)
	}
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$resolvedUseDarkMode)

	# Rounded container
	$dlgRoundBorder = New-Object System.Windows.Controls.Border
	$dlgRoundBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$dlgRoundBorder.Background = $bc.ConvertFromString($Theme.WindowBg)
	$dlgRoundBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$dlgRoundBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	$dlgDock = New-Object System.Windows.Controls.DockPanel
	$dlgDock.LastChildFill = $true

	# Title bar
	$dlgTBar = New-Object System.Windows.Controls.Border
	$dlgTBar.Background = $bc.ConvertFromString($(if ($Theme.HeaderBg) { $Theme.HeaderBg } else { $Theme.WindowBg }))
	$dlgTBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
	$dlgTBar.Padding = [System.Windows.Thickness]::new(12, 8, 8, 8)
	$dlgTBarGrid = New-Object System.Windows.Controls.Grid
	$dlgTBarTitle = New-Object System.Windows.Controls.TextBlock
	$dlgTBarTitle.Text = $Title
	$dlgTBarTitle.VerticalAlignment = 'Center'
	$dlgTBarTitle.FontSize = 12
	$dlgTBarTitle.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	[void]($dlgTBarGrid.Children.Add($dlgTBarTitle))
	$dlgTBarClose = New-Object System.Windows.Controls.Button
	$dlgTBarClose.Content = 'x'
	$dlgTBarClose.FontFamily = [System.Windows.Media.FontFamily]::new('Arial')
	$dlgTBarClose.FontSize = 12
	$dlgTBarClose.Width = 32
	$dlgTBarClose.Height = 28
	$dlgTBarClose.Background = [System.Windows.Media.Brushes]::Transparent
	$dlgTBarClose.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlgTBarClose.BorderThickness = [System.Windows.Thickness]::new(0)
	$dlgTBarClose.Cursor = [System.Windows.Input.Cursors]::Hand
	$dlgTBarClose.HorizontalAlignment = 'Right'
	$dlgTBarClose.VerticalContentAlignment = 'Center'
	$dlgTBarClose.HorizontalContentAlignment = 'Center'
	$dlgTBarClose.Add_Click({ $dlg.Close() }.GetNewClosure())
	[void]($dlgTBarGrid.Children.Add($dlgTBarClose))
	$dlgTBar.Child = $dlgTBarGrid
	$dlgTBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
	$dlgTBarCtx2 = New-Object System.Windows.Controls.ContextMenu
	$dlgTBarCtx2Close = New-Object System.Windows.Controls.MenuItem
	$dlgTBarCtx2Close.Header = 'Close'; $dlgTBarCtx2Close.InputGestureText = 'Alt+F4'; $dlgTBarCtx2Close.FontWeight = [System.Windows.FontWeights]::Bold
	$dlgTBarCtx2Ref = $dlg
	$dlgTBarCtx2Close.Add_Click({ $dlgTBarCtx2Ref.Close() }.GetNewClosure())
	[void]$dlgTBarCtx2.Items.Add($dlgTBarCtx2Close)
	$dlgTBar.ContextMenu = $dlgTBarCtx2
	[System.Windows.Controls.DockPanel]::SetDock($dlgTBar, [System.Windows.Controls.Dock]::Top)
	[void]($dlgDock.Children.Add($dlgTBar))

	$outerGrid = New-Object System.Windows.Controls.Grid
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
	[void]($outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
	$headerBorder = New-Object System.Windows.Controls.Border
	$headerBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 16)
	$headerBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$headerBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
	[System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

	$headerStack = New-Object System.Windows.Controls.StackPanel
	$headerStack.Orientation = 'Vertical'

	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.Text = $Title
	$titleText.FontSize = $Script:GuiLayout.FontSizeHeading
	$titleText.FontWeight = [System.Windows.FontWeights]::Bold
	$titleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	[void]($headerStack.Children.Add($titleText))
	if (-not [string]::IsNullOrWhiteSpace($SummaryText))
	{
		$summaryBlock = New-Object System.Windows.Controls.TextBlock
		$summaryBlock.Text = $SummaryText
		$summaryBlock.TextWrapping = 'Wrap'
		$summaryBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$summaryBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		[void]($headerStack.Children.Add($summaryBlock))
	}

	if (-not [string]::IsNullOrWhiteSpace($LogPath))
	{
		$logPathBlock = New-Object System.Windows.Controls.TextBlock
		$logFilePrefix = if ($Strings.ContainsKey('LogFilePrefix')) { [string]$Strings.LogFilePrefix } else { & $L 'GuiCommonLogFilePrefix' 'Log file' }
		$logPathBlock.Text = "{0}: {1}" -f $logFilePrefix, $LogPath
		$logPathBlock.TextWrapping = 'Wrap'
		$logPathBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$logPathBlock.Foreground = $bc.ConvertFromString($Theme.TextMuted)
		$logPathBlock.FontSize = $Script:GuiLayout.FontSizeLabel
		[void]($headerStack.Children.Add($logPathBlock))
	}

	$headerBorder.Child = $headerStack
	[void]($outerGrid.Children.Add($headerBorder))
	$listScroll = New-Object System.Windows.Controls.ScrollViewer
	$listScroll.VerticalScrollBarVisibility = 'Auto'
	$listScroll.HorizontalScrollBarVisibility = 'Disabled'
	$listScroll.Margin = [System.Windows.Thickness]::new(0)
	[System.Windows.Controls.Grid]::SetRow($listScroll, 1)

	$listStack = New-Object System.Windows.Controls.StackPanel
	$listStack.Orientation = 'Vertical'
	$listStack.Margin = [System.Windows.Thickness]::new(18, 16, 18, 16)

	if (@($SummaryCards).Count -gt 0)
	{
		$summaryHeader = New-Object System.Windows.Controls.TextBlock
		$summaryHeader.Text = $(if ($Strings.ContainsKey('ImpactSummary')) { [string]$Strings.ImpactSummary } else { & $L 'GuiCommonImpactSummary' 'Impact summary' })
		$summaryHeader.FontSize = $Script:GuiLayout.FontSizeLabel
		$summaryHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
		$summaryHeader.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$summaryHeader.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($listStack.Children.Add($summaryHeader))
		$summaryBorder = New-Object System.Windows.Controls.Border
		$summaryBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$summaryBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		$summaryBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$summaryBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$summaryBorder.Padding = [System.Windows.Thickness]::new(12, 12, 12, 4)
		$summaryBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
		$summaryBorder.Child = (New-DialogSummaryCardsPanel -Theme $Theme -SummaryCards $SummaryCards)
		[void]($listStack.Children.Add($summaryBorder))
	}

	# -- Status filter bar ------------------------------------------
	# Clickable status pills that filter the results list below.
	# Only shown for non-preview (post-execution) results.
	$statusFilterActiveRef = @{ Value = $null }  # tracks active filter; $null = show all
	$allResultCards = [System.Collections.Generic.List[object]]::new()  # populated during card build
	$allResultStatusMap = [System.Collections.Generic.List[string]]::new()  # parallel list of status category per card
	$filterBarPanel = $null
	$filterPillButtons = @{}

	$isPreviewModeForFilter = @($Results | Where-Object { @('Already in desired state', 'Will change', 'Requires restart', 'High-risk changes', 'Not fully restorable', 'Preview') -contains [string]$_.Status }).Count -gt 0
		. (Join-Path $PSScriptRoot 'ExecutionSummaryDialog\Show-GuiCommonExecutionSummaryDialog\StatusFilterChips.ps1')
	# -- End status filter bar --------------------------------------

	$previewStatusOrder = @{
		'Already in desired state' = 0
		'Will change' = 1
		'Requires restart' = 2
		'High-risk changes' = 3
		'Not fully restorable' = 4
		'Preview' = 1
	}
	$previewStatuses = @('Already in desired state', 'Will change', 'Requires restart', 'High-risk changes', 'Not fully restorable', 'Preview')
	$isPreviewMode = @($results | Where-Object { $previewStatuses -contains [string]$_.Status }).Count -gt 0
	$hasPreviewGroups = @($results | Where-Object { (Test-GuiCommonObjectField -Object $_ -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$_.PreviewGroupHeader) }).Count -gt 0
	$displayResults = if ($isPreviewMode)
	{
		if ($hasPreviewGroups)
		{
			@($results | Sort-Object `
				@{ Expression = { if ((Test-GuiCommonObjectField -Object $_ -FieldName 'PreviewGroupSortOrder')) { [int]$_.PreviewGroupSortOrder } else { 99 } } }, `
				@{ Expression = { if ($previewStatusOrder.ContainsKey([string]$_.Status)) { [int]$previewStatusOrder[[string]$_.Status] } else { 99 } } }, `
				@{ Expression = { [int]$_.Order } })
		}
		else
		{
			@($results | Sort-Object `
				@{ Expression = { if ($previewStatusOrder.ContainsKey([string]$_.Status)) { [int]$previewStatusOrder[[string]$_.Status] } else { 99 } } }, `
				@{ Expression = { [int]$_.Order } })
		}
	}
	else
	{
		$results
	}
	$lastPreviewSection = $null

	# Pre-compute frequently used brushes before the loop to avoid repeated
	# ConvertFromString calls (saves hundreds of conversions for 269+ results).
	$preThickness1 = [System.Windows.Thickness]::new(1)
	$preBrushCardBg = $bc.ConvertFromString($Theme.CardBg)
	$preBrushCardBorder = $bc.ConvertFromString($Theme.CardBorder)
	$preBrushTextPrimary = $bc.ConvertFromString($Theme.TextPrimary)
	$preBrushTextSecondary = $bc.ConvertFromString($Theme.TextSecondary)
	$preBrushTextMuted = $bc.ConvertFromString($Theme.TextMuted)
	$preBrushSectionLabel = $bc.ConvertFromString($Theme.SectionLabel)
	$preBrushCautionText = $bc.ConvertFromString($Theme.CautionText)
	$preStatusBrushes = @{
		'Failed'                = @{ Bg = $bc.ConvertFromString($Theme.RiskHighBadgeBg); Border = $bc.ConvertFromString($Theme.RiskHighBadge); Fg = $bc.ConvertFromString($Theme.RiskHighBadge) }
		'High-risk changes'     = @{ Bg = $bc.ConvertFromString($Theme.RiskHighBadgeBg); Border = $bc.ConvertFromString($Theme.RiskHighBadge); Fg = $bc.ConvertFromString($Theme.RiskHighBadge) }
		'Not fully restorable'  = @{ Bg = $bc.ConvertFromString($Theme.RiskHighBadgeBg); Border = $bc.ConvertFromString($Theme.RiskHighBadge); Fg = $bc.ConvertFromString($Theme.RiskHighBadge) }
		'Requires restart'      = @{ Bg = $bc.ConvertFromString($Theme.RiskMediumBadgeBg); Border = $bc.ConvertFromString($Theme.RiskMediumBadge); Fg = $bc.ConvertFromString($Theme.RiskMediumBadge) }
		'Restart pending'       = @{ Bg = $bc.ConvertFromString($Theme.RiskMediumBadgeBg); Border = $bc.ConvertFromString($Theme.RiskMediumBadge); Fg = $bc.ConvertFromString($Theme.RiskMediumBadge) }
		'Will change'           = @{ Bg = $bc.ConvertFromString($Theme.StatusPillBg); Border = $bc.ConvertFromString($Theme.StatusPillBorder); Fg = $bc.ConvertFromString($Theme.StatusPillText) }
		'Already in desired state' = @{ Bg = $bc.ConvertFromString($Theme.LowRiskBadgeBg); Border = $bc.ConvertFromString($Theme.LowRiskBadge); Fg = $bc.ConvertFromString($Theme.LowRiskBadge) }
		'Preview'               = @{ Bg = $bc.ConvertFromString($Theme.StatusPillBg); Border = $bc.ConvertFromString($Theme.StatusPillBorder); Fg = $bc.ConvertFromString($Theme.StatusPillText) }
		'Skipped'               = @{ Bg = $bc.ConvertFromString($Theme.TabBg); Border = $bc.ConvertFromString($Theme.BorderColor); Fg = $bc.ConvertFromString($Theme.TextSecondary) }
		'Not applicable'        = @{ Bg = $bc.ConvertFromString($Theme.TabBg); Border = $bc.ConvertFromString($Theme.BorderColor); Fg = $bc.ConvertFromString($Theme.TextSecondary) }
		'Not Run'               = @{ Bg = $bc.ConvertFromString($Theme.TabBg); Border = $bc.ConvertFromString($Theme.CautionBorder); Fg = $bc.ConvertFromString($Theme.CautionText) }
	}
	$preDefaultStatusBrushes = @{ Bg = $bc.ConvertFromString($Theme.LowRiskBadgeBg); Border = $bc.ConvertFromString($Theme.LowRiskBadge); Fg = $bc.ConvertFromString($Theme.LowRiskBadge) }

	# Suspend layout while adding all result cards to avoid per-child
	# Measure/Arrange cycles that make the dialog slow to open.
	try { $listStack.BeginInit() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionSummaryDialog.Show-GuiCommonExecutionSummaryDialog.ListStackBeginInit' }

	# Limit the initial batch to keep dialog open time fast; remaining
	# results are loaded when the user scrolls or clicks "Show all".
	$initialBatchLimit = 50
	$resultIndex = 0
	$totalResultCount = $displayResults.Count

		. (Join-Path $PSScriptRoot 'ExecutionSummaryDialog\Show-GuiCommonExecutionSummaryDialog\ResultRows.ps1')

	# If we cut the loop short, add a "Show all" button that loads the rest.
		. (Join-Path $PSScriptRoot 'ExecutionSummaryDialog\Show-GuiCommonExecutionSummaryDialog\ShowAllResultsExpansion.ps1')

	# -- Restart-required informational section ---------------------
	$restartPendingItems = @($results | Where-Object {
		[string]$_.Status -eq 'Restart pending' -or
		((Test-GuiCommonObjectField -Object $_ -FieldName 'RequiresRestart') -and [bool]$_.RequiresRestart)
	})
	if ($restartPendingItems.Count -gt 0)
	{
		$restartSectionBorder = New-Object System.Windows.Controls.Border
		$restartSectionBorder.Background = $bc.ConvertFromString($Theme.RiskMediumBadgeBg)
		$restartSectionBorder.BorderBrush = $bc.ConvertFromString($Theme.RiskMediumBadge)
		$restartSectionBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$restartSectionBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$restartSectionBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
		$restartSectionBorder.Margin = [System.Windows.Thickness]::new(0, 6, 0, 10)

		$restartSectionStack = New-Object System.Windows.Controls.StackPanel
		$restartSectionStack.Orientation = 'Vertical'

		$restartTitle = New-Object System.Windows.Controls.TextBlock
		$restartTitle.Text = (& $L 'GuiCommonRestartRequired' 'These changes need a restart to take effect:')
		$restartTitle.FontSize = $Script:GuiLayout.FontSizeBody
		$restartTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
		$restartTitle.Foreground = $bc.ConvertFromString($Theme.RiskMediumBadge)
		$restartTitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($restartSectionStack.Children.Add($restartTitle))

		foreach ($restartItem in $restartPendingItems)
		{
			$restartItemBlock = New-Object System.Windows.Controls.TextBlock
			$restartItemBlock.Text = [string]([char]0x2022) + '  ' + [string]$restartItem.Name
			$restartItemBlock.TextWrapping = 'Wrap'
			$restartItemBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$restartItemBlock.Foreground = $bc.ConvertFromString($Theme.RiskMediumBadge)
			$restartItemBlock.Margin = [System.Windows.Thickness]::new(4, 2, 0, 2)
			[void]($restartSectionStack.Children.Add($restartItemBlock))
		}

		$restartSectionBorder.Child = $restartSectionStack
		[void]($listStack.Children.Add($restartSectionBorder))
	}
	# -- End restart-required section -------------------------------

	if ($results.Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = (& $L 'GuiCommonNoExecutionResults' 'No execution results are available for this run.')
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		[void]($listStack.Children.Add($emptyBlock))
	}

	try { $listStack.EndInit() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionSummaryDialog.Show-GuiCommonExecutionSummaryDialog.ListStackEndInit' }
	$listScroll.Content = $listStack
	[void]($outerGrid.Children.Add($listScroll))
	$buttonBorder = New-Object System.Windows.Controls.Border
	$buttonBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
	$buttonBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$buttonBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$buttonBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	[System.Windows.Controls.Grid]::SetRow($buttonBorder, 2)

	$buttonPanel = New-Object System.Windows.Controls.WrapPanel
	$buttonPanel.Orientation = 'Horizontal'
	$buttonPanel.HorizontalAlignment = 'Right'

	$resultRef = @{
		Value = (Get-GuiDialogDismissResult -Buttons $Buttons)
	}

		. (Join-Path $PSScriptRoot 'ExecutionSummaryDialog\Show-GuiCommonExecutionSummaryDialog\DialogButtons.ps1')

	$buttonBorder.Child = $buttonPanel
	[void]($outerGrid.Children.Add($buttonBorder))
	[void]($dlgDock.Children.Add($outerGrid))
	$dlgRoundBorder.Child = $dlgDock
	$dlg.Content = $dlgRoundBorder

	[void]($dlg.ShowDialog())
	return $resultRef.Value
}
