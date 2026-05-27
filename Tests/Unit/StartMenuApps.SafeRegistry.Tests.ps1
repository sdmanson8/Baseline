Set-StrictMode -Version Latest

BeforeAll {
    $script:filePath = Join-Path $PSScriptRoot '../../Module/Regions/StartMenuApps.psm1'
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

Describe 'StartMenuApps registry writes' {
    It 'writes HKCU Start values through Set-RegistryValueSafe' {
        $safeWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Set-RegistryValueSafe'
                }, $true))

        foreach ($name in @('ShowFrequentList', 'ShowRecentList')) {
            @($safeWrites | Where-Object {
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Path') -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start' -and
                    (Get-CommandParameterValue -Command $_ -ParameterName 'Name') -eq $name
                }).Count | Should -BeGreaterOrEqual 1
        }
    }

    It 'does not write HKCU Start values through New-ItemProperty' {
        $directWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'New-ItemProperty' -and
                    $node.Extent.Text -match 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Start' -and
                    $node.Extent.Text -match '(ShowFrequentList|ShowRecentList)'
                }, $true))

        $directWrites.Count | Should -Be 0
    }
}
