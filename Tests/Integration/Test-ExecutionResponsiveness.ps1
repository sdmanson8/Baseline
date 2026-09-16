$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Requires Windows PowerShell 5.1.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Read-Ast($relative) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    return $ast
}
function Import-Function($relative, $name) {
    $ast = Read-Ast $relative
    $fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    $body = $fn.Body.Extent.Text
    Set-Item "Function:script:$name" ([scriptblock]::Create($body.Substring(1, $body.Length - 2)))
}
# The actual picker request must carry the worker inventory and return the response.
Import-Function 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1' 'Request-GuiScheduledTasksSelection'
$task = [pscustomobject]@{ TaskName = 'Example'; State = 'Ready' }
$GUIRunState = [pscustomobject]@{}
$GUIRunState | Add-Member ScriptMethod Enqueue {
    param($entry)
    if ($entry.AvailableTasks.Count -ne 1 -or $entry.AvailableTasks[0].TaskName -ne 'Example') { throw 'Inventory lost in request' }
    $entry.ResponseState.Result = [pscustomobject]@{ SelectedTaskNames = @('Example') }
    $entry.ResponseState.Done = $true
}
$response = Request-GuiScheduledTasksSelection -Mode Disable -AvailableTasks @($task)
if ($response.SelectedTaskNames[0] -ne 'Example') { throw 'Selection response lost' }

# Execute the real inventory branch with a query that throws if called on the picker path.
$ast = Read-Ast 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1'
$assignment = $ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$taskInventory'}, $true)
function Get-ScheduledTask { throw 'Unexpected Task Scheduler query' }
$AvailableTasks = @($task)
$inventoryScript = [scriptblock]::Create('param($AvailableTasks)' + "`n" + $assignment.Extent.Text + "`n`$taskInventory")
$taskInventory = & $inventoryScript -AvailableTasks $AvailableTasks
if ($taskInventory.TaskName -ne 'Example') { throw 'Picker did not reuse inventory' }

# Run real worker health-check logic on a separate runspace with deliberately slow checks.
$workerAst = Read-Ast 'Module/GUIExecution/Start-GuiExecutionWorker/Start-GuiExecutionWorker.ps1'
$health = $workerAst.Find({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith("if (`$executionMode -eq 'Run' -and `$healthCheckAppliedCount")}, $true)
if (-not $health) { throw 'Missing worker health-check stage' }
$setup = @'
$executionMode = 'Run'; $healthCheckAppliedCount = 1; $healthCheckRestartPending = $false
$Script:RunState = @{ ErrorCount = 0 }
function Write-GuiTweakExecutionWorkerStartupNotice { param($Message, [switch]$Progress) }
function Resolve-BaselineSettingsAppsFeaturesHealthAssessment { Start-Sleep -Milliseconds 300; [pscustomobject]@{ Healthy = $true } }
function Resolve-BaselineScreenSnippingHealthAssessment { Start-Sleep -Milliseconds 300; [pscustomobject]@{ Healthy = $false; Message = 'test failure' } }
'@
$ps = [powershell]::Create()
try {
    [void]$ps.AddScript($setup + "`n" + $health.Extent.Text + "`n`$Script:RunState")
    $async = $ps.BeginInvoke()
    $ticks = 0
    while (-not $async.IsCompleted) { $ticks++; Start-Sleep -Milliseconds 20 }
    $result = @($ps.EndInvoke($async))[-1]
    if ($ps.HadErrors) { throw ($ps.Streams.Error | Out-String) }
    if ($ticks -lt 5 -or -not $result.SettingsAppsFeaturesHealthAssessment.Healthy -or $result.ScreenSnippingHealthAssessment.Healthy) { throw 'Worker did not preserve health results or blocked caller' }
} finally { $ps.Dispose() }
$completion = Read-Ast 'Module/GUI/ExecutionOrchestration/ExecutionRunOrchestration/Complete-GuiExecutionRun/PostRunHealthAssessment.ps1'
$calls = $completion.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -like 'Resolve-Baseline*HealthAssessment'}, $true)
if ($calls.Count) { throw 'Completion still runs blocking health checks' }
'PASS: inventory transport/reuse and asynchronous health checks preserve results without querying from completion.'
