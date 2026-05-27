<#
    .SYNOPSIS
#>
function Show-GuiCommonThemedDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[string]$Title,
		[string]$Message,
		[string[]]$Buttons = @('OK'),
		[object]$UseDarkMode = $true,
		[string]$AccentButton = $null,
		[string]$DestructiveButton = $null
	)

	$bc = $Script:SharedBrushConverter
	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Show-GuiCommonThemedDialog'

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.MinWidth = $Script:GuiDialogDefaultWidth
	$dlg.MaxWidth = 640
	$dlg.SizeToContent = 'WidthAndHeight'
	$dlg.ResizeMode = 'NoResize'
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
		Write-GuiCommonWarning ("Failed to assign dialog owner for '{0}': {1}" -f $(if ($Title) { $Title } else { 'dialog' }), $_.Exception.Message)
	}
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$resolvedUseDarkMode)

	# Rounded container border
	$dlgRoundedBorder = New-Object System.Windows.Controls.Border
	$dlgRoundedBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$dlgRoundedBorder.Background = $bc.ConvertFromString($Theme.WindowBg)
	$dlgRoundedBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$dlgRoundedBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	$dlgRoundedBorder.ClipToBounds = $true

	# Title bar with drag and close
	$dlgTitleBar = New-Object System.Windows.Controls.Border
	$dlgTitleBar.Background = $bc.ConvertFromString($(if ($Theme.HeaderBg) { $Theme.HeaderBg } else { $Theme.WindowBg }))
	$dlgTitleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
	$dlgTitleBar.Padding = [System.Windows.Thickness]::new(12, 8, 8, 8)
	$dlgTitleBarGrid = New-Object System.Windows.Controls.Grid
	$dlgTitleBlock = New-Object System.Windows.Controls.TextBlock
	$dlgTitleBlock.Text = $Title
	$dlgTitleBlock.VerticalAlignment = 'Center'
	$dlgTitleBlock.FontSize = 12
	$dlgTitleBlock.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	[void]($dlgTitleBarGrid.Children.Add($dlgTitleBlock))
	$dlgCloseBtn = New-Object System.Windows.Controls.Button
	$dlgCloseBtn.Content = 'x'
	$dlgCloseBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Arial')
	$dlgCloseBtn.FontSize = 12
	$dlgCloseBtn.Width = 32
	$dlgCloseBtn.Height = 28
	$dlgCloseBtn.Background = [System.Windows.Media.Brushes]::Transparent
	$dlgCloseBtn.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlgCloseBtn.BorderThickness = [System.Windows.Thickness]::new(0)
	$dlgCloseBtn.Cursor = [System.Windows.Input.Cursors]::Hand
	$dlgCloseBtn.HorizontalAlignment = 'Right'
	$dlgCloseBtn.VerticalContentAlignment = 'Center'
	$dlgCloseBtn.HorizontalContentAlignment = 'Center'
	try { Set-GuiPopupCaptionButtonStyle -Button $dlgCloseBtn -Variant 'Close' -Theme $Theme -UseDarkMode $resolvedUseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Dialogs.ShowThemedDialog.SetCloseButtonStyle' }
	$dlgCloseBtn.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() }.GetNewClosure())
	[void]($dlgTitleBarGrid.Children.Add($dlgCloseBtn))
	$dlgTitleBar.Child = $dlgTitleBarGrid
	$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
	$dlgCtxMenu = New-Object System.Windows.Controls.ContextMenu
	$dlgCtxClose = New-Object System.Windows.Controls.MenuItem
	$dlgCtxClose.Header = 'Close'; $dlgCtxClose.InputGestureText = 'Alt+F4'; $dlgCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
	$dlgCtxRef = $dlg
	$dlgCtxClose.Add_Click({ $dlgCtxRef.DialogResult = $false; $dlgCtxRef.Close() }.GetNewClosure())
	[void]$dlgCtxMenu.Items.Add($dlgCtxClose)
	$dlgTitleBar.ContextMenu = $dlgCtxMenu

	$dlgOuterWrapper = New-Object System.Windows.Controls.DockPanel
	$dlgOuterWrapper.LastChildFill = $true
	[System.Windows.Controls.DockPanel]::SetDock($dlgTitleBar, [System.Windows.Controls.Dock]::Top)
	[void]($dlgOuterWrapper.Children.Add($dlgTitleBar))

	$outerStack = New-Object System.Windows.Controls.StackPanel

	$msgBorder = New-Object System.Windows.Controls.Border
	$msgBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
	$msgTb = New-Object System.Windows.Controls.TextBlock
	$msgTb.Text = $Message
	$msgTb.TextWrapping = 'Wrap'
	$msgTb.MaxWidth = $Script:GuiDialogDefaultWidth - 48
	$msgTb.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$msgTb.FontSize = $Script:GuiLayout.FontSizeBody
	$msgTb.LineHeight = $Script:GuiLayout.DialogLineHeight
	$msgBorder.Child = $msgTb
	[void]($outerStack.Children.Add($msgBorder))
	$btnBorder = New-Object System.Windows.Controls.Border
	$btnBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
	$btnBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$btnBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$btnBorder.CornerRadius = [System.Windows.CornerRadius]::new(0, 0, 8, 8)
	$btnBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	$btnPanel = New-Object System.Windows.Controls.StackPanel
	$btnPanel.Orientation = 'Horizontal'
	$btnPanel.HorizontalAlignment = 'Right'
	$resolveDialogButtonIcon = {
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
			'Save' { return 'Export' }
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
		Value = (Get-GuiDialogDismissResult -Buttons $Buttons)
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

		$buttonIconName = & $resolveDialogButtonIcon -Label $label -Accent $AccentButton -Destructive $DestructiveButton -ButtonCount $Buttons.Count
		if (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Set-GuiButtonIconContent -Button $btn -IconName $buttonIconName -Text $label -Gap 6
		}
		else
		{
			$btn.Content = $label
		}

		if ($label -eq $AccentButton -or (($null -eq $AccentButton -or [string]::IsNullOrWhiteSpace($AccentButton)) -and $Buttons.Count -eq 1))
		{
			$btn.IsDefault = $true
		}
		if ($label -eq 'Close' -or $label -eq 'Cancel')
		{
			$btn.IsCancel = $true
		}

		$btnLabel = $label
		$dlgRef = $dlg
		$resRef = $resultRef
		$btn.Add_Click({
			$resRef.Value = $btnLabel
			$dlgRef.Close()
		}.GetNewClosure())

		[void]($btnPanel.Children.Add($btn))
	}

	$btnBorder.Child = $btnPanel
	[void]($outerStack.Children.Add($btnBorder))
	[void]($dlgOuterWrapper.Children.Add($outerStack))
	$dlgRoundedBorder.Child = $dlgOuterWrapper
	$dlg.Content = $dlgRoundedBorder

	[void]($dlg.ShowDialog())
	return $resultRef.Value
}

