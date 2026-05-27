Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/CliMode.Helpers.ps1'
    . $filePath
    $script:PresetDir = Resolve-Path (Join-Path $PSScriptRoot '../../Module/Data/Presets')
    $script:BootstrapContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Bootstrap/Baseline.ps1')
    $script:ModuleContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Baseline.psm1')
}

Describe 'Resolve-BaselineCliIntent' {
    It 'returns Gui mode when no flags are set' {
        $r = Resolve-BaselineCliIntent -ParamValues @{}
        $r.Mode | Should -Be 'Gui'
        $r.Apply | Should -BeFalse
        $r.Errors.Count | Should -Be 0
    }

    It 'returns ListPresets mode when -ListPresets is set' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ListPresets = $true }
        $r.Mode | Should -Be 'ListPresets'
        $r.NoGui | Should -BeTrue
        $r.Errors.Count | Should -Be 0
    }

    It 'records an error when -ListPresets is combined with -Apply' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ListPresets = $true; Apply = $true }
        $r.Errors.Count | Should -BeGreaterThan 0
    }

    It 'records an error when -ListPresets is combined with -ConfigFile' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ListPresets = $true; ConfigFile = 'C:/x.json' }
        $r.Errors.Count | Should -BeGreaterThan 0
    }

    It 'promotes ConfigFile alone to Apply with a warning' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConfigFile = 'C:/saved.json' }
        $r.Mode | Should -Be 'Headless'
        $r.Apply | Should -BeTrue
        $r.Warnings.Count | Should -BeGreaterThan 0
    }

    It 'promotes Preset alone to Apply with a warning' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ Preset = 'Balanced' }
        $r.Apply | Should -BeTrue
        $r.PresetName | Should -Be 'Balanced'
    }

    It 'does not promote when DryRun is set' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConfigFile = 'C:/x.json'; DryRun = $true }
        $r.Apply | Should -BeFalse
        $r.DryRun | Should -BeTrue
        $r.Warnings.Count | Should -Be 0
    }

    It 'honors explicit -Apply without warning' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConfigFile = 'C:/x.json'; Apply = $true }
        $r.Apply | Should -BeTrue
        $r.Warnings.Count | Should -Be 0
    }

    It 'treats ApplyProfile as Apply' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConfigFile = 'C:/x.json'; ApplyProfile = $true }
        $r.Apply | Should -BeTrue
        $r.Warnings.Count | Should -Be 0
    }

    It 'forces Headless when -NoGui is set with no other flags' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ NoGui = $true }
        $r.Mode | Should -Be 'Headless'
        $r.NoGui | Should -BeTrue
        $r.Apply | Should -BeFalse
    }

    It 'returns ConsoleGui mode without promoting a preset to apply' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConsoleGui = $true; Preset = 'Basic' }
        $r.Mode | Should -Be 'ConsoleGui'
        $r.NoGui | Should -BeTrue
        $r.Apply | Should -BeFalse
        $r.PresetName | Should -Be 'Basic'
        $r.Warnings.Count | Should -Be 0
        $r.Errors.Count | Should -Be 0
    }

    It 'rejects ConsoleGui with unattended apply arguments' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ConsoleGui = $true; ApplyPreset = 'Basic' }
        $r.Mode | Should -Be 'ConsoleGui'
        $r.Errors.Count | Should -BeGreaterThan 0
    }

    It 'falls back to ProfilePath when ConfigFile not given' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ProfilePath = 'C:/legacy.json'; Apply = $true }
        $r.ConfigPath | Should -Be 'C:/legacy.json'
        $r.Apply | Should -BeTrue
    }

    It 'falls back to Preset when ApplyPreset not given' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ Preset = 'Minimal'; Apply = $true }
        $r.PresetName | Should -Be 'Minimal'
    }

    It 'prefers ApplyPreset over Preset when both supplied' {
        $r = Resolve-BaselineCliIntent -ParamValues @{ ApplyPreset = 'Advanced'; Preset = 'Basic'; Apply = $true }
        $r.PresetName | Should -Be 'Advanced'
    }

    It 'tolerates a null ParamValues hashtable' {
        $r = Resolve-BaselineCliIntent -ParamValues $null
        $r.Mode | Should -Be 'Gui'
    }
}

