# State capture helper slice for Baseline.
# Provides system state snapshot capture, comparison, and persistence for
# tweaks tracked by the manifest system.
#
# Dependencies (loaded earlier in SharedHelpers.psm1):
#   Get-TweakManifestEntryValue, Test-TweakManifestEntryField (Manifest.Helpers.ps1)
#   Get-OSInfo, Get-WindowsVersionData (Environment.Helpers.ps1)

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

function New-SystemStateSnapshot
{
	<# .SYNOPSIS Captures a full system state snapshot by evaluating Detect scriptblocks across the manifest. #>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[array]$Manifest,

		[string]$CategoryFilter = $null
	)

	$entries = [System.Collections.ArrayList]::new()
	$timestamp = [datetime]::UtcNow.ToString('o')

	$osVersionString = $null
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
			$osVersionString = 'Unknown'
		}
	}

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
			$valuesMatch = [string]$beforeValue -eq [string]$afterValue
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

	$snapshot = $rawJson | ConvertFrom-Json -ErrorAction Stop

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
