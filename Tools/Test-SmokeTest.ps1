<#
    .SYNOPSIS
    Smoke-test script for Baseline source validation.

    .DESCRIPTION
    Validates file structure, module loading, manifest integrity, preset
    generation, and extraction safety. By default this only checks
    source-controlled content so it can run in CI directly after checkout.
    Use -RequireReleaseArtifacts to add built-launcher checks before release.

    Cross-platform checks run anywhere. GUI/WPF checks require Windows
    with PowerShell 5.1 Desktop edition.

    .EXAMPLE
    powershell -File .\Tools\Test-SmokeTest.ps1

    .EXAMPLE
    powershell -File .\Tools\Test-SmokeTest.ps1 -IncludeGUI

    .EXAMPLE
    powershell -File .\Tools\Test-SmokeTest.ps1 -RequireReleaseArtifacts
#>

[CmdletBinding()]
param (
    [switch]$IncludeGUI,
    [switch]$RequireReleaseArtifacts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$passed = 0
$failed = 0
$skipped = 0

<#
    .SYNOPSIS
#>

function Write-TestResult
{
    param (
        [string]$Name,
        [ValidateSet('Pass', 'Fail', 'Skip')]
        [string]$Result,
        [string]$Detail = ''
    )

    $symbol = switch ($Result)
    {
        'Pass' { '[PASS]'; $script:passed++ }
        'Fail' { '[FAIL]'; $script:failed++ }
        'Skip' { '[SKIP]'; $script:skipped++ }
    }

    $line = "  $symbol $Name"
    if ($Detail) { $line += " -- $Detail" }
    # Write-Host: intentional - test/tooling console output
    Write-Host $line
}

<#
    .SYNOPSIS
#>
function Import-NewInstallerPackageFunctions
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $moduleName = 'Baseline.NewInstallerPackage.TestImport'
    $existingModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
    if ($existingModule)
    {
        Remove-Module -Name $moduleName -Force
    }

    $moduleSource = (($functions | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine) +
        [Environment]::NewLine +
        'Export-ModuleMember -Function *'

    $tempModuleDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("Baseline-SmokeTest-{0}" -f [System.Guid]::NewGuid().ToString('N'))
    $tempModulePath = Join-Path $tempModuleDirectory "$moduleName.psm1"
    New-Item -ItemType Directory -Path $tempModuleDirectory -Force | Out-Null
    $utf8WithBom = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($tempModulePath, $moduleSource, $utf8WithBom)

    try
    {
        Import-Module -Name $tempModulePath -Force -DisableNameChecking | Out-Null
    }
    finally
    {
        if (Test-Path -LiteralPath $tempModuleDirectory)
        {
            Remove-Item -LiteralPath $tempModuleDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# Section 1: File structure
# ============================================================
Write-Host "`n=== File Structure ===" -ForegroundColor Cyan

$requiredFiles = @(
    'Bootstrap/Baseline.ps1'
    'README.md'
    'CHANGELOG.md'
    'LICENSE'
    'Launcher/Baseline.manifest'
    'Bootstrap/Start-BaselineElevated.ps1'
    'Module/Baseline.psd1'
    'Module/Baseline.psm1'
    'Module/SharedHelpers.psm1'
    'Module/Logging.psm1'
    'Module/GUICommon.psm1'
    'Module/GUIExecution.psm1'
    'Module/Regions/GUI.psm1'
    'Module/GUI/SessionState.ps1'
    'Module/GUI/PreviewBuilders.ps1'
    'Module/GUI/ExecutionSummary.ps1'
    'Module/GUI/PresetManagement.ps1'
    'Module/GUI/GameModeUI.ps1'
    'Module/GUI/GameModeState.ps1'
    'Module/GUI/ExecutionOrchestration.ps1'
    'Module/SharedHelpers/Registry.Helpers.ps1'
    'Module/SharedHelpers/Environment.Helpers.ps1'
    'Module/SharedHelpers/Manifest.Helpers.ps1'
    'Module/SharedHelpers/GameMode.Helpers.ps1'
    'Module/SharedHelpers/ScenarioMode.Helpers.ps1'
    'Module/SharedHelpers/Preset.Helpers.ps1'
    'Module/SharedHelpers/Recovery.Helpers.ps1'
    'Module/SharedHelpers/Lifecycle.Helpers.ps1'
    'Module/SharedHelpers/ErrorHandling.Helpers.ps1'
    'Module/SharedHelpers/PackageManagement.Helpers.ps1'
    'Module/SharedHelpers/AdvancedStartup.Helpers.ps1'
    'Module/SharedHelpers/Taskbar.Helpers.ps1'
    'Module/SharedHelpers/SystemMaintenance.Helpers.ps1'
    'Module/Data/GameMode/GameModeAllowlist.json'
    'Module/Data/GameMode/GameModeAdvanced.json'
    'Module/Data/GameMode/GameModeProfiles.json'
    'Module/Data/Presets/Minimal.json'
    'Module/Data/Presets/Basic.json'
    'Module/Data/Presets/Balanced.json'
    'Module/Data/Presets/Advanced.json'
    'Tools/Validate-ManifestData.ps1'
    'Tools/Generate-PresetFiles.ps1'
    'Tools/New-ReleasePackage.ps1'
    'Tools/New-InstallerPackage.ps1'
    'Tools/Invoke-LifecyclePlaybook.ps1'
    'Tools/New-IncidentReproductionPack.ps1'
    '.github/workflows/ci.yml'
    '.github/workflows/pages.yml'
    'docs/website/index.html'
    'docs/website/sitemap.xml'
    'docs/website/google906d6ac91b49de74.html'
    'dev_docs/Installer-Signing-Policy.md'
)

foreach ($file in $requiredFiles)
{
    $fullPath = Join-Path $repoRoot $file
    if (Test-Path -LiteralPath $fullPath -PathType Leaf)
    {
        Write-TestResult -Name $file -Result Pass
    }
    else
    {
        Write-TestResult -Name $file -Result Fail -Detail 'File missing'
    }
}

# ============================================================
# Section 2: JSON data files load cleanly
# ============================================================
Write-Host "`n=== JSON Data Files ===" -ForegroundColor Cyan

$dataDir = Join-Path $repoRoot 'Module/Data'
$jsonFiles = Get-ChildItem -Path $dataDir -Filter '*.json' -Recurse -File

foreach ($jsonFile in $jsonFiles)
{
    try
    {
        $null = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
        Write-TestResult -Name $jsonFile.Name -Result Pass
    }
    catch
    {
        Write-TestResult -Name $jsonFile.Name -Result Fail -Detail $_.Exception.Message
    }
}

# ============================================================
# Localization QA
# ============================================================
Write-Host "`n=== Localization QA ===" -ForegroundColor Cyan

try
{
    $null = & (Join-Path $repoRoot 'Tools/Test-LocalizationQA.ps1')
    Write-TestResult -Name 'Localization QA' -Result Pass
}
catch
{
    Write-TestResult -Name 'Localization QA' -Result Fail -Detail $_.Exception.Message
}

# ============================================================
# Section 3: PowerShell syntax validation
# ============================================================
Write-Host "`n=== PowerShell Syntax ===" -ForegroundColor Cyan

$psFiles = @(
    Get-ChildItem -Path (Join-Path $repoRoot 'Module') -Filter '*.ps1' -Recurse -File
    Get-ChildItem -Path (Join-Path $repoRoot 'Module') -Filter '*.psm1' -Recurse -File
    Get-ChildItem -Path (Join-Path $repoRoot 'Bootstrap') -Filter '*.ps1' -Recurse -File
)

foreach ($psFile in $psFiles)
{
    try
    {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($psFile.FullName, [ref]$tokens, [ref]$errors)

        if ($errors.Count -eq 0)
        {
            Write-TestResult -Name $psFile.Name -Result Pass
        }
        else
        {
            Write-TestResult -Name $psFile.Name -Result Fail -Detail "$($errors.Count) parse error(s): $($errors[0].Message)"
        }
    }
    catch
    {
        Write-TestResult -Name $psFile.Name -Result Fail -Detail $_.Exception.Message
    }
}

# Windows PowerShell 5.1 treats BOM-less scripts as ANSI. Any non-ASCII bytes in
# such files can turn into mojibake or even parser errors, so guard that directly.
$encodingRoots = @(
    (Join-Path $repoRoot 'Module')
    (Join-Path $repoRoot 'Tools')
    (Join-Path $repoRoot 'Bootstrap')
    (Join-Path $repoRoot 'Completion')
    (Join-Path $repoRoot 'Assets')
    (Join-Path $repoRoot 'Tests')
)

$encodingFiles = @(
    foreach ($root in $encodingRoots)
    {
        if (Test-Path -LiteralPath $root)
        {
            Get-ChildItem -Path $root -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File
        }
    }
)

foreach ($encodingFile in $encodingFiles)
{
    try
    {
        $bytes = [System.IO.File]::ReadAllBytes($encodingFile.FullName)
        $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasNonAsciiBytes = $false

        foreach ($byte in $bytes)
        {
            if ($byte -gt 127)
            {
                $hasNonAsciiBytes = $true
                break
            }
        }

        if ($hasNonAsciiBytes -and -not $hasUtf8Bom)
        {
            Write-TestResult -Name "Encoding: $($encodingFile.Name)" -Result Fail -Detail 'Contains non-ASCII bytes without a UTF-8 BOM (unsafe for Windows PowerShell 5.1)'
        }
        else
        {
            Write-TestResult -Name "Encoding: $($encodingFile.Name)" -Result Pass
        }
    }
    catch
    {
        Write-TestResult -Name "Encoding: $($encodingFile.Name)" -Result Fail -Detail $_.Exception.Message
    }
}

# ============================================================
# ============================================================
Write-Host "`n=== Extraction Safety ===" -ForegroundColor Cyan

$guiPath = Join-Path $repoRoot 'Module/Regions/GUI.psm1'
$guiContent = Get-Content -LiteralPath $guiPath -Raw

# Verify the GUI load block exists in Show-TweakGUI.
$guiModuleFiles = @(
    'GuiContext.ps1'
    'StateTransitions.ps1'
    'ObservableState.ps1'
    'UxPolicy.ps1'
    'UserPreferences.ps1'
    'UIDensity.ps1'
    'SessionState.ps1'
    'TweakAvailability.ps1'
    'PreviewBuilders.ps1'
    'ExecutionSummary.ps1'
    'PresetManagement.ps1'
    'GameModeUI.ps1'
    'GameModeState.ps1'
    'PreflightChecks.ps1'
    'PlanSummaryPanel.ps1'
    'ExecutionOrchestration.ps1'
    'EventInfrastructure.ps1'
    'GuiResponsivenessWatchdog.ps1'
    'StyleManagement.ps1'
    'DeveloperDiagnostics.ps1'
    'ExecutionSummaryDialog.ps1'
    'DiffView.ps1'
    'ComplianceView.ps1'
    'AuditView.ps1'
    'DialogHelpers.ps1'
    'ReviewMode.ps1'
    'AddCustomAppDialog.ps1'
    'StartupManagerDialog.ps1'
    'RemovalPersistenceDialog.ps1'
    'UserFoldersDialog.ps1'
    'TabManagement.ps1'
    'WindowSetup.ps1'
    'ApplyTheme.ps1'
    'StyledControlsSetup.ps1'
    'BuildTweakControls.ps1'
    'UpdatesPanel.ps1'
    'BuildTabContent.ps1'
    'BuildPrimaryTabs.ps1'
    'SearchFilterHandlers.ps1'
    'ActionHandlers.ps1'
)

foreach ($ef in $guiModuleFiles)
{
    if ($guiContent -match [regex]::Escape($ef))
    {
        Write-TestResult -Name "GUI.psm1 dot-sources $ef" -Result Pass
    }
    else
    {
        Write-TestResult -Name "GUI.psm1 dot-sources $ef" -Result Fail -Detail 'Dot-source reference not found'
    }
}

if ($RequireReleaseArtifacts)
{
    $baselineExePath = Join-Path $repoRoot 'Baseline.exe'
    if (Test-Path -LiteralPath $baselineExePath)
    {
        Write-TestResult -Name 'Baseline.exe exists at the repository root' -Result Pass
    }
    else
    {
        Write-TestResult -Name 'Baseline.exe exists at the repository root' -Result Fail -Detail 'Launcher executable not found'
    }
}
else
{
    Write-TestResult -Name 'Baseline.exe exists at the repository root' -Result Skip -Detail 'Use -RequireReleaseArtifacts to validate built launcher artifacts'
}

$legacyRunExePath = Join-Path $repoRoot 'run.exe'
if (-not (Test-Path -LiteralPath $legacyRunExePath))
{
    Write-TestResult -Name 'run.exe has been removed' -Result Pass
}
else
{
    Write-TestResult -Name 'run.exe has been removed' -Result Fail -Detail 'Legacy launcher executable still present'
}

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'run.cmd')))
{
    Write-TestResult -Name 'run.cmd has been removed' -Result Pass
}
else
{
    Write-TestResult -Name 'run.cmd has been removed' -Result Fail -Detail 'Legacy batch launcher still present'
}

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'Baseline.ps1')))
{
    Write-TestResult -Name 'Root Baseline.ps1 has been moved' -Result Pass
}
else
{
    Write-TestResult -Name 'Root Baseline.ps1 has been moved' -Result Fail -Detail 'Legacy root script still present'
}

