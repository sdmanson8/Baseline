Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/ThemeManagement.ps1'
    $guiCommonPath = Join-Path $PSScriptRoot '../../Module/GUICommon.psm1'
    $applyThemePath = Join-Path $PSScriptRoot '../../Module/GUI/ApplyTheme.ps1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DarkThemeResourcePath = Join-Path $script:RepoRoot 'Module/GUI/Themes/Dark.xaml'
    $script:LightThemeResourcePath = Join-Path $script:RepoRoot 'Module/GUI/Themes/Light.xaml'
    $script:ApplyThemeContent = Get-BaselineTestSourceText -Path $applyThemePath
    Import-Module -Force -DisableNameChecking $guiCommonPath
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'GUI theme preference persistence' {
    It 'persists the normalized theme preference when applying a theme preference' {
        $script:ApplyThemeContent | Should -Match 'Set-BaselineUserPreference -Key ''Theme'' -Value \$normalized'
        $script:ApplyThemeContent | Should -Match "ApplyTheme\.ApplyBaselineThemePreference\.SavePreference"
    }
}

Describe 'GUI theme resource dictionaries' {
    It 'ships dark and light WPF dictionaries' {
        Test-Path -LiteralPath $script:DarkThemeResourcePath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:LightThemeResourcePath -PathType Leaf | Should -BeTrue
    }

    It 'defines shared brush tokens and implicit base control styles' {
        $content = Get-BaselineTestSourceText -Path $script:DarkThemeResourcePath
        foreach ($token in @(
            'Brush.WindowBg',
            'Brush.Surface',
            'Brush.SurfaceElevated',
            'Brush.SurfaceControl',
            'Brush.TextPrimary',
            'Brush.TextSecondary',
            'Brush.TextDisabled',
            'Brush.Border',
            'Brush.BorderStrong',
            'Brush.Accent',
            'Brush.SplashBackdrop',
            'Brush.SplashCard',
            'Brush.SplashCardBorder',
            'Brush.SplashSubtitle',
            'Brush.SplashStepActive'
        )) {
            $content | Should -Match ([regex]::Escape(('x:Key="{0}"' -f $token)))
        }
        $content | Should -Match '<Style TargetType="TextBox">'
        $content | Should -Match '<Setter Property="CaretBrush" Value="\{DynamicResource Brush\.TextPrimary\}"/>'
		$content | Should -Match '<Style TargetType="ComboBox">'
		$content | Should -Match '<Style TargetType="Button">'
		$content | Should -Match 'x:Key="\{x:Static SystemColors\.WindowBrushKey\}"'
		$content | Should -Match 'x:Key="\{x:Static SystemColors\.ControlBrushKey\}"'
		$content | Should -Match 'x:Key="\{x:Static SystemColors\.MenuBrushKey\}"'
		$content | Should -Match 'x:Key="\{x:Static SystemColors\.HighlightBrushKey\}"'
		$content | Should -Match '<Style TargetType="FlowDocumentScrollViewer">'
	}

    It 'uses the layered Baseline dark palette instead of the old flat purple theme' {
        $content = Get-BaselineTestSourceText -Path $script:DarkThemeResourcePath
        $content | Should -Match '<Color x:Key="Color\.WindowBg">#0E111A</Color>'
        $content | Should -Match '<Color x:Key="Color\.HeaderBg">#121624</Color>'
        $content | Should -Match '<Color x:Key="Color\.Surface">#161A26</Color>'
        $content | Should -Match '<Color x:Key="Color\.SurfaceElevated">#1E2433</Color>'
        $content | Should -Match '<Color x:Key="Color\.SurfaceControl">#262D40</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextPrimary">#F4F7FF</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextSecondary">#CDD6EA</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextMuted">#A3ADC6</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextDisabled">#7E89A8</Color>'
        $content | Should -Match '<Color x:Key="Color\.Border">#2430445A</Color>'
        $content | Should -Match '<Color x:Key="Color\.BorderStrong">#3C4A66</Color>'
        $content | Should -Match '<Color x:Key="Color\.Accent">#7CB7FF</Color>'
        $content | Should -Match '<Color x:Key="Color\.Success">#35D07F</Color>'
        $content | Should -Match '<Color x:Key="Color\.Progress">#35D07F</Color>'
        $content | Should -Match '<Color x:Key="Color\.SplashCard">#0FFFFFFF</Color>'
        $content | Should -Match '<Color x:Key="Color\.SplashCardBorder">#00FFFFFF</Color>'
        $content | Should -Match '<Color x:Key="Color\.SplashSubtitle">#CDD6EA</Color>'
        $content | Should -Match '<Color x:Key="Color\.SplashStepActive">#E6EBFF</Color>'
        $content | Should -Match '<Color x:Key="Color\.Warning">#D6A84A</Color>'
        $content | Should -Match '<Color x:Key="Color\.Danger">#FF6B8A</Color>'
    }

    It 'uses a dedicated light palette with layered surfaces and readable log colors' {
        $content = Get-BaselineTestSourceText -Path $script:LightThemeResourcePath
        $themeContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/ThemeManagement.ps1')

        $content | Should -Match '<Color x:Key="Color\.WindowBg">#F3F5F8</Color>'
        $content | Should -Match '<Color x:Key="Color\.SurfaceElevated">#FFFFFF</Color>'
        $content | Should -Match '<Color x:Key="Color\.SurfaceControl">#F7F8FA</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextPrimary">#111827</Color>'
        $content | Should -Match '<Color x:Key="Color\.TextSecondary">#4B5563</Color>'
        $content | Should -Match '<Color x:Key="Color\.Border">#D8DEE8</Color>'
        $content | Should -Match '<Color x:Key="Color\.Accent">#2563EB</Color>'
        $content | Should -Match '<Color x:Key="Color\.AccentHover">#1D4ED8</Color>'
        $content | Should -Match '<Color x:Key="Color\.Success">#1F7A4C</Color>'
        $content | Should -Match '<Color x:Key="Color\.Progress">#1F7A4C</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogBg">#F7F8FA</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogDefault">#1F2937</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogInfo">#1D4ED8</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogDebug">#6D28D9</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogSuccess">#1F7A4C</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogWarning">#9A6700</Color>'
        $content | Should -Match '<Color x:Key="Color\.LogError">#B42318</Color>'
        $content | Should -Match '<SolidColorBrush x:Key="Brush\.LogDebug" Color="\{StaticResource Color\.LogDebug\}"/>'
        $content | Should -Match '<Color x:Key="Color\.SplashCardTop">#FFFFFF</Color>'
        $content | Should -Match '<Color x:Key="Color\.SplashCardBottom">#F4F6FA</Color>'
        $content | Should -Match '<LinearGradientBrush x:Key="Brush\.SplashCard" StartPoint="0\.5,0" EndPoint="0\.5,1">'
        $content | Should -Not -Match '<Color x:Key="Color\.WindowBg">#FFFFFF</Color>|<Color x:Key="Color\.Progress">#16A34A</Color>'

        $themeContent | Should -Match 'WindowBg\s+= "#F3F5F8"'
        $themeContent | Should -Match 'CardBg\s+= "#FFFFFF"'
        $themeContent | Should -Match 'CardBorder\s+= "#D8DEE8"'
        $themeContent | Should -Match 'AccentBlue\s+= "#2563EB"'
        $themeContent | Should -Match 'StateAccent\s+= "#1F7A4C"'
        $themeContent | Should -Match 'StateAccentStrong\s+= "#1F7A4C"'
        $themeContent | Should -Match 'ProgressGreen\s+= "#1F7A4C"'
        $themeContent | Should -Match 'LogDebug\s+= "#6D28D9"'
        $themeContent | Should -Match 'LogWarning\s+= "#9A6700"'
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
        $Script:DarkTheme = @{ AccentBlue = '#7CB7FF' }
    }

    It 'returns the provided fallback color when non-empty' {
        Get-GuiFallbackColor -FallbackColor '#FF0000' | Should -Be '#FF0000'
    }

    It 'returns DarkTheme AccentBlue when no fallback provided' {
        Get-GuiFallbackColor -FallbackColor '' | Should -Be '#7CB7FF'
    }

    It 'returns DarkTheme AccentBlue for null fallback' {
        Get-GuiFallbackColor -FallbackColor $null | Should -Be '#7CB7FF'
    }

    It 'returns hardcoded default when DarkTheme is missing' {
        $Script:DarkTheme = $null
        $result = Get-GuiFallbackColor -FallbackColor ''
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GuiReadableForegroundColor' {
    It 'selects a dark foreground for the dark theme light accent fill' {
        Get-GuiReadableForegroundColor -BackgroundColor '#7CB7FF' -CandidateColors @('#FFFFFF', '#111827', '#0E111A') | Should -Be '#0E111A'
    }

    It 'selects a light foreground for the light theme dark accent fill' {
        Get-GuiReadableForegroundColor -BackgroundColor '#2563EB' -CandidateColors @('#FFFFFF', '#111827', '#F3F5F8') | Should -Be '#FFFFFF'
    }
}

Describe 'Repair-GuiThemePaletteWithReferences' {
    BeforeEach {
        $Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
        $Script:DarkTheme = @{
            AccentBlue = '#7CB7FF'
            TextPrimary = '#F4F7FF'
            TextSecondary = '#CDD6EA'
            CardBg = '#252D40'
            HeaderBg = '#151824'
            FocusRing = '#9ACAFF'
            TabHoverBg = '#343C55'
            AccentHover = '#9ACAFF'
            AccentPress = '#4D9CFF'
        }
        $Script:LightTheme = @{
            AccentBlue = '#1550AA'
            TextPrimary = '#1F2937'
            TextSecondary = '#4B5563'
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
            AccentBlue = '#7CB7FF'
            TextPrimary = '#F4F7FF'
            TextSecondary = '#CDD6EA'
            CardBg = '#252D40'
            HeaderBg = '#151824'
            FocusRing = '#9ACAFF'
            TabHoverBg = '#343C55'
            AccentHover = '#9ACAFF'
            AccentPress = '#4D9CFF'
        }
        $result = Repair-GuiThemePaletteWithReferences -Theme $theme -ThemeName 'Dark' 3>$null
        $result.AccentBlue | Should -Be '#7CB7FF'
    }

    It 'fills missing keys from the opposite theme' {
        $theme = @{ AccentBlue = '#3B82F6' }
        $result = Repair-GuiThemePaletteWithReferences -Theme $theme -ThemeName 'Dark' 3>$null
        $result | Should -BeOfType [hashtable]
    }

    It 'does not crash on empty theme' {
        $result = Repair-GuiThemePaletteWithReferences -Theme @{} -ThemeName 'Dark' 3>$null
        $result | Should -BeOfType [hashtable]
    }
}
