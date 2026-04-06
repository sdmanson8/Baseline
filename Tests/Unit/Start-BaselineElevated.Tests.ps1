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
    It 'builds the hidden elevated PowerShell argument list for Baseline.ps1' {
        $result = @(New-BaselineLauncherArgumentList -ScriptPath 'C:\Baseline\Baseline.ps1')

        $result | Should -Be @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-WindowStyle'
            'Hidden'
            '-STA'
            '-File'
            'C:\Baseline\Baseline.ps1'
        )
    }

    It 'appends forwarded arguments without rewriting or flattening them' {
        $result = @(New-BaselineLauncherArgumentList -ScriptPath 'C:\Baseline\Baseline.ps1' -ForwardedArguments @(
            '-Preset'
            'Basic'
            '-Functions'
            'DiagTrackService -Disable'
        ))

        $result | Should -Be @(
            '-NoProfile'
            '-ExecutionPolicy'
            'Bypass'
            '-WindowStyle'
            'Hidden'
            '-STA'
            '-File'
            'C:\Baseline\Baseline.ps1'
            '-Preset'
            'Basic'
            '-Functions'
            'DiagTrackService -Disable'
        )
    }
}
