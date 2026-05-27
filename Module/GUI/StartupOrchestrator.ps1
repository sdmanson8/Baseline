$Script:StartupOrchestratorRan = $false

# Four-phase startup orchestrator.
# Phase 1 runs synchronously before the GUI builds rows (so NEW badges
# render correctly on the foreground tab). Phases 2-4 run on a background
# runspace after GuiReady=true so they don't block the dispatcher.
#
# Phase 1: NEW badge initialization (load AddedInVersions.json, compute
#          per-user baseline from saved prefs, decide which tweaks are new).
# Phase 2: First-launch config backup with 30s timeout. Snapshots every
#          tweak's Detect() result so the user has a return-to-previous
#          reference. One-shot, gated by the InitialConfigBackupCompleted
#          pref. On timeout the pref is left unset so the next launch
#          retries.
# Phase 3: Remove stale %LOCALAPPDATA%\Temp\Baseline\RC\<old-version>\
#          directories from prior launcher versions. Best-effort.
# Phase 4: Verify the on-disk GUI module against the bundled
#          integrity.manifest.json. Logs warnings on hash mismatch but
#          doesn't auto-rebuild — that's the launcher's job.

function Write-StartupOrchestratorLog
{
	param ([string]$Message)
	if (-not $env:BASELINE_PERF_LOG) { return }
	if (Get-Command -Name 'Get-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { if (-not [bool](Get-BaselineDebugLogging)) { return } }
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.PerfLog.GetDebugMode'; return }
	}
	elseif ((Test-Path -Path Variable:\Script:DebugLoggingEnabled) -and -not [bool]$Script:DebugLoggingEnabled)
	{
		return
	}
	else
	{
		return
	}
	try
	{
		$logPath = Join-Path $env:LOCALAPPDATA 'Temp\Baseline\perf.log'
		$line = '{0} [Startup] {1}{2}' -f ([DateTime]::UtcNow.ToString('o')), $Message, [Environment]::NewLine
		[System.IO.File]::AppendAllText($logPath, $line, [System.Text.Encoding]::UTF8)
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.PerfLog.Append' }
}

function Invoke-FirstLaunchConfigBackup
{
	param (
		[Parameter(Mandatory = $true)][object[]]$TweakManifest,
		[int]$TimeoutSeconds = 30,
		[string]$BaselineVersion,
		[object]$Dispatcher = $null
	)

	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$snapshot = New-Object System.Collections.Specialized.OrderedDictionary
	$timedOut = $false
	$processed = 0

	foreach ($tweak in @($TweakManifest))
	{
		if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $timedOut = $true; break }
		if (-not $tweak -or -not $tweak.Function -or -not $tweak.Detect) { continue }
		$functionName = [string]$tweak.Function
		# Prefer the live detection cache to avoid re-running Detect for
		# rows the foreground/pre-build tabs already probed. Cache hit is
		# a hashtable lookup; cache miss falls back to the live probe.
		$cached = $null
		try { $cached = Get-CachedDetection -Function $functionName } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.FirstLaunchBackup.GetCachedDetection' }
		if ($null -ne $cached)
		{
			$snapshot[$functionName] = [bool]$cached
		}
		else
		{
			try
			{
				$value = [bool](Invoke-GuiDetectScriptblock -Detect $tweak.Detect -DefaultValue ([bool]$tweak.Default))
				$snapshot[$functionName] = $value
				try { Set-CachedDetection -Function $functionName -Value $value } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.FirstLaunchBackup.SetCachedDetection' }
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.Invoke-FirstLaunchConfigBackup:catch83' -Severity Debug }

				$snapshot[$functionName] = $null
			}
		}
		$processed++
		# Yield every 5 detections so user input and rendering preempt this
		# work — same cooperative pattern as Add-TabSectionsToPanel uses.
		if ($Dispatcher -and ($processed % 5 -eq 0))
		{
			try { $Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]{}) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StartupOrchestrator.FirstLaunchBackup.DispatcherYield' }
		}
	}

	if ($timedOut)
	{
		Write-StartupOrchestratorLog ('Phase 2 backup timed out at {0:N1}s with {1} tweaks captured' -f $sw.Elapsed.TotalSeconds, $snapshot.Count)
		return $false
	}

	$backupDir = Join-Path $env:LOCALAPPDATA 'Baseline\backups'
	if (-not (Test-Path -LiteralPath $backupDir))
	{
		$null = New-Item -Path $backupDir -ItemType Directory -Force
	}
	$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
	$backupPath = Join-Path $backupDir ("initial-{0}.json" -f $stamp)
	$payload = [pscustomobject]@{
		Schema           = 'Baseline.InitialConfigBackup'
		SchemaVersion    = 1
		SavedAtUtc       = ([DateTime]::UtcNow.ToString('o'))
		BaselineVersion  = $BaselineVersion
		ElapsedSeconds   = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
		TweakCount       = $snapshot.Count
		Tweaks           = $snapshot
	}
	[System.IO.File]::WriteAllText($backupPath, ($payload | ConvertTo-Json -Depth 6), [System.Text.Encoding]::UTF8)
	Write-StartupOrchestratorLog ('Phase 2 backup wrote {0} entries to {1} in {2:N1}s' -f $snapshot.Count, $backupPath, $sw.Elapsed.TotalSeconds)
	return $true
}

