# State capture helpers for Baseline.
# Provides system state snapshot capture, comparison, and persistence for
# tweaks tracked by the manifest system.
#
# Dependencies (loaded earlier in SharedHelpers.psm1):
#   Get-TweakManifestEntryValue, Test-TweakManifestEntryField (Manifest.Helpers.ps1)
#   Get-OSInfo, Get-WindowsVersionData (Environment.Helpers.ps1)

<#
    .SYNOPSIS
#>

function ConvertTo-StateCaptureComparableText
{
	[CmdletBinding()]
	param ([object]$Value)

	if ($null -eq $Value)
	{
		return ''
	}

	if ($Value -is [string])
	{
		return [string]$Value
	}

	if ($Value -is [bool] -or $Value -is [ValueType])
	{
		return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
	}

	if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject] -or ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])))
	{
		try
		{
			return ($Value | ConvertTo-Json -Depth 16 -Compress)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StateCapture.Helpers.ConvertTo-StateCaptureComparableText:catch39' -Severity Debug }

			return [string]$Value
		}
	}

	return [string]$Value
}

<#
    .SYNOPSIS
#>

function Get-TweakCurrentStateValue
{
	<# .SYNOPSIS Evaluates a single manifest entry's Detect scriptblock and returns a structured state object. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry
	)

	$functionName = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Function')
	$entryName    = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Name')
	$entryKey     = '{0}|{1}' -f $entryName, $functionName

	$detectedValue = $null
	$detectBlock   = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Detect'

	if ($null -ne $detectBlock)
	{
		try
		{
			$detectedValue = & $detectBlock
		}
		catch
		{
			$warnMsg = "StateCapture: Detect scriptblock failed for '$functionName': $($_.Exception.Message)"
			$logWarningCommand = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
			if ($logWarningCommand) { LogWarning $warnMsg } else { Write-Warning $warnMsg }
			$detectedValue = $null
		}
	}

	return [pscustomobject]@{
		Key           = $entryKey
		Name          = $entryName
		Function      = $functionName
		DetectedValue = $detectedValue
		Timestamp     = [datetime]::UtcNow.ToString('o')
	}
}

<#
    .SYNOPSIS
#>

function Invoke-StateCaptureProgressCallback
{
	[CmdletBinding()]
	param (
		[AllowNull()]
		[scriptblock]$ProgressCallback,

		[Parameter(Mandatory = $true)]
		[object]$Progress
	)

	if ($null -eq $ProgressCallback)
	{
		return
	}

	try
	{
		& $ProgressCallback $Progress
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'StateCapture.ProgressCallback'
		}
	}
}

<#
    .SYNOPSIS
#>