foreach ($legacySiteFile in @('index.html', 'sitemap.xml', 'google906d6ac91b49de74.html'))
{
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $legacySiteFile)))
    {
        Write-TestResult -Name "Root $legacySiteFile has been moved" -Result Pass
    }
    else
    {
        Write-TestResult -Name "Root $legacySiteFile has been moved" -Result Fail -Detail 'Legacy site asset still present'
    }
}

$launcherSourcePath = Join-Path $repoRoot 'Launcher/Program.cs'
$launcherSourceContent = Get-Content -LiteralPath $launcherSourcePath -Raw
$launcherManifestPath = Join-Path $repoRoot 'Launcher/Baseline.manifest'
$launcherManifestContent = Get-Content -LiteralPath $launcherManifestPath -Raw
$launcherProjectPath = Join-Path $repoRoot 'Launcher/RunLauncher.csproj'
$launcherProjectContent = Get-Content -LiteralPath $launcherProjectPath -Raw

if ($launcherSourceContent -match [regex]::Escape('Bootstrap\Baseline.ps1'))
{
    Write-TestResult -Name 'Baseline.exe launcher source points at Bootstrap\Baseline.ps1' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher source points at Bootstrap\Baseline.ps1' -Result Fail -Detail 'Main script path not found'
}

if ($launcherSourceContent -match [regex]::Escape('RunspaceFactory.CreateRunspace') -and $launcherSourceContent -match [regex]::Escape('PowerShell.Create()') -and $launcherSourceContent -match [regex]::Escape('BaselinePowerShellHost'))
{
    Write-TestResult -Name 'Baseline.exe launcher hosts Windows PowerShell in-process' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher hosts Windows PowerShell in-process' -Result Fail -Detail 'Embedded PowerShell host path not found'
}

