Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Scheduler.Helpers.ps1'
    . $filePath
}

Describe 'Register-BaselineScheduledTask' {
    BeforeEach {
        $script:SharedHelpersRepoRoot = Join-Path $TestDrive 'RepoRoot'
        $bootstrapDir = Join-Path $script:SharedHelpersRepoRoot 'Bootstrap'
        $moduleDir = Join-Path $script:SharedHelpersRepoRoot 'Module'
        New-Item -ItemType Directory -Path $bootstrapDir -Force | Out-Null
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $bootstrapDir 'Baseline.ps1') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $moduleDir 'SharedHelpers.psm1') -Force | Out-Null

        $script:profilePath = Join-Path $TestDrive 'profile.json'
        Set-Content -LiteralPath $script:profilePath -Value '{}' -Encoding UTF8

        $script:originalProgramData = $env:ProgramData
        $env:ProgramData = $TestDrive
        $script:principalCalls = [System.Collections.Generic.List[object]]::new()
        $script:registerCalls = [System.Collections.Generic.List[object]]::new()

        function New-ScheduledTaskAction {
            param([string]$Execute, [string]$Argument)
            return [pscustomobject]@{ Execute = $Execute; Argument = $Argument }
        }

        function New-ScheduledTaskTrigger {
            param(
                [switch]$Once,
                [switch]$Daily,
                [switch]$Weekly,
                [datetime]$At,
                [timespan]$RepetitionInterval,
                [timespan]$RepetitionDuration,
                [string]$DaysOfWeek
            )
            return [pscustomobject]@{
                Once = [bool]$Once
                Daily = [bool]$Daily
                Weekly = [bool]$Weekly
                At = $At
                DaysOfWeek = $DaysOfWeek
            }
        }

        function New-ScheduledTaskSettingsSet {
            param(
                [switch]$AllowStartIfOnBatteries,
                [switch]$DontStopIfGoingOnBatteries,
                [switch]$StartWhenAvailable
            )
            return [pscustomobject]@{
                AllowStartIfOnBatteries = [bool]$AllowStartIfOnBatteries
                DontStopIfGoingOnBatteries = [bool]$DontStopIfGoingOnBatteries
                StartWhenAvailable = [bool]$StartWhenAvailable
            }
        }

        function New-ScheduledTaskPrincipal {
            param([string]$UserId, [string]$RunLevel, [string]$LogonType)
            $principal = [pscustomobject]@{
                UserId = $UserId
                RunLevel = $RunLevel
                LogonType = $LogonType
            }
            [void]$script:principalCalls.Add($principal)
            return $principal
        }

        function Get-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath)
            return $null
        }

        function Register-ScheduledTask {
            param(
                [string]$TaskName,
                [string]$TaskPath,
                [object]$Action,
                [object]$Trigger,
                [object]$Settings,
                [object]$Principal,
                [string]$Description
            )
            [void]$script:registerCalls.Add([pscustomobject]@{
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
        $env:ProgramData = $script:originalProgramData
        foreach ($name in @(
                'New-ScheduledTaskAction',
                'New-ScheduledTaskTrigger',
                'New-ScheduledTaskSettingsSet',
                'New-ScheduledTaskPrincipal',
                'Get-ScheduledTask',
                'Register-ScheduledTask'
            )) {
            Remove-Item -Path ("Function:\{0}" -f $name) -ErrorAction SilentlyContinue
        }
    }

    It 'registers Baseline scheduled tasks with a SYSTEM service principal' {
        Register-BaselineScheduledTask -TaskName 'Audit' -ProfilePath $script:profilePath -Schedule Daily -Time '03:30'

        $script:principalCalls.Count | Should -Be 1
        $script:principalCalls[0].UserId | Should -Be 'NT AUTHORITY\SYSTEM'
        $script:principalCalls[0].RunLevel | Should -Be 'Highest'
        $script:principalCalls[0].LogonType | Should -Be 'ServiceAccount'
        $script:registerCalls.Count | Should -Be 1
        $script:registerCalls[0].TaskPath | Should -Be '\Baseline\'
        $script:registerCalls[0].Principal | Should -Be $script:principalCalls[0]
    }

    It 'registers Windows Update security install runs through SharedHelpers under SYSTEM' {
        Register-BaselineWindowsUpdateScheduledRun -Schedule Daily -Time '02:15'

        $script:principalCalls.Count | Should -Be 1
        $script:principalCalls[0].UserId | Should -Be 'NT AUTHORITY\SYSTEM'
        $script:principalCalls[0].RunLevel | Should -Be 'Highest'
        $script:principalCalls[0].LogonType | Should -Be 'ServiceAccount'
        $script:registerCalls.Count | Should -Be 1
        $script:registerCalls[0].TaskName | Should -Be 'WindowsSecurityUpdates'
        $script:registerCalls[0].TaskPath | Should -Be '\Baseline\'
        $script:registerCalls[0].Action.Execute | Should -Be 'powershell.exe'
        $script:registerCalls[0].Action.Argument | Should -Match '-NoProfile'
        $script:registerCalls[0].Action.Argument | Should -Match '-NonInteractive'
        $script:registerCalls[0].Action.Argument | Should -Match '-File'

        $scriptPath = $script:registerCalls[0].Action.Argument -replace '^.*-File\s+"([^"]+)".*$', '$1'
        $scriptContent = Get-BaselineTestSourceText -Path $scriptPath
        $scriptContent | Should -Match 'SharedHelpers\.psm1'
        $scriptContent | Should -Match 'Invoke-BaselineWindowsUpdateScheduledRun'
        $script:registerCalls[0].Principal | Should -Be $script:principalCalls[0]
    }
}
