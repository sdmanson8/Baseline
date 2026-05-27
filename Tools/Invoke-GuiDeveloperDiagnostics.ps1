<#
    .SYNOPSIS
    Runs developer diagnostics for the Baseline GUI from an external process.

    .DESCRIPTION
    This script is launched by the GUI in a child powershell.exe process. It keeps
    Pester and validation execution outside the GUI runspace, streams console
    output to the caller, and writes a JSON report under .artifacts/gui-tests.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('ExportReport', 'SourceQuality', 'Unit', 'GuiComposition', 'Integration')]
    [string]$Action,

    [string]$OutputPath,

    [switch]$AllowIntegration
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$invocationRoot = (Get-Location).ProviderPath
$candidateManifest = Join-Path $invocationRoot 'Module\Baseline.psd1'
$repoRoot = if (Test-Path -LiteralPath $candidateManifest -PathType Leaf)
{
    $invocationRoot
}
else
{
    Split-Path -Path $PSScriptRoot -Parent
}

if ([string]::IsNullOrWhiteSpace([string]$OutputPath))
{
    $reportDir = Join-Path $repoRoot '.artifacts\gui-tests'
    $OutputPath = Join-Path $reportDir ('TestReport_{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function New-DiagnosticsLayer
{
    param(
        [string]$Name,
        [string]$Script,
        [string]$Result = 'Unknown',
        [int]$Passed = 0,
        [int]$Failed = 0,
        [int]$Skipped = 0,
        [double]$Duration = 0,
        [string]$Output = ''
    )

    return [ordered]@{
        name     = $Name
        script   = $Script
        result   = $Result
        passed   = $Passed
        failed   = $Failed
        skipped  = $Skipped
        duration = $Duration
        output   = $Output
    }
}

function New-DiagnosticsReport
{
    param(
        [string]$ActionName
    )

    return [ordered]@{
        generated = (Get-Date -Format 'o')
        action    = $ActionName
        platform  = [ordered]@{
            os        = [System.Environment]::OSVersion.VersionString
            edition   = $PSVersionTable.PSEdition
            psVersion = $PSVersionTable.PSVersion.ToString()
            hostname  = [System.Environment]::MachineName
        }
        layers   = [ordered]@{}
        summary  = [ordered]@{
            totalPassed  = 0
            totalFailed  = 0
            totalSkipped = 0
            overallResult = 'Unknown'
        }
    }
}

function Complete-DiagnosticsReport
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Report
    )

    $passed = 0
    $failed = 0
    $skipped = 0
    $hasFailure = $false

    foreach ($key in $Report.layers.Keys)
    {
        $layer = $Report.layers[$key]
        $passed += [int]$layer.passed
        $failed += [int]$layer.failed
        $skipped += [int]$layer.skipped
        if ([string]$layer.result -in @('Failed', 'Error'))
        {
            $hasFailure = $true
        }
    }

    $Report.summary.totalPassed = $passed
    $Report.summary.totalFailed = $failed
    $Report.summary.totalSkipped = $skipped
    $Report.summary.overallResult = if ($hasFailure) { 'Failed' } else { 'Passed' }
    return $Report
}

function Write-DiagnosticsReport
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Specialized.OrderedDictionary]$Report,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent -PathType Container))
    {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, ($Report | ConvertTo-Json -Depth 8), $utf8NoBom)
}

function Invoke-DiagnosticsPowerShellScript
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$Arguments = @()
    )

    $layerOutput = New-Object System.Text.StringBuilder
    $passed = 0
    $failed = 0
    $skipped = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf))
    {
        return (New-DiagnosticsLayer -Name $Name -Script $ScriptPath -Result 'Skipped' -Skipped 1 -Output "Script not found: $ScriptPath")
    }

    $powershellPath = Join-Path $PSHOME 'powershell.exe'
    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + @($Arguments)
    & $powershellPath @childArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        Write-Host $line
        [void]$layerOutput.AppendLine($line)
        $passed += ([regex]::Matches($line, '\[PASS\]')).Count
        $failed += ([regex]::Matches($line, '\[FAIL\]')).Count
        $skipped += ([regex]::Matches($line, '\[SKIP\]')).Count
    }
    $exitCode = [int]$LASTEXITCODE
    $sw.Stop()

    $result = if (($exitCode -ne 0) -or ($failed -gt 0)) { 'Failed' } else { 'Passed' }
    return (New-DiagnosticsLayer -Name $Name -Script $ScriptPath -Result $result -Passed $passed -Failed $failed -Skipped $skipped -Duration ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Output $layerOutput.ToString().Trim())
}

