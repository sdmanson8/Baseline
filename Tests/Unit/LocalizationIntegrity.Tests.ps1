Set-StrictMode -Version Latest

# Pester resolves -ForEach during discovery, so the locale case list must exist
# before BeforeAll runs. The source data itself is loaded inside BeforeAll.
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localizationDir = Join-Path $repoRoot 'Localizations'
$sourceFileName = 'en-US.json'
$localeFilePattern = '^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\.json$'

$script:LocaleCases = @(
    Get-ChildItem -LiteralPath $localizationDir -Recurse -Filter '*.json' -File | Where-Object {
        $_.Name -match $localeFilePattern -and $_.Name -notin @($sourceFileName, 'en-GB.json')
    } | Sort-Object Name | ForEach-Object {
        @{
            LocaleName = $_.Name
            LocalePath = $_.FullName
            LocaleCode = $_.BaseName
            LocaleDirectory = $_.Directory.Name
        }
    }
)

$script:AllLocaleCases = @(
    Get-ChildItem -LiteralPath $localizationDir -Recurse -Filter '*.json' -File | Where-Object {
        $_.Name -match $localeFilePattern
    } | Sort-Object FullName | ForEach-Object {
        @{
            LocaleName = $_.Name
            LocalePath = $_.FullName
            LocaleCode = $_.BaseName
            LocaleDirectory = $_.Directory.Name
        }
    }
)

