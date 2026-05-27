Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Join-Path $PSScriptRoot '../..'
    $script:TemplateDir = Resolve-Path (Join-Path $repoRoot '.github/ISSUE_TEMPLATE') -ErrorAction Stop
    $script:ConfigPath = Join-Path $script:TemplateDir 'config.yml'
    $script:BugPath = Join-Path $script:TemplateDir 'bug_report.yaml'
    $script:FeaturePath = Join-Path $script:TemplateDir 'feature_request.yaml'
}

Describe 'GitHub issue templates exist' {
    It 'has a config.yml' {
        Test-Path -LiteralPath $script:ConfigPath | Should -BeTrue
    }
    It 'has a bug_report.yaml' {
        Test-Path -LiteralPath $script:BugPath | Should -BeTrue
    }
    It 'has a feature_request.yaml' {
        Test-Path -LiteralPath $script:FeaturePath | Should -BeTrue
    }
}

Describe 'config.yml disables blank issues' {
    It 'sets blank_issues_enabled: false' {
        $content = [System.IO.File]::ReadAllText($script:ConfigPath)
        $content | Should -Match 'blank_issues_enabled:\s*false'
    }
}

Describe 'bug_report.yaml has the required Baseline-specific fields' {
    BeforeAll {
        $script:BugContent = [System.IO.File]::ReadAllText($script:BugPath)
    }
    It 'asks for Baseline version' {
        $script:BugContent | Should -Match 'id:\s*baseline-version'
    }
    It 'asks for Windows build' {
        $script:BugContent | Should -Match 'id:\s*windows-build'
    }
    It 'has an applied tweaks / preset textarea' {
        $script:BugContent | Should -Match 'id:\s*applied-tweaks'
    }
    It 'mentions the support bundle export path' {
        $script:BugContent | Should -Match 'Export Support Bundle'
        $script:BugContent | Should -Match 'id:\s*support-bundle'
    }
    It 'points to %LOCALAPPDATA%\\Baseline daily log path' {
        $script:BugContent | Should -Match '%LOCALAPPDATA%\\Baseline'
    }
    It 'mentions the perf trace path when Debug Mode is on' {
        $script:BugContent | Should -Match 'BASELINE_PERF_LOG'
        $script:BugContent | Should -Match 'perf\.log'
    }
    It 'forces a search-for-duplicates pre-flight check' {
        $script:BugContent | Should -Match 'searched existing issues'
    }
}

Describe 'feature_request.yaml has the required structure' {
    BeforeAll {
        $script:FeatureContent = [System.IO.File]::ReadAllText($script:FeaturePath)
    }
    It 'asks what problem the feature solves' {
        $script:FeatureContent | Should -Match 'id:\s*problem'
    }
    It 'asks for a proposed solution' {
        $script:FeatureContent | Should -Match 'id:\s*proposal'
    }
    It 'asks which Baseline surface is affected' {
        $script:FeatureContent | Should -Match 'id:\s*surface'
    }
}
