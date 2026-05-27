Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $guiCommonPath = Join-Path $PSScriptRoot '../../Module/GUICommon.psm1'
    $dialogsPath = Join-Path $PSScriptRoot '../../Module/GUICommon/Dialogs.ps1'
    $windowChromePath = Join-Path $PSScriptRoot '../../Module/GUICommon/WindowChrome.ps1'
    $sharedScrollBarsPath = Join-Path $PSScriptRoot '../../Module/GUICommon/SharedScrollBars.ps1'
    $dpiAwarenessPath = Join-Path $PSScriptRoot '../../Module/GUICommon/DpiAwareness.ps1'
    $popupWindowsPath = Join-Path $PSScriptRoot '../../Module/GUICommon/PopupWindows.ps1'
    $themePalettePath = Join-Path $PSScriptRoot '../../Module/GUICommon/ThemePalette.ps1'
    $executionSummaryDialogCommonPath = Join-Path $PSScriptRoot '../../Module/GUICommon/ExecutionSummaryDialog.ps1'
    $utilitiesPath = Join-Path $PSScriptRoot '../../Module/GUICommon/Utilities.ps1'
    $styleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $dialogHelpersPath = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1'
    $dialogHelpersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers'
    $executionSummaryDialogPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionSummaryDialog.ps1'
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $applyThemePath = Join-Path $PSScriptRoot '../../Module/GUI/ApplyTheme.ps1'
    $mainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $windowSetupPath = Join-Path $PSScriptRoot '../../Module/GUI/WindowSetup.ps1'
    $environmentHelpersPath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Environment.Helpers.ps1'
    $darkThemePath = Join-Path $PSScriptRoot '../../Module/GUI/Themes/Dark.xaml'
    $lightThemePath = Join-Path $PSScriptRoot '../../Module/GUI/Themes/Light.xaml'

    $guiCommonContent = @(
        Get-BaselineTestSourceText -Path $guiCommonPath
        Get-BaselineTestSourceText -Path $dialogsPath
        Get-BaselineTestSourceText -Path $utilitiesPath
        Get-BaselineTestSourceText -Path $windowChromePath
        Get-BaselineTestSourceText -Path $sharedScrollBarsPath
        Get-BaselineTestSourceText -Path $dpiAwarenessPath
        Get-BaselineTestSourceText -Path $popupWindowsPath
        Get-BaselineTestSourceText -Path $themePalettePath
    ) -join "`n"
    $styleManagementContent = Get-BaselineTestSourceText -Path $styleManagementPath
    $dialogHelpersContent = Get-BaselineTestSourceText -Path @(
        $dialogHelpersPath
        (Join-Path $dialogHelpersSplitRoot 'DialogThemeHelpers.ps1')
        (Join-Path $dialogHelpersSplitRoot 'SettingsDialogs.ps1')
        (Join-Path $dialogHelpersSplitRoot 'RemoteDialogs.ps1')
        (Join-Path $dialogHelpersSplitRoot 'ContentDialogs.ps1')
        (Join-Path $dialogHelpersSplitRoot 'AuditOperatorDialogs.ps1')
    )
    $executionSummaryDialogContent = Get-BaselineTestSourceText -Path $executionSummaryDialogPath
    $executionSummaryDialogCommonContent = Get-BaselineTestSourceText -Path $executionSummaryDialogCommonPath
    $dpiAwarenessContent = Get-BaselineTestSourceText -Path $dpiAwarenessPath
    $guiContent = (Get-BaselineTestSourceText -Path $guiPath) + "`n" + (Get-BaselineTestSourceText -Path $applyThemePath)
    $mainWindowContent = Get-BaselineTestSourceText -Path $mainWindowPath
    $windowSetupContent = Get-BaselineTestSourceText -Path $windowSetupPath
    $environmentHelpersContent = Get-BaselineTestSourceText -Path $environmentHelpersPath
    $darkThemeContent = Get-BaselineTestSourceText -Path $darkThemePath
    $lightThemeContent = Get-BaselineTestSourceText -Path $lightThemePath
}

