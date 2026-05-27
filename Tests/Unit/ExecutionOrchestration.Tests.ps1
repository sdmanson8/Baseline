Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $executionPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration.ps1'
    $executionStateSummaryPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionStateSummary.ps1'
    $executionViewPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionView.ps1'
    $executionRunPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionRunOrchestration.ps1'
    $appExecutionRunPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionRunOrchestration/Start-GuiAppExecutionRun/Start-GuiAppExecutionRun.ps1'
    $executionWorkerPath = Join-Path $PSScriptRoot '../../Module/GUIExecution/Start-GuiExecutionWorker/Start-GuiExecutionWorker.ps1'
    $appExecutionWorkerPath = Join-Path $PSScriptRoot '../../Module/GUIExecution/Start-GuiAppExecutionWorker/Start-GuiAppExecutionWorker.ps1'
    $progressChromePath = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/ProgressNavChrome.ps1'
    $guiExecutionPath = Join-Path $PSScriptRoot '../../Module/GUIExecution.psm1'
    $sessionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $styledControlsPath = Join-Path $PSScriptRoot '../../Module/GUI/StyledControlsSetup.ps1'
    $script:ExecutionStateSummaryPath = $executionStateSummaryPath
    $script:ExecutionContent = Get-BaselineTestSourceText -Path @(
        $executionPath
        $executionStateSummaryPath
        $executionViewPath
        $executionRunPath
    )
    $script:ExecutionViewContent = Get-BaselineTestSourceText -Path $executionViewPath
    $script:ExecutionRunContent = Get-BaselineTestSourceText -Path $executionRunPath
    $script:AppExecutionRunContent = Get-BaselineTestSourceText -Path $appExecutionRunPath
    $script:ExecutionWorkerContent = Get-BaselineTestSourceText -Path $executionWorkerPath
    $script:AppExecutionWorkerContent = Get-BaselineTestSourceText -Path $appExecutionWorkerPath
    $script:ExecutionRunPath = $executionRunPath
    $script:ProgressChromeContent = Get-BaselineTestSourceText -Path $progressChromePath
    $script:GuiExecutionContent = Get-BaselineTestSourceText -Path $guiExecutionPath
    $script:SessionStateContent = Get-BaselineTestSourceText -Path $sessionStatePath
    $script:StyledControlsContent = Get-BaselineTestSourceText -Path $styledControlsPath
}

