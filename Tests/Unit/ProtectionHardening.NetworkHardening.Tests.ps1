Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('NetworkHardeningRegistry','NetbiosOverTcpip','WinRMService')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'NetworkHardeningRegistry -Enable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setCalls        = 0
        $script:setRecords      = @()
        $script:throwOnSet      = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Set-BaselineNetworkHardeningRegistrySettings {
            $script:setCalls++
            if ($script:throwOnSet) { throw 'apply failed' }
            return $script:setRecords
        }
        function Restore-BaselineNetworkHardeningRegistrySettings { return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineNetworkHardeningRegistrySettings','Restore-BaselineNetworkHardeningRegistrySettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'invokes the bulk apply primitive once' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='IGMPLevel'; Applied=$true }
            [pscustomobject]@{ Id='LlmnrDisable'; Applied=$true }
        )
        NetworkHardeningRegistry -Enable
        $script:setCalls | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs an apply summary tallying applied / skipped' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='IGMPLevel';     Applied=$true }
            [pscustomobject]@{ Id='LlmnrDisable';  Applied=$true }
            [pscustomobject]@{ Id='RpcEpMapAuth';  Applied=$false }
        )
        NetworkHardeningRegistry -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Network hardening summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'applied=2'
        $summary | Should -Match 'skipped=1'
    }

    It 'reports failed and logs error when the helper throws' {
        $script:throwOnSet = $true
        NetworkHardeningRegistry -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'apply failed'
    }
}

Describe 'NetworkHardeningRegistry -Disable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:restoreRecords  = @()
        $script:throwOnRestore  = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Set-BaselineNetworkHardeningRegistrySettings { return @() }
        function Restore-BaselineNetworkHardeningRegistrySettings {
            if ($script:throwOnRestore) { throw 'restore failed' }
            return $script:restoreRecords
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineNetworkHardeningRegistrySettings','Restore-BaselineNetworkHardeningRegistrySettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'logs a reversal summary tallying restored / skipped + SkipReason for each skipped entry' {
        $script:restoreRecords = @(
            [pscustomobject]@{ Id='IGMPLevel';    Restored=$true;  Skipped=$false; SkipReason=$null }
            [pscustomobject]@{ Id='LlmnrDisable'; Restored=$false; Skipped=$true;  SkipReason='NoBackup' }
        )
        NetworkHardeningRegistry -Disable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Network hardening reversal summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'restored=1'
        $summary | Should -Match 'skipped=1'
        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped LlmnrDisable.*NoBackup' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports failed when restore throws' {
        $script:throwOnRestore = $true
        NetworkHardeningRegistry -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'restore failed'
    }
}

Describe 'NetbiosOverTcpip' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:disableRecords  = @()
        $script:restoreRecords  = @()
        $script:throwOnDisable  = $false
        $script:throwOnRestore  = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Disable-BaselineNetBiosOverTcpip {
            if ($script:throwOnDisable) { throw 'netbt disable failed' }
            return $script:disableRecords
        }
        function Restore-BaselineNetBiosOverTcpip {
            if ($script:throwOnRestore) { throw 'netbt restore failed' }
            return $script:restoreRecords
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Disable-BaselineNetBiosOverTcpip','Restore-BaselineNetBiosOverTcpip')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'logs adapter / applied / skipped tally on Enable' {
        $script:disableRecords = @(
            [pscustomobject]@{ AdapterId='Tcpip_{abc}'; Applied=$true }
            [pscustomobject]@{ AdapterId='Tcpip_{def}'; Applied=$true }
            [pscustomobject]@{ AdapterId='Tcpip_{ghi}'; Applied=$false }
        )
        NetbiosOverTcpip -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'NetBIOS over TCP/IP summary' }
        $summary | Should -Match 'adapters=3'
        $summary | Should -Match 'applied=2'
        $summary | Should -Match 'skipped=1'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs adapter / restored tally on Disable' {
        $script:restoreRecords = @(
            [pscustomobject]@{ AdapterId='Tcpip_{abc}'; Restored=$true }
            [pscustomobject]@{ AdapterId='Tcpip_{def}'; Restored=$true }
        )
        NetbiosOverTcpip -Disable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'NetBIOS over TCP/IP reversal summary' }
        $summary | Should -Match 'adapters=2'
        $summary | Should -Match 'restored=2'
    }

    It 'reports failed on Enable when helper throws' {
        $script:throwOnDisable = $true
        NetbiosOverTcpip -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'netbt disable failed'
    }

    It 'reports failed on Disable when helper throws' {
        $script:throwOnRestore = $true
        NetbiosOverTcpip -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'netbt restore failed'
    }
}

