Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $actionPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $actionSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:ActionContent = Get-BaselineTestSourceText -Path @(
        $actionPath
        (Join-Path $actionSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $actionSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $actionSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $actionSplitRoot 'MenuHandlers.ps1')
    )
}

Describe 'Preview run handoff' {
    It 'starts execution when the preview dialog returns the run label' {
        $script:ActionContent | Should -Match 'Register-GuiEventHandler -Source \$BtnPreviewRun -EventName ''Click'''
        $script:ActionContent | Should -Match '\$previewResult = & \$showSelectedTweakPreviewCommand -SelectedTweaks \$tweakList -AllowApply'
        $script:ActionContent | Should -Match 'if \(\$previewResult -and \$previewResult -eq \(& \$getUxRunActionLabelCommand\)\)'
        $script:ActionContent | Should -Match '& \$startGuiExecutionRunCommand -TweakList \$tweakList -Mode ''Run'' -ExecutionTitle'
    }
}
