Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/TaskbarClock.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'ClockInNotificationCenter' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:throwOnWrite = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnWrite) { throw 'registry write denied' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Show or Hide' {
        { ClockInNotificationCenter } | Should -Throw
    }

    It 'writes ShowClockInNotificationCenter=1 on Show' {
        ClockInNotificationCenter -Show

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be 'ShowClockInNotificationCenter'
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes ShowClockInNotificationCenter=0 on Hide' {
        ClockInNotificationCenter -Hide

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs an error and marks failed when the registry write throws' {
        $script:throwOnWrite = $true

        ClockInNotificationCenter -Show

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'registry write denied'
    }
}

Describe 'SecondsInSystemClock' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:throwOnWrite = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:throwOnWrite) { throw 'boom' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Show or Hide' {
        { SecondsInSystemClock } | Should -Throw
    }

    It 'writes ShowSecondsInSystemClock=1 on Show' {
        SecondsInSystemClock -Show

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be 'ShowSecondsInSystemClock'
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes ShowSecondsInSystemClock=0 on Hide' {
        SecondsInSystemClock -Hide

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs an error and marks failed when the registry write throws' {
        $script:throwOnWrite = $true

        SecondsInSystemClock -Hide

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'boom'
    }
}
