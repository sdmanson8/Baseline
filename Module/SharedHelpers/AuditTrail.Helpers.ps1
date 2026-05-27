# Audit trail helpers for Baseline.
# Provides structured JSONL audit logging for execution runs, defaults
# restoration, profile imports, and other auditable actions.

<#
    .SYNOPSIS
#>

function Get-AuditLogPath
{
	<# .SYNOPSIS Returns the path to the Baseline audit log file, creating the directory if needed. #>
	$auditDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Baseline')
	if (-not [System.IO.Directory]::Exists($auditDir))
	{
		[void][System.IO.Directory]::CreateDirectory($auditDir)
	}
	return [System.IO.Path]::Combine($auditDir, 'audit.jsonl')
}

function Get-BaselineAuditRetentionDays
{
	<# .SYNOPSIS Returns the audit retention period in days. #>
	[CmdletBinding()]
	param ()

	$retentionValue = $env:BASELINE_AUDIT_RETENTION_DAYS
	$days = 90
	if (-not [string]::IsNullOrWhiteSpace([string]$retentionValue))
	{
		try { $days = [int]$retentionValue } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Get-BaselineAuditRetentionDays:catch30' -Severity Debug }
		 $days = 90 }
	}

	if ($days -lt 30)
	{
		$days = 30
	}

	return $days
}

<#
    .SYNOPSIS
#>

function Get-BaselineAuditRetentionCutoff
{
	<# .SYNOPSIS Returns the audit retention cutoff timestamp. #>
	[CmdletBinding()]
	param ()

	return (Get-Date).AddDays(-1 * (Get-BaselineAuditRetentionDays))
}

function Invoke-BaselineAuditRetentionPolicy
{
	<# .SYNOPSIS Prunes audit log entries older than the retention cutoff. #>
	[CmdletBinding()]
	param ()

	$cutoff = Get-BaselineAuditRetentionCutoff
	Clear-AuditLog -OlderThan $cutoff
	return [pscustomobject]@{
		Cutoff = $cutoff.ToString('o')
		Days   = (Get-BaselineAuditRetentionDays)
	}
}

<#
    .SYNOPSIS
#>

