using module .\Logging.psm1

# Lightweight field-existence check used throughout GUICommon and GUI modules.
# Defined here so it is available as soon as GUICommon.psm1 loads, before
# GUI.psm1 dot-sources its extracted scripts.
function Test-GuiObjectField
{
	param([object]$Object, [string]$FieldName)
	if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName)) { return $false }
	if ($Object -is [System.Collections.IDictionary]) { return [bool]$Object.Contains($FieldName) }
	return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
}

function Get-GuiObjectField
{
	param([object]$Object, [string]$FieldName)
	if (-not (Test-GuiObjectField -Object $Object -FieldName $FieldName)) { return $null }
	if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }
	return $Object.$FieldName
}

$Script:SharedBrushConverter = [System.Windows.Media.BrushConverter]::new()
$Script:GuiCommonWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Centralized GUI layout constants -- keeps magic numbers in one place for consistency.
$Script:GuiLayout = @{
	# Font sizes (px)
	FontSizeTitle         = 16
	FontSizeHeading       = 18
	FontSizeSection       = 14
	FontSizeBody          = 13
	FontSizeSubheading    = 12
	FontSizeLabel         = 11
	FontSizeSmall         = 10
	FontSizeTiny          = 9

	# Main window dimensions (px)
	WindowMinWidth        = 940
	WindowMinHeight       = 660

	# Dialog dimensions (px)
	DialogDefaultWidth    = 440
	DialogLargeWidth      = 760
	DialogLargeHeight     = 620
	DialogLargeMinWidth   = 680
	DialogLargeMinHeight  = 520
	HelpDialogWidth       = 580
	HelpDialogHeight      = 620
	HelpDialogMinWidth    = 420
	HelpDialogMinHeight   = 400
	LogDialogWidth        = 780
	LogDialogHeight       = 640
	LogDialogMinWidth     = 500
	LogDialogMinHeight    = 300

	# Button dimensions (px)
	ButtonMinWidth        = 112
	ButtonHeight          = 34
	ButtonLargeHeight     = 40
	ButtonAbortMinWidth   = 104

	# Progress section (px)
	ProgressBarHeight     = 18
	ProgressBarMinWidth   = 200
	ProgressColumnWidth   = 124

	# Card layout (px)
	CardCornerRadius      = 8
	CardMinWidth          = 150
	PillCornerRadius      = 999
	BorderRadiusSmall     = 6
	BorderRadiusLarge     = 10

	# Component dimensions (px)
	ComboBoxMinWidth      = 220
	ComboBoxCompareWidth  = 160
	ComboBoxCompareHeight = 28
	TooltipMaxWidth       = 320
	CheckBoxMinHeight     = 24
	ScrollBarWidth        = 6
	PanelHorizontalPad    = 24

	# Timing (ms)
	SearchRefreshDelayMs  = 300

	# Shadow effect
	ShadowDirection       = 270

	# Line heights (px)
	DialogLineHeight      = 20
}
# Legacy alias kept for any external references
$Script:GuiDialogDefaultWidth = $Script:GuiLayout.DialogDefaultWidth

function Get-GuiLayout
{
	return [hashtable]$Script:GuiLayout.Clone()
}

function Write-GuiCommonWarning
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	$shouldLog = $true
	if ($Script:GuiCommonWarnings)
	{
		try
		{
			$shouldLog = $Script:GuiCommonWarnings.Add($Message)
		}
		catch
		{
			$shouldLog = $true
		}
	}

	if ($shouldLog)
	{
		LogWarning $Message
	}
}

