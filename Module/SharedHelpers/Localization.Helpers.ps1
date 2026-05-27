<#
    .SYNOPSIS
    JSON-based localization loader for Baseline.

    .DESCRIPTION
    Replaces Import-LocalizedData with a JSON-based approach that supports
    all Baseline language codes. Falls back through culture -> language -> en.
    Compatible with PowerShell 5.1+.
#>

function Resolve-BaselineLocalizationDirectory
{
    <#
        .SYNOPSIS
        Resolves the repository localization directory from a module or script base path.

        .PARAMETER BasePath
        One or more candidate paths near the active module or script. The resolver
        walks upward from each candidate and returns the first Localizations
        directory that contains JSON localization files.
    #>
    [CmdletBinding()]
    param(
        [string[]]$BasePath
    )

    $candidateRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($BasePath, $PSScriptRoot))
    {
        if ([string]::IsNullOrWhiteSpace([string]$path))
        {
            continue
        }

        $root = [string]$path
        if (Test-Path -LiteralPath $root -PathType Leaf)
        {
            $root = Split-Path -Path $root -Parent
        }

        $probe = $root
        for ($i = 0; $i -lt 3 -and -not [string]::IsNullOrWhiteSpace([string]$probe); $i++)
        {
            [void]$candidateRoots.Add($probe)
            $probe = Split-Path -Path $probe -Parent
        }
    }

    $candidateRoots = $candidateRoots | Select-Object -Unique
    foreach ($root in $candidateRoots)
    {
        $localizationsPath = Join-Path -Path $root -ChildPath 'Localizations'
        $hasLocalizationFiles = Get-ChildItem -LiteralPath $localizationsPath -Filter '*.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ((Test-Path -LiteralPath $localizationsPath -PathType Container) -and $hasLocalizationFiles)
        {
            return $localizationsPath
        }
    }

    return $null
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineLocalizationFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    $matches = @(
        Get-ChildItem -LiteralPath $BaseDirectory -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { [string]::Equals($_.Name, $FileName, [System.StringComparison]::OrdinalIgnoreCase) }
    )

    if ($matches.Count -eq 1)
    {
        return $matches[0].FullName
    }

    if ($matches.Count -eq 0)
    {
        throw "Localization file '$FileName' not found under '$BaseDirectory'."
    }

    throw "Multiple localization files named '$FileName' were found under '$BaseDirectory'."
}

<#
    .SYNOPSIS
#>

