Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DialogPath = Join-Path $script:RepoRoot 'Module/GUI/StartupManagerDialog.ps1'
    $script:XamlPath = Join-Path $script:RepoRoot 'Module/GUI/MainWindow.xaml'
    $script:WindowSetupPath = Join-Path $script:RepoRoot 'Module/GUI/WindowSetup.ps1'
    $script:ActionHandlersPath = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers'
    $script:GuiRegionPath = Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1'

    $script:DialogContent = Get-BaselineTestSourceText -Path $script:DialogPath
    $script:XamlContent = Get-BaselineTestSourceText -Path $script:XamlPath
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path $script:WindowSetupPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $script:GuiRegionPath
}

Describe 'Startup Manager dialog: category placement' {
    It 'does not expose Startup Manager from the Tools menu' {
        $script:XamlContent | Should -Not -Match 'Name="MenuToolsStartupManager"'
        $script:WindowSetupContent | Should -Not -Match 'MenuToolsStartupManager'
    }

    It 'dot-sources StartupManagerDialog.ps1 from Module/Regions/GUI.psm1' {
        $script:GuiRegionContent | Should -Match "Join-Path \`$Script:GuiExtractedRoot 'StartupManagerDialog\.ps1'"
    }
}

Describe 'Startup Manager dialog: function definitions' {
    It 'defines Show-GuiStartupManagerDialog' {
        $script:DialogContent | Should -Match 'function Show-GuiStartupManagerDialog'
    }

    It 'defines Get-GuiStartupManagerEntries for the shared flat renderer' {
        $script:DialogContent | Should -Match 'function Get-GuiStartupManagerEntries'
    }

    It 'defines New-GuiStartupManagerEntryRow for the shared flat renderer' {
        $script:DialogContent | Should -Match 'function New-GuiStartupManagerEntryRow'
    }

    It 'defines Add-GuiStartupManagerRowsToPanel for the shared flat renderer' {
        $script:DialogContent | Should -Match 'function Add-GuiStartupManagerRowsToPanel'
    }

    It 'defines New-GuiStartupManagerTabContent for the Customizations tab' {
        $script:DialogContent | Should -Match 'function New-GuiStartupManagerTabContent'
    }

    It 'keeps Startup Manager as a Customizations action card that opens the popup dialog' {
        $script:DialogContent | Should -Match 'Builds the Customizations-tab content surface for startup entries'
        $script:DialogContent | Should -Match 'function Invoke-GuiCustomizationsStartupManagerAction'
        $script:DialogContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiStartupManagerDialog'"
        $script:DialogContent | Should -Match 'Invoke-GuiCustomizationsStartupManagerAction'
    }

    It 'short-circuits in headless harness when $Script:CurrentTheme is unset' {
        $script:DialogContent | Should -Match 'if \(-not \$Script:CurrentTheme\)'
        $script:DialogContent | Should -Match 'return @\{ Cancelled = \$true; Changes = @\(\) \}'
    }

    It 'enumerates entries via the shared helper' {
        $script:DialogContent | Should -Match '\$entries = @\(Get-GuiStartupManagerEntries\)'
    }

    It 'wraps the enumerator in try/catch routed through Write-SwallowedException' {
        $script:DialogContent | Should -Match "Source 'StartupManagerDialog\.Enumerate'"
    }

    It 'binds per-row checkbox Click to Set-BaselineStartupEntryEnabled with Enable / Disable parameter sets' {
        $script:DialogContent | Should -Match 'Set-BaselineStartupEntryEnabled -EntryId .*-Enable'
        $script:DialogContent | Should -Match 'Set-BaselineStartupEntryEnabled -EntryId .*-Disable'
    }

    It 'snaps the checkbox back when Set-BaselineStartupEntryEnabled returns false (UI must not lie about state)' {
        $script:DialogContent | Should -Match 'if \(-not \$ok\)'
        $script:DialogContent | Should -Match '\$cbRef\.IsChecked = -not \$desired'
    }

    It 'disables RunOnce / no-ApprovedKey rows so Task Manager-style toggle never silently fails' {
        $script:DialogContent | Should -Match '\$isToggleable = \(-not \[bool\]\$entry\.IsRunOnce\) -and \(-not \[string\]::IsNullOrWhiteSpace\(\[string\]\$entry\.ApprovedKey\)\)'
        $script:DialogContent | Should -Match '\$cb\.IsEnabled = \$false'
    }

    It 'records each successful toggle in the Changes list so callers can summarize the session' {
        $script:DialogContent | Should -Match '\$changeListRef\.Add\(\[pscustomobject\]@\{'
        $script:DialogContent | Should -Match 'EntryId = \[string\]\$entryRef\.EntryId'
        $script:DialogContent | Should -Match 'Enabled = \$desired'
    }

    It 'renders a flat list instead of grouping rows by Source' {
        $script:DialogContent | Should -Not -Match 'Group-Object -Property Source'
    }
}

Describe 'Startup Manager dialog: Tools menu removal' {
    It 'removes the legacy Tools click handler' {
        $script:ActionHandlersContent | Should -Not -Match 'MenuToolsStartupManager'
    }
}
