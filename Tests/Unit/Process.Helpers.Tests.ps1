Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Process.Helpers.ps1'
    $script:ProcessHelpersContent = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in @('ConvertTo-BaselineWindowsProcessArgument', 'ConvertTo-BaselineProcessArgumentString', 'Invoke-UserLaunch')
        }, $true)

    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Process helper argument handling' {
    It 'quotes paths with spaces and trailing backslashes using Windows command-line rules' {
        ConvertTo-BaselineWindowsProcessArgument -Value 'C:\Path With Space\' | Should -Be '"C:\Path With Space\\"'
    }

    It 'preserves embedded quotes and unquoted simple arguments' {
        ConvertTo-BaselineProcessArgumentString -ArgumentList @('plain', 'a"b', 'C:\Path\NoSpace\') | Should -Be 'plain "a\"b" C:\Path\NoSpace\'
    }

    It 'uses ProcessStartInfo.ArgumentList when the runtime exposes it' {
        $script:ProcessHelpersContent | Should -Match "GetProperty\('ArgumentList'\)"
        $script:ProcessHelpersContent | Should -Match '\$psi\.ArgumentList\.Add'
    }

    It 'verifies the taskkill fallback result in Stop-BaselineProcessTree' {
        $script:ProcessHelpersContent | Should -Match '\$taskkillExitCode'
        $script:ProcessHelpersContent | Should -Match '\$taskkillTimedOut'
        $script:ProcessHelpersContent | Should -Match 'VerifyTerminated'
    }
}

Describe 'Invoke-UserLaunch' {
    BeforeEach {
        $script:userLaunchWarnings = New-Object System.Collections.Generic.List[string]
        function LogWarning {
            param([object]$Message)
            [void]$script:userLaunchWarnings.Add([string]$Message)
        }
    }

    AfterEach {
        Remove-Item -LiteralPath Function:\LogWarning -ErrorAction SilentlyContinue
    }

    It 'logs and shows a warning when an interactive launch fails' {
        Mock Start-Process { throw [System.InvalidOperationException]::new('shell blocked') }

        $warningRecords = @()
        $result = Invoke-UserLaunch `
            -FilePath 'fake.exe' `
            -ArgumentList @('C:\Path With Space\file.txt') `
            -Description 'test document' `
            -WarningVariable warningRecords `
            -WarningAction SilentlyContinue

        $result | Should -BeFalse
        $script:userLaunchWarnings.Count | Should -Be 1
        $script:userLaunchWarnings[0] | Should -Match 'Failed to launch test document'
        $script:userLaunchWarnings[0] | Should -Match 'shell blocked'
        [string]$warningRecords[0] | Should -Match 'Failed to launch test document'
        [string]$warningRecords[0] | Should -Match 'shell blocked'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'fake.exe' -and
            @($ArgumentList).Count -eq 1 -and
            @($ArgumentList)[0] -eq 'C:\Path With Space\file.txt' -and
            $ErrorAction -eq 'Stop'
        }
    }
}
