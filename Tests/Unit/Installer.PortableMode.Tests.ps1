Set-StrictMode -Version Latest

$script:InstallerTemplates = @(
    @{
        ScriptName = 'Baseline-Setup.iss'
        ScriptPath = Join-Path $PSScriptRoot '../../dist/Baseline-Setup.iss'
    }
)

Describe 'Portable installer registration' {
    It '<ScriptName> declares a setup mutex so concurrent setup windows are rejected' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match '#define\s+MySetupMutex\s+"Baseline-Setup-D5A779F1-8936-4E66-A24D-9A4E43A2A4D9"' -Because "$ScriptName must keep a stable setup-instance mutex"
        $content | Should -Match '(?m)^\s*SetupMutex=\{#MySetupMutex\}\s*$' -Because "$ScriptName must let Inno Setup reject a second setup instance"
    }

    It '<ScriptName> disables uninstall registration for portable mode' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match '(?m)^\s*Uninstallable=IsInstallMode\s*$' -Because "portable mode in $ScriptName must not create an uninstallable entry"
        $content | Should -Match '(?m)^\s*CreateUninstallRegKey=IsInstallMode\s*$' -Because "portable mode in $ScriptName must not register in Apps & Features"
    }

    It '<ScriptName> disables the incompatible mode for the selected setup scope' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match 'procedure ApplyModeAvailability;' -Because "$ScriptName must keep setup scope and install/portable mode mutually exclusive"
        $content | Should -Match 'if IsAdminInstallMode then\s+begin\s+RbInstall\.Enabled := True;\s+RbPortable\.Enabled := False;\s+RbInstall\.Checked := True;\s+RbPortable\.Checked := False;\s+GInstallMode := True;' -Because "$ScriptName all-users setup must make portable unavailable"
        $content | Should -Match 'else\s+begin\s+RbInstall\.Enabled := False;\s+RbPortable\.Enabled := True;\s+RbInstall\.Checked := False;\s+RbPortable\.Checked := True;\s+GInstallMode := False;' -Because "$ScriptName current-user setup must make install unavailable"
        $content | Should -Match 'if IsAdminInstallMode and Assigned\(RbPortable\) and RbPortable\.Checked then' -Because "$ScriptName must reject a stale portable click in all-users setup"
        $content | Should -Match 'else if \(not IsAdminInstallMode\) and Assigned\(RbInstall\) and RbInstall\.Checked then' -Because "$ScriptName must reject a stale install click in current-user setup"
        $content | Should -Match 'ApplyModeAvailability;' -Because "$ScriptName must apply the rule when the mode page is created or shown"
    }

    It '<ScriptName> explains which setup scope enables each disabled mode option' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match 'Choose "Only me" setup mode to enable Portable\.' -Because "$ScriptName should explain why portable is unavailable during all-users setup"
        $content | Should -Match 'Choose "Install for all users" setup mode to enable Install\.' -Because "$ScriptName should explain why install is unavailable during current-user setup"
        $content | Should -Match 'RbInstall\.Hint := InstallHint;' -Because "$ScriptName should attach the install explanation to the disabled install option"
        $content | Should -Match 'RbInstall\.ShowHint := InstallHint <> '''';' -Because "$ScriptName should only show the install hint when install is disabled"
        $content | Should -Match 'RbPortable\.Hint := PortableHint;' -Because "$ScriptName should attach the portable explanation to the disabled portable option"
        $content | Should -Match 'RbPortable\.ShowHint := PortableHint <> '''';' -Because "$ScriptName should only show the portable hint when portable is disabled"
    }

    It '<ScriptName> creates launchable install and portable desktop shortcuts' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match 'Name: "\{group\}\\\{#MyAppName\}".*Filename: "\{app\}\\\{#MyAppExeName\}".*WorkingDir: "\{app\}".*IconFilename: "\{app\}\\\{#MyAppExeName\}"' -Because "$ScriptName Start Menu shortcuts must launch Baseline from the install folder"
        $content | Should -Match 'Name: "\{autodesktop\}\\\{#MyAppName\}".*Filename: "\{app\}\\\{#MyAppExeName\}".*WorkingDir: "\{app\}".*IconFilename: "\{app\}\\\{#MyAppExeName\}"' -Because "$ScriptName desktop shortcuts must launch Baseline from the install folder"
        $content | Should -Match 'Dest := GPortablePath \+ ''\\\{#MyAppExeName\}''' -Because "$ScriptName portable shortcut should target the portable Baseline.exe"
        $content | Should -Match 'if not FileExists\(Dest\) then\s+RaiseException' -Because "$ScriptName must not create a portable shortcut to a missing exe"
        $content | Should -Match "SaveStringToFile\(GPortablePath \+ '\\Baseline\.portable', 'portable=1'#13#10, False\)" -Because "$ScriptName must mark portable mode explicitly for the launcher"
        $content | Should -Match 'Portable marker could not be written' -Because "$ScriptName must fail visibly if portable state cannot be made portable"
        $content | Should -Match "if GDesktop then\s+CreateShellLink\(" -Because "$ScriptName should honor the desktop shortcut selection in portable mode"
        $content | Should -Match "CreateShellLink\(\s*ExpandConstant\('\{autodesktop\}'\) \+ '\\Baseline\.lnk',\s*'Baseline',\s*Dest,\s*'',\s*GPortablePath,\s*Dest," -Because "$ScriptName portable shortcuts need target, working directory, and icon set to the target exe"
    }
}

