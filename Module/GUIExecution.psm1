using module .\Logging.psm1
using module .\SharedHelpers.psm1


<#
    .SYNOPSIS
    Internal GUI execution helper module for Baseline.

    .DESCRIPTION
    Provides cleanup and run-state helpers used by the GUI execution flow.
    This is internal runtime plumbing, not user-facing documentation.
#>

function Get-GuiExecutionOperationMode
{
	[CmdletBinding()]
	param ()

	$mode = $null
	try
	{
		if (Get-Command -Name Get-BaselineOperationMode -ErrorAction SilentlyContinue)
		{
			$mode = Get-BaselineOperationMode
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Get-GuiExecutionOperationMode:catch27' -Severity Debug }

		$mode = $null
	}

	if ([string]::IsNullOrWhiteSpace([string]$mode))
	{
		$mode = [System.Environment]::GetEnvironmentVariable('BASELINE_OPERATION_MODE')
	}

	if ([string]$mode -in @('ReadOnly', 'ReadWrite'))
	{
		return [string]$mode
	}

	return 'ReadWrite'
}

function Get-GuiExecutionThemeSnapshot
{
	[CmdletBinding()]
	param ()

	$theme = Get-Variable -Name 'BaselineCurrentTheme' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
	$themeName = Get-Variable -Name 'BaselineCurrentThemeName' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
	$useDarkMode = Get-Variable -Name 'BaselineUseDarkMode' -Scope Global -ValueOnly -ErrorAction SilentlyContinue

	if ([string]::IsNullOrWhiteSpace([string]$themeName))
	{
		$themeName = [System.Environment]::GetEnvironmentVariable('BASELINE_THEME_NAME')
	}

	$themeModeFlag = [System.Environment]::GetEnvironmentVariable('BASELINE_USE_DARK_MODE')
	if ($null -eq $useDarkMode -and -not [string]::IsNullOrWhiteSpace([string]$themeModeFlag))
	{
		$useDarkMode = ([string]$themeModeFlag -eq '1')
	}

	return [pscustomobject]@{
		Theme       = $theme
		ThemeName   = $themeName
		UseDarkMode = $useDarkMode
	}
}

function Set-GuiExecutionRunspaceThemeSnapshot
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Runspace
	)

	$themeSnapshot = Get-GuiExecutionThemeSnapshot
	$Runspace.SessionStateProxy.SetVariable('bgCurrentTheme', $themeSnapshot.Theme)
	$Runspace.SessionStateProxy.SetVariable('bgCurrentThemeName', $themeSnapshot.ThemeName)
	$Runspace.SessionStateProxy.SetVariable('bgUseDarkMode', $themeSnapshot.UseDarkMode)
}

function Get-GuiPreRunSnapshotTimeoutSeconds
{
	[CmdletBinding()]
	param ()

	$rawTimeout = [System.Environment]::GetEnvironmentVariable('BASELINE_PRE_RUN_SNAPSHOT_TIMEOUT_SECONDS')
	$parsedTimeout = 0
	if (-not [string]::IsNullOrWhiteSpace([string]$rawTimeout) -and [int]::TryParse([string]$rawTimeout, [ref]$parsedTimeout) -and $parsedTimeout -gt 0)
	{
		return $parsedTimeout
	}

	return 120
}

function Write-GuiExecutionQueueRunNotice
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$RunState,

		[Parameter(Mandatory = $true)]
		[string]$Message,

		[ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
		[string]$Level = 'DEBUG',

		[switch]$Progress,

		[switch]$ProgressOnly
	)

	if (-not $RunState -or -not $RunState.ContainsKey('LogQueue') -or -not $RunState['LogQueue'])
	{
		return
	}

	try
	{
		$RunState['LogQueue'].Enqueue([PSCustomObject]@{
			Kind = '_RunNotice'
			Level = $Level
			Message = $Message
			Progress = [bool]$Progress
			ProgressOnly = [bool]$ProgressOnly
			Diagnostic = $true
		})
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to enqueue GUI execution notice: $($_.Exception.Message)"
	}
}

