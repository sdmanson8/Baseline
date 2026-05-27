Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.Networking.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('DeliveryOptimization', 'DnsProvider', 'NtpServerOverride', 'OpenSSHServer')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'DeliveryOptimization' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:policyCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:cacheCleanupCount = 0

        <#
            .SYNOPSIS
        #>

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )
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

        function Set-Policy {
            param(
                [string]$Scope,
                [string]$Path,
                [string]$Name,
                [string]$Type,
                [object]$Value
            )

            [void]$script:policyCalls.Add([pscustomobject]@{
                Scope = $Scope
                Path  = $Path
                Name  = $Name
                Type  = $Type
                Value = $Value
            })
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
                Path         = $Path
                Name         = $Name
                PropertyType = $PropertyType
                Value        = $Value
            })
        }

        <#
            .SYNOPSIS
        #>

        function Delete-DeliveryOptimizationCache {
            param(
                [switch]$Force,
                [object]$ErrorAction
            )

            $script:cacheCleanupCount++
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Policy -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue
    }

    It 'writes the policy-disabled state when turning Delivery Optimization off' {
        DeliveryOptimization -Disable

        $script:policyCalls.Count | Should -Be 1
        $script:policyCalls[0].Scope | Should -Be 'Computer'
        $script:policyCalls[0].Path | Should -Be 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        $script:policyCalls[0].Name | Should -Be 'DODownloadMode'
        $script:policyCalls[0].Type | Should -Be 'DWord'
        $script:policyCalls[0].Value | Should -Be 99
        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Value | Should -Be 0
        $script:cacheCleanupCount | Should -Be 1
    }

    It 'clears the policy state when turning Delivery Optimization on' {
        DeliveryOptimization -Enable

        $script:policyCalls.Count | Should -Be 1
        $script:policyCalls[0].Type | Should -Be 'CLEAR'
        $script:policyCalls[0].Value | Should -BeNullOrEmpty
        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Value | Should -Be 1
        $script:cacheCleanupCount | Should -Be 0
    }
}

Describe 'DnsProvider' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $script:NetworkingContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.Networking.psm1')
    }

    It 'applies the Google preset to every adapter that is Up' {
        $script:NetworkingContent | Should -Match 'foreach \(\$Adapter in @\(& \$getNetAdapterCommand \| Where-Object -FilterScript \{ \$_.Status -eq ''Up'' \}\)\)'
        $script:NetworkingContent | Should -Match '& \$setDnsClientServerAddressCommand -InterfaceIndex \$Adapter.ifIndex -ServerAddresses \$provider.IPv4Addresses -ErrorAction Stop'
        $script:NetworkingContent | Should -Match '& \$setDnsClientServerAddressCommand -InterfaceIndex \$Adapter.ifIndex -ServerAddresses \$provider.IPv6Addresses -ErrorAction Stop'
    }

    It 'restores automatic DNS assignment when DHCP is selected' {
        $script:NetworkingContent | Should -Match 'Write-ConsoleStatus -Action "Restoring DNS server settings to DHCP"'
        $script:NetworkingContent | Should -Match 'foreach \(\$Adapter in @\(& \$getNetAdapterCommand \| Where-Object -FilterScript \{ \$_.Status -eq ''Up'' \}\)\)'
        $script:NetworkingContent | Should -Match '& \$setDnsClientServerAddressCommand -InterfaceIndex \$Adapter.ifIndex -ResetServerAddresses -ErrorAction Stop'
        $script:NetworkingContent | Should -Match 'Write-ConsoleStatus -Status success'
    }

    It 'leaves the current DNS settings unchanged for Default' {
        $result = & {
            $loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
            $loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
            $loggedWarningMessages = [System.Collections.Generic.List[string]]::new()
            $consoleActions = [System.Collections.Generic.List[string]]::new()
            $consoleStatuses = [System.Collections.Generic.List[string]]::new()
            $dnsCalls = [System.Collections.Generic.List[object]]::new()

            <#
                .SYNOPSIS
            #>

            function Write-ConsoleStatus {
                param(
                    [string]$Action,
                    [string]$Status
                )

                if (-not [string]::IsNullOrWhiteSpace($Action)) {
                    [void]$consoleActions.Add($Action)
                }
                if (-not [string]::IsNullOrWhiteSpace($Status)) {
                    [void]$consoleStatuses.Add($Status)
                }
            }

            <#
                .SYNOPSIS
            #>

            function LogInfo {
                param([string]$Message)
                [void]$loggedInfoMessages.Add($Message)
            }

            <#
                .SYNOPSIS
            #>
            function LogWarning {
                param([string]$Message)
                [void]$loggedWarningMessages.Add($Message)
            }

            <#
                .SYNOPSIS
            #>
            function LogError {
                param([string]$Message)
                [void]$loggedErrorMessages.Add($Message)
            }

            <#
                .SYNOPSIS
            #>

            function Get-NetAdapter {
                return @(
                    [pscustomobject]@{
                        Status = 'Up'
                        ifIndex = 11
                        Name = 'Ethernet'
                    },
                    [pscustomobject]@{
                        Status = 'Down'
                        ifIndex = 12
                        Name = 'Wi-Fi'
                    }
                )
            }

            <#
                .SYNOPSIS
            #>

            function Set-DnsClientServerAddress {
                [CmdletBinding()]
                param(
                    [int]$InterfaceIndex,
                    [string[]]$ServerAddresses,
                    [switch]$ResetServerAddresses,
                    [object]$ErrorAction
                )

                [void]$dnsCalls.Add([pscustomobject]@{
                    InterfaceIndex = $InterfaceIndex
                    ServerAddresses = @($ServerAddresses)
                    ResetServerAddresses = [bool]$ResetServerAddresses
                })
            }

            DnsProvider -Default

            [pscustomobject]@{
                DnsCalls            = $dnsCalls
                ConsoleActions      = $consoleActions
                ConsoleStatuses     = $consoleStatuses
                LoggedErrorMessages = $loggedErrorMessages
            }
        }

        $result.DnsCalls.Count | Should -Be 0
        $result.ConsoleActions[0] | Should -Be 'Leaving DNS provider settings unchanged'
        $result.ConsoleStatuses[-1] | Should -Be 'success'
        $result.LoggedErrorMessages.Count | Should -Be 0
    }
}