function Initialize-GuiDpiAwareness
{
	param ()

	if (-not ('WinAPI.GuiDpiHelper' -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class GuiDpiHelper
	{
		// PROCESS_PER_MONITOR_DPI_AWARE_V2 = 2 (Windows 10 1703+)
		// Falls back to PROCESS_PER_MONITOR_DPI_AWARE = 2 via shcore on older builds
		[DllImport("user32.dll", SetLastError = true)]
		public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

		[DllImport("shcore.dll", SetLastError = true)]
		public static extern int SetProcessDpiAwareness(int awareness);

		public static void Enable()
		{
			try
			{
				// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
				if (!SetProcessDpiAwarenessContext(new IntPtr(-4)))
				{
					// Fallback: PROCESS_PER_MONITOR_DPI_AWARE = 2
					SetProcessDpiAwareness(2);
				}
			}
			catch
			{
				try { SetProcessDpiAwareness(2); } catch { }
			}
		}
	}
}
"@ -ErrorAction Stop | Out-Null
	}

	try { [WinAPI.GuiDpiHelper]::Enable() } catch { <# non-fatal #> }
}

function Initialize-GuiWindowChromeInterop
{
	param ()

	if (-not ('WinAPI.GuiWindowChrome' -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class GuiWindowChrome
	{
		[DllImport("dwmapi.dll")]
		public static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref int pvAttribute, int cbAttribute);

		[DllImport("user32.dll")]
		public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

		[DllImport("user32.dll")]
		public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

		[DllImport("user32.dll")]
		public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

function Invoke-GuiWindowChromeThemeUpdate
{
	param(
		[Parameter(Mandatory = $true)]
		$Window,

		[bool]$UseDarkMode = $true
	)

	try
	{
		Initialize-GuiWindowChromeInterop
	}
	catch
	{
		Write-GuiCommonWarning ("Failed to initialize DWM window chrome interop: {0}" -f $_.Exception.Message)
		return $false
	}

	$windowHandle = [IntPtr]::Zero
	try
	{
		$interopHelper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
		$windowHandle = $interopHelper.Handle
	}
	catch
	{
		Write-GuiCommonWarning ("Failed to resolve a window handle for chrome theming: {0}" -f $_.Exception.Message)
		return $false
	}

	if ($windowHandle -eq [IntPtr]::Zero)
	{
		return $false
	}

	$immersiveDarkModeAttribute = if ([Environment]::OSVersion.Version.Build -ge 18362) { 20 } else { 19 }
	$attributeValue = if ($UseDarkMode) { 1 } else { 0 }

	try
	{
		$result = [WinAPI.GuiWindowChrome]::DwmSetWindowAttribute($windowHandle, $immersiveDarkModeAttribute, [ref]$attributeValue, 4)
		if ($result -ne 0)
		{
			Write-GuiCommonWarning ("DwmSetWindowAttribute returned 0x{0:X8} while applying {1} chrome." -f ($result -band 0xFFFFFFFF), $(if ($UseDarkMode) { 'dark' } else { 'light' }))
			return $false
		}
	}
	catch
	{
		Write-GuiCommonWarning ("Failed to apply window chrome theming: {0}" -f $_.Exception.Message)
		return $false
	}

	# Apply Windows 11 rounded corners (DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2)
	if ([Environment]::OSVersion.Version.Build -ge 22000)
	{
		try
		{
			$cornerPreference = 2
			[void]([WinAPI.GuiWindowChrome]::DwmSetWindowAttribute($windowHandle, 33, [ref]$cornerPreference, 4))
		}
		catch { }
	}

	# Force non-client area repaint so title bar buttons update immediately
	try
	{
		# SWP_FRAMECHANGED (0x20) | SWP_NOMOVE (0x2) | SWP_NOSIZE (0x1) | SWP_NOZORDER (0x4)
		[void]([WinAPI.GuiWindowChrome]::SetWindowPos($windowHandle, [IntPtr]::Zero, 0, 0, 0, 0, 0x27))
		# WM_NCACTIVATE with wParam=1 forces Windows to repaint the title bar chrome
		[void]([WinAPI.GuiWindowChrome]::SendMessage($windowHandle, 0x0086, [IntPtr]::new(1), [IntPtr]::Zero))
		[void]([WinAPI.GuiWindowChrome]::SendMessage($windowHandle, 0x0086, [IntPtr]::new(0), [IntPtr]::Zero))
		[void]([WinAPI.GuiWindowChrome]::SendMessage($windowHandle, 0x0086, [IntPtr]::new(1), [IntPtr]::Zero))
		# RDW_FRAME (0x400) | RDW_INVALIDATE (0x1) | RDW_UPDATENOW (0x100)
		[void]([WinAPI.GuiWindowChrome]::RedrawWindow($windowHandle, [IntPtr]::Zero, [IntPtr]::Zero, 0x501))
	}
	catch { }

	return $true
}

function Set-GuiWindowChromeTheme
{
	param(
		[Parameter(Mandatory = $true)]
		$Window,

		[bool]$UseDarkMode = $true
	)

	if (-not $Window)
	{
		return $false
	}

	try
	{
		if ((Test-GuiObjectField -Object $Window -FieldName 'GuiWindowChromeUseDarkMode'))
		{
			$Window.GuiWindowChromeUseDarkMode = [bool]$UseDarkMode
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiWindowChromeUseDarkMode' -NotePropertyValue ([bool]$UseDarkMode) -Force
		}
	}
	catch
	{
		$null = $_
	}

	if (Invoke-GuiWindowChromeThemeUpdate -Window $Window -UseDarkMode:$UseDarkMode)
	{
		return $true
	}

	$handlerPropertyName = 'GuiWindowChromeSourceInitializedHandler'
	$existingHandler = $null
	try
	{
		if ($Window.PSObject.Properties[$handlerPropertyName])
		{
			$existingHandler = $Window.$handlerPropertyName
		}
	}
	catch
	{
		$existingHandler = $null
	}

	if (-not $existingHandler)
	{
		# Do NOT use .GetNewClosure() here -- it creates a dynamic module scope
		# that cannot resolve module-private functions like Invoke-GuiWindowChromeThemeUpdate.
		# This handler captures no outer variables, so a bare scriptblock is correct.
		$sourceInitializedHandler = {
			param($sender, $eventArgs)

			$requestedDarkMode = $true
			try
			{
				if ((Test-GuiObjectField -Object $sender -FieldName 'GuiWindowChromeUseDarkMode'))
				{
					$requestedDarkMode = [bool]$sender.GuiWindowChromeUseDarkMode
				}
			}
			catch
			{
				$requestedDarkMode = $true
			}

			[void](Invoke-GuiWindowChromeThemeUpdate -Window $sender -UseDarkMode:$requestedDarkMode)
		}

		$Window.Add_SourceInitialized($sourceInitializedHandler)

		try
		{
			$Window | Add-Member -NotePropertyName $handlerPropertyName -NotePropertyValue $sourceInitializedHandler -Force
		}
		catch
		{
			$null = $_
		}
	}

	return $false
}

function ConvertTo-RoundedWindow
{
	<# .SYNOPSIS Converts a programmatic WPF Window to borderless with rounded corners and a custom title bar. #>
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $true)]
		[hashtable]$Theme
	)

	$bc = $Script:SharedBrushConverter
	$Window.WindowStyle = 'None'
	$Window.AllowsTransparency = $true
	$Window.Background = [System.Windows.Media.Brushes]::Transparent
	if ($Window.ResizeMode -eq 'CanResize') { $Window.ResizeMode = 'CanResizeWithGrip' }

	$roundBorder = New-Object System.Windows.Controls.Border
	$roundBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$roundBorder.Background = $bc.ConvertFromString($Theme.WindowBg)
	$roundBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$roundBorder.BorderThickness = [System.Windows.Thickness]::new(1)

	$dock = New-Object System.Windows.Controls.DockPanel
	$dock.LastChildFill = $true

	$titleBar = New-Object System.Windows.Controls.Border
	$titleBar.Background = $bc.ConvertFromString($(if ($Theme.HeaderBg) { $Theme.HeaderBg } else { $Theme.WindowBg }))
	$titleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
	$titleBar.Padding = [System.Windows.Thickness]::new(12, 8, 8, 8)
	$titleGrid = New-Object System.Windows.Controls.Grid
	$titleBlock = New-Object System.Windows.Controls.TextBlock
	$titleBlock.Text = $Window.Title
	$titleBlock.VerticalAlignment = 'Center'
	$titleBlock.FontSize = 12
	$titleBlock.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	[void]($titleGrid.Children.Add($titleBlock))
	$closeBtn = New-Object System.Windows.Controls.Button
	$closeBtn.Content = [string][char]0xE106
	$closeBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
	$closeBtn.FontSize = 10
	$closeBtn.Width = 32
	$closeBtn.Height = 28
	$closeBtn.Background = [System.Windows.Media.Brushes]::Transparent
	$closeBtn.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$closeBtn.BorderThickness = [System.Windows.Thickness]::new(0)
	$closeBtn.Cursor = [System.Windows.Input.Cursors]::Hand
	$closeBtn.HorizontalAlignment = 'Right'
	$closeBtn.VerticalContentAlignment = 'Center'
	$closeBtn.HorizontalContentAlignment = 'Center'
	$closeBtn.Add_Click({ $Window.Close() }.GetNewClosure())
	[void]($titleGrid.Children.Add($closeBtn))
	$titleBar.Child = $titleGrid
	$titleBar.Add_MouseLeftButtonDown({ $Window.DragMove() }.GetNewClosure())
	[System.Windows.Controls.DockPanel]::SetDock($titleBar, [System.Windows.Controls.Dock]::Top)
	[void]($dock.Children.Add($titleBar))

	return @{ RoundBorder = $roundBorder; DockPanel = $dock }
}

function Complete-RoundedWindow
{
	<# .SYNOPSIS Finishes wrapping a window's content in the rounded border. #>
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $true)]
		[object]$ContentElement,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.Border]$RoundBorder,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.DockPanel]$DockPanel
	)

	[void]($DockPanel.Children.Add($ContentElement))
	$RoundBorder.Child = $DockPanel
	$Window.Content = $RoundBorder
}

