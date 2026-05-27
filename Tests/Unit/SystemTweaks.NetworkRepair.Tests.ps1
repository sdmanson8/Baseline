Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.NetworkRepair.psm1'
    $source = Get-Content -Raw $filePath
    $source = [regex]::Replace($source, '^using module[^\r\n]*[\r\n]+', '', 'Multiline')
    $sb = [scriptblock]::Create($source)
    $ast = $sb.Ast
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'NetworkStackReset' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:processCalls = [System.Collections.Generic.List[object]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:throwOnCall = 0
        $env:SystemRoot = 'C:\Windows'

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Invoke-BaselineProcess {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds,
                [int[]]$AllowedExitCodes
            )

            [void]$script:processCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
                AllowedExitCodes = @($AllowedExitCodes)
            })

            if ($script:throwOnCall -gt 0 -and $script:processCalls.Count -eq $script:throwOnCall) {
                throw 'netsh failed'
            }

            return [pscustomobject]@{ ExitCode = 0 }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Invoke-BaselineProcess')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'runs the explicit netsh network reset sequence' {
        NetworkStackReset

        $script:consoleActions[0] | Should -Be 'Resetting Windows network stack'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:processCalls.Count | Should -Be 3
        @($script:processCalls[0].ArgumentList) | Should -Be @('winsock', 'reset')
        @($script:processCalls[1].ArgumentList) | Should -Be @('winhttp', 'reset', 'proxy')
        @($script:processCalls[2].ArgumentList) | Should -Be @('int', 'ip', 'reset')
        $script:processCalls | ForEach-Object { $_.FilePath | Should -Be 'C:\Windows\System32\netsh.exe' }
        $script:processCalls | ForEach-Object { $_.AllowedExitCodes | Should -Be @(0) }
        $script:warningMessages[-1] | Should -Match 'Restart required'
    }

    It 'continues and reports warning when one netsh reset command is rejected' {
        $script:throwOnCall = 2

        NetworkStackReset

        $script:processCalls.Count | Should -Be 3
        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:errorMessages.Count | Should -Be 0
        $script:warningMessages | Should -Contain "Network stack reset step 'Resetting WinHTTP proxy' did not complete: netsh failed"
    }
}
