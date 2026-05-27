<#
    .SYNOPSIS
    Module wrapper for OperatorPolicy.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'OperatorPolicy.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'New-BaselineOperatorPolicy'
    'Test-BaselineOperatorChangeWindow'
    'Test-BaselineKillSwitch'
    'Invoke-BaselineKillSwitch'
    'Clear-BaselineKillSwitch'
    'Test-BaselineOperatorRunPolicy'
    'Format-BaselineOperatorPolicyDecision'
)

Export-ModuleMember -Function $ExportedFunctions





