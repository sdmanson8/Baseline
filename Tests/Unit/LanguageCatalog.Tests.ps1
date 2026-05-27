Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Module/GUI/LanguageCatalog.ps1')
}

Describe 'GUI language catalog' {
    It 'returns individual language entries that can be searched by English name' {
        $entries = @(Get-GuiLanguageEntries -LocalizationDirectory (Join-Path $PSScriptRoot '../../Localizations'))

        $entries.Count | Should -BeGreaterThan 1
        $matches = @($entries | Where-Object {
            ([string]$_.SearchIndex).IndexOf('spanish', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })

        $matches.Count | Should -BeGreaterThan 0
        @($matches.Code) | Should -Contain 'es'
    }
}