Describe 'NtpServerOverride' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:callSequence = [System.Collections.Generic.List[string]]::new()

        <#
            .SYNOPSIS
        #>

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )
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

        function Start-Service {
            param(
                [string]$Name,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Start-Service:{0}' -f $Name))
        }

        <#
            .SYNOPSIS
        #>
        function Restart-Service {
            param(
                [string]$Name,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Restart-Service:{0}' -f $Name))
        }

        <#
            .SYNOPSIS
        #>

        function w32tm {
            [void]$script:callSequence.Add("w32tm:$($args -join ' ')")
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Start-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Restart-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\w32tm -ErrorAction SilentlyContinue
    }

    It 'configures pool.ntp.org when enabling the override' {
        NtpServerOverride -Enable

        $script:callSequence.Count | Should -Be 4
        $script:callSequence[0] | Should -Be 'Start-Service:w32time'
        $script:callSequence[1] | Should -Be 'w32tm:/config /update /manualpeerlist:pool.ntp.org,0x8 /syncfromflags:MANUAL'
        $script:callSequence[2] | Should -Be 'Restart-Service:w32time'
        $script:callSequence[3] | Should -Be 'w32tm:/resync'
        $script:loggedInfoMessages[0] | Should -Be 'Setting Windows Time server override to pool.ntp.org'
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'restores time.windows.com when disabling the override' {
        NtpServerOverride -Disable

        $script:callSequence.Count | Should -Be 4
        $script:callSequence[0] | Should -Be 'Start-Service:w32time'
        $script:callSequence[1] | Should -Be 'w32tm:/config /update /manualpeerlist:time.windows.com,0x8 /syncfromflags:MANUAL'
        $script:callSequence[2] | Should -Be 'Restart-Service:w32time'
        $script:callSequence[3] | Should -Be 'w32tm:/resync'
        $script:loggedInfoMessages[0] | Should -Be 'Restoring Windows Time server to time.windows.com'
        $script:loggedErrorMessages.Count | Should -Be 0
    }
}

Describe 'OpenSSHServer' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:callSequence = [System.Collections.Generic.List[string]]::new()
        $script:configWriteValue = $null
        $script:sshFirewallRuleExists = $true

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
        function Get-WindowsCapability {
            param(
                [string]$Name,
                [switch]$Online,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Get-WindowsCapability:{0}' -f $Name))
            [pscustomobject]@{
                State = 'NotPresent'
            }
        }

        <#
            .SYNOPSIS
        #>

        function Add-WindowsCapability {
            param(
                [switch]$Online,
                [string]$Name,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Add-WindowsCapability:{0}' -f $Name))
        }

        <#
            .SYNOPSIS
        #>
        function Set-Service {
            param(
                [string]$Name,
                [string]$StartupType,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Set-Service:{0}:{1}' -f $Name, $StartupType))
        }

        <#
            .SYNOPSIS
        #>

        function Start-Service {
            param(
                [string]$Name,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Start-Service:{0}' -f $Name))
        }

        <#
            .SYNOPSIS
        #>
        function Get-NetFirewallRule {
            param(
                [string]$Name,
            [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Get-NetFirewallRule:{0}' -f $Name))
            if (-not $script:sshFirewallRuleExists)
            {
                return $null
            }
            [pscustomobject]@{
                Enabled = $false
            }
        }

        function Set-NetFirewallRule {
            param(
                [string]$Name,
                [string]$Enabled,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Set-NetFirewallRule:{0}:{1}' -f $Name, $Enabled))
        }

        <#
            .SYNOPSIS
        #>

        function New-NetFirewallRule {
            param(
                [string]$Name,
                [string]$DisplayName,
                [bool]$Enabled,
                [string]$Direction,
                [string]$Protocol,
                [string]$Action,
                [int]$LocalPort,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('New-NetFirewallRule:{0}' -f $Name))
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
                [string]$ItemType,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('New-Item:{0}:{1}' -f $ItemType, $Path))
        }

        <#
            .SYNOPSIS
        #>

        function Get-Content {
            param(
                [string]$Path,
                [switch]$Raw,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Get-Content:{0}' -f $Path))
            @"
Match Group administrators
  AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@
        }

        <#
            .SYNOPSIS
        #>

        function Set-Content {
            param(
                [string]$Path,
                [string]$Value,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Set-Content:{0}' -f $Path))
            $script:configWriteValue = $Value
        }

        <#
            .SYNOPSIS
        #>
        function Restart-Service {
            param(
                [string]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:callSequence.Add(('Restart-Service:{0}' -f $Name))
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-WindowsCapability -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-WindowsCapability -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Start-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item Function:\New-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Content -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Content -ErrorAction SilentlyContinue
        Remove-Item Function:\Restart-Service -ErrorAction SilentlyContinue
    }

    It 'installs OpenSSH Server and normalizes the standard SSH config' {
        OpenSSHServer

        $script:callSequence[0] | Should -Be 'Get-WindowsCapability:OpenSSH.Server~~~~0.0.1.0'
        $script:callSequence | Should -Contain 'Add-WindowsCapability:OpenSSH.Server~~~~0.0.1.0'
        $script:callSequence | Should -Contain 'Set-Service:sshd:Automatic'
        $script:callSequence | Should -Contain 'Start-Service:sshd'
        $script:callSequence | Should -Contain 'Set-Service:ssh-agent:Automatic'
        $script:callSequence | Should -Contain 'Start-Service:ssh-agent'
        $script:callSequence | Should -Contain 'Get-NetFirewallRule:sshd'
        $script:callSequence | Should -Contain 'Set-NetFirewallRule:sshd:True'
        $script:callSequence | Should -Contain ('New-Item:Directory:{0}' -f (Join-Path $HOME '.ssh'))
        $script:callSequence | Should -Contain ('New-Item:File:{0}' -f (Join-Path (Join-Path $HOME '.ssh') 'authorized_keys'))
        $script:callSequence | Should -Contain 'Get-Content:C:\ProgramData\ssh\sshd_config'
        $script:callSequence | Should -Contain 'Set-Content:C:\ProgramData\ssh\sshd_config'
        $script:callSequence | Should -Contain 'Restart-Service:sshd'
        $script:consoleActions[0] | Should -Be 'Installing OpenSSH Server'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:loggedErrorMessages.Count | Should -Be 0
        $script:configWriteValue | Should -Match '# Match Group administrators'
        $script:configWriteValue | Should -Match '#   AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
    }

    It 'creates the OpenSSH firewall rule when it is absent' {
        $script:sshFirewallRuleExists = $false

        OpenSSHServer

        $script:callSequence | Should -Contain 'New-NetFirewallRule:sshd'
        $script:callSequence | Should -Not -Contain 'Set-NetFirewallRule:sshd:True'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }
}
