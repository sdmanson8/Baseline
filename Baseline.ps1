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
	.\Baseline.ps1

	.EXAMPLE Run the script by specifying the module functions as an argument (headless)
	.\Baseline.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal"

	.EXAMPLE Run a preset non-interactively
	.\Baseline.ps1 -Preset Advanced

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
	$Functions,

	[Parameter(Mandatory = $false)]
	[string]
	$Preset
)

Clear-Host

$Script:BootstrapSplash = $null

#region InitialActions
$Script:RepoRoot = $PSScriptRoot
$Script:ModuleRoot = Join-Path $Script:RepoRoot 'Module'
$Script:ModuleRootExists = Test-Path -LiteralPath $Script:ModuleRoot -PathType Container
$Script:RegionsRoot = Join-Path $Script:ModuleRoot 'Regions'

$RequiredFiles = @(
    (Join-Path (Join-Path $Script:RepoRoot 'Localizations') 'Baseline.psd1')
)

$RequiredFiles += if ($Script:ModuleRootExists)
{
	@(
		(Join-Path $Script:ModuleRoot 'SharedHelpers.psm1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'ErrorHandling.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Registry.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Environment.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Manifest.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'PackageManagement.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'AdvancedStartup.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Taskbar.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'SystemMaintenance.Helpers.ps1')
		(Join-Path $Script:ModuleRoot 'Baseline.psm1')
		(Join-Path $Script:ModuleRoot 'Baseline.psd1')
		(Join-Path $Script:RegionsRoot 'GUI.psm1')
		(Join-Path $Script:ModuleRoot 'Logging.psm1')
		(Join-Path $Script:ModuleRoot 'GUICommon.psm1')
		(Join-Path $Script:ModuleRoot 'GUIExecution.psm1')
	)
}
else
{
	@()
}

$MissingRequired = $RequiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) }
$RegionFiles = if ($Script:ModuleRootExists)
{
	Get-ChildItem -LiteralPath $Script:RegionsRoot -Filter '*.psm1' -File -ErrorAction SilentlyContinue
}
else
{
	@()
}

if (-not $Script:ModuleRootExists -or $MissingRequired -or -not $RegionFiles) {
    Write-Host ""
    Write-Warning "There are missing files in the script folder. Please re-download the archive."
    Write-Host ""

    if (-not $Script:ModuleRootExists)
    {
        Write-Warning ("Could not find the module folder: '{0}'" -f (Join-Path $Script:RepoRoot 'Module'))
    }

    if ($MissingRequired) {
        Write-Warning "Missing required files:"
        $MissingRequired | ForEach-Object { Write-Warning "  $_" }
    }

    if (-not $RegionFiles) {
        Write-Warning "No region files found in: $Script:RegionsRoot"
    }

    exit
}

Import-Module -Name (Join-Path $Script:ModuleRoot 'SharedHelpers.psm1') -Force -ErrorAction Stop
$Script:BootstrapSplash = Show-BootstrapLoadingSplash
$osName = (Get-OSInfo).OSName
$Host.UI.RawUI.WindowTitle = "Baseline | Windows Utility for $osName"
$displayVersion = Get-BaselineDisplayVersion
if (-not [string]::IsNullOrWhiteSpace([string]$displayVersion))
{
	$Host.UI.RawUI.WindowTitle = "$($Host.UI.RawUI.WindowTitle) $displayVersion"
}

function Get-ErrorDetailText
{
	param(
		[Parameter(Mandatory = $true)]
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)

	$detailParts = @()
	if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.Exception.Message))
	{
		$detailParts += $ErrorRecord.Exception.Message
	}

	if ($ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage))
	{
		$detailParts += $ErrorRecord.InvocationInfo.PositionMessage.Trim()
	}

	if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace))
	{
		$detailParts += "Stack:`n$($ErrorRecord.ScriptStackTrace.Trim())"
	}

	return ($detailParts -join "`n`n")
}

function ConvertTo-HeadlessPresetName
{
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$PresetName
	)

	$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Safe' } else { [string]$PresetName }
	$normalizedPresetName = [System.IO.Path]::GetFileNameWithoutExtension($normalizedPresetName.Trim())

	switch -Regex ($normalizedPresetName)
	{
		'^\s*minimal\s*$'               { return 'Minimal' }
		'^\s*balanced\s*$'              { return 'Balanced' }
		'^\s*safe\s*$'                  { return 'Safe' }
		'^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
		default                         { return $normalizedPresetName }
	}
}

function Get-HeadlessPresetCommandList
{
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$PresetName
	)

	$presetDirectory = Join-Path -Path $Script:ModuleRoot -ChildPath 'Data\Presets'
	if (-not (Test-Path -LiteralPath $presetDirectory -PathType Container))
	{
		throw "Preset directory was not found: $presetDirectory"
	}

	$presetPath = $null
	if (Test-Path -LiteralPath $PresetName -PathType Leaf)
	{
		$presetPath = (Resolve-Path -LiteralPath $PresetName -ErrorAction Stop).Path
	}
	else
	{
		$normalizedPresetName = ConvertTo-HeadlessPresetName -PresetName $PresetName
		foreach ($extension in @('.json', '.txt'))
		{
			$candidatePath = Join-Path -Path $presetDirectory -ChildPath ("{0}{1}" -f $normalizedPresetName, $extension)
			if (Test-Path -LiteralPath $candidatePath -PathType Leaf)
			{
				$presetPath = $candidatePath
				break
			}
		}
	}

	if ([string]::IsNullOrWhiteSpace([string]$presetPath))
	{
		throw "Preset file '$PresetName.json' or '$PresetName.txt' was not found under Module\Data\Presets."
	}

	$commandList = [System.Collections.Generic.List[string]]::new()
	$commandIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)

	if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase))
	{
		$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
		if ($presetData -and $presetData.PSObject.Properties['Entries'])
		{
			$rawEntries = @($presetData.Entries)
		}
		elseif ($presetData -is [System.Collections.IEnumerable] -and -not ($presetData -is [string]))
		{
			$rawEntries = @($presetData)
		}
		else
		{
			$rawEntries = @()
		}
	}
	else
	{
		$rawEntries = [System.IO.File]::ReadAllLines($presetPath)
	}

	foreach ($rawEntry in $rawEntries)
	{
		$commandLine = [string]$rawEntry
		if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

		$trimmed = $commandLine.Trim()
		if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

		$functionName = ($trimmed -split '\s+', 2)[0].Trim()
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		if ($commandIndex.ContainsKey($functionName))
		{
			$commandList[$commandIndex[$functionName]] = $trimmed
		}
		else
		{
			$commandIndex[$functionName] = $commandList.Count
			[void]$commandList.Add($trimmed)
		}
	}

	return ,$commandList.ToArray()
}

