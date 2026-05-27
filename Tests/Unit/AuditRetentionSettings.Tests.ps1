Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:SessionStatePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $script:AuditViewPath = Join-Path $PSScriptRoot '../../Module/GUI/AuditView.ps1'
    $script:DialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $script:DialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $script:MainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $script:GuiContent = Get-BaselineTestSourceText -Path $script:SessionStatePath
    $script:AuditViewContent = Get-BaselineTestSourceText -Path $script:AuditViewPath
    $script:DialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $script:DialogHelpersPath
        (Join-Path $script:DialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $script:DialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
    $script:MainWindowContent = Get-BaselineTestSourceText -Path $script:MainWindowPath
}

Describe 'Audit retention settings' {
    It 'persists the retention window in GUI settings snapshots' {
        $script:GuiContent | Should -Match 'SchemaVersion = 20'
        $script:GuiContent | Should -Match 'AuditRetentionDays'
        $script:GuiContent | Should -Match '\$Script:AuditRetentionDays = \[int\]\$desiredAuditRetentionDays'
        $script:GuiContent | Should -Match '\$Script:Ctx.UI.AuditRetentionDays = \[int\]\$desiredAuditRetentionDays'
    }

    It 'initializes the audit dialog from the saved retention preference and keeps it live' {
        $script:AuditViewContent | Should -Match '\$initialRetentionDays = if \(\$Script:AuditRetentionDays\)'
        $script:AuditViewContent | Should -Match '\$retentionCombo.Add_SelectionChanged'
        $script:AuditViewContent | Should -Match '\$Script:AuditRetentionDays = & \$getSelectedRetentionDays'
        $script:AuditViewContent | Should -Match '\$Script:Ctx.UI.AuditRetentionDays = \[int\]\$Script:AuditRetentionDays'
    }

    It 'exposes audit retention as a first-class settings dialog and menu entry' {
        $script:DialogHelpersContent | Should -Match 'function Show-GuiAuditSettingsDialog'
        $script:DialogHelpersContent | Should -Match 'GuiAuditSettings'
        $script:DialogHelpersContent | Should -Match 'CmbAuditRetention'
        $script:MainWindowContent | Should -Match 'MenuFileAuditSettings'
        $script:MainWindowContent | Should -Match 'Audit Settings\.\.\.'
    }
}
