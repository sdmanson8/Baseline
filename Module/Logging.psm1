<#
    .SYNOPSIS
    Logging module for Baseline.

    .VERSION
	2.0.0

	.DATE
	17.03.2026 - initial version
	21.03.2026 - Added GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Initializes the log file used by the script and provides helper functions for writing
    informational, warning, and error messages to that log.
#>

using module .\SharedHelpers.psm1

$script:LogFilePath = $null
$script:LogLock = New-Object System.Threading.Mutex($false, "Global\RemoveWindowsAILogLock")
$script:LogStatistics = @{
    Info = 0
    Warning = 0
    Error = 0
}
$script:UILogHandler = $null
$script:ConsoleStatusContext = $null

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
        catch { }
    }

    $queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
    if ($queue) {
        try {
            $queue.Enqueue($Entry)
            return $true
        }
        catch { }
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
        Set-Content -Path $Path -Value "=== Log Started at $(Get-Date) ==="
    } elseif (!(Test-Path $Path)) {
        # Create if doesn't exist
        Set-Content -Path $Path -Value "=== Log Started at $(Get-Date) ==="
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
    $logMessage = "$timestamp $Level`: $Message"
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
    
    # Show log output in the console only when explicitly requested.
    if ($ShowConsole) {
        switch ($Level) {
            'ERROR'   { Write-Host "ERROR: $Message" -ForegroundColor Red }
            'WARNING' { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
            default   { Write-Host "INFO: $Message" }
        }
    }
    
    # Use a mutex so multiple log writes do not corrupt the log file.
    $acquired = $script:LogLock.WaitOne(5000)  # 5 second timeout
    try {
        if ($acquired) {
            Add-Content -Path $script:LogFilePath -Value $logMessage -Encoding UTF8
        } else {
            # Fallback if mutex times out
            Write-Host "WARNING: Log mutex timeout - retrying..." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 100
            Add-Content -Path $script:LogFilePath -Value $logMessage -Encoding UTF8
        }
    }
    finally {
        if ($acquired) {
            $script:LogLock.ReleaseMutex()
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

# Export the logging functions used by the loader and region modules.
Export-ModuleMember -Function Set-LogFile, Reset-LogStatistics, Get-LogStatistics, Set-UILogHandler, Clear-UILogHandler, LogInfo, LogWarning, LogError, Write-LogMessage, Write-ConsoleStatus
