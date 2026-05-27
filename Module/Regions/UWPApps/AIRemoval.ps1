<#
    .SYNOPSIS
    Admin utility for disabling and removing Windows AI features such as Copilot, Recall, and related packages.

    .VERSION
    1.0.0

    .DATE
    21.03.2026 - Initial Release
    25.05.2026 - Major upgrades to GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Validates the local Baseline files, enforces Windows PowerShell 5.1,
    relaunches as administrator when needed, initializes logging, and then
    removes or restores AI-related components depending on the selected mode.
    The script supports both a non-interactive command-line workflow and a
    graphical selection window focused on Windows AI features only. This is an
    administrative maintenance script, not a general end-user feature.

    .NOTES
    This script makes system-wide changes, including registry edits, package
    removal, optional feature removal, scheduled task cleanup, and file
    deletion. Some actions use elevated or TrustedInstaller-level operations.

    .EXAMPLE
    # ExecutionPolicy Bypass: required for direct invocation when the system execution policy blocks unsigned scripts
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\UWPApps\AIRemoval.ps1

    .EXAMPLE
    # ExecutionPolicy Bypass: required for direct invocation when the system execution policy blocks unsigned scripts
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\UWPApps\AIRemoval.ps1 -revertMode

    .EXAMPLE
    # ExecutionPolicy Bypass: required for non-interactive/headless invocation where no user is present to adjust policy
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\UWPApps\AIRemoval.ps1 -nonInteractive -AllOptions

    .EXAMPLE
    # ExecutionPolicy Bypass: required for non-interactive/headless invocation where no user is present to adjust policy
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\UWPApps\AIRemoval.ps1 -nonInteractive -AllOptions -backupMode

    .EXAMPLE
    # ExecutionPolicy Bypass: required for non-interactive/headless invocation with selective options
    powershell.exe -ExecutionPolicy Bypass -File .\Module\Regions\UWPApps\AIRemoval.ps1 -nonInteractive -Options RemoveAIFiles,RemoveRecallTasks
#>

param(
    [switch]$nonInteractive,
    [ValidateSet('DisableRegKeys',
        'PreventAIPackageReinstall',
        'DisableCopilotPolicies',
        'RemoveAppxPackages',
        'RemoveRecallFeature',
        'RemoveCBSPackages',
        'RemoveAIFiles',
        'HideAIComponents',
        'DisableRewrite',
        'RemoveRecallTasks',
        'RemoveVoiceAccess')]
    [array]$Options,
    [switch]$AllOptions,
    [switch]$revertMode,
    [switch]$backupMode,
    [string]$LogFilePath
)


if ($nonInteractive) {
    if (!($AllOptions) -and (!$Options -or $Options.Count -eq 0)) {
        throw 'Non-Interactive mode was supplied without any options -  Please use -Options or -AllOptions when using Non-Interactive Mode'
        exit
    }
}

# Resolve the local files this script depends on before any removal work begins.
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$LocalizationRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "Localizations"))
$ModuleRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "Module"))
$AIRemovalPackagePath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "Assets\AIRemovalPackage"))

if (-not (Test-Path -LiteralPath $ModuleRoot -PathType Container))
{
    throw "Module directory not found under: $RepoRoot"
}

$HelpersModulePath = [System.IO.Path]::GetFullPath((Join-Path $ModuleRoot "SharedHelpers.psm1"))
$ModulePath       = [System.IO.Path]::GetFullPath((Join-Path $ModuleRoot "Baseline.psm1"))
$ManifestPath     = [System.IO.Path]::GetFullPath((Join-Path $ModuleRoot "Baseline.psd1"))

$ScriptFiles = @(
	$HelpersModulePath,
	$ModulePath,
	$ManifestPath
)

if (($ScriptFiles | Test-Path) -contains $false)
{
	Write-Information -MessageData "" -InformationAction Continue
	Write-Warning "Required files are missing. Please re-download the archive."
	Write-Information -MessageData "" -InformationAction Continue

	foreach ($File in $ScriptFiles)
	{
		if (-not (Test-Path $File))
		{
			Write-Warning "Missing: $File"
		}
	}

	exit
}

# Load JSON localization helper and localized strings.
. (Join-Path $ModuleRoot 'SharedHelpers\Localization.Helpers.ps1')
$Global:Localization = Import-BaselineLocalization -BaseDirectory $LocalizationRoot -UICulture $PSUICulture
Import-Module -Name $ManifestPath -ErrorAction Stop

Remove-Module -Name Baseline -Force -ErrorAction Ignore

try
{
	Import-Module -Name $ManifestPath -PassThru -Force -ErrorAction Stop | Out-Null
}
catch [System.InvalidOperationException]
{
	Write-Warning -Message $Localization.UnsupportedPowerShell
	exit
}

Import-Module -Name $HelpersModulePath -Force

try {
    if ($Host -and $Host.UI -and $Host.UI.RawUI -and -not $Global:GUIMode) {
        $Host.UI.RawUI.WindowTitle = "Remove Windows AI - Baseline"
    }
}
catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval.ps1:142' -Severity Debug }

    # Silently skip - background runspaces do not support WindowTitle
}

# Require the classic Windows PowerShell 5.1 host.
$runningWindowsPowerShell51 = (
    $PSVersionTable.PSEdition -eq 'Desktop' -and
    $PSVersionTable.PSVersion.Major -eq 5 -and
    $PSVersionTable.PSVersion.Minor -eq 1
)

if (-not $runningWindowsPowerShell51) {
    Write-Host 'ERROR: This script requires Windows PowerShell 5.1 (powershell.exe).' -ForegroundColor Red
    Write-Host "You are currently running PowerShell version $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)." -ForegroundColor Red
    Write-Host 'This host is not supported. Please run the script using the classic Windows PowerShell 5.1.' -ForegroundColor Red
    if (-not $nonInteractive) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "This script must be run in Windows PowerShell 5.1.`n`nCurrent version: $($PSVersionTable.PSVersion)`n`nPlease use powershell.exe.",
                'PowerShell Version Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        catch
        {
            Write-Warning ("Unable to show PowerShell version error dialog: {0}" -f $_.Exception.Message)
        }
    }
    exit 1
}

# Relaunch as administrator before making system changes.
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    $localAIRemovalScript = if ($PSCommandPath)
    {
        $PSCommandPath
    }
    else
    {
        Join-Path -Path $PSScriptRoot -ChildPath 'AIRemoval.ps1'
    }

    if (-not (Test-Path -LiteralPath $localAIRemovalScript -PathType Leaf))
    {
        throw "AIRemoval local script was not found: $localAIRemovalScript"
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $localAIRemovalScript
    )

    if ($nonInteractive) {
        $arguments += '-nonInteractive'

        if ($AllOptions) {
            $arguments += '-AllOptions'
        }

        if ($revertMode) {
            $arguments += '-revertMode'
        }

        if ($backupMode) {
            $arguments += '-backupMode'
        }


        if ($Options -and $Options.count -ne 0) {
            #if options and alloptions is supplied just do all options
            if ($AllOptions) {
                #double check arglist has all options (should already have it)
                if ($arguments -notcontains '-AllOptions') {
                    $arguments += '-AllOptions'
                }
            }
            else {
                $arguments += '-Options'
                $arguments += ($Options -join ',')
            }
        }
    }

    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Run commands as TrustedInstaller when standard elevation is not enough.
<#
    .SYNOPSIS
    Runs run trusted.
#>

function RunTrusted {
    param(
        [String]$command,
        $psversion,
        [string]$logFile
        )

    $psexe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psexe -PathType Leaf)) {
        $psexe = 'powershell.exe'
    }

    $loggingModulePath = [System.IO.Path]::GetFullPath((Join-Path $ModuleRoot "Logging.psm1"))

    # If log file not provided, use current
    if (!$logFile -and (Get-AIRemovalLogFilePath)) {
        $logFile = Get-AIRemovalLogFilePath
    }

    $trustedScriptDirectory = Join-Path $env:ProgramData 'Baseline\AIRemoval'
    New-Item -Path $trustedScriptDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $trustedOperationId = [guid]::NewGuid().ToString('N')
    $trustedScriptPath = Join-Path $trustedScriptDirectory ('TrustedInstaller-{0}.ps1' -f $trustedOperationId)
    $trustedMarkerPath = Join-Path $trustedScriptDirectory ('TrustedInstaller-{0}.complete.json' -f $trustedOperationId)
    $trustedErrorPath = Join-Path $trustedScriptDirectory ('TrustedInstaller-{0}.error.json' -f $trustedOperationId)

    # Pass log file to the new process
    if ($logFile) {
        $escapedLogFile = $logFile -replace "'", "''"
        $escapedLoggingModulePath = $loggingModulePath -replace "'", "''"
        $command = @"
`$env:AIREMOVAL_LOG = '$escapedLogFile'
Import-Module '$escapedLoggingModulePath' -Force
Set-LogFile -Path `$env:AIREMOVAL_LOG
$command
"@
    }

    $escapedTrustedMarkerPath = $trustedMarkerPath -replace "'", "''"
    $escapedTrustedErrorPath = $trustedErrorPath -replace "'", "''"
    $trustedPayload = $command
    $command = @"
