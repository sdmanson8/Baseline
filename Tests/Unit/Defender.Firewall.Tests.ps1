Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/Defender/Defender.Firewall.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Firewall' {
    BeforeEach {
        $script:consoleActions    = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses   = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages      = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages   = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages     = [System.Collections.Generic.List[string]]::new()
        $script:removeRegCalls    = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls      = [System.Collections.Generic.List[string]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:testPathReturnValue = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name })
        }
        function Test-Path {
            param([string]$Path)
            return $script:testPathReturnValue
        }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
        function Set-ItemProperty {
            param([string]$Path, [string]$LiteralPath, [string]$Name, [string]$Type, [object]$Value, [object]$ErrorAction)
            [void]$script:setItemPropertyCalls.Add([pscustomobject]@{ Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }); Name = $Name; Type = $Type; Value = $Value })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-RegistryValueSafe -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'requires either Enable or Disable (parameter set validation)' {
        { Firewall } | Should -Throw
    }

    It 'removes the EnableFirewall policy when enabling' {
        Firewall -Enable

        $script:consoleActions[0] | Should -Be 'Enabling Windows Firewall'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:removeRegCalls.Count | Should -Be 1
        $script:removeRegCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'
        $script:removeRegCalls[0].Name | Should -Be 'EnableFirewall'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'writes the policy value when disabling and the policy key already exists' {
        $script:testPathReturnValue = $true

        Firewall -Disable

        $script:consoleActions[0] | Should -Be 'Disabling Windows Firewall'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:newItemCalls.Count | Should -Be 0
        $script:setItemPropertyCalls.Count | Should -Be 1
        $script:setItemPropertyCalls[0].Name | Should -Be 'EnableFirewall'
        $script:setItemPropertyCalls[0].Value | Should -Be 0
        $script:setItemPropertyCalls[0].Type | Should -Be 'DWord'
    }

    It 'creates the policy key when disabling on a system that lacks it' {
        $script:testPathReturnValue = $false

        Firewall -Disable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'
        $script:setItemPropertyCalls.Count | Should -Be 1
    }

    It 'reports failure when enabling throws' {
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name)
            throw 'simulated failure'
        }

        Firewall -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated failure'
    }
}

Describe 'WindowsFirewallLogging' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:netshCalls = [System.Collections.Generic.List[string]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function netsh {
            [void]$script:netshCalls.Add($args -join ' ')
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\netsh -ErrorAction SilentlyContinue
    }

    It 'configures per-profile logging with dropped+allowed connection capture' {
        WindowsFirewallLogging

        $script:consoleActions[0] | Should -Be 'Configuring Windows Firewall logging'
        $script:consoleStatuses[-1] | Should -Be 'success'
        # 4 commands per profile (filename / maxfilesize / dropped / allowed) * 3 profiles = 12
        $script:netshCalls.Count | Should -Be 12
        $joined = $script:netshCalls -join "`n"
        $joined | Should -Match 'domainprofile logging filename .*pfirewall_domain\.log'
        $joined | Should -Match 'privateprofile logging filename .*pfirewall_private\.log'
        $joined | Should -Match 'publicprofile logging filename .*pfirewall_public\.log'
        $joined | Should -Match 'domainprofile logging maxfilesize 16384'
        $joined | Should -Match 'privateprofile logging maxfilesize 16384'
        $joined | Should -Match 'publicprofile logging maxfilesize 16384'
        $joined | Should -Match 'domainprofile logging droppedconnections enable'
        $joined | Should -Match 'privateprofile logging droppedconnections enable'
        $joined | Should -Match 'publicprofile logging droppedconnections enable'
        $joined | Should -Match 'domainprofile logging allowedconnections enable'
        $joined | Should -Match 'privateprofile logging allowedconnections enable'
        $joined | Should -Match 'publicprofile logging allowedconnections enable'
        $script:errorMessages.Count | Should -Be 0
    }
}

