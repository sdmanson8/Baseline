Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    function Test-GuiObjectField {
        param([object]$Object, [string]$FieldName)
        if ($null -eq $Object) { return $false }
        if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($FieldName) }
        return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
    }

    function Get-BaselineLocalizedString {
        param(
            [string]$Key,
            [string]$Fallback,
            [object[]]$FormatArgs = @()
        )

        if ($FormatArgs.Count -gt 0)
        {
            return ($Fallback -f $FormatArgs)
        }

        return $Fallback
    }

    function LogInfo { param([object]$Message) }
    function LogWarning { param([object]$Message) }
    function LogError { param([object]$Message) }

    $filePath = Join-Path $PSScriptRoot '../../Module/GUIExecution.psm1'
    $script:GuiExecutionContent = Get-BaselineTestSourceText -Path $filePath
    $script:AppExecutionRunContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/ExecutionOrchestration/ExecutionRunOrchestration/Start-GuiAppExecutionRun/Start-GuiAppExecutionRun.ps1')
    $script:ExecutionWorkerContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUIExecution/Start-GuiExecutionWorker/Start-GuiExecutionWorker.ps1')
    $script:AppExecutionWorkerContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUIExecution/Start-GuiAppExecutionWorker/Start-GuiAppExecutionWorker.ps1')
    $script:SharedHelpersContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/SharedHelpers.psm1')
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions)
    {
        Invoke-Expression $fn.Extent.Text
    }
}

