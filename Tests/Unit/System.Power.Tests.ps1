Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.Power.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Hibernation' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:powercfgCalls = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:exitCode = 0

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function POWERCFG {
            [void]$script:powercfgCalls.Add($args -join ' ')
            $global:LASTEXITCODE = $script:exitCode
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','LogWarning','POWERCFG')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable (parameter set validation)' {
        { Hibernation } | Should -Throw
    }

    It 'calls POWERCFG /HIBERNATE OFF when disabling' {
        $script:exitCode = 0

        Hibernation -Disable

        $script:powercfgCalls.Count | Should -Be 1
        $script:powercfgCalls[0] | Should -Match 'HIBERNATE OFF'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'calls POWERCFG /HIBERNATE ON when enabling' {
        Hibernation -Enable
        $script:powercfgCalls[0] | Should -Match 'HIBERNATE ON'
    }

    It 'reports warning when powercfg returns a non-zero exit code' {
        $script:exitCode = 1

        Hibernation -Disable

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:errorMessages.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'exit code 1'
    }
}

Describe 'PowerPlan' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:powercfgCalls = [System.Collections.Generic.List[string]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:hasUltimate = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction)
        }
        function Set-Policy {
            param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value)
            [void]$script:policyCalls.Add([pscustomobject]@{ Scope = $Scope; Name = $Name; Type = $Type })
        }
        function POWERCFG {
            $callText = $args -join ' '
            [void]$script:powercfgCalls.Add($callText)
            if ($callText -match '/LIST') {
                if ($script:hasUltimate) { return 'Power Scheme GUID: e9a42b02-d5df-448d-aa00-03f14749eb61  (Ultimate Performance)' }
                return 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *'
            }
            return ''
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Remove-ItemProperty','Set-Policy','POWERCFG')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of High/Balanced/Ultimate' {
        { PowerPlan } | Should -Throw
    }

    It 'sets the SCHEME_MIN active plan for High' {
        PowerPlan -High
        ($script:powercfgCalls -join ' ') | Should -Match 'SCHEME_MIN'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'sets the SCHEME_BALANCED active plan for Balanced' {
        PowerPlan -Balanced
        ($script:powercfgCalls -join ' ') | Should -Match 'SCHEME_BALANCED'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'activates the Ultimate GUID when it is already present' {
        $script:hasUltimate = $true

        PowerPlan -Ultimate

        $calls = $script:powercfgCalls -join ' '
        $calls | Should -Match 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        ($script:powercfgCalls | Where-Object { $_ -match '/SETACTIVE' }).Count | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'warns when Ultimate is missing and duplication does not bring it back' {
        $script:hasUltimate = $false

        PowerPlan -Ultimate

        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Ultimate Performance'
    }
}

Describe 'PowerPlan -CustomPower (custom plan)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:powercfgCalls = [System.Collections.Generic.List[string]]::new()
        $script:hasCustomPowerGuid = $false
        $script:hasUltimate = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Remove-ItemProperty { param([string]$Path, [string]$Name, [switch]$Force, [object]$ErrorAction) }
        function Set-Policy { param([string]$Scope, [string]$Path, [string]$Name, [string]$Type, [object]$Value) }
        function POWERCFG {
            $callText = $args -join ' '
            [void]$script:powercfgCalls.Add($callText)
            if ($callText -match '/LIST') {
                $lines = @()
                if ($script:hasUltimate)        { $lines += 'Power Scheme GUID: e9a42b02-d5df-448d-aa00-03f14749eb61  (Ultimate Performance)' }
                if ($script:hasCustomPowerGuid) { $lines += 'Power Scheme GUID: 57696e68-616e-6365-506f-776572000000  (Custom Power Plan) *' }
                return ($lines -join "`n")
            }
            if ($callText -match '/DUPLICATESCHEME') {
                # Once duplication runs, the next /LIST should report the custom plan is present.
                $script:hasCustomPowerGuid = $true
            }
            return ''
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Remove-ItemProperty','Set-Policy','POWERCFG')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'duplicates the Ultimate scheme into the canonical custom GUID when missing' {
        PowerPlan -CustomPower
        $calls = $script:powercfgCalls -join ' | '
        $calls | Should -Match '/DUPLICATESCHEME e9a42b02-d5df-448d-aa00-03f14749eb61 57696e68-616e-6365-506f-776572000000'
        $calls | Should -Match '-CHANGENAME 57696e68-616e-6365-506f-776572000000 Custom Power Plan'
        $calls | Should -Match '/SETACTIVE 57696e68-616e-6365-506f-776572000000'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips duplication and goes straight to /SETACTIVE when the plan already exists' {
        $script:hasCustomPowerGuid = $true
        PowerPlan -CustomPower
        $calls = $script:powercfgCalls -join ' | '
        $calls | Should -Not -Match '/DUPLICATESCHEME'
        $calls | Should -Match '/SETACTIVE 57696e68-616e-6365-506f-776572000000'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}

Describe 'HybridSleep' {
    BeforeEach {
        $script:choiceCalls = [System.Collections.Generic.List[object]]::new()
        $script:visibilityCalls = [System.Collections.Generic.List[object]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) }
        function Set-PowerSchemeSettingVisibility {
            param([string]$SubgroupGuid, [string]$SettingGuid)
            [void]$script:visibilityCalls.Add([pscustomobject]@{ Subgroup = $SubgroupGuid; Setting = $SettingGuid })
        }
        function Set-PowerSchemeChoiceSetting {
            param([string]$DisplayName, [string]$SubgroupGuid, [string]$SettingGuid, [int]$Value)
            [void]$script:choiceCalls.Add([pscustomobject]@{
                DisplayName = $DisplayName
                Subgroup = $SubgroupGuid
                Setting = $SettingGuid
                Value = $Value
            })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','LogError','Set-PowerSchemeSettingVisibility','Set-PowerSchemeChoiceSetting')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of Enable/Disable' {
        { HybridSleep } | Should -Throw
    }

    It 'targets the SUB_SLEEP / HYBRIDSLEEP GUIDs with value 1 when enabling' {
        HybridSleep -Enable
        $script:choiceCalls.Count | Should -Be 1
        $script:choiceCalls[0].Subgroup | Should -Be '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        $script:choiceCalls[0].Setting  | Should -Be '94ac6d29-73ce-41a6-809f-6363ba21b47e'
        $script:choiceCalls[0].Value    | Should -Be 1
        $script:choiceCalls[0].DisplayName | Should -Be 'Hybrid Sleep'
    }

    It 'writes value 0 when disabling' {
        HybridSleep -Disable
        $script:choiceCalls[0].Value | Should -Be 0
    }

    It 'unhides the setting in the Power Options UI before writing' {
        HybridSleep -Enable
        $script:visibilityCalls.Count | Should -Be 1
        $script:visibilityCalls[0].Setting | Should -Be '94ac6d29-73ce-41a6-809f-6363ba21b47e'
    }

    It 'logs a warning rather than throwing when powercfg refuses (e.g., unsupported hardware)' {
        function Set-PowerSchemeChoiceSetting { param($DisplayName,$SubgroupGuid,$SettingGuid,$Value) throw 'Element not found.' }
        { HybridSleep -Enable } | Should -Not -Throw
        $script:warningMessages.Count | Should -BeGreaterThan 0
        $script:warningMessages[0] | Should -Match 'unsupported'
    }
}

Describe 'JSON entries for custom plan and HybridSleep' {
    BeforeAll {
        $jsonPath = Join-Path $PSScriptRoot '../../Module/Data/System.json'
        $script:SystemJson = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    }

    It 'PowerPlan exposes Custom as a Choice option with display label' {
        $entry = $script:SystemJson.Entries | Where-Object { $_.Function -eq 'PowerPlan' }
        $entry | Should -Not -BeNullOrEmpty
        $entry.Options | Should -Contain 'Custom'
        $entry.DisplayOptions | Should -Contain 'Custom Power Plan'
    }

    It 'HybridSleep is registered as a Toggle with Enable/Disable params' {
        $entry = $script:SystemJson.Entries | Where-Object { $_.Function -eq 'HybridSleep' }
        $entry | Should -Not -BeNullOrEmpty
        $entry.Type     | Should -Be 'Toggle'
        $entry.OnParam  | Should -Be 'Enable'
        $entry.OffParam | Should -Be 'Disable'
        $entry.Tags     | Should -Contain 'sleep'
    }
}

Describe 'ProcessorMinimumState / ProcessorMaximumState' {
    BeforeEach {
        $script:numericCalls = [System.Collections.Generic.List[object]]::new()

        function Set-PowerSchemeNumericRangeSetting {
            param(
                [string]$DisplayName,
                [string]$SubgroupGuid,
                [string]$SettingGuid,
                [int]$Value,
                [int]$ACValue,
                [int]$DCValue
            )
            [void]$script:numericCalls.Add([pscustomobject]@{
                DisplayName = $DisplayName
                SettingGuid = $SettingGuid
                Value = $Value
                ACValue = $ACValue
                DCValue = $DCValue
                ParameterSet = $PSCmdlet.ParameterSetName
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Set-PowerSchemeNumericRangeSetting -ErrorAction SilentlyContinue
    }

    It 'rejects Value outside 0..100' {
        { ProcessorMinimumState -Value 150 } | Should -Throw
        { ProcessorMinimumState -Value -1 } | Should -Throw
    }

    It 'forwards a single numeric value to the helper' {
        ProcessorMinimumState -Value 50

        $script:numericCalls.Count | Should -Be 1
        $script:numericCalls[0].DisplayName | Should -Be 'processor minimum state'
        $script:numericCalls[0].Value | Should -Be 50
    }

    It 'forwards AC/DC channel values to the helper' {
        ProcessorMaximumState -ACValue 100 -DCValue 80

        $script:numericCalls.Count | Should -Be 1
        $script:numericCalls[0].DisplayName | Should -Be 'processor maximum state'
        $script:numericCalls[0].ACValue | Should -Be 100
        $script:numericCalls[0].DCValue | Should -Be 80
    }
}

Describe 'Set-PowerSchemeNumericRangeSetting' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:visibilityCalls = [System.Collections.Generic.List[object]]::new()
        $script:valueCalls = [System.Collections.Generic.List[object]]::new()
        $script:valueSetterThrows = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function Set-PowerSchemeSettingVisibility {
            param([string]$SubgroupGuid, [string]$SettingGuid)
            [void]$script:visibilityCalls.Add([pscustomobject]@{ SubgroupGuid = $SubgroupGuid; SettingGuid = $SettingGuid })
        }
        function Set-PowerSchemeSettingValue {
            param([string]$SubgroupGuid, [string]$SettingGuid, [object]$Value, [string]$Units)
            if ($script:valueSetterThrows) { throw 'powercfg rejected setting' }
            [void]$script:valueCalls.Add([pscustomobject]@{ Value = $Value; Units = $Units })
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','LogWarning','Set-PowerSchemeSettingVisibility','Set-PowerSchemeSettingValue')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'applies a single numeric value through visibility + value helpers' {
        Set-PowerSchemeNumericRangeSetting -DisplayName 'x' -SubgroupGuid 'g1' -SettingGuid 's1' -Value 50

        $script:visibilityCalls.Count | Should -Be 1
        $script:valueCalls.Count | Should -Be 1
        $script:valueCalls[0].Value | Should -Be 50
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'applies AC/DC channel values as an ordered hashtable' {
        Set-PowerSchemeNumericRangeSetting -DisplayName 'x' -SubgroupGuid 'g1' -SettingGuid 's1' -ACValue 100 -DCValue 40

        $script:valueCalls.Count | Should -Be 1
        $script:valueCalls[0].Value.ACValue | Should -Be 100
        $script:valueCalls[0].Value.DCValue | Should -Be 40
    }

    It 'logs an error and reports failed status when a value is outside MinValue/MaxValue' {
        Set-PowerSchemeNumericRangeSetting -DisplayName 'x' -SubgroupGuid 'g1' -SettingGuid 's1' -Value 50 -MinValue 80 -MaxValue 90

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'outside the supported range'
        $script:valueCalls.Count | Should -Be 0
    }

    It 'logs a warning and reports warning status when Windows rejects the power setting' {
        $script:valueSetterThrows = $true

        Set-PowerSchemeNumericRangeSetting -DisplayName 'x' -SubgroupGuid 'g1' -SettingGuid 's1' -Value 50

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:errorMessages.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'powercfg rejected setting'
    }
}

Describe 'Set-PowerSchemeChoiceSetting' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function Set-PowerSchemeSettingVisibility { param([string]$SubgroupGuid, [string]$SettingGuid) }
        function Set-PowerSchemeSettingValue { param([string]$SubgroupGuid, [string]$SettingGuid, [object]$Value) throw 'powercfg rejected choice' }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','LogWarning','Set-PowerSchemeSettingVisibility','Set-PowerSchemeSettingValue')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'logs a warning and reports warning status when Windows rejects the choice setting' {
        Set-PowerSchemeChoiceSetting -DisplayName 'x' -SubgroupGuid 'g1' -SettingGuid 's1' -Value 2

        $script:consoleStatuses[-1] | Should -Be 'warning'
        $script:errorMessages.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'powercfg rejected choice'
    }
}
