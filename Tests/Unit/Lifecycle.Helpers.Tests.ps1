Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:LifecycleHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Lifecycle.Helpers.ps1'
    $script:LifecycleHelpersContent = Get-BaselineTestSourceText -Path $script:LifecycleHelpersPath
    $script:LifecycleToolPath = Join-Path $PSScriptRoot '../../Tools/Invoke-LifecyclePlaybook.ps1'
    $script:IncidentToolPath = Join-Path $PSScriptRoot '../../Tools/New-IncidentReproductionPack.ps1'
    $script:SigningPolicyPath = Join-Path $PSScriptRoot '../../dev_docs/Installer-Signing-Policy.md'
}

Describe 'Lifecycle helpers' {
    It 'exposes lifecycle playbook and incident reproduction helpers' {
        $script:LifecycleHelpersContent | Should -Match 'function New-BaselineLifecyclePlaybook'
        $script:LifecycleHelpersContent | Should -Match 'function Invoke-BaselineLifecyclePlaybook'
        $script:LifecycleHelpersContent | Should -Match 'function Import-BaselineRollbackProfile'
        $script:LifecycleHelpersContent | Should -Match 'function Get-BaselineReleaseArtifactVerification'
        $script:LifecycleHelpersContent | Should -Match 'function Assert-BaselineReleaseArtifactVerification'
        $script:LifecycleHelpersContent | Should -Match 'function New-BaselineIncidentReproductionPack'
        $script:LifecycleHelpersContent | Should -Match 'Rollback profile'
        $script:LifecycleHelpersContent | Should -Match 'incident reproduction'
        $script:LifecycleHelpersContent | Should -Match 'timestamp countersignature is missing'
    }

    It 'ships the lifecycle tooling and signing policy documentation' {
        Test-Path -LiteralPath $script:LifecycleToolPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:IncidentToolPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:SigningPolicyPath -PathType Leaf | Should -BeTrue
        $script:LifecycleToolContent = Get-BaselineTestSourceText -Path $script:LifecycleToolPath
        $script:LifecycleToolContent | Should -Match 'Write-AuditRecord'
        $script:LifecycleToolContent | Should -Match 'VerificationChanged'
        $script:LifecycleToolContent | Should -Match 'lifecycle verification metadata'
        $script:LifecycleToolContent | Should -Match 'Lifecycle execution blocked because the artifact could not be verified'
    }
}
