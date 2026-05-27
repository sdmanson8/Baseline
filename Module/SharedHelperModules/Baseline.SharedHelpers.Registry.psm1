<#
    .SYNOPSIS
    Module wrapper for Registry.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'Registry.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Set-Policy'
    'Get-CurrentWindowsUserSid'
    'ConvertTo-NativeRegistryPath'
    'ConvertTo-RegExeValueType'
    'Dismount-RegistryHive'
    'Mount-RegistryHive'
    'Test-RegistryValueEquivalent'
    'Set-RegistryValueSafe'
    'Remove-RegistryValueSafe'
    'ConvertTo-RegistryCompositeStringValue'
    'Set-RegistryCompositeStringValue'
    'Set-SystemTweaksRegistryValue'
    'Remove-SystemTweaksRegistryValue'
)

Export-ModuleMember -Function $ExportedFunctions





