$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Import-TestFunction($Path,$Name){
    $e=$null; $t=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Path),[ref]$t,[ref]$e)
    if($e){throw ($e | Out-String)}
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if(-not $fn){throw "Missing $Name"}
    Set-Item -Path "Function:script:$Name" -Value ([scriptblock]::Create($fn.Body.Extent.Text.Trim().Substring(1,$fn.Body.Extent.Text.Trim().Length-2)))
}
Import-TestFunction 'Module/GUI/GameModeState.ps1' 'Set-ExecutionGameModeContext'
Import-TestFunction 'Module/GUI/GameModeState.ps1' 'Get-ExecutionGameModeContext'
Import-TestFunction 'Module/GUI/ExecutionOrchestration/ExecutionRunOrchestration.ps1' 'Set-GuiExecutionGameModeRunContext'
$Script:Ctx=@{GameMode=@{ExecutionContext=$null}}
function Test-HasGameModeTweaks {param($TweakList) @($TweakList).Count -gt 0}
function Get-GameModeDecisionOverrides { @{GameBar='Enable';GPUScheduling='Enable'} }
function Get-GameModeDecisionOverridesText {param($Overrides) 'Test'}
function Get-UxBilingualLocalizedString {param($Key,$Fallback,$FormatArgs) $Fallback -f $FormatArgs}
function LogInfo {param($Message)}
foreach($operation in @('Apply','Restore')){
    Set-GuiExecutionGameModeRunContext -TweakList @([pscustomobject]@{Function='GameBar';GameModeProfile='Streaming';GameModeOperation=$operation})
    $actual=Get-ExecutionGameModeContext
    if($actual.Profile -ne 'Streaming' -or $actual.Operation -ne $operation -or $actual.DecisionOverrides.GPUScheduling -ne 'Enable'){throw 'Run metadata lost'}
    if(-not [object]::ReferenceEquals($actual,$Script:ExecutionGameModeContext)){throw 'GUI and execution contexts diverged'}
}
Set-GuiExecutionGameModeRunContext -TweakList @()
if($null -ne (Get-ExecutionGameModeContext) -or $null -ne $Script:ExecutionGameModeContext){throw 'Standard run retained gaming context'}
Set-ExecutionGameModeContext -GameModeContext ([pscustomobject]@{Profile='Streaming'})
Set-ExecutionGameModeContext -GameModeContext $null
if($null -ne $Script:Ctx.GameMode.ExecutionContext){throw 'Completion retained stale gaming context'}
$wrongCalls=@(Get-ChildItem (Join-Path $root 'Module/GUI/ExecutionOrchestration') -Recurse -Filter '*.ps1' | Select-String 'Set-ExecutionGameModeContext -Context')
if($wrongCalls.Count){throw 'Incorrect Context argument remains'}
'PASS: gaming Apply/Restore metadata, standard-run clearing, completion clearing, and all orchestration call sites.'