if ($launcherSourceContent -match [regex]::Escape('powershell.AddCommand(launcherScript)') -and $launcherSourceContent -match [regex]::Escape('BindPowerShellInvocationArguments(powershell, normalizedArgs)') -and $launcherSourceContent -notmatch 'AddScript')
{
    Write-TestResult -Name 'Baseline.exe launcher binds CLI arguments through PowerShell SDK APIs' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher binds CLI arguments through PowerShell SDK APIs' -Result Fail -Detail 'Expected AddCommand/AddParameter binding without AddScript'
}

if ($launcherSourceContent -match [regex]::Escape('GetRestrictedRuntimeCacheRoot()') -and $launcherSourceContent -match [regex]::Escape('Environment.SpecialFolder.CommonApplicationData') -and $launcherSourceContent -match [regex]::Escape('HydrationManifestMatches(root, payloadManifest)') -and $launcherSourceContent -match [regex]::Escape('FileMatchesSha256(filePath, payload.Sha256)'))
{
    Write-TestResult -Name 'Baseline.exe launcher verifies the hydrated ProgramData runtime cache' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher verifies the hydrated ProgramData runtime cache' -Result Fail -Detail 'Expected ProgramData cache ACL and per-file SHA-256 verification'
}

if ($launcherSourceContent -match [regex]::Escape('ApartmentState.STA') -and $launcherSourceContent -match [regex]::Escape('PSThreadOptions.ReuseThread'))
{
    Write-TestResult -Name 'Baseline.exe launcher runs the embedded host on an STA thread' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher runs the embedded host on an STA thread' -Result Fail -Detail 'Embedded host STA configuration not found'
}

