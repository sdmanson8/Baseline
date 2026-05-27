	if (-not [System.Windows.Application]::Current)
	{
		$Script:GuiApplication = [System.Windows.Application]::new()
	}
	$Script:InitialResolvedThemeName = 'Light'
	try
	{
		$startupThemeName = Get-BaselineStartupThemeName
		if ($startupThemeName -in @('Light', 'Dark')) { $Script:InitialResolvedThemeName = [string]$startupThemeName }
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ResolveInitialTheme'
	}
	[void](Set-GuiThemeResources -Target ([System.Windows.Application]::Current) -ThemeName $Script:InitialResolvedThemeName)

	$loadedForm = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XAML))

	if (-not ($loadedForm -is [System.Windows.Window]))
	{
		throw "XAML root did not load as System.Windows.Window. Actual type: $($loadedForm.GetType().FullName)"
	}

	[System.Windows.Window]$Form = $loadedForm
	$Script:MainForm = $Form
	[void](Set-GuiThemeResources -Target $Form -ThemeName $Script:InitialResolvedThemeName)
	$Script:MainWindowWorkAreaMaximized = $false
	$Script:MainWindowPendingWorkAreaMaximize = $false
	$Script:MainWindowApplyingWorkAreaMaximize = $false
	$Script:MainWindowRestoreBounds = $null
	$Script:MainWindowDefaultRestoreBounds = $null

	function New-GuiMainWindowBoundsSnapshot
	{
		param(
			[double]$Left,
			[double]$Top,
			[double]$Width,
			[double]$Height
		)

		if ([double]::IsNaN($Left) -or [double]::IsNaN($Top) -or [double]::IsNaN($Width) -or [double]::IsNaN($Height)) { return $null }
		if ($Width -le 0 -or $Height -le 0) { return $null }

		return [pscustomobject]@{
			Left   = $Left
			Top    = $Top
			Width  = $Width
			Height = $Height
		}
	}

	function Convert-GuiWindowRectToBoundsSnapshot
	{
		param(
			[System.Windows.Rect]$Rect
		)

		if ([System.Windows.Rect]::Empty.Equals($Rect)) { return $null }
		return New-GuiMainWindowBoundsSnapshot -Left ([double]$Rect.Left) -Top ([double]$Rect.Top) -Width ([double]$Rect.Width) -Height ([double]$Rect.Height)
	}

	function Get-GuiMainWindowBoundsSnapshot
	{
		param(
			[System.Windows.Window]$Window
		)

		if (-not $Window) { return $null }

		$width = [double]$Window.Width
		$height = [double]$Window.Height
		if ([double]::IsNaN($width) -or $width -le 0) { $width = [double]$Window.ActualWidth }
		if ([double]::IsNaN($height) -or $height -le 0) { $height = [double]$Window.ActualHeight }

		return New-GuiMainWindowBoundsSnapshot -Left ([double]$Window.Left) -Top ([double]$Window.Top) -Width $width -Height $height
	}

	function Test-GuiMainWindowBoundsSnapshot
	{
		param(
			[object]$Bounds
		)

		if (-not $Bounds) { return $false }
		return ($null -ne $Bounds.Left -and $null -ne $Bounds.Top -and $null -ne $Bounds.Width -and $null -ne $Bounds.Height -and [double]$Bounds.Width -gt 0 -and [double]$Bounds.Height -gt 0)
	}

	function Convert-GuiDeviceRectToDipBounds
	{
		param(
			[System.Windows.Window]$Window,
			[object]$Rect
		)

		$left = [double]$Rect.Left
		$top = [double]$Rect.Top
		$right = [double]$Rect.Right
		$bottom = [double]$Rect.Bottom
		$source = [System.Windows.PresentationSource]::FromVisual($Window)
		if ($source -and $source.CompositionTarget)
		{
			$transform = $source.CompositionTarget.TransformFromDevice
			$topLeft = $transform.Transform([System.Windows.Point]::new($left, $top))
			$bottomRight = $transform.Transform([System.Windows.Point]::new($right, $bottom))
			return New-GuiMainWindowBoundsSnapshot -Left ([double]$topLeft.X) -Top ([double]$topLeft.Y) -Width ([double]($bottomRight.X - $topLeft.X)) -Height ([double]($bottomRight.Y - $topLeft.Y))
		}

		return New-GuiMainWindowBoundsSnapshot -Left $left -Top $top -Width ([double]($right - $left)) -Height ([double]($bottom - $top))
	}

	function Get-GuiMainWindowWorkArea
	{
		param(
			[System.Windows.Window]$Window
		)

		try
		{
			Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
			$windowInterop = New-Object System.Windows.Interop.WindowInteropHelper($Window)
			$windowHandle = $windowInterop.Handle
			if ($windowHandle -eq [IntPtr]::Zero -and $windowInterop.PSObject.Methods['EnsureHandle'])
			{
				$windowHandle = $windowInterop.EnsureHandle()
			}
			if ($windowHandle -ne [IntPtr]::Zero)
			{
				$screen = [System.Windows.Forms.Screen]::FromHandle($windowHandle)
				if ($screen)
				{
					$bounds = Convert-GuiDeviceRectToDipBounds -Window $Window -Rect $screen.WorkingArea
					if (Test-GuiMainWindowBoundsSnapshot -Bounds $bounds) { return $bounds }
				}
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ResolveWorkArea' 2>$null
		}

		$workArea = [System.Windows.SystemParameters]::WorkArea
		return New-GuiMainWindowBoundsSnapshot -Left ([double]$workArea.Left) -Top ([double]$workArea.Top) -Width ([double]$workArea.Width) -Height ([double]$workArea.Height)
	}

	function Limit-GuiMainWindowBoundsToWorkArea
	{
		param(
			[System.Windows.Window]$Window,
			[object]$Bounds,
			[double]$MinWidth = 0.0,
			[double]$MinHeight = 0.0
		)

		if (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $Bounds)) { return $Bounds }

		$workAreaBounds = Get-GuiMainWindowWorkArea -Window $Window
		if (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $workAreaBounds)) { return $Bounds }

		$effectiveMinWidth = [Math]::Min([Math]::Max($MinWidth, 0.0), [double]$workAreaBounds.Width)
		$effectiveMinHeight = [Math]::Min([Math]::Max($MinHeight, 0.0), [double]$workAreaBounds.Height)
		$boundedWidth = [Math]::Min([Math]::Max([double]$Bounds.Width, $effectiveMinWidth), [double]$workAreaBounds.Width)
		$boundedHeight = [Math]::Min([Math]::Max([double]$Bounds.Height, $effectiveMinHeight), [double]$workAreaBounds.Height)
		$workLeft = [double]$workAreaBounds.Left
		$workTop = [double]$workAreaBounds.Top
		$maxLeft = $workLeft + [double]$workAreaBounds.Width - $boundedWidth
		$maxTop = $workTop + [double]$workAreaBounds.Height - $boundedHeight
		$boundedLeft = [Math]::Min([Math]::Max([double]$Bounds.Left, $workLeft), $maxLeft)
		$boundedTop = [Math]::Min([Math]::Max([double]$Bounds.Top, $workTop), $maxTop)

		return New-GuiMainWindowBoundsSnapshot -Left $boundedLeft -Top $boundedTop -Width $boundedWidth -Height $boundedHeight
	}

	function Test-GuiMainWindowBoundsEquivalent
	{
		param(
			[object]$LeftBounds,
			[object]$RightBounds
		)

		if (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $LeftBounds)) { return $false }
		if (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $RightBounds)) { return $false }

		return (
			[Math]::Abs([double]$LeftBounds.Left - [double]$RightBounds.Left) -le 1.0 -and
			[Math]::Abs([double]$LeftBounds.Top - [double]$RightBounds.Top) -le 1.0 -and
			[Math]::Abs([double]$LeftBounds.Width - [double]$RightBounds.Width) -le 1.0 -and
			[Math]::Abs([double]$LeftBounds.Height - [double]$RightBounds.Height) -le 1.0
		)
	}

	function Test-GuiMainWindowBoundsMatchWorkArea
	{
		param(
			[System.Windows.Window]$Window,
			[object]$Bounds
		)

		if (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $Bounds)) { return $false }
		$workAreaBounds = Get-GuiMainWindowWorkArea -Window $Window
		return (Test-GuiMainWindowBoundsEquivalent -LeftBounds $Bounds -RightBounds $workAreaBounds)
	}

	function Test-GuiMainWindowWorkAreaMaximized
	{
		param(
			[System.Windows.Window]$Window
		)

		if ([bool]$Script:MainWindowWorkAreaMaximized) { return $true }
		return ($Window -and $Window.WindowState -eq [System.Windows.WindowState]::Maximized)
	}

	function Set-GuiMainWindowChromeMaximizedState
	{
		param(
			[System.Windows.Window]$Window,
			[object]$RootBorder,
			[object]$TitleBarControl,
			[object]$BottomBorderControl,
			[bool]$Maximized
		)

		if (-not $RootBorder) { return }

		if ($Maximized)
		{
			$RootBorder.CornerRadius = [System.Windows.CornerRadius]::new(0)
			$RootBorder.Margin = [System.Windows.Thickness]::new(0)
			if ($TitleBarControl) { $TitleBarControl.CornerRadius = [System.Windows.CornerRadius]::new(0) }
			if ($BottomBorderControl) { $BottomBorderControl.CornerRadius = [System.Windows.CornerRadius]::new(0) }
		}
		else
		{
			$RootBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
			$RootBorder.Margin = [System.Windows.Thickness]::new(0)
			if ($TitleBarControl) { $TitleBarControl.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0) }
			if ($BottomBorderControl) { $BottomBorderControl.CornerRadius = [System.Windows.CornerRadius]::new(0, 0, 8, 8) }
		}
	}

	function Save-GuiMainWindowPlacementForRestore
	{
		param(
			[System.Windows.Window]$Window,
			[bool]$Maximized,
			[string]$Source = 'WindowSetup.SaveWindowPlacement'
		)

		try
		{
			if (-not $Window) { return }
			if (-not (Get-Command -Name 'Save-BaselineWindowPlacement' -ErrorAction SilentlyContinue)) { return }

			$rect = $null
			if ($Maximized)
			{
				if (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowRestoreBounds)
				{
					$rect = $Script:MainWindowRestoreBounds
				}
				elseif ($Window.WindowState -eq [System.Windows.WindowState]::Maximized)
				{
					$rect = Convert-GuiWindowRectToBoundsSnapshot -Rect $Window.RestoreBounds
				}
				if (-not $rect)
				{
					$rect = Get-GuiMainWindowBoundsSnapshot -Window $Window
				}
			}
			else
			{
				$rect = Get-GuiMainWindowBoundsSnapshot -Window $Window
			}

			if ($rect)
			{
				if ($Maximized -and (Test-GuiMainWindowBoundsMatchWorkArea -Window $Window -Bounds $rect) -and (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowDefaultRestoreBounds))
				{
					$rect = $Script:MainWindowDefaultRestoreBounds
				}
				Save-BaselineWindowPlacement -Left ([double]$rect.Left) -Top ([double]$rect.Top) `
					-Width ([double]$rect.Width) -Height ([double]$rect.Height) -Maximized $Maximized | Out-Null
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source $Source 2>$null
		}
	}

	function Set-GuiMainWindowWorkAreaMaximized
	{
		param(
			[System.Windows.Window]$Window,
			[bool]$Maximized,
			[switch]$PreserveRestoreBounds
		)

		if (-not $Window) { return }
		if ($Script:MainWindowApplyingWorkAreaMaximize) { return }

		$Script:MainWindowApplyingWorkAreaMaximize = $true
		try
		{
			if ($Maximized)
			{
				if (-not [bool]$Script:MainWindowWorkAreaMaximized -and ((-not $PreserveRestoreBounds) -or (-not (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowRestoreBounds))))
				{
					if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized)
					{
						$Script:MainWindowRestoreBounds = Convert-GuiWindowRectToBoundsSnapshot -Rect $Window.RestoreBounds
					}
					else
					{
						$Script:MainWindowRestoreBounds = Get-GuiMainWindowBoundsSnapshot -Window $Window
					}
				}
				if ($Window.WindowState -ne [System.Windows.WindowState]::Normal)
				{
					$Window.WindowState = [System.Windows.WindowState]::Normal
				}
				$workAreaBounds = Get-GuiMainWindowWorkArea -Window $Window
				if (Test-GuiMainWindowBoundsSnapshot -Bounds $workAreaBounds)
				{
					$Window.MinWidth = [Math]::Min([double]$Window.MinWidth, [double]$workAreaBounds.Width)
					$Window.MinHeight = [Math]::Min([double]$Window.MinHeight, [double]$workAreaBounds.Height)
					$Window.Left = [double]$workAreaBounds.Left
					$Window.Top = [double]$workAreaBounds.Top
					$Window.Width = [double]$workAreaBounds.Width
					$Window.Height = [double]$workAreaBounds.Height
					$Script:MainWindowWorkAreaMaximized = $true
				}
			}
			else
			{
				if ($Window.WindowState -ne [System.Windows.WindowState]::Normal)
				{
					$Window.WindowState = [System.Windows.WindowState]::Normal
				}
				$restoreBounds = if (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowRestoreBounds)
				{
					$Script:MainWindowRestoreBounds
				}
				else
				{
					$Script:MainWindowDefaultRestoreBounds
				}
				if ((Test-GuiMainWindowBoundsMatchWorkArea -Window $Window -Bounds $restoreBounds) -and (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowDefaultRestoreBounds))
				{
					$restoreBounds = $Script:MainWindowDefaultRestoreBounds
				}
				$restoreBounds = Limit-GuiMainWindowBoundsToWorkArea -Window $Window -Bounds $restoreBounds -MinWidth ([double]$Window.MinWidth) -MinHeight ([double]$Window.MinHeight)
				if (Test-GuiMainWindowBoundsSnapshot -Bounds $restoreBounds)
				{
					$Window.Left = [double]$restoreBounds.Left
					$Window.Top = [double]$restoreBounds.Top
					$Window.Width = [double]$restoreBounds.Width
					$Window.Height = [double]$restoreBounds.Height
				}
				$Script:MainWindowRestoreBounds = Get-GuiMainWindowBoundsSnapshot -Window $Window
				$Script:MainWindowWorkAreaMaximized = $false
			}
		}
		finally
		{
			$Script:MainWindowApplyingWorkAreaMaximize = $false
		}

		Set-GuiMainWindowChromeMaximizedState -Window $Window -RootBorder $WindowBorder -TitleBarControl $TitleBar -BottomBorderControl $BottomBorder -Maximized ([bool]$Script:MainWindowWorkAreaMaximized)
		Save-GuiMainWindowPlacementForRestore -Window $Window -Maximized ([bool]$Script:MainWindowWorkAreaMaximized) -Source 'WindowSetup.SaveWindowPlacement.StateChange'
	}

	try
	{
		$selectWindowIconFrame = {
			param(
				[Parameter(Mandatory = $true)]
				[System.Collections.IEnumerable]
				$Frames,
				[Parameter(Mandatory = $true)]
				[int]$TargetPixelWidth
			)

			$closest = $Frames |
				Sort-Object -Property @{ Expression = { [Math]::Abs($_.PixelWidth - $TargetPixelWidth) } } |
				Select-Object -First 1
			return $closest
		}

		$repoBasePath = Split-Path -Path $Script:GuiModuleBasePath -Parent
		$windowIconPath = Join-Path -Path $repoBasePath -ChildPath 'Assets\baseline.ico'
		if (-not [string]::IsNullOrWhiteSpace([string]$windowIconPath) -and (Test-Path -LiteralPath $windowIconPath -PathType Leaf))
		{
			$windowIconUri = [System.Uri]::new([System.IO.Path]::GetFullPath($windowIconPath), [System.UriKind]::Absolute)
			$iconDecoder = [System.Windows.Media.Imaging.IconBitmapDecoder]::new(
				$windowIconUri,
				[System.Windows.Media.Imaging.BitmapCreateOptions]::None,
				[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
			)
			$windowIconSource = if ($iconDecoder.Frames -and $iconDecoder.Frames.Count -gt 0)
			{
				& $selectWindowIconFrame -Frames $iconDecoder.Frames -TargetPixelWidth 32
			}
			else
			{
				$null
			}
			if (-not $windowIconSource)
			{
				$windowIconSource = [System.Windows.Media.Imaging.BitmapFrame]::Create($windowIconUri)
			}
			if ($windowIconSource -and $windowIconSource.CanFreeze)
			{
				$windowIconSource.Freeze()
			}
			$Form.Icon = $windowIconSource
			$titleBarLogo = $Form.FindName('TitleBarLogo')
			if ($titleBarLogo)
			{
				$titleBarLogo.Source = $windowIconSource
				[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($titleBarLogo, [System.Windows.Media.BitmapScalingMode]::HighQuality)
				$titleBarLogo.SnapsToDevicePixels = $true
				$titleBarLogo.UseLayoutRounding = $true
			}
		}
	}
	catch
	{
		Write-GuiRuntimeWarning -Context 'WindowIcon' -Message $_.Exception.Message
	}

	# Size the window to 85% of the screen working area so it fits any resolution
	# without being full-screen. Falls back to safe defaults if the call fails.
	# When the user has a saved placement and it still falls
	# on a connected display we restore that instead.
	try
	{
		$workArea = Get-GuiMainWindowWorkArea -Window $Form
		$widthRatio = if ($workArea.Width -ge 2560) { 0.55 } elseif ($workArea.Width -ge 1920) { 0.65 } else { 0.85 }
		$targetW  = [Math]::Round($workArea.Width  * $widthRatio)
		$targetH  = [Math]::Round($workArea.Height * 0.85)
		$maxW = [Math]::Min(1400, $workArea.Width)

		# On small screens, clamp MinWidth to the available work area
		$effectiveMinW = [Math]::Min($guiWindowMinWidth, $workArea.Width)
		$effectiveMinH = [Math]::Min($guiWindowMinHeight, $workArea.Height)

		$defaultW = [Math]::Min([Math]::Max($targetW, $effectiveMinW), $maxW)
		$defaultH = [Math]::Min([Math]::Max($targetH, $effectiveMinH), $workArea.Height)
		$defaultLeft = $workArea.Left + (([double]$workArea.Width  - $defaultW) / 2.0)
		$defaultTop  = $workArea.Top  + (([double]$workArea.Height - $defaultH) / 2.0)
		$Script:MainWindowDefaultRestoreBounds = New-GuiMainWindowBoundsSnapshot -Left ([double]$defaultLeft) -Top ([double]$defaultTop) -Width ([double]$defaultW) -Height ([double]$defaultH)

		$Form.MinWidth  = $effectiveMinW
		$Form.MinHeight = $effectiveMinH

		$placement = $null
		if (Get-Command -Name 'Resolve-BaselineWindowPlacement' -ErrorAction SilentlyContinue)
		{
			try
			{
				$defaultRect = [pscustomobject]@{
					Left   = [double]$defaultLeft
					Top    = [double]$defaultTop
					Width  = [double]$defaultW
					Height = [double]$defaultH
				}
				$placement = Resolve-BaselineWindowPlacement -DefaultRect $defaultRect
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ResolvePlacement'; $placement = $null }
		}

		if ($placement)
		{
			$placementBounds = New-GuiMainWindowBoundsSnapshot -Left ([double]$placement.Left) -Top ([double]$placement.Top) -Width ([double]$placement.Width) -Height ([double]$placement.Height)
			if ((Test-GuiMainWindowBoundsMatchWorkArea -Window $Form -Bounds $placementBounds) -and (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowDefaultRestoreBounds))
			{
				$placementBounds = $Script:MainWindowDefaultRestoreBounds
			}
			$Form.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
			$Form.Left = [double]$placementBounds.Left
			$Form.Top  = [double]$placementBounds.Top
			$placementBounds = Limit-GuiMainWindowBoundsToWorkArea -Window $Form -Bounds $placementBounds -MinWidth $effectiveMinW -MinHeight $effectiveMinH
			$Form.Width  = [Math]::Max([double]$placementBounds.Width,  [double]$effectiveMinW)
			$Form.Height = [Math]::Max([double]$placementBounds.Height, [double]$effectiveMinH)
			$Form.Left = [double]$placementBounds.Left
			$Form.Top  = [double]$placementBounds.Top
			if ($placement.Maximized)
			{
				$restoredNormalBounds = New-GuiMainWindowBoundsSnapshot -Left ([double]$placementBounds.Left) -Top ([double]$placementBounds.Top) -Width ([double]$Form.Width) -Height ([double]$Form.Height)
				if ((Test-GuiMainWindowBoundsMatchWorkArea -Window $Form -Bounds $restoredNormalBounds) -and (Test-GuiMainWindowBoundsSnapshot -Bounds $Script:MainWindowDefaultRestoreBounds))
				{
					$restoredNormalBounds = $Script:MainWindowDefaultRestoreBounds
				}
				$restoredNormalBounds = Limit-GuiMainWindowBoundsToWorkArea -Window $Form -Bounds $restoredNormalBounds -MinWidth $effectiveMinW -MinHeight $effectiveMinH
				$Script:MainWindowRestoreBounds = $restoredNormalBounds
				$Script:MainWindowPendingWorkAreaMaximize = $true
			}
		}
		else
		{
			$Form.Width  = $defaultW
			$Form.Height = $defaultH
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ApplyDefaultWindowBounds'
		$fallbackWorkArea = [System.Windows.SystemParameters]::WorkArea
		$Form.MinWidth = [Math]::Min($guiWindowMinWidth, [double]$fallbackWorkArea.Width)
		$Form.MinHeight = [Math]::Min($guiWindowMinHeight, [double]$fallbackWorkArea.Height)
		$Form.Width  = [Math]::Min([Math]::Max(940, [double]$Form.MinWidth), [double]$fallbackWorkArea.Width)
		$Form.Height = [Math]::Min([Math]::Max(720, [double]$Form.MinHeight), [double]$fallbackWorkArea.Height)
	}
	$HeaderBorder    = $Form.FindName("HeaderBorder")
	$HeaderSeparator = $Form.FindName("HeaderSeparator")
	$TitleText       = $Form.FindName("TitleText")
	$WindowBorder  = $Form.FindName("RootBorder")
	$TitleBar      = $Form.FindName("TitleBar")
	$TitleBarText  = $Form.FindName("TitleBarText")
	$BtnMinimize   = $Form.FindName("BtnMinimize")
	$BtnMaximize   = $Form.FindName("BtnMaximize")
	$BtnClose      = $Form.FindName("BtnClose")
	$BottomBorder  = $Form.FindName("BottomBorder")
	if ($BottomBorder) { $BottomBorder.CornerRadius = [System.Windows.CornerRadius]::new(0, 0, 8, 8) }

	$applyPendingMainWindowWorkAreaMaximize = {
		if (-not [bool]$Script:MainWindowPendingWorkAreaMaximize) { return }
		$Script:MainWindowPendingWorkAreaMaximize = $false
		Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true -PreserveRestoreBounds
	}.GetNewClosure()
	$Form.Add_SourceInitialized($applyPendingMainWindowWorkAreaMaximize)
	$Form.Add_Loaded($applyPendingMainWindowWorkAreaMaximize)

	# Wire custom title bar: drag, minimize, maximize, close
	if ($TitleBar)
	{
		$TitleBar.Add_MouseLeftButtonDown({
			if ($_.ClickCount -eq 2)
			{
				if (Test-GuiMainWindowWorkAreaMaximized -Window $Form)
				{
					Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $false
				}
				else
				{
					Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true
				}
			}
			else
			{
				if (Test-GuiMainWindowWorkAreaMaximized -Window $Form)
				{
					Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $false
				}
				$Form.DragMove()
			}
		})
	}
	# System-style right-click context menu for the custom title bar
	if ($TitleBar)
	{
		$sysMenu = New-Object System.Windows.Controls.ContextMenu
		$miRestore = New-Object System.Windows.Controls.MenuItem
		$miRestore.Header = 'Restore'
		$miRestore.Add_Click({ Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $false })
		$miMove = New-Object System.Windows.Controls.MenuItem
		$miMove.Header = 'Move'
		$miMove.IsEnabled = $false
		$miSize = New-Object System.Windows.Controls.MenuItem
		$miSize.Header = 'Size'
		$miSize.IsEnabled = $false
		$miMinimize = New-Object System.Windows.Controls.MenuItem
		$miMinimize.Header = 'Minimize'
		$miMinimize.Add_Click({ $Form.WindowState = [System.Windows.WindowState]::Minimized })
		$miMaximize = New-Object System.Windows.Controls.MenuItem
		$miMaximize.Header = 'Maximize'
		$miMaximize.Add_Click({ Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true })
		$sep = New-Object System.Windows.Controls.Separator
		$miRememberPos = New-Object System.Windows.Controls.MenuItem
		$miRememberPos.Header = 'Remember Window Position'
		$miRememberPos.IsCheckable = $true
		$miRememberPos.ToolTip = 'Restore this window''s size and position on next launch.'
		try
		{
			if (Get-Command -Name 'Get-BaselineUserPreference' -ErrorAction SilentlyContinue)
			{
				$miRememberPos.IsChecked = [bool](Get-BaselineUserPreference -Key 'RememberWindowPosition' -Default $true)
			}
			else { $miRememberPos.IsChecked = $true }
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.LoadRememberWindowPosition'; $miRememberPos.IsChecked = $true }
		$miRememberPos.Add_Click({
			try
			{
				if (Get-Command -Name 'Set-BaselineUserPreference' -ErrorAction SilentlyContinue)
				{
					Set-BaselineUserPreference -Key 'RememberWindowPosition' -Value ([bool]$miRememberPos.IsChecked)
				}
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.RememberPositionToggle' 2>$null }
		})
		$sepRemember = New-Object System.Windows.Controls.Separator
		$miClose = New-Object System.Windows.Controls.MenuItem
		$miClose.Header = 'Close'
		$miClose.InputGestureText = 'Alt+F4'
		$miClose.FontWeight = [System.Windows.FontWeights]::Bold
		$miClose.Add_Click({ $Form.Close() })
		[void]$sysMenu.Items.Add($miRestore)
		[void]$sysMenu.Items.Add($miMove)
		[void]$sysMenu.Items.Add($miSize)
		[void]$sysMenu.Items.Add($miMinimize)
		[void]$sysMenu.Items.Add($miMaximize)
		[void]$sysMenu.Items.Add($sepRemember)
		[void]$sysMenu.Items.Add($miRememberPos)
		[void]$sysMenu.Items.Add($sep)
		[void]$sysMenu.Items.Add($miClose)
		$Script:TitleBarSystemMenu = $sysMenu
		$Script:TitleBarSystemMenuItems = @{ Restore = $miRestore; Minimize = $miMinimize; Maximize = $miMaximize; Move = $miMove; Size = $miSize }
		$sysMenu.Add_Opened({
			$isMax = Test-GuiMainWindowWorkAreaMaximized -Window $Form
			$Script:TitleBarSystemMenuItems.Restore.IsEnabled = $isMax
			$Script:TitleBarSystemMenuItems.Maximize.IsEnabled = -not $isMax
			$Script:TitleBarSystemMenuItems.Move.IsEnabled = -not $isMax
			$Script:TitleBarSystemMenuItems.Size.IsEnabled = -not $isMax
		})
		$TitleBar.ContextMenu = $sysMenu
	}
	if ($BtnMinimize) { $BtnMinimize.Add_Click({ $Form.WindowState = [System.Windows.WindowState]::Minimized }) }
	if ($BtnMaximize)
	{
		$BtnMaximize.Add_Click({
			if (Test-GuiMainWindowWorkAreaMaximized -Window $Form)
			{
				Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $false
			}
			else
			{
				Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true
			}
		})
	}
	if ($BtnClose) { $BtnClose.Add_Click({ $Form.Close() }) }

	# Persist window placement on close so the next launch
	# can restore the user's normal bounds before applying work-area maximize.
	$Form.Add_Closing({
		Save-GuiMainWindowPlacementForRestore -Window $Form -Maximized (Test-GuiMainWindowWorkAreaMaximized -Window $Form) -Source 'WindowSetup.SaveWindowPlacement'
	})

	# Adjust border radius when maximized.
	$Form.Add_StateChanged({
		if ($Script:MainWindowApplyingWorkAreaMaximize) { return }
		if ($Form.WindowState -eq [System.Windows.WindowState]::Maximized)
		{
			Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true
			return
		}
		Set-GuiMainWindowChromeMaximizedState -Window $Form -RootBorder $WindowBorder -TitleBarControl $TitleBar -BottomBorderControl $BottomBorder -Maximized (Test-GuiMainWindowWorkAreaMaximized -Window $Form)
	})
	$PrimaryTabs   = $Form.FindName("PrimaryTabs")
	$PrimaryTabDropdown = $Form.FindName("PrimaryTabDropdown")
	$PrimaryTabHost = $Form.FindName("PrimaryTabHost")
	$ContentBorder = $Form.FindName("ContentBorder")
	$ContentScrollHost = $Form.FindName("ContentScrollHost")
	$ContentScroll = $Form.FindName("ContentScroll")
	$BtnBackToTop = $Form.FindName("BtnBackToTop")
	$ExpertModeBanner = $Form.FindName("ExpertModeBanner")
	$StatusText    = $Form.FindName("StatusText")
	$Script:StatusTextControl = $StatusText
	$ActionButtonBar = $Form.FindName("ActionButtonBar")
	$BtnPreviewRun = $Form.FindName("BtnPreviewRun")
	$BtnRun        = $Form.FindName("BtnRun")
	$Script:RunPathContextLabel = $Form.FindName("RunPathContextLabel")
	$BtnDefaults   = $Form.FindName("BtnDefaults")
	$BtnExportSettings = $null
	$BtnImportSettings = $null
	$BtnRestoreSnapshot = $null
	$ChkTheme      = $Form.FindName("ChkTheme")
	$BtnLanguage   = $Form.FindName("BtnLanguage")
	$LanguagePopup = $Form.FindName("LanguagePopup")
	$LanguagePopupBorder = $Form.FindName("LanguagePopupBorder")
	$TxtLanguageSearch = $Form.FindName("TxtLanguageSearch")
	$TxtLanguageSearchPlaceholder = $Form.FindName("TxtLanguageSearchPlaceholder")
	$LanguageListPanel = $Form.FindName("LanguageListPanel")
	$TxtLanguageState = $Form.FindName("TxtLanguageState")
	$ThemeToggleGroup = $Form.FindName("ThemeToggleGroup")
	$TxtThemeState = $Form.FindName("TxtThemeState")
	$BtnStartHere  = $Form.FindName("BtnStartHere")
	$BtnHelp       = $Form.FindName("BtnHelp")
	$BtnLog        = $Form.FindName("BtnLog")
	$ChkScan       = $Form.FindName("ChkScan")
	$ScanLabel     = $Form.FindName("ScanLabel")
	$SearchLabel   = $Form.FindName("SearchLabel")
	$TxtSearch     = $Form.FindName("TxtSearch")
	$TxtSearchPlaceholder = $Form.FindName("TxtSearchPlaceholder")
	$BtnClearSearch = $Form.FindName("BtnClearSearch")
	$RiskFilterLabel = $Form.FindName("RiskFilterLabel")
	$CategoryFilterLabel = $Form.FindName("CategoryFilterLabel")
	$PlatformFilterLabel = $Form.FindName("PlatformFilterLabel")
	$ViewFilterLabel = $Form.FindName("ViewFilterLabel")
	$CmbRiskFilter = $Form.FindName("CmbRiskFilter")
	$CmbCategoryFilter = $Form.FindName("CmbCategoryFilter")
	$CmbPlatformFilter = $Form.FindName("CmbPlatformFilter")
	$ChkHideUnavailableItems = $Form.FindName("ChkHideUnavailableItems")
	$ChkSelectedOnly = $Form.FindName("ChkSelectedOnly")
	$ChkHighRiskOnly = $Form.FindName("ChkHighRiskOnly")
	$ChkRestorableOnly = $Form.FindName("ChkRestorableOnly")
	$ChkGamingOnly = $Form.FindName("ChkGamingOnly")
	$ChkDesignMode = $Form.FindName("ChkDesignMode")
	$BtnFilterToggle = $Form.FindName("BtnFilterToggle")
	$FilterOptionsPanel = $Form.FindName("FilterOptionsPanel")
	$NavModeTweaks = $Form.FindName("NavModeTweaks")
	$NavModeGaming = $Form.FindName("NavModeGaming")
	$NavModeApps = $Form.FindName("NavModeApps")
	$NavModeUpdates = $Form.FindName("NavModeUpdates")
	$NavModeDeploymentMedia = $Form.FindName("NavModeDeploymentMedia")
	$ModeSubtitle = $Form.FindName("ModeSubtitle")
	$TweaksView = $Form.FindName("TweaksView")
	$DeploymentMediaView = $Form.FindName("DeploymentMediaView")
	$DeploymentMediaScroll = $Form.FindName("DeploymentMediaScroll")
	$DeploymentMediaWrapPanel = $Form.FindName("DeploymentMediaWrapPanel")
	$BtnDeploymentMediaDetectIso = $Form.FindName("BtnDeploymentMediaDetectIso")
	$BtnDeploymentMediaPreviewPlan = $Form.FindName("BtnDeploymentMediaPreviewPlan")
	$BtnDeploymentMediaStartBuild = $Form.FindName("BtnDeploymentMediaStartBuild")
	$DeploymentMediaStatusBanner = $Form.FindName("DeploymentMediaStatusBanner")
	$TxtDeploymentMediaSelectionStatus = $Form.FindName("TxtDeploymentMediaSelectionStatus")
	$TxtDeploymentMediaBuildStatus = $Form.FindName("TxtDeploymentMediaBuildStatus")
	$DeploymentMediaProgressPanel = $Form.FindName("DeploymentMediaProgressPanel")
	$DeploymentMediaProgressBar = $Form.FindName("DeploymentMediaProgressBar")
	$TxtDeploymentMediaProgressText = $Form.FindName("TxtDeploymentMediaProgressText")
	$CmbDeploymentMediaMicrosoftIso = $Form.FindName("CmbDeploymentMediaMicrosoftIso")
	$BtnDeploymentMediaDownloadMicrosoftIso = $Form.FindName("BtnDeploymentMediaDownloadMicrosoftIso")
	$TxtDeploymentMediaSourceIso = $Form.FindName("TxtDeploymentMediaSourceIso")
	$BtnDeploymentMediaBrowseIso = $Form.FindName("BtnDeploymentMediaBrowseIso")
	$TxtDeploymentMediaEditionIndex = $Form.FindName("TxtDeploymentMediaEditionIndex")
	$CmbDeploymentMediaDetectedEdition = $Form.FindName("CmbDeploymentMediaDetectedEdition")
	$TxtDeploymentMediaDetectedIsoSummary = $Form.FindName("TxtDeploymentMediaDetectedIsoSummary")
	$TxtDeploymentMediaWorkingDirectory = $Form.FindName("TxtDeploymentMediaWorkingDirectory")
	$BtnDeploymentMediaBrowseWorking = $Form.FindName("BtnDeploymentMediaBrowseWorking")
	$CmbDeploymentMediaOutputMode = $Form.FindName("CmbDeploymentMediaOutputMode")
	$TxtDeploymentMediaUsbTargetRoot = $Form.FindName("TxtDeploymentMediaUsbTargetRoot")
	$BtnDeploymentMediaBrowseUsbTarget = $Form.FindName("BtnDeploymentMediaBrowseUsbTarget")
	$TxtDeploymentMediaAutounattend = $Form.FindName("TxtDeploymentMediaAutounattend")
	$BtnDeploymentMediaCreateAutounattend = $Form.FindName("BtnDeploymentMediaCreateAutounattend")
	$BtnDeploymentMediaBrowseAutounattend = $Form.FindName("BtnDeploymentMediaBrowseAutounattend")
	$TxtDeploymentMediaDriverSource = $Form.FindName("TxtDeploymentMediaDriverSource")
	$BtnDeploymentMediaBrowseDrivers = $Form.FindName("BtnDeploymentMediaBrowseDrivers")
	$ChkDeploymentMediaBootDrivers = $Form.FindName("ChkDeploymentMediaBootDrivers")
	$ChkDeploymentMediaBaselineTweaks = $Form.FindName("ChkDeploymentMediaBaselineTweaks")
	$TxtDeploymentMediaPlanPreview = $Form.FindName("TxtDeploymentMediaPlanPreview")
	$AppsView = $Form.FindName("AppsView")
	$AppsScroll = $Form.FindName("AppsScroll")
	$AppsWrapPanel = $Form.FindName("AppsWrapPanel")
	$BtnUpdateAllApps = $Form.FindName("BtnUpdateAllApps")
	$AppsPackageManagerBanner = $Form.FindName("AppsPackageManagerBanner")
	$TxtAppsPackageManagerBanner = $Form.FindName("TxtAppsPackageManagerBanner")
	$AppsCategoryTabs = $Form.FindName("AppsCategoryTabs")
	$BtnAppsFilterToggle = $Form.FindName("BtnAppsFilterToggle")
	$AppsFilterOptionsPanel = $Form.FindName("AppsFilterOptionsPanel")
	$AppsSourceLabel = $Form.FindName("AppsSourceLabel")
	$AppsStatusLabel = $Form.FindName("AppsStatusLabel")
	$CmbAppsStatusFilter = $Form.FindName("CmbAppsStatusFilter")
	$TxtAppSelectionStatus = $Form.FindName("TxtAppSelectionStatus")
	$BtnInstallSelectedApps = $Form.FindName("BtnInstallSelectedApps")
	$BtnUninstallSelectedApps = $Form.FindName("BtnUninstallSelectedApps")
	$BtnUpdateSelectedApps = $Form.FindName("BtnUpdateSelectedApps")
	$BtnApplyQueuedActions = $Form.FindName("BtnApplyQueuedActions")
	$BtnClearQueuedActions = $Form.FindName("BtnClearQueuedActions")
	$BtnScanInstalledApps = $Form.FindName("BtnScanInstalledApps")
	$AppsActionSeparator1 = $Form.FindName("AppsActionSeparator1")
	$BtnAppsSourceFilterAll = $Form.FindName("BtnAppsSourceFilterAll")
	$BtnAppsSourceFilterWinGet = $Form.FindName("BtnAppsSourceFilterWinGet")
	$BtnAppsSourceFilterChocolatey = $Form.FindName("BtnAppsSourceFilterChocolatey")
	$AppsFilterViewDivider = $Form.FindName("AppsFilterViewDivider")
	$AppsViewModeLabel = $Form.FindName("AppsViewModeLabel")
	$BtnAppsViewCards = $Form.FindName("BtnAppsViewCards")
	$BtnAppsViewList = $Form.FindName("BtnAppsViewList")
	$BtnAppsAddCustom = $Form.FindName("BtnAppsAddCustom")
	$UpdateDialogOverlay = $Form.FindName("UpdateDialogOverlay")
	$UpdateDialogCard = $Form.FindName("UpdateDialogCard")
	$TxtOverlayTitle = $Form.FindName("TxtOverlayTitle")
	$TxtUpdateDescription = $Form.FindName("TxtUpdateDescription")
	$CustomPBarContainer = $Form.FindName("CustomPBarContainer")
	$TxtDownloadProgressLabel = $Form.FindName("TxtDownloadProgressLabel")
	$TxtDownloadProgressPct = $Form.FindName("TxtDownloadProgressPct")
	$BtnDownloadNo = $Form.FindName("BtnDownloadNo")
	$BtnDownloadYes = $Form.FindName("BtnDownloadYes")

	# --- Top Menu Bar controls ---
	$MenuBarBorder              = $Form.FindName("MenuBarBorder")
	$MainMenuBar                = $Form.FindName("MainMenuBar")
	$MenuFile                   = $Form.FindName("MenuFile")
	$MenuFileImportSettings     = $Form.FindName("MenuFileImportSettings")
	$MenuFileExportSettings     = $Form.FindName("MenuFileExportSettings")
	$MenuFileSettings           = $Form.FindName("MenuFileSettings")
	$MenuFileAuditSettings      = $Form.FindName("MenuFileAuditSettings")
	$MenuFileExportConfigProfile = $Form.FindName("MenuFileExportConfigProfile")
	$MenuFileExportSystemState  = $Form.FindName("MenuFileExportSystemState")
	$MenuFileExit               = $Form.FindName("MenuFileExit")
	$MenuActions                = $Form.FindName("MenuActions")
	$MenuActionsConnectToComputer = $Form.FindName("MenuActionsConnectToComputer")
	$MenuActionsDisconnect      = $Form.FindName("MenuActionsDisconnect")
	$RemoteModeBanner            = $Form.FindName("RemoteModeBanner")
	$RemoteModeBannerText        = $Form.FindName("RemoteModeBannerText")
	$BtnRemoteModeBannerDisconnect = $Form.FindName("BtnRemoteModeBannerDisconnect")
	$MenuActionsPreviewRun      = $Form.FindName("MenuActionsPreviewRun")
	$MenuActionsRunTweaks       = $Form.FindName("MenuActionsRunTweaks")
	$MenuActionsUndoLastRun     = $Form.FindName("MenuActionsUndoLastRun")
	$MenuActionsRestoreDefaults = $Form.FindName("MenuActionsRestoreDefaults")
	$MenuActionsCheckCompliance = $Form.FindName("MenuActionsCheckCompliance")
	$MenuActionsScanSystem      = $Form.FindName("MenuActionsScanSystem")
	$MenuActionsAuditLog        = $Form.FindName("MenuActionsAuditLog")
	$MenuActionsSep1            = $Form.FindName("MenuActionsSep1")
	$MenuActionsSep2            = $Form.FindName("MenuActionsSep2")
	$MenuActionsSep3            = $Form.FindName("MenuActionsSep3")
	$MenuView                   = $Form.FindName("MenuView")
	$MenuViewFilters            = $Form.FindName("MenuViewFilters")
	$MenuViewLogsPanel          = $Form.FindName("MenuViewLogsPanel")
	$MenuViewTheme              = $Form.FindName("MenuViewTheme")
	$MenuTools                  = $Form.FindName("MenuTools")
	$MenuToolsAppsManager       = $Form.FindName("MenuToolsAppsManager")
	$MenuToolsUpdateAllApps     = $Form.FindName("MenuToolsUpdateAllApps")
	$MenuToolsSepDeveloperDiagnostics = $Form.FindName("MenuToolsSepDeveloperDiagnostics")
	$MenuToolsDeveloperDiagnostics = $Form.FindName("MenuToolsDeveloperDiagnostics")
	$MenuToolsDeveloperDiagnosticsGenerateReport = $Form.FindName("MenuToolsDeveloperDiagnosticsGenerateReport")
	$MenuToolsDeveloperDiagnosticsSourceQuality = $Form.FindName("MenuToolsDeveloperDiagnosticsSourceQuality")
	$MenuToolsDeveloperDiagnosticsUnitTests = $Form.FindName("MenuToolsDeveloperDiagnosticsUnitTests")
	$MenuToolsDeveloperDiagnosticsGuiComposition = $Form.FindName("MenuToolsDeveloperDiagnosticsGuiComposition")
	$MenuToolsDeveloperDiagnosticsOpenLatestReport = $Form.FindName("MenuToolsDeveloperDiagnosticsOpenLatestReport")
	$MenuToolsDeveloperDiagnosticsCopyCommands = $Form.FindName("MenuToolsDeveloperDiagnosticsCopyCommands")
	$MenuToolsDeveloperDiagnosticsIntegrationSeparator = $Form.FindName("MenuToolsDeveloperDiagnosticsIntegrationSeparator")
	$MenuToolsDeveloperDiagnosticsIntegrationTests = $Form.FindName("MenuToolsDeveloperDiagnosticsIntegrationTests")
	$MenuToolsExportSupportBundle = $Form.FindName("MenuToolsExportSupportBundle")
	$MenuToolsApproveRemoteTargets = $Form.FindName("MenuToolsApproveRemoteTargets")
	$MenuToolsSaveRemoteApprovalPolicy = $Form.FindName("MenuToolsSaveRemoteApprovalPolicy")
	$MenuToolsLoadRemoteApprovalPolicy = $Form.FindName("MenuToolsLoadRemoteApprovalPolicy")
	$MenuToolsRemoteConsole = $Form.FindName("MenuToolsRemoteConsole")
	$MenuToolsOperatorConsole = $Form.FindName("MenuToolsOperatorConsole")
	$MenuToolsRemoteSessionStatus = $Form.FindName("MenuToolsRemoteSessionStatus")
	$MenuToolsRemovalPersistence = $Form.FindName("MenuToolsRemovalPersistence")
	$MenuToolsSepApps           = $Form.FindName("MenuToolsSepApps")
	$MenuHelp                   = $Form.FindName("MenuHelp")
	$MenuHelpHelp               = $Form.FindName("MenuHelpHelp")
	$MenuHelpStartGuide         = $Form.FindName("MenuHelpStartGuide")
	$MenuHelpReadme             = $Form.FindName("MenuHelpReadme")
	$MenuHelpFAQ                = $Form.FindName("MenuHelpFAQ")
	$MenuHelpChangelog          = $Form.FindName("MenuHelpChangelog")
	$MenuHelpCheckForUpdate     = $Form.FindName("MenuHelpCheckForUpdate")
	$MenuHelpReleaseStatus      = $Form.FindName("MenuHelpReleaseStatus")
	$MenuHelpTroubleshooting    = $Form.FindName("MenuHelpTroubleshooting")
	$MenuHelpAbout              = $Form.FindName("MenuHelpAbout")

	$Script:WindowBorder                 = $WindowBorder
	$Script:MenuBarBorder                = $MenuBarBorder
	$Script:MainMenuBar                  = $MainMenuBar
	$Script:MenuFile                     = $MenuFile
	$Script:MenuActions                  = $MenuActions
	$Script:MenuActionsConnectToComputer = $MenuActionsConnectToComputer
	$Script:MenuActionsDisconnect        = $MenuActionsDisconnect
	$Script:RemoteModeBanner             = $RemoteModeBanner
	$Script:RemoteModeBannerText         = $RemoteModeBannerText
	$Script:BtnRemoteModeBannerDisconnect = $BtnRemoteModeBannerDisconnect
	$Script:MenuView                     = $MenuView
	$Script:MenuTools                    = $MenuTools
	$Script:MenuHelp                     = $MenuHelp
	$Script:MenuViewFilters              = $MenuViewFilters
	$Script:MenuViewTheme                = $MenuViewTheme
	$Script:MenuActionsCheckCompliance   = $MenuActionsCheckCompliance
	$Script:MenuActionsScanSystem        = $MenuActionsScanSystem
	$Script:MenuActionsAuditLog          = $MenuActionsAuditLog
	$Script:MenuViewLogsPanel            = $MenuViewLogsPanel
	$Script:MenuHelpChangelog            = $MenuHelpChangelog
	$Script:MenuHelpCheckForUpdate       = $MenuHelpCheckForUpdate
	$Script:MenuActionsUndoLastRun       = $MenuActionsUndoLastRun
	$Script:MenuActionsRestoreDefaults   = $MenuActionsRestoreDefaults
	$Script:MenuActionsPreviewRun        = $MenuActionsPreviewRun
	$Script:MenuActionsRunTweaks         = $MenuActionsRunTweaks
	$Script:MenuFileExportSettings       = $MenuFileExportSettings
	$Script:MenuFileImportSettings       = $MenuFileImportSettings
	$Script:MenuFileSettings             = $MenuFileSettings
	$Script:MenuFileAuditSettings        = $MenuFileAuditSettings
	$Script:MenuFileExportConfigProfile  = $MenuFileExportConfigProfile
	$Script:MenuFileExportSystemState    = $MenuFileExportSystemState
	$Script:MenuToolsAppsManager         = $MenuToolsAppsManager
	$Script:MenuToolsUpdateAllApps       = $MenuToolsUpdateAllApps
	$Script:MenuToolsSepDeveloperDiagnostics = $MenuToolsSepDeveloperDiagnostics
	$Script:MenuToolsDeveloperDiagnostics = $MenuToolsDeveloperDiagnostics
	$Script:MenuToolsDeveloperDiagnosticsGenerateReport = $MenuToolsDeveloperDiagnosticsGenerateReport
	$Script:MenuToolsDeveloperDiagnosticsSourceQuality = $MenuToolsDeveloperDiagnosticsSourceQuality
	$Script:MenuToolsDeveloperDiagnosticsUnitTests = $MenuToolsDeveloperDiagnosticsUnitTests
	$Script:MenuToolsDeveloperDiagnosticsGuiComposition = $MenuToolsDeveloperDiagnosticsGuiComposition
	$Script:MenuToolsDeveloperDiagnosticsOpenLatestReport = $MenuToolsDeveloperDiagnosticsOpenLatestReport
	$Script:MenuToolsDeveloperDiagnosticsCopyCommands = $MenuToolsDeveloperDiagnosticsCopyCommands
	$Script:MenuToolsDeveloperDiagnosticsIntegrationSeparator = $MenuToolsDeveloperDiagnosticsIntegrationSeparator
	$Script:MenuToolsDeveloperDiagnosticsIntegrationTests = $MenuToolsDeveloperDiagnosticsIntegrationTests
	$Script:MenuToolsExportSupportBundle = $MenuToolsExportSupportBundle
	$Script:MenuToolsApproveRemoteTargets = $MenuToolsApproveRemoteTargets
	$Script:MenuToolsSaveRemoteApprovalPolicy = $MenuToolsSaveRemoteApprovalPolicy
	$Script:MenuToolsLoadRemoteApprovalPolicy = $MenuToolsLoadRemoteApprovalPolicy
	$Script:MenuToolsRemoteConsole = $MenuToolsRemoteConsole
	$Script:MenuToolsOperatorConsole = $MenuToolsOperatorConsole
	$Script:MenuToolsRemoteSessionStatus = $MenuToolsRemoteSessionStatus
	$Script:MenuToolsRemovalPersistence = $MenuToolsRemovalPersistence
	$Script:MenuActionsSep1              = $MenuActionsSep1
	$Script:MenuActionsSep2              = $MenuActionsSep2
	$Script:MenuActionsSep3              = $MenuActionsSep3
	$Script:MenuToolsSepApps             = $MenuToolsSepApps
	$Script:MenuHelpHelp                 = $MenuHelpHelp
	$Script:MenuHelpStartGuide           = $MenuHelpStartGuide
	$Script:MenuHelpReadme               = $MenuHelpReadme
	$Script:MenuHelpFAQ                  = $MenuHelpFAQ
	$Script:MenuHelpReleaseStatus        = $MenuHelpReleaseStatus
	$Script:MenuHelpTroubleshooting      = $MenuHelpTroubleshooting
	$Script:MenuHelpAbout                = $MenuHelpAbout

	$Script:PrimaryTabHost = $PrimaryTabHost
	$Script:ContentScrollHost = $ContentScrollHost
	$Script:BtnBackToTop = $BtnBackToTop
	$Script:ExpertModeBanner = $ExpertModeBanner
	$Script:ThemeToggleGroup = $ThemeToggleGroup
	$Script:SearchLabel = $SearchLabel
	$Script:TxtSearch = $TxtSearch
	$Script:TxtSearchPlaceholder = $TxtSearchPlaceholder
	$Script:BtnClearSearch = $BtnClearSearch
	$Script:BtnFilterToggle = $BtnFilterToggle
	$Script:FilterOptionsPanel = $FilterOptionsPanel
	$Script:RiskFilterLabel = $RiskFilterLabel
	$Script:CategoryFilterLabel = $CategoryFilterLabel
	$Script:PlatformFilterLabel = $PlatformFilterLabel
	$Script:ViewFilterLabel = $ViewFilterLabel
	$Script:ChkSelectedOnly = $ChkSelectedOnly
	$Script:CmbPlatformFilter = $CmbPlatformFilter
	$Script:ChkHideUnavailableItems = $ChkHideUnavailableItems
	$Script:ChkHighRiskOnly = $ChkHighRiskOnly
	$Script:ChkRestorableOnly = $ChkRestorableOnly
	$Script:ChkGamingOnly = $ChkGamingOnly
	$Script:BtnPreviewRun = $BtnPreviewRun
	$Script:BtnRun = $BtnRun
	$Script:BtnDefaults = $BtnDefaults
	$Script:BtnStartHere = $BtnStartHere
	$Script:BtnHelp = $BtnHelp
	$Script:NavModeTweaks = $NavModeTweaks
	$Script:NavModeGaming = $NavModeGaming
	$Script:NavModeApps = $NavModeApps
	$Script:NavModeUpdates = $NavModeUpdates
	$Script:NavModeDeploymentMedia = $NavModeDeploymentMedia
	$Script:ModeSubtitle = $ModeSubtitle
	$Script:TweaksView = $TweaksView
	$Script:DeploymentMediaView = $DeploymentMediaView
	$Script:DeploymentMediaScroll = $DeploymentMediaScroll
	$Script:DeploymentMediaWrapPanel = $DeploymentMediaWrapPanel
	$Script:BtnDeploymentMediaDetectIso = $BtnDeploymentMediaDetectIso
	$Script:BtnDeploymentMediaPreviewPlan = $BtnDeploymentMediaPreviewPlan
	$Script:BtnDeploymentMediaStartBuild = $BtnDeploymentMediaStartBuild
	$Script:DeploymentMediaStatusBanner = $DeploymentMediaStatusBanner
	$Script:TxtDeploymentMediaSelectionStatus = $TxtDeploymentMediaSelectionStatus
	$Script:TxtDeploymentMediaBuildStatus = $TxtDeploymentMediaBuildStatus
	$Script:DeploymentMediaProgressPanel = $DeploymentMediaProgressPanel
	$Script:DeploymentMediaProgressBar = $DeploymentMediaProgressBar
	$Script:TxtDeploymentMediaProgressText = $TxtDeploymentMediaProgressText
	$Script:CmbDeploymentMediaMicrosoftIso = $CmbDeploymentMediaMicrosoftIso
	$Script:BtnDeploymentMediaDownloadMicrosoftIso = $BtnDeploymentMediaDownloadMicrosoftIso
	$Script:TxtDeploymentMediaSourceIso = $TxtDeploymentMediaSourceIso
	$Script:BtnDeploymentMediaBrowseIso = $BtnDeploymentMediaBrowseIso
	$Script:TxtDeploymentMediaEditionIndex = $TxtDeploymentMediaEditionIndex
	$Script:CmbDeploymentMediaDetectedEdition = $CmbDeploymentMediaDetectedEdition
	$Script:TxtDeploymentMediaDetectedIsoSummary = $TxtDeploymentMediaDetectedIsoSummary
	$Script:TxtDeploymentMediaWorkingDirectory = $TxtDeploymentMediaWorkingDirectory
	$Script:BtnDeploymentMediaBrowseWorking = $BtnDeploymentMediaBrowseWorking
	$Script:CmbDeploymentMediaOutputMode = $CmbDeploymentMediaOutputMode
	$Script:TxtDeploymentMediaUsbTargetRoot = $TxtDeploymentMediaUsbTargetRoot
	$Script:BtnDeploymentMediaBrowseUsbTarget = $BtnDeploymentMediaBrowseUsbTarget
	$Script:TxtDeploymentMediaAutounattend = $TxtDeploymentMediaAutounattend
	$Script:BtnDeploymentMediaCreateAutounattend = $BtnDeploymentMediaCreateAutounattend
	$Script:BtnDeploymentMediaBrowseAutounattend = $BtnDeploymentMediaBrowseAutounattend
	$Script:TxtDeploymentMediaDriverSource = $TxtDeploymentMediaDriverSource
	$Script:BtnDeploymentMediaBrowseDrivers = $BtnDeploymentMediaBrowseDrivers
	$Script:ChkDeploymentMediaBootDrivers = $ChkDeploymentMediaBootDrivers
	$Script:ChkDeploymentMediaBaselineTweaks = $ChkDeploymentMediaBaselineTweaks
	$Script:TxtDeploymentMediaPlanPreview = $TxtDeploymentMediaPlanPreview
	$Script:AppsView = $AppsView
	$Script:AppsScroll = $AppsScroll
	$Script:AppsWrapPanel = $AppsWrapPanel
	$Script:BtnUpdateAllApps = $BtnUpdateAllApps
	$Script:AppsPackageManagerBanner = $AppsPackageManagerBanner
	$Script:TxtAppsPackageManagerBanner = $TxtAppsPackageManagerBanner
	$Script:AppsCategoryTabs = $AppsCategoryTabs
	$Script:BtnAppsFilterToggle = $BtnAppsFilterToggle
	$Script:AppsFilterOptionsPanel = $AppsFilterOptionsPanel
	$Script:AppsSourceLabel = $AppsSourceLabel
	$Script:AppsStatusLabel = $AppsStatusLabel
	$Script:CmbAppsStatusFilter = $CmbAppsStatusFilter
	$Script:TxtAppSelectionStatus = $TxtAppSelectionStatus
	$Script:BtnInstallSelectedApps = $BtnInstallSelectedApps
	$Script:BtnUninstallSelectedApps = $BtnUninstallSelectedApps
	$Script:BtnUpdateSelectedApps = $BtnUpdateSelectedApps
	$Script:BtnApplyQueuedActions = $BtnApplyQueuedActions
	$Script:BtnClearQueuedActions = $BtnClearQueuedActions
	$Script:BtnScanInstalledApps = $BtnScanInstalledApps
	$Script:AppsActionSeparator1 = $AppsActionSeparator1
	$Script:BtnAppsSourceFilterAll = $BtnAppsSourceFilterAll
	$Script:BtnAppsSourceFilterWinGet = $BtnAppsSourceFilterWinGet
	$Script:BtnAppsSourceFilterChocolatey = $BtnAppsSourceFilterChocolatey
	$Script:AppsFilterViewDivider = $AppsFilterViewDivider
	$Script:AppsViewModeLabel = $AppsViewModeLabel
	$Script:BtnAppsViewCards = $BtnAppsViewCards
	$Script:BtnAppsViewList = $BtnAppsViewList
	$Script:BtnAppsAddCustom = $BtnAppsAddCustom
	$Script:UpdateDialogOverlay = $UpdateDialogOverlay
	$Script:UpdateDialogCard = $UpdateDialogCard
	$Script:TxtOverlayTitle = $TxtOverlayTitle
	$Script:TxtUpdateDescription = $TxtUpdateDescription
	$Script:CustomPBarContainer = $CustomPBarContainer
	$Script:TxtDownloadProgressLabel = $TxtDownloadProgressLabel
	$Script:TxtDownloadProgressPct = $TxtDownloadProgressPct
	$Script:BtnDownloadNo = $BtnDownloadNo
	$Script:BtnDownloadYes = $BtnDownloadYes
	$Script:ExecutionLogBox = $null
	$Script:ExecutionPreviousContent = $null
	$Script:ExecutionLastConsoleAction = $null
	$Script:ExecutionProgressHost = $null
	$Script:ExecutionProgressBar = $null
	$Script:ExecutionProgressText = $null
	$Script:ExecutionProgressIndeterminate = $false
	$Script:ExecutionLastProgressCompleted = -1
	$Script:ExecutionSubProgressBar = $null
	$Script:ExecutionSubProgressText = $null
	$Script:AbortRunButton = $null
	$Script:AbortRequested = $false
	$Script:ExecutionWorker = $null
	$Script:ExecutionRunspace = $null
	$Script:ExecutionRunPowerShell = $null
		$Script:ExecutionRunTimer = $null
		$Script:RunAbortDisposition = $null
		$Script:ExecutionMode = $null
		$Script:SuppressRunClosePrompt = $false
		$Script:ForceCloseCompleted = $false
		$Script:ExecutionTimerErrorShown = $false
	$Script:AbortDialogShowing = $false
	$Script:BgPS = $null
	$Script:BgAsync = $null
	$Script:BaselineApplicationsCatalog = $null
	$Script:BaselineApplicationsCatalogByCategory = @{}
	$Script:BaselineApplicationsCatalogCategory = $null
	$Script:InstalledAppsCache = [pscustomobject]@{
		WinGet = @{}
		Chocolatey = @{}
		WinGetUpdates = @{}
		ChocolateyUpdates = @{}
	}
	$Script:AppsModeActive = $false
	$Script:GamingModeActive = $false
	$Script:GamingReturnPrimaryTab = $null
	$Script:UpdatesModeActive = $false
	$Script:UpdatesReturnPrimaryTab = $null
	$Script:DeploymentMediaModeActive = $false
	$Script:DeploymentMediaReturnPrimaryTab = $null
	$Script:DeploymentMediaBuilderViewInitialized = $false
	$Script:DeploymentMediaDetectedIsoInfo = $null
	$Script:DeploymentMediaCurrentPlan = $null
	$Script:DeploymentMediaBuildInProgress = $false
	$Script:AppsViewLoaded = $false
	$Script:AppsViewDirty = $false
	$Script:AppsViewBuildSignature = $null
	$Script:AppsCacheRefreshInProgress = $false
	$Script:AppsOperationInProgress = $false
	$Script:AppsCategoryFilter = 'Browsers'
	$Script:AppsStatusFilter = 'All'
	$Script:AppsViewMode = 'Cards'
	$Script:AppsViewModeUiUpdating = $false
	$Script:AppsFilterUiUpdating = $false
	$Script:TxtAppsProgressText = $null
	$Script:AppsProgressBar = $null
	$Script:AppsActionButtons = [System.Collections.Generic.List[object]]::new()
	$Script:AppsBulkActionButtons = [System.Collections.Generic.List[object]]::new()
	$Script:AppsSelectionControls = [System.Collections.Generic.List[object]]::new()
	$Script:AppsQueuedActionControls = [System.Collections.Generic.List[object]]::new()
	$Script:AppsQueuedActionControlMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$Script:SelectedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$Script:AppsSelectionUiUpdating = $false
	$Script:AppsQueuedActionUiUpdating = $false
	$Script:AppActionStates = @{}
	foreach ($bulkButton in @($BtnInstallSelectedApps, $BtnUninstallSelectedApps, $BtnUpdateSelectedApps, $BtnApplyQueuedActions, $BtnClearQueuedActions, $BtnScanInstalledApps))
	{
		if ($bulkButton)
		{
			[void]$Script:AppsBulkActionButtons.Add($bulkButton)
		}
	}
	$Script:DownloadStartEvent = $null
	$Script:DownloadExtractEvent = $null
	$Script:UpdateCheckPrimaryClickEvent = $null
	$Script:UpdateCheckSecondaryClickEvent = $null
	$Script:UpdateOverlayPrimaryClickEvent = $null
	$Script:UpdateOverlaySecondaryClickEvent = $null
	$Script:UpdateOverlayPrimaryPreviewMouseDownEvent = $null
	$Script:UpdateOverlayPrimaryPreviewMouseUpEvent = $null
	$Script:UpdateOverlayPreviewMouseDownEvent = $null
	$Script:UpdateOverlayPreviewMouseUpEvent = $null
	$Script:UpdateOverlayPrimaryClickAction = $null
	$Script:UpdateOverlaySecondaryClickAction = $null
	$Script:UpdateDownloadTimer = $null
	$Script:UpdateDownloadPowerShell = $null
	$Script:UpdateDownloadRunspace = $null
	$Script:UpdateDownloadAsyncResult = $null
	$Script:UpdateDownloadSyncHash = $null
	$Script:UpdateOverlayState = [hashtable]::Synchronized(@{
		PrimaryAction = $null
		SecondaryAction = $null
		PrimaryCloses = $false
		SecondaryCloses = $true
	})
	Initialize-BaselineUpdateOverlay
	$Script:SearchText = ''
	$Script:AppsSearchText = ''
	$Script:AppsPackageSourcePreference = 'auto'
	$Script:AppsSourceFilter = 'All'
	$Script:AppsSourceFilterUiUpdating = $false
	$Script:SearchResultsTabTag = '__SEARCH_RESULTS__'
	$Script:LastStandardPrimaryTab = $null
	$Script:TabScrollOffsets = @{}
	$Script:TabContentCache = @{}
	$Script:CategoryFilterListCache = @{}
	$Script:LastCategoryFilterPopulateKey = $null
	$Script:LastCategoryFilterSignature = $null
	$Script:FilterGeneration = 0
	$Script:SearchRefreshTimer = $null
	$Script:FilterRefreshTimer = $null
	$Script:PendingFilterValues = @{}
	$Script:SearchUiUpdating = $false
	$Script:AppsSourceUiUpdating = $false
	$Script:ThemeUiUpdating = $false
	$Script:SearchRefreshDelayMs = $Script:GuiLayout.SearchRefreshDelayMs
	$Script:CurrentThemeName = $Script:InitialResolvedThemeName
	$Script:UiSnapshotUndo = $null
	$Script:PresetStatusMessage = $null
	$Script:PresetStatusTone = 'info'
	$Script:PresetStatusBadge = $null
	$Script:PresetProgressHost = $null
	$Script:PresetProgressBar = $null
	$Script:EnvironmentRecommendationData = $null
	$Script:EnvironmentSummaryText = $null
	$Script:SecondaryActionGroupBorder = $null
	$previousGuiUnhandledExceptionHooked = [bool]$Script:GuiUnhandledExceptionHooked
	$previousGuiUnhandledExceptionHandler = $Script:GuiUnhandledExceptionHandler
	$previousGuiDispatcher = if ($Script:MainForm -and $Script:MainForm.Dispatcher)
	{
		$Script:MainForm.Dispatcher
	}
	elseif ($Form -and $Form.Dispatcher)
	{
		$Form.Dispatcher
	}
	else
	{
		$null
	}

	if ($previousGuiUnhandledExceptionHooked -and $previousGuiUnhandledExceptionHandler -and $previousGuiDispatcher)
	{
		try
		{
			$previousGuiDispatcher.remove_UnhandledException($previousGuiUnhandledExceptionHandler)
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.RemoveUnhandledExceptionHook' }
	}

	$Script:GuiUnhandledExceptionHooked = $false
	$Script:GuiUnhandledExceptionHandler = $null
	$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
		[System.StringComparer]::OrdinalIgnoreCase
	)
	$Script:ExplicitPresetSelectionDefinitions = @{}

	$Script:GuiDispatcherHandlingError = $false
	if (-not $Script:GuiUnhandledExceptionHooked -and $Form -and $Form.Dispatcher)
	{
		$Script:GuiUnhandledExceptionHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
			param($unusedSender, $e)

			if ($Script:GuiDispatcherHandlingError)
			{
				$e.Handled = $true
				return
			}
			$Script:GuiDispatcherHandlingError = $true

			$dispatcherException = $null
			if ($e -and $e.Exception)
			{
				$dispatcherException = $e.Exception
			}

			# Treat critical .NET exceptions as fatal. Reporting failures below must
			# never promote a non-fatal dispatcher exception into a fatal shutdown.
			$isFatal = $dispatcherException -is [System.StackOverflowException] -or
				$dispatcherException -is [System.OutOfMemoryException] -or
				$dispatcherException -is [System.AccessViolationException] -or
				$dispatcherException -is [System.InvalidProgramException]

			try
			{
				$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
				if ($showGuiRuntimeFailureScript -and $dispatcherException)
				{
					[void](& $showGuiRuntimeFailureScript -Context 'WPF Dispatcher' -Exception $dispatcherException -ShowDialog)
				}
				elseif ($dispatcherException)
				{
					Write-Warning (Format-BaselineErrorForLog -ErrorObject $dispatcherException -Prefix 'GUI event failed: WPF Dispatcher')
				}
				else
				{
					Write-Warning 'GUI event failed: WPF Dispatcher raised an unhandled exception event without an exception payload.'
				}
			}
			catch
			{
				$reporterErrorRecord = $_
				$dispatcherErrorText = if ($dispatcherException) {
					try { Format-BaselineErrorForLog -ErrorObject $dispatcherException -Prefix 'GUI event failed: WPF Dispatcher' }
					catch {
						$formattingErrorRecord = $_
						$formattingErrorType = if ($formattingErrorRecord.Exception) { $formattingErrorRecord.Exception.GetType().FullName } else { $formattingErrorRecord.GetType().FullName }
						Write-Warning ('GUI dispatcher error formatting failed: {0}: {1}' -f $formattingErrorType, [string]$formattingErrorRecord)
						'GUI event failed: WPF Dispatcher: {0}: {1}' -f $dispatcherException.GetType().FullName, [string]$dispatcherException
					}
				} else {
					'GUI event failed: WPF Dispatcher raised an unhandled exception event without an exception payload.'
				}
				$reporterErrorText = try {
					Format-BaselineErrorForLog -ErrorObject $reporterErrorRecord.Exception -Prefix 'GUI dispatcher failure reporter failed'
				}
				catch {
					$reporterFormattingErrorRecord = $_
					$reporterFormattingErrorType = if ($reporterFormattingErrorRecord.Exception) { $reporterFormattingErrorRecord.Exception.GetType().FullName } else { $reporterFormattingErrorRecord.GetType().FullName }
					Write-Warning ('GUI dispatcher reporter error formatting failed: {0}: {1}' -f $reporterFormattingErrorType, [string]$reporterFormattingErrorRecord)
					'GUI dispatcher failure reporter failed.'
				}

				try
				{
					if (Get-Command -Name 'LogError' -CommandType Function,Alias -ErrorAction SilentlyContinue)
					{
						LogError $dispatcherErrorText
						LogError $reporterErrorText
					}
					elseif ($Global:LogFilePath)
					{
						$timestamp = Get-Date -Format 'dd-MM-yyyy HH:mm'
						$lines = @(
							('{0} ERROR: {1}' -f $timestamp, $dispatcherErrorText),
							('{0} ERROR: {1}' -f $timestamp, $reporterErrorText)
						)
						[System.IO.File]::AppendAllText([string]$Global:LogFilePath, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
					}
					else
					{
						Write-Warning $dispatcherErrorText
						Write-Warning $reporterErrorText
					}
				}
				catch
				{
					Write-Warning $dispatcherErrorText
					Write-Warning $reporterErrorText
				}

				try
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $reporterErrorRecord -Source 'WindowSetup.DispatcherRuntimeFailureReport' -Severity Warning
					}
				}
				catch
				{
					$swallowedLoggingErrorRecord = $_
					$swallowedLoggingErrorType = if ($swallowedLoggingErrorRecord.Exception) { $swallowedLoggingErrorRecord.Exception.GetType().FullName } else { $swallowedLoggingErrorRecord.GetType().FullName }
					Write-Warning ('GUI dispatcher swallowed-exception logging failed: {0}: {1}' -f $swallowedLoggingErrorType, [string]$swallowedLoggingErrorRecord)
				}
			}
			finally
			{
				$Script:GuiDispatcherHandlingError = $false
			}

			if ($e) { $e.Handled = -not $isFatal }
		}

		try
		{
			$Form.Dispatcher.add_UnhandledException($Script:GuiUnhandledExceptionHandler)
			$Script:GuiUnhandledExceptionHooked = $true
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.AddUnhandledExceptionHook' }
	}
	$Script:RiskFilter = 'All'
	$Script:CategoryFilter = 'All'
	$Script:PlatformFilter = 'ThisDevice'
	$Script:CategoryFilterInternalValues = [System.Collections.Generic.List[string]]::new()
	$Script:PlatformFilterInternalValues = [System.Collections.Generic.List[string]]::new()
	$Script:AppsCategoryFilterInternalValues = [System.Collections.Generic.List[string]]::new()
	$Script:AppsStatusFilterInternalValues = [System.Collections.Generic.List[string]]::new()
	$Script:LastPlatformFilterPopulateKey = $null
	$Script:SelectedOnlyFilter = $false
	$Script:HighRiskOnlyFilter = $false
	$Script:RestorableOnlyFilter = $false
	$Script:GamingOnlyFilter = $false
	$Script:HideUnavailableItems = $true
	$Script:DesignMode = $false
	$Script:RestoreLastSession = $true
	$Script:AutoScanOnLaunch = $false
	$Script:StartupRunInitialActions = $true
	$Script:StartupCheckWinGet = $true
	$Script:StartupWinGetCheckFrequency = 'Startup'
	$Script:StartupCheckChocolatey = $true
	$Script:StartupChocolateyCheckFrequency = 'Startup'
	$Script:RequireRunConfirmation = $true
	$Script:AutoCheckUpdates = $true
	$Script:UpdateCheckFrequency = 'Startup'
	$Script:UpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
	$Script:IncludePrereleaseUpdates = $false
	$Script:ScanEnabled = $false
	$Script:DebugLoggingEnabled = $false
	$Script:LogLevel = 'All'
	$Script:LogFileDirectory = ''
	$Script:DefaultStartupMode = 'Safe'
	$Script:UIDensity = if (Get-Command -Name 'Get-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineUiDensity } else { 'Comfort' }
	try
	{
		if (Get-Command -Name 'Get-BaselineUserPreference' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$Script:HideUnavailableItems = [bool](Get-BaselineUserPreference -Key 'HideUnavailableItems' -Default $true)
			$Script:DesignMode = [bool](Get-BaselineUserPreference -Key 'DesignMode' -Default $false)
			$Script:RestoreLastSession = [bool](Get-BaselineUserPreference -Key 'RestoreLastSession' -Default $true)
			$Script:AutoScanOnLaunch = [bool](Get-BaselineUserPreference -Key 'AutoScanOnLaunch' -Default $false)
			$Script:StartupRunInitialActions = [bool](Get-BaselineUserPreference -Key 'StartupRunInitialActions' -Default $true)
			$Script:StartupCheckWinGet = [bool](Get-BaselineUserPreference -Key 'StartupCheckWinGet' -Default $true)
			$Script:StartupWinGetCheckFrequency = [string](Get-BaselineUserPreference -Key 'StartupWinGetCheckFrequency' -Default 'Startup')
			$Script:StartupCheckChocolatey = [bool](Get-BaselineUserPreference -Key 'StartupCheckChocolatey' -Default $true)
			$Script:StartupChocolateyCheckFrequency = [string](Get-BaselineUserPreference -Key 'StartupChocolateyCheckFrequency' -Default 'Startup')
			if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$Script:StartupWinGetCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $Script:StartupWinGetCheckFrequency
				$Script:StartupChocolateyCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $Script:StartupChocolateyCheckFrequency
			}
			$Script:RequireRunConfirmation = [bool](Get-BaselineUserPreference -Key 'RequireRunConfirmation' -Default $true)
			$Script:AutoCheckUpdates = [bool](Get-BaselineUserPreference -Key 'AutoCheckUpdates' -Default $true)
			$Script:UpdateCheckFrequency = [string](Get-BaselineUserPreference -Key 'UpdateCheckFrequency' -Default 'Startup')
			if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue) { $Script:UpdateCheckFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $Script:UpdateCheckFrequency }
			$defaultUpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
			$Script:UpdateBranch = [string](Get-BaselineUserPreference -Key 'UpdateBranch' -Default $defaultUpdateBranch)
			if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { $Script:UpdateBranch = ConvertTo-BaselineUpdateBranch -Branch $Script:UpdateBranch }
			$Script:IncludePrereleaseUpdates = [bool](Get-BaselineUserPreference -Key 'IncludePrereleaseUpdates' -Default $false)
			$Script:DebugLoggingEnabled = [bool](Get-BaselineUserPreference -Key 'DebugLoggingEnabled' -Default $false)
			$Script:LogLevel = [string](Get-BaselineUserPreference -Key 'LogLevel' -Default 'All')
			if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue) { $Script:LogLevel = Normalize-GuiLogLevel -Level $Script:LogLevel }
			$Script:LogFileDirectory = [string](Get-BaselineUserPreference -Key 'LogFileDirectory' -Default '')
			$Script:DefaultStartupMode = [string](Get-BaselineUserPreference -Key 'DefaultStartupMode' -Default $Script:DefaultStartupMode)
			if ($Script:DefaultStartupMode -notin @('Safe', 'Expert')) { $Script:DefaultStartupMode = 'Safe' }
			$Script:UIDensity = if (Get-Command -Name 'Normalize-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue) { Normalize-BaselineUiDensity -Density ([string](Get-BaselineUserPreference -Key 'UIDensity' -Default $Script:UIDensity)) } else { [string](Get-BaselineUserPreference -Key 'UIDensity' -Default $Script:UIDensity) }
			$Script:AppsPackageSourcePreference = [string](Get-BaselineUserPreference -Key 'AppsPackageSourcePreference' -Default $Script:AppsPackageSourcePreference)
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.LoadGuiPreferences'
		$Script:HideUnavailableItems = $true
		$Script:DesignMode = $false
		$Script:RestoreLastSession = $true
		$Script:StartupRunInitialActions = $true
		$Script:StartupCheckWinGet = $true
		$Script:StartupWinGetCheckFrequency = 'Startup'
		$Script:StartupCheckChocolatey = $true
		$Script:StartupChocolateyCheckFrequency = 'Startup'
		$Script:RequireRunConfirmation = $true
		$Script:AutoCheckUpdates = $true
		$Script:UpdateCheckFrequency = 'Startup'
		$Script:UpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
		$Script:IncludePrereleaseUpdates = $false
		$Script:DebugLoggingEnabled = $false
		$Script:LogFileDirectory = ''
		$Script:DefaultStartupMode = 'Safe'
		$Script:AppsPackageSourcePreference = 'auto'
	}
	if (Get-Command -Name 'Set-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Set-BaselineDebugLogging -Enabled ([bool]$Script:DebugLoggingEnabled) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ApplyDebugLoggingPreference' }
	}
	if (Get-Command -Name 'Set-GuiPerfTraceState' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Set-GuiPerfTraceState -Enabled ([bool]$Script:DebugLoggingEnabled) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ApplyPerfTraceState' }
	}
	try
	{
		LogDebug ('GUI preferences loaded. RunInitialActions={0}; CheckWinGet={1}; WinGetFrequency="{2}"; CheckChocolatey={3}; ChocolateyFrequency="{4}"; DebugLogging={5}; LogLevel="{6}"; AppsSource="{7}"; RestoreLastSession={8}; AutoScanOnLaunch={9}' -f [bool]$Script:StartupRunInitialActions, [bool]$Script:StartupCheckWinGet, [string]$Script:StartupWinGetCheckFrequency, [bool]$Script:StartupCheckChocolatey, [string]$Script:StartupChocolateyCheckFrequency, [bool]$Script:DebugLoggingEnabled, [string]$Script:LogLevel, [string]$Script:AppsPackageSourcePreference, [bool]$Script:RestoreLastSession, [bool]$Script:AutoScanOnLaunch)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.LoadGuiPreferences.LogDebug'
	}
	$Script:AdvancedMode = [string]::Equals([string]$Script:DefaultStartupMode, 'Expert', [System.StringComparison]::OrdinalIgnoreCase)
	$Script:SafeMode = -not [bool]$Script:AdvancedMode

	# Auto-detect language from system UI culture. Session restore may override this.
	$Script:SelectedLanguage = $null
	$cultureToFileMap = @{ 'zh-cn' = 'zh-Hans'; 'zh-sg' = 'zh-Hans'; 'zh-tw' = 'zh-Hant'; 'zh-hk' = 'zh-Hant'; 'zh-mo' = 'zh-Hant' }
	$uiCultureLower = $PSUICulture.ToLower()
	$autoLangCandidates = @()
	if ($cultureToFileMap.ContainsKey($uiCultureLower)) { $autoLangCandidates += $cultureToFileMap[$uiCultureLower] }
	$autoLangCandidates += @($uiCultureLower, ($PSUICulture -split '-')[0].ToLower())
	$locDirInit = $Script:GuiLocalizationDirectoryPath
	foreach ($candidate in $autoLangCandidates)
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$locDirInit))
		{
			try
			{
				$null = Resolve-BaselineLocalizationFile -BaseDirectory $locDirInit -FileName "$candidate.json"
				$Script:SelectedLanguage = $candidate
				break
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'WindowSetup.ResolveLocalizationCandidate'; $null = $_ }
		}
	}
	if (-not $Script:SelectedLanguage) { $Script:SelectedLanguage = 'en' }
	Initialize-GameModeState
	if ($Script:TweakIndicesByPrimaryTab -and $Script:GamingCrossTabFunctions -and $Script:GamingCrossTabFunctions.Count -gt 0)
	{
		if (-not $Script:TweakIndicesByPrimaryTab.ContainsKey('Gaming'))
		{
			$Script:TweakIndicesByPrimaryTab['Gaming'] = [System.Collections.Generic.List[int]]::new()
		}
		$gamingIndexBucket = $Script:TweakIndicesByPrimaryTab['Gaming']
		for ($gamingIndex = 0; $gamingIndex -lt $Script:TweakManifest.Count; $gamingIndex++)
		{
			$gamingTweak = $Script:TweakManifest[$gamingIndex]
			if (-not $gamingTweak) { continue }
			$gamingFunction = [string]$gamingTweak.Function
			if ([string]::IsNullOrWhiteSpace($gamingFunction)) { continue }
			if ($Script:GamingCrossTabFunctions.Contains($gamingFunction) -and -not $gamingIndexBucket.Contains($gamingIndex))
			{
				[void]$gamingIndexBucket.Add($gamingIndex)
			}
		}
	}
	$Script:FilterUiUpdating = $false
	$Script:ExecutionSummaryRecords = @()
	$Script:ExecutionSummaryLookup = @{}
	$Script:ExecutionCurrentSummaryKey = $null
	$Script:GuiDisplayVersion = Get-BaselineDisplayVersion

		# Keep the native window title concise; version details live in Help.
		$headerTitle = $Form.Title
		try
		{
			$windowTitle = Get-UxMainWindowTitleText
			$Form.Title = $windowTitle
			if ($TitleBarText) { $TitleBarText.Text = $windowTitle }
			$headerTitle = $windowTitle
		}
		catch { Write-GuiRuntimeWarning -Context 'WindowTitle' -Message $_.Exception.Message }
		$TitleText.Text = $headerTitle