try {
$trustedPayload
    `$trustedExitCode = if (`$null -ne `$global:LASTEXITCODE) { [int]`$global:LASTEXITCODE } else { 0 }
    [pscustomobject]@{
        Completed = `$true
        ExitCode = `$trustedExitCode
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$escapedTrustedMarkerPath' -Encoding UTF8 -Force
    if (`$trustedExitCode -ne 0) { exit `$trustedExitCode }
}
catch {
    [pscustomobject]@{
        Completed = `$false
        Message = `$_.Exception.Message
        Type = `$_.Exception.GetType().FullName
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$escapedTrustedErrorPath' -Encoding UTF8 -Force
    exit 1
}
"@
    Set-Content -LiteralPath $trustedScriptPath -Value $command -Encoding UTF8 -Force -ErrorAction Stop

    $trustedInstallerService = Get-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
    if ($trustedInstallerService -and $trustedInstallerService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        try {
            Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        catch {
            $stopError = $_
            try
            {
                $null = Invoke-BaselineProcess -FilePath 'taskkill.exe' -ArgumentList @('/im', 'trustedinstaller.exe', '/f') -TimeoutSeconds 60 -AllowedExitCodes @(0, 128)
            }
            catch
            {
                if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.StopTrustedInstaller.Taskkill' -Severity Warning
                }
            }
            Remove-HandledErrorRecord -ErrorRecord $stopError
        }
    }

    $originalTrustedInstallerBinPath = $null
    $defaultTrustedInstallerBinPath = Join-Path $env:SystemRoot 'servicing\TrustedInstaller.exe'
    $trustedFailure = $null
    $restoreFailure = $null

    try
    {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
        if ($service -and -not [string]::IsNullOrWhiteSpace([string]$service.PathName)) {
            $originalTrustedInstallerBinPath = [string]$service.PathName
        }
        else {
            $originalTrustedInstallerBinPath = $defaultTrustedInstallerBinPath
        }

        $trustedCommand = 'cmd.exe /c "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $psexe, $trustedScriptPath

        LogInfo 'Temporarily changing TrustedInstaller service command to run AIRemoval privileged cleanup.'
        $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('config', 'TrustedInstaller', 'binPath=', $trustedCommand) -TimeoutSeconds 60
        # The payload is a transient PowerShell process, not a service process.
        # SCM exit code 1053 is acceptable here; the marker/error files below are the authoritative result.
        $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('start', 'TrustedInstaller') -TimeoutSeconds 120 -AllowedExitCodes @(0, 1053)
        $trustedDeadline = [DateTime]::UtcNow.AddMinutes(20)
        while ((-not (Test-Path -LiteralPath $trustedMarkerPath -PathType Leaf)) -and
               (-not (Test-Path -LiteralPath $trustedErrorPath -PathType Leaf)) -and
               [DateTime]::UtcNow -lt $trustedDeadline)
        {
            Start-Sleep -Milliseconds 500
        }

        if (Test-Path -LiteralPath $trustedErrorPath -PathType Leaf)
        {
            $trustedError = Get-Content -LiteralPath $trustedErrorPath -Raw -ErrorAction Stop
            throw "TrustedInstaller AIRemoval command failed: $trustedError"
        }

        if (-not (Test-Path -LiteralPath $trustedMarkerPath -PathType Leaf))
        {
            throw "TrustedInstaller AIRemoval command did not report completion within the 20 minute timeout."
        }

        $trustedResult = Get-Content -LiteralPath $trustedMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $trustedResult -or -not $trustedResult.Completed)
        {
            throw "TrustedInstaller AIRemoval command did not produce a valid completion marker."
        }
        if ([int]$trustedResult.ExitCode -ne 0)
        {
            throw "TrustedInstaller AIRemoval command returned exit code $([int]$trustedResult.ExitCode)."
        }
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.RunTrusted:catch380' -Severity Debug }

        $trustedFailure = $_
    }
    finally
    {
        if (-not [string]::IsNullOrWhiteSpace($originalTrustedInstallerBinPath))
        {
            try
            {
                LogInfo 'Restoring TrustedInstaller service command after AIRemoval privileged cleanup.'
                $null = Invoke-BaselineProcess -FilePath 'sc.exe' -ArgumentList @('config', 'TrustedInstaller', 'binPath=', $originalTrustedInstallerBinPath) -TimeoutSeconds 60
            }
            catch
            {
                if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                {
                    Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.RestoreTrustedInstaller' -Severity Error
                }
                $restoreFailure = $_
            }
        }

        $trustedInstallerService = Get-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
        if ($trustedInstallerService -and $trustedInstallerService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            try {
                Stop-Service -Name TrustedInstaller -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            }
            catch {
                $stopError = $_
                try
                {
                    $null = Invoke-BaselineProcess -FilePath 'taskkill.exe' -ArgumentList @('/im', 'trustedinstaller.exe', '/f') -TimeoutSeconds 60 -AllowedExitCodes @(0, 128)
                }
                catch
                {
                    if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
                    {
                        Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.FinalStopTrustedInstaller.Taskkill' -Severity Warning
                    }
                }
                Remove-HandledErrorRecord -ErrorRecord $stopError
            }
        }
        Remove-Item -LiteralPath $trustedScriptPath -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -LiteralPath $trustedMarkerPath -Force -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -LiteralPath $trustedErrorPath -Force -ErrorAction SilentlyContinue | Out-Null
    }

    if ($restoreFailure)
    {
        throw [System.InvalidOperationException]::new('Failed to restore the TrustedInstaller service command after AIRemoval privileged cleanup.', $restoreFailure.Exception)
    }
    if ($trustedFailure)
    {
        throw $trustedFailure.Exception
    }
}

function Invoke-AIRemovalNativeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [object[]]$ArgumentList = @(),

        [int]$TimeoutSeconds = 120,

        [int[]]$AllowedExitCodes = @(0)
    )

    return Invoke-BaselineProcess -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes $AllowedExitCodes
}

function Invoke-AIRemovalTakeOwnership {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$Recurse
    )

    $arguments = @('/f', $Path)
    if ($Recurse) {
        $arguments += @('/r', '/d', 'Y')
    }

    $null = Invoke-AIRemovalNativeProcess -FilePath 'takeown.exe' -ArgumentList $arguments -TimeoutSeconds 120
}

function Grant-AIRemovalAdministratorsFullControl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $null = Invoke-AIRemovalNativeProcess -FilePath 'icacls.exe' -ArgumentList @($Path, '/grant', '*S-1-5-32-544:F', '/t') -TimeoutSeconds 120
}

function Invoke-AIRemovalReg {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ArgumentList,

        [int[]]$AllowedExitCodes = @(0),

        [int]$TimeoutSeconds = 120,

        [switch]$CaptureOutput
    )

    return Invoke-BaselineProcess -FilePath 'reg.exe' -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes $AllowedExitCodes -CaptureOutput:$CaptureOutput
}

function Invoke-AIRemovalDism {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ArgumentList,

        [int[]]$AllowedExitCodes = @(0),

        [int]$TimeoutSeconds = 1800,

        [switch]$CaptureOutput
    )

    return Invoke-BaselineProcess -FilePath 'dism.exe' -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -AllowedExitCodes $AllowedExitCodes -CaptureOutput:$CaptureOutput
}

#=====================================================================================
# Script setup, status output, logging, and shared runtime state
#=====================================================================================

# Write short progress text for the interactive workflow.
<#
    .SYNOPSIS
    Writes status.
#>

function Write-Status {
    param(
        [string]$msg,
        [switch]$errorOutput,
        [switch]$warningOutput
    )
    if ($errorOutput) {
        Write-ConsoleStatus -Status failed
    }
    elseif ($warningOutput) {
        Write-ConsoleStatus -Status warning
    }
    else {
        $action = ($msg -replace '\s*-\s*$', '').Trim()
        if (-not [string]::IsNullOrWhiteSpace($action)) {
            Write-ConsoleStatus -Action $action
        }
    }
}

# Import the shared logging module and choose the active log file path.
$LoggingModulePath = [System.IO.Path]::GetFullPath((Join-Path $ModuleRoot "Logging.psm1"))
Import-Module -Name $LoggingModulePath -Force

# Track the active log path locally so standalone runs do not inherit Baseline's
# global log unless Baseline passes it explicitly.
$script:ActiveLogFilePath = Join-Path $env:TEMP "Remove Windows AI.txt"

# Log file priority: explicit parameter, environment variable, then the
# standalone fallback file.
if ($LogFilePath) {
    $script:ActiveLogFilePath = $LogFilePath
} elseif ($env:AIREMOVAL_LOG) {
    $script:ActiveLogFilePath = $env:AIREMOVAL_LOG
}

Set-LogFile -Path $script:ActiveLogFilePath

function Write-AIRemovalSwallowedException {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory)]
        [string]$Source,

        [ValidateSet('Debug', 'Warning', 'Error')]
        [string]$Severity = 'Debug'
    )

    if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) {
        Write-SwallowedException -ErrorRecord $ErrorRecord -Source $Source -Severity $Severity
        return
    }

    Write-Verbose ("{0}: {1}" -f $Source, $ErrorRecord.Exception.Message)
}

# Return the active log file path for helper functions that need it.
<#
    .SYNOPSIS
    Gets log file path.
#>

function Get-AIRemovalLogFilePath {
    return $script:ActiveLogFilePath
}

# Write shared files under a mutex so concurrent operations do not corrupt them.
<#
    .SYNOPSIS
    Writes file safely.
#>
function Write-AIRemovalFileSafely {
    param(
        [string]$Path,
        [string]$Value,
        [switch]$Append
    )

    $mutexName = "Global\AIRemovalLogLock"
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

if ($revertMode) {
    $Global:revert = 1
}
else {
    $Global:revert = 0
}

if ($backupMode) {
    $Global:backup = 1
}
else {
    $Global:backup = 0
}

$Global:tempDir = ([System.IO.Path]::GetTempPath())

#=====================================================================================

# Create a restore point before making destructive changes when backup mode is enabled.
<#
    .SYNOPSIS
    Runs create restore point.
#>

function New-AIRemovalRestorePoint {
    param(
        [switch]$nonInteractive
    )

    #check vss service first
    $vssService = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
    if ($vssService -and $vssService.StartType -eq 'Disabled') {
        try {
            Write-Status -msg 'Enabling VSS Service - '
            LogInfo 'Enabling VSS Service'
            Set-Service -Name 'VSS' -StartupType Manual -ErrorAction SilentlyContinue | Out-Null
            Start-Service -Name 'VSS' -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            LogError 'Unable to Start VSS Service -  Can not create restore point!'
            return
        }

    }
    #enable system protection to allow restore points
    $restoreEnabled = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    if (!$restoreEnabled) {
       # Write-Status -msg 'Enabling Restore Points on System - '
       # LogInfo 'Enabling Restore Points on System'
        Enable-ComputerRestore -Drive "$env:SystemDrive\"

    }

    if ($nonInteractive) {
        #allow restore point to be created even if one was just made
        $restoreFreqPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $restoreFreqKey = 'SystemRestorePointCreationFrequency'
        $currentValue = (Get-ItemProperty -Path $restoreFreqPath -Name $restoreFreqKey -ErrorAction SilentlyContinue).$restoreFreqKey
        if ($currentValue -ne 0) {
            Set-ItemProperty -Path $restoreFreqPath -Name $restoreFreqKey -Value 0 -Force
        }

        $restorePointName = "AIRemoval-$(Get-Date -Format 'yyyy-MM-dd')"
        Write-Status -msg "Creating Restore Point - "
        LogInfo "Creating Restore Point: [$restorePointName]"
       # Write-Status -msg 'This may take a moment - please wait'
        Checkpoint-Computer -Description $restorePointName -RestorePointType 'MODIFY_SETTINGS'
        Write-ConsoleStatus -Status success
}
    else {
        #allow restore point to be created even if one was just made
        $restoreFreqPath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $restoreFreqKey = 'SystemRestorePointCreationFrequency'
        $currentValue = (Get-ItemProperty -Path $restoreFreqPath -Name $restoreFreqKey -ErrorAction SilentlyContinue).$restoreFreqKey
        if ($currentValue -ne 0) {
            Set-ItemProperty -Path $restoreFreqPath -Name $restoreFreqKey -Value 0 -Force
        }

        $restorePointName = "AIRemoval-$(Get-Date -Format 'yyyy-MM-dd')"
        Write-Status -msg "Creating Restore Point - "
        LogInfo "Creating Restore Point: [$restorePointName]"
       # Write-Status -msg 'This may take a moment - please wait'
        Checkpoint-Computer -Description $restorePointName -RestorePointType 'MODIFY_SETTINGS'
        Write-ConsoleStatus -Status success
}

}

 # Update per-app UWP settings by loading and editing the app's settings.dat hive.
<#
    .SYNOPSIS
    Sets UWP app registry entry.
#>

function Set-UwpAppRegistryEntry {
    # modified to work in windows powershell from https://github.com/agadiffe/WindowsMize/blob/fe78912ccb1c83d440bd2123f5e43a6156fab31a/src/modules/applications/settings/public/Set-UwpAppSetting.ps1
    <#
    .SYNOPSIS
        Modifies UWP app registry entries in the settings.dat file.

    .EXAMPLE
        PS> $setting = [PSCustomObject]@{
                Name  = 'VideoAutoplay'
                Value = '0'
                Type  = '5f5e10b'
            }
        PS> $setting | Set-UwpAppRegistryEntry -FilePath $FilePath
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [string] $FilePath
    )

    begin {
        $AppSettingsRegPath = 'HKEY_USERS\APP_SETTINGS'
        $AppSettingsRegMountPath = 'HKU\APP_SETTINGS'
        $RegContent = "Windows Registry Editor Version 5.00`n"

        $null = Invoke-AIRemovalReg -ArgumentList @('UNLOAD', $AppSettingsRegMountPath) -AllowedExitCodes @(0, 1)

        $max = 30
        $attempts = 0
        $ProcessToStop = @(
            'AppActions'
            'SearchHost'
            'FESearchHost'
            'msedgewebview2'
            'TextInputHost'
            'VisualAssistExe'
            'WebExperienceHostApp'
        )
        Stop-Process -Name $ProcessToStop -Force -ErrorAction SilentlyContinue | Out-Null
        # Use bounded polling because Wait-Process can return before the profile hive lock is released.
        # The Microsoft example waits for process exit only, not for registry hive availability.
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/wait-process?view=powershell-7.5#example-1-stop-a-process-and-wait

        # since we are trying multiple times while the processes are stopping this will work as soon as the file is freed
        do {
            $loadResult = Invoke-AIRemovalReg -ArgumentList @('LOAD', $AppSettingsRegMountPath, $FilePath) -AllowedExitCodes @(0, 1)
            $global:LASTEXITCODE = $loadResult.ExitCode
            $attempts++
        } while ($LASTEXITCODE -ne 0 -and $attempts -lt $max)

        if ($LASTEXITCODE -ne 0) {
            LogError 'Unable to load settings.dat'
            return
        }

    }

    process {
        $Value = $InputObject.Value
        $Value = switch ($InputObject.Type) {
            '5f5e10b' {
                # Single byte for boolean
                '{0:x2}' -f [byte][int]$Value
            }
            '5f5e10c' {
                # Unicode string
                $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value + "`0")
                ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
            }
            '5f5e104' {
                # Int32
                $bytes = [BitConverter]::GetBytes([int]$Value)
                ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
            }
            '5f5e105' {
                # UInt32
                $bytes = [BitConverter]::GetBytes([uint32]$Value)
                ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
            }
            '5f5e106' {
                # Int64
                $bytes = [BitConverter]::GetBytes([int64]$Value)
                ($bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
            }
        }

        $Value = $Value -replace '\s+', ','

        # create timestamp for remaining bytes
        $timestampBytes = [BitConverter]::GetBytes([int64](Get-Date).ToFileTime())
        $Timestamp = ($timestampBytes | ForEach-Object { '{0:x2}' -f $_ }) -join ','

        # build registry content
        if ($InputObject.Path) {
            $RegKey = $InputObject.Path
        }
        else {
            $RegKey = 'LocalState'
        }
        $RegContent += "`n[$AppSettingsRegPath\$RegKey]
        ""$($InputObject.Name)""=hex($($InputObject.Type)):$Value,$Timestamp`n" -replace '(?m)^ *'
    }

    end {
        $SettingRegFilePath = "$($tempDir)uwp_app_settings.reg"
        $RegContent | Out-File -FilePath $SettingRegFilePath

        $null = Invoke-AIRemovalReg -ArgumentList @('IMPORT', $SettingRegFilePath)
        $null = Invoke-AIRemovalReg -ArgumentList @('UNLOAD', $AppSettingsRegMountPath) -AllowedExitCodes @(0, 1)

        Remove-Item -Path $SettingRegFilePath -Force -ErrorAction SilentlyContinue
    }
}

# Retry protected registry writes through TrustedInstaller when the current token
# is blocked by ACLs on newer Windows builds.
<#
    .SYNOPSIS
    Runs trusted registry write.
#>

function Invoke-TrustedRegistryWrite {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'String')]
        [string]$Type
    )

    $nativePath = ConvertTo-NativeRegistryPath -Path $Path
    $regType = ConvertTo-RegExeValueType -Type $Type
    $escapedPath = $nativePath.Replace("'", "''")
    $escapedName = $Name.Replace("'", "''")
    $escapedValue = ([string]$Value).Replace("'", "''")
    $logFile = Get-AIRemovalLogFilePath
    $resultMarkerPath = Join-Path $env:TEMP ("AIRemoval_TI_{0}.marker" -f ([guid]::NewGuid().ToString('N')))
    $escapedMarkerPath = $resultMarkerPath.Replace("'", "''")

    Remove-Item -Path $resultMarkerPath -Force -ErrorAction SilentlyContinue

    $command = @"
& reg.exe add '$escapedPath' /v '$escapedName' /t $regType /d '$escapedValue' /f *>`$null
if (`$LASTEXITCODE -eq 0) {
    Set-Content -Path '$escapedMarkerPath' -Value 'ok' -Encoding ASCII -Force
}
"@

    RunTrusted -command $command -psversion $Global:psversion -logFile $logFile
    Start-Sleep -Milliseconds 300

    if (Test-Path -Path $resultMarkerPath) {
        Remove-Item -Path $resultMarkerPath -Force -ErrorAction SilentlyContinue
        return $true
    }

    try {
        $currentValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name

        if ($Type -eq 'DWord') {
            return ([int]$currentValue -eq [int]$Value)
        }

        return ([string]$currentValue -eq [string]$Value)
    }
    catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Invoke-TrustedRegistryWrite:catch888' -Severity Debug }

        return $false
    }
}

# Apply AIRemoval-specific access denied handling on top of the shared
# safe registry setter from SharedHelpers.psm1.
<#
    .SYNOPSIS
    Sets AI removal registry value.
#>

function Set-AIRemovalRegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'String')]
        [string]$Type,

        [switch]$TryTrustedInstallerOnAccessDenied,
        [switch]$SkipOnAccessDenied
    )

    $params = @{
        Path = $Path
        Name = $Name
        Value = $Value
        Type = $Type
        SkipOnAccessDenied = $SkipOnAccessDenied
    }

    if ($TryTrustedInstallerOnAccessDenied) {
        $params.AccessDeniedFallback = {
            param($DeniedPath, $DeniedName, $DeniedValue, $DeniedType)
            Invoke-TrustedRegistryWrite -Path $DeniedPath -Name $DeniedName -Value $DeniedValue -Type $DeniedType
        }
    }

    if ($SkipOnAccessDenied) {
        $params.OnAccessDenied = {
            param($DeniedPath, $DeniedName)
            LogInfo "Skipping registry value '$DeniedName' at '$DeniedPath' because access was denied."
        }
    }

    Set-RegistryValueSafe @params
}

# Disable AI-related registry settings for Windows, Edge, Search, and privacy features.
<#
    .SYNOPSIS
    Disables registry keys.
#>

function Disable-Registry-Keys {
    # Disable AI registry keys.
    Write-Status -msg "$(@('Disabling', 'Enabling')[$revert]) Copilot and Recall - "
    LogInfo "$(@('Disabling', 'Enabling')[$revert]) Copilot and Recall"
    <#
    #new keys related to windows ai schedled task
    #npu check
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'HardwareCompatibility' /t REG_DWORD /d '0' /f
    #dont know
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'ITManaged' /t REG_DWORD /d '0' /f
    #enabled by windows ai schedled task
    #set to 1 in the us
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'AllowedInRegion' /t REG_DWORD /d '0' /f
    #enabled by windows ai schelded task
    # policy enabled = 1 when recall is enabled in group policy
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'PolicyConfigured' /t REG_DWORD /d '0' /f
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'PolicyEnabled' /t REG_DWORD /d '0' /f
    # Mark hardware compatibility checks as not satisfied.
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'FTDisabledState' /t REG_DWORD /d '0' /f
    # Disable additional NPU/driver eligibility checks.
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'MeetsAdditionalDriverRequirements' /t REG_DWORD /d '0' /f
    #sucess from last run
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'LastOperationKind' /t REG_DWORD /d '2' /f
    #doesnt install recall for me so 0
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'AttemptedInstallCount' /t REG_DWORD /d '0' /f
    #windows build
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'LastBuild' /t REG_DWORD /d '7171' /f
    #5 for no good reason
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /v 'MaxInstallAttemptsAllowed' /t REG_DWORD /d '5' /f
    #>

    if (!$revert) {
        #removing it does not get remade on restart so we will just remove it for now
        Reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /f *>$null

        Reg.exe delete 'HKCU\Software\Microsoft\Windows\Shell\Copilot' /v 'CopilotLogonTelemetryTime' /f *>$null
        Reg.exe delete 'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.Copilot_8wekyb3d8bbwe\Copilot.StartupTaskId' /f *>$null
        Reg.exe delete 'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe\WebViewHostStartupId' /f *>$null
        Reg.exe delete 'HKCU\Software\Microsoft\Copilot' /v 'WakeApp' /f *>$null
    }

    #set for local machine and current user to be sure
    $hives = @('HKLM', 'HKCU')
    foreach ($hive in $hives) {
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v 'TurnOffWindowsCopilot' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAIDataAnalysis' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'AllowRecallEnablement' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableClickToDo' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'TurnOffSavingSnapshots' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableSettingsAgent' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAgentConnectors' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableAgentWorkspaces' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableRemoteAgentConnectors' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        #only for insiders using enterprise or education as of right now (12/23/25)
        #Reg.exe add "$hive\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v 'DisableRecallDataProviders' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat" /v 'IsUserEligible' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v 'IsCopilotAvailable' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
        Reg.exe add "$hive\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v 'CopilotDisabledReason' /t REG_SZ /d @('FeatureIsDisabled', ' ')[$revert] /f *>$null
    }
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\Microsoft.Copilot_8wekyb3d8bbwe' /v 'Value' /t REG_SZ /d @('Deny', 'Prompt')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe' /v 'Value' /t REG_SZ /d @('Deny', 'Prompt')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels' /v 'Value' /t REG_SZ /d @('Deny', 'Prompt')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\Capabilities\systemAIModels' /v 'RecordUsageData' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' /v 'AgentActivationEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v 'ShowCopilotButton' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\input\Settings' /v 'InsightsEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\Shell\ClickToDo' /v 'DisableClickToDo' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Write-ConsoleStatus -Status success
#remove copilot from search
    Write-Status -msg "$(@('Disabling', 'Enabling')[$revert]) Copilot In Windows Search - "
    LogInfo "$(@('Disabling', 'Enabling')[$revert]) Copilot In Windows Search"
    Reg.exe add 'HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer' /v 'DisableSearchBoxSuggestions' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Write-ConsoleStatus -Status success
#disable copilot in edge
    Write-Status -msg "$(@('Disabling', 'Enabling')[$revert]) Copilot In Edge - "
    LogInfo "$(@('Disabling', 'Enabling')[$revert]) Copilot In Edge"
    #keeping depreciated policies incase user has older versions of edge

    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'CopilotCDPPageContext' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null #depreciated shows Unknown policy in edge://policy
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'CopilotPageContext' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'HubsSidebarEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'EdgeEntraCopilotPageContext' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'Microsoft365CopilotChatIconEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null #depreciated shows Unknown policy in edge://policy
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'EdgeHistoryAISearchEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'ComposeInlineEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'GenAILocalFoundationalModelSettings' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'BuiltInAIAPIsEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'AIGenThemesEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'DevToolsGenAiSettings' /t REG_DWORD /d @('2', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Edge' /v 'ShareBrowsingHistoryWithCopilotSearchAllowed' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    #disable edge copilot mode
    # "enabled_labs_experiments":["edge-copilot-mode@2"]
    # view flags at edge://flags
    $null = Invoke-BaselineProcess -FilePath 'taskkill.exe' -ArgumentList @('/im', 'msedge.exe', '/f') -TimeoutSeconds 60 -AllowedExitCodes @(0, 128)
    $config = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
    . (Join-Path $PSScriptRoot 'AIRemoval\Disable-Registry-Keys\EdgeCopilotFlagPolicy.ps1')

    #disable office ai with group policy
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\training\general' /v 'disabletraining' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\training\specific\adaptivefloatie' /v 'disabletrainingofadaptivefloatie' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable connected experiences in office should prevent copilot from working
    Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\common\privacy' /v 'controllerconnectedservicesenabled' /t REG_DWORD /d @('2', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\common\privacy' /v 'usercontentdisabled' /t REG_DWORD /d @('2', '1')[$revert] /f *>$null
    #disable copilot buttons in word
    #Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\word\disabledcmdbaritemslist' /v 'TCID1' /t REG_SZ /d '47229' /f
    #Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\word\disabledcmdbaritemslist' /v 'TCID2' /t REG_SZ /d '43223' /f
    #Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\word\disabledcmdbaritemslist' /v 'TCID3' /t REG_SZ /d '34872' /f
    #Reg.exe add 'HKCU\Software\Policies\Microsoft\office\16.0\word\disabledcmdbaritemslist' /v 'TCID4' /t REG_SZ /d '42552' /f
    #disable copilot in word
    Reg.exe add 'HKCU\Software\Microsoft\Office\16.0\Word\Options' /v 'EnableCopilot' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    #disable copilot in excel
    Reg.exe add 'HKCU\Software\Microsoft\Office\16.0\Excel\Options' /v 'EnableCopilot' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    #disable copilot in onenote
    Reg.exe add 'HKCU\Software\Microsoft\Office\16.0\OneNote\Options\Copilot' /v 'CopilotEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Office\16.0\OneNote\Options\Copilot' /v 'CopilotNotebooksEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Office\16.0\OneNote\Options\Copilot' /v 'CopilotSkittleEnabled' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    #disable office ai content safety
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\general' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\alternativetext' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\imagequestionandanswering' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\promptassistance' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\rewrite' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\summarization' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\summarizationwithreferences' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\texttotable' /v 'disablecontentsafety' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable additional keys
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' /v 'AutoOpenCopilotLargeScreens' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI' /v 'Value' /t REG_SZ /d @('Deny', 'Allow')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels' /v 'Value' /t REG_SZ /d @('Deny', 'Allow')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' /v 'LetAppsAccessGenerativeAI' /t REG_DWORD /d @('2', '1')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' /v 'LetAppsAccessSystemAIModels' /t REG_DWORD /d @('2', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot' /v 'AllowCopilotRuntime' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins' /v 'CopilotPWAPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins' /v 'RecallPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    #disable copilot background app access
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe' /v 'DisabledByUser' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe' /v 'Disabled' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe' /v 'SleepDisabled' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe' /v 'DisabledByUser' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe' /v 'Disabled' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe' /v 'SleepDisabled' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable for all users
    $sids = (Get-ChildItem 'registry::HKEY_USERS').Name | Where-Object { $_ -like 'HKEY_USERS\S-1-5-21*' -and $_ -notlike '*Classes*' }
    foreach ($sid in $sids) {
        Reg.exe add "$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" /v 'CopilotPWAPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
        Reg.exe add "$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins" /v 'RecallPin' /t REG_DWORD /d @('0', '1')[$revert] /f *>$null
    }
    #disable ai actions
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1853569164' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\4098520719' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\929719951' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #enable new feature to hide ai actions in context menu when none are avaliable
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1646260367' /v 'EnabledState' /t REG_DWORD /d @('2', '0')[$revert] /f *>$null
    #disable additional ai velocity ids found from: https://github.com/phantomofearth/windows-velocity-feature-lists
    #keep in mind these may or may not do anything depending on the windows build
    #disable copilot nudges
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\1546588812' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\203105932' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\2381287564' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3189581453' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3552646797' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable copilot in taskbar and systray
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3389499533' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\4027803789' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\450471565' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #enable removing ai componets (not sure what this does yet)
    #Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\2931206798' /v 'EnabledState' /t REG_DWORD /d '2' /f
    #Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3098978958' /v 'EnabledState' /t REG_DWORD /d '2' /f
    #Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3233196686' /v 'EnabledState' /t REG_DWORD /d '2' /f
    #disable core ai / click to do with feature management
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\2283032206' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\502943886' /v 'EnabledState' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable ask copilot (taskbar search)
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarCompanion' -Type DWord -Value @([int]0, [int]1)[$revert]
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\Shell\BrandedKey' -Name 'BrandedKeyChoiceType' -Type String -Value @('Search', 'App')[$revert] -TryTrustedInstallerOnAccessDenied -SkipOnAccessDenied | Out-Null
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\Shell\BrandedKey' -Name 'AppAumid' -Type String -Value @(' ', 'Microsoft.Copilot_8wekyb3d8bbwe!App')[$revert] -TryTrustedInstallerOnAccessDenied -SkipOnAccessDenied | Out-Null
    Set-AIRemovalRegistryValue -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CopilotKey' -Name 'SetCopilotHardwareKey' -Type String -Value @(' ', 'Microsoft.Copilot_8wekyb3d8bbwe!App')[$revert]
    #disable recall customized homepage
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SettingSync\WindowsSettingHandlers' -Name 'A9HomeContentEnabled' -Type DWord -Value @([int]0, [int]1)[$revert]
    #disable typing data harvesting for ai training
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Type DWord -Value @([int]1, [int]0)[$revert]
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Type DWord -Value @([int]1, [int]0)[$revert]
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Type DWord -Value @([int]0, [int]1)[$revert]
    Set-AIRemovalRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization' -Name 'Value' -Type DWord -Value @([int]0, [int]1)[$revert]
    #hide copilot ads in settings home page
    Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' /v 'DisableConsumerAccountStateContent' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    #disable office hub startup
    Reg.exe add 'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe\WebViewHostStartupId' /v 'State' /t REG_DWORD /d @('1', '2')[$revert] /f *>$null
    Write-ConsoleStatus -Status success
#disable ai image creator in paint
    Write-Status -msg "$(@('Disabling', 'Enabling')[$revert]) Image Creator In Paint - "
    LogInfo "$(@('Disabling', 'Enabling')[$revert]) Image Creator In Paint"
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' /v 'DisableImageCreator' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' /v 'DisableCocreator' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' /v 'DisableGenerativeFill' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' /v 'DisableGenerativeErase' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' /v 'DisableRemoveBackground' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
    # disable experimental agentic features
    # Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\IsoEnvBroker" /v "Enabled" /t REG_DWORD /d "0" /f
    # Reg.exe add "HKLM\SYSTEM\ControlSet001\Services\IsoEnvBroker" /v "Enabled" /t REG_DWORD /d "0" /f
    # leaving commented since its still only in preview builds
    Write-ConsoleStatus -Status success
# Apply the same defaults to future users via the default profile hive.
    $defaultUserHiveFile = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    $defaultUserHiveMount = 'HKU\AIRemoval_DefaultUser'
    $defaultUserHivePsPath = 'Registry::HKEY_USERS\AIRemoval_DefaultUser'

    [GC]::Collect()
    $hiveloaded = Mount-RegistryHive -MountPath $defaultUserHiveMount -PsPath $defaultUserHivePsPath -HiveFile $defaultUserHiveFile
    if (-not $hiveloaded) {
        LogWarning 'Unable to load the default user hive'
    }

    . (Join-Path $PSScriptRoot 'AIRemoval\Disable-Registry-Keys\DefaultUserAiPolicy.ps1')

    #disable ask copilot in context menu
    if ($revert) {
        Reg.exe delete 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' /v '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' /f *>$null
    }
    else {
        Reg.exe add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' /v '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}' /t REG_SZ /d 'Ask Copilot' /f *>$null
    }
    #Reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Services\WSAIFabricSvc' /v 'Start' /t REG_DWORD /d @('4', '2')[$revert] /f *>$null
    try {
        Stop-Service -Name WSAIFabricSvc -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Disable-Registry-Keys:catch1176' -Severity Debug }

        #ignore error when svc is already removed
    }
    Write-ConsoleStatus -Status success
$backupPath = "$PSScriptRoot\AIRemoval\Backup"
    $backupFileWSAI = 'WSAIFabricSvc.reg'
    $backupFileAAR = 'AARSVC.reg'
    . (Join-Path $PSScriptRoot 'AIRemoval\Disable-Registry-Keys\WSAIFabricServicePolicy.ps1')

    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture'
    $allFX = (Get-ChildItem $root -Recurse).Name | Where-Object { $_ -like '*FxProperties' }
    #search the fx props for VocalEffectPack and add {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5 = 1
    foreach ($fxPath in $allFX) {
        $keys = Get-ItemProperty "registry::$fxPath"
        foreach ($key in $keys) {
            if ($key | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like '{*},*' } | Where-Object { $_.Definition -like '*#VocaEffectPack*' }) {
                Write-Status -msg "$(@('Disabling','Enabling')[$revert]) AI Voice Effects - "
                LogInfo "$(@('Disabling','Enabling')[$revert]) AI Voice Effects"
                $regPath = Convert-Path $key.PSPath
                if ($revert) {
                    #enable
                    $command = "Reg.exe delete '$regPath' /v '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' /f"
                    RunTrusted -command $command -psversion $psversion -logFile $logFile
                }
                else {
                    #disable
                    $command = "Reg.exe add '$regPath' /v '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5' /t REG_DWORD /d '1' /f"
                    RunTrusted -command $command -psversion $psversion -logFile $logFile
                }
            Write-ConsoleStatus -Status success
}
        }
    }

    #disable gaming copilot
    #found from: https://github.com/meetrevision/playbook/issues/197
    #not sure this really does anything in my testing gaming copilot still appears
    if ($revert) {
        $command = "reg delete 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.Xbox.GamingAI.Companion.Host.GamingCompanionHostOptions' /f"
        RunTrusted -command $command -psversion $psversion -logFile $logFile
    }
    else {
        $command = "reg add 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.Xbox.GamingAI.Companion.Host.GamingCompanionHostOptions' /v 'ActivationType' /t REG_DWORD /d 0 /f;
    reg add 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.Xbox.GamingAI.Companion.Host.GamingCompanionHostOptions' /v 'Server' /t REG_SZ /d `" `" /f
    "
        RunTrusted -command $command -psversion $psversion -logFile $logFile
    }


    #remove windows ai dll contracts
    $command = "
    Reg delete 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\WellKnownContracts' /v 'Windows.AI.Actions.ActionsContract' /f
    Reg delete 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\WellKnownContracts' /v 'Windows.AI.Agents.AgentsContract' /f
    Reg delete 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\WellKnownContracts' /v 'Windows.AI.MachineLearning.MachineLearningContract' /f
    Reg delete 'HKLM\SOFTWARE\Microsoft\WindowsRuntime\WellKnownContracts' /v 'Windows.AI.MachineLearning.Preview.MachineLearningPreviewContract' /f
    "
    RunTrusted -command $command -psversion $psversion -logFile $logFile

    #disable ai setting in uwp photos app
    $uwpPhotosSettings = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.Photos_8wekyb3d8bbwe\Settings\settings.dat"
    . (Join-Path $PSScriptRoot 'AIRemoval\Disable-Registry-Keys\PhotosSettingsPolicy.ps1')

    #disable app actions
    #method credit : https://github.com/agadiffe/WindowsMize
    $settingsDat = "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\Settings\settings.dat"

    if (Test-Path $settingsDat) {
        Write-Status -msg "$(@('Disabling','Enabling')[$revert]) App Actions - "
        LogInfo "$(@('Disabling','Enabling')[$revert]) App Actions"

        $apps = @(
            'Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe'
            'Microsoft.Office.ActionsServer_8wekyb3d8bbwe'
            'MSTeams_8wekyb3d8bbwe'
            'Microsoft.Paint_8wekyb3d8bbwe'
            'Microsoft.Windows.Photos_8wekyb3d8bbwe'
            'MicrosoftWindows.Client.CBS_cw5n1h2txyewy' #describe image (system)
        )

        foreach ($app in $apps) {
            $setting = [PSCustomObject]@{
                Name  = $app
                Path  = 'LocalState\DisabledApps'
                Value = @('1', '0')[$revert] # 1 = disable    0 = enable
                Type  = '5f5e10b'
            }

            $setting | Set-UwpAppRegistryEntry -FilePath $settingsDat
        }
        Write-ConsoleStatus -Status success
}


    #force policy changes
    #Write-Status -msg 'Applying Registry Changes'
    LogInfo "Applying Registry Changes"
    gpupdate /force /wait:0 >$null
}

<#
    .SYNOPSIS
    Removes voice access.
#>

function Remove-Voice-Access {
    Reg.exe add 'HKCU\Software\Microsoft\VoiceAccess' /v 'RunningState' /t REG_DWORD /d @('0', '1')[$revert] /f >$null
    Reg.exe add 'HKCU\Software\Microsoft\VoiceAccess' /v 'TextCorrection' /t REG_DWORD /d @('1', '2')[$revert] /f >$null
    Reg.exe add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AccessibilityTemp' /v @('0', '1')[$revert] /t REG_DWORD /d '0' /f >$null
    $startMenu = "$env:appdata\Microsoft\Windows\Start Menu\Programs\Accessibility"
    $voiceExe = "$env:windir\System32\voiceaccess.exe"

    if ($backup) {
        Write-Status -msg 'Backing up Voice Access - '
        LogInfo 'Backing up Voice Access'
        if (!(Test-Path $backupPath)) {
            New-Item $backupPath -Force -ItemType Directory | Out-Null
        }
        Copy-Item $voiceExe -Destination $backupPath -Force -ErrorAction SilentlyContinue | Out-Null
        Copy-Item "$startMenu\VoiceAccess.lnk" -Destination $backupPath -Force -ErrorAction SilentlyContinue | Out-Null
        Write-ConsoleStatus -Status success
    }

    if ($revert) {
        if ((Test-Path "$backupPath\VoiceAccess.exe") -and (Test-Path "$backupPath\VoiceAccess.lnk")) {
            Write-Status -msg 'Restoring Voice Access - '
            LogInfo 'Restoring Voice Access'
            Move-Item "$backupPath\VoiceAccess.exe" -Destination "$env:windir\System32" -Force | Out-Null
            Move-Item "$backupPath\VoiceAccess.lnk" -Destination $startMenu -Force | Out-Null
            Write-ConsoleStatus -Status success
        }
        else {
            LogError 'Voice Access Backup NOT Found!'
        }
    }
    else {
        Write-Status -msg 'Removing Voice Access - '
        LogInfo 'Removing Voice Access'
        $command = "Remove-item -path $env:windir\System32\voiceaccess.exe -force -ErrorAction SilentlyContinue -Recurse | Out-Null"
        RunTrusted -command $command -psversion $psversion -logFile $logFile
        Start-Sleep 1
        Remove-Item "$startMenu\VoiceAccess.lnk" -Force -ErrorAction SilentlyContinue
        $voiceAccessLink = Join-Path $startMenu 'VoiceAccess.lnk'
        if ((Test-Path -LiteralPath $voiceExe -PathType Leaf) -or (Test-Path -LiteralPath $voiceAccessLink -PathType Leaf)) {
            LogError 'Voice Access removal did not meet postconditions.'
            Write-ConsoleStatus -Status failed
            return
        }
        Write-ConsoleStatus -Status success
    }
}

# Install or remove a custom update package that blocks AI package reinstallation.
<#
    .SYNOPSIS
    Installs NOAI package.
#>

function Install-NOAIPackage {

    if (!$revert) {
        $package = Get-WindowsPackage -Online | Where-Object { $_.PackageName -like '*SdManson8*' }
        if (!$package) {
            #check cpu arch
            $arm = ((Get-CimInstance -Class Win32_ComputerSystem).SystemType -match 'ARM64') -or ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
            $arch = if ($arm) { 'arm64' } else { 'amd64' }
            #add cert to registry
            $certRegPath = 'HKLM:\Software\Microsoft\SystemCertificates\ROOT\Certificates\8A334AA8052DD244A647306A76B8178FA215F344'
            if (!(Test-Path "$certRegPath")) {
                New-Item -Path $certRegPath -Force >$null
            }

            $localPackagePath = Join-Path -Path (Join-Path -Path $AIRemovalPackagePath -ChildPath $arch) -ChildPath "SdManson8AIRemoval-$($arch)1.0.0.0.cab"
            if (-not (Test-Path -LiteralPath $localPackagePath -PathType Leaf)) {
                LogError "AIRemoval package was not found locally: $localPackagePath"
                return
            }

            LogInfo "AIRemoval package found locally"
            LogInfo "Installing AIRemoval package"

            try {
                Add-WindowsPackage `
                     -Online `
                     -PackagePath $localPackagePath `
                     -NoRestart `
                     -IgnoreCheck `
                     -ErrorAction Stop `
                     *> $null
            }
            catch {
                $HandledError = $_
                $dismResult = Invoke-AIRemovalDism -ArgumentList @('/Online', '/Add-Package', ('/PackagePath:{0}' -f $localPackagePath), '/NoRestart', '/IgnoreCheck') -AllowedExitCodes @(0, 3010)
                if ($dismResult.ExitCode -eq 0 -or $dismResult.ExitCode -eq 3010)
                {
                    Remove-HandledErrorRecord -ErrorRecord $HandledError
                }
                else
                {
                    LogError "Failed to install AIRemoval package: $($HandledError.Exception.Message)"
                }
            }
        }
        else {
            LogError 'Update package already installed'
        }

       # Write-Status -msg 'Checking update package install status - '
        LogInfo "Checking update package install status"
        $package = Get-WindowsPackage -Online | Where-Object { $_.PackageName -like '*SdManson8*' }
        if ($package.PackageState -eq 'InstallPending') {
            LogError 'Package installed incorrectly -  Uninstalling!'
            try {
                Remove-WindowsPackage -Online -PackageName $package.PackageName -NoRestart -IgnoreCheck -ErrorAction Stop >$null
            }
            catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Install-NOAIPackage:catch1390' -Severity Debug }

                $null = Invoke-AIRemovalDism -ArgumentList @('/Online', '/remove-package', ('/PackageName:{0}' -f $package.PackageName), '/NoRestart', '/IgnoreCheck')
            }
            #remove reg install location
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
            Get-ChildItem $regPath | ForEach-Object {
                $value = try { Get-ItemProperty "registry::$($_.Name)" -ErrorAction SilentlyContinue } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Install-NOAIPackage:catch1396' -Severity Debug }
                 $null }
                if ($value -and $value.PSPath -like '*SdManson8*') {
                    Remove-Item -Path $value.PSPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    }
    else {

        $package = Get-WindowsPackage -Online | Where-Object { $_.PackageName -like '*SdManson8*' }
        if ($package) {
            Write-Status 'Removing Custom Windows Update Package - '
            LogInfo 'Removing Custom Windows Update Package'
            try {
                Remove-WindowsPackage -Online -PackageName $package.PackageName -NoRestart -IgnoreCheck -ErrorAction Stop >$null
            }
            catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Install-NOAIPackage:catch1412' -Severity Debug }

                $null = Invoke-AIRemovalDism -ArgumentList @('/Online', '/remove-package', ('/PackageName:{0}' -f $package.PackageName), '/NoRestart', '/IgnoreCheck')
            }
            #remove reg install location
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
            Get-ChildItem $regPath | ForEach-Object {
                $value = try { Get-ItemProperty "registry::$($_.Name)" -ErrorAction SilentlyContinue } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Install-NOAIPackage:catch1418' -Severity Debug }
                 $null }
                if ($value -and $value.PSPath -like '*SdManson8*') {
                    Remove-Item -Path $value.PSPath -Recurse -Force -ErrorAction SilentlyContinue| Out-Null
                }
            }
            Write-ConsoleStatus -Status success
}
        else {
            LogError 'Unable to Find Update Package'
        }

    }

}