<#
    .SYNOPSIS
#>
function New-DialogSummaryCard
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[string]$Label,

		[object]$Value,
		[string]$Detail,
		[string]$Tone = 'Primary'
	)

	$bc = $Script:SharedBrushConverter
	$card = New-Object System.Windows.Controls.Border
	$card.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
	$card.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
	$card.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
	$card.MinWidth = $Script:GuiLayout.CardMinWidth
	$card.Background = $bc.ConvertFromString($Theme.CardBg)
	$card.BorderThickness = [System.Windows.Thickness]::new(1)

	$labelBrush = $bc.ConvertFromString($Theme.TextMuted)
	$valueBrush = $bc.ConvertFromString($Theme.TextPrimary)
	$borderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$detailBrush = $bc.ConvertFromString($Theme.TextSecondary)

	switch ([string]$Tone)
	{
		'Danger'
		{
			$borderBrush = $bc.ConvertFromString($(if ($Theme.RiskHighBadge) { $Theme.RiskHighBadge } else { $Theme.CautionBorder }))
			$valueBrush = $bc.ConvertFromString($(if ($Theme.RiskHighBadge) { $Theme.RiskHighBadge } else { $Theme.CautionText }))
		}
		'Caution'
		{
			$borderBrush = $bc.ConvertFromString($(if ($Theme.CautionBorder) { $Theme.CautionBorder } else { $Theme.BorderColor }))
			$valueBrush = $bc.ConvertFromString($(if ($Theme.CautionText) { $Theme.CautionText } else { $Theme.TextPrimary }))
		}
		'Success'
		{
			$borderBrush = $bc.ConvertFromString($(if ($Theme.LowRiskBadge) { $Theme.LowRiskBadge } else { $Theme.BorderColor }))
			$valueBrush = $bc.ConvertFromString($(if ($Theme.LowRiskBadge) { $Theme.LowRiskBadge } else { $Theme.TextPrimary }))
		}
		'Muted'
		{
			$borderBrush = $bc.ConvertFromString($Theme.BorderColor)
			$valueBrush = $bc.ConvertFromString($Theme.TextSecondary)
		}
		'Primary'
		{
			$borderBrush = $bc.ConvertFromString($(if ($Theme.AccentBlue) { $Theme.AccentBlue } else { $Theme.BorderColor }))
			$valueBrush = $bc.ConvertFromString($(if ($Theme.AccentBlue) { $Theme.AccentBlue } else { $Theme.TextPrimary }))
		}
	}

	$card.BorderBrush = $borderBrush

	$stack = New-Object System.Windows.Controls.StackPanel
	$stack.Orientation = 'Vertical'

	$cardIconName = $null
	if (Get-Command -Name 'Get-GuiSummaryCardIconName' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$cardIconName = Get-GuiSummaryCardIconName -Label $Label
	}
	$labelIconContent = $null
	if ($cardIconName -and (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue))
	{
		$labelIconContent = New-GuiLabeledIconContent -IconName $cardIconName -Text $Label -IconSize 13 -Gap 6 -TextFontSize $Script:GuiLayout.FontSizeSmall -Foreground $labelBrush -AllowTextOnlyFallback -Bold
	}
	if ($labelIconContent)
	{
		[void]($stack.Children.Add($labelIconContent))
	}
	else
	{
		$labelBlock = New-Object System.Windows.Controls.TextBlock
		$labelBlock.Text = $Label
		$labelBlock.FontSize = $Script:GuiLayout.FontSizeSmall
		$labelBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
		$labelBlock.TextWrapping = 'Wrap'
		$labelBlock.Foreground = $labelBrush
		[void]($stack.Children.Add($labelBlock))
	}
	$valueBlock = New-Object System.Windows.Controls.TextBlock
	$valueText = [string]$Value
	if ([string]::IsNullOrWhiteSpace($valueText))
	{
		$valueText = '0'
	}
	$valueBlock.Text = $valueText
	$valueBlock.FontSize = $Script:GuiLayout.FontSizeHeading
	$valueBlock.FontWeight = [System.Windows.FontWeights]::Bold
	$valueBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
	$valueBlock.TextWrapping = 'Wrap'
	$valueBlock.Foreground = $valueBrush
	[void]($stack.Children.Add($valueBlock))
	if (-not [string]::IsNullOrWhiteSpace([string]$Detail))
	{
		$detailBlock = New-Object System.Windows.Controls.TextBlock
		$detailBlock.Text = [string]$Detail
		$detailBlock.FontSize = $Script:GuiLayout.FontSizeSmall
		$detailBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
		$detailBlock.TextWrapping = 'Wrap'
		$detailBlock.Foreground = $detailBrush
		[void]($stack.Children.Add($detailBlock))
	}

	$card.Child = $stack
	return $card
}

