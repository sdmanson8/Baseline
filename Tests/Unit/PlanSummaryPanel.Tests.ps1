Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $planSummaryPath = Join-Path $PSScriptRoot '../../Module/GUI/PlanSummaryPanel.ps1'
    $planSummaryRowsPath = Join-Path $PSScriptRoot '../../Module/GUI/PlanSummaryPanel/Show-PlanSummaryDialog/TweakPlanRows.ps1'
    $script:PlanSummaryContent = Get-BaselineTestSourceText -Path $planSummaryPath
    $script:PlanSummaryRowsContent = Get-BaselineTestSourceText -Path $planSummaryRowsPath
}

Describe 'Plan summary panel' {
    It 'routes owner assignment failures through Write-SwallowedException' {
        $script:PlanSummaryContent | Should -Match "PlanSummaryPanel\.ShowPlanSummaryPanel\.SetOwner"
    }

    It 'captures the run label before wiring WPF click delegates' {
        $script:PlanSummaryContent | Should -Match '\$continueLabel = Get-UxRunActionLabel'
        $script:PlanSummaryContent | Should -Match '\$btnContinue\.Content = \$continueLabel'
        $script:PlanSummaryContent | Should -Match '\$continueLabelRef = \$continueLabel'
        $script:PlanSummaryContent | Should -Match '\$resRefContinue\.Value = \$continueLabelRef'
        $script:PlanSummaryContent | Should -Not -Match '\$resRefContinue\.Value = \(Get-UxRunActionLabel\)'
    }

    It 'virtualizes selected tweak rows in the plan summary' {
        $script:PlanSummaryRowsContent | Should -Match '\$planRowsList = New-Object System\.Windows\.Controls\.ListBox'
        $script:PlanSummaryRowsContent | Should -Match 'VirtualizingStackPanel\]::SetIsVirtualizing\(\$planRowsList, \$true\)'
        $script:PlanSummaryRowsContent | Should -Match 'VirtualizingStackPanel\]::SetVirtualizationMode\(\$planRowsList, \[System\.Windows\.Controls\.VirtualizationMode\]::Recycling\)'
        $script:PlanSummaryRowsContent | Should -Match '\$planRowsList\.ItemsSource = \$planRowItems'
        $script:PlanSummaryRowsContent | Should -Match '\$planRowsList\.MaxHeight'
        $script:PlanSummaryRowsContent | Should -Not -Match '\$bodyStack\.Children\.Add\(\$rowBorder\)'
    }
}
