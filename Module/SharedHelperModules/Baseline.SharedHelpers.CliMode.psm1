<#
    .SYNOPSIS
    Module wrapper for CliMode.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'CliMode.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Resolve-BaselineCliIntent'
    'Get-BaselineHeadlessExitCode'
    'Get-BaselinePresetCatalog'
    'Format-BaselinePresetCatalog'
    'Resolve-BaselineCliLogPath'
)

Export-ModuleMember -Function $ExportedFunctions