Describe 'Localization key-set integrity' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $script:LocalizationDir = Join-Path $script:RepoRoot 'Localizations'
        $script:SourceFileName = 'en-US.json'
        $sourceMatches = @(Get-ChildItem -LiteralPath $script:LocalizationDir -Recurse -File -Filter 'en-US.json' -ErrorAction SilentlyContinue)
        if ($sourceMatches.Count -ne 1) { throw "Localization file 'en-US.json' not found uniquely under '$script:LocalizationDir'." }
        $script:SourcePath = $sourceMatches[0].FullName

        $sourceLikeMatches = @(Get-ChildItem -LiteralPath $script:LocalizationDir -Recurse -File -Filter 'en-GB.json' -ErrorAction SilentlyContinue)
        if ($sourceLikeMatches.Count -ne 1) { throw "Localization file 'en-GB.json' not found uniquely under '$script:LocalizationDir'." }
        $script:SourceLikePath = $sourceLikeMatches[0].FullName

        $script:LocalizationSchemaPath = Join-Path $script:LocalizationDir 'localization_schema.json'
        $script:LocaleMapPath = Join-Path $script:LocalizationDir 'locale-map.json'

        $script:SourceMap = Get-BaselineTestSourceText -Path $script:SourcePath | ConvertFrom-Json -ErrorAction Stop
        $script:SourceKeys = @($script:SourceMap.PSObject.Properties.Name)
        $script:SourceKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($key in $script:SourceKeys)
        {
            [void]$script:SourceKeySet.Add([string]$key)
        }

        $sortedSourceKeys = [string[]]@($script:SourceKeys | ForEach-Object { [string]$_ })
        [System.Array]::Sort($sortedSourceKeys, [System.StringComparer]::Ordinal)
        $sourcePayload = [System.Text.Encoding]::UTF8.GetBytes(($sortedSourceKeys -join "`n"))
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try
        {
            $sourceHashBytes = $sha256.ComputeHash($sourcePayload)
        }
        finally
        {
            $sha256.Dispose()
        }

        $script:SourceKeyHash = (($sourceHashBytes | ForEach-Object { $_.ToString('x2') }) -join '')

        # PowerShell 5.1 ships ConvertFrom-Json without -AsHashtable, so we
        # parse to PSObject and project to a hashtable manually. Keeps the
        # downstream indexer access (e.g. $LocalizationSchema['key_hash'])
        # identical across supported Windows PowerShell 5.1 runs.
        $convertToHashtable = {
            param($Object)
            $h = @{}
            if ($null -eq $Object) { return $h }
            foreach ($prop in $Object.PSObject.Properties)
            {
                $h[[string]$prop.Name] = $prop.Value
            }
            return $h
        }

        $schemaObj = Get-BaselineTestSourceText -Path $script:LocalizationSchemaPath | ConvertFrom-Json -ErrorAction Stop
        $localeMapObj = Get-BaselineTestSourceText -Path $script:LocaleMapPath | ConvertFrom-Json -ErrorAction Stop
        $script:LocalizationSchema = & $convertToHashtable $schemaObj
        $script:LocaleMap = & $convertToHashtable $localeMapObj
    }

    It 'keeps the canonical source schema for en-US.json' {
        [string]$script:LocalizationSchema['source_file'] | Should -Be 'en-US.json'
        [int]$script:LocalizationSchema['key_count'] | Should -Be $script:SourceKeys.Count
        [string]$script:LocalizationSchema['hash_algorithm'] | Should -Be 'sha256'
        [string]$script:LocalizationSchema['key_hash'] | Should -Be $script:SourceKeyHash
    }

    It 'keeps the canonical source schema for en-GB.json' {
        $sourceLikeMap = Get-BaselineTestSourceText -Path $script:SourceLikePath | ConvertFrom-Json -ErrorAction Stop
        $sourceLikeKeys = @($sourceLikeMap.PSObject.Properties.Name)
        $sortedSourceLikeKeys = [string[]]@($sourceLikeKeys | ForEach-Object { [string]$_ })
        [System.Array]::Sort($sortedSourceLikeKeys, [System.StringComparer]::Ordinal)
        $sourceLikePayload = [System.Text.Encoding]::UTF8.GetBytes(($sortedSourceLikeKeys -join "`n"))
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try
        {
            $sourceLikeHashBytes = $sha256.ComputeHash($sourceLikePayload)
        }
        finally
        {
            $sha256.Dispose()
        }
        $sourceLikeHash = (($sourceLikeHashBytes | ForEach-Object { $_.ToString('x2') }) -join '')

        $sourceLikeKeys.Count | Should -Be $script:SourceKeys.Count
        $sourceLikeHash | Should -Be $script:SourceKeyHash
    }

    It '<LocaleName> lives in the mapped directory' -ForEach $script:LocaleCases {
        [string]$script:LocaleMap[$LocaleCode] | Should -Be $LocaleDirectory
    }

    It 'uses ASCII-safe locale directory names for release package portability' {
        $nonAsciiDirectories = @(
            Get-ChildItem -LiteralPath $script:LocalizationDir -Directory |
                Where-Object { $_.Name -match '[^\x00-\x7F]' } |
                ForEach-Object { $_.Name }
        )

        $nonAsciiDirectories | Should -BeNullOrEmpty -Because 'locale directories are embedded in release zips and must extract consistently on non-UTF-8 tools.'
    }

    It '<LocaleName> preserves every source key' -ForEach $script:LocaleCases {
        $localeMap = Get-BaselineTestSourceText -Path $LocalePath | ConvertFrom-Json -ErrorAction Stop
        $localeKeys = @($localeMap.PSObject.Properties.Name)
        $localeKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($key in $localeKeys)
        {
            [void]$localeKeySet.Add([string]$key)
        }

        $missingKeys = @($script:SourceKeys | Where-Object { -not $localeKeySet.Contains([string]$_) })
        $extraKeys = @($localeKeys | Where-Object { -not $script:SourceKeySet.Contains([string]$_) })

        $missingKeys | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' must never drop canonical keys."
        $extraKeys | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' must not invent keys outside the canonical source set."
    }
}