Describe 'Get-GuiExecutionActionTimeoutSeconds' {
    It 'honors the manifest timeout override when present' {
        $entry = [pscustomobject]@{
            TimeoutSeconds = 42
            Function = 'Anything'
            Type = 'Toggle'
        }

        Get-GuiExecutionActionTimeoutSeconds -Entry $entry -ExecutionClass 'Tweak' | Should -Be 42
    }

    It 'uses the scheduled tasks timeout bucket for task tweaks' {
        $entry = [pscustomobject]@{
            Function = 'ScheduledTasks'
            Type = 'Action'
        }

        Get-GuiExecutionActionTimeoutSeconds -Entry $entry -ExecutionClass 'Tweak' | Should -Be 120
    }

    It 'uses the app default timeout bucket for applications' {
        Get-GuiExecutionActionTimeoutSeconds -Entry ([pscustomobject]@{ Name = 'Firefox' }) -ExecutionClass 'App' | Should -Be 900
    }

    It 'uses the UWPApps manifest timeout override for bulk app operations' {
        $uwpManifestPath = Join-Path $PSScriptRoot '../../Module/Data/UWPApps.json'
        $uwpManifest = Get-BaselineTestSourceText -Path $uwpManifestPath | ConvertFrom-Json
        $uwpEntry = @($uwpManifest.Entries | Where-Object Function -eq 'UWPApps' | Select-Object -First 1)[0]

        $uwpEntry.TimeoutSeconds | Should -Be 1800
        Get-GuiExecutionActionTimeoutSeconds -Entry $uwpEntry -ExecutionClass 'Tweak' | Should -Be 1800
    }

    It 'uses the explicit PowerShellV2 optional-feature timeout from the manifest' {
        $osHardeningManifestPath = Join-Path $PSScriptRoot '../../Module/Data/OSHardening.json'
        $osHardeningManifest = Get-BaselineTestSourceText -Path $osHardeningManifestPath | ConvertFrom-Json
        $powerShellV2Entry = @($osHardeningManifest.Entries | Where-Object Function -eq 'PowerShellV2' | Select-Object -First 1)[0]

        $powerShellV2Entry.TimeoutSeconds | Should -Be 300
        Get-GuiExecutionActionTimeoutSeconds -Entry $powerShellV2Entry -ExecutionClass 'Tweak' | Should -Be 300
    }

    It 'uses the explicit Windows Update product service timeout from the manifest' {
        $privacyManifestPath = Join-Path $PSScriptRoot '../../Module/Data/PrivacyTelemetry.json'
        $privacyManifest = Get-BaselineTestSourceText -Path $privacyManifestPath | ConvertFrom-Json
        $updateMSProductsEntry = @($privacyManifest.Entries | Where-Object Function -eq 'UpdateMSProducts' | Select-Object -First 1)[0]

        $updateMSProductsEntry.TimeoutSeconds | Should -Be 300
        Get-GuiExecutionActionTimeoutSeconds -Entry $updateMSProductsEntry -ExecutionClass 'Tweak' | Should -Be 300
    }

    It 'uses explicit timeouts for long-running Windows feature and capability tweaks' {
        $defenderManifestPath = Join-Path $PSScriptRoot '../../Module/Data/Defender.json'
        $systemManifestPath = Join-Path $PSScriptRoot '../../Module/Data/System.json'
        $defenderManifest = Get-BaselineTestSourceText -Path $defenderManifestPath | ConvertFrom-Json
        $systemManifest = Get-BaselineTestSourceText -Path $systemManifestPath | ConvertFrom-Json

        $defenderAppGuardEntry = @($defenderManifest.Entries | Where-Object Function -eq 'DefenderAppGuard' | Select-Object -First 1)[0]
        $windowsSandboxEntry = @($defenderManifest.Entries | Where-Object Function -eq 'WindowsSandbox' | Select-Object -First 1)[0]
        $openSshEntry = @($systemManifest.Entries | Where-Object Function -eq 'OpenSSHServer' | Select-Object -First 1)[0]
        $reservedStorageEntry = @($systemManifest.Entries | Where-Object Function -eq 'ReservedStorage' | Select-Object -First 1)[0]

        Get-GuiExecutionActionTimeoutSeconds -Entry $defenderAppGuardEntry -ExecutionClass 'Tweak' | Should -Be 600
        Get-GuiExecutionActionTimeoutSeconds -Entry $windowsSandboxEntry -ExecutionClass 'Tweak' | Should -Be 600
        Get-GuiExecutionActionTimeoutSeconds -Entry $openSshEntry -ExecutionClass 'Tweak' | Should -Be 900
        Get-GuiExecutionActionTimeoutSeconds -Entry $reservedStorageEntry -ExecutionClass 'Tweak' | Should -Be 120
    }

    It 'uses a longer wrapper timeout for multi-capability Windows capability runs' {
        $entry = [pscustomobject]@{
            Function = 'WindowsCapabilities'
            Type = 'Choice'
        }

        Get-GuiExecutionActionTimeoutSeconds -Entry $entry -ExecutionClass 'Tweak' | Should -Be 3600
    }

    It 'validates choice values against manifest options before invoking the command' {
        $script:GuiExecutionContent | Should -Match '\$choiceOptions = @\(\)'
        $script:GuiExecutionContent | Should -Match '\$choiceParam -notin \$choiceOptions'
        $script:GuiExecutionContent | Should -Match 'The choice selection for'
        $script:GuiExecutionContent | Should -Match 'is invalid'
        $script:GuiExecutionContent | Should -Match 'Expected one of'
    }
}

Describe 'Get-GuiPreRunSnapshotTimeoutSeconds' {
    It 'uses the explicit pre-run snapshot deadline by default' {
        Get-GuiPreRunSnapshotTimeoutSeconds | Should -Be 120
    }

    It 'honors the environment override when it is positive' {
        $oldValue = [System.Environment]::GetEnvironmentVariable('BASELINE_PRE_RUN_SNAPSHOT_TIMEOUT_SECONDS')
        try
        {
            [System.Environment]::SetEnvironmentVariable('BASELINE_PRE_RUN_SNAPSHOT_TIMEOUT_SECONDS', '7', [System.EnvironmentVariableTarget]::Process)
            Get-GuiPreRunSnapshotTimeoutSeconds | Should -Be 7
        }
        finally
        {
            [System.Environment]::SetEnvironmentVariable('BASELINE_PRE_RUN_SNAPSHOT_TIMEOUT_SECONDS', $oldValue, [System.EnvironmentVariableTarget]::Process)
        }
    }
}

