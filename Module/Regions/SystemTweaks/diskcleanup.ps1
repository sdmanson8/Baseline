<#
    .SYNOPSIS
    Admin maintenance utility that runs Windows disk cleanup tasks and writes progress to the Baseline log.

    .VERSION
    1.0.0

    .DATE
    21.03.2026 - Initial Release
    25.05.2026 - Major upgrades to GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Imports the shared logging module, selects a log file, runs Disk Cleanup in
    very low disk mode, and then runs DISM component cleanup to remove
    superseded component store files. This script is intended for maintenance
    workflows rather than user-facing setup flow.

    .NOTES
    This script is intended to be called by Baseline. If no log path is
    provided, it falls back to a temporary log file.

    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\SystemTweaks\diskcleanup.ps1
#>

# Import the shared logging module used by Baseline child scripts.
$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$script:ModuleRoot = Join-Path $script:RepoRoot 'Module'

if (-not (Test-Path -LiteralPath $script:ModuleRoot -PathType Container)) {
    throw "Module directory not found under: $script:RepoRoot"
}

Import-Module -Name (Join-Path $script:ModuleRoot 'Logging.psm1') -Force
Import-Module -Name (Join-Path $script:ModuleRoot 'SharedHelpers.psm1') -Force

# Select the log file in this order: explicit parameter, environment variable,
# existing global log path, then a temporary fallback file.
if ($LogFilePath) {
    Set-LogFile -Path $LogFilePath
    #LogInfo "Using log file from parameter: $LogFilePath"
} elseif ($env:diskcleanup) {
    Set-LogFile -Path $env:diskcleanup
    #LogInfo "Using log file from environment: $env:diskcleanup"
} elseif ($global:LogFilePath) {
    Set-LogFile -Path $global:LogFilePath
    #LogInfo "Using log file from global: $global:LogFilePath"
} else {
    $defaultLog = Join-Path $env:TEMP "diskcleanup.txt"
    Set-LogFile -Path $defaultLog
    #LogInfo "Using default log file: $defaultLog"
}

# Return the active log file path if one has already been configured.
<#
    .SYNOPSIS
    Gets log file path.
#>

function Get-DiskCleanupLogFilePath {
    if ($global:LogFilePath) { return $global:LogFilePath }
    if ($env:diskcleanup) { return $env:diskcleanup }
    return $null
}

# Write file content under a mutex so concurrent cleanup operations do not
# corrupt the log or any temporary output file.
<#
    .SYNOPSIS
    Writes file safely.
#>
function Write-DiskCleanupFileSafely {
    param(
        [string]$Path,
        [string]$Value,
        [switch]$Append
    )

    $mutexName = "Global\diskcleanupLogLock"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    $acquired = $mutex.WaitOne(5000)
    try {
        if ($acquired) {
            if ($Append) {
                Add-Content -Path $Path -Value $Value -Encoding UTF8
            } else {
                Set-Content -Path $Path -Value $Value -Encoding UTF8
            }
        }
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
    }
}

$Global:tempDir = ([System.IO.Path]::GetTempPath())

if (-not ("WinAPI.DiskCleanupWindow" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAPI
{
    public static class DiskCleanupWindow
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    }
}
"@ -ErrorAction Stop | Out-Null
}

<#
    .SYNOPSIS
    Sets low disk checks disabled.
#>

function Set-LowDiskChecksDisabled {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Disable,

        [AllowNull()]
        [object]$RestoreValue = $null,

        [switch]$Restore
    )

    $policyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $valueName = "NoLowDiskSpaceChecks"

    if (-not (Test-Path -Path $policyPath)) {
        New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
    }

    if ($Restore) {
        if ($null -eq $RestoreValue) {
            if ($null -ne (Get-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue)) {
                Remove-ItemProperty -Path $policyPath -Name $valueName -Force -ErrorAction SilentlyContinue | Out-Null
            }
        } else {
            New-ItemProperty -Path $policyPath -Name $valueName -PropertyType DWord -Value ([int]$RestoreValue) -Force -ErrorAction Stop | Out-Null
        }
    } elseif ($Disable) {
        New-ItemProperty -Path $policyPath -Name $valueName -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
    }
}

