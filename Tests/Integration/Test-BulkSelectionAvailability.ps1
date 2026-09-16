$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Import-TestFunction($Path,$Name){
    $e=$null; $t=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path),[ref]$t,[ref]$e)
    if($e){throw ($e | Out-String)}
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    Set-Item "Function:script:$Name" ([scriptblock]::Create($fn.Body.Extent.Text.Trim().Substring(1,$fn.Body.Extent.Text.Trim().Length-2)))
}
foreach($name in @('Enter-GuiSelectionBulkUpdate','Exit-GuiSelectionBulkUpdate','Test-GuiSelectionBulkUpdateInProgress')){Import-TestFunction 'Module/GUI/SessionState.ps1' $name}
Import-TestFunction 'Module/GUI/ExecutionOrchestration/ExecutionStateSummary.ps1' 'Update-GuiScopedRunActionAvailability'
$Script:GuiSelectionBulkUpdateInProgress=$false
$Script:GameModePlanSyncPending=$false
$Script:RunActionAvailabilityRefreshPending=$false
$Script:Calls=0
$Script:Selected=0
$Script:BtnRun=[pscustomobject]@{IsEnabled=$false}
function Get-GuiScopedRunActionAvailability {
    $Script:Calls++
    [pscustomobject]@{RunEnabled=($Script:Selected -gt 0);PreviewEnabled=($Script:Selected -gt 0);MenuRunEnabled=($Script:Selected -gt 0)}
}
$outer=Enter-GuiSelectionBulkUpdate
try{
    for($i=0;$i -lt 372;$i++){Update-GuiScopedRunActionAvailability}
    $inner=Enter-GuiSelectionBulkUpdate
    try{Update-GuiScopedRunActionAvailability}finally{Exit-GuiSelectionBulkUpdate $inner}
    if($Script:Calls -ne 0){throw 'Nested batch scanned incomplete selections'}
    $Script:Selected=6
}finally{Exit-GuiSelectionBulkUpdate $outer}
if($Script:Calls -ne 1 -or -not $Script:BtnRun.IsEnabled){throw 'Batch did not publish final availability exactly once'}
try{
    $outer=Enter-GuiSelectionBulkUpdate
    try{$Script:Selected=0;Update-GuiScopedRunActionAvailability;throw 'simulated failure'}finally{Exit-GuiSelectionBulkUpdate $outer}
}catch{if($_.Exception.Message -ne 'simulated failure'){throw}}
if($Script:Calls -ne 2 -or $Script:BtnRun.IsEnabled -or (Test-GuiSelectionBulkUpdateInProgress)){throw 'Failed batch left stale state'}
$Script:Selected=1;Update-GuiScopedRunActionAvailability
if($Script:Calls -ne 3 -or -not $Script:BtnRun.IsEnabled){throw 'Individual changes no longer refresh immediately'}
Import-TestFunction 'Module/GUI/PresetApplication.ps1' 'Set-TabPreset'
function Get-GuiPresetDebugLogger {}
function Resolve-TabPresetContext {param($PrimaryTab,$PresetTier,$SelectionDefinition,$WriteGuiPresetDebugScript) @{UsesExplicitPreset=$true}}
function Initialize-TabPresetApplicationState {param($PresetContext,$SaveGuiUndoSnapshotScript,$WriteGuiPresetDebugScript)}
function Set-TabPresetSharedUiState {param($PrimaryTab,$PresetContext,$SetSafeModeStateScript,$SetAdvancedModeStateScript,$UpdateCategoryFilterListScript,$SetFilterSelectionsScript,$WriteGuiPresetDebugScript)}
function Apply-TabPresetSelections {param($PresetContext,$TestTweakMatchesPresetTierScript,$SyncLinkedStateCapture)
    for($i=0;$i -lt 372;$i++){Update-GuiScopedRunActionAvailability}
    $Script:Selected=6
    @{SelectedCount=6}
}
function Ensure-SafePresetRestorePointSelection {param($PresetContext,$PresetStats) $PresetStats}
function Write-TabPresetUnmatchedEntryWarnings {param($PresetContext)}
function Complete-TabPresetApplication {param($PrimaryTab,$PresetContext,$PresetStats,$WriteGuiPresetDebugScript) Update-GuiScopedRunActionAvailability}
Set-TabPreset -PrimaryTab Updates -PresetTier Security
if($Script:Calls -ne 4 -or (Test-GuiSelectionBulkUpdateInProgress)){throw 'Real Set-TabPreset did not enclose mutations in one batch'}
Import-TestFunction 'Module/GUI/BuildTweakControls.ps1' 'Update-CurrentTabContent'
function Start-GuiPerfScope {throw 'render reached'}
$Script:GuiContentRestoreInProgress=$true
Update-CurrentTabContent
$Script:GuiContentRestoreInProgress=$false
$renderReached=$false
try{Update-CurrentTabContent}catch{if($_.Exception.Message -eq 'render reached'){$renderReached=$true}else{throw}}
if(-not $renderReached){throw 'Rendering remained suppressed after restoration'}
Import-TestFunction 'Module/GUI/ExecutionOrchestration/ExecutionView.ps1' 'Exit-ExecutionView'
Add-Type -AssemblyName PresentationFramework
function Start-GuiPerfScope {param($Name)}
function Stop-GuiPerfScope {param($Scope)}
function LogInfo {param($Message)}
function Get-UxBilingualLocalizedString {param($Key,$Fallback) $Fallback}
function Set-GuiActionButtonsEnabled {param($Enabled) Update-GuiScopedRunActionAvailability}
function Set-SearchControlsEnabled {param($Enabled)}
function Reset-RunAbortState {}
function Build-TabContent {param($PrimaryTab) Update-GuiScopedRunActionAvailability}
function Get-UxRunActionLabel {'Run'}
function Test-GuiObjectField {param($Object,$FieldName) $null -ne $Object.PSObject.Properties[$FieldName]}
$Script:CurrentPrimaryTab='Updates'
$ContentScroll=[pscustomobject]@{VerticalScrollBarVisibility='Disabled';Content=$null}
$Script:BtnRun=$null
$Script:Calls=0
Exit-ExecutionView
if($Script:Calls -ne 1 -or (Test-GuiSelectionBulkUpdateInProgress)){throw 'Returning from execution repeated the selection scan or left updates suppressed'}
'PASS: 373 nested bulk refresh requests coalesced to one final scan; exception cleanup and immediate single-selection updates.'
