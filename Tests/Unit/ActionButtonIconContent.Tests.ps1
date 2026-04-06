Set-StrictMode -Version Latest

BeforeAll {
    $stylePath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $actionPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $executionPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration.ps1'

    $script:StyleContent = Get-Content -LiteralPath $stylePath -Raw -Encoding UTF8
    $script:ActionContent = Get-Content -LiteralPath $actionPath -Raw -Encoding UTF8
    $script:ExecutionContent = Get-Content -LiteralPath $executionPath -Raw -Encoding UTF8
}

Describe 'Action button icon content' {
    It 'keeps localized toolbar and footer buttons on the shared icon pipeline' {
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnDefaults -IconName ''RestoreDefaults'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLog -IconName ''OpenLog'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLanguage -IconName ''Language'''
        $script:StyleContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnClearSearch -IconName ''Clear'''
    }

    It 'preserves Preview Run and Run Tweaks icons during UX text refreshes' {
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnRun -IconName ''RunTweaks'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnPreviewRun -IconName ''PreviewRun'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnStartHere -IconName ''QuickStart'''
        $script:ActionContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnHelp -IconName ''Help'''
    }

    It 'restores normal action labels through Sync-UxActionButtonText after execution view resets' {
        $script:ExecutionContent | Should -Match "Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue"
        $script:ExecutionContent | Should -Match 'Sync-UxActionButtonText'
    }
}
