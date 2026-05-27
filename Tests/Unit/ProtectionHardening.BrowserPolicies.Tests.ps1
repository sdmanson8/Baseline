Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -eq 'BrowserEnterprisePolicies') {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'BrowserEnterprisePolicies -Enable' {
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

        function Set-BaselineBrowserPolicySettings {
            $script:setCalls++
            if ($script:throwOnSet) { throw 'browser apply failed' }
            return $script:setRecords
        }
        function Restore-BaselineBrowserPolicySettings { return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineBrowserPolicySettings','Restore-BaselineBrowserPolicySettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'invokes the bulk apply primitive once' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='Edge:SmartScreenEnabled';      Browser='Edge';    Applied=$true }
            [pscustomobject]@{ Id='Chrome:DnsOverHttpsMode';      Browser='Chrome';  Applied=$true }
            [pscustomobject]@{ Id='Firefox:DisableTelemetry';     Browser='Firefox'; Applied=$true }
            [pscustomobject]@{ Id='Brave:BraveWalletDisabled';    Browser='Brave';   Applied=$true }
        )
        BrowserEnterprisePolicies -Enable
        $script:setCalls | Should -Be 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'logs an apply summary tallying applied / skipped + per-browser counts' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='Edge:SmartScreenEnabled';        Browser='Edge';   Applied=$true  }
            [pscustomobject]@{ Id='Edge:SitePerProcess';            Browser='Edge';   Applied=$true  }
            [pscustomobject]@{ Id='Edge:SSLVersionMin';             Browser='Edge';   Applied=$false }
            [pscustomobject]@{ Id='Chrome:BlockThirdPartyCookies';  Browser='Chrome'; Applied=$true  }
            [pscustomobject]@{ Id='Firefox:DisableTelemetry';       Browser='Firefox'; Applied=$true }
            [pscustomobject]@{ Id='Brave:BraveWalletDisabled';      Browser='Brave'; Applied=$true }
        )
        BrowserEnterprisePolicies -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Browser policies summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'settings=6'
        $summary | Should -Match 'applied=5'
        $summary | Should -Match 'skipped=1'
        $summary | Should -Match 'edge=3'
        $summary | Should -Match 'chrome=1'
        $summary | Should -Match 'firefox=1'
        $summary | Should -Match 'brave=1'
    }

    It 'reports failed and logs error when the apply helper throws' {
        $script:throwOnSet = $true
        BrowserEnterprisePolicies -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages.Count | Should -Be 1
        $script:errorMessages[0] | Should -Match 'browser apply failed'
    }
}

Describe 'BrowserEnterprisePolicies -Disable' {
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

        function Set-BaselineBrowserPolicySettings { return @() }
        function Restore-BaselineBrowserPolicySettings {
            if ($script:throwOnRestore) { throw 'browser restore failed' }
            return $script:restoreRecords
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineBrowserPolicySettings','Restore-BaselineBrowserPolicySettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'logs reversal summary tallying restored / skipped + SkipReason for each skipped entry' {
        $script:restoreRecords = @(
            [pscustomobject]@{ Id='Edge:SmartScreenEnabled';       Restored=$true;  Skipped=$false; SkipReason=$null }
            [pscustomobject]@{ Id='Chrome:BlockThirdPartyCookies'; Restored=$false; Skipped=$true;  SkipReason='NoBackup' }
        )
        BrowserEnterprisePolicies -Disable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Browser policies reversal summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'restored=1'
        $summary | Should -Match 'skipped=1'
        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped Chrome:BlockThirdPartyCookies.*NoBackup' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports failed when restore throws' {
        $script:throwOnRestore = $true
        BrowserEnterprisePolicies -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'browser restore failed'
    }
}

Describe 'BrowserEnterprisePolicies parameter contract' {
    BeforeEach {
        function Write-ConsoleStatus { param($Action, $Status) }
        function LogInfo  { param($Message) }
        function LogError { param($Message) }
        function Set-BaselineBrowserPolicySettings { return @() }
        function Restore-BaselineBrowserPolicySettings { return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-BaselineBrowserPolicySettings','Restore-BaselineBrowserPolicySettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires Enable or Disable' {
        { BrowserEnterprisePolicies } | Should -Throw
    }

    It 'rejects both switches together' {
        { BrowserEnterprisePolicies -Enable -Disable } | Should -Throw
    }
}
