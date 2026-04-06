# Audit trail helper slice for Baseline.
# Provides structured JSONL audit logging for execution runs, defaults
# restoration, profile imports, and other auditable actions.

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

function Write-AuditRecord
{
	<# .SYNOPSIS Appends a single JSON-lines audit record to the Baseline audit log. #>
	param (
		[Parameter(Mandatory)]
		[string]$Action,

		[Parameter(Mandatory)]
		[ValidateSet('Run', 'Defaults', 'GameMode', 'Compliance')]
		[string]$Mode,

		[object]$Results,
		[string]$PresetName,
		[string]$ProfilePath,
		[System.TimeSpan]$Duration,
		[hashtable]$Details
	)

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
}

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
			$obj = $line | ConvertFrom-Json
		}
		catch
		{
			continue
		}

		if ($PSBoundParameters.ContainsKey('Since') -and $null -ne $obj.Timestamp)
		{
			$ts = [datetime]::Parse($obj.Timestamp)
			if ($ts -lt $Since) { continue }
		}

		if (-not [string]::IsNullOrWhiteSpace($Action) -and $obj.Action -ne $Action) { continue }

		$records.Add($obj)
		if ($records.Count -ge $MaxRecords) { break }
	}

	return @($records)
}

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
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch { $rec.Timestamp } } else { '(unknown)' }
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
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch { $rec.Timestamp } } else { '(unknown)' }
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
		[void]$sb.AppendLine('<style>body{font-family:Segoe UI,sans-serif;margin:2em}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;text-align:left}th{background:#f4f4f4}tr:nth-child(even){background:#fafafa}.run{margin-bottom:1.5em;padding:1em;border:1px solid #e0e0e0;border-radius:4px}</style>')
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
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch { $rec.Timestamp } } else { '(unknown)' }
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
			$ts = if ($rec.Timestamp) { try { ([datetime]::Parse($rec.Timestamp)).ToString('yyyy-MM-dd HH:mm:ss') } catch { $rec.Timestamp } } else { '(unknown)' }
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
			$obj = $line | ConvertFrom-Json
			$ts = [datetime]::Parse($obj.Timestamp)
			if ($ts -ge $OlderThan)
			{
				$kept.Add($line)
			}
		}
		catch
		{
			# Keep unparseable lines to avoid silent data loss
			$kept.Add($line)
		}
	}

	$content = if ($kept.Count -gt 0) { ($kept -join "`n") + "`n" } else { '' }
	[System.IO.File]::WriteAllText($auditPath, $content, [System.Text.UTF8Encoding]::new($false))
}
