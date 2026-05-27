<#
    .SYNOPSIS
    Internal logging module for Baseline.

    .VERSION
    1.0.0

    .DATE
    21.03.2026 - Initial Release
    06.04.2026 - Major changes to the GUI, and added more features
    25.05.2026

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Initializes the log file used by the script and provides helper functions for writing
    informational, warning, and error messages to that log. This module is internal
    runtime plumbing, not end-user guidance.
#>

using module .\SharedHelpers.psm1

# Log files live under the Baseline state root with a date folder and a
# timestamped filename so each launch gets a distinct session log path.
$script:LogFilePath = $null
$script:LogLock = New-Object System.Threading.Mutex($false, "Global\BaselineLogLock")
$script:LogStatistics = @{
    Info = 0
    Warning = 0
    Error = 0
    Debug = 0
}
# DEBUG entries are gated: they are only emitted when Debug Mode is on
# (Settings → Diagnostics, persisted as DebugLoggingEnabled in Baseline-user-prefs.json).
# When off, Write-BaselineDebug returns immediately with no I/O unless the
# caller explicitly marks the entry as an always-on support diagnostic.
$script:DebugLoggingEnabled = $false
# RunId is a per-session correlation GUID. Generated lazily on first read so
# unit tests that import the module without bootstrapping still get a stable
# value. The short form (first 8 chars) is what's stamped onto every log line;
# the full GUID is what the bundle metadata records and what bundle readers
# already filter on (see Get-BaselineSupportBundleDeepLinks RunId param).
$script:RunId = $null
$script:RunIdShort = $null
$script:UILogHandler = $null
$script:ConsoleStatusContext = $null
$script:OperationScopeStack = [System.Collections.Generic.List[object]]::new()
$script:LogMode = $null
$script:LogScope = 'Baseline'
$script:DefaultLogMutexTimeoutMs = 5000
$script:LogMutexRetryBackoffMs = @(100, 250, 500)
$script:PendingLogMessages = [System.Collections.Generic.List[string]]::new()
$script:PendingLogMessagesSyncRoot = [object]::new()
$script:UILogWarningCache = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:SessionStatisticsSyncRoot = [object]::new()
$script:SessionStatistics = @{
    SessionStartTime    = $null
    PresetName          = $null
    TweaksSelected      = 0
    PreviewRunCount     = 0
    ApplyRunCount       = 0
    SucceededCount      = 0
    FailedCount         = 0
    SkippedCount        = 0
    NotApplicableCount  = 0
    NotRunCount         = 0
    IsGUI               = $false
    GameModeActive      = $false
    GameModeProfile     = $null
}

<#
    .SYNOPSIS
    Gets baseline log directory.

    #>

function Get-BaselineLogDirectory {
    param(
        [string]$FallbackRoot = $env:TEMP
    )

    $localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData))
    {
        $localAppData = $FallbackRoot
    }

    $logDirectory = Join-Path $localAppData 'Temp\Baseline\Logs'
    try
    {
        [void](New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop)
        return $logDirectory
    }
    catch
    {
        return $FallbackRoot
    }
}

function Resolve-BaselineLogDirectory {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RequestedDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DefaultDirectory
    )

    if ([string]::IsNullOrWhiteSpace($RequestedDirectory))
    {
        return $DefaultDirectory
    }

    try
    {
        $resolvedDirectory = [System.IO.Path]::GetFullPath($RequestedDirectory.Trim())
        if (-not [System.IO.Directory]::Exists($resolvedDirectory))
        {
            [void][System.IO.Directory]::CreateDirectory($resolvedDirectory)
        }
        return $resolvedDirectory
    }
    catch
    {
        return $DefaultDirectory
    }
}

function Get-BaselineStoredLogDirectoryPreference {
    $localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { return '' }

    $preferencesPath = [System.IO.Path]::Combine($localAppData, 'Baseline', 'UserState', 'Profiles', 'Baseline-user-prefs.json')
    if (-not [System.IO.File]::Exists($preferencesPath)) { return '' }

    try
    {
        $raw = [System.IO.File]::ReadAllText($preferencesPath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }

        $parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if ($parsed -and $parsed.Values -and $parsed.Values.PSObject.Properties['LogFileDirectory'])
        {
            return [string]$parsed.Values.LogFileDirectory
        }
    }
    catch
    {
        return ''
    }

    return ''
}

function Get-BaselineConfiguredLogDirectory {
    param(
        [string]$DefaultDirectory,
        [string]$FallbackRoot = $env:TEMP
    )

    if ([string]::IsNullOrWhiteSpace($DefaultDirectory))
    {
        $DefaultDirectory = Get-BaselineLogDirectory -FallbackRoot $FallbackRoot
    }

    $configuredDirectory = Get-BaselineStoredLogDirectoryPreference
    return (Resolve-BaselineLogDirectory -RequestedDirectory $configuredDirectory -DefaultDirectory $DefaultDirectory)
}

<#
    .SYNOPSIS
    Creates baseline session log path.

    #>

function New-BaselineSessionLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OsName,

        [Parameter()]
        [datetime]$SessionStart = [DateTime]::Now
    )

    $sessionDirectory = [System.IO.Path]::Combine($LogDirectory, $SessionStart.ToString('yyyy-MM-dd'))
    $sessionFileName = '{0} Baseline - Utility for {1}.log' -f $SessionStart.ToString('HH-mm-ss'), $OsName
    return [System.IO.Path]::Combine($sessionDirectory, $sessionFileName)
}

<#
    .SYNOPSIS
    Writes UI log warning.

    #>

