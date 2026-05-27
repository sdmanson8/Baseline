using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Maintenance scheduled-task consumers.

	.DESCRIPTION
	Restores three regressions: Windows Cleanup (cleanmgr /sagerun:1337
	with a 30-day interactive toast reminder), SoftwareDistributionTask, and
	TempTask. CleanupTask is implemented here; the other two ship in
	follow-up commits in the same cluster. Authoring follows
		the maintenance-task implementation
	`function CleanupTask` exactly, factored through Baseline's
	`Register-BaselineToastApp` and `Show-BaselineToast` helpers.

	The notification toast must render in the user session, so both the
	cleanup task and the reminder task run under a user-context principal
	(`-RunLevel Highest`). The VBS shim is preserved so wscript.exe
	can invoke powershell.exe without a console flash; the toast emission
	itself stays inline inside the generated .ps1 so the
	scheduled task survives a Baseline uninstall.
#>

$Script:BaselineMaintenanceTaskPath = 'Baseline'
$Script:BaselineMaintenanceTaskScriptDir = Join-Path $env:SystemRoot 'System32\Tasks\Baseline'
$Script:BaselineCleanupTaskName = 'Windows Cleanup'
$Script:BaselineCleanupNotificationTaskName = 'Windows Cleanup Notification'
$Script:BaselineCleanupAppId = 'Baseline'
$Script:BaselineCleanupProtocolName = 'BaselineCleanup'
$Script:BaselineSoftwareDistributionTaskName = 'SoftwareDistribution'
$Script:BaselineSoftwareDistributionScriptBase = 'SoftwareDistribution'
$Script:BaselineSoftwareDistributionDownloadPath = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
$Script:BaselineTempTaskName = 'Temp'
$Script:BaselineTempScriptBase = 'Temp'

# Published cleanup categories. StateFlags1337 is a magic preset id
# (any 4-digit number works). cleanmgr /sagerun:1337
# enacts every category whose StateFlags1337 = 2.
$Script:BaselineCleanupVolumeCaches = @(
	'BranchCache',
	'Delivery Optimization Files',
	'Device Driver Packages',
	'Language Pack',
	'Previous Installations',
	'Setup Log Files',
	'System error memory dump files',
	'System error minidump files',
	'Temporary Files',
	'Temporary Setup Files',
	'Update Cleanup',
	'Upgrade Discarded Files',
	'Windows Defender',
	'Windows ESD installation files',
	'Windows Upgrade Log Files'
)

<#
	.SYNOPSIS
	Creates baseline maintenance task scripts.

	#>

function New-BaselineMaintenanceTaskScripts
{
	<#
		.SYNOPSIS
		Writes the .ps1/.vbs script pair under
		$env:SystemRoot\System32\Tasks\Baseline for a maintenance task.

		.DESCRIPTION
		The .vbs shim is the silent-launch trick: wscript.exe invokes
		powershell.exe without surfacing a console window. The .ps1 holds
		the actual work. Folder is created if missing. Files are overwritten
		on every register call (idempotent).
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$BaseName,

		[Parameter(Mandatory)]
		[string]$PowerShellContent
	)

	if (-not (Test-Path -LiteralPath $Script:BaselineMaintenanceTaskScriptDir))
	{
		$null = New-Item -Path $Script:BaselineMaintenanceTaskScriptDir -ItemType Directory -Force
	}

	$ps1Path = Join-Path $Script:BaselineMaintenanceTaskScriptDir "$BaseName.ps1"
	$vbsPath = Join-Path $Script:BaselineMaintenanceTaskScriptDir "$BaseName.vbs"

	# Write PS1 in UTF-8 with BOM so Windows PowerShell 5.1's default reader
	# parses non-ASCII (localized toast strings) correctly.
	[System.IO.File]::WriteAllText($ps1Path, $PowerShellContent, (New-Object System.Text.UTF8Encoding($true)))

	$vbsContent = "CreateObject(""Wscript.Shell"").Run ""powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File %SystemRoot%\System32\Tasks\Baseline\$BaseName.ps1"", 0`r`n"
	# VBS must be ASCII / Default encoding for wscript.exe to parse cleanly.
	[System.IO.File]::WriteAllText($vbsPath, $vbsContent, [System.Text.Encoding]::Default)

	return [pscustomobject]@{
		Ps1Path = $ps1Path
		VbsPath = $vbsPath
	}
}

<#
	.SYNOPSIS
	Creates baseline maintenance task principal.

	#>

function New-BaselineMaintenanceTaskPrincipal
{
	<#
		.SYNOPSIS
		Returns a user-context scheduled-task principal suitable for tasks
		that must render UI (toasts) in the interactive session.

		.DESCRIPTION
		Maintenance tasks intentionally do NOT use the SYSTEM principal
		that `Scheduler.Helpers.ps1` sets, because SYSTEM-context toast
		emission does not surface in the user's Action Center. Domain
		joins cannot resolve a SID for the local user, so `$env:USERDOMAIN`
		is used as the domain qualifier when present (tracked PR workaround
		workaround).
	#>
	[CmdletBinding()]
	param ()

	if ($env:USERDOMAIN)
	{
		return New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
	}

	return New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -RunLevel Highest
}

