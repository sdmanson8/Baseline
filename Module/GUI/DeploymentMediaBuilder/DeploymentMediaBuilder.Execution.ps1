# DeploymentMediaBuilder.Execution.ps1
# Bounded execution, cancellation, telemetry, and cleanup helpers.

function Write-GuiDeploymentMediaBuildStatus
{
	[CmdletBinding()]
	param (
		[scriptblock]$ProgressCallback,
		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	if ($ProgressCallback)
	{
		& $ProgressCallback $Message
	}
	if (Get-Command -Name 'LogInfo' -CommandType Function, Alias -ErrorAction SilentlyContinue)
	{
		LogInfo $Message
	}
}

function Format-GuiDeploymentMediaExecutionByteProgressText
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Operation,
		[long]$CompletedBytes,
		[long]$TotalBytes,
		[long]$RemainingSeconds = -1
	)

	$safeCompleted = [Math]::Max([int64]0, [int64]$CompletedBytes)
	$safeTotal = [Math]::Max([int64]1, [int64]$TotalBytes)
	$completedGb = $safeCompleted / 1GB
	$totalGb = $safeTotal / 1GB
	$pct = if ($TotalBytes -le 0)
	{
		if ($CompletedBytes -ge $TotalBytes) { 100.0 } else { 0.0 }
	}
	else
	{
		[Math]::Round(($safeCompleted / [double]$safeTotal) * 100, 1)
	}
	$remainingText = if ($RemainingSeconds -ge 0)
	{
		$remaining = [TimeSpan]::FromSeconds([double]$RemainingSeconds)
		if ($remaining.TotalHours -ge 1) { '{0:00}:{1:00}:{2:00}' -f [int]$remaining.TotalHours, $remaining.Minutes, $remaining.Seconds }
		else { '{0:00}:{1:00}' -f $remaining.Minutes, $remaining.Seconds }
	}
	else
	{
		'calculating'
	}

	return ('{0}: {1:N2}/{2:N2} GB ({3:N1}%). Time remaining: {4}.' -f $Operation, $completedGb, $totalGb, $pct, $remainingText)
}

function New-GuiDeploymentMediaByteProgressRecord
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Operation,
		[long]$CompletedBytes,
		[long]$TotalBytes,
		[Parameter(Mandatory = $true)]
		[DateTime]$StartedUtc
	)

	$remainingSeconds = [int64]-1
	if ($CompletedBytes -ge $TotalBytes -and $TotalBytes -ge 0)
	{
		$remainingSeconds = [int64]0
	}
	else
	{
		$elapsedSeconds = ([DateTime]::UtcNow - $StartedUtc).TotalSeconds
		if ($CompletedBytes -gt 0 -and $elapsedSeconds -gt 0)
		{
			$bytesPerSecond = $CompletedBytes / [double]$elapsedSeconds
			if ($bytesPerSecond -gt 0)
			{
				$remainingSeconds = [int64][Math]::Ceiling(([Math]::Max([int64]0, [int64]$TotalBytes - [int64]$CompletedBytes)) / $bytesPerSecond)
			}
		}
	}

	$displayText = Format-GuiDeploymentMediaExecutionByteProgressText -Operation $Operation -CompletedBytes $CompletedBytes -TotalBytes $TotalBytes -RemainingSeconds $remainingSeconds
	return [pscustomobject]@{
		IsByteProgress = $true
		Operation = $Operation
		Message = $Operation
		CompletedBytes = [int64]$CompletedBytes
		TotalBytes = [int64]$TotalBytes
		RemainingSeconds = [int64]$remainingSeconds
		DisplayText = $displayText
		StartedUtc = $StartedUtc
		UpdatedUtc = [DateTime]::UtcNow
	}
}

function Write-GuiDeploymentMediaBuildCopyProgress
{
	[CmdletBinding()]
	param (
		[scriptblock]$ProgressCallback,
		[Parameter(Mandatory = $true)]
		[string]$Operation,
		[long]$CompletedBytes,
		[long]$TotalBytes,
		[Parameter(Mandatory = $true)]
		[DateTime]$StartedUtc
	)

	if (-not $ProgressCallback) { return }

	$newProgressRecord = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'New-GuiDeploymentMediaByteProgressRecord'
	$progress = & $newProgressRecord -Operation $Operation -CompletedBytes $CompletedBytes -TotalBytes $TotalBytes -StartedUtc $StartedUtc
	& $ProgressCallback $progress
}

function New-GuiDeploymentMediaCancellationState
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	return [hashtable]::Synchronized(@{
		CancelRequested = $false
		CancelReason = ''
		RequestedUtc = $null
		CurrentStage = ''
		StageStartedUtc = $null
	})
}

function Request-GuiDeploymentMediaCancellation
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$CancellationState,
		[string]$Reason = 'Deployment media operation cancelled by operator.'
	)

	if (-not $CancellationState) { return }

	$CancellationState.CancelRequested = $true
	$CancellationState.CancelReason = $Reason
	$CancellationState.RequestedUtc = [DateTime]::UtcNow
}

function Test-GuiDeploymentMediaCancellationRequested
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[hashtable]$CancellationState
	)

	return ($CancellationState -and $CancellationState.ContainsKey('CancelRequested') -and [bool]$CancellationState.CancelRequested)
}

function Assert-GuiDeploymentMediaNotCancelled
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$CancellationState,
		[string]$Stage = 'Deployment media operation'
	)

	if (Test-GuiDeploymentMediaCancellationRequested -CancellationState $CancellationState)
	{
		$reason = if ($CancellationState.ContainsKey('CancelReason') -and -not [string]::IsNullOrWhiteSpace([string]$CancellationState.CancelReason)) { [string]$CancellationState.CancelReason } else { 'Deployment media operation cancelled by operator.' }
		throw ([System.OperationCanceledException]::new(('{0} cancelled. {1}' -f $Stage, $reason)))
	}
}

function Set-GuiDeploymentMediaCurrentStage
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$CancellationState,
		[string]$Stage
	)

	if (-not $CancellationState) { return }

	$CancellationState.CurrentStage = [string]$Stage
	$CancellationState.StageStartedUtc = [DateTime]::UtcNow
}

function New-GuiDeploymentMediaBuildTelemetry
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan,
		[Parameter(Mandatory = $true)]
		[string]$BuildRoot,
		[Parameter(Mandatory = $true)]
		[string]$MediaRoot,
		[Parameter(Mandatory = $true)]
		[string]$MountRoot,
		[int]$GlobalTimeoutSeconds
	)

	$architecture = ''
	if ($Plan.IsoImageInfo -and $Plan.IsoImageInfo.PSObject.Properties['Editions'])
	{
		foreach ($edition in @($Plan.IsoImageInfo.Editions))
		{
			if ([int]$edition.Index -eq [int]$Plan.EditionIndex -and $edition.PSObject.Properties['Architecture'])
			{
				$architecture = [string]$edition.Architecture
				break
			}
		}
	}

	return @{
		SourceIsoName = [System.IO.Path]::GetFileName([string]$Plan.SourceIso)
		SourceIsoPath = [string]$Plan.SourceIso
		EditionIndex = [int]$Plan.EditionIndex
		EditionName = [string]$Plan.EditionName
		Architecture = $architecture
		ImageKind = $(if ($Plan.IsoImageInfo -and $Plan.IsoImageInfo.PSObject.Properties['ImageKind']) { [string]$Plan.IsoImageInfo.ImageKind } else { '' })
		OutputMode = [string]$Plan.OutputMode
		GlobalTimeoutSeconds = [int]$GlobalTimeoutSeconds
		TempPaths = [pscustomobject]@{
			BuildRoot = $BuildRoot
			MediaRoot = $MediaRoot
			MountRoot = $MountRoot
		}
		StageRecords = [System.Collections.Generic.List[object]]::new()
		CleanupRecords = [System.Collections.Generic.List[object]]::new()
	}
}

