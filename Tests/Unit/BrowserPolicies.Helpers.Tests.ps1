Set-StrictMode -Version Latest

BeforeAll {
    $registryHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    . $registryHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/BrowserPolicies.Helpers.ps1'
    . $filePath

    $script:sandboxBase = "HKCU:\Software\Baseline_BrowserPolicies_Tests_$([guid]::NewGuid().ToString('N'))"
    $script:liveRoot    = Join-Path $script:sandboxBase 'Live'
    $script:backupRoot  = Join-Path $script:sandboxBase 'Backup'
    $env:BASELINE_BROWSER_POLICY_BACKUP_ROOT = $script:backupRoot

    function Reset-BrowserSandbox
    {
        if (Test-Path -LiteralPath $script:sandboxBase)
        {
            Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:liveRoot -Force | Out-Null
        New-Item -Path $script:backupRoot -Force | Out-Null
    }

    function New-BrowserSetting
    {
        param(
            [string]$Id,
            [string]$Browser,
            [string]$Name,
            $Value,
            [string]$Type = 'DWord'
        )
        $path = Join-Path $script:liveRoot $Browser
        return [pscustomobject]@{
            Id          = $Id
            Browser     = $Browser
            Path        = $path
            Name        = $Name
            Type        = $Type
            Value       = $Value
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
    Remove-Item -LiteralPath Env:BASELINE_BROWSER_POLICY_BACKUP_ROOT -ErrorAction SilentlyContinue
}

Describe 'Get-BaselineBrowserPolicySettings' {
    It 'returns the canonical browser catalog by default' {
        $catalog = Get-BaselineBrowserPolicySettings
        $ids = $catalog | ForEach-Object Id
        $ids | Should -Contain 'Edge:SmartScreenEnabled'
        $ids | Should -Contain 'Edge:SitePerProcess'
        $ids | Should -Contain 'Edge:SSLVersionMin'
        $ids | Should -Contain 'Edge:PasswordManagerEnabled'
        $ids | Should -Contain 'Edge:AutofillCreditCardEnabled'
        $ids | Should -Contain 'Chrome:BlockThirdPartyCookies'
        $ids | Should -Contain 'Chrome:DnsOverHttpsMode'
        $ids | Should -Contain 'Chrome:SafeBrowsingProtectionLevel'
        $ids | Should -Contain 'Chrome:PasswordManagerEnabled'
        $ids | Should -Contain 'Chrome:AutofillCreditCardEnabled'
        $ids | Should -Contain 'Chrome:AutofillAddressEnabled'
        $ids | Should -Contain 'Firefox:DisableTelemetry'
        $ids | Should -Contain 'Firefox:DisableFirefoxStudies'
        $ids | Should -Contain 'Firefox:DisableDefaultBrowserAgent'
        $ids | Should -Contain 'Firefox:SSLVersionMin'
        $ids | Should -Contain 'Firefox:PasswordManagerEnabled'
        $ids | Should -Contain 'Firefox:OfferToSaveLogins'
        $ids | Should -Contain 'Firefox:OfferToSaveLoginsDefault'
        $ids | Should -Contain 'Firefox:AutofillCreditCardEnabled'
        $ids | Should -Contain 'Firefox:AutofillAddressEnabled'
        $ids | Should -Contain 'Brave:BlockThirdPartyCookies'
        $ids | Should -Contain 'Brave:DnsOverHttpsMode'
        $ids | Should -Contain 'Brave:SafeBrowsingProtectionLevel'
        $ids | Should -Contain 'Brave:PasswordManagerEnabled'
        $ids | Should -Contain 'Brave:AutofillCreditCardEnabled'
        $ids | Should -Contain 'Brave:AutofillAddressEnabled'
        $ids | Should -Contain 'Brave:BraveRewardsDisabled'
        $ids | Should -Contain 'Brave:BraveWalletDisabled'
        $ids | Should -Contain 'Brave:BraveP3AEnabled'
        $ids | Should -Contain 'Brave:BraveStatsPingEnabled'
        $ids | Should -Contain 'Brave:BraveWebDiscoveryEnabled'
        $ids | Should -Contain 'Brave:BraveAIChatEnabled'
    }

    It 'sets SSLVersionMin to tls1.2' {
        $entry = (Get-BaselineBrowserPolicySettings -Browser Edge) | Where-Object Id -eq 'Edge:SSLVersionMin'
        $entry.Value | Should -Be 'tls1.2'
        $entry.Type  | Should -Be 'String'
    }

    It 'sets DnsOverHttpsMode to automatic' {
        $entry = (Get-BaselineBrowserPolicySettings -Browser Chrome) | Where-Object Id -eq 'Chrome:DnsOverHttpsMode'
        $entry.Value | Should -Be 'automatic'
        $entry.Type  | Should -Be 'String'
    }

    It 'sets Firefox SSLVersionMin to tls1.2 through the GPO policy key' {
        $entry = (Get-BaselineBrowserPolicySettings -Browser Firefox) | Where-Object Id -eq 'Firefox:SSLVersionMin'
        $entry.Value | Should -Be 'tls1.2'
        $entry.Type  | Should -Be 'String'
    }

    It 'sets Brave-specific analytics and wallet policies' {
        $catalog = Get-BaselineBrowserPolicySettings -Browser Brave
        ($catalog | Where-Object Id -eq 'Brave:BraveWalletDisabled').Value | Should -Be 1
        ($catalog | Where-Object Id -eq 'Brave:BraveP3AEnabled').Value | Should -Be 0
        ($catalog | Where-Object Id -eq 'Brave:BraveStatsPingEnabled').Value | Should -Be 0
        ($catalog | Where-Object Id -eq 'Brave:BraveAIChatEnabled').Value | Should -Be 0
    }

    It 'returns only Edge entries when -Browser Edge is requested' {
        $catalog = Get-BaselineBrowserPolicySettings -Browser Edge
        $catalog | ForEach-Object Browser | Sort-Object -Unique | Should -Be 'Edge'
    }

    It 'returns only Chrome entries when -Browser Chrome is requested' {
        $catalog = Get-BaselineBrowserPolicySettings -Browser Chrome
        $catalog | ForEach-Object Browser | Sort-Object -Unique | Should -Be 'Chrome'
    }

    It 'returns only Firefox entries when -Browser Firefox is requested' {
        $catalog = Get-BaselineBrowserPolicySettings -Browser Firefox
        $catalog | ForEach-Object Browser | Sort-Object -Unique | Should -Be 'Firefox'
    }

    It 'returns only Brave entries when -Browser Brave is requested' {
        $catalog = Get-BaselineBrowserPolicySettings -Browser Brave
        $catalog | ForEach-Object Browser | Sort-Object -Unique | Should -Be 'Brave'
    }

    It 'targets the documented HKLM ADMX policy keys' {
        $catalog = Get-BaselineBrowserPolicySettings
        ($catalog | Where-Object Browser -eq 'Edge')   | ForEach-Object Path | Sort-Object -Unique | Should -Be 'HKLM:\Software\Policies\Microsoft\Edge'
        ($catalog | Where-Object Browser -eq 'Chrome') | ForEach-Object Path | Sort-Object -Unique | Should -Be 'HKLM:\Software\Policies\Google\Chrome'
        ($catalog | Where-Object Browser -eq 'Firefox') | ForEach-Object Path | Sort-Object -Unique | Should -Be 'HKLM:\Software\Policies\Mozilla\Firefox'
        ($catalog | Where-Object Browser -eq 'Brave')   | ForEach-Object Path | Sort-Object -Unique | Should -Be 'HKLM:\Software\Policies\BraveSoftware\Brave'
    }
}

Describe 'Get-BaselineBrowserPolicyBackupRoot' {
    AfterEach { $env:BASELINE_BROWSER_POLICY_BACKUP_ROOT = $script:backupRoot }

    It 'returns the env override when set' {
        $env:BASELINE_BROWSER_POLICY_BACKUP_ROOT = 'HKCU:\Software\Foo'
        Get-BaselineBrowserPolicyBackupRoot | Should -Be 'HKCU:\Software\Foo'
    }

    It 'falls through to HKLM:\Software\Baseline\BrowserPolicies when no override is set' {
        Remove-Item -LiteralPath Env:BASELINE_BROWSER_POLICY_BACKUP_ROOT -ErrorAction SilentlyContinue
        Get-BaselineBrowserPolicyBackupRoot | Should -Be 'HKLM:\Software\Baseline\BrowserPolicies'
    }
}

Describe 'ConvertTo-BaselineBrowserPolicyBackupKey' {
    It 'replaces the colon separator with double underscore' {
        ConvertTo-BaselineBrowserPolicyBackupKey -Id 'Edge:SmartScreenEnabled' | Should -Be 'Edge__SmartScreenEnabled'
        ConvertTo-BaselineBrowserPolicyBackupKey -Id 'Chrome:DnsOverHttpsMode' | Should -Be 'Chrome__DnsOverHttpsMode'
    }
}

Describe 'Set-BaselineBrowserPolicySettings' {
    BeforeEach { Reset-BrowserSandbox }

    It 'writes the desired DWord value to the live key' {
        $setting = New-BrowserSetting -Id 'Edge:Test' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1
    }

    It 'writes string-typed policies (e.g. SSLVersionMin)' {
        $setting = New-BrowserSetting -Id 'Edge:SSL' -Browser 'Edge' -Name 'SSLVersionMin' -Value 'tls1.2' -Type 'String'
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 'tls1.2'
    }

    It 'snapshots the prior value into a colon-safe backup key when one existed' {
        $setting = New-BrowserSetting -Id 'Chrome:Test' -Browser 'Chrome' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 99 -Type DWord -Force

        $result = @(Set-BaselineBrowserPolicySettings -Settings @($setting))
        $result[0].PreviousValue | Should -Be 99
        $result[0].PreviousExists | Should -BeTrue
        $result[0].BackupCreated | Should -BeTrue

        $backupKey = Join-Path $script:backupRoot 'Chrome__Test'
        Test-Path -LiteralPath $backupKey | Should -BeTrue
        $b = Get-ItemProperty -LiteralPath $backupKey
        $b.Value | Should -Be 99
        $b.Existed | Should -Be 1
        $b.Browser | Should -Be 'Chrome'
    }

    It 'records Existed=0 when no prior value was present' {
        $setting = New-BrowserSetting -Id 'Edge:Fresh' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        $b = Get-ItemProperty -LiteralPath (Join-Path $script:backupRoot 'Edge__Fresh')
        $b.Existed | Should -Be 0
    }

    It 'does not overwrite an existing backup on re-run' {
        $setting = New-BrowserSetting -Id 'Edge:Drift' -Browser 'Edge' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 50 -Type DWord -Force

        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        $result = @(Set-BaselineBrowserPolicySettings -Settings @($setting))
        $result[0].BackupCreated | Should -BeFalse

        $b = Get-ItemProperty -LiteralPath (Join-Path $script:backupRoot 'Edge__Drift')
        $b.Value | Should -Be 50  # genuine original survives a re-apply
    }

    It 'honours -WhatIf without writing or backing up' {
        $setting = New-BrowserSetting -Id 'Edge:Whatif' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) -WhatIf | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'Edge__Whatif') | Should -BeFalse
    }
}

Describe 'Restore-BaselineBrowserPolicySettings' {
    BeforeEach { Reset-BrowserSandbox }

    It 'restores a prior value when Existed=1' {
        $setting = New-BrowserSetting -Id 'Edge:R1' -Browser 'Edge' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 7 -Type DWord -Force

        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1

        Restore-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 7
    }

    It 'removes the live value when Existed=0' {
        $setting = New-BrowserSetting -Id 'Edge:R2' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1

        Restore-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
    }

    It 'removes the backup key after a successful restore' {
        $setting = New-BrowserSetting -Id 'Edge:R3' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Restore-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'Edge__R3') | Should -BeFalse
    }

    It 'reports SkipReason=NoBackup when no backup exists' {
        $setting = New-BrowserSetting -Id 'Edge:R4' -Browser 'Edge' -Name 'Foo' -Value 1
        $result = @(Restore-BaselineBrowserPolicySettings -Settings @($setting))
        $result[0].Restored | Should -BeFalse
        $result[0].Skipped | Should -BeTrue
        $result[0].SkipReason | Should -Be 'NoBackup'
    }
}

