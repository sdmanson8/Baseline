<#
    .SYNOPSIS
    Internal build tool for creating the Baseline setup executable with Inno Setup.

    .DESCRIPTION
    Builds a temporary installer payload archive, extracts it as the setup payload,
    stamps version and path defines into the unified Baseline-Setup.iss script,
    then compiles it with ISCC.exe to produce a single
    Baseline-<version>-setup.exe for stable releases.
    This is a maintainer-facing packaging script.

    .EXAMPLE
    powershell -File .\Tools\New-InstallerPackage.ps1

    .EXAMPLE
    powershell -File .\Tools\New-InstallerPackage.ps1 -GenerateScriptOnly
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$OutputDirectory,
    [string]$Version,
    [string]$IsccPath,
    [ValidateRange(1, 86400)]
    [int]$IsccTimeoutSeconds = 3600,
    [switch]$IncludeDocs,
    [switch]$GenerateScriptOnly,
    [switch]$RefreshInstallerTranslations,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$toolRepoRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Zip.Helpers.ps1')
. (Join-Path $toolRepoRoot 'Module/SharedHelpers/Process.Helpers.ps1')

function New-BaselineReleaseZip
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DestinationZip
    )

    [void](New-BaselineZipArchive `
        -SourceDirectory $SourceDirectory `
        -DestinationZip $DestinationZip)
}

<#
    .SYNOPSIS
    Runs ISCC with a bounded wait and file-backed diagnostics.
