Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DialogPath = Join-Path $script:RepoRoot 'Module/GUI/RemovalPersistenceDialog.ps1'
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

Describe 'Removal Persistence dialog: menu wiring' {
    It 'declares MenuToolsRemovalPersistence in the Tools menu' {
        $script:XamlContent | Should -Match 'Name="MenuToolsRemovalPersistence"'
        $idxItem = $script:XamlContent.IndexOf('Name="MenuToolsRemovalPersistence"')
        $idxToolsMenu = $script:XamlContent.IndexOf('Name="MenuTools"')
        $idxItem | Should -BeGreaterThan $idxToolsMenu
    }

    It 'wires FindName + $Script: assignment in WindowSetup.ps1' {
        $script:WindowSetupContent | Should -Match '\$MenuToolsRemovalPersistence = \$Form\.FindName\("MenuToolsRemovalPersistence"\)'
        $script:WindowSetupContent | Should -Match '\$Script:MenuToolsRemovalPersistence = \$MenuToolsRemovalPersistence'
    }

    It 'dot-sources RemovalPersistenceDialog.ps1 from Module/Regions/GUI.psm1' {
        $script:GuiRegionContent | Should -Match "Join-Path \`$Script:GuiExtractedRoot 'RemovalPersistenceDialog\.ps1'"
    }
}

Describe 'Removal Persistence dialog: function definition' {
    It 'defines Show-GuiRemovalPersistenceDialog' {
        $script:DialogContent | Should -Match 'function Show-GuiRemovalPersistenceDialog'
    }

    It 'short-circuits in headless harness when $Script:CurrentTheme is unset' {
        $script:DialogContent | Should -Match 'if \(-not \$Script:CurrentTheme\)'
        $script:DialogContent | Should -Match 'return @\{ Cancelled = \$true; Removed = @\(\) \}'
    }

    It 'enumerates entries via Get-BaselineRemovalPersistenceTasks behind a Get-Command guard' {
        $script:DialogContent | Should -Match "Get-Command -Name 'Get-BaselineRemovalPersistenceTasks'"
        $script:DialogContent | Should -Match '\$entries = @\(Get-BaselineRemovalPersistenceTasks\)'
    }

    It 'wraps the enumerator in try/catch routed through Write-SwallowedException' {
        $script:DialogContent | Should -Match "Source 'RemovalPersistenceDialog\.Enumerate'"
    }

    It 'binds the per-row Remove button to Unregister-BaselineRemovalPersistenceTask -RemoveScript' {
        $script:DialogContent | Should -Match 'Unregister-BaselineRemovalPersistenceTask -Name .*-RemoveScript'
    }

    It 'records every successful removal in the Removed list so the caller can summarize the session' {
        $script:DialogContent | Should -Match '\$removedList\.Add\(\[string\]\$entryRef\.TaskName\)'
    }

    It 'visually marks the row as removed (Opacity 0.5) without rebuilding the whole panel' {
        $script:DialogContent | Should -Match '\$rowBorderRef\.Opacity = 0\.5'
    }

    It 're-enables the Remove button on a failed unregister so the user can retry' {
        $script:DialogContent | Should -Match 'if \(-not \$ok\)'
        $script:DialogContent | Should -Match '\$btnRef\.IsEnabled = \$true'
    }

    It 'flags missing script files so the user knows the task will fail on next trigger' {
        $script:DialogContent | Should -Match 'if \(-not \[bool\]\$entry\.ScriptExists\)'
    }
}

Describe 'Removal Persistence dialog: click handler integration' {
    It 'registers a Click handler on MenuToolsRemovalPersistence in ActionHandlers.ps1' {
        $script:ActionHandlersContent | Should -Match 'if \(\$MenuToolsRemovalPersistence\)'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuToolsRemovalPersistence -EventName ''Click'''
    }

    It 'invokes Show-GuiRemovalPersistenceDialog from the Click handler' {
        $script:ActionHandlersContent | Should -Match 'Show-GuiRemovalPersistenceDialog'
    }

    It 'resolves the dialog through the GUI runtime command surface' {
        $idxIf = $script:ActionHandlersContent.IndexOf('if ($MenuToolsRemovalPersistence)')
        $tail = $script:ActionHandlersContent.Substring($idxIf)
        $tail | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiRemovalPersistenceDialog' -CommandType 'Function'"
        $tail | Should -Match 'Removal Persistence dialog command is not available\.'
    }

    It 'uses the run-in-progress gate so the dialog cannot be opened mid-apply' {
        $idxIf = $script:ActionHandlersContent.IndexOf('if ($MenuToolsRemovalPersistence)')
        $tail = $script:ActionHandlersContent.Substring($idxIf)
        $tail | Should -Match 'if \(& \$testGuiRunInProgressCapture\) \{ return \}'
    }
}
