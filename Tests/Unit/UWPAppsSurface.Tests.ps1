Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1'
    $script:UwpAppsContent = Get-BaselineTestSourceText -Path $filePath
}

Describe 'UWP apps picker surface' {
    It 'repairs picker theme values before forcing an opaque picker background in both branches' {
        $script:UwpAppsContent | Should -Match 'function Set-UWPAppsPickerSurface'
        $script:UwpAppsContent | Should -Match 'function Resolve-UWPAppsPickerUseDarkMode'
        $script:UwpAppsContent | Should -Match 'BASELINE_USE_DARK_MODE'
        $script:UwpAppsContent | Should -Match 'return \$true'
        $script:UwpAppsContent | Should -Match '\[object\]\s*\$UseDarkMode'
        $script:UwpAppsContent | Should -Match 'GUICommon\\Get-GuiBooleanValue -Value \$UseDarkMode -Default \(Resolve-UWPAppsPickerUseDarkMode\)'
        $script:UwpAppsContent | Should -Match '\$setUWPAppsPickerSurface = \$\{function:Set-UWPAppsPickerSurface\}'
        ([regex]::Matches($script:UwpAppsContent, '& \$setUWPAppsPickerSurface -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer')).Count | Should -Be 2
        $script:UwpAppsContent | Should -Match '& \$repairGuiThemePalette -Theme \$surfaceTheme -ThemeName'
        $script:UwpAppsContent | Should -Match '\$defaultThemeColors = if \(\$resolvedUseDarkMode\)'
        $script:UwpAppsContent | Should -Match '\$getThemeColor = \{'
        $script:UwpAppsContent | Should -Match '\[void\]\$BrushConverter\.ConvertFromString\(\$value\)'
        $script:UwpAppsContent | Should -Match '\$windowBg = & \$getThemeColor -ColorName ''WindowBg'' -DefaultColor'
        $script:UwpAppsContent | Should -Match '\$panelBg = & \$getThemeColor -ColorName ''PanelBg'' -DefaultColor'
        $script:UwpAppsContent | Should -Match '\$Window\.Background = \$BrushConverter\.ConvertFromString\(\$windowBg\)'
        $script:UwpAppsContent | Should -Match '\$RootBorder\.Background = \$BrushConverter\.ConvertFromString\(\$windowBg\)'
        $script:UwpAppsContent | Should -Match '\$PanelContainer\.Background = \$BrushConverter\.ConvertFromString\(\$panelBg\)'
    }

    It 'does not pre-apply raw current-theme brush strings before the shared helpers run' {
        $script:UwpAppsContent | Should -Not -Match '\$RootBorder\.Background = \$bc\.ConvertFromString\(\$currentTheme\.WindowBg\)'
        $script:UwpAppsContent | Should -Not -Match '\$RootBorder\.BorderBrush = \$bc\.ConvertFromString\(\$currentTheme\.BorderColor\)'
        $script:UwpAppsContent | Should -Not -Match '\$Form\.Foreground = \$bc\.ConvertFromString\(\$currentTheme\.TextPrimary\)'
    }

    It 'routes popup actions through the shared async runner' {
        ([regex]::Matches($script:UwpAppsContent, 'GUICommon\\Start-GuiPopupCommandAsync -Window \$Form -ModulePath \$modulePath -AdditionalModulePaths @\(\$guiCommonPath\) -CommandName ''UWPApps'' -CommandParameters \$commandParameters')).Count | Should -Be 2
        $script:UwpAppsContent | Should -Match '\$Form\.PSObject\.Properties\[''GuiPopupOperationResult''\]'
        $script:UwpAppsContent | Should -Match '\$Form\.GuiPopupOperationResult'
    }

    It 'uses the exported common themed dialog for manual Store follow-up' {
        $script:UwpAppsContent | Should -Match 'GUICommon\\Show-GuiCommonThemedDialog @dialogParams'
        $script:UwpAppsContent | Should -Not -Match 'GUICommon\\Show-ThemedDialog'
        $script:UwpAppsContent | Should -Match '\$currentTheme = Get-UWPAppsPickerTheme'
        $script:UwpAppsContent | Should -Match '\$isDarkMode = Resolve-UWPAppsPickerUseDarkMode'
    }

    It 'loads all WPF assemblies needed by the picker explicitly' {
        ([regex]::Matches($script:UwpAppsContent, 'Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop')).Count | Should -Be 2
    }

    It 'uses normal text fonts for app names instead of inheriting the icon font' {
        $script:UwpAppsContent | Should -Not -Match 'FontFamily="FluentSystemIcons" FontSize="12" ShowInTaskbar="True"'
        ([regex]::Matches($script:UwpAppsContent, 'FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"')).Count | Should -Be 2
        ([regex]::Matches($script:UwpAppsContent, '\$TextBlock\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)')).Count | Should -BeGreaterOrEqual 2
        $script:UwpAppsContent | Should -Match '\$TextBlock\.Foreground = \$Form\.Foreground'
    }

    It 'loads bundled WinRT dependencies before using Appx cmdlets' {
        $script:UwpAppsContent | Should -Match '\[void\]\(Initialize-BaselineWinRtRuntimeDependencies\)'
    }
}
