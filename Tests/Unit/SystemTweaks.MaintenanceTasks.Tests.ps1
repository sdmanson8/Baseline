Set-StrictMode -Version Latest

BeforeAll {
    # Stubs for module-level dependencies normally pulled in via `using module`.
    function LogInfo { param([string]$Message) }
    function LogWarning { param([string]$Message) }
    function Write-ConsoleStatus { param([string]$Action, [string]$Status) }

    # Localization stub - returns the supplied fallback verbatim (with format
    # substitution if requested), so tests stay independent of the locale
    # JSON files.
    function Get-BaselineLocalizedString {
        param(
            [Parameter(Mandatory)][string]$Key,
            [Parameter(Mandatory)][AllowEmptyString()][string]$Fallback,
            [object[]]$FormatArgs = @()
        )
        if ($FormatArgs.Count -gt 0) { return ($Fallback -f $FormatArgs) }
        return $Fallback
    }

    # Toast helpers - load the real implementation so XML construction is
    # exercised end-to-end. The Send/Show paths are not invoked from
    # CleanupTask register/delete so WinRT is never hit.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Toast.Helpers.ps1')

    # bypassed and the function bodies execute in the test scope.
    $consumerPath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.MaintenanceTasks.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($consumerPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    # Re-declare the script-scope constants the module sets at top-level -
    $script:BaselineMaintenanceTaskPath = 'Baseline'
    $script:BaselineCleanupTaskName = 'Windows Cleanup'
    $script:BaselineCleanupNotificationTaskName = 'Windows Cleanup Notification'
    $script:BaselineCleanupAppId = 'Baseline'
    $script:BaselineCleanupProtocolName = 'BaselineCleanup'
    $script:BaselineSoftwareDistributionTaskName = 'SoftwareDistribution'
    $script:BaselineSoftwareDistributionScriptBase = 'SoftwareDistribution'
    $script:BaselineSoftwareDistributionDownloadPath = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    $script:BaselineTempTaskName = 'Temp'
    $script:BaselineTempScriptBase = 'Temp'
    $script:BaselineCleanupVolumeCaches = @(
        'BranchCache','Delivery Optimization Files','Device Driver Packages',
        'Language Pack','Previous Installations','Setup Log Files',
        'System error memory dump files','System error minidump files',
        'Temporary Files','Temporary Setup Files','Update Cleanup',
        'Upgrade Discarded Files','Windows Defender',
        'Windows ESD installation files','Windows Upgrade Log Files'
    )

    # Redirect the script-artifact directory into TestDrive so file writes
    # don't touch the real System32\Tasks\Baseline folder.
    $script:BaselineMaintenanceTaskScriptDir = Join-Path $TestDrive 'TasksBaseline'
}

Describe 'Get-BaselineCleanupTaskScript' {
    It 'emits a payload that runs cleanmgr /sagerun:1337 and DISM cleanup' {
        $payload = Get-BaselineCleanupTaskScript
        $payload | Should -Match 'cleanmgr\.exe'
        $payload | Should -Match '/sagerun:1337'
        $payload | Should -Match 'Dism\.exe'
        $payload | Should -Match '/StartComponentCleanup'
    }
}

Describe 'Get-BaselineCleanupNotificationTaskScript' {
    It 'embeds a ToastGeneric XML with the supplied title/body/protocol' {
        $payload = Get-BaselineCleanupNotificationTaskScript -Title 'Cleanup' -Body 'Run now?' -RunLabel 'Run'

        $payload | Should -Match 'ToastNotificationManager'
        $payload | Should -Match 'CreateToastNotifier\(''Baseline''\)'
        # The toast XML lives inside a here-string literal in the payload.
        $payload | Should -Match 'Cleanup'
        $payload | Should -Match 'Run now\?'
        $payload | Should -Match 'BaselineCleanup:'
    }

    It 'escapes single quotes in localized strings so the here-string stays valid' {
        $payload = Get-BaselineCleanupNotificationTaskScript -Title "Don't run" -Body 'B' -RunLabel 'Run'
        # Doubled single quote inside the here-string body is the escape form.
        $payload | Should -Match "Don''t run"
    }
}

Describe 'Set-BaselineCleanupVolumeCacheFlags' {
    BeforeEach {
        $script:registryWrites = [System.Collections.Generic.List[object]]::new()
        $script:registryRemoves = [System.Collections.Generic.List[object]]::new()
        $script:existingKeys = [System.Collections.Generic.HashSet[string]]::new()

        function Get-ChildItem {
            param([string]$Path, [string]$ErrorAction)
            return $script:BaselineCleanupVolumeCaches | ForEach-Object {
                [pscustomobject]@{ PsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\$_" }
            }
        }

        function Test-Path {
            param([string]$Path, [string]$LiteralPath)
            $candidate = if ($Path) { $Path } else { $LiteralPath }
            return $script:existingKeys.Contains($candidate)
        }

        function New-Item {
            param([string]$Path, [string]$ItemType, [switch]$Force)
            [void]$script:existingKeys.Add($Path)
            return [pscustomobject]@{ Path = $Path }
        }

        function New-ItemProperty {
            param([string]$Path, [string]$Name, [object]$Value, [string]$PropertyType, [switch]$Force)
            [void]$script:registryWrites.Add([pscustomobject]@{
                Path = $Path; Name = $Name; Value = $Value; PropertyType = $PropertyType
            })
            return [pscustomobject]@{ Path = $Path; Name = $Name }
        }

        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [string]$ErrorAction)
            [void]$script:registryRemoves.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($name in @('Get-ChildItem','Test-Path','New-Item','New-ItemProperty','Remove-ItemProperty')) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It 'writes StateFlags1337 = 2 across all 15 cleanup categories' {
        Set-BaselineCleanupVolumeCacheFlags

        $stateFlagsWrites = @($script:registryWrites | Where-Object { $_.Name -eq 'StateFlags1337' })
        $stateFlagsWrites.Count | Should -Be 15
        ($stateFlagsWrites | ForEach-Object { $_.Value } | Sort-Object -Unique) | Should -Be 2
    }

    It 'pre-clears any lingering StateFlags1337 before re-writing' {
        Set-BaselineCleanupVolumeCacheFlags
        # Removes happen first (one per discovered VolumeCaches child).
        $script:registryRemoves.Count | Should -BeGreaterOrEqual 15
        ($script:registryRemoves | Select-Object -First 1).Name | Should -Be 'StateFlags1337'
    }
}

Describe 'Clear-BaselineCleanupVolumeCacheFlags' {
    BeforeEach {
        $script:removeCalls = [System.Collections.Generic.List[object]]::new()

        function Get-ChildItem {
            param([string]$Path, [string]$ErrorAction)
            return @(
                [pscustomobject]@{ PsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\BranchCache' }
                [pscustomobject]@{ PsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Update Cleanup' }
            )
        }

        function Remove-ItemProperty {
            param([string]$Path, [string]$Name, [switch]$Force, [string]$ErrorAction)
            [void]$script:removeCalls.Add([pscustomobject]@{ Path = $Path; Name = $Name })
        }
    }

    AfterEach {
        foreach ($name in @('Get-ChildItem','Remove-ItemProperty')) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It 'removes StateFlags1337 from every VolumeCaches child' {
        Clear-BaselineCleanupVolumeCacheFlags
        $script:removeCalls.Count | Should -Be 2
        ($script:removeCalls | ForEach-Object { $_.Name } | Sort-Object -Unique) | Should -Be 'StateFlags1337'
    }
}

Describe 'New-BaselineMaintenanceTaskScripts' {
    It 'writes a UTF-8 BOM .ps1 and an ASCII .vbs shim under the script dir' {
        $result = New-BaselineMaintenanceTaskScripts -BaseName 'TestPair' -PowerShellContent "Write-Host 'hi'"

        Test-Path -LiteralPath $result.Ps1Path | Should -BeTrue
        Test-Path -LiteralPath $result.VbsPath | Should -BeTrue

        # PS1 should contain the supplied content.
        Get-Content -LiteralPath $result.Ps1Path -Raw | Should -Match "Write-Host 'hi'"

        # PS1 should be UTF-8 BOM (0xEF 0xBB 0xBF).
        $bytes = [System.IO.File]::ReadAllBytes($result.Ps1Path)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)

        # VBS should reference the matching .ps1 by name and use wscript-friendly syntax.
        $vbsContent = Get-Content -LiteralPath $result.VbsPath -Raw
        $vbsContent | Should -Match 'CreateObject\("Wscript\.Shell"\)\.Run'
        $vbsContent | Should -Match 'TestPair\.ps1'
        $vbsContent | Should -Match 'WindowStyle Hidden'
    }

    It 'creates the script directory if it does not yet exist' {
        $freshDir = Join-Path $TestDrive ('FreshTaskDir_' + [guid]::NewGuid().ToString('N'))
        $script:BaselineMaintenanceTaskScriptDir = $freshDir
        try {
            Test-Path -LiteralPath $freshDir | Should -BeFalse
            $null = New-BaselineMaintenanceTaskScripts -BaseName 'X' -PowerShellContent 'Y'
            Test-Path -LiteralPath $freshDir | Should -BeTrue
        }
        finally {
            $script:BaselineMaintenanceTaskScriptDir = Join-Path $TestDrive 'TasksBaseline'
        }
    }
}

Describe 'CleanupTask orchestration' {
    BeforeEach {
        $script:registerToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:registerScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()
        $script:maintenanceScripts = [System.Collections.Generic.List[object]]::new()
        $script:setVolumeFlagsCount = 0
        $script:clearVolumeFlagsCount = 0

        # Override the side-effecting helpers with recorders.
        function Register-BaselineToastApp {
            param([string]$AppId, [string]$DisplayName, [bool]$ShowInSettings, [string]$ProtocolName, [string]$ProtocolCommand)
            [void]$script:registerToastCalls.Add([pscustomobject]@{
                AppId = $AppId; DisplayName = $DisplayName; ProtocolName = $ProtocolName; ProtocolCommand = $ProtocolCommand
            })
        }

        function Unregister-BaselineToastApp {
            param([string]$AppId, [string]$ProtocolName)
            [void]$script:unregisterToastCalls.Add([pscustomobject]@{
                AppId = $AppId; ProtocolName = $ProtocolName
            })
        }

        function Set-BaselineCleanupVolumeCacheFlags { $script:setVolumeFlagsCount++ }
        function Clear-BaselineCleanupVolumeCacheFlags { $script:clearVolumeFlagsCount++ }

        function New-BaselineMaintenanceTaskScripts {
            param([string]$BaseName, [string]$PowerShellContent)
            [void]$script:maintenanceScripts.Add([pscustomobject]@{
                BaseName = $BaseName
                PowerShellContent = $PowerShellContent
            })
            return [pscustomobject]@{
                Ps1Path = Join-Path $TestDrive "$BaseName.ps1"
                VbsPath = Join-Path $TestDrive "$BaseName.vbs"
            }
        }

        function New-BaselineMaintenanceTaskPrincipal {
            return [pscustomobject]@{ UserId = 'TESTUSER'; RunLevel = 'Highest' }
        }

        function New-ScheduledTaskAction { param($Execute, $Argument) return [pscustomobject]@{ Execute = $Execute; Argument = $Argument } }
        function New-ScheduledTaskTrigger {
            param([switch]$Daily, [int]$DaysInterval, [datetime]$At)
            return [pscustomobject]@{ Daily = [bool]$Daily; DaysInterval = $DaysInterval; At = $At }
        }
        function New-ScheduledTaskSettingsSet { param([string]$Compatibility, [switch]$StartWhenAvailable) return [pscustomobject]@{ Compatibility = $Compatibility } }
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return $null }
        function Register-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [object]$Action, [object]$Trigger, [object]$Settings, [object]$Principal, [string]$Description, [switch]$Force)
            [void]$script:registerScheduledTaskCalls.Add([pscustomobject]@{
                TaskName = $TaskName; TaskPath = $TaskPath; Trigger = $Trigger; Description = $Description
            })
            return [pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath; Author = $null }
        }
        function Unregister-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [switch]$Confirm, [string]$ErrorAction)
            [void]$script:unregisterScheduledTaskCalls.Add([pscustomobject]@{
                TaskName = $TaskName; TaskPath = $TaskPath
            })
        }

        # When CleanupTask -Delete probes for the existing tasks, return a
        # truthy stub so the unregister path runs.
        function Get-ScheduledTaskForDelete {
            param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction)
            return [pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath }
        }
    }

    AfterEach {
        foreach ($name in @(
            'Register-BaselineToastApp','Unregister-BaselineToastApp',
            'Set-BaselineCleanupVolumeCacheFlags','Clear-BaselineCleanupVolumeCacheFlags',
            'New-BaselineMaintenanceTaskScripts','New-BaselineMaintenanceTaskPrincipal',
            'New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskSettingsSet',
            'Get-ScheduledTask','Register-ScheduledTask','Unregister-ScheduledTask'
        )) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It '-Register: configures volume caches, registers AppId+protocol, registers two tasks' {
        CleanupTask -Register

        $script:setVolumeFlagsCount | Should -Be 1

        $script:registerToastCalls.Count | Should -Be 1
        $script:registerToastCalls[0].AppId | Should -Be 'Baseline'
        $script:registerToastCalls[0].ProtocolName | Should -Be 'BaselineCleanup'
        $script:registerToastCalls[0].ProtocolCommand | Should -Match '-File'
        $script:registerToastCalls[0].ProtocolCommand | Should -Match 'Windows_Cleanup_Protocol\.ps1'
        $protocolScript = $script:maintenanceScripts | Where-Object BaseName -eq 'Windows_Cleanup_Protocol'
        $protocolScript.PowerShellContent | Should -Match 'Start-ScheduledTask'
        $protocolScript.PowerShellContent | Should -BeLike "*'\Baseline\'*"
        $protocolScript.PowerShellContent | Should -BeLike "*'Windows Cleanup'*"

        $script:registerScheduledTaskCalls.Count | Should -Be 2
        $cleanupCall = $script:registerScheduledTaskCalls | Where-Object TaskName -eq 'Windows Cleanup'
        $reminderCall = $script:registerScheduledTaskCalls | Where-Object TaskName -eq 'Windows Cleanup Notification'
        $cleanupCall | Should -Not -BeNullOrEmpty
        $reminderCall | Should -Not -BeNullOrEmpty

        # Cleanup task is on-demand (no trigger); reminder is the 30-day daily.
        $cleanupCall.Trigger | Should -BeNullOrEmpty
        $reminderCall.Trigger.Daily | Should -BeTrue
        $reminderCall.Trigger.DaysInterval | Should -Be 30

        # Descriptions should have the username substituted from the locale template.
        $cleanupCall.Description | Should -Match $env:USERNAME
        $reminderCall.Description | Should -Match $env:USERNAME
    }

    It '-Delete: unregisters both tasks, removes AppId+protocol, clears flags, removes script files' {
        # Pretend both tasks exist so the unregister path fires.
        Set-Item -Path Function:\Get-ScheduledTask -Value (Get-Item Function:\Get-ScheduledTaskForDelete).ScriptBlock
        # Simulate "no Baseline tasks remain after deletion" so the AppId
        # cleanup branch fires.
        function Test-BaselineMaintenanceTasksRemaining { return $false }

        # Drop sentinel script files into the redirected dir so we can prove they get removed.
        New-Item -ItemType Directory -Path $script:BaselineMaintenanceTaskScriptDir -Force | Out-Null
        foreach ($base in @('Windows_Cleanup','Windows_Cleanup_Notification')) {
            foreach ($ext in @('.ps1','.vbs')) {
                Set-Content -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "$base$ext") -Value 'sentinel' -Encoding UTF8
            }
        }

        try {
            CleanupTask -Delete

            $script:unregisterScheduledTaskCalls.Count | Should -Be 2
            ($script:unregisterScheduledTaskCalls | ForEach-Object { $_.TaskName } | Sort-Object) | Should -Be @('Windows Cleanup','Windows Cleanup Notification')

            $script:unregisterToastCalls.Count | Should -Be 1
            $script:unregisterToastCalls[0].AppId | Should -Be 'Baseline'
            $script:unregisterToastCalls[0].ProtocolName | Should -Be 'BaselineCleanup'

            $script:clearVolumeFlagsCount | Should -Be 1

            # All four script files should now be gone.
            foreach ($base in @('Windows_Cleanup','Windows_Cleanup_Notification')) {
                foreach ($ext in @('.ps1','.vbs')) {
                    Test-Path -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "$base$ext") | Should -BeFalse
                }
            }
        }
        finally {
            Remove-Item -Path Function:\Test-BaselineMaintenanceTasksRemaining -ErrorAction SilentlyContinue
        }
    }

    It '-Delete: keeps the AppId in place when other Baseline tasks remain, but still drops the protocol' {
        Set-Item -Path Function:\Get-ScheduledTask -Value (Get-Item Function:\Get-ScheduledTaskForDelete).ScriptBlock
        # Simulate SoftwareDistribution still being registered.
        function Test-BaselineMaintenanceTasksRemaining { return $true }

        $script:protocolRemovals = [System.Collections.Generic.List[string]]::new()
        function Test-Path { param([string]$Path, [string]$LiteralPath); return $true }
        function Remove-Item {
            param([string]$Path, [string]$LiteralPath, [switch]$Recurse, [switch]$Force, [string]$ErrorAction)
            $candidate = if ($Path) { $Path } else { $LiteralPath }
            [void]$script:protocolRemovals.Add($candidate)
        }

        try {
            CleanupTask -Delete

            # Toast AppId helper should NOT be called - protocol got swept inline.
            $script:unregisterToastCalls.Count | Should -Be 0
            # The protocol HKCR key must have been removed directly.
            ($script:protocolRemovals | Where-Object { $_ -like '*HKEY_CLASSES_ROOT\BaselineCleanup*' }).Count | Should -BeGreaterOrEqual 1
        }
        finally {
            foreach ($name in @('Test-BaselineMaintenanceTasksRemaining','Test-Path','Remove-Item')) {
                Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-BaselineSoftwareDistributionTaskScript' {
    It 'embeds the wuauserv wait, cache flush, and an information-only toast' {
        $payload = Get-BaselineSoftwareDistributionTaskScript -Body 'Update cache cleared.'

        # Service-stop guard.
        $payload | Should -Match "Get-Service -Name wuauserv"
        $payload | Should -Match "WaitForStatus\('Stopped', '01:00:00'\)"

        # Cache flush targets the right path.
        $expectedDownloadPath = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
        $payload | Should -BeLike "*$expectedDownloadPath*"
        $payload | Should -Match 'Remove-Item -Recurse -Force'

        # Information-only toast: no actions element, no protocol arguments.
        $payload | Should -Not -Match 'activationType=\"protocol\"'
        $payload | Should -Match 'Update cache cleared\.'
        $payload | Should -Match "CreateToastNotifier\('Baseline'\)"
    }

    It 'escapes single quotes inside the toast body so the here-string stays valid' {
        $payload = Get-BaselineSoftwareDistributionTaskScript -Body "Don't worry, cache cleared"
        $payload | Should -Match "Don''t worry"
    }
}

Describe 'Test-BaselineMaintenanceTasksRemaining' {
    AfterEach {
        Remove-Item -Path Function:\Get-ScheduledTask -ErrorAction SilentlyContinue
    }

    It 'returns $true when Get-ScheduledTask yields any task in \Baseline\' {
        function Get-ScheduledTask {
            param([string]$TaskPath, [string]$TaskName, [string]$ErrorAction)
            return [pscustomobject]@{ TaskName = 'SoftwareDistribution'; TaskPath = $TaskPath }
        }
        Test-BaselineMaintenanceTasksRemaining | Should -BeTrue
    }

    It 'returns $false when Get-ScheduledTask yields nothing' {
        function Get-ScheduledTask { param([string]$TaskPath, [string]$TaskName, [string]$ErrorAction); return $null }
        Test-BaselineMaintenanceTasksRemaining | Should -BeFalse
    }
}

Describe 'SoftwareDistributionTask orchestration' {
    BeforeEach {
        $script:registerToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:registerScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()

        function Register-BaselineToastApp {
            param([string]$AppId, [string]$DisplayName, [bool]$ShowInSettings, [string]$ProtocolName, [string]$ProtocolCommand)
            [void]$script:registerToastCalls.Add([pscustomobject]@{
                AppId = $AppId; DisplayName = $DisplayName; ProtocolName = $ProtocolName; ProtocolCommand = $ProtocolCommand
            })
        }

        function Unregister-BaselineToastApp {
            param([string]$AppId, [string]$ProtocolName)
            [void]$script:unregisterToastCalls.Add([pscustomobject]@{ AppId = $AppId; ProtocolName = $ProtocolName })
        }

        function New-BaselineMaintenanceTaskScripts {
            param([string]$BaseName, [string]$PowerShellContent)
            return [pscustomobject]@{
                Ps1Path = Join-Path $TestDrive "$BaseName.ps1"
                VbsPath = Join-Path $TestDrive "$BaseName.vbs"
            }
        }

        function New-BaselineMaintenanceTaskPrincipal {
            return [pscustomobject]@{ UserId = 'TESTUSER'; RunLevel = 'Highest' }
        }

        function New-ScheduledTaskTrigger {
            param([switch]$Daily, [int]$DaysInterval, [datetime]$At)
            return [pscustomobject]@{ Daily = [bool]$Daily; DaysInterval = $DaysInterval; At = $At }
        }

        function Register-BaselineMaintenanceTask {
            param([string]$TaskName, [string]$VbsPath, [object]$Trigger, [object]$Principal, [string]$Description)
            [void]$script:registerScheduledTaskCalls.Add([pscustomobject]@{
                TaskName = $TaskName; VbsPath = $VbsPath; Trigger = $Trigger; Description = $Description
            })
        }

        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return $null }
        function Unregister-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [switch]$Confirm, [string]$ErrorAction)
            [void]$script:unregisterScheduledTaskCalls.Add([pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath })
        }
    }

    AfterEach {
        foreach ($name in @(
            'Register-BaselineToastApp','Unregister-BaselineToastApp',
            'New-BaselineMaintenanceTaskScripts','New-BaselineMaintenanceTaskPrincipal',
            'New-ScheduledTaskTrigger','Register-BaselineMaintenanceTask',
            'Get-ScheduledTask','Unregister-ScheduledTask',
            'Test-BaselineMaintenanceTasksRemaining'
        )) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It '-Register: registers AppId without a protocol and schedules a 90-day daily trigger' {
        SoftwareDistributionTask -Register

        $script:registerToastCalls.Count | Should -Be 1
        $script:registerToastCalls[0].AppId | Should -Be 'Baseline'
        # Information-only toast: no URL protocol handler.
        [string]::IsNullOrEmpty($script:registerToastCalls[0].ProtocolName) | Should -BeTrue
        [string]::IsNullOrEmpty($script:registerToastCalls[0].ProtocolCommand) | Should -BeTrue

        $script:registerScheduledTaskCalls.Count | Should -Be 1
        $call = $script:registerScheduledTaskCalls[0]
        $call.TaskName | Should -Be 'SoftwareDistribution'
        $call.Trigger.Daily | Should -BeTrue
        $call.Trigger.DaysInterval | Should -Be 90
        # Description should mention the cache path AND the username.
        $call.Description | Should -BeLike '*SoftwareDistribution\Download*'
        $call.Description | Should -Match $env:USERNAME
    }

    It '-Delete (no other tasks): unregisters task, removes files, and releases the AppId' {
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return [pscustomobject]@{ TaskName = $TaskName } }
        function Test-BaselineMaintenanceTasksRemaining { return $false }

        New-Item -ItemType Directory -Path $script:BaselineMaintenanceTaskScriptDir -Force | Out-Null
        foreach ($ext in @('.ps1','.vbs')) {
            Set-Content -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "SoftwareDistribution$ext") -Value 'sentinel' -Encoding UTF8
        }

        SoftwareDistributionTask -Delete

        $script:unregisterScheduledTaskCalls.Count | Should -Be 1
        $script:unregisterScheduledTaskCalls[0].TaskName | Should -Be 'SoftwareDistribution'

        $script:unregisterToastCalls.Count | Should -Be 1
        $script:unregisterToastCalls[0].AppId | Should -Be 'Baseline'

        foreach ($ext in @('.ps1','.vbs')) {
            Test-Path -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "SoftwareDistribution$ext") | Should -BeFalse
        }
    }

    It '-Delete (cleanup task still present): unregisters task and files but leaves AppId alone' {
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return [pscustomobject]@{ TaskName = $TaskName } }
        function Test-BaselineMaintenanceTasksRemaining { return $true }

        SoftwareDistributionTask -Delete

        $script:unregisterScheduledTaskCalls.Count | Should -Be 1
        $script:unregisterToastCalls.Count | Should -Be 0
    }
}