<#
    .SYNOPSIS
    Closes disk space notification window.
#>

function Close-DiskSpaceNotificationWindow {
    $closed = $false
    $windowTitles = @(
        "Disk Space Notification"
    )

    foreach ($windowTitle in $windowTitles) {
        foreach ($windowHandle in @(
            [WinAPI.DiskCleanupWindow]::FindWindow($null, $windowTitle),
            [WinAPI.DiskCleanupWindow]::FindWindow("#32770", $windowTitle)
        )) {
            if ($windowHandle -ne [IntPtr]::Zero) {
                [WinAPI.DiskCleanupWindow]::PostMessage($windowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                $closed = $true
            }
        }
    }

    return $closed
}

<#
    .SYNOPSIS
    Closes cleanup process window.
#>

function Close-CleanupProcessWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    try {
        $Process.Refresh()
    } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'diskcleanup.Close-CleanupProcessWindow:catch199' -Severity Debug }

        return $false
    }

    if ($Process.HasExited) {
        return $true
    }

    if ($Process.MainWindowHandle -eq [IntPtr]::Zero) {
        return $false
    }

    return $Process.CloseMainWindow()
}

<#
    .SYNOPSIS
    Waits for cleanup process and dismiss notification.
#>

function Wait-CleanupProcessAndDismissNotification {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [int]$PostExitSeconds = 60,

        [int]$QuietAfterCloseSeconds = 2,

        [int]$TimeoutSeconds = 900
    )

    $waitDeadline = $null
    if ($TimeoutSeconds -gt 0) {
        $waitDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    }

    $graceDeadline = $null
    $closeLogged = $false
    $quietDeadline = $null
    $cleanupWindowCloseRequested = $false

    while ($true) {
        $now = Get-Date
        try {
            $Process.Refresh()
        } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'diskcleanup.Wait-CleanupProcessAndDismissNotification:catch245' -Severity Debug }

            break
        }

        if ($waitDeadline -and $now -ge $waitDeadline) {
            if (-not $Process.HasExited) {
                LogWarning ("cleanmgr.exe timed out after {0} second(s); stopping process tree." -f $TimeoutSeconds)
                Stop-BaselineProcessTree -Process $Process -Source 'DiskCleanup.CleanmgrTimeout'
            }
            break
        }

        if ($Process.HasExited) {
            if (-not $graceDeadline) {
                $graceDeadline = $now.AddSeconds($PostExitSeconds)
            }

            if ($now -ge $graceDeadline) {
                break
            }
        }

        if (Close-DiskSpaceNotificationWindow) {
            if (-not $closeLogged) {
                LogInfo "Closed Disk Space Notification popup automatically."
                $closeLogged = $true
            }
            $quietDeadline = $now.AddSeconds($QuietAfterCloseSeconds)
        } elseif ($quietDeadline -and $now -ge $quietDeadline -and -not $cleanupWindowCloseRequested) {
            if (Close-CleanupProcessWindow -Process $Process) {
                $cleanupWindowCloseRequested = $true
                $quietDeadline = $now.AddSeconds($QuietAfterCloseSeconds)
            }
        } elseif ($cleanupWindowCloseRequested -and $quietDeadline -and $now -ge $quietDeadline) {
            $Process.Refresh()
            if (-not $Process.HasExited) {
                LogWarning "cleanmgr.exe did not exit after its window was closed; stopping process tree."
                Stop-BaselineProcessTree -Process $Process -Source 'DiskCleanup.CleanmgrTimeout'
            }
            break
        } elseif ($Process.HasExited -and $quietDeadline -and $now -ge $quietDeadline) {
            break
        }

        Start-Sleep -Milliseconds 500
    }

    Close-DiskSpaceNotificationWindow | Out-Null
}

<#
    .SYNOPSIS
    Runs built in silent cleanup.
#>

