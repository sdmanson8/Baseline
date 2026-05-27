# Removal-script persistence helpers.
#
# Removal persistence flow:
# Baseline saves uninstall scripts under ProgramData\Scripts\<Name>.ps1 and
# registers a SYSTEM-context scheduled task under \<Name> that fires on logon
# or startup. When Windows feature updates re-add removed apps, the next user
# logon or system boot re-runs the saved removal script automatically.
#
# Baseline currently removes apps once via UWPApps / Applications regions; the
# Users should rerun Baseline after every feature update. This helper module
# ships the back-end persistence primitive -- script disk-write + task
# registration / unregistration / enumeration. Wiring it into removal
# regions (the "Persist removal" toggle UX) is a separate slice.

function Get-BaselineRemovalScriptDirectory
{
	<#
		.SYNOPSIS
		Returns the canonical directory where Baseline persists removal scripts.

		.DESCRIPTION
		Defaults to `$env:ProgramData\Baseline\RemovalScripts`. Honours an
		override via the `BASELINE_REMOVAL_SCRIPT_DIR` environment variable so
		tests and unattended harnesses can redirect to a sandbox path without
		touching ProgramData.

		.OUTPUTS
		[string] absolute directory path. The directory is not created here --
		callers that need it created use Save-BaselineRemovalScript, which
		creates it on demand.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_REMOVAL_SCRIPT_DIR
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override
	}

	$programData = $env:ProgramData
	if ([string]::IsNullOrWhiteSpace($programData))
	{
		# Last-resort fallback for unusual environments where ProgramData isn't
		# set (locked-down service contexts, broken images). Mirror the Windows
		# default rather than throwing -- the caller will get a useful path.
		$programData = 'C:\ProgramData'
	}

	return (Join-Path -Path $programData -ChildPath 'Baseline\RemovalScripts')
}

function Test-BaselineRemovalPersistenceEntryName
{
	<#
		.SYNOPSIS
		Validates a removal-persistence entry name against allowed characters.

		.DESCRIPTION
		Entry names become both a file name (`<Name>.ps1`) and a Task Scheduler
		task name. Both surfaces reject path separators, drive letters, and
		several reserved characters. Restrict to ASCII letters, digits,
		hyphen, underscore, and dot, with a max length of 64. This is the
		same shape used for its bloat-removal / edge-removal /
		OneDriveRemoval names and matches what `Register-ScheduledTask`
		accepts for `-TaskName`.

		.OUTPUTS
		[bool] $true if the name is valid, $false otherwise.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Name
	)

	if ([string]::IsNullOrWhiteSpace($Name))
	{
		return $false
	}

	if ($Name.Length -gt 64)
	{
		return $false
	}

	return ($Name -match '^[A-Za-z0-9_.\-]+$')
}

function Save-BaselineRemovalScript
{
	<#
		.SYNOPSIS
		Writes a persisted removal script to disk under the Baseline removal
		scripts directory.

		.DESCRIPTION
		Creates the parent directory if missing and writes `<Name>.ps1` to it.
		Content is written as UTF-8 with BOM and CRLF line endings, which is
		what powershell.exe (Windows PowerShell 5.1) expects without
		surprises. The Baseline header comment is prepended so future readers
		know the file is generated and the regenerator name.

		If a script with the same name already exists, it is overwritten -- the
		generator is the source of truth, and removal flows are re-emitted on
		every "persist" toggle.

		.OUTPUTS
		[string] full path to the written file.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[string]$ScriptBody,

		[string]$Description
	)

	if (-not (Test-BaselineRemovalPersistenceEntryName -Name $Name))
	{
		throw "Invalid removal persistence entry name: '$Name'. Must be 1-64 characters, ASCII letters / digits / dot / hyphen / underscore."
	}

	$directory = Get-BaselineRemovalScriptDirectory
	$scriptPath = Join-Path -Path $directory -ChildPath ("{0}.ps1" -f $Name)

	if (-not $PSCmdlet.ShouldProcess($scriptPath, 'Write removal persistence script'))
	{
		return $scriptPath
	}

	if (-not (Test-Path -LiteralPath $directory))
	{
		New-Item -ItemType Directory -Path $directory -Force | Out-Null
	}

	$header = @(
		'# This script is maintained by the Baseline removal persistence helper.'
		"# Entry name: $Name"
		"# Generated: $([System.DateTime]::UtcNow.ToString('o'))"
		'# Do not edit by hand. It is recreated whenever the persistence toggle fires.'
	)

	if (-not [string]::IsNullOrWhiteSpace($Description))
	{
		$header += "# Description: $Description"
	}

	$header += ''
	$header += $ScriptBody

	$payload = ($header -join "`r`n")

	# Use [System.IO.File] rather than Set-Content / Out-File -- the latter
	# pair pulls the host's current encoding (which on PS 5.1 defaults to
	# the OEM page on some locales) and silently writes mojibake. UTF-8 with
	# BOM keeps powershell.exe happy across locales without stream pipeline
	# munging from Add-Content / Set-Content providers.
	$utf8WithBom = [System.Text.UTF8Encoding]::new($true)
	[System.IO.File]::WriteAllText($scriptPath, $payload, $utf8WithBom)

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Saved removal persistence script: $scriptPath"
	}

	return $scriptPath
}

