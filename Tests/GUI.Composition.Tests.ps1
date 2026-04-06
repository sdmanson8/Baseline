Set-StrictMode -Version Latest

BeforeAll {
    # Load WPF assemblies so types like [System.Windows.Controls.Button] resolve
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
    Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

    # Helper: parse functions from a .ps1 file via AST (no execution of top-level code)
    # Rewrites function names with script: scope so they survive Pester 5 scoping.
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
    function Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }
    function Get-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $null }
        if ($Object -is [System.Collections.IDictionary]) { return $Object[$FieldName] }
        $prop = $Object.PSObject.Properties[$FieldName]
        if ($prop) { return $prop.Value }
        return $null
    }

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $guiDir   = Join-Path $repoRoot 'Module/GUI'

    # ── Mode state functions ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'ModeState.ps1')

    # ── Plan summary dialog ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'PlanSummaryPanel.ps1') -Include 'Show-PlanSummaryDialog'

    # ── Style management (Set-ButtonChrome, Show-ThemedDialog) ──
    Import-AstFunctions -FilePath (Join-Path $guiDir 'StyleManagement.ps1') -Include 'Set-ButtonChrome', 'Show-ThemedDialog'

    # ── New-SafeThickness, New-WpfSetter from GUI.psm1 (needed by Set-ButtonChrome) ──
    $guiPsmPath = Join-Path $repoRoot 'Module/Regions/GUI.psm1'
    Import-AstFunctions -FilePath $guiPsmPath -Include 'New-SafeThickness', 'New-WpfSetter'

    # ── Initialize BrushCache so New-SafeBrushConverter doesn't index into null ──
    $Script:BrushCache = @{}

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

    It 'Show-ThemedDialog function exists (exported from GUICommon)' {
        Get-Command -Name 'Show-ThemedDialog' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'Show-ExecutionSummaryDialog function exists (exported from GUICommon)' {
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
    It 'Get-TweakVisualMetadata function exists' {
        Get-Command -Name 'Get-TweakVisualMetadata' -CommandType Function -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'returns object with MatchesDesired, StateLabel, StateTone for a Toggle tweak' {
        $tweak = [pscustomobject]@{
            Name         = 'TestTweak'
            Type         = 'Toggle'
            Default      = $true
            Risk         = 'Low'
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

    It 'Set-ButtonChrome accepts all documented variants: <Variant>' -ForEach @(
        @{ Variant = 'Primary' }
        @{ Variant = 'Preview' }
        @{ Variant = 'Danger' }
        @{ Variant = 'DangerSubtle' }
        @{ Variant = 'Secondary' }
        @{ Variant = 'Subtle' }
        @{ Variant = 'Selection' }
    ) {
        $btn = [System.Windows.Controls.Button]::new()
        # Should not throw for any valid variant
        { Set-ButtonChrome -Button $btn -Variant $Variant } | Should -Not -Throw
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

    It 'DarkTheme has required keys: WindowBg, HeaderBg, AccentBlue, CautionBg, TextPrimary' {
        $required = @('WindowBg', 'HeaderBg', 'AccentBlue', 'CautionBg', 'TextPrimary')
        foreach ($key in $required) {
            $Script:DarkTheme.Keys | Should -Contain $key
        }
    }

    It 'LightTheme has required keys: WindowBg, HeaderBg, AccentBlue, CautionBg, TextPrimary' {
        $required = @('WindowBg', 'HeaderBg', 'AccentBlue', 'CautionBg', 'TextPrimary')
        foreach ($key in $required) {
            $Script:LightTheme.Keys | Should -Contain $key
        }
    }
}
