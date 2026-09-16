param([switch]$ModuleScope)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 required'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Import-TestFunction($Path,$Name){
 $errors=$null;$tokens=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path),[ref]$tokens,[ref]$errors)
 if($errors){throw ($errors|Out-String)}
 $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
 $body=$fn.Body.Extent.Text
 Set-Item "Function:script:$Name" ([scriptblock]::Create($body.Substring(1,$body.Length-2)))
}
function Test-GuiObjectField($Object,$FieldName){$Object.ContainsKey($FieldName)}
function Get-TweakVisualMetadata { @{} }
function Get-GameModeActionStateLabel($ActionParam){$ActionParam}
function Get-UxLocalizedString($Key,$Fallback){$Fallback}
function Get-TweakBlastRadiusText {param($Tweak,$TypeLabel,$ScenarioTags,$MatchesDesired) ''}
Import-TestFunction 'Module/GUI/GameModeUI.ps1' 'New-GameModePlanEntry'
$choice=New-GameModePlanEntry -Tweak @{Function='Win32PrioritySeparation';Type='Choice';Options=@('Programs','BackgroundServices');Default='Programs'} -ProfileName Streaming -ToggleParam Programs
if($choice.Value -ne 'Programs' -or $choice.Options.Count -ne 2 -or $choice.DefaultValue -ne 'Programs'){throw 'Game Mode lost choice execution metadata'}
Import-TestFunction 'Module/Regions/Applications.psm1' 'Throw-ApplicationActionFailure'
Import-TestFunction 'Module/Regions/Applications.psm1' 'Get-ApplicationActionTimeoutException'
function LogError($Message) {}
$caught=$false
try { try {throw 'WinGet exit code -1978335212'} catch {Throw-ApplicationActionFailure -TargetName WinRAR -ActionLabel Install -ErrorRecord $_} }
catch { $caught=$_.Exception.Message -match '-1978335212'; if(-not $_.Exception.InnerException){throw 'Lost inner failure'} }
if(-not $caught){throw 'App failure lost WinGet diagnostic'}

Add-Type -AssemblyName PresentationFramework
Import-TestFunction 'Module/GUI/BuildTabContent.ps1' 'Start-ProgressiveTabSectionsHydration'
function Get-GuiFunctionCapture {param($Name) $null}
function New-TabSectionsRenderPlan {param($BuildContext) 1;2;3;4;5}
function Test-TabContentHydrationCurrent {param($PrimaryTab,$BuildGeneration,$BuildToken,[switch]$BackgroundBuild) -not $Script:CancelBuild}
function Test-TabContentBuildStillCurrent {param($PrimaryTab,$BuildGeneration) $true}
function Clear-TabContentBuildToken {param($PrimaryTab,$BuildToken) $Script:Frame.Continue=$false}
function Add-TabRenderPlanItem {param($BuildContext,$RenderItem) $Script:Rendered.Add($RenderItem); Start-Sleep -Milliseconds 30; $true}
function Complete-TabContentBuild {param($BuildContext,$AllTabIndexes,$BuildGeneration,$BuildToken,[switch]$BackgroundBuild,[switch]$SkipIdlePrebuild,[switch]$AlreadyDisplayed) $Script:Completed=$true; $Script:Frame.Continue=$false}
function Write-GuiRuntimeWarning {param($Context,$Message) throw $Message}
$panel=New-Object Windows.Controls.StackPanel
$Script:Rendered=New-Object 'Collections.Generic.List[int]'
$Script:Frame=New-Object Windows.Threading.DispatcherFrame
$Script:Completed=$false;$Script:CancelBuild=$false
Start-ProgressiveTabSectionsHydration -BuildContext ([pscustomobject]@{PrimaryTab='Security';MainPanel=$panel}) -AllTabIndexes @(1,2,3,4,5) -BuildGeneration 1 -BuildToken test
if($Script:Rendered.Count -gt 1){throw 'Foreground rendering did not yield after first row'}
$Script:InputAt=-1
[void]$panel.Dispatcher.BeginInvoke([Action]{$Script:InputAt=$Script:Rendered.Count},[Windows.Threading.DispatcherPriority]::Input)
[Windows.Threading.Dispatcher]::PushFrame($Script:Frame)
if(-not $Script:Completed -or $Script:Rendered.Count -ne 5 -or $Script:InputAt -ne 1){throw 'Rendering starved input or lost rows'}
$Script:Rendered.Clear();$Script:Completed=$false;$Script:Frame=New-Object Windows.Threading.DispatcherFrame
Start-ProgressiveTabSectionsHydration -BuildContext ([pscustomobject]@{PrimaryTab='Security';MainPanel=$panel}) -AllTabIndexes @(1,2,3,4,5) -BuildGeneration 2 -BuildToken test2
$Script:CancelBuild=$true
[Windows.Threading.Dispatcher]::PushFrame($Script:Frame)
if($Script:Rendered.Count -ne 1 -or $Script:Completed){throw 'Cancelled tab still rendered rows'}
'PASS: Game Mode choice payload, app error preservation, foreground input scheduling, ordered rendering and cancellation.'
if(-not $ModuleScope){
 $testModule=New-Module -ArgumentList $PSCommandPath -ScriptBlock {param($Path) . $Path -ModuleScope}
 Remove-Module $testModule
 'PASS: the same rendering checks also pass inside a module.'
}
