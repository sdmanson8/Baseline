Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/Logging.psm1'
    $script:LoggingContent = Get-BaselineTestSourceText -Path $filePath
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Add-PendingLogMessage', 'Restore-PendingLogMessages', 'Write-PendingLogMessagesToFile', 'Write-LogMessage', 'Get-BaselineRunId', 'Get-BaselineRunIdShort', 'Set-BaselineRunId', 'New-BaselineSessionLogPath', 'Reset-LogStatistics', 'Set-LogFile', 'Get-BaselineCurrentOperationScope', 'Start-BaselineOperationScope', 'Set-BaselineOperationFailed', 'Stop-BaselineOperationScope', 'ConvertTo-BaselineLogScopeText', 'Get-BaselineLogScope', 'Set-BaselineLogScope', 'Clear-BaselineLogScope', 'Resolve-BaselineLogScope', 'Format-BaselineErrorForLog', 'Write-BaselineError', 'Write-ConsoleStatus')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    function Send-UILogEntry {
        param([psobject]$Entry)
        return $true
    }

    function New-TestLogMutex {
        param(
            [bool[]]$WaitResults
        )

        $state = [pscustomobject]@{
            WaitResults   = [System.Collections.Generic.Queue[bool]]::new()
            WaitArguments = [System.Collections.Generic.List[int]]::new()
            ReleaseCount  = 0
        }

        foreach ($result in @($WaitResults)) {
            $state.WaitResults.Enqueue([bool]$result)
        }

        $mutex = [pscustomobject]@{
            State = $state
        }

        $null = $mutex | Add-Member -MemberType ScriptMethod -Name WaitOne -Value {
            param([int]$MillisecondsTimeout)
            [void]$this.State.WaitArguments.Add([int]$MillisecondsTimeout)
            if ($this.State.WaitResults.Count -eq 0) {
                return $false
            }

            return $this.State.WaitResults.Dequeue()
        } -Force

        $null = $mutex | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value {
            $this.State.ReleaseCount++
        } -Force

        return $mutex
    }
}

Describe 'Operation failure scopes' {
    BeforeEach {
        $script:OperationScopeStack = [System.Collections.Generic.List[object]]::new()
        $script:ConsoleStatusContext = $null
        $script:CapturedUiEntries = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage {}

        function Send-UILogEntry {
            param([psobject]$Entry)
            [void]$script:CapturedUiEntries.Add($Entry)
            return $true
        }

        function Write-Host { param([object]$Object, [switch]$NoNewline, [string]$ForegroundColor) }
    }

    AfterEach {
        Remove-Item Function:\Send-UILogEntry -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-Host -ErrorAction SilentlyContinue
    }

    It 'marks the current operation failed when Write-BaselineError is called' {
        $scope = Start-BaselineOperationScope -Name 'Unit operation'

        Write-BaselineError -Message 'operation failed'
        $result = Stop-BaselineOperationScope -Scope $scope

        $result.Failed | Should -BeTrue
        @($result.FailureReasons).Count | Should -Be 1
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $Level -eq 'ERROR'
        }
    }

    It 'does not report success for a console action whose scope was marked failed' {
        Write-ConsoleStatus -Action 'Scoped action'
        Write-BaselineError -Message 'inner failure'
        Write-ConsoleStatus -Status success

        $statusEntry = @($script:CapturedUiEntries | Where-Object { $_.Kind -eq 'ConsoleStatus' }) | Select-Object -Last 1
        $statusEntry.Status | Should -Be 'failed'
        $script:OperationScopeStack.Count | Should -Be 0
    }
}

Describe 'New-BaselineSessionLogPath' {
    It 'creates a date folder and timestamped log filename' {
        $root = Join-Path $TestDrive 'logs'
        [void][System.IO.Directory]::CreateDirectory($root)

        $sessionStart = [datetime]::ParseExact('2026-04-27 09:15:33.123', 'yyyy-MM-dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture)

        $path = New-BaselineSessionLogPath -LogDirectory $root -OsName 'Windows 11' -SessionStart $sessionStart

        $dateFolder = $sessionStart.ToString('yyyy-MM-dd')
        $fileName = '{0} Baseline - Utility for Windows 11.log' -f $sessionStart.ToString('HH-mm-ss')
        $expectedPath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $root $dateFolder) $fileName))

        $path | Should -Be $expectedPath
        [System.IO.Path]::GetFileName($path) | Should -Be $fileName
        (Split-Path -Parent $path) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $root $dateFolder)))
    }
}

