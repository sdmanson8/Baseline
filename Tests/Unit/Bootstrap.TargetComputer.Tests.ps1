Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Bootstrap/Baseline.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'ConvertTo-ValidatedTargetComputerList') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'ConvertTo-ValidatedTargetComputerList' {
    It 'returns trimmed hostnames and FQDNs' {
        $result = ConvertTo-ValidatedTargetComputerList -ComputerName @(' server01 ', 'api01.contoso.local')

        $result | Should -Be @('server01', 'api01.contoso.local')
    }

    It 'throws on invalid hostname characters' {
        { ConvertTo-ValidatedTargetComputerList -ComputerName @('server 01') } | Should -Throw '*Invalid -TargetComputer entry*'
    }

    It 'throws on IPv4 literals' {
        { ConvertTo-ValidatedTargetComputerList -ComputerName @('10.0.0.12') } | Should -Throw '*not an IP literal*'
    }
}
