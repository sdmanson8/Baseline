<#
    .SYNOPSIS
    VM-based integration test runner for Baseline.

    .DESCRIPTION
    Executes real tweak functions against a live Windows installation and
    verifies that system state changes as expected. Must be run as
    Administrator inside a disposable VM.

    Creates a system restore point before testing and outputs structured
    results. Each category applies a safe change, verifies it, undoes it,
    and verifies restoration.

    .PARAMETER Category
    Which test category to run. Defaults to 'All'.

    .PARAMETER DryRun
    When set, skips destructive operations (package removal). Registry,
    service, and policy tests still execute because they are reversible.

    .PARAMETER SkipRestorePoint
    When set, skips system restore point creation (useful in CI where
    restore points are unavailable on Server SKUs).

    .EXAMPLE
    pwsh -File .\Tests\Integration\IntegrationTest.ps1

    .EXAMPLE
    pwsh -File .\Tests\Integration\IntegrationTest.ps1 -Category Registry -DryRun
#>

[CmdletBinding()]
param (
    [ValidateSet('All', 'Registry', 'Services', 'Packages', 'GroupPolicy', 'GameMode')]
    [string]$Category = 'All',

    [switch]$DryRun,

    [switch]$SkipRestorePoint
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
$script:RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$script:Passed   = 0
$script:Failed   = 0
$script:Skipped  = 0
$script:Results  = [System.Collections.Generic.List[pscustomobject]]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-TestResult
{
    param (
        [string]$Category,
        [string]$Name,
        [ValidateSet('Pass', 'Fail', 'Skip')]
        [string]$Result,
        [string]$Detail = ''
    )

    switch ($Result)
    {
        'Pass' { $script:Passed++; $symbol = '[PASS]' }
        'Fail' { $script:Failed++; $symbol = '[FAIL]' }
        'Skip' { $script:Skipped++; $symbol = '[SKIP]' }
    }

    $entry = [pscustomobject]@{
        Category  = $Category
        Name      = $Name
        Result    = $Result
        Detail    = $Detail
        Timestamp = (Get-Date -Format 'o')
    }
    $script:Results.Add($entry)

    $line = "  $symbol [$Category] $Name"
    if ($Detail) { $line += " -- $Detail" }
    # Write-Host: intentional — test/tooling console output
    Write-Host $line
}

function Assert-IsAdministrator
{
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        Write-Error 'Integration tests must be run as Administrator.'
    }
}

function Assert-IsWindows
{
    if ($env:OS -ne 'Windows_NT')
    {
        Write-Error 'Integration tests require a Windows environment.'
    }
}

