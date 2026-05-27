Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    function Get-OSInfo {
        [pscustomobject]@{
            IsWindowsServer = $true
            OSName = 'Windows Server 2022'
        }
    }

    function Get-BaselineValidationMatrixSummary {
        [pscustomobject]@{
            ServerValidationSummary = 'CI only: Windows Server 2022 (CI only)'
            ServerCIOnly = $true
            HasServerCoverage = $true
        }
    }

    function script:Test-IsSafeModeUX {
        return ([bool]$script:SafeMode)
    }

    function script:Test-IsExpertModeUX {
        return ([bool]$script:AdvancedMode)
    }

    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/UxPolicy.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    $script:Localization = $null
    $Global:Localization = $null
}

Describe 'UxPolicy' {
    BeforeEach {
        $script:SafeMode = $false
        $script:AdvancedMode = $false
        $script:GameMode = $false
        $script:GameModeProfile = $null
        $script:DesignMode = $false
        $script:GuiDisplayVersion = $null
        $Global:Localization = $null
    }

    It 'routes OS-info and validation-matrix lookup failures through Write-SwallowedException' {
        $script:GuiContent = $null
        $content = Get-BaselineTestSourceText -Path $filePath
        $content | Should -Match "Source 'UxPolicy\.GetUxMainWindowTitleText\.LoadOSInfo'"
        $content | Should -Match "Source 'UxPolicy\.GetUxExecutionSummary\.LoadValidationMatrix'"
        $content | Should -Match "Source 'UxPolicy\.GetUxExecutionSummary\.LoadOSInfo'"
    }

    Describe 'Beginner UX helpers' {
        It 'allows empty fallback strings in localized string helpers' {
            $result = Get-UxLocalizedString -Key 'Missing_Key' -Fallback ''

            $result | Should -Be ''
        }

        It 'uses non-empty fallback text when a non-English locale is missing a GUI key' {
            $previousLanguage = [System.Environment]::GetEnvironmentVariable('BASELINE_LANGUAGE', 'Process')
            try {
                [System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', 'sq', 'Process')
                $Global:Localization = @{}

                Get-UxLocalizedString -Key 'Missing_Gui_Key' -Fallback 'Required label' | Should -Be 'Required label'
            }
            finally {
                [System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', $previousLanguage, 'Process')
            }
        }

        It 'recommends the Basic preset outside Safe Mode' {
            Get-UxRecommendedPresetName | Should -Be 'Basic'
        }

        It 'recommends the Advanced preset in Expert Mode' {
            $script:AdvancedMode = $true

            Get-UxRecommendedPresetName | Should -Be 'Advanced'
        }

        It 'uses the legacy action labels in standard mode' {
            Get-UxRunActionLabel | Should -Be 'Run Tweaks'
            Get-UxUndoSelectionActionLabel | Should -Be 'Restore Snapshot'
            Get-UxUndoProfileActionLabel | Should -Be 'Export Rollback Profile'
        }

        It 'switches to Save Config in Design Mode' {
            $script:DesignMode = $true

            Get-UxRunActionLabel | Should -Match '^Save Config'
            (Get-UxMainWindowTitleText) | Should -Match 'Design Mode'
            (Get-UxMainWindowTitleText) | Should -Match 'Windows Server 2022'
        }

        It 'uses Undo Selection Change in Expert Mode' {
            $script:AdvancedMode = $true

            Get-UxRunActionLabel | Should -Be 'Run Tweaks'
            Get-UxUndoSelectionActionLabel | Should -Be 'Undo Selection Change'
            Get-UxUndoProfileActionLabel | Should -Be 'Export Rollback Profile'
        }

        It 'switches to the Safe Mode recommendation set when Safe Mode is enabled' {
            $script:SafeMode = $true

            Get-UxRecommendedPresetName | Should -Be 'Minimal'
            Get-UxRunActionLabel | Should -Be 'Run Tweaks'
            Get-UxUndoSelectionActionLabel | Should -Be 'Undo Selection Change'
            Get-UxUndoProfileActionLabel | Should -Be 'Export Undo Profile'
        }

        It 'returns the expected quick-start sequence in Safe Mode' {
            $script:SafeMode = $true
            $steps = @(Get-UxQuickStartSteps)

            $steps | Should -HaveCount 3
            $steps[0] | Should -Be 'Choose a preset - Minimal is recommended for most users.'
            $steps[1] | Should -Be 'Click Preview Run to see what will change.'
            $steps[2] | Should -Be 'Click Run Tweaks to apply.'
        }

        It 'summarizes undo and restore paths for beginners in Safe Mode' {
            $script:SafeMode = $true
            $lines = @(Get-UxUndoAndRestoreLines)

            ($lines -join ' ') | Should -Match 'Undo Selection Change'
            ($lines -join ' ') | Should -Match 'Restore Defaults'
            ($lines -join ' ') | Should -Match 'Export Undo Profile'
        }

        It 'builds a first-run welcome message with preview and recovery guidance' {
            $script:SafeMode = $true
            $message = Get-UxFirstRunWelcomeMessage

            $message | Should -Match 'Baseline helps you safely optimize Windows settings'
            $message | Should -Match 'You can safely explore Baseline before applying changes'
            $message | Should -Match 'Preview Run shows what will change'
            $message | Should -Match 'Undo reverses your last changes'
            $message | Should -Match 'Restore to Defaults resets supported settings'
            $message | Should -Match 'Start Guide:'
            $message | Should -Match '3\. Run Tweaks'
        }

        It 'switches the start guide to Expert wording when Expert Mode is enabled' {
            $script:SafeMode = $true
            $script:AdvancedMode = $true

            Get-UxFirstRunPrimaryActionLabel | Should -Be 'Start with Advanced'
            @(Get-UxQuickStartSteps)[0] | Should -Be 'Load Advanced to start from the full expert preset, or customize individual tweaks.'

            $message = Get-UxFirstRunWelcomeMessage
            $message | Should -Match 'Expert Mode unlocks all presets, including advanced and high-risk tweaks'
            $message | Should -Match 'Advanced is the recommended starting point and loads the broadest selection'
            $message | Should -Match '3\. Run Tweaks'
        }

        It 'uses the mode-aware preset-loaded status text' {
            Get-UxPresetLoadedStatusText -PresetName 'Basic' | Should -Be 'Basic loaded. Use Preview Run before applying it.'

            $script:SafeMode = $true
            Get-UxPresetLoadedStatusText -PresetName 'Minimal' | Should -Be 'Quick Start loaded. Use Preview Run before applying it.'

            $script:SafeMode = $false
            $script:AdvancedMode = $true
            Get-UxPresetLoadedStatusText -PresetName 'Advanced' | Should -Be 'Advanced loaded. Use Preview Run before applying it.'
        }
    }

    Describe 'Get-UxPresetEmphasisText' {
        It 'promotes Minimal in Safe Mode' {
            $script:SafeMode = $true

            Get-UxPresetEmphasisText | Should -Match 'Quick Start is recommended'
            Get-UxPresetEmphasisText | Should -Match 'your first run'
            Get-UxPresetEmphasisText | Should -Not -Match '\{0\}'
            Get-UxPresetEmphasisText | Should -Not -Match '^Start here'
        }

        It 'formats the localized Safe Mode preset emphasis instead of exposing placeholders' {
            $script:SafeMode = $true
            $Global:Localization = @{
                GuiPresetQuickStart = 'Quick Start'
                GuiPresetStartHereEmphasis = '{0} is recommended for your first run.'
            }

            Get-UxPresetEmphasisText | Should -Be 'Quick Start is recommended for your first run.'
        }

        It 'keeps the original non-Safe preset emphasis' {
            Get-UxPresetEmphasisText | Should -Be 'Use these shortcuts to start from a sensible baseline before fine-tuning individual tweaks.'
        }

        It 'uses Advanced-first preset emphasis in Expert Mode' {
            $script:AdvancedMode = $true

            Get-UxPresetEmphasisText | Should -Match 'Start with Advanced'
            Get-UxPresetSummaryText | Should -Match 'Advanced is the expert starting point in Expert Mode'
        }
    }

    Describe 'Get-UxHelpSections' {
        It 'keeps the original non-Safe help content outside Safe Mode' {
            $sections = Get-UxHelpSections

            $sections.Keys | Should -Contain 'Quick Start'
            $sections.Keys | Should -Contain 'Import / Export / Session Restore'
            $sections.Keys | Should -Contain 'Remote Management'
            ($sections['Presets'] -join ' ') | Should -Match 'Basic is the recommended default for normal users'
            ($sections['Remote Management'] -join ' ') | Should -Match 'CLI only'
            ($sections['Remote Management'] -join ' ') | Should -Match 'WinRM'
        }

        It 'keeps Safe Mode help aligned with the Minimal recommendation' {
            $script:SafeMode = $true
            $sections = Get-UxHelpSections

            ($sections['Presets'] -join ' ') | Should -Match 'Minimal is the recommended preset for most users'
            ($sections['Start Guide'] -join ' ') | Should -Match 'reference material'
            ($sections['Start Guide'] -join ' ') | Should -Not -Match 'Choose a preset'
            $sections.Keys | Should -Contain 'Import / Export'
            $sections.Keys | Should -Contain 'Remote Management'
            ($sections['Remote Management'] -join ' ') | Should -Match 'one machine first'
        }

        It 'keeps Expert Mode on the original full-detail copy' {
            $script:AdvancedMode = $true
            $sections = Get-UxHelpSections

            $sections.Keys | Should -Contain 'Run Tweaks'
            $sections.Keys | Should -Contain 'Import / Export / Session Restore'
            ($sections['Presets'] -join ' ') | Should -Match 'Minimal, Basic, Balanced, Advanced load from preset files'
            $sections.Keys | Should -Contain 'Remote Management'
            ($sections['Remote Management'] -join ' ') | Should -Match 'connection layer'
            ($sections['Remote Management'] -join ' ') | Should -Match 'per-machine execution reporting'
        }

        It 'switches Expert Mode help to Game Mode workflow content when Game Mode is active' {
            $script:AdvancedMode = $true
            $script:GameMode = $true
            $script:GameModeProfile = 'Competitive'
            $script:GuiDisplayVersion = 'v1.0.0'

            Get-UxHelpDialogSubtitle | Should -Be 'Game Mode workflow and execution help - v1.0.0'

            $sections = Get-UxHelpSections

            $sections.Keys | Should -Contain 'Game Mode Workflow'
            $sections.Keys | Should -Contain 'Profiles and Plan Building'
            $sections.Keys | Should -Contain 'Advanced Options'
            $sections.Keys | Should -Not -Contain 'Quick Start'
            $sections.Keys | Should -Not -Contain 'Presets'
            ($sections['Game Mode Workflow'] -join ' ') | Should -Match 'Competitive'
            ($sections['Game Mode Workflow'] -join ' ') | Should -Match 'only the Gaming tab plan can be edited or run'
            ($sections['Preview Run'] -join ' ') | Should -Match 'active Game Mode plan'
            ($sections['Profiles and Plan Building'] -join ' ') | Should -Match 'Casual, Competitive, Streaming, and Troubleshooting'
        }

        It 'adds a server validation warning to preview summaries on Windows Server' {
            $summary = [pscustomobject]@{
                SelectedCount = 2
                HighRiskCount = 0
                MediumRiskCount = 0
                ShouldRecommendRestorePoint = $false
                RestoreRecommendation = $null
                RestoreRecommendationSeverity = $null
                DirectUndoEligibleCount = 0
                Categories = @()
                CategoryText = ''
            }

            $parts = @(Get-UxPreviewSummaryParts -Summary $summary -IsGameModePreview:$false -AlreadyDesiredCount 0 -WillChangeCount 1 -RequiresRestartCount 0 -NotFullyRestorablePreviewCount 0 -AdvancedTierCount 0)

            ($parts -join ' ') | Should -Match 'Server validation outside CI remains CI only'
        }
    }
}
