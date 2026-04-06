# Shared helper slice for Baseline.

function Initialize-ForegroundWindowInterop
{
	<# .SYNOPSIS Loads the WinAPI.ForegroundWindow P/Invoke type definition. #>
	if (-not ("WinAPI.ForegroundWindow" -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class ForegroundWindow
	{
		[DllImport("user32.dll")]
		public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetForegroundWindow(IntPtr hWnd);
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

function Initialize-ConsoleWindowInterop
{
	<# .SYNOPSIS Loads the WinAPI.ConsoleWindow P/Invoke type definition. #>
	if (-not ("WinAPI.ConsoleWindow" -as [type]))
	{
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
	public static class ConsoleWindow
	{
		[DllImport("kernel32.dll")]
		public static extern IntPtr GetConsoleWindow();

		[DllImport("user32.dll")]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
	}
}
"@ -ErrorAction Stop | Out-Null
	}
}

function Get-ConsoleHandle
{
	<# .SYNOPSIS Returns the console window handle via kernel32 P/Invoke. #>
	Initialize-ConsoleWindowInterop
	return [WinAPI.ConsoleWindow]::GetConsoleWindow()
}

function Hide-ConsoleWindow
{
	<# .SYNOPSIS Hides the console window using ShowWindow(SW_HIDE). #>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 0 <# SW_HIDE #>) | Out-Null
	}
}

function Show-ConsoleWindow
{
	<# .SYNOPSIS Shows and restores the console window using ShowWindow(SW_RESTORE). #>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 9 <# SW_RESTORE #>) | Out-Null
	}
}

function Test-InteractiveHost
{
	<# .SYNOPSIS Tests whether the current PowerShell host supports interactive UI. #>
	try
	{
		if ($null -eq $Host -or $null -eq $Host.UI)
		{
			return $false
		}

		$null = $Host.UI.RawUI
		return $true
	}
	catch
	{
		return $false
	}
}

function Initialize-WpfWindowForeground
{
	<# .SYNOPSIS Configures a WPF window to activate and bring itself to foreground. #>
	param
	(
		[Parameter(Mandatory = $true)]
		$Window
	)

	try
	{
		$Window.ShowActivated = $true
	}
	catch
	{
		# Ignore if the supplied object is not a WPF Window.
	}

	$activationPending = [ref]$true
	$bringWindowToFront = {
		if (-not $activationPending.Value)
		{
			return
		}

		$activationPending.Value = $false

		try
		{
			$activateWindowAction = [System.Action]{
				try
				{
					Initialize-ForegroundWindowInterop

					if ($Window.WindowState -eq [System.Windows.WindowState]::Minimized)
					{
						$Window.WindowState = [System.Windows.WindowState]::Normal
					}

					$interopHelper = New-Object -TypeName System.Windows.Interop.WindowInteropHelper -ArgumentList $Window
					if ($interopHelper.Handle -ne [IntPtr]::Zero)
					{
						[WinAPI.ForegroundWindow]::ShowWindowAsync($interopHelper.Handle, 9 <# SW_RESTORE #>) | Out-Null
						[WinAPI.ForegroundWindow]::SetForegroundWindow($interopHelper.Handle) | Out-Null
					}

					$originalTopmost = $Window.Topmost
					$Window.Topmost = $true
					$Window.Activate() | Out-Null
					$Window.Focus() | Out-Null

					$resetTopmostAction = [System.Action]{
						$Window.Topmost = $originalTopmost
					}
					$Window.Dispatcher.BeginInvoke($resetTopmostAction, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
				}
				catch
				{
					try
					{
						$Window.WindowState = [System.Windows.WindowState]::Normal
						$Window.Activate() | Out-Null
						$Window.Focus() | Out-Null
					}
					catch
					{
						# Ignore foreground activation failures and allow the dialog to continue opening normally.
					}
				}
			}

			$Window.Dispatcher.BeginInvoke($activateWindowAction, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
		}
		catch
		{
			try
			{
				$Window.WindowState = [System.Windows.WindowState]::Normal
				$Window.Activate() | Out-Null
				$Window.Focus() | Out-Null
			}
			catch
			{
				# Ignore foreground activation failures and allow the dialog to continue opening normally.
			}
		}
	}

	$Window.Add_Loaded($bringWindowToFront)
	$Window.Add_SourceInitialized($bringWindowToFront)
	$Window.Add_ContentRendered($bringWindowToFront)
	$Window.Add_StateChanged({
		if ($activationPending -and ($Window.WindowState -eq [System.Windows.WindowState]::Minimized))
		{
			$bringWindowToFront.Invoke()
		}
	})
}

function Get-WindowsVersionData
{
	<# .SYNOPSIS Retrieves Windows version details from the registry (build, UBR, display version). #>
	$CurrentVersion = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
	$CurrentBuild = [string]$CurrentVersion.CurrentBuild
	$DisplayVersion = [string]$CurrentVersion.DisplayVersion
	$ProductName = [string]$CurrentVersion.ProductName
	$InstallationType = [string]$CurrentVersion.InstallationType
	$UBR = 0
	$IsWindowsServer = $false

	if ([string]::IsNullOrWhiteSpace($CurrentBuild))
	{
		$CurrentBuild = [string]$CurrentVersion.CurrentBuildNumber
	}

	if ([string]::IsNullOrWhiteSpace($DisplayVersion))
	{
		$DisplayVersion = [string]$CurrentVersion.ReleaseId
	}

	if ($null -ne $CurrentVersion.UBR)
	{
		$UBR = [int]$CurrentVersion.UBR
	}

	if (-not [string]::IsNullOrWhiteSpace($InstallationType))
	{
		$IsWindowsServer = $InstallationType -match "Server"
	}
	elseif (-not [string]::IsNullOrWhiteSpace($ProductName))
	{
		$IsWindowsServer = $ProductName -match "Server"
	}

	$buildNumber = 0
	if (-not [int]::TryParse([string]$CurrentBuild, [ref]$buildNumber)) { $buildNumber = 0 }

	[pscustomobject]@{
		IsWindows11      = ($buildNumber -ge 22000)
		IsWindowsServer  = $IsWindowsServer
		CurrentBuild     = $buildNumber
		UBR              = $UBR
		DisplayVersion   = $DisplayVersion
		ProductName      = $ProductName
		InstallationType = $InstallationType
	}
}

function Get-OSInfo
{
	<# .SYNOPSIS Returns a summary object with OS name, build, UBR, and version data. #>
	$VersionData = Get-WindowsVersionData
	$OSName = if ($VersionData.IsWindowsServer)
	{
		if ([string]::IsNullOrWhiteSpace($VersionData.ProductName))
		{
			"Windows Server"
		}
		else
		{
			$VersionData.ProductName
		}
	}
	elseif ($VersionData.IsWindows11)
	{
		"Windows 11"
	}
	else
	{
		"Windows 10"
	}

	[pscustomobject]@{
		IsWindows11      = $VersionData.IsWindows11
		IsWindowsServer  = $VersionData.IsWindowsServer
		OSName           = $OSName
		CurrentBuild     = $VersionData.CurrentBuild
		UBR              = $VersionData.UBR
		DisplayVersion   = $VersionData.DisplayVersion
		ProductName      = $VersionData.ProductName
		InstallationType = $VersionData.InstallationType
	}
}

function ConvertTo-WindowsDisplayVersionComparable
{
	<# .SYNOPSIS Converts a display version string (e.g. 23H2) to a sortable integer. #>
	param
	(
		[string]
		$DisplayVersion
	)

	if ([string]::IsNullOrWhiteSpace($DisplayVersion))
	{
		return $null
	}

	if ($DisplayVersion -match '^(?<Year>\d{2})H(?<Half>\d)$')
	{
		return ([int]$Matches.Year * 10) + [int]$Matches.Half
	}

	return $null
}

function Test-Windows11FeatureBranchSupport
{
	<# .SYNOPSIS Tests whether Windows 11 meets the feature branch threshold. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[hashtable[]]
		$Thresholds
	)

	$VersionData = Get-WindowsVersionData
	if (-not $VersionData.IsWindows11)
	{
		return $false
	}

	$ParsedThresholds = $Thresholds | ForEach-Object {
		[pscustomobject]@{
			DisplayVersion = [string]$_.DisplayVersion
			Build          = [int]$_.Build
			UBR            = if ($null -ne $_.UBR) { [int]$_.UBR } else { 0 }
		}
	} | Sort-Object Build, UBR

	if (-not $ParsedThresholds)
	{
		return $false
	}

	$ApplicableThreshold = $ParsedThresholds | Where-Object -FilterScript {
		$VersionData.CurrentBuild -ge $_.Build
	} | Select-Object -Last 1

	if (-not $ApplicableThreshold)
	{
		return $false
	}

	if ($VersionData.CurrentBuild -gt $ApplicableThreshold.Build)
	{
		return $true
	}

	return ($VersionData.UBR -ge $ApplicableThreshold.UBR)
}

function Show-BootstrapLoadingSplash
{
	<# .SYNOPSIS Displays a loading splash window in a background runspace. #>
	[CmdletBinding()]
	[OutputType([System.Object])]
	param ()

	try
	{
		Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

		# Check saved session for theme preference
		$useLightTheme = $false
		try
		{
			$sessionPath = Join-Path $env:LOCALAPPDATA 'Baseline\Profiles\Baseline-last-session.json'
			if (Test-Path -LiteralPath $sessionPath)
			{
				$sessionJson = Get-Content -LiteralPath $sessionPath -Raw -ErrorAction Stop | ConvertFrom-Json
				if ($sessionJson.State -and $sessionJson.State.Theme -eq 'Light') { $useLightTheme = $true }
			}
		}
		catch { }

		$syncHash = [hashtable]::Synchronized(@{
			Window     = $null
			Dispatcher = $null
			IsReady    = $false
			IsAlive    = $true
		})

		# Theme colors
		if ($useLightTheme)
		{
			$splashBg = '#E4E8F0'; $splashBorder = '#A7B0C0'; $splashFg = '#1A1C2E'
			$splashSub = '#31384A'; $splashAccent = '#1550AA'; $splashFooterBg = '#D6DBE5'
			$splashMuted = '#646C7F'; $splashBtnFg = '#31384A'; $splashDarkMode = $false
		}
		else
		{
			$splashBg = '#1E1E2E'; $splashBorder = '#333346'; $splashFg = '#CDD6F4'
			$splashSub = '#A6ADC8'; $splashAccent = '#89B4FA'; $splashFooterBg = '#181825'
			$splashMuted = '#6C7086'; $splashBtnFg = '#A6ADC8'; $splashDarkMode = $true
		}

		$runspace = [runspacefactory]::CreateRunspace()
		$runspace.ApartmentState = 'STA'
		$runspace.ThreadOptions  = 'ReuseThread'
		$runspace.Open()
		$runspace.SessionStateProxy.SetVariable('syncHash', $syncHash)
		$runspace.SessionStateProxy.SetVariable('splashBg', $splashBg)
		$runspace.SessionStateProxy.SetVariable('splashBorder', $splashBorder)
		$runspace.SessionStateProxy.SetVariable('splashFg', $splashFg)
		$runspace.SessionStateProxy.SetVariable('splashSub', $splashSub)
		$runspace.SessionStateProxy.SetVariable('splashAccent', $splashAccent)
		$runspace.SessionStateProxy.SetVariable('splashFooterBg', $splashFooterBg)
		$runspace.SessionStateProxy.SetVariable('splashMuted', $splashMuted)
		$runspace.SessionStateProxy.SetVariable('splashBtnFg', $splashBtnFg)
		$runspace.SessionStateProxy.SetVariable('splashDarkMode', $splashDarkMode)

		$ps = [powershell]::Create()
		$ps.Runspace = $runspace
		[void]$ps.AddScript({
			try
			{
				Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

				[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Baseline | Windows Utility"
	Width="520" Height="260"
	ResizeMode="NoResize"
	WindowStartupLocation="CenterScreen"
	Background="Transparent"
	Foreground="$splashFg"
	FontFamily="Segoe UI"
	ShowInTaskbar="True"
	Topmost="True"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border CornerRadius="8" Background="$splashBg" BorderBrush="$splashBorder" BorderThickness="1">
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<StackPanel Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,6,6,0">
			<Button Name="BtnMinimize" Content="&#x2015;" Width="28" Height="24" FontSize="11"
				Background="Transparent" Foreground="$splashBtnFg" BorderThickness="0"
				Cursor="Hand" ToolTip="Minimize" Margin="0,0,2,0"/>
			<Button Name="BtnClose" Content="&#x2715;" Width="28" Height="24" FontSize="11"
				Background="Transparent" Foreground="$splashBtnFg" BorderThickness="0"
				Cursor="Hand" ToolTip="Close"/>
		</StackPanel>
		<StackPanel Grid.Row="1" VerticalAlignment="Center" HorizontalAlignment="Center">
			<TextBlock Text="Baseline" FontSize="22" FontWeight="Bold"
				Foreground="$splashFg" HorizontalAlignment="Center" Margin="0,0,0,6"/>
			<TextBlock Text="Windows Optimization &amp; Hardening"
				FontSize="13" Foreground="$splashSub"
				HorizontalAlignment="Center" Margin="0,0,0,24"/>
			<TextBlock Name="StatusText" Text="Please wait..."
				FontSize="14" Foreground="$splashAccent"
				HorizontalAlignment="Center"/>
		</StackPanel>
		<Border Grid.Row="2" Background="$splashFooterBg" Padding="12,8" CornerRadius="0,0,8,8">
			<TextBlock FontSize="11" Foreground="$splashMuted" HorizontalAlignment="Center"
				Text="This window will close automatically when ready."/>
		</Border>
	</Grid>
	</Border>
</Window>
"@
				$splash = [System.Windows.Markup.XamlReader]::Load(
					(New-Object System.Xml.XmlNodeReader $xaml)
				)

				# Apply Windows 11 rounded corners and dark title bar
				$splash.Add_SourceInitialized({
					try
					{
						if (-not ('WinAPI.SplashChrome' -as [type]))
						{
							Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace WinAPI { public static class SplashChrome { [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref int pvAttribute, int cbAttribute); } }
"@ -ErrorAction Stop | Out-Null
						}
						$hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($splash)).Handle
						if ($hwnd -ne [IntPtr]::Zero)
						{
							$darkMode = if ($splashDarkMode) { 1 } else { 0 }
							$immAttr = if ([Environment]::OSVersion.Version.Build -ge 18362) { 20 } else { 19 }
							[void]([WinAPI.SplashChrome]::DwmSetWindowAttribute($hwnd, $immAttr, [ref]$darkMode, 4))
							if ([Environment]::OSVersion.Version.Build -ge 22000)
							{
								$cornerPref = 2
								[void]([WinAPI.SplashChrome]::DwmSetWindowAttribute($hwnd, 33, [ref]$cornerPref, 4))
							}
						}
					}
					catch { }
				})

				# Wire up minimize/close buttons and drag-to-move
				$btnMin = $splash.FindName('BtnMinimize')
				$btnCls = $splash.FindName('BtnClose')
				if ($btnMin)
				{
					$btnMin.Add_Click({ $splash.WindowState = [System.Windows.WindowState]::Minimized })
				}
				if ($btnCls)
				{
					$btnCls.Add_Click({
						$syncHash.UserClosed = $true
						$splash.Close()
						# Terminate the entire process when user explicitly closes the splash
						[System.Environment]::Exit(0)
					})
				}
				$splash.Add_MouseLeftButtonDown({ param($s,$e) $splash.DragMove() })

				$syncHash.Window     = $splash
				$syncHash.Dispatcher = $splash.Dispatcher

				$splash.Add_ContentRendered({ $syncHash.IsReady = $true })
				$splash.Add_Closed({
					$syncHash.IsAlive = $false
					$splash.Dispatcher.InvokeShutdown()
				})

				$splash.ShowDialog() | Out-Null
			}
			catch
			{
				$syncHash.IsReady = $true
				$syncHash.IsAlive = $false
			}
		})

		$asyncResult = $ps.BeginInvoke()
		$deadline = [datetime]::Now.AddSeconds(10)
		while (-not $syncHash.IsReady -and [datetime]::Now -lt $deadline)
		{
			Start-Sleep -Milliseconds 50
		}

		if (-not $syncHash.IsAlive)
		{
			# Splash never became ready - clean up the background runspace.
			try { $ps.Stop(); $ps.Dispose() } catch {}
			try { $runspace.Close(); $runspace.Dispose() } catch {}
			return $null
		}

		$syncHash._PowerShell  = $ps
		$syncHash._AsyncResult = $asyncResult
		$syncHash._Runspace    = $runspace

		return $syncHash
	}
	catch
	{
		try { if ($ps) { $ps.Stop(); $ps.Dispose() } } catch {}
		try { if ($runspace) { $runspace.Close(); $runspace.Dispose() } } catch {}
		return $null
	}
}

function Close-LoadingSplashWindow
{
	<# .SYNOPSIS Closes a splash window and optionally disposes background resources. #>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $false)]
		[object]
		$Splash,

		[Parameter(Mandatory = $false)]
		[switch]
		$DisposeResources,

		[Parameter(Mandatory = $false)]
		[int]
		$CloseTimeoutMilliseconds = 2000
	)

	if (-not $Splash) { return $false }

	$closeRequested = $false

	try
	{
		if ($Splash -is [hashtable])
		{
			if ($Splash.IsAlive -and $Splash.Dispatcher -and (-not $Splash.Dispatcher.HasShutdownStarted))
			{
				$Splash.Dispatcher.Invoke([System.Action]{
					if ($Splash.Window)
					{
						try { $Splash.Window.Hide() } catch { $null = $_ }
						try { $Splash.Window.Close() } catch { $null = $_ }
					}
					$Splash.IsAlive = $false
				})
				$closeRequested = $true
			}
		}
		elseif ($Splash.Dispatcher -and (-not $Splash.Dispatcher.HasShutdownStarted))
		{
			$Splash.Dispatcher.Invoke([System.Action]{
				try { $Splash.Hide() } catch { $null = $_ }
				try { $Splash.Close() } catch { $null = $_ }
			})
			$closeRequested = $true
		}
	}
	catch
	{
		$null = $_
	}

	if ($DisposeResources -and $Splash -is [hashtable])
	{
		$closeDeadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max($CloseTimeoutMilliseconds, 0))
		while ($Splash.IsAlive -and [datetime]::UtcNow -lt $closeDeadline)
		{
			Start-Sleep -Milliseconds 50
		}

		if ($Splash.IsAlive -and $Splash.Dispatcher -and (-not $Splash.Dispatcher.HasShutdownStarted))
		{
			try { $Splash.Dispatcher.InvokeShutdown() } catch { $null = $_ }
		}

		try
		{
			if ($Splash._PowerShell -and $Splash._AsyncResult)
			{
				$Splash._PowerShell.EndInvoke($Splash._AsyncResult)
			}
		}
		catch
		{
			$null = $_
		}

		try { if ($Splash._PowerShell) { $Splash._PowerShell.Dispose() } } catch { $null = $_ }
		try { if ($Splash._Runspace) { $Splash._Runspace.Close(); $Splash._Runspace.Dispose() } } catch { $null = $_ }
	}

	return $closeRequested
}

function Show-Menu
{
	<# .SYNOPSIS Displays an interactive console menu with arrow key navigation. #>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[array]
		$Menu,

		[Parameter(Mandatory = $true)]
		[int]
		$Default,

		[Parameter(Mandatory = $false)]
		[switch]
		$AddSkip
	)

	$Menu = @($Menu)

	if ($Localization -and $Localization.KeyboardArrows)
	{
		$Menu += ($Localization.KeyboardArrows -f [System.Char]::ConvertFromUtf32(0x2191), [System.Char]::ConvertFromUtf32(0x2193))
	}
	else
	{
		$Menu += ("Please use the arrow keys {0} and {1} on your keyboard to select your answer" -f [System.Char]::ConvertFromUtf32(0x2191), [System.Char]::ConvertFromUtf32(0x2193))
	}

	if ($AddSkip)
	{
		$Menu += Get-LocalizedShellString -ResourceId 16956 -Fallback 'Skip'
	}

	if ($env:WT_SESSION)
	{
		[System.Console]::BufferHeight += $Menu.Count
	}

	$minY = [Console]::CursorTop
	$y = [Math]::Max([Math]::Min(($Default - 1), ($Menu.Count - 1)), 0)

	# Returns selected menu item on Enter, or $null on Escape (callers must handle $null).
	do
	{
		[Console]::CursorTop = $minY
		[Console]::CursorLeft = 0
		$i = 0

		foreach ($item in $Menu)
		{
			if ($i -ne $y)
			{
				Write-Host ('  {0}  ' -f $item)
			}
			else
			{
				Write-Host ('[ {0} ]' -f $item)
			}

			$i++
		}

		$k = [Console]::ReadKey($true)
		switch ($k.Key)
		{
			'UpArrow'
			{
				if ($y -gt 0)
				{
					$y--
				}
			}
			'DownArrow'
			{
				if ($y -lt ($Menu.Count - 1))
				{
					$y++
				}
			}
			'Enter'
			{
				return $Menu[$y]
			}
		}
	}
	while ($k.Key -notin ([ConsoleKey]::Escape, [ConsoleKey]::Enter))
}

