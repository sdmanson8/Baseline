$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Windows PowerShell 5.1 required.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Read-TestAst($RelativePath) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $RelativePath), [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $ast
}
$ast = Read-TestAst 'Module/Regions/InitialSetup.psm1'
$fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'CreateRestorePoint'}, $true)
. ([scriptblock]::Create($fn.Extent.Text))
function LogInfo { param($Message) }
function LogError { param($Message) $Script:Messages.Add($Message) }
function Write-ConsoleStatus { param($Status) }
function Set-BaselineTweakOutcome { param($Function,$Status,$Detail) $Script:Outcome = @{Function=$Function; Status=$Status; Detail=$Detail} }
function Get-Service {
    param($Name)
    if ($Script:Scenario -eq 'missing-service' -and $Name -eq 'swprv') { throw 'Missing swprv' }
    [pscustomobject]@{ StartType = 'Disabled'; Status = 'Stopped' }
}
function Set-Service { param($Name, $StartupType) $Script:Services.Add("$Name=$StartupType") }
function Start-Service { param($Name) $Script:Services.Add("start:$Name") }
function Enable-ComputerRestore { param($Drive) }
function Disable-ComputerRestore { throw 'Must not disable protection after creating a checkpoint' }
function Get-OSInfo { [pscustomobject]@{OSName='Windows 11'} }
function Get-BaselineDisplayVersion { '24H2' }
function Get-ComputerRestorePoint {
    $Script:Queries++
    [pscustomobject]@{ Description = 'Baseline | Utility for Windows 11 24H2'; SequenceNumber = 1 }
    if ($Script:Queries -gt 1 -and $Script:Scenario -ne 'no-new-point') {
        [pscustomobject]@{ Description = 'Baseline | Utility for Windows 11 24H2'; SequenceNumber = 2 }
    }
}
function Get-Item {
    param($LiteralPath)
    $key = [pscustomobject]@{}
    $key | Add-Member ScriptMethod GetValueNames { if ($Script:Scenario -ne 'missing-frequency') { 'SystemRestorePointCreationFrequency' } }
    $key | Add-Member ScriptMethod GetValue { param($Name) 77 }
    $key | Add-Member ScriptMethod GetValueKind { param($Name) [Microsoft.Win32.RegistryValueKind]::DWord }
    $key | Add-Member ScriptMethod Close {}
    $key
}
function New-ItemProperty { param($Path,$Name,$PropertyType,$Value,[switch]$Force) $Script:Frequencies.Add([int]$Value) }
function Remove-ItemProperty { param($Path,$Name) $Script:Frequencies.Add(-1) }
function Start-Job {
    param($ScriptBlock,$ArgumentList)
    if ($Script:Services -notcontains 'start:swprv') { throw 'Checkpoint started before its provider' }
    [pscustomobject]@{Fixture=$true}
}
function Wait-Job { param([Parameter(ValueFromPipeline=$true)]$InputObject,$Timeout) process { if ($Script:Scenario -ne 'timeout') { $InputObject } } }
function Receive-Job { param([Parameter(ValueFromPipeline=$true)]$InputObject) process { if ($Script:Scenario -eq 'checkpoint-error') { throw 'Checkpoint failed' } } }
function Remove-Job { param([Parameter(ValueFromPipeline=$true)]$InputObject,[switch]$Force) process { $Script:JobRemoved=$true } }
foreach ($case in @('success','missing-frequency','checkpoint-error','timeout','no-new-point','missing-service')) {
    $Script:Scenario=$case; $Script:Queries=0; $Script:JobRemoved=$false
    $Script:Outcome=$null
    $Script:Services=[Collections.Generic.List[string]]::new()
    $Script:Frequencies=[Collections.Generic.List[int]]::new()
    $Script:Messages=[Collections.Generic.List[string]]::new()
    $result = CreateRestorePoint
    if ($result -ne ($case -in @('success','missing-frequency'))) { throw "Incorrect restore result: $case" }
    if (-not $result -and ($Script:Outcome.Status -ne 'Failed' -or -not $Script:Outcome.Detail)) { throw 'Failure outcome was not reported' }
    if ($case -ne 'missing-service') {
        if (-not $Script:JobRemoved) { throw 'Job was not removed' }
        $expected = if ($case -eq 'missing-frequency') { -1 } else { 77 }
        if ($Script:Frequencies.Count -ne 2 -or $Script:Frequencies[0] -ne 0 -or $Script:Frequencies[1] -ne $expected) { throw "Frequency was not restored: $case" }
    }
    Write-Host "PASS: restore point $case"
}

