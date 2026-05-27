<#
    .SYNOPSIS
#>
function Get-GuiPopupLocalizedString
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Fallback,

		[object[]]$FormatArgs = @()
	)

	if (Test-Path -Path Function:\Get-UxLocalizedString)
	{
		try
		{
			return (Get-UxLocalizedString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs)
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Get-GuiPopupLocalizedString.GetUxLocalizedString'
		}
	}

	if (Test-Path -Path Function:\Get-BaselineLocalizedString)
	{
		try
		{
			return (Get-BaselineLocalizedString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs)
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Get-GuiPopupLocalizedString.GetBaselineLocalizedString'
		}
	}

	$template = $Fallback
	$localizationSource = if ($null -ne $Global:Localization) { $Global:Localization } elseif ($null -ne $Localization) { $Localization } else { $null }
	if ($null -ne $localizationSource)
	{
		$candidate = $null
		if ($localizationSource -is [System.Collections.IDictionary] -and $localizationSource.Contains($Key))
		{
			$candidate = [string]$localizationSource[$Key]
		}
		elseif ($localizationSource.PSObject -and $localizationSource.PSObject.Properties[$Key])
		{
			$candidate = [string]$localizationSource.$Key
		}

		if (-not [string]::IsNullOrWhiteSpace($candidate))
		{
			$template = $candidate
		}
	}

	if ($FormatArgs.Count -gt 0)
	{
		return ($template -f $FormatArgs)
	}

	return $template
}

<#
    .SYNOPSIS
