<#
    .SYNOPSIS
    Generate Module/integrity.manifest.json — SHA-256 hashes of every Baseline
    module script file. Used by the loader when BASELINE_INTEGRITY_MODE is set
    to Strict or Audit.

    .DESCRIPTION
    Walks the Module/ tree and records SHA-256 hashes of every .psm1, .psd1,
    and .ps1 file. The resulting manifest is consumed by
    Invoke-BaselineModuleIntegrityGate at module load. Run this after every
    intentional change to module source before publishing a release.

    .PARAMETER ModuleRoot
    Override the module directory to hash. Defaults to ../Module relative to
    this script.

    .PARAMETER OutputPath
    Override the manifest output location. Defaults to <ModuleRoot>/integrity.manifest.json.
#>
[CmdletBinding()]
param(
    [string]$ModuleRoot,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
if (-not $ModuleRoot)
{
    $ModuleRoot = Join-Path $repoRoot 'Module'
}
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).ProviderPath

$integrityHelper = Join-Path $ModuleRoot 'SharedHelpers/Integrity.Helpers.ps1'
if (-not (Test-Path -LiteralPath $integrityHelper -PathType Leaf))
{
    throw "Integrity helper not found at '$integrityHelper'."
}

. $integrityHelper

if (-not $OutputPath)
{
    $OutputPath = Get-BaselineIntegrityManifestPath -ModuleRoot $ModuleRoot
}

# A previous integrity.manifest.json must not pollute its own re-hash, so
# delete it before walking the tree.
if (Test-Path -LiteralPath $OutputPath -PathType Leaf)
{
    Remove-Item -LiteralPath $OutputPath -Force
}

$manifest = New-BaselineIntegrityManifest -ModuleRoot $ModuleRoot
$json = $manifest | ConvertTo-Json -Depth 8

[System.IO.File]::WriteAllText($OutputPath, $json + [System.Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote integrity manifest with {0} files: {1}" -f $manifest.fileCount, $OutputPath)
