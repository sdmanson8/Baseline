$helperDir = Join-Path $PSScriptRoot '..\Module\SharedHelpers'
$helperFiles = Get-ChildItem -Path $helperDir -Filter '*.ps1' -File
$safeScriptVarPattern = '^\$Script:(SharedHelpersModuleRoot|SharedHelpersRepoRoot|Cached\w+)$'
$violations = 0
foreach ($hf in $helperFiles)
{
    $content = Get-Content -LiteralPath $hf.FullName -Raw
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
