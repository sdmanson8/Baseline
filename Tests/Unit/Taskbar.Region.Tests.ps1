Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Taskbar.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    # Only load the outer (top-level) functions; skip any nested ones (e.g. UnpinTaskbarShortcuts' internals)
    $functions = $ast.FindAll({
            param($node)
            ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
            ($node.Parent -is [System.Management.Automation.Language.NamedBlockAst])
        }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Taskbar.psm1 region' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setRegistrySafeCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setViewModeCalls = [System.Collections.Generic.List[object]]::new()
        $script:ucpdScriptBlocks = [System.Collections.Generic.List[string]]::new()
        $script:getPackageReturns = $true
        $script:getAppxPackageReturns = $true
        $script:machineIdReturn = 'MACHINE-1234'
        $script:settingsBytes = [byte[]]::new(80)
        $script:stuckRectsAvailable = $true
        $script:setViewModeThrows = $false
        $script:pathExists = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
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
            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; PropertyType = $PropertyType })
        }
        function Set-RegistryValueSafe {
            [CmdletBinding()]
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            [void]$script:setRegistrySafeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        }
        function Remove-ItemProperty {
            [CmdletBinding()]
            param([string[]]$Path, [string[]]$Name, [switch]$Force)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Remove-RegistryValueSafe {
            [CmdletBinding()]
            param([string[]]$Path, [string[]]$Name)
            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Get-ItemPropertyValue {
            [CmdletBinding()]
            param([string]$Path, [string]$Name)
            if (-not $script:stuckRectsAvailable) { throw 'no StuckRects3' }
            return $script:settingsBytes
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
        function Get-Package {
            param([string]$Name, [string]$ProviderName)
            if ($script:getPackageReturns) { return [pscustomobject]@{ Name = 'Microsoft Edge' } }
            return $null
        }
        function Set-NewsInterestsTaskbarViewMode {
            param([string]$MachineId, [int]$ViewMode)
            if ($script:setViewModeThrows) { throw 'view-mode update failed' }
            [void]$script:setViewModeCalls.Add([pscustomobject]@{ MachineId = $MachineId; ViewMode = $ViewMode })
        }
        function Remove-HandledErrorRecord { param([object]$ErrorRecord) }
        function Get-TweakSkipLabel { param([object]$MyInvocation) return 'label' }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Test-Path','New-Item','New-ItemProperty','Set-RegistryValueSafe','Remove-ItemProperty','Remove-RegistryValueSafe','Get-ItemPropertyValue','Set-Policy','Get-AppxPackage','Invoke-UCPDBypassed','Get-Package','Set-NewsInterestsTaskbarViewMode','Remove-HandledErrorRecord','Get-TweakSkipLabel')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    Context 'NewsInterests' {
        BeforeEach {
            $Global:Localization = [pscustomobject]@{ Skipped = '{0} skipped' }
        }

        AfterEach {
            Remove-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
        }

        It 'requires Enable or Disable' {
            { NewsInterests } | Should -Throw
        }

        It 'skips without calling the helper when Edge is not installed' {
            $script:getPackageReturns = $false

            NewsInterests -Disable

            $script:setViewModeCalls.Count | Should -Be 0
            $script:consoleStatuses.Count | Should -Be 0
        }

        It 'calls Set-NewsInterestsTaskbarViewMode with ViewMode 2 on Disable' {
            $script:getPackageReturns = $true

            # The function reads MachineId via [Microsoft.Win32.Registry]::GetValue. We can't
            # easily mock that static call, so we accept whatever real value the host has.
            # Instead we skip if no MachineId is actually present.
            $hasMachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
            if (-not $hasMachineId) {
                Set-ItResult -Skipped -Because 'no SQMClient MachineId available on this host'
            }

            NewsInterests -Disable

            $script:setViewModeCalls[0].ViewMode | Should -Be 2
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'calls Set-NewsInterestsTaskbarViewMode with ViewMode 0 on Enable' {
            $script:getPackageReturns = $true

            $hasMachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
            if (-not $hasMachineId) {
                Set-ItResult -Skipped -Because 'no SQMClient MachineId available on this host'
            }

            NewsInterests -Enable

            $script:setViewModeCalls[0].ViewMode | Should -Be 0
        }

        It 'records a warning when Set-NewsInterestsTaskbarViewMode throws' {
            $script:setViewModeThrows = $true

            $hasMachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
            if (-not $hasMachineId) {
                Set-ItResult -Skipped -Because 'no SQMClient MachineId available on this host'
            }

            NewsInterests -Enable

            $script:consoleStatuses[-1] | Should -Be 'warning'
            $script:warningMessages[0] | Should -Match 'News and Interests'
        }
    }

    Context 'MeetNow' {
        It 'requires Hide or Show' {
            { MeetNow } | Should -Throw
        }

        It 'sets byte index 9 to 128 and writes the binary blob on Hide' {
            $script:settingsBytes = [byte[]](0..31)

            MeetNow -Hide

            $script:setRegistrySafeCalls.Count | Should -Be 1
            $script:setRegistrySafeCalls[0].Name | Should -Be 'Settings'
            $script:setRegistrySafeCalls[0].Type | Should -Be 'Binary'
            $script:setRegistrySafeCalls[0].Value[9] | Should -Be 128
        }

        It 'sets byte index 9 to 0 on Show' {
            $script:settingsBytes = [byte[]](0..31)
            $script:settingsBytes[9] = 128

            MeetNow -Show

            $script:setRegistrySafeCalls[0].Value[9] | Should -Be 0
        }

        It 'reports failed when StuckRects3 cannot be read' {
            $script:stuckRectsAvailable = $false

            MeetNow -Hide

            $script:consoleStatuses[-1] | Should -Be 'failed'
        }
    }

    Context 'TaskbarAlignment' {
        It 'writes TaskbarAl=0 on Left' {
            TaskbarAlignment -Left

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarAl' }).Value | Should -Be 0
        }

        It 'writes TaskbarAl=1 on Center' {
            TaskbarAlignment -Center

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarAl' }).Value | Should -Be 1
        }

        It 'creates Explorer\\Advanced when missing before writing TaskbarAl' {
            $script:pathExists = $false

            TaskbarAlignment -Center

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    Context 'TaskbarWidgets' {
        BeforeEach {
            $Global:Localization = [pscustomobject]@{ Skipped = '{0} skipped' }
        }

        AfterEach {
            Remove-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
        }

        It 'creates Explorer\\Advanced inside the UCPD bypass script before writing TaskbarDa' {
            TaskbarWidgets -Hide

            $script:ucpdScriptBlocks[0] | Should -Match 'New-Item -Path \$path -Force -ErrorAction Stop'
            $script:ucpdScriptBlocks[0] | Should -Match 'TaskbarDa'
        }

        It 'returns without touching registry or policy when WebExperience package is absent' {
            $script:getAppxPackageReturns = $false

            TaskbarWidgets -Hide

            $script:ucpdScriptBlocks.Count | Should -Be 0
            $script:newItemPropertyCalls.Count | Should -Be 0
            $script:removeItemPropertyCalls.Count | Should -Be 0
            $script:policyCalls.Count | Should -Be 0
            $script:consoleStatuses.Count | Should -Be 0
        }
    }

    Context 'TaskbarSearch' {
        It 'creates the Search key when missing before writing SearchboxTaskbarMode' {
            $script:pathExists = $false

            TaskbarSearch -SearchBox

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'SearchboxTaskbarMode' }).Value | Should -Be 2
        }
    }

    Context 'SearchHighlights' {
        It 'creates SearchSettings when missing before writing IsDynamicSearchBoxEnabled' {
            $script:pathExists = $false

            SearchHighlights -Show

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'IsDynamicSearchBoxEnabled' }).Value | Should -Be 1
        }
    }

    Context 'TaskViewButton' {
        It 'writes ShowTaskViewButton=0 on Hide' {
            TaskViewButton -Hide

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowTaskViewButton' }).Value | Should -Be 0
        }

        It 'writes ShowTaskViewButton=1 on Show' {
            TaskViewButton -Show

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'ShowTaskViewButton' }).Value | Should -Be 1
        }

        It 'creates Explorer\\Advanced when missing before writing ShowTaskViewButton' {
            $script:pathExists = $false

            TaskViewButton -Hide

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    Context 'TaskbarCombine' {
        It 'writes TaskbarGlomLevel=0 on Always' {
            TaskbarCombine -Always

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Value | Should -Be 0
        }

        It 'writes TaskbarGlomLevel=2 on Never' {
            TaskbarCombine -Never

            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarGlomLevel' }).Value | Should -Be 2
        }

        It 'creates Explorer\\Advanced when missing before writing TaskbarGlomLevel' {
            $script:pathExists = $false

            TaskbarCombine -Full

            $script:newItemCalls | Should -Contain 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
    }

    Context 'TaskbarEndTask' {
        It 'creates the key when missing and writes TaskbarEndTask=1 on Enable' {
            $script:pathExists = $false

            TaskbarEndTask -Enable

            $script:newItemCalls.Count | Should -Be 1
            ($script:setRegistrySafeCalls | Where-Object { $_.Name -eq 'TaskbarEndTask' }).Value | Should -Be 1
        }
    }

    Context 'UnpinTaskbarShortcuts parameter validation' {
        It 'requires -Shortcuts' {
            { UnpinTaskbarShortcuts } | Should -Throw
        }
    }
}
