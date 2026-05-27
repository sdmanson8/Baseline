Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:GroupPolicyHelpersContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/SharedHelpers/GroupPolicy.Helpers.ps1')
}

Describe 'GroupPolicy helper swallowed-exception routing' {
    It 'routes environment and policy lookup failures through Write-SwallowedException' {
        $script:GroupPolicyHelpersContent | Should -Match "Source 'GroupPolicy\.GetBaselineGpoPolicyValueState\.GetValueKind'"
        $script:GroupPolicyHelpersContent | Should -Match "Source 'GroupPolicy\.GetBaselineGpoPolicyValueState\.LoadValue'"
        $script:GroupPolicyHelpersContent | Should -Match "Source 'GroupPolicy\.GetBaselineGpoEnvironmentSummary\.LoadComputerSystem'"
        $script:GroupPolicyHelpersContent | Should -Match "Source 'GroupPolicy\.GetBaselineGpoEnvironmentSummary\.LoadEnrollments'"
        $script:GroupPolicyHelpersContent | Should -Match "Source 'GroupPolicy\.GetBaselineGpoEnvironmentSummary\.ScanPolicyRoot'"
    }
}

Describe 'GroupPolicy report partial failure visibility' {
    It 'includes unreadable manifest fragments in formatted reports' {
        $script:GroupPolicyHelpersContent | Should -Match 'PartialFailureCount'
        $script:GroupPolicyHelpersContent | Should -Match 'Report incomplete'
        $script:GroupPolicyHelpersContent | Should -Match 'PartialFailures'
    }
}
