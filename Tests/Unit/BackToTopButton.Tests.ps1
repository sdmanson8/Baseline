Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    $script:MainWindowContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/MainWindow.xaml')
    $script:WindowSetupContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/WindowSetup.ps1')
    $script:GuiRegionContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1')
    $script:BackToTopContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/BackToTopButton.ps1')
    $script:ContentManagementContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/ContentManagement.ps1')
    $script:BuildTabContentContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/BuildTabContent.ps1')
    $script:ProgressNavChromeContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/AppsModule/ProgressNavChrome.ps1')
}

Describe 'Back to Top button' {
    It 'adds one floating overlay button to the shared content surface' {
        $script:MainWindowContent | Should -Match '<Style x:Key="BackToTopButtonStyle" TargetType="Button">'
        $script:MainWindowContent | Should -Match '<Grid Name="ContentScrollHost">'
        $script:MainWindowContent | Should -Match '<ScrollViewer Name="ContentScroll"'
        $script:MainWindowContent | Should -Match '<ScrollViewer Name="DeploymentMediaScroll"'
        $script:MainWindowContent | Should -Match '<ScrollViewer Name="AppsScroll"'
        $script:MainWindowContent | Should -Match '<Button Name="BtnBackToTop"'
        $script:MainWindowContent | Should -Match 'HorizontalAlignment="Right"'
        $script:MainWindowContent | Should -Match 'VerticalAlignment="Bottom"'
        $script:MainWindowContent | Should -Match 'ToolTip="Scroll to top"'
        $script:MainWindowContent | Should -Match 'Visibility="Collapsed"'
        $script:MainWindowContent | Should -Match 'Opacity="0"'
    }

    It 'wires the shared helper during GUI startup' {
        $script:GuiRegionContent | Should -Match "BackToTopButton\.ps1"
        $script:GuiRegionContent | Should -Match 'Initialize-GuiBackToTopButton -Window \$Form -ScrollViewer \$ContentScroll -AdditionalScrollViewers @\(\$DeploymentMediaScroll, \$AppsScroll\) -Button \$BtnBackToTop'
        $script:WindowSetupContent | Should -Match '\$ContentScrollHost = \$Form\.FindName\("ContentScrollHost"\)'
        $script:WindowSetupContent | Should -Match '\$BtnBackToTop = \$Form\.FindName\("BtnBackToTop"\)'
        $script:WindowSetupContent | Should -Match '\$Script:BtnBackToTop = \$BtnBackToTop'
    }

    It 'uses thresholded visibility, fade animation, smooth offset animation, and Ctrl+Home' {
        $script:BackToTopContent | Should -Match '\$Script:BackToTopScrollThreshold = 500\.0'
        $script:BackToTopContent | Should -Match 'function Update-GuiBackToTopButton'
        $script:BackToTopContent | Should -Match 'function Get-GuiBackToTopActiveScrollViewer'
        $script:BackToTopContent | Should -Match 'function Invoke-GuiBackToTopScroll'
        $script:BackToTopContent | Should -Match '\[System\.Windows\.Media\.Animation\.DoubleAnimation\]::new\(\)'
        $script:BackToTopContent | Should -Match '\[System\.Windows\.Media\.Animation\.CubicEase\]::new\(\)'
        $script:BackToTopContent | Should -Match 'ScrollToVerticalOffset\(\[Math\]::Max\(0\.0, \$currentOffset\)\)'
        $script:BackToTopContent | Should -Match 'if \(\$updateScript\) \{ & \$updateScript \}'
        $script:BackToTopContent | Should -Match '\$eventArgs\.Key -ne \[System\.Windows\.Input\.Key\]::Home'
        $script:BackToTopContent | Should -Match '\[System\.Windows\.Input\.ModifierKeys\]::Control'
    }

    It 'shares the button across all four navigation modes' {
        $script:BackToTopContent | Should -Match '\[bool\]\$Script:AppsModeActive'
        $script:BackToTopContent | Should -Match 'return \$Script:AppsScroll'
        $script:BackToTopContent | Should -Match '\[bool\]\$Script:DeploymentMediaModeActive'
        $script:BackToTopContent | Should -Match 'return \$Script:DeploymentMediaScroll'
        $script:BackToTopContent | Should -Match 'return \$Script:BackToTopScrollViewer'
        $script:BackToTopContent | Should -Match '\$Script:BackToTopScrollViewers = \[System\.Collections\.Generic\.List\[System\.Windows\.Controls\.ScrollViewer\]\]::new\(\)'
        $script:BackToTopContent | Should -Match 'foreach \(\$registeredScrollViewer in \$Script:BackToTopScrollViewers\)'
        $script:BackToTopContent | Should -Not -Match '\$Script:AppsModeActive -or \$Script:UpdatesModeActive -or \$Script:DeploymentMediaModeActive'
    }

    It 'refreshes visibility when content or navigation mode changes' {
        $script:ContentManagementContent | Should -Match 'ContentManagement\.UpdateBackToTopButton'
        $script:BuildTabContentContent | Should -Match 'BuildTabContent\.SaveTabContentCacheEntry\.UpdateBackToTopButton'
        $script:ProgressNavChromeContent | Should -Match 'AppsModule\.Set-GuiAppsMode\.UpdateBackToTopButton'
        $script:ProgressNavChromeContent | Should -Match 'AppsModule\.Set-GuiUpdatesMode\.UpdateBackToTopButton'
        $script:ProgressNavChromeContent | Should -Match 'AppsModule\.Set-GuiDeploymentMediaMode\.UpdateBackToTopButton'
    }
}
