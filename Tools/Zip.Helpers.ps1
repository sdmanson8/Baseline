<#
    .SYNOPSIS
    Shared ZIP creation and validation helpers for Baseline packaging.
#>

Set-StrictMode -Version Latest

function Get-BaselineZipNormalizedEntryName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName
    )

    $normalized = ($EntryName -replace '\\', '/').TrimStart('/')
    $normalized = $normalized.Normalize([System.Text.NormalizationForm]::FormC)

    if ([string]::IsNullOrWhiteSpace($normalized))
    {
        throw 'ZIP entry name cannot be empty.'
    }

    $segments = @($normalized -split '/')
    if ($segments -contains '..')
    {
        throw "ZIP entry path traversal is not allowed: $EntryName"
    }

    if ([System.IO.Path]::IsPathRooted($normalized))
    {
        throw "ZIP entry path must be relative: $EntryName"
    }

    return $normalized
}

function New-BaselineZipArchive
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DestinationZip,

        [string]$EntryPrefix,

        [string[]]$ExcludeRelativePath = @()
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourceDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Container))
    {
        throw "ZIP source directory not found: $sourceFullPath"
    }

    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationZip)
    $destinationDirectory = Split-Path -Path $destinationFullPath -Parent
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container))
    {
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $destinationFullPath)
    {
        Remove-Item -LiteralPath $destinationFullPath -Force
    }

    $prefix = ''
    if (-not [string]::IsNullOrWhiteSpace($EntryPrefix))
    {
        $prefix = (Get-BaselineZipNormalizedEntryName -EntryName $EntryPrefix).TrimEnd('/') + '/'
    }

    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($relativePath in $ExcludeRelativePath)
    {
        if (-not [string]::IsNullOrWhiteSpace($relativePath))
        {
            [void]$excluded.Add((Get-BaselineZipNormalizedEntryName -EntryName $relativePath))
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $encoding = [System.Text.Encoding]::UTF8
    $compression = [System.IO.Compression.CompressionLevel]::Optimal
    $zip = [System.IO.Compression.ZipFile]::Open($destinationFullPath, [System.IO.Compression.ZipArchiveMode]::Create, $encoding)

    try
    {
        $files = [System.IO.Directory]::EnumerateFiles($sourceFullPath, '*', [System.IO.SearchOption]::AllDirectories) |
            Sort-Object

        foreach ($file in $files)
        {
            $fileFullPath = [System.IO.Path]::GetFullPath($file)
            if ([string]::Equals($fileFullPath, $destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase))
            {
                continue
            }

            $relative = $fileFullPath.Substring($sourceFullPath.Length).TrimStart(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )
            $relative = Get-BaselineZipNormalizedEntryName -EntryName $relative

            if ($excluded.Contains($relative))
            {
                continue
            }

            $entryName = Get-BaselineZipNormalizedEntryName -EntryName ($prefix + $relative)
            if (-not $seen.Add($entryName))
            {
                throw "Multiple files normalize to the same ZIP entry name: $entryName"
            }

            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip,
                $fileFullPath,
                $entryName,
                $compression
            ) | Out-Null
        }
    }
    finally
    {
        if ($null -ne $zip)
        {
            $zip.Dispose()
        }
    }

    return (Get-Item -LiteralPath $destinationFullPath)
}

function Read-BaselineZipUInt16
{
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return [System.BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-BaselineZipUInt32
{
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return [System.BitConverter]::ToUInt32($Bytes, $Offset)
}

function Test-BaselineZipUnicodeIntegrity
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$ExpectedEntry = @()
    )

    $zipPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $bytes = [System.IO.File]::ReadAllBytes($zipPath)
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $entries = New-Object 'System.Collections.Generic.List[string]'
    $utf8 = [System.Text.Encoding]::UTF8

    for ($i = 0; $i -le ($bytes.Length - 46); $i++)
    {
        if ($bytes[$i] -ne 0x50 -or $bytes[$i + 1] -ne 0x4b -or $bytes[$i + 2] -ne 0x01 -or $bytes[$i + 3] -ne 0x02)
        {
            continue
        }

        $flags = Read-BaselineZipUInt16 -Bytes $bytes -Offset ($i + 8)
        $nameLength = Read-BaselineZipUInt16 -Bytes $bytes -Offset ($i + 28)
        $extraLength = Read-BaselineZipUInt16 -Bytes $bytes -Offset ($i + 30)
        $commentLength = Read-BaselineZipUInt16 -Bytes $bytes -Offset ($i + 32)
        $localOffset = [int](Read-BaselineZipUInt32 -Bytes $bytes -Offset ($i + 42))

        $centralNameBytes = New-Object byte[] $nameLength
        [System.Array]::Copy($bytes, $i + 46, $centralNameBytes, 0, $nameLength)
        $entryName = $utf8.GetString($centralNameBytes)
        [void]$entries.Add($entryName)

        if ($localOffset -lt 0 -or ($localOffset + 30) -gt $bytes.Length -or
            $bytes[$localOffset] -ne 0x50 -or $bytes[$localOffset + 1] -ne 0x4b -or
            $bytes[$localOffset + 2] -ne 0x03 -or $bytes[$localOffset + 3] -ne 0x04)
        {
            [void]$issues.Add("Local header missing for '$entryName'.")
        }
        else
        {
            $localNameLength = Read-BaselineZipUInt16 -Bytes $bytes -Offset ($localOffset + 26)
            $localNameBytes = New-Object byte[] $localNameLength
            [System.Array]::Copy($bytes, $localOffset + 30, $localNameBytes, 0, $localNameLength)

            if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$centralNameBytes, [byte[]]$localNameBytes))
            {
                [void]$issues.Add("Central and local filenames differ for '$entryName'.")
            }
        }

        $hasNonAscii = $false
        foreach ($nameByte in $centralNameBytes)
        {
            if ($nameByte -ge 0x80)
            {
                $hasNonAscii = $true
                break
            }
        }

        if ($hasNonAscii -and (($flags -band 0x0800) -eq 0))
        {
            [void]$issues.Add("Non-ASCII entry '$entryName' is not marked UTF-8.")
        }

        $i += 45 + $nameLength + $extraLength + $commentLength
    }

    foreach ($expected in $ExpectedEntry)
    {
        $expectedName = Get-BaselineZipNormalizedEntryName -EntryName $expected
        if (-not ($entries -contains $expectedName))
        {
            [void]$issues.Add("Expected entry missing: $expectedName")
        }
    }

    return [pscustomobject]@{
        Path       = $zipPath
        EntryCount = $entries.Count
        Success    = ($issues.Count -eq 0)
        Issues     = @($issues)
        Entries    = @($entries)
    }
}
