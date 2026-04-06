Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AdvancedStartup.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    function LogInfo {}
    function LogWarning {}
}

Describe 'Get-AdvancedStartupAssetPath' {
    It 'resolves the first matching asset under the shared helpers repo root' {
        $script:SharedHelpersRepoRoot = Join-Path $TestDrive 'repo'
        $assetsRoot = Join-Path $script:SharedHelpersRepoRoot 'Assets'
        $null = New-Item -ItemType Directory -Path $assetsRoot -Force
        $iconPath = Join-Path $assetsRoot 'troubleshoot.ico'
        Set-Content -LiteralPath $iconPath -Value 'ico' -Encoding ASCII

        $result = Get-AdvancedStartupAssetPath -FileName 'troubleshoot.ico'

        $result | Should -Be ([System.IO.Path]::GetFullPath($iconPath))
    }
}

Describe 'Get-AdvancedStartupShortcutArguments' {
    It 'encodes a ShellExecute launcher for the provided command path' {
        $arguments = Get-AdvancedStartupShortcutArguments -CommandPath 'C:\ProgramData\Baseline\AdvancedStartup.cmd'
        $encodedCommand = ($arguments -split 'EncodedCommand ', 2)[1]
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encodedCommand))

        $arguments | Should -Match '^-NoProfile -WindowStyle Hidden -EncodedCommand '
        $decoded | Should -Match 'ShellExecute'
        $decoded | Should -Match 'AdvancedStartup\.cmd'
        $decoded | Should -Match 'runas'
    }
}