Describe 'Execution orchestration timer wiring' {
    It 'captures the execution pump tick scriptblock before registering DispatcherTimer callbacks' {
        ([regex]::Matches($script:ExecutionContent, '\$executionPumpTickFn = \$Script:ExecutionPumpTickFn')).Count | Should -Be 2
        ([regex]::Matches($script:ExecutionContent, 'Add_Tick\(\{\s*& \$executionPumpTickFn\s*\}\.GetNewClosure\(\)\)')).Count | Should -Be 2
    }

    It 'guards execution-view controls before toggling their enabled state' {
        $script:ExecutionContent | Should -Match 'Test-GuiObjectField -Object \$PrimaryTabs -FieldName ''IsEnabled'''
        $script:ExecutionContent | Should -Match 'Test-GuiObjectField -Object \$BtnRun -FieldName ''Content'''
        $script:ExecutionContent | Should -Match 'Test-GuiObjectField -Object \$Script:BtnUndoLastRun -FieldName ''IsEnabled'''
    }

    It 'tracks not-applicable and not-run items separately from skipped session counts' {
        $script:ExecutionRunContent | Should -Match "Add-SessionStatistic -Name 'SkippedCount' -Increment \`$guiSummaryPayload\.SkippedCount"
        $script:ExecutionRunContent | Should -Match "Add-SessionStatistic -Name 'NotApplicableCount' -Increment \`$guiSummaryPayload\.NotApplicableCount"
        $script:ExecutionRunContent | Should -Match "Add-SessionStatistic -Name 'NotRunCount' -Increment \`$guiSummaryPayload\.NotRunCount"
        $script:ExecutionRunContent | Should -Not -Match "SkippedCount' -Increment \(\`$guiSummaryPayload\.SkippedCount \+ \`$guiSummaryPayload\.NotApplicableCount \+ \`$guiSummaryPayload\.NotRunCount\)"
    }

    It 'uses a native WPF progress bar in the execution header' {
        $script:ExecutionViewContent | Should -Match 'New-Object System\.Windows\.Controls\.ProgressBar'
        $script:ExecutionViewContent | Should -Match 'ExecutionView\.ProgressBar\.Foreground'
        $script:ExecutionViewContent | Should -Match 'New-ExecutionProgressBarTemplate'
        $script:ExecutionViewContent | Should -Match 'return New-GuiExecutionProgressBarTemplate'
        $script:ProgressChromeContent | Should -Match 'function New-GuiExecutionProgressBarTemplate'
        $script:ProgressChromeContent | Should -Match '<Border x:Name="PART_Indicator"'
        $script:ProgressChromeContent | Should -Match '<Border x:Name="PART_BusyIndicator"'
        $script:ProgressChromeContent | Should -Match 'Storyboard\.TargetProperty="Opacity"'
        $script:ProgressChromeContent | Should -Match 'Storyboard\.TargetName="BusyIndicatorTransform"'
        $script:ProgressChromeContent | Should -Match 'Storyboard\.TargetProperty="X"'
        $script:ProgressChromeContent | Should -Match '<Trigger Property="IsIndeterminate" Value="True">'
        $script:ProgressChromeContent | Should -Not -Match 'ExecutionSheenRect'
        $script:ProgressChromeContent | Should -Match 'RepeatBehavior="Forever"'
        $script:ProgressChromeContent | Should -Match 'AutoReverse="True"'
        $script:ExecutionViewContent | Should -Match 'ProgressBar = \$progressBar'
        $script:ExecutionViewContent | Should -Not -Match 'New-SharedProgressBarHost -Maximum 1 -Value 0'
    }

    It 'aligns the execution Abort button with the progress bar row' {
        $script:ExecutionViewContent | Should -Match '\$abortBtnHost\.Margin = \[System\.Windows\.Thickness\]::new\(0, -6, 0, 0\)'
        $script:ExecutionViewContent | Should -Match '\$abortBtn\.Height = \(\[double\]\$Script:GuiLayout\.ProgressBarHeight \+ 12\)'
        $script:ExecutionViewContent | Should -Match '\$abortBtn\.Padding = \[System\.Windows\.Thickness\]::new\(16,4,16,4\)'
    }

    It 'keeps run progress driven by queued start and completion events' {
        $script:ExecutionRunContent | Should -Match "GuiProgressPreparingRun' -Fallback 'Busy - preparing run\.\.\.'"
        $script:ExecutionRunContent | Should -Match '& \$Script:UpdateProgressFn -Completed 0 -Total 0 -CurrentAction \$preparingRunLabel'
        $script:ExecutionRunContent | Should -Match "GuiProgressStarting' -Fallback 'Starting\.\.\.'"
        $script:ExecutionRunContent | Should -Match '\$Script:RunInProgress = \$true'
        $script:ExecutionRunContent | Should -Match '\$Script:Ctx\.Run\.InProgress = \$true'
        $script:ExecutionRunContent | Should -Match '\$completedStepIndex = if \(\(Test-GuiObjectField -Object \$entry -FieldName ''StepIndex''\)\)'
        $script:ExecutionRunContent | Should -Match '\$completedProgress = if \(\$null -ne \$completedStepIndex\)'
        $script:ExecutionRunContent | Should -Match '\$Script:ExecutionCurrentStepIndex -gt \[int\]\$Script:RunState\[''CompletedCount''\]'
        $script:ExecutionRunContent | Should -Not -Match '\$currentAction = if \(-not \[string\]::IsNullOrWhiteSpace\(\$Script:RunState\[''CurrentTweak''\]\)\)'
    }

    It 'keeps run startup diagnostics debug-only instead of appending them to the visible console' {
        $script:ExecutionRunContent | Should -Match "'_RunNotice'"
        $script:ExecutionRunContent | Should -Match '\$noticeDiagnostic'
        $script:ExecutionRunContent | Should -Match '\$noticeProgressOnly'
        $script:ExecutionRunContent | Should -Match 'LogDebug -Message \$noticeMessage -Always'
        $script:ExecutionRunContent | Should -Match 'if \(\$noticeDiagnostic\)'
        $script:ExecutionRunContent | Should -Match 'if \(-not \$noticeProgressOnly\)'
        $script:GuiExecutionContent | Should -Match 'Diagnostic = \$true'
        $script:GuiExecutionContent | Should -Match 'ProgressOnly = \$true'
        $script:ExecutionWorkerContent | Should -Match 'Diagnostic = \$true'
        $script:ExecutionRunContent | Should -Match 'Execution startup: dispatching background worker'
        $script:ExecutionRunContent | Should -Match 'Execution startup: background worker started'
        $script:ExecutionRunContent | Should -Match 'Execution startup: starting dispatcher pump\.'
        $script:ExecutionRunContent | Should -Match 'Execution startup: dispatcher pump started; invoking first tick\.'
        $script:ExecutionRunContent | Should -Match 'LogDebug -Message \("Execution startup: dispatching background worker.* -Always'
        $script:ExecutionRunContent | Should -Not -Match 'LogInfo \("Execution startup: dispatching background worker'
        $script:ExecutionRunContent | Should -Match "Start-GuiPerfScope -Name 'Execution\.WorkerStart'"
        $script:ExecutionRunContent | Should -Match "Start-GuiPerfScope -Name 'Execution\.TimerStart'"
        $script:GuiExecutionContent | Should -Match 'Execution startup: creating background runspace\.'
        $script:GuiExecutionContent | Should -Match 'Execution startup: worker BeginInvoke returned\.'
        $script:ExecutionWorkerContent | Should -Match 'function Write-GuiTweakExecutionWorkerStartupNotice'
        $script:ExecutionWorkerContent | Should -Match 'Execution worker entered background runspace\.'
        $script:ExecutionWorkerContent | Should -Match 'Execution worker importing Baseline modules\.'
        $script:ExecutionWorkerContent | Should -Match 'Execution worker capturing pre-run system snapshot\.'
        $script:GuiExecutionContent | Should -Match 'Execution worker snapshot checking \{0\}/\{1\}: \{2\}\.'
        $script:ExecutionWorkerContent | Should -Match 'Execution worker starting selected tweaks: \{0\} item\(s\)\.'
    }

    It 'keeps app execution logging aligned with tweak execution diagnostics' {
        $script:AppExecutionRunContent | Should -Match 'Starting app execution \(action: \{0\}, selected: \{1\}, source: \{2\}\)'
        $script:AppExecutionRunContent | Should -Match 'Execution startup: dispatching background worker\. mode=Apps; action=\{0\}; selected=\{1\}; loader=\{2\}; log=\{3\}'
        $script:AppExecutionRunContent | Should -Match 'Execution startup: background worker started\. asyncCompleted=\{0\}; runspaceState=\{1\}'
        $script:AppExecutionRunContent | Should -Match 'Execution startup: starting dispatcher pump\.'
        $script:AppExecutionRunContent | Should -Match 'Execution startup: dispatcher pump started; invoking first tick\.'
        $script:AppExecutionRunContent | Should -Match "Start-GuiPerfScope -Name 'Execution\.WorkerStart'"
        $script:AppExecutionRunContent | Should -Match "Start-GuiPerfScope -Name 'Execution\.TimerStart'"
        $script:AppExecutionRunContent | Should -Match 'Write-GuiAppExecutionSummaryToLog -Action'
        $script:AppExecutionRunContent | Should -Match 'Run summary \| Success \| \[Apps\]'
        $script:AppExecutionRunContent | Should -Match 'Run summary \| Failed \| \[Apps\]'
        $script:AppExecutionRunContent | Should -Match 'function Script:Show-GuiAppExecutionSummaryDialog'
        $script:AppExecutionRunContent | Should -Match 'function Script:ConvertTo-GuiAppExecutionSummaryResults'
        $script:AppExecutionRunContent | Should -Match 'Get-GuiAppExecutionSummaryCards -Action \$Action -Counts \$counts'
        $script:AppExecutionRunContent | Should -Match 'Show-ExecutionSummaryDialog -Title \$summaryTitle -SummaryText \$summaryText -Results \$summaryResults -LogPath \$displayLogPath -SummaryCards \$summaryCards -Buttons \$summaryButtons'
        $script:AppExecutionRunContent | Should -Match 'Show-GuiAppExecutionSummaryDialog -Action \$runAction -Result \$runAppResult -AbortedRun:\$appAbortedRun -LogPath \$Global:LogFilePath'
        $script:AppExecutionRunContent | Should -Match 'if \(\$appSummaryChoice -eq ''Open Detailed Log'''
        $script:AppExecutionRunContent | Should -Match 'Close-GuiMainWindow -Reason ''App execution summary exit requested\.'''
        $script:AppExecutionRunContent | Should -Match 'function Script:Get-GuiAppExecutionProgressVerb'
        $script:AppExecutionRunContent | Should -Match 'function Script:Write-GuiAppExecutionProgressLog'
        $script:AppExecutionRunContent | Should -Match 'function Script:Set-GuiAppProgressOutcome'
        $script:AppExecutionRunContent | Should -Match 'function Script:Get-GuiAppExecutionLiveLogKey'
        $script:AppExecutionRunContent | Should -Match 'function Script:Write-GuiAppExecutionSummaryToLog'
        $script:AppExecutionRunContent | Should -Match '''\{0\} \{1\} - \{2\}'' -f \$progressVerb, \$appName, \$statusLabel'
        $script:AppExecutionRunContent | Should -Match 'Write-GuiAppExecutionProgressLog -Action \(\[string\]\$qEntry\.Action\) -Name \$appName -Started'
        $script:AppExecutionRunContent | Should -Not -Match 'Write-GuiAppExecutionProgressLog -Action \(\[string\]\$qEntry\.Action\) -Name \$appName -Status ''Running'''
        $script:AppExecutionRunContent | Should -Match 'Write-GuiAppExecutionProgressLog -Action \(\[string\]\$qEntry\.Action\) -Name \$displayName -Status \$appStatus'
        $script:AppExecutionRunContent | Should -Match 'function Script:Get-GuiAppExecutionLiveLogMessage'
        $script:ExecutionRunContent | Should -Match 'function Set-GuiExecutionRunLogLine'
        $script:AppExecutionRunContent | Should -Match '\$Script:AppExecutionLiveLogBlocks = @\{\}'
        $script:AppExecutionRunContent | Should -Match '\$Script:AppendLogFn = \{ param\(\$Text, \$Level = ''INFO'', \[switch\]\$PassThru\) Add-GuiExecutionRunLogLine -Text \$Text -Level \$Level -PassThru:\$PassThru \}'
        $script:AppExecutionRunContent | Should -Match '\$Script:AppExecutionLiveLogBlocks\[\$appLiveLogKey\] = & \$Script:AppendLogFn \$appLiveLogMessage ''INFO'' -PassThru'
        $script:AppExecutionRunContent | Should -Match 'Set-GuiExecutionRunLogLine -Block \$Script:AppExecutionLiveLogBlocks\[\$appLiveLogKey\] -Text \$appLiveLogMessage -Level \$appLevel'
        $script:AppExecutionRunContent | Should -Match '& \$Script:AppendLogFn \$appLiveLogMessage \$appLevel'
        $script:AppExecutionRunContent | Should -Not -Match 'Add-ExecutionLogLine -Text \$appProgressMessage'
        $script:AppExecutionRunContent | Should -Match 'Raw logger entries belong in the file log'
        $script:AppExecutionRunContent | Should -Match '\$appActiveProgressText = \$appProgressMessage'
        $script:AppExecutionRunContent | Should -Match 'Set-SharedProgressBarState -ProgressBar \$Script:ExecutionProgressBar -ProgressText \$Script:ExecutionProgressText -Completed \(\[int\]\$Script:RunState\[''AppCurrentProgressCount''\]\) -Total \$stepTotal -CurrentAction \$appActiveProgressText'
        $script:AppExecutionRunContent | Should -Match 'Set-SharedProgressBarState -ProgressBar \$Script:ExecutionProgressBar -ProgressText \$Script:ExecutionProgressText -Completed \(\[int\]\$Script:RunState\[''AppCompletedCount''\]\) -Total \(\[int\]\$Script:RunState\[''AppProgressTotal''\]\) -CurrentAction \$finalLabel'
        $script:ExecutionRunContent | Should -Match 'AppProgressIndeterminate = \$false'
        $script:AppExecutionWorkerContent | Should -Match '\$Script:RunState\[''AppProgressIndeterminate''\] = \$false'
        $script:AppExecutionRunContent | Should -Match '\$noticeDiagnostic'
        $script:AppExecutionRunContent | Should -Match 'LogDebug -Message \$noticeMessage -Always'
        $script:AppExecutionWorkerContent | Should -Match 'function Write-GuiAppExecutionWorkerStartupNotice'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker entered background runspace\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker loading JSON and localization helpers\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker importing GUI execution helpers\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker importing application modules\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker connected logging pipeline\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker creating action host\.'
        $script:AppExecutionWorkerContent | Should -Match 'Execution worker starting selected apps: \{0\} item\(s\)\.'
    }

    It 'supplies localization arguments for timer error prefixes' {
        $script:ExecutionRunContent | Should -Match 'GuiLogExecutionQueueEntryFailed'' -Fallback ''\[Timer\] Queue entry failed \[\{0\}\]: \{1\}'' -FormatArgs @\(\$entryLabel, \$entryError\)'
        $script:ExecutionRunContent | Should -Match '\$executionUpdateError = if \(\$_\.Exception\) \{ \[string\]\$_\.Exception\.Message \} else \{ \[string\]\$_ \}'
        $script:ExecutionRunContent | Should -Match 'GuiLogExecutionUpdateFailedDetail'' -Fallback ''Execution UI update failed: \{0\}'' -FormatArgs @\(\$executionUpdateError\)'
        $script:AppExecutionRunContent | Should -Match 'GuiLogExecutionAppTimerQueueEntryFailed'' -Fallback ''\[AppTimer\] Queue entry failed \[\{0\}\]: \{1\}'' -FormatArgs @\(\$appQueueEntryKind, \$appQueueEntryError\)'
        $script:AppExecutionRunContent | Should -Match '\$appExecutionUpdateError = if \(\$_\.Exception\) \{ \[string\]\$_\.Exception\.Message \} else \{ \[string\]\$_ \}'
        $script:AppExecutionRunContent | Should -Match 'GuiLogExecutionAppTimerUpdateFailed'' -Fallback ''\[AppTimer\] Execution UI update failed: \{0\}'' -FormatArgs @\(\$appExecutionUpdateError\)'
    }

    It 'gates execution pumps through the canonical run-state accessor' {
        $script:ExecutionContent | Should -Match 'if \(-not \(& \$Script:TestGuiRunInProgressScript\) -or -not \$Script:RunState\) \{ return \}'
        $script:ExecutionContent | Should -Not -Match 'if \(-not \$Script:RunInProgress -or -not \$Script:RunState\) \{ return \}'
    }

    It 'drains execution queue events in bounded dispatcher slices' {
        $script:ExecutionRunContent | Should -Match 'function Invoke-GuiExecutionRunQueueDrain'
        $script:ExecutionRunContent | Should -Match '\[int\]\$MaxEntries = 64'
        $script:ExecutionRunContent | Should -Match '\[int\]\$MaxMilliseconds = 40'
        $script:ExecutionRunContent | Should -Match '\[System\.Diagnostics\.Stopwatch\]::StartNew\(\)'
        $script:ExecutionRunContent | Should -Match '\$processedEntries -ge \$MaxEntries'
        $script:ExecutionRunContent | Should -Match '\$drainStopwatch\.ElapsedMilliseconds -ge \$MaxMilliseconds'
        $script:ExecutionRunContent | Should -Match 'return \(-not \$Script:RunState\[''LogQueue''\]\.IsEmpty\)'
        $script:ExecutionRunContent | Should -Match '\$queueHasMore = \[bool\]\(& \$Script:DrainExecutionQueueSafely\)'
        $script:ExecutionRunContent | Should -Match 'if \(\$queueHasMore\) \{ return \}'
    }

    It 'captures the pre-run snapshot in the background worker before tweaks execute' {
        $uiSnapshotCall = $script:ExecutionRunContent.IndexOf('Save-GuiExecutionPreRunSnapshot')
        $workerSnapshotIndex = $script:ExecutionWorkerContent.IndexOf('Invoke-GuiPreRunSnapshotCapture')
        $firstTweakLoopIndex = $script:ExecutionWorkerContent.IndexOf('foreach ($tweak in $tweakList)')

        $uiSnapshotCall | Should -Be -1
        $script:ExecutionRunContent | Should -Match 'Sync-GuiExecutionPreRunSnapshotFromRunState'
        $workerSnapshotIndex | Should -BeGreaterThan 0
        $firstTweakLoopIndex | Should -BeGreaterThan $workerSnapshotIndex
        $script:ExecutionWorkerContent | Should -Match '\$Script:RunState\[''PreRunSnapshot''\] = \$preRunSnapshot'
        $script:ExecutionWorkerContent | Should -Match 'Get-GuiPreRunSnapshotTimeoutSeconds'
        $script:ExecutionWorkerContent | Should -Match '\$Script:RunState\[''PreRunSnapshotTimedOut''\] = \$true'
        $script:ExecutionWorkerContent | Should -Match 'continuing with selected tweaks'
        $script:GuiExecutionContent | Should -Match 'New-SystemStateSnapshot -Manifest \$snapshotManifest -ProgressCallback \$progressCallback'
        $script:ExecutionWorkerContent | Should -Match 'GUIExecution\.PreRunSnapshot\.ManifestAvailabilityStamp'
    }

    It 'uses shared localization helpers inside the background execution worker' {
        $script:ExecutionWorkerContent | Should -Not -Match 'Get-UxBilingualLocalizedString'
        $script:ExecutionWorkerContent | Should -Match 'Get-BaselineBilingualString'
    }

    It 'does not stop Explorer during GUI run startup' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ExecutionRunPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0

        $startupFunction = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Initialize-GuiExecutionRunState'
        }, $true)

        $startupFunction | Should -Not -BeNullOrEmpty
        $startupFunction.Extent.Text | Should -Not -Match 'Stop-Foreground'
    }

    It 'does not stop Explorer after post actions in the background worker' {
        $script:ExecutionWorkerContent | Should -Not -Match 'Stop-Foreground'
    }

    It 'passes OnParam for manifest-backed action entries' {
        $script:ExecutionWorkerContent | Should -Match '\$actionParam = \[string\]\$tweak\.OnParam'
        $script:ExecutionWorkerContent | Should -Match '\$commandArguments\[\$actionParam\] = \$true'
        $script:ExecutionWorkerContent | Should -Match '\$tweak\.ExtraArgs\.GetEnumerator\(\) \| ForEach-Object \{ \$commandArguments\[\[string\]\$_.Key\] = \$_.Value \}'
    }

    It 'builds command arguments for NumericRange entries before invoking the action host' {
        $script:ExecutionWorkerContent | Should -Match "'NumericRange'"
        $script:ExecutionWorkerContent | Should -Match 'New-GuiExecutionNumericRangeCommandArguments -Tweak \$tweak'
        $script:ExecutionWorkerContent | Should -Match 'ACValue = \[int\]\$acValue'
        $script:ExecutionWorkerContent | Should -Match 'DCValue = \[int\]\$dcValue'
        $script:ExecutionWorkerContent | Should -Match 'Value = \[int\]\$scalarValue'
    }

    It 'does not recursively disable the tab tree before replacing it with the execution view' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ExecutionRunPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0

        $startupFunction = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Initialize-GuiExecutionRunState'
        }, $true)

        $startupFunction | Should -Not -BeNullOrEmpty
        $startupFunction.Extent.Text | Should -Not -Match '\$PrimaryTabs\.IsEnabled = \$false'
        $script:ExecutionViewContent | Should -Match '\$PrimaryTabs\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
    }

    It 'hides the footer run buttons while the execution view is active' {
        $script:ExecutionViewContent | Should -Match '\$Script:ExecutionPreviousFooterVisibility = @\{'
        $script:ExecutionViewContent | Should -Match '\$BtnRun\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        $script:ExecutionViewContent | Should -Match '\$BtnDefaults\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        $script:ExecutionViewContent | Should -Match '\$BtnRun\.Visibility = if \(\$previousFooterVisibility -and \$previousFooterVisibility\.BtnRun\)'
        $script:ExecutionViewContent | Should -Match '\$BtnDefaults\.Visibility = if \(\$previousFooterVisibility -and \$previousFooterVisibility\.BtnDefaults\)'
    }

    It 'prevents delayed progress updates from moving the header backwards' {
        $script:ExecutionContent | Should -Match '\$Script:ExecutionLastProgressCompleted = -1'
        $script:StyledControlsContent | Should -Match '\$Completed -lt \[int\]\$Script:ExecutionLastProgressCompleted'
        $script:StyledControlsContent | Should -Match 'return'
        $script:StyledControlsContent | Should -Match '\$Script:ExecutionLastProgressCompleted = \$Completed'
    }

    It 'refreshes the installed-app cache after app actions finish' {
        $script:ExecutionContent | Should -Match '\$(?:Action|runAction|runCatchAction) -in @\(''Install'', ''Uninstall'', ''Update'', ''UpdateAll''\)'
        $script:ExecutionContent | Should -Match 'Start-AppsCacheRefresh'
    }

    It 'wires the execution idle watchdog into both app and tweak run loops' {
        $script:ExecutionContent | Should -Match 'function Update-ExecutionActivityHeartbeat'
        $script:ExecutionContent | Should -Match 'function Test-ExecutionIdleWatchdogExpired'
        $script:ExecutionContent | Should -Match 'function Invoke-ExecutionIdleWatchdogPrompt'
        $script:ExecutionContent | Should -Match 'Baseline has not reported progress for 10 minutes\.'
        $script:ExecutionContent | Should -Match "Buttons @\('Continue Waiting', 'Abort Run'\)"
        $script:ExecutionContent | Should -Match 'Invoke-ExecutionIdleWatchdogPrompt -RunState \$Script:RunState'
        $script:ExecutionContent | Should -Match 'IdleWatchdogSeconds = 600'
        $script:ExecutionContent | Should -Match 'IdleWatchdogPromptOpen = \$false'
        $script:ExecutionContent | Should -Match 'LastActivityAt   = \(Get-Date\)'
    }

    It 'uses structured per-app queue events and keeps the app execution abort button visible' {
        $script:ExecutionContent | Should -Match 'Enter-ExecutionView -Title \$executionTitle -ShowAbortButton:\$true'
        $script:ExecutionContent | Should -Match "'_AppStarted'"
        $script:ExecutionContent | Should -Match "'_AppCompleted'"
        $script:ExecutionContent | Should -Match 'AppUseStructuredProgress = \$false'
        $script:ExecutionContent | Should -Match 'Abort requested - stopping the current app operation now\.'
    }

    It 'stops app and tweak workers immediately when abort is confirmed' {
        $script:AppExecutionRunContent | Should -Match 'Abort requested - stopping the current app operation now\.'
        $script:ExecutionRunContent | Should -Match 'Abort requested - stopping the current operation now\.'
        $script:AppExecutionRunContent | Should -Not -Match 'TotalSeconds -ge 2'
        $script:ExecutionRunContent | Should -Not -Match 'TotalSeconds -ge 2'
        $script:StyledControlsContent | Should -Match '\$Script:RunState\[''Paused''\] = \$true'
        $script:StyledControlsContent | Should -Match '& \$Script:ExecutionPumpTickFn'
        $script:StyledControlsContent | Should -Match 'StyledControls\.RequestRunAbort\.PumpTick'
    }

    It 'routes connected remote runs through the remote apply helper' {
        $script:ExecutionContent | Should -Match 'Get-GuiRemoteTargetContext'
        $script:ExecutionContent | Should -Match 'function Confirm-RemoteMultiTargetApply'
        $script:ExecutionContent | Should -Match 'function Confirm-RemoteTargetApproval'
        $script:ExecutionContent | Should -Match 'function Get-ExecutionResumeCandidateList'
        $script:SessionStateContent | Should -Match 'function Save-GuiInterruptedRunProfile'
        $script:SessionStateContent | Should -Match 'function Clear-GuiInterruptedRunProfile'
        $script:ExecutionContent | Should -Match 'Save-GuiInterruptedRunProfile -ResumeCandidates'
        $script:ExecutionContent | Should -Match 'Clear-GuiInterruptedRunProfile'
        $script:ExecutionContent | Should -Match 'Resume Interrupted Run'
        $script:ExecutionContent | Should -Match 'Show-ThemedDialog -Title ''Confirm Remote Apply'''
        $script:ExecutionContent | Should -Match 'Apply to Targets'
        $script:ExecutionContent | Should -Match 'Approve this exact target list for the current GUI session before applying changes'
        $script:ExecutionContent | Should -Match 'Remote run cancelled before apply'
        $script:ExecutionContent | Should -Match 'Remote run cancelled before target approval'
        $script:ExecutionContent | Should -Match 'Invoke-BaselineRemoteApply'
        $script:ExecutionContent | Should -Match 'New-ConfigurationProfile'
        $script:ExecutionContent | Should -Match 'Complete-GuiExecutionRun -Mode ''Run'' -CompletedCount \$executionSummary.Count -ExecutionSummary \$executionSummary -LogPath \$Global:LogFilePath -RemoteExecution -RemoteTargetLabel \$targetLabel'
        $script:ExecutionContent | Should -Match "ExecutionOrchestration\.RemoteRunCleanup\.RemoveTempProfilePath"
        $script:ExecutionContent | Should -Match "ExecutionOrchestration\.RemoteRunCleanup\.RemoveTempProfileDir"
    }

    It 'routes run-loop log failures through Write-SwallowedException' {
        $script:ExecutionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ExecutionOrchestration\.RunLoop\.FatalAppError\.LogError'''
        $script:ExecutionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ExecutionOrchestration\.RunLoop\.FatalAppDiagnostic\.LogError'''
        $script:ExecutionContent | Should -Match 'Interactive selection request failed: \{0\}'
        $script:ExecutionContent | Should -Match 'ExecutionOrchestration\.InteractiveSelectionRequest\.LogError'
    }

    It 'blocks apply/defaults runs when the host-taint assessment is blocked' {
        $script:ExecutionRunContent | Should -Match '\$Global:BaselineHostTaint'
        $script:ExecutionRunContent | Should -Match '\[string\]\$Global:BaselineHostTaint\.Level -eq ''Blocked'''
        $script:ExecutionRunContent | Should -Match 'GuiHostTaintRunBlocked'
        $script:ExecutionRunContent | Should -Match 'LogError \$hostTaintMessage'
        $script:ExecutionRunContent | Should -Match 'Set-GuiStatusText -Text \$hostTaintMessage -Tone ''caution'''
        $script:ExecutionRunContent | Should -Match "Show-ThemedDialog -Title .*GuiHostTaintRunBlockedTitle"
    }
}

