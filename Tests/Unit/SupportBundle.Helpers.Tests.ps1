Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    <#
        .SYNOPSIS
    #>

    function Get-BaselineDisplayVersion { return '1.0.0' }

    # Json helpers must load first - SupportBundle/RemoteTarget call ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    $auditHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/AuditTrail.Helpers.ps1'
    $processHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Process.Helpers.ps1'
    $stateCaptureHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/StateCapture.Helpers.ps1'
    $bundleHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle.Helpers.ps1'
    $remoteHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/RemoteTarget.Helpers.ps1'
    $script:BundleHelpersPath = $bundleHelpersPath
    $script:ExportBundleSplitPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle/Export-BaselineSupportBundle/Export-BaselineSupportBundle.ps1'
    $environmentHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $script:SharedHelpersRepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:SharedHelpersModuleRoot = Join-Path $script:SharedHelpersRepoRoot 'Module'
    foreach ($filePath in @($remoteHelpersPath, $environmentHelpersPath, $bundleHelpersPath)) {
    }
    foreach ($filePath in @($auditHelpersPath, $processHelpersPath, $stateCaptureHelpersPath, $remoteHelpersPath, $environmentHelpersPath, $bundleHelpersPath)) {
        $sourceText = Get-BaselineTestSourceText -Path $filePath
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($fn in $functions) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    foreach ($functionName in @(
        'Stop-BaselineProcessTree',
        'ConvertTo-BaselineWindowsProcessArgument',
        'ConvertTo-BaselineProcessArgumentString',
        'Invoke-BaselineProcess',
        'ConvertTo-BaselineSupportBundleWindowsProcessArgument',
        'ConvertTo-BaselineSupportBundleProcessArgumentString',
        'Invoke-BaselineSupportBundleProcessCapture'
    )) {
        $functionCommand = Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue
        if ($functionCommand) {
            Set-Item -Path ("Function:\Global:{0}" -f $functionName) -Value $functionCommand.ScriptBlock
        }
    }
    $script:SupportBundleUnitProcessCaptureStub = {
        param(
            [string]$FilePath,
            [object[]]$ArgumentList,
            [int]$TimeoutSeconds
        )

        $scriptText = if ($ArgumentList -contains '-File') { Get-Content -LiteralPath ([string]$ArgumentList[-1]) -Raw -Encoding UTF8 } else { [string]$ArgumentList[-1] }
        if ($scriptText -match 'Get-MpComputerStatus') {
            return [pscustomobject]@{
                ExitCode       = 0
                StandardOutput = '{"AMServiceEnabled":true,"AntivirusEnabled":true,"RealTimeProtectionEnabled":true,"IoavProtectionEnabled":true,"NISEnabled":true,"AntispywareEnabled":true}'
                StandardError  = ''
            }
        }

        if ($scriptText -match 'Get-WindowsOptionalFeature -Online') {
            return [pscustomobject]@{
                ExitCode       = 0
                StandardOutput = '[{"Name":"NetFx3","State":"Enabled"},{"Name":"SMB1Protocol","State":"Disabled"}]'
                StandardError  = ''
            }
        }

        return [pscustomobject]@{
            ExitCode       = 0
            StandardOutput = ''
            StandardError  = ''
        }
    }
    Set-Item -Path Function:\Invoke-BaselineSupportBundleProcessCapture -Value $script:SupportBundleUnitProcessCaptureStub
    Set-Item -Path Function:\Global:Invoke-BaselineSupportBundleProcessCapture -Value $script:SupportBundleUnitProcessCaptureStub

    $script:TempRoot = Join-Path $env:TEMP ('BaselineSupportBundleTests_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    $script:AuditLogPath = Join-Path $script:TempRoot 'audit.jsonl'
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $oldTimestamp = ([datetime]::UtcNow).AddDays(-120).ToString('o')
    $recentTimestamp = ([datetime]::UtcNow).AddHours(-1).ToString('o')
    @(
        ('{{"Timestamp":"{0}","Action":"Run","Mode":"Run"}}' -f $oldTimestamp)
        ('{{"Timestamp":"{0}","Action":"Compliance","Mode":"Compliance"}}' -f $recentTimestamp)
    ) | Set-Content -LiteralPath $script:AuditLogPath -Encoding UTF8
    $script:BundlePath = Join-Path $script:TempRoot 'support-bundle.zip'
}

AfterAll {
    if ($null -ne $script:OriginalLocalAppData) {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Export-BaselineSupportBundle' {
    It 'creates a zip archive with bundle metadata and audit log' {
        $historyRoot = Join-Path $script:TempRoot 'LocalAppData'
        $historyDir = Join-Path $historyRoot 'Baseline'
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        $historyPath = Join-Path $historyDir 'remote-orchestration.jsonl'
        @(
            '{"Timestamp":"2026-04-14T08:00:00.0000000Z","MachineName":"TESTHOST","RunId":"abc123","Operation":"RemoteApply","ComputerName":"server01","Status":"Applied","SessionReused":true,"SessionState":"Opened","AppliedCount":2,"FailedCount":0,"DriftedCount":0,"TotalChecked":0,"FailureCategory":"Success","Retryable":false,"RetryReason":"Completed successfully.","Errors":[],"HistoryPath":"C:\\Temp\\remote-orchestration.jsonl"}'
            '{"Timestamp":"2026-04-14T08:01:00.0000000Z","MachineName":"TESTHOST","RunId":"def456","Operation":"RemoteCompliance","ComputerName":"server02","Status":"Compliant","SessionReused":false,"SessionState":"Opened","AppliedCount":0,"FailedCount":0,"DriftedCount":0,"TotalChecked":4,"FailureCategory":"Success","Retryable":false,"RetryReason":"Completed successfully.","Errors":[],"HistoryPath":"C:\\Temp\\remote-orchestration.jsonl"}'
        ) | Set-Content -LiteralPath $historyPath -Encoding UTF8

        # Place the seeded audit log where Get-AuditLogPath will resolve it
        # once $env:LOCALAPPDATA is redirected below.
        Copy-Item -LiteralPath $script:AuditLogPath -Destination (Join-Path $historyDir 'audit.jsonl') -Force

        $previousLocalAppData = $env:LOCALAPPDATA
        $previousTemp = $env:TEMP
        $previousTmp = $env:TMP
        $env:LOCALAPPDATA = $historyRoot
        $env:TEMP = Join-Path $script:TempRoot 'Temp'
        $env:TMP = $env:TEMP
        $launchTraceDir = Join-Path $env:TEMP 'Baseline'
        New-Item -ItemType Directory -Path $launchTraceDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $launchTraceDir 'Baseline-launch-trace.txt') -Value 'launch trace line' -Encoding UTF8
        $sessionSnapshot = [pscustomobject]@{
            SelectedPreset               = 'Privacy'
            SafeMode                     = $true
            AdvancedMode                 = $false
            UIDensity                    = 'Compact'
            CurrentPrimaryTab            = 'Privacy'
            ExplicitSelectionDefinitions = @('AdvertisingID', 'ActivityHistory')
        }
        try {
            $result = Export-BaselineSupportBundle -OutputPath $script:BundlePath -IncludeTestReport:$false -ConfigStatePost $sessionSnapshot
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
            $env:TEMP = $previousTemp
            $env:TMP = $previousTmp
        }

        Test-Path -LiteralPath $result.OutputPath | Should -BeTrue

        $extractDir = Join-Path $script:TempRoot 'extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $metadataPath = Join-Path $extractDir 'metadata.json'
        $auditCopyPath = Join-Path $extractDir 'audit.jsonl'
        $contentsPath = Join-Path $extractDir 'contents.json'
        $versionPath = Join-Path $extractDir 'baseline-version.json'
        $environmentPath = Join-Path $extractDir 'environment.json'
        $featuresPath = Join-Path $extractDir 'windows-features.json'
        $storagePath = Join-Path $extractDir 'storage-summary.json'
        $actionContextPath = Join-Path $extractDir 'user-action-context.json'

        Test-Path -LiteralPath $metadataPath | Should -BeTrue
        Test-Path -LiteralPath $auditCopyPath | Should -BeTrue
        Test-Path -LiteralPath $contentsPath | Should -BeTrue
        Test-Path -LiteralPath $versionPath | Should -BeTrue
        Test-Path -LiteralPath $environmentPath | Should -BeTrue
        Test-Path -LiteralPath $featuresPath | Should -BeTrue
        Test-Path -LiteralPath $storagePath | Should -BeTrue
        Test-Path -LiteralPath $actionContextPath | Should -BeTrue

        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.Schema | Should -Be 'Baseline.SupportBundle'
        $metadata.BaselineVersion | Should -Match '^v1\.0\.0'
        $metadata.AuditRetention.Days | Should -BeGreaterThan 0

        $version = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
        $version.version | Should -Be '1.0.0'
        $version.channel | Should -Be 'stable'
        $version.ps_version | Should -Not -BeNullOrEmpty

        $environment = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json
        $environment.Schema | Should -Be 'Baseline.Environment'
        $environment.OS.Version | Should -Not -BeNullOrEmpty
        $environment.PowerShell.Version | Should -Not -BeNullOrEmpty

        $features = Get-Content -LiteralPath $featuresPath -Raw | ConvertFrom-Json
        $features.Schema | Should -Be 'Baseline.WindowsFeatures'
        @($features.Services | Where-Object Name -eq 'WinRM').Count | Should -Be 1
        $features.CollectionStatus.Defender | Should -Be 'Collected'
        $features.CollectionStatus.OptionalFeatures | Should -Be 'Collected'
        ($features.OptionalFeatures | Where-Object Name -eq 'NetFx3').State | Should -Be 'Enabled'

        $storage = Get-Content -LiteralPath $storagePath -Raw | ConvertFrom-Json
        $storage.Schema | Should -Be 'Baseline.StorageSummary'
        @($storage.Locations | Where-Object Name -eq 'TempBaseline').Count | Should -Be 1
        $runtimeCache = $storage.Locations | Where-Object Name -eq 'RuntimeCache' | Select-Object -First 1
        $runtimeCache.Path | Should -Match '\\Baseline\\RuntimeCache\\RC$'
        $runtimeCache.Path | Should -Not -Match '\\AppData\\Local\\Temp\\Baseline\\RC$'
        @($storage.Locations | Where-Object Name -eq 'LegacyLocalRuntimeCache').Count | Should -Be 1

        $actionContext = Get-Content -LiteralPath $actionContextPath -Raw | ConvertFrom-Json
        $actionContext.Schema | Should -Be 'Baseline.UserActionContext'
        $actionContext.PresetUsed | Should -Be 'Privacy'
        $actionContext.SafeMode | Should -BeTrue
        @($actionContext.SelectedTweaks).Count | Should -Be 2

        $contents = Get-Content -LiteralPath $contentsPath -Raw | ConvertFrom-Json
        @($contents.Files).Count | Should -BeGreaterThan 0
        @($contents.Files | Where-Object Name -eq 'baseline-version.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'environment.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'windows-features.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'storage-summary.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'user-action-context.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'remote-orchestration.jsonl').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'remote-orchestration-summary.txt').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'remote-orchestration-runs.json').Count | Should -Be 0
        @($contents.Files | Where-Object Name -eq 'remote-orchestration-reconciliation.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'remote-orchestration-details.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'validation-evidence.json').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'Logs/Baseline-launch-trace.txt').Count | Should -Be 1
        @($contents.Files | Where-Object Name -eq 'bundle-index.json').Count | Should -Be 1

        $auditLines = @(Get-Content -LiteralPath $auditCopyPath)
        $auditLines.Count | Should -Be 1
        ($auditLines[0] | ConvertFrom-Json).Action | Should -Be 'Compliance'

        Test-Path -LiteralPath (Join-Path $extractDir 'remote-orchestration.jsonl') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'remote-orchestration-summary.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'remote-orchestration-reconciliation.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'remote-orchestration-details.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'validation-evidence.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'Logs/Baseline-launch-trace.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $extractDir 'bundle-index.json') | Should -BeTrue
    }

    It 'packages the selected session log and classifies errors from it' {
        $caseRoot = Join-Path $script:TempRoot 'SelectedSessionLog'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $selectedLogPath = Join-Path $caseRoot 'selected-session.log'
        @(
            '13-05-2026 07:18 INFO: selected session started'
            "13-05-2026 07:18 ERROR: Cannot find path 'C:\Temp\Missing.txt' because it does not exist."
        ) | Set-Content -LiteralPath $selectedLogPath -Encoding UTF8

        $otherLogPath = Join-Path $caseRoot 'current-session.log'
        '13-05-2026 07:18 INFO: current session without errors' | Set-Content -LiteralPath $otherLogPath -Encoding UTF8

        $previousGlobalLogPathVariable = Get-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue
        $Global:LogFilePath = $otherLogPath
        $bundlePath = Join-Path $caseRoot 'selected-session-bundle.zip'
        try {
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -SessionLogPath $selectedLogPath
        }
        finally {
            if ($previousGlobalLogPathVariable) {
                Set-Variable -Name LogFilePath -Scope Global -Value $previousGlobalLogPathVariable.Value
            }
            else {
                Remove-Variable -Name LogFilePath -Scope Global -ErrorAction SilentlyContinue
            }
        }

        $extractDir = Join-Path $caseRoot 'extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $copiedLogPath = Join-Path $extractDir 'Logs\baseline.log'
        Test-Path -LiteralPath $copiedLogPath | Should -BeTrue
        (Get-Content -LiteralPath $copiedLogPath -Raw) | Should -Match 'Missing\.txt'

        $metadata = Get-Content -LiteralPath (Join-Path $extractDir 'metadata.json') -Raw | ConvertFrom-Json
        $metadata.SelectedSessionLog.SourcePath | Should -Be ([System.IO.Path]::GetFullPath($selectedLogPath))
        $metadata.SelectedSessionLog.SourceFileName | Should -Be 'selected-session.log'

        $index = Get-Content -LiteralPath (Join-Path $extractDir 'bundle-index.json') -Raw | ConvertFrom-Json
        $index.Files.DailyLog | Should -Be 'Logs/baseline.log'
        $index.Files.Errors | Should -Be 'errors.json'

        $errors = Get-Content -LiteralPath (Join-Path $extractDir 'errors.json') -Raw | ConvertFrom-Json
        $errors.Source | Should -Be ([System.IO.Path]::GetFullPath($selectedLogPath))
        $errors.Counts.DEPENDENCY | Should -BeGreaterThan 0
    }

    It 'adds deep-link artifacts when a run is targeted' {
        $historyRoot = Join-Path $script:TempRoot 'LocalAppDataDeepLink'
        $historyDir = Join-Path $historyRoot 'Baseline'
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        $historyPath = Join-Path $historyDir 'remote-orchestration.jsonl'
        @(
            '{"Timestamp":"2026-04-14T08:02:00.0000000Z","RecordKind":"Target","MachineName":"TESTHOST","RunId":"run-001","Operation":"RemoteApply","ComputerName":"server03","Status":"Failed","TargetState":"Failed","TerminalState":"Failed","FailedCount":1,"SessionReused":false,"SessionState":"Opened","FailureCategory":"Execution","Retryable":false,"RetryReason":"Execution failed.","Errors":["boom"],"HistoryPath":"C:\\Temp\\remote-orchestration.jsonl"}'
            '{"Timestamp":"2026-04-14T08:02:05.0000000Z","RecordKind":"RunSummary","MachineName":"TESTHOST","RunId":"run-001","Operation":"RemoteApply","Status":"Failed","TargetState":"Failed","TerminalState":"Failed","TargetCount":1,"SucceededCount":0,"FailedCount":1,"SkippedCount":0,"RetryingCount":0,"CancelledCount":0,"TotalAttempts":1,"TotalRetries":0,"SessionReused":false,"SessionState":"Opened","FailureCategory":"Execution","Retryable":false,"RetryReason":"Execution failed.","Errors":["boom"],"HistoryPath":"C:\\Temp\\remote-orchestration.jsonl"}'
        ) | Set-Content -LiteralPath $historyPath -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $historyRoot
        try {
            $result = Export-BaselineSupportBundle -OutputPath (Join-Path $script:TempRoot 'deep-link-bundle.zip') -IncludeTestReport:$false -DeepLinkRunId 'run-001' -DeepLinkComputerName 'server03' -DeepLinkOperation 'RemoteApply'
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath (Join-Path $script:TempRoot 'deep-link-extract') -Force
        $extractDir = Join-Path $script:TempRoot 'deep-link-extract'
        Test-Path -LiteralPath (Join-Path $extractDir 'remote-orchestration-deeplinks.json') | Should -BeTrue

        $contents = Get-Content -LiteralPath (Join-Path $extractDir 'bundle-index.json') -Raw | ConvertFrom-Json
        $contents.Files.RemoteDeepLinks | Should -Be 'remote-orchestration-deeplinks.json'
        $contents.DeepLinks.Count | Should -Be 1
        $contents.DeepLinks[0].RunId | Should -Be 'run-001'
        $contents.DeepLinks[0].Artifacts | Should -Contain 'remote-orchestration-deeplinks.json'
    }

    It 'captures validation evidence and provenance in the bundle' {
        $repoRoot = Join-Path $script:TempRoot 'RepoRoot'
        $testsRoot = Join-Path $repoRoot 'Tests'
        $integrationRoot = Join-Path $testsRoot 'Integration'
        New-Item -ItemType Directory -Path $integrationRoot -Force | Out-Null

        @(
            '{ "generated": "2026-04-14T14:38:31.7842438+02:00", "platform": { "os": "Microsoft Windows NT 10.0.26100.0", "edition": "Core", "psVersion": "7.6.0", "hostname": "SHELDON" }, "layers": { "unit": { "result": "Passed", "passed": 2640, "failed": 0, "skipped": 4 }, "composition": { "result": "Passed", "passed": 27, "failed": 0 } }, "summary": { "overallResult": "Passed" } }'
        ) | Set-Content -LiteralPath (Join-Path $testsRoot 'TestReport.json') -Encoding UTF8

        @(
            '{ "summary": { "testedDesktopEditions": ["Windows 11 Pro (26100)"], "pendingDesktopEditions": [], "serverEditions": ["Windows Server 2022 (CI only)"] } }'
        ) | Set-Content -LiteralPath (Join-Path $integrationRoot 'DesktopMatrixResults.json') -Encoding UTF8

        $previousRepoRoot = $script:SharedHelpersRepoRoot
        $script:SharedHelpersRepoRoot = $repoRoot
        try {
            $report = Get-BaselineValidationEvidenceReport -RepoRoot $repoRoot
            $report.Summary | Should -Be 'unit-tested; desktop-session CI validated; server CI only'
            @($report.ValidationChannels).Count | Should -Be 3
            ($report.ValidationChannels | Where-Object Channel -eq 'unit-tested').Status | Should -Be 'Passed'
            ($report.ValidationChannels | Where-Object Channel -eq 'desktop-session CI validated').Status | Should -Be 'Passed'
            ($report.ValidationChannels | Where-Object Channel -eq 'server CI only').Status | Should -Be 'CI only'

            $result = Export-BaselineSupportBundle -OutputPath (Join-Path $script:TempRoot 'validation-bundle.zip') -IncludeTestReport:$false
            Expand-Archive -LiteralPath $result.OutputPath -DestinationPath (Join-Path $script:TempRoot 'validation-extract') -Force
            $extractDir = Join-Path $script:TempRoot 'validation-extract'

            Test-Path -LiteralPath (Join-Path $extractDir 'validation-evidence.json') | Should -BeTrue
            $validationEvidence = Get-Content -LiteralPath (Join-Path $extractDir 'validation-evidence.json') -Raw | ConvertFrom-Json
            $validationEvidence.Summary | Should -Be 'unit-tested; desktop-session CI validated; server CI only'
            $validationEvidence.ValidationChannels.Count | Should -Be 3

            $metadata = Get-Content -LiteralPath (Join-Path $extractDir 'metadata.json') -Raw | ConvertFrom-Json
            $metadata.ValidationEvidenceSummary | Should -Be 'unit-tested; desktop-session CI validated; server CI only'
            $metadata.ValidationEvidenceChannels.Count | Should -Be 3
        }
        finally {
            $script:SharedHelpersRepoRoot = $previousRepoRoot
        }
    }

    It 'resolves validation evidence from the launcher root when the hydrated runtime has no test artifacts' {
        $runtimeRoot = Join-Path $script:TempRoot 'HydratedRuntimeWithoutTests'
        $launcherRoot = Join-Path $script:TempRoot 'LauncherRootWithTests'
        $testsRoot = Join-Path $launcherRoot 'Tests'
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $testsRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $launcherRoot 'Baseline.exe') -Value '' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $testsRoot 'TestReport.json') -Encoding UTF8 -Value @'
{
  "generated": "2026-04-14T14:38:31.7842438+02:00",
  "platform": {
    "os": "Microsoft Windows NT 10.0.26100.0",
    "psVersion": "5.1.26100.1"
  },
  "layers": {
    "unit": {
      "result": "Passed",
      "passed": 12,
      "failed": 0,
      "skipped": 0
    }
  }
}
'@

        $previousRepoRoot = $script:SharedHelpersRepoRoot
        $previousLauncherPath = $env:BASELINE_LAUNCHER_PATH
        $script:SharedHelpersRepoRoot = $runtimeRoot
        $env:BASELINE_LAUNCHER_PATH = Join-Path $launcherRoot 'Baseline.exe'
        try {
            $resolvedRoot = Get-BaselineSupportBundleValidationEvidenceRoot
            $resolvedRoot | Should -Be $launcherRoot

            $report = Get-BaselineValidationEvidenceReport -RepoRoot $resolvedRoot
            $report.Summary | Should -Be 'unit-tested'
            ($report.ValidationChannels | Where-Object Channel -eq 'unit-tested').Status | Should -Be 'Passed'
        }
        finally {
            $script:SharedHelpersRepoRoot = $previousRepoRoot
            if ($null -eq $previousLauncherPath) {
                Remove-Item Env:\BASELINE_LAUNCHER_PATH -ErrorAction SilentlyContinue
            }
            else {
                $env:BASELINE_LAUNCHER_PATH = $previousLauncherPath
            }
        }
    }

    It 'emits SnapshotDiff.json when pre and post snapshots are supplied' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $script:TempRoot
        try {
            $preSnapshot = [pscustomobject]@{
                Schema        = 'Baseline.StateSnapshot'
                SchemaVersion = 1
                Timestamp     = ([datetime]::UtcNow).AddMinutes(-5).ToString('o')
                MachineName   = 'TESTHOST'
                OSVersion     = 'Windows 11'
                Entries       = @(
                    [pscustomobject]@{
                        Key           = 'FeatureA'
                        Name          = 'Feature A'
                        Function      = 'FeatureA'
                        DetectedValue = 'Disabled'
                    }
                )
            }
            $postSnapshot = [pscustomobject]@{
                Schema        = 'Baseline.StateSnapshot'
                SchemaVersion = 1
                Timestamp     = [datetime]::UtcNow.ToString('o')
                MachineName   = 'TESTHOST'
                OSVersion     = 'Windows 11'
                Entries       = @(
                    [pscustomobject]@{
                        Key           = 'FeatureA'
                        Name          = 'Feature A'
                        Function      = 'FeatureA'
                        DetectedValue = 'Enabled'
                    }
                    [pscustomobject]@{
                        Key           = 'FeatureB'
                        Name          = 'Feature B'
                        Function      = 'FeatureB'
                        DetectedValue = 'Enabled'
                    }
                )
            }

            $bundlePath = Join-Path $script:TempRoot 'snapshot-diff-bundle.zip'
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -PreSnapshot $preSnapshot -PostSnapshot $postSnapshot
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $extractDir = Join-Path $script:TempRoot 'snapshot-diff-extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $snapshotDiffPath = Join-Path $extractDir 'SnapshotDiff.json'
        Test-Path -LiteralPath $snapshotDiffPath | Should -BeTrue

        $snapshotDiff = Get-Content -LiteralPath $snapshotDiffPath -Raw | ConvertFrom-Json
        $snapshotDiff.Schema | Should -Be 'Baseline.SnapshotDiff'
        $snapshotDiff.HasPre | Should -BeTrue
        $snapshotDiff.HasPost | Should -BeTrue
        $snapshotDiff.Diff.ChangedCount | Should -Be 1
        $snapshotDiff.Diff.AddedCount | Should -Be 1
        $snapshotDiff.Diff.RemovedCount | Should -Be 0
    }

    It 'includes the preflight report when the preflight command is available' {
        $bundleContent = Get-BaselineTestSourceText -Path $script:BundleHelpersPath
        $bundleContent | Should -Match 'Invoke-PreflightChecks'
        $bundleContent | Should -Match 'preflight-report\.json'
        $bundleContent | Should -Match 'remote-orchestration\.jsonl'
        $bundleContent | Should -Match 'remote-orchestration-summary\.txt'
        $bundleContent | Should -Match 'Get-BaselineRemoteRunSummaries'
        $bundleContent | Should -Match 'remote-orchestration-runs\.json'
        $bundleContent | Should -Match 'remote-orchestration-reconciliation\.json'
        $bundleContent | Should -Match 'remote-orchestration-details\.json'
        $bundleContent | Should -Match 'Get-BaselineSupportBundleDeepLinks'
        $bundleContent | Should -Match 'remote-orchestration-deeplinks\.json'
        $bundleContent | Should -Match 'validation-evidence\.json'
        $bundleContent | Should -Match 'bundle-index\.json'
    }

    It 'includes generated GUI diagnostics test reports when requested' {
        $bundleContent = Get-BaselineTestSourceText -Path $script:ExportBundleSplitPath
        $bundleContent | Should -Match "\.artifacts\\gui-tests"
        $bundleContent | Should -Match "TestReport_\*\.json"
        $bundleContent | Should -Match "BASELINE_LAUNCHER_PATH"
        $bundleContent | Should -Match "CurrentDomain\.BaseDirectory"
        $bundleContent | Should -Match "TestReports/\{0\}"
        $bundleContent | Should -Match "Tests\\TestReport\.json"
    }

    It 'persists Connect-dialog connectivity results into remote-connectivity.json' {
        $connectivityRoot = Join-Path $script:TempRoot 'LocalAppDataConnectivity'
        New-Item -ItemType Directory -Path (Join-Path $connectivityRoot 'Baseline') -Force | Out-Null
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $connectivityRoot
        try {
            $connectivity = @(
                [pscustomobject]@{ ComputerName = 'PC01'; Reachable = $true;  Status = 'Reachable';   BlockedByPolicy = $false; Error = $null;                ConnectionMethod = 'WinRM' }
                [pscustomobject]@{ ComputerName = 'PC02'; Reachable = $false; Status = 'Unreachable'; BlockedByPolicy = $false; Error = 'WinRM not enabled';  ConnectionMethod = 'WinRMHttps' }
            )
            $bundlePath = Join-Path $script:TempRoot 'connectivity-bundle.zip'
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -ConnectivityResults $connectivity
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $extractDir = Join-Path $script:TempRoot 'connectivity-extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $connectivityPath = Join-Path $extractDir 'remote-connectivity.json'
        Test-Path -LiteralPath $connectivityPath | Should -BeTrue

        $payload = Get-Content -LiteralPath $connectivityPath -Raw | ConvertFrom-Json
        $payload.Schema | Should -Be 'Baseline.RemoteConnectivity'
        $payload.SchemaVersion | Should -Be 1
        @($payload.Results).Count | Should -Be 2
        $payload.Results[0].ComputerName | Should -Be 'PC01'
        $payload.Results[1].ConnectionMethod | Should -Be 'WinRMHttps'

        $index = Get-Content -LiteralPath (Join-Path $extractDir 'bundle-index.json') -Raw | ConvertFrom-Json
        $index.Files.RemoteConnectivity | Should -Be 'remote-connectivity.json'
    }

    It 'omits remote-connectivity.json when no ConnectivityResults are supplied' {
        $emptyRoot = Join-Path $script:TempRoot 'LocalAppDataNoConnectivity'
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'Baseline') -Force | Out-Null
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $emptyRoot
        try {
            $bundlePath = Join-Path $script:TempRoot 'no-connectivity-bundle.zip'
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $extractDir = Join-Path $script:TempRoot 'no-connectivity-extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        Test-Path -LiteralPath (Join-Path $extractDir 'remote-connectivity.json') | Should -BeFalse

        $index = Get-Content -LiteralPath (Join-Path $extractDir 'bundle-index.json') -Raw | ConvertFrom-Json
        $hasConnectivityField = [bool]($index.Files.PSObject.Properties.Name -contains 'RemoteConnectivity')
        $hasConnectivityField | Should -BeFalse
    }

    It 'includes supplied Windows Update status in support bundle metadata and artifacts' {
        $windowsUpdateStatus = [pscustomobject]@{
            Schema      = 'Baseline.WindowsUpdateStatus'
            GeneratedAt = [System.DateTime]::UtcNow.ToString('o')
            Succeeded   = $true
            Summary     = [pscustomobject]@{
                Total    = 3
                Critical = 1
                Security = 1
                Drivers  = 0
                Optional = 1
            }
            AvailableUpdates = @()
            RecentHistory    = @()
            LastScheduledRun = $null
        }

        $statusRoot = Join-Path $script:TempRoot 'LocalAppDataWindowsUpdateStatus'
        New-Item -ItemType Directory -Path (Join-Path $statusRoot 'Baseline') -Force | Out-Null
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $statusRoot
        try {
            $bundlePath = Join-Path $script:TempRoot 'windows-update-status-bundle.zip'
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -WindowsUpdateStatus $windowsUpdateStatus
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $extractDir = Join-Path $script:TempRoot 'windows-update-status-extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $statusPath = Join-Path $extractDir 'windows-update-status.json'
        Test-Path -LiteralPath $statusPath | Should -BeTrue

        $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $status.Schema | Should -Be 'Baseline.WindowsUpdateStatus'
        $status.Succeeded | Should -BeTrue
        $status.Summary.Critical | Should -Be 1
        $status.Summary.Security | Should -Be 1

        $metadata = Get-Content -LiteralPath (Join-Path $extractDir 'metadata.json') -Raw | ConvertFrom-Json
        $metadata.WindowsUpdateStatusSucceeded | Should -BeTrue
        $metadata.WindowsUpdateSummary.Total | Should -Be 3

        $index = Get-Content -LiteralPath (Join-Path $extractDir 'bundle-index.json') -Raw | ConvertFrom-Json
        $index.Files.WindowsUpdateStatus | Should -Be 'windows-update-status.json'
    }

    It 'does not run live Windows Update status collection during export' {
        $script:WindowsUpdateStatusWasCalled = $false
        function Get-WindowsUpdateStatus {
            $script:WindowsUpdateStatusWasCalled = $true
            throw 'Export should not call live Windows Update status collection.'
        }

        $script:SupportBundleWindowsUpdateProgressEvents = New-Object 'System.Collections.Generic.List[object]'
        $bundlePath = Join-Path $script:TempRoot 'windows-update-not-collected-bundle.zip'
        try {
            $result = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -ProgressCallback {
                param(
                    [string]$Stage,
                    [string]$Message
                )

                $script:SupportBundleWindowsUpdateProgressEvents.Add([pscustomobject]@{
                    Stage   = $Stage
                    Message = $Message
                })
            }
        }
        finally {
            Remove-Item -Path Function:\Get-WindowsUpdateStatus -ErrorAction SilentlyContinue
        }

        $script:WindowsUpdateStatusWasCalled | Should -BeFalse

        $extractDir = Join-Path $script:TempRoot 'windows-update-not-collected-extract'
        Expand-Archive -LiteralPath $result.OutputPath -DestinationPath $extractDir -Force

        $status = Get-Content -LiteralPath (Join-Path $extractDir 'windows-update-status.json') -Raw | ConvertFrom-Json
        $status.Schema | Should -Be 'Baseline.WindowsUpdateStatus'
        $status.Collected | Should -BeFalse
        $status.CollectionState | Should -Be 'NotCollected'
        $status.Reason | Should -Match 'does not run live Windows Update status checks'

        $metadata = Get-Content -LiteralPath (Join-Path $extractDir 'metadata.json') -Raw | ConvertFrom-Json
        $metadata.WindowsUpdateStatusSucceeded | Should -BeNullOrEmpty

        $messages = @($script:SupportBundleWindowsUpdateProgressEvents | ForEach-Object { $_.Message })
        $messages | Should -Contain 'Recording Windows Update status snapshot...'
    }

    It 'collects Windows feature state through bounded child collectors' {
        $script:SupportBundleWindowsFeatureCollectorCalls = New-Object 'System.Collections.Generic.List[object]'
        $script:SupportBundleWindowsFeatureProgressEvents = New-Object 'System.Collections.Generic.List[object]'

        function Get-Service {
            param([string]$Name)

            return [pscustomobject]@{
                Status    = 'Running'
                StartType = 'Automatic'
            }
        }

        $processCaptureScript = {
            param(
                [string]$FilePath,
                [object[]]$ArgumentList,
                [int]$TimeoutSeconds
            )

            $scriptText = if ($ArgumentList -contains '-File') { Get-Content -LiteralPath ([string]$ArgumentList[-1]) -Raw -Encoding UTF8 } else { [string]$ArgumentList[-1] }
            $script:SupportBundleWindowsFeatureCollectorCalls.Add([pscustomobject]@{
                TimeoutSeconds = $TimeoutSeconds
                ScriptText     = $scriptText
            })

            if ($scriptText -match 'Get-MpComputerStatus') {
                return [pscustomobject]@{
                    ExitCode       = 0
                    StandardOutput = '{"AMServiceEnabled":true,"AntivirusEnabled":true,"RealTimeProtectionEnabled":false,"IoavProtectionEnabled":true,"NISEnabled":true,"AntispywareEnabled":true}'
                    StandardError  = ''
                }
            }

            if ($scriptText -match 'Get-WindowsOptionalFeature -Online') {
                return [pscustomobject]@{
                    ExitCode       = 0
                    StandardOutput = '[{"Name":"NetFx3","State":"Enabled"},{"Name":"SMB1Protocol","State":"Disabled"}]'
                    StandardError  = ''
                }
            }

            throw "Unexpected collector script: $scriptText"
        }

        try {
            $features = New-BaselineSupportBundleWindowsFeatures -ProcessCaptureScript $processCaptureScript -ProgressCallback {
                param(
                    [string]$Stage,
                    [string]$Message
                )

                $script:SupportBundleWindowsFeatureProgressEvents.Add([pscustomobject]@{
                    Stage   = $Stage
                    Message = $Message
                })
            }
        }
        finally {
            Remove-Item -Path Function:\Get-Service -ErrorAction SilentlyContinue
            Set-Item -Path Function:\Global:Invoke-BaselineSupportBundleProcessCapture -Value $script:SupportBundleUnitProcessCaptureStub
        }

        $features.CollectionStatus.Defender | Should -Be 'Collected'
        $features.CollectionStatus.OptionalFeatures | Should -Be 'Collected'
        $features.Defender.AMServiceEnabled | Should -BeTrue
        ($features.OptionalFeatures | Where-Object Name -eq 'NetFx3').State | Should -Be 'Enabled'
        ($features.OptionalFeatures | Where-Object Name -eq 'SMB1Protocol').State | Should -Be 'Disabled'

        $script:SupportBundleWindowsFeatureCollectorCalls.Count | Should -Be 2
        @($script:SupportBundleWindowsFeatureCollectorCalls | Where-Object TimeoutSeconds -eq 10).Count | Should -Be 1
        @($script:SupportBundleWindowsFeatureCollectorCalls | Where-Object TimeoutSeconds -eq 20).Count | Should -Be 1
        ($script:SupportBundleWindowsFeatureCollectorCalls | Select-Object -ExpandProperty ScriptText) -join "`n" | Should -Not -Match '-FeatureName'

        $stages = @($script:SupportBundleWindowsFeatureProgressEvents | ForEach-Object { $_.Stage })
        $stages | Should -Contain 'WindowsFeatures.Services'
        $stages | Should -Contain 'WindowsFeatures.Defender'
        $stages | Should -Contain 'WindowsFeatures.OptionalFeatures'
    }

    It 'reports support bundle progress stages to callers' {
        $script:SupportBundleProgressEvents = New-Object 'System.Collections.Generic.List[object]'
        $bundlePath = Join-Path $script:TempRoot 'progress-callback-bundle.zip'
        $null = Export-BaselineSupportBundle -OutputPath $bundlePath -IncludeTestReport:$false -ProgressCallback {
            param(
                [string]$Stage,
                [string]$Message
            )

            $script:SupportBundleProgressEvents.Add([pscustomobject]@{
                Stage   = $Stage
                Message = $Message
            })
        }

        $stages = @($script:SupportBundleProgressEvents | ForEach-Object { $_.Stage })
        $messages = @($script:SupportBundleProgressEvents | ForEach-Object { $_.Message })
        $stages | Should -Contain 'Prepare'
        $stages | Should -Contain 'WindowsUpdate'
        $stages | Should -Contain 'Compress'
        $messages | Should -Contain 'Creating ZIP archive...'
    }
}
