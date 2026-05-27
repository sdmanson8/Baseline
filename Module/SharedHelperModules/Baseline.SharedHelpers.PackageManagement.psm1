<#
    .SYNOPSIS
    Module wrapper for PackageManagement.Helpers.ps1.

    .DESCRIPTION
    Exposes helper functions through this dedicated module boundary so they are loaded via PowerShell's module system.

#>

$Script:SharedHelpersModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:SharedHelpersRepoRoot = Split-Path -Path $Script:SharedHelpersModuleRoot -Parent

$helperPath = Join-Path -Path (Join-Path $Script:SharedHelpersModuleRoot 'SharedHelpers') -ChildPath 'PackageManagement.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath))
{
    throw "Required shared helper file is missing: $helperPath"
}

. $helperPath

$ExportedFunctions = @(
    'Update-ProcessPathFromRegistry'
    'Get-ApplicationPackageIdCandidates'
    'Resolve-ApplicationPackageId'
    'Test-ApplicationPackageIdInCache'
    'Write-PackageHelperWarning'
    'Resolve-WinGetExecutable'
    'Get-WinGetVersion'
    'Reset-WinGetAvailabilityState'
    'Test-WinGetAvailable'
    'Resolve-ChocolateyExecutable'
    'Get-ChocolateyVersion'
    'Reset-ChocolateyAvailabilityState'
    'Test-ChocolateyAvailable'
    'Test-BaselineEnvironmentFlagEnabled'
    'Test-ChocolateyBootstrapInteractiveHost'
    'Test-ChocolateyBootstrapApproved'
    'Confirm-ChocolateyBootstrapExecution'
    'Get-WinGetBootstrapInstallerMetadata'
    'Get-WinGetBootstrapInstallerArguments'
    'Invoke-WinGetBootstrap'
    'Invoke-ChocolateyBootstrap'
    'Invoke-DownloadFile'
    'Get-BaselineLatestReleaseAssetUrl'
    'Save-BaselineExecutable'
    'Set-DownloadSecurityProtocol'
    'Assert-FileHash'
    'Assert-AuthenticodeSignature'
    'Get-PowerShellInstallerArchitecture'
    'Resolve-PowerShellInstallerUri'
    'Get-OneDriveSetupPath'
    'ConvertTo-NormalizedVersion'
    'Get-InstalledVCRedistVersion'
    'Get-InstalledDotNetRuntimeVersion'
    'Get-LatestDotNetRuntimeRelease'
    'Install-VCRedist'
    'Install-DotNetRuntimeVersion'
    'Install-DotNetRuntimes'
)

Export-ModuleMember -Function $ExportedFunctions





