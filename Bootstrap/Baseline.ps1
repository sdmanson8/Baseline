<#
	.SYNOPSIS
	WPF GUI for Windows 10 & Windows 11 fine-tuning and automating the routine tasks

    .VERSION
    1.0.0

    .DATE
    21.03.2026 - Initial Release
    06.04.2026 - Major changes to the GUI, and added more features
    25.05.2026

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

	.DESCRIPTION
	Launches a tabbed WPF GUI showing every tweak as a checkbox or dropdown.
	Checked = Enable/Show, Unchecked = Disable/Hide, Defaults match the old preset.
	Click "Run Tweaks" to apply, or "Reset to Windows Defaults" to undo.

	.EXAMPLE Run the GUI
	.\Baseline.exe

	.EXAMPLE Run the script by specifying the module functions as an argument (headless)
	.\Bootstrap\Baseline.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal"

	.EXAMPLE Run a preset non-interactively
	.\Baseline.exe -Preset Basic

	.EXAMPLE Run the local interactive console menu
	.\Baseline.exe -ConsoleGui

	.EXAMPLE Run the local interactive console menu with preset items pre-selected
	.\Baseline.exe -ConsoleGui -Preset Basic

	.EXAMPLE Run a Game Mode profile non-interactively
	.\Baseline.exe -GameModeProfile Competitive

	.EXAMPLE Run a scenario profile non-interactively
	.\Baseline.exe -ScenarioProfile Privacy

	.EXAMPLE Run a troubleshooting Game Mode profile with explicit decision overrides
	.\Baseline.exe -GameModeProfile Troubleshooting -GameModeDecisionOverrides @{ FullscreenOptimizations = 'Disable'; MultiplaneOverlay = 'Disable' }

	.NOTES
	Supported Windows 10 versions
	Version: 1607+
	Editions: Home/Pro/Enterprise

	Supported Windows 11 versions
	Version: 23H2+
	Editions: Home/Pro/Enterprise
#>

[CmdletBinding()]
param
(
	[Parameter(Mandatory = $false)]
	[string[]]
	$Functions,

	[Parameter(Mandatory = $false)]
	[string[]]
	$Include,

	[Parameter(Mandatory = $false)]
	[string]
	$Preset,

	[Parameter(Mandatory = $false)]
	[ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
	[string]
	$GameModeProfile,

	[Parameter(Mandatory = $false)]
	[ValidateSet('Workstation', 'Privacy', 'Recovery')]
	[string]
	$ScenarioProfile,

	[Parameter(Mandatory = $false)]
	[hashtable]
	$GameModeDecisionOverrides = @{},

	[Parameter(Mandatory = $false)]
	[switch]
	$DryRun,

	[Parameter(Mandatory = $false)]
	[switch]
	$ComplianceCheck,

	# Apply all settings stored in a configuration profile to the local machine
	# without opening the GUI.  Use together with -ProfilePath.
	# Example: Baseline.exe -ConfigFile .\MyConfig.json -Run
	# Legacy form: Baseline.exe -ProfilePath .\MyConfig.json -ApplyProfile
	[Parameter(Mandatory = $false)]
	[Alias('Run')]
	[switch]
	$ApplyProfile,

	[Parameter(Mandatory = $false)]
	[switch]
	$ScheduledRun,

	[Parameter(Mandatory = $false)]
	[Alias('ConfigFile')]
	[string]
	$ProfilePath,

	# When set, all canonical write helpers (registry, audit, persistence) refuse
	# to mutate state. Useful for compliance-only scans on production endpoints.
	[Parameter(Mandatory = $false)]
	[switch]
	$ReadOnly,

	# Output mode for headless runs: Text (default), Json, Ndjson.
	[Parameter(Mandatory = $false)]
	[ValidateSet('Text', 'Json', 'Ndjson')]
	[string]
	$OutputFormat = 'Text',

	# Multi-target safety: forces preview-only unless -Apply is also specified.
	[Parameter(Mandatory = $false)]
	[switch]
	$Apply,

	# Suppress the GUI even when no other headless intent is supplied. Combined
	# with -ApplyPreset/-ApplyProfile/-ConfigFile/-ListPresets it forces the
	# unattended path; on its own it exits cleanly with no work performed.
	[Parameter(Mandatory = $false)]
	[switch]
	$NoGui,

	# Start the local interactive console menu instead of the WPF GUI.
	# Optional -Preset preselects that preset's command list in the menu.
	[Parameter(Mandatory = $false)]
	[switch]
	$ConsoleGui,

	# Run the GUI in config-creation mode so detection reads defaults and
	# the run action becomes Save Config instead of applying changes.
	[Parameter(Mandatory = $false)]
	[switch]
	$Design,

	# Print the catalog of shipped presets and exit. Implies -NoGui.
	[Parameter(Mandatory = $false)]
	[switch]
	$ListPresets,

	# Long form of -Preset for parity with the tracked preset contract.
	# Implies Apply
	# unless -DryRun is also specified.
	[Parameter(Mandatory = $false)]
	[string]
	$ApplyPreset,

	# Override the default session log path. Accepts a file or a directory;
	# directory inputs receive the auto-generated default filename.
	[Parameter(Mandatory = $false)]
	[string]
	$LogPath,

	# Lifecycle automation entry point. When set, runs the named automation
	# instead of the default GUI/CLI flow and exits.
	[Parameter(Mandatory = $false)]
	[ValidateSet('Upgrade', 'Downgrade', 'Rollback', 'IncidentPack', 'GpoConflictReport')]
	[string]
	$LifecycleOperation,

	[Parameter(Mandatory = $false)]
	[string]
	$LifecycleInstallerPath,

	[Parameter(Mandatory = $false)]
	[string]
	$LifecycleRollbackProfilePath,

	[Parameter(Mandatory = $false)]
	[string]
	$LifecycleSupportBundlePath,

	[Parameter(Mandatory = $false)]
	[string]
	$LifecycleOutputPath,

	[Parameter(Mandatory = $false)]
	[switch]
	$LifecycleExecute,

	[Parameter(Mandatory = $false)]
	[string[]]
	$TargetComputer,

	[Parameter(Mandatory = $false)]
	[System.Management.Automation.PSCredential]
	$RemoteCredential
)

Set-StrictMode -Version Latest
$Script:IsEmbeddedHost = ([System.Environment]::GetEnvironmentVariable('BASELINE_EMBEDDED_HOST') -eq '1')
$Script:LaunchTraceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
$Script:LaunchTracePath = Join-Path $Script:LaunchTraceDirectory 'Baseline-launch-trace.txt'

function Exit-BaselineBootstrap
{
	param(
		[int]
		$Code = 0
	)

	$Global:LASTEXITCODE = [int]$Code
	if ($Script:IsEmbeddedHost)
	{
		return [int]$Code
	}

	exit ([int]$Code)
}

<#
    .SYNOPSIS
#>

function Write-LaunchTrace
{
	param([string]$Message)

	try
	{
		if (-not [System.IO.Directory]::Exists($Script:LaunchTraceDirectory))
		{
			[void][System.IO.Directory]::CreateDirectory($Script:LaunchTraceDirectory)
		}
		Add-Content -LiteralPath $Script:LaunchTracePath -Value ("{0:o} {1}" -f [DateTime]::UtcNow, $Message) -ErrorAction SilentlyContinue
	}
	catch
	{
		$null = $_
	}
}

function Test-BaselineBootstrapSplashAbortRequested
{
	param(
		[object]
		$Splash = $Script:BootstrapSplash
	)

	if (-not $Splash)
	{
		return $false
	}

	if ($Splash -is [hashtable])
	{
		if ($Splash.ContainsKey('AbortRequested') -and [bool]$Splash.AbortRequested) { return $true }
		if ($Splash.ContainsKey('UserClosed') -and [bool]$Splash.UserClosed) { return $true }
		if ($Splash.ContainsKey('ProgrammaticClose') -and [bool]$Splash.ProgrammaticClose) { return $false }
		if ($Splash.ContainsKey('GuiReady') -and [bool]$Splash.GuiReady) { return $false }
		if ($Splash.ContainsKey('WasRendered') -and [bool]$Splash.WasRendered -and $Splash.ContainsKey('IsAlive') -and (-not [bool]$Splash.IsAlive)) { return $true }
	}

	return $false
}

function Stop-BaselineIfBootstrapSplashAbortRequested
{
	param(
		[string]
		$Phase = 'startup'
	)

	if (-not (Test-BaselineBootstrapSplashAbortRequested -Splash $Script:BootstrapSplash))
	{
		return
	}

	Write-LaunchTrace ('Bootstrap splash close requested abort before GUI open: {0}' -f $Phase)
	$Global:LASTEXITCODE = 0
	[System.Environment]::Exit(0)
	try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch { Write-LaunchTrace ('Bootstrap fallback process kill failed: {0}' -f $_.Exception.Message) }
}

function Set-BaselineBootstrapSplashChecklistStep
{
	param(
		[Parameter(Mandatory = $true)]
		[ValidateSet('updates','system','winget','chocolatey','finalize')]
		[string]
		$StepId,

		[Parameter(Mandatory = $true)]
		[ValidateSet('pending','in_progress','completed')]
		[string]
		$Status,

		[Parameter(Mandatory = $false)]
		[AllowEmptyString()]
		[string]
		$SubAction = ''
	)

	if (-not $Script:BootstrapSplash -or -not $Script:BootstrapSplash.IsAlive)
	{
		return
	}

	$setSplashStepCommand = Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $setSplashStepCommand)
	{
		return
	}

	try
	{
		$stepOrder = @()
		if ($Script:BootstrapSplash -is [hashtable] -and $Script:BootstrapSplash.ContainsKey('StepOrder') -and $Script:BootstrapSplash['StepOrder'])
		{
			$stepOrder = @($Script:BootstrapSplash['StepOrder'])
		}

		if ($stepOrder.Count -gt 0 -and $stepOrder -notcontains $StepId)
		{
			return
		}

		& $setSplashStepCommand -Splash $Script:BootstrapSplash -StepId $StepId -Status $Status -SubAction $SubAction | Out-Null
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.SplashChecklistStep' -Severity Debug
	}
}

Write-LaunchTrace 'Bootstrap start'

<#
    .SYNOPSIS
#>