Describe 'GUI apply pipeline busy-state cleanup' {
    # Background: apply paths with multiple early-return branches must clear
    # the run-in-progress state, or the GUI can remain permanently spinning on
    # "Applying tweaks". Baseline's state is the `RunInProgress` flag on
    # `$Script:GuiState` plus the disabled
    # `PrimaryTabs` / scoped run-action availability / `BtnDefaults` /
    # `Set-GuiActionButtonsEnabled` / `ChkScan` / `ChkTheme` / search controls.
    # These tests pin that EVERY exit path out of the apply pipeline restores
    # all of them, so a thrown pump-tick body or a failed timer construction
    # never traps the GUI in busy state.

    It 'pump-tick outer catch clears RunInProgress and re-enables every disabled control' {
        # Locate the outer catch on the tweaks pump-tick (the one that follows
        # the second `finally { Clear-LogMode }` block, which is unique to the
        # tweaks-execution pump-tick body — the apps pump-tick does not have it).
        $clearLogModeIndex = $script:ExecutionContent.IndexOf('Clear-LogMode')
        $clearLogModeIndex | Should -BeGreaterThan 0
        $outerCatchSlice = $script:ExecutionContent.Substring($clearLogModeIndex)
        # The next `catch` after Clear-LogMode is the outer pump-tick catch.
        $outerCatchSlice | Should -Match 'GuiLogExecutionOuterCatch'
        # Cleanup contract — every line below must be present in the catch slice
        # before the next `function` keyword (i.e. before we leave Start-GuiExecutionRun).
        $functionBoundary = $outerCatchSlice.IndexOf("`tfunction Get-ActiveTweakRunList")
        if ($functionBoundary -lt 0) { $functionBoundary = $outerCatchSlice.Length }
        $catchBody = $outerCatchSlice.Substring(0, $functionBoundary)
        $catchBody | Should -Match 'Restore-GuiExecutionRunControls -SourcePrefix ''ExecutionRunOrchestration\.ExecutionTimerCatch'''
        $script:ExecutionRunContent | Should -Match "& \`$Script:GuiState\.Set 'RunInProgress' \`$false"
        $script:ExecutionRunContent | Should -Match "\`$PrimaryTabs\.IsEnabled = \`$true"
        $script:ExecutionRunContent | Should -Match 'Update-GuiScopedRunActionAvailability'
        $script:ExecutionRunContent | Should -Match "\`$BtnDefaults\.IsEnabled = \`$true"
        $script:ExecutionRunContent | Should -Match 'Set-GuiActionButtonsEnabled -Enabled \$true'
        $script:ExecutionRunContent | Should -Match "\`$ChkScan\.IsEnabled = \`$true"
        $script:ExecutionRunContent | Should -Match "\`$ChkTheme\.IsEnabled = \`$true"
        $script:ExecutionRunContent | Should -Match 'Set-SearchControlsEnabled -Enabled \$true'
    }

    It 'synchronous timer-start is wrapped so a throw before first tick still clears RunInProgress' {
        # The Tweaks apply pipeline's `& $executionPumpTickFn` is the synchronous
        # first invocation. It MUST be inside a try/catch that matches the cleanup
        # contract — otherwise a throw in `New-Object DispatcherTimer` or the
        # first pump-tick invocation traps the GUI in busy state with no recovery.
        $script:ExecutionContent | Should -Match 'GuiLogExecutionTimerStartFailed'
        # The localization key only exists on the Tweaks-side timer wrapper, so
        # this assertion both confirms presence and uniqueness.
        ([regex]::Matches($script:ExecutionContent, 'GuiLogExecutionTimerStartFailed')).Count | Should -Be 1
    }

    It 'forbids leading Start-Sleep on any wait loop' {
        # A busy-wait loop that sleeps before checking work state makes a
        # no-op run look hung. Apply pipeline must not introduce any
        # Start-Sleep; DispatcherTimer is the cooperative pump.
        $script:ExecutionContent | Should -Not -Match 'Start-Sleep'
    }

    It 'forbids modal MessageBox dialogs on the apply path' {
        # Empty-selection handling must not show modal MessageBox dialogs that
        # can hang unattended runs. Apply path must use Show-ThemedDialog
        # (which the headless host can stub) or LogWarning.
        $script:ExecutionContent | Should -Not -Match '\[System\.Windows\.MessageBox\]::Show'
        $script:ExecutionContent | Should -Not -Match '\[System\.Windows\.Forms\.MessageBox\]::Show'
    }
}

