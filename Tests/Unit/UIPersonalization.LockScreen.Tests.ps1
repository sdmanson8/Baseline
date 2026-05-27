Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization/UIPersonalization.LockScreen.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'LockScreen (OS-gated)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:isWindows11 = $true
        $script:hasPolicy = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Get-BaselineSystemPlatformInfo {
            [pscustomobject]@{
                IsWindows11 = $script:isWindows11
                IsWindows10 = (-not $script:isWindows11)
                IsServer = $false
                ProductType = 1
                EditionID = 'Professional'
                Caption = if ($script:isWindows11) { 'Microsoft Windows 11 Pro' } else { 'Microsoft Windows 10 Pro' }
            }
        }
        function Get-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            if ($script:hasPolicy) { return [pscustomobject]@{ NoLockScreen = 1 } }
            return $null
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Test-Path { param([string]$Path) return $true }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineSystemPlatformInfo','Get-ItemProperty','Remove-RegistryValueSafe','Set-RegistryValueSafe','Test-Path','New-Item','Set-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Enable or Disable' {
        { LockScreen } | Should -Throw
    }

    It 'returns silently on non-Windows 11 editions' {
        $script:isWindows11 = $false

        LockScreen -Disable

        $script:consoleStatuses.Count | Should -Be 0
        $script:setRegistrySafeCalls.Count | Should -Be 0
    }

    It 'sets NoLockScreen=1 on Disable for Windows 11' {
        LockScreen -Disable

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Name | Should -Be 'NoLockScreen'
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes NoLockScreen on Enable when the policy is present' {
        $script:hasPolicy = $true

        LockScreen -Enable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'NoLockScreen'
    }
}

Describe 'LockScreenBlur' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','Set-ItemProperty','Set-RegistryValueSafe','Remove-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Enable or Disable' {
        { LockScreenBlur } | Should -Throw
    }

    It 'removes DisableAcrylicBackgroundOnLogon on Enable' {
        LockScreenBlur -Enable

        $script:removeItemPropertyCalls.Count | Should -Be 1
        $script:removeItemPropertyCalls[0].Name | Should -Be 'DisableAcrylicBackgroundOnLogon'
    }

    It 'sets DisableAcrylicBackgroundOnLogon=1 on Disable' {
        LockScreenBlur -Disable

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
    }
}

Describe 'NetworkFromLockScreen and ShutdownFromLockScreen' {
    BeforeEach {
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus { param([string]$Action, [string]$Status) }
        function LogInfo { param([string]$Message) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','Set-ItemProperty','Set-RegistryValueSafe','Remove-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'NetworkFromLockScreen -Disable writes DontDisplayNetworkSelectionUI=1' {
        NetworkFromLockScreen -Disable

        $script:setRegistrySafeCalls[0].Name | Should -Be 'DontDisplayNetworkSelectionUI'
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
    }

    It 'NetworkFromLockScreen -Enable removes DontDisplayNetworkSelectionUI' {
        NetworkFromLockScreen -Enable

        $script:removeItemPropertyCalls[0].Name | Should -Be 'DontDisplayNetworkSelectionUI'
    }

    It 'ShutdownFromLockScreen -Enable writes ShutdownWithoutLogon=1' {
        ShutdownFromLockScreen -Enable

        $match = $script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShutdownWithoutLogon' }
        $match.Value | Should -Be 1
    }

    It 'ShutdownFromLockScreen -Disable writes ShutdownWithoutLogon=0' {
        ShutdownFromLockScreen -Disable

        $match = $script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShutdownWithoutLogon' }
        $match.Value | Should -Be 0
    }
}

Describe 'LockScreenCamera' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:hasPolicyKey = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:hasPolicyKey }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Enable or Disable' {
        { LockScreenCamera } | Should -Throw
    }

    It 'sets NoLockScreenCamera=1 under the Personalization policy on Enable' {
        LockScreenCamera -Enable

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
        $script:setRegistrySafeCalls[0].Name | Should -Be 'NoLockScreenCamera'
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
        $script:setRegistrySafeCalls[0].Type | Should -Be 'DWord'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'creates the Personalization policy key when missing' {
        $script:hasPolicyKey = $false

        LockScreenCamera -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    }

    It 'removes the policy on Disable' {
        LockScreenCamera -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'NoLockScreenCamera'
        $script:setRegistrySafeCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'BlockDomainPINLogon' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:hasPolicyKey = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:hasPolicyKey }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','Set-RegistryValueSafe','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Enable or Disable' {
        { BlockDomainPINLogon } | Should -Throw
    }

    It 'sets AllowDomainPINLogon=0 under the System policy on Enable' {
        BlockDomainPINLogon -Enable

        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        $script:setRegistrySafeCalls[0].Name | Should -Be 'AllowDomainPINLogon'
        $script:setRegistrySafeCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'creates the System policy key when missing' {
        $script:hasPolicyKey = $false

        BlockDomainPINLogon -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    }

    It 'removes the policy value on Disable' {
        BlockDomainPINLogon -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'AllowDomainPINLogon'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
