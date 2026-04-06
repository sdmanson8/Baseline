<#
	.SYNOPSIS
	Validates generated low-risk preset files against manifest policy.

	.DESCRIPTION
	Generates the supported curated presets into a temporary directory and runs the
	manifest validator against those generated files so CI can catch generator drift
	without forcing the checked-in curated presets to be regenerated.

	.EXAMPLE
	pwsh -File .\Tools\Test-PresetGeneration.ps1
#>

[CmdletBinding()]
param (
	[string[]]$PresetNames = @('Minimal', 'Basic', 'Balanced')
)

$ErrorActionPreference = 'Stop'

$generatorPath = Join-Path $PSScriptRoot 'Generate-PresetFiles.ps1'
$validatorPath = Join-Path $PSScriptRoot 'Validate-ManifestData.ps1'
$tempOutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-preset-validation-{0}" -f ([guid]::NewGuid().ToString('n')))

New-Item -Path $tempOutputRoot -ItemType Directory -Force | Out-Null

try
{
	& $generatorPath -PresetNames $PresetNames -OutputDirectory $tempOutputRoot

	$missingGeneratedPresets = @(
		foreach ($presetName in @($PresetNames))
		{
			$normalizedPresetName = [System.IO.Path]::GetFileNameWithoutExtension(([string]$presetName).Trim())
			if ([string]::IsNullOrWhiteSpace($normalizedPresetName))
			{
				continue
			}

			$generatedPath = Join-Path $tempOutputRoot ("{0}.json" -f $normalizedPresetName)
			if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf))
			{
				$generatedPath
			}
		}
	)
	if ($missingGeneratedPresets.Count -gt 0)
	{
		throw ("Generator did not create the expected preset files: {0}" -f ($missingGeneratedPresets -join ', '))
	}

		& $validatorPath -PresetDirectory $tempOutputRoot -AllowPartialPresetDirectory

	# Write-Host: intentional — test/tooling console output
	Write-Host ("Generated preset validation passed for: {0}" -f ((@($PresetNames) | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension(([string]$_).Trim()) }) -join ', ')) -ForegroundColor Green

	# Golden-file comparison: generated output must match the checked-in curated presets.
	# Divergence means the generator no longer reflects curation intent.
	$canonicalPresetDir = Join-Path $PSScriptRoot '..\Module\Data\Presets'
	$totalDiff = 0
	foreach ($presetName in @($PresetNames))
	{
		$normalizedName = [System.IO.Path]::GetFileNameWithoutExtension(([string]$presetName).Trim())
		$generatedFile  = Join-Path $tempOutputRoot "$normalizedName.json"
		$canonicalFile  = Join-Path $canonicalPresetDir "$normalizedName.json"

		if (-not (Test-Path -LiteralPath $canonicalFile -PathType Leaf))
		{
			Write-Warning "Golden-file comparison: no checked-in preset found at $canonicalFile - skipping $normalizedName"
			continue
		}

		$generatedEntries = @((Get-Content -LiteralPath $generatedFile  -Raw | ConvertFrom-Json).Entries | ForEach-Object { [string]$_ })
		$canonicalEntries = @((Get-Content -LiteralPath $canonicalFile  -Raw | ConvertFrom-Json).Entries | ForEach-Object { [string]$_ })

		$onlyInGenerated = @($generatedEntries | Where-Object { $canonicalEntries -notcontains $_ })
		$onlyInCanonical = @($canonicalEntries | Where-Object { $generatedEntries -notcontains $_ })
		$diffCount       = $onlyInGenerated.Count + $onlyInCanonical.Count

		if ($diffCount -gt 0)
		{
			Write-Warning ("Golden-file diff [{0}]: {1} difference(s) - generator does not match checked-in preset" -f $normalizedName, $diffCount)
			if ($onlyInGenerated.Count -gt 0) { Write-Warning ("  Only in generated: {0}" -f ($onlyInGenerated -join ', ')) }
			if ($onlyInCanonical.Count -gt 0) { Write-Warning ("  Only in canonical: {0}" -f ($onlyInCanonical -join ', ')) }
			$totalDiff += $diffCount
		}
		else
		{
			Write-Host ("Golden-file match [{0}]: generated preset matches checked-in preset" -f $normalizedName) -ForegroundColor Green
		}
	}

	if ($totalDiff -gt 0)
	{
		throw ("Golden-file comparison: $totalDiff total difference(s) between generated and checked-in presets. Generator does not match curated presets.")
	}
}
finally
{
	if (Test-Path -LiteralPath $tempOutputRoot)
	{
		Remove-Item -LiteralPath $tempOutputRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}