Describe 'Runtime localization source coverage' {
    BeforeAll {
        $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
        if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
        . $sourceContentHelperPath

        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $script:LocalizationDir = Join-Path $script:RepoRoot 'Localizations'
        $sourcePath = Join-Path $script:LocalizationDir 'English (United States)/en-US.json'
        $sourceMap = Get-BaselineTestSourceText -Path $sourcePath | ConvertFrom-Json -ErrorAction Stop
        $script:RuntimeSourceKeys = @($sourceMap.PSObject.Properties.Name)
        $script:RuntimeSourceKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($key in $script:RuntimeSourceKeys)
        {
            [void]$script:RuntimeSourceKeySet.Add([string]$key)
        }

        $todoPath = Join-Path $script:RepoRoot 'todo.md'
        $script:TodoLocalizationKeys = @()
        if (Test-Path -LiteralPath $todoPath -PathType Leaf)
        {
            $todoContent = Get-BaselineTestSourceText -Path $todoPath
            $script:TodoLocalizationKeys = @(
                [regex]::Matches($todoContent, '(?m)^(Bootstrap|Progress)_[A-Za-z0-9_]+$') |
                    ForEach-Object { [string]$_.Value } |
                    Sort-Object -Unique
            )
        }

        $script:RuntimeLocalizationCallKeys = [System.Collections.Generic.List[object]]::new()
        foreach ($rootName in @('Bootstrap', 'Module'))
        {
            $rootPath = Join-Path $script:RepoRoot $rootName
            if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }

            foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -Recurse -Include '*.ps1','*.psm1' -File -ErrorAction SilentlyContinue))
            {
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
                if ($parseErrors -and $parseErrors.Count -gt 0) { continue }

                $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($cmd in $commands)
                {
                    $commandName = $cmd.GetCommandName()
                    if ($commandName -notin @('Get-BaselineLocalizedString', 'Get-BaselineBilingualString')) { continue }

                    $elements = @($cmd.CommandElements)
                    $literalKey = $null
                    $literalFallback = $null
                    $hasLiteralFallback = $false
                    for ($i = 1; $i -lt $elements.Count; $i++)
                    {
                        $element = $elements[$i]
                        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

                        $parameterName = [string]$element.ParameterName
                        if ($parameterName -notin @('Key', 'Fallback')) { continue }

                        $valueAst = $element.Argument
                        if ($null -eq $valueAst -and ($i + 1) -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst])
                        {
                            $i++
                            $valueAst = $elements[$i]
                        }

                        if ($valueAst -is [System.Management.Automation.Language.StringConstantExpressionAst])
                        {
                            if ($parameterName -eq 'Key')
                            {
                                $literalKey = [string]$valueAst.Value
                            }
                            elseif ($parameterName -eq 'Fallback')
                            {
                                $literalFallback = [string]$valueAst.Value
                                $hasLiteralFallback = $true
                            }
                        }
                    }

                    if ($null -ne $literalKey)
                    {
                        [void]$script:RuntimeLocalizationCallKeys.Add([pscustomobject]@{
                            Key                = $literalKey
                            File               = $file.FullName.Substring($script:RepoRoot.Length + 1)
                            Line               = $cmd.Extent.StartLineNumber
                            Fallback           = $literalFallback
                            HasLiteralFallback = $hasLiteralFallback
                        })
                    }
                }
            }
        }
    }

    It 'keeps every literal runtime Baseline localization key in en-US.json' {
        $missingRuntimeKeys = @(
            $script:RuntimeLocalizationCallKeys |
                Where-Object { -not $script:RuntimeSourceKeySet.Contains([string]$_.Key) } |
                Sort-Object Key, File, Line |
                ForEach-Object { '{0} ({1}:{2})' -f $_.Key, $_.File, $_.Line }
        )

        $missingRuntimeKeys | Should -BeNullOrEmpty -Because "literal runtime localization keys must exist in en-US.json: $($missingRuntimeKeys -join '; ')"
    }

    It 'keeps every explicit todo.md runtime localization key in en-US.json' {
        $missingTodoKeys = @(
            $script:TodoLocalizationKeys |
                Where-Object { -not $script:RuntimeSourceKeySet.Contains([string]$_) }
        )

        $script:TodoLocalizationKeys.Count | Should -BeGreaterThan 0 -Because 'todo.md must expose the audited runtime localization key list.'
        $missingTodoKeys | Should -BeNullOrEmpty -Because "todo.md runtime localization keys must exist in en-US.json: $($missingTodoKeys -join ', ')"
    }

    It 'keeps operational runtime localization fallbacks visible' {
        $emptyOperationalFallbacks = @(
            $script:RuntimeLocalizationCallKeys |
                Where-Object {
                    [string]$_.Key -match '^(Bootstrap|Progress)_' -and
                    [bool]$_.HasLiteralFallback -and
                    [string]::IsNullOrWhiteSpace([string]$_.Fallback)
                } |
                Sort-Object Key, File, Line |
                ForEach-Object { '{0} ({1}:{2})' -f $_.Key, $_.File, $_.Line }
        )

        $emptyOperationalFallbacks | Should -BeNullOrEmpty -Because "operational/progress keys need visible English fallback text: $($emptyOperationalFallbacks -join '; ')"
    }
}

