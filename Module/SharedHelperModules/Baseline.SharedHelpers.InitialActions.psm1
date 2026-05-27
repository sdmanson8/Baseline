<#
    .SYNOPSIS
    Module wrapper for InitialActions.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'InitialActions.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Get-BaselineStartupLabel'
    'Test-BaselineUnsupportedHost'
    'Test-BaselineHostsEntry'
    'Get-BaselineHostsCandidateEntries'
    'Test-BaselineHostsDownloadSuspect'
    'Get-BaselineDefenderProductStateCode'
    'Test-BaselineDefenderActiveByProductState'
    'Test-BaselineDefenderFullyEnabled'
    'Test-BaselineDefenderServicesHealthy'
    'Resolve-BaselineSettingsAppsFeaturesHealthAssessment'
    'Resolve-BaselineScreenSnippingHealthAssessment'
    'Resolve-BaselineHostsCleanupPolicy'
    'Resolve-BaselineHostTaintAssessment'
)

Export-ModuleMember -Function $ExportedFunctions





