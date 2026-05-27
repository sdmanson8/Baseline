Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    # Json helpers must load first — RemoteTarget calls ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    function Write-SwallowedException
    {
        param (
            [object]$ErrorRecord,
            [string]$Source
        )
    }

    $script:RemoteTargetHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemoteTarget.Helpers.ps1'
    $script:SharedHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1'
    $script:RemoteTargetHelpersContent = Get-BaselineTestSourceText -Path $script:RemoteTargetHelpersPath
    $script:SharedHelpersContent = Get-BaselineTestSourceText -Path $script:SharedHelpersPath
    . $script:RemoteTargetHelpersPath

    $script:ResumeTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineResumeTests_' + [guid]::NewGuid().ToString('N'))
    [System.Environment]::SetEnvironmentVariable('BASELINE_REMOTE_RESUME_DIR', $script:ResumeTempRoot)
}

AfterAll {
    [System.Environment]::SetEnvironmentVariable('BASELINE_REMOTE_RESUME_DIR', $null)
    if ($script:ResumeTempRoot -and (Test-Path -LiteralPath $script:ResumeTempRoot)) {
        Remove-Item -LiteralPath $script:ResumeTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Remote resume checkpoint contract' {
    BeforeEach {
        if (Test-Path -LiteralPath $script:ResumeTempRoot) {
            Remove-Item -LiteralPath $script:ResumeTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'declares the resume helpers and Resume-BaselineRemoteOrchestration verb' {
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteResumeDirectory'
        $script:RemoteTargetHelpersContent | Should -Match 'function Save-BaselineRemoteResumeCheckpoint'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteResumeCheckpoint'
        $script:RemoteTargetHelpersContent | Should -Match 'function Get-BaselineRemoteResumableRuns'
        $script:RemoteTargetHelpersContent | Should -Match 'function Clear-BaselineRemoteResumeCheckpoint'
        $script:RemoteTargetHelpersContent | Should -Match 'function Resolve-BaselineRemoteResumeTargets'
        $script:RemoteTargetHelpersContent | Should -Match 'function Resume-BaselineRemoteOrchestration'
    }

    It 'exports the resume helpers from the shared helpers module' {
        $script:SharedHelpersContent | Should -Match "'Save-BaselineRemoteResumeCheckpoint'"
        $script:SharedHelpersContent | Should -Match "'Get-BaselineRemoteResumableRuns'"
        $script:SharedHelpersContent | Should -Match "'Resume-BaselineRemoteOrchestration'"
        $script:SharedHelpersContent | Should -Match "'Clear-BaselineRemoteResumeCheckpoint'"
    }

    It 'persists a checkpoint with the targets it was created for and seeds Pending states' {
        $runId = 'test-run-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $checkpoint = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b', 'host-c') -Status 'Running'

        $checkpoint.RunId | Should -Be $runId
        $checkpoint.Operation | Should -Be 'RemoteApply'
        $checkpoint.Status | Should -Be 'Running'
        $checkpoint.Targets | Should -Be @('host-a', 'host-b', 'host-c')
        $checkpoint.TargetStates['host-a'] | Should -Be 'Pending'
        $checkpoint.TargetStates['host-b'] | Should -Be 'Pending'
        $checkpoint.TargetStates['host-c'] | Should -Be 'Pending'

        $path = Get-BaselineRemoteResumeCheckpointPath -RunId $runId
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'writes the checkpoint file atomically (no temp file left behind)' {
        $runId = 'atomic-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteCompliance' -ProfilePath 'C:\\profile.json' -Targets @('host-a') -Status 'Running'

        $tmpPath = (Get-BaselineRemoteResumeCheckpointPath -RunId $runId) + '.tmp'
        Test-Path -LiteralPath $tmpPath | Should -BeFalse
    }

    It 'merges partial target-state updates into the existing checkpoint' {
        $runId = 'merge-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-a' = 'Succeeded' } -Status 'Running'

        $loaded = @(Get-BaselineRemoteResumeCheckpoint -RunId $runId)
        $loaded.Count | Should -Be 1
        $loaded[0].TargetStates.'host-a' | Should -Be 'Succeeded'
        $loaded[0].TargetStates.'host-b' | Should -Be 'Pending'
        $loaded[0].Targets | Should -Be @('host-a', 'host-b')
    }

    It 'records the interrupt reason when status flips to Interrupted' {
        $runId = 'interrupt-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-b' = 'Cancelled' } -Status 'Interrupted' -InterruptReason 'Kill switch engaged during run.'

        $loaded = @(Get-BaselineRemoteResumeCheckpoint -RunId $runId)
        $loaded[0].Status | Should -Be 'Interrupted'
        $loaded[0].InterruptReason | Should -Be 'Kill switch engaged during run.'
        $loaded[0].TargetStates.'host-b' | Should -Be 'Cancelled'
    }

    It 'Clear-BaselineRemoteResumeCheckpoint removes the file' {
        $runId = 'clear-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a') -Status 'Running'
        $path = Get-BaselineRemoteResumeCheckpointPath -RunId $runId
        Test-Path -LiteralPath $path | Should -BeTrue

        Clear-BaselineRemoteResumeCheckpoint -RunId $runId
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'enumerates checkpoints and silently skips corrupt files' {
        $goodId = 'good-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $goodId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a') -Status 'Running'

        $corruptPath = Join-Path (Get-BaselineRemoteResumeDirectory) 'corrupt.json'
        [System.IO.File]::WriteAllText($corruptPath, '{ this is not valid json')

        $all = @(Get-BaselineRemoteResumeCheckpoint)
        $all.Count | Should -Be 1
        $all[0].RunId | Should -Be $goodId
    }
}

