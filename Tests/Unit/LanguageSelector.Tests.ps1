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
        $script:GuiContent | Should -Match '<ToggleButton Name="BtnLanguage"[^>]*Content="Language"'
        $script:GuiContent | Should -Match '<Popup Name="LanguagePopup"[^>]*IsOpen="\{Binding IsChecked, ElementName=BtnLanguage, Mode=TwoWay\}"'
        $script:GuiContent | Should -Match 'Set-ButtonChrome -Button \$BtnLanguage -Variant ''Subtle'' -Compact -Muted'
        $script:GuiContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLanguage\s+-IconName ''Language''\s+-Text ''Language'''
    }

    It 'opens the language popup through popup state instead of manual click toggling' {
        $script:GuiContent | Should -Match 'Register-GuiEventHandler -Source \$LanguagePopup -EventName ''Opened'''
        $script:GuiContent | Should -Not -Match 'Register-GuiEventHandler -Source \$BtnLanguage -EventName ''Click'''
    }

    It 'wires popup language options to select on press via applyLanguageChange' {
        $script:GuiContent | Should -Match '\$langBtn\.ClickMode = \[System\.Windows\.Controls\.ClickMode\]::Press'
        $script:GuiContent | Should -Match 'function Set-SelectedGuiLanguage'
        $script:GuiContent | Should -Match '\$setSelectedGuiLanguageCommand = \$\{function:Set-SelectedGuiLanguage\}'
        $script:GuiContent | Should -Match '& \$setSelectedGuiLanguageCommand \(\[string\]\$buttonSender\.Tag\)'
        $script:GuiContent | Should -Match 'if \(\$BtnLanguage\) \{ \$BtnLanguage\.IsChecked = \$false \}'
    }
}
