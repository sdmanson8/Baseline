Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $xamlPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $buildPrimaryTabsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildPrimaryTabs.ps1'
    $buildTweakControlsPath = Join-Path $PSScriptRoot '../../Module/GUI/BuildTweakControls.ps1'
    $styleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $windowSetupPath = Join-Path $PSScriptRoot '../../Module/GUI/WindowSetup.ps1'
    $script:GuiContent = @(
        Get-BaselineTestSourceText -Path $xamlPath
        Get-BaselineTestSourceText -Path $guiPath
        Get-BaselineTestSourceText -Path $buildPrimaryTabsPath
        Get-BaselineTestSourceText -Path $buildTweakControlsPath
        Get-BaselineTestSourceText -Path $styleManagementPath
        Get-BaselineTestSourceText -Path $windowSetupPath
    ) -join "`n"
}

Describe 'Language selector wiring' {
    It 'uses the shared localization directory resolver' {
        $script:GuiContent | Should -Match '\$Script:GuiLocalizationDirectoryPath\s*=\s*Resolve-BaselineLocalizationDirectory -BasePath \$Script:GuiModuleBasePath'
        $script:GuiContent | Should -Match '\$locDirInit\s*=\s*\$Script:GuiLocalizationDirectoryPath'
        $script:GuiContent | Should -Match '\$locDir\s*=\s*\$Script:GuiLocalizationDirectoryPath'
    }

    It 'renders the language button through the shared icon button pipeline' {
        $script:GuiContent | Should -Match '<ToggleButton Name="BtnLanguage"[^>]*Content=""'
        $script:GuiContent | Should -Match '<Popup Name="LanguagePopup"[^>]*IsOpen="\{Binding IsChecked, ElementName=BtnLanguage, Mode=TwoWay\}"'
        $script:GuiContent | Should -Match '<Popup Name="LanguagePopup"[^>]*StaysOpen="True"'
        $script:GuiContent | Should -Match 'Set-ButtonChrome -Button \$BtnLanguage -Variant ''Subtle'' -Compact -Muted'
        $script:GuiContent | Should -Match 'Set-GuiButtonIconContent -Button \$BtnLanguage\s+-IconName ''Language''\s+-Text \(Get-UxLocalizedString -Key ''GuiBtnLanguage'' -Fallback ''Language''\)'
    }

    It 'opens the language popup through popup state instead of manual click toggling' {
        $script:GuiContent | Should -Match 'Register-GuiEventHandler -Source \$LanguagePopup -EventName ''Opened'''
        $script:GuiContent | Should -Not -Match 'Register-GuiEventHandler -Source \$BtnLanguage -EventName ''Click'''
    }

    It 'refreshes language results directly from typed search text' {
        $script:GuiContent | Should -Match 'Register-GuiEventHandler -Source \$TxtLanguageSearch -EventName ''TextChanged'''
        $script:GuiContent | Should -Match '\$renderLanguageList -FilterText \(\[string\]\$TxtLanguageSearch\.Text\)'
        $script:GuiContent | Should -Match '\$searchIndex\.IndexOf\(\$normalizedFilter, \[System\.StringComparison\]::OrdinalIgnoreCase\) -ge 0'
        $script:GuiContent | Should -Match '<Popup Name="LanguagePopup"[^>]*StaysOpen="True"'
        $script:GuiContent | Should -Not -Match '\[string\]\$_\.SearchIndex -like "\*\$normalizedFilter\*"'
    }

    It 'wires popup language options to select on press via applyLanguageChange' {
        $script:GuiContent | Should -Match '\$langBtn\.ClickMode = \[System\.Windows\.Controls\.ClickMode\]::Press'
        $script:GuiContent | Should -Match 'function Set-SelectedGuiLanguage'
        $script:GuiContent | Should -Match '\$setSelectedGuiLanguageCommand = \$\{function:Set-SelectedGuiLanguage\}'
        $script:GuiContent | Should -Match '\$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name ''Get-UxLocalizedString'''
        $script:GuiContent | Should -Match '\$getUxBilingualLocalizedStringCapture = Get-GuiFunctionCapture -Name ''Get-UxBilingualLocalizedString'''
        $script:GuiContent | Should -Match '& \$getUxLocalizedStringCapture -Key ''GuiLanguageSearchNoResults'''
        $script:GuiContent | Should -Match '& \$getUxBilingualLocalizedStringCapture -Key ''GuiLogLanguageChanged'''
        $script:GuiContent | Should -Match '& \$setSelectedGuiLanguageCommand \(\[string\]\$buttonSender\.Tag\)'
        $script:GuiContent | Should -Match 'if \(\$BtnLanguage\) \{ \$BtnLanguage\.IsChecked = \$false \}'
    }
}