function Invoke-BuiltInSilentCleanup {
    param(
        [int]$LaunchTimeoutSeconds = 15,

        [int]$TaskTimeoutSeconds = 900
    )

    if (-not (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue) -or
        -not (Get-Command -Name Start-ScheduledTask -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $silentCleanupTask = Get-ScheduledTask -TaskPath "\Microsoft\Windows\DiskCleanup\" -TaskName "SilentCleanup" -ErrorAction Stop
    } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'diskcleanup.Invoke-BuiltInSilentCleanup:catch314' -Severity Debug }

        return $false
    }

    $existingProcessIds = @(Get-Process -Name cleanmgr -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

    Start-ScheduledTask -InputObject $silentCleanupTask -ErrorAction Stop

    $launchDeadline = (Get-Date).AddSeconds($LaunchTimeoutSeconds)
    $taskDeadline = (Get-Date).AddSeconds($TaskTimeoutSeconds)

    while ((Get-Date) -lt $taskDeadline) {
        $newCleanmgrProcess = Get-Process -Name cleanmgr -ErrorAction SilentlyContinue |
            Where-Object { $existingProcessIds -notcontains $_.Id } |
            Select-Object -First 1

        if ($newCleanmgrProcess) {
            $remainingSeconds = [int][Math]::Ceiling(($taskDeadline - (Get-Date)).TotalSeconds)
            if ($remainingSeconds -lt 1) { $remainingSeconds = 1 }

            Wait-CleanupProcessAndDismissNotification -Process $newCleanmgrProcess -TimeoutSeconds $remainingSeconds
            return $true
        }

        try {
            $taskState = (Get-ScheduledTask -TaskPath "\Microsoft\Windows\DiskCleanup\" -TaskName "SilentCleanup" -ErrorAction Stop).State
        } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'diskcleanup.Invoke-BuiltInSilentCleanup:catch340' -Severity Debug }

            break
        }

        if ((Get-Date) -ge $launchDeadline) {
            break
        }

        Start-Sleep -Milliseconds 500
    }

    try {
        $currentTask = Get-ScheduledTask -TaskPath "\Microsoft\Windows\DiskCleanup\" -TaskName "SilentCleanup" -ErrorAction Stop
        if ($currentTask.State -eq "Running" -and (Get-Command -Name Stop-ScheduledTask -ErrorAction SilentlyContinue)) {
            Stop-ScheduledTask -InputObject $currentTask -ErrorAction SilentlyContinue
            LogWarning ("SilentCleanup did not launch a trackable cleanmgr.exe process within {0} second(s); stopped the task and using direct cleanmgr.exe." -f $LaunchTimeoutSeconds)
        }
    } catch {
        LogWarning "SilentCleanup state check failed after launch wait: $($_.Exception.Message)"
    }

    return $false
}

<#
.SYNOPSIS
Removes temporary and unnecessary Windows files, then cleans up superseded system components.
#>
$lowDiskPolicyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$originalLowDiskChecksValue = Get-ItemPropertyValue -Path $lowDiskPolicyPath -Name "NoLowDiskSpaceChecks" -ErrorAction SilentlyContinue
try {
    Set-LowDiskChecksDisabled -Disable $true

    $usedSilentCleanupTask = $false
    try {
        $usedSilentCleanupTask = Invoke-BuiltInSilentCleanup
    } catch {
        LogWarning "SilentCleanup task launch failed. Running direct cleanmgr.exe: $($_.Exception.Message)"
    }

    if (-not $usedSilentCleanupTask) {
        try {
            $cleanmgrProcess = Start-Process -FilePath cleanmgr.exe -ArgumentList "/d C: /VERYLOWDISK" -PassThru -NoNewWindow -ErrorAction Stop
            Wait-CleanupProcessAndDismissNotification -Process $cleanmgrProcess -TimeoutSeconds 900
        } catch {
            LogWarning "Direct cleanmgr.exe launch failed: $($_.Exception.Message)"
        }
    }
    LogInfo "Running cleanmgr.exe completed"
}
finally {
    try {
        Set-LowDiskChecksDisabled -Restore -RestoreValue $originalLowDiskChecksValue -Disable $false
    } catch {
        LogWarning "Failed to restore low disk space checks: $($_.Exception.Message)"
    }
}

# Run DISM component cleanup to remove superseded Windows component store data.
$null = Invoke-BaselineProcess -FilePath 'Dism.exe' -ArgumentList @('/online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart') -TimeoutSeconds 1800
LogInfo "Running DISM Component Cleanup completed"