function Invoke-StaleRcDirCleanup
{
	param ([string]$CurrentVersion)

	if ([string]::IsNullOrWhiteSpace($CurrentVersion)) { return 0 }
	$rcRoot = Join-Path $env:LOCALAPPDATA 'Temp\Baseline\RC'
	if (-not (Test-Path -LiteralPath $rcRoot)) { return 0 }
	$deleted = 0
	# by the current process so deletion should succeed; if a user has two
	# Baseline instances open across versions, the locked files just stay.
	foreach ($dir in (Get-ChildItem -LiteralPath $rcRoot -Directory -ErrorAction SilentlyContinue))
	{
		if ($dir.Name -eq $CurrentVersion) { continue }
		try
		{
			Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
			$deleted++
			Write-StartupOrchestratorLog ('Phase 3 removed stale RC dir {0}' -f $dir.FullName)
		}
		catch
		{
			Write-StartupOrchestratorLog ('Phase 3 could not remove {0}: {1}' -f $dir.FullName, $_.Exception.Message)
		}
	}
	return $deleted
}

function Invoke-BaselineIntegrityCheck
{
	param ([string]$ModuleRoot)

	if (-not $ModuleRoot -or -not (Test-Path -LiteralPath $ModuleRoot)) { return -1 }
	$manifestPath = Join-Path $ModuleRoot 'integrity.manifest.json'
	if (-not (Test-Path -LiteralPath $manifestPath)) { return -1 }

	$mismatches = 0
	try
	{
		$raw = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
		$manifest = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
		if (-not $manifest -or -not $manifest.files) { return -1 }
		foreach ($prop in $manifest.files.PSObject.Properties)
		{
			$relPath = [string]$prop.Name
			$expected = [string]$prop.Value
			$fullPath = Join-Path $ModuleRoot $relPath
			if (-not (Test-Path -LiteralPath $fullPath))
			{
				$mismatches++
				Write-StartupOrchestratorLog ('Phase 4 missing file: {0}' -f $relPath)
				continue
			}
			try
			{
				$actual = Get-BaselineFileSha256 -Path $fullPath
				if ([string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) { continue }
				# integrity.manifest.json is regenerated on each build but the
				# user's edited file in the repo can drift from it. Skip the
				# manifest itself in mismatch reporting.
				if ($relPath -ieq 'integrity.manifest.json') { continue }
				$mismatches++
				Write-StartupOrchestratorLog ('Phase 4 hash mismatch: {0}' -f $relPath)
			}
			catch
			{
				$mismatches++
				Write-StartupOrchestratorLog ('Phase 4 hash failed for {0}: {1}' -f $relPath, $_.Exception.Message)
			}
		}
	}
	catch
	{
		Write-StartupOrchestratorLog ('Phase 4 manifest parse failed: {0}' -f $_.Exception.Message)
		return -1
	}
	return $mismatches
}

function Invoke-BaselineStartupOrchestrator
{
	param (
		[object[]]$TweakManifest,
		[string]$ModuleRoot,
		[string]$BaselineVersion,
		[object]$Dispatcher = $null
	)

	if ($Script:StartupOrchestratorRan) { return }
	$Script:StartupOrchestratorRan = $true

	Write-StartupOrchestratorLog 'Orchestrator started'

	# Phase 2: First-launch backup with 30s timeout.
	try
	{
		$alreadyDone = [bool](Get-BaselineUserPreference -Key 'InitialConfigBackupCompleted' -Default $false)
		if (-not $alreadyDone -and $TweakManifest -and @($TweakManifest).Count -gt 0)
		{
			$completed = Invoke-FirstLaunchConfigBackup -TweakManifest $TweakManifest -TimeoutSeconds 30 -BaselineVersion $BaselineVersion -Dispatcher $Dispatcher
			if ($completed)
			{
				Set-BaselineUserPreference -Key 'InitialConfigBackupCompleted' -Value $true
				Write-StartupOrchestratorLog 'Phase 2 OK (backup written)'
			}
			else
			{
				Write-StartupOrchestratorLog 'Phase 2 TIMED OUT (will retry next launch)'
			}
		}
		else
		{
			Write-StartupOrchestratorLog 'Phase 2 skipped (already completed or empty manifest)'
		}
	}
	catch { Write-StartupOrchestratorLog ('Phase 2 FAILED: {0}' -f $_.Exception.Message) }

	# Phase 3: Stale RC dir cleanup.
	try
	{
		$deleted = Invoke-StaleRcDirCleanup -CurrentVersion $BaselineVersion
		Write-StartupOrchestratorLog ('Phase 3 OK ({0} stale dirs removed)' -f $deleted)
	}
	catch { Write-StartupOrchestratorLog ('Phase 3 FAILED: {0}' -f $_.Exception.Message) }

	# Phase 4: Integrity check.
	try
	{
		$issues = Invoke-BaselineIntegrityCheck -ModuleRoot $ModuleRoot
		if ($issues -lt 0)
		{
			Write-StartupOrchestratorLog 'Phase 4 SKIPPED (no manifest)'
		}
		elseif ($issues -gt 0)
		{
			Write-StartupOrchestratorLog ('Phase 4 WARN ({0} mismatches)' -f $issues)
		}
		else
		{
			Write-StartupOrchestratorLog 'Phase 4 OK (integrity verified)'
		}
	}
	catch { Write-StartupOrchestratorLog ('Phase 4 FAILED: {0}' -f $_.Exception.Message) }

	Save-BaselineUserPreferences
	Write-StartupOrchestratorLog 'Orchestrator complete'
}
