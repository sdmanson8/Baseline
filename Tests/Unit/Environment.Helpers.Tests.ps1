Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    <#
        .SYNOPSIS
    #>

    function Get-BaselineLocalizedString {
        param(
            [string]$Key,
            [string]$Fallback,
            [object[]]$FormatArgs = @()
        )

        if ($FormatArgs.Count -gt 0)
        {
            return ($Fallback -f $FormatArgs)
        }

        return $Fallback
    }

    <#
        .SYNOPSIS
    #>

    function Get-BaselineBilingualString {
        param(
            [string]$Key,
            [string]$Fallback,
            [object[]]$FormatArgs = @()
        )

        if ($FormatArgs.Count -gt 0)
        {
            return ($Fallback -f $FormatArgs)
        }

        return $Fallback
    }

    <#
        .SYNOPSIS
    #>

    function LogInfo { param([object]$Message) }
    <#
        .SYNOPSIS
    #>
    function LogWarning { param([object]$Message) }
    <#
        .SYNOPSIS
    #>
    function LogError { param([object]$Message) }
    <#
        .SYNOPSIS
    #>
    function Write-SwallowedException {
        param(
            [object]$ErrorRecord,
            [string]$Source
        )

        [void]$script:DebugSwallowedExceptionCalls.Add([pscustomobject]@{
            Source  = [string]$Source
            Message = if ($ErrorRecord -and $ErrorRecord.Exception) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
        })
    }

    # Json helpers must load first - Environment.Helpers calls ConvertFrom-BaselineJson.
    . (Join-Path $PSScriptRoot '../../Module/SharedHelpers/Json.Helpers.ps1')

    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $script:EnvironmentHelpersContent = Get-BaselineTestSourceText -Path $filePath
    $script:EnglishLocalizationFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../../Localizations') -Directory |
            Where-Object { $_.Name -like 'English*' } |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.json' -File }
    )
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:EnvironmentHelpersContent, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }

    <#
        .SYNOPSIS
    #>
    function Set-DownloadSecurityProtocol { }

    Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction Stop
    if (-not ('EnvironmentHelpersSplashTestDispatcher' -as [type]))
    {
        Add-Type -TypeDefinition @'
using System;

public class EnvironmentHelpersSplashTestDispatcher
{
    public bool HasShutdownStarted { get; set; }

    public void Invoke(Action action)
    {
        if (action != null)
        {
            action();
        }
    }
}

public class EnvironmentHelpersSplashTestElement
{
    public object Text { get; set; }
    public object Visibility { get; set; }
    public object Foreground { get; set; }
    public object Stroke { get; set; }
    public object Fill { get; set; }
    public object RenderTransform { get; set; }
    public double Opacity { get; set; }

    public EnvironmentHelpersSplashTestElement()
    {
        Opacity = 1.0;
    }

    public void BeginAnimation(object property, object animation) { }
    public void BeginAnimation(object property, object animation, object handoffBehavior) { }
}

public class EnvironmentHelpersSplashTestProgressBar
{
    public object Visibility { get; set; }
    public bool IsIndeterminate { get; set; }
    public double Maximum { get; set; }
    public double Value { get; set; }
    public double Width { get; set; }
    public double ActualWidth { get; set; }

    public EnvironmentHelpersSplashTestProgressBar()
    {
        Maximum = 330.0;
        Width = 330.0;
        ActualWidth = 330.0;
    }

    public void BeginAnimation(object property, object animation)
    {
        ApplyAnimation(animation);
    }

    public void BeginAnimation(object property, object animation, object handoffBehavior)
    {
        ApplyAnimation(animation);
    }

    private void ApplyAnimation(object animation)
    {
        if (animation == null)
        {
            return;
        }

        var animationType = animation.GetType();
        var toProperty = animationType.GetProperty("To");
        if (toProperty == null)
        {
            return;
        }

        var toValue = toProperty.GetValue(animation, null);
        if (toValue is double)
        {
            Value = (double)toValue;
        }
    }
}
'@
    }

    $script:DebugSwallowedExceptionCalls = [System.Collections.Generic.List[object]]::new()
}

Describe 'Invoke-UCPDBypassed' {
    It 'throws on non-zero exit codes and still removes the temporary executable' {
        $tempPath = Join-Path $TestDrive 'powershell_temp.cmd'

        function Invoke-BaselineProcess {}
        Mock Get-UCPDTemporaryPowerShellPath { $tempPath }
        Mock Copy-Item {
            param($Path, $Destination)
            Set-Content -LiteralPath $Destination -Value "@exit /b 5" -Encoding ASCII
        }
        Mock Invoke-BaselineProcess { throw "Process '$FilePath' failed with exit code 5." }
        Mock Remove-Item {}

        { Invoke-UCPDBypassed -ScriptText "'noop'" } | Should -Throw '*exit code 5*'
        Assert-MockCalled Remove-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq $tempPath -and $Force
        }
        Microsoft.PowerShell.Management\Remove-Item Function:\Invoke-BaselineProcess -ErrorAction SilentlyContinue
    }

    It 'accepts script blocks by writing their source text to the temporary script' {
        $tempPath = Join-Path $TestDrive 'powershell_temp.cmd'
        $script:ucpdScriptText = $null

        function Invoke-BaselineProcess {}
        Mock Get-UCPDTemporaryPowerShellPath { $tempPath }
        Mock Copy-Item {
            param($Path, $Destination)
            Set-Content -LiteralPath $Destination -Value '@exit /b 0' -Encoding ASCII
        }
        Mock Set-Content {
            param($LiteralPath, $Value)
            $script:ucpdScriptText = [string]$Value
        }
        Mock Invoke-BaselineProcess { [pscustomobject]@{ ExitCode = 0 } }
        Mock Remove-Item {}

        Invoke-UCPDBypassed -ScriptBlock { Set-ItemProperty -Path 'HKCU:\Software\Test' -Name Demo -Value 1 }

        $script:ucpdScriptText | Should -Match 'Set-ItemProperty'
        $script:ucpdScriptText | Should -Match 'HKCU:\\Software\\Test'
        Microsoft.PowerShell.Management\Remove-Item Function:\Invoke-BaselineProcess -ErrorAction SilentlyContinue
    }
}

Describe 'Baseline auto-update setup flow contract' {
    It 'uses the release setup executable instead of replacing Baseline.exe directly' {
        $script:EnvironmentHelpersContent | Should -Match "Baseline-\*-setup\.exe"
        $script:EnvironmentHelpersContent | Should -Match "/BASELINEUPDATE=1"
        $script:EnvironmentHelpersContent | Should -Match "/BASELINEUPDATETARGETDIR=`"\{0\}`""
        $script:EnvironmentHelpersContent | Should -Match "/RELAUNCH=`"\{0\}`""
        $script:EnvironmentHelpersContent | Should -Match '\$updateTargetDirectory = Split-Path -Path \$exePath -Parent'
        $script:EnvironmentHelpersContent | Should -Match "start /wait"
        $script:EnvironmentHelpersContent | Should -Not -Match 'move /y `"\$newExePath`" `"\$exePath`"'
    }

    It 'requires the release zip and setup hashes before applying the setup update' {
        $script:EnvironmentHelpersContent | Should -Match "\.sha256\.json"
        $script:EnvironmentHelpersContent | Should -Match '\$releaseAssetPattern = Get-BaselineUpdateAssetPattern -Branch \$updateBranch'
        $script:EnvironmentHelpersContent | Should -Match 'Get-BaselineUpdateAsset -Assets @\(\$release\.assets\) -Pattern \$releaseAssetPattern'
        $script:EnvironmentHelpersContent | Should -Match 'Expand-Archive -LiteralPath \$zipPath'
        $script:EnvironmentHelpersContent | Should -Match 'Release zip must contain exactly one Baseline-\*-setup\.exe'
        $script:EnvironmentHelpersContent | Should -Match 'Assert-BaselineUpdateFileHash -Path \$zipPath'
        $script:EnvironmentHelpersContent | Should -Match 'Assert-BaselineUpdateFileHash -Path \$setupPath'
    }

    It 'uses channel-qualified release zip asset patterns' {
        Get-BaselineUpdateAssetPattern -Branch Stable | Should -Be 'Baseline-*-stable.zip'
        Get-BaselineUpdateAssetPattern -Branch Beta | Should -Be 'Baseline-*-beta.zip'
    }

    It 'formats splash download telemetry as transfer rate and remaining time only' {
        Format-BaselineDownloadStatus -VersionTag 'v9.9.9' -BytesReceived 50MB -TotalBytes 100MB -ElapsedSeconds 10 |
            Should -Be '5 MB/s - 00:10 remaining'

        Format-BaselineDownloadStatus -VersionTag 'v9.9.9' -BytesReceived 50MB -TotalBytes 0 -ElapsedSeconds 10 |
            Should -Be ''
    }

    It 'uses uninstall registration to identify installed update mode' {
        $installDirectory = Join-Path $TestDrive 'Programs\Baseline'
        $null = New-Item -ItemType Directory -Path $installDirectory -Force
        $exePath = Join-Path $installDirectory 'Baseline.exe'
        $null = New-Item -ItemType File -Path $exePath -Force

        Mock Get-ItemProperty {
            [pscustomobject]@{ InstallLocation = $installDirectory }
        } -ParameterFilter { $LiteralPath -like 'Registry::HKEY_CURRENT_USER*' }

        Get-BaselineUpdateInstallMode -ExecutablePath $exePath | Should -Be 'Install'
    }

    It 'treats executables without Baseline install registration as portable update mode' {
        $portableDirectory = Join-Path $TestDrive 'Portable\Baseline'
        $null = New-Item -ItemType Directory -Path $portableDirectory -Force
        $exePath = Join-Path $portableDirectory 'Baseline.exe'
        $null = New-Item -ItemType File -Path $exePath -Force

        Mock Get-ItemProperty { throw 'not found' }

        Get-BaselineUpdateInstallMode -ExecutablePath $exePath | Should -Be 'Portable'
    }
}

