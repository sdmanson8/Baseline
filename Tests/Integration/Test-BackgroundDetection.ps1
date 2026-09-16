$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1.'}
Add-Type -AssemblyName PresentationFramework
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $root 'Module/GUI/DetectionWorker.ps1')
$Script:Results=@{}
function Set-CachedDetection { param($Function,$Value) $Script:Results[$Function]=$Value }
function Get-CachedDetection { param($Function) if($Script:Results.ContainsKey($Function)){$Script:Results[$Function]} }
function Write-GuiRuntimeWarning { param($Context,$Message) }
$Script:Updates=0
$Script:GuiDetectionSubscriptions.Slow={$Script:Updates++}
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Module/GUI/TweakAnalysis.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw ($errors | Out-String)}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GuiToggleDetectedState'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$Script:ScanEnabled=$true
function Test-GuiObjectField {param($Object,$FieldName) $null -ne $Object.PSObject.Properties[$FieldName]}
function Get-GuiToggleGoalState {param($Tweak) $true}
$watch=[Diagnostics.Stopwatch]::StartNew()
$slowTweak=[pscustomobject]@{Function='Slow';Detect={Start-Sleep -Seconds 5; $true}}
$initial=Get-GuiToggleDetectedState -Tweak $slowTweak
if($initial.Known){throw 'Pending detection was reported as known'}
$enqueueMs=$watch.ElapsedMilliseconds
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='Slow';Detect={throw 'duplicate must not execute'}})
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='False';Detect={$false}})
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='Failure';Detect={throw 'query failed'}})
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='Newer';Detect={Start-Sleep -Milliseconds 100; $false}})
Set-CachedDetection -Function Newer -Value $true
$Script:Ticks=0
$frame=[Windows.Threading.DispatcherFrame]::new()
$pulse=[Windows.Threading.DispatcherTimer]::new()
$pulse.Interval=[TimeSpan]::FromMilliseconds(50)
$pulse.Add_Tick({
    $Script:Ticks++
    if($Script:GuiDetectionWorker.Pending.Count -eq 0 -or $watch.Elapsed.TotalSeconds -gt 40){$frame.Continue=$false}
})
$pulse.Start()
[Windows.Threading.Dispatcher]::PushFrame($frame)
$pulse.Stop()
if($Script:Results.Slow -ne $true -or -not $Script:Results.ContainsKey('False') -or $Script:Results.False -ne $false){throw 'Detection results lost'}
if($Script:Updates -ne 1){throw 'Duplicate detection or callback'}
if(-not $Script:GuiDetectionFailures.ContainsKey('Failure')){throw 'Query failure not recorded'}
if($Script:Results.Newer -ne $true){throw 'Background result overwrote newer cache state'}
$completed=Get-GuiToggleDetectedState -Tweak $slowTweak
if(-not $completed.Known -or -not $completed.Value){throw 'Row state did not receive completed detection'}
if($Script:Ticks -lt 30){throw 'Dispatcher did not remain responsive during slow detection'}
if($enqueueMs -gt 1000){throw "Enqueue blocked: $enqueueMs ms"}
Stop-GuiBackgroundDetection
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='CancelDuringOpen';Detect={Start-Sleep -Seconds 30; $true}})
$closeWatch=[Diagnostics.Stopwatch]::StartNew()
Stop-GuiBackgroundDetection
if($closeWatch.ElapsedMilliseconds -gt 1000){throw 'Closing waited for detection'}
"PASS: enqueue ${enqueueMs}ms; $Script:Ticks dispatcher heartbeats during a 5-second detection; true/false results, deduplication, error reporting, shutdown."
