<#
.SYNOPSIS
Exercises the abort dialog decisions and actual worker cancellation in PS 5.1.
Uses sleeping workers; does not apply tweaks or close any application window.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repoRoot 'Module/GUIExecution/WorkerLifecycle.ps1')

function Import-TestFunctions {
    param([string]$Path, [string[]]$Names)
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    foreach ($name in $Names) {
        $fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
        if (-not $fn) { throw "Missing function $name" }
        Set-Item -Path "Function:script:$name" -Value $fn.Body.GetScriptBlock()
    }
}
Import-TestFunctions -Path (Join-Path $repoRoot 'Module/GUIExecution.psm1') -Names @('Request-GuiExecutionWorkerStop', 'Stop-GuiExecutionWorkerAsync', 'Complete-GuiExecutionWorker')
Import-TestFunctions -Path (Join-Path $repoRoot 'Module/GUI/ExecutionOrchestration/ExecutionStateSummary.ps1') -Names @('Set-RunAbortDisposition', 'Get-RunAbortDisposition')
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Module/GUI/StyledControlsSetup.ps1'), [ref]$null, [ref]$null)
foreach ($name in @('RequestRunAbortFn', 'PromptRunAbortFn')) {
    $assignment = $ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$Script:' + $name)}, $true)
    Invoke-Expression $assignment.Extent.Text
}
function Get-UxLocalizedString { param($Key, $Fallback) $Fallback }
function Get-UxBilingualLocalizedString { param($Key, $Fallback) $Fallback }
function Set-GuiStatusText { param($Text, $Tone) }
function LogWarning { param($Message) }
function Write-SwallowedException { param($ErrorRecord, $Source) throw $ErrorRecord }
function Show-ThemedDialog { param($Title, $Message, $Buttons, $AccentButton, $DestructiveButton) $script:choice }
$Script:ForceCloseExecutionFn = { $script:closed = $true }

foreach ($scenario in @('Return to Tweaks', 'Exit Now', 'Cancel', 'Complete')) {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powerShell = [powershell]::Create()
    $powerShell.Runspace = $runspace
    $null = $powerShell.AddScript($(if ($scenario -eq 'Complete') { '42' } else { 'Start-Sleep -Seconds 30' }))
    $invocation = $powerShell.BeginInvoke()
    $worker = [pscustomobject]@{ PowerShell = $powerShell; AsyncResult = $invocation; Runspace = $runspace }
    $Script:RunState = @{ Paused = $false; AbortDisposition = $null }
    $Script:RunInProgress = $true
    $Script:AbortRequested = $false
    $Script:RunAbortDisposition = $null
    $script:closed = $false
    $script:choice = $scenario
    $Script:ExecutionPumpTickFn = { Request-GuiExecutionWorkerStop -PowerShellInstance $powerShell }
    try {
        if ($scenario -ne 'Complete') { & $Script:PromptRunAbortFn }
        switch ($scenario) {
            'Return to Tweaks' {
                if ($script:closed -or (Get-RunAbortDisposition) -ne 'Return' -or -not $Script:AbortRequested) { throw 'Return routed to exit or failed to abort' }
                if (-not $invocation.AsyncWaitHandle.WaitOne(5000)) { throw 'Abort did not stop the worker' }
                Stop-GuiExecutionWorkerAsync -Worker $worker
            }
            'Exit Now' {
                if (-not $script:closed -or (Get-RunAbortDisposition) -ne 'Exit') { throw 'Explicit exit was not honored' }
                Stop-GuiExecutionWorkerAsync -Worker $worker
            }
            'Cancel' {
                if ($script:closed -or $Script:AbortRequested -or $Script:RunState.Paused) { throw 'Cancel changed the run state' }
                if ($invocation.IsCompleted) { throw 'Cancel stopped the worker' }
                Stop-GuiExecutionWorkerAsync -Worker $worker
            }
            'Complete' {
                if (-not $invocation.AsyncWaitHandle.WaitOne(5000)) { throw 'Normal worker did not complete' }
                Complete-GuiExecutionWorker -Worker $worker
            }
        }
        $deadline = [datetime]::UtcNow.AddSeconds(5)
        while ($runspace.RunspaceStateInfo.State -ne 'Closed') {
            if ([datetime]::UtcNow -gt $deadline) { throw "Runspace was not cleaned up: $scenario" }
            Start-Sleep -Milliseconds 50
        }
        Write-Output "PASS: $scenario; worker cleaned up and application host still running."
    }
    finally {
        $powerShell.Dispose()
        $runspace.Dispose()
    }
}
# A further pipeline confirms the host remains usable after cancellation/cleanup.
$probe = [powershell]::Create().AddScript('6 * 7')
try {
    if ($probe.Invoke()[0] -ne 42) { throw 'Host unusable after abort' }
} finally { $probe.Dispose() }
