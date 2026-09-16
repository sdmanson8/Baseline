$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 required.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Import-TestFunction($Path, $Name) {
    $errors = $null; $tokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name}, $true)
    $body = $fn.Body.Extent.Text
    Set-Item "Function:script:$Name" ([scriptblock]::Create($body.Substring(1, $body.Length - 2)))
}
function Assert-True($Condition, $Message) { if (-not $Condition) { throw $Message } }
function LogInfo($Message) {}
function LogError($Message) {}
function Write-SwallowedException { param($ErrorRecord, $Source, $Severity) }
function Write-ConsoleStatus { param($Action) }
function Get-BaselineLocalizedString { param($Key, $Fallback, $FormatArgs) $Fallback }
function Get-PackageManagerAvailabilityStateValue { param($AvailabilityState, $PropertyName) $true }
function Resolve-WinGetExecutable { 'winget.exe' }
function Invoke-StreamingProcess {
    param($FilePath, $ArgumentList, $TimeoutSeconds)
    $Script:CapturedArguments = $ArgumentList
    $Script:InvocationCount++
    $Script:NativeExitCode
}
foreach ($name in @('Invoke-WingetInstall', 'Invoke-WingetUninstall', 'Invoke-WingetUpdate', 'Get-WinGetActionFailureMessage', 'Throw-ApplicationActionFailure', 'Get-ApplicationActionTimeoutException')) {
    Import-TestFunction 'Module/Regions/Applications.psm1' $name
}
foreach ($action in @('Install', 'Uninstall', 'Update')) {
    foreach ($code in @(0, -1978335138, 42)) {
        $Script:NativeExitCode = $code; $Script:InvocationCount = 0
        $failure = $null
        try { & "Invoke-Winget$action" -WinGetId 'RARLab.WinRAR' -WinGetSource winget -DisplayName 'WinRAR' }
        catch { $failure = $_ }
        $sourceIndex = [array]::IndexOf($Script:CapturedArguments, '--source')
        Assert-True ($sourceIndex -ge 0 -and $Script:CapturedArguments[$sourceIndex + 1] -eq 'winget') 'Catalog action did not select its repository.'
        Assert-True ($Script:InvocationCount -eq 1) 'Action retried unexpectedly.'
        if ($code -eq 0) { Assert-True ($null -eq $failure) 'Successful action failed.' }
        else {
            Assert-True ($failure.Exception.Message.Contains([string]$code)) 'Native failure code lost.'
            if ($code -eq -1978335138) {
                Assert-True ($failure.Exception.Message.Contains('0x8A15005E') -and $failure.Exception.Message.Contains('certificate')) 'Certificate diagnostic lost.'
            }
        }
    }
}

foreach ($name in @('Test-ApplicationCatalogField', 'Get-ApplicationCatalogFieldValue', 'Resolve-ApplicationExecutionRoute', 'Invoke-ApplicationAction')) {
    Import-TestFunction 'Module/Regions/Applications.psm1' $name
}
$Script:NativeExitCode = 0
foreach ($source in @('winget', 'msstore', 'private-repository')) {
    foreach ($action in @('Install', 'Uninstall', 'Update')) {
        $app = @{ Name = 'Test'; Type = 'winget'; WinGetId = 'Test.Package'; WinGetSource = $source }
        Invoke-ApplicationAction -Action $action -Application $app -PreferredSource winget -PackageManagerAvailabilityState @{WinGetAvailable = $true}
        $sourceIndex = [array]::IndexOf($Script:CapturedArguments, '--source')
        Assert-True ($sourceIndex -ge 0 -and $Script:CapturedArguments[$sourceIndex + 1] -eq $source) 'Routing discarded the explicit repository.'
    }
}
Invoke-ApplicationAction -Action Install -Application @{Name = 'WinRAR'; Type = 'winget'; WinGetId = 'RARLab.WinRAR'} -PreferredSource winget
Assert-True ($Script:CapturedArguments[-1] -eq 'winget') 'Catalog default repository was lost.'
Invoke-WingetInstall -WinGetId Test.Package -DisplayName Test
Assert-True ($Script:CapturedArguments -notcontains '--source') 'Legacy callers lost unrestricted source selection.'
$storeEntryCount = 0
foreach ($file in @('Media', 'Utilities')) {
    $manifest = Get-Content (Join-Path $root "Module/Data/AppsCategory/$file.json") -Raw | ConvertFrom-Json
    $entries = @($manifest.Entries)
    foreach ($entry in $entries) {
        if ($entry.ExtraArgs.WinGetId -in @('9NNCB5BS59PH', '9NHT9RB2F4HD', '9PF4KZ2VN4W9')) {
            $storeEntryCount++
            Assert-True ($entry.WinGetSource -eq 'msstore') 'Store catalog entry lost explicit source metadata.'
        }
    }
}
Assert-True ($storeEntryCount -eq 3) 'Store metadata test did not inspect all three entries.'