function Write-AuditRecord
{
	<# .SYNOPSIS Appends a single JSON-lines audit record to the Baseline audit log. #>
	param (
		[Parameter(Mandatory)]
		[string]$Action,

		[Parameter(Mandatory)]
		[ValidateSet('Run', 'Defaults', 'GameMode', 'Compliance', 'Deployment', 'Profile')]
		[string]$Mode,

		[object]$Results,
		[string]$PresetName,
		[string]$ProfilePath,
		[System.TimeSpan]$Duration,
		[hashtable]$Details
	)

	Assert-BaselineWriteAllowed -Operation 'Write-AuditRecord'

	$record = [ordered]@{
		Timestamp      = (Get-Date).ToString('o')
		MachineName    = $env:COMPUTERNAME
		BaselineVersion = [string](Get-BaselineDisplayVersion)
		Action         = $Action
		Mode           = $Mode
	}

	if ($null -ne $Results)
	{
		$record['Results'] = [ordered]@{
			AppliedCount        = [int]$(if ($Results.PSObject.Properties['AppliedCount']) { $Results.AppliedCount } elseif ($Results.PSObject.Properties['SuccessCount']) { $Results.SuccessCount } else { 0 })
			FailedCount         = [int]$(if ($Results.PSObject.Properties['FailedCount']) { $Results.FailedCount } else { 0 })
			SkippedCount        = [int]$(if ($Results.PSObject.Properties['SkippedCount']) { $Results.SkippedCount } else { 0 })
			RestartPendingCount = [int]$(if ($Results.PSObject.Properties['RestartPendingCount']) { $Results.RestartPendingCount } else { 0 })
		}
	}

	if (-not [string]::IsNullOrWhiteSpace($PresetName))   { $record['PresetName']  = $PresetName }
	if (-not [string]::IsNullOrWhiteSpace($ProfilePath))  { $record['ProfilePath'] = $ProfilePath }
	if ($null -ne $Duration)                              { $record['DurationSeconds'] = [math]::Round($Duration.TotalSeconds, 2) }
	if ($null -ne $Details -and $Details.Count -gt 0)     { $record['Details'] = $Details }

	$json = ConvertTo-Json -InputObject $record -Compress -Depth 4
	$auditPath = Get-AuditLogPath
	[System.IO.File]::AppendAllText($auditPath, "$json`n", [System.Text.UTF8Encoding]::new($false))
	try
	{
		Invoke-BaselineAuditRetentionPolicy | Out-Null
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Write-AuditRecord.InvokeRetentionPolicy' -Severity Warning
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-AuditLog
{
	<# .SYNOPSIS Reads and optionally filters the Baseline audit log. Returns an array of parsed records. #>
	param (
		[datetime]$Since,
		[int]$MaxRecords = 500,
		[string]$Action
	)

	$auditPath = Get-AuditLogPath
	if (-not [System.IO.File]::Exists($auditPath))
	{
		return @()
	}

	$lines = [System.IO.File]::ReadAllLines($auditPath, [System.Text.UTF8Encoding]::new($false))
	$records = [System.Collections.Generic.List[object]]::new()

	foreach ($line in $lines)
	{
		if ([string]::IsNullOrWhiteSpace($line)) { continue }
		try
		{
			$obj = $line | ConvertFrom-BaselineJson -Depth 16
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Get-AuditLog:catch160' -Severity Debug }

			continue
		}

		if ($PSBoundParameters.ContainsKey('Since') -and $null -ne $obj.Timestamp)
		{
			$ts = $null
			if ($obj.Timestamp -is [datetime])
			{
				$ts = [datetime]$obj.Timestamp
			}
			else
			{
				try
				{
					$ts = [datetime]::Parse([string]$obj.Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Get-AuditLog:catch178' -Severity Debug }

					$ts = $null
				}
			}
			if ($null -ne $ts -and $ts -lt $Since) { continue }
		}

		if (-not [string]::IsNullOrWhiteSpace($Action) -and $obj.Action -ne $Action) { continue }

		$records.Add($obj)
		if ($records.Count -ge $MaxRecords) { break }
	}

	return @($records)
}

<#
    .SYNOPSIS
#>

function Export-AuditReport
{
	<# .SYNOPSIS Generates a formatted audit report from the Baseline audit log. #>
	param (
		[Parameter(Mandatory)]
		[string]$OutputPath,

		[ValidateSet('Markdown', 'Html')]
		[string]$Format = 'Markdown',

		[datetime]$Since
	)

	$getParams = @{}
	if ($PSBoundParameters.ContainsKey('Since')) { $getParams['Since'] = $Since }
	$getParams['MaxRecords'] = 10000
	$records = @(Get-AuditLog @getParams)

	if ($Format -eq 'Markdown')
	{
		$sb = [System.Text.StringBuilder]::new()
		[void]$sb.AppendLine('# Baseline Audit Report')
		[void]$sb.AppendLine('')
		[void]$sb.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
		[void]$sb.AppendLine("Machine: $env:COMPUTERNAME")
		[void]$sb.AppendLine("Records: $($records.Count)")
		[void]$sb.AppendLine('')

		# Summary table - runs by action type
		$grouped = $records | Group-Object -Property Action
		[void]$sb.AppendLine('## Summary by Action')
		[void]$sb.AppendLine('')
		[void]$sb.AppendLine('| Action | Count | Succeeded | Failed |')
		[void]$sb.AppendLine('|--------|-------|-----------|--------|')
		foreach ($group in $grouped)
		{
			$succeeded = ($group.Group | Where-Object { $_.Results } | ForEach-Object { [int]$_.Results.AppliedCount + [int]$_.Results.RestartPendingCount } | Measure-Object -Sum).Sum
			$failed = ($group.Group | Where-Object { $_.Results } | ForEach-Object { [int]$_.Results.FailedCount } | Measure-Object -Sum).Sum
			[void]$sb.AppendLine("| $($group.Name) | $($group.Count) | $succeeded | $failed |")
		}
		[void]$sb.AppendLine('')

		# Timeline
		[void]$sb.AppendLine('## Timeline')
		[void]$sb.AppendLine('')
		foreach ($rec in $records)
		{
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Export-AuditReport:catch246' -Severity Debug }
			 $rec.Timestamp } } else { '(unknown)' }
			$dur = if ($rec.DurationSeconds) { " (${$rec.DurationSeconds}s)" } else { '' }
			$resultInfo = ''
			if ($rec.Results)
			{
				$resultInfo = " - Applied: $($rec.Results.AppliedCount), Failed: $($rec.Results.FailedCount), Skipped: $($rec.Results.SkippedCount)"
			}
			[void]$sb.AppendLine("- **$ts** | $($rec.Action) ($($rec.Mode))$dur$resultInfo")
		}
		[void]$sb.AppendLine('')

		# Per-run detail
		[void]$sb.AppendLine('## Run Details')
		[void]$sb.AppendLine('')
		$index = 0
		foreach ($rec in $records)
		{
			$index++
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Export-AuditReport:catch264' -Severity Debug }
			 $rec.Timestamp } } else { '(unknown)' }
			[void]$sb.AppendLine("### Run $index - $($rec.Action)")
			[void]$sb.AppendLine("- **Time:** $ts")
			[void]$sb.AppendLine("- **Mode:** $($rec.Mode)")
			[void]$sb.AppendLine("- **Version:** $($rec.BaselineVersion)")
			if ($rec.DurationSeconds) { [void]$sb.AppendLine("- **Duration:** $($rec.DurationSeconds)s") }
			if ($rec.PresetName) { [void]$sb.AppendLine("- **Preset:** $($rec.PresetName)") }
			if ($rec.ProfilePath) { [void]$sb.AppendLine("- **Profile:** $($rec.ProfilePath)") }
			if ($rec.Results)
			{
				[void]$sb.AppendLine("- **Results:** Applied=$($rec.Results.AppliedCount), Failed=$($rec.Results.FailedCount), Skipped=$($rec.Results.SkippedCount), RestartPending=$($rec.Results.RestartPendingCount)")
			}
			if ($rec.Details)
			{
				[void]$sb.AppendLine("- **Details:** $(ConvertTo-Json -InputObject $rec.Details -Compress -Depth 2)")
			}
			[void]$sb.AppendLine('')
		}

		[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
	}
	else
	{
		# HTML format
		$sb = [System.Text.StringBuilder]::new()
		[void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Baseline Audit Report</title>')
		[void]$sb.AppendLine('<style>body{font-family:Arial,sans-serif;margin:2em}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#f4f4f4}tr:nth-child(even){background:#fafafa}.run{margin-bottom:1.5em;padding:1em;border:1px solid #e0e0e0;border-radius:4px}</style>')
		[void]$sb.AppendLine('</head><body>')
		[void]$sb.AppendLine("<h1>Baseline Audit Report</h1>")
		[void]$sb.AppendLine("<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Machine: $env:COMPUTERNAME | Records: $($records.Count)</p>")

		# Summary table
		$grouped = $records | Group-Object -Property Action
		[void]$sb.AppendLine('<h2>Summary by Action</h2><table><tr><th>Action</th><th>Count</th><th>Succeeded</th><th>Failed</th></tr>')
		foreach ($group in $grouped)
		{
			$succeeded = ($group.Group | Where-Object { $_.Results } | ForEach-Object { [int]$_.Results.AppliedCount + [int]$_.Results.RestartPendingCount } | Measure-Object -Sum).Sum
			$failed = ($group.Group | Where-Object { $_.Results } | ForEach-Object { [int]$_.Results.FailedCount } | Measure-Object -Sum).Sum
			[void]$sb.AppendLine("<tr><td>$($group.Name)</td><td>$($group.Count)</td><td>$succeeded</td><td>$failed</td></tr>")
		}
		[void]$sb.AppendLine('</table>')

		# Timeline
		[void]$sb.AppendLine('<h2>Timeline</h2><ul>')
		foreach ($rec in $records)
		{
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Export-AuditReport:catch310' -Severity Debug }
			 $rec.Timestamp } } else { '(unknown)' }
			$resultInfo = ''
			if ($rec.Results) { $resultInfo = " - Applied: $($rec.Results.AppliedCount), Failed: $($rec.Results.FailedCount)" }
			[void]$sb.AppendLine("<li><strong>$ts</strong> | $($rec.Action) ($($rec.Mode))$resultInfo</li>")
		}
		[void]$sb.AppendLine('</ul>')

		# Per-run detail
		[void]$sb.AppendLine('<h2>Run Details</h2>')
		$index = 0
		foreach ($rec in $records)
		{
			$index++
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Export-AuditReport:catch323' -Severity Debug }
			 $rec.Timestamp } } else { '(unknown)' }
			[void]$sb.AppendLine("<div class='run'><h3>Run $index - $($rec.Action)</h3>")
			[void]$sb.AppendLine("<p>Time: $ts | Mode: $($rec.Mode) | Version: $($rec.BaselineVersion)</p>")
			if ($rec.Results) { [void]$sb.AppendLine("<p>Applied: $($rec.Results.AppliedCount) | Failed: $($rec.Results.FailedCount) | Skipped: $($rec.Results.SkippedCount) | RestartPending: $($rec.Results.RestartPendingCount)</p>") }
			if ($rec.DurationSeconds) { [void]$sb.AppendLine("<p>Duration: $($rec.DurationSeconds)s</p>") }
			if ($rec.PresetName) { [void]$sb.AppendLine("<p>Preset: $($rec.PresetName)</p>") }
			[void]$sb.AppendLine('</div>')
		}

		[void]$sb.AppendLine('</body></html>')
		[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
	}
}

