# Lightweight in-process perf tracer for the Baseline GUI.
# Activation: Debug Mode must be enabled, which sets BASELINE_PERF_LOG=1.
# When Debug Mode is off, Start/Stop scopes are near-zero-cost no-ops.
# Output: $env:LOCALAPPDATA\Temp\Baseline\perf.log (one line per scope: ISO8601, ms, name, note).

$Script:GuiPerfEnabled = $null
$Script:GuiPerfDetailedEnabled = $false
$Script:GuiPerfLogPath = $null
$Script:GuiPerfSink    = $null

function Test-GuiPerfTraceDebugEnabled
{
	[CmdletBinding()]
	param()

	if (Get-Command -Name 'Get-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { return [bool](Get-BaselineDebugLogging) }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'PerfTrace.TestGuiPerfTraceDebugEnabled.GetBaselineDebugLogging' }
	}

	if (Test-Path -Path Variable:\Script:DebugLoggingEnabled)
	{
		return [bool]$Script:DebugLoggingEnabled
	}

	return $false
}

function Set-GuiPerfTraceState
{
	[CmdletBinding()]
	param(
		[bool]$Enabled
	)

	if (-not $Enabled)
	{
		$Script:GuiPerfEnabled = $false
		$Script:GuiPerfLogPath = $null
		Remove-Item -Path Env:\BASELINE_PERF_LOG -ErrorAction SilentlyContinue
		return
	}

	$env:BASELINE_PERF_LOG = '1'
	Initialize-GuiPerfTrace
}

function Initialize-GuiPerfTrace
{
	[CmdletBinding()]
	param()

	$raw = [System.Environment]::GetEnvironmentVariable('BASELINE_PERF_LOG')
	$perfRequested = (-not [string]::IsNullOrWhiteSpace($raw)) -and ($raw -ne '0' -and $raw.ToLowerInvariant() -ne 'false' -and $raw.ToLowerInvariant() -ne 'off')
	$detailRaw = [System.Environment]::GetEnvironmentVariable('BASELINE_PERF_DETAIL')
	$Script:GuiPerfDetailedEnabled = (-not [string]::IsNullOrWhiteSpace($detailRaw)) -and ($detailRaw -ne '0' -and $detailRaw.ToLowerInvariant() -ne 'false' -and $detailRaw.ToLowerInvariant() -ne 'off')
	$debugEnabled = Test-GuiPerfTraceDebugEnabled
	$Script:GuiPerfEnabled = ($debugEnabled -and $perfRequested)

	if (-not $Script:GuiPerfEnabled) { return }

	$base = $env:LOCALAPPDATA
	if ([string]::IsNullOrWhiteSpace($base)) { $base = [System.IO.Path]::GetTempPath() }
	$dir = Join-Path $base 'Temp\Baseline'
	try
	{
		if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
		$Script:GuiPerfLogPath = Join-Path $dir 'perf.log'
		$stamp = (Get-Date).ToString('o')
		[System.IO.File]::AppendAllText($Script:GuiPerfLogPath, "# session $stamp pid=$PID`r`n", [System.Text.Encoding]::UTF8)
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'PerfTrace.InitializeGuiPerfTrace.WriteSessionHeader'
		$Script:GuiPerfEnabled = $false
	}
}

function Start-GuiPerfScope
{
	[CmdletBinding()]
	[OutputType([object])]
	param(
		[Parameter(Mandatory)][string]$Name,
		[string]$Note = '',
		[switch]$Detailed
	)

	if (-not $Script:GuiPerfEnabled) { return $null }
	if ($Detailed -and -not $Script:GuiPerfDetailedEnabled) { return $null }
	return [pscustomobject]@{
		Name = $Name
		Note = $Note
		Sw   = [System.Diagnostics.Stopwatch]::StartNew()
	}
}

function Stop-GuiPerfScope
{
	[CmdletBinding()]
	param(
		[object]$Scope,
		[string]$ExtraNote = ''
	)

	if (-not $Script:GuiPerfEnabled -or -not $Scope) { return }
	try
	{
		$Scope.Sw.Stop()
		$ms   = [int]$Scope.Sw.Elapsed.TotalMilliseconds
		$note = if ([string]::IsNullOrWhiteSpace($ExtraNote)) { $Scope.Note } else { $ExtraNote }
		$line = "{0} {1,6} ms  {2}  {3}`r`n" -f (Get-Date).ToString('HH:mm:ss.fff'), $ms, $Scope.Name, $note
		[System.IO.File]::AppendAllText($Script:GuiPerfLogPath, $line, [System.Text.Encoding]::UTF8)
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'PerfTrace.StopGuiPerfScope.AppendLine' }
}