<#
	.SYNOPSIS
	Sets baseline cleanup volume cache flags.

	#>

function Set-BaselineCleanupVolumeCacheFlags
{
	<#
		.SYNOPSIS
		Configures the VolumeCaches StateFlags1337 entries that
		cleanmgr.exe /sagerun:1337 reads.

		.DESCRIPTION
		Clears any pre-existing StateFlags1337 across all VolumeCaches keys
		(prevents lingering values from earlier registrations), then writes
		StateFlags1337 = 2 on each cache in $Script:BaselineCleanupVolumeCaches.
		A value of 2 means "selected for cleanup at the 1337 sageset profile".
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches' -ErrorAction SilentlyContinue | ForEach-Object {
		Remove-ItemProperty -Path $_.PsPath -Name 'StateFlags1337' -Force -ErrorAction SilentlyContinue
	}

	foreach ($volumeCache in $Script:BaselineCleanupVolumeCaches)
	{
		$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\$volumeCache"
		if (-not (Test-Path -Path $path))
		{
			$null = New-Item -Path $path -Force
		}
		$null = New-ItemProperty -Path $path -Name 'StateFlags1337' -PropertyType DWord -Value 2 -Force
	}
}

<#
	.SYNOPSIS
	Clears baseline cleanup volume cache flags.

	#>

function Clear-BaselineCleanupVolumeCacheFlags
{
	<#
		.SYNOPSIS
		Removes the StateFlags1337 entries written by
		Set-BaselineCleanupVolumeCacheFlags. Idempotent.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param ()

	Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches' -ErrorAction SilentlyContinue | ForEach-Object {
		Remove-ItemProperty -Path $_.PsPath -Name 'StateFlags1337' -Force -ErrorAction SilentlyContinue
	}
}

<#
	.SYNOPSIS
	Gets baseline cleanup task script.

	#>

function Get-BaselineCleanupTaskScript
{
	<#
		.SYNOPSIS
		Returns the PowerShell payload for the Windows Cleanup task.

		.DESCRIPTION
		Stops any conflicting cleanmgr/Dism processes, runs cleanmgr
		with /sagerun:1337 (the StateFlags1337 preset configured by
		Set-BaselineCleanupVolumeCacheFlags), then runs DISM
		/Cleanup-Image /StartComponentCleanup /NoRestart for component-
		store reduction. Self-contained — does not depend on Baseline
		being installed at run time.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	return @'
# Baseline maintenance task — Windows Cleanup
# Maintenance payload used by the cleanup task and kept for uninstall cleanup.
# Baseline is uninstalled. Mirrors the CleanupTask payload.

Get-Process -Name cleanmgr, Dism, DismHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$ProcessInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = "$env:SystemRoot\System32\cleanmgr.exe"
$ProcessInfo.Arguments = "/sagerun:1337"
$ProcessInfo.UseShellExecute = $true
$ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

$Process = New-Object -TypeName System.Diagnostics.Process
$Process.StartInfo = $ProcessInfo
$Process.Start() | Out-Null

Start-Sleep -Seconds 3

$ProcessInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = "$env:SystemRoot\System32\Dism.exe"
$ProcessInfo.Arguments = "/Online /English /Cleanup-Image /StartComponentCleanup /NoRestart"
$ProcessInfo.UseShellExecute = $true
$ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

$Process = New-Object -TypeName System.Diagnostics.Process
$Process.StartInfo = $ProcessInfo
$Process.Start() | Out-Null
'@
}

<#
	.SYNOPSIS
	Gets baseline cleanup notification task script.

	#>

function Get-BaselineCleanupNotificationTaskScript
{
	<#
		.SYNOPSIS
		Returns the PowerShell payload for the Windows Cleanup Notification
		task.

		.DESCRIPTION
		Emits an interactive toast (with Run + dismiss actions) that
		activates the BaselineCleanup: URL protocol when the user clicks
		Run. The toast XML construction follows the same structure as
		`New-BaselineToastXml -ActionLabel ... -ActionProtocol BaselineCleanup`
		produces; we inline it here so the scheduled task survives a
		Baseline uninstall. Localized strings are baked in at register
		time so the user sees them in their preferred language.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Title,

		[Parameter(Mandatory)]
		[string]$Body,

		[Parameter(Mandatory)]
		[string]$RunLabel,

		[string]$AppId = $Script:BaselineCleanupAppId,

		[string]$ProtocolName = $Script:BaselineCleanupProtocolName
	)

	# Build the XML through the same DOM helper used at runtime so format
	# stays in lock-step with New-BaselineToastXml. The result is injected
	# into the scheduled-task payload as a here-string literal.
	$toastXml = New-BaselineToastXml -Title $Title -Body $Body -ActionLabel $RunLabel -ActionProtocol $ProtocolName

	# Escape any single quotes that would break the here-string literal.
	$escapedXml = $toastXml -replace "'", "''"

	$payload = @"
