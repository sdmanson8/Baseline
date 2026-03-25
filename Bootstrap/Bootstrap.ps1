<#
    .SYNOPSIS
    Download and launch Baseline from GitHub.

    .DESCRIPTION
    This script is designed to be hosted at a raw GitHub URL and executed with
    a one-liner such as:

        iwr https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex

    It downloads the latest branch archive, extracts it to a temp folder, and
    launches the repo's root run.cmd entrypoint.
#>

[CmdletBinding()]
param(
    [string]$Owner = 'sdmanson8',
    [string]$Repository = 'Baseline',
    [string]$Branch = 'main',
    [string]$CacheRoot = (Join-Path $env:TEMP 'Baseline-Bootstrap')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Enable-Tls12
{
    try
    {
        $current = [System.Net.ServicePointManager]::SecurityProtocol
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (($current -band $tls12) -ne $tls12)
        {
            [System.Net.ServicePointManager]::SecurityProtocol = $current -bor $tls12
        }
    }
    catch { $null = $_ }
}

function Invoke-DownloadFile
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    $invokeParams = @{
        Uri         = $Uri
        OutFile     = $OutFile
        ErrorAction = 'Stop'
    }

    $iwrCommand = Get-Command Invoke-WebRequest -ErrorAction Stop
    if ($iwrCommand.Parameters.ContainsKey('UseBasicParsing'))
    {
        $invokeParams.UseBasicParsing = $true
    }

    Invoke-WebRequest @invokeParams | Out-Null
}

function Get-RepositoryRoot
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractRoot
    )

    $repoRoot = Get-ChildItem -Path $ExtractRoot -Directory -ErrorAction Stop | Select-Object -First 1
    if (-not $repoRoot)
    {
        throw 'The extracted archive did not contain a repository root folder.'
    }

    return $repoRoot.FullName
}

try
{
    Enable-Tls12

    if (Test-Path -LiteralPath $CacheRoot)
    {
        Remove-Item -LiteralPath $CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

    $archivePath = Join-Path $CacheRoot "$Repository.zip"
    $extractRoot = Join-Path $CacheRoot 'extract'
    $downloadUrl = "https://github.com/$Owner/$Repository/archive/refs/heads/$Branch.zip"

    Write-Host "Downloading $Repository from $downloadUrl"
    Invoke-DownloadFile -Uri $downloadUrl -OutFile $archivePath

    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

    $repoRoot = Get-RepositoryRoot -ExtractRoot $extractRoot
    $runCmd = Join-Path $repoRoot 'run.cmd'

    if (-not (Test-Path -LiteralPath $runCmd))
    {
        throw "run.cmd was not found in the extracted repository: $repoRoot"
    }

    Write-Host "Launching Baseline..."
    Push-Location $repoRoot
    try
    {
        & $runCmd
    }
    finally
    {
        Pop-Location
    }
}
catch
{
    Write-Error "Failed to bootstrap Baseline: $($_.Exception.Message)"
    throw
}
