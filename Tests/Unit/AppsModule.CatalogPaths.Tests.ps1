Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/CatalogHelpers.ps1')
}

Describe 'Apps catalog path resolution' {
    BeforeEach {
        $script:ModuleRoot = Join-Path $TestDrive 'Module'
        $script:CatalogRoot = Join-Path $script:ModuleRoot 'Data\AppsCategory'
        New-Item -ItemType Directory -Path $script:CatalogRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ModuleRoot 'GUI\Show-TweakGUI') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:CatalogRoot 'Browsers.json') -Value '{"Entries":[]}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:CatalogRoot 'Documents.json') -Value '{"Entries":[]}' -Encoding UTF8
    }

    It 'finds shared app categories when the GUI base path is the GUI root' {
        $script:GuiModuleBasePath = Join-Path $script:ModuleRoot 'GUI'

        $categories = @(Get-AppsCatalogCategoryNames)

        $categories | Should -Contain 'Browsers'
        $categories | Should -Contain 'Documents'
    }

    It 'finds shared app category files when the GUI base path is a GUI module directory' {
        $script:GuiModuleBasePath = Join-Path $script:ModuleRoot 'GUI\Show-TweakGUI'

        $files = @(Get-AppsCatalogFilesForCategory -Category 'Documents')

        $files.Count | Should -Be 1
        $files[0].FullName | Should -Be (Join-Path $script:CatalogRoot 'Documents.json')
    }
}
