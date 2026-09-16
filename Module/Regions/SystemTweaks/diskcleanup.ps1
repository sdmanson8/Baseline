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
using System.Text;

namespace WinAPI
{
    public static class DiskCleanupWindow
    {
        private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder className, int capacity);

        [DllImport("user32.dll")]
        private static extern IntPtr GetDlgItem(IntPtr dialog, int controlId);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool IsWindowEnabled(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        public static bool AcceptNotification(int processId)
        {
            bool accepted = false;
            EnumWindows(delegate(IntPtr window, IntPtr parameter)
            {
                uint ownerId;
                GetWindowThreadProcessId(window, out ownerId);
                if (ownerId != (uint)processId || !IsWindowVisible(window)) return true;

                var className = new StringBuilder(256);
                GetClassName(window, className, className.Capacity);
                if (className.ToString() != "#32770") return true;

                // Standard dialog IDs work across Windows display languages.
                // Progress/cancel dialogs have no IDOK button and are left alone.
                IntPtr okButton = GetDlgItem(window, 1); // IDOK
                if (okButton != IntPtr.Zero && IsWindowVisible(okButton) && IsWindowEnabled(okButton))
                {
                    // Send IDOK / BN_CLICKED without activating the background dialog.
                    accepted |= PostMessage(window, 0x0111, new IntPtr(1), okButton); // WM_COMMAND
                }
                return true;
            }, IntPtr.Zero);
            return accepted;
        }
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
    Waits in the background worker and accepts cleanup completion notifications.
#>
function Wait-CleanupProcessAndDismissNotification {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,

        [int]$TimeoutSeconds = 900
    )

    # Retain the native handle before exit so .NET can still retrieve the exit code.
    $null = $Process.Handle
    $waitDeadline = $null
    if ($TimeoutSeconds -gt 0) {
        $waitDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    }

    while (-not $Process.HasExited) {
        if ([WinAPI.DiskCleanupWindow]::AcceptNotification($Process.Id)) {
            LogInfo "Accepted Disk Cleanup notification automatically."
        }

        if ($waitDeadline -and (Get-Date) -ge $waitDeadline) {
            LogWarning ("cleanmgr.exe timed out after {0} second(s); stopping process tree." -f $TimeoutSeconds)
            Stop-BaselineProcessTree -Process $Process -Source 'DiskCleanup.CleanmgrTimeout'
            throw [TimeoutException]::new("Disk Cleanup exceeded its $TimeoutSeconds second execution limit.")
        }

        Start-Sleep -Milliseconds 500
        $Process.Refresh()
    }
    $Process.WaitForExit()
    if ($null -eq $Process.ExitCode) { throw 'Disk Cleanup exited, but its exit code could not be retrieved.' }
    if ($Process.ExitCode -ne 0) { throw "Disk Cleanup exited with code $($Process.ExitCode)." }
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

            try { Wait-CleanupProcessAndDismissNotification -Process $newCleanmgrProcess -TimeoutSeconds $remainingSeconds }
            finally { $newCleanmgrProcess.Dispose() }
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

    $usedSilentCleanupTask = Invoke-BuiltInSilentCleanup

    if (-not $usedSilentCleanupTask) {
        $cleanupStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $cleanupStartInfo.FileName = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
        $cleanupStartInfo.Arguments = '/d C: /VERYLOWDISK'
        $cleanupStartInfo.UseShellExecute = $false
        $cleanupStartInfo.CreateNoWindow = $true
        $cleanmgrProcess = [System.Diagnostics.Process]::Start($cleanupStartInfo)
        try { Wait-CleanupProcessAndDismissNotification -Process $cleanmgrProcess -TimeoutSeconds 900 }
        finally { $cleanmgrProcess.Dispose() }
    }
    LogInfo "Running cleanmgr.exe completed"
}
catch { LogWarning "Disk Cleanup did not complete: $($_.Exception.Message)" }
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
