Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $systemDataPath = Join-Path $PSScriptRoot '../../Module/Data/System.json'
    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/System/System.Updates.psm1'
    $script:SystemData = Get-BaselineTestSourceText -Path $systemDataPath | ConvertFrom-Json
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('StoreSearchResults', 'WindowsUpdate', 'Convert-WindowsUpdateRepairRegistryPathForRegExe', 'Export-WindowsUpdateRepairRegistryKey', 'Remove-WindowsUpdateRepairRegistryKey', 'Get-WindowsUpdateRepairServiceIfPresent', 'Stop-WindowsUpdateRepairServiceIfPresent', 'Set-WindowsUpdateRepairServiceStartupIfPresent', 'Start-WindowsUpdateRepairServiceIfPresent', 'Remove-WindowsUpdateRepairItemIfPresent', 'Rename-WindowsUpdateRepairItemIfPresent', 'Remove-WindowsUpdateRepairRegistryValueIfPresent', 'Remove-WindowsUpdateRepairBitsTransfersIfPresent', 'DownloadUpdatesOverMeteredConnection', 'StoreAppAutoDownload', 'FeatureUpdateDeferral', 'QualityUpdateDeferral', 'UpdateNotificationLevel', 'WindowsUpdateDisableAll', 'WindowsUpdateSecurityOnlyMode', 'WindowsUpdatePause')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'WindowsUpdateSecurityOnlyMode' {
    BeforeEach {
        $script:updateSecurityOnlyCalls = [pscustomobject]@{
            AutoDownload = [System.Collections.Generic.List[string]]::new()
            Driver = [System.Collections.Generic.List[string]]::new()
            Restart = [System.Collections.Generic.List[string]]::new()
            FeatureDeferral = [System.Collections.Generic.List[string]]::new()
            QualityDeferral = [System.Collections.Generic.List[string]]::new()
        }

        <#
            .SYNOPSIS
        #>

        function UpdateAutoDownload {
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
                [switch]$Enable,
                [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
                [switch]$Disable
            )

            [void]$script:updateSecurityOnlyCalls.AutoDownload.Add($PSCmdlet.ParameterSetName)
        }

        <#
            .SYNOPSIS
        #>
        function UpdateDriver {
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
                [switch]$Enable,
                [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
                [switch]$Disable
            )

            [void]$script:updateSecurityOnlyCalls.Driver.Add($PSCmdlet.ParameterSetName)
        }

        <#
            .SYNOPSIS
        #>

        function UpdateRestart {
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
                [switch]$Enable,
                [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
                [switch]$Disable
            )

            [void]$script:updateSecurityOnlyCalls.Restart.Add($PSCmdlet.ParameterSetName)
        }

        <#
            .SYNOPSIS
        #>
        function FeatureUpdateDeferral {
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
                [switch]$Enable,
                [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
                [switch]$Disable
            )

            [void]$script:updateSecurityOnlyCalls.FeatureDeferral.Add($PSCmdlet.ParameterSetName)
        }

        <#
            .SYNOPSIS
        #>

        function QualityUpdateDeferral {
            param(
                [Parameter(Mandatory = $true, ParameterSetName = 'Default')]
                [switch]$Default,
                [Parameter(Mandatory = $true, ParameterSetName = 'FourDays')]
                [switch]$FourDays,
                [Parameter(Mandatory = $true, ParameterSetName = 'SevenDays')]
                [switch]$SevenDays
            )

            [void]$script:updateSecurityOnlyCalls.QualityDeferral.Add($PSCmdlet.ParameterSetName)
        }

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
        }

        <#
            .SYNOPSIS
        #>
        function LogError {
            param([string]$Message)
        }
    }

    AfterEach {
        Remove-Item Function:\UpdateAutoDownload -ErrorAction SilentlyContinue
        Remove-Item Function:\UpdateDriver -ErrorAction SilentlyContinue
        Remove-Item Function:\UpdateRestart -ErrorAction SilentlyContinue
        Remove-Item Function:\FeatureUpdateDeferral -ErrorAction SilentlyContinue
        Remove-Item Function:\QualityUpdateDeferral -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
    }

    It 'applies the security-only bundle when enabled' {
        WindowsUpdateSecurityOnlyMode -Enable

        @($script:updateSecurityOnlyCalls.AutoDownload) | Should -Be @('Disable')
        @($script:updateSecurityOnlyCalls.Driver) | Should -Be @('Disable')
        @($script:updateSecurityOnlyCalls.Restart) | Should -Be @('Disable')
        @($script:updateSecurityOnlyCalls.FeatureDeferral) | Should -Be @('Enable')
        @($script:updateSecurityOnlyCalls.QualityDeferral) | Should -Be @('FourDays')
    }

    It 'restores the normal update posture when disabled' {
        WindowsUpdateSecurityOnlyMode -Disable

        @($script:updateSecurityOnlyCalls.AutoDownload) | Should -Be @('Enable')
        @($script:updateSecurityOnlyCalls.Driver) | Should -Be @('Enable')
        @($script:updateSecurityOnlyCalls.Restart) | Should -Be @('Enable')
        @($script:updateSecurityOnlyCalls.FeatureDeferral) | Should -Be @('Disable')
        @($script:updateSecurityOnlyCalls.QualityDeferral) | Should -Be @('Default')
    }
}