function New-SystemStateSnapshot
{
	<# .SYNOPSIS Captures a full system state snapshot by evaluating Detect scriptblocks across the manifest. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[array]$Manifest,

		[string]$CategoryFilter = $null,

		[AllowNull()]
		[scriptblock]$ProgressCallback = $null
	)

	$entries = [System.Collections.ArrayList]::new()
	$timestamp = [datetime]::UtcNow.ToString('o')

	$osVersionString = $null
	Invoke-StateCaptureProgressCallback -ProgressCallback $ProgressCallback -Progress ([pscustomobject]@{
		Stage    = 'SystemInfo'
		Index    = 0
		Total    = 0
		Name     = 'System information'
		Function = 'Get-OSInfo'
		Key      = 'System information|Get-OSInfo'
		Category = 'System'
	})
	try
	{
		$osInfo = Get-OSInfo
		if ($osInfo -and $osInfo.PSObject.Properties['Caption'])
		{
			$osVersionString = [string]$osInfo.Caption
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StateCapture.Helpers.New-SystemStateSnapshot:catch164' -Severity Debug }

		$osVersionString = $null
	}

	if ([string]::IsNullOrWhiteSpace($osVersionString))
	{
		try
		{
			$winData = Get-WindowsVersionData
			if ($winData -and $winData.PSObject.Properties['DisplayVersion'])
			{
				$osVersionString = [string]$winData.DisplayVersion
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StateCapture.Helpers.New-SystemStateSnapshot:catch179' -Severity Debug }

			$osVersionString = 'Unknown'
		}
	}

	$candidateEntries = [System.Collections.ArrayList]::new()
	foreach ($entry in @($Manifest))
	{
		if (-not $entry) { continue }

		if (-not [string]::IsNullOrWhiteSpace($CategoryFilter))
		{
			$entryCategory = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Category')
			if (-not $entryCategory.Equals($CategoryFilter, [System.StringComparison]::OrdinalIgnoreCase))
			{
				continue
			}
		}

		# Skip entries that are not scannable or have no Detect scriptblock.
		$scannable = Get-TweakManifestEntryValue -Entry $entry -FieldName 'Scannable'
		if ($null -ne $scannable -and -not [bool]$scannable) { continue }

		$detectBlock = Get-TweakManifestEntryValue -Entry $entry -FieldName 'Detect'
		if ($null -eq $detectBlock) { continue }

		[void]$candidateEntries.Add($entry)
	}

	$entryIndex = 0
	$totalEntries = [int]$candidateEntries.Count
	foreach ($entry in @($candidateEntries))
	{
		$entryIndex++
		$functionName = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function')
		$entryName    = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Name')
		$entryCategory = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Category')
		$entryKey     = '{0}|{1}' -f $entryName, $functionName

		Invoke-StateCaptureProgressCallback -ProgressCallback $ProgressCallback -Progress ([pscustomobject]@{
			Stage    = 'EntryStart'
			Index    = $entryIndex
			Total    = $totalEntries
			Name     = $entryName
			Function = $functionName
			Key      = $entryKey
			Category = $entryCategory
		})

		$stateValue = Get-TweakCurrentStateValue -Entry $entry
		[void]$entries.Add($stateValue)
	}

	return [pscustomobject]@{
		Schema        = 'Baseline.StateSnapshot'
		SchemaVersion = 1
		Timestamp     = $timestamp
		MachineName   = [System.Environment]::MachineName
		OSVersion     = $osVersionString
		Entries       = @($entries)
	}
}

<#
    .SYNOPSIS
#>

function Compare-SystemStateSnapshots
{
	<# .SYNOPSIS Compares two system state snapshots and returns the differences. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Before,

		[Parameter(Mandatory = $true)]
		[object]$After
	)

	$beforeMap = @{}
	foreach ($entry in @($Before.Entries))
	{
		if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.Key))
		{
			$beforeMap[[string]$entry.Key] = $entry
		}
	}

	$afterMap = @{}
	foreach ($entry in @($After.Entries))
	{
		if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.Key))
		{
			$afterMap[[string]$entry.Key] = $entry
		}
	}

	$added     = [System.Collections.ArrayList]::new()
	$removed   = [System.Collections.ArrayList]::new()
	$changed   = [System.Collections.ArrayList]::new()
	$unchanged = [System.Collections.ArrayList]::new()

	# Entries present in After but not in Before.
	foreach ($key in $afterMap.Keys)
	{
		if (-not $beforeMap.ContainsKey($key))
		{
			[void]$added.Add($afterMap[$key])
		}
	}

	# Entries present in Before but not in After.
	foreach ($key in $beforeMap.Keys)
	{
		if (-not $afterMap.ContainsKey($key))
		{
			[void]$removed.Add($beforeMap[$key])
		}
	}

	# Entries present in both - compare DetectedValue.
	foreach ($key in $beforeMap.Keys)
	{
		if (-not $afterMap.ContainsKey($key)) { continue }

		$beforeEntry = $beforeMap[$key]
		$afterEntry  = $afterMap[$key]

		$beforeValue = $beforeEntry.DetectedValue
		$afterValue  = $afterEntry.DetectedValue

		$valuesMatch = $false
		if ($null -eq $beforeValue -and $null -eq $afterValue)
		{
			$valuesMatch = $true
		}
		elseif ($null -ne $beforeValue -and $null -ne $afterValue)
		{
			$valuesMatch = (ConvertTo-StateCaptureComparableText -Value $beforeValue) -eq (ConvertTo-StateCaptureComparableText -Value $afterValue)
		}

		if ($valuesMatch)
		{
			[void]$unchanged.Add($afterEntry)
		}
		else
		{
			[void]$changed.Add([pscustomobject]@{
				Key           = $key
				Name          = [string]$afterEntry.Name
				Function      = [string]$afterEntry.Function
				BeforeValue   = $beforeValue
				AfterValue    = $afterValue
			})
		}
	}

	return [pscustomobject]@{
		Added     = @($added)
		Removed   = @($removed)
		Changed   = @($changed)
		Unchanged = @($unchanged)
	}
}

