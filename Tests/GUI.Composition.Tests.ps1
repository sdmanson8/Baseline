Set-StrictMode -Version Latest

BeforeAll {
    # Load WPF assemblies so types like [System.Windows.Controls.Button] resolve
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

    # Helper: parse functions from a .ps1 file via AST (no execution of top-level code)
    # Rewrites function names with script: scope so they survive Pester 5 scoping.
    <#
        .SYNOPSIS
    #>

    function Import-AstFunctions {
        param (
            [string]$FilePath,
            [string[]]$Include
        )
        if (-not (Test-Path $FilePath)) { throw "Source file not found: $FilePath" }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)
        $fns = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $fns) {
            if ($Include -and $fn.Name -notin $Include) { continue }
            # Rewrite the function definition to use script: scope so it's visible
            # from Pester It blocks (Invoke-Expression in a nested call defaults to local scope)
            $fnText = $fn.Extent.Text -replace "^function\s+$([regex]::Escape($fn.Name))", "function script:$($fn.Name)"
            Invoke-Expression $fnText
        }
    }

    # Helper used by several GUI source files
    <#
        .SYNOPSIS
    #>

    function Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }
    <#
        .SYNOPSIS
    #>
    function Get-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $null }
        if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }
        $prop = $Object.PSObject.Properties[$FieldName]
        if ($prop) { return $prop.Value }
        return $null
    }

    function Get-GuiExplicitSelectionDefinition {
        param([string]$FunctionName)
        if ($script:ExplicitSelectionDefinitions -and $script:ExplicitSelectionDefinitions.ContainsKey($FunctionName)) {
            return $script:ExplicitSelectionDefinitions[$FunctionName]
        }
        return $null
    }

    function Invoke-GuiDetectScriptblock {
        param(
            [object]$Detect,
            [bool]$DefaultValue
        )
        return [bool]$script:DetectedToggleState
    }

    function script:Test-IsSafeModeUX {
        return ([bool]$script:SafeMode)
    }

    function script:Test-IsExpertModeUX {
        return ([bool]$script:AdvancedMode)
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $guiDir   = Join-Path $repoRoot 'Module/GUI'

    # ── Mode state functions ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'ModeState.ps1')

    # ── Plan summary dialog ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'PlanSummaryPanel.ps1') -Include 'Show-PlanSummaryDialog'

    # ── Style management (Set-GuiButtonChrome, Show-ThemedDialog) ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'StyleManagement.ps1') -Include 'Set-GuiButtonChrome', 'New-GuiChoiceComboTemplate', 'Set-ChoiceComboStyle', 'Show-ThemedDialog', 'Update-HeaderModeStateText', 'Update-GuiMenuBarLocalization', 'Update-GuiMenuBarTheme', 'Update-GuiDuplicateActionVisibility'

    # ── New-SafeThickness, New-WpfSetter from GUI.psm1 (needed by Set-GuiButtonChrome) ──
    $guiPsmPath = Join-Path $repoRoot 'Module/Regions/GUI.psm1'
    Import-AstFunctions -FilePath $guiPsmPath -Include 'New-SafeThickness', 'New-WpfSetter'

    # ── Initialize shared GUI state used by imported rendering helpers ──
    $Script:BrushCache = @{}
    $Script:SharedBrushConverter = [System.Windows.Media.BrushConverter]::new()
    $Script:TitleBarText = $null
    $Script:Form = $null

    # ── Execution summary dialog ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'ExecutionSummaryDialog.ps1') -Include 'Show-ExecutionSummaryDialog'

    # ── Icon factory (Test-GuiIconsAvailable, New-GuiLabeledIconContent, Set-GuiButtonIconContent) ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'IconFactory.ps1')

    # ── Tweak visualization (Get-TweakVisualMetadata) ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'TweakVisualization.ps1') -Include 'Get-TweakVisualMetadata'

    # ── Tweak analysis helpers needed by Get-TweakVisualMetadata ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'TweakAnalysis.ps1')

    # ── UX policy helpers ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'UxPolicy.ps1')

    # ── Theme palettes ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'ThemeManagement.ps1')

    # ── Game mode UI (Set-GameModeState) ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'GameModeUI.ps1') -Include 'Set-GameModeState'

    # Execute theme variable assignments from ThemeManagement.ps1 so $Script:DarkTheme / $Script:LightTheme are set
    $themeAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $guiDir 'ThemeManagement.ps1'), [ref]$null, [ref]$null)
    $assignments = $themeAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.ToString() -match '^\$Script:(Dark|Light)Theme$'
    }, $true)
    foreach ($assign in $assignments) {
        Invoke-Expression $assign.Extent.Text
    }

    $Global:Localization = @{}
}

# ─────────────────────────────────────────────────────────────
# W-1b: Mode transition contracts
# ─────────────────────────────────────────────────────────────
Describe 'Mode transition contracts (W-1b)' {
    It 'Set-SafeModeState function exists' {
        Get-Command -Name 'Set-SafeModeState' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Set-AdvancedModeState function exists' {
        Get-Command -Name 'Set-AdvancedModeState' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Set-GameModeState function exists' {
        Get-Command -Name 'Set-GameModeState' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }
}

# ─────────────────────────────────────────────────────────────
# W-1a: Dialog creation contracts
# ─────────────────────────────────────────────────────────────
Describe 'Dialog creation contracts (W-1a)' {
    It 'Show-PlanSummaryDialog function exists' {
        Get-Command -Name 'Show-PlanSummaryDialog' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Show-ThemedDialog function exists (available in GUICommon)' {
        Get-Command -Name 'Show-ThemedDialog' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Show-ExecutionSummaryDialog function exists (available in GUICommon)' {
        Get-Command -Name 'Show-ExecutionSummaryDialog' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }
}