if ($launcherSourceContent -match [regex]::Escape('PSExecutionPolicyPreference') -and $launcherSourceContent -match [regex]::Escape('InitialSessionState.CreateDefault()') -and $launcherSourceContent -match [regex]::Escape('initialSessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;') -and $launcherSourceContent -match [regex]::Escape('RunspaceFactory.CreateRunspace(host, initialSessionState)'))
{
    Write-TestResult -Name 'Baseline.exe launcher bypasses script execution policy for trusted embedded bootstrap' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher bypasses script execution policy for trusted embedded bootstrap' -Result Fail -Detail 'Hosted runspace execution policy bypass not configured'
}

if ($launcherSourceContent -match [regex]::Escape('BASELINE_EMBEDDED_HOST') -and $launcherSourceContent -match [regex]::Escape('BASELINE_LAUNCHER_PATH'))
{
    Write-TestResult -Name 'Baseline.exe launcher forwards embedded-host state' -Result Pass
}
else
{
    Write-TestResult -Name 'Baseline.exe launcher forwards embedded-host state' -Result Fail -Detail 'Embedded host or launcher path env vars missing'
}

if ($launcherManifestContent -match [regex]::Escape('requireAdministrator'))
{
    Write-TestResult -Name 'Launcher manifest requires administrator' -Result Pass
}
else
{
    Write-TestResult -Name 'Launcher manifest requires administrator' -Result Fail -Detail 'requireAdministrator not found'
}

$startBaselineElevatedPath = Join-Path $repoRoot 'Bootstrap/Start-BaselineElevated.ps1'
$startBaselineElevatedContent = Get-Content -LiteralPath $startBaselineElevatedPath -Raw

