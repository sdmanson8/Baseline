$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Requires Windows PowerShell 5.1.'}
Add-Type -AssemblyName PresentationFramework
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$path=Join-Path $repoRoot 'Module/GUI/GameModeUI.ps1'
$module=New-Module -ArgumentList $path -ScriptBlock {
    param($Path)
    . $Path
    function Get-UxLocalizedString { param($Key,$Fallback) $Fallback }
    function Test-GuiObjectField { param($Object,$FieldName) $Object.Contains($FieldName) }
    function Import-GameModeAdvancedData { @{Function='Example';Label='Example';Description='Example';Category='Test';ApplyValue='Enable'} }
    function Test-GameModeAdvancedProfileDefaultSelection { param($Entry,$ProfileName) $true }
    function Set-ButtonChrome { param($Button,$Variant,[switch]$Compact) }
    function Register-GuiEventHandler { param($Source,$EventName,$Handler) $Source."add_$EventName"($Handler) }
    $Script:NewSafeBrushConverterScript={param($Context) New-Object Windows.Media.BrushConverter}
    $Script:CurrentTheme=@{CardBg='White';CardBorder='Gray';TextSecondary='Black';TextMuted='Gray';TextPrimary='Black'}
    $Script:GuiLayout=@{FontSizeLabel=12;FontSizeSmall=10}
    $Script:GameModeCorePlan=@(); $Script:GameModePlan=@()
    $Script:GameModeAdvancedSelections=@{Example=$true}
    $Script:GameModeAdvancedOptionsExpanded=$false
    $Script:ClearTabContentCacheScript={throw 'Advanced selection must not discard tab cache.'}
    $Script:SummaryUpdates=0; $Script:AvailabilityUpdates=0
    $Script:UpdateRunActionAvailabilityScript={$Script:AvailabilityUpdates++}
    $Script:UpdateCurrentTabContentScript={ $Script:Panel=New-GameModeAdvancedPanel -ProfileName Test }
    $Script:BuildGameModeAdvancedPlanEntriesScript={param($ProfileName) if($Script:GameModeAdvancedSelections.Example){ @{Function='Example';IsAdvanced=$true} } }
    $Script:SyncGameModeContextStateScript={}
    $Script:SyncGameModePlanToGamingControlsScript={}
    $Script:ShowGuiRuntimeFailureScript={param($Context,$Exception) throw $Exception}
    function Check-Expansion {
        $Script:Panel=New-GameModeAdvancedPanel -ProfileName Test -OnSelectionChanged {$Script:SummaryUpdates++}
        $originalPanel=$Script:Panel
        if($Script:Panel.Child.Children[1].Visibility -ne 'Collapsed'){throw 'Initial state wrong'}
        $button=$Script:Panel.Child.Children[0].Children[1]
        $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        foreach($selected in @($false,$true,$false,$true)) {
            $checkbox=$Script:Panel.Child.Children[1].Children[2].Children[0]
            $checkbox.IsChecked=$selected
            if($Script:GameModeAdvancedSelections.Example -ne $selected){throw 'Selection failed'}
            if($Script:Panel.Child.Children[1].Visibility -ne 'Visible'){throw 'Selection collapsed options'}
            if($Script:Panel.Child.Children[0].Children[1].Content -ne 'Hide options'){throw 'Button label lost'}
            if(-not [object]::ReferenceEquals($originalPanel,$Script:Panel)){throw 'Panel was rebuilt'}
            if($selected -and @($Script:GameModePlan).Count -ne 1){throw 'Checked item missing from plan'}
            if(-not $selected -and @($Script:GameModePlan).Count -ne 0){throw 'Unchecked item retained in plan'}
            if(-not $selected -and $checkbox.Content -notmatch 'recommended'){throw 'Recommended label not updated'}
        }
        if($Script:SummaryUpdates -ne 4 -or $Script:AvailabilityUpdates -ne 4){throw 'Summary/availability updates missing'}
        $Script:Panel.Child.Children[0].Children[1].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        & $Script:UpdateCurrentTabContentScript
        if($Script:Panel.Child.Children[1].Visibility -ne 'Collapsed'){throw 'Explicit collapse lost'}
        'PASS: four selection changes preserve controls, expansion, plan, labels, summary updates, and Run availability. Explicit collapse survives a later rebuild.'
    }
    Export-ModuleMember -Function Check-Expansion
}
Import-Module $module
Check-Expansion