function Test-BaselineAdministrator
{
	param()

	try
	{
		$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		$currentPrincipal = [System.Security.Principal.WindowsPrincipal]::new($currentIdentity)
		return $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	catch
	{
		Write-LaunchTrace ('Administrator detection failed: {0}' -f $_.Exception.Message)
		return $false
	}
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineCommandLineLiteral
{
	param(
		[Parameter(Mandatory = $true)]
		[object]
		$Value
	)

	if ($null -eq $Value)
	{
		return '$null'
	}

	if ($Value -is [bool])
	{
		return if ($Value) { '$true' } else { '$false' }
	}

	if ($Value -is [System.Collections.IDictionary])
	{
		$parts = [System.Collections.Generic.List[string]]::new()
		foreach ($key in @($Value.Keys | Sort-Object))
		{
			$keyText = [string]$key
			$valueText = ConvertTo-BaselineCommandLineLiteral -Value $Value[$key]
			$parts.Add(('{0} = {1}' -f ($keyText -replace "'", "''"), $valueText))
		}

		return '@{ ' + ($parts -join '; ') + ' }'
	}

	if ($Value -is [System.Array])
	{
		$arrayParts = [System.Collections.Generic.List[string]]::new()
		foreach ($item in @($Value))
		{
			$arrayParts.Add((ConvertTo-BaselineCommandLineLiteral -Value $item))
		}

		return '@(' + ($arrayParts -join ', ') + ')'
	}

	$text = [string]$Value
	return "'" + ($text -replace "'", "''") + "'"
}

<#
    .SYNOPSIS
#>

function ConvertTo-ValidatedTargetComputerList
{
	param(
		[Parameter(Mandatory = $true)]
		[string[]]
		$ComputerName
	)

	$hostnamePattern = '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$'
	$ipv4LiteralPattern = '^(?:\d{1,3}\.){3}\d{1,3}$'
	$validated = [System.Collections.Generic.List[string]]::new()

	foreach ($computer in @($ComputerName))
	{
		$candidate = [string]$computer
		if ([string]::IsNullOrWhiteSpace($candidate))
		{
			throw 'Invalid -TargetComputer entry: value cannot be empty.'
		}

		$candidate = $candidate.Trim()
		if ($candidate -match $ipv4LiteralPattern)
		{
			throw ("Invalid -TargetComputer entry '{0}'. Use a hostname or FQDN, not an IP literal." -f $candidate)
		}

		if ($candidate -notmatch $hostnamePattern)
		{
			throw ("Invalid -TargetComputer entry '{0}'. Use a valid hostname or FQDN." -f $candidate)
		}

		$validated.Add($candidate)
	}

	return $validated.ToArray()
}

<#
    .SYNOPSIS
#>

function New-BaselineElevationArgumentList
{
	param()

	$argumentList = [System.Collections.Generic.List[string]]::new()

	if ($Functions)
	{
		[void]$argumentList.Add('-Functions')
		foreach ($functionName in @($Functions))
		{
			[void]$argumentList.Add([string]$functionName)
		}
	}

	if ($Include)
	{
		[void]$argumentList.Add('-Include')
		foreach ($includePath in @($Include))
		{
			[void]$argumentList.Add([string]$includePath)
		}
	}

	if ($Preset)
	{
		[void]$argumentList.Add('-Preset')
		[void]$argumentList.Add([string]$Preset)
	}

	if ($GameModeProfile)
	{
		[void]$argumentList.Add('-GameModeProfile')
		[void]$argumentList.Add([string]$GameModeProfile)
	}

	if ($ScenarioProfile)
	{
		[void]$argumentList.Add('-ScenarioProfile')
		[void]$argumentList.Add([string]$ScenarioProfile)
	}

	if ($Apply)
	{
		[void]$argumentList.Add('-Apply')
	}

	if ($ApplyProfile)
	{
		[void]$argumentList.Add('-ApplyProfile')
	}

	if ($NoGui)
	{
		[void]$argumentList.Add('-NoGui')
	}

	if ($ConsoleGui)
	{
		[void]$argumentList.Add('-ConsoleGui')
	}

	if ($Design)
	{
		[void]$argumentList.Add('-Design')
	}

	if ($ListPresets)
	{
		[void]$argumentList.Add('-ListPresets')
	}

	if ($ApplyPreset)
	{
		[void]$argumentList.Add('-ApplyPreset')
		[void]$argumentList.Add([string]$ApplyPreset)
	}

	if ($GameModeDecisionOverrides -and $GameModeDecisionOverrides.Count -gt 0)
	{
		[void]$argumentList.Add('-GameModeDecisionOverrides')
		[void]$argumentList.Add((ConvertTo-BaselineCommandLineLiteral -Value $GameModeDecisionOverrides))
	}

	if ($DryRun)
	{
		[void]$argumentList.Add('-DryRun')
	}

	if ($ComplianceCheck)
	{
		[void]$argumentList.Add('-ComplianceCheck')
	}

	if ($ScheduledRun)
	{
		[void]$argumentList.Add('-ScheduledRun')
	}

	if ($ReadOnly)
	{
		[void]$argumentList.Add('-ReadOnly')
	}

	if ($PSBoundParameters.ContainsKey('LogPath') -and -not [string]::IsNullOrWhiteSpace($LogPath))
	{
		[void]$argumentList.Add('-LogPath')
		[void]$argumentList.Add([string]$LogPath)
	}

	if ($ProfilePath)
	{
		[void]$argumentList.Add('-ProfilePath')
		[void]$argumentList.Add([string]$ProfilePath)
	}

	if ($OutputFormat)
	{
		[void]$argumentList.Add('-OutputFormat')
		[void]$argumentList.Add([string]$OutputFormat)
	}

	if ($TargetComputer)
	{
		[void]$argumentList.Add('-TargetComputer')
		foreach ($computerName in @($TargetComputer))
		{
			[void]$argumentList.Add([string]$computerName)
		}
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$LifecycleOperation))
	{
		[void]$argumentList.Add('-LifecycleOperation')
		[void]$argumentList.Add([string]$LifecycleOperation)
	}

	if ($LifecycleInstallerPath)
	{
		[void]$argumentList.Add('-LifecycleInstallerPath')
		[void]$argumentList.Add([string]$LifecycleInstallerPath)
	}

	if ($LifecycleRollbackProfilePath)
	{
		[void]$argumentList.Add('-LifecycleRollbackProfilePath')
		[void]$argumentList.Add([string]$LifecycleRollbackProfilePath)
	}

	if ($LifecycleSupportBundlePath)
	{
		[void]$argumentList.Add('-LifecycleSupportBundlePath')
		[void]$argumentList.Add([string]$LifecycleSupportBundlePath)
	}

	if ($LifecycleOutputPath)
	{
		[void]$argumentList.Add('-LifecycleOutputPath')
		[void]$argumentList.Add([string]$LifecycleOutputPath)
	}

	if ($LifecycleExecute)
	{
		[void]$argumentList.Add('-LifecycleExecute')
	}

	if ($PSBoundParameters.ContainsKey('RemoteCredential'))
	{
		throw 'Direct non-elevated startup with -RemoteCredential is not supported. Launch Baseline.exe or start an elevated shell first.'
	}

	return $argumentList.ToArray()
}

$Script:BootstrapDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Script:BootstrapDir))
{
	$Script:BootstrapDir = Split-Path -Path $PSCommandPath -Parent -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($Script:BootstrapDir) -and $MyInvocation.MyCommand.Path)
{
	$Script:BootstrapDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
if ([string]::IsNullOrWhiteSpace($Script:BootstrapDir))
{
	throw 'Unable to determine Baseline bootstrap directory — $PSScriptRoot, $PSCommandPath, and $MyInvocation.MyCommand.Path are all empty.'
}

Write-LaunchTrace ("Bootstrap dir resolved: {0}" -f $Script:BootstrapDir)

# Keep this explicit import before localization, module loading, and InitialActions.
$bootstrapHelpersPath = Join-Path $Script:BootstrapDir 'Helpers\Bootstrap.Helpers.ps1'
if (-not (Test-Path -LiteralPath $bootstrapHelpersPath -PathType Leaf))
{
	throw "Required bootstrap helper file is missing: $bootstrapHelpersPath"
}
. $bootstrapHelpersPath

if (-not $Script:IsEmbeddedHost)
{
	Clear-Host
}

$Script:BootstrapSplash = $null

#region InitialActions
$Script:RepoRoot = Split-Path -Path $Script:BootstrapDir -Parent
$Script:ModuleRoot = Join-Path $Script:RepoRoot 'Module'
$Script:ModuleRootExists = Test-Path -LiteralPath $Script:ModuleRoot -PathType Container
$Script:RegionsRoot = Join-Path $Script:ModuleRoot 'Regions'

$LocalizationRoot = Join-Path $Script:RepoRoot 'Localizations'
$RequiredFiles = @(
	$bootstrapHelpersPath
    (Join-Path (Join-Path $LocalizationRoot 'English (United States)') 'en-US.json')
)

$RequiredFiles += if ($Script:ModuleRootExists)
{
	@(
		(Join-Path $Script:ModuleRoot 'SharedHelpers.psm1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Json.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Localization.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'ErrorHandling.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'CliMode.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Registry.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Environment.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Manifest.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'GameMode.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'ScenarioMode.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Preset.Helpers.ps1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'Recovery.Helpers.ps1')
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

    return (Exit-BaselineBootstrap -Code 2)
}

Write-LaunchTrace 'Bootstrap files verified'

# Resolve the startup UI culture before loading localization so the bootstrap
# splash, auto-update check, and initial package-manager checks all use the
# last selected GUI language when one exists.
# JSON helpers are dependency-free wrappers used by localization parsing and
# the user-prefs reader; source them before localization so both layers share
# the same depth-aware ConvertFrom-Json shim.
. (Join-Path $Script:ModuleRoot 'SharedHelpers\Json.Helpers.ps1')

# Load localization before the bootstrap splash so the first splash frame can
# render localized text and culture-sensitive controls immediately.
. (Join-Path $Script:ModuleRoot 'SharedHelpers\Localization.Helpers.ps1')
$Script:BootstrapUICulture = Resolve-BaselineBootstrapUICulture
$Global:Localization = Import-BaselineLocalization -BaseDirectory (Join-Path $Script:RepoRoot 'Localizations') -UICulture $Script:BootstrapUICulture
[void](Set-BaselineThreadCulture -UICulture $Script:BootstrapUICulture)
[System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', $Script:BootstrapUICulture, [System.EnvironmentVariableTarget]::Process)

Write-LaunchTrace 'Localization loaded'

Import-Module -Name (Join-Path $Script:ModuleRoot 'SharedHelpers.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
Write-LaunchTrace 'Shared helpers imported'

[void](Initialize-BaselineMarkdownRuntime -ModuleRoot $Script:ModuleRoot)
Write-LaunchTrace ('Markdown runtime loaded: {0}' -f (Test-BaselineMarkdownRuntimeReady))

if ($ReadOnly)
{
	if ($Apply)
	{
		throw [System.InvalidOperationException]::new('-ReadOnly cannot be combined with -Apply. ReadOnly mode forbids any state mutation; -Apply requests state mutation. Pick one.')
	}
	if ($ApplyProfile)
	{
		throw [System.InvalidOperationException]::new('-ReadOnly cannot be combined with -ApplyProfile. ReadOnly mode forbids any state mutation; -ApplyProfile writes profile state to the system. Pick one.')
	}
	Set-BaselineOperationMode -Mode 'ReadOnly'
	Write-LaunchTrace 'Operation mode forced to ReadOnly via -ReadOnly switch.'
}
else
{
	Set-BaselineOperationMode -Mode 'ReadWrite'
}

Set-BaselineCliOutputFormat -Format $OutputFormat
Write-LaunchTrace ('CLI output format set to {0}.' -f $OutputFormat)

# Resolve the running Baseline version early so headless lifecycle ops can
# stamp it into playbooks/incident packs before the GUI/auto-update path runs.
$Script:CurrentAppVersion = Resolve-BaselineCurrentVersion
Write-LaunchTrace ('Baseline current version resolved: {0}' -f $Script:CurrentAppVersion)

$Script:StartupSplashSettings = [pscustomobject]@{
	RunInitialActions = $true
	CheckWinGet = $true
	CheckChocolatey = $true
	WinGetCheckFrequency = 'Startup'
	ChocolateyCheckFrequency = 'Startup'
}
if (Get-Command -Name 'Get-BaselineStartupSplashSettings' -CommandType Function -ErrorAction SilentlyContinue)
{
	try
	{
		$Script:StartupSplashSettings = Get-BaselineStartupSplashSettings
		Write-LaunchTrace ('Startup splash settings loaded: initialActions={0}; winget={1}/{2}; chocolatey={3}/{4}' -f [bool]$Script:StartupSplashSettings.RunInitialActions, [bool]$Script:StartupSplashSettings.CheckWinGet, [string]$Script:StartupSplashSettings.WinGetCheckFrequency, [bool]$Script:StartupSplashSettings.CheckChocolatey, [string]$Script:StartupSplashSettings.ChocolateyCheckFrequency)
	}
	catch
	{
		Write-LaunchTrace ('Startup splash settings read failed; using defaults: {0}' -f $_.Exception.Message)
		Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.StartupSplashSettings' -Severity Debug
	}
}

function Get-BaselineBootstrapSplashStepOrder
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[object]$StartupSettings,

		[switch]$IncludeUpdates
	)

	$stepOrder = New-Object System.Collections.Generic.List[string]
	if ([bool]$IncludeUpdates)
	{
		[void]$stepOrder.Add('updates')
	}
	if ((-not $StartupSettings) -or [bool]$StartupSettings.RunInitialActions)
	{
		[void]$stepOrder.Add('system')
	}

	$startupWinGetEnabled = (-not $StartupSettings) -or [bool]$StartupSettings.CheckWinGet
	$startupChocolateyEnabled = (-not $StartupSettings) -or [bool]$StartupSettings.CheckChocolatey
	$startupWinGetFrequency = if ($StartupSettings -and $StartupSettings.PSObject.Properties['WinGetCheckFrequency']) { [string]$StartupSettings.WinGetCheckFrequency } else { 'Startup' }
	$startupChocolateyFrequency = if ($StartupSettings -and $StartupSettings.PSObject.Properties['ChocolateyCheckFrequency']) { [string]$StartupSettings.ChocolateyCheckFrequency } else { 'Startup' }
	$startupPackageManagerDecisionCommand = Get-Command -Name 'Get-BaselineStartupPackageManagerCheckDecision' -CommandType Function -ErrorAction Stop | Select-Object -First 1
	$startupWinGetDecision = & $startupPackageManagerDecisionCommand -PackageManager 'WinGet' -Enabled:$startupWinGetEnabled -Frequency $startupWinGetFrequency
	$startupChocolateyDecision = & $startupPackageManagerDecisionCommand -PackageManager 'Chocolatey' -Enabled:$startupChocolateyEnabled -Frequency $startupChocolateyFrequency

	if ([bool]$startupWinGetDecision.ShouldCheck)
	{
		[void]$stepOrder.Add('winget')
	}
	if ([bool]$startupChocolateyDecision.ShouldCheck)
	{
		[void]$stepOrder.Add('chocolatey')
	}
	[void]$stepOrder.Add('finalize')

	return @($stepOrder.ToArray())
}

if (-not [string]::IsNullOrWhiteSpace([string]$LifecycleOperation))
{
	Write-LaunchTrace ('Lifecycle automation entry point invoked: {0}' -f $LifecycleOperation)
	try
	{
		switch ($LifecycleOperation)
		{
			'IncidentPack'
			{
				if ([string]::IsNullOrWhiteSpace($LifecycleSupportBundlePath))
				{
					throw '-LifecycleSupportBundlePath is required for IncidentPack operations.'
				}
				$packResult = New-BaselineIncidentReproductionPack `
					-SupportBundlePath $LifecycleSupportBundlePath `
					-OutputDirectory $LifecycleOutputPath
				Format-BaselineCliResult -InputObject $packResult
			}
			'GpoConflictReport'
			{
				$manifest = @()
				$manifestReadFailures = [System.Collections.Generic.List[object]]::new()
				$dataDir = Join-Path $Script:ModuleRoot 'Data'
				if (Test-Path -LiteralPath $dataDir)
				{
					foreach ($df in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' -File -ErrorAction SilentlyContinue))
					{
						try
						{
							$raw = Get-Content -LiteralPath $df.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
							if ($raw -is [System.Collections.IEnumerable] -and -not ($raw -is [string]))
							{
								foreach ($item in $raw) { if ($item) { $manifest += $item } }
							}
							elseif ($raw.PSObject.Properties['Tweaks'])
							{
								foreach ($item in @($raw.Tweaks)) { if ($item) { $manifest += $item } }
							}
							elseif ($raw)
							{
								$manifest += $raw
							}
						}
						catch
						{
							Write-LaunchTrace ('Skipping unreadable manifest fragment {0}: {1}' -f $df.Name, $_.Exception.Message)
							Write-Warning ('GPO conflict report is incomplete; skipped unreadable manifest fragment {0}: {1}' -f $df.FullName, $_.Exception.Message)
							[void]$manifestReadFailures.Add([pscustomobject]@{
								Path = $df.FullName
								Error = $_.Exception.Message
							})
						}
					}
				}
				$report = Get-BaselineGpoConflictReport -Manifest $manifest
				if ($manifestReadFailures.Count -gt 0)
				{
					$report | Add-Member -NotePropertyName PartialFailureCount -NotePropertyValue ([int]$manifestReadFailures.Count) -Force
					$report | Add-Member -NotePropertyName PartialFailures -NotePropertyValue ($manifestReadFailures.ToArray()) -Force
				}
				if ($OutputFormat -eq 'Text')
				{
					Write-Output (Format-BaselineGpoConflictReport -Report $report)
				}
				else
				{
					Format-BaselineCliResult -InputObject $report
				}
			}
			default
			{
				$playbook = New-BaselineLifecyclePlaybook `
					-Operation $LifecycleOperation `
					-CurrentVersion $Script:CurrentAppVersion `
					-InstallerPath $LifecycleInstallerPath `
					-RollbackProfilePath $LifecycleRollbackProfilePath
				if ($LifecycleExecute)
				{
					Invoke-BaselineLifecyclePlaybook -Playbook $playbook | ForEach-Object { Format-BaselineCliResult -InputObject $_ }
				}
				else
				{
					Format-BaselineCliResult -InputObject $playbook
				}
			}
		}
		return (Exit-BaselineBootstrap -Code 0)
	}
	catch
	{
		Write-BaselineCliEvent -Kind 'Error' -Message ('Lifecycle operation failed: {0}' -f $_.Exception.Message)
		return (Exit-BaselineBootstrap -Code 2)
	}
}

# Normalize the CLI intent so the rest of the bootstrap can keep speaking the
# original parameter vocabulary (-Preset / -ApplyProfile / etc.) regardless of
# whether the user typed the long-form spelling.
$Script:CliIntent = $null
$cliIntentCmd = Get-Command -Name 'Resolve-BaselineCliIntent' -CommandType Function -ErrorAction SilentlyContinue
if ($cliIntentCmd)
{
	$cliIntentParams = @{
		Apply = [bool]$Apply
		ApplyProfile = [bool]$ApplyProfile
		DryRun = [bool]$DryRun
		ListPresets = [bool]$ListPresets
		NoGui = [bool]$NoGui
		ConsoleGui = [bool]$ConsoleGui
		ApplyPreset = [string]$ApplyPreset
		ConfigFile = [string]$ProfilePath
		ProfilePath = [string]$ProfilePath
		Preset = [string]$Preset
	}
	$Script:CliIntent = & $cliIntentCmd -ParamValues $cliIntentParams
	foreach ($cliWarning in @($Script:CliIntent.Warnings))
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$cliWarning))
		{
			Write-LaunchTrace ('CLI intent warning: {0}' -f [string]$cliWarning)
			Write-Warning ([string]$cliWarning)
		}
	}
	if (@($Script:CliIntent.Errors).Count -gt 0)
	{
		foreach ($cliError in @($Script:CliIntent.Errors))
		{
			if (-not [string]::IsNullOrWhiteSpace([string]$cliError))
			{
				Write-LaunchTrace ('CLI intent error: {0}' -f [string]$cliError)
				Write-Error ([string]$cliError)
			}
		}
		return (Exit-BaselineBootstrap -Code 2)
	}
}

# Long-form -ApplyPreset is just an alternate spelling of -Preset; normalize so
# the preset expansion path below sees a single canonical value.
if (-not [string]::IsNullOrWhiteSpace([string]$ApplyPreset) -and [string]::IsNullOrWhiteSpace([string]$Preset))
{
	$Preset = $ApplyPreset
	Write-LaunchTrace ("Normalized -ApplyPreset '{0}' to -Preset." -f $ApplyPreset)
}

# A config/profile path supplied without -ApplyProfile/-ComplianceCheck must not
# silently no-op. Promote to ApplyProfile so the user actually gets what they
# asked for (or sees the manifest in dry-run mode).
if (-not [string]::IsNullOrWhiteSpace([string]$ProfilePath) -and -not $ComplianceCheck -and -not $ApplyProfile -and -not $TargetComputer -and -not $DryRun)
{
	$ApplyProfile = $true
	Write-LaunchTrace ("Promoting -ProfilePath '{0}' to -ApplyProfile." -f $ProfilePath)
	Write-Warning ("ProfilePath '{0}' supplied without -ApplyProfile/-ComplianceCheck; promoting to -ApplyProfile (use -DryRun to preview only)." -f $ProfilePath)
}

# Handle --list-presets early: it short-circuits everything else.
if ($ListPresets)
{
	$presetCatalogCmd = Get-Command -Name 'Get-BaselinePresetCatalog' -CommandType Function -ErrorAction SilentlyContinue
	$presetFormatCmd = Get-Command -Name 'Format-BaselinePresetCatalog' -CommandType Function -ErrorAction SilentlyContinue
	if (-not $presetCatalogCmd -or -not $presetFormatCmd)
	{
		Write-LaunchTrace 'Preset catalog helpers missing — cannot honor -ListPresets.'
		Write-Error 'Preset catalog helpers are unavailable; cannot list presets.'
		return (Exit-BaselineBootstrap -Code 2)
	}
	$presetCatalog = & $presetCatalogCmd -PresetDirectory (Join-Path $Script:ModuleRoot 'Data\Presets')
	$rendered = & $presetFormatCmd -Catalog $presetCatalog
	Write-Output $rendered
	return (Exit-BaselineBootstrap -Code 0)
}

$Script:PowerShellRemotingForcesNoGui = $false
$isPowerShellRemotingSession = $false
$remotingSessionCommand = Get-Command -Name 'Test-BaselinePowerShellRemotingSession' -CommandType Function -ErrorAction SilentlyContinue
if ($remotingSessionCommand)
{
	$isPowerShellRemotingSession = [bool](& $remotingSessionCommand)
}
if ($isPowerShellRemotingSession)
{
	if ($ConsoleGui)
	{
		Write-LaunchTrace 'PowerShell Remoting session rejected -ConsoleGui so WPF paths stay bypassed.'
		Write-Error '-ConsoleGui cannot run inside PowerShell Remoting / WinRM. Use -NoGui with -Preset, -Functions, or -ProfilePath for remote automation.'
		return (Exit-BaselineBootstrap -Code 2)
	}

	if (-not $NoGui)
	{
		$NoGui = $true
		$Script:PowerShellRemotingForcesNoGui = $true
		Write-LaunchTrace 'PowerShell Remoting session forces -NoGui so WPF paths stay bypassed.'
	}
}

# Multi-target preview safety: when more than one target is supplied without
# explicit -Apply, force preview-only mode. The user must opt in to changes.
$Script:RemoteForcesNoGui = $false
if ($TargetComputer -and -not $NoGui)
{
	$NoGui = $true
	$Script:RemoteForcesNoGui = $true
	Write-LaunchTrace 'Remote targeting forces -NoGui so WPF paths stay bypassed.'
}
$Script:RemoteTargetCount = if ($TargetComputer) { @($TargetComputer).Count } else { 0 }
$Script:MultiTargetPreviewOnly = ($Script:RemoteTargetCount -gt 1 -and -not $Apply)
if ($Script:MultiTargetPreviewOnly)
{
	Write-LaunchTrace ('Multi-target preview-only enforced: {0} target(s) without -Apply.' -f $Script:RemoteTargetCount)
}

# Initialize logging early so the update check and splash phase are captured.
Import-Module -Name (Join-Path $Script:ModuleRoot 'Logging.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
Write-LaunchTrace 'Logging module imported'
$osName = (Get-OSInfo).OSName
$logDirectory = Get-BaselineLogDirectory -FallbackRoot $env:TEMP
$logDirectory = Get-BaselineConfiguredLogDirectory -DefaultDirectory $logDirectory -FallbackRoot $env:TEMP
$Global:LogFilePath = New-BaselineSessionLogPath -LogDirectory $logDirectory -OsName $osName
$Script:LogDefaultFileName = [System.IO.Path]::GetFileName($Global:LogFilePath)
if ($PSBoundParameters.ContainsKey('LogPath') -and -not [string]::IsNullOrWhiteSpace($LogPath))
{
	$logResolution = Resolve-BaselineCliLogPath -RequestedPath $LogPath -DefaultPath $Global:LogFilePath -DefaultFileName $Script:LogDefaultFileName -WorkingDirectory (Get-Location).ProviderPath
	if ($logResolution.Warning)
	{
		Write-LaunchTrace ('LogPath override rejected: {0}' -f [string]$logResolution.Warning)
		Write-Warning ([string]$logResolution.Warning)
	}
	$Global:LogFilePath = [string]$logResolution.ResolvedPath
}
Set-LogFile -Path $Global:LogFilePath
Initialize-SessionStatistics
Set-BaselineLogScope -Scope 'Bootstrap'
Write-LaunchTrace 'Logging initialized'

if ($Script:IsEmbeddedHost)
{
	$null = Initialize-BaselineProcessIdentity
}

# Decide whether the GUI bootstrap splash + single-instance gate should run.
# Headless work intents (preset, profile, functions, list-presets, etc.) skip
# the splash entirely so unattended runs do not flash a window. -NoGui without
# any work to do exits cleanly so scripts can probe the launcher safely.
$hasHeadlessWorkIntent = (
	($Functions -and $Functions.Count -gt 0) -or
	-not [string]::IsNullOrWhiteSpace([string]$Preset) -or
	-not [string]::IsNullOrWhiteSpace([string]$GameModeProfile) -or
	-not [string]::IsNullOrWhiteSpace([string]$ScenarioProfile) -or
	-not [string]::IsNullOrWhiteSpace([string]$ProfilePath) -or
	-not [string]::IsNullOrWhiteSpace([string]$ApplyPreset) -or
	$ApplyProfile -or $ComplianceCheck -or $ListPresets -or $ConsoleGui
)
$hasHeadlessIntent = (
	$hasHeadlessWorkIntent -or
	$ComplianceCheck -or $ScheduledRun -or $TargetComputer -or $NoGui -or $ConsoleGui
)
if ($NoGui -and -not $Script:RemoteForcesNoGui -and -not $hasHeadlessWorkIntent)
{
	Write-LaunchTrace '-NoGui supplied without any headless work intent; exiting cleanly.'
	Write-Warning '-NoGui supplied with no work to do (no -Preset/-Functions/-ApplyProfile/-ApplyPreset/-ListPresets/-ConfigFile). Exiting.'
	return (Exit-BaselineBootstrap -Code 0)
}
$shouldShowBootstrapSplash = -not $hasHeadlessIntent

if ($shouldShowBootstrapSplash)
{
	# Single-instance gate: when starting the GUI, refuse to launch a second
	# Baseline window over an existing one. Fails closed — if the helper is
	# missing or throws we abort with exit code 2 rather than risk a second
	# GUI fighting the first one over the same daily log.
	$singleInstanceAcquireCmd = Get-Command -Name 'Acquire-BaselineSingleInstance' -CommandType Function -ErrorAction SilentlyContinue
	if (-not $singleInstanceAcquireCmd)
	{
		Write-LaunchTrace 'Single-instance helper is missing — cannot enforce the GUI gate. Failing closed.'
		Write-Warning 'Single-instance helper is missing; cannot safely launch a second GUI instance. Aborting.'
		return (Exit-BaselineBootstrap -Code 2)
	}
	try
	{
		$Script:SingleInstanceState = & $singleInstanceAcquireCmd
		$Script:SingleInstanceMutexName = $Script:SingleInstanceState.MutexName
		$Script:SingleInstanceLock = $Script:SingleInstanceState.LockResult
		$Script:SingleInstanceDecision = $Script:SingleInstanceState.Decision
		if ($Script:SingleInstanceDecision -and $Script:SingleInstanceDecision.Action -eq 'HandoffAndExit')
		{
			Write-LaunchTrace ('Single-instance handoff: {0}' -f [string]$Script:SingleInstanceDecision.Reason)
			return (Exit-BaselineBootstrap -Code 0)
		}
	}
	catch
	{
		Write-LaunchTrace ('SingleInstance gate failed: {0}' -f $_.Exception.Message)
		Write-Warning ('SingleInstance gate failed: {0}. Aborting to avoid concurrent GUI runs.' -f $_.Exception.Message)
		return (Exit-BaselineBootstrap -Code 2)
	}

	Write-LaunchTrace 'Bootstrap splash requested'
	$showBootstrapSplashCommand = Get-Command -Name 'Show-BootstrapLoadingSplash' -CommandType Function -ErrorAction SilentlyContinue
	if ($showBootstrapSplashCommand)
	{
		Write-LaunchTrace ('Bootstrap splash command resolved: {0}' -f [string]$showBootstrapSplashCommand.ModuleName)
		try
		{
			$shouldPrimeUpdatesPulse = $false
			if (Get-Command -Name 'Test-BaselineAutoUpdateStartupEnabled' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$shouldPrimeUpdatesPulse = [bool](Test-BaselineAutoUpdateStartupEnabled)
			}
			$bootstrapSplashStepOrder = Get-BaselineBootstrapSplashStepOrder -StartupSettings $Script:StartupSplashSettings -IncludeUpdates:$shouldPrimeUpdatesPulse
			Write-LaunchTrace ('Bootstrap splash steps: {0}' -f ($bootstrapSplashStepOrder -join ', '))

			if (-not $shouldPrimeUpdatesPulse)
			{
				$defaultSplashStepOrder = @('system','winget','chocolatey','finalize')
				$usesDefaultSplashStepOrder = @($bootstrapSplashStepOrder).Count -eq $defaultSplashStepOrder.Count
				if ($usesDefaultSplashStepOrder)
				{
					for ($stepIndex = 0; $stepIndex -lt $defaultSplashStepOrder.Count; $stepIndex++)
					{
						if ([string]$bootstrapSplashStepOrder[$stepIndex] -ne [string]$defaultSplashStepOrder[$stepIndex])
						{
							$usesDefaultSplashStepOrder = $false
							break
						}
					}
				}

				if ($usesDefaultSplashStepOrder)
				{
					$Script:BootstrapSplash = & $showBootstrapSplashCommand
				}
				else
				{
					$Script:BootstrapSplash = & $showBootstrapSplashCommand -StepOrder $bootstrapSplashStepOrder
				}
			}
			else
			{
				$Script:BootstrapSplash = & $showBootstrapSplashCommand -StartUpdatesPulse -StepOrder $bootstrapSplashStepOrder
			}
		}
		catch
		{
			Write-LaunchTrace ('Bootstrap splash command failed: {0}' -f $_.Exception.Message)
			Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.ShowBootstrapLoadingSplash' -Severity Debug
			$Script:BootstrapSplash = $null
		}
	}
	else
	{
		Write-LaunchTrace 'Bootstrap splash command was not found'
		$Script:BootstrapSplash = $null
	}
	$bootstrapSplashType = if ($Script:BootstrapSplash) { $Script:BootstrapSplash.GetType().FullName } else { '<null>' }
	$bootstrapSplashIsAlive = '<missing>'
	$bootstrapSplashWasRendered = '<missing>'
	if ($Script:BootstrapSplash -is [hashtable])
	{
		if ($Script:BootstrapSplash.ContainsKey('IsAlive')) { $bootstrapSplashIsAlive = [string]$Script:BootstrapSplash.IsAlive }
		if ($Script:BootstrapSplash.ContainsKey('WasRendered')) { $bootstrapSplashWasRendered = [string]$Script:BootstrapSplash.WasRendered }
	}
	elseif ($Script:BootstrapSplash)
	{
		if ($Script:BootstrapSplash.PSObject.Properties['IsAlive']) { $bootstrapSplashIsAlive = [string]$Script:BootstrapSplash.IsAlive }
		if ($Script:BootstrapSplash.PSObject.Properties['WasRendered']) { $bootstrapSplashWasRendered = [string]$Script:BootstrapSplash.WasRendered }
	}
	Write-LaunchTrace ('Bootstrap splash handle state: null={0} type={1} isAlive={2} wasRendered={3}' -f ($null -eq $Script:BootstrapSplash), $bootstrapSplashType, $bootstrapSplashIsAlive, $bootstrapSplashWasRendered)
	if ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive -and $Script:BootstrapSplash.WasRendered)
	{
		Write-LaunchTrace 'Bootstrap splash shown'
	}
	elseif ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive)
	{
		Write-LaunchTrace 'Bootstrap splash render pending'
	}
	else
	{
		Write-LaunchTrace 'Bootstrap splash was not shown'
	}
	Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'after splash initialization'
}
else
{
	Write-LaunchTrace 'Bootstrap splash skipped (headless intent detected).'
}

