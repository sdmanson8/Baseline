Set-StrictMode -Version Latest

BeforeAll {
    $guiPath = Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1'
    $tabMgmtPath = Join-Path $PSScriptRoot '../../Module/GUI/TabManagement.ps1'

    $script:GuiContent = Get-Content -LiteralPath $guiPath -Raw -Encoding UTF8
    $script:TabMgmtContent = Get-Content -LiteralPath $tabMgmtPath -Raw -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────
# W-1c / R-5b: Responsive tab/dropdown switching contracts
# ─────────────────────────────────────────────────────────────

Describe 'Responsive tab/dropdown switching contracts' {

    Context 'XAML layout structure' {
        It 'defines PrimaryTabHost grid as the tab bar container' {
            $script:GuiContent | Should -Match '<Grid Name="PrimaryTabHost"'
        }

        It 'uses a ScrollViewer with horizontal auto-scroll for the tab header' {
            $script:GuiContent | Should -Match '<ScrollViewer Name="PrimaryTabHeaderScroll"'
            $script:GuiContent | Should -Match 'HorizontalScrollBarVisibility="Auto"'
            $script:GuiContent | Should -Match 'VerticalScrollBarVisibility="Disabled"'
        }

        It 'uses a horizontal StackPanel as the tab item host' {
            $script:GuiContent | Should -Match '<StackPanel Name="HeaderPanel"'
            $script:GuiContent | Should -Match 'Orientation="Horizontal"'
            $script:GuiContent | Should -Match 'IsItemsHost="True"'
        }

        It 'declares PrimaryTabDropdown ComboBox as collapsed in XAML' {
            $script:GuiContent | Should -Match '<ComboBox Name="PrimaryTabDropdown" Visibility="Collapsed"'
        }
    }

    Context 'Adaptive tab mode enforcement' {
        It 'initializes AdaptiveTabMode to tabs' {
            $script:GuiContent | Should -Match '\$Script:AdaptiveTabMode = .tabs.'
        }

        It 'initializes SuppressDropdownSync to false' {
            $script:GuiContent | Should -Match '\$Script:SuppressDropdownSync = \$false'
        }

        It 'adaptive layout script always sets mode to tabs' {
            # The layout script must unconditionally set mode to 'tabs' (no width-based branching to dropdown)
            $script:GuiContent | Should -Match '\$Script:AdaptiveTabMode = .tabs.'
        }

        It 'adaptive layout script collapses the dropdown' {
            $script:GuiContent | Should -Match '\$PrimaryTabDropdown\.Visibility = \[System\.Windows\.Visibility\]::Collapsed'
        }

        It 'adaptive layout script makes the tab strip visible' {
            $script:GuiContent | Should -Match '\$PrimaryTabs\.Visibility = \[System\.Windows\.Visibility\]::Visible'
        }

        It 'never switches to dropdown mode based on window width' {
            # Ensure no width-based mode toggle exists (was a historical responsive pattern)
            $script:GuiContent | Should -Not -Match "\`$newMode = if .*'dropdown'.*'tabs'"
            $script:GuiContent | Should -Not -Match '\$windowWidth -lt 1000'
            $script:GuiContent | Should -Not -Match "\`$Script:AdaptiveTabMode = 'dropdown'"
        }
    }

    Context 'Adaptive padding thresholds' {
        It 'computes availableTabWidth from PrimaryTabHost or Form' {
            $script:GuiContent | Should -Match '\$availableTabWidth = if \(\$PrimaryTabHost -and \$PrimaryTabHost\.ActualWidth -gt 0\)'
            $script:GuiContent | Should -Match '\[double\]\$PrimaryTabHost\.ActualWidth'
            $script:GuiContent | Should -Match '\[Math\]::Max\(0, \[double\]\$Form\.ActualWidth - 16\)'
        }

        It 'applies wider padding at 1400px+ and compact padding below' {
            $script:GuiContent | Should -Match '\$availableTabWidth -ge 1400'
            # Wide: 16px horizontal padding
            $script:GuiContent | Should -Match '\[System\.Windows\.Thickness\]::new\(16, 6, 16, 6\)'
            # Compact: 8px horizontal padding
            $script:GuiContent | Should -Match '\[System\.Windows\.Thickness\]::new\(8, 6, 8, 6\)'
        }

        It 'applies padding to each TabItem in the loop' {
            $script:GuiContent | Should -Match '\$tabItem\.Padding = \$padding'
        }
    }

    Context 'SizeChanged handler registration' {
        It 'registers the adaptive tab layout script on Form SizeChanged' {
            $script:GuiContent | Should -Match "Register-GuiEventHandler -Source \`$Form -EventName 'SizeChanged'"
            $script:GuiContent | Should -Match '\$Script:AdaptiveTabLayoutScript'
        }

        It 'calls BringIntoView on the selected tab after resize' {
            $script:GuiContent | Should -Match '\$selectedTab\.BringIntoView\(\)'
        }
    }

    Context 'Tab selection and search integration' {
        It 'tracks LastStandardPrimaryTab on tab selection' {
            $script:GuiContent | Should -Match '\$Script:LastStandardPrimaryTab = \[string\]\$selected\.Tag'
        }

        It 'excludes the search results sentinel tag from standard tab tracking' {
            $script:GuiContent | Should -Match "\[string\]\`$selected\.Tag -ne \`$Script:SearchResultsTabTag"
        }

        It 'defines the search results tab tag sentinel' {
            $script:GuiContent | Should -Match "\`$Script:SearchResultsTabTag = '__SEARCH_RESULTS__'"
        }
    }

    Context 'TabManagement.ps1 helper functions' {
        It 'defines Update-PrimaryTabVisuals function' {
            $script:TabMgmtContent | Should -Match 'function Update-PrimaryTabVisuals'
        }

        It 'defines Add-PrimaryTabHoverEffects function' {
            $script:TabMgmtContent | Should -Match 'function Add-PrimaryTabHoverEffects'
        }

        It 'defines Get-PrimaryTabItem function' {
            $script:TabMgmtContent | Should -Match 'function Get-PrimaryTabItem'
        }

        It 'Update-PrimaryTabVisuals applies distinct styling for active vs inactive tabs' {
            $script:TabMgmtContent | Should -Match '\$tab -eq \$PrimaryTabs\.SelectedItem'
            $script:TabMgmtContent | Should -Match 'FontWeight.*SemiBold'
            $script:TabMgmtContent | Should -Match 'FontWeight.*Normal'
        }

        It 'hover effects register MouseEnter, MouseLeave, GotKeyboardFocus, LostKeyboardFocus handlers' {
            $script:TabMgmtContent | Should -Match "Register-GuiEventHandler -Source \`$Tab -EventName 'MouseEnter'"
            $script:TabMgmtContent | Should -Match "Register-GuiEventHandler -Source \`$Tab -EventName 'MouseLeave'"
            $script:TabMgmtContent | Should -Match "Register-GuiEventHandler -Source \`$Tab -EventName 'GotKeyboardFocus'"
            $script:TabMgmtContent | Should -Match "Register-GuiEventHandler -Source \`$Tab -EventName 'LostKeyboardFocus'"
        }

        It 'Initialize-SearchResultsTab is a legacy stub that returns null' {
            $script:TabMgmtContent | Should -Match 'function Initialize-SearchResultsTab'
            $script:TabMgmtContent | Should -Match 'return \$null'
        }
    }
}
