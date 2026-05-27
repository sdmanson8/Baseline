Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/PostActions.psm1'
    $script:PostActionsExtractedContent = Get-Content -Raw (Join-Path $PSScriptRoot '../../Module/Regions/PostActions/PostActions/PostActions.ps1')
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    # test the small post-action helper functions in isolation.
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    # Exclude the outer PostActions function itself (it performs global state
    # mutation and is not meaningful at unit level).
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'PostActions') { continue }
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'PostActions temporary policy cleanup' {
    It 'removes optional Baseline policy temp files only after literal path existence checks' {
        $script:PostActionsExtractedContent | Should -Match 'Join-Path \$env:TEMP ''Computer\.txt'''
        $script:PostActionsExtractedContent | Should -Match 'Test-Path -LiteralPath \$temporaryPolicyFile'
        $script:PostActionsExtractedContent | Should -Match 'Remove-Item -LiteralPath \$temporaryPolicyFile'
        $script:PostActionsExtractedContent | Should -Match 'Resolve-BaselinePolicyToolPath'
        $script:PostActionsExtractedContent | Should -Not -Match 'Binaries\\'
        $script:PostActionsExtractedContent | Should -Not -Match 'Get-ChildItem -Path "\$env:TEMP\\Computer\.txt", "\$env:TEMP\\User\.txt"'
    }
}

Describe 'PostActions Explorer restart' {
    It 'explicitly relaunches Explorer after stopping the shell' {
        $script:PostActionsExtractedContent | Should -Match 'Restarting Explorer shell'
        $script:PostActionsExtractedContent | Should -Match "Invoke-UserLaunch -FilePath 'explorer\.exe' -Description 'Explorer shell restart after post actions'"
    }
}

Describe 'Get-PostActionRequirement' {
    BeforeEach {
        $Global:BaselinePostActionRequirements = $null
    }

    AfterEach {
        Remove-Variable -Name BaselinePostActionRequirements -Scope Global -ErrorAction SilentlyContinue
    }

    It 'returns $false when the global state is not a hashtable' {
        $Global:BaselinePostActionRequirements = 'not a hashtable'

        Get-PostActionRequirement -Name 'Missing' | Should -BeFalse
    }

    It 'returns $false when the key is missing' {
        $Global:BaselinePostActionRequirements = @{ OtherKey = $true }

        Get-PostActionRequirement -Name 'Missing' | Should -BeFalse
    }

    It 'returns $true when the key is present and truthy' {
        $Global:BaselinePostActionRequirements = @{ RefreshShell = $true }

        Get-PostActionRequirement -Name 'RefreshShell' | Should -BeTrue
    }

    It 'returns $false when the key is present but falsy' {
        $Global:BaselinePostActionRequirements = @{ RefreshShell = $false }

        Get-PostActionRequirement -Name 'RefreshShell' | Should -BeFalse
    }
}

Describe 'Invoke-PostActionStep' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:handledErrors = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function Remove-HandledErrorRecord {
            param([object]$ErrorRecord)
            [void]$script:handledErrors.Add($ErrorRecord)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','Remove-HandledErrorRecord')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'reports success when the scriptblock runs without throwing' {
        Invoke-PostActionStep -Action 'test step' -ScriptBlock { 1 + 1 | Out-Null }

        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'rethrows and reports failed when ScriptBlock throws and -ContinueOnFailure is not set' {
        { Invoke-PostActionStep -Action 'test step' -ScriptBlock { throw 'boom' } } |
            Should -Throw 'boom'
        $script:consoleStatuses[-1] | Should -Be 'failed'
    }

    It 'suppresses exceptions and reports warning when -ContinueOnFailure is set' {
        Invoke-PostActionStep -Action 'test step' -ScriptBlock { throw 'explain' } -ContinueOnFailure

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'test step was skipped'
        $script:handledErrors.Count | Should -Be 1
    }
}

Describe 'Invoke-PostActionProcess' {
    BeforeEach {
        $script:startProcessCalls = [System.Collections.Generic.List[object]]::new()
        $script:stopProcessTreeCalls = [System.Collections.Generic.List[object]]::new()
        $script:processExitCode = 0
        $script:processTimesOut = $false

        function Start-Process {
            param(
                [string]$FilePath,
                [string[]]$ArgumentList,
                [string]$WindowStyle,
                [switch]$PassThru,
                [string]$RedirectStandardOutput,
                [string]$RedirectStandardError
            )
            [void]$script:startProcessCalls.Add([pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList })

            # Return an object with WaitForExit / Refresh / ExitCode / Dispose / Id.
            $proc = [pscustomobject]@{
                Id       = 4242
                ExitCode = $script:processExitCode
            }
            Add-Member -InputObject $proc -MemberType ScriptMethod -Name 'WaitForExit' -Value {
                param($ms)
                return -not $script:processTimesOut
            } -Force
            Add-Member -InputObject $proc -MemberType ScriptMethod -Name 'Refresh' -Value { } -Force
            Add-Member -InputObject $proc -MemberType ScriptMethod -Name 'Dispose' -Value { } -Force
            return $proc
        }
        function Stop-BaselineProcessTree {
            param([object]$Process, [string]$Source)
            [void]$script:stopProcessTreeCalls.Add([pscustomobject]@{ Process = $Process; Source = $Source })
        }
    }

    AfterEach {
        foreach ($n in @('Start-Process','Stop-BaselineProcessTree')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'returns quietly when the process exits with code 0' {
        $script:processExitCode = 0

        { Invoke-PostActionProcess -FilePath 'fake.exe' -Description 'demo' } | Should -Not -Throw
        $script:startProcessCalls.Count | Should -Be 1
    }

    It 'throws when the process returns a non-zero exit code' {
        $script:processExitCode = 7

        { Invoke-PostActionProcess -FilePath 'fake.exe' -Description 'demo' } |
            Should -Throw '*exit code 7*'
    }

    It 'attempts to stop the process and throws on timeout' {
        $script:processTimesOut = $true

        { Invoke-PostActionProcess -FilePath 'fake.exe' -Description 'demo' -TimeoutSeconds 1 } |
            Should -Throw '*timed out*'
        $script:stopProcessTreeCalls.Count | Should -Be 1
        $script:stopProcessTreeCalls[0].Process.Id | Should -Be 4242
        $script:stopProcessTreeCalls[0].Source | Should -Be 'PostActions.ProcessTimeout'
    }

    It 'passes ArgumentList through to Start-Process' {
        Invoke-PostActionProcess -FilePath 'fake.exe' -ArgumentList @('-a','b') -Description 'demo'

        $script:startProcessCalls[0].ArgumentList -join ',' | Should -Be '-a,b'
    }
}
