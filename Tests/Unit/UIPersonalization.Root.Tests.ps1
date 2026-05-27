Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
}

Describe 'UIPersonalization root registry migration' {
    It 'routes TrayIcons NoAutoTrayNotify through Set-RegistryValueSafe' {
        $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'TrayIcons'
        }, $true)

        $functionAst | Should -Not -BeNullOrEmpty

        $safeCalls = @($functionAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Set-RegistryValueSafe' -and
                $node.Extent.Text -match 'NoAutoTrayNotify'
        }, $true))

        $safeCalls.Count | Should -Be 1
    }

    It 'does not use direct registry value writers for TrayIcons NoAutoTrayNotify' {
        $functionAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'TrayIcons'
        }, $true)

        $directCalls = @($functionAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                @('New-ItemProperty', 'Set-ItemProperty') -contains $node.GetCommandName() -and
                $node.Extent.Text -match 'NoAutoTrayNotify'
        }, $true))

        $directCalls | Should -BeNullOrEmpty
    }
}
