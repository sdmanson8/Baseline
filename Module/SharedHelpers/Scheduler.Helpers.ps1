# Internal scheduler helpers for Baseline.
# Provides Windows Task Scheduler integration for running Baseline profiles
# on a schedule (compliance checks or apply operations).

<#
    .SYNOPSIS
#>

function Register-BaselineScheduledTask
{
	<#
		.SYNOPSIS
		Registers a Windows Task Scheduler task that runs Baseline on a schedule.

		.DESCRIPTION
		Creates a scheduled task under the Baseline\ task folder that executes
		Bootstrap\Baseline.ps1 with the specified profile and action on the given schedule.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$TaskName,

		[Parameter(Mandatory)]
		[string]$ProfilePath,

		[Parameter(Mandatory)]
		[ValidateSet('Daily', 'Weekly', 'Monthly', 'Hourly')]
		[string]$Schedule,

		[string]$Time = '03:00',

		[ValidateSet('ComplianceCheck', 'Apply')]
		[string]$Action = 'ComplianceCheck',

		[string]$Description
	)

	# Resolve the full path to the relocated entry script relative to the repo root.
	$baselineScript = Join-Path $Script:SharedHelpersRepoRoot 'Bootstrap/Baseline.ps1'
	if (-not (Test-Path -LiteralPath $baselineScript))
	{
		throw "Bootstrap\Baseline.ps1 not found at expected path: $baselineScript"
	}

	# Resolve ProfilePath to an absolute path.
	$resolvedProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath)
	if (-not (Test-Path -LiteralPath $resolvedProfilePath))
	{
		throw "Profile file not found: $resolvedProfilePath"
	}

	# Build the PowerShell arguments based on the action.
	if ($Action -eq 'ComplianceCheck')
	{
		# ExecutionPolicy Bypass: required for scheduled task PowerShell execution
		$psArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$baselineScript`" -ScheduledRun -ComplianceCheck -ProfilePath `"$resolvedProfilePath`""
	}
	else
	{
		# Apply mode: run as a scheduled run with the profile path.
		# ExecutionPolicy Bypass: required for scheduled task PowerShell execution
		$psArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$baselineScript`" -ScheduledRun -ComplianceCheck -ProfilePath `"$resolvedProfilePath`""
	}

	# Create the scheduled task action.
	$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArguments

	# Parse the time string into hours and minutes.
	$timeParts = $Time -split ':'
	$hour = [int]$timeParts[0]
	$minute = if ($timeParts.Count -gt 1) { [int]$timeParts[1] } else { 0 }
	$triggerTime = [datetime]::Today.AddHours($hour).AddMinutes($minute)

	# Create the trigger based on the schedule type.
	$taskTrigger = switch ($Schedule)
	{
		'Hourly'
		{
			# PowerShell's New-ScheduledTaskTrigger does not have a direct -Hourly
			# option. Use a daily trigger with a 1-hour repetition interval.
			$t = New-ScheduledTaskTrigger -Once -At $triggerTime -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
			$t
			break
		}
		'Daily'
		{
			New-ScheduledTaskTrigger -Daily -At $triggerTime
			break
		}
		'Weekly'
		{
			New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $triggerTime
			break
		}
		'Monthly'
		{
			# Monthly is not directly supported by New-ScheduledTaskTrigger.
			# Use a daily trigger that runs every 30 days via repetition.
			$t = New-ScheduledTaskTrigger -Once -At $triggerTime -RepetitionInterval (New-TimeSpan -Days 30) -RepetitionDuration (New-TimeSpan -Days 3650)
			$t
			break
		}
	}

	# Task settings: run even on battery, start when available if missed.
	$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
	$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -RunLevel Highest -LogonType ServiceAccount

	# Build the description if not provided.
	if ([string]::IsNullOrWhiteSpace($Description))
	{
		$Description = "Baseline $Action - Profile: $(Split-Path $resolvedProfilePath -Leaf) - Schedule: $Schedule at $Time"
	}

	$fullTaskName = "Baseline\$TaskName"

	# Unregister any existing task with the same name.
	$existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -ErrorAction SilentlyContinue
	if ($existingTask)
	{
		Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Confirm:$false
	}

	# Register the scheduled task.
	Register-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Description $Description

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Registered scheduled task '$fullTaskName' ($Schedule at $Time, Action=$Action)"
	}
}

<#
    .SYNOPSIS
#>