# ─────────────────────────────────────────────────────────────
# W-1f: Icon fallback behavior
# ─────────────────────────────────────────────────────────────
Describe 'Icon fallback behavior (W-1f)' {
    BeforeEach {
        # Ensure icon system is NOT initialized
        $Script:GuiIconEnabled = $false
        $Script:GuiIconFontFamily = $null
    }

    It 'Test-GuiIconsAvailable returns $false when icon system is not initialized' {
        Test-GuiIconsAvailable | Should -Be $false
    }

    It 'New-GuiLabeledIconContent with -AllowTextOnlyFallback returns non-null even without icons' {
        $result = New-GuiLabeledIconContent -IconName 'Settings' -Text 'Test Label' -AllowTextOnlyFallback
        $result | Should -Not -BeNullOrEmpty
    }

    It 'Set-GuiButtonIconContent falls back to text-only without icon system' {
        $btn = [System.Windows.Controls.Button]::new()
        Set-GuiButtonIconContent -Button $btn -IconName 'Settings' -Text 'Apply'
        # Button content should be set (text fallback) rather than left empty
        $btn.Content | Should -Not -BeNullOrEmpty
        # The fallback should include or equal the text label
        [string]$btn.Content | Should -Not -Be ''
    }
}

# ─────────────────────────────────────────────────────────────
# W-1c: Preview count generation
# ─────────────────────────────────────────────────────────────
Describe 'Preview count generation (W-1c)' {
    BeforeEach {
        $script:ExplicitSelectionDefinitions = @{}
        $script:DetectedToggleState = $false
        $Script:ScanEnabled = $false
    }

    It 'Get-TweakVisualMetadata function exists' {
        Get-Command -Name 'Get-TweakVisualMetadata' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'returns object with MatchesDesired, StateLabel, StateTone, and detected toggle state for a Toggle tweak' {
        $tweak = [pscustomobject]@{
            Name         = 'TestTweak'
            Type         = 'Toggle'
            Default      = $true
            Risk         = 'Low'
            Function     = 'TestFunction'
            CautionReason = ''
            SubCategory   = ''
            SourceRegion  = ''
            Category     = 'Test'
            PresetTier   = 'Basic'
            Options      = @()
            Tags         = @()
            ScenarioTags = @()
            Description  = ''
            Detail       = ''
            WhyThisMatters = ''
        }
        $state = [pscustomobject]@{
            IsChecked    = $true
            CurrentValue = $true
        }

        $result = Get-TweakVisualMetadata -Tweak $tweak -StateSource $state

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'MatchesDesired'
        $result.PSObject.Properties.Name | Should -Contain 'StateLabel'
        $result.PSObject.Properties.Name | Should -Contain 'StateTone'
        $result.PSObject.Properties.Name | Should -Contain 'DetectedState'
        $result.PSObject.Properties.Name | Should -Contain 'GoalState'
        $result.PSObject.Properties.Name | Should -Contain 'IsSelected'
    }

    It 'marks a toggle Already Set only when detected state equals goal state: <CaseName>' -ForEach @(
        @{ CaseName = 'Disabled matches Disable'; Detected = $false; Goal = $false; ExpectedLabel = 'Already Set'; ExpectedMatches = $true }
        @{ CaseName = 'Enabled does not match Disable'; Detected = $true; Goal = $false; ExpectedLabel = 'Not Applied'; ExpectedMatches = $false }
        @{ CaseName = 'Enabled matches Enable'; Detected = $true; Goal = $true; ExpectedLabel = 'Already Set'; ExpectedMatches = $true }
        @{ CaseName = 'Disabled does not match Enable'; Detected = $false; Goal = $true; ExpectedLabel = 'Not Applied'; ExpectedMatches = $false }
    ) {
        $Script:ScanEnabled = $true
        $script:DetectedToggleState = [bool]$Detected
        $tweak = [pscustomobject]@{
            Name = 'Toggle State Test'
            Type = 'Toggle'
            Default = [bool]$Goal
            Detect = { $script:DetectedToggleState }
            Function = 'ToggleStateTest'
            Risk = 'Low'
            Tags = @()
            ScenarioTags = @()
        }
        $state = [pscustomobject]@{ IsChecked = $false }

        $result = Get-TweakVisualMetadata -Tweak $tweak -StateSource $state

        $result.StateLabel | Should -Be $ExpectedLabel
        $result.MatchesDesired | Should -Be $ExpectedMatches
    }

    It 'shows Will Change when a scanned toggle is selected but detected state does not match the goal' {
        $Script:ScanEnabled = $true
        $script:DetectedToggleState = $false
        $tweak = [pscustomobject]@{
            Name = 'Toggle State Test'
            Type = 'Toggle'
            Default = $true
            Detect = { $script:DetectedToggleState }
            Function = 'ToggleStateTest'
            Risk = 'Low'
            Tags = @()
            ScenarioTags = @()
        }
        $state = [pscustomobject]@{ IsChecked = $true }

        $result = Get-TweakVisualMetadata -Tweak $tweak -StateSource $state

        $result.StateLabel | Should -Be 'Will Change'
        $result.MatchesDesired | Should -BeFalse
    }

    It 'uses cached toggle detection before invoking a live Detect scriptblock' {
        $Script:ScanEnabled = $true
        $script:DetectedToggleState = $false
        function script:Get-CachedDetection {
            param([string]$Function)
            if ($Function -eq 'CachedToggleState') { return $true }
            return $null
        }

        try {
            $tweak = [pscustomobject]@{
                Name = 'Cached Toggle State'
                Type = 'Toggle'
                Default = $true
                Detect = { $false }
                Function = 'CachedToggleState'
                Risk = 'Low'
                Tags = @()
                ScenarioTags = @()
            }

            $result = Get-TweakVisualMetadata -Tweak $tweak -StateSource ([pscustomobject]@{ IsChecked = $false })

            $result.MatchesDesired | Should -BeTrue
            $result.DetectedState | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath Function:\Get-CachedDetection -ErrorAction SilentlyContinue
        }
    }

    It 'returns null for null tweak input' {
        $result = Get-TweakVisualMetadata -Tweak $null
        $result | Should -BeNullOrEmpty
    }
}

# ─────────────────────────────────────────────────────────────
# W-1d: Button chrome variants
# ─────────────────────────────────────────────────────────────
Describe 'Button chrome variants (W-1d)' {
    BeforeAll {
        $Script:CurrentTheme = $Script:DarkTheme
    }

    It 'Set-GuiButtonChrome accepts all documented variants: <Variant>' -ForEach @(
        @{ Variant = 'Primary' }
        @{ Variant = 'Preview' }
        @{ Variant = 'Danger' }
        @{ Variant = 'DangerSubtle' }
        @{ Variant = 'Secondary' }
        @{ Variant = 'Subtle' }
        @{ Variant = 'Selection' }
        @{ Variant = 'SegmentNeutral' }
    ) {
        $btn = [System.Windows.Controls.Button]::new()
        # Should not throw for any valid variant
        { Set-GuiButtonChrome -Button $btn -Variant $Variant } | Should -Not -Throw
    }
}

# ─────────────────────────────────────────────────────────────
# W-1e: Theme management
# ─────────────────────────────────────────────────────────────
Describe 'Theme management (W-1e)' {
    It '$Script:DarkTheme exists after module load' {
        $Script:DarkTheme | Should -Not -BeNullOrEmpty
    }

    It '$Script:LightTheme exists after module load' {
        $Script:LightTheme | Should -Not -BeNullOrEmpty
    }

    It 'DarkTheme has required keys: WindowBg, HeaderBg, AccentBlue, CautionBg, TextPrimary, BorderStrong' {
        $required = @('WindowBg', 'HeaderBg', 'AccentBlue', 'CautionBg', 'TextPrimary', 'BorderStrong')
        foreach ($key in $required) {
            $Script:DarkTheme.Keys | Should -Contain $key
        }
    }

    It 'LightTheme has required keys: WindowBg, HeaderBg, AccentBlue, CautionBg, TextPrimary, BorderStrong' {
        $required = @('WindowBg', 'HeaderBg', 'AccentBlue', 'CautionBg', 'TextPrimary', 'BorderStrong')
        foreach ($key in $required) {
            $Script:LightTheme.Keys | Should -Contain $key
        }
    }

    It 'ConvertTo-GuiBrush returns a WPF brush type' {
        $brush = ConvertTo-GuiBrush -Color '#CDD6F4' -Context 'Test'

        $brush | Should -BeOfType ([System.Windows.Media.Brush])
    }

    It 'New-SafeBrushConverter returns a WPF brush type' {
        $converter = New-SafeBrushConverter -Context 'Test'
        $brush = $converter.ConvertFromString('#CDD6F4')

        $brush | Should -BeOfType ([System.Windows.Media.Brush])
    }

    It 'New-WpfSetter applies wrapped brush values safely through WPF styles' {
        $wrappedBrush = [System.Management.Automation.PSObject]::AsPSObject([System.Windows.Media.Brushes]::CornflowerBlue)
        $style = [System.Windows.Style]::new([System.Windows.Controls.Button])
        $setter = New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $wrappedBrush
        [void]$style.Setters.Add($setter)

        $button = [System.Windows.Controls.Button]::new()
        $button.Content = 'Test'
        $button.Style = $style

        { $button.Measure([System.Windows.Size]::new(1000, 1000)) } | Should -Not -Throw
    }

    It 'Set-ChoiceComboStyle stores concrete brushes for combo resources and survives layout' {
        $Script:CurrentTheme = $Script:DarkTheme
        $Script:CurrentThemeName = 'Dark'
        $Script:ChoiceComboTemplate = $null
        $Script:ChoiceComboTemplateTheme = $null
        $Script:ChoiceComboTemplateLoadFailures = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        $combo = [System.Windows.Controls.ComboBox]::new()
        [void]$combo.Items.Add('Disable')
        [void]$combo.Items.Add('Enable')

        Set-ChoiceComboStyle -Combo $combo

        $combo.Resources[[System.Windows.SystemColors]::MenuBrushKey] | Should -BeOfType ([System.Windows.Media.Brush])
        $combo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] | Should -BeOfType ([System.Windows.Media.Brush])
        $combo.ItemContainerStyle | Should -Not -BeNullOrEmpty
        $combo.OverridesDefaultStyle | Should -BeTrue
        $combo.Template | Should -Not -BeNullOrEmpty
        $combo.BorderBrush | Should -BeOfType ([System.Windows.Media.SolidColorBrush])
        $combo.BorderBrush.Color.ToString() | Should -Be '#FF3C4A66'
        $comboContentSite = $combo.Template.FindName('ContentSite', $combo)
        $comboContentSite | Should -Not -BeNullOrEmpty
        $comboContentSite.GetValue([System.Windows.Documents.TextElement]::ForegroundProperty) | Should -Be $combo.Foreground

        $item = [System.Windows.Controls.ComboBoxItem]::new()
        $item.Content = 'Disable'
        $item.Style = $combo.ItemContainerStyle

        {
            $combo.Measure([System.Windows.Size]::new(1000, 1000))
            $combo.Arrange([System.Windows.Rect]::new(0, 0, 240, 30))
            $item.Measure([System.Windows.Size]::new(1000, 1000))
            $item.Arrange([System.Windows.Rect]::new(0, 0, 240, 30))
        } | Should -Not -Throw

        [void]$item.ApplyTemplate()
        $itemContentSite = $item.Template.FindName('ItemContentSite', $item)
        $itemContentSite | Should -Not -BeNullOrEmpty
        $itemContentBinding = [System.Windows.Data.BindingOperations]::GetBinding($itemContentSite, [System.Windows.Controls.ContentPresenter]::ContentProperty)
        $itemContentBinding | Should -Not -BeNullOrEmpty
        $itemContentBinding.Path.Path | Should -Be 'Content'
    }

    It 'Set-ChoiceComboStyle keeps a themed custom template in light mode' {
        $Script:CurrentTheme = $Script:LightTheme
        $Script:CurrentThemeName = 'Light'
        $Script:ChoiceComboTemplate = $null
        $Script:ChoiceComboTemplateTheme = $null

        $combo = [System.Windows.Controls.ComboBox]::new()
        [void]$combo.Items.Add('Disable')
        [void]$combo.Items.Add('Enable')

        Set-ChoiceComboStyle -Combo $combo

        $combo.OverridesDefaultStyle | Should -BeTrue
        $combo.Template | Should -Not -BeNullOrEmpty
        $combo.Background | Should -BeOfType ([System.Windows.Media.Brush])
        $combo.Foreground | Should -BeOfType ([System.Windows.Media.Brush])
        $combo.BorderBrush | Should -BeOfType ([System.Windows.Media.Brush])
    }

    It 'New-GuiLabeledIconContent normalizes wrapped foreground brushes before layout' {
        $Script:GuiIconEnabled = $false
        $Script:GuiIconFontFamily = $null

        $wrappedBrush = [System.Management.Automation.PSObject]::AsPSObject([System.Windows.Media.Brushes]::SeaGreen)
        $content = New-GuiLabeledIconContent -IconName 'Settings' -Text 'Test Label' -Foreground $wrappedBrush -AllowTextOnlyFallback

        $content | Should -Not -BeNullOrEmpty
        $content.Children.Count | Should -Be 1
        $content.Children[0] | Should -BeOfType ([System.Windows.Controls.TextBlock])
        $content.Children[0].Foreground | Should -BeOfType ([System.Windows.Media.Brush])
        { $content.Measure([System.Windows.Size]::new(1000, 1000)) } | Should -Not -Throw
    }

    It 'Update-GuiMenuBarTheme preserves brush resources for menu foreground updates' {
        $Script:CurrentTheme = $Script:DarkTheme
        $Script:MainMenuBar = [System.Windows.Controls.Menu]::new()
        $Script:MainMenuBar.Resources['MenuBarBackground']  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuBarBorder']      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuBarForeground']  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuBarHoverBg']     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuBarHoverFg']     = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuSubmenuBg']      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuSubmenuBorder']  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MainMenuBar.Resources['MenuSeparatorBrush'] = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Colors]::Black)
        $Script:MenuBarBorder = [System.Windows.Controls.Border]::new()

        { Update-GuiMenuBarTheme } | Should -Not -Throw

        $Script:MainMenuBar.Resources['MenuBarForeground'] | Should -BeOfType ([System.Windows.Media.Brush])
        $Script:MainMenuBar.Resources['MenuBarHoverFg'] | Should -BeOfType ([System.Windows.Media.Brush])
        $Script:MenuBarBorder.Background | Should -BeOfType ([System.Windows.Media.Brush])
        $Script:MenuBarBorder.BorderBrush | Should -BeOfType ([System.Windows.Media.Brush])
    }
}

