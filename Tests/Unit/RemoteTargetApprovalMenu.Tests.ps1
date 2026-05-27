Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:GuiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:MainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $script:ActionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:StyleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $script:SessionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $script:DialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $script:DialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $script:GuiContent = (Get-BaselineTestSourceText -Path $script:GuiPath) + "`n" + (Get-BaselineTestSourceText -Path $script:MainWindowPath)
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:StyleManagementContent = Get-BaselineTestSourceText -Path $script:StyleManagementPath
    $script:SessionStateContent = Get-BaselineTestSourceText -Path $script:SessionStatePath
    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $script:DialogHelpersPath
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
}

Describe 'Remote target approval menu' {
    It 'adds an explicit target approval action to the Tools menu and wires it through the GUI' {
        $script:GuiContent | Should -Match 'MenuToolsApproveRemoteTargets'
        $script:GuiContent | Should -Match 'Approve Target List\.{3}'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Set-GuiRemoteTargetApprovalList'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Test-GuiRemoteTargetApproval'"
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuToolsApproveRemoteTargets -EventName ''Click'''
        $script:ActionHandlersContent | Should -Match 'Approve this exact target list for the current session'
    }

    It 'stores approved target lists in session state and clears them on disconnect' {
        $script:SessionStateContent | Should -Match 'ApprovedTargetComputers'
        $script:SessionStateContent | Should -Match 'ApprovedAt'
        $script:SessionStateContent | Should -Match 'ApprovalMessage'
        $script:SessionStateContent | Should -Match 'PinnedBaselineVersion'
        $script:SessionStateContent | Should -Match 'SchemaVersion = 20'
        $script:SessionStateContent | Should -Match 'function Test-GuiRemoteTargetApproval'
        $script:SessionStateContent | Should -Match 'function Set-GuiRemoteTargetApprovalList'
        $script:SessionStateContent | Should -Match 'function Clear-GuiRemoteTargetApprovalList'
        $script:SessionStateContent | Should -Match 'function Export-GuiRemoteTargetApprovalPolicy'
        $script:SessionStateContent | Should -Match 'function Import-GuiRemoteTargetApprovalPolicy'
        $script:SessionStateContent | Should -Match 'Clear-BaselineRemoteSessionCache'
    }

    It 'routes remote-target banner and prompt fallbacks through Write-SwallowedException' {
        $script:SessionStateContent | Should -Match 'SessionState\.Set-GuiRemoteTargetContext\.UpdateGuiRemoteModeBanner'
        $script:SessionStateContent | Should -Match 'SessionState\.Clear-GuiRemoteTargetContext\.ClearBaselineRemoteSessionCache'
        $script:SessionStateContent | Should -Match 'SessionState\.Clear-GuiRemoteTargetContext\.UpdateGuiRemoteModeBanner'
        $script:SessionStateContent | Should -Match 'SessionState\.Update-GuiRemoteModeBanner\.LoadRemoteTargetContext'
        $script:SessionStateContent | Should -Match 'SessionState\.Update-GuiRemoteModeBanner\.ResolveRemoteConnectionMethodLabel'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.GetCredential'
    }

    It 'routes remote connection dialog setup and cleanup failures through Write-SwallowedException' {
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.SetOwner'
        $script:SessionStateContent | Should -Match 'Get-GuiSharedScrollBarStyleXaml -Theme \$theme'
        $script:SessionStateContent | Should -Match 'HorizontalScrollBarVisibility="Auto"'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.SetWindowChromeTheme'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.SetButtonChrome'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.SetGuiRemoteConnectivityResults'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.CleanupTestTimer'
        $script:SessionStateContent | Should -Match 'SessionState\.Prompt-GuiRemoteTargetConnection\.CleanupTestDisposePowerShell'
    }

    It 'routes GUI settings snapshot restore fallbacks through Write-SwallowedException' {
        $script:SessionStateContent | Should -Match 'SessionState\.Import-GuiSettingsProfile\.RestoreUndoSnapshot'
        $script:SessionStateContent | Should -Match 'SessionState\.Restore-GuiSnapshot\.RestoreRedoSnapshot'
    }

    It 'keeps the approval menu label and enabled state synced with styling' {
        $script:StyleManagementContent | Should -Match 'MenuToolsApproveRemoteTargets'
        $script:StyleManagementContent | Should -Match "GuiMenuToolsApproveRemoteTargets"
        $script:StyleManagementContent | Should -Match "New-GuiLabeledIconContent -IconName 'Shield'"
        $script:StyleManagementContent | Should -Match "New-GuiLabeledIconContent -IconName 'WindowConsole'"
        $script:StyleManagementContent | Should -Match "New-GuiLabeledIconContent -IconName 'WindowSettings'"
        $script:StyleManagementContent | Should -Match 'MenuToolsApproveRemoteTargets\.IsEnabled = \(\$Enabled'
        $script:StyleManagementContent | Should -Match 'MenuToolsSaveRemoteApprovalPolicy'
        $script:StyleManagementContent | Should -Match 'MenuToolsLoadRemoteApprovalPolicy'
        $script:StyleManagementContent | Should -Match 'MenuToolsRemoteConsole'
        $script:StyleManagementContent | Should -Match 'GuiMenuToolsRemoteConsole'
        $script:StyleManagementContent | Should -Match 'GuiMenuToolsSaveRemoteApprovalPolicy'
        $script:StyleManagementContent | Should -Match 'GuiMenuToolsLoadRemoteApprovalPolicy'
    }

    It 'adds a remote console dialog with orchestration controls' {
        $script:DialogHelpersContent | Should -Match 'function Show-GuiRemoteConsoleDialog'
        $script:DialogHelpersContent | Should -Match '\$scrollBarStyleXaml = Get-BaselineScrollBarStyleXaml -Theme \$theme'
        $script:DialogHelpersContent | Should -Match 'HorizontalScrollBarVisibility="Auto"'
        $script:DialogHelpersContent | Should -Match 'Remote Console'
        $script:DialogHelpersContent | Should -Match 'BtnConnect'
        $script:DialogHelpersContent | Should -Match 'BtnApprove'
        $script:DialogHelpersContent | Should -Match 'BtnSavePolicy'
        $script:DialogHelpersContent | Should -Match 'BtnLoadPolicy'
        $script:DialogHelpersContent | Should -Match 'BtnPreflight'
        $script:DialogHelpersContent | Should -Match "Get-GuiFunctionCapture -Name 'Invoke-PreflightChecks'"
        $script:DialogHelpersContent | Should -Match "Invoke-CapturedFunction -Name 'Invoke-PreflightChecks'"
        $script:DialogHelpersContent | Should -Match 'SupportedEnvironmentClassification'
        $script:DialogHelpersContent | Should -Match 'PolicyConflictSignals'
        $script:DialogHelpersContent | Should -Not -Match 'Firewall access:'
        $script:DialogHelpersContent | Should -Match 'Export Deep-Linked Support Bundle'
        $script:DialogHelpersContent | Should -Match 'DeepLinkRunId'
        $script:DialogHelpersContent | Should -Match 'TxtFilterRuns'
        $script:DialogHelpersContent | Should -Match 'LstRecentRemoteRuns'
        $script:DialogHelpersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteRunSummaries'"
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.ResolveErrorDialog'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.LoadSessionSnapshot'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.LoadSystemSnapshot'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.LoadConnectivityResults'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.StartExplorer'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiRemoteConsoleDialog\.RemoveSessionStatePath'
    }

    It 'adds a release status dialog and wires it through the Help menu' {
        $script:DialogHelpersContent | Should -Match 'function Show-GuiReleaseStatusDialog'
        $script:DialogHelpersContent | Should -Match 'Release Status'
        $script:DialogHelpersContent | Should -Match 'Pinned version:'
        $script:DialogHelpersContent | Should -Match 'Pin Current Version'
        $script:DialogHelpersContent | Should -Match 'Clear Pin'
        $script:DialogHelpersContent | Should -Match 'Icon system:'
        $script:DialogHelpersContent | Should -Match 'Validation matrix:'
        $script:DialogHelpersContent | Should -Match 'Validation evidence:'
        $script:DialogHelpersContent | Should -Match 'Validation channels:'
        $script:DialogHelpersContent | Should -Match 'Build/test provenance:'
        $script:DialogHelpersContent | Should -Match 'Artifact verification:'
        $script:DialogHelpersContent | Should -Match 'Server validation outside CI'
        $script:DialogHelpersContent | Should -Match 'Verification:'
        $script:GuiContent | Should -Match 'MenuHelpReleaseStatus'
        $script:GuiContent | Should -Match 'Release Status\.{3}'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiReleaseStatusDialog'"
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuHelpReleaseStatus -EventName ''Click'''
        $script:ActionHandlersContent | Should -Match 'GuiMenuHelpReleaseStatus'
        $script:StyleManagementContent | Should -Match 'MenuHelpReleaseStatus'
        $script:StyleManagementContent | Should -Match 'GuiMenuHelpReleaseStatus'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiReleaseStatusDialog\.ResolveModuleRoot'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiReleaseStatusDialog\.ResolveRepoRoot'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiReleaseStatusDialog\.LoadVersion'
    }

    It 'routes changelog and readme path resolution fallbacks through Write-SwallowedException' {
        $script:DialogHelpersContent | Should -Match 'function Resolve-BaselineChangelogPath'
        $script:DialogHelpersContent | Should -Match 'function Resolve-BaselineReadmePath'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.AddLauncherCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.AddAppBaseCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.AddModuleCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.AddDialogHelpersRootCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.AddCurrentDirectoryCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineChangelogPath\.TestCandidatePath'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.AddLauncherCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.AddAppBaseCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.AddModuleCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.AddDialogHelpersRootCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.AddCurrentDirectoryCandidate'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.Resolve-BaselineReadmePath\.TestCandidatePath'
    }

    It 'routes dialog event wiring fallbacks through Write-SwallowedException' {
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiTroubleshootingGuideDialog\.RaiseExportSupportBundleClick'
        $script:DialogHelpersContent | Should -Match 'DialogHelpers\.ShowGuiReleaseStatusDialog\.RaiseDownloadBaselineClick'
    }

    It 'adds a troubleshooting guide dialog and wires it through the Help menu' {
        $script:DialogHelpersContent | Should -Match 'function Show-GuiTroubleshootingGuideDialog'
        $script:DialogHelpersContent | Should -Match 'Troubleshooting Guide'
        $script:DialogHelpersContent | Should -Match 'GUI-STARTUP-004'
        $script:DialogHelpersContent | Should -Match 'Export Support Bundle'
        $script:DialogHelpersContent | Should -Match 'BtnExportBundle'
        $script:GuiContent | Should -Match 'MenuHelpTroubleshooting'
        $script:GuiContent | Should -Match 'Troubleshooting Guide\.{3}'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiTroubleshootingGuideDialog'"
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuHelpTroubleshooting -EventName ''Click'''
        $script:ActionHandlersContent | Should -Match 'GuiMenuHelpTroubleshooting'
        $script:StyleManagementContent | Should -Match 'MenuHelpTroubleshooting'
        $script:StyleManagementContent | Should -Match 'GuiMenuHelpTroubleshooting'
    }
}
