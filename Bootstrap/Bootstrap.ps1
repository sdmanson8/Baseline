<#
    .SYNOPSIS
    Download and install Baseline from GitHub.

    .DESCRIPTION
    This script is designed to be hosted at a raw GitHub URL, downloaded to a
    local file, inspected if desired, and executed as a script file:

        Invoke-WebRequest -Uri https://raw.githubusercontent.com/sdmanson8/Baseline/main/Bootstrap/Bootstrap.ps1 -OutFile "$env:TEMP\Baseline.Bootstrap.ps1" -UseBasicParsing
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\Baseline.Bootstrap.ps1"

    It resolves GitHub's latest release redirect, downloads the release zip,
    verifies it, extracts it to a folder under the user's Downloads directory,
    and then runs Bootstrap.Install.ps1 from inside the verified archive. The
    packaged installer script locates and verifies Baseline-<version>-setup.exe
    before running it. When BASELINE_PRESET is
    set or -Preset is supplied, the preset is forwarded to the installed launcher.

    .NOTES
    SECURITY: Do not execute remote bootstrap content directly from a pipeline.
    This bootstrap script itself is not signature-validated or hash-pinned.
    Release payload integrity is enforced by downloading the companion
    <release-zip>.sha256.json manifest from the GitHub Release and verifying
    SHA-256 for both the zip and the extracted setup executable before launch.
    For higher assurance, download the release assets manually from the
    Releases page, verify the hash manifest yourself, and run the setup
    executable directly.
#>

