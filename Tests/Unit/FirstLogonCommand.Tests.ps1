BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ConfigProfilePath = Join-Path $script:RepoRoot 'Module/SharedHelpers/ConfigProfile.Helpers.ps1'
    $script:SharedHelpersManifestPath = Join-Path $script:RepoRoot 'Module/SharedHelpers.psm1'
    $script:ConfigProfileModulePath = Join-Path $script:RepoRoot 'Module/SharedHelperModules/Baseline.SharedHelpers.ConfigProfile.psm1'
    $script:TweakVisualizationPath = Join-Path $script:RepoRoot 'Module/GUI/TweakVisualization.ps1'
    $script:ActionHandlersPath = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers'
    $script:StyleManagementPath = Join-Path $script:RepoRoot 'Module/GUI/StyleManagement.ps1'
    $script:ReadmePath = Join-Path $script:RepoRoot 'README.md'

    . (Join-Path $script:RepoRoot 'Module/SharedHelpers/Json.Helpers.ps1')
    . $script:ConfigProfilePath

    $script:ConfigProfileContent = Get-BaselineTestSourceText -Path $script:ConfigProfilePath
    $script:SharedHelpersContent = Get-BaselineTestSourceText -Path $script:SharedHelpersManifestPath
    $script:ConfigProfileModuleContent = Get-BaselineTestSourceText -Path $script:ConfigProfileModulePath
    $script:TweakVisualizationContent = Get-BaselineTestSourceText -Path $script:TweakVisualizationPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:StyleManagementContent = Get-BaselineTestSourceText -Path $script:StyleManagementPath
    $script:ReadmeContent = Get-BaselineTestSourceText -Path $script:ReadmePath
}

Describe 'Export-BaselineFirstLogonCommandSnippet' {
    BeforeEach {
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-firstlogon-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
        $script:ConfigPath = Join-Path $script:TempRoot 'Saved & Config.json'
        $script:OutputPath = Join-Path $script:TempRoot 'Baseline-FirstLogonCommand.xml'
        Set-Content -LiteralPath $script:ConfigPath -Value '{}' -Encoding UTF8
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TempRoot) { Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes a valid FirstLogonCommands XML snippet with an escaped command line' {
        $result = Export-BaselineFirstLogonCommandSnippet -ConfigPath $script:ConfigPath -FilePath $script:OutputPath

        Test-Path -LiteralPath $script:OutputPath | Should -BeTrue
        $xml = [System.IO.File]::ReadAllText($script:OutputPath)

        $xml | Should -Match '<FirstLogonCommands xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">'
        $xml | Should -Match '<SynchronousCommand wcm:action="add">'
        $xml | Should -Match '<Order>1</Order>'
        $xml | Should -Match '<Description>Run Baseline configuration profile</Description>'
        $xml | Should -Match 'Baseline\.exe --configfile &quot;.*Saved &amp; Config\.json&quot; --apply'
        $result.CommandLine | Should -Match 'Baseline\.exe --configfile ".*Saved & Config\.json" --apply'
        $result.FilePath | Should -Be $script:OutputPath
        $result.ConfigPath | Should -Be ([System.IO.Path]::GetFullPath($script:ConfigPath))
    }

    It 'creates the output directory if needed' {
        $nestedOutput = Join-Path $script:TempRoot 'nested\FirstLogon\autounattend-snippet.xml'
        $null = Export-BaselineFirstLogonCommandSnippet -ConfigPath $script:ConfigPath -FilePath $nestedOutput

        Test-Path -LiteralPath (Split-Path -Path $nestedOutput -Parent) | Should -BeTrue
        Test-Path -LiteralPath $nestedOutput | Should -BeTrue
    }
}

Describe 'First-logon command exports are wired through shared helpers and GUI' {
    It 'is exported by the shared helper manifest and named module' {
        $script:SharedHelpersContent | Should -Match "'Export-BaselineFirstLogonCommandSnippet'"
        $script:ConfigProfileModuleContent | Should -Match "'Export-BaselineFirstLogonCommandSnippet'"
    }

    It 'adds the Export First-Logon Command button next to the export profile button' {
        $script:ActionHandlersContent | Should -Match 'BtnExportFirstLogonCommand'
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Export-BaselineFirstLogonCommandSnippet' -CommandType 'Function'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiFileOpenDialog' -CommandType 'Function'"
        $script:ActionHandlersContent | Should -Match "Get-GuiRuntimeCommand -Name 'Show-GuiFileSaveDialog' -CommandType 'Function'"
        $script:ActionHandlersContent | Should -Match 'Split-Path -Path \$configPath -Parent'
    }

    It 'updates the button text and enabled state in the style layer' {
        $script:StyleManagementContent | Should -Match 'BtnExportFirstLogonCommand'
        $script:StyleManagementContent | Should -Match 'Export First-Logon Command'
        $script:StyleManagementContent | Should -Match 'Export an autounattend FirstLogonCommands XML snippet'
    }

    It 'allows the save dialog to target the config folder' {
        $script:TweakVisualizationContent | Should -Match '\[string\]\$InitialDirectory'
        $script:TweakVisualizationContent | Should -Match '\$saveDialog\.InitialDirectory = \$InitialDirectory'
    }

    It 'documents the first-logon command workflow in the README' {
        $script:ReadmeContent | Should -Match 'Export a first-logon command for autounattend'
        $script:ReadmeContent | Should -Match 'FirstLogonCommands'
        $script:ReadmeContent | Should -Match 'Baseline\.exe --configfile'
    }
}
