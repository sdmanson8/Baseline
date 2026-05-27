Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Bootstrap/Helpers/Bootstrap.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Get-HeadlessCommandInvocation', 'ConvertTo-HeadlessCommandArgumentLiteral')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Get-HeadlessCommandInvocation' {
    It 'binds switch parameters as named arguments' {
        $cmdAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'RemoteCommands -Disable',
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

    It 'emits PowerShell literals for profile values that need quoting' {
        ConvertTo-HeadlessCommandArgumentLiteral -Value 'C:\Path With Space\file.txt' | Should -Be "'C:\Path With Space\file.txt'"
        ConvertTo-HeadlessCommandArgumentLiteral -Value "Bob's value" | Should -Be "'Bob''s value'"
        ConvertTo-HeadlessCommandArgumentLiteral -Value @('alpha beta', "gamma's") | Should -Be "@('alpha beta', 'gamma''s')"
    }

    It 'preserves spaces, quotes, and date-shaped values through profile command parsing' {
        $pathValue = 'C:\Path With Space\file.txt'
        $labelValue = "Bob's ""quoted"" value"
        $dateValue = '2026-05-11'
        $commandText = 'ExampleCommand -Path {0} -Label {1} -StartDate {2}' -f @(
            ConvertTo-HeadlessCommandArgumentLiteral -Value $pathValue
            ConvertTo-HeadlessCommandArgumentLiteral -Value $labelValue
            ConvertTo-HeadlessCommandArgumentLiteral -Value $dateValue
        )
        $cmdAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $commandText,
            [ref]$null,
            [ref]$null
        ).EndBlock.Statements[0].PipelineElements[0]

        $result = Get-HeadlessCommandInvocation -CommandAst $cmdAst

        $result.NamedArguments['Path'] | Should -Be $pathValue
        $result.NamedArguments['Label'] | Should -Be $labelValue
        $result.NamedArguments['StartDate'] | Should -Be $dateValue
        $result.DisplayArguments | Should -Be @(
            "-Path 'C:\Path With Space\file.txt'"
            "-Label 'Bob''s ""quoted"" value'"
            "-StartDate '2026-05-11'"
        )
    }
}
