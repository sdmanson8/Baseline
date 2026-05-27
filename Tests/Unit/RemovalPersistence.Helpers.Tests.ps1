Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemovalPersistence.Helpers.ps1'
    . $filePath
}

Describe 'Get-BaselineRemovalScriptDirectory' {
    BeforeEach {
        Remove-Item -LiteralPath Env:BASELINE_REMOVAL_SCRIPT_DIR -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_REMOVAL_SCRIPT_DIR -ErrorAction SilentlyContinue
    }

    It 'returns the override path when BASELINE_REMOVAL_SCRIPT_DIR is set' {
        $env:BASELINE_REMOVAL_SCRIPT_DIR = 'C:\Sandbox\BaselineRemoval'
        Get-BaselineRemovalScriptDirectory | Should -Be 'C:\Sandbox\BaselineRemoval'
    }

    It 'falls through to ProgramData\Baseline\RemovalScripts when no override is set' {
        $env:ProgramData = 'C:\TestProgramData'
        Get-BaselineRemovalScriptDirectory | Should -Be 'C:\TestProgramData\Baseline\RemovalScripts'
    }

    It 'falls back to C:\ProgramData if ProgramData env var is empty' {
        $originalProgramData = $env:ProgramData
        try {
            $env:ProgramData = ''
            Get-BaselineRemovalScriptDirectory | Should -Be 'C:\ProgramData\Baseline\RemovalScripts'
        }
        finally {
            $env:ProgramData = $originalProgramData
        }
    }
}

Describe 'Test-BaselineRemovalPersistenceEntryName' {
    It 'accepts plain ASCII names' {
        Test-BaselineRemovalPersistenceEntryName -Name 'BloatRemoval' | Should -BeTrue
        Test-BaselineRemovalPersistenceEntryName -Name 'Edge_Removal' | Should -BeTrue
        Test-BaselineRemovalPersistenceEntryName -Name 'OneDrive-Removal' | Should -BeTrue
        Test-BaselineRemovalPersistenceEntryName -Name 'apps.v2' | Should -BeTrue
    }

    It 'rejects empty / whitespace names' {
        Test-BaselineRemovalPersistenceEntryName -Name '' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name '   ' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name $null | Should -BeFalse
    }

    It 'rejects names containing path separators' {
        Test-BaselineRemovalPersistenceEntryName -Name 'foo\bar' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name 'foo/bar' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name '..\evil' | Should -BeFalse
    }

    It 'rejects names containing reserved task-scheduler characters' {
        Test-BaselineRemovalPersistenceEntryName -Name 'foo:bar' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name 'foo*bar' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name 'foo bar' | Should -BeFalse
        Test-BaselineRemovalPersistenceEntryName -Name 'foo;bar' | Should -BeFalse
    }

    It 'rejects names longer than 64 characters' {
        $longName = 'a' * 65
        Test-BaselineRemovalPersistenceEntryName -Name $longName | Should -BeFalse
    }

    It 'accepts names of exactly 64 characters' {
        $boundary = 'a' * 64
        Test-BaselineRemovalPersistenceEntryName -Name $boundary | Should -BeTrue
    }
}

Describe 'Save-BaselineRemovalScript' {
    BeforeEach {
        $script:sandboxRoot = Join-Path $TestDrive 'RemovalScripts'
        $env:BASELINE_REMOVAL_SCRIPT_DIR = $script:sandboxRoot
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_REMOVAL_SCRIPT_DIR -ErrorAction SilentlyContinue
    }

    It 'creates the parent directory and writes the script content' {
        $body = "Get-AppxPackage *Microsoft.MicrosoftSolitaireCollection* | Remove-AppxPackage"
        $resultPath = Save-BaselineRemovalScript -Name 'BloatRemoval' -ScriptBody $body

        $resultPath | Should -Be (Join-Path $script:sandboxRoot 'BloatRemoval.ps1')
        Test-Path -LiteralPath $resultPath | Should -BeTrue

        $written = [System.IO.File]::ReadAllText($resultPath)
        $written | Should -Match 'Get-AppxPackage \*Microsoft\.MicrosoftSolitaireCollection\*'
        $written | Should -Match '# Generated:'
        $written | Should -Match '# Entry name: BloatRemoval'
    }

    It 'includes the description in the header when provided' {
        $resultPath = Save-BaselineRemovalScript -Name 'EdgeRemoval' -ScriptBody '# noop' -Description 'Edge re-install nuke from feature update'
        $written = [System.IO.File]::ReadAllText($resultPath)
        $written | Should -Match '# Description: Edge re-install nuke from feature update'
    }

    It 'overwrites an existing script with the same name' {
        Save-BaselineRemovalScript -Name 'BloatRemoval' -ScriptBody '# v1' | Out-Null
        $secondPath = Save-BaselineRemovalScript -Name 'BloatRemoval' -ScriptBody '# v2'
        $written = [System.IO.File]::ReadAllText($secondPath)
        $written | Should -Match '# v2'
        $written | Should -Not -Match '# v1'
    }

    It 'writes UTF-8 with BOM' {
        $resultPath = Save-BaselineRemovalScript -Name 'BomTest' -ScriptBody '# nothing'
        $bytes = [System.IO.File]::ReadAllBytes($resultPath)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }

    It 'rejects invalid entry names' {
        { Save-BaselineRemovalScript -Name 'foo\bar' -ScriptBody '# noop' } | Should -Throw -ExpectedMessage '*Invalid removal persistence entry name*'
    }

    It 'honours -WhatIf and writes nothing to disk' {
        $resultPath = Save-BaselineRemovalScript -Name 'WhatIfTest' -ScriptBody '# noop' -WhatIf
        $resultPath | Should -Be (Join-Path $script:sandboxRoot 'WhatIfTest.ps1')
        Test-Path -LiteralPath $resultPath | Should -BeFalse
    }
}

