
# Support bundle helpers for Baseline.
# Builds a portable, operator-facing archive with environment, audit,
# compliance, and execution context for troubleshooting and enterprise review.

<#
    .SYNOPSIS
#>

function Write-SupportBundleSwallowedException
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[object]$ErrorRecord,

		[Parameter(Mandatory)]
		[string]$Source,

		[ValidateSet('Debug', 'Warning', 'Error')]
		[string]$Severity = 'Warning'
	)

	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Write-SwallowedException -ErrorRecord $ErrorRecord -Source $Source -Severity $Severity
		return
	}

	$message = '[swallow] {0}: {1}' -f $Source, $ErrorRecord.Exception.Message
	switch ($Severity)
	{
		'Debug' { Write-Verbose $message }
		'Error' { Write-Error $message -ErrorAction Continue }
		default { Write-Warning $message }
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineSupportBundleDeepLinks
{
	[CmdletBinding()]
	param (
		[string[]]$RunId,
		[string[]]$ComputerName,
		[string[]]$Operation
	)

	$runFilter = @($RunId | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$computerFilter = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })
	$operationFilter = @($Operation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim().ToLowerInvariant() })

	$records = @()
	if (Get-Command -Name 'Get-BaselineRemoteOrchestrationHistory' -ErrorAction SilentlyContinue)
	{
		try
		{
			$records = @(Get-BaselineRemoteOrchestrationHistory -MaxRecords 500)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDeepLinks:catch63' -Severity Debug }

			$records = @()
		}
	}
	if ($records.Count -eq 0)
	{
		try
		{
			$historyPath = $null
			if (Get-Command -Name 'Get-BaselineRemoteOrchestrationHistoryPath' -ErrorAction SilentlyContinue)
			{
				try { $historyPath = Get-BaselineRemoteOrchestrationHistoryPath } catch {
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDeepLinks:catch75' -Severity Debug }
				 $historyPath = $null }
			}
			if ([string]::IsNullOrWhiteSpace($historyPath))
			{
				$historyPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Baseline') 'remote-orchestration.jsonl'
			}
			if (-not [string]::IsNullOrWhiteSpace($historyPath) -and (Test-Path -LiteralPath $historyPath))
			{
				$lines = [System.IO.File]::ReadAllLines($historyPath, [System.Text.UTF8Encoding]::new($false))
				foreach ($line in $lines)
				{
					if ([string]::IsNullOrWhiteSpace($line)) { continue }
					try
					{
						$record = $line | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
						if ($record) { $records += $record }
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDeepLinks:catch92' -Severity Debug }

						continue
					}
				}
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDeepLinks:catch99' -Severity Debug }

			$records = @()
		}
	}

	$links = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($record in $records)
	{
		if (-not $record) { continue }
		$recordKind = if ($record.PSObject.Properties['RecordKind']) { [string]$record.RecordKind } else { 'Target' }
		if ($recordKind -notin @('Target', 'RunSummary')) { continue }

		$recordRunId = if ($record.PSObject.Properties['RunId']) { [string]$record.RunId } else { $null }
		$recordComputer = if ($record.PSObject.Properties['ComputerName']) { [string]$record.ComputerName } else { $null }
		$recordOperation = if ($record.PSObject.Properties['Operation']) { [string]$record.Operation } else { 'Remote' }

		if ($runFilter.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($recordRunId) -or $runFilter -notcontains $recordRunId.Trim().ToLowerInvariant())) { continue }
		if ($computerFilter.Count -gt 0 -and ([string]::IsNullOrWhiteSpace($recordComputer) -or $computerFilter -notcontains $recordComputer.Trim().ToLowerInvariant())) { continue }
		if ($operationFilter.Count -gt 0 -and $operationFilter -notcontains $recordOperation.Trim().ToLowerInvariant()) { continue }

		$targetState = if ($record.PSObject.Properties['TargetState']) { [string]$record.TargetState } else { 'Unknown' }
		$terminalState = if ($record.PSObject.Properties['TerminalState']) { [string]$record.TerminalState } else { 'Unknown' }
		$failedCount = if ($record.PSObject.Properties['FailedCount']) { [int]$record.FailedCount } else { 0 }
		$historyPath = if ($record.PSObject.Properties['HistoryPath']) { [string]$record.HistoryPath } else { $null }

		$artifactNames = [System.Collections.Generic.List[string]]::new()
		[void]$artifactNames.Add('bundle-index.json')
		[void]$artifactNames.Add('metadata.json')
		[void]$artifactNames.Add('remote-orchestration.jsonl')
		[void]$artifactNames.Add('remote-orchestration-summary.txt')
		[void]$artifactNames.Add('remote-orchestration-runs.json')
		[void]$artifactNames.Add('remote-orchestration-reconciliation.json')
		[void]$artifactNames.Add('remote-orchestration-details.json')
		if ($failedCount -gt 0)
		{
			[void]$artifactNames.Add('remote-orchestration-deeplinks.json')
		}

		$links.Add([pscustomobject]@{
			Kind         = $recordKind
			RunId        = $recordRunId
			ComputerName  = $recordComputer
			Operation     = $recordOperation
			TargetState   = $targetState
			TerminalState = $terminalState
			FailedCount   = $failedCount
			HistoryPath   = $historyPath
			Artifacts     = @($artifactNames | Select-Object -Unique)
		})
	}

	return @($links)
}

function New-BaselineSupportBundleWindowsUpdateStatusNotCollected
{
	[CmdletBinding()]
	param()

	return [pscustomobject][ordered]@{
		Schema          = 'Baseline.WindowsUpdateStatus'
		GeneratedAt     = [System.DateTime]::UtcNow.ToString('o')
		Collected       = $false
		CollectionState = 'NotCollected'
		Reason          = 'Support bundle export does not run live Windows Update status checks. Pass -WindowsUpdateStatus with a pre-collected snapshot to include live status.'
	}
}

function ConvertTo-BaselineSupportBundleWindowsProcessArgument
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[string]$Value
	)

	if ([string]::IsNullOrEmpty($Value))
	{
		return '""'
	}

	if ($Value -notmatch '[\s"]')
	{
		return $Value
	}

	$builder = [System.Text.StringBuilder]::new()
	[void]$builder.Append('"')
	$backslashCount = 0
	foreach ($character in $Value.ToCharArray())
	{
		if ($character -eq '\')
		{
			$backslashCount++
			continue
		}

		if ($character -eq '"')
		{
			if ($backslashCount -gt 0)
			{
				[void]$builder.Append([string]::new([char]92, ($backslashCount * 2)))
				$backslashCount = 0
			}
			[void]$builder.Append('\"')
			continue
		}

		if ($backslashCount -gt 0)
		{
			[void]$builder.Append([string]::new([char]92, $backslashCount))
			$backslashCount = 0
		}
		[void]$builder.Append($character)
	}

	if ($backslashCount -gt 0)
	{
		[void]$builder.Append([string]::new([char]92, ($backslashCount * 2)))
	}

	[void]$builder.Append('"')
	return $builder.ToString()
}

function ConvertTo-BaselineSupportBundleProcessArgumentString
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object[]]$ArgumentList
	)

	if (-not $ArgumentList -or $ArgumentList.Count -eq 0) { return '' }

	$quoted = foreach ($argument in @($ArgumentList))
	{
		ConvertTo-BaselineSupportBundleWindowsProcessArgument -Value ([string]$argument)
	}

	return ($quoted -join ' ')
}

