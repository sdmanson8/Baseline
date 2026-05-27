Set-StrictMode -Version Latest

BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


    $filePath = Join-Path $PSScriptRoot '../../Tools/New-InstallerPackage.ps1'
    $script:RepoRoot = Split-Path -Path (Split-Path -Path $filePath -Parent) -Parent
    $script:OriginalRepoRootVariable = Get-Variable -Name repoRoot -Scope Script -ErrorAction SilentlyContinue
    $script:OriginalBaselineLanguage = [System.Environment]::GetEnvironmentVariable('BASELINE_LANGUAGE', 'Process')

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functions) {
        Invoke-Expression $fn.Extent.Text
    }
}

AfterAll {
    [System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', $script:OriginalBaselineLanguage, 'Process')
    if ($script:OriginalRepoRootVariable)
    {
        Set-Variable -Name repoRoot -Scope Script -Value $script:OriginalRepoRootVariable.Value
    }
    else
    {
        Remove-Variable -Name repoRoot -Scope Script -ErrorAction SilentlyContinue
    }
}

Describe 'Get-InstallerLocalizationSource' {
    BeforeEach {
        $script:LocalizationRoot = Join-Path $TestDrive 'Localizations'
        $englishDir = Join-Path $script:LocalizationRoot 'English (United States)'
        $frenchDir = Join-Path $script:LocalizationRoot 'French'

        New-Item -ItemType Directory -Path $englishDir -Force | Out-Null
        New-Item -ItemType Directory -Path $frenchDir -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $englishDir 'en-US.json') -Encoding UTF8 -Value @'
{
  "Installer_LangPage_Title": "Choose Language",
  "Installer_LangPage_Desc": "Choose the display language for Baseline."
}
'@

        Set-Content -LiteralPath (Join-Path $frenchDir 'fr.json') -Encoding UTF8 -Value @'
{
  "Installer_LangPage_Title": "Choisir la langue"
}
'@
    }

    It 'uses explicit locale translations and seeds missing non-English strings from english source text' {
        $result = Get-InstallerLocalizationSource -UICulture 'fr-FR' -RepoRoot $script:RepoRoot -LocalizationRoot $script:LocalizationRoot

        $result['LangPage.Title'] | Should -Be 'Choisir la langue'
        $result['LangPage.Desc'] | Should -Be 'Choose the display language for Baseline.'
        $result['Btn.Next'] | Should -Be 'Next >'
    }

    It 'keeps english fallback strings for english cultures' {
        $result = Get-InstallerLocalizationSource -UICulture 'en-US' -RepoRoot $script:RepoRoot -LocalizationRoot $script:LocalizationRoot

        $result['LangPage.Title'] | Should -Be 'Choose Language'
        $result['LangPage.Desc'] | Should -Be 'Choose the display language for Baseline.'
        $result['Btn.Next'] | Should -Be 'Next >'
    }
}

