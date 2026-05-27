Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    <#
        .SYNOPSIS
    #>

    function Get-BaselineDisplayVersion { return '1.0.0' }

    $environmentHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $auditHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AuditTrail.Helpers.ps1'
    $schedulerHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Scheduler.Helpers.ps1'
    $script:SharedHelpersRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:SharedHelpersModuleRoot = Join-Path $script:SharedHelpersRepoRoot 'Module'
    $script:AuditHelpersContent = Get-BaselineTestSourceText -Path $auditHelpersPath

    $environmentAst = [System.Management.Automation.Language.Parser]::ParseFile($environmentHelpersPath, [ref]$null, [ref]$null)
    $environmentFunctions = $environmentAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $environmentFunctions) {
        if ($fn.Name -in @('Set-BaselineOperationMode', 'Get-BaselineOperationMode', 'Test-BaselineReadOnlyMode', 'Assert-BaselineWriteAllowed')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    # Parse and load audit helpers
    $auditAst = [System.Management.Automation.Language.Parser]::ParseFile($auditHelpersPath, [ref]$null, [ref]$null)
    $auditFunctions = $auditAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $auditFunctions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Parse scheduler helpers for Task verification tests
    $schedulerAst = [System.Management.Automation.Language.Parser]::ParseFile($schedulerHelpersPath, [ref]$null, [ref]$null)
    $schedulerFunctions = $schedulerAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $schedulerFunctions) {
        Invoke-Expression $fn.Extent.Text
    }

    $script:OriginalRetentionDays = $env:BASELINE_AUDIT_RETENTION_DAYS
    $script:OriginalPolicyThreshold = $env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
}

AfterAll {
    # Restore original environment variables
    if ($null -ne $script:OriginalRetentionDays) {
        $env:BASELINE_AUDIT_RETENTION_DAYS = $script:OriginalRetentionDays
    }
    else {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_DAYS' -ErrorAction SilentlyContinue
    }

    if ($null -ne $script:OriginalPolicyThreshold) {
        $env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD = $script:OriginalPolicyThreshold
    }
    else {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
    }

    if ($null -ne $script:OriginalLocalAppData) {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }
    else {
        Remove-Item -Path 'Env:LOCALAPPDATA' -ErrorAction SilentlyContinue
    }
}

Describe 'Write-AuditRecord' {
    AfterEach {
        Set-BaselineOperationMode -Mode 'ReadWrite'
    }

    It 'accepts Profile mode and writes a profile audit record' {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'write-profile-mode'

        Write-AuditRecord -Action 'ProfileApply' -Mode 'Profile' -ProfilePath 'C:\Temp\profile.json' -Details @{
            Entries = 3
            Failed  = 0
        }

        $auditPath = Join-Path $env:LOCALAPPDATA 'Baseline\audit.jsonl'
        Test-Path -LiteralPath $auditPath | Should -BeTrue

        $record = (Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json)
        $record.Action | Should -Be 'ProfileApply'
        $record.Mode | Should -Be 'Profile'
        $record.ProfilePath | Should -Be 'C:\Temp\profile.json'
        $record.Details.Entries | Should -Be 3
    }

    It 'routes audit retention cleanup through warning-severity swallowed-exception logging' {
        $script:AuditHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''AuditTrail\.Write-AuditRecord\.InvokeRetentionPolicy'' -Severity Warning'
    }

    It 'throws in ReadOnly mode before creating audit storage' {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'readonly-profile-mode'
        Set-BaselineOperationMode -Mode 'ReadOnly'

        {
            Write-AuditRecord -Action 'ProfileApply' -Mode 'Profile' -ProfilePath 'C:\Temp\profile.json'
        } | Should -Throw -ExceptionType ([System.InvalidOperationException])

        Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Baseline') | Should -BeFalse
    }
}

Describe 'Get-BaselineAuditRetentionPolicyThreshold' {
    It 'returns default 90-day policy threshold' {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
        $threshold = Get-BaselineAuditRetentionPolicyThreshold
        $threshold | Should -Be 90
    }

    It 'respects environment variable override' {
        $env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD = '120'
        $threshold = Get-BaselineAuditRetentionPolicyThreshold
        $threshold | Should -Be 120
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
    }
}