function Invoke-BaselineSupportBundleProcessCapture
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$FilePath,

		[object[]]$ArgumentList = @(),

		[int]$TimeoutSeconds = 30
	)

	$invokeBaselineProcessCommand = Get-Command -Name 'Invoke-BaselineProcess' -CommandType Function -ErrorAction SilentlyContinue
	if ($invokeBaselineProcessCommand)
	{
		return & $invokeBaselineProcessCommand -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -CaptureOutput -AllowAnyExitCode
	}

	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $FilePath
	$argumentListProperty = $psi.GetType().GetProperty('ArgumentList')
	if ($argumentListProperty)
	{
		foreach ($argument in @($ArgumentList))
		{
			[void]$psi.ArgumentList.Add([string]$argument)
		}
	}
	else
	{
		$psi.Arguments = ConvertTo-BaselineSupportBundleProcessArgumentString -ArgumentList $ArgumentList
	}
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	$stdoutTask = $null
	$stderrTask = $null
	$stdout = ''
	$stderr = ''

	try
	{
		[void]$process.Start()
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		$completed = $process.WaitForExit([int]([TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSeconds)).TotalMilliseconds))
		if (-not $completed)
		{
			try { $process.Kill() } catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.ProcessCapture.Kill' -Severity Debug }
			throw ([System.TimeoutException]::new(("Process '{0}' timed out after {1} second(s)." -f $FilePath, $TimeoutSeconds)))
		}

		try { $stdout = [string]$stdoutTask.GetAwaiter().GetResult() } catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.ProcessCapture.StdoutAwait' -Severity Debug }
		try { $stderr = [string]$stderrTask.GetAwaiter().GetResult() } catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.ProcessCapture.StderrAwait' -Severity Debug }

		return [pscustomobject][ordered]@{
			ExitCode       = [int]$process.ExitCode
			StandardOutput = $stdout
			StandardError  = $stderr
			TimedOut       = $false
			ProcessId      = [int]$process.Id
			FilePath       = $FilePath
		}
	}
	finally
	{
		try { $process.Dispose() } catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.ProcessCapture.Dispose' -Severity Debug }
	}
}

function Export-BaselineSupportBundle
{
	<#
		.SYNOPSIS
		Builds a Baseline support bundle archive at the requested output path.

		.DESCRIPTION
		Stages a portable folder containing:
		- bundle metadata
		- audit log snapshot
		- optional system state snapshot
		- optional compliance report
		- optional configuration profile
		- optional test report
		Then compresses the staging folder into a ZIP archive.

		When -Immutable is specified, generates a signoff bundle with:
		- SHA256 checksums for all included files
		- Bundle integrity manifest
		- Provenance tracking (user, machine, timestamp)
		- Read-only file attributes on working contents
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$OutputPath,

		[switch]$Immutable,

		[string]$SignoffReason,

		[string]$ProfilePath,

		[string]$SessionLogPath,

		[object]$ComplianceReport,

		[object]$WindowsUpdateStatus,

		[object]$SystemSnapshot,

		[object]$PreSnapshot,

		[object]$PostSnapshot,

		[object]$ConfigStatePre,

		[object]$ConfigStatePost,

		[Parameter()]
		[AllowEmptyCollection()]
		[object[]]$RemoteTargets = @(),

		[object]$ReproductionContext,

		[array]$Manifest,

		[string[]]$DeepLinkRunId,

		[string[]]$DeepLinkComputerName,

		[string[]]$DeepLinkOperation,

		[switch]$IncludeAuditLog = $true,

		[int]$AuditRetentionDays = $(try { Get-BaselineAuditRetentionDays } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Export-BaselineSupportBundle:catch383' -Severity Debug }
		 90 }),

		[switch]$IncludeTestReport = $true,

		[Parameter()]
		[AllowEmptyCollection()]
		[object[]]$ConnectivityResults = @(),

		[scriptblock]$ProgressCallback
	)

	if ([string]::IsNullOrWhiteSpace($OutputPath))
	{
		throw 'OutputPath is required.'
	}

	if (-not $OutputPath.EndsWith('.zip', [System.StringComparison]::OrdinalIgnoreCase))
	{
		$OutputPath = '{0}.zip' -f $OutputPath
	}

	$parentDir = Split-Path -Path $OutputPath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		$null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
	}

	$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineSupportBundle_{0}' -f [guid]::NewGuid().ToString('N'))
	$stagingDir = Join-Path $tempRoot 'Bundle'
	$bundleEntries = [System.Collections.Generic.List[pscustomobject]]::new()
	$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
	$deepLinkFilters = [ordered]@{
		RunId = @($DeepLinkRunId | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim() })
		ComputerName = @($DeepLinkComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim() })
		Operation = @($DeepLinkOperation | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_.Trim() })
	}

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'SupportBundle\Export-BaselineSupportBundle\Export-BaselineSupportBundle.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Verifies the integrity of an immutable/signoff support bundle by checking
    SHA256 checksums against the embedded integrity manifest.
#>