Describe 'WinRMService' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:disableResult   = $null
        $script:restoreResult   = $null
        $script:throwOnDisable  = $false
        $script:throwOnRestore  = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Disable-BaselineWinRMService {
            if ($script:throwOnDisable) { throw 'winrm disable failed' }
            return $script:disableResult
        }
        function Restore-BaselineWinRMService {
            if ($script:throwOnRestore) { throw 'winrm restore failed' }
            return $script:restoreResult
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Disable-BaselineWinRMService','Restore-BaselineWinRMService')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'logs the per-service summary on Enable when service was found' {
        $script:disableResult = [pscustomobject]@{
            Found=$true; Skipped=$false; SkipReason=$null
            Stopped=$true; Disabled=$true
            PriorStartType='Manual'; PriorStatus='Running'
        }
        WinRMService -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'WinRM service summary' }
        $summary | Should -Match 'stopped=True'
        $summary | Should -Match 'disabled=True'
        $summary | Should -Match 'priorStartType=Manual'
        $summary | Should -Match 'priorStatus=Running'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs a skipped reason on Enable when WinRM is not installed' {
        $script:disableResult = [pscustomobject]@{
            Found=$false; Skipped=$true; SkipReason='NotInstalled'
            Stopped=$false; Disabled=$false
        }
        WinRMService -Enable
        ($script:logInfoMessages | Where-Object { $_ -match 'WinRM service skipped: NotInstalled' }) | Should -Not -BeNullOrEmpty
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs the reversal summary on Disable when a backup existed' {
        $script:restoreResult = [pscustomobject]@{
            Restored=$true; Skipped=$false; SkipReason=$null
            PriorStartType='Manual'; PriorStatus='Running'
            StartTypeRestored=$true; Started=$true
        }
        WinRMService -Disable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'WinRM service reversal summary' }
        $summary | Should -Match 'startTypeRestored=True'
        $summary | Should -Match 'started=True'
        $summary | Should -Match 'priorStartType=Manual'
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs a skipped reason on Disable when no backup exists' {
        $script:restoreResult = [pscustomobject]@{
            Restored=$false; Skipped=$true; SkipReason='NoBackup'
        }
        WinRMService -Disable
        ($script:logInfoMessages | Where-Object { $_ -match 'WinRM service restore skipped: NoBackup' }) | Should -Not -BeNullOrEmpty
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when the disable helper throws' {
        $script:throwOnDisable = $true
        WinRMService -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'winrm disable failed'
    }

    It 'reports failed when the restore helper throws' {
        $script:throwOnRestore = $true
        WinRMService -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'winrm restore failed'
    }
}

Describe 'Networking handler parameter contract' {
    BeforeEach {
        function Write-ConsoleStatus { param($Action, $Status) }
        function LogInfo  { param($Message) }
        function LogError { param($Message) }
        function Set-BaselineNetworkHardeningRegistrySettings { return @() }
        function Restore-BaselineNetworkHardeningRegistrySettings { return @() }
        function Disable-BaselineNetBiosOverTcpip { return @() }
        function Restore-BaselineNetBiosOverTcpip { return @() }
        function Disable-BaselineWinRMService { return [pscustomobject]@{ Found=$false; Skipped=$true; SkipReason='NotInstalled'; Stopped=$false; Disabled=$false } }
        function Restore-BaselineWinRMService { return [pscustomobject]@{ Restored=$false; Skipped=$true; SkipReason='NoBackup' } }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineNetworkHardeningRegistrySettings','Restore-BaselineNetworkHardeningRegistrySettings','Disable-BaselineNetBiosOverTcpip','Restore-BaselineNetBiosOverTcpip','Disable-BaselineWinRMService','Restore-BaselineWinRMService')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'NetworkHardeningRegistry requires Enable or Disable' {
        { NetworkHardeningRegistry } | Should -Throw
    }

    It 'NetworkHardeningRegistry rejects both switches together' {
        { NetworkHardeningRegistry -Enable -Disable } | Should -Throw
    }

    It 'NetbiosOverTcpip requires Enable or Disable' {
        { NetbiosOverTcpip } | Should -Throw
    }

    It 'NetbiosOverTcpip rejects both switches together' {
        { NetbiosOverTcpip -Enable -Disable } | Should -Throw
    }

    It 'WinRMService requires Enable or Disable' {
        { WinRMService } | Should -Throw
    }

    It 'WinRMService rejects both switches together' {
        { WinRMService -Enable -Disable } | Should -Throw
    }
}