function Write-GuiDeploymentMediaTelemetryLog
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$Telemetry,
		[Parameter(Mandatory = $true)]
		[ValidateSet('Stage', 'Cleanup')]
		[string]$Kind,
		[Parameter(Mandatory = $true)]
		[object]$Record
	)

	if (-not $Telemetry -or -not $Record) { return }

	try
	{
		$tempPaths = $Telemetry.TempPaths
		$payload = [ordered]@{
			Event = 'DeploymentMediaBuilderTelemetry'
			Kind = $Kind
			Name = [string]$Record.Name
			Outcome = [string]$Record.Outcome
			StartedUtc = $Record.StartedUtc
			CompletedUtc = $Record.CompletedUtc
			ElapsedSeconds = $Record.ElapsedSeconds
			Detail = [string]$Record.Detail
			SourceIsoName = [string]$Telemetry.SourceIsoName
			EditionIndex = [int]$Telemetry.EditionIndex
			EditionName = [string]$Telemetry.EditionName
			Architecture = [string]$Telemetry.Architecture
			ImageKind = [string]$Telemetry.ImageKind
			OutputMode = [string]$Telemetry.OutputMode
			GlobalTimeoutSeconds = [int]$Telemetry.GlobalTimeoutSeconds
			TempPaths = [ordered]@{
				BuildRoot = $(if ($tempPaths) { [string]$tempPaths.BuildRoot } else { '' })
				MediaRoot = $(if ($tempPaths) { [string]$tempPaths.MediaRoot } else { '' })
				MountRoot = $(if ($tempPaths) { [string]$tempPaths.MountRoot } else { '' })
			}
		}
		$message = 'DeploymentMediaTelemetry ' + (ConvertTo-Json -InputObject $payload -Depth 8 -Compress)
		if ([string]$Record.Outcome -eq 'Failed')
		{
			if ($Kind -eq 'Cleanup' -and (Get-Command -Name 'LogWarning' -CommandType Function, Alias -ErrorAction SilentlyContinue))
			{
				LogWarning $message
			}
			elseif (Get-Command -Name 'LogError' -CommandType Function, Alias -ErrorAction SilentlyContinue)
			{
				LogError $message
			}
			return
		}
		if (Get-Command -Name 'LogInfo' -CommandType Function, Alias -ErrorAction SilentlyContinue)
		{
			LogInfo $message
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.TelemetryLog' -Severity Warning
		}
	}
}

function Add-GuiDeploymentMediaTelemetryRecord
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$Telemetry,
		[Parameter(Mandatory = $true)]
		[ValidateSet('Stage', 'Cleanup')]
		[string]$Kind,
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[DateTime]$StartedUtc,
		[Parameter(Mandatory = $true)]
		[DateTime]$CompletedUtc,
		[Parameter(Mandatory = $true)]
		[string]$Outcome,
		[string]$Detail = ''
	)

	if (-not $Telemetry) { return }

	$record = [pscustomobject]@{
		Name = $Name
		StartedUtc = $StartedUtc
		CompletedUtc = $CompletedUtc
		ElapsedSeconds = [Math]::Round(($CompletedUtc - $StartedUtc).TotalSeconds, 3)
		Outcome = $Outcome
		Detail = $Detail
	}

	if ($Kind -eq 'Cleanup')
	{
		[void]$Telemetry.CleanupRecords.Add($record)
	}
	else
	{
		[void]$Telemetry.StageRecords.Add($record)
	}

	Write-GuiDeploymentMediaTelemetryLog -Telemetry $Telemetry -Kind $Kind -Record $record
}

function Get-GuiDeploymentMediaExecutionFunctionCapture
{
	[CmdletBinding()]
	[OutputType([scriptblock])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	$command = Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
	if (-not $command -or -not $command.ScriptBlock)
	{
		throw ('Deployment media required helper is not loaded: {0}' -f $Name)
	}

	$scriptBlock = $command.ScriptBlock
	return {
		& $scriptBlock @args
	}.GetNewClosure()
}

function Get-GuiDeploymentMediaTelemetryRecordWriter
{
	[CmdletBinding()]
	[OutputType([scriptblock])]
	param ()

	return (Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Add-GuiDeploymentMediaTelemetryRecord')
}

function Get-GuiDeploymentMediaStageTimeoutSeconds
{
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[DateTime]$OperationStartedUtc,
		[int]$GlobalTimeoutSeconds,
		[int]$StageTimeoutSeconds
	)

	if ($StageTimeoutSeconds -lt 1) { $StageTimeoutSeconds = 1 }
	if ($GlobalTimeoutSeconds -lt 1) { return $StageTimeoutSeconds }

	$deadlineUtc = $OperationStartedUtc.AddSeconds($GlobalTimeoutSeconds)
	$remainingSeconds = [int][Math]::Floor(($deadlineUtc - [DateTime]::UtcNow).TotalSeconds)
	if ($remainingSeconds -lt 1)
	{
		throw ([System.TimeoutException]::new(('Deployment media build exceeded its global timeout of {0} second(s).' -f $GlobalTimeoutSeconds)))
	}

	return [Math]::Max(1, [Math]::Min($StageTimeoutSeconds, $remainingSeconds))
}

function Invoke-GuiDeploymentMediaCleanupWithRetry
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[scriptblock]$Action,
		[AllowNull()]
		[hashtable]$Telemetry,
		[string]$Detail = '',
		[ValidateRange(1, 10)]
		[int]$MaxAttempts = 3,
		[ValidateRange(0, 60000)]
		[int]$DelayMilliseconds = 750
	)

	$startedUtc = [DateTime]::UtcNow
	$addTelemetryRecord = Get-GuiDeploymentMediaTelemetryRecordWriter
	$attemptCount = [Math]::Max(1, $MaxAttempts)
	$lastError = $null
	for ($attempt = 1; $attempt -le $attemptCount; $attempt++)
	{
		try
		{
			& $Action
			$successDetail = ('{0}; Attempts={1}' -f $Detail, $attempt).Trim(@(';', ' '))
			& $addTelemetryRecord -Telemetry $Telemetry -Kind Cleanup -Name $Name -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Succeeded' -Detail $successDetail
			return
		}
		catch
		{
			$lastError = $_
			if ($attempt -lt $attemptCount)
			{
				if (Get-Command -Name 'LogWarning' -CommandType Function, Alias -ErrorAction SilentlyContinue)
				{
					LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix ('Deployment media cleanup retry {0}/{1} for {2}' -f ($attempt + 1), $attemptCount, $Name))
				}
				if ($DelayMilliseconds -gt 0)
				{
					Start-Sleep -Milliseconds $DelayMilliseconds
				}
			}
		}
	}

	$failureDetail = ('{0}; Attempts={1}; Error={2}' -f $Detail, $attemptCount, $lastError.Exception.Message).Trim(@(';', ' '))
	& $addTelemetryRecord -Telemetry $Telemetry -Kind Cleanup -Name $Name -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Failed' -Detail $failureDetail
	if ($lastError) { throw $lastError }
}

