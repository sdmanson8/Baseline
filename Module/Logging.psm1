<#
    .SYNOPSIS
    Logging module for Baseline.

    .VERSION
	3.1.0 (beta)

	.DATE
	17.03.2026 - initial beta version
	21.03.2026 - Added GUI
	06.04.2026 - Major changes to the GUI, and added more features
	26.04.2026 - Minor Fixes

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Initializes the log file used by the script and provides helper functions for writing
    informational, warning, and error messages to that log.
#>

using module .\SharedHelpers.psm1

# Log file is written to $env:TEMP with a timestamp-based name. The admin
# requirement mitigates symlink attacks but the location is still predictable.
$script:LogFilePath = $null
$script:LogLock = New-Object System.Threading.Mutex($false, "Global\BaselineLogLock")
$script:LogStatistics = @{
    Info = 0
    Warning = 0
    Error = 0
}
$script:UILogHandler = $null
$script:ConsoleStatusContext = $null
$script:LogMode = $null
$script:DefaultLogMutexTimeoutMs = 5000
$script:UILogWarningCache = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:SessionStatistics = @{
    SessionStartTime    = $null
    PresetName          = $null
    TweaksSelected      = 0
    PreviewRunCount     = 0
    ApplyRunCount       = 0
    SucceededCount      = 0
    FailedCount         = 0
    SkippedCount        = 0
    IsGUI               = $false
    GameModeActive      = $false
    GameModeProfile     = $null
}

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

function Reset-LogStatistics {
    $script:LogStatistics = @{
        Info = 0
        Warning = 0
        Error = 0
    }
}

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

function Clear-LogMode {
    $script:LogMode = $null
}

<#
    .SYNOPSIS
    Set the log file path used by the logging module.

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
    
    # Create directory if needed
    $dir = Split-Path $Path -Parent
    if (!(Test-Path $dir)) {
        New-Item $dir -ItemType Directory -Force | Out-Null
    }
    
    if ($Clear) {
        # Only clear if explicitly requested
        Set-Content -Path $Path -Value "=== Log Started at $(Get-Date) ===" -Encoding UTF8
    } elseif (!(Test-Path $Path)) {
        # Create if doesn't exist
        Set-Content -Path $Path -Value "=== Log Started at $(Get-Date) ===" -Encoding UTF8
    }
}

<#
    .SYNOPSIS
    Write a formatted message to the current log file.

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
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO',
        [switch]$AddGap,
        [switch]$ShowConsole  # Changed from NoConsole to ShowConsole (default off)
    )
    
    if (-not $script:LogFilePath) { return }

    if ([string]::IsNullOrWhiteSpace($Message)) {
    return
    }

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm"
    $contextPrefix = if ([string]::IsNullOrWhiteSpace($script:LogMode)) { '' } else { "[Mode=$($script:LogMode)] " }
    $logMessage = "$timestamp $Level`: $contextPrefix$Message"
    if ($AddGap) { $logMessage += "`n" }

    switch ($Level) {
        'INFO' { $script:LogStatistics.Info++ }
        'WARNING' { $script:LogStatistics.Warning++ }
        'ERROR' { $script:LogStatistics.Error++ }
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
    try {
        $acquired = $script:LogLock.WaitOne($script:DefaultLogMutexTimeoutMs)
    }
    catch {
        # Mutex handle may be closed if the runspace was disposed — write directly
        try { Add-Content -Path $script:LogFilePath -Value $logMessage -Encoding UTF8 } catch { }
        return
    }
    try {
        if ($acquired) {
            Add-Content -Path $script:LogFilePath -Value $logMessage -Encoding UTF8
        } else {
            try {
                Write-Host "WARNING: Log mutex timeout after $($script:DefaultLogMutexTimeoutMs) ms; message not written to file: $logMessage" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Log mutex timeout after $($script:DefaultLogMutexTimeoutMs) ms; message not written to file: $logMessage"
            }
        }
    }
    finally {
        if ($acquired) {
            try { $script:LogLock.ReleaseMutex() } catch { }
        }
    }
}

<#
    .SYNOPSIS
    Write an informational message to the log.

    .PARAMETER Message
    Informational message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    LogInfo -Message "Region modules imported"
#>
function LogInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    Write-LogMessage -Message $Message -Level 'INFO' -AddGap:$AddGap -ShowConsole:$ShowConsole
}

<#
    .SYNOPSIS
    Write a warning message to the log.

    .PARAMETER Message
    Warning message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    LogWarning -Message "Optional file was not found"
#>
function LogWarning {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    Write-LogMessage -Message $Message -Level 'WARNING' -AddGap:$AddGap -ShowConsole:$ShowConsole
}

<#
    .SYNOPSIS
    Write an error message to the log.

    .PARAMETER Message
    Error message text to log.

    .PARAMETER AddGap
    Add a blank line after the log entry.

    .PARAMETER ShowConsole
    Also display the message in the console.

    .EXAMPLE
    LogError -Message "PowerShell 5.1 not found."
