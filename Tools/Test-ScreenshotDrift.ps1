<#
    .SYNOPSIS
    Validates screenshot manifest freshness and flags potentially stale screenshots.

    .DESCRIPTION
    Maintains a screenshot manifest (Tests/Fixtures/ScreenshotManifest.json) that
    tracks each screenshot reference in the README: its URL, description, associated
    source files, and last-verified date.

    The tool flags screenshots as potentially stale when:
    - A referenced URL is missing from the manifest
    - The associated source files have been modified since the screenshot was verified
    - The last-verified date exceeds the staleness threshold (default 90 days)

    .PARAMETER ManifestPath
    Path to the screenshot manifest JSON. Defaults to Tests/Fixtures/ScreenshotManifest.json.

    .PARAMETER StaleDays
    Number of days before a screenshot is considered potentially stale. Default: 90.

    .PARAMETER UpdateManifest
    If set, regenerates the manifest from README screenshot references and marks
    all entries as verified today. Use after capturing fresh screenshots.

    .EXAMPLE
    pwsh -File .\Tools\Test-ScreenshotDrift.ps1

    .EXAMPLE
    pwsh -File .\Tools\Test-ScreenshotDrift.ps1 -UpdateManifest

    .EXAMPLE
    pwsh -File .\Tools\Test-ScreenshotDrift.ps1 -StaleDays 30
#>

[CmdletBinding()]
param (
    [string]$ManifestPath,
    [int]$StaleDays = 90,
    [switch]$UpdateManifest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $ManifestPath)
{
    $ManifestPath = Join-Path $repoRoot 'Tests/Fixtures/ScreenshotManifest.json'
}

$readmePath = Join-Path $repoRoot 'README.md'
$passed = 0
$failed = 0
$warned = 0

function Write-DriftResult
{
    param (
        [string]$Name,
        [ValidateSet('Pass', 'Fail', 'Warn')]
        [string]$Result,
        [string]$Detail = ''
    )

    $symbol = switch ($Result)
    {
        'Pass' { '[PASS]'; $script:passed++ }
        'Fail' { '[FAIL]'; $script:failed++ }
        'Warn' { '[WARN]'; $script:warned++ }
    }

    $line = "  $symbol $Name"
    if ($Detail) { $line += " -- $Detail" }
    # Write-Host: intentional — test/tooling console output
    Write-Host $line
}

# ============================================================
# Parse screenshot references from README
# ============================================================
# Write-Host: intentional — test/tooling console output
Write-Host "`n=== Screenshot Drift Check ===" -ForegroundColor Cyan

$readmeContent = Get-Content -LiteralPath $readmePath -Raw
$imgPattern = '<img\s+src="([^"]+)"[^>]*alt="([^"]*)"'
$imgMatches = [regex]::Matches($readmeContent, $imgPattern)

$readmeScreenshots = @()
foreach ($match in $imgMatches)
{
    $readmeScreenshots += [ordered]@{
        url         = $match.Groups[1].Value
        description = $match.Groups[2].Value
    }
}

Write-DriftResult -Name "README screenshot references found" -Result Pass -Detail "$($readmeScreenshots.Count) screenshot(s)"

# ============================================================
# Default source file associations for known screenshots
# ============================================================
$defaultAssociations = @{
    'Windows 10 GUI'              = @('Module/Regions/GUI.psm1', 'Module/GUI/StyleManagement.ps1', 'Module/GUI/ThemeManagement.ps1')
    'Windows 10 Non-Interactive'  = @('Baseline.ps1', 'Module/Baseline.psm1')
    'Windows 11 GUI'              = @('Module/Regions/GUI.psm1', 'Module/GUI/StyleManagement.ps1', 'Module/GUI/ThemeManagement.ps1')
    'Windows 11 Non-Interactive'  = @('Baseline.ps1', 'Module/Baseline.psm1')
    'Baseline GUI hero screenshot' = @('Module/Regions/GUI.psm1', 'Module/GUI/StyleManagement.ps1')
}

