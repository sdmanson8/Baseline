Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Bootstrap/Bootstrap.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'Resolve-RawBootstrapPreset') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Resolve-RawBootstrapPreset' {
    It 'returns the explicit preset when it is valid' {
        $result = Resolve-RawBootstrapPreset -Preset 'Basic' -EnvironmentPreset 'Balanced'

        $result | Should -Be 'Basic'
    }

    It 'falls back to the environment preset when explicit preset is blank' {
        $result = Resolve-RawBootstrapPreset -Preset '' -EnvironmentPreset 'Balanced'

        $result | Should -Be 'Balanced'
    }

    It 'returns null when neither explicit nor environment preset is set' {
        $result = Resolve-RawBootstrapPreset -Preset $null -EnvironmentPreset $null

        $result | Should -BeNullOrEmpty
    }

    It 'rejects path-like preset values' {
        { Resolve-RawBootstrapPreset -Preset '..\Basic' -EnvironmentPreset $null } | Should -Throw '*Invalid preset token*'
    }

    It 'rejects shell-meta preset values from the environment' {
        { Resolve-RawBootstrapPreset -Preset $null -EnvironmentPreset 'Basic;calc' } | Should -Throw '*Invalid preset token*'
    }
}
