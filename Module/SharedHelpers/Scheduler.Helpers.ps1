# Scheduler helper slice for Baseline.
# Provides Windows Task Scheduler integration for running Baseline profiles
# on a schedule (compliance checks or apply operations).

function Register-BaselineScheduledTask
{
	<#
		.SYNOPSIS
		Registers a Windows Task Scheduler task that runs Baseline on a schedule.

		.DESCRIPTION
		Creates a scheduled task under the Baseline\ task folder that executes
		Baseline.ps1 with the specified profile and action on the given schedule.
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

	# Resolve the full path to Baseline.ps1 relative to the repo root.
	$baselineScript = Join-Path $Script:SharedHelpersRepoRoot 'Baseline.ps1'
	if (-not (Test-Path -LiteralPath $baselineScript))
	{
		throw "Baseline.ps1 not found at expected path: $baselineScript"
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
	Register-ScheduledTask -TaskName $TaskName -TaskPath '\Baseline\' -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Description $Description -RunLevel Highest

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Registered scheduled task '$fullTaskName' ($Schedule at $Time, Action=$Action)"
	}
}

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
