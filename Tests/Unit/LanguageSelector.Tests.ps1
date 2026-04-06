Set-StrictMode -Version Latest

BeforeAll {
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:GuiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

Describe 'Language selector wiring' {
    It 'uses the shared localization directory resolver' {
        $script:GuiContent | Should -Match '\$Script:GuiLocalizationDirectoryPath\s*=\s*Resolve-BaselineLocalizationDirectory -BasePath \$Script:GuiModuleBasePath'
        $script:GuiContent | Should -Match '\$locDirInit\s*=\s*\$Script:GuiLocalizationDirectoryPath'
        $script:GuiContent | Should -Match '\$locDir\s*=\s*\$Script:GuiLocalizationDirectoryPath'
    }

    It 'renders the language button through the shared icon button pipeline' {
        $script:GuiContent | Should -Match '<Button Name="BtnLanguage"[^>]*Content="Language"'
        $script:GuiContent | Should -Match "Set-ButtonChrome -Button \$BtnLanguage -Variant 'Subtle' -Compact -Muted"
        $script:GuiContent | Should -Match "Set-GuiButtonIconContent -Button \$BtnLanguage\s+-IconName 'Language'\s+-Text 'Language'"
    }
}
