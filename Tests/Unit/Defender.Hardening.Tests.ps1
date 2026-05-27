Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.Hardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'DefenderAppGuard' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:enableCalls = [System.Collections.Generic.List[object]]::new()
        $script:disableCalls = [System.Collections.Generic.List[object]]::new()
        $script:featureState = 'Disabled'
        $script:featureExists = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Remove-HandledErrorRecord { param($ErrorRecord) }
        function Get-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName, [object]$ErrorAction, [object]$WarningAction)
            if (-not $script:featureExists) { return $null }
            [pscustomobject]@{ FeatureName = $FeatureName; State = $script:featureState }
        }
        function Enable-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName, [switch]$NoRestart, [object]$ErrorAction, [object]$WarningAction)
            [void]$script:enableCalls.Add($FeatureName)
        }
        function Disable-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName, [switch]$NoRestart, [object]$ErrorAction, [object]$WarningAction)
            [void]$script:disableCalls.Add($FeatureName)
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-HandledErrorRecord -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue
    }

    It 'enables the WDAG feature when currently disabled' {
        $script:featureState = 'Disabled'
        DefenderAppGuard -Enable

        $script:enableCalls.Count | Should -Be 1
        $script:enableCalls[0] | Should -Be 'Windows-Defender-ApplicationGuard'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'warns and skips when the WDAG feature is unavailable' {
        $script:featureExists = $false
        DefenderAppGuard -Enable

        $script:enableCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:warningMessages[0] | Should -Match 'not available'
    }

    It 'reports success without enabling when WDAG is already enabled' {
        $script:featureState = 'Enabled'
        DefenderAppGuard -Enable

        $script:enableCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:infoMessages -join ' ' | Should -Match 'already enabled'
    }

    It 'disables the WDAG feature when currently enabled' {
        $script:featureState = 'Enabled'
        DefenderAppGuard -Disable

        $script:disableCalls.Count | Should -Be 1
        $script:disableCalls[0] | Should -Be 'Windows-Defender-ApplicationGuard'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'requires either Enable or Disable (parameter set validation)' {
        { DefenderAppGuard } | Should -Throw
    }
}

Describe 'CIMemoryIntegrity' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'writes Enabled=1 to the DeviceGuard HVCI scenario when enabling' {
        CIMemoryIntegrity -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Path | Should -Match 'HypervisorEnforcedCodeIntegrity'
        $script:setItemPropertyCalls[0].Name | Should -Be 'Enabled'
        $script:setItemPropertyCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes the Enabled registry value when disabling' {
        CIMemoryIntegrity -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Path | Should -Match 'HypervisorEnforcedCodeIntegrity'
        $script:removeRegCalls[0].Name | Should -Be 'Enabled'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'LocalSecurityAuthority' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:virtEnabled = $true
        $script:hypervisorPresent = $false
        $Script:Localization = [pscustomobject]@{ EnableHardwareVT = 'hardware virt required' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Get-CimInstance {
            param([string]$ClassName)
            if ($ClassName -eq 'CIM_Processor') {
                [pscustomobject]@{ VirtualizationFirmwareEnabled = $script:virtEnabled }
            } else {
                [pscustomobject]@{ HypervisorPresent = $script:hypervisorPresent }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    }

    It 'writes RunAsPPL values when virtualization is enabled in firmware' {
        $script:virtEnabled = $true
        LocalSecurityAuthority -Enable

        $script:newItemPropertyCalls.Count | Should -Be 2
        $names = @($script:newItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'RunAsPPL'
        $names | Should -Contain 'RunAsPPLBoot'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes the LSA PPL values on disable' {
        LocalSecurityAuthority -Disable

        $script:removeRegCalls.Count | Should -BeGreaterThan 1
        $names = @($script:removeRegCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'RunAsPPL'
        $names | Should -Contain 'RunAsPPLBoot'
    }

    It 'clears policy state on every call' {
        LocalSecurityAuthority -Enable

        # Every call clears the policy first regardless of Enable/Disable
        $clearCalls = @($script:policyCalls | Where-Object { $_.Type -eq 'CLEAR' })
        $clearCalls.Count | Should -BeGreaterThan 0
    }
}

Describe 'DEPOptOut' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:bcdCalls = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function bcdedit {
            [void]$script:bcdCalls.Add($args -join ' ')
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\bcdedit -ErrorAction SilentlyContinue
    }

    It 'runs bcdedit with OptIn on enable' {
        DEPOptOut -Enable

        $script:bcdCalls.Count | Should -Be 1
        $script:bcdCalls[0] | Should -Match 'OptIn'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'runs bcdedit with OptOut on disable' {
        DEPOptOut -Disable

        $script:bcdCalls[0] | Should -Match 'OptOut'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'F8BootMenu' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:bcdCalls = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function bcdedit {
            [void]$script:bcdCalls.Add($args -join ' ')
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\bcdedit -ErrorAction SilentlyContinue
    }

    It 'sets BootMenuPolicy Legacy on enable' {
        F8BootMenu -Enable

        $script:bcdCalls[0] | Should -Match 'Legacy'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'sets BootMenuPolicy Standard on disable' {
        F8BootMenu -Disable

        $script:bcdCalls[0] | Should -Match 'Standard'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'BootRecovery' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:bcdCalls = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function bcdedit {
            [void]$script:bcdCalls.Add($args -join ' ')
            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\bcdedit -ErrorAction SilentlyContinue
    }

    It 'deletes BootStatusPolicy on enable' {
        BootRecovery -Enable

        $script:bcdCalls[0] | Should -Match 'deletevalue'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'sets IgnoreAllFailures on disable' {
        BootRecovery -Disable

        $script:bcdCalls[0] | Should -Match 'IgnoreAllFailures'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
