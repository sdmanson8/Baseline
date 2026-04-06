Set-StrictMode -Version Latest

BeforeAll {
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $stateTransitionPath = Join-Path $PSScriptRoot '../../Module/GUI/StateTransitions.ps1'
    $gameModePath = Join-Path $PSScriptRoot '../../Module/GUI/GameModeUI.ps1'

    $script:GuiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
    $script:StateTransitionContent = Get-Content -LiteralPath $stateTransitionPath -Raw -Encoding UTF8
    $script:GameModeContent = Get-Content -LiteralPath $gameModePath -Raw -Encoding UTF8
}

Describe 'Focused GUI rebuilds' {
    It 'keeps idle tab prebuild available but makes it opt-in per rebuild' {
        $script:GuiContent | Should -Match 'function Build-TabContent'
        $script:GuiContent | Should -Match '\[switch\]\$SkipIdlePrebuild'
        $script:GuiContent | Should -Match 'if \(-not \$SkipIdlePrebuild -and \$PrimaryTabs -and \$PrimaryTabs\.Dispatcher\)'
        $script:GuiContent | Should -Match '\[System\.Windows\.Threading\.DispatcherPriority\]::ApplicationIdle'
    }

    It 'threads the focused rebuild flag through the current-tab refresh path' {
        $script:GuiContent | Should -Match 'function Update-CurrentTabContent'
        $script:GuiContent | Should -Match '& \$buildTabContentScript -PrimaryTab \$targetTab -SkipIdlePrebuild:\$SkipIdlePrebuild'
        $script:GuiContent | Should -Match '\$skipIdlePrebuild = \[bool\]\$Script:SkipIdlePrebuildOnNextPrimaryTabSelection'
        $script:GuiContent | Should -Match '& \$updateCurrentTabContentScript -SkipIdlePrebuild:\$skipIdlePrebuild'
    }

    It 'uses focused rebuilds for theme and shared mode transitions' {
        $script:GuiContent | Should -Match 'Build-TabContent -PrimaryTab \$Script:CurrentPrimaryTab -SkipIdlePrebuild'
        $script:StateTransitionContent | Should -Match '& \$Script:UpdateCurrentTabContentScript -SkipIdlePrebuild'
    }

    It 'uses focused rebuilds for game mode refreshes' {
        $script:GameModeContent | Should -Match '& \$Script:UpdateCurrentTabContentScript -SkipIdlePrebuild'
        $script:GameModeContent | Should -Match '& \$updateCurrentTabContentScript -SkipIdlePrebuild'
        $script:GameModeContent | Should -Match '\$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = \$true'
    }
}
