<#
    .SYNOPSIS
    Module wrapper for AuditTrail.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'AuditTrail.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Get-AuditLogPath'
    'Get-BaselineAuditRetentionDays'
    'Get-BaselineAuditRetentionCutoff'
    'Invoke-BaselineAuditRetentionPolicy'
    'Write-AuditRecord'
    'Get-AuditLog'
    'Export-AuditReport'
    'Clear-AuditLog'
    'Get-BaselineAuditRetentionPolicyThreshold'
    'Test-BaselineAuditRetentionBelowPolicy'
    'Get-BaselineAuditRetentionPolicyWarning'
    'Test-BaselineAuditRetentionTaskExecution'
    'Get-BaselineAuditRetentionReport'
)

Export-ModuleMember -Function $ExportedFunctions





