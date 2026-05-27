Set-StrictMode -Version Latest

BeforeAll {
    $utilityPath = Join-Path $PSScriptRoot '../../Module/GUICommon/Utilities.ps1'
    $layoutPath = Join-Path $PSScriptRoot '../../Module/GUICommon/Layout.ps1'
    $asts = @(
        [System.Management.Automation.Language.Parser]::ParseFile($utilityPath, [ref]$null, [ref]$null)
        [System.Management.Automation.Language.Parser]::ParseFile($layoutPath, [ref]$null, [ref]$null)
    )
    $functions = foreach ($ast in $asts) {
        $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    }

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Test-GuiCommonUniqueAdd', 'Write-GuiCommonWarning', 'Get-GuiCommonSafeFontSize')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:FunctionTextByName = @{}
    foreach ($fn in $functions) {
        $script:FunctionTextByName[$fn.Name] = $fn.Extent.Text
    }
}

Describe 'GUICommon warning dedupe' {
    BeforeEach {
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:GuiCommonWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:GuiCommonWarningsSyncRoot = [object]::new()
        $script:GuiFontSizeWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:GuiFontSizeWarningsSyncRoot = [object]::new()

        function LogWarning {
            param([string]$Message)
            [void]$script:warningMessages.Add($Message)
        }
    }

    AfterEach {
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'guards unique warning insertion with Monitor.Enter and Monitor.Exit' {
        $script:FunctionTextByName['Test-GuiCommonUniqueAdd'] | Should -Match '\[System\.Threading\.Monitor\]::Enter'
        $script:FunctionTextByName['Test-GuiCommonUniqueAdd'] | Should -Match '\[System\.Threading\.Monitor\]::Exit'
    }

    It 'logs an invalid font-size warning only once for repeated calls' {
        $layout = @{ FontSizeLabel = 'invalid' }

        $first = Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11 -Layout $layout
        $second = Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11 -Layout $layout

        $first | Should -Be 11
        $second | Should -Be 11
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match "Invalid GUI font size for 'FontSizeLabel'"
    }
}