# Change Windows region policy JSON files so Copilot and related AI policies default to disabled.
<#
    .SYNOPSIS
    Disables copilot policies.
#>

function Disable-Copilot-Policies {
    #disable copilot policies in region policy json
    $JSONPath = "$env:windir\System32\IntegratedServicesRegionPolicySet.json"
    if (Test-Path $JSONPath) {
       # Write-Host "$(@('Disabling','Enabling')[$revert]) CoPilot Policies in " -NoNewline -ForegroundColor Cyan
       # Write-Host "[$JSONPath]" -ForegroundColor Yellow
        LogInfo "$(@('Disabling','Enabling')[$revert]) CoPilot Policies in [$JSONPath]"

        Invoke-AIRemovalTakeOwnership -Path $JSONPath
        Grant-AIRemovalAdministratorsFullControl -Path $JSONPath

        #edit the content
        $jsonContent = Get-Content $JSONPath | ConvertFrom-Json
        try {
            $copilotPolicies = $jsonContent.policies | Where-Object { $_.'$comment' -like '*CoPilot*' }
            foreach ($policies in $copilotPolicies) {
                $policies.defaultState = @('disabled', 'enabled')[$revert]
            }
            $recallPolicies = $jsonContent.policies | Where-Object { $_.'$comment' -like '*A9*' -or $_.'$comment' -like '*Manage Recall*' -or $_.'$comment' -like '*Settings Agent*' }
            foreach ($recallPolicy in $recallPolicies) {
                if ($recallPolicy.'$comment' -like '*A9*') {
                    $recallPolicy.defaultState = @('enabled', 'disabled')[$revert]
                }
                elseif ($recallPolicy.'$comment' -like '*Manage Recall*') {
                    $recallPolicy.defaultState = @('disabled', 'enabled')[$revert]
                }
                elseif ($recallPolicy.'$comment' -like '*Settings Agent*') {
                    $recallPolicy.defaultState = @('enabled', 'disabled')[$revert]
                }
            }
            $newJSONContent = $jsonContent | ConvertTo-Json -Depth 100
            Set-Content $JSONPath -Value $newJSONContent -Force
            $total = ($copilotPolicies.count) + ($recallPolicies.count)
            Write-Status -msg "CoPilot Policies $(@('Disabled','Enabled')[$revert]) - "
            LogInfo "$total CoPilot Policies $(@('Disabled','Enabled')[$revert])"
            Write-ConsoleStatus -Status success
}
        catch {
            LogError 'CoPilot Not Found in IntegratedServicesRegionPolicySet'
        }


    }

    #additional json path for visual assist
    $visualAssistPath = "$env:windir\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\VisualAssist\VisualAssistActions.json"
    if (Test-Path $visualAssistPath) {
        Write-Status -msg "$(@('Disabling','Enabling')[$revert]) Generative AI in Visual Assist - "
        LogInfo "$(@('Disabling','Enabling')[$revert]) Generative AI in Visual Assist"

        Invoke-AIRemovalTakeOwnership -Path $visualAssistPath
        Grant-AIRemovalAdministratorsFullControl -Path $visualAssistPath

        $jsoncontent = Get-Content $visualAssistPath | ConvertFrom-Json
        $jsonContent.actions | Add-Member -MemberType NoteProperty -Name usesGenerativeAI -Value @($false, $true)[$revert] -force
        $newJSONContent = $jsonContent | ConvertTo-Json -Depth 100
        Set-Content $visualAssistPath -Value $newJSONContent -Force
        Write-ConsoleStatus -Status success
}

}

