Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/UxPolicy.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    $script:Localization = $null
}

Describe 'UxPolicy' {
    BeforeEach {
        $script:SafeMode = $false
        $script:AdvancedMode = $false
        $script:GameMode = $false
        $script:GameModeProfile = $null
    }

    Describe 'Beginner UX helpers' {
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
            ($lines -join ' ') | Should -Match 'Restore to Windows Defaults'
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

            $sections.Keys | Should -Contain 'Getting Started'
            $sections.Keys | Should -Contain 'Import / Export / Session Restore'
            ($sections['Presets'] -join ' ') | Should -Match 'Basic is the recommended default for normal users'
        }

        It 'keeps Safe Mode help aligned with the Minimal recommendation' {
            $script:SafeMode = $true
            $sections = Get-UxHelpSections

            ($sections['Presets'] -join ' ') | Should -Match 'Minimal is the recommended preset for most users'
            $sections.Keys | Should -Contain 'Import / Export'
        }

        It 'keeps Expert Mode on the original full-detail copy' {
            $script:AdvancedMode = $true
            $sections = Get-UxHelpSections

            $sections.Keys | Should -Contain 'Run Tweaks'
            $sections.Keys | Should -Contain 'Import / Export / Session Restore'
            ($sections['Presets'] -join ' ') | Should -Match 'Minimal, Basic, Balanced, Advanced load from preset files'
        }

        It 'switches Expert Mode help to Game Mode workflow content when Game Mode is active' {
            $script:AdvancedMode = $true
            $script:GameMode = $true
            $script:GameModeProfile = 'Competitive'

            Get-UxHelpDialogSubtitle | Should -Be 'Game Mode workflow and execution help'

            $sections = Get-UxHelpSections

            $sections.Keys | Should -Contain 'Game Mode Workflow'
            $sections.Keys | Should -Contain 'Profiles and Plan Building'
            $sections.Keys | Should -Contain 'Advanced Options'
            $sections.Keys | Should -Not -Contain 'Getting Started'
            $sections.Keys | Should -Not -Contain 'Presets'
            ($sections['Game Mode Workflow'] -join ' ') | Should -Match 'Competitive'
            ($sections['Game Mode Workflow'] -join ' ') | Should -Match 'only the Gaming tab plan can be edited or run'
            ($sections['Preview Run'] -join ' ') | Should -Match 'active Game Mode plan'
            ($sections['Profiles and Plan Building'] -join ' ') | Should -Match 'Casual, Competitive, Streaming, and Troubleshooting'
        }
    }
}
