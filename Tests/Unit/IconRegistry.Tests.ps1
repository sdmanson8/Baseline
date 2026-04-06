Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/IconRegistry.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Get-GuiIconFontPath', 'Get-GuiIconFontFamilyName', 'Get-GuiIconGlyph')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:ExpectedFontPath = Join-Path $script:RepoRoot 'Module/Fonts/FluentSystemIcons.ttf'
}

Describe 'Get-GuiIconFontPath' {
    It 'finds the icon font from the GUI region module root' {
        $moduleRoot = Join-Path $script:RepoRoot 'Module/Regions'

        Get-GuiIconFontPath -ModuleRoot $moduleRoot | Should -Be $script:ExpectedFontPath
    }

    It 'finds the icon font from the extracted GUI script root' {
        $moduleRoot = Join-Path $script:RepoRoot 'Module/GUI'

        Get-GuiIconFontPath -ModuleRoot $moduleRoot | Should -Be $script:ExpectedFontPath
    }
}

Describe 'Get-GuiIconFontFamilyName' {
    It 'matches the bundled Fluent icon font family name' {
        Get-GuiIconFontFamilyName | Should -Be 'Fluent System Icons'
    }
}

Describe 'Get-GuiIconGlyph' {
    It 'maps the language selector to the Fluent globe glyph' {
        [int](Get-GuiIconGlyph -Name 'Language') | Should -Be 0xE774
    }
}
