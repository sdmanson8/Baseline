Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.Hardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'DefenderExploitGuardPolicy') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Defender exploit-guard registry toggles' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:mpPreferenceCalls = 0

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path {
            param([string]$Path)
            return $false
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Value, [string]$Type, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Set-MpPreference {
            param([object]$AttackSurfaceReductionRules_Ids, [object]$AttackSurfaceReductionRules_Actions, [object]$ErrorAction)
            $script:mpPreferenceCalls++
        }
        function Set-ProcessMitigation {
            param([switch]$System, [object[]]$Enable, [object]$ErrorAction)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Set-ItemProperty','Set-MpPreference','Set-ProcessMitigation')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'routes the HKCU passive mode write through the safe registry helper' {
        DefenderExploitGuardPolicy

        $script:newItemCalls.Count | Should -Be 2
        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'PassiveMode'
        $script:setRegistryCalls[0].Value | Should -Be 2
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'DriverLoadPolicy'
        $script:mpPreferenceCalls | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