# Download Store packages and dependencies for backup or restore scenarios.
# Original wrapper source: https://github.com/Andrew-J-Larson/OS-Scripts/blob/main/Windows/Wrapper-Functions/DownloadAppxPackage-Function.ps1
<#
    .SYNOPSIS
    Runs download appx package.
#>

function DownloadAppxPackage {
    param(
        [string]$PackageFamilyName,
        [string]$ProductId,
        [string]$outputDir
    )
    if (-Not ($PackageFamilyName -Or $ProductId)) {
        LogError 'Missing either PackageFamilyName or ProductId.'
        return @()
    }

    $candidateRoots = @()

    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and (Test-Path -LiteralPath $outputDir -PathType Container)) {
        $candidateRoots += (Join-Path -Path $outputDir -ChildPath $PackageFamilyName)
        $candidateRoots += $outputDir
    }

    $localPackageRoot = Join-Path -Path $PSScriptRoot -ChildPath 'AIRemoval\Backup\AppxBackup'
    if (Test-Path -LiteralPath $localPackageRoot -PathType Container) {
        $candidateRoots += (Join-Path -Path $localPackageRoot -ChildPath $PackageFamilyName)
        $candidateRoots += $localPackageRoot
    }

    $packageFiles = @()
    foreach ($candidateRoot in ($candidateRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
            continue
        }

        $packageFiles += Get-ChildItem -LiteralPath $candidateRoot -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @('.appxbundle', '.msixbundle', '.appx', '.msix')
        } | Select-Object -ExpandProperty FullName
    }

    $packageFiles = @($packageFiles | Select-Object -Unique)
    if ($packageFiles.Count -eq 0) {
        LogWarning "No local AppX package files were found for $PackageFamilyName."
    }

    return $packageFiles
}

