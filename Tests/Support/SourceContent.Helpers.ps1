Set-StrictMode -Version Latest

function Get-BaselineExplicitDotSourcePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Line
    )

    $sourceDirectory = Split-Path -Parent $SourcePath
    $patterns = @(
        '^\s*\.\s*\(Join-Path\s+\$PSScriptRoot\s+[''"]([^''"]+\.ps1)[''"]\)\s*(?:#.*)?$',
        '^\s*\.\s*\(Join-Path\s+-Path\s+\$PSScriptRoot\s+-ChildPath\s+[''"]([^''"]+\.ps1)[''"]\)\s*(?:#.*)?$'
    )

    foreach ($pattern in $patterns)
    {
        $match = [regex]::Match($Line, $pattern)
        if ($match.Success)
        {
            $candidatePath = Join-Path -Path $sourceDirectory -ChildPath $match.Groups[1].Value
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf)
            {
                return (Resolve-Path -LiteralPath $candidatePath -ErrorAction Stop).ProviderPath
            }
        }
    }

    return $null
}

function Get-BaselineTestSourcePathSet
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    $seen = @{}
    $paths = [System.Collections.Generic.List[string]]::new()
    $queue = New-Object System.Collections.Queue

    foreach ($sourcePath in $Path)
    {
        $resolvedPath = (Resolve-Path -LiteralPath $sourcePath -ErrorAction Stop).ProviderPath
        [void]$queue.Enqueue($resolvedPath)
    }

    while ($queue.Count -gt 0)
    {
        $candidatePath = [string]$queue.Dequeue()
        if ($seen.ContainsKey($candidatePath))
        {
            continue
        }

        $seen[$candidatePath] = $true
        [void]$paths.Add($candidatePath)

        $extension = [System.IO.Path]::GetExtension($candidatePath)
        if (($extension -ne '.ps1') -and ($extension -ne '.psm1'))
        {
            continue
        }

        foreach ($line in @(Get-Content -LiteralPath $candidatePath))
        {
            $dotSourcePath = Get-BaselineExplicitDotSourcePath -SourcePath $candidatePath -Line $line
            if (-not [string]::IsNullOrWhiteSpace($dotSourcePath))
            {
                [void]$queue.Enqueue($dotSourcePath)
            }
        }
    }

    return @($paths.ToArray())
}

function Get-BaselineTestSourceText
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    $chunks = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($candidatePath in $Path)
    {
        [void]$chunks.Add((Expand-BaselineTestSourceText -Path $candidatePath -Seen $seen))
    }

    return ($chunks -join "`n")
}

function Expand-BaselineTestSourceText
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Seen
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    if ($Seen.ContainsKey($resolvedPath))
    {
        return ''
    }
    $Seen[$resolvedPath] = $true

    $chunks = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(Get-Content -LiteralPath $resolvedPath -Encoding UTF8))
    {
        $dotSourcePath = Get-BaselineExplicitDotSourcePath -SourcePath $resolvedPath -Line $line
        if (-not [string]::IsNullOrWhiteSpace($dotSourcePath))
        {
            [void]$chunks.Add((Expand-BaselineTestSourceText -Path $dotSourcePath -Seen $Seen))
            continue
        }

        [void]$chunks.Add($line)
    }

    return ($chunks -join "`n")
}
