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
        $script:startProcessCalls = [System.Collections.Generic.List[object]]::new()
        $Global:LogFilePath = 'C:\temp\Baseline.log'

        function Write-ConsoleStatus {
            param([string]$Action, [string]$Status)
            if (-not [string]::IsNullOrWhiteSpace($Status)) { [void]$script:consoleStatuses.Add($Status) }
        }
        function LogInfo { param([string]$Message) }
        function Start-Process {
            param([string]$FilePath, [string]$ArgumentList, [string]$WindowStyle)
            [void]$script:startProcessCalls.Add([pscustomobject]@{ FilePath = $FilePath; ArgumentList = $ArgumentList })
        }
        function Invoke-BaselineProcess {
            param([string]$FilePath, [object[]]$ArgumentList, [int]$TimeoutSeconds)
            [void]$script:startProcessCalls.Add([pscustomobject]@{ FilePath = $FilePath; ArgumentList = @($ArgumentList); TimeoutSeconds = $TimeoutSeconds })
            [pscustomobject]@{ ExitCode = 0 }
        }
        # $PSScriptRoot is empty when the function is re-evaluated via
        # Invoke-Expression, so Join-Path's Path becomes an empty string.
        # Shim Join-Path to tolerate empty Path.
        function Join-Path {
            param([string]$Path, [string]$ChildPath)
            if ([string]::IsNullOrEmpty($Path)) { return $ChildPath }
            return [System.IO.Path]::Combine($Path, $ChildPath)
        }
    }

    AfterEach {
        foreach ($n in @('Write-ConsoleStatus','LogInfo','Start-Process','Invoke-BaselineProcess','Join-Path')) {
            Remove-Item Function:\$n -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue
    }

    It 'launches the diskcleanup helper script with powershell.exe' {
        DiskCleanup

        $script:startProcessCalls.Count | Should -Be 1
        $script:startProcessCalls[0].FilePath | Should -Be 'powershell.exe'
        @($script:startProcessCalls[0].ArgumentList) -join ' ' | Should -Match 'diskcleanup\.ps1'
        @($script:startProcessCalls[0].ArgumentList) | Should -Contain '-ExecutionPolicy'
        @($script:startProcessCalls[0].ArgumentList) | Should -Contain 'Bypass'
        $script:startProcessCalls[0].TimeoutSeconds | Should -Be 3000
    }
}

Describe 'DiskCleanup manifest bounds' {
    It 'declares a GUI timeout long enough for the cleanup helper process' {
        $manifest = Get-Content -Raw (Join-Path $PSScriptRoot '../../Module/Data/SystemTweaks.json') | ConvertFrom-Json
        $entry = $manifest.Entries | Where-Object Function -eq 'DiskCleanup' | Select-Object -First 1

        [int]$entry.TimeoutSeconds | Should -BeGreaterOrEqual 3000
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