Describe 'GUI run completion exit code' {
    It 'pins $Global:LASTEXITCODE through Get-BaselineHeadlessExitCode at run completion' {
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Get-BaselineHeadlessExitCode'"
        $script:ExecutionContent | Should -Match '\$Global:LASTEXITCODE\s*=\s*\[int\]\$guiExit\.ExitCode'
        $script:ExecutionContent | Should -Match 'GUI run finished: exitCode='
    }

    It 'classifies aborted runs with no failures and unstarted remainder as partial' {
        # When the user aborts mid-run, the completed-count gap must NOT be
        # silently rolled into 0 / clean.
        $script:ExecutionContent | Should -Match 'if \(\$abortedRun -and \$guiFailed -eq 0 -and \$guiSucceeded -lt \$guiTotal\)'
        $script:ExecutionContent | Should -Match '\$guiFailed = \$guiTotal - \$guiSucceeded'
    }

    It 'computes the exit code AFTER the audit record is written' {
        $auditIndex = $script:ExecutionContent.IndexOf('Write-AuditRecord @auditParams')
        $exitCodePinIndex = $script:ExecutionContent.IndexOf('$Global:LASTEXITCODE = [int]$guiExit.ExitCode')
        $completeIndex = $script:ExecutionContent.IndexOf('Complete-GuiExecutionRun -Mode $Script:ExecutionMode')

        $auditIndex | Should -BeGreaterThan 0
        $exitCodePinIndex | Should -BeGreaterThan $auditIndex
        $completeIndex | Should -BeGreaterThan $exitCodePinIndex
    }

    It 'guards the helper lookup so a missing Get-BaselineHeadlessExitCode never breaks the GUI completion path' {
        # ErrorAction SilentlyContinue + outer try/catch routed through
        # Write-SwallowedException — completion must keep going even if
        # the helper module is unloaded mid-session.
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Get-BaselineHeadlessExitCode' -CommandType Function -ErrorAction SilentlyContinue"
        $script:ExecutionContent | Should -Match "Source 'ExecutionOrchestration\.RunCompletion\.ExitCode'"
    }

    It 'routes the Apps & features health check through the run-completion path' {
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Resolve-BaselineSettingsAppsFeaturesHealthAssessment' -CommandType Function -ErrorAction SilentlyContinue"
        $script:ExecutionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ExecutionOrchestration\.RunCompletion\.SettingsAppsFeaturesHealthAssessment'''
        $script:ExecutionContent | Should -Match 'Selected tweaks have finished running, but the Settings appsfeatures health check needs attention\.'
    }

    It 'routes the ScreenSketch regression probe through the run-completion path' {
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Resolve-BaselineScreenSnippingHealthAssessment' -CommandType Function -ErrorAction SilentlyContinue"
        $script:ExecutionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ExecutionOrchestration\.RunCompletion\.ScreenSnippingHealthAssessment'''
        $script:ExecutionContent | Should -Match 'Set-ExecutionSummaryStatus -Key ''PrtScnSnippingTool'' -Status ''Failed'' -Detail \(\[string\]\$screenSnippingHealthAssessment\.Message\)'
    }

    It 'emits run-completion toasts through the shared Baseline toast helper' {
        $script:ExecutionContent | Should -Match "function Invoke-GuiExecutionCompletionToast"
        $script:ExecutionContent | Should -Match 'if \(\$Mode -ne ''Run''\)'
        $script:ExecutionContent | Should -Match 'Get-Command -Name ''Test-BaselineToastRuntimeAvailable'' -CommandType Function -ErrorAction SilentlyContinue'
        $script:ExecutionContent | Should -Match 'Show-BaselineToast -Title \$Title -Body \$Body -AppId ''Baseline'' -Duration ''Short'''
        $script:ExecutionContent | Should -Match 'Invoke-GuiExecutionCompletionToast -Mode \$Mode -Title \$dlgTitle -Body \$summaryCountsText'
        $script:ExecutionContent | Should -Match "ExecutionOrchestration\.RunCompletion\.Toast"
    }

    It 'returns to the restored GUI when the local run summary closes' {
        $script:ExecutionRunContent | Should -Match 'if \(\$nextStep -eq ''Close''\)\s*\{\s*Exit-ExecutionView\s*\}\s*else\s*\{\s*Close-GuiMainWindow -Reason ''Execution summary exit requested\.'''
        $script:ExecutionRunContent | Should -Not -Match 'if \(\$nextStep -eq ''Close''\)\s*\{[\s\S]*?Invoke-GuiSystemScan'
    }
}