# Auto-update: check GitHub for a newer release and apply before continuing
$Global:LoadingSplash = $Script:BootstrapSplash
if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentAppVersion) -or $Script:CurrentAppVersion -eq '0.0.0')
{
	$Script:CurrentAppVersion = Resolve-BaselineCurrentVersion
}
Set-BaselineLogScope -Scope 'Updater'
try
{
	Invoke-BaselineAutoUpdate -Splash $Script:BootstrapSplash -CurrentVersion $Script:CurrentAppVersion
}
finally
{
	Set-BaselineLogScope -Scope 'Bootstrap'
}
if ($Script:StartupSplashSettings -and [bool]$Script:StartupSplashSettings.RunInitialActions)
{
	Set-BaselineBootstrapSplashChecklistStep -StepId 'system' -Status 'in_progress' -SubAction ''
}
Write-LaunchTrace 'Auto-update checked'
Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'after auto-update check'

$osName = (Get-OSInfo).OSName
$Script:BaselineWindowTitle = "Baseline | Utility for $osName"
try
{
	$Host.UI.RawUI.WindowTitle = $Script:BaselineWindowTitle
}
catch
{
	$null = $_
}

if ([string]::IsNullOrWhiteSpace($Preset) -and [string]::IsNullOrWhiteSpace($GameModeProfile) -and [string]::IsNullOrWhiteSpace($ScenarioProfile) -and -not $Functions)
{
	$Preset = Resolve-HeadlessEnvironmentPreset -EnvironmentPreset $env:BASELINE_PRESET
}

