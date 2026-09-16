# Exercises cross-tab search with deterministic category caches in Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repoRoot 'Module/GUI/AppsModule/CatalogHelpers.ps1')
function Test-GuiObjectField { param($Object, $FieldName) return $null -ne $Object.PSObject.Properties[$FieldName] }
function Assert-Names {
    param([object[]]$Items, [string]$Expected)
    $actual = (@($Items | ForEach-Object { $_.Name } | Sort-Object) -join ',')
    if ($actual -ne $Expected) { throw "Expected '$Expected', got '$actual'." }
}
$Script:GuiModuleBasePath = Join-Path $repoRoot 'Module/GUI'
$Script:AppsCategoryFilter = 'Browsers'
$Script:AppsStatusFilter = 'All'
$Script:AppsSourceFilter = 'All'
$Script:BaselineApplicationsCatalogByCategory = @{}
foreach ($category in @(Get-AppsCatalogCategoryNames)) { $Script:BaselineApplicationsCatalogByCategory[$category] = @() }
$browser = [pscustomobject]@{ Name = 'Browser'; SearchIndex = 'shared browser'; WinGetId = 'test.browser'; ChocoId = ''; ExtraArgs = $null }
$editor = [pscustomobject]@{ Name = 'Editor'; SearchIndex = 'shared editor'; WinGetId = ''; ChocoId = 'test.editor'; ExtraArgs = $null }
$Script:BaselineApplicationsCatalogByCategory['Browsers'] = @($browser)
$Script:BaselineApplicationsCatalogByCategory['Development'] = @($editor)
$Script:BaselineApplicationsCatalog = @($browser)
$Script:BaselineApplicationsCatalogCategory = 'Browsers'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'SHARED' -SkipPackageManagerAvailabilityRefresh) 'Browser,Editor'
if ($Script:BaselineApplicationsCatalogCategory -ne 'Browsers' -or $Script:AppsCategoryFilter -ne 'Browsers') { throw 'Search changed the active category.' }
Assert-Names @($Script:BaselineApplicationsCatalog) 'Browser'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'shared editor' -SkipPackageManagerAvailabilityRefresh) 'Editor'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'missing' -SkipPackageManagerAvailabilityRefresh) ''
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery '  ' -SkipPackageManagerAvailabilityRefresh) 'Browser'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'shared' -Category 'Development' -SkipPackageManagerAvailabilityRefresh) 'Editor'
$Script:AppsSourceFilter = 'choco'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'shared' -SkipPackageManagerAvailabilityRefresh) 'Editor'
$Script:AppsSourceFilter = 'All'
$Script:AppsCategoryFilter = 'Documents'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery 'shared' -SkipPackageManagerAvailabilityRefresh) 'Browser,Editor'
Assert-Names @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery '' -SkipPackageManagerAvailabilityRefresh) ''
Write-Host 'PASS: cross-tab search, multi-term matching, empty results, source filters, explicit category counts, and clearing search.'