function Stop-GuiPreRunSnapshotCaptureAsync
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	$completed = $false

	try
	{
		if ($Worker.PowerShell)
		{
			$stopResult = $Worker.PowerShell.BeginStop($null, $null)
			if ($stopResult -and $stopResult.AsyncWaitHandle)
			{
				if ($stopResult.AsyncWaitHandle.WaitOne(1000))
				{
					try { $Worker.PowerShell.EndStop($stopResult) } catch { Write-GuiExecutionCleanupWarning "Failed to finalize pre-run snapshot stop: $($_.Exception.Message)" }
				}
			}
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to request pre-run snapshot worker stop: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.AsyncResult)
		{
			if (-not $Worker.AsyncResult.IsCompleted)
			{
				$Worker.AsyncResult.AsyncWaitHandle.WaitOne(1000) | Out-Null
			}
			$completed = [bool]$Worker.AsyncResult.IsCompleted
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed while waiting for pre-run snapshot worker stop: $($_.Exception.Message)"
	}

	try
	{
		if ($completed -and $Worker.PowerShell -and $Worker.AsyncResult)
		{
			$Worker.PowerShell.EndInvoke($Worker.AsyncResult)
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to finalize pre-run snapshot worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.PowerShell)
		{
			$Worker.PowerShell.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose pre-run snapshot PowerShell worker: $($_.Exception.Message)"
	}

	try
	{
		if ($completed -and $Worker.Runspace)
		{
			$Worker.Runspace.Close()
			$Worker.Runspace.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose pre-run snapshot runspace: $($_.Exception.Message)"
	}
}

function Request-GuiExecutionPowerShellStopAsync
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		$PowerShell,

		[string]$Source = 'GUIExecution.PowerShellStop',

		[int]$StopWaitMilliseconds = 1000
	)

	if (-not $PowerShell)
	{
		return $true
	}

	try
	{
		$stopResult = $PowerShell.BeginStop($null, $null)
		if ($stopResult -and $stopResult.AsyncWaitHandle)
		{
			if ($stopResult.AsyncWaitHandle.WaitOne([Math]::Max(0, $StopWaitMilliseconds)))
			{
				try { $PowerShell.EndStop($stopResult) }
				catch { Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.EndStop') -Severity Debug }
				return $true
			}

			return $false
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source $Source -Severity Warning
		return $false
	}

	return $true
}

function Invoke-GuiPreRunSnapshotCapture
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$LoaderPath,

		[Parameter(Mandatory = $true)]
		[string]$LocalizationDirectory,

		[Parameter(Mandatory = $true)]
		[string]$UICulture,

		[Parameter(Mandatory = $true)]
		[string]$LogFilePath,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$LogMode,

		[Parameter(Mandatory = $true)]
		[string]$OperationMode,

		[Parameter(Mandatory = $true)]
		[int]$TimeoutSeconds,

		[AllowNull()]
		[hashtable]$RunState = $null
	)

	if ($TimeoutSeconds -le 0)
	{
		$TimeoutSeconds = Get-GuiPreRunSnapshotTimeoutSeconds
	}

	$snapshotState = [hashtable]::Synchronized(@{
		Done = $false
		ErrorMessage = $null
		Snapshot = $null
		SnapshotPath = $null
		EntryCount = 0
		LastProgress = $null
	})
	$progressQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
	$logQueue = if ($RunState -and $RunState.ContainsKey('LogQueue')) { $RunState['LogQueue'] } else { $null }

	$snapshotRunspace = [runspacefactory]::CreateRunspace()
	$snapshotRunspace.ApartmentState = 'STA'
	$snapshotRunspace.ThreadOptions = 'ReuseThread'
	$snapshotRunspace.Open()
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotLoaderPath', $LoaderPath)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotLocDir', $LocalizationDirectory)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotUICulture', $UICulture)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotLogFilePath', $LogFilePath)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotLogMode', $LogMode)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotOperationMode', $OperationMode)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotState', $snapshotState)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotProgressQueue', $progressQueue)
	$snapshotRunspace.SessionStateProxy.SetVariable('snapshotLogQueue', $logQueue)
	Set-GuiExecutionRunspaceThemeSnapshot -Runspace $snapshotRunspace

	$snapshotWorker = [powershell]::Create().AddScript({
		try
		{
			$Global:GUIMode = $true
			if ([string]::IsNullOrWhiteSpace([string]$snapshotOperationMode))
			{
				$snapshotOperationMode = 'ReadWrite'
			}
			$Global:BaselineOperationMode = [string]$snapshotOperationMode
			[System.Environment]::SetEnvironmentVariable('BASELINE_OPERATION_MODE', [string]$snapshotOperationMode, [System.EnvironmentVariableTarget]::Process)
			if ($bgCurrentTheme -is [System.Collections.IDictionary])
			{
				$Global:BaselineCurrentTheme = $bgCurrentTheme
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$bgCurrentThemeName))
			{
				$Global:BaselineCurrentThemeName = [string]$bgCurrentThemeName
			}
			if ($null -ne $bgUseDarkMode)
			{
				$Global:BaselineUseDarkMode = [bool]$bgUseDarkMode
			}

			$snapshotModuleRoot = Split-Path $snapshotLoaderPath -Parent
			$snapshotImportProgress = [pscustomobject]@{
				Stage    = 'ModuleImport'
				Index    = 0
				Total    = 0
				Name     = 'Baseline module import'
				Function = 'Import-Module'
				Key      = 'Baseline module import|Import-Module'
				Category = 'Execution'
			}
			$snapshotState['LastProgress'] = $snapshotImportProgress
			$snapshotProgressQueue.Enqueue([PSCustomObject]@{
				Message = 'Execution worker snapshot importing Baseline modules.'
				Progress = $snapshotImportProgress
			})

			. (Join-Path $snapshotModuleRoot 'SharedHelpers\Json.Helpers.ps1')
			. (Join-Path $snapshotModuleRoot 'SharedHelpers\Localization.Helpers.ps1')
			$Global:Localization = Import-BaselineLocalization -BaseDirectory $snapshotLocDir -UICulture $snapshotUICulture
			[void](Set-BaselineThreadCulture -UICulture $snapshotUICulture)

			$Global:LogFilePath = $snapshotLogFilePath
			Import-Module $snapshotLoaderPath -Force -Global -ErrorAction Stop
			if (Get-Command -Name Set-BaselineOperationMode -ErrorAction SilentlyContinue)
			{
				Set-BaselineOperationMode -Mode ([string]$snapshotOperationMode)
			}

			$global:LogFilePath = $snapshotLogFilePath
			Set-LogFile -Path $snapshotLogFilePath
			Set-LogMode -Mode $snapshotLogMode
			if ($snapshotLogQueue)
			{
				Set-UILogHandler { param($entry) $snapshotLogQueue.Enqueue($entry) }
			}

			$snapshotDetectScriptblocks = @{}
			$snapshotVisibleIfScriptblocks = @{}
			$detectScriptblocksPath = Join-Path $snapshotModuleRoot 'GUI\DetectScriptblocks.ps1'
			if (Test-Path -LiteralPath $detectScriptblocksPath)
			{
				. $detectScriptblocksPath
				$detectScriptblocksVariable = Get-Variable -Scope Script -Name 'DetectScriptblocks' -ErrorAction SilentlyContinue
				$visibleIfScriptblocksVariable = Get-Variable -Scope Script -Name 'VisibleIfScriptblocks' -ErrorAction SilentlyContinue
				if ($detectScriptblocksVariable -and $detectScriptblocksVariable.Value -is [hashtable])
				{
					$snapshotDetectScriptblocks = $detectScriptblocksVariable.Value
				}
				if ($visibleIfScriptblocksVariable -and $visibleIfScriptblocksVariable.Value -is [hashtable])
				{
					$snapshotVisibleIfScriptblocks = $visibleIfScriptblocksVariable.Value
				}
			}

			$snapshotManifestProgress = [pscustomobject]@{
				Stage    = 'Manifest'
				Index    = 0
				Total    = 0
				Name     = 'Snapshot manifest metadata'
				Function = 'Import-TweakManifestFromData'
				Key      = 'Snapshot manifest metadata|Import-TweakManifestFromData'
				Category = 'Execution'
			}
			$snapshotState['LastProgress'] = $snapshotManifestProgress
			$snapshotProgressQueue.Enqueue([PSCustomObject]@{
				Message = 'Execution worker snapshot loading manifest metadata.'
				Progress = $snapshotManifestProgress
			})

			$snapshotManifest = Import-TweakManifestFromData -DetectScriptblocks $snapshotDetectScriptblocks -VisibleIfScriptblocks $snapshotVisibleIfScriptblocks
			try
			{
				$snapshotSystemInfo = Get-BaselineSystemPlatformInfo
				$null = Update-BaselineManifestAvailability -Manifest $snapshotManifest -SystemInfo $snapshotSystemInfo
				$null = Update-BaselineManifestExecutionSupport -Manifest $snapshotManifest
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.PreRunSnapshotWorker.ManifestAvailabilityStamp'
			}

			$progressCallback = {
				param([object]$SnapshotProgress)

				if ($null -eq $SnapshotProgress)
				{
					return
				}

				$snapshotState['LastProgress'] = $SnapshotProgress
				$stage = if ($SnapshotProgress.PSObject.Properties['Stage']) { [string]$SnapshotProgress.Stage } else { '' }
				$functionName = if ($SnapshotProgress.PSObject.Properties['Function']) { [string]$SnapshotProgress.Function } else { '' }
				$entryName = if ($SnapshotProgress.PSObject.Properties['Name']) { [string]$SnapshotProgress.Name } else { '' }
				$index = if ($SnapshotProgress.PSObject.Properties['Index']) { [int]$SnapshotProgress.Index } else { 0 }
				$total = if ($SnapshotProgress.PSObject.Properties['Total']) { [int]$SnapshotProgress.Total } else { 0 }

				if ($stage -eq 'SystemInfo')
				{
					$message = 'Execution worker snapshot checking system information.'
				}
				elseif ($total -gt 0)
				{
					$label = if (-not [string]::IsNullOrWhiteSpace($functionName)) { $functionName } else { $entryName }
					if (-not [string]::IsNullOrWhiteSpace($entryName) -and $entryName -ne $label)
					{
						$label = '{0} ({1})' -f $label, $entryName
					}
					$message = 'Execution worker snapshot checking {0}/{1}: {2}.' -f $index, $total, $label
				}
				else
				{
					$message = 'Execution worker snapshot checking manifest entry.'
				}

				$snapshotProgressQueue.Enqueue([PSCustomObject]@{
					Message = $message
					Progress = $SnapshotProgress
					ProgressOnly = $true
				})
			}

			$snapshot = New-SystemStateSnapshot -Manifest $snapshotManifest -ProgressCallback $progressCallback
			$snapshotDir = Join-Path (Get-BaselineDataDirectory) 'Snapshots'
			if (-not (Test-Path -LiteralPath $snapshotDir)) { New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null }
			Limit-SnapshotDirectory -Directory $snapshotDir -Keep 10
			$snapshotPath = Join-Path $snapshotDir ('PreRun-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
			Export-SystemStateSnapshot -Snapshot $snapshot -Path $snapshotPath

			$snapshotState['Snapshot'] = $snapshot
			$snapshotState['SnapshotPath'] = $snapshotPath
			$snapshotState['EntryCount'] = [int]@($snapshot.Entries).Count
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Invoke-GuiPreRunSnapshotCapture:catch487' -Severity Debug }

			$snapshotState['ErrorMessage'] = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Pre-run snapshot capture failed.' } else { [string]$_.Exception.Message }
		}
		finally
		{
			try { if (Get-Command -Name Clear-LogMode -ErrorAction SilentlyContinue) { Clear-LogMode } } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Invoke-GuiPreRunSnapshotCapture:catch493' -Severity Debug }
			 }
			$snapshotState['Done'] = $true
		}
	})
	$snapshotWorker.Runspace = $snapshotRunspace

	$startedAt = Get-Date
	$asyncResult = $snapshotWorker.BeginInvoke()
	$timedOut = $false
	$aborted = $false
	$completed = $false
	$cleanupScheduled = $false

	try
	{
		while (-not $asyncResult.AsyncWaitHandle.WaitOne(250))
		{
			$progressItem = $null
			while ($progressQueue.TryDequeue([ref]$progressItem))
			{
				if ($progressItem -and $progressItem.PSObject.Properties['Message'])
				{
					$progressOnly = ($progressItem.PSObject.Properties['ProgressOnly'] -and [bool]$progressItem.ProgressOnly)
					Write-GuiExecutionQueueRunNotice -RunState $RunState -Message ([string]$progressItem.Message) -Progress -ProgressOnly:$progressOnly
				}
				$progressItem = $null
			}

			if ($RunState -and [bool]$RunState['AbortRequested'])
			{
				$aborted = $true
				break
			}

			if (((Get-Date) - $startedAt).TotalSeconds -ge [double]$TimeoutSeconds)
			{
				$timedOut = $true
				break
			}
		}

		$progressItem = $null
		while ($progressQueue.TryDequeue([ref]$progressItem))
		{
			if ($progressItem -and $progressItem.PSObject.Properties['Message'])
			{
				$progressOnly = ($progressItem.PSObject.Properties['ProgressOnly'] -and [bool]$progressItem.ProgressOnly)
				Write-GuiExecutionQueueRunNotice -RunState $RunState -Message ([string]$progressItem.Message) -Progress -ProgressOnly:$progressOnly
			}
			$progressItem = $null
		}

		if ($timedOut -or $aborted)
		{
			Stop-GuiPreRunSnapshotCaptureAsync -Worker ([pscustomobject]@{
				PowerShell = $snapshotWorker
				AsyncResult = $asyncResult
				Runspace = $snapshotRunspace
			})
			$cleanupScheduled = $true

			return [pscustomobject]@{
				Succeeded = $false
				TimedOut = $timedOut
				Aborted = $aborted
				ErrorMessage = $null
				Snapshot = $null
				SnapshotPath = $null
				EntryCount = 0
				LastProgress = $snapshotState['LastProgress']
				DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
			}
		}

		$completed = $true
		$null = $snapshotWorker.EndInvoke($asyncResult)
		if (-not [string]::IsNullOrWhiteSpace([string]$snapshotState['ErrorMessage']))
		{
			return [pscustomobject]@{
				Succeeded = $false
				TimedOut = $false
				Aborted = $false
				ErrorMessage = [string]$snapshotState['ErrorMessage']
				Snapshot = $null
				SnapshotPath = $null
				EntryCount = 0
				LastProgress = $snapshotState['LastProgress']
				DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
			}
		}

		return [pscustomobject]@{
			Succeeded = $true
			TimedOut = $false
			Aborted = $false
			ErrorMessage = $null
			Snapshot = $snapshotState['Snapshot']
			SnapshotPath = [string]$snapshotState['SnapshotPath']
			EntryCount = [int]$snapshotState['EntryCount']
			LastProgress = $snapshotState['LastProgress']
			DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Invoke-GuiPreRunSnapshotCapture:catch596' -Severity Debug }

		return [pscustomobject]@{
			Succeeded = $false
			TimedOut = $false
			Aborted = $aborted
			ErrorMessage = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Pre-run snapshot capture failed.' } else { [string]$_.Exception.Message }
			Snapshot = $null
			SnapshotPath = $null
			EntryCount = 0
			LastProgress = $snapshotState['LastProgress']
			DurationSeconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
		}
	}
	finally
	{
		if (-not $cleanupScheduled)
		{
			try { $snapshotWorker.Dispose() } catch { Write-GuiExecutionCleanupWarning "Failed to dispose pre-run snapshot worker: $($_.Exception.Message)" }
			try
			{
				$snapshotRunspace.Close()
				$snapshotRunspace.Dispose()
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to dispose pre-run snapshot runspace: $($_.Exception.Message)"
			}
		}
	}
}