if ($Script:BootstrapSplash -and $Script:BootstrapSplash.IsAlive)
{
	try {
		$Script:BootstrapSplash.Dispatcher.Invoke([System.Action]{
			$Script:BootstrapSplash.Window.Title = $Script:BaselineWindowTitle
		})
	} catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.BootstrapSplash.SetWindowTitle' -Severity Debug }
}

Remove-Module -Name Baseline -Force -ErrorAction Ignore

# Checking whether script is the correct PowerShell version
try
{
	Import-Module -Name (Join-Path $Script:ModuleRoot 'Baseline.psd1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
}
catch [System.InvalidOperationException]
{
	Write-Warning -Message $Localization.UnsupportedPowerShell
	return (Exit-BaselineBootstrap -Code 2)
}

$initialActionsModulePath = Join-Path $Script:RegionsRoot 'InitialActions.psm1'
$initialActionsModule = Import-Module -Name $initialActionsModulePath -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop -PassThru
$Script:InitialActionsCommand = $initialActionsModule.ExportedCommands['InitialActions']
if (-not $Script:InitialActionsCommand)
{
	throw "Required startup command 'InitialActions' was not exported by: $initialActionsModulePath"
}

function Invoke-BaselineInitialActions
{
	[CmdletBinding()]
	param (
		[switch]$SkipWinGetCheck,
		[switch]$SkipChocolateyCheck
	)

	& $Script:InitialActionsCommand -SkipWinGetCheck:$SkipWinGetCheck -SkipChocolateyCheck:$SkipChocolateyCheck
}

function Test-BaselineStartupPackageManagerCheckDue
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('WinGet', 'Chocolatey')]
		[string]$PackageManager,

		[bool]$Enabled = $true,

		[string]$Frequency = 'Startup'
	)

	$decisionCommand = Get-Command -Name 'Get-BaselineStartupPackageManagerCheckDecision' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $decisionCommand)
	{
		throw 'Get-BaselineStartupPackageManagerCheckDecision was not available for startup package-manager scheduling.'
	}

	$decision = & $decisionCommand -PackageManager $PackageManager -Enabled:$Enabled -Frequency $Frequency
	Write-LaunchTrace ('Startup {0} check decision: enabled={1}; frequency={2}; shouldCheck={3}; reason={4}' -f $PackageManager, [bool]$Enabled, [string]$decision.Frequency, [bool]$decision.ShouldCheck, [string]$decision.Reason)
	try
	{
		LogDebug ('Startup package-manager check due result consumed. PackageManager="{0}"; Enabled={1}; Frequency="{2}"; ShouldCheck={3}; LastCheckedUtc="{4}"; NextEligibleUtc="{5}"; Reason="{6}"' -f $PackageManager, [bool]$Enabled, [string]$decision.Frequency, [bool]$decision.ShouldCheck, $(if ($decision.LastCheckedUtc) { ([datetime]$decision.LastCheckedUtc).ToUniversalTime().ToString('o') } else { '' }), $(if ($decision.NextEligibleUtc) { ([datetime]$decision.NextEligibleUtc).ToUniversalTime().ToString('o') } else { '' }), [string]$decision.Reason)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.StartupPackageManagerCheckDue.LogDebug' -Severity Warning
	}
	return [bool]$decision.ShouldCheck
}

function Invoke-BaselinePackageManagerStartupChecks
{
	[CmdletBinding()]
	param (
		[switch]$SkipWinGetCheck,

		[switch]$SkipChocolateyCheck
	)

	if ([bool]$SkipWinGetCheck -and [bool]$SkipChocolateyCheck)
	{
		Write-LaunchTrace 'Startup package-manager checks skipped by preference or frequency.'
		try { LogDebug ('Startup package-manager bootstrap skipped. SkipWinGet={0}; SkipChocolatey={1}' -f [bool]$SkipWinGetCheck, [bool]$SkipChocolateyCheck) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.PackageManagerStartupChecks.SkippedLogDebug' -Severity Warning }
		return
	}

	$packageManagerBootstrapCommand = Get-Command -Name 'Initialize-PackageManagersBootstrap' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $packageManagerBootstrapCommand)
	{
		throw 'Initialize-PackageManagersBootstrap was not available for startup package-manager checks.'
	}

	Write-LaunchTrace ('Package-manager startup checks started (skipWinGet={0}; skipChocolatey={1})' -f [bool]$SkipWinGetCheck, [bool]$SkipChocolateyCheck)
	try { LogDebug ('Startup package-manager bootstrap command resolved. Command="{0}"; Source="{1}"; IncludeWinGet={2}; IncludeChocolatey={3}' -f [string]$packageManagerBootstrapCommand.Name, [string]$packageManagerBootstrapCommand.Source, (-not [bool]$SkipWinGetCheck), (-not [bool]$SkipChocolateyCheck)) }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.PackageManagerStartupChecks.CommandLogDebug' -Severity Warning }
	& $packageManagerBootstrapCommand -LoadingSplash $Global:LoadingSplash -IncludeWinGet:(-not [bool]$SkipWinGetCheck) -IncludeChocolatey:(-not [bool]$SkipChocolateyCheck)
	Write-LaunchTrace 'Package-manager startup checks completed'
	try { LogDebug ('Startup package-manager bootstrap completed. WinGetRequested={0}; ChocolateyRequested={1}' -f (-not [bool]$SkipWinGetCheck), (-not [bool]$SkipChocolateyCheck)) }
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.PackageManagerStartupChecks.CompletedLogDebug' -Severity Warning }
}