[CmdletBinding()]
param(
    [string]$Owner = 'sdmanson8',
    [string]$Repository = 'Baseline',
    [string]$Preset,
    [ValidateSet('stable', 'beta')]
    [string]$ReleaseChannel,
    [string]$CacheRoot = (Join-Path (Join-Path ([System.Environment]::GetFolderPath('UserProfile')) 'Downloads') 'Baseline-Bootstrap')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

<#
    .SYNOPSIS
#>

function Write-BootstrapSwallowedException
{
    param(
        [Parameter(Mandatory = $true)]
        [object]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [ValidateSet('Debug', 'Warning', 'Error')]
        [string]$Severity = 'Debug'
    )

    if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
    {
        Write-SwallowedException -ErrorRecord $ErrorRecord -Source $Source -Severity $Severity
        return
    }

    $message = '[swallow] {0}: {1}' -f $Source, $ErrorRecord.Exception.Message
    switch ($Severity)
    {
        'Warning' { Write-Warning $message }
        'Error' { Write-Error $message -ErrorAction Continue }
        default { Write-Verbose $message }
    }
}

<#
    .SYNOPSIS
#>

function Enable-Tls12
{
    try
    {
        # Ensure no prior script has disabled certificate validation (MITM risk).
        if ($null -ne [System.Net.ServicePointManager]::ServerCertificateValidationCallback)
        {
            Write-Warning "ServerCertificateValidationCallback was overridden by a prior script - resetting to default."
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        }

        $current = [System.Net.ServicePointManager]::SecurityProtocol
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (($current -band $tls12) -ne $tls12)
        {
            [System.Net.ServicePointManager]::SecurityProtocol = $current -bor $tls12
        }
    }
    catch { Write-BootstrapSwallowedException -ErrorRecord $_ -Source 'Bootstrap.Enable-Tls12' -Severity Warning }
}

<#
    .SYNOPSIS
#>

function Resolve-RawBootstrapPreset
{
    param(
        [string]$Preset,
        [string]$EnvironmentPreset = $env:BASELINE_PRESET
    )

    $candidate = if ([string]::IsNullOrWhiteSpace($Preset)) { $EnvironmentPreset } else { $Preset }
    if ([string]::IsNullOrWhiteSpace($candidate))
    {
        return $null
    }

    if ($candidate -notmatch '^[A-Za-z0-9_.-]+$')
    {
        throw ("Invalid preset token '{0}'. Use letters, numbers, dots, underscores, or hyphens only." -f $candidate)
    }

	return [string]$candidate
}

<#
    .SYNOPSIS
#>

function Format-RawBootstrapByteCount
{
    param(
        [Parameter(Mandatory = $true)]
        [int64]$Bytes
    )

    if ($Bytes -ge 1GB)
    {
        return ('{0:N1} GB' -f ($Bytes / 1GB))
    }

    if ($Bytes -ge 1MB)
    {
        return ('{0:N1} MB' -f ($Bytes / 1MB))
    }

    if ($Bytes -ge 1KB)
    {
        return ('{0:N1} KB' -f ($Bytes / 1KB))
    }

    return ('{0:N0} B' -f $Bytes)
}

<#
    .SYNOPSIS
#>

function Invoke-RawBootstrapDownloadFile
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [string]$Label = 'Downloaded file'
    )

    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.UserAgent = 'BaselineBootstrap'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $request.AllowAutoRedirect = $true

    $response = $null
    $inputStream = $null
    $outputStream = $null
    $activity = "Downloading $Label..."
    $statusPrefix = "Downloading $Label"
    $previousProgressPreference = $ProgressPreference

    try
    {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $totalBytes = [int64]$response.ContentLength
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] 65536
        $receivedBytes = [int64]0
        $ProgressPreference = 'Continue'

        while ($true)
        {
            $read = $inputStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0)
            {
                break
            }

            $outputStream.Write($buffer, 0, $read)
            $receivedBytes += [int64]$read

            if ($totalBytes -gt 0)
            {
                $percentComplete = [System.Math]::Min(100, [System.Math]::Floor(($receivedBytes * 100.0) / $totalBytes))
                $operation = '{0} of {1}' -f (Format-RawBootstrapByteCount -Bytes $receivedBytes), (Format-RawBootstrapByteCount -Bytes $totalBytes)
                Write-Progress -Activity $activity -Status $statusPrefix -CurrentOperation $operation -PercentComplete $percentComplete
            }
            else
            {
                $operation = '{0} downloaded' -f (Format-RawBootstrapByteCount -Bytes $receivedBytes)
                Write-Progress -Activity $activity -Status $statusPrefix -CurrentOperation $operation
            }
        }

        $outputStream.Flush()

        if ($totalBytes -gt 0 -and $receivedBytes -ne $totalBytes)
        {
            throw "Downloaded byte count for '$Label' did not match Content-Length. Expected $totalBytes but received $receivedBytes."
        }
    }
    finally
    {
        Write-Progress -Activity $activity -Completed
        $ProgressPreference = $previousProgressPreference

        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Get-RawBootstrapHttpErrorMessage
{
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebException]$Exception
    )

    $response = $Exception.Response
    if (-not $response)
    {
        return $Exception.Message
    }

    $statusText = $Exception.Message
    try
    {
        $httpResponse = [System.Net.HttpWebResponse]$response
        $statusText = '{0} {1}' -f ([int]$httpResponse.StatusCode), $httpResponse.StatusDescription
    }
    catch { Write-BootstrapSwallowedException -ErrorRecord $_ -Source 'Bootstrap.Get-RawBootstrapHttpErrorMessage.Status' -Severity Debug }

    $bodyText = ''
    $stream = $null
    $reader = $null
    try
    {
        $stream = $response.GetResponseStream()
        if ($stream)
        {
            $reader = [System.IO.StreamReader]::new($stream)
            $bodyText = $reader.ReadToEnd()
        }
    }
    catch { Write-BootstrapSwallowedException -ErrorRecord $_ -Source 'Bootstrap.Get-RawBootstrapHttpErrorMessage.Body' -Severity Debug }
    finally
    {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        $response.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($bodyText))
    {
        return $statusText
    }

    return ('{0}. Response body: {1}' -f $statusText, $bodyText.Trim())
}

<#
    .SYNOPSIS
#>

function Resolve-RawBootstrapLatestReleaseTag
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $latestUri = "https://github.com/$Owner/$Repository/releases/latest"
    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($latestUri)
    $request.Method = 'GET'
    $request.UserAgent = 'BaselineBootstrap'
    $request.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $request.AllowAutoRedirect = $false

    $response = $null
    try
    {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $candidateUris = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace([string]$response.Headers['Location']))
        {
            [void]$candidateUris.Add([string]$response.Headers['Location'])
        }
        if ($response.ResponseUri)
        {
            [void]$candidateUris.Add($response.ResponseUri.AbsoluteUri)
        }

        foreach ($candidateUri in @($candidateUris))
        {
            $match = [regex]::Match([string]$candidateUri, '/releases/tag/([^/?#]+)')
            if ($match.Success)
            {
                return [System.Uri]::UnescapeDataString($match.Groups[1].Value)
            }
        }

        throw "GitHub did not return a latest-release tag redirect for $latestUri."
    }
    catch [System.Net.WebException]
    {
        $message = Get-RawBootstrapHttpErrorMessage -Exception $_.Exception
        throw "Failed to resolve latest GitHub release for $Owner/$Repository from $latestUri`: $message"
    }
    finally
    {
        if ($response) { $response.Dispose() }
    }
}

