$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Import-TestFunction {
    param([string]$Path, [string]$Name)
    $errors=$null; $tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $Path),[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if (-not $fn) { throw "Missing function $Name" }
    Set-Item -Path "Function:script:$Name" -Value $fn.Body.GetScriptBlock()
}
function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message }; $script:passed++ }
$script:passed=0
$testRoot=Join-Path $repoRoot '.artifacts/support-regression'
[void][IO.Directory]::CreateDirectory($testRoot)
Import-TestFunction 'Module/SharedHelpers/SupportBundle.Helpers.ps1' 'Get-BaselineSupportBundleClassifiedErrors'
$logPath=Join-Path $testRoot 'log.txt'
@(
 '10-09-2026 05:39 DEBUG: [RunId=run] [Startup] [swallow] callback failed'
 'Exception type: System.Management.Automation.CommandNotFoundException'
 'at callback, startup.ps1: line 100'
 '10-09-2026 05:48 ERROR: [RunId=worker] [Baseline] Line File Message'
 ' 837 PlatformSupport.Helpers.ps1 The power scheme does not exist.'
 '10-09-2026 05:48 INFO: [RunId=run] [GUI] Run summary | Success | Account Protection Warning'
 '10-09-2026 05:48 WARNING: [RunId=run] [GUI] Run summary | Restart pending | Network Devices'
 '10-09-2026 05:49 DEBUG: [RunId=run] [GUI] GUI responsiveness failure: heartbeat delayed'
) | Set-Content -LiteralPath $logPath -Encoding UTF8
$errors=Get-BaselineSupportBundleClassifiedErrors -LogPath $logPath -MaxErrors 0
Assert-Test ($errors.TotalCount -eq 3) 'Classifier must retain real errors and stalls, excluding summary rows.'
Assert-Test ($errors.Counts.DEPENDENCY -eq 1 -and $errors.Counts.NETWORK -eq 0) 'Classifier must use exception identity, not title words.'
Assert-Test ($errors.Errors[1].StackTrace[0] -match 'power scheme') 'Multiline native error detail was lost.'
$capped=Get-BaselineSupportBundleClassifiedErrors -LogPath $logPath -MaxErrors 1
Assert-Test ($capped.Truncated -and $capped.TotalCount -eq 3 -and $capped.IncludedCount -eq 1) 'Truncation must be explicit.'
Import-TestFunction 'Module/SharedHelpers/Json.Helpers.ps1' 'ConvertFrom-BaselineJson'
$TerminalSettingsPath=Join-Path $testRoot 'settings.json'
"{`n  `"profiles`": {`n    `"defaults`": {},`n    `"list`": [{ `"name`": `"Keep me`" }]`n  }`n}" | Set-Content -LiteralPath $TerminalSettingsPath -Encoding UTF8
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Module/Regions/ContextMenu.psm1'),[ref]$null,[ref]$null)
$assignment=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Terminal' -and $n.Right.Extent.Text -match 'Get-Content'},$true)
. ([scriptblock]::Create($assignment.Extent.Text))
Assert-Test ($Terminal.profiles.list[0].name -eq 'Keep me') 'Terminal whole-document read failed.'
Import-TestFunction 'Module/SharedHelpers/Environment.Helpers.ps1' 'Set-BaselineTweakOutcome'
Import-Module (Join-Path $repoRoot 'Module/GUIExecution.psm1') -Force
$rs=[runspacefactory]::CreateRunspace(); $rs.Open()
try {
    $setup=[powershell]::Create(); $setup.Runspace=$rs
    $definition='function Set-BaselineTweakOutcome {' + ${function:Set-BaselineTweakOutcome}.ToString() + '}'
    [void]$setup.AddScript($definition + @"
function Repair { Set-BaselineTweakOutcome -Function 'Child' -Status Skipped -Detail 'Optional SFC skipped'; Set-BaselineTweakOutcome -Function 'Repair' -Status 'Restart pending' -Detail 'Repair applied' }
function Missing { Set-BaselineTweakOutcome -Function 'Missing' -Status 'Not applicable' -Detail 'Component absent' }
function Normal { Set-BaselineTweakOutcome -Function 'Child' -Status Skipped -Detail 'Optional substep skipped'; 'normal output' }
function Failing { Write-Error 'native operation failed' -ErrorAction Continue }
"@)
    $null=$setup.Invoke(); $setup.Dispose()
    $hostContext=[pscustomobject]@{ Runspace=$rs; OperationMode='ReadOnly' }
    $repair=Invoke-GuiExecutionActionHostCommand -ActionHost $hostContext -CommandName Repair -TimeoutSeconds 10
    Assert-Test ($repair.Succeeded -and $repair.Outcome.Status -eq 'Restart pending') 'Operation outcome was lost between runspaces.'
    $missing=Invoke-GuiExecutionActionHostCommand -ActionHost $hostContext -CommandName Missing -TimeoutSeconds 10
    Assert-Test ($missing.Succeeded -and $missing.Outcome.Status -eq 'Not applicable') 'Explicit prerequisite result was lost.'
    $normal=Invoke-GuiExecutionActionHostCommand -ActionHost $hostContext -CommandName Normal -TimeoutSeconds 10
    Assert-Test ($normal.Outcome.Status -eq 'Success' -and $normal.Output[0] -eq 'normal output') 'Outcome leaked between operations or changed output.'
    $failed=Invoke-GuiExecutionActionHostCommand -ActionHost $hostContext -CommandName Failing -TimeoutSeconds 10
    Assert-Test (-not $failed.Succeeded -and $failed.ErrorMessage -match 'native operation failed') 'Nonterminating action-host error was reported as success.'
} finally { $rs.Dispose() }
# PowerPlan runs against deterministic native-process and registry doubles only.
Import-TestFunction 'Module/Regions/System/System.Power.psm1' 'PowerPlan'
function Remove-ItemProperty { param($Path,$Name,[switch]$Force,$ErrorAction) }
function Set-Policy { param($Scope,$Path,$Name,$Type) }
function LogInfo { param($Message) }
function Write-ConsoleStatus { param($Status) }
$script:calls=[Collections.Generic.List[object]]::new()
$script:failDuplicate=$false; $script:wrongActive=$false; $script:activeScheme=''
function Set-BaselineActivePowerScheme { param($Scheme) $script:calls.Add(@('/SETACTIVE',[string]$Scheme)); $script:activeScheme = [string]$Scheme; return 0 }
function Invoke-BaselineProcess {
    param($FilePath,$ArgumentList,[switch]$CaptureOutput,[switch]$AllowAnyExitCode)
    $script:calls.Add(@($ArgumentList))
    if ($ArgumentList[0] -eq '/DUPLICATESCHEME' -and $script:failDuplicate) { throw 'Unsupported scheme' }
    if ($ArgumentList[0] -eq '/SETACTIVE') { $script:activeScheme=$ArgumentList[1] }
    $output=if ($ArgumentList[0] -eq '/GETACTIVESCHEME' -and -not $script:wrongActive) { $script:activeScheme } else { '' }
    [pscustomobject]@{ ExitCode=$(if ($ArgumentList[0] -eq '/QUERY') { 1 } else { 0 }); StandardOutput=$output; StandardError='' }
}
PowerPlan -Ultimate
$duplicate=@($script:calls | Where-Object { $_[0] -eq '/DUPLICATESCHEME' })
Assert-Test ($duplicate.Count -eq 1 -and $duplicate[0][1] -eq $duplicate[0][2]) 'Ultimate duplication must specify its destination GUID.'
$script:failDuplicate=$true; $script:calls.Clear(); $threw=$false
try { PowerPlan -Ultimate } catch { $threw=$true }
Assert-Test ($threw -and @($script:calls | Where-Object { $_[0] -eq '/SETACTIVE' }).Count -eq 0) 'Unsupported scheme silently activated another plan.'
$script:failDuplicate=$false; $script:wrongActive=$true; $threw=$false
try { PowerPlan -Balanced } catch { $threw=$true }
Assert-Test $threw 'Power plan success requires active-scheme verification.'
# Exercise WPF headers with changing counts and existing panel identities.
Add-Type -AssemblyName PresentationFramework
Import-TestFunction 'Module/GUI/TabManagement.ps1' 'Update-PrimaryTabHeaders'
function Start-GuiPerfScope { param($Name,$Note) }
function Stop-GuiPerfScope { param($Scope) }
function Get-PrimaryTabVisibleTweakCount { param($PrimaryTab,$SearchQuery) $script:testCount }
function Get-LocalizedTabHeader { param($PrimaryTab) $PrimaryTab }
function Get-GuiPrimaryTabIconName { param($PrimaryTab) 'Home' }
function New-GuiLabeledIconContent {
    param($IconName,$Text,$IconSize,$Gap,[switch]$AllowTextOnlyFallback)
    $panel=[Windows.Controls.StackPanel]::new(); $label=[Windows.Controls.TextBlock]::new(); $label.Text=$Text; [void]$panel.Children.Add($label); $panel
}
$PrimaryTabs=[Windows.Controls.TabControl]::new(); $tab=[Windows.Controls.TabItem]::new(); $tab.Tag='Initial Setup'; [void]$PrimaryTabs.Items.Add($tab)
$Script:SearchText=''; $Script:SearchResultsTabTag='Search'; $script:testCount=2
Update-PrimaryTabHeaders
$originalHeader=$tab.Header
$script:testCount=3
Update-PrimaryTabHeaders
Assert-Test ([object]::ReferenceEquals($originalHeader,$tab.Header) -and $tab.Header.Children[0].Text -eq 'Initial Setup (3)') 'Header refresh should update text without rebuilding its visual tree.'
# Exercise captured commands after leaving the caller's module scope.
Import-TestFunction 'Module/GUI/ActionHandlers/SystemScanFooterHandlers.ps1' 'Get-GuiSupportBundleRunContext'
$contextDefinition = 'function Get-GuiSupportBundleRunContext {' + ${function:Get-GuiSupportBundleRunContext}.ToString() + '}'
$contextModule = New-Module -ScriptBlock {
    param($Definition)
    . ([scriptblock]::Create($Definition))
    $script:RunState = @{ PreRunSnapshot = @{ Marker = 'before' }; PostRunSnapshot = @{ Marker = 'after' } }
    $script:LastRunProfile = $null
    function Get-BaselineRunId { 'run-identity' }
    function Get-ContextCommand { Get-Command Get-GuiSupportBundleRunContext }
    Export-ModuleMember -Function Get-ContextCommand
} -ArgumentList $contextDefinition
$command = & $contextModule { Get-ContextCommand }
$closure = { & $command }.GetNewClosure()
$context = & $closure
Assert-Test ($context.RunId -eq 'run-identity' -and $context.Pre.Marker -eq 'before' -and $context.Post.Marker -eq 'after') 'Export closure lost live module state.'
$windowModule = New-Module -ScriptBlock {
    function Invoke-WindowTransition {
        function Set-WindowState { param($Window,$Maximized,[switch]$PreserveRestoreBounds) Update-WindowState -Window $Window -Value $Maximized }
        function Update-WindowState { param($Window,$Value) $Window.Maximized=$Value }
        $Form=[pscustomobject]@{ Maximized=$false }
        $setStartupWindowMaximizedCommand=Get-Command Set-WindowState
        $apply=[Action[bool]]({param([bool]$WindowMaximized) & $setStartupWindowMaximizedCommand -Window $Form -Maximized $WindowMaximized -PreserveRestoreBounds}.GetNewClosure())
        $apply.Invoke($true)
        return $Form.Maximized
    }
    Export-ModuleMember -Function Invoke-WindowTransition
}
Assert-Test ([bool](& $windowModule { Invoke-WindowTransition })) 'Captured maximize command lost sibling helpers in a deferred closure.'
Import-TestFunction 'Module/SharedHelpers/SupportBundle.Helpers.ps1' 'Get-BaselineSupportBundleObjectValue'
Import-TestFunction 'Module/SharedHelpers/SupportBundle.Helpers.ps1' 'New-BaselineSupportBundleUserActionContext'
$profilePath=Join-Path $testRoot 'session.json'
'{"State":{"ActivePresetName":"Advanced","ExplicitSelectionDefinitions":[],"SafeMode":false,"AdvancedMode":true,"UIDensity":"Compact","CurrentPrimaryTab":"Initial Setup"}}' | Set-Content -LiteralPath $profilePath -Encoding UTF8
$actionContext=New-BaselineSupportBundleUserActionContext -ProfilePath $profilePath
Assert-Test ($actionContext.PresetUsed -eq 'Advanced') 'Export lost the active preset.'
# Execute Terminal's read/update/write path against a synthetic settings file.
Import-TestFunction 'Module/Regions/ContextMenu.psm1' 'OpenWindowsTerminalAdminContext'
function Get-AppxPackage { param($Name,$WarningAction) [pscustomobject]@{ PackageFamilyName = 'Test.Terminal' } }
function Get-WindowsTerminalSettingsPath { param($Package) $TerminalSettingsPath }
'{"profiles":{"defaults":{"colorScheme":{"child":{"deep":{"value":"Unicode preserved"}}}},"list":[{"name":"Keep me"}]}}' | Set-Content -LiteralPath $TerminalSettingsPath -Encoding UTF8
OpenWindowsTerminalAdminContext -Disable
$savedTerminal=Get-Content -LiteralPath $TerminalSettingsPath -Raw | ConvertFrom-Json
Assert-Test ($savedTerminal.profiles.defaults.elevate -eq $false -and $savedTerminal.profiles.defaults.colorScheme.child.deep.value -eq 'Unicode preserved' -and $savedTerminal.profiles.list[0].name -eq 'Keep me') 'Terminal update truncated unrelated settings.'
'{' | Set-Content -LiteralPath $TerminalSettingsPath -Encoding UTF8
$parseFailed=$false
try { OpenWindowsTerminalAdminContext -Disable } catch { $parseFailed=$true }
Assert-Test $parseFailed 'Invalid Terminal settings were not surfaced as an operation failure.'
# A real unsupported powercfg query must remain a clean, read-only capability probe.
Remove-Item Function:Invoke-BaselineProcess
. (Join-Path $repoRoot 'Module/SharedHelpers/Process.Helpers.ps1')
Import-TestFunction 'Module/SharedHelpers/PlatformSupport.Helpers.ps1' 'Test-BaselinePowerSchemeSettingAvailable'
$errorCount=$Global:Error.Count
$available=Test-BaselinePowerSchemeSettingAvailable -SubgroupGuid '00000000-0000-0000-0000-000000000000' -SettingGuid '00000000-0000-0000-0000-000000000000'
Assert-Test (-not $available -and $Global:Error.Count -eq $errorCount) 'Unsupported native capability query polluted the error stream.'
Write-Host "PASS: $script:passed support-bundle regression assertions (PowerShell $($PSVersionTable.PSVersion))."
