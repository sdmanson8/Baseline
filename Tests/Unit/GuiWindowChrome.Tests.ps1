Set-StrictMode -Version Latest

BeforeAll {
    $guiCommonPath = Join-Path $PSScriptRoot '../../Module/GUICommon.psm1'
    $styleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $dialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $executionSummaryDialogPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionSummaryDialog.ps1'
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'

    $guiCommonContent = Get-Content -LiteralPath $guiCommonPath -Raw -Encoding UTF8
    $styleManagementContent = Get-Content -LiteralPath $styleManagementPath -Raw -Encoding UTF8
    $dialogHelpersContent = Get-Content -LiteralPath $dialogHelpersPath -Raw -Encoding UTF8
    $executionSummaryDialogContent = Get-Content -LiteralPath $executionSummaryDialogPath -Raw -Encoding UTF8
    $guiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

Describe 'GUI window chrome theming' {
    It 'defines and exports a shared window chrome theming helper' {
        $guiCommonContent | Should -Match 'function Set-GuiWindowChromeTheme'
        $guiCommonContent | Should -Match 'DwmSetWindowAttribute'
        $guiCommonContent | Should -Match "'Set-GuiWindowChromeTheme'"
    }

    It 'threads the active dark mode state through shared dialog wrappers' {
        $styleManagementContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
        $dialogHelpersContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
        $executionSummaryDialogContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'applies native window chrome theming when the main theme changes' {
        $guiContent | Should -Match 'GUICommon\\Set-GuiWindowChromeTheme -Window \$Form -UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'restyles custom caption buttons from the active theme' {
        $styleManagementContent | Should -Match 'function Set-WindowCaptionButtonStyle'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnMinimize'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnMaximize'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnClose -Variant ''Close'''
    }

    It 'applies native window chrome theming to custom XAML dialogs' {
        $dialogHelpersContent | Should -Match 'GUICommon\\Set-GuiWindowChromeTheme -Window \$dlg -UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'marks Close actions as cancel semantics in shared dialogs' {
        $guiCommonContent | Should -Match '\$btn\.IsCancel = \$true'
        $dialogHelpersContent | Should -Match '\$btnClose\.IsCancel = \$true'
    }
}