Describe 'Localization value integrity' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $script:LocalizationDir = Join-Path $script:RepoRoot 'Localizations'
        $script:ExemptKeysPath = Join-Path $script:LocalizationDir 'english_exempt_keys.json'

        $script:ExemptKeys = @()
        if (Test-Path -LiteralPath $script:ExemptKeysPath -PathType Leaf)
        {
            $exemptData = Get-BaselineTestSourceText -Path $script:ExemptKeysPath | ConvertFrom-Json -ErrorAction Stop
            if ($exemptData -is [System.Collections.IDictionary])
            {
                $script:ExemptKeys = @($exemptData.Keys)
            }
            elseif ($exemptData -is [pscustomobject])
            {
                $script:ExemptKeys = @($exemptData.PSObject.Properties | ForEach-Object { $_.Name })
            }
            else
            {
                $script:ExemptKeys = @($exemptData)
            }
        }

        $script:ExemptKeys = @(
            $script:ExemptKeys |
                Where-Object { $_ } |
                Sort-Object -Unique
        )

        function Test-LocalizedFormatString {
            param([string]$Value)

            $argumentCount = 0
            $formatMatches = @([regex]::Matches($Value, '\{([0-9]+)(?:,[^{}]+)?(?::[^{}]+)?\}'))
            if ($formatMatches.Count -gt 0)
            {
                $maxIndex = 0
                foreach ($match in $formatMatches)
                {
                    $index = [int]$match.Groups[1].Value
                    if ($index -gt $maxIndex)
                    {
                        $maxIndex = $index
                    }
                }
                $argumentCount = $maxIndex + 1
            }

            $formatArguments = New-Object object[] $argumentCount
            for ($i = 0; $i -lt $argumentCount; $i++)
            {
                $formatArguments[$i] = $i
            }

            [void][string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $Value, $formatArguments)
        }

        function New-ProtectedBrandZeroWidthPattern {
            param([string]$Brand)

            $zeroWidth = '[\u200B\u200C\u200D\u2060\uFEFF]'
            $chars = $Brand.ToCharArray() | ForEach-Object { [regex]::Escape([string]$_) }
            return '(?i)' + ($chars -join "$zeroWidth*")
        }

        $script:ZeroWidthCharacterPattern = '[\u200B\u200C\u200D\u2060\uFEFF]'
        $script:ControlCharacterPattern = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'
        $script:ProtectedBrandPatterns = @{}
        foreach ($brand in @('Adobe', 'Microsoft', 'WinGet', 'Chocolatey', 'PowerShell'))
        {
            $script:ProtectedBrandPatterns[$brand] = New-ProtectedBrandZeroWidthPattern -Brand $brand
        }
    }

    It '<LocaleName> does not contain empty translations outside the exemption list' -ForEach $script:LocaleCases {
        $localeMap = Get-BaselineTestSourceText -Path $LocalePath | ConvertFrom-Json -ErrorAction Stop
        $emptyKeys = @(
            $localeMap.PSObject.Properties |
                Where-Object {
                    [string]::IsNullOrWhiteSpace([string]$_.Value) -and
                    ($_.Name -notin $script:ExemptKeys)
                } |
                ForEach-Object { $_.Name }
        )

        $emptyKeys | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' must not contain empty translations for non-exempt keys."
    }

    It '<LocaleName> has runtime-valid .NET format strings' -ForEach $script:LocaleCases {
        $localeMap = Get-BaselineTestSourceText -Path $LocalePath | ConvertFrom-Json -ErrorAction Stop
        $formatErrors = foreach ($prop in $localeMap.PSObject.Properties)
        {
            try
            {
                Test-LocalizedFormatString -Value ([string]$prop.Value)
            }
            catch
            {
                "{0}: {1}" -f $prop.Name, $_.Exception.Message
            }
        }

        $formatErrors = @($formatErrors)
        $formatErrors | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' contains strings that can throw during .NET formatting: $($formatErrors -join '; ')"
    }

    It '<LocaleName> has no control characters or zero-width protected brand names' -ForEach $script:AllLocaleCases {
        $rawText = Get-BaselineTestSourceText -Path $LocalePath
        $controlCharacterFindings = @(
            [regex]::Matches($rawText, $script:ControlCharacterPattern) |
                ForEach-Object { 'offset {0}' -f $_.Index }
        )

        $localeMap = $rawText | ConvertFrom-Json -ErrorAction Stop
        $protectedBrandFindings = foreach ($prop in $localeMap.PSObject.Properties)
        {
            $value = [string]$prop.Value
            foreach ($brand in $script:ProtectedBrandPatterns.Keys)
            {
                $brandMatches = [regex]::Matches($value, [string]$script:ProtectedBrandPatterns[$brand])
                foreach ($brandMatch in $brandMatches)
                {
                    if ($brandMatch.Value -match $script:ZeroWidthCharacterPattern)
                    {
                        '{0}: {1}' -f $prop.Name, $brand
                    }
                }
            }
        }

        $controlCharacterFindings | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' must not contain JSON control characters outside standard whitespace: $($controlCharacterFindings -join '; ')"
        @($protectedBrandFindings) | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' must not split protected brand names with zero-width characters: $($protectedBrandFindings -join '; ')"
    }
}