# Run the actual support-export worker body with fixture helpers. Its detector
# requires a worker-private function, and must not invoke a parent-bound detector.
$fixture = Join-Path $root ('.artifacts/Support Worker ' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory((Join-Path $fixture 'GUI'))
[IO.File]::WriteAllText((Join-Path $fixture 'GUI/DetectScriptblocks.ps1'), @'
function Get-WorkerOnlyValue { 'worker-owned' }
$Script:DetectScriptblocks = @{ Fixture = { Get-WorkerOnlyValue } }
$Script:VisibleIfScriptblocks = @{}
'@)
[IO.File]::WriteAllText((Join-Path $fixture 'SharedHelpers.psm1'), @'
function Import-TweakManifestFromData {
    param($ModuleRoot,$DetectScriptblocks,$VisibleIfScriptblocks)
    [pscustomobject]@{Function='Fixture'; Detect=$DetectScriptblocks.Fixture}
}
function Export-BaselineSupportBundle {
    param($OutputPath,$Manifest,$ProfilePath,$SessionLogPath,$PreSnapshot,$PostSnapshot,$IncludeAuditLog,$IncludeTestReport,$ConnectivityResults,$ProgressCallback)
    if ((& $Manifest[0].Detect) -ne 'worker-owned') { throw 'Wrong detection scope' }
    [pscustomobject]@{ OutputPath=$OutputPath }
}
'@)
$ast = Read-TestAst 'Module/GUI/ActionHandlers/SystemScanFooterHandlers.ps1'
$fn = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-GuiSupportBundleExportAsync'}, $true)
$call = $fn.Find({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'AddScript'}, $true)
$body = $call.Arguments[0].ScriptBlock.Extent.Text
$sync = [hashtable]::Synchronized(@{})
$ps = [powershell]::Create()
try {
    $null=$ps.AddScript($body.Substring(1,$body.Length-2)).AddArgument((Join-Path $fixture 'SharedHelpers.psm1')).AddArgument($fixture).AddArgument('fixture.zip').AddArgument('').AddArgument('').AddArgument($null).AddArgument($null).AddArgument(@()).AddArgument($sync)
    $async=$ps.BeginInvoke()
    if (-not $async.AsyncWaitHandle.WaitOne(10000)) { throw 'Export worker timed out' }
    $result=@($ps.EndInvoke($async))
    if ($ps.HadErrors) { throw ($ps.Streams.Error | Out-String) }
    if ($sync.OutputPath -ne 'fixture.zip' -or $result.Count -ne 1) { throw 'Export worker lost result' }
    Write-Host 'PASS: export worker owns its detection functions and returns its result'
}
finally { $ps.Dispose() }

# The action host consumes explicit failure outcomes without interpreting arbitrary
# Boolean output as failure (some commands legitimately return false).
$hostAst = Read-TestAst 'Module/GUIExecution.psm1'
foreach ($name in @('Invoke-GuiExecutionActionHostCommand','Test-GuiExecutionObjectField')) {
    $definition=$hostAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$environmentAst=Read-TestAst 'Module/SharedHelpers/Environment.Helpers.ps1'
$outcomeDefinition=$environmentAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-BaselineTweakOutcome'},$true)
$runspace=[runspacefactory]::CreateRunspace()
$runspace.Open()
$initializer=[powershell]::Create()
$initializer.Runspace=$runspace
try {
    $null=$initializer.AddScript($outcomeDefinition.Extent.Text + @'

function FixtureFailure { Set-BaselineTweakOutcome -Function FixtureFailure -Status Failed -Detail 'fixture checkpoint failure'; $false }
function FixtureBoolean { $false }
'@)
    $null=$initializer.Invoke()
    if ($initializer.HadErrors) { throw ($initializer.Streams.Error | Out-String) }
    $actionHost=[pscustomobject]@{Runspace=$runspace; OperationMode='ReadWrite'}
    $failure=Invoke-GuiExecutionActionHostCommand -ActionHost $actionHost -CommandName FixtureFailure -TimeoutSeconds 5
    if ($failure.Succeeded -or $failure.ErrorMessage -notmatch 'fixture checkpoint failure') { throw 'Explicit failure was reported as success' }
    $boolean=Invoke-GuiExecutionActionHostCommand -ActionHost $actionHost -CommandName FixtureBoolean -TimeoutSeconds 5
    if (-not $boolean.Succeeded -or $boolean.Output[0] -ne $false) { throw 'Boolean output contract changed' }
    Write-Host 'PASS: action host reports explicit failure and preserves Boolean output'
}
finally { $initializer.Dispose(); $runspace.Dispose() }
