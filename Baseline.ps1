<#
	.SYNOPSIS
	WPF GUI for Windows 10 & Windows 11 fine-tuning and automating the routine tasks

    .VERSION
	3.0.0 (beta)

	.DATE
	17.03.2026 - initial beta version
	21.03.2026 - Added GUI
	06.04.2026 - Major changes to the GUI, and added more features

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
	.\Baseline.ps1 -Preset Basic

	.EXAMPLE Run a Game Mode profile non-interactively
	.\Baseline.ps1 -GameModeProfile Competitive

	.EXAMPLE Run a scenario profile non-interactively
	.\Baseline.ps1 -ScenarioProfile Privacy

	.EXAMPLE Run a troubleshooting Game Mode profile with explicit decision overrides
	.\Baseline.ps1 -GameModeProfile Troubleshooting -GameModeDecisionOverrides @{ FullscreenOptimizations = 'Disable'; MultiplaneOverlay = 'Disable' }

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

	[Parameter(Mandatory = $false)]
	[switch]
	$ScheduledRun,

	[Parameter(Mandatory = $false)]
	[string]
	$ProfilePath,

	[Parameter(Mandatory = $false)]
	[string[]]
	$TargetComputer,

	[Parameter(Mandatory = $false)]
	[System.Management.Automation.PSCredential]
	$RemoteCredential
)

Set-StrictMode -Version Latest
Clear-Host

$Script:BootstrapSplash = $null

#region InitialActions
$Script:RepoRoot = $PSScriptRoot
$Script:ModuleRoot = Join-Path $Script:RepoRoot 'Module'
$Script:ModuleRootExists = Test-Path -LiteralPath $Script:ModuleRoot -PathType Container
$Script:RegionsRoot = Join-Path $Script:ModuleRoot 'Regions'

$RequiredFiles = @(
    (Join-Path (Join-Path $Script:RepoRoot 'Localizations') 'en.json')
)

$RequiredFiles += if ($Script:ModuleRootExists)
{
	@(
		(Join-Path $Script:ModuleRoot 'SharedHelpers.psm1')
		(Join-Path (Join-Path $Script:ModuleRoot 'SharedHelpers') 'ErrorHandling.Helpers.ps1')
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

    exit
}

Import-Module -Name (Join-Path $Script:ModuleRoot 'SharedHelpers.psm1') -Force -ErrorAction Stop
$Script:BootstrapSplash = Show-BootstrapLoadingSplash
$osName = (Get-OSInfo).OSName
$Host.UI.RawUI.WindowTitle = "Baseline | Utility for $osName"

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

if ([string]::IsNullOrWhiteSpace($Preset) -and [string]::IsNullOrWhiteSpace($GameModeProfile) -and [string]::IsNullOrWhiteSpace($ScenarioProfile) -and -not $Functions)
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

# Load the JSON localization helper before module import.
. (Join-Path $Script:ModuleRoot 'SharedHelpers\Localization.Helpers.ps1')
$Global:Localization = Import-BaselineLocalization -BaseDirectory (Join-Path $Script:RepoRoot 'Localizations') -UICulture $PSUICulture

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

# Validate mutual exclusion using original bound parameters before any expansion.
$headlessModes = @($Preset, $GameModeProfile, $ScenarioProfile, $(if ($Functions) { 'Functions' })) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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

if ($DryRun -and -not $ComplianceCheck -and $headlessModes.Count -eq 0)
{
	throw 'Specify -Preset, -GameModeProfile, -ScenarioProfile, or -Functions when using -DryRun.'
}

if ($ComplianceCheck -and [string]::IsNullOrWhiteSpace($ProfilePath))
{
	throw 'Specify -ProfilePath when using -ComplianceCheck.'
}

if (-not [string]::IsNullOrWhiteSpace($ProfilePath) -and -not $ComplianceCheck -and -not $TargetComputer)
{
	throw 'Specify -ComplianceCheck when using -ProfilePath (unless -TargetComputer is also specified).'
}

if ($TargetComputer -and [string]::IsNullOrWhiteSpace($ProfilePath) -and -not $Preset)
{
	throw 'Specify -ProfilePath or -Preset when using -TargetComputer.'
}

if ($TargetComputer -and $Functions -and -not $Preset)
{
	throw '-TargetComputer cannot be combined with -Functions directly. Use -ProfilePath or -Preset instead.'
}

if ($GameModeProfile)
{
	$GameModeDecisionOverrides = Resolve-ValidatedGameModeDecisionOverrides -ProfileName $GameModeProfile -DecisionOverrides $GameModeDecisionOverrides
}

# Preset mode expands the requested preset into the same command list used by
# the headless path so the bootstrap can stay non-interactive.
if ($Preset)
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
		exit 1
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
		exit 1
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
		if ($anyDrift.Count -gt 0) { exit 1 }
		exit 0
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
		if ($anyFailed.Count -gt 0) { exit 1 }
		exit 0
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
		exit 1
	}

	try
	{
		$profileContent = Get-Content -LiteralPath $resolvedProfilePath -Raw -ErrorAction Stop
		$complianceProfile = $profileContent | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		Write-Error "Failed to read profile '$resolvedProfilePath': $_"
		exit 1
	}

	# Load the manifest for state detection.
	$complianceManifest = @(Import-TweakManifestFromData)
	if (-not $complianceManifest -or $complianceManifest.Count -eq 0)
	{
		Write-Error 'Failed to load tweak manifest for compliance checking.'
		exit 1
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
		exit 1
	}
	exit 0
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

	if ($DryRun)
	{
		Write-Host ''
		Write-Host '  Baseline Dry Run' -ForegroundColor Cyan
		Write-Host '  ================' -ForegroundColor Cyan
		Write-Host "  Mode: $(if ($Preset) { "Preset '$Preset'" } elseif ($GameModeProfile) { "Game Mode '$GameModeProfile'" } elseif ($ScenarioProfile) { "Scenario '$ScenarioProfile'" } else { 'Direct functions' })"
		Write-Host "  Commands: $($Functions.Count)"
		Write-Host ''

		# Load the manifest once so dry-run output can include risk/category metadata.
		$dryRunManifest = $null
		$importManifestCmd = Get-Command -Name 'Import-TweakManifestFromData' -CommandType Function -ErrorAction SilentlyContinue
		if ($importManifestCmd)
		{
			try { $dryRunManifest = @(& $importManifestCmd) } catch { $dryRunManifest = $null }
		}
	}
	else
	{
		Invoke-Command -ScriptBlock {InitialActions}
	}

	if (-not $DryRun)
	{
		Add-SessionStatistic -Name 'ApplyRunCount'
	}

	$dryRunOrder = 0
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
			Add-SessionStatistic -Name 'SkippedCount'
			continue
		}

		$commandElement = $statements[0].PipelineElements[0]
		$functionName = $commandElement.GetCommandName()
		$resolvedCommand = Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue
		if (-not $resolvedCommand)
		{
			LogError "Unknown function '$functionName' - skipping. Only functions loaded by the Baseline module are allowed."
			Add-SessionStatistic -Name 'SkippedCount'
			continue
		}

		if ($DryRun)
		{
			$dryRunOrder++
			$commandArgs = @($commandElement.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.SafeGetValue() })
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

			$risk = if ($manifestEntry -and $manifestEntry.PSObject.Properties['Risk']) { [string]$manifestEntry.Risk } else { '?' }
			$category = if ($manifestEntry -and $manifestEntry.PSObject.Properties['Category']) { [string]$manifestEntry.Category } else { '?' }
			$restart = if ($manifestEntry -and $manifestEntry.PSObject.Properties['RequiresRestart'] -and [bool]$manifestEntry.RequiresRestart) { 'Yes' } else { 'No' }
			$restorable = if ($manifestEntry -and $manifestEntry.PSObject.Properties['Restorable']) { if ([bool]$manifestEntry.Restorable) { 'Yes' } else { 'No' } } else { '?' }

			$riskColor = switch ($risk) { 'High' { 'Red' }; 'Medium' { 'Yellow' }; default { 'Green' } }

			Write-Host ("  {0,3}. {1}{2}" -f $dryRunOrder, $functionName, $argsDisplay)
			Write-Host ("        Category: {0}  |  Risk: " -f $category) -NoNewline
			Write-Host $risk -ForegroundColor $riskColor -NoNewline
			Write-Host ("  |  Restart: {0}  |  Restorable: {1}" -f $restart, $restorable)
		}
		else
		{
			# Safe to invoke: AST confirms single simple command, function is a known loaded function.
			# Use direct & invocation with AST-parsed arguments instead of Invoke-Expression.
			$commandArgs = @($commandElement.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.SafeGetValue() })
			$headlessTweakErrorBaseline = if ($Global:Error) { $Global:Error.Count } else { 0 }
			if ($commandArgs.Count -gt 0)
			{
				& $resolvedCommand @commandArgs
			}
			else
			{
				& $resolvedCommand
			}

			# Track success/failure by checking whether new errors appeared
			if ($Global:Error -and $Global:Error.Count -gt $headlessTweakErrorBaseline)
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
	}
	else
	{
		Invoke-Command -ScriptBlock {PostActions; Errors}
	}
	exit
}

