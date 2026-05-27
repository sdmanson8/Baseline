Set-StrictMode -Version Latest

BeforeAll {
    $registryHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    . $registryHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AuthHardening.Helpers.ps1'
    . $filePath

    $script:sandboxBase = "HKCU:\Software\Baseline_AuthHardening_Tests_$([guid]::NewGuid().ToString('N'))"
    $script:liveRoot    = Join-Path $script:sandboxBase 'Live'
    $script:backupRoot  = Join-Path $script:sandboxBase 'Backup'
    $env:BASELINE_AUTHHARD_BACKUP_ROOT = $script:backupRoot

    function Reset-AuthSandbox
    {
        if (Test-Path -LiteralPath $script:sandboxBase)
        {
            Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:liveRoot -Force | Out-Null
        New-Item -Path $script:backupRoot -Force | Out-Null
    }

    function New-AuthSetting
    {
        param(
            [string]$Id,
            [string]$Name,
            $Value,
            [string]$Type = 'DWord',
            [bool]$Caution = $false,
            [string]$SubKey = 'Default'
        )
        $path = Join-Path $script:liveRoot $SubKey
        return [pscustomobject]@{
            Id          = $Id
            Path        = $path
            Name        = $Name
            Type        = $Type
            Value       = $Value
            Caution     = $Caution
            Description = "Test setting $Id"
        }
    }

    function Get-LiveValue
    {
        param([pscustomobject]$Setting)
        if (-not (Test-Path -LiteralPath $Setting.Path)) { return $null }
        $item = Get-ItemProperty -LiteralPath $Setting.Path -ErrorAction SilentlyContinue
        if (-not $item -or -not $item.PSObject.Properties[$Setting.Name]) { return $null }
        return $item.PSObject.Properties[$Setting.Name].Value
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:sandboxBase)
    {
        Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath Env:BASELINE_AUTHHARD_BACKUP_ROOT -ErrorAction SilentlyContinue
}

Describe 'Get-BaselineAuthHardeningSettings' {
    It 'returns the canonical catalog of auth-hardening settings' {
        $catalog = Get-BaselineAuthHardeningSettings
        $ids = $catalog | ForEach-Object Id
        $ids | Should -Contain 'Kerberos.SupportedEncryptionTypes'
        $ids | Should -Contain 'NTLM.RestrictSending'
        $ids | Should -Contain 'NTLM.RestrictReceiving'
        $ids | Should -Contain 'LDAP.ClientIntegrity'
        $ids | Should -Contain 'Netlogon.RequireSignOrSeal'
        $ids | Should -Contain 'Netlogon.RequireStrongKey'
        $ids | Should -Contain 'Netlogon.SealSecureChannel'
        $ids | Should -Contain 'Netlogon.SignSecureChannel'
        $ids | Should -Contain 'Winlogon.SCRemoveOption'
        $ids | Should -Contain 'SessionManager.SafeDllSearchMode'
        $ids | Should -Contain 'SessionManager.CWDIllegalInDllSearch'
        $ids | Should -Contain 'PowerShell.LockdownPolicy'
    }

    It 'sets Kerberos SupportedEncryptionTypes to AES-only (0x18)' {
        $entry = Get-BaselineAuthHardeningSettings | Where-Object Id -eq 'Kerberos.SupportedEncryptionTypes'
        $entry.Value | Should -Be 24
        $entry.Type  | Should -Be 'DWord'
    }

    It 'ships NTLM restrict values at audit (1), not deny (2)' {
        $send = Get-BaselineAuthHardeningSettings | Where-Object Id -eq 'NTLM.RestrictSending'
        $recv = Get-BaselineAuthHardeningSettings | Where-Object Id -eq 'NTLM.RestrictReceiving'
        $send.Value | Should -Be 1
        $recv.Value | Should -Be 1
    }

    It 'flags NTLM restrict and PSLockdownPolicy as Caution' {
        $cautioners = Get-BaselineAuthHardeningSettings | Where-Object { $_.Caution } | ForEach-Object Id
        $cautioners | Should -Contain 'NTLM.RestrictSending'
        $cautioners | Should -Contain 'NTLM.RestrictReceiving'
        $cautioners | Should -Contain 'PowerShell.LockdownPolicy'
    }

    It 'sets SCRemoveOption as the REG_SZ string "1"' {
        $entry = Get-BaselineAuthHardeningSettings | Where-Object Id -eq 'Winlogon.SCRemoveOption'
        $entry.Value | Should -Be '1'
        $entry.Type  | Should -Be 'String'
    }

    It 'sets CWDIllegalInDllSearch to 0xFFFFFFFF (encoded as -1 int32)' {
        $entry = Get-BaselineAuthHardeningSettings | Where-Object Id -eq 'SessionManager.CWDIllegalInDllSearch'
        $entry.Value | Should -Be -1
        $entry.Type  | Should -Be 'DWord'
    }

    It 'targets the documented HKLM policy keys' {
        $catalog = Get-BaselineAuthHardeningSettings
        ($catalog | Where-Object Id -eq 'Kerberos.SupportedEncryptionTypes').Path | Should -Be 'HKLM:\System\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
        ($catalog | Where-Object Id -eq 'NTLM.RestrictSending').Path              | Should -Be 'HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0'
        ($catalog | Where-Object Id -eq 'LDAP.ClientIntegrity').Path              | Should -Be 'HKLM:\System\CurrentControlSet\Services\LDAP'
        ($catalog | Where-Object Id -eq 'Netlogon.RequireSignOrSeal').Path        | Should -Be 'HKLM:\System\CurrentControlSet\Services\Netlogon\Parameters'
        ($catalog | Where-Object Id -eq 'Winlogon.SCRemoveOption').Path           | Should -Be 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
        ($catalog | Where-Object Id -eq 'SessionManager.SafeDllSearchMode').Path  | Should -Be 'HKLM:\System\CurrentControlSet\Control\Session Manager'
        ($catalog | Where-Object Id -eq 'PowerShell.LockdownPolicy').Path         | Should -Be 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'
    }
}

Describe 'Get-BaselineAuthHardeningBackupRoot' {
    AfterEach { $env:BASELINE_AUTHHARD_BACKUP_ROOT = $script:backupRoot }

    It 'returns the env override when set' {
        $env:BASELINE_AUTHHARD_BACKUP_ROOT = 'HKCU:\Software\Foo'
        Get-BaselineAuthHardeningBackupRoot | Should -Be 'HKCU:\Software\Foo'
    }

    It 'falls through to HKLM:\Software\Baseline\AuthHardening when no override is set' {
        Remove-Item -LiteralPath Env:BASELINE_AUTHHARD_BACKUP_ROOT -ErrorAction SilentlyContinue
        Get-BaselineAuthHardeningBackupRoot | Should -Be 'HKLM:\Software\Baseline\AuthHardening'
    }
}

Describe 'ConvertTo-BaselineAuthHardeningBackupKey' {
    It 'replaces dotted namespace separators with double underscores' {
        ConvertTo-BaselineAuthHardeningBackupKey -Id 'Kerberos.SupportedEncryptionTypes' | Should -Be 'Kerberos__SupportedEncryptionTypes'
        ConvertTo-BaselineAuthHardeningBackupKey -Id 'Netlogon.RequireSignOrSeal'        | Should -Be 'Netlogon__RequireSignOrSeal'
        ConvertTo-BaselineAuthHardeningBackupKey -Id 'PowerShell.LockdownPolicy'         | Should -Be 'PowerShell__LockdownPolicy'
    }
}

Describe 'Set-BaselineAuthHardeningSettings' {
    BeforeEach { Reset-AuthSandbox }

    It 'writes the desired DWord value to the live key' {
        $setting = New-AuthSetting -Id 'Test.A' -Name 'Foo' -Value 7
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 7
    }

    It 'writes string-typed policies (e.g. SCRemoveOption)' {
        $setting = New-AuthSetting -Id 'Test.SC' -Name 'ScRemoveOption' -Value '1' -Type 'String'
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be '1'
    }

    It 'snapshots the prior value into the dotted-id-safe backup key when one existed' {
        $setting = New-AuthSetting -Id 'Test.B' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 42 -Type DWord -Force

        $result = @(Set-BaselineAuthHardeningSettings -Settings @($setting))
        $result[0].PreviousValue | Should -Be 42
        $result[0].PreviousExists | Should -BeTrue
        $result[0].BackupCreated | Should -BeTrue

        $backupKey = Join-Path $script:backupRoot 'Test__B'
        Test-Path -LiteralPath $backupKey | Should -BeTrue
        $b = Get-ItemProperty -LiteralPath $backupKey
        $b.Value | Should -Be 42
        $b.Existed | Should -Be 1
    }

    It 'records Existed=0 when no prior value was present' {
        $setting = New-AuthSetting -Id 'Test.C' -Name 'Foo' -Value 1
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        $b = Get-ItemProperty -LiteralPath (Join-Path $script:backupRoot 'Test__C')
        $b.Existed | Should -Be 0
    }

    It 'does not overwrite an existing backup on re-run' {
        $setting = New-AuthSetting -Id 'Test.D' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 11 -Type DWord -Force

        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        $result = @(Set-BaselineAuthHardeningSettings -Settings @($setting))
        $result[0].BackupCreated | Should -BeFalse

        $b = Get-ItemProperty -LiteralPath (Join-Path $script:backupRoot 'Test__D')
        $b.Value | Should -Be 11  # genuine original survives a re-apply
    }

    It 'skips Caution-flagged settings unless -IncludeCaution is set' {
        $danger = New-AuthSetting -Id 'Test.Danger' -Name 'Foo' -Value 1 -Caution $true
        $result = @(Set-BaselineAuthHardeningSettings -Settings @($danger))
        $result[0].Skipped | Should -BeTrue
        $result[0].SkipReason | Should -Be 'Caution'
        Get-LiveValue -Setting $danger | Should -BeNullOrEmpty
    }

    It 'applies Caution-flagged settings when -IncludeCaution is supplied' {
        $danger = New-AuthSetting -Id 'Test.Danger' -Name 'Foo' -Value 1 -Caution $true
        $result = @(Set-BaselineAuthHardeningSettings -Settings @($danger) -IncludeCaution)
        $result[0].Skipped | Should -BeFalse
        $result[0].Applied | Should -BeTrue
        Get-LiveValue -Setting $danger | Should -Be 1
    }

    It 'honours -WhatIf without writing or backing up' {
        $setting = New-AuthSetting -Id 'Test.WhatIf' -Name 'Foo' -Value 1
        Set-BaselineAuthHardeningSettings -Settings @($setting) -WhatIf | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'Test__WhatIf') | Should -BeFalse
    }
}

Describe 'Restore-BaselineAuthHardeningSettings' {
    BeforeEach { Reset-AuthSandbox }

    It 'restores a prior value when Existed=1' {
        $setting = New-AuthSetting -Id 'Test.R1' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 88 -Type DWord -Force

        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1

        Restore-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 88
    }

    It 'removes the live value when Existed=0' {
        $setting = New-AuthSetting -Id 'Test.R2' -Name 'Foo' -Value 1
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1

        Restore-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
    }

    It 'removes the backup key after a successful restore' {
        $setting = New-AuthSetting -Id 'Test.R3' -Name 'Foo' -Value 1
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Restore-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'Test__R3') | Should -BeFalse
    }

    It 'reports SkipReason=NoBackup when no backup exists' {
        $setting = New-AuthSetting -Id 'Test.R4' -Name 'Foo' -Value 1
        $result = @(Restore-BaselineAuthHardeningSettings -Settings @($setting))
        $result[0].Restored | Should -BeFalse
        $result[0].Skipped | Should -BeTrue
        $result[0].SkipReason | Should -Be 'NoBackup'
    }
}