Describe 'Theme menu state (W-1g)' {
    BeforeEach {
        <#
            .SYNOPSIS
        #>

        function script:Get-UxLocalizedString {
            param(
                [string]$Key,
                [string]$Fallback
            )

            switch ($Key) {
                'GuiThemeLight' { return 'Theme: Light' }
                'GuiThemeDark'  { return 'Theme: Dark' }
                default         { return $Fallback }
            }
        }

        $Script:MenuViewTheme = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuViewTheme.IsCheckable = $true
        $Script:ChkTheme = [System.Windows.Controls.CheckBox]::new()
        $Script:TxtThemeState = [System.Windows.Controls.TextBlock]::new()
        $Script:CurrentTheme = $Script:DarkTheme
        $Script:CurrentThemeName = 'Dark'
        $Script:SafeMode = $false
        $Script:AdvancedMode = $false
    }

    It 'syncs the menu label and check state for Light theme' {
        $Script:ChkTheme.IsChecked = $true

        Update-HeaderModeStateText

        [string]$Script:MenuViewTheme.Header | Should -Be 'Switch to Dark Mode'
        $Script:MenuViewTheme.IsChecked | Should -BeTrue
        [string]$Script:TxtThemeState.Text | Should -Be 'Theme: Light'
    }

    It 'syncs the menu label and check state for Dark theme' {
        $Script:ChkTheme.IsChecked = $false

        Update-HeaderModeStateText

        [string]$Script:MenuViewTheme.Header | Should -Be 'Switch to Light Mode'
        $Script:MenuViewTheme.IsChecked | Should -BeFalse
        [string]$Script:TxtThemeState.Text | Should -Be 'Theme: Dark'
    }
}