# Baseline maintenance task — Windows Cleanup notification
# Maintenance payload used by the cleanup task and kept for uninstall cleanup.
# Baseline is uninstalled. Mirrors the CleanupTask notification payload.

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

`$ToastXmlText = @'
$escapedXml
'@

`$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
`$ToastXml.LoadXml(`$ToastXmlText)

`$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New(`$ToastXml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$AppId').Show(`$ToastMessage)
"@

	return $payload
}

<#
	.SYNOPSIS
	Registers baseline maintenance task.

	#>

function Register-BaselineMaintenanceTask
{
	<#
		.SYNOPSIS
		Registers a wscript-shim scheduled task in the \Baseline\ task path.

		.DESCRIPTION
		Common-shape task registrar for the maintenance consumers. Caller
		supplies the task name, the .vbs path that wscript.exe will run, an
		optional trigger (omit for an on-demand task), the principal
		(user-context for tasks that must render UI), and a description.
		Removes any pre-existing task with the same name first. Sets the
		`Author` property to `Baseline` so legacy tasks remain
		distinguishable in Task Scheduler.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[string]$TaskName,

		[Parameter(Mandatory)]
		[string]$VbsPath,

		[object]$Trigger,

		[Parameter(Mandatory)]
		[object]$Principal,

		[Parameter(Mandatory)]
		[string]$Description
	)

	$existing = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $TaskName -ErrorAction SilentlyContinue
	if ($existing)
	{
		Unregister-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
	}

	$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $VbsPath
	$settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable

	$registerParams = @{
		TaskName    = $TaskName
		TaskPath    = $Script:BaselineMaintenanceTaskPath
		Principal   = $Principal
		Action      = $action
		Settings    = $settings
		Description = $Description
		Force       = $true
	}
	if ($Trigger)
	{
		$registerParams['Trigger'] = $Trigger
	}

	$null = Register-ScheduledTask @registerParams

	$task = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $TaskName -ErrorAction SilentlyContinue
	if ($task)
	{
		$task.Author = 'Baseline'
		$null = $task | Set-ScheduledTask
	}
}

<#
	.SYNOPSIS
	Checks baseline maintenance tasks remaining.

	#>

function Test-BaselineMaintenanceTasksRemaining
{
	<#
		.SYNOPSIS
		Returns $true when at least one scheduled task still exists under
		the \Baseline\ task path.

		.DESCRIPTION
		The Baseline AppUserModelId is shared across maintenance tasks
		(CleanupTask, SoftwareDistributionTask, TempTask). The Delete path
		of each task uses this helper to decide whether it owns the final
		cleanup of the AppId — leaving it in place while any other Baseline
		task still needs to surface toasts.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	$remaining = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -ErrorAction SilentlyContinue
	return [bool]$remaining
}

<#
	.SYNOPSIS
	Gets baseline software distribution task script.

	#>

function Get-BaselineSoftwareDistributionTaskScript
{
	<#
		.SYNOPSIS
		Returns the PowerShell payload for the SoftwareDistribution task.

		.DESCRIPTION
		Waits up to one hour for the Windows Update service (wuauserv) to
		stop, clears every entry under
		%SystemRoot%\SoftwareDistribution\Download, then surfaces an
		information-only toast confirming the flush. Mirrors the
		SoftwareDistributionTask payload, factored through the shared
		Baseline toast XML builder for consistency. Self-contained — does
		not depend on Baseline being installed at run time.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Body,

		[string]$AppId = $Script:BaselineCleanupAppId
	)

	# Reuse the same DOM builder as the runtime toast helper so the XML
	# format stays in lock-step with New-BaselineToastXml. Information-only
	# toasts have no actions (omit ActionLabel/ActionProtocol).
	$toastXml = New-BaselineToastXml -Title 'Baseline' -Body $Body
	$escapedXml = $toastXml -replace "'", "''"
	$escapedDownloadPath = $Script:BaselineSoftwareDistributionDownloadPath -replace "'", "''"

	$payload = @"
# Baseline maintenance task — Software Distribution cache flush
# Maintenance payload used by the cleanup task and kept for uninstall cleanup.
# Baseline is uninstalled. Mirrors the SoftwareDistributionTask payload.

# Wait until the Windows Update service is stopped before clearing the
# download cache; bail out quietly if it stays busy past the one-hour
# threshold so the scheduled task does not error noisily.
try
{
	(Get-Service -Name wuauserv -ErrorAction Stop).WaitForStatus('Stopped', '01:00:00')
}
catch
{
	return
}

Get-ChildItem -Path '$escapedDownloadPath' -Recurse -Force -ErrorAction SilentlyContinue |
	Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

`$ToastXmlText = @'
$escapedXml
'@

`$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
`$ToastXml.LoadXml(`$ToastXmlText)

`$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New(`$ToastXml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$AppId').Show(`$ToastMessage)
"@

	return $payload
}

<#
	.SYNOPSIS
	Gets baseline temp task script.

	#>

