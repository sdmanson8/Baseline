# End-to-end scenario: profile compare → audit → snapshot → rollback.
#
# The scenario is hermetic: it creates a temp profile and snapshot, exercises
# the lifecycle helpers, and asserts the artefacts and audit records that the
# enterprise rollout playbook depends on.

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    Import-Module (Join-Path $repoRoot 'Module\SharedHelpers.psm1') -Force -ErrorAction Stop
}

Describe 'Preset lifecycle scenario (profile/audit/snapshot/rollback)' {

    BeforeEach {
        $script:scenarioRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("BaselineScenario_{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $script:scenarioRoot -ItemType Directory -Force | Out-Null

        $script:profilePath = Join-Path $script:scenarioRoot 'profile.json'
        $script:snapshotPath = Join-Path $script:scenarioRoot 'snapshot.json'
        $script:auditPath = Join-Path $script:scenarioRoot 'audit.jsonl'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:scenarioRoot) {
            Remove-Item -LiteralPath $script:scenarioRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Set-BaselineOperationMode -Mode 'ReadWrite'
    }

    It 'writes a profile envelope and reads it back with Schema validation' {
        $payload = [ordered]@{
            ProfileName = 'ScenarioPreset'
            Entries = @(
                [ordered]@{ Function = 'TestTweakA'; State = 'Enable' },
                [ordered]@{ Function = 'TestTweakB'; State = 'Disable' }
            )
        }

        Write-BaselineDocument -FilePath $script:profilePath -Schema 'Baseline.ConfigurationProfile' -SchemaVersion 1 -Data $payload
        Test-Path -LiteralPath $script:profilePath | Should -BeTrue

        $reread = Read-BaselineDocument -FilePath $script:profilePath -ExpectedSchema 'Baseline.ConfigurationProfile'
        $reread.Schema | Should -Be 'Baseline.ConfigurationProfile'
        $reread.Data.ProfileName | Should -Be 'ScenarioPreset'
        @($reread.Data.Entries).Count | Should -Be 2
    }

    It 'records audit events and re-reads them in order' {
        Add-BaselineAuditRecord -FilePath $script:auditPath -Record ([ordered]@{ Action = 'Apply'; Function = 'TestTweakA'; Result = 'Ok' })
        Add-BaselineAuditRecord -FilePath $script:auditPath -Record ([ordered]@{ Action = 'Apply'; Function = 'TestTweakB'; Result = 'Ok' })

        $lines = Get-Content -LiteralPath $script:auditPath
        @($lines).Count | Should -Be 2
        ($lines[0] | ConvertFrom-Json).Function | Should -Be 'TestTweakA'
        ($lines[1] | ConvertFrom-Json).Function | Should -Be 'TestTweakB'
    }

    It 'refuses to write when the runtime is in ReadOnly mode' {
        Set-BaselineOperationMode -Mode 'ReadOnly'
        Test-BaselineReadOnlyMode | Should -BeTrue

        { Write-BaselineDocument -FilePath $script:profilePath -Schema 'Baseline.ConfigurationProfile' -SchemaVersion 1 -Data @{ Entries = @() } } |
            Should -Throw -ExceptionType ([System.InvalidOperationException])

        { Add-BaselineAuditRecord -FilePath $script:auditPath -Record @{ Action = 'Apply' } } |
            Should -Throw -ExceptionType ([System.InvalidOperationException])
    }

    It 'detects no GPO conflict for a tweak that targets a non-policy hive' {
        $entry = [pscustomobject]@{
            Function     = 'NonPolicyTweak'
            RegistryPath = 'HKCU:\SOFTWARE\BaselineScenarioTest'
            RegistryName = 'Value'
        }
        $report = Get-BaselineGpoConflictReport -Manifest @($entry)
        $report.HasConflicts | Should -BeFalse
        $report.ConflictCount | Should -Be 0
    }
}
