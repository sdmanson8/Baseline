<#
    .SYNOPSIS
    Module wrapper for GameMode.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'GameMode.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Get-GameModeAllowlist'
    'Write-GameModeDataWarning'
    'Read-GameModeJsonDataFile'
    'Get-GameModeReviewedCrossCategoryAllowlist'
    'Import-GameModeAllowlistData'
    'Import-GameModeAdvancedData'
    'Get-GameModeAdvancedFunctions'
    'Test-GameModeAdvancedProfileDefaultSelection'
    'Resolve-GameModeAllowlistToggleParam'
    'Get-GameModeEntryScopeCategory'
    'Test-GameModeAllowlistEntryReviewed'
    'Test-GameModeProfileDefaultEligible'
    'Test-GameModeManifestDefaultEnabled'
    'Import-GameModeProfileData'
    'Get-GameModeProfileDefinitions'
    'Get-GameModeDecisionPromptKeyCatalog'
    'Test-GameModeProfileDefaultSelection'
    'Resolve-GameModeDecisionToggleParam'
    'Test-GameModeDecisionPromptRequired'
    'Get-GameModeDecisionPromptDefinition'
    'Get-GameModeDecisionPromptDefinitions'
    'Merge-GameModeSelectionState'
    'Get-GameModeSelectionSet'
    'Get-GameModeDecisionOverridesText'
    'Get-GameModeProfilePlan'
    'Get-GameModeProfileCommandList'
    'Resolve-ValidatedGameModeDecisionOverrides'
)

Export-ModuleMember -Function $ExportedFunctions