#>
function Add-GuiPopupWindowChrome
{
	<# .SYNOPSIS Adds a shared title bar with minimize and close buttons to a borderless picker window. #>
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.Border]$RootBorder,

		[System.Windows.Controls.Panel]$PanelContainer = $null,

		[string]$Title = $null,

		[hashtable]$Theme = $null,

		[object]$UseDarkMode = $true
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Add-GuiPopupWindowChrome'

	if (-not $Window -or -not $RootBorder)
	{
		return $false
	}

	try
	{
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupChromeApplied') -and [bool]$Window.GuiPopupChromeApplied)
		{
			return $true
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome:catch106' -Severity Debug }

		$null = $_
	}

	$contentElement = $RootBorder.Child
	if (-not $contentElement)
	{
		return $false
	}

	try
	{
		$RootBorder.Child = $null
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome:catch121' -Severity Debug }

		$null = $_
	}

	$bc = $Script:SharedBrushConverter
	$themeRef = if ($Theme) { $Theme } elseif (Test-GuiCommonObjectField -Object $Script:CurrentTheme -FieldName 'WindowBg') { $Script:CurrentTheme } else { @{} }
	[void](Add-GuiSharedScrollBarResources -Target $Window -Theme $themeRef)
	$fallbackWindowBg = if ($resolvedUseDarkMode) { '#1E1E2E' } else { '#F3F5F8' }
	$fallbackHeaderBg = if ($resolvedUseDarkMode) { '#181825' } else { '#F7F8FA' }
	$fallbackBorderColor = if ($resolvedUseDarkMode) { '#333346' } else { '#D8DEE8' }
	$fallbackTextPrimary = if ($resolvedUseDarkMode) { '#CDD6F4' } else { '#111827' }

	$getThemeColor = {
		param(
			[string]$ColorName,
			[string]$DefaultColor
		)

		try
		{
			if ($themeRef -and ($themeRef -is [System.Collections.IDictionary]) -and $themeRef.Contains($ColorName))
			{
				$value = [string]$themeRef[$ColorName]
				if (-not [string]::IsNullOrWhiteSpace($value))
				{
					return $value
				}
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome.ResolveThemeColor' }

		return $DefaultColor
	}.GetNewClosure()

	$windowTitle = if ([string]::IsNullOrWhiteSpace([string]$Title)) { [string]$Window.Title } else { [string]$Title }
	$Window.Title = $windowTitle
	$Window.Background = [System.Windows.Media.Brushes]::Transparent

	$titleBarBackground = & $getThemeColor -ColorName 'HeaderBg' -DefaultColor (& $getThemeColor -ColorName 'WindowBg' -DefaultColor $fallbackHeaderBg)
	$titleBarTextColor = & $getThemeColor -ColorName 'TextPrimary' -DefaultColor $fallbackTextPrimary
	$borderColor = & $getThemeColor -ColorName 'BorderColor' -DefaultColor $fallbackBorderColor
	$closeLabel = Get-GuiPopupLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

	$titleBar = New-Object System.Windows.Controls.Border
	$titleBar.Background = $bc.ConvertFromString($titleBarBackground)
	$titleBar.BorderBrush = $bc.ConvertFromString($borderColor)
	$titleBar.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
	$titleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0)
	$titleBar.Padding = [System.Windows.Thickness]::new(12, 8, 8, 8)
	$titleBar.Cursor = [System.Windows.Input.Cursors]::Arrow
	$titleBar.SnapsToDevicePixels = $true

	$titleGrid = New-Object System.Windows.Controls.Grid
	$titleGrid.SnapsToDevicePixels = $true
	$titleColumn = New-Object System.Windows.Controls.ColumnDefinition
	$titleColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
	$titleColumn.MinWidth = 120
	$buttonsColumn = New-Object System.Windows.Controls.ColumnDefinition
	$buttonsColumn.Width = [System.Windows.GridLength]::Auto
	[void]$titleGrid.ColumnDefinitions.Add($titleColumn)
	[void]$titleGrid.ColumnDefinitions.Add($buttonsColumn)

	$titleBlock = New-Object System.Windows.Controls.TextBlock
	$titleBlock.Text = $windowTitle
	$titleBlock.VerticalAlignment = 'Center'
	$titleBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$titleBlock.FontSize = 12
	$titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
	$titleBlock.Foreground = $bc.ConvertFromString($titleBarTextColor)
	$titleBlock.TextTrimming = 'CharacterEllipsis'
	[System.Windows.Controls.Grid]::SetColumn($titleBlock, 0)
	[void]$titleGrid.Children.Add($titleBlock)

	$buttonStack = New-Object System.Windows.Controls.StackPanel
	$buttonStack.Orientation = 'Horizontal'
	$buttonStack.HorizontalAlignment = 'Right'
	$buttonStack.VerticalAlignment = 'Center'
	[System.Windows.Controls.Grid]::SetColumn($buttonStack, 1)

	$windowRef = $Window
	$minimizeButton = New-Object System.Windows.Controls.Button
	$minimizeButton.Content = [char]0x2212
	$minimizeButton.FontFamily = [System.Windows.Media.FontFamily]::new('Arial')
	$minimizeButton.FontSize = 12
	$minimizeButton.Width = 36
	$minimizeButton.Height = 28
	$minimizeButton.Background = [System.Windows.Media.Brushes]::Transparent
	$minimizeButton.Foreground = $bc.ConvertFromString($titleBarTextColor)
	$minimizeButton.BorderThickness = [System.Windows.Thickness]::new(0)
	$minimizeButton.Cursor = [System.Windows.Input.Cursors]::Hand
	$minimizeButton.HorizontalContentAlignment = 'Center'
	$minimizeButton.VerticalContentAlignment = 'Center'
	$minimizeButton.ToolTip = 'Minimize'
	$minimizeButton.IsEnabled = $true
	$minimizeButton.Opacity = 1.0
	try { Set-GuiPopupCaptionButtonStyle -Button $minimizeButton -Theme $themeRef -UseDarkMode $resolvedUseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome.SetMinimizeButtonStyle' }
	$minimizeButton.Add_Click({ $windowRef.WindowState = [System.Windows.WindowState]::Minimized }.GetNewClosure())

	$closeButton = New-Object System.Windows.Controls.Button
	$closeButton.Content = 'x'
	$closeButton.FontFamily = [System.Windows.Media.FontFamily]::new('Arial')
	$closeButton.FontSize = 12
	$closeButton.Width = 36
	$closeButton.Height = 28
	$closeButton.Background = [System.Windows.Media.Brushes]::Transparent
	$closeButton.Foreground = $bc.ConvertFromString($titleBarTextColor)
	$closeButton.BorderThickness = [System.Windows.Thickness]::new(0)
	$closeButton.Cursor = [System.Windows.Input.Cursors]::Hand
	$closeButton.HorizontalContentAlignment = 'Center'
	$closeButton.VerticalContentAlignment = 'Center'
	$closeButton.ToolTip = $closeLabel
	$closeButton.IsEnabled = $true
	$closeButton.Opacity = 1.0
	try { Set-GuiPopupCaptionButtonStyle -Button $closeButton -Variant 'Close' -Theme $themeRef -UseDarkMode $resolvedUseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome.SetCloseButtonStyle' }
	$closeButton.Add_Click({ $windowRef.Close() }.GetNewClosure())
	$closeButton.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
	$minimizeButton.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)

	[void]$buttonStack.Children.Add($minimizeButton)
	[void]$buttonStack.Children.Add($closeButton)
	[void]$titleGrid.Children.Add($buttonStack)
	$titleBar.Child = $titleGrid
	$testPopupDescendant = ${function:Test-GuiPopupDescendantOfElement}
	$titleBar.Add_MouseLeftButtonDown({
		param($sender, $mouseArgs)

		$originalSource = if ($mouseArgs) { $mouseArgs.OriginalSource } else { $null }
		if (((& $testPopupDescendant -Source $originalSource -Target $windowRef.GuiPopupMinimizeButton)) -or ((& $testPopupDescendant -Source $originalSource -Target $windowRef.GuiPopupCloseButton)))
		{
			return
		}

		$windowRef.DragMove()
	}.GetNewClosure())

	$menu = New-Object System.Windows.Controls.ContextMenu
	$miMinimize = New-Object System.Windows.Controls.MenuItem
	$miMinimize.Header = 'Minimize'
	$miMinimize.Add_Click({ $windowRef.WindowState = [System.Windows.WindowState]::Minimized }.GetNewClosure())
	$miClose = New-Object System.Windows.Controls.MenuItem
	$miClose.Header = $closeLabel
	$miClose.InputGestureText = 'Alt+F4'
	$miClose.FontWeight = [System.Windows.FontWeights]::Bold
	$miClose.Add_Click({ $windowRef.Close() }.GetNewClosure())
	[void]$menu.Items.Add($miMinimize)
	[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
	[void]$menu.Items.Add($miClose)
	$titleBar.ContextMenu = $menu

	$popupDock = New-Object System.Windows.Controls.DockPanel
	$popupDock.LastChildFill = $true
	$popupDock.Background = [System.Windows.Media.Brushes]::Transparent
	[System.Windows.Controls.DockPanel]::SetDock($titleBar, [System.Windows.Controls.Dock]::Top)
	[void]$popupDock.Children.Add($titleBar)

	$progressHost = New-Object System.Windows.Controls.Border
	$progressHost.Margin = [System.Windows.Thickness]::new(12, 6, 12, 0)
	$progressHost.Height = [double]$Script:GuiLayout.PopupProgressBarHeight
	$progressHost.MinWidth = [double]$Script:GuiLayout.PopupProgressBarMinWidth
	$progressHost.CornerRadius = [System.Windows.CornerRadius]::new(2)
	$progressHost.Background = $bc.ConvertFromString($(if ($Theme.CardBorder) { $Theme.CardBorder } else { $borderColor }))
	$progressHost.Visibility = [System.Windows.Visibility]::Collapsed
	$progressHost.SnapsToDevicePixels = $true

	$progressBar = New-Object System.Windows.Controls.ProgressBar
	$progressBar.Minimum = 0
	$progressBar.Maximum = 100
	$progressBar.Value = 0
	$progressBar.IsIndeterminate = $true
	$progressBar.BorderThickness = [System.Windows.Thickness]::new(0)
	$progressBar.Background = $bc.ConvertFromString($(if ($Theme.CardBorder) { $Theme.CardBorder } else { $borderColor }))
	$progressBar.Foreground = $bc.ConvertFromString($(if ($Theme.AccentBlue) { $Theme.AccentBlue } else { $titleBarTextColor }))
	$progressBar.HorizontalAlignment = 'Stretch'
	$progressBar.VerticalAlignment = 'Stretch'
	$progressBar.SnapsToDevicePixels = $true
	$progressHost.Child = $progressBar

	$progressInserted = $false
	if ($contentElement -is [System.Windows.Controls.Grid])
	{
		$contentGrid = [System.Windows.Controls.Grid]$contentElement
		$rowDefinitions = $contentGrid.RowDefinitions
		if ($rowDefinitions -and $rowDefinitions.Count -gt 0)
		{
			$insertRowIndex = [Math]::Max(0, $rowDefinitions.Count - 1)
			$progressRow = New-Object System.Windows.Controls.RowDefinition
			$progressRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
			$rowDefinitions.Insert($insertRowIndex, $progressRow)

			foreach ($child in @($contentGrid.Children))
			{
				$childRow = [System.Windows.Controls.Grid]::GetRow($child)
				if ($childRow -ge $insertRowIndex)
				{
					[System.Windows.Controls.Grid]::SetRow($child, $childRow + 1)
				}
			}

			[System.Windows.Controls.Grid]::SetRow($progressHost, $insertRowIndex)
			[System.Windows.Controls.Grid]::SetColumnSpan($progressHost, [Math]::Max(1, [int]$contentGrid.ColumnDefinitions.Count))
			[void]$contentGrid.Children.Add($progressHost)
			$progressInserted = $true
		}
	}

	if (-not $progressInserted)
	{
		[void]$popupDock.Children.Add($progressHost)
	}

	[void]$popupDock.Children.Add($contentElement)
	$RootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$RootBorder.ClipToBounds = $true
	$RootBorder.Child = $popupDock

	try
	{
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupRootBorder'))
		{
			$Window.GuiPopupRootBorder = $RootBorder
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupRootBorder' -NotePropertyValue $RootBorder -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupContentElement'))
		{
			$Window.GuiPopupContentElement = $contentElement
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupContentElement' -NotePropertyValue $contentElement -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupTitleBar'))
		{
			$Window.GuiPopupTitleBar = $titleBar
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupTitleBar' -NotePropertyValue $titleBar -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupTitleText'))
		{
			$Window.GuiPopupTitleText = $titleBlock
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupTitleText' -NotePropertyValue $titleBlock -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupMinimizeButton'))
		{
			$Window.GuiPopupMinimizeButton = $minimizeButton
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupMinimizeButton' -NotePropertyValue $minimizeButton -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupCloseButton'))
		{
			$Window.GuiPopupCloseButton = $closeButton
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupCloseButton' -NotePropertyValue $closeButton -Force
		}
		if ($PanelContainer)
		{
			if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemePanelContainer'))
			{
				$Window.GuiPopupThemePanelContainer = $PanelContainer
			}
			else
			{
				$Window | Add-Member -NotePropertyName 'GuiPopupThemePanelContainer' -NotePropertyValue $PanelContainer -Force
			}
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressHost'))
		{
			$Window.GuiPopupProgressHost = $progressHost
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupProgressHost' -NotePropertyValue $progressHost -Force
		}
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressBar'))
		{
			$Window.GuiPopupProgressBar = $progressBar
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupProgressBar' -NotePropertyValue $progressBar -Force
		}
		[void](Register-GuiPopupThemeWindow -Window $Window)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome:catch416' -Severity Debug }

		$null = $_
	}

	try
	{
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupChromeApplied'))
		{
			$Window.GuiPopupChromeApplied = $true
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupChromeApplied' -NotePropertyValue $true -Force
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Add-GuiPopupWindowChrome:catch432' -Severity Debug }

		$null = $_
	}

	[void](Set-GuiPopupWindowTheme -Window $Window -Theme $Theme -UseDarkMode:$resolvedUseDarkMode)

	return $true
}

