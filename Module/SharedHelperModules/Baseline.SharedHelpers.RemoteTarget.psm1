<#
    .SYNOPSIS
    Module wrapper for RemoteTarget.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'RemoteTarget.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Get-BaselineRemoteCredentialScopeKey'
    'Get-BaselineRemoteSessionKey'
    'ConvertTo-BaselineRemoteTransportSettingsValue'
    'Get-BaselineRemoteTransportSettingsSignature'
    'New-BaselineRemoteSessionCacheEntry'
    'Test-BaselineRemoteSessionCacheEntry'
    'Remove-BaselineRemoteSessionCacheEntry'
    'Invoke-BaselineRemoteSessionCacheMaintenance'
    'Get-BaselineRemoteTargetTerminalState'
    'Get-BaselineRemoteTargetState'
    'New-BaselineRemoteTargetStateTransition'
    'Add-BaselineRemoteTargetStateTransition'
    'Clear-BaselineRemoteSessionCache'
    'Get-BaselineRemoteSession'
    'Get-BaselineRemoteSessionSummary'
    'Get-BaselineRemoteOrchestrationHistoryPath'
    'Get-BaselineRemoteFailureProfile'
    'New-BaselineRemoteAttemptRecord'
    'Get-BaselineRemoteRetryAnalytics'
    'Write-BaselineRemoteAttemptHistoryRecord'
    'Get-BaselineRemoteOrchestrationHistory'
    'Get-BaselineRemoteOrchestrationSummary'
    'Get-BaselineRemoteOrchestrationDetails'
    'Get-BaselineRemoteRunSummaries'
    'Get-BaselineRemoteTargetHealthPath'
    'Get-BaselineRemoteTargetHealth'
    'Update-BaselineRemoteTargetHealth'
    'Get-BaselineRemoteTargetFailureHistory'
    'Get-BaselineRemoteApprovalDecisionPath'
    'Write-BaselineRemoteApprovalDecision'
    'Get-BaselineRemoteApprovalDecisions'
    'Write-BaselineRemoteRolloutOutcome'
    'Get-BaselineRemoteRolloutOutcomes'
    'Get-BaselineRemoteOrchestrationDashboard'
    'Search-BaselineRemoteOrchestrationHistory'
    'Get-BaselineRemoteTargetLifecycleState'
    'Get-BaselineRemoteOrchestrationReconciliation'
    'Invoke-BaselineRemoteEntryWithRetry'
    'Invoke-BaselineRemoteRetryDelay'
    'Test-BaselineRemoteOrchestrationAllowed'
    'Write-BaselineRemoteOrchestrationRecord'
    'Write-BaselineRemoteOrchestrationSummaryRecord'
    'Get-BaselineRemoteResumeDirectory'
    'Get-BaselineRemoteResumeCheckpointPath'
    'Save-BaselineRemoteResumeCheckpoint'
    'Get-BaselineRemoteResumeCheckpoint'
    'Get-BaselineRemoteResumableRuns'
    'Clear-BaselineRemoteResumeCheckpoint'
    'Resolve-BaselineRemoteResumeTargets'
    'Resume-BaselineRemoteOrchestration'
    'Test-BaselineRemoteConnectivity'
    'Invoke-BaselineRemoteCompliance'
    'Invoke-BaselineRemoteApply'
)

Export-ModuleMember -Function $ExportedFunctions





