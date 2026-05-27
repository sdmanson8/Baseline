<#
    .SYNOPSIS
    Build the Baseline launcher executable.

    .DESCRIPTION
    Builds the Windows PowerShell 5.1 in-process launcher and optionally copies
    the resulting Baseline.exe to the repository root.
#>

[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [switch]$CopyToRepoRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$projectPath = Join-Path $repoRoot 'Launcher/RunLauncher.csproj'
$manifestScript = Join-Path $repoRoot 'Tools/New-ModuleIntegrityManifest.ps1'
$buildPath = Join-Path $repoRoot '.artifacts/launcher-build'

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf))
{
    throw "Launcher project not found: $projectPath"
}

if (-not (Test-Path -LiteralPath $manifestScript -PathType Leaf))
{
    throw "Module integrity manifest generator not found: $manifestScript"
}

Write-Host "Refreshing module integrity manifest..." -ForegroundColor Cyan
& $manifestScript

$buildArgs = @(
    'build',
    $projectPath,
    '-c', $Configuration,
    '-f', 'net48',
    '-o', $buildPath
)

Write-Host "Building launcher..." -ForegroundColor Cyan
& dotnet @buildArgs
if ($LASTEXITCODE -ne 0)
{
    throw "dotnet build failed with exit code $LASTEXITCODE"
}

$builtExe = Join-Path $buildPath 'Baseline.exe'
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf))
{
    throw "Build completed but Baseline.exe was not found at: $builtExe"
}

<#
    .SYNOPSIS
#>

function Get-PeMachine
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try
    {
        $reader = [System.IO.BinaryReader]::new($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        return $reader.ReadUInt16()
    }
    finally
    {
        $stream.Dispose()
    }
}

$machine = Get-PeMachine -Path $builtExe
if ($machine -ne 0x014C)
{
    throw ("Launcher build produced an unexpected PE machine 0x{0:X4} for {1}. Expected AnyCPU/IL-only (0x014C)." -f $machine, $builtExe)
}

if ($CopyToRepoRoot)
{
    $repoExe = Join-Path $repoRoot 'Baseline.exe'
    Copy-Item -LiteralPath $builtExe -Destination $repoExe -Force
    Write-Host "Copied launcher to: $repoExe" -ForegroundColor Green
}

Write-Host "Build output: $builtExe" -ForegroundColor Green
