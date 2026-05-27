Set-StrictMode -Version Latest

BeforeAll {
    $script:filePath = Join-Path $PSScriptRoot '../../Module/Regions/StartMenu.psm1'
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:filePath, [ref]$null, [ref]$null)
    $script:webSearch = $script:ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'WebSearch'
        }, $true)

    function Get-CommandParameterValue {
        param(
            [System.Management.Automation.Language.CommandAst]$Command,
            [string]$ParameterName
        )

        for ($i = 0; $i -lt $Command.CommandElements.Count; $i++) {
            $element = $Command.CommandElements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                $element.ParameterName -eq $ParameterName -and
                ($i + 1) -lt $Command.CommandElements.Count) {
                return $Command.CommandElements[$i + 1].Extent.Text.Trim('"', "'")
            }
        }

        return $null
    }
}

Describe 'StartMenu WebSearch registry writes' {
    It 'writes HKCU search values through Set-RegistryValueSafe' {
        $safeWrites = @($script:webSearch.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Set-RegistryValueSafe'
                }, $true))

        foreach ($name in @('BingSearchEnabled', 'CortanaConsent')) {
            @($safeWrites | Where-Object {
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Path') -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -and
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Name') -eq $name
                }).Count | Should -BeGreaterOrEqual 1
        }
    }

    It 'does not write HKCU search values through Set-ItemProperty' {
        $directWrites = @($script:webSearch.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Set-ItemProperty' -and
                    $node.Extent.Text -match 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search' -and
                    $node.Extent.Text -match '(BingSearchEnabled|CortanaConsent)'
                }, $true))

        $directWrites.Count | Should -Be 0
    }
}
