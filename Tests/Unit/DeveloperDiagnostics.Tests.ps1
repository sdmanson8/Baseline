Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:MainWindowContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/MainWindow.xaml')
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/WindowSetup.ps1')
    $script:MenuHandlersContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers/MenuHandlers.ps1')
    $script:ModeStateContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/ModeState.ps1')
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1')
    $script:DeveloperDiagnosticsContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/GUI/DeveloperDiagnostics.ps1')
    $script:RunnerContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Tools/Invoke-GuiDeveloperDiagnostics.ps1')
}

Describe 'Developer Diagnostics menu' {
    It 'adds the Expert Tools submenu and all requested actions' {
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnostics'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsGenerateReport'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsSourceQuality'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsUnitTests'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsGuiComposition'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsOpenLatestReport'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsCopyCommands'
        $script:MainWindowContent | Should -Match 'MenuToolsDeveloperDiagnosticsIntegrationTests'
    }

    It 'captures the menu controls during window setup' {
        $script:WindowSetupContent | Should -Match '\$MenuToolsDeveloperDiagnostics\s+=\s+\$Form\.FindName\("MenuToolsDeveloperDiagnostics"\)'
        $script:WindowSetupContent | Should -Match '\$Script:MenuToolsDeveloperDiagnosticsGenerateReport\s+='
        $script:WindowSetupContent | Should -Match '\$Script:MenuToolsDeveloperDiagnosticsCopyCommands\s+='
    }

    It 'loads the diagnostics module before menu handlers initialize it' {
        $script:GuiRegionContent | Should -Match "DeveloperDiagnostics\.ps1"
        $script:MenuHandlersContent | Should -Match "Initialize-GuiDeveloperDiagnosticsMenu"
        $script:MenuHandlersContent | Should -Match "GuiMenuToolsDeveloperDiagnosticsGenerateReport"
    }

    It 'keeps the menu state synchronized with Safe and Expert mode transitions' {
        $script:ModeStateContent | Should -Match "Update-GuiDeveloperDiagnosticsMenuState"
    }

    It 'keeps the submenu openable while gating runnable actions individually' {
        $script:DeveloperDiagnosticsContent | Should -Match '\$Script:MenuToolsDeveloperDiagnostics\.IsEnabled = \[bool\]\$availability\.ShowMenu'
        $script:DeveloperDiagnosticsContent | Should -Match 'Set-GuiDeveloperDiagnosticsMenuItemState -MenuItem \$item -Enabled \(\[bool\]\$availability\.Enabled\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'MenuToolsDeveloperDiagnosticsCopyCommands -Enabled \(\[bool\]\$availability\.ShowMenu\)'
    }

    It 'opens a launcher dialog from the parent Developer Diagnostics item' {
        $script:DeveloperDiagnosticsContent | Should -Match 'function Show-GuiDeveloperDiagnosticsLauncher'
        $script:DeveloperDiagnosticsContent | Should -Match 'Open-GuiDeveloperDiagnosticsLauncherFromMenu'
        $script:DeveloperDiagnosticsContent | Should -Match 'EventName ''Click'' -Handler \$openDeveloperDiagnosticsLauncher'
        $script:DeveloperDiagnosticsContent | Should -Match 'EventName ''PreviewMouseLeftButtonUp'' -Handler \$openDeveloperDiagnosticsLauncher'
        $script:DeveloperDiagnosticsContent | Should -Match 'EventName ''KeyUp'' -Handler \$openDeveloperDiagnosticsLauncherFromKeyboard'
        $script:DeveloperDiagnosticsContent | Should -Match '\$openLauncherFromMenuScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Open-GuiDeveloperDiagnosticsLauncherFromMenu'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$startDiagnosticsActionForButtons = \$startDiagnosticsActionScript'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$startDiagnosticsActionForButtons -Action ''ExportReport'''
    }

    It 'prompts before installing missing Pester inside the same launcher window' {
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsFunctionCapture'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Set-GuiDeveloperDiagnosticsControlState'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Write-GuiDeveloperDiagnosticsError'
        $script:DeveloperDiagnosticsContent | Should -Match 'LogError \$Message -Scope ''GUI'''
        $script:DeveloperDiagnosticsContent | Should -Not -Match '\$OpenLatestReportButton\.IsEnabled ='
        $script:DeveloperDiagnosticsContent | Should -Not -Match '\$CopyCommandsButton\.IsEnabled ='
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterMissing = & \$testPesterMissingScript -Availability \$availability'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'if \(& \$testPesterMissingScript -Availability \$availability\)[\s\S]{0,120}& \$beginPesterInstall'
        $script:DeveloperDiagnosticsContent | Should -Match 'Start-GuiDeveloperDiagnosticsPesterInstallProcess'
        $script:DeveloperDiagnosticsContent | Should -Match 'BASELINE_DIAGNOSTICS_STEP:'
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Checking PSGallery'"
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Checking PowerShellGet'"
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Installing NuGet provider'"
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Installing Pester'"
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Verifying version'"
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Ready'"
        $script:DeveloperDiagnosticsContent | Should -Match 'function Stop-BaselineDiagnosticsInstall'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Console\]::Error\.WriteLine\(\$Message\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Console\]::Error\.Flush\(\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Environment\]::Exit\(\[int\]\$ExitCode\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'trap'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Environment\]::Exit\(1\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-BaselineDiagnosticsCurrentUserModuleRoot'
        $script:DeveloperDiagnosticsContent | Should -Match 'function ConvertTo-BaselineDiagnosticsVersion'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Select-BaselineDiagnosticsStablePesterPackage'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Invoke-BaselineDiagnosticsWebText'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-BaselineDiagnosticsGalleryPackageVersions'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Select-BaselineDiagnosticsStablePackageVersion'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Test-BaselineDiagnosticsServerOperatingSystem'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Install-BaselineDiagnosticsGalleryModulePackage'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Install-BaselineDiagnosticsPowerShellGetComponents'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Console\]::Out\.WriteLine\(\("\{0\} \{1\} is already installed for the current user\."'
        $script:DeveloperDiagnosticsContent | Should -Match '\[Console\]::Out\.WriteLine\(\("Installing \{0\} \{1\} from PowerShell Gallery for the current user\.\.\."'
        $script:DeveloperDiagnosticsContent | Should -Match 'https://www\.powershellgallery\.com/api/v2/FindPackagesById\(\)\?id=\{0\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'https://www\.powershellgallery\.com/api/v2/package/\{0\}/\{1\}'
        $script:DeveloperDiagnosticsContent | Should -Match "Install-BaselineDiagnosticsGalleryModulePackage -Name 'PackageManagement' -Version '1\.4\.8\.1'"
        $script:DeveloperDiagnosticsContent | Should -Match "Install-BaselineDiagnosticsGalleryModulePackage -Name 'PowerShellGet' -Version '2\.2\.5'"
        $script:DeveloperDiagnosticsContent | Should -Match 'Import-Module -Name \$packageManagementManifest -Force -Global -ErrorAction Stop'
        $script:DeveloperDiagnosticsContent | Should -Match 'Import-Module -Name \$powerShellGetManifest -Force -Global -ErrorAction Stop'
        $script:DeveloperDiagnosticsContent | Should -Match "Write-BaselineDiagnosticsStep 'Installing PowerShellGet'"
        $script:DeveloperDiagnosticsContent | Should -Match '\$ConfirmPreference = ''None'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$PSDefaultParameterValues\[''\*:Confirm''\] = \$false'
        $script:DeveloperDiagnosticsContent | Should -Match "'Get-PackageProvider'"
        $script:DeveloperDiagnosticsContent | Should -Match "'Install-PackageProvider'"
        $script:DeveloperDiagnosticsContent | Should -Match "'Find-Module'"
        $script:DeveloperDiagnosticsContent | Should -Match "'Install-Module'"
        $script:DeveloperDiagnosticsContent | Should -Match 'Installing missing PowerShellGet/PackageManagement components: \{0\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'PowerShellGet/PackageManagement automatic installation failed: \{0\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'required command\(s\) are still missing: \{0\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'Get-Command -Name \$commandName -ErrorAction SilentlyContinue'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'Get-Command -Name \$commandName -CommandType Cmdlet'
        $script:DeveloperDiagnosticsContent | Should -Match '-ExitCode 43'
        $script:DeveloperDiagnosticsContent | Should -Match "Register-PSRepository @registerRepositoryParameters"
        $script:DeveloperDiagnosticsContent | Should -Match "Set-PSRepository @setRepositoryParameters"
        $script:DeveloperDiagnosticsContent | Should -Match "Set-PSRepository is not available; continuing without marking PSGallery trusted"
        $script:DeveloperDiagnosticsContent | Should -Match "Import-PackageProvider @importProviderParameters"
        $script:DeveloperDiagnosticsContent | Should -Match '\$providerParameters\.Confirm = \$false'
        $script:DeveloperDiagnosticsContent | Should -Match '\$providerParameters\.ForceBootstrap = \$true'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installModuleParameters\.AcceptLicense = \$true'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installModuleParameters\.Confirm = \$false'
        $script:DeveloperDiagnosticsContent | Should -Match 'Find-Module -Name Pester -Repository PSGallery -AllVersions'
        $script:DeveloperDiagnosticsContent | Should -Match '\$useServerPesterPackageFeedInstall = Test-BaselineDiagnosticsServerOperatingSystem'
        $script:DeveloperDiagnosticsContent | Should -Match 'if \(\$useServerPesterPackageFeedInstall\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'Windows Server detected; using the PowerShell Gallery package feed directly to avoid legacy PowerShellGet prerelease parsing\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'Select-BaselineDiagnosticsStablePackageVersion -Versions @\(Get-BaselineDiagnosticsGalleryPackageVersions -Name ''Pester''\) -Major 5'
        $script:DeveloperDiagnosticsContent | Should -Match 'Install-BaselineDiagnosticsGalleryModulePackage -Name ''Pester'' -Version \(\[string\]\$latestPesterVersion\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'Select-BaselineDiagnosticsStablePesterPackage -Packages @\(Find-Module -Name Pester -Repository PSGallery -AllVersions -ErrorAction Stop\) -Major 5'
        $script:DeveloperDiagnosticsContent | Should -Match 'Select-BaselineDiagnosticsStablePesterPackage -Packages @\(Find-Module -Name Pester -Repository PSGallery -AllVersions -ErrorAction Stop\) -Major \$recommendedMajor'
        $script:DeveloperDiagnosticsContent | Should -Match 'if \(Test-BaselineDiagnosticsServerOperatingSystem\)'
        $script:DeveloperDiagnosticsContent | Should -Match 'Select-BaselineDiagnosticsStablePackageVersion -Versions @\(Get-BaselineDiagnosticsGalleryPackageVersions -Name ''Pester''\) -Major \$recommendedMajor'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'Where-Object \{ \$_.Version\.Major -eq 5 \}'
        $script:DeveloperDiagnosticsContent | Should -Match 'Install-Module @installModuleParameters'
        $script:DeveloperDiagnosticsContent | Should -Match 'Running Pester install in non-interactive mode; prompts are suppressed\.'
        $script:DeveloperDiagnosticsContent | Should -Match '''-NoProfile'', ''-NonInteractive'', ''-ExecutionPolicy'', ''Bypass'', ''-File'', \$installScriptPath'
        $script:DeveloperDiagnosticsContent | Should -Match '''-NoProfile'', ''-NonInteractive'', ''-ExecutionPolicy'', ''Bypass'', ''-File'', \$checkScriptPath'
        $script:DeveloperDiagnosticsContent | Should -Match '\$Script:GuiDeveloperDiagnosticsPesterMinimumSupportedVersion = \[version\]''5\.5\.0'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$Script:GuiDeveloperDiagnosticsPesterStatusCacheDays = 7'
        $script:DeveloperDiagnosticsContent | Should -Match '\$Script:GuiDeveloperDiagnosticsPesterStatusCheckTimeoutSeconds = 60'
        $script:DeveloperDiagnosticsContent | Should -Match '\$Script:GuiDeveloperDiagnosticsPesterInstallNoOutputWarningSeconds = 60'
        $script:DeveloperDiagnosticsContent | Should -Match 'Supported Pester 5\.x 5\.5\.0 or newer is not available\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'InstallPester_\{0\}\.ps1'
        $script:DeveloperDiagnosticsContent | Should -Match 'CheckPesterStatus_\{0\}\.ps1'
        $script:DeveloperDiagnosticsContent | Should -Match 'Join-GuiDeveloperDiagnosticsArgumentList -Arguments \$arguments'
        $script:DeveloperDiagnosticsContent | Should -Match 'PowerShell Gallery is not reachable'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester installation stopped because PowerShellGet/PackageManagement could not be installed automatically\.'
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallLogText = & \$readTextFileForTimer -Path \(\[string\]\$pesterInstallStateForTimer\.LogPath\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\$powerShellGetBootstrapFailed = \('
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallLogText -match ''PowerShellGet/PackageManagement automatic installation failed:'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallLogText -match ''PowerShellGet/PackageManagement automatic installation completed, but required command\\\(s\\\) are still missing:'''
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsDataDirectory'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsPesterStatusCachePath'
        $script:DeveloperDiagnosticsContent | Should -Match 'PesterStatus\.json'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsInstalledPesterStatus'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsPesterStatusCheckScript'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Start-GuiDeveloperDiagnosticsPesterStatusCheckProcess'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Read-GuiDeveloperDiagnosticsPesterStatusCache'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Write-GuiDeveloperDiagnosticsPesterStatusCache'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsPesterStatusSummary'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Test-GuiDeveloperDiagnosticsPesterStatusCheckDue'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Format-GuiDeveloperDiagnosticsPesterStatusText'
        $script:DeveloperDiagnosticsContent | Should -Match 'function New-GuiDeveloperDiagnosticsPesterInstallCommandContext'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installOutputBox'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installCommandBox = New-Object System\.Windows\.Controls\.TextBox'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressPanel = New-Object System\.Windows\.Controls\.StackPanel'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressText = New-Object System\.Windows\.Controls\.TextBlock'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressBar = New-Object System\.Windows\.Controls\.ProgressBar'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installTrustExpander = New-Object System\.Windows\.Controls\.Expander'
        $script:DeveloperDiagnosticsContent | Should -Match 'Developer Diagnostics installs Pester from the official PowerShell Gallery in a separate Windows PowerShell process\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester is installed outside the GUI process so diagnostics cannot interfere with the running Baseline session\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Get-GuiDeveloperDiagnosticsPesterInstallStatusText'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Add-GuiDeveloperDiagnosticsPesterInstallFileDeltaOutput'
        $script:DeveloperDiagnosticsContent | Should -Match 'Current step: \{0\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'Last output received: \{1\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'No output received for \{0:N0\} seconds\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'The installer may be waiting on PowerShellGet, provider bootstrap, or network activity\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Read-GuiDeveloperDiagnosticsTextFile'
        $script:DeveloperDiagnosticsContent | Should -Match 'function Open-GuiDeveloperDiagnosticsPath'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installPesterButton = New-Object System\.Windows\.Controls\.Button'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installPesterButton\.Content = ''Install Pester'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$viewPesterCommandButton\.Content = ''View Command'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$cancelPesterInstallButton\.Content = ''Cancel'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$openPesterLogButton\.Content = ''Open Log'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$copyPesterLogButton\.Content = ''Copy Log'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$openReportFolderButton\.Content = ''Open Report Folder'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$checkPesterStatusButton\.Content = ''Check Now'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$updatePesterButton\.Content = ''Update Pester'''
        $script:DeveloperDiagnosticsContent | Should -Match 'Checking PSGallery in background'
        $script:DeveloperDiagnosticsContent | Should -Match '\$button\.Add_Click\(\$Click\)'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '\$button\.Add_Click\(\$Click\.GetNewClosure\(\)\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\$copyCommandsForClick = \$copyCommandsScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$statusTextForCopyCommands = \$statusText'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$copyCommandsForClick'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'Copy PowerShell Commands[\s\S]{0,260}& \$copyCommandsScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installPesterButton\.Add_Click\(\$beginPesterInstall\.GetNewClosure\(\)\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\$closeButtonVariant = if \(\$pesterMissing\) \{ ''Secondary'' \} else \{ ''Primary'' \}'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressBar\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressBarForPesterInstall\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressBarForPesterInstall\.IsIndeterminate = \$true'
        $script:DeveloperDiagnosticsContent | Should -Match 'Supported Pester 5\.x 5\.5\.0 or newer is required\. Install Pester to enable diagnostics, or close this dialog\.'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressTextForTimer\.Text = \(& \$getPesterInstallStatusTextForTimer -State \$pesterInstallStateForTimer\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressBarForTimer\.Value = 1'
        $script:DeveloperDiagnosticsContent | Should -Match '\$actionButtons = @\(\)'
        $script:DeveloperDiagnosticsContent | Should -Match '\$actionButton\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        $script:DeveloperDiagnosticsContent | Should -Match '\$actionButton\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:DeveloperDiagnosticsContent | Should -Match '\$newPesterInstallCommandContextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''New-GuiDeveloperDiagnosticsPesterInstallCommandContext'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$getPesterInstallTempDirectoryScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Get-GuiDeveloperDiagnosticsTempDirectory'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$getPesterStatusSummaryScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Get-GuiDeveloperDiagnosticsPesterStatusSummary'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$formatPesterStatusTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Format-GuiDeveloperDiagnosticsPesterStatusText'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$testPesterStatusCheckDueScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Test-GuiDeveloperDiagnosticsPesterStatusCheckDue'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$startPesterStatusCheckScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Start-GuiDeveloperDiagnosticsPesterStatusCheckProcess'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$writePesterStatusCacheScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Write-GuiDeveloperDiagnosticsPesterStatusCache'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$setActionButtonsStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Set-GuiDeveloperDiagnosticsActionButtonsState'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$setControlStateScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Set-GuiDeveloperDiagnosticsControlState'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$updateLauncherAvailabilityViewScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Update-GuiDeveloperDiagnosticsLauncherAvailabilityView'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$addOutputTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Add-GuiDeveloperDiagnosticsOutputText'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$addFileDeltaOutputScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Add-GuiDeveloperDiagnosticsFileDeltaOutput'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$addPesterInstallFileDeltaOutputScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Add-GuiDeveloperDiagnosticsPesterInstallFileDeltaOutput'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$getPesterInstallStatusTextScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Get-GuiDeveloperDiagnosticsPesterInstallStatusText'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$readTextFileScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Read-GuiDeveloperDiagnosticsTextFile'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$openPathScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Open-GuiDeveloperDiagnosticsPath'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$testPesterMissingScript = Get-GuiDeveloperDiagnosticsFunctionCapture -Name ''Test-GuiDeveloperDiagnosticsPesterMissing'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$tempDirectory = & \$getPesterInstallTempDirectoryScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$combinedLogPath = Join-Path \$tempDirectory \(''PesterInstall_\{0\}\.log'''
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallState\.LogPath = \$combinedLogPath'
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallState\.CommandContext = & \$newPesterInstallCommandContextScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallState\.CommandText = \[string\]\$pesterInstallState\.CommandContext\.CommandText'
        $script:DeveloperDiagnosticsContent | Should -Match '-CommandContext \$pesterInstallState\.CommandContext'
        $script:DeveloperDiagnosticsContent | Should -Match 'PowerShell command:`r`n\{0\}`r`nStarted Pester installer process PID \{1\}'
        $script:DeveloperDiagnosticsContent | Should -Match 'TimeoutSeconds = \[int\]600'
        $script:DeveloperDiagnosticsContent | Should -Match 'CommandContext = \$null'
        $script:DeveloperDiagnosticsContent | Should -Match 'CommandText = '''''
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterStatusCheckState = @\{'
        $script:DeveloperDiagnosticsContent | Should -Match 'TimeoutSeconds = \[int\]\$Script:GuiDeveloperDiagnosticsPesterStatusCheckTimeoutSeconds'
        $script:DeveloperDiagnosticsContent | Should -Match '\$beginPesterStatusCheck = \{'
        $script:DeveloperDiagnosticsContent | Should -Match '\$checkPesterStatusButton\.Add_Click\(\{ & \$beginPesterStatusCheck -Manual \$true \}\.GetNewClosure\(\)\)'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$beginPesterStatusCheck -Manual \$false'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$writePesterStatusCacheForTimer -Status \$statusResult'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester status check timed out after \{0\} seconds\.'
        $script:DeveloperDiagnosticsContent | Should -Match '\$pesterInstallStateForTimer = \$pesterInstallState'
        $script:DeveloperDiagnosticsContent | Should -Match '\$addPesterInstallFileDeltaOutputForTimer = \$addPesterInstallFileDeltaOutputScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$updateLauncherAvailabilityViewForTimer = \$updateLauncherAvailabilityViewScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$actionButtonsForTimer = \$actionButtons'
        $script:DeveloperDiagnosticsContent | Should -Match '\$openLatestReportButtonForTimer = \$openLatestReportButton'
        $script:DeveloperDiagnosticsContent | Should -Match '\$copyCommandsButtonForTimer = \$copyCommandsButton'
        $script:DeveloperDiagnosticsContent | Should -Match '\$writeErrorForTimer = \$writeErrorScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$cancelPesterInstallButtonForTimer = \$cancelPesterInstallButton'
        $script:DeveloperDiagnosticsContent | Should -Match '\$stopProcessTreeForTimer = \$stopProcessTreeScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$readTextFileForTimer = \$readTextFileScript'
        $script:DeveloperDiagnosticsContent | Should -Match '\$renderPesterStatusForInstallTimer = \$renderPesterStatus'
        $script:DeveloperDiagnosticsContent | Should -Match '\$statusTextForTimer = \$statusTextForPesterInstall'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installProgressTextForTimer = \$installProgressTextForPesterInstall'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installOutputBoxForTimer = \$installOutputBoxForPesterInstall'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installCommandBoxForPesterInstall = \$installCommandBox'
        $script:DeveloperDiagnosticsContent | Should -Match '\$viewPesterCommandButton\.Add_Click\(\{'
        $script:DeveloperDiagnosticsContent | Should -Match '\$installCommandBoxForFooter\.Text = \[string\]\$pesterInstallStateForFooter\.CommandText'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$setActionButtonsStateScript -Buttons \$actionButtons -Enabled \$false'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$setControlStateScript -Control \$copyCommandsButton -Enabled \$false'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$addPesterInstallFileDeltaOutputForTimer -TextBox \$installOutputBoxForTimer -Path \$stdoutPath -State \$pesterInstallStateForTimer'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$updateLauncherAvailabilityViewForTimer -ActionButtons \$actionButtonsForTimer -OpenLatestReportButton \$openLatestReportButtonForTimer -CopyCommandsButton \$copyCommandsButtonForTimer'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester installation timed out after \{0\} minutes\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'Installer process tree was stopped after timeout\.'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$stopProcessTreeForStatusTimer -Process \$pesterStatusCheckStateForTimer\.Process'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$stopProcessTreeForTimer -Process \$pesterInstallStateForTimer\.Process'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$stopProcessTreeForCancel -Process \$pesterInstallStateForCancel\.Process'
        $script:DeveloperDiagnosticsContent | Should -Match 'Stopping installer process tree\.\.\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'Installation canceled safely\.'
        $script:DeveloperDiagnosticsContent | Should -Match '\[System\.Windows\.Clipboard\]::SetText\(\$logText\)'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '& \$appendInstallOutput'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '& \$appendOutput'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '& \$readPesterFileDelta'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '& \$readDiagnosticsFileDelta'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$testPesterMissingForTimer -Availability \$refreshedAvailability'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester installation process was stopped before completion\. Exit code: \{0\}\.'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$writeErrorForTimer -Message \$failureMessage'
        $script:DeveloperDiagnosticsContent | Should -Match 'Pester installation process was stopped before completion because the Developer Diagnostics window closed\. PID: \{0\}\.'
        $script:DeveloperDiagnosticsContent | Should -Match 'VM only\. Modifies registry, services, and packages\. Recommended only in disposable VMs\.'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'System\.Collections\.Generic\.List\[object\]'
        $script:DeveloperDiagnosticsContent | Should -Not -Match '-EncodedCommand'
        $script:DeveloperDiagnosticsContent | Should -Not -Match 'Show-ThemedDialog[\s\S]*Pester 5\.0 or newer is not available'
    }
}

Describe 'Developer Diagnostics execution contract' {
    It 'gates visibility and enablement on expert mode, Tools, Tests, Pester, and active runs' {
        $script:DeveloperDiagnosticsContent | Should -Match "Test-GuiModeActive -Mode 'Expert'"
        $script:DeveloperDiagnosticsContent | Should -Match 'Join-Path \$repoRoot ''Tools'''
        $script:DeveloperDiagnosticsContent | Should -Match 'Join-Path \$repoRoot ''Tests'''
        $script:DeveloperDiagnosticsContent | Should -Match "Test-GuiDeveloperDiagnosticsPesterAvailable"
        $script:DeveloperDiagnosticsContent | Should -Match "Test-GuiRunInProgress"
    }

    It 'resolves diagnostics from the installed payload root when the GUI runs from the embedded runtime cache' {
        $script:DeveloperDiagnosticsContent | Should -Match "Get-GuiDeveloperDiagnosticsCandidateRoots"
        $script:DeveloperDiagnosticsContent | Should -Match "Test-GuiDeveloperDiagnosticsPayloadRoot"
        $script:DeveloperDiagnosticsContent | Should -Match "BASELINE_LAUNCHER_PATH"
        $script:DeveloperDiagnosticsContent | Should -Match "CurrentDomain\.BaseDirectory"
    }

    It 'launches diagnostics in a child Windows PowerShell process and streams redirected output' {
        $script:DeveloperDiagnosticsContent | Should -Match "Get-GuiDeveloperDiagnosticsPowerShellPath"
        $script:DeveloperDiagnosticsContent | Should -Match "Start-Process -FilePath"
        $script:DeveloperDiagnosticsContent | Should -Match "RedirectStandardOutput"
        $script:DeveloperDiagnosticsContent | Should -Match "Read-GuiDeveloperDiagnosticsFileDelta"
        $script:DeveloperDiagnosticsContent | Should -Match "Stop-GuiDeveloperDiagnosticsProcessTree"
        $script:DeveloperDiagnosticsContent | Should -Match '\$diagnosticsStateForControls = \$state'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$stopProcessTreeScript -Process \$diagnosticsStateForControls\.Process'
        $script:DeveloperDiagnosticsContent | Should -Match '\$getReportSummaryForTimer = \$getReportSummaryScript'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$getReportSummaryForTimer -ReportPath \$reportPath -ExitCode \$exitCode'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$addFileDeltaOutputForTimer -TextBox \$outputBox -Path \$stdoutPath -State \$diagnosticsStateForTimer'
        $script:DeveloperDiagnosticsContent | Should -Match '& \$updateMenuStateForTimer'
        $script:DeveloperDiagnosticsContent | Should -Not -Match "Invoke-Pester"
    }

    It 'writes GUI report artifacts under .artifacts/gui-tests with timestamped names' {
        $script:DeveloperDiagnosticsContent | Should -Match "\.artifacts\\gui-tests"
        $script:DeveloperDiagnosticsContent | Should -Match "TestReport_\{0\}\.json"
        $script:RunnerContent | Should -Match "\.artifacts\\gui-tests"
        $script:RunnerContent | Should -Match "TestReport_\{0\}\.json"
    }

    It 'keeps integration diagnostics hidden unless the source checkout opt-in flag exists' {
        $script:DeveloperDiagnosticsContent | Should -Match "\.baseline-enable-integration-diagnostics"
        $script:DeveloperDiagnosticsContent | Should -Match "VM only"
    }

    It 'runs Pester only from the external diagnostics runner' {
        $script:RunnerContent | Should -Match "Import-Module Pester"
        $script:RunnerContent | Should -Match "Invoke-Pester"
        $script:RunnerContent | Should -Match "Invoke-DiagnosticsPowerShellScript"
    }
}