Describe 'Safe Mode visibility (W-1h)' {
    BeforeEach {
        <#
            .SYNOPSIS
        #>

        function script:Get-UxLocalizedString {
            param(
                [string]$Key,
                [string]$Fallback,
                [object[]]$FormatArgs
            )

            switch ($Key) {
                'GuiStatusSafeModeEnabled' { return 'Safe mode enabled.' }
                'GuiStatusSafeModeDisabledRestored' { return 'Safe mode disabled.' }
                'GuiStatusSafeModeDisabledCleared' { return ('Safe mode disabled and {0} selection(s) cleared.' -f $FormatArgs[0]) }
                default { return $Fallback }
            }
        }

        <#
            .SYNOPSIS
        #>

        function script:Test-GuiModeActive {
            param([string]$Mode)

            switch ($Mode) {
                'Safe'   { return $script:SafeModeActive }
                'Expert' { return $script:ExpertModeActive }
                default  { return $false }
            }
        }

        <#
            .SYNOPSIS
        #>
        function script:Set-GuiMode {
            param([string]$ViewMode)

            $script:LastViewMode = $ViewMode
        }

        <#
            .SYNOPSIS
        #>

        function script:Invoke-GuiStateTransition {
            param(
                [string]$Context,
                [string]$StatusMessage,
                [string]$StatusTone,
                [switch]$ClearCache,
                [switch]$RebuildTab,
                [switch]$SyncActionButton,
                [switch]$UpdatePresetBadge,
                [switch]$UpdateModeText
            )

            $script:TransitionCall = [pscustomobject]@{
                Context          = $Context
                StatusMessage    = $StatusMessage
                StatusTone       = $StatusTone
                ClearCache       = [bool]$ClearCache
                RebuildTab       = [bool]$RebuildTab
                SyncActionButton = [bool]$SyncActionButton
                UpdatePresetBadge = [bool]$UpdatePresetBadge
                UpdateModeText   = [bool]$UpdateModeText
            }
        }

        $script:SafeModeActive = $false
        $script:ExpertModeActive = $false
        $script:LastViewMode = $null
        $script:TransitionCall = $null
        $script:ClearedSelectionCount = 0
        $script:ClearInvisibleSelectionStateScript = {
            $script:ClearedSelectionCount++
            return 3
        }

        foreach ($name in @(
            'BtnLog',
            'BtnFilterToggle',
            'ChkScan',
            'FilterOptionsPanel',
            'MenuTools',
            'MenuToolsAppsManager',
            'MenuToolsUpdateAllApps',
            'MenuToolsExportSupportBundle',
            'MenuToolsApproveRemoteTargets',
            'MenuToolsSaveRemoteApprovalPolicy',
            'MenuToolsLoadRemoteApprovalPolicy',
            'MenuToolsRemoteConsole',
            'MenuToolsOperatorConsole',
            'MenuToolsRemoteSessionStatus',
            'MenuToolsRemovalPersistence',
            'MenuToolsSepApps',
            'MenuActionsCheckCompliance',
            'MenuActionsScanSystem',
            'MenuActionsAuditLog',
            'MenuViewFilters',
            'MenuFileExportSystemState',
            'MenuFileExportConfigProfile'
        )) {
            Set-Variable -Scope Script -Name $name -Value $null
        }

        $Script:BtnLog = [System.Windows.Controls.Button]::new()
        $Script:BtnLog.Visibility = 'Visible'
        $Script:BtnFilterToggle = [System.Windows.Controls.Button]::new()
        $Script:BtnFilterToggle.Visibility = 'Visible'
        $Script:ChkScan = [System.Windows.Controls.CheckBox]::new()
        $Script:ChkScan.Visibility = 'Visible'
        $Script:FilterOptionsPanel = $null
        $Script:MenuTools = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuTools.Visibility = 'Visible'
        $Script:MenuToolsAppsManager = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsAppsManager.Visibility = 'Visible'
        $Script:MenuToolsUpdateAllApps = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsUpdateAllApps.Visibility = 'Visible'
        $Script:MenuToolsExportSupportBundle = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsExportSupportBundle.Visibility = 'Visible'
        $Script:MenuToolsApproveRemoteTargets = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsApproveRemoteTargets.Visibility = 'Visible'
        $Script:MenuToolsSaveRemoteApprovalPolicy = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsSaveRemoteApprovalPolicy.Visibility = 'Visible'
        $Script:MenuToolsLoadRemoteApprovalPolicy = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsLoadRemoteApprovalPolicy.Visibility = 'Visible'
        $Script:MenuToolsRemoteConsole = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsRemoteConsole.Visibility = 'Visible'
        $Script:MenuToolsOperatorConsole = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsOperatorConsole.Visibility = 'Visible'
        $Script:MenuToolsRemoteSessionStatus = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsRemoteSessionStatus.Visibility = 'Visible'
        $Script:MenuToolsRemovalPersistence = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuToolsRemovalPersistence.Visibility = 'Visible'
        $Script:MenuToolsSepApps = [System.Windows.Controls.Separator]::new()
        $Script:MenuToolsSepApps.Visibility = 'Visible'
        $Script:MenuActionsCheckCompliance = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuActionsCheckCompliance.Visibility = 'Visible'
        $Script:MenuActionsScanSystem = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuActionsScanSystem.Visibility = 'Visible'
        $Script:MenuActionsAuditLog = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuActionsAuditLog.Visibility = 'Visible'
        $Script:MenuViewFilters = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuViewFilters.Visibility = 'Visible'
        $Script:MenuFileExportSystemState = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuFileExportSystemState.Visibility = 'Visible'
        $Script:MenuFileExportConfigProfile = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuFileExportConfigProfile.Visibility = 'Visible'
        $Script:ExpertModeBanner = [System.Windows.Controls.Border]::new()
        $Script:ExpertModeBanner.Visibility = 'Visible'
    }

    It 'collapses advanced controls when Safe Mode is enabled' {
        $script:SafeModeActive = $false
        $script:ExpertModeActive = $false

        Set-SafeModeState -Enabled:$true

        $script:LastViewMode | Should -Be 'Safe'
        $script:TransitionCall.Context | Should -Be 'SafeMode'
        $script:TransitionCall.StatusTone | Should -Be 'success'
        $script:ClearedSelectionCount | Should -Be 1
        $script:BtnLog.Visibility | Should -Be 'Collapsed'
        $script:BtnFilterToggle.Visibility | Should -Be 'Collapsed'
        $script:ChkScan.Visibility | Should -Be 'Collapsed'
        $script:ExpertModeBanner.Visibility | Should -Be 'Collapsed'
        $script:MenuTools.Visibility | Should -Be 'Visible'
        $script:MenuToolsExportSupportBundle.Visibility | Should -Be 'Visible'
        $script:MenuToolsAppsManager.Visibility | Should -Be 'Visible'
        $script:MenuToolsUpdateAllApps.Visibility | Should -Be 'Visible'
        $script:MenuToolsApproveRemoteTargets.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsSaveRemoteApprovalPolicy.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsLoadRemoteApprovalPolicy.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsRemoteConsole.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsOperatorConsole.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsRemoteSessionStatus.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsRemovalPersistence.Visibility | Should -Be 'Collapsed'
        $script:MenuToolsSepApps.Visibility | Should -Be 'Collapsed'
        $script:MenuActionsCheckCompliance.Visibility | Should -Be 'Collapsed'
        $script:MenuActionsScanSystem.Visibility | Should -Be 'Collapsed'
        $script:MenuActionsAuditLog.Visibility | Should -Be 'Collapsed'
        $script:MenuViewFilters.Visibility | Should -Be 'Collapsed'
        $script:MenuFileExportSystemState.Visibility | Should -Be 'Collapsed'
        $script:MenuFileExportConfigProfile.Visibility | Should -Be 'Collapsed'
    }

    It 'restores controls when Safe Mode is disabled' {
        $script:SafeModeActive = $true
        $script:ExpertModeActive = $false
        $script:BtnLog.Visibility = 'Collapsed'
        $script:BtnFilterToggle.Visibility = 'Collapsed'
        $script:ChkScan.Visibility = 'Collapsed'
        $script:ExpertModeBanner.Visibility = 'Collapsed'
        $script:MenuTools.Visibility = 'Collapsed'
        $script:MenuToolsExportSupportBundle.Visibility = 'Visible'
        $script:MenuToolsAppsManager.Visibility = 'Collapsed'
        $script:MenuToolsUpdateAllApps.Visibility = 'Collapsed'
        $script:MenuToolsApproveRemoteTargets.Visibility = 'Collapsed'
        $script:MenuToolsSaveRemoteApprovalPolicy.Visibility = 'Collapsed'
        $script:MenuToolsLoadRemoteApprovalPolicy.Visibility = 'Collapsed'
        $script:MenuToolsRemoteConsole.Visibility = 'Collapsed'
        $script:MenuToolsOperatorConsole.Visibility = 'Collapsed'
        $script:MenuToolsRemoteSessionStatus.Visibility = 'Collapsed'
        $script:MenuToolsRemovalPersistence.Visibility = 'Collapsed'
        $script:MenuToolsSepApps.Visibility = 'Collapsed'
        $script:MenuActionsCheckCompliance.Visibility = 'Collapsed'
        $script:MenuActionsScanSystem.Visibility = 'Collapsed'
        $script:MenuActionsAuditLog.Visibility = 'Collapsed'
        $script:MenuViewFilters.Visibility = 'Collapsed'
        $script:MenuFileExportSystemState.Visibility = 'Collapsed'
        $script:MenuFileExportConfigProfile.Visibility = 'Collapsed'

        Set-SafeModeState -Enabled:$false

        $script:LastViewMode | Should -Be 'Standard'
        $script:TransitionCall.Context | Should -Be 'SafeMode'
        $script:TransitionCall.StatusTone | Should -Be 'muted'
        $script:BtnLog.Visibility | Should -Be 'Collapsed'
        $script:BtnFilterToggle.Visibility | Should -Be 'Visible'
        $script:ChkScan.Visibility | Should -Be 'Visible'
        $script:ExpertModeBanner.Visibility | Should -Be 'Collapsed'
        $script:MenuTools.Visibility | Should -Be 'Visible'
        $script:MenuToolsExportSupportBundle.Visibility | Should -Be 'Visible'
        $script:MenuToolsAppsManager.Visibility | Should -Be 'Visible'
        $script:MenuToolsUpdateAllApps.Visibility | Should -Be 'Visible'
        $script:MenuToolsApproveRemoteTargets.Visibility | Should -Be 'Visible'
        $script:MenuToolsSaveRemoteApprovalPolicy.Visibility | Should -Be 'Visible'
        $script:MenuToolsLoadRemoteApprovalPolicy.Visibility | Should -Be 'Visible'
        $script:MenuToolsRemoteConsole.Visibility | Should -Be 'Visible'
        $script:MenuToolsOperatorConsole.Visibility | Should -Be 'Visible'
        $script:MenuToolsRemoteSessionStatus.Visibility | Should -Be 'Visible'
        $script:MenuToolsRemovalPersistence.Visibility | Should -Be 'Visible'
        $script:MenuToolsSepApps.Visibility | Should -Be 'Visible'
        $script:MenuActionsCheckCompliance.Visibility | Should -Be 'Visible'
        $script:MenuActionsScanSystem.Visibility | Should -Be 'Visible'
        $script:MenuActionsAuditLog.Visibility | Should -Be 'Visible'
        $script:MenuViewFilters.Visibility | Should -Be 'Visible'
        $script:MenuFileExportSystemState.Visibility | Should -Be 'Visible'
        $script:MenuFileExportConfigProfile.Visibility | Should -Be 'Visible'
    }

    It 'keeps the header log button hidden when Expert Mode is enabled' {
        $script:SafeModeActive = $false
        $script:ExpertModeActive = $false
        $script:BtnLog.Visibility = 'Collapsed'
        $script:BtnFilterToggle.Visibility = 'Collapsed'
        $script:ChkScan.Visibility = 'Collapsed'

        Set-AdvancedModeState -Enabled:$true

        $script:LastViewMode | Should -Be 'Expert'
        $script:TransitionCall.Context | Should -Be 'ExpertMode'
        $script:BtnLog.Visibility | Should -Be 'Collapsed'
        $script:BtnFilterToggle.Visibility | Should -Be 'Visible'
        $script:ChkScan.Visibility | Should -Be 'Visible'
        $script:ExpertModeBanner.Visibility | Should -Be 'Visible'
    }
}

