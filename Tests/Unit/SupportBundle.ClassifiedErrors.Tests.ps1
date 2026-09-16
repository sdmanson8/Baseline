Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        if ($fn.Name -in @('Get-BaselineSupportBundleClassifiedErrors')) {
            Invoke-Expression $fn.Extent.Text
        }
    }
}

Describe 'Get-BaselineSupportBundleClassifiedErrors' {
    BeforeEach {
        $script:tempLog = Join-Path ([System.IO.Path]::GetTempPath()) ("baseline-classify-{0}.log" -f ([guid]::NewGuid().ToString('N')))
    }
    AfterEach {
        if ($script:tempLog -and (Test-Path -LiteralPath $script:tempLog)) {
            Remove-Item -LiteralPath $script:tempLog -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns null when log file does not exist' {
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath 'C:/does/not/exist.log'
        $result | Should -BeNullOrEmpty
    }

    It 'returns 0 errors when log has no ERROR/WARNING lines' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 INFO: starting up'
            '01-01-2026 10:01 INFO: did a thing'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Errors.Count | Should -Be 0
    }

    It 'classifies AUTH from an explicit exception type' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 ERROR: failed to set key'
            'Exception type: System.UnauthorizedAccessException'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Errors.Count | Should -Be 1
        $result.Errors[0].Category | Should -Be 'AUTH'
        $result.Counts['AUTH'] | Should -Be 1
    }

    It 'classifies NETWORK from explicit network exception types' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 ERROR: dns lookup failed for github.com'
            'Exception type: System.Net.WebException'
            '01-01-2026 10:01 WARNING: proxy refused authentication'
            'Exception type: System.Net.WebException'
            '01-01-2026 10:02 ERROR: connection timed out'
            'Exception type: System.Net.WebException'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Counts['NETWORK'] | Should -Be 3
    }

    It 'does not infer policy failures from prose' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 ERROR: this setting is managed by your organization'
            '01-01-2026 10:01 ERROR: disabled by your administrator'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Counts['POLICY'] | Should -Be 0
        $result.Counts['UNKNOWN'] | Should -Be 2
    }

    It 'classifies DEPENDENCY from explicit exception types' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 ERROR: module not found: Foo'
            'Exception type: System.Management.Automation.CommandNotFoundException'
            '01-01-2026 10:01 ERROR: cannot find path C:\bar'
            'Exception type: System.IO.FileNotFoundException'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Counts['DEPENDENCY'] | Should -Be 2
    }

    It 'falls back to UNKNOWN for unrecognized patterns' {
        Set-Content -LiteralPath $script:tempLog -Value @(
            '01-01-2026 10:00 ERROR: something completely unexpected happened'
        ) -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog
        $result.Counts['UNKNOWN'] | Should -Be 1
    }

    It 'caps results at MaxErrors' {
        $lines = 1..50 | ForEach-Object { '01-01-2026 10:00 ERROR: access denied #{0}' -f $_ }
        Set-Content -LiteralPath $script:tempLog -Value $lines -Encoding UTF8
        $result = Get-BaselineSupportBundleClassifiedErrors -LogPath $script:tempLog -MaxErrors 10
        $result.Errors.Count | Should -Be 10
        $result.TotalCount | Should -Be 50
        $result.Truncated | Should -BeTrue
    }
}