if ([string]::IsNullOrWhiteSpace($Preset) -and -not $Functions)
{
	$Preset = $env:BASELINE_PRESET
}

if ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive)
{
	try {
		$Script:BootstrapSplash.Dispatcher.Invoke([System.Action]{
			$Script:BootstrapSplash.Window.Title = $Host.UI.RawUI.WindowTitle
		})
	} catch { $null = $_ }
}

Remove-Module -Name Baseline -Force -ErrorAction Ignore
try
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture $PSUICulture -BaseDirectory $Script:RepoRoot\Localizations -FileName Baseline -ErrorAction Stop
}
catch
{
	Import-LocalizedData -BindingVariable Global:Localization -UICulture en-US -BaseDirectory $Script:RepoRoot\Localizations -FileName Baseline
}

# Checking whether script is the correct PowerShell version
try
{
	Import-Module -Name (Join-Path $Script:ModuleRoot 'Baseline.psd1') -Force -ErrorAction Stop
}
catch [System.InvalidOperationException]
{
	Write-Warning -Message $Localization.UnsupportedPowerShell
	exit
}

# Preset mode expands the requested preset into the same command list used by
# the headless path so the bootstrap can stay non-interactive.
if ($Preset)
{
	if ($Functions)
	{
		throw 'Specify either -Preset or -Functions, not both.'
	}

	$Functions = @(Get-HeadlessPresetCommandList -PresetName $Preset)
	if (-not $Functions -or $Functions.Count -eq 0)
	{
		throw "Preset '$Preset' did not resolve to any commands."
	}
}

# Headless mode: run specific functions or a preset from the command line
if ($Functions)
{
	$Global:BaselineHeadlessCommands = @($Functions)
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
Hide-ConsoleWindow

# Show a WPF loading splash while startup checks run
$Script:LoadingSplash = $Script:BootstrapSplash
$Global:LoadingSplash = $Script:LoadingSplash

# Run mandatory startup checks (no menu prompt)
try
{
	InitialActions
}
catch
{
	$startupError = $_
	$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
	$Script:LoadingSplash = $null
	$Global:LoadingSplash = $null
	Show-ConsoleWindow

	$startupErrorMessage = Get-ErrorDetailText -ErrorRecord $startupError
	LogError "GUI startup failed before the main window opened: $startupErrorMessage"
	Write-Error -ErrorRecord $startupError

	try
	{
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		[System.Windows.MessageBox]::Show(
			"Baseline failed to open the GUI.`n`n$startupErrorMessage`n`nLog file:`n$Global:LogFilePath",
			'Baseline Startup Error',
			[System.Windows.MessageBoxButton]::OK,
			[System.Windows.MessageBoxImage]::Error
		) | Out-Null
	}
	catch
	{
		Write-Warning "Baseline failed to open the GUI. See the log file: $Global:LogFilePath"
	}

	throw
}
#endregion InitialActions

#region GUI
# Ensure GUI module and dependencies are imported
try
{
	Import-Module -Name (Join-Path $Script:ModuleRoot 'Logging.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUICommon.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUIExecution.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:RegionsRoot 'GUI.psm1') -Force -ErrorAction Stop
}
catch
{
	$importError = $_
	if ($Script:LoadingSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
		$Script:LoadingSplash = $null
		$Global:LoadingSplash = $null
	}
	Show-ConsoleWindow
	LogError "Failed to import GUI modules: $($importError.Exception.Message)"
	throw
}

# Launch the WPF tweak-selection GUI — replaces the old preset file
try
{
	Show-TweakGUI
	if ($Script:LoadingSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
		$Script:LoadingSplash = $null
		$Global:LoadingSplash = $null
	}
}
catch
{
	$guiError = $_
	if ($Script:LoadingSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
		$Script:LoadingSplash = $null
		$Global:LoadingSplash = $null
	}
	Show-ConsoleWindow

	$guiErrorMessage = Get-ErrorDetailText -ErrorRecord $guiError
	LogError "GUI construction failed: $guiErrorMessage"
	Write-Error -ErrorRecord $guiError

	try
	{
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		[System.Windows.MessageBox]::Show(
			"Baseline failed while opening the GUI.`n`n$guiErrorMessage`n`nLog file:`n$Global:LogFilePath",
			'Baseline GUI Error',
			[System.Windows.MessageBoxButton]::OK,
			[System.Windows.MessageBoxImage]::Error
		) | Out-Null
	}
	catch
	{
		Write-Warning "Baseline failed while opening the GUI. See the log file: $Global:LogFilePath"
	}

	throw
}
#endregion GUI
