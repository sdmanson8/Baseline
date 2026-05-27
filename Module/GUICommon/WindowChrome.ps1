<#
    .SYNOPSIS
#>
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

		[DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
		private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

		[DllImport("user32.dll", EntryPoint = "GetWindowLong")]
		private static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);

		[DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
		private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

		[DllImport("user32.dll", EntryPoint = "SetWindowLong")]
		private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

		public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex)
		{
			return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex) : GetWindowLong32(hWnd, nIndex);
		}

		public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong)
		{
			return IntPtr.Size == 8 ? SetWindowLongPtr64(hWnd, nIndex, dwNewLong) : SetWindowLong32(hWnd, nIndex, dwNewLong);
		}

		[DllImport("user32.dll")]
		public static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

		public const int GWL_STYLE = -16;
		public const int WS_SYSMENU = 0x00080000;
		public const int WS_MINIMIZEBOX = 0x00020000;
		public const int WS_MAXIMIZEBOX = 0x00010000;
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

<#
    .SYNOPSIS
#>
function Restore-WindowSystemMenu
{
	<# .SYNOPSIS Adds a system-style right-click context menu to a WindowStyle=None WPF window or its title bar element. #>
	param (
		[Parameter(Mandatory = $true)]
		$Window,

		$TitleBarElement = $null
	)

	try
	{
		# Add WS_SYSMENU via Win32 for taskbar right-click support
		Initialize-GuiWindowChromeInterop
		$interopHelper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
		$hwnd = $interopHelper.Handle
		if ($hwnd -ne [IntPtr]::Zero)
		{
			$style = [WinAPI.GuiWindowChrome]::GetWindowLongPtr($hwnd, [WinAPI.GuiWindowChrome]::GWL_STYLE)
			$styleInt = $style.ToInt64()
			$styleInt = $styleInt -bor [WinAPI.GuiWindowChrome]::WS_SYSMENU
			$styleInt = $styleInt -bor [WinAPI.GuiWindowChrome]::WS_MINIMIZEBOX
			$styleInt = $styleInt -bor [WinAPI.GuiWindowChrome]::WS_MAXIMIZEBOX
			[void]([WinAPI.GuiWindowChrome]::SetWindowLongPtr($hwnd, [WinAPI.GuiWindowChrome]::GWL_STYLE, [IntPtr]::new($styleInt)))
			[void]([WinAPI.GuiWindowChrome]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x27))
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Restore-WindowSystemMenu.ApplySystemMenu' }

	# Build a WPF ContextMenu that mimics the standard system menu
	try
	{
		$menu = New-Object System.Windows.Controls.ContextMenu
		$miClose = New-Object System.Windows.Controls.MenuItem
		$miClose.Header = 'Close'
		$miClose.InputGestureText = 'Alt+F4'
		$miClose.FontWeight = [System.Windows.FontWeights]::Bold
		$windowRef = $Window
		$miClose.Add_Click({ $windowRef.Close() }.GetNewClosure())
		[void]$menu.Items.Add($miClose)
		$target = if ($TitleBarElement) { $TitleBarElement } else { $Window }
		$target.ContextMenu = $menu
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Restore-WindowSystemMenu.BuildContextMenu' }
}

<#
    .SYNOPSIS
#>
function Invoke-GuiWindowChromeThemeUpdate
{
	param(
		[Parameter(Mandatory = $true)]
		$Window,

		[object]$UseDarkMode = $true
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Invoke-GuiWindowChromeThemeUpdate'

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

	$osBuild = [Environment]::OSVersion.Version.Build
	$immersiveDarkModeAttributes = [System.Collections.Generic.List[int]]::new()
	if ($osBuild -ge 18362)
	{
		[void]$immersiveDarkModeAttributes.Add(20)
	}
	if ($osBuild -ge 17763)
	{
		[void]$immersiveDarkModeAttributes.Add(19)
	}
	$attributeValue = if ($resolvedUseDarkMode) { 1 } else { 0 }
	if ($immersiveDarkModeAttributes.Count -eq 0)
	{
		return $false
	}

	try
	{
		$chromeThemeApplied = $false
		$result = 0
		foreach ($immersiveDarkModeAttribute in $immersiveDarkModeAttributes)
		{
			$candidateAttributeValue = $attributeValue
			$result = [WinAPI.GuiWindowChrome]::DwmSetWindowAttribute($windowHandle, $immersiveDarkModeAttribute, [ref]$candidateAttributeValue, 4)
			if ($result -eq 0)
			{
				$chromeThemeApplied = $true
				break
			}
		}

		if (-not $chromeThemeApplied)
		{
			Write-GuiCommonWarning ("DwmSetWindowAttribute returned 0x{0:X8} while applying {1} chrome." -f ($result -band 0xFFFFFFFF), $(if ($resolvedUseDarkMode) { 'dark' } else { 'light' }))
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
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Invoke-GuiWindowChromeThemeUpdate.ApplyRoundedCorners' }
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
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Invoke-GuiWindowChromeThemeUpdate.RepaintChrome' }

	return $true
}

<#
    .SYNOPSIS
#>
function Set-GuiWindowChromeTheme
{
	param(
		[Parameter(Mandatory = $true)]
		$Window,

		[object]$UseDarkMode = $true
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Set-GuiWindowChromeTheme'

	if (-not $Window)
	{
		return $false
	}

	try
	{
		$scrollTheme = if ($resolvedUseDarkMode)
		{
			@{
				ScrollBg          = '#151824'
				ScrollThumb       = '#3A4561'
				ScrollThumbHover  = '#4D5875'
				ScrollThumbActive = '#5E6C8E'
			}
		}
		else
		{
			@{
				ScrollBg          = '#F0F1F5'
				ScrollThumb       = '#B4B6C2'
				ScrollThumbHover  = '#8D8FA0'
				ScrollThumbActive = '#6C6E80'
			}
		}
		[void](Add-GuiSharedScrollBarResources -Target $Window -Theme $scrollTheme)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Set-GuiWindowChromeTheme.AddSharedScrollBars'
	}

	try
	{
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiWindowChromeUseDarkMode'))
		{
			$Window.GuiWindowChromeUseDarkMode = $resolvedUseDarkMode
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiWindowChromeUseDarkMode' -NotePropertyValue $resolvedUseDarkMode -Force
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Set-GuiWindowChromeTheme.SetUseDarkModeProperty'
	}

	if (Invoke-GuiWindowChromeThemeUpdate -Window $Window -UseDarkMode:$resolvedUseDarkMode)
	{
		Restore-WindowSystemMenu -Window $Window
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
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Set-GuiWindowChromeTheme:catch303' -Severity Debug }

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
				if ((Test-GuiCommonObjectField -Object $sender -FieldName 'GuiWindowChromeUseDarkMode'))
				{
					$requestedDarkMode = Get-GuiBooleanValue -Value $sender.GuiWindowChromeUseDarkMode -Default $true -Context 'Set-GuiWindowChromeTheme/SourceInitialized'
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Set-GuiWindowChromeTheme:catch324' -Severity Debug }

				$requestedDarkMode = $true
			}

			[void](Invoke-GuiWindowChromeThemeUpdate -Window $sender -UseDarkMode:$requestedDarkMode)
			Restore-WindowSystemMenu -Window $sender
		}

		$Window.Add_SourceInitialized($sourceInitializedHandler)

		try
		{
			$Window | Add-Member -NotePropertyName $handlerPropertyName -NotePropertyValue $sourceInitializedHandler -Force
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'WindowChrome.Set-GuiWindowChromeTheme.SetSourceInitializedHandlerProperty'
		}
	}

	return $false
}

<#
    .SYNOPSIS
#>
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
	$roundBorder.ClipToBounds = $true

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
	$closeBtn.Content = 'x'
	$closeBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Arial')
	$closeBtn.FontSize = 12
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
	# Add system-style context menu to title bar
	$ctxMenu = New-Object System.Windows.Controls.ContextMenu
	$ctxClose = New-Object System.Windows.Controls.MenuItem
	$ctxClose.Header = 'Close'; $ctxClose.InputGestureText = 'Alt+F4'; $ctxClose.FontWeight = [System.Windows.FontWeights]::Bold
	$ctxWindowRef = $Window
	$ctxClose.Add_Click({ $ctxWindowRef.Close() }.GetNewClosure())
	[void]$ctxMenu.Items.Add($ctxClose)
	$titleBar.ContextMenu = $ctxMenu
	[System.Windows.Controls.DockPanel]::SetDock($titleBar, [System.Windows.Controls.Dock]::Top)
	[void]($dock.Children.Add($titleBar))

	return @{ RoundBorder = $roundBorder; DockPanel = $dock }
}

<#
    .SYNOPSIS
#>
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
