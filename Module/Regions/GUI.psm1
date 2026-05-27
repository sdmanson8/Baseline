using module ..\Logging.psm1
using module ..\SharedHelpers.psm1
using module ..\GUICommon.psm1
using module ..\GUIExecution.psm1

$Script:GuiLayout = GUICommon\Get-GuiLayout
$Script:GuiFontSizeWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Script:SetButtonChromeScript = $null

. (Join-Path $PSScriptRoot '..\GUI\PerfTrace.ps1')

function Set-ButtonChrome
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[System.Windows.Controls.Primitives.ButtonBase]$Button,
		[ValidateSet('Primary', 'Preview', 'Danger', 'DangerSubtle', 'Secondary', 'Subtle', 'Selection', 'SegmentNeutral')]
		[string]$Variant = 'Secondary',
		[switch]$Compact,
		[switch]$Muted
	)

	if ($Script:SetButtonChromeScript -isnot [scriptblock])
	{
		throw 'Set-ButtonChrome proxy is not initialized.'
	}

	& $Script:SetButtonChromeScript @PSBoundParameters
}

function Test-GuiStartupSplashLive
{
	param (
		[object]$Splash
	)

	if ($Splash -isnot [hashtable]) { return $false }
	if (-not $Splash.ContainsKey('IsAlive')) { return $false }
	if (Test-GuiStartupSplashAbortRequested -Splash $Splash) { return $false }
	if (-not [bool]$Splash.IsAlive) { return $false }

	if ($Splash.ContainsKey('WasRendered') -and [bool]$Splash.WasRendered) { return $true }
	if ($Splash.ContainsKey('Dispatcher') -and $null -ne $Splash.Dispatcher) { return $true }

	return $false
}

function Test-GuiStartupSplashAbortRequested
{
	param (
		[object]$Splash
	)

	if ($Splash -isnot [hashtable]) { return $false }
	if ($Splash.ContainsKey('AbortRequested') -and [bool]$Splash['AbortRequested']) { return $true }
	if ($Splash.ContainsKey('UserClosed') -and [bool]$Splash['UserClosed']) { return $true }
	if ($Splash.ContainsKey('ProgrammaticClose') -and [bool]$Splash['ProgrammaticClose']) { return $false }
	if ($Splash.ContainsKey('GuiReady') -and [bool]$Splash['GuiReady']) { return $false }
	if ($Splash.ContainsKey('IsAlive') -and $Splash.ContainsKey('WasRendered') -and [bool]$Splash.WasRendered -and (-not [bool]$Splash.IsAlive)) { return $true }

	return $false
}

function Stop-GuiStartupSplashAbortProcess
{
	param (
		[scriptblock]$Trace,
		[string]$Message = 'Startup splash closed before GUI readiness; aborting process'
	)

	if ($Trace -is [scriptblock])
	{
		try { & $Trace $Message } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Stop-GuiStartupSplashAbortProcess:catch71' -Severity Debug }
		 $null = $_ }
	}

	[System.Environment]::Exit(0)
	try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Stop-GuiStartupSplashAbortProcess:catch75' -Severity Debug }
	 $null = $_ }
}

function Start-GuiStartupSplashAbortWatchdog
{
	param (
		[object]$Splash
	)

	if ($Splash -isnot [hashtable]) { return $null }

	$watchRunspace = [runspacefactory]::CreateRunspace()
	$watchRunspace.ApartmentState = 'MTA'
	$watchRunspace.Open()
	$watchRunspace.SessionStateProxy.SetVariable('splash', $Splash)
	$watchPowerShell = [powershell]::Create()
	$watchPowerShell.Runspace = $watchRunspace
	[void]$watchPowerShell.AddScript({
		$traceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'Baseline'
		$tracePath = Join-Path $traceDirectory 'Baseline-launch-trace.txt'
		$trace = {
			param([string]$Message)
			try
			{
				if (-not [System.IO.Directory]::Exists($traceDirectory)) { [void][System.IO.Directory]::CreateDirectory($traceDirectory) }
				$line = ("{0:o} {1}`r`n" -f [DateTime]::UtcNow, $Message)
				$bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
				$stream = [System.IO.FileStream]::new($tracePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
				try { $stream.Write($bytes, 0, $bytes.Length) }
				finally { $stream.Dispose() }
			}
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Start-GuiStartupSplashAbortWatchdog:catch106' -Severity Debug }
			 $null = $_ }
		}

		& $trace 'StartupSplashAbortWatchdog: started'
		while ($true)
		{
			$abortRequested = $false
			if ($splash -is [hashtable])
			{
				if ($splash.ContainsKey('AbortRequested') -and [bool]$splash['AbortRequested']) { $abortRequested = $true }
				elseif ($splash.ContainsKey('UserClosed') -and [bool]$splash['UserClosed']) { $abortRequested = $true }
				elseif ($splash.ContainsKey('ProgrammaticClose') -and [bool]$splash['ProgrammaticClose']) { return }
				elseif ($splash.ContainsKey('GuiReady') -and [bool]$splash['GuiReady']) { return }
				elseif ($splash.ContainsKey('IsAlive') -and (-not [bool]$splash['IsAlive'])) { $abortRequested = $true }
			}
			else
			{
				return
			}

			if ($abortRequested)
			{
				& $trace 'StartupSplashAbortWatchdog: startup splash closed before GuiReady; aborting process'
				[System.Environment]::Exit(0)
				try { [System.Diagnostics.Process]::GetCurrentProcess().Kill() } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Start-GuiStartupSplashAbortWatchdog:catch130' -Severity Debug }
				 $null = $_ }
				return
			}

			Start-Sleep -Milliseconds 75
		}
	})

	return [pscustomobject]@{
		PowerShell  = $watchPowerShell
		Runspace    = $watchRunspace
		AsyncResult = $watchPowerShell.BeginInvoke()
	}
}

