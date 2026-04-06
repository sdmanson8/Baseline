<#
.SYNOPSIS
    Adds missing metadata fields (Impact, Safe, RequiresRestart, WhyThisMatters, PresetTier,
    CompatibilitySensitivity) to all Module/Data/*.json tweak entries.

.DESCRIPTION
    Derives values from existing metadata:
    - Impact: derived from Risk (Low->Low, Medium->Medium, High->High)
    - Safe: derived from Risk (Low->true, Medium/High->false)
    - RequiresRestart: heuristic from tags, description, function name
    - WhyThisMatters: generated from Description + Detail + Risk context
    - PresetTier: assigned based on Risk + function name + exclusion rules
    - CompatibilitySensitivity: defaults to 'Low' if missing (valid: Low, Medium, High)
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot 'Module'

if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container))
{
    throw "Module directory not found under: $repoRoot"
}

$dataDir = Join-Path $moduleRoot 'Data'
$jsonFiles = Get-ChildItem -Path $dataDir -Filter '*.json' -File

# Functions that are in the curated Minimal preset
$minimalFunctions = @(
    'ActivityHistory', 'AdvertisingID', 'BingSearch', 'LockWidgets',
    'OneDriveFileExplorerAd', 'Powershell7Telemetry', 'SearchHighlights',
    'SettingsSuggestedContent', 'StartRecommendationsTips', 'TailoredExperiences',
    'TaskbarEndTask', 'TaskbarWidgets', 'WebSearch',
    'DiagnosticDataLevel', 'FeedbackFrequency', 'TaskbarSearch'
)

# Functions that are in the curated Basic preset (superset of Minimal)
$safeFunctions = @(
    $minimalFunctions + @(
        'CheckWinGet', 'CreateRestorePoint', 'ExplorerAutoDiscovery',
        'FileExtensions', 'LanguageListAccess', 'MapUpdates',
        'MergeConflicts', 'NewsInterests', 'PreventEdgeShortcutCreation',
        'SharedExperiences', 'StartAccountNotifications', 'TaskViewButton',
        'UnpinTaskbarShortcuts', 'Update-DesktopRegistry', 'Update-Powershell',
        'UseStoreOpenWith', 'WiFiSense', 'WPBT'
    )
) | Select-Object -Unique

# Functions that are in the curated Balanced preset (superset of Basic)
$balancedFunctions = @(
    $safeFunctions + @(
        'Camera', 'ClipboardHistory', 'DiagTrackService', 'FastStartup',
        'LocationTracking', 'MaintenanceWakeUp', 'Microphone',
        'NTFSLastAccess', 'ScheduledTasks', 'SleepTimeout',
        'SpeechRecognition', 'AppSuggestions', 'UpdateDriver', 'UpdateRestart'
    )
) | Select-Object -Unique

# Functions explicitly excluded from Balanced (app-specific, opinionated)
$balancedExclusions = @(
    'AdobeNetBlock', 'Block-AdobeNetwork', 'Block-RazerNetwork',
    'RazerNetBlock', 'Debloat-Brave', 'Debloat-Edge',
    'AeroShake', 'DisableAeroShake'
)

# Tags/names that suggest a restart is needed
$restartKeywords = @(
    'restart', 'reboot', 'shutdown', 'boot', 'startup',
    'driver', 'kernel', 'memory integrity', 'credential guard',
    'secure boot', 'bitlocker', 'hypervisor', 'vbs',
    'explorer restart', 'logoff', 'sign out'
)

# Functions known to require restart
$restartFunctions = @(
    'GPUScheduling', 'FastStartup', 'CIMemoryIntegrity',
    'LocalSecurityAuthority', 'Protect-OS', 'WindowsSandbox',
    'DefenderAppGuard', 'VirtualizationBasedSecurity',
    'Disable-IPv6', 'NTFSLastAccess', 'LanmanWorkstationGuestAuthPolicy'
)

# Conservative backfill for reviewed gaming-safe functions only.
# Keep this explicit so the helper does not guess scenario metadata for unrelated tweaks.
$conservativeGamingMetadataMap = @{
    'GPUScheduling' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'competitive', 'streaming')
        GamingPreviewGroup = 'Core Performance'
        TroubleshootingOnly = $false
    }
    'XboxGameBar' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'casual', 'streaming')
        GamingPreviewGroup = 'Xbox & Overlay'
        TroubleshootingOnly = $false
    }
    'XboxGameTips' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'casual', 'competitive', 'streaming')
        GamingPreviewGroup = 'Background & Notifications'
        TroubleshootingOnly = $false
    }
    'FullscreenOptimizations' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'troubleshooting')
        GamingPreviewGroup = 'Compatibility & Troubleshooting'
        TroubleshootingOnly = $true
    }
    'MultiplaneOverlay' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'competitive', 'troubleshooting')
        GamingPreviewGroup = 'Compatibility & Troubleshooting'
        TroubleshootingOnly = $false
    }
    'NetworkAdaptersSavePower' = @{
        RecoveryLevel = 'Direct'
        ScenarioTags = @('gaming', 'troubleshooting', 'networking', 'performance')
        GamingPreviewGroup = 'Compatibility & Troubleshooting'
        TroubleshootingOnly = $true
    }
}

function Get-RequiresRestart {
    param([hashtable]$Entry)

    $func = [string]$Entry.Function
    if ($func -in $restartFunctions) { return $true }

    $searchText = @(
        [string]$Entry.Description,
        [string]$Entry.Detail,
        [string]$Entry.Name,
        ($Entry.Tags -join ' ')
    ) -join ' '

    foreach ($kw in $restartKeywords) {
        if ($searchText -match [regex]::Escape($kw)) { return $true }
    }

    return $false
}

function Get-PresetTier {
    param([hashtable]$Entry)

    $func = [string]$Entry.Function
    $risk = [string]$Entry.Risk

    # Explicit exclusions from Balanced
    if ($func -in $balancedExclusions) {
        if ($risk -eq 'High') { return 'Advanced' }
        return $null  # Omitted - not in any preset
    }

    if ($func -in $minimalFunctions) { return 'Minimal' }
    if ($func -in $safeFunctions) { return 'Safe' }
    if ($func -in $balancedFunctions) { return 'Balanced' }

    # Auto-assign based on risk
    switch ($risk) {
        'Low'    { return 'Safe' }
        'Medium' {
            # Medium-risk: check if it's opinionated or app-specific
            $tags = @($Entry.Tags)
            $name = [string]$Entry.Name
            $isAppSpecific = ($tags -contains 'edge' -or $tags -contains 'brave' -or
                             $tags -contains 'adobe' -or $tags -contains 'razer' -or
                             $name -match 'Edge|Brave|Adobe|Razer')
            $isOpinionated = ($tags -contains 'shell' -or $tags -contains 'aero' -or
                             $name -match 'Aero\s*Shake|Folder.*Behavior')
            $isIrreversible = ($Entry.ContainsKey('Restorable') -and $Entry.Restorable -eq $false)

            if ($isAppSpecific -or $isOpinionated -or $isIrreversible) {
                return 'Advanced'
            }
            return 'Balanced'
        }
        'High'   { return 'Advanced' }
        default  { return 'Safe' }
    }
}

function Get-WhyThisMatters {
    param([hashtable]$Entry)

    $name = [string]$Entry.Name
    $desc = [string]$Entry.Description
    $detail = [string]$Entry.Detail
    $risk = [string]$Entry.Risk

    # Build context-aware explanation
    $parts = @()

    # Use Detail if available (it's usually the most informative)
    if (-not [string]::IsNullOrWhiteSpace($detail)) {
        $parts += $detail
    }
    elseif (-not [string]::IsNullOrWhiteSpace($desc)) {
        $parts += $desc
    }

    # Add risk context
    if ($risk -eq 'High') {
        $parts += 'This is a high-risk change that may be difficult or impossible to reverse.'
    }
    elseif ($risk -eq 'Medium') {
        $parts += 'This change carries moderate risk and may affect some workflows.'
    }

    $result = ($parts -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($result)) {
        $result = "Controls the $name setting on your system."
    }

    return $result
}

function Test-HasConservativeGamingMetadataValue {
    param(
        [hashtable]$Entry,
        [string]$FieldName
    )

    $func = [string]$Entry.Function
    if ([string]::IsNullOrWhiteSpace($func)) { return $false }
    if (-not $conservativeGamingMetadataMap.ContainsKey($func)) { return $false }
    return $conservativeGamingMetadataMap[$func].ContainsKey($FieldName)
}

function Get-ConservativeGamingMetadataValue {
    param(
        [hashtable]$Entry,
        [string]$FieldName
    )

    if (-not (Test-HasConservativeGamingMetadataValue -Entry $Entry -FieldName $FieldName))
    {
        return $null
    }

    return $conservativeGamingMetadataMap[[string]$Entry.Function][$FieldName]
}

$totalEntries = 0
$totalModified = 0

foreach ($file in $jsonFiles) {
    $jsonText = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $data = $jsonText | ConvertFrom-Json

    if (-not $data.Entries) {
        # Write-Host: intentional — test/tooling console output
        Write-Host "  Skipping $($file.Name) - no Entries array" -ForegroundColor Yellow
        continue
    }

    $modified = $false
    $entryCount = $data.Entries.Count

    foreach ($entry in $data.Entries) {
        $totalEntries++
        $entryHash = @{}
        $entry.PSObject.Properties | ForEach-Object { $entryHash[$_.Name] = $_.Value }

        $changed = $false

        # Add Impact
        if (-not $entry.PSObject.Properties['Impact']) {
            $impactValue = switch ([string]$entry.Risk) {
                'High'   { 'High' }
                'Medium' { 'Medium' }
                default  { 'Low' }
            }
            $entry | Add-Member -MemberType NoteProperty -Name 'Impact' -Value $impactValue
            $changed = $true
        }

        # Add Safe - defaults to (Risk -eq 'Low') but respects explicit overrides.
        # To mark a non-Low-risk entry as safe (e.g., a well-understood Medium toggle),
        # set "Safe": true directly in the manifest JSON before running this tool.
        if (-not $entry.PSObject.Properties['Safe']) {
            $safeValue = ([string]$entry.Risk -eq 'Low')
            $entry | Add-Member -MemberType NoteProperty -Name 'Safe' -Value $safeValue
            $changed = $true
        }

        # Add RequiresRestart
        if (-not $entry.PSObject.Properties['RequiresRestart']) {
            $restartValue = Get-RequiresRestart -Entry $entryHash
            $entry | Add-Member -MemberType NoteProperty -Name 'RequiresRestart' -Value $restartValue
            $changed = $true
        }

        # Add WhyThisMatters
        if (-not $entry.PSObject.Properties['WhyThisMatters']) {
            $whyValue = Get-WhyThisMatters -Entry $entryHash
            $entry | Add-Member -MemberType NoteProperty -Name 'WhyThisMatters' -Value $whyValue
            $changed = $true
        }

        # Add PresetTier
        if (-not $entry.PSObject.Properties['PresetTier']) {
            $tierValue = Get-PresetTier -Entry $entryHash
            $entry | Add-Member -MemberType NoteProperty -Name 'PresetTier' -Value $tierValue
            $changed = $true
        }

        # Add RecoveryLevel only for explicitly reviewed gaming-safe entries.
        $needsRecoveryLevel = (-not $entry.PSObject.Properties['RecoveryLevel']) -or [string]::IsNullOrWhiteSpace([string]$entry.RecoveryLevel)
        if ($needsRecoveryLevel -and (Test-HasConservativeGamingMetadataValue -Entry $entryHash -FieldName 'RecoveryLevel')) {
            $entry | Add-Member -MemberType NoteProperty -Name 'RecoveryLevel' -Value (Get-ConservativeGamingMetadataValue -Entry $entryHash -FieldName 'RecoveryLevel') -Force
            $changed = $true
        }

        # Add ScenarioTags only for reviewed gaming-safe entries to avoid broad guesses.
        $needsScenarioTags = (-not $entry.PSObject.Properties['ScenarioTags']) -or $null -eq $entry.ScenarioTags -or @($entry.ScenarioTags).Count -eq 0
        if ($needsScenarioTags -and (Test-HasConservativeGamingMetadataValue -Entry $entryHash -FieldName 'ScenarioTags')) {
            $entry | Add-Member -MemberType NoteProperty -Name 'ScenarioTags' -Value @(Get-ConservativeGamingMetadataValue -Entry $entryHash -FieldName 'ScenarioTags') -Force
            $changed = $true
        }

        # Add GamingPreviewGroup only for the explicit Game Mode allowlist set.
        $needsGamingPreviewGroup = (-not $entry.PSObject.Properties['GamingPreviewGroup']) -or [string]::IsNullOrWhiteSpace([string]$entry.GamingPreviewGroup)
        if ($needsGamingPreviewGroup -and (Test-HasConservativeGamingMetadataValue -Entry $entryHash -FieldName 'GamingPreviewGroup')) {
            $entry | Add-Member -MemberType NoteProperty -Name 'GamingPreviewGroup' -Value (Get-ConservativeGamingMetadataValue -Entry $entryHash -FieldName 'GamingPreviewGroup') -Force
            $changed = $true
        }

        # Add TroubleshootingOnly only when the reviewed map explicitly says so.
        $needsTroubleshootingOnly = (-not $entry.PSObject.Properties['TroubleshootingOnly']) -or $null -eq $entry.TroubleshootingOnly
        if ($needsTroubleshootingOnly -and (Test-HasConservativeGamingMetadataValue -Entry $entryHash -FieldName 'TroubleshootingOnly')) {
            $entry | Add-Member -MemberType NoteProperty -Name 'TroubleshootingOnly' -Value ([bool](Get-ConservativeGamingMetadataValue -Entry $entryHash -FieldName 'TroubleshootingOnly')) -Force
            $changed = $true
        }

        # Add CompatibilitySensitivity - defaults to 'Low' if missing
        if (-not $entry.PSObject.Properties['CompatibilitySensitivity']) {
            $entry | Add-Member -MemberType NoteProperty -Name 'CompatibilitySensitivity' -Value 'Low'
            $changed = $true
        }

        if ($changed) {
            $modified = $true
            $totalModified++
        }
    }

    if ($modified) {
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would update $($file.Name) ($entryCount entries)" -ForegroundColor Cyan
        }
        else {
            $outputJson = $data | ConvertTo-Json -Depth 10
            # Ensure consistent formatting
            [System.IO.File]::WriteAllText($file.FullName, $outputJson + "`n", [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Updated $($file.Name) ($entryCount entries)" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  No changes needed for $($file.Name)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Total entries processed: $totalEntries" -ForegroundColor White
Write-Host "Total entries modified:  $totalModified" -ForegroundColor White
if ($DryRun) {
    Write-Host "(DRY RUN - no files were written)" -ForegroundColor Yellow
}
