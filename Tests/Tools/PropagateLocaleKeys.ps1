# One-shot propagation script for the 35 regression locale keys
# (todo.md P3 #22). Inserts each missing key into every locale .json under
# Localizations/, picking translations from the localization bundle
# /Localizations/<de-DE|es-ES|fr-FR|hu-HU|it-IT|pl-PL|pt-BR|ru-RU|tr-TR|uk-UA|
# zh-CN>/Base.psd1 where the Baseline locale has a matching counterpart, and
# falling back to the en-US value otherwise. Output preserves the alphabetical
# 2-space-indented shape of the existing locale files.

[CmdletBinding()]
param (
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$keys = @(
    'BitLockerAutomaticEncryption', 'BitLockerInOperation',
    'CodeCompilationFailedWarning', 'ControlledFolderAccessEnabledWarning',
    'HostsWarning', 'UnsupportedArchitecture', 'NoHomeWindowsEditionSupport',
    'gpeditNotSupported', 'GeoIdNotSupported', 'LocationServicesDisabled',
    'NoSupportedNetworkAdapters', 'JSONNotValid', 'DotSourcedWarning',
    'CopilotPCSupport', 'CustomStartMenu', 'SearchHighlightsDisabled',
    'WidgetNotInstalled', 'PhotosNotInstalled',
    'OneDriveAccountWarning', 'OneDriveInstalled', 'OneDriveNotInstalled',
    'InstallNotification', 'UninstallNotification', 'PackageIsInstalled',
    'PackageNotInstalled',
    'NoOptionalFeatures', 'NoScheduledTasks', 'NoUWPApps', 'NoWindowsFeatures',
    'ProgIdNotExists', 'ProgramPathNotExists', 'ScheduledTaskCreatedByAnotherUser',
    'ThirdPartyArchiverInstalled', 'ThirdPartyAVInstalled',
    'UserFolderMoveSkipped'
)

# Maps Baseline locale code (the .json basename) to a localized dir name
# when a translation is available there. Codes not listed fall back to en-US.
$baselineToLocalized = @{
    'de'      = 'de-DE'
    'es'      = 'es-ES'
    'es-MX'   = 'es-ES'
    'fr'      = 'fr-FR'
    'fr-CA'   = 'fr-FR'
    'hu'      = 'hu-HU'
    'it'      = 'it-IT'
    'pl'      = 'pl-PL'
    'pt'      = 'pt-BR'
    'pt-BR'   = 'pt-BR'
    'ru'      = 'ru-RU'
    'tr'      = 'tr-TR'
    'uk'      = 'uk-UA'
    'zh-Hans' = 'zh-CN'
    'zh-Hant' = 'zh-CN'
}

$localizedRoot = Join-Path $RepoRoot 'Localizations'
$baselineLocalesRoot = Join-Path $RepoRoot 'Localizations'

# Read a localization .psd1 — they are `ConvertFrom-StringData` literals so the
# hashtable parses cleanly via Import-LocalizedData semantics. We simulate
# that with manual line-parsing because Import-LocalizedData wants culture
# folders to match $PSUICulture exactly.
function Read-LocalizedPsd1 {
    param ([Parameter(Mandatory)][string]$Path)
    $h = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $h }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -notmatch "(?s)@'(.*)'@") { return $h }
    $body = $matches[1]
    foreach ($line in ($body -split "`r?`n")) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim -notmatch '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
        $k = $matches[1]
        $v = $matches[2]
        # ConvertFrom-StringData unescapes `\n` and `\\` in psd1 here-strings.
        $v = $v -replace '\\n', "`n"
        $v = $v -replace '\\\\', '\'
        $h[$k] = $v
    }
    return $h
}

# Source of truth: en-US localized values. Used as fallback for any locale that
# the bundle does not translate.
$localizedEnUs = Read-LocalizedPsd1 -Path (Join-Path $localizedRoot 'en-US\Base.psd1')

# Pre-load every supported locale we care about.
$localizedTables = @{ 'en-US' = $localizedEnUs }
foreach ($code in ($baselineToLocalized.Values | Sort-Object -Unique)) {
    $p = Join-Path $localizedRoot "$code\Base.psd1"
    $localizedTables[$code] = Read-LocalizedPsd1 -Path $p
}

function Get-LocalizedValueForLocale {
    param (
        [Parameter(Mandatory)][string]$BaselineLocale,
        [Parameter(Mandatory)][string]$Key
    )
    $localizedCode = $baselineToLocalized[$BaselineLocale]
    if ($localizedCode -and $localizedTables.ContainsKey($localizedCode)) {
        $t = $localizedTables[$localizedCode]
        if ($t.Contains($Key) -and -not [string]::IsNullOrWhiteSpace([string]$t[$Key])) {
            return [string]$t[$Key]
        }
    }
    if ($localizedEnUs.Contains($Key)) { return [string]$localizedEnUs[$Key] }
    return $null
}

# JSON-escape a string the same way the existing locale files are written
# (uses ConvertTo-Json's primitive serializer, which produces a quoted form).
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
$missingFromLocalized = [System.Collections.Generic.List[string]]::new()

foreach ($d in $dirs) {
    $jsonFile = Get-ChildItem $d.FullName -Filter '*.json' | Select-Object -First 1
    if (-not $jsonFile) { continue }
    $code = $jsonFile.BaseName

    $raw = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8
    # Use [ordered] hashtable so we can mutate without losing keys; we re-sort
    # at write time anyway.
    $tmp = $raw | ConvertFrom-Json
    $map = [ordered]@{}
    foreach ($p in $tmp.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }

    $added = 0
    foreach ($key in $keys) {
        if ($map.Contains($key)) { continue }
        $val = Get-LocalizedValueForLocale -BaselineLocale $code -Key $key
        if ($null -eq $val) {
            $missingFromLocalized.Add(("$code/$key")) | Out-Null
            continue
        }
        $map[$key] = $val
        $added++
    }

    if ($added -gt 0) {
        Write-LocaleJson -Path $jsonFile.FullName -Map $map
        $filesTouched++
        $totalAdded += $added
    }
}

Write-Output ("files_touched={0} keys_added={1} locale_misses={2}" -f $filesTouched, $totalAdded, $missingFromLocalized.Count)
if ($missingFromLocalized.Count -gt 0) {
    Write-Output 'first 10 locale misses:'
    foreach ($m in ($missingFromLocalized | Select-Object -First 10)) { Write-Output "  $m" }
}
