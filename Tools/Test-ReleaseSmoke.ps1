<#
    .SYNOPSIS
    Release smoke-test entry point for Baseline artifact validation.

    .DESCRIPTION
    Runs the standard smoke suite with built-launcher checks enabled. Use this
    after building the launcher or before packaging a release.

    .EXAMPLE
    powershell -File .\Tools\Test-ReleaseSmoke.ps1

    .EXAMPLE
    powershell -File .\Tools\Test-ReleaseSmoke.ps1 -IncludeGUI

    .EXAMPLE
    powershell -File .\Tools\Test-ReleaseSmoke.ps1 -AllowUnsignedPreview
#>

[CmdletBinding()]
param (
    [switch]$IncludeGUI,
    [switch]$AllowUnsignedPreview
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$releaseGateFailures = 0

function Write-ReleaseGateResult
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Pass', 'Fail', 'Skip')]
        [string]$Result,

        [string]$Detail = ''
    )

    $prefix = switch ($Result)
    {
        'Pass' { '[PASS]' }
        'Fail' { '[FAIL]'; $script:releaseGateFailures++ }
        'Skip' { '[SKIP]' }
    }

    $line = "  $prefix $Name"
    if (-not [string]::IsNullOrWhiteSpace($Detail))
    {
        $line = "$line -- $Detail"
    }

    Write-Host $line
}

function Test-UnsignedPreviewAllowed
{
    [CmdletBinding()]
    param()

    $value = [string][Environment]::GetEnvironmentVariable('BASELINE_PREVIEW_UNSIGNED')
    $explicitPreviewOptIn = [bool]$AllowUnsignedPreview -or ($value -match '^(?i:1|true|yes|on)$')
    if (-not $explicitPreviewOptIn)
    {
        return $false
    }

    $manifestPath = Join-Path $repoRoot 'Module/Baseline.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        return $false
    }

    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    return $false
}

function Test-ReleaseArtifactSignature
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$AllowedSignerSubjects = @()
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        Write-ReleaseGateResult -Name "Authenticode: $Path" -Result Fail -Detail 'Artifact missing'
        return
    }

    if (-not (Get-Command -Name 'Get-AuthenticodeSignature' -ErrorAction SilentlyContinue))
    {
        Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Fail -Detail 'Get-AuthenticodeSignature is unavailable'
        return
    }

    $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid')
    {
        if (($signature.Status -eq 'NotSigned') -and (Test-UnsignedPreviewAllowed))
        {
            Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Pass -Detail 'Unsigned preview explicitly allowed'
            return
        }

        Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Fail -Detail "Status: $($signature.Status)"
        return
    }

    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ($AllowedSignerSubjects.Count -gt 0 -and $subject -notin $AllowedSignerSubjects)
    {
        Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Fail -Detail "Unexpected signer: $subject"
        return
    }

    if (-not $signature.TimeStamperCertificate)
    {
        Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Fail -Detail 'Missing RFC 3161 timestamp'
        return
    }

    Write-ReleaseGateResult -Name "Authenticode: $([System.IO.Path]::GetFileName($Path))" -Result Pass -Detail $subject
}

function Test-ReleaseAuthenticodeGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Release Authenticode Gate ===" -ForegroundColor Cyan

    $artifactPaths = New-Object System.Collections.Generic.List[string]
    $baselineExePath = Join-Path $repoRoot 'Baseline.exe'
    [void]$artifactPaths.Add($baselineExePath)

    foreach ($searchRoot in @($repoRoot, (Join-Path $repoRoot 'dist')))
    {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
        foreach ($setup in @(Get-ChildItem -LiteralPath $searchRoot -Filter 'Baseline-*-setup.exe' -File -ErrorAction SilentlyContinue))
        {
            if (-not $artifactPaths.Contains($setup.FullName))
            {
                [void]$artifactPaths.Add($setup.FullName)
            }
        }
    }

    $setupCount = @($artifactPaths | Where-Object { [System.IO.Path]::GetFileName($_) -like 'Baseline-*-setup.exe' }).Count
    if ($setupCount -eq 0)
    {
        Write-ReleaseGateResult -Name 'Authenticode: setup artifact presence' -Result Fail -Detail 'No Baseline-*-setup.exe artifact found in repo root or dist'
    }

    foreach ($artifactPath in $artifactPaths)
    {
        Test-ReleaseArtifactSignature -Path $artifactPath
    }
}

