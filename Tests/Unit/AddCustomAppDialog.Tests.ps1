Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:DialogPath = Join-Path $script:RepoRoot 'Module/GUI/AddCustomAppDialog.ps1'
    $script:XamlPath = Join-Path $script:RepoRoot 'Module/GUI/MainWindow.xaml'
    $script:WindowSetupPath = Join-Path $script:RepoRoot 'Module/GUI/WindowSetup.ps1'
    $script:ActionHandlersPath = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers.ps1'
    $script:ActionHandlersSplitRoot = Join-Path $script:RepoRoot 'Module/GUI/ActionHandlers'
    $script:GuiRegionPath = Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1'
    $script:UserAppsHelpersPath = Join-Path $script:RepoRoot 'Module/SharedHelpers/UserApps.Helpers.ps1'

    $script:DialogContent = Get-BaselineTestSourceText -Path $script:DialogPath
    $script:XamlContent = Get-BaselineTestSourceText -Path $script:XamlPath
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path $script:WindowSetupPath
    $script:ActionHandlersContent = Get-BaselineTestSourceText -Path @(
        $script:ActionHandlersPath
        (Join-Path $script:ActionHandlersSplitRoot 'ThemeNavigationHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'ButtonHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'SystemScanFooterHandlers.ps1')
        (Join-Path $script:ActionHandlersSplitRoot 'MenuHandlers.ps1')
    )
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $script:GuiRegionPath
}

Describe '+ Add custom app dialog: XAML button wiring (#29 / spec #18)' {
    It 'declares BtnAppsAddCustom in MainWindow.xaml within the Apps filter options panel' {
        $script:XamlContent | Should -Match 'Name="BtnAppsAddCustom"'
        # Must sit inside the same WrapPanel as the existing source-filter / view-mode controls.
        $idxButton = $script:XamlContent.IndexOf('Name="BtnAppsAddCustom"')
        $idxFilterPanel = $script:XamlContent.IndexOf('Name="AppsFilterOptionsPanel"')
        $idxFilterPanelClose = $script:XamlContent.IndexOf('</WrapPanel>', $idxFilterPanel)
        $idxButton | Should -BeGreaterThan $idxFilterPanel
        $idxButton | Should -BeLessThan $idxFilterPanelClose
    }

    It 'wires FindName + $Script: assignment for BtnAppsAddCustom in WindowSetup.ps1' {
        $script:WindowSetupContent | Should -Match '\$BtnAppsAddCustom = \$Form\.FindName\("BtnAppsAddCustom"\)'
        $script:WindowSetupContent | Should -Match '\$Script:BtnAppsAddCustom = \$BtnAppsAddCustom'
    }
}

Describe '+ Add custom app dialog: dot-source wiring' {
    It 'dot-sources AddCustomAppDialog.ps1 from Module/Regions/GUI.psm1' {
        $script:GuiRegionContent | Should -Match "Join-Path \`$Script:GuiExtractedRoot 'AddCustomAppDialog\.ps1'"
    }
}

Describe '+ Add custom app dialog: function definitions' {
    It 'defines Show-GuiAddCustomAppDialog' {
        $script:DialogContent | Should -Match 'function Show-GuiAddCustomAppDialog'
    }

    It 'defines Save-BaselineUserAppEntry helper' {
        $script:DialogContent | Should -Match 'function Save-BaselineUserAppEntry'
    }

    It 'short-circuits in headless harness when $Script:CurrentTheme is unset' {
        $script:DialogContent | Should -Match 'if \(-not \$Script:CurrentTheme\)'
        $script:DialogContent | Should -Match 'return @\{ Cancelled = \$true; Saved = \$false'
    }

    It 'binds the Save click to validate via Test-BaselineUserAppEntry before persisting' {
        $script:DialogContent | Should -Match 'Test-BaselineUserAppEntry -Entry \$entryObject'
        # Validation gate must run BEFORE Save-BaselineUserAppEntry.
        $idxValidate = $script:DialogContent.IndexOf('Test-BaselineUserAppEntry -Entry $entryObject')
        $idxSave = $script:DialogContent.IndexOf('Save-BaselineUserAppEntry -Entry $entryObject')
        $idxValidate | Should -BeGreaterThan 0
        $idxSave | Should -BeGreaterThan $idxValidate
    }

    It 'surfaces validation errors to the in-dialog ValidationPanel rather than silently dropping' {
        $script:DialogContent | Should -Match 'if \(-not \$validation\.IsValid\)'
        $script:DialogContent | Should -Match "\`$panelRef\.Visibility = 'Visible'"
    }

    It 'forces Function=AppInstall on every saved entry (security guard against arbitrary registry writes)' {
        # Test-BaselineUserAppEntry rejects any Function != 'AppInstall', but pinning
        # the dialog explicitly stamps it ensures we never rely on the user remembering.
        $script:DialogContent | Should -Match "Function    = 'AppInstall'"
    }

    It 'writes via [System.IO.File]::WriteAllText with UTF8 (no BOM)' {
        $script:DialogContent | Should -Match '\[System\.IO\.File\]::WriteAllText'
        $script:DialogContent | Should -Match 'New-Object System\.Text\.UTF8Encoding\(\$false\)'
    }

    It 'derives the on-disk filename via Get-BaselineUserAppFileName, suffixing on collision' {
        $script:DialogContent | Should -Match 'function Get-BaselineUserAppFileName'
        $script:DialogContent | Should -Match 'Test-Path -LiteralPath \$candidate'
    }

    It 'wraps the on-disk write in try/catch so a write failure surfaces in the panel instead of crashing the GUI' {
        $script:DialogContent | Should -Match "Source 'AddCustomAppDialog\.Save'"
    }
}