Describe 'Bootstrap CLI intent wiring' {
    It 'normalizes ApplyPreset before preset expansion' {
        $normalizeIndex = $script:BootstrapContent.IndexOf('$Preset = $ApplyPreset')
        $presetExpansionIndex = $script:BootstrapContent.IndexOf('elseif ($Preset)')

        $normalizeIndex | Should -BeGreaterThan 0
        $presetExpansionIndex | Should -BeGreaterThan 0
        $normalizeIndex | Should -BeLessThan $presetExpansionIndex
    }

    It 'promotes local ConfigFile/ProfilePath to ApplyProfile before validation' {
        $promotionIndex = $script:BootstrapContent.IndexOf('$ApplyProfile = $true')
        $validationIndex = $script:BootstrapContent.IndexOf('Specify -ComplianceCheck or -ApplyProfile when using -ProfilePath')

        $promotionIndex | Should -BeGreaterThan 0
        $validationIndex | Should -BeGreaterThan 0
        $promotionIndex | Should -BeLessThan $validationIndex
    }

    It 'exits before showing the bootstrap splash for NoGui without work' {
        $noGuiExitIndex = $script:BootstrapContent.IndexOf('if ($NoGui -and -not $Script:RemoteForcesNoGui -and -not $hasHeadlessWorkIntent)')
        $splashIndex = $script:BootstrapContent.IndexOf("Get-Command -Name 'Show-BootstrapLoadingSplash'")

        $noGuiExitIndex | Should -BeGreaterThan 0
        $splashIndex | Should -BeGreaterThan 0
        $noGuiExitIndex | Should -BeLessThan $splashIndex
    }

    It 'guards the bootstrap splash behind GUI-only intent' {
        $script:BootstrapContent | Should -Match '\$hasHeadlessIntent = \('
        $script:BootstrapContent | Should -Match '\$ComplianceCheck -or \$ScheduledRun -or \$TargetComputer -or \$NoGui'
        $script:BootstrapContent | Should -Match '\$shouldShowBootstrapSplash = -not \$hasHeadlessIntent'
        $script:BootstrapContent | Should -Match 'if \(\$shouldShowBootstrapSplash\)\s*\{[\s\S]*Get-Command -Name ''Show-BootstrapLoadingSplash'''
        $script:BootstrapContent | Should -Match "Get-Command -Name 'Test-BaselineAutoUpdateStartupEnabled'"
        $script:BootstrapContent | Should -Match '\$Script:BootstrapSplash = & \$showBootstrapSplashCommand -StartUpdatesPulse'
    }

    It 'routes ConsoleGui before unattended preset expansion' {
        $script:BootstrapContent | Should -Match '\[switch\]\s*\r?\n\s*\$ConsoleGui'
        $script:BootstrapContent | Should -Match 'ConsoleGui = \[bool\]\$ConsoleGui'
        $script:BootstrapContent | Should -Match '\$hasHeadlessWorkIntent[\s\S]*\$ConsoleGui'

        $consoleBranchIndex = $script:BootstrapContent.IndexOf('$consoleSelection = Show-BaselineConsoleGui')
        $presetExpansionIndex = $script:BootstrapContent.IndexOf('elseif ($Preset)', $consoleBranchIndex)

        $consoleBranchIndex | Should -BeGreaterThan 0
        $presetExpansionIndex | Should -BeGreaterThan 0
        $consoleBranchIndex | Should -BeLessThan $presetExpansionIndex
    }

    It 'forces remote targeting through NoGui' {
        $script:BootstrapContent | Should -Match 'Remote targeting forces -NoGui'
        $script:BootstrapContent | Should -Match '\$Script:RemoteForcesNoGui = \$false'
        $script:BootstrapContent | Should -Match '\$Script:RemoteForcesNoGui = \$true'
        $script:BootstrapContent | Should -Match '\$TargetComputer -and -not \$NoGui'
        $script:BootstrapContent | Should -Match '\$NoGui -and -not \$Script:RemoteForcesNoGui -and -not \$hasHeadlessWorkIntent'
    }

    It 'forces direct PowerShell Remoting sessions through NoGui before splash intent is computed' {
        $script:BootstrapContent | Should -Match 'Test-BaselinePowerShellRemotingSession'
        $script:BootstrapContent | Should -Match 'PowerShell Remoting session forces -NoGui'
        $script:BootstrapContent | Should -Match 'PowerShell Remoting session rejected -ConsoleGui'
        $script:BootstrapContent | Should -Match '\$Script:PowerShellRemotingForcesNoGui = \$true'

        $remotingIndex = $script:BootstrapContent.IndexOf('$isPowerShellRemotingSession')
        $headlessIntentIndex = $script:BootstrapContent.IndexOf('$hasHeadlessWorkIntent = (')

        $remotingIndex | Should -BeGreaterThan 0
        $headlessIntentIndex | Should -BeGreaterThan 0
        $remotingIndex | Should -BeLessThan $headlessIntentIndex
    }

    It 'materializes headless modes as an array before counting them' {
        $script:BootstrapContent | Should -Match '\[string\[\]\]\$headlessModes = @\('
        $script:BootstrapContent | Should -Match '\$headlessModes.Count -gt 1'
        $script:BootstrapContent | Should -Match '\$headlessModes.Count -eq 0'
    }

    It 'requests the updates pulse before the auto-update check runs' {
        $script:BootstrapContent | Should -Match '& \$showBootstrapSplashCommand -StartUpdatesPulse'
        $startPulseIndex = $script:BootstrapContent.IndexOf('& $showBootstrapSplashCommand -StartUpdatesPulse')
        $autoUpdateIndex = $script:BootstrapContent.IndexOf('Invoke-BaselineAutoUpdate -Splash $Script:BootstrapSplash -CurrentVersion $Script:CurrentAppVersion')

        $startPulseIndex | Should -BeGreaterThan 0
        $autoUpdateIndex | Should -BeGreaterThan 0
        $startPulseIndex | Should -BeLessThan $autoUpdateIndex
    }

    It 'hands the startup splash from updates to system checks immediately after auto-update' {
        $script:BootstrapContent | Should -Match 'function Set-BaselineBootstrapSplashChecklistStep'
        $autoUpdateIndex = $script:BootstrapContent.IndexOf('Invoke-BaselineAutoUpdate -Splash $Script:BootstrapSplash -CurrentVersion $Script:CurrentAppVersion')
        $systemStepIndex = $script:BootstrapContent.IndexOf("Set-BaselineBootstrapSplashChecklistStep -StepId 'system' -Status 'in_progress' -SubAction ''", $autoUpdateIndex)
        $initialActionsIndex = $script:BootstrapContent.IndexOf('$initialActionsModulePath = Join-Path $Script:RegionsRoot ''InitialActions.psm1''')

        $autoUpdateIndex | Should -BeGreaterThan 0
        $systemStepIndex | Should -BeGreaterThan 0
        $initialActionsIndex | Should -BeGreaterThan 0
        $autoUpdateIndex | Should -BeLessThan $systemStepIndex
        $systemStepIndex | Should -BeLessThan $initialActionsIndex
    }

    It 'sets explicit log scopes for updater, bootstrap, and GUI phases' {
        $script:BootstrapContent | Should -Match "Set-BaselineLogScope -Scope 'Bootstrap'"
        $script:BootstrapContent | Should -Match "Set-BaselineLogScope -Scope 'Updater'"
        $script:BootstrapContent | Should -Match "Set-BaselineLogScope -Scope 'GUI'"

        $updaterScopeIndex = $script:BootstrapContent.IndexOf("Set-BaselineLogScope -Scope 'Updater'")
        $autoUpdateIndex = $script:BootstrapContent.IndexOf('Invoke-BaselineAutoUpdate -Splash $Script:BootstrapSplash -CurrentVersion $Script:CurrentAppVersion')
        $restoreBootstrapScopeIndex = $script:BootstrapContent.IndexOf("Set-BaselineLogScope -Scope 'Bootstrap'", $autoUpdateIndex)
        $guiScopeIndex = $script:BootstrapContent.IndexOf("Set-BaselineLogScope -Scope 'GUI'")
        $showGuiIndex = $script:BootstrapContent.IndexOf('Show-TweakGUI', $guiScopeIndex)

        $updaterScopeIndex | Should -BeGreaterThan 0
        $autoUpdateIndex | Should -BeGreaterThan 0
        $restoreBootstrapScopeIndex | Should -BeGreaterThan 0
        $guiScopeIndex | Should -BeGreaterThan 0
        $showGuiIndex | Should -BeGreaterThan 0
        $updaterScopeIndex | Should -BeLessThan $autoUpdateIndex
        $autoUpdateIndex | Should -BeLessThan $restoreBootstrapScopeIndex
        $guiScopeIndex | Should -BeLessThan $showGuiIndex
    }

    It 'logs the bootstrap splash as shown only after the splash content rendered' {
        $script:BootstrapContent | Should -Match '\$Script:BootstrapSplash\.WasRendered'
        $script:BootstrapContent | Should -Match "Write-LaunchTrace 'Bootstrap splash shown'"
        $script:BootstrapContent | Should -Match "Write-LaunchTrace 'Bootstrap splash was not shown'"
    }

    It 'primes the updates pulse when startup update settings allow a check' {
        $script:BootstrapContent | Should -Match '\$shouldPrimeUpdatesPulse = \$false'
        $script:BootstrapContent | Should -Match "Get-Command -Name 'Test-BaselineAutoUpdateStartupEnabled'"
        $script:BootstrapContent | Should -Match '\$shouldPrimeUpdatesPulse = \[bool\]\(Test-BaselineAutoUpdateStartupEnabled\)'
        $script:BootstrapContent | Should -Not -Match "Get-Command -Name 'Get-BaselineAutoUpdateThrottleDecision'"
        $script:BootstrapContent | Should -Not -Match '\$shouldPrimeUpdatesPulse = \[bool\]\$autoUpdateThrottleDecision\.ShouldCheck'
        $script:BootstrapContent | Should -Match 'if \(-not \$shouldPrimeUpdatesPulse\)'
        $script:BootstrapContent | Should -Match '\$Script:BootstrapSplash = & \$showBootstrapSplashCommand\s*\r?\n'
        $script:BootstrapContent | Should -Match '\$Script:BootstrapSplash = & \$showBootstrapSplashCommand -StartUpdatesPulse'
    }

    It 'aborts before opening the GUI when the startup splash is user-closed' {
        $script:BootstrapContent | Should -Match 'function Test-BaselineBootstrapSplashAbortRequested'
        $script:BootstrapContent | Should -Match 'function Stop-BaselineIfBootstrapSplashAbortRequested'
        $script:BootstrapContent | Should -Match "Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'after initial checks'"
        $script:BootstrapContent | Should -Match "Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'before Show-TweakGUI'"
        $script:BootstrapContent | Should -Match '\[System\.Environment\]::Exit\(0\)'
        $script:BootstrapContent | Should -Match '\[System\.Diagnostics\.Process\]::GetCurrentProcess\(\)\.Kill\(\)'

        $abortIndex = $script:BootstrapContent.IndexOf("Stop-BaselineIfBootstrapSplashAbortRequested -Phase 'before Show-TweakGUI'")
        $guiOpenIndex = $script:BootstrapContent.IndexOf('Show-TweakGUI', $abortIndex)

        $abortIndex | Should -BeGreaterThan 0
        $guiOpenIndex | Should -BeGreaterThan 0
        $abortIndex | Should -BeLessThan $guiOpenIndex
    }

    It 'fails closed when the GUI single-instance gate cannot run' {
        $script:BootstrapContent | Should -Not -Match 'SingleInstance gate threw, allowing run'
        $script:BootstrapContent | Should -Match 'SingleInstance gate failed'
        $script:BootstrapContent | Should -Match 'Single-instance helper is missing'
        $script:BootstrapContent | Should -Match "Get-Command -Name 'Acquire-BaselineSingleInstance'"
        $script:BootstrapContent | Should -Match '\$Script:SingleInstanceState = & \$singleInstanceAcquireCmd'
        $script:BootstrapContent | Should -Match 'return \(Exit-BaselineBootstrap -Code 2\)'
    }

    It 'sources JSON helpers before localization helpers during bootstrap' {
        $jsonIndex = $script:BootstrapContent.IndexOf("SharedHelpers\Json.Helpers.ps1")
        $localizationIndex = $script:BootstrapContent.IndexOf("SharedHelpers\Localization.Helpers.ps1")

        $jsonIndex | Should -BeGreaterThan 0
        $localizationIndex | Should -BeGreaterThan 0
        $jsonIndex | Should -BeLessThan $localizationIndex
    }

    It 'declares -Include and imports tweak libraries before preset expansion' {
        $script:BootstrapContent | Should -Match '\[string\[\]\]\s*\$Include'

        $includeImportIndex = $script:BootstrapContent.IndexOf('Import-BaselineIncludedTweakLibraries -IncludePaths $Include')
        $presetExpansionIndex = $script:BootstrapContent.IndexOf('# Preset mode expands the requested preset')

        $includeImportIndex | Should -BeGreaterThan 0
        $presetExpansionIndex | Should -BeGreaterThan 0
        $includeImportIndex | Should -BeLessThan $presetExpansionIndex
    }

    It 'routes the headless function-list path through Get-BaselineHeadlessExitCode' {
        $script:BootstrapContent | Should -Match 'headlessExit\s*=\s*Get-BaselineHeadlessExitCode\s+-Total\s+\$headlessTotal'
        $script:BootstrapContent | Should -Match 'Headless function run finished: exitCode='
        $script:BootstrapContent | Should -Match '\$Global:LASTEXITCODE\s*=\s*\[int\]\$headlessExit\.ExitCode'
    }

    It 'wraps PostActions/Errors in a try/finally so the exit code always emits' {
        # Locate the headless function-list block by anchoring to its trace tag,
        # then assert the surrounding finally is what computes the exit code.
        $exitTag = 'Headless function run finished: exitCode='
        $exitTagIndex = $script:BootstrapContent.IndexOf($exitTag)
        $exitTagIndex | Should -BeGreaterThan 0
        $finallyIndex = $script:BootstrapContent.LastIndexOf('finally', $exitTagIndex)
        $tryIndex = $script:BootstrapContent.LastIndexOf('try', $finallyIndex)
        $tryIndex | Should -BeGreaterThan 0
        $finallyIndex | Should -BeGreaterThan $tryIndex
        $finallyIndex | Should -BeLessThan $exitTagIndex
    }

    It 'routes the profile-apply path through Get-BaselineHeadlessExitCode' {
        $script:BootstrapContent | Should -Match 'applyExit\s*=\s*Get-BaselineHeadlessExitCode\s+-Total\s+\$applyTotal'
        $script:BootstrapContent | Should -Match 'Profile apply finished: exitCode='
        $script:BootstrapContent | Should -Match '\$Global:LASTEXITCODE\s*=\s*\[int\]\$applyExit\.ExitCode'
    }

    It 'reports no-tweaks-selected when the resolved profile produced no work' {
        $script:BootstrapContent | Should -Match 'emptyExit\s*=\s*Get-BaselineHeadlessExitCode\s+-Total\s+0'
        $script:BootstrapContent | Should -Match 'Profile apply: no work selected'
    }

    It 'reads dry-run manifest metadata through the manifest field helper' {
        $manifestLookupIndex = $script:BootstrapContent.IndexOf('$manifestEntry = & $lookupCmd -Manifest $dryRunManifest -Function $functionName')
        $riskIndex = $script:BootstrapContent.IndexOf('Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName ''Risk''')
        $categoryIndex = $script:BootstrapContent.IndexOf('Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName ''Category''')
        $restartIndex = $script:BootstrapContent.IndexOf('Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName ''RequiresRestart''')
        $restorableIndex = $script:BootstrapContent.IndexOf('Get-TweakManifestEntryValue -Entry $manifestEntry -FieldName ''Restorable''')

        $manifestLookupIndex | Should -BeGreaterThan 0
        $riskIndex | Should -BeGreaterThan $manifestLookupIndex
        $categoryIndex | Should -BeGreaterThan $manifestLookupIndex
        $restartIndex | Should -BeGreaterThan $manifestLookupIndex
        $restorableIndex | Should -BeGreaterThan $manifestLookupIndex
    }
}

