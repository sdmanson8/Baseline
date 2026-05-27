Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.HardwarePower.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'RazerBlock' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:icaclsCalls = [System.Collections.Generic.List[object]]::new()
        $script:razerPathExists = $false
        $script:icaclsExit = 0

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:razerPathExists }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [string]$ItemType, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function Remove-Item {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Path, [switch]$Recurse, [switch]$Force)
            [void]$script:removeItemCalls.Add($Path)
        }
        function icacls {
            [void]$script:icaclsCalls.Add([pscustomobject]@{ Args = $args })
            $global:LASTEXITCODE = $script:icaclsExit
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','Set-ItemProperty','New-Item','Remove-Item','icacls')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable' {
        { RazerBlock } | Should -Throw
    }

    It 'creates Razer directory and applies deny permission on Enable when path missing' {
        $script:razerPathExists = $false

        RazerBlock -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:removeItemCalls.Count | Should -Be 0
        $script:icaclsCalls.Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'clears the existing Razer directory on Enable when path exists' {
        $script:razerPathExists = $true

        RazerBlock -Enable

        $script:removeItemCalls.Count | Should -Be 1
        $script:newItemCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes DriverSearching and DisableCoInstallers registry values on Enable' {
        RazerBlock -Enable

        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'SearchOrderConfig' }).Value | Should -Be 0
        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'DisableCoInstallers' }).Value | Should -Be 1
    }

    It 'reports failed when icacls returns non-zero on Enable' {
        $script:icaclsExit = 5

        RazerBlock -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'icacls'
    }

    It 'restores registry defaults and removes deny permission on Disable' {
        RazerBlock -Disable

        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'SearchOrderConfig' }).Value | Should -Be 1
        ($script:setItemPropertyCalls | Where-Object { $_.Name -eq 'DisableCoInstallers' }).Value | Should -Be 0
        $script:icaclsCalls.Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'S3Sleep' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeSafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:shouldThrow = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            if ($script:shouldThrow) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeSafeCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-ItemProperty','Remove-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes PlatformAoAcOverride=0 on Enable' {
        S3Sleep -Enable

        $script:setItemPropertyCalls[0].Name | Should -Be 'PlatformAoAcOverride'
        $script:setItemPropertyCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'removes PlatformAoAcOverride on Disable via Remove-RegistryValueSafe' {
        S3Sleep -Disable

        $script:removeSafeCalls.Count | Should -Be 1
        $script:removeSafeCalls[0].Name | Should -Be 'PlatformAoAcOverride'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when Set-ItemProperty throws' {
        $script:shouldThrow = $true

        S3Sleep -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
    }
}

Describe 'ServicesManual' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setServiceCalls = [System.Collections.Generic.List[object]]::new()
        $script:missingService = $null

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Get-Service {
            [CmdletBinding()]
            param([Parameter(Position=0)][string]$Name)
            if ($Name -eq $script:missingService) {
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new("Cannot find any service with service name '$Name'"),
                    'NoServiceFoundForGivenName',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Name
                )
                $PSCmdlet.ThrowTerminatingError($err)
            }
            return [pscustomobject]@{ Name = $Name; ServiceName = $Name }
        }
        function Set-Service {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline=$true)][object]$InputObject, [string]$Name, [string]$StartupType)
            process {
                $svcName = if ($InputObject) { $InputObject.Name } else { $Name }
                [void]$script:setServiceCalls.Add([pscustomobject]@{ Name = $svcName; StartupType = $StartupType })
            }
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Get-Service','Set-Service')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable' {
        { ServicesManual } | Should -Throw
    }

    It 'configures a large number of services on Enable and finishes with success' {
        ServicesManual -Enable

        # 100+ services are processed in the hardcoded table; a loose lower bound is fine.
        $script:setServiceCalls.Count | Should -BeGreaterThan 50
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'uses the StartupType column on Enable for known services' {
        ServicesManual -Enable

        ($script:setServiceCalls | Where-Object { $_.Name -eq 'DiagTrack' }).StartupType | Should -Be 'Disabled'
        ($script:setServiceCalls | Where-Object { $_.Name -eq 'Dhcp' }).StartupType | Should -Be 'Automatic'
    }

    It 'uses the OriginalType column on Disable for known services' {
        ServicesManual -Disable

        ($script:setServiceCalls | Where-Object { $_.Name -eq 'DiagTrack' }).StartupType | Should -Be 'Automatic'
    }

    It 'logs missing services as unavailable and continues' {
        $script:missingService = 'DiagTrack'

        ServicesManual -Enable

        ($script:infoMessages | Where-Object { $_ -match 'DiagTrack' }).Count | Should -BeGreaterOrEqual 1
        ($script:warningMessages | Where-Object { $_ -match 'DiagTrack' }).Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'Teredo' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:netshExit = 0
        $script:shouldThrow = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            if ($script:shouldThrow) { throw 'set-itemproperty failed' }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function netsh { $global:LASTEXITCODE = $script:netshExit }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-ItemProperty','netsh')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'writes DisabledComponents=0 on Enable' {
        Teredo -Enable

        $script:setItemPropertyCalls[0].Name | Should -Be 'DisabledComponents'
        $script:setItemPropertyCalls[0].Value | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes DisabledComponents=1 on Disable' {
        Teredo -Disable

        $script:setItemPropertyCalls[0].Value | Should -Be 1
    }

    It 'reports failed when netsh returns non-zero' {
        $script:netshExit = 2

        Teredo -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'netsh'
    }
}

Describe 'WPBT' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeSafeCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [switch]$Force)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeSafeCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-ItemProperty','Remove-RegistryValueSafe')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'removes DisableWpbtExecution on Enable' {
        WPBT -Enable

        $script:removeSafeCalls.Count | Should -Be 1
        $script:removeSafeCalls[0].Name | Should -Be 'DisableWpbtExecution'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'writes DisableWpbtExecution=1 on Disable' {
        WPBT -Disable

        $script:setItemPropertyCalls[0].Name | Should -Be 'DisableWpbtExecution'
        $script:setItemPropertyCalls[0].Value | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
