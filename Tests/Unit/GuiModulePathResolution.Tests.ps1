Set-StrictMode -Version Latest

BeforeAll {
    $script:ModulePathResolutionPath = Join-Path $PSScriptRoot '../../Module/GUI/Show-TweakGUI/ModulePathResolution.ps1'
}

Describe 'GUI module base path resolution' {
    BeforeEach {
        $script:ModuleRoot = Join-Path $TestDrive 'Module'
        New-Item -ItemType Directory -Path (Join-Path $script:ModuleRoot 'GUI\Show-TweakGUI') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ModuleRoot 'Regions') -Force | Out-Null
    }

    It 'normalizes an extracted GUI root to the Module root' {
        $script:GuiModuleBasePath = Join-Path $script:ModuleRoot 'GUI'

        . $script:ModulePathResolutionPath

        $script:GuiModuleBasePath | Should -Be $script:ModuleRoot
    }

    It 'normalizes an extracted GUI split directory to the Module root' {
        $script:GuiModuleBasePath = Join-Path $script:ModuleRoot 'GUI\Show-TweakGUI'

        . $script:ModulePathResolutionPath

        $script:GuiModuleBasePath | Should -Be $script:ModuleRoot
    }

    It 'keeps the existing Regions normalization' {
        $script:GuiModuleBasePath = Join-Path $script:ModuleRoot 'Regions'

        . $script:ModulePathResolutionPath

        $script:GuiModuleBasePath | Should -Be $script:ModuleRoot
    }
}