Describe 'Get-BaselineHeadlessExitCode' {
    It 'returns 0 / clean when all targets succeeded' {
        $r = Get-BaselineHeadlessExitCode -Total 5 -Succeeded 5
        $r.ExitCode | Should -Be 0
        $r.Reason | Should -Be 'clean'
    }

    It 'returns 0 / no-tweaks-selected when nothing was applied at all' {
        $r = Get-BaselineHeadlessExitCode
        $r.ExitCode | Should -Be 0
        $r.Reason | Should -Be 'no-tweaks-selected'
    }

    It 'returns 1 / partial when some succeeded and some failed' {
        $r = Get-BaselineHeadlessExitCode -Total 5 -Succeeded 3 -Failed 2
        $r.ExitCode | Should -Be 1
        $r.Reason | Should -Be 'partial'
    }

    It 'returns 1 / all-failed when every target failed' {
        $r = Get-BaselineHeadlessExitCode -Total 3 -Failed 3
        $r.ExitCode | Should -Be 1
        $r.Reason | Should -Be 'all-failed'
    }

    It 'returns 2 / preflight-failed when only preflight blocked the run' {
        $r = Get-BaselineHeadlessExitCode -Total 0 -PreflightFailed 1
        $r.ExitCode | Should -Be 2
        $r.Reason | Should -Be 'preflight-failed'
    }

    It 'treats negative inputs as zero' {
        $r = Get-BaselineHeadlessExitCode -Total -5 -Succeeded -2 -Failed -1
        $r.ExitCode | Should -Be 0
    }

    It 'still reports failure even if a stale PreflightFailed > 0 was passed alongside results' {
        $r = Get-BaselineHeadlessExitCode -Total 5 -Succeeded 4 -Failed 1 -PreflightFailed 1
        $r.ExitCode | Should -Be 1
    }
}

