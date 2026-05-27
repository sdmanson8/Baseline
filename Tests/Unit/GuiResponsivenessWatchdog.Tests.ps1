Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:watchdogPath = Join-Path $PSScriptRoot '../../Module/GUI/GuiResponsivenessWatchdog.ps1'
    $script:showDialogPath = Join-Path $PSScriptRoot '../../Module/GUI/Show-TweakGUI/ShowDialogErrorHandling.ps1'
    $script:guiModulePath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:WatchdogContent = Get-BaselineTestSourceText -Path $script:watchdogPath
    $script:ShowDialogContent = Get-BaselineTestSourceText -Path $script:showDialogPath
    $script:GuiModuleContent = Get-BaselineTestSourceText -Path $script:guiModulePath

    . $script:watchdogPath
}

Describe 'GUI responsiveness watchdog' {
    It 'logs a GUI hang when the dispatcher does not complete a heartbeat' {
        $logPath = Join-Path $TestDrive 'baseline-watchdog.log'
        Initialize-GuiResponsivenessWatchdogType
        $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        $watchdog = [Baseline.GuiResponsivenessWatchdog]::new($dispatcher, $logPath, 'unit1234', 50, 1000, 'Unit Test Window')

        try {
            $watchdog.Start()
            Start-Sleep -Milliseconds 1500
            $watchdog.Stop()
        }
        finally {
            $watchdog.Dispose()
        }

        $logText = [System.IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)
        $logText | Should -Match 'DEBUG: \[RunId=unit1234\] \[GUI\] GUI responsiveness failure'
        $logText | Should -Match 'Close now or wait'
        $logText | Should -Match 'GUI crash/hang'
    }

    It 'loads before ShowDialog and stops in the ShowDialog finally block' {
        $script:GuiModuleContent | Should -Match 'Join-Path \$Script:GuiExtractedRoot ''GuiResponsivenessWatchdog\.ps1'''
        $script:ShowDialogContent | Should -Match 'Start-GuiResponsivenessWatchdog -Window \$Form'
        $script:ShowDialogContent | Should -Match 'finally\s*\{(?s).*Stop-GuiResponsivenessWatchdog -Watchdog \$guiResponsivenessWatchdog'
    }

    It 'writes directly through System.IO instead of dispatcher-bound logging' {
        $script:WatchdogContent | Should -Match 'File\.AppendAllText'
        $script:WatchdogContent | Should -Not -Match 'LogError'
        $script:WatchdogContent | Should -Not -Match 'Add-Content'
    }
}
