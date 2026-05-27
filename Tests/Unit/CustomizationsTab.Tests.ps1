Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:GuiRegionPath = Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1'
    $script:BuildPrimaryTabsPath = Join-Path $script:RepoRoot 'Module/GUI/BuildPrimaryTabs.ps1'
    $script:TabManagementPath = Join-Path $script:RepoRoot 'Module/GUI/TabManagement.ps1'
    $script:BuildTabContentPath = Join-Path $script:RepoRoot 'Module/GUI/BuildTabContent.ps1'
    $script:IconFactoryPath = Join-Path $script:RepoRoot 'Module/GUI/IconFactory.ps1'
    $script:StartupDialogPath = Join-Path $script:RepoRoot 'Module/GUI/StartupManagerDialog.ps1'

    $script:GuiRegionContent = Get-BaselineTestSourceText -Path $script:GuiRegionPath
    $script:BuildPrimaryTabsContent = Get-BaselineTestSourceText -Path $script:BuildPrimaryTabsPath
    $script:TabManagementContent = Get-BaselineTestSourceText -Path $script:TabManagementPath
    $script:BuildTabContentContent = Get-BaselineTestSourceText -Path $script:BuildTabContentPath
    $script:IconFactoryContent = Get-BaselineTestSourceText -Path $script:IconFactoryPath
    $script:StartupDialogContent = Get-BaselineTestSourceText -Path $script:StartupDialogPath
}

Describe 'Customizations tab wiring' {
    It 'declares Customizations as a primary category' {
        $script:GuiRegionContent | Should -Match '"Customizations"\s*=\s*@\(\)'
    }

    It 'forces the Customizations tab to exist even when no manifest tweaks map to it' {
        $script:BuildPrimaryTabsContent | Should -Match 'if \(\$pKey -eq ''Customizations''\)'
        $script:BuildPrimaryTabsContent | Should -Match 'Get-GuiCustomizationsActionCardCount'
    }

    It 'counts rendered action cards for the Customizations tab header' {
        $script:TabManagementContent | Should -Match 'function Get-GuiCustomizationsActionCardDefinitions'
        $script:TabManagementContent | Should -Match 'function Get-GuiCustomizationsActionCardCount'
        $script:TabManagementContent | Should -Match 'if \(\$pKey -eq ''Customizations''\)'
        $script:TabManagementContent | Should -Match 'Get-GuiCustomizationsActionCardCount'
    }

    It 'resolves the Customizations tab count to the rendered action-card count' {
        . $script:TabManagementPath

        Get-GuiCustomizationsActionCardCount | Should -Be 3
        @((Get-GuiCustomizationsActionCardDefinitions) | Select-Object -ExpandProperty Key) | Should -Be @('StartupManager', 'UserFolders', 'WslInstall')
    }

    It 'localizes and icons the Customizations tab like the other tweak categories' {
        $script:TabManagementContent | Should -Match "'Customizations'\s+=\s+'GuiTabCustomizations'"
        $script:IconFactoryContent | Should -Match "'Customizations'\s+\{\s+return 'WindowSettings'\s+\}"
    }

    It 'special-cases Build-TabContent for Customizations' {
        $script:BuildTabContentContent | Should -Match 'if \(\$PrimaryTab -eq ''Customizations''\)'
        $script:BuildTabContentContent | Should -Match 'New-GuiStartupManagerTabContent'
        $script:BuildTabContentContent | Should -Match '(?s)if \(\$PrimaryTab -eq ''Customizations''\).*?Invoke-GuiStartupReadySignal'
    }

    It 'hosts Startup Manager, User Folders, and WSL install action cards inside Customizations' {
        $script:TabManagementContent | Should -Match 'StartupManager'
        $script:TabManagementContent | Should -Match 'UserFolders'
        $script:TabManagementContent | Should -Match 'WslInstall'
        $script:StartupDialogContent | Should -Match 'foreach \(\$definition in @\(Get-GuiCustomizationsActionCardDefinitions\)\)'
        $script:StartupDialogContent | Should -Match 'function New-GuiCustomizationsActionCard'
        $script:StartupDialogContent | Should -Match 'Invoke-GuiCustomizationsStartupManagerAction'
        $script:StartupDialogContent | Should -Match 'Invoke-GuiCustomizationsUserFoldersAction'
        $script:StartupDialogContent | Should -Match 'Invoke-GuiCustomizationsWslInstallAction'
    }

    It 'routes adaptive tab layout bring-into-view failures through Write-SwallowedException' {
        $script:BuildPrimaryTabsContent | Should -Match "BuildPrimaryTabs\.AdaptiveTabLayout\.BringIntoView"
    }

    It 'does not count startup entries as Customizations tab items' {
        $script:TabManagementContent | Should -Not -Match 'Get-BaselineStartupEntries'
        $script:BuildPrimaryTabsContent | Should -Not -Match 'Get-BaselineStartupEntries'
    }
}