function Test-GuiExecutionObjectField
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Object,

		[Parameter(Mandatory = $true)]
		[string]$FieldName
	)

	if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $false
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return $Object.Contains($FieldName)
	}

	return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
}

function Write-GuiExecutionCleanupWarning
{
	param ([string]$Message)

		if ([string]::IsNullOrWhiteSpace($Message))
		{
			return
		}

	LogWarning $Message
}

<#
    .SYNOPSIS
    Updates GUI run state counter.

    .DESCRIPTION
    Updates the shared GUI run-state counter for an execution worker.
#>
function Update-GuiRunStateCounter
{
	param (
		[hashtable]$RunState,
		[string]$Key,
		[int]$Delta = 1
	)

	[System.Threading.Monitor]::Enter($RunState.SyncRoot)
	try
	{
		$RunState[$Key] = [int]$RunState[$Key] + $Delta
		return [int]$RunState[$Key]
	}
	finally
	{
		[System.Threading.Monitor]::Exit($RunState.SyncRoot)
	}
}

<#
    .SYNOPSIS
    Gets GUI execution outcome.

    .DESCRIPTION
    Returns the normalized execution outcome object for a GUI action.
#>

function Get-GuiExecutionOutcome
{
	param (
		[string]$Status,
		[string]$Detail,
		[bool]$RequiresRestart = $false
	)

	$statusText = if ([string]::IsNullOrWhiteSpace($Status)) { 'Pending' } else { $Status.Trim() }

	switch -Regex ($statusText)
	{
		'^(Failed)$' { return 'Failed' }
		'^(Timed Out)$' { return 'Timed Out' }
		'^(Timed Out / Unknown Final State)$' { return 'Timed Out / Unknown Final State' }
		'^(Not Run)$' { return 'Not Run' }
		'^(Not applicable)$' { return 'Not applicable' }
		'^(Restart pending)$' { return 'Restart pending' }
		'^(Skipped)$'
		{
			if (-not [string]::IsNullOrWhiteSpace($Detail) -and $Detail -match '(?i)\b(not applicable|not supported|unsupported|unsupported build|windows server)\b')
			{
				return 'Not applicable'
			}
			return 'Skipped'
		}
		'^(Success)$'
		{
			if ($RequiresRestart)
			{
				return 'Restart pending'
			}
			return 'Success'
		}
		default
		{
			return $statusText
		}
	}
}

<#
    .SYNOPSIS
    Checks GUI execution applied outcome.

    .DESCRIPTION
    Checks whether a GUI execution result represents an applied change.
#>

function Test-GuiExecutionAppliedOutcome
{
	param (
		[string]$Outcome
	)

	return ($Outcome -in @('Success', 'Restart pending'))
}

<#
    .SYNOPSIS
    Creates GUI execution applied tweak metadata.

    .DESCRIPTION
    Builds the metadata record used when a GUI tweak is applied.
#>
function New-GuiExecutionAppliedTweakMetadata
{
	param (
		[object]$Result,
		[string]$Outcome
	)

	if (-not $Result)
	{
		return $null
	}

	$resolvedOutcome = if ([string]::IsNullOrWhiteSpace($Outcome))
	{
		Get-GuiExecutionOutcome -Status ([string]$Result.Status) -Detail ([string]$Result.Detail) -RequiresRestart $(if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'RequiresRestart')) { [bool]$Result.RequiresRestart } else { $false })
	}
	else
	{
		[string]$Outcome
	}

	return [pscustomobject]@{
		Key                 = [string]$Result.Key
		Order               = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'Order')) { [int]$Result.Order } else { 0 }
		Name                = [string]$Result.Name
		Function            = [string]$Result.Function
		Category            = [string]$Result.Category
		Type                = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'Type')) { [string]$Result.Type } else { $null }
		TypeLabel           = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'TypeLabel')) { [string]$Result.TypeLabel } else { $null }
		Selection           = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'Selection')) { [string]$Result.Selection } else { $null }
		ToggleParam         = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'ToggleParam')) { [string]$Result.ToggleParam } else { $null }
		RequiresRestart     = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'RequiresRestart')) { [bool]$Result.RequiresRestart } else { $false }
		Restorable          = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'Restorable')) { $Result.Restorable } else { $null }
		RecoveryLevel       = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'RecoveryLevel')) { [string]$Result.RecoveryLevel } else { $null }
		TroubleshootingOnly = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'TroubleshootingOnly')) { [bool]$Result.TroubleshootingOnly } else { $false }
		FromGameMode        = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'FromGameMode')) { [bool]$Result.FromGameMode } else { $false }
		GameModeProfile     = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'GameModeProfile')) { [string]$Result.GameModeProfile } else { $null }
		GameModeOperation   = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'GameModeOperation')) { [string]$Result.GameModeOperation } else { $null }
		Outcome             = $resolvedOutcome
		Detail              = if ((Test-GuiExecutionObjectField -Object $Result -FieldName 'Detail')) { [string]$Result.Detail } else { $null }
	}
}

<#
    .SYNOPSIS
    Gets GUI execution summary payload.

    .DESCRIPTION
    Builds the summary payload shown after a GUI execution run.
#>

