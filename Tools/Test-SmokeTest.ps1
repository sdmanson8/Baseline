<#
    .SYNOPSIS
    Smoke-test script for Baseline release validation.

    .DESCRIPTION
    Validates file structure, module loading, manifest integrity, preset
    generation, and extraction safety. Run on Windows before release.

    Cross-platform checks run anywhere. GUI/WPF checks require Windows
    with PowerShell 5.1 Desktop edition.

    .EXAMPLE
    pwsh -File .\Tools\Test-SmokeTest.ps1

    .EXAMPLE
    pwsh -File .\Tools\Test-SmokeTest.ps1 -IncludeGUI
#>

[CmdletBinding()]
param (
    [switch]$IncludeGUI
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$passed = 0
$failed = 0
$skipped = 0

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
    # Write-Host: intentional — test/tooling console output
    Write-Host $line
}

# ============================================================
# Section 1: File structure
# ============================================================
Write-Host "`n=== File Structure ===" -ForegroundColor Cyan

$requiredFiles = @(
    'Baseline.ps1'
    'run.cmd'
    'README.md'
    'CHANGELOG.md'
    'LICENSE'
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
    'docs/ARCHITECTURE.md'
    'Module/SharedHelpers/Registry.Helpers.ps1'
    'Module/SharedHelpers/Environment.Helpers.ps1'
    'Module/SharedHelpers/Manifest.Helpers.ps1'
    'Module/SharedHelpers/GameMode.Helpers.ps1'
    'Module/SharedHelpers/ScenarioMode.Helpers.ps1'
    'Module/SharedHelpers/Preset.Helpers.ps1'
    'Module/SharedHelpers/Recovery.Helpers.ps1'
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
# Section 3: PowerShell syntax validation
# ============================================================
Write-Host "`n=== PowerShell Syntax ===" -ForegroundColor Cyan

$psFiles = @(
    Get-ChildItem -Path (Join-Path $repoRoot 'Module') -Filter '*.ps1' -Recurse -File
    Get-ChildItem -Path (Join-Path $repoRoot 'Module') -Filter '*.psm1' -Recurse -File
    Get-ChildItem -Path (Join-Path $repoRoot 'Bootstrap') -Filter '*.ps1' -Recurse -File
    Get-Item -LiteralPath (Join-Path $repoRoot 'Baseline.ps1')
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
    Get-Item -LiteralPath (Join-Path $repoRoot 'Baseline.ps1')
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
# Section 4: Extraction safety
# ============================================================
Write-Host "`n=== Extraction Safety ===" -ForegroundColor Cyan

$guiPath = Join-Path $repoRoot 'Module/Regions/GUI.psm1'
$guiContent = Get-Content -LiteralPath $guiPath -Raw

# Verify dot-source block exists in Show-TweakGUI
$extractedFiles = @(
    'GuiContext.ps1'
    'ObservableState.ps1'
    'UxPolicy.ps1'
    'ExecutionSummary.ps1'
    'PresetManagement.ps1'
    'GameModeUI.ps1'
    'ThemeManagement.ps1'
    'TweakAnalysis.ps1'
    'ComponentFactory.ps1'
    'FilteringLogic.ps1'
    'SystemScan.ps1'
    'DialogHelpers.ps1'
    'TabManagement.ps1'
)

foreach ($ef in $extractedFiles)
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

$runCmdPath = Join-Path $repoRoot 'run.cmd'
$runCmdContent = Get-Content -LiteralPath $runCmdPath -Raw

if ($runCmdContent -match 'set "LAUNCHER_SCRIPT=%~dp0Bootstrap\\Start-BaselineElevated\.ps1"')
{
    Write-TestResult -Name 'run.cmd defines the elevated launcher helper path' -Result Pass
}
else
{
    Write-TestResult -Name 'run.cmd defines the elevated launcher helper path' -Result Fail -Detail 'Launcher helper definition not found'
}

if ($runCmdContent -match 'powershell\.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LAUNCHER_SCRIPT%" %\*')
{
    Write-TestResult -Name 'run.cmd launches the PowerShell elevation helper directly' -Result Pass
}
else
{
    Write-TestResult -Name 'run.cmd launches the PowerShell elevation helper directly' -Result Fail -Detail 'Expected helper launch command not found'
}

if ($runCmdContent -notmatch 'baseline-launch\.vbs')
{
    Write-TestResult -Name 'run.cmd no longer emits a temporary VBScript launcher' -Result Pass
}
else
{
    Write-TestResult -Name 'run.cmd no longer emits a temporary VBScript launcher' -Result Fail -Detail 'Stale VBScript launcher generation still present'
}

# Verify structural parser integrity in GUI.psm1 and extracted files.
# The PowerShell parser already validates balanced script blocks and braces, so
# parse success is the correct structural signal here.
$filesToCheck = @($guiPath) + ($extractedFiles | ForEach-Object { Join-Path $repoRoot "Module/GUI/$_" })

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

# Verify no stale Win10_11Util references in active code
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
            if ($cfContent -match 'Win10_11Util')
            {
                $staleRefCount++
            }
        }
    }
}

$entryScript = Get-Content -LiteralPath (Join-Path $repoRoot 'Baseline.ps1') -Raw
if ($entryScript -match 'Win10_11Util') { $staleRefCount++ }

if ($staleRefCount -eq 0)
{
    Write-TestResult -Name 'No stale Win10_11Util references in active code' -Result Pass
}
else
{
    Write-TestResult -Name 'No stale Win10_11Util references in active code' -Result Fail -Detail "$staleRefCount file(s) with stale references"
}

$initialSetupPath = Join-Path $repoRoot 'Module/Regions/InitialSetup.psm1'
$initialSetupContent = Get-Content -LiteralPath $initialSetupPath -Raw

if (
    $initialSetupContent -match 'github\.com/asheroto/winget-install/releases/download/' -and
    $initialSetupContent -notmatch 'raw\.githubusercontent\.com/asheroto/winget-install/master/'
)
{
    Write-TestResult -Name 'CheckWinGet uses a pinned installer URL' -Result Pass
}
else
{
    Write-TestResult -Name 'CheckWinGet uses a pinned installer URL' -Result Fail -Detail 'Expected a pinned release download URL and no master-branch raw URL'
}

if ($initialSetupContent -match 'Assert-FileHash')
{
    Write-TestResult -Name 'CheckWinGet verifies installer SHA-256' -Result Pass
}
else
{
    Write-TestResult -Name 'CheckWinGet verifies installer SHA-256' -Result Fail -Detail 'Hash verification call not found'
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
$safeScriptVarPattern = '^\$Script:(SharedHelpersModuleRoot|SharedHelpersRepoRoot|Cached\w+|ConfigProfileSchema\w*)$'
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