Describe 'Register-BaselineRemovalPersistenceTask' {
    BeforeEach {
        $script:registerCalls = [System.Collections.Generic.List[object]]::new()
        $script:triggerCalls = [System.Collections.Generic.List[object]]::new()
        $script:principalCalls = [System.Collections.Generic.List[object]]::new()
        $script:settingsCalls = [System.Collections.Generic.List[object]]::new()
        $script:unregisterCalls = [System.Collections.Generic.List[object]]::new()
        $script:existingTask = $null

        function New-ScheduledTaskAction {
            param([string]$Execute, [string]$Argument)
            return [pscustomobject]@{ Execute = $Execute; Argument = $Argument }
        }

        function New-ScheduledTaskTrigger {
            param([switch]$AtLogon, [switch]$AtStartup)
            $obj = [pscustomobject]@{ AtLogon = [bool]$AtLogon; AtStartup = [bool]$AtStartup }
            [void]$script:triggerCalls.Add($obj)
            return $obj
        }

        function New-ScheduledTaskPrincipal {
            param([string]$UserId, [string]$LogonType, [string]$RunLevel)
            $obj = [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = $RunLevel }
            [void]$script:principalCalls.Add($obj)
            return $obj
        }

        function New-ScheduledTaskSettingsSet {
            param(
                [switch]$AllowStartIfOnBatteries,
                [switch]$DontStopIfGoingOnBatteries,
                [switch]$StartWhenAvailable,
                [timespan]$ExecutionTimeLimit
            )
            $obj = [pscustomobject]@{
                AllowStartIfOnBatteries    = [bool]$AllowStartIfOnBatteries
                DontStopIfGoingOnBatteries = [bool]$DontStopIfGoingOnBatteries
                StartWhenAvailable         = [bool]$StartWhenAvailable
                ExecutionTimeLimit         = $ExecutionTimeLimit
            }
            [void]$script:settingsCalls.Add($obj)
            return $obj
        }

        function Get-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath)
            return $script:existingTask
        }

        function Unregister-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [switch]$Confirm)
            [void]$script:unregisterCalls.Add([pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath })
        }

        function Register-ScheduledTask {
            param(
                [string]$TaskName,
                [string]$TaskPath,
                [object]$Action,
                [object]$Trigger,
                [object]$Principal,
                [object]$Settings,
                [string]$Description
            )
            $obj = [pscustomobject]@{
                TaskName    = $TaskName
                TaskPath    = $TaskPath
                Action      = $Action
                Trigger     = $Trigger
                Principal   = $Principal
                Settings    = $Settings
                Description = $Description
            }
            [void]$script:registerCalls.Add($obj)
            return $obj
        }

        $script:fakeScript = Join-Path $TestDrive 'fake.ps1'
        Set-Content -LiteralPath $script:fakeScript -Value '# noop' -Encoding UTF8
    }

    It 'registers a logon-trigger task as SYSTEM with Highest run level' {
        $result = Register-BaselineRemovalPersistenceTask -Name 'BloatRemoval' -ScriptPath $script:fakeScript -Trigger Logon

        $result | Should -Be '\Baseline\Persistence\BloatRemoval'
        $script:registerCalls.Count | Should -Be 1

        $call = $script:registerCalls[0]
        $call.TaskName | Should -Be 'BloatRemoval'
        $call.TaskPath | Should -Be '\Baseline\Persistence\'
        $call.Principal.UserId | Should -Be 'NT AUTHORITY\SYSTEM'
        $call.Principal.LogonType | Should -Be 'ServiceAccount'
        $call.Principal.RunLevel | Should -Be 'Highest'

        @($call.Trigger).Count | Should -Be 1
        @($call.Trigger)[0].AtLogon | Should -BeTrue
        @($call.Trigger)[0].AtStartup | Should -BeFalse
    }

    It 'registers a startup-trigger task' {
        Register-BaselineRemovalPersistenceTask -Name 'EdgeRemoval' -ScriptPath $script:fakeScript -Trigger Startup | Out-Null

        @($script:registerCalls[0].Trigger).Count | Should -Be 1
        @($script:registerCalls[0].Trigger)[0].AtStartup | Should -BeTrue
    }

    It 'registers both logon and startup triggers when -Trigger Both' {
        Register-BaselineRemovalPersistenceTask -Name 'BothTriggers' -ScriptPath $script:fakeScript -Trigger Both | Out-Null

        @($script:registerCalls[0].Trigger).Count | Should -Be 2
    }

    It 'embeds the script path into the powershell.exe argument' {
        Register-BaselineRemovalPersistenceTask -Name 'ArgsTest' -ScriptPath $script:fakeScript -Trigger Logon | Out-Null

        $action = $script:registerCalls[0].Action
        $action.Execute | Should -Be 'powershell.exe'
        $action.Argument | Should -Match '-NoProfile'
        $action.Argument | Should -Match '-NonInteractive'
        $action.Argument | Should -Match '-ExecutionPolicy Bypass'
        $action.Argument | Should -Match ([regex]::Escape($script:fakeScript))
    }

    It 'configures unlimited execution time and battery-friendly settings' {
        Register-BaselineRemovalPersistenceTask -Name 'SettingsTest' -ScriptPath $script:fakeScript -Trigger Logon | Out-Null

        $settings = $script:registerCalls[0].Settings
        $settings.AllowStartIfOnBatteries | Should -BeTrue
        $settings.DontStopIfGoingOnBatteries | Should -BeTrue
        $settings.StartWhenAvailable | Should -BeTrue
        $settings.ExecutionTimeLimit.TotalSeconds | Should -Be 0
    }

    It 'unregisters an existing task with the same name before registering' {
        $script:existingTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }

        Register-BaselineRemovalPersistenceTask -Name 'BloatRemoval' -ScriptPath $script:fakeScript -Trigger Logon | Out-Null

        $script:unregisterCalls.Count | Should -Be 1
        $script:unregisterCalls[0].TaskName | Should -Be 'BloatRemoval'
        $script:registerCalls.Count | Should -Be 1
    }

    It 'uses a default description when none provided' {
        Register-BaselineRemovalPersistenceTask -Name 'DescTest' -ScriptPath $script:fakeScript -Trigger Logon | Out-Null

        $script:registerCalls[0].Description | Should -Match "Baseline removal persistence for 'DescTest'"
    }

    It 'uses the supplied description when provided' {
        Register-BaselineRemovalPersistenceTask -Name 'CustomDesc' -ScriptPath $script:fakeScript -Trigger Logon -Description 'Custom desc' | Out-Null

        $script:registerCalls[0].Description | Should -Be 'Custom desc'
    }

    It 'rejects invalid entry names' {
        { Register-BaselineRemovalPersistenceTask -Name 'foo\bar' -ScriptPath $script:fakeScript -Trigger Logon } | Should -Throw -ExpectedMessage '*Invalid removal persistence entry name*'
    }

    It 'throws when the script path does not exist' {
        { Register-BaselineRemovalPersistenceTask -Name 'MissingScript' -ScriptPath (Join-Path $TestDrive 'does-not-exist.ps1') -Trigger Logon } | Should -Throw -ExpectedMessage '*Removal persistence script not found*'
    }

    It 'honours -WhatIf and does not call Register-ScheduledTask' {
        Register-BaselineRemovalPersistenceTask -Name 'WhatIfReg' -ScriptPath $script:fakeScript -Trigger Logon -WhatIf | Out-Null
        $script:registerCalls.Count | Should -Be 0
    }
}