function Write-UILogWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $shouldWrite = $true
    if ($script:UILogWarningCache) {
        try {
            $shouldWrite = $script:UILogWarningCache.Add($Message)
        }
        catch {
            $shouldWrite = $true
        }
    }

    if ($shouldWrite) {
        Write-Warning $Message
    }
}

<#
    .SYNOPSIS
    Send UI log entry.

    #>

function Send-UILogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$Entry
    )

    if ($script:UILogHandler) {
        try {
            & $script:UILogHandler $Entry
            return $true
        }
        catch {
            Write-UILogWarning "Baseline UI log handler failed: $($_.Exception.Message)"
        }
    }

    $queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
    if ($queue) {
        try {
            $queue.Enqueue($Entry)
            return $true
        }
        catch {
            Write-UILogWarning "Baseline UI log queue enqueue failed: $($_.Exception.Message)"
        }
    }

    return $false
}

<#
    .SYNOPSIS
    Reset log statistics.

    #>

function Reset-LogStatistics {
    $script:LogStatistics = @{
        Info = 0
        Warning = 0
        Error = 0
        Debug = 0
    }
}

<#
    .SYNOPSIS
    Sets log mode.

    #>
function Set-LogMode {
    param(
        [string]$Mode
    )

    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $script:LogMode = $null
        return
    }

    $script:LogMode = $Mode.Trim()
}

<#
    .SYNOPSIS
    Clears log mode.

    #>

function Clear-LogMode {
    $script:LogMode = $null
}

function ConvertTo-BaselineLogScopeText {
    param(
        [AllowNull()]
        [object]$Scope
    )

    if ($null -eq $Scope) { return '' }

    $scopeText = ''
    if ($Scope -is [string]) {
        $scopeText = [string]$Scope
    }
    elseif ($Scope.PSObject -and $Scope.PSObject.Properties['Name']) {
        $scopeText = [string]$Scope.Name
    }
    else {
        $scopeText = [string]$Scope
    }

    if ([string]::IsNullOrWhiteSpace($scopeText)) { return '' }

    $scopeText = ($scopeText -replace '[\r\n]+', ' ').Trim()
    return $scopeText
}

function Get-BaselineLogScope {
    $scopeText = ConvertTo-BaselineLogScopeText -Scope $script:LogScope
    if ([string]::IsNullOrWhiteSpace($scopeText)) { return 'Baseline' }
    return $scopeText
}

function Set-BaselineLogScope {
    param(
        [string]$Scope
    )

    $scopeText = ConvertTo-BaselineLogScopeText -Scope $Scope
    if ([string]::IsNullOrWhiteSpace($scopeText)) {
        $script:LogScope = 'Baseline'
        return
    }

    $script:LogScope = $scopeText
}

function Clear-BaselineLogScope {
    $script:LogScope = 'Baseline'
}

function Resolve-BaselineLogScope {
    param(
        [AllowNull()]
        [object]$Scope
    )

    $scopeText = ConvertTo-BaselineLogScopeText -Scope $Scope
    if (-not [string]::IsNullOrWhiteSpace($scopeText)) { return $scopeText }

    $operationScope = Get-BaselineCurrentOperationScope
    if ($operationScope -and $operationScope.PSObject.Properties['LogScope']) {
        $scopeText = ConvertTo-BaselineLogScopeText -Scope $operationScope.LogScope
        if (-not [string]::IsNullOrWhiteSpace($scopeText)) { return $scopeText }
    }

    $scopeText = ConvertTo-BaselineLogScopeText -Scope $script:LogScope
    if (-not [string]::IsNullOrWhiteSpace($scopeText)) { return $scopeText }

    return 'Baseline'
}

<#
    .SYNOPSIS
    Set the log file path used by the logging module.



.DESCRIPTION

Sets the log file path used by the logging module. using Baseline's source configuration.
    .PARAMETER Path
    Path to the log file that should receive log output.

    .PARAMETER Clear
    Clear the existing log file and start a new log header.

    .EXAMPLE
    Set-LogFile -Path $global:LogFilePath
#>
function Set-LogFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [switch]$Clear
    )

    $script:LogFilePath = $Path
    Reset-LogStatistics

    # Use [System.IO] directly throughout because Microsoft.PowerShell.Management
    # guaranteed to be loaded inside the embedded PowerShell host Baseline.exe
    # spins up during bootstrap. A single failed cmdlet here would prevent the
    # session log file from ever being created.
    try {
        $dir = [System.IO.Path]::GetDirectoryName($Path)
        if ($dir -and -not [System.IO.Directory]::Exists($dir)) {
            [void][System.IO.Directory]::CreateDirectory($dir)
        }
    } catch { $null = $_ }

    $debugTag = if ($script:DebugLoggingEnabled) { ' DebugMode=ON' } else { '' }
    $sessionIdTag = ' SessionId={0}' -f (Get-BaselineRunId)
    $header = "=== Log Started at $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz'))$debugTag$sessionIdTag ===`r`n"
    $utf8 = [System.Text.Encoding]::UTF8
    if ($Clear) {
        try { [System.IO.File]::WriteAllText($Path, $header, $utf8) } catch { $null = $_ }
    } elseif (-not [System.IO.File]::Exists($Path)) {
        try { [System.IO.File]::WriteAllText($Path, $header, $utf8) } catch { $null = $_ }
    }
}

<#
    .SYNOPSIS
    Adds pending log message.

    #>
