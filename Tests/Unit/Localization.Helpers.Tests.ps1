Set-StrictMode -Version Latest

BeforeAll {
    $filePath = Join-Path $PSScriptRoot '../../Module/SharedHelpers/Localization.Helpers.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    foreach ($fn in $functions) {
        if ($fn.Name -in @('Resolve-BaselineLocalizationDirectory', 'Get-BaselineLocalizedString', 'Get-BaselineBilingualString')) {
            Invoke-Expression $fn.Extent.Text
        }
    }

    $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:ExpectedLocalizationPath = Join-Path $script:RepoRoot 'Localizations'
}

Describe 'Resolve-BaselineLocalizationDirectory' {
    It 'finds the localization directory from the repository root' {
        Resolve-BaselineLocalizationDirectory -BasePath $script:RepoRoot | Should -Be $script:ExpectedLocalizationPath
    }

    It 'finds the localization directory from the module root' {
        $moduleRoot = Join-Path $script:RepoRoot 'Module'

        Resolve-BaselineLocalizationDirectory -BasePath $moduleRoot | Should -Be $script:ExpectedLocalizationPath
    }

    It 'finds the localization directory from the GUI region root' {
        $moduleRoot = Join-Path $script:RepoRoot 'Module/Regions'

        Resolve-BaselineLocalizationDirectory -BasePath $moduleRoot | Should -Be $script:ExpectedLocalizationPath
    }

    It 'finds the localization directory from the GUI module root' {
        $moduleRoot = Join-Path $script:RepoRoot 'Module/GUI'

        Resolve-BaselineLocalizationDirectory -BasePath $moduleRoot | Should -Be $script:ExpectedLocalizationPath
    }

    It 'allows empty fallback strings in the localization helpers' {
        $result = Get-BaselineLocalizedString -Key 'Missing_Key' -Fallback ''
        $bilingual = Get-BaselineBilingualString -Key 'Missing_Key' -Fallback ''

        $result | Should -Be ''
        $bilingual | Should -Be ''
    }

    It 'returns visible fallback text and logs the key and culture when a non-English translation is missing' {
        $previousLanguage = [System.Environment]::GetEnvironmentVariable('BASELINE_LANGUAGE')
        $previousLocalizationVariable = Get-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
        $script:WarningMessages = [System.Collections.Generic.List[string]]::new()

        function LogWarning { param([string]$Message) [void]$script:WarningMessages.Add($Message) }

        try {
            [System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', 'fr-FR', [System.EnvironmentVariableTarget]::Process)
            $Global:Localization = @{}

            $result = Get-BaselineLocalizedString -Key 'Missing_Operational_Key' -Fallback 'Visible operational fallback'

            $result | Should -Be 'Visible operational fallback'
            $script:WarningMessages.Count | Should -Be 1
            $script:WarningMessages[0] | Should -Match 'Missing_Operational_Key'
            $script:WarningMessages[0] | Should -Match 'fr-FR'
        }
        finally {
            [System.Environment]::SetEnvironmentVariable('BASELINE_LANGUAGE', $previousLanguage, [System.EnvironmentVariableTarget]::Process)
            if ($previousLocalizationVariable)
            {
                $Global:Localization = $previousLocalizationVariable.Value
            }
            else
            {
                Remove-Variable -Name Localization -Scope Global -ErrorAction SilentlyContinue
            }

            Remove-Variable -Name CachedBaselineMissingLocalizationWarnings -Scope Script -ErrorAction SilentlyContinue
            Remove-Item Function:\LogWarning -ErrorAction SilentlyContinue
        }
    }
}
