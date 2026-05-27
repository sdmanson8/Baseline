Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:GuiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:MainWindowPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $script:ActionHandlersPath = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $PSScriptRoot '../../Module/GUI/ActionHandlers'
    $script:StyleManagementPath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $script:WindowClosingHandlerPath = Join-Path $PSScriptRoot '../../Module/GUI/Show-TweakGUI/WindowClosingHandler.ps1'
    $script:GuiContent = (Get-BaselineTestSourceText -Path $script:GuiPath) + "`n" + (Get-BaselineTestSourceText -Path $script:MainWindowPath)
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:StyleManagementContent = Get-BaselineTestSourceText -Path $script:StyleManagementPath
    $script:WindowClosingContent = Get-BaselineTestSourceText -Path $script:WindowClosingHandlerPath
}

Describe 'Support bundle GUI wiring' {
    It 'exposes support bundle export in the menu and wires it through the action handlers' {
        $script:GuiContent | Should -Match 'MenuToolsExportSupportBundle'
        $script:GuiContent | Should -Match 'Export Support Bundle\.\.\.'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Export-BaselineSupportBundle'"
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$MenuToolsExportSupportBundle -EventName ''Click'''
        $script:ActionHandlersContent | Should -Match 'Show-GuiSupportBundleSessionLogDialog'
        $script:ActionHandlersContent | Should -Match 'Get-GuiSupportBundleSessionLogChoices'
        $script:ActionHandlersContent | Should -Match 'Show-GuiFileSaveDialog'
        $script:ActionHandlersContent | Should -Match 'function Show-GuiSupportBundleProgressDialog'
        $script:ActionHandlersContent | Should -Match 'New-Object System\.Windows\.Controls\.ProgressBar'
        $script:ActionHandlersContent | Should -Match '\$progressBar\.IsIndeterminate = \$true'
        $script:ActionHandlersContent | Should -Match "Get-GuiFunctionCapture -Name 'Show-GuiSupportBundleProgressDialog'"
        $script:ActionHandlersContent | Should -Match "Get-GuiFunctionCapture -Name 'Close-GuiSupportBundleProgressDialog'"
        $script:ActionHandlersContent | Should -Match "Get-GuiFunctionCapture -Name 'Set-GuiSupportBundleProgressDialogStatus'"
        $script:ActionHandlersContent | Should -Match "Get-GuiFunctionCapture -Name 'Start-GuiSupportBundleExportAsync'"
        $script:ActionHandlersContent | Should -Match "Get-GuiFunctionCapture -Name 'Show-ThemedDialog'"
        $script:ActionHandlersContent | Should -Match '\$progressDialog = & \$showSupportBundleProgressDialogCommand -OutputPath \$savePath'
        $script:ActionHandlersContent | Should -Match '& \$closeSupportBundleProgressDialogCommand -ProgressDialog \$progressDialog'
        $script:ActionHandlersContent | Should -Match 'function Start-GuiSupportBundleExportAsync'
        $script:ActionHandlersContent | Should -Match '\[System\.Management\.Automation\.Runspaces\.RunspaceFactory\]::CreateRunspace\(\)'
        $script:ActionHandlersContent | Should -Match '\$ps\.BeginInvoke\(\)'
        $script:ActionHandlersContent | Should -Match '\[System\.Windows\.Threading\.DispatcherTimer\]::new\(\)'
        $script:ActionHandlersContent | Should -Match 'Set-GuiSupportBundleProgressDialogStatus'
        $script:ActionHandlersContent | Should -Match 'Import-Module -Name \$SharedHelpersPath -Force -Global -ErrorAction Stop'
        $script:ActionHandlersContent | Should -Match 'ProgressCallback = \$progressCallback'
        $script:ActionHandlersContent | Should -Match 'Export-BaselineSupportBundle @exportArgs'
        $script:ActionHandlersContent | Should -Not -Match 'Manifest = \$manifest'
        $script:ActionHandlersContent | Should -Not -Match 'Import-TweakManifestFromData -ModuleRoot'
        $script:ActionHandlersContent | Should -Match 'function Stop-GuiSupportBundleExportWorker'
        $script:ActionHandlersContent | Should -Match '\$Script:StopGuiSupportBundleExportWorkerScript = \$\{function:Stop-GuiSupportBundleExportWorker\}'
        $script:ActionHandlersContent | Should -Match '& \$stopSupportBundleExportScript -Reason ''Support bundle export completed\.'''
        $script:ActionHandlersContent | Should -Match 'SupportBundleExportWorker'
        $script:ActionHandlersContent | Should -Match '\$worker\.PowerShell\.BeginStop'
        $script:ActionHandlersContent | Should -Match '\$worker\.Runspace\.Close\(\)'
        $script:ActionHandlersContent | Should -Match '\$worker\.Runspace\.CloseAsync\(\)'
        $script:WindowClosingContent | Should -Match "Get-Variable -Scope Script -Name 'StopGuiSupportBundleExportWorkerScript'"
        $script:ActionHandlersContent | Should -Match '& \$startSupportBundleExportAsyncCommand -OutputPath \$savePath'
        $script:ActionHandlersContent | Should -Match '-SetProgressDialogStatus \$setSupportBundleProgressDialogStatusCommand'
        $script:ActionHandlersContent | Should -Match '-CloseProgressDialog \$closeSupportBundleProgressDialogCommand'
        $script:ActionHandlersContent | Should -Match '-ShowDialog \$showThemedDialogCommand'
        $script:ActionHandlersContent | Should -Match 'SupportBundleExportInProgress'
        $script:ActionHandlersContent | Should -Match '-SessionLogPath'
        $script:ActionHandlersContent | Should -Match "Invoke-UserLaunch -FilePath 'explorer.exe'"
        $script:ActionHandlersContent | Should -Not -Match 'Select a folder to save the support bundle'
        $script:ActionHandlersContent | Should -Match 'PreRunSnapshot'
        $script:ActionHandlersContent | Should -Match 'PostRunSnapshot'
        $script:ActionHandlersContent | Should -Match '-PreSnapshot'
        $script:ActionHandlersContent | Should -Match '-PostSnapshot'
        $script:ActionHandlersContent | Should -Match 'Export Support Bundle'
    }

    It 'keeps the support bundle label and enabled state in sync with the GUI theme and action state' {
        $script:StyleManagementContent | Should -Match 'MenuToolsExportSupportBundle'
        $script:StyleManagementContent | Should -Match "GuiMenuToolsExportSupportBundle"
        $script:StyleManagementContent | Should -Match 'Set-GuiActionButtonsEnabled'
        $script:StyleManagementContent | Should -Match 'MenuToolsExportSupportBundle\.IsEnabled = \$Enabled'
    }

    It 'keeps support bundle cleanup callable after local function names leave scope' {
        $parseErrors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:ActionHandlersContent, [ref]$tokens, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $functions = @{}
        foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if ($functionAst.Name -in @('Close-GuiSupportBundleProgressDialog', 'Stop-GuiSupportBundleExportWorker')) {
                $functions[$functionAst.Name] = $functionAst.Extent.Text
            }
        }
        $functions.ContainsKey('Close-GuiSupportBundleProgressDialog') | Should -BeTrue
        $functions.ContainsKey('Stop-GuiSupportBundleExportWorker') | Should -BeTrue

        Invoke-Expression $functions['Close-GuiSupportBundleProgressDialog']
        Invoke-Expression $functions['Stop-GuiSupportBundleExportWorker']
        $Script:CloseGuiSupportBundleProgressDialogScript = ${function:Close-GuiSupportBundleProgressDialog}
        $Script:StopGuiSupportBundleExportWorkerScript = ${function:Stop-GuiSupportBundleExportWorker}
        Remove-Item -Path Function:\Close-GuiSupportBundleProgressDialog -Force
        Remove-Item -Path Function:\Stop-GuiSupportBundleExportWorker -Force

        $Script:SupportBundleExportInProgress = $true
        $Script:SupportBundleExportWorker = [pscustomobject]@{
            Timer            = $null
            ProgressDialog   = $null
            PowerShell       = $null
            AsyncResult      = $null
            MenuItem         = $null
            SessionStatePath = $null
            Runspace         = $null
        }

        & $Script:StopGuiSupportBundleExportWorkerScript -Reason 'test cleanup' -SkipEndInvoke

        $Script:SupportBundleExportInProgress | Should -BeFalse
        $Script:SupportBundleExportWorker | Should -BeNullOrEmpty
    }

    It 'keeps app maintenance and support bundle export visible while Safe Mode hides advanced Tools actions' {
        $modeStateContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/ModeState.ps1')
        $modeStateContent | Should -Match '\$Script:MenuTools\.Visibility\s+=\s+''Visible'''
        $modeStateContent | Should -Match '\$Script:MenuToolsAppsManager\.Visibility\s+=\s+''Visible'''
        $modeStateContent | Should -Match '\$Script:MenuToolsUpdateAllApps\.Visibility\s+=\s+''Visible'''
        $modeStateContent | Should -Match '\$Script:MenuToolsExportSupportBundle\.Visibility\s+=\s+''Visible'''
        $modeStateContent | Should -Match '\$Script:MenuToolsRemoteConsole\.Visibility\s+=\s+\$safeModeHidden'
    }
}