function Add-PendingLogMessage {
    param(
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $lockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($script:PendingLogMessagesSyncRoot, [ref]$lockTaken)
        [void]$script:PendingLogMessages.Add($Message)
    }
    finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($script:PendingLogMessagesSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Restore pending log messages.

    #>
function Restore-PendingLogMessages {
    param(
        [string[]]$Messages
    )

    if (-not $Messages -or $Messages.Count -eq 0) {
        return
    }

    $lockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($script:PendingLogMessagesSyncRoot, [ref]$lockTaken)
        $script:PendingLogMessages.InsertRange(0, @($Messages))
    }
    finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($script:PendingLogMessagesSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Writes pending log messages to file.

    #>
function Write-PendingLogMessagesToFile {
    param(
        [string]$CurrentMessage,
        [switch]$CurrentMessageAlreadyQueued
    )

    $messagesToWrite = [System.Collections.Generic.List[string]]::new()
    $lockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($script:PendingLogMessagesSyncRoot, [ref]$lockTaken)
        foreach ($queuedMessage in @($script:PendingLogMessages)) {
            [void]$messagesToWrite.Add([string]$queuedMessage)
        }
        $script:PendingLogMessages.Clear()
    }
    finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($script:PendingLogMessagesSyncRoot)
        }
    }

    if (-not $CurrentMessageAlreadyQueued -and -not [string]::IsNullOrWhiteSpace($CurrentMessage)) {
        [void]$messagesToWrite.Add($CurrentMessage)
    }

    if ($messagesToWrite.Count -eq 0) {
        return $true
    }

    try {
        # Use [System.IO.File]::AppendAllText so the writes succeed inside the embedded
        # PowerShell host where Add-Content (Microsoft.PowerShell.Management) may not
        # be loaded. Joining once and appending in one call also avoids per-line opens.
        $payload = ([string]::Join("`r`n", $messagesToWrite.ToArray())) + "`r`n"
        [System.IO.File]::AppendAllText($script:LogFilePath, $payload, [System.Text.Encoding]::UTF8)
        return $true
    }
    catch {
        Restore-PendingLogMessages -Messages $messagesToWrite.ToArray()
        return $false
    }
}

<#
    .SYNOPSIS
    Write a formatted message to the current log file.



.DESCRIPTION

Applies the Baseline behavior for write a formatted message to the current log file..
    .PARAMETER Message
    Message text to write to the log.

    .PARAMETER Level
    Severity level to include in the log entry.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    Write-LogMessage -Message "Import started" -Level INFO
