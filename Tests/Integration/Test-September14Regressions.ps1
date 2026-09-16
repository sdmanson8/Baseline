$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Requires Windows PowerShell 5.1.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:passed = 0
function Assert-Test($Condition, $Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
function Get-TestFunction($Path, $Name) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $Path),[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name},$true)
    if (-not $fn) { throw "Missing function $Name" }; $fn.Extent.Text
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught=$null
    try { & $Action } catch { $caught=$_ }
    Assert-Test ($caught -and $caught.Exception.Message -match $Pattern) "Expected error matching $Pattern; got $caught"
}
function LogInfo { param($Message) }
function LogWarning { param($Message) }
function LogError { param($Message) }
function Write-ConsoleStatus { param($Action,$Status) }
function Write-Status { param($msg) }
function Invoke-SilencedProgress { param($Action) & $Action }
foreach ($name in @('Get-GuiNumericRangeValue','ConvertTo-PowerSchemeDisplayValue','ConvertTo-PowerSchemeSystemValue')) {
    . ([scriptblock]::Create((Get-TestFunction 'Module/SharedHelpers.psm1' $name)))
}
foreach ($value in @(50,589,1635,100000)) {
    Assert-Test ((ConvertTo-PowerSchemeSystemValue $value Milliseconds) -eq $value) 'Native milliseconds were rescaled.'
    Assert-Test ((ConvertTo-PowerSchemeDisplayValue $value Milliseconds) -eq $value) 'Displayed milliseconds were rescaled.'
}
Assert-Test ((ConvertTo-PowerSchemeSystemValue 2 Minutes) -eq 120) 'Minute conversion changed.'
foreach ($name in @('Set-PowerSchemeNumericRangeSetting','Set-PowerSchemeChoiceSetting')) {
    . ([scriptblock]::Create((Get-TestFunction 'Module/Regions/System/System.Power.psm1' $name)))
}
function Set-PowerSchemeSettingVisibility { param($SubgroupGuid,$SettingGuid) }
function Set-PowerSchemeSettingValue { param($SubgroupGuid,$SettingGuid,$Value,$Units) $script:writtenValue=$Value }
Set-PowerSchemeNumericRangeSetting -DisplayName Test -SubgroupGuid a -SettingGuid b -MinValue 1 -ACValue 5 -DCValue 9
Assert-Test ($script:writtenValue.ACValue -eq 5 -and $script:writtenValue.DCValue -eq 9) 'Channel validation included unbound Value=0.'
Assert-Throws { Set-PowerSchemeNumericRangeSetting -DisplayName Test -SubgroupGuid a -SettingGuid b -Value 101 } 'outside the supported range'
function Set-PowerSchemeSettingValue { throw 'native power failure' }
Assert-Throws { Set-PowerSchemeNumericRangeSetting -DisplayName Test -SubgroupGuid a -SettingGuid b -Value 50 } 'native power failure'
Assert-Throws { Set-PowerSchemeChoiceSetting -DisplayName Test -SubgroupGuid a -SettingGuid b -Value 1 } 'native power failure'

foreach ($name in @('Set-OptionalFeatureBundleState','LegacyMediaBundle')) {
    . ([scriptblock]::Create((Get-TestFunction 'Module/Regions/System/System.FeatureBundles.psm1' $name)))
}
$script:features=New-Object 'Collections.Generic.List[string]'
function Disable-WindowsOptionalFeature { param($FeatureName,[switch]$Online,[switch]$NoRestart,$ErrorAction,$WarningAction) $script:features.Add($FeatureName) }
LegacyMediaBundle -Disable
Assert-Test ($script:features.Contains('WindowsMediaPlayer') -and -not $script:features.Contains('Media.WindowsMediaPlayer')) 'Capability name passed to feature API.'
function Disable-WindowsOptionalFeature { throw 'servicing failure' }
Assert-Throws { LegacyMediaBundle -Disable } 'servicing failure'

# Evaluate the service deletion policy with every external action replaced.
# This runs the real absent-service/error branches without modifying services.
function Get-Service { param($ErrorAction) }
function Test-Path { param($LiteralPath,$ErrorAction) $false }
function Remove-Item { throw 'Unexpected registry mutation in absent-component test.' }
function Invoke-BaselineProcess { param($FilePath,$ArgumentList,$TimeoutSeconds,[switch]$AllowAnyExitCode,[switch]$CaptureOutput)
    Assert-Test ($ArgumentList[0] -eq 'delete' -and $ArgumentList[1] -eq 'WSAIFabricSvc') 'Unexpected service operation.'
    [pscustomobject]@{ExitCode=$script:serviceExit;StandardOutput='test';StandardError=''}
}
$revert=$false; $backup=$false
$policy=Join-Path $repoRoot 'Module/Regions/UWPApps/AIRemoval/Disable-Registry-Keys/WSAIFabricServicePolicy.ps1'
foreach ($code in @(0,1060)) { $script:serviceExit=$code; . $policy }
$script:serviceExit=5
Assert-Throws { . $policy } 'exit code 5'

. ([scriptblock]::Create((Get-TestFunction 'Module/Regions/Defender/Defender.Hardening.psm1' 'DefenderAppGuard')))
function Get-WindowsOptionalFeature { param([switch]$Online,$ErrorAction,$WarningAction) }
function Set-BaselineTweakOutcome { param($Function,$Status,$Detail) $script:outcome=$Status }
DefenderAppGuard -Enable
Assert-Test ($script:outcome -eq 'Not applicable') 'Absent WDAG reported success/restart.'
$script:outcome=$null
DefenderAppGuard -Disable
Assert-Test ($script:outcome -eq 'Not applicable') 'Absent WDAG disable reported success.'