# Remove or restore AI-related AppX packages such as Copilot, CoreAI, and Office AI components.
<#
    .SYNOPSIS
    Removes AI appx packages.
#>

function Remove-AI-Appx-Packages {

    if ($revert) {
        Write-Status -msg 'Installing AI Appx Packages - '
        LogInfo 'Installing AI Appx Packages'
        #download appx packages from store
        $appxBackup = "$PSScriptRoot\AIRemoval\Backup\AppxBackup"
        if (Test-Path $appxBackup) {
            $familyNames = Get-Content "$appxBackup\PackageFamilyNames.txt" -ErrorAction SilentlyContinue
            foreach ($package in $familyNames) {
                $downloadedFiles = DownloadAppxPackage -PackageFamilyName $package -outputDir $appxBackup
                $bundle = $downloadedFiles | Where-Object { $_ -match '\.appxbundle$' -or $_ -match '\.msixbundle$' } | Select-Object -First 1
                if ($bundle) {
                    Add-AppPackage $bundle
                }
            }

            #cleanup
            Remove-Item "$appxBackup\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            LogError 'Unable to Find AppxBackup in User Directory!'
        }
        Write-ConsoleStatus -Status success
}
    else {

        #to make this part faster make a txt file in temp with chunck of removal
        #code and then just run that from run
        #trusted function due to the design of having it hidden from the user

        $packageRemovalPath = "$($tempDir)aiPackageRemoval.ps1"
        if (!(test-path $packageRemovalPath)) {
            New-Item $packageRemovalPath -Force | Out-Null
        }

        #needed for separate powershell sessions
        $aipackages = @(
            # 'MicrosoftWindows.Client.Photon'
            'MicrosoftWindows.Client.AIX'
            'MicrosoftWindows.Client.CoPilot'
            'Microsoft.Windows.Ai.Copilot.Provider'
            'Microsoft.Copilot'
            'Microsoft.MicrosoftOfficeHub'
            'MicrosoftWindows.Client.CoreAI'
            'Microsoft.Edge.GameAssist'
            'Microsoft.Office.ActionsServer'
            'aimgr'
            'Microsoft.WritingAssistant'
            #ai component packages installed on copilot+ pcs
            'MicrosoftWindows.*.Voiess'
            'MicrosoftWindows.*.Speion'
            'MicrosoftWindows.*.Livtop'
            'MicrosoftWindows.*.InpApp'
            'MicrosoftWindows.*.Filons'
            'WindowsWorkload.Data.Analysis.Stx.*'
            'WindowsWorkload.Manager.*'
            'WindowsWorkload.PSOnnxRuntime.Stx.*'
            'WindowsWorkload.PSTokenizer.Stx.*'
            'WindowsWorkload.QueryBlockList.*'
            'WindowsWorkload.QueryProcessor.Data.*'
            'WindowsWorkload.QueryProcessor.Stx.*'
            'WindowsWorkload.SemanticText.Data.*'
            'WindowsWorkload.SemanticText.Stx.*'
            'WindowsWorkload.Data.ContentExtraction.Stx.*'
            'WindowsWorkload.ScrRegDetection.Data.*'
            'WindowsWorkload.ScrRegDetection.Stx.*'
            'WindowsWorkload.Data.ImageSearch.Stx.*'
            'WindowsWorkload.ImageContentModeration.*'
            'WindowsWorkload.ImageContentModeration.Data.*'
            'WindowsWorkload.ImageSearch.Data.*'
            'WindowsWorkload.ImageSearch.Stx.*'
            'WindowsWorkload.ImageSearch.Stx.*'
            'WindowsWorkload.ImageTextSearch.Data.*'
            'WindowsWorkload.PSOnnxRuntime.Stx.*'
            'WindowsWorkload.PSTokenizerShared.Data.*'
            'WindowsWorkload.PSTokenizerShared.Stx.*'
            'WindowsWorkload.ImageTextSearch.Stx.*'
            'WindowsWorkload.ImageTextSearch.Stx.*'
        )

        if ($backup) {

            #create file with package family names for reverting
            $appxBackup = "$PSScriptRoot\AIRemoval\Backup\AppxBackup"
            if (!(Test-Path $appxBackup)) {
                New-Item $appxBackup -ItemType Directory -Force | Out-Null
            }

            $backuppath = New-Item $appxBackup -Name 'PackageFamilyNames.txt' -ItemType File -Force

            $familyNames = get-appxpackage -allusers | Where-Object { $aipackages -contains $_.Name }
            foreach ($familyName in $familyNames) {
                Add-Content -Path $backuppath.FullName -Value $familyName.PackageFamilyName | Out-Null
            }

        }

        $code = @'
$aipackages = @(
    'MicrosoftWindows.Client.AIX'
    'MicrosoftWindows.Client.CoPilot'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.Copilot'
    'Microsoft.MicrosoftOfficeHub'
    'MicrosoftWindows.Client.CoreAI'
    'Microsoft.Edge.GameAssist'
    'Microsoft.Office.ActionsServer'
    'aimgr'
    'Microsoft.WritingAssistant'
    'MicrosoftWindows.*.Voiess'
    'MicrosoftWindows.*.Speion'
    'MicrosoftWindows.*.Livtop'
    'MicrosoftWindows.*.InpApp'
    'MicrosoftWindows.*.Filons'
    'WindowsWorkload.Data.Analysis.Stx.*'
    'WindowsWorkload.Manager.*'
    'WindowsWorkload.PSOnnxRuntime.Stx.*'
    'WindowsWorkload.PSTokenizer.Stx.*'
    'WindowsWorkload.QueryBlockList.*'
    'WindowsWorkload.QueryProcessor.Data.*'
    'WindowsWorkload.QueryProcessor.Stx.*'
    'WindowsWorkload.SemanticText.Data.*'
    'WindowsWorkload.SemanticText.Stx.*'
    'WindowsWorkload.Data.ContentExtraction.Stx.*'
    'WindowsWorkload.ScrRegDetection.Data.*'
    'WindowsWorkload.ScrRegDetection.Stx.*'
    'WindowsWorkload.Data.ImageSearch.Stx.*'
    'WindowsWorkload.ImageContentModeration.*'
    'WindowsWorkload.ImageContentModeration.Data.*'
    'WindowsWorkload.ImageSearch.Data.*'
    'WindowsWorkload.ImageSearch.Stx.*'
    'WindowsWorkload.ImageSearch.Stx.*'
    'WindowsWorkload.ImageTextSearch.Data.*'
    'WindowsWorkload.PSOnnxRuntime.Stx.*'
    'WindowsWorkload.PSTokenizerShared.Data.*'
    'WindowsWorkload.PSTokenizerShared.Stx.*'
    'WindowsWorkload.ImageTextSearch.Stx.*'
    'WindowsWorkload.ImageTextSearch.Stx.*'
)

$provisioned = get-appxprovisionedpackage -online
$appxpackage = get-appxpackage -allusers
$store = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
$users = @('S-1-5-18'); if (test-path $store) { $users += $((Get-ChildItem $store -ea 0 | Where-Object { $_ -like '*S-1-5-21*' }).PSChildName) }

#use eol trick to uninstall some locked packages
foreach ($choice in $aipackages) {
    foreach ($appx in $($provisioned | Where-Object { $_.PackageName -like "*$choice*" })) {

        $PackageName = $appx.PackageName
        $PackageFamilyName = ($appxpackage | Where-Object { $_.Name -eq $appx.DisplayName }).PackageFamilyName
        New-Item "$store\Deprovisioned\$PackageFamilyName" -force

        Set-NonRemovableAppsPolicy -Online -PackageFamilyName $PackageFamilyName -NonRemovable 0

        foreach ($sid in $users) {
            New-Item "$store\EndOfLife\$sid\$PackageName" -force
        }
        remove-appxprovisionedpackage -packagename $PackageName -online -allusers
    }
    foreach ($appx in $($appxpackage | Where-Object { $_.PackageFullName -like "*$choice*" })) {

        $PackageFullName = $appx.PackageFullName
        $PackageFamilyName = $appx.PackageFamilyName
        New-Item "$store\Deprovisioned\$PackageFamilyName" -force
        Set-NonRemovableAppsPolicy -Online -PackageFamilyName $PackageFamilyName -NonRemovable 0

        #remove inbox apps
        $inboxApp = "$store\InboxApplications\$PackageFullName"
        Remove-Item -Path $inboxApp -Force

        #get all installed user sids for package due to not all showing up in reg
        foreach ($user in $appx.PackageUserInformation) {
            $sid = $user.UserSecurityID.SID
            if ($users -notcontains $sid) {
                $users += $sid
            }
            New-Item "$store\EndOfLife\$sid\$PackageFullName" -force
            remove-appxpackage -package $PackageFullName -User $sid
        }
        remove-appxpackage -package $PackageFullName -allusers
    }
}
'@
        Set-Content -Path $packageRemovalPath -Value $code -Force | Out-Null


        Write-Status -msg 'Removing AI Appx Packages - '
        LogInfo 'Removing AI Appx Packages'
        $command = "&`"$($tempDir)aiPackageRemoval.ps1`""
        RunTrusted -command $command -psversion $psversion -logFile $logFile

        #check packages removal
        #exit loop after 10 tries
        $attempts = 0
        do {
            Start-Sleep 1
            $packages = get-appxpackage -AllUsers | Where-Object { $aipackages -contains $_.Name }
            if ($packages) {
                $attempts++
                $command = "&`"$($tempDir)aiPackageRemoval.ps1`""
                RunTrusted -command $command -psversion $psversion -logFile $logFile
            }

        }while ($packages -and $attempts -lt 10)

        Write-ConsoleStatus -Status success
#tell windows copilot pwa is already installed
        Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoInstalledPWAs' /v 'CopilotPWAPreinstallCompleted' /t REG_DWORD /d '1' /f *>$null
        Reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoInstalledPWAs' /v 'Microsoft.Copilot_8wekyb3d8bbwe' /t REG_DWORD /d '1' /f *>$null
        #incase the user is on 25h2 and is using education or enterprise (required for this policy to work)
        #uninstalls copilot with group policy (will ensure it doesnt get reinstalled)
        Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages' /v 'Enabled' /t REG_DWORD /d '1' /f *>$null
        Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages\Microsoft.Copilot_8wekyb3d8bbwe' /v 'RemovePackage' /t REG_DWORD /d '1' /f *>$null
        Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe' /v 'RemovePackage' /t REG_DWORD /d '1' /f *>$null

        ## undo eol unblock trick to prevent latest cumulative update (LCU) failing
        #  $eolPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife'
        #  $eolKeys = (Get-ChildItem $eolPath).Name
        #  foreach ($path in $eolKeys) {
        #      Remove-Item "registry::$path" -Recurse -Force -ErrorAction SilentlyContinue
        #  }
    }
}

# Remove the Recall optional feature and its payload from the operating system.
<#
    .SYNOPSIS
    Removes recall optional feature.
#>

function Remove-Recall-Optional-Feature {
    if (!$revert) {
        # Keep Enable-WindowsOptionalFeature disabled here; on current builds it can block indefinitely.
        #Enable-WindowsOptionalFeature -Online -FeatureName 'Recall' -All -NoRestart
        # Remove Recall optional feature.
        Write-Status -msg 'Removing Recall Optional Feature - '
        LogInfo "Removing Recall Optional Feature"
        try {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction Stop
            $state = $feature.State
            if ($state -and $state -ne 'DisabledWithPayloadRemoved') {
                $ProgressPreference = 'SilentlyContinue'
                try {
                    Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -Remove -NoRestart -ErrorAction Stop | Out-Null
                }
                catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Remove-Recall-Optional-Feature:catch1804' -Severity Debug }

                    $null = Invoke-AIRemovalDism -ArgumentList @('/Online', '/Disable-Feature', '/FeatureName:Recall', '/Remove', '/NoRestart', '/Quiet')
                }
            }
        }
        catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Remove-Recall-Optional-Feature:catch1809' -Severity Debug }

            $dismResult = Invoke-AIRemovalDism -ArgumentList @('/Online', '/Get-FeatureInfo', '/FeatureName:Recall') -CaptureOutput
            $dismOutput = $dismResult.StandardOutput

            if ($dismResult.ExitCode -eq 0) {
                $isDisabledWithPayloadRemoved = $dismOutput | Select-String -Pattern 'State\s*:\s*Disabled with Payload Removed'

                if (!$isDisabledWithPayloadRemoved) {
                    $null = Invoke-AIRemovalDism -ArgumentList @('/Online', '/Disable-Feature', '/FeatureName:Recall', '/Remove', '/NoRestart', '/Quiet')
                }
            }
        }
        Write-ConsoleStatus -Status success
}
}