Describe 'Localization string-overflow guard' {
    BeforeAll {
    $sourceContentHelperPath = Join-Path $PSScriptRoot 'Support/SourceContent.Helpers.ps1'
    if (-not (Test-Path -LiteralPath $sourceContentHelperPath)) { $sourceContentHelperPath = Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1' }
    . $sourceContentHelperPath


        $script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $script:LocalizationDir = Join-Path $script:RepoRoot 'Localizations'
        $script:StringLengthLimitsPath = Join-Path $script:LocalizationDir 'string_length_limits.json'

        $script:StringLengthLimits = @{}
        if (Test-Path -LiteralPath $script:StringLengthLimitsPath -PathType Leaf)
        {
            $limitData = Get-BaselineTestSourceText -Path $script:StringLengthLimitsPath | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $limitData.PSObject.Properties)
            {
                if ($prop.Name.StartsWith('_')) { continue }
                $script:StringLengthLimits[[string]$prop.Name] = [int]$prop.Value
            }
        }
    }

    It 'has a non-empty length-limit configuration' {
        $script:StringLengthLimits.Count | Should -BeGreaterThan 0 -Because 'string_length_limits.json must define at least one tight UI slot to guard against overflow.'
    }

    It '<LocaleName> respects every declared UI slot length limit' -ForEach $script:LocaleCases {
        $localeMap = Get-BaselineTestSourceText -Path $LocalePath | ConvertFrom-Json -ErrorAction Stop
        $overflows = foreach ($key in $script:StringLengthLimits.Keys)
        {
            $prop = $localeMap.PSObject.Properties[$key]
            if ($null -eq $prop) { continue }
            $value = [string]$prop.Value
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $limit = [int]$script:StringLengthLimits[$key]
            if ($value.Length -gt $limit)
            {
                "{0} = '{1}' ({2} chars, limit {3})" -f $key, $value, $value.Length, $limit
            }
        }

        $overflows = @($overflows)
        $overflows | Should -BeNullOrEmpty -Because "Locale file '$LocaleName' has translations that exceed declared UI slot widths and will overflow the control: $($overflows -join '; ')"
    }
}
