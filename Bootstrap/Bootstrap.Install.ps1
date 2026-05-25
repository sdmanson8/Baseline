<#
    .SYNOPSIS
    Run the verified Baseline installer payload.

    .DESCRIPTION
    Runs from inside the verified release zip after Bootstrap.ps1 has
    downloaded the release zip, verified its SHA-256 manifest, and extracted
    the payload. This script locates the setup executable, verifies its hash
    against the same release manifest, runs the installer, and launches the
    installed Baseline executable when available.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExtractRoot,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [string]$Repository = 'Baseline',

    [string]$Preset
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-BootstrapInstallCleanupWarning
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Warning ("Bootstrap installer cleanup: {0}" -f $Message)
}

$helpersPath = Join-Path $PSScriptRoot 'Helpers\Bootstrap.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helpersPath -PathType Leaf))
{
    throw "Verified bootstrap helper file was not found: $helpersPath"
}

. $helpersPath

$Preset = Resolve-BootstrapPreset -Preset $Preset

$setupExe = Find-BootstrapSetupExecutable -ExtractRoot $ExtractRoot
if (-not $setupExe)
{
    throw "Baseline-*-setup.exe was not found in the extracted archive under $ExtractRoot."
}

$setupHash = Assert-BootstrapReleaseAssetHash -ManifestPath $ManifestPath -AssetName ([System.IO.Path]::GetFileName($setupExe)) -FilePath $setupExe -Label 'Setup executable'
Write-Host "Verified SHA-256 for $([System.IO.Path]::GetFileName($setupExe)): $setupHash"

Write-Host "Running installer $setupExe..."
$setupProcess = Start-Process -FilePath $setupExe -PassThru

if (-not $setupProcess.WaitForExit([int][TimeSpan]::FromMinutes(30).TotalMilliseconds))
{
    try
    {
        $killTreeMethod = $setupProcess.GetType().GetMethod('Kill', [type[]]@([bool]))

        if ($killTreeMethod)
        {
            [void]$killTreeMethod.Invoke($setupProcess, @($true))
        }
        else
        {
            $taskkill = [System.Diagnostics.Process]::new()
            try
            {
                $taskkill.StartInfo.FileName = (Join-Path $env:SystemRoot 'System32\taskkill.exe')
                $taskkill.StartInfo.Arguments = ('/PID {0} /T /F' -f $setupProcess.Id)
                $taskkill.StartInfo.UseShellExecute = $false
                $taskkill.StartInfo.CreateNoWindow = $true
                [void]$taskkill.Start()
                if (-not $taskkill.WaitForExit(5000))
                {
                    try { $taskkill.Kill() } catch { Write-BootstrapInstallCleanupWarning ("taskkill cleanup process could not be stopped: {0}" -f $_.Exception.Message) }
                }
            }
            finally
            {
                try { $taskkill.Dispose() } catch { Write-BootstrapInstallCleanupWarning ("taskkill cleanup process could not be disposed: {0}" -f $_.Exception.Message) }
            }
        }
    }
    catch
    {
        Write-BootstrapInstallCleanupWarning ("setup process tree cleanup failed: {0}" -f $_.Exception.Message)
        try { $setupProcess.Kill() } catch { Write-BootstrapInstallCleanupWarning ("setup process fallback kill failed: {0}" -f $_.Exception.Message) }
    }

    throw 'Baseline setup timed out after 30 minutes.'
}

if ($setupProcess.ExitCode -ne 0)
{
    throw "Baseline installer exited with code $($setupProcess.ExitCode)."
}

$installedExe = Find-InstalledBaselineExecutable
if (-not $installedExe)
{
    throw "$Repository installer exited successfully, but no installed Baseline.exe was found in the default locations."
}

$previousPreset = $env:BASELINE_PRESET
$hadPreviousPreset = -not [string]::IsNullOrWhiteSpace([string]$previousPreset)
if (-not [string]::IsNullOrWhiteSpace([string]$Preset))
{
    $env:BASELINE_PRESET = $Preset
    Write-Host "Launching $installedExe with preset '$Preset'..."
}
else
{
    Write-Host "Launching $installedExe..."
}

try
{
    & $installedExe
}
finally
{
    if ($hadPreviousPreset)
    {
        $env:BASELINE_PRESET = $previousPreset
    }
    else
    {
        Remove-Item -Path Env:\BASELINE_PRESET -ErrorAction SilentlyContinue
    }
}