Describe 'Get-BaselinePresetCatalog' {
    It 'throws when the directory does not exist' {
        { Get-BaselinePresetCatalog -PresetDirectory 'C:/does/not/exist/here' } | Should -Throw
    }

    It 'returns the four shipped presets' {
        $catalog = Get-BaselinePresetCatalog -PresetDirectory $script:PresetDir
        $names = @($catalog | ForEach-Object { $_.Name })
        $names | Should -Contain 'Balanced'
        $names | Should -Contain 'Basic'
        $names | Should -Contain 'Advanced'
        $names | Should -Contain 'Minimal'
    }

    It 'reports a non-zero entry count for Balanced' {
        $catalog = Get-BaselinePresetCatalog -PresetDirectory $script:PresetDir
        $balanced = $catalog | Where-Object { $_.Name -eq 'Balanced' } | Select-Object -First 1
        $balanced.EntryCount | Should -BeGreaterThan 0
        $balanced.Error | Should -BeNullOrEmpty
    }

    It 'records parse errors per-entry rather than throwing for the whole catalog' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-presets-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $tempDir 'Good.json') -Value '{"Name":"Good","Entries":["A","B","C"]}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $tempDir 'Bad.json') -Value '{ this is not json' -Encoding UTF8
            $catalog = Get-BaselinePresetCatalog -PresetDirectory $tempDir
            $catalog.Count | Should -Be 2
            ($catalog | Where-Object { $_.Name -eq 'Good' }).EntryCount | Should -Be 3
            ($catalog | Where-Object { $_.Name -eq 'Bad' }).Error | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Format-BaselinePresetCatalog' {
    It 'returns a friendly message for an empty catalog' {
        Format-BaselinePresetCatalog -Catalog @() | Should -Be 'No presets available.'
    }

    It 'tolerates a null catalog' {
        Format-BaselinePresetCatalog -Catalog $null | Should -Be 'No presets available.'
    }

    It 'renders header + one line per preset' {
        $catalog = @(
            [pscustomobject]@{ Name = 'Balanced'; EntryCount = 100; Path = 'x'; Error = $null }
            [pscustomobject]@{ Name = 'Minimal';  EntryCount = 5;   Path = 'x'; Error = $null }
        )
        $rendered = Format-BaselinePresetCatalog -Catalog $catalog
        $rendered | Should -Match 'PRESET'
        $rendered | Should -Match 'TWEAK COUNT'
        $rendered | Should -Match 'Balanced'
        $rendered | Should -Match 'Minimal'
        $rendered | Should -Match '100'
        $rendered | Should -Match '\b5\b'
    }

    It 'renders an error annotation for failing entries' {
        $catalog = @(
            [pscustomobject]@{ Name = 'Bad'; EntryCount = 0; Path = 'x'; Error = 'parse failed' }
        )
        $rendered = Format-BaselinePresetCatalog -Catalog $catalog
        $rendered | Should -Match 'parse failed'
    }
}

