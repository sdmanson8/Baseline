# Preset helpers for Baseline.
# Normalize non-interactive preset names and prepare command sets.

<#
    .SYNOPSIS
#>
function ConvertTo-HeadlessPresetName
{
	<# .SYNOPSIS Normalizes a preset name string to a standard value (Minimal, Basic, Balanced, Advanced). #>
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$PresetName
	)

	$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
	$normalizedPresetName = $normalizedPresetName.Trim()
	if ($normalizedPresetName -notmatch '^[A-Za-z0-9_.-]+$')
	{
		throw ("Invalid preset token '{0}'. Use letters, numbers, dots, underscores, or hyphens only." -f $normalizedPresetName)
	}

	if ($normalizedPresetName -match '^(?<name>.+?)\.(json|txt)$')
	{
		$normalizedPresetName = $Matches['name']
	}

	switch -Regex ($normalizedPresetName)
	{
		'^\s*minimal\s*$'                                                          { return 'Minimal' }
		'^\s*(light|conservative)\s*$'                                             { return 'Minimal' }
		'^\s*(basic|safe)\s*$'                                                     { return 'Basic' }
		'^\s*balanced\s*$'                                                         { return 'Balanced' }
		'^\s*(gaming|game|gaming.only|optimized.for.gaming)\s*$'                   { return 'Balanced' }
		'^\s*(advanced|aggressive)\s*$'                                            { return 'Advanced' }
		'^\s*(extreme|all.on)\s*$'                                                 { return 'Advanced' }
		default                                                                    { throw "Unknown preset name '$normalizedPresetName'. Valid presets: Minimal (alias: Light), Basic (alias: Safe), Balanced (alias: Gaming), Advanced (alias: Extreme)." }
	}
}

<#
    .SYNOPSIS