#>
function Invoke-InstallerIscc
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [object[]]$ArgumentList = @(),

        [Parameter(Mandatory = $true)]
        [string]$StdoutFile,

        [Parameter(Mandatory = $true)]
        [string]$StderrFile,

        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 3600
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $StdoutFile `
        -RedirectStandardError $StderrFile

    try
    {
        $timeoutMilliseconds = [int]([TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds)
        if (-not $process.WaitForExit($timeoutMilliseconds))
        {
            Stop-BaselineProcessTree -Process $process -Source 'NewInstallerPackage.IsccTimeout'
            throw (New-Object System.TimeoutException -ArgumentList ("ISCC timed out after {0} second(s)." -f $TimeoutSeconds))
        }

        [void]$process.WaitForExit()
        $process.Refresh()

        return [pscustomobject]@{
            ExitCode  = [int]$process.ExitCode
            ProcessId = [int]$process.Id
        }
    }
    finally
    {
        if ($null -ne $process)
        {
            $process.Dispose()
        }
    }
}

# ── Locate ISCC ───────────────────────────────────────────────────────────────

<#
    .SYNOPSIS
#>
function Resolve-IsccPath
{
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath))
    {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf))
        {
            throw "Specified ISCC path not found: $RequestedPath"
        }
        return $RequestedPath
    }

    $cmd = Get-Command -Name 'iscc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd)
    {
        $cmdPath = $null
        $pathProperty = $cmd.PSObject.Properties['Path']
        if ($pathProperty)
        {
            $cmdPath = [string]$pathProperty.Value
        }

        if ([string]::IsNullOrWhiteSpace([string]$cmdPath))
        {
            $sourceProperty = $cmd.PSObject.Properties['Source']
            if ($sourceProperty)
            {
                $cmdPath = [string]$sourceProperty.Value
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cmdPath) -and (Test-Path -LiteralPath $cmdPath -PathType Leaf))
        {
            return [string]$cmdPath
        }
    }

    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    {
        $candidate = Join-Path -Path $root -ChildPath 'Inno Setup 6'
        $candidate = Join-Path -Path $candidate -ChildPath 'ISCC.exe'

        if (Test-Path -LiteralPath $candidate -PathType Leaf)
        {
            return $candidate
        }
    }

    return $null
}

<#
    .SYNOPSIS
#>
function Get-InstallerPayloadEntries
{
    [CmdletBinding()]
    param()

    return @(
        'Baseline.exe'
        'Bootstrap'
        'Module'
        'Localizations'
        'Assets'
        'Completion'
        'Tools'
        'Tests'
        'docs'
        'README.md'
        'LICENSE'
        'CHANGELOG.md'
    )
}

<#
    .SYNOPSIS
#>
function Assert-InstallerPayloadExcludesRepositoryMetadata
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    foreach ($relativePath in @('.git', '.github'))
    {
        $candidate = Join-Path $SourceRoot $relativePath
        if (Test-Path -LiteralPath $candidate)
        {
            throw "Installer payload includes repository metadata: $relativePath"
        }
    }
}

<#
    .SYNOPSIS
#>
function Get-InstallerBuildLayout
{
    [CmdletBinding()]
    param(
        [string]$BaseTempPath = [System.IO.Path]::GetTempPath(),
        [string]$RootName = ('BaselineInstaller_{0}' -f [System.Guid]::NewGuid().ToString('N'))
    )

    $tempRoot = Join-Path $BaseTempPath $RootName
    $tempDist = Join-Path $tempRoot 'd'
    $tempExtract = Join-Path $tempRoot 'x'
    $tempScripts = Join-Path $tempRoot 'i'
    $stageRoot = Join-Path $tempRoot 's'
    $stageDir = Join-Path $stageRoot 'B'
    $sourceRoot = Join-Path $tempExtract 'B'

    return [pscustomobject]@{
        TempRoot    = $tempRoot
        TempDist    = $tempDist
        TempExtract = $tempExtract
        TempScripts = $tempScripts
        StageRoot   = $stageRoot
        StageDir    = $stageDir
        SourceRoot  = $sourceRoot
    }
}

<#
    .SYNOPSIS
#>
function Get-InstallerPayloadPathBudgetReport
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$BaseTempPath = [System.IO.Path]::GetTempPath(),

        [string]$RootName = ('BaselineInstaller_{0}' -f [System.Guid]::NewGuid().ToString('N'))
    )

    $layout = Get-InstallerBuildLayout -BaseTempPath $BaseTempPath -RootName $RootName
    $maxLength = 0
    $maxRelativePath = $null
    $maxTargetPath = $null

    foreach ($relativeEntry in (Get-InstallerPayloadEntries))
    {
        $sourcePath = Join-Path $RepoRoot $relativeEntry
        if (-not (Test-Path -LiteralPath $sourcePath))
        {
            continue
        }

        if (Test-Path -LiteralPath $sourcePath -PathType Leaf)
        {
            $targetPath = Join-Path $layout.SourceRoot $relativeEntry
            $targetLength = $targetPath.Length
            if ($targetLength -gt $maxLength)
            {
                $maxLength = $targetLength
                $maxRelativePath = $relativeEntry
                $maxTargetPath = $targetPath
            }

            continue
        }

        $sourceRootPath = (Resolve-Path -LiteralPath $sourcePath).Path
        foreach ($file in (Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force -ErrorAction SilentlyContinue))
        {
            $relativeChildPath = $file.FullName.Substring($sourceRootPath.Length).TrimStart('\')
            $relativeTargetPath = Join-Path $relativeEntry $relativeChildPath
            $targetPath = Join-Path $layout.SourceRoot $relativeTargetPath
            $targetLength = $targetPath.Length

            if ($targetLength -gt $maxLength)
            {
                $maxLength = $targetLength
                $maxRelativePath = $relativeTargetPath
                $maxTargetPath = $targetPath
            }
        }
    }

    return [pscustomobject]@{
        Layout          = $layout
        MaxLength       = $maxLength
        MaxRelativePath = $maxRelativePath
        MaxTargetPath   = $maxTargetPath
    }
}

<#
    .SYNOPSIS
#>
function Get-InstallerLocalizationDefinitions
{
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ OutputKey = 'LangPage.Title';              LocalizationKey = 'Installer_LangPage_Title';              Fallback = 'Choose Language' }
        [pscustomobject]@{ OutputKey = 'LangPage.Desc';               LocalizationKey = 'Installer_LangPage_Desc';               Fallback = 'Choose the display language for Baseline.' }
        [pscustomobject]@{ OutputKey = 'LangPage.Search';             LocalizationKey = 'Installer_LangPage_Search';             Fallback = 'Search languages:' }
        [pscustomobject]@{ OutputKey = 'LangPage.Display';            LocalizationKey = 'Installer_LangPage_Display';            Fallback = 'Display language:' }
        [pscustomobject]@{ OutputKey = 'LangPage.NoResults';          LocalizationKey = 'Installer_LangPage_NoResults';          Fallback = 'No matching languages found.' }
        [pscustomobject]@{ OutputKey = 'LangPage.Help';               LocalizationKey = 'Installer_LangPage_Help';               Fallback = 'Search by English or native language name. You can change this later in Baseline.' }
        [pscustomobject]@{ OutputKey = 'WizardTitle.Default';         LocalizationKey = 'Installer_WizardTitle_Default';         Fallback = 'Baseline Setup' }
        [pscustomobject]@{ OutputKey = 'WizardTitle.Install';         LocalizationKey = 'Installer_WizardTitle_Install';         Fallback = 'Baseline Setup - Install' }
        [pscustomobject]@{ OutputKey = 'WizardTitle.Portable';        LocalizationKey = 'Installer_WizardTitle_Portable';        Fallback = 'Baseline Setup - Portable' }
        [pscustomobject]@{ OutputKey = 'PortableMode.AllUsersError';  LocalizationKey = 'Installer_PortableMode_AllUsersError';  Fallback = 'Portable mode writes to the current user''s profile and cannot be installed in all-users setup mode. Restart Setup and choose "Current user" on the install scope page, or rerun Setup with /CURRENTUSER.' }
        [pscustomobject]@{ OutputKey = 'RestartAdminError';           LocalizationKey = 'Installer_RestartAdminError';           Fallback = 'Setup could not be restarted with administrative privileges.' }
        [pscustomobject]@{ OutputKey = 'InstallFolderDialog.Title';   LocalizationKey = 'Installer_InstallFolderDialog_Title';   Fallback = 'Select installation folder' }
        [pscustomobject]@{ OutputKey = 'InstallPath.EmptyError';      LocalizationKey = 'Installer_InstallPath_EmptyError';      Fallback = 'Please choose an installation folder.' }
        [pscustomobject]@{ OutputKey = 'ModePage.Title';              LocalizationKey = 'Installer_ModePage_Title';              Fallback = 'Installation Type' }
        [pscustomobject]@{ OutputKey = 'ModePage.Desc';               LocalizationKey = 'Installer_ModePage_Desc';               Fallback = 'Specify whether you want to install Baseline or run it as a portable app.' }
        [pscustomobject]@{ OutputKey = 'ModePage.Action';             LocalizationKey = 'Installer_ModePage_Action';             Fallback = 'Select action:' }
        [pscustomobject]@{ OutputKey = 'RbInstall.Caption';           LocalizationKey = 'Installer_RbInstall_Caption';           Fallback = 'Install for this PC' }
        [pscustomobject]@{ OutputKey = 'RbInstall.Desc';              LocalizationKey = 'Installer_RbInstall_Desc';              Fallback = 'Baseline will be installed and registered in Programs and Features.' }
        [pscustomobject]@{ OutputKey = 'RbPortable.Caption';          LocalizationKey = 'Installer_RbPortable_Caption';          Fallback = 'Portable' }
        [pscustomobject]@{ OutputKey = 'RbPortable.Desc';             LocalizationKey = 'Installer_RbPortable_Desc';             Fallback = 'Run portable version (no installation needed).' }
        [pscustomobject]@{ OutputKey = 'ScopePage.Title';             LocalizationKey = 'Installer_ScopePage_Title';             Fallback = 'Install Scope' }
        [pscustomobject]@{ OutputKey = 'ScopePage.Desc';              LocalizationKey = 'Installer_ScopePage_Desc';              Fallback = 'Choose who should be able to use Baseline.' }
        [pscustomobject]@{ OutputKey = 'ScopePage.Heading';           LocalizationKey = 'Installer_ScopePage_Heading';           Fallback = 'Select install scope:' }
        [pscustomobject]@{ OutputKey = 'RbCurrentUser.Caption';       LocalizationKey = 'Installer_RbCurrentUser_Caption';       Fallback = 'Install for me only (recommended)' }
        [pscustomobject]@{ OutputKey = 'RbCurrentUser.Desc';          LocalizationKey = 'Installer_RbCurrentUser_Desc';          Fallback = 'Installs Baseline for the current Windows account only.' }
        [pscustomobject]@{ OutputKey = 'RbAllUsers.Caption';          LocalizationKey = 'Installer_RbAllUsers_Caption';          Fallback = 'Install for all users' }
        [pscustomobject]@{ OutputKey = 'RbAllUsers.Desc';             LocalizationKey = 'Installer_RbAllUsers_Desc';             Fallback = 'Installs Baseline for every account on this PC and restarts Setup with administrative privileges if needed.' }
        [pscustomobject]@{ OutputKey = 'LocPage.Title';               LocalizationKey = 'Installer_LocPage_Title';               Fallback = 'Install Location' }
        [pscustomobject]@{ OutputKey = 'LocPage.Desc';                LocalizationKey = 'Installer_LocPage_Desc';                Fallback = 'Choose where Baseline should be installed.' }
        [pscustomobject]@{ OutputKey = 'LocPage.Heading';             LocalizationKey = 'Installer_LocPage_Heading';             Fallback = 'Install location:' }
        [pscustomobject]@{ OutputKey = 'BtnBrowse.Caption';           LocalizationKey = 'Installer_BtnBrowse_Caption';           Fallback = 'Browse...' }
        [pscustomobject]@{ OutputKey = 'LocPage.Note';                LocalizationKey = 'Installer_LocPage_Note';                Fallback = 'Baseline will be registered with Windows and can be uninstalled from Settings.' }
        [pscustomobject]@{ OutputKey = 'ShortPage.Title';             LocalizationKey = 'Installer_ShortPage_Title';             Fallback = 'Shortcuts' }
        [pscustomobject]@{ OutputKey = 'ShortPage.Desc';              LocalizationKey = 'Installer_ShortPage_Desc';              Fallback = 'Choose which shortcuts to create for Baseline.' }
        [pscustomobject]@{ OutputKey = 'ShortPage.Heading';           LocalizationKey = 'Installer_ShortPage_Heading';           Fallback = 'Create these shortcuts:' }
        [pscustomobject]@{ OutputKey = 'CbDesktop.Caption';           LocalizationKey = 'Installer_CbDesktop_Caption';           Fallback = 'Desktop shortcut' }
        [pscustomobject]@{ OutputKey = 'CbStartMenu.Caption';         LocalizationKey = 'Installer_CbStartMenu_Caption';         Fallback = 'Start menu shortcut' }
        [pscustomobject]@{ OutputKey = 'FinishPage.Title';            LocalizationKey = 'Installer_FinishPage_Title';            Fallback = 'Setup Complete' }
        [pscustomobject]@{ OutputKey = 'FinishPage.Desc';             LocalizationKey = 'Installer_FinishPage_Desc';             Fallback = 'Baseline is ready to use.' }
        [pscustomobject]@{ OutputKey = 'CbLaunch.Caption';            LocalizationKey = 'Installer_CbLaunch_Caption';            Fallback = 'Launch Baseline now' }
        [pscustomobject]@{ OutputKey = 'FinishMsg.Install';           LocalizationKey = 'Installer_FinishMsg_Install';           Fallback = 'Baseline has been installed to:' }
        [pscustomobject]@{ OutputKey = 'FinishMsg.Portable';          LocalizationKey = 'Installer_FinishMsg_Portable';          Fallback = 'Baseline is ready in:' }
        [pscustomobject]@{ OutputKey = 'FinishMsg.PortableShortcut';  LocalizationKey = 'Installer_FinishMsg_PortableShortcut';  Fallback = 'A desktop shortcut has been created.' }
        [pscustomobject]@{ OutputKey = 'Btn.Next';                    LocalizationKey = 'Installer_Btn_Next';                    Fallback = 'Next >' }
        [pscustomobject]@{ OutputKey = 'Btn.Install';                 LocalizationKey = 'Installer_Btn_Install';                 Fallback = 'Install' }
        [pscustomobject]@{ OutputKey = 'Btn.Extract';                 LocalizationKey = 'Installer_Btn_Extract';                 Fallback = 'Extract' }
        [pscustomobject]@{ OutputKey = 'Btn.Finish';                  LocalizationKey = 'Installer_Btn_Finish';                  Fallback = 'Finish' }
    )
}

<#
    .SYNOPSIS
#>
function Import-InstallerLocalizationTable
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalizationRoot,

        [Parameter(Mandatory)]
        [string]$UICulture
    )

    if (-not (Test-Path -LiteralPath $LocalizationRoot -PathType Container))
    {
        return @{}
    }

    $cultureMap = @{
        'zh-CN' = 'zh-Hans'
        'zh-SG' = 'zh-Hans'
        'zh-TW' = 'zh-Hant'
        'zh-HK' = 'zh-Hant'
        'zh-MO' = 'zh-Hant'
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'

    function Add-InstallerLocalizationCandidate
    {
        param(
            [Parameter(Mandatory)]
            [string]$Candidate
        )

        if (-not [string]::IsNullOrWhiteSpace([string]$Candidate) -and -not $candidates.Contains($Candidate))
        {
            [void]$candidates.Add($Candidate)
        }
    }

    $normalizedCulture = if ([string]::IsNullOrWhiteSpace([string]$UICulture)) { 'en-US' } else { [string]$UICulture.Trim() }
    if ($cultureMap.ContainsKey($normalizedCulture))
    {
        Add-InstallerLocalizationCandidate -Candidate $cultureMap[$normalizedCulture]
    }

    try
    {
        $normalizedCulture = [System.Globalization.CultureInfo]::GetCultureInfo($normalizedCulture).Name
    }
    catch
    {
        $null = $_
    }

    Add-InstallerLocalizationCandidate -Candidate $normalizedCulture

    if ($normalizedCulture -match '-')
    {
        $languageOnly = ($normalizedCulture -split '-', 2)[0]
        try
        {
            $languageOnly = [System.Globalization.CultureInfo]::GetCultureInfo($languageOnly).Name
        }
        catch
        {
            $null = $_
        }

        if ($languageOnly -ne $normalizedCulture)
        {
            Add-InstallerLocalizationCandidate -Candidate $languageOnly
        }
    }

    $localeFile = $null
    foreach ($candidate in $candidates)
    {
        $matches = @(
            Get-ChildItem -LiteralPath $LocalizationRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { [string]::Equals($_.Name, ('{0}.json' -f $candidate), [System.StringComparison]::OrdinalIgnoreCase) }
        )

        if ($matches.Count -eq 1)
        {
            $localeFile = $matches[0].FullName
            break
        }

        if ($matches.Count -gt 1)
        {
            throw "Multiple localization files named '$candidate.json' were found under '$LocalizationRoot'."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$localeFile))
    {
        return @{}
    }

    $jsonObject = ConvertFrom-InstallerJsonFile -Path $localeFile
    $table = @{}
    foreach ($property in $jsonObject.PSObject.Properties)
    {
        $table[$property.Name] = [string]$property.Value
    }

    return $table
}

<#
    .SYNOPSIS
#>
function Get-InstallerLocalizationSource
{
    [CmdletBinding()]
    param(
        [string]$UICulture = 'en-US',

        [string]$RepoRoot,

        [string]$LocalizationRoot
    )

    if (-not (Get-Command -Name 'Get-BaselineLocalizedString' -ErrorAction SilentlyContinue))
    {
        if ([string]::IsNullOrWhiteSpace([string]$RepoRoot))
        {
            throw 'RepoRoot is required to load installer localization helpers.'
        }

        $localizationHelpersPath = Join-Path $RepoRoot 'Module\SharedHelpers\Localization.Helpers.ps1'
        if (-not (Test-Path -LiteralPath $localizationHelpersPath -PathType Leaf))
        {
            throw "Localization helper script not found: $localizationHelpersPath"
        }

        . $localizationHelpersPath
    }

    if ([string]::IsNullOrWhiteSpace([string]$LocalizationRoot) -and -not [string]::IsNullOrWhiteSpace([string]$RepoRoot))
    {
        $LocalizationRoot = Join-Path $RepoRoot 'Localizations'
    }

    $Localization = if ([string]::IsNullOrWhiteSpace([string]$LocalizationRoot))
    {
        @{}
    }
    else
    {
        Import-InstallerLocalizationTable -LocalizationRoot $LocalizationRoot -UICulture $UICulture
    }

    $isEnglishCulture = $false
    try
    {
        $isEnglishCulture = ([System.Globalization.CultureInfo]::GetCultureInfo($UICulture).TwoLetterISOLanguageName -eq 'en')
    }
    catch
    {
        $isEnglishCulture = ([string]$UICulture -like 'en*')
    }

    $sourceMap = [ordered]@{}
    foreach ($definition in (Get-InstallerLocalizationDefinitions))
    {
        $localizedValue = $null
        if ($Localization -is [System.Collections.IDictionary] -and $Localization.Contains($definition.LocalizationKey))
        {
            $localizedValue = [string]$Localization[$definition.LocalizationKey]
        }

        if ($isEnglishCulture)
        {
            $sourceMap[$definition.OutputKey] = if ([string]::IsNullOrWhiteSpace($localizedValue)) { [string]$definition.Fallback } else { $localizedValue }
        }
        else
        {
            $sourceMap[$definition.OutputKey] = if ([string]::IsNullOrWhiteSpace($localizedValue)) { [string]$definition.Fallback } else { $localizedValue }
        }
    }

    return $sourceMap
}

<#
    .SYNOPSIS
#>
function Get-InstallerLocaleCodes
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateContent
    )

    $matches = [regex]::Matches($TemplateContent, "LocaleEntries\[\d+\]\s*:=\s*'([^']+)';")
    $codes = foreach ($match in $matches)
    {
        $entry = [string]$match.Groups[1].Value
        $separator = $entry.LastIndexOf('|')
        if ($separator -ge 0)
        {
            $entry.Substring($separator + 1)
        }
        else
        {
            $entry
        }
    }

    $codes | Select-Object -Unique
}

<#
    .SYNOPSIS
#>
function ConvertTo-InnoStringLiteral
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $Value = $Value -replace "\r?\n", ' '
    "'" + $Value.Replace("'", "''") + "'"
}

<#
    .SYNOPSIS
#>
function ConvertTo-StringMap
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$JsonObject
    )

    $map = [ordered]@{}
    foreach ($prop in $JsonObject.PSObject.Properties)
    {
        $map[$prop.Name] = [string]$prop.Value
    }

    return $map
}

<#
    .SYNOPSIS
#>
function Read-InstallerUtf8Text
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $utf8Strict = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
    return [System.IO.File]::ReadAllText($Path, $utf8Strict)
}

<#
    .SYNOPSIS
#>
function ConvertFrom-InstallerJsonFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $jsonText = Read-InstallerUtf8Text -Path $Path
    return ($jsonText | ConvertFrom-Json -ErrorAction Stop)
}

<#
    .SYNOPSIS
#>
function Get-InstallerMojibakeMarker
{
    [CmdletBinding()]
    param()

    @(
        [string][char]0xFFFD
        [string][char]0x00C3
        [string][char]0x00C2
        ([string][char]0x00E1 + [string][char]0x2030)
        ([string][char]0x00E6 + [string][char]0x2039)
    )
}

<#
    .SYNOPSIS
#>
function Assert-InstallerTextEncodingClean
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Context
    )

    foreach ($marker in (Get-InstallerMojibakeMarker))
    {
        if ($Text.Contains($marker))
        {
            $codePoints = @($marker.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int][char]$_ }) -join ' '
            throw "$Context contains mojibake marker $codePoints."
        }
    }
}

<#
    .SYNOPSIS
#>
function Get-InstallerLocalizationEnglishInvariantKeys
{
    [CmdletBinding()]
    param()

    @()
}

<#
    .SYNOPSIS
#>
function Assert-InstallerLocalizationWorkspaceComplete
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $sourcePath = Join-Path $Root 'en.json'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf))
    {
        throw "Installer localization source file missing: $sourcePath"
    }

    $sourceMap = ConvertTo-StringMap -JsonObject (ConvertFrom-InstallerJsonFile -Path $sourcePath)
    $englishInvariantKeys = @(Get-InstallerLocalizationEnglishInvariantKeys)
    foreach ($localeFile in @(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File | Where-Object { $_.Name -ne 'en.json' }))
    {
        $localeMap = ConvertTo-StringMap -JsonObject (ConvertFrom-InstallerJsonFile -Path $localeFile.FullName)
        foreach ($key in $sourceMap.Keys)
        {
            if (-not $localeMap.Contains($key))
            {
                throw "Installer localization '$($localeFile.Name)' is missing required key '$key'."
            }

            $value = [string]$localeMap[$key]
            if ([string]::IsNullOrWhiteSpace($value))
            {
                throw "Installer localization '$($localeFile.Name)' has a blank value for '$key'."
            }

            Assert-InstallerTextEncodingClean -Text $value -Context "Installer localization '$($localeFile.Name)' key '$key'"

            if (($value -eq [string]$sourceMap[$key]) -and ($key -notin $englishInvariantKeys))
            {
                throw "Installer localization '$($localeFile.Name)' still matches English source for '$key'."
            }
        }
    }
}

<#
    .SYNOPSIS
#>
function Reset-InstallerLocalizationWorkspaceFromSource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $sourcePath = Join-Path $Root 'en.json'
    $sourceMap = ConvertTo-StringMap -JsonObject (ConvertFrom-InstallerJsonFile -Path $sourcePath)
    foreach ($localeFile in @(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File | Where-Object { $_.Name -ne 'en.json' }))
    {
        $localeMap = [ordered]@{}
        foreach ($key in $sourceMap.Keys)
        {
            $localeMap[$key] = [string]$sourceMap[$key]
        }

        $localeMap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $localeFile.FullName -Encoding UTF8
    }
}

<#
    .SYNOPSIS
#>
function Initialize-InstallerLocalizationWorkspace
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$SourceMap,

        [Parameter(Mandatory)]
        [string[]]$LocaleCodes,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$LocalizationRoot
    )

    New-Item -Path $Root -ItemType Directory -Force | Out-Null

    $sourcePath = Join-Path $Root 'en.json'
    $SourceMap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sourcePath -Encoding UTF8

    foreach ($locale in $LocaleCodes)
    {
        if ($locale -like 'en*')
        {
            continue
        }

        $destinationPath = Join-Path $Root ("{0}.json" -f $locale)
        $localeMap = [ordered]@{}
        $existingMap = Get-InstallerLocalizationSource -UICulture $locale -RepoRoot $RepoRoot -LocalizationRoot $LocalizationRoot
        foreach ($key in $SourceMap.Keys)
        {
            $existingValue = $null
            if ($existingMap -is [System.Collections.IDictionary] -and $existingMap.Contains($key))
            {
                $existingValue = [string]$existingMap[$key]
            }

            if (-not [string]::IsNullOrWhiteSpace($existingValue))
            {
                $localeMap[$key] = $existingValue
            }
            else
            {
                $localeMap[$key] = [string]$SourceMap[$key]
            }
        }

        $localeMap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $destinationPath -Encoding UTF8
    }

    return $sourcePath
}

<#
    .SYNOPSIS
#>
function Get-InstallerLocalizationCacheKey
{
    <#
        .SYNOPSIS
        Returns the SHA-256 hex of the installer's en.json source strings.
        Used as the cache directory name so translations are only regenerated
        when the English source strings actually change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnJsonPath
    )

    $bytes  = [System.IO.File]::ReadAllBytes($EnJsonPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash   = $sha256.ComputeHash($bytes)
    $sha256.Dispose()
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

<#
    .SYNOPSIS
#>
function Get-InstallerFileSha256
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Get-Command -Name 'Get-FileHash' -ErrorAction SilentlyContinue)
    {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try
    {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try
        {
            $hashBytes = $sha256.ComputeHash($stream)
        }
        finally
        {
            $sha256.Dispose()
        }
    }
    finally
    {
        $stream.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToUpperInvariant()
}

<#
    .SYNOPSIS
#>
function Get-InstallerSetupFileName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$ChannelToken
    )

    $versionSegment = $Version.Trim()
    if ($versionSegment.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase))
    {
        $versionSegment = $versionSegment.Substring(1)
    }

    $channelSegment = $ChannelToken.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($channelSegment) -or $channelSegment -eq 'stable')
    {
        return "Baseline-$versionSegment-setup.exe"
    }

    $channelSuffix = "-$channelSegment"
    if ($versionSegment.EndsWith($channelSuffix, [System.StringComparison]::OrdinalIgnoreCase))
    {
        return "Baseline-$versionSegment-setup.exe"
    }

    return "Baseline-$versionSegment-$channelSegment-setup.exe"
}

<#
    .SYNOPSIS
#>
function Invoke-InstallerLocalizationTranslation
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [switch]$RefreshTranslations
    )

    # ── Cache check ──────────────────────────────────────────────────────────
    # The translated locale files are keyed by a hash of en.json.
    # If the cache folder for this hash already exists, copy from it and skip
    # the (slow, noisy) Google Translate pass entirely.

    $enJsonPath  = Join-Path $Root 'en.json'
    $cacheRoot   = Join-Path $repoRoot 'dist\installer-locale-cache'
    $cacheKey    = Get-InstallerLocalizationCacheKey -EnJsonPath $enJsonPath
    $cacheFolder = Join-Path $cacheRoot $cacheKey

    if (Test-Path -LiteralPath $cacheFolder -PathType Container)
    {
        Write-Host "  [locale-cache] Hit ($cacheKey) — skipping translation pass." -ForegroundColor DarkGray
        foreach ($cachedFile in Get-ChildItem -LiteralPath $cacheFolder -Filter '*.json')
        {
            if ($cachedFile.Name -eq 'en.json') { continue }
            Copy-Item -LiteralPath $cachedFile.FullName -Destination (Join-Path $Root $cachedFile.Name) -Force
        }

        try
        {
            Assert-InstallerLocalizationWorkspaceComplete -Root $Root
            return
        }
        catch
        {
            Write-Host "  [locale-cache] Invalid ($cacheKey) — discarding stale translations: $($_.Exception.Message)" -ForegroundColor Yellow
            Remove-Item -LiteralPath $cacheFolder -Recurse -Force -ErrorAction SilentlyContinue
            Reset-InstallerLocalizationWorkspaceFromSource -Root $Root
        }
    }

    if (-not $RefreshTranslations)
    {
        throw "Installer localization cache is missing or invalid for key '$cacheKey'. Run Tools/New-InstallerPackage.ps1 with -RefreshInstallerTranslations only after maintainer approval to refresh translations."
    }

    Write-Host "  [locale-cache] Miss ($cacheKey) — running translation pass..." -ForegroundColor DarkGray

    # ── Translate ────────────────────────────────────────────────────────────
    $fillScript = Join-Path $repoRoot 'Tools/Fill-LocalizationLeaks.js'
    if (-not (Test-Path -LiteralPath $fillScript -PathType Leaf))
    {
        throw "Localization translation helper not found: $fillScript"
    }

    $oldRoot = $env:LOCALIZATION_ROOT
    $oldSource = $env:LOCALIZATION_SOURCE_FILE
    $oldFailOnRemaining = $env:LOCALIZATION_FAIL_ON_REMAINING

    Push-Location $repoRoot
    try
    {
        $env:LOCALIZATION_ROOT = $Root
        $env:LOCALIZATION_SOURCE_FILE = 'en.json'
        $env:LOCALIZATION_FAIL_ON_REMAINING = '1'
        & node $fillScript
        if ($LASTEXITCODE -ne 0)
        {
            throw "Localization translation helper failed with exit code $LASTEXITCODE."
        }
        Assert-InstallerLocalizationWorkspaceComplete -Root $Root
    }
    finally
    {
        if ($null -ne $oldRoot)
        {
            $env:LOCALIZATION_ROOT = $oldRoot
        }
        else
        {
            Remove-Item Env:LOCALIZATION_ROOT -ErrorAction SilentlyContinue
        }

        if ($null -ne $oldSource)
        {
            $env:LOCALIZATION_SOURCE_FILE = $oldSource
        }
        else
        {
            Remove-Item Env:LOCALIZATION_SOURCE_FILE -ErrorAction SilentlyContinue
        }

        if ($null -ne $oldFailOnRemaining)
        {
            $env:LOCALIZATION_FAIL_ON_REMAINING = $oldFailOnRemaining
        }
        else
        {
            Remove-Item Env:LOCALIZATION_FAIL_ON_REMAINING -ErrorAction SilentlyContinue
        }

        Pop-Location
    }

    # ── Populate cache ───────────────────────────────────────────────────────
    # Evict any stale cache entries first so the folder stays tidy.
    if (Test-Path -LiteralPath $cacheRoot -PathType Container)
    {
        Get-ChildItem -LiteralPath $cacheRoot -Directory | Where-Object { $_.Name -ne $cacheKey } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    New-Item -Path $cacheFolder -ItemType Directory -Force | Out-Null
    Get-ChildItem -LiteralPath $Root -Filter '*.json' | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cacheFolder $_.Name) -Force
    }
    Write-Host "  [locale-cache] Saved translations to cache ($cacheKey)." -ForegroundColor DarkGray
}

<#
    .SYNOPSIS
#>
function New-InstallerLocalizationFunction
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$SourceMap,

        [Parameter(Mandatory)]
        [string[]]$LocaleCodes,

        [Parameter(Mandatory)]
        [string]$LocalizationRoot
    )

    $localeData = [ordered]@{}
    foreach ($locale in $LocaleCodes)
    {
        if ($locale -like 'en*')
        {
            continue
        }

        $localePath = Join-Path $LocalizationRoot ("{0}.json" -f $locale)
        if (-not (Test-Path -LiteralPath $localePath -PathType Leaf))
        {
            continue
        }

        $localeData[$locale.ToLowerInvariant()] = ConvertTo-StringMap -JsonObject (ConvertFrom-InstallerJsonFile -Path $localePath)
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('function GetSetupString(Key: String): String;')
    [void]$sb.AppendLine('var')
    [void]$sb.AppendLine('  Lang: String;')
    [void]$sb.AppendLine('begin')
    [void]$sb.AppendLine('  Lang := Lowercase(GLocaleCode);')

    $firstLocale = $true
    $emittedLocaleBranch = $false
    foreach ($locale in ($localeData.Keys | Sort-Object))
    {
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $translations = $localeData[$locale]
        foreach ($key in $SourceMap.Keys)
        {
            $sourceValue = [string]($SourceMap[$key])
            $localeValue = if ($translations.Contains($key)) { [string]$translations[$key] } else { '' }
            if ([string]::IsNullOrWhiteSpace($localeValue) -or $localeValue -eq $sourceValue)
            {
                continue
            }

            [void]$lines.Add(("    if Key = '{0}' then begin Result := {1}; Exit; end;" -f $key, (ConvertTo-InnoStringLiteral -Value $localeValue)))
        }

        if ($lines.Count -eq 0)
        {
            continue
        }

        if ($firstLocale)
        {
            [void]$sb.AppendLine(("  if Lang = '{0}' then" -f $locale))
            $firstLocale = $false
            $emittedLocaleBranch = $true
        }
        else
        {
            [void]$sb.AppendLine(("  else if Lang = '{0}' then" -f $locale))
        }

        [void]$sb.AppendLine('  begin')
        foreach ($line in $lines)
        {
            [void]$sb.AppendLine($line)
        }
        [void]$sb.AppendLine('  end')
    }

    if ($emittedLocaleBranch)
    {
        [void]$sb.AppendLine('  else')
        [void]$sb.AppendLine('  begin')
        foreach ($key in $SourceMap.Keys)
        {
            $sourceValue = [string]($SourceMap[$key])
            [void]$sb.AppendLine(("    if Key = '{0}' then begin Result := {1}; Exit; end;" -f $key, (ConvertTo-InnoStringLiteral -Value $sourceValue)))
        }
        [void]$sb.AppendLine('    Result := Key;')
        [void]$sb.AppendLine('  end;')
    }
    else
    {
        foreach ($key in $SourceMap.Keys)
        {
            $sourceValue = [string]($SourceMap[$key])
            [void]$sb.AppendLine(("  if Key = '{0}' then begin Result := {1}; Exit; end;" -f $key, (ConvertTo-InnoStringLiteral -Value $sourceValue)))
        }
        [void]$sb.AppendLine('  Result := Key;')
    }
    [void]$sb.AppendLine('end;')

    return $sb.ToString()
}

# ── Paths ─────────────────────────────────────────────────────────────────────

$repoRoot    = Split-Path -Path $PSScriptRoot -Parent
$templateIss = Join-Path $repoRoot 'dist\Baseline-Setup.iss'

if (-not (Test-Path -LiteralPath $templateIss -PathType Leaf))
{
    throw "Inno Setup template not found: $templateIss"
}

# ── Version ───────────────────────────────────────────────────────────────────

$moduleManifestPath = Join-Path $repoRoot 'Module\Baseline.psd1'
$manifest = $null
if ([string]::IsNullOrWhiteSpace($Version) -and (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf))
{
    $manifest = Import-PowerShellDataFile -LiteralPath $moduleManifestPath
    if ($manifest -and $manifest.ModuleVersion) { $Version = [string]$manifest.ModuleVersion }
}
elseif (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf)
{
    $manifest = Import-PowerShellDataFile -LiteralPath $moduleManifestPath
}
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = 'dev' }

$updateChannel = 'Stable'
$setupChannelToken = $updateChannel.ToLowerInvariant()

# ── Output dir ────────────────────────────────────────────────────────────────

$resolvedOutput = if ([string]::IsNullOrWhiteSpace($OutputDirectory))
{
    Join-Path $repoRoot 'dist'
}
elseif ([System.IO.Path]::IsPathRooted($OutputDirectory))
{
    $OutputDirectory
}
else
{
    Join-Path $repoRoot $OutputDirectory
}

if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Container))
{
    New-Item -Path $resolvedOutput -ItemType Directory -Force | Out-Null
}

# ── Build launcher ────────────────────────────────────────────────────────────

$buildLauncherScript = Join-Path $PSScriptRoot 'Build-Launcher.ps1'
$repoExe             = Join-Path $repoRoot 'Baseline.exe'
$launcherProject     = Join-Path $repoRoot 'Launcher\RunLauncher.csproj'
$launcherSourceRoots  = @(
    (Join-Path $repoRoot 'Launcher')
    (Join-Path $repoRoot 'Bootstrap')
    (Join-Path $repoRoot 'Module')
    (Join-Path $repoRoot 'Localizations')
    (Join-Path $repoRoot 'Assets')
    (Join-Path $repoRoot 'Completion')
)

$needsBuild = -not (Test-Path -LiteralPath $repoExe -PathType Leaf)
if (-not $needsBuild -and (Test-Path -LiteralPath $launcherProject -PathType Leaf))
{
    $exeTime  = (Get-Item -LiteralPath $repoExe).LastWriteTimeUtc
    $srcFiles = @()
    foreach ($root in $launcherSourceRoots)
    {
        if (Test-Path -LiteralPath $root -PathType Container)
        {
            $srcFiles += Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue
        }
    }
    $srcFiles = $srcFiles | Where-Object {
        $_.FullName -notmatch '\\(bin|obj)\\'
    }
    $needsBuild = $srcFiles | Where-Object { $_.LastWriteTimeUtc -gt $exeTime } | Select-Object -First 1
}

if ($needsBuild)
{
    Write-Host 'Building launcher...' -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $buildLauncherScript -PathType Leaf))
    {
        throw "Build-Launcher.ps1 not found: $buildLauncherScript"
    }
    & $buildLauncherScript -CopyToRepoRoot
    if ($LASTEXITCODE -ne 0) { throw "Build-Launcher.ps1 failed with exit code $LASTEXITCODE." }
}

if (-not (Test-Path -LiteralPath $repoExe -PathType Leaf))
{
    throw "Baseline.exe not found after launcher build: $repoExe"
}

# ── Build installer payload ───────────────────────────────────────────────────

$buildLayout = Get-InstallerBuildLayout
$tempRoot    = $buildLayout.TempRoot
$tempDist    = $buildLayout.TempDist
$tempExtract = $buildLayout.TempExtract
$tempScripts = $buildLayout.TempScripts
$archiveName = "Baseline-payload-$Version.zip"
$archivePath = Join-Path $tempDist $archiveName

try
{
    New-Item -Path $tempDist    -ItemType Directory -Force | Out-Null
    New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null
    New-Item -Path $tempScripts -ItemType Directory -Force | Out-Null

    # Stage loose files and compress them into the temporary setup payload zip.
    $stageRoot = $buildLayout.StageRoot
    $stageDir  = $buildLayout.StageDir
    New-Item -Path $stageDir -ItemType Directory -Force | Out-Null

    foreach ($rel in (Get-InstallerPayloadEntries))
    {
        $src = Join-Path $repoRoot $rel
        if (Test-Path -LiteralPath $src)
        {
            Copy-Item -LiteralPath $src -Destination $stageDir -Recurse -Force
        }
    }

    Get-ChildItem -LiteralPath $stageDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('.DS_Store','Thumbs.db') } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    New-BaselineReleaseZip -SourceDirectory $stageRoot -DestinationZip $archivePath

    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf))
    {
        throw "Portable archive not created: $archivePath"
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $tempExtract -Force
    $sourceRoot = $buildLayout.SourceRoot
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container))
    {
        throw "Payload root missing after extraction: $sourceRoot"
    }
    Assert-InstallerPayloadExcludesRepositoryMetadata -SourceRoot $sourceRoot

    # ── Stamp defines into a working copy of the .iss ────────────────────────

    $issContent = Read-InstallerUtf8Text -Path $templateIss
    $installerLocaleCodes = Get-InstallerLocaleCodes -TemplateContent $issContent
    $installerLocalizationRoot = Join-Path $tempRoot 'installer-localization'
    $installerLocalizationSource = Get-InstallerLocalizationSource -UICulture 'en-US' -RepoRoot $repoRoot

    Initialize-InstallerLocalizationWorkspace `
        -Root $installerLocalizationRoot `
        -SourceMap $installerLocalizationSource `
        -LocaleCodes $installerLocaleCodes `
        -RepoRoot $repoRoot

    Invoke-InstallerLocalizationTranslation -Root $installerLocalizationRoot -RefreshTranslations:$RefreshInstallerTranslations

    # ISPP double-quoted #define strings interpret C-style escapes (\r, \t, \n, etc.),
    # so raw Windows paths like "...\runneradmin\..." get mangled. Double the
    # backslashes here; ISPP un-escapes them back to single backslashes at expansion.
    $sourceRootEscaped     = $sourceRoot.Replace('\', '\\')
    $resolvedOutputEscaped = $resolvedOutput.Replace('\', '\\')
    $issContent = $issContent -replace '#define MyAppVersion\s+"[^"]*"',  "#define MyAppVersion `"$Version`""
    $issContent = $issContent -replace '#define MyAppChannel\s+"[^"]*"',  "#define MyAppChannel `"$updateChannel`""
    $issContent = $issContent -replace '#define MyAppChannelToken\s+"[^"]*"', "#define MyAppChannelToken `"$setupChannelToken`""
    $issContent = $issContent -replace '#define MySourceRoot\s+"[^"]*"',  "#define MySourceRoot `"$sourceRootEscaped`""
    $issContent = $issContent -replace '#define MyOutputDir\s+"[^"]*"',   "#define MyOutputDir  `"$resolvedOutputEscaped`""

    $generatedLocalization = New-InstallerLocalizationFunction `
        -SourceMap $installerLocalizationSource `
        -LocaleCodes $installerLocaleCodes `
        -LocalizationRoot $installerLocalizationRoot

    $functionStart = $issContent.IndexOf('function GetSetupString(Key: String): String;')
    $functionEnd   = $issContent.IndexOf('// Apply translated strings to all wizard pages after language is confirmed.')
    if (($functionStart -lt 0) -or ($functionEnd -lt 0) -or ($functionEnd -le $functionStart))
    {
        throw 'Unable to locate installer localization block in template.'
    }

    $issContent = $issContent.Substring(0, $functionStart) +
                  $generatedLocalization +
                  [Environment]::NewLine + [Environment]::NewLine +
                  $issContent.Substring($functionEnd)

    Assert-InstallerTextEncodingClean -Text $issContent -Context 'Generated installer script'

    $stampedIss = Join-Path $tempScripts "Baseline-Setup-$Version.iss"
    $utf8WithBom = New-Object System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($stampedIss, $issContent, $utf8WithBom)

    # ── Optionally persist the script only ───────────────────────────────────

    if ($GenerateScriptOnly)
    {
        $persistedPath = Join-Path $resolvedOutput "Baseline-Setup-$Version.iss"
        Copy-Item -LiteralPath $stampedIss -Destination $persistedPath -Force
        return [pscustomobject]@{
            ScriptPath    = $persistedPath
            InstallerPath = $null
            Version       = $Version
            Channel       = $updateChannel
            ChannelToken  = $setupChannelToken
            Compiled      = $false
        }
    }

    # ── Compile ───────────────────────────────────────────────────────────────

    $resolvedIscc = Resolve-IsccPath -RequestedPath $IsccPath
    if ([string]::IsNullOrWhiteSpace($resolvedIscc))
    {
        throw 'Inno Setup compiler (ISCC.exe) not found. Install Inno Setup 6 or pass -IsccPath.'
    }

    $setupFileName = Get-InstallerSetupFileName -Version $Version -ChannelToken $setupChannelToken
    $setupPath     = Join-Path $resolvedOutput $setupFileName

    if ((Test-Path -LiteralPath $setupPath -PathType Leaf) -and -not $Force)
    {
        throw "Installer already exists: $setupPath. Re-run with -Force to overwrite."
    }
    if ((Test-Path -LiteralPath $setupPath -PathType Leaf) -and $Force)
    {
        Remove-Item -LiteralPath $setupPath -Force
    }

    if ($PSCmdlet.ShouldProcess($setupPath, 'Build Baseline setup executable'))
    {
        $stdoutFile = Join-Path $tempScripts 'iscc.stdout.log'
        $stderrFile = Join-Path $tempScripts 'iscc.stderr.log'
        $compilerResult = $null
        $compilerError = $null
        try
        {
            $compilerResult = Invoke-InstallerIscc `
                -FilePath $resolvedIscc `
                -ArgumentList @('/Qp', "`"$stampedIss`"") `
                -StdoutFile $stdoutFile `
                -StderrFile $stderrFile `
                -TimeoutSeconds $IsccTimeoutSeconds
        }
        catch
        {
            $compilerError = $_
        }

        if ($compilerError -or $compilerResult.ExitCode -ne 0)
        {
            Write-Host '--- ISCC stdout ---'
            if (Test-Path -LiteralPath $stdoutFile) { Get-Content -LiteralPath $stdoutFile | Write-Host }
            Write-Host '--- ISCC stderr ---'
            if (Test-Path -LiteralPath $stderrFile) { Get-Content -LiteralPath $stderrFile | Write-Host }
            $persistDir = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineInstaller-failed-' + [System.Guid]::NewGuid().ToString('N'))
            New-Item -Path $persistDir -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $stampedIss -Destination $persistDir -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $stdoutFile -Destination $persistDir -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $stderrFile -Destination $persistDir -Force -ErrorAction SilentlyContinue
            # Snapshot the staged source root before the finally block wipes $tempRoot;
            # without this, the CI catch handler has nothing left to inspect.
            $listingFile = Join-Path $persistDir 'extract-listing.txt'
            if (Test-Path -LiteralPath $sourceRoot -PathType Container)
            {
                "Source root: $sourceRoot" | Out-File -LiteralPath $listingFile -Encoding UTF8
                "" | Out-File -LiteralPath $listingFile -Encoding UTF8 -Append
                Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force -ErrorAction SilentlyContinue |
                    Select-Object Mode, Length, FullName |
                    Format-Table -AutoSize |
                    Out-String |
                    Out-File -LiteralPath $listingFile -Encoding UTF8 -Append
            }
            else
            {
                "Source root missing at failure time: $sourceRoot" | Out-File -LiteralPath $listingFile -Encoding UTF8
            }
            Write-Host "Persisted ISCC diagnostics to: $persistDir"
            if ($compilerError)
            {
                throw $compilerError
            }
            throw "ISCC failed with exit code $($compilerResult.ExitCode)."
        }
        else
        {
            if (Test-Path -LiteralPath $stdoutFile) { Get-Content -LiteralPath $stdoutFile | Write-Host }
        }
    }

    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf))
    {
        throw "Expected installer was not produced: $setupPath"
    }

    $setupHashManifestPath = $setupPath + '.sha256.json'
    $setupHashManifest = [ordered]@{
        schemaVersion = 1
        algorithm    = 'sha256'
        generatedUtc = ([System.DateTime]::UtcNow.ToString('o'))
        version      = $Version
        files        = [ordered]@{
            $setupFileName = Get-InstallerFileSha256 -Path $setupPath
        }
    }
    $setupHashManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $setupHashManifestPath -Encoding UTF8

    $repoSetupPath = Join-Path $repoRoot $setupFileName
    $repoSetupHashManifestPath = Join-Path $repoRoot ([System.IO.Path]::GetFileName($setupHashManifestPath))

    if (-not [string]::Equals([System.IO.Path]::GetFullPath($setupPath), [System.IO.Path]::GetFullPath($repoSetupPath), [System.StringComparison]::OrdinalIgnoreCase))
    {
        Copy-Item -LiteralPath $setupPath -Destination $repoSetupPath -Force
    }
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($setupHashManifestPath), [System.IO.Path]::GetFullPath($repoSetupHashManifestPath), [System.StringComparison]::OrdinalIgnoreCase))
    {
        Copy-Item -LiteralPath $setupHashManifestPath -Destination $repoSetupHashManifestPath -Force
    }

    [pscustomobject]@{
        InstallerPath    = $setupPath
        HashManifestPath = $setupHashManifestPath
        Version          = $Version
        Channel          = $updateChannel
        ChannelToken     = $setupChannelToken
        SizeBytes        = [int64](Get-Item -LiteralPath $setupPath).Length
        Compiled         = $true
    }
}
finally
{
    if (Test-Path -LiteralPath $tempRoot)
    {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
