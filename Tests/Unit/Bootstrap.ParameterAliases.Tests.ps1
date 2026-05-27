Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Bootstrap/Baseline.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $script:profilePathParameter = $ast.ParamBlock.Parameters | Where-Object {
        $_.Name.VariablePath.UserPath -eq 'ProfilePath'
    } | Select-Object -First 1
}

Describe 'Bootstrap parameter aliases' {
    It 'keeps ConfigFile as the only alias for ProfilePath' {
        $script:profilePathParameter | Should -Not -BeNullOrEmpty

        $aliasAttribute = $script:profilePathParameter.Attributes | Where-Object {
            $_.TypeName.FullName -eq 'Alias'
        } | Select-Object -First 1

        $aliasAttribute | Should -Not -BeNullOrEmpty

        $aliases = @($aliasAttribute.PositionalArguments | ForEach-Object { $_.Value })

        $aliases | Should -Be @('ConfigFile')
    }
}
