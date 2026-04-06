Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/GUI/ComponentFactory.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Format-TweakScenarioTag' {
    It 'uppercases known acronyms' {
        Format-TweakScenarioTag -Tag 'uwp' | Should -Be 'UWP'
        Format-TweakScenarioTag -Tag 'gpu' | Should -Be 'GPU'
        Format-TweakScenarioTag -Tag 'dns' | Should -Be 'DNS'
        Format-TweakScenarioTag -Tag 'smb' | Should -Be 'SMB'
        Format-TweakScenarioTag -Tag 'wmi' | Should -Be 'WMI'
    }

    It 'title-cases regular tags' {
        Format-TweakScenarioTag -Tag 'privacy' | Should -Be 'Privacy'
        Format-TweakScenarioTag -Tag 'gaming' | Should -Be 'Gaming'
        Format-TweakScenarioTag -Tag 'system' | Should -Be 'System'
    }

    It 'handles hyphenated tags' {
        $result = Format-TweakScenarioTag -Tag 'quality-of-life'
        $result | Should -Not -BeNullOrEmpty
    }

    It 'handles empty string' {
        Format-TweakScenarioTag -Tag '' | Should -BeIn @('', $null)
    }

    It 'handles null gracefully' {
        Format-TweakScenarioTag -Tag $null | Should -BeIn @('', $null)
    }

    It 'is case-insensitive for acronym matching' {
        Format-TweakScenarioTag -Tag 'UWP' | Should -Be 'UWP'
        Format-TweakScenarioTag -Tag 'Uwp' | Should -Be 'UWP'
    }
}
