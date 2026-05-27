Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:GuiContent = Get-BaselineTestSourceText -Path (Join-Path $PSScriptRoot '../../Module/Regions/GUI.psm1')
}

Describe 'Updates tab routing' {
    It 'keeps Updates out of the primary tab strip because it is a navigation mode' {
        $script:GuiContent | Should -Not -Match '"Updates"\s+=\s+@\(\)'
    }

    It 'includes the Windows Update policy functions in the routing set' {
        $match = [regex]::Match(
            $script:GuiContent,
            '(?s)foreach \(\s*\$functionName in @\((?<List>.*?)\)\s*\)'
        )

        $match.Success | Should -Be $true

        $functionNames = [regex]::Matches($match.Groups['List'].Value, "'([^']+)'") | ForEach-Object {
            $_.Groups[1].Value
        }

        foreach ($name in @(
            'MapUpdates'
            'UpdateMSRT'
            'UpdateNotificationLevel'
            'WindowsUpdate'
            'WindowsUpdateDisableAll'
        ))
        {
            $functionNames | Should -Contain $name
        }
    }

    It 'keeps app-update and repair-only helpers out of the Updates routing set' {
        $match = [regex]::Match(
            $script:GuiContent,
            '(?s)foreach \(\s*\$functionName in @\((?<List>.*?)\)\s*\)'
        )

        $functionNames = [regex]::Matches($match.Groups['List'].Value, "'([^']+)'") | ForEach-Object {
            $_.Groups[1].Value
        }

        foreach ($name in @(
            'AppUpdate'
            'DefenderSignatureUpdateInterval'
            'Invoke-ChocoUpdate'
            'Invoke-WingetUpdate'
            'Windows11SMBUpdateIssue'
        ))
        {
            $functionNames | Should -Not -Contain $name
        }
    }
}
