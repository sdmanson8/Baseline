Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DialogPath = Join-Path $script:RepoRoot 'Module/GUI/DeploymentMediaBuilderDialog.ps1'
    $script:ViewPath = Join-Path $script:RepoRoot 'Module/GUI/DeploymentMediaBuilderView.ps1'
    $script:DeploymentMediaBuilderSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/DeploymentMediaBuilder'
    $script:DialogSplitPaths = @(
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Validation.ps1')
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Execution.ps1')
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Dialog.ps1')
    )
    $script:ViewSplitPaths = @(
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.UI.ps1')
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Unattend.ps1')
        (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Events.ps1')
    )
    $script:XamlPath = Join-Path $script:RepoRoot 'Module/GUI/MainWindow.xaml'
    $script:WindowSetupPath = Join-Path $script:RepoRoot 'Module/GUI/WindowSetup.ps1'
    $script:StyleManagementPath = Join-Path $script:RepoRoot 'Module/GUI/StyleManagement.ps1'
    $script:ModeStatePath = Join-Path $script:RepoRoot 'Module/GUI/ModeState.ps1'
    $script:SessionRestorePartPath = Join-Path $script:RepoRoot 'Module/GUI/SessionState/Restore-GuiSettingsSnapshot/RestorePreferenceSettings.ps1'
    $script:ActionHandlersPath = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers'
    $script:GuiRegionPath = Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1'

    $script:DialogParentContent = Get-Content -LiteralPath $script:DialogPath -Encoding UTF8 -Raw
    $script:ViewParentContent = Get-Content -LiteralPath $script:ViewPath -Encoding UTF8 -Raw
    $script:DialogContent = Get-BaselineTestSourceText -Path $script:DialogPath
    $script:ViewContent = Get-BaselineTestSourceText -Path $script:ViewPath
    $script:XamlContent = Get-BaselineTestSourceText -Path $script:XamlPath
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path $script:WindowSetupPath
    $script:StyleContent = Get-BaselineTestSourceText -Path $script:StyleManagementPath
    $script:ModeContent = Get-BaselineTestSourceText -Path $script:ModeStatePath
    $script:SessionRestoreContent = Get-BaselineTestSourceText -Path $script:SessionRestorePartPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $script:GuiRegionPath
}

Describe 'Deployment Media Builder split contract' {
    It 'keeps extracted files present and dot-sourced in fixed rollback order' {
        foreach ($path in @($script:DialogSplitPaths + $script:ViewSplitPaths)) {
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        }

        $script:DialogParentContent | Should -Match 'DeploymentMediaBuilder split rollback checkpoint'
        $dialogValidation = $script:DialogParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.Validation.ps1'")
        $dialogExecution = $script:DialogParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.Execution.ps1'")
        $dialogShell = $script:DialogParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.Dialog.ps1'")
        $dialogValidation | Should -BeGreaterThan -1
        $dialogExecution | Should -BeGreaterThan $dialogValidation
        $dialogShell | Should -BeGreaterThan $dialogExecution

        $script:ViewParentContent | Should -Match 'DeploymentMediaBuilder split rollback checkpoint'
        $viewUi = $script:ViewParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.UI.ps1'")
        $viewUnattend = $script:ViewParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.Unattend.ps1'")
        $viewEvents = $script:ViewParentContent.IndexOf("'DeploymentMediaBuilder/DeploymentMediaBuilder.Events.ps1'")
        $viewUi | Should -BeGreaterThan -1
        $viewUnattend | Should -BeGreaterThan $viewUi
        $viewEvents | Should -BeGreaterThan $viewUnattend
    }
}

Describe 'Deployment Media Builder menu wiring' {
    It 'does not expose Advanced Tools as a Tools menu action' {
        $script:XamlContent | Should -Not -Match 'Name="MenuToolsAdvanced"'
        $script:XamlContent | Should -Not -Match 'Name="MenuToolsDeploymentMediaBuilder"'
        $script:XamlContent | Should -Not -Match 'Advanced Tools\.\.\.'
    }

    It 'does not wire removed Advanced Tools controls in WindowSetup.ps1' {
        $script:WindowSetupContent | Should -Not -Match 'MenuToolsAdvanced'
        $script:WindowSetupContent | Should -Not -Match 'MenuToolsDeploymentMediaBuilder'
    }

    It 'does not localize or enable removed Advanced Tools menu surfaces' {
        $script:StyleContent | Should -Not -Match 'GuiMenuToolsAdvanced'
        $script:StyleContent | Should -Not -Match 'MenuToolsAdvanced'
        $script:ActionHandlersContent | Should -Not -Match 'GuiMenuToolsAdvanced'
        $script:StyleContent | Should -Not -Match 'GuiMenuToolsDeploymentMediaBuilder'
    }

    It 'does not reference Advanced Tools in mode visibility restores' {
        $script:ModeContent | Should -Not -Match 'MenuToolsAdvanced'
        $script:SessionRestoreContent | Should -Not -Match 'MenuToolsAdvanced'
        $script:ModeContent | Should -Not -Match 'MenuToolsDeploymentMediaBuilder'
        $script:SessionRestoreContent | Should -Not -Match 'MenuToolsDeploymentMediaBuilder'
    }

    It 'dot-sources DeploymentMediaBuilderDialog.ps1 from Module/Regions/GUI.psm1' {
        $script:GuiRegionContent | Should -Match "Join-Path \`$Script:GuiExtractedRoot 'DeploymentMediaBuilderDialog\.ps1'"
    }

    It 'dot-sources DeploymentMediaBuilderView.ps1 from Module/Regions/GUI.psm1' {
        $script:GuiRegionContent | Should -Match "Join-Path \`$Script:GuiExtractedRoot 'DeploymentMediaBuilderView\.ps1'"
    }
}