Describe 'Resolve-BaselineCliLogPath' {
    BeforeEach {
        $script:DefaultDir = Join-Path $TestDrive 'default'
        [void][System.IO.Directory]::CreateDirectory($script:DefaultDir)
        $script:DefaultFile = '11-22-33 Baseline.log'
        $script:DefaultPath = Join-Path $script:DefaultDir $script:DefaultFile
    }

    It 'returns the default path when the override is empty' {
        $r = Resolve-BaselineCliLogPath -RequestedPath '' -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        $r.ResolvedPath | Should -Be $script:DefaultPath
        $r.UsedDefault | Should -BeTrue
        $r.Warning | Should -BeNullOrEmpty
    }

    It 'returns the default path when the override is whitespace' {
        $r = Resolve-BaselineCliLogPath -RequestedPath "   `t" -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        $r.UsedDefault | Should -BeTrue
        $r.ResolvedPath | Should -Be $script:DefaultPath
    }

    It 'uses an explicit file path verbatim' {
        $target = Join-Path $TestDrive 'custom/run.log'
        $r = Resolve-BaselineCliLogPath -RequestedPath $target -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        $r.ResolvedPath | Should -Be ([System.IO.Path]::GetFullPath($target))
        $r.UsedDefault | Should -BeFalse
        $r.Warning | Should -BeNullOrEmpty
    }

    It 'creates the parent directory when missing' {
        $target = Join-Path $TestDrive 'fresh/dir/run.log'
        $r = Resolve-BaselineCliLogPath -RequestedPath $target -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        [System.IO.Directory]::Exists((Split-Path -Parent $r.ResolvedPath)) | Should -BeTrue
    }

    It 'appends the default filename when given a directory ending in a separator' {
        $dir = Join-Path $TestDrive 'logsdir/'
        $r = Resolve-BaselineCliLogPath -RequestedPath $dir -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        [System.IO.Path]::GetFileName($r.ResolvedPath) | Should -Be $script:DefaultFile
        (Split-Path -Parent $r.ResolvedPath) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'logsdir')))
    }

    It 'appends the default filename when given an existing directory without a trailing separator' {
        $dir = Join-Path $TestDrive 'existingdir'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $r = Resolve-BaselineCliLogPath -RequestedPath $dir -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        [System.IO.Path]::GetFileName($r.ResolvedPath) | Should -Be $script:DefaultFile
    }

    It 'resolves a relative path against the supplied working directory' {
        $cwd = Join-Path $TestDrive 'wd'
        [void][System.IO.Directory]::CreateDirectory($cwd)
        $r = Resolve-BaselineCliLogPath -RequestedPath 'session.log' -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile -WorkingDirectory $cwd
        $r.ResolvedPath | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $cwd 'session.log')))
        $r.UsedDefault | Should -BeFalse
    }

    It 'falls back to the default and surfaces a warning when the path is malformed' {
        $r = Resolve-BaselineCliLogPath -RequestedPath "bad`0name.log" -DefaultPath $script:DefaultPath -DefaultFileName $script:DefaultFile
        $r.UsedDefault | Should -BeTrue
        $r.ResolvedPath | Should -Be $script:DefaultPath
        $r.Warning | Should -Match 'Ignoring -LogPath'
    }
}