function Show-ThemedDialog
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
		[bool]$UseDarkMode = $true,
		[string]$AccentButton = $null,
		[string]$DestructiveButton = $null
	)

	$bc = $Script:SharedBrushConverter

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.MinWidth = $Script:GuiDialogDefaultWidth
	$dlg.MaxWidth = 640
	$dlg.SizeToContent = 'WidthAndHeight'
	$dlg.ResizeMode = 'NoResize'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
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
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$UseDarkMode)

	# Rounded container border
	$dlgRoundedBorder = New-Object System.Windows.Controls.Border
	$dlgRoundedBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$dlgRoundedBorder.Background = $bc.ConvertFromString($Theme.WindowBg)
	$dlgRoundedBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$dlgRoundedBorder.BorderThickness = [System.Windows.Thickness]::new(1)

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
	$dlgCloseBtn.Content = [string][char]0xE106
	$dlgCloseBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
	$dlgCloseBtn.FontSize = 10
	$dlgCloseBtn.Width = 32
	$dlgCloseBtn.Height = 28
	$dlgCloseBtn.Background = [System.Windows.Media.Brushes]::Transparent
	$dlgCloseBtn.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlgCloseBtn.BorderThickness = [System.Windows.Thickness]::new(0)
	$dlgCloseBtn.Cursor = [System.Windows.Input.Cursors]::Hand
	$dlgCloseBtn.HorizontalAlignment = 'Right'
	$dlgCloseBtn.VerticalContentAlignment = 'Center'
	$dlgCloseBtn.HorizontalContentAlignment = 'Center'
	$dlgCloseBtn.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() }.GetNewClosure())
	[void]($dlgTitleBarGrid.Children.Add($dlgCloseBtn))
	$dlgTitleBar.Child = $dlgTitleBarGrid
	$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())

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
	$btnBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	$btnPanel = New-Object System.Windows.Controls.StackPanel
	$btnPanel.Orientation = 'Horizontal'
	$btnPanel.HorizontalAlignment = 'Right'

	$resultRef = @{
		Value = $(if ($Buttons -contains 'Close') { 'Close' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
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
		$label = if ((Test-GuiObjectField -Object $summaryCard -FieldName 'Label')) { [string]$summaryCard.Label } else { '' }
		if ([string]::IsNullOrWhiteSpace($label)) { continue }
		$summaryCardControl = New-DialogSummaryCard `
			-Theme $Theme `
			-Label $label `
			-Value $(if ((Test-GuiObjectField -Object $summaryCard -FieldName 'Value')) { $summaryCard.Value } else { $null }) `
			-Detail $(if ((Test-GuiObjectField -Object $summaryCard -FieldName 'Detail')) { [string]$summaryCard.Detail } else { $null }) `
			-Tone $(if ((Test-GuiObjectField -Object $summaryCard -FieldName 'Tone')) { [string]$summaryCard.Tone } else { 'Primary' })
		if ($summaryCardControl)
		{
			[void]($panel.Children.Add($summaryCardControl))
		}
	}

	return $panel
}

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
			$borderBrush = $(if ($Theme.RiskHighBadge) { $Theme.RiskHighBadge } else { $Theme.CautionBorder })
			$foreground = $(if ($Theme.RiskHighBadge) { $Theme.RiskHighBadge } else { $Theme.CautionText })
		}
		'Caution'
		{
			$background = $(if ($Theme.RiskMediumBadgeBg) { $Theme.RiskMediumBadgeBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.RiskMediumBadge) { $Theme.RiskMediumBadge } else { $Theme.CautionBorder })
			$foreground = $(if ($Theme.RiskMediumBadge) { $Theme.RiskMediumBadge } else { $Theme.CautionText })
		}
		'Success'
		{
			$background = $(if ($Theme.LowRiskBadgeBg) { $Theme.LowRiskBadgeBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.LowRiskBadge) { $Theme.LowRiskBadge } else { $Theme.StatusPillBorder })
			$foreground = $(if ($Theme.LowRiskBadge) { $Theme.LowRiskBadge } else { $Theme.StatusPillText })
		}
		'Primary'
		{
			$background = $(if ($Theme.TabActiveBg) { $Theme.TabActiveBg } else { $Theme.StatusPillBg })
			$borderBrush = $(if ($Theme.AccentBlue) { $Theme.AccentBlue } else { $Theme.StatusPillBorder })
			$foreground = $(if ($Theme.AccentBlue) { $Theme.AccentBlue } else { $Theme.StatusPillText })
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
		$label = if ((Test-GuiObjectField -Object $item -FieldName 'Label')) { [string]$item.Label } else { '' }
		if ([string]::IsNullOrWhiteSpace($label)) { continue }
		$pill = New-DialogMetadataPill `
			-Theme $Theme `
			-Label $label `
			-Tone $(if ((Test-GuiObjectField -Object $item -FieldName 'Tone')) { [string]$item.Tone } else { 'Muted' }) `
			-ToolTip $(if ((Test-GuiObjectField -Object $item -FieldName 'ToolTip')) { [string]$item.ToolTip } else { $null })
		if ($pill)
		{
			[void]($panel.Children.Add($pill))
		}
	}

	return $panel
}

# NOTE: This function is ~700 lines and contains duplicated status-styling logic
# for each outcome state. A future refactor should extract:
#   1. A status-styling lookup table (OutcomeState -> color/icon/label)
#   2. A card/row builder helper to reduce per-status boilerplate
#   3. Filter/grouping logic into a separate function
# The current implementation works correctly; the concern is maintainability.
function Show-ExecutionSummaryDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[object[]]$Results,
		[string]$Title = 'Execution Summary',
		[string]$SummaryText,
		[string]$LogPath,
		[object[]]$SummaryCards = @(),
		[string[]]$Buttons = @('Close'),
		[hashtable]$Strings = @{},
		[bool]$UseDarkMode = $true
	)

	$bc = $Script:SharedBrushConverter
	$results = @($Results)

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = $Script:GuiLayout.DialogLargeWidth
	$dlg.Height = $Script:GuiLayout.DialogLargeHeight
	$dlg.MinWidth = $Script:GuiLayout.DialogLargeMinWidth
	$dlg.MinHeight = $Script:GuiLayout.DialogLargeMinHeight
	$dlg.ResizeMode = 'CanResizeWithGrip'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
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
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$UseDarkMode)

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
	$dlgTBarClose.Content = [string][char]0xE106
	$dlgTBarClose.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
	$dlgTBarClose.FontSize = 10
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
		$logFilePrefix = if ($Strings.ContainsKey('LogFilePrefix')) { [string]$Strings.LogFilePrefix } else { 'Log file' }
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
		$summaryHeader.Text = $(if ($Strings.ContainsKey('ImpactSummary')) { [string]$Strings.ImpactSummary } else { 'Impact summary' })
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

	# ── Status filter bar ──────────────────────────────────────────
	# Clickable status pills that filter the results list below.
	# Only shown for non-preview (post-execution) results.
	$statusFilterActiveRef = @{ Value = $null }  # tracks active filter; $null = show all
	$allResultCards = [System.Collections.Generic.List[object]]::new()  # populated during card build
	$allResultStatusMap = [System.Collections.Generic.List[string]]::new()  # parallel list of status category per card
	$filterBarPanel = $null
	$filterPillButtons = @{}

	$isPreviewModeForFilter = @($Results | Where-Object { @('Already in desired state', 'Will change', 'Requires restart', 'High-risk changes', 'Not fully restorable', 'Preview') -contains [string]$_.Status }).Count -gt 0
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
	# ── End status filter bar ──────────────────────────────────────

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
	$hasPreviewGroups = @($results | Where-Object { (Test-GuiObjectField -Object $_ -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$_.PreviewGroupHeader) }).Count -gt 0
	$displayResults = if ($isPreviewMode)
	{
		if ($hasPreviewGroups)
		{
			@($results | Sort-Object `
				@{ Expression = { if ((Test-GuiObjectField -Object $_ -FieldName 'PreviewGroupSortOrder')) { [int]$_.PreviewGroupSortOrder } else { 99 } } }, `
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
	try { $listStack.BeginInit() } catch { <# non-fatal #> }

	# Limit the initial batch to keep dialog open time fast; remaining
	# results are loaded when the user scrolls or clicks "Show all".
	$initialBatchLimit = 50
	$resultIndex = 0
	$totalResultCount = $displayResults.Count

	foreach ($result in $displayResults)
	{
		if ($isPreviewMode)
		{
			$sectionLabel = if ($hasPreviewGroups -and (Test-GuiObjectField -Object $result -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$result.PreviewGroupHeader)) {
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
				$sectionHeader.Margin = [System.Windows.Thickness]::new(0, $(if ($null -eq $lastPreviewSection) { 0 } else { 8 }), 0, 8)
				[void]($listStack.Children.Add($sectionHeader))
				$lastPreviewSection = $sectionLabel
			}
		}

		# Determine the status category for filtering and left-border color
		$cardStatusCategory = switch ([string]$result.Status)
		{
			'Success'         { 'Success'; break }
			'Skipped'         { 'Skipped'; break }
			'Not applicable'  { 'Skipped'; break }
			'Not Run'         { 'Skipped'; break }
			'Restart pending' { 'Restart pending'; break }
			'Failed'          { 'Failed'; break }
			default           { 'Success' }
		}

		$leftBorderColor = switch ($cardStatusCategory)
		{
			'Success'         { $bc.ConvertFromString($Theme.LowRiskBadge); break }
			'Skipped'         { $bc.ConvertFromString($Theme.BorderColor); break }
			'Failed'          { $bc.ConvertFromString($Theme.RiskHighBadge); break }
			'Restart pending' { $bc.ConvertFromString($Theme.RiskMediumBadge); break }
			default           { $bc.ConvertFromString($Theme.LowRiskBadge) }
		}

		$rowBorder = New-Object System.Windows.Controls.Border
		$rowBorder.Background = $preBrushCardBg
		$rowBorder.BorderBrush = $preBrushCardBorder
		$rowBorder.BorderThickness = [System.Windows.Thickness]::new(3, 1, 1, 1)
		$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$rowBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
		$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
		$rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

		# Color the left border by status category
		$rowBorder.BorderBrush = $leftBorderColor

		$rowStack = New-Object System.Windows.Controls.StackPanel
		$rowStack.Orientation = 'Vertical'

		$headerGrid = New-Object System.Windows.Controls.Grid
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
		$nameBlock = New-Object System.Windows.Controls.TextBlock
		$nameBlock.Text = [string]$result.Name
		$nameBlock.FontSize = 13
		$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
		$nameBlock.TextWrapping = 'Wrap'
		$nameBlock.Foreground = $preBrushTextPrimary
		[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
		[void]($headerGrid.Children.Add($nameBlock))
		$statusBorder = New-Object System.Windows.Controls.Border
		$statusBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
		$statusBorder.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$statusBorder.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
		$statusBorder.BorderThickness = $preThickness1
		$statusText = New-Object System.Windows.Controls.TextBlock
		$statusText.Text = [string]$result.Status
		$statusText.FontSize = $Script:GuiLayout.FontSizeLabel
		$statusText.FontWeight = [System.Windows.FontWeights]::SemiBold

		$statusKey = [string]$result.Status
		$statusBrushSet = if ($preStatusBrushes.ContainsKey($statusKey)) { $preStatusBrushes[$statusKey] } else { $preDefaultStatusBrushes }
		$statusBorder.Background = $statusBrushSet.Bg
		$statusBorder.BorderBrush = $statusBrushSet.Border
		$statusText.Foreground = $statusBrushSet.Fg

		$statusBorder.Child = $statusText
		[System.Windows.Controls.Grid]::SetColumn($statusBorder, 1)
		[void]($headerGrid.Children.Add($statusBorder))
		[void]($rowStack.Children.Add($headerGrid))
		$metaParts = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Category)) { $metaParts += [string]$result.Category }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Selection)) { $metaParts += [string]$result.Selection }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Risk)) { $metaParts += ("{0} Risk" -f [string]$result.Risk) }
		if ($metaParts.Count -gt 0)
		{
			$metaBlock = New-Object System.Windows.Controls.TextBlock
			$metaBlock.Text = ($metaParts -join '  |  ')
			$metaBlock.TextWrapping = 'Wrap'
			$metaBlock.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
			$metaBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$metaBlock.Foreground = $preBrushTextMuted
			[void]($rowStack.Children.Add($metaBlock))
		}

		$chipItems = New-Object System.Collections.Generic.List[object]
		$typeLabel = $null
		$typeTone = 'Muted'
		if ((Test-GuiObjectField -Object $result -FieldName 'TypeBadgeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeBadgeLabel))
		{
			$typeLabel = [string]$result.TypeBadgeLabel
		}
		elseif ((Test-GuiObjectField -Object $result -FieldName 'TypeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeLabel))
		{
			$typeLabel = [string]$result.TypeLabel
		}
		elseif ((Test-GuiObjectField -Object $result -FieldName 'Type') -and -not [string]::IsNullOrWhiteSpace([string]$result.Type))
		{
			$typeLabel = [string]$result.Type
		}
		if ((Test-GuiObjectField -Object $result -FieldName 'TypeTone') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeTone))
		{
			$typeTone = [string]$result.TypeTone
		}
		elseif ($typeLabel -eq 'Uninstall / Remove')
		{
			$typeTone = 'Danger'
		}
		elseif ($typeLabel -eq 'Toggle')
		{
			$typeTone = 'Success'
		}
		elseif ($typeLabel -eq 'Choice')
		{
			$typeTone = 'Primary'
		}
		if (-not [string]::IsNullOrWhiteSpace($typeLabel))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $typeLabel
				Tone = $typeTone
				ToolTip = 'Type of tweak'
			})
		}

		$currentState = $null
		$currentStateTone = 'Muted'
		if ((Test-GuiObjectField -Object $result -FieldName 'CurrentState') -and -not [string]::IsNullOrWhiteSpace([string]$result.CurrentState))
		{
			$currentState = [string]$result.CurrentState
		}
		elseif ((Test-GuiObjectField -Object $result -FieldName 'StateLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.StateLabel))
		{
			$currentState = [string]$result.StateLabel
		}
		if ((Test-GuiObjectField -Object $result -FieldName 'CurrentStateTone') -and -not [string]::IsNullOrWhiteSpace([string]$result.CurrentStateTone))
		{
			$currentStateTone = [string]$result.CurrentStateTone
		}
		elseif ($currentState -eq 'Enabled')
		{
			$currentStateTone = 'Success'
		}
		elseif ($currentState -eq 'Custom')
		{
			$currentStateTone = 'Primary'
		}
		if (-not [string]::IsNullOrWhiteSpace($currentState))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $currentState
				Tone = $currentStateTone
				ToolTip = 'Current state in the GUI'
			})
		}

		$outcomeState = $null
		if ((Test-GuiObjectField -Object $result -FieldName 'OutcomeState') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeState))
		{
			$outcomeState = [string]$result.OutcomeState
		}
		if (-not [string]::IsNullOrWhiteSpace($outcomeState))
		{
			$outcomeTone = switch -Regex ($outcomeState)
			{
				'^(Success|Already in desired state|Already at Windows default|Not applicable|Not applicable on this system)$' { 'Success'; break }
				'^(Restart pending|Failed and recoverable)$' { 'Caution'; break }
				'^(Skipped by preset or selection|Not supported by in-app restore)$' { 'Muted'; break }
				'^(Failed and manual intervention required|Not run)$' { 'Danger'; break }
				default { 'Muted' }
			}
			[void]$chipItems.Add([pscustomobject]@{
				Label = $outcomeState
				Tone = $outcomeTone
				ToolTip = 'Normalized execution outcome'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'FailureCategory') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCategory))
		{
			$failureCategory = [string]$result.FailureCategory
			$failureTone = switch -Regex ($failureCategory)
			{
				'^(Access denied|Reboot required|Missing dependency|Blocked by current system state|Network/download failure|Partial success|Manual intervention required|Unsupported OS/build)$' { 'Caution'; break }
				'^(Unsupported environment|Skipped by preset policy|Not supported by in-app restore)$' { 'Muted'; break }
				'^(Already in desired state|Not applicable|Not run)$' { 'Success'; break }
				default { 'Muted' }
			}
			[void]$chipItems.Add([pscustomobject]@{
				Label = $failureCategory
				Tone = $failureTone
				ToolTip = 'Failure category'
			})
		}

		if ([string]$result.Status -eq 'Failed' -and (Test-GuiObjectField -Object $result -FieldName 'RetryAvailability') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryAvailability))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$result.RetryAvailability
				Tone = $(if ((Test-GuiObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { 'Caution' } else { 'Danger' })
				ToolTip = 'Retry policy for this failure'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'FailureCode') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCode))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$result.FailureCode
				Tone = 'Muted'
				ToolTip = 'Machine-readable failure code'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'RequiresRestart') -and [bool]$result.RequiresRestart)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Restart required'
				Tone = 'Caution'
				ToolTip = 'This change requires a restart to take effect.'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'TroubleshootingOnly') -and [bool]$result.TroubleshootingOnly)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Troubleshooting only'
				Tone = 'Caution'
				ToolTip = 'Use this only when diagnosing game compatibility, overlay, or display issues.'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'Restorable') -and $null -ne $result.Restorable -and -not [bool]$result.Restorable)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Manual recovery'
				Tone = 'Danger'
				ToolTip = 'This change cannot be fully rolled back automatically.'
			})
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryLevel))
		{
			$recoveryLevelLabel = [string]$result.RecoveryLevel
			$recoveryTone = switch ($recoveryLevelLabel)
			{
				'Direct' { 'Success'; break }
				'DefaultsOnly' { 'Primary'; break }
				'RestorePoint' { 'Caution'; break }
				'Manual' { 'Danger'; break }
				default { 'Muted' }
			}
				[void]$chipItems.Add([pscustomobject]@{
					Label = "Recovery: $recoveryLevelLabel"
					Tone = $recoveryTone
					ToolTip = 'Recommended recovery path for this tweak.'
				})
		}

		$scenarioTags = @()
		if ((Test-GuiObjectField -Object $result -FieldName 'ScenarioTags') -and $result.ScenarioTags)
		{
			$scenarioTags = @($result.ScenarioTags)
		}
		elseif ((Test-GuiObjectField -Object $result -FieldName 'Tags') -and $result.Tags)
		{
			$scenarioTags = @($result.Tags)
		}
		if ($scenarioTags.Count -gt 0)
		{
			foreach ($scenarioTag in @($scenarioTags | Select-Object -First 4))
			{
				if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
				[void]$chipItems.Add([pscustomobject]@{
					Label = [string]$scenarioTag
					Tone = 'Muted'
					ToolTip = 'Scenario tag'
				})
			}
			if ($scenarioTags.Count -gt 4)
			{
				[void]$chipItems.Add([pscustomobject]@{
					Label = "+$($scenarioTags.Count - 4) more"
					Tone = 'Muted'
					ToolTip = 'Additional scenario tags are present in the manifest.'
				})
			}
		}

		if ($chipItems.Count -gt 0)
		{
			$chipRow = New-Object System.Windows.Controls.Border
			$chipRow.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$chipRow.Child = (New-DialogMetadataPillPanel -Theme $Theme -Items $chipItems)
			[void]($rowStack.Children.Add($chipRow))
		}

		# ── Expandable detail section (collapsed by default) ──
		$detailStack = New-Object System.Windows.Controls.StackPanel
		$detailStack.Orientation = 'Vertical'
		$detailStack.Visibility = [System.Windows.Visibility]::Collapsed

		# Expand/collapse hint text
		$expandDetailsText = if ($Strings.ContainsKey('ExpandDetails')) { [string]$Strings.ExpandDetails } else { 'Click to expand details' }
		$collapseDetailsText = if ($Strings.ContainsKey('CollapseDetails')) { [string]$Strings.CollapseDetails } else { 'Click to collapse' }
		$expandHint = New-Object System.Windows.Controls.TextBlock
		$expandHint.Text = [char]0x25BC + '  ' + $expandDetailsText
		$expandHint.FontSize = $Script:GuiLayout.FontSizeSmall
		$expandHint.Foreground = $preBrushTextMuted
		$expandHint.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$expandHint.HorizontalAlignment = 'Left'

		# Check if there are any details worth expanding
		$hasExpandableContent = (
			(-not [string]::IsNullOrWhiteSpace([string]$result.ReasonIncluded)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.OutcomeReason) -and (
				[string]$result.Status -in @('Failed', 'Skipped', 'Restart pending', 'Not Run', 'Not applicable') -or
				((Test-GuiObjectField -Object $result -FieldName 'OutcomeState') -and [string]$result.OutcomeState -in @('Already in desired state', 'Already at Windows default', 'Not applicable on this system', 'Skipped by preset or selection', 'Not supported by in-app restore', 'Failed and recoverable', 'Failed and manual intervention required'))
			)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.Detail)) -or
			((Test-GuiObjectField -Object $result -FieldName 'RecoveryHint') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryHint)) -or
			((Test-GuiObjectField -Object $result -FieldName 'RetryReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryReason)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.BlastRadius))
		)

		if ($hasExpandableContent)
		{
			[void]($rowStack.Children.Add($expandHint))

			# Wire click-to-expand on the card border
			$capturedDetailStack = $detailStack
			$capturedExpandHint = $expandHint
			$rowBorder.Add_MouseLeftButtonUp({
				if ($capturedDetailStack.Visibility -eq [System.Windows.Visibility]::Collapsed)
				{
					$capturedDetailStack.Visibility = [System.Windows.Visibility]::Visible
					$capturedExpandHint.Text = [string]([char]0x25B2) + '  ' + $collapseDetailsText
				}
				else
				{
					$capturedDetailStack.Visibility = [System.Windows.Visibility]::Collapsed
					$capturedExpandHint.Text = [string]([char]0x25BC) + '  ' + $expandDetailsText
				}
			}.GetNewClosure())
		}

		# All detail content goes into $detailStack instead of $rowStack
		if (-not [string]::IsNullOrWhiteSpace([string]$result.ReasonIncluded))
		{
			$reasonSeparator = New-Object System.Windows.Controls.Separator
			$reasonSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($reasonSeparator))
			$reasonHeader = New-Object System.Windows.Controls.TextBlock
			$reasonHeader.Text = 'WHY INCLUDED'
			$reasonHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$reasonHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$reasonHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($reasonHeader))
			$reasonBlock = New-Object System.Windows.Controls.TextBlock
			$reasonBlock.Text = [string]$result.ReasonIncluded
			$reasonBlock.TextWrapping = 'Wrap'
			$reasonBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$reasonBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$reasonBlock.Foreground = $preBrushTextSecondary
			[void]($detailStack.Children.Add($reasonBlock))
		}

		$outcomeReasonStatus = if ((Test-GuiObjectField -Object $result -FieldName 'Status')) { [string]$result.Status } else { '' }
		$outcomeReasonState = if ((Test-GuiObjectField -Object $result -FieldName 'OutcomeState')) { [string]$result.OutcomeState } else { '' }
		$showOutcomeReason = (
			$outcomeReasonStatus -in @('Failed', 'Skipped', 'Restart pending', 'Not Run', 'Not applicable') -or
			$outcomeReasonState -in @('Already in desired state', 'Already at Windows default', 'Not applicable on this system', 'Skipped by preset or selection', 'Not supported by in-app restore', 'Failed and recoverable', 'Failed and manual intervention required')
		)

		if ($showOutcomeReason -and (Test-GuiObjectField -Object $result -FieldName 'OutcomeReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeReason))
		{
			$outcomeReasonSeparator = New-Object System.Windows.Controls.Separator
			$outcomeReasonSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($outcomeReasonSeparator))
			$outcomeReasonHeader = New-Object System.Windows.Controls.TextBlock
			$outcomeReasonHeader.Text = 'WHY THIS HAPPENED'
			$outcomeReasonHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$outcomeReasonHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$outcomeReasonHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($outcomeReasonHeader))
			$outcomeReasonBlock = New-Object System.Windows.Controls.TextBlock
			$outcomeReasonBlock.Text = [string]$result.OutcomeReason
			$outcomeReasonBlock.TextWrapping = 'Wrap'
			$outcomeReasonBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$outcomeReasonBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$outcomeReasonBlock.Foreground = $(if ($result.Status -eq 'Failed' -or $result.Status -eq 'Not Run') { $preBrushTextPrimary } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($outcomeReasonBlock))
		}

		if ([string]$result.Status -eq 'Failed' -and (Test-GuiObjectField -Object $result -FieldName 'RetryReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryReason))
		{
			$retrySeparator = New-Object System.Windows.Controls.Separator
			$retrySeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($retrySeparator))
			$retryHeader = New-Object System.Windows.Controls.TextBlock
			$retryHeader.Text = 'RETRY POLICY'
			$retryHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$retryHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$retryHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($retryHeader))
			$retryBlock = New-Object System.Windows.Controls.TextBlock
			$retryBlock.Text = [string]$result.RetryReason
			$retryBlock.TextWrapping = 'Wrap'
			$retryBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$retryBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$retryBlock.Foreground = $(if ((Test-GuiObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($retryBlock))
		}

		if ((Test-GuiObjectField -Object $result -FieldName 'RecoveryHint') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryHint))
		{
			$hintSeparator = New-Object System.Windows.Controls.Separator
			$hintSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($hintSeparator))
			$hintHeader = New-Object System.Windows.Controls.TextBlock
			$hintHeader.Text = 'RECOVERY HINT'
			$hintHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$hintHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$hintHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($hintHeader))
			$hintBlock = New-Object System.Windows.Controls.TextBlock
			$hintBlock.Text = [string]$result.RecoveryHint
			$hintBlock.TextWrapping = 'Wrap'
			$hintBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$hintBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$hintBlock.Foreground = $(if ((Test-GuiObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($hintBlock))
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$result.BlastRadius))
		{
			$blastBlock = New-Object System.Windows.Controls.TextBlock
			$blastBlock.Text = [string]$result.BlastRadius
			$blastBlock.TextWrapping = 'Wrap'
			$blastBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$blastBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$blastBlock.Foreground = $preBrushTextSecondary
			[void]($detailStack.Children.Add($blastBlock))
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$result.Detail))
		{
			$detailBlock = New-Object System.Windows.Controls.TextBlock
			$detailBlock.Text = [string]$result.Detail
			$detailBlock.TextWrapping = 'Wrap'
			$detailBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$detailBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$detailBlock.Foreground = $(if ($result.Status -eq 'Failed' -or $result.Status -eq 'Not Run') { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($detailBlock))
		}

		# Add the collapsible detail panel to the card
		if ($hasExpandableContent)
		{
			[void]($rowStack.Children.Add($detailStack))
		}

		$rowBorder.Child = $rowStack
		[void]($listStack.Children.Add($rowBorder))

		# Track card for status filter bar
		[void]$allResultCards.Add($rowBorder)
		[void]$allResultStatusMap.Add($cardStatusCategory)

		$resultIndex++

		# After the initial batch, stop building cards and insert a
		# "Show all" button so the dialog opens fast for large result sets.
		if ($resultIndex -eq $initialBatchLimit -and $totalResultCount -gt $initialBatchLimit)
		{
			break
		}
	}

	# If we cut the loop short, add a "Show all" button that loads the rest.
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

			try { $capturedListStack.BeginInit() } catch { <# non-fatal #> }
			foreach ($result in $remainingResults)
			{
				if ($isPreviewMode)
				{
					$sectionLabel = if ($hasPreviewGroups -and (Test-GuiObjectField -Object $result -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$result.PreviewGroupHeader)) {
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
			try { $capturedListStack.EndInit() } catch { <# non-fatal #> }
		}.GetNewClosure())

		[void]($listStack.Children.Add($showAllBtn))
	}

	# ── Restart-required informational section ─────────────────────
	$restartPendingItems = @($results | Where-Object {
		[string]$_.Status -eq 'Restart pending' -or
		((Test-GuiObjectField -Object $_ -FieldName 'RequiresRestart') -and [bool]$_.RequiresRestart)
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
		$restartTitle.Text = 'These changes need a restart to take effect:'
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
	# ── End restart-required section ───────────────────────────────

	if ($results.Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = 'No execution results are available for this run.'
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		[void]($listStack.Children.Add($emptyBlock))
	}

	try { $listStack.EndInit() } catch { <# non-fatal #> }
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
		Value = $(if ($Buttons -contains 'Close') { 'Close' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
		$btn.MinWidth = $Script:GuiLayout.ButtonMinWidth
		$btn.Height = $Script:GuiLayout.ButtonHeight
		$btn.Margin = [System.Windows.Thickness]::new(6, 4, 0, 4)
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)

		if ($label -eq 'Exit')
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Danger'
		}
		elseif ($label -eq 'Close')
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Primary'
		}
		else
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Secondary'
		}
		if ($Buttons.Count -eq 1)
		{
			$btn.IsDefault = $true
		}
		if ($label -eq 'Close')
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

function Show-RiskDecisionDialog
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
		[string[]]$Buttons = @('Cancel', 'Continue Anyway'),
		[bool]$UseDarkMode = $true,
		[string]$AccentButton = $null,
		[string]$DestructiveButton = $null
	)

	$bc = $Script:SharedBrushConverter
	$cards = @($SummaryCards)

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = 780
	$dlg.Height = 620
	$dlg.MinWidth = 700
	$dlg.MinHeight = 520
	$dlg.ResizeMode = 'CanResizeWithGrip'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
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
	[void](Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode:$UseDarkMode)

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
	$dlgTBarClose.Content = [string][char]0xE106
	$dlgTBarClose.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
	$dlgTBarClose.FontSize = 10
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
		$cardsHeader.Text = 'Summary'
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

	$resultRef = @{
		Value = $(if ($Buttons -contains 'Cancel') { 'Cancel' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
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

function Get-GuiSettingsProfileDirectory
{
	param (
		[string]$AppName = 'Baseline'
	)

	$baseDir = if ($env:LOCALAPPDATA)
	{
		Join-Path $env:LOCALAPPDATA "$AppName\Profiles"
	}
	else
	{
		Join-Path $env:TEMP "$AppName\Profiles"
	}

	try
	{
		if (-not (Test-Path -LiteralPath $baseDir))
		{
			[void](New-Item -ItemType Directory -Path $baseDir -Force -ErrorAction Stop)
		}
	}
	catch
	{
		$null = $_
	}

	return $baseDir
}

function Get-GuiLastRunFilePath
{
	return (Join-Path (Get-GuiSettingsProfileDirectory) 'Baseline-last-run.json')
}

function Get-GuiSessionStatePath
{
	param (
		[string]$AppName = 'Baseline'
	)

	return (Join-Path (Get-GuiSettingsProfileDirectory -AppName $AppName) "$AppName-last-session.json")
}

function Save-GuiSessionStateDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,

		[string]$AppName = 'Baseline'
	)

	try
	{
		$sessionState = [ordered]@{
			Schema = "$AppName.GuiSession"
			SchemaVersion = 1
			SavedAt = (Get-Date).ToString('o')
			State = $Snapshot
		}
		($sessionState | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath (Get-GuiSessionStatePath -AppName $AppName) -Encoding UTF8 -Force
		LogInfo "Saved GUI session state."
		return $true
	}
	catch
	{
		LogWarning "Failed to save GUI session state: $($_.Exception.Message)"
		return $false
	}
}

function Read-GuiSessionStateDocument
{
	param (
		[string]$AppName = 'Baseline',
		[string]$ExpectedSchema = 'Baseline.GuiSettings'
	)

	$sessionPath = Get-GuiSessionStatePath -AppName $AppName
	if (-not (Test-Path -LiteralPath $sessionPath))
	{
		return $null
	}

	try
	{
		$raw = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 -ErrorAction Stop
		$sessionPayload = $raw | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		LogWarning "Failed to read GUI session state: $($_.Exception.Message)"
		return $null
	}

	$snapshot = if ((Test-GuiObjectField -Object $sessionPayload -FieldName 'State')) { $sessionPayload.State } else { $sessionPayload }
	if (
		-not $snapshot -or
		((Test-GuiObjectField -Object $snapshot -FieldName 'Schema') -and [string]$snapshot.Schema -ne $ExpectedSchema) -or
		-not (Test-GuiObjectField -Object $snapshot -FieldName 'Controls')
	)
	{
		LogWarning 'The saved GUI session state is invalid and was ignored.'
		return $null
	}

	return $snapshot
}

function Show-GuiSettingsSaveDialog
{
	param (
		[string]$AppName = 'Baseline'
	)

	$saveDialog = New-Object Microsoft.Win32.SaveFileDialog
	$saveDialog.Filter = "$AppName Settings (*.json)|*.json|All Files (*.*)|*.*"
	$saveDialog.InitialDirectory = Get-GuiSettingsProfileDirectory -AppName $AppName
	$saveDialog.FileName = "$AppName-settings-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')

	if ($saveDialog.ShowDialog() -eq $true)
	{
		return $saveDialog.FileName
	}

	return $null
}

function Show-GuiSettingsOpenDialog
{
	param (
		[string]$AppName = 'Baseline'
	)

	$openDialog = New-Object Microsoft.Win32.OpenFileDialog
	$openDialog.Filter = "$AppName Settings (*.json)|*.json|All Files (*.*)|*.*"
	$openDialog.InitialDirectory = Get-GuiSettingsProfileDirectory -AppName $AppName
	$openDialog.Multiselect = $false

	if ($openDialog.ShowDialog() -eq $true)
	{
		return $openDialog.FileName
	}

	return $null
}

function Write-GuiSettingsProfileDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,

		[Parameter(Mandatory = $true)]
		[string]$FilePath
	)

	($Snapshot | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $FilePath -Encoding UTF8 -Force
	return $true
}

function Read-GuiSettingsProfileDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[string]$FilePath,

		[string]$ExpectedSchema = 'Baseline.GuiSettings'
	)

	$raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
	$parsedProfile = $raw | ConvertFrom-Json -ErrorAction Stop
	$snapshot = if ((Test-GuiObjectField -Object $parsedProfile -FieldName 'State')) { $parsedProfile.State } else { $parsedProfile }

	if (
		-not $snapshot -or
		((Test-GuiObjectField -Object $snapshot -FieldName 'Schema') -and [string]$snapshot.Schema -ne $ExpectedSchema) -or
		-not (Test-GuiObjectField -Object $snapshot -FieldName 'Controls')
	)
	{
		throw 'The selected file does not contain a valid Baseline settings profile.'
	}

	return $snapshot
}

Export-ModuleMember -Function @(
	'Test-GuiObjectField'
	'Get-GuiObjectField'
	'Get-GuiLayout'
	'Set-GuiWindowChromeTheme'
	'ConvertTo-RoundedWindow'
	'Complete-RoundedWindow'
	'Show-ThemedDialog'
	'Show-ExecutionSummaryDialog'
	'Show-RiskDecisionDialog'
	'New-DialogMetadataPill'
	'New-DialogMetadataPillPanel'
	'New-DialogSummaryCard'
	'New-DialogSummaryCardsPanel'
	'Get-GuiSettingsProfileDirectory'
	'Get-GuiSessionStatePath'
	'Save-GuiSessionStateDocument'
	'Read-GuiSessionStateDocument'
	'Show-GuiSettingsSaveDialog'
	'Show-GuiSettingsOpenDialog'
	'Write-GuiSettingsProfileDocument'
	'Read-GuiSettingsProfileDocument'
	'Get-GuiLastRunFilePath'
	'Initialize-GuiDpiAwareness'
)
