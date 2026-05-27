<#
    .SYNOPSIS
    Runs the internal validation suite and appends all output to a log file.

    .PARAMETER LogFile
    Path to the log file. Defaults to Win11-validation.log in the repo root.

    .EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Run-ValidationSuite.ps1

    .NOTES
    This is an internal build/verification script for maintainers and CI.
#>

[CmdletBinding()]
param (
    [string]$LogFile
)

# Continue intentionally so the suite captures output from each validation layer before summarizing.
$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

if (-not $LogFile)
{
    $LogFile = Join-Path $repoRoot 'Win11-validation.log'
}

<#
    .SYNOPSIS
#>

function Append-Log
{
    param([string]$Text)
    $Text | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# ── Header ──
("=== VALIDATION LOG ===" + "`n" + (Get-Date -Format 'o') + "`n" + "OS: $([System.Environment]::OSVersion.VersionString)" + "`n" + "PS: $($PSVersionTable.PSVersion)" + "`n") | Out-File -FilePath $LogFile -Encoding UTF8

# ── 1. Source smoke tests ──
Append-Log '=== SOURCE SMOKE TESTS ==='
$smokeOut = & (Join-Path $repoRoot 'Tools/Test-SmokeTest.ps1') *>&1 | Out-String
Append-Log $smokeOut

# ── 1b. Release smoke tests ──
Append-Log "`n=== RELEASE SMOKE TESTS ==="
$releaseSmokeScript = Join-Path $repoRoot 'Tools/Test-ReleaseSmoke.ps1'
$repoExe = Join-Path $repoRoot 'Baseline.exe'
if (Test-Path -LiteralPath $repoExe -PathType Leaf)
{
    $releaseSmokeOut = & $releaseSmokeScript *>&1 | Out-String
    Append-Log $releaseSmokeOut
}
else
{
    Append-Log '  [SKIP] Release smoke tests -- Baseline.exe not found; build the launcher or packaging inputs first.'
}

# ── 2. Documentation consistency checks ──
Append-Log "`n=== DOCS CONSISTENCY CHECKS ==="
$docsOut = & (Join-Path $repoRoot 'Tools/Test-DocumentationConsistency.ps1') *>&1 | Out-String
Append-Log $docsOut

# ── 3. Unit tests ──
Append-Log "`n=== UNIT TESTS ==="
Import-Module Pester -MinimumVersion 5.0.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $repoRoot 'Tests/Unit'
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'None'
$cfg.TestRegistry.Enabled = $false
$unitResult = Invoke-Pester -Configuration $cfg
Append-Log ("UNIT-SUMMARY: Total={0} Passed={1} Failed={2} Skipped={3}" -f $unitResult.TotalCount, $unitResult.PassedCount, $unitResult.FailedCount, $unitResult.SkippedCount)
if ($unitResult.FailedCount -gt 0)
{
    $unitResult.Failed | ForEach-Object { Append-Log ("  FAIL: {0}" -f $_.Name) }
}

# ── 4. Composition tests ──
Append-Log "`n=== COMPOSITION TESTS ==="
$cfg2 = New-PesterConfiguration
$cfg2.Run.Path = Join-Path $repoRoot 'Tests/GUI.Composition.Tests.ps1'
$cfg2.Run.PassThru = $true
$cfg2.Output.Verbosity = 'None'
$cfg2.TestRegistry.Enabled = $false
$compResult = Invoke-Pester -Configuration $cfg2
Append-Log ("COMPOSITION-SUMMARY: Total={0} Passed={1} Failed={2} Skipped={3}" -f $compResult.TotalCount, $compResult.PassedCount, $compResult.FailedCount, $compResult.SkippedCount)
if ($compResult.FailedCount -gt 0)
{
    $compResult.Failed | ForEach-Object { Append-Log ("  FAIL: {0}" -f $_.Name) }
}

# ── 5. Responsive tab/dropdown tests ──
Append-Log "`n=== RESPONSIVE TAB/DROPDOWN TESTS ==="
$cfg3 = New-PesterConfiguration
$cfg3.Run.Path = Join-Path $repoRoot 'Tests/Unit/ResponsiveTabDropdown.Tests.ps1'
$cfg3.Run.PassThru = $true
$cfg3.Output.Verbosity = 'None'
$cfg3.TestRegistry.Enabled = $false
$respResult = Invoke-Pester -Configuration $cfg3
Append-Log ("RESPONSIVE-SUMMARY: Total={0} Passed={1} Failed={2} Skipped={3}" -f $respResult.TotalCount, $respResult.PassedCount, $respResult.FailedCount, $respResult.SkippedCount)

# ── 6. Export JSON report ──
Append-Log "`n=== EXPORT REPORT ==="
$reportOut = & (Join-Path $repoRoot 'Tools/Export-TestReport.ps1') *>&1 | Out-String
Append-Log $reportOut

# ── Final summary ──
Append-Log "`n=== FINAL SUMMARY ==="
Append-Log ("Unit:        {0}/{1} passed, {2} failed, {3} skipped" -f $unitResult.PassedCount, $unitResult.TotalCount, $unitResult.FailedCount, $unitResult.SkippedCount)
Append-Log ("Composition: {0}/{1} passed" -f $compResult.PassedCount, $compResult.TotalCount)
Append-Log ("Responsive:  {0}/{1} passed" -f $respResult.PassedCount, $respResult.TotalCount)
Append-Log ("Report:      Tests/TestReport.json")
Append-Log ("Log:         $LogFile")

# Write-Host: intentional — tooling console output
Write-Host ("Done. Results in {0}" -f $LogFile)