function Request-GuiDeploymentMediaPowerShellStop
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[System.Management.Automation.PowerShell]$PowerShell,
		[string]$Source = 'DeploymentMedia.PowerShellStop',
		[int]$StopWaitMilliseconds = 1000
	)

	if (-not $PowerShell) { return $true }

	try
	{
		$stopResult = $PowerShell.BeginStop($null, $null)
		if ($stopResult -and $stopResult.AsyncWaitHandle)
		{
			if ($stopResult.AsyncWaitHandle.WaitOne([Math]::Max(0, $StopWaitMilliseconds)))
			{
				try { $PowerShell.EndStop($stopResult) }
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source ($Source + '.EndStop') -Severity Debug
					}
				}
				return $true
			}
			return $false
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source $Source -Severity Warning
		}
		return $false
	}

	return $true
}

function Import-GuiDeploymentMediaDismModule
{
	[CmdletBinding()]
	param ()

	if (Get-Command -Name 'Get-WindowsImage' -CommandType Function, Cmdlet -ErrorAction SilentlyContinue)
	{
		return
	}

	try
	{
		Import-Module -Name 'Dism' -ErrorAction Stop -WarningAction SilentlyContinue
	}
	catch
	{
		throw ('The inbox DISM PowerShell module is required to inspect Windows images, but Baseline could not load it: {0}' -f $_.Exception.Message)
	}

	if (-not (Get-Command -Name 'Get-WindowsImage' -CommandType Function, Cmdlet -ErrorAction SilentlyContinue))
	{
		throw 'The inbox DISM PowerShell module is required to inspect Windows images, but Get-WindowsImage was not available after loading Dism.'
	}
}

function Invoke-GuiDeploymentMediaPowerShellStage
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock,
		[object[]]$ArgumentList = @(),
		[ValidateRange(1, 86400)]
		[int]$TimeoutSeconds = 900,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry
	)

	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	$setCurrentStage = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Set-GuiDeploymentMediaCurrentStage'
	$requestPowerShellStop = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Request-GuiDeploymentMediaPowerShellStop'
	$testCancellationRequested = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Test-GuiDeploymentMediaCancellationRequested'
	& $assertNotCancelled -CancellationState $CancellationState -Stage $Name
	& $setCurrentStage -CancellationState $CancellationState -Stage $Name

	$startedUtc = [DateTime]::UtcNow
	$addTelemetryRecord = Get-GuiDeploymentMediaTelemetryRecordWriter
	$runspace = $null
	$ps = $null
	$asyncResult = $null
	$completed = $false
	try
	{
		$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
		$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialSessionState)
		$runspace.ApartmentState = 'STA'
		$runspace.ThreadOptions = 'ReuseThread'
		$runspace.Open()

		$ps = [System.Management.Automation.PowerShell]::Create()
		$ps.Runspace = $runspace
		[void]$ps.AddScript($ScriptBlock.ToString())
		foreach ($argument in @($ArgumentList))
		{
			[void]$ps.AddArgument($argument)
		}

		$asyncResult = $ps.BeginInvoke()
		$deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
		while (-not $asyncResult.AsyncWaitHandle.WaitOne(250))
		{
			if (& $testCancellationRequested -CancellationState $CancellationState)
			{
				[void](& $requestPowerShellStop -PowerShell $ps -Source ('DeploymentMedia.{0}.CancelStop' -f $Name))
				throw ([System.OperationCanceledException]::new(('Deployment media stage cancelled: {0}' -f $Name)))
			}
			if ([DateTime]::UtcNow -ge $deadlineUtc)
			{
				[void](& $requestPowerShellStop -PowerShell $ps -Source ('DeploymentMedia.{0}.TimeoutStop' -f $Name))
				throw ([System.TimeoutException]::new(('{0} timed out after {1} second(s).' -f $Name, $TimeoutSeconds)))
			}
		}

		$completed = $true
		$result = @($ps.EndInvoke($asyncResult))
		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $Name -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Succeeded'
		if ($result.Count -eq 0) { return $null }
		if ($result.Count -eq 1) { return $result[0] }
		return $result
	}
	catch
	{
		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $Name -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Failed' -Detail $_.Exception.Message
		throw
	}
	finally
	{
		if (-not $completed -and $ps)
		{
			[void](& $requestPowerShellStop -PowerShell $ps -Source ('DeploymentMedia.{0}.FinalStop' -f $Name))
		}
		try { if ($ps) { $ps.Dispose() } }
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source ('DeploymentMedia.{0}.DisposePowerShell' -f $Name) -Severity Warning
			}
		}
		try
		{
			if ($runspace)
			{
				if ($completed) { $runspace.Close() } else { $runspace.CloseAsync() }
				$runspace.Dispose()
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source ('DeploymentMedia.{0}.DisposeRunspace' -f $Name) -Severity Warning
			}
		}
	}
}

function Get-GuiDeploymentMediaOscdimgCandidatePaths
{
	[CmdletBinding()]
	[OutputType([string[]])]
	param ()

	$candidates = [System.Collections.Generic.List[string]]::new()
	$addCandidate = {
		param ([string]$Path)
		if (-not [string]::IsNullOrWhiteSpace($Path))
		{
			[void]$candidates.Add([System.IO.Path]::GetFullPath($Path))
		}
	}

	foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles))
	{
		if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
		foreach ($architecture in @('amd64', 'x86', 'arm64'))
		{
			& $addCandidate (Join-Path $root ('Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\{0}\Oscdimg\oscdimg.exe' -f $architecture))
		}
	}

	$wingetRoots = [System.Collections.Generic.List[string]]::new()
	if (-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) { [void]$wingetRoots.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet')) }
	if (-not [string]::IsNullOrWhiteSpace([string]$env:ProgramFiles)) { [void]$wingetRoots.Add((Join-Path $env:ProgramFiles 'WinGet')) }
	if (-not [string]::IsNullOrWhiteSpace([string]${env:ProgramFiles(x86)})) { [void]$wingetRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'WinGet')) }
	foreach ($wingetRoot in @($wingetRoots))
	{
		if ([string]::IsNullOrWhiteSpace([string]$wingetRoot)) { continue }
		& $addCandidate (Join-Path $wingetRoot 'Links\oscdimg.exe')
		$packageRoot = Join-Path $wingetRoot 'Packages'
		if (Test-Path -LiteralPath $packageRoot -PathType Container)
		{
			foreach ($directory in @(Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'Microsoft.OSCDIMG_*' -ErrorAction SilentlyContinue))
			{
				& $addCandidate (Join-Path $directory.FullName 'oscdimg.exe')
			}
		}
	}

	return @($candidates.ToArray() | Select-Object -Unique)
}

function Find-GuiDeploymentMediaOscdimgPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if (Get-Command -Name 'Update-ProcessPathFromRegistry' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-ProcessPathFromRegistry
	}

	$command = Get-Command -Name 'oscdimg.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source))
	{
		return [string]$command.Source
	}

	foreach ($candidate in @(Get-GuiDeploymentMediaOscdimgCandidatePaths))
	{
		if (Test-Path -LiteralPath $candidate -PathType Leaf)
		{
			return $candidate
		}
	}

	return ''
}

function Resolve-GuiDeploymentMediaWingetPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	if (Get-Command -Name 'Resolve-WinGetExecutable' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$resolved = Resolve-WinGetExecutable
		if (-not [string]::IsNullOrWhiteSpace([string]$resolved) -and (Test-Path -LiteralPath ([string]$resolved) -PathType Leaf))
		{
			return [string]$resolved
		}
	}

	if (Get-Command -Name 'Update-ProcessPathFromRegistry' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-ProcessPathFromRegistry
	}

	$command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source))
	{
		return [string]$command.Source
	}

	foreach ($candidate in @(
		(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
		(Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\winget.exe')
	))
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf))
		{
			return [string]$candidate
		}
	}

	return ''
}

