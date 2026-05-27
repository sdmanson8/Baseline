# Dialog helper functions for Baseline UI modals.

$Script:DialogHelpersRoot = $PSScriptRoot
$dialogHelpersSplitRoot = Join-Path $Script:DialogHelpersRoot 'DialogHelpers'
. (Join-Path $dialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
. (Join-Path $dialogHelpersSplitRoot 'ContentDialogs.ps1')
. (Join-Path $Script:DialogHelpersRoot 'PerfTrace.ps1')
Initialize-GuiPerfTrace
. (Join-Path $dialogHelpersSplitRoot 'SettingsDialogs.ps1')
. (Join-Path $dialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
. (Join-Path $dialogHelpersSplitRoot 'RemoteDialogs.ps1')