Describe 'Unregister-BaselineRemovalPersistenceTask' {
    BeforeEach {
        $script:sandboxRoot = Join-Path $TestDrive 'RemovalScripts'
        $env:BASELINE_REMOVAL_SCRIPT_DIR = $script:sandboxRoot
        New-Item -ItemType Directory -Path $script:sandboxRoot -Force | Out-Null

        $script:unregisterCalls = [System.Collections.Generic.List[object]]::new()
        $script:existingTask = $null

        function Get-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath)
            return $script:existingTask
        }

        function Unregister-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath, [switch]$Confirm)
            [void]$script:unregisterCalls.Add([pscustomobject]@{ TaskName = $TaskName; TaskPath = $TaskPath })
        }
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_REMOVAL_SCRIPT_DIR -ErrorAction SilentlyContinue
    }

    It 'returns $false and does nothing when the task does not exist' {
        $result = Unregister-BaselineRemovalPersistenceTask -Name 'Nope'
        $result | Should -BeFalse
        $script:unregisterCalls.Count | Should -Be 0
    }

    It 'unregisters and returns $true when the task exists' {
        $script:existingTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }
        $result = Unregister-BaselineRemovalPersistenceTask -Name 'BloatRemoval'
        $result | Should -BeTrue
        $script:unregisterCalls.Count | Should -Be 1
    }

    It 'leaves the script on disk when -RemoveScript is not specified' {
        $script:existingTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }
        $scriptPath = Join-Path $script:sandboxRoot 'BloatRemoval.ps1'
        Set-Content -LiteralPath $scriptPath -Value '# noop' -Encoding UTF8

        Unregister-BaselineRemovalPersistenceTask -Name 'BloatRemoval' | Out-Null

        Test-Path -LiteralPath $scriptPath | Should -BeTrue
    }

    It 'removes the script when -RemoveScript is specified' {
        $script:existingTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }
        $scriptPath = Join-Path $script:sandboxRoot 'BloatRemoval.ps1'
        Set-Content -LiteralPath $scriptPath -Value '# noop' -Encoding UTF8

        Unregister-BaselineRemovalPersistenceTask -Name 'BloatRemoval' -RemoveScript | Out-Null

        Test-Path -LiteralPath $scriptPath | Should -BeFalse
    }

    It 'tolerates missing script when -RemoveScript is specified' {
        $script:existingTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }
        # No script on disk
        { Unregister-BaselineRemovalPersistenceTask -Name 'BloatRemoval' -RemoveScript } | Should -Not -Throw
    }

    It 'rejects invalid entry names' {
        { Unregister-BaselineRemovalPersistenceTask -Name '..\evil' } | Should -Throw -ExpectedMessage '*Invalid removal persistence entry name*'
    }
}