function Get-GuiDeploymentMediaOscdimgInstallPageUrl
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	return 'https://winstall.app/apps/Microsoft.OSCDIMG'
}

function Test-GuiDeploymentMediaOscdimgDependencyError
{
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[AllowNull()]
		[object]$ErrorRecord,
		[string]$Message = ''
	)

	$text = [string]$Message
	if ([string]::IsNullOrWhiteSpace($text) -and $ErrorRecord -and $ErrorRecord.PSObject.Properties['Exception'])
	{
		$text = [string]$ErrorRecord.Exception.Message
	}

	if ([string]::IsNullOrWhiteSpace($text)) { return $false }
	return ($text -match 'Microsoft OSCDIMG' -or $text -match 'Microsoft\.OSCDIMG' -or $text -match 'oscdimg\.exe is required')
}

function Install-GuiDeploymentMediaOscdimgPackage
{
	[CmdletBinding()]
	param (
		[scriptblock]$ProgressCallback,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry,
		[int]$TimeoutSeconds = 1800
	)

	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	& $assertNotCancelled -CancellationState $CancellationState -Stage 'Install Microsoft OSCDIMG'

	if (Get-Command -Name 'Test-WinGetAvailable' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if (-not (Test-WinGetAvailable -Refresh))
		{
			throw 'Microsoft OSCDIMG could not be installed because WinGet is not available.'
		}
	}

	$wingetPath = Resolve-GuiDeploymentMediaWingetPath
	if ([string]::IsNullOrWhiteSpace([string]$wingetPath))
	{
		throw 'Microsoft OSCDIMG could not be installed because winget.exe was not found.'
	}

	Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message 'Installing Microsoft OSCDIMG from WinGet.'
	$arguments = @(
		'install',
		'--id', 'Microsoft.OSCDIMG',
		'--exact',
		'--silent',
		'--accept-package-agreements',
		'--accept-source-agreements',
		'--disable-interactivity',
		'--source', 'winget'
	)
	$null = Invoke-GuiDeploymentMediaProcess -FilePath $wingetPath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes @(0) -CancellationState $CancellationState -StageName 'Install Microsoft OSCDIMG' -Telemetry $Telemetry
	if (Get-Command -Name 'Update-ProcessPathFromRegistry' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-ProcessPathFromRegistry
	}
}

function Resolve-GuiDeploymentMediaOscdimgPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[switch]$InstallIfMissing,
		[scriptblock]$ProgressCallback,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry,
		[int]$TimeoutSeconds = 1800
	)

	$resolved = Find-GuiDeploymentMediaOscdimgPath
	if (-not [string]::IsNullOrWhiteSpace([string]$resolved))
	{
		return [string]$resolved
	}

	if ($InstallIfMissing)
	{
		Install-GuiDeploymentMediaOscdimgPackage -ProgressCallback $ProgressCallback -CancellationState $CancellationState -Telemetry $Telemetry -TimeoutSeconds $TimeoutSeconds
		$resolved = Find-GuiDeploymentMediaOscdimgPath
		if (-not [string]::IsNullOrWhiteSpace([string]$resolved))
		{
			return [string]$resolved
		}
	}

	throw 'oscdimg.exe is required to create an ISO. Baseline can install the official Microsoft.OSCDIMG package from WinGet when WinGet is available.'
}

function Resolve-GuiDeploymentMediaDismPath
{
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$dismPath = Join-Path $env:SystemRoot 'System32\dism.exe'
	if (Test-Path -LiteralPath $dismPath -PathType Leaf)
	{
		return $dismPath
	}

	$command = Get-Command -Name 'dism.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source))
	{
		return [string]$command.Source
	}

	throw 'dism.exe is required for deployment media image servicing.'
}

function Invoke-GuiDeploymentMediaProcess
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$FilePath,
		[object[]]$ArgumentList = @(),
		[int]$TimeoutSeconds = 7200,
		[int[]]$AllowedExitCodes = @(0),
		[AllowNull()]
		[hashtable]$CancellationState,
		[string]$StageName = '',
		[string]$WorkingDirectory = '',
		[AllowNull()]
		[hashtable]$Telemetry
	)

	$convertProcessArguments = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'ConvertTo-BaselineProcessArgumentString'
	$stopProcessTree = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Stop-BaselineProcessTree'
	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	$setCurrentStage = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Set-GuiDeploymentMediaCurrentStage'
	$testCancellationRequested = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Test-GuiDeploymentMediaCancellationRequested'

	$effectiveStageName = if ([string]::IsNullOrWhiteSpace($StageName)) { [System.IO.Path]::GetFileName($FilePath) } else { $StageName }
	& $assertNotCancelled -CancellationState $CancellationState -Stage $effectiveStageName
	& $setCurrentStage -CancellationState $CancellationState -Stage $effectiveStageName

	$startedUtc = [DateTime]::UtcNow
	$addTelemetryRecord = Get-GuiDeploymentMediaTelemetryRecordWriter
	$argumentDisplay = & $convertProcessArguments -ArgumentList $ArgumentList
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
		$psi.Arguments = $argumentDisplay
	}
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
	if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory))
	{
		if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container))
		{
			throw ('Working directory does not exist for {0}: {1}' -f $effectiveStageName, $WorkingDirectory)
		}
		$psi.WorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)
	}

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	try
	{
		[void]$process.Start()
		$deadlineUtc = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
		while (-not $process.WaitForExit(250))
		{
			if (& $testCancellationRequested -CancellationState $CancellationState)
			{
				& $stopProcessTree -Process $process -Source ('DeploymentMedia.{0}.Cancel' -f $effectiveStageName)
				throw ([System.OperationCanceledException]::new(('Deployment media process cancelled during {0}.' -f $effectiveStageName)))
			}
			if ([DateTime]::UtcNow -ge $deadlineUtc)
			{
				& $stopProcessTree -Process $process -Source ('DeploymentMedia.{0}.Timeout' -f $effectiveStageName)
				throw ([System.TimeoutException]::new(('{0} timed out after {1} second(s). Process: {2}' -f $effectiveStageName, $TimeoutSeconds, $FilePath)))
			}
		}

		$effectiveAllowedExitCodes = @($AllowedExitCodes)
		if ($effectiveAllowedExitCodes.Count -eq 0) { $effectiveAllowedExitCodes = @(0) }
		if ($process.ExitCode -notin $effectiveAllowedExitCodes)
		{
			throw ("Process '{0}' failed with exit code {1}. Arguments: {2}" -f $FilePath, $process.ExitCode, $argumentDisplay)
		}

		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $effectiveStageName -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Succeeded' -Detail ('ProcessId={0}; ExitCode={1}' -f $process.Id, $process.ExitCode)
		return [pscustomobject]@{
			ExitCode = [int]$process.ExitCode
			TimedOut = $false
			ProcessId = [int]$process.Id
			FilePath = $FilePath
			Arguments = $argumentDisplay
		}
	}
	catch
	{
		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $effectiveStageName -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Failed' -Detail $_.Exception.Message
		throw
	}
	finally
	{
		try { $process.Dispose() }
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Write-SwallowedException -ErrorRecord $_ -Source ('DeploymentMedia.{0}.DisposeProcess' -f $effectiveStageName) -Severity Debug
			}
		}
	}
}

