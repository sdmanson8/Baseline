<#
	.SYNOPSIS
	Validate tweak metadata files under Module/Data.

	.DESCRIPTION
	Checks that JSON payloads load successfully, required entry fields exist,
	duplicate Name|Function keys are not present across files, and each
	SourceRegion points at a real region module that actually defines the
	declared function.

	.EXAMPLE
	pwsh -File .\Tools\Validate-ManifestData.ps1
#>

[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot 'Module'

if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container))
{
	throw "Module directory not found under: $repoRoot"
}

$dataDir = Join-Path $moduleRoot 'Data'
$regionDir = Join-Path $moduleRoot 'Regions'

if (-not (Test-Path -LiteralPath $dataDir))
{
	throw "Data directory not found: $dataDir"
}

if (-not (Test-Path -LiteralPath $regionDir))
{
	throw "Region directory not found: $regionDir"
}

$issues = New-Object System.Collections.ArrayList
$entryKeys = @{}
$regionFunctions = @{}
$totalEntries = 0
$dataFileCount = 0

foreach ($regionFile in (Get-ChildItem -LiteralPath $regionDir -Filter '*.psm1' -File | Sort-Object BaseName))
{
	$regionName = $regionFile.BaseName
	$rawContent = Get-Content -LiteralPath $regionFile.FullName -Raw -Encoding UTF8
	$functionMatches = [regex]::Matches($rawContent, '(?im)^\s*function\s+([A-Za-z0-9_.-]+)\b')
	$functionNames = @(
		$functionMatches |
			ForEach-Object { $_.Groups[1].Value } |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
			Sort-Object -Unique
	)
	$regionFunctions[$regionName] = $functionNames
}

foreach ($dataFile in (Get-ChildItem -LiteralPath $dataDir -Filter '*.json' -File | Sort-Object Name))
{
	$dataFileCount++

	try
	{
		$payload = Get-Content -LiteralPath $dataFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'InvalidJson'
			File = $dataFile.Name
			Entry = $null
			Message = $_.Exception.Message
		})
		continue
	}

	if (-not $payload.PSObject.Properties['Entries'])
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'MissingEntries'
			File = $dataFile.Name
			Entry = $null
			Message = 'Top-level Entries array is missing.'
		})
		continue
	}

	$entryIndex = 0
	foreach ($entry in @($payload.Entries))
	{
		$entryIndex++
		if (-not $entry)
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'NullEntry'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = 'Encountered a null entry in the manifest.'
			})
			continue
		}

		$totalEntries++
		$name = [string]$entry.Name
		$functionName = [string]$entry.Function
		$typeName = [string]$entry.Type
		$sourceRegion = if ($entry.PSObject.Properties['SourceRegion']) { [string]$entry.SourceRegion } else { '' }

		foreach ($field in @(
			[PSCustomObject]@{ Name = 'Name'; Value = $name },
			[PSCustomObject]@{ Name = 'Function'; Value = $functionName },
			[PSCustomObject]@{ Name = 'Type'; Value = $typeName },
			[PSCustomObject]@{ Name = 'SourceRegion'; Value = $sourceRegion }
		))
		{
			if ([string]::IsNullOrWhiteSpace([string]$field.Value))
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingField'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "Required field '$($field.Name)' is missing."
				})
			}
		}

		# Validate metadata fields exist (Risk, Tags, Impact, Safe, RequiresRestart, WhyThisMatters)
		foreach ($metaField in @('Risk', 'Tags', 'Impact', 'Safe', 'RequiresRestart', 'WhyThisMatters'))
		{
			if (-not $entry.PSObject.Properties[$metaField])
			{
				[void]$issues.Add([PSCustomObject]@{
					Type = 'MissingMetadata'
					File = $dataFile.Name
					Entry = $entryIndex
					Message = "Metadata field '$metaField' is missing on '$name'."
				})
			}
		}

		if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($functionName))
		{
			$key = '{0}|{1}' -f $name.Trim(), $functionName.Trim()
			if (-not $entryKeys.ContainsKey($key))
			{
				$entryKeys[$key] = New-Object System.Collections.ArrayList
			}

			[void]$entryKeys[$key].Add(('{0}#Entry{1}' -f $dataFile.Name, $entryIndex))
		}

		if ([string]::IsNullOrWhiteSpace($sourceRegion))
		{
			continue
		}

		if (-not $regionFunctions.ContainsKey($sourceRegion))
		{
			[void]$issues.Add([PSCustomObject]@{
				Type = 'MissingRegionModule'
				File = $dataFile.Name
				Entry = $entryIndex
				Message = "SourceRegion '$sourceRegion' does not match any file in Module/Regions."
			})
			continue
		}

		if (-not [string]::IsNullOrWhiteSpace($functionName) -and ($regionFunctions[$sourceRegion] -notcontains $functionName))
		{
			$otherOwners = @(
				$regionFunctions.GetEnumerator() |
					Where-Object { $_.Key -ne $sourceRegion -and $_.Value -contains $functionName } |
					Select-Object -ExpandProperty Key
			)

			[void]$issues.Add([PSCustomObject]@{
				Type = if ($otherOwners.Count -gt 0) { 'OwnershipDrift' } else { 'MissingFunction' }
				File = $dataFile.Name
				Entry = $entryIndex
				Message = if ($otherOwners.Count -gt 0) {
					"Function '$functionName' is not defined in SourceRegion '$sourceRegion'. Found in: $($otherOwners -join ', ')."
				}
				else {
					"Function '$functionName' is not defined in SourceRegion '$sourceRegion' or any other region module."
				}
			})
		}
	}
}

foreach ($entryKey in $entryKeys.GetEnumerator() | Sort-Object Key)
{
	$locations = @($entryKey.Value | Sort-Object -Unique)
	if ($locations.Count -gt 1)
	{
		[void]$issues.Add([PSCustomObject]@{
			Type = 'DuplicateEntry'
			File = $null
			Entry = $null
			Message = "Duplicate manifest key '$($entryKey.Key)' found in: $($locations -join ', ')."
		})
	}
}

if ($issues.Count -gt 0)
{
	Write-Host ''
	Write-Host 'Manifest validation failed:' -ForegroundColor Red
	foreach ($issue in @($issues))
	{
		$location = if ($issue.File) {
			if ($null -ne $issue.Entry) { "$($issue.File) entry $($issue.Entry)" } else { $issue.File }
		}
		else {
			'global'
		}
		Write-Host ("- [{0}] {1}: {2}" -f $issue.Type, $location, $issue.Message) -ForegroundColor Yellow
	}
	Write-Host ''
	exit 1
}

Write-Host ("Validated {0} data file(s), {1} entry(s), and {2} region module(s)." -f $dataFileCount, $totalEntries, $regionFunctions.Count) -ForegroundColor Green
Write-Host 'No duplicate manifest keys, orphaned SourceRegion values, or region ownership drift found.' -ForegroundColor Green