# Restart Script in PowerShell 5.1 if running PowerShell 7
Restart-Script -ScriptPath $MyInvocation.MyCommand.Path -Preset $Preset -GameModeProfile $GameModeProfile -ScenarioProfile $ScenarioProfile -Functions $Functions -DryRun:$DryRun

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
	Start-Process -FilePath $staHost -ArgumentList @(
		'-STA',
		'-ExecutionPolicy', (Get-ExecutionPolicy).ToString(),
		'-NoProfile',
		'-File', $MyInvocation.MyCommand.Path
	) -WindowStyle Hidden
	exit
}

# Signal to InitialActions/PostActions that we are running in GUI mode.
# Region modules check this flag to skip the "Press Enter to close" prompt
# and suppress PostActions from running during startup.
$Global:GUIMode = $true

# Mark the session as GUI mode for the session summary
Update-SessionStatistics -Values @{ IsGUI = $true }

# Hide the console window before anything else runs - the splash is the only
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
try
{
	Import-Module -Name (Join-Path $Script:ModuleRoot 'Logging.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUICommon.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:ModuleRoot 'GUIExecution.psm1') -Force -ErrorAction Stop
	Import-Module -Name (Join-Path $Script:RegionsRoot 'GUI.psm1') -Force -ErrorAction Stop
	# Force-reimporting resets $script:LogFilePath to $null inside Logging.psm1 (each
	# module above has 'using module Logging.psm1' which re-runs the initializer).
	if ($global:LogFilePath) { Set-LogFile -Path $global:LogFilePath }
}
catch
{
	$importError = $_
	# Restore log path in case a -Force import reset it before failing
	if ($global:LogFilePath) { Set-LogFile -Path $global:LogFilePath }
	if ($Script:LoadingSplash)
	{
		$null = Close-LoadingSplashWindow -Splash $Script:LoadingSplash -DisposeResources
		$Script:LoadingSplash = $null
		$Global:LoadingSplash = $null
	}
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
