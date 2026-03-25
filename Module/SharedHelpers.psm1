<#
    .SYNOPSIS
    Shared helper loader module for Win10_11Util.

    .DESCRIPTION
    Dot-sources the helper slices from Module/SharedHelpers and exports the
    shared helper functions consumed across the project.
#>

$Script:SharedHelpersModuleRoot = $PSScriptRoot
$Script:SharedHelpersRepoRoot = Split-Path $PSScriptRoot -Parent

$HelperFiles = @(
    'ErrorHandling.Helpers.ps1'
    'Registry.Helpers.ps1'
    'Environment.Helpers.ps1'
    'Manifest.Helpers.ps1'
    'PackageManagement.Helpers.ps1'
    'AdvancedStartup.Helpers.ps1'
    'Taskbar.Helpers.ps1'
    'SystemMaintenance.Helpers.ps1'
)

foreach ($helperFile in $HelperFiles)
{
    $helperPath = Join-Path -Path (Join-Path $PSScriptRoot 'SharedHelpers') -ChildPath $helperFile
    if (-not (Test-Path -LiteralPath $helperPath))
    {
        throw "Required shared helper file is missing: $helperPath"
    }

    . $helperPath
}

$ExportedFunctions = @(
    'Remove-HandledErrorRecord'
    'Test-IgnorableErrorMessage'
    'Test-IgnorableErrorRecord'
    'Get-NewUnhandledErrorRecords'
    'Invoke-SilencedProgress'
    'Set-Policy'
    'ConvertTo-NativeRegistryPath'
    'ConvertTo-RegExeValueType'
    'Dismount-RegistryHive'
    'Mount-RegistryHive'
    'Test-RegistryValueEquivalent'
    'Set-RegistryValueSafe'
    'Remove-RegistryValueSafe'
    'Set-SystemTweaksRegistryValue'
    'Remove-SystemTweaksRegistryValue'
    'Initialize-ForegroundWindowInterop'
    'Initialize-ConsoleWindowInterop'
    'Get-ConsoleHandle'
    'Hide-ConsoleWindow'
    'Show-ConsoleWindow'
    'Initialize-WpfWindowForeground'
    'Get-WindowsVersionData'
    'Get-OSInfo'
    'Get-LocalizedShellString'
    'ConvertTo-WindowsDisplayVersionComparable'
    'Test-Windows11FeatureBranchSupport'
    'Show-BootstrapLoadingSplash'
    'Close-LoadingSplashWindow'
    'Show-Menu'
    'Restart-Script'
    'Get-WinUtilDisplayVersion'
    'Stop-Foreground'
    'Convert-JsonManifestValue'
    'ConvertTo-TweakRiskLevel'
    'ConvertTo-TweakPresetTier'
    'Convert-ToWhyThisMattersText'
    'Import-TweakManifestFromData'
    'Test-TweakManifestIntegrity'
    'Update-ProcessPathFromRegistry'
    'Resolve-WinGetExecutable'
    'Get-WinGetVersion'
    'Invoke-DownloadFile'
    'Get-OneDriveSetupPath'
    'ConvertTo-NormalizedVersion'
    'Get-InstalledVCRedistVersion'
    'Get-InstalledDotNetRuntimeVersion'
    'Get-LatestDotNetRuntimeRelease'
    'Install-VCRedist'
    'Install-DotNetRuntimes'
    'Get-AdvancedStartupDesktopDirectory'
    'Get-AdvancedStartupDownloadsDirectory'
    'Get-AdvancedStartupAssetPath'
    'Get-AdvancedStartupIconLocation'
    'Enable-AdvancedStartupWindowsRecoveryEnvironment'
    'Get-AdvancedStartupCommandPath'
    'Set-AdvancedStartupCommandFile'
    'Get-AdvancedStartupShortcutArguments'
    'Get-TaskbarPinnedItems'
    'Get-TaskbarPinnedMatches'
    'Invoke-TaskbarUnpin'
    'Remove-TaskbarPinnedLink'
    'Invoke-TaskbarUnpinWithFallback'
    'Remove-TaskbarPinnedLinksByPattern'
    'Invoke-ARM64ShellUnpin'
    'Test-Windows11SmbDuplicateSidIssue'
    'Invoke-AdditionalServiceOptimizations'
)

Export-ModuleMember -Function $ExportedFunctions