Describe 'Get-BaselineTempTaskScript' {
    It 'sweeps %TEMP% files older than 1 day and the orphan-folder list' {
        $payload = Get-BaselineTempTaskScript -Body 'Temp cleared.'

        # %TEMP% age filter.
        $payload | Should -Match 'Get-ChildItem -Path \$env:TEMP'
        $payload | Should -Match 'CreationTime -lt \(Get-Date\)\.AddDays\(-1\)'

        # Orphan-folder list - the literal $WinREAgent / $SysReset / etc. names
        # must survive the outer here-string as plain strings.
        foreach ($literal in @('$WinREAgent','$SysReset','$Windows.~WS','$GetCurrent','ESD','Intel','PerfLogs')) {
            $payload | Should -BeLike "*$literal*"
        }

        # NetworkService temp folder.
        $payload | Should -Match 'ServiceProfiles\\NetworkService\\AppData\\Local\\Temp'

        # ReAgentOld.xml gating for the Recovery folder.
        $payload | Should -Match 'ReAgentOld\.xml'

        # Information-only completion toast - no actions, body wired in.
        $payload | Should -Not -Match 'activationType=\"protocol\"'
        $payload | Should -Match 'Temp cleared\.'
        $payload | Should -Match "CreateToastNotifier\('Baseline'\)"
    }

    It 'produces a payload that parses as valid PowerShell' {
        $payload = Get-BaselineTempTaskScript -Body 'B'
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($payload, [ref]$null, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }
}

Describe 'TempTask orchestration' {
    BeforeEach {
        $script:registerToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterToastCalls = [System.Collections.Generic.List[object]]::new()
        $script:registerScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterScheduledTaskCalls = [System.Collections.Generic.List[object]]::new()

        function Register-BaselineToastApp {
            param([string]$AppId, [string]$DisplayName, [bool]$ShowInSettings, [string]$ProtocolName, [string]$ProtocolCommand)
            [void]$script:registerToastCalls.Add([pscustomobject]@{
                AppId = $AppId; DisplayName = $DisplayName; ProtocolName = $ProtocolName; ProtocolCommand = $ProtocolCommand
            })
        }
        function Unregister-BaselineToastApp {
            param([string]$AppId, [string]$ProtocolName)
            [void]$script:unregisterToastCalls.Add([pscustomobject]@{ AppId = $AppId; ProtocolName = $ProtocolName })
        }
        function New-BaselineMaintenanceTaskScripts {
            param([string]$BaseName, [string]$PowerShellContent)
            return [pscustomobject]@{
                Ps1Path = Join-Path $TestDrive "$BaseName.ps1"
                VbsPath = Join-Path $TestDrive "$BaseName.vbs"
            }
        }
        function New-BaselineMaintenanceTaskPrincipal { return [pscustomobject]@{ UserId = 'TESTUSER'; RunLevel = 'Highest' } }
        function New-ScheduledTaskTrigger {
            param([switch]$Daily, [int]$DaysInterval, [datetime]$At)
            return [pscustomobject]@{ Daily = [bool]$Daily; DaysInterval = $DaysInterval; At = $At }
        }
        function Register-BaselineMaintenanceTask {
            param([string]$TaskName, [string]$VbsPath, [object]$Trigger, [object]$Principal, [string]$Description)
            [void]$script:registerScheduledTaskCalls.Add([pscustomobject]@{
                TaskName = $TaskName; VbsPath = $VbsPath; Trigger = $Trigger; Description = $Description
            })
        }
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return $null }
        function Unregister-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [switch]$Confirm, [string]$ErrorAction)
            [void]$script:unregisterScheduledTaskCalls.Add([pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath })
        }
    }

    AfterEach {
        foreach ($name in @(
            'Register-BaselineToastApp','Unregister-BaselineToastApp',
            'New-BaselineMaintenanceTaskScripts','New-BaselineMaintenanceTaskPrincipal',
            'New-ScheduledTaskTrigger','Register-BaselineMaintenanceTask',
            'Get-ScheduledTask','Unregister-ScheduledTask',
            'Test-BaselineMaintenanceTasksRemaining'
        )) {
            Remove-Item -Path "Function:\$name" -ErrorAction SilentlyContinue
        }
    }

    It '-Register: registers AppId without protocol and schedules a 60-day daily trigger' {
        TempTask -Register

        $script:registerToastCalls.Count | Should -Be 1
        $script:registerToastCalls[0].AppId | Should -Be 'Baseline'
        [string]::IsNullOrEmpty($script:registerToastCalls[0].ProtocolName) | Should -BeTrue

        $script:registerScheduledTaskCalls.Count | Should -Be 1
        $call = $script:registerScheduledTaskCalls[0]
        $call.TaskName | Should -Be 'Temp'
        $call.Trigger.Daily | Should -BeTrue
        $call.Trigger.DaysInterval | Should -Be 60
        $call.Description | Should -BeLike '*%TEMP%*'
        $call.Description | Should -Match $env:USERNAME
    }

    It '-Delete (no other tasks): unregisters task, removes files, releases the AppId' {
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return [pscustomobject]@{ TaskName = $TaskName } }
        function Test-BaselineMaintenanceTasksRemaining { return $false }

        New-Item -ItemType Directory -Path $script:BaselineMaintenanceTaskScriptDir -Force | Out-Null
        foreach ($ext in @('.ps1','.vbs')) {
            Set-Content -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "Temp$ext") -Value 'sentinel' -Encoding UTF8
        }

        TempTask -Delete

        $script:unregisterScheduledTaskCalls.Count | Should -Be 1
        $script:unregisterScheduledTaskCalls[0].TaskName | Should -Be 'Temp'

        $script:unregisterToastCalls.Count | Should -Be 1
        $script:unregisterToastCalls[0].AppId | Should -Be 'Baseline'

        foreach ($ext in @('.ps1','.vbs')) {
            Test-Path -LiteralPath (Join-Path $script:BaselineMaintenanceTaskScriptDir "Temp$ext") | Should -BeFalse
        }
    }

    It '-Delete (other Baseline tasks remain): leaves the AppId in place' {
        function Get-ScheduledTask { param([string]$TaskName, [string]$TaskPath, [string]$ErrorAction) return [pscustomobject]@{ TaskName = $TaskName } }
        function Test-BaselineMaintenanceTasksRemaining { return $true }

        TempTask -Delete

        $script:unregisterScheduledTaskCalls.Count | Should -Be 1
        $script:unregisterToastCalls.Count | Should -Be 0
    }
}

