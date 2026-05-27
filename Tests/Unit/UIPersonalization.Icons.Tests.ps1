Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization/UIPersonalization.Icons.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'UIPersonalization.Icons toggles' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:pathExists = $false
        $script:hasExistingProperty = $false
        $script:shouldThrow = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function New-PSDrive { param([string]$Name, [string]$PSProvider, [string]$Root) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Value = $Value })
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [object]$ErrorAction)
            $target = if ($Path) { $Path } else { $LiteralPath }
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $target; Name = $Name; Value = $Value })
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:shouldThrow) { throw 'set-registryvaluesafe failed' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-Item {
            param([string]$LiteralPath, [string]$Path, [switch]$Force, [object]$ErrorAction)
            $target = if ($LiteralPath) { $LiteralPath } else { $Path }
            [void]$script:removeItemCalls.Add($target)
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Get-ItemProperty {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            if ($script:hasExistingProperty) { return [pscustomobject]@{ $Name = 1 } }
            return $null
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','New-PSDrive','Test-Path','New-Item','New-ItemProperty','Set-ItemProperty','Set-RegistryValueSafe','Remove-Item','Remove-RegistryValueSafe','Get-ItemProperty')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    Context 'ShareMenu' {
        It 'requires Enable or Disable' {
            { ShareMenu } | Should -Throw
        }

        It 'writes ModernSharing GUID on Enable' {
            ShareMenu -Enable

            $script:setItemPropertyCalls[0].Value | Should -Match '{e2bf9676-5f8f-435c-97eb-11607a5bedf7}'
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'removes the ModernSharing key on Disable when it exists' {
            $script:pathExists = $true

            ShareMenu -Disable

            $script:removeItemCalls.Count | Should -Be 1
            $script:removeItemCalls[0] | Should -Match 'ModernSharing'
        }

        It 'skips removal on Disable when the key is absent' {
            $script:pathExists = $false

            ShareMenu -Disable

            $script:removeItemCalls.Count | Should -Be 0
            $script:consoleStatuses[-1] | Should -Be 'success'
        }
    }

    Context 'SharingWizard' {
        It 'removes SharingWizardOn on Enable when the value exists' {
            $script:hasExistingProperty = $true

            SharingWizard -Enable

            $script:removeRegCalls[0].Name | Should -Be 'SharingWizardOn'
        }

        It 'writes SharingWizardOn=0 on Disable' {
            SharingWizard -Disable

            $script:setRegistrySafeCalls[0].Name | Should -Be 'SharingWizardOn'
            $script:setRegistrySafeCalls[0].Value | Should -Be 0
        }
    }

    Context 'ShortcutArrow' {
        It 'writes shortcut-arrow icon resource on Disable when path missing' {
            $script:pathExists = $false

            ShortcutArrow -Disable

            $script:newItemCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Name | Should -Be '29'
            $script:setRegistrySafeCalls[0].Value | Should -Match 'imageres\.dll,-1015'
        }

        It 'removes the 29 value on Enable when path exists' {
            $script:pathExists = $true

            ShortcutArrow -Enable

            $script:removeRegCalls[0].Name | Should -Be '29'
        }
    }

    Context 'ThisPC' {
        It 'writes This-PC GUID with value 0 on Show when path missing' {
            $script:pathExists = $false

            ThisPC -Show

            $script:newItemCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Name | Should -Be '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
            $script:setRegistrySafeCalls[0].Value | Should -Be 0
        }

        It 'removes the This-PC value on Hide when it exists' {
            $script:hasExistingProperty = $true

            ThisPC -Hide

            $script:removeRegCalls[0].Name | Should -Be '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
        }
    }

    Context 'WindowsColorMode' {
        It 'requires Dark or Light' {
            { WindowsColorMode } | Should -Throw
        }

        It 'writes SystemUsesLightTheme=0 on Dark' {
            WindowsColorMode -Dark

            $script:setRegistrySafeCalls[0].Name | Should -Be 'SystemUsesLightTheme'
            $script:setRegistrySafeCalls[0].Value | Should -Be 0
        }

        It 'writes SystemUsesLightTheme=1 on Light' {
            WindowsColorMode -Light

            $script:setRegistrySafeCalls[0].Value | Should -Be 1
        }
    }
}
