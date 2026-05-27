$ErrorActionPreference = 'Stop'

$helperDir = Join-Path $PSScriptRoot '..\Module\SharedHelpers'
$resolvedHelperDir = Resolve-Path -LiteralPath $helperDir -ErrorAction Stop
$helperDirItem = Get-Item -LiteralPath $resolvedHelperDir.ProviderPath -ErrorAction Stop
if (-not $helperDirItem.PSIsContainer)
{
    throw "Shared helper directory path is not a directory: $($helperDirItem.FullName)"
}

$helperFiles = Get-ChildItem -LiteralPath $helperDirItem.FullName -Filter '*.ps1' -File -ErrorAction Stop
$safeScriptVarPattern = '^\$Script:(SharedHelpersModuleRoot|SharedHelpersRepoRoot|Cached\w+|ConfigProfileSchema\w*|WinGetAvailabilityState|ChocolateyAvailabilityState)$'
$violations = 0
foreach ($hf in $helperFiles)
{
    $content = Get-Content -LiteralPath $hf.FullName -Raw -ErrorAction Stop
    $scriptVarMatches = [regex]::Matches($content, '\$Script:\w+')
    foreach ($m in $scriptVarMatches)
    {
        if ($m.Value -notmatch $safeScriptVarPattern)
        {
            $violations++
            Write-Host "$($hf.Name): $($m.Value)"
        }
    }
}

Write-Host "Total violations: $violations"
