Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RemoteTargetHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemoteTarget.Helpers.ps1'
    $script:SharedHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    $script:RemoteTargetHelpersContent = Get-BaselineTestSourceText -Path $script:RemoteTargetHelpersPath
    $script:SharedHelpersContent = Get-BaselineTestSourceText -Path $script:SharedHelpersPath
    function Write-SwallowedException
    {
        param(
            [object]$ErrorRecord,
            [string]$Source
        )
    }
    . $script:RemoteTargetHelpersPath
}

Describe 'Remote session caching' {
    It 'declares a reusable remote session cache and reuses it across remote operations' {
        $script:RemoteTargetHelpersContent | Should -Match 'RemoteSessionCache'
        $script:RemoteTargetHelpersContent | Should -Match 'Variable:\\Script:CachedRemoteSessionCache'
        $script:RemoteTargetHelpersContent | Should -Not -Match 'CachedRemoteSessionCacheVariable'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteCredentialScopeKey'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteSessionKey'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteTransportSettingsSignature'
        $script:RemoteTargetHelpersContent | Should -Match 'function Invoke-BaselineRemoteSessionCacheMaintenance'
        $script:RemoteTargetHelpersContent | Should -Match 'function Clear-BaselineRemoteSessionCache'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteSession'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteTargetTerminalState'
        $script:RemoteTargetHelpersContent | Should -Match 'Get-BaselineRemoteSession -ComputerName \$computer -Credential \$Credential'
    }

    It 'declares remote orchestration history helpers and writes structured records' {
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteOrchestrationHistoryPath'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteFailureProfile'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteOrchestrationHistory'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteOrchestrationDetails'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteOrchestrationSummary'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteRunSummaries'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteTargetLifecycleState'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteOrchestrationReconciliation'
        $script:RemoteTargetHelpersContent | Should -Match 'function Invoke-BaselineRemoteEntryWithRetry'
        $script:RemoteTargetHelpersContent | Should -Match 'function Invoke-BaselineRemoteRetryDelay'
        $script:RemoteTargetHelpersContent | Should -Match 'function Invoke-BaselineRemoteCheckpointAction'
        $script:RemoteTargetHelpersContent | Should -Match 'function Test-BaselineRemoteOrchestrationAllowed'
        $script:RemoteTargetHelpersContent | Should -Match 'function Write-BaselineRemoteOrchestrationRecord'
        $script:RemoteTargetHelpersContent | Should -Match 'function Write-BaselineRemoteOrchestrationSummaryRecord'
        $script:RemoteTargetHelpersContent | Should -Match 'remote-orchestration\.jsonl'
        $script:RemoteTargetHelpersContent | Should -Match 'RecordKind'
        $script:RemoteTargetHelpersContent | Should -Match 'TerminalState'
        $script:RemoteTargetHelpersContent | Should -Match 'FailureCategory'
        $script:RemoteTargetHelpersContent | Should -Match 'RetryReason'
        $script:RemoteTargetHelpersContent | Should -Match 'LifecycleState'
        $script:RemoteTargetHelpersContent | Should -Match 'AttemptCount'
        $script:RemoteTargetHelpersContent | Should -Match 'RetryCount'
    }

    It 'exports the session cache helpers from the shared helpers module' {
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteSession'"
        $script:SharedHelpersContent | Should -Match "'Clear-BaselineRemoteSessionCache'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteOrchestrationHistoryPath'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteFailureProfile'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteOrchestrationHistory'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteOrchestrationDetails'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteOrchestrationSummary'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteRunSummaries'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteOrchestrationReconciliation'"
        $script:SharedHelpersContent | Should -Match "'Write-BaselineRemoteOrchestrationRecord'"
        $script:SharedHelpersContent | Should -Match "'Write-BaselineRemoteOrchestrationSummaryRecord'"
    }

    It 'clears cached sessions when the GUI disconnects a remote target' {
        $actionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
        $actionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
        $actionHandlersContent = Get-BaselineTestSourceText -Path @(
            $actionHandlersPath
            (Join-Path $actionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
            (Join-Path $actionHandlersSplitRoot 'ButtonHandlers.ps1')
            (Join-Path $actionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
            (Join-Path $actionHandlersSplitRoot 'MenuHandlers.ps1')
        )

        $actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Clear-BaselineRemoteSessionCache'"
        $actionHandlersContent | Should -Match '\$clearRemoteSessionCacheCommand -ComputerName @\(\$context.TargetComputers\)'
    }

    It 'routes remote TCP cleanup failures through Write-SwallowedException' {
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Test-BaselineRemoteTargetConnectivity\.TcpClose'''
    }

    It 'routes remote session cache cleanup failures through Write-SwallowedException' {
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Remove-BaselineRemoteSessionCacheEntry\.RemovePSSession'''
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Invoke-BaselineRemoteSessionCacheMaintenance\.UpdateLastUsedUtc'''
    }

    It 'routes remote history timestamp parse failures through Write-SwallowedException' {
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteOrchestrationHistory\.SinceTimestampParse'''
    }

    It 'routes remote history line parse failures through Write-SwallowedException' {
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteOrchestrationHistory\.ParseLine'''
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteRunSummaries\.ParseLine'''
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteResumeCheckpoint\.ParseLine'''
    }

    It 'routes remote summary timestamp parse failures through Write-SwallowedException' {
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteOrchestrationSummary\.SinceTimestampParse'''
        $script:RemoteTargetHelpersContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''RemoteTarget\.Get-BaselineRemoteRunSummaries\.SinceTimestampParse'''
    }

    It 'keys sessions by credential scope and transport settings' {
        $script:CachedRemoteSessionCache = @{}

        Mock New-PSSession {
            [pscustomobject]@{
                ComputerName = $ComputerName
                State        = 'Opened'
            }
        }

        Mock Remove-PSSession {}

        $credential = [pscredential]::new('DOMAIN\User', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))

        $first = Get-BaselineRemoteSession -ComputerName 'server01' -Credential $credential -TransportSettings @{ Port = 5986; UseSSL = $true } -IdleTimeoutMinutes 30
        $second = Get-BaselineRemoteSession -ComputerName 'server01' -Credential $credential -TransportSettings @{ UseSSL = $true; Port = 5986 } -IdleTimeoutMinutes 30
        $third = Get-BaselineRemoteSession -ComputerName 'server01' -Credential $credential -TransportSettings @{ Port = 5985 } -IdleTimeoutMinutes 30

        $first.ComputerName | Should -Be 'server01'
        $second.ComputerName | Should -Be 'server01'
        $third.ComputerName | Should -Be 'server01'
        Should -Invoke New-PSSession -Times 2
        $script:CachedRemoteSessionCache.Count | Should -Be 2
    }

    It 'evicts stale cache entries before reusing a remote session' {
        $script:CachedRemoteSessionCache = @{}

        Mock New-PSSession {
            [pscustomobject]@{
                ComputerName = $ComputerName
                State        = 'Opened'
            }
        }

        Mock Remove-PSSession {}

        $credential = [pscredential]::new('DOMAIN\User', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))

        $first = Get-BaselineRemoteSession -ComputerName 'server01' -Credential $credential -TransportSettings @{ Port = 5986; UseSSL = $true } -IdleTimeoutMinutes 30
        $cacheKey = Get-BaselineRemoteSessionKey -ComputerName 'server01' -Credential $credential -TransportSettings @{ Port = 5986; UseSSL = $true }
        $script:CachedRemoteSessionCache[$cacheKey].LastUsedUtc = [datetime]::UtcNow.AddMinutes(-45)

        $removed = Invoke-BaselineRemoteSessionCacheMaintenance -ComputerName 'server01' -IdleTimeoutMinutes 15
        $refreshed = Get-BaselineRemoteSession -ComputerName 'server01' -Credential $credential -TransportSettings @{ UseSSL = $true; Port = 5986 } -IdleTimeoutMinutes 15

        $first.ComputerName | Should -Be 'server01'
        $removed | Should -Contain $cacheKey
        $refreshed.ComputerName | Should -Be 'server01'
        Should -Invoke New-PSSession -Times 2
    }
}

Describe 'Remote resume checkpoint warnings' {
    BeforeEach {
        $script:remoteCheckpointWarnings = [System.Collections.Generic.List[string]]::new()
        function LogWarning { param([string]$Message) [void]$script:remoteCheckpointWarnings.Add($Message) }
    }

    AfterEach {
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'logs checkpoint persistence failures with context instead of swallowing them silently' {
        $result = Invoke-BaselineRemoteCheckpointAction -Description 'persist RemoteApply checkpoint state for run test-run' -Action { throw 'disk full' }

        $result | Should -BeNullOrEmpty
        $script:remoteCheckpointWarnings | Should -HaveCount 1
        $script:remoteCheckpointWarnings[0] | Should -Match 'Failed to persist RemoteApply checkpoint state for run test-run'
        $script:remoteCheckpointWarnings[0] | Should -Match 'disk full'
    }
}

Describe 'Remote target state machine' {
    It 'maps orchestration status into explicit target states' {
        Get-BaselineRemoteTargetState -Operation 'RemoteApply' -State 'Running' | Should -Be 'Running'
        Get-BaselineRemoteTargetState -Operation 'RemoteApply' -Status 'Applied' | Should -Be 'Succeeded'
        Get-BaselineRemoteTargetState -Operation 'RemoteCompliance' -Status 'Drifted' | Should -Be 'RequiresReview'
        Get-BaselineRemoteTargetState -Operation 'RemoteApply' -Status 'Skipped' | Should -Be 'RequiresReview'
        Get-BaselineRemoteTargetState -Operation 'ConnectivityTest' -Status 'Reachable' | Should -Be 'Succeeded'
        Get-BaselineRemoteTargetState -Operation 'RemoteApply' -Blocked $true | Should -Be 'PreflightFailed'
        Get-BaselineRemoteTargetState -Operation 'RemoteApply' -Cancelled $true | Should -Be 'Cancelled'
    }

    It 'builds ordered target state transitions' {
        $transitions = [System.Collections.Generic.List[pscustomobject]]::new()
        $null = $transitions.Add([pscustomobject]@{ Seed = $true })
        $timestamp = [datetime]::Parse('2026-04-15T10:00:00Z')

        $transition = Add-BaselineRemoteTargetStateTransition -Transitions $transitions -Operation 'RemoteApply' -State 'Pending' -Phase 'Queued' -Status 'Unknown' -Reason 'Queued for apply.' -Timestamp $timestamp

        $transitions.Count | Should -Be 2
        $transition.Operation | Should -Be 'RemoteApply'
        $transition.State | Should -Be 'Pending'
        $transition.Phase | Should -Be 'Queued'
        $transition.Status | Should -Be 'Unknown'
        $transition.Reason | Should -Be 'Queued for apply.'
        $transition.Timestamp | Should -Be $timestamp.ToUniversalTime()
        $transitions[1].State | Should -Be 'Pending'
    }

    It 'summarizes target states and writes them to history records' {
        $originalLocalAppData = $env:LOCALAPPDATA
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('Baseline-RemoteState-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        try
        {
            $env:LOCALAPPDATA = $tempRoot

            $record = Write-BaselineRemoteOrchestrationRecord -Record @{
                RecordKind         = 'Target'
                RunId              = 'run-001'
                Operation          = 'RemoteApply'
                ComputerName       = 'server01'
                RemoteTargetLabel  = 'server01'
                Status             = 'Applied'
                TargetState        = 'Succeeded'
                TerminalState      = 'Succeeded'
                LifecycleState     = 'Succeeded'
                AttemptCount       = 2
                RetryCount         = 1
                StartedAt          = [datetime]::Parse('2026-04-15T10:00:00Z')
                CompletedAt        = [datetime]::Parse('2026-04-15T10:05:00Z')
                DurationSeconds    = 300
                TargetStateHistory = @(
                    [pscustomobject]@{
                        Operation = 'RemoteApply'
                        State     = 'Pending'
                        Phase     = 'Queued'
                        Status    = $null
                        Reason    = 'Queued for apply.'
                        Timestamp = [datetime]::Parse('2026-04-15T10:00:00Z')
                    }
                )
            }

            $summaryRecord = Write-BaselineRemoteOrchestrationSummaryRecord -Record @{
                RunId              = 'run-001'
                Operation          = 'RemoteApply'
                Status             = 'Completed'
                TerminalState      = 'Succeeded'
                TargetState        = 'Succeeded'
                TargetCount        = 1
                SucceededCount     = 1
                FailedCount        = 0
                SkippedCount       = 0
                RetryingCount      = 0
                CancelledCount     = 0
                TotalAttempts      = 2
                TotalRetries       = 1
                TargetStateCounts  = [ordered]@{
                    Pending = 0
                    Connecting = 0
                    Connected = 0
                    PreflightFailed = 0
                    PreviewReady = 0
                    Running = 0
                    Succeeded = 1
                    Failed = 0
                    Cancelled = 0
                    RequiresReview = 0
                }
                TerminalStateCounts = [ordered]@{
                    Succeeded = 1
                    Failed = 0
                    Skipped = 0
                    Retrying = 0
                    Cancelled = 0
                }
            }

            $summary = Get-BaselineRemoteOrchestrationReconciliation -Records @(
                [pscustomobject]@{
                    Operation     = 'RemoteApply'
                    Status        = 'Applied'
                    Retryable     = $false
                    BlockedByPolicy = $false
                    TargetState   = 'Succeeded'
                    TerminalState = 'Succeeded'
                    AttemptCount  = 2
                    RetryCount    = 1
                    FailureCategory = 'Success'
                },
                [pscustomobject]@{
                    Operation     = 'RemoteCompliance'
                    Status        = 'Drifted'
                    Retryable     = $false
                    BlockedByPolicy = $false
                    TargetState   = 'RequiresReview'
                    TerminalState = 'Failed'
                    AttemptCount  = 1
                    RetryCount    = 0
                    FailureCategory = 'Compliance'
                }
            )

            $summary.TargetState | Should -Be 'RequiresReview'
            $summary.TargetStateCounts['Succeeded'] | Should -Be 1
            $summary.TargetStateCounts['RequiresReview'] | Should -Be 1
            $summary.TotalAttempts | Should -Be 3
            $summary.TotalRetries | Should -Be 1

            $historyPath = Get-BaselineRemoteOrchestrationHistoryPath
            $historyLines = @(Get-Content -LiteralPath $historyPath -Encoding UTF8)
            $historyLines.Count | Should -Be 2

            $targetPayload = $historyLines[0] | ConvertFrom-Json
            $targetPayload.RecordKind | Should -Be 'Target'
            $targetPayload.TargetState | Should -Be 'Succeeded'
            $targetPayload.TargetStateHistory.Count | Should -Be 1
            $targetPayload.TargetStateHistory[0].State | Should -Be 'Pending'
            $targetPayload.TargetStateHistory[0].Phase | Should -Be 'Queued'

            $summaryPayload = $historyLines[1] | ConvertFrom-Json
            $summaryPayload.RecordKind | Should -Be 'RunSummary'
            $summaryPayload.TargetState | Should -Be 'Succeeded'
            $summaryPayload.TargetStateCounts.Succeeded | Should -Be 1
            $summaryPayload.TerminalStateCounts.Succeeded | Should -Be 1
        }
        finally
        {
            $env:LOCALAPPDATA = $originalLocalAppData
            if (Test-Path -LiteralPath $tempRoot)
            {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    It 'persists artifact verification details on rollout outcomes' {
        $originalLocalAppData = $env:LOCALAPPDATA
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('Baseline-RolloutOutcome-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        try
        {
            $env:LOCALAPPDATA = $tempRoot
            $verification = [pscustomobject]@{
                VerificationState   = 'Valid'
                VerificationMessage = 'Artifact signature and timestamp verification succeeded.'
                HashAlgorithm       = 'SHA256'
                FileHash            = 'ABCDEF0123456789'
                SignatureStatus     = 'Valid'
                SignerSubject       = 'CN=Microsoft Corporation'
                TimestampStatus     = 'Present'
                TimestampSubject    = 'CN=Microsoft Time-Stamp Service'
                VerificationAt      = '2026-04-15T10:15:00Z'
            }

            $record = Write-BaselineRemoteRolloutOutcome -RunId 'run-001' -Operation 'RemoteApply' -Outcome 'Succeeded' -ArtifactVerification $verification -Details @{ Source = 'unit-test' }

            $record.ArtifactVerificationState | Should -Be 'Valid'
            $record.ArtifactFileHash | Should -Be 'ABCDEF0123456789'
            $record.ArtifactSignerSubject | Should -Be 'CN=Microsoft Corporation'
            $record.ArtifactTimestampStatus | Should -Be 'Present'
            $record.Details.ArtifactVerification.VerificationState | Should -Be 'Valid'

            $historyPath = Get-BaselineRemoteOrchestrationHistoryPath
            $historyLines = @(Get-Content -LiteralPath $historyPath -Encoding UTF8)
            $historyLines.Count | Should -Be 1
            $payload = $historyLines[0] | ConvertFrom-Json
            $payload.ArtifactVerificationState | Should -Be 'Valid'
            $payload.ArtifactFileHash | Should -Be 'ABCDEF0123456789'
            $payload.ArtifactTimestampSubject | Should -Be 'CN=Microsoft Time-Stamp Service'
        }
        finally
        {
            $env:LOCALAPPDATA = $originalLocalAppData
            if (Test-Path -LiteralPath $tempRoot)
            {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
