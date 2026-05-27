Set-StrictMode -Version Latest

BeforeAll {
    $script:HelperPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/WindowsUpdate.Helpers.ps1'
    . $script:HelperPath

    function New-FakeIndexedCollection
    {
        param (
            [object[]]$Items = @()
        )

        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @($Items))
        {
            [void]$list.Add($item)
        }

        $collection = [pscustomobject]@{
            Items = $list
        }
        $collection | Add-Member -MemberType ScriptProperty -Name Count -Value { $this.Items.Count } -Force
        $collection | Add-Member -MemberType ScriptMethod -Name Item -Value { param ($Index) $this.Items[[int]$Index] } -Force
        $collection | Add-Member -MemberType ScriptMethod -Name Add -Value {
            param ($Item)
            [void]$this.Items.Add($Item)
            return ($this.Items.Count - 1)
        } -Force
        return $collection
    }

    function New-FakeUpdate
    {
        param (
            [string]$Id,
            [int]$RevisionNumber,
            [string]$Title,
            [string]$MsrcSeverity = '',
            [string[]]$CategoryNames = @(),
            [object]$Type = 1,
            [string[]]$KBArticleIDs = @(),
            [bool]$IsInstalled = $false,
            [bool]$IsHidden = $false,
            [bool]$IsDownloaded = $false,
            [bool]$RebootRequired = $false
        )

        $categories = @(
            foreach ($categoryName in @($CategoryNames))
            {
                [pscustomobject]@{
                    Name       = $categoryName
                    CategoryID = $categoryName
                    Type       = 'UpdateClassification'
                }
            }
        )

        return [pscustomobject]@{
            Identity       = [pscustomobject]@{ UpdateID = $Id; RevisionNumber = $RevisionNumber }
            Title          = $Title
            Description    = "Description for $Title"
            MsrcSeverity   = $MsrcSeverity
            Categories     = New-FakeIndexedCollection -Items $categories
            KBArticleIDs   = New-FakeIndexedCollection -Items $KBArticleIDs
            IsInstalled    = $IsInstalled
            IsHidden       = $IsHidden
            IsDownloaded   = $IsDownloaded
            Type           = $Type
            RebootRequired = $RebootRequired
        }
    }

    function New-FakeWindowsUpdateProgressJob
    {
        param (
            [int[]]$Percentages
        )

        if (-not $Percentages -or $Percentages.Count -eq 0)
        {
            $Percentages = @(100)
        }

        $job = [pscustomobject]@{
            Percentages   = [int[]]$Percentages
            ProgressIndex = 0
            CleanedUp     = $false
        }
        $job | Add-Member -MemberType ScriptProperty -Name IsCompleted -Value {
            return ([int]$this.ProgressIndex -ge ([int]$this.Percentages.Count - 1))
        } -Force
        $job | Add-Member -MemberType ScriptMethod -Name GetProgress -Value {
            $index = [Math]::Min([int]$this.ProgressIndex, ([int]$this.Percentages.Count - 1))
            $percent = [int]$this.Percentages[$index]
            if ([int]$this.ProgressIndex -lt ([int]$this.Percentages.Count - 1))
            {
                $this.ProgressIndex = [int]$this.ProgressIndex + 1
            }

            return [pscustomobject]@{
                PercentComplete              = $percent
                CurrentUpdateIndex           = 0
                CurrentUpdatePercentComplete = $percent
                CurrentUpdateBytesDownloaded = 0
                CurrentUpdateBytesToDownload = 0
                TotalBytesDownloaded         = 0
                TotalBytesToDownload         = 0
            }
        } -Force
        $job | Add-Member -MemberType ScriptMethod -Name CleanUp -Value {
            $this.CleanedUp = $true
        } -Force
        return $job
    }

    function New-FakeWindowsUpdateSessionFixture
    {
        param (
            [object[]]$Updates = @(),
            [object[]]$History = @(),
            [int]$DownloadResultCode = 2,
            [int]$InstallResultCode = 2,
            [bool]$InstallRebootRequired = $false,
            [bool]$SystemInfoRebootRequired = $false,
            [int[]]$DownloadProgressPercentages = @(0, 100),
            [int[]]$InstallProgressPercentages = @(0, 100)
        )

        $searcher = [pscustomobject]@{
            UpdatesCollection = New-FakeIndexedCollection -Items $Updates
            HistoryCollection = New-FakeIndexedCollection -Items $History
            LastCriteria      = $null
        }
        $searcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
            param ($Criteria)
            $this.LastCriteria = $Criteria
            return [pscustomobject]@{ Updates = $this.UpdatesCollection }
        } -Force
        $searcher | Add-Member -MemberType ScriptMethod -Name GetTotalHistoryCount -Value {
            return $this.HistoryCollection.Count
        } -Force
        $searcher | Add-Member -MemberType ScriptMethod -Name QueryHistory -Value {
            param ($StartIndex, $Count)
            $items = New-Object 'System.Collections.Generic.List[object]'
            for ($index = [int]$StartIndex; $index -lt ([int]$StartIndex + [int]$Count); $index++)
            {
                [void]$items.Add($this.HistoryCollection.Item($index))
            }
            return New-FakeIndexedCollection -Items ([object[]]$items.ToArray())
        } -Force

        $downloader = [pscustomobject]@{
            Updates                = $null
            ResultCode             = $DownloadResultCode
            ProgressPercentages    = [int[]]$DownloadProgressPercentages
            AsyncJob               = $null
            BeginProgressCallback  = $null
            BeginCompletedCallback = $null
            BeginState             = $null
        }
        $downloader | Add-Member -MemberType ScriptMethod -Name Download -Value {
            return [pscustomobject]@{ ResultCode = $this.ResultCode }
        } -Force
        $downloader | Add-Member -MemberType ScriptMethod -Name BeginDownload -Value {
            param ($OnProgressChanged, $OnCompleted, $State)
            $this.BeginProgressCallback = $OnProgressChanged
            $this.BeginCompletedCallback = $OnCompleted
            $this.BeginState = $State
            $this.AsyncJob = New-FakeWindowsUpdateProgressJob -Percentages $this.ProgressPercentages
            return $this.AsyncJob
        } -Force
        $downloader | Add-Member -MemberType ScriptMethod -Name EndDownload -Value {
            param ($Job)
            return [pscustomobject]@{ ResultCode = $this.ResultCode }
        } -Force

        $installer = [pscustomobject]@{
            Updates                = $null
            ResultCode             = $InstallResultCode
            RebootRequired         = $InstallRebootRequired
            ProgressPercentages    = [int[]]$InstallProgressPercentages
            AsyncJob               = $null
            BeginProgressCallback  = $null
            BeginCompletedCallback = $null
            BeginState             = $null
        }
        $installer | Add-Member -MemberType ScriptMethod -Name Install -Value {
            return [pscustomobject]@{ ResultCode = $this.ResultCode }
        } -Force
        $installer | Add-Member -MemberType ScriptMethod -Name BeginInstall -Value {
            param ($OnProgressChanged, $OnCompleted, $State)
            $this.BeginProgressCallback = $OnProgressChanged
            $this.BeginCompletedCallback = $OnCompleted
            $this.BeginState = $State
            $this.AsyncJob = New-FakeWindowsUpdateProgressJob -Percentages $this.ProgressPercentages
            return $this.AsyncJob
        } -Force
        $installer | Add-Member -MemberType ScriptMethod -Name EndInstall -Value {
            param ($Job)
            return [pscustomobject]@{ ResultCode = $this.ResultCode }
        } -Force

        $systemInfo = [pscustomobject]@{
            RebootRequired = $SystemInfoRebootRequired
        }

        $session = [pscustomobject]@{
            Searcher   = $searcher
            Downloader = $downloader
            Installer  = $installer
        }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { return $this.Searcher } -Force
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateDownloader -Value { return $this.Downloader } -Force
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateInstaller -Value { return $this.Installer } -Force

        return [pscustomobject]@{
            Session    = $session
            Searcher   = $searcher
            Downloader = $downloader
            Installer  = $installer
            SystemInfo = $systemInfo
        }
    }
}

