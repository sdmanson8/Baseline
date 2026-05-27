Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.SystemRestore.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'SystemRestoreProtection' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:enableRestoreCalls = [System.Collections.Generic.List[string]]::new()
        $script:disableRestoreCalls = [System.Collections.Generic.List[string]]::new()
        $script:rpSessionInterval = 1
        $script:enableThrows = $false
        $script:cimThrows = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Enable-ComputerRestore {
            [CmdletBinding()]
            param([string]$Drive)
            if ($script:enableThrows) { throw 'enable-computerrestore failed' }
            [void]$script:enableRestoreCalls.Add($Drive)
        }
        function Disable-ComputerRestore {
            [CmdletBinding()]
            param([string]$Drive)
            if ($script:enableThrows) { throw 'disable-computerrestore failed' }
            [void]$script:disableRestoreCalls.Add($Drive)
        }
        function Get-CimInstance {
            [CmdletBinding()]
            param([string]$ClassName, [string]$Namespace)
            if ($script:cimThrows) { throw 'cim failed' }
            return [pscustomobject]@{ RPSessionInterval = $script:rpSessionInterval }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Enable-ComputerRestore','Disable-ComputerRestore','Get-CimInstance')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable' {
        { SystemRestoreProtection } | Should -Throw
    }

    It 'calls Enable-ComputerRestore and verifies via CIM on -Enable' {
        $script:rpSessionInterval = 1

        SystemRestoreProtection -Enable

        $script:enableRestoreCalls.Count | Should -Be 1
        $script:enableRestoreCalls[0] | Should -Match '^[A-Za-z]:\\$'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when CIM check shows RPSessionInterval not 1 after Enable' {
        $script:rpSessionInterval = 0

        SystemRestoreProtection -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'RPSessionInterval'
    }

    It 'reports failed when Enable-ComputerRestore throws' {
        $script:enableThrows = $true

        SystemRestoreProtection -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'enable-computerrestore failed'
    }

    It 'calls Disable-ComputerRestore on -Disable' {
        SystemRestoreProtection -Disable

        $script:disableRestoreCalls.Count | Should -Be 1
        $script:disableRestoreCalls[0] | Should -Match '^[A-Za-z]:\\$'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'SystemRestoreAllocation' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:vssadminCalls = [System.Collections.Generic.List[object]]::new()
        $script:vssadminExitCode = 0

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function vssadmin {
            [void]$script:vssadminCalls.Add([pscustomobject]@{ Args = @($args) })
            $global:LASTEXITCODE = $script:vssadminExitCode
            if ($script:vssadminExitCode -eq 0) { 'Successfully resized.' } else { 'Error: bogus failure' }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','vssadmin')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of the percentage switches' {
        { SystemRestoreAllocation } | Should -Throw
    }

    It 'invokes vssadmin with /MaxSize=5%% on -Pct5' {
        SystemRestoreAllocation -Pct5

        $script:vssadminCalls.Count | Should -Be 1
        $callArgs = $script:vssadminCalls[0].Args
        $callArgs[0] | Should -Be 'resize'
        $callArgs[1] | Should -Be 'shadowstorage'
        ($callArgs -join ' ') | Should -Match '/MaxSize=5%'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'invokes vssadmin with /MaxSize=10%% on -Pct10' {
        SystemRestoreAllocation -Pct10

        ($script:vssadminCalls[0].Args -join ' ') | Should -Match '/MaxSize=10%'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'invokes vssadmin with /MaxSize=15%% on -Pct15' {
        SystemRestoreAllocation -Pct15
        ($script:vssadminCalls[0].Args -join ' ') | Should -Match '/MaxSize=15%'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'invokes vssadmin with /MaxSize=20%% on -Pct20' {
        SystemRestoreAllocation -Pct20
        ($script:vssadminCalls[0].Args -join ' ') | Should -Match '/MaxSize=20%'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when vssadmin exits non-zero' {
        $script:vssadminExitCode = 1

        SystemRestoreAllocation -Pct10

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'vssadmin exited 1'
    }
}

Describe 'SystemRestorePointFrequency' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $true
        $script:setThrows = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path, [string]$LiteralPath) return $script:pathExists }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:setThrows) { throw 'set-registry-value-safe failed' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable' {
        { SystemRestorePointFrequency } | Should -Throw
    }

    It 'writes SystemRestorePointCreationFrequency=0 DWord on -Enable when key exists' {
        $script:pathExists = $true

        SystemRestorePointFrequency -Enable

        $script:newItemCalls.Count | Should -Be 0
        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be 'SystemRestorePointCreationFrequency'
        $script:setRegistrySafeCalls[0].Value | Should -Be 0
        $script:setRegistrySafeCalls[0].Type | Should -Be 'DWord'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'creates the SystemRestore key on -Enable when key is missing' {
        $script:pathExists = $false

        SystemRestorePointFrequency -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Match 'SystemRestore$'
        $script:setRegistrySafeCalls.Count | Should -Be 1
    }

    It 'reports failed when Set-RegistryValueSafe throws on -Enable' {
        $script:pathExists = $true
        $script:setThrows = $true

        SystemRestorePointFrequency -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'set-registry-value-safe failed'
    }

    It 'removes SystemRestorePointCreationFrequency on -Disable' {
        SystemRestorePointFrequency -Disable

        $script:removeRegistrySafeCalls.Count | Should -Be 1
        $script:removeRegistrySafeCalls[0].Name | Should -Be 'SystemRestorePointCreationFrequency'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
