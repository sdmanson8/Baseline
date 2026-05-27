# Compliance checking helpers for Baseline.
# Provides drift detection by comparing current system state against a saved
# profile (snapshot) and generating compliance reports with remediation plans.
#
# Dependencies (loaded earlier in SharedHelpers.psm1):
#   Get-TweakCurrentStateValue, Get-TweakPlannedStateValue (StateCapture.Helpers.ps1)
#   Get-TweakManifestEntryValue, Test-TweakManifestEntryField,
#     Get-ManifestEntryByFunction (Manifest.Helpers.ps1)
#   Write-BaselineDocument (Persistence.Helpers.ps1)

<#
    .SYNOPSIS
#>

function Test-SystemCompliance
{
	<#
		.SYNOPSIS
		Evaluates the current system state against a saved profile or snapshot and
		returns a structured compliance report indicating compliant, drifted, and
		unknown entries.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Profile,

		[Parameter(Mandatory = $true)]
		[array]$Manifest
	)

	$entries = [System.Collections.ArrayList]::new()
	$compliantCount = 0
	$driftedCount   = 0
	$unknownCount   = 0

	# Determine profile name from common schema fields.
	$profileName = $null
	if ($Profile.PSObject.Properties['ProfileName'])
	{
		$profileName = [string]$Profile.ProfileName
	}
	elseif ($Profile.PSObject.Properties['Data'] -and $Profile.Data.PSObject.Properties['ProfileName'])
	{
		$profileName = [string]$Profile.Data.ProfileName
	}
	elseif ($Profile.PSObject.Properties['Schema'])
	{
		$profileName = [string]$Profile.Schema
	}

	# Resolve the entries list from the profile. Support both raw snapshot
	# objects (Schema = Baseline.StateSnapshot with top-level Entries) and
	# persistence-envelope documents (Data.Entries).
	$profileEntries = $null
	if ($Profile.PSObject.Properties['Entries'] -and $Profile.Entries)
	{
		$profileEntries = @($Profile.Entries)
	}
	elseif ($Profile.PSObject.Properties['Data'] -and $Profile.Data.PSObject.Properties['Entries'])
	{
		$profileEntries = @($Profile.Data.Entries)
	}

	if (-not $profileEntries -or $profileEntries.Count -eq 0)
	{
		return [pscustomobject]@{
			Schema       = 'Baseline.ComplianceReport'
			Timestamp    = [datetime]::UtcNow.ToString('o')
			MachineName  = [System.Environment]::MachineName
			ProfileName  = $profileName
			TotalChecked = 0
			Compliant    = 0
			Drifted      = 0
			Unknown      = 0
			Entries      = @()
		}
	}

	# Build a hashtable index of manifest entries by function name to avoid
	# O(n) linear scans in Get-ManifestEntryByFunction for every profile entry.
	$manifestByFunction = @{}
	foreach ($mEntry in @($Manifest))
	{
		$mFunc = [string](Get-TweakManifestEntryValue -Entry $mEntry -FieldName 'Function')
		if (-not [string]::IsNullOrWhiteSpace($mFunc))
		{
			$manifestByFunction[$mFunc] = $mEntry
		}
	}

	# Yield to the UI dispatcher periodically so the GUI stays responsive
	# during long compliance checks.
	$dispatcherType = 'System.Windows.Threading.Dispatcher' -as [type]
	$entryIndex = 0

	foreach ($profileEntry in @($profileEntries))
	{
		if (-not $profileEntry) { continue }
		$entryIndex++
		if ($dispatcherType -and ($entryIndex % 10 -eq 0))
		{
			try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ComplianceHelpers.Test-SystemCompliance.DispatcherYield' }
		}

		$functionName = $null
		$entryName    = $null
		$desiredValue = $null

		if ($profileEntry.PSObject.Properties['Function'])
		{
			$functionName = [string]$profileEntry.Function
		}
		if ($profileEntry.PSObject.Properties['Name'])
		{
			$entryName = [string]$profileEntry.Name
		}
		if ($profileEntry.PSObject.Properties['DetectedValue'])
		{
			$desiredValue = $profileEntry.DetectedValue
		}

		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		# Find the corresponding manifest entry via indexed lookup.
		$manifestEntry = $manifestByFunction[$functionName]
		if (-not $manifestEntry)
		{
			# Entry exists in profile but not in the current manifest - mark unknown.
			$unknownCount++
			[void]$entries.Add([pscustomobject]@{
				Function     = $functionName
				Name         = if (-not [string]::IsNullOrWhiteSpace($entryName)) { $entryName } else { $functionName }
				DesiredState = $desiredValue
				ActualState  = $null
				Status       = 'Unknown'
			})
			continue
		}

		# Skip entries that are not scannable or have no Detect scriptblock.
		$scannable = Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Scannable'
		if ($null -ne $scannable -and -not [bool]$scannable)
		{
			$unknownCount++
			[void]$entries.Add([pscustomobject]@{
				Function     = $functionName
				Name         = if (-not [string]::IsNullOrWhiteSpace($entryName)) { $entryName } else { $functionName }
				DesiredState = $desiredValue
				ActualState  = $null
				Status       = 'Unknown'
			})
			continue
		}

		$detectBlock = Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Detect'
		if ($null -eq $detectBlock)
		{
			$unknownCount++
			[void]$entries.Add([pscustomobject]@{
				Function     = $functionName
				Name         = if (-not [string]::IsNullOrWhiteSpace($entryName)) { $entryName } else { $functionName }
				DesiredState = $desiredValue
				ActualState  = $null
				Status       = 'Unknown'
			})
			continue
		}

		# Evaluate the current system state using the same engine as the scan.
		$stateResult = Get-TweakCurrentStateValue -Entry $manifestEntry
		$actualValue = $stateResult.DetectedValue

		# Compare desired vs actual.
		$status = 'Drifted'
		if ($null -eq $desiredValue -and $null -eq $actualValue)
		{
			$status = 'Compliant'
		}
		elseif ($null -ne $desiredValue -and $null -ne $actualValue)
		{
			if ([string]$desiredValue -eq [string]$actualValue)
			{
				$status = 'Compliant'
			}
		}

		if ($status -eq 'Compliant')
		{
			$compliantCount++
		}
		else
		{
			$driftedCount++
		}

		[void]$entries.Add([pscustomobject]@{
			Function     = $functionName
			Name         = if (-not [string]::IsNullOrWhiteSpace($entryName)) { $entryName } else { $functionName }
			DesiredState = $desiredValue
			ActualState  = $actualValue
			Status       = $status
		})
	}

	return [pscustomobject]@{
		Schema       = 'Baseline.ComplianceReport'
		Timestamp    = [datetime]::UtcNow.ToString('o')
		MachineName  = [System.Environment]::MachineName
		ProfileName  = $profileName
		TotalChecked = $entries.Count
		Compliant    = $compliantCount
		Drifted      = $driftedCount
		Unknown      = $unknownCount
		Entries      = @($entries)
	}
}
<#
    .SYNOPSIS