Describe 'LOLBinFirewallRules' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newRuleCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRuleCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function New-NetFirewallRule {
            param(
                [string]$DisplayName, [string]$Group, [string]$Direction, [string]$Action,
                [string]$Program, [string]$Protocol, [string]$Profile, [string]$Enabled,
                [object]$ErrorAction
            )
            [void]$script:newRuleCalls.Add([pscustomobject]@{
                DisplayName = $DisplayName; Group = $Group; Direction = $Direction;
                Action = $Action; Program = $Program; Protocol = $Protocol;
                Profile = $Profile; Enabled = $Enabled
            })
        }
        function Remove-NetFirewallRule {
            param([string]$Group, [object]$ErrorAction)
            [void]$script:removeRuleCalls.Add([pscustomobject]@{ Group = $Group })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\New-NetFirewallRule -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }

    It 'requires either Enable or Disable (parameter set validation)' {
        { LOLBinFirewallRules -Enable -Disable } | Should -Throw
    }

    It 'adds outbound block rules tagged with the Baseline-LOLBin-Block group when enabling' {
        LOLBinFirewallRules -Enable

        $script:newRuleCalls.Count | Should -BeGreaterThan 30
        ($script:newRuleCalls.Group | Select-Object -Unique) | Should -Be 'Baseline-LOLBin-Block'
        ($script:newRuleCalls.Direction | Select-Object -Unique) | Should -Be 'Outbound'
        ($script:newRuleCalls.Action | Select-Object -Unique) | Should -Be 'Block'
        ($script:newRuleCalls.Protocol | Select-Object -Unique) | Should -Be 'TCP'
        ($script:newRuleCalls.Profile | Select-Object -Unique) | Should -Be 'Any'
        ($script:newRuleCalls.DisplayName -join "`n") | Should -Match 'Baseline-LOLBin-Block: certutil\.exe'
        ($script:newRuleCalls.DisplayName -join "`n") | Should -Match 'Baseline-LOLBin-Block: mshta\.exe'
        ($script:newRuleCalls.DisplayName -join "`n") | Should -Match 'Baseline-LOLBin-Block: regsvr32\.exe'
        $script:removeRuleCalls.Count | Should -Be 0
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'removes the entire rule group in one Remove-NetFirewallRule call when disabling' {
        LOLBinFirewallRules -Disable

        $script:removeRuleCalls.Count | Should -Be 1
        $script:removeRuleCalls[0].Group | Should -Be 'Baseline-LOLBin-Block'
        $script:newRuleCalls.Count | Should -Be 0
        $script:consoleActions[0] | Should -Be 'Removing LOLBin firewall rules'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:errorMessages.Count | Should -Be 0
    }

    It 'reports failure when the firewall apply throws' {
        function New-NetFirewallRule {
            param(
                [string]$DisplayName, [string]$Group, [string]$Direction, [string]$Action,
                [string]$Program, [string]$Protocol, [string]$Profile, [string]$Enabled,
                [object]$ErrorAction
            )
            throw 'simulated firewall failure'
        }

        LOLBinFirewallRules -Enable

        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'simulated firewall failure'
    }
}

Describe 'NetworkProtection' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        $script:warningMessages = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:mpCalls = [System.Collections.Generic.List[object]]::new()
        $script:defenderExecutionAvailable = $true

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) [void]$script:infoMessages.Add($Message) }
        function LogWarning { param([string]$Message) [void]$script:warningMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-MpPreference {
            param([string]$EnableNetworkProtection, [object]$ErrorAction)
            [void]$script:mpCalls.Add($EnableNetworkProtection)
        }
        function Get-TweakSkipLabel { param($Invocation) return 'NetworkProtection' }
        function Test-BaselineDefenderExecutionAvailable { return [bool]$script:defenderExecutionAvailable }
        function Get-BaselineDefenderExecutionUnavailableReason { return 'Set-MpPreference is not available.' }
        $Script:Localization = [pscustomobject]@{ Skipped = 'Skipped: {0}' }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-MpPreference -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-TweakSkipLabel -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-BaselineDefenderExecutionAvailable -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BaselineDefenderExecutionUnavailableReason -ErrorAction SilentlyContinue
    }

    It 'enables network protection via Set-MpPreference' {
        NetworkProtection -Enable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0] | Should -Be 'Enabled'
        $script:consoleActions[0] | Should -Match 'Enabling Microsoft Defender Exploit Guard network protection'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'disables network protection via Set-MpPreference' {
        NetworkProtection -Disable

        $script:mpCalls.Count | Should -Be 1
        $script:mpCalls[0] | Should -Be 'Disabled'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'skips entirely when Defender command surface is unavailable' {
        $script:defenderExecutionAvailable = $false

        NetworkProtection -Enable

        $script:mpCalls.Count | Should -Be 0
        $script:warningMessages.Count | Should -Be 1
        $script:warningMessages[0] | Should -Match 'Set-MpPreference is not available'
    }
}