# Exercise the actual filter and grouping functions, including cross-listed Gaming entries.
function Start-GuiPerfScope { param($Name, $Note) }
function Stop-GuiPerfScope { param($Scope) }
function Resolve-GuiPrimaryTabForTweak { param($Tweak) $Tweak.Primary }
function Test-TweakVisibleInCurrentMode { param($Tweak) $Script:Visited.Add($Tweak.Function); $true }
function Get-TweakFocusGroup { param($Tweak) $Tweak.Group }
Import-TestFunction 'Module/GUI/FilteringLogic.ps1' 'Test-TweakMatchesCurrentFilters'
Import-TestFunction 'Module/GUI/ContentManagement.ps1' 'Get-TabContentGroupedTweaks'
$Script:TweakManifest = @(
    @{ Function = 'A'; Primary = 'Security'; Group = 'Protection'; Risk = 'Low'; Category = 'Security' },
    @{ Function = 'B'; Primary = 'System'; Group = 'General'; Risk = 'Low'; Category = 'System' },
    @{ Function = 'C'; Primary = 'Security'; Group = 'Protection'; Risk = 'High'; Category = 'Security' },
    @{ Function = 'D'; Primary = 'Gaming'; Group = 'General'; Risk = 'Low'; Category = 'Gaming' }
)
$Script:TweakIndicesByPrimaryTab = @{ Security = @(0, 2); System = @(1); Gaming = @(1, 3) }
$Script:GamingCrossTabFunctions = [Collections.Generic.HashSet[string]]::new()
[void]$Script:GamingCrossTabFunctions.Add('B')
$Script:HideUnavailableItems = $false
$Script:Visited = [Collections.Generic.List[string]]::new()
$result = Get-TabContentGroupedTweaks -PrimaryTab Security -IsSearchResultsTab $false
Assert-True ($result.MatchCount -eq 2 -and ($result.CategoryTweaks['Protection'] -join ',') -eq '0,2') 'Security grouping changed.'
Assert-True (($Script:Visited -join ',') -eq 'A,C') 'Grouping evaluated unrelated tabs.'
$Script:RiskFilter = 'Low'
$result = Get-TabContentGroupedTweaks -PrimaryTab Security -IsSearchResultsTab $false
Assert-True ($result.MatchCount -eq 1 -and $result.CategoryTweaks['Protection'][0] -eq 0) 'Risk filter ignored.'
$Script:RiskFilter = 'All'; $Script:GamingModeActive = $true
$result = Get-TabContentGroupedTweaks -PrimaryTab Gaming -IsSearchResultsTab $false
Assert-True ($result.MatchCount -eq 2 -and ($result.CategoryTweaks['General'] -join ',') -eq '1,3') 'Gaming cross-list lost.'
$Script:GamingModeActive = $false
$result = Get-TabContentGroupedTweaks -PrimaryTab Search -IsSearchResultsTab $true -SearchQuery System
Assert-True ($result.MatchCount -eq 1 -and $result.CategoryTweaks['System | General'][0] -eq 1) 'Search stopped spanning tabs.'
$result = Get-TabContentGroupedTweaks -PrimaryTab Missing -IsSearchResultsTab $false
Assert-True ($result.MatchCount -eq 0) 'Missing tab was not empty.'
$Script:TweakManifest = @()
$result = Get-TabContentGroupedTweaks -PrimaryTab Search -IsSearchResultsTab $true
Assert-True ($result.MatchCount -eq 0) 'Empty manifest search was not empty.'

# Actual view transitions with WPF containers and isolated UI collaborators.
Add-Type -AssemblyName PresentationFramework
Import-TestFunction 'Module/GUI/AppsModule/ProgressNavChrome.ps1' 'Set-GuiAppsMode'
Import-TestFunction 'Module/GUI/ExecutionOrchestration/ExecutionView.ps1' 'Exit-ExecutionView'
function Set-GuiNavModeCheckedState {}
function Set-GuiOptimizeFilterChromeVisible { param($Visible) }
function Update-CurrentTabContent { param([switch]$SkipIdlePrebuild) $Script:RenderCount++ }
function Enter-GuiSelectionBulkUpdate { $false }
function Exit-GuiSelectionBulkUpdate { param($PreviousState) }
function Get-UxBilingualLocalizedString { param($Key, $Fallback) $Fallback }
function Set-GuiActionButtonsEnabled { param($Enabled) }
function Set-SearchControlsEnabled { param($Enabled) }
function Reset-RunAbortState {}
function Build-TabContent { param($PrimaryTab) $Script:RenderCount++ }
$Script:RenderCount = 0
$Script:AppsModeActive = $true
Set-GuiAppsMode -Enable:$false -SkipContentRestore
Assert-True (-not $Script:AppsModeActive -and $Script:RenderCount -eq 0) 'Execution transition rendered a tweak tab.'
$Script:AppsModeActive = $true
Set-GuiAppsMode -Enable:$false
Assert-True ($Script:RenderCount -eq 1) 'Normal navigation stopped rendering.'
$ContentScroll = New-Object System.Windows.Controls.ScrollViewer
$savedPanel = New-Object System.Windows.Controls.StackPanel
$Script:ExecutionPreviousContent = $savedPanel
$Script:CurrentPrimaryTab = 'Security'
$Script:RenderCount = 0
Exit-ExecutionView -SkipContentRestore
Assert-True ($Script:RenderCount -eq 0 -and [object]::ReferenceEquals($ContentScroll.Content, $savedPanel)) 'App completion rebuilt or lost hidden content.'
Exit-ExecutionView
Assert-True ($Script:RenderCount -eq 1) 'Tweak execution completion stopped rendering.'
'PASS: WinGet source and failures; indexed grouping and filters; app execution and ordinary view transitions.'
