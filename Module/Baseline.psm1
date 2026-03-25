<#
    .SYNOPSIS
    Loader module for Baseline.
 
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
Import-Module -Name "$PSScriptRoot\SharedHelpers.psm1" -Force -Global

# Detect the OS version once through the shared helper so every module uses the same logic.
$osName = (Get-OSInfo).OSName
# Initialize logging and write to an OS-specific log file in %TEMP%
$global:LogFilePath = Join-Path $env:TEMP "Baseline - Windows Utility for $osName.txt"
Set-LogFile -Path $global:LogFilePath

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