function Get-ReleaseGateInputFile
{
    [CmdletBinding()]
    param()

    $roots = @('Module', 'Bootstrap', 'Launcher', 'ShortcutLauncher', 'Tools', 'dist', 'dev_docs', 'Assets', 'Completion', 'Localizations')
    foreach ($rootName in $roots)
    {
        $rootPath = Join-Path $repoRoot $rootName
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\vendor\\' -and
                $_.FullName -notmatch '\\(bin|obj)\\' -and
                $_.FullName -notmatch '\\\.git\\' -and
                $_.FullName -notmatch '\\\.artifacts\\'
            }
    }

    foreach ($fileName in @('README.md', 'CHANGELOG.md', 'Baseline.exe'))
    {
        $path = Join-Path $repoRoot $fileName
        if (Test-Path -LiteralPath $path -PathType Leaf)
        {
            Get-Item -LiteralPath $path
        }
    }
}

function Test-StaleTestReportGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Test Report Freshness Gate ===" -ForegroundColor Cyan

    $reportPath = Join-Path $repoRoot 'Tests/TestReport.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf))
    {
        Write-ReleaseGateResult -Name 'Tests/TestReport.json freshness' -Result Fail -Detail 'Report missing'
        return
    }

    try
    {
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $generatedUtc = ([datetimeoffset]::Parse([string]$report.generated)).UtcDateTime
    }
    catch
    {
        Write-ReleaseGateResult -Name 'Tests/TestReport.json freshness' -Result Fail -Detail $_.Exception.Message
        return
    }

    $latestInput = Get-ReleaseGateInputFile |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $latestInput)
    {
        Write-ReleaseGateResult -Name 'Tests/TestReport.json freshness' -Result Fail -Detail 'No release input files found'
        return
    }

    if ($generatedUtc -lt $latestInput.LastWriteTimeUtc)
    {
        $relativePath = $latestInput.FullName.Substring($repoRoot.Length + 1)
        Write-ReleaseGateResult -Name 'Tests/TestReport.json freshness' -Result Fail -Detail ("Report {0:o} predates {1} ({2:o})" -f $generatedUtc, $relativePath, $latestInput.LastWriteTimeUtc)
        return
    }

    Write-ReleaseGateResult -Name 'Tests/TestReport.json freshness' -Result Pass -Detail ("Generated {0:o}" -f $generatedUtc)
}

function Test-ReleaseModuleIntegrityGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Module Integrity Manifest Gate ===" -ForegroundColor Cyan

    $moduleRoot = Join-Path $repoRoot 'Module'
    $jsonHelper = Join-Path $moduleRoot 'SharedHelpers/Json.Helpers.ps1'
    $integrityHelper = Join-Path $moduleRoot 'SharedHelpers/Integrity.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $jsonHelper -PathType Leaf) -or -not (Test-Path -LiteralPath $integrityHelper -PathType Leaf))
    {
        Write-ReleaseGateResult -Name 'Module integrity manifest' -Result Fail -Detail 'Integrity helper files are missing'
        return
    }

    try
    {
        . $jsonHelper
        . $integrityHelper
        [void](Test-BaselineModuleIntegrity -ModuleRoot $moduleRoot)
        Write-ReleaseGateResult -Name 'Module integrity manifest' -Result Pass
    }
    catch
    {
        Write-ReleaseGateResult -Name 'Module integrity manifest' -Result Fail -Detail $_.Exception.Message
    }
}

function Test-ReleaseZipHygieneGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Release Zip Hygiene Gate ===" -ForegroundColor Cyan

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zipFiles = @()
    foreach ($searchRoot in @($repoRoot, (Join-Path $repoRoot 'dist')))
    {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
        $zipFiles += @(Get-ChildItem -LiteralPath $searchRoot -Filter 'Baseline-*.zip' -File -ErrorAction SilentlyContinue)
    }
    $zipFiles = @($zipFiles | Sort-Object FullName -Unique)

    if ($zipFiles.Count -eq 0)
    {
        Write-ReleaseGateResult -Name 'Release zip hygiene' -Result Skip -Detail 'No Baseline-*.zip artifact found'
        return
    }

    foreach ($zipFile in $zipFiles)
    {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
        try
        {
            $badEntries = @(
                $archive.Entries |
                    Where-Object {
                        $entryName = [string]$_.FullName
                        $entryName -match '(^|/)(bin|obj)/' -or
                        $entryName -match '\.FileListAbsolute\.txt$' -or
                        $entryName -match '\.cache$' -or
                        $entryName -match '^[A-Za-z]:' -or
                        $entryName -match '\\'
                    } |
                    Select-Object -First 5 -ExpandProperty FullName
            )

            if ($badEntries.Count -gt 0)
            {
                Write-ReleaseGateResult -Name "Release zip hygiene: $($zipFile.Name)" -Result Fail -Detail ($badEntries -join ', ')
            }
            else
            {
                Write-ReleaseGateResult -Name "Release zip hygiene: $($zipFile.Name)" -Result Pass
            }
        }
        finally
        {
            $archive.Dispose()
        }
    }
}