Describe 'Get-BaselineTempPurgePaths' {
    It 'returns the orphan-folder list anchored to the system drive and root' {
        $paths = Get-BaselineTempPurgePaths
        $paths.Count | Should -Be 8
        ($paths | Where-Object { $_ -like '*$WinREAgent*' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*$SysReset*' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*$Windows.~WS*' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*$GetCurrent*' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*\ESD' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*\Intel' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*\PerfLogs' }).Count | Should -Be 1
        ($paths | Where-Object { $_ -like '*ServiceProfiles\NetworkService\AppData\Local\Temp' }).Count | Should -Be 1
    }
}

Describe 'Invoke-BaselineSoftwareDistributionFlush' {
    BeforeEach {
        # Redirect the download path into TestDrive so we never touch the
        # real %SystemRoot%\SoftwareDistribution\Download.
        $script:downloadDir = Join-Path $TestDrive 'SDDownload'
        $script:BaselineSoftwareDistributionDownloadPath = $script:downloadDir
    }

    AfterEach {
        Remove-Item -Path Function:\Get-Service -ErrorAction SilentlyContinue
    }

    It 'returns SkippedReason when wuauserv is busy and does not touch the cache' {
        New-Item -ItemType Directory -Path $script:downloadDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:downloadDir 'cab.cab') -Value 'x'

        function Get-Service {
            param([string]$Name, [string]$ErrorAction)
            $svc = [pscustomobject]@{ Status = 'Running' }
            $svc | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
                param($status, $timeout); throw [System.ServiceProcess.TimeoutException]::new('busy')
            }
            return $svc
        }

        $result = Invoke-BaselineSoftwareDistributionFlush -WuauservStopWaitSeconds 1
        $result.Cleared | Should -BeFalse
        $result.SkippedReason | Should -Match 'busy'
        # File should still exist.
        Test-Path -LiteralPath (Join-Path $script:downloadDir 'cab.cab') | Should -BeTrue
    }

    It 'clears the download cache and reports BytesFreed when wuauserv is stopped' {
        New-Item -ItemType Directory -Path $script:downloadDir -Force | Out-Null
        $payload = 'x' * 4096
        Set-Content -LiteralPath (Join-Path $script:downloadDir 'cab.cab') -Value $payload

        function Get-Service {
            param([string]$Name, [string]$ErrorAction)
            return [pscustomobject]@{ Status = 'Stopped' }
        }

        $result = Invoke-BaselineSoftwareDistributionFlush
        $result.Cleared | Should -BeTrue
        $result.BytesFreed | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $script:downloadDir 'cab.cab') | Should -BeFalse
    }

    It 'is a no-op (Cleared=true, BytesFreed=0) when the download dir does not exist' {
        function Get-Service {
            param([string]$Name, [string]$ErrorAction)
            return [pscustomobject]@{ Status = 'Stopped' }
        }

        $result = Invoke-BaselineSoftwareDistributionFlush
        $result.Cleared | Should -BeTrue
        $result.BytesFreed | Should -Be 0
    }
}