Describe 'Get-BaselineRemovalPersistenceTasks' {
    BeforeEach {
        $script:sandboxRoot = Join-Path $TestDrive 'RemovalScripts'
        $env:BASELINE_REMOVAL_SCRIPT_DIR = $script:sandboxRoot
        New-Item -ItemType Directory -Path $script:sandboxRoot -Force | Out-Null
        $script:fakeTasks = $null

        function Get-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath)
            return $script:fakeTasks
        }
    }

    AfterEach {
        Remove-Item -LiteralPath Env:BASELINE_REMOVAL_SCRIPT_DIR -ErrorAction SilentlyContinue
    }

    It 'returns an empty array when no tasks are registered' {
        $script:fakeTasks = $null
        $result = Get-BaselineRemovalPersistenceTasks
        @($result).Count | Should -Be 0
    }

    It 'projects task data into pscustomobjects with FullName / ScriptPath / ScriptExists' {
        $script:fakeTasks = @(
            [pscustomobject]@{ TaskName = 'BloatRemoval'; State = 'Ready'; Description = 'desc 1' }
            [pscustomobject]@{ TaskName = 'EdgeRemoval'; State = 'Ready'; Description = 'desc 2' }
        )
        # Only BloatRemoval has a script on disk.
        Set-Content -LiteralPath (Join-Path $script:sandboxRoot 'BloatRemoval.ps1') -Value '# noop' -Encoding UTF8

        $result = @(Get-BaselineRemovalPersistenceTasks)
        $result.Count | Should -Be 2

        $bloat = $result | Where-Object { $_.TaskName -eq 'BloatRemoval' }
        $bloat.FullName | Should -Be '\Baseline\Persistence\BloatRemoval'
        $bloat.State | Should -Be 'Ready'
        $bloat.ScriptPath | Should -Be (Join-Path $script:sandboxRoot 'BloatRemoval.ps1')
        $bloat.ScriptExists | Should -BeTrue
        $bloat.Description | Should -Be 'desc 1'

        $edge = $result | Where-Object { $_.TaskName -eq 'EdgeRemoval' }
        $edge.ScriptExists | Should -BeFalse
    }
}

Describe 'Test-BaselineRemovalPersistenceTaskExists' {
    BeforeEach {
        $script:fakeTask = $null
        function Get-ScheduledTask {
            param([string]$TaskName, [string]$TaskPath)
            return $script:fakeTask
        }
    }

    It 'returns $true when the task exists' {
        $script:fakeTask = [pscustomobject]@{ TaskName = 'BloatRemoval' }
        Test-BaselineRemovalPersistenceTaskExists -Name 'BloatRemoval' | Should -BeTrue
    }

    It 'returns $false when the task does not exist' {
        $script:fakeTask = $null
        Test-BaselineRemovalPersistenceTaskExists -Name 'Nope' | Should -BeFalse
    }

    It 'returns $false for invalid entry names without throwing' {
        Test-BaselineRemovalPersistenceTaskExists -Name 'foo\bar' | Should -BeFalse
    }
}
