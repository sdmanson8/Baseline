Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Tools/New-InstallerPackage.ps1'
    $script:InstallerPackageContent = Get-Content -LiteralPath $filePath -Raw
    $script:RepoRoot = Split-Path -Path (Split-Path -Path $filePath -Parent) -Parent
    $script:InstallerPackageAst = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $script:InstallerPackageAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Resolve-IsccPath' {
    BeforeEach {
        $script:OriginalProgramFiles = [System.Environment]::GetEnvironmentVariable('ProgramFiles', 'Process')
        $script:OriginalProgramFilesX86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)', 'Process')
    }

    AfterEach {
        [System.Environment]::SetEnvironmentVariable('ProgramFiles', $script:OriginalProgramFiles, 'Process')
        [System.Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $script:OriginalProgramFilesX86, 'Process')
    }

    It 'returns the requested path when it exists' {
        $requestedPath = Join-Path $TestDrive 'ISCC.exe'
        Set-Content -LiteralPath $requestedPath -Value '' -Encoding ASCII

        Resolve-IsccPath -RequestedPath $requestedPath | Should -Be $requestedPath
    }

    It 'returns null without throwing when no installation roots are defined' {
        [System.Environment]::SetEnvironmentVariable('ProgramFiles', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $null, 'Process')

        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'iscc.exe' }

        { Resolve-IsccPath } | Should -Not -Throw
        Resolve-IsccPath | Should -Be $null
    }
}

Describe 'Invoke-InstallerIscc' {
    It 'does not use the Start-Process wait parameter' {
        $commands = $script:InstallerPackageAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                [string]::Equals($node.GetCommandName(), 'Start-Process', [System.StringComparison]::OrdinalIgnoreCase)
        }, $true)

        $commands.Count | Should -BeGreaterThan 0
        foreach ($command in $commands) {
            $waitParameter = $command.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                    [string]::Equals($_.ParameterName, 'Wait', [System.StringComparison]::OrdinalIgnoreCase)
            }
            $waitParameter | Should -BeNullOrEmpty
        }
    }

    It 'bounds the Inno Setup compiler wait and kills the process tree on timeout' {
        $script:InstallerPackageContent | Should -Match '\[int\]\$IsccTimeoutSeconds = 3600'
        $script:InstallerPackageContent | Should -Match '\$process\.WaitForExit\(\$timeoutMilliseconds\)'
        $script:InstallerPackageContent | Should -Match 'Stop-BaselineProcessTree -Process \$process'
        $script:InstallerPackageContent | Should -Match 'NewInstallerPackage\.IsccTimeout'
        $script:InstallerPackageContent | Should -Match 'Invoke-InstallerIscc[\s\S]+-TimeoutSeconds \$IsccTimeoutSeconds'
    }
}

Describe 'Get-InstallerBuildLayout' {
    It 'uses short staging directory names for the installer payload' {
        $layout = Get-InstallerBuildLayout `
            -BaseTempPath 'C:\Users\runneradmin\AppData\Local\Temp' `
            -RootName 'BaselineInstaller_1234567890abcdef1234567890abcdef'

        $layout.TempExtract | Should -Be 'C:\Users\runneradmin\AppData\Local\Temp\BaselineInstaller_1234567890abcdef1234567890abcdef\x'
        $layout.SourceRoot | Should -Be 'C:\Users\runneradmin\AppData\Local\Temp\BaselineInstaller_1234567890abcdef1234567890abcdef\x\B'
        $layout.StageDir | Should -Be 'C:\Users\runneradmin\AppData\Local\Temp\BaselineInstaller_1234567890abcdef1234567890abcdef\s\B'
    }

    It 'archives the staging root so extraction recreates the payload source root' {
        $script:InstallerPackageContent | Should -Match 'New-BaselineReleaseZip\s+-SourceDirectory\s+\$stageRoot\s+-DestinationZip\s+\$archivePath'
    }
}

Describe 'Get-InstallerPayloadEntries' {
    It 'ships runtime diagnostics tooling without repository-only automation content' {
        $entries = Get-InstallerPayloadEntries

        $entries | Should -Contain 'README.md'
        $entries | Should -Contain 'LICENSE'
        $entries | Should -Contain 'CHANGELOG.md'
        $entries | Should -Contain 'Tools'
        $entries | Should -Contain 'Tests'
        $entries | Should -Not -Contain '.github'
    }
}

Describe 'Assert-InstallerPayloadExcludesRepositoryMetadata' {
    It 'accepts a curated installer payload root' {
        $payloadRoot = Join-Path $TestDrive 'Payload'
        New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'Module') -Force | Out-Null

        { Assert-InstallerPayloadExcludesRepositoryMetadata -SourceRoot $payloadRoot } | Should -Not -Throw
    }

    It 'rejects repository metadata directories in the installer payload root' {
        $payloadRoot = Join-Path $TestDrive 'Payload'
        New-Item -ItemType Directory -Path (Join-Path $payloadRoot '.github') -Force | Out-Null

        { Assert-InstallerPayloadExcludesRepositoryMetadata -SourceRoot $payloadRoot } |
            Should -Throw '*Installer payload includes repository metadata: .github*'
    }
}

Describe 'Baseline-Setup.iss payload exclusions' {
    It 'keeps repository metadata out of recursive file copy rules' {
        $templatePath = Join-Path $script:RepoRoot 'dist/Baseline-Setup.iss'
        $template = Get-Content -LiteralPath $templatePath -Raw

        $template | Should -Match 'Excludes:\s+"\{#MyAppExeName\},\.git\\\*,\.github\\\*"'
    }
}

Describe 'Get-InstallerPayloadPathBudgetReport' {
    It 'keeps the staged payload under the classic MAX_PATH limit for release packaging' {
        $report = Get-InstallerPayloadPathBudgetReport `
            -RepoRoot $script:RepoRoot `
            -BaseTempPath 'C:\Users\runneradmin\AppData\Local\Temp' `
            -RootName 'BaselineInstaller_1234567890abcdef1234567890abcdef'

        $report.MaxLength | Should -BeLessOrEqual 259
        $report.MaxRelativePath | Should -Match 'Assets\\AIRemovalPackage\\'
    }
}
