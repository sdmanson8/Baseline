Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Gaming.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Win32PrioritySeparation' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:regCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'requires Programs or BackgroundServices' {
        { Win32PrioritySeparation } | Should -Throw
    }

    It 'writes Win32PrioritySeparation=38 for Programs' {
        Win32PrioritySeparation -Programs

        $script:regCalls.Count | Should -Be 1
        $script:regCalls[0].Name | Should -Be 'Win32PrioritySeparation'
        $script:regCalls[0].Value | Should -Be 38
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes Win32PrioritySeparation=24 for BackgroundServices' {
        Win32PrioritySeparation -BackgroundServices

        $script:regCalls.Count | Should -Be 1
        $script:regCalls[0].Value | Should -Be 24
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'records an error and failed status if Set-RegistryValueSafe throws' {
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            throw 'reg failure'
        }

        Win32PrioritySeparation -Programs

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'reg failure'
    }
}

Describe 'SystemResponsiveness' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:regCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'sets SystemResponsiveness=10 on Enable' {
        SystemResponsiveness -Enable

        $script:regCalls.Count | Should -Be 1
        $script:regCalls[0].Name | Should -Be 'SystemResponsiveness'
        $script:regCalls[0].Value | Should -Be 10
    }

    It 'sets SystemResponsiveness=20 on Disable' {
        SystemResponsiveness -Disable

        $script:regCalls[0].Value | Should -Be 20
    }
}

Describe 'GamingCpuPriority and GamingSchedulingCategory and GamingGpuPriority' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:regCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'raises Priority to 6 on Enable and 2 on Disable (CPU priority)' {
        GamingCpuPriority -Enable
        $script:regCalls[0].Name | Should -Be 'Priority'
        $script:regCalls[0].Value | Should -Be 6

        $script:regCalls.Clear()
        GamingCpuPriority -Disable
        $script:regCalls[0].Value | Should -Be 2
    }

    It 'sets Scheduling Category High on Enable and Medium on Disable' {
        GamingSchedulingCategory -Enable
        $script:regCalls[0].Name | Should -Be 'Scheduling Category'
        $script:regCalls[0].Value | Should -Be 'High'

        $script:regCalls.Clear()
        GamingSchedulingCategory -Disable
        $script:regCalls[0].Value | Should -Be 'Medium'
    }

    It 'raises GPU Priority to 8 on Enable and 2 on Disable' {
        GamingGpuPriority -Enable
        $script:regCalls[0].Name | Should -Be 'GPU Priority'
        $script:regCalls[0].Value | Should -Be 8

        $script:regCalls.Clear()
        GamingGpuPriority -Disable
        $script:regCalls[0].Value | Should -Be 2
    }
}

Describe 'FullscreenOptimizations' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value; Type = $Type })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'writes GameDVR_DXGIHonorFSEWindowsCompatible=0 on Enable' {
        FullscreenOptimizations -Enable
        $script:setRegistrySafeCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes GameDVR_DXGIHonorFSEWindowsCompatible=1 on Disable' {
        FullscreenOptimizations -Disable
        $script:setRegistrySafeCalls[0].Value | Should -Be 1
    }
}

Describe 'MultiplaneOverlay' {
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
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
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

    It 'removes OverlayTestMode on Enable' {
        MultiplaneOverlay -Enable

        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Name | Should -Be 'OverlayTestMode'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes OverlayTestMode=5 on Disable' {
        MultiplaneOverlay -Disable

        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'OverlayTestMode'
        $script:setItemPropertyCalls[0].Value | Should -Be 5
    }
}

Describe 'GameDVR' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Name = $Name })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'sets GameDVR_Enabled=1 and clears behavior on Enable' {
        GameDVR -Enable

        $enabled = @($script:newItemPropertyCalls | Where-Object { $_.Name -eq 'GameDVR_Enabled' })
        $enabled[0].Value | Should -Be 1
        $removedNames = @($script:removeRegCalls | ForEach-Object { $_.Name })
        $removedNames | Should -Contain 'GameDVR_FSEBehaviorMode'
        $removedNames | Should -Contain 'GameDVR_EFSEFeatureFlags'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes GameDVR_Enabled=0 plus behavior flags on Disable' {
        GameDVR -Disable

        $names = @($script:newItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'GameDVR_Enabled'
        $names | Should -Contain 'GameDVR_FSEBehaviorMode'
        $names | Should -Contain 'GameDVR_EFSEFeatureFlags'

        $enabled = @($script:newItemPropertyCalls | Where-Object { $_.Name -eq 'GameDVR_Enabled' })
        $enabled[0].Value | Should -Be 0
    }

    It 'creates the key on Enable when Test-Path returns false' {
        $script:pathExists = $false

        GameDVR -Enable

        $script:newItemCalls.Count | Should -Be 1
    }
}