#>

function Get-DriftedEntries
{
	<#
		.SYNOPSIS
		Filters a compliance report to return only entries with Status = 'Drifted'.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ComplianceReport
	)

	if (-not $ComplianceReport -or -not $ComplianceReport.PSObject.Properties['Entries'])
	{
		return @()
	}

	return @($ComplianceReport.Entries | Where-Object { $_.Status -eq 'Drifted' })
}

function Get-ComplianceFixList
{
	<#
		.SYNOPSIS
		For each drifted entry in a compliance report, builds a tweak run list item
		that would bring the system back into compliance. The returned array uses
		the same command-string format consumed by the headless execution path.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$ComplianceReport,

		[Parameter(Mandatory = $true)]
		[array]$Manifest
	)

	$fixList = [System.Collections.ArrayList]::new()
	$driftedEntries = Get-DriftedEntries -ComplianceReport $ComplianceReport

	foreach ($drifted in @($driftedEntries))
	{
		if (-not $drifted) { continue }

		$functionName = [string]$drifted.Function
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		$manifestEntry = Get-ManifestEntryByFunction -Manifest $Manifest -Function $functionName
		if (-not $manifestEntry) { continue }

		$desiredValue = $drifted.DesiredState
		$typeValue = [string](Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'Type')

		$command = $null
		switch ($typeValue)
		{
			'Toggle'
			{
				# Determine which parameter achieves the desired state.
				$onParam  = ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OnParam')
				$offParam = ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OffParam')

				if ([string]::IsNullOrWhiteSpace($onParam))  { $onParam  = 'Enable' }
				if ([string]::IsNullOrWhiteSpace($offParam)) { $offParam = 'Disable' }

				if ($null -ne $desiredValue)
				{
					$paramName = if ([bool]$desiredValue) { $onParam } else { $offParam }
					$command = '{0} -{1}' -f $functionName, $paramName
				}
				else
				{
					# Desired was null (feature not present); use the Off param.
					$command = '{0} -{1}' -f $functionName, $offParam
				}
			}
			'Date'
			{
				$dateValue = if ($null -ne $desiredValue) { [string]$desiredValue } else { $null }
				$dateParam = ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'DateParam')
				if ([string]::IsNullOrWhiteSpace($dateParam))
				{
					$dateParam = 'StartDate'
				}

				if ([string]::IsNullOrWhiteSpace($dateValue))
				{
					$offParam = ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OffParam')
					if ([string]::IsNullOrWhiteSpace($offParam))
					{
						$offParam = 'Disable'
					}
					$command = '{0} -{1}' -f $functionName, $offParam
				}
				else
				{
					$onParam = ConvertTo-NormalizedParameterName -Value (Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName 'OnParam')
					if ([string]::IsNullOrWhiteSpace($onParam))
					{
						$onParam = 'Enable'
					}
					$command = '{0} -{1} -{2} {3}' -f $functionName, $onParam, $dateParam, $dateValue
				}
			}
			'Choice'
			{
				if ($null -ne $desiredValue -and -not [string]::IsNullOrWhiteSpace([string]$desiredValue))
				{
					$command = '{0} -{1}' -f $functionName, [string]$desiredValue
				}
				else
				{
					$command = $functionName
				}
			}
			default
			{
				$command = $functionName
			}
		}

		if (-not [string]::IsNullOrWhiteSpace($command))
		{
			[void]$fixList.Add($command)
		}
	}

	return @($fixList)
}

