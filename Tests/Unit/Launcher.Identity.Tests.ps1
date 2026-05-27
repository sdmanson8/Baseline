Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:LauncherProgramPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Launcher/Program.cs'))
    $script:LauncherProjectPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Launcher/RunLauncher.csproj'))
    $script:LauncherManifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Launcher/Baseline.manifest'))
    $script:LauncherSurfacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Launcher/EmbeddedRuntimeSurface.json'))
    $script:BootstrapPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Bootstrap/Baseline.ps1'))
    $script:InitialActionsPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module/Regions/InitialActions.psm1'))
    $script:UwpAppsPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1'))
    $script:SystemWindowsFeaturesPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1'))
    $script:TelemetryServicesPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1'))
    $script:BuildLauncherPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Tools/Build-Launcher.ps1'))

    $script:LauncherProgramContent = Get-BaselineTestSourceText -Path $script:LauncherProgramPath
    $script:LauncherProjectContent = Get-BaselineTestSourceText -Path $script:LauncherProjectPath
    $script:LauncherManifestContent = Get-BaselineTestSourceText -Path $script:LauncherManifestPath
    $script:LauncherSurfaceContent = Get-BaselineTestSourceText -Path $script:LauncherSurfacePath
    $script:BootstrapContent = Get-BaselineTestSourceText -Path $script:BootstrapPath
    $script:InitialActionsContent = Get-BaselineTestSourceText -Path $script:InitialActionsPath
    $script:UwpAppsContent = Get-BaselineTestSourceText -Path $script:UwpAppsPath
    $script:SystemWindowsFeaturesContent = Get-BaselineTestSourceText -Path $script:SystemWindowsFeaturesPath
    $script:TelemetryServicesContent = Get-BaselineTestSourceText -Path $script:TelemetryServicesPath
    $script:BuildLauncherContent = Get-BaselineTestSourceText -Path $script:BuildLauncherPath
}

