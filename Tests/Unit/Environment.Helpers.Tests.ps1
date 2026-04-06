Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Invoke-UCPDBypassed' {
    It 'throws on non-zero exit codes and still removes the temporary executable' {
        $tempPath = Join-Path $TestDrive 'powershell_temp.cmd'

        Mock Get-UCPDTemporaryPowerShellPath { $tempPath }
        Mock Copy-Item {
            param($Path, $Destination)
            Set-Content -LiteralPath $Destination -Value "@exit /b 5" -Encoding ASCII
        }
        Mock Remove-Item {}

        { Invoke-UCPDBypassed -ScriptBlock { 'noop' } } | Should -Throw '*exit code 5*'
        Assert-MockCalled Remove-Item -Times 1 -ParameterFilter {
            $Path -eq $tempPath -and $Force
        }
    }
}

Describe 'Get-UCPDTemporaryPowerShellPath' {
    It 'creates a GUID-suffixed executable path in the source directory' {
        $sourceDirectory = Join-Path $TestDrive 'WindowsPowerShell/v1.0'
        $null = New-Item -ItemType Directory -Path $sourceDirectory -Force
        $sourcePath = Join-Path $sourceDirectory 'powershell.exe'

        $path = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath

        Split-Path -Path $path -Parent | Should -Be (Split-Path -Path $sourcePath -Parent)
        Split-Path -Path $path -Leaf | Should -Match '^powershell_[0-9a-f]{32}\.exe$'
    }

    It 'returns a unique path for each call' {
        $sourceDirectory = Join-Path $TestDrive 'WindowsPowerShell/v1.0'
        $null = New-Item -ItemType Directory -Path $sourceDirectory -Force
        $sourcePath = Join-Path $sourceDirectory 'powershell.exe'
        $first = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath
        $second = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath

        $first | Should -Not -Be $second
    }
}

Describe 'Get-BaselineDisplayVersion' {
    It 'reads ModuleVersion from a module manifest and prefixes it with v' {
        $moduleRoot = Join-Path $TestDrive 'ModuleRoot'
        $null = New-Item -ItemType Directory -Path $moduleRoot -Force
        $manifestPath = Join-Path $moduleRoot 'Baseline.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '2.0.0' }" -Encoding ASCII

        $result = Get-BaselineDisplayVersion -ModuleRoot $moduleRoot

        $result | Should -Be 'v2.0.0'
    }
}

Describe 'Get-LocalizedShellString' {
    It 'falls back and strips accelerators when the shell resource is unavailable' {
        $result = Get-LocalizedShellString -ResourceId 1 -Fallback '&Skip' -StripAccelerators

        $result | Should -Be 'Skip'
    }
}
