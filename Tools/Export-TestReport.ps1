<#
    .SYNOPSIS
    Runs all test layers and exports a machine-readable JSON report.

    .DESCRIPTION
    Executes smoke tests, Pester unit tests, GUI composition tests, and preset
    validation, then outputs a structured JSON report summarizing results from
    each layer. Designed for CI consumption and badge generation.

    .PARAMETER OutputPath
    Path for the JSON report file. Defaults to Tests/TestReport.json.

    .PARAMETER NoBadge
    Skip writing the shield badge metadata to the report.

    .EXAMPLE
    pwsh -File .\Tools\Export-TestReport.ps1

    .EXAMPLE
    pwsh -File .\Tools\Export-TestReport.ps1 -OutputPath ./artifacts/report.json
#>

[CmdletBinding()]
param (
    [string]$OutputPath,
    [switch]$NoBadge
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath)
{
    $OutputPath = Join-Path $repoRoot 'Tests/TestReport.json'
}

$report = [ordered]@{
    generated    = (Get-Date -Format 'o')
    platform     = [ordered]@{
        os       = [System.Environment]::OSVersion.VersionString
        edition  = $PSVersionTable.PSEdition
        psVersion = $PSVersionTable.PSVersion.ToString()
        hostname = [System.Environment]::MachineName
    }
    layers       = [ordered]@{}
    summary      = [ordered]@{
        totalPassed  = 0
        totalFailed  = 0
        totalSkipped = 0
        overallResult = 'Unknown'
    }
}

# ── Helper: run a script and capture exit code ──
function Invoke-TestLayer
{
    param (
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $layer = [ordered]@{
        name     = $Name
        script   = $ScriptPath
        result   = 'Unknown'
        passed   = 0
        failed   = 0
        skipped  = 0
        duration = $null
        output   = ''
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf))
    {
        $layer.result = 'Skipped'
        $layer.skipped = 1
        $layer.output = "Script not found: $ScriptPath"
        return $layer
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        $rawOutput = & $ScriptPath @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $sw.Stop()

        $layer.duration = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $layer.output = $rawOutput.Trim()

        # Parse [PASS]/[FAIL]/[SKIP] markers from smoke-style output
        $passMatches = ([regex]::Matches($rawOutput, '\[PASS\]')).Count
        $failMatches = ([regex]::Matches($rawOutput, '\[FAIL\]')).Count
        $skipMatches = ([regex]::Matches($rawOutput, '\[SKIP\]')).Count

        $layer.passed = $passMatches
        $layer.failed = $failMatches
        $layer.skipped = $skipMatches

        if ($exitCode -ne 0 -or $failMatches -gt 0)
        {
            $layer.result = 'Failed'
        }
        else
        {
            $layer.result = 'Passed'
        }
    }
    catch
    {
        $sw.Stop()
        $layer.duration = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $layer.result = 'Error'
        $layer.failed = 1
        $layer.output = $_.Exception.Message
    }

    return $layer
}

# ── Helper: run Pester and capture results ──
function Invoke-PesterLayer
{
    param (
        [string]$Name,
        [string]$Path
    )

    $layer = [ordered]@{
        name     = $Name
        script   = $Path
        result   = 'Unknown'
        passed   = 0
        failed   = 0
        skipped  = 0
        duration = $null
        output   = ''
    }

    if (-not (Test-Path -LiteralPath $Path))
    {
        $layer.result = 'Skipped'
        $layer.skipped = 1
        $layer.output = "Path not found: $Path"
        return $layer
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = $Path
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Output.Verbosity = 'None'

        $pesterResult = Invoke-Pester -Configuration $pesterConfig
        $sw.Stop()

        $layer.duration = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $layer.passed = $pesterResult.PassedCount
        $layer.failed = $pesterResult.FailedCount
        $layer.skipped = $pesterResult.SkippedCount
        $layer.output = "Tests: $($pesterResult.TotalCount) | Passed: $($pesterResult.PassedCount) | Failed: $($pesterResult.FailedCount) | Skipped: $($pesterResult.SkippedCount)"

        if ($pesterResult.FailedCount -gt 0)
        {
            $layer.result = 'Failed'
        }
        else
        {
            $layer.result = 'Passed'
        }
    }
    catch
    {
        $sw.Stop()
        $layer.duration = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        $layer.result = 'Error'
        $layer.failed = 1
        $layer.output = $_.Exception.Message
    }

    return $layer
}

# ============================================================
# Layer 1: Smoke tests
# ============================================================
# Write-Host: intentional — test/tooling console output
Write-Host 'Running smoke tests...' -ForegroundColor Cyan
$smokeResult = Invoke-TestLayer -Name 'Smoke Tests' -ScriptPath (Join-Path $repoRoot 'Tools/Test-SmokeTest.ps1')
$report.layers['smoke'] = $smokeResult

# ============================================================
# Layer 2: Unit tests (Pester)
# ============================================================
Write-Host 'Running unit tests...' -ForegroundColor Cyan
$unitResult = Invoke-PesterLayer -Name 'Unit Tests' -Path (Join-Path $repoRoot 'Tests/Unit')
$report.layers['unit'] = $unitResult

# ============================================================
# Layer 3: GUI composition tests (Pester)
# ============================================================
Write-Host 'Running GUI composition tests...' -ForegroundColor Cyan
$compositionResult = Invoke-PesterLayer -Name 'GUI Composition Tests' -Path (Join-Path $repoRoot 'Tests/GUI.Composition.Tests.ps1')
$report.layers['composition'] = $compositionResult

# ============================================================
# Layer 4: Preset generation validation
# ============================================================
Write-Host 'Running preset validation...' -ForegroundColor Cyan
$presetResult = Invoke-TestLayer -Name 'Preset Validation' -ScriptPath (Join-Path $repoRoot 'Tools/Test-PresetGeneration.ps1')
$report.layers['preset'] = $presetResult

# ============================================================
# Aggregate summary
# ============================================================
$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0

foreach ($layerKey in $report.layers.Keys)
{
    $l = $report.layers[$layerKey]
    $totalPassed  += $l.passed
    $totalFailed  += $l.failed
    $totalSkipped += $l.skipped
}

$report.summary.totalPassed  = $totalPassed
$report.summary.totalFailed  = $totalFailed
$report.summary.totalSkipped = $totalSkipped
$report.summary.overallResult = if ($totalFailed -gt 0) { 'Failed' } else { 'Passed' }

# ============================================================
# Badge metadata (shields.io compatible)
# ============================================================
if (-not $NoBadge)
{
    $badgeColor = if ($totalFailed -gt 0) { 'red' } else { 'brightgreen' }
    $badgeMessage = if ($totalFailed -gt 0)
    {
        "$totalFailed failed"
    }
    else
    {
        "$totalPassed passed"
    }

    $report['badge'] = [ordered]@{
        schemaVersion = 1
        label         = 'tests'
        message       = $badgeMessage
        color         = $badgeColor
    }
}

# ============================================================
# Write report
# ============================================================
$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir))
{
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host ''
Write-Host "=== Test Report ===" -ForegroundColor Cyan
Write-Host "  Passed:  $totalPassed"
Write-Host "  Failed:  $totalFailed"
Write-Host "  Skipped: $totalSkipped"
Write-Host "  Result:  $($report.summary.overallResult)"
Write-Host "  Report:  $OutputPath"
Write-Host ''

if ($totalFailed -gt 0)
{
    Write-Host '  REPORT: FAILURES DETECTED' -ForegroundColor Red
    exit 1
}
else
{
    Write-Host '  REPORT: ALL LAYERS PASSED' -ForegroundColor Green
    exit 0
}