Describe 'Test-BaselineAuditRetentionBelowPolicy' {
    BeforeEach {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
    }

    It 'returns $true when retention is below policy threshold' {
        $result = Test-BaselineAuditRetentionBelowPolicy -RetentionDays 30
        $result | Should -BeTrue
    }

    It 'returns $false when retention meets policy threshold' {
        $result = Test-BaselineAuditRetentionBelowPolicy -RetentionDays 90
        $result | Should -BeFalse
    }

    It 'returns $false when retention exceeds policy threshold' {
        $result = Test-BaselineAuditRetentionBelowPolicy -RetentionDays 180
        $result | Should -BeFalse
    }
}

Describe 'Get-BaselineAuditRetentionPolicyWarning' {
    BeforeEach {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
    }

    It 'returns $null when retention meets policy' {
        $warning = Get-BaselineAuditRetentionPolicyWarning -RetentionDays 90
        $warning | Should -BeNullOrEmpty
    }

    It 'returns warning object when retention is below policy' {
        $warning = Get-BaselineAuditRetentionPolicyWarning -RetentionDays 30
        $warning | Should -Not -BeNullOrEmpty
        $warning.Warning | Should -BeTrue
        $warning.CurrentDays | Should -Be 30
        $warning.PolicyMinimum | Should -Be 90
        $warning.Deficit | Should -Be 60
        $warning.Message | Should -Match 'below the policy minimum'
        $warning.Recommendation | Should -Not -BeNullOrEmpty
    }

    It 'assigns High severity for large deficit' {
        $warning = Get-BaselineAuditRetentionPolicyWarning -RetentionDays 30
        $warning.Severity | Should -Be 'High'
    }

    It 'assigns Medium severity for small deficit' {
        $warning = Get-BaselineAuditRetentionPolicyWarning -RetentionDays 80
        $warning.Severity | Should -Be 'Medium'
    }
}

Describe 'Test-BaselineAuditRetentionTaskExecution' {
    It 'returns structured result with status fields' {
        $result = Test-BaselineAuditRetentionTaskExecution
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties['TasksChecked'] | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties['OverallStatus'] | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties['Issues'] | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties['Recommendations'] | Should -Not -BeNullOrEmpty
    }

    It 'handles no scheduled tasks gracefully' {
        # In test environment there are no Baseline scheduled tasks
        $result = Test-BaselineAuditRetentionTaskExecution
        # Should not throw, should return a valid status
        $result.OverallStatus | Should -BeIn @('Unknown', 'OnDemandOnly', 'Unavailable', 'Error', 'Healthy', 'Degraded')
    }
}

Describe 'Get-BaselineAuditRetentionReport' {
    BeforeEach {
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_DAYS' -ErrorAction SilentlyContinue
    }

    It 'returns comprehensive report with all required sections' {
        $report = Get-BaselineAuditRetentionReport
        $report | Should -Not -BeNullOrEmpty
        $report.PSObject.Properties['GeneratedAt'] | Should -Not -BeNullOrEmpty
        $report.PSObject.Properties['MachineName'] | Should -Not -BeNullOrEmpty
        $report.PSObject.Properties['Retention'] | Should -Not -BeNullOrEmpty
        $report.PSObject.Properties['TaskExecution'] | Should -Not -BeNullOrEmpty
        $report.PSObject.Properties['OverallCompliance'] | Should -Not -BeNullOrEmpty
    }

    It 'includes retention details' {
        $report = Get-BaselineAuditRetentionReport
        $report.Retention.CurrentDays | Should -BeGreaterOrEqual 30
        $report.Retention.PolicyMinimum | Should -BeGreaterOrEqual 1
        $report.Retention.Keys | Should -Contain 'BelowPolicy'
        $report.Retention.Keys | Should -Contain 'CutoffDate'
    }

    It 'marks NonCompliant when below policy threshold' {
        $env:BASELINE_AUDIT_RETENTION_DAYS = '30'
        Remove-Item -Path 'Env:BASELINE_AUDIT_RETENTION_POLICY_THRESHOLD' -ErrorAction SilentlyContinue
        $report = Get-BaselineAuditRetentionReport
        $report.Retention.BelowPolicy | Should -BeTrue
        $report.OverallCompliance | Should -Be 'NonCompliant'
    }

    It 'includes policy warning when below threshold' {
        $env:BASELINE_AUDIT_RETENTION_DAYS = '30'
        $report = Get-BaselineAuditRetentionReport
        $report.PolicyWarning | Should -Not -BeNullOrEmpty
        $report.Issues.Count | Should -BeGreaterThan 0
    }
}