Describe 'Get-BaselineAuthHardeningStatus' {
    BeforeEach { Reset-AuthSandbox }

    It 'classifies a live key matching desired as Hardened' {
        $setting = New-AuthSetting -Id 'Test.S1' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 1 -Type DWord -Force

        $status = @(Get-BaselineAuthHardeningStatus -Settings @($setting))
        $status[0].State | Should -Be 'Hardened'
        $status[0].CurrentValue | Should -Be 1
    }

    It 'classifies a live key with a different value as Drift' {
        $setting = New-AuthSetting -Id 'Test.S2' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 99 -Type DWord -Force

        $status = @(Get-BaselineAuthHardeningStatus -Settings @($setting))
        $status[0].State | Should -Be 'Drift'
        $status[0].CurrentValue | Should -Be 99
    }

    It 'classifies a missing live value as NotSet' {
        $setting = New-AuthSetting -Id 'Test.S3' -Name 'Foo' -Value 1
        $status = @(Get-BaselineAuthHardeningStatus -Settings @($setting))
        $status[0].State | Should -Be 'NotSet'
    }

    It 'reports the Caution flag through to status output' {
        $setting = New-AuthSetting -Id 'Test.S4' -Name 'Foo' -Value 1 -Caution $true
        $status = @(Get-BaselineAuthHardeningStatus -Settings @($setting))
        $status[0].Caution | Should -BeTrue
    }

    It 'reports BackupPresent after an apply' {
        $setting = New-AuthSetting -Id 'Test.S5' -Name 'Foo' -Value 1
        Set-BaselineAuthHardeningSettings -Settings @($setting) | Out-Null
        $status = @(Get-BaselineAuthHardeningStatus -Settings @($setting))
        $status[0].BackupPresent | Should -BeTrue
    }
}