# Load GUI subsystem scripts during module import so Show-TweakGUI can call their top-level functions.
. (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'GUI' | Join-Path -ChildPath 'AppsModule.ps1')
. (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'GUI' | Join-Path -ChildPath 'UpdateOverlayModule.ps1')
. (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'GUI' | Join-Path -ChildPath 'LanguageCatalog.ps1')
<#
    .SYNOPSIS
    Return a validated font size for the current GUI layout.

    .DESCRIPTION
    Proxies to GUICommon\Get-GuiCommonSafeFontSize so region GUI code can resolve a layout key to a safe font size with a fallback value.

    .PARAMETER Key
    Layout key to resolve.

    .PARAMETER Default
    Fallback font size used when the key is missing or invalid.

    .PARAMETER Layout
    Layout object to read from. Defaults to the current GUI layout state.

    .EXAMPLE
    Get-GuiSafeFontSize -Key 'Body' -Default 12
#>
function Get-GuiSafeFontSize
{
	param(
		[Parameter(Mandatory = $true)]
		[string]$Key,
		[double]$Default = 12,
		[object]$Layout = $Script:GuiLayout
	)

	return GUICommon\Get-GuiCommonSafeFontSize -Key $Key -Default $Default -Layout $Layout
}

<#
    .SYNOPSIS
    Creates safe thickness.

    #>
function New-SafeThickness
{
	param(
		[double]$Left = 0,
		[double]$Top = 0,
		[double]$Right = 0,
		[double]$Bottom = 0,
		[Nullable[double]]$Uniform = $null
	)

	if ($null -ne $Uniform)
	{
		return [System.Windows.Thickness]::new([double]$Uniform)
	}

	return [System.Windows.Thickness]::new($Left, $Top, $Right, $Bottom)
}

<#
    .SYNOPSIS
    Creates WPF setter.

    #>

function New-WpfSetter
{
	param(
		[Parameter(Mandatory = $true)][System.Windows.DependencyProperty]$Property,
		[Parameter(Mandatory = $true)][object]$Value,
		[string]$TargetName
	)

	$setter = New-Object System.Windows.Setter
	$setter.Property = $Property
	$resolvedValue = $Value
	if ($null -ne $resolvedValue -and $resolvedValue -is [psobject])
	{
		$unwrappedValue = $resolvedValue.psobject.BaseObject
		if ($null -ne $unwrappedValue)
		{
			$resolvedValue = $unwrappedValue
		}
	}

	if (
		$null -ne $resolvedValue -and
		$Property.PropertyType -eq [System.Windows.Media.Brush] -and
		$resolvedValue -isnot [System.Windows.Media.Brush]
	)
	{
		try
		{
			if ($resolvedValue -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$resolvedValue))
			{
				if (Get-Command -Name 'ConvertTo-GuiBrush' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$resolvedValue = ConvertTo-GuiBrush -Color ([string]$resolvedValue) -Context 'New-WpfSetter'
				}
				else
				{
					$resolvedValue = [System.Windows.Media.Brush]([System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$resolvedValue))
				}
			}
			else
			{
				$resolvedValue = [System.Windows.Media.Brush]$resolvedValue
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.New-WpfSetter:catch253' -Severity Debug }

			$resolvedValue = $Value
		}
	}

	$setter.Value = $resolvedValue
	if (-not [string]::IsNullOrWhiteSpace($TargetName))
	{
		$setter.TargetName = $TargetName
	}

	return $setter
}

<#
    .SYNOPSIS
    Gets GUI runtime failure details.

    #>