<#
    .SYNOPSIS
#>

function Resolve-RawBootstrapReleaseAssetName
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('stable', 'beta')]
        [string]$ReleaseChannel
    )

    $cleanVersion = $TagName.Trim()
    if ($cleanVersion.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase))
    {
        $cleanVersion = $cleanVersion.Substring(1)
    }

    $channelSuffix = '-' + $ReleaseChannel
    if (-not $cleanVersion.EndsWith($channelSuffix, [System.StringComparison]::OrdinalIgnoreCase))
    {
        $cleanVersion = $cleanVersion + $channelSuffix
    }

    return "Baseline-$cleanVersion.zip"
}

<#
    .SYNOPSIS
#>

function Get-RawBootstrapFileSha256
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "File was not found: $Path"
    }

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

function Get-RawBootstrapReleaseIntegrityManifest
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf))
    {
        throw "Release integrity manifest was not found: $ManifestPath"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$manifest.algorithm -ne 'sha256')
    {
        throw "Unsupported release integrity manifest algorithm '$([string]$manifest.algorithm)'."
    }

    if (-not $manifest.PSObject.Properties['files'] -or -not $manifest.files)
    {
        throw "Release integrity manifest does not contain a files map: $ManifestPath"
    }

    return $manifest
}

<#
    .SYNOPSIS
#>

function Get-RawBootstrapReleaseAssetSha256
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    $manifest = Get-RawBootstrapReleaseIntegrityManifest -ManifestPath $ManifestPath
    $assetProperty = $manifest.files.PSObject.Properties[$AssetName]
    if (-not $assetProperty -or [string]::IsNullOrWhiteSpace([string]$assetProperty.Value))
    {
        throw "Release integrity manifest '$ManifestPath' does not contain a SHA-256 entry for '$AssetName'."
    }

    return ([string]$assetProperty.Value).Trim().ToUpperInvariant()
}

<#
    .SYNOPSIS
#>

function Assert-RawBootstrapReleaseAssetHash
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$AssetName,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$Label = 'Downloaded file'
    )

    $expected = Get-RawBootstrapReleaseAssetSha256 -ManifestPath $ManifestPath -AssetName $AssetName
    $actual = Get-RawBootstrapFileSha256 -Path $FilePath
    if ($actual -ne $expected)
    {
        throw "$Label failed SHA-256 verification. Expected $expected but received $actual."
    }

    return $actual
}

<#
    .SYNOPSIS
    Finds the verified bootstrap install script in an extracted release archive.

    .DESCRIPTION
    Requires exactly one Bootstrap.Install.ps1 file under the verified release archive so the raw bootstrap can hand off to packaged install logic without downloading helper scripts from raw GitHub.
#>
function Find-BootstrapInstallScript
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtractRoot
    )

    $matches = @(Get-ChildItem -Path $ExtractRoot -Filter 'Bootstrap.Install.ps1' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1)
    {
        throw "Expected exactly one Bootstrap.Install.ps1 under $ExtractRoot. Found $($matches.Count)."
    }

    return $matches[0].FullName
}
<#
    .SYNOPSIS
#>