#>
function Resolve-HeadlessEnvironmentPreset
{
	<# .SYNOPSIS Validates and normalizes BASELINE_PRESET for headless startup. #>
	param (
		[string]$EnvironmentPreset = $env:BASELINE_PRESET
	)

	if ([string]::IsNullOrWhiteSpace($EnvironmentPreset))
	{
		return $null
	}

	return (ConvertTo-HeadlessPresetName -PresetName $EnvironmentPreset)
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetCommandFunctionName
{
	param ([string]$CommandLine)

	if ([string]::IsNullOrWhiteSpace([string]$CommandLine))
	{
		return $null
	}

	$trimmed = [string]$CommandLine.Trim()
	if ($trimmed.StartsWith('!'))
	{
		$trimmed = $trimmed.Substring(1).TrimStart()
	}

	if ([string]::IsNullOrWhiteSpace($trimmed))
	{
		return $null
	}

	$functionName = ($trimmed -split '\s+', 2)[0].Trim()
	if ([string]::IsNullOrWhiteSpace($functionName))
	{
		return $null
	}

	return $functionName
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetEntryFieldValue
{
	param (
		[AllowNull()][object]$Entry,
		[Parameter(Mandatory = $true)]
		[string]$FieldName
	)

	if ($null -eq $Entry)
	{
		return $null
	}

	if ($Entry -is [System.Collections.IDictionary])
	{
		if ($Entry.Contains($FieldName))
		{
			return $Entry[$FieldName]
		}

		return $null
	}

	if ($Entry.PSObject -and $Entry.PSObject.Properties[$FieldName])
	{
		return $Entry.$FieldName
	}

	return $null
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetIncludedFunctionSet
{
	if ($Global:HeadlessPresetIncludedFunctionNames -is [System.Collections.Generic.HashSet[string]])
	{
		return $Global:HeadlessPresetIncludedFunctionNames
	}

	$Global:HeadlessPresetIncludedFunctionNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	return $Global:HeadlessPresetIncludedFunctionNames
}

<#
    .SYNOPSIS
#>
function Set-HeadlessPresetIncludedFunctionSet
{
	param (
		[string[]]$FunctionNames = @()
	)

	if ($Global:HeadlessPresetIncludedFunctionNames -isnot [System.Collections.Generic.HashSet[string]])
	{
		$Global:HeadlessPresetIncludedFunctionNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}

	$includedFunctions = $Global:HeadlessPresetIncludedFunctionNames
	$includedFunctions.Clear()

	foreach ($functionName in @($FunctionNames))
	{
		if ([string]::IsNullOrWhiteSpace([string]$functionName))
		{
			continue
		}

		[void]$includedFunctions.Add(([string]$functionName).Trim())
	}
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetIncludedTweakLibraryPathSet
{
	if ($Global:HeadlessPresetIncludedTweakLibraryPaths -is [System.Collections.Generic.List[string]])
	{
		return $Global:HeadlessPresetIncludedTweakLibraryPaths
	}

	$Global:HeadlessPresetIncludedTweakLibraryPaths = [System.Collections.Generic.List[string]]::new()
	return $Global:HeadlessPresetIncludedTweakLibraryPaths
}

<#
    .SYNOPSIS
#>
function Set-HeadlessPresetIncludedTweakLibraryPathSet
{
	param (
		[string[]]$IncludePaths = @()
	)

	if ($Global:HeadlessPresetIncludedTweakLibraryPaths -isnot [System.Collections.Generic.List[string]])
	{
		$Global:HeadlessPresetIncludedTweakLibraryPaths = [System.Collections.Generic.List[string]]::new()
	}

	$includedPaths = $Global:HeadlessPresetIncludedTweakLibraryPaths
	$includedPaths.Clear()
	$seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($includePath in @($IncludePaths))
	{
		if ([string]::IsNullOrWhiteSpace([string]$includePath))
		{
			continue
		}

		$normalizedIncludePath = ([string]$includePath).Trim()
		if ($seenPaths.Add($normalizedIncludePath))
		{
			[void]$includedPaths.Add($normalizedIncludePath)
		}
	}
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetValidFunctionSet
{
	param (
		[string]$ModuleRoot
	)

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$dataDirectory = Join-Path -Path $resolvedRoot -ChildPath 'Data'
	if (-not (Test-Path -LiteralPath $dataDirectory -PathType Container))
	{
		throw "Manifest data directory was not found: $dataDirectory"
	}

	$presetDirectory = Join-Path -Path $dataDirectory -ChildPath 'Presets'
	$resolvedPresetDirectory = if (Test-Path -LiteralPath $presetDirectory -PathType Container)
	{
		[System.IO.Path]::GetFullPath($presetDirectory)
	}
	else
	{
		$null
	}

	$validFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($dataFile in (Get-ChildItem -LiteralPath $dataDirectory -Filter '*.json' -File -Recurse | Sort-Object FullName))
	{
		$resolvedDataFilePath = [System.IO.Path]::GetFullPath($dataFile.FullName)
		if ($resolvedPresetDirectory -and $resolvedDataFilePath.StartsWith($resolvedPresetDirectory, [System.StringComparison]::OrdinalIgnoreCase))
		{
			continue
		}

		$rawJson = Get-Content -LiteralPath $resolvedDataFilePath -Raw -ErrorAction Stop
		if ([string]::IsNullOrWhiteSpace($rawJson))
		{
			continue
		}

		try
		{
			$payload = $rawJson | ConvertFrom-BaselineJson -Depth 12 -ErrorAction Stop
		}
		catch
		{
			throw "Manifest data file '$resolvedDataFilePath' could not be parsed while validating presets: $($_.Exception.Message)"
		}

		if (-not $payload -or -not $payload.PSObject.Properties['Entries'])
		{
			continue
		}

		foreach ($entry in @($payload.Entries))
		{
			if (-not $entry -or -not $entry.PSObject.Properties['Function'])
			{
				continue
			}

			$functionName = [string]$entry.Function
			if ([string]::IsNullOrWhiteSpace($functionName))
			{
				continue
			}

			[void]$validFunctions.Add($functionName.Trim())
		}
	}

	foreach ($functionName in @(Get-HeadlessPresetIncludedFunctionSet))
	{
		if ([string]::IsNullOrWhiteSpace([string]$functionName))
		{
			continue
		}

		[void]$validFunctions.Add(([string]$functionName).Trim())
	}

	return $validFunctions
}

<#
    .SYNOPSIS
#>
function Assert-HeadlessPresetCommandListValid
{
	param (
		[Parameter(Mandatory = $true)]
		[string[]]$CommandList,

		[Parameter(Mandatory = $true)]
		[string]$PresetPath,

		[string]$ModuleRoot,

		[switch]$WarningOnly
	)

	$validFunctions = Get-HeadlessPresetValidFunctionSet -ModuleRoot $ModuleRoot
	$invalidEntries = [System.Collections.Generic.List[string]]::new()

	foreach ($commandLine in @($CommandList))
	{
		if ([string]::IsNullOrWhiteSpace([string]$commandLine))
		{
			continue
		}

		$trimmed = [string]$commandLine.Trim()
		$functionName = Get-HeadlessPresetCommandFunctionName -CommandLine $trimmed
		if ([string]::IsNullOrWhiteSpace($functionName) -or $validFunctions.Contains($functionName))
		{
			continue
		}

		[void]$invalidEntries.Add(("'{0}' in '{1}'" -f $functionName, $trimmed))
	}

	if ($invalidEntries.Count -eq 0)
	{
		return
	}

	$message = "Preset '$PresetPath' contains unknown region entry point(s): {0}. Every preset command must start with a Function defined in Module/Data manifests or an included tweak library." -f ($invalidEntries -join ', ')
	if ($WarningOnly)
	{
		Write-Warning $message
		return
	}

	throw $message
}

<#
    .SYNOPSIS
#>
function Get-HeadlessPresetCommandList
{
	<# .SYNOPSIS Loads the command list from a preset JSON or TXT file with ordered add/remove operations and deduplication. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$PresetName,

		[string]$ModuleRoot,

		[switch]$WarningOnly
	)

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$presetDirectory = Join-Path -Path $resolvedRoot -ChildPath (Join-Path 'Data' 'Presets')
	if (-not (Test-Path -LiteralPath $presetDirectory -PathType Container))
	{
		throw "Preset directory was not found: $presetDirectory"
	}
	$resolvedPresetDirectory = [System.IO.Path]::GetFullPath($presetDirectory)

	$presetPath = $null
	if (Test-Path -LiteralPath $PresetName -PathType Leaf)
	{
		$candidateFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PresetName -ErrorAction Stop).Path)
		$normalizedPresetDir = $resolvedPresetDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
		if (($candidateFullPath -ne $resolvedPresetDirectory) -and (-not $candidateFullPath.StartsWith($normalizedPresetDir, [System.StringComparison]::OrdinalIgnoreCase)))
		{
			throw "Preset file path must be within the preset directory ($presetDirectory). Received: $candidateFullPath"
		}
		$presetPath = $candidateFullPath
	}
	else
	{
		$normalizedPresetName = ConvertTo-HeadlessPresetName -PresetName $PresetName
		foreach ($extension in @('.json', '.txt'))
		{
			$candidatePath = Join-Path -Path $presetDirectory -ChildPath ("{0}{1}" -f $normalizedPresetName, $extension)
			if (Test-Path -LiteralPath $candidatePath -PathType Leaf)
			{
				$presetPath = $candidatePath
				break
			}
		}
	}

	if ([string]::IsNullOrWhiteSpace([string]$presetPath))
	{
		throw "Preset file '$PresetName.json' or '$PresetName.txt' was not found under Module\Data\Presets."
	}

	$commandList = [System.Collections.Generic.List[string]]::new()
	$commandIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)

	if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase))
	{
		$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
		if ($presetData -and $presetData.PSObject.Properties['Entries'])
		{
			$rawEntries = @($presetData.Entries)
		}
		elseif ($presetData -is [System.Collections.IEnumerable] -and -not ($presetData -is [string]))
		{
			$rawEntries = @($presetData)
		}
		else
		{
			$rawEntries = @()
		}
	}
	else
	{
		$rawEntries = [System.IO.File]::ReadAllLines($presetPath)
	}

	foreach ($rawEntry in $rawEntries)
	{
		if ($null -eq $rawEntry)
		{
			continue
		}

		if ($rawEntry -is [string])
		{
			$commandLine = [string]$rawEntry
			if ([string]::IsNullOrWhiteSpace($commandLine))
			{
				continue
			}

			$trimmed = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#'))
			{
				continue
			}

			if ($trimmed.StartsWith('!'))
			{
				$removedFunctionName = Get-HeadlessPresetCommandFunctionName -CommandLine $trimmed
				if ([string]::IsNullOrWhiteSpace($removedFunctionName))
				{
					throw "Preset '$presetPath' contains a removal directive without a function name: '$trimmed'."
				}

				for ($i = $commandList.Count - 1; $i -ge 0; $i--)
				{
					$currentFunctionName = Get-HeadlessPresetCommandFunctionName -CommandLine $commandList[$i]
					if (-not [string]::IsNullOrWhiteSpace($currentFunctionName) -and $currentFunctionName.Equals($removedFunctionName, [System.StringComparison]::OrdinalIgnoreCase))
					{
						$commandList.RemoveAt($i)
					}
				}

				$commandIndex.Clear()
				for ($i = 0; $i -lt $commandList.Count; $i++)
				{
					$currentFunctionName = Get-HeadlessPresetCommandFunctionName -CommandLine $commandList[$i]
					if ([string]::IsNullOrWhiteSpace($currentFunctionName))
					{
						continue
					}

					$commandIndex[$currentFunctionName] = $i
				}

				continue
			}

			$functionName = Get-HeadlessPresetCommandFunctionName -CommandLine $trimmed
			if ([string]::IsNullOrWhiteSpace($functionName))
			{
				continue
			}

			if ($commandIndex.ContainsKey($functionName))
			{
				$commandList[$commandIndex[$functionName]] = $trimmed
			}
			else
			{
				$commandIndex[$functionName] = $commandList.Count
				[void]$commandList.Add($trimmed)
			}

			continue
		}

		$actionValue = [string](Get-HeadlessPresetEntryFieldValue -Entry $rawEntry -FieldName 'Action')
		if ([string]::IsNullOrWhiteSpace($actionValue))
		{
			throw "Preset '$presetPath' contains a JSON entry object without Action."
		}

		switch -Regex ($actionValue.Trim())
		{
			'^(?i)add$'
			{
				$commandLine = [string](Get-HeadlessPresetEntryFieldValue -Entry $rawEntry -FieldName 'Command')
				if ([string]::IsNullOrWhiteSpace($commandLine))
				{
					throw "Preset '$presetPath' contains an Add action without a Command value."
				}

				$trimmed = $commandLine.Trim()
				if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('!'))
				{
					throw "Preset '$presetPath' contains an Add action with an invalid Command value: '$trimmed'."
				}

				$functionName = Get-HeadlessPresetCommandFunctionName -CommandLine $trimmed
				if ([string]::IsNullOrWhiteSpace($functionName))
				{
					throw "Preset '$presetPath' contains an Add action without a valid function name: '$trimmed'."
				}

				if ($commandIndex.ContainsKey($functionName))
				{
					$commandList[$commandIndex[$functionName]] = $trimmed
				}
				else
				{
					$commandIndex[$functionName] = $commandList.Count
					[void]$commandList.Add($trimmed)
				}
				continue
			}
			'^(?i)remove$'
			{
				$functionName = [string](Get-HeadlessPresetEntryFieldValue -Entry $rawEntry -FieldName 'Function')
				if ([string]::IsNullOrWhiteSpace($functionName))
				{
					throw "Preset '$presetPath' contains a Remove action without a Function value."
				}

				$functionName = $functionName.Trim()
				for ($i = $commandList.Count - 1; $i -ge 0; $i--)
				{
					$currentFunctionName = Get-HeadlessPresetCommandFunctionName -CommandLine $commandList[$i]
					if (-not [string]::IsNullOrWhiteSpace($currentFunctionName) -and $currentFunctionName.Equals($functionName, [System.StringComparison]::OrdinalIgnoreCase))
					{
						$commandList.RemoveAt($i)
					}
				}

				$commandIndex.Clear()
				for ($i = 0; $i -lt $commandList.Count; $i++)
				{
					$currentFunctionName = Get-HeadlessPresetCommandFunctionName -CommandLine $commandList[$i]
					if ([string]::IsNullOrWhiteSpace($currentFunctionName))
					{
						continue
					}

					$commandIndex[$currentFunctionName] = $i
				}

				continue
			}
			default
			{
				throw "Preset '$presetPath' contains an unsupported Action value '$actionValue'."
			}
		}
	}

	Assert-HeadlessPresetCommandListValid -CommandList $commandList.ToArray() -PresetPath $presetPath -ModuleRoot $resolvedRoot -WarningOnly:$WarningOnly

	return $commandList.ToArray()
}