function Register-BaselineWindowsUpdateScheduledRun
{
	<#
		.SYNOPSIS
		Registers a scheduled Baseline Windows Update security install run.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[string]$TaskName = 'WindowsSecurityUpdates',

		[Parameter(Mandatory)]
		[ValidateSet('Daily', 'Weekly', 'Monthly', 'Hourly')]
		[string]$Schedule,

		[string]$Time = '03:00',

		[string]$Description
	)

	$sharedHelpersPath = Join-Path $Script:SharedHelpersRepoRoot 'Module/SharedHelpers.psm1'
	if (-not (Test-Path -LiteralPath $sharedHelpersPath))
	{
		throw "Module\SharedHelpers.psm1 not found at expected path: $sharedHelpersPath"
	}

	$escapedSharedHelpersPath = $sharedHelpersPath.Replace("'", "''")
$scheduledCommand = "Import-Module '$escapedSharedHelpersPath' -Force -DisableNameChecking -WarningAction SilentlyContinue; Invoke-BaselineWindowsUpdateScheduledRun"
	$scheduledScriptDirectory = Join-Path $env:ProgramData 'Baseline'
	$scheduledScriptPath = Join-Path $scheduledScriptDirectory "$TaskName.ps1"
	New-Item -Path $scheduledScriptDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
	Set-Content -LiteralPath $scheduledScriptPath -Value $scheduledCommand -Encoding UTF8 -Force -ErrorAction Stop
	$psArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scheduledScriptPath`""
	$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArguments

	$timeParts = $Time -split ':'
	$hour = [int]$timeParts[0]
	$minute = if ($timeParts.Count -gt 1) { [int]$timeParts[1] } else { 0 }
	$triggerTime = [datetime]::Today.AddHours($hour).AddMinutes($minute)

	$taskTrigger = switch ($Schedule)
	{
		'Hourly'
		{
			$t = New-ScheduledTaskTrigger -Once -At $triggerTime -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
			$t
			break
		}
		'Daily'
		{
			New-ScheduledTaskTrigger -Daily -At $triggerTime
			break
		}
		'Weekly'
		{
			New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $triggerTime
			break
		}
		'Monthly'
		{
			$t = New-ScheduledTaskTrigger -Once -At $triggerTime -RepetitionInterval (New-TimeSpan -Days 30) -RepetitionDuration (New-TimeSpan -Days 3650)
			$t
			break
		}
	}

	$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
	$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -RunLevel Highest -LogonType ServiceAccount

	if ([string]::IsNullOrWhiteSpace($Description))
	{
		$Description = "Baseline Windows Update security install - Schedule: $Schedule at $Time"
	}

	$existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -ErrorAction SilentlyContinue
	if ($existingTask)
	{
		Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Confirm:$false
	}

	Register-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Description $Description

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Registered scheduled Windows Update security install task 'Baseline\$TaskName' ($Schedule at $Time)"
	}
}

<#
    .SYNOPSIS
#>

function Unregister-BaselineScheduledTask
{
	<#
		.SYNOPSIS
		Removes a previously registered Baseline scheduled task.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$TaskName
	)

	$existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -ErrorAction SilentlyContinue
	if (-not $existingTask)
	{
		throw "Scheduled task 'Baseline\$TaskName' not found."
	}

	Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Confirm:$false

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Removed scheduled task 'Baseline\$TaskName'"
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineScheduledTasks
{
	<#
		.SYNOPSIS
		Returns all Baseline scheduled tasks registered under the Baseline\ task folder.

		.OUTPUTS
		Array of objects with TaskName, State, NextRunTime, LastRunTime, LastTaskResult, Description.
		Returns an empty array if no tasks are found.
	#>
	[CmdletBinding()]
	param ()

	$tasks = Get-ScheduledTask -TaskPath '\Baseline\' -ErrorAction SilentlyContinue
	if (-not $tasks)
	{
		return @()
	}

	$results = [System.Collections.Generic.List[object]]::new()

	foreach ($task in @($tasks))
	{
		$taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath '\Baseline\' -ErrorAction SilentlyContinue

		$results.Add([pscustomobject]@{
			TaskName       = $task.TaskName
			State          = [string]$task.State
			NextRunTime    = if ($taskInfo) { $taskInfo.NextRunTime } else { $null }
			LastRunTime    = if ($taskInfo) { $taskInfo.LastRunTime } else { $null }
			LastTaskResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
			Description    = $task.Description
		})
	}

	return @($results)
}

<#
    .SYNOPSIS
#>

function Test-BaselineScheduledTaskExists
{
	<#
		.SYNOPSIS
		Tests whether a Baseline scheduled task with the given name exists.

		.OUTPUTS
		$true if the task exists, $false otherwise.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$TaskName
	)

	$task = Get-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -ErrorAction SilentlyContinue
	return ($null -ne $task)
}
