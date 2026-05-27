<#
  .SYNOPSIS
  Resolves the file set defined by Launcher/EmbeddedRuntimeSurface.json.

  .DESCRIPTION
  Returns the exact repository-relative files that should be embedded into the
  Baseline.exe runtime payload. By default optional include globs are excluded.

  .EXAMPLE
  powershell -File .\Tools\Get-EmbeddedRuntimeSurface.ps1

  .EXAMPLE
  powershell -File .\Tools\Get-EmbeddedRuntimeSurface.ps1 -IncludeOptional
#>

[CmdletBinding()]
param(
    [switch]$IncludeOptional,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $repoRoot 'Launcher/EmbeddedRuntimeSurface.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Runtime surface manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$includeGlobs = [System.Collections.Generic.List[string]]::new()
foreach ($glob in @($manifest.includeGlobs)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$glob)) {
        [void]$includeGlobs.Add([string]$glob)
    }
}

if ($IncludeOptional) {
    foreach ($glob in @($manifest.optionalIncludeGlobs)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$glob)) {
            [void]$includeGlobs.Add([string]$glob)
        }
    }
}

$excludeGlobs = [string[]]@($manifest.excludeGlobs)

<#
    .SYNOPSIS
#>

function Convert-ToRelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $relativePath = [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
    return ($relativePath -replace '\\', '/')
}

<#
    .SYNOPSIS
#>
function Test-AnyWildcardMatch {
    param(
        [string]$Path,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

$files = Get-ChildItem -LiteralPath $repoRoot -File -Recurse
$selected = [System.Collections.Generic.List[string]]::new()

foreach ($file in $files) {
    $relativePath = Convert-ToRelativePath -BasePath $repoRoot -FullPath $file.FullName

    if (-not (Test-AnyWildcardMatch -Path $relativePath -Patterns $includeGlobs)) {
        continue
    }

    if (Test-AnyWildcardMatch -Path $relativePath -Patterns $excludeGlobs) {
        continue
    }

    [void]$selected.Add($relativePath)
}

$result = $selected | Sort-Object -Unique

if ($AsJson) {
    $result | ConvertTo-Json -Depth 2
}
else {
    $result
}
