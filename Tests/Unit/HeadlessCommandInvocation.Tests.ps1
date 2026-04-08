Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Baseline.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'Get-HeadlessCommandInvocation') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Get-HeadlessCommandInvocation' {
    It 'binds switch parameters as named arguments' {
        $cmdAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'Disable-RemoteCommands -Disable',
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]

        $result = Get-HeadlessCommandInvocation -CommandAst $cmdAst

        $result.NamedArguments['Disable'] | Should -BeTrue
        @($result.PositionalArguments).Count | Should -Be 0
        $result.DisplayArguments | Should -Be @('-Disable')
    }

    It 'binds list-valued named parameters' {
        $cmdAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'UnpinTaskbarShortcuts -Shortcuts Edge, Store, Outlook',
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]

        $result = Get-HeadlessCommandInvocation -CommandAst $cmdAst

        @($result.NamedArguments['Shortcuts']).Count | Should -Be 3
        @($result.NamedArguments['Shortcuts']) | Should -Be @('Edge', 'Store', 'Outlook')
        $result.DisplayArguments | Should -Be @('-Shortcuts Edge, Store, Outlook')
    }
}