Describe '+ Add custom app dialog: click handler integration' {
    It 'registers a Click handler on BtnAppsAddCustom in ActionHandlers.ps1' {
        $script:ActionHandlersContent | Should -Match 'if \(\$BtnAppsAddCustom\)'
        $script:ActionHandlersContent | Should -Match 'Register-GuiEventHandler -Source \$BtnAppsAddCustom -EventName ''Click'''
    }

    It 'invokes Show-GuiAddCustomAppDialog from the Click handler' {
        $script:ActionHandlersContent | Should -Match '\$result = Show-GuiAddCustomAppDialog'
    }

    It 'refreshes the catalog via Get-BaselineApplicationsCatalog -Force after a saved entry' {
        $script:ActionHandlersContent | Should -Match 'Get-BaselineApplicationsCatalog -Force'
        # Refresh must be gated on $result.Saved being truthy, otherwise cancelling
        # the dialog still triggers a full catalog rebuild.
        $idxSavedGate = $script:ActionHandlersContent.IndexOf('if (-not $result -or -not $result.Saved) { return }')
        $idxRefresh = $script:ActionHandlersContent.IndexOf('Get-BaselineApplicationsCatalog -Force')
        $idxSavedGate | Should -BeGreaterThan 0
        $idxRefresh | Should -BeGreaterThan $idxSavedGate
    }

    It 'invalidates AppsViewBuildSignature so the next Build-AppsViewCards picks up the new entry' {
        $idxRefresh = $script:ActionHandlersContent.IndexOf('Get-BaselineApplicationsCatalog -Force')
        $tail = $script:ActionHandlersContent.Substring($idxRefresh)
        $tail | Should -Match '\$Script:AppsViewBuildSignature = \$null'
        $tail | Should -Match 'Build-AppsViewCards'
    }
}

Describe 'Save-BaselineUserAppEntry behavior' {
    BeforeAll {
        # Source the helper functions into the test session via Invoke-Expression
        # against the parsed AST function-definition snippets. This keeps the test
        # focused on the dialog file and avoids dragging in the WPF surface.
        . $script:UserAppsHelpersPath
        . $script:DialogPath

        $script:TempUserAppsDir = Join-Path ([System.IO.Path]::GetTempPath()) ('BaselineUserAppsTest_' + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:TempUserAppsDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if ($script:TempUserAppsDir -and (Test-Path -LiteralPath $script:TempUserAppsDir))
        {
            Remove-Item -LiteralPath $script:TempUserAppsDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'sanitizes app names with spaces and reserved chars into a safe filename' {
        $name = Get-BaselineUserAppFileName -Name 'My Cool App: V1/2'
        $name | Should -Not -Match '[\\/:*?"<>|]'
        $name | Should -Match '\.json$'
    }

    It 'writes a valid catalog file with Tab=Applications and a single Entries member' {
        $entry = [pscustomobject]@{
            Name = 'TestUserApp'
            SubCategory = 'Tools'
            Function = 'AppInstall'
            ExtraArgs = [pscustomobject]@{ WinGetId = 'Test.UserApp' }
        }
        $path = Save-BaselineUserAppEntry -Entry $entry -Directory $script:TempUserAppsDir
        Test-Path -LiteralPath $path | Should -Be $true

        $parsed = Get-BaselineTestSourceText -Path $path | ConvertFrom-Json
        $parsed.Tab | Should -Be 'Applications'
        @($parsed.Entries).Count | Should -Be 1
        $parsed.Entries[0].Name | Should -Be 'TestUserApp'
    }

    It 'suffixes the filename on collision rather than overwriting' {
        $entry = [pscustomobject]@{
            Name = 'CollidingApp'
            SubCategory = 'Tools'
            Function = 'AppInstall'
            ExtraArgs = [pscustomobject]@{ WinGetId = 'Test.Collide' }
        }
        $first = Save-BaselineUserAppEntry -Entry $entry -Directory $script:TempUserAppsDir
        $second = Save-BaselineUserAppEntry -Entry $entry -Directory $script:TempUserAppsDir
        $first | Should -Not -Be $second
        Test-Path -LiteralPath $first | Should -Be $true
        Test-Path -LiteralPath $second | Should -Be $true
    }
}