if ($startBaselineElevatedContent -match [regex]::Escape('Baseline.exe'))
{
    Write-TestResult -Name 'Start-BaselineElevated.ps1 relaunches Baseline.exe' -Result Pass
}
else
{
    Write-TestResult -Name 'Start-BaselineElevated.ps1 relaunches Baseline.exe' -Result Fail -Detail 'Baseline.exe launch command not found'
}

if ($launcherProjectContent -match [regex]::Escape('<ApplicationManifest>Baseline.manifest</ApplicationManifest>'))
{
    Write-TestResult -Name 'Launcher project embeds Baseline.manifest' -Result Pass
}
else
{
    Write-TestResult -Name 'Launcher project embeds Baseline.manifest' -Result Fail -Detail 'ApplicationManifest not configured'
}

if ($launcherProjectContent -notmatch [regex]::Escape('Microsoft.PowerShell.SDK'))
{
    Write-TestResult -Name 'Launcher project does not reference Microsoft.PowerShell.SDK' -Result Pass
}
else
{
    Write-TestResult -Name 'Launcher project does not reference Microsoft.PowerShell.SDK' -Result Fail -Detail 'PowerShell SDK package reference still present'
}

if ($launcherProjectContent -match '<AssemblyName>Baseline</AssemblyName>')
{
    Write-TestResult -Name 'Launcher project builds Baseline.exe' -Result Pass
}
else
{
    Write-TestResult -Name 'Launcher project builds Baseline.exe' -Result Fail -Detail 'Assembly name not set to Baseline'
}

if ($launcherProjectContent -match '<TargetFramework>net48</TargetFramework>' -and $launcherProjectContent -match [regex]::Escape('System.Management.Automation'))
{
    Write-TestResult -Name 'Launcher project targets net48 with the Windows PowerShell automation reference' -Result Pass
}
else
{
    Write-TestResult -Name 'Launcher project targets net48 with the Windows PowerShell automation reference' -Result Fail -Detail 'Expected Windows PowerShell host project settings not found'
}

# The PowerShell parser already validates balanced script blocks and braces, so
# parse success is the correct structural signal here.
$filesToCheck = @($guiPath) + ($guiModuleFiles | ForEach-Object { Join-Path $repoRoot "Module/GUI/$_" })

foreach ($filePath in $filesToCheck)
{
    $fileName = Split-Path $filePath -Leaf
    $parseErrors = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors.Count -eq 0)
    {
        Write-TestResult -Name "Brace balance: $fileName" -Result Pass -Detail 'Parser validation passed'
    }
    else
    {
        $detail = $parseErrors[0].Message
        Write-TestResult -Name "Brace balance: $fileName" -Result Fail -Detail $detail
    }
}

# Verify no bare Remove-ItemProperty -ErrorAction Stop in region modules
$regionDir = Join-Path $repoRoot 'Module/Regions'
$regionFiles = Get-ChildItem -Path $regionDir -Filter '*.psm1' -File

$bareRemoveCount = 0
foreach ($rf in $regionFiles)
{
    $rfContent = Get-Content -LiteralPath $rf.FullName -Raw
    $matches = [regex]::Matches($rfContent, 'Remove-ItemProperty[^|\n]*-ErrorAction\s+Stop')
    $bareRemoveCount += $matches.Count
}

if ($bareRemoveCount -eq 0)
{
    Write-TestResult -Name 'No bare Remove-ItemProperty -ErrorAction Stop in regions' -Result Pass
}
else
{
    Write-TestResult -Name 'No bare Remove-ItemProperty -ErrorAction Stop in regions' -Result Fail -Detail "$bareRemoveCount remaining"
}

# Verify no stale legacy launcher references in active code
$staleRefCount = 0
$activeCodeDirs = @(
    (Join-Path $repoRoot 'Module')
    (Join-Path $repoRoot 'Bootstrap')
    (Join-Path $repoRoot 'Completion')
    (Join-Path $repoRoot 'Assets')
)

foreach ($dir in $activeCodeDirs)
{
    if (Test-Path $dir)
    {
        $codeFiles = Get-ChildItem -Path $dir -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File
        foreach ($cf in $codeFiles)
        {
            $cfContent = Get-Content -LiteralPath $cf.FullName -Raw
            if ($cfContent -match 'legacy launcher')
            {
                $staleRefCount++
            }
        }
    }
}

$entryScript = Get-Content -LiteralPath (Join-Path $repoRoot 'Bootstrap/Baseline.ps1') -Raw
if ($entryScript -match 'legacy launcher') { $staleRefCount++ }

if ($staleRefCount -eq 0)
{
    Write-TestResult -Name 'No stale legacy launcher references in active code' -Result Pass
}
else
{
    Write-TestResult -Name 'No stale legacy launcher references in active code' -Result Fail -Detail "$staleRefCount file(s) with stale references"
}

