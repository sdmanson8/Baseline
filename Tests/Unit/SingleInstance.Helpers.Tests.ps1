Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SingleInstance.Helpers.ps1'
    . $filePath

    function script:NewMutexName {
        return ('Local\Baseline-Test-{0}' -f ([guid]::NewGuid().ToString('N')))
    }
}

Describe 'Get-BaselineSingleInstanceMutexName' {
    It 'returns the canonical Local\Baseline-SingleInstance-<user> shape' {
        $name = Get-BaselineSingleInstanceMutexName -UserName 'alice'
        $name | Should -Be 'Local\Baseline-SingleInstance-alice'
    }

    It 'lowercases the username' {
        $name = Get-BaselineSingleInstanceMutexName -UserName 'AliceCAPS'
        $name | Should -Be 'Local\Baseline-SingleInstance-alicecaps'
    }

    It 'sanitizes domain backslashes so they do not introduce a path component' {
        $name = Get-BaselineSingleInstanceMutexName -UserName 'CONTOSO\jdoe'
        $name | Should -Be 'Local\Baseline-SingleInstance-contoso_jdoe'
        ($name -split 'Baseline-SingleInstance-')[1] | Should -Not -Match '\\'
    }

    It 'sanitizes UPN-form usernames (allows @ as _ since @ is not in the allowlist)' {
        $name = Get-BaselineSingleInstanceMutexName -UserName 'jdoe@contoso.com'
        $name | Should -Be 'Local\Baseline-SingleInstance-jdoe_contoso.com'
    }

    It 'preserves dot, underscore, and hyphen' {
        $name = Get-BaselineSingleInstanceMutexName -UserName 'first.last_v2-svc'
        $name | Should -Be 'Local\Baseline-SingleInstance-first.last_v2-svc'
    }

    It 'falls back to "unknown" when the username sanitizes to nothing' {
        $name = Get-BaselineSingleInstanceMutexName -UserName '???'
        $name | Should -Be 'Local\Baseline-SingleInstance-unknown'
    }

    It 'gives different users different mutex names so RDS-style sessions do not collide' {
        $a = Get-BaselineSingleInstanceMutexName -UserName 'alice'
        $b = Get-BaselineSingleInstanceMutexName -UserName 'bob'
        $a | Should -Not -Be $b
    }
}

Describe 'Test-BaselineSingleInstanceLockAvailable' {
    It 'acquires the lock on first call (CreatedNew=$true)' {
        $name = NewMutexName
        $r = Test-BaselineSingleInstanceLockAvailable -MutexName $name
        try {
            $r.Acquired   | Should -BeTrue
            $r.CreatedNew | Should -BeTrue
            $r.Mutex      | Should -Not -BeNullOrEmpty
            $r.Error      | Should -BeNullOrEmpty
        } finally {
            if ($r.Mutex) { try { $r.Mutex.ReleaseMutex() } catch { $null = $_ }; try { $r.Mutex.Dispose() } catch { $null = $_ } }
        }
    }

    It 'fails to acquire when the same mutex is already owned by another thread (Acquired=$false)' {
        # Mutexes are thread-affine — a recursive WaitOne on the *same* thread
        # would succeed, so the contention check must run from a different
        # thread to mirror the real scenario (two Baseline.exe processes).
        $name = NewMutexName
        $first = Test-BaselineSingleInstanceLockAvailable -MutexName $name
        try {
            $helperPath = (Resolve-Path (Join-Path $PSScriptRoot '../../Module/SharedHelpers/SingleInstance.Helpers.ps1')).Path
            $ps = [PowerShell]::Create()
            try {
                $null = $ps.AddScript({
                    param($helper, $mutexName)
                    . $helper
                    Test-BaselineSingleInstanceLockAvailable -MutexName $mutexName
                }).AddArgument($helperPath).AddArgument($name)
                $second = $ps.Invoke()[0]
            } finally {
                $ps.Dispose()
            }
            $second.Acquired   | Should -BeFalse
            $second.CreatedNew | Should -BeFalse
            $second.Mutex      | Should -BeNullOrEmpty
        } finally {
            if ($first.Mutex) { try { $first.Mutex.ReleaseMutex() } catch { $null = $_ }; try { $first.Mutex.Dispose() } catch { $null = $_ } }
        }
    }

    It 'returns Acquired=$false (not throw) when given an invalid mutex name' {
        # Backslashes inside the suffix portion are invalid for kernel objects.
        $r = Test-BaselineSingleInstanceLockAvailable -MutexName ('Local\bad\name-' + [guid]::NewGuid().ToString('N'))
        $r.Acquired | Should -BeFalse
        $r.Error    | Should -Not -BeNullOrEmpty
    }
}

