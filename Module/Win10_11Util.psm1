<#
    .SYNOPSIS
    Loader module for Win10_11Util.
 
    .VERSION
	2.0.0

	.DATE
	17.03.2026 - initial version
	21.03.2026 - Added GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Imports shared modules and region modules, then exports their functions.
    This Script is a PowerShell module for Windows 10 & Windows 11 for fine-tuning and automating the routine tasks
#>

# Logging and helper functions are shared across all region modules, so we import them first to ensure they are available for use in the region modules.
# Import shared modules used by all region modules
Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -Global
Import-Module -Name "$PSScriptRoot\Helpers.psm1" -Force -Global

# Detect the OS version once through the shared helper so every module uses the same logic.
$osName = (Get-OSInfo).OSName
# Initialize logging and write to an OS-specific log file in %TEMP%
$global:LogFilePath = Join-Path $env:TEMP "WinUtil Script for $osName.txt"
Set-LogFile -Path $global:LogFilePath

<#
    .SYNOPSIS
    Restart the script in Windows PowerShell 5.1 when launched from PowerShell 7.

    .PARAMETER ScriptPath
    Path to the script file that should be restarted in Windows PowerShell 5.1.

    .EXAMPLE
    Restart-Script -ScriptPath $MyInvocation.MyCommand.Path
#>
function Restart-Script
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$ScriptPath
	)
	if ($PSVersionTable.PSVersion.Major -ge 7)
	{
		$powershell51 = (Get-Command -Name powershell.exe -ErrorAction SilentlyContinue).Source

		if (-not $powershell51)
		{
			LogError "PowerShell 5.1 not found."
			[Environment]::Exit(1)
		}

		if (-not (Test-Path -LiteralPath $ScriptPath))
		{
			LogError "Script not found: $ScriptPath"
			[Environment]::Exit(1)
		}

		LogInfo "Restarting script in Windows PowerShell 5.1"

		$argList = @(
			'-ExecutionPolicy', 'Bypass',
			'-NoProfile',
			'-File', $ScriptPath
		)

		if ($Functions)
		{
			$argList += '-Functions'
			$argList += $Functions
		}

		Start-Process -FilePath $powershell51 -ArgumentList $argList -WindowStyle Hidden
		[Environment]::Exit(0)
	}
}

<#
    .SYNOPSIS
    Load the region modules that provide the script's functions.

    .DESCRIPTION
    Imports Errors.psm1 and InitialActions.psm1 first because other region modules may depend on them.
    Then imports the remaining region modules from the Regions folder in name order and exports their functions through this loader module.
#>
$RegionDir = Join-Path $PSScriptRoot 'Regions'

$coreFiles = @('Errors.psm1', 'InitialActions.psm1')
$excludedRegionFiles = @(
)

foreach ($core in $coreFiles) {
    $corePath = Join-Path $RegionDir $core
    if (Test-Path -LiteralPath $corePath) {
        try {
            Import-Module -Name $corePath -Force -Global -ErrorAction Stop
        }
        catch {
            LogError "Failed to import region module '$core': $($_.Exception.Message)"
            throw
        }
    }
}

Get-ChildItem -Path $RegionDir -Filter '*.psm1' -File |
    Where-Object { $_.Name -notin $coreFiles -and $_.Name -notin $excludedRegionFiles } |
    Sort-Object Name |
    ForEach-Object {
        try {
            Import-Module -Name $_.FullName -Force -Global -ErrorAction Stop
        }
        catch {
            LogError "Failed to import region module '$($_.Name)': $($_.Exception.Message)"
            throw
        }
    }

Export-ModuleMember -Function *
