$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:passed = 0
function Assert-Test { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message }; $script:passed++ }
function Import-TestFunction {
    param([string]$Path, [string]$Name)
    $errors = $null; $tokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $Path), [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    if (-not $fn) { throw "Missing function $Name" }
    Set-Item "Function:script:$Name" $fn.Body.GetScriptBlock()
}
# Resolve the exact identity from the incident, with no GUI or machine changes.
Add-Type -Path (Join-Path $repoRoot 'Launcher/BundledAssemblyResolver.cs')
$resolver = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType('Baseline.RunLauncher.BundledAssemblyResolver') } | Where-Object { $_ } | Select-Object -First 1
$resolver.GetMethod('Install', [Reflection.BindingFlags]'Static,NonPublic').Invoke($null, @([string](Join-Path $repoRoot 'Module/Libraries')))
$vectorPath = [string](Join-Path $repoRoot 'Module/Libraries/System.Numerics.Vectors.dll')
$bundledName = [Reflection.AssemblyName]::GetAssemblyName($vectorPath)
$resolve = $resolver.GetMethod('Resolve', [Reflection.BindingFlags]'Static,NonPublic')
$requestedName = New-Object Reflection.AssemblyName('System.Numerics.Vectors, Version=4.1.4.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
$vector = $resolve.Invoke($null, @([string]$vectorPath, [Reflection.AssemblyName]$bundledName, [Reflection.AssemblyName]$requestedName))
foreach ($identity in @('Other, Version=4.1.4.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a', 'System.Numerics.Vectors, Version=9.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a', 'System.Numerics.Vectors, Version=4.1.4.0, Culture=neutral, PublicKeyToken=null')) {
    $unrelated = New-Object Reflection.AssemblyName($identity)
    Assert-Test ($null -eq $resolve.Invoke($null, @([string]$vectorPath, [Reflection.AssemblyName]$bundledName, [Reflection.AssemblyName]$unrelated))) 'Resolver accepted an unrelated or incompatible assembly identity.'
}
Assert-Test ($vector.GetName().Version -eq [version]'4.1.6.0') 'WinRT vector reference was not resolved to the bundled assembly.'
Assert-Test ($vector.Location -eq (Join-Path $repoRoot 'Module/Libraries/System.Numerics.Vectors.dll')) 'Assembly resolved outside the payload.'
$redirected = [Reflection.Assembly]::Load('System.Numerics.Vectors, Version=4.1.5.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
Assert-Test ($redirected.GetName().Version -eq [version]'4.1.6.0') 'AppDomain handler did not resolve a missing compatible version.'
# Execute from another thread/runspace, matching the embedded worker host.
$rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $ps = [powershell]::Create(); $ps.Runspace = $rs
try {
    [void]$ps.AddScript("[Reflection.Assembly]::Load('System.Numerics.Vectors, Version=4.1.4.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a').GetName().Version.ToString()")
    $result = $ps.Invoke()
    Assert-Test (-not $ps.HadErrors -and $result[0] -in @('4.1.4.0','4.1.6.0')) 'Dependency resolution failed in a worker runspace.'
} finally { $ps.Dispose(); $rs.Dispose() }
# PowerPlan must query GUID identity and never duplicate an existing hidden plan.
Import-TestFunction 'Module/Regions/System/System.Power.psm1' 'PowerPlan'
function Remove-ItemProperty { param($Path,$Name,[switch]$Force,$ErrorAction) }
function Set-Policy { param($Scope,$Path,$Name,$Type) }
function LogInfo { param($Message) }
function Write-ConsoleStatus { param($Status) }
$script:calls = [Collections.Generic.List[object]]::new()
$script:exists = $true; $script:active = ''; $script:creationFails = $false
function Set-BaselineActivePowerScheme { param($Scheme) $script:calls.Add(@('/SETACTIVE',[string]$Scheme)); $script:active = [string]$Scheme; return 0 }
function Invoke-BaselineProcess {
    param($FilePath,$ArgumentList,[switch]$CaptureOutput,[switch]$AllowAnyExitCode)
    $script:calls.Add(@($ArgumentList))
    if ($ArgumentList[0] -eq '/LIST') { throw 'Display lists are not scheme identity probes.' }
    if ($ArgumentList[0] -eq '/DUPLICATESCHEME' -and $script:creationFails) { throw 'Creation rejected' }
    if ($ArgumentList[0] -eq '/SETACTIVE') { $script:active = $ArgumentList[1] }
    [pscustomobject]@{ ExitCode = $(if ($ArgumentList[0] -eq '/QUERY' -and -not $script:exists) { 1 } else { 0 }); StandardOutput = $(if ($ArgumentList[0] -eq '/GETACTIVESCHEME') { $script:active } else { '' }) }
}
foreach ($option in @('Ultimate','CustomPower','High','Balanced')) {
    $script:calls.Clear(); $options = @{$option=$true}; PowerPlan @options
    Assert-Test (@($script:calls | Where-Object { $_[0] -eq '/DUPLICATESCHEME' }).Count -eq 0) "Existing $option scheme was duplicated."
}
$script:exists = $false; $script:calls.Clear(); PowerPlan -Ultimate
$duplicate = @($script:calls | Where-Object { $_[0] -eq '/DUPLICATESCHEME' })
Assert-Test ($duplicate.Count -eq 1 -and $duplicate[0][1] -eq $duplicate[0][2]) 'Missing Ultimate scheme destination was not stable.'
$script:creationFails = $true; $script:calls.Clear(); $failed = $false
try { PowerPlan -Ultimate } catch { $failed = $true }
Assert-Test ($failed -and @($script:calls | Where-Object { $_[0] -eq '/SETACTIVE' }).Count -eq 0) 'Failed creation must not activate another scheme.'
# Selection-only queries use the same predicates while avoiding preview rendering.
Import-TestFunction 'Module/GUI/PreviewBuilders.ps1' 'Get-SelectedTweakRunList'
Import-TestFunction 'Module/GUI/PreviewBuilders.ps1' 'Get-GuiIndexedControlState'
function Test-GuiObjectField { param($Object,$FieldName) if ($null -eq $Object) { return $false }; if ($Object -is [Collections.IDictionary]) { return $Object.Contains($FieldName) }; return [bool]$Object.PSObject.Properties[$FieldName] }
function Test-GuiTweakAvailableOnCurrentSystem { param($Tweak) return -not $Tweak.Unavailable }
function Get-GuiExplicitSelectionDefinition { param($FunctionName) return $script:explicit[$FunctionName] }
function Remove-GuiExplicitSelectionDefinition { param($FunctionName) }
function Get-TweakVisualMetadata { throw 'Button availability must not build a visual preview.' }
$script:explicit = @{}
$manifest = @(); $controls = @{}
foreach ($type in @('Toggle','Choice','NumericRange','Date','Action')) {
    $index = $manifest.Count
    $manifest += @{ Function = $type; Category = 'System'; Type = $type; OnParam = 'Enable'; OffParam = 'Disable'; Options = @('A','B') }
    $controls[$index] = @{ IsEnabled = $true; IsChecked = $true; SelectedIndex = 1; SelectedDate = [datetime]'2026-09-11' }
}
$selected = @(Get-SelectedTweakRunList -TweakManifest $manifest -Controls $controls -SelectionOnly)
Assert-Test ($selected.Count -eq 5) 'Selection-only lost a supported control type.'
$controls[0].IsChecked = $false; $script:explicit.Toggle = @{ Type = 'Toggle'; State = 'Off' }
Assert-Test (@(Get-SelectedTweakRunList -TweakManifest $manifest -Controls $controls -SelectionOnly).Count -eq 5) 'Explicit Off selection was lost.'
$manifest[0].Unavailable = $true; $controls[1].IsEnabled = $false; $controls[2].IsChecked = $false; $controls[4].IsChecked = $false
Assert-Test (@(Get-SelectedTweakRunList -TweakManifest $manifest -Controls $controls -SelectionOnly).Count -eq 1) 'Unavailable, disabled or unselected controls were included.'
foreach ($name in @('Get-GuiTweakRunListPrimaryTab','Test-GuiTweakRunListItemBelongsToUpdates','Test-GuiTweakRunListItemBelongsToGaming','Select-GuiModeScopedTweakRunList','Get-ActiveTweakRunList','Get-GuiScopedRunActionAvailability')) {
    Import-TestFunction 'Module/GUI/ExecutionOrchestration/ExecutionStateSummary.ps1' $name
}
$Script:TweakManifest = $manifest; $Script:Controls = $controls
$Script:AppsModeActive = $false; $Script:DeploymentMediaModeActive = $false; $Script:GamingModeActive = $false; $Script:UpdatesModeActive = $false; $Script:GameMode = $false
Assert-Test ((Get-GuiScopedRunActionAvailability).RunEnabled) 'Scoped availability lost an active selection.'
$Script:UpdatesModeActive = $true
Assert-Test (-not (Get-GuiScopedRunActionAvailability).RunEnabled) 'Scoped availability included another mode.'
# Extract and execute the actual RegistryBackup detector with an absent task.
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Module/GUI/DetectScriptblocks.ps1'), [ref]$null, [ref]$null)
$pair = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.HashtableAst] }, $true).KeyValuePairs | Where-Object { $_.Item1.Value -eq 'RegistryBackup' } | Select-Object -First 1
$detector = $pair.Item2.Find({ param($n) $n -is [Management.Automation.Language.ScriptBlockExpressionAst] }, $true).ScriptBlock.GetScriptBlock()
function Get-ItemProperty { param($Path,$Name,$EA) @{ EnablePeriodicBackup = 1 } }
function Get-ScheduledTask { [CmdletBinding()] param() @() }
Assert-Test (-not (& $detector)) 'An absent backup task should produce false.'
function Get-ScheduledTask { [CmdletBinding()] param() [pscustomobject]@{ TaskName = 'AutoRegBackup' } }
Assert-Test ([bool](& $detector)) 'An existing backup task was not detected.'
Write-Host "PASS: $script:passed incident regression assertions (PowerShell $($PSVersionTable.PSVersion))."
# Compare full previews with lightweight selection for a preset-sized manifest.
$script:visualCalls = 0
function Get-TweakVisualMetadata { param($Tweak,$StateSource) $script:visualCalls++; @{} }
$largeManifest = @(); $largeControls = @{}; $script:explicit = @{}
for ($i = 0; $i -lt 258; $i++) {
    $largeManifest += @{ Function = "Tweak$i"; Category = 'System'; Type = 'Toggle'; OnParam = 'Enable'; OffParam = 'Disable' }
    $largeControls[$i] = @{ IsEnabled = $true; IsChecked = $true }
}
$full = @(Get-SelectedTweakRunList -TweakManifest $largeManifest -Controls $largeControls)
Assert-Test ($script:visualCalls -eq 258) 'Full previews must retain their visual metadata.'
$script:visualCalls = 0
$watch = [Diagnostics.Stopwatch]::StartNew()
$light = @(Get-SelectedTweakRunList -TweakManifest $largeManifest -Controls $largeControls -SelectionOnly)
$watch.Stop()
Assert-Test ($script:visualCalls -eq 0 -and $light.Count -eq $full.Count -and ($light.Function -join ',') -eq ($full.Function -join ',')) 'Lightweight selection changed the preset or built preview metadata.'
Write-Host "258-item selection: $($watch.ElapsedMilliseconds) ms, zero preview metadata calls."
Write-Host "PASS: $script:passed total incident regression assertions."
