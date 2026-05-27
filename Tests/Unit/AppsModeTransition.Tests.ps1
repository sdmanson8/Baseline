Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:MainWindowXamlPath = Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml'
    $script:WindowSetupPath = Join-Path $PSScriptRoot '../../Module/GUI/WindowSetup.ps1'
    $script:ProgressNavChromePath = Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/ProgressNavChrome.ps1'
    $script:MainWindowXamlContent = Get-BaselineTestSourceText -Path $script:MainWindowXamlPath
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path $script:WindowSetupPath
    $script:ProgressNavChromeContent = Get-BaselineTestSourceText -Path $script:ProgressNavChromePath
}

Describe 'Apps progress strip' {
    It 'does not declare the removed Apps progress/status strip in the UI' {
        $script:MainWindowXamlContent | Should -Not -Match 'Name="AppsProgressContainer"'
        $script:MainWindowXamlContent | Should -Not -Match 'Name="TxtAppsProgressText"'
    }

    It 'does not wire the removed strip into window setup or Apps mode' {
        $script:WindowSetupContent | Should -Not -Match 'AppsProgressContainer'
        $script:WindowSetupContent | Should -Not -Match '\$Form\.FindName\("TxtAppsProgressText"\)'
        $script:ProgressNavChromeContent | Should -Not -Match 'Initialize-AppsProgressSection'
        $script:ProgressNavChromeContent | Should -Not -Match '\$Script:TxtAppsProgressText\.Visibility'
        $script:ProgressNavChromeContent | Should -Not -Match '\$Script:TxtAppsProgressText\.Text = \(Get-AppsCacheRefreshPromptText\)'
    }
}

Describe 'Apps mode navigation restore' {
    It 'hydrates the selected Optimize tab when leaving Apps mode' {
        $script:ProgressNavChromeContent | Should -Match '(?s)elseif \(-not \[bool\]\$Script:GamingModeActive -and -not \[bool\]\$Script:UpdatesModeActive -and -not \[bool\]\$Script:DeploymentMediaModeActive\)\s*\{\s*if \(Get-Command -Name ''Update-CurrentTabContent'' -CommandType Function -ErrorAction SilentlyContinue\)\s*\{\s*Update-CurrentTabContent -SkipIdlePrebuild'
    }
}