function Import-BaselineLocalization
{
    <#
        .SYNOPSIS
        Loads a JSON localization file and returns a hashtable of strings.

        .PARAMETER BaseDirectory
        The directory containing the JSON localization files.

        .PARAMETER UICulture
        The UI culture string (e.g. 'en-US', 'de-DE', 'zh-CN').
        Defaults to $PSUICulture.

        .OUTPUTS
        [hashtable] Key-value pairs of localized strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory,

        [Parameter()]
        [string]$UICulture = $PSUICulture
    )

    # Map PowerShell culture codes to Baseline-style JSON file names.
    # Tries exact match first (e.g. pt-BR), then language-only (e.g. pt),
    # then known mappings (e.g. zh-CN -> zh-Hans), then falls back to en.
    $cultureMap = @{
        'zh-CN' = 'zh-Hans'
        'zh-SG' = 'zh-Hans'
        'zh-TW' = 'zh-Hant'
        'zh-HK' = 'zh-Hant'
        'zh-MO' = 'zh-Hant'
    }

    $candidates = [System.Collections.Generic.List[string]]::new()

    <#
        .SYNOPSIS
    #>

    function Add-LocalizationCandidate
    {
        param(
            [Parameter(Mandatory)]
            [string]$Candidate
        )

        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and -not $candidates.Contains($Candidate))
        {
            [void]$candidates.Add($Candidate)
        }
    }

    # 1. Try mapped name (e.g. zh-CN -> zh-Hans)
    if ($cultureMap.ContainsKey($UICulture))
    {
        Add-LocalizationCandidate -Candidate $cultureMap[$UICulture]
    }

    # 2. Try the canonical culture name (e.g. pt-BR, nl-BE, sr-Cyrl)
    $normalizedCulture = $UICulture
    try
    {
        $normalizedCulture = [System.Globalization.CultureInfo]::GetCultureInfo($UICulture).Name
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Localization.Helpers.Import-BaselineLocalization:catch167' -Severity Debug }

        $null = $_
    }
    Add-LocalizationCandidate -Candidate $normalizedCulture

    # 3. Try language-only (e.g. de from de-DE)
    $langOnly = $normalizedCulture
    if ($normalizedCulture -match '-')
    {
        $langOnly = ($normalizedCulture -split '-', 2)[0]
        try
        {
            $langOnly = [System.Globalization.CultureInfo]::GetCultureInfo($langOnly).Name
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Localization.Helpers.Import-BaselineLocalization:catch182' -Severity Debug }

            $null = $_
        }
        if ($langOnly -ne $normalizedCulture)
        {
            Add-LocalizationCandidate -Candidate $langOnly
        }
    }

    # 4. Fallback to English
    Add-LocalizationCandidate -Candidate 'en-US'

    $resolvedCandidate = $null
    foreach ($candidate in $candidates)
    {
        try
        {
            $null = Resolve-BaselineLocalizationFile -BaseDirectory $BaseDirectory -FileName "$candidate.json"
            $resolvedCandidate = $candidate
            break
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Localization.Helpers.Import-BaselineLocalization:catch204' -Severity Debug }

            $null = $_
        }
    }

    if (-not $resolvedCandidate)
    {
        throw "No localization file found in '$BaseDirectory' for culture '$UICulture'."
    }

    $readLocalizationFile = {
        param([string]$JsonPath)

        $jsonContent = Get-Content -Path $JsonPath -Raw -Encoding UTF8
        $jsonObj = $jsonContent | ConvertFrom-BaselineJson -Depth 16

        $hashtable = @{}
        foreach ($prop in $jsonObj.PSObject.Properties)
        {
            $hashtable[$prop.Name] = $prop.Value
        }

        return $hashtable
    }

    $englishPath = Resolve-BaselineLocalizationFile -BaseDirectory $BaseDirectory -FileName 'en-US.json'

    $merged = & $readLocalizationFile $englishPath
    if ($resolvedCandidate -ne 'en-US')
    {
        $candidatePath = Resolve-BaselineLocalizationFile -BaseDirectory $BaseDirectory -FileName "$resolvedCandidate.json"
        $candidateMap = & $readLocalizationFile $candidatePath
        foreach ($entry in $candidateMap.GetEnumerator())
        {
            if ([string]::IsNullOrWhiteSpace([string]$entry.Value))
            {
                continue
            }

            $merged[$entry.Key] = $entry.Value
        }
    }

    return $merged
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineCultureName
{
    <#
        .SYNOPSIS
        Resolves a Baseline UI culture token to a .NET culture name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$UICulture = $PSUICulture
    )

    $cultureMap = @{
        'zh-Hans' = 'zh-CN'
        'zh-Hant' = 'zh-TW'
    }

    $candidate = if ([string]::IsNullOrWhiteSpace([string]$UICulture)) { 'en-US' } else { [string]$UICulture.Trim() }
    if ($cultureMap.ContainsKey($candidate))
    {
        $candidate = $cultureMap[$candidate]
    }

    try
    {
        $null = [System.Globalization.CultureInfo]::GetCultureInfo($candidate)
        return $candidate
    }
    catch
    {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Localization.Helpers.Resolve-BaselineCultureName:catch283' -Severity Debug }

        $null = $_
    }

    if ($candidate -match '-')
    {
        $languageOnly = ($candidate -split '-', 2)[0]
        try
        {
            $null = [System.Globalization.CultureInfo]::GetCultureInfo($languageOnly)
            return $languageOnly
        }
        catch
        {
	if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Localization.Helpers.Resolve-BaselineCultureName:catch296' -Severity Debug }

            $null = $_
        }
    }

    return 'en-US'
}

