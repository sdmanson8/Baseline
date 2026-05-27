Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $stylePath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $actionPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $actionSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $executionPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration.ps1'
    $executionSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration'
    $iconFactoryPath = Join-Path $PSScriptRoot '../../Module/GUI/IconFactory.ps1'

    $script:StyleContent = Get-BaselineTestSourceText -Path $stylePath
    $script:IconFactoryContent = Get-BaselineTestSourceText -Path $iconFactoryPath
    $script:ActionContent = Get-BaselineTestSourceText -Path @(
        $actionPath
        (Join-Path $actionSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $actionSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $actionSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $actionSplitRoot 'MenuHandlers.ps1')
    )
    $script:ExecutionContent = Get-BaselineTestSourceText -Path @(
        $executionPath
        (Join-Path $executionSplitRoot 'ExecutionStateSummary.ps1')
        (Join-Path $executionSplitRoot 'ExecutionView.ps1')
        (Join-Path $executionSplitRoot 'ExecutionRunOrchestration.ps1')
    )
}

Describe 'Action button icon content' {
    It 'keeps localized toolbar and footer buttons on the shared icon pipeline' {
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnDefaults -IconName ''RestoreDefaults'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLog -IconName ''OpenLog'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLanguage -IconName ''Language'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnClearSearch -IconName ''Clear'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$clearButton -IconName ''Clear'' -Text '''''
        $script:StyleContent | Should -Match '-Foreground \$clearButton\.Foreground'
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnScanInstalledApps -IconName ''Search'''
        $script:IconFactoryContent | Should -Match 'function Set-GuiButtonIconContent[\s\S]*\[AllowEmptyString\(\)\]\s*\[string\]\$Text'
    }

    It 'preserves Preview Run and Run Tweaks icons during UX text refreshes' {
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnRun -IconName ''RunTweaks'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnPreviewRun -IconName ''PreviewRun'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnStartHere -IconName ''QuickStart'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnHelp -IconName ''Help'''
    }

    It 'always restores the main run button label after execution is no longer in progress' {
        $script:ActionContent | Should -Match 'if \(\$Script:BtnRun -and -not \(& \$Script:TestGuiRunInProgressScript\)\)'
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$Script:BtnRun -IconName ''RunTweaks'' -Text \(Get-UxRunActionLabel\) -ToolTip \(Get-UxRunActionToolTip\)'
        $script:ActionContent | Should -Not -Match '\$btnRunContent -notin @\(''Pause'', ''Resume'', ''Stopping\.\.\.'', ''Exiting\.\.\.''\)'
    }

    It 'drops the old Apps refresh label from the main run button' {
        $script:ActionContent | Should -Not -Match 'GuiRefreshButton'
        $script:ActionContent | Should -Not -Match 'Tooltip_RefreshInstallationStatus'
    }

    It 'routes Design Mode Save Config to configuration profile export' {
        $script:ActionContent | Should -Match 'Register-GuiEventHandler -Source \$BtnRun -EventName ''Click'''
        $script:ActionContent | Should -Match '\$testIsDesignModeUxCommand -and \(& \$testIsDesignModeUxCommand\)'
        $script:ActionContent | Should -Match '\$exportGuiConfigurationProfileCommand -Context ''DesignModeSaveConfig'''
        $script:ActionContent | Should -Match 'function Invoke-GuiConfigurationProfileExport'
        $script:ActionContent | Should -Match 'New-ConfigurationProfile'
        $script:ActionContent | Should -Match 'Export-ConfigurationProfile'
        $script:ActionContent | Should -Not -Match 'Test-IsDesignModeUX[\s\S]{0,250}Export-GuiSettingsProfile'
    }

    It 'routes ActionHandlers UI cleanup swallows through Write-SwallowedException' {
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.UpdateRunPathContextLabel\.Foreground'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.ExportSupportBundle\.RemoveSessionStatePath'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuFileExit\.CloseMainForm'''
    }

    It 'routes ActionHandlers help menu logger failures through Write-SwallowedException' {
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuClickRouting\.LogWarning'''
        $script:ActionContent | Should -Match '\$MenuHelpHelp\.Add_Click\(\$openHelpDialogFromMenu\)'
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpHelp\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpHelp\.ShowFailureDialog'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpGettingStarted\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpReadme\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpReadme\.ShowThemedDialog'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpFAQ\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpChangelog\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpUpdateCheck\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpReleaseStatus\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpTroubleshooting\.LogWarning'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpAbout\.ShowThemedDialog'''
    }

    It 'routes ActionHandlers help/about text fallbacks through Write-SwallowedException' {
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.ExportConfigProfile\.GetDisplayVersion'''
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.ImportConfigProfile\.GetDisplayVersion'''
        $script:ActionContent | Should -Match '& \$raiseButtonClick \$Script:BtnStartHere'
        $script:ActionContent | Should -Not -Match 'MenuHelpStartGuide\.GetQuickStartSteps'
        $script:ActionContent | Should -Not -Match 'MenuHelpStartGuide\.GetOnboardingMode'
        $script:ActionContent | Should -Not -Match 'MenuHelpStartGuide\.GetHelpLines'
        $script:ActionContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''ActionHandlers\.MenuHelpAbout\.GetDisplayVersion'''
    }

    It 'restores normal action labels through Sync-UxActionButtonText after execution view resets' {
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue"
        $script:ExecutionContent | Should -Match 'Sync-UxActionButtonText'
    }
}
