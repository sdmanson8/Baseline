<#
.SYNOPSIS
Verifies DiskCleanup through the real GUI action host using a harmless worker.
No cleanup tools or system tweaks are executed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixtureRoot = Join-Path $repoRoot ('.artifacts/Disk Cleanup Test ' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot

function Get-TestFunctionSource {
    param([string]$Path, [string]$Name)
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    $fn = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
    if (-not $fn) { throw "Missing function: $Name" }
    return $fn.Extent.Text
}

$guiPath = Join-Path $repoRoot 'Module/GUIExecution.psm1'
foreach ($name in @('Invoke-GuiExecutionActionHostCommand', 'Test-GuiExecutionObjectField', 'Close-GuiExecutionActionHost')) {
    Invoke-Expression (Get-TestFunctionSource -Path $guiPath -Name $name)
}
$diskCleanupSource = Get-TestFunctionSource -Path (Join-Path $repoRoot 'Module/Regions/SystemTweaks/SystemTweaks.Cleanup.psm1') -Name 'DiskCleanup'

$workerSource = @'
$root = $env:diskcleanup
[IO.File]::WriteAllText((Join-Path $root 'ready'), [string]$PID)
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while (-not (Test-Path -LiteralPath (Join-Path $root 'release'))) {
    if ([DateTime]::UtcNow -gt $deadline) { exit 1 }
    Start-Sleep -Milliseconds 100
}
[IO.File]::WriteAllText((Join-Path $root 'completed'), 'completed')
'@
[IO.File]::WriteAllText((Join-Path $fixtureRoot 'diskcleanup.ps1'), $workerSource)

$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$runspace.SessionStateProxy.SetVariable('FixtureRoot', $fixtureRoot)
$initializer = [powershell]::Create()
$initializer.Runspace = $runspace
$null = $initializer.AddScript(@'
$global:LogFilePath = $FixtureRoot
function Write-ConsoleStatus { param($Action, $Status) }
function LogInfo { param($Message) $Message }
function Join-Path {
    param($Path, $ChildPath)
    if ($ChildPath -eq 'diskcleanup.ps1') { return [IO.Path]::Combine($FixtureRoot, $ChildPath) }
    return [IO.Path]::Combine($Path, $ChildPath)
}
function NextAction { 'next action completed' }
'@ + "`n" + $diskCleanupSource)
$null = $initializer.Invoke()
if ($initializer.HadErrors) { throw ($initializer.Streams.Error | Out-String) }
$initializer.Dispose()
$actionHost = [pscustomobject]@{ Runspace = $runspace; OperationMode = 'ReadWrite' }
$workerProcess = $null
try {
    $cleanup = Invoke-GuiExecutionActionHostCommand -ActionHost $actionHost -CommandName DiskCleanup -TimeoutSeconds 5
    if (-not $cleanup.Succeeded) { throw ($cleanup | Out-String) }
    $next = Invoke-GuiExecutionActionHostCommand -ActionHost $actionHost -CommandName NextAction -TimeoutSeconds 5
    if (-not $next.Succeeded -or $next.Output -notcontains 'next action completed') { throw 'Next action did not complete' }

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'ready'))) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Worker did not start' }
        Start-Sleep -Milliseconds 100
    }
    $workerProcess = Get-Process -Id ([int][IO.File]::ReadAllText((Join-Path $fixtureRoot 'ready')))
    Close-GuiExecutionActionHost -ActionHost $actionHost
    $actionHost = $null
    $workerProcess.Refresh()
    if ($workerProcess.HasExited) { throw 'Worker exited before maintenance was released' }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'release'), 'release')
    if (-not $workerProcess.WaitForExit(10000)) { throw 'Worker did not finish independently' }
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'completed'))) { throw 'Worker did not complete after host closed' }
    Write-Output ('PASS: DiskCleanup returned in {0}s; next action completed; action host closed; worker then finished independently.' -f $cleanup.DurationSeconds)
}
finally {
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'release'), 'release')
    if ($workerProcess) { $workerProcess.Dispose() }
    if ($actionHost) { Close-GuiExecutionActionHost -ActionHost $actionHost }
}
