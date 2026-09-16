$ErrorActionPreference='Stop'
function Write-ShutdownTrace($Text) { [IO.File]::AppendAllText($env:BASELINE_SHUTDOWN_TEST_LOG, $Text + "`r`n") }
Write-ShutdownTrace 'script entry'
$root=$env:BASELINE_SHUTDOWN_TEST_ROOT
if ([Threading.Thread]::CurrentThread.ManagedThreadId -ne [int]$env:BASELINE_SHUTDOWN_TEST_THREAD) { throw 'GUI does not run on launcher STA thread' }
Add-Type -AssemblyName PresentationFramework
. (Join-Path $root 'Module/GUIExecution/WorkerLifecycle.ps1')
. (Join-Path $root 'Module/GUI/DetectionWorker.ps1')
function Import-FixtureFunction($Relative,$Name) {
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$null,[ref]$errors)
    if($errors){throw ($errors | Out-String)}
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    Set-Item "Function:script:$Name" ([scriptblock]::Create($fn.Body.Extent.Text.Trim().Substring(1,$fn.Body.Extent.Text.Trim().Length-2)))
}
Import-FixtureFunction 'Module/GUI/ActionHandlers/SystemScanFooterHandlers.ps1' 'Stop-GuiSupportBundleExportWorker'
function New-FixtureWorker {
    $rs=[runspacefactory]::CreateRunspace(); $rs.Open()
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    $null=$ps.AddScript('Start-Sleep -Seconds 30')
    [pscustomobject]@{PowerShell=$ps; Runspace=$rs; AsyncResult=$ps.BeginInvoke(); Timer=[Windows.Threading.DispatcherTimer]::new(); MenuItem=$null; MenuWasEnabled=$true; ProgressDialog=$null; SessionStatePath=''}
}
function Register-GuiEventHandler {
    param($Source,$EventName,$Handler)
    switch($EventName){Closing {$Source.Add_Closing($Handler)} Closed {$Source.Add_Closed($Handler)}}
}
function Save-GuiSessionState {}
function Clear-GuiWindowRuntimeState {}
function Write-SwallowedException { param($ErrorRecord,$Source,$Severity) throw $ErrorRecord }
function LogWarning { param($Message) }
function Start-GuiResponsivenessWatchdog { param($Window) $null }
function Stop-GuiResponsivenessWatchdog { param($Watchdog) }
function Get-CachedDetection { param($Function) $null }
function Set-CachedDetection { param($Function,$Value) }
function Write-GuiRuntimeWarning { param($Context,$Message) throw $Message }
$Script:TestGuiRunInProgressScript={$false}
$Script:StopGuiSupportBundleExportWorkerScript=${function:Stop-GuiSupportBundleExportWorker}
$Form=[Windows.Window]::new()
$Form.Width=1; $Form.Height=1; $Form.Opacity=0; $Form.ShowInTaskbar=$false; $Form.ShowActivated=$false
$Script:MainForm=$Form
$Script:AppsCacheRefreshWorker=New-FixtureWorker
$Script:SupportBundleExportWorker=New-FixtureWorker
$Script:SplashCloseWorker=New-FixtureWorker
$startupSplashAbortWatchdog=New-FixtureWorker
$owned=@($Script:AppsCacheRefreshWorker,$Script:SupportBundleExportWorker,$Script:SplashCloseWorker,$startupSplashAbortWatchdog)
Request-GuiBackgroundDetection -Tweak ([pscustomobject]@{Function='SlowShutdown'; Detect={Start-Sleep -Seconds 30; $true}})
$pool=$Script:GuiDetectionWorker.Pool
. (Join-Path $root 'Module/GUI/Show-TweakGUI/WindowClosingHandler.ps1')
$traceGuiStartup={param($Message)}
$timer=[Windows.Threading.DispatcherTimer]::new()
$closeDelay=300
if ($env:BASELINE_SHUTDOWN_CLOSE_DELAY) { $closeDelay=[int]$env:BASELINE_SHUTDOWN_CLOSE_DELAY }
$timer.Interval=[TimeSpan]::FromMilliseconds($closeDelay)
$timer.Add_Tick({$timer.Stop(); $watch.Restart(); $Form.Close()})
$timer.Start()
$watch=[Diagnostics.Stopwatch]::StartNew()
Write-ShutdownTrace 'show dialog'
. (Join-Path $root 'Module/GUI/Show-TweakGUI/ShowDialogErrorHandling.ps1')
Write-ShutdownTrace 'dialog returned'
if($watch.Elapsed.TotalSeconds -gt 3){throw 'Closing blocked the GUI thread'}
$deadline=[DateTime]::UtcNow.AddSeconds(8)
do {
    $open=@($owned | Where-Object {$_.Runspace.RunspaceStateInfo.State -ne 'Closed'})
    if($open.Count -eq 0 -and $pool.RunspacePoolStateInfo.State -eq 'Closed'){break}
    Start-Sleep -Milliseconds 20
} while([DateTime]::UtcNow -lt $deadline)
if($open.Count -gt 0 -or $pool.RunspacePoolStateInfo.State -ne 'Closed'){throw 'Owned workers remain open after window close'}
Write-ShutdownTrace 'all workers closed'
0
