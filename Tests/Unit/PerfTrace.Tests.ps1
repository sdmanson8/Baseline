Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


	$script:PerfTraceContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/PerfTrace.ps1')
	$script:DialogHelpersContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/GUI/DialogHelpers.ps1')
	$script:GuiRegionContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1')
}

Describe 'PerfTrace swallowed-exception routing' {
    It 'routes perf-log initialization and append failures through Write-SwallowedException' {
        $script:PerfTraceContent | Should -Match "Source 'PerfTrace\.TestGuiPerfTraceDebugEnabled\.GetBaselineDebugLogging'"
        $script:PerfTraceContent | Should -Match "Source 'PerfTrace\.InitializeGuiPerfTrace\.WriteSessionHeader'"
        $script:PerfTraceContent | Should -Match "Source 'PerfTrace\.StopGuiPerfScope\.AppendLine'"
    }

    It 'requires Debug Mode before creating perf.log' {
        $script:PerfTraceContent | Should -Match 'function Test-GuiPerfTraceDebugEnabled'
        $script:PerfTraceContent | Should -Match '\$debugEnabled = Test-GuiPerfTraceDebugEnabled'
        $script:PerfTraceContent | Should -Match '\$Script:GuiPerfEnabled = \(\$debugEnabled -and \$perfRequested\)'
        $script:PerfTraceContent | Should -Match "\[System\.Environment\]::GetEnvironmentVariable\('BASELINE_PERF_DETAIL'\)"
        $script:PerfTraceContent | Should -Match 'if \(\$Detailed -and -not \$Script:GuiPerfDetailedEnabled\) \{ return \$null \}'
        $script:PerfTraceContent | Should -Match 'function Set-GuiPerfTraceState'
        $script:PerfTraceContent | Should -Match 'Remove-Item -Path Env:\\BASELINE_PERF_LOG'
    }

	It 'loads PerfTrace from the module root before dialog helpers that depend on it' {
		$script:GuiRegionContent.IndexOf('function Stop-GuiPerfScope') | Should -BeLessThan $script:GuiRegionContent.IndexOf('function Set-ButtonChrome')
		$script:DialogHelpersContent | Should -Match 'Join-Path \$Script:DialogHelpersRoot ''PerfTrace\.ps1'''
		$script:DialogHelpersContent | Should -Not -Match 'Join-Path \$dialogHelpersSplitRoot ''PerfTrace\.ps1'''
	}
}