Describe 'Windows Update helper functions' {
    It 'parses under Windows PowerShell 5.1' {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:HelperPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }

    It 'maps WUA update metadata into a manifest-independent update model' {
        $updates = @(
            New-FakeUpdate -Id 'critical-id' -RevisionNumber 1 -Title 'Critical cumulative update' -MsrcSeverity 'Critical' -CategoryNames @('Security Updates') -KBArticleIDs @('5000001')
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates') -KBArticleIDs @('5000002')
            New-FakeUpdate -Id 'driver-id' -RevisionNumber 3 -Title 'Driver update' -CategoryNames @('Drivers') -Type 2
            New-FakeUpdate -Id 'optional-id' -RevisionNumber 4 -Title 'Optional update' -CategoryNames @('Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates

        $result = @(Get-WindowsUpdateList -Session $fixture.Session)

        $fixture.Searcher.LastCriteria | Should -Be 'IsInstalled=0 and IsHidden=0'
        $result.Count | Should -Be 4
        $result[0].Classification | Should -Be 'Critical'
        $result[1].Classification | Should -Be 'Security'
        $result[2].Classification | Should -Be 'Drivers'
        $result[3].Classification | Should -Be 'Optional'
        $result[0].MsrcSeverity | Should -Be 'Critical'
        $result[0].KBArticleIDs | Should -Contain '5000001'
        $result[1].Categories[0].Name | Should -Be 'Security Updates'
        $result[2].Type | Should -Be 'Driver'
        $result[3].IsInstalled | Should -BeFalse
        $result[3].IsHidden | Should -BeFalse
    }

    It 'downloads selected updates through a WUA update collection and structured result' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'optional-id' -RevisionNumber 4 -Title 'Optional update' -CategoryNames @('Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -DownloadResultCode 2
        $records = @(Get-WindowsUpdateList -Session $fixture.Session)

        $result = Download-WindowsUpdates -Updates $records -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection }

        $fixture.Downloader.Updates.Count | Should -Be 2
        $result.Operation | Should -Be 'Download'
        $result.UpdateCount | Should -Be 2
        $result.Result | Should -Be 'Succeeded'
        $result.Succeeded | Should -BeTrue
    }

    It 'reports asynchronous download progress percentages from the WUA job' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -DownloadResultCode 2 -DownloadProgressPercentages @(0, 45, 100)
        $records = @(Get-WindowsUpdateList -Session $fixture.Session)
        $percentages = [System.Collections.Generic.List[int]]::new()

        $result = Download-WindowsUpdates -Updates $records -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection } -ProgressPollMilliseconds 0 -ProgressCallback {
            param ([object]$Progress)
            [void]$percentages.Add([int]$Progress.PercentComplete)
        }

        $result.Succeeded | Should -BeTrue
        [int[]]$percentages.ToArray() | Should -Be @(0, 45, 100)
        $fixture.Downloader.BeginProgressCallback | Should -Not -BeNullOrEmpty
        $fixture.Downloader.BeginCompletedCallback | Should -Not -BeNullOrEmpty
        $fixture.Downloader.BeginState | Should -Be 'Baseline.WindowsUpdate.Download'
        $fixture.Downloader.AsyncJob.CleanedUp | Should -BeTrue
    }

    It 'installs selected updates and exposes reboot-required state' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -InstallResultCode 2 -InstallRebootRequired:$true
        $records = @(Get-WindowsUpdateList -Session $fixture.Session)

        $result = Install-WindowsUpdates -Updates $records -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection } -SystemInfo $fixture.SystemInfo

        $fixture.Installer.Updates.Count | Should -Be 1
        $result.Operation | Should -Be 'Install'
        $result.Result | Should -Be 'Succeeded'
        $result.Succeeded | Should -BeTrue
        $result.RebootRequired | Should -BeTrue
    }

    It 'reports restart required when Windows Update system state has a pending restart notification' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -InstallResultCode 2 -InstallRebootRequired:$false -SystemInfoRebootRequired:$true
        $records = @(Get-WindowsUpdateList -Session $fixture.Session)

        $result = Install-WindowsUpdates -Updates $records -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection } -SystemInfo $fixture.SystemInfo

        $result.Succeeded | Should -BeTrue
        $result.RebootRequired | Should -BeTrue
    }

    It 'reports asynchronous install progress percentages from the WUA job' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -InstallResultCode 2 -InstallProgressPercentages @(0, 30, 75, 100)
        $records = @(Get-WindowsUpdateList -Session $fixture.Session)
        $percentages = [System.Collections.Generic.List[int]]::new()

        $result = Install-WindowsUpdates -Updates $records -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection } -SystemInfo $fixture.SystemInfo -ProgressPollMilliseconds 0 -ProgressCallback {
            param ([object]$Progress)
            [void]$percentages.Add([int]$Progress.PercentComplete)
        }

        $result.Succeeded | Should -BeTrue
        [int[]]$percentages.ToArray() | Should -Be @(0, 30, 75, 100)
        $fixture.Installer.BeginProgressCallback | Should -Not -BeNullOrEmpty
        $fixture.Installer.BeginCompletedCallback | Should -Not -BeNullOrEmpty
        $fixture.Installer.BeginState | Should -Be 'Baseline.WindowsUpdate.Install'
        $fixture.Installer.AsyncJob.CleanedUp | Should -BeTrue
    }

    It 'returns read-only Windows Update history records from QueryHistory' {
        $history = @(
            [pscustomobject]@{
                Date        = [datetime]'2026-04-28T10:00:00'
                Title       = 'Security update'
                Description = 'Installed security update'
                Operation   = 1
                ResultCode  = 2
                HResult     = 0
                SupportUrl  = 'https://support.microsoft.com/'
            }
            [pscustomobject]@{
                Date        = [datetime]'2026-04-27T10:00:00'
                Title       = 'Driver update'
                Description = 'Driver install failed'
                Operation   = 1
                ResultCode  = 4
                HResult     = -1
                SupportUrl  = ''
            }
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -History $history

        $result = @(Get-WindowsUpdateHistory -Session $fixture.Session -Count 2)

        $result.Count | Should -Be 2
        $result[0].OperationName | Should -Be 'Installation'
        $result[0].Result | Should -Be 'Succeeded'
        $result[1].Result | Should -Be 'Failed'
        $result[1].Title | Should -Be 'Driver update'
    }

    It 'returns a structured no-op result when no updates are selected' {
        $fixture = New-FakeWindowsUpdateSessionFixture

        $result = Download-WindowsUpdates -Updates @() -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection }

        $result.Operation | Should -Be 'Download'
        $result.UpdateCount | Should -Be 0
        $result.Result | Should -Be 'NoUpdates'
        $result.Succeeded | Should -BeTrue
    }

    It 'installs only security and critical updates for scheduled security runs' {
        $updates = @(
            New-FakeUpdate -Id 'critical-id' -RevisionNumber 1 -Title 'Critical cumulative update' -MsrcSeverity 'Critical' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'driver-id' -RevisionNumber 3 -Title 'Driver update' -CategoryNames @('Drivers') -Type 2
            New-FakeUpdate -Id 'optional-id' -RevisionNumber 4 -Title 'Optional update' -CategoryNames @('Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates

        $result = Install-WindowsSecurityUpdates -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection } -SystemInfo $fixture.SystemInfo

        $fixture.Downloader.Updates.Count | Should -Be 2
        $fixture.Installer.Updates.Count | Should -Be 2
        $result.Schema | Should -Be 'Baseline.WindowsUpdateSecurityInstall'
        $result.AvailableCount | Should -Be 4
        $result.SelectedCount | Should -Be 2
        $result.Summary.Critical | Should -Be 1
        $result.Summary.Security | Should -Be 1
        $result.Summary.Drivers | Should -Be 1
        $result.Summary.Optional | Should -Be 1
        $result.SelectedTitles | Should -Contain 'Critical cumulative update'
        $result.SelectedTitles | Should -Contain 'Security update'
        $result.SelectedTitles | Should -Not -Contain 'Driver update'
        $result.Succeeded | Should -BeTrue
    }

    It 'returns Windows Update status with available update summary and recent history' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'optional-id' -RevisionNumber 4 -Title 'Optional update' -CategoryNames @('Updates')
        )
        $history = @(
            [pscustomobject]@{
                Date        = [datetime]'2026-04-28T11:00:00'
                Title       = 'Latest security update'
                Description = 'Installed security update'
                Operation   = 1
                ResultCode  = 2
                HResult     = 0
                SupportUrl  = 'https://support.microsoft.com/'
            }
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates -History $history
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppDataStatus'
        try {
            $result = Get-WindowsUpdateStatus -Session $fixture.Session -HistoryCount 1
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.Schema | Should -Be 'Baseline.WindowsUpdateStatus'
        $result.Succeeded | Should -BeTrue
        $result.Summary.Total | Should -Be 2
        $result.Summary.Security | Should -Be 1
        $result.Summary.Optional | Should -Be 1
        $result.AvailableUpdates[0].Title | Should -Be 'Security update'
        $result.RecentHistory[0].Title | Should -Be 'Latest security update'
    }

    It 'reports non-compliance when security or critical updates are pending' {
        $updates = @(
            New-FakeUpdate -Id 'critical-id' -RevisionNumber 1 -Title 'Critical cumulative update' -MsrcSeverity 'Critical' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
            New-FakeUpdate -Id 'optional-id' -RevisionNumber 4 -Title 'Optional update' -CategoryNames @('Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppDataCompliance'
        try {
            $result = Get-WindowsUpdateCompliance -Session $fixture.Session
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.Schema | Should -Be 'Baseline.WindowsUpdateCompliance'
        $result.Status | Should -Be 'NonCompliant'
        $result.CriticalPending | Should -Be 1
        $result.SecurityPending | Should -Be 1
    }

    It 'persists scheduled security run results for later status reporting' {
        $updates = @(
            New-FakeUpdate -Id 'security-id' -RevisionNumber 2 -Title 'Security update' -CategoryNames @('Security Updates')
        )
        $fixture = New-FakeWindowsUpdateSessionFixture -Updates $updates
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppDataScheduledRun'
        try {
            $result = Invoke-BaselineWindowsUpdateScheduledRun -Session $fixture.Session -CollectionFactory { New-FakeIndexedCollection }
            $resultPath = Get-BaselineWindowsUpdateScheduledResultPath
            $payload = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result.Succeeded | Should -BeTrue
        Test-Path -LiteralPath $resultPath | Should -BeTrue
        $payload.Schema | Should -Be 'Baseline.WindowsUpdateSecurityInstall'
        $payload.SelectedCount | Should -Be 1
        $payload.Succeeded | Should -BeTrue
    }

    It 'persists structured scheduled run failures before throwing' {
        $badSession = [pscustomobject]@{}
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppDataScheduledRunFailure'
        try {
            { Invoke-BaselineWindowsUpdateScheduledRun -Session $badSession } | Should -Throw
            $resultPath = Get-BaselineWindowsUpdateScheduledResultPath
            $payload = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        Test-Path -LiteralPath $resultPath | Should -BeTrue
        $payload.Schema | Should -Be 'Baseline.WindowsUpdateSecurityInstall'
        $payload.Operation | Should -Be 'ScheduledSecurityInstall'
        $payload.Succeeded | Should -BeFalse
        $payload.Error | Should -Match 'Could not create Windows Update searcher'
    }
}