# Remove hidden CBS packages related to AI features that do not appear in normal package lists.
# Restoring these packages is intentionally not implemented here.
<#
    .SYNOPSIS
    Removes AI CBS packages.
#>

function Remove-AI-CBS-Packages {
    if (!$revert) {
        #additional hidden packages
        Write-Status -msg 'Removing Additional Hidden AI Packages - '
        LogInfo "Removing Additional Hidden AI Packages"
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
        $ProgressPreference = 'SilentlyContinue'
        Get-ChildItem $regPath | ForEach-Object {
            $value = try { Get-ItemPropertyValue "registry::$($_.Name)" -Name Visibility -ErrorAction SilentlyContinue | Out-Null } catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Remove-AI-CBS-Packages:catch1840' -Severity Debug }
             $null }

            if ($null -ne $value) {
                if ($value -eq 2 -and $_.PSChildName -like '*AIX*' -or $_.PSChildName -like '*Recall*' -or $_.PSChildName -like '*Copilot*' -or $_.PSChildName -like '*CoreAI*') {
                    Set-ItemProperty "registry::$($_.Name)" -Name Visibility -Value 1 -Force | Out-Null
                    New-ItemProperty "registry::$($_.Name)" -Name DefVis -PropertyType DWord -Value 2 -Force | Out-Null
                    Remove-Item "registry::$($_.Name)\Owners" -Force -ErrorAction SilentlyContinue | Out-Null
                    Remove-Item "registry::$($_.Name)\Updates" -Force -ErrorAction SilentlyContinue | Out-Null
                    try {
                        Remove-WindowsPackage -Online -PackageName $_.PSChildName -NoRestart -ErrorAction Stop | Out-Null
                        $paths = Get-ChildItem "$env:windir\servicing\Packages" -Filter "*$($_.PSChildName)*" -ErrorAction SilentlyContinue
                        foreach ($path in $paths) {
                            if ($path) {
                                Remove-Item $path.FullName -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        }

                    }
                    catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AIRemoval.Remove-AI-CBS-Packages:catch1858' -Severity Debug }

                        $null = Invoke-AIRemovalDism -ArgumentList @('/Online', '/Remove-Package', ('/PackageName:{0}' -f $_.PSChildName), '/NoRestart')
                        $paths = Get-ChildItem "$env:windir\servicing\Packages" -Filter "*$($_.PSChildName)*" -ErrorAction SilentlyContinue
                        foreach ($path in $paths) {
                            if ($path) {
                                Remove-Item $path.FullName -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                    }

                }
            }

        }
        Write-ConsoleStatus -Status success
}
}

# Remove or restore AI-related files, URI handlers, and selected Office AI assets.
<#
    .SYNOPSIS
    Removes AI files.
#>

function Remove-AI-Files {


    . (Join-Path $PSScriptRoot 'AIRemoval\Remove-AI-Files\Remove-AI-Files.ps1')

    #TEST:
    # remove ai components from component storage
    # this will prevent sfc from trying to repair files removed
    # but seems to prevent windows update from working
    <#
    $compPath = "$env:systemroot\System32\config\COMPONENTS"

    reg.exe query 'HKLM\COMPONENTS' /ve *>$null
    if ($LASTEXITCODE -ne 0) {
        reg.exe load 'HKLM\COMPONENTS' $compPath >$null
    }

    if ($LASTEXITCODE -ne 0) {
        LogError "Unable to Load $compPath"
    }
    else {
        $paths = Get-ChildItem 'registry::HKLM\COMPONENTS\DerivedData\Components' | Where-Object { $_.PSChildName -like '*copilot*' -or
            $_.PSChildName -like '*userexperience-aix*' -or
            $_.PSChildName -like '*userexperience-recall*' -or
            $_.PSChildName -like '*userexperience-coreai*' }

        if ($paths) {
            Write-Status -msg 'Removing AI Components Found in Component Storage - '
            #backup by default for now
            $backupPath = "$PSScriptRoot\AIRemoval\Backup\CompStorage"
            if (!(Test-Path $backupPath)) {
                New-Item $backupPath -ItemType Directory | Out-Null
            }

            foreach ($path in $paths) {
                reg.exe export $path.Name "$backupPath\$($path.PSChildName).reg" /y >$null
                reg.exe delete $path.Name /f
            }

        }
        else {
            Write-Status -msg 'No Ai Components Found in Component Storage'
        }

    }
    #>
}

# Hide or unhide AI-related pages in the Settings app.
<#
    .SYNOPSIS
    Hides AI components.
#>

function Hide-AI-Components {
    #hide ai components in immersive settings
    Write-Status -msg "$(@('Hiding','Unhiding')[$revert]) Ai Components in Settings - "
    LogInfo "$(@('Hiding','Unhiding')[$revert]) Ai Components in Settings"

$existingSettings = try { Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue } catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.Hide-AI-Components.ReadSettingsPageVisibility' -Severity Warning; $null }
    #early return if the user has already customized this with showonly rather than hide, in this event ill assume the user has knowledge of this key and aicomponents is likely not shown anyway
    if ($existingSettings -like '*showonly*') {
        LogError 'SettingsPageVisibility contains "showonly" - Skipping!'
        return
    }

    if ($revert) {
        #if the key is not just hide ai components then just remove it and retain the rest
        if ($existingSettings -ne 'hide:aicomponents;appactions;') {
            #in the event that this is just aicomponents but multiple times newkey will just be hide: which is valid
            $newKey = $existingSettings -replace 'aicomponents;appactions;', ''
            Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v 'SettingsPageVisibility' /t REG_SZ /d $newKey /f >$null
        }
        else {
            Reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v 'SettingsPageVisibility' /f >$null
        }
    }
    else {
        if ($existingSettings -and $existingSettings -notlike '*aicomponents;*') {

            if (!($existingSettings.endswith(';'))) {
                #doesnt have trailing ; so need to add it
                $newval = $existingSettings + ';aicomponents;appactions;'
            }
            else {
                $newval = $existingSettings + 'aicomponents;appactions;'
            }

            Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v 'SettingsPageVisibility' /t REG_SZ /d $newval /f >$null
        }
        elseif ($null -eq $existingSettings) {
            Reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v 'SettingsPageVisibility' /t REG_SZ /d 'hide:aicomponents;appactions;' /f >$null
        }

    }
        Write-ConsoleStatus -Status success
}

# Disable or re-enable the Notepad Rewrite AI feature through policy settings.
<#
    .SYNOPSIS
    Disables notepad rewrite.
#>

function Disable-Notepad-Rewrite {
    #disable rewrite for notepad
    Write-Status -msg "$(@('Disabling','Enabling')[$revert]) Rewrite Ai Feature for Notepad - "
    LogInfo "$(@('Disabling','Enabling')[$revert]) Rewrite Ai Feature for Notepad"
    Reg.exe add 'HKLM\SOFTWARE\Policies\WindowsNotepad' /v 'DisableAIFeatures' /t REG_DWORD /d @('1', '0')[$revert] /f *>$null
        Write-ConsoleStatus -Status success
}


# Remove Recall and Office AI scheduled tasks that can recreate or trigger AI components.
<#
    .SYNOPSIS
    Removes recall tasks.
#>

function Remove-Recall-Tasks {
    if (!$revert) {
        Write-Status -msg 'Disabling Recall Scheduled Tasks - '
        LogInfo 'Disabling Recall Scheduled Tasks'
        #believe it or not to disable and remove these you need system priv
        #create another sub script for removal
        $code = @"
Get-ScheduledTask -TaskPath '*WindowsAI*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
Remove-Item "`$env:Systemroot\System32\Tasks\Microsoft\Windows\WindowsAI" -Recurse -Force -ErrorAction SilentlyContinue
`$initConfigID = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WindowsAI\Recall\InitialConfiguration" -Name 'Id'
`$policyConfigID = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WindowsAI\Recall\PolicyConfiguration" -Name 'Id'
if(`$initConfigID -and `$policyConfigID){
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\`$initConfigID" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\`$policyConfigID" -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WindowsAI" -Force -Recurse -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskName "*Office Actions Server*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
    Remove-Item "`$env:Systemroot\System32\Tasks\Microsoft\Office\Office Actions Server" -ErrorAction SilentlyContinue -Force
    `$officeConfigID = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Office\Office Actions Server' -Name 'Id'
    if (`$officeConfigID) {
        Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\`$officeConfigID" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Office\Office Actions Server' -Recurse -Force -ErrorAction SilentlyContinue
"@

        $subScript = "$($tempDir)RemoveRecallTasks.ps1"
        New-Item "$subScript" -Force | Out-Null
        Set-Content "$subScript" -Value $code -Force | Out-Null

        $command = "&`"$subScript`""
        RunTrusted -command $command -psversion $psversion -logFile $logFile
        Start-Sleep 1

        #when just running this option alone the tasks will be remade so we need to at least ensure they are disabled
        $command = "
        Get-ScheduledTask -TaskName '*Office Actions Server*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskPath '*WindowsAI*' | Disable-ScheduledTask -ErrorAction SilentlyContinue
        "
        RunTrusted -command $command -psversion $psversion -logFile $logFile
        $remainingEnabledTasks = @(
            Get-ScheduledTask -TaskPath '*WindowsAI*' -ErrorAction SilentlyContinue
            Get-ScheduledTask -TaskName '*Office Actions Server*' -ErrorAction SilentlyContinue
        ) | Where-Object { $_.State -ne 'Disabled' }
        if ($remainingEnabledTasks.Count -gt 0) {
            LogError 'Recall or Office AI scheduled tasks remained enabled after removal.'
            Write-ConsoleStatus -Status failed
            return
        }
        Write-ConsoleStatus -Status success
}
}

# Run selected actions directly from the command line without showing the GUI.
if ($nonInteractive) {
    if ($backup) {
        New-AIRemovalRestorePoint -nonInteractive
    }
    if ($AllOptions) {
        Disable-Registry-Keys
        Install-NOAIPackage
        Disable-Copilot-Policies
        Remove-AI-Appx-Packages
        Remove-Recall-Optional-Feature
        Remove-AI-CBS-Packages
        Remove-AI-Files
        Hide-AI-Components
        Disable-Notepad-Rewrite
        Remove-Recall-Tasks
    }
    else {
        #loop through options array and run desired tweaks
        switch ($Options) {
            'DisableRegKeys' { Disable-Registry-Keys }
            'Prevent-AI-Package-Reinstall' { Install-NOAIPackage }
            'DisableCopilotPolicies' { Disable-Copilot-Policies }
            'RemoveAppxPackages' { Remove-AI-Appx-Packages }
            'RemoveRecallFeature' { Remove-Recall-Optional-Feature }
            'RemoveCBSPackages' { Remove-AI-CBS-Packages }
            'RemoveAIFiles' { Remove-AI-Files }
            'HideAIComponents' { Hide-AI-Components }
            'DisableRewrite' { Disable-Notepad-Rewrite }
            'RemoveRecallTasks' { Remove-Recall-Tasks }
            'RemoveVoiceAccess' { Remove-Voice-Access }
        }
    }
}
else {

    #===============================================================================
    # Build the interactive selection window used for guided AI removal.
    #===============================================================================

    $functionDescriptions = @{
        'Disable-Registry-Keys'          = 'Disables Copilot and Recall through registry modifications, including Windows Search integration and Edge Copilot features. Also disables AI image creator in Paint and various AI-related privacy settings.'
        'Prevent-AI-Package-Reinstall'   = 'Installs a custom Windows Update Package to prevent Windows Update and DISM from reinstalling AI packages.'
        'Disable-Copilot-Policies'       = 'Disables Copilot policies in the Windows integrated services region policy JSON file by setting their default state to disabled.'
        'Remove-AI-Appx-Packages'        = 'Removes AI-related AppX packages including Copilot, AIX, CoreAI, and various WindowsWorkload AI components using advanced removal techniques.'
        'Remove-Recall-Optional-Feature' = 'Removes the Recall optional Windows feature completely from the system, including payload removal.'
        'Remove-AI-CBS-Packages'         = 'Removes additional hidden AI packages from Component Based Servicing (CBS) by unhiding them and forcing removal.'
        'Remove-AI-Files'                = 'Removes AI-related files from SystemApps, WindowsApps, and other system directories. Also removes machine learning DLLs and Copilot installers.'
        'Hide-AI-Components'             = 'Hides AI components in Windows Settings by modifying the SettingsPageVisibility policy to prevent user access to AI settings.'
        'Disable-Notepad-Rewrite'        = 'Disables the AI Rewrite feature in Windows Notepad through registry modifications and group policy settings.'
        'Remove-Recall-Tasks'            = 'Disables Recall-related scheduled tasks in Windows Task Scheduler to prevent AI data collection processes from running.'
        'Remove-Voice-Access'            = 'Backs up and removes Voice Access, or restores it again in revert mode. Left off by default because it can freeze on some systems.'
    }

    $window = New-Object System.Windows.Window
    $window.Title = 'Remove Windows AI'
    $window.Width = 600
    $window.Height = 700
    $window.WindowStartupLocation = 'CenterScreen'
    $window.ResizeMode = 'NoResize'

    $window.Background = [System.Windows.Media.Brushes]::Black
    $window.Foreground = [System.Windows.Media.Brushes]::White

    $mainGrid = New-Object System.Windows.Controls.Grid
    $window.Content = $mainGrid

    $titleRow = New-Object System.Windows.Controls.RowDefinition
    $titleRow.Height = [System.Windows.GridLength]::new(80)
    $mainGrid.RowDefinitions.Add($titleRow) | Out-Null

    $contentRow = New-Object System.Windows.Controls.RowDefinition
    $contentRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $mainGrid.RowDefinitions.Add($contentRow) | Out-Null

    $toggleRow = New-Object System.Windows.Controls.RowDefinition
    $toggleRow.Height = [System.Windows.GridLength]::new(130)
    $mainGrid.RowDefinitions.Add($toggleRow) | Out-Null

    $bottomRow = New-Object System.Windows.Controls.RowDefinition
    $bottomRow.Height = [System.Windows.GridLength]::new(80)
    $mainGrid.RowDefinitions.Add($bottomRow) | Out-Null


    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = 'Remove Windows AI'
    $title.FontSize = 18
    $title.FontWeight = 'Bold'
    $title.Foreground = [System.Windows.Media.Brushes]::Cyan
    $title.HorizontalAlignment = 'Center'
    $title.VerticalAlignment = 'Center'
    $title.Margin = '0,20,0,0'
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $mainGrid.Children.Add($title) | Out-Null

    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    $scrollViewer.Margin = '20,10,20,10'
    [System.Windows.Controls.Grid]::SetRow($scrollViewer, 1)
    $mainGrid.Children.Add($scrollViewer) | Out-Null

    $scrollViewerStyle = @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type ScrollViewer}">
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="{x:Type ScrollViewer}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <ScrollContentPresenter Grid.Column="0" Margin="0,0,15,0"/>
                    <ScrollBar Grid.Column="1"
                               Name="PART_VerticalScrollBar"
                               Value="{TemplateBinding VerticalOffset}"
                               Maximum="{TemplateBinding ScrollableHeight}"
                               ViewportSize="{TemplateBinding ViewportHeight}"
                               Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"
                               Width="12"
                               Margin="3,0,8,0">
                        <ScrollBar.Style>
                            <Style TargetType="ScrollBar">
                                <Setter Property="Background" Value="#2B2B2B"/>
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="ScrollBar">
                                            <ControlTemplate.Resources>
                                                <Style x:Key="AiScrollBarTrackButtonStyle" TargetType="RepeatButton">
                                                    <Setter Property="OverridesDefaultStyle" Value="True"/>
                                                    <Setter Property="IsTabStop" Value="False"/>
                                                    <Setter Property="Focusable" Value="False"/>
                                                    <Setter Property="Template">
                                                        <Setter.Value>
                                                            <ControlTemplate TargetType="RepeatButton">
                                                                <Border Background="Transparent"/>
                                                            </ControlTemplate>
                                                        </Setter.Value>
                                                    </Setter>
                                                </Style>
                                                <Style x:Key="AiScrollBarArrowButtonStyle" TargetType="RepeatButton">
                                                    <Setter Property="OverridesDefaultStyle" Value="True"/>
                                                    <Setter Property="Background" Value="Transparent"/>
                                                    <Setter Property="IsTabStop" Value="False"/>
                                                    <Setter Property="Focusable" Value="False"/>
                                                    <Setter Property="Delay" Value="350"/>
                                                    <Setter Property="Interval" Value="55"/>
                                                    <Setter Property="Template">
                                                        <Setter.Value>
                                                            <ControlTemplate TargetType="RepeatButton">
                                                                <Grid Background="Transparent" SnapsToDevicePixels="True">
                                                                    <Border x:Name="ArrowSurface" Background="#7A7A7A" CornerRadius="5" Opacity="0"/>
                                                                    <ContentPresenter x:Name="ArrowGlyph" HorizontalAlignment="Center" VerticalAlignment="Center" Opacity="0.36"/>
                                                                </Grid>
                                                                <ControlTemplate.Triggers>
                                                                    <Trigger Property="IsMouseOver" Value="True">
                                                                        <Setter TargetName="ArrowSurface" Property="Opacity" Value="0.18"/>
                                                                        <Setter TargetName="ArrowGlyph" Property="Opacity" Value="0.92"/>
                                                                    </Trigger>
                                                                    <Trigger Property="IsPressed" Value="True">
                                                                        <Setter TargetName="ArrowSurface" Property="Opacity" Value="0.26"/>
                                                                        <Setter TargetName="ArrowGlyph" Property="Opacity" Value="1.0"/>
                                                                    </Trigger>
                                                                    <Trigger Property="IsEnabled" Value="False">
                                                                        <Setter TargetName="ArrowGlyph" Property="Opacity" Value="0.14"/>
                                                                    </Trigger>
                                                                </ControlTemplate.Triggers>
                                                            </ControlTemplate>
                                                        </Setter.Value>
                                                    </Setter>
                                                </Style>
                                            </ControlTemplate.Resources>
                                            <Grid SnapsToDevicePixels="True">
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="16"/>
                                                    <RowDefinition Height="*"/>
                                                    <RowDefinition Height="16"/>
                                                </Grid.RowDefinitions>
                                                <RepeatButton Grid.Row="0" Style="{StaticResource AiScrollBarArrowButtonStyle}" Command="ScrollBar.LineUpCommand">
                                                    <Path Data="M 2 6 L 5 3 L 8 6" Stroke="#5A5A5A" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
                                                </RepeatButton>
                                                <Border Grid.Row="1" Background="{TemplateBinding Background}" CornerRadius="6"/>
                                                <Track Grid.Row="1" Name="PART_Track" IsDirectionReversed="True">
                                                    <Track.DecreaseRepeatButton>
                                                        <RepeatButton Style="{StaticResource AiScrollBarTrackButtonStyle}" Command="ScrollBar.PageUpCommand"/>
                                                    </Track.DecreaseRepeatButton>
                                                    <Track.Thumb>
                                                        <Thumb>
                                                            <Thumb.Style>
                                                                <Style TargetType="Thumb">
                                                                    <Setter Property="Background" Value="#5A5A5A"/>
                                                                    <Setter Property="Template">
                                                                        <Setter.Value>
                                                                            <ControlTemplate TargetType="Thumb">
                                                                                <Border Background="{TemplateBinding Background}"
                                                                                        CornerRadius="6"
                                                                                        Margin="2"/>
                                                                            </ControlTemplate>
                                                                        </Setter.Value>
                                                                    </Setter>
                                                                    <Style.Triggers>
                                                                        <Trigger Property="IsMouseOver" Value="True">
                                                                            <Setter Property="Background" Value="#7A7A7A"/>
                                                                        </Trigger>
                                                                    </Style.Triggers>
                                                                </Style>
                                                            </Thumb.Style>
                                                        </Thumb>
                                                    </Track.Thumb>
                                                    <Track.IncreaseRepeatButton>
                                                        <RepeatButton Style="{StaticResource AiScrollBarTrackButtonStyle}" Command="ScrollBar.PageDownCommand"/>
                                                    </Track.IncreaseRepeatButton>
                                                </Track>
                                                <RepeatButton Grid.Row="2" Style="{StaticResource AiScrollBarArrowButtonStyle}" Command="ScrollBar.LineDownCommand">
                                                    <Path Data="M 2 3 L 5 6 L 8 3" Stroke="#5A5A5A" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
                                                </RepeatButton>
                                            </Grid>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                            </Style>
                        </ScrollBar.Style>
                    </ScrollBar>
                </Grid>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
'@

    $reader = New-Object System.Xml.XmlNodeReader([xml]$scrollViewerStyle)
    $scrollViewer.Style = [System.Windows.Markup.XamlReader]::Load($reader)


    $stackPanel = New-Object System.Windows.Controls.StackPanel
    $stackPanel.Orientation = 'Vertical'
    $scrollViewer.Content = $stackPanel

    $checkboxes = @{}
    $functions = @(
        'Disable-Registry-Keys'
        'Prevent-AI-Package-Reinstall'
        'Disable-Copilot-Policies'
        'Remove-AI-Appx-Packages'
        'Remove-Recall-Optional-Feature'
        'Remove-AI-CBS-Packages'
        'Remove-AI-Files'
        'Hide-AI-Components'
        'Disable-Notepad-Rewrite'
        'Remove-Recall-Tasks'
        'Remove-Voice-Access'
    )

    foreach ($func in $functions) {
        $optionContainer = New-Object System.Windows.Controls.DockPanel
        $optionContainer.Margin = '0,5,0,5'
        $optionContainer.LastChildFill = $false

        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.Content = $func.Replace('-', ' ')
        $checkbox.FontSize = 14
        $checkbox.Foreground = [System.Windows.Media.Brushes]::White
        $checkbox.Margin = '0,0,10,0'
        $checkbox.VerticalAlignment = 'Center'
        $checkbox.IsChecked = $true
        if ($func -eq 'Remove-Voice-Access') {
            $checkbox.IsChecked = $false
        }
        [System.Windows.Controls.DockPanel]::SetDock($checkbox, 'Left')
        $checkboxes[$func] = $checkbox

        $infoButton = New-Object System.Windows.Controls.Button
        $infoButton.Content = '?'
        $infoButton.Width = 25
        $infoButton.Height = 25
        $infoButton.FontSize = 12
        $infoButton.FontWeight = 'Bold'
        $infoButton.Background = [System.Windows.Media.Brushes]::DarkBlue
        $infoButton.Foreground = [System.Windows.Media.Brushes]::White
        $infoButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        $infoButton.BorderThickness = 0
        $infoButton.VerticalAlignment = 'Center'
        $infoButton.Cursor = 'Hand'
        [System.Windows.Controls.DockPanel]::SetDock($infoButton, 'Right')

        $infoTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="12">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
        $infoButton.Template = [System.Windows.Markup.XamlReader]::Parse($infoTemplate)

        $infoButton.Add_Click({
                param($eventSource, $e)
                $funcName = $functions | Where-Object { $checkboxes[$_] -eq $optionContainer.Children[0] }
                if (!$funcName) {
                    # Find the function name by looking at the parent container
                    $parentContainer = $eventSource.Parent
                    $checkboxInContainer = $parentContainer.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] }
                    $funcName = $functions | Where-Object { ($checkboxes[$_].Content -replace ' ', '-') -eq ($checkboxInContainer.Content -replace ' ', '-') }
                }

                # Find the correct function name
                foreach ($f in $functions) {
                    if ($checkboxes[$f].Parent -eq $eventSource.Parent) {
                        $funcName = $f
                        break
                    }
                }

                $description = $functionDescriptions[$funcName]
                [System.Windows.MessageBox]::Show($description, $funcName, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            })

        $optionContainer.Children.Add($checkbox) | Out-Null
        $optionContainer.Children.Add($infoButton) | Out-Null
        $stackPanel.Children.Add($optionContainer) | Out-Null
    }

    # Add toggle controls for backup and revert mode.
    <#
        .SYNOPSIS
        Adds i OS toggle to UI.
    #>

    function Add-iOSToggleToUI {
        param(
            [Parameter(Mandatory = $true)]
            [System.Windows.Controls.Panel]$ParentControl,
            [bool]$IsChecked = $false,
            [string]$Name = 'iOSToggle'
        )

        $styleXaml = @'
            <ResourceDictionary
                xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

                <Style x:Key="CleanToggleStyle" TargetType="{x:Type ToggleButton}">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="BorderBrush" Value="Transparent"/>
                    <Setter Property="BorderThickness" Value="0"/>
                    <Setter Property="Width" Value="40"/>
                    <Setter Property="Height" Value="24"/>
                    <Setter Property="Cursor" Value="Hand"/>
                    <Setter Property="Focusable" Value="False"/>
                    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="{x:Type ToggleButton}">
                                <Grid>
                                    <!-- Switch Track -->
                                    <Border x:Name="SwitchTrack"
                                            Width="40" Height="24"
                                            Background="#E5E5E7"
                                            CornerRadius="12"
                                            BorderThickness="0">

                                        <!-- Switch Thumb -->
                                        <Border x:Name="SwitchThumb"
                                                Width="20" Height="20"
                                                Background="White"
                                                CornerRadius="10"
                                                HorizontalAlignment="Left"
                                                VerticalAlignment="Center"
                                                Margin="2,0,0,0">
                                            <Border.Effect>
                                                <DropShadowEffect Color="#00000040"
                                                                  Direction="270"
                                                                  ShadowDepth="1"
                                                                  BlurRadius="3"
                                                                  Opacity="0.4"/>
                                            </Border.Effect>
                                            <Border.RenderTransform>
                                                <TranslateTransform x:Name="ThumbTransform" X="0"/>
                                            </Border.RenderTransform>
                                        </Border>
                                    </Border>
                                </Grid>

                                <ControlTemplate.Triggers>
                                    <!-- Checked State (ON) -->
                                    <Trigger Property="IsChecked" Value="True">
                                        <Trigger.EnterActions>
                                            <BeginStoryboard>
                                                <Storyboard>
                                                    <!-- Slide thumb to right -->
                                                    <DoubleAnimation
                                                        Storyboard.TargetName="ThumbTransform"
                                                        Storyboard.TargetProperty="X"
                                                        To="16"
                                                        Duration="0:0:0.2"/>
                                                    <!-- Change track color to green -->
                                                    <ColorAnimation
                                                        Storyboard.TargetName="SwitchTrack"
                                                        Storyboard.TargetProperty="Background.Color"
                                                        To="#34C759"
                                                        Duration="0:0:0.2"/>
                                                </Storyboard>
                                            </BeginStoryboard>
                                        </Trigger.EnterActions>
                                        <Trigger.ExitActions>
                                            <BeginStoryboard>
                                                <Storyboard>
                                                    <!-- Slide thumb to left -->
                                                    <DoubleAnimation
                                                        Storyboard.TargetName="ThumbTransform"
                                                        Storyboard.TargetProperty="X"
                                                        To="0"
                                                        Duration="0:0:0.2"/>
                                                    <!-- Change track color to gray -->
                                                    <ColorAnimation
                                                        Storyboard.TargetName="SwitchTrack"
                                                        Storyboard.TargetProperty="Background.Color"
                                                        To="#E5E5E7"
                                                        Duration="0:0:0.2"/>
                                                </Storyboard>
                                            </BeginStoryboard>
                                        </Trigger.ExitActions>
                                    </Trigger>
                                </ControlTemplate.Triggers>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Style>
            </ResourceDictionary>
'@

        $reader = New-Object System.Xml.XmlNodeReader([xml]$styleXaml)
        $resourceDict = [System.Windows.Markup.XamlReader]::Load($reader)

        $toggleButton = New-Object System.Windows.Controls.Primitives.ToggleButton
        $toggleButton.Name = $Name
        $toggleButton.IsChecked = $IsChecked
        $toggleButton.Style = $resourceDict['CleanToggleStyle']
        $ParentControl.Children.Add($toggleButton) | Out-Null

        return $toggleButton
    }

    $toggleGrid = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetRow($toggleGrid, 2)
    $toggleGrid.Margin = '20,10,55,15'

    $row1 = New-Object System.Windows.Controls.RowDefinition
    $row1.Height = [System.Windows.GridLength]::Auto
    $row2 = New-Object System.Windows.Controls.RowDefinition
    $row2.Height = [System.Windows.GridLength]::Auto
    $toggleGrid.RowDefinitions.Add($row1) | Out-Null
    $toggleGrid.RowDefinitions.Add($row2) | Out-Null

    $mainGrid.Children.Add($toggleGrid) | Out-Null

    $togglePanel1 = New-Object System.Windows.Controls.DockPanel
    $togglePanel1.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $togglePanel1.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $togglePanel1.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $togglePanel1.LastChildFill = $false
    [System.Windows.Controls.Grid]::SetRow($togglePanel1, 0)

    $toggleLabel1 = New-Object System.Windows.Controls.TextBlock
    $toggleLabel1.Text = 'Revert Mode:'
    $toggleLabel1.Foreground = [System.Windows.Media.Brushes]::White
    $toggleLabel1.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $toggleLabel1.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    [System.Windows.Controls.DockPanel]::SetDock($toggleLabel1, 'Left')
    $togglePanel1.Children.Add($toggleLabel1) | Out-Null

    $revertModeToggle = Add-iOSToggleToUI -ParentControl $togglePanel1 -IsChecked $revert
    [System.Windows.Controls.DockPanel]::SetDock($revertModeToggle, 'Left')

    $revertInfoButton = New-Object System.Windows.Controls.Button
    $revertInfoButton.Content = '?'
    $revertInfoButton.Width = 25
    $revertInfoButton.Height = 25
    $revertInfoButton.FontSize = 12
    $revertInfoButton.FontWeight = 'Bold'
    $revertInfoButton.Background = [System.Windows.Media.Brushes]::DarkBlue
    $revertInfoButton.Foreground = [System.Windows.Media.Brushes]::White
    $revertInfoButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $revertInfoButton.BorderThickness = 0
    $revertInfoButton.VerticalAlignment = 'Center'
    $revertInfoButton.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $revertInfoButton.Cursor = 'Hand'
    [System.Windows.Controls.DockPanel]::SetDock($revertInfoButton, 'Right')

    $revertInfoTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="12">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
    $revertInfoButton.Template = [System.Windows.Markup.XamlReader]::Parse($revertInfoTemplate)
    $revertInfoButton.Add_Click({
            $description = 'Revert Mode will undo changes made by this tool, restoring AI features and settings to their original state. Selected options above will be reverted/enabled when this mode is selected.'
            [System.Windows.MessageBox]::Show($description, 'Revert Mode', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        })

    $togglePanel1.Children.Add($revertInfoButton) | Out-Null
    $toggleGrid.Children.Add($togglePanel1) | Out-Null

    $togglePanel2 = New-Object System.Windows.Controls.DockPanel
    $togglePanel2.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $togglePanel2.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $togglePanel2.LastChildFill = $false
    [System.Windows.Controls.Grid]::SetRow($togglePanel2, 1)

    $toggleLabel2 = New-Object System.Windows.Controls.TextBlock
    $toggleLabel2.Text = 'Backup Mode:'
    $toggleLabel2.Foreground = [System.Windows.Media.Brushes]::White
    $toggleLabel2.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $toggleLabel2.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    [System.Windows.Controls.DockPanel]::SetDock($toggleLabel2, 'Left')
    $togglePanel2.Children.Add($toggleLabel2) | Out-Null

    $backupModeToggle = Add-iOSToggleToUI -ParentControl $togglePanel2 -IsChecked $backup
    [System.Windows.Controls.DockPanel]::SetDock($backupModeToggle, 'Left')

    $backupInfoButton = New-Object System.Windows.Controls.Button
    $backupInfoButton.Content = '?'
    $backupInfoButton.Width = 25
    $backupInfoButton.Height = 25
    $backupInfoButton.FontSize = 12
    $backupInfoButton.FontWeight = 'Bold'
    $backupInfoButton.Background = [System.Windows.Media.Brushes]::DarkBlue
    $backupInfoButton.Foreground = [System.Windows.Media.Brushes]::White
    $backupInfoButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $backupInfoButton.BorderThickness = 0
    $backupInfoButton.VerticalAlignment = 'Center'
    $backupInfoButton.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $backupInfoButton.Cursor = 'Hand'
    [System.Windows.Controls.DockPanel]::SetDock($backupInfoButton, 'Right')

    $backupInfoTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="12">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
    $backupInfoButton.Template = [System.Windows.Markup.XamlReader]::Parse($backupInfoTemplate)
    $backupInfoButton.Add_Click({
            $description = 'Backup Mode keeps necessary files in your User directory allowing revert mode to work properly, use this option while removing AI if you would like to fully revert the removal process.'
            [System.Windows.MessageBox]::Show($description, 'Backup Mode', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        })

    $togglePanel2.Children.Add($backupInfoButton) | Out-Null
    $toggleGrid.Children.Add($togglePanel2) | Out-Null
    # Keep backup mode and revert mode mutually exclusive.
    $backupModeToggle.Add_Checked({
            $Global:backup = 1
            $revertModeToggle.IsChecked = $false
        }) | Out-Null

    $backupModeToggle.Add_Unchecked({
            $Global:backup = 0
        }) | Out-Null

    $revertModeToggle.Add_Checked({
            $Global:revert = 1
            $backupModeToggle.IsChecked = $false
        }) | Out-Null

    $revertModeToggle.Add_Unchecked({
            $Global:revert = 0
        }) | Out-Null

    $bottomGrid = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetRow($bottomGrid, 3)
    $bottomGrid.Margin = '25,15,25,15'

    $leftColumn = New-Object System.Windows.Controls.ColumnDefinition
    $leftColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $bottomGrid.ColumnDefinitions.Add($leftColumn) | Out-Null

    $rightColumn = New-Object System.Windows.Controls.ColumnDefinition
    $rightColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $bottomGrid.ColumnDefinitions.Add($rightColumn) | Out-Null

    $actionPanel = New-Object System.Windows.Controls.StackPanel
    $actionPanel.Orientation = 'Horizontal'
    $actionPanel.HorizontalAlignment = 'Right'
    $actionPanel.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($actionPanel, 1)

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = 'Cancel'
    $cancelButton.Width = 80
    $cancelButton.Height = 35
    $cancelButton.Background = [System.Windows.Media.Brushes]::DarkRed
    $cancelButton.Foreground = [System.Windows.Media.Brushes]::White
    $cancelButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $cancelButton.BorderThickness = 0
    $cancelButton.Margin = '0,0,10,0'
    $cancelButton.Cursor = 'Hand'

    $cancelTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="17">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
    $cancelButton.Template = [System.Windows.Markup.XamlReader]::Parse($cancelTemplate)
    $cancelButton.Add_Click({
            $window.Close()
        })

    $applyButton = New-Object System.Windows.Controls.Button
    $applyButton.Content = 'Apply'
    $applyButton.Width = 80
    $applyButton.Height = 35
    $applyButton.Background = [System.Windows.Media.Brushes]::DarkGreen
    $applyButton.Foreground = [System.Windows.Media.Brushes]::White
    $applyButton.BorderBrush = [System.Windows.Media.Brushes]::Transparent
    $applyButton.BorderThickness = 0
    $applyButton.Cursor = 'Hand'

    $applyTemplate = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="17">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
    $applyButton.Template = [System.Windows.Markup.XamlReader]::Parse($applyTemplate)
    $applyButton.Add_Click({
            Write-Status -msg 'Killing AI Processes - '
            # Stop running AI-related processes before changing packages and files.

    start-process msedge.exe
    Start-Sleep 2
    Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue | Out-Null

            $aiProcesses = @(
                'ai.exe'
                'Copilot.exe'
                'aihost.exe'
                'aicontext.exe'
                'ClickToDo.exe'
                'aixhost.exe'
                'WorkloadsSessionHost.exe'
                'WebViewHost.exe'
                'aimgr.exe'
                'AppActions.exe'
            )
            foreach ($procName in $aiProcesses) {
                $null = Invoke-AIRemovalNativeProcess -FilePath 'taskkill.exe' -ArgumentList @('/im', $procName, '/f') -TimeoutSeconds 60 -AllowedExitCodes @(0, 128)
            }
            Write-ConsoleStatus -Status success
$progressWindow = New-Object System.Windows.Window
            $progressWindow.Title = 'Processing - '
            $progressWindow.Width = 400
            $progressWindow.Height = 200
            $progressWindow.WindowStartupLocation = 'CenterOwner'
            $progressWindow.Owner = $window
            $progressWindow.Background = [System.Windows.Media.Brushes]::Black
            $progressWindow.Foreground = [System.Windows.Media.Brushes]::White
            $progressWindow.ResizeMode = 'NoResize'

            $progressGrid = New-Object System.Windows.Controls.Grid
            $progressWindow.Content = $progressGrid

            $progressText = New-Object System.Windows.Controls.TextBlock
            $progressText.Text = 'Initializing - '
            $progressText.FontSize = 14
            $progressText.Foreground = [System.Windows.Media.Brushes]::Cyan
            $progressText.HorizontalAlignment = 'Center'
            $progressText.VerticalAlignment = 'Center'
            $progressText.TextWrapping = 'Wrap'
            $progressGrid.Children.Add($progressText) | Out-Null

            $progressWindow.Show()

            $selectedFunctions = @()
            foreach ($func in $functions) {
                if ($checkboxes[$func].IsChecked) {
                    $selectedFunctions += $func
                }
            }

            if ($selectedFunctions.Count -eq 0) {
                $progressWindow.Close()
                [System.Windows.MessageBox]::Show('No options selected.', 'Nothing to Process', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                return
            }

            try {
                if ($backup) {
                    New-AIRemovalRestorePoint
                }
                foreach ($func in $selectedFunctions) {
                    $progressText.Text = "Executing: $($func.Replace('-', ' '))"
                    $progressWindow.UpdateLayout()
                    [System.Windows.Forms.Application]::DoEvents()

                    switch ($func) {
                        'Disable-Registry-Keys' { Disable-Registry-Keys }
                        'Prevent-AI-Package-Reinstall' { Install-NOAIPackage }
                        'Disable-Copilot-Policies' { Disable-Copilot-Policies }
                        'Remove-AI-Appx-Packages' { Remove-AI-Appx-Packages }
                        'Remove-Recall-Optional-Feature' { Remove-Recall-Optional-Feature }
                        'Remove-AI-CBS-Packages' { Remove-AI-CBS-Packages }
                        'Remove-AI-Files' { Remove-AI-Files }
                        'Hide-AI-Components' { Hide-AI-Components }
                        'Disable-Notepad-Rewrite' { Disable-Notepad-Rewrite }
                        'Remove-Recall-Tasks' { Remove-Recall-Tasks }
                        'Remove-Voice-Access' { Remove-Voice-Access }
                    }

                    Start-Sleep -Milliseconds 500
                }

                $progressText.Text = 'Completed successfully!'
                Start-Sleep -Seconds 2
                $progressWindow.Close()

                $result = [System.Windows.MessageBox]::Show("AI removal process completed successfully!`n`nWould you like to restart your computer now to ensure all changes take effect?", 'Process Complete', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)

                if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                    # Remove temporary helper files before restart.
                    try {
                        Remove-Item "$($tempDir)aiPackageRemoval.ps1" -Force -ErrorAction SilentlyContinue
                    }
                    catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.RestartCleanup.RemoveAiPackageRemoval' }
                    try {
                        Remove-Item "$($tempDir)RemoveRecallTasks.ps1" -Force -ErrorAction SilentlyContinue
                    }
                    catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.RestartCleanup.RemoveRecallTasks' }
                    try {
                        Remove-Item "$($tempDir)PathsToDelete.txt" -Force -ErrorAction SilentlyContinue
                    }
                    catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.RestartCleanup.RemovePathsToDelete' }
                    try {
                        Remove-Item "$($tempDir)SdManson8AIRemoval-*1.0.0.0.cab" -Force -ErrorAction SilentlyContinue
                    }
                    catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.RestartCleanup.RemoveCab' }

                    # Restore the original execution policy if the script changed it.
                    if ($ogExecutionPolicy) {
                        if ($Global:executionPolicyUser) {
                            Reg.exe add 'HKCU\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
                        }
                        elseif ($Global:executionPolicyMachine) {
                            Reg.exe add 'HKLM\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
                        }
                        elseif ($Global:executionPolicyWow64) {
                            Reg.exe add 'HKLM\SOFTWARE\Wow6432Node\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
                        }
                        elseif ($Global:executionPolicyUserPol) {
                            Reg.exe add 'HKCU\SOFTWARE\Policies\Microsoft\Windows\PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
                        }
                        else {
                            Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
                        }
                    }
                    Restart-Computer -Force
                }

                $window.Close()
            }
            catch {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\Regions\UWPApps\AIRemoval.ps1:2833' -Severity Debug }

                $progressWindow.Close()
                [System.Windows.MessageBox]::Show("An error occurred: $($_.Exception.Message)", 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        })


    $actionPanel.Children.Add($cancelButton) | Out-Null
    $actionPanel.Children.Add($applyButton) | Out-Null

    $bottomGrid.Children.Add($actionPanel) | Out-Null
    $mainGrid.Children.Add($bottomGrid) | Out-Null

    $window.ShowDialog() | Out-Null
}

# Clean up temporary helper files created during package and task removal.
try {
    Remove-Item "$($tempDir)aiPackageRemoval.ps1" -Force -ErrorAction SilentlyContinue
}
catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.FinalCleanup.RemoveAiPackageRemoval' }
try {
    Remove-Item "$($tempDir)RemoveRecallTasks.ps1" -Force -ErrorAction SilentlyContinue
}
catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.FinalCleanup.RemoveRecallTasks' }
try {
    Remove-Item "$($tempDir)PathsToDelete.txt" -Force -ErrorAction SilentlyContinue
}
catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.FinalCleanup.RemovePathsToDelete' }
try {
    Remove-Item "$($tempDir)SdManson8AIRemoval-*1.0.0.0.cab" -Force -ErrorAction SilentlyContinue
}
catch { Write-AIRemovalSwallowedException -ErrorRecord $_ -Source 'AIRemoval.FinalCleanup.RemoveCab' }

# Restore the original execution policy if the script changed it.
if ($ogExecutionPolicy) {
    if ($Global:executionPolicyUser) {
        Reg.exe add 'HKCU\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
    }
    elseif ($Global:executionPolicyMachine) {
        Reg.exe add 'HKLM\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
    }
    elseif ($Global:executionPolicyWow64) {
        Reg.exe add 'HKLM\SOFTWARE\Wow6432Node\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
    }
    elseif ($Global:executionPolicyUserPol) {
        Reg.exe add 'HKCU\SOFTWARE\Policies\Microsoft\Windows\PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
    }
    else {
        Reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell' /v 'ExecutionPolicy' /t REG_SZ /d $ogExecutionPolicy /f >$null
    }
}