function Get-ReleaseArtifactSha256
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

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

function Get-ReleaseZipEntrySha256
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry
    )

    $stream = $Entry.Open()
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

function Get-ReleaseArtifactIdentity
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )

    $baseName = $null
    $kind = $null
    if ($File.Name -match '^Baseline-(.+)-setup\.exe$')
    {
        $baseName = $Matches[1]
        $kind = 'setup'
    }
    elseif ($File.Name -match '^Baseline-(.+)\.zip$')
    {
        $baseName = $Matches[1]
        $kind = 'zip'
    }
    else
    {
        return $null
    }

    $version = $baseName
    $channel = 'stable'
    if ($baseName -match '^(.+)-(stable)$')
    {
        $version = $Matches[1]
        $channel = $Matches[2].ToLowerInvariant()
    }

    [pscustomobject]@{
        File     = $File
        Kind     = $kind
        Version  = $version
        Channel  = $channel
        Identity = ('{0}|{1}' -f $version, $channel)
    }
}

function Get-ReleaseHashManifestFileHash
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    if (-not $Manifest.files)
    {
        return $null
    }

    $property = $Manifest.files.PSObject.Properties[$FileName]
    if (-not $property)
    {
        return $null
    }

    return ([string]$property.Value).ToUpperInvariant()
}

function Test-ReleaseArtifactManifest
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Artifact
    )

    $manifestPath = $Artifact.FullName + '.sha256.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        Write-ReleaseGateResult -Name "Release manifest: $($Artifact.Name)" -Result Fail -Detail 'Missing .sha256.json manifest'
        return $null
    }

    try
    {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedHash = Get-ReleaseHashManifestFileHash -Manifest $manifest -FileName $Artifact.Name
        if ([string]::IsNullOrWhiteSpace($expectedHash))
        {
            Write-ReleaseGateResult -Name "Release manifest: $($Artifact.Name)" -Result Fail -Detail 'Manifest does not contain artifact hash'
            return $manifest
        }

        $actualHash = Get-ReleaseArtifactSha256 -Path $Artifact.FullName
        if ($actualHash -ne $expectedHash)
        {
            Write-ReleaseGateResult -Name "Release manifest: $($Artifact.Name)" -Result Fail -Detail 'Manifest hash does not match current file bytes'
            return $manifest
        }

        Write-ReleaseGateResult -Name "Release manifest: $($Artifact.Name)" -Result Pass
        return $manifest
    }
    catch
    {
        Write-ReleaseGateResult -Name "Release manifest: $($Artifact.Name)" -Result Fail -Detail $_.Exception.Message
        return $null
    }
}

function Test-ReleaseArtifactSetGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Release Artifact Set Gate ===" -ForegroundColor Cyan

    $distRoot = Join-Path $repoRoot 'dist'
    if (-not (Test-Path -LiteralPath $distRoot -PathType Container))
    {
        Write-ReleaseGateResult -Name 'Release artifact set' -Result Skip -Detail 'dist directory missing'
        return
    }

    $artifacts = @(
        Get-ChildItem -LiteralPath $distRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^Baseline-(.+-setup\.exe|.+\.zip)$' }
    )

    if ($artifacts.Count -eq 0)
    {
        Write-ReleaseGateResult -Name 'Release artifact set' -Result Skip -Detail 'No release artifacts found in dist'
        return
    }

    $identities = @($artifacts | ForEach-Object { Get-ReleaseArtifactIdentity -File $_ } | Where-Object { $null -ne $_ })
    $identityNames = @($identities | Select-Object -ExpandProperty Identity -Unique)
    if ($identityNames.Count -ne 1)
    {
        Write-ReleaseGateResult -Name 'Release artifact identity exclusivity' -Result Fail -Detail ($identityNames -join ', ')
    }
    else
    {
        Write-ReleaseGateResult -Name 'Release artifact identity exclusivity' -Result Pass -Detail $identityNames[0]
    }

    $manifestsByArtifact = @{}
    foreach ($artifact in $artifacts)
    {
        $manifestsByArtifact[$artifact.Name] = Test-ReleaseArtifactManifest -Artifact $artifact
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $looseSetupsByName = @{}
    foreach ($setup in @($artifacts | Where-Object { $_.Name -like 'Baseline-*-setup.exe' }))
    {
        $looseSetupsByName[$setup.Name] = $setup
    }

    foreach ($zipFile in @($artifacts | Where-Object { $_.Extension -eq '.zip' }))
    {
        $zipManifest = $manifestsByArtifact[$zipFile.Name]
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
        try
        {
            $setupEntries = @(
                $archive.Entries |
                    Where-Object { [System.IO.Path]::GetFileName([string]$_.FullName) -like 'Baseline-*-setup.exe' }
            )

            if ($setupEntries.Count -ne 1)
            {
                Write-ReleaseGateResult -Name "ZIP setup payload: $($zipFile.Name)" -Result Fail -Detail "Expected one setup exe, found $($setupEntries.Count)"
                continue
            }

            $entry = $setupEntries[0]
            $entryName = [System.IO.Path]::GetFileName([string]$entry.FullName)
            $entryHash = Get-ReleaseZipEntrySha256 -Entry $entry
            $manifestEntryHash = if ($zipManifest) { Get-ReleaseHashManifestFileHash -Manifest $zipManifest -FileName $entryName } else { $null }

            if (-not [string]::IsNullOrWhiteSpace($manifestEntryHash) -and $entryHash -ne $manifestEntryHash)
            {
                Write-ReleaseGateResult -Name "ZIP setup manifest: $($zipFile.Name)" -Result Fail -Detail "$entryName hash differs from zip manifest"
            }
            else
            {
                Write-ReleaseGateResult -Name "ZIP setup manifest: $($zipFile.Name)" -Result Pass -Detail $entryName
            }

            if ($looseSetupsByName.ContainsKey($entryName))
            {
                $looseHash = Get-ReleaseArtifactSha256 -Path $looseSetupsByName[$entryName].FullName
                if ($looseHash -ne $entryHash)
                {
                    Write-ReleaseGateResult -Name "Loose setup matches ZIP: $entryName" -Result Fail -Detail 'Loose setup bytes differ from ZIP-contained setup'
                }
                else
                {
                    Write-ReleaseGateResult -Name "Loose setup matches ZIP: $entryName" -Result Pass
                }
            }
        }
        finally
        {
            $archive.Dispose()
        }
    }
}

