# Shared helper slice for Baseline.

function Initialize-ForegroundWindowInterop
{
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
	Initialize-ConsoleWindowInterop
	return [WinAPI.ConsoleWindow]::GetConsoleWindow()
}

function Hide-ConsoleWindow
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 0) | Out-Null
	}
}

function Show-ConsoleWindow
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	$hwnd = Get-ConsoleHandle
	if ($hwnd -ne [System.IntPtr]::Zero)
	{
		[WinAPI.ConsoleWindow]::ShowWindow($hwnd, 9) | Out-Null
	}
}

function Initialize-WpfWindowForeground
{
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

	$activationPending = $true
	$bringWindowToFront = {
		if (-not $activationPending)
		{
			return
		}

		$activationPending = $false

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
						[WinAPI.ForegroundWindow]::ShowWindowAsync($interopHelper.Handle, 9) | Out-Null
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

	[pscustomobject]@{
		IsWindows11      = ([int]$CurrentBuild -ge 22000)
		IsWindowsServer  = $IsWindowsServer
		CurrentBuild     = [int]$CurrentBuild
		UBR              = $UBR
		DisplayVersion   = $DisplayVersion
		ProductName      = $ProductName
		InstallationType = $InstallationType
	}
}

function Get-OSInfo
{
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
	[CmdletBinding()]
	[OutputType([System.Object])]
	param ()

	try
	{
		Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

		$syncHash = [hashtable]::Synchronized(@{
			Window     = $null
			Dispatcher = $null
			IsReady    = $false
			IsAlive    = $true
		})

		$runspace = [runspacefactory]::CreateRunspace()
		$runspace.ApartmentState = 'STA'
		$runspace.ThreadOptions  = 'ReuseThread'
		$runspace.Open()
		$runspace.SessionStateProxy.SetVariable('syncHash', $syncHash)

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
	ResizeMode="CanMinimize"
	WindowStartupLocation="CenterScreen"
	Background="#1E1E2E"
	Foreground="#CDD6F4"
	FontFamily="Segoe UI"
	ShowInTaskbar="True"
	Topmost="True">
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
			<TextBlock Text="Baseline" FontSize="22" FontWeight="Bold"
				Foreground="#CDD6F4" HorizontalAlignment="Center" Margin="0,0,0,6"/>
			<TextBlock Text="Windows Optimization &amp; Hardening"
				FontSize="13" Foreground="#A6ADC8"
				HorizontalAlignment="Center" Margin="0,0,0,24"/>
			<TextBlock Name="StatusText" Text="Please wait..."
				FontSize="14" Foreground="#89B4FA"
				HorizontalAlignment="Center"/>
		</StackPanel>
		<Border Grid.Row="1" Background="#181825" Padding="12,8">
			<TextBlock FontSize="11" Foreground="#6C7086" HorizontalAlignment="Center"
				Text="This window will close automatically when ready."/>
		</Border>
	</Grid>
</Window>
"@
				$splash = [System.Windows.Markup.XamlReader]::Load(
					(New-Object System.Xml.XmlNodeReader $xaml)
				)

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

		if (-not $syncHash.IsAlive) { return $null }

		$syncHash._PowerShell  = $ps
		$syncHash._AsyncResult = $asyncResult
		$syncHash._Runspace    = $runspace

		return $syncHash
	}
	catch
	{
		return $null
	}
}

function Close-LoadingSplashWindow
{
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
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$ScriptPath
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

		$argList = @(
			'-ExecutionPolicy', 'Bypass',
			'-NoProfile',
			'-File', $ScriptPath
		)

		if ($Functions)
		{
			$argList += '-Functions'
			$argList += $Functions
		}

		Start-Process -FilePath $powershell51 -ArgumentList $argList -WindowStyle Hidden
		[Environment]::Exit(0)
	}
}

function Get-BaselineDisplayVersion
{
	$moduleManifestPath = Join-Path $Script:SharedHelpersModuleRoot 'Baseline.psd1'
	if (-not (Test-Path -LiteralPath $moduleManifestPath))
	{
		return $null
	}

	try
	{
		$moduleManifest = Import-PowerShellDataFile -Path $moduleManifestPath -ErrorAction Stop
		if ($moduleManifest.ContainsKey('ModuleVersion') -and -not [string]::IsNullOrWhiteSpace([string]$moduleManifest.ModuleVersion))
		{
			return "v{0}" -f [string]$moduleManifest.ModuleVersion
		}
	}
	catch { $null = $_ }

	return $null
}

function Stop-Foreground
{
	Stop-Process -Name "explorer" -Force | Out-Null
}
