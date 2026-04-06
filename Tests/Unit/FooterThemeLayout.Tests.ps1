Set-StrictMode -Version Latest

BeforeAll {
    $stylePath = Join-Path $PSScriptRoot '../../Module/GUI/StyleManagement.ps1'
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'

    $script:StyleContent = Get-Content -LiteralPath $stylePath -Raw -Encoding UTF8
    $script:GuiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
}

Describe 'Footer and theme toggle layout' {
    It 'uses a dedicated theme palette for the Light Mode toggle' {
        $script:StyleContent | Should -Match "ValidateSet\('Default', 'Mode', 'Theme'\)"
        $script:StyleContent | Should -Match 'Set-HeaderToggleStyle -CheckBox \$ChkTheme -Palette Theme'
    }

    It 'gives the footer a two-row action and status layout' {
        $script:GuiContent | Should -Match '<Border Name="BottomBorder" Grid.Row="4" Padding="10,14,10,8" BorderThickness="0,1,0,0">'
        $script:GuiContent | Should -Match '<StackPanel Name="ActionButtonBar" Grid.Column="0"\s+Orientation="Vertical"'
        $script:GuiContent | Should -Match '<TextBlock Name="RunPathContextLabel" Grid.Column="1"'
    }

    It 'styles the footer and secondary action group from the active theme surfaces' {
        $script:GuiContent | Should -Match '\$BottomBorder\.Background = \$bc\.ConvertFromString\(\$Theme\.PanelBg\)'
        $script:GuiContent | Should -Match '\$BottomBorder\.BorderBrush = \$bc\.ConvertFromString\(\$Theme\.BorderColor\)'
        $script:GuiContent | Should -Match '\$Script:SecondaryActionGroupBorder\.Background = \$bc\.ConvertFromString\(\$Script:CurrentTheme\.CardBg\)'
    }
}
