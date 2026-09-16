$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 required.' }
Add-Type -AssemblyName PresentationFramework
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture = Join-Path $root ('.artifacts/Card Scheduling ' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory((Join-Path $fixture 'Build-AppsViewCards'))
Copy-Item (Join-Path $root 'Module/GUI/AppsModule/CardBuildLifecycle.ps1') (Join-Path $fixture 'CardBuildLifecycle.ps1')
[IO.File]::WriteAllText((Join-Path $fixture 'Build-AppsViewCards/Build-AppsViewCards.ps1'), @'
foreach ($app in $sortedCatalog) {
    Start-Sleep -Milliseconds 30
    $card = [Windows.Controls.TextBlock]::new()
    $card.Text = [string]$app
    $null = $Script:AppsWrapPanel.Children.Add($card)
    $installedCount++
}
'@)
$errors=$null
$parentAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Module/GUI/AppsModule.ps1'),[ref]$null,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$parentFunction=$parentAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Build-AppsViewCards'},$true)
$module = New-Module -ArgumentList $fixture,$parentFunction.Extent.Text -ScriptBlock {
    param($Fixture,$ParentFunction)
    . (Join-Path $Fixture 'CardBuildLifecycle.ps1')
    . ([scriptblock]::Create($ParentFunction))
    function Start-GuiPerfScope { param($Name) $null }
    function New-SafeBrushConverter { param($Context) [Windows.Media.BrushConverter]::new() }
    function Get-GuiCurrentTheme { @{} }
    function Initialize-AppsSelectionState { $Script:SelectedAppIds=[Collections.Generic.HashSet[string]]::new() }
    function Update-AppCategoryFilterList {}
    function Update-AppStatusFilterList {}
    function Get-BaselineApplicationsCatalog { param([switch]$AllCategories) @('first','second') }
    function Get-AppsCatalogItemsBySearchStatusAndSourceFilters { param($SearchQuery) @('first','second') }
    function Get-ApplicationCacheSnapshot { param($CacheState) @{WinGet=@{}; Chocolatey=@{}; WinGetUpdates=@{}; ChocolateyUpdates=@{}} }
    function Get-GuiRuntimeCommand { param($Name,$CommandType) Get-Command $Name }
    function Get-GuiFunctionCapture { param($Name) (Get-Command $Name).ScriptBlock }
    function Set-AppSelectionState {}
    function Set-AppQueuedAction {}
    function Get-AppQueuedAction {}
    function Start-AppsModuleActionAsync {}
    function Invoke-GuiRuntimeFailureReport {}
    function Stop-GuiPerfScope { param($Scope,$ExtraNote) }
    function Write-GuiRuntimeWarning { param($Context,$Message) throw $Message }
    function Update-AppsSelectionSummary { $Script:Completions++ }
    function Get-UxLocalizedString { param($Key,$Fallback) $Fallback }
    $Script:AppsWrapPanel = [Windows.Controls.WrapPanel]::new()
    $Script:TxtAppsProgressText = [Windows.Controls.TextBlock]::new()
    $Script:AppsCategoryFilter = 'All'
    $Script:Completions = 0
    $Script:AppsViewLoaded=$true; $Script:AppsViewDirty=$false; $Script:AppsModeActive=$true
    $Script:AppsStatusFilter='All'
    function Start-TestBuild {
        param($Catalog,$Signature)
        $Script:AppsWrapPanel.Children.Clear()
        $context = @{
            Panel=$Script:AppsWrapPanel; Catalog=@($Catalog); Position=0; Action=$null; Perf=$null
            Values=@{cacheReady=$true; installedCount=0; updateAvailableCount=0; allCatalog=@($Catalog); catalog=@($Catalog); activeStatusFilter='All'; renderSignature=$Signature}
        }
        $step = Get-Command Invoke-AppsViewCardsBuildStep
        $context.Action = [Action]{ & $step -Context $context }.GetNewClosure()
        $Script:AppsCardBuildContext = $context
        $null=$context.Panel.Dispatcher.BeginInvoke($context.Action,[Windows.Threading.DispatcherPriority]::Background)
        $context
    }
    function Read-TestState { @{Context=$Script:AppsCardBuildContext; Panel=$Script:AppsWrapPanel; Signature=$Script:AppsViewBuildSignature; Completions=$Script:Completions; Summary=$Script:TxtAppsProgressText.Text} }
    function Invoke-StaleTestStep { param($Context) Invoke-AppsViewCardsBuildStep -Context $Context }
    Export-ModuleMember -Function Build-AppsViewCards,Start-TestBuild,Read-TestState,Invoke-StaleTestStep
}
try {
    Import-Module $module
    Build-AppsViewCards
    if ((Read-TestState).Panel.Children.Count -ne 0) { throw 'Parent built cards synchronously' }
    $parentFrame=[Windows.Threading.DispatcherFrame]::new()
    $parentTimer=[Windows.Threading.DispatcherTimer]::new()
    $parentTimer.Interval=[TimeSpan]::FromMilliseconds(10)
    $parentWatch=[Diagnostics.Stopwatch]::StartNew()
    $parentTimer.Add_Tick({ if (-not (Read-TestState).Context -or $parentWatch.Elapsed.TotalSeconds -gt 10) { $parentFrame.Continue=$false } })
    $parentTimer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($parentFrame)
    $parentTimer.Stop()
    if ((Read-TestState).Panel.Children.Count -ne 2 -or (Read-TestState).Completions -ne 1) { throw 'Parent did not preserve card build context' }
    $old=Start-TestBuild -Catalog (1..20) -Signature first
    $frame=[Windows.Threading.DispatcherFrame]::new()
    $timer=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Normal)
    $timer.Interval=[TimeSpan]::FromMilliseconds(10)
    $Script:Pulses=0; $Script:Replaced=$false
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $timer.Add_Tick({
        $Script:Pulses++
        $state=Read-TestState
        if (-not $Script:Replaced -and $state.Panel.Children.Count -ge 3) {
            $Script:Replaced=$true
            $null=Start-TestBuild -Catalog @('new1','new2','new3') -Signature second
            Invoke-StaleTestStep -Context $old
        }
        if (($Script:Replaced -and -not (Read-TestState).Context) -or $watch.Elapsed.TotalSeconds -gt 10) { $frame.Continue=$false }
    })
    $timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $timer.Stop()
    $state=Read-TestState
    if ($state.Context -or $state.Signature -ne 'second' -or $state.Completions -ne 2) { throw 'Build completion/cancellation failed' }
    if (($state.Panel.Children.Text -join ',') -ne 'new1,new2,new3') { throw 'Stale cards were appended or card order was lost' }
    if ($Script:Pulses -lt 4 -or $state.Summary -notmatch '3/3') { throw 'Dispatcher pulses or cumulative summary failed' }
    Write-Host "PASS: $Script:Pulses dispatcher pulses; ordered cards; stale build cancelled; cumulative summary preserved"
}
finally { Remove-Module $module }