function Get-BaselineTempTaskScript
{
	<#
		.SYNOPSIS
		Returns the PowerShell payload for the Temp folder cleanup task.

		.DESCRIPTION
		Removes every file under %TEMP% whose CreationTime is older than
		one day, then sweeps the well-known orphan folders the original workflow targets
		(`$WinREAgent`, `$SysReset`, `$Windows.~WS`, `$GetCurrent`, `ESD`,
		`Intel`, `PerfLogs`, the NetworkService temp folder, plus
		`Recovery` only when a stale `ReAgentOld.xml` is present). Emits an
		information-only completion toast. Self-contained — does not depend
		on Baseline being installed at run time.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory)]
		[string]$Body,

		[string]$AppId = $Script:BaselineCleanupAppId
	)

	$toastXml = New-BaselineToastXml -Title 'Baseline' -Body $Body
	$escapedXml = $toastXml -replace "'", "''"

	$payload = @"
# Baseline maintenance task — Temp folder purge
# Maintenance payload used by the cleanup task and kept for uninstall cleanup.
# Baseline is uninstalled. Mirrors the TempTask payload.

# Remove %TEMP% files older than 24h. Use -Force to include hidden items
# and -ErrorAction SilentlyContinue so a single locked file does not abort
# the sweep — the next run will catch it.
Get-ChildItem -Path `$env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
	Where-Object -FilterScript { `$_.CreationTime -lt (Get-Date).AddDays(-1) } |
	Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# The well-known orphan-folder list. Single quotes preserve the