#>
function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        [string]$Scope,
        [switch]$AddGap,
        [switch]$ShowConsole,  # Changed from NoConsole to ShowConsole (default off)
        [switch]$Always
    )

    if ($Level -eq 'DEBUG' -and -not $script:DebugLoggingEnabled -and -not $Always) { return }

    # If the module-scoped path was reset (e.g. by a -Force re-import), fall
    # back to the global path the bootstrap published. Without this, errors
    # raised from GUI event handlers vanish silently — see GUI-GENERIC-001
    # diagnosis where the dialog appeared but no log line was written.
    if (-not $script:LogFilePath) {
        if ($global:LogFilePath) {
            $script:LogFilePath = $global:LogFilePath
        } else {
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
    return
    }

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm"
    $runIdPrefix = '[RunId={0}] ' -f (Get-BaselineRunIdShort)
    $contextPrefix = if ([string]::IsNullOrWhiteSpace($script:LogMode)) { '' } else { "[Mode=$($script:LogMode)] " }
    $scopeText = Resolve-BaselineLogScope -Scope $Scope
    $scopePrefix = "[$scopeText] "
    $logMessage = "$timestamp $Level`: $runIdPrefix$scopePrefix$contextPrefix$Message"
    if ($AddGap) { $logMessage += "`n" }

    switch ($Level) {
        'INFO' { $script:LogStatistics.Info++ }
        'WARNING' { $script:LogStatistics.Warning++ }
        'ERROR' { $script:LogStatistics.Error++ }
        'DEBUG' { $script:LogStatistics.Debug++ }
    }

    $null = Send-UILogEntry -Entry ([PSCustomObject]@{
        Kind = 'Log'
        Level = $Level
        Message = $Message
    })

    # Write-Host: intentional — console logging output channel
    # Show log output in the console only when explicitly requested.
    if ($ShowConsole) {
        switch ($Level) {
            'ERROR'   { Write-Host "ERROR: $Message" -ForegroundColor Red }
            'WARNING' { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
            default   { Write-Host "INFO: $Message" }
        }
    }

    # Use a mutex so multiple log writes do not corrupt the log file.
    $acquired = $false
    $messageQueued = $false
    try {
        $acquired = $script:LogLock.WaitOne($script:DefaultLogMutexTimeoutMs)
    }
    catch {
        # Mutex handle may be closed if the runspace was disposed — write directly
        $null = Write-PendingLogMessagesToFile -CurrentMessage $logMessage
        return
    }
    try {
        if ($acquired) {
            $null = Write-PendingLogMessagesToFile -CurrentMessage $logMessage
        } else {
            Add-PendingLogMessage -Message $logMessage
            $messageQueued = $true
            try {
                Write-Host "WARNING: Log mutex timeout after $($script:DefaultLogMutexTimeoutMs) ms; message queued for retry: $logMessage" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Log mutex timeout after $($script:DefaultLogMutexTimeoutMs) ms; message queued for retry: $logMessage"
            }

            foreach ($backoffMs in @($script:LogMutexRetryBackoffMs)) {
                Start-Sleep -Milliseconds ([int]$backoffMs)
                try {
                    $acquired = $script:LogLock.WaitOne(0)
                }
                catch {
                    $acquired = $false
                    break
                }

                if ($acquired) {
                    $null = Write-PendingLogMessagesToFile -CurrentMessage $logMessage -CurrentMessageAlreadyQueued:$messageQueued
                    break
                }
            }
        }
    }
    finally {
        if ($acquired) {
            try { $script:LogLock.ReleaseMutex() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Logging.Write.WriteLogMessage.ReleaseMutex' -Severity Debug }
        }
    }
}

<#
    .SYNOPSIS
    Write an informational message to the log.



.DESCRIPTION

Applies the Baseline behavior for write an informational message to the log..
    .PARAMETER Message
    Informational message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    Write-BaselineInfo -Message "Region modules imported"
#>
function Write-BaselineInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Scope,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    Write-LogMessage -Message $Message -Level 'INFO' -Scope $Scope -AddGap:$AddGap -ShowConsole:$ShowConsole
}

<#
    .SYNOPSIS
    Write a warning message to the log.



.DESCRIPTION

Applies the Baseline behavior for write a warning message to the log..
    .PARAMETER Message
    Warning message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    Write-BaselineWarning -Message "Optional file was not found"
#>
function Write-BaselineWarning {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Message,
        [string]$Scope,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    $logMessage = Format-BaselineErrorForLog -ErrorObject $Message
    Write-LogMessage -Message $logMessage -Level 'WARNING' -Scope $Scope -AddGap:$AddGap -ShowConsole:$ShowConsole
}

<#
    .SYNOPSIS
    Formats an exception or ErrorRecord with diagnostic detail for the session log.

    .DESCRIPTION
    Keeps full PowerShell error context in the log: type, category, fully qualified
    error id, invocation position, script stack trace, target type, and .NET stack
    traces. Plain strings are returned unchanged.
#>
function Format-BaselineErrorForLog {
    param(
        [Parameter(Mandatory=$true)]
        [object]$ErrorObject,

        [string]$Prefix
    )

    if ($null -eq $ErrorObject) {
        return ''
    }

    $errorRecord = $null
    $exception = $null

    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $errorRecord = $ErrorObject
        $exception = $ErrorObject.Exception
    }
    elseif ($ErrorObject -is [System.Exception]) {
        $exception = $ErrorObject
        try {
            if ($ErrorObject.PSObject.Properties['ErrorRecord']) {
                $errorRecord = $ErrorObject.ErrorRecord
            }
        }
        catch {
            $errorRecord = $null
        }
    }
    elseif ($ErrorObject.PSObject -and $ErrorObject.PSObject.Properties['Exception']) {
        try {
            $exception = $ErrorObject.Exception
            if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
                $errorRecord = $ErrorObject
            }
        }
        catch {
            $exception = $null
        }
    }

    if (-not $exception -and -not $errorRecord) {
        $plainText = [string]$ErrorObject
        if ([string]::IsNullOrWhiteSpace($Prefix)) {
            return $plainText
        }
        return ('{0}: {1}' -f $Prefix, $plainText)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $message = if ($exception) { [string]$exception.Message } else { [string]$ErrorObject }
    if ([string]::IsNullOrWhiteSpace($Prefix)) {
        [void]$lines.Add($message)
    }
    else {
        [void]$lines.Add(('{0}: {1}' -f $Prefix, $message))
    }

    if ($exception) {
        [void]$lines.Add(('Exception type: {0}' -f $exception.GetType().FullName))
        if ($exception.HResult) {
            [void]$lines.Add(('HResult: {0}' -f $exception.HResult))
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$exception.Source)) {
            [void]$lines.Add(('Source: {0}' -f $exception.Source))
        }
    }

    if ($errorRecord) {
        if (-not [string]::IsNullOrWhiteSpace([string]$errorRecord.FullyQualifiedErrorId)) {
            [void]$lines.Add(('FullyQualifiedErrorId: {0}' -f $errorRecord.FullyQualifiedErrorId))
        }
        if ($errorRecord.CategoryInfo) {
            [void]$lines.Add(('CategoryInfo: {0}' -f $errorRecord.CategoryInfo.ToString()))
        }
        if ($errorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.InvocationInfo.PositionMessage)) {
            [void]$lines.Add('Invocation:')
            [void]$lines.Add($errorRecord.InvocationInfo.PositionMessage.Trim())
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$errorRecord.ScriptStackTrace)) {
            [void]$lines.Add('Script stack trace:')
            [void]$lines.Add($errorRecord.ScriptStackTrace.Trim())
        }
        if ($null -ne $errorRecord.TargetObject) {
            $targetType = 'unknown'
            try { $targetType = $errorRecord.TargetObject.GetType().FullName } catch { $targetType = 'unknown' }
            [void]$lines.Add(('Target object type: {0}' -f $targetType))
        }
    }

    $inner = if ($exception) { $exception.InnerException } else { $null }
    $innerIndex = 1
    while ($inner) {
        [void]$lines.Add(('Inner exception {0}: {1}' -f $innerIndex, $inner.Message))
        [void]$lines.Add(('Inner exception {0} type: {1}' -f $innerIndex, $inner.GetType().FullName))
        if (-not [string]::IsNullOrWhiteSpace([string]$inner.StackTrace)) {
            [void]$lines.Add(('Inner exception {0} stack trace:' -f $innerIndex))
            [void]$lines.Add($inner.StackTrace.Trim())
        }
        $inner = $inner.InnerException
        $innerIndex++
    }

    if ($exception -and -not [string]::IsNullOrWhiteSpace([string]$exception.StackTrace)) {
        [void]$lines.Add('Stack trace:')
        [void]$lines.Add($exception.StackTrace.Trim())
    }

    return ($lines -join [Environment]::NewLine)
}

<#
    .SYNOPSIS
    Write an error message to the log.



.DESCRIPTION