Describe 'Find-BaselineRunningInstance' {
    It 'returns $null when nothing matches the pattern' {
        $r = Find-BaselineRunningInstance -CurrentProcessId 1 -ProcessLister { @() }
        $r | Should -BeNullOrEmpty
    }

    It 'excludes the current PID' {
        $lister = {
            @(
                [pscustomobject]@{ Id = 4242; ProcessName = 'Baseline'; MainWindowHandle = [IntPtr]::new(1234) }
            )
        }
        $r = Find-BaselineRunningInstance -CurrentProcessId 4242 -ProcessLister $lister
        $r | Should -BeNullOrEmpty
    }

    It 'drops processes with a zero MainWindowHandle (no top-level window)' {
        $lister = {
            @(
                [pscustomobject]@{ Id = 9001; ProcessName = 'Baseline'; MainWindowHandle = [IntPtr]::Zero }
            )
        }
        $r = Find-BaselineRunningInstance -CurrentProcessId 1 -ProcessLister $lister
        $r | Should -BeNullOrEmpty
    }

    It 'returns the lowest-PID match (deterministic across multiple slots)' {
        $lister = {
            @(
                [pscustomobject]@{ Id = 9999; ProcessName = 'Baseline'; MainWindowHandle = [IntPtr]::new(2222) }
                [pscustomobject]@{ Id = 5555; ProcessName = 'Baseline'; MainWindowHandle = [IntPtr]::new(1111) }
                [pscustomobject]@{ Id = 7777; ProcessName = 'Baseline'; MainWindowHandle = [IntPtr]::new(3333) }
            )
        }
        $r = Find-BaselineRunningInstance -CurrentProcessId 1 -ProcessLister $lister
        $r.ProcessId        | Should -Be 5555
        $r.MainWindowHandle | Should -Be ([IntPtr]::new(1111))
        $r.ProcessName      | Should -Be 'Baseline'
    }

    It 'matches process names by prefix (Baseline.exe and Baseline-foo)' {
        $lister = {
            @(
                [pscustomobject]@{ Id = 100; ProcessName = 'Notepad'; MainWindowHandle = [IntPtr]::new(5) }
                [pscustomobject]@{ Id = 200; ProcessName = 'BaselineLauncher'; MainWindowHandle = [IntPtr]::new(7) }
            )
        }
        $r = Find-BaselineRunningInstance -CurrentProcessId 1 -ProcessLister $lister
        $r.ProcessId | Should -Be 200
    }

    It 'tolerates a thrown ProcessLister and returns $null' {
        $lister = { throw 'boom' }
        $r = Find-BaselineRunningInstance -CurrentProcessId 1 -ProcessLister $lister
        $r | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-BaselineSingleInstanceDecision' {
    It 'returns Continue when AllowMultipleInstances is set (CI escape hatch)' {
        $r = Resolve-BaselineSingleInstanceDecision -LockResult ([pscustomobject]@{ Acquired = $false }) -AllowMultipleInstances
        $r.Action | Should -Be 'Continue'
        $r.Reason | Should -Match 'AllowMultipleInstances'
    }

    It 'returns Continue when the lock was acquired' {
        $lock = [pscustomobject]@{ Acquired = $true; CreatedNew = $true; Mutex = $null; Error = $null }
        $r = Resolve-BaselineSingleInstanceDecision -LockResult $lock
        $r.Action | Should -Be 'Continue'
        $r.TargetProcessId | Should -BeNullOrEmpty
    }

    It 'returns HandoffAndExit when the lock is unavailable AND a running instance was found' {
        $lock = [pscustomobject]@{ Acquired = $false }
        $running = [pscustomobject]@{ ProcessId = 4242; MainWindowHandle = [IntPtr]::new(99) }
        $r = Resolve-BaselineSingleInstanceDecision -LockResult $lock -RunningInstance $running
        $r.Action          | Should -Be 'HandoffAndExit'
        $r.TargetProcessId | Should -Be 4242
        $r.TargetHandle    | Should -Be ([IntPtr]::new(99))
        $r.Reason          | Should -Match '4242'
    }

    It 'returns HandoffAndExit when the lock is unavailable but no running instance was found' {
        $lock = [pscustomobject]@{ Acquired = $false }
        $r = Resolve-BaselineSingleInstanceDecision -LockResult $lock -RunningInstance $null
        $r.Action          | Should -Be 'HandoffAndExit'
        $r.TargetProcessId | Should -BeNullOrEmpty
    }

    It 'does not attempt foregrounding when the lock holder has no discoverable window yet' {
        $name = NewMutexName
        $first = Test-BaselineSingleInstanceLockAvailable -MutexName $name
        try {
            $helperPath = (Resolve-Path (Join-Path $PSScriptRoot '../../Module/SharedHelpers/SingleInstance.Helpers.ps1')).Path
            $ps = [PowerShell]::Create()
            try {
                $null = $ps.AddScript({
                    param($helper, $mutexName)
                    . $helper
                    Acquire-BaselineSingleInstance -MutexName $mutexName -ProcessLister { @() }
                }).AddArgument($helperPath).AddArgument($name)
                $second = $ps.Invoke()[0]
            } finally {
                $ps.Dispose()
            }
            $second.Decision.Action | Should -Be 'HandoffAndExit'
            $second.Decision.TargetHandle | Should -BeNullOrEmpty
            $second.ForegroundResult | Should -BeNullOrEmpty
        } finally {
            if ($first.Mutex) { try { $first.Mutex.ReleaseMutex() } catch { $null = $_ }; try { $first.Mutex.Dispose() } catch { $null = $_ } }
        }
    }
}

Describe 'Invoke-BaselineSingleInstanceForeground' {
    It 'returns Succeeded=$false (and does not throw) when the handle is zero' {
        $r = Invoke-BaselineSingleInstanceForeground -WindowHandle ([IntPtr]::Zero)
        $r.Succeeded | Should -BeFalse
        $r.Reason    | Should -Match 'zero'
    }

    It 'returns Succeeded=$false (and does not throw) for a bogus non-zero handle' {
        # 0xDEADBEEF is not a real window — SetForegroundWindow should return false.
        $r = Invoke-BaselineSingleInstanceForeground -WindowHandle ([IntPtr]::new(0xDEADBEEF))
        $r.Succeeded | Should -BeFalse
        $r.Reason    | Should -Not -BeNullOrEmpty
    }
}
