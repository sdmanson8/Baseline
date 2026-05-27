Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/OSHardening/ProtectionHardening.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('AuthHardeningRegistry','AuthHardeningCautionRegistry')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:auditSafeIds = @(
        'Kerberos.SupportedEncryptionTypes',
        'LDAP.ClientIntegrity',
        'Netlogon.RequireSignOrSeal',
        'Netlogon.RequireStrongKey',
        'Netlogon.SealSecureChannel',
        'Netlogon.SignSecureChannel',
        'Winlogon.SCRemoveOption',
        'SessionManager.SafeDllSearchMode',
        'SessionManager.CWDIllegalInDllSearch'
    )
    $script:cautionIds = @(
        'NTLM.RestrictSending',
        'NTLM.RestrictReceiving',
        'PowerShell.LockdownPolicy'
    )

    function New-FakeCatalog {
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($id in $script:auditSafeIds) {
            $records.Add([pscustomobject]@{ Id=$id; Caution=$false }) | Out-Null
        }
        foreach ($id in $script:cautionIds) {
            $records.Add([pscustomobject]@{ Id=$id; Caution=$true }) | Out-Null
        }
        return $records.ToArray()
    }
}

Describe 'AuthHardeningRegistry -Enable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setSettingsArg  = $null
        $script:setIncludeArg   = $false
        $script:setRecords      = @()
        $script:throwOnSet      = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineAuthHardeningSettings { return New-FakeCatalog }
        function Set-BaselineAuthHardeningSettings {
            param($Settings, $BackupRoot, [switch]$IncludeCaution)
            $script:setSettingsArg = $Settings
            $script:setIncludeArg  = [bool]$IncludeCaution
            if ($script:throwOnSet) { throw 'auth apply failed' }
            return $script:setRecords
        }
        function Restore-BaselineAuthHardeningSettings { param($Settings, $BackupRoot) return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineAuthHardeningSettings','Set-BaselineAuthHardeningSettings','Restore-BaselineAuthHardeningSettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'passes only the non-caution subset to the helper' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='Kerberos.SupportedEncryptionTypes'; Applied=$true }
        )
        AuthHardeningRegistry -Enable
        $passedIds = @($script:setSettingsArg | ForEach-Object { $_.Id })
        $passedIds.Count | Should -Be $script:auditSafeIds.Count
        foreach ($id in $script:auditSafeIds) { $passedIds | Should -Contain $id }
        foreach ($id in $script:cautionIds)   { $passedIds | Should -Not -Contain $id }
        $script:setIncludeArg | Should -Be $false
    }

    It 'logs apply summary tallying applied / skipped' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='Kerberos.SupportedEncryptionTypes'; Applied=$true  }
            [pscustomobject]@{ Id='LDAP.ClientIntegrity';              Applied=$true  }
            [pscustomobject]@{ Id='Netlogon.RequireSignOrSeal';        Applied=$false }
        )
        AuthHardeningRegistry -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Auth hardening summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'applied=2'
        $summary | Should -Match 'skipped=1'
    }

    It 'reports failed when helper throws' {
        $script:throwOnSet = $true
        AuthHardeningRegistry -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'auth apply failed'
    }
}

Describe 'AuthHardeningRegistry -Disable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:restoreSettingsArg = $null
        $script:restoreRecords     = @()
        $script:throwOnRestore     = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineAuthHardeningSettings { return New-FakeCatalog }
        function Set-BaselineAuthHardeningSettings { param($Settings, $BackupRoot, [switch]$IncludeCaution) return @() }
        function Restore-BaselineAuthHardeningSettings {
            param($Settings, $BackupRoot)
            $script:restoreSettingsArg = $Settings
            if ($script:throwOnRestore) { throw 'auth restore failed' }
            return $script:restoreRecords
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineAuthHardeningSettings','Set-BaselineAuthHardeningSettings','Restore-BaselineAuthHardeningSettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'restores only the non-caution subset' {
        AuthHardeningRegistry -Disable
        $passedIds = @($script:restoreSettingsArg | ForEach-Object { $_.Id })
        foreach ($id in $script:auditSafeIds) { $passedIds | Should -Contain $id }
        foreach ($id in $script:cautionIds)   { $passedIds | Should -Not -Contain $id }
    }

    It 'logs reversal summary + SkipReason for each skipped entry' {
        $script:restoreRecords = @(
            [pscustomobject]@{ Id='Kerberos.SupportedEncryptionTypes'; Restored=$true;  Skipped=$false; SkipReason=$null }
            [pscustomobject]@{ Id='LDAP.ClientIntegrity';              Restored=$false; Skipped=$true;  SkipReason='NoBackup' }
        )
        AuthHardeningRegistry -Disable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Auth hardening reversal summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'restored=1'
        $summary | Should -Match 'skipped=1'
        ($script:logInfoMessages | Where-Object { $_ -match 'Skipped LDAP.ClientIntegrity.*NoBackup' }) | Should -Not -BeNullOrEmpty
    }

    It 'reports failed when restore throws' {
        $script:throwOnRestore = $true
        AuthHardeningRegistry -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'auth restore failed'
    }
}