Applies the Baseline behavior for write an error message to the log..
    .PARAMETER Message
    Error message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    Write-BaselineError -Message "PowerShell 5.1 not found."
#>
function Write-BaselineError {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Message,
        [string]$Scope,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    $logMessage = Format-BaselineErrorForLog -ErrorObject $Message
    Set-BaselineOperationFailed -Reason $logMessage
    Write-LogMessage -Message $logMessage -Level 'ERROR' -Scope $Scope -AddGap:$AddGap -ShowConsole:$ShowConsole
}

<#
    .SYNOPSIS
    Gets log statistics.

    #>

function Get-LogStatistics {
    return [PSCustomObject]@{
        InfoCount = $script:LogStatistics.Info
        WarningCount = $script:LogStatistics.Warning
        ErrorCount = $script:LogStatistics.Error
        DebugCount = $script:LogStatistics.Debug
    }
}

function Get-BaselineCurrentOperationScope {
    if ($script:OperationScopeStack -and $script:OperationScopeStack.Count -gt 0) {
        return $script:OperationScopeStack[$script:OperationScopeStack.Count - 1]
    }

    return $null
}

function Start-BaselineOperationScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [string]$LogScope
    )

    $scope = [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString('N')
        Name = $Name
        LogScope = (ConvertTo-BaselineLogScopeText -Scope $LogScope)
        Failed = $false
        FailureReasons = [System.Collections.Generic.List[string]]::new()
    }
    [void]$script:OperationScopeStack.Add($scope)
    return $scope
}

function Set-BaselineOperationFailed {
    [CmdletBinding()]
    param(
        [object]$Scope,
        [string]$Reason
    )

    $targetScope = $Scope
    if (-not $targetScope) {
        $targetScope = Get-BaselineCurrentOperationScope
    }
    if (-not $targetScope) { return }

    if ($targetScope.PSObject.Properties['Failed']) {
        $targetScope.Failed = $true
    }
    if (
        -not [string]::IsNullOrWhiteSpace($Reason) -and
        $targetScope.PSObject.Properties['FailureReasons']
    ) {
        $failureReasons = $targetScope.FailureReasons
        if ($null -ne $failureReasons) {
            [void]$failureReasons.Add($Reason)
        }
    }
}

function Stop-BaselineOperationScope {
    [CmdletBinding()]
    param(
        [object]$Scope
    )

    $targetScope = $Scope
    if (-not $targetScope) {
        $targetScope = Get-BaselineCurrentOperationScope
    }
    if (-not $targetScope) { return $null }

    [void]$script:OperationScopeStack.Remove($targetScope)
    return $targetScope
}

<#
    .SYNOPSIS
    Write a debug message to the log. No-op when Debug Mode is off unless Always is supplied.

    .DESCRIPTION
    DEBUG entries are gated by $script:DebugLoggingEnabled. When the flag is
    off (the default), this function returns immediately without producing
    any I/O, so it is safe to call from hot paths. Use Always only for
    diagnostics that are part of the normal support log contract.

    DEBUG is for diagnostic detail, not an INFO/WARNING/ERROR mirror. Use it
    for state resolution, branch decisions, object counts, resolved paths,
    retry details, timings, and internal values that explain why or how an
    operation is running. Do not add DEBUG entries that repeat an operational
    INFO line such as "Starting scan" or "Checking services" without adding
    diagnostic context.

    .EXAMPLE
    Write-BaselineDebug -Message "Theme apply resolved resource dictionary: $themePath"
#>
function Write-BaselineDebug {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Scope,
        [switch]$AddGap,
        [switch]$ShowConsole,
        [switch]$Always
    )
    if (-not $Always -and -not $script:DebugLoggingEnabled) { return }
    Write-LogMessage -Message $Message -Level 'DEBUG' -Scope $Scope -AddGap:$AddGap -ShowConsole:$ShowConsole -Always:$Always
}

<#
    .SYNOPSIS
    Toggle Debug Mode logging at runtime.

    .DESCRIPTION
    Sets the in-process flag that gates DEBUG-level emissions. The Settings
    UI and the startup orchestrator call this when DebugLoggingEnabled is
    persisted in Baseline-user-prefs.json.
#>
function Set-BaselineDebugLogging {
    param(
        [Parameter(Mandatory=$true)]
        [bool]$Enabled
    )
    $script:DebugLoggingEnabled = $Enabled
}

<#
    .SYNOPSIS
    Returns whether Debug Mode logging is currently enabled.


.DESCRIPTION

Applies the Baseline behavior for returns whether Debug Mode logging is currently enabled..
#>
function Get-BaselineDebugLogging {
    return [bool]$script:DebugLoggingEnabled
}

<#
    .SYNOPSIS
    Set the per-session correlation RunId.

    .DESCRIPTION
    Bootstrap calls this once just before Set-LogFile so the very first
    header line records the full SessionId and every subsequent log entry carries the same RunId.
    Tests can also call it to pin the value.
#>
function Set-BaselineRunId {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RunId
    )
    if ([string]::IsNullOrWhiteSpace($RunId)) { return }
    $script:RunId = $RunId
    $clean = $RunId -replace '[^0-9a-fA-F]', ''
    $script:RunIdShort = if ($clean.Length -ge 8) { $clean.Substring(0, 8).ToLowerInvariant() } else { $clean.ToLowerInvariant() }
}

<#
    .SYNOPSIS
    Returns the full session RunId GUID, generating one on first read.


.DESCRIPTION

