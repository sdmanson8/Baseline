<#
    .SYNOPSIS
    Validates localization JSON files against the English baseline.

    .DESCRIPTION
    Checks key parity, placeholder parity, and exact-English leakage across
    the JSON localization files in Localizations/. Exact matches for a small
    set of invariant values are allowed. English variants are still scanned
    for key and placeholder parity, and unfinished locales can also be kept
    out of the failure path.
#>

[CmdletBinding()]
param (
    [string]$RepoRoot,
    [string[]]$InvariantValues = @('No', 'OK', 'Wi-Fi', 'Bluetooth', 'OneDrive', 'AI', 'Defender', 'HDR', 'Office', 'RPC', 'UAC', 'UI', 'Windows Terminal'),
    [string[]]$UnfinishedLocales = @(),
    [string[]]$EnglishVariantLocales = @(),
    [string]$TerminologyPolicyPath,
    [string]$LocalizationSchemaPath,
    [string]$AuditReportPath,
    [switch]$EnforceTerminologyPolicy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepoRoot))
{
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptRoot) -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path))
    {
        $scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    }
    if ([string]::IsNullOrWhiteSpace($scriptRoot))
    {
        throw 'Unable to resolve the localization QA script root.'
    }

    $RepoRoot = Split-Path -Path $scriptRoot -Parent
}

$SourceFileName = 'en-US.json'
$LocalizationDir = Join-Path $RepoRoot 'Localizations'
$SkipSourceFiles = @($SourceFileName)
$LocaleFilePattern = '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\.json$'

<#
    .SYNOPSIS
#>