Describe 'Bootstrap LogPath wiring' {
    It 'declares the -LogPath parameter on Baseline.ps1' {
        $script:BootstrapContent | Should -Match '\$LogPath'
    }

    It 'invokes Resolve-BaselineCliLogPath when an override is supplied' {
        $script:BootstrapContent | Should -Match 'Resolve-BaselineCliLogPath'
    }

    It 'assigns the resolved path back to $Global:LogFilePath' {
        $script:BootstrapContent | Should -Match '\$Global:LogFilePath\s*=\s*\[string\]\$logResolution\.ResolvedPath'
    }

    It 'uses a session log path helper and stops clearing the log file on launch' {
        $script:BootstrapContent | Should -Match 'New-BaselineSessionLogPath -LogDirectory \$logDirectory -OsName \$osName'
        $script:BootstrapContent | Should -Not -Match 'Set-LogFile -Path \$Global:LogFilePath -Clear'
    }
}

Describe 'Module/Baseline log path wiring' {
    It 'reuses the existing session log path when one is already set' {
        $script:ModuleContent | Should -Match '\$resolvedLogPath = \[string\]\$global:LogFilePath'
        $script:ModuleContent | Should -Match 'if \(\[string\]::IsNullOrWhiteSpace\(\$resolvedLogPath\)\)'
        $script:ModuleContent | Should -Match 'New-BaselineSessionLogPath -LogDirectory \$logDirectory -OsName \$osName'
        $script:ModuleContent | Should -Not -Match 'Set-LogFile -Path \$global:LogFilePath -Clear'
    }
}
