<#
    .SYNOPSIS
    JSON-based localization loader for Baseline.

    .DESCRIPTION
    Replaces Import-LocalizedData with a JSON-based approach that supports
    all Winhance language codes. Falls back through culture -> language -> en.
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

    # Map PowerShell culture codes to Winhance-style JSON file names.
    # Tries exact match first (e.g. pt-BR), then language-only (e.g. pt),
    # then known mappings (e.g. zh-CN -> zh-Hans), then falls back to en.
    $cultureMap = @{
        'zh-CN' = 'zh-Hans'
        'zh-SG' = 'zh-Hans'
        'zh-TW' = 'zh-Hant'
        'zh-HK' = 'zh-Hant'
        'zh-MO' = 'zh-Hant'
    }

    $candidates = @()

    # 1. Try mapped name (e.g. zh-CN -> zh-Hans)
    if ($cultureMap.ContainsKey($UICulture))
    {
        $candidates += $cultureMap[$UICulture]
    }

    # 2. Try full culture code as-is (e.g. pt-BR, nl-BE)
    $candidates += $UICulture.ToLower()

    # 3. Try language-only (e.g. de from de-DE)
    $langOnly = ($UICulture -split '-')[0].ToLower()
    if ($langOnly -ne $UICulture.ToLower())
    {
        $candidates += $langOnly
    }

    # 4. Fallback to English
    $candidates += 'en'

    foreach ($candidate in $candidates)
    {
        $jsonPath = Join-Path $BaseDirectory "$candidate.json"
        if (Test-Path -LiteralPath $jsonPath -PathType Leaf)
        {
            $jsonContent = Get-Content -Path $jsonPath -Raw -Encoding UTF8
            $jsonObj = ConvertFrom-Json -InputObject $jsonContent

            # Convert PSCustomObject to hashtable for PowerShell 5.1 compatibility.
            $hashtable = @{}
            foreach ($prop in $jsonObj.PSObject.Properties)
            {
                $hashtable[$prop.Name] = $prop.Value
            }

            return $hashtable
        }
    }

    throw "No localization file found in '$BaseDirectory' for culture '$UICulture'."
}
