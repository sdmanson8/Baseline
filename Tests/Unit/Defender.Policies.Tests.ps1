Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.Policies.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'PowerShellModulesLogging' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value; PropertyType = $PropertyType })
        }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
    }

    It 'enables module logging by creating the policy key and setting values' {
        PowerShellModulesLogging -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 2
        $enableEntry = $script:newItemPropertyCalls | Where-Object { $_.Name -eq 'EnableModuleLogging' } | Select-Object -First 1
        $enableEntry.Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes module logging values when disabling' {
        PowerShellModulesLogging -Disable

        $script:removeRegCalls.Count | Should -BeGreaterThan 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'PowerShellScriptsLogging' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
    }

    It 'writes EnableScriptBlockLogging=1 when enabling' {
        PowerShellScriptsLogging -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'EnableScriptBlockLogging'
        $script:newItemPropertyCalls[0].Value | Should -Be 1
    }

    It 'removes EnableScriptBlockLogging when disabling' {
        PowerShellScriptsLogging -Disable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'EnableScriptBlockLogging'
    }
}

Describe 'PUAppsDetection' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:mpCalls = [System.Collections.Generic.List[object]]::new()
        $script:defenderExecutionAvailable = $true
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Get-TweakSkipLabel { param($Invocation) return 'PUAppsDetection' }
        function Test-BaselineDefenderExecutionAvailable { return [bool]$script:defenderExecutionAvailable }
        function Get-BaselineDefenderExecutionUnavailableReason { return 'Set-MpPreference is not available.' }
        function Set-MpPreference {
            param([string]$PUAProtection, [object]$ErrorAction)
            [void]$script:mpCalls.Add($PUAProtection)
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-BaselineDefenderExecutionAvailable -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineDefenderExecutionUnavailableReason -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-MpPreference -ErrorAction SilentlyContinue
    }

    It 'enables PUA protection via Set-MpPreference' {
        PUAppsDetection -Enable

        $script:mpCalls[0] | Should -Be 'Enabled'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'disables PUA protection via Set-MpPreference' {
        PUAppsDetection -Disable

        $script:mpCalls[0] | Should -Be 'Disabled'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips when Defender command surface is unavailable' {
        $script:defenderExecutionAvailable = $false
        PUAppsDetection -Enable

        $script:mpCalls.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Set-MpPreference is not available'
    }
}

Describe 'SaveZoneInformation' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
    }

    It 'writes the HKCU SaveZoneInformation=1 property on Disable' {
        SaveZoneInformation -Disable

        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'SaveZoneInformation'
        $script:setRegistryCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes the HKCU SaveZoneInformation value on Enable' {
        SaveZoneInformation -Enable

        # Always clears the HKLM policy (first call), plus the HKCU on Enable (second)
        $userRemovals = @($script:removeRegCalls | Where-Object { $_.Path -match 'HKCU' })
        $userRemovals.Count | Should -Be 1
        $userRemovals[0].Name | Should -Be 'SaveZoneInformation'
    }
}

Describe 'SharingMappedDrives' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
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
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'sets EnableLinkedConnections=1 on enable' {
        SharingMappedDrives -Enable

        $script:setItemPropertyCalls[0].Name | Should -Be 'EnableLinkedConnections'
        $script:setItemPropertyCalls[0].Value | Should -Be 1
    }

    It 'removes EnableLinkedConnections on disable' {
        SharingMappedDrives -Disable

        $script:removeRegCalls[0].Name | Should -Be 'EnableLinkedConnections'
    }
}

Describe 'WindowsSandbox' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:enableCalls = [System.Collections.Generic.List[object]]::new()
        $script:disableCalls = [System.Collections.Generic.List[object]]::new()
        $script:productName = 'Windows 11 Pro'
        $script:featureState = 'Disabled'
        $script:featureExists = $true
        $script:virtEnabled = $true
        $script:hypervisorPresent = $false
        $Script:Localization = [pscustomobject]@{
            Skipped = 'Skipped: {0}'
            EnableHardwareVT = 'hardware virt required'
            RestartFunction = 'Run again: {0}'
        }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Get-TweakSkipLabel { param($Invocation) return 'WindowsSandbox' }
        function Remove-HandledErrorRecord { param($ErrorRecord) }
        function Get-ItemProperty {
            param([string]$Path, [string]$Name)
            [pscustomobject]@{ ProductName = $script:productName }
        }
        function Get-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName, [object]$ErrorAction, [object]$WarningAction)
            if (-not $script:featureExists) { return $null }
            [pscustomobject]@{ FeatureName = $FeatureName; State = $script:featureState }
        }
        function Enable-WindowsOptionalFeature {
            param([switch]$All, [switch]$Online, [string]$FeatureName, [switch]$NoRestart, [object]$ErrorAction, [object]$WarningAction)
            [void]$script:enableCalls.Add($FeatureName)
        }
        function Disable-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName, [switch]$NoRestart, [object]$ErrorAction, [object]$WarningAction)
            [void]$script:disableCalls.Add($FeatureName)
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
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-HandledErrorRecord -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    }

    It 'skips on Home edition' {
        $script:productName = 'Windows 11 Home'
        WindowsSandbox -Enable

        $script:enableCalls.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
    }

    It 'enables the Containers-DisposableClientVM feature when supported' {
        $script:productName = 'Windows 11 Pro'
        $script:featureState = 'Disabled'
        $script:virtEnabled = $true
        WindowsSandbox -Enable

        $script:enableCalls.Count | Should -Be 1
        $script:enableCalls[0] | Should -Be 'Containers-DisposableClientVM'
    }

    It 'reports already-enabled without calling Enable-WindowsOptionalFeature' {
        $script:productName = 'Windows 11 Pro'
        $script:featureState = 'Enabled'
        WindowsSandbox -Enable

        $script:enableCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'disables the Sandbox feature when currently enabled' {
        $script:productName = 'Windows 11 Pro'
        $script:featureState = 'Enabled'
        WindowsSandbox -Disable

        $script:disableCalls.Count | Should -Be 1
        $script:disableCalls[0] | Should -Be 'Containers-DisposableClientVM'
    }
}

Describe 'WindowsScriptHost' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistryCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Get-TweakSkipLabel { param($Invocation) return 'WindowsScriptHost' }
        function Test-Path { param([string]$Path) return $false }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:setRegistryCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Get-ScheduledTask {
            param([string[]]$TaskName, [object]$ErrorAction)
            return @()
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ScheduledTask -ErrorAction SilentlyContinue
    }

    It 'disables the Script Host by writing Enabled=0' {
        WindowsScriptHost -Disable

        $script:setRegistryCalls.Count | Should -Be 1
        $script:setRegistryCalls[0].Name | Should -Be 'Enabled'
        $script:setRegistryCalls[0].Value | Should -Be 0
    }

    It 'enables the Script Host by removing the Enabled value' {
        WindowsScriptHost -Enable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'Enabled'
    }
}