Describe 'WindowsGameMode' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'writes both AutoGameModeEnabled=1 and AllowAutoGameMode=1 on Enable' {
        WindowsGameMode -Enable

        $names = @($script:newItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'AutoGameModeEnabled'
        $names | Should -Contain 'AllowAutoGameMode'
        foreach ($c in $script:newItemPropertyCalls) { $c.Value | Should -Be 1 }
    }

    It 'writes both AutoGameModeEnabled=0 and AllowAutoGameMode=0 on Disable' {
        WindowsGameMode -Disable

        foreach ($c in $script:newItemPropertyCalls) { $c.Value | Should -Be 0 }
    }
}

Describe 'MouseAcceleration' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'writes the enhanced-pointer-precision triplet on Enable' {
        MouseAcceleration -Enable

        $script:setItemPropertyCalls.Count | Should -Be 3
        $byName = @{}
        foreach ($c in $script:setItemPropertyCalls) { $byName[$c.Name] = $c.Value }
        $byName['MouseSpeed'] | Should -Be '1'
        $byName['MouseThreshold1'] | Should -Be '6'
        $byName['MouseThreshold2'] | Should -Be '10'
    }

    It 'zeros the triplet on Disable' {
        MouseAcceleration -Disable

        $script:setItemPropertyCalls.Count | Should -Be 3
        foreach ($c in $script:setItemPropertyCalls) { $c.Value | Should -Be '0' }
    }
}

Describe 'NaglesAlgorithm' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:adapters = @([pscustomobject]@{ ifIndex = 1; Status = 'Up'; InterfaceGuid = '{AAAA}' })

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Get-NetAdapter {
            param([switch]$Physical, [object]$ErrorAction)
            return $script:adapters
        }
        function Get-NetIPInterface {
            param([int]$InterfaceIndex, [string]$AddressFamily, [object]$ErrorAction)
            return @([pscustomobject]@{ InterfaceIndex = $InterfaceIndex })
        }
        function Test-Path { param([string]$Path) return $true }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-NetAdapter','Get-NetIPInterface','Test-Path','New-ItemProperty','Remove-RegistryValueSafe')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'skips when no active adapters are found' {
        $script:adapters = @()

        NaglesAlgorithm -Disable

        $script:warningMessages -join ' ' | Should -Match 'No active'
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'writes TcpAckFrequency=1 and TCPNoDelay=1 for every active adapter on Disable' {
        $script:adapters = @(
            [pscustomobject]@{ ifIndex = 1; Status = 'Up'; InterfaceGuid = '{AAAA}' },
            [pscustomobject]@{ ifIndex = 2; Status = 'Up'; InterfaceGuid = '{BBBB}' }
        )

        NaglesAlgorithm -Disable

        $script:newItemPropertyCalls.Count | Should -Be 4
        $names = @($script:newItemPropertyCalls | ForEach-Object { $_.Name })
        ($names | Where-Object { $_ -eq 'TcpAckFrequency' }).Count | Should -Be 2
        ($names | Where-Object { $_ -eq 'TCPNoDelay' }).Count | Should -Be 2
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes TcpAckFrequency and TCPNoDelay for every active adapter on Enable' {
        $script:adapters = @([pscustomobject]@{ ifIndex = 1; Status = 'Up'; InterfaceGuid = '{AAAA}' })

        NaglesAlgorithm -Enable

        $script:removeRegCalls.Count | Should -Be 2
        $names = @($script:removeRegCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'TcpAckFrequency'
        $names | Should -Contain 'TCPNoDelay'
    }
}

Describe 'NetworkThrottling' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:regCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-RegistryValueSafe -ErrorAction SilentlyContinue
    }

    It 'writes NetworkThrottlingIndex=10 on Enable' {
        NetworkThrottling -Enable
        $script:regCalls[0].Name | Should -Be 'NetworkThrottlingIndex'
        $script:regCalls[0].Value | Should -Be 10
    }

    It 'writes NetworkThrottlingIndex=-1 on Disable (disables throttling)' {
        NetworkThrottling -Disable
        $script:regCalls[0].Value | Should -Be -1
    }
}