Describe 'GUI execution NumericRange argument helper' {
    BeforeAll {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($executionWorkerPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0

        $helperNames = @(
            'Test-GuiExecutionValuePresent',
            'Add-GuiExecutionExtraArguments',
            'New-GuiExecutionNumericRangeCommandArguments'
        )
        foreach ($helper in $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $helperNames
        }, $true))
        {
            Invoke-Expression $helper.Extent.Text
        }

        function Test-GuiObjectField {
            param([AllowNull()][object]$Object, [Parameter(Mandatory = $true)][string]$FieldName)
            if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName)) { return $false }
            if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
            return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
        }
    }

    AfterAll {
        foreach ($name in @('Test-GuiExecutionValuePresent','Add-GuiExecutionExtraArguments','New-GuiExecutionNumericRangeCommandArguments','Test-GuiObjectField')) {
            Remove-Item Function:\$name -ErrorAction SilentlyContinue
        }
    }

    It 'passes explicit AC/DC channel values' {
        $tweak = [pscustomobject]@{
            Function = 'ProcessorMinimumState'
            Type = 'NumericRange'
            ACValue = '98'
            DCValue = '7'
            ExtraArgs = $null
        }

        $args = New-GuiExecutionNumericRangeCommandArguments -Tweak $tweak

        $args.ACValue | Should -Be 98
        $args.DCValue | Should -Be 7
        $args.ContainsKey('Value') | Should -BeFalse
    }

    It 'passes scalar numeric values' {
        $tweak = [pscustomobject]@{
            Function = 'ProcessorPerformanceIncreaseThreshold'
            Type = 'NumericRange'
            Value = '13'
            ExtraArgs = $null
        }

        $args = New-GuiExecutionNumericRangeCommandArguments -Tweak $tweak

        $args.Value | Should -Be 13
        $args.ContainsKey('ACValue') | Should -BeFalse
        $args.ContainsKey('DCValue') | Should -BeFalse
    }

    It 'reads channel values from the Value object when presets store them there' {
        $tweak = [pscustomobject]@{
            Function = 'USBHubSelectiveSuspendTimeout'
            Type = 'NumericRange'
            Value = [pscustomobject]@{
                ACValue = '2431'
                DCValue = '2825'
            }
            ExtraArgs = @{ Units = 'Milliseconds' }
        }

        $args = New-GuiExecutionNumericRangeCommandArguments -Tweak $tweak

        $args.ACValue | Should -Be 2431
        $args.DCValue | Should -Be 2825
        $args.Units | Should -Be 'Milliseconds'
    }

    It 'rejects incomplete channel selections with a clear error' {
        $tweak = [pscustomobject]@{
            Function = 'ProcessorMinimumState'
            Type = 'NumericRange'
            ACValue = '98'
            ExtraArgs = $null
        }

        { New-GuiExecutionNumericRangeCommandArguments -Tweak $tweak } | Should -Throw -ExpectedMessage '*must include both ACValue and DCValue*'
    }
}

