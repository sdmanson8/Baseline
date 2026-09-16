Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/SystemTweaks.Cleanup.psm1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'DiskCleanup' {
    BeforeEach {
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:launchFails = $false
        $script:worker = [pscustomobject]@{
            StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
            Id = 123
            Disposed = $false
        }
        $script:worker | Add-Member ScriptMethod Start {
            if ($script:launchFails) { throw 'launch failed' }
            return $true
        }
        $script:worker | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
        $Global:LogFilePath = 'C:\temp\Baseline.log'
        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if ($Status) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function New-Object { param([string]$TypeName) return $script:worker }
        function Join-Path {
            param([string]$Path, [string]$ChildPath)
            if ([string]::IsNullOrEmpty($Path)) { return "C:\Baseline With Spaces\$ChildPath" }
            return [IO.Path]::Combine($Path, $ChildPath)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','New-Object','Join-Path')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue
    }

    It 'starts a detached worker with no shell or output pipes and releases its process handle' {
        DiskCleanup
        $script:worker.StartInfo.FileName | Should -Be ([IO.Path]::Combine($PSHOME, 'powershell.exe'))
        $script:worker.StartInfo.Arguments | Should -Match '-File "C:\\Baseline With Spaces\\diskcleanup.ps1"'
        $script:worker.StartInfo.Arguments | Should -Match '-NonInteractive'
        $script:worker.StartInfo.UseShellExecute | Should -BeFalse
        $script:worker.StartInfo.CreateNoWindow | Should -BeTrue
        $script:worker.StartInfo.WindowStyle | Should -Be 'Hidden'
        $script:worker.StartInfo.RedirectStandardOutput | Should -BeFalse
        $script:worker.StartInfo.RedirectStandardError | Should -BeFalse
        $script:worker.StartInfo.EnvironmentVariables['diskcleanup'] | Should -Be $Global:LogFilePath
        $script:worker.Disposed | Should -BeTrue
        $script:consoleStatuses | Should -Contain 'success'
    }

    It 'propagates launch failures without reporting success and releases the handle' {
        $script:launchFails = $true
        { DiskCleanup } | Should -Throw '*launch failed*'
        $script:consoleStatuses | Should -Not -Contain 'success'
        $script:worker.Disposed | Should -BeTrue
    }
}

Describe 'diskcleanup helper process bounds' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $script:DiskCleanupHelperContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/SystemTweaks/diskcleanup.ps1')
    }

    It 'bounds cleanmgr waits and uses shared tree termination on timeout' {
        $script:DiskCleanupHelperContent | Should -Match '\[int\]\$TimeoutSeconds = 900'
        $script:DiskCleanupHelperContent | Should -Match 'Stop-BaselineProcessTree -Process \$Process -Source ''DiskCleanup\.CleanmgrTimeout'''
        $script:DiskCleanupHelperContent | Should -Match 'Wait-CleanupProcessAndDismissNotification -Process \$cleanmgrProcess -TimeoutSeconds 900'
        $script:DiskCleanupHelperContent | Should -Match 'Stop-ScheduledTask -InputObject \$currentTask'
        $script:DiskCleanupHelperContent | Should -Match 'return \$false'
        $script:DiskCleanupHelperContent | Should -Match '/StartComponentCleanup'
        $script:DiskCleanupHelperContent | Should -Match '/NoRestart'
        $script:DiskCleanupHelperContent | Should -Match '-TimeoutSeconds 1800'
        $script:DiskCleanupHelperContent | Should -Not -Match '/ResetBase'
        $script:DiskCleanupHelperContent | Should -Not -Match 'Stop-Process\s+-Id\s+\$Process\.Id'
    }

    It 'accepts the cleanup process OK dialog without closing or killing its progress window' {
        $script:DiskCleanupHelperContent | Should -Match 'AcceptNotification\(\$Process.Id\)'
        $script:DiskCleanupHelperContent | Should -Match 'ownerId != \(uint\)processId'
        $script:DiskCleanupHelperContent | Should -Match 'GetDlgItem\(window, 1\)'
        $script:DiskCleanupHelperContent | Should -Match 'PostMessage\(window, 0x0111, new IntPtr\(1\), okButton\)'
        $script:DiskCleanupHelperContent | Should -Not -Match 'FindWindow|CloseMainWindow|0x0010|quietDeadline'
    }
}

Describe 'Invoke-CleanupOperation' {
    BeforeEach {
        $script:consoleActions = [System.Collections.Generic.List[string]]::new()
        $script:consoleStatuses = [System.Collections.Generic.List[string]]::new()
        $script:removedPaths = [System.Collections.Generic.List[string]]::new()
        $script:clearRecycleCalled = $false
        $script:clearRecycleThrows = $false

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Action)) { [void]$script:consoleActions.Add($Action) }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function LogWarning { param([string]$Message) }
        function Test-Path { param([string]$Path) return $true }
        function Remove-Item {
            param([string]$Path, [switch]$Force, [switch]$Recurse, [object]$ErrorAction)
            [void]$script:removedPaths.Add($Path)
        }
        function Clear-RecycleBin {
            param([switch]$Force, [object]$ErrorAction)
            $script:clearRecycleCalled = $true
            if ($script:clearRecycleThrows) { throw 'recycle bin locked' }
        }
        function New-Object {
            param([string]$ComObject)
            throw 'no Shell.Application in tests'
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','LogWarning','Test-Path','Remove-Item','Clear-RecycleBin','New-Object')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
    }

    It 'requires one of All/Temp/Cache/Recycle' {
        { Invoke-CleanupOperation } | Should -Throw
    }

    It 'cleans TEMP paths on -Temp' {
        Invoke-CleanupOperation -Temp

        $script:removedPaths.Count | Should -BeGreaterOrEqual 1
        ($script:removedPaths | Where-Object { $_ -match 'TEMP' }).Count | Should -BeGreaterOrEqual 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'cleans cache paths on -Cache' {
        Invoke-CleanupOperation -Cache

        ($script:removedPaths | Where-Object { $_ -match 'INetCache' }).Count | Should -BeGreaterOrEqual 1
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'calls Clear-RecycleBin on -Recycle and reports success' {
        Invoke-CleanupOperation -Recycle

        $script:clearRecycleCalled | Should -BeTrue
        $script:consoleStatuses[-1] | Should -Be 'success'
    }

    It 'reports failed when -Recycle throws' {
        $script:clearRecycleThrows = $true

        Invoke-CleanupOperation -Recycle

        $script:consoleStatuses[-1] | Should -Be 'failed'
    }
}