<#
    .SYNOPSIS
#>

function Export-SystemStateSnapshot
{
	<# .SYNOPSIS Exports a system state snapshot to a JSON file (UTF-8 no BOM). #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,

		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	$parentDir = Split-Path $Path -Parent
	if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir))
	{
		$null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
	}

	$json = $Snapshot | ConvertTo-Json -Depth 10
	$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
	[System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

<#
    .SYNOPSIS
#>

function Import-SystemStateSnapshot
{
	<# .SYNOPSIS Imports and validates a system state snapshot from a JSON file. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -LiteralPath $Path))
	{
		throw "Snapshot file not found: $Path"
	}

	$rawJson = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
	if ([string]::IsNullOrWhiteSpace($rawJson))
	{
		throw "Snapshot file is empty: $Path"
	}

	$snapshot = $rawJson | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop

	if (-not $snapshot.PSObject.Properties['Schema'] -or [string]$snapshot.Schema -ne 'Baseline.StateSnapshot')
	{
		throw "Invalid snapshot schema. Expected 'Baseline.StateSnapshot', found '$([string]$snapshot.Schema)'."
	}

	if (-not $snapshot.PSObject.Properties['SchemaVersion'] -or [int]$snapshot.SchemaVersion -lt 1)
	{
		throw "Unsupported snapshot schema version: $([string]$snapshot.SchemaVersion)"
	}

	return $snapshot
}

<#
    .SYNOPSIS
#>

function Limit-SnapshotDirectory
{
	<# .SYNOPSIS Prunes old snapshot files from a directory, keeping the most recent N files. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Directory,

		[int]$Keep = 10
	)

	if (-not (Test-Path -LiteralPath $Directory)) { return }

	$snapshotFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File | Sort-Object LastWriteTime -Descending)
	if ($snapshotFiles.Count -le $Keep) { return }

	$filesToRemove = $snapshotFiles | Select-Object -Skip $Keep
	foreach ($file in $filesToRemove)
	{
		try
		{
			Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			$warnMsg = "SnapshotCleanup: Failed to remove old snapshot '$($file.FullName)': $($_.Exception.Message)"
			$logWarningCommand = Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue
			if ($logWarningCommand) { LogWarning $warnMsg } else { Write-Warning $warnMsg }
		}
	}
}

<#
    .SYNOPSIS
#>

