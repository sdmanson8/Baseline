Set-StrictMode -Version Latest

BeforeAll {
    $script:filePath = Join-Path $PSScriptRoot '../../Module/Regions/System.psm1'
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:filePath, [ref]$null, [ref]$null)

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

Describe 'NumLock registry writes' {
    It 'writes .DEFAULT keyboard values through Set-RegistryValueSafe' {
        $safeWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Set-RegistryValueSafe'
                }, $true))

        foreach ($value in @('2147483650', '2147483648')) {
            @($safeWrites | Where-Object {
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Path') -eq 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' -and
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Value') -eq $value
                }).Count | Should -BeGreaterOrEqual 1
        }
    }

    It 'does not write .DEFAULT keyboard values through New-ItemProperty' {
        $directWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'New-ItemProperty' -and
                    $node.Extent.Text -match 'Registry::HKEY_USERS\\.DEFAULT\\Control Panel\\Keyboard' -and
                    $node.Extent.Text -match 'InitialKeyboardIndicators'
                }, $true))

        $directWrites.Count | Should -Be 0
    }
}
