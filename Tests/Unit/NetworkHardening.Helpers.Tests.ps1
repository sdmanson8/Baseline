Set-StrictMode -Version Latest

BeforeAll {
    $registryHelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Registry.Helpers.ps1'
    . $registryHelperPath

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/NetworkHardening.Helpers.ps1'
    . $filePath

    $script:sandboxBase = "HKCU:\Software\Baseline_NetworkHardening_Tests_$([guid]::NewGuid().ToString('N'))"
    $script:liveRoot    = Join-Path $script:sandboxBase 'Live'
    $script:backupRoot  = Join-Path $script:sandboxBase 'Backup'
    $script:netbtRoot   = Join-Path $script:sandboxBase 'NetBT\Interfaces'

    $env:BASELINE_NETHARD_BACKUP_ROOT      = $script:backupRoot
    $env:BASELINE_NETBT_INTERFACES_ROOT    = $script:netbtRoot

    function Reset-NetSandbox
    {
        if (Test-Path -LiteralPath $script:sandboxBase)
        {
            Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:liveRoot -Force | Out-Null
        New-Item -Path $script:backupRoot -Force | Out-Null
        New-Item -Path $script:netbtRoot -Force | Out-Null
    }

    function New-FakeSetting
    {
        param(
            [string]$Id,
            [string]$Name,
            $Value
        )
        $path = Join-Path $script:liveRoot $Id
        return [pscustomobject]@{
            Id          = $Id
            Path        = $path
            Name        = $Name
            Type        = 'DWord'
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

    function New-FakeAdapter
    {
        param([string]$AdapterId, [Nullable[int]]$NetbiosOptions)
        $key = Join-Path $script:netbtRoot $AdapterId
        New-Item -Path $key -Force | Out-Null
        if ($null -ne $NetbiosOptions)
        {
            Set-ItemProperty -LiteralPath $key -Name 'NetbiosOptions' -Value $NetbiosOptions -Type DWord -Force
        }
    }

    function Get-AdapterNetbiosOptions
    {
        param([string]$AdapterId)
        $key = Join-Path $script:netbtRoot $AdapterId
        if (-not (Test-Path -LiteralPath $key)) { return $null }
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $item -or -not $item.PSObject.Properties['NetbiosOptions']) { return $null }
        return [int]$item.NetbiosOptions
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:sandboxBase)
    {
        Remove-Item -LiteralPath $script:sandboxBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath Env:BASELINE_NETHARD_BACKUP_ROOT   -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath Env:BASELINE_NETBT_INTERFACES_ROOT -ErrorAction SilentlyContinue
}

Describe 'Get-BaselineNetworkHardeningRegistrySettings' {
    It 'returns the canonical catalog including all spec items' {
        $catalog = Get-BaselineNetworkHardeningRegistrySettings
        $ids = $catalog | ForEach-Object Id
        $ids | Should -Contain 'IGMPLevel'
        $ids | Should -Contain 'DisableIPSourceRouting'
        $ids | Should -Contain 'EnableICMPRedirect'
        $ids | Should -Contain 'TcpMaxDataRetransmissions'
        $ids | Should -Contain 'KeepAliveTime'
        $ids | Should -Contain 'PerformRouterDiscovery'
        $ids | Should -Contain 'EnableDeadGWDetect'
        $ids | Should -Contain 'LlmnrDisable'
        $ids | Should -Contain 'MdnsDisable'
        $ids | Should -Contain 'RpcEpMapAuth'
    }

    It 'returns each setting with required fields populated' {
        $catalog = Get-BaselineNetworkHardeningRegistrySettings
        foreach ($s in $catalog) {
            $s.Path | Should -Not -BeNullOrEmpty
            $s.Name | Should -Not -BeNullOrEmpty
            $s.Type | Should -Be 'DWord'
            $s.Description | Should -Not -BeNullOrEmpty
        }
    }

    It 'sets DisableIPSourceRouting to 2 (reject all)' {
        $entry = Get-BaselineNetworkHardeningRegistrySettings | Where-Object Id -eq 'DisableIPSourceRouting'
        $entry.Value | Should -Be 2
    }

    It 'sets KeepAliveTime to 300000ms (5 minutes)' {
        $entry = Get-BaselineNetworkHardeningRegistrySettings | Where-Object Id -eq 'KeepAliveTime'
        $entry.Value | Should -Be 300000
    }
}

Describe 'Get-BaselineNetworkHardeningBackupRoot' {
    AfterEach { $env:BASELINE_NETHARD_BACKUP_ROOT = $script:backupRoot }

    It 'returns the env override when set' {
        $env:BASELINE_NETHARD_BACKUP_ROOT = 'HKCU:\Software\Foo'
        Get-BaselineNetworkHardeningBackupRoot | Should -Be 'HKCU:\Software\Foo'
    }

    It 'falls through to HKLM:\Software\Baseline\NetworkHardening when no override is set' {
        Remove-Item -LiteralPath Env:BASELINE_NETHARD_BACKUP_ROOT -ErrorAction SilentlyContinue
        Get-BaselineNetworkHardeningBackupRoot | Should -Be 'HKLM:\Software\Baseline\NetworkHardening'
    }
}

Describe 'Set-BaselineNetworkHardeningRegistrySettings' {
    BeforeEach { Reset-NetSandbox }

    It 'writes the desired value to the live key' {
        $setting = New-FakeSetting -Id 'TestA' -Name 'Foo' -Value 42
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 42
    }

    It 'snapshots the prior value into the backup key when one existed' {
        $setting = New-FakeSetting -Id 'TestB' -Name 'Foo' -Value 0
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 7 -Type DWord -Force

        $result = @(Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting))
        $result[0].PreviousValue | Should -Be 7
        $result[0].PreviousExists | Should -BeTrue
        $result[0].BackupCreated | Should -BeTrue

        $backupKey = Join-Path $script:backupRoot 'TestB'
        Test-Path -LiteralPath $backupKey | Should -BeTrue
        $backup = Get-ItemProperty -LiteralPath $backupKey
        $backup.Value | Should -Be 7
        $backup.Existed | Should -Be 1
    }

    It 'records Existed=0 when no prior value was present' {
        $setting = New-FakeSetting -Id 'TestC' -Name 'Foo' -Value 1
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null

        $backupKey = Join-Path $script:backupRoot 'TestC'
        $backup = Get-ItemProperty -LiteralPath $backupKey
        $backup.Existed | Should -Be 0
    }

    It 'does not overwrite an existing backup on re-run' {
        $setting = New-FakeSetting -Id 'TestD' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 99 -Type DWord -Force

        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        # First apply succeeded; live now has $setting.Value (=1).
        # If we re-apply, the helper should NOT capture 1 as the original.
        $result = @(Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting))
        $result[0].BackupCreated | Should -BeFalse

        $backupKey = Join-Path $script:backupRoot 'TestD'
        $backup = Get-ItemProperty -LiteralPath $backupKey
        $backup.Value | Should -Be 99  # the genuine original survives
    }

    It 'honours -WhatIf without writing or creating backups' {
        $setting = New-FakeSetting -Id 'TestE' -Name 'Foo' -Value 1
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) -WhatIf | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'TestE') | Should -BeFalse
    }
}

