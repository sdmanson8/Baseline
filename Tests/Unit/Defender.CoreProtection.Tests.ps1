Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.CoreProtection.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'DNSoverHTTPS') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'DNSoverHTTPS' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:setDnsCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:clearCacheCount = 0
        $script:registerDnsCount = 0

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
            [void]$script:infoMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function LogWarning {
            param([string]$Message)
            [void]$script:warningMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function LogError {
            param([string]$Message)
            [void]$script:errorMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>

        function Get-CimInstance {
            param([string]$ClassName)

            [pscustomobject]@{
                HypervisorPresent = $false
            }
        }

        <#
            .SYNOPSIS
        #>
        function Get-NetAdapter {
            param([switch]$Physical)

            [pscustomobject]@{
                InterfaceGuid = 'guid-1'
            }
        }

        <#
            .SYNOPSIS
        #>

        function Set-DnsClientServerAddress {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline = $true)]
                [object]$InputObject,

                [string[]]$ServerAddresses,
                [switch]$ResetServerAddresses
            )

            process {
                [void]$script:setDnsCalls.Add([pscustomobject]@{
                    InputObject = $InputObject
                    ServerAddresses = @($ServerAddresses)
                    ResetServerAddresses = [bool]$ResetServerAddresses
                })
            }
        }

        <#
            .SYNOPSIS
        #>

        function Test-Path {
            param([string]$Path)

            return $false
        }

        <#
            .SYNOPSIS
        #>
        function New-Item {
            param(
                [string]$Path,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:newItemCalls.Add($Path)
        }

        <#
            .SYNOPSIS
        #>

        function New-ItemProperty {
            param(
                [string]$Path,
                [string]$Name,
                [string]$PropertyType,
                [object]$Value,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:newItemPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
                PropertyType = $PropertyType
                Value = $Value
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

            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
                Value = $Value
            })
        }

        <#
            .SYNOPSIS
        #>

        function Remove-Item {
            param(
                [string[]]$Path,
                [switch]$Recurse,
                [switch]$Force,
                [object]$ErrorAction
            )

            foreach ($itemPath in @($Path)) {
                [void]$script:removeItemCalls.Add($itemPath)
            }
        }

        <#
            .SYNOPSIS
        #>
        function Clear-DnsClientCache {
            param([object]$ErrorAction)

            $script:clearCacheCount++
        }

        <#
            .SYNOPSIS
        #>

        function Register-DnsClient {
            param([object]$ErrorAction)

            $script:registerDnsCount++
        }

        <#
            .SYNOPSIS
        #>
        function Get-ChildItem {
            param(
                [string]$LiteralPath,
                [object]$ErrorAction
            )

            @(
                [pscustomobject]@{ PSChildName = '2001:4860:4860::8888' },
                [pscustomobject]@{ PSChildName = '2001:4860:4860::8844' }
            )
        }
    }

    AfterEach {
        Microsoft.PowerShell.Management\Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Get-NetAdapter -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Set-DnsClientServerAddress -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Clear-DnsClientCache -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Register-DnsClient -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
    }

    It 'applies the Google preset with dual-stack addresses' {
        DNSoverHTTPS -Google

        $script:consoleActions[0] | Should -Be 'Enabling DNS-over-HTTPS for Google'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:infoMessages[0] | Should -Be 'Enabling DNS-over-HTTPS for Google'
        $script:errorMessages.Count | Should -Be 0

        $script:setDnsCalls.Count | Should -Be 1
        @($script:setDnsCalls[0].ServerAddresses) | Should -Be @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844')
        $script:setDnsCalls[0].ResetServerAddresses | Should -Be $false
        $script:setDnsCalls[0].InputObject.InterfaceGuid | Should -Be 'guid-1'

        $script:newItemCalls.Count | Should -Be 4
        $script:newItemPropertyCalls.Count | Should -Be 4
        $script:clearCacheCount | Should -Be 1
        $script:registerDnsCount | Should -Be 1
    }

    It 'accepts a custom IPv6 server pair' {
        DNSoverHTTPS -Enable -PrimaryDNS '2001:4860:4860::8888' -SecondaryDNS '2001:4860:4860::8844'

        $script:consoleActions[0] | Should -Be 'Enabling DNS-over-HTTPS for custom DNS servers'
        $script:setDnsCalls.Count | Should -Be 1
        @($script:setDnsCalls[0].ServerAddresses) | Should -Be @('2001:4860:4860::8888', '2001:4860:4860::8844')

        $serverPaths = @($script:newItemPropertyCalls | ForEach-Object { $_.Path })
        $serverPaths | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\guid-1\DohInterfaceSettings\Doh\2001:4860:4860::8888'
        $serverPaths | Should -Contain 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\guid-1\DohInterfaceSettings\Doh\2001:4860:4860::8844'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'disables DNS-over-HTTPS by resetting DNS servers' {
        DNSoverHTTPS -Disable

        $script:consoleActions[0] | Should -Be 'Disabling DNS-over-HTTPS'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:setDnsCalls.Count | Should -Be 1
        $script:setDnsCalls[0].ResetServerAddresses | Should -Be $true
        $script:setDnsCalls[0].InputObject.InterfaceGuid | Should -Be 'guid-1'

        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'NameServer'
        $script:removeItemCalls.Count | Should -Be 1
        $script:removeItemCalls[0] | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\guid-1\DohInterfaceSettings\Doh'
        $script:clearCacheCount | Should -Be 1
        $script:registerDnsCount | Should -Be 1
        $script:errorMessages.Count | Should -Be 0
    }
}