Describe 'Resumable run detection' {
    BeforeEach {
        if (Test-Path -LiteralPath $script:ResumeTempRoot) {
            Remove-Item -LiteralPath $script:ResumeTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns runs explicitly marked Interrupted that still have pending targets' {
        $runId = 'i-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-a' = 'Succeeded' } -Status 'Interrupted' -InterruptReason 'test'

        $resumable = @(Get-BaselineRemoteResumableRuns -StaleAfterMinutes 60)
        $resumable.Count | Should -Be 1
        $resumable[0].RunId | Should -Be $runId
        $resumable[0].PendingTargets | Should -Contain 'host-b'
        $resumable[0].PendingTargets | Should -Not -Contain 'host-a'
    }

    It 'does not surface completed runs' {
        $runId = 'c-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-a' = 'Succeeded' } -Status 'Completed'

        $resumable = @(Get-BaselineRemoteResumableRuns)
        $resumable.Count | Should -Be 0
    }

    It 'treats a stale Running checkpoint (beyond StaleAfterMinutes) as resumable' {
        $runId = 's-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b') -Status 'Running'

        $path = Get-BaselineRemoteResumeCheckpointPath -RunId $runId
        $raw = [System.IO.File]::ReadAllText($path)
        $obj = $raw | ConvertFrom-Json
        $obj.UpdatedAt = [DateTimeOffset]::UtcNow.AddHours(-3).ToString('o')
        [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 6))

        $resumable = @(Get-BaselineRemoteResumableRuns -StaleAfterMinutes 60)
        $resumable.Count | Should -Be 1
        $resumable[0].RunId | Should -Be $runId
    }

    It 'skips interrupted runs whose targets all landed in a terminal state' {
        $runId = 't-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-a' = 'Failed' } -Status 'Interrupted' -InterruptReason 'test'

        $resumable = @(Get-BaselineRemoteResumableRuns)
        $resumable.Count | Should -Be 0
    }
}