function Get-GuiRuntimeFailureDetails
{
	param (
		[string]$Context = 'GUI',
		[System.Exception]$Exception,
		[string[]]$DebugTrail
	)

	$errorLines = New-Object System.Collections.Generic.List[string]
	[void]$errorLines.Add(('GUI event failed: {0}' -f $Exception.Message))
	[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureExceptionType' -Fallback 'Exception type: {0}' -FormatArgs @($Exception.GetType().FullName)))
	$errorRecord = $null
	try
	{
		if ($Exception.PSObject.Properties['ErrorRecord'])
		{
			$errorRecord = $Exception.ErrorRecord
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Get-GuiRuntimeFailureDetails:catch293' -Severity Debug }

		$errorRecord = $null
	}
	if ($Exception.InnerException)
	{
		[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureInnerException' -Fallback 'Inner exception: {0}' -FormatArgs @($Exception.InnerException.Message)))
	}
	if ($errorRecord)
	{
		if ($errorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.InvocationInfo.PositionMessage))
		{
			[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureInvocation' -Fallback 'Invocation:'))
			[void]$errorLines.Add($errorRecord.InvocationInfo.PositionMessage.Trim())
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$errorRecord.ScriptStackTrace))
		{
			[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureScriptStackTrace' -Fallback 'Script stack trace:'))
			[void]$errorLines.Add($errorRecord.ScriptStackTrace.Trim())
		}
		if ($null -ne $errorRecord.TargetObject)
		{
			$targetType = try { $errorRecord.TargetObject.GetType().FullName } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Get-GuiRuntimeFailureDetails:catch315' -Severity Debug }
			 'unknown' }
			[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureTargetObjectType' -Fallback 'Target object type: {0}' -FormatArgs @($targetType)))
		}
	}
	if ($Exception.StackTrace)
	{
		[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailureStackTrace' -Fallback 'Stack trace:'))
		[void]$errorLines.Add($Exception.StackTrace.Trim())
	}

	if ($DebugTrail -and $DebugTrail.Count -gt 0)
	{
		[void]$errorLines.Add('')
		[void]$errorLines.Add((Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeFailurePresetDebugTrail' -Fallback 'Preset debug trail (most recent entries):'))
		$startIndex = [Math]::Max(0, $DebugTrail.Count - 15)
		for ($i = $startIndex; $i -lt $DebugTrail.Count; $i++)
		{
			[void]$errorLines.Add($DebugTrail[$i])
		}
	}

	return ($errorLines -join [Environment]::NewLine)
}

<#
    .SYNOPSIS
    Show GUI runtime failure.

    #>

function Show-GuiRuntimeFailure
{
	param (
		[string]$Context = 'GUI',
		[System.Exception]$Exception,
		[switch]$ShowDialog,
		[string[]]$DebugTrail
	)

	if (-not $Exception) { return $null }

	$errorText = Get-GuiRuntimeFailureDetails -Context $Context -Exception $Exception -DebugTrail $DebugTrail
	$writeBaselineErrorCommand = Get-Command -Name 'Write-BaselineError' -CommandType Function -ErrorAction SilentlyContinue
	if ($writeBaselineErrorCommand)
	{
		& $writeBaselineErrorCommand -Message $errorText -Scope $Context
	}
	else
	{
		$logErrorCommand = Get-Command -Name 'LogError' -CommandType Function,Alias -ErrorAction SilentlyContinue
		if ($logErrorCommand)
		{
			& $logErrorCommand -Message $errorText -Scope $Context
		}
		else
		{
			Write-Warning $errorText
		}
	}

	if ($ShowDialog -and $Script:MainForm -and $Script:CurrentTheme)
	{
		try
		{
			$friendlyError = Get-BaselineErrorInfo -Exception $Exception -Context $Context
			$friendlyTitle = if ($friendlyError -and $friendlyError.PSObject.Properties['Title']) { [string]$friendlyError.Title } else { 'GUI Error' }
			$friendlyMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyError -LogPath $Global:LogFilePath -IncludeLogPath
			$noopButtonChrome = { param($Button, $Variant) }
			GUICommon\Show-GuiCommonThemedDialog `
				-Theme $Script:CurrentTheme `
				-ApplyButtonChrome $noopButtonChrome `
				-OwnerWindow $Script:MainForm `
				-Title $friendlyTitle `
				-Message $friendlyMessage `
				-Buttons @('OK') `
				-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
				-AccentButton 'OK'
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Show-GuiRuntimeFailure:catch393' -Severity Debug }

			$null = $_
		}
	}

	return $errorText
}

<#
    .SYNOPSIS
    Writes GUI preset debug.

    #>

function Write-GuiPresetDebug
{
	param (
		[string]$Context = 'GUI',
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return }

	$debugMessage = "[Context={0}] {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Message
	$debugTrailText = "[GUIPreset] {0}" -f $debugMessage
	try
	{
		if (-not $Script:GuiPresetDebugTrail)
		{
			$Script:GuiPresetDebugTrail = [System.Collections.Generic.List[string]]::new()
		}
		[void]$Script:GuiPresetDebugTrail.Add($debugTrailText)
		while ($Script:GuiPresetDebugTrail.Count -gt 100)
		{
			$Script:GuiPresetDebugTrail.RemoveAt(0)
		}

		$loggedDebug = $false
		if (Get-Command -Name 'LogDebug' -CommandType Function,Alias -ErrorAction SilentlyContinue)
		{
			try
			{
				LogDebug -Message $debugMessage -Scope 'GUIPreset'
				$loggedDebug = $true
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Write-GuiPresetDebug:catch439' -Severity Debug }

				$loggedDebug = $false
			}
		}
		if (-not $loggedDebug -and (Get-Command -Name 'Write-BaselineDebug' -CommandType Function -ErrorAction SilentlyContinue))
		{
			Write-BaselineDebug -Message $debugMessage -Scope 'GUIPreset'
		}
	}
	catch
	{
		try
		{
			Write-Warning $debugTrailText
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Write-GuiPresetDebug:catch455' -Severity Debug }

			$null = $_
		}
	}
}

$Script:GuiPresetDebugScript = ${function:Write-GuiPresetDebug}

<#
    .SYNOPSIS
    Writes GUI runtime warning.

    #>

function Write-GuiRuntimeWarning
{
	param (
		[string]$Context,
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return }

	$warningKey = '{0}|{1}' -f $Context, $Message
	$shouldLog = $true
	if ($Script:GuiRuntimeWarnings)
	{
		try { $shouldLog = $Script:GuiRuntimeWarnings.Add($warningKey) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUI.Write-GuiRuntimeWarning:catch483' -Severity Debug }
		 $shouldLog = $true }
	}
	if (-not $shouldLog) { return }

	$warningText = Get-UxBilingualLocalizedString -Key 'GuiLogRuntimeWarning' -Fallback 'GUI runtime safeguard [{0}]: {1}' -FormatArgs @($(if ($Context) { $Context } else { 'GUI' }), $Message)
	if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
	{
		LogWarning $warningText
	}
	else
	{
		Write-Warning $warningText
	}
}


<#
	.SYNOPSIS
	WPF-based GUI that replaces the preset file (Bootstrap/Baseline.ps1).

	.DESCRIPTION
	Builds a modern two-tier tabbed WPF window from a tweak manifest.
	Each tweak is presented with clear Enable/Disable visual state,
	info icons for descriptions, and grouped caution warnings per tab.
	The GUI stays open for multiple runs and supports light/dark themes.

	.NOTES
	Tweak types
	  Toggle  - Enable/Disable or Show/Hide parameter pair
	  Choice  - Multiple named parameter sets (combo box)
	  Action  - No parameters; checkbox means "run this"

	Manifest field reference
	  Name            Display text
	  Category        Primary tab name
	  SubCategory     Secondary tab name (optional)
	  Function        PowerShell function to invoke
	  Type            Toggle | Choice | Action
	  OnParam         Parameter name for the "on" / positive state   (Toggle only)
	  OffParam        Parameter name for the "off" / negative state  (Toggle only)
	  Options         [string[]] of available parameter names        (Choice only)
	  DisplayOptions  [string[]] of friendly display names           (Choice only)
	  Default         $true/$false (Toggle/Action) or string (Choice)
	  WinDefault      The Windows-default value ($true/$false or string)
	  Description     Info tooltip text
	  Caution         $true if the tweak carries a CAUTION warning
	  CautionReason   Explanation of why this tweak is cautioned
	  ExtraArgs       Hashtable of additional arguments
	  Scannable       $true (default) if system-scan can detect state; $false to always allow re-run

	App catalog field reference
	  Name            Display text
	  SubCategory     Secondary grouping name
	  WinGetId        WinGet package identifier
	  ChocoId         Chocolatey package identifier
	  EntityType      winget | choco | store | direct | command | uwp | feature | system | placeholder
	  SupportsExecution  $true when the backend can execute the item
#>

#region Detect & Visibility Scriptblocks
# Defined in Module/GUI/DetectScriptblocks.ps1 and loaded so the hashtables
# land in this module's $Script: scope. Kept as a separate file because the
# block was nearly 400 lines of hashtable literal.
. (Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'GUI' | Join-Path -ChildPath 'DetectScriptblocks.ps1')
#endregion Detect & Visibility Scriptblocks

$Script:TweakManifest = @()
$Script:ManifestLoadedFromData = $false

# Defined at module scope so Show-TweakGUI can capture them once for deferred
# WPF event handlers and dispatcher callbacks.
function Test-IsSafeModeUX
{
	<#
	    .SYNOPSIS
	    Return whether the GUI is currently in Safe Mode.

	    .DESCRIPTION
	    Reads the script-scoped Safe Mode flag and returns it as a boolean for other GUI helpers.

	    .EXAMPLE
	    Test-IsSafeModeUX
	#>
	return ([bool]$Script:SafeMode)
}
<#
    .SYNOPSIS
    Checks is expert mode ux.

    #>
function Test-IsExpertModeUX { return ([bool]$Script:AdvancedMode) }
<#
    .SYNOPSIS
    Checks GUI run in progress.

    #>
function Test-GuiRunInProgress
{
	if ($Script:GuiState -and $Script:GuiState.Get -is [scriptblock])
	{
		$runInProgressState = & $Script:GuiState.Get 'RunInProgress'
		return [bool]$runInProgressState
	}

	if ($Script:Ctx -and $Script:Ctx.ContainsKey('Run') -and $Script:Ctx.Run -is [hashtable] -and $Script:Ctx.Run.ContainsKey('InProgress'))
	{
		return [bool]$Script:Ctx.Run.InProgress
	}

	return [bool]$Script:RunInProgress
}


#region GUI Builder
function Show-TweakGUI
{
	<#
		.SYNOPSIS
		Show the WPF tweak-selection GUI and execute selected tweaks.

		.DESCRIPTION
		Builds a modern two-tier tabbed WPF window from $Script:TweakManifest.
		The GUI stays open after each run so further changes can be made.
		Supports dark/light themes, system-scan to skip already-applied tweaks,
		info icons, caution sections, and linked toggles (PS7 <-> telemetry).

		.EXAMPLE
		Show-TweakGUI
	#>
	[CmdletBinding()]
	param ()

	Update-SessionStatistics -Values @{ IsGUI = $true }

	# Enable per-monitor DPI awareness before any WPF objects are created
	# so the window renders at native resolution on high-DPI displays.
	try { GUICommon\Initialize-GuiDpiAwareness } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ShowTweakGUI.InitializeGuiDpiAwareness' }

	# --- GUI function groups ---
	$Script:GuiExtractedRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'GUI'
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\StartupTrace.ps1')
	& $traceGuiStartup 'Show-TweakGUI start'
	if (Test-GuiStartupSplashAbortRequested -Splash $Global:LoadingSplash)
	{
		Stop-GuiStartupSplashAbortProcess -Trace $traceGuiStartup -Message 'Show-TweakGUI aborted because startup splash was closed before completion'
	}

	# Context Object and Observable State must load first - other GUI files reference $Script:Ctx
	. (Join-Path $Script:GuiExtractedRoot 'GuiContext.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'StateTransitions.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ObservableState.ps1')
	$Script:Ctx = New-GuiContext
	$Script:Ctx.Config.ExtractedRoot = $Script:GuiExtractedRoot
	$Script:AuditRetentionDays = [int]$Script:Ctx.UI.AuditRetentionDays
	$Script:DesignMode = [bool]$Global:DesignMode
	$Script:Ctx.UI.DesignMode = [bool]$Script:DesignMode
	if ($Script:Ctx.ContainsKey('Mode')) { $Script:Ctx.Mode.Design = [bool]$Script:DesignMode }
	& $traceGuiStartup 'Core context loaded'

	. (Join-Path $Script:GuiExtractedRoot 'UxPolicy.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'UserPreferences.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'UIDensity.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'SessionState.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'TweakAvailability.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DetectCache.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PreviewBuilders.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ExecutionSummary.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PresetManagement.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'GameModeUI.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'GameModeState.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PreflightChecks.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PlanSummaryPanel.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ExecutionOrchestration.ps1')
	& $traceGuiStartup 'Core GUI scripts loaded'

	$__baselineExtractedPartDidReturn = $false
	$__baselineExtractedPartHasReturnValue = $false
	$__baselineExtractedPartReturnValue = $null
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\ManifestImport.ps1')
	if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
	try
	{
		$Script:CurrentBaselineVersion = if (Get-Command -Name 'Get-BaselineDisplayVersion' -CommandType Function -ErrorAction SilentlyContinue) { [string](Get-BaselineDisplayVersion) } else { 'unknown' }
		Initialize-GuiDetectCache -BaselineVersion $Script:CurrentBaselineVersion
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ShowTweakGUI.InitializeDetectCache'
	}
	& $traceGuiStartup 'Manifest ready'

	# Write-GuiRuntimeWarning is defined at module scope so Dispatcher.BeginInvoke closures and .GetNewClosure() scriptblocks can resolve it.
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\WpfCategoryInitialization.ps1')

	. (Join-Path $Script:GuiExtractedRoot 'EventInfrastructure.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'GuiResponsivenessWatchdog.ps1')


	$Script:GuiEventHandlerStore = [System.Collections.Generic.List[object]]::new()
	$Script:GuiRuntimeCommandCache = @{}
	$Script:GuiFunctionCaptureCache = @{}
	$Script:ShowGuiRuntimeFailureScript = ${function:Show-ScopedGuiRuntimeFailure}
	$Script:TestGuiRunInProgressScript = ${function:Test-GuiRunInProgress}
	$Script:NewSafeBrushConverterScript = ${function:New-SafeBrushConverter}
	if ($Script:ShowGuiRuntimeFailureScript -isnot [scriptblock]) { throw "Show-ScopedGuiRuntimeFailure capture did not resolve to a scriptblock." }
	if ($Script:TestGuiRunInProgressScript -isnot [scriptblock]) { throw "Test-GuiRunInProgress capture did not resolve to a scriptblock." }
	if ($Script:NewSafeBrushConverterScript -isnot [scriptblock]) { throw "New-SafeBrushConverter capture did not resolve to a scriptblock." }

	$Script:DarkTheme = Repair-GuiThemePaletteWithReferences -Theme $Script:DarkTheme -ThemeName 'Dark'
	$Script:LightTheme = Repair-GuiThemePaletteWithReferences -Theme $Script:LightTheme -ThemeName 'Light'
	$Script:CurrentTheme = $Script:DarkTheme
	$Script:BrushCache = @{}
	$Script:SharedBrushConverter = [System.Windows.Media.BrushConverter]::new()
	$Script:SharedCardShadow = $null

	# Sync context - theme (read-only after init)
	$Script:Ctx.Theme.Dark = $Script:DarkTheme
	$Script:Ctx.Theme.Light = $Script:LightTheme
	$Script:Ctx.Theme.Current = $Script:CurrentTheme
	$Script:Ctx.Theme.CurrentName = 'Dark'
	$Script:Ctx.Theme.BrushConverter = $Script:SharedBrushConverter
	$Script:Ctx.Theme.BrushCache = $Script:BrushCache
	#endregion Theme colors

	Initialize-GuiIconSystem -ModuleRoot $Script:GuiModuleBasePath

	. (Join-Path $Script:GuiExtractedRoot 'StyleManagement.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'BackToTopButton.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DeveloperDiagnostics.ps1')
	$Script:SetButtonChromeScript = ${function:Set-GuiButtonChrome}
	if ($Script:SetButtonChromeScript -isnot [scriptblock]) { throw 'Set-GuiButtonChrome capture did not resolve to a scriptblock.' }
	& $traceGuiStartup 'Theme and icon systems ready'


	#region Themed Dialog

	. (Join-Path $Script:GuiExtractedRoot 'ExecutionSummaryDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DiffView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ComplianceView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'AuditView.ps1')


	. (Join-Path $Script:GuiExtractedRoot 'DialogHelpers.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ReviewMode.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'AddCustomAppDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'StartupManagerDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'RemovalPersistenceDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DeploymentMediaBuilderDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DeploymentMediaBuilderView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'UserFoldersDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'TabManagement.ps1')

	$guiWindowMinWidth  = $Script:GuiLayout.WindowMinWidth
	$guiWindowMinHeight = $Script:GuiLayout.WindowMinHeight

	#region XAML template
	$xamlPath = Join-Path $Script:GuiExtractedRoot 'MainWindow.xaml'
	if (-not (Test-Path -LiteralPath $xamlPath))
	{
		throw "Main window XAML resource is missing: $xamlPath"
	}
	$xamlText = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
	$xamlText = $xamlText.Replace('__GuiWindowMinWidth__', [string]$guiWindowMinWidth).Replace('__GuiWindowMinHeight__', [string]$guiWindowMinHeight)
	[xml]$XAML = $xamlText
	#endregion XAML template

	#region Window setup and control wiring
	. (Join-Path $Script:GuiExtractedRoot 'WindowSetup.ps1')
	#endregion
	& $traceGuiStartup 'Window setup complete'

	#region Helper: Apply theme
	. (Join-Path $Script:GuiExtractedRoot 'ApplyTheme.ps1')
	#endregion
	Initialize-GuiBackToTopButton -Window $Form -ScrollViewer $ContentScroll -AdditionalScrollViewers @($DeploymentMediaScroll, $AppsScroll) -Button $BtnBackToTop


	#region Helper: Create styled controls
	. (Join-Path $Script:GuiExtractedRoot 'StyledControlsSetup.ps1')
	#endregion
	#endregion


	#region Build controls for a set of tweaks
	. (Join-Path $Script:GuiExtractedRoot 'BuildTweakControls.ps1')
	#endregion

	#region Windows Update runtime panel
	. (Join-Path $Script:GuiExtractedRoot 'UpdatesPanel.ps1')
	#endregion

	#region Build tab content for a primary category
	. (Join-Path $Script:GuiExtractedRoot 'BuildTabContent.ps1')
	#endregion

	$Script:RunInProgress = $false

	# --- Observable State: reactive UI bindings ---
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\ObservableGuiState.ps1')

	# Subscriber: StatusText -> $StatusText.Text
	& $Script:GuiState.Subscribe 'StatusText' {
		param ($newValue)
		if ($StatusText)
		{
			$StatusText.Text = [string]$newValue
			$StatusText.Visibility = if ([string]::IsNullOrWhiteSpace([string]$newValue)) { 'Collapsed' } else { 'Visible' }
		}
	}

	# Subscriber: StatusForeground -> $StatusText.Foreground (color string -> WPF brush)
	& $Script:GuiState.Subscribe 'StatusForeground' {
		param ($newValue)
		if ($StatusText -and $newValue -and $Script:SharedBrushConverter)
		{
			try { $StatusText.Foreground = $Script:SharedBrushConverter.ConvertFromString([string]$newValue) }
			catch { Write-GuiRuntimeWarning -Context 'GuiState/StatusForeground' -Message $_.Exception.Message }
		}
	}

	# Subscriber: RunInProgress -> sync to $Script: and context
	& $Script:GuiState.Subscribe 'RunInProgress' {
		param ($newValue)
		$Script:RunInProgress = [bool]$newValue
		if ($Script:Ctx) { $Script:Ctx.Run.InProgress = [bool]$newValue }
	}

	# Sync context - UI references
	$Script:Ctx.UI.MainForm = $Form
	$Script:Ctx.UI.StatusText = $StatusText
	$Script:Ctx.Run.InProgress = $false

	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\WindowClosingHandler.ps1')

	$Script:StartupSessionSnapshot = $null
	$Script:StartupHydratePrimaryTab = 'Initial Setup'
	$Script:StartupRestoreSessionPending = $false
	$Script:StartupIsFirstRun = $true
	try
	{
		$Script:StartupIsFirstRun = [bool](Test-GuiFirstRunWelcomePending)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.ResolveStartupSession.FirstRunState'
		$Script:StartupIsFirstRun = $true
	}

	$startupRestoreLastSession = if ($null -ne $Script:RestoreLastSession) { [bool]$Script:RestoreLastSession } else { $true }
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\StartupSessionRestoreProbe.ps1')
	& $traceGuiStartup ("Startup session resolved: firstRun={0}; restorePending={1}; tab={2}" -f $Script:StartupIsFirstRun, $Script:StartupRestoreSessionPending, $Script:StartupHydratePrimaryTab)

	#region Build primary tabs
	. (Join-Path $Script:GuiExtractedRoot 'BuildPrimaryTabs.ps1')
	#endregion
	& $traceGuiStartup 'Primary tabs built'

	# Linked-toggle wiring is handled inline in Build-TweakRow (supports lazy tab building).

	$Script:ClearTabContentCacheScript = ${function:Clear-TabContentCache}
	$Script:UpdateCategoryFilterListScript = ${function:Update-CategoryFilterList}
	$Script:UpdateSearchResultsTabStateScript = ${function:Update-SearchResultsTabState}

	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\VisibleContentRefresh.ps1')

	# Subscribers: filter state -> sync $Script: variables and refresh UI
	$refreshVisibleContentCapture = $refreshVisibleContent
	foreach ($filterProp in @('RiskFilter', 'CategoryFilter', 'SelectedOnlyFilter', 'HighRiskOnlyFilter', 'RestorableOnlyFilter', 'GamingOnlyFilter'))
	{
		$propCapture = $filterProp
		& $Script:GuiState.Subscribe $filterProp {
			param ($newValue)
			Set-Variable -Name $propCapture -Value $newValue -Scope Script
			& $refreshVisibleContentCapture
		}.GetNewClosure()
	}

	. (Join-Path $Script:GuiExtractedRoot 'SearchFilterHandlers.ps1')

	. (Join-Path $Script:GuiExtractedRoot 'ActionHandlers.ps1')


	# Late-bind function captures for handlers that run from WPF event contexts
	# where Show-TweakGUI's local scope isn't on the call chain.
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\GuiScriptblockCaptures.ps1')
	Set-StaticControlTabOrder
	Set-GuiActionButtonsEnabled -Enabled $true
	& $traceGuiStartup 'Static controls initialized'

	$shouldRestoreLastSession = if ($null -ne $Script:RestoreLastSession) { [bool]$Script:RestoreLastSession } else { $true }
	$restoredSessionStatusText = Get-UxLocalizedString -Key 'GuiLogSessionRestoredPreviousState' -Fallback ''
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\StartupSessionRestoreApply.ps1')
	Update-GuiLocalizationStrings
	Update-PrimaryTabHeaders
	Sync-UxActionButtonText
	& $traceGuiStartup 'Initial localization and headers synced'

	$startBaselineDownloadScript = Get-GuiFunctionCapture -Name 'Start-BaselineDownload'
	$hideBaselineUpdateOverlayScript = Get-GuiFunctionCapture -Name 'Hide-BaselineUpdateOverlay'
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\UpdateDownloadHandler.ps1')

	$Script:UpdateOverlayPrimaryClickAction = $Script:DownloadStartEvent
	$Script:UpdateOverlaySecondaryClickAction = {
		if ($hideBaselineUpdateOverlayScript)
		{
			& $hideBaselineUpdateOverlayScript
		}
	}.GetNewClosure()
	if ($Script:UpdateOverlayState)
	{
		$Script:UpdateOverlayState.PrimaryAction = $Script:DownloadStartEvent
		$Script:UpdateOverlayState.SecondaryAction = $Script:UpdateOverlaySecondaryClickAction
		$Script:UpdateOverlayState.PrimaryCloses = $false
		$Script:UpdateOverlayState.SecondaryCloses = $true
	}

	# Resolve all first-run dependencies ONCE, here, while module scope is valid.
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\FirstRunAndSplashHandoff.ps1')
	$startupPresentationCompleted = $false
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1')
	& $traceGuiStartup 'ContentRendered startup handler registered'

	# When the startup splash is live, let the main window render without stealing focus.
	if (& $testGuiStartupSplashAbortBlock -Splash $startupSplashHandle)
	{
		Stop-GuiStartupSplashAbortProcess -Trace $traceGuiStartup -Message 'Show-TweakGUI aborted before ShowDialog because startup splash was closed'
	}
	$Form.ShowActivated = -not [bool]$hasLiveStartupSplash
	Initialize-WpfWindowForeground -Window $Form
	& $traceGuiStartup 'Window activation policy initialized'

	# Set Preview Run as the default-focused action so it feels like the natural next step.
	if ($BtnPreviewRun) { $BtnPreviewRun.Focusable = $true }
	& $traceGuiStartup 'Pre-show initialization complete'

	# Show the GUI
	. (Join-Path $PSScriptRoot '..\GUI\Show-TweakGUI\ShowDialogErrorHandling.ps1')

	LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogGuiClosed' -Fallback 'GUI closed')

	# Write local-only session summary to the log file at end of GUI session
	Write-SessionSummaryToLog
}
#endregion GUI Builder

#region Report-TweakProgress

function Write-TweakProgress
{
	<#
		.SYNOPSIS
		Reports sub-task progress from inside a tweak function back to the GUI progress bar.

		.DESCRIPTION
		Intended to be called from tweak functions that run in the background runspace during a
		GUI-mode execution.  The function enqueues a '_SubProgress' message into $Global:GUIRunState
		(set automatically by the GUI run loop).  The DispatcherTimer on the UI thread picks it up
		and updates the secondary progress bar below the main tweak progress bar.

		If the script is not running in GUI mode or $Global:GUIRunState is not set the call is a
		no-op, so it is safe to leave in tweak functions even when they are run headlessly.

		.PARAMETER Action
		Short label shown next to the percentage, e.g. "Downloading WinGet installer".

		.PARAMETER Completed
		Number of units completed.  Used together with -Total.

		.PARAMETER Total
		Total number of units.  When provided with -Completed the bar fills proportionally.

		.PARAMETER Percent
		0-100 percentage.  Use this instead of -Completed/-Total when only a percentage is available.

		.EXAMPLE
		# Inside a tweak function that downloads a file in chunks:
		for ($i = 0; $i -lt $chunks.Count; $i++)
		{
		    Write-TweakProgress -Action "Downloading installer" -Completed $i -Total $chunks.Count
		    # ... download chunk ...
		}
	#>
	[CmdletBinding()]
	param (
		[string]$Action    = $null,
		[int]   $Completed = 0,
		[int]   $Total     = 0,
		[int]   $Percent   = -1
	)

	if (-not $Global:GUIMode) { return }
	# $GUIRunState is the ConcurrentQueue injected directly by the GUI run loop via
	# SessionStateProxy.SetVariable - it is not a global, just a session variable.
	$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
	if (-not $queue) { return }

	$queue.Enqueue([PSCustomObject]@{
		Kind      = '_SubProgress'
		Action    = $Action
		Completed = $Completed
		Total     = $Total
		Percent   = $Percent
	})
}
#endregion Report-TweakProgress

Set-Alias -Name Report-TweakProgress -Value Write-TweakProgress -Scope Script
Export-ModuleMember -Function 'Show-TweakGUI', 'Write-TweakProgress' -Alias 'Report-TweakProgress'
