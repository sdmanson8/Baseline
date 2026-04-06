Set-StrictMode -Version Latest

BeforeAll {
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $script:GuiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

Describe 'Adaptive primary tab layout' {
    It 'uses a stable horizontally scrollable single-row tab host for primary navigation' {
        $script:GuiContent | Should -Match '<Grid Name="PrimaryTabHost" Grid.Row="1" Margin="8,4,8,0">'
        $script:GuiContent | Should -Match '<ScrollViewer Name="PrimaryTabHeaderScroll"'
        $script:GuiContent | Should -Match 'HorizontalScrollBarVisibility="Auto"'
        $script:GuiContent | Should -Match '<StackPanel Name="HeaderPanel"'
        $script:GuiContent | Should -Match 'Orientation="Horizontal"'
        $script:GuiContent | Should -Match 'IsItemsHost="True"'
        $script:GuiContent | Should -Not -Match '<UniformGrid Name="HeaderPanel" Rows="1"'
    }

    It 'keeps the real tab strip visible instead of switching to dropdown mode' {
        $script:GuiContent | Should -Match '\$PrimaryTabs\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        $script:GuiContent | Should -Match '\$PrimaryTabDropdown\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        $script:GuiContent | Should -Not -Match '\$windowWidth -lt 1000'
        $script:GuiContent | Should -Not -Match "\$newMode = if .*'dropdown'.*'tabs'"
    }
}