function Set-BaselineStartupPackageManagerChecksCompleted
{
	[CmdletBinding()]
	param (
		[bool]$WinGet,

		[bool]$Chocolatey
	)

	if (-not ($WinGet -or $Chocolatey))
	{
		try { LogDebug 'Startup package-manager check completion state not persisted because no checks ran.' }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.PackageManagerStartupChecks.NoCompletionStateLogDebug' -Severity Warning }
		return
	}

	if (Get-Command -Name 'Set-BaselineStartupPackageManagerCheckState' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-BaselineStartupPackageManagerCheckState -WinGet:$WinGet -Chocolatey:$Chocolatey
		try { LogDebug ('Startup package-manager check completion state requested. WinGet={0}; Chocolatey={1}' -f [bool]$WinGet, [bool]$Chocolatey) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.PackageManagerStartupChecks.CompletionStateLogDebug' -Severity Warning }
	}
}

Import-BaselineIncludedTweakLibraries -IncludePaths $Include

# Validate mutual exclusion using original bound parameters before any expansion.
# Keep this as a string array so Count remains reliable even for a single mode
# or when no headless mode is present.
[string[]]$headlessModes = @(
	@($Preset, $GameModeProfile, $ScenarioProfile, $(if ($Functions) { 'Functions' }), $(if ($ApplyProfile) { 'ApplyProfile' })) |
		Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($ConsoleGui)
{
	if ($TargetComputer)
	{
		throw '-ConsoleGui is local-only and cannot be combined with -TargetComputer. Use -NoGui for remote automation.'
	}
	if ($Functions)
	{
		throw '-ConsoleGui cannot be combined with -Functions. Use -Preset to preselect items or select functions from the console menu.'
	}
	if ($Apply -or $ApplyProfile -or $ComplianceCheck -or $ScheduledRun -or -not [string]::IsNullOrWhiteSpace([string]$ProfilePath) -or -not [string]::IsNullOrWhiteSpace([string]$ApplyPreset))
	{
		throw '-ConsoleGui cannot be combined with apply/profile/compliance arguments. Use -NoGui for unattended automation.'
	}
	if ($GameModeProfile -or $ScenarioProfile)
	{
		throw '-ConsoleGui currently accepts only an optional -Preset preselection, not Game Mode or scenario profiles.'
	}
}
if ($ComplianceCheck -and $headlessModes.Count -gt 0)
{
	throw '-ComplianceCheck cannot be combined with -Preset, -GameModeProfile, -ScenarioProfile, or -Functions.'
}

if ($ScheduledRun -and -not $ComplianceCheck)
{
	throw '-ScheduledRun requires -ComplianceCheck.'
}

if ($ScheduledRun -and $headlessModes.Count -gt 0)
{
	throw '-ScheduledRun cannot be combined with -Preset, -GameModeProfile, -ScenarioProfile, or -Functions.'
}

if ($headlessModes.Count -gt 1)
{
	throw 'Specify only one of -Preset, -GameModeProfile, -ScenarioProfile, or -Functions.'
}

if ($PSBoundParameters.ContainsKey('GameModeDecisionOverrides') -and [string]::IsNullOrWhiteSpace($GameModeProfile))
{
	throw 'Specify -GameModeProfile when using -GameModeDecisionOverrides.'
}

if ($DryRun -and -not $ConsoleGui -and -not $ComplianceCheck -and $headlessModes.Count -eq 0)
{
	throw 'Specify -Preset, -GameModeProfile, -ScenarioProfile, or -Functions when using -DryRun.'
}

if ($ComplianceCheck -and [string]::IsNullOrWhiteSpace($ProfilePath))
{
	throw 'Specify -ProfilePath when using -ComplianceCheck.'
}

if ($ApplyProfile -and [string]::IsNullOrWhiteSpace($ProfilePath))
{
	throw 'Specify -ProfilePath when using -ApplyProfile.'
}

if (-not [string]::IsNullOrWhiteSpace($ProfilePath) -and -not $ComplianceCheck -and -not $ApplyProfile -and -not $TargetComputer)
{
	throw 'Specify -ComplianceCheck or -ApplyProfile when using -ProfilePath (unless -TargetComputer is also specified).'
}

if ($TargetComputer -and [string]::IsNullOrWhiteSpace($ProfilePath) -and -not $Preset)
{
	throw 'Specify -ProfilePath or -Preset when using -TargetComputer.'
}

if ($TargetComputer -and $Functions -and -not $Preset)
{
	throw '-TargetComputer cannot be combined with -Functions directly. Use -ProfilePath or -Preset instead.'
}

if ($TargetComputer)
{
	$TargetComputer = @(ConvertTo-ValidatedTargetComputerList -ComputerName $TargetComputer)
}

if ($TargetComputer -and $Include -and @($Include).Count -gt 0)
{
	throw '-Include cannot be combined with -TargetComputer. Included tweak libraries are local-only.'
}

if ($GameModeProfile)
{
	$GameModeDecisionOverrides = Resolve-ValidatedGameModeDecisionOverrides -ProfileName $GameModeProfile -DecisionOverrides $GameModeDecisionOverrides
}

# Preset mode expands the requested preset into the same command list used by
# the headless path so the bootstrap can stay non-interactive.
if ($ConsoleGui)
{
	if ($Script:BootstrapSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:BootstrapSplash -DisposeResources
		$Script:BootstrapSplash = $null
	}

	$consolePresetCommands = @()
	if ($Preset)
	{
		$consolePresetCommands = @(Get-HeadlessPresetCommandList -PresetName $Preset)
		if (-not $consolePresetCommands -or $consolePresetCommands.Count -eq 0)
		{
			throw "Preset '$Preset' did not resolve to any commands."
		}
	}

	$consoleManifest = @(Import-TweakManifestFromData)
	if (-not $consoleManifest -or $consoleManifest.Count -eq 0)
	{
		throw 'Failed to load tweak manifest for the console menu.'
	}

	$consoleSelection = Show-BaselineConsoleGui -Manifest $consoleManifest -PreselectedCommands $consolePresetCommands -PresetName $Preset
	if ($null -eq $consoleSelection)
	{
		Write-LaunchTrace 'Console GUI exited without a selected run.'
		return (Exit-BaselineBootstrap -Code 0)
	}

	$Functions = @($consoleSelection | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
	if (-not $Functions -or $Functions.Count -eq 0)
	{
		Write-LaunchTrace 'Console GUI returned no selected commands.'
		Write-Host 'No commands selected.' -ForegroundColor Yellow
		return (Exit-BaselineBootstrap -Code 0)
	}

	Write-LaunchTrace ('Console GUI selected {0} command(s).' -f $Functions.Count)
}
elseif ($Preset)
{
	$Functions = @(Get-HeadlessPresetCommandList -PresetName $Preset)
	if (-not $Functions -or $Functions.Count -eq 0)
	{
		throw "Preset '$Preset' did not resolve to any commands."
	}
}

if ($GameModeProfile)
{
	$Functions = @(Get-GameModeProfileCommandList -ProfileName $GameModeProfile -DecisionOverrides $GameModeDecisionOverrides)
	if (-not $Functions -or $Functions.Count -eq 0)
	{
		throw "Game Mode profile '$GameModeProfile' did not resolve to any commands."
	}
}

if ($ScenarioProfile)
{
	$Functions = @(Get-ScenarioProfileCommandList -ProfileName $ScenarioProfile)
	if (-not $Functions -or $Functions.Count -eq 0)
	{
		throw "Scenario profile '$ScenarioProfile' did not resolve to any commands."
	}
}

# Remote targeting mode: apply or check compliance on remote machines.
if ($TargetComputer)
{
	# Close the bootstrap splash - remote mode does not use the GUI.
	if ($Script:BootstrapSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:BootstrapSplash -DisposeResources
		$Script:BootstrapSplash = $null
	}

	# If -Preset was specified without -ProfilePath, convert the preset to a
	# temporary profile file so the remote helpers can consume it.
	$remoteProfilePath = $ProfilePath
	$tempProfileCreated = $false
	if ([string]::IsNullOrWhiteSpace($remoteProfilePath) -and $Preset)
	{
		$manifest = @(Import-TweakManifestFromData)
		$tempProfile = ConvertFrom-PresetToProfile -PresetName $Preset -Manifest $manifest -ModuleRoot $Script:ModuleRoot
		$remoteProfilePath = Join-Path ([System.IO.Path]::GetTempPath()) "Baseline_Preset_$Preset.json"
		Export-ConfigurationProfile -Profile $tempProfile -FilePath $remoteProfilePath
		$tempProfileCreated = $true
	}

	$resolvedRemoteProfile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($remoteProfilePath)
	if (-not (Test-Path -LiteralPath $resolvedRemoteProfile))
	{
		Write-Error "Profile file not found: $resolvedRemoteProfile"
		return (Exit-BaselineBootstrap -Code 1)
	}

	try
	{
		$remoteProfileDocument = Get-Content -LiteralPath $resolvedRemoteProfile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
		if ($remoteProfileDocument -and $remoteProfileDocument.PSObject.Properties['IncludePaths'])
		{
			$remoteIncludePaths = @(
				@($remoteProfileDocument.IncludePaths) |
					Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
					ForEach-Object { ([string]$_).Trim() }
			)
			if ($remoteIncludePaths.Count -gt 0)
			{
				throw 'Configuration profiles that include custom tweak libraries are local-only and cannot be applied to remote targets.'
			}
		}
	}
	catch
	{
		Write-Error "Failed to validate include libraries for remote profile '$resolvedRemoteProfile': $_"
		return (Exit-BaselineBootstrap -Code 1)
	}

	# Test connectivity first.
	Write-Host ''
	Write-Host '  Baseline Remote Targeting' -ForegroundColor Cyan
	Write-Host '  =========================' -ForegroundColor Cyan
	Write-Host ''
	Write-Host '  Testing connectivity...' -ForegroundColor DarkGray

	$connectParams = @{ ComputerName = $TargetComputer }
	if ($RemoteCredential) { $connectParams.Credential = $RemoteCredential }
	$connectResults = Test-BaselineRemoteConnectivity @connectParams

	$unreachable = @($connectResults | Where-Object { -not $_.Reachable })
	if ($unreachable.Count -gt 0)
	{
		foreach ($ur in @($unreachable))
		{
			Write-Host "  [UNREACHABLE] $($ur.ComputerName): $($ur.Error)" -ForegroundColor Red
		}
	}

	$reachableMachines = @($connectResults | Where-Object { $_.Reachable } | ForEach-Object { $_.ComputerName })
	if ($reachableMachines.Count -eq 0)
	{
		Write-Error 'No target computers are reachable.'
		if ($tempProfileCreated -and (Test-Path -LiteralPath $resolvedRemoteProfile)) { Remove-Item -LiteralPath $resolvedRemoteProfile -Force -ErrorAction SilentlyContinue }
		return (Exit-BaselineBootstrap -Code 1)
	}

	$remoteParams = @{ ComputerName = $reachableMachines; ProfilePath = $resolvedRemoteProfile }
	if ($RemoteCredential) { $remoteParams.Credential = $RemoteCredential }

	if ($ComplianceCheck)
	{
		# Remote compliance check mode.
		Write-Host "  Running compliance check on $($reachableMachines.Count) machine(s)..." -ForegroundColor DarkGray
		Write-Host ''

		$remoteResults = Invoke-BaselineRemoteCompliance @remoteParams

		$remoteResults | Format-Table -Property @(
			@{ Label = 'Computer'; Expression = { $_.ComputerName }; Width = 20 }
			@{ Label = 'Compliant'; Expression = { $_.Compliant }; Width = 10 }
			@{ Label = 'Drifted'; Expression = { $_.DriftedCount }; Width = 8 }
			@{ Label = 'Checked'; Expression = { $_.TotalChecked }; Width = 8 }
			@{ Label = 'Errors'; Expression = { if ($_.Errors.Count -gt 0) { $_.Errors -join '; ' } else { '' } }; Width = 40 }
		) -AutoSize -Wrap

		if ($tempProfileCreated -and (Test-Path -LiteralPath $resolvedRemoteProfile)) { Remove-Item -LiteralPath $resolvedRemoteProfile -Force -ErrorAction SilentlyContinue }

		$anyDrift = @($remoteResults | Where-Object { -not $_.Compliant })
		if ($anyDrift.Count -gt 0) { return (Exit-BaselineBootstrap -Code 1) }
		return (Exit-BaselineBootstrap -Code 0)
	}
	else
	{
		# Remote apply mode.
		Write-Host "  Applying profile to $($reachableMachines.Count) machine(s)..." -ForegroundColor DarkGray
		Write-Host ''

		$remoteResults = Invoke-BaselineRemoteApply @remoteParams

		$remoteResults | Format-Table -Property @(
			@{ Label = 'Computer'; Expression = { $_.ComputerName }; Width = 20 }
			@{ Label = 'Applied'; Expression = { $_.Applied }; Width = 8 }
			@{ Label = 'Succeeded'; Expression = { $_.AppliedCount }; Width = 10 }
			@{ Label = 'Failed'; Expression = { $_.FailedCount }; Width = 8 }
			@{ Label = 'Errors'; Expression = { if ($_.Errors.Count -gt 0) { $_.Errors -join '; ' } else { '' } }; Width = 40 }
		) -AutoSize -Wrap

		if ($tempProfileCreated -and (Test-Path -LiteralPath $resolvedRemoteProfile)) { Remove-Item -LiteralPath $resolvedRemoteProfile -Force -ErrorAction SilentlyContinue }

		$anyFailed = @($remoteResults | Where-Object { -not $_.Applied })
		if ($anyFailed.Count -gt 0) { return (Exit-BaselineBootstrap -Code 1) }
		return (Exit-BaselineBootstrap -Code 0)
	}
}

# Compliance check mode: compare current system state against a saved profile.
if ($ComplianceCheck)
{
	# Close the bootstrap splash - compliance check does not use the GUI.
	if ($Script:BootstrapSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:BootstrapSplash -DisposeResources
		$Script:BootstrapSplash = $null
	}

	# Import the profile from the specified path.
	$complianceProfile = $null
	$resolvedProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath)
	if (-not (Test-Path -LiteralPath $resolvedProfilePath))
	{
		Write-Error "Profile file not found: $resolvedProfilePath"
		return (Exit-BaselineBootstrap -Code 1)
	}

	try
	{
		$profileContent = Get-Content -LiteralPath $resolvedProfilePath -Raw -ErrorAction Stop
		$complianceProfile = $profileContent | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		Write-Error "Failed to read profile '$resolvedProfilePath': $_"
		return (Exit-BaselineBootstrap -Code 1)
	}

	# Load the manifest for state detection.
	$complianceManifest = @(Import-TweakManifestFromData)
	if (-not $complianceManifest -or $complianceManifest.Count -eq 0)
	{
		Write-Error 'Failed to load tweak manifest for compliance checking.'
		return (Exit-BaselineBootstrap -Code 1)
	}

	# Run the compliance check.
	$complianceReport = Test-SystemCompliance -Profile $complianceProfile -Manifest $complianceManifest

	# Display formatted output.
	Write-Host ''
	Write-Host '  Baseline Compliance Check' -ForegroundColor Cyan
	Write-Host '  =========================' -ForegroundColor Cyan
	Write-Host "  Profile:  $resolvedProfilePath"
	Write-Host "  Machine:  $($complianceReport.MachineName)"
	Write-Host "  Time:     $($complianceReport.Timestamp)"
	Write-Host ''
	Write-Host "  Total Checked: $($complianceReport.TotalChecked)"
	Write-Host "  Compliant:     $($complianceReport.Compliant)" -ForegroundColor Green
	Write-Host "  Drifted:       $($complianceReport.Drifted)" -ForegroundColor $(if ($complianceReport.Drifted -gt 0) { 'Yellow' } else { 'Green' })
	Write-Host "  Unknown:       $($complianceReport.Unknown)" -ForegroundColor $(if ($complianceReport.Unknown -gt 0) { 'DarkGray' } else { 'Green' })
	Write-Host ''

	if ($complianceReport.Entries -and $complianceReport.Entries.Count -gt 0)
	{
		$complianceReport.Entries | Format-Table -Property @(
			@{ Label = 'Function'; Expression = { $_.Function }; Width = 30 }
			@{ Label = 'Name'; Expression = { $_.Name }; Width = 30 }
			@{ Label = 'Desired'; Expression = { if ($null -ne $_.DesiredState) { [string]$_.DesiredState } else { '(null)' } }; Width = 12 }
			@{ Label = 'Actual'; Expression = { if ($null -ne $_.ActualState) { [string]$_.ActualState } else { '(null)' } }; Width = 12 }
			@{ Label = 'Status'; Expression = { $_.Status }; Width = 10 }
		) -AutoSize -Wrap
	}

	$driftedEntries = Get-DriftedEntries -ComplianceReport $complianceReport
	if ($driftedEntries.Count -gt 0)
	{
		Write-Host '  Drifted entries:' -ForegroundColor Yellow
		foreach ($driftEntry in @($driftedEntries))
		{
			$desiredText = if ($null -ne $driftEntry.DesiredState) { [string]$driftEntry.DesiredState } else { '(null)' }
			$actualText  = if ($null -ne $driftEntry.ActualState)  { [string]$driftEntry.ActualState }  else { '(null)' }
			Write-Host "    - $($driftEntry.Name) ($($driftEntry.Function)): desired=$desiredText, actual=$actualText" -ForegroundColor Yellow
		}

		Write-Host ''
		Write-Host '  Fix commands:' -ForegroundColor Cyan
		$fixList = Get-ComplianceFixList -ComplianceReport $complianceReport -Manifest $complianceManifest
		foreach ($fixCmd in @($fixList))
		{
			Write-Host "    $fixCmd"
		}
		Write-Host ''
	}

	# When running as a scheduled task, write an audit record automatically.
	if ($ScheduledRun)
	{
		$scheduledDetails = [ordered]@{
			TotalChecked = [int]$complianceReport.TotalChecked
			Compliant    = [int]$complianceReport.Compliant
			Drifted      = [int]$complianceReport.Drifted
			Unknown      = [int]$complianceReport.Unknown
		}

		Write-AuditRecord -Action 'ScheduledComplianceCheck' -Mode 'Compliance' -ProfilePath $resolvedProfilePath -Details $scheduledDetails
	}

	# Exit with appropriate code.
	if ($complianceReport.Drifted -gt 0)
	{
		return (Exit-BaselineBootstrap -Code 1)
	}
	return (Exit-BaselineBootstrap -Code 0)
}

# Profile apply mode: load a saved configuration profile and apply every entry to
# the local machine without opening the GUI.
# Usage:  Baseline.exe -ProfilePath .\MyConfig.json -ApplyProfile
function New-BaselineManifestFunctionAllowList
{
	param(
		[Parameter(Mandatory = $true)]
		[object[]]$Manifest
	)

	$allowList = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($entry in @($Manifest))
	{
		$functionName = Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function'
		if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
		{
			$allowList[[string]$functionName] = $true
		}
	}

	return $allowList
}

function Test-BaselineManifestFunctionAllowed
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$FunctionName,

		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$AllowList
	)

	if ([string]::IsNullOrWhiteSpace($FunctionName)) { return $false }
	return [bool]$AllowList.Contains($FunctionName)
}