function Invoke-GuiDeploymentMediaDism
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object[]]$ArgumentList,
		[Parameter(Mandatory = $true)]
		[string]$StageName,
		[int]$TimeoutSeconds = 3600,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry
	)

	$dismPath = Resolve-GuiDeploymentMediaDismPath
	return Invoke-GuiDeploymentMediaProcess -FilePath $dismPath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes @(0) -CancellationState $CancellationState -StageName $StageName -Telemetry $Telemetry
}

function Invoke-GuiDeploymentMediaIsoDismountCleanup
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$ImagePath,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry
	)

	$cleanupAction = {
		$diskImage = Get-DiskImage -ImagePath $ImagePath -ErrorAction SilentlyContinue
		if ($diskImage -and $diskImage.Attached)
		{
			Dismount-DiskImage -ImagePath $ImagePath -ErrorAction Stop
		}
	}.GetNewClosure()
	Invoke-GuiDeploymentMediaCleanupWithRetry -Name 'Dismount source ISO' -Action $cleanupAction -Telemetry $Telemetry -Detail $ImagePath -MaxAttempts 3 -DelayMilliseconds 750
}

function Invoke-GuiDeploymentMediaDismountImage
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$MountPath,
		[Parameter(Mandatory = $true)]
		[ValidateSet('Save', 'Discard')]
		[string]$Mode,
		[int]$TimeoutSeconds = 1800,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry,
		[switch]$Cleanup
	)

	$modeArgument = if ($Mode -eq 'Save') { '/Commit' } else { '/Discard' }
	$stageName = ('Dismount image ({0})' -f $Mode)
	$startedUtc = [DateTime]::UtcNow
	if ($Cleanup)
	{
		$cleanupAction = {
			$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Unmount-Image', ('/MountDir:{0}' -f $MountPath), $modeArgument) -StageName $stageName -TimeoutSeconds $TimeoutSeconds -CancellationState $CancellationState -Telemetry $null
		}.GetNewClosure()
		Invoke-GuiDeploymentMediaCleanupWithRetry -Name $stageName -Action $cleanupAction -Telemetry $Telemetry -Detail $MountPath -MaxAttempts 3 -DelayMilliseconds 1000
		return
	}

	try
	{
		$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Unmount-Image', ('/MountDir:{0}' -f $MountPath), $modeArgument) -StageName $stageName -TimeoutSeconds $TimeoutSeconds -CancellationState $CancellationState -Telemetry $Telemetry
	}
	catch
	{
		throw
	}
}

function Invoke-GuiDeploymentMediaEmergencyDismCleanup
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry
	)

	$cleanupAction = {
		$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Cleanup-Wim') -StageName 'Emergency DISM cleanup' -TimeoutSeconds 900 -CancellationState $CancellationState -Telemetry $null
	}.GetNewClosure()
	Invoke-GuiDeploymentMediaCleanupWithRetry -Name 'Emergency DISM cleanup' -Action $cleanupAction -Telemetry $Telemetry -MaxAttempts 3 -DelayMilliseconds 1000
}