Describe 'Execution selected tweak mode scoping' {
    BeforeAll {
        . $script:ExecutionStateSummaryPath

        function Get-SelectedTweakRunList {
            return @($script:SelectedTweakRunListForScopeTest)
        }

        function Resolve-GuiPrimaryTabForTweak {
            param ([object]$Tweak)

            $functionName = if ($Tweak -is [System.Collections.IDictionary])
            {
                if ($Tweak.Contains('Function')) { [string]$Tweak['Function'] } else { $null }
            }
            elseif ($Tweak.PSObject.Properties['Function']) { [string]$Tweak.Function }
            else { $null }

            if ([string]::Equals([string]$functionName, 'WindowsUpdate', [System.StringComparison]::OrdinalIgnoreCase))
            {
                return 'Updates'
            }

            if ([string]::Equals([string]$functionName, 'GameOptimize', [System.StringComparison]::OrdinalIgnoreCase))
            {
                return 'Gaming'
            }

            if ($Tweak -is [System.Collections.IDictionary])
            {
                if ($Tweak.Contains('Category')) { return [string]$Tweak['Category'] }
                return $null
            }

            if ($Tweak.PSObject.Properties['Category'])
            {
                return [string]$Tweak.Category
            }

            return $null
        }
    }

    BeforeEach {
        $Script:GameMode = $false
        $Script:GamingModeActive = $false
        $Script:UpdatesModeActive = $false
        $Script:AppsModeActive = $false
        $Script:DeploymentMediaModeActive = $false
        $Script:TestGuiRunInProgressScript = $null
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Optimize item'; Function = 'AdvertisingID'; Category = 'Privacy' }
            @{ Name = 'Update item'; Function = 'WindowsUpdate'; Category = 'System' }
        )
    }

    It 'excludes Windows Updates selections from Optimize preview and run lists' {
        $Script:UpdatesModeActive = $false

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 1
        [string]$result[0]['Function'] | Should -Be 'AdvertisingID'
    }

    It 'excludes Optimize selections from Windows Updates preview and run lists' {
        $Script:UpdatesModeActive = $true

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 1
        [string]$result[0]['Function'] | Should -Be 'WindowsUpdate'
    }

    It 'excludes Gaming selections from Optimize preview and run lists' {
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Optimize item'; Function = 'AdvertisingID'; Category = 'Privacy' }
            @{ Name = 'Gaming item'; Function = 'GameOptimize'; Category = 'Gaming' }
        )

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 1
        [string]$result[0]['Function'] | Should -Be 'AdvertisingID'
    }

    It 'excludes Optimize selections from Gaming preview and run lists' {
        $Script:GamingModeActive = $true
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Optimize item'; Function = 'AdvertisingID'; Category = 'Privacy' }
            @{ Name = 'Gaming item'; Function = 'GameOptimize'; Category = 'Gaming' }
        )

        $result = @(Get-ActiveTweakRunList)

        $result.Count | Should -Be 1
        [string]$result[0]['Function'] | Should -Be 'GameOptimize'
    }

    It 'keeps Optimize preview and run actions disabled when only Windows Updates items are selected' {
        $Script:UpdatesModeActive = $false
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Update item'; Function = 'WindowsUpdate'; Category = 'System' }
        )
        $Script:BtnPreviewRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:BtnRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:MenuActionsPreviewRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:MenuActionsRunTweaks = [pscustomobject]@{ IsEnabled = $true }

        Update-GuiScopedRunActionAvailability

        $Script:BtnPreviewRun.IsEnabled | Should -BeFalse
        $Script:BtnRun.IsEnabled | Should -BeFalse
        $Script:MenuActionsPreviewRun.IsEnabled | Should -BeFalse
        $Script:MenuActionsRunTweaks.IsEnabled | Should -BeFalse
    }

    It 'enables Optimize preview and run actions when an Optimize item is selected' {
        $Script:UpdatesModeActive = $false
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Optimize item'; Function = 'AdvertisingID'; Category = 'Privacy' }
        )
        $Script:BtnPreviewRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:BtnRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:MenuActionsPreviewRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:MenuActionsRunTweaks = [pscustomobject]@{ IsEnabled = $false }

        Update-GuiScopedRunActionAvailability

        $Script:BtnPreviewRun.IsEnabled | Should -BeTrue
        $Script:BtnRun.IsEnabled | Should -BeTrue
        $Script:MenuActionsPreviewRun.IsEnabled | Should -BeTrue
        $Script:MenuActionsRunTweaks.IsEnabled | Should -BeTrue
    }

    It 'keeps Windows Updates preview and run actions disabled when only Optimize items are selected' {
        $Script:UpdatesModeActive = $true
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Optimize item'; Function = 'AdvertisingID'; Category = 'Privacy' }
        )
        $Script:BtnPreviewRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:BtnRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:MenuActionsPreviewRun = [pscustomobject]@{ IsEnabled = $true }
        $Script:MenuActionsRunTweaks = [pscustomobject]@{ IsEnabled = $true }

        Update-GuiScopedRunActionAvailability

        $Script:BtnPreviewRun.IsEnabled | Should -BeFalse
        $Script:BtnRun.IsEnabled | Should -BeFalse
        $Script:MenuActionsPreviewRun.IsEnabled | Should -BeFalse
        $Script:MenuActionsRunTweaks.IsEnabled | Should -BeFalse
    }

    It 'enables Windows Updates preview and run actions when a Windows Updates item is selected' {
        $Script:UpdatesModeActive = $true
        $script:SelectedTweakRunListForScopeTest = @(
            @{ Name = 'Update item'; Function = 'WindowsUpdate'; Category = 'System' }
        )
        $Script:BtnPreviewRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:BtnRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:MenuActionsPreviewRun = [pscustomobject]@{ IsEnabled = $false }
        $Script:MenuActionsRunTweaks = [pscustomobject]@{ IsEnabled = $false }

        Update-GuiScopedRunActionAvailability

        $Script:BtnPreviewRun.IsEnabled | Should -BeTrue
        $Script:BtnRun.IsEnabled | Should -BeTrue
        $Script:MenuActionsPreviewRun.IsEnabled | Should -BeTrue
        $Script:MenuActionsRunTweaks.IsEnabled | Should -BeTrue
    }
}