Applies the Baseline behavior for returns the full session RunId GUID, generating one on first read..
#>
function Get-BaselineRunId {
    if ([string]::IsNullOrWhiteSpace($script:RunId)) {
        Set-BaselineRunId -RunId ([guid]::NewGuid().ToString())
    }
    return $script:RunId
}

<#
    .SYNOPSIS
    Returns the 8-character short form of the session RunId for log prefixing.


.DESCRIPTION

Applies the Baseline behavior for returns the 8-character short form of the session RunId for log prefixing..
#>
function Get-BaselineRunIdShort {
    if ([string]::IsNullOrWhiteSpace($script:RunIdShort)) {
        $null = Get-BaselineRunId
    }
    return $script:RunIdShort
}

# In-process action trail. A bounded ring buffer of UI / CLI actions the
# user took during this session. Surfaced in support-bundle metadata under
# ReproductionContext.ActionSequence so a maintainer can replay the path.
# Capped to keep the bundle small even on long-running sessions.
$script:ActionTrail = $null
$script:ActionTrailMax = 200

<#
    .SYNOPSIS
    Append an entry to the in-process action trail.

    .DESCRIPTION
    Lazy-initialized ring buffer. Each entry is timestamped and tagged.
    Safe to call from any thread context — failures never throw.

    .PARAMETER Action
    Short label, e.g. 'Apply Preset: Balanced', 'Run Tweaks', 'Open Settings'.

    .PARAMETER Detail
    Optional context, e.g. selected preset name, target count, error category.
#>
function Add-BaselineActionTrail {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Action,
        [string]$Detail
    )
    try {
        if ($null -eq $script:ActionTrail) {
            $script:ActionTrail = [System.Collections.Generic.List[pscustomobject]]::new()
        }
        $entry = [pscustomobject]@{
            Timestamp = [datetime]::UtcNow.ToString('o')
            Action    = $Action
            Detail    = if ([string]::IsNullOrWhiteSpace($Detail)) { $null } else { [string]$Detail }
        }
        [void]$script:ActionTrail.Add($entry)
        # Cap the buffer: drop the oldest 25% when we hit the limit so
        # we keep enough recent context but never grow without bound.
        if ($script:ActionTrail.Count -gt $script:ActionTrailMax) {
            $drop = [int]($script:ActionTrailMax / 4)
            $script:ActionTrail.RemoveRange(0, $drop)
        }
    } catch { $null = $_ }
}

<#
    .SYNOPSIS
    Returns the in-process action trail as an array.


.DESCRIPTION

Applies the Baseline behavior for returns the in-process action trail as an array..
#>
function Get-BaselineActionTrail {
    if ($null -eq $script:ActionTrail) { return @() }
    return @($script:ActionTrail)
}

<#
    .SYNOPSIS
    Clears the in-process action trail.


.DESCRIPTION

Applies the Baseline behavior for clears the in-process action trail..
#>
function Reset-BaselineActionTrail {
    $script:ActionTrail = $null
}

<#
    .SYNOPSIS
    Records a suppressed exception at the requested operational severity.

    .DESCRIPTION
    Use Debug only for harmless cleanup or UI polish paths. Use Warning or
    Error when the swallowed exception affects persistence, process control,
    support collection, link/file launch, or native command execution.
#>
function Write-SwallowedException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $ErrorRecord,

        [Parameter(Mandatory=$true)]
        [string]$Source,

        [ValidateSet('Debug', 'Warning', 'Error')]
        [string]$Severity = 'Debug'
    )

    try {
        $message = Format-BaselineErrorForLog -ErrorObject $ErrorRecord -Prefix ("[swallow] {0}" -f $Source)
        switch ($Severity)
        {
            'Debug'
            {
                if ($script:DebugLoggingEnabled)
                {
                    Write-LogMessage -Message $message -Level 'DEBUG' -Scope $Source
                }
            }
            'Warning'
            {
                if (Get-Command -Name 'Write-BaselineWarning' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-BaselineWarning $message
                }
                else
                {
                    Write-Warning $message
                }
            }
            'Error'
            {
                if (Get-Command -Name 'Write-BaselineError' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-BaselineError $message
                }
                else
                {
                    Write-Error $message
                }
            }
        }
    }
    catch
    {
        $loggingFailure = $_
        $fallbackMessage = "[swallow-log-failure] {0}: failed to record swallowed exception: {1}" -f $Source, $loggingFailure.Exception.Message
        try
        {
            Write-Warning $fallbackMessage
        }
        catch
        {
            try
            {
                $emergencyDirectory = Get-BaselineLogDirectory
                $emergencyLogPath = Join-Path $emergencyDirectory 'Baseline-emergency.log'
                $line = "{0} {1}{2}" -f ([datetime]::UtcNow.ToString('o')), $fallbackMessage, [Environment]::NewLine
                [System.IO.File]::AppendAllText($emergencyLogPath, $line, [System.Text.Encoding]::UTF8)
            }
            catch
            {
                $null = $_
            }
        }
    }
}

<#
    .SYNOPSIS
    Records a swallowed exception at Debug severity.

    .DESCRIPTION
    Compatibility wrapper for existing harmless cleanup paths. Meaningful
    swallowed failures should call Write-SwallowedException directly with
    Warning or Error severity.
#>
function Write-DebugSwallowedException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $ErrorRecord,

        [Parameter(Mandatory=$true)]
        [string]$Source
    )

    Write-SwallowedException -ErrorRecord $ErrorRecord -Source $Source -Severity Debug
}

<#
    .SYNOPSIS
    Sets UI log handler.

    #>
function Set-UILogHandler {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Handler
    )
    $script:UILogHandler = $Handler
}

<#
    .SYNOPSIS
    Clears UI log handler.

    #>

