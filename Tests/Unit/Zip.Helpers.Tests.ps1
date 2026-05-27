Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $script:RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ZipHelpersPath = Join-Path $script:RepoRoot 'Tools/Zip.Helpers.ps1'
    $script:NewInstallerPackageRawContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Tools/New-InstallerPackage.ps1') -Raw -Encoding UTF8
    $script:NewReleasePackageRawContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Tools/New-ReleasePackage.ps1') -Raw -Encoding UTF8
    $script:NewInstallerPackageContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Tools/New-InstallerPackage.ps1')
    $script:NewReleasePackageContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Tools/New-ReleasePackage.ps1')

    . $script:ZipHelpersPath
}

Describe 'Baseline ZIP helpers' {
    It 'creates UTF-8 NFC entries that validate against local header names' {
        $source = Join-Path $TestDrive 'source'
        $modifierLetterApostrophe = [string][char]0x02BC
        $latinSmallAWithMacron = [string][char]0x0101
        $latinSmallAWithRingAbove = [string][char]0x00E5
        $kiche = 'K' + $modifierLetterApostrophe + 'iche' + $modifierLetterApostrophe
        $maori = 'M' + $latinSmallAWithMacron + 'ori'
        $norwegianBokmal = 'Norwegian Bokm' + $latinSmallAWithRingAbove + 'l'

        New-Item -Path (Join-Path $source $kiche) -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $source $maori) -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $source $norwegianBokmal) -ItemType Directory -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $source ($kiche + '/quc.json')) -Value '{}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $source ($maori + '/mi.json')) -Value '{}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $source ($norwegianBokmal + '/nb.json')) -Value '{}' -Encoding UTF8

        $zipPath = Join-Path $TestDrive 'unicode.zip'
        New-BaselineZipArchive -SourceDirectory $source -DestinationZip $zipPath | Out-Null

        $validation = Test-BaselineZipUnicodeIntegrity -Path $zipPath -ExpectedEntry @(
            ($kiche + '/quc.json')
            ($maori + '/mi.json')
            ($norwegianBokmal + '/nb.json')
        )

        $validation.Success | Should -BeTrue
        $validation.Issues.Count | Should -Be 0
    }

    It 'routes package builders through the shared Unicode-safe ZIP writer' {
        $script:NewInstallerPackageRawContent | Should -Match 'Zip\.Helpers\.ps1'
        $script:NewReleasePackageRawContent | Should -Match 'Zip\.Helpers\.ps1'
        $script:NewInstallerPackageContent | Should -Match 'New-BaselineZipArchive'
        $script:NewReleasePackageContent | Should -Match 'New-BaselineZipArchive'
    }

    It 'does not create or package a nested localization zip' {
        $localizationArchiveScriptName = 'New-Localization' + 'Archive.ps1'

        Test-Path -LiteralPath (Join-Path $script:RepoRoot ('Tools/' + $localizationArchiveScriptName)) | Should -BeFalse
        $script:NewInstallerPackageContent | Should -Not -Match ([regex]::Escape($localizationArchiveScriptName))
        $script:NewReleasePackageContent | Should -Not -Match ([regex]::Escape($localizationArchiveScriptName))
        $script:NewInstallerPackageContent | Should -Not -Match 'Localizations\.zip'
        $script:NewReleasePackageContent | Should -Not -Match 'Localizations\.zip'
    }
}