function Get-GuiExecutionSummaryPayload
{
	param (
		[object[]]$Results
	)

	$results = @($Results | Where-Object { $_ })
	$decorated = @(
		foreach ($result in $results)
		{
			$outcome = Get-GuiExecutionOutcome -Status ([string]$result.Status) -Detail ([string]$result.Detail) -RequiresRestart $(if ((Test-GuiExecutionObjectField -Object $result -FieldName 'RequiresRestart')) { [bool]$result.RequiresRestart } else { $false })
			[pscustomobject]@{
				Result = $result
				Outcome = $outcome
			}
		}
	)

	$successResults = @($decorated | Where-Object Outcome -eq 'Success' | ForEach-Object { $_.Result })
	$restartPendingResults = @($decorated | Where-Object Outcome -eq 'Restart pending' | ForEach-Object { $_.Result })
	$failedResults = @($decorated | Where-Object Outcome -eq 'Failed' | ForEach-Object { $_.Result })
	$timedOutResults = @($decorated | Where-Object Outcome -eq 'Timed Out' | ForEach-Object { $_.Result })
	$timedOutUnknownResults = @($decorated | Where-Object Outcome -eq 'Timed Out / Unknown Final State' | ForEach-Object { $_.Result })
	$skippedResults = @($decorated | Where-Object Outcome -eq 'Skipped' | ForEach-Object { $_.Result })
	$notApplicableResults = @($decorated | Where-Object Outcome -eq 'Not applicable' | ForEach-Object { $_.Result })
	$notRunResults = @($decorated | Where-Object Outcome -eq 'Not Run' | ForEach-Object { $_.Result })
	$appliedResults = @($decorated | Where-Object { Test-GuiExecutionAppliedOutcome -Outcome $_.Outcome } | ForEach-Object { $_.Result })

	return [pscustomobject]@{
		TotalCount = $results.Count
		SuccessCount = $successResults.Count
		RestartPendingCount = $restartPendingResults.Count
		AppliedCount = $appliedResults.Count
		FailedCount = ($failedResults.Count + $timedOutResults.Count + $timedOutUnknownResults.Count)
		TimeoutCount = $timedOutResults.Count
		TimeoutUnknownCount = $timedOutUnknownResults.Count
		SkippedCount = $skippedResults.Count
		NotApplicableCount = $notApplicableResults.Count
		NotRunCount = $notRunResults.Count
		DirectUndoEligibleCount = @(
			$appliedResults |
				Where-Object {
					(Test-GuiExecutionObjectField -Object $_ -FieldName 'Restorable') -and
					$null -ne $_.Restorable -and
					[bool]$_.Restorable -and
					(Test-GuiExecutionObjectField -Object $_ -FieldName 'RecoveryLevel') -and
					[string]$_.RecoveryLevel -eq 'Direct'
				}
		).Count
		Results = $results
		AppliedResults = $appliedResults
		RestartPendingResults = $restartPendingResults
		RestartPendingNames = @($restartPendingResults | ForEach-Object { [string]$_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		OutcomeCounts = [ordered]@{
			Success = $successResults.Count
			RestartPending = $restartPendingResults.Count
			Failed = $failedResults.Count
			TimedOut = $timedOutResults.Count
			TimedOutUnknown = $timedOutUnknownResults.Count
			Skipped = $skippedResults.Count
			NotApplicable = $notApplicableResults.Count
			NotRun = $notRunResults.Count
		}
	}
}

<#
    .SYNOPSIS
    Resolves GUI execution availability gate.

    .DESCRIPTION
    Determines whether a GUI entry is available on the current system.
#>

function Resolve-GuiExecutionAvailabilityGate
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry,
		[switch]$ForceUnsupported
	)

	$availability = $null
	if ($null -eq $Entry)
	{
		return [pscustomobject]@{
			Decision = 'Allow'
			Reason   = ''
		}
	}

	if ($Entry -is [System.Collections.IDictionary])
	{
		if ($Entry.Contains('Availability'))
		{
			$availability = $Entry['Availability']
		}
	}
	elseif ($Entry.PSObject -and $Entry.PSObject.Properties['Availability'])
	{
		$availability = $Entry.Availability
	}

	if ($null -eq $availability)
	{
		return [pscustomobject]@{
			Decision = 'Allow'
			Reason   = ''
		}
	}

	$isAvailable = $true
	$reason = $null
	if ($availability -is [System.Collections.IDictionary])
	{
		if ($availability.Contains('Available')) { $isAvailable = [bool]$availability['Available'] }
		if ($availability.Contains('Reason')) { $reason = [string]$availability['Reason'] }
	}
	elseif ($availability.PSObject)
	{
		if ($availability.PSObject.Properties['Available']) { $isAvailable = [bool]$availability.Available }
		if ($availability.PSObject.Properties['Reason']) { $reason = [string]$availability.Reason }
	}

	if ($isAvailable)
	{
		return [pscustomobject]@{
			Decision = 'Allow'
			Reason   = ''
		}
	}

	$resolvedReason = if ([string]::IsNullOrWhiteSpace($reason)) { 'Not available on this OS.' } else { [string]$reason }
	return [pscustomobject]@{
		Decision = if ($ForceUnsupported) { 'Force' } else { 'Block' }
		Reason   = $resolvedReason
	}
}

<#
    .SYNOPSIS
    Resolves execution support that depends on the selected option.

    .DESCRIPTION
    Manifest-level SupportsExecution is entry-wide, but some choice entries have
    options with different prerequisites. This gate checks the selected run
    entry so supported options such as Cursors -Default can still execute while
    options requiring external configuration are skipped with a clear reason.
#>
function Resolve-GuiExecutionDynamicSelectionSupport
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry
	)

	$result = [ordered]@{
		SupportsExecution = $true
		Reason            = ''
	}

	$functionName = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Function')
	if ([string]::IsNullOrWhiteSpace($functionName))
	{
		return [pscustomobject]$result
	}

	if ($functionName -eq 'Cursors')
	{
		$selectedValue = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Value')
		if ($selectedValue -in @('Dark', 'Light'))
		{
			$cursorArchiveUrl = [string][System.Environment]::GetEnvironmentVariable('BASELINE_CURSOR_ARCHIVE_URL')
			if ([string]::IsNullOrWhiteSpace($cursorArchiveUrl))
			{
				$result.SupportsExecution = $false
				$result.Reason = 'Dark and light cursor themes require BASELINE_CURSOR_ARCHIVE_URL to point to the verified Windows cursor archive.'
			}
		}
	}

	return [pscustomobject]$result
}

<#
    .SYNOPSIS
    Resolves GUI execution supports execution gate.

    .DESCRIPTION
    Determines whether a GUI entry supports execution in the current mode.
#>

function Resolve-GuiExecutionSupportsExecutionGate
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry,
		[switch]$ForceUnsupported
	)

	$dynamicSupport = Resolve-GuiExecutionDynamicSelectionSupport -Entry $Entry
	if (-not $dynamicSupport.SupportsExecution)
	{
		return [pscustomobject]@{
			Decision = if ($ForceUnsupported) { 'Force' } else { 'Block' }
			Reason   = if ([string]::IsNullOrWhiteSpace([string]$dynamicSupport.Reason)) { 'Execution not supported on this system.' } else { [string]$dynamicSupport.Reason }
		}
	}

	if (Test-BaselineEntrySupportsExecution -Entry $Entry)
	{
		return [pscustomobject]@{
			Decision = 'Allow'
			Reason   = ''
		}
	}

	$reason = if (Get-Command -Name 'Get-BaselineEntrySupportsExecutionReason' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Get-BaselineEntrySupportsExecutionReason -Entry $Entry
	}
	elseif ($Entry -is [System.Collections.IDictionary] -and $Entry.Contains('SupportsExecutionReason'))
	{
		$Entry['SupportsExecutionReason']
	}
	elseif ($null -ne $Entry -and $Entry.PSObject.Properties['SupportsExecutionReason'])
	{
		$Entry.SupportsExecutionReason
	}
	else
	{
		$null
	}

	return [pscustomobject]@{
		Decision = if ($ForceUnsupported) { 'Force' } else { 'Block' }
		Reason   = if ([string]::IsNullOrWhiteSpace([string]$reason)) { 'Execution not supported on this system.' } else { [string]$reason }
	}
}

<#
    .SYNOPSIS
    Gets a GUI execution entry field value.

    .DESCRIPTION
    Resolves a property from either a dictionary-backed or PSObject-backed
    execution entry.
#>
function Get-GuiExecutionEntryFieldValue
{
	param (
		[object]$Entry,
		[string]$FieldName
	)

	if ($null -eq $Entry -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $null
	}

	if ($Entry -is [System.Collections.IDictionary])
	{
		if ($Entry.Contains($FieldName))
		{
			return $Entry[$FieldName]
		}

		return $null
	}

	if ($Entry.PSObject -and $Entry.PSObject.Properties[$FieldName])
	{
		return $Entry.$FieldName
	}

	return $null
}

<#
    .SYNOPSIS
    Resolves the timeout for a GUI execution entry.

    .DESCRIPTION
    Applies the shared timeout defaults for tweak/app execution while allowing
    manifest entries to override the timeout explicitly.
#>
function Get-GuiExecutionActionTimeoutSeconds
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry,

		[ValidateSet('Tweak', 'App', 'AppScan', 'PackageBootstrap')]
		[string]$ExecutionClass = 'Tweak'
	)

	$manifestTimeout = Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'TimeoutSeconds'
	if ($null -ne $manifestTimeout)
	{
		$parsedTimeout = 0
		if ([int]::TryParse(([string]$manifestTimeout), [ref]$parsedTimeout) -and $parsedTimeout -gt 0)
		{
			return $parsedTimeout
		}
	}

	if ($ExecutionClass -eq 'App')
	{
		return 900
	}
	if ($ExecutionClass -eq 'AppScan')
	{
		return 300
	}
	if ($ExecutionClass -eq 'PackageBootstrap')
	{
		return 900
	}

	$type = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Type')
	$risk = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Risk')
	$recoveryLevel = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'RecoveryLevel')
	$compatibilitySensitivity = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'CompatibilitySensitivity')
	$functionName = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Function')
	$name = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Name')
	$sourceRegion = [string](Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'SourceRegion')
	$combinedIdentity = ("{0} {1} {2}" -f $functionName, $name, $sourceRegion).Trim()

	if ($combinedIdentity -match '(?i)\b(sfc|dism|component repair|component store|repair)\b')
	{
		return 600
	}

	if ($functionName -eq 'WindowsCapabilities')
	{
		return 3600
	}

	if ($functionName -in @('WindowsFeatures', 'UWPApps'))
	{
		return 300
	}

	if ($functionName -eq 'ScheduledTasks')
	{
		return 120
	}

	if ($type -eq 'Action')
	{
		return 180
	}

	if ($risk -eq 'High' -or $compatibilitySensitivity -eq 'High' -or ($recoveryLevel -and $recoveryLevel -ne 'Direct'))
	{
		return 180
	}

	return 60
}

<#
    .SYNOPSIS
    Tests whether a GUI execution entry is marked critical.
#>
function Test-GuiExecutionCriticalAction
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Entry
	)

	$criticalValue = Get-GuiExecutionEntryFieldValue -Entry $Entry -FieldName 'Critical'
	if ($null -eq $criticalValue)
	{
		return $false
	}

	return [bool]$criticalValue
}