Describe 'Deployment Media Builder top navigation view' {
    It 'declares the builder navigation mode and inline view controls' {
        $script:XamlContent | Should -Match 'Name="NavModeDeploymentMedia"'
        $script:XamlContent | Should -Match '(?s)Name="NavModeUpdates".*Name="NavModeDeploymentMedia".*Name="NavModeApps"'
        $script:XamlContent | Should -Match 'Name="DeploymentMediaView"'
        $script:XamlContent | Should -Match 'Name="CmbDeploymentMediaMicrosoftIso"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaDownloadMicrosoftIso"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaDetectIso"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaPreviewPlan"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaStartBuild"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaCreateAutounattend"'
        $script:XamlContent | Should -Match 'Official Microsoft ISO Download'
        $script:XamlContent | Should -Match "Powered by Microsoft's Media Creation Tool"
        $script:XamlContent | Should -Match 'Name="DeploymentMediaChecklistExpander"'
        $script:XamlContent | Should -Match 'Setup checklist'
        $script:XamlContent | Should -Match 'Preview and Start ISO Build become available together after required setup inputs validate.'
        $script:XamlContent | Should -Not -Match 'Name="DeploymentMediaPlanCard"'
        $script:XamlContent | Should -Not -Match 'Name="TxtDeploymentMediaPlanPreview"'
        $script:XamlContent | Should -Match 'Name="BtnDeploymentMediaPreviewPlan"[^>]*IsEnabled="False"'

        $stepChecklist = $script:XamlContent.IndexOf('Setup checklist')
        $stepSource = $script:XamlContent.IndexOf('Choose source ISO')
        $stepDetect = $script:XamlContent.IndexOf('Detect editions')
        $stepOutput = $script:XamlContent.IndexOf('Choose build output')
        $stepCustomize = $script:XamlContent.IndexOf('Add optional setup customizations')
        $stepChecklist | Should -BeGreaterThan -1
        $stepSource | Should -BeGreaterThan -1
        $stepChecklist | Should -BeLessThan $stepSource
        $stepDetect | Should -BeGreaterThan $stepSource
        $stepOutput | Should -BeGreaterThan $stepDetect
        $stepCustomize | Should -BeGreaterThan $stepOutput

        $bottomActionStart = $script:XamlContent.IndexOf('<WrapPanel Name="BottomActionBar"')
        $bottomActionStart | Should -BeGreaterThan -1
        $bottomActionEnd = $script:XamlContent.IndexOf('</WrapPanel>', $bottomActionStart)
        $bottomActionEnd | Should -BeGreaterThan $bottomActionStart
        $bottomActionXaml = $script:XamlContent.Substring($bottomActionStart, $bottomActionEnd - $bottomActionStart)
        $bottomActionXaml | Should -Match 'Name="BtnDeploymentMediaPreviewPlan"'
        $bottomActionXaml | Should -Match 'Name="BtnDeploymentMediaStartBuild"'
        $bottomActionXaml | Should -Match 'Padding="18,10"'
        $bottomActionXaml | Should -Match 'Padding="28,12"'
    }

    It 'keeps DeploymentMediaView free of filter and search surfaces' {
        $idxStart = $script:XamlContent.IndexOf('<Grid Name="DeploymentMediaView"')
        $idxStart | Should -BeGreaterThan -1
        $idxEnd = $script:XamlContent.IndexOf('<Grid Name="AppsView"', $idxStart)
        $idxEnd | Should -BeGreaterThan $idxStart
        $deploymentViewXaml = $script:XamlContent.Substring($idxStart, $idxEnd - $idxStart)
        $deploymentViewXaml | Should -Not -Match 'Search'
        $deploymentViewXaml | Should -Not -Match 'Filter'
        $deploymentViewXaml | Should -Not -Match 'Name="BtnDeploymentMediaPreviewPlan"'
        $deploymentViewXaml | Should -Not -Match 'Name="BtnDeploymentMediaStartBuild"'
    }

    It 'wires the navigation view through normal mode state and plan helpers' {
        $script:WindowSetupContent | Should -Match '\$NavModeDeploymentMedia = \$Form\.FindName\("NavModeDeploymentMedia"\)'
        $script:WindowSetupContent | Should -Match '\$DeploymentMediaView = \$Form\.FindName\("DeploymentMediaView"\)'
        $script:WindowSetupContent | Should -Match '\$Script:NavModeDeploymentMedia = \$NavModeDeploymentMedia'
        $script:WindowSetupContent | Should -Match '\$Script:DeploymentMediaView = \$DeploymentMediaView'
        $script:StyleContent | Should -Match 'Nav_DeploymentMedia'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$NavModeDeploymentMedia -EventName ''Checked'''
        $script:ViewContent | Should -Match 'function Initialize-GuiDeploymentMediaBuilderView'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaBuilderPlan'
        $script:ViewContent | Should -Match 'function Convert-GuiDeploymentMediaBuilderInputPath'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaBuilderSourceIsoPath'
        $script:ViewContent | Should -Match 'function Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso'
        $script:ViewContent | Should -Match 'function Initialize-GuiDeploymentMediaMicrosoftIsoOptionList'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDownloadMicrosoftIso'
        $script:ViewContent | Should -Match 'function Test-GuiDeploymentMediaBuilderPreviewPrerequisites'
        $script:ViewContent | Should -Match 'function Update-GuiDeploymentMediaBuilderPreviewAvailability'
        $script:ViewContent | Should -Match '\$Script:BtnDeploymentMediaPreviewPlan\.IsEnabled = \$actionReady'
        $script:ViewContent | Should -Match '\$Script:BtnDeploymentMediaStartBuild\.IsEnabled = \$actionReady'
        $script:ViewContent | Should -Not -Match '\$Script:BtnDeploymentMediaStartBuild\.IsEnabled = \$Enabled -and \$Script:DeploymentMediaCurrentPlan'
        $script:ViewContent | Should -Match 'function Select-GuiDeploymentMediaBuilderWorkerPayload'
        $script:ViewContent | Should -Match 'function Clear-GuiDeploymentMediaBuilderDetectedIsoState'
        $script:ViewContent | Should -Match 'function Test-GuiDeploymentMediaBuilderIsoInfoPayload'
        $script:ViewContent | Should -Match 'function Set-GuiDeploymentMediaBuilderDetectedIsoInfo'
        $script:ViewContent | Should -Match 'function Set-GuiDeploymentMediaBuilderProgressState'
        $script:ViewContent | Should -Match 'function Initialize-GuiDeploymentMediaBuilderProgressChrome'
        $script:ViewContent | Should -Match 'function Show-GuiDeploymentMediaBuildPlanPreviewDialog'
        $script:ViewContent | Should -Match 'Show-ExecutionSummaryDialog -Title ''Preview Build Plan'''
        $script:ViewContent | Should -Match 'function Show-GuiDeploymentMediaBuildProgressDialog'
        $script:ViewContent | Should -Match 'function Set-GuiDeploymentMediaBuildDialogProgressState'
        $script:ViewContent | Should -Match 'function Add-GuiDeploymentMediaBuildDialogLogLine'
        $script:ViewContent | Should -Match 'function Complete-GuiDeploymentMediaBuildProgressDialog'
        $script:XamlContent | Should -Match 'Name="DeploymentMediaProgressPanel"'
        $script:XamlContent | Should -Match 'Name="DeploymentMediaProgressBar"'
        $script:XamlContent | Should -Match 'Name="TxtDeploymentMediaProgressText"'
        $script:WindowSetupContent | Should -Match '\$DeploymentMediaProgressPanel = \$Form\.FindName\("DeploymentMediaProgressPanel"\)'
        $script:WindowSetupContent | Should -Match '\$Script:DeploymentMediaProgressBar = \$DeploymentMediaProgressBar'
        $script:ViewContent | Should -Match 'Run Detect Editions again after changing the source ISO'
        $script:ViewContent | Should -Match 'Register-GuiEventHandler -Source \$Script:TxtDeploymentMediaSourceIso -EventName ''TextChanged'''
        $script:ViewContent | Should -Match 'ISO detection completed without usable edition data'
        $script:ViewContent | Should -Match 'Deployment media ISO edition detection started'
        $script:ViewContent | Should -Match 'Deployment media ISO editions detected'
        $script:ViewContent | Should -Match '\$null = \. \(\[string\]\$Context\.DialogPath\)'
        $script:ViewContent | Should -Match 'New-GuiDeploymentMediaBuildPlan'
        $script:ViewContent | Should -Match 'Start-GuiDeploymentMediaBuilderBackgroundOperation'
        $script:ViewContent | Should -Match 'Invoke-GuiDeploymentMediaBuild @buildParameters'
    }

    It 'runs ISO detection and media builds off the WPF thread with timeouts' {
        $script:ViewContent | Should -Match 'function Start-GuiDeploymentMediaBuilderBackgroundOperation'
        $script:ViewContent | Should -Match '\[System\.Management\.Automation\.Runspaces\.InitialSessionState\]::CreateDefault\(\)'
        $script:ViewContent | Should -Match '\$initialSessionState\.ImportPSModule\(@\(''Microsoft\.PowerShell\.Management'', ''Microsoft\.PowerShell\.Utility''\)\)'
        $script:ViewContent | Should -Match '\[System\.Management\.Automation\.Runspaces\.RunspaceFactory\]::CreateRunspace\(\$initialSessionState\)'
        $script:ViewContent | Should -Match '\[scriptblock\]\$WorkerBlock'
        $script:ViewContent | Should -Match '\.AddArgument\(\$Worker\)'
        $script:ViewContent | Should -Not -Match '\[scriptblock\]::Create\(\$WorkerSource\)'
        $script:ViewContent | Should -Match '\[System\.Windows\.Threading\.DispatcherTimer\]::new\(\)'
        $script:ViewContent | Should -Match '\$ps\.BeginInvoke\(\)'
        $script:ViewContent | Should -Match '\$ps\.BeginStop\(\$null, \$null\)'
        $script:ViewContent | Should -Match '-Name \$operationName.*-TimeoutSeconds 28800'
        $script:ViewContent | Should -Match '\$operationName = ''Microsoft ISO acquisition'''
        $script:ViewContent | Should -Match '\$operationName = ''UUP ISO assembly'''
        $script:ViewContent | Should -Match "-Name 'Deployment media ISO detection'.*-TimeoutSeconds 900"
        $script:ViewContent | Should -Match "-Name 'Deployment media build'.*-TimeoutSeconds 28800"
        $script:ViewContent | Should -Match 'Resolve-GuiDeploymentMediaBuilderSupportPath -Name ''Execution'''
        $script:ViewContent | Should -Match 'Resolve-GuiDeploymentMediaBuilderSupportPath -Name ''ProcessHelper'''
        $script:ViewContent | Should -Match '\. \(\[string\]\$Context\.ExecutionPath\)'
        $script:ViewContent | Should -Match '\$context\[''SelectedTweaks''\] = @\(\$selectedTweaks\)'
        $script:ViewContent | Should -Match 'function Stop-GuiDeploymentMediaBuilderBackgroundOperation'
        $script:ViewContent | Should -Match '\$operation\.Sync\.CancelRequested = \$true'
        $script:ViewContent | Should -Match 'Cancel Operation'
        $script:ViewContent | Should -Match 'CancellationState = \$Sync'
        $script:ViewContent | Should -Match 'GlobalTimeoutSeconds = 28800'
    }

    It 'captures delayed deployment media callback helpers before dispatcher callbacks run' {
        foreach ($expected in @(
            '\$setIsoValidationMessageScript = \$\{function:Set-GuiDeploymentMediaBuilderIsoValidationMessage\}',
            '\$setControlsEnabledScript = \$\{function:Set-GuiDeploymentMediaBuilderControlsEnabled\}',
            '\$setStatusScript = \$\{function:Set-GuiDeploymentMediaBuilderStatus\}',
            '\$writeErrorLogScript = \$\{function:Write-GuiDeploymentMediaBuilderErrorLog\}',
            '\$showDialogScript = \$\{function:Show-ThemedDialog\}',
            '\$clearDetectedIsoStateScript = \$\{function:Clear-GuiDeploymentMediaBuilderDetectedIsoState\}',
            '\$testIsoInfoPayloadScript = \$\{function:Test-GuiDeploymentMediaBuilderIsoInfoPayload\}',
            '\$convertPlanTextScript = \$\{function:Convert-GuiDeploymentMediaBuildPlanToText\}',
            '\$completeOperationScript = \$\{function:Complete-GuiDeploymentMediaBuilderBackgroundOperation\}',
            'function Convert-GuiDeploymentMediaBuilderWorkerErrorRecord',
            '\$convertWorkerErrorScript = \$\{function:Convert-GuiDeploymentMediaBuilderWorkerErrorRecord\}',
            '\$writeDebugLogScript = \$\{function:Write-GuiDeploymentMediaBuilderViewDebugLog\}',
            '\$ErrorActionPreference = ''Stop''',
            '\[scriptblock\]\$WorkerBlock',
            'ProgressPayload = \$null',
            'LastStatus = ''''',
            '\$streamErrors = @\(\$ps\.Streams\.Error\)',
            'ErrorCount=\{2\}',
            'DeploymentMediaBuilderView\.BackgroundOperation\.ErrorStream',
            '\$showMicrosoftIsoFailureDialogScript = \$\{function:Show-GuiDeploymentMediaMicrosoftIsoFailureDialog\}',
            '\$writeSwallowedExceptionScript = Get-Command -Name ''Write-SwallowedException''',
            '& \$setStatusScript -Message \$Message -Tone ''muted'' -ShowBanner',
            '& \$writeErrorLogScript -ErrorRecord \$ErrorRecord',
            '& \$clearDetectedIsoStateScript -Summary',
            '& \$setControlsEnabledScript -Enabled:\$true',
            '& \$completeOperationScript -Operation \$operation',
            '\$workerErrorRecord = & \$convertWorkerErrorScript -ErrorRecord \$streamErrorRecord -OperationName \$Name',
            '\$workerErrorRecord = & \$convertWorkerErrorScript -ErrorRecord \$_ -OperationName \$Name',
            '& \$writeDebugLogScript -Message',
            '\$operation\.LastStatus = \$statusKey',
            '& \$StatusCallback \$progressPayload',
            'DeploymentMediaBuilderMissingWorkerPayload',
            'DeploymentMediaBuilderView\.BackgroundOperation\.MissingPayload',
            '& \$FailedCallback -ErrorRecord \$workerErrorRecord',
            '& \$showDialogScript -Title ''Deployment Media Builder'''
        )) {
            $script:ViewContent | Should -Match $expected
        }

        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?\$clearDetectedIsoStateScript = \$\{function:Clear-GuiDeploymentMediaBuilderDetectedIsoState\}'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?\$testIsoInfoPayloadScript = \$\{function:Test-GuiDeploymentMediaBuilderIsoInfoPayload\}'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?\$writeDebugLogScript = \$\{function:Write-GuiDeploymentMediaBuilderViewDebugLog\}'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?& \$testIsoInfoPayloadScript -IsoInfo \$isoInfo'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?\$completedCallback = \{[\s\S]+?& \$writeDebugLogScript -Message'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?\$failedCallback = \{[\s\S]+?& \$writeDebugLogScript -Message'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$writeDebugLogScript = \$\{function:Write-GuiDeploymentMediaBuilderViewDebugLog\}'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$buildResult = Invoke-GuiDeploymentMediaBuild @buildParameters[\s\S]+?if \(\$null -eq \$buildResult\)'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$completedCallback = \{[\s\S]+?& \$writeDebugLogScript -Message'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$completedCallback = \{[\s\S]+?if \(-not \$buildResult\)'
        $script:ViewContent | Should -Match 'Deployment media build returned an incomplete result\. OutputPath="\{0\}"; ReportPath="\{1\}"\.'
        $script:ViewContent | Should -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$failedCallback = \{[\s\S]+?& \$writeDebugLogScript -Message'

        $script:ViewContent | Should -Not -Match '(?m)^\s*Set-GuiDeploymentMediaBuilderStatus -Message \$Message -Tone ''muted'' -ShowBanner'
        $script:ViewContent | Should -Not -Match '(?m)^\s*Complete-GuiDeploymentMediaBuilderBackgroundOperation -Operation \$operation'
        $script:ViewContent | Should -Not -Match '(?m)^\s*\$lastStatus = '''''
        $script:ViewContent | Should -Not -Match '(?m)^\s*& \$FailedCallback -ErrorRecord \$_'
    }

    It 'routes deployment media build progress through the shared progress dialog without duplicate status text' {
        $script:ViewContent | Should -Match '\$setProgressStateScript = \$\{function:Set-GuiDeploymentMediaBuilderProgressState\}'
        $script:ViewContent | Should -Match '\$showBuildDialogScript = \$\{function:Show-GuiDeploymentMediaBuildProgressDialog\}'
        $script:ViewContent | Should -Match '\$setBuildDialogProgressScript = \$\{function:Set-GuiDeploymentMediaBuildDialogProgressState\}'
        $script:ViewContent | Should -Match '\$addBuildDialogProgressLogScript = \$\{function:Add-GuiDeploymentMediaBuildDialogProgressLog\}'
        $script:ViewContent | Should -Match '\$completeBuildDialogScript = \$\{function:Complete-GuiDeploymentMediaBuildProgressDialog\}'
        $script:ViewContent | Should -Match '& \$setProgressStateScript -Progress \$Progress -Message \$message'
        $script:ViewContent | Should -Match '& \$setBuildDialogProgressScript -Dialog \$buildDialog -Progress \$Progress -Message \$message'
        $script:ViewContent | Should -Match '& \$addBuildDialogProgressLogScript -Dialog \$buildDialog -Progress \$Progress -Message \$message'
        $script:ViewContent | Should -Match '& \$setStatusScript -Message ''Build running\.'' -Tone ''muted'''
        $script:ViewContent | Should -Match '& \$setProgressStateScript -Hide'
        $script:ViewContent | Should -Not -Match '\$statusMessage ='
        $script:ViewContent | Should -Not -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$statusCallback = \{[\s\S]+?& \$setStatusScript -Message \$statusMessage'
        $script:ViewContent | Should -Match '\$inlineStatusText = if \(\$ShowBanner\) \{ '''' \} else \{ \[string\]\$Message \}'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaSharedProgressBarStateCommand'
        $script:ViewContent | Should -Match '\$setSharedProgressBarState = Get-GuiDeploymentMediaSharedProgressBarStateCommand'
        $script:ViewContent | Should -Match '& \$setSharedProgressBarState -ProgressBar \$Script:DeploymentMediaProgressBar'
        $script:ViewContent | Should -Match '& \$setSharedProgressBarState -ProgressBar \$Dialog\.ProgressBar'
        $script:ViewContent | Should -Match 'New-Object System\.Windows\.Controls\.RichTextBox'
        $script:ViewContent | Should -Match '\$abortButton\.Content = ''Abort'''
        $script:ViewContent | Should -Match 'Stop-GuiDeploymentMediaBuilderBackgroundOperation'
        $script:ViewContent | Should -Not -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?\$Script:TxtDeploymentMediaPlanPreview\.Text = \(& \$convertPlanTextScript -Plan \$plan\) \+ \[Environment\]::NewLine \+ \[Environment\]::NewLine \+ \$Message'
        $script:ViewContent | Should -Not -Match 'function Invoke-GuiDeploymentMediaBuilderStartBuild[\s\S]+?& \$setStatusScript -Message \$Message -Tone ''muted'' -ShowBanner'
    }

    It 'populates detected ISO editions as selectable data and syncs the selected image index' {
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaBuilderSelectedEdition'
        $script:ViewContent | Should -Match 'function New-GuiDeploymentMediaBuilderEditionItem'
        $script:ViewContent | Should -Match 'function Set-GuiDeploymentMediaBuilderDetectedEditionItems'
        $script:ViewContent | Should -Match 'function Sync-GuiDeploymentMediaBuilderEditionSelection'
        $script:ViewContent | Should -Match '\$selectedItem\.PSObject\.Properties\[''Edition''\]'
        $script:ViewContent | Should -Match '\$Script:CmbDeploymentMediaDetectedEdition\.DisplayMemberPath = ''DisplayName'''
        $script:ViewContent | Should -Match '\$Script:CmbDeploymentMediaDetectedEdition\.SelectedValuePath = ''Index'''
        $script:ViewContent | Should -Match '\$Script:DeploymentMediaDetectedEditionLookup\[\[string\]\$item\.DisplayName\] = \$edition'
        $script:ViewContent | Should -Match '\$Script:CmbDeploymentMediaDetectedEdition\.ItemsSource = @\(\$items\.ToArray\(\)\)'
        $script:ViewContent | Should -Match '\$Script:DeploymentMediaDetectedIsoInfo = \$IsoInfo'
        $script:ViewContent | Should -Match 'Set-GuiDeploymentMediaBuilderDetectedEditionItems -IsoInfo \$IsoInfo'
        $script:ViewContent | Should -Match '\$setDetectedIsoInfoScript = \$\{function:Set-GuiDeploymentMediaBuilderDetectedIsoInfo\}'
        $script:ViewContent | Should -Match '\$editionItemCount = & \$setDetectedIsoInfoScript -IsoInfo \$isoInfo'
        $script:ViewContent | Should -Not -Match '\$setDetectedEditionItemsScript = \$\{function:Set-GuiDeploymentMediaBuilderDetectedEditionItems\}'
        $script:ViewContent | Should -Not -Match '\$editionItemCount = & \$setDetectedEditionItemsScript -IsoInfo \$isoInfo'
        $script:ViewContent | Should -Match 'ISO detection completed without selectable Windows editions'
        $script:ViewContent | Should -Match 'Deployment media edition dropdown populated\. Items='
        $script:ViewContent | Should -Match '\$syncEditionSelectionScript = \$\{function:Sync-GuiDeploymentMediaBuilderEditionSelection\}'
        $script:ViewContent | Should -Match 'Register-GuiEventHandler -Source \$Script:CmbDeploymentMediaDetectedEdition -EventName ''SelectionChanged'''
        $script:ViewContent | Should -Match '& \$syncEditionSelectionScript'
        $script:ViewContent | Should -Match '\$Script:TxtDeploymentMediaEditionIndex\.Text = \[string\]\$selectedEdition\.Index'
        $script:ViewContent | Should -Not -Match 'function Invoke-GuiDeploymentMediaBuilderDetectIso[\s\S]+?New-Object System\.Windows\.Controls\.ComboBoxItem[\s\S]+?Deployment media ISO editions detected'
    }

    It 'handles Microsoft acquisition failures as a manual official-download path' {
        foreach ($expected in @(
            'function Test-GuiDeploymentMediaMicrosoftAutomatedDownloadBlocked',
            'function Show-GuiDeploymentMediaMicrosoftIsoFailureDialog',
            'Open Microsoft Download Page',
            'Start-Process -FilePath \$pageUrl -ErrorAction Stop',
            'DeploymentMediaBuilderView\.DownloadMicrosoftIso\.OpenMicrosoftDownloadPage',
            'The automated ISO acquisition workflow did not complete',
            'New-GuiDeploymentMediaUupAssemblyPlan -Option \$selectedOption',
            'UUP ISO Assembly',
            'Open UUP Website',
            'Package ZIP',
            'Command scripts:'
        )) {
            $script:ViewContent | Should -Match $expected
        }

        foreach ($unexpected in @(
            'sec-ch-ua',
            'sec-fetch-',
            'Chrome/137',
            'Get-Random -Minimum 600 -Maximum 1800',
            'Start-Sleep -Milliseconds'
        )) {
            $script:ViewContent | Should -Not -Match $unexpected
        }
    }

    It 'logs secondary UI rendering and operation logging failures explicitly' {
        $script:ViewContent | Should -Match 'function Write-GuiDeploymentMediaBuilderErrorLog'
        $script:ViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''DeploymentMediaBuilderView\.SetStatus\.ConvertBrush'' -Severity Warning'
        $script:ViewContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source \$Source -Severity Warning'
        $script:ViewContent | Should -Not -Match 'catch \{ \$brush = \$null \}'
        $script:ViewContent | Should -Not -Match 'failure could not be written to the Baseline log'
    }

    It 'captures view commands before registering WPF handlers' {
        foreach ($expected in @(
            '\$resetStartStateScript = \$\{function:Reset-GuiDeploymentMediaBuilderStartState\}',
            '\$setStatusScript = \$\{function:Set-GuiDeploymentMediaBuilderStatus\}',
            '\$fileDialogScript = \$\{function:Show-GuiDeploymentMediaBuilderFileDialog\}',
            '\$folderDialogScript = \$\{function:Show-GuiDeploymentMediaBuilderFolderDialog\}',
            '\$unattendGeneratorScript = Get-GuiRuntimeCommand -Name ''Show-GuiDeploymentMediaUnattendGeneratorDialog'' -CommandType ''Function''',
            '\$downloadMicrosoftIsoScript = \$\{function:Invoke-GuiDeploymentMediaBuilderDownloadMicrosoftIso\}',
            '\$detectIsoScript = \$\{function:Invoke-GuiDeploymentMediaBuilderDetectIso\}',
            '\$previewPlanScript = \$\{function:Invoke-GuiDeploymentMediaBuilderPreviewPlan\}',
            '\$startBuildScript = \$\{function:Invoke-GuiDeploymentMediaBuilderStartBuild\}',
            '\$syncTextScript = \$\{function:Sync-GuiDeploymentMediaBuilderViewText\}',
            '\$sourceMatchesDetectedIsoScript = \$\{function:Test-GuiDeploymentMediaBuilderSourceMatchesDetectedIso\}',
            '\$getSourceIsoPathScript = \$\{function:Get-GuiDeploymentMediaBuilderSourceIsoPath\}',
            '& \$resetStartStateScript',
            '& \$setStatusScript -Message',
            '\$path = & \$fileDialogScript -Filter',
            '\$path = & \$folderDialogScript -Description',
            'Show-GuiDeploymentMediaUnattendGeneratorDialog not found',
            '& \$unattendGeneratorScript -TargetTextBox \$autounattendTextBox',
            '\{ & \$downloadMicrosoftIsoScript \}\.GetNewClosure\(\)',
            '\{ & \$detectIsoScript \}\.GetNewClosure\(\)',
            '\{ & \$previewPlanScript \}\.GetNewClosure\(\)',
            '\{ & \$startBuildScript \}\.GetNewClosure\(\)'
        )) {
            $script:ViewContent | Should -Match $expected
        }

        foreach ($unexpected in @(
            '\{ Invoke-GuiDeploymentMediaBuilderDetectIso \}\.GetNewClosure\(\)',
            '\{ Invoke-GuiDeploymentMediaBuilderPreviewPlan \}\.GetNewClosure\(\)',
            '\{ Invoke-GuiDeploymentMediaBuilderStartBuild \}\.GetNewClosure\(\)',
            '\$path = Show-GuiDeploymentMediaBuilderFileDialog -Filter',
            '\$path = Show-GuiDeploymentMediaBuilderFolderDialog -Description'
        )) {
            $script:ViewContent | Should -Not -Match $unexpected
        }
    }

    It 'validates Detect Editions input before ISO inspection' {
        $script:ViewContent | Should -Match 'function Set-GuiDeploymentMediaBuilderIsoValidationMessage'
        $script:ViewContent | Should -Match '\$getSourceIsoPathScript = \$\{function:Get-GuiDeploymentMediaBuilderSourceIsoPath\}'
        $script:ViewContent | Should -Match '\$sourceIso = & \$getSourceIsoPathScript'
        $script:ViewContent | Should -Match 'Select a Windows ISO before detecting editions\.'
        $script:ViewContent | Should -Match 'Source ISO must be an \.iso file\.'
        $script:ViewContent | Should -Match 'Source ISO does not exist: \{0\}'
        $script:ViewContent | Should -Match 'Get-GuiDeploymentMediaIsoImageInfo -SourceIso \$sourceIso'
        $script:ViewContent | Should -Match 'ExecutionPath = \$executionPath'
        $script:ViewContent | Should -Not -Match 'Get-GuiDeploymentMediaIsoImageInfo -SourceIso \(\[string\]\$Script:TxtDeploymentMediaSourceIso\.Text\)'
    }

    It 'captures target text boxes for browse button handlers' {
        foreach ($expected in @(
            '\$sourceIsoTextBox = \$Script:TxtDeploymentMediaSourceIso',
            '\$autounattendTextBox = \$Script:TxtDeploymentMediaAutounattend',
            '\$workingDirectoryTextBox = \$Script:TxtDeploymentMediaWorkingDirectory',
            '\$driverSourceTextBox = \$Script:TxtDeploymentMediaDriverSource',
            '\$usbTargetRootTextBox = \$Script:TxtDeploymentMediaUsbTargetRoot',
            '\$sourceIsoTextBox\.Text = \$path',
            '\$autounattendTextBox\.Text = \$path',
            '\$workingDirectoryTextBox\.Text = \$path',
            '\$driverSourceTextBox\.Text = \$path',
            '\$usbTargetRootTextBox\.Text = \[System\.IO\.Path\]::GetPathRoot\(\$path\)',
            'ISO selected\. Run Detect Editions to inspect available images\.'
        )) {
            $script:ViewContent | Should -Match $expected
        }

        foreach ($expected in @(
            '\$CmbDeploymentMediaMicrosoftIso = \$Form\.FindName\("CmbDeploymentMediaMicrosoftIso"\)',
            '\$BtnDeploymentMediaDownloadMicrosoftIso = \$Form\.FindName\("BtnDeploymentMediaDownloadMicrosoftIso"\)',
            '\$Script:CmbDeploymentMediaMicrosoftIso = \$CmbDeploymentMediaMicrosoftIso',
            '\$Script:BtnDeploymentMediaDownloadMicrosoftIso = \$BtnDeploymentMediaDownloadMicrosoftIso',
            '\$BtnDeploymentMediaCreateAutounattend = \$Form\.FindName\("BtnDeploymentMediaCreateAutounattend"\)',
            '\$Script:BtnDeploymentMediaCreateAutounattend = \$BtnDeploymentMediaCreateAutounattend'
        )) {
            $script:WindowSetupContent | Should -Match $expected
        }

        foreach ($unexpected in @(
            '\$Script:TxtDeploymentMediaSourceIso\.Text = \$path',
            '\$Script:TxtDeploymentMediaAutounattend\.Text = \$path',
            '\$Script:TxtDeploymentMediaWorkingDirectory\.Text = \$path',
            '\$Script:TxtDeploymentMediaDriverSource\.Text = \$path',
            '\$Script:TxtDeploymentMediaUsbTargetRoot\.Text = \[System\.IO\.Path\]::GetPathRoot\(\$path\)'
        )) {
            $script:ViewContent | Should -Not -Match $unexpected
        }
    }

    It 'creates autounattend XML offline without browser or navigation dependencies' {
        $script:ViewContent | Should -Match 'function Show-GuiDeploymentMediaUnattendGeneratorDialog'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaUnattendOptionGroups'
        $script:ViewContent | Should -Match 'function New-GuiDeploymentMediaUnattendXmlDocument'
        $script:ViewContent | Should -Match 'function Save-GuiDeploymentMediaUnattendXml'
        $script:ViewContent | Should -Match 'function New-GuiSectionHeader'
        $script:ViewContent | Should -Match 'function New-GuiSettingCard'
        $script:ViewContent | Should -Match 'function New-GuiSettingRow'
        $script:ViewContent | Should -Match 'function Update-GuiUnattendControlDependencies'
        $script:ViewContent | Should -Match 'function Test-GuiDeploymentMediaUnattendGeneratorState'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaUnattendSummary'
        $script:ViewContent | Should -Match 'function Get-GuiDeploymentMediaUnattendPresetChoices'
        $script:ViewContent | Should -Match "SourceModel', 'Schneegans\.Unattend\.Configuration'"
        foreach ($expected in @(
            'GUICommon\\ConvertTo-RoundedWindow',
            'GUICommon\\Complete-RoundedWindow',
            '\$window\.Width = \[Math\]::Min\(\[double\]940',
            '\$window\.Height = \[Math\]::Min\(\[double\]640',
            '\$window\.MaxWidth = \[Math\]::Max',
            '\$window\.MaxHeight = \[Math\]::Max',
            '\$window\.WindowState = \[System\.Windows\.WindowState\]::Normal',
            'function New-GuiUnattendTabStripItem',
            'function Update-GuiDeploymentMediaUnattendTabVisuals',
            'New-GuiIconTextBlock -IconName',
            '\$tabScroll\.HorizontalScrollBarVisibility = \[System\.Windows\.Controls\.ScrollBarVisibility\]::Auto',
            'MouseLeftButtonUp',
            'Advanced mode',
            '\$startInAdvancedMode = \$false',
            'Test-IsExpertModeUX',
            '\$advancedModeCheckBox\.IsChecked = \$startInAdvancedMode',
            '\$initialShowAdvanced = \[bool\]\$advancedModeCheckBox\.IsChecked',
            '& \$setChoiceDisplayModeScript -Controls \$controls -ShowAdvanced:\$initialShowAdvanced',
            '& \$updateDependenciesScript -Controls \$controls -ShowAdvanced:\$initialShowAdvanced',
            'raw XML/internal values',
            'GeneratedPreview',
            'Review XML',
            '\$updateReviewPanelScript = \$\{function:Update-GuiDeploymentMediaUnattendReviewPanel\}',
            '\$setChoiceDisplayModeScript = \$\{function:Set-GuiDeploymentMediaUnattendChoiceDisplayMode\}',
            '\$updateDependenciesScript = \$\{function:Update-GuiUnattendControlDependencies\}',
            '\$updateBloatwarePreviewScript = \$\{function:Update-GuiDeploymentMediaBloatwarePreview\}',
            '\$applyPresetScript = \$\{function:Apply-GuiDeploymentMediaUnattendPreset\}',
            '\$testStateScript = \$\{function:Test-GuiDeploymentMediaUnattendGeneratorState\}',
            '& \$updateReviewPanelScript -Controls \$controls',
            '& \$setChoiceDisplayModeScript -Controls \$controls',
            '& \$updateDependenciesScript -Controls \$controls',
            '& \$updateBloatwarePreviewScript -Controls \$controls',
            '& \$applyPresetScript -Preset',
            '& \$testStateScript -State \$state',
            'Import existing XML',
            'Generate XML',
            'Set-GuiButtonIconContent -Button \$useXmlButton -IconName ''Document'' -Text ''Import existing XML''',
            'Set-GuiButtonIconContent -Button \$previewButton -IconName ''PreviewRun'' -Text ''Preview''',
            'Set-GuiButtonIconContent -Button \$saveButton -IconName ''Document'' -Text ''Generate XML''',
            'Set-GuiButtonIconContent -Button \$closeButton -IconName ''Clear'''
        )) {
            $script:ViewContent | Should -Match $expected
        }
        foreach ($expected in @(
            'LanguageSettings',
            'AccountSettings',
            'EditionSettings',
            'ComputerNameSettings',
            'TimeZoneSettings',
            'ProcessorArchitectures',
            'Bloatwares',
            'ScriptSettings',
            'DesktopIcons',
            'StartFolderSettings'
        )) {
            $script:ViewContent | Should -Match $expected
        }
        $script:ViewContent | Should -Not -Match 'New-Object System\.Windows\.Controls\.WebBrowser'
        $script:ViewContent | Should -Not -Match '\[Uri\]'
        $script:ViewContent | Should -Not -Match '\.Navigate\('
        $script:ViewContent | Should -Not -Match 'view-source:'
        $script:ViewContent | Should -Not -Match '\$window\.Width = 1040'
        $script:ViewContent | Should -Not -Match '\$window\.Height = 760'
        $script:ViewContent | Should -Not -Match 'New-Object System\.Windows\.Controls\.ListBox'
        $script:ViewContent | Should -Not -Match 'New-Object System\.Windows\.Controls\.TabControl'
        $script:ViewContent | Should -Not -Match 'Use custom XML\.\.\.'
        $script:ViewContent | Should -Not -Match 'Create XML\.\.\.'
    }
}

Describe 'Offline autounattend generator XML contract' {
    BeforeAll {
        . $script:ViewPath
    }

    It 'serializes option defaults into a valid local autounattend document' {
        $state = [ordered]@{}
        foreach ($group in @(Get-GuiDeploymentMediaUnattendOptionGroups)) {
            foreach ($option in @($group.Options)) {
                $state[[string]$option.Key] = $option.Default
            }
        }

        $document = New-GuiDeploymentMediaUnattendXmlDocument -State $state
        $document.GetType().FullName | Should -Be 'System.Xml.XmlDocument'

        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($document.NameTable)
        $namespaceManager.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')

        $document.SelectSingleNode('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]', $namespaceManager) | Should -Not -BeNullOrEmpty
        $document.SelectNodes('//u:RunSynchronousCommand', $namespaceManager).Count | Should -BeGreaterThan 0
        $document.OuterXml | Should -Match 'BaselineOfflineGenerator'
        $document.OuterXml | Should -Match 'Option name="LanguageSettings"'
        $document.OuterXml | Should -Match 'Option name="AccountSettings"'
    }

    It 'uses friendly UI choices while preserving raw XML values' {
        $groups = @(Get-GuiDeploymentMediaUnattendOptionGroups)
        $options = @{}
        foreach ($group in $groups) {
            foreach ($option in @($group.Options)) {
                $options[[string]$option.Key] = $option
            }
        }

        $options['KeyboardIdentifier'].Kind | Should -Be 'Choice'
        @($options['KeyboardIdentifier'].Choices | Where-Object { $_.Label -eq 'English (United States) - QWERTY' -and $_.Value -eq '00000409' }).Count | Should -Be 1
        @($options['GeoLocation'].Choices | Where-Object { $_.Label -eq 'United States' -and $_.Value -eq '244' }).Count | Should -Be 1
        @($options['ProcessorArchitectures'].Choices | Where-Object { $_.Label -eq '64-bit (x64)' -and $_.Value -eq 'amd64' }).Count | Should -Be 1
        $options['BypassRequirementsCheck'].Description | Should -Match 'unsupported TPM'
        $options['InstallImageIndex'].DependsOn[0].Key | Should -Be 'InstallFromSettings'
        $options['AccountName0'].DependsOn[0].Value | Should -Be 'UnattendedLocalAccount'
    }

    It 'validates dependent answer-file fields before saving' {
        $state = [ordered]@{
            UILanguage = 'en-US'
            UserLocale = 'en-US'
            AccountSettings = 'UnattendedLocalAccount'
            AccountName0 = ''
            WifiSettings = 'Unattended'
            WifiSsid = ''
            WifiKey = ''
            InstallFromSettings = 'ImageIndex'
            InstallImageIndex = 'abc'
            TimeZoneSettings = 'Explicit'
            TimeZone = ''
        }

        $result = Test-GuiDeploymentMediaUnattendGeneratorState -State $state
        $result.IsValid | Should -BeFalse
        ($result.Errors -join "`n") | Should -Match 'account name'
        ($result.Errors -join "`n") | Should -Match 'SSID'
        ($result.Errors -join "`n") | Should -Match 'positive number'
        ($result.Errors -join "`n") | Should -Match 'time zone'
    }
}

Describe 'Microsoft ISO source download contract' {
    BeforeAll {
        . (Join-Path $script:DeploymentMediaBuilderSplitRoot 'DeploymentMediaBuilder.Validation.ps1')
    }

    It 'offers MCT-first Windows 10 and Windows 11 acquisition choices plus explicit fallbacks' {
        $options = @(Get-GuiDeploymentMediaMicrosoftIsoOptions)
        $options.Count | Should -BeGreaterOrEqual 5
        @($options | Where-Object { $_.Id -eq 'Windows11MctX64' -and $_.AcquisitionMode -eq 'MediaCreationTool' -and $_.MediaCreationToolUrl -eq 'https://go.microsoft.com/fwlink/?linkid=2156295' }).Count | Should -Be 1
        @($options | Where-Object { $_.Id -eq 'Windows10MctX64' -and $_.AcquisitionMode -eq 'MediaCreationTool' -and $_.MediaCreationToolUrl -eq 'https://go.microsoft.com/fwlink/?LinkId=691209' }).Count | Should -Be 1
        @($options | Where-Object { $_.AcquisitionMode -eq 'ManualPage' }).Count | Should -BeGreaterOrEqual 2
        @($options | Where-Object { $_.AcquisitionMode -eq 'UUPLocal' -and $_.ComplianceLabel -match 'Microsoft UUP files' }).Count | Should -Be 1
        foreach ($option in $options) {
            $option.PSObject.Properties.Name | Should -Contain 'AcquisitionMode'
            $option.PSObject.Properties.Name | Should -Contain 'FilePrefix'
        }
    }

    It 'only accepts HTTPS Microsoft-hosted ISO download links' {
        Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri 'https://software.download.prss.microsoft.com/dbazure/example/Win11.iso' | Should -BeTrue
        Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri 'https://software-static.download.prss.microsoft.com/dbazure/example/Win10.iso' | Should -BeTrue
        Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri 'https://download.windowsupdate.com/example/windows-uup.cab' | Should -BeTrue
        Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri 'http://software.download.prss.microsoft.com/dbazure/example/Win11.iso' | Should -BeFalse
        Test-GuiDeploymentMediaMicrosoftDownloadUri -Uri 'https://example.com/Win11.iso' | Should -BeFalse
    }

    It 'summarizes Microsoft connector rejection payloads without exposing raw JSON' {
        $message = Get-GuiDeploymentMediaMicrosoftConnectorErrorMessage -Operation 'download link request' -Json '{"Errors":[{"Key":"ErrorSettings.SentinelReject","Value":"Sentinel marked this request as rejected.","Type":9}]}'
        $message | Should -Be 'Microsoft temporarily rejected the automated ISO download request. This can happen when Microsoft rate-limits or blocks automated download sessions. Try again later, download the ISO manually from Microsoft, or import an existing ISO.'
        $message | Should -Not -Match '\{"Errors"'
        $message | Should -Not -Match 'ErrorSettings\.SentinelReject'
    }

    It 'uses Media Creation Tool orchestration instead of the legacy connector API' {
        foreach ($expected in @(
            'function Save-GuiDeploymentMediaMicrosoftMediaCreationTool',
            'function Test-GuiDeploymentMediaMicrosoftExecutableSignature',
            'function Get-GuiDeploymentMediaLiveProcessTreeSnapshot',
            'function Wait-GuiDeploymentMediaMctIsoFile',
            'function Start-GuiDeploymentMediaMicrosoftMediaCreationToolIsoWorkflow',
            'Get-AuthenticodeSignature -LiteralPath \$Path',
            'Start-Process -FilePath \(\[string\]\$tool\.Path\) -PassThru -WindowStyle Normal',
            'New-Object System\.IO\.FileSystemWatcher',
            'ParentProcessId=\{0\}',
            'ProcessExitGraceSeconds = 15',
            'Microsoft Media Creation Tool is closed; checking for completed ISO output',
            'Get-GuiDeploymentMediaIsoImageInfo -SourceIso \$isoPath',
            'function Get-GuiDeploymentMediaUupWorkflowLayout',
            'function Test-GuiDeploymentMediaUupToolchain',
            'function New-GuiDeploymentMediaUupAssemblyPlan',
            'function Import-GuiDeploymentMediaUupPackageManifest',
            'function Test-GuiDeploymentMediaUupPackageManifest',
            'function Wait-GuiDeploymentMediaUupPackageArchive',
            'function Expand-GuiDeploymentMediaUupPackageArchive',
            'function Find-GuiDeploymentMediaUupCommandScript',
            'function Start-GuiDeploymentMediaUupCommandProcess',
            'function Save-GuiDeploymentMediaUupTransparencyManifest',
            'WindowStyle = \[System\.Diagnostics\.ProcessWindowStyle\]::Normal',
            'Wait-GuiDeploymentMediaMctIsoFile[\s\S]+-IncludeSubdirectories'
        )) {
            $script:DialogContent | Should -Match $expected
        }

        foreach ($unexpected in @(
            'software-download-connector',
            'GetProductDownloadLinksBySku',
            'getskuinformationbyproductedition',
            'vlscppe\.microsoft\.com/tags',
            'ProductEditionPattern',
            'MediaCreationTool.*SendKeys'
        )) {
            $script:DialogContent | Should -Not -Match $unexpected
        }
    }

    It 'defines a concrete UUP assembly contract without calling it an official Microsoft ISO' {
        $option = @(Get-GuiDeploymentMediaMicrosoftIsoOptions | Where-Object { $_.AcquisitionMode -eq 'UUPLocal' } | Select-Object -First 1)[0]
        $plan = New-GuiDeploymentMediaUupAssemblyPlan -Option $option

        $plan.IsEnabled | Should -BeTrue
        $plan.AcquisitionTier | Should -Be 2
        $plan.ComplianceLabel | Should -Be 'Generated installation media using Microsoft UUP files.'
        $plan.OutputLabel | Should -Be 'ISO assembled locally from official Microsoft UUP packages.'
        $plan.OutputLabel | Should -Not -Match '^Official Microsoft ISO$'
        $plan.PSObject.Properties.Name | Should -Contain 'SourcePageUrl'
        $plan.PSObject.Properties.Name | Should -Contain 'CommandScriptNames'
        $plan.PSObject.Properties.Name | Should -Contain 'OutputDirectory'
        ($plan.DiscoveryPolicy -join "`n") | Should -Match 'UUP dump package generator'
        ($plan.PackageTypes -join ',') | Should -Match '\.cab'
        ($plan.PackageTypes -join ',') | Should -Match '\.esd'
        ($plan.CommandScriptNames -join ',') | Should -Match 'uup_download_windows\.cmd'
        ($plan.AssemblyStages -join "`n") | Should -Match 'Write transparency manifest and build report'
        $plan.Toolchain.PSObject.Properties.Name | Should -Contain 'DismAvailable'
        $plan.Toolchain.PSObject.Properties.Name | Should -Contain 'OscdimgAvailable'
    }
}

Describe 'Deployment Media Builder dialog contract' {
    It 'defines the dialog and plan/report helpers' {
        $script:DialogContent | Should -Match 'function Show-GuiDeploymentMediaBuilderDialog'
        $script:DialogContent | Should -Match 'function Import-GuiDeploymentMediaExecutionHelpers'
        $script:DialogContent | Should -Match 'function New-GuiDeploymentMediaBuildPlan'
        $script:DialogContent | Should -Match 'function Get-GuiDeploymentMediaIsoImageInfo'
        $script:DialogContent | Should -Match 'Import-GuiDeploymentMediaExecutionHelpers'
        $script:DialogContent | Should -Match 'function Get-GuiDeploymentMediaMicrosoftIsoOptions'
        $script:DialogContent | Should -Match 'function Resolve-GuiDeploymentMediaMicrosoftIsoDownloadLink'
        $script:DialogContent | Should -Match 'function Start-GuiDeploymentMediaMicrosoftMediaCreationToolIsoWorkflow'
        $script:DialogContent | Should -Match 'function Save-GuiDeploymentMediaMicrosoftLatestIso'
        $script:DialogContent | Should -Match 'function Invoke-GuiDeploymentMediaBuild'
        $script:DialogContent | Should -Match 'function Resolve-GuiDeploymentMediaOscdimgPath'
        $script:DialogContent | Should -Match 'function Install-GuiDeploymentMediaOscdimgPackage'
        $script:DialogContent | Should -Match 'function Test-GuiDeploymentMediaOscdimgDependencyError'
        $script:DialogContent | Should -Match 'function Get-GuiDeploymentMediaOscdimgInstallPageUrl'
        $script:DialogContent | Should -Match 'function Show-GuiDeploymentMediaDialogOscdimgInstallPrompt'
        $script:DialogContent | Should -Match 'function Invoke-GuiDeploymentMediaDriverInjection'
        $script:DialogContent | Should -Match 'function Save-GuiDeploymentMediaBuildReport'
    }

    It 'short-circuits in headless harness when $Script:CurrentTheme is unset' {
        $script:DialogContent | Should -Match 'if \(-not \$Script:CurrentTheme\)'
        $script:DialogContent | Should -Match 'return @\{ Cancelled = \$true; Previewed = \$false; Started = \$false; ReportPath = \$null; OutputPath = \$null; BuildRoot = \$null \}'
    }

    It 'keeps the workflow explicit, previewable, and auditable' {
        $script:DialogContent | Should -Match 'Preview Build Plan'
        $script:DialogContent | Should -Match 'Start ISO Build'
        $script:DialogContent | Should -Match 'Detect Editions'
        $script:ViewContent | Should -Match 'official Microsoft ISO acquisition'
        $script:ViewContent | Should -Match 'Start the selected ISO acquisition workflow'
        $script:DialogContent | Should -Match 'IsEnabled="False"'
        $script:DialogContent | Should -Match 'Show-ThemedDialog -Title \$titleText'
        $script:DialogContent | Should -Match 'Start-GuiDeploymentMediaDialogBackgroundOperation'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaBuild @buildParameters'
        $script:DialogContent | Should -Match 'Build report saved'
    }

    It 'downloads and verifies the official Media Creation Tool instead of scraping connector links' {
        foreach ($expected in @(
            'https://www.microsoft.com/en-us/software-download/windows11',
            'https://www.microsoft.com/en-us/software-download/windows10',
            'https://go.microsoft.com/fwlink/?linkid=2156295',
            'https://go.microsoft.com/fwlink/?LinkId=691209',
            'Test-GuiDeploymentMediaMicrosoftDownloadUri',
            'Downloaded Media Creation Tool hash verification failed',
            'Downloaded Microsoft executable signature is not valid',
            'Downloaded executable is not signed by Microsoft'
        )) {
            $script:DialogContent | Should -Match ([regex]::Escape($expected))
        }

        foreach ($unexpected in @(
            'software-download-connector',
            'GetProductDownloadLinksBySku',
            'getskuinformationbyproductedition',
            'vlscppe.microsoft.com/tags',
            'ProductEditionPattern'
        )) {
            $script:DialogContent | Should -Not -Match ([regex]::Escape($unexpected))
        }
    }

    It 'runs legacy modal ISO detection and media builds off the WPF thread' {
        $script:DialogContent | Should -Match 'function Start-GuiDeploymentMediaDialogBackgroundOperation'
        $script:DialogContent | Should -Match '\[System\.Management\.Automation\.Runspaces\.InitialSessionState\]::CreateDefault\(\)'
        $script:DialogContent | Should -Match '\$initialSessionState\.ImportPSModule\(@\(''Microsoft\.PowerShell\.Management'', ''Microsoft\.PowerShell\.Utility''\)\)'
        $script:DialogContent | Should -Match '\[System\.Management\.Automation\.Runspaces\.RunspaceFactory\]::CreateRunspace\(\$initialSessionState\)'
        $script:DialogContent | Should -Match '\[scriptblock\]\$WorkerBlock'
        $script:DialogContent | Should -Match '\.AddArgument\(\$Worker\)'
        $script:DialogContent | Should -Not -Match '\[scriptblock\]::Create\(\$WorkerSource\)'
        $script:DialogContent | Should -Match '\[System\.Windows\.Threading\.DispatcherTimer\]::new\(\)'
        $script:DialogContent | Should -Match '\$ps\.BeginInvoke\(\)'
        $script:DialogContent | Should -Match '\$ps\.BeginStop\(\$null, \$null\)'
        $script:DialogContent | Should -Match 'LastStatus = '''''
        $script:DialogContent | Should -Match '\$operation\.LastStatus = \$status'
        $script:DialogContent | Should -Match "-Name 'Deployment media ISO detection'.*-TimeoutSeconds 900"
        $script:DialogContent | Should -Match "-Name 'Deployment media build'.*-TimeoutSeconds 28800"
        $script:DialogContent | Should -Match 'function Stop-GuiDeploymentMediaDialogBackgroundOperation'
        $script:DialogContent | Should -Match 'Cancel Operation'
        $script:DialogContent | Should -Match 'CancellationState = \$Sync'
        $script:DialogContent | Should -Match 'Resolve-GuiDeploymentMediaDialogSupportPath -Name ''Execution'''
        $script:DialogContent | Should -Match 'ExecutionPath'
        $script:DialogContent | Should -Match 'ProcessHelperPath'
        $script:DialogContent | Should -Not -Match 'Invoke-GuiDeploymentMediaBuild -Plan \$currentPlan'
        $script:DialogContent | Should -Not -Match '(?m)^\s*\$lastStatus = '''''
    }

    It 'preserves the safety contract from todo1.md' {
        foreach ($expected in @(
            'Official Microsoft ISO only',
            'Never modify the original ISO',
            'Always use a temp/working directory',
            'Always verify WIM/ESD presence and selected image index',
            'Always show the selected edition before build',
            'Always produce a build log/report',
            'Always cleanup mounts',
            'Support safe cancellation',
            'Never silently ignore DISM or oscdimg failures',
            'Preview Build Plan remains optional before Start ISO Build'
        )) {
            $script:DialogContent | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'validates source ISO, edition index, answer file, and driver directory before start is enabled' {
        $script:DialogContent | Should -Match 'Source ISO is required'
        $script:DialogContent | Should -Match 'Source ISO must be an \.iso file'
        $script:DialogContent | Should -Match 'Selected edition index must be 1 or higher'
        $script:DialogContent | Should -Match 'Run Detect Editions before starting a build'
        $script:DialogContent | Should -Match 'Detected ISO image details belong to a different source ISO'
        $script:DialogContent | Should -Match 'Autounattend file must be an \.xml file'
        $script:DialogContent | Should -Match 'Driver source directory does not exist'
        $script:DialogContent | Should -Match '\$btnPreview\.IsEnabled = \$ready'
        $script:DialogContent | Should -Match '\$btnStartBuild\.IsEnabled = \$ready'
        $script:DialogContent | Should -Match 'Ready to preview or start ISO build'
    }

    It 'inspects the selected ISO with Windows image APIs and cleans up the mount' {
        $script:DialogContent | Should -Match "Get-Command -Name 'Mount-DiskImage' -CommandType Function, Cmdlet"
        $script:DialogContent | Should -Match 'function Import-GuiDeploymentMediaDismModule'
        $script:DialogContent | Should -Match "Import-Module -Name 'Dism' -ErrorAction Stop"
        $script:DialogContent | Should -Match 'function Invoke-GuiDeploymentMediaPowerShellStage[\s\S]+?\[System\.Management\.Automation\.Runspaces\.InitialSessionState\]::CreateDefault\(\)'
        $script:DialogContent | Should -Match 'function Invoke-GuiDeploymentMediaPowerShellStage[\s\S]+?\[System\.Management\.Automation\.Runspaces\.RunspaceFactory\]::CreateRunspace\(\$initialSessionState\)'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaPowerShellStage -Name ''Mount source ISO for edition detection'''
        $script:DialogContent | Should -Match 'Mount-DiskImage -ImagePath \$Path'
        $script:DialogContent | Should -Match 'Get-WindowsImage -ImagePath \$Path'
        $script:DialogContent | Should -Match 'sources\\install\.wim'
        $script:DialogContent | Should -Match 'sources\\install\.esd'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaIsoDismountCleanup -ImagePath \$SourceIso'
        $script:DialogContent | Should -Match 'Dismount-DiskImage -ImagePath \$ImagePath'
        $script:DialogContent | Should -Match 'Failed to cleanup mounted ISO'
    }

    It 'performs real media build actions instead of only writing a report' {
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaRobocopy -Source \$isoRoot -Destination \$mediaRoot'
        $script:DialogContent | Should -Match 'Copy-Item -LiteralPath \(\[string\]\$Plan\.AutounattendPath\) -Destination \$answerDestination'
        $script:DialogContent | Should -Match 'Get-SelectedTweakRunList -TweakManifest \$Script:TweakManifest -Controls \$Script:Controls'
        $script:DialogContent | Should -Match 'Resolve-GuiDeploymentMediaDismPath'
        $script:DialogContent | Should -Match "Invoke-GuiDeploymentMediaDism -ArgumentList @\('/Mount-Image'"
        $script:DialogContent | Should -Match "'/Add-Driver'"
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaDismountImage -MountPath \$installMountPath -Mode Save'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaEmergencyDismCleanup'
        $script:DialogContent | Should -Match 'oscdimg\.exe is required to create an ISO'
        $script:DialogContent | Should -Match 'Microsoft\.OSCDIMG'
        $script:DialogContent | Should -Match "Resolve-GuiDeploymentMediaOscdimgPath -InstallIfMissing"
        $script:DialogContent | Should -Match "'--id', 'Microsoft\.OSCDIMG'"
        $script:DialogContent | Should -Match "'--accept-package-agreements'"
        $script:DialogContent | Should -Match "'--accept-source-agreements'"
        $script:DialogContent | Should -Match "'--disable-interactivity'"
        $script:DialogContent | Should -Match "'--source', 'winget'"
        $script:DialogContent | Should -Match 'https://winstall\.app/apps/Microsoft\.OSCDIMG'
        $script:DialogContent | Should -Match 'Open Install Page'
        $script:DialogContent | Should -Match 'Invoke-UserLaunch -FilePath \$pageUrl -Description ''Microsoft OSCDIMG install page'''
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaProcess -FilePath \$oscdimgPath'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaRobocopy -Source \$mediaRoot -Destination \$targetRoot'
        $script:DialogContent | Should -Match 'Invoke-GuiDeploymentMediaProcess -FilePath \$bootsectPath'
        $script:DialogContent | Should -Match '\$validatedPlan = New-GuiDeploymentMediaBuildPlan'
        $script:DialogContent | Should -Match 'Deployment media build plan failed final validation'
        $script:DialogContent | Should -Match '\[object\[\]\]\$SelectedTweaks = \$null'
        $script:DialogContent | Should -Match '\$selectedTweaks = if \(\$null -ne \$SelectedTweaks\)'
        $script:DialogContent | Should -Match '\[hashtable\]\$CancellationState'
        $script:DialogContent | Should -Match 'Get-GuiDeploymentMediaStageTimeoutSeconds'
        $script:DialogContent | Should -Match 'New-GuiDeploymentMediaBuildTelemetry'
        $script:DialogContent | Should -Match 'StageRecords'
        $script:DialogContent | Should -Match 'CleanupRecords'
        $script:DialogContent | Should -Match 'function New-GuiDeploymentMediaByteProgressRecord'
        $script:DialogContent | Should -Match 'Write-GuiDeploymentMediaBuildCopyProgress'
        $script:DialogContent | Should -Match 'CompletedBytes'
        $script:DialogContent | Should -Match 'TotalBytes'
        $script:DialogContent | Should -Match 'RemainingSeconds'
        $script:DialogContent | Should -Match '\[System\.IO\.File\]::Open'
        $script:DialogContent | Should -Not -Match 'robocopy\.exe'
    }

    It 'uses structured telemetry and retrying cleanup for long-running media operations' {
        $script:DialogContent | Should -Match 'function Write-GuiDeploymentMediaTelemetryLog'
        $script:DialogContent | Should -Match 'function Get-GuiDeploymentMediaExecutionFunctionCapture'
        $script:DialogContent | Should -Match 'function Get-GuiDeploymentMediaTelemetryRecordWriter'
        $script:DialogContent | Should -Match '\$addTelemetryRecord = Get-GuiDeploymentMediaTelemetryRecordWriter'
        $script:DialogContent | Should -Match '\$assertNotCancelled = Get-GuiDeploymentMediaExecutionFunctionCapture -Name ''Assert-GuiDeploymentMediaNotCancelled'''
        $script:DialogContent | Should -Match '\$writeCopyProgress = Get-GuiDeploymentMediaExecutionFunctionCapture -Name ''Write-GuiDeploymentMediaBuildCopyProgress'''
        $script:DialogContent | Should -Not -Match '(?m)^\s*Add-GuiDeploymentMediaTelemetryRecord -Telemetry'
        $script:DialogContent | Should -Match 'DeploymentMediaTelemetry'
        $script:DialogContent | Should -Match 'SourceIsoName'
        $script:DialogContent | Should -Match 'Architecture'
        $script:DialogContent | Should -Match 'TempPaths'
        $script:DialogContent | Should -Match 'function Invoke-GuiDeploymentMediaCleanupWithRetry'
        $script:DialogContent | Should -Match 'MaxAttempts 3'
        $script:DialogContent | Should -Match 'Cleanup error'
        $script:DialogContent | Should -Match 'Emergency DISM cleanup'
    }

    It 'keeps Create USB explicit and conservative' {
        $script:DialogContent | Should -Match 'TxtUsbTargetRoot'
        $script:DialogContent | Should -Match 'USB target root is required when output mode is Create USB'
        $script:DialogContent | Should -Match 'USB target must be the root of a removable drive'
        $script:DialogContent | Should -Match 'USB target must be a removable drive'
        $script:DialogContent | Should -Match 'USB target root must be empty before Baseline copies media to it'
        $script:DialogContent | Should -Match 'Get-CimInstance -ClassName Win32_LogicalDisk'
    }
}

Describe 'Deployment Media Builder click handler integration' {
    It 'captures the dialog command from the GUI runtime command surface' {
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiDeploymentMediaBuilderDialog' -CommandType 'Function'"
        $script:ActionHandlersContent | Should -Match 'Show-GuiDeploymentMediaBuilderDialog not found'
    }

    It 'does not expose the removed direct Advanced Tools click handler' {
        $script:ActionHandlersContent | Should -Not -Match 'if \(\$MenuToolsAdvanced\)'
        $script:ActionHandlersContent | Should -Not -Match 'Register-GuiEventHandler -Source \$MenuToolsAdvanced -EventName ''Click'''
        $script:ActionHandlersContent | Should -Not -Match 'Deployment Media Builder dialog command is not available\.'
    }
}