Describe 'Duplicate action visibility (W-1i)' {
    BeforeEach {
        foreach ($name in @(
            'BtnExportSettings',
            'BtnImportSettings',
            'BtnExportConfigProfile',
            'BtnExportSystemState',
            'BtnCheckCompliance',
            'BtnAuditLog',
            'BtnLog',
            'BtnUndoLastRun'
        )) {
            Set-Variable -Scope Script -Name $name -Value $null
        }

        $Script:BtnExportSettings = [System.Windows.Controls.Button]::new()
        $Script:BtnImportSettings = [System.Windows.Controls.Button]::new()
        $Script:BtnExportConfigProfile = [System.Windows.Controls.Button]::new()
        $Script:BtnExportSystemState = [System.Windows.Controls.Button]::new()
        $Script:BtnCheckCompliance = [System.Windows.Controls.Button]::new()
        $Script:BtnAuditLog = [System.Windows.Controls.Button]::new()
        $Script:BtnLog = [System.Windows.Controls.Button]::new()
        $Script:BtnUndoLastRun = [System.Windows.Controls.Button]::new()

        foreach ($button in @(
            $Script:BtnExportSettings,
            $Script:BtnImportSettings,
            $Script:BtnExportConfigProfile,
            $Script:BtnExportSystemState,
            $Script:BtnCheckCompliance,
            $Script:BtnAuditLog,
            $Script:BtnLog,
            $Script:BtnUndoLastRun
        )) {
            $button.Visibility = 'Visible'
        }
    }

    It 'collapses the duplicated toolbar actions and log button' {
        Update-GuiDuplicateActionVisibility

        $Script:BtnExportSettings.Visibility | Should -Be 'Collapsed'
        $Script:BtnImportSettings.Visibility | Should -Be 'Collapsed'
        $Script:BtnExportConfigProfile.Visibility | Should -Be 'Collapsed'
        $Script:BtnExportSystemState.Visibility | Should -Be 'Collapsed'
        $Script:BtnCheckCompliance.Visibility | Should -Be 'Collapsed'
        $Script:BtnAuditLog.Visibility | Should -Be 'Collapsed'
        $Script:BtnLog.Visibility | Should -Be 'Collapsed'
        $Script:BtnUndoLastRun.Visibility | Should -Be 'Visible'
    }
}

