Set-StrictMode -Version Latest

BeforeAll {
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $actionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $errorHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/ErrorHandling.Helpers.ps1'

    $guiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
    $actionHandlersContent = Get-Content -LiteralPath $actionHandlersPath -Raw -Encoding UTF8
    $errorHelpersContent = Get-Content -LiteralPath $errorHelpersPath -Raw -Encoding UTF8
}

Describe 'First-run startup command wiring' {
        It 'resolves first-run GUI commands before startup handlers run' {
                $guiContent | Should -Match "Get-Item function:Show-ThemedDialog"
                $guiContent | Should -Match "Get-Item function:Show-FirstRunWelcomeDialog"
                $guiContent | Should -Match "Get-UxFirstRunWelcomeMessage"
                $guiContent | Should -Match "Get-Command 'Show-HelpDialog'"
                $guiContent | Should -Match "Get-Command 'Set-GuiPresetSelection'"
                $guiContent | Should -Match "Get-Command 'Set-GuiStatusText'"
                $guiContent | Should -Match "Get-Command 'Get-UxRecommendedPresetName'"
                $guiContent | Should -Match "Get-Command 'Get-GuiFirstRunWelcomeMarkerPath'"
    }

        It 'uses the same runtime-command pattern for the New Start Here action' {
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-ThemedDialog'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-HelpDialog'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Set-GuiPresetSelection'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxRecommendedPresetName'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxPresetLoadedStatusText'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxFirstRunPrimaryActionLabel'"
		$actionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Get-UxFirstRunWelcomeMessage'"
        $actionHandlersContent | Should -Not -Match '\$welcomeMessage\s*=\s*Get-UxFirstRunWelcomeMessage'
        $actionHandlersContent | Should -Not -Match '\$choice\s*=\s*Show-ThemedDialog\s+-Title\s+''Welcome to Baseline'''
        $actionHandlersContent | Should -Match "Show-HelpDialog not found\."
    }

    It 'maps a missing help dialog function to the startup-command error code' {
        $errorHelpersContent | Should -Match "'\*Show-HelpDialog not found\*' \{ return 'GUI-STARTUP-004' \}"
    }
}
