Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:PreflightChecksPath = Join-Path $PSScriptRoot '../../Module/GUI/PreflightChecks.ps1'
    $script:PreflightChecksContent = Get-BaselineTestSourceText -Path $script:PreflightChecksPath
    if (-not (Get-Command -Name 'Get-UxLocalizedString' -ErrorAction SilentlyContinue))
    {
        function Get-UxLocalizedString
        {
            param(
                [string]$Key,
                [string]$Fallback,
                [object[]]$FormatArgs
            )

            if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0)
            {
                return ($Fallback -f $FormatArgs)
            }

            return $Fallback
        }
    }

    . $script:PreflightChecksPath
}

Describe 'Preflight checks' {
    AfterEach {
        Remove-Item Function:\Test-IsDesignModeUX -ErrorAction SilentlyContinue
        $Global:BaselineHostTaint = $null
    }

    It 'includes a managed policy environment check in the preflight run' {
        $script:PreflightChecksContent | Should -Match 'function Test-PreflightManagedPolicyEnvironment'
        $script:PreflightChecksContent | Should -Match "GuiPreflightNamePolicies"
        $script:PreflightChecksContent | Should -Match "GuiPreflightPoliciesPassed"
        $script:PreflightChecksContent | Should -Match "GuiPreflightPoliciesError"
        $script:PreflightChecksContent | Should -Match 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'
        $script:PreflightChecksContent | Should -Match 'Test-PreflightManagedPolicyEnvironment'
        $script:PreflightChecksContent | Should -Match 'Review the connected target with the remote console and confirm the GPO scope before applying changes'
        $script:PreflightChecksContent | Should -Match 'Export the relevant policy hives or document the enforced settings before a high-risk run'
        $script:PreflightChecksContent | Should -Match 'RemediationActions'
        $script:PreflightChecksContent | Should -Match 'Generate an incident reproduction pack from the support bundle after any failed remediation attempt'
    }

    It 'returns a structured preflight contract' {
        Mock Test-PreflightAdminElevation {
            [pscustomobject]@{ Name = 'Administrator'; Key = 'AdminElevation'; Status = 'Passed'; Message = 'Running as administrator'; Category = 'Security'; Details = [ordered]@{ IsAdministrator = $true } }
        }
        Mock Test-PreflightDiskSpace {
            [pscustomobject]@{ Name = 'Disk space'; Status = 'Passed'; Message = '120 GB free'; Category = 'Storage' }
        }
        Mock Test-PreflightVSS {
            [pscustomobject]@{ Name = 'Volume Shadow Copy'; Status = 'Passed'; Message = 'Service is running'; Category = 'Services' }
        }
        Mock Test-PreflightEventLog {
            [pscustomobject]@{ Name = 'EventLog service'; Status = 'Passed'; Message = 'Service is running'; Category = 'Services' }
        }
        Mock Test-PreflightWMI {
            [pscustomobject]@{ Name = 'WMI health'; Status = 'Passed'; Message = 'CIM/WMI responding'; Category = 'System' }
        }
        Mock Test-PreflightSystemRestore {
            [pscustomobject]@{ Name = 'System Restore'; Status = 'Passed'; Message = 'Enabled'; Category = 'System' }
        }
        Mock Test-PreflightManagedPolicyEnvironment {
            [pscustomobject]@{ Name = 'Managed endpoint policy'; Key = 'ManagedPolicyEnvironment'; Status = 'Warning'; Message = 'Domain joined'; Category = 'Security'; Details = [ordered]@{ DomainJoined = $true; ActivePolicyHives = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'); ConflictSignals = @('Domain joined') } }
        }
        Mock Test-PreflightPendingReboot {
            [pscustomobject]@{ Name = 'Pending reboot'; Key = 'PendingReboot'; Status = 'Passed'; Message = 'No pending reboot detected'; Category = 'System'; Details = [ordered]@{ PendingReasons = @() } }
        }
        Mock Test-PreflightWinRMReachability {
            param([string[]]$Targets)
            [pscustomobject]@{ Name = 'WinRM reachability'; Key = 'WinRMReachability'; Status = 'Passed'; Message = '2 target(s) reachable via WinRM'; Category = 'Services'; Details = [ordered]@{ TargetCount = @($Targets).Count; ReachableTargets = @($Targets); UnreachableTargets = @(); ServiceStatus = 'Running' } }
        }

        $results = Invoke-PreflightChecks -RemoteTargets @('server01', 'server02')

        $results.Status | Should -Be 'Warning'
        $results.Passed | Should -BeFalse
        $results.WinRMReachability.TargetCount | Should -Be 2
        $results.WinRMReachability.ReachableTargets | Should -Contain 'server01'
        $results.PSObject.Properties['FirewallAccess'] | Should -BeNullOrEmpty
        $results.Credentials.IsElevated | Should -BeTrue
        $results.PolicyConflictSignals.Status | Should -Be 'Warning'
        $results.PolicyConflictSignals.ConflictCount | Should -Be 1
        $results.SupportedEnvironmentClassification.Status | Should -Be 'AttentionRequired'
        $results.SupportedEnvironmentClassification.WarningCount | Should -Be 1

        # Risk category surfacing
        $results.PolicyConflictSignals.Categories | Should -Not -BeNullOrEmpty
        @($results.RiskCategories).Count | Should -BeGreaterThan 0
        $managedCategory = @($results.RiskCategories | Where-Object { $_.Key -eq 'ManagedEndpointPolicy' })
        $managedCategory.Count | Should -Be 1
        $managedCategory[0].Status | Should -Be 'Warning'
        $managedCategory[0].DocumentationPath | Should -Match 'Remediation/ManagedEndpoints'
    }

    It 'short-circuits to a passed contract in Design Mode' {
        function Test-IsDesignModeUX {
            return $true
        }

        $results = Invoke-PreflightChecks -RemoteTargets @('server01')

        $results.Passed | Should -Be $true
        $results.Status | Should -Be 'Passed'
        @($results.AllResults).Count | Should -Be 0
        @($results.RiskCategories).Count | Should -Be 0
    }

    It 'fails preflight when host taint is blocked' {
        Mock Test-PreflightAdminElevation {
            [pscustomobject]@{ Name = 'Administrator'; Key = 'AdminElevation'; Status = 'Passed'; Message = 'Running as administrator'; Category = 'Security'; Details = [ordered]@{ IsAdministrator = $true } }
        }
        Mock Test-PreflightDiskSpace { [pscustomobject]@{ Name = 'Disk space'; Status = 'Passed'; Message = 'OK'; Category = 'Storage' } }
        Mock Test-PreflightVSS { [pscustomobject]@{ Name = 'VSS'; Status = 'Passed'; Message = 'OK'; Category = 'Services' } }
        Mock Test-PreflightEventLog { [pscustomobject]@{ Name = 'EventLog'; Status = 'Passed'; Message = 'OK'; Category = 'Services' } }
        Mock Test-PreflightWMI { [pscustomobject]@{ Name = 'WMI'; Status = 'Passed'; Message = 'OK'; Category = 'System' } }
        Mock Test-PreflightSystemRestore { [pscustomobject]@{ Name = 'Restore'; Status = 'Passed'; Message = 'OK'; Category = 'System' } }
        Mock Test-PreflightManagedPolicyEnvironment { [pscustomobject]@{ Name = 'Managed endpoint policy'; Key = 'ManagedPolicyEnvironment'; Status = 'Passed'; Message = 'OK'; Category = 'Security'; Details = [ordered]@{ DomainJoined = $false; ActivePolicyHives = @(); ConflictSignals = @() } } }
        Mock Test-PreflightPendingReboot { [pscustomobject]@{ Name = 'Pending reboot'; Key = 'PendingReboot'; Status = 'Passed'; Message = 'No pending reboot detected'; Category = 'System'; Details = [ordered]@{ PendingReasons = @() } } }
        Mock Test-PreflightWinRMReachability { [pscustomobject]@{ Name = 'WinRM reachability'; Key = 'WinRMReachability'; Status = 'Passed'; Message = 'WinRM not targeted'; Category = 'Services'; Details = [ordered]@{ TargetCount = 0; ReachableTargets = @(); UnreachableTargets = @(); ServiceStatus = 'Running' } } }

        $Global:BaselineHostTaint = [pscustomobject]@{
            Level         = 'Blocked'
            BackdoorFound = $true
            Detected      = @('Win 10 Tweaker')
            AdvisoryUrls  = @('https://massgrave.dev/genuine-installation-media')
        }

        $results = Invoke-PreflightChecks

        $results.Status | Should -Be 'Failed'
        $results.Passed | Should -BeFalse
        @($results.CriticalFailures | Where-Object Key -eq 'HostTaint').Count | Should -Be 1
        $results.HostIntegrity.Status | Should -Be 'Failed'
        $results.HostIntegrity.Summary | Should -Match 'Win 10 Tweaker'
        $hostTaintRisk = @($results.RiskCategories | Where-Object Key -eq 'HostTaint')
        $hostTaintRisk.Count | Should -Be 1
        $hostTaintRisk[0].Status | Should -Be 'Failed'
        @($hostTaintRisk[0].RemediationActions).Count | Should -BeGreaterThan 0
    }

    It 'exposes partial WinRM coverage as a Warning with a PartialCoverage flag' {
        Mock Test-PreflightAdminElevation {
            [pscustomobject]@{ Name = 'Administrator'; Key = 'AdminElevation'; Status = 'Passed'; Message = 'Running as administrator'; Category = 'Security'; Details = [ordered]@{ IsAdministrator = $true } }
        }
        Mock Test-PreflightDiskSpace { [pscustomobject]@{ Name = 'Disk space'; Status = 'Passed'; Message = 'OK'; Category = 'Storage' } }
        Mock Test-PreflightVSS { [pscustomobject]@{ Name = 'VSS'; Status = 'Passed'; Message = 'OK'; Category = 'Services' } }
        Mock Test-PreflightEventLog { [pscustomobject]@{ Name = 'EventLog'; Status = 'Passed'; Message = 'OK'; Category = 'Services' } }
        Mock Test-PreflightWMI { [pscustomobject]@{ Name = 'WMI'; Status = 'Passed'; Message = 'OK'; Category = 'System' } }
        Mock Test-PreflightSystemRestore { [pscustomobject]@{ Name = 'Restore'; Status = 'Passed'; Message = 'OK'; Category = 'System' } }
        Mock Test-PreflightManagedPolicyEnvironment { [pscustomobject]@{ Name = 'Managed endpoint policy'; Key = 'ManagedPolicyEnvironment'; Status = 'Passed'; Message = 'OK'; Category = 'Security'; Details = [ordered]@{ DomainJoined = $false; ActivePolicyHives = @(); ConflictSignals = @() } } }
        Mock Test-PreflightPendingReboot { [pscustomobject]@{ Name = 'Pending reboot'; Key = 'PendingReboot'; Status = 'Passed'; Message = 'No pending reboot detected'; Category = 'System'; Details = [ordered]@{ PendingReasons = @() } } }
        Mock Test-PreflightWinRMReachability {
            param([string[]]$Targets)
            [pscustomobject]@{
                Name = 'WinRM reachability'
                Key  = 'WinRMReachability'
                Status = 'Warning'
                Message = 'Partial WinRM coverage: 1 of 2 target(s) reachable.'
                Category = 'Services'
                RemediationActions = @('Confirm DNS resolution and routing for the unreachable target(s).')
                Details = [ordered]@{
                    TargetCount = 2
                    ReachableTargets = @('server01')
                    UnreachableTargets = @('server02: unreachable')
                    PartialCoverage = $true
                    ServiceStatus = 'Running'
                }
            }
        }

        $results = Invoke-PreflightChecks -RemoteTargets @('server01', 'server02')

        $results.Status | Should -Be 'Warning'
        $results.WinRMReachability.Status | Should -Be 'Warning'
        $variability = @($results.RiskCategories | Where-Object { $_.Key -eq 'WinRMVariability' })
        $variability.Count | Should -Be 1
        $variability[0].Status | Should -Be 'Warning'
        $variability[0].DocumentationPath | Should -Match 'Remediation/WinRMReachability'
        @($variability[0].RemediationActions).Count | Should -BeGreaterThan 0
    }

    It 'produces a partial-success rollout risk category when recent PartialSuccess outcomes exist' {
        function Get-BaselineRemoteRolloutOutcomes {
            param(
                [string]$RunId,
                [string[]]$Outcome,
                [string]$Operation,
                [datetime]$Since,
                [int]$MaxRecords = 25
            )
            return @(
                [pscustomobject]@{
                    RecordedUtc = [datetime]::UtcNow.AddHours(-3)
                    RunId = 'run-123'
                    Operation = 'ApplyTweaks'
                    Outcome = 'PartialSuccess'
                    TargetCount = 5
                    SucceededCount = 3
                    FailedCount = 2
                    SkippedCount = 0
                    CancelledCount = 0
                }
            )
        }

        $risk = Get-BaselinePartialSuccessRolloutRisk
        $risk | Should -Not -BeNullOrEmpty
        $risk.Key | Should -Be 'PartialSuccessRolloutRisk'
        $risk.Status | Should -Be 'Warning'
        $risk.DocumentationPath | Should -Match 'Remediation/PartialSuccess'
        $risk.Summary | Should -Match 'run-123'
        @($risk.RemediationActions).Count | Should -BeGreaterThan 0
    }

    It 'returns a passed partial-success category when no PartialSuccess outcomes are recorded' {
        function Get-BaselineRemoteRolloutOutcomes {
            param(
                [string]$RunId,
                [string[]]$Outcome,
                [string]$Operation,
                [datetime]$Since,
                [int]$MaxRecords = 25
            )
            return @(
                [pscustomobject]@{
                    RecordedUtc = [datetime]::UtcNow.AddHours(-1)
                    RunId = 'run-456'
                    Operation = 'ApplyTweaks'
                    Outcome = 'Succeeded'
                    TargetCount = 3
                    SucceededCount = 3
                    FailedCount = 0
                    SkippedCount = 0
                    CancelledCount = 0
                }
            )
        }

        $risk = Get-BaselinePartialSuccessRolloutRisk
        $risk | Should -Not -BeNullOrEmpty
        $risk.Status | Should -Be 'Passed'
    }

    It 'renders risk categories in the preflight dialog payload' {
        # Render branch exercised by Show-PreflightResultsDialog should include the heading and remediation pointers.
        $script:PreflightChecksContent | Should -Match 'GuiPreflightRiskCategoryHeading'
        $script:PreflightChecksContent | Should -Match 'GuiPreflightRiskCategoryDocsLabel'
        $script:PreflightChecksContent | Should -Match 'GuiPreflightRiskCategoryLogsLabel'
        $script:PreflightChecksContent | Should -Match 'function New-BaselineRiskCategory'
        $script:PreflightChecksContent | Should -Match 'function Get-BaselineRiskCategoryList'
        $script:PreflightChecksContent | Should -Match 'function Get-BaselinePartialSuccessRolloutRisk'
    }

    It 'routes non-fatal preflight catches through Write-SwallowedException and reads optional reboot values quietly' {
        $script:PreflightChecksContent | Should -Match 'PreflightChecks\.Get-BaselinePartialSuccessRolloutRisk\.LoadOutcomes'
        $script:PreflightChecksContent | Should -Match 'PreflightChecks\.TestPreflightManagedPolicyEnvironment\.LoadDomainJoined'
        $script:PreflightChecksContent | Should -Match 'PreflightChecks\.TestPreflightManagedPolicyEnvironment\.TestPathPolicy'
        $script:PreflightChecksContent | Should -Match 'PreflightChecks\.TestPreflightSystemRestore\.LoadSrpStatus'
        $script:PreflightChecksContent | Should -Match 'PSObject\.Properties\[''PendingFileRenameOperations''\]'
        $script:PreflightChecksContent | Should -Match 'PSObject\.Properties\[''PostRebootReporting''\]'
        $script:PreflightChecksContent | Should -Not -Match 'PreflightChecks\.TestPreflightPendingReboot\.LoadPostRebootReporting'
    }
}
