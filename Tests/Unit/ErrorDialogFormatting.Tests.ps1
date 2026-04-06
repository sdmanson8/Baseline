Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/ErrorHandling.Helpers.ps1')
}

Describe 'User-facing error dialog formatting' {
    It 'returns a friendly title and guidance for startup errors' {
        $errorInfo = Get-BaselineErrorInfo -Exception ([System.InvalidOperationException]::new('First-run welcome failed: test')) -Context 'GUI startup'

        $errorInfo.Code | Should -Be 'GUI-STARTUP-003'
        $errorInfo.Title | Should -Be "Baseline Couldn't Finish Setup"
        $errorInfo.Message | Should -Match 'first-run welcome experience'
        $errorInfo.StageDescription | Should -Be 'while starting the app.'
        @($errorInfo.NextSteps).Count | Should -BeGreaterThan 0
    }

    It 'formats dialogs with actions and a reference instead of the old error code label' {
        $message = Format-BaselineErrorDialogMessage -ErrorInfo ([pscustomobject]@{
            Code = 'GUI-STARTUP-003'
            Message = 'Baseline hit a problem while preparing its first-run welcome experience.'
            StageDescription = 'while starting the app.'
            NextSteps = @(
                'Close Baseline and open it again.',
                'Use the log file below to see which startup step failed.'
            )
        }) -LogPath 'C:\Temp\baseline.log' -IncludeLogPath

        $message | Should -Match 'Try this:'
        $message | Should -Match 'This happened while starting the app\.'
        $message | Should -Match 'Reference: GUI-STARTUP-003'
        $message | Should -Match 'C:\\Temp\\baseline\.log'
        $message | Should -Not -Match 'Error code:'
        $message | Should -Not -Match 'Something went wrong\. Please restart the application and try again\.'
    }
}
