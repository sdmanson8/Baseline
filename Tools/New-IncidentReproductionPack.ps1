<#
    .SYNOPSIS
    Generates a Baseline incident reproduction pack from a support bundle.

    .DESCRIPTION
    Reads the support bundle metadata, preflight report, compliance report, and
    recent audit log entries, then writes a compact incident reproduction pack
    containing structured JSON and a human-readable markdown summary.

    .EXAMPLE
    powershell -File .\Tools\New-IncidentReproductionPack.ps1 -SupportBundlePath .\Bundle.zip
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SupportBundlePath,

    [string]$OutputDirectory,

    [string]$IncidentId
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path $repoRoot 'Module\Baseline.psd1'
Import-Module -LiteralPath $modulePath -Force -ErrorAction Stop

New-BaselineIncidentReproductionPack -SupportBundlePath $SupportBundlePath -OutputDirectory $OutputDirectory -IncidentId $IncidentId
