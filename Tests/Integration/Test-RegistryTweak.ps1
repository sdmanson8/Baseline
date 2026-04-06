<#
    .SYNOPSIS
    Focused integration test for a single registry-based tweak function.

    .DESCRIPTION
    Takes a Baseline function name and its expected registry side-effect,
    invokes the function with the "apply" parameter, verifies the registry
    value changed, then invokes the "undo" parameter and verifies
    restoration. Must be run as Administrator on a real Windows VM.

    .PARAMETER FunctionName
    The Baseline function to test (e.g., 'FileExtensions').

    .PARAMETER RegistryPath
    The registry path to check (e.g., 'HKCU:\Software\Microsoft\...\Advanced').

    .PARAMETER ValueName
    The registry value name to verify (e.g., 'HideFileExt').

    .PARAMETER ApplyParam
    The parameter set name to apply the change (e.g., 'Show', 'Enable', 'Disable').

    .PARAMETER ExpectedValue
    The expected registry value after applying.

    .PARAMETER UndoParam
    The parameter set name to undo the change (e.g., 'Hide', 'Disable', 'Enable').

    .PARAMETER UndoExpectedValue
    The expected registry value after undoing. If not specified, the test
    verifies that the value returns to its pre-test state.

    .EXAMPLE
    pwsh -File .\Tests\Integration\Test-RegistryTweak.ps1 `
        -FunctionName FileExtensions `
        -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -ValueName HideFileExt `
        -ApplyParam Show `
        -ExpectedValue 0 `
        -UndoParam Hide `
        -UndoExpectedValue 1
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$FunctionName,

    [Parameter(Mandatory)]
    [string]$RegistryPath,

    [Parameter(Mandatory)]
    [string]$ValueName,

    [Parameter(Mandatory)]
    [string]$ApplyParam,

    [Parameter(Mandatory)]
    [object]$ExpectedValue,

    [Parameter(Mandatory)]
    [string]$UndoParam,

    [object]$UndoExpectedValue
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$passed = 0
$failed = 0

function Write-TestResult
{
    param (
        [string]$Name,
        [ValidateSet('Pass', 'Fail')]
        [string]$Result,
        [string]$Detail = ''
    )

    $symbol = switch ($Result)
    {
        'Pass' { '[PASS]'; $script:passed++ }
        'Fail' { '[FAIL]'; $script:failed++ }
    }

    $line = "  $symbol $Name"
    if ($Detail) { $line += " -- $Detail" }
    # Write-Host: intentional — test/tooling console output
    Write-Host $line
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if ($env:OS -ne 'Windows_NT')
{
    Write-Error 'This test requires a Windows environment.'
}

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Error 'This test must be run as Administrator.'
}

# ---------------------------------------------------------------------------
# Import modules
# ---------------------------------------------------------------------------
Write-Host "`n=== Test-RegistryTweak: $FunctionName ===" -ForegroundColor Cyan

$modulePath = Join-Path $repoRoot 'Module'
Import-Module (Join-Path $modulePath 'SharedHelpers.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $modulePath 'Logging.psm1')       -Force -ErrorAction Stop

$regionDir = Join-Path $modulePath 'Regions'
foreach ($region in Get-ChildItem -Path $regionDir -Filter '*.psm1' -File)
{
    Import-Module $region.FullName -Force -ErrorAction Stop
}

# Verify the function exists
$cmd = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
if (-not $cmd)
{
    Write-Error "Function '$FunctionName' not found after importing Baseline modules."
}

# ---------------------------------------------------------------------------
# Capture original state
# ---------------------------------------------------------------------------
$originalValue = $null
$originalExists = $false
try
{
    $originalValue = (Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop).$ValueName
    $originalExists = $true
}
catch
{
    # Value may not exist before the test
}

Write-Host "  Original value: $(if ($originalExists) { $originalValue } else { '<not set>' })"

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------
try
{
    $applyArgs = @{ $ApplyParam = $true }
    & $FunctionName @applyArgs

    $currentValue = (Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop).$ValueName

    if ($currentValue -eq $ExpectedValue)
    {
        Write-TestResult -Name "Apply (-$ApplyParam): $ValueName = $ExpectedValue" -Result Pass
    }
    else
    {
        Write-TestResult -Name "Apply (-$ApplyParam): $ValueName = $ExpectedValue" -Result Fail -Detail "Got $currentValue"
    }
}
catch
{
    Write-TestResult -Name "Apply (-$ApplyParam)" -Result Fail -Detail $_.Exception.Message
}

# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------
try
{
    $undoArgs = @{ $UndoParam = $true }
    & $FunctionName @undoArgs

    if ($PSBoundParameters.ContainsKey('UndoExpectedValue'))
    {
        # Explicit undo value provided -- check against it
        $currentValue = $null
        $valueExists  = $false
        try
        {
            $currentValue = (Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop).$ValueName
            $valueExists = $true
        }
        catch { }

        if ($valueExists -and $currentValue -eq $UndoExpectedValue)
        {
            Write-TestResult -Name "Undo (-$UndoParam): $ValueName = $UndoExpectedValue" -Result Pass
        }
        elseif (-not $valueExists -and $null -eq $UndoExpectedValue)
        {
            Write-TestResult -Name "Undo (-$UndoParam): $ValueName removed" -Result Pass
        }
        else
        {
            $detail = if ($valueExists) { "Got $currentValue" } else { 'Value does not exist' }
            Write-TestResult -Name "Undo (-$UndoParam): $ValueName = $UndoExpectedValue" -Result Fail -Detail $detail
        }
    }
    else
    {
        # No explicit undo value -- verify restoration to original state
        $currentValue = $null
        $valueExists  = $false
        try
        {
            $currentValue = (Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop).$ValueName
            $valueExists = $true
        }
        catch { }

        if ($originalExists -and $valueExists -and $currentValue -eq $originalValue)
        {
            Write-TestResult -Name "Undo (-$UndoParam): restored to original ($originalValue)" -Result Pass
        }
        elseif (-not $originalExists -and -not $valueExists)
        {
            Write-TestResult -Name "Undo (-$UndoParam): value removed (matches original)" -Result Pass
        }
        else
        {
            $detail = if ($valueExists) { "Got $currentValue, expected $originalValue" } else { 'Value removed but originally existed' }
            Write-TestResult -Name "Undo (-$UndoParam): restored to original" -Result Fail -Detail $detail
        }
    }
}
catch
{
    Write-TestResult -Name "Undo (-$UndoParam)" -Result Fail -Detail $_.Exception.Message
}

# ---------------------------------------------------------------------------
# Final restore (safety net)
# ---------------------------------------------------------------------------
try
{
    if ($originalExists)
    {
        if (!(Test-Path $RegistryPath))
        {
            New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $RegistryPath -Name $ValueName -PropertyType DWord -Value $originalValue -Force -ErrorAction Stop | Out-Null
    }
}
catch
{
    Write-Host "  Warning: Could not restore original value: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "  Passed: $passed  Failed: $failed"

if ($failed -gt 0)
{
    exit 1
}
else
{
    exit 0
}
