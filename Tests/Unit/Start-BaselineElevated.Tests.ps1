Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Bootstrap/Start-BaselineElevated.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'New-BaselineLauncherArgumentList' {
    It 'returns forwarded launcher arguments unchanged' {
        $result = @(New-BaselineLauncherArgumentList -ForwardedArguments @(
            '-Preset'
            'Basic'
            '-Functions'
            'DiagTrackService -Disable'
        ))

        $result | Should -Be @(
            '-Preset'
            'Basic'
            '-Functions'
            'DiagTrackService -Disable'
        )
    }

    It 'returns an empty array when no forwarded arguments are supplied' {
        $result = @(New-BaselineLauncherArgumentList)

        $result | Should -Be @()
    }
}
