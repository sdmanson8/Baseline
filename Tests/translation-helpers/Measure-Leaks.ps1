<#
    Computes exact-English leak counts per non-English-variant locale.
    Writes a JSON report with per-locale leak counts plus exempt breakdown.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$LocalizationDir = Join-Path $RepoRoot 'Localizations'
$SourcePath      = Join-Path $LocalizationDir 'English (United States)\en-US.json'
$QAPath          = Join-Path $RepoRoot 'Tools\Test-LocalizationQA.ps1'
$ExemptPath      = Join-Path $LocalizationDir 'english_exempt_keys.json'

# English-variant locales to ignore (they are expected to hold English)
$EnglishVariants = @(
    'en-AE.json','en-AU.json','en-BZ.json','en-CA.json','en-GB.json','en-IE.json',
    'en-IN.json','en-JM.json','en-MV.json','en-MY.json','en-NZ.json','en-PH.json',
    'en-SG.json','en-TT.json','en-US.json','en-ZA.json','en-ZW.json','en-029.json'
)

# Parse QA script to pull its ExemptKeys + InvariantValues arrays
# The file has two ExemptKeys blocks: the first hardcoded list, second re-merges with JSON.
$QAText = Get-Content -LiteralPath $QAPath -Raw
$ExemptFromScript = @()
$firstBlock = [regex]::Match($QAText, '\$ExemptKeys\s*=\s*@\(([\s\S]*?)\r?\n\)')
if ($firstBlock.Success) {
    $ExemptFromScript = [regex]::Matches($firstBlock.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
}

$InvariantMatch = [regex]::Match($QAText, "\`$InvariantValues.*?@\(([^\)]*?)\)")
$InvariantValues = @()
if ($InvariantMatch.Success) {
    $InvariantValues = [regex]::Matches($InvariantMatch.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
}

# Merge exempt keys file (top-level object -> keys)
$ExemptFromFile = @()
if (Test-Path $ExemptPath) {
    $json = Get-Content -LiteralPath $ExemptPath -Raw | ConvertFrom-Json
    if ($json.PSObject -and $json.PSObject.Properties) {
        $ExemptFromFile = $json.PSObject.Properties.Name
    }
}

$ExemptSet = @{}
foreach ($k in @($ExemptFromScript + $ExemptFromFile) | Sort-Object -Unique) { $ExemptSet[$k] = $true }

$InvariantSet = @{}
foreach ($v in $InvariantValues) { $InvariantSet[$v] = $true }

# Load source
$SourceData = Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json
$SourceMap = @{}
foreach ($p in $SourceData.PSObject.Properties) { $SourceMap[$p.Name] = [string]$p.Value }

# Discover all locale files
$LocaleFiles = Get-ChildItem -LiteralPath $LocalizationDir -Recurse -Filter '*.json' -File |
    Where-Object { $_.Name -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\.json$' } |
    Where-Object { $EnglishVariants -notcontains $_.Name } |
    Sort-Object Name

$NonExemptKeys = @($SourceMap.Keys | Where-Object { -not $ExemptSet.ContainsKey($_) })

$Report = [ordered]@{
    generated = (Get-Date -Format 'o')
    source_key_count = $SourceMap.Count
    exempt_key_count = $ExemptSet.Count
    non_exempt_key_count = $NonExemptKeys.Count
    non_exempt_keys = @($NonExemptKeys | Sort-Object)
    script_exempt_count = $ExemptFromScript.Count
    file_exempt_count = $ExemptFromFile.Count
    invariant_value_count = $InvariantSet.Count
    english_variants_skipped = $EnglishVariants
    total_leak_count = 0
    total_exempt_matches = 0
    locale_count = $LocaleFiles.Count
    locales = [ordered]@{}
}

foreach ($f in $LocaleFiles) {
    try {
        $localeData = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
    } catch {
        $Report.locales[$f.Name] = [ordered]@{ error = "invalid_json: $($_.Exception.Message)" }
        continue
    }
    $map = @{}
    foreach ($p in $localeData.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }

    $leakCount = 0
    $exemptMatchCount = 0
    $invariantMatchCount = 0
    $missingCount = 0
    $sampleKeys = New-Object System.Collections.Generic.List[string]

    foreach ($key in $SourceMap.Keys) {
        if (-not $map.ContainsKey($key)) { $missingCount++; continue }
        $src = $SourceMap[$key]
        $loc = $map[$key]
        if ($loc -ceq $src) {
            if ($ExemptSet.ContainsKey($key)) {
                $exemptMatchCount++
            } elseif ($InvariantSet.ContainsKey($src)) {
                $invariantMatchCount++
            } else {
                $leakCount++
                if ($sampleKeys.Count -lt 10) { $sampleKeys.Add($key) | Out-Null }
            }
        }
    }

    $Report.locales[$f.Name] = [ordered]@{
        path = $f.FullName.Substring($RepoRoot.Length).TrimStart('\','/')
        leak_count = $leakCount
        exempt_matches = $exemptMatchCount
        invariant_matches = $invariantMatchCount
        missing_keys = $missingCount
        sample_leak_keys = @($sampleKeys)
    }
    $Report.total_leak_count += $leakCount
    $Report.total_exempt_matches += $exemptMatchCount
}

# Rank by leak count
$Top = $Report.locales.GetEnumerator() |
    Where-Object { $_.Value.leak_count -gt 0 } |
    Sort-Object { -[int]$_.Value.leak_count } |
    Select-Object -First 10 |
    ForEach-Object {
        [ordered]@{
            file = $_.Key
            leak_count = $_.Value.leak_count
        }
    }
$Report.top_10_by_leaks = @($Top)

if (-not $OutputPath) {
    $OutputPath = Join-Path $RepoRoot 'Tests\leak-report-before.json'
}
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host "=== Leak Scoping Report ==="
Write-Host ("Source keys        : {0}" -f $Report.source_key_count)
Write-Host ("Exempt keys        : {0}" -f $Report.exempt_key_count)
Write-Host ("Invariant values   : {0}" -f $Report.invariant_value_count)
Write-Host ("Locales scanned    : {0}" -f $Report.locale_count)
Write-Host ("Total leak count   : {0}" -f $Report.total_leak_count)
Write-Host ""
Write-Host "Top 10 locales by leak count:"
foreach ($t in $Top) {
    Write-Host ("  {0,-20} {1}" -f $t.file, $t.leak_count)
}
Write-Host ""
Write-Host ("Report written to: {0}" -f $OutputPath)