<#
    .SYNOPSIS
#>
function New-GuiPopupInfoIcon
{
	<# .SYNOPSIS Creates the standard per-row information glyph used in popup picker windows. #>
	param(
		[string]$TooltipText,

		[hashtable]$Theme = $null,

		[object]$UseDarkMode = $true,

		[object]$Margin = $null
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'New-GuiPopupInfoIcon'
	$themeRef = if ($Theme) { $Theme } elseif (Test-GuiCommonObjectField -Object $Script:CurrentTheme -FieldName 'AccentBlue') { $Script:CurrentTheme } else { @{} }
	$accentColor = if ($resolvedUseDarkMode) { '#89B4FA' } else { '#2563EB' }

	try
	{
		if ($themeRef -and ($themeRef -is [System.Collections.IDictionary]) -and $themeRef.Contains('AccentBlue'))
		{
			$themeAccent = [string]$themeRef['AccentBlue']
			if (-not [string]::IsNullOrWhiteSpace($themeAccent))
			{
				$accentColor = $themeAccent
			}
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.New-GuiPopupInfoIcon.ResolveThemeColor'
	}

	if ($null -eq $Margin)
	{
		$Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
	}

	$icon = New-Object -TypeName System.Windows.Controls.TextBlock
	$icon.Text = [char]0x24D8
	$icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI Symbol')
	$icon.FontSize = 14
	$icon.FontWeight = [System.Windows.FontWeights]::SemiBold
	$icon.VerticalAlignment = 'Center'
	$icon.Margin = $Margin
	$icon.Cursor = [System.Windows.Input.Cursors]::Arrow
	$icon.ToolTip = if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'More information' } else { $TooltipText }
	[System.Windows.Controls.ToolTipService]::SetPlacement($icon, [System.Windows.Controls.Primitives.PlacementMode]::Right)
	[System.Windows.Controls.ToolTipService]::SetShowDuration($icon, 20000)
	[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($icon, 150)

	try
	{
		$icon.Foreground = $Script:SharedBrushConverter.ConvertFromString($accentColor)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.New-GuiPopupInfoIcon.SetForeground'
		$icon.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
	}

	return $icon
}

<#
    .SYNOPSIS
#>
function Show-GuiActivatedDialog
{
	# Show the dialog through WPF's normal modal path. Do not toggle Topmost or
	# call Activate/Focus from lifecycle events; once the user moves focus to
	# another window, Baseline must not reclaim it.
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window
	)

	return $Window.ShowDialog()
}

<#
    .SYNOPSIS
#>
function Register-GuiPopupThemeWindow
{
	<# .SYNOPSIS Registers an existing popup window for global theme updates and an optional repaint callback. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $false)]
		[scriptblock]$ThemeCallback = $null
	)

	if (-not $Window)
	{
		return $false
	}

	try
	{
		if ($ThemeCallback)
		{
			if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemeCallback'))
			{
				$Window.GuiPopupThemeCallback = $ThemeCallback
			}
			else
			{
				$Window | Add-Member -NotePropertyName 'GuiPopupThemeCallback' -NotePropertyValue $ThemeCallback -Force
			}
		}

		if (-not $Script:GuiPopupThemeWindows.Contains($Window))
		{
			[void]$Script:GuiPopupThemeWindows.Add($Window)
		}

		$registrationAttached = $false
		if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemeRegistrationAttached'))
		{
			$registrationAttached = [bool]$Window.GuiPopupThemeRegistrationAttached
		}

		if (-not $registrationAttached)
		{
			$Window.Add_Closed({
				param($sender, $eventArgs)
				try
				{
					if ($Script:GuiPopupThemeWindows)
					{
						[void]$Script:GuiPopupThemeWindows.Remove($sender)
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Register-GuiPopupThemeWindow:catch582' -Severity Debug }

					$null = $_
				}
			}.GetNewClosure())

			if ((Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemeRegistrationAttached'))
			{
				$Window.GuiPopupThemeRegistrationAttached = $true
			}
			else
			{
				$Window | Add-Member -NotePropertyName 'GuiPopupThemeRegistrationAttached' -NotePropertyValue $true -Force
			}
		}
	}
	catch
	{
		Write-GuiCommonWarning ("Failed to register popup window for theme updates: {0}" -f $_.Exception.Message)
		return $false
	}

	return $true
}

<#
    .SYNOPSIS
#>
function Set-GuiPopupWindowProgress
{
	<# .SYNOPSIS Shows or hides the shared miniature progress strip on a popup window. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $false)]
		[bool]$Visible = $true,

		[Parameter(Mandatory = $false)]
		[switch]$Indeterminate,

		[Parameter(Mandatory = $false)]
		[int]$Completed = 0,

		[Parameter(Mandatory = $false)]
		[int]$Total = 0
	)

	if (-not $Window)
	{
		return $false
	}

	$progressHost = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressHost'
	$progressBar = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressBar'
	if (-not $progressHost -or -not $progressBar)
	{
		return $false
	}

	try
	{
		if ($Visible)
		{
			$progressHost.Visibility = [System.Windows.Visibility]::Visible
			if ($Indeterminate -or $Total -le 0)
			{
				$progressBar.IsIndeterminate = $true
				$progressBar.Maximum = 1
				$progressBar.Value = 0
			}
			else
			{
				$safeTotal = [Math]::Max(1, $Total)
				$safeCompleted = [Math]::Min([Math]::Max(0, $Completed), $safeTotal)
				$progressBar.IsIndeterminate = $false
				$progressBar.Maximum = $safeTotal
				$progressBar.Value = $safeCompleted
			}
		}
		else
		{
			$progressHost.Visibility = [System.Windows.Visibility]::Collapsed
			$progressBar.IsIndeterminate = $false
			$progressBar.Maximum = 1
			$progressBar.Value = 0
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowProgress:catch671' -Severity Debug }

		$null = $_
	}

	return $true
}

<#
    .SYNOPSIS
#>
function Set-GuiPopupWindowTheme
{
	<# .SYNOPSIS Applies the shared popup chrome surface colors to an open popup window. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,

		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Set-GuiPopupWindowTheme'

	if (-not $Window)
	{
		return $false
	}

	$bc = $Script:SharedBrushConverter
	$themeRef = if ($Theme) { $Theme } elseif (Test-GuiCommonObjectField -Object $Script:CurrentTheme -FieldName 'WindowBg') { $Script:CurrentTheme } else { @{} }
	$fallbackWindowBg = if ($resolvedUseDarkMode) { '#1E1E2E' } else { '#F3F5F8' }
	$fallbackHeaderBg = if ($resolvedUseDarkMode) { '#181825' } else { '#F7F8FA' }
	$fallbackBorderColor = if ($resolvedUseDarkMode) { '#333346' } else { '#D8DEE8' }
	$fallbackTextPrimary = if ($resolvedUseDarkMode) { '#CDD6F4' } else { '#111827' }
	$fallbackAccentBlue = if ($resolvedUseDarkMode) { '#89B4FA' } else { '#2563EB' }

	$getThemeColor = {
		param(
			[string]$ColorName,
			[string]$DefaultColor
		)

		try
		{
			if ($themeRef -and ($themeRef -is [System.Collections.IDictionary]) -and $themeRef.Contains($ColorName))
			{
				$value = [string]$themeRef[$ColorName]
				if (-not [string]::IsNullOrWhiteSpace($value))
				{
					return $value
				}
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.ResolveThemeColor' }

		return $DefaultColor
	}.GetNewClosure()

	$windowBg = & $getThemeColor -ColorName 'WindowBg' -DefaultColor $fallbackWindowBg
	$panelBg = & $getThemeColor -ColorName 'PanelBg' -DefaultColor $windowBg
	$titleBarBackground = & $getThemeColor -ColorName 'HeaderBg' -DefaultColor (& $getThemeColor -ColorName 'WindowBg' -DefaultColor $fallbackHeaderBg)
	$titleBarTextColor = & $getThemeColor -ColorName 'TextPrimary' -DefaultColor $fallbackTextPrimary
	$borderColor = & $getThemeColor -ColorName 'BorderColor' -DefaultColor $fallbackBorderColor
	$accentBlue = & $getThemeColor -ColorName 'AccentBlue' -DefaultColor $fallbackAccentBlue

	try { $Window.Background = [System.Windows.Media.Brushes]::Transparent } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetWindowBackground' }
	try { $Window.Foreground = $bc.ConvertFromString($titleBarTextColor) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetWindowForeground' }

	$rootBorder = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupRootBorder'
	if ($rootBorder)
	{
		try { $rootBorder.Background = $bc.ConvertFromString($windowBg) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetRootBorderBackground' }
		try { $rootBorder.BorderBrush = $bc.ConvertFromString($borderColor) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetRootBorderBorderBrush' }
		try { $rootBorder.BorderThickness = [System.Windows.Thickness]::new(1) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetRootBorderThickness' }
		try { $rootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetRootBorderCornerRadius' }
		try { $rootBorder.ClipToBounds = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetRootBorderClipToBounds' }
	}

	$titleBar = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupTitleBar'
	if ($titleBar)
	{
		try { $titleBar.Background = $bc.ConvertFromString($titleBarBackground) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetTitleBarBackground' }
		try { $titleBar.BorderBrush = $bc.ConvertFromString($borderColor) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetTitleBarBorderBrush' }
		try { $titleBar.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetTitleBarBorderThickness' }
	}

	$titleText = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupTitleText'
	if ($titleText)
	{
		try { $titleText.Foreground = $bc.ConvertFromString($titleBarTextColor) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetTitleTextForeground' }
	}

	$panelContainer = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemePanelContainer'
	if ($panelContainer)
	{
		try { $panelContainer.Background = $bc.ConvertFromString($panelBg) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetPanelContainerBackground' }
	}

	$progressHost = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressHost'
	if ($progressHost)
	{
		try { $progressHost.Background = $bc.ConvertFromString($borderColor) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetProgressHostBackground' }
	}

	$progressBar = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupProgressBar'
	if ($progressBar)
	{
		try
		{
			$progressBar.Background = $bc.ConvertFromString($borderColor)
			$progressBar.Foreground = $bc.ConvertFromString($accentBlue)
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetProgressBarBrushes' }
	}

	$minimizeButton = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupMinimizeButton'
	if ($minimizeButton)
	{
		try
		{
			$minimizeButton.IsEnabled = $true
			$minimizeButton.Foreground = $bc.ConvertFromString($titleBarTextColor)
			$minimizeButton.Background = [System.Windows.Media.Brushes]::Transparent
			$minimizeButton.Opacity = 1.0
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetPopupMinimizeButtonFallbackBrushes' }
		try { Set-GuiPopupCaptionButtonStyle -Button $minimizeButton -Theme $themeRef -UseDarkMode $resolvedUseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetPopupMinimizeButtonStyle' }
	}

	$closeButton = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupCloseButton'
	if ($closeButton)
	{
		try
		{
			$closeButton.IsEnabled = $true
			$closeButton.Foreground = $bc.ConvertFromString($titleBarTextColor)
			$closeButton.Background = [System.Windows.Media.Brushes]::Transparent
			$closeButton.Opacity = 1.0
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetPopupCloseButtonFallbackBrushes' }
		try { Set-GuiPopupCaptionButtonStyle -Button $closeButton -Variant 'Close' -Theme $themeRef -UseDarkMode $resolvedUseDarkMode } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.SetPopupCloseButtonStyle' }
	}

	try
	{
		if (Test-Path -Path Function:\Set-GuiWindowChromeTheme)
		{
			[void](Set-GuiWindowChromeTheme -Window $Window -UseDarkMode:$resolvedUseDarkMode)
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Set-GuiPopupWindowTheme.ApplyChrome' }

	$themeCallback = Get-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupThemeCallback'
	if ($themeCallback -is [scriptblock])
	{
		try
		{
			& $themeCallback -Window $Window -Theme $themeRef -UseDarkMode $resolvedUseDarkMode
		}
		catch
		{
			Write-GuiCommonWarning ("Failed to run popup theme callback for window '{0}': {1}" -f [string]$Window.Title, $_.Exception.Message)
		}
	}

	return $true
}

<#
    .SYNOPSIS
#>
function Update-GuiPopupWindowThemes
{
	<# .SYNOPSIS Repaints all registered popup windows for the current theme. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,

		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Update-GuiPopupWindowThemes'

	if (-not $Script:GuiPopupThemeWindows -or $Script:GuiPopupThemeWindows.Count -eq 0)
	{
		return 0
	}

	$updatedCount = 0
	foreach ($window in @($Script:GuiPopupThemeWindows))
	{
		if (-not $window)
		{
			continue
		}

		try
		{
			if (-not [bool]$window.IsLoaded -and -not [bool]$window.IsVisible)
			{
				[void]$Script:GuiPopupThemeWindows.Remove($window)
				continue
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Update-GuiPopupWindowThemes:catch882' -Severity Debug }

			# If a window has already torn down, prune it from the registry.
			[void]$Script:GuiPopupThemeWindows.Remove($window)
			continue
		}

			try
			{
				if (Set-GuiPopupWindowTheme -Window $window -Theme $Theme -UseDarkMode:$resolvedUseDarkMode)
				{
					$updatedCount++
				}
		}
		catch
		{
			Write-GuiCommonWarning ("Failed to update popup theme for an open window: {0}" -f $_.Exception.Message)
		}
	}

	return $updatedCount
}

<#
    .SYNOPSIS
#>
function Start-GuiPopupCommandAsync
{
	<# .SYNOPSIS Runs a popup action on a background STA runspace while the popup shows its miniature progress strip. #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Window]$Window,

		[Parameter(Mandatory = $true)]
		[string]$ModulePath,

		[Parameter(Mandatory = $true)]
		[string]$CommandName,

		[Parameter(Mandatory = $false)]
		[hashtable]$CommandParameters = @{},

		[Parameter(Mandatory = $false)]
		[string[]]$AdditionalModulePaths = @()
	)

	if (-not $Window -or [string]::IsNullOrWhiteSpace($ModulePath) -or [string]::IsNullOrWhiteSpace($CommandName))
	{
		return $false
	}

	try
	{
		if (Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupOperationError')
		{
			$Window.GuiPopupOperationError = $null
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupOperationError' -NotePropertyValue $null -Force
		}

		if (Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupOperationResult')
		{
			$Window.GuiPopupOperationResult = $null
		}
		else
		{
			$Window | Add-Member -NotePropertyName 'GuiPopupOperationResult' -NotePropertyValue $null -Force
		}

		Set-GuiPopupWindowProgress -Window $Window -Visible $true -Indeterminate | Out-Null
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync.InitializeOperationState' }

	$syncHash = [hashtable]::Synchronized(@{
		Done = $false
		Error = $null
		Result = $null
	})

	$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
	$runspace.ApartmentState = 'STA'
	$runspace.ThreadOptions = 'ReuseThread'
	$runspace.Open()
	$ps = [System.Management.Automation.PowerShell]::Create()
	$ps.Runspace = $runspace

	$operation = {
		param(
			[string]$PopupModulePath,
			[string]$PopupCommandName,
			[hashtable]$PopupCommandParameters,
			[string[]]$PopupAdditionalModulePaths,
			[hashtable]$Sync
		)

		try
		{
			foreach ($path in @($PopupAdditionalModulePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
			{
		Import-Module -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -Name $path -ErrorAction Stop | Out-Null
			}

	Import-Module -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -Name $PopupModulePath -ErrorAction Stop | Out-Null
			$Sync.Result = & $PopupCommandName @PopupCommandParameters
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync:catch990' -Severity Debug }

			$Sync.Error = $_
		}
		finally
		{
			$Sync.Done = $true
		}
	}.GetNewClosure()

	$null = $ps.AddScript($operation).
		AddArgument($ModulePath).
		AddArgument($CommandName).
		AddArgument($CommandParameters).
		AddArgument(@($AdditionalModulePaths)).
		AddArgument($syncHash)

	$asyncResult = $ps.BeginInvoke()
	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(50)
	$timer.Add_Tick({
		if (-not $asyncResult.IsCompleted)
		{
			return
		}

		$timer.Stop()

		try { $ps.EndInvoke($asyncResult) | Out-Null } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync:catch1018' -Severity Debug }
		 if (-not $syncHash.Error) { $syncHash.Error = $_ } }
		try { $ps.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync.DisposePowerShell' }
		try { $runspace.Close(); $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync.DisposeRunspace' }

		try
		{
			if ($syncHash.Error)
			{
				if (Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupOperationError')
				{
					$Window.GuiPopupOperationError = $syncHash.Error
				}
				else
				{
					$Window | Add-Member -NotePropertyName 'GuiPopupOperationError' -NotePropertyValue $syncHash.Error -Force
				}
			}
			else
			{
				if (Test-GuiCommonObjectField -Object $Window -FieldName 'GuiPopupOperationResult')
				{
					$Window.GuiPopupOperationResult = $syncHash.Result
				}
				else
				{
					$Window | Add-Member -NotePropertyName 'GuiPopupOperationResult' -NotePropertyValue $syncHash.Result -Force
				}
			}

			Set-GuiPopupWindowProgress -Window $Window -Visible $false | Out-Null
			$Window.Close()
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Start-GuiPopupCommandAsync.CompleteOperationState' }
	}.GetNewClosure())
	$timer.Start()

	return $true
}
<#
    .SYNOPSIS
#>
function Get-GuiPopupThemeColor
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,
		[Parameter(Mandatory = $true)]
		[string]$ColorName,
		[Parameter(Mandatory = $true)]
		[string]$DefaultColor,
		[string]$ErrorSource = 'PopupWindows.Get-GuiPopupThemeColor'
	)

	try
	{
		if ($Theme -and ($Theme -is [System.Collections.IDictionary]) -and $Theme.Contains($ColorName))
		{
			$value = [string]$Theme[$ColorName]
			if (-not [string]::IsNullOrWhiteSpace($value))
			{
				return $value
			}
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source $ErrorSource
	}

	return $DefaultColor
}

<#
    .SYNOPSIS
#>
function Set-GuiPopupActionButtonStyle
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[CmdletBinding()]
	param(
		[System.Windows.Controls.Button]$Button,
		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,
		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	if (-not $Button)
	{
		return
	}

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Set-GuiPopupActionButtonStyle'
	$themeRef = if ($Theme) { $Theme } elseif (Test-GuiCommonObjectField -Object $Script:CurrentTheme -FieldName 'WindowBg') { $Script:CurrentTheme } else { @{} }
	$bc = $Script:SharedBrushConverter

	$normalBg = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonBg' -DefaultColor $(if ($resolvedUseDarkMode) { '#262D40' } else { '#FFFFFF' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolveNormalBackground'
	$hoverBg = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'TabHoverBg' -DefaultColor $(if ($resolvedUseDarkMode) { '#2E3650' } else { '#E3E9F3' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolveHoverBackground'
	$pressBg = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonPressBg' -DefaultColor $(if ($resolvedUseDarkMode) { '#202638' } else { '#D7DFEC' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolvePressBackground'
	$normalBorder = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonBorder' -DefaultColor $(if ($resolvedUseDarkMode) { '#39435C' } else { '#C9D4E3' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolveBorder'
	$foreground = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonFg' -DefaultColor $(if ($resolvedUseDarkMode) { '#F4F7FF' } else { '#263248' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolveForeground'
	$focusBorder = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'FocusRing' -DefaultColor $(if ($resolvedUseDarkMode) { '#9ACAFF' } else { '#3B82F6' }) -ErrorSource 'PopupWindows.Set-GuiPopupActionButtonStyle.ResolveFocusBorder'

	$normalBgBrush = $bc.ConvertFromString($normalBg)
	$hoverBgBrush = $bc.ConvertFromString($hoverBg)
	$pressBgBrush = $bc.ConvertFromString($pressBg)
	$normalBorderBrush = $bc.ConvertFromString($normalBorder)
	$focusBorderBrush = $bc.ConvertFromString($focusBorder)
	$foregroundBrush = $bc.ConvertFromString($foreground)
	$paddingValue = if ($Button.Padding -and ($Button.Padding.Left -ne 0 -or $Button.Padding.Top -ne 0 -or $Button.Padding.Right -ne 0 -or $Button.Padding.Bottom -ne 0))
	{
		$Button.Padding
	}
	else
	{
		[System.Windows.Thickness]::new(12, 6, 12, 6)
	}

	$Button.Foreground = $foregroundBrush
	$Button.Background = $normalBgBrush
	$Button.BorderBrush = $normalBorderBrush
	$Button.BorderThickness = [System.Windows.Thickness]::new(1)
	$Button.FocusVisualStyle = $null
	$Button.Cursor = [System.Windows.Input.Cursors]::Hand
	$Button.Template = $null

	$template = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
	$border = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$border.Name = 'PopupActionBd'
	$border.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
	$border.SetValue([System.Windows.Controls.Border]::PaddingProperty, $paddingValue)
	$border.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $normalBgBrush)
	$border.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $normalBorderBrush)
	$border.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
	$presenter = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::ContentSourceProperty, 'Content')
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
	$border.AppendChild($presenter)
	$template.VisualTree = $border

	$hoverTrigger = New-Object System.Windows.Trigger
	$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
	$hoverTrigger.Value = $true
	[void]$hoverTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $hoverBgBrush, 'PopupActionBd')))
	[void]$hoverTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $normalBorderBrush, 'PopupActionBd')))
	[void]$template.Triggers.Add($hoverTrigger)

	$focusTrigger = New-Object System.Windows.Trigger
	$focusTrigger.Property = [System.Windows.UIElement]::IsKeyboardFocusedProperty
	$focusTrigger.Value = $true
	[void]$focusTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $focusBorderBrush, 'PopupActionBd')))
	[void]$focusTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(2), 'PopupActionBd')))
	[void]$template.Triggers.Add($focusTrigger)

	$pressTrigger = New-Object System.Windows.Trigger
	$pressTrigger.Property = [System.Windows.Controls.Primitives.ButtonBase]::IsPressedProperty
	$pressTrigger.Value = $true
	[void]$pressTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $pressBgBrush, 'PopupActionBd')))
	[void]$template.Triggers.Add($pressTrigger)

	$disabledTrigger = New-Object System.Windows.Trigger
	$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
	$disabledTrigger.Value = $false
	[void]$disabledTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::OpacityProperty, 0.55, 'PopupActionBd')))
	[void]$template.Triggers.Add($disabledTrigger)

	$Button.Template = $template
}

<#
    .SYNOPSIS
#>
function Set-GuiPopupCaptionButtonStyle
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[CmdletBinding()]
	param(
		[System.Windows.Controls.Button]$Button,
		[ValidateSet('Standard', 'Close')]
		[string]$Variant = 'Standard',
		[Parameter(Mandatory = $false)]
		[hashtable]$Theme = $null,
		[Parameter(Mandatory = $false)]
		[object]$UseDarkMode = $true
	)

	if (-not $Button)
	{
		return
	}

	$resolvedUseDarkMode = Get-GuiBooleanValue -Value $UseDarkMode -Default $true -Context 'Set-GuiPopupCaptionButtonStyle'
	$themeRef = if ($Theme) { $Theme } elseif (Test-GuiCommonObjectField -Object $Script:CurrentTheme -FieldName 'WindowBg') { $Script:CurrentTheme } else { @{} }
	$bc = $Script:SharedBrushConverter

	$foreground = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'TextPrimary' -DefaultColor $(if ($resolvedUseDarkMode) { '#F4F7FF' } else { '#111827' }) -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolveForeground'
	$hoverBg = if ($Variant -eq 'Close')
	{
		Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'DestructiveHover' -DefaultColor '#A6294E' -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolveCloseHoverBackground'
	}
	else
	{
		Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonHoverBg' -DefaultColor $(if ($resolvedUseDarkMode) { '#343C55' } else { '#E8EDF5' }) -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolveHoverBackground'
	}
	$pressBg = if ($Variant -eq 'Close')
	{
		Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'DestructiveBg' -DefaultColor '#C0325A' -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolveClosePressBackground'
	}
	else
	{
		Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'SecondaryButtonPressBg' -DefaultColor $(if ($resolvedUseDarkMode) { '#202638' } else { '#DCE4F0' }) -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolvePressBackground'
	}
	$hoverForeground = if ($Variant -eq 'Close') { '#FFFFFF' } else { $foreground }
	$focusBorder = Get-GuiPopupThemeColor -Theme $themeRef -ColorName 'FocusRing' -DefaultColor $(if ($resolvedUseDarkMode) { '#9ACAFF' } else { '#3B82F6' }) -ErrorSource 'PopupWindows.Set-GuiPopupCaptionButtonStyle.ResolveFocusBorder'

	$foregroundBrush = $bc.ConvertFromString($foreground)
	$hoverForegroundBrush = $bc.ConvertFromString($hoverForeground)
	$hoverBgBrush = $bc.ConvertFromString($hoverBg)
	$pressBgBrush = $bc.ConvertFromString($pressBg)
	$focusBorderBrush = $bc.ConvertFromString($focusBorder)

	$Button.Foreground = $foregroundBrush
	$Button.Background = [System.Windows.Media.Brushes]::Transparent
	$Button.BorderBrush = [System.Windows.Media.Brushes]::Transparent
	$Button.BorderThickness = [System.Windows.Thickness]::new(0)
	$Button.FocusVisualStyle = $null
	$Button.Cursor = [System.Windows.Input.Cursors]::Hand
	$Button.Padding = [System.Windows.Thickness]::new(0)
	$Button.Template = $null

	$template = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
	$border = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$border.Name = 'PopupCaptionBd'
	$border.SetValue([System.Windows.Controls.Border]::BackgroundProperty, [System.Windows.Media.Brushes]::Transparent)
	$border.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, [System.Windows.Media.Brushes]::Transparent)
	$border.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(0))
	$border.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
	$border.SetValue([System.Windows.Controls.Border]::SnapsToDevicePixelsProperty, $true)
	$presenter = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::ContentSourceProperty, 'Content')
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$presenter.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
	$border.AppendChild($presenter)
	$template.VisualTree = $border

	$hoverTrigger = New-Object System.Windows.Trigger
	$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
	$hoverTrigger.Value = $true
	[void]$hoverTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $hoverBgBrush, 'PopupCaptionBd')))
	[void]$hoverTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $hoverForegroundBrush)))
	[void]$template.Triggers.Add($hoverTrigger)

	$focusTrigger = New-Object System.Windows.Trigger
	$focusTrigger.Property = [System.Windows.UIElement]::IsKeyboardFocusedProperty
	$focusTrigger.Value = $true
	[void]$focusTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderBrushProperty, $focusBorderBrush, 'PopupCaptionBd')))
	[void]$focusTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1), 'PopupCaptionBd')))
	[void]$template.Triggers.Add($focusTrigger)

	$pressTrigger = New-Object System.Windows.Trigger
	$pressTrigger.Property = [System.Windows.Controls.Primitives.ButtonBase]::IsPressedProperty
	$pressTrigger.Value = $true
	[void]$pressTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::BackgroundProperty, $pressBgBrush, 'PopupCaptionBd')))
	[void]$pressTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Control]::ForegroundProperty, $hoverForegroundBrush)))
	[void]$template.Triggers.Add($pressTrigger)

	$disabledTrigger = New-Object System.Windows.Trigger
	$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
	$disabledTrigger.Value = $false
	[void]$disabledTrigger.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.Border]::OpacityProperty, 0.45, 'PopupCaptionBd')))
	[void]$template.Triggers.Add($disabledTrigger)

	$Button.Template = $template
}

<#
    .SYNOPSIS
#>
function Test-GuiPopupDescendantOfElement
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[object]$Source,
		[Parameter(Mandatory = $false)]
		[object]$Target
	)

	if (-not $Source -or -not $Target)
	{
		return $false
	}

	$current = $Source
	while ($current)
	{
		if ($current -eq $Target)
		{
			return $true
		}

		try
		{
			if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D])
			{
				$current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
				continue
			}

			if ($current -is [System.Windows.FrameworkContentElement])
			{
				$current = $current.Parent
				continue
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'PopupWindows.Test-GuiPopupDescendantOfElement.GetParent'
		}

		$current = $null
	}

	return $false
}