function Register-BaselineRemovalPersistenceTask
{
	<#
		.SYNOPSIS
		Registers a Task Scheduler task that re-runs a saved removal script on
		logon and / or startup.

		.DESCRIPTION
		Creates the task under `\Baseline\Persistence\<Name>` running as
		`NT AUTHORITY\SYSTEM` with `RunLevel = Highest`. Trigger choice follows
		the same task layout: bloatware removal usually runs `AtLogon`
		(re-applies after the per-user re-provisioning that follows feature
		updates), kernel-level rip-and-replace such as Edge runs `AtStartup`.
		Both can be combined when desired.

		The task replaces any prior task with the same name so re-saving is
		idempotent. Unregister-BaselineRemovalPersistenceTask is the inverse.

		.OUTPUTS
		[string] full task path (e.g. `\Baseline\Persistence\BloatRemoval`).
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[string]$ScriptPath,

		[ValidateSet('Logon', 'Startup', 'Both')]
		[string]$Trigger = 'Logon',

		[string]$Description
	)

	if (-not (Test-BaselineRemovalPersistenceEntryName -Name $Name))
	{
		throw "Invalid removal persistence entry name: '$Name'. Must be 1-64 characters, ASCII letters / digits / dot / hyphen / underscore."
	}

	if (-not (Test-Path -LiteralPath $ScriptPath))
	{
		throw "Removal persistence script not found: $ScriptPath"
	}

	$taskPath = '\Baseline\Persistence\'
	$fullName = "$taskPath$Name"

	if (-not $PSCmdlet.ShouldProcess($fullName, 'Register removal persistence scheduled task'))
	{
		return $fullName
	}

	$psArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
	$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArguments

	$triggers = [System.Collections.Generic.List[object]]::new()
	if ($Trigger -eq 'Logon' -or $Trigger -eq 'Both')
	{
		$triggers.Add((New-ScheduledTaskTrigger -AtLogon))
	}
	if ($Trigger -eq 'Startup' -or $Trigger -eq 'Both')
	{
		$triggers.Add((New-ScheduledTaskTrigger -AtStartup))
	}

	$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

	# ExecutionTimeLimit (New-TimeSpan 0) → unlimited. Matches the original:
	# AppX cleanup after a Windows feature update can take many minutes.
	$settings = New-ScheduledTaskSettingsSet `
		-AllowStartIfOnBatteries `
		-DontStopIfGoingOnBatteries `
		-StartWhenAvailable `
		-ExecutionTimeLimit (New-TimeSpan -Seconds 0)

	$resolvedDescription = if ([string]::IsNullOrWhiteSpace($Description))
	{
		"Baseline removal persistence for '$Name' -- re-runs after feature updates re-add the removed components."
	}
	else
	{
		$Description
	}

	$existing = Get-ScheduledTask -TaskName $Name -TaskPath $taskPath -ErrorAction SilentlyContinue
	if ($existing)
	{
		Unregister-ScheduledTask -TaskName $Name -TaskPath $taskPath -Confirm:$false
	}

	Register-ScheduledTask `
		-TaskName $Name `
		-TaskPath $taskPath `
		-Action $action `
		-Trigger $triggers.ToArray() `
		-Principal $principal `
		-Settings $settings `
		-Description $resolvedDescription | Out-Null

	$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
	if ($logInfoCmd)
	{
		LogInfo "Registered removal persistence task: $fullName ($Trigger)"
	}

	return $fullName
}

function Unregister-BaselineRemovalPersistenceTask
{
	<#
		.SYNOPSIS
		Removes a removal-persistence scheduled task and (optionally) the
		associated saved script.

		.DESCRIPTION
		Removes `\Baseline\Persistence\<Name>`. When `-RemoveScript` is set,
		the corresponding `<Name>.ps1` under the removal scripts directory
		is deleted as well. Returns silently when the task does not exist --
		this is the inverse of an idempotent register.

		.OUTPUTS
		[bool] $true if the task existed and was removed; $false if no task
		with that name was registered.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[string]$Name,

		[switch]$RemoveScript
	)

	if (-not (Test-BaselineRemovalPersistenceEntryName -Name $Name))
	{
		throw "Invalid removal persistence entry name: '$Name'. Must be 1-64 characters, ASCII letters / digits / dot / hyphen / underscore."
	}

	$taskPath = '\Baseline\Persistence\'
	$fullName = "$taskPath$Name"
	$removed = $false

	$existing = Get-ScheduledTask -TaskName $Name -TaskPath $taskPath -ErrorAction SilentlyContinue
	if ($existing)
	{
		if ($PSCmdlet.ShouldProcess($fullName, 'Unregister removal persistence scheduled task'))
		{
			Unregister-ScheduledTask -TaskName $Name -TaskPath $taskPath -Confirm:$false
			$removed = $true

			$logInfoCmd = Get-Command -Name 'LogInfo' -CommandType Function -ErrorAction SilentlyContinue
			if ($logInfoCmd)
			{
				LogInfo "Removed removal persistence task: $fullName"
			}
		}
	}

	if ($RemoveScript)
	{
		$directory = Get-BaselineRemovalScriptDirectory
		$scriptPath = Join-Path -Path $directory -ChildPath ("{0}.ps1" -f $Name)
		if (Test-Path -LiteralPath $scriptPath)
		{
			if ($PSCmdlet.ShouldProcess($scriptPath, 'Remove persisted removal script'))
			{
				Remove-Item -LiteralPath $scriptPath -Force
			}
		}
	}

	return $removed
}

function Get-BaselineRemovalPersistenceTasks
{
	<#
		.SYNOPSIS
		Lists removal-persistence scheduled tasks registered under
		`\Baseline\Persistence\`.

		.DESCRIPTION
		Returns an array of pscustomobjects with task metadata plus the
		resolved script path (which may not exist on disk if the user
		manually deleted it). Returns an empty array when no persistence
		tasks are registered.

		.OUTPUTS
		[object[]] one entry per registered task, with fields TaskName,
		FullName, State, ScriptPath, ScriptExists, Description.
	#>
	[CmdletBinding()]
	param ()

	$taskPath = '\Baseline\Persistence\'
	$tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
	if (-not $tasks)
	{
		return @()
	}

	$directory = Get-BaselineRemovalScriptDirectory
	$results = [System.Collections.Generic.List[object]]::new()

	foreach ($task in @($tasks))
	{
		$scriptPath = Join-Path -Path $directory -ChildPath ("{0}.ps1" -f $task.TaskName)
		$results.Add([pscustomobject]@{
			TaskName     = $task.TaskName
			FullName     = "$taskPath$($task.TaskName)"
			State        = [string]$task.State
			ScriptPath   = $scriptPath
			ScriptExists = (Test-Path -LiteralPath $scriptPath)
			Description  = $task.Description
		})
	}

	return @($results)
}

function Test-BaselineRemovalPersistenceTaskExists
{
	<#
		.SYNOPSIS
		Tests whether a removal-persistence scheduled task with the given
		name is registered.

		.OUTPUTS
		[bool]
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory)]
		[string]$Name
	)

	if (-not (Test-BaselineRemovalPersistenceEntryName -Name $Name))
	{
		return $false
	}

	$task = Get-ScheduledTask -TaskName $Name -TaskPath '\Baseline\Persistence\' -ErrorAction SilentlyContinue
	return ($null -ne $task)
}

