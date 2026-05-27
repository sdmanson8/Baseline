<#
    .SYNOPSIS
    Module wrapper for ConfigProfile.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'ConfigProfile.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'ConvertTo-ConfigurationProfileValueText'
    'New-ConfigurationProfile'
    'Export-ConfigurationProfile'
    'Export-BaselineFirstLogonCommandSnippet'
    'Import-ConfigurationProfile'
    'Import-ConfigurationProfileIncludeLibraries'
    'Test-ConfigurationProfileCompatibility'
    'Compare-ConfigurationProfiles'
    'Get-ProfileEntryComparisonKey'
    'ConvertFrom-PresetToProfile'
    'ConvertFrom-BaselineConfigProfileToRunList'
)

Export-ModuleMember -Function $ExportedFunctions