Describe 'Test-GuiExecutionInvocationTimedOut' {
    It 'returns true for explicit timeout results' {
        $result = [pscustomobject]@{
            TimedOut = $true
            ErrorTypeName = $null
        }

        Test-GuiExecutionInvocationTimedOut -InvocationResult $result | Should -Be $true
    }

    It 'returns true when the invocation failed with a timeout exception type' {
        $result = [pscustomobject]@{
            TimedOut = $false
            ErrorTypeName = 'System.TimeoutException'
        }

        Test-GuiExecutionInvocationTimedOut -InvocationResult $result | Should -Be $true
    }

    It 'returns false for ordinary failures' {
        $result = [pscustomobject]@{
            TimedOut = $false
            ErrorTypeName = 'System.InvalidOperationException'
        }

        Test-GuiExecutionInvocationTimedOut -InvocationResult $result | Should -Be $false
    }
}

Describe 'New-GuiExecutionAppBatchResult' {
    It 'returns a partial outcome when some apps fail and others succeed' {
        $route = [pscustomobject]@{
            SelectionKey = 'winget:code'
            WinGetId = 'Microsoft.VisualStudioCode'
            ChocoId = $null
            DisplayName = 'Visual Studio Code'
            EntityType = 'winget'
            Route = 'winget'
            SelectedSource = 'winget'
            PackageId = 'Microsoft.VisualStudioCode'
        }

        $result = New-GuiExecutionAppBatchResult -Action 'Install' -SuccessfulApps @(
            New-GuiExecutionAppBatchEntry -Route $route
        ) -FailedApps @(
            New-GuiExecutionAppBatchEntry -Route $route -Error 'Timed out after 900 seconds.'
        )

        $result.Outcome | Should -Be 'Partial'
        $result.SuccessCount | Should -Be 1
        $result.FailureCount | Should -Be 1
    }

    It 'does not reject the first app result because the target collection is empty' {
        $script:AppExecutionWorkerContent | Should -Match 'if \(\$null -eq \$Collection -or \$null -eq \$Route\)'
        $script:AppExecutionWorkerContent | Should -Not -Match 'if \(-not \$Collection -or -not \$Route\)'
    }
}

