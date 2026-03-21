<#
	.SYNOPSIS
	WPF GUI for Windows 10 & Windows 11 fine-tuning and automating the routine tasks

    .VERSION
	2.0.0

	.DATE
	17.03.2026 - initial version
	21.03.2026 - Added GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

	.DESCRIPTION
	Launches a tabbed WPF GUI showing every tweak as a checkbox or dropdown.
	Checked = Enable/Show, Unchecked = Disable/Hide, Defaults match the old preset.
	Click "Run Tweaks" to apply, or "Reset to Windows Defaults" to undo.

	.EXAMPLE Run the GUI
	.\Win10_11Util.ps1

	.EXAMPLE Run the script by specifying the module functions as an argument (headless)
	.\Win10_11Util.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal"

	.NOTES
	Supported Windows 10 versions
	Version: 1607+
	Editions: Home/Pro/Enterprise

	Supported Windows 11 versions
	Version: 23H2+
	Editions: Home/Pro/Enterprise

	.NOTES
	The below sources were used, and edited for my purposes:
	https://github.com/Disassembler0/Win10-Initial-Setup-Script
	https://gist.github.com/ricardojba/ecdfe30dadbdab6c514a530bc5d51ef6
	https://github.com/farag2/Sophia-Script-for-Windows
	https://github.com/zoicware/RemoveWindowsAI/tree/main
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param
(
	[Parameter(Mandatory = $false)]
	[string[]]
	$Functions
)

Clear-Host

function Show-BootstrapLoadingSplash
{
	[CmdletBinding()]
	[OutputType([System.Object])]
	param ()

	try
	{
		Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop

		# Run the splash window in a separate STA thread so it has its own
		# WPF dispatcher message loop and stays alive/responsive while the
		# main thread is busy loading modules and running startup checks.
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
	Title="WinUtil Script"
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
			<TextBlock Text="WinUtil Script" FontSize="22" FontWeight="Bold"
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
				$splash = [Windows.Markup.XamlReader]::Load(
					(New-Object System.Xml.XmlNodeReader $xaml)
				)

				$syncHash.Window     = $splash
				$syncHash.Dispatcher = $splash.Dispatcher

				$splash.Add_ContentRendered({ $syncHash.IsReady = $true })
				$splash.Add_Closed({
					$syncHash.IsAlive = $false
					$splash.Dispatcher.InvokeShutdown()
				})

				# ShowDialog() runs the dispatcher message loop on this thread,
				# keeping the splash window alive and responsive.
				$splash.ShowDialog() | Out-Null
			}
			catch
			{
				$syncHash.IsReady = $true
				$syncHash.IsAlive = $false
			}
		})

		$asyncResult = $ps.BeginInvoke()

		# Wait for the splash window to finish rendering (with timeout)
		$deadline = [datetime]::Now.AddSeconds(10)
		while (-not $syncHash.IsReady -and [datetime]::Now -lt $deadline)
		{
			Start-Sleep -Milliseconds 50
		}

		if (-not $syncHash.IsAlive) { return $null }

		# Stash cleanup handles inside the hashtable
		$syncHash._PowerShell   = $ps
		$syncHash._AsyncResult  = $asyncResult
		$syncHash._Runspace     = $runspace

		return $syncHash
	}
	catch
	{
		return $null
	}
}

$Script:BootstrapSplash = Show-BootstrapLoadingSplash

#region InitialActions
$RequiredFiles = @(
    "$PSScriptRoot\Localizations\Win10_11Util.psd1",
    "$PSScriptRoot\Module\Helpers.psm1",
    "$PSScriptRoot\Module\Win10_11Util.psm1",
    "$PSScriptRoot\Manifest\Win10_11Util.psd1"
)

$MissingRequired = $RequiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) }
$RegionFiles = Get-ChildItem -Path "$PSScriptRoot\Module\Regions" -Filter '*.psm1' -File -ErrorAction SilentlyContinue

