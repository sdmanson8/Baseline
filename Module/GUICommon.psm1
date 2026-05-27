using module .\Logging.psm1

<#
    .SYNOPSIS
    Internal GUI helper module for shared WPF chrome, dialogs, and settings I/O.

    .DESCRIPTION
    Provides accessors, layout constants, DPI/chrome setup, popup window
    decoration, themed dialogs (including the execution-summary and
    risk-decision dialogs), and settings/session-state persistence used by
    the Baseline GUI runtime. Function bodies live in Module/GUICommon/*.ps1
    and run in this module's scope.
#>

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase -ErrorAction SilentlyContinue

$Script:SharedBrushConverter = [System.Windows.Media.BrushConverter]::new()
$Script:GuiCommonWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Script:GuiCommonWarningsSyncRoot = [object]::new()
$Script:GuiFontSizeWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Script:GuiFontSizeWarningsSyncRoot = [object]::new()
$Script:GuiPopupThemeWindows = [System.Collections.Generic.List[object]]::new()

$Script:GuiCommonRoot = Join-Path $PSScriptRoot 'GUICommon'

. (Join-Path $Script:GuiCommonRoot 'Accessors.ps1')
. (Join-Path $Script:GuiCommonRoot 'Layout.ps1')
. (Join-Path $Script:GuiCommonRoot 'Utilities.ps1')
. (Join-Path $Script:GuiCommonRoot 'ThemePalette.ps1')
. (Join-Path $Script:GuiCommonRoot 'DpiAwareness.ps1')
. (Join-Path $Script:GuiCommonRoot 'WindowChrome.ps1')
. (Join-Path $Script:GuiCommonRoot 'SharedScrollBars.ps1')
. (Join-Path $Script:GuiCommonRoot 'PopupWindows.ps1')
. (Join-Path $Script:GuiCommonRoot 'Dialogs.ps1')
. (Join-Path $Script:GuiCommonRoot 'ExecutionSummaryDialog.ps1')
. (Join-Path $Script:GuiCommonRoot 'RiskDecisionDialog.ps1')
. (Join-Path $Script:GuiCommonRoot 'SettingsStore.ps1')

Export-ModuleMember -Function @(
	'Test-GuiCommonObjectField'
	'Get-GuiCommonObjectField'
	'Get-GuiLayout'
	'Get-GuiCommonSafeFontSize'
	'Get-GuiBooleanValue'
	'Get-GuiPopupLocalizedString'
	'Repair-GuiThemePalette'
	'Set-GuiWindowChromeTheme'
	'Get-GuiSharedScrollBarStyleXaml'
	'Add-GuiSharedScrollBarResources'
	'Add-GuiPopupWindowChrome'
	'Set-GuiPopupActionButtonStyle'
	'Set-GuiPopupCaptionButtonStyle'
	'New-GuiPopupInfoIcon'
	'Register-GuiPopupThemeWindow'
	'Show-GuiActivatedDialog'
	'Set-GuiPopupWindowProgress'
	'Update-GuiPopupWindowThemes'
	'Start-GuiPopupCommandAsync'
	'ConvertTo-RoundedWindow'
	'Complete-RoundedWindow'
	'Show-GuiCommonThemedDialog'
	'Show-GuiCommonExecutionSummaryDialog'
	'Show-GuiCommonRiskDecisionDialog'
	'New-DialogMetadataPill'
	'New-DialogMetadataPillPanel'
	'New-DialogSummaryCard'
	'New-DialogSummaryCardsPanel'
	'Get-GuiSettingsProfileDirectory'
	'Get-GuiSessionStatePath'
	'Save-GuiSessionStateDocument'
	'Read-GuiSessionStateDocument'
	'Show-GuiSettingsSaveDialog'
	'Show-GuiFileOpenDialog'
	'Show-GuiSettingsOpenDialog'
	'Write-GuiSettingsProfileDocument'
	'Read-GuiSettingsProfileDocument'
	'Get-GuiLastRunFilePath'
	'Get-GuiInterruptedRunFilePath'
	'Initialize-GuiDpiAwareness'
)