function Test-BaselineSupportBundleIntegrity
{
	<#
		.SYNOPSIS
		Verifies the integrity of an immutable Baseline support bundle.

		.DESCRIPTION
		Extracts the bundle temporarily, reads the integrity manifest, and
		verifies SHA256 checksums for all tracked files.

		.OUTPUTS
		PSCustomObject with:
		- Valid: $true if all checksums match
		- Immutable: $true if the bundle contains an integrity manifest
		- FilesChecked: Number of files verified
		- FilesPassed: Number of files with matching checksums
		- FilesFailed: Number of files with mismatched checksums
		- Failures: Array of files that failed verification
		- Provenance: Signoff provenance information from the manifest
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$BundlePath
	)

	if (-not (Test-Path -LiteralPath $BundlePath))
	{
		throw "Bundle not found: $BundlePath"
	}

	$result = [ordered]@{
		BundlePath    = $BundlePath
		Valid         = $false
		Immutable     = $false
		FilesChecked  = 0
		FilesPassed   = 0
		FilesFailed   = 0
		Failures      = @()
		Provenance    = $null
		VerifiedAt    = (Get-Date).ToString('o')
	}

	$tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) ('BundleVerify_{0}' -f [guid]::NewGuid().ToString('N'))

	try
	{
		$null = New-Item -Path $tempExtract -ItemType Directory -Force
		Expand-Archive -LiteralPath $BundlePath -DestinationPath $tempExtract -Force

		$manifestPath = Join-Path $tempExtract 'integrity-manifest.json'
		if (-not (Test-Path -LiteralPath $manifestPath))
		{
			$result.Immutable = $false
			$result.Valid = $null  # Cannot verify non-immutable bundles
			return [pscustomobject]$result
		}

		$result.Immutable = $true

		$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-BaselineJson -Depth 16

		if ($manifest.Provenance)
		{
			$result.Provenance = $manifest.Provenance
		}

		$failures = [System.Collections.Generic.List[pscustomobject]]::new()

		foreach ($fileEntry in $manifest.Files)
		{
			$filePath = Join-Path $tempExtract $fileEntry.FileName
			$result.FilesChecked++

			if (-not (Test-Path -LiteralPath $filePath))
			{
				$failures.Add([pscustomobject]@{
					FileName   = $fileEntry.FileName
					Expected   = $fileEntry.SHA256
					Actual     = 'FILE_MISSING'
					Status     = 'Missing'
				})
				continue
			}

			try
			{
				$actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash

				if ($actualHash -eq $fileEntry.SHA256)
				{
					$result.FilesPassed++
				}
				else
				{
					$failures.Add([pscustomobject]@{
						FileName   = $fileEntry.FileName
						Expected   = $fileEntry.SHA256
						Actual     = $actualHash
						Status     = 'Mismatch'
					})
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Test-BaselineSupportBundleIntegrity:catch538' -Severity Debug }

				$failures.Add([pscustomobject]@{
					FileName   = $fileEntry.FileName
					Expected   = $fileEntry.SHA256
					Actual     = 'HASH_ERROR'
					Status     = 'Error'
					Error      = $_.Exception.Message
				})
			}
		}

		$result.FilesFailed = $failures.Count
		$result.Failures = @($failures)
		$result.Valid = ($failures.Count -eq 0)

		return [pscustomobject]$result
	}
	finally
	{
		if (Test-Path -LiteralPath $tempExtract)
		{
			# Remove read-only attributes before cleanup
			Get-ChildItem -LiteralPath $tempExtract -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
				$_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
			}
			Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}

<#
	.SYNOPSIS
	Build the ConfigState.json payload for a support bundle.

	.DESCRIPTION
	Projects the GUI session snapshot (whatever Get-GuiSettingsSnapshot
	returns) down to the field set called for in todo.md #14: preset,
	user overrides, Safe Mode, Onboarding mode, Game Mode profile, and
	the most recent Preview Run output. Both Pre and Post are accepted;
	either may be null. When both are present a shallow per-key Diff is
	emitted so a maintainer can see exactly what flipped between the
	two states without re-deriving it.
#>
function New-BaselineSupportBundleConfigState
{
	[CmdletBinding()]
	param (
		[object]$PreState,
		[object]$PostState
	)

	$projection = {
		param($state)
		if ($null -eq $state) { return $null }
		$props = $state.PSObject.Properties
		$pick = {
			param($name)
			if ($props[$name]) { return $state.$name }
			return $null
		}
		[ordered]@{
			Preset                    = & $pick 'SelectedPreset'
			Theme                     = & $pick 'Theme'
			Language                  = & $pick 'Language'
			SafeMode                  = & $pick 'SafeMode'
			AdvancedMode              = & $pick 'AdvancedMode'
			GameMode                  = & $pick 'GameMode'
			GameModeProfile           = & $pick 'GameModeProfile'
			GameModeDecisionOverrides = & $pick 'GameModeDecisionOverrides'
			OnboardingMode            = & $pick 'DefaultStartupMode'
			RestoreLastSession        = & $pick 'RestoreLastSession'
			RequireRunConfirmation    = & $pick 'RequireRunConfirmation'
			PreviewBeforeRunDefault   = & $pick 'PreviewBeforeRunDefault'
			LastPreviewRunOutput      = & $pick 'LastPreviewRunOutput'
			AppsQueuedActions         = & $pick 'AppsQueuedActions'
			LoggingEnabled            = & $pick 'LoggingEnabled'
			LogLevel                  = & $pick 'LogLevel'
			DebugLoggingEnabled       = & $pick 'DebugLoggingEnabled'
			RiskFilter                = & $pick 'RiskFilter'
			CategoryFilter            = & $pick 'CategoryFilter'
		}
	}

	$pre  = & $projection $PreState
	$post = & $projection $PostState

	$diff = $null
	if ($null -ne $pre -and $null -ne $post)
	{
		$changed = [System.Collections.Generic.List[pscustomobject]]::new()
		foreach ($key in $post.Keys)
		{
			$preVal  = if ($pre.Contains($key))  { $pre[$key]  } else { $null }
			$postVal = $post[$key]
			$preJson  = try { ConvertTo-Json -InputObject $preVal  -Depth 4 -Compress } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleConfigState:catch633' -Severity Debug }
			 [string]$preVal }
			$postJson = try { ConvertTo-Json -InputObject $postVal -Depth 4 -Compress } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleConfigState:catch634' -Severity Debug }
			 [string]$postVal }
			if ($preJson -ne $postJson)
			{
				[void]$changed.Add([pscustomobject]@{
					Key  = [string]$key
					Pre  = $preVal
					Post = $postVal
				})
			}
		}
		$diff = [ordered]@{
			ChangedCount = $changed.Count
			Changed      = @($changed)
		}
	}

	return [pscustomobject][ordered]@{
		Schema        = 'Baseline.ConfigState'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
		HasPre        = ($null -ne $pre)
		HasPost       = ($null -ne $post)
		Pre           = $pre
		Post          = $post
		Diff          = $diff
	}
}

<#
	.SYNOPSIS
	Build the RemoteTargets.json payload for a support bundle.

	.DESCRIPTION
	Sanitized projection of the live remote target context. Each target is
	emitted as { TargetName, ConnectionMethod, State, CredentialType }.
	Hostname leakage is bounded - anything past the first dot is dropped so
	we keep "PC01" rather than shipping "PC01.corp.contoso.com". Credential
	values are never serialized: only the *type* (NTLM / Kerberos / Cert /
	None) lands in the bundle.
#>
function New-BaselineSupportBundleRemoteTargets
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[object[]]$Targets
	)

	$out = [System.Collections.Generic.List[pscustomobject]]::new()
	foreach ($t in $Targets)
	{
		if ($null -eq $t) { continue }
		$props = $t.PSObject.Properties

		$rawName = if ($props['ComputerName']) { [string]$t.ComputerName } elseif ($props['TargetName']) { [string]$t.TargetName } else { $null }
		$shortName = $null
		if (-not [string]::IsNullOrWhiteSpace($rawName))
		{
			# Strip FQDN tail to avoid leaking the org's domain into the bundle.
			$shortName = ($rawName -split '\.', 2)[0]
		}

		$method = if ($props['ConnectionMethod']) { [string]$t.ConnectionMethod } elseif ($props['Method']) { [string]$t.Method } else { 'WinRM' }

		$state = $null
		if ($props['State']) { $state = [string]$t.State }
		elseif ($props['Status']) { $state = [string]$t.Status }
		elseif ($props['Reachable']) { $state = if ([bool]$t.Reachable) { 'Connected' } else { 'Failed' } }

		$credType = $null
		if ($props['CredentialType']) { $credType = [string]$t.CredentialType }
		elseif ($props['Credential'])
		{
			# Best-effort inference - UPN looks like Kerberos territory,
			# DOMAIN\user looks like NTLM. Never serialize the credential.
			$cred = $t.Credential
			if ($cred -and $cred.UserName)
			{
				$user = [string]$cred.UserName
				if ($user -match '@')      { $credType = 'Kerberos' }
				elseif ($user -match '\\') { $credType = 'NTLM' }
				else                       { $credType = 'Default' }
			}
			else { $credType = 'None' }
		}
		else { $credType = 'CurrentUser' }

		[void]$out.Add([pscustomobject][ordered]@{
			TargetName       = $shortName
			ConnectionMethod = $method
			State            = $state
			CredentialType   = $credType
		})
	}

	return [pscustomobject][ordered]@{
		Schema        = 'Baseline.RemoteTargets'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
		Targets       = @($out)
	}
}

function Test-BaselineSupportBundleElevated
{
	try
	{
		$current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		$principal = [System.Security.Principal.WindowsPrincipal]::new($current)
		return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Test-BaselineSupportBundleElevated:catch746' -Severity Debug }
	 return $null }
}

function Get-BaselineSupportBundleMaskedName
{
	param (
		[string]$Name
	)

	if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
	$trimmed = $Name.Trim()
	if ($trimmed.Length -le 1) { return '*' }
	return ('{0}{1}' -f $trimmed.Substring(0, 1), ('*' * ($trimmed.Length - 1)))
}

function Get-BaselineSupportBundleObjectValue
{
	param (
		[object]$InputObject,
		[string]$Name
	)

	if ($null -eq $InputObject) { return $null }
	$property = $InputObject.PSObject.Properties[$Name]
	if ($property) { return $property.Value }
	return $null
}

