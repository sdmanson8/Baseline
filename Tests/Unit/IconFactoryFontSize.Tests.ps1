Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $iconFactoryPath = Join-Path $PSScriptRoot '../../Module/GUI/IconFactory.ps1'
    $script:IconFactoryContent = Get-BaselineTestSourceText -Path $iconFactoryPath
}

Describe 'Icon factory font sizing' {
    It 'guards shared icon text helpers against non-positive font sizes' {
        $script:IconFactoryContent | Should -Match 'function Test-GuiPositiveFontSize'
        $script:IconFactoryContent | Should -Match 'if \(Test-GuiPositiveFontSize -Value \$Size\)'
        $script:IconFactoryContent | Should -Match 'if \(Test-GuiPositiveFontSize -Value \$TextFontSize\)'
        $script:IconFactoryContent | Should -Match '\$resolvedTextFontSize = if \(Test-GuiPositiveFontSize -Value \$TextFontSize\)'
        $script:IconFactoryContent | Should -Match 'elseif \(Test-GuiPositiveFontSize -Value \$Button\.FontSize\)'
    }
}