Describe 'Get-BaselineBrowserPolicyStatus' {
    BeforeEach { Reset-BrowserSandbox }

    It 'classifies a live key matching desired as Hardened' {
        $setting = New-BrowserSetting -Id 'Edge:S1' -Browser 'Edge' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 1 -Type DWord -Force

        $status = @(Get-BaselineBrowserPolicyStatus -Settings @($setting))
        $status[0].State | Should -Be 'Hardened'
        $status[0].CurrentValue | Should -Be 1
        $status[0].Browser | Should -Be 'Edge'
    }

    It 'classifies a live key with a different value as Drift' {
        $setting = New-BrowserSetting -Id 'Edge:S2' -Browser 'Edge' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 99 -Type DWord -Force

        $status = @(Get-BaselineBrowserPolicyStatus -Settings @($setting))
        $status[0].State | Should -Be 'Drift'
        $status[0].CurrentValue | Should -Be 99
    }

    It 'classifies a missing live value as NotSet' {
        $setting = New-BrowserSetting -Id 'Edge:S3' -Browser 'Edge' -Name 'Foo' -Value 1
        $status = @(Get-BaselineBrowserPolicyStatus -Settings @($setting))
        $status[0].State | Should -Be 'NotSet'
    }

    It 'reports BackupPresent after an apply' {
        $setting = New-BrowserSetting -Id 'Edge:S4' -Browser 'Edge' -Name 'Foo' -Value 1
        Set-BaselineBrowserPolicySettings -Settings @($setting) | Out-Null
        $status = @(Get-BaselineBrowserPolicyStatus -Settings @($setting))
        $status[0].BackupPresent | Should -BeTrue
    }
}
