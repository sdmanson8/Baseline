Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/SessionState.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @(
            'Resolve-GuiModePreference',
            'Get-GuiFirstRunWelcomeMarkerPath',
            'Test-GuiFirstRunWelcomePending',
            'Complete-GuiFirstRunWelcome'
        )) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Resolve-GuiModePreference' {
    It 'keeps Safe Mode active when Safe Mode is requested' {
        $result = Resolve-GuiModePreference -SafeMode $true -AdvancedMode $false

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }

    It 'keeps Expert Mode active when Expert Mode is requested' {
        $result = Resolve-GuiModePreference -SafeMode $false -AdvancedMode $true

        $result.SafeMode | Should -Be $false
        $result.AdvancedMode | Should -Be $true
    }

    It 'prefers Safe Mode when an old snapshot tries to restore both modes off' {
        $result = Resolve-GuiModePreference -SafeMode $false -AdvancedMode $false

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }

    It 'lets Safe Mode win if both flags are somehow true' {
        $result = Resolve-GuiModePreference -SafeMode $true -AdvancedMode $true

        $result.SafeMode | Should -Be $true
        $result.AdvancedMode | Should -Be $false
    }
}

Describe 'First-run welcome state' {
    BeforeEach {
        $script:TestGuiSettingsProfileDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-welcome-tests-{0}" -f ([guid]::NewGuid().ToString('N')))

        function Get-GuiSettingsProfileDirectory {
            param ([string]$AppName = 'Baseline')
            return $script:TestGuiSettingsProfileDirectory
        }

        function LogWarning {
            param ([string]$Message)
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestGuiSettingsProfileDirectory -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-GuiSettingsProfileDirectory -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'treats a missing welcome marker as pending' {
        Test-GuiFirstRunWelcomePending | Should -Be $true
    }

    It 'marks the welcome as completed after the first successful display' {
        $markerPath = Get-GuiFirstRunWelcomeMarkerPath

        Complete-GuiFirstRunWelcome | Should -Be $true
        (Test-Path -LiteralPath $markerPath) | Should -Be $true
        Test-GuiFirstRunWelcomePending | Should -Be $false
    }
}