Describe 'XboxGameBar' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Test-Path { param([string]$Path) return $true }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Name = $Name; Value = $Value })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','New-ItemProperty')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes AppCaptureEnabled=0 and GameDVR_Enabled=0 on Disable' {
        XboxGameBar -Disable

        $names = @($script:newItemPropertyCalls | ForEach-Object { $_.Name })
        $names | Should -Contain 'AppCaptureEnabled'
        $names | Should -Contain 'GameDVR_Enabled'
        foreach ($c in $script:newItemPropertyCalls) { $c.Value | Should -Be 0 }
    }

    It 'writes AppCaptureEnabled=1 and GameDVR_Enabled=1 on Enable' {
        XboxGameBar -Enable

        foreach ($c in $script:newItemPropertyCalls) { $c.Value | Should -Be 1 }
    }
}

Describe 'Set-AppGraphicsPerformance' {
    BeforeEach {
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:logWarnMessages = [System.Collections.Generic.List[string]]::new()
        $script:logErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:gpuPrefKeyExists = $true
        $script:hasDedicatedGpu = $true
        $script:setRegistryThrows = $false
        $script:isInteractiveHost = $false

        function LogInfo { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:logWarnMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:logErrorMessages.Add($Message) }
        function Write-ConsoleStatus { param([string]$Action, [string]$Status) }
        function Get-CimInstance {
            [CmdletBinding()]
            param([string]$ClassName)
            if ($script:hasDedicatedGpu) {
                return @(
                    [pscustomobject]@{ AdapterDACType = 'Internal' },
                    [pscustomobject]@{ AdapterDACType = 'Direct VGA' }
                )
            }
            return @([pscustomobject]@{ AdapterDACType = 'Internal' })
        }
        function Test-Path { param([string]$Path, [string]$LiteralPath) return $script:gpuPrefKeyExists }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:setRegistryThrows) { throw 'set-registry-value-safe failed' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Test-InteractiveHost { return $script:isInteractiveHost }
    }

    AfterEach {
        foreach ($n in @('LogInfo','LogWarning','LogError','Write-ConsoleStatus','Get-CimInstance','Test-Path','New-Item','Set-RegistryValueSafe','Test-InteractiveHost')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'returns $false and logs an info note when no dedicated GPU is detected' {
        $script:hasDedicatedGpu = $false

        $result = Set-AppGraphicsPerformance -AppPath 'C:\game.exe'

        $result | Should -BeFalse
        $script:setRegistrySafeCalls.Count | Should -Be 0
        ($script:logInfoMessages -join "`n") | Should -Match 'no dedicated GPU'
    }

    It 'writes GpuPreference=2 String value keyed by AppPath when key exists' {
        $script:gpuPrefKeyExists = $true

        $result = Set-AppGraphicsPerformance -AppPath 'C:\game.exe'

        $result | Should -BeTrue
        $script:newItemCalls.Count | Should -Be 0
        $script:setRegistrySafeCalls.Count | Should -Be 1
        $script:setRegistrySafeCalls[0].Path | Should -Be 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $script:setRegistrySafeCalls[0].Name | Should -Be 'C:\game.exe'
        $script:setRegistrySafeCalls[0].Value | Should -Be 'GpuPreference=2;'
        $script:setRegistrySafeCalls[0].Type | Should -Be 'String'
    }

    It 'creates the UserGpuPreferences key when it does not yet exist' {
        $script:gpuPrefKeyExists = $false

        $result = Set-AppGraphicsPerformance -AppPath 'C:\game.exe'

        $result | Should -BeTrue
        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $script:setRegistrySafeCalls.Count | Should -Be 1
    }

    It 'returns $false and logs an error if Set-RegistryValueSafe throws' {
        $script:setRegistryThrows = $true

        $result = Set-AppGraphicsPerformance -AppPath 'C:\game.exe'

        $result | Should -BeFalse
        ($script:logErrorMessages -join "`n") | Should -Match 'set-registry-value-safe failed'
    }

    It 'returns $false on a non-interactive host when AppPath is omitted' {
        $script:isInteractiveHost = $false

        $result = Set-AppGraphicsPerformance

        $result | Should -BeFalse
        $script:setRegistrySafeCalls.Count | Should -Be 0
        ($script:logWarnMessages -join "`n") | Should -Match 'non-interactive'
    }

    It 'returns $false on -WhatIf and writes nothing' {
        $result = Set-AppGraphicsPerformance -AppPath 'C:\game.exe' -WhatIf

        $result | Should -BeFalse
        $script:setRegistrySafeCalls.Count | Should -Be 0
    }
}
