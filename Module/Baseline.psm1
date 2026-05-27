<#
    .SYNOPSIS
    Internal loader module for Baseline.

    .VERSION
    1.0.0

    .DATE
    21.03.2026 - Initial Release
    25.05.2026 - Major upgrades to GUI

	.AUTHOR
	sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Imports shared modules and region modules, then exports their functions.
    This module exists for the internal Baseline runtime and should be treated
    as implementation detail, not end-user documentation.
#>

# Logging and helper functions are shared across all region modules, so import
# logging first, then fail fast on every remaining core module.
$coreModuleImports = @(
    @{ Name = 'Logging.psm1';     Path = Join-Path $PSScriptRoot 'Logging.psm1';     CanLog = $false }
    @{ Name = 'SharedHelpers.psm1'; Path = Join-Path $PSScriptRoot 'SharedHelpers.psm1'; CanLog = $true  }
    @{ Name = 'GUICommon.psm1';   Path = Join-Path $PSScriptRoot 'GUICommon.psm1';   CanLog = $true  }
    @{ Name = 'GUIExecution.psm1';  Path = Join-Path $PSScriptRoot 'GUIExecution.psm1';  CanLog = $true  }
)

foreach ($coreImport in $coreModuleImports)
{
    try
    {
        Import-Module -Name $coreImport.Path -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch
    {
        $message = "Failed to import core module '$($coreImport.Name)': $($_.Exception.Message)"
        if ([bool]$coreImport.CanLog -and (Get-Command -Name 'LogError' -CommandType Function -ErrorAction SilentlyContinue))
        {
            LogError $message
        }
        else
        {
            Write-Error -Message $message
        }
        throw [System.InvalidOperationException]::new($message, $_.Exception)
    }
}

# Optional supply-chain hardening. When BASELINE_INTEGRITY_MODE is set to
# Strict or Audit, every script file under Module/ is hashed and compared
# against Module/integrity.manifest.json before any region modules load.
# Default mode is Off (no overhead, no behaviour change).
if (Get-Command -Name 'Invoke-BaselineModuleIntegrityGate' -ErrorAction SilentlyContinue)
{
    Invoke-BaselineModuleIntegrityGate -ModuleRoot $PSScriptRoot
}

# Detect the OS version once through the shared helper so every module uses the same logic.
$osName = (Get-OSInfo).OSName

# Initialize logging in the disposable temp storage root. BASELINE_STATE_ROOT is
# reserved for persistent user state such as profiles and saved sessions.
$logDirectory = Get-BaselineLogDirectory -FallbackRoot $env:TEMP
$logDirectory = Get-BaselineConfiguredLogDirectory -DefaultDirectory $logDirectory -FallbackRoot $env:TEMP

$resolvedLogPath = [string]$global:LogFilePath
if ([string]::IsNullOrWhiteSpace($resolvedLogPath))
{
    $resolvedLogPath = New-BaselineSessionLogPath -LogDirectory $logDirectory -OsName $osName
}
$previousLogPath = [string]$global:LogFilePath
$hadPreviousLogPath = -not [string]::IsNullOrWhiteSpace([string]$previousLogPath)
$alreadyInitialized = $hadPreviousLogPath -and $previousLogPath -eq $resolvedLogPath
$global:LogFilePath = $resolvedLogPath
Set-LogFile -Path $global:LogFilePath
$existingSessionStats = Get-SessionStatistics
$statisticsInitialized = ($existingSessionStats -and $existingSessionStats.ContainsKey('SessionStartTime') -and $existingSessionStats.SessionStartTime)
if ((-not $alreadyInitialized) -or (-not $statisticsInitialized))
{
    Initialize-SessionStatistics
    if ($hadPreviousLogPath -and -not $alreadyInitialized)
    {
        LogWarning ("Baseline loader reset session statistics after module reload because the log path changed from '{0}' to '{1}'." -f $previousLogPath, $resolvedLogPath)
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
    'GUI.psm1'
)

foreach ($core in $coreFiles) {
    $corePath = Join-Path $RegionDir $core
    if (Test-Path -LiteralPath $corePath) {
        try {
            Import-Module -Name $corePath -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
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
            Import-Module -Name $_.FullName -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
        }
        catch {
            LogError "Failed to import region module '$($_.Name)': $($_.Exception.Message)"
            throw
        }
    }

# Region modules are imported with -Global so their functions are available
# directly. Do not export with wildcard to avoid leaking internal helpers.
Export-ModuleMember -Function @()