function Get-BaselineSupportBundleGitBuildId
{
	$repoRoot = $null
	$repoRootVariable = Get-Variable -Name 'SharedHelpersRepoRoot' -Scope Script -ErrorAction SilentlyContinue
	if ($repoRootVariable) { $repoRoot = [string]$repoRootVariable.Value }
	if ([string]::IsNullOrWhiteSpace($repoRoot))
	{
		$repoRoot = try { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleGitBuildId:catch781' -Severity Debug }
		 $null }
	}
	if ([string]::IsNullOrWhiteSpace($repoRoot)) { return $null }

	$gitDir = Join-Path $repoRoot '.git'
	if (-not (Test-Path -LiteralPath $gitDir)) { return $null }

	try
	{
		$headPath = Join-Path $gitDir 'HEAD'
		if (-not (Test-Path -LiteralPath $headPath)) { return $null }
		$head = ([System.IO.File]::ReadAllText($headPath, [System.Text.UTF8Encoding]::new($false))).Trim()
		if ([string]::IsNullOrWhiteSpace($head)) { return $null }
		if ($head -match '^ref:\s+(.+)$')
		{
			$refPath = Join-Path $gitDir $matches[1]
			if (Test-Path -LiteralPath $refPath)
			{
				$commit = ([System.IO.File]::ReadAllText($refPath, [System.Text.UTF8Encoding]::new($false))).Trim()
				if ($commit -match '^[0-9a-fA-F]{7,40}$') { return $commit }
			}

			$packedRefsPath = Join-Path $gitDir 'packed-refs'
			if (Test-Path -LiteralPath $packedRefsPath)
			{
				$packedLines = [System.IO.File]::ReadAllLines($packedRefsPath, [System.Text.UTF8Encoding]::new($false))
				$escapedRef = [regex]::Escape($matches[1])
				foreach ($line in $packedLines)
				{
					if ($line -match ("^([0-9a-fA-F]{{40}})\s+{0}$" -f $escapedRef)) { return $matches[1] }
				}
			}
			return $head
		}
		if ($head -match '^[0-9a-fA-F]{7,40}$') { return $head }
		return $head
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleGitBuildId:catch818' -Severity Debug }
	 return $null }
}

function Get-BaselineSupportBundleValidationEvidenceRoot
{
	[CmdletBinding()]
	[OutputType([string])]
	param()

	$roots = New-Object 'System.Collections.Generic.List[string]'
	$addRoot = {
		param([string]$Path)

		if ([string]::IsNullOrWhiteSpace([string]$Path)) { return }
		try { $resolvedRoot = [System.IO.Path]::GetFullPath($Path) }
		catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleValidationEvidenceRoot:catch833' -Severity Debug }
		 return }

		foreach ($existingRoot in $roots)
		{
			if ([string]::Equals([string]$existingRoot, [string]$resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase))
			{
				return
			}
		}

		[void]$roots.Add($resolvedRoot)
	}.GetNewClosure()

	& $addRoot ([string]$Script:SharedHelpersRepoRoot)

	$launcherPath = [string]$env:BASELINE_LAUNCHER_PATH
	if (-not [string]::IsNullOrWhiteSpace($launcherPath) -and [System.IO.Path]::IsPathRooted($launcherPath))
	{
		& $addRoot (Split-Path -Path $launcherPath -Parent)
	}

	try { & $addRoot ([System.AppDomain]::CurrentDomain.BaseDirectory) } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleValidationEvidenceRoot:catch854' -Severity Debug }
	 $null = $_ }
	try { & $addRoot ((Get-Location).ProviderPath) } catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleValidationEvidenceRoot:catch855' -Severity Debug }
	 $null = $_ }

	foreach ($root in $roots)
	{
		$testReportPath = Join-Path $root 'Tests\TestReport.json'
		$matrixPath = Join-Path $root 'Tests\Integration\DesktopMatrixResults.json'
		if ((Test-Path -LiteralPath $testReportPath -PathType Leaf) -or (Test-Path -LiteralPath $matrixPath -PathType Leaf))
		{
			return [string]$root
		}
	}

	return $null
}

function New-BaselineSupportBundleVersionInfo
{
	[CmdletBinding()]
	param (
		[string]$BaselineVersion
	)

	$displayVersion = $BaselineVersion
	if ([string]::IsNullOrWhiteSpace($displayVersion))
	{
		$displayVersion = 'unknown'
	}

	$normalizedVersion = ([string]$displayVersion).Trim()
	if ($normalizedVersion.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase))
	{
		$normalizedVersion = $normalizedVersion.Substring(1)
	}
	$releaseLabel = $null
	if ($normalizedVersion -match '(?i)(alpha|beta|rc|preview|dev|nightly)')
	{
		$releaseLabel = $matches[1].ToLowerInvariant()
	}
	if ($normalizedVersion -match '^(\d+\.\d+\.\d+(?:\.\d+)?)')
	{
		$normalizedVersion = $matches[1]
	}

	$buildId = Get-BaselineSupportBundleGitBuildId
	if ([string]::IsNullOrWhiteSpace($buildId))
	{
		try { $buildId = [System.Reflection.Assembly]::GetEntryAssembly().ManifestModule.ModuleVersionId.ToString('N') } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleVersionInfo:catch901' -Severity Debug }
		 $buildId = $null }
	}

	$channel = 'stable'
	if ($releaseLabel -or $displayVersion -match '(?i)(alpha|beta|rc|preview|dev|nightly)' -or [string]::Equals($env:BASELINE_CHANNEL, 'dev', [System.StringComparison]::OrdinalIgnoreCase))
	{
		$channel = 'dev'
	}

	return [pscustomobject][ordered]@{
		Schema          = 'Baseline.Version'
		SchemaVersion   = 1
		GeneratedAt     = [System.DateTime]::UtcNow.ToString('o')
		version         = $normalizedVersion
		display_version = $displayVersion
		release_label   = $releaseLabel
		build           = $buildId
		channel         = $channel
		ps_version      = [string]$PSVersionTable.PSVersion
		ps_edition      = [string]$PSVersionTable.PSEdition
		elevated        = (Test-BaselineSupportBundleElevated)
	}
}