# literal `$WinREAgent / `$SysReset / etc. names that would otherwise be
# interpreted as PowerShell variables.
`$Paths = @(
	(Join-Path `$env:SystemDrive '`$WinREAgent'),
	(Join-Path `$env:SystemDrive '`$SysReset'),
	(Join-Path `$env:SystemDrive '`$Windows.~WS'),
	(Join-Path `$env:SystemDrive '`$GetCurrent'),
	(Join-Path `$env:SystemDrive 'ESD'),
	(Join-Path `$env:SystemDrive 'Intel'),
	(Join-Path `$env:SystemDrive 'PerfLogs'),
	(Join-Path `$env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Temp')
)

# Recovery folder is only safe to clear once Windows itself has flagged
# the ReAgent state as stale (ReAgentOld.xml).
`$RecoveryDir = Join-Path `$env:SystemDrive 'Recovery'
if (Test-Path -LiteralPath `$RecoveryDir)
{
	`$reagentStale = Get-ChildItem -Path `$RecoveryDir -Force -ErrorAction SilentlyContinue |
		Where-Object -FilterScript { `$_.Name -eq 'ReAgentOld.xml' }
	if (`$reagentStale)
	{
		`$Paths += `$RecoveryDir
	}
}

foreach (`$candidate in `$Paths)
{
	if (Test-Path -LiteralPath `$candidate)
	{
		Remove-Item -LiteralPath `$candidate -Recurse -Force -ErrorAction SilentlyContinue
	}
}

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

`$ToastXmlText = @'
$escapedXml
'@

`$ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
`$ToastXml.LoadXml(`$ToastXmlText)

`$ToastMessage = [Windows.UI.Notifications.ToastNotification]::New(`$ToastXml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$AppId').Show(`$ToastMessage)
"@

	return $payload
}

<#
	.SYNOPSIS
	Runs baseline software distribution flush.

	#>

function Invoke-BaselineSoftwareDistributionFlush
{
	<#
		.SYNOPSIS
		In-process Software Distribution download cache flush.

		.DESCRIPTION
		Aggregate-cleanup variant of the SoftwareDistributionTask payload.
		Mirrors the same flush logic but runs synchronously inside the
		current PowerShell host (no scheduled task, no toast). Bails out
		quickly if the Windows Update service is busy — unlike the
		scheduled-task payload, this does not block for an hour.

		Returns a summary `[pscustomobject]` with `Cleared`,
		`SkippedReason`, and `BytesFreed` so the caller can roll an
		aggregate report.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([pscustomobject])]
	param (
		[int]$WuauservStopWaitSeconds = 5
	)

	$result = [pscustomobject]@{
		Cleared       = $false
		SkippedReason = $null
		BytesFreed    = 0L
	}

	try
	{
		$wuauserv = Get-Service -Name wuauserv -ErrorAction Stop
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.MaintenanceTasks.Invoke-BaselineSoftwareDistributionFlush:catch636' -Severity Debug }

		$result.SkippedReason = "wuauserv not present: $($_.Exception.Message)"
		return $result
	}

	if ($wuauserv.Status -ne 'Stopped')
	{
		try
		{
			$wuauserv.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($WuauservStopWaitSeconds))
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.MaintenanceTasks.Invoke-BaselineSoftwareDistributionFlush:catch648' -Severity Debug }

			$result.SkippedReason = "Windows Update service is busy (status=$($wuauserv.Status))"
			return $result
		}
	}

	if (-not (Test-Path -LiteralPath $Script:BaselineSoftwareDistributionDownloadPath))
	{
		$result.Cleared = $true
		return $result
	}

	$bytes = 0L
	try
	{
		$bytes = (Get-ChildItem -LiteralPath $Script:BaselineSoftwareDistributionDownloadPath -Recurse -Force -ErrorAction SilentlyContinue |
			Where-Object { -not $_.PSIsContainer } |
			Measure-Object -Property Length -Sum).Sum
		if ($null -eq $bytes) { $bytes = 0L }
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.MaintenanceTasks.Invoke-BaselineSoftwareDistributionFlush:catch669' -Severity Debug }

		$bytes = 0L
	}

	Get-ChildItem -LiteralPath $Script:BaselineSoftwareDistributionDownloadPath -Recurse -Force -ErrorAction SilentlyContinue |
		Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

	$result.Cleared = $true
	$result.BytesFreed = [long]$bytes
	return $result
}

<#
	.SYNOPSIS
	Gets baseline temp purge paths.

	#>

function Get-BaselineTempPurgePaths
{
	<#
		.SYNOPSIS
		Returns the literal orphan-folder list TempTask sweeps. Centralised
		here so both the scheduled-task payload and the aggregate
		`Invoke-CleanupOperation -All` walk the same set.

		.DESCRIPTION
		Excludes `%TEMP%` itself (which has its own age-filtered sweep) and
		excludes the `Recovery` folder, which only becomes safe to clear
		once `ReAgentOld.xml` is present — the caller decides when that
		gating applies.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param ()

	return @(
		(Join-Path $env:SystemDrive '$WinREAgent'),
		(Join-Path $env:SystemDrive '$SysReset'),
		(Join-Path $env:SystemDrive '$Windows.~WS'),
		(Join-Path $env:SystemDrive '$GetCurrent'),
		(Join-Path $env:SystemDrive 'ESD'),
		(Join-Path $env:SystemDrive 'Intel'),
		(Join-Path $env:SystemDrive 'PerfLogs'),
		(Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Temp')
	)
}

<#
	.SYNOPSIS
	Runs baseline temp folder purge.

	#>

function Invoke-BaselineTempFolderPurge
{
	<#
		.SYNOPSIS
		In-process original-style %TEMP% sweep plus orphan-folder cleanup.

		.DESCRIPTION
		Aggregate-cleanup variant of the TempTask payload. Removes %TEMP%
		entries older than `MinAgeDays` and walks the orphan-folder list
		from `Get-BaselineTempPurgePaths`. The Recovery folder is only
		touched when `ReAgentOld.xml` is present (matches the original gating).

		Returns a summary `[pscustomobject]` with `PathsCleared`,
		`PathsSkipped`, and `BytesFreed`.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[OutputType([pscustomobject])]
	param (
		[int]$MinAgeDays = 1,

		[switch]$IncludeRecoveryWhenStale
	)

	$cleared = 0
	$skipped = 0
	$bytesFreed = 0L

	$cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($MinAgeDays))

	if (Test-Path -LiteralPath $env:TEMP)
	{
		Get-ChildItem -LiteralPath $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
			Where-Object -FilterScript { $_.CreationTime -lt $cutoff } |
			ForEach-Object {
				try
				{
					if ($_.PSIsContainer -eq $false) { $bytesFreed += [long]$_.Length }
					Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
					$cleared++
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.MaintenanceTasks.Invoke-BaselineTempFolderPurge:catch765' -Severity Debug }

					$skipped++
				}
			}
	}

	$paths = Get-BaselineTempPurgePaths

	if ($IncludeRecoveryWhenStale)
	{
		$recoveryDir = Join-Path $env:SystemDrive 'Recovery'
		if (Test-Path -LiteralPath $recoveryDir)
		{
			$reagentStale = Get-ChildItem -LiteralPath $recoveryDir -Force -ErrorAction SilentlyContinue |
				Where-Object -FilterScript { $_.Name -eq 'ReAgentOld.xml' }
			if ($reagentStale)
			{
				$paths = @($paths) + $recoveryDir
			}
		}
	}

	foreach ($path in $paths)
	{
		if (-not (Test-Path -LiteralPath $path)) { continue }

		try
		{
			$size = (Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
				Where-Object { -not $_.PSIsContainer } |
				Measure-Object -Property Length -Sum).Sum
			if ($null -ne $size) { $bytesFreed += [long]$size }

			Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
			$cleared++
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SystemTweaks.MaintenanceTasks.Invoke-BaselineTempFolderPurge:catch802' -Severity Debug }

			$skipped++
		}
	}

	return [pscustomobject]@{
		PathsCleared = $cleared
		PathsSkipped = $skipped
		BytesFreed   = $bytesFreed
	}
}

<#
	.SYNOPSIS
	Runs cleanup task.

	#>

function CleanupTask
{
	<#
		.SYNOPSIS
		Registers (or removes) the Windows Cleanup scheduled task and its
		30-day toast reminder. Regression restored.

		.DESCRIPTION
		Manifest entry: Type=Toggle, OnParam=Register, OffParam=Delete.

		Register path:
		  - Configures VolumeCaches StateFlags1337 across 15 cleanup
		    categories.
		  - Registers the Baseline AppUserModelId and BaselineCleanup:
		    URL-protocol handler that activates the Windows Cleanup task
		    when the user clicks Run on the toast.
		  - Writes wscript-shim launchers for Windows_Cleanup.ps1 and
		    Windows_Cleanup_Notification.ps1 under
		    %SystemRoot%\System32\Tasks\Baseline\.
		  - Registers `\Baseline\Windows Cleanup` (on-demand) and
		    `\Baseline\Windows Cleanup Notification` (every 30 days at
		    9pm) scheduled tasks under a user-context principal.

		Delete path:
		  - Unregisters both scheduled tasks.
		  - Unregisters the AppUserModelId and URL-protocol handler.
		  - Removes the script artifacts.
		  - Clears the StateFlags1337 entries.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory, ParameterSetName = 'Register')]
		[switch]$Register,

		[Parameter(Mandatory, ParameterSetName = 'Delete')]
		[switch]$Delete
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		'Register'
		{
			Write-ConsoleStatus -Action 'Registering Windows Cleanup task'
			LogInfo "Registering Baseline Windows Cleanup scheduled task and 30-day toast reminder"

			Set-BaselineCleanupVolumeCacheFlags

			# Localized strings — Get-BaselineLocalizedString returns the
			# fallback when the key is missing, so the toast always renders.
			$cleanupTitle = Get-BaselineLocalizedString -Key 'CleanupTaskNotificationTitle' -Fallback 'Windows clean up'
			$cleanupBody = Get-BaselineLocalizedString -Key 'CleanupTaskNotificationEvent' -Fallback 'Run task to clean up Windows unused files and updates?'
			$runLabel = Get-BaselineLocalizedString -Key 'Run' -Fallback 'Run'
			$cleanupTaskDescription = Get-BaselineLocalizedString -Key 'CleanupTaskDescription' -Fallback 'Cleaning up Windows unused files and updates using built-in Disk cleanup app. Scheduled task can be run only if user "{0}" logged into the system.' -FormatArgs @($env:USERNAME)
			$notificationDescription = Get-BaselineLocalizedString -Key 'CleanupNotificationTaskDescription' -Fallback 'Pop-up notification reminder about cleaning up Windows unused files and updates. Scheduled task can be run only if user "{0}" logged into the system.' -FormatArgs @($env:USERNAME)

			$protocolTaskPath = "\$Script:BaselineMaintenanceTaskPath\"
			$protocolScript = "Start-ScheduledTask -TaskPath '$protocolTaskPath' -TaskName '$Script:BaselineCleanupTaskName'"
			$protocolArtifacts = New-BaselineMaintenanceTaskScripts -BaseName 'Windows_Cleanup_Protocol' -PowerShellContent $protocolScript
			$protocolCommand = ('powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden -File "{0}"' -f $protocolArtifacts.Ps1Path)

			Register-BaselineToastApp `
				-AppId $Script:BaselineCleanupAppId `
				-DisplayName $Script:BaselineCleanupAppId `
				-ProtocolName $Script:BaselineCleanupProtocolName `
				-ProtocolCommand $protocolCommand

			$cleanupArtifacts = New-BaselineMaintenanceTaskScripts -BaseName 'Windows_Cleanup' -PowerShellContent (Get-BaselineCleanupTaskScript)
			$notificationScript = Get-BaselineCleanupNotificationTaskScript -Title $cleanupTitle -Body $cleanupBody -RunLabel $runLabel
			$notificationArtifacts = New-BaselineMaintenanceTaskScripts -BaseName 'Windows_Cleanup_Notification' -PowerShellContent $notificationScript

			$principal = New-BaselineMaintenanceTaskPrincipal

			Register-BaselineMaintenanceTask `
				-TaskName $Script:BaselineCleanupTaskName `
				-VbsPath $cleanupArtifacts.VbsPath `
				-Principal $principal `
				-Description $cleanupTaskDescription

			$reminderTrigger = New-ScheduledTaskTrigger -Daily -DaysInterval 30 -At 9pm
			Register-BaselineMaintenanceTask `
				-TaskName $Script:BaselineCleanupNotificationTaskName `
				-VbsPath $notificationArtifacts.VbsPath `
				-Trigger $reminderTrigger `
				-Principal $principal `
				-Description $notificationDescription

			LogInfo "Registered '\\$Script:BaselineMaintenanceTaskPath\\$Script:BaselineCleanupTaskName' and 30-day toast reminder"
			Write-ConsoleStatus -Status success
		}

		'Delete'
		{
			Write-ConsoleStatus -Action 'Removing Windows Cleanup task'
			LogInfo "Removing Baseline Windows Cleanup scheduled task and 30-day toast reminder"

			foreach ($taskName in @($Script:BaselineCleanupTaskName, $Script:BaselineCleanupNotificationTaskName))
			{
				$existing = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $taskName -ErrorAction SilentlyContinue
				if ($existing)
				{
					Unregister-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
				}
			}

			# Always remove the URL-protocol handler — only CleanupTask owns
			# it. The AppId is shared across the maintenance tasks, so leave
			# it in place if SoftwareDistributionTask or TempTask still need
			# to surface toasts.
			if (Test-BaselineMaintenanceTasksRemaining)
			{
				$protocolKey = "Registry::HKEY_CLASSES_ROOT\$Script:BaselineCleanupProtocolName"
				if (Test-Path -Path $protocolKey)
				{
					Remove-Item -Path $protocolKey -Recurse -Force -ErrorAction SilentlyContinue
				}
			}
			else
			{
				Unregister-BaselineToastApp -AppId $Script:BaselineCleanupAppId -ProtocolName $Script:BaselineCleanupProtocolName
			}

			foreach ($baseName in @('Windows_Cleanup', 'Windows_Cleanup_Notification', 'Windows_Cleanup_Protocol'))
			{
				foreach ($ext in @('.ps1', '.vbs'))
				{
					$path = Join-Path $Script:BaselineMaintenanceTaskScriptDir "$baseName$ext"
					if (Test-Path -LiteralPath $path)
					{
						Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
					}
				}
			}

			Clear-BaselineCleanupVolumeCacheFlags

			LogInfo "Removed Baseline Windows Cleanup scheduled task and 30-day toast reminder"
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Runs software distribution task.

	#>

function SoftwareDistributionTask
{
	<#
		.SYNOPSIS
		Registers (or removes) the Baseline SoftwareDistribution scheduled
		task — a 90-day flush of the Windows Update download cache. The original
		regression restored.

		.DESCRIPTION
		Manifest entry: Type=Toggle, OnParam=Register, OffParam=Delete.

		Register path:
		  - Registers the Baseline AppUserModelId so the completion toast
		    surfaces under a recognised application identity. Idempotent
		    when CleanupTask has already registered it.
		  - Writes wscript-shim launchers for SoftwareDistribution.{ps1,vbs}
		    under %SystemRoot%\System32\Tasks\Baseline\. The .ps1 waits up
		    to one hour for wuauserv to stop, then clears every entry under
		    %SystemRoot%\SoftwareDistribution\Download and emits an
		    information-only toast.
		  - Registers `\Baseline\SoftwareDistribution` (every 90 days at
		    9pm) under a user-context principal so the toast renders in
		    the interactive session.

		Delete path:
		  - Unregisters the scheduled task and removes its script artifacts.
		  - Releases the AppUserModelId only if no other Baseline
		    maintenance task still needs it.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory, ParameterSetName = 'Register')]
		[switch]$Register,

		[Parameter(Mandatory, ParameterSetName = 'Delete')]
		[switch]$Delete
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		'Register'
		{
			Write-ConsoleStatus -Action 'Registering SoftwareDistribution flush task'
			LogInfo "Registering Baseline SoftwareDistribution scheduled task (90-day Windows Update cache flush)"

			$completionBody = Get-BaselineLocalizedString -Key 'SoftwareDistributionTaskNotificationEvent' -Fallback 'Windows update cache successfully deleted.'
			$taskDescription = Get-BaselineLocalizedString -Key 'FolderTaskDescription' -Fallback 'The {0} folder cleanup. Scheduled task can be run only if user "{1}" logged into the system.' -FormatArgs @('%SystemRoot%\SoftwareDistribution\Download', $env:USERNAME)

			# AppId only — no URL protocol because the toast is information-only.
			Register-BaselineToastApp `
				-AppId $Script:BaselineCleanupAppId `
				-DisplayName $Script:BaselineCleanupAppId

			$payload = Get-BaselineSoftwareDistributionTaskScript -Body $completionBody
			$artifacts = New-BaselineMaintenanceTaskScripts -BaseName $Script:BaselineSoftwareDistributionScriptBase -PowerShellContent $payload

			$principal = New-BaselineMaintenanceTaskPrincipal
			$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 90 -At 9pm

			Register-BaselineMaintenanceTask `
				-TaskName $Script:BaselineSoftwareDistributionTaskName `
				-VbsPath $artifacts.VbsPath `
				-Trigger $trigger `
				-Principal $principal `
				-Description $taskDescription

			LogInfo "Registered '\\$Script:BaselineMaintenanceTaskPath\\$Script:BaselineSoftwareDistributionTaskName' (every 90 days)"
			Write-ConsoleStatus -Status success
		}

		'Delete'
		{
			Write-ConsoleStatus -Action 'Removing SoftwareDistribution flush task'
			LogInfo "Removing Baseline SoftwareDistribution scheduled task"

			$existing = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $Script:BaselineSoftwareDistributionTaskName -ErrorAction SilentlyContinue
			if ($existing)
			{
				Unregister-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $Script:BaselineSoftwareDistributionTaskName -Confirm:$false -ErrorAction SilentlyContinue
			}

			foreach ($ext in @('.ps1', '.vbs'))
			{
				$path = Join-Path $Script:BaselineMaintenanceTaskScriptDir "$Script:BaselineSoftwareDistributionScriptBase$ext"
				if (Test-Path -LiteralPath $path)
				{
					Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
				}
			}

			# Only release the shared AppId when no other maintenance task remains.
			if (-not (Test-BaselineMaintenanceTasksRemaining))
			{
				Unregister-BaselineToastApp -AppId $Script:BaselineCleanupAppId
			}

			LogInfo "Removed Baseline SoftwareDistribution scheduled task"
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Runs temp task.

	#>

function TempTask
{
	<#
		.SYNOPSIS
		Registers (or removes) the Baseline Temp scheduled task — a 60-day
		purge of %TEMP% files older than one day plus the well-known
		orphan-folder list. Regression restored.

		.DESCRIPTION
		Manifest entry: Type=Toggle, OnParam=Register, OffParam=Delete.

		Register path:
		  - Registers the Baseline AppUserModelId so the completion toast
		    surfaces under a recognised application identity (idempotent
		    when CleanupTask or SoftwareDistributionTask already did so).
		  - Writes wscript-shim launchers for Temp.{ps1,vbs} under
		    %SystemRoot%\System32\Tasks\Baseline\. The .ps1 sweeps stale
		    %TEMP% files plus the orphan folders the original workflow targets, then
		    emits an information-only completion toast.
		  - Registers `\Baseline\Temp` (every 60 days at 9pm) under a
		    user-context principal so the toast renders in the
		    interactive session.

		Delete path:
		  - Unregisters the scheduled task and removes its script artifacts.
		  - Releases the AppUserModelId only if no other Baseline
		    maintenance task still needs it.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory, ParameterSetName = 'Register')]
		[switch]$Register,

		[Parameter(Mandatory, ParameterSetName = 'Delete')]
		[switch]$Delete
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		'Register'
		{
			Write-ConsoleStatus -Action 'Registering Temp folder purge task'
			LogInfo "Registering Baseline Temp scheduled task (60-day TEMP purge)"

			$completionBody = Get-BaselineLocalizedString -Key 'TempTaskNotificationEvent' -Fallback 'Temporary files folder successfully cleaned up.'
			$taskDescription = Get-BaselineLocalizedString -Key 'FolderTaskDescription' -Fallback 'The {0} folder cleanup. Scheduled task can be run only if user "{1}" logged into the system.' -FormatArgs @('%TEMP%', $env:USERNAME)

			Register-BaselineToastApp `
				-AppId $Script:BaselineCleanupAppId `
				-DisplayName $Script:BaselineCleanupAppId

			$payload = Get-BaselineTempTaskScript -Body $completionBody
			$artifacts = New-BaselineMaintenanceTaskScripts -BaseName $Script:BaselineTempScriptBase -PowerShellContent $payload

			$principal = New-BaselineMaintenanceTaskPrincipal
			$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval 60 -At 9pm

			Register-BaselineMaintenanceTask `
				-TaskName $Script:BaselineTempTaskName `
				-VbsPath $artifacts.VbsPath `
				-Trigger $trigger `
				-Principal $principal `
				-Description $taskDescription

			LogInfo "Registered '\\$Script:BaselineMaintenanceTaskPath\\$Script:BaselineTempTaskName' (every 60 days)"
			Write-ConsoleStatus -Status success
		}

		'Delete'
		{
			Write-ConsoleStatus -Action 'Removing Temp folder purge task'
			LogInfo "Removing Baseline Temp scheduled task"

			$existing = Get-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $Script:BaselineTempTaskName -ErrorAction SilentlyContinue
			if ($existing)
			{
				Unregister-ScheduledTask -TaskPath "\$Script:BaselineMaintenanceTaskPath\" -TaskName $Script:BaselineTempTaskName -Confirm:$false -ErrorAction SilentlyContinue
			}

			foreach ($ext in @('.ps1', '.vbs'))
			{
				$path = Join-Path $Script:BaselineMaintenanceTaskScriptDir "$Script:BaselineTempScriptBase$ext"
				if (Test-Path -LiteralPath $path)
				{
					Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
				}
			}

			if (-not (Test-BaselineMaintenanceTasksRemaining))
			{
				Unregister-BaselineToastApp -AppId $Script:BaselineCleanupAppId
			}

			LogInfo "Removed Baseline Temp scheduled task"
			Write-ConsoleStatus -Status success
		}
	}
}
$ExportedFunctions = @(
    'CleanupTask',
    'Clear-BaselineCleanupVolumeCacheFlags',
    'Get-BaselineCleanupNotificationTaskScript',
    'Get-BaselineCleanupTaskScript',
    'Get-BaselineSoftwareDistributionTaskScript',
    'Get-BaselineTempPurgePaths',
    'Get-BaselineTempTaskScript',
    'Invoke-BaselineSoftwareDistributionFlush',
    'Invoke-BaselineTempFolderPurge',
    'New-BaselineMaintenanceTaskPrincipal',
    'New-BaselineMaintenanceTaskScripts',
    'Register-BaselineMaintenanceTask',
    'Set-BaselineCleanupVolumeCacheFlags',
    'SoftwareDistributionTask',
    'TempTask',
    'Test-BaselineMaintenanceTasksRemaining'
)
Export-ModuleMember -Function $ExportedFunctions