Describe 'WindowsUpdatePause' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()

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

        function Remove-ItemProperty {
            param(
                [string]$Path,
                [object]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:removedPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'writes the pause registry values when enabled' {
        WindowsUpdatePause -Enable -StartDate '2025-04-08'

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:newItemPropertyCalls.Count | Should -Be 5
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'PauseFeatureUpdatesStartTime'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'PauseQualityUpdatesStartTime'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'PauseUpdatesStartTime'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'PausedFeatureDate'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'PausedQualityDate'
        ($script:newItemPropertyCalls | Where-Object Name -eq 'PauseUpdatesStartTime').Value | Should -Be '2025-04-08T00:00:00Z'
    }

    It 'clears the pause registry values when disabled' {
        WindowsUpdatePause -Disable

        $script:removedPropertyCalls.Count | Should -Be 1
        $script:removedPropertyCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:removedPropertyCalls[0].Name | Should -Be @(
            'PauseFeatureUpdatesStartTime'
            'PauseQualityUpdatesStartTime'
            'PauseUpdatesStartTime'
            'PausedFeatureDate'
            'PausedQualityDate'
        )
        $script:newItemPropertyCalls.Count | Should -Be 0
    }
}

Describe 'WindowsUpdateDisableAll' {
    BeforeEach {
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:stoppedServices = [System.Collections.Generic.List[string]]::new()
        $script:setServiceCalls = [System.Collections.Generic.List[object]]::new()
        $script:disabledTasks = [System.Collections.Generic.List[string]]::new()
        $script:enabledTasks = [System.Collections.Generic.List[string]]::new()
        $script:scheduledTaskActions = [System.Collections.Generic.List[object]]::new()
        $script:scheduledTaskTriggers = [System.Collections.Generic.List[object]]::new()
        $script:scheduledTaskSettings = [System.Collections.Generic.List[object]]::new()
        $script:scheduledTaskPrincipals = [System.Collections.Generic.List[object]]::new()
        $script:registeredTasks = [System.Collections.Generic.List[object]]::new()
        $script:unregisteredTasks = [System.Collections.Generic.List[object]]::new()
        $script:setContentCalls = [System.Collections.Generic.List[object]]::new()

        function Write-ConsoleStatus {
            param(
                [string]$Action,
                [string]$Status
            )
        }

        function LogInfo {
            param([string]$Message)
        }

        function LogError {
            param([string]$Message)
        }

        function Test-Path {
            param([string]$Path)
            return $false
        }

        function New-Item {
            param(
                [string]$Path,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:newItemCalls.Add($Path)
        }

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
                Path = $Path
                Name = $Name
                PropertyType = $PropertyType
                Value = $Value
            })
        }

        function Set-Content {
            param(
                [string]$LiteralPath,
                [object]$Value,
                [string]$Encoding,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:setContentCalls.Add([pscustomobject]@{
                LiteralPath = $LiteralPath
                Value = [string]$Value
            })
        }

        function Remove-ItemProperty {
            param(
                [string]$Path,
                [object]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:removedPropertyCalls.Add([pscustomobject]@{
                Path = $Path
                Name = $Name
            })
        }

        function Stop-Service {
            param(
                [string]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:stoppedServices.Add($Name)
        }

        function Set-Service {
            param(
                [string]$Name,
                [string]$StartupType,
                [object]$ErrorAction
            )

            [void]$script:setServiceCalls.Add([pscustomobject]@{
                Name = $Name
                StartupType = $StartupType
            })
        }

        function Get-ScheduledTask {
            param(
                [string]$TaskName,
                [string]$TaskPath,
                [object]$ErrorAction
            )

            [pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath }
        }

        function Disable-ScheduledTask {
            process {
                [void]$script:disabledTasks.Add([string]$_.TaskPath)
            }
        }

        function Enable-ScheduledTask {
            process {
                [void]$script:enabledTasks.Add([string]$_.TaskPath)
            }
        }

        function New-ScheduledTaskAction {
            param(
                [string]$Execute,
                [string]$Argument
            )

            $action = [pscustomobject]@{ Execute = $Execute; Argument = $Argument }
            [void]$script:scheduledTaskActions.Add($action)
            return $action
        }

        function New-ScheduledTaskTrigger {
            param(
                [switch]$AtStartup,
                [switch]$AtLogon
            )

            $trigger = [pscustomobject]@{
                AtStartup = [bool]$AtStartup
                AtLogon = [bool]$AtLogon
            }
            [void]$script:scheduledTaskTriggers.Add($trigger)
            return $trigger
        }

        function New-ScheduledTaskSettingsSet {
            param(
                [switch]$AllowStartIfOnBatteries,
                [switch]$DontStopIfGoingOnBatteries,
                [switch]$StartWhenAvailable
            )

            $settings = [pscustomobject]@{
                AllowStartIfOnBatteries = [bool]$AllowStartIfOnBatteries
                DontStopIfGoingOnBatteries = [bool]$DontStopIfGoingOnBatteries
                StartWhenAvailable = [bool]$StartWhenAvailable
            }
            [void]$script:scheduledTaskSettings.Add($settings)
            return $settings
        }

        function New-ScheduledTaskPrincipal {
            param(
                [string]$UserId,
                [string]$LogonType,
                [string]$RunLevel
            )

            $principal = [pscustomobject]@{
                UserId = $UserId
                LogonType = $LogonType
                RunLevel = $RunLevel
            }
            [void]$script:scheduledTaskPrincipals.Add($principal)
            return $principal
        }

        function Unregister-ScheduledTask {
            param(
                [string]$TaskName,
                [string]$TaskPath,
                [switch]$Confirm,
                [object]$ErrorAction
            )

            [void]$script:unregisteredTasks.Add([pscustomobject]@{
                TaskName = $TaskName
                TaskPath = $TaskPath
            })
        }

        function Register-ScheduledTask {
            param(
                [string]$TaskName,
                [string]$TaskPath,
                [object]$Action,
                [object[]]$Trigger,
                [object]$Settings,
                [object]$Principal,
                [string]$Description,
                [switch]$Force
            )

            [void]$script:registeredTasks.Add([pscustomobject]@{
                TaskName = $TaskName
                TaskPath = $TaskPath
                Action = $Action
                Trigger = $Trigger
                Settings = $Settings
                Principal = $Principal
                Description = $Description
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Content -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Stop-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item Function:\Disable-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item Function:\Enable-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ScheduledTaskAction -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ScheduledTaskTrigger -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ScheduledTaskSettingsSet -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ScheduledTaskPrincipal -ErrorAction SilentlyContinue
        Remove-Item Function:\Unregister-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item Function:\Register-ScheduledTask -ErrorAction SilentlyContinue
    }

    It 'writes policy values, disables update services, disables update tasks, and registers the guard task when enabled' {
        WindowsUpdateDisableAll -Enable

        $script:newItemCalls | Should -Contain 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        $script:newItemCalls | Should -Contain 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
        ($script:newItemPropertyCalls | Where-Object Name -eq 'NoAutoUpdate').Value | Should -Be 1
        ($script:newItemPropertyCalls | Where-Object Name -eq 'AUOptions').Value | Should -Be 1
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DODownloadMode').Value | Should -Be 0
        @($script:stoppedServices) | Should -Be @('BITS', 'wuauserv', 'UsoSvc', 'WaaSMedicSvc')
        @($script:setServiceCalls | ForEach-Object StartupType) | Should -Be @('Disabled', 'Disabled', 'Disabled', 'Disabled')
        $script:disabledTasks.Count | Should -Be 6
        $script:registeredTasks.Count | Should -Be 1
        $script:registeredTasks[0].TaskName | Should -Be 'WindowsUpdateGuard'
        $script:registeredTasks[0].TaskPath | Should -Be '\Baseline\'
        $script:registeredTasks[0].Action.Execute | Should -Be 'powershell.exe'
        $script:registeredTasks[0].Action.Argument | Should -Match '-File'
        $script:setContentCalls.Count | Should -Be 1
        $script:setContentCalls[0].LiteralPath | Should -Match 'WindowsUpdateGuard\.ps1$'
        $script:setContentCalls[0].Value | Should -Match 'NoAutoUpdate'
        $script:setContentCalls[0].Value | Should -Match 'WaaSMedicSvc'
        $script:registeredTasks[0].Trigger.Count | Should -Be 2
        $script:registeredTasks[0].Principal.UserId | Should -Be 'NT AUTHORITY\SYSTEM'
    }

    It 'removes policy values, unregisters the guard task, restores service startup, and enables update tasks when disabled' {
        WindowsUpdateDisableAll -Disable

        $script:removedPropertyCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        $script:removedPropertyCalls[0].Name | Should -Be @('NoAutoUpdate', 'AUOptions')
        $script:removedPropertyCalls[1].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
        $script:removedPropertyCalls[1].Name | Should -Be 'DODownloadMode'
        $script:unregisteredTasks | Where-Object TaskName -eq 'WindowsUpdateGuard' | Should -Not -BeNullOrEmpty
        @($script:setServiceCalls | ForEach-Object StartupType) | Should -Be @('Manual', 'Manual', 'Automatic', 'Manual')
        $script:enabledTasks.Count | Should -Be 6
    }
}

Describe 'UpdateNotificationLevel' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()

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

        function Remove-ItemProperty {
            param(
                [string]$Path,
                [object]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:removedPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'restores the default update notification behavior when default is selected' {
        UpdateNotificationLevel -Default

        $script:removedPropertyCalls.Count | Should -Be 1
        $script:removedPropertyCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:removedPropertyCalls[0].Name | Should -Be 'SetUpdateNotificationLevel'
        $script:newItemCalls.Count | Should -Be 0
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'shows all update notifications when all is selected' {
        UpdateNotificationLevel -All

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'SetUpdateNotificationLevel'
        $script:newItemPropertyCalls[0].Value | Should -Be 0
    }

    It 'shows restart warnings only when restart-only is selected' {
        UpdateNotificationLevel -RestartOnly

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'SetUpdateNotificationLevel'
        $script:newItemPropertyCalls[0].Value | Should -Be 1
    }

    It 'hides all update notifications when off is selected' {
        UpdateNotificationLevel -Off

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'SetUpdateNotificationLevel'
        $script:newItemPropertyCalls[0].Value | Should -Be 2
    }
}

Describe 'Update notification metadata' {
    It 'uses the four-state selector with the documented policy values' {
        $updateNotification = @($script:SystemData.Entries | Where-Object Function -eq 'UpdateNotificationLevel')
        $updateNotification.Count | Should -Be 1
        $updateNotification[0].Type | Should -Be 'Choice'
        @($updateNotification[0].Options) | Should -Be @('Default', 'All', 'RestartOnly', 'Off')
        @($updateNotification[0].DisplayOptions) | Should -Be @('Default', 'All notifications', 'Restart only', 'Off')
        $updateNotification[0].Default | Should -Be 'Default'
        $updateNotification[0].WinDefault | Should -Be 'Default'
        $updateNotification[0].Detail | Should -Be 'Controls whether Windows shows all update notifications, only restart warnings, or no update notifications.'
    }
}

Describe 'Windows Update repair metadata' {
    It 'does not expose the repair workflow as a restorable Windows default item' {
        $windowsUpdateRepair = @($script:SystemData.Entries | Where-Object Function -eq 'WindowsUpdate')

        $windowsUpdateRepair.Count | Should -Be 1
        $windowsUpdateRepair[0].Restorable | Should -BeFalse
        $windowsUpdateRepair[0].RecoveryLevel | Should -Be 'Manual'
        $windowsUpdateRepair[0].WinDefault | Should -Be 'Standard'
    }
}

Describe 'FeatureUpdateDeferral' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()

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

        function Remove-ItemProperty {
            param(
                [string]$Path,
                [object]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:removedPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'writes the feature deferral keys when enabled' {
        FeatureUpdateDeferral -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:newItemPropertyCalls.Count | Should -Be 3
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'BranchReadinessLevel'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'DeferFeatureUpdates'
        $script:newItemPropertyCalls | ForEach-Object Name | Should -Contain 'DeferFeatureUpdatesPeriodInDays'
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DeferFeatureUpdatesPeriodInDays').Value | Should -Be 365
    }

    It 'clears the feature deferral keys when disabled' {
        FeatureUpdateDeferral -Disable

        $script:removedPropertyCalls.Count | Should -Be 1
        $script:removedPropertyCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:removedPropertyCalls[0].Name | Should -Be @('BranchReadinessLevel', 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays')
        $script:newItemPropertyCalls.Count | Should -Be 0
    }
}

Describe 'QualityUpdateDeferral' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:removedPropertyCalls = [System.Collections.Generic.List[object]]::new()

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

        function Remove-ItemProperty {
            param(
                [string]$Path,
                [object]$Name,
                [switch]$Force,
                [object]$ErrorAction
            )

            [void]$script:removedPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
            })
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'restores Windows default quality update behavior' {
        QualityUpdateDeferral -Default

        $script:removedPropertyCalls.Count | Should -Be 1
        $script:removedPropertyCalls[0].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $script:removedPropertyCalls[0].Name | Should -Be @('DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays')
        $script:newItemPropertyCalls.Count | Should -Be 0
    }

    It 'writes the four-day quality update deferral keys' {
        QualityUpdateDeferral -FourDays

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 2
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DeferQualityUpdates').Value | Should -Be 1
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DeferQualityUpdatesPeriodInDays').Value | Should -Be 4
    }

    It 'writes the seven-day quality update deferral keys' {
        QualityUpdateDeferral -SevenDays

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemPropertyCalls.Count | Should -Be 2
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DeferQualityUpdates').Value | Should -Be 1
        ($script:newItemPropertyCalls | Where-Object Name -eq 'DeferQualityUpdatesPeriodInDays').Value | Should -Be 7
    }
}

Describe 'Quality update deferral metadata' {
    It 'uses only the short dropdown labels' {
        $qualityDeferral = @($script:SystemData.Entries | Where-Object Function -eq 'QualityUpdateDeferral')
        $qualityDeferral.Count | Should -Be 1
        @($qualityDeferral[0].DisplayOptions).Count | Should -Be 3
        $qualityDeferral[0].DisplayOptions[0] | Should -Be 'default'
        $qualityDeferral[0].DisplayOptions[1] | Should -Be '4 days'
        $qualityDeferral[0].DisplayOptions[2] | Should -Be '7 days'
        $qualityDeferral[0].Detail | Should -Be 'Delays monthly quality updates by 4 or 7 days.'
    }
}

Describe 'DownloadUpdatesOverMeteredConnection' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

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
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'allows downloads over metered connections when enabled' {
        DownloadUpdatesOverMeteredConnection -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'AllowAutoWindowsUpdateDownloadOverMeteredNetwork'
        $script:newItemPropertyCalls[0].Value | Should -Be 1
    }

    It 'blocks downloads over metered connections when disabled' {
        DownloadUpdatesOverMeteredConnection -Disable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'AllowAutoWindowsUpdateDownloadOverMeteredNetwork'
        $script:newItemPropertyCalls[0].Value | Should -Be 0
    }
}

Describe 'StoreAppAutoDownload' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:newItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:newItemPropertyCalls = [System.Collections.Generic.List[object]]::new()

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
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\New-ItemProperty -ErrorAction SilentlyContinue
    }

    It 'allows Microsoft Store app updates when enabled' {
        StoreAppAutoDownload -Enable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'AutoDownload'
        $script:newItemPropertyCalls[0].Value | Should -Be 4
    }

    It 'blocks Microsoft Store app updates when disabled' {
        StoreAppAutoDownload -Disable

        $script:newItemCalls.Count | Should -Be 1
        $script:newItemCalls[0] | Should -Be 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
        $script:newItemPropertyCalls.Count | Should -Be 1
        $script:newItemPropertyCalls[0].Name | Should -Be 'AutoDownload'
        $script:newItemPropertyCalls[0].Value | Should -Be 2
    }
}

Describe 'StoreSearchResults' {
    BeforeEach {
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:icaclsCalls = [System.Collections.Generic.List[object]]::new()
        $script:originalLocalAppData = $env:LocalAppData
        $env:LocalAppData = '/tmp/LocalAppData'

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
        function LogWarning {
            param([string]$Message)
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
        function Test-Path {
            param([string]$LiteralPath)
            return $true
        }

        <#
            .SYNOPSIS
        #>
        function icacls {
            param(
                [string]$Path,
                [string]$Action,
                [string]$Principal
            )

            [void]$script:icaclsCalls.Add([pscustomobject]@{
                Path      = $Path
                Action    = $Action
                Principal = $Principal
            })

            $global:LASTEXITCODE = 0
        }
    }

    AfterEach {
        if ($null -ne $script:originalLocalAppData) {
            $env:LocalAppData = $script:originalLocalAppData
        } else {
            Remove-Item Env:LocalAppData -ErrorAction SilentlyContinue
        }

        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\icacls -ErrorAction SilentlyContinue
    }

    It 'blocks Microsoft Store search results when enabled' {
        StoreSearchResults -Enable

        $script:icaclsCalls.Count | Should -Be 1
        $script:icaclsCalls[0].Path | Should -Be (Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db')
        $script:icaclsCalls[0].Action | Should -Be '/deny'
        $script:icaclsCalls[0].Principal | Should -Be 'Everyone:F'
    }

    It 'unblocks Microsoft Store search results when disabled' {
        StoreSearchResults -Disable

        $script:icaclsCalls.Count | Should -Be 1
        $script:icaclsCalls[0].Path | Should -Be (Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db')
        $script:icaclsCalls[0].Action | Should -Be '/remove:d'
        $script:icaclsCalls[0].Principal | Should -Be 'Everyone'
    }
}

Describe 'WindowsUpdate' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedWarningMessages = [System.Collections.Generic.List[string]]::new()
        $script:loggedErrorMessages = [System.Collections.Generic.List[string]]::new()
        $script:startProcessCalls = [System.Collections.Generic.List[object]]::new()
        $script:stopServiceCalls = [System.Collections.Generic.List[string]]::new()
        $script:setServiceCalls = [System.Collections.Generic.List[object]]::new()
        $script:startServiceCalls = [System.Collections.Generic.List[string]]::new()
        $script:removeItemCalls = [System.Collections.Generic.List[object]]::new()
        $script:renameItemCalls = [System.Collections.Generic.List[object]]::new()
        $script:removeItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:setItemPropertyCalls = [System.Collections.Generic.List[object]]::new()
        $script:getBitsTransferCalls = [System.Collections.Generic.List[object]]::new()
        $script:bitsTransferRemovals = [System.Collections.Generic.List[object]]::new()
        $script:newObjectComObjects = [System.Collections.Generic.List[string]]::new()
        $script:detectNowCalled = $false

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
        function LogWarning {
            param([string]$Message)
            [void]$script:loggedWarningMessages.Add($Message)
        }

        <#
            .SYNOPSIS
        #>
        function LogError {
            param([string]$Message)
            [void]$script:loggedErrorMessages.Add($Message)
        }

        function LogDebug {
            param([string]$Message)
        }

        function Test-Path {
            param([string]$Path, [string]$LiteralPath)
            $candidate = if (-not [string]::IsNullOrWhiteSpace($LiteralPath)) { $LiteralPath } else { $Path }
            if ([string]::IsNullOrWhiteSpace($candidate)) { return $false }
            if ($candidate -like '*.bak') { return $false }
            if ($candidate -like '*\Application Data\Microsoft\Network\Downloader') { return $true }
            if ($candidate -like '*\SoftwareDistribution\Download') { return $true }
            if ($candidate -like '*\SoftwareDistribution\DataStore') { return $true }
            if ($candidate -like '*\System32\Catroot2') { return $true }
            if ($candidate -like '*\WindowsUpdate.log') { return $true }
            if ($candidate -like 'HKLM:\*' -or $candidate -like 'HKCU:\*') { return $true }
            return $false
        }

        <#
            .SYNOPSIS
        #>

        function Get-Service {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Name,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [pscustomobject]@{ Name = $Name }
        }

        <#
            .SYNOPSIS
        #>

        function Stop-Service {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Name,
                [object]$InputObject,
                [switch]$Force,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            $serviceName = if (-not [string]::IsNullOrWhiteSpace($Name)) { $Name } elseif ($InputObject -and $InputObject.PSObject.Properties['Name']) { [string]$InputObject.Name } else { '' }
            [void]$script:stopServiceCalls.Add($serviceName)
        }

        <#
            .SYNOPSIS
        #>
        function Set-Service {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Name,
                [string]$StartupType,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:setServiceCalls.Add([pscustomobject]@{
                Name = $Name
                StartupType = $StartupType
            })
        }

        <#
            .SYNOPSIS
        #>

        function Start-Service {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Name,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:startServiceCalls.Add($Name)
        }

        <#
            .SYNOPSIS
        #>
        function Remove-Item {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Path,
                [string]$LiteralPath,
                [switch]$Recurse,
                [switch]$Force,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:removeItemCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Recurse = [bool]$Recurse
            })
        }

        <#
            .SYNOPSIS
        #>

        function Get-Item {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Path,
                [string]$LiteralPath,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            $resolvedPath = if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path }
            if ($resolvedPath -like 'HKLM:\*' -or $resolvedPath -like 'HKCU:\*')
            {
                $item = [pscustomobject]@{ Path = $resolvedPath }
                $item | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value {
                    @(
                        'AccountDomainSid', 'PingID', 'SusClientId',
                        'ExcludeWUDriversInQualityUpdate', 'PreventDeviceMetadataFromNetwork',
                        'DontPromptForWindowsUpdate', 'DontSearchWindowsUpdate',
                        'DriverUpdateWizardWuSearchEnabled', 'NoAutoRebootWithLoggedOnUsers',
                        'AUPowerManagement', 'BranchReadinessLevel',
                        'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdatesPeriodInDays'
                    )
                } -Force
                return $item
            }

            [pscustomobject]@{ FullName = $resolvedPath }
        }

        <#
            .SYNOPSIS
        #>

        function Get-ChildItem {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$LiteralPath,
                [string]$Filter,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [pscustomobject]@{ FullName = (Join-Path $LiteralPath ($Filter -replace '\*', '0')) }
        }

        <#
            .SYNOPSIS
        #>

        function Rename-Item {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Path,
                [string]$LiteralPath,
                [string]$NewName,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:renameItemCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                NewName = $NewName
            })
        }

        <#
            .SYNOPSIS
        #>

        function Remove-ItemProperty {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Path,
                [string]$LiteralPath,
                [string]$Name,
                [switch]$Force,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:removeItemPropertyCalls.Add([pscustomobject]@{
                Path = $(if ([string]::IsNullOrEmpty($Path)) { $LiteralPath } else { $Path })
                Name = $Name
            })
        }

        <#
            .SYNOPSIS
        #>

        function Set-ItemProperty {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$Path, [string]$LiteralPath,
                [string]$Name,
                [object]$Value,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
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

        function Start-Process {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [switch]$NoNewWindow,
                [switch]$Wait,
                [string]$WindowStyle,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:startProcessCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
            })
        }

        function Invoke-BaselineProcess {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:startProcessCalls.Add([pscustomobject]@{
                FilePath = $FilePath
                ArgumentList = @($ArgumentList)
                TimeoutSeconds = $TimeoutSeconds
            })
            [pscustomobject]@{ ExitCode = 0 }
        }

        <#
            .SYNOPSIS
        #>

        function Get-BitsTransfer {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:getBitsTransferCalls.Add([pscustomobject]@{
                Invocation = $script:getBitsTransferCalls.Count + 1
            })

            [pscustomobject]@{
                JobId = '00000000-0000-0000-0000-000000000000'
            }
        }

        <#
            .SYNOPSIS
        #>

        function Remove-BitsTransfer {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [Parameter(ValueFromPipeline = $true)]
                [object]$InputObject,
                [object]$BitsJob,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            process
            {
                $targetJob = if ($null -ne $BitsJob) { $BitsJob } else { $InputObject }
                [void]$script:bitsTransferRemovals.Add($targetJob)
            }
        }

        <#
            .SYNOPSIS
        #>

        function New-Object {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [Parameter(Mandatory = $true)]
                [string]$ComObject,
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            [void]$script:newObjectComObjects.Add($ComObject)

            $result = [pscustomobject]@{}
            $result | Add-Member -MemberType ScriptMethod -Name DetectNow -Value {
                $script:detectNowCalled = $true
            } -PassThru
        }
    }

    AfterEach {
        Remove-Item Function:\Write-ConsoleStatus -ErrorAction SilentlyContinue
        Remove-Item Function:\LogInfo -ErrorAction SilentlyContinue
        Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        Remove-Item Function:\LogError -ErrorAction SilentlyContinue
        Remove-Item Function:\LogDebug -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Stop-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Start-Service -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
        Remove-Item Function:\Rename-Item -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-ItemProperty -ErrorAction SilentlyContinue
        Remove-Item Function:\Start-Process -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-BaselineProcess -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-BitsTransfer -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-BitsTransfer -ErrorAction SilentlyContinue
        Remove-Item Function:\New-Object -ErrorAction SilentlyContinue
    }

    It 'runs the standard repair sequence' {
        WindowsUpdate -Standard

        $script:consoleActions[0] | Should -Be 'Repairing Windows Update'
        $script:consoleStatuses[-1] | Should -Be 'success'
        $script:stopServiceCalls | Should -Be @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
        @($script:setServiceCalls | ForEach-Object Name) | Should -Be @('BITS', 'wuauserv', 'CryptSvc')
        @($script:startServiceCalls) | Should -Be @('BITS', 'wuauserv', 'CryptSvc', 'AppIDSvc')
        $script:renameItemCalls.Count | Should -Be 1
        $script:renameItemCalls[0].NewName | Should -Be 'Download.bak'
        @($script:startProcessCalls | Where-Object FilePath -like '*regsvr32.exe') | Should -HaveCount 36
        @($script:startProcessCalls | Where-Object FilePath -like '*cmd.exe') | Should -HaveCount 0
        @($script:startProcessCalls | Where-Object FilePath -like '*secedit.exe') | Should -HaveCount 0
        @($script:startProcessCalls | Where-Object FilePath -like '*gpupdate.exe') | Should -HaveCount 1
        @($script:startProcessCalls | Where-Object FilePath -like '*netsh.exe') | Should -HaveCount 3
        @($script:startProcessCalls | Where-Object FilePath -like '*wuauclt.exe') | Should -HaveCount 1
        $script:getBitsTransferCalls.Count | Should -Be 1
        $script:bitsTransferRemovals.Count | Should -Be 1
        $script:newObjectComObjects | Should -Be @('Microsoft.Update.AutoUpdate')
        $script:detectNowCalled | Should -Be $true
        $script:loggedWarningMessages.Count | Should -Be 0
        $script:loggedErrorMessages.Count | Should -Be 0
    }

    It 'runs the aggressive repair sequence' {
        WindowsUpdate -Aggressive

        $script:consoleActions[0] | Should -Be 'Repairing Windows Update (Aggressive)'
        $script:consoleStatuses[-1] | Should -Be 'success'
        @($script:renameItemCalls | ForEach-Object NewName) | Should -Be @('DataStore.bak', 'catroot2.bak', 'Download.bak')
        $script:startProcessCalls[0].FilePath | Should -BeLike '*chkdsk.exe'
        @($script:startProcessCalls[0].ArgumentList) | Should -Be @('/scan', '/perf')
        $script:startProcessCalls[1].FilePath | Should -BeLike '*sfc.exe'
        @($script:startProcessCalls[1].ArgumentList) | Should -Be @('/scannow')
        $script:startProcessCalls[2].FilePath | Should -BeLike '*dism.exe'
        @($script:startProcessCalls[2].ArgumentList) | Should -Be @('/online', '/cleanup-image', '/restorehealth')
        @($script:startProcessCalls | Where-Object FilePath -like '*sc.exe') | Should -HaveCount 2
        @($script:startProcessCalls | Where-Object FilePath -like '*cmd.exe') | Should -HaveCount 0
        @($script:startProcessCalls | Where-Object FilePath -like '*wuauclt.exe') | Should -HaveCount 1
        $script:getBitsTransferCalls.Count | Should -Be 1
        $script:bitsTransferRemovals.Count | Should -Be 1
        $script:newObjectComObjects | Should -Be @('Microsoft.Update.AutoUpdate')
        $script:detectNowCalled | Should -Be $true
        $script:loggedWarningMessages.Count | Should -Be 0
        $script:loggedErrorMessages.Count | Should -Be 0
    }
}
