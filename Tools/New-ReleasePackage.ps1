<#
	.SYNOPSIS
	Create a clean Baseline release zip with the intended public structure.

	.DESCRIPTION
	Stages the public release files under a temporary `Baseline/` folder and
	creates a zip archive from that staged layout. By default the package keeps
	the public repo structure recognizable while excluding planning files such as
	`todo.md` and `docs/`.

	.EXAMPLE
	pwsh -File .\Tools\New-ReleasePackage.ps1

	.EXAMPLE
	pwsh -File .\Tools\New-ReleasePackage.ps1 -OutputDirectory .\dist -IncludeDocs
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[string]$OutputDirectory,
	[string]$Version,
	[string]$ArchiveName,
	[switch]$IncludeDocs,
	[switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleManifestPath = Join-Path $repoRoot 'Module/Baseline.psd1'

if ([string]::IsNullOrWhiteSpace($Version) -and (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf))
{
	$moduleManifest = Import-PowerShellDataFile -LiteralPath $moduleManifestPath
	if ($moduleManifest -and $moduleManifest.ModuleVersion)
	{
		$Version = [string]$moduleManifest.ModuleVersion
	}
}

if ([string]::IsNullOrWhiteSpace($Version))
{
	$Version = 'dev'
}

$resolvedOutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory))
{
	Join-Path $repoRoot 'dist'
}
elseif ([System.IO.Path]::IsPathRooted($OutputDirectory))
{
	$OutputDirectory
}
else
{
	Join-Path $repoRoot $OutputDirectory
}

if (-not (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container))
{
	New-Item -Path $resolvedOutputDirectory -ItemType Directory -Force | Out-Null
}

$resolvedArchiveName = if ([string]::IsNullOrWhiteSpace($ArchiveName))
{
	"Baseline-$Version.zip"
}
else
{
	$ArchiveName
}

$archivePath = Join-Path $resolvedOutputDirectory $resolvedArchiveName
if (Test-Path -LiteralPath $archivePath -PathType Leaf)
{
	if (-not $Force)
	{
		throw "Archive already exists: $archivePath. Re-run with -Force to overwrite it."
	}

	Remove-Item -LiteralPath $archivePath -Force -ErrorAction Stop
}

$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("BaselineRelease_{0}" -f ([System.Guid]::NewGuid().ToString('N')))
$packageRoot = Join-Path $stageRoot 'Baseline'
$publicPaths = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in @(
	'Baseline.ps1'
	'run.cmd'
	'README.md'
	'CHANGELOG.md'
	'LICENSE'
	'Assets'
	'Bootstrap'
	'Completion'
	'Localizations'
	'Module'
))
{
	[void]$publicPaths.Add($relativePath)
}

if ($IncludeDocs)
{
	[void]$publicPaths.Add('docs')
}

try
{
	New-Item -Path $packageRoot -ItemType Directory -Force | Out-Null

	foreach ($relativePath in $publicPaths)
	{
		$sourcePath = Join-Path $repoRoot $relativePath
		if (-not (Test-Path -LiteralPath $sourcePath))
		{
			throw "Required release path was not found: $sourcePath"
		}

		$destinationPath = Join-Path $packageRoot $relativePath
		$destinationParent = Split-Path -Path $destinationPath -Parent
		if (-not [string]::IsNullOrWhiteSpace($destinationParent) -and -not (Test-Path -LiteralPath $destinationParent -PathType Container))
		{
			New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
		}

		Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
	}

	Get-ChildItem -LiteralPath $packageRoot -Force -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -in @('.DS_Store', 'Thumbs.db') } |
		Remove-Item -Force -ErrorAction SilentlyContinue

	if ($PSCmdlet.ShouldProcess($archivePath, 'Create Baseline release package'))
	{
		Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal -Force
	}

	$archiveItem = Get-Item -LiteralPath $archivePath -ErrorAction Stop
	[pscustomobject]@{
		Path         = $archiveItem.FullName
		Version      = $Version
		SizeBytes    = [int64]$archiveItem.Length
		IncludesDocs = [bool]$IncludeDocs
	}
}
finally
{
	if (Test-Path -LiteralPath $stageRoot)
	{
		Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}
