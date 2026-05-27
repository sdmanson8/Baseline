Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:TargetFiles = @(
        (Join-Path $PSScriptRoot '../../Module/GUICommon/SettingsStore.ps1')
        (Join-Path $PSScriptRoot '../../Module/SharedHelpers/SupportBundle.Helpers.ps1')
        (Join-Path $PSScriptRoot '../../Module/Regions/ContextMenu.psm1')
        (Join-Path $PSScriptRoot '../../Module/Regions/PostActions.psm1')
    )

    $script:FileContent = @{}
    foreach ($path in $script:TargetFiles) {
        $script:FileContent[$path] = Get-BaselineTestSourceText -Path $path
    }
}

Describe 'Runtime JSON parse depth guards' {
    It 'caps every current production JSON helper call with -Depth' {
        foreach ($path in $script:TargetFiles) {
            $content = $script:FileContent[$path]
            $lines = @($content -split "`r?`n")
            foreach ($line in $lines) {
                if ($line -notmatch 'ConvertFrom-BaselineJson' -or $line -match 'Get-Command') {
                    continue
                }

                $line | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+\d+'
            }
        }
    }

    It 'uses the expected depth for GUI session/profile documents' {
        $guiCommonPath = $script:TargetFiles[0]
        $script:FileContent[$guiCommonPath] | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+12\s+-ErrorAction Stop'
    }

    It 'uses the expected depth for remote orchestration history parsing' {
        $supportBundlePath = $script:TargetFiles[1]
        $script:FileContent[$supportBundlePath] | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+16\s+-ErrorAction Stop'
    }

    It 'uses the expected depth for Windows Terminal settings and post-action capability payloads' {
        $contextMenuPath = $script:TargetFiles[2]
        $postActionsPath = $script:TargetFiles[3]

        $script:FileContent[$contextMenuPath] | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+16'
        $script:FileContent[$postActionsPath] | Should -Match 'ConvertFrom-BaselineJson\s+-Depth\s+4'
    }
}