<#
    .SYNOPSIS
#>

function Add-WindowsUpdateComplianceReportSection
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Report
	)

	if ($Report -is [System.Collections.IDictionary])
	{
		if ($Report.Contains('WindowsUpdateCompliance'))
		{
			return $Report
		}
	}
	elseif ($Report.PSObject.Properties['WindowsUpdateCompliance'])
	{
		return $Report
	}

	$getWindowsUpdateComplianceCommand = Get-Command -Name 'Get-WindowsUpdateCompliance' -CommandType Function -ErrorAction SilentlyContinue
	if (-not $getWindowsUpdateComplianceCommand)
	{
		return $Report
	}

	$windowsUpdateCompliance = $null
	try
	{
		$windowsUpdateCompliance = & $getWindowsUpdateComplianceCommand
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Compliance.Helpers.Add-WindowsUpdateComplianceReportSection:catch387' -Severity Debug }

		$windowsUpdateCompliance = [pscustomobject]@{
			Schema      = 'Baseline.WindowsUpdateCompliance'
			GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
			Status      = 'Unknown'
			Error       = $_.Exception.Message
		}
	}

	if ($Report -is [System.Collections.IDictionary])
	{
		$Report['WindowsUpdateCompliance'] = $windowsUpdateCompliance
	}
	else
	{
		$Report | Add-Member -MemberType NoteProperty -Name 'WindowsUpdateCompliance' -Value $windowsUpdateCompliance -Force
	}

	return $Report
}

<#
    .SYNOPSIS
#>