Describe 'Restore-BaselineNetworkHardeningRegistrySettings' {
    BeforeEach { Reset-NetSandbox }

    It 'restores a prior value when Existed=1' {
        $setting = New-FakeSetting -Id 'TestF' -Name 'Foo' -Value 1
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 50 -Type DWord -Force

        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 1

        Restore-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 50
    }

    It 'removes the live value when Existed=0' {
        $setting = New-FakeSetting -Id 'TestG' -Name 'Foo' -Value 5
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -Be 5

        Restore-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Get-LiveValue -Setting $setting | Should -BeNullOrEmpty
    }

    It 'removes the backup key after a successful restore' {
        $setting = New-FakeSetting -Id 'TestH' -Name 'Foo' -Value 5
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Restore-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        Test-Path -LiteralPath (Join-Path $script:backupRoot 'TestH') | Should -BeFalse
    }

    It 'reports SkipReason=NoBackup when no backup exists' {
        $setting = New-FakeSetting -Id 'TestI' -Name 'Foo' -Value 5
        $result = @(Restore-BaselineNetworkHardeningRegistrySettings -Settings @($setting))
        $result[0].Restored | Should -BeFalse
        $result[0].Skipped | Should -BeTrue
        $result[0].SkipReason | Should -Be 'NoBackup'
    }
}

