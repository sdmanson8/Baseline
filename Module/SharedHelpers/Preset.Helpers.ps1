# Preset helper slice for Baseline.
# Extracted from Baseline.ps1 - contains headless preset name normalization
# and preset command list loading for non-interactive execution paths.

function ConvertTo-HeadlessPresetName
{
	<# .SYNOPSIS Normalizes a preset name string to a standard value (Minimal, Basic, Balanced, Advanced). #>
	param (
		[Parameter(Mandatory = $false)]
		[string]
		$PresetName
	)

	$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
	$normalizedPresetName = [System.IO.Path]::GetFileNameWithoutExtension($normalizedPresetName.Trim())

	switch -Regex ($normalizedPresetName)
	{
		'^\s*minimal\s*$'               { return 'Minimal' }
		'^\s*balanced\s*$'              { return 'Balanced' }
		'^\s*(basic|safe)\s*$'          { return 'Basic' }
		'^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
		default                         { throw "Unknown preset name '$normalizedPresetName'. Valid presets: Minimal, Basic, Balanced, Advanced." }
	}
}

function Get-HeadlessPresetCommandList
{
	<# .SYNOPSIS Loads the command list from a preset JSON or TXT file with deduplication. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$PresetName,

		[string]$ModuleRoot
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
		$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
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
		$commandLine = [string]$rawEntry
		if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

		$trimmed = $commandLine.Trim()
		if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

		$functionName = ($trimmed -split '\s+', 2)[0].Trim()
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		if ($commandIndex.ContainsKey($functionName))
		{
			$commandList[$commandIndex[$functionName]] = $trimmed
		}
		else
		{
			$commandIndex[$functionName] = $commandList.Count
			[void]$commandList.Add($trimmed)
		}
	}

	return $commandList.ToArray()
}
