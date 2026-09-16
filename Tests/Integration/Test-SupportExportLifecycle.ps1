$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 required'}
Add-Type -AssemblyName PresentationFramework
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $root 'Module/GUIExecution/WorkerLifecycle.ps1')
$fixture=Join-Path $root ('.artifacts/export-lifecycle-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'GUI'))
[IO.File]::WriteAllText((Join-Path $fixture 'GUI/DetectScriptblocks.ps1'),'$Script:DetectScriptblocks=@{}; $Script:VisibleIfScriptblocks=@{}')
[IO.File]::WriteAllText((Join-Path $fixture 'SharedHelpers.psm1'),@'
function Import-TweakManifestFromData { param($ModuleRoot,$DetectScriptblocks,$VisibleIfScriptblocks) @() }
function Export-BaselineSupportBundle {
    param($OutputPath,$Manifest,$ProfilePath,$SessionLogPath,$PreSnapshot,$PostSnapshot,$IncludeAuditLog,$IncludeTestReport,$ConnectivityResults,$ProgressCallback)
    & $ProgressCallback 'collecting fixture'
    Start-Sleep -Milliseconds 700
    if($OutputPath -eq 'failure.zip'){throw 'fixture export failure'}
    [pscustomobject]@{OutputPath=$OutputPath}
}
'@)
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Module/GUI/ActionHandlers/SystemScanFooterHandlers.ps1'),[ref]$null,[ref]$errors)
if($errors){throw ($errors | Out-String)}
$definitions=foreach($name in @('Start-GuiSupportBundleExportAsync','Receive-GuiSupportBundleExport','Stop-GuiSupportBundleExportWorker')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $fn){throw "Missing $name"}; $fn.Extent.Text
}
$module=New-Module -ArgumentList $fixture,($definitions -join "`r`n") -ScriptBlock {
    param($Fixture,$Definitions)
    . ([scriptblock]::Create($Definitions))
    $Script:GuiModuleBasePath=$Fixture
    $Script:StopGuiSupportBundleExportWorkerScript=${function:Stop-GuiSupportBundleExportWorker}
    function LogInfo { param($Message) $Script:Log.Add($Message) }
    function LogError { param($Message) $Script:Log.Add($Message) }
    function Format-BaselineErrorForLog { param($ErrorObject,$Prefix) "$Prefix : $($ErrorObject.Exception.Message)" }
    function Invoke-UserLaunch { param($FilePath,$ArgumentList,$Description) $Script:Launches++ }
    function Write-SwallowedException { param($ErrorRecord,$Source) throw $ErrorRecord }
    function Get-FixtureTone { param($Tone) "color:$Tone" }
    function Set-FixtureStatus { param($Text,$Tone) $Script:Statuses.Add((Get-FixtureTone $Tone)+':'+$Text) }
    function Start-TestExport {
        param($Fail)
        $Script:Statuses=[Collections.Generic.List[string]]::new()
        $Script:Log=[Collections.Generic.List[string]]::new(); $Script:Launches=0
        $Script:Menu=[pscustomobject]@{IsEnabled=$false}
        $output=if($Fail){'failure.zip'}else{'success.zip'}
        Start-GuiSupportBundleExportAsync -OutputPath $output -SessionStatePath (Join-Path $Fixture 'session.json') -SessionLogPath 'fixture.log' -MenuItem $Script:Menu -SetStatusTextCommand (Get-Command Set-FixtureStatus) -SetProgressDialogStatus {} -CloseProgressDialog {} -ShowDialog {}
        $Script:OwnedRunspace=$Script:SupportBundleExportWorker.Runspace
    }
    function Read-TestExport { @{Worker=$Script:SupportBundleExportWorker; InProgress=$Script:SupportBundleExportInProgress; Statuses=@($Script:Statuses); Log=@($Script:Log); Launches=$Script:Launches; Menu=$Script:Menu; Runspace=$Script:OwnedRunspace} }
    Export-ModuleMember -Function Start-TestExport,Read-TestExport
}
Import-Module $module
foreach($failure in @($false,$true)) {
    Start-TestExport -Fail $failure
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    do {
        $frame=[Windows.Threading.DispatcherFrame]::new()
        $pulse=[Windows.Threading.DispatcherTimer]::new(); $pulse.Interval=[TimeSpan]::FromMilliseconds(25)
        $pulse.Add_Tick({$pulse.Stop(); $frame.Continue=$false}.GetNewClosure()); $pulse.Start()
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        $state=Read-TestExport
        if(-not $state.Worker -and $state.Runspace.RunspaceStateInfo.State -eq 'Closed'){break}
    }while([DateTime]::UtcNow -lt $deadline)
    if($state.Worker -or $state.InProgress -or -not $state.Menu.IsEnabled){throw 'Completion did not clear module-owned worker state and restore menu'}
    if($state.Runspace.RunspaceStateInfo.State -ne 'Closed'){throw 'Export runspace remained open'}
    $tone=if($failure){'danger'}else{'success'}
    if(-not ($state.Statuses -match "^color:$tone")){throw "Missing $tone status from private helper"}
    if($state.Launches -ne [int](-not $failure)){throw 'Incorrect Explorer launch count'}
    Write-Host "PASS: export failure=$failure; private status helpers, completion state, menu and runspace cleanup"
}
Remove-Module $module