Describe 'GUI execution action host exports and logging bootstrap' {
    It 'exports the GUI execution helpers used by background execution runspaces' {
        $script:GuiExecutionContent | Should -Match "'Test-GuiExecutionObjectField'"
        $script:GuiExecutionContent | Should -Match "'Get-GuiExecutionActionTimeoutSeconds'"
        $script:GuiExecutionContent | Should -Match "'Get-GuiPreRunSnapshotTimeoutSeconds'"
        $script:GuiExecutionContent | Should -Match "'Test-GuiExecutionCriticalAction'"
        $script:GuiExecutionContent | Should -Match "'Test-GuiExecutionInvocationTimedOut'"
        $script:GuiExecutionContent | Should -Match "'New-GuiExecutionAppBatchEntry'"
        $script:GuiExecutionContent | Should -Match "'New-GuiExecutionAppBatchResult'"
        $script:GuiExecutionContent | Should -Match "'New-GuiExecutionActionHost'"
        $script:GuiExecutionContent | Should -Match "'Close-GuiExecutionActionHost'"
        $script:GuiExecutionContent | Should -Match "'Invoke-GuiExecutionActionHostCommand'"
        $script:GuiExecutionContent | Should -Match "'Get-GuiExecutionAppActionVerb'"
        $script:GuiExecutionContent | Should -Match "'Resolve-GuiAppTimeoutVerification'"
        $script:GuiExecutionContent | Should -Match "'Write-GuiExecutionTimeoutRecord'"
        $script:GuiExecutionContent | Should -Match "'Invoke-GuiPreRunSnapshotCapture'"
    }

    It 'allows an empty log mode for standard pre-run snapshot capture' {
        $script:GuiExecutionContent | Should -Match '(?s)function Invoke-GuiPreRunSnapshotCapture.*?\[AllowEmptyString\(\)\]\s*\r?\n\s*\[string\]\$LogMode'
    }

    It 'requests snapshot worker stop asynchronously when the pre-run snapshot deadline is reached' {
        $preRunStopFunction = [regex]::Match($script:GuiExecutionContent, '(?s)function Stop-GuiPreRunSnapshotCaptureAsync.*?(?=function Invoke-GuiPreRunSnapshotCapture)').Value
        $preRunStopFunction | Should -Match 'BeginStop\(\$null, \$null\)'
        $preRunStopFunction | Should -Match 'EndStop\(\$stopResult\)'
        $preRunStopFunction | Should -Not -Match '\$Worker\.PowerShell\.Stop\(\)'
    }

    It 'requests action-host timeout stops asynchronously without blocking the timeout path' {
        $script:GuiExecutionContent | Should -Match 'function Request-GuiExecutionPowerShellStopAsync'
        $script:GuiExecutionContent | Should -Match '\$PowerShell\.BeginStop\(\$null, \$null\)'

        $actionHostFunction = [regex]::Match($script:GuiExecutionContent, '(?s)function Invoke-GuiExecutionActionHostCommand.*?(?=function Test-GuiExecutionInvocationTimedOut)').Value
        $actionHostFunction | Should -Match "Request-GuiExecutionPowerShellStopAsync -PowerShell \`$powerShell -Source 'GUIExecution\.ActionHostCommand\.TimeoutStop'"
        $actionHostFunction | Should -Match "Request-GuiExecutionPowerShellStopAsync -PowerShell \`$powerShell -Source 'GUIExecution\.ActionHostCommand\.AbortStop'"
        $actionHostFunction | Should -Match 'did not stop within the bounded timeout cleanup window'
        $actionHostFunction | Should -Not -Match '\$powerShell\.Stop\(\)'
    }

    It 'does not convert completed app commands into failures because of unrelated global error records' {
        $actionHostFunction = [regex]::Match($script:GuiExecutionContent, '(?s)function Invoke-GuiExecutionActionHostCommand.*?(?=function Test-GuiExecutionInvocationTimedOut)').Value
        $actionHostFunction | Should -Match '\$results = @\(\$powerShell\.EndInvoke\(\$asyncResult\)\)'
        $actionHostFunction | Should -Match 'Succeeded\s+=\s+\$true'
        $actionHostFunction | Should -Not -Match 'Get-NewUnhandledErrorRecords -BaselineCount \$errorBaseline'
    }

    It 'abandons timed-out action hosts with non-blocking runspace close before creating a replacement host' {
        $script:GuiExecutionContent | Should -Match '\[switch\]\$NonBlocking'
        $script:GuiExecutionContent | Should -Match '\$runspace\.CloseAsync\(\)'
        $script:GuiExecutionContent | Should -Match 'CloseActionHost\.CloseRunspaceAsync'
        $script:ExecutionWorkerContent | Should -Match 'Close-GuiExecutionActionHost -ActionHost \$actionHost -NonBlocking'
        $script:ExecutionWorkerContent | Should -Match '(?s)finally.*Close-GuiExecutionActionHost -ActionHost \$actionHost -NonBlocking.*\$Script:RunState\[''Done''\] = \$true'
    }

    It 'preseeds the requested log path before importing the loader in background runspaces' {
        ([regex]::Matches($script:GuiExecutionContent, '\$Global:LogFilePath = \$bgLogFilePath\s*\r?\n\s*Import-Module \$bgLoaderPath -Force -Global -ErrorAction Stop')).Count | Should -Be 3
    }

    It 'loads GUI execution helpers into the app worker runspace before creating action hosts' {
        $script:GuiExecutionContent | Should -Match '\$guiExecutionModulePath = Join-Path \$PSScriptRoot ''GUIExecution\.psm1'''
        $script:GuiExecutionContent | Should -Match '\$actionHostLoaderPath = Join-Path \$PSScriptRoot ''Baseline\.psm1'''
        $script:GuiExecutionContent | Should -Match 'SessionStateProxy\.SetVariable\(''bgGuiExecutionModulePath'''
        $script:GuiExecutionContent | Should -Match 'SessionStateProxy\.SetVariable\(''bgActionHostLoaderPath'''
        $script:AppExecutionWorkerContent | Should -Match 'Import-Module \$bgGuiExecutionModulePath -Force -Global -DisableNameChecking'
        ([regex]::Matches($script:AppExecutionWorkerContent, '-LoaderPath \$bgActionHostLoaderPath')).Count | Should -Be 3
        ([regex]::Matches($script:AppExecutionWorkerContent, '-LogQueue \$null')).Count | Should -Be 3
        $script:AppExecutionWorkerContent | Should -Not -Match '-LoaderPath \$bgLoaderPath'
        $script:AppExecutionWorkerContent | Should -Not -Match '-LogQueue \$\(if \(\$Script:RunState\)'
        $script:AppExecutionWorkerContent | Should -Match 'Test-GuiExecutionObjectField -Object \$verificationResult'
    }

    It 'defines shared object-field helpers and seeds operation mode into runspaces' {
        $script:SharedHelpersContent | Should -Match 'function Test-GuiObjectField'
        $script:SharedHelpersContent | Should -Match "'Test-GuiObjectField'"
        $script:SharedHelpersContent | Should -Match "'Update-BaselineManifestExecutionSupport'"
        $script:GuiExecutionContent | Should -Match 'function Test-GuiExecutionObjectField'
        $script:GuiExecutionContent | Should -Match 'function Get-GuiExecutionOperationMode'
        $script:GuiExecutionContent | Should -Match 'function Get-GuiExecutionThemeSnapshot'
        $script:GuiExecutionContent | Should -Match "SessionStateProxy\.SetVariable\('bgCurrentTheme'"
        $script:GuiExecutionContent | Should -Match "SessionStateProxy\.SetVariable\('bgOperationMode'"
        $script:GuiExecutionContent | Should -Match 'OperationMode\s+=\s+\$resolvedOperationMode'
        $script:GuiExecutionContent | Should -Match 'Set-BaselineOperationMode -Mode \(\[string\]\$bgOperationMode\)'
        $script:GuiExecutionContent | Should -Match '\$Global:BaselineCurrentTheme = \$bgCurrentTheme'
        $script:GuiExecutionContent | Should -Match '\$Global:BaselineOperationMode = \[string\]\$InvocationOperationMode'
        $script:GuiExecutionContent | Should -Match 'Set-BaselineOperationMode -Mode \(\[string\]\$InvocationOperationMode\)'
    }

    It 'prevents later app progress events from downgrading failed or partial outcomes' {
        $script:AppExecutionRunContent | Should -Match 'function Script:Get-GuiAppProgressOutcomeRank'
        $script:AppExecutionRunContent | Should -Match 'function Script:Set-GuiAppProgressOutcome'
        $script:AppExecutionRunContent | Should -Match 'Get-GuiAppProgressOutcomeRank -Status \$Status'
        $script:AppExecutionRunContent | Should -Match 'Get-GuiAppProgressOutcomeRank -Status \$currentStatus'
        $script:AppExecutionRunContent | Should -Match 'Set-GuiAppProgressOutcome -RunState \$Script:RunState -Status \$appStatus'
        $script:AppExecutionRunContent | Should -Match 'Set-GuiAppProgressOutcome -RunState \$Script:RunState -Status \$status'
        $script:AppExecutionRunContent | Should -Match '\$Script:RunState\[''AppResult''\].*FieldName ''Outcome'''
        $script:AppExecutionRunContent | Should -Match '\$Script:RunState\[''AppOutcome''\] = \[string\]\$Script:RunState\[''AppResult''\]\.Outcome'
    }
}