<#
    .SYNOPSIS
#>
function New-DialogSummaryCardsPanel
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[object[]]$SummaryCards
	)

	$panel = New-Object System.Windows.Controls.WrapPanel
	$panel.Orientation = 'Horizontal'
	$panel.HorizontalAlignment = 'Stretch'

	foreach ($summaryCard in @($SummaryCards))
	{
		if ($null -eq $summaryCard) { continue }
		$label = if ((Test-GuiCommonObjectField -Object $summaryCard -FieldName 'Label')) { [string]$summaryCard.Label } else { '' }
		if ([string]::IsNullOrWhiteSpace($label)) { continue }
		$summaryCardControl = New-DialogSummaryCard `
			-Theme $Theme `
			-Label $label `
			-Value $(if ((Test-GuiCommonObjectField -Object $summaryCard -FieldName 'Value')) { $summaryCard.Value } else { $null }) `
			-Detail $(if ((Test-GuiCommonObjectField -Object $summaryCard -FieldName 'Detail')) { [string]$summaryCard.Detail } else { $null }) `
			-Tone $(if ((Test-GuiCommonObjectField -Object $summaryCard -FieldName 'Tone')) { [string]$summaryCard.Tone } else { 'Primary' })
		if ($summaryCardControl)
		{
			[void]($panel.Children.Add($summaryCardControl))
		}
	}

	return $panel
}

<#
    .SYNOPSIS
#>
function New-DialogMetadataPill
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[string]$Label,

		[string]$Tone = 'Muted',
		[string]$ToolTip
	)

	if ([string]::IsNullOrWhiteSpace($Label)) { return $null }

	$bc = $Script:SharedBrushConverter
	$border = New-Object System.Windows.Controls.Border
	$border.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
	$border.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
	$border.Margin = [System.Windows.Thickness]::new(0, 0, 6, 6)
	$border.VerticalAlignment = 'Center'
	$border.BorderThickness = [System.Windows.Thickness]::new(1)

	$background = $Theme.StatusPillBg
	$borderBrush = $Theme.StatusPillBorder
	$foreground = $Theme.StatusPillText

	switch ([string]$Tone)
	{
		'Danger'
		{
			$background = $(if ($Theme.RiskHighBadgeBg) { $Theme.RiskHighBadgeBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.RiskHighBadgeBg) { $Theme.RiskHighBadgeBg } else { $Theme.StatusPillBorder })
			$foreground = $(if ($Theme.RiskHighBadge) { $Theme.RiskHighBadge } else { $Theme.CautionText })
		}
		'Caution'
		{
			$background = $(if ($Theme.RiskMediumBadgeBg) { $Theme.RiskMediumBadgeBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.RiskMediumBadgeBg) { $Theme.RiskMediumBadgeBg } else { $Theme.StatusPillBorder })
			$foreground = $(if ($Theme.RiskMediumBadge) { $Theme.RiskMediumBadge } else { $Theme.CautionText })
		}
		'Success'
		{
			$background = $(if ($Theme.LowRiskBadgeBg) { $Theme.LowRiskBadgeBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.LowRiskBadgeBg) { $Theme.LowRiskBadgeBg } else { $Theme.StatusPillBorder })
			$foreground = $(if ($Theme.LowRiskBadge) { $Theme.LowRiskBadge } else { $Theme.StatusPillText })
		}
		'Primary'
		{
			$background = $Theme.StatusPillBg
			$borderBrush = $Theme.StatusPillBorder
			$foreground = $Theme.StatusPillText
		}
		'Muted'
		{
			$background = $Theme.StatusPillBg
			$borderBrush = $Theme.StatusPillBorder
			$foreground = $Theme.StatusPillText
		}
	}

	$border.Background = $bc.ConvertFromString($background)
	$border.BorderBrush = $bc.ConvertFromString($borderBrush)

	$txt = New-Object System.Windows.Controls.TextBlock
	$txt.Text = $Label
	$txt.FontSize = $Script:GuiLayout.FontSizeSmall
	$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
	$txt.Foreground = $bc.ConvertFromString($foreground)
	$border.Child = $txt

	if (-not [string]::IsNullOrWhiteSpace($ToolTip))
	{
		$border.ToolTip = $ToolTip
	}

	return $border
}

<#
    .SYNOPSIS
#>
function New-DialogMetadataPillPanel
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[object[]]$Items
	)

	$panel = New-Object System.Windows.Controls.WrapPanel
	$panel.Orientation = 'Horizontal'
	$panel.HorizontalAlignment = 'Stretch'

	foreach ($item in @($Items))
	{
		if ($null -eq $item) { continue }
		$label = if ((Test-GuiCommonObjectField -Object $item -FieldName 'Label')) { [string]$item.Label } else { '' }
		if ([string]::IsNullOrWhiteSpace($label)) { continue }
		$pill = New-DialogMetadataPill `
			-Theme $Theme `
			-Label $label `
			-Tone $(if ((Test-GuiCommonObjectField -Object $item -FieldName 'Tone')) { [string]$item.Tone } else { 'Muted' }) `
			-ToolTip $(if ((Test-GuiCommonObjectField -Object $item -FieldName 'ToolTip')) { [string]$item.ToolTip } else { $null })
		if ($pill)
		{
			[void]($panel.Children.Add($pill))
		}
	}

	return $panel
}