function Get-LocalizedShellString
{
	<# .SYNOPSIS Retrieves a localized Windows shell string by resource ID. #>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[uint32]
		$ResourceId,

		[Parameter(Mandatory = $true)]
		[string]
		$Fallback,

		[Parameter(Mandatory = $false)]
		[switch]
		$StripAccelerators
	)

	$value = $null

	try
	{
		if ("WinAPI.GetStrings" -as [type])
		{
			$value = [WinAPI.GetStrings]::GetString($ResourceId)
		}
	}
	catch
	{
		$value = $null
	}

	if ([string]::IsNullOrWhiteSpace($value))
	{
		$value = $Fallback
	}

	if ($StripAccelerators -and -not [string]::IsNullOrEmpty($value))
	{
		$value = $value.Replace("&", "")
	}

	return $value
}

function Restart-Script
{
	<# .SYNOPSIS Restarts the script under Windows PowerShell 5.1 if running in PowerShell 7+. #>
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$ScriptPath,

		[string]
		$Preset,

		[string]
		$GameModeProfile,

		[string]
		$ScenarioProfile,

		[string[]]
		$Functions,

		[switch]
		$DryRun
	)
	if ($PSVersionTable.PSVersion.Major -ge 7)
	{
		$powershell51 = (Get-Command -Name powershell.exe -ErrorAction SilentlyContinue).Source

		if (-not $powershell51)
		{
			LogError "PowerShell 5.1 not found."
			[Environment]::Exit(1)
		}

		if (-not (Test-Path -LiteralPath $ScriptPath))
		{
			LogError "Script not found: $ScriptPath"
			[Environment]::Exit(1)
		}

		LogInfo "Restarting script in Windows PowerShell 5.1"

		$currentPolicy = (Get-ExecutionPolicy).ToString()
		$argList = @(
			'-ExecutionPolicy', $currentPolicy,
			'-NoProfile',
			'-File', $ScriptPath
		)

		if ($Preset)
		{
			$argList += '-Preset'
			$argList += $Preset
		}
		elseif ($GameModeProfile)
		{
			$argList += '-GameModeProfile'
			$argList += $GameModeProfile
		}
		elseif ($ScenarioProfile)
		{
			$argList += '-ScenarioProfile'
			$argList += $ScenarioProfile
		}
		elseif ($Functions)
		{
			$argList += '-Functions'
			$argList += $Functions
		}

		if ($DryRun)
		{
			$argList += '-DryRun'
		}

		Start-Process -FilePath $powershell51 -ArgumentList $argList -WindowStyle Hidden
		[Environment]::Exit(0)
	}
}