Describe 'Get-UCPDTemporaryPowerShellPath' {
    It 'creates a GUID-suffixed executable path in the source directory' {
        $sourceDirectory = Join-Path $TestDrive 'WindowsPowerShell/v1.0'
        $null = New-Item -ItemType Directory -Path $sourceDirectory -Force
        $sourcePath = Join-Path $sourceDirectory 'powershell.exe'

        $path = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath

        Split-Path -Path $path -Parent | Should -Be (Split-Path -Path $sourcePath -Parent)
        Split-Path -Path $path -Leaf | Should -Match '^powershell_[0-9a-f]{32}\.exe$'
    }

    It 'returns a unique path for each call' {
        $sourceDirectory = Join-Path $TestDrive 'WindowsPowerShell/v1.0'
        $null = New-Item -ItemType Directory -Path $sourceDirectory -Force
        $sourcePath = Join-Path $sourceDirectory 'powershell.exe'
        $first = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath
        $second = Get-UCPDTemporaryPowerShellPath -SourcePath $sourcePath

        $first | Should -Not -Be $second
    }
}

Describe 'Get-BaselineDisplayVersion' {
    BeforeEach {
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'reads ModuleVersion from a module manifest and prefixes it with v' {
        $moduleRoot = Join-Path $TestDrive 'ModuleRoot'
        $null = New-Item -ItemType Directory -Path $moduleRoot -Force
        $manifestPath = Join-Path $moduleRoot 'Baseline.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '2.0.0' }" -Encoding ASCII

        $result = Get-BaselineDisplayVersion -ModuleRoot $moduleRoot

        $result | Should -Be 'v2.0.0'
    }

    It 'routes manifest parse failures through Write-SwallowedException and returns null' {
        $moduleRoot = Join-Path $TestDrive 'BrokenModuleRoot'
        $null = New-Item -ItemType Directory -Path $moduleRoot -Force
        $manifestPath = Join-Path $moduleRoot 'Baseline.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '2.0.0' }" -Encoding ASCII

        Mock Import-EnvironmentPowerShellDataFile { throw 'manifest parse failed' } -ParameterFilter { $Path -eq $manifestPath }

        Get-BaselineDisplayVersion -ModuleRoot $moduleRoot | Should -BeNullOrEmpty
        $script:DebugSwallowedExceptionCalls.Count | Should -Be 1
        $script:DebugSwallowedExceptionCalls[0].Source | Should -Be 'Environment.GetBaselineDisplayVersion.LoadManifest'
    }
}

Describe 'Get-BaselineWindowsThemePreference' {
    BeforeEach {
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'routes registry read failures through Write-SwallowedException and returns null' {
        Mock Get-ItemProperty { throw 'registry read failed' } -ParameterFilter {
            $LiteralPath -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        }

        Get-BaselineWindowsThemePreference | Should -BeNullOrEmpty
        $script:DebugSwallowedExceptionCalls.Count | Should -Be 1
        $script:DebugSwallowedExceptionCalls[0].Source | Should -Be 'Environment.GetBaselineWindowsThemePreference.LoadTheme'
    }
}

Describe 'Get-BaselineStartupThemeName' {
    BeforeEach {
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'prefers the saved session theme over the Windows theme' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-user-prefs.json' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-Content { '{}' } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock ConvertFrom-BaselineJson {
            [pscustomobject]@{
                State = @{
                    Theme = 'Dark'
                }
            }
        }

        Get-BaselineStartupThemeName | Should -Be 'Dark'
    }

    It 'defaults first launch to System and resolves through the Windows theme' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-user-prefs.json' -or $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-BaselineWindowsThemePreference { 'Light' }

        Get-BaselineStartupThemePreference | Should -Be 'System'
        Get-BaselineStartupThemeName | Should -Be 'Light'
    }

    It 'resolves a saved System theme through the Windows theme' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-user-prefs.json' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-Content { '{}' } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock ConvertFrom-BaselineJson {
            [pscustomobject]@{
                State = @{
                    Theme = 'System'
                }
            }
        }
        Mock Get-BaselineWindowsThemePreference { 'Dark' }

        Get-BaselineStartupThemePreference | Should -Be 'System'
        Get-BaselineStartupThemeName | Should -Be 'Dark'
    }

    It 'falls back to the current Windows theme when no saved session exists' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-user-prefs.json' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-BaselineWindowsThemePreference { 'Light' }

        Get-BaselineStartupThemeName | Should -Be 'Light'
    }

    It 'routes session read failures through Write-SwallowedException and falls back to the Windows theme' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*Baseline-user-prefs.json' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-Content { throw 'session read failed' } -ParameterFilter { $LiteralPath -like '*Baseline-last-session.json' }
        Mock Get-BaselineWindowsThemePreference { 'Dark' }

        Get-BaselineStartupThemeName | Should -Be 'Dark'
        $script:DebugSwallowedExceptionCalls.Count | Should -Be 1
        $script:DebugSwallowedExceptionCalls[0].Source | Should -Be 'Environment.GetBaselineStartupThemePreference.LoadSession'
    }
}

Describe 'Get-BaselineUpdateSettings' {
    It 'treats a disabled update-check state as disabled when the auto-check preference has not been written yet' {
        $preferencePath = Join-Path $TestDrive 'missing-user-prefs.json'
        $statePath = Join-Path $TestDrive 'auto-update-check-disabled.json'
        Set-BaselineUpdateCheckState -Path $statePath -Status 'Disabled' -PreserveLastChecked

        $settings = Get-BaselineUpdateSettings -PreferencePath $preferencePath -StatePath $statePath

        $settings.AutoCheckUpdates | Should -BeFalse
    }

    It 'lets an explicit auto-check preference override the disabled display state' {
        $preferencePath = Join-Path $TestDrive 'user-prefs-enabled.json'
        $statePath = Join-Path $TestDrive 'auto-update-check-disabled.json'
        Set-BaselineUpdateCheckState -Path $statePath -Status 'Disabled' -PreserveLastChecked
        [System.IO.File]::WriteAllText(
            $preferencePath,
            (@{
                Schema = 'Baseline.UserPreferences'
                SchemaVersion = 1
                Values = @{
                    AutoCheckUpdates = $true
                    UpdateCheckFrequency = 'Weekly'
                    IncludePrereleaseUpdates = $true
                    UpdateBranch = 'Beta'
                }
            } | ConvertTo-Json -Depth 6),
            [System.Text.Encoding]::UTF8
        )

        $settings = Get-BaselineUpdateSettings -PreferencePath $preferencePath -StatePath $statePath

        $settings.AutoCheckUpdates | Should -BeTrue
        $settings.CheckFrequency | Should -Be 'Weekly'
        $settings.IncludePrereleaseBuilds | Should -BeTrue
        $settings.UpdateBranch | Should -Be 'Beta'
        $settings.RepositoryName | Should -Be 'baseline_dev'
        $settings.RepositoryUrl | Should -Be 'https://github.com/sdmanson8/baseline_dev'
        $settings.ReleaseApiUri | Should -Be 'https://api.github.com/repos/sdmanson8/baseline_dev/releases'
    }
}

