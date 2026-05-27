Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization/UIPersonalization.Taskbar.psm1'

    $source = Get-Content -Raw $filePath
    $script:TaskbarContent = Get-BaselineTestSourceText -Path $filePath
    $source = [regex]::Replace($source, '^using module[^\r\n]*[\r\n]+', '', 'Multiline')
    $sb = [scriptblock]::Create($source)
    $ast = $sb.Ast
    # Only load the outer functions (avoid redefining nested helpers of Invoke-UIPersonalizationTaskbarShortcutUnpin etc.)
    $functions = $ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
            ($node.Parent -is [System.Management.Automation.Language.NamedBlockAst])
        }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'UIPersonalization.Taskbar content pins' {
    It 'routes ARM64 shell-unpin cleanup failures through Write-SwallowedException' {
        $script:TaskbarContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''UIPersonalization\.Taskbar\.Invoke-UIPersonalizationTaskbarShortcutUnpin\.DoIt'''
        $script:TaskbarContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''UIPersonalization\.Taskbar\.Invoke-UIPersonalizationTaskbarShortcutUnpin\.EndInvoke'''
    }
}

Describe 'UIPersonalization.Taskbar toggle functions' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:ucpdScriptBlocks = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $false
        $script:hasExistingProperty = $false
        $script:shouldThrow = $false
        $script:getAppxPackageReturns = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            [CmdletBinding()]
            param([string]$Path, [switch]$Force)
            [void]$script:newItemCalls.Add($Path)
        }
        function New-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$Name, [string]$PropertyType, [object]$Value, [switch]$Force)
            if ($script:shouldThrow) { throw 'new-itemproperty failed' }
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Remove-ItemProperty {
            [CmdletBinding()]
            param([string[]]$Path, [string[]]$Name, [switch]$Force)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Get-ItemProperty {
            [CmdletBinding()]
            param([string]$Path, [string]$Name)
            if ($script:hasExistingProperty) { return [pscustomobject]@{ $Name = 1 } }
            return $null
        }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:shouldThrow) { throw 'set-registryvaluesafe failed' }
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Name = $Name; Type = $Type })
        }
        function Get-AppxPackage {
            param([string]$Name)
            if ($script:getAppxPackageReturns) { return [pscustomobject]@{ Name = $Name } }
            return $null
        }
        function Invoke-UCPDBypassed {
            [CmdletBinding(DefaultParameterSetName = 'ScriptText')]
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'ScriptText')]
                [string]$ScriptText,

                [Parameter(Mandatory = $true, ParameterSetName = 'ScriptBlock')]
                [scriptblock]$ScriptBlock
            )

            if ($PSCmdlet.ParameterSetName -eq 'ScriptBlock') {
                $ScriptText = $ScriptBlock.ToString()
            }

            [void]$script:ucpdScriptBlocks.Add($ScriptText)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Test-Path','New-Item','New-ItemProperty','Remove-ItemProperty','Get-ItemProperty','Set-RegistryValueSafe','Remove-RegistryValueSafe','Set-Policy','Get-AppxPackage','Invoke-UCPDBypassed')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    Context 'Set-UIPersonalizationTaskbarAlignment' {
        It 'requires Left or Center' {
            { Set-UIPersonalizationTaskbarAlignment } | Should -Throw
        }

        It 'writes TaskbarAl=0 on Left' {
            Set-UIPersonalizationTaskbarAlignment -Left

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarAl' }).Value | Should -Be 0
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'writes TaskbarAl=1 on Center' {
            Set-UIPersonalizationTaskbarAlignment -Center

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarAl' }).Value | Should -Be 1
        }

        It 'creates Explorer\\Advanced when missing before writing TaskbarAl' {
            $script:pathExists = $false

            Set-UIPersonalizationTaskbarAlignment -Center

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }

        It 'reports failed when the registry write throws' {
            $script:shouldThrow = $true

            Set-UIPersonalizationTaskbarAlignment -Center

            $script:consoleStatuses[-1] | Should -Be 'failed'
        }
    }

    Context 'Set-UIPersonalizationTaskbarWidgets' {
        BeforeEach {
            $Global:Localization = [pscustomobject]@{ Skipped = '{0} skipped' }
            if (-not (Test-Path Function:\Get-TweakSkipLabel)) {
                function Get-TweakSkipLabel { param([object]$MyInvocation) return 'label' }
            }
        }

        AfterEach {
            Remove-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
            Microsoft.PowerShell.Management\Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        }

        It 'creates Explorer\\Advanced inside the UCPD bypass script before writing TaskbarDa' {
            Set-UIPersonalizationTaskbarWidgets -Hide

            $script:ucpdScriptBlocks[0] | Should -Match 'New-Item -Path \$path -Force -ErrorAction Stop'
            $script:ucpdScriptBlocks[0] | Should -Match 'TaskbarDa'
        }

        It 'returns without touching registry or policy when WebExperience package is absent' {
            $script:getAppxPackageReturns = $false

            Set-UIPersonalizationTaskbarWidgets -Hide

            $script:ucpdScriptBlocks.Count | Should -Be 0
            $script:newItemPropertyCalls.Count | Should -Be 0
            $script:removeItemPropertyCalls.Count | Should -Be 0
            $script:policyCalls.Count | Should -Be 0
            $script:consoleStatuses.Count | Should -Be 0
        }
    }

    Context 'Set-UIPersonalizationTaskbarSearch' {
        BeforeEach {
            # Set-UIPersonalizationTaskbarSearch writes an unconditional "clear-policy" New-ItemProperty in HKLM
            # which we just tolerate in the mock.
        }

        It 'writes SearchboxTaskbarMode=0 on -Hide' {
            Set-UIPersonalizationTaskbarSearch -Hide

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'SearchboxTaskbarMode' }).Value | Should -Be 0
        }

        It 'writes SearchboxTaskbarMode=1 on -SearchIcon' {
            Set-UIPersonalizationTaskbarSearch -SearchIcon

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'SearchboxTaskbarMode' }).Value | Should -Be 1
        }

        It 'writes SearchboxTaskbarMode=2 on -SearchBox' {
            Set-UIPersonalizationTaskbarSearch -SearchBox

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'SearchboxTaskbarMode' }).Value | Should -Be 2
        }

        It 'writes SearchboxTaskbarMode=3 on -SearchIconLabel' {
            Set-UIPersonalizationTaskbarSearch -SearchIconLabel

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'SearchboxTaskbarMode' }).Value | Should -Be 3
        }

        It 'creates the Search key when missing before writing SearchboxTaskbarMode' {
            $script:pathExists = $false

            Set-UIPersonalizationTaskbarSearch -SearchBox

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
        }

        It 'clears the DisableSearch policy up-front' {
            Set-UIPersonalizationTaskbarSearch -SearchBox

            @($script:policyCalls | Where-Object { $_.Name -eq 'DisableSearch' -and $_.Type -eq 'CLEAR' }).Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Set-UIPersonalizationSearchHighlights' {
        It 'creates SearchSettings when missing before writing IsDynamicSearchBoxEnabled' {
            $script:pathExists = $false

            Set-UIPersonalizationSearchHighlights -Show

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'IsDynamicSearchBoxEnabled' }).Value | Should -Be 1
        }
    }

    Context 'Set-UIPersonalizationTaskViewButton' {
        It 'writes ShowTaskViewButton=0 on -Hide' {
            Set-UIPersonalizationTaskViewButton -Hide

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowTaskViewButton' }).Value | Should -Be 0
        }

        It 'writes ShowTaskViewButton=1 on -Show' {
            Set-UIPersonalizationTaskViewButton -Show

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowTaskViewButton' }).Value | Should -Be 1
        }

        It 'creates Explorer\\Advanced when missing before writing ShowTaskViewButton' {
            $script:pathExists = $false

            Set-UIPersonalizationTaskViewButton -Hide

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    Context 'Set-UIPersonalizationTaskbarCombine' {
        It 'writes TaskbarGlomLevel=0 on -Always' {
            Set-UIPersonalizationTaskbarCombine -Always

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Value | Should -Be 0
        }

        It 'writes TaskbarGlomLevel=1 on -Full' {
            Set-UIPersonalizationTaskbarCombine -Full

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Value | Should -Be 1
        }

        It 'writes TaskbarGlomLevel=2 on -Never' {
            Set-UIPersonalizationTaskbarCombine -Never

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Value | Should -Be 2
        }

        It 'creates Explorer\\Advanced when missing before writing TaskbarGlomLevel' {
            $script:pathExists = $false

            Set-UIPersonalizationTaskbarCombine -Always

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    Context 'Set-UIPersonalizationTaskbarEndTask' {
        It 'creates the TaskbarDeveloperSettings key when missing before writing the value' {
            $script:pathExists = $false

            Set-UIPersonalizationTaskbarEndTask -Enable

            $script:newItemCalls.Count | Should -Be 1
            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'Set-UIPersonalizationTaskbarEndTask' }).Value | Should -Be 1
        }

        It 'removes Set-UIPersonalizationTaskbarEndTask on Disable when the property exists' {
            $script:pathExists = $true
            $script:hasExistingProperty = $true

            Set-UIPersonalizationTaskbarEndTask -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'Set-UIPersonalizationTaskbarEndTask'
        }
    }

    Context 'Set-TaskbarAcrylicOpacity' {
        It 'rejects an opacity above 100' {
            { Set-TaskbarAcrylicOpacity -Opacity 150 } | Should -Throw
        }

        It 'rejects a negative opacity' {
            { Set-TaskbarAcrylicOpacity -Opacity -1 } | Should -Throw
        }

        It 'writes TaskbarAcrylicOpacity with the provided value via Set-RegistryValueSafe' {
            Set-TaskbarAcrylicOpacity -Opacity 45

            $script:setRegistrySafeCalls[0].Name | Should -Be 'TaskbarAcrylicOpacity'
            $script:setRegistrySafeCalls[0].Value | Should -Be 45
        }
    }

    Context 'Set-SmallTaskbarIcons' {
        It 'writes TaskbarSmallIcons=1 via Set-RegistryValueSafe on Enable' {
            Set-SmallTaskbarIcons -Enable

            $script:setRegistrySafeCalls[0].Name | Should -Be 'TaskbarSmallIcons'
            $script:setRegistrySafeCalls[0].Value | Should -Be 1
        }

        It 'removes TaskbarSmallIcons via Remove-RegistryValueSafe on Disable' {
            Set-SmallTaskbarIcons -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'TaskbarSmallIcons'
        }
    }

    Context 'Set-AltTabEdgeTabFilter' {
        It 'writes MultiTaskingAltTabFilter=1 on Enable' {
            Set-AltTabEdgeTabFilter -Enable

            $script:setRegistrySafeCalls[0].Name | Should -Be 'MultiTaskingAltTabFilter'
            $script:setRegistrySafeCalls[0].Value | Should -Be 1
        }

        It 'removes MultiTaskingAltTabFilter on Disable' {
            Set-AltTabEdgeTabFilter -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'MultiTaskingAltTabFilter'
        }
    }

    Context 'BatteryPercentage' {
        BeforeEach {
            $script:hasBattery = $true
            function Get-CimInstance {
                param([string]$ClassName)
                if ($script:hasBattery) { return [pscustomobject]@{ Name = 'Battery' } }
                return $null
            }
            function Write-SwallowedException {
                param([object]$ErrorRecord, [string]$Source)
            }
        }

        AfterEach {
            Microsoft.PowerShell.Management\Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
            Microsoft.PowerShell.Management\Remove-Item Function:\Write-SwallowedException -ErrorAction SilentlyContinue
        }

        It 'writes IsBatteryPercentageEnabled=1 on Enable when a battery is present' {
            BatteryPercentage -Enable

            $script:setRegistrySafeCalls[0].Name | Should -Be 'IsBatteryPercentageEnabled'
            $script:setRegistrySafeCalls[0].Value | Should -Be 1
            $script:setRegistrySafeCalls[0].Type | Should -Be 'DWord'
        }

        It 'removes IsBatteryPercentageEnabled on Disable' {
            BatteryPercentage -Disable

            $script:removeRegistrySafeCalls[0].Name | Should -Be 'IsBatteryPercentageEnabled'
            $script:setRegistrySafeCalls.Count | Should -Be 0
        }

        It 'short-circuits with no registry write on a desktop (no battery)' {
            $script:hasBattery = $false

            BatteryPercentage -Enable

            $script:setRegistrySafeCalls.Count | Should -Be 0
            $script:removeRegistrySafeCalls.Count | Should -Be 0
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'reports failed and logs when the registry write throws' {
            $script:shouldThrow = $true

            BatteryPercentage -Enable

            $script:consoleStatuses[-1] | Should -Be 'failed'
            $script:errorMessages.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Invoke-UIPersonalizationTaskbarShortcutUnpin parameter validation' {
        It 'requires the -Shortcuts parameter' {
            { Invoke-UIPersonalizationTaskbarShortcutUnpin } | Should -Throw
        }

        It 'rejects an invalid shortcut name' {
            { Invoke-UIPersonalizationTaskbarShortcutUnpin -Shortcuts 'NonExistent' } | Should -Throw
        }
    }
}
