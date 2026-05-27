Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $summaryPath = Join-Path $PSScriptRoot '../../Module/GUI/ExecutionSummary.ps1'
    $script:SummaryContent = Get-BaselineTestSourceText -Path $summaryPath
}

Describe 'PlatformSupport unavailable entries surface in run summary (P2 #18c)' {
    # The ExecutionOrchestration availability partition flags unavailable
    # entries with Status='Not applicable' via Set-ExecutionSummaryStatus.
    # ExecutionSummary classifier translates that status to the
    # 'Not applicable on this system' OutcomeState, which the insights
    # aggregator counts into NotApplicableCount, which the counts-text
    # builder renders as "Not applicable: N" in the post-run summary.
    # These pins guard each link in that chain so a refactor cannot drop
    # the user-facing skipped count.

    It 'classifier maps the Not applicable status to the Not-applicable-on-this-system OutcomeState' {
        $script:SummaryContent | Should -Match "'\^\(Not applicable\)\$'"
        $script:SummaryContent | Should -Match "OutcomeState = 'Not applicable on this system'"
    }

    It 'insights aggregator counts both Not-applicable status forms into NotApplicableCount' {
        $script:SummaryContent | Should -Match "OutcomeState -in @\('Not applicable', 'Not applicable on this system'\)"
        $script:SummaryContent | Should -Match 'NotApplicableCount'
    }

    It 'counts-text builder renders the Not applicable count when non-zero' {
        $script:SummaryContent | Should -Match 'if \(\$Insights\.NotApplicableCount -gt 0\) \{ \$parts \+= "Not applicable: \$\(\$Insights\.NotApplicableCount\)" \}'
    }

    It 'next-steps builder explains why the items were skipped (Run mode)' {
        $script:SummaryContent | Should -Match 'were skipped cleanly because they do not apply on this system'
    }
}