Describe 'AuthHardeningCautionRegistry -Enable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:setSettingsArg  = $null
        $script:setIncludeArg   = $false
        $script:setRecords      = @()
        $script:throwOnSet      = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineAuthHardeningSettings { return New-FakeCatalog }
        function Set-BaselineAuthHardeningSettings {
            param($Settings, $BackupRoot, [switch]$IncludeCaution)
            $script:setSettingsArg = $Settings
            $script:setIncludeArg  = [bool]$IncludeCaution
            if ($script:throwOnSet) { throw 'auth caution apply failed' }
            return $script:setRecords
        }
        function Restore-BaselineAuthHardeningSettings { param($Settings, $BackupRoot) return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineAuthHardeningSettings','Set-BaselineAuthHardeningSettings','Restore-BaselineAuthHardeningSettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'passes only the caution subset and -IncludeCaution to the helper' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='NTLM.RestrictSending';   Applied=$true }
            [pscustomobject]@{ Id='NTLM.RestrictReceiving'; Applied=$true }
            [pscustomobject]@{ Id='PowerShell.LockdownPolicy'; Applied=$true }
        )
        AuthHardeningCautionRegistry -Enable
        $passedIds = @($script:setSettingsArg | ForEach-Object { $_.Id })
        $passedIds.Count | Should -Be $script:cautionIds.Count
        foreach ($id in $script:cautionIds)   { $passedIds | Should -Contain $id }
        foreach ($id in $script:auditSafeIds) { $passedIds | Should -Not -Contain $id }
        $script:setIncludeArg | Should -Be $true
    }

    It 'logs caution apply summary' {
        $script:setRecords = @(
            [pscustomobject]@{ Id='NTLM.RestrictSending';      Applied=$true  }
            [pscustomobject]@{ Id='NTLM.RestrictReceiving';    Applied=$true  }
            [pscustomobject]@{ Id='PowerShell.LockdownPolicy'; Applied=$false }
        )
        AuthHardeningCautionRegistry -Enable
        $summary = $script:logInfoMessages | Where-Object { $_ -match 'Auth hardening \(caution\) summary' }
        $summary | Should -Not -BeNullOrEmpty
        $summary | Should -Match 'applied=2'
        $summary | Should -Match 'skipped=1'
    }

    It 'reports failed when helper throws' {
        $script:throwOnSet = $true
        AuthHardeningCautionRegistry -Enable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'auth caution apply failed'
    }
}

Describe 'AuthHardeningCautionRegistry -Disable' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages   = [System.Collections.Generic.List[string]]::new()
        $script:logInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:restoreSettingsArg = $null
        $script:restoreRecords     = @()
        $script:throwOnRestore     = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo  { param([string]$Message) [void]$script:logInfoMessages.Add($Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }

        function Get-BaselineAuthHardeningSettings { return New-FakeCatalog }
        function Set-BaselineAuthHardeningSettings { param($Settings, $BackupRoot, [switch]$IncludeCaution) return @() }
        function Restore-BaselineAuthHardeningSettings {
            param($Settings, $BackupRoot)
            $script:restoreSettingsArg = $Settings
            if ($script:throwOnRestore) { throw 'auth caution restore failed' }
            return $script:restoreRecords
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineAuthHardeningSettings','Set-BaselineAuthHardeningSettings','Restore-BaselineAuthHardeningSettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'restores only the caution subset' {
        AuthHardeningCautionRegistry -Disable
        $passedIds = @($script:restoreSettingsArg | ForEach-Object { $_.Id })
        foreach ($id in $script:cautionIds)   { $passedIds | Should -Contain $id }
        foreach ($id in $script:auditSafeIds) { $passedIds | Should -Not -Contain $id }
    }

    It 'reports failed when restore throws' {
        $script:throwOnRestore = $true
        AuthHardeningCautionRegistry -Disable
        $script:consoleStatuses[-1] | Should -Be 'failed'
        $script:errorMessages[0] | Should -Match 'auth caution restore failed'
    }
}

Describe 'Auth hardening handler parameter contract' {
    BeforeEach {
        function Write-ConsoleStatus { param($Action, $Status) }
        function LogInfo  { param($Message) }
        function LogError { param($Message) }
        function Get-BaselineAuthHardeningSettings { return New-FakeCatalog }
        function Set-BaselineAuthHardeningSettings { param($Settings, $BackupRoot, [switch]$IncludeCaution) return @() }
        function Restore-BaselineAuthHardeningSettings { param($Settings, $BackupRoot) return @() }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Get-BaselineAuthHardeningSettings','Set-BaselineAuthHardeningSettings','Restore-BaselineAuthHardeningSettings')) {
            Microsoft.PowerShell.Management\Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'AuthHardeningRegistry requires Enable or Disable' {
        { AuthHardeningRegistry } | Should -Throw
    }

    It 'AuthHardeningRegistry rejects both switches together' {
        { AuthHardeningRegistry -Enable -Disable } | Should -Throw
    }

    It 'AuthHardeningCautionRegistry requires Enable or Disable' {
        { AuthHardeningCautionRegistry } | Should -Throw
    }

    It 'AuthHardeningCautionRegistry rejects both switches together' {
        { AuthHardeningCautionRegistry -Enable -Disable } | Should -Throw
    }
}