function Export-ComplianceReport
{
	<#
		.SYNOPSIS
		Writes a compliance report to disk in JSON or Markdown format.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Report,

		[Parameter(Mandatory = $true)]
		[string]$FilePath,

		[ValidateSet('Json', 'Markdown')]
		[string]$Format = 'Json'
	)

	$parentDir = Split-Path $FilePath -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		$null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
	}

	$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
	$reportToWrite = Add-WindowsUpdateComplianceReportSection -Report $Report

	switch ($Format)
	{
		'Json'
		{
			$json = $reportToWrite | ConvertTo-Json -Depth 16
			[System.IO.File]::WriteAllText($FilePath, $json, $utf8NoBom)
		}
		'Markdown'
		{
			$lines = [System.Collections.ArrayList]::new()
			[void]$lines.Add("# Baseline Compliance Report")
			[void]$lines.Add('')
			[void]$lines.Add("| Field | Value |")
			[void]$lines.Add("| --- | --- |")
			[void]$lines.Add("| Timestamp | $($reportToWrite.Timestamp) |")
			[void]$lines.Add("| Machine | $($reportToWrite.MachineName) |")
			[void]$lines.Add("| Profile | $($reportToWrite.ProfileName) |")
			[void]$lines.Add("| Total Checked | $($reportToWrite.TotalChecked) |")
			[void]$lines.Add("| Compliant | $($reportToWrite.Compliant) |")
			[void]$lines.Add("| Drifted | $($reportToWrite.Drifted) |")
			[void]$lines.Add("| Unknown | $($reportToWrite.Unknown) |")
			[void]$lines.Add('')

			if ($reportToWrite.PSObject.Properties['WindowsUpdateCompliance'])
			{
				$wuCompliance = $reportToWrite.WindowsUpdateCompliance
				[void]$lines.Add("## Windows Update Compliance")
				[void]$lines.Add('')
				[void]$lines.Add("| Field | Value |")
				[void]$lines.Add("| --- | --- |")
				[void]$lines.Add("| Status | $($wuCompliance.Status) |")
				[void]$lines.Add("| Critical Pending | $($wuCompliance.CriticalPending) |")
				[void]$lines.Add("| Security Pending | $($wuCompliance.SecurityPending) |")
				if ($wuCompliance.PSObject.Properties['Error'] -and -not [string]::IsNullOrWhiteSpace([string]$wuCompliance.Error))
				{
					[void]$lines.Add("| Error | $($wuCompliance.Error) |")
				}
				[void]$lines.Add('')
			}

			if ($reportToWrite.Entries -and $reportToWrite.Entries.Count -gt 0)
			{
				[void]$lines.Add("## Entries")
				[void]$lines.Add('')
				[void]$lines.Add("| Function | Name | Desired | Actual | Status |")
				[void]$lines.Add("| --- | --- | --- | --- | --- |")

				foreach ($entry in @($reportToWrite.Entries))
				{
					$desired = if ($null -ne $entry.DesiredState) { [string]$entry.DesiredState } else { '(null)' }
					$actual  = if ($null -ne $entry.ActualState)  { [string]$entry.ActualState }  else { '(null)' }
					[void]$lines.Add("| $($entry.Function) | $($entry.Name) | $desired | $actual | $($entry.Status) |")
				}

				[void]$lines.Add('')
			}

			# Separate sections for drifted entries for quick scanning.
			$driftedEntries = @($reportToWrite.Entries | Where-Object { $_.Status -eq 'Drifted' })
			if ($driftedEntries.Count -gt 0)
			{
				[void]$lines.Add("## Drifted Entries")
				[void]$lines.Add('')
				foreach ($entry in @($driftedEntries))
				{
					$desired = if ($null -ne $entry.DesiredState) { [string]$entry.DesiredState } else { '(null)' }
					$actual  = if ($null -ne $entry.ActualState)  { [string]$entry.ActualState }  else { '(null)' }
					[void]$lines.Add("- **$($entry.Name)** ($($entry.Function)): desired=$desired, actual=$actual")
				}
				[void]$lines.Add('')
			}

			$markdown = $lines -join "`n"
			[System.IO.File]::WriteAllText($FilePath, $markdown, $utf8NoBom)
		}
	}
}