Describe 'Launcher identity host' {
    It 'hosts Windows PowerShell in-process instead of shelling out to powershell.exe' {
        $script:LauncherProgramContent | Should -Match 'RunspaceFactory\.CreateRunspace\(host, initialSessionState\)'
        $script:LauncherProgramContent | Should -Match 'PowerShell\.Create\(\)'
        $script:LauncherProgramContent | Should -Match 'BaselinePowerShellHost'
        $script:LauncherProgramContent | Should -Not -Match 'ProcessStartInfo'
        $script:LauncherProgramContent | Should -Not -Match 'Process\.Start'
    }

    It 'keys the hydrated runtime cache by build identity, version, and launcher fingerprint' {
        $script:LauncherProgramContent | Should -Match 'ManifestModule\.ModuleVersionId\.ToString\("N"\)'
        $script:LauncherProgramContent | Should -Match 'Substring\(0,\s*12\)'
        $script:LauncherProgramContent | Should -Match 'RuntimeCacheSchema\s*=\s*"4"'
        $script:LauncherProgramContent | Should -Match 'Path\.Combine\(cacheRoot, version, RuntimeCacheSchema, buildId, launcherFingerprint\)'
        $script:LauncherProgramContent | Should -Match 'GetLauncherCacheFingerprint\(launcherPath\)'
        $script:LauncherProgramContent | Should -Match 'GetRestrictedRuntimeCacheRoot\(\)'
        $script:LauncherProgramContent | Should -Match 'Environment\.SpecialFolder\.CommonApplicationData'
        $script:LauncherProgramContent | Should -Match 'EnsureRestrictedDirectory\(cacheRoot\)'
        $script:LauncherProgramContent | Should -Match 'WellKnownSidType\.BuiltinAdministratorsSid'
        $script:LauncherProgramContent | Should -Match 'WellKnownSidType\.LocalSystemSid'
        $script:LauncherProgramContent | Should -Match 'SHA256\.Create\(\)'
        $script:LauncherProgramContent | Should -Match 'sentinelLines\.Length != 4'
    }

    It 'embeds shared helper wrapper modules and validates the full payload before cache reuse' {
        $script:LauncherProjectContent | Should -Match '<EmbeddedResource Include="\.\./Bootstrap/Helpers/\*\.ps1">'
        $script:LauncherSurfaceContent | Should -Match '"Bootstrap/Helpers/\*\.ps1"'
        $script:LauncherProjectContent | Should -Match 'BaselinePayload/Bootstrap/Helpers/%\(Filename\)%\(Extension\)'
        $script:LauncherProjectContent | Should -Match '<EmbeddedResource Include="\.\./Module/SharedHelpers/\*\*/\*\.ps1">'
        $script:LauncherSurfaceContent | Should -Match '"Module/SharedHelpers/\*\*/\*\.ps1"'
        $script:LauncherProjectContent | Should -Match '<EmbeddedResource Include="\.\./Module/GUIExecution/\*\*/\*\.ps1">'
        $script:LauncherSurfaceContent | Should -Match '"Module/GUIExecution/\*\*/\*\.ps1"'
        $script:LauncherProjectContent | Should -Match '<EmbeddedResource Include="\.\./Module/SharedHelperModules/\*\.psm1">'
        $script:LauncherSurfaceContent | Should -Match '"Module/SharedHelperModules/\*\.psm1"'
        $script:LauncherProjectContent | Should -Match 'BaselinePayload/Module/SharedHelperModules/%\(Filename\)%\(Extension\)'
        $script:LauncherProjectContent | Should -Match '<EmbeddedResource Include="\.\./Module/integrity\.manifest\.json">'
        $script:LauncherSurfaceContent | Should -Match '"Module/integrity\.manifest\.json"'
        $script:LauncherProgramContent | Should -Match 'GetEmbeddedPayloadResourceNames\(asm\)'
        $script:LauncherProgramContent | Should -Match 'GetEmbeddedPayloadManifest\(asm\)'
        $script:LauncherProgramContent | Should -Match 'ComputeHydratedResourceSha256\(asm, resourceName, relativePath\)'
        $script:LauncherProgramContent | Should -Match 'HydrationManifestMatches\(root, payloadManifest\)'
        $script:LauncherProgramContent | Should -Match 'FileMatchesSha256\(filePath, payload\.Sha256\)'
        $script:LauncherProgramContent | Should -Match 'WriteHydrationManifest\(staging, payloadManifest\)'
        $script:LauncherProgramContent | Should -Match 'HydrationManifest\s*=\s*"\.baseline-runtime-manifest\.sha256"'
        $script:LauncherProgramContent | Should -Match 'Path\.Combine\(root, HydrationSentinel\)'
    }

    It 'keeps hydrated payload paths under MAX_PATH on Administrator profiles' {
        $script:LauncherManifestContent | Should -Match 'longPathAware'
        $script:LauncherProgramContent | Should -Match 'RuntimeCacheFolderName\s*=\s*"RC"'
        $script:LauncherProgramContent | Should -Match 'StagingSuffix\s*=\s*"\.s"'

        $runtimeRoot = 'C:\ProgramData\Baseline\RuntimeCache\RC\1.0.0\4\00000000000000000000000000000000.s\000000000000'
        $payloadRoots = @(
            @{ Root = Join-Path $script:RepoRoot 'Bootstrap'; Prefix = 'Bootstrap\' },
            @{ Root = Join-Path $script:RepoRoot 'Module'; Prefix = 'Module\' },
            @{ Root = Join-Path $script:RepoRoot 'Localizations'; Prefix = 'Localizations\' },
            @{ Root = Join-Path $script:RepoRoot 'Assets'; Prefix = 'Assets\' },
            @{ Root = Join-Path $script:RepoRoot 'Completion'; Prefix = 'Completion\' }
        )

        $hydratedPathLengths = foreach ($payloadRoot in $payloadRoots)
        {
            if (-not (Test-Path -LiteralPath $payloadRoot.Root -PathType Container))
            {
                continue
            }

            Get-ChildItem -LiteralPath $payloadRoot.Root -Recurse -File | ForEach-Object {
                $relativePath = $payloadRoot.Prefix + $_.FullName.Substring($payloadRoot.Root.Length + 1)
                (Join-Path $runtimeRoot $relativePath).Length
            }
        }

        $maxHydratedPathLength = $hydratedPathLengths | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

        $maxHydratedPathLength | Should -BeLessOrEqual 259
    }

    It 'restores UTF-8 BOMs only for non-ASCII PowerShell payload files during hydration' {
        $script:LauncherProgramContent | Should -Match 'Utf8Bom'
        $script:LauncherProgramContent | Should -Match 'ShouldPrependUtf8Bom\(target, resourceStream\)'
        $script:LauncherProgramContent | Should -Match 'ResourceStartsWithUtf8Bom'
        $script:LauncherProgramContent | Should -Match 'RequiresPowerShellUtf8Bom'
        $script:LauncherProgramContent | Should -Match 'extension\.Equals\("\.ps1"'
        $script:LauncherProgramContent | Should -Match 'extension\.Equals\("\.psm1"'
        $script:LauncherProgramContent | Should -Match 'extension\.Equals\("\.psd1"'
        $script:LauncherProgramContent | Should -Match 'hasNonAsciiByte'
    }

    It 'keeps the embedded host on the STA launcher thread' {
        $script:LauncherProgramContent | Should -Match 'runspace\.ApartmentState = ApartmentState\.STA;'
        $script:LauncherProgramContent | Should -Match 'runspace\.ThreadOptions = PSThreadOptions\.ReuseThread;'
        $script:LauncherProgramContent | Should -Match 'Environment\.SetEnvironmentVariable\(EmbeddedHostVar, "1", EnvironmentVariableTarget\.Process\);'
        $script:LauncherProgramContent | Should -Match 'BASELINE_INTEGRITY_MODE'
        $script:LauncherProgramContent | Should -Match 'Environment\.SetEnvironmentVariable\(IntegrityModeVar, "Strict", EnvironmentVariableTarget\.Process\);'
        $script:LauncherProgramContent | Should -Match 'PSExecutionPolicyPreference'
        $script:LauncherProgramContent | Should -Match 'InitialSessionState\.CreateDefault\(\)'
        $script:LauncherProgramContent | Should -Match 'initialSessionState\.ExecutionPolicy = Microsoft\.PowerShell\.ExecutionPolicy\.Bypass;'
        $script:LauncherProgramContent | Should -Match 'RunspaceFactory\.CreateRunspace\(host, initialSessionState\)'
    }

    It 'does not apply the default PowerShell timeout to the interactive GUI path' {
        $script:LauncherProgramContent | Should -Match 'private static TimeSpan\? GetPowerShellInvokeTimeout\(string\[\] normalizedArgs\)'
        $script:LauncherProgramContent | Should -Match 'if \(IsGuiPowerShellInvocation\(normalizedArgs\)\)\s*\{\s*return null;'
        $script:LauncherProgramContent | Should -Match 'asyncResult\.AsyncWaitHandle\.WaitOne\(\)'
        $script:LauncherProgramContent | Should -Match 'asyncResult\.AsyncWaitHandle\.WaitOne\(timeout\.Value\)'
        $script:LauncherProgramContent | Should -Match 'BASELINE_POWERSHELL_TIMEOUT_SECONDS'
        $script:LauncherProgramContent | Should -Match '"NoGui"'
        $script:LauncherProgramContent | Should -Match '"Functions"'
        $script:LauncherProgramContent | Should -Match '"Preset"'
        $script:LauncherProgramContent | Should -Match '"ConsoleGui"'
        $script:LauncherProgramContent | Should -Match '"TargetComputer"'
        $script:LauncherProgramContent | Should -Match 'ConsoleGuiArgumentName\s*=\s*"ConsoleGui"'
        $script:LauncherProgramContent | Should -Match 'IsEnabledPowerShellSwitchArgument\(argument, ConsoleGuiArgumentName\)'

        $headlessArgumentBlock = [regex]::Match($script:LauncherProgramContent, 'HeadlessPowerShellArguments\s*=\s*new\[\]\s*\{[\s\S]*?\};').Value
        $headlessArgumentBlock | Should -Not -Match '"ConsoleGui"' -Because 'the interactive console menu should not inherit the default headless workflow timeout'
    }

    It 'rejects duplicate GUI launcher instances before runtime hydration' {
        $script:LauncherProgramContent | Should -Match 'LauncherGuiInstanceMutexPrefix\s*=\s*@"Local\\Baseline-GuiInstance-"'
        $script:LauncherProgramContent | Should -Match 'RequiresLauncherGuiInstanceLock\(normalizedArgs\)'
        $script:LauncherProgramContent | Should -Match 'TryAcquireLauncherGuiInstance\(out launcherGuiInstanceMutex\)'
        $script:LauncherProgramContent | Should -Match 'ReleaseLauncherGuiInstance\(launcherGuiInstanceMutex\)'
        $script:LauncherProgramContent | Should -Match 'GetMutexSafeUserName\(Environment\.UserName\)'
        $script:LauncherProgramContent | Should -Match 'Baseline is already running for this Windows user'

        $lockIndex = $script:LauncherProgramContent.IndexOf('TryAcquireLauncherGuiInstance(out launcherGuiInstanceMutex)')
        $hydrateIndex = $script:LauncherProgramContent.IndexOf('EnsureHydratedRuntime(launcherPath)')
        $lockIndex | Should -BeGreaterThan -1
        $hydrateIndex | Should -BeGreaterThan -1
        $lockIndex | Should -BeLessThan $hydrateIndex
    }

    It 'requires an explicit portable marker or environment flag before portable state is used' {
        $script:LauncherProgramContent | Should -Match 'PortableMarkerFileName\s*=\s*"Baseline\.portable"'
        $script:LauncherProgramContent | Should -Match 'IsExplicitPortableModeRequested\(appBase\)'
        $script:LauncherProgramContent | Should -Match 'Path\.Combine\(appBase, "Data"\)'
        $script:LauncherProgramContent | Should -Match 'File\.Exists\(markerPath\)'
        $script:LauncherProgramContent | Should -Match 'IsTruthyEnvironmentValue\(envValue\)'
        $script:LauncherProgramContent | Should -Match 'Portable mode was requested'
        $script:LauncherProgramContent | Should -Not -Match 'IsCurrentUserInstallLocation'
        $script:LauncherProgramContent | Should -Not -Match 'StartsWith\(localAppData'
    }

    It 'invokes the embedded bootstrap with named command-line parameters preserved' {
        $script:LauncherProgramContent | Should -Match 'powershell\.AddCommand\(launcherScript\)'
        $script:LauncherProgramContent | Should -Match 'BindPowerShellInvocationArguments\(powershell, normalizedArgs\)'
        $script:LauncherProgramContent | Should -Match 'AddBoundPowerShellParameter\(powershell, canonicalName, values\.ToArray\(\)\)'
        $script:LauncherProgramContent | Should -Match 'powershell\.AddParameter\(canonicalName'
        $script:LauncherProgramContent | Should -Match 'powershell\.AddArgument\(argument\)'
        $script:LauncherProgramContent | Should -Not -Match 'BuildPowerShellInvocationScript'
        $script:LauncherProgramContent | Should -Not -Match 'AddScript'
        $script:LauncherProgramContent | Should -Not -Match '@BaselineLauncherArguments'
        $script:LauncherProgramContent | Should -Match 'BootstrapSwitchParameterNames'
        $script:LauncherProgramContent | Should -Match '"ListPresets"'
        $script:LauncherProgramContent | Should -Not -Match 'QuotePowerShellStringLiteral'
        $script:LauncherProgramContent | Should -Match 'TrySplitPowerShellParameterAssignment'
        $script:LauncherProgramContent | Should -Match 'ParseSwitchValue'
    }

    It 'checks for the interactive GUI path before honoring timeout overrides' {
        $guiCheckIndex = $script:LauncherProgramContent.IndexOf('if (IsGuiPowerShellInvocation(normalizedArgs))')
        $envOverrideIndex = $script:LauncherProgramContent.IndexOf('Environment.GetEnvironmentVariable(PowerShellTimeoutSecondsVar)')
        $guiCheckIndex | Should -BeGreaterThan -1
        $envOverrideIndex | Should -BeGreaterThan -1
        $guiCheckIndex | Should -BeLessThan $envOverrideIndex
    }

    It 'targets net48 and references the Windows PowerShell automation assembly' {
        $script:LauncherProjectContent | Should -Match '<TargetFramework>net48</TargetFramework>'
        $script:LauncherProjectContent | Should -Match '<Reference Include="System\.Management\.Automation">'
        $script:LauncherProjectContent | Should -Match 'System\.Management\.Automation\.dll'
        $script:LauncherProjectContent | Should -Match '<PlatformTarget>AnyCPU</PlatformTarget>'
        $script:LauncherProjectContent | Should -Match '<Prefer32Bit>false</Prefer32Bit>'
        $script:LauncherProjectContent | Should -Match '<LangVersion>12\.0</LangVersion>'
        $script:LauncherProjectContent | Should -Not -Match '<LangVersion>latest</LangVersion>'
        $script:LauncherProjectContent | Should -Not -Match 'Microsoft\.PowerShell\.SDK'
    }

    It 'builds the launcher with dotnet build for net48' {
        $manifestRefreshIndex = $script:BuildLauncherContent.IndexOf('New-ModuleIntegrityManifest.ps1')
        $dotnetBuildIndex = $script:BuildLauncherContent.IndexOf("'build'")

        $manifestRefreshIndex | Should -BeGreaterThan -1
        $dotnetBuildIndex | Should -BeGreaterThan -1
        $manifestRefreshIndex | Should -BeLessThan $dotnetBuildIndex
        $script:BuildLauncherContent | Should -Match '''build'''
        $script:BuildLauncherContent | Should -Match '''-f'', ''net48'''
        $script:BuildLauncherContent | Should -Not -Match 'PlatformTarget=x64'
        $script:BuildLauncherContent | Should -Not -Match '0x8664'
        $script:BuildLauncherContent | Should -Match '0x014C'
        $script:BuildLauncherContent | Should -Not -Match 'PublishSingleFile'
        $script:BuildLauncherContent | Should -Not -Match 'SelfContained'
    }
}

Describe 'Embedded host bootstrap flow' {
    It 'avoids console-only title and clear-host calls on the embedded host path' {
        $script:BootstrapContent | Should -Match 'if \(-not \$Script:IsEmbeddedHost\)\s*\{\s*Clear-Host'
        $script:BootstrapContent | Should -Match '\$Script:BaselineWindowTitle = "Baseline \| Utility for \$osName"'
        $script:BootstrapContent | Should -Match 'try\s*\{\s*\$Host\.UI\.RawUI\.WindowTitle = \$Script:BaselineWindowTitle'
        $script:BootstrapContent | Should -Match '\$Script:BootstrapSplash\.Window\.Title = \$Script:BaselineWindowTitle'
    }

    It 'skips later Clear-Host calls when the embedded launcher owns the process' {
        ([regex]::Matches($script:InitialActionsContent, '\$env:BASELINE_EMBEDDED_HOST -ne ''1'' -and \(Test-InteractiveHost\)')).Count | Should -Be 2
    }

    It 'treats startup AppX package probes as non-fatal checks' {
        $script:InitialActionsContent | Should -Match '\[void\]\(Initialize-BaselineWinRtRuntimeDependencies\)'
        $script:InitialActionsContent | Should -Match "Test-BaselineAppxPackagePresence -Name 'MicrosoftWindows\.Client\.CBS'"
        $script:InitialActionsContent | Should -Match 'Bootstrap_FeatureExperiencePackNotApplicable'
        $script:InitialActionsContent | Should -Match "Test-BaselineAppxPackagePresence -Name 'Microsoft\.WindowsStore'"
        $script:InitialActionsContent | Should -Match 'Bootstrap_MicrosoftStoreNotApplicable'
    }

    It 'keeps the headless apply loop on valid splatting syntax' {
        $script:BootstrapContent | Should -Not -Match '@invocation\.NamedArguments'
        $script:BootstrapContent | Should -Match '\$namedArguments\s*=\s*\$invocation\.NamedArguments'
        $script:BootstrapContent | Should -Match '& \$resolvedCmd @namedArguments'
    }

    It 'uses an explicit bootstrap exit helper for embedded host exit codes' {
        $script:BootstrapContent | Should -Match 'function Exit-BaselineBootstrap'
        $script:BootstrapContent | Should -Match '\$Global:LASTEXITCODE = \[int\]\$Code'
        $script:BootstrapContent | Should -Match 'return \(Exit-BaselineBootstrap -Code 2\)'
        $script:BootstrapContent | Should -Not -Match 'if \(\$Script:IsEmbeddedHost\) \{ return \} else \{ exit \}'
    }

    It 'invokes InitialActions through a resolved module command in the embedded runspace' {
        $script:BootstrapContent | Should -Match '\$initialActionsModule = Import-Module -Name \$initialActionsModulePath[\s\S]+-PassThru'
        $script:BootstrapContent | Should -Match '\$Script:InitialActionsCommand = \$initialActionsModule\.ExportedCommands\[''InitialActions''\]'
        $script:BootstrapContent | Should -Match 'function Invoke-BaselineInitialActions'
        $script:BootstrapContent | Should -Match '& \$Script:InitialActionsCommand'
        $script:BootstrapContent | Should -Not -Match 'Invoke-Command -ScriptBlock \{\s*InitialActions\s*\}'
        $script:BootstrapContent | Should -Not -Match '\n\tInitialActions\r?\n'
    }

    It 'routes audited bootstrap abort scenarios through explicit non-zero exit codes' {
        $script:BootstrapContent | Should -Match 'if \(-not \$Script:ModuleRootExists -or \$MissingRequired -or -not \$RegionFiles\)[\s\S]+?return \(Exit-BaselineBootstrap -Code 2\)'
        $script:BootstrapContent | Should -Match 'if \(@\(\$Script:CliIntent\.Errors\)\.Count -gt 0\)[\s\S]+?return \(Exit-BaselineBootstrap -Code 2\)'
        $script:BootstrapContent | Should -Match 'Preset catalog helpers missing[\s\S]+?return \(Exit-BaselineBootstrap -Code 2\)'
        $script:BootstrapContent | Should -Match 'Single-instance helper is missing[\s\S]+?return \(Exit-BaselineBootstrap -Code 2\)'
        $script:BootstrapContent | Should -Match '\$Localization\.UnsupportedPowerShell[\s\S]+?return \(Exit-BaselineBootstrap -Code 2\)'
    }

    It 'keeps apply-profile app catalogs non-enumerated and preserves positional arguments' {
        $script:BootstrapContent | Should -Match 'return ,\$Script:ApplyProfileApplicationsCatalog'
        $script:BootstrapContent | Should -Match '\$applyCatalog = Get-ApplyProfileApplicationsCatalog'
        $script:BootstrapContent | Should -Not -Match '\$applyCatalog = @\(Get-ApplyProfileApplicationsCatalog\)'
        $script:BootstrapContent | Should -Match '\$positionalArguments\s*=\s*\$invocation\.PositionalArguments'
        $script:BootstrapContent | Should -Match '& \$resolvedCmd @namedArguments @positionalArguments'
    }

    It 'reflects apply-profile finalization failures in the final exit accounting' {
        $script:BootstrapContent | Should -Match '\$applyFinalizationErrors = 0'
        $script:BootstrapContent | Should -Match '\$applyFinalizationFailures = \[System\.Collections\.Generic\.List\[string\]\]::new\(\)'
        $script:BootstrapContent | Should -Match '\$applyFinalizationErrors\+\+'
        $script:BootstrapContent | Should -Match 'FinalizationFailures = @\(\$applyFinalizationFailures\)'
        $script:BootstrapContent | Should -Match '\$applyTotal = \[int\]\$applyFunctions\.Count \+ \[int\]\$applyAppActions\.Count \+ \[int\]\$applyFinalizationErrors'
        $script:BootstrapContent | Should -Match '\$applyTotalFailed = \[int\]\$applyErrors \+ \[int\]\$applyAppErrors \+ \[int\]\$applyFinalizationErrors'
        $script:BootstrapContent | Should -Match 'finalizationFailures=\{5\}'
    }

    It 'resolves apply-profile AppActions against catalog metadata without skipping them' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:BootstrapContent, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        $resolverAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Resolve-ApplyProfileAppActionEntry'
        }, $true)
        $resolverAst | Should -Not -BeNullOrEmpty
        Invoke-Expression $resolverAst.Extent.Text

        $catalog = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $catalog['winget:mozilla.firefox'] = [pscustomobject]@{
            Name = 'Mozilla Firefox'
            WinGetId = 'Mozilla.Firefox'
            EntityType = 'application'
            SubCategory = 'Browsers'
            SupportsExecution = $true
        }

        $resolved = Resolve-ApplyProfileAppActionEntry -AppAction ([pscustomobject]@{
            AppId = 'winget:mozilla.firefox'
            Action = 'Install'
        }) -Catalog $catalog

        $resolved | Should -Not -BeNullOrEmpty
        $resolved.Name | Should -Be 'Mozilla Firefox'
        $resolved.WinGetId | Should -Be 'Mozilla.Firefox'
        $resolved.Action | Should -Be 'Install'
        $resolved.SupportsExecution | Should -BeTrue
    }
}

Describe 'Foreground helper process selection' {
    It 'keeps GUI dialogs on the shared no-focus-stealing foreground helper' {
        $script:UwpAppsContent | Should -Match 'Initialize-WpfWindowForeground -Window \$Form'
        ([regex]::Matches($script:SystemWindowsFeaturesContent, 'Initialize-WpfWindowForeground -Window \$Form')).Count | Should -Be 2
        $script:TelemetryServicesContent | Should -Match 'Initialize-WpfWindowForeground -Window \$Form'

        $script:UwpAppsContent | Should -Not -Match 'Get-Process -Name Baseline, powershell, WindowsTerminal'
        $script:SystemWindowsFeaturesContent | Should -Not -Match 'Get-Process -Name Baseline, powershell, WindowsTerminal'
        $script:TelemetryServicesContent | Should -Not -Match 'Get-Process -Name Baseline, powershell, WindowsTerminal'
    }
}
