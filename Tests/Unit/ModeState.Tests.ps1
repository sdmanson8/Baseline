Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $modeStatePath = Join-Path $PSScriptRoot '../../Module/GUI/ModeState.ps1'
    $script:ModeStateContent = Get-BaselineTestSourceText -Path $modeStatePath
}

Describe 'Mode state' {
    It 'persists Safe and Expert startup-mode changes' {
        $script:ModeStateContent | Should -Match 'function Save-GuiDefaultStartupModePreference'
        $script:ModeStateContent | Should -Match 'Set-BaselineUserPreference -Key ''DefaultStartupMode'' -Value \$Mode'
        $script:ModeStateContent | Should -Match "Save-GuiDefaultStartupModePreference -Mode 'Safe'"
        $script:ModeStateContent | Should -Match 'Save-GuiDefaultStartupModePreference -Mode \$nextStartupMode'
    }

    It 'routes design-mode preference writes through Write-SwallowedException' {
        $script:ModeStateContent | Should -Match "ModeState\.Set-DesignModeState\.SavePreference"
    }

    It 'keeps Safe and Expert mode state independent of the removed header checkbox' {
        $script:ModeStateContent | Should -Match "Set-GuiMode -ViewMode"
        $script:ModeStateContent | Should -Match "Save-GuiDefaultStartupModePreference -Mode"
        $script:ModeStateContent | Should -Not -Match '\$ChkSafeMode'
        $script:ModeStateContent | Should -Not -Match 'GuiChkSafeMode'
    }
}