Describe 'Resolve-BaselineRemoteResumeTargets' {
    It 'returns only the pending/cancelled/running targets in original order' {
        $runId = 'r-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\profile.json' -Targets @('host-a', 'host-b', 'host-c', 'host-d') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates ([ordered]@{
            'host-a' = 'Succeeded'
            'host-b' = 'Failed'
            'host-c' = 'Cancelled'
            'host-d' = 'Pending'
        }) -Status 'Interrupted' -InterruptReason 'test'

        $checkpoint = (Get-BaselineRemoteResumeCheckpoint -RunId $runId)[0]
        $pending = @(Resolve-BaselineRemoteResumeTargets -Checkpoint $checkpoint)
        $pending | Should -Be @('host-c', 'host-d')
    }
}

Describe 'Resume-BaselineRemoteOrchestration' {
    BeforeEach {
        if (Test-Path -LiteralPath $script:ResumeTempRoot) {
            Remove-Item -LiteralPath $script:ResumeTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the checkpoint does not exist' {
        { Resume-BaselineRemoteOrchestration -RunId 'does-not-exist' } | Should -Throw "*No resume checkpoint found*"
    }

    It 'throws when the referenced profile is missing' {
        $runId = 'no-profile-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath 'C:\\nope\\missing-profile.json' -Targets @('host-a') -Status 'Interrupted' -InterruptReason 'test'

        { Resume-BaselineRemoteOrchestration -RunId $runId } | Should -Throw "*profile that cannot be found*"
    }

    It 'returns Resumed=$false and clears the checkpoint when no targets remain pending' {
        $runId = 'done-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (-not (Test-Path -LiteralPath $script:ResumeTempRoot)) { [void][System.IO.Directory]::CreateDirectory($script:ResumeTempRoot) }
        $profilePath = Join-Path $script:ResumeTempRoot ('profile-{0}.json' -f $runId)
        [System.IO.File]::WriteAllText($profilePath, '{}')
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath $profilePath -Targets @('host-a') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates @{ 'host-a' = 'Succeeded' } -Status 'Interrupted' -InterruptReason 'test'

        $response = Resume-BaselineRemoteOrchestration -RunId $runId
        $response.Resumed | Should -BeFalse

        Test-Path -LiteralPath (Get-BaselineRemoteResumeCheckpointPath -RunId $runId) | Should -BeFalse
    }

    It 'dispatches only pending targets via Invoke-BaselineRemoteApply' {
        $runId = 'dispatch-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (-not (Test-Path -LiteralPath $script:ResumeTempRoot)) { [void][System.IO.Directory]::CreateDirectory($script:ResumeTempRoot) }
        $profilePath = Join-Path $script:ResumeTempRoot ('profile-{0}.json' -f $runId)
        [System.IO.File]::WriteAllText($profilePath, '{}')
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -ProfilePath $profilePath -Targets @('host-a', 'host-b', 'host-c') -Status 'Running'
        $null = Save-BaselineRemoteResumeCheckpoint -RunId $runId -Operation 'RemoteApply' -TargetStates ([ordered]@{
            'host-a' = 'Succeeded'
            'host-b' = 'Cancelled'
            'host-c' = 'Pending'
        }) -Status 'Interrupted' -InterruptReason 'test'

        Mock -CommandName 'Invoke-BaselineRemoteApply' -MockWith {
            param (
                [string[]]$ComputerName,
                [string]$ProfilePath,
                [int]$MaxRetryCount = 2,
                [int]$RetryDelayMilliseconds = 250,
                [string]$ResumeRunId,
                [System.Management.Automation.PSCredential]$Credential
            )
            return @(
                [pscustomobject]@{ ComputerName = 'host-b'; TerminalState = 'Succeeded'; ResumeRunId = $ResumeRunId }
                [pscustomobject]@{ ComputerName = 'host-c'; TerminalState = 'Succeeded'; ResumeRunId = $ResumeRunId }
            )
        }

        $response = Resume-BaselineRemoteOrchestration -RunId $runId
        $response.Resumed | Should -BeTrue
        $response.Results.Count | Should -Be 2
        Should -Invoke -CommandName 'Invoke-BaselineRemoteApply' -Times 1 -ParameterFilter {
            (@($ComputerName) -join ',') -eq 'host-b,host-c' -and $ResumeRunId -eq $runId
        }
    }
}