# Real WPF controls with actual handlers; no application window or settings changes.
Add-Type -AssemblyName PresentationFramework
. ([scriptblock]::Create((Get-TestFunction 'Module/GUI/TweakRowFactory/ControlFactories.ps1' 'Register-GuiNumericRangeSelectionHandlers')))
function Get-TweakRowFactoryFunctionCapture { param($Name)
    switch ($Name) {
        'Get-GuiNumericRangeChannelValue' { {param($Value,$Channel,$NumericRange) [int]$Value} }
        'Format-GuiPowerSchemeValueText' { {param($Value,$NumericRange,$Units) [string]$Value} }
        'Get-UxLocalizedString' { {param($Key,$Fallback,$FormatArgs) $Fallback} }
    }
}
function Register-GuiEventHandler { param($Source,$EventName,$Handler) $Source."add_$EventName"($Handler) }
$state=@{IsRestoring=$false;IsChecked=$false;ACValue=0;DCValue=0;Value=$null}
$record=@{Refreshes=0;Definition=$null}
$context=@{
    RemoveExplicitSelectionDefinition={param($FunctionName) $record.Definition=$null}.GetNewClosure()
    GetExplicitSelectionDefinition={param($FunctionName) $record.Definition}.GetNewClosure()
    SetExplicitSelectionDefinition={param($FunctionName,$Definition) $record.Definition=$Definition}.GetNewClosure()
    UpdateRunActionAvailabilityScript={$record.Refreshes++}.GetNewClosure()
}
$check=New-Object Windows.Controls.CheckBox
$ac=New-Object Windows.Controls.Slider; $ac.Maximum=100000
$dc=New-Object Windows.Controls.Slider; $dc.Maximum=100000
Register-GuiNumericRangeSelectionHandlers -CheckBox $check -AcSlider $ac -DcSlider $dc -FunctionName Test -NumericRange @{} -Units Milliseconds -RowContext $context -StateControl $state
$check.IsChecked=$true
Assert-Test ($record.Refreshes -eq 1) 'Checking must refresh Run availability.'
$ac.Value=589; $dc.Value=1635
Assert-Test ($record.Definition.ACValue -eq 589 -and $record.Definition.DCValue -eq 1635) 'Slider values did not reach selection.'
Assert-Test ($record.Refreshes -eq 1) 'Slider movements rescanned selection membership.'
$state.IsRestoring=$true; $ac.Value=600
Assert-Test ($record.Definition.ACValue -eq 589) 'Restore emitted a selection change.'
$state.IsRestoring=$false; $check.IsChecked=$false
Assert-Test ($null -eq $record.Definition -and $record.Refreshes -eq 2) 'Unchecking did not remove selection and refresh availability.'

# Only harmless child processes exercise cleanup completion/timeout handling.
Add-Type 'namespace WinAPI { public static class DiskCleanupWindow { public static bool AcceptNotification(int id) { return false; } } }'
. ([scriptblock]::Create((Get-TestFunction 'Module/Regions/SystemTweaks/diskcleanup.ps1' 'Wait-CleanupProcessAndDismissNotification')))
function Stop-BaselineProcessTree { param($Process,$Source) $Process.Kill(); $Process.WaitForExit() }
foreach ($scenario in @('Success','Failure','Timeout')) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $PSHOME 'powershell.exe'
    $command=switch ($scenario) { 'Success' {'exit 0'} 'Failure' {'exit 7'} 'Timeout' {'Start-Sleep -Seconds 10'} }
    $start.Arguments='-NoProfile -Command "'+$command+'"'
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $child=[Diagnostics.Process]::Start($start)
    try {
        switch ($scenario) {
            'Success' { Wait-CleanupProcessAndDismissNotification -Process $child -TimeoutSeconds 5; Assert-Test $child.HasExited 'Cleanup wait returned before completion.' }
            'Failure' { Assert-Throws { Wait-CleanupProcessAndDismissNotification -Process $child -TimeoutSeconds 5 } 'exited with code 7' }
            'Timeout' { Assert-Throws { Wait-CleanupProcessAndDismissNotification -Process $child -TimeoutSeconds 1 } 'execution limit'; Assert-Test $child.HasExited 'Timed-out child remained running.' }
        }
    } finally { if (-not $child.HasExited) { $child.Kill() }; $child.Dispose() }
}
. ([scriptblock]::Create((Get-TestFunction 'Module/Regions/Defender/Defender.Hardening.psm1' 'DefenderExploitGuardPolicy')))
function New-Item { param($Path,[switch]$Force,$ErrorAction) }
function Set-RegistryValueSafe { param($Path,$Name,$Type,$Value) }
function Set-ItemProperty { param($LiteralPath,$Name,$Value,$ErrorAction) }
function Set-MpPreference { param($AttackSurfaceReductionRules_Ids,$AttackSurfaceReductionRules_Actions,$ErrorAction) }
function Set-ProcessMitigation { throw 'mitigation failure' }
Assert-Throws { DefenderExploitGuardPolicy } 'mitigation failure'
. ([scriptblock]::Create((Get-TestFunction 'Module/Regions/UIPersonalization/UIPersonalization.Taskbar.psm1' 'BatteryPercentage')))
function Get-CimInstance { param($ClassName,$ErrorAction) }
$script:outcome=$null
BatteryPercentage -Enable
Assert-Test ($script:outcome -eq 'Not applicable') 'Absent battery reported success.'
"PASS: $script:passed September 14 regression assertions (no system settings changed)."