function Clear-UILogHandler {
    $script:UILogHandler = $null
}

<#
    .SYNOPSIS
    Writes console status.

    #>
function Write-ConsoleStatus {
    [CmdletBinding()]
    param(
        [string]$Action,

        [string]$Scope,

        [ValidateSet('success', 'failed', 'warning')]
        [string]$Status
    )

    $guiModeValue = Get-Variable -Name GUIMode -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    $writeToHost = (-not [bool]$guiModeValue)

    if ([string]::IsNullOrWhiteSpace($Action) -and [string]::IsNullOrWhiteSpace($Status)) {
        throw "Write-ConsoleStatus requires -Action, -Status, or both."
    }

    if (-not [string]::IsNullOrWhiteSpace($Action) -and [string]::IsNullOrWhiteSpace($Status)) {
        $operationScope = Start-BaselineOperationScope -Name $Action -LogScope $Scope
        $script:ConsoleStatusContext = [PSCustomObject]@{
            Action = $Action
            OperationScope = $operationScope
        }
        $null = Send-UILogEntry -Entry ([PSCustomObject]@{
            Kind = 'ConsoleAction'
            Action = $Action
        })
        if ($writeToHost) {
            Write-Host ("{0} - " -f $Action) -NoNewline
        }
        return
    }

    $operationScope = if (
        $script:ConsoleStatusContext -and
        $script:ConsoleStatusContext.PSObject.Properties['OperationScope']
    ) {
        $script:ConsoleStatusContext.OperationScope
    } else {
        $null
    }
    if (-not [string]::IsNullOrWhiteSpace($Action)) {
        $script:ConsoleStatusContext = $null
    }

    $statusText = $Status.ToLowerInvariant()
    if ($statusText -eq 'failed') {
        Set-BaselineOperationFailed -Scope $operationScope -Reason 'Console status failed.'
    }
    elseif ($statusText -eq 'success' -and $operationScope -and $operationScope.PSObject.Properties['Failed'] -and [bool]$operationScope.Failed) {
        $statusText = 'failed'
    }
    $color = switch ($statusText) {
        'success' { 'Green' }
        'failed' { 'Red' }
        default { 'Yellow' }
    }

    if ([string]::IsNullOrWhiteSpace($Action)) {
        $null = Send-UILogEntry -Entry ([PSCustomObject]@{
            Kind = 'ConsoleStatus'
            Status = $statusText
        })
        if ($writeToHost) {
            Write-Host ("{0}!" -f $statusText) -ForegroundColor $color
        }
        if ($operationScope) {
            $null = Stop-BaselineOperationScope -Scope $operationScope
        }
        $script:ConsoleStatusContext = $null
        return
    }

    $null = Send-UILogEntry -Entry ([PSCustomObject]@{
        Kind = 'ConsoleComplete'
        Action = $Action
        Status = $statusText
    })
    if ($writeToHost) {
        Write-Host ("{0} - " -f $Action) -NoNewline
        Write-Host ("{0}!" -f $statusText) -ForegroundColor $color
    }
    if ($operationScope) {
        $null = Stop-BaselineOperationScope -Scope $operationScope
    }
    $script:ConsoleStatusContext = $null
}

<#
    .SYNOPSIS
    Initializes session statistics.

    #>

