Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/UIPersonalization/UIPersonalization.Notifications.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Notifications registry writers (shared shims)' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:errorMessages = [System.Collections.Generic.List[string]]::new()
        $script:regCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeRegCalls = [System.Collections.Generic.List[object]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:pathExists = $false
        $script:regThrows = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogError { param([string]$Message) [void]$script:errorMessages.Add($Message) }
        function Set-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Type)
            if ($script:regThrows) { throw 'registry denied' }
            [void]$script:regCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value })
        }
        function Remove-RegistryValueSafe {
            param([string]$Path, [string]$Name, [object]$ErrorAction)
            [void]$script:removeRegCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
        function Test-Path { param([string]$Path) return $script:pathExists }
        function New-Item {
            param([string]$Path, [switch]$Force, [object]$ErrorAction)
            [void]$script:newItemCalls.Add($Path)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogError','Set-RegistryValueSafe','Remove-RegistryValueSafe','Test-Path','New-Item')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    Context 'Set-NotificationSounds' {
        It 'requires one of Enable or Disable' {
            { Set-NotificationSounds } | Should -Throw
        }

        It 'writes NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND=1 on Enable' {
            Set-NotificationSounds -Enable

            $script:regCalls[0].Name | Should -Be 'NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND'
            $script:regCalls[0].Value | Should -Be 1
            $script:consoleStatuses[-1] | Should -Be 'success'
        }

        It 'writes NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND=0 on Disable' {
            Set-NotificationSounds -Disable

            $script:regCalls[0].Value | Should -Be 0
        }

        It 'reports failed and logs an error when the registry write throws' {
            $script:regThrows = $true

            Set-NotificationSounds -Enable

            $script:consoleStatuses[-1] | Should -Be 'failed'
            $script:errorMessages[0] | Should -Match 'registry denied'
        }
    }

    Context 'Set-LockScreenNotifications' {
        It 'writes NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK=1 on Enable' {
            Set-LockScreenNotifications -Enable

            $script:regCalls[0].Name | Should -Be 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK'
            $script:regCalls[0].Value | Should -Be 1
        }

        It 'writes 0 on Disable' {
            Set-LockScreenNotifications -Disable

            $script:regCalls[0].Value | Should -Be 0
        }
    }

    Context 'Set-CriticalNotificationsOnLockScreen' {
        It 'writes NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK on Enable' {
            Set-CriticalNotificationsOnLockScreen -Enable

            $script:regCalls[0].Name | Should -Be 'NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK'
            $script:regCalls[0].Value | Should -Be 1
        }
    }

    Context 'Set-DSTNotifications' {
        It 'writes DstNotification=1 on Enable and 0 on Disable' {
            Set-DSTNotifications -Enable
            Set-DSTNotifications -Disable

            $script:regCalls[0].Name | Should -Be 'DstNotification'
            $script:regCalls[0].Value | Should -Be 1
            $script:regCalls[1].Value | Should -Be 0
        }
    }

    Context 'Set-CapabilityAccessNotifications' {
        It 'removes Enabled value on Enable' {
            Set-CapabilityAccessNotifications -Enable

            $script:removeRegCalls[0].Name | Should -Be 'Enabled'
            $script:removeRegCalls[0].Path | Should -Match 'CapabilityAccessNotification'
        }

        It 'creates the key and sets Enabled=0 on Disable when path is missing' {
            $script:pathExists = $false

            Set-CapabilityAccessNotifications -Disable

            $script:newItemCalls.Count | Should -Be 1
            $script:regCalls[0].Name | Should -Be 'Enabled'
            $script:regCalls[0].Value | Should -Be 0
        }

        It 'skips key creation on Disable when path already exists' {
            $script:pathExists = $true

            Set-CapabilityAccessNotifications -Disable

            $script:newItemCalls.Count | Should -Be 0
            $script:regCalls[0].Value | Should -Be 0
        }
    }

    Context 'Set-StartupAppNotifications and Set-SecurityMaintenanceNotifications' {
        It 'StartupApp -Enable removes the Enabled value' {
            Set-StartupAppNotifications -Enable

            $script:removeRegCalls[0].Path | Should -Match 'StartupTask'
        }

        It 'SecurityMaintenance -Disable creates the key path and writes Enabled=0' {
            $script:pathExists = $false

            Set-SecurityMaintenanceNotifications -Disable

            $script:newItemCalls.Count | Should -Be 1
            $script:regCalls[0].Name | Should -Be 'Enabled'
            $script:regCalls[0].Value | Should -Be 0
        }
    }
}
