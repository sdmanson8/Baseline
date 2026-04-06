Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/ThemeManagement.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Write-GuiThemeFallbackWarning' {
    BeforeEach {
        $Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
    }

    It 'does nothing for empty message' {
        Write-GuiThemeFallbackWarning -Context 'Test' -Message ''
        $Script:GuiThemeFallbackWarnings.Count | Should -Be 0
    }

    It 'logs a warning once' {
        Write-GuiThemeFallbackWarning -Context 'Test' -Message 'Missing color' 3>$null
        $Script:GuiThemeFallbackWarnings.Count | Should -Be 1
    }

    It 'deduplicates identical warnings' {
        Write-GuiThemeFallbackWarning -Context 'Test' -Message 'Missing color' 3>$null
        Write-GuiThemeFallbackWarning -Context 'Test' -Message 'Missing color' 3>$null
        $Script:GuiThemeFallbackWarnings.Count | Should -Be 1
    }

    It 'allows different context+message combinations' {
        Write-GuiThemeFallbackWarning -Context 'A' -Message 'Missing' 3>$null
        Write-GuiThemeFallbackWarning -Context 'B' -Message 'Missing' 3>$null
        $Script:GuiThemeFallbackWarnings.Count | Should -Be 2
    }
}

Describe 'Get-GuiFallbackColor' {
    BeforeEach {
        $Script:DarkTheme = @{ AccentBlue = '#89B4FA' }
    }

    It 'returns the provided fallback color when non-empty' {
        Get-GuiFallbackColor -FallbackColor '#FF0000' | Should -Be '#FF0000'
    }

    It 'returns DarkTheme AccentBlue when no fallback provided' {
        Get-GuiFallbackColor -FallbackColor '' | Should -Be '#89B4FA'
    }

    It 'returns DarkTheme AccentBlue for null fallback' {
        Get-GuiFallbackColor -FallbackColor $null | Should -Be '#89B4FA'
    }

    It 'returns hardcoded default when DarkTheme is missing' {
        $Script:DarkTheme = $null
        $result = Get-GuiFallbackColor -FallbackColor ''
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Repair-GuiThemePalette' {
    BeforeEach {
        $Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
        $Script:DarkTheme = @{
            AccentBlue = '#89B4FA'
            TextPrimary = '#CDD6F4'
            TextSecondary = '#B6BED8'
            CardBg = '#272B3A'
            HeaderBg = '#181825'
            FocusRing = '#C9DEFF'
            TabHoverBg = '#3670B8'
            AccentHover = '#74C7EC'
            AccentPress = '#94E2D5'
        }
        $Script:LightTheme = @{
            AccentBlue = '#1550AA'
            TextPrimary = '#1A1C2E'
            TextSecondary = '#31384A'
            CardBg = '#FFFFFF'
            HeaderBg = '#D6DBE5'
            FocusRing = '#0D63E0'
            TabHoverBg = '#3670B8'
            AccentHover = '#1A60C4'
            AccentPress = '#104090'
        }
    }

    It 'returns the theme unchanged when all keys present' {
        $theme = @{
            AccentBlue = '#89B4FA'
            TextPrimary = '#CDD6F4'
            TextSecondary = '#B6BED8'
            CardBg = '#272B3A'
            HeaderBg = '#181825'
            FocusRing = '#C9DEFF'
            TabHoverBg = '#3670B8'
            AccentHover = '#74C7EC'
            AccentPress = '#94E2D5'
        }
        $result = Repair-GuiThemePalette -Theme $theme -ThemeName 'Dark' 3>$null
        $result.AccentBlue | Should -Be '#89B4FA'
    }

    It 'fills missing keys from the opposite theme' {
        $theme = @{ AccentBlue = '#3B82F6' }
        $result = Repair-GuiThemePalette -Theme $theme -ThemeName 'Dark' 3>$null
        $result | Should -BeOfType [hashtable]
    }

    It 'does not crash on empty theme' {
        $result = Repair-GuiThemePalette -Theme @{} -ThemeName 'Dark' 3>$null
        $result | Should -BeOfType [hashtable]
    }
}