<#
    .SYNOPSIS
    Creates an initialized GUI execution action host.

    .DESCRIPTION
    Creates a dedicated runspace that imports Baseline once and can then
    execute bounded commands one at a time under timeout control.
#>
function New-GuiExecutionActionHost
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$LoaderPath,

		[Parameter(Mandatory)]
		[string]$LocalizationDirectory,

		[Parameter(Mandatory)]
		[string]$UICulture,

		[Parameter(Mandatory)]
		[string]$LogFilePath,

		[string]$LogMode,

		[string]$OperationMode,

		[AllowNull()]
		$LogQueue
	)

	$resolvedOperationMode = if ([string]::IsNullOrWhiteSpace([string]$OperationMode)) { Get-GuiExecutionOperationMode } else { [string]$OperationMode }

	$runspace = [runspacefactory]::CreateRunspace()
	$runspace.ApartmentState = 'STA'
	$runspace.ThreadOptions = 'ReuseThread'
	$runspace.Open()
	$runspace.SessionStateProxy.SetVariable('bgLoaderPath', $LoaderPath)
	$runspace.SessionStateProxy.SetVariable('bgLocDir', $LocalizationDirectory)
	$runspace.SessionStateProxy.SetVariable('bgUICulture', $UICulture)
	$runspace.SessionStateProxy.SetVariable('bgLogFilePath', $LogFilePath)
	$runspace.SessionStateProxy.SetVariable('bgLogMode', $LogMode)
	$runspace.SessionStateProxy.SetVariable('bgOperationMode', $resolvedOperationMode)
	$runspace.SessionStateProxy.SetVariable('bgGuiLogQueue', $LogQueue)
	Set-GuiExecutionRunspaceThemeSnapshot -Runspace $runspace

	$initializer = [powershell]::Create().AddScript({
		$Global:GUIMode = $true
		if ([string]::IsNullOrWhiteSpace([string]$bgOperationMode))
		{
			$bgOperationMode = 'ReadWrite'
		}
		$Global:BaselineOperationMode = [string]$bgOperationMode
		[System.Environment]::SetEnvironmentVariable('BASELINE_OPERATION_MODE', [string]$bgOperationMode, [System.EnvironmentVariableTarget]::Process)
		if ($bgCurrentTheme -is [System.Collections.IDictionary])
		{
			$Global:BaselineCurrentTheme = $bgCurrentTheme
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$bgCurrentThemeName))
		{
			$Global:BaselineCurrentThemeName = [string]$bgCurrentThemeName
		}
		if ($null -ne $bgUseDarkMode)
		{
			$Global:BaselineUseDarkMode = [bool]$bgUseDarkMode
		}
		$bgModuleRoot = Split-Path $bgLoaderPath -Parent
		$bgJsonHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Json.Helpers.ps1'
		$bgHelperPath = Join-Path $bgModuleRoot 'SharedHelpers\Localization.Helpers.ps1'
		. $bgJsonHelperPath
		. $bgHelperPath
		$Global:Localization = Import-BaselineLocalization -BaseDirectory $bgLocDir -UICulture $bgUICulture
		[void](Set-BaselineThreadCulture -UICulture $bgUICulture)
		$Global:LogFilePath = $bgLogFilePath
		Import-Module $bgLoaderPath -Force -Global -ErrorAction Stop
		if (Get-Command -Name Set-BaselineOperationMode -ErrorAction SilentlyContinue)
		{
			Set-BaselineOperationMode -Mode ([string]$bgOperationMode)
		}
		Set-LogFile -Path $bgLogFilePath
		Set-LogMode -Mode $bgLogMode
		if ($bgGuiLogQueue)
		{
			Set-Variable -Name 'GUIRunState' -Scope Global -Value $bgGuiLogQueue
			Set-UILogHandler { param($entry) $bgGuiLogQueue.Enqueue($entry) }
		}
		else
		{
			Clear-UILogHandler
		}

		return $true
	})
	$initializer.Runspace = $runspace

	try
	{
		$null = $initializer.Invoke()
		if ($initializer.HadErrors)
		{
			$initError = $initializer.Streams.Error | Select-Object -First 1
			if ($initError)
			{
				throw $initError
			}

			throw 'Failed to initialize the GUI execution action host.'
		}
	}
	catch
	{
		try { $initializer.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.NewActionHost.DisposeInitializer' }
		try { $runspace.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.NewActionHost.CloseRunspace' }
		try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.NewActionHost.DisposeRunspace' }
		throw
	}
	finally
	{
		try { $initializer.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.NewActionHost.DisposeInitializerFinally' }
	}

	return [pscustomobject]@{
		Runspace      = $runspace
		OperationMode = $resolvedOperationMode
	}
}

<#
    .SYNOPSIS
    Closes a GUI execution action host.
#>
function Close-GuiExecutionActionHost
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		$ActionHost,

		[switch]$NonBlocking
	)

	if (-not $ActionHost)
	{
		return
	}

	$runspace = if ($ActionHost.PSObject.Properties['Runspace']) { $ActionHost.Runspace } else { $null }
	if (-not $runspace)
	{
		return
	}

	if ($NonBlocking)
	{
		try { $runspace.CloseAsync(); return } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.CloseActionHost.CloseRunspaceAsync' -Severity Warning }
		return
	}

	try { $runspace.Close() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.CloseActionHost.CloseRunspace' }
	try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.CloseActionHost.DisposeRunspace' }
}

<#
    .SYNOPSIS
    Invokes a bounded command inside a GUI execution action host.
#>
function Invoke-GuiExecutionActionHostCommand
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		$ActionHost,

		[Parameter(Mandatory)]
		[string]$CommandName,

		[hashtable]$CommandArguments = @{},

		[Parameter(Mandatory)]
		[int]$TimeoutSeconds,

		[hashtable]$RunState = $null
	)

	$invocationOperationMode = if ((Test-GuiExecutionObjectField -Object $ActionHost -FieldName 'OperationMode') -and -not [string]::IsNullOrWhiteSpace([string]$ActionHost.OperationMode))
	{
		[string]$ActionHost.OperationMode
	}
	else
	{
		Get-GuiExecutionOperationMode
	}

	$powerShell = [powershell]::Create().AddScript({
		param (
			[string]$InvocationCommandName,
			[hashtable]$InvocationCommandArguments,
			[string]$InvocationOperationMode
		)

		if ([string]::IsNullOrWhiteSpace([string]$InvocationOperationMode))
		{
			$InvocationOperationMode = [System.Environment]::GetEnvironmentVariable('BASELINE_OPERATION_MODE')
		}
		if ([string]::IsNullOrWhiteSpace([string]$InvocationOperationMode))
		{
			$InvocationOperationMode = 'ReadWrite'
		}
		$Global:BaselineOperationMode = [string]$InvocationOperationMode
		[System.Environment]::SetEnvironmentVariable('BASELINE_OPERATION_MODE', [string]$InvocationOperationMode, [System.EnvironmentVariableTarget]::Process)
		if (Get-Command -Name Set-BaselineOperationMode -ErrorAction SilentlyContinue)
		{
			Set-BaselineOperationMode -Mode ([string]$InvocationOperationMode)
		}

		$resolvedCommand = Get-Command -Name $InvocationCommandName -ErrorAction Stop | Select-Object -First 1
		if ($InvocationCommandArguments -and $InvocationCommandArguments.Count -gt 0)
		{
			& $resolvedCommand @InvocationCommandArguments
		}
		else
		{
			& $resolvedCommand
		}
	}).AddArgument($CommandName).AddArgument($CommandArguments).AddArgument($invocationOperationMode)
	$powerShell.Runspace = $ActionHost.Runspace

	$startedAt = Get-Date
	$asyncResult = $null
	$timedOut = $false
	$aborted = $false
	$stopIssued = $false
	$stopCompleted = $true

	try
	{
		$asyncResult = $powerShell.BeginInvoke()
		while (-not $asyncResult.AsyncWaitHandle.WaitOne(250))
		{
			if ($RunState -and [bool]$RunState['AbortRequested'])
			{
				$aborted = $true
				$stopCompleted = Request-GuiExecutionPowerShellStopAsync -PowerShell $powerShell -Source 'GUIExecution.ActionHostCommand.AbortStop'
				$stopIssued = $true
				break
			}

			if (((Get-Date) - $startedAt).TotalSeconds -ge [double]$TimeoutSeconds)
			{
				$timedOut = $true
				$stopCompleted = Request-GuiExecutionPowerShellStopAsync -PowerShell $powerShell -Source 'GUIExecution.ActionHostCommand.TimeoutStop'
				$stopIssued = $true
				break
			}
		}

		if ($timedOut -or $aborted)
		{
			if ($asyncResult -and -not $asyncResult.IsCompleted)
			{
				try { $asyncResult.AsyncWaitHandle.WaitOne(1000) | Out-Null } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.ActionHostCommand.StopWait' }
			}

			return [pscustomobject]@{
				Succeeded         = $false
				TimedOut          = $timedOut
				Aborted           = $aborted
				ErrorMessage      = $null
				ErrorTypeName     = $null
				Output            = @()
				StartedAt         = $startedAt
				EndedAt           = Get-Date
				DurationSeconds   = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
				CommandName       = $CommandName
				StopCompleted     = $stopCompleted
				HostRequiresReset = $stopIssued
			}
		}

		$results = @($powerShell.EndInvoke($asyncResult))
		return [pscustomobject]@{
			Succeeded         = $true
			TimedOut          = $false
			Aborted           = $false
			ErrorMessage      = $null
			ErrorTypeName     = $null
			Output            = @($results)
			StartedAt         = $startedAt
			EndedAt           = Get-Date
			DurationSeconds   = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
			CommandName       = $CommandName
			StopCompleted     = $true
			HostRequiresReset = $false
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Invoke-GuiExecutionActionHostCommand:catch1501' -Severity Debug }

		return [pscustomobject]@{
			Succeeded         = $false
			TimedOut          = $false
			Aborted           = $aborted
			ErrorMessage      = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Execution failed.' } else { [string]$_.Exception.Message }
			ErrorTypeName     = if ($_.Exception) { [string]$_.Exception.GetType().FullName } else { $null }
			Output            = @()
			StartedAt         = $startedAt
			EndedAt           = Get-Date
			DurationSeconds   = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
			CommandName       = $CommandName
			StopCompleted     = $stopCompleted
			HostRequiresReset = $stopIssued
		}
	}
	finally
	{
		if (($timedOut -or $aborted) -and $asyncResult -and -not [bool]$asyncResult.IsCompleted)
		{
			Write-GuiExecutionCleanupWarning "Action host command '$CommandName' did not stop within the bounded timeout cleanup window; abandoning its runspace so GUI execution can continue."
		}
		else
		{
			try { $powerShell.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.ActionHostCommand.DisposePowerShell' }
		}
	}
}

<#
    .SYNOPSIS
    Tests whether an execution invocation ended in a timeout.
#>
function Test-GuiExecutionInvocationTimedOut
{
	param (
		[AllowNull()]
		$InvocationResult
	)

	if (-not $InvocationResult)
	{
		return $false
	}

	if ((Test-GuiExecutionObjectField -Object $InvocationResult -FieldName 'TimedOut') -and [bool]$InvocationResult.TimedOut)
	{
		return $true
	}

	if ((Test-GuiExecutionObjectField -Object $InvocationResult -FieldName 'ErrorTypeName') -and [string]$InvocationResult.ErrorTypeName -eq 'System.TimeoutException')
	{
		return $true
	}

	return $false
}

<#
    .SYNOPSIS
    Gets the display verb for an app execution action.
#>
function Get-GuiExecutionAppActionVerb
{
	param (
		[string]$Action
	)

	switch ([string]$Action)
	{
		'Install' { return 'Install' }
		'Uninstall' { return 'Uninstall' }
		'Update' { return 'Update' }
		'UpdateAll' { return 'Update' }
		default { return 'Run' }
	}
}

<#
    .SYNOPSIS
    Creates a structured app execution result entry.
#>
function New-GuiExecutionAppBatchEntry
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[object]$Route,

		[string]$Error = $null
	)

	if (-not $Route)
	{
		return $null
	}

	$entry = [ordered]@{
		SelectionKey   = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'SelectionKey')) { [string]$Route.SelectionKey } else { $null }
		WinGetId       = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'WinGetId')) { [string]$Route.WinGetId } else { $null }
		ChocoId        = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'ChocoId')) { [string]$Route.ChocoId } else { $null }
		Name           = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'DisplayName')) { [string]$Route.DisplayName } else { $null }
		EntityType     = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'EntityType')) { [string]$Route.EntityType } else { $null }
		Route          = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'Route')) { [string]$Route.Route } else { $null }
		SelectedSource = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'SelectedSource')) { [string]$Route.SelectedSource } else { $null }
		PackageId      = if ((Test-GuiExecutionObjectField -Object $Route -FieldName 'PackageId')) { [string]$Route.PackageId } else { $null }
	}

	if (-not [string]::IsNullOrWhiteSpace($Error))
	{
		$entry['Error'] = [string]$Error
	}

	return [pscustomobject]$entry
}