if ($ApplyProfile)
{
	# Close the bootstrap splash - headless mode does not use the GUI.
	if ($Script:BootstrapSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:BootstrapSplash -DisposeResources
		$Script:BootstrapSplash = $null
	}

	# Resolve and load the profile.
	$applyResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath)
	if (-not (Test-Path -LiteralPath $applyResolvedPath))
	{
		Write-Error "Profile file not found: $applyResolvedPath"
		return (Exit-BaselineBootstrap -Code 1)
	}

	$applyProfile = $null
	try
	{
		$applyProfile = Get-Content -LiteralPath $applyResolvedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		Write-Error "Failed to read profile '$applyResolvedPath': $_"
		return (Exit-BaselineBootstrap -Code 1)
	}

	try
	{
		Import-ConfigurationProfileIncludeLibraries -Profile $applyProfile
	}
	catch
	{
		Write-Error "Failed to import include libraries from profile '$applyResolvedPath': $_"
		return (Exit-BaselineBootstrap -Code 1)
	}

	$profileSelections = if ($applyProfile.PSObject.Properties['Selections']) { @($applyProfile.Selections) } else { @() }
	$profileAppActions = if ($applyProfile.PSObject.Properties['AppActions']) { @($applyProfile.AppActions) } else { @() }
	$profilePreferredSource = if ($applyProfile.PSObject.Properties['AppsPackageSourcePreference']) { [string]$applyProfile.AppsPackageSourcePreference } else { $null }

	<#
	    .SYNOPSIS
	#>

	function Get-ApplyProfileApplicationIdentityKey
	{
		param ([object]$Entry)

		if (-not $Entry) { return $null }

		$entityType = $null
		try
		{
			$entityType = Get-ApplicationEntityType -Entry $Entry
		}
		catch
		{
			$entityType = $null
		}

		$topLevelWinGetId = $null
		$topLevelChocoId = $null
		try
		{
			if ($Entry.PSObject.Properties['WinGetId'])
			{
				$topLevelWinGetId = [string]$Entry.WinGetId
			}
			if ($Entry.PSObject.Properties['ChocoId'])
			{
				$topLevelChocoId = [string]$Entry.ChocoId
			}
		}
		catch
		{
			$null = $_
		}

		if (-not [string]::IsNullOrWhiteSpace($topLevelWinGetId))
		{
			return ("winget:{0}" -f [string]$topLevelWinGetId.Trim().ToLowerInvariant())
		}

		if (-not [string]::IsNullOrWhiteSpace($topLevelChocoId))
		{
			return ("choco:{0}" -f [string]$topLevelChocoId.Trim().ToLowerInvariant())
		}

		if ($Entry.ExtraArgs)
		{
			try
			{
				if ($Entry.ExtraArgs.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.WinGetId))
				{
					return ("winget:{0}" -f [string]$Entry.ExtraArgs.WinGetId.Trim().ToLowerInvariant())
				}
				if ($Entry.ExtraArgs.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.ExtraArgs.ChocoId))
				{
					return ("choco:{0}" -f [string]$Entry.ExtraArgs.ChocoId.Trim().ToLowerInvariant())
				}
			}
			catch
			{
				$null = $_
			}
		}

		$name = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.Name)) { [string]$Entry.Name.Trim().ToLowerInvariant() } else { '<unknown>' }
		$subCategory = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.SubCategory)) { [string]$Entry.SubCategory.Trim().ToLowerInvariant() } else { '<none>' }
		if ([string]::IsNullOrWhiteSpace([string]$entityType))
		{
			$entityType = 'application'
		}

		return ("{0}:{1}:{2}" -f [string]$entityType, $subCategory, $name)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-ApplyProfileApplicationsCatalog
	{
		[CmdletBinding()]
		param ()

		if ($Script:ApplyProfileApplicationsCatalog -is [System.Collections.Generic.Dictionary[string, object]])
		{
			return ,$Script:ApplyProfileApplicationsCatalog
		}

		$catalog = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
		$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
		$catalogRoot = Join-Path -Path $moduleRoot -ChildPath 'Module\Data\AppsCategory'
		if (-not (Test-Path -LiteralPath $catalogRoot -PathType Container))
		{
			$Script:ApplyProfileApplicationsCatalog = $catalog
			return ,$Script:ApplyProfileApplicationsCatalog
		}

		foreach ($catalogFile in @(Get-ChildItem -LiteralPath $catalogRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name))
		{
			try
			{
				$catalogPayload = Get-Content -LiteralPath $catalogFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
				foreach ($entry in @($catalogPayload.Entries))
				{
					if (-not $entry) { continue }
					$entryId = Get-ApplyProfileApplicationIdentityKey -Entry $entry
					if ([string]::IsNullOrWhiteSpace($entryId) -or $catalog.ContainsKey($entryId)) { continue }
					$catalog[$entryId] = $entry
				}
			}
			catch
			{
				Write-Warning ("Skipping applications catalog file '{0}': {1}" -f $catalogFile.FullName, $_.Exception.Message)
			}
		}

		$Script:ApplyProfileApplicationsCatalog = $catalog
		return ,$Script:ApplyProfileApplicationsCatalog
	}

	<#
	    .SYNOPSIS
	#>

	function Resolve-ApplyProfileAppActionEntry
	{
		param (
			[object]$AppAction,
			[System.Collections.Generic.Dictionary[string, object]]$Catalog = $null
		)

		if (-not $AppAction) { return $null }

		$appId = $null
		$action = $null
		$name = $null
		$winGetId = $null
		$chocoId = $null
		$extraArgs = $null

		if ($AppAction -is [System.Collections.IDictionary])
		{
			$appId = if ($AppAction.Contains('AppId')) { [string]$AppAction['AppId'] } elseif ($AppAction.Contains('SelectionKey')) { [string]$AppAction['SelectionKey'] } else { $null }
			$action = if ($AppAction.Contains('Action')) { [string]$AppAction['Action'] } else { $null }
			$name = if ($AppAction.Contains('Name')) { [string]$AppAction['Name'] } else { $null }
			$winGetId = if ($AppAction.Contains('WinGetId')) { [string]$AppAction['WinGetId'] } else { $null }
			$chocoId = if ($AppAction.Contains('ChocoId')) { [string]$AppAction['ChocoId'] } else { $null }
			$extraArgs = if ($AppAction.Contains('ExtraArgs')) { $AppAction['ExtraArgs'] } else { $null }
		}
		elseif ($AppAction -is [pscustomobject] -or ($null -ne $AppAction.PSObject))
		{
			$appId = if ($AppAction.PSObject.Properties['AppId']) { [string]$AppAction.AppId } elseif ($AppAction.PSObject.Properties['SelectionKey']) { [string]$AppAction.SelectionKey } else { $null }
			$action = if ($AppAction.PSObject.Properties['Action']) { [string]$AppAction.Action } else { $null }
			$name = if ($AppAction.PSObject.Properties['Name']) { [string]$AppAction.Name } else { $null }
			$winGetId = if ($AppAction.PSObject.Properties['WinGetId']) { [string]$AppAction.WinGetId } else { $null }
			$chocoId = if ($AppAction.PSObject.Properties['ChocoId']) { [string]$AppAction.ChocoId } else { $null }
			$extraArgs = if ($AppAction.PSObject.Properties['ExtraArgs']) { $AppAction.ExtraArgs } else { $null }
		}

		if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($action))
		{
			return $null
		}

		$normalizedAction = [string]$action.Trim()
		if ($normalizedAction -notin @('Install', 'Uninstall'))
		{
			return $null
		}

		$resolvedEntry = $null
		if ($Catalog -and $Catalog.Count -gt 0)
		{
			$resolvedEntry = $null
			if ($Catalog.TryGetValue([string]$appId, [ref]$resolvedEntry))
			{
				$null = $resolvedEntry
			}
			else
			{
				$resolvedEntry = $null
			}
		}

		if ($resolvedEntry)
		{
			if ([string]::IsNullOrWhiteSpace($name) -and $resolvedEntry.PSObject.Properties['Name']) { $name = [string]$resolvedEntry.Name }
			if ([string]::IsNullOrWhiteSpace($winGetId) -and $resolvedEntry.PSObject.Properties['WinGetId']) { $winGetId = [string]$resolvedEntry.WinGetId }
			if ([string]::IsNullOrWhiteSpace($chocoId) -and $resolvedEntry.PSObject.Properties['ChocoId']) { $chocoId = [string]$resolvedEntry.ChocoId }
			if (-not $extraArgs -and $resolvedEntry.PSObject.Properties['ExtraArgs']) { $extraArgs = $resolvedEntry.ExtraArgs }
		}

		if ([string]::IsNullOrWhiteSpace($name))
		{
			$name = if (-not [string]::IsNullOrWhiteSpace($winGetId)) { $winGetId } elseif (-not [string]::IsNullOrWhiteSpace($chocoId)) { $chocoId } else { [string]$appId }
		}

		return [pscustomobject]@{
			AppId = [string]$appId
			Action = $normalizedAction
			Name = $name
			WinGetId = $winGetId
			ChocoId = $chocoId
			ExtraArgs = $extraArgs
			SelectionKey = [string]$appId
			EntityType = if ($resolvedEntry -and $resolvedEntry.PSObject.Properties['EntityType']) { [string]$resolvedEntry.EntityType } elseif ($resolvedEntry -and $resolvedEntry.PSObject.Properties['Type']) { [string]$resolvedEntry.Type } else { $null }
			SubCategory = if ($resolvedEntry -and $resolvedEntry.PSObject.Properties['SubCategory']) { [string]$resolvedEntry.SubCategory } else { $null }
			SupportsExecution = if ($resolvedEntry -and $resolvedEntry.PSObject.Properties['SupportsExecution']) { [bool]$resolvedEntry.SupportsExecution } else { $true }
		}
	}

	if ($profileSelections.Count -eq 0 -and $profileAppActions.Count -eq 0)
	{
		Write-Warning "Profile '$applyResolvedPath' contains no selections. Nothing to apply."
		return (Exit-BaselineBootstrap -Code 0)
	}

	$applyFunctions = [System.Collections.Generic.List[string]]::new()
	$applyValidationErrors = 0
	$applyFunctionAllowList = $null
	if ($profileSelections.Count -gt 0)
	{
		$applyManifest = @(Import-TweakManifestFromData)
		if (-not $applyManifest -or $applyManifest.Count -eq 0)
		{
			Write-Error 'Failed to load tweak manifest for profile apply.'
			return (Exit-BaselineBootstrap -Code 1)
		}
		$applyFunctionAllowList = New-BaselineManifestFunctionAllowList -Manifest $applyManifest

		foreach ($sel in $profileSelections)
		{
			$fn = if ($sel.PSObject.Properties['Function']) { [string]$sel.Function } else { $null }
			if ([string]::IsNullOrWhiteSpace($fn)) { continue }
			if (-not (Test-BaselineManifestFunctionAllowed -FunctionName $fn -AllowList $applyFunctionAllowList))
			{
				LogError "Profile function '$fn' is not declared in the tweak manifest and will not be invoked."
				$applyValidationErrors++
				continue
			}

			$type = if ($sel.PSObject.Properties['Type']) { [string]$sel.Type } else { 'Toggle' }

			$callLine = switch ($type)
			{
				'Choice'
				{
					$v = if ($sel.PSObject.Properties['SelectedValue']) { [string]$sel.SelectedValue } else { $null }
					if ([string]::IsNullOrWhiteSpace($v)) { $fn } else { "$fn -$v" }
				}
				'NumericRange'
				{
					if ($sel.PSObject.Properties['ACValue'] -or $sel.PSObject.Properties['DCValue'])
					{
						$ac = if ($sel.PSObject.Properties['ACValue']) { [string]$sel.ACValue } else { $null }
						$dc = if ($sel.PSObject.Properties['DCValue']) { [string]$sel.DCValue } else { $null }
						$parts = @()
						if (-not [string]::IsNullOrWhiteSpace($ac)) { $parts += "-ACValue $(ConvertTo-HeadlessCommandArgumentLiteral -Value $ac)" }
						if (-not [string]::IsNullOrWhiteSpace($dc)) { $parts += "-DCValue $(ConvertTo-HeadlessCommandArgumentLiteral -Value $dc)" }
						"$fn $($parts -join ' ')"
					}
					elseif ($sel.PSObject.Properties['Value'])
					{
						"$fn -Value $(ConvertTo-HeadlessCommandArgumentLiteral -Value ([string]$sel.Value))"
					}
					else { $fn }
				}
				'Date'
				{
					$run = if ($sel.PSObject.Properties['Run']) { [bool]$sel.Run } else { $false }
					if (-not $run) { continue }
					$dateParam = if ($sel.PSObject.Properties['DateParam']) { [string]$sel.DateParam } else { 'StartDate' }
					$dateVal   = if ($sel.PSObject.Properties['Value'])     { [string]$sel.Value }     else { $null }
					if ([string]::IsNullOrWhiteSpace($dateVal)) { $fn } else { "$fn -$dateParam $(ConvertTo-HeadlessCommandArgumentLiteral -Value $dateVal)" }
				}
				default
				{
					$param = if ($sel.PSObject.Properties['ToggleParam']) { [string]$sel.ToggleParam } else { $null }
					if ([string]::IsNullOrWhiteSpace($param)) { $fn } else { "$fn -$param" }
				}
			}

			if (-not [string]::IsNullOrWhiteSpace($callLine)) { $applyFunctions.Add($callLine) }
		}
	}

	$applyAppActions = [System.Collections.Generic.List[object]]::new()
	if ($profileAppActions.Count -gt 0)
	{
		$applyCatalog = Get-ApplyProfileApplicationsCatalog
		foreach ($appAction in $profileAppActions)
		{
			$resolvedAppAction = Resolve-ApplyProfileAppActionEntry -AppAction $appAction -Catalog $applyCatalog
			if ($resolvedAppAction)
			{
				$applyAppActions.Add($resolvedAppAction) | Out-Null
			}
		}
		if ($applyAppActions.Count -lt $profileAppActions.Count)
		{
			Write-Warning 'One or more queued app actions could not be resolved and were skipped.'
		}
	}

	if ($applyFunctions.Count -eq 0 -and $applyAppActions.Count -eq 0)
	{
		if ($applyValidationErrors -gt 0)
		{
			Write-Warning "Profile '$applyResolvedPath' did not contain any allowed tweak or app actions."
			$Global:LASTEXITCODE = 1
			return (Exit-BaselineBootstrap -Code 1)
		}

		Write-Warning "Profile '$applyResolvedPath' produced no applicable changes. Nothing to apply."
		$emptyExit = Get-BaselineHeadlessExitCode -Total 0
		Write-LaunchTrace ('Profile apply: no work selected, exitCode={0} reason={1}' -f [int]$emptyExit.ExitCode, [string]$emptyExit.Reason)
		$Global:LASTEXITCODE = [int]$emptyExit.ExitCode
		return (Exit-BaselineBootstrap -Code ([int]$emptyExit.ExitCode))
	}

	Write-Host ''
	Write-Host '  Baseline Profile Apply' -ForegroundColor Cyan
	Write-Host '  ======================' -ForegroundColor Cyan
	Write-Host "  Profile:  $applyResolvedPath"
	Write-Host "  Tweaks:   $($applyFunctions.Count)"
	Write-Host "  Apps:     $($applyAppActions.Count)"
	if (-not [string]::IsNullOrWhiteSpace($profilePreferredSource))
	{
		Write-Host "  Source:   $profilePreferredSource"
	}
	Write-Host ''

	Update-SessionStatistics -Values @{
		PresetName     = if ($applyProfile.PSObject.Properties['Name']) { [string]$applyProfile.Name } else { $null }
		TweaksSelected = $applyFunctions.Count
		AppsSelected   = $applyAppActions.Count
		IsGUI          = $false
	}

	if ($DryRun)
	{
		Write-Host '  Dry-run mode — no changes will be applied.' -ForegroundColor Yellow
		$idx = 0
		if ($applyFunctions.Count -gt 0)
		{
			Write-Host '  Tweak actions:' -ForegroundColor Cyan
			foreach ($call in $applyFunctions)
			{
				$idx++
				Write-Host "  [$idx] $call"
			}
		}
		if ($applyAppActions.Count -gt 0)
		{
			Write-Host '  App actions:' -ForegroundColor Cyan
			foreach ($appAction in $applyAppActions)
			{
				$idx++
				$appDisplayName = if (-not [string]::IsNullOrWhiteSpace([string]$appAction.Name)) { [string]$appAction.Name } elseif (-not [string]::IsNullOrWhiteSpace([string]$appAction.WinGetId)) { [string]$appAction.WinGetId } elseif (-not [string]::IsNullOrWhiteSpace([string]$appAction.ChocoId)) { [string]$appAction.ChocoId } else { [string]$appAction.AppId }
				Write-Host "  [$idx] $($appAction.Action) $appDisplayName"
			}
		}
		Write-Host ''
		Write-Host "  Total: $idx command$(if ($idx -ne 1) { 's' }) would be executed." -ForegroundColor Cyan
		$Global:LASTEXITCODE = 0
		return (Exit-BaselineBootstrap -Code 0)
	}

	$Global:BaselineHeadlessCommands = if ($applyFunctions.Count -gt 0) { $applyFunctions.ToArray() } else { @() }
	Invoke-BaselineInitialActions
        Add-SessionStatistic -Name 'ApplyRunCount'

        $applyErrors = [int]$applyValidationErrors
        $applyAppErrors = 0
        $applyFinalizationErrors = 0
        $applyFinalizationFailures = [System.Collections.Generic.List[string]]::new()
        try
        {
	foreach ($call in $applyFunctions)
	{
		$tokens = $null; $parseErrors = $null
		$commandAst = [System.Management.Automation.Language.Parser]::ParseInput($call, [ref]$tokens, [ref]$parseErrors)
		$statements = $commandAst.EndBlock.Statements
		if ($parseErrors.Count -gt 0 -or $statements.Count -ne 1 -or
			$statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or
			$statements[0].PipelineElements.Count -ne 1 -or
			$statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandAst])
		{
			LogError "Invalid command format '$call' — skipping."
			$applyErrors++
			continue
		}

		$cmdElement  = $statements[0].PipelineElements[0]
		$functionName = $cmdElement.GetCommandName()
		$resolvedCmd  = Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue
		if (-not (Test-BaselineManifestFunctionAllowed -FunctionName $functionName -AllowList $applyFunctionAllowList))
		{
			LogError "Function '$functionName' is not declared in the tweak manifest — skipping."
			$applyErrors++
			continue
		}
		if (-not $resolvedCmd)
		{
			LogError "Unknown function '$functionName' — skipping."
			$applyErrors++
			continue
		}

		try
		{
			$invocation = Get-HeadlessCommandInvocation -CommandAst $cmdElement
		}
		catch
		{
			LogError "Invalid command arguments for '$functionName': $($_.Exception.Message)"
			$applyErrors++
			continue
		}
		$namedArguments = $invocation.NamedArguments
		$positionalArguments = $invocation.PositionalArguments
		$operationScope = Start-BaselineOperationScope -Name $functionName
		$operationThrew = $false
		try
		{
			if ($namedArguments.Count -gt 0 -and $positionalArguments.Count -gt 0)
			{
				& $resolvedCmd @namedArguments @positionalArguments
			}
			elseif ($namedArguments.Count -gt 0)
			{
				& $resolvedCmd @namedArguments
			}
			elseif ($positionalArguments.Count -gt 0)
			{
				& $resolvedCmd @positionalArguments
			}
			else
			{
				& $resolvedCmd
			}
		}
		catch
		{
			Set-BaselineOperationFailed -Scope $operationScope -Reason $_.Exception.Message
			LogError "Function '$functionName' failed: $($_.Exception.Message)"
			$operationThrew = $true
		}
		$operationResult = Stop-BaselineOperationScope -Scope $operationScope
		if ($operationThrew -or ($operationResult -and [bool]$operationResult.Failed))
		{
			$applyErrors++
		}
		else
		{
			Add-SessionStatistic -Name 'SucceededCount'
		}
	}

	if ($applyAppActions.Count -gt 0)
	{
		foreach ($actionName in @('Install', 'Uninstall'))
		{
			$actionApplications = @($applyAppActions | Where-Object { [string]$_.Action -eq $actionName })
			if ($actionApplications.Count -eq 0) { continue }

			$actionResult = Invoke-AppBatchAction -Action $actionName -Applications $actionApplications -PreferredSource $profilePreferredSource
			if ($actionResult -and $actionResult.PSObject.Properties['FailureCount'])
			{
				$applyAppErrors += [int]$actionResult.FailureCount
			}
		}
	}
	}
	finally
	{
		# Always run PostActions/Errors and emit the structured exit code, even
		# if a tweak threw out of the loop above. Same tracked contract
		# the headless-functions path uses: never block, never throw, never pop
		# a dialog.
                try { Invoke-Command -ScriptBlock { PostActions; Errors } }
                catch
                {
                        $applyFinalizationErrors++
                        [void]$applyFinalizationFailures.Add(('PostActions: {0}' -f $_.Exception.Message))
                        Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.ApplyProfile.PostActions' -Severity Warning
                }

                try
                {
                        Write-AuditRecord -Action 'ProfileApply' -Mode 'Profile' -ProfilePath $applyResolvedPath -Details @{
                                Entries              = $applyFunctions.Count
                                AppActions           = $applyAppActions.Count
                                Failed               = ($applyErrors + $applyAppErrors + $applyFinalizationErrors)
                                FinalizationFailures = @($applyFinalizationFailures)
                        }
                }
                catch
                {
                        $applyFinalizationErrors++
                        [void]$applyFinalizationFailures.Add(('Audit: {0}' -f $_.Exception.Message))
                        Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.ApplyProfile.Audit' -Severity Warning
                }

                $applyTotal = [int]$applyFunctions.Count + [int]$applyAppActions.Count + [int]$applyFinalizationErrors
                $applyTotalFailed = [int]$applyErrors + [int]$applyAppErrors + [int]$applyFinalizationErrors
                $applySucceeded = $applyTotal - $applyTotalFailed
                if ($applySucceeded -lt 0) { $applySucceeded = 0 }
                $applyExit = Get-BaselineHeadlessExitCode -Total $applyTotal -Succeeded $applySucceeded -Failed $applyTotalFailed
                Write-LaunchTrace ('Profile apply finished: exitCode={0} reason={1} total={2} succeeded={3} failed={4} finalizationFailures={5}' -f [int]$applyExit.ExitCode, [string]$applyExit.Reason, $applyTotal, $applySucceeded, $applyTotalFailed, ($applyFinalizationFailures -join '; '))
                $Global:LASTEXITCODE = [int]$applyExit.ExitCode
        }
	return (Exit-BaselineBootstrap -Code ([int]$Global:LASTEXITCODE))
}