<#
    .SYNOPSIS
#>

function Set-BaselineThreadCulture
{
    <#
        .SYNOPSIS
        Applies the requested culture to the current and default thread contexts.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$UICulture = $PSUICulture
    )

    $resolvedCulture = Resolve-BaselineCultureName -UICulture $UICulture
    $cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($resolvedCulture)

    [System.Threading.Thread]::CurrentThread.CurrentCulture = $cultureInfo
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $cultureInfo
    [System.Globalization.CultureInfo]::DefaultThreadCurrentCulture = $cultureInfo
    [System.Globalization.CultureInfo]::DefaultThreadCurrentUICulture = $cultureInfo

    return $cultureInfo.Name
}

function Get-BaselineLocalizedString
{
    <#
        .SYNOPSIS
        Resolves a Baseline localization key with a fallback string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Fallback,

        [object[]]$FormatArgs = @()
    )

    $cultureName = [string]([System.Environment]::GetEnvironmentVariable('BASELINE_LANGUAGE'))
    if ([string]::IsNullOrWhiteSpace($cultureName))
    {
        $cultureName = [string][System.Threading.Thread]::CurrentThread.CurrentUICulture.Name
    }
    $template = $Fallback
    $foundTranslation = $false
    $localizationVariable = Get-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $localizationVariable)
    {
        $localizationVariable = Get-Variable -Name Localization -ErrorAction SilentlyContinue
    }

    $localizationSource = if ($null -ne $localizationVariable) { $localizationVariable.Value } else { $null }
    if ($null -ne $localizationSource)
    {
        $candidate = $null
        if ($localizationSource -is [System.Collections.IDictionary] -and $localizationSource.Contains($Key))
        {
            $candidate = [string]$localizationSource[$Key]
        }
        elseif ($localizationSource.PSObject -and $localizationSource.PSObject.Properties[$Key])
        {
            $candidate = [string]$localizationSource.$Key
        }

        if (-not [string]::IsNullOrWhiteSpace($candidate))
        {
            $template = $candidate
            $foundTranslation = $true
        }
    }

    if (-not $foundTranslation)
    {
        $warningKey = '{0}|{1}' -f $cultureName, $Key
        if (-not (Get-Variable -Name CachedBaselineMissingLocalizationWarnings -Scope Script -ErrorAction SilentlyContinue))
        {
            $Script:CachedBaselineMissingLocalizationWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }

        if ($Script:CachedBaselineMissingLocalizationWarnings.Add($warningKey))
        {
            $warningMessage = "Missing localization key '$Key' for culture '$cultureName'; using English fallback text."
            if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
            {
                LogWarning $warningMessage
            }
            else
            {
                Write-Warning $warningMessage
            }
        }
    }

    if ($FormatArgs.Count -gt 0)
    {
        return ($template -f $FormatArgs)
    }

    return $template
}

<#
    .SYNOPSIS
#>

function Get-BaselineBilingualString
{
    <#
        .SYNOPSIS
        Returns the localized string followed by the English fallback.

        .DESCRIPTION
        Intended for logs and diagnostics where translated text helps users
        while the English source text keeps the output easy to grep.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Fallback,

        [object[]]$FormatArgs = @(),

        [string]$Separator = ' | '
    )

    $localized = Get-BaselineLocalizedString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs
    $english = if ($FormatArgs.Count -gt 0) { $Fallback -f $FormatArgs } else { $Fallback }

    if ([string]::IsNullOrWhiteSpace([string]$localized) -or [string]$localized -eq [string]$english)
    {
        return $english
    }

    return ('{0}{1}{2}' -f $localized, $Separator, $english)
}
