Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'MountManagerAutoMount') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'MountManagerAutoMount' {
    BeforeEach {
        $script:consoleActions   = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses  = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages     = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages    = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls     = [System.Collections.Generic.List[object]]::new()
        $script:setRegCalls      = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls   = [System.Collections.Generic.List[object]]::new()
        $script:existingPaths    = [System.Collections.Generic.HashSet[string]]::new()
        [void]$script:existingPaths.Add('HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr')

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo    { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) }
        function LogError   { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path  { param([string]$Path) return $script:existingPaths.Contains($Path) }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add([pscustomobject]@{ Path = $Path })
            [void]$script:existingPaths.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires either -Enable or -Disable' {
        { MountManagerAutoMount } | Should -Throw
    }

    It 'sets MountMgr\NoAutoMount=1 (DWord) when enabling' {
        MountManagerAutoMount -Enable

        $script:setRegCalls.Count | Should -Be 1
        $script:setRegCalls[0].Path  | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr'
        $script:setRegCalls[0].Name  | Should -Be 'NoAutoMount'
        $script:setRegCalls[0].Value | Should -Be 1
        $script:setRegCalls[0].Type  | Should -Be 'DWord'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'creates the MountMgr key when missing before writing the value' {
        $script:existingPaths.Clear()

        MountManagerAutoMount -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0].Path | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr'
        $script:setRegCalls.Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes the NoAutoMount value when disabling' {
        MountManagerAutoMount -Disable

        $script:setRegCalls.Count    | Should -Be 0
        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Path | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr'
        $script:removeRegCalls[0].Name | Should -Be 'NoAutoMount'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed and logs the error when Set-RegistryValueSafe throws' {
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            throw 'simulated registry failure'
        }

        MountManagerAutoMount -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated registry failure'
    }

    It 'reports failed and logs the error when Remove-RegistryValueSafe throws on disable' {
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            throw 'simulated remove failure'
        }

        MountManagerAutoMount -Disable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated remove failure'
    }

    It 'rejects both -Enable and -Disable supplied together (parameter set validation)' {
        { MountManagerAutoMount -Enable -Disable } | Should -Throw
    }
}
