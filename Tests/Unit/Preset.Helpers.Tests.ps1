Set-StrictMode -Version Latest

BeforeAll {
    # Json helpers must load first - Preset.Helpers calls ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    # Read inner functions from the loaded file via AST.
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

    It 'normalizes dotted gaming aliases without treating them as file paths' {
        ConvertTo-HeadlessPresetName -PresetName 'gaming.only' | Should -Be 'Balanced'
        ConvertTo-HeadlessPresetName -PresetName 'optimized.for.gaming' | Should -Be 'Balanced'
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

    It 'rejects path-like preset tokens' {
        { ConvertTo-HeadlessPresetName -PresetName '..\Basic' } | Should -Throw '*Invalid preset token*'
    }

    It 'rejects shell-meta preset tokens' {
        { ConvertTo-HeadlessPresetName -PresetName 'Basic;calc' } | Should -Throw '*Invalid preset token*'
    }
}

Describe 'Resolve-HeadlessEnvironmentPreset' {
    It 'returns null when the environment preset is blank' {
        Resolve-HeadlessEnvironmentPreset -EnvironmentPreset '' | Should -BeNullOrEmpty
        Resolve-HeadlessEnvironmentPreset -EnvironmentPreset $null | Should -BeNullOrEmpty
    }

    It 'normalizes valid environment preset values' {
        Resolve-HeadlessEnvironmentPreset -EnvironmentPreset 'Balanced.json' | Should -Be 'Balanced'
    }

    It 'rejects invalid environment preset values' {
        { Resolve-HeadlessEnvironmentPreset -EnvironmentPreset '..\Basic' } | Should -Throw '*Invalid preset token*'
    }
}

Describe 'Get-HeadlessPresetCommandList' {
    BeforeAll {
        $moduleRoot = Join-Path $PSScriptRoot '../../Module'
    }

    BeforeEach {
        Set-HeadlessPresetIncludedFunctionSet -FunctionNames @()
        Set-HeadlessPresetIncludedTweakLibraryPathSet -IncludePaths @()
    }

    AfterEach {
        Set-HeadlessPresetIncludedFunctionSet -FunctionNames @()
        Set-HeadlessPresetIncludedTweakLibraryPathSet -IncludePaths @()
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

    It 'accepts functions supplied by included tweak libraries' {
        $includeModuleRoot = Join-Path $TestDrive 'IncludedModule'
        $includeDataRoot = Join-Path $includeModuleRoot 'Data'
        $includePresetRoot = Join-Path $includeDataRoot 'Presets'
        New-Item -ItemType Directory -Path $includePresetRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $includeDataRoot 'System.json') -Encoding UTF8 -Value @'
{
  "Tab": "System",
  "Entries": [
    {
      "Name": "Known Tweak",
      "Function": "KnownFunction",
      "Type": "Toggle",
      "Default": false
    }
  ]
}
'@

        Set-Content -LiteralPath (Join-Path $includePresetRoot 'Include.txt') -Encoding UTF8 -Value @'
KnownFunction -Enable
CustomFunction -Disable
'@

        { Get-HeadlessPresetCommandList -PresetName (Join-Path $includePresetRoot 'Include.txt') -ModuleRoot $includeModuleRoot } | Should -Throw '*CustomFunction*'

        Set-HeadlessPresetIncludedFunctionSet -FunctionNames @('CustomFunction')
        $commands = Get-HeadlessPresetCommandList -PresetName (Join-Path $includePresetRoot 'Include.txt') -ModuleRoot $includeModuleRoot

        $commands.Count | Should -Be 2
        $commands | Should -Contain 'KnownFunction -Enable'
        $commands | Should -Contain 'CustomFunction -Disable'
    }

    It 'tracks included tweak library paths separately from included functions' {
        Set-HeadlessPresetIncludedTweakLibraryPathSet -IncludePaths @(
            '  C:\Libraries\First.psm1  '
            'C:\Libraries\FIRST.psm1'
            'C:\Libraries\Second.psd1'
        )

        $paths = @(Get-HeadlessPresetIncludedTweakLibraryPathSet)
        $paths.Count | Should -Be 2
        $paths | Should -Contain 'C:\Libraries\First.psm1'
        $paths | Should -Contain 'C:\Libraries\Second.psd1'
    }

    It 'supports !function removal directives in text presets' {
        $removeModuleRoot = Join-Path $TestDrive 'RemovalTextModule'
        $removeDataRoot = Join-Path $removeModuleRoot 'Data'
        $removePresetRoot = Join-Path $removeDataRoot 'Presets'
        New-Item -ItemType Directory -Path $removePresetRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $removeDataRoot 'System.json') -Encoding UTF8 -Value @'
{
  "Tab": "System",
  "Entries": [
    {
      "Name": "Known Tweak",
      "Function": "KnownFunction",
      "Type": "Toggle",
      "Default": false
    },
    {
      "Name": "Other Tweak",
      "Function": "OtherFunction",
      "Type": "Toggle",
      "Default": false
    }
  ]
}
'@

        Set-Content -LiteralPath (Join-Path $removePresetRoot 'Removal.txt') -Encoding UTF8 -Value @'
KnownFunction -Enable
OtherFunction -Disable
!KnownFunction
'@

        $commands = @(Get-HeadlessPresetCommandList -PresetName (Join-Path $removePresetRoot 'Removal.txt') -ModuleRoot $removeModuleRoot)

        $commands.Count | Should -Be 1
        $commands[0] | Should -Be 'OtherFunction -Disable'
    }

    It 'supports explicit Remove actions in JSON presets' {
        $removeJsonModuleRoot = Join-Path $TestDrive 'RemovalJsonModule'
        $removeJsonDataRoot = Join-Path $removeJsonModuleRoot 'Data'
        $removeJsonPresetRoot = Join-Path $removeJsonDataRoot 'Presets'
        New-Item -ItemType Directory -Path $removeJsonPresetRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $removeJsonDataRoot 'System.json') -Encoding UTF8 -Value @'
{
  "Tab": "System",
  "Entries": [
    {
      "Name": "Known Tweak",
      "Function": "KnownFunction",
      "Type": "Toggle",
      "Default": false
    },
    {
      "Name": "Other Tweak",
      "Function": "OtherFunction",
      "Type": "Toggle",
      "Default": false
    }
  ]
}
'@

        Set-Content -LiteralPath (Join-Path $removeJsonPresetRoot 'Removal.json') -Encoding UTF8 -Value @'
{
  "Name": "Removal",
  "Entries": [
    {
      "Action": "Add",
      "Command": "KnownFunction -Enable"
    },
    {
      "Action": "Add",
      "Command": "OtherFunction -Disable"
    },
    {
      "Action": "Remove",
      "Function": "KnownFunction"
    }
  ]
}
'@

        $commands = @(Get-HeadlessPresetCommandList -PresetName (Join-Path $removeJsonPresetRoot 'Removal.json') -ModuleRoot $removeJsonModuleRoot)

        $commands.Count | Should -Be 1
        $commands[0] | Should -Be 'OtherFunction -Disable'
    }

    It 'throws before execution when a preset references an unknown manifest function' {
        $brokenModuleRoot = Join-Path $TestDrive 'BrokenModule'
        $brokenDataRoot = Join-Path $brokenModuleRoot 'Data'
        $brokenPresetRoot = Join-Path $brokenDataRoot 'Presets'
        New-Item -ItemType Directory -Path $brokenPresetRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $brokenDataRoot 'System.json') -Encoding UTF8 -Value @'
{
  "Tab": "System",
  "Entries": [
    {
      "Name": "Known Tweak",
      "Function": "KnownFunction",
      "Type": "Toggle",
      "Default": false
    }
  ]
}
'@

        Set-Content -LiteralPath (Join-Path $brokenPresetRoot 'Broken.json') -Encoding UTF8 -Value @'
{
  "Name": "Broken",
  "Entries": [
    "KnownFunction -Enable",
    "MissingFunction -Disable"
  ]
}
'@

        $brokenPresetPath = Join-Path $brokenPresetRoot 'Broken.json'

        {
            Get-HeadlessPresetCommandList -PresetName $brokenPresetPath -ModuleRoot $brokenModuleRoot
        } | Should -Throw '*MissingFunction*'
    }

    It 'can warn instead of throwing for unknown preset functions' {
        $warnModuleRoot = Join-Path $TestDrive 'WarnOnlyModule'
        $warnDataRoot = Join-Path $warnModuleRoot 'Data'
        $warnPresetRoot = Join-Path $warnDataRoot 'Presets'
        New-Item -ItemType Directory -Path $warnPresetRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $warnDataRoot 'System.json') -Encoding UTF8 -Value @'
{
  "Tab": "System",
  "Entries": [
    {
      "Name": "Known Tweak",
      "Function": "KnownFunction",
      "Type": "Toggle",
      "Default": false
    }
  ]
}
'@

        Set-Content -LiteralPath (Join-Path $warnPresetRoot 'WarnOnly.json') -Encoding UTF8 -Value @'
{
  "Name": "WarnOnly",
  "Entries": [
    "KnownFunction -Enable",
    "MissingFunction -Disable"
  ]
}
'@

        Mock Write-Warning {}

        $warnPresetPath = Join-Path $warnPresetRoot 'WarnOnly.json'
        $commands = Get-HeadlessPresetCommandList -PresetName $warnPresetPath -ModuleRoot $warnModuleRoot -WarningOnly

        $commands.Count | Should -Be 2
        Should -Invoke Write-Warning -Times 1 -ParameterFilter {
            $Message -like '*MissingFunction*'
        }
    }
}

Describe 'ConvertTo-TweakPresetTier' {
    BeforeAll {
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
        ConvertTo-TweakPresetTier -Value 'Standard' | Should -Be 'Standard'
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