function New-BaselineSupportBundleEnvironmentInfo
{
	[CmdletBinding()]
	param ()

	$osInfo = [ordered]@{
		Version      = [string][System.Environment]::OSVersion.Version
		BuildNumber  = $null
		Edition      = $null
		Caption      = [string][System.Environment]::OSVersion.VersionString
		Architecture = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
	}
	try
	{
		$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
		$osInfo['Caption'] = [string]$os.Caption
		$osInfo['Version'] = [string]$os.Version
		$osInfo['BuildNumber'] = [string]$os.BuildNumber
		$osInfo['Architecture'] = [string]$os.OSArchitecture
	}
	catch
	{
		Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.EnvironmentInfo.LoadOperatingSystem' -Severity Warning
	}
	try
	{
		$ntVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
		$osInfo['Edition'] = [string]$ntVersion.EditionID
		if ([string]::IsNullOrWhiteSpace([string]$osInfo['BuildNumber']) -and $ntVersion.CurrentBuildNumber)
		{
			$osInfo['BuildNumber'] = [string]$ntVersion.CurrentBuildNumber
		}
	}
	catch
	{
		Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.EnvironmentInfo.LoadNtVersion' -Severity Warning
	}

	$domainInfo = [ordered]@{
		Type = $null
		Name = $null
	}
	try
	{
		$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
		if ([bool]$cs.PartOfDomain)
		{
			$domainInfo['Type'] = 'Domain'
			$domainInfo['Name'] = [string]$cs.Domain
		}
		else
		{
			$domainInfo['Type'] = 'Workgroup'
			$domainInfo['Name'] = [string]$cs.Workgroup
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleEnvironmentInfo:catch981' -Severity Debug }

		$domainInfo['Type'] = 'Unknown'
		$domainInfo['Name'] = $env:USERDOMAIN
	}

	$executionPolicies = @()
	try
	{
		$executionPolicies = @(Get-ExecutionPolicy -List | ForEach-Object {
			[pscustomobject][ordered]@{
				Scope           = [string]$_.Scope
				ExecutionPolicy = [string]$_.ExecutionPolicy
			}
		})
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleEnvironmentInfo:catch997' -Severity Debug }
	 $executionPolicies = @() }

	return [pscustomobject][ordered]@{
		Schema        = 'Baseline.Environment'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
		OS            = $osInfo
		Process       = [ordered]@{
			Architecture = if ([System.Environment]::Is64BitProcess) { 'x64' } else { 'x86' }
			Elevated     = (Test-BaselineSupportBundleElevated)
		}
		User          = [ordered]@{
			NameMasked  = (Get-BaselineSupportBundleMaskedName -Name $env:USERNAME)
			Domain      = $env:USERDOMAIN
			MachineName = (Get-BaselineSupportBundleMaskedName -Name $env:COMPUTERNAME)
		}
		Domain        = $domainInfo
		PowerShell    = [ordered]@{
			Edition = [string]$PSVersionTable.PSEdition
			Version = [string]$PSVersionTable.PSVersion
		}
		ExecutionPolicy = @($executionPolicies)
		Locale        = [ordered]@{
			Culture   = [System.Globalization.CultureInfo]::CurrentCulture.Name
			UICulture = [System.Globalization.CultureInfo]::CurrentUICulture.Name
			Language  = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
		}
	}
}

function New-BaselineSupportBundleWindowsFeatures
{
	[CmdletBinding()]
	param (
		[scriptblock]$ProgressCallback,

		[scriptblock]$ProcessCaptureScript
	)

	$notifyProgress = {
		param(
			[string]$Stage,
			[string]$Message
		)

		if (-not $ProgressCallback) { return }
		try { & $ProgressCallback -Stage $Stage -Message $Message }
		catch { Write-SupportBundleSwallowedException -ErrorRecord $_ -Source 'SupportBundle.WindowsFeatures.ProgressCallback' -Severity Debug }
	}.GetNewClosure()

	$writeCollectionWarning = {
		param([string]$Message)

		if ([string]::IsNullOrWhiteSpace($Message)) { return }
		if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogWarning $Message
			return
		}
		Write-Warning $Message
	}

	if (-not $ProcessCaptureScript)
	{
		$processCaptureCommand = Get-Command -Name 'Invoke-BaselineSupportBundleProcessCapture' -CommandType Function -ErrorAction SilentlyContinue
		$ProcessCaptureScript = if ($processCaptureCommand) { $processCaptureCommand.ScriptBlock } else { $null }
	}

	$invokePowerShellJsonCollector = {
		param(
			[Parameter(Mandatory = $true)][string]$Name,
			[Parameter(Mandatory = $true)][string]$ScriptText,
			[int]$TimeoutSeconds = 15
		)

		$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
		if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf))
		{
			$powershellPath = 'powershell.exe'
		}

		$collectorScriptPath = $null
		try
		{
			if (-not $ProcessCaptureScript)
			{
				throw 'Support bundle process capture helper is unavailable.'
			}

			$collectorScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineSupportBundleCollector_{0}.ps1' -f [guid]::NewGuid().ToString('N'))
			[System.IO.File]::WriteAllText($collectorScriptPath, $ScriptText, [System.Text.Encoding]::UTF8)

			$processResult = & $ProcessCaptureScript -FilePath $powershellPath -ArgumentList @(
				'-NoProfile',
				'-ExecutionPolicy',
				'Bypass',
				'-File',
				$collectorScriptPath
			) -TimeoutSeconds $TimeoutSeconds
		}
		catch [System.TimeoutException]
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleWindowsFeatures:catch1093' -Severity Debug }

			& $writeCollectionWarning ("Support bundle {0} collector timed out after {1} second(s)." -f $Name, $TimeoutSeconds)
			return [pscustomobject][ordered]@{
				Succeeded = $false
				TimedOut  = $true
				Value     = $null
				Error     = $_.Exception.Message
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleWindowsFeatures:catch1103' -Severity Debug }

			& $writeCollectionWarning ("Support bundle {0} collector failed to start: {1}" -f $Name, $_.Exception.Message)
			return [pscustomobject][ordered]@{
				Succeeded = $false
				TimedOut  = $false
				Value     = $null
				Error     = $_.Exception.Message
			}
		}
		finally
		{
			if (-not [string]::IsNullOrWhiteSpace($collectorScriptPath))
			{
				Remove-Item -LiteralPath $collectorScriptPath -Force -ErrorAction SilentlyContinue
			}
		}

		if ($processResult.ExitCode -ne 0)
		{
			$errorText = if (-not [string]::IsNullOrWhiteSpace([string]$processResult.StandardError)) { [string]$processResult.StandardError } else { [string]$processResult.StandardOutput }
			& $writeCollectionWarning ("Support bundle {0} collector exited with code {1}. {2}" -f $Name, [int]$processResult.ExitCode, $errorText)
			return [pscustomobject][ordered]@{
				Succeeded = $false
				TimedOut  = $false
				Value     = $null
				Error     = $errorText
			}
		}

		$json = [string]$processResult.StandardOutput
		if ([string]::IsNullOrWhiteSpace($json))
		{
			return [pscustomobject][ordered]@{
				Succeeded = $true
				TimedOut  = $false
				Value     = $null
				Error     = $null
			}
		}

		try
		{
			$value = $json.Trim() | ConvertFrom-Json
			return [pscustomobject][ordered]@{
				Succeeded = $true
				TimedOut  = $false
				Value     = $value
				Error     = $null
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleWindowsFeatures:catch1147' -Severity Debug }

			& $writeCollectionWarning ("Support bundle {0} collector returned invalid JSON: {1}" -f $Name, $_.Exception.Message)
			return [pscustomobject][ordered]@{
				Succeeded = $false
				TimedOut  = $false
				Value     = $null
				Error     = $_.Exception.Message
			}
		}
	}.GetNewClosure()

	$serviceNames = @('WinRM', 'wuauserv', 'BITS', 'EventLog', 'Schedule', 'WinDefend', 'MpsSvc')
	$services = [System.Collections.Generic.List[pscustomobject]]::new()
	& $notifyProgress -Stage 'WindowsFeatures.Services' -Message 'Collecting Windows service state...'
	foreach ($serviceName in $serviceNames)
	{
		try
		{
			$svc = Get-Service -Name $serviceName -ErrorAction Stop
			[void]$services.Add([pscustomobject][ordered]@{
				Name      = $serviceName
				Status    = [string]$svc.Status
				StartType = [string]$svc.StartType
			})
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleWindowsFeatures:catch1173' -Severity Debug }

			[void]$services.Add([pscustomobject][ordered]@{
				Name      = $serviceName
				Status    = 'Unavailable'
				StartType = $null
			})
		}
	}

	$defender = $null
	$collectionStatus = [ordered]@{
		Services         = 'Collected'
		Defender         = 'NotCollected'
		OptionalFeatures = 'NotCollected'
	}

	& $notifyProgress -Stage 'WindowsFeatures.Defender' -Message 'Collecting Microsoft Defender state...'
	$defenderScript = @'