Describe 'GUI window chrome theming' {
    It 'defines and exports a shared window chrome theming helper' {
        $guiCommonContent | Should -Match 'function Set-GuiWindowChromeTheme'
        $guiCommonContent | Should -Match 'DwmSetWindowAttribute'
        $guiCommonContent | Should -Match "'Set-GuiWindowChromeTheme'"
    }

    It 'defines and exports shared theme palette repair for action-host picker runspaces' {
        $guiCommonContent | Should -Match 'function Repair-GuiThemePalette'
        $guiCommonContent | Should -Match "'Repair-GuiThemePalette'"
        $guiCommonContent | Should -Match 'function Write-GuiCommonThemeRepairWarning'
    }

    It 'defines and exports a shared popup chrome helper with minimize and close controls' {
        $guiCommonContent | Should -Match 'function Add-GuiPopupWindowChrome'
        $guiCommonContent | Should -Match "'Add-GuiPopupWindowChrome'"
        $guiCommonContent | Should -Match 'Minimize'
        $guiCommonContent | Should -Match 'Close'
        $guiCommonContent | Should -Match '\$RootBorder\.Child = \$null'
    }

    It 'keeps shared popup caption buttons visible without main GUI style helpers' {
        $guiCommonContent | Should -Match '\$minimizeButton\.Foreground = \$bc\.ConvertFromString\(\$titleBarTextColor\)'
        $guiCommonContent | Should -Match '\$closeButton\.Foreground = \$bc\.ConvertFromString\(\$titleBarTextColor\)'
        $guiCommonContent | Should -Match '\$minimizeButton\.Opacity = 1\.0'
        $guiCommonContent | Should -Match '\$closeButton\.Opacity = 1\.0'
        $styleManagementContent | Should -Match 'ContentSourceProperty, ''Content'''
        $guiCommonContent | Should -Match 'SetPopupMinimizeButtonFallbackBrushes'
        $guiCommonContent | Should -Match 'SetPopupCloseButtonFallbackBrushes'
    }

    It 'defines shared two-axis scrollbar resources for popup and dialog surfaces' {
        $guiCommonContent | Should -Match 'function Get-GuiSharedScrollBarStyleXaml'
        $guiCommonContent | Should -Match 'function Add-GuiSharedScrollBarResources'
        $guiCommonContent | Should -Match "'Get-GuiSharedScrollBarStyleXaml'"
        $guiCommonContent | Should -Match "'Add-GuiSharedScrollBarResources'"
        $guiCommonContent | Should -Match 'Command="ScrollBar\.PageUpCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.PageDownCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.PageLeftCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.PageRightCommand"'
        $guiCommonContent | Should -Match 'BaselineScrollBarArrowButtonStyle'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.LineUpCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.LineDownCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.LineLeftCommand"'
        $guiCommonContent | Should -Match 'Command="ScrollBar\.LineRightCommand"'
        $guiCommonContent | Should -Match '<RowDefinition Height="16"/>'
        $guiCommonContent | Should -Match '<ColumnDefinition Width="16"/>'
        $guiCommonContent | Should -Match 'Add-GuiSharedScrollBarResources -Target \$Window'
    }

    It 'keeps main window scrollbars on the same subtle arrow template' {
        $mainWindowContent | Should -Match 'BaselineScrollBarArrowButtonStyle'
        $mainWindowContent | Should -Match 'Command="ScrollBar\.LineUpCommand"'
        $mainWindowContent | Should -Match 'Command="ScrollBar\.LineDownCommand"'
        $mainWindowContent | Should -Match 'Command="ScrollBar\.LineLeftCommand"'
        $mainWindowContent | Should -Match 'Command="ScrollBar\.LineRightCommand"'
        $mainWindowContent | Should -Match '<RowDefinition Height="16"/>'
        $mainWindowContent | Should -Match '<ColumnDefinition Width="16"/>'
    }

    It 'normalizes dark mode values before shared chrome theming runs' {
        $guiCommonContent | Should -Match 'function Get-GuiBooleanValue'
        $guiCommonContent | Should -Match 'Get-GuiBooleanValue -Value \$UseDarkMode -Default \$true -Context ''Set-GuiWindowChromeTheme'''
        $guiCommonContent | Should -Match 'Get-GuiBooleanValue -Value \$UseDarkMode -Default \$true -Context ''Add-GuiPopupWindowChrome'''
    }

    It 'defines the miniature popup progress helpers' {
        $guiCommonContent | Should -Match 'function Set-GuiPopupWindowProgress'
        $guiCommonContent | Should -Match 'function Set-GuiPopupWindowTheme'
        $guiCommonContent | Should -Match 'function Update-GuiPopupWindowThemes'
        $guiCommonContent | Should -Match 'function Start-GuiPopupCommandAsync'
        $guiCommonContent | Should -Match 'Import-Module -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -Name \$path'
        $guiCommonContent | Should -Match 'Import-Module -Global -Force -DisableNameChecking -WarningAction SilentlyContinue -Name \$PopupModulePath'
        $guiCommonContent | Should -Match 'GuiPopupProgressHost'
        $guiCommonContent | Should -Match 'GuiPopupProgressBar'
        $guiCommonContent | Should -Match 'RowDefinitions\.Insert'
        $guiCommonContent | Should -Match 'Grid]::SetRow\(\$progressHost, \$insertRowIndex\)'
    }

    It 'allows popup windows to register custom theme repaint callbacks' {
        $guiCommonContent | Should -Match 'function Register-GuiPopupThemeWindow'
        $guiCommonContent | Should -Match "'Register-GuiPopupThemeWindow'"
        $guiCommonContent | Should -Match 'GuiPopupThemeCallback'
        $guiCommonContent | Should -Match 'Register-GuiPopupThemeWindow -Window \$Window'
    }

    It 'threads the active dark mode state through shared dialog wrappers' {
        $styleManagementContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
        $dialogHelpersContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
        $executionSummaryDialogContent | Should -Match '-UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'applies native window chrome theming when the main theme changes' {
        $guiContent | Should -Match 'GUICommon\\Set-GuiWindowChromeTheme -Window \$Form -UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'keeps custom windows visually rounded by not painting square host backgrounds' {
        $mainWindowContent | Should -Match 'Background="Transparent"'
        $mainWindowContent | Should -Match 'BorderBrush="Transparent"'
        $mainWindowContent | Should -Match '<Border Name="RootBorder"[^>]*CornerRadius="8"[^>]*ClipToBounds="True"'
        $mainWindowContent | Should -Match '<Grid Background="Transparent" Margin="0">'
        $mainWindowContent | Should -Match '<Grid Grid\.Row="1" Background="Transparent" Margin="0">'
        $mainWindowContent | Should -Match '<Border Name="BottomBorder"[^>]*CornerRadius="0,0,8,8"'
        $mainWindowContent | Should -Match 'Name="SubmenuBorder"[^>]*CornerRadius="8"'
        $environmentHelpersContent | Should -Match 'Background="Transparent"'
        $environmentHelpersContent | Should -Match 'BorderBrush="Transparent"'
        $environmentHelpersContent | Should -Match '<Border Name="RootBorder"[^>]*CornerRadius="8"[^>]*ClipToBounds="True"'
        $environmentHelpersContent | Should -Match '<Grid Background="Transparent" Margin="0"'
        $guiCommonContent | Should -Match '\$Window\.Background = \[System\.Windows\.Media\.Brushes\]::Transparent'
        $guiCommonContent | Should -Match '\$RootBorder\.CornerRadius = \[System\.Windows\.CornerRadius\]::new\(8\)'
        $guiCommonContent | Should -Match '\$RootBorder\.ClipToBounds = \$true'
        $guiCommonContent | Should -Match '\$dlgRoundedBorder\.ClipToBounds = \$true'
        $guiCommonContent | Should -Match '\$btnBorder\.CornerRadius = \[System\.Windows\.CornerRadius\]::new\(0, 0, 8, 8\)'
    }

    It 'maximizes the main window to the monitor work area instead of native fullscreen bounds' {
        $windowSetupContent | Should -Match 'function Get-GuiMainWindowWorkArea'
        $windowSetupContent | Should -Match '\[System\.Windows\.Forms\.Screen\]::FromHandle\(\$windowHandle\)'
        $windowSetupContent | Should -Match 'TransformFromDevice'
        $windowSetupContent | Should -Match 'function Limit-GuiMainWindowBoundsToWorkArea'
        $windowSetupContent | Should -Match '\$workArea = Get-GuiMainWindowWorkArea -Window \$Form'
        $windowSetupContent | Should -Match 'Limit-GuiMainWindowBoundsToWorkArea -Window \$Form -Bounds \$placementBounds'
        $windowSetupContent | Should -Match '\$Window\.MinWidth = \[Math\]::Min'
        $windowSetupContent | Should -Match 'function Test-GuiMainWindowBoundsMatchWorkArea'
        $windowSetupContent | Should -Match 'Test-GuiMainWindowBoundsMatchWorkArea -Window \$Window -Bounds \$restoreBounds'
        $windowSetupContent | Should -Match 'Test-GuiMainWindowBoundsMatchWorkArea -Window \$Window -Bounds \$rect'
        $windowSetupContent | Should -Match 'Test-GuiMainWindowBoundsMatchWorkArea -Window \$Form -Bounds \$placementBounds'
        $windowSetupContent | Should -Match 'Test-GuiMainWindowBoundsMatchWorkArea -Window \$Form -Bounds \$restoredNormalBounds'
        $windowSetupContent | Should -Match 'function Set-GuiMainWindowWorkAreaMaximized'
        $windowSetupContent | Should -Match '\$Script:MainWindowDefaultRestoreBounds = \$null'
        $windowSetupContent | Should -Match '\$Script:MainWindowDefaultRestoreBounds = New-GuiMainWindowBoundsSnapshot'
        $windowSetupContent | Should -Match '\$Script:MainWindowPendingWorkAreaMaximize = \$true'
        $windowSetupContent | Should -Match '\$Form\.Add_SourceInitialized\(\$applyPendingMainWindowWorkAreaMaximize\)'
        $windowSetupContent | Should -Match '\(\(-not \$PreserveRestoreBounds\) -or \(-not \(Test-GuiMainWindowBoundsSnapshot -Bounds \$Script:MainWindowRestoreBounds\)\)\)'
        $windowSetupContent | Should -Match '\$restoreBounds = if \(Test-GuiMainWindowBoundsSnapshot -Bounds \$Script:MainWindowRestoreBounds\)'
        $windowSetupContent | Should -Match '\$Script:MainWindowDefaultRestoreBounds'
        $windowSetupContent | Should -Match '\$Script:MainWindowRestoreBounds = Get-GuiMainWindowBoundsSnapshot -Window \$Window'
        $windowSetupContent | Should -Match 'function Save-GuiMainWindowPlacementForRestore'
        $windowSetupContent | Should -Match 'Save-BaselineWindowPlacement[\s\S]*-Maximized \$Maximized'
        $windowSetupContent | Should -Match 'Save-GuiMainWindowPlacementForRestore -Window \$Window -Maximized \(\[bool\]\$Script:MainWindowWorkAreaMaximized\) -Source ''WindowSetup\.SaveWindowPlacement\.StateChange'''
        $windowSetupContent | Should -Match 'Save-GuiMainWindowPlacementForRestore -Window \$Form -Maximized \(Test-GuiMainWindowWorkAreaMaximized -Window \$Form\) -Source ''WindowSetup\.SaveWindowPlacement'''
        $windowSetupContent | Should -Match 'if \(-not \$rect\)[\s\S]*\$rect = Get-GuiMainWindowBoundsSnapshot -Window \$Window'
        $windowSetupContent | Should -Match 'Set-GuiMainWindowChromeMaximizedState[\s\S]*Thickness\]::new\(0\)'
        $windowSetupContent | Should -Not -Match '\$Form\.WindowState\s*=\s*\[System\.Windows\.WindowState\]::Maximized'
        $windowSetupContent | Should -Not -Match 'Thickness\]::new\(7\)'
    }

    It 'keeps header minimum width constrained to the active monitor work area' {
        $styleManagementContent | Should -Match 'Get-GuiMainWindowWorkArea -Window \$Form'
        $styleManagementContent | Should -Match '\[double\]\$Form\.MinWidth -gt \$workAreaWidth'
        $styleManagementContent | Should -Match '\$Form\.Width = \$workAreaWidth'
        $styleManagementContent | Should -Match '\$Form\.Left = \$maxLeft'
    }

    It 'restores the startup splash from explicit normal bounds when unmaximized' {
        $environmentHelpersContent | Should -Match '\$splashWindowChromeState = @\{'
        $environmentHelpersContent | Should -Match '\$splashDefaultBounds = \[pscustomobject\]@\{'
        $environmentHelpersContent | Should -Match '\$testSplashStartupBoundsMatchWorkArea = \{'
        $environmentHelpersContent | Should -Match '\$placementBounds = \$splashDefaultBounds'
        $environmentHelpersContent | Should -Match 'NormalBounds = \$null'
        $environmentHelpersContent | Should -Match '\$captureSplashNormalBoundsAction = \{'
        $environmentHelpersContent | Should -Match '\$restoreSplashNormalBoundsAction = \{'
        $environmentHelpersContent | Should -Match '\$getSplashWindowWorkAreaBoundsAction = \{'
        $environmentHelpersContent | Should -Match '\$setSplashWindowMaximizedStateAction = \{'
        $environmentHelpersContent | Should -Match '& \$setSplashWindowMaximizedStateAction -Maximized \(-not \[bool\]\$syncHash\[''WindowMaximized''\]\)'
        $environmentHelpersContent | Should -Match '& \$setSplashWindowMaximizedStateAction -Maximized \$false'
        $environmentHelpersContent | Should -Match '& \$setSplashWindowMaximizedStateAction -Maximized \$true'
        $environmentHelpersContent | Should -Match '\$workAreaBounds = & \$getSplashWindowWorkAreaBoundsAction'
        $environmentHelpersContent | Should -Not -Match '\$splash\.WindowState = \[System\.Windows\.WindowState\]::Maximized'
        $environmentHelpersContent | Should -Not -Match 'Thickness\]::new\(7\)'
        $environmentHelpersContent | Should -Match '\$splash\.Add_LocationChanged\(\$rememberSplashNormalBoundsAction\)'
        $environmentHelpersContent | Should -Match '\$splash\.Add_SizeChanged\(\$rememberSplashNormalBoundsAction\)'
        $environmentHelpersContent | Should -Match '\$splashWindowChromeState\[''NormalBounds''\] = \[pscustomobject\]@\{'
    }

    It 'rounds tooltip hover boxes in both GUI themes' {
        $darkThemeContent | Should -Match '<ControlTemplate TargetType="\{x:Type ToolTip\}">'
        $darkThemeContent | Should -Match 'CornerRadius="8"'
        $lightThemeContent | Should -Match '<ControlTemplate TargetType="\{x:Type ToolTip\}">'
        $lightThemeContent | Should -Match 'CornerRadius="8"'
    }

    It 'keeps Help in the Help menu instead of the header action strip' {
        $mainWindowContent | Should -Match '<MenuItem Name="MenuHelp"'
        $mainWindowContent | Should -Match '<MenuItem Name="MenuHelpHelp" Header="Help"/>'
        $windowSetupContent | Should -Match '\$MenuHelpHelp\s+=\s+\$Form\.FindName\("MenuHelpHelp"\)'
        $windowSetupContent | Should -Match '\$Script:MenuHelpHelp\s+=\s+\$MenuHelpHelp'
        $mainWindowContent | Should -Match 'Name="BtnHelp"[\s\S]*Visibility="Collapsed"[\s\S]*IsTabStop="False"'
    }

    It 'renders Help dialog bullets with a normal text font' {
        $dialogHelpersContent | Should -Match 'Title="\$helpDialogTitle"[\s\S]*FontFamily="Segoe UI"'
        $dialogHelpersContent | Should -Match '\$bullet\.Text = \[char\]0x2022'
        $dialogHelpersContent | Should -Match '\$bullet\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)'
    }

    It 'dot-sources the language catalog and removes the close-time save prompt' {
        $guiContent | Should -Match 'LanguageCatalog\.ps1'
        $guiContent | Should -Not -Match 'GuiSaveSessionTitle'
        $guiContent | Should -Not -Match 'GuiSaveSessionMessage'
        $guiContent | Should -Not -Match 'GuiSaveSessionSave'
        $guiContent | Should -Not -Match 'GuiSaveSessionDiscard'
    }

    It 'restyles custom caption buttons from the active theme' {
        $styleManagementContent | Should -Match 'function Set-WindowCaptionButtonStyle'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnMinimize'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnMaximize'
        $guiContent | Should -Match 'Set-WindowCaptionButtonStyle -Button \$BtnClose -Variant ''Close'''
        $guiCommonContent | Should -Match 'function Set-GuiPopupCaptionButtonStyle'
        $guiCommonContent | Should -Match 'Set-GuiPopupCaptionButtonStyle -Button \$dlgCloseBtn -Variant ''Close'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''Dialogs\.ShowThemedDialog\.SetCloseButtonStyle'''
    }

    It 'routes header toggle and menu sync fallback failures through Write-SwallowedException' {
        $styleManagementContent | Should -Match "StyleManagement\.Set-HeaderToggleControlsStyle\.ApplyChrome"
        $styleManagementContent | Should -Match "StyleManagement\.Set-HeaderToggleStyle\.LoadTemplate"
        $styleManagementContent | Should -Match "StyleManagement\.Update-HeaderModeStateText\.SyncMenuViewTheme"
        $styleManagementContent | Should -Match "StyleManagement\.Update-HeaderModeStateText\.UpdateMainFormTitle"
        $styleManagementContent | Should -Match "StyleManagement\.Update-GuiMenuBarTheme\.UpdateMenuBarBorder"
    }

    It 'does not style the removed Safe or Expert header mode toggle' {
        $styleManagementContent | Should -Not -Match '\$modeToggleLabel'
        $styleManagementContent | Should -Not -Match '\$ChkSafeMode'
        $styleManagementContent | Should -Not -Match 'TxtSafeModeLabel|TxtExpertModeLabel'
        $styleManagementContent | Should -Not -Match 'AutomationProperties\]::SetName\(\$ChkSafeMode'
    }

    It 'routes style template cleanup failures through Write-SwallowedException' {
        $styleManagementContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyleManagement\.Set-HeaderToggleStyle\.TemplateReaderDispose'''
        $styleManagementContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyleManagement\.Set-ChoiceComboStyle\.ApplyTemplate'''
    }

    It 'routes style theme logger failures through Write-SwallowedException' {
        $styleManagementContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyleManagement\.Update-GuiMenuBarTheme\.LogWarning'''
        $styleManagementContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''StyleManagement\.Update-GuiScrollBarTheme\.LogWarning'''
    }

    It 'routes popup window cleanup failures through Write-SwallowedException' {
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Start-GuiPopupCommandAsync\.DisposePowerShell'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Start-GuiPopupCommandAsync\.DisposeRunspace'''
    }

    It 'routes popup window styling and progress cleanup failures through Write-SwallowedException' {
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Add-GuiPopupWindowChrome\.SetMinimizeButtonStyle'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Add-GuiPopupWindowChrome\.SetCloseButtonStyle'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Add-GuiPopupWindowChrome\.ResolveThemeColor'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetWindowBackground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetWindowForeground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.ResolveThemeColor'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetRootBorderBackground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetRootBorderBorderBrush'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetRootBorderThickness'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetTitleBarBackground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetTitleBarBorderBrush'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetTitleBarBorderThickness'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetTitleTextForeground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetPanelContainerBackground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetProgressHostBackground'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetProgressBarBrushes'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetPopupMinimizeButtonStyle'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.SetPopupCloseButtonStyle'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Set-GuiPopupWindowTheme\.ApplyChrome'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Start-GuiPopupCommandAsync\.InitializeOperationState'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''PopupWindows\.Start-GuiPopupCommandAsync\.CompleteOperationState'''
    }

    It 'routes window chrome cleanup failures through Write-SwallowedException' {
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Restore-WindowSystemMenu\.ApplySystemMenu'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Restore-WindowSystemMenu\.BuildContextMenu'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Invoke-GuiWindowChromeThemeUpdate\.ApplyRoundedCorners'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Invoke-GuiWindowChromeThemeUpdate\.RepaintChrome'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Set-GuiWindowChromeTheme\.SetUseDarkModeProperty'''
        $guiCommonContent | Should -Match 'Write-SwallowedException -ErrorRecord \$_ -Source ''WindowChrome\.Set-GuiWindowChromeTheme\.SetSourceInitializedHandlerProperty'''
    }

    It 'tries supported immersive dark-mode attributes before logging a chrome warning' {
        $guiCommonContent | Should -Match '\$immersiveDarkModeAttributes = \[System\.Collections\.Generic\.List\[int\]\]::new\(\)'
        $guiCommonContent | Should -Match '\$immersiveDarkModeAttributes\.Add\(20\)'
        $guiCommonContent | Should -Match '\$immersiveDarkModeAttributes\.Add\(19\)'
        $guiCommonContent | Should -Match 'foreach \(\$immersiveDarkModeAttribute in \$immersiveDarkModeAttributes\)'
        $guiCommonContent | Should -Match 'if \(\$result -eq 0\)'
        $guiCommonContent | Should -Match 'if \(-not \$chromeThemeApplied\)'
    }

    It 'routes Dpi awareness bootstrap failures through Write-SwallowedException' {
        $dpiAwarenessContent.Contains('Write-SwallowedException -ErrorRecord $_ -Source ''DpiAwareness.Initialize-GuiDpiAwareness.Enable''') | Should -BeTrue
    }

    It 'routes execution summary layout-init failures through Write-SwallowedException' {
        $executionSummaryDialogCommonContent | Should -Match 'Write-SwallowedException[\s\S]*ExecutionSummaryDialog\.Show-GuiCommonExecutionSummaryDialog\.ListStackBeginInit'
        $executionSummaryDialogCommonContent | Should -Match 'Write-SwallowedException[\s\S]*ExecutionSummaryDialog\.Show-GuiCommonExecutionSummaryDialog\.CapturedListStackBeginInit'
        $executionSummaryDialogCommonContent | Should -Match 'Write-SwallowedException[\s\S]*ExecutionSummaryDialog\.Show-GuiCommonExecutionSummaryDialog\.CapturedListStackEndInit'
        $executionSummaryDialogCommonContent | Should -Match 'Write-SwallowedException[\s\S]*ExecutionSummaryDialog\.Show-GuiCommonExecutionSummaryDialog\.ListStackEndInit'
    }

    It 'applies native window chrome theming to custom XAML dialogs' {
        $dialogHelpersContent | Should -Match 'GUICommon\\Set-GuiWindowChromeTheme -Window \$dlg -UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'uses the shared popup chrome helper in the borderless picker windows' {
        $uwpAppsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1')
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $uwpAppsContent | Should -Match '(?m)^using module \.\.\\GUICommon\.psm1'
        $systemFeaturesContent | Should -Match '(?m)^using module \.\.\\\.\.\\GUICommon\.psm1'
        $telemetryContent | Should -Match '(?m)^using module \.\.\\\.\.\\GUICommon\.psm1'
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title \$uwpAppsTitle -Theme \$currentTheme -UseDarkMode \$isDarkMode')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title (?:\$windowsCapabilitiesTitle|\$windowsFeaturesTitle) -Theme \$Theme -UseDarkMode \$UseDarkMode')).Count | Should -Be 2
        ([regex]::Matches($telemetryContent, 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title \$scheduledTasksTitle -Theme \$Theme -UseDarkMode \$UseDarkMode')).Count | Should -Be 1
    }

    It 'uses standard per-row info glyphs in bulk picker windows' {
        $uwpAppsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1')
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $guiCommonContent | Should -Match 'function New-GuiPopupInfoIcon'
        $guiCommonContent | Should -Match "'New-GuiPopupInfoIcon'"
        $guiCommonContent | Should -Match '\$icon\.Text = \[char\]0x24D8'
        $systemFeaturesContent | Should -Not -Match '\$IconBlock'
        $telemetryContent | Should -Not -Match '\$IconBlock'
        $uwpAppsContent | Should -Not -Match '\$IconBlock'
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\New-GuiPopupInfoIcon')).Count | Should -Be 2
        ([regex]::Matches($telemetryContent, 'GUICommon\\New-GuiPopupInfoIcon')).Count | Should -Be 1
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\New-GuiPopupInfoIcon')).Count | Should -Be 2
    }

    It 'keeps Scheduled Tasks picker text and command button on normal UI fonts' {
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $telemetryContent | Should -Not -Match 'FontFamily="FluentSystemIcons" FontSize="12" ShowInTaskbar="True"'
        $telemetryContent | Should -Match 'FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"'
        $telemetryContent | Should -Match 'CheckBox Name="CheckBoxSelectAll"'
        $telemetryContent | Should -Match '\$TextBlock\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)'
        $telemetryContent | Should -Match '\$Button\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)'
        $telemetryContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiSelectAll'' -Fallback ''Select All'''
        $telemetryContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceEnable'' -Fallback ''Enable'''
        $telemetryContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceDisable'' -Fallback ''Disable'''
        $telemetryContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''Tweak_ScheduledTasks'' -Fallback ''Diagnostics Tracking Tasks'''
        $telemetryContent | Should -Match 'GUICommon\\Set-GuiPopupActionButtonStyle -Button \$Button -Theme \$Theme -UseDarkMode \$UseDarkMode'
        $telemetryContent | Should -Match '\$CheckBoxSelectAll\.Add_Click\(\{Invoke-TelemetryServiceSelectAllClick\}\)'
        $telemetryContent | Should -Match '\$Form\.Title = \$scheduledTasksTitle'
        $telemetryContent | Should -Match 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title \$scheduledTasksTitle -Theme \$Theme -UseDarkMode \$UseDarkMode'
        $guiCommonContent | Should -Match 'function Set-GuiPopupActionButtonStyle'
    }

    It 'resolves the Scheduled Tasks picker theme from shared GUI state and registers repaint callbacks' {
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $telemetryContent | Should -Match 'function Resolve-ScheduledTasksPickerUseDarkMode'
        $telemetryContent | Should -Match 'Variable:\\Global:BaselineCurrentTheme'
        $telemetryContent | Should -Match 'Variable:\\Global:BaselineCurrentThemeName'
        $telemetryContent | Should -Match 'Variable:\\Global:BaselineUseDarkMode'
        $telemetryContent | Should -Match '\$env:BASELINE_THEME_NAME'
        $telemetryContent | Should -Match 'function Set-ScheduledTasksPickerSurface'
        $telemetryContent | Should -Match 'function Set-ScheduledTasksPickerElementTheme'
        $telemetryContent | Should -Match 'GUICommon\\Register-GuiPopupThemeWindow -Window \$Form -ThemeCallback \$scheduledTasksThemeCallback'
    }

    It 'keeps UWP Apps picker labels and command buttons on the shared popup paths' {
        $uwpAppsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1')

        ([regex]::Matches($uwpAppsContent, '\$Button(Install|Uninstall)\.FontFamily\s+=\s+\[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, '\$Button(Install|Uninstall)\.FontSize\s+=\s+12')).Count | Should -Be 2
        $uwpAppsContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''Tweak_UWPApps'' -Fallback ''UWP Apps \(Bulk\)'''
        $uwpAppsContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceInstall'' -Fallback ''Install'''
        $uwpAppsContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceUninstall'' -Fallback ''Uninstall'''
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Get-GuiPopupLocalizedString -Key ''UninstallUWPForAll'' -Fallback ''For all users''')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiSelectAll'' -Fallback ''Select All''')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Set-GuiPopupActionButtonStyle -Button \$Button(Install|Uninstall) -Theme \$currentTheme -UseDarkMode \$isDarkMode')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Set-GuiPopupActionButtonStyle -Button \$Button(Install|Uninstall) -Theme \$Theme -UseDarkMode \$UseDarkMode')).Count | Should -Be 2
    }

    It 'resolves the UWP Apps picker theme from shared GUI state and registers repaint callbacks' {
        $uwpAppsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1')

        $uwpAppsContent | Should -Match 'function Resolve-UWPAppsPickerUseDarkMode'
        $uwpAppsContent | Should -Match 'function Get-UWPAppsPickerTheme'
        $uwpAppsContent | Should -Match 'Variable:\\Global:BaselineCurrentThemeName'
        $uwpAppsContent | Should -Match 'Variable:\\Global:BaselineUseDarkMode'
        $uwpAppsContent | Should -Match 'Variable:\\Global:BaselineCurrentTheme'
        $uwpAppsContent | Should -Match '\$env:BASELINE_USE_DARK_MODE'
        $uwpAppsContent | Should -Match '\$env:BASELINE_THEME_NAME'
        ([regex]::Matches($uwpAppsContent, '\$currentTheme = Get-UWPAppsPickerTheme')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, 'GUICommon\\Register-GuiPopupThemeWindow -Window \$Form -ThemeCallback \$uwpApps(Install|Uninstall)ThemeCallback')).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, '& \$uwpApps(Install|Uninstall)ThemeCallback -Window \$Form -Theme \$currentTheme -UseDarkMode \$isDarkMode')).Count | Should -Be 2
    }

    It 'keeps Windows Features and Capabilities picker text and command buttons on normal UI fonts' {
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')

        $systemFeaturesContent | Should -Not -Match 'FontFamily="FluentSystemIcons" FontSize="12" ShowInTaskbar="True"'
        ([regex]::Matches($systemFeaturesContent, 'FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, 'CheckBox Name="CheckBoxSelectAll"')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, '\$TextBlock\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)')).Count | Should -BeGreaterOrEqual 2
        ([regex]::Matches($systemFeaturesContent, '\$Button\.FontFamily = \[System\.Windows\.Media\.FontFamily\]::new\(''Segoe UI''\)')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiSelectAll'' -Fallback ''Select All''')).Count | Should -Be 2
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceInstall'' -Fallback ''Install'''
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceUninstall'' -Fallback ''Uninstall'''
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceEnable'' -Fallback ''Enable'''
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''GuiChoiceDisable'' -Fallback ''Disable'''
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''Tweak_WindowsCapabilities'' -Fallback ''Windows Capabilities'''
        $systemFeaturesContent | Should -Match 'GUICommon\\Get-GuiPopupLocalizedString -Key ''Tweak_WindowsFeatures'' -Fallback ''Windows Features'''
        $systemFeaturesContent | Should -Match 'WindowsCapabilities\.SetPopupActionButtonStyle'
        $systemFeaturesContent | Should -Match 'WindowsFeatures\.SetPopupActionButtonStyle'
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\Set-GuiPopupActionButtonStyle -Button \$Button -Theme \$Theme -UseDarkMode \$UseDarkMode')).Count | Should -Be 4
        $systemFeaturesContent | Should -Match '\$CheckBoxSelectAll\.Add_Click\(\{Invoke-CapabilitySelectAllClick\}\)'
        $systemFeaturesContent | Should -Match '\$CheckBoxSelectAll\.Add_Click\(\{Invoke-FeatureSelectAllClick\}\)'
        $systemFeaturesContent | Should -Match '\$Form\.Title = \$windowsCapabilitiesTitle'
        $systemFeaturesContent | Should -Match '\$Form\.Title = \$windowsFeaturesTitle'
        $systemFeaturesContent | Should -Match 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title \$windowsCapabilitiesTitle -Theme \$Theme -UseDarkMode \$UseDarkMode'
        $systemFeaturesContent | Should -Match 'GUICommon\\Add-GuiPopupWindowChrome -Window \$Form -RootBorder \$RootBorder -PanelContainer \$PanelContainer -Title \$windowsFeaturesTitle -Theme \$Theme -UseDarkMode \$UseDarkMode'
    }

    It 'resolves Windows Features and Capabilities picker theme from shared GUI state' {
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')

        $systemFeaturesContent | Should -Match 'function Resolve-SystemPickerUseDarkMode'
        $systemFeaturesContent | Should -Match 'function Get-SystemPickerTheme'
        $systemFeaturesContent | Should -Match 'function Get-SystemPickerResolvedThemeColor'
        $systemFeaturesContent | Should -Match 'Variable:\\Global:BaselineCurrentThemeName'
        $systemFeaturesContent | Should -Match 'Variable:\\Global:BaselineUseDarkMode'
        $systemFeaturesContent | Should -Match 'Variable:\\Global:BaselineCurrentTheme'
        $systemFeaturesContent | Should -Match '\$env:BASELINE_USE_DARK_MODE'
        $systemFeaturesContent | Should -Match '\$env:BASELINE_THEME_NAME'
        ([regex]::Matches($systemFeaturesContent, '\$Theme = Get-SystemPickerTheme')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, '\$UseDarkMode = Resolve-SystemPickerUseDarkMode')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, 'Get-SystemPickerResolvedThemeColor -Theme \$Theme -ColorName ''WindowBg''')).Count | Should -Be 2
        ([regex]::Matches($systemFeaturesContent, 'Get-SystemPickerResolvedThemeColor -Theme \$Theme -ColorName ''BorderColor''')).Count | Should -Be 2
        $systemFeaturesContent | Should -Match '\[void\]\$BrushConverter\.ConvertFromString\(\[string\]\$candidate\)'
    }

    It 'uses the popup secondary button palette for the default action surface' {
        $guiCommonContent | Should -Match 'ColorName ''SecondaryButtonBg'''
        $guiCommonContent | Should -Match 'ColorName ''SecondaryButtonFg'''
    }

    It 'uses the shared popup localized-string helper for picker captions and button text' {
        $guiCommonContent | Should -Match 'function Get-GuiPopupLocalizedString'
        $guiCommonContent | Should -Match '''Get-GuiPopupLocalizedString'''
        $guiCommonContent | Should -Match 'Get-GuiPopupLocalizedString -Key ''GuiCloseButton'' -Fallback ''Close'''
    }

    It 'repairs the Windows feature picker theme before applying chrome' {
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')
        $uwpAppsContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/UWPApps.psm1')
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $systemFeaturesContent | Should -Not -Match '\$UseDarkMode = \$false'
        $systemFeaturesContent | Should -Not -Match "Get-Command -Name 'Repair-GuiThemePalette'"
        $uwpAppsContent | Should -Not -Match "Get-Command -Name 'Repair-GuiThemePalette'"
        $telemetryContent | Should -Not -Match "Get-Command -Name 'Repair-GuiThemePalette'"
        ([regex]::Matches($systemFeaturesContent, "Get-Command -Name 'GUICommon\\Repair-GuiThemePalette'")).Count | Should -Be 2
        ([regex]::Matches($uwpAppsContent, "Get-Command -Name 'GUICommon\\Repair-GuiThemePalette'")).Count | Should -Be 1
        ([regex]::Matches($telemetryContent, "Get-Command -Name 'GUICommon\\Repair-GuiThemePalette'")).Count | Should -Be 1
        $systemFeaturesContent | Should -Match '& \$repairGuiThemePalette -Theme \$Theme -ThemeName'
    }

    It 'routes popup actions through the shared async runner' {
        $systemFeaturesContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/System/System.WindowsFeatures.psm1')
        $telemetryContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')

        $systemFeaturesContent | Should -Match 'function Resolve-SystemPickerGuiCommonPath'
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\Start-GuiPopupCommandAsync -Window \$Form -ModulePath \$modulePath -AdditionalModulePaths @\(\$sharedHelpersPath, \$guiCommonPath\) -CommandName ''WindowsCapabilities''')).Count | Should -Be 1
        ([regex]::Matches($systemFeaturesContent, 'GUICommon\\Start-GuiPopupCommandAsync -Window \$Form -ModulePath \$modulePath -AdditionalModulePaths @\(\$guiCommonPath\) -CommandName ''WindowsFeatures''')).Count | Should -Be 1
        ([regex]::Matches($telemetryContent, 'GUICommon\\Start-GuiPopupCommandAsync -Window \$Form -ModulePath \$modulePath -AdditionalModulePaths @\(\$guiCommonPath\) -CommandName ''ScheduledTasks''')).Count | Should -Be 1
    }

    It 'resolves split picker async modules from parent module paths' {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $expectedGuiCommonPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'Module/GUICommon.psm1'))

        $modulePath = $null
        $guiCommonPath = $null
        . (Join-Path $repoRoot 'Module/Regions/PrivacyTelemetry/TelemetryServices/ScheduledTasks/ModulePathResolution.ps1')
        [System.IO.Path]::GetFullPath($modulePath) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $repoRoot 'Module/Regions/PrivacyTelemetry/PrivacyTelemetry.TelemetryServices.psm1')))
        [System.IO.Path]::GetFullPath($guiCommonPath) | Should -Be $expectedGuiCommonPath

        $modulePath = $null
        . (Join-Path $repoRoot 'Module/Regions/UWPApps/UWPApps/ModulePathResolution.ps1')
        [System.IO.Path]::GetFullPath($modulePath) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $repoRoot 'Module/Regions/UWPApps.psm1')))
        [System.IO.Path]::GetFullPath((Resolve-UWPAppsGuiCommonPath -StartPath $modulePath)) | Should -Be $expectedGuiCommonPath

        $modulePath = $null
        . (Join-Path $repoRoot 'Module/Regions/System/WindowsFeatures/WindowsCapabilities/ModulePathResolution.ps1')
        [System.IO.Path]::GetFullPath($modulePath) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $repoRoot 'Module/Regions/System/System.WindowsFeatures.psm1')))
    }

    It 'prevents popup caption drag chrome from swallowing minimize and close clicks' {
        $guiCommonContent | Should -Match 'function Test-GuiPopupDescendantOfElement'
        $guiCommonContent | Should -Match '\$testPopupDescendant = \$\{function:Test-GuiPopupDescendantOfElement\}'
        $guiCommonContent | Should -Match '& \$testPopupDescendant -Source \$originalSource -Target \$windowRef\.GuiPopupMinimizeButton'
        $guiCommonContent | Should -Match '& \$testPopupDescendant -Source \$originalSource -Target \$windowRef\.GuiPopupCloseButton'
        $guiCommonContent | Should -Match '\$windowRef\.DragMove\(\)'
    }

    It 'keeps popup caption buttons enabled despite picker action-button defaults' {
        $guiCommonContent | Should -Match '\$minimizeButton\.IsEnabled = \$true'
        $guiCommonContent | Should -Match '\$closeButton\.IsEnabled = \$true'
    }

    It 'repaints open popup windows when the main theme changes' {
        $guiContent | Should -Match 'GUICommon\\Update-GuiPopupWindowThemes -Theme \$Theme -UseDarkMode \(\$Script:CurrentThemeName -eq ''Dark''\)'
    }

    It 'marks Close actions as cancel semantics in shared dialogs' {
        $guiCommonContent | Should -Match '\$btn\.IsCancel = \$true'
        $dialogHelpersContent | Should -Match '\$btnClose\.IsCancel = \$true'
    }

    It 'maps implicit shared-dialog close to dismissive results instead of the first action button' {
        $guiCommonContent | Should -Match 'function Get-GuiDialogDismissResult'
        $guiCommonContent | Should -Match 'if \(\$Buttons -contains ''Cancel''\)'
        $guiCommonContent | Should -Match 'if \(\$Buttons -contains ''Close''\)'
        $guiCommonContent | Should -Match 'Get-GuiDialogDismissResult -Buttons \$Buttons'
        $executionSummaryDialogCommonContent | Should -Match 'Get-GuiDialogDismissResult -Buttons \$Buttons'
        $executionSummaryDialogCommonContent | Should -Not -Match '\$Buttons\.Count -gt 0\) \{ \$Buttons\[0\] \}'
    }
}