# Headless mode: run specific functions or a preset from the command line
if ($Functions)
{
	# Close the bootstrap splash - headless mode does not use the GUI.
	if ($Script:BootstrapSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:BootstrapSplash -DisposeResources
		$Script:BootstrapSplash = $null
	}

	$Global:BaselineHeadlessCommands = @($Functions)

	# Initialize session statistics for the headless run
	Update-SessionStatistics -Values @{
		PresetName     = if ($Preset) { $Preset } elseif ($GameModeProfile) { "GameMode:$GameModeProfile" } elseif ($ScenarioProfile) { "Scenario:$ScenarioProfile" } else { $null }
		TweaksSelected = $Functions.Count
		IsGUI          = $false
		GameModeActive = [bool]$GameModeProfile
		GameModeProfile = $GameModeProfile
	}

	$headlessManifest = @()
	try
	{
		$headlessManifest = @(Import-TweakManifestFromData)
	}
	catch
	{
		LogError "Failed to load tweak manifest for headless execution: $($_.Exception.Message)"
		$Global:LASTEXITCODE = 1
		return (Exit-BaselineBootstrap -Code 1)
	}
	if (-not $headlessManifest -or $headlessManifest.Count -eq 0)
	{
		LogError 'Failed to load tweak manifest for headless execution.'
		$Global:LASTEXITCODE = 1
		return (Exit-BaselineBootstrap -Code 1)
	}
	$headlessFunctionAllowList = New-BaselineManifestFunctionAllowList -Manifest $headlessManifest
	$dryRunManifest = if ($DryRun) { $headlessManifest } else { $null }

	if ($DryRun)
	{
		Write-Host ''
		Write-Host '  Baseline Dry Run' -ForegroundColor Cyan
		Write-Host '  ================' -ForegroundColor Cyan
		Write-Host "  Mode: $(if ($Preset) { "Preset '$Preset'" } elseif ($GameModeProfile) { "Game Mode '$GameModeProfile'" } elseif ($ScenarioProfile) { "Scenario '$ScenarioProfile'" } else { 'Direct functions' })"
		Write-Host "  Commands: $($Functions.Count)"
		Write-Host ''
	}
	else
	{
		Invoke-BaselineInitialActions
	}

	if (-not $DryRun)
	{
		Add-SessionStatistic -Name 'ApplyRunCount'
	}

	$dryRunOrder = 0
	$dryRunRejected = 0
	foreach ($Function in $Functions)
	{
		# Validate the command via AST parsing to ensure it is a single, simple
		# function call (no pipelines, semicolons, or subexpressions). Then verify
		# the function name exists in the loaded module scope before executing.
		$tokens = $null
		$parseErrors = $null
		$commandAst = [System.Management.Automation.Language.Parser]::ParseInput(
			$Function, [ref]$tokens, [ref]$parseErrors
		)

		$statements = $commandAst.EndBlock.Statements
		if ($parseErrors.Count -gt 0 -or
			$statements.Count -ne 1 -or
			$statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or
			$statements[0].PipelineElements.Count -ne 1 -or
			$statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandAst])
		{
			LogError "Invalid command format '$Function' - only simple function calls are allowed."
			if ($DryRun) { $dryRunRejected++ } else { Add-SessionStatistic -Name 'FailedCount' }
			continue
		}

			$commandElement = $statements[0].PipelineElements[0]
			$functionName = $commandElement.GetCommandName()
			if (-not (Test-BaselineManifestFunctionAllowed -FunctionName $functionName -AllowList $headlessFunctionAllowList))
			{
				LogError "Function '$functionName' is not declared in the tweak manifest and will not be invoked."
				if ($DryRun) { $dryRunRejected++ } else { Add-SessionStatistic -Name 'FailedCount' }
				continue
			}

			$resolvedCommand = Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue
			if (-not $resolvedCommand)
			{
				LogError "Unknown function '$functionName' - skipping. Only functions loaded by the Baseline module are allowed."
				if ($DryRun) { $dryRunRejected++ } else { Add-SessionStatistic -Name 'FailedCount' }
				continue
			}

			try
			{
				$commandInvocation = Get-HeadlessCommandInvocation -CommandAst $commandElement
			}
			catch
			{
				LogError "Invalid command arguments for '$functionName': $($_.Exception.Message)"
				if ($DryRun) { $dryRunRejected++ } else { Add-SessionStatistic -Name 'FailedCount' }
				continue
			}

			if ($DryRun)
			{
				$dryRunOrder++
				$commandArgs = @($commandInvocation.DisplayArguments)
				$argsDisplay = if ($commandArgs.Count -gt 0) { " $($commandArgs -join ' ')" } else { '' }

				# Look up manifest metadata when available for richer output.
				$manifestEntry = $null
				if ($dryRunManifest)
				{
					$lookupCmd = Get-Command -Name 'Get-ManifestEntryByFunction' -CommandType Function -ErrorAction SilentlyContinue
					if ($lookupCmd)
					{
						$manifestEntry = & $lookupCmd -Manifest $dryRunManifest -Function $functionName -ErrorAction SilentlyContinue
					}
				}

				# Read manifest fields through the canonical accessor so dry-run
				# output handles dictionary-shaped and PSCustomObject-shaped entries
				# identically (and stays in sync with the rest of the codebase).
				$riskValue = if ($manifestEntry) { Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Risk' } else { $null }
				$categoryValue = if ($manifestEntry) { Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Category' } else { $null }
				$restartValue = if ($manifestEntry) { Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'RequiresRestart' } else { $null }
				$restorableValue = if ($manifestEntry) { Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Restorable' } else { $null }

				$risk = if ($null -ne $riskValue -and -not [string]::IsNullOrWhiteSpace([string]$riskValue)) { [string]$riskValue } else { '?' }
				$category = if ($null -ne $categoryValue -and -not [string]::IsNullOrWhiteSpace([string]$categoryValue)) { [string]$categoryValue } else { '?' }
				$restart = if ($null -ne $restartValue -and [bool]$restartValue) { 'Yes' } else { 'No' }
				$restorable = if ($null -eq $restorableValue) { '?' } elseif ([bool]$restorableValue) { 'Yes' } else { 'No' }

				$riskColor = switch ($risk) { 'High' { 'Red' }; 'Medium' { 'Yellow' }; default { 'Green' } }

				Write-Host ("  {0,3}. {1}{2}" -f $dryRunOrder, $functionName, $argsDisplay)
				Write-Host ("        Category: {0}  |  Risk: " -f $category) -NoNewline
				Write-Host $risk -ForegroundColor $riskColor -NoNewline
				Write-Host ("  |  Restart: {0}  |  Restorable: {1}" -f $restart, $restorable)
			}
			else
			{
				# Safe to invoke: AST confirms single simple command, function is a known loaded function.
				# Bind named parameters through a dictionary so parameter sets resolve correctly.
				$namedArguments = $commandInvocation.NamedArguments
				$positionalArguments = $commandInvocation.PositionalArguments
				$operationScope = Start-BaselineOperationScope -Name $functionName
				$operationThrew = $false
				try
				{
					if ($namedArguments.Count -gt 0 -and $positionalArguments.Count -gt 0)
					{
						& $resolvedCommand @namedArguments @positionalArguments
					}
					elseif ($namedArguments.Count -gt 0)
					{
						& $resolvedCommand @namedArguments
					}
					elseif ($positionalArguments.Count -gt 0)
					{
						& $resolvedCommand @positionalArguments
					}
					else
					{
						& $resolvedCommand
					}
				}
				catch
				{
					Set-BaselineOperationFailed -Scope $operationScope -Reason $_.Exception.Message
					LogError "Function '$functionName' failed: $($_.Exception.Message)"
					$operationThrew = $true
				}
				$operationResult = Stop-BaselineOperationScope -Scope $operationScope
				if ($operationThrew -or ($operationResult -and [bool]$operationResult.Failed))
				{
					Add-SessionStatistic -Name 'FailedCount'
				}
				else
				{
					Add-SessionStatistic -Name 'SucceededCount'
				}
			}
	}

	if ($DryRun)
	{
		Write-Host ''
		Write-Host "  Total: $dryRunOrder command$(if ($dryRunOrder -ne 1) { 's' }) would be executed." -ForegroundColor Cyan
		Write-Host '  No changes were applied.' -ForegroundColor Cyan
		Write-Host ''
		$Global:LASTEXITCODE = if ($dryRunRejected -gt 0) { 1 } else { 0 }
		return (Exit-BaselineBootstrap -Code ([int]$Global:LASTEXITCODE))
	}

	# Always run PostActions/Errors and emit the structured exit code, even if a
	# tweak threw out of the loop above — the documented unattended contract
	# says we never block, never throw, never pop a dialog.
	try
	{
		Invoke-Command -ScriptBlock {PostActions; Errors}
	}
	finally
	{
		$sessionStats = Get-SessionStatistics
		$headlessSucceeded = if ($sessionStats -and $sessionStats.ContainsKey('SucceededCount')) { [int]$sessionStats['SucceededCount'] } else { 0 }
		$headlessFailed = if ($sessionStats -and $sessionStats.ContainsKey('FailedCount')) { [int]$sessionStats['FailedCount'] } else { 0 }
		$headlessTotal = [int]$Functions.Count
		$headlessExit = Get-BaselineHeadlessExitCode -Total $headlessTotal -Succeeded $headlessSucceeded -Failed $headlessFailed
		Write-LaunchTrace ('Headless function run finished: exitCode={0} reason={1} total={2} succeeded={3} failed={4}' -f [int]$headlessExit.ExitCode, [string]$headlessExit.Reason, $headlessTotal, $headlessSucceeded, $headlessFailed)
		$Global:LASTEXITCODE = [int]$headlessExit.ExitCode
	}
	return (Exit-BaselineBootstrap -Code ([int]$Global:LASTEXITCODE))
}

# Restart under Windows PowerShell 5.1 unless we are already running there
Restart-Script -ScriptPath $MyInvocation.MyCommand.Path -Preset $Preset -GameModeProfile $GameModeProfile -ScenarioProfile $ScenarioProfile -Functions $Functions -Include $Include -DryRun:$DryRun

# WPF requires an STA thread. If Windows PowerShell was launched with -MTA,
# restart just the GUI path in a clean STA host before any windows are created.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA)
{
	$staHost = (Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue).Source
	if (-not $staHost)
	{
		throw 'Baseline GUI requires an STA PowerShell host, but powershell.exe was not found.'
	}

	if (-not (Test-Path -LiteralPath $MyInvocation.MyCommand.Path))
	{
		throw "Baseline GUI could not restart in STA mode because the script path was not found: $($MyInvocation.MyCommand.Path)"
	}

	Write-Warning 'Baseline GUI requires STA. Restarting in Windows PowerShell STA mode...'
	$staArgumentList = [System.Collections.Generic.List[string]]::new()
	[void]$staArgumentList.Add('-STA')
	[void]$staArgumentList.Add('-ExecutionPolicy')
	[void]$staArgumentList.Add((Get-ExecutionPolicy).ToString())
	[void]$staArgumentList.Add('-NoProfile')
	[void]$staArgumentList.Add('-File')
	[void]$staArgumentList.Add($MyInvocation.MyCommand.Path)
	foreach ($argument in @(New-BaselineElevationArgumentList))
	{
		[void]$staArgumentList.Add([string]$argument)
	}
	Start-Process -FilePath $staHost -ArgumentList $staArgumentList.ToArray()
	return (Exit-BaselineBootstrap -Code 0)
}

# Signal to InitialActions/PostActions that we are running in GUI mode.
# Region modules check this flag to skip the "Press Enter to close" prompt
# and suppress PostActions from running during startup.
$Global:GUIMode = $true
$Global:DesignMode = [bool]$Design

# Mark the session as GUI mode for the session summary
Update-SessionStatistics -Values @{ IsGUI = $true }

# Show a WPF loading splash while startup checks run
$Script:LoadingSplash = $Script:BootstrapSplash
$Global:LoadingSplash = $Script:LoadingSplash
Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'before initial checks'

# Run configured startup checks (no menu prompt).
try
{
	$startupWinGetFrequency = if ($Script:StartupSplashSettings -and $Script:StartupSplashSettings.PSObject.Properties['WinGetCheckFrequency']) { [string]$Script:StartupSplashSettings.WinGetCheckFrequency } else { 'Startup' }
	$startupChocolateyFrequency = if ($Script:StartupSplashSettings -and $Script:StartupSplashSettings.PSObject.Properties['ChocolateyCheckFrequency']) { [string]$Script:StartupSplashSettings.ChocolateyCheckFrequency } else { 'Startup' }
	$runStartupWinGetCheck = Test-BaselineStartupPackageManagerCheckDue -PackageManager 'WinGet' -Enabled:($Script:StartupSplashSettings -and [bool]$Script:StartupSplashSettings.CheckWinGet) -Frequency $startupWinGetFrequency
	$runStartupChocolateyCheck = Test-BaselineStartupPackageManagerCheckDue -PackageManager 'Chocolatey' -Enabled:($Script:StartupSplashSettings -and [bool]$Script:StartupSplashSettings.CheckChocolatey) -Frequency $startupChocolateyFrequency
	$skipStartupWinGetCheck = -not [bool]$runStartupWinGetCheck
	$skipStartupChocolateyCheck = -not [bool]$runStartupChocolateyCheck
	try
	{
		LogDebug ('Startup splash execution resolved. RunInitialActions={0}; CheckWinGet={1}; WinGetFrequency="{2}"; WinGetDue={3}; WinGetSkip={4}; CheckChocolatey={5}; ChocolateyFrequency="{6}"; ChocolateyDue={7}; ChocolateySkip={8}' -f [bool]($Script:StartupSplashSettings -and $Script:StartupSplashSettings.RunInitialActions), [bool]($Script:StartupSplashSettings -and $Script:StartupSplashSettings.CheckWinGet), $startupWinGetFrequency, [bool]$runStartupWinGetCheck, [bool]$skipStartupWinGetCheck, [bool]($Script:StartupSplashSettings -and $Script:StartupSplashSettings.CheckChocolatey), $startupChocolateyFrequency, [bool]$runStartupChocolateyCheck, [bool]$skipStartupChocolateyCheck)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.StartupSplashExecution.LogDebug' -Severity Warning
	}

	if ($Script:StartupSplashSettings -and -not [bool]$Script:StartupSplashSettings.RunInitialActions)
	{
		Write-LaunchTrace 'InitialActions skipped by startup splash settings.'
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_InitialActionsSkippedByPreference' -Fallback 'Initial startup checks skipped by user preference.')
		try { LogDebug ('Initial startup checks skipped by preference while package-manager checks remain independently scheduled. WinGetSkip={0}; ChocolateySkip={1}' -f [bool]$skipStartupWinGetCheck, [bool]$skipStartupChocolateyCheck) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.InitialActions.SkippedByPreferenceLogDebug' -Severity Warning }
	}
	else
	{
		Write-LaunchTrace ('InitialActions started (skipWinGet={0}; skipChocolatey={1})' -f [bool]$skipStartupWinGetCheck, [bool]$skipStartupChocolateyCheck)
		try { LogDebug ('Initial startup checks invoking with package-manager skip flags. SkipWinGet={0}; SkipChocolatey={1}' -f [bool]$skipStartupWinGetCheck, [bool]$skipStartupChocolateyCheck) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Bootstrap.InitialActions.InvokeLogDebug' -Severity Warning }
		Invoke-BaselineInitialActions -SkipWinGetCheck:$skipStartupWinGetCheck -SkipChocolateyCheck:$skipStartupChocolateyCheck
		Write-LaunchTrace 'InitialActions completed'
	}
	Invoke-BaselinePackageManagerStartupChecks -SkipWinGetCheck:$skipStartupWinGetCheck -SkipChocolateyCheck:$skipStartupChocolateyCheck
	Set-BaselineStartupPackageManagerChecksCompleted -WinGet:$runStartupWinGetCheck -Chocolatey:$runStartupChocolateyCheck
	Set-BaselineBootstrapSplashChecklistStep -StepId 'finalize' -Status 'in_progress' -SubAction ''
	Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'after initial checks'
}
catch
{
	$startupError = $_
	if ($Script:LoadingSplash -and $Script:LoadingSplash.IsAlive)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
	}
	$Script:LoadingSplash = $null
	$Global:LoadingSplash = $null
	Show-ConsoleWindow

	$startupErrorMessage = Get-ErrorDetailText -ErrorRecord $startupError
	LogError "GUI startup failed before the main window opened: $startupErrorMessage"
	Write-Error -ErrorRecord $startupError
	$friendlyStartupError = Get-BaselineErrorInfo -Exception $startupError.Exception -Context 'GUI startup'
	$friendlyStartupMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyStartupError -LogPath $Global:LogFilePath -IncludeLogPath

	try
	{
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		[System.Windows.MessageBox]::Show(
			$friendlyStartupMessage,
			$(if ($friendlyStartupError -and $friendlyStartupError.PSObject.Properties['Title']) { [string]$friendlyStartupError.Title } else { 'Baseline Startup Error' }),
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
Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'before GUI module import'
try
{
	Import-Module -Name (Join-Path $Script:ModuleRoot 'Logging.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUICommon.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUIExecution.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:RegionsRoot 'GUI.psm1') -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
	# Force-reimporting resets $script:LogFilePath to $null inside Logging.psm1 (each
	# module above has 'using module Logging.psm1' which re-runs the initializer).
	if ($global:LogFilePath) { Set-LogFile -Path $global:LogFilePath }
	Write-LaunchTrace 'GUI modules imported'
}
catch
{
	$importError = $_
	# Restore log path in case a -Force import reset it before failing
	if ($global:LogFilePath) { Set-LogFile -Path $global:LogFilePath }
	if ($Script:LoadingSplash -and $Script:LoadingSplash.IsAlive)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
	}
	$Script:LoadingSplash = $null
	$Global:LoadingSplash = $null
	Show-ConsoleWindow
	LogError "Failed to import GUI modules: $($importError.Exception.Message)"
	$friendlyImportError = Get-BaselineErrorInfo -Exception $importError.Exception -Context 'GUI module import'
	$friendlyImportMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyImportError -LogPath $Global:LogFilePath -IncludeLogPath

	try
	{
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		[System.Windows.MessageBox]::Show(
			$friendlyImportMessage,
			$(if ($friendlyImportError -and $friendlyImportError.PSObject.Properties['Title']) { [string]$friendlyImportError.Title } else { 'Baseline Startup Error' }),
			[System.Windows.MessageBoxButton]::OK,
			[System.Windows.MessageBoxImage]::Error
		) | Out-Null
	}
	catch
	{
		Write-Warning "Baseline failed while preparing the GUI. See the log file: $Global:LogFilePath"
	}

	throw
}

# Launch the WPF tweak-selection GUI - replaces the old preset file
try
{
	# Only hide the console once startup checks and GUI module imports have completed.
	# This keeps Windows 10 startup failures visible instead of silently disappearing.
	Hide-ConsoleWindow
Set-BaselineLogScope -Scope 'GUI'
Write-LaunchTrace 'Preparing GUI open'
Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'before Show-TweakGUI'
Show-TweakGUI
Write-LaunchTrace 'GUI opened'
if ($Script:LoadingSplash -and $Script:LoadingSplash.IsAlive)
{
	$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
}
$Script:LoadingSplash = $null
$Global:LoadingSplash = $null
}
catch
{
	$guiError = $_
	if ($Script:LoadingSplash -and $Script:LoadingSplash.IsAlive)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
	}
	$Script:LoadingSplash = $null
	$Global:LoadingSplash = $null
	Show-ConsoleWindow

	$guiErrorMessage = Get-ErrorDetailText -ErrorRecord $guiError
	LogError "GUI construction failed: $guiErrorMessage"
	Write-Error -ErrorRecord $guiError
	$friendlyGuiError = Get-BaselineErrorInfo -Exception $guiError.Exception -Context 'GUI construction'
	$friendlyGuiMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyGuiError -LogPath $Global:LogFilePath -IncludeLogPath

	try
	{
		Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
		[System.Windows.MessageBox]::Show(
			$friendlyGuiMessage,
			$(if ($friendlyGuiError -and $friendlyGuiError.PSObject.Properties['Title']) { [string]$friendlyGuiError.Title } else { 'Baseline GUI Error' }),
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