$ErrorActionPreference = 'Stop'
$mpStatus = Get-MpComputerStatus -ErrorAction Stop
[pscustomobject][ordered]@{
	AMServiceEnabled           = [bool]$mpStatus.AMServiceEnabled
	AntivirusEnabled          = [bool]$mpStatus.AntivirusEnabled
	RealTimeProtectionEnabled = [bool]$mpStatus.RealTimeProtectionEnabled
	IoavProtectionEnabled     = [bool]$mpStatus.IoavProtectionEnabled
	NISEnabled                = [bool]$mpStatus.NISEnabled
	AntispywareEnabled        = [bool]$mpStatus.AntispywareEnabled
} | ConvertTo-Json -Compress -Depth 4
'@
	$defenderResult = & $invokePowerShellJsonCollector -Name 'DefenderStatus' -ScriptText $defenderScript -TimeoutSeconds 10
	if ($defenderResult.Succeeded -and $null -ne $defenderResult.Value)
	{
		$mpStatus = $defenderResult.Value
		$defender = [ordered]@{
			AMServiceEnabled           = [bool]$mpStatus.AMServiceEnabled
			AntivirusEnabled          = [bool]$mpStatus.AntivirusEnabled
			RealTimeProtectionEnabled = [bool]$mpStatus.RealTimeProtectionEnabled
			IoavProtectionEnabled     = [bool]$mpStatus.IoavProtectionEnabled
			NISEnabled                = [bool]$mpStatus.NISEnabled
			AntispywareEnabled        = [bool]$mpStatus.AntispywareEnabled
		}
		$collectionStatus['Defender'] = 'Collected'
	}
	elseif ($defenderResult.TimedOut)
	{
		$collectionStatus['Defender'] = 'TimedOut'
	}
	else
	{
		$collectionStatus['Defender'] = 'Unavailable'
	}

	$optionalFeatures = [System.Collections.Generic.List[pscustomobject]]::new()
	$featureNames = @(
		'Microsoft-Windows-Subsystem-Linux',
		'VirtualMachinePlatform',
		'Microsoft-Hyper-V-All',
		'Containers',
		'NetFx3',
		'IIS-WebServerRole',
		'TelnetClient',
		'SMB1Protocol'
	)
	$featureStateByName = @{}
	& $notifyProgress -Stage 'WindowsFeatures.OptionalFeatures' -Message 'Collecting optional Windows feature state...'
	$featureNamesJson = @($featureNames) | ConvertTo-Json -Compress
	$optionalFeatureScript = @"
