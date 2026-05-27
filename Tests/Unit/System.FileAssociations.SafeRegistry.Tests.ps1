Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.FileAssociations.psm1'
    $sourceText = Get-BaselineTestSourceText -Path $script:filePath
    $script:ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$null, [ref]$null)

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

Describe 'System.FileAssociations registry writes' {
    It 'writes .DEFAULT file-association values through Set-RegistryValueSafe' {
        $safeWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Set-RegistryValueSafe'
                }, $true))

        @($safeWrites | Where-Object {
                (Get-CommandParameterValue -Command $_ -ParameterName 'Path') -eq 'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\FileAssociations\ProgIds' -and
                (Get-CommandParameterValue -Command $_ -ParameterName 'Name') -match '^_'
            }).Count | Should -BeGreaterOrEqual 1
    }

    It 'does not write .DEFAULT file-association values through New-ItemProperty' {
        $directWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'New-ItemProperty' -and
                    $node.Extent.Text -match 'Registry::HKEY_USERS\\.DEFAULT\\Software\\Microsoft\\Windows\\CurrentVersion\\FileAssociations\\ProgIds'
                }, $true))

        $directWrites.Count | Should -Be 0
    }

    It 'does not write HKCU file-association values through parent-scope New-ItemProperty or Set-ItemProperty commands' {
        $directWrites = @($script:ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in @('New-ItemProperty', 'Set-ItemProperty') -and
                    $node.Extent.Text -match 'HKCU:\\'
                }, $true))

        $directWrites.Count | Should -Be 0
    }
}
