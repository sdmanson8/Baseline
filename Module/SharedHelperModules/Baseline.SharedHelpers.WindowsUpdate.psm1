<#
    .SYNOPSIS
    Module wrapper for WindowsUpdate.Helpers.ps1.

    .DESCRIPTION
    Exposes Windows Update Agent helper functions through a dedicated module boundary.
#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'WindowsUpdate.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Get-WindowsUpdateList'
    'Install-WindowsSecurityUpdates'
    'Download-WindowsUpdates'
    'Install-WindowsUpdates'
    'Get-WindowsUpdateStatus'
    'Get-WindowsUpdateCompliance'
    'Invoke-BaselineWindowsUpdateScheduledRun'
    'Get-WindowsUpdateHistory'
)

Export-ModuleMember -Function $ExportedFunctions