if ($MissingRequired -or -not $RegionFiles) {
    Write-Host ""
    Write-Warning "There are missing files in the script folder. Please re-download the archive."
    Write-Host ""

    if ($MissingRequired) {
        Write-Warning "Missing required files:"
        $MissingRequired | ForEach-Object { Write-Warning "  $_" }
    }

    if (-not $RegionFiles) {
        Write-Warning "No region files found in: $PSScriptRoot\Module\Regions"
    }

    exit
}

Import-Module -Name $PSScriptRoot\Module\Helpers.psm1 -Force -ErrorAction Stop
$osName = (Get-OSInfo).OSName
$Host.UI.RawUI.WindowTitle = "WinUtil Script for $osName"

if ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive)
{
	try {
		$Script:BootstrapSplash.Dispatcher.Invoke([Action]{
			$Script:BootstrapSplash.Window.Title = "WinUtil Script for $osName"
		})
	} catch { $null = $_ }
}

Remove-Module -Name Win10_11Util -Force -ErrorAction Ignore
try
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture $PSUICulture -BaseDirectory $PSScriptRoot\Localizations -FileName Win10_11Util -ErrorAction Stop
}
catch
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture en-US -BaseDirectory $PSScriptRoot\Localizations -FileName Win10_11Util
}

# Checking whether script is the correct PowerShell version
try
{
	Import-Module -Name $PSScriptRoot\Manifest\Win10_11Util.psd1 -Force -ErrorAction Stop
}
catch [System.InvalidOperationException]
{
	Write-Warning -Message $Localization.UnsupportedPowerShell
	exit
}

# Headless mode: run specific functions from the command line
if ($Functions)
{
	Invoke-Command -ScriptBlock {InitialActions}

	foreach ($Function in $Functions)
	{
		Invoke-Expression -Command $Function
	}

	Invoke-Command -ScriptBlock {PostActions; Errors}
	exit
}

# Restart Script in PowerShell 5.1 if running PowerShell 7
Restart-Script -ScriptPath $MyInvocation.MyCommand.Path

# Signal to InitialActions/PostActions that we are running in GUI mode.
# Region modules check this flag to skip the "Press Enter to close" prompt
# and suppress PostActions from running during startup.
$Global:GUIMode = $true

# Hide the console window before anything else runs — the splash is the only
# visible window during startup. The console reappears only when Run Tweaks fires.
# Use GetConsoleWindow() (kernel32) to get the actual console HWND — using
# Process.MainWindowHandle is wrong here because when the console starts hidden
# Windows returns the splash window's handle instead, causing ShowWindowAsync to
# hide the splash rather than the console.
$_hwndType = @'
using System;
using System.Runtime.InteropServices;
public static class ConsoleHelper {
	[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
	[DllImport("user32.dll")]   public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@
if (-not ('ConsoleHelper' -as [type])) { Add-Type -TypeDefinition $_hwndType }
$_consoleHwnd = [ConsoleHelper]::GetConsoleWindow()
if ($_consoleHwnd -ne [IntPtr]::Zero)
{
	[ConsoleHelper]::ShowWindowAsync($_consoleHwnd, 0) | Out-Null
}
Remove-Variable _consoleHwnd -ErrorAction SilentlyContinue

# Show a WPF loading splash while startup checks run
# Reuse the bootstrap splash (which runs in its own thread) if available
$Script:LoadingSplash = if ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive) {
	$Script:BootstrapSplash
}
else {
	Show-LoadingSplash
}
$Global:LoadingSplash = $Script:LoadingSplash

# Run mandatory startup checks (no menu prompt)
InitialActions
$Global:LoadingSplash = $null
#endregion InitialActions

#region GUI
# Launch the WPF tweak-selection GUI — replaces the old preset file
Show-TweakGUI -StartupSplash $Script:LoadingSplash
#endregion GUI
