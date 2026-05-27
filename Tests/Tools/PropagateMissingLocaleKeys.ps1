# Propagation script: ensure every locale .json under Localizations/ contains
# every key present in en-US.json. Missing keys are filled with the en-US value
# verbatim (English fallback) so the LocalizationIntegrity "preserves every
# source key" test passes. Translators can replace the English fallbacks later.
#
# This is the broader companion to PropagateLocaleKeys.ps1: that script
# only handled 35 specific localized keys with proper translations from the
# localization bundle. This script catches every other gap
# (e.g., the 31 GuiApps_*/Nav_* keys added in commit d796432 but never
# back-filled to other locales).

[CmdletBinding()]
param (
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$baselineLocalesRoot = Join-Path $RepoRoot 'Localizations'
$enUsPath = Join-Path $baselineLocalesRoot 'English (United States)\en-US.json'

$enUsRaw = Get-Content -LiteralPath $enUsPath -Raw -Encoding UTF8
$enUsObj = $enUsRaw | ConvertFrom-Json
$enUsMap = [ordered]@{}
foreach ($p in $enUsObj.PSObject.Properties) { $enUsMap[$p.Name] = [string]$p.Value }

function ConvertTo-LocaleJsonString {
    param ([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function Write-LocaleJson {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Map
    )
    $sortedKeys = ($Map.Keys | Sort-Object -Culture 'en-US')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('{')
    for ($i = 0; $i -lt $sortedKeys.Count; $i++) {
        $k = $sortedKeys[$i]
        $jsonKey = ConvertTo-LocaleJsonString $k
        $jsonVal = ConvertTo-LocaleJsonString ([string]$Map[$k])
        $sep = if ($i -lt ($sortedKeys.Count - 1)) { ',' } else { '' }
        [void]$sb.AppendLine(('  {0}: {1}{2}' -f $jsonKey, $jsonVal, $sep))
    }
    [void]$sb.Append('}')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $utf8NoBom)
}

$dirs = Get-ChildItem -LiteralPath $baselineLocalesRoot -Directory
$totalAdded = 0
$filesTouched = 0

foreach ($d in $dirs) {
    $jsonFile = Get-ChildItem $d.FullName -Filter '*.json' | Select-Object -First 1
    if (-not $jsonFile) { continue }
    if ($jsonFile.FullName -eq $enUsPath) { continue }

    $raw = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8
    $tmp = $raw | ConvertFrom-Json
    $map = [ordered]@{}
    foreach ($p in $tmp.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }

    $added = 0
    foreach ($key in $enUsMap.Keys) {
        if ($map.Contains($key)) { continue }
        $map[$key] = [string]$enUsMap[$key]
        $added++
    }

    if ($added -gt 0) {
        Write-LocaleJson -Path $jsonFile.FullName -Map $map
        $filesTouched++
        $totalAdded += $added
    }
}

Write-Output ("files_touched={0} keys_added={1}" -f $filesTouched, $totalAdded)