function Invoke-DiagnosticsPesterLayer
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        return (New-DiagnosticsLayer -Name $Name -Script $Path -Result 'Skipped' -Skipped 1 -Output "Path not found: $Path")
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = $Path
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Output.Verbosity = 'Detailed'
        $pesterConfig.TestRegistry.Enabled = $false

        $pesterResult = Invoke-Pester -Configuration $pesterConfig
        $sw.Stop()

        $resultText = if ([int]$pesterResult.FailedCount -gt 0) { 'Failed' } else { 'Passed' }
        $summaryText = "Tests: $($pesterResult.TotalCount) | Passed: $($pesterResult.PassedCount) | Failed: $($pesterResult.FailedCount) | Skipped: $($pesterResult.SkippedCount)"
        Write-Host $summaryText

        return (New-DiagnosticsLayer -Name $Name -Script $Path -Result $resultText -Passed ([int]$pesterResult.PassedCount) -Failed ([int]$pesterResult.FailedCount) -Skipped ([int]$pesterResult.SkippedCount) -Duration ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Output $summaryText)
    }
    catch
    {
        $sw.Stop()
        Write-Host ("ERROR: {0}" -f $_.Exception.Message)
        return (New-DiagnosticsLayer -Name $Name -Script $Path -Result 'Error' -Failed 1 -Duration ([math]::Round($sw.Elapsed.TotalSeconds, 2)) -Output $_.Exception.Message)
    }
}

$exitCode = 0
$report = New-DiagnosticsReport -ActionName $Action
$reportAlreadyWritten = $false

try
{
    Push-Location $repoRoot
    try
    {
        switch ($Action)
        {
            'ExportReport'
            {
                $exportScript = Join-Path $repoRoot 'Tools\Export-TestReport.ps1'
                $exportLayer = Invoke-DiagnosticsPowerShellScript -Name 'Generated Test Report' -ScriptPath $exportScript -Arguments @('-OutputPath', $OutputPath)
                if (Test-Path -LiteralPath $OutputPath -PathType Leaf)
                {
                    $reportAlreadyWritten = $true
                    $existingReport = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json
                    Write-Host ''
                    Write-Host "Report: $OutputPath"
                    if ($existingReport.summary)
                    {
                        Write-Host ("Passed: {0}" -f $existingReport.summary.totalPassed)
                        Write-Host ("Failed: {0}" -f $existingReport.summary.totalFailed)
                        Write-Host ("Skipped: {0}" -f $existingReport.summary.totalSkipped)
                        Write-Host ("Result: {0}" -f $existingReport.summary.overallResult)
                        if ([string]$existingReport.summary.overallResult -eq 'Failed') { $exitCode = 1 }
                    }
                    if ([string]$exportLayer.result -in @('Failed', 'Error')) { $exitCode = 1 }
                    break
                }

                $report.layers['generated'] = $exportLayer
            }
            'SourceQuality'
            {
                $smokeScript = Join-Path $repoRoot 'Tools\Test-SmokeTest.ps1'
                $report.layers['sourceQuality'] = Invoke-DiagnosticsPowerShellScript -Name 'Source Quality Guards' -ScriptPath $smokeScript
            }
            'Unit'
            {
                $unitPath = Join-Path $repoRoot 'Tests\Unit'
                $report.layers['unit'] = Invoke-DiagnosticsPesterLayer -Name 'Unit Tests' -Path $unitPath
            }
            'GuiComposition'
            {
                $compositionPath = Join-Path $repoRoot 'Tests\GUI.Composition.Tests.ps1'
                $report.layers['composition'] = Invoke-DiagnosticsPesterLayer -Name 'GUI Composition Tests' -Path $compositionPath
            }
            'Integration'
            {
                if (-not $AllowIntegration)
                {
                    throw 'Integration diagnostics are VM-only and require explicit AllowIntegration opt-in.'
                }
                $integrationPath = Join-Path $repoRoot 'Tests\Integration'
                $report.layers['integration'] = Invoke-DiagnosticsPesterLayer -Name 'Integration Tests' -Path $integrationPath
            }
        }
    }
    finally
    {
        Pop-Location
    }
}
catch
{
    $report.layers['error'] = New-DiagnosticsLayer -Name 'Diagnostics Runner' -Script $PSCommandPath -Result 'Error' -Failed 1 -Output $_.Exception.Message
    Write-Host ("ERROR: {0}" -f $_.Exception.Message)
}

if (-not $reportAlreadyWritten)
{
    $report = Complete-DiagnosticsReport -Report $report
    Write-DiagnosticsReport -Report $report -Path $OutputPath

    Write-Host ''
    Write-Host '=== Diagnostics Summary ==='
    Write-Host ("  Passed:  {0}" -f $report.summary.totalPassed)
    Write-Host ("  Failed:  {0}" -f $report.summary.totalFailed)
    Write-Host ("  Skipped: {0}" -f $report.summary.totalSkipped)
    Write-Host ("  Result:  {0}" -f $report.summary.overallResult)
    Write-Host ("  Report:  {0}" -f $OutputPath)

    if ([string]$report.summary.overallResult -eq 'Failed')
    {
        $exitCode = 1
    }
}

exit $exitCode