Describe 'Set-LogFile' {
    It 'creates the nested session directory and log header' {
        $script:DebugLoggingEnabled = $false
        $script:RunId = $null
        $script:RunIdShort = $null
        $root = Join-Path $TestDrive 'logs'
        $sessionStart = [datetime]::ParseExact('2026-04-27 09:15:33.123', 'yyyy-MM-dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture)
        $path = New-BaselineSessionLogPath -LogDirectory $root -OsName 'Windows 11' -SessionStart $sessionStart

        Set-LogFile -Path $path

        [System.IO.Directory]::Exists((Split-Path -Parent $path)) | Should -BeTrue
        [System.IO.File]::Exists($path) | Should -BeTrue

        $content = [System.IO.File]::ReadAllText($path)
        $content | Should -Match '^=== Log Started at '
        $content | Should -Match 'SessionId='
        $content | Should -Not -Match 'RunId='
    }
}

Describe 'Write-LogMessage backlog handling' {
    BeforeEach {
        $script:LogFilePath = Join-Path $TestDrive 'baseline.log'
        $script:LogMode = $null
        $script:LogScope = 'Baseline'
        $script:DefaultLogMutexTimeoutMs = 5000
        $script:LogMutexRetryBackoffMs = @(100, 250, 500)
        $script:LogStatistics = @{
            Info = 0
            Warning = 0
            Error = 0
        }
        $script:PendingLogMessages = [System.Collections.Generic.List[string]]::new()
        $script:PendingLogMessagesSyncRoot = [object]::new()
        $script:CapturedHostMessages = [System.Collections.Generic.List[string]]::new()
        $script:CapturedWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CapturedSleeps = [System.Collections.Generic.List[int]]::new()
        Set-BaselineRunId -RunId 'aaaaaaaa-1111-2222-3333-444444444444'

        function Write-Host {
            param(
                [string]$Object,
                [string]$ForegroundColor,
                [switch]$NoNewline
            )

            [void]$script:CapturedHostMessages.Add([string]$Object)
        }

        function Write-Warning {
            param([string]$Message)
            [void]$script:CapturedWarnings.Add([string]$Message)
        }

        function Start-Sleep {
            param([int]$Milliseconds)
            [void]$script:CapturedSleeps.Add([int]$Milliseconds)
        }
    }

    AfterEach {
        foreach ($functionName in @('Write-Host', 'Write-Warning', 'Start-Sleep')) {
            Remove-Item -Path ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        if ($script:LogFilePath -and (Test-Path -LiteralPath $script:LogFilePath)) {
            Remove-Item -LiteralPath $script:LogFilePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'flushes queued messages before the current write when the mutex is available' {
        [void]$script:PendingLogMessages.Add('queued log line')
        $script:LogLock = New-TestLogMutex -WaitResults @($true)

        Write-LogMessage -Message 'current write'

        $content = [System.IO.File]::ReadAllText($script:LogFilePath)
        $lines = @($content -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 2
        $lines[0] | Should -Be 'queued log line'
        $lines[1] | Should -Match '^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Baseline\] current write$'
        $script:PendingLogMessages.Count | Should -Be 0
        $script:LogLock.State.ReleaseCount | Should -Be 1
    }

    It 'queues timed-out messages and flushes them on the next successful write' {
        $script:LogLock = New-TestLogMutex -WaitResults @($false, $false, $false, $false)

        Write-LogMessage -Message 'first write'

        $script:PendingLogMessages.Count | Should -Be 1
        $script:PendingLogMessages[0] | Should -Match 'INFO: \[RunId=aaaaaaaa\] \[Baseline\] first write'
        $script:CapturedSleeps.ToArray() | Should -Be @(100, 250, 500)
        $script:CapturedHostMessages[0] | Should -Match 'queued for retry'

        $script:LogLock = New-TestLogMutex -WaitResults @($true)

        Write-LogMessage -Message 'second write'

        $content = [System.IO.File]::ReadAllText($script:LogFilePath)
        $lines = @($content -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Baseline\] first write$'
        $lines[1] | Should -Match '^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Baseline\] second write$'
        $script:PendingLogMessages.Count | Should -Be 0
    }

    It 'always emits a scope segment and keeps transient operation names out of the scope field' {
        $script:LogLock = New-TestLogMutex -WaitResults @($true, $true, $true)

        Write-LogMessage -Message 'default scoped write'
        Set-BaselineLogScope -Scope 'Bootstrap'
        Write-LogMessage -Message 'phase scoped write'
        $scope = Start-BaselineOperationScope -Name 'Checking installation status...'
        try {
            Write-LogMessage -Message 'operation scoped write'
        }
        finally {
            $null = Stop-BaselineOperationScope -Scope $scope
        }

        $content = [System.IO.File]::ReadAllText($script:LogFilePath)
        $content | Should -Match '(?m)^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Baseline\] default scoped write\r?$'
        $content | Should -Match '(?m)^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Bootstrap\] phase scoped write\r?$'
        $content | Should -Match '(?m)^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[Bootstrap\] operation scoped write\r?$'
        $content | Should -Not -Match '\[Checking installation status\.\.\.\]'
    }

    It 'uses an explicit operation log scope without using the human action text' {
        $script:LogLock = New-TestLogMutex -WaitResults @($true)

        $scope = Start-BaselineOperationScope -Name 'Checking installation status...' -LogScope 'PackageManager'
        try {
            Write-LogMessage -Message 'package manager scoped write'
        }
        finally {
            $null = Stop-BaselineOperationScope -Scope $scope
        }

        $content = [System.IO.File]::ReadAllText($script:LogFilePath)
        $content | Should -Match '(?m)^\d{2}-\d{2}-\d{4} \d{2}:\d{2} INFO: \[RunId=aaaaaaaa\] \[PackageManager\] package manager scoped write\r?$'
        $content | Should -Not -Match '\[Checking installation status\.\.\.\]'
    }

    It 'retries timed-out writes with the configured backoff sequence' {
        $script:LogLock = New-TestLogMutex -WaitResults @($false, $false, $false, $false)

        Write-LogMessage -Message 'retry target'

        $script:LogLock.State.WaitArguments.ToArray() | Should -Be @(5000, 0, 0, 0)
        $script:CapturedSleeps.ToArray() | Should -Be @(100, 250, 500)
        $script:PendingLogMessages.Count | Should -Be 1
    }

    It 'routes log mutex release failures through Write-SwallowedException with Debug severity' {
        $script:LoggingContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Logging\.Write\.WriteLogMessage\.ReleaseMutex'' -Severity Debug'
    }
}