function Compare-BootstrapReleaseVersions
{
    param(
        [AllowNull()]
        [string]$LeftVersion,

        [AllowNull()]
        [string]$RightVersion
    )

    $parseVersionInfo = {
        param([AllowNull()][string]$VersionText)

        if ([string]::IsNullOrWhiteSpace([string]$VersionText))
        {
            return $null
        }

        $trimmedText = ([string]$VersionText).Trim()
        $comparableText = $trimmedText.Split('+')[0].Trim()
        $versionPattern = '^v?(?<Major>\d+)\.(?<Minor>\d+)\.(?<Patch>\d+)(?:-(?<Prerelease>[0-9A-Za-z][0-9A-Za-z.-]*))?$'
        if ($comparableText -notmatch $versionPattern)
        {
            return [pscustomobject]@{
                OriginalText     = $trimmedText
                Parsed           = $false
                CoreVersion      = $null
                PrereleaseTokens = @()
                IsPrerelease     = $false
            }
        }

        $parts = @($Matches['Major'], $Matches['Minor'], $Matches['Patch'], '0')

        $coreVersion = $null
        try
        {
            $coreVersion = [System.Version]($parts -join '.')
        }
        catch
        {
            return [pscustomobject]@{
                OriginalText     = $trimmedText
                Parsed           = $false
                CoreVersion      = $null
                PrereleaseTokens = @()
                IsPrerelease     = $false
            }
        }

        $prereleaseTokens = @()

        if (-not [string]::IsNullOrWhiteSpace($Matches['Prerelease']))
        {
            $prereleaseTokens = @([string]$Matches['Prerelease'] -split '[.-]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return [pscustomobject]@{
            OriginalText     = $trimmedText
            Parsed           = $true
            CoreVersion      = $coreVersion
            PrereleaseTokens = $prereleaseTokens
            IsPrerelease     = ($prereleaseTokens.Count -gt 0)
        }
    }

    $leftInfo = & $parseVersionInfo $LeftVersion
    $rightInfo = & $parseVersionInfo $RightVersion

    if ($null -eq $leftInfo -and $null -eq $rightInfo) { return 0 }
    if ($null -eq $leftInfo) { return -1 }
    if ($null -eq $rightInfo) { return 1 }

    if (-not $leftInfo.Parsed -and -not $rightInfo.Parsed)
    {
        return [Math]::Sign([string]::Compare($leftInfo.OriginalText, $rightInfo.OriginalText, [System.StringComparison]::OrdinalIgnoreCase))
    }
    if (-not $leftInfo.Parsed) { return -1 }
    if (-not $rightInfo.Parsed) { return 1 }

    $coreComparison = $leftInfo.CoreVersion.CompareTo($rightInfo.CoreVersion)
    if ($coreComparison -ne 0)
    {
        return [Math]::Sign($coreComparison)
    }

    if ($leftInfo.IsPrerelease -and -not $rightInfo.IsPrerelease) { return -1 }
    if (-not $leftInfo.IsPrerelease -and $rightInfo.IsPrerelease) { return 1 }
    if (-not $leftInfo.IsPrerelease -and -not $rightInfo.IsPrerelease) { return 0 }

    $maxTokenCount = [Math]::Max($leftInfo.PrereleaseTokens.Count, $rightInfo.PrereleaseTokens.Count)
    for ($index = 0; $index -lt $maxTokenCount; $index++)
    {
        if ($index -ge $leftInfo.PrereleaseTokens.Count) { return -1 }
        if ($index -ge $rightInfo.PrereleaseTokens.Count) { return 1 }

        $leftToken = [string]$leftInfo.PrereleaseTokens[$index]
        $rightToken = [string]$rightInfo.PrereleaseTokens[$index]
        $leftTokenIsNumber = ($leftToken -match '^\d+$')
        $rightTokenIsNumber = ($rightToken -match '^\d+$')

        if ($leftTokenIsNumber -and $rightTokenIsNumber)
        {
            $leftNumber = [int64]$leftToken
            $rightNumber = [int64]$rightToken
            if ($leftNumber -ne $rightNumber)
            {
                return [Math]::Sign($leftNumber.CompareTo($rightNumber))
            }
            continue
        }

        if ($leftTokenIsNumber -and -not $rightTokenIsNumber) { return -1 }
        if (-not $leftTokenIsNumber -and $rightTokenIsNumber) { return 1 }

        $tokenComparison = [string]::Compare($leftToken, $rightToken, [System.StringComparison]::OrdinalIgnoreCase)
        if ($tokenComparison -ne 0)
        {
            return [Math]::Sign($tokenComparison)
        }
    }

    return 0
}

<#
    .SYNOPSIS
#>

function Get-BootstrapLatestRelease
{
    param(
        [AllowNull()]
        [object[]]$Releases
    )

    $bestRelease = $null
    $bestPublishedAt = [DateTimeOffset]::MinValue

    foreach ($release in @($Releases))
    {
        if ($null -eq $release -or [bool]$release.draft)
        {
            continue
        }

        $candidateTag = [string]$release.tag_name
        if ([string]::IsNullOrWhiteSpace([string]$candidateTag))
        {
            continue
        }

        $candidatePublishedAt = [DateTimeOffset]::MinValue
        foreach ($propertyName in @('published_at', 'created_at'))
        {
            $rawPublishedAt = [string]$release.$propertyName
            if ([string]::IsNullOrWhiteSpace([string]$rawPublishedAt))
            {
                continue
            }

            try
            {
                $candidatePublishedAt = [DateTimeOffset]::Parse($rawPublishedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                break
            }
            catch { Write-BootstrapSwallowedException -ErrorRecord $_ -Source 'Bootstrap.Get-BootstrapLatestRelease.ParsePublishedAt' -Severity Debug }
        }

        if ($null -eq $bestRelease)
        {
            $bestRelease = $release
            $bestPublishedAt = $candidatePublishedAt
            continue
        }

        $comparison = Compare-BootstrapReleaseVersions -LeftVersion $candidateTag -RightVersion ([string]$bestRelease.tag_name)
        if ($comparison -gt 0 -or ($comparison -eq 0 -and $candidatePublishedAt -gt $bestPublishedAt))
        {
            $bestRelease = $release
            $bestPublishedAt = $candidatePublishedAt
        }
    }

    return $bestRelease
}

$Preset = Resolve-RawBootstrapPreset -Preset $Preset

try
{
    Enable-Tls12

    $resolvedCache = [System.IO.Path]::GetFullPath($CacheRoot)
    $resolvedDownloads = [System.IO.Path]::GetFullPath((Join-Path ([System.Environment]::GetFolderPath('UserProfile')) 'Downloads')).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedCache.StartsWith($resolvedDownloads, [System.StringComparison]::OrdinalIgnoreCase))
    {
        throw "CacheRoot must be under $resolvedDownloads. Received: $CacheRoot"
    }

    if (Test-Path -LiteralPath $CacheRoot)
    {
        try
        {
            Remove-Item -LiteralPath $CacheRoot -Recurse -Force -ErrorAction Stop
        }
        catch
        {
            Write-Error "Failed to clean bootstrap cache '$CacheRoot'. Stale or locked content could affect extraction: $($_.Exception.Message)"
            throw
        }
    }

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null

    $archivePath = Join-Path $CacheRoot 'Baseline-release.zip'
    $extractRoot = Join-Path $CacheRoot 'extract'

    $releaseChannel = if (-not [string]::IsNullOrWhiteSpace($ReleaseChannel)) { $ReleaseChannel } else { 'stable' }
    Write-Host "Resolving latest GitHub release..."
    $latestTag = Resolve-RawBootstrapLatestReleaseTag -Owner $Owner -Repository $Repository
    $assetName = Resolve-RawBootstrapReleaseAssetName -TagName $latestTag -ReleaseChannel $releaseChannel
    $integrityAssetName = $assetName + '.sha256.json'
    $downloadTag = [System.Uri]::EscapeDataString($latestTag)
    $downloadAsset = [System.Uri]::EscapeDataString($assetName)
    $downloadManifest = [System.Uri]::EscapeDataString($integrityAssetName)
    $downloadUrl = "https://github.com/$Owner/$Repository/releases/download/$downloadTag/$downloadAsset"
    $integrityUrl = "https://github.com/$Owner/$Repository/releases/download/$downloadTag/$downloadManifest"
    $archivePath = Join-Path $CacheRoot $assetName
    $integrityManifestPath = Join-Path $CacheRoot $integrityAssetName

    # Write-Host: intentional bootstrap progress output.
    Write-Host "Downloading $Repository $latestTag from $downloadUrl"
    Invoke-RawBootstrapDownloadFile -Uri $downloadUrl -OutFile $archivePath -Label 'Baseline release archive'
    Write-Host "Downloading release integrity manifest from $integrityUrl"
    Invoke-RawBootstrapDownloadFile -Uri $integrityUrl -OutFile $integrityManifestPath -Label 'release integrity manifest'
    $archiveHash = Assert-RawBootstrapReleaseAssetHash -ManifestPath $integrityManifestPath -AssetName $assetName -FilePath $archivePath -Label 'Release archive'
    Write-Host "Verified SHA-256 for $assetName`: $archiveHash"

    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

    $installScript = Find-BootstrapInstallScript -ExtractRoot $extractRoot
    Write-Host "Running verified bootstrap installer script $installScript..."
    & $installScript -ExtractRoot $extractRoot -ManifestPath $integrityManifestPath -Repository $Repository -Preset $Preset
}
catch
{
    Write-Error "Failed to bootstrap Baseline: $($_.Exception.Message)"
    throw
}