# ---------------------------------------------------------------------------
# Module import
# ---------------------------------------------------------------------------
function Import-BaselineModules
{
    $modulePath = Join-Path $script:RepoRoot 'Module'

    # Import SharedHelpers first (provides Write-ConsoleStatus, LogInfo, etc.)
    Import-Module (Join-Path $modulePath 'SharedHelpers.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath 'Logging.psm1')       -Force -ErrorAction Stop

    # Import region modules that contain the functions we test
    $regionDir = Join-Path $modulePath 'Regions'
    foreach ($region in Get-ChildItem -Path $regionDir -Filter '*.psm1' -File)
    {
        Import-Module $region.FullName -Force -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# System restore point
# ---------------------------------------------------------------------------
function New-IntegrationRestorePoint
{
    if ($SkipRestorePoint)
    {
        Write-Host '  Skipping restore point creation (-SkipRestorePoint)' -ForegroundColor Yellow
        return
    }

    try
    {
        Write-Host '  Creating system restore point...' -ForegroundColor Cyan
        Checkpoint-Computer -Description 'Baseline Integration Test' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Host '  Restore point created.' -ForegroundColor Green
    }
    catch
    {
        Write-Host "  Warning: Could not create restore point: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '  Tests will continue. Manual cleanup may be required.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Category: Registry
# ---------------------------------------------------------------------------
function Invoke-RegistryTests
{
    Write-Host "`n=== Registry Tests ===" -ForegroundColor Cyan

    # Test: FileExtensions toggle (Show / Hide)
    # Show = HideFileExt -> 0, Hide = HideFileExt -> 1
    $regPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $valueName = 'HideFileExt'

    # Capture baseline value
    $originalValue = $null
    try
    {
        $originalValue = (Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop).$valueName
    }
    catch
    {
        # Value may not exist; that is fine
    }

    # Apply: Show file extensions (HideFileExt = 0)
    try
    {
        FileExtensions -Show
        $currentValue = (Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop).$valueName

        if ($currentValue -eq 0)
        {
            Write-TestResult -Category 'Registry' -Name 'FileExtensions -Show sets HideFileExt=0' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Registry' -Name 'FileExtensions -Show sets HideFileExt=0' -Result Fail -Detail "Expected 0, got $currentValue"
        }
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'FileExtensions -Show sets HideFileExt=0' -Result Fail -Detail $_.Exception.Message
    }

    # Undo: Hide file extensions (HideFileExt = 1)
    try
    {
        FileExtensions -Hide
        $currentValue = (Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop).$valueName

        if ($currentValue -eq 1)
        {
            Write-TestResult -Category 'Registry' -Name 'FileExtensions -Hide sets HideFileExt=1' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Registry' -Name 'FileExtensions -Hide sets HideFileExt=1' -Result Fail -Detail "Expected 1, got $currentValue"
        }
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'FileExtensions -Hide sets HideFileExt=1' -Result Fail -Detail $_.Exception.Message
    }

    # Restore original value
    try
    {
        if ($null -ne $originalValue)
        {
            New-ItemProperty -Path $regPath -Name $valueName -PropertyType DWord -Value $originalValue -Force -ErrorAction Stop | Out-Null
        }
        Write-TestResult -Category 'Registry' -Name 'FileExtensions restored to original value' -Result Pass
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'FileExtensions restored to original value' -Result Fail -Detail $_.Exception.Message
    }

    # Test: ClearRecentFiles toggle (Enable / Disable)
    # Enable = ClearRecentDocsOnExit -> 1, Disable = value removed
    $crfPath   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $crfName   = 'ClearRecentDocsOnExit'

    $crfOriginal = $null
    $crfOriginalExists = $false
    try
    {
        $crfOriginal = (Get-ItemProperty -Path $crfPath -Name $crfName -ErrorAction Stop).$crfName
        $crfOriginalExists = $true
    }
    catch
    {
        # Value may not exist
    }

    try
    {
        ClearRecentFiles -Enable
        $crfCurrent = (Get-ItemProperty -Path $crfPath -Name $crfName -ErrorAction Stop).$crfName

        if ($crfCurrent -eq 1)
        {
            Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Enable sets ClearRecentDocsOnExit=1' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Enable sets ClearRecentDocsOnExit=1' -Result Fail -Detail "Expected 1, got $crfCurrent"
        }
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Enable sets ClearRecentDocsOnExit=1' -Result Fail -Detail $_.Exception.Message
    }

    try
    {
        ClearRecentFiles -Disable
        $crfStillExists = $false
        try
        {
            $null = (Get-ItemProperty -Path $crfPath -Name $crfName -ErrorAction Stop).$crfName
            $crfStillExists = $true
        }
        catch { }

        if (-not $crfStillExists)
        {
            Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Disable removes ClearRecentDocsOnExit' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Disable removes ClearRecentDocsOnExit' -Result Fail -Detail 'Value still present after Disable'
        }
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles -Disable removes ClearRecentDocsOnExit' -Result Fail -Detail $_.Exception.Message
    }

    # Restore original ClearRecentFiles state
    try
    {
        if ($crfOriginalExists)
        {
            if (!(Test-Path $crfPath))
            {
                New-Item -Path $crfPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $crfPath -Name $crfName -Type DWord -Value $crfOriginal -ErrorAction Stop
        }
        Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles restored to original state' -Result Pass
    }
    catch
    {
        Write-TestResult -Category 'Registry' -Name 'ClearRecentFiles restored to original state' -Result Fail -Detail $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Category: Services
# ---------------------------------------------------------------------------
function Invoke-ServiceTests
{
    Write-Host "`n=== Service Tests ===" -ForegroundColor Cyan

    # Test with a safe, non-critical service: SysMain (Superfetch)
    # This service is commonly toggled and safe to stop/start.
    $serviceName = 'SysMain'

    # Check if the service exists on this OS
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc)
    {
        Write-TestResult -Category 'Services' -Name "Service $serviceName exists" -Result Skip -Detail 'Service not found on this OS'
        return
    }

    $originalStatus  = $svc.Status
    $originalStartup = $svc.StartType

    # Stop the service
    try
    {
        if ($svc.Status -eq 'Running')
        {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
        Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop

        $svc = Get-Service -Name $serviceName
        if ($svc.StartType -eq 'Disabled')
        {
            Write-TestResult -Category 'Services' -Name "Disable $serviceName startup" -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Services' -Name "Disable $serviceName startup" -Result Fail -Detail "StartType is $($svc.StartType)"
        }
    }
    catch
    {
        Write-TestResult -Category 'Services' -Name "Disable $serviceName startup" -Result Fail -Detail $_.Exception.Message
    }

    # Restore the service
    try
    {
        Set-Service -Name $serviceName -StartupType $originalStartup -ErrorAction Stop
        if ($originalStatus -eq 'Running')
        {
            Start-Service -Name $serviceName -ErrorAction Stop
            Start-Sleep -Seconds 2
        }

        $svc = Get-Service -Name $serviceName
        if ($svc.StartType -eq $originalStartup -and $svc.Status -eq $originalStatus)
        {
            Write-TestResult -Category 'Services' -Name "Restore $serviceName to original state" -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Services' -Name "Restore $serviceName to original state" -Result Fail -Detail "StartType=$($svc.StartType) Status=$($svc.Status)"
        }
    }
    catch
    {
        Write-TestResult -Category 'Services' -Name "Restore $serviceName to original state" -Result Fail -Detail $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Category: Packages
# ---------------------------------------------------------------------------
function Invoke-PackageTests
{
    Write-Host "`n=== Package Tests ===" -ForegroundColor Cyan

    if ($DryRun)
    {
        Write-TestResult -Category 'Packages' -Name 'UWP removal test' -Result Skip -Detail 'Skipped in DryRun mode'
        return
    }

    # Test: Remove a safe, non-essential UWP app (Microsoft.BingNews)
    # This is commonly pre-installed and safe to remove.
    $appName = 'Microsoft.BingNews'

    $app = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
    if (-not $app)
    {
        Write-TestResult -Category 'Packages' -Name "UWP $appName present" -Result Skip -Detail 'App not installed; nothing to test'
        return
    }

    try
    {
        Get-AppxPackage -Name $appName | Remove-AppxPackage -ErrorAction Stop
        $appAfter = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue

        if (-not $appAfter)
        {
            Write-TestResult -Category 'Packages' -Name "Remove UWP $appName" -Result Pass
        }
        else
        {
            Write-TestResult -Category 'Packages' -Name "Remove UWP $appName" -Result Fail -Detail 'App still present after removal'
        }
    }
    catch
    {
        Write-TestResult -Category 'Packages' -Name "Remove UWP $appName" -Result Fail -Detail $_.Exception.Message
    }

    # Note: UWP reinstallation requires the Store or DISM with the original
    # package, which is not reliably automatable. This is a one-way test.
    Write-TestResult -Category 'Packages' -Name 'UWP reinstallation' -Result Skip -Detail 'Reinstallation requires Store or DISM; VM snapshot restore recommended'
}

# ---------------------------------------------------------------------------
# Category: Group Policy
# ---------------------------------------------------------------------------
function Invoke-GroupPolicyTests
{
    Write-Host "`n=== Group Policy Tests ===" -ForegroundColor Cyan

    # Test: LanmanWorkstationGuestAuthPolicy (LGPO-backed toggle)
    # This uses Set-Policy under the hood.
    # Verify the registry side-effect at:
    #   HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation
    #   AllowInsecureGuestAuth

    $gpRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
    $gpName    = 'AllowInsecureGuestAuth'

    # Capture original state
    $gpOriginal = $null
    $gpOriginalExists = $false
    try
    {
        $gpOriginal = (Get-ItemProperty -Path $gpRegPath -Name $gpName -ErrorAction Stop).$gpName
        $gpOriginalExists = $true
    }
    catch { }

    # Check if Set-Policy / LGPO is available
    $setPolicyAvailable = Get-Command -Name 'Set-Policy' -ErrorAction SilentlyContinue
    if (-not $setPolicyAvailable)
    {
        Write-TestResult -Category 'GroupPolicy' -Name 'Set-Policy command available' -Result Skip -Detail 'Set-Policy not loaded; LGPO infrastructure may not be present'
        return
    }

    # Apply: Disable (AllowInsecureGuestAuth = 0)
    try
    {
        LanmanWorkstationGuestAuthPolicy -Disable
        $gpCurrent = (Get-ItemProperty -Path $gpRegPath -Name $gpName -ErrorAction Stop).$gpName

        if ($gpCurrent -eq 0)
        {
            Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Disable sets value=0' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Disable sets value=0' -Result Fail -Detail "Expected 0, got $gpCurrent"
        }
    }
    catch
    {
        Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Disable sets value=0' -Result Fail -Detail $_.Exception.Message
    }

    # Undo: Enable (AllowInsecureGuestAuth = 1)
    try
    {
        LanmanWorkstationGuestAuthPolicy -Enable
        $gpCurrent = (Get-ItemProperty -Path $gpRegPath -Name $gpName -ErrorAction Stop).$gpName

        if ($gpCurrent -eq 1)
        {
            Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Enable sets value=1' -Result Pass
        }
        else
        {
            Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Enable sets value=1' -Result Fail -Detail "Expected 1, got $gpCurrent"
        }
    }
    catch
    {
        Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy -Enable sets value=1' -Result Fail -Detail $_.Exception.Message
    }

    # Restore original state
    try
    {
        if ($gpOriginalExists)
        {
            Set-ItemProperty -Path $gpRegPath -Name $gpName -Value $gpOriginal -ErrorAction Stop
        }
        else
        {
            # Remove the value if it did not exist before
            if (Test-Path $gpRegPath)
            {
                Remove-ItemProperty -Path $gpRegPath -Name $gpName -ErrorAction SilentlyContinue
            }
        }
        Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy restored to original state' -Result Pass
    }
    catch
    {
        Write-TestResult -Category 'GroupPolicy' -Name 'LanmanWorkstationGuestAuthPolicy restored to original state' -Result Fail -Detail $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Category: Game Mode
# ---------------------------------------------------------------------------
function Invoke-GameModeTests
{
    Write-Host "`n=== Game Mode Tests ===" -ForegroundColor Cyan

    # Verify Game Mode profile definitions load
    $getProfiles = Get-Command -Name 'Get-GameModeProfileDefinitions' -ErrorAction SilentlyContinue
    if (-not $getProfiles)
    {
        Write-TestResult -Category 'GameMode' -Name 'Get-GameModeProfileDefinitions available' -Result Skip -Detail 'Function not loaded'
        return
    }

    try
    {
        $profiles = Get-GameModeProfileDefinitions
        if ($profiles.Count -ge 4)
        {
            Write-TestResult -Category 'GameMode' -Name 'Profile definitions load' -Result Pass -Detail "$($profiles.Count) profiles"
        }
        else
        {
            Write-TestResult -Category 'GameMode' -Name 'Profile definitions load' -Result Fail -Detail "Expected >= 4, got $($profiles.Count)"
        }
    }
    catch
    {
        Write-TestResult -Category 'GameMode' -Name 'Profile definitions load' -Result Fail -Detail $_.Exception.Message
    }

    # Verify allowlist loads
    try
    {
        $allowlist = Get-GameModeAllowlist
        if ($allowlist.Count -gt 0)
        {
            Write-TestResult -Category 'GameMode' -Name 'Allowlist loads' -Result Pass -Detail "$($allowlist.Count) entries"
        }
        else
        {
            Write-TestResult -Category 'GameMode' -Name 'Allowlist loads' -Result Fail -Detail 'Empty allowlist'
        }
    }
    catch
    {
        Write-TestResult -Category 'GameMode' -Name 'Allowlist loads' -Result Fail -Detail $_.Exception.Message
    }

    # Verify Casual profile selection state builds without error
    $mergeCmd = Get-Command -Name 'Merge-GameModeSelectionState' -ErrorAction SilentlyContinue
    if (-not $mergeCmd)
    {
        Write-TestResult -Category 'GameMode' -Name 'Merge-GameModeSelectionState available' -Result Skip -Detail 'Function not loaded'
        return
    }

    try
    {
        # Load full manifest to test merge
        $dataDir  = Join-Path $script:RepoRoot 'Module/Data'
        $manifest = @()
        foreach ($jsonFile in Get-ChildItem -Path $dataDir -Filter '*.json' -File)
        {
            $data = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
            if ($data.Entries)
            {
                $manifest += $data.Entries
            }
        }

        $selectionState = Merge-GameModeSelectionState -Manifest $manifest -ProfileName 'Casual' -Allowlist $allowlist
        if ($selectionState -is [System.Collections.IDictionary])
        {
            Write-TestResult -Category 'GameMode' -Name 'Casual profile selection state builds' -Result Pass -Detail "$($selectionState.Count) selections"
        }
        else
        {
            Write-TestResult -Category 'GameMode' -Name 'Casual profile selection state builds' -Result Fail -Detail 'Result is not a dictionary'
        }
    }
    catch
    {
        Write-TestResult -Category 'GameMode' -Name 'Casual profile selection state builds' -Result Fail -Detail $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host '  Baseline Integration Test Runner' -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

Assert-IsWindows
Assert-IsAdministrator

Write-Host "Category: $Category"
Write-Host "DryRun:   $DryRun"
Write-Host ''

# Import Baseline modules
Write-Host '--- Loading Baseline Modules ---' -ForegroundColor Cyan
Import-BaselineModules
Write-Host '  Modules loaded.' -ForegroundColor Green

# Create restore point
Write-Host "`n--- Restore Point ---" -ForegroundColor Cyan
New-IntegrationRestorePoint

# Run selected categories
$categories = if ($Category -eq 'All')
{
    @('Registry', 'Services', 'Packages', 'GroupPolicy', 'GameMode')
}
else
{
    @($Category)
}

foreach ($cat in $categories)
{
    switch ($cat)
    {
        'Registry'    { Invoke-RegistryTests }
        'Services'    { Invoke-ServiceTests }
        'Packages'    { Invoke-PackageTests }
        'GroupPolicy' { Invoke-GroupPolicyTests }
        'GameMode'    { Invoke-GameModeTests }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Passed:  $($script:Passed)"
Write-Host "  Failed:  $($script:Failed)"
Write-Host "  Skipped: $($script:Skipped)"

# Export structured results as JSON for CI consumption
$resultsPath = Join-Path $PSScriptRoot 'IntegrationResults.json'
$script:Results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultsPath -Encoding UTF8
Write-Host "`n  Results written to: $resultsPath"

if ($script:Failed -gt 0)
{
    Write-Host "`n  INTEGRATION TESTS FAILED" -ForegroundColor Red
    exit 1
}
else
{
    Write-Host "`n  ALL INTEGRATION TESTS PASSED" -ForegroundColor Green
    exit 0
}