<#
    .SYNOPSIS
#>

function Clear-AuditLog
{
	<# .SYNOPSIS Removes audit records older than the specified threshold (retention policy). #>
	param (
		[Parameter(Mandatory)]
		[datetime]$OlderThan
	)

	$auditPath = Get-AuditLogPath
	if (-not [System.IO.File]::Exists($auditPath))
	{
		return
	}

	$lines = [System.IO.File]::ReadAllLines($auditPath, [System.Text.UTF8Encoding]::new($false))
	$kept = [System.Collections.Generic.List[string]]::new()

	foreach ($line in $lines)
	{
		if ([string]::IsNullOrWhiteSpace($line)) { continue }
		try
		{
			$obj = $line | ConvertFrom-BaselineJson -Depth 16
			$ts = [datetime]::Parse($obj.Timestamp)
			if ($ts -ge $OlderThan)
			{
				$kept.Add($line)
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Clear-AuditLog:catch370' -Severity Debug }

			# Keep unparseable lines to avoid silent data loss
			$kept.Add($line)
		}
	}

	$content = if ($kept.Count -gt 0) { ($kept -join "`n") + "`n" } else { '' }
	[System.IO.File]::WriteAllText($auditPath, $content, [System.Text.UTF8Encoding]::new($false))
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns the minimum retention period (in days) required by enterprise policy.
    This represents the floor below which the retention setting generates warnings.
#>

function Get-BaselineAuditRetentionPolicyThreshold
{
	<# .SYNOPSIS Returns the enterprise policy minimum retention threshold in days. #>
	[CmdletBinding()]
	param ()

	# Enterprise policy minimum: 90 days retention recommended.
	# Can be overridden via environment variable for enterprise flexibility.
	$configuredThreshold = $env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD
	if (-not [string]::IsNullOrWhiteSpace([string]$configuredThreshold))
	{
		try { return [int]$configuredThreshold } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Get-BaselineAuditRetentionPolicyThreshold:catch400' -Severity Debug }
		 return 90 }
	}

	return 90
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Tests whether the current audit retention setting falls below the policy threshold.
#>

function Test-BaselineAuditRetentionBelowPolicy
{
	<# .SYNOPSIS Returns $true if current retention is below the policy threshold. #>
	[CmdletBinding()]
	param (
		[int]$RetentionDays = $(Get-BaselineAuditRetentionDays)
	)

	$threshold = Get-BaselineAuditRetentionPolicyThreshold
	return ($RetentionDays -lt $threshold)
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Returns a warning object if retention is below policy threshold, $null otherwise.
#>

function Get-BaselineAuditRetentionPolicyWarning
{
	<# .SYNOPSIS Returns policy warning details if retention is below threshold. #>
	[CmdletBinding()]
	param (
		[int]$RetentionDays = $(Get-BaselineAuditRetentionDays)
	)

	$threshold = Get-BaselineAuditRetentionPolicyThreshold

	if ($RetentionDays -lt $threshold)
	{
		return [pscustomobject]@{
			Warning        = $true
			CurrentDays    = $RetentionDays
			PolicyMinimum  = $threshold
			Deficit        = $threshold - $RetentionDays
			Message        = "Audit retention of $RetentionDays days is below the policy minimum of $threshold days. Consider increasing retention to meet compliance requirements."
			Severity       = if (($threshold - $RetentionDays) -ge 30) { 'High' } else { 'Medium' }
			Recommendation = "Set BASELINE_AUDIT_RETENTION_DAYS environment variable to at least $threshold, or select a higher retention period in the Audit Settings dialog."
		}
	}

	return $null
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Verifies whether scheduled retention policy tasks are actually executing.
    Returns a structured result with execution status and any issues detected.
#>

function Test-BaselineAuditRetentionTaskExecution
{
	<# .SYNOPSIS Verifies retention policy task execution status. #>
	[CmdletBinding()]
	param ()

	$result = [ordered]@{
		TasksChecked       = @()
		TasksExecuting     = @()
		TasksStale         = @()
		TasksMissing       = @()
		OverallStatus      = 'Unknown'
		LastRetentionRun   = $null
		Issues             = @()
		Recommendations    = @()
	}

	# Check for Baseline scheduled tasks that should enforce retention
	if (-not (Get-Command -Name 'Get-BaselineScheduledTasks' -ErrorAction SilentlyContinue))
	{
		$result.Issues += 'Scheduler helpers not available. Cannot verify scheduled retention tasks.'
		$result.OverallStatus = 'Unavailable'
		return [pscustomobject]$result
	}

	try
	{
		$baselineTasks = @(Get-BaselineScheduledTasks)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AuditTrail.Helpers.Test-BaselineAuditRetentionTaskExecution:catch495' -Severity Debug }

		$result.Issues += "Failed to enumerate Baseline scheduled tasks: $($_.Exception.Message)"
		$result.OverallStatus = 'Error'
		return [pscustomobject]$result
	}

	if ($baselineTasks.Count -eq 0)
	{
		# No scheduled tasks - retention is applied on-demand only
		$result.OverallStatus = 'OnDemandOnly'
		$result.Issues += 'No Baseline scheduled tasks found. Retention policy is applied only during interactive use.'
		$result.Recommendations += 'Consider registering a scheduled compliance check to ensure periodic retention enforcement.'
		return [pscustomobject]$result
	}

	$staleThresholdDays = 14  # Tasks not run in 14 days are considered stale
	$staleThreshold = (Get-Date).AddDays(-$staleThresholdDays)

	foreach ($task in $baselineTasks)
	{
		$result.TasksChecked += $task.TaskName

		if ($task.State -notin @('Ready', 'Running'))
		{
			$result.TasksMissing += $task.TaskName
			$result.Issues += "Task '$($task.TaskName)' is not in a runnable state (State: $($task.State))."
			continue
		}

		if ($null -eq $task.LastRunTime -or $task.LastRunTime -eq [datetime]::MinValue)
		{
			$result.TasksStale += $task.TaskName
			$result.Issues += "Task '$($task.TaskName)' has never executed."
			continue
		}

		if ($task.LastRunTime -lt $staleThreshold)
		{
			$result.TasksStale += $task.TaskName
			$daysSinceRun = [math]::Round(((Get-Date) - $task.LastRunTime).TotalDays, 1)
			$result.Issues += "Task '$($task.TaskName)' has not run in $daysSinceRun days (last: $($task.LastRunTime.ToString('yyyy-MM-dd HH:mm')))."
			continue
		}

		# Task is executing normally
		$result.TasksExecuting += $task.TaskName

		# Track the most recent retention-related run
		if ($null -eq $result.LastRetentionRun -or $task.LastRunTime -gt $result.LastRetentionRun)
		{
			$result.LastRetentionRun = $task.LastRunTime
		}
	}

	# Determine overall status
	if ($result.TasksStale.Count -gt 0 -or $result.TasksMissing.Count -gt 0)
	{
		$result.OverallStatus = 'Degraded'
		$result.Recommendations += 'Review and repair stale or disabled scheduled tasks.'
	}
	elseif ($result.TasksExecuting.Count -gt 0)
	{
		$result.OverallStatus = 'Healthy'
	}
	else
	{
		$result.OverallStatus = 'Unknown'
	}

	return [pscustomobject]$result
}

<#
    .SYNOPSIS

    .DESCRIPTION
    Generates a comprehensive audit retention status report including policy compliance,
    task execution verification, and recommendations.
#>

function Get-BaselineAuditRetentionReport
{
	<# .SYNOPSIS Generates comprehensive audit retention status report. #>
	[CmdletBinding()]
	param ()

	$currentRetention = Get-BaselineAuditRetentionDays
	$policyThreshold = Get-BaselineAuditRetentionPolicyThreshold
	$policyWarning = Get-BaselineAuditRetentionPolicyWarning -RetentionDays $currentRetention
	$taskExecution = Test-BaselineAuditRetentionTaskExecution

	$report = [ordered]@{
		GeneratedAt         = (Get-Date).ToString('o')
		MachineName         = $env:COMPUTERNAME
		Retention           = [ordered]@{
			CurrentDays     = $currentRetention
			PolicyMinimum   = $policyThreshold
			BelowPolicy     = ($currentRetention -lt $policyThreshold)
			CutoffDate      = (Get-BaselineAuditRetentionCutoff).ToString('o')
		}
		PolicyWarning       = $policyWarning
		TaskExecution       = $taskExecution
		OverallCompliance   = 'Unknown'
		Issues              = @()
		Recommendations     = @()
	}

	# Aggregate issues and recommendations
	if ($policyWarning)
	{
		$report.Issues += $policyWarning.Message
		$report.Recommendations += $policyWarning.Recommendation
	}

	$report.Issues += $taskExecution.Issues
	$report.Recommendations += $taskExecution.Recommendations

	# Determine overall compliance
	if ($report.Retention.BelowPolicy)
	{
		$report.OverallCompliance = 'NonCompliant'
	}
	elseif ($taskExecution.OverallStatus -eq 'Degraded')
	{
		$report.OverallCompliance = 'PartiallyCompliant'
	}
	elseif ($taskExecution.OverallStatus -eq 'Healthy')
	{
		$report.OverallCompliance = 'Compliant'
	}
	else
	{
		$report.OverallCompliance = 'Unknown'
	}

	return [pscustomobject]$report
}