Describe 'Invoke-BaselineTempFolderPurge' {
    BeforeEach {
        $script:tempDir = Join-Path $TestDrive 'TempPurge'
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        $env:TEMP_ORIGINAL = $env:TEMP
        $env:TEMP = $script:tempDir
    }

    AfterEach {
        $env:TEMP = $env:TEMP_ORIGINAL
        Remove-Item -Path Env:TEMP_ORIGINAL -ErrorAction SilentlyContinue
        # Don't touch real orphan paths - the helper only walks paths that exist
        # under TestDrive, so nothing to clean up.
    }

    It 'sweeps %TEMP% files older than the cutoff and leaves recent files alone' {
        $oldFile = Join-Path $script:tempDir 'old.tmp'
        $newFile = Join-Path $script:tempDir 'new.tmp'
        Set-Content -LiteralPath $oldFile -Value 'old'
        Set-Content -LiteralPath $newFile -Value 'new'
        # Backdate creation time on the "old" file by 5 days.
        (Get-Item -LiteralPath $oldFile).CreationTime = (Get-Date).AddDays(-5)

        $result = Invoke-BaselineTempFolderPurge -MinAgeDays 1

        Test-Path -LiteralPath $oldFile | Should -BeFalse
        Test-Path -LiteralPath $newFile | Should -BeTrue
        $result.PathsCleared | Should -BeGreaterOrEqual 1
    }

    It 'tolerates a missing %TEMP% directory' {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        { Invoke-BaselineTempFolderPurge -MinAgeDays 1 } | Should -Not -Throw
    }
}
