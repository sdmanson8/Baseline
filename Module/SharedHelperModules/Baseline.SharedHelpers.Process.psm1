<#
    .SYNOPSIS
    Module wrapper for Process.Helpers.ps1.
#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'Process.Helpers.ps1'

if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

Export-ModuleMember -Function @(
    'Stop-BaselineProcessTree',
    'ConvertTo-BaselineWindowsProcessArgument',
    'ConvertTo-BaselineProcessArgumentString',
    'Invoke-BaselineProcess',
    'Invoke-UserLaunch'
)