<#
    .SYNOPSIS
    Builds a structured batch result for app execution.
#>
function New-GuiExecutionAppBatchResult
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$Action,

		[object[]]$SuccessfulApps = @(),

		[object[]]$FailedApps = @()
	)

	$successfulApps = @($SuccessfulApps | Where-Object { $_ })
	$failedApps = @($FailedApps | Where-Object { $_ })
	$processedCount = $successfulApps.Count + $failedApps.Count
	if ($processedCount -eq 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_NoSelection' -Fallback 'No applications were selected.'
		LogWarning $message
		return [pscustomobject]@{
			Action         = $Action
			TotalCount     = 0
			SuccessCount   = 0
			FailureCount   = 0
			Outcome        = 'Failed'
			Message        = $message
			SuccessfulApps = @()
			FailedApps     = @()
		}
	}

	$pastTense = switch ($Action)
	{
		'Install'   { 'installed' }
		'Uninstall' { 'uninstalled' }
		'Update'    { 'updated' }
		default     { 'processed' }
	}

	if ($failedApps.Count -gt 0 -and $successfulApps.Count -gt 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchPartial' -Fallback 'Partially {0} {1} selected app(s): {2} succeeded, {3} failed.' -FormatArgs @($pastTense, $processedCount, $successfulApps.Count, $failedApps.Count)
		LogWarning $message
		$outcome = 'Partial'
	}
	elseif ($failedApps.Count -gt 0)
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchFailed' -Fallback 'Failed to {0} {1} selected app(s).' -FormatArgs @($pastTense, $processedCount)
		LogError $message
		$outcome = 'Failed'
	}
	else
	{
		$message = Get-BaselineLocalizedString -Key 'Progress_BatchSuccess' -Fallback 'Successfully {0} {1} selected app(s).' -FormatArgs @($pastTense, $successfulApps.Count)
		LogInfo $message
		$outcome = 'Success'
	}

	return [pscustomobject]@{
		Action         = $Action
		TotalCount     = $processedCount
		SuccessCount   = $successfulApps.Count
		FailureCount   = $failedApps.Count
		Outcome        = $outcome
		Message        = $message
		SuccessfulApps = @($successfulApps)
		FailedApps     = @($failedApps)
	}
}

<#
    .SYNOPSIS
    Writes a structured execution timeout record to the log.
#>
function Write-GuiExecutionTimeoutRecord
{
	[CmdletBinding()]
	param (
		[string]$ActionId,
		[string]$ActionName,
		[string]$ActionType,
		[int]$TimeoutSeconds,
		[datetime]$StartedAt,
		[datetime]$EndedAt,
		[string]$CommandName,
		[int]$ExitCode = [int]::MinValue,
		[bool]$VerificationAttempted = $false,
		[string]$VerificationResult = $null,
		[bool]$Continued = $true,
		[bool]$Aborted = $false,
		[string]$Result = 'Timed Out',
		[string]$Message = $null
	)

	$record = [ordered]@{
		id                    = $ActionId
		name                  = $ActionName
		type                  = $ActionType
		timeoutSeconds        = $TimeoutSeconds
		result                = $Result
		startTime             = $StartedAt.ToString('o')
		endTime               = $EndedAt.ToString('o')
		command               = $CommandName
		verificationAttempted = $VerificationAttempted
		verificationResult    = $VerificationResult
		continued             = $Continued
		aborted               = $Aborted
	}

	if ($ExitCode -ne [int]::MinValue)
	{
		$record.exitCode = $ExitCode
	}
	if (-not [string]::IsNullOrWhiteSpace($Message))
	{
		$record.message = $Message
	}

	LogWarning ("Execution timeout: {0}" -f ($record | ConvertTo-Json -Compress -Depth 5))
}

<#
    .SYNOPSIS
    Verifies an app action after a timeout.

    .DESCRIPTION
    Performs a lightweight package-manager-backed verification so installs,
    updates, and removals can resolve to a real final state after the timeout
    window expires.
