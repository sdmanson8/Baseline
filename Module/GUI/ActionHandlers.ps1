# Keep this explicit order; later handler groups depend on command captures and controls initialized by earlier groups.
$actionHandlersSplitRoot = Join-Path $PSScriptRoot 'ActionHandlers'
. (Join-Path $actionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
. (Join-Path $actionHandlersSplitRoot 'ButtonHandlers.ps1')
. (Join-Path $actionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
. (Join-Path $actionHandlersSplitRoot 'MenuHandlers.ps1')
