Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:GuiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:MainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $script:ActionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:DialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $script:DialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $script:StyleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $script:GuiContent = (Get-BaselineTestSourceText -Path $script:GuiPath) + "`n" + (Get-BaselineTestSourceText -Path $script:MainWindowPath)
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $script:DialogHelpersPath
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
    $script:StyleManagementContent = Get-BaselineTestSourceText -Path $script:StyleManagementPath
}

Describe 'Remote session status menu' {
    It 'exposes a remote session status entry in the Tools menu' {
        $script:GuiContent | Should -Match 'MenuToolsRemoteSessionStatus'
        $script:GuiContent | Should -Match 'Remote Session Status\.{3}'
        $script:DialogHelpersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteRunSummaries'"
        $script:DialogHelpersContent | Should -Match 'LstRecentRemoteRuns'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-BaselineRemoteSessionSummary'"
        $script:ActionHandlersContent | Should -Match 'TransportKey'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuToolsRemoteSessionStatus -EventName ''Click'''
        $script:ActionHandlersContent | Should -Match 'Viewed remote session status'
    }

    It 'keeps the label and enabled state in sync with GUI styling' {
        $script:StyleManagementContent | Should -Match 'MenuToolsRemoteSessionStatus'
        $script:StyleManagementContent | Should -Match "GuiMenuToolsRemoteSessionStatus"
        $script:StyleManagementContent | Should -Match 'MenuToolsRemoteSessionStatus\.IsEnabled = \$Enabled'
    }
}