Describe 'Get-BaselineNetworkHardeningRegistryStatus' {
    BeforeEach { Reset-NetSandbox }

    It 'classifies a live key matching desired as Hardened' {
        $setting = New-FakeSetting -Id 'TestJ' -Name 'Foo' -Value 5
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 5 -Type DWord -Force

        $status = @(Get-BaselineNetworkHardeningRegistryStatus -Settings @($setting))
        $status[0].State | Should -Be 'Hardened'
        $status[0].CurrentValue | Should -Be 5
    }

    It 'classifies a live key with a different value as Drift' {
        $setting = New-FakeSetting -Id 'TestK' -Name 'Foo' -Value 5
        New-Item -Path $setting.Path -Force | Out-Null
        Set-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -Value 99 -Type DWord -Force

        $status = @(Get-BaselineNetworkHardeningRegistryStatus -Settings @($setting))
        $status[0].State | Should -Be 'Drift'
        $status[0].CurrentValue | Should -Be 99
    }

    It 'classifies a missing live value as NotSet' {
        $setting = New-FakeSetting -Id 'TestL' -Name 'Foo' -Value 5
        $status = @(Get-BaselineNetworkHardeningRegistryStatus -Settings @($setting))
        $status[0].State | Should -Be 'NotSet'
        $status[0].CurrentValue | Should -BeNullOrEmpty
    }

    It 'reports BackupPresent when a Baseline backup exists' {
        $setting = New-FakeSetting -Id 'TestM' -Name 'Foo' -Value 5
        Set-BaselineNetworkHardeningRegistrySettings -Settings @($setting) | Out-Null
        $status = @(Get-BaselineNetworkHardeningRegistryStatus -Settings @($setting))
        $status[0].BackupPresent | Should -BeTrue
    }
}

Describe 'Disable-BaselineNetBiosOverTcpip' {
    BeforeEach { Reset-NetSandbox }

    It 'sets NetbiosOptions=2 on every adapter' {
        New-FakeAdapter -AdapterId 'Tcpip_{aaaa}' -NetbiosOptions 0
        New-FakeAdapter -AdapterId 'Tcpip_{bbbb}' -NetbiosOptions 1

        Disable-BaselineNetBiosOverTcpip | Out-Null
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{aaaa}' | Should -Be 2
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{bbbb}' | Should -Be 2
    }

    It 'snapshots prior values into per-adapter backups' {
        New-FakeAdapter -AdapterId 'Tcpip_{cccc}' -NetbiosOptions 0
        Disable-BaselineNetBiosOverTcpip | Out-Null

        $bk = Join-Path (Join-Path $script:backupRoot 'NetBiosOverTcpip') 'Tcpip_{cccc}'
        Test-Path -LiteralPath $bk | Should -BeTrue
        $b = Get-ItemProperty -LiteralPath $bk
        $b.Value | Should -Be 0
        $b.Existed | Should -Be 1
    }

    It 'records Existed=0 for adapters with no prior NetbiosOptions value' {
        New-FakeAdapter -AdapterId 'Tcpip_{dddd}' -NetbiosOptions $null
        Disable-BaselineNetBiosOverTcpip | Out-Null

        $bk = Join-Path (Join-Path $script:backupRoot 'NetBiosOverTcpip') 'Tcpip_{dddd}'
        $b = Get-ItemProperty -LiteralPath $bk
        $b.Existed | Should -Be 0
    }

    It 'returns one record per processed adapter' {
        New-FakeAdapter -AdapterId 'Tcpip_{eeee}' -NetbiosOptions 0
        New-FakeAdapter -AdapterId 'Tcpip_{ffff}' -NetbiosOptions 1
        # also create a non-Tcpip subkey that should be ignored
        New-Item -Path (Join-Path $script:netbtRoot 'NotAnAdapter') -Force | Out-Null

        $results = @(Disable-BaselineNetBiosOverTcpip)
        $results.Count | Should -Be 2
    }
}

Describe 'Restore-BaselineNetBiosOverTcpip' {
    BeforeEach { Reset-NetSandbox }

    It 'restores prior NetbiosOptions when Existed=1' {
        New-FakeAdapter -AdapterId 'Tcpip_{1111}' -NetbiosOptions 1
        Disable-BaselineNetBiosOverTcpip | Out-Null
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{1111}' | Should -Be 2

        Restore-BaselineNetBiosOverTcpip | Out-Null
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{1111}' | Should -Be 1
    }

    It 'removes NetbiosOptions when Existed=0' {
        New-FakeAdapter -AdapterId 'Tcpip_{2222}' -NetbiosOptions $null
        Disable-BaselineNetBiosOverTcpip | Out-Null
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{2222}' | Should -Be 2

        Restore-BaselineNetBiosOverTcpip | Out-Null
        Get-AdapterNetbiosOptions -AdapterId 'Tcpip_{2222}' | Should -BeNullOrEmpty
    }

    It 'returns an empty array when no backups exist' {
        $results = @(Restore-BaselineNetBiosOverTcpip)
        $results.Count | Should -Be 0
    }
}