# ============================================================
# Update manifest mode
# ============================================================
if ($UpdateManifest)
{
    $manifest = [ordered]@{
        generatedAt  = (Get-Date -Format 'o')
        staleDays    = $StaleDays
        screenshots  = @()
    }

    foreach ($img in $readmeScreenshots)
    {
        $sources = @()
        if ($defaultAssociations.ContainsKey($img.description))
        {
            $sources = $defaultAssociations[$img.description]
        }

        $manifest.screenshots += [ordered]@{
            url            = $img.url
            description    = $img.description
            lastVerified   = (Get-Date -Format 'yyyy-MM-dd')
            associatedFiles = $sources
        }
    }

    $manifestDir = Split-Path $ManifestPath -Parent
    if ($manifestDir -and -not (Test-Path -LiteralPath $manifestDir))
    {
        New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    Write-DriftResult -Name "Manifest updated" -Result Pass -Detail "$($manifest.screenshots.Count) entries written to $ManifestPath"

    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    Write-Host "  Manifest regenerated with $($manifest.screenshots.Count) screenshot(s)"
    Write-Host "  All entries marked as verified: $(Get-Date -Format 'yyyy-MM-dd')"
    exit 0
}

# ============================================================
# Validation mode (default)
# ============================================================
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf))
{
    Write-DriftResult -Name "Screenshot manifest exists" -Result Fail -Detail "Not found at $ManifestPath. Run with -UpdateManifest to create it."

    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    Write-Host "  Passed: $passed"
    Write-Host "  Failed: $failed"
    Write-Host "  Warned: $warned"
    exit 1
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
Write-DriftResult -Name "Screenshot manifest loaded" -Result Pass -Detail "$($manifest.screenshots.Count) entries"

# Check: every README screenshot URL is in the manifest
$manifestUrls = @($manifest.screenshots | ForEach-Object { $_.url })
foreach ($img in $readmeScreenshots)
{
    if ($img.url -in $manifestUrls)
    {
        Write-DriftResult -Name "Tracked: $($img.description)" -Result Pass
    }
    else
    {
        Write-DriftResult -Name "Untracked: $($img.description)" -Result Fail -Detail "URL not in manifest — run -UpdateManifest"
    }
}

# Check: staleness threshold
$today = Get-Date
foreach ($entry in $manifest.screenshots)
{
    $verified = [datetime]::Parse($entry.lastVerified)
    $age = ($today - $verified).Days

    if ($age -gt $StaleDays)
    {
        Write-DriftResult -Name "Stale: $($entry.description)" -Result Warn -Detail "Last verified $age days ago (threshold: $StaleDays)"
    }
    else
    {
        Write-DriftResult -Name "Fresh: $($entry.description)" -Result Pass -Detail "Verified $age day(s) ago"
    }
}

# Check: associated source file modification dates
foreach ($entry in $manifest.screenshots)
{
    if (-not $entry.associatedFiles -or $entry.associatedFiles.Count -eq 0) { continue }

    $verified = [datetime]::Parse($entry.lastVerified)
    $modifiedAfter = @()

    foreach ($relPath in $entry.associatedFiles)
    {
        $fullPath = Join-Path $repoRoot $relPath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf)
        {
            $lastWrite = (Get-Item -LiteralPath $fullPath).LastWriteTime
            if ($lastWrite -gt $verified)
            {
                $modifiedAfter += $relPath
            }
        }
    }

    if ($modifiedAfter.Count -gt 0)
    {
        Write-DriftResult -Name "Source drift: $($entry.description)" -Result Warn -Detail "Modified since verification: $($modifiedAfter -join ', ')"
    }
    else
    {
        Write-DriftResult -Name "Source stable: $($entry.description)" -Result Pass
    }
}

# ============================================================
# Summary
# ============================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Passed:  $passed"
Write-Host "  Failed:  $failed"
Write-Host "  Warned:  $warned"

if ($failed -gt 0)
{
    Write-Host "`n  SCREENSHOT DRIFT CHECK FAILED" -ForegroundColor Red
    exit 1
}
elseif ($warned -gt 0)
{
    Write-Host "`n  SCREENSHOT DRIFT CHECK: WARNINGS" -ForegroundColor Yellow
    exit 0
}
else
{
    Write-Host "`n  ALL SCREENSHOTS CURRENT" -ForegroundColor Green
    exit 0
}
