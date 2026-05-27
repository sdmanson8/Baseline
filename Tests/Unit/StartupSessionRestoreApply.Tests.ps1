Set-StrictMode -Version Latest

BeforeAll {
    $script:StartupSessionRestoreApplyPath = Join-Path $PSScriptRoot '../../Module/GUI/Show-TweakGUI/StartupSessionRestoreApply.ps1'
    $script:StartupSessionRestoreApplyContent = Get-Content -LiteralPath $script:StartupSessionRestoreApplyPath -Raw
}

Describe 'Startup session restore apply' {
    It 'captures the current tab refresh helper for failed startup restores' {
        $script:StartupSessionRestoreApplyContent | Should -Match "Get-GuiFunctionCapture -Name 'Update-CurrentTabContent'"
        $script:StartupSessionRestoreApplyContent | Should -Match "Get-GuiFunctionCapture -Name 'Test-GuiVisibleTabContentCurrent'"
    }

    It 'preserves durable preferences while applying the startup session snapshot' {
        $script:StartupSessionRestoreApplyContent | Should -Match '& \$restoreGuiSessionStateScript -Snapshot \$Script:StartupSessionSnapshot -PreserveDurablePreferences'
    }

    It 'hydrates the selected startup tab when restore fails or visible content is stale' {
        $script:StartupSessionRestoreApplyContent | Should -Match '\$hydrateVisibleTab = \(-not \$restoredGuiSession -and \[bool\]\$Script:StartupRestoreSessionPending\)'
        $script:StartupSessionRestoreApplyContent | Should -Match '\$hydrateVisibleTab = -not \[bool\]\(& \$testVisibleTabContentCurrentScript\)'
        $script:StartupSessionRestoreApplyContent | Should -Match '& \$refreshCurrentTabContentScript -SkipIdlePrebuild'
    }

    It 'clears the pending startup restore flag after recovery hydration' {
        $script:StartupSessionRestoreApplyContent | Should -Match '\$Script:StartupRestoreSessionPending = \$false'
        $script:StartupSessionRestoreApplyContent | Should -Match "Regions\.GUI\.RestoreStartupSession\.HydrateVisibleTab"
    }
}
