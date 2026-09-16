$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Run with Windows PowerShell 5.1.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:passed = 0
function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message }; $script:passed++ }
function Get-TestFunction { param($Path,$Name)
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $Path),[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if (-not $fn) { throw "Missing function $Name" }; $fn.Extent.Text
}
Import-Module (Join-Path $repoRoot 'Module/GUIExecution.psm1') -Force -DisableNameChecking
$requests=@(
    @{Path='Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1';Name='Request-GuiScheduledTasksSelection';Arguments=@{Mode='Disable'}},
    @{Path='Module/Regions/UWPApps/UWPApps/GuiUwpAppsSelection.ps1';Name='Request-GuiUWPAppsSelection';Arguments=@{Mode='Uninstall'}},
    @{Path='Module/Regions/System/System.WindowsFeatures.psm1';Name='Request-GuiSystemSelection';Arguments=@{RequestType='WindowsFeatures';Mode='Disable'}}
)
foreach ($request in $requests) {
    $rs=[runspacefactory]::CreateRunspace(); $rs.Open()
    $queue=New-Object 'Collections.Concurrent.ConcurrentQueue[object]'
    $rs.SessionStateProxy.SetVariable('GUIRunState',$queue)
    $setup=[powershell]::Create(); $setup.Runspace=$rs
    [void]$setup.AddScript((Get-TestFunction $request.Path $request.Name)); [void]$setup.Invoke(); $setup.Dispose()
    $responder=[powershell]::Create()
    [void]$responder.AddScript({param($Queue)
        $entry=$null
        while (-not $Queue.TryDequeue([ref]$entry)) { Start-Sleep -Milliseconds 20 }
        Start-Sleep -Milliseconds 1500
        $entry.ResponseState.Result='confirmed'; $entry.ResponseState.Done=$true
    }).AddArgument($queue)
    $async=$responder.BeginInvoke()
    try {
        $result=Invoke-GuiExecutionActionHostCommand -ActionHost @{Runspace=$rs;OperationMode='ReadWrite'} -CommandName $request.Name -CommandArguments $request.Arguments -TimeoutSeconds 1
        Assert-Test ($result.Succeeded -and -not $result.TimedOut -and $result.Output[0] -eq 'confirmed') "$($request.Name) charged user interaction against the timeout: $($result.ErrorMessage)"
        Assert-Test ($result.DurationSeconds -ge 1.5) 'Wall duration must retain time spent waiting for a selection.'
        [void]$responder.EndInvoke($async)
        $setup=[powershell]::Create(); $setup.Runspace=$rs
        [void]$setup.AddScript('function Test-ActiveWork { Start-Sleep -Seconds 3 }'); [void]$setup.Invoke(); $setup.Dispose()
        $result=Invoke-GuiExecutionActionHostCommand -ActionHost @{Runspace=$rs;OperationMode='ReadWrite'} -CommandName Test-ActiveWork -TimeoutSeconds 1
        Assert-Test $result.TimedOut 'Active work did not time out after a completed selection.'
    } finally { $responder.Dispose(); $rs.Dispose() }
}
# The same invocation must resume its remaining budget, and Abort must work
# while the execution clock is paused for a picker.
foreach ($scenario in @('Resume','Abort')) {
    $rs=[runspacefactory]::CreateRunspace(); $rs.Open()
    $queue=New-Object 'Collections.Concurrent.ConcurrentQueue[object]'
    $state=[hashtable]::Synchronized(@{AbortRequested=$false})
    $rs.SessionStateProxy.SetVariable('GUIRunState',$queue)
    $setup=[powershell]::Create(); $setup.Runspace=$rs
    [void]$setup.AddScript((Get-TestFunction $requests[0].Path $requests[0].Name) + '; function Test-PickerThenWork { Request-GuiScheduledTasksSelection -Mode Disable; Start-Sleep -Seconds 3 }')
    [void]$setup.Invoke(); $setup.Dispose()
    $responder=[powershell]::Create()
    [void]$responder.AddScript({param($Queue,$State,$Scenario)
        $entry=$null
        while (-not $Queue.TryDequeue([ref]$entry)) { Start-Sleep -Milliseconds 20 }
        Start-Sleep -Milliseconds 1500
        if ($Scenario -eq 'Abort') { $State.AbortRequested=$true }
        else { $entry.ResponseState.Done=$true }
    }).AddArgument($queue).AddArgument($state).AddArgument($scenario)
    $async=$responder.BeginInvoke()
    try {
        $result=Invoke-GuiExecutionActionHostCommand -ActionHost @{Runspace=$rs;OperationMode='ReadWrite'} -CommandName Test-PickerThenWork -TimeoutSeconds 1 -RunState $state
        if ($scenario -eq 'Abort') { Assert-Test ($result.Aborted -and -not $result.TimedOut) 'Abort failed while waiting for a picker.' }
        else { Assert-Test ($result.TimedOut -and $result.DurationSeconds -ge 2.5) 'The active-work budget was not resumed after picker cancellation.' }
        [void]$responder.EndInvoke($async)
    } finally { $responder.Dispose(); $rs.Dispose() }
}
# Exercise the real outcome protocol without touching machine settings.
Invoke-Expression (Get-TestFunction 'Module/SharedHelpers/Environment.Helpers.ps1' 'Set-BaselineTweakOutcome')
Invoke-Expression (Get-TestFunction 'Module/Regions/UIPersonalization/UIPersonalization.Explorer.psm1' 'TaskManagerDetails')
function Get-WindowsVersionData { @{CurrentBuild=26100} }
function Start-Process { throw 'Modern Task Manager must not be launched to initialize a legacy preference.' }
$Global:BaselineTweakOutcomeContext=@{Function='TaskManagerDetails';Status='Success';Detail=''}
TaskManagerDetails -Enable
Assert-Test ($Global:BaselineTweakOutcomeContext.Status -eq 'Not applicable') 'Modern Task Manager was reported as applied.'
Invoke-Expression (Get-TestFunction 'Module/Regions/System/System.Power.psm1' 'PowerPlan')
function Set-Policy { param($Scope,$Path,$Name,$Type) }
function LogInfo { param($Message) }
function Write-ConsoleStatus { param($Status,$Action) }
function Invoke-BaselineProcess { param($FilePath,$ArgumentList,[switch]$CaptureOutput,[switch]$AllowAnyExitCode)
    if ($ArgumentList[0] -ne '/QUERY') { throw 'Unsupported activation must not change to another plan or report success.' }
    @{ExitCode=0;StandardOutput=''}
}
function Set-BaselineActivePowerScheme { param($Scheme) return $script:nativeStatus }
$script:nativeStatus=50
$Global:BaselineTweakOutcomeContext=@{Function='PowerPlan';Status='Success';Detail=''}
PowerPlan -Ultimate
Assert-Test ($Global:BaselineTweakOutcomeContext.Status -eq 'Not applicable') 'ERROR_NOT_SUPPORTED was misclassified.'
$script:nativeStatus=5; $failed=$false
try { PowerPlan -Ultimate } catch { $failed=$true }
Assert-Test $failed 'An access denied native activation result was hidden.'
function LogWarning { param($Message) }
function Test-Windows11FeatureBranchSupport { return $false }
foreach ($guard in @(
    @{Path='Module/Regions/SystemTweaks/SystemTweaks.General.psm1';Name='CrossDeviceResume';Options=@('Enable','Disable')},
    @{Path='Module/Regions/UWPApps.psm1';Name='RevertStartMenu';Options=@('Enable','Disable')},
    @{Path='Module/Regions/StartMenuApps.psm1';Name='StartMenuAllSectionCategories';Options=@('Show','Hide')}
)) {
    Invoke-Expression (Get-TestFunction $guard.Path $guard.Name)
    foreach ($option in $guard.Options) {
        $Global:BaselineTweakOutcomeContext=@{Function=$guard.Name;Status='Success';Detail=''}
        $options=@{$option=$true}; & $guard.Name @options
        Assert-Test ($Global:BaselineTweakOutcomeContext.Status -eq 'Not applicable') "$($guard.Name) -$option reported success on an unsupported build."
    }
}
Remove-Variable BaselineTweakOutcomeContext -Scope Global
Write-Host "PASS: $script:passed fresh-install regression assertions (PowerShell $($PSVersionTable.PSVersion))."
