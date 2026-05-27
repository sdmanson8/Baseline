Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AdvancedStartup.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    <#
        .SYNOPSIS
    #>

    function LogInfo {}
    <#
        .SYNOPSIS
    #>
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
    It 'writes a ShellExecute launcher file for the provided command path' {
        $commandPath = Join-Path $TestDrive 'Baseline\AdvancedStartup.cmd'
        $arguments = Get-AdvancedStartupShortcutArguments -CommandPath $commandPath
        $launcherPath = [System.IO.Path]::ChangeExtension($commandPath, '.ps1')
        $launcherContent = Get-BaselineTestSourceText -Path $launcherPath

        $arguments | Should -Match '^-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '
        $arguments | Should -Match ([regex]::Escape($launcherPath))
        $launcherContent | Should -Match 'ShellExecute'
        $launcherContent | Should -Match 'AdvancedStartup\.cmd'
        $launcherContent | Should -Match 'runas'
    }
}