Describe 'Disable-BaselineWinRMService' {
    BeforeEach { Reset-NetSandbox }

    It 'snapshots prior state and invokes stop + disable when service is running' {
        $fakeService = [pscustomobject]@{ Name='WinRM'; StartType='Manual'; Status='Running' }
        $stopCalled = $false
        $disableCalled = $false
        $stop = { $script:stopCalled = $true }
        $disable = { $script:disableCalled = $true }
        $script:stopCalled = $false
        $script:disableCalled = $false

        $result = Disable-BaselineWinRMService `
            -ServiceLookup { $fakeService } `
            -StopAction $stop `
            -DisableAction $disable

        $result.Found | Should -BeTrue
        $result.Stopped | Should -BeTrue
        $result.Disabled | Should -BeTrue
        $script:stopCalled | Should -BeTrue
        $script:disableCalled | Should -BeTrue

        $bk = Get-BaselineWinRMServiceBackupKey
        $b = Get-ItemProperty -LiteralPath $bk
        $b.PriorStartType | Should -Be 'Manual'
        $b.PriorStatus | Should -Be 'Running'
    }

    It 'does not stop a service that is already Stopped' {
        $fakeService = [pscustomobject]@{ Name='WinRM'; StartType='Manual'; Status='Stopped' }
        $script:stopCalled = $false
        $result = Disable-BaselineWinRMService `
            -ServiceLookup { $fakeService } `
            -StopAction { $script:stopCalled = $true } `
            -DisableAction { }
        $result.Stopped | Should -BeFalse
        $script:stopCalled | Should -BeFalse
    }

    It 'does not disable a service that is already Disabled' {
        $fakeService = [pscustomobject]@{ Name='WinRM'; StartType='Disabled'; Status='Stopped' }
        $script:disableCalled = $false
        $result = Disable-BaselineWinRMService `
            -ServiceLookup { $fakeService } `
            -StopAction { } `
            -DisableAction { $script:disableCalled = $true }
        $result.Disabled | Should -BeFalse
        $script:disableCalled | Should -BeFalse
    }

    It 'returns Skipped=$true when the service does not exist' {
        $result = Disable-BaselineWinRMService `
            -ServiceLookup { throw 'service not found' } `
            -StopAction { } `
            -DisableAction { }
        $result.Found | Should -BeFalse
        $result.Skipped | Should -BeTrue
        $result.SkipReason | Should -Be 'NotInstalled'
    }
}

Describe 'Restore-BaselineWinRMService' {
    BeforeEach { Reset-NetSandbox }

    It 'restores PriorStartType and starts when PriorStatus was Running' {
        # Simulate prior disable having captured the snapshot.
        Disable-BaselineWinRMService `
            -ServiceLookup { [pscustomobject]@{ Name='WinRM'; StartType='Manual'; Status='Running' } } `
            -StopAction { } -DisableAction { } | Out-Null

        $script:restoredType = $null
        $script:started = $false
        $result = Restore-BaselineWinRMService `
            -RestoreStartTypeAction { param($t) $script:restoredType = $t } `
            -StartAction { $script:started = $true }

        $result.Restored | Should -BeTrue
        $result.PriorStartType | Should -Be 'Manual'
        $result.StartTypeRestored | Should -BeTrue
        $script:restoredType | Should -Be 'Manual'
        $script:started | Should -BeTrue
    }

    It 'does not start the service if PriorStatus was not Running' {
        Disable-BaselineWinRMService `
            -ServiceLookup { [pscustomobject]@{ Name='WinRM'; StartType='Manual'; Status='Stopped' } } `
            -StopAction { } -DisableAction { } | Out-Null

        $script:started = $false
        Restore-BaselineWinRMService `
            -RestoreStartTypeAction { param($t) } `
            -StartAction { $script:started = $true } | Out-Null
        $script:started | Should -BeFalse
    }

    It 'removes the backup key after restore' {
        Disable-BaselineWinRMService `
            -ServiceLookup { [pscustomobject]@{ Name='WinRM'; StartType='Manual'; Status='Running' } } `
            -StopAction { } -DisableAction { } | Out-Null

        Restore-BaselineWinRMService `
            -RestoreStartTypeAction { param($t) } `
            -StartAction { } | Out-Null

        Test-Path -LiteralPath (Get-BaselineWinRMServiceBackupKey) | Should -BeFalse
    }

    It 'returns Skipped=$true with SkipReason=NoBackup when no snapshot exists' {
        $result = Restore-BaselineWinRMService `
            -RestoreStartTypeAction { param($t) } `
            -StartAction { }
        $result.Restored | Should -BeFalse
        $result.Skipped | Should -BeTrue
        $result.SkipReason | Should -Be 'NoBackup'
    }
}