function Get-BaselineDisplayVersion
{
	<# .SYNOPSIS Reads the module version string from Baseline.psd1. #>
	param ([string]$ModuleRoot)

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$moduleManifestPath = Join-Path $resolvedRoot 'Baseline.psd1'
	if (-not (Test-Path -LiteralPath $moduleManifestPath))
	{
		return $null
	}

	try
	{
		$moduleManifest = Import-PowerShellDataFile -Path $moduleManifestPath -ErrorAction Stop
		if ($moduleManifest.ContainsKey('ModuleVersion') -and -not [string]::IsNullOrWhiteSpace([string]$moduleManifest.ModuleVersion))
		{
			$version = "v{0}" -f [string]$moduleManifest.ModuleVersion
			if ($moduleManifest.ContainsKey('PrivateData') -and $moduleManifest.PrivateData -is [hashtable] -and $moduleManifest.PrivateData.ContainsKey('Prerelease') -and -not [string]::IsNullOrWhiteSpace([string]$moduleManifest.PrivateData.Prerelease))
			{
				$version = "{0} ({1})" -f $version, [string]$moduleManifest.PrivateData.Prerelease
			}
			return $version
		}
	}
	catch { $null = $_ }

	return $null
}

function Get-TweakSkipLabel
{
	<# .SYNOPSIS Returns the current tweak or caller name for skip log labels. #>
	param (
		[System.Management.Automation.InvocationInfo]$CallerInvocation
	)

	if ($Global:CurrentTweakName) { return $Global:CurrentTweakName }
	if ($CallerInvocation -and $CallerInvocation.MyCommand) { return $CallerInvocation.MyCommand.Name }
	return "this item"
}

