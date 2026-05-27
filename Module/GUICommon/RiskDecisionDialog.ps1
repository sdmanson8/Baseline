<#
    .SYNOPSIS
#>
function Show-GuiCommonRiskDecisionDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[string]$Title = 'Warning',
		[string]$Message,
		[object[]]$SummaryCards = @(),
		[string[]]$Buttons = @('Cancel', 'Preview Run', 'Run Anyway'),
		[object]$UseDarkMode = $true,
		[string]$AccentButton = $null,
		[string]$DestructiveButton = $null
	)

	$bc = $Script:SharedBrushConverter
	$cards = @($SummaryCards)
	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Show-GuiCommonRiskDecisionDialog'

	# Localization helper
	$getLocalStr2 = Get-Command -Name 'Get-UxLocalizedString' -CommandType Function -ErrorAction SilentlyContinue
	$L2 = { param([string]$Key, [string]$Fallback) if ($getLocalStr2) { & $getLocalStr2 -Key $Key -Fallback $Fallback } else { $Fallback } }

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = 780
	$dlg.Height = 620
	$dlg.MinWidth = 700
	$dlg.MinHeight = 520
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
		Write-GuiCommonWarning ("Failed to assign dialog owner for '{0}': {1}" -f $(if ($Title) { $Title } else { 'message dialog' }), $_.Exception.Message)
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
	if (-not [string]::IsNullOrWhiteSpace($Message))
	{
		$messageBlock = New-Object System.Windows.Controls.TextBlock
		$messageBlock.Text = $Message
		$messageBlock.TextWrapping = 'Wrap'
		$messageBlock.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
		$messageBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$messageBlock.LineHeight = 20
		[void]($headerStack.Children.Add($messageBlock))
	}

	$headerBorder.Child = $headerStack
	[void]($outerGrid.Children.Add($headerBorder))
	$bodyScroll = New-Object System.Windows.Controls.ScrollViewer
	$bodyScroll.VerticalScrollBarVisibility = 'Auto'
	$bodyScroll.HorizontalScrollBarVisibility = 'Disabled'
	[System.Windows.Controls.Grid]::SetRow($bodyScroll, 1)

	$bodyStack = New-Object System.Windows.Controls.StackPanel
	$bodyStack.Orientation = 'Vertical'
	$bodyStack.Margin = [System.Windows.Thickness]::new(18, 16, 18, 16)

	if ($cards.Count -gt 0)
	{
		$cardsHeader = New-Object System.Windows.Controls.TextBlock
		$cardsHeader.Text = (& $L2 'GuiCommonSummary' 'Summary')
		$cardsHeader.FontSize = $Script:GuiLayout.FontSizeLabel
		$cardsHeader.FontWeight = [System.Windows.FontWeights]::SemiBold
		$cardsHeader.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$cardsHeader.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
		[void]($bodyStack.Children.Add($cardsHeader))
		$cardsBorder = New-Object System.Windows.Controls.Border
		$cardsBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$cardsBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		$cardsBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$cardsBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$cardsBorder.Padding = [System.Windows.Thickness]::new(12, 12, 12, 4)
		$cardsBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
		$cardsBorder.Child = (New-DialogSummaryCardsPanel -Theme $Theme -SummaryCards $cards)
		[void]($bodyStack.Children.Add($cardsBorder))
	}

	$bodyScroll.Content = $bodyStack
	[void]($outerGrid.Children.Add($bodyScroll))
	$buttonBorder = New-Object System.Windows.Controls.Border
	$buttonBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
	$buttonBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$buttonBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$buttonBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	[System.Windows.Controls.Grid]::SetRow($buttonBorder, 2)

	$buttonPanel = New-Object System.Windows.Controls.StackPanel
	$buttonPanel.Orientation = 'Horizontal'
	$buttonPanel.HorizontalAlignment = 'Right'
	$resolveRiskDialogButtonIcon = {
		param(
			[string]$Label,
			[string]$Accent,
			[string]$Destructive,
			[int]$ButtonCount
		)

		switch ([string]$Label)
		{
			'Cancel' { return 'Clear' }
			'Close' { return 'Clear' }
			'No' { return 'Clear' }
			'OK' { return 'Passed' }
			'Yes' { return 'Passed' }
			'Apply' { return 'Passed' }
			'Continue' { return 'Passed' }
			'Run Anyway' { return 'Warning' }
		}

		if ($Label -eq $Accent -or (($null -eq $Accent -or [string]::IsNullOrWhiteSpace($Accent)) -and $ButtonCount -eq 1))
		{
			return 'Passed'
		}

		if ($Label -eq $Destructive)
		{
			return 'Warning'
		}

		return 'Info'
	}

	$resultRef = @{
		Value = $(if ($Buttons -contains 'Cancel') { 'Cancel' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.MinWidth = $Script:GuiLayout.ButtonMinWidth
		$btn.Height = $Script:GuiLayout.ButtonHeight
		$btn.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)

		if ($label -eq $AccentButton)
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Primary'
		}
		elseif ($label -eq $DestructiveButton)
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Danger'
		}
		else
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Secondary'
		}

		$buttonIconName = & $resolveRiskDialogButtonIcon -Label $label -Accent $AccentButton -Destructive $DestructiveButton -ButtonCount $Buttons.Count
		if (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Set-GuiButtonIconContent -Button $btn -IconName $buttonIconName -Text $label -Gap 6
		}
		else
		{
			$btn.Content = $label
		}

		# Make Cancel the keyboard-default (Enter) and Escape target so the safe
		# action has the most prominent interaction path for destructive dialogs.
		if ($label -eq 'Cancel')
		{
			$btn.IsDefault = $true
			$btn.IsCancel = $true
		}

		$btnLabel = $label
		$dlgRef = $dlg
		$resRef = $resultRef
		$btn.Add_Click({
			$resRef.Value = $btnLabel
			$dlgRef.Close()
		}.GetNewClosure())

		[void]($buttonPanel.Children.Add($btn))
	}

	$buttonBorder.Child = $buttonPanel
	[void]($outerGrid.Children.Add($buttonBorder))
	[void]($dlgDock.Children.Add($outerGrid))
	$dlgRoundBorder.Child = $dlgDock
	$dlg.Content = $dlgRoundBorder

	[void]($dlg.ShowDialog())
	return $resultRef.Value
}