Describe 'Installer update flow' {
    It '<ScriptName> accepts update-mode launch parameters and relaunches Baseline after install' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match 'GUpdateFlow:\s+Boolean' -Because "$ScriptName must track the update flow separately from normal setup"
        $content | Should -Match 'GUpdateTargetDir:\s+String' -Because "$ScriptName must track the trusted update target directory separately from the relaunch executable"
        $content | Should -Match "GetCommandLineSwitchValue\('BASELINEUPDATE'\)" -Because "$ScriptName must expose an explicit update-mode switch"
        $content | Should -Match "GetCommandLineSwitchValue\('BASELINEUPDATEMODE'\)" -Because "$ScriptName must know whether it is updating install or portable mode"
        $content | Should -Match "GetCommandLineSwitchValue\('BASELINEUPDATETARGETDIR'\)" -Because "$ScriptName must receive the expected update target directory"
        $content | Should -Match "GetCommandLineSwitchValue\('RELAUNCH'\)" -Because "$ScriptName must relaunch the updated Baseline executable"
        $content | Should -Match 'IsBaselineRelaunchPathAllowed' -Because "$ScriptName must validate update relaunch targets before executing them"
        $content | Should -Match 'ExtractFileName\(ExePath\)' -Because "$ScriptName must validate the relaunch basename"
        $content | Should -Match "Rejected update relaunch target" -Because "$ScriptName must reject unexpected relaunch paths"
        $content | Should -Match "ShellExec\('open', ExePath" -Because "$ScriptName must launch Baseline through ShellExecute so the requireAdministrator manifest is honored"
        $content | Should -Match 'Baseline launch target missing' -Because "$ScriptName must log missing launch targets instead of silently doing nothing"
        $content | Should -Match 'Failed to launch Baseline' -Because "$ScriptName must log ShellExecute launch failures"
        $content | Should -Match 'if GUpdateFlow then\s+LaunchBaseline;' -Because "$ScriptName must relaunch after ssPostInstall, including silent update runs"
    }

    It '<ScriptName> skips interactive wizard pages during update mode' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match 'if GUpdateFlow and \(\(PageID = PageLanguage\.ID\).*PageFinish\.ID' -Because "$ScriptName update mode should not stop on setup wizard pages"
    }
}