Describe 'Initialize-InstallerLocalizationWorkspace' {
    BeforeEach {
        $script:LocalizationRoot = Join-Path $TestDrive 'Localizations'
        $englishDir = Join-Path $script:LocalizationRoot 'English (United States)'
        $frenchDir = Join-Path $script:LocalizationRoot 'French'

        New-Item -ItemType Directory -Path $englishDir -Force | Out-Null
        New-Item -ItemType Directory -Path $frenchDir -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $frenchDir 'fr.json') -Encoding UTF8 -Value @'
{
  "Installer_LangPage_Title": "Choisir la langue",
  "Installer_Btn_Next": "Suivant >"
}
'@
    }

    It 'writes locale-specific installer files with english source text for missing translations' {
        $workspaceRoot = Join-Path $TestDrive 'installer-workspace'
        $sourceMap = Get-InstallerLocalizationSource -UICulture 'en-US' -RepoRoot $script:RepoRoot -LocalizationRoot $script:LocalizationRoot

        Initialize-InstallerLocalizationWorkspace `
            -Root $workspaceRoot `
            -SourceMap $sourceMap `
            -LocaleCodes @('en', 'fr', 'de') `
            -RepoRoot $script:RepoRoot `
            -LocalizationRoot $script:LocalizationRoot | Out-Null

        $englishJson = Get-BaselineTestSourceText -Path (Join-Path $workspaceRoot 'en.json') | ConvertFrom-Json
        $frenchJson = Get-BaselineTestSourceText -Path (Join-Path $workspaceRoot 'fr.json') | ConvertFrom-Json
        $germanJson = Get-BaselineTestSourceText -Path (Join-Path $workspaceRoot 'de.json') | ConvertFrom-Json

        $englishJson.'LangPage.Title' | Should -Be 'Choose Language'
        $frenchJson.'LangPage.Title' | Should -Be 'Choisir la langue'
        $frenchJson.'Btn.Next' | Should -Be 'Suivant >'
        $frenchJson.'LangPage.Desc' | Should -Be 'Choose the display language for Baseline.'
        $germanJson.'LangPage.Title' | Should -Be 'Choose Language'
        $germanJson.'Btn.Next' | Should -Be 'Next >'
    }
}

Describe 'Installer localization encoding guards' {
    It 'reads UTF-8 no-BOM installer locale text without mojibake' {
        $path = Join-Path $TestDrive 'utf8-no-bom.json'
        $expected = '{"value":"' + [string][char]0x00EF + ' ' + [string][char]0x9009 + [string][char]0x62E9 + '"}'
        $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
        [System.IO.File]::WriteAllText($path, $expected, $utf8NoBom)

        Read-InstallerUtf8Text -Path $path | Should -Be $expected
    }

    It 'fails generated installer text that contains mojibake markers' {
        $badText = 'ge' + [string][char]0x00C3 + [string][char]0x00AF + 'nstalleer'

        { Assert-InstallerTextEncodingClean -Text $badText -Context 'test installer text' } |
            Should -Throw 'test installer text contains mojibake marker*'
    }
}

Describe 'Assert-InstallerLocalizationWorkspaceComplete' {
    BeforeEach {
        $script:WorkspaceRoot = Join-Path $TestDrive 'installer-locale-cache'
        New-Item -ItemType Directory -Path $script:WorkspaceRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'en.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "Choose Language",
  "Btn.Next": "Next >"
}
'@
    }

    It 'accepts complete translated installer locale files' {
        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'fr.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "Choisir la langue",
  "Btn.Next": "Suivant >"
}
'@

        { Assert-InstallerLocalizationWorkspaceComplete -Root $script:WorkspaceRoot } | Should -Not -Throw
    }

    It 'rejects blank non-English installer values' {
        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'fr.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "",
  "Btn.Next": "Suivant >"
}
'@

        { Assert-InstallerLocalizationWorkspaceComplete -Root $script:WorkspaceRoot } |
            Should -Throw "*blank value for 'LangPage.Title'*"
    }

    It 'rejects non-English installer values that still match English' {
        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'fr.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "Choose Language",
  "Btn.Next": "Suivant >"
}
'@

        { Assert-InstallerLocalizationWorkspaceComplete -Root $script:WorkspaceRoot } |
            Should -Throw "*still matches English source for 'LangPage.Title'*"
    }

    It 'rejects mojibake in non-English installer values' {
        $badTitle = 'ge' + [string][char]0x00C3 + [string][char]0x00AF + 'nstalleer'
        $localeMap = [ordered]@{
            'LangPage.Title' = $badTitle
            'Btn.Next' = 'Suivant >'
        }
        $localeMap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'fr.json') -Encoding UTF8

        { Assert-InstallerLocalizationWorkspaceComplete -Root $script:WorkspaceRoot } |
            Should -Throw "*mojibake marker*"
    }
}

Describe 'Invoke-InstallerLocalizationTranslation' {
    BeforeEach {
        $script:repoRoot = Join-Path $TestDrive 'Repo'
        $script:WorkspaceRoot = Join-Path $TestDrive 'installer-localization'
        New-Item -ItemType Directory -Path $script:WorkspaceRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'en.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "Choose Language"
}
'@
        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot 'fr.json') -Encoding UTF8 -Value @'
{
  "LangPage.Title": "Choose Language"
}
'@
    }

    It 'fails closed on a missing translation cache unless refresh is explicitly requested' {
        { Invoke-InstallerLocalizationTranslation -Root $script:WorkspaceRoot } |
            Should -Throw '*Installer localization cache is missing or invalid*RefreshInstallerTranslations*'
    }
}