Describe 'Menu localization refresh (W-1j)' {
    BeforeEach {
        <#
            .SYNOPSIS
        #>

        function script:Get-UxLocalizedString {
            param(
                [string]$Key,
                [string]$Fallback,
                [object[]]$FormatArgs
            )

            $value = if ($script:LocalizationMap.ContainsKey($Key)) { $script:LocalizationMap[$Key] } else { $Fallback }
            if ($FormatArgs -and $FormatArgs.Count -gt 0) { return ($value -f $FormatArgs) }
            return $value
        }

        $script:LocalizationMap = @{
            GuiMenuFile                = 'File'
            GuiMenuActions             = 'Actions'
            GuiMenuView                = 'View'
            GuiMenuTools               = 'Tools'
            GuiMenuHelp                = 'Help'
            GuiMenuFileImportSettings  = 'Import Settings'
            GuiMenuViewOpenLogs        = 'Open Logs'
            GuiMenuViewSwitchToLightMode = 'Switch to Light Mode'
            GuiMenuViewSwitchToDarkMode  = 'Switch to Dark Mode'
            GuiThemeDark               = 'Theme: Dark'
            GuiThemeLight              = 'Theme: Light'
        }

        foreach ($name in @(
            'MenuFile',
            'MenuActions',
            'MenuView',
            'MenuTools',
            'MenuHelp',
            'MenuActionsConnectToComputer',
            'MenuActionsDisconnect',
            'MenuFileImportSettings',
            'MenuFileExportSettings',
            'MenuFileSettings',
            'MenuFileAuditSettings',
            'MenuFileExportConfigProfile',
            'MenuFileExportSystemState',
            'MenuActionsPreviewRun',
            'MenuActionsRunTweaks',
            'MenuActionsUndoLastRun',
            'MenuActionsRestoreDefaults',
            'MenuActionsCheckCompliance',
            'MenuActionsScanSystem',
            'MenuActionsAuditLog',
            'MenuViewFilters',
            'MenuViewLogsPanel',
            'MenuViewTheme',
            'MenuToolsAppsManager',
            'MenuToolsUpdateAllApps',
            'MenuToolsDeveloperDiagnostics',
            'MenuToolsDeveloperDiagnosticsGenerateReport',
            'MenuToolsDeveloperDiagnosticsSourceQuality',
            'MenuToolsDeveloperDiagnosticsUnitTests',
            'MenuToolsDeveloperDiagnosticsGuiComposition',
            'MenuToolsDeveloperDiagnosticsOpenLatestReport',
            'MenuToolsDeveloperDiagnosticsCopyCommands',
            'MenuToolsDeveloperDiagnosticsIntegrationTests',
            'MenuToolsExportSupportBundle',
            'MenuToolsApproveRemoteTargets',
            'MenuToolsSaveRemoteApprovalPolicy',
            'MenuToolsLoadRemoteApprovalPolicy',
            'MenuToolsRemoteConsole',
            'MenuToolsOperatorConsole',
            'MenuToolsRemoteSessionStatus',
            'MenuToolsRemovalPersistence',
            'MenuHelpHelp',
            'MenuHelpStartGuide',
            'MenuHelpDocumentation',
            'MenuHelpReadme',
            'MenuHelpFAQ',
            'MenuHelpChangelog',
            'MenuHelpCheckForUpdate',
            'MenuHelpReleaseStatus',
            'MenuHelpTroubleshooting',
            'MenuHelpAbout'
        )) {
            Set-Variable -Scope Script -Name $name -Value $null
        }

        $Script:MenuFile = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuActions = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuView = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuTools = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuHelp = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuFileImportSettings = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuViewLogsPanel = [System.Windows.Controls.MenuItem]::new()
        $Script:MenuViewTheme = [System.Windows.Controls.MenuItem]::new()
        $Script:ChkTheme = [System.Windows.Controls.CheckBox]::new()
        $Script:ChkTheme.IsChecked = $false
        $Script:MenuViewTheme.IsCheckable = $true
        $Script:TxtThemeState = [System.Windows.Controls.TextBlock]::new()
        $Script:CurrentTheme = $Script:DarkTheme
        $Script:CurrentThemeName = 'Dark'
        $Script:SafeMode = $false
        $Script:AdvancedMode = $false
    }

    It 'refreshes menu labels when the localization source changes' {
        Update-GuiMenuBarLocalization

        [string]$Script:MenuFile.Header | Should -Be 'File'
        [string]$Script:MenuActions.Header | Should -Be 'Actions'
        [string]$Script:MenuView.Header | Should -Be 'View'
        [string]$Script:MenuTools.Header | Should -Be 'Tools'
        [string]$Script:MenuHelp.Header | Should -Be 'Help'
        [string]$Script:MenuFileImportSettings.Header | Should -Be 'Import Settings'
        [string]$Script:MenuViewLogsPanel.Header | Should -Be 'Open Logs'
        [string]$Script:MenuViewTheme.Header | Should -Be 'Switch to Light Mode'
        [string]$Script:TxtThemeState.Text | Should -Be 'Theme: Dark'

        $script:LocalizationMap = @{
            GuiMenuFile                = 'Fichier'
            GuiMenuActions             = 'Actions'
            GuiMenuView                = 'Affichage'
            GuiMenuTools               = 'Outils'
            GuiMenuHelp                = 'Aide'
            GuiMenuFileImportSettings  = 'Importer les parametres'
            GuiMenuViewOpenLogs        = 'Ouvrir les journaux'
            GuiMenuViewSwitchToLightMode = 'Basculer vers le mode clair'
            GuiMenuViewSwitchToDarkMode  = 'Basculer vers le mode sombre'
            GuiThemeDark               = 'Theme : sombre'
            GuiThemeLight              = 'Theme : clair'
        }

        Update-GuiMenuBarLocalization

        [string]$Script:MenuFile.Header | Should -Be 'Fichier'
        [string]$Script:MenuActions.Header | Should -Be 'Actions'
        [string]$Script:MenuView.Header | Should -Be 'Affichage'
        [string]$Script:MenuTools.Header | Should -Be 'Outils'
        [string]$Script:MenuHelp.Header | Should -Be 'Aide'
        [string]$Script:MenuFileImportSettings.Header | Should -Be 'Importer les parametres'
        [string]$Script:MenuViewLogsPanel.Header | Should -Be 'Ouvrir les journaux'
        [string]$Script:MenuViewTheme.Header | Should -Be 'Basculer vers le mode clair'
        [string]$Script:TxtThemeState.Text | Should -Be 'Theme : sombre'
    }
}
