Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Logging.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Initialize-SessionStatistics', 'Update-SessionStatistics', 'Add-SessionStatistic', 'Get-SessionStatistics')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:FunctionTextByName = @{}
    foreach ($fn in $functions) {
        $script:FunctionTextByName[$fn.Name] = $fn.Extent.Text
    }
}

Describe 'Session statistics synchronization' {
    BeforeEach {
        $script:SessionStatisticsSyncRoot = [object]::new()
        $script:SessionStatistics = @{
            SessionStartTime    = $null
            PresetName          = $null
            TweaksSelected      = 0
            PreviewRunCount     = 0
            ApplyRunCount       = 0
            SucceededCount      = 0
            FailedCount         = 0
            SkippedCount        = 0
            NotApplicableCount  = 0
            NotRunCount         = 0
            IsGUI               = $false
            GameModeActive      = $false
            GameModeProfile     = $null
        }
    }

    It 'guards session statistics access with Monitor.Enter and Monitor.Exit' {
        foreach ($functionName in @('Initialize-SessionStatistics', 'Update-SessionStatistics', 'Add-SessionStatistic', 'Get-SessionStatistics')) {
            $script:FunctionTextByName[$functionName] | Should -Match '\[System\.Threading\.Monitor\]::Enter'
            $script:FunctionTextByName[$functionName] | Should -Match '\[System\.Threading\.Monitor\]::Exit'
        }
    }

    It 'increments only known counters' {
        Add-SessionStatistic -Name 'SucceededCount'
        Add-SessionStatistic -Name 'SucceededCount' -Increment 2
        Add-SessionStatistic -Name 'NotApplicableCount' -Increment 4
        Add-SessionStatistic -Name 'NotRunCount' -Increment 5
        Add-SessionStatistic -Name 'MissingCount' -Increment 99

        $stats = Get-SessionStatistics
        $stats.SucceededCount | Should -Be 3
        $stats.NotApplicableCount | Should -Be 4
        $stats.NotRunCount | Should -Be 5
        $stats.ContainsKey('MissingCount') | Should -BeFalse
    }

    It 'updates only known session statistic keys' {
        Update-SessionStatistics -Values @{
            PresetName = 'Balanced'
            ApplyRunCount = 4
            ImaginaryKey = 'ignored'
        }

        $stats = Get-SessionStatistics
        $stats.PresetName | Should -Be 'Balanced'
        $stats.ApplyRunCount | Should -Be 4
        $stats.ContainsKey('ImaginaryKey') | Should -BeFalse
    }

    It 'returns a clone snapshot' {
        $snapshot = Get-SessionStatistics
        $snapshot.SucceededCount = 42

        $stats = Get-SessionStatistics
        $stats.SucceededCount | Should -Be 0
    }

    It 'reinitializes the statistics hashtable under the same sync root' {
        $originalSyncRoot = $script:SessionStatisticsSyncRoot
        Add-SessionStatistic -Name 'FailedCount' -Increment 3

        Initialize-SessionStatistics

        $stats = Get-SessionStatistics
        $script:SessionStatisticsSyncRoot | Should -Be $originalSyncRoot
        $stats.FailedCount | Should -Be 0
        $stats.SessionStartTime | Should -Not -BeNullOrEmpty
    }
}
