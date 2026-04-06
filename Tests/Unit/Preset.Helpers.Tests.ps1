Set-StrictMode -Version Latest

BeforeAll {
    # Extract inner functions from the dot-sourced file via AST.
    # Uses Invoke-Expression on function definition AST nodes - safe because
    # ParseFile only parses (no execution) and we only evaluate FunctionDefinitionAst
    # nodes, which merely define functions without side effects.
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Preset.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'ConvertTo-HeadlessPresetName' {
    It 'returns Basic when input is null or empty' {
        ConvertTo-HeadlessPresetName -PresetName '' | Should -Be 'Basic'
        ConvertTo-HeadlessPresetName -PresetName '  ' | Should -Be 'Basic'
        ConvertTo-HeadlessPresetName | Should -Be 'Basic'
    }

    It 'normalizes Minimal (case-insensitive)' {
        ConvertTo-HeadlessPresetName -PresetName 'minimal' | Should -Be 'Minimal'
        ConvertTo-HeadlessPresetName -PresetName 'MINIMAL' | Should -Be 'Minimal'
        ConvertTo-HeadlessPresetName -PresetName '  Minimal  ' | Should -Be 'Minimal'
    }

    It 'normalizes Balanced (case-insensitive)' {
        ConvertTo-HeadlessPresetName -PresetName 'balanced' | Should -Be 'Balanced'
        ConvertTo-HeadlessPresetName -PresetName 'BALANCED' | Should -Be 'Balanced'
    }

    It 'normalizes Basic and the Safe alias' {
        ConvertTo-HeadlessPresetName -PresetName 'basic' | Should -Be 'Basic'
        ConvertTo-HeadlessPresetName -PresetName 'Basic' | Should -Be 'Basic'
        ConvertTo-HeadlessPresetName -PresetName 'safe' | Should -Be 'Basic'
        ConvertTo-HeadlessPresetName -PresetName 'Safe' | Should -Be 'Basic'
    }

    It 'normalizes Advanced and the Aggressive alias' {
        ConvertTo-HeadlessPresetName -PresetName 'advanced' | Should -Be 'Advanced'
        ConvertTo-HeadlessPresetName -PresetName 'Advanced' | Should -Be 'Advanced'
        ConvertTo-HeadlessPresetName -PresetName 'aggressive' | Should -Be 'Advanced'
        ConvertTo-HeadlessPresetName -PresetName 'Aggressive' | Should -Be 'Advanced'
    }

    It 'strips file extension before normalizing' {
        ConvertTo-HeadlessPresetName -PresetName 'Balanced.json' | Should -Be 'Balanced'
        ConvertTo-HeadlessPresetName -PresetName 'Advanced.txt' | Should -Be 'Advanced'
    }

    It 'throws on unknown preset name' {
        { ConvertTo-HeadlessPresetName -PresetName 'Nonexistent' } | Should -Throw '*Unknown preset name*'
    }
}

Describe 'Get-HeadlessPresetCommandList' {
    BeforeAll {
        $moduleRoot = Join-Path $PSScriptRoot '../../Module'
    }

    It 'loads commands from a valid JSON preset file' {
        $commands = Get-HeadlessPresetCommandList -PresetName 'Basic' -ModuleRoot $moduleRoot

        $commands | Should -Not -BeNullOrEmpty
        $commands.Count | Should -BeGreaterThan 0
        foreach ($cmd in $commands) {
            $cmd | Should -Not -BeNullOrEmpty
            $cmd | Should -BeOfType [string]
        }
    }

    It 'returns distinct function names (last-wins dedup)' {
        $commands = Get-HeadlessPresetCommandList -PresetName 'Basic' -ModuleRoot $moduleRoot
        $functionNames = @($commands | ForEach-Object { ($_ -split '\s+', 2)[0] })
        $unique = @($functionNames | Select-Object -Unique)

        $unique.Count | Should -Be $functionNames.Count
    }

    It 'resolves alias names like Safe to Basic' {
        $commandsBasic = Get-HeadlessPresetCommandList -PresetName 'Basic' -ModuleRoot $moduleRoot
        $commandsSafe = Get-HeadlessPresetCommandList -PresetName 'safe' -ModuleRoot $moduleRoot

        # Safe is an alias for Basic, so they should produce the same commands
        $commandsBasic.Count | Should -Be $commandsSafe.Count
    }

    It 'throws for a nonexistent preset' {
        { Get-HeadlessPresetCommandList -PresetName 'DoesNotExist' -ModuleRoot $moduleRoot } | Should -Throw
    }

    It 'throws when preset directory does not exist' {
        { Get-HeadlessPresetCommandList -PresetName 'Basic' -ModuleRoot '/nonexistent/path' } | Should -Throw '*Preset directory*'
    }
}

Describe 'ConvertTo-TweakPresetTier' {
    BeforeAll {
        # ConvertTo-TweakPresetTier lives in Manifest.Helpers.ps1 - extract it too
        $manifestPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Manifest.Helpers.ps1'
        $ast2 = [System.Management.Automation.Language.Parser]::ParseFile($manifestPath, [ref]$null, [ref]$null)
        $functions2 = $ast2.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions2) {
            if ($fn.Name -eq 'ConvertTo-TweakPresetTier') {
                Invoke-Expression $fn.Extent.Text
            }
        }
    }

    It 'returns the explicit value when a valid tier string is provided' {
        ConvertTo-TweakPresetTier -Value 'Advanced' | Should -Be 'Advanced'
        ConvertTo-TweakPresetTier -Value 'Balanced' | Should -Be 'Balanced'
        ConvertTo-TweakPresetTier -Value 'Minimal' | Should -Be 'Minimal'
    }

    It 'normalizes aliases (aggressive -> Advanced, safe -> Basic)' {
        ConvertTo-TweakPresetTier -Value 'aggressive' | Should -Be 'Advanced'
        ConvertTo-TweakPresetTier -Value 'safe' | Should -Be 'Basic'
    }

    It 'defaults to Basic when Value is null or empty' {
        ConvertTo-TweakPresetTier -Value $null | Should -Be 'Basic'
        ConvertTo-TweakPresetTier -Value '' | Should -Be 'Basic'
    }

    It 'falls back to Basic for unknown string values' {
        ConvertTo-TweakPresetTier -Value 'UnknownTier' | Should -Be 'Basic'
    }

    It 'returns Advanced when Risk is High' {
        ConvertTo-TweakPresetTier -Value $null -Risk 'High' | Should -Be 'Advanced'
    }

    It 'returns Balanced when Risk is Medium' {
        ConvertTo-TweakPresetTier -Value $null -Risk 'Medium' | Should -Be 'Balanced'
    }

    It 'returns Advanced when Impact is true' {
        ConvertTo-TweakPresetTier -Value $null -Impact $true | Should -Be 'Advanced'
    }

    It 'explicit Value takes precedence over Risk and Impact' {
        ConvertTo-TweakPresetTier -Value 'Minimal' -Risk 'High' -Impact $true | Should -Be 'Minimal'
    }
}