function Get-ReleaseMojibakeMarker
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

function Test-GeneratedInstallerScriptEncodingGate
{
    [CmdletBinding()]
    param()

    Write-Host "`n=== Generated Installer Script Encoding Gate ===" -ForegroundColor Cyan

    $distRoot = Join-Path $repoRoot 'dist'
    if (-not (Test-Path -LiteralPath $distRoot -PathType Container))
    {
        Write-ReleaseGateResult -Name 'Generated installer script encoding' -Result Skip -Detail 'dist directory missing'
        return
    }

    $generatedScripts = @(Get-ChildItem -LiteralPath $distRoot -Filter 'Baseline-Setup-*.iss' -File -ErrorAction SilentlyContinue)
    if ($generatedScripts.Count -eq 0)
    {
        Write-ReleaseGateResult -Name 'Generated installer script encoding' -Result Skip -Detail 'No generated setup scripts found'
        return
    }

    $utf8Strict = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false, $true)
    foreach ($scriptFile in $generatedScripts)
    {
        try
        {
            $content = [System.IO.File]::ReadAllText($scriptFile.FullName, $utf8Strict)
            $badMarker = $null
            foreach ($marker in (Get-ReleaseMojibakeMarker))
            {
                if ($content.Contains($marker))
                {
                    $badMarker = @($marker.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int][char]$_ }) -join ' '
                    break
                }
            }

            if ($badMarker)
            {
                Write-ReleaseGateResult -Name "Generated installer script encoding: $($scriptFile.Name)" -Result Fail -Detail "Mojibake marker $badMarker"
            }
            else
            {
                Write-ReleaseGateResult -Name "Generated installer script encoding: $($scriptFile.Name)" -Result Pass
            }
        }
        catch
        {
            Write-ReleaseGateResult -Name "Generated installer script encoding: $($scriptFile.Name)" -Result Fail -Detail $_.Exception.Message
        }
    }
}

$smokeTestPath = Join-Path $PSScriptRoot 'Test-SmokeTest.ps1'
if (-not (Test-Path -LiteralPath $smokeTestPath -PathType Leaf))
{
    throw "Smoke-test script not found: $smokeTestPath"
}

& $smokeTestPath -RequireReleaseArtifacts -IncludeGUI:$IncludeGUI
$smokeExitCode = $LASTEXITCODE
if ($smokeExitCode -ne 0)
{
    exit $smokeExitCode
}

Test-ReleaseAuthenticodeGate
Test-ReleaseArtifactSetGate
Test-GeneratedInstallerScriptEncodingGate
Test-ReleaseModuleIntegrityGate
Test-StaleTestReportGate
Test-ReleaseZipHygieneGate

if ($releaseGateFailures -gt 0)
{
    Write-Host "`n  RELEASE SMOKE TEST FAILED" -ForegroundColor Red
    exit 1
}

Write-Host "`n  RELEASE GATES PASSED" -ForegroundColor Green
exit 0
