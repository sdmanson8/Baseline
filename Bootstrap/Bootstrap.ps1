<#
    .SYNOPSIS
    Download and launch Baseline from GitHub.

    .DESCRIPTION
    This script is designed to be hosted at a raw GitHub URL and executed with
    a one-liner such as:

        iwr https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -UseBasicParsing | iex

    It queries the GitHub Releases API for the latest release (including
    pre-releases), downloads the release asset zip, extracts it to a temp
    folder, and launches the repo's root run.cmd entrypoint. When
    BASELINE_PRESET is set or -Preset is supplied, the preset is forwarded
    into the noninteractive runner.

    .NOTES
    SECURITY: This bootstrap uses pipe-to-IEX with no integrity verification
    (no hash check, signature validation, or certificate pinning). The download
    is protected by TLS 1.2 to GitHub over HTTPS, but a compromised DNS or TLS
    interception could serve modified code. For higher assurance, download the
    archive manually, verify the commit hash, and run Baseline.ps1 directly.
#>

[CmdletBinding()]
param(
    [string]$Owner = 'sdmanson8',
    [string]$Repository = 'Baseline',
    [string]$Preset,
    [string]$CacheRoot = (Join-Path $env:TEMP 'Baseline-Bootstrap')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Preset))
{
    $Preset = $env:BASELINE_PRESET
}

function Enable-Tls12
{
    try
    {
        # Ensure no prior script has disabled certificate validation (MITM risk).
        if ($null -ne [System.Net.ServicePointManager]::ServerCertificateValidationCallback)
        {
            Write-Warning "ServerCertificateValidationCallback was overridden by a prior script - resetting to default."
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        }

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
        TimeoutSec  = 30
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

    $resolvedCache = [System.IO.Path]::GetFullPath($CacheRoot)
    $resolvedTemp  = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedCache.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "CacheRoot must be under `$env:TEMP ($env:TEMP). Received: $CacheRoot"
    }

    if (Test-Path -LiteralPath $CacheRoot)
    {
        Remove-Item -LiteralPath $CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

    $archivePath = Join-Path $CacheRoot "$Repository.zip"
    $extractRoot = Join-Path $CacheRoot 'extract'

    # Resolve the latest release (including pre-releases) via the GitHub API.
    $apiUrl = "https://api.github.com/repos/$Owner/$Repository/releases"
    Write-Host "Querying GitHub releases..."
    $releasesJson = (New-Object System.Net.WebClient).DownloadString($apiUrl)
    $releases = $releasesJson | ConvertFrom-Json
    if (-not $releases -or $releases.Count -eq 0)
    {
        throw "No releases found at $apiUrl"
    }
    $latest = $releases | Where-Object { -not $_.draft } | Select-Object -First 1
    if (-not $latest)
    {
        throw "No non-draft releases found at $apiUrl"
    }

    # Prefer the uploaded .zip asset; fall back to the GitHub-generated zipball.
    $asset = $latest.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if ($asset)
    {
        $downloadUrl = $asset.browser_download_url
    }
    else
    {
        $downloadUrl = $latest.zipball_url
    }

    # Write-Host: intentional — bootstrap progress output
    Write-Host "Downloading $Repository $($latest.tag_name) from $downloadUrl"
    Invoke-DownloadFile -Uri $downloadUrl -OutFile $archivePath

    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

    $repoRoot = Get-RepositoryRoot -ExtractRoot $extractRoot
    $runCmd = Join-Path $repoRoot 'run.cmd'

    if (-not (Test-Path -LiteralPath $runCmd))
    {
        throw "run.cmd was not found in the extracted repository: $repoRoot"
    }

    $previousPreset = $env:BASELINE_PRESET
    $hadPreviousPreset = -not [string]::IsNullOrWhiteSpace([string]$previousPreset)
    if (-not [string]::IsNullOrWhiteSpace([string]$Preset))
    {
        $env:BASELINE_PRESET = $Preset
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Preset))
    {
        Write-Host "Launching Baseline headless run with preset '$Preset'..."
    }
    else
    {
        Write-Host "Launching Baseline..."
    }
    Push-Location $repoRoot
    try
    {
        & $runCmd
    }
    finally
    {
        Pop-Location
        if ($hadPreviousPreset)
        {
            $env:BASELINE_PRESET = $previousPreset
        }
        else
        {
            Remove-Item -Path Env:\BASELINE_PRESET -ErrorAction SilentlyContinue
        }
    }
}
catch
{
    Write-Error "Failed to bootstrap Baseline: $($_.Exception.Message)"
    throw
}