`$ErrorActionPreference = 'Stop'
`$targetNames = @((@'
$featureNamesJson
'@) | ConvertFrom-Json)
`$targetLookup = @{}
foreach (`$name in `$targetNames) { `$targetLookup[[string]`$name] = `$true }
`$features = Get-WindowsOptionalFeature -Online -ErrorAction Stop
`$selected = foreach (`$feature in @(`$features))
{
	`$featureName = [string]`$feature.FeatureName
	if (`$targetLookup.ContainsKey(`$featureName))
	{
		[pscustomobject][ordered]@{
			Name = `$featureName
			State = [string]`$feature.State
		}
	}
}
@(`$selected) | ConvertTo-Json -Compress -Depth 4
"@
	$optionalFeatureResult = & $invokePowerShellJsonCollector -Name 'WindowsOptionalFeatures' -ScriptText $optionalFeatureScript -TimeoutSeconds 20
	if ($optionalFeatureResult.Succeeded -and $null -ne $optionalFeatureResult.Value)
	{
		foreach ($feature in @($optionalFeatureResult.Value))
		{
			if ($feature -and $feature.PSObject.Properties['Name'])
			{
				$featureStateByName[[string]$feature.Name] = [string]$feature.State
			}
		}
		$collectionStatus['OptionalFeatures'] = 'Collected'
	}
	elseif ($optionalFeatureResult.TimedOut)
	{
		$collectionStatus['OptionalFeatures'] = 'TimedOut'
	}
	else
	{
		$collectionStatus['OptionalFeatures'] = 'Unavailable'
	}

	foreach ($featureName in $featureNames)
	{
		if ($featureStateByName.ContainsKey($featureName))
		{
			[void]$optionalFeatures.Add([pscustomobject][ordered]@{
				Name  = $featureName
				State = [string]$featureStateByName[$featureName]
			})
			continue
		}

		[void]$optionalFeatures.Add([pscustomobject][ordered]@{
			Name  = $featureName
			State = 'Unavailable'
		})
	}

	return [pscustomobject][ordered]@{
		Schema           = 'Baseline.WindowsFeatures'
		SchemaVersion    = 1
		GeneratedAt      = [System.DateTime]::UtcNow.ToString('o')
		CollectionStatus = [pscustomobject]$collectionStatus
		Services         = @($services)
		Defender         = $defender
		OptionalFeatures = @($optionalFeatures)
	}
}

function Get-BaselineSupportBundleDirectorySummary
{
	param (
		[Parameter(Mandatory = $true)][string]$Name,
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Path
	)

	$summary = [ordered]@{
		Name           = $Name
		Path           = $Path
		Exists         = $false
		FileCount      = 0
		DirectoryCount = 0
		Bytes          = 0
		Error          = $null
	}

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path))
	{
		return [pscustomobject]$summary
	}

	$summary['Exists'] = $true
	try
	{
		$rootPath = [System.IO.Path]::GetFullPath($Path)
		$directories = New-Object 'System.Collections.Generic.Stack[string]'
		$directories.Push($rootPath)
		while ($directories.Count -gt 0)
		{
			$currentDirectory = $directories.Pop()
			try
			{
				foreach ($directoryPath in [System.IO.Directory]::EnumerateDirectories($currentDirectory))
				{
					$summary['DirectoryCount'] = [int]$summary['DirectoryCount'] + 1
					try
					{
						$directoryInfo = [System.IO.DirectoryInfo]::new($directoryPath)
						if (($directoryInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
						{
							continue
						}
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDirectorySummary:catch1356' -Severity Debug }

						if ([string]::IsNullOrWhiteSpace([string]$summary['Error'])) { $summary['Error'] = $_.Exception.Message }
						continue
					}
					$directories.Push($directoryPath)
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDirectorySummary:catch1364' -Severity Debug }

				if ([string]::IsNullOrWhiteSpace([string]$summary['Error'])) { $summary['Error'] = $_.Exception.Message }
			}

			try
			{
				foreach ($filePath in [System.IO.Directory]::EnumerateFiles($currentDirectory))
				{
					$fileInfo = [System.IO.FileInfo]::new($filePath)
					if (($fileInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
					{
						continue
					}
				$summary['FileCount'] = [int]$summary['FileCount'] + 1
					$summary['Bytes'] = [int64]$summary['Bytes'] + [int64]$fileInfo.Length
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDirectorySummary:catch1382' -Severity Debug }

				if ([string]::IsNullOrWhiteSpace([string]$summary['Error'])) { $summary['Error'] = $_.Exception.Message }
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleDirectorySummary:catch1388' -Severity Debug }

		$summary['Error'] = $_.Exception.Message
	}

	return [pscustomobject]$summary
}

function New-BaselineSupportBundleStorageSummary
{
	[CmdletBinding()]
	param ()

	$localAppData = $env:LOCALAPPDATA
	$tempRoot = [System.IO.Path]::GetTempPath()
	$commonAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
	$baselineRoot = if (-not [string]::IsNullOrWhiteSpace($localAppData)) { Join-Path $localAppData 'Baseline' } else { $null }
	$localTempBaseline = if (-not [string]::IsNullOrWhiteSpace($localAppData)) { Join-Path (Join-Path $localAppData 'Temp') 'Baseline' } else { $null }
	$tempBaseline = Join-Path $tempRoot 'Baseline'
	$userStatePath = if (-not [string]::IsNullOrWhiteSpace($baselineRoot)) { Join-Path $baselineRoot 'UserState' } else { $null }
	$runtimeCachePath = if (-not [string]::IsNullOrWhiteSpace($commonAppData)) { Join-Path (Join-Path (Join-Path $commonAppData 'Baseline') 'RuntimeCache') 'RC' } else { $null }
	$legacyRuntimeCachePath = if (-not [string]::IsNullOrWhiteSpace($localTempBaseline)) { Join-Path $localTempBaseline 'RC' } else { $null }
	$localTempLogsPath = if (-not [string]::IsNullOrWhiteSpace($localTempBaseline)) { Join-Path $localTempBaseline 'Logs' } else { $null }
	$summaryByPath = @{}
	$directorySummaryCommand = Get-Command -Name 'Get-BaselineSupportBundleDirectorySummary' -CommandType Function -ErrorAction SilentlyContinue
	$directorySummaryScript = if ($directorySummaryCommand) { $directorySummaryCommand.ScriptBlock } else { $null }
	$getDirectorySummary = {
		param(
			[string]$Name,
			[string]$Path
		)

		$cacheKey = $null
		if (-not [string]::IsNullOrWhiteSpace($Path))
		{
			try { $cacheKey = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).ToLowerInvariant() }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleStorageSummary:catch1424' -Severity Debug }
			 $cacheKey = $null }
		}

		if (-not [string]::IsNullOrWhiteSpace($cacheKey) -and $summaryByPath.ContainsKey($cacheKey))
		{
			$cached = $summaryByPath[$cacheKey]
			return [pscustomobject][ordered]@{
				Name           = $Name
				Path           = $Path
				Exists         = [bool]$cached.Exists
				FileCount      = [int]$cached.FileCount
				DirectoryCount = [int]$cached.DirectoryCount
				Bytes          = [int64]$cached.Bytes
				Error          = $cached.Error
			}
		}

		if (-not $directorySummaryScript)
		{
			throw 'Support bundle directory summary helper is unavailable.'
		}

		$summary = & $directorySummaryScript -Name $Name -Path $Path
		if (-not [string]::IsNullOrWhiteSpace($cacheKey))
		{
			$summaryByPath[$cacheKey] = $summary
		}
		return $summary
	}.GetNewClosure()

	$locations = @(
		(& $getDirectorySummary -Name 'BaselineAppData' -Path $baselineRoot),
		(& $getDirectorySummary -Name 'UserState' -Path $userStatePath),
		(& $getDirectorySummary -Name 'BaselineLocalTemp' -Path $localTempBaseline),
		(& $getDirectorySummary -Name 'RuntimeCache' -Path $runtimeCachePath),
		(& $getDirectorySummary -Name 'LegacyLocalRuntimeCache' -Path $legacyRuntimeCachePath),
		(& $getDirectorySummary -Name 'LocalTempLogs' -Path $localTempLogsPath),
		(& $getDirectorySummary -Name 'TempBaseline' -Path $tempBaseline),
		(& $getDirectorySummary -Name 'TempBaselineLogs' -Path (Join-Path $tempBaseline 'Logs'))
	)

	return [pscustomobject][ordered]@{
		Schema        = 'Baseline.StorageSummary'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
		Locations     = @($locations)
	}
}

function New-BaselineSupportBundleUserActionContext
{
	[CmdletBinding()]
	param (
		[string]$ProfilePath,
		[object]$ReproductionContext,
		[object]$ConfigStatePre,
		[object]$ConfigStatePost
	)

	$sessionState = $ConfigStatePost
	if ($null -eq $sessionState -and -not [string]::IsNullOrWhiteSpace($ProfilePath) -and (Test-Path -LiteralPath $ProfilePath))
	{
		try
		{
			$profileJson = [System.IO.File]::ReadAllText($ProfilePath, [System.Text.UTF8Encoding]::new($false))
			$profile = if (Get-Command -Name 'ConvertFrom-BaselineJson' -ErrorAction SilentlyContinue)
			{
				$profileJson | ConvertFrom-BaselineJson -Depth 32
			}
			else
			{
				$profileJson | ConvertFrom-Json
			}
			$profileState = Get-BaselineSupportBundleObjectValue -InputObject $profile -Name 'State'
			if ($null -ne $profileState) { $sessionState = $profileState } else { $sessionState = $profile }
		}
		catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleUserActionContext:catch1500' -Severity Debug }
		 $sessionState = $null }
	}

	$selectedPreset = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'SelectedPreset'
	$explicitSelections = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'ExplicitSelections'
	$explicitSelectionDefinitions = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'ExplicitSelectionDefinitions'
	$selectedTweaks = @()
	if ($null -ne $explicitSelectionDefinitions)
	{
		$selectedTweaks = @($explicitSelectionDefinitions)
	}
	elseif ($null -ne $explicitSelections)
	{
		$selectedTweaks = @($explicitSelections)
	}

	return [pscustomobject][ordered]@{
		Schema              = 'Baseline.UserActionContext'
		SchemaVersion       = 1
		GeneratedAt         = [System.DateTime]::UtcNow.ToString('o')
		PresetUsed          = $selectedPreset
		SelectedTweaks      = @($selectedTweaks)
		SafeMode            = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'SafeMode'
		ExpertMode          = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'AdvancedMode'
		UIDensity           = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'UIDensity'
		CurrentPrimaryTab   = Get-BaselineSupportBundleObjectValue -InputObject $sessionState -Name 'CurrentPrimaryTab'
		HasPreConfigState   = ($null -ne $ConfigStatePre)
		HasPostConfigState  = ($null -ne $ConfigStatePost)
		ReproductionContext = $ReproductionContext
	}
}

<#
	.SYNOPSIS
	Build a richer system info snapshot for support bundles.

	.DESCRIPTION
	Captures OS / SKU / arch / domain join / elevation / WinRM / Defender state /
	GPO summary / package counts. All probes are best-effort - a single failure
	never aborts the snapshot. Sensitive values (domain name, full GPO output,
	signature lists) are deliberately omitted.
#>
function New-BaselineSupportBundleSystemInfo
{
	$info = [ordered]@{
		Schema        = 'Baseline.SystemInfo'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
	}

	try
	{
		$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
		$info['OS'] = [ordered]@{
			Caption       = [string]$os.Caption
			Version       = [string]$os.Version
			BuildNumber   = [string]$os.BuildNumber
			Architecture  = [string]$os.OSArchitecture
			InstallDate   = if ($os.InstallDate) { [datetime]$os.InstallDate | ForEach-Object { $_.ToUniversalTime().ToString('o') } } else { $null }
			LastBootUpTime = if ($os.LastBootUpTime) { [datetime]$os.LastBootUpTime | ForEach-Object { $_.ToUniversalTime().ToString('o') } } else { $null }
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1562' -Severity Debug }

		$info['OS'] = [ordered]@{
			Caption      = [string][System.Environment]::OSVersion.VersionString
			Version      = [string][System.Environment]::OSVersion.Version
			Architecture = if ([System.Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
		}
	}

	try
	{
		$sku = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
		$info['SKU'] = [string]$sku
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1576' -Severity Debug }
	 $info['SKU'] = $null }

	try
	{
		$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
		$info['DomainJoined'] = [bool]$cs.PartOfDomain
		$info['SystemType']   = [string]$cs.SystemType
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1584' -Severity Debug }

		$info['DomainJoined'] = $null
		$info['SystemType']   = $null
	}

	try
	{
		$current = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		$principal = [System.Security.Principal.WindowsPrincipal]::new($current)
		$info['Elevated'] = [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1596' -Severity Debug }
	 $info['Elevated'] = $null }

	$info['PowerShell'] = [ordered]@{
		Edition = [string]$PSVersionTable.PSEdition
		Version = [string]$PSVersionTable.PSVersion
	}

	try
	{
		$winrm = Get-Service -Name WinRM -ErrorAction Stop
		$info['WinRM'] = [ordered]@{
			Status    = [string]$winrm.Status
			StartType = [string]$winrm.StartType
		}
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1611' -Severity Debug }
	 $info['WinRM'] = $null }

	try
	{
		if (Get-Command -Name 'Get-MpPreference' -ErrorAction SilentlyContinue)
		{
			$mp = Get-MpPreference -ErrorAction Stop
			$info['Defender'] = [ordered]@{
				DisableRealtimeMonitoring = [bool]$mp.DisableRealtimeMonitoring
				DisableBehaviorMonitoring = [bool]$mp.DisableBehaviorMonitoring
				DisableScriptScanning     = [bool]$mp.DisableScriptScanning
				PUAProtection             = [string]$mp.PUAProtection
				MAPSReporting             = [string]$mp.MAPSReporting
			}
		}
		else { $info['Defender'] = $null }
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1628' -Severity Debug }
	 $info['Defender'] = $null }

	try
	{
		# gpresult /r outputs a long human-readable report; capture only that
		# the user has GPO scope at all, not the full content.
		$gpResult = & gpresult /r /scope:computer 2>$null | Select-Object -First 60
		$info['GPO'] = [ordered]@{
			Available = ($LASTEXITCODE -eq 0)
			LineCount = if ($gpResult) { ([string[]]$gpResult).Count } else { 0 }
		}
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1640' -Severity Debug }
	 $info['GPO'] = [ordered]@{ Available = $false; LineCount = 0 } }

	$pkgCounts = [ordered]@{}
	try
	{
		if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue)
		{
			$wingetLines = & winget list --accept-source-agreements 2>$null
			# winget list emits a header + separator + entries; subtract them.
			$pkgCounts['Winget'] = [Math]::Max(0, ([string[]]$wingetLines).Count - 2)
		}
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1652' -Severity Debug }
	 $pkgCounts['Winget'] = $null }
	try
	{
		if (Get-Command -Name 'choco' -ErrorAction SilentlyContinue)
		{
			$chocoLines = & choco list --local-only --limit-output 2>$null
			$pkgCounts['Chocolatey'] = ([string[]]$chocoLines).Count
		}
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1661' -Severity Debug }
	 $pkgCounts['Chocolatey'] = $null }
	$info['PackageCounts'] = $pkgCounts

	# VM detection - best-effort via CIM Manufacturer/Model.
	try
	{
		$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
		$model = ([string]$cs.Model).ToLowerInvariant()
		$mfg = ([string]$cs.Manufacturer).ToLowerInvariant()
		$hypervisor = $null
		if ($mfg -match 'microsoft' -and $model -match 'virtual') { $hypervisor = 'Hyper-V' }
		elseif ($mfg -match 'vmware') { $hypervisor = 'VMware' }
		elseif ($mfg -match 'parallels') { $hypervisor = 'Parallels' }
		elseif ($model -match 'virtualbox') { $hypervisor = 'VirtualBox' }
		elseif ($model -match 'kvm|qemu') { $hypervisor = 'KVM/QEMU' }
		$info['Virtualization'] = [ordered]@{
			IsVM       = ($null -ne $hypervisor)
			Hypervisor = $hypervisor
		}
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.New-BaselineSupportBundleSystemInfo:catch1681' -Severity Debug }
	 $info['Virtualization'] = $null }

	return [pscustomobject]$info
}

<#
	.SYNOPSIS
	Scrape recent ERROR / WARNING entries from the daily log and classify them.

	.DESCRIPTION
	Lightweight pattern classifier - categories match the Errors.json contract
	in todo.md (#14): AUTH / NETWORK / POLICY / DEPENDENCY / UNKNOWN. Pure-text
	matching against the Exception.Message tail of the log line - no parsing,
	no PowerShell ErrorRecord reconstruction.
#>
function Get-BaselineSupportBundleClassifiedErrors
{
	param (
		[Parameter(Mandatory = $true)][string]$LogPath,
		[int]$MaxErrors = 200
	)

	if (-not (Test-Path -LiteralPath $LogPath)) { return $null }

	$lines = $null
	try
	{
		# Use FileShare.ReadWrite so a live writer doesn't block us.
		$fs = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
		try
		{
			$reader = [System.IO.StreamReader]::new($fs, [System.Text.UTF8Encoding]::new($false))
			try { $lines = $reader.ReadToEnd() -split "`r?`n" }
			finally { $reader.Dispose() }
		}
		finally { $fs.Dispose() }
	}
	catch {
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SupportBundle.Helpers.Get-BaselineSupportBundleClassifiedErrors:catch1718' -Severity Debug }
	 return $null }

	$classified = [System.Collections.Generic.List[pscustomobject]]::new()
	$counts = [ordered]@{ AUTH = 0; NETWORK = 0; POLICY = 0; DEPENDENCY = 0; UNKNOWN = 0 }

	for ($i = $lines.Count - 1; $i -ge 0; $i--)
	{
		$line = $lines[$i]
		if ([string]::IsNullOrWhiteSpace($line)) { continue }
		# Match the LogMessage format: "dd-MM-yyyy HH:mm LEVEL: ..."
		if ($line -notmatch '\b(ERROR|WARNING)\b') { continue }
		if ($classified.Count -ge $MaxErrors) { break }

		$msg = $line.ToLowerInvariant()
		$category = 'UNKNOWN'
		if ($msg -match 'access\s+denied|unauthor|requires?\s+administrator|elevation|elevated|hresult: 0x80070005|0x80004003') { $category = 'AUTH' }
		elseif ($msg -match 'network|wininet|dns|proxy|connection\s+(refused|reset|timed)|host\s+(unreachable|not\s+found)|wsaeconnaborted|0x800705b4|timed?\s*out') { $category = 'NETWORK' }
		elseif ($msg -match 'group\s+policy|gpo\b|policy\s+(restricted|prevents)|disabled\s+by\s+(your\s+)?administrator|managed\s+by\s+your\s+organization') { $category = 'POLICY' }
		elseif ($msg -match 'not\s+found|missing|cannot\s+find|no\s+such\s+file|service\s+(not\s+installed|missing)|cmdletnot|commandnot|cannot\s+load|module\s+not\s+found') { $category = 'DEPENDENCY' }

		$stackTrace = [System.Collections.Generic.List[string]]::new()
		for ($stackIndex = $i + 1; $stackIndex -lt $lines.Count -and $stackTrace.Count -lt 20; $stackIndex++)
		{
			$stackLine = [string]$lines[$stackIndex]
			if ([string]::IsNullOrWhiteSpace($stackLine)) { continue }
			if ($stackLine -match '\b(INFO|DEBUG|WARNING|ERROR)\b') { break }
			if ($stackLine -match '^\s+at\s+|^\s+in\s+.*:\s*line\s+\d+|^\s*\+\s+|^\s*CategoryInfo\s*:|^\s*FullyQualifiedErrorId\s*:|^\s*ScriptStackTrace\s*:|^\s*Exception\s*:')
			{
				[void]$stackTrace.Add($stackLine)
				continue
			}
			if ($stackTrace.Count -gt 0) { break }
		}

		$counts[$category]++
		[void]$classified.Add([pscustomobject]@{
			Category   = $category
			Line       = $line
			StackTrace = @($stackTrace)
		})
	}

	return [pscustomobject][ordered]@{
		Schema        = 'Baseline.ClassifiedErrors'
		SchemaVersion = 1
		GeneratedAt   = [System.DateTime]::UtcNow.ToString('o')
		Source        = $LogPath
		Counts        = $counts
		Errors        = @($classified)
	}
}