function Resolve-LocalizationFilePath
{
    param(
        [Parameter(Mandatory)]
        [string]$LocalizationRoot,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    $matches = @(
        Get-ChildItem -LiteralPath $LocalizationRoot -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue
    )

    if ($matches.Count -eq 1)
    {
        return $matches[0].FullName
    }

    if ($matches.Count -eq 0)
    {
        throw "Localization file '$FileName' not found under '$LocalizationRoot'."
    }

    throw "Multiple localization files named '$FileName' were found under '$LocalizationRoot'."
}

if ($EnglishVariantLocales.Count -eq 0)
{
    $EnglishVariantLocales = @(
        Get-ChildItem -LiteralPath $LocalizationDir -Recurse -Filter 'en-*.json' -File |
            Where-Object { $_.Name -ne $SourceFileName } |
            Sort-Object Name |
            ForEach-Object { $_.Name }
    )
}
else
{
    $EnglishVariantLocales = @(
        $EnglishVariantLocales |
            Where-Object { $_ -and $_ -ne $SourceFileName } |
            Sort-Object -Unique
    )
}

$SourcePath = Resolve-LocalizationFilePath -LocalizationRoot $LocalizationDir -FileName $SourceFileName

# Exempt list intentionally empty: every non-English locale should translate every key.
$ExemptKeys = @()

$ExemptKeysPath = Join-Path $LocalizationDir 'english_exempt_keys.json'
if (Test-Path -LiteralPath $ExemptKeysPath -PathType Leaf)
{
    $ExemptKeyData = Get-Content -LiteralPath $ExemptKeysPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($ExemptKeyData -is [System.Collections.IDictionary])
    {
        $ExemptKeys += @($ExemptKeyData.Keys)
    }
    elseif ($ExemptKeyData -is [pscustomobject])
    {
        $props = @($ExemptKeyData.PSObject.Properties)
        if ($props.Count -gt 0)
        {
            $ExemptKeys += @($props | ForEach-Object { $_.Name })
        }
    }
    else
    {
        $ExemptKeys += @($ExemptKeyData)
    }
}

$ExemptKeys = @(
    $ExemptKeys |
        Where-Object { $_ } |
        Sort-Object -Unique
)

<#
    .SYNOPSIS
#>

function Get-LocalizationStringMap
{
    param(
        [Parameter(Mandatory)]
        [object]$JsonObject
    )

    $map = @{}
    foreach ($property in $JsonObject.PSObject.Properties)
    {
        $map[$property.Name] = $property.Value
    }

    return $map
}

<#
    .SYNOPSIS
#>

function Get-LocalizationPlaceholderTokens
{
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return [regex]::Matches($Value, '\{[0-9]+\}') | ForEach-Object { $_.Value }
}

<#
    .SYNOPSIS
#>
function Test-LocalizationPlaceholderParity
{
    param(
        [Parameter(Mandatory)]
        [string]$SourceValue,
        [Parameter(Mandatory)]
        [string]$LocaleValue
    )

    $sourceTokens = @(Get-LocalizationPlaceholderTokens -Value $SourceValue | Sort-Object)
    $localeTokens = @(Get-LocalizationPlaceholderTokens -Value $LocaleValue | Sort-Object)

    return (@($sourceTokens) -join '|') -eq (@($localeTokens) -join '|')
}

<#
    .SYNOPSIS
#>

function Test-LocalizationFormatString
{
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $argumentCount = 0
    $matches = @([regex]::Matches($Value, '\{([0-9]+)(?:,[^{}]+)?(?::[^{}]+)?\}'))
    if ($matches.Count -gt 0)
    {
        $maxIndex = 0
        foreach ($match in $matches)
        {
            $index = [int]$match.Groups[1].Value
            if ($index -gt $maxIndex)
            {
                $maxIndex = $index
            }
        }
        $argumentCount = $maxIndex + 1
    }

    $formatArguments = New-Object object[] $argumentCount
    for ($i = 0; $i -lt $argumentCount; $i++)
    {
        $formatArguments[$i] = $i
    }

    try
    {
        [void][string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $Value, $formatArguments)
        return [pscustomobject]@{
            IsValid = $true
            Message = $null
        }
    }
    catch
    {
        return [pscustomobject]@{
            IsValid = $false
            Message = $_.Exception.Message
        }
    }
}

<#
    .SYNOPSIS
#>

function Get-LocalizationKeySetHash
{
    param(
        [Parameter(Mandatory)]
        [object[]]$Keys
    )

    $sortedKeys = [string[]]@($Keys | ForEach-Object { [string]$_ })
    [System.Array]::Sort($sortedKeys, [System.StringComparer]::Ordinal)
    $payload = [System.Text.Encoding]::UTF8.GetBytes(($sortedKeys -join "`n"))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $hashBytes = $sha256.ComputeHash($payload)
    }
    finally
    {
        $sha256.Dispose()
    }

    return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

<#
    .SYNOPSIS
#>

function Get-LocaleContentHash
{
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $hashBytes = $sha256.ComputeHash($bytes)
    }
    finally
    {
        $sha256.Dispose()
    }

    return (($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

<#
    .SYNOPSIS
#>

function Get-LocalizationTermMatchKeys
{
    param(
        [Parameter(Mandatory)]
        [object]$JsonObject,

        [Parameter(Mandatory)]
        [string]$TermToken
    )

    $matchKeys = [System.Collections.Generic.List[string]]::new()
    $entries = @()
    if ($JsonObject -is [System.Collections.IDictionary])
    {
        $entries = @($JsonObject.GetEnumerator())
    }
    else
    {
        $entries = @($JsonObject.PSObject.Properties)
    }

    foreach ($property in $entries)
    {
        if ($property.Value -isnot [string])
        {
            continue
        }

        if ([string]$property.Value -and ([string]$property.Value).IndexOf($TermToken, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            $matchKeys.Add($property.Name)
        }
    }

    return @($matchKeys)
}

<#
    .SYNOPSIS
#>

function Get-LocalizationTerminologyPolicy
{
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path))
    {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

<#
    .SYNOPSIS
#>

function Get-LocalizationSchema
{
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path))
    {
        throw 'Localization schema path was not provided.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "Missing localization schema file: $Path"
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf))
{
    throw "Missing source file: $SourcePath"
}

if (-not (Test-Path -LiteralPath $LocalizationDir -PathType Container))
{
    throw "Missing localization directory: $LocalizationDir"
}

$SourceMap = Get-LocalizationStringMap -JsonObject (Get-Content -LiteralPath $SourcePath -Raw | ConvertFrom-Json)
$SourceKeys = @($SourceMap.Keys)
$LocalizationSchema = Get-LocalizationSchema -Path $(if ($PSBoundParameters.ContainsKey('LocalizationSchemaPath')) { $LocalizationSchemaPath } else { Join-Path $LocalizationDir 'localization_schema.json' })
$SourceKeyHash = Get-LocalizationKeySetHash -Keys $SourceKeys

if (
    -not $LocalizationSchema.PSObject.Properties['key_count'] -or
    -not $LocalizationSchema.PSObject.Properties['hash_algorithm'] -or
    -not $LocalizationSchema.PSObject.Properties['key_hash']
)
{
    throw "Localization schema file is missing required fields: $(if ($PSBoundParameters.ContainsKey('LocalizationSchemaPath')) { $LocalizationSchemaPath } else { Join-Path $LocalizationDir 'localization_schema.json' })"
}

if ([string]$LocalizationSchema.hash_algorithm -ne 'sha256')
{
    throw "Unsupported localization schema hash algorithm: $([string]$LocalizationSchema.hash_algorithm)"
}

if ([int]$LocalizationSchema.key_count -ne $SourceKeys.Count -or [string]$LocalizationSchema.key_hash -ne $SourceKeyHash)
{
    throw ("Localization schema mismatch for source file {0}: expected {1} keys/{2}, found {3} keys/{4}" -f `
        $SourcePath,
        [int]$LocalizationSchema.key_count,
        [string]$LocalizationSchema.key_hash,
        $SourceKeys.Count,
        $SourceKeyHash)
}

$SourceLikeFiles = @($SourceFileName, 'en-GB.json')
foreach ($sourceLikeFile in $SourceLikeFiles)
{
    $sourceLikePath = Resolve-LocalizationFilePath -LocalizationRoot $LocalizationDir -FileName $sourceLikeFile

    $sourceLikeMap = if ($sourceLikeFile -eq $SourceFileName) { $SourceMap } else { Get-LocalizationStringMap -JsonObject (Get-Content -LiteralPath $sourceLikePath -Raw | ConvertFrom-Json) }
    $sourceLikeKeys = @($sourceLikeMap.Keys)
    $sourceLikeHash = Get-LocalizationKeySetHash -Keys $sourceLikeKeys
    if ([int]$LocalizationSchema.key_count -ne $sourceLikeKeys.Count -or $sourceLikeHash -ne $SourceKeyHash)
    {
        throw ("Localization source file {0} does not match the canonical key set" -f $sourceLikePath)
    }
}

$LocaleFiles = Get-ChildItem -LiteralPath $LocalizationDir -Recurse -Filter '*.json' -File | Where-Object {
    ($SkipSourceFiles -notcontains $_.Name) -and
    ($_.Name -match $LocaleFilePattern)
} | Sort-Object Name

$TerminologyPolicy = Get-LocalizationTerminologyPolicy -Path $(if ($PSBoundParameters.ContainsKey('TerminologyPolicyPath')) { $TerminologyPolicyPath } else { Join-Path $LocalizationDir 'terminology_policy.json' })
$TerminologyTerms = @()
if ($TerminologyPolicy -and $TerminologyPolicy.PSObject.Properties['terms'])
{
    $TerminologyTerms = @($TerminologyPolicy.terms | Where-Object { $_ -and $_.name -and $_.token -and $_.policy })
}

$Summary = [ordered]@{
    scanned_files = 0
    files_with_key_errors = 0
    files_with_placeholder_errors = 0
    files_with_format_errors = 0
    files_with_remaining_leaks = 0
    files_with_ignored_leaks = 0
    files_with_unfinished_leaks = 0
    files_with_english_variant_leaks = 0
    total_missing_keys = 0
    total_extra_keys = 0
    total_placeholder_errors = 0
    total_format_errors = 0
    total_remaining_leaks = 0
    total_ignored_leaks = 0
    total_unfinished_leaks = 0
    total_english_variant_leaks = 0
    source_key_count = $SourceKeys.Count
    source_key_hash = $SourceKeyHash
    duplicate_locale_groups = 0
    files_with_empty_strings = 0
    total_empty_strings = 0
}

$HasFailure = $false
$TerminologyAccumulators = [ordered]@{}
$TerminologyLocaleDetails = [System.Collections.Generic.List[object]]::new()
if ($TerminologyTerms.Count -gt 0)
{
    foreach ($term in $TerminologyTerms)
    {
        $TerminologyAccumulators[[string]$term.name] = [ordered]@{
            token = [string]$term.token
            policy = [string]$term.policy
            files_with_token = 0
            files_without_token = 0
            files_with_token_names = [System.Collections.Generic.List[string]]::new()
            files_without_token_names = [System.Collections.Generic.List[string]]::new()
            sample_matches = [ordered]@{}
        }
    }
}

Write-Host "`n=== Localization QA ===" -ForegroundColor Cyan

# --- Duplicate-content detection ---
# Group locale files by their byte-for-byte hash and warn about identical pairs.
$ContentHashMap = [ordered]@{}
foreach ($LocaleFile in $LocaleFiles)
{
    $hash = Get-LocaleContentHash -FilePath $LocaleFile.FullName
    if (-not $ContentHashMap.Contains($hash))
    {
        $ContentHashMap[$hash] = [System.Collections.Generic.List[string]]::new()
    }
    $ContentHashMap[$hash].Add($LocaleFile.Name)
}

foreach ($hash in $ContentHashMap.Keys)
{
    $group = @($ContentHashMap[$hash])
    if ($group.Count -gt 1)
    {
        $Summary.duplicate_locale_groups++
        $names = $group -join ', '
        Write-Host ("  [WARN] Duplicate locale content ({0} identical files): {1}" -f $group.Count, $names) -ForegroundColor Yellow
    }
}

foreach ($LocaleFile in $LocaleFiles)
{
    try
    {
        $LocaleMap = Get-LocalizationStringMap -JsonObject (Get-Content -LiteralPath $LocaleFile.FullName -Raw | ConvertFrom-Json)
    }
    catch
    {
        $HasFailure = $true
        Write-Host ("  [FAIL] {0} -- invalid JSON: {1}" -f $LocaleFile.Name, $_.Exception.Message)
        continue
    }

    $Summary.scanned_files++

    $MissingKeys = @($SourceKeys | Where-Object { -not $LocaleMap.ContainsKey($_) })
    $ExtraKeys = @($LocaleMap.Keys | Where-Object { -not $SourceMap.ContainsKey($_) })
    $PlaceholderErrors = New-Object System.Collections.Generic.List[object]
    $FormatErrors = New-Object System.Collections.Generic.List[object]
    $ExactLeaks = New-Object System.Collections.Generic.List[string]
    $EmptyStringKeys = New-Object System.Collections.Generic.List[string]

    foreach ($Key in $SourceKeys)
    {
        if (-not $LocaleMap.ContainsKey($Key))
        {
            continue
        }

        $SourceValue = $SourceMap[$Key]
        $LocaleValue = $LocaleMap[$Key]

        if (($SourceValue -is [string]) -and ($LocaleValue -is [string]))
        {
            if (-not (Test-LocalizationPlaceholderParity -SourceValue $SourceValue -LocaleValue $LocaleValue))
            {
                $PlaceholderErrors.Add([pscustomobject]@{
                    key = $Key
                    source_placeholders = @(Get-LocalizationPlaceholderTokens -Value $SourceValue)
                    locale_placeholders = @(Get-LocalizationPlaceholderTokens -Value $LocaleValue)
                })
            }

            $formatValidation = Test-LocalizationFormatString -Value $LocaleValue
            if (-not $formatValidation.IsValid)
            {
                $FormatErrors.Add([pscustomobject]@{
                    key = $Key
                    message = $formatValidation.Message
                })
            }

            if (
                $LocaleValue -ceq $SourceValue -and
                ($ExemptKeys -notcontains $Key) -and
                ($InvariantValues -notcontains $SourceValue)
            )
            {
                $ExactLeaks.Add($Key)
            }

            if ($SourceValue.Length -gt 0 -and $LocaleValue.Length -eq 0 -and ($ExemptKeys -notcontains $Key))
            {
                $EmptyStringKeys.Add($Key)
            }
        }
    }

    $IsUnfinished = $UnfinishedLocales -contains $LocaleFile.Name
    $IsEnglishVariant = $EnglishVariantLocales -contains $LocaleFile.Name
    $IsLeakIgnored = $IsUnfinished -or $IsEnglishVariant
    $RealLeakCount = if ($IsLeakIgnored) { 0 } else { $ExactLeaks.Count }

    $Summary.total_missing_keys += $MissingKeys.Count
    $Summary.total_extra_keys += $ExtraKeys.Count
    $Summary.total_placeholder_errors += $PlaceholderErrors.Count
    $Summary.total_format_errors += $FormatErrors.Count
    $Summary.total_remaining_leaks += $RealLeakCount
    $Summary.total_ignored_leaks += if ($IsLeakIgnored) { $ExactLeaks.Count } else { 0 }
    $Summary.total_unfinished_leaks += if ($IsUnfinished) { $ExactLeaks.Count } else { 0 }
    $Summary.total_english_variant_leaks += if ($IsEnglishVariant) { $ExactLeaks.Count } else { 0 }
    $Summary.total_empty_strings += $EmptyStringKeys.Count
    if ($IsEnglishVariant -and $ExactLeaks.Count -gt 0)
    {
        $Summary.files_with_english_variant_leaks++
    }
    if ($EmptyStringKeys.Count -gt 0)
    {
        $Summary.files_with_empty_strings++
    }

    if ($TerminologyTerms.Count -gt 0)
    {
        $localeTermMatches = [ordered]@{}
        foreach ($term in $TerminologyTerms)
        {
            $termName = [string]$term.name
            $termToken = [string]$term.token
            $termPolicy = [string]$term.policy
            $matchKeys = @(Get-LocalizationTermMatchKeys -JsonObject $LocaleMap -TermToken $termToken)
            $matchCount = $matchKeys.Count

            $localeTermMatches[$termName] = [ordered]@{
                token = $termToken
                policy = $termPolicy
                matched_keys = $matchKeys
                match_count = $matchCount
            }

            if (-not $IsLeakIgnored)
            {
                $termAccumulator = $TerminologyAccumulators[$termName]
                if ($matchCount -gt 0)
                {
                    $termAccumulator.files_with_token++
                    $termAccumulator.files_with_token_names.Add($LocaleFile.Name)
                    $termAccumulator.sample_matches[$LocaleFile.Name] = $matchKeys
                }
                else
                {
                    $termAccumulator.files_without_token++
                    $termAccumulator.files_without_token_names.Add($LocaleFile.Name)
                }
            }
        }

        $TerminologyLocaleDetails.Add([pscustomobject]@{
            file = $LocaleFile.Name
            is_unfinished = $IsUnfinished
            is_english_variant = $IsEnglishVariant
            is_ignored = $IsLeakIgnored
            term_matches = $localeTermMatches
        })
    }

    if ($MissingKeys.Count -gt 0 -or $ExtraKeys.Count -gt 0)
    {
        $Summary.files_with_key_errors++
        $HasFailure = $true
        $detailParts = @()
        if ($MissingKeys.Count -gt 0) { $detailParts += ("missing={0}" -f $MissingKeys.Count) }
        if ($ExtraKeys.Count -gt 0) { $detailParts += ("extra={0}" -f $ExtraKeys.Count) }
        Write-Host ("  [FAIL] {0} -- key parity mismatch ({1})" -f $LocaleFile.Name, ($detailParts -join ', '))
        continue
    }

    if ($PlaceholderErrors.Count -gt 0)
    {
        $Summary.files_with_placeholder_errors++
        $HasFailure = $true
        Write-Host ("  [FAIL] {0} -- {1} placeholder error(s)" -f $LocaleFile.Name, $PlaceholderErrors.Count)
        continue
    }

    if ($FormatErrors.Count -gt 0)
    {
        $Summary.files_with_format_errors++
        $HasFailure = $true
        $preview = @($FormatErrors | Select-Object -First 5 | ForEach-Object { "{0}: {1}" -f $_.key, $_.message }) -join '; '
        Write-Host ("  [FAIL] {0} -- {1} format string error(s): {2}" -f $LocaleFile.Name, $FormatErrors.Count, $preview)
        continue
    }

    if ($EmptyStringKeys.Count -gt 0)
    {
        $HasFailure = $true
        $preview = ($EmptyStringKeys | Select-Object -First 5) -join ', '
        Write-Host ("  [FAIL] {0} -- {1} blank localized string(s): {2}" -f $LocaleFile.Name, $EmptyStringKeys.Count, $preview)
        continue
    }

    if ($IsUnfinished)
    {
        $Summary.files_with_ignored_leaks++
        $Summary.files_with_unfinished_leaks++
        Write-Host ("  [SKIP] {0} -- unfinished locale; {1} exact-match leak(s) ignored" -f $LocaleFile.Name, $ExactLeaks.Count)
        continue
    }

    if ($IsEnglishVariant)
    {
        $Summary.files_with_ignored_leaks++
        Write-Host ("  [SKIP] {0} -- English variant; {1} exact-match leak(s) ignored" -f $LocaleFile.Name, $ExactLeaks.Count)
        continue
    }

    if ($ExactLeaks.Count -gt 0)
    {
        $Summary.files_with_remaining_leaks++
        $HasFailure = $true
        $preview = ($ExactLeaks | Select-Object -First 5) -join ', '
        Write-Host ("  [FAIL] {0} -- {1} exact-English leak(s): {2}" -f $LocaleFile.Name, $ExactLeaks.Count, $preview)
        continue
    }

    Write-Host ("  [PASS] {0}" -f $LocaleFile.Name)
}

$TerminologyAudit = $null
if ($TerminologyTerms.Count -gt 0)
{
    $termSummary = [ordered]@{}
    $TerminologyViolations = [System.Collections.Generic.List[object]]::new()

    foreach ($term in $TerminologyTerms)
    {
        $termName = [string]$term.name
        $termPolicy = [string]$term.policy
        $accumulator = $TerminologyAccumulators[$termName]

        $violationNames = switch ($termPolicy)
        {
            'LOCALIZE' { @($accumulator.files_with_token_names) }
            'LOCKED_ENGLISH' { @($accumulator.files_without_token_names) }
            default { @() }
        }

        foreach ($fileName in $violationNames)
        {
            $matchInfo = $null
            foreach ($record in $TerminologyLocaleDetails)
            {
                if ([string]$record.file -eq $fileName)
                {
                    $matchInfo = $record.term_matches[$termName]
                    break
                }
            }

            $TerminologyViolations.Add([pscustomobject]@{
                file = $fileName
                term = $termName
                policy = $termPolicy
                matched_keys = if ($null -ne $matchInfo) { @($matchInfo.matched_keys) } else { @() }
                match_count = if ($null -ne $matchInfo) { [int]$matchInfo.match_count } else { 0 }
            })
        }

        $termSummary[$termName] = [ordered]@{
            token = [string]$accumulator.token
            policy = [string]$accumulator.policy
            files_with_token = [int]$accumulator.files_with_token
            files_without_token = [int]$accumulator.files_without_token
            files_with_token_names = @($accumulator.files_with_token_names)
            files_without_token_names = @($accumulator.files_without_token_names)
            sample_matches = $accumulator.sample_matches
        }
    }

    $TerminologyAudit = [ordered]@{
        policy_path = $(if ($TerminologyPolicyPath) { [string]$TerminologyPolicyPath } else { [string](Join-Path $LocalizationDir 'terminology_policy.json') })
        regional_tone = $(if ($TerminologyPolicy -and $TerminologyPolicy.PSObject.Properties['regionalTone']) { [string]$TerminologyPolicy.regionalTone } else { 'localized_freedom' })
        terms = $termSummary
        violations = @($TerminologyViolations)
    }

    if ($AuditReportPath)
    {
        $report = [ordered]@{
            generated = (Get-Date -Format 'o')
            repository_root = $RepoRoot
            localization_schema = [ordered]@{
                path = $(if ($PSBoundParameters.ContainsKey('LocalizationSchemaPath')) { [string]$LocalizationSchemaPath } else { [string](Join-Path $LocalizationDir 'localization_schema.json') })
                source_file = [string]$LocalizationSchema.source_file
                key_count = [int]$LocalizationSchema.key_count
                hash_algorithm = [string]$LocalizationSchema.hash_algorithm
                key_hash = [string]$LocalizationSchema.key_hash
            }
            structural_summary = $Summary
            terminology = $TerminologyAudit
        }

        $reportDir = Split-Path -Path $AuditReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportDir) -and -not (Test-Path -LiteralPath $reportDir -PathType Container))
        {
            $null = New-Item -ItemType Directory -Path $reportDir -Force
        }

        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $AuditReportPath -Encoding UTF8
        Write-Host ("  [INFO] Terminology audit written to {0}" -f $AuditReportPath) -ForegroundColor Cyan
    }

    if ($EnforceTerminologyPolicy -and $TerminologyViolations.Count -gt 0)
    {
        $HasFailure = $true
        Write-Host ("  [FAIL] terminology policy violations: {0}" -f $TerminologyViolations.Count)
        foreach ($violation in ($TerminologyViolations | Select-Object -First 10))
        {
            $previewKeys = if ($violation.matched_keys.Count -gt 0) { ($violation.matched_keys | Select-Object -First 3) -join ', ' } else { '<none>' }
            Write-Host ("    {0}: {1} ({2}) -> {3}" -f $violation.file, $violation.term, $violation.policy, $previewKeys)
        }
    }
}

Write-Host ("  Scanned files: {0}" -f $Summary.scanned_files)
Write-Host ("  Remaining exact-English leaks: {0}" -f $Summary.total_remaining_leaks)
Write-Host ("  Ignored exact-English leaks: {0}" -f $Summary.total_ignored_leaks)
Write-Host ("    unfinished locales: {0}" -f $Summary.total_unfinished_leaks)
Write-Host ("  English-variant exact-English leaks: {0}" -f $Summary.total_english_variant_leaks)
Write-Host ("  Placeholder issues: {0}" -f $Summary.total_placeholder_errors)
Write-Host ("  Format string issues: {0}" -f $Summary.total_format_errors)
Write-Host ("  Files with ignored leaks: {0}" -f $Summary.files_with_ignored_leaks)
Write-Host ("  Files with English-variant leaks: {0}" -f $Summary.files_with_english_variant_leaks)
Write-Host ("  Duplicate locale content groups: {0}" -f $Summary.duplicate_locale_groups)
Write-Host ("  Files with empty strings: {0} (total empty: {1})" -f $Summary.files_with_empty_strings, $Summary.total_empty_strings)

if ($HasFailure)
{
    throw 'Localization QA failed.'
}
