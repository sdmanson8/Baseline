<#
    .SYNOPSIS
    Module wrapper for Environment.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'Environment.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Initialize-ForegroundWindowInterop'
    'Initialize-ConsoleWindowInterop'
    'Get-ConsoleHandle'
    'Hide-ConsoleWindow'
    'Show-ConsoleWindow'
    'Test-InteractiveHost'
    'Initialize-WpfWindowForeground'
    'Get-WindowsVersionData'
    'Get-OSInfo'
    'Get-BaselineStartupThemePreference'
    'Get-BaselineStartupThemeName'
    'Get-BaselineValidationMatrixSummary'
    'Get-BaselineValidationEvidenceReport'
    'ConvertTo-WindowsDisplayVersionComparable'
    'Test-Windows11FeatureBranchSupport'
    'Show-BootstrapLoadingSplash'
    'Initialize-BaselineProcessIdentity'
    'Format-BaselineDownloadStatus'
    'Set-BootstrapLoadingSplashState'
    'Set-BootstrapLoadingSplashStep'
    'Close-LoadingSplashWindow'
    'Compare-BaselineReleaseVersions'
    'Get-BaselineLatestReleaseEntry'
    'Get-BaselineUpdateAsset'
    'Get-BaselineUpdateAssetPattern'
    'Invoke-BaselineAutoUpdate'
    'Invoke-BaselineUpdateCheck'
    'Get-BaselineUpdateSettings'
    'Get-BaselineStartupSplashSettings'
    'Get-BaselineStartupPackageManagerCheckStatePath'
    'Get-BaselineStartupPackageManagerCheckState'
    'Set-BaselineStartupPackageManagerCheckState'
    'Get-BaselineStartupPackageManagerCheckDecision'
    'Get-BaselineUpdateCheckState'
    'Set-BaselineUpdateCheckState'
    'Format-BaselineUpdateLastChecked'
    'ConvertTo-BaselineUpdateCheckFrequency'
    'ConvertTo-BaselineUpdateBranch'
    'Get-BaselineDefaultUpdateBranch'
    'Get-BaselineUpdateRepositoryName'
    'Get-BaselineUpdateRepositoryUrl'
    'Get-BaselineUpdateReleaseApiUri'
    'Get-BaselineUpdateReleasePageUrl'
    'Test-BaselineUpdatePrereleaseAllowed'
    'Test-BaselineAutoUpdateStartupEnabled'
    'Show-Menu'
    'Get-LocalizedShellString'
    'Restart-Script'
    'Get-BaselineDisplayVersion'
    'Get-TweakSkipLabel'
    'Stop-Foreground'
    'Invoke-UCPDBypassed'
    'Get-UCPDTemporaryPowerShellPath'
    'Set-BaselineOperationMode'
    'Get-BaselineOperationMode'
    'Test-BaselineReadOnlyMode'
    'Assert-BaselineWriteAllowed'
    'Initialize-BaselineWinRtRuntimeDependencies'
    'Initialize-BaselineMarkdownRuntime'
    'Test-BaselineMarkdownRuntimeReady'
    'ConvertFrom-BaselineMarkdownToFlowDocument'
    'ConvertFrom-BaselineMarkdownToAnchoredFlowDocument'
    'Get-BaselineMarkdownPipeline'
    'ConvertFrom-BaselineMarkdownToHtml'
    'Initialize-BaselineWebView2Runtime'
    'Test-BaselineWebView2RuntimeReady'
    'Test-IsVirtualMachine'
)

Export-ModuleMember -Function $ExportedFunctions