Describe 'Installer freshness check' {
    It '<ScriptName> performs a lightweight optional setup freshness check before normal setup' -ForEach $script:InstallerTemplates {
        $content = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

        $content | Should -Match '#define\s+MyAppChannel\s+"Beta"' -Because "$ScriptName should carry a setup channel without showing repository URLs"
        $content | Should -Match '#define\s+MyAppChannelToken\s+"beta"' -Because "$ScriptName should stamp a lowercase channel token for the setup filename"
        $content | Should -Match '#define\s+MySetupBaseFilename\s+"Baseline-" \+ MyAppVersion \+ "-" \+ MyAppChannelToken \+ "-setup"' -Because "$ScriptName should emit channel-qualified setup filenames"
        $content | Should -Match '(?m)^\s*OutputBaseFilename=\{#MySetupBaseFilename\}\s*$' -Because "$ScriptName should use the canonical setup filename define"
        $content | Should -Match 'function RunSetupFreshnessCheck: Boolean;' -Because "$ScriptName should keep installer freshness separate from the app updater"
        $content | Should -Match 'GetSetupFreshnessApiUrl' -Because "$ScriptName should query release metadata only"
        $content | Should -Match 'Baseline/releases' -Because "$ScriptName should check the Beta release channel when built from beta metadata"
        $content | Should -Match '\$releaseChannelToken = if \(\$Channel -eq' -Because "$ScriptName should derive the setup freshness asset channel from the selected release channel"
        $content | Should -Match '\[regex\]::Escape\(\$releaseChannelToken\)' -Because "$ScriptName should build a channel-qualified release zip pattern"
        $content | Should -Match '\^Baseline-\\d\+\\\.\\d\+\\\.\\d\+-' -Because "$ScriptName should recognize channel-stamped release zips"
        $content | Should -Match '\$_\.name -match \$assetPattern' -Because "$ScriptName should use the channel-qualified asset pattern"
        $content | Should -Not -Match '\^Baseline-\.\+\\\.zip\$' -Because "$ScriptName should not accept generic release zips"
        $content | Should -Not -Match 'setup-\.\+\\\.exe\|\.\+\\\.zip' -Because "$ScriptName should not use ambiguous setup-or-zip matching"
        $content | Should -Match 'WindowsPowerShell\\v1\.0\\powershell\.exe' -Because "$ScriptName must use Windows PowerShell 5.1 for JSON parsing"
        $content | Should -Match 'ConvertFrom-Json' -Because "$ScriptName should parse GitHub JSON with a structured parser"
        $content | Should -Match 'New-Object System\.Text\.UTF8Encoding\(\$false\)' -Because "$ScriptName runtime script must stay compatible with Windows PowerShell 5.1"
        $content | Should -Not -Match '::new\(' -Because "$ScriptName runtime script must not use PowerShell 7-only syntax"
        $content | Should -Match '\$request\.Timeout = 3000' -Because "$ScriptName should not block offline installs"
        $content | Should -Match 'Status = ''''Skipped'''' \}' -Because "$ScriptName should silently continue when the check cannot complete"
        $content | Should -Match 'A newer Baseline setup is available\.' -Because "$ScriptName should prompt only when a newer installer exists"
        $content | Should -Match 'Continue Anyway' -Because "$ScriptName should allow the current installer to continue"
        $content | Should -Match 'Download Latest Setup' -Because "$ScriptName should let users open the latest release"
        $content | Should -Match 'ShellExecAsOriginalUser\(''open'', ReleaseUrl' -Because "$ScriptName should hand browser downloads back to the unelevated user shell"
        $content | Should -Match '(?s)if Choice = IDNO then\s+begin\s+Result := False;.*ShellExecAsOriginalUser\(''open'', ReleaseUrl' -Because "$ScriptName must cancel setup when the user chooses download, even if opening the browser fails"
        $content | Should -Match 'if GUpdateFlow or GResumeInstallFlow or WizardSilent then' -Because "$ScriptName should not nest the check inside app updates, elevated resume, or silent setup"
        $content | Should -Match 'if \(not RunSetupFreshnessCheck\) then' -Because "$ScriptName should cancel only when the user chooses download/cancel"
    }

    It 'stamps generated setup scripts with the manifest update channel' {
        $scriptPath = Join-Path $PSScriptRoot '../../Tools/New-InstallerPackage.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

        $content | Should -Match '\$updateChannel = ''Stable'''
        $content | Should -Match '\$manifest\.PrivateData\.ContainsKey\(''Prerelease''\)'
        $content | Should -Match '\$updateChannel = ''Beta'''
        $content | Should -Match '\$setupChannelToken = \$updateChannel\.ToLowerInvariant\(\)'
        $content | Should -Match '#define MyAppChannel\\s\+"\[\^"\]\*"'
        $content | Should -Match '#define MyAppChannelToken\\s\+"\[\^"\]\*"'
        $content | Should -Match 'function Get-InstallerSetupFileName'
        $content | Should -Match '\$setupFileName = Get-InstallerSetupFileName -Version \$Version -ChannelToken \$setupChannelToken'
        $content | Should -Match '\$setupHashManifestPath = \$setupPath \+ ''\.sha256\.json'''
        $content | Should -Match 'Get-InstallerFileSha256 -Path \$setupPath'
        $content | Should -Match '\$repoSetupPath = Join-Path \$repoRoot \$setupFileName'
        $content | Should -Match '\$repoSetupHashManifestPath = Join-Path \$repoRoot'
        $content | Should -Match 'HashManifestPath = \$setupHashManifestPath'
        $content | Should -Not -Match '::new\('
    }

    It 'copies release zip artifacts to the repository root' {
        $scriptPath = Join-Path $PSScriptRoot '../../Tools/New-ReleasePackage.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

        $content | Should -Match '\$repoArchivePath = Join-Path \$repoRoot \$resolvedArchiveName'
        $content | Should -Match '\$repoHashManifestPath = Join-Path \$repoRoot'
        $content | Should -Match 'Copy-Item -LiteralPath \$archivePath -Destination \$repoArchivePath -Force'
        $content | Should -Match 'Copy-Item -LiteralPath \$hashManifestPath -Destination \$repoHashManifestPath -Force'
    }

    It 'cleans stale generated release artifacts before forced release packaging' {
        $scriptPath = Join-Path $PSScriptRoot '../../Tools/New-ReleasePackage.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

        $content | Should -Match 'function Get-BaselineGeneratedReleaseArtifact'
        $content | Should -Match 'function Clear-BaselineReleaseOutputDirectory'
        $content | Should -Match '\^Baseline-\.\+-setup\\\.exe\$'
        $content | Should -Not -Match 'Baseline-setup-\.\+'
        $content | Should -Match '\^Baseline-\\d\.\+\\\.zip\$'
        $content | Should -Match '\^Baseline-Setup-\\d\.\+\\\.iss\$'
        $content | Should -Match '(?s)if \(\$Force\).*Clear-BaselineReleaseOutputDirectory -OutputDirectory \$resolvedOutputDirectory'
        $content | Should -Not -Match 'Baseline-Setup-\*\.iss'
    }

    It 'requires explicit opt-in before refreshing installer translations during release packaging' {
        $releaseScriptPath = Join-Path $PSScriptRoot '../../Tools/New-ReleasePackage.ps1'
        $installerScriptPath = Join-Path $PSScriptRoot '../../Tools/New-InstallerPackage.ps1'
        $releaseContent = Get-Content -LiteralPath $releaseScriptPath -Raw -Encoding UTF8
        $installerContent = Get-Content -LiteralPath $installerScriptPath -Raw -Encoding UTF8

        $installerContent | Should -Match '\[switch\]\$RefreshInstallerTranslations'
        $installerContent | Should -Match 'Installer localization cache is missing or invalid'
        $installerContent | Should -Match '-RefreshInstallerTranslations'
        $installerContent | Should -Match 'Invoke-InstallerLocalizationTranslation -Root \$installerLocalizationRoot -RefreshTranslations:\$RefreshInstallerTranslations'
        $releaseContent | Should -Match '\[switch\]\$RefreshInstallerTranslations'
        $releaseContent | Should -Match '\$installerArgs\[''RefreshInstallerTranslations''\] = \$true'
    }
}