#>
function Resolve-GuiAppTimeoutVerification
{
	[CmdletBinding(DefaultParameterSetName = 'Application')]
	param (
		[Parameter(Mandatory)]
		[ValidateSet('Install', 'Uninstall', 'Update')]
		[string]$Action,

		[Parameter(Mandatory = $true, ParameterSetName = 'Application')]
		[AllowNull()]
		[object]$Application,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$WinGetId,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$ChocoId,

		[Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
		[string]$DisplayName,

		[string]$PreferredSource = $null,

		[object]$PackageManagerAvailabilityState = $null,

		[int]$TimeoutSeconds = 300
	)

	$verificationApp = $Application
	if ($PSCmdlet.ParameterSetName -eq 'Legacy')
	{
		$verificationApp = [pscustomobject]@{
			Name = $DisplayName
			WinGetId = $WinGetId
			ChocoId = $ChocoId
			SupportsExecution = $true
		}
	}

	if (-not $verificationApp)
	{
		return [pscustomobject]@{
			VerificationAttempted = $false
			VerificationResult = 'Unavailable'
			ResolvedStatus = 'Timed Out / Unknown Final State'
			Succeeded = $false
			Message = 'No application metadata was available for timeout verification.'
		}
	}

	$route = Resolve-ApplicationExecutionRoute -Application $verificationApp -PreferredSource $PreferredSource -PackageManagerAvailabilityState $PackageManagerAvailabilityState -Action $Action
	if ($route.Route -eq 'unsupported' -or [string]::IsNullOrWhiteSpace([string]$route.PackageId))
	{
		return [pscustomobject]@{
			VerificationAttempted = $false
			VerificationResult = 'Unavailable'
			ResolvedStatus = 'Timed Out / Unknown Final State'
			Succeeded = $false
			Message = 'Timeout verification is not available for this application route.'
		}
	}

	try
	{
		switch ($Action)
		{
			'Install'
			{
				if ($route.Route -eq 'winget')
				{
					$installedCache = Get-InstalledAppCache -TimeoutSeconds $TimeoutSeconds
					$isInstalled = $installedCache.ContainsKey([string]$route.PackageId)
				}
				elseif ($route.Route -eq 'choco')
				{
					$installedCache = Get-InstalledChocolateyAppCache -TimeoutSeconds $TimeoutSeconds
					$isInstalled = $installedCache.ContainsKey([string]$route.PackageId)
				}
				else
				{
					$isInstalled = $false
				}

				return [pscustomobject]@{
					VerificationAttempted = $true
					VerificationResult = $(if ($isInstalled) { 'Installed' } else { 'NotInstalled' })
					ResolvedStatus = $(if ($isInstalled) { 'Success' } else { 'Timed Out / Unknown Final State' })
					Succeeded = [bool]$isInstalled
					Message = $(if ($isInstalled) { 'Installed after timeout.' } else { 'Baseline could not verify that the app installed after the timeout.' })
				}
			}
			'Uninstall'
			{
				if ($route.Route -eq 'winget')
				{
					$installedCache = Get-InstalledAppCache -TimeoutSeconds $TimeoutSeconds
					$isRemoved = -not $installedCache.ContainsKey([string]$route.PackageId)
				}
				elseif ($route.Route -eq 'choco')
				{
					$installedCache = Get-InstalledChocolateyAppCache -TimeoutSeconds $TimeoutSeconds
					$isRemoved = -not $installedCache.ContainsKey([string]$route.PackageId)
				}
				else
				{
					$isRemoved = $false
				}

				return [pscustomobject]@{
					VerificationAttempted = $true
					VerificationResult = $(if ($isRemoved) { 'Removed' } else { 'StillInstalled' })
					ResolvedStatus = $(if ($isRemoved) { 'Already Removed' } else { 'Timed Out / Unknown Final State' })
					Succeeded = [bool]$isRemoved
					Message = $(if ($isRemoved) { 'Removed after timeout.' } else { 'Baseline could not verify that the app was removed after the timeout.' })
				}
			}
			'Update'
			{
				if ($route.Route -eq 'winget')
				{
					$updateCache = Get-AvailableAppUpdateCache -TimeoutSeconds $TimeoutSeconds
					$isUpdated = -not $updateCache.ContainsKey([string]$route.PackageId)
				}
				elseif ($route.Route -eq 'choco')
				{
					$updateCache = Get-AvailableChocolateyUpdateCache -TimeoutSeconds $TimeoutSeconds
					$isUpdated = -not $updateCache.ContainsKey([string]$route.PackageId)
				}
				else
				{
					$isUpdated = $false
				}

				return [pscustomobject]@{
					VerificationAttempted = $true
					VerificationResult = $(if ($isUpdated) { 'Updated' } else { 'UpdateStillAvailable' })
					ResolvedStatus = $(if ($isUpdated) { 'Updated' } else { 'Timed Out / Unknown Final State' })
					Succeeded = [bool]$isUpdated
					Message = $(if ($isUpdated) { 'Updated after timeout.' } else { 'Baseline could not verify that the update completed after the timeout.' })
				}
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.Resolve-GuiAppTimeoutVerification:catch1895' -Severity Debug }

		return [pscustomobject]@{
			VerificationAttempted = $true
			VerificationResult = if ([string]::IsNullOrWhiteSpace([string]$_.Exception.Message)) { 'Failed' } else { [string]$_.Exception.Message }
			ResolvedStatus = 'Timed Out / Unknown Final State'
			Succeeded = $false
			Message = 'Timeout verification failed before Baseline could confirm the final state.'
		}
	}
}

<#
    .SYNOPSIS
    Start GUI execution worker.

    .DESCRIPTION
    Starts the background worker used for selected GUI tweak execution.
#>

function Start-GuiExecutionWorker
{
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$RunState,

		[Parameter(Mandatory = $true)]
		[object[]]$TweakList,

		[Parameter(Mandatory = $true)]
		[ValidateSet('Run', 'Defaults')]
		[string]$Mode,

		[Parameter(Mandatory = $true)]
		[string]$LoaderPath,

		[Parameter(Mandatory = $true)]
		[string]$LocalizationDirectory,

		[Parameter(Mandatory = $true)]
		[string]$UICulture,

		[Parameter(Mandatory = $true)]
		[string]$LogFilePath,
		[string]$LogMode,
		[switch]$ForceUnsupported
	)

	$writeStartupNotice = {
		param([string]$Message)
		try
		{
			if ($RunState -and $RunState.ContainsKey('LogQueue') -and $RunState['LogQueue'])
			{
				$RunState['LogQueue'].Enqueue([pscustomobject]@{
					Kind = '_RunNotice'
					Level = 'DEBUG'
					Message = $Message
					Progress = $true
					Diagnostic = $true
				})
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'GUIExecution.StartWorker.EnqueueStartupNotice' }
	}

	& $writeStartupNotice 'Execution startup: creating background runspace.'
	$bgRunspace = [runspacefactory]::CreateRunspace()
	$bgRunspace.ApartmentState = 'STA'
	$bgRunspace.ThreadOptions = 'ReuseThread'
	$bgRunspace.Open()
	& $writeStartupNotice 'Execution startup: background runspace opened.'
	$operationMode = Get-GuiExecutionOperationMode
	$bgRunspace.SessionStateProxy.SetVariable('runState', $RunState)
	$bgRunspace.SessionStateProxy.SetVariable('tweakList', @($TweakList))
	$bgRunspace.SessionStateProxy.SetVariable('executionMode', $Mode)
	$bgRunspace.SessionStateProxy.SetVariable('bgLoaderPath', $LoaderPath)
	$bgRunspace.SessionStateProxy.SetVariable('bgLocDir', $LocalizationDirectory)
	$bgRunspace.SessionStateProxy.SetVariable('bgUICulture', $UICulture)
	$bgRunspace.SessionStateProxy.SetVariable('bgLogFilePath', $LogFilePath)
	$bgRunspace.SessionStateProxy.SetVariable('bgLogMode', $LogMode)
	$bgRunspace.SessionStateProxy.SetVariable('bgOperationMode', $operationMode)
	$bgRunspace.SessionStateProxy.SetVariable('bgForceUnsupported', [bool]$ForceUnsupported)
	$bgRunspace.SessionStateProxy.SetVariable('GUIRunState', $RunState['LogQueue'])
	Set-GuiExecutionRunspaceThemeSnapshot -Runspace $bgRunspace

		. (Join-Path $PSScriptRoot 'GUIExecution\Start-GuiExecutionWorker\Start-GuiExecutionWorker.ps1')

	$worker.Runspace = $bgRunspace
	& $writeStartupNotice 'Execution startup: invoking worker scriptblock.'
	$asyncResult = $worker.BeginInvoke()
	& $writeStartupNotice 'Execution startup: worker BeginInvoke returned.'

	return [pscustomobject]@{
		PowerShell = $worker
		AsyncResult = $asyncResult
		Runspace = $bgRunspace
	}
}

<#
    .SYNOPSIS
    Start GUI app execution worker.

    .DESCRIPTION
    Starts the background worker used for application installation or removal.
#>

function Start-GuiAppExecutionWorker
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall', 'Update', 'UpdateAll')]
		[string]$Action,

		[Parameter(Mandatory = $true)]
		[string]$LoaderPath,

		[Parameter(Mandatory = $true)]
		[string]$LocalizationDirectory,

		[Parameter(Mandatory = $true)]
		[string]$UICulture,

		[Parameter(Mandatory = $true)]
		[string]$LogFilePath,

		[string]$LogMode,

		[hashtable]$RunState,

		[string]$WinGetId,

		[string]$ChocoId,

		[string]$DisplayName,

		[object]$Application,

		[object[]]$SelectedApps = @(),

		[string]$PreferredSource = $null,

		[object]$PackageManagerAvailabilityState = $null
	)

	$resolvedDisplayName = $DisplayName
	$resolvedWinGetId = $WinGetId
	$resolvedChocoId = $ChocoId
	if ($Application)
	{
		if ([string]::IsNullOrWhiteSpace([string]$resolvedDisplayName) -and $Application.PSObject.Properties['Name'])
		{
			$resolvedDisplayName = [string]$Application.Name
		}
		if ([string]::IsNullOrWhiteSpace([string]$resolvedWinGetId) -and $Application.PSObject.Properties['WinGetId'])
		{
			$resolvedWinGetId = [string]$Application.WinGetId
		}
		if ([string]::IsNullOrWhiteSpace([string]$resolvedChocoId) -and $Application.PSObject.Properties['ChocoId'])
		{
			$resolvedChocoId = [string]$Application.ChocoId
		}
	}

	$guiExecutionModulePath = Join-Path $PSScriptRoot 'GUIExecution.psm1'
	$actionHostLoaderPath = Join-Path $PSScriptRoot 'Baseline.psm1'
	if (-not (Test-Path -LiteralPath $guiExecutionModulePath -PathType Leaf))
	{
		throw "Unable to start app execution worker because GUIExecution.psm1 was not found at '$guiExecutionModulePath'."
	}
	if (-not (Test-Path -LiteralPath $actionHostLoaderPath -PathType Leaf))
	{
		throw "Unable to start app execution worker because Baseline.psm1 was not found at '$actionHostLoaderPath'."
	}

	$bgRunspace = [runspacefactory]::CreateRunspace()
	$bgRunspace.ApartmentState = 'STA'
	$bgRunspace.ThreadOptions = 'ReuseThread'
	$bgRunspace.Open()
	$operationMode = Get-GuiExecutionOperationMode
	if ($RunState)
	{
		$bgRunspace.SessionStateProxy.SetVariable('runState', $RunState)
		if ($RunState.ContainsKey('LogQueue'))
		{
			$bgRunspace.SessionStateProxy.SetVariable('GUIRunState', $RunState['LogQueue'])
		}
	}
	$bgRunspace.SessionStateProxy.SetVariable('bgLoaderPath', $LoaderPath)
	$bgRunspace.SessionStateProxy.SetVariable('bgGuiExecutionModulePath', $guiExecutionModulePath)
	$bgRunspace.SessionStateProxy.SetVariable('bgActionHostLoaderPath', $actionHostLoaderPath)
	$bgRunspace.SessionStateProxy.SetVariable('bgLocDir', $LocalizationDirectory)
	$bgRunspace.SessionStateProxy.SetVariable('bgUICulture', $UICulture)
	$bgRunspace.SessionStateProxy.SetVariable('bgLogFilePath', $LogFilePath)
	$bgRunspace.SessionStateProxy.SetVariable('bgLogMode', $LogMode)
	$bgRunspace.SessionStateProxy.SetVariable('bgOperationMode', $operationMode)
	$bgRunspace.SessionStateProxy.SetVariable('runAction', $Action)
	$bgRunspace.SessionStateProxy.SetVariable('packageId', $resolvedWinGetId)
	$bgRunspace.SessionStateProxy.SetVariable('chocolateyId', $resolvedChocoId)
	$bgRunspace.SessionStateProxy.SetVariable('displayName', $resolvedDisplayName)
	$bgRunspace.SessionStateProxy.SetVariable('application', $Application)
	$bgRunspace.SessionStateProxy.SetVariable('selectedApps', @($SelectedApps))
	$bgRunspace.SessionStateProxy.SetVariable('preferredSource', $PreferredSource)
	$bgRunspace.SessionStateProxy.SetVariable('packageManagerAvailabilityState', $PackageManagerAvailabilityState)
	Set-GuiExecutionRunspaceThemeSnapshot -Runspace $bgRunspace

		. (Join-Path $PSScriptRoot 'GUIExecution\Start-GuiAppExecutionWorker\Start-GuiAppExecutionWorker.ps1')

	$worker.Runspace = $bgRunspace
	$asyncResult = $worker.BeginInvoke()

	return [pscustomobject]@{
		PowerShell = $worker
		AsyncResult = $asyncResult
		Runspace = $bgRunspace
	}
}

<#
    .SYNOPSIS
    Request GUI execution worker stop.

    .DESCRIPTION
    Signals an active GUI execution worker to stop.
#>

function Request-GuiExecutionWorkerStop
{
	param (
		[Parameter(Mandatory = $true)]
		$PowerShellInstance
	)

	if (-not $PowerShellInstance)
	{
		return
	}

	[System.Threading.ThreadPool]::QueueUserWorkItem(
		[System.Threading.WaitCallback]{
			param($state)
			try
			{
				if ($state)
				{
					$state.Stop()
				}
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to request GUI execution worker stop: $($_.Exception.Message)"
			}
		},
		$PowerShellInstance
	) | Out-Null
}

<#
    .SYNOPSIS
    Stop GUI execution worker async.

    .DESCRIPTION
    Starts the asynchronous shutdown path for a GUI execution worker.
#>

function Stop-GuiExecutionWorkerAsync
{
	# Fire-and-forget cleanup via ThreadPool. Each step (Stop, EndInvoke, Dispose,
	# Runspace.Close/Dispose) is wrapped in its own try/catch because a failure in
	# one step must not prevent cleanup of subsequent resources. Callers should null
	# out their $Worker reference after calling this function - the ThreadPool work
	# item provides no completion signal.
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	[System.Threading.ThreadPool]::QueueUserWorkItem(
		[System.Threading.WaitCallback]{
			param($state)

			if (-not $state)
			{
				return
			}

			try
			{
				if ($state.PowerShell)
				{
					$state.PowerShell.Stop()
				}
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to stop GUI execution worker asynchronously: $($_.Exception.Message)"
			}

			try
			{
				if ($state.PowerShell -and $state.AsyncResult)
				{
					$state.PowerShell.EndInvoke($state.AsyncResult)
				}
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to finalize GUI execution worker asynchronously: $($_.Exception.Message)"
			}

			try
			{
				if ($state.PowerShell)
				{
					$state.PowerShell.Dispose()
				}
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to dispose GUI PowerShell worker asynchronously: $($_.Exception.Message)"
			}

			try
			{
				if ($state.Runspace)
				{
					$state.Runspace.Close()
					$state.Runspace.Dispose()
				}
			}
			catch
			{
				Write-GuiExecutionCleanupWarning "Failed to dispose GUI runspace asynchronously: $($_.Exception.Message)"
			}
		},
		$Worker
	) | Out-Null
}

<#
    .SYNOPSIS
    Stop GUI execution worker.

    .DESCRIPTION
    Stops the active GUI execution worker and releases worker resources.
#>

function Stop-GuiExecutionWorker
{
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	try
	{
		if ($Worker.PowerShell)
		{
			$Worker.PowerShell.Stop()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to stop GUI execution worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.PowerShell -and $Worker.AsyncResult)
		{
			$Worker.PowerShell.EndInvoke($Worker.AsyncResult)
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to finalize GUI execution worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.PowerShell)
		{
			$Worker.PowerShell.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose GUI PowerShell worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.Runspace)
		{
			$Worker.Runspace.Close()
			$Worker.Runspace.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose GUI runspace: $($_.Exception.Message)"
	}
}

<#
    .SYNOPSIS
    Complete GUI execution worker.

    .DESCRIPTION
    Finishes GUI execution worker cleanup and updates run-state metadata.
#>

function Complete-GuiExecutionWorker
{
	param (
		[Parameter(Mandatory = $true)]
		$Worker
	)

	if (-not $Worker)
	{
		return
	}

	try
	{
		if ($Worker.PowerShell -and $Worker.AsyncResult)
		{
			$Worker.PowerShell.EndInvoke($Worker.AsyncResult)
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to finalize completed GUI execution worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.PowerShell)
		{
			$Worker.PowerShell.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose completed GUI PowerShell worker: $($_.Exception.Message)"
	}

	try
	{
		if ($Worker.Runspace)
		{
			$Worker.Runspace.Close()
			$Worker.Runspace.Dispose()
		}
	}
	catch
	{
		Write-GuiExecutionCleanupWarning "Failed to dispose completed GUI runspace: $($_.Exception.Message)"
	}
}

Export-ModuleMember -Function @(
	'Update-GuiRunStateCounter'
	'Test-GuiExecutionObjectField'
	'Get-GuiExecutionOutcome'
	'Get-GuiExecutionActionTimeoutSeconds'
	'Get-GuiPreRunSnapshotTimeoutSeconds'
	'Test-GuiExecutionAppliedOutcome'
	'Test-GuiExecutionCriticalAction'
	'Test-GuiExecutionInvocationTimedOut'
	'New-GuiExecutionAppliedTweakMetadata'
	'New-GuiExecutionAppBatchEntry'
	'New-GuiExecutionAppBatchResult'
	'Get-GuiExecutionSummaryPayload'
	'Resolve-GuiExecutionAvailabilityGate'
	'Resolve-GuiExecutionSupportsExecutionGate'
	'New-GuiExecutionActionHost'
	'Close-GuiExecutionActionHost'
	'Invoke-GuiExecutionActionHostCommand'
	'Get-GuiExecutionAppActionVerb'
	'Resolve-GuiAppTimeoutVerification'
	'Write-GuiExecutionTimeoutRecord'
	'Invoke-GuiPreRunSnapshotCapture'
	'Start-GuiExecutionWorker'
	'Start-GuiAppExecutionWorker'
	'Request-GuiExecutionWorkerStop'
	'Stop-GuiExecutionWorkerAsync'
	'Stop-GuiExecutionWorker'
	'Complete-GuiExecutionWorker'
)