$initialSetupPath = Join-Path $repoRoot 'Module/Regions/InitialSetup.psm1'
$initialSetupContent = Get-Content -LiteralPath $initialSetupPath -Raw
$packageManagementHelpersPath = Join-Path $repoRoot 'Module/SharedHelpers/PackageManagement.Helpers.ps1'
$packageManagementHelpersContent = Get-Content -LiteralPath $packageManagementHelpersPath -Raw
$winGetMetadataFunctionMatch = [regex]::Match(
    $packageManagementHelpersContent,
    '(?s)function\s+Get-WinGetBootstrapInstallerMetadata\b.*?(?=\r?\nfunction\s|\z)'
)
$winGetMetadataContent = if ($winGetMetadataFunctionMatch.Success) { $winGetMetadataFunctionMatch.Value } else { '' }

if (
    $initialSetupContent -match '\bGet-WinGetBootstrapInstallerMetadata\b' -and
    $winGetMetadataContent -match 'github\.com/.+/releases/download/' -and
    $initialSetupContent -notmatch 'raw\.githubusercontent\.com/.+/master/' -and
    $winGetMetadataContent -notmatch 'raw\.githubusercontent\.com/.+/master/'
)
{
    Write-TestResult -Name 'CheckWinGet uses a pinned installer URL' -Result Pass
}
else
{
    Write-TestResult -Name 'CheckWinGet uses a pinned installer URL' -Result Fail -Detail 'Expected CheckWinGet to source a pinned release URL from the shared helper and avoid master-branch raw URLs'
}

if ($initialSetupContent -match 'Assert-FileHash')
{
    Write-TestResult -Name 'CheckWinGet verifies installer SHA-256' -Result Pass
}
else
{
    Write-TestResult -Name 'CheckWinGet verifies installer SHA-256' -Result Fail -Detail 'Hash verification call not found'
}

