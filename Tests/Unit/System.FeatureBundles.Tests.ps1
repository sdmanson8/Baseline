Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.FeatureBundles.psm1'
    $manifestPath = Join-Path $PSScriptRoot '../../Module/Data/System.json'
    $script:SystemManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Set-OptionalFeatureBundleState', 'LegacyMediaBundle', 'NfsBundle', 'HyperVManagementTools')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Feature bundle wrappers' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:featureCalls = [System.Collections.Generic.List[object]]::new()

        <#
            .SYNOPSIS
        #>

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )

            if (-not [string]::IsNullOrWhiteSpace($Action)) {
                [void]$script:consoleActions.Add($Action)
            }
            if (-not [string]::IsNullOrWhiteSpace($Status)) {
                [void]$script:consoleStatuses.Add($Status)
            }
        }

        <#
            .SYNOPSIS
        #>

        function LogInfo {
            param([string]$Message)
            [void]$script:loggedInfoMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function LogError {
            param([string]$Message)
            [void]$script:loggedErrorMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function Invoke-SilencedProgress {
            param([scriptblock]$ScriptBlock)
            & $ScriptBlock
        }

        <#
            .SYNOPSIS
        #>

        function Enable-WindowsOptionalFeature {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$FeatureName,
                [switch]$Online,
                [switch]$All,
                [switch]$NoRestart,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:featureCalls.Add([pscustomobject]@{
                Command = 'Enable'
                FeatureName = $FeatureName
                All = [bool]$All
            })
        }

        <#
            .SYNOPSIS
        #>

        function Disable-WindowsOptionalFeature {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$FeatureName,
                [switch]$Online,
                [switch]$NoRestart,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:featureCalls.Add([pscustomobject]@{
                Command = 'Disable'
                FeatureName = $FeatureName
                All = $false
            })
        }

        <#
            .SYNOPSIS
        #>

        function nfsadmin {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$Arguments
            )

            [void]$script:featureCalls.Add([pscustomobject]@{
                Command = 'nfsadmin'
                Arguments = @($Arguments)
            })
        }

        <#
            .SYNOPSIS
        #>
        function Set-ItemProperty {
            param(
                [string]$Path, [string]$LiteralPath,
                [string]$Name,
                [object]$Value,
                [object]$ErrorAction
            )

            [void]$script:featureCalls.Add([pscustomobject]@{
                Command = 'Set-ItemProperty'
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
                Value = $Value
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-SilencedProgress -ErrorAction SilentlyContinue
        Remove-Item Function:\Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue
        Remove-Item Function:\nfsadmin -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'enables the Legacy Media bundle' {
        LegacyMediaBundle -Enable

        $script:featureCalls.Count | Should -Be 4
        $script:featureCalls[0].Command | Should -Be 'Enable'
        $script:featureCalls[0].FeatureName | Should -Be 'Media.WindowsMediaPlayer'
        $script:featureCalls[1].FeatureName | Should -Be 'MediaPlayback'
        $script:featureCalls[2].FeatureName | Should -Be 'DirectPlay'
        $script:featureCalls[3].FeatureName | Should -Be 'LegacyComponents'
        $script:consoleActions[0] | Should -Be 'Enabling Legacy Media bundle'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'disables the Legacy Media bundle' {
        LegacyMediaBundle -Disable

        $script:featureCalls.Count | Should -Be 4
        @($script:featureCalls | ForEach-Object Command) | Should -Be @('Disable', 'Disable', 'Disable', 'Disable')
        $script:consoleActions[0] | Should -Be 'Disabling Legacy Media bundle'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'enables the NFS bundle and applies the client defaults' {
        NfsBundle -Enable

        $script:featureCalls.Count | Should -Be 8
        $script:featureCalls[0].FeatureName | Should -Be 'ServicesForNFS-ClientOnly'
        $script:featureCalls[1].FeatureName | Should -Be 'ClientForNFS-Infrastructure'
        $script:featureCalls[2].FeatureName | Should -Be 'NFS-Administration'
        $script:featureCalls[3].Command | Should -Be 'nfsadmin'
        @($script:featureCalls[3].Arguments) | Should -Be @('client', 'stop')
        $script:featureCalls[4].Command | Should -Be 'Set-ItemProperty'
        $script:featureCalls[4].Name | Should -Be 'AnonymousUID'
        $script:featureCalls[5].Name | Should -Be 'AnonymousGID'
        $script:featureCalls[6].Command | Should -Be 'nfsadmin'
        @($script:featureCalls[6].Arguments) | Should -Be @('client', 'start')
        $script:featureCalls[7].Command | Should -Be 'nfsadmin'
        @($script:featureCalls[7].Arguments) | Should -Be @('client', 'localhost', 'config', 'fileaccess=755', 'SecFlavors=+sys', '-krb5', '-krb5i')
        $script:consoleActions[0] | Should -Be 'Enabling NFS bundle'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'disables the NFS bundle without applying the client defaults' {
        NfsBundle -Disable

        $script:featureCalls.Count | Should -Be 3
        @($script:featureCalls | ForEach-Object Command) | Should -Be @('Disable', 'Disable', 'Disable')
        $script:consoleActions[0] | Should -Be 'Disabling NFS bundle'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'enables Hyper-V management tools with the all flag' {
        HyperVManagementTools -Enable

        $script:featureCalls.Count | Should -Be 1
        $script:featureCalls[0].Command | Should -Be 'Enable'
        $script:featureCalls[0].FeatureName | Should -Be 'Microsoft-Hyper-V-Tools-All'
        $script:featureCalls[0].All | Should -Be $true
        $script:consoleActions[0] | Should -Be 'Enabling Hyper-V Management Tools'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'disables Hyper-V management tools' {
        HyperVManagementTools -Disable

        $script:featureCalls.Count | Should -Be 1
        $script:featureCalls[0].Command | Should -Be 'Disable'
        $script:featureCalls[0].FeatureName | Should -Be 'Microsoft-Hyper-V-Tools-All'
        $script:featureCalls[0].All | Should -Be $false
        $script:consoleActions[0] | Should -Be 'Disabling Hyper-V Management Tools'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'declares servicing-length GUI execution timeouts for Windows feature bundles' {
        foreach ($functionName in @('LegacyMediaBundle', 'NfsBundle', 'HyperVManagementTools')) {
            $entry = $script:SystemManifest.Entries | Where-Object { $_.Function -eq $functionName } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty
            [int]$entry.TimeoutSeconds | Should -BeGreaterOrEqual 900
        }
    }
}