<#
.SYNOPSIS
Kill all explorer.exe processes to apply shell/taskbar changes.

.DESCRIPTION
Terminates explorer.exe (taskbar, desktop shell, all File Explorer windows).
The shell restarts automatically. Used during tweak execution to force
registry changes to take immediate effect.
#>
function Stop-Foreground
{
	LogInfo "Stopping explorer.exe to apply shell changes"
	Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue | Out-Null
}

<#
.SYNOPSIS
Execute a scriptblock via a UCPD-bypassed PowerShell copy with guaranteed cleanup.

.DESCRIPTION
Copies powershell.exe to a temporary name to bypass the Windows UCPD driver
which blocks certain registry writes. The temporary file is removed in a
finally block to guarantee cleanup even if the command fails.

.PARAMETER ScriptBlock
The scriptblock to execute in the temporary PowerShell process.
#>
function Invoke-UCPDBypassed
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock
	)

	$sourcePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
	$tempPath = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath

	Copy-Item -Path $sourcePath -Destination $tempPath -Force -ErrorAction Stop | Out-Null
	try
	{
		# ExecutionPolicy Bypass: required for elevated child process
	& $tempPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $ScriptBlock | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "Temporary PowerShell copy returned exit code $LASTEXITCODE"
		}
	}
	finally
	{
		Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue | Out-Null
	}
}

function Get-UCPDTemporaryPowerShellPath
{
	<# .SYNOPSIS Generates a unique temporary PowerShell executable path for UCPD bypass. #>
	param (
		[string]$SourcePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
	)

	$sourceDirectory = Split-Path -Path $SourcePath -Parent
	$sourceLeaf = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
	$uniqueName = '{0}_{1}.exe' -f $sourceLeaf, ([guid]::NewGuid().ToString('N'))
	return (Join-Path -Path $sourceDirectory -ChildPath $uniqueName)
}