$installerScriptPath = Join-Path $repoRoot 'Tools/New-InstallerPackage.ps1'
try
{
    Import-NewInstallerPackageFunctions -ScriptPath $installerScriptPath
    $pathBudget = Get-InstallerPayloadPathBudgetReport `
        -RepoRoot $repoRoot `
        -BaseTempPath 'C:\Users\runneradmin\AppData\Local\Temp' `
        -RootName 'BaselineInstaller_1234567890abcdef1234567890abcdef'

    if ($pathBudget.MaxLength -le 259)
    {
        Write-TestResult -Name 'Installer payload staging stays within MAX_PATH budget' -Result Pass -Detail $pathBudget.MaxLength
    }
    else
    {
        Write-TestResult -Name 'Installer payload staging stays within MAX_PATH budget' -Result Fail -Detail "$($pathBudget.MaxLength): $($pathBudget.MaxRelativePath)"
    }
}
catch
{
    Write-TestResult -Name 'Installer payload staging stays within MAX_PATH budget' -Result Fail -Detail $_.Exception.Message
}

# ============================================================
# Section 5: Manifest validation
# ============================================================
Write-Host "`n=== Manifest Validation ===" -ForegroundColor Cyan

try
{
    $validatorPath = Join-Path $repoRoot 'Tools/Validate-ManifestData.ps1'
    $null = & $validatorPath 2>&1
    Write-TestResult -Name 'Validate-ManifestData.ps1' -Result Pass
}
catch
{
    Write-TestResult -Name 'Validate-ManifestData.ps1' -Result Fail -Detail $_.Exception.Message
}

try
{
    $psd1Path = Join-Path $repoRoot 'Module/Baseline.psd1'
    $manifestResult = Test-ModuleManifest -Path $psd1Path -ErrorAction Stop
    Write-TestResult -Name 'Test-ModuleManifest (Baseline.psd1)' -Result Pass -Detail "Version $($manifestResult.Version)"
}
catch
{
    Write-TestResult -Name 'Test-ModuleManifest (Baseline.psd1)' -Result Fail -Detail $_.Exception.Message
}

# ============================================================
# Section 6: Preset generation
# ============================================================
Write-Host "`n=== Preset Generation ===" -ForegroundColor Cyan

try
{
    $presetTestPath = Join-Path $repoRoot 'Tools/Test-PresetGeneration.ps1'
    if (Test-Path $presetTestPath)
    {
        $null = & $presetTestPath 2>&1
        Write-TestResult -Name 'Test-PresetGeneration.ps1' -Result Pass
    }
    else
    {
        Write-TestResult -Name 'Test-PresetGeneration.ps1' -Result Skip -Detail 'Script not found'
    }
}
catch
{
    Write-TestResult -Name 'Test-PresetGeneration.ps1' -Result Fail -Detail $_.Exception.Message
}

# ============================================================
# Section 7: Preset ladder superset validation
# ============================================================
Write-Host "`n=== Preset Ladder Validation ===" -ForegroundColor Cyan

$presetDir = Join-Path $repoRoot 'Module/Data/Presets'
$presetOrder = @('Minimal', 'Basic', 'Balanced', 'Advanced')
$presetFunctions = @{}

<#
    .SYNOPSIS
#>

function Get-PresetFunctionName
{
    param([object]$Entry)

    if ($Entry -is [string])
    {
        $commandLine = $Entry.Trim()
        if (-not [string]::IsNullOrWhiteSpace($commandLine))
        {
            return ([string]$commandLine -split '\s+', 2)[0].Trim()
        }
    }

    if ($Entry -and $Entry.PSObject.Properties['Function'])
    {
        return [string]$Entry.Function
    }

    return $null
}

# Load function names from each preset
$presetLoadOk = $true
foreach ($presetName in $presetOrder)
{
    $presetFile = Join-Path $presetDir "$presetName.json"
    try
    {
        $presetData = Get-Content -LiteralPath $presetFile -Raw | ConvertFrom-Json
        $presetFunctions[$presetName] = @(
            $presetData.Entries |
                ForEach-Object { Get-PresetFunctionName -Entry $_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        Write-TestResult -Name "Load preset: $presetName" -Result Pass -Detail "$($presetFunctions[$presetName].Count) functions"
    }
    catch
    {
        Write-TestResult -Name "Load preset: $presetName" -Result Fail -Detail $_.Exception.Message
        $presetLoadOk = $false
    }
}

# Validate cumulative ladder: Minimal < Basic < Balanced < Advanced
if ($presetLoadOk)
{
    for ($i = 0; $i -lt $presetOrder.Count - 1; $i++)
    {
        $subset = $presetOrder[$i]
        $superset = $presetOrder[$i + 1]
        $missing = @($presetFunctions[$subset] | Where-Object { $_ -notin $presetFunctions[$superset] })

        if ($missing.Count -eq 0)
        {
            Write-TestResult -Name "Ladder: $subset is subset of $superset" -Result Pass
        }
        else
        {
            Write-TestResult -Name "Ladder: $subset is subset of $superset" -Result Fail -Detail "Missing in ${superset}: $($missing -join ', ')"
        }
    }
}
else
{
    Write-TestResult -Name 'Preset ladder validation' -Result Skip -Detail 'One or more presets failed to load'
}

# ============================================================
# Section 8: GUI smoke tests (Windows only)
# ============================================================
if ($IncludeGUI)
{
    Write-Host "`n=== GUI Smoke Tests (Windows) ===" -ForegroundColor Cyan

    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT')
    {
        # Test: SharedHelpers module loads
        try
        {
            Import-Module (Join-Path $repoRoot 'Module/SharedHelpers.psm1') -Force -ErrorAction Stop
            Write-TestResult -Name 'Import SharedHelpers.psm1' -Result Pass
        }
        catch
        {
            Write-TestResult -Name 'Import SharedHelpers.psm1' -Result Fail -Detail $_.Exception.Message
        }

        # Test: Test-InteractiveHost exists
        if (Get-Command -Name 'Test-InteractiveHost' -ErrorAction SilentlyContinue)
        {
            Write-TestResult -Name 'Test-InteractiveHost available' -Result Pass
        }
        else
        {
            Write-TestResult -Name 'Test-InteractiveHost available' -Result Fail
        }

        # Test: Remove-RegistryValueSafe exists
        if (Get-Command -Name 'Remove-RegistryValueSafe' -ErrorAction SilentlyContinue)
        {
            Write-TestResult -Name 'Remove-RegistryValueSafe available' -Result Pass
        }
        else
        {
            Write-TestResult -Name 'Remove-RegistryValueSafe available' -Result Fail
        }

        # Test: Preset helpers load
        try
        {
            $presetName = ConvertTo-HeadlessPresetName -PresetName 'basic'
            if ($presetName -eq 'Basic')
            {
                Write-TestResult -Name 'ConvertTo-HeadlessPresetName' -Result Pass
            }
            else
            {
                Write-TestResult -Name 'ConvertTo-HeadlessPresetName' -Result Fail -Detail "Got: $presetName"
            }
        }
        catch
        {
            Write-TestResult -Name 'ConvertTo-HeadlessPresetName' -Result Fail -Detail $_.Exception.Message
        }

        # Test: Scenario profile definitions load
        try
        {
            $profiles = Get-ScenarioProfileDefinitions
            if ($profiles.Count -ge 3)
            {
                Write-TestResult -Name 'Get-ScenarioProfileDefinitions' -Result Pass -Detail "$($profiles.Count) profiles"
            }
            else
            {
                Write-TestResult -Name 'Get-ScenarioProfileDefinitions' -Result Fail -Detail "Only $($profiles.Count) profiles"
            }
        }
        catch
        {
            Write-TestResult -Name 'Get-ScenarioProfileDefinitions' -Result Fail -Detail $_.Exception.Message
        }

        # Test: Game Mode profile definitions load
        try
        {
            $gmProfiles = Get-GameModeProfileDefinitions
            if ($gmProfiles.Count -ge 4)
            {
                Write-TestResult -Name 'Get-GameModeProfileDefinitions' -Result Pass -Detail "$($gmProfiles.Count) profiles"
            }
            else
            {
                Write-TestResult -Name 'Get-GameModeProfileDefinitions' -Result Fail -Detail "Only $($gmProfiles.Count) profiles"
            }
        }
        catch
        {
            Write-TestResult -Name 'Get-GameModeProfileDefinitions' -Result Fail -Detail $_.Exception.Message
        }
    }
    else
    {
        Write-TestResult -Name 'GUI smoke tests' -Result Skip -Detail 'Requires Windows'
    }
}
else
{
    Write-Host "`n=== GUI Smoke Tests ===" -ForegroundColor Cyan
    Write-TestResult -Name 'GUI smoke tests' -Result Skip -Detail 'Use -IncludeGUI to enable'
}

# ============================================================
# Section 9: Architectural boundary checks
# ============================================================
Write-Host "`n=== Architectural Boundaries ===" -ForegroundColor Cyan

# Check SharedHelpers do not read GUI $Script: state
$helperDir = Join-Path $repoRoot 'Module/SharedHelpers'
$helperFiles = Get-ChildItem -Path $helperDir -Filter '*.ps1' -File
$safeScriptVarPattern = '^\$Script:(SharedHelpersModuleRoot|SharedHelpersRepoRoot|Cached\w+|ConfigProfileSchema\w*|WinGetAvailabilityState|ChocolateyAvailabilityState)$'
$helperBoundaryViolations = 0

foreach ($hf in $helperFiles)
{
    $hfContent = Get-Content -LiteralPath $hf.FullName -Raw
    $scriptVarMatches = [regex]::Matches($hfContent, '\$Script:\w+')
    foreach ($m in $scriptVarMatches)
    {
        if ($m.Value -notmatch $safeScriptVarPattern)
        {
            $helperBoundaryViolations++
        }
    }
}

if ($helperBoundaryViolations -eq 0)
{
    Write-TestResult -Name 'SharedHelpers: no GUI $Script: state coupling' -Result Pass
}
else
{
    Write-TestResult -Name 'SharedHelpers: no GUI $Script: state coupling' -Result Fail -Detail "$helperBoundaryViolations violation(s)"
}

# Check ExecutionOrchestration.ps1 uses accessors for Game Mode state
$orchPath = Join-Path $repoRoot 'Module/GUI/ExecutionOrchestration.ps1'
$orchContent = Get-Content -LiteralPath $orchPath -Raw
$gatedVars = @('GameModeProfile', 'GameModePlan', 'GameModeDecisionOverrides', 'ExecutionGameModeContext')
$orchAccessorViolations = 0

foreach ($gv in $gatedVars)
{
    $directReads = [regex]::Matches($orchContent, "\`$Script:$gv\b")
    $orchAccessorViolations += $directReads.Count
}

if ($orchAccessorViolations -eq 0)
{
    Write-TestResult -Name 'ExecutionOrchestration: Game Mode state via accessors' -Result Pass
}
else
{
    Write-TestResult -Name 'ExecutionOrchestration: Game Mode state via accessors' -Result Fail -Detail "$orchAccessorViolations direct `$Script: read(s)"
}

# Check GUI.psm1 uses accessors for gated Game Mode state
$guiAccessorViolations = 0

foreach ($gv in $gatedVars)
{
    $directReads = [regex]::Matches($guiContent, "\`$Script:$gv\b")
    $guiAccessorViolations += $directReads.Count
}

if ($guiAccessorViolations -eq 0)
{
    Write-TestResult -Name 'GUI.psm1: Game Mode state via accessors' -Result Pass
}
else
{
    Write-TestResult -Name 'GUI.psm1: Game Mode state via accessors' -Result Fail -Detail "$guiAccessorViolations direct `$Script: read(s)"
}

# ============================================================
# Summary
# ============================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Passed:  $passed"
Write-Host "  Failed:  $failed"
Write-Host "  Skipped: $skipped"
Write-Host ""

if ($failed -gt 0)
{
    Write-Host "  SMOKE TEST FAILED" -ForegroundColor Red
    exit 1
}
else
{
    Write-Host "  ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
}