function Invoke-GuiDeploymentMediaRobocopy
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Source,
		[Parameter(Mandatory = $true)]
		[string]$Destination,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry,
		[scriptblock]$ProgressCallback,
		[string]$Operation = 'Copying deployment media'
	)

	if (-not (Test-Path -LiteralPath $Source -PathType Container))
	{
		throw ('Deployment media copy source directory does not exist: {0}' -f $Source)
	}

	$stageName = if ([string]::IsNullOrWhiteSpace($Operation)) { 'Copying deployment media' } else { [string]$Operation }
	$startedUtc = [DateTime]::UtcNow
	$addTelemetryRecord = Get-GuiDeploymentMediaTelemetryRecordWriter
	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	$setCurrentStage = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Set-GuiDeploymentMediaCurrentStage'
	$writeCopyProgress = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Write-GuiDeploymentMediaBuildCopyProgress'
	$sourceRoot = [System.IO.Path]::GetFullPath($Source)
	$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
	$sourcePrefix = $sourceRoot
	if (-not $sourcePrefix.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString()) -and -not $sourcePrefix.EndsWith([System.IO.Path]::AltDirectorySeparatorChar.ToString()))
	{
		$sourcePrefix += [System.IO.Path]::DirectorySeparatorChar
	}
	[void][System.IO.Directory]::CreateDirectory($destinationRoot)
	& $setCurrentStage -CancellationState $CancellationState -Stage $stageName

	try
	{
		$directories = @(Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force -ErrorAction Stop)
		$files = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force -ErrorAction Stop)
		$totalBytes = [int64]0
		foreach ($file in $files)
		{
			$totalBytes += [int64]$file.Length
		}

		& $writeCopyProgress -ProgressCallback $ProgressCallback -Operation $stageName -CompletedBytes 0 -TotalBytes $totalBytes -StartedUtc $startedUtc

		foreach ($directory in $directories)
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage $stageName
			$relativeDirectory = $directory.FullName.Substring($sourcePrefix.Length).TrimStart([char[]]@('\', '/'))
			if ([string]::IsNullOrWhiteSpace($relativeDirectory)) { continue }
			$targetDirectory = Join-Path $destinationRoot $relativeDirectory
			[void][System.IO.Directory]::CreateDirectory($targetDirectory)
		}

		$completedBytes = [int64]0
		$lastProgressUtc = [DateTime]::UtcNow.AddSeconds(-1)
		$buffer = New-Object byte[] (4MB)
		foreach ($file in $files)
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage $stageName
			$relativeFile = $file.FullName.Substring($sourcePrefix.Length).TrimStart([char[]]@('\', '/'))
			$targetFile = Join-Path $destinationRoot $relativeFile
			$targetDirectory = [System.IO.Path]::GetDirectoryName($targetFile)
			if (-not [string]::IsNullOrWhiteSpace($targetDirectory))
			{
				[void][System.IO.Directory]::CreateDirectory($targetDirectory)
			}

			$sourceStream = $null
			$destinationStream = $null
			try
			{
				$sourceStream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
				$destinationStream = [System.IO.File]::Open($targetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
				while ($true)
				{
					& $assertNotCancelled -CancellationState $CancellationState -Stage $stageName
					$bytesRead = $sourceStream.Read($buffer, 0, $buffer.Length)
					if ($bytesRead -le 0) { break }
					$destinationStream.Write($buffer, 0, $bytesRead)
					$completedBytes += [int64]$bytesRead
					$nowUtc = [DateTime]::UtcNow
					if (($nowUtc - $lastProgressUtc).TotalMilliseconds -ge 500 -or $completedBytes -ge $totalBytes)
					{
						& $writeCopyProgress -ProgressCallback $ProgressCallback -Operation $stageName -CompletedBytes $completedBytes -TotalBytes $totalBytes -StartedUtc $startedUtc
						$lastProgressUtc = $nowUtc
					}
				}
			}
			finally
			{
				if ($destinationStream) { $destinationStream.Dispose() }
				if ($sourceStream) { $sourceStream.Dispose() }
			}

			$targetInfo = Get-Item -LiteralPath $targetFile -Force -ErrorAction Stop
			$targetInfo.CreationTimeUtc = $file.CreationTimeUtc
			$targetInfo.LastWriteTimeUtc = $file.LastWriteTimeUtc
			$targetInfo.LastAccessTimeUtc = $file.LastAccessTimeUtc
			$targetInfo.Attributes = $file.Attributes
		}

		foreach ($directory in $directories)
		{
			$relativeDirectory = $directory.FullName.Substring($sourcePrefix.Length).TrimStart([char[]]@('\', '/'))
			if ([string]::IsNullOrWhiteSpace($relativeDirectory)) { continue }
			$targetDirectory = Join-Path $destinationRoot $relativeDirectory
			$targetInfo = Get-Item -LiteralPath $targetDirectory -Force -ErrorAction Stop
			$targetInfo.CreationTimeUtc = $directory.CreationTimeUtc
			$targetInfo.LastWriteTimeUtc = $directory.LastWriteTimeUtc
			$targetInfo.LastAccessTimeUtc = $directory.LastAccessTimeUtc
			$targetInfo.Attributes = $directory.Attributes
		}

		& $writeCopyProgress -ProgressCallback $ProgressCallback -Operation $stageName -CompletedBytes $totalBytes -TotalBytes $totalBytes -StartedUtc $startedUtc
		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $stageName -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Succeeded' -Detail ('Files={0}; Bytes={1}' -f @($files).Count, $totalBytes)
	}
	catch
	{
		& $addTelemetryRecord -Telemetry $Telemetry -Kind Stage -Name $stageName -StartedUtc $startedUtc -CompletedUtc ([DateTime]::UtcNow) -Outcome 'Failed' -Detail $_.Exception.Message
		throw
	}
}

function Get-GuiDeploymentMediaPreparedInstallImagePath
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$MediaRoot
	)

	$wimPath = Join-Path $MediaRoot 'sources\install.wim'
	if (Test-Path -LiteralPath $wimPath -PathType Leaf) { return $wimPath }

	$esdPath = Join-Path $MediaRoot 'sources\install.esd'
	if (Test-Path -LiteralPath $esdPath -PathType Leaf) { return $esdPath }

	throw ('Prepared media does not contain sources\install.wim or sources\install.esd under {0}.' -f $MediaRoot)
}

function Invoke-GuiDeploymentMediaDriverInjection
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan,
		[Parameter(Mandatory = $true)]
		[string]$MediaRoot,
		[Parameter(Mandatory = $true)]
		[string]$MountRoot,
		[scriptblock]$ProgressCallback,
		[AllowNull()]
		[hashtable]$CancellationState,
		[AllowNull()]
		[hashtable]$Telemetry
	)

	if ([string]::IsNullOrWhiteSpace([string]$Plan.DriverSource) -and -not [bool]$Plan.InjectBootDrivers)
	{
		return
	}

	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	$null = Resolve-GuiDeploymentMediaDismPath
	[void][System.IO.Directory]::CreateDirectory($MountRoot)

	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.DriverSource))
	{
		& $assertNotCancelled -CancellationState $CancellationState -Stage 'Install image driver injection'
		$installImagePath = Get-GuiDeploymentMediaPreparedInstallImagePath -MediaRoot $MediaRoot
		if ([System.IO.Path]::GetExtension($installImagePath).Equals('.esd', [System.StringComparison]::OrdinalIgnoreCase))
		{
			throw 'Driver injection requires sources\install.wim; convert install.esd to WIM before enabling driver injection.'
		}

		$installMountPath = Join-Path $MountRoot 'Install'
		[void][System.IO.Directory]::CreateDirectory($installMountPath)
		Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Mounting install image index {0} for driver injection.' -f $Plan.EditionIndex)
		try
		{
			$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Mount-Image', ('/ImageFile:{0}' -f $installImagePath), ('/Index:{0}' -f ([int]$Plan.EditionIndex)), ('/MountDir:{0}' -f $installMountPath)) -StageName 'Mount install image' -TimeoutSeconds 1800 -CancellationState $CancellationState -Telemetry $Telemetry
			$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Image:{0}' -f $installMountPath, '/Add-Driver', ('/Driver:{0}' -f ([string]$Plan.DriverSource)), '/Recurse') -StageName 'Inject install drivers' -TimeoutSeconds 7200 -CancellationState $CancellationState -Telemetry $Telemetry
			Invoke-GuiDeploymentMediaDismountImage -MountPath $installMountPath -Mode Save -TimeoutSeconds 1800 -CancellationState $CancellationState -Telemetry $Telemetry
		}
		catch
		{
			$originalError = $_.Exception.Message
			try { Invoke-GuiDeploymentMediaDismountImage -MountPath $installMountPath -Mode Discard -TimeoutSeconds 1800 -CancellationState $null -Telemetry $Telemetry -Cleanup }
			catch
			{
				$cleanupError = $_.Exception.Message
				try { Invoke-GuiDeploymentMediaEmergencyDismCleanup -CancellationState $null -Telemetry $Telemetry }
				catch { throw ('Install image driver injection failed: {0} Cleanup failed: {1}; emergency cleanup failed: {2}' -f $originalError, $cleanupError, $_.Exception.Message) }
				throw ('Install image driver injection failed: {0} Cleanup failed: {1}' -f $originalError, $cleanupError)
			}
			throw ('Install image driver injection failed: {0}' -f $originalError)
		}
	}

	if ([bool]$Plan.InjectBootDrivers)
	{
		& $assertNotCancelled -CancellationState $CancellationState -Stage 'Boot image driver injection'
		if ([string]::IsNullOrWhiteSpace([string]$Plan.DriverSource))
		{
			throw 'Boot driver injection requires a driver source directory.'
		}

		$bootImagePath = Join-Path $MediaRoot 'sources\boot.wim'
		if (-not (Test-Path -LiteralPath $bootImagePath -PathType Leaf))
		{
			throw ('Prepared media does not contain sources\boot.wim under {0}.' -f $MediaRoot)
		}

		$bootImages = @(Invoke-GuiDeploymentMediaPowerShellStage -Name 'Inspect boot images' -ScriptBlock {
			param ([string]$ImagePath)
			Import-Module -Name 'Dism' -ErrorAction Stop -WarningAction SilentlyContinue
			foreach ($image in @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop))
			{
				[pscustomobject]@{
					ImageIndex = [int]$image.ImageIndex
				}
			}
		} -ArgumentList @($bootImagePath) -TimeoutSeconds 900 -CancellationState $CancellationState -Telemetry $Telemetry)
		foreach ($bootImage in $bootImages)
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage ('Boot image {0} driver injection' -f $bootImage.ImageIndex)
			$bootMountPath = Join-Path $MountRoot ('Boot-{0}' -f $bootImage.ImageIndex)
			[void][System.IO.Directory]::CreateDirectory($bootMountPath)
			Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Mounting boot image index {0} for driver injection.' -f $bootImage.ImageIndex)
			try
			{
				$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Mount-Image', ('/ImageFile:{0}' -f $bootImagePath), ('/Index:{0}' -f ([int]$bootImage.ImageIndex)), ('/MountDir:{0}' -f $bootMountPath)) -StageName ('Mount boot image {0}' -f $bootImage.ImageIndex) -TimeoutSeconds 1800 -CancellationState $CancellationState -Telemetry $Telemetry
				$null = Invoke-GuiDeploymentMediaDism -ArgumentList @('/Image:{0}' -f $bootMountPath, '/Add-Driver', ('/Driver:{0}' -f ([string]$Plan.DriverSource)), '/Recurse') -StageName ('Inject boot image {0} drivers' -f $bootImage.ImageIndex) -TimeoutSeconds 7200 -CancellationState $CancellationState -Telemetry $Telemetry
				Invoke-GuiDeploymentMediaDismountImage -MountPath $bootMountPath -Mode Save -TimeoutSeconds 1800 -CancellationState $CancellationState -Telemetry $Telemetry
			}
			catch
			{
				$originalError = $_.Exception.Message
				try { Invoke-GuiDeploymentMediaDismountImage -MountPath $bootMountPath -Mode Discard -TimeoutSeconds 1800 -CancellationState $null -Telemetry $Telemetry -Cleanup }
				catch
				{
					$cleanupError = $_.Exception.Message
					try { Invoke-GuiDeploymentMediaEmergencyDismCleanup -CancellationState $null -Telemetry $Telemetry }
					catch { throw ('Boot image driver injection failed: {0} Cleanup failed: {1}; emergency cleanup failed: {2}' -f $originalError, $cleanupError, $_.Exception.Message) }
					throw ('Boot image driver injection failed: {0} Cleanup failed: {1}' -f $originalError, $cleanupError)
				}
				throw ('Boot image driver injection failed: {0}' -f $originalError)
			}
		}
	}
}