function Get-TweakPlannedStateValue
{
	<# .SYNOPSIS Derives the planned post-execution state for a tweak run list item. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$RunListItem
	)

	$typeValue = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Type')
	$functionName = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Function')

	switch ($typeValue)
	{
		'Toggle'
		{
			$toggleParam = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'ToggleParam')
			if ([string]::IsNullOrWhiteSpace($toggleParam))
			{
				$toggleParam = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Selection')
			}

			$onParam  = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'OnParam')
			$offParam = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'OffParam')

			$plannedState = $null
			if (-not [string]::IsNullOrWhiteSpace($toggleParam) -and -not [string]::IsNullOrWhiteSpace($onParam))
			{
				if ($toggleParam.Equals($onParam, [System.StringComparison]::OrdinalIgnoreCase))
				{
					$plannedState = $true
				}
				elseif (-not [string]::IsNullOrWhiteSpace($offParam) -and $toggleParam.Equals($offParam, [System.StringComparison]::OrdinalIgnoreCase))
				{
					$plannedState = $false
				}
			}

			# Fallback: infer from common parameter names.
			if ($null -eq $plannedState -and -not [string]::IsNullOrWhiteSpace($toggleParam))
			{
				$normalizedParam = $toggleParam.Trim().TrimStart('-')
				switch -Regex ($normalizedParam)
				{
					'^(Enable|On|Yes|Show|Add|Install|Activate)$'  { $plannedState = $true; break }
					'^(Disable|Off|No|Hide|Remove|Uninstall|Deactivate)$' { $plannedState = $false; break }
				}
			}

			return [pscustomobject]@{
				Function     = $functionName
				Type         = 'Toggle'
				ToggleParam  = $toggleParam
				PlannedState = $plannedState
			}
		}
		'Date'
		{
			$runFlag = $null
			if (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'Run')
			{
				$runFlag = [bool](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Run')
			}
			elseif (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'State')
			{
				$runFlag = ([string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'State') -match '^(?i:on|true|1)$')
			}
			elseif (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'IsChecked')
			{
				$runFlag = [bool](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'IsChecked')
			}

			$dateValue = $null
			foreach ($fieldName in @('Value', 'DateValue', 'SelectedValue'))
			{
				if (Test-TweakManifestEntryField -Entry $RunListItem -FieldName $fieldName)
				{
					$candidateValue = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName $fieldName)
					if (-not [string]::IsNullOrWhiteSpace($candidateValue))
					{
						$dateValue = $candidateValue
						break
					}
				}
			}

			$dateParam = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'DateParam')
			return [pscustomobject]@{
				Function     = $functionName
				Type         = 'Date'
				Run          = if ($null -eq $runFlag) { [bool]$dateValue } else { [bool]$runFlag }
				DateParam    = $dateParam
				Value        = $dateValue
				PlannedState = if ($null -eq $runFlag) { $dateValue } elseif ($runFlag) { $dateValue } else { $false }
			}
		}
		'Choice'
		{
			$selection = [string](Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Selection')

			return [pscustomobject]@{
				Function     = $functionName
				Type         = 'Choice'
				Selection    = $selection
				PlannedState = $selection
			}
		}
		'NumericRange'
		{
			$rawValue = $null
			if (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'Value')
			{
				$rawValue = Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'Value'
			}
			elseif (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'NumericValue')
			{
				$rawValue = Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'NumericValue'
			}
			elseif ((Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'ACValue') -or (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'DCValue'))
			{
				$rawValue = [ordered]@{
					ACValue = if (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'ACValue') { Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'ACValue' } else { $null }
					DCValue = if (Test-TweakManifestEntryField -Entry $RunListItem -FieldName 'DCValue') { Get-TweakManifestEntryValue -Entry $RunListItem -FieldName 'DCValue' } else { $null }
				}
			}

			$acValue = $null
			$dcValue = $null
			if ($rawValue -is [System.Collections.IDictionary])
			{
				if ($rawValue.Contains('ACValue'))
				{
					$acValue = $rawValue['ACValue']
				}
				if ($rawValue.Contains('DCValue'))
				{
					$dcValue = $rawValue['DCValue']
				}
			}
			elseif ($rawValue -is [pscustomobject])
			{
				if ($rawValue.PSObject.Properties['ACValue'])
				{
					$acValue = $rawValue.ACValue
				}
				if ($rawValue.PSObject.Properties['DCValue'])
				{
					$dcValue = $rawValue.DCValue
				}
			}

			$numericValue = if ($null -ne $acValue) { $acValue } else { $rawValue }
			$plannedState = if ($null -ne $dcValue -or $null -ne $acValue) { [ordered]@{ ACValue = $acValue; DCValue = if ($null -ne $dcValue) { $dcValue } else { $acValue } } } else { $numericValue }

			return [pscustomobject]@{
				Function     = $functionName
				Type         = 'NumericRange'
				Value        = $rawValue
				NumericValue = $numericValue
				ACValue      = $acValue
				DCValue      = $dcValue
				PlannedState = $plannedState
			}
		}
		default
		{
			return [pscustomobject]@{
				Function     = $functionName
				Type         = $typeValue
				PlannedState = $null
			}
		}
	}
}

