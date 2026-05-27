Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:TweakVisualizationPath = Join-Path $PSScriptRoot '../../Module/GUI/TweakVisualization.ps1'
    $script:TweakVisualizationContent = Get-BaselineTestSourceText -Path $script:TweakVisualizationPath
}

Describe 'Search results summary styling' {
    It 'uses the same subtle button chrome as caution details for the inline clear button' {
        $script:TweakVisualizationContent | Should -Match 'Set-ButtonChrome -Button \$clearBtn -Variant ''Subtle'' -Compact'
        $script:TweakVisualizationContent | Should -Match 'New-GuiLabeledIconContent -IconName ''Clear'' .* -Foreground \$clearBtn\.Foreground'
        $script:TweakVisualizationContent | Should -Not -Match '\$clearButtonBackground'
        $script:TweakVisualizationContent | Should -Not -Match '\$clearButtonForeground'
        $script:TweakVisualizationContent | Should -Not -Match '\$clearBtn\.Background = \$bc\.ConvertFromString'
        $script:TweakVisualizationContent | Should -Not -Match '\$clearBtn\.BorderBrush = \$bc\.ConvertFromString'
        $script:TweakVisualizationContent | Should -Not -Match '\$clearBtn\.Foreground = \$bc\.ConvertFromString\(\$accentBlue\)'
    }
}