Describe 'Get-BaselineStartupSplashSettings' {
    It 'defaults all startup splash work to enabled when no preference file exists' {
        $settings = Get-BaselineStartupSplashSettings -PreferencePath (Join-Path $TestDrive 'missing-user-prefs.json')

        $settings.RunInitialActions | Should -BeTrue
        $settings.CheckWinGet | Should -BeTrue
        $settings.CheckChocolatey | Should -BeTrue
        $settings.WinGetCheckFrequency | Should -Be 'Startup'
        $settings.ChocolateyCheckFrequency | Should -Be 'Startup'
    }

    It 'reads explicit startup splash preferences from the GUI preference file' {
        $preferencePath = Join-Path $TestDrive 'user-prefs-startup-splash.json'
        [System.IO.File]::WriteAllText(
            $preferencePath,
            (@{
                Schema = 'Baseline.UserPreferences'
                SchemaVersion = 1
                Values = @{
                    StartupRunInitialActions = $false
                    StartupCheckWinGet = $false
                    StartupWinGetCheckFrequency = 'Daily'
                    StartupCheckChocolatey = $true
                    StartupChocolateyCheckFrequency = 'Weekly'
                }
            } | ConvertTo-Json -Depth 6),
            [System.Text.Encoding]::UTF8
        )

        $settings = Get-BaselineStartupSplashSettings -PreferencePath $preferencePath

        $settings.RunInitialActions | Should -BeFalse
        $settings.CheckWinGet | Should -BeFalse
        $settings.WinGetCheckFrequency | Should -Be 'Daily'
        $settings.CheckChocolatey | Should -BeTrue
        $settings.ChocolateyCheckFrequency | Should -Be 'Weekly'
    }

    It 'reads the same LOCALAPPDATA user preference path as the GUI store' {
        $previousLocalAppData = $env:LOCALAPPDATA
        try
        {
            $localAppData = Join-Path $TestDrive 'LocalAppData'
            $env:LOCALAPPDATA = $localAppData
            $preferenceDirectory = Join-Path (Join-Path (Join-Path $localAppData 'Baseline') 'UserState') 'Profiles'
            $preferencePath = Join-Path $preferenceDirectory 'Baseline-user-prefs.json'
            $null = New-Item -ItemType Directory -Path $preferenceDirectory -Force
            [System.IO.File]::WriteAllText(
                $preferencePath,
                (@{
                    Schema = 'Baseline.UserPreferences'
                    SchemaVersion = 1
                    Values = @{
                        StartupRunInitialActions = $false
                        StartupCheckWinGet = $false
                        StartupCheckChocolatey = $false
                    }
                } | ConvertTo-Json -Depth 6),
                [System.Text.Encoding]::UTF8
            )

            Get-BaselineUpdatePreferencePath | Should -Be $preferencePath
            $settings = Get-BaselineStartupSplashSettings

            $settings.RunInitialActions | Should -BeFalse
            $settings.CheckWinGet | Should -BeFalse
            $settings.CheckChocolatey | Should -BeFalse
        }
        finally
        {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }

    It 'tracks WinGet and Chocolatey startup package-manager check timestamps separately' {
        $statePath = Join-Path $TestDrive 'startup-package-manager-checks.json'
        $firstCheck = [datetime]'2026-05-20T00:00:00Z'
        $secondCheck = [datetime]'2026-05-21T00:00:00Z'

        Set-BaselineStartupPackageManagerCheckState -Path $statePath -WinGet -NowUtc $firstCheck
        Set-BaselineStartupPackageManagerCheckState -Path $statePath -Chocolatey -NowUtc $secondCheck

        $state = Get-BaselineStartupPackageManagerCheckState -Path $statePath
        ([datetime]$state.WinGetLastCheckedUtc).ToString('o') | Should -Be $firstCheck.ToUniversalTime().ToString('o')
        ([datetime]$state.ChocolateyLastCheckedUtc).ToString('o') | Should -Be $secondCheck.ToUniversalTime().ToString('o')
    }

    It 'uses each package-manager frequency to decide whether startup checks are due' {
        $statePath = Join-Path $TestDrive 'startup-package-manager-frequency.json'
        Set-BaselineStartupPackageManagerCheckState -Path $statePath -WinGet -Chocolatey -NowUtc ([datetime]'2026-05-20T00:00:00Z')

        $dailyDue = Get-BaselineStartupPackageManagerCheckDecision -Path $statePath -PackageManager 'WinGet' -Enabled:$true -Frequency 'Daily' -NowUtc ([datetime]'2026-05-21T00:01:00Z')
        $weeklyBlocked = Get-BaselineStartupPackageManagerCheckDecision -Path $statePath -PackageManager 'Chocolatey' -Enabled:$true -Frequency 'Weekly' -NowUtc ([datetime]'2026-05-21T00:01:00Z')
        $disabled = Get-BaselineStartupPackageManagerCheckDecision -Path $statePath -PackageManager 'WinGet' -Enabled:$false -Frequency 'Startup' -NowUtc ([datetime]'2026-05-21T00:01:00Z')

        $dailyDue.ShouldCheck | Should -BeTrue
        $weeklyBlocked.ShouldCheck | Should -BeFalse
        $disabled.ShouldCheck | Should -BeFalse
    }
}

Describe 'Baseline update branch mapping' {
    It 'maps stable and beta branches to their release repositories' {
        ConvertTo-BaselineUpdateBranch -Branch 'stable' | Should -Be 'Stable'
        ConvertTo-BaselineUpdateBranch -Branch 'beta' | Should -Be 'Beta'
        Get-BaselineUpdateRepositoryUrl -Branch 'Stable' | Should -Be 'https://github.com/sdmanson8/Baseline'
        Get-BaselineUpdateRepositoryUrl -Branch 'Beta' | Should -Be 'https://github.com/sdmanson8/baseline_dev'
        Get-BaselineUpdateReleaseApiUri -Branch 'Beta' | Should -Be 'https://api.github.com/repos/sdmanson8/baseline_dev/releases'
    }

    It 'defaults beta builds to the beta update branch' {
        $manifestPath = Join-Path $TestDrive 'Baseline.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ PrivateData = @{ Prerelease = 'beta' } }" -Encoding ASCII

        Get-BaselineDefaultUpdateBranch -ModuleManifestPath $manifestPath | Should -Be 'Beta'
    }

    It 'defaults stable builds to the stable update branch' {
        $manifestPath = Join-Path $TestDrive 'Baseline.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ PrivateData = @{} }" -Encoding ASCII

        Get-BaselineDefaultUpdateBranch -ModuleManifestPath $manifestPath | Should -Be 'Stable'
    }

    It 'allows prerelease candidates by explicit stable preference or by beta branch' {
        Test-BaselineUpdatePrereleaseAllowed -Branch 'Stable' -IncludePrerelease:$false | Should -BeFalse
        Test-BaselineUpdatePrereleaseAllowed -Branch 'Stable' -IncludePrerelease:$true | Should -BeTrue
        Test-BaselineUpdatePrereleaseAllowed -Branch 'Beta' -IncludePrerelease:$false | Should -BeTrue
    }
}

Describe 'Compare-BaselineReleaseVersions' {
    It 'treats a newer major version as higher even when an older prerelease appears first' {
        (Compare-BaselineReleaseVersions -LeftVersion 'v4.0.0-beta' -RightVersion 'v3.0.0-beta') | Should -BeGreaterThan 0
    }

    It 'treats stable releases as newer than prereleases of the same core version' {
        (Compare-BaselineReleaseVersions -LeftVersion 'v4.0.0' -RightVersion 'v4.0.0-beta') | Should -BeGreaterThan 0
    }

    It 'treats rc builds as newer than beta builds of the same core version' {
        (Compare-BaselineReleaseVersions -LeftVersion 'v4.0.0-rc1' -RightVersion 'v4.0.0-beta') | Should -BeGreaterThan 0
    }

    It 'normalizes display-version prerelease text in parentheses' {
        (Compare-BaselineReleaseVersions -LeftVersion 'v4.0.0 (beta)' -RightVersion 'v4.0.0-beta') | Should -Be 0
    }
}

Describe 'Show-BootstrapLoadingSplash' {
    It 'keeps the startup splash visible while the GUI is loading' {
        $script:EnvironmentHelpersContent | Should -Match 'ShowInTaskbar="True"'
        $script:EnvironmentHelpersContent | Should -Not -Match 'ShowInTaskbar="False"'
    }

    It 'shows the startup splash normally without forcing topmost foreground state' {
        $script:EnvironmentHelpersContent | Should -Match 'ShowActivated="True"'
        $script:EnvironmentHelpersContent | Should -Match 'Topmost="False"'
        $script:EnvironmentHelpersContent | Should -Match 'WindowActive = \$false'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Activated\(\{[\s\S]*\$syncHash\[''WindowActive''\] = \$true'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Deactivated\(\{[\s\S]*\$syncHash\[''WindowActive''\] = \$false'
        $script:EnvironmentHelpersContent | Should -Match '\$recordSplashShownAction = \{'
        $script:EnvironmentHelpersContent | Should -Not -Match '\$showSplashForegroundAction = \{'
        $script:EnvironmentHelpersContent | Should -Not -Match '\[void\]\$splash\.Activate\(\)'
        $script:EnvironmentHelpersContent | Should -Not -Match '\[void\]\$splash\.Focus\(\)'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash loaded'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash content rendered'
    }

    It 'restores splash maximized state and exposes a splash maximize control' {
        $script:EnvironmentHelpersContent | Should -Match 'Resolve-BaselineWindowPlacement -DefaultRect \$defaultRect'
        $script:EnvironmentHelpersContent | Should -Match 'if \(\[string\]\$placement\.Source -eq ''saved''\)'
        $script:EnvironmentHelpersContent | Should -Match 'WindowStartupLocation="\$splashWindowStartupLocation"'
        $script:EnvironmentHelpersContent | Should -Match 'WindowMaximized = \$splashWindowMaximized'
        $script:EnvironmentHelpersContent | Should -Match 'SetVariable\(''splashWindowMaximized'', \$splashWindowMaximized\)'
        $script:EnvironmentHelpersContent | Should -Match 'Name="BtnMaximize"'
        $script:EnvironmentHelpersContent | Should -Match 'WS_MAXIMIZEBOX'
        $script:EnvironmentHelpersContent | Should -Match '\$btnMax\.Add_Click\(\{ & \$toggleSplashMaximizeAction \}'
        $script:EnvironmentHelpersContent | Should -Match '\$syncHash\[''WindowMaximized''\]\s*=\s*\$isMaximized'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_StateChanged\(\{[\s\S]*& \$syncSplashWindowStateAction'
        $script:EnvironmentHelpersContent | Should -Match '& \$setSplashWindowMaximizedStateAction -Maximized \$true'
    }

    It 'uses a danger hover style for the splash close caption button' {
        $script:EnvironmentHelpersContent | Should -Match 'x:Key="SplashCloseButtonStyle"'
        $script:EnvironmentHelpersContent | Should -Match 'BasedOn="\{StaticResource SplashCaptionButtonStyle\}"'
        $script:EnvironmentHelpersContent | Should -Match '<Setter Property="Background" Value="\{DynamicResource Brush\.Danger\}"'
        $script:EnvironmentHelpersContent | Should -Match 'Name="BtnClose"[\s\S]*Style="\{StaticResource SplashCloseButtonStyle\}"'
        $script:EnvironmentHelpersContent | Should -Not -Match 'Name="BtnClose"[^>]*Background="Transparent"'
        $script:EnvironmentHelpersContent | Should -Not -Match 'Name="BtnClose"[^>]*Foreground="\{DynamicResource Brush\.TextSecondary\}"'
    }

    It 'treats user splash close before GUI readiness as a process abort' {
        $script:EnvironmentHelpersContent | Should -Match 'UserClosed\s*=\s*\$false'
        $script:EnvironmentHelpersContent | Should -Match 'AbortRequested\s*=\s*\$false'
        $script:EnvironmentHelpersContent | Should -Match 'ProgrammaticClose\s*=\s*\$false'
        $script:EnvironmentHelpersContent | Should -Match '\$requestSplashAbortAction = \{'
        $script:EnvironmentHelpersContent | Should -Match "\`$syncHash\['AbortRequested'\]\s*=\s*\`$true"
        $script:EnvironmentHelpersContent | Should -Match '\[System\.Environment\]::Exit\(0\)'
        $script:EnvironmentHelpersContent | Should -Match '\[System\.Diagnostics\.Process\]::GetCurrentProcess\(\)\.Kill\(\)'
        $script:EnvironmentHelpersContent | Should -Match '\$btnCls\.Add_Click\(\{ & \$requestSplashAbortAction ''caption button'' \}'
        $script:EnvironmentHelpersContent | Should -Match '\$miCloseCtx\.Add_Click\(\{ & \$requestSplashAbortAction ''context menu'' \}'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Closing\(\{[\s\S]*& \$requestSplashAbortAction ''window close'''
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Closed\(\{[\s\S]*Bootstrap splash closed before GUI readiness; aborting process'
    }

    It 'marks normal splash handoff closes as programmatic so they do not abort startup' {
        $script:EnvironmentHelpersContent | Should -Match 'function Close-LoadingSplashWindow'
        $script:EnvironmentHelpersContent | Should -Match "\`$Splash\['ProgrammaticClose'\]\s*=\s*\`$true"
    }

    It 'primes the first splash step immediately and upgrades that prime for startup update checks' {
        $script:EnvironmentHelpersContent | Should -Match '\[switch\]\$StartUpdatesPulse'
        $script:EnvironmentHelpersContent | Should -Match '\[string\[\]\]\$StepOrder = @\(\)'
        $script:EnvironmentHelpersContent | Should -Not -Match 'splashLocCheckingForUpdates'
        $script:EnvironmentHelpersContent | Should -Match '\$allowedSplashSteps = @\(''updates'', ''system'', ''winget'', ''chocolatey'', ''finalize''\)'
        $script:EnvironmentHelpersContent | Should -Match 'if \(\$StepOrder -and \$StepOrder\.Count -gt 0\)'
        $script:EnvironmentHelpersContent | Should -Match '\$splashStepOrder = @\(''system'', ''winget'', ''chocolatey'', ''finalize''\)'
        $script:EnvironmentHelpersContent | Should -Match 'if \(\[bool\]\$StartUpdatesPulse -and \(-not \(\$splashStepOrder -contains ''updates''\)\)\)'
        $script:EnvironmentHelpersContent | Should -Match '\$stepRowsXaml = \(\$stepRows -join \[System\.Environment\]::NewLine\)'
        $script:EnvironmentHelpersContent | Should -Match '\$syncHash\[''StepOrder''\] = @\(\$splashStepOrder\)'
        $script:EnvironmentHelpersContent | Should -Match 'InitialStepPrimeApplied = \$false'
        $script:EnvironmentHelpersContent | Should -Match 'bootstrapLoadingSplashStepCommand'
        $script:EnvironmentHelpersContent | Should -Match 'bootstrapLoadingSplashStateCommand'
        $script:EnvironmentHelpersContent | Should -Match '\$initialStepId = if \(\$splashStepOrder\.Count -gt 0\) \{ \[string\]\$splashStepOrder\[0\] \} else \{ ''finalize'' \}'
        $script:EnvironmentHelpersContent | Should -Match 'if \(\$subActionPanelControl\) \{ \$subActionPanelControl\.Visibility = \[System\.Windows\.Visibility\]::Collapsed \}'
        $script:EnvironmentHelpersContent | Should -Match '\$progressBarControl = if \(\$syncHash\.ContainsKey\(''ProgressBar''\)\) \{ \$syncHash\[''ProgressBar''\] \} else \{ \$null \}'
        $script:EnvironmentHelpersContent | Should -Match '\$progressBarControl\.BeginAnimation\(\[System\.Windows\.Controls\.ProgressBar\]::ValueProperty, \$fill, \[System\.Windows\.Media\.Animation\.HandoffBehavior\]::SnapshotAndReplace\)'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Loaded\(\{[\s\S]*& \$primeInitialStepAction ''Loaded'''
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_ContentRendered\(\{[\s\S]*& \$primeInitialStepAction ''ContentRendered'''
    }

    It 'removes inactive splash steps from runtime state' {
        $script:EnvironmentHelpersContent | Should -Match "Get-BaselineLocalizedString -Key 'Bootstrap_StepCheckingForUpdates' -Fallback 'Checking for Updates'"
        $script:EnvironmentHelpersContent | Should -Match 'foreach \(\$knownStepId in @\(''updates'', ''system'', ''winget'', ''chocolatey'', ''finalize''\)\)'
        $script:EnvironmentHelpersContent | Should -Match 'if \(-not \$activeSplashStepIds\.ContainsKey\(\$knownStepId\)\)'
        $script:EnvironmentHelpersContent | Should -Match '\[void\]\$stepGlyphs\.Remove\(\$knownStepId\)'
        $script:EnvironmentHelpersContent | Should -Match '\$initialStepId = if \(\$splashStepOrder\.Count -gt 0\) \{ \[string\]\$splashStepOrder\[0\] \} else \{ ''finalize'' \}'
        $script:EnvironmentHelpersContent | Should -Not -Match "Bootstrap_StepUpdateCheck"
    }

    It 'uses a value-driven progress bar template with standard named parts' {
        $script:EnvironmentHelpersContent | Should -Match '<ProgressBar Name="ProgressBar"'
        $script:EnvironmentHelpersContent | Should -Match 'x:Name="PART_Track"'
        $script:EnvironmentHelpersContent | Should -Match 'x:Name="PART_Indicator"'
        $script:EnvironmentHelpersContent | Should -Match 'x:Name="PART_GlowRect"'
        $script:EnvironmentHelpersContent | Should -Match 'Width="\{TemplateBinding Value\}"'
        $script:EnvironmentHelpersContent | Should -Not -Match '<Border Background="\{TemplateBinding Foreground\}" CornerRadius="2"\s*/>'
    }

    It 'scales splash progress values to the rendered bar width' {
        $script:EnvironmentHelpersContent | Should -Match 'function Get-BaselineSplashProgressWidth'
        $script:EnvironmentHelpersContent | Should -Match '\$barWidth = Get-BaselineSplashProgressWidth -ProgressBar \$progressBar'
        $script:EnvironmentHelpersContent | Should -Match '\$progressBar.Maximum = \$barWidth'
        $script:EnvironmentHelpersContent | Should -Match '\$progressBar.Value = \[Math\]::Round\(\(\(\$safeCompleted / \$safeTotal\) \* \$barWidth\), 3\)'
        $script:EnvironmentHelpersContent | Should -Match '\$snapTo = \(\[double\]\$activeIdx / \$stepCount\) \* \$barWidth'
        $script:EnvironmentHelpersContent | Should -Match '\$anim.To   = \(\[double\]\$completedCount / \$stepCount\) \* \$barWidth'
    }

    It 'routes splash icon failures through debug logging and chrome failures through launch tracing' {
        $script:EnvironmentHelpersContent | Should -Match 'function Show-BootstrapLoadingSplash'
        $script:EnvironmentHelpersContent | Should -Match 'Environment\.ShowBootstrapLoadingSplash\.LoadSplashIcon'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash chrome setup failed'
    }

    It 'loads the splash theme dictionary and binds splash chrome with DynamicResource brushes' {
        $script:EnvironmentHelpersContent | Should -Match 'Module\\GUI\\Themes\\\{0\}'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Resources\.MergedDictionaries\.Add\(\$themeDictionary\)'
        $script:EnvironmentHelpersContent | Should -Match 'Background="Transparent"\s+BorderBrush="Transparent"\s+BorderThickness="0"'
        $script:EnvironmentHelpersContent | Should -Match '<Border Name="RootBorder"[^>]+Background="\{DynamicResource Brush\.SplashBackdrop\}"[^>]+BorderBrush="\{DynamicResource Brush\.Border\}"[^>]+BorderThickness="1"[^>]+HorizontalAlignment="Stretch"[^>]+VerticalAlignment="Stretch"'
        $script:EnvironmentHelpersContent | Should -Match '<Grid Background="Transparent" Margin="0"[^>]+HorizontalAlignment="Stretch"[^>]+VerticalAlignment="Stretch"'
        $script:EnvironmentHelpersContent | Should -Match '<Grid Grid\.Row="0" Background="\{DynamicResource Brush\.HeaderBg\}"'
        $script:EnvironmentHelpersContent | Should -Match '<Border Name="SplashContentCard"[^>]+Background="\{DynamicResource Brush\.SplashCard\}"[^>]+BorderThickness="0"'
        $script:EnvironmentHelpersContent | Should -Not -Match '<Border Name="SplashContentCard"[^>]+BorderBrush="\{DynamicResource Brush\.SplashCardBorder\}"'
        $script:EnvironmentHelpersContent | Should -Match '<DropShadowEffect Color="#000000" BlurRadius="34" ShadowDepth="0" Opacity="0\.18"\s*/>'
        $script:EnvironmentHelpersContent | Should -Not -Match 'Name="SplashLogoCard"'
        $script:EnvironmentHelpersContent | Should -Match 'Background="\{DynamicResource Brush\.SplashBackdrop\}"'
        $script:EnvironmentHelpersContent | Should -Match 'Foreground="\{DynamicResource Brush\.TextPrimary\}"'
        $script:EnvironmentHelpersContent | Should -Match 'Foreground="\{DynamicResource Brush\.SplashSubtitle\}"'
        $script:EnvironmentHelpersContent | Should -Match 'Width="360" Height="6"'
        $script:EnvironmentHelpersContent | Should -Match '<DropShadowEffect Color="\{DynamicResource Color\.Progress\}" BlurRadius="10" ShadowDepth="0" Opacity="0\.35"\s*/>'
    }

    It 'keeps a live splash runspace when rendering is delayed' {
        $script:EnvironmentHelpersContent | Should -Match 'WasLoaded\s*=\s*\$false'
        $script:EnvironmentHelpersContent | Should -Match 'WasRendered\s*=\s*\$false'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_Loaded\(\{[\s\S]*\$syncHash\[''WasLoaded''\] = \$true'
        $script:EnvironmentHelpersContent | Should -Match '\$splash\.Add_ContentRendered\(\{[\s\S]*\$syncHash\[''WasRendered''\] = \$true[\s\S]*\$syncHash\[''IsReady''\] = \$true'
        $script:EnvironmentHelpersContent | Should -Match '\$splashStartupFailed = -not \$syncHash\[''IsAlive''\]'
        $script:EnvironmentHelpersContent | Should -Match 'if \(\$splashStartupFailed\)'
        $script:EnvironmentHelpersContent | Should -Match 'elseif \(-not \$syncHash\[''WasRendered''\]\)'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash render pending after readiness wait; leaving runspace active\.'

        $loadedBlock = [regex]::Match(
            $script:EnvironmentHelpersContent,
            '(?s)\$splash\.Add_Loaded\(\{.*?\}\)\s*\r?\n\r?\n\s*\$splash\.Add_ContentRendered'
        ).Value
        $loadedSuccessBlock = [regex]::Match($loadedBlock, '(?s)try\s*\{(?<Body>.*?)\}\s*catch').Groups['Body'].Value
        $loadedSuccessBlock | Should -Not -Match '\$syncHash\[''WasShown''\] = \$true'
        $loadedSuccessBlock | Should -Not -Match '\$syncHash\[''IsReady''\] = \$true'
    }

    It 'records splash thread failures instead of reporting a successful splash' {
        $script:EnvironmentHelpersContent | Should -Match 'ErrorMessage\s*=\s*\$null'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash runspace failed'
        $script:EnvironmentHelpersContent | Should -Match 'Bootstrap splash failed before it became visible'
    }
}

Describe 'Get-BaselineLatestReleaseEntry' {
    BeforeEach {
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'selects the highest non-draft release regardless of API ordering when pre-release builds are included' {
        $releases = @(
            [pscustomobject]@{ draft = $false; tag_name = 'v3.0.0-beta'; published_at = '2026-03-01T00:00:00Z' }
            [pscustomobject]@{ draft = $false; tag_name = 'v4.0.0-beta'; published_at = '2026-04-01T00:00:00Z' }
        )

        $result = Get-BaselineLatestReleaseEntry -Releases $releases -IncludePrerelease

        [string]$result.tag_name | Should -Be 'v4.0.0-beta'
    }

    It 'skips pre-release builds by default' {
        $releases = @(
            [pscustomobject]@{ draft = $false; prerelease = $true; tag_name = 'v5.0.0-beta'; published_at = '2026-05-01T00:00:00Z' }
            [pscustomobject]@{ draft = $false; prerelease = $false; tag_name = 'v4.0.0'; published_at = '2026-04-02T00:00:00Z' }
        )

        $result = Get-BaselineLatestReleaseEntry -Releases $releases

        [string]$result.tag_name | Should -Be 'v4.0.0'
    }

    It 'prefers a stable release over a prerelease with the same core version' {
        $releases = @(
            [pscustomobject]@{ draft = $false; prerelease = $true; tag_name = 'v4.0.0-beta'; published_at = '2026-04-01T00:00:00Z' }
            [pscustomobject]@{ draft = $false; prerelease = $false; tag_name = 'v4.0.0'; published_at = '2026-04-02T00:00:00Z' }
        )

        $result = Get-BaselineLatestReleaseEntry -Releases $releases

        [string]$result.tag_name | Should -Be 'v4.0.0'
    }

    It 'selects the latest release that contains the requested channel asset' {
        $releases = @(
            [pscustomobject]@{
                draft = $false
                prerelease = $false
                tag_name = 'v1.0.0'
                published_at = '2026-05-25T00:00:00Z'
                assets = @([pscustomobject]@{ name = 'Baseline-1.0.0-stable.zip' })
            }
            [pscustomobject]@{
                draft = $false
                prerelease = $true
                tag_name = 'v1.0.0-beta'
                published_at = '2026-05-24T00:00:00Z'
                assets = @([pscustomobject]@{ name = 'Baseline-1.0.0-beta.zip' })
            }
        )

        $result = Get-BaselineLatestReleaseEntry -Releases $releases -IncludePrerelease -AssetPattern 'Baseline-*-beta.zip'

        [string]$result.tag_name | Should -Be 'v1.0.0-beta'
    }

    It 'skips malformed published_at values after routing the parse error' {
        $releases = @(
            [pscustomobject]@{ draft = $false; prerelease = $false; tag_name = 'v3.0.0-beta'; published_at = 'not-a-date' }
            [pscustomobject]@{ draft = $false; prerelease = $false; tag_name = 'v4.0.0'; published_at = '2026-04-02T00:00:00Z' }
        )

        $result = Get-BaselineLatestReleaseEntry -Releases $releases

        [string]$result.tag_name | Should -Be 'v4.0.0'
        $script:DebugSwallowedExceptionCalls.Count | Should -Be 1
        $script:DebugSwallowedExceptionCalls[0].Source | Should -Be 'Environment.GetBaselineLatestReleaseEntry.ParsePublishedAt'
    }
}

Describe 'Test-BaselineReleaseUpdateRequired' {
    It 'allows an explicit beta channel switch from the same stable core version' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0-beta' -CurrentVersion 'v1.0.0' -UpdateBranch 'Beta' |
            Should -BeTrue
    }

    It 'does not treat the same beta build as a new update once already on beta' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0-beta' -CurrentVersion 'v1.0.0 (beta)' -UpdateBranch 'Beta' |
            Should -BeFalse
    }

    It 'does not treat the same beta build as a new update when the launcher reports a plain numeric version' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0-beta' -CurrentVersion 'v1.0.0' -UpdateBranch 'Beta' -CurrentBuildBranch 'Beta' |
            Should -BeFalse
    }

    It 'allows an explicit stable channel switch from a newer beta build' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0' -CurrentVersion 'v4.0.0 (beta)' -UpdateBranch 'Stable' |
            Should -BeTrue
    }

    It 'allows an explicit stable channel switch when the beta launcher reports a plain numeric version' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0' -CurrentVersion 'v4.0.0' -UpdateBranch 'Stable' -CurrentBuildBranch 'Beta' |
            Should -BeTrue
    }

    It 'allows an explicit beta channel switch from a newer stable build' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0-beta' -CurrentVersion 'v4.0.0' -UpdateBranch 'Beta' -CurrentBuildBranch 'Stable' |
            Should -BeTrue
    }

    It 'does not downgrade a stable build to an older stable release' {
        Test-BaselineReleaseUpdateRequired -LatestVersion 'v1.0.0' -CurrentVersion 'v4.0.0' -UpdateBranch 'Stable' |
            Should -BeFalse
    }
}

Describe 'Invoke-BaselineUpdateCheck' {
    BeforeEach {
        $script:updateCheckThrottlePath = Join-Path $TestDrive 'manual-update-check.json'
        Remove-Item -LiteralPath $script:updateCheckThrottlePath -Force -ErrorAction SilentlyContinue
        Mock Get-BaselineAutoUpdateThrottlePath { $script:updateCheckThrottlePath }
        Mock Set-DownloadSecurityProtocol {}
    }

    It 'offers the stable release when the current beta build reports only its numeric version' {
        Mock Get-BaselineDefaultUpdateBranch { 'Beta' }
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{
                    draft        = $false
                    prerelease   = $false
                    tag_name     = 'v1.0.0'
                    published_at = '2026-05-25T00:00:00Z'
                    assets       = @([pscustomobject]@{ name = 'Baseline-1.0.0-stable.zip' })
                }
            )
        }

        $result = Invoke-BaselineUpdateCheck -CurrentVersion '4.0.0' -UpdateBranch 'Stable'

        $result.Status | Should -Be 'Update available'
        $result.IsUpdateAvailable | Should -BeTrue
        $result.LatestVersion | Should -Be 'v1.0.0'
        $result.RepositoryUrl | Should -Be 'https://github.com/sdmanson8/Baseline'
    }
}

Describe 'Get-BaselineValidationMatrixSummary' {
    It 'loads server coverage from the integration validation matrix' {
        $repoRoot = Join-Path $TestDrive 'RepoRoot'
        $matrixRoot = Join-Path $repoRoot 'Tests/Integration'
        $null = New-Item -ItemType Directory -Path $matrixRoot -Force
        $matrixPath = Join-Path $matrixRoot 'DesktopMatrixResults.json'
        Set-Content -LiteralPath $matrixPath -Encoding UTF8 -Value @'
{
  "summary": {
    "testedDesktopEditions": ["Windows 11 Pro (26100)"],
    "pendingDesktopEditions": ["Windows 10 22H2"],
    "serverEditions": ["Windows Server 2022 (CI only)"]
  }
}
'@

        $result = Get-BaselineValidationMatrixSummary -RepoRoot $repoRoot

        $result.Summary | Should -Be 'Validated: Windows 11 Pro (26100) | Pending: Windows 10 22H2 | Server: Windows Server 2022 (CI only)'
        $result.ServerValidationSummary | Should -Be 'CI only: Windows Server 2022 (CI only)'
        $result.ServerCoverageStatus | Should -Be 'CIOnly'
        $result.HasServerCoverage | Should -BeTrue
        $result.ServerCIOnly | Should -BeTrue
    }
}

Describe 'Get-BaselineValidationEvidenceReport' {
    It 'combines test report and validation matrix channels into a provenance summary' {
        $repoRoot = Join-Path $TestDrive 'RepoRoot'
        $testsRoot = Join-Path $repoRoot 'Tests'
        $integrationRoot = Join-Path $testsRoot 'Integration'
        $null = New-Item -ItemType Directory -Path $integrationRoot -Force

        Set-Content -LiteralPath (Join-Path $testsRoot 'TestReport.json') -Encoding UTF8 -Value @'
{
  "generated": "2026-04-14T14:38:31.7842438+02:00",
  "platform": {
    "os": "Microsoft Windows NT 10.0.26100.0",
    "edition": "Core",
    "psVersion": "7.6.0",
    "hostname": "SHELDON"
  },
  "layers": {
    "unit": {
      "result": "Passed",
      "passed": 2640,
      "failed": 0,
      "skipped": 4
    },
    "composition": {
      "result": "Passed",
      "passed": 27,
      "failed": 0,
      "skipped": 0
    }
  },
  "summary": {
    "overallResult": "Passed"
  }
}
'@

        Set-Content -LiteralPath (Join-Path $integrationRoot 'DesktopMatrixResults.json') -Encoding UTF8 -Value @'
{
  "summary": {
    "testedDesktopEditions": ["Windows 11 Pro (26100)"],
    "pendingDesktopEditions": [],
    "serverEditions": ["Windows Server 2022 (CI only)"]
  }
}
'@

        $result = Get-BaselineValidationEvidenceReport -RepoRoot $repoRoot

        $result.Schema | Should -Be 'Baseline.ValidationEvidence'
        $result.Summary | Should -Be 'unit-tested; desktop-session CI validated; server CI only'
        @($result.ValidationChannels).Count | Should -Be 3
        ($result.ValidationChannels | Where-Object Channel -eq 'unit-tested').Status | Should -Be 'Passed'
        ($result.ValidationChannels | Where-Object Channel -eq 'desktop-session CI validated').Status | Should -Be 'Passed'
        ($result.ValidationChannels | Where-Object Channel -eq 'server CI only').Status | Should -Be 'CI only'
    }
}

Describe 'Invoke-BaselineAutoUpdate' {
    BeforeEach {
        Remove-Item Env:\BASELINE_EMBEDDED_HOST -ErrorAction SilentlyContinue
        Remove-Item Env:\BASELINE_INSTALLER_MODE -ErrorAction SilentlyContinue
        Remove-Item Env:\BASELINE_SKIP_UPDATE -ErrorAction SilentlyContinue
        Remove-Item Env:\BASELINE_LAUNCHER_PATH -ErrorAction SilentlyContinue
        $script:autoUpdateThrottlePath = Join-Path $TestDrive 'auto-update-check.json'
        Remove-Item -LiteralPath $script:autoUpdateThrottlePath -Force -ErrorAction SilentlyContinue
        $script:loggedInfoMessages = [System.Collections.Generic.List[string]]::new()
        Mock LogInfo {
            param([object]$Message)
            [void]$script:loggedInfoMessages.Add([string]$Message)
        }
        Mock Get-BaselineAutoUpdateThrottlePath { $script:autoUpdateThrottlePath }
        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $true
                CheckFrequency = 'Startup'
                UpdateBranch = 'Stable'
                IncludePrereleaseBuilds = $false
            }
        }
        Mock Test-BaselineUpdateEndpointAvailable { $true }
    }

    It 'allows the startup auto-update check when no throttle file exists' {
        $path = Join-Path $TestDrive 'missing-auto-update-check.json'

        $decision = Get-BaselineAutoUpdateThrottleDecision -Path $path -NowUtc ([datetime]'2026-04-30T12:00:00Z') -MinimumIntervalHours 4

        $decision.ShouldCheck | Should -BeTrue
    }

    It 'blocks the startup auto-update check inside the four-hour throttle window' {
        $path = Join-Path $TestDrive 'recent-auto-update-check.json'
        Set-BaselineAutoUpdateThrottleTimestamp -Path $path -NowUtc ([datetime]'2026-04-30T10:00:00Z')

        $decision = Get-BaselineAutoUpdateThrottleDecision -Path $path -NowUtc ([datetime]'2026-04-30T13:59:59Z') -MinimumIntervalHours 4

        $decision.ShouldCheck | Should -BeFalse
        $decision.NextEligibleUtc.ToUniversalTime().ToString('o') | Should -Be '2026-04-30T14:00:00.0000000Z'
    }

    It 'allows the startup auto-update check after the four-hour throttle window' {
        $path = Join-Path $TestDrive 'elapsed-auto-update-check.json'
        Set-BaselineAutoUpdateThrottleTimestamp -Path $path -NowUtc ([datetime]'2026-04-30T10:00:00Z')

        $decision = Get-BaselineAutoUpdateThrottleDecision -Path $path -NowUtc ([datetime]'2026-04-30T14:00:00Z') -MinimumIntervalHours 4

        $decision.ShouldCheck | Should -BeTrue
    }

    It 'stays idle when the launcher flag is missing' {
        Mock Invoke-RestMethod {
            throw 'release lookup should not run'
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw
        Assert-MockCalled Invoke-RestMethod -Times 0
    }

    It 'queries GitHub when Baseline.exe launches the updater' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII

        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $true
                CheckFrequency = 'Startup'
                UpdateBranch = 'Beta'
                IncludePrereleaseBuilds = $false
            }
        }
        Mock Set-DownloadSecurityProtocol {}
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                draft    = $false
                tag_name = '4.0.0'
                assets   = @()
            }
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw
        Assert-MockCalled Set-DownloadSecurityProtocol -Times 1
        Assert-MockCalled Invoke-RestMethod -Times 1
        Test-Path -LiteralPath $script:autoUpdateThrottlePath | Should -BeTrue
    }

    It 'queries the beta release repository when the beta update branch is selected' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII
        $script:updateCheckUri = ''

        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $true
                CheckFrequency = 'Startup'
                UpdateBranch = 'Beta'
                IncludePrereleaseBuilds = $false
            }
        }
        Mock Set-DownloadSecurityProtocol {}
        Mock Invoke-RestMethod {
            param($Uri)
            $script:updateCheckUri = [string]$Uri
            [pscustomobject]@{
                draft    = $false
                tag_name = '4.0.0'
                assets   = @()
            }
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw

        $script:updateCheckUri | Should -Be 'https://api.github.com/repos/sdmanson8/baseline_dev/releases'
    }

    It 'does not touch the network when automatic update checks are disabled' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII

        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $false
                CheckFrequency = 'Startup'
                UpdateBranch = 'Stable'
                IncludePrereleaseBuilds = $false
            }
        }
        Mock Set-DownloadSecurityProtocol {
            throw 'security protocol should not be set'
        }
        Mock Invoke-RestMethod {
            throw 'release lookup should not run'
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw

        Assert-MockCalled Set-DownloadSecurityProtocol -Times 0
        Assert-MockCalled Test-BaselineUpdateEndpointAvailable -Times 0
        Assert-MockCalled Invoke-RestMethod -Times 0
        (Get-BaselineUpdateCheckState -Path $script:autoUpdateThrottlePath).Status | Should -Be 'Disabled'
    }

    It 'marks startup update checks as skipped when the release endpoint is offline' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII

        Mock Test-BaselineUpdateEndpointAvailable { $false }
        Mock Set-DownloadSecurityProtocol {
            throw 'security protocol should not be set'
        }
        Mock Invoke-RestMethod {
            throw 'release lookup should not run'
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw

        Assert-MockCalled Set-DownloadSecurityProtocol -Times 0
        Assert-MockCalled Invoke-RestMethod -Times 0
        (Get-BaselineUpdateCheckState -Path $script:autoUpdateThrottlePath).Status | Should -Be 'Skipped (offline)'
    }

    It 'keeps the startup update check on determinate checklist progress' {
        $script:EnvironmentHelpersContent | Should -Match 'Set-BootstrapLoadingSplashState\s+-Splash \$Splash\s+-Completed 0\s+-Total 5'
        $script:EnvironmentHelpersContent | Should -Not -Match '(?s)Set-BootstrapLoadingSplashState\s+-Splash \$Splash\s+-StatusText\s+\(Get-BaselineLocalizedString\s+-Key ''Bootstrap_CheckingForUpdates''\s+-Fallback ''Checking for updates\.\.\.''\)'
    }

    It 'does not query GitHub again before the configured daily interval elapses' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII
        Set-BaselineUpdateCheckState -Path $script:autoUpdateThrottlePath -Status 'Up to date' -LatestVersion '4.0.0' -NowUtc ([datetime]::UtcNow.AddHours(-1))

        Mock Set-DownloadSecurityProtocol {}
        Mock Invoke-RestMethod {
            throw 'release lookup should not run'
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}
        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $true
                CheckFrequency = 'Daily'
                UpdateBranch = 'Stable'
                IncludePrereleaseBuilds = $false
            }
        }

        { Invoke-BaselineAutoUpdate -CurrentVersion '4.0.0' } | Should -Not -Throw

        Assert-MockCalled Invoke-RestMethod -Times 0
        ($script:loggedInfoMessages -join "`n") | Should -Match 'frequency interval has not elapsed'
    }

    It 'uses the highest non-draft release tag when deciding whether the current build is up to date' {
        $env:BASELINE_EMBEDDED_HOST = '1'
        $env:BASELINE_LAUNCHER_PATH = Join-Path $TestDrive 'Baseline.exe'
        Set-Content -LiteralPath $env:BASELINE_LAUNCHER_PATH -Value '' -Encoding ASCII

        Mock Get-BaselineUpdateSettings {
            [pscustomobject]@{
                AutoCheckUpdates = $true
                CheckFrequency = 'Startup'
                UpdateBranch = 'Beta'
                IncludePrereleaseBuilds = $false
            }
        }
        Mock Set-DownloadSecurityProtocol {}
        Mock Invoke-RestMethod {
            @(
                [pscustomobject]@{
                    draft    = $false
                    tag_name = 'v3.0.0-beta'
                    assets   = @([pscustomobject]@{ name = 'Baseline-3.0.0-beta.zip' })
                }
                [pscustomobject]@{
                    draft    = $false
                    tag_name = 'v4.0.0-beta'
                    assets   = @([pscustomobject]@{ name = 'Baseline-4.0.0-beta.zip' })
                }
            )
        }
        Mock Set-BootstrapLoadingSplashState {}
        Mock Close-LoadingSplashWindow {}

        { Invoke-BaselineAutoUpdate -CurrentVersion 'v4.0.0 (beta)' } | Should -Not -Throw

        ($script:loggedInfoMessages -join "`n") | Should -Match 'Already up to date \(latest: v4\.0\.0-beta\)\.'
    }
}

Describe 'Get-LocalizedShellString' {
    It 'falls back and strips accelerators when the shell resource is unavailable' {
        $result = Get-LocalizedShellString -ResourceId 1 -Fallback '&Skip' -StripAccelerators

        $result | Should -Be 'Skip'
    }
}

Describe 'Baseline markdown runtime' {
    BeforeEach {
        $script:CachedBaselineMarkdownRuntimeLoaded = $false
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'uses loaded AppDomain assemblies instead of Type.GetType for Markdig readiness checks' {
        $content = Get-BaselineTestSourceText -Path $filePath

        $content | Should -Match '\[System\.AppDomain\]::CurrentDomain\.GetAssemblies\(\)'
        $content | Should -Match 'GetType\(''Markdig\.Wpf\.Markdown'', \$false, \$false\)'
        $content | Should -Not -Match 'Type\]::GetType\(''Markdig\.Wpf\.Markdown, Markdig\.Wpf''\)'
    }

    It 'loads the bundled Markdig runtime and renders markdown to html' {
        $moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module'))

        Initialize-BaselineMarkdownRuntime -ModuleRoot $moduleRoot | Should -BeTrue
        Test-BaselineMarkdownRuntimeReady | Should -BeTrue

        $html = ConvertFrom-BaselineMarkdownToHtml -Markdown '# Title'

        $html | Should -Match '<h1'
        $html | Should -Match 'Title'
    }

    It 'renders anchored FlowDocuments for README in-page links' {
        $moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module'))

        Initialize-BaselineMarkdownRuntime -ModuleRoot $moduleRoot | Should -BeTrue
        Test-BaselineMarkdownRuntimeReady | Should -BeTrue

        $result = ConvertFrom-BaselineMarkdownToAnchoredFlowDocument -Markdown "# Title`r`n`r`n[Jump](#title)"

        $result.Document | Should -Not -BeNullOrEmpty
        $result.AnchorMap.ContainsKey('title') | Should -BeTrue
        @($result.Hyperlinks).Count | Should -BeGreaterThan 0
        [string]$result.Hyperlinks[0].NavigateUri.OriginalString | Should -Be '#title'
    }

    It 'routes assembly load failures through Write-SwallowedException' {
        $moduleRoot = Join-Path $TestDrive 'MarkdownModuleRoot'
        $librariesRoot = Join-Path $moduleRoot 'Libraries'
        $null = New-Item -ItemType Directory -Path $librariesRoot -Force
        foreach ($dllName in @(
            'System.Buffers.dll',
            'System.Runtime.CompilerServices.Unsafe.dll',
            'System.Numerics.Vectors.dll',
            'System.Memory.dll',
            'Markdig.dll',
            'Markdig.Wpf.dll'
        ))
        {
            $null = New-Item -ItemType File -Path (Join-Path $librariesRoot $dllName) -Force
        }

        Mock Test-BaselineMarkdownRuntimeReady { $false }
        Initialize-BaselineMarkdownRuntime -ModuleRoot $moduleRoot | Should -BeFalse
        (@($script:DebugSwallowedExceptionCalls | Where-Object Source -eq 'Environment.InitializeBaselineMarkdownRuntime.AddAssembly')).Count | Should -Be 6
    }
}

Describe 'Baseline WinRT runtime dependencies' {
    It 'defines a loader for bundled Windows Runtime projection dependencies' {
        $script:EnvironmentHelpersContent | Should -Match 'function Initialize-BaselineWinRtRuntimeDependencies'
        $script:EnvironmentHelpersContent | Should -Match 'System\.Runtime\.CompilerServices\.Unsafe\.dll'
        $script:EnvironmentHelpersContent | Should -Match 'System\.Numerics\.Vectors\.dll'
        $script:EnvironmentHelpersContent | Should -Match 'Environment\.InitializeBaselineWinRtRuntimeDependencies\.AddAssembly'
    }
}

Describe 'Baseline webview2 runtime' {
    BeforeEach {
        $script:CachedBaselineWebView2RuntimeLoaded = $false
        $script:DebugSwallowedExceptionCalls.Clear()
    }

    It 'routes assembly load failures through Write-SwallowedException' {
        $moduleRoot = Join-Path $TestDrive 'WebView2ModuleRoot'
        $librariesRoot = Join-Path $moduleRoot 'Libraries'
        $null = New-Item -ItemType Directory -Path $librariesRoot -Force
        foreach ($dllName in @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll'))
        {
            $null = New-Item -ItemType File -Path (Join-Path $librariesRoot $dllName) -Force
        }

        Mock Test-Path { $true } -ParameterFilter {
            $LiteralPath -eq $moduleRoot -or
            $LiteralPath -eq $librariesRoot -or
            $LiteralPath -eq (Join-Path $librariesRoot 'Microsoft.Web.WebView2.Core.dll') -or
            $LiteralPath -eq (Join-Path $librariesRoot 'Microsoft.Web.WebView2.WinForms.dll')
        }

        Mock Test-BaselineWebView2RuntimeReady { $false }
        Initialize-BaselineWebView2Runtime -ModuleRoot $moduleRoot | Should -BeFalse
        (@($script:DebugSwallowedExceptionCalls | Where-Object Source -eq 'Environment.InitializeBaselineWebView2Runtime.AddAssembly')).Count | Should -Be 2
    }
}

Describe 'Bootstrap splash defaults' {
    It 'renders the custom splash title from the window title' {
        $script:EnvironmentHelpersContent | Should -Match 'Name="TitleText"'
        $script:EnvironmentHelpersContent | Should -Match 'Text="\{Binding RelativeSource=\{RelativeSource AncestorType=Window\}, Path=Title\}"'
    }

    It 'uses non-empty splash text fallbacks for initialization' {
        ([regex]::Matches($script:EnvironmentHelpersContent, "Get-BaselineLocalizedString -Key 'GuiSplashLoading' -Fallback 'Please Wait\.\.\.'")).Count | Should -Be 1
        $script:EnvironmentHelpersContent | Should -Match "GuiSplashSubtitle' -Fallback 'Review, preview, and apply system changes safely'"
        $script:EnvironmentHelpersContent | Should -Not -Match 'GuiSplashAutoClose|autoCloseEsc|This window will close automatically when ready'
    }

    It 'keeps every English splash localization on the neutral loading text' {
        foreach ($localeFile in $script:EnglishLocalizationFiles) {
            $content = Get-BaselineTestSourceText -Path $localeFile.FullName
            $content | Should -Match '"GuiSplashLoading": "(Please|Kindly) Wait\.\.\."'
        }
    }
}

Describe 'Bootstrap splash progress' {
    It 'preserves the current fill when an indeterminate status update arrives' {
        $dispatcher = [EnvironmentHelpersSplashTestDispatcher]::new()
        $statusText = [EnvironmentHelpersSplashTestElement]::new()
        $subActionPanel = [EnvironmentHelpersSplashTestElement]::new()
        $progressBar = [EnvironmentHelpersSplashTestProgressBar]::new()
        $progressBar.Value = 132
        $progressBar.Maximum = 330
        $progressBar.IsIndeterminate = $false
        $progressBar.Visibility = [System.Windows.Visibility]::Collapsed

        $splash = @{
            Window = [pscustomobject]@{}
            Dispatcher = $dispatcher
            StatusText = $statusText
            SubActionPanel = $subActionPanel
            ProgressBar = $progressBar
        }

        Set-BootstrapLoadingSplashState -Splash $splash -StatusText 'Checking installation status...' -Indeterminate | Should -BeTrue

        $statusText.Text | Should -Be 'Checking installation status...'
        $subActionPanel.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $progressBar.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $progressBar.IsIndeterminate | Should -BeTrue
        $progressBar.Value | Should -Be 132
        $progressBar.Maximum | Should -Be 330
    }

    It 'hides the splash status line for indeterminate updates when the status text is blank' {
        $dispatcher = [EnvironmentHelpersSplashTestDispatcher]::new()
        $statusText = [EnvironmentHelpersSplashTestElement]::new()
        $statusText.Text = 'Checking installation status...'
        $subActionPanel = [EnvironmentHelpersSplashTestElement]::new()
        $subActionPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $progressBar = [EnvironmentHelpersSplashTestProgressBar]::new()
        $progressBar.Visibility = [System.Windows.Visibility]::Collapsed
        $progressBar.IsIndeterminate = $false

        $splash = @{
            Window = [pscustomobject]@{}
            Dispatcher = $dispatcher
            StatusText = $statusText
            SubActionPanel = $subActionPanel
            ProgressBar = $progressBar
        }

        Set-BootstrapLoadingSplashState -Splash $splash -StatusText ([string]::Empty) -Indeterminate | Should -BeTrue

        $statusText.Text | Should -Be ''
        $subActionPanel.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $progressBar.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $progressBar.IsIndeterminate | Should -BeTrue
    }

    It 'keeps checklist progress determinate when an indeterminate status update follows an active step' {
        $dispatcher = [EnvironmentHelpersSplashTestDispatcher]::new()
        $statusText = [EnvironmentHelpersSplashTestElement]::new()
        $subActionPanel = [EnvironmentHelpersSplashTestElement]::new()
        $progressBar = [EnvironmentHelpersSplashTestProgressBar]::new()
        $progressBar.IsIndeterminate = $false
        $progressBar.Value = 24
        $progressBar.Maximum = 330

        $splash = @{
            Window = [pscustomobject]@{}
            Dispatcher = $dispatcher
            StatusText = $statusText
            SubActionPanel = $subActionPanel
            ProgressBar = $progressBar
            ChecklistProgressActive = $true
        }

        Set-BootstrapLoadingSplashState -Splash $splash -StatusText 'Checking for updates...' -Indeterminate | Should -BeTrue

        $subActionPanel.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $progressBar.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $progressBar.IsIndeterminate | Should -BeFalse
        $progressBar.Value | Should -Be 24
        $progressBar.Maximum | Should -Be 330
    }

    It 'starts determinate progress when the first splash step advances the bar' {
        $dispatcher = [EnvironmentHelpersSplashTestDispatcher]::new()
        $progressBar = [EnvironmentHelpersSplashTestProgressBar]::new()
        $progressBar.IsIndeterminate = $true
        $progressBar.Value = 0
        $progressBar.Maximum = 1

        $stepIds = @('updates', 'system', 'winget', 'chocolatey', 'finalize')
        $stepGlyphs = @{}
        $stepIdleDots = @{}
        $stepPulseDots = @{}
        $stepChecks = @{}
        $stepLabels = @{}
        $stepStates = @{}
        foreach ($stepId in $stepIds)
        {
            $stepGlyphs[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepIdleDots[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $pulseDot = [EnvironmentHelpersSplashTestElement]::new()
            $pulseDot.RenderTransform = [System.Windows.Media.ScaleTransform]::new()
            $stepPulseDots[$stepId] = $pulseDot
            $stepChecks[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepLabels[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepStates[$stepId] = 'pending'
        }

        $splash = @{
            Window = [pscustomobject]@{}
            Dispatcher = $dispatcher
            StepGlyphs = $stepGlyphs
            StepIdleDots = $stepIdleDots
            StepPulseDots = $stepPulseDots
            StepChecks = $stepChecks
            StepLabels = $stepLabels
            StepStates = $stepStates
            ProgressBar = $progressBar
            ChecklistProgressActive = $false
            SplashTheme = [pscustomobject]@{
                Muted   = '#6C7086'
                Sub     = '#A6ADC8'
                Primary = '#CDD6F4'
                Accent  = '#89B4FA'
            }
            StepOrder = $stepIds
        }

        Set-BootstrapLoadingSplashStep -Splash $splash -StepId 'updates' -Status 'in_progress' -SubAction '' | Should -BeTrue

        $progressBar.IsIndeterminate | Should -BeFalse
        $progressBar.Value | Should -BeGreaterThan 0
        $progressBar.Maximum | Should -Be 330
        $splash.ChecklistProgressActive | Should -BeTrue
    }

    It 'keeps the final splash handoff moving until GUI readiness completes it' {
        $dispatcher = [EnvironmentHelpersSplashTestDispatcher]::new()
        $progressBar = [EnvironmentHelpersSplashTestProgressBar]::new()
        $progressBar.IsIndeterminate = $false
        $progressBar.Value = 264
        $progressBar.Maximum = 330

        $stepIds = @('updates', 'system', 'winget', 'chocolatey', 'finalize')
        $stepGlyphs = @{}
        $stepIdleDots = @{}
        $stepPulseDots = @{}
        $stepChecks = @{}
        $stepLabels = @{}
        $stepStates = @{}
        foreach ($stepId in $stepIds)
        {
            $stepGlyphs[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepIdleDots[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $pulseDot = [EnvironmentHelpersSplashTestElement]::new()
            $pulseDot.RenderTransform = [System.Windows.Media.ScaleTransform]::new()
            $stepPulseDots[$stepId] = $pulseDot
            $stepChecks[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepLabels[$stepId] = [EnvironmentHelpersSplashTestElement]::new()
            $stepStates[$stepId] = if ($stepId -eq 'finalize') { 'pending' } else { 'completed' }
        }

        $splash = @{
            Window = [pscustomobject]@{}
            Dispatcher = $dispatcher
            StepGlyphs = $stepGlyphs
            StepIdleDots = $stepIdleDots
            StepPulseDots = $stepPulseDots
            StepChecks = $stepChecks
            StepLabels = $stepLabels
            StepStates = $stepStates
            ProgressBar = $progressBar
            ChecklistProgressActive = $false
            SplashTheme = [pscustomobject]@{
                Muted   = '#6C7086'
                Sub     = '#A6ADC8'
                Primary = '#CDD6F4'
                Accent  = '#89B4FA'
            }
            StepOrder = $stepIds
        }

        Set-BootstrapLoadingSplashStep -Splash $splash -StepId 'finalize' -Status 'in_progress' -SubAction '' | Should -BeTrue

        $progressBar.IsIndeterminate | Should -BeFalse
        $progressBar.Value | Should -BeGreaterThan 320
        $progressBar.Value | Should -BeLessOrEqual 321
        $splash.ChecklistProgressActive | Should -BeTrue

        Set-BootstrapLoadingSplashStep -Splash $splash -StepId 'finalize' -Status 'completed' -SubAction '' | Should -BeTrue

        $progressBar.Value | Should -Be 330
        $splash.ChecklistProgressActive | Should -BeFalse
        $splash.CompletionAnimationDeadlineUtc | Should -BeOfType ([datetime])
    }

    It 'keeps splash step pulse animation scoped to the active step and responsive' {
        $script:EnvironmentHelpersContent | Should -Match '\$sxa\.From = 1\.0; \$sxa\.To = 1\.4'
        $script:EnvironmentHelpersContent | Should -Match '\$sxa\.Duration = New-Object System\.Windows\.Duration \(\[TimeSpan\]::FromMilliseconds\(360\)\)'
        $script:EnvironmentHelpersContent | Should -Match '\$sya\.From = 1\.0; \$sya\.To = 1\.4'
        $script:EnvironmentHelpersContent | Should -Match '\$sya\.Duration = New-Object System\.Windows\.Duration \(\[TimeSpan\]::FromMilliseconds\(360\)\)'
        $script:EnvironmentHelpersContent | Should -Match '\$oa\.From = 0\.6; \$oa\.To = 1\.0'
        $script:EnvironmentHelpersContent | Should -Match '\$oa\.Duration = New-Object System\.Windows\.Duration \(\[TimeSpan\]::FromMilliseconds\(360\)\)'
        $script:EnvironmentHelpersContent | Should -Match '\$stopInactivePulseDots = \{'
        $script:EnvironmentHelpersContent | Should -Match '\$activePulseStepId = if \(\$Status -eq ''in_progress''\) \{ \$StepId \} else \{ \$null \}'
        $script:EnvironmentHelpersContent | Should -Match '& \$stopInactivePulseDots \$activePulseStepId'
        $script:EnvironmentHelpersContent | Should -Match '\$fillDurationMs = 2200'
        $script:EnvironmentHelpersContent | Should -Match '\$fillDurationMs = 24000'
        $script:EnvironmentHelpersContent | Should -Match '\$handoffCeiling = \$barWidth \* 0\.97'
        $script:EnvironmentHelpersContent | Should -Not -Match '\[TimeSpan\]::FromSeconds\(5\)'
    }
}

Describe 'Test-IsVirtualMachine' {
    It 'returns $true when Win32_ComputerSystem reports a virtual-machine model' {
        Mock Get-CimInstance {
            [pscustomobject]@{ Model = 'Virtual Machine' }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        Test-IsVirtualMachine | Should -BeTrue
    }

    It 'returns $true for known hypervisor signatures (VMware, VBOX)' {
        Mock Get-CimInstance {
            [pscustomobject]@{ Model = 'VMware Virtual Platform' }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Test-IsVirtualMachine | Should -BeTrue

        Mock Get-CimInstance {
            [pscustomobject]@{ Model = 'VirtualBox (VBOX)' }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        Test-IsVirtualMachine | Should -BeTrue
    }

    It 'returns $false for a physical machine model' {
        Mock Get-CimInstance {
            [pscustomobject]@{ Model = 'OptiPlex 7090' }
        } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        Test-IsVirtualMachine | Should -BeFalse
    }

    It 'returns $false when CIM lookup fails rather than throwing' {
        Mock Get-CimInstance { throw 'cim offline' } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }

        Test-IsVirtualMachine | Should -BeFalse
    }
}