Describe 'PlatformSupport availability partition (P2 #18)' {
    # Entries flagged unavailable by Update-BaselineManifestAvailability must
    # be marked "Not applicable" in the run summary and filtered out of the
    # execution list, so the per-preset report surfaces the count of skipped
    # entries instead of silently dropping them.

    It 'does not partition selected tweaks on the WPF dispatcher before local apply' {
        $initIndex = $script:ExecutionContent.IndexOf('Initialize-ExecutionSummary -SelectedTweaks $tweakList')
        $partitionIndex = $script:ExecutionContent.IndexOf('Resolve-GuiExecutionRunnableTweaks -TweakList $tweakList -ForceUnsupported:$ForceUnsupported')
        $initIndex | Should -BeGreaterThan 0
        $partitionIndex | Should -Be -1
        $script:ExecutionRunContent | Should -Match 'Availability and\s+# execution-support gates are enforced by the worker'
    }

    It 'marks unavailable entries Not applicable via Set-ExecutionSummaryStatus' {
        $script:ExecutionContent | Should -Match "Set-ExecutionSummaryStatus -Key \(\[string\]\`$tweak\.Key\) -Status 'Not applicable' -Detail \`$detailText"
    }

    It 'keeps unavailable-entry filtering in the background worker' {
        $script:ExecutionContent | Should -Match 'return @\(\$availableTweaks\.ToArray\(\)\)'
        $script:ExecutionRunContent | Should -Not -Match '\$tweakList = @\(Resolve-GuiExecutionRunnableTweaks -TweakList \$tweakList -ForceUnsupported:\$ForceUnsupported\)'
        $script:ExecutionWorkerContent | Should -Match 'Resolve-GuiExecutionAvailabilityGate -Entry \$tweak -ForceUnsupported:\$bgForceUnsupported'
        $script:ExecutionWorkerContent | Should -Match 'Resolve-GuiExecutionSupportsExecutionGate -Entry \$tweak -ForceUnsupported:\$bgForceUnsupported'
        ([regex]::Matches($script:ExecutionWorkerContent, "Status = 'not applicable'")).Count | Should -BeGreaterOrEqual 2
        $script:ExecutionRunContent | Should -Match '\$skipStatus = if \(\$completedStatus -eq ''not applicable''\) \{ ''Not applicable'' \} else \{ ''Skipped'' \}'
    }

    It 'copies manifest availability and execution-support fields into resolved run selections' {
        $script:ExecutionRunContent | Should -Match 'Copy-ResolvedExecutionTweakWithGateMetadata'
        $script:ExecutionRunContent | Should -Match "'Availability', 'SupportsExecution', 'SupportsExecutionReason', 'TimeoutSeconds'"
        $script:ExecutionRunContent | Should -Match 'Get-ManifestEntryByFunction -Manifest \$Script:TweakManifest -Function \$functionName'
    }

    It 'reads availability metadata via the IDictionary and PSObject paths' {
        $script:GuiExecutionContent | Should -Match '\$availability\.Contains\(''Available''\)'
        $script:GuiExecutionContent | Should -Match '\$availability\.PSObject\.Properties\[''Available''\]'
    }

    It 'keeps Start-GuiExecutionRun inside the staged refactor size budget' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ExecutionRunPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0

        $functionAst = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Start-GuiExecutionRun'
        }, $true) | Select-Object -First 1

        $functionAst | Should -Not -BeNullOrEmpty
        ($functionAst.Extent.EndLineNumber - $functionAst.Extent.StartLineNumber + 1) | Should -BeLessOrEqual 400
    }
}