function Initialize-SessionStatistics {
    $lockTaken = $false
    try
    {
        [System.Threading.Monitor]::Enter($script:SessionStatisticsSyncRoot, [ref]$lockTaken)
        $script:SessionStatistics = @{
            SessionStartTime    = Get-Date
            PresetName          = $null
            TweaksSelected      = 0
            PreviewRunCount     = 0
            ApplyRunCount       = 0
            SucceededCount      = 0
            FailedCount         = 0
            SkippedCount        = 0
            NotApplicableCount  = 0
            NotRunCount         = 0
            IsGUI               = $false
            GameModeActive      = $false
            GameModeProfile     = $null
        }
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($script:SessionStatisticsSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Updates session statistics.

    #>

function Update-SessionStatistics {
    param(
        [hashtable]$Values
    )

    if (-not $Values) { return }

    $lockTaken = $false
    try
    {
        [System.Threading.Monitor]::Enter($script:SessionStatisticsSyncRoot, [ref]$lockTaken)
        if (-not $script:SessionStatistics) { return }

        foreach ($key in $Values.Keys)
        {
            if ($script:SessionStatistics.ContainsKey($key))
            {
                $script:SessionStatistics[$key] = $Values[$key]
            }
        }
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($script:SessionStatisticsSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Adds session statistic.

    #>

function Add-SessionStatistic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int]$Increment = 1
    )

    $lockTaken = $false
    try
    {
        [System.Threading.Monitor]::Enter($script:SessionStatisticsSyncRoot, [ref]$lockTaken)
        if (-not $script:SessionStatistics -or -not $script:SessionStatistics.ContainsKey($Name)) { return }

        $script:SessionStatistics[$Name] = [int]$script:SessionStatistics[$Name] + $Increment
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($script:SessionStatisticsSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Gets session statistics.

    #>
function Get-SessionStatistics {
    $lockTaken = $false
    try
    {
        [System.Threading.Monitor]::Enter($script:SessionStatisticsSyncRoot, [ref]$lockTaken)
        if (-not $script:SessionStatistics) { return $null }
        return $script:SessionStatistics.Clone()
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($script:SessionStatisticsSyncRoot)
        }
    }
}

<#
    .SYNOPSIS
    Writes session summary to log.

    #>

function Write-SessionSummaryToLog {
    <#
        .SYNOPSIS
        Writes a single structured session summary line at the end of the log file.

        .DESCRIPTION
        Gathers local-only session statistics (preset, tweak counts, run counts,
        success/failure/skip counts, mode, game mode, duration) and appends a
        human-readable summary block to the Baseline log. This is never sent
        anywhere -- it stays in the local log file so users can include it
        when filing issues.
    #>

    if (-not $script:LogFilePath) { return }
    $stats = Get-SessionStatistics
    if (-not $stats) { return }

    # Skip writing if no meaningful activity was tracked (e.g. background runspace
    # that imported the module but never ran through the main session flow).
    $skippedCount = if ($stats.ContainsKey('SkippedCount')) { [int]$stats.SkippedCount } else { 0 }
    $notApplicableCount = if ($stats.ContainsKey('NotApplicableCount')) { [int]$stats.NotApplicableCount } else { 0 }
    $notRunCount = if ($stats.ContainsKey('NotRunCount')) { [int]$stats.NotRunCount } else { 0 }

    $hasActivity = ($stats.PreviewRunCount -gt 0 -or $stats.ApplyRunCount -gt 0 -or
                    $stats.SucceededCount -gt 0 -or $stats.FailedCount -gt 0 -or
                    $skippedCount -gt 0 -or $notApplicableCount -gt 0 -or
                    $notRunCount -gt 0 -or $stats.TweaksSelected -gt 0)
    if (-not $hasActivity) { return }

    # Calculate duration
    $durationText = '?'
    if ($stats.SessionStartTime)
    {
        $elapsed = (Get-Date) - [datetime]$stats.SessionStartTime
        if ($elapsed.TotalHours -ge 1)
        {
            $durationText = '{0}h {1}m {2}s' -f [int][Math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
        }
        elseif ($elapsed.TotalMinutes -ge 1)
        {
            $durationText = '{0}m {1}s' -f [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        }
        else
        {
            $durationText = '{0}s' -f [int][Math]::Floor($elapsed.TotalSeconds)
        }
    }

    $presetDisplay    = if ([string]::IsNullOrWhiteSpace([string]$stats.PresetName)) { 'None' } else { [string]$stats.PresetName }
    $modeDisplay      = if ($stats.IsGUI) { 'GUI' } else { 'Headless' }
    $gameModeDisplay  = if ($stats.GameModeActive) {
        if ([string]::IsNullOrWhiteSpace([string]$stats.GameModeProfile)) { 'Yes' } else { "Yes ($($stats.GameModeProfile))" }
    } else { 'No' }

    $summaryLine = "Preset: $presetDisplay | Tweaks selected: $($stats.TweaksSelected) | Preview runs: $($stats.PreviewRunCount) | Apply runs: $($stats.ApplyRunCount) | Succeeded: $($stats.SucceededCount) | Failed: $($stats.FailedCount) | Skipped: $skippedCount | Not applicable: $notApplicableCount | Not run: $notRunCount | Mode: $modeDisplay | Game Mode: $gameModeDisplay | Duration: $durationText"
    $runIdPrefix = '[RunId={0}] ' -f (Get-BaselineRunIdShort)

    $block = @(
        ''
        ('{0}--- Session Summary ---' -f $runIdPrefix)
        ('{0}{1}' -f $runIdPrefix, $summaryLine)
    )

    $acquired = $script:LogLock.WaitOne($script:DefaultLogMutexTimeoutMs)
    try {
        if ($acquired) {
            try {
                $payload = ($block -join "`r`n") + "`r`n"
                [System.IO.File]::AppendAllText($script:LogFilePath, $payload, [System.Text.Encoding]::UTF8)
            } catch { $null = $_ }
        }
    }
    finally {
        if ($acquired) {
            $script:LogLock.ReleaseMutex()
        }
    }
}

# Dispose the log mutex when the module is removed to release the system handle.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($script:LogLock) { $script:LogLock.Dispose() }
}

# Keep the legacy function names as aliases so existing modules continue to load,
# while the exported canonical API uses Verb-Noun names.
Set-Alias -Name LogInfo -Value Write-BaselineInfo -Scope Local
Set-Alias -Name LogWarning -Value Write-BaselineWarning -Scope Local
Set-Alias -Name LogError -Value Write-BaselineError -Scope Local
Set-Alias -Name LogDebug -Value Write-BaselineDebug -Scope Local

# Export the logging functions used by the loader and region modules.
Export-ModuleMember -Function Get-BaselineLogDirectory, Resolve-BaselineLogDirectory, Get-BaselineConfiguredLogDirectory, New-BaselineSessionLogPath, Set-LogFile, Reset-LogStatistics, Get-LogStatistics, Get-BaselineCurrentOperationScope, Start-BaselineOperationScope, Set-BaselineOperationFailed, Stop-BaselineOperationScope, Set-LogMode, Clear-LogMode, Get-BaselineLogScope, Set-BaselineLogScope, Clear-BaselineLogScope, Set-UILogHandler, Clear-UILogHandler, Write-BaselineInfo, Write-BaselineWarning, Write-BaselineError, Write-BaselineDebug, Write-SwallowedException, Write-DebugSwallowedException, Format-BaselineErrorForLog, Set-BaselineDebugLogging, Get-BaselineDebugLogging, Set-BaselineRunId, Get-BaselineRunId, Get-BaselineRunIdShort, Add-BaselineActionTrail, Get-BaselineActionTrail, Reset-BaselineActionTrail, Write-LogMessage, Write-ConsoleStatus, Initialize-SessionStatistics, Update-SessionStatistics, Add-SessionStatistic, Get-SessionStatistics, Write-SessionSummaryToLog -Alias LogInfo, LogWarning, LogError, LogDebug