#>
function LogError {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$AddGap,
        [switch]$ShowConsole
    )
    Write-LogMessage -Message $Message -Level 'ERROR' -AddGap:$AddGap -ShowConsole:$ShowConsole
}

function Get-LogStatistics {
    return [PSCustomObject]@{
        InfoCount = $script:LogStatistics.Info
        WarningCount = $script:LogStatistics.Warning
        ErrorCount = $script:LogStatistics.Error
    }
}

function Set-UILogHandler {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Handler
    )
    $script:UILogHandler = $Handler
}

function Clear-UILogHandler {
    $script:UILogHandler = $null
}

function Write-ConsoleStatus {
    [CmdletBinding()]
    param(
        [string]$Action,

        [ValidateSet('success', 'failed', 'warning')]
        [string]$Status
    )

    $writeToHost = (-not $Global:GUIMode)

    if ([string]::IsNullOrWhiteSpace($Action) -and [string]::IsNullOrWhiteSpace($Status)) {
        throw "Write-ConsoleStatus requires -Action, -Status, or both."
    }

    if (-not [string]::IsNullOrWhiteSpace($Action) -and [string]::IsNullOrWhiteSpace($Status)) {
        $script:ConsoleStatusContext = [PSCustomObject]@{
            Action = $Action
            ErrorBaseline = if ($Global:Error) { $Global:Error.Count } else { 0 }
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

    if (-not [string]::IsNullOrWhiteSpace($Action)) {
        $script:ConsoleStatusContext = $null
    }

    $statusText = $Status.ToLowerInvariant()
    if (
        $statusText -eq 'success' -and
        $script:ConsoleStatusContext -and
        ($script:ConsoleStatusContext.PSObject.Properties['ErrorBaseline'])
    ) {
        $errorBaseline = [int]$script:ConsoleStatusContext.ErrorBaseline
        $newErrors = Get-NewUnhandledErrorRecords -BaselineCount $errorBaseline
        if ($newErrors.Count -gt 0) {
            $statusText = 'failed'
        }
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
    $script:ConsoleStatusContext = $null
}

function Initialize-SessionStatistics {
    $script:SessionStatistics = @{
        SessionStartTime    = Get-Date
        PresetName          = $null
        TweaksSelected      = 0
        PreviewRunCount     = 0
        ApplyRunCount       = 0
        SucceededCount      = 0
        FailedCount         = 0
        SkippedCount        = 0
        IsGUI               = $false
        GameModeActive      = $false
        GameModeProfile     = $null
    }
}

function Update-SessionStatistics {
    param(
        [hashtable]$Values
    )

    if (-not $script:SessionStatistics -or -not $Values) { return }

    foreach ($key in $Values.Keys)
    {
        if ($script:SessionStatistics.ContainsKey($key))
        {
            $script:SessionStatistics[$key] = $Values[$key]
        }
    }
}

function Add-SessionStatistic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [int]$Increment = 1
    )

    if (-not $script:SessionStatistics -or -not $script:SessionStatistics.ContainsKey($Name)) { return }

    $script:SessionStatistics[$Name] = [int]$script:SessionStatistics[$Name] + $Increment
}

function Get-SessionStatistics {
    if (-not $script:SessionStatistics) { return $null }
    return $script:SessionStatistics.Clone()
}

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
    if (-not $script:SessionStatistics) { return }

    $stats = $script:SessionStatistics

    # Skip writing if no meaningful activity was tracked (e.g. background runspace
    # that imported the module but never ran through the main session flow).
    $hasActivity = ($stats.PreviewRunCount -gt 0 -or $stats.ApplyRunCount -gt 0 -or
                    $stats.SucceededCount -gt 0 -or $stats.FailedCount -gt 0 -or
                    $stats.SkippedCount -gt 0 -or $stats.TweaksSelected -gt 0)
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

    $summaryLine = "Preset: $presetDisplay | Tweaks selected: $($stats.TweaksSelected) | Preview runs: $($stats.PreviewRunCount) | Apply runs: $($stats.ApplyRunCount) | Succeeded: $($stats.SucceededCount) | Failed: $($stats.FailedCount) | Skipped: $($stats.SkippedCount) | Mode: $modeDisplay | Game Mode: $gameModeDisplay | Duration: $durationText"

    $block = @(
        ''
        '--- Session Summary ---'
        $summaryLine
    )

    $acquired = $script:LogLock.WaitOne($script:DefaultLogMutexTimeoutMs)
    try {
        if ($acquired) {
            Add-Content -Path $script:LogFilePath -Value ($block -join "`n") -Encoding UTF8
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

# Export the logging functions used by the loader and region modules.
Export-ModuleMember -Function Set-LogFile, Reset-LogStatistics, Get-LogStatistics, Set-LogMode, Clear-LogMode, Set-UILogHandler, Clear-UILogHandler, LogInfo, LogWarning, LogError, Write-LogMessage, Write-ConsoleStatus, Initialize-SessionStatistics, Update-SessionStatistics, Add-SessionStatistic, Get-SessionStatistics, Write-SessionSummaryToLog