function Get-GuiDeploymentMediaSelectedTweaksForSetup
{
	[CmdletBinding()]
	[OutputType([object[]])]
	param ()

	if (-not (Get-Command -Name 'Get-SelectedTweakRunList' -CommandType Function -ErrorAction SilentlyContinue))
	{
		throw 'Get-SelectedTweakRunList is required to stage selected Baseline setup customizations.'
	}

	$selectedTweaks = @(Get-SelectedTweakRunList -TweakManifest $Script:TweakManifest -Controls $Script:Controls)
	if ($selectedTweaks.Count -lt 1)
	{
		throw 'Baseline setup customizations were requested, but no GUI tweaks are selected.'
	}

	return $selectedTweaks
}

function Invoke-GuiDeploymentMediaBuild
{
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan,
		[scriptblock]$ProgressCallback,
		[AllowNull()]
		[object[]]$SelectedTweaks = $null,
		[AllowNull()]
		[hashtable]$CancellationState,
		[ValidateRange(1, 86400)]
		[int]$GlobalTimeoutSeconds = 28800
	)

	if (-not $CancellationState)
	{
		$CancellationState = New-GuiDeploymentMediaCancellationState
	}
	$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name 'Assert-GuiDeploymentMediaNotCancelled'
	& $assertNotCancelled -CancellationState $CancellationState -Stage 'Deployment media build'

	if (-not [bool]$Plan.IsValid)
	{
		throw 'Deployment media build plan has blocking validation errors.'
	}

	$validatedPlan = New-GuiDeploymentMediaBuildPlan -SourceIso ([string]$Plan.SourceIso) -WorkingDirectory ([string]$Plan.WorkingDirectory) -EditionIndex ([int]$Plan.EditionIndex) -EditionName ([string]$Plan.EditionName) -AutounattendPath ([string]$Plan.AutounattendPath) -DriverSource ([string]$Plan.DriverSource) -UsbTargetRoot ([string]$Plan.UsbTargetRoot) -IsoImageInfo $Plan.IsoImageInfo -OutputMode ([string]$Plan.OutputMode) -InjectBootDrivers:([bool]$Plan.InjectBootDrivers) -IncludeBaselineTweaks:([bool]$Plan.IncludeBaselineTweaks)
	if (-not [bool]$validatedPlan.IsValid)
	{
		throw ('Deployment media build plan failed final validation: {0}' -f (@($validatedPlan.Errors) -join '; '))
	}
	$Plan = $validatedPlan

	$startedUtc = [DateTime]::UtcNow
	$buildRoot = Join-Path ([string]$Plan.WorkingDirectory) ('Build-{0}' -f $startedUtc.ToString('yyyyMMdd-HHmmss'))
	$mediaRoot = Join-Path $buildRoot 'Media'
	$mountRoot = Join-Path $buildRoot 'Mount'
	[void][System.IO.Directory]::CreateDirectory($mediaRoot)
	[void][System.IO.Directory]::CreateDirectory($mountRoot)
	$telemetry = New-GuiDeploymentMediaBuildTelemetry -Plan $Plan -BuildRoot $buildRoot -MediaRoot $mediaRoot -MountRoot $mountRoot -GlobalTimeoutSeconds $GlobalTimeoutSeconds

	$diskImage = $null
	$primaryError = $null
	$cleanupError = $null
	$outputPath = $null

	try
	{
		Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message 'Mounting source ISO read-only.'
		$mountTimeoutSeconds = Get-GuiDeploymentMediaStageTimeoutSeconds -OperationStartedUtc $startedUtc -GlobalTimeoutSeconds $GlobalTimeoutSeconds -StageTimeoutSeconds 300
		$diskImage = $true
		$mountInfo = Invoke-GuiDeploymentMediaPowerShellStage -Name 'Mount source ISO' -ScriptBlock {
			param ([string]$SourceIso)
			$mountedImage = Mount-DiskImage -ImagePath $SourceIso -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
			$volume = $mountedImage | Get-Volume -ErrorAction Stop | Select-Object -First 1
			if (-not $volume -or [string]::IsNullOrWhiteSpace([string]$volume.DriveLetter))
			{
				throw 'Mounted ISO did not expose a drive letter.'
			}
			[pscustomobject]@{
				DriveLetter = [string]$volume.DriveLetter
			}
		} -ArgumentList @([string]$Plan.SourceIso) -TimeoutSeconds $mountTimeoutSeconds -CancellationState $CancellationState -Telemetry $telemetry
		$isoRoot = ('{0}:\' -f $mountInfo.DriveLetter)
		Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Copying ISO contents from {0} to {1}.' -f $isoRoot, $mediaRoot)
		& $assertNotCancelled -CancellationState $CancellationState -Stage 'Copy source ISO contents'
		Invoke-GuiDeploymentMediaRobocopy -Source $isoRoot -Destination $mediaRoot -CancellationState $CancellationState -Telemetry $telemetry -ProgressCallback $ProgressCallback -Operation 'Copying ISO contents'
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.Execution.Invoke-GuiDeploymentMediaBuild:catch869' -Severity Debug }

		$primaryError = $_
	}
	finally
	{
		if ($diskImage)
		{
			try { Invoke-GuiDeploymentMediaIsoDismountCleanup -ImagePath ([string]$Plan.SourceIso) -CancellationState $CancellationState -Telemetry $telemetry }
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilder.Execution.Invoke-GuiDeploymentMediaBuild:catch878' -Severity Debug }
			 $cleanupError = $_ }
		}
	}

	if ($cleanupError -and $primaryError)
	{
		throw ('Deployment media source ISO cleanup failed after source copy error. Source error: {0} Cleanup error: {1}' -f $primaryError.Exception.Message, $cleanupError.Exception.Message)
	}
	if ($cleanupError)
	{
		throw ('Failed to cleanup mounted ISO: {0}' -f $cleanupError.Exception.Message)
	}
	if ($primaryError)
	{
		throw $primaryError
	}

	& $assertNotCancelled -CancellationState $CancellationState -Stage 'Prepare deployment media'
	$installImagePath = Get-GuiDeploymentMediaPreparedInstallImagePath -MediaRoot $mediaRoot
	Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Prepared install image: {0}.' -f $installImagePath)

	if (-not [string]::IsNullOrWhiteSpace([string]$Plan.AutounattendPath))
	{
		& $assertNotCancelled -CancellationState $CancellationState -Stage 'Stage autounattend.xml'
		$answerDestination = Join-Path $mediaRoot 'autounattend.xml'
		Copy-Item -LiteralPath ([string]$Plan.AutounattendPath) -Destination $answerDestination -Force -ErrorAction Stop
		Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Staged autounattend.xml at {0}.' -f $answerDestination)
	}

	if ([bool]$Plan.IncludeBaselineTweaks)
	{
		& $assertNotCancelled -CancellationState $CancellationState -Stage 'Stage Baseline setup customizations'
		$selectedTweaks = if ($null -ne $SelectedTweaks) { @($SelectedTweaks) } else { @(Get-GuiDeploymentMediaSelectedTweaksForSetup) }
		if ($selectedTweaks.Count -lt 1)
		{
			throw 'Baseline setup customizations were requested, but no GUI tweaks are selected.'
		}

		$setupScriptsDirectory = Join-Path $mediaRoot 'sources\$OEM$\$$\Setup\Scripts'
		[void][System.IO.Directory]::CreateDirectory($setupScriptsDirectory)
		$setupPlanPath = Join-Path $setupScriptsDirectory 'Baseline-DeploymentPlan.json'
		$setupPlan = [pscustomobject]@{
			CreatedUtc = [DateTime]::UtcNow
			Source = 'Baseline Deployment Media Builder'
			SelectedTweaks = @($selectedTweaks)
		}
		[System.IO.File]::WriteAllText($setupPlanPath, ($setupPlan | ConvertTo-Json -Depth 12), [System.Text.Encoding]::UTF8)
		Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Staged selected Baseline setup customization plan at {0}.' -f $setupPlanPath)
	}

	Invoke-GuiDeploymentMediaDriverInjection -Plan $Plan -MediaRoot $mediaRoot -MountRoot $mountRoot -ProgressCallback $ProgressCallback -CancellationState $CancellationState -Telemetry $telemetry

	switch ([string]$Plan.OutputMode)
	{
		'Export Working Folder Only'
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage 'Export working folder'
			$outputPath = $mediaRoot
		}
		'Create ISO'
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage 'Create ISO output'
			Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message 'Resolving Microsoft OSCDIMG tool.'
			$dependencyTimeoutSeconds = Get-GuiDeploymentMediaStageTimeoutSeconds -OperationStartedUtc $startedUtc -GlobalTimeoutSeconds $GlobalTimeoutSeconds -StageTimeoutSeconds 1800
			$oscdimgPath = Resolve-GuiDeploymentMediaOscdimgPath -InstallIfMissing -ProgressCallback $ProgressCallback -CancellationState $CancellationState -Telemetry $telemetry -TimeoutSeconds $dependencyTimeoutSeconds
			$etfsbootPath = Join-Path $mediaRoot 'boot\etfsboot.com'
			$efisysPath = Join-Path $mediaRoot 'efi\microsoft\boot\efisys.bin'
			if (-not (Test-Path -LiteralPath $etfsbootPath -PathType Leaf))
			{
				throw ('BIOS boot sector file is missing: {0}' -f $etfsbootPath)
			}
			if (-not (Test-Path -LiteralPath $efisysPath -PathType Leaf))
			{
				throw ('UEFI boot sector file is missing: {0}' -f $efisysPath)
			}
			$outputPath = Join-Path ([string]$Plan.WorkingDirectory) ('Baseline-DeploymentMedia-{0}.iso' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')))
			$bootData = '-bootdata:2#p0,e,b{0}#pEF,e,b{1}' -f $etfsbootPath, $efisysPath
			$arguments = @('-m', '-o', '-u2', '-udfver102', $bootData, $mediaRoot, $outputPath)
			Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Creating ISO at {0}.' -f $outputPath)
			$oscdimgTimeoutSeconds = Get-GuiDeploymentMediaStageTimeoutSeconds -OperationStartedUtc $startedUtc -GlobalTimeoutSeconds $GlobalTimeoutSeconds -StageTimeoutSeconds 7200
			$null = Invoke-GuiDeploymentMediaProcess -FilePath $oscdimgPath -ArgumentList $arguments -TimeoutSeconds $oscdimgTimeoutSeconds -AllowedExitCodes @(0) -CancellationState $CancellationState -StageName 'Create ISO image' -Telemetry $telemetry
			if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf))
			{
				throw ('oscdimg.exe completed but ISO output was not created: {0}' -f $outputPath)
			}
		}
		'Create USB'
		{
			& $assertNotCancelled -CancellationState $CancellationState -Stage 'Create USB output'
			$targetRoot = [System.IO.Path]::GetFullPath([string]$Plan.UsbTargetRoot)
			$bootsectPath = Join-Path $mediaRoot 'boot\bootsect.exe'
			if (-not (Test-Path -LiteralPath $bootsectPath -PathType Leaf))
			{
				throw ('USB boot sector tool is missing from prepared media: {0}' -f $bootsectPath)
			}
			Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Copying prepared media to USB target {0}.' -f $targetRoot)
			Invoke-GuiDeploymentMediaRobocopy -Source $mediaRoot -Destination $targetRoot -CancellationState $CancellationState -Telemetry $telemetry -ProgressCallback $ProgressCallback -Operation 'Copying prepared media to USB target'
			$driveArgument = [System.IO.Path]::GetPathRoot($targetRoot).TrimEnd('\')
			$null = Invoke-GuiDeploymentMediaProcess -FilePath $bootsectPath -ArgumentList @('/nt60', $driveArgument, '/force') -TimeoutSeconds 300 -AllowedExitCodes @(0) -CancellationState $CancellationState -StageName 'Write USB boot sector' -Telemetry $telemetry
			$outputPath = $targetRoot
			$targetInstallImage = Join-Path $targetRoot ('sources\{0}' -f [System.IO.Path]::GetFileName($installImagePath))
			if (-not (Test-Path -LiteralPath $targetInstallImage -PathType Leaf))
			{
				throw ('USB copy completed but install image was not present at {0}.' -f $targetInstallImage)
			}
		}
		default
		{
			throw ('Unsupported deployment media output mode: {0}' -f $Plan.OutputMode)
		}
	}

	$result = [pscustomobject]@{
		StartedUtc = $startedUtc
		CompletedUtc = [DateTime]::UtcNow
		OutputMode = [string]$Plan.OutputMode
		BuildRoot = $buildRoot
		MediaRoot = $mediaRoot
		OutputPath = $outputPath
		ReportPath = $null
		Telemetry = $telemetry
	}
	$result.ReportPath = Save-GuiDeploymentMediaBuildReport -Plan $Plan -BuildResult $result
	Write-GuiDeploymentMediaBuildStatus -ProgressCallback $ProgressCallback -Message ('Deployment media build completed. Report: {0}.' -f $result.ReportPath)
	return $result
}

function Save-GuiDeploymentMediaBuildReport
{
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Plan,
		[object]$BuildResult = $null
	)

	if (-not [bool]$Plan.IsValid)
	{
		throw 'Deployment media build plan has blocking validation errors.'
	}

	$reportDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Baseline\DeploymentMediaBuilder\Reports'
	[void][System.IO.Directory]::CreateDirectory($reportDirectory)
	$reportPath = Join-Path $reportDirectory ('BuildPlan-{0}.json' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')))
	$report = [pscustomobject]@{
		ReportType = 'DeploymentMediaBuildReport'
		GeneratedUtc = [DateTime]::UtcNow
		Plan = $Plan
		BuildResult = $BuildResult
	}
	$json = $report | ConvertTo-Json -Depth 12
	[System.IO.File]::WriteAllText($reportPath, $json, [System.Text.Encoding]::UTF8)
	return $reportPath
}

