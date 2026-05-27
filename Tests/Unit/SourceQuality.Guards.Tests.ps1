Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ModuleRoot = Join-Path $script:RepoRoot 'Module'
    . (Join-Path $PSScriptRoot '../Support/SourceContent.Helpers.ps1')

    function Get-SourceFile {
        param(
            [string[]]$Include = @('*.ps1', '*.psm1')
        )

        Get-ChildItem -LiteralPath $script:ModuleRoot -Recurse -File -Include $Include |
            Where-Object { $_.FullName -notmatch '\\vendor\\' }
    }

    function Get-RepoPowerShellFile {
        param(
            [string[]]$Roots = @('Module', 'Tools', 'Bootstrap', 'Tests')
        )

        $files = @()
        foreach ($rootName in $Roots) {
            $rootPath = Join-Path $script:RepoRoot $rootName
            if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
                continue
            }

            $files += Get-ChildItem -LiteralPath $rootPath -Recurse -File |
                Where-Object {
                    $_.Extension -in @('.ps1', '.psm1') -and
                    $_.FullName -notmatch '\\vendor\\'
                }
        }

        return @($files)
    }

    function Get-ModuleFunctionDuplicateSignature {
        $definitions = New-Object System.Collections.Generic.List[object]
        foreach ($file in Get-RepoPowerShellFile -Roots @('Module')) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($functionAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)) {
                $definitions.Add([pscustomobject]@{
                    Name = $functionAst.Name
                    Path = Get-RelativeSourcePath -Path $functionAst.Extent.File
                })
            }
        }

        foreach ($group in ($definitions | Group-Object Name | Where-Object Count -gt 1 | Sort-Object Name)) {
            $paths = @($group.Group | Sort-Object Path | ForEach-Object { $_.Path })
            '{0}|{1}|{2}' -f $group.Name, $group.Count, ($paths -join ';')
        }
    }

    function Get-OversizedFunctionSignature {
        param(
            [int]$MaximumLines = 400
        )

        foreach ($file in Get-RepoPowerShellFile -Roots @('Module', 'Tools', 'Bootstrap', 'Tests')) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }
            $sourceLines = [System.IO.File]::ReadAllLines($file.FullName)

            foreach ($functionAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)) {
                $excludedLines = New-Object 'System.Collections.Generic.HashSet[int]'
                foreach ($nestedPayload in @($functionAst.FindAll({
                    param($node)
                    ($node -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) -or
                        ($node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.StringConstantType -match 'HereString')
                }, $true))) {
                    for ($line = $nestedPayload.Extent.StartLineNumber; $line -le $nestedPayload.Extent.EndLineNumber; $line++) {
                        [void]$excludedLines.Add($line)
                    }
                }

                $lineCount = 0
                $inBlockComment = $false
                for ($lineNumber = $functionAst.Extent.StartLineNumber; $lineNumber -le $functionAst.Extent.EndLineNumber; $lineNumber++) {
                    if ($excludedLines.Contains($lineNumber)) {
                        continue
                    }

                    $trimmedLine = $sourceLines[$lineNumber - 1].Trim()
                    if ($inBlockComment) {
                        if ($trimmedLine -match '#>') {
                            $inBlockComment = $false
                        }
                        continue
                    }
                    if ($trimmedLine -match '^<#') {
                        if ($trimmedLine -notmatch '#>') {
                            $inBlockComment = $true
                        }
                        continue
                    }
                    if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('#') -or $trimmedLine -match '^[\{\}\)\]\.;]+$') {
                        continue
                    }

                    $lineCount++
                }

                if ($lineCount -gt $MaximumLines) {
                    '{0}:{1}:{2}:{3}' -f (Get-RelativeSourcePath -Path $functionAst.Extent.File), $functionAst.Extent.StartLineNumber, $functionAst.Name, $lineCount
                }
            }
        }
    }

    function Get-RelativeSourcePath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        return ([System.IO.Path]::GetFullPath($Path).Substring($script:RepoRoot.Length + 1) -replace '/', '\')
    }

    function Find-SourcePattern {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Pattern,

            [System.IO.FileInfo[]]$Files = (Get-SourceFile)
        )

        $results = @()
        foreach ($file in $Files) {
            $lines = [System.IO.File]::ReadAllLines($file.FullName)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $Pattern) {
                    $results += [pscustomobject]@{
                        Path   = Get-RelativeSourcePath -Path $file.FullName
                        Line   = $i + 1
                        Text   = $lines[$i]
                        Before = if ($i -gt 0) { $lines[$i - 1] } else { '' }
                        After  = if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' }
                    }
                }
            }
        }

        return @($results)
    }

    function Get-UnloggedRuntimeCatchSignature {
        $loggingCommands = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        @(
            'LogInfo', 'LogWarning', 'LogError', 'LogDebug',
            'Write-BaselineInfo', 'Write-BaselineWarning', 'Write-BaselineError', 'Write-BaselineDebug',
            'Write-LogMessage', 'Write-ConsoleStatus', 'Write-SwallowedException', 'Write-DebugSwallowedException',
            'Write-UILogWarning', 'Write-Warning', 'Write-Error', 'Write-Debug', 'Write-Verbose',
            'Write-GuiRuntimeWarning', 'Write-GuiExecutionCleanupWarning', 'Write-SupportBundleSwallowedException',
            'Write-BootstrapSwallowedException', 'Write-BootstrapLog', 'Write-ScanTrace', 'Append-Log',
            'Write-ReleaseGateResult', 'Write-TestResult', 'Write-DriftResult',
            'Add-BaselineActionTrail', 'Write-AuditRecord',
            'Write-EnvironmentSwallowedException', 'Write-AIRemovalSwallowedException',
            'Write-ConfigProfileDebugSwallowedException', 'Write-GroupPolicyDebugSwallowedException',
            'Write-GuiCommonWarning', 'Write-EdgeRemovalLog', 'Write-StartupOrchestratorLog',
            'Write-GuiDeploymentMediaBuilderErrorLog', 'Write-GameModeDataWarning', 'Write-PackageHelperWarning',
            'Write-EnvironmentLaunchTrace', 'Write-BaselineRemoteCheckpointWarning', 'Write-BgTrace',
            'Write-GuiThemeFallbackWarning', 'Write-GuiDeveloperDiagnosticsError',
            'Invoke-GuiRuntimeFailureReport', 'Set-GuiDeploymentMediaBuilderStatus', 'Set-GuiSettingsStoreUnavailable'
        ) | ForEach-Object { [void]$loggingCommands.Add($_) }

        $moduleFiles = Get-RepoPowerShellFile -Roots @('Module') |
            Where-Object { (Get-RelativeSourcePath -Path $_.FullName) -ne 'Module\Logging.psm1' }

        foreach ($file in $moduleFiles) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($catchAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CatchClauseAst]
            }, $true)) {
                $hasThrow = [bool]$catchAst.Body.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.ThrowStatementAst]
                }, $true)
                if ($hasThrow) {
                    continue
                }

                $hasLogging = $false
                foreach ($commandAst in @($catchAst.Body.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true))) {
                    $commandName = $commandAst.GetCommandName()
                    if ($commandName -and $loggingCommands.Contains($commandName)) {
                        $hasLogging = $true
                        break
                    }
                }

                if (-not $hasLogging) {
                    '{0}:{1}: non-throwing catch has no runtime logging command' -f (Get-RelativeSourcePath -Path $file.FullName), $catchAst.Extent.StartLineNumber
                }
            }
        }
    }

    function Get-FunctionText {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors) {
            throw "Could not parse $Path"
        }

        $functionAst = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
        }, $true) | Select-Object -First 1

        if (-not $functionAst) {
            throw "Function $Name not found in $Path"
        }

        return $functionAst.Extent.Text
    }

    function Get-ParameterAliasName {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.ParameterAst]$ParameterAst
        )

        $aliases = @()
        foreach ($attribute in @($ParameterAst.Attributes)) {
            if ($attribute -isnot [System.Management.Automation.Language.AttributeAst]) {
                continue
            }

            $attributeName = $attribute.TypeName.FullName
            if ($attributeName -notin @('Alias', 'AliasAttribute', 'System.Management.Automation.AliasAttribute')) {
                continue
            }

            foreach ($argument in @($attribute.PositionalArguments)) {
                try {
                    $value = $argument.SafeGetValue()
                }
                catch {
                    continue
                }

                foreach ($candidate in @($value)) {
                    $alias = [string]$candidate
                    if (-not [string]::IsNullOrWhiteSpace($alias)) {
                        $aliases += $alias
                    }
                }
            }
        }

        return @($aliases)
    }

    function Get-LocalFunctionParameterMetadata {
        param(
            [System.IO.FileInfo[]]$Files
        )

        $metadata = @{}
        foreach ($file in $Files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($functionAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)) {
                if (-not $metadata.ContainsKey($functionAst.Name)) {
                    $metadata[$functionAst.Name] = @{
                        Parameters = @{}
                    }
                }

                $parameterTable = $metadata[$functionAst.Name]['Parameters']
                $parameterAsts = @()
                if ($functionAst.Body.ParamBlock) {
                    $parameterAsts += @($functionAst.Body.ParamBlock.Parameters)
                }
                $parameterAsts += @($functionAst.Parameters | Where-Object { $_ -is [System.Management.Automation.Language.ParameterAst] })

                foreach ($parameterAst in $parameterAsts) {
                    $name = $parameterAst.Name.VariablePath.UserPath
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $parameterTable[$name] = $true
                    }

                    foreach ($alias in Get-ParameterAliasName -ParameterAst $parameterAst) {
                        $parameterTable[$alias] = $true
                    }
                }
            }
        }

        return $metadata
    }

    function Test-LocalFunctionParameterName {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name,

            [string[]]$KnownParameters = @()
        )

        $commonParameters = @(
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable',
            'OutVariable', 'OutBuffer', 'PipelineVariable',
            'WhatIf', 'Confirm',
            'vb', 'db', 'ea', 'wa', 'ia', 'ev', 'wv', 'iv', 'ov', 'ob', 'pv', 'wi', 'cf'
        )

        if ($Name -in $commonParameters) {
            return $true
        }

        if ($Name -in $KnownParameters) {
            return $true
        }

        $matches = @($KnownParameters | Where-Object { $_.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) })
        return ($matches.Count -eq 1)
    }

    function Get-InvalidLocalFunctionCommandParameter {
        param(
            [System.IO.FileInfo[]]$Files
        )

        $metadata = Get-LocalFunctionParameterMetadata -Files $Files
        $invalid = New-Object System.Collections.Generic.List[string]
        foreach ($file in $Files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($commandAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {
                $commandName = $commandAst.GetCommandName()
                if ([string]::IsNullOrWhiteSpace($commandName) -or -not $metadata.ContainsKey($commandName)) {
                    continue
                }

                $knownParameters = @($metadata[$commandName]['Parameters'].GetEnumerator() | ForEach-Object { [string]$_.Key })
                foreach ($parameterAst in @($commandAst.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                    if ([string]::IsNullOrWhiteSpace($parameterAst.ParameterName)) {
                        continue
                    }

                    if (-not (Test-LocalFunctionParameterName -Name $parameterAst.ParameterName -KnownParameters $knownParameters)) {
                        [void]$invalid.Add(('{0}:{1}:{2} -{3}' -f (Get-RelativeSourcePath -Path $parameterAst.Extent.File), $parameterAst.Extent.StartLineNumber, $commandName, $parameterAst.ParameterName))
                    }
                }
            }
        }

        return @($invalid | Sort-Object -Unique)
    }

    function Get-SilentStartProcessCall {
        param(
            [System.IO.FileInfo[]]$Files
        )

        $matches = New-Object System.Collections.Generic.List[string]
        foreach ($file in $Files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($commandAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process'
            }, $true)) {
                for ($i = 0; $i -lt $commandAst.CommandElements.Count; $i++) {
                    $element = $commandAst.CommandElements[$i]
                    if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        continue
                    }

                    if ($element.ParameterName -notin @('ErrorAction', 'EA')) {
                        continue
                    }

                    $argumentText = $null
                    if ($element.Argument) {
                        $argumentText = $element.Argument.Extent.Text
                    }
                    elseif (($i + 1) -lt $commandAst.CommandElements.Count -and $commandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        $argumentText = $commandAst.CommandElements[$i + 1].Extent.Text
                    }

                    if ($argumentText -match 'SilentlyContinue') {
                        [void]$matches.Add(('{0}:{1}: {2}' -f (Get-RelativeSourcePath -Path $commandAst.Extent.File), $commandAst.Extent.StartLineNumber, $commandAst.Extent.Text.Trim()))
                    }
                }
            }
        }

        return @($matches | Sort-Object -Unique)
    }

    function Get-StaticStringArgumentValue {
        param(
            [AllowNull()]
            [System.Management.Automation.Language.Ast]$Ast
        )

        if (-not $Ast) {
            return $null
        }

        try {
            $value = $Ast.SafeGetValue()
            if ($value -is [string]) {
                return [string]$value
            }
        }
        catch {
            return $null
        }

        return $null
    }

    function Get-CommandArgumentAfterParameter {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.CommandAst]$CommandAst,

            [Parameter(Mandatory = $true)]
            [string]$ParameterName
        )

        for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
            $element = $CommandAst.CommandElements[$i]
            if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                continue
            }
            if (-not [string]::Equals($element.ParameterName, $ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($element.Argument) {
                return $element.Argument
            }
            if (($i + 1) -lt $CommandAst.CommandElements.Count -and $CommandAst.CommandElements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                return $CommandAst.CommandElements[$i + 1]
            }
            return $null
        }

        return $null
    }

    function Get-FirstPositionalCommandArgument {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.CommandAst]$CommandAst
        )

        for ($i = 1; $i -lt $CommandAst.CommandElements.Count; $i++) {
            $element = $CommandAst.CommandElements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($element.Argument) {
                    $i++
                }
                continue
            }

            return $element
        }

        return $null
    }

    function Get-StaticLoggingCall {
        param(
            [System.IO.FileInfo[]]$Files
        )

        $records = @()
        foreach ($file in $Files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            foreach ($commandAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true)) {
                $commandName = $commandAst.GetCommandName()
                if ([string]::IsNullOrWhiteSpace($commandName)) {
                    continue
                }

                $level = $null
                switch -Regex ($commandName) {
                    '^(LogDebug|Write-BaselineDebug)$' { $level = 'DEBUG'; break }
                    '^(LogInfo|Write-BaselineInfo)$' { $level = 'INFO'; break }
                    '^(LogWarning|Write-BaselineWarning)$' { $level = 'WARNING'; break }
                    '^(LogError|Write-BaselineError)$' { $level = 'ERROR'; break }
                    '^Write-LogMessage$' {
                        $levelAst = Get-CommandArgumentAfterParameter -CommandAst $commandAst -ParameterName 'Level'
                        $levelValue = Get-StaticStringArgumentValue -Ast $levelAst
                        if ($levelValue -in @('DEBUG', 'INFO', 'WARNING', 'ERROR')) {
                            $level = [string]$levelValue
                        }
                        break
                    }
                }

                if (-not $level) {
                    continue
                }

                $messageAst = Get-CommandArgumentAfterParameter -CommandAst $commandAst -ParameterName 'Message'
                if (-not $messageAst) {
                    $messageAst = Get-FirstPositionalCommandArgument -CommandAst $commandAst
                }

                $message = Get-StaticStringArgumentValue -Ast $messageAst
                if ([string]::IsNullOrWhiteSpace($message)) {
                    continue
                }

                $records += [pscustomobject]@{
                    Path    = Get-RelativeSourcePath -Path $commandAst.Extent.File
                    Line    = $commandAst.Extent.StartLineNumber
                    Level   = $level
                    Message = $message.Trim()
                }
            }
        }

        return $records
    }

    function ConvertTo-NormalizedLogMessage {
        param(
            [string]$Message
        )

        if ([string]::IsNullOrWhiteSpace($Message)) {
            return ''
        }

        return (($Message -replace '\s+', ' ').Trim()).ToLowerInvariant()
    }
}

Describe 'Source quality guardrails' {
    It 'does not globally ignore broad infrastructure errors' {
        $path = Join-Path $script:RepoRoot 'Module/SharedHelpers/ErrorHandling.Helpers.ps1'
        $functionText = Get-FunctionText -Path $path -Name 'Test-IgnorableErrorMessage'

        $forbidden = @(
            'Cannot find path',
            'Cannot bind argument',
            'The parameter is incorrect',
            'Unknown error',
            'Access is denied',
            'Security error',
            'The system cannot find the path specified',
            'The system cannot find the file specified'
        )

        foreach ($pattern in $forbidden) {
            $functionText | Should -Not -Match ([regex]::Escape($pattern))
        }

        $functionText | Should -Match 'IsNullOrWhiteSpace\(\$Message\)\) \{ return \$false \}'
        $functionText | Should -Not -Match 'Property \.\* does not exist'
        $functionText | Should -Not -Match 'The property \.\* cannot be found on this object'
    }

    It 'keeps Invoke-BaselineProcess exit-code checking enabled by default' {
        $path = Join-Path $script:RepoRoot 'Module/SharedHelpers/Process.Helpers.ps1'
        $functionText = Get-FunctionText -Path $path -Name 'Invoke-BaselineProcess'

        $functionText | Should -Match '\[int\[\]\]\s*\$AllowedExitCodes\s*=\s*@\(0\)'
        $functionText | Should -Match '\[switch\]\s*\$AllowAnyExitCode'
        $functionText | Should -Match 'if\s*\(\s*-not\s+\$AllowAnyExitCode'
        $functionText | Should -Match 'throw\s+\$message'
    }

    It 'does not discard Invoke-BaselineProcess results with [void]' {
        $sourceMatches = @(Find-SourcePattern -Pattern '\[void\]\s*\(Invoke-BaselineProcess')

        $sourceMatches.Count | Should -Be 0
    }

    It 'uses the severity-aware swallowed-exception logger in production modules' {
        $moduleFiles = Get-RepoPowerShellFile -Roots @('Module') |
            Where-Object { (Get-RelativeSourcePath -Path $_.FullName) -ne 'Module\Logging.psm1' }

        $sourceMatches = @(Find-SourcePattern -Files $moduleFiles -Pattern 'Write-DebugSwallowedException\s+-')

        $sourceMatches.Count | Should -Be 0
    }

    It 'keeps every non-throwing runtime catch on an explicit logging path' {
        $unloggedCatches = @(Get-UnloggedRuntimeCatchSignature)

        if ($unloggedCatches.Count -gt 0) {
            throw ("Unlogged runtime catch blocks:{0}{1}" -f [Environment]::NewLine, ($unloggedCatches -join [Environment]::NewLine))
        }
    }

    It 'keeps known native repair commands out of untracked Start-Process paths' {
        $files = @(
            Join-Path $script:RepoRoot 'Module/Regions/System/System.Updates.psm1'
            Join-Path $script:RepoRoot 'Module/Regions/SystemTweaks/SystemTweaks.Cleanup.psm1'
            Join-Path $script:RepoRoot 'Module/Regions/SystemTweaks/SystemTweaks.SMBRepair.psm1'
        ) | ForEach-Object { Get-Item -LiteralPath $_ }

        $sourceMatches = @(Find-SourcePattern -Files $files -Pattern 'Start-Process')

        $sourceMatches.Count | Should -Be 0
    }

    It 'keeps static DEBUG logging diagnostic instead of mirrored operational text' {
        $files = Get-RepoPowerShellFile -Roots @('Module', 'Bootstrap') |
            Where-Object { (Get-RelativeSourcePath -Path $_.FullName) -notin @('Module\Logging.psm1') }

        $calls = @(Get-StaticLoggingCall -Files $files)
        $operationalMessages = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($call in @($calls | Where-Object { $_.Level -in @('INFO', 'WARNING', 'ERROR') })) {
            $normalized = ConvertTo-NormalizedLogMessage -Message $call.Message
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                [void]$operationalMessages.Add($normalized)
            }
        }

        $violations = New-Object System.Collections.Generic.List[string]
        foreach ($call in @($calls | Where-Object { $_.Level -eq 'DEBUG' })) {
            $normalized = ConvertTo-NormalizedLogMessage -Message $call.Message
            if ([string]::IsNullOrWhiteSpace($normalized)) {
                continue
            }

            if ($operationalMessages.Contains($normalized)) {
                [void]$violations.Add(('{0}:{1}: DEBUG duplicates an INFO/WARNING/ERROR message: {2}' -f $call.Path, $call.Line, $call.Message))
            }
            elseif ($call.Message -match '^(Entering|Exiting)\b') {
                [void]$violations.Add(('{0}:{1}: DEBUG uses trace-only entry/exit wording instead of diagnostic detail: {2}' -f $call.Path, $call.Line, $call.Message))
            }
        }

        if ($violations.Count -gt 0) {
            throw ("Non-diagnostic DEBUG log messages:{0}{1}" -f [Environment]::NewLine, ($violations -join [Environment]::NewLine))
        }
    }

    It 'waits for SMB repair SFC through Invoke-BaselineProcess' {
        $path = Join-Path $script:RepoRoot 'Module/Regions/SystemTweaks/SystemTweaks.SMBRepair.psm1'
        $content = Get-BaselineTestSourceText -Path $path

        $content | Should -Match 'Invoke-BaselineProcess\s+-FilePath "\$env:SystemRoot\\System32\\sfc\.exe"'
        $content | Should -Match "-ArgumentList @\('/scannow'\)"
        $content | Should -Match '-AllowedExitCodes @\(0\)'
    }

    It 'fails bootstrap install when setup exits cleanly but Baseline.exe is missing' {
        $path = Join-Path $script:RepoRoot 'Bootstrap/Bootstrap.Install.ps1'
        $content = Get-BaselineTestSourceText -Path $path

        $content | Should -Match 'if \(-not \$installedExe\)'
        $content | Should -Match 'throw "\$Repository installer exited successfully, but no installed Baseline\.exe was found'
    }

    It 'limits headless and profile apply to manifest-declared tweak functions' {
        $path = Join-Path $script:RepoRoot 'Bootstrap/Baseline.ps1'
        $content = Get-BaselineTestSourceText -Path $path

        $content | Should -Match 'function New-BaselineManifestFunctionAllowList'
        $content | Should -Match 'function Test-BaselineManifestFunctionAllowed'
        $content | Should -Match 'Import-TweakManifestFromData'
        $content | Should -Match 'Profile function .* is not declared in the tweak manifest'
        $content | Should -Match 'Function .* is not declared in the tweak manifest and will not be invoked'
        $content | Should -Match "Add-SessionStatistic -Name 'FailedCount'"
    }

    It 'keeps dynamic execution limited to explicit reviewed sites' {
        $patterns = @(
            'Invoke-Expression',
            '\biex\b',
            '\[scriptblock\]::Create',
            '-EncodedCommand',
            '[''"]-Command[''"]'
        )

        $allowed = @()

        $unexpected = New-Object System.Collections.Generic.List[object]
        foreach ($pattern in $patterns) {
            foreach ($match in Find-SourcePattern -Pattern $pattern) {
                $isAllowed = $false
                foreach ($entry in $allowed) {
                    $parts = $entry -split '\|', 3
                    if ($match.Path -eq $parts[0] -and $match.Text.Contains($parts[1]) -and $match.Text.Contains($parts[2])) {
                        $isAllowed = $true
                        break
                    }
                }

                if (-not $isAllowed) {
                    $unexpected.Add($match)
                }
            }
        }

        $unexpected.Count | Should -Be 0
    }

    It 'keeps WPF event handlers independent of module-scoped object-field helper lookup' {
        $violations = @()
        foreach ($file in (Get-SourceFile | Where-Object { $_.Extension -in @('.ps1', '.psm1') })) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $($file.FullName)"
            }

            $eventRegistrations = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Register-GuiEventHandler'
            }, $true)

            foreach ($registration in $eventRegistrations) {
                if ($registration.Extent.Text -match '\bTest-GuiObjectField\b') {
                    $violations += '{0}:{1}: Register-GuiEventHandler directly references Test-GuiObjectField' -f (Get-RelativeSourcePath -Path $file.FullName), $registration.Extent.StartLineNumber
                }
            }
        }

        $violations | Should -BeNullOrEmpty
    }

    It 'does not allow wildcard module function exports' {
        $moduleFiles = Get-SourceFile -Include @('*.psm1')
        $sourceMatches = @(Find-SourcePattern -Files $moduleFiles -Pattern 'Export-ModuleMember\s+-Function\s+[''"]?\*[''"]?')

        $sourceMatches.Count | Should -Be 0

        $manifestPath = Join-Path $script:RepoRoot 'Module/Baseline.psd1'
        $manifestContent = Get-BaselineTestSourceText -Path $manifestPath
        $manifestContent | Should -Not -Match 'FunctionsToExport\s*=\s*[''"]?\*[''"]?'
    }

    It 'does not allow duplicate function names in module source' {
        $duplicates = @(Get-ModuleFunctionDuplicateSignature)

        $duplicates.Count | Should -Be 0
    }

    It 'keeps local function command parameters aligned with declared metadata' {
        $files = Get-RepoPowerShellFile -Roots @('Module', 'Bootstrap', 'Tools')
        $invalidParameters = @(Get-InvalidLocalFunctionCommandParameter -Files $files)

        if ($invalidParameters.Count -gt 0) {
            throw ("Invalid local function command parameters:{0}{1}" -f [Environment]::NewLine, ($invalidParameters -join [Environment]::NewLine))
        }
    }

    It 'does not duplicate bootstrap helper function names across raw and packaged bootstrap scripts' {
        $bootstrapFiles = @(
            Join-Path $script:RepoRoot 'Bootstrap/Bootstrap.ps1'
            Join-Path $script:RepoRoot 'Bootstrap/Bootstrap.Install.ps1'
            Join-Path $script:RepoRoot 'Bootstrap/Helpers/Bootstrap.Helpers.ps1'
        )

        $definitions = New-Object System.Collections.Generic.List[object]
        foreach ($filePath in $bootstrapFiles) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$tokens, [ref]$errors)
            if ($errors) {
                throw "Could not parse $filePath"
            }

            foreach ($functionAst in $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)) {
                $definitions.Add([pscustomobject]@{
                    Name = $functionAst.Name
                    Path = Get-RelativeSourcePath -Path $functionAst.Extent.File
                })
            }
        }

        $unexpectedDuplicates = @(
            $definitions |
                Group-Object Name |
                Where-Object Count -gt 1 |
                ForEach-Object {
                    '{0}|{1}' -f $_.Name, (@($_.Group | Select-Object -ExpandProperty Path | Sort-Object -Unique) -join ';')
                }
        )

        $unexpectedDuplicates.Count | Should -Be 0
    }

    It 'keeps Show-TweakGUI scripts in the GUI owner folder as complete load statements' {
        $guiModulePath = Join-Path $script:RepoRoot 'Module/Regions/GUI.psm1'
        $partsRoot = Join-Path $script:RepoRoot 'Module/GUI/Show-TweakGUI'
        $guiContent = Get-BaselineTestSourceText -Path $guiModulePath
        $resolvedPaths = @(Get-BaselineTestSourcePathSet -Path $guiModulePath)

        $guiContent | Should -Not -Match '(?m)^\s*(Ad|\$S|\$f)\s*#'
        @(Get-ChildItem -LiteralPath $partsRoot -Filter 'Step*.ps1' -File).Count | Should -Be 0

        $partNames = @(
            'StartupTrace.ps1',
            'ManifestImport.ps1',
            'WpfCategoryInitialization.ps1',
            'ObservableGuiState.ps1',
            'WindowClosingHandler.ps1',
            'StartupSessionRestoreProbe.ps1',
            'VisibleContentRefresh.ps1',
            'GuiScriptblockCaptures.ps1',
            'StartupSessionRestoreApply.ps1',
            'UpdateDownloadHandler.ps1',
            'FirstRunAndSplashHandoff.ps1',
            'ContentRenderedStartupCompletion.ps1',
            'ShowDialogErrorHandling.ps1',
            'ModulePathResolution.ps1',
            'CategoryPathMapping.ps1',
            'AvailabilityStateOverrides.ps1',
            'PrimaryTabTweakIndex.ps1',
            'WindowPresentation.ps1'
        )

        foreach ($partName in $partNames) {
            $partPath = Join-Path $partsRoot $partName
            $partPath | Should -Exist

            $resolvedPaths | Should -Contain (Resolve-Path -LiteralPath $partPath).ProviderPath

            $partContent = Get-BaselineTestSourceText -Path $partPath
            $partContent | Should -Not -Match '(?m)^\s*(d-Type|cript:|irstRun)\b'
        }
    }

    It 'keeps split imports in owner folders with descriptive names' {
        $legacyFolderName = '_' + 'OversizedFunctionParts'
        $legacyVariablePrefix = 'Baseline' + 'Oversized'
        $genericStepFilePattern = 'Step\d{3}\.ps1'
        $files = @()
        foreach ($rootName in @('Module', 'Tools', 'Bootstrap', 'Tests', 'Launcher', 'dev_docs')) {
            $rootPath = Join-Path $script:RepoRoot $rootName
            if (Test-Path -LiteralPath $rootPath -PathType Container) {
                $files += Get-ChildItem -LiteralPath $rootPath -Recurse -File |
                    Where-Object {
                        $_.FullName -notmatch '\\vendor\\' -and
                        $_.FullName -notmatch '\\(bin|obj)\\' -and
                        $_.Extension.ToLowerInvariant() -in @('.ps1', '.psm1', '.psd1', '.ps1xml', '.json', '.cs', '.csproj', '.md', '.xml', '.xaml', '.yml', '.yaml', '.txt')
                    }
            }
        }

        $matches = foreach ($file in $files) {
            if ($file.Name -match ('^' + $genericStepFilePattern + '$')) {
                Get-RelativeSourcePath -Path $file.FullName
            }

            $content = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($legacyToken in @($legacyFolderName, $legacyVariablePrefix)) {
                if ($content.Contains($legacyToken)) {
                    Get-RelativeSourcePath -Path $file.FullName
                }
            }
            if ($content -match $genericStepFilePattern) {
                Get-RelativeSourcePath -Path $file.FullName
            }
        }
        @($matches).Count | Should -Be 0
    }

    It 'keeps PowerShell functions at or below the staged refactor size limit' {
        $oversizedFunctions = @(Get-OversizedFunctionSignature -MaximumLines 400)

        $oversizedFunctions.Count | Should -Be 0
    }

    It 'does not use unbounded process wait calls in source, tools, bootstrap, or tests' {
        $files = Get-RepoPowerShellFile -Roots @('Module', 'Tools', 'Bootstrap', 'Tests')
        $startProcess = 'Start-' + 'Process'
        $waitParameter = '-' + 'Wait'
        $sourceMatches = @(Find-SourcePattern -Files $files -Pattern ('{0}.*{1}|{1}.*{0}' -f [regex]::Escape($startProcess), [regex]::Escape($waitParameter)))

        $sourceMatches.Count | Should -Be 0
    }

    It 'does not suppress Start-Process launch failures in production code' {
        $files = Get-RepoPowerShellFile -Roots @('Module', 'Tools', 'Bootstrap')
        $silentLaunches = @(Get-SilentStartProcessCall -Files $files)

        if ($silentLaunches.Count -gt 0) {
            throw ("Start-Process uses -ErrorAction SilentlyContinue:{0}{1}" -f [Environment]::NewLine, ($silentLaunches -join [Environment]::NewLine))
        }
    }

    It 'keeps removed localization archive packaging references absent' {
        $files = Get-RepoPowerShellFile -Roots @('Module', 'Tools', 'Bootstrap', 'Tests')
        $archiveName = 'Localizations' + '.zip'
        $builderName = 'New-' + 'LocalizationArchive'
        $sourceMatches = @(Find-SourcePattern -Files $files -Pattern ('{0}|{1}' -f [regex]::Escape($archiveName), [regex]::Escape($builderName)))

        $sourceMatches.Count | Should -Be 0
    }

    It 'keeps empty catches restricted to reviewed cleanup and trace sites' {
        $allowed = @(
            'Module\GUICommon\SharedScrollBars.ps1:239',
            'Module\SharedHelpers\Environment.Helpers.ps1:1544',
            'Module\SharedHelpers\Environment.Helpers.ps1:1702',
            'Module\SharedHelpers\Environment.Helpers.ps1:1845',
            'Module\SharedHelpers\Environment.Helpers.ps1:1865',
            'Module\SharedHelpers\Environment.Helpers.ps1:1870',
            'Module\SharedHelpers\Environment.Helpers.ps1:1888',
            'Module\SharedHelpers\Environment.Helpers.ps1:1913',
            'Module\SharedHelpers\Environment.Helpers.ps1:1940',
            'Module\SharedHelpers\Environment.Helpers.ps1:2897',
            'Module\Regions\GUI.psm1:70',
            'Module\Regions\GUI.psm1:74',
            'Module\Regions\GUI.psm1:101',
            'Module\Regions\GUI.psm1:125',
            'Module\Regions\GUI.psm1:1606',
            'Module\GUI\BuildTabContent.ps1:218',
            'Module\GUI\Show-TweakGUI\ContentRenderedStartupCompletion.ps1:70',
            'Module\SharedHelpers\Environment\Set-BootstrapLoadingSplashStep\SplashDispatcherUpdate.ps1:353',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:499',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:657',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:800',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:820',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:825',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:843',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:868',
            'Module\SharedHelpers\Environment\Show-BootstrapLoadingSplash\Show-BootstrapLoadingSplash.ps1:895'
        )

        $unexpected = Find-SourcePattern -Pattern 'catch\s*\{\s*\}' |
            Where-Object { ('{0}:{1}' -f $_.Path, $_.Line) -notin $allowed }

        @($unexpected).Count | Should -Be 0
    }

    It 'keeps high-signal swallowed exceptions on explicit severity-aware logging' {
        $files = @(
            'Bootstrap\Bootstrap.ps1',
            'Bootstrap\Baseline.ps1',
            'Module\SharedHelpers\AuditTrail.Helpers.ps1',
            'Module\SharedHelpers\Persistence.Helpers.ps1',
            'Module\SharedHelpers\Process.Helpers.ps1',
            'Module\SharedHelpers\SupportBundle.Helpers.ps1',
            'Module\Regions\UWPApps\AIRemoval.ps1'
        ) | ForEach-Object { Get-Item -LiteralPath (Join-Path $script:RepoRoot $_) }

        $debugWrapperMatches = Find-SourcePattern -Files $files -Pattern 'Write-DebugSwallowedException'
        $missingSeverityMatches = Find-SourcePattern -Files $files -Pattern '\b(Write-SwallowedException|Write-SupportBundleSwallowedException|Write-BootstrapSwallowedException)\s+-' |
            Where-Object { $_.Text -notmatch '-Severity\s+' }

        @($debugWrapperMatches).Count | Should -Be 0
        @($missingSeverityMatches).Count | Should -Be 0
    }

    It 'keeps swallowed-exception logging failures visible through an emergency fallback' {
        $loggingPath = Join-Path $script:RepoRoot 'Module/Logging.psm1'
        $loggingContent = Get-Content -LiteralPath $loggingPath -Raw -Encoding UTF8

        $loggingContent | Should -Match '\[swallow-log-failure\]'
        $loggingContent | Should -Match 'Baseline-emergency\.log'
        $loggingContent | Should -Match '\[System\.IO\.File\]::AppendAllText'
    }

    It 'keeps interactive user launches visible through Invoke-UserLaunch' {
        $processHelperPath = Join-Path $script:RepoRoot 'Module/SharedHelpers/Process.Helpers.ps1'
        $processHelperContent = Get-BaselineTestSourceText -Path $processHelperPath
        $processHelperContent | Should -Match 'function Invoke-UserLaunch'
        $processHelperContent | Should -Match 'LogWarning \$message'
        $processHelperContent | Should -Match 'Write-Warning \$message'

        $files = @(
            'Module/GUI/UpdateOverlayModule.ps1',
            'Module/GUI/DialogHelpers/ContentDialogs.ps1',
            'Module/GUI/DialogHelpers/SettingsDialogs/Show-GuiSettingsDialog/LogFolderBrowseHandler.ps1',
            'Module/Regions/OneDrive.psm1',
            'Module/Regions/PostActions/PostActions/PostActions.ps1',
            'Module/Regions/InitialActions/InitialActions/HarmfulTweakerNetworkCleanup.ps1'
        )
        foreach ($relativePath in $files) {
            $content = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot $relativePath)
            $content | Should -Match 'Invoke-UserLaunch'
        }
    }

    It 'enforces release signing, fresh test report, and zip hygiene gates in release smoke' {
        $releaseSmokePath = Join-Path $script:RepoRoot 'Tools/Test-ReleaseSmoke.ps1'
        $content = Get-BaselineTestSourceText -Path $releaseSmokePath

        $content | Should -Match 'Test-ReleaseAuthenticodeGate'
        $content | Should -Match 'Get-AuthenticodeSignature'
        $content | Should -Match 'TimeStamperCertificate'
        $content | Should -Match 'AllowUnsignedPreview'
        $content | Should -Match 'BASELINE_PREVIEW_UNSIGNED'
        $content | Should -Match 'PrivateData\.ContainsKey\(''Prerelease''\)'
        $content | Should -Match 'Test-StaleTestReportGate'
        $content | Should -Match 'Tests/TestReport\.json'
        $content | Should -Match 'Get-ReleaseGateInputFile'
        $content | Should -Match 'Test-ReleaseArtifactSetGate'
        $content | Should -Match 'Release artifact identity exclusivity'
        $content | Should -Match 'Loose setup bytes differ from ZIP-contained setup'
        $content | Should -Match 'Manifest hash does not match current file bytes'
        $content | Should -Match 'Test-GeneratedInstallerScriptEncodingGate'
        $content | Should -Match 'Generated installer script encoding'
        $content | Should -Match 'Mojibake marker'
        $content | Should -Match 'Test-ReleaseZipHygieneGate'
        $content | Should -Match '\(bin\|obj\)'
        $content | Should -Match 'FileListAbsolute'
    }

    It 'runs release smoke in CI only after final artifacts and a fresh test report exist' {
        $workflowPath = Join-Path $script:RepoRoot '.github/workflows/ci.yml'
        $content = Get-BaselineTestSourceText -Path $workflowPath

        $packageIndex = $content.IndexOf('name: Build release package')
        $reportIndex = $content.IndexOf('name: Regenerate release test report')
        $smokeIndex = $content.LastIndexOf('name: Run release smoke tests')

        $packageIndex | Should -BeGreaterOrEqual 0
        $reportIndex | Should -BeGreaterThan $packageIndex
        $smokeIndex | Should -BeGreaterThan $reportIndex
        $content.Substring(0, $packageIndex) | Should -Not -Match 'Test-ReleaseSmoke\.ps1'
        $content | Should -Match 'Export-TestReport\.ps1'
        $content | Should -Match 'Import-PowerShellDataFile -LiteralPath \.\\Module\\Baseline\.psd1'
        $content | Should -Match '\$manifest\.PrivateData\.ContainsKey\(''Prerelease''\)'
        $content | Should -Match '\$releaseSmokeArgs = @\{\}'
        $content | Should -Match '\$releaseSmokeArgs\[''AllowUnsignedPreview''\] = \$true'
        $content | Should -Match 'Test-ReleaseSmoke\.ps1 @releaseSmokeArgs'
    }

    It 'refreshes installer translations during CI release package generation' {
        $workflowPath = Join-Path $script:RepoRoot '.github/workflows/ci.yml'
        $content = Get-BaselineTestSourceText -Path $workflowPath

        $content | Should -Match 'New-ReleasePackage\.ps1 -Force -RefreshInstallerTranslations'
    }

    It 'documents the ProgramData runtime cache and hash-verified reuse contract' {
        $runtimeCacheDocPath = Join-Path $script:RepoRoot 'dev_docs/RuntimeCache.md'
        $content = Get-BaselineTestSourceText -Path $runtimeCacheDocPath

        $content | Should -Match '%ProgramData%\\Baseline\\RuntimeCache\\RC'
        $content | Should -Match '\.baseline-runtime-manifest\.sha256'
        $content | Should -Match 'SHA-256'
        $content | Should -Match 'Administrators and SYSTEM'
        $content | Should -Not -Match '%LOCALAPPDATA%\\Baseline\\RC'
    }

    It 'keeps headless failure accounting on explicit operation scopes' {
        $bootstrapContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Bootstrap/Baseline.ps1')
        $loggingContent = Get-BaselineTestSourceText -Path (Join-Path $script:RepoRoot 'Module/Logging.psm1')

        $bootstrapContent | Should -Match 'Start-BaselineOperationScope -Name \$functionName'
        $bootstrapContent | Should -Match 'Stop-BaselineOperationScope -Scope \$operationScope'
        $bootstrapContent | Should -Match 'Invalid command arguments for'
        $bootstrapContent | Should -Not -Match '\$Global:Error\.Count'

        $loggingContent | Should -Match 'function Start-BaselineOperationScope'
        $loggingContent | Should -Match 'function Stop-BaselineOperationScope'
        $loggingContent | Should -Match 'function Set-BaselineOperationFailed'
        $loggingContent | Should -Match 'Set-BaselineOperationFailed -Reason \$logMessage'
        $loggingContent | Should -Match 'if \(\$statusText -eq ''failed''\)'
        $loggingContent | Should -Not -Match '\$Global:Error\.Count'
    }

    It 'keeps locale directories ASCII-safe for portable release archives' {
        $localeRoot = Join-Path $script:RepoRoot 'Localizations'
        $nonAsciiDirectories = @(
            Get-ChildItem -LiteralPath $localeRoot -Directory |
                Where-Object { $_.Name -match '[^\x00-\x7F]' }
        )

        $nonAsciiDirectories.Count | Should -Be 0
    }

    It 'keeps PowerShell 5.1 hazard markers out of module and tool code' {
        $files = @(
            Get-SourceFile
            Get-RepoPowerShellFile -Roots @('Tools')
        )

        $sourceMatches = @(Find-SourcePattern -Files $files -Pattern 'System\.Text\.Json|RuntimeInformation\]::OSArchitecture')

        $sourceMatches.Count | Should -Be 0
    }

    It 'keeps generated filler comments out of module, tool, bootstrap, and test code' {
        $files = @(
            Get-RepoPowerShellFile -Roots @('Module', 'Tools', 'Bootstrap', 'Tests')
        )

        $fillerPhrase = 'Internal ' + 'function'
        $generatedSupportsPrefix = 'Supports '
        $generatedHandlingSuffix = 'handling inside Baseline'
        $generatedSynopsisPrefix = $generatedSupportsPrefix + '.* ' + $generatedHandlingSuffix
        $sourceMatches = Find-SourcePattern -Files $files -Pattern ('^\s*{0} (?:[A-Za-z0-9_.:-]+)?\.|{1}' -f [regex]::Escape($fillerPhrase), $generatedSynopsisPrefix)

        @($sourceMatches).Count | Should -Be 0
    }

    It 'keeps mojibake markers out of module code' {
        $pattern = [string]::Join('|', @((226, 65533, 195, 194) | ForEach-Object { [regex]::Escape([string][char]$_) }))
        $rawHits = @(Find-SourcePattern -Files (Get-RepoPowerShellFile -Roots @('Module')) -Pattern $pattern)

        $badMarkerHits = @($rawHits | Where-Object {
            -not (
                $_.Text.Contains('Romanian') -and
                $_.Path -in @('Module\GUI\BuildPrimaryTabs.ps1', 'Module\GUI\LanguageCatalog.ps1')
            )
        })

        @($badMarkerHits).Count | Should -Be 0
    }

    It 'keeps informal AIRemoval comments out of source' {
        $path = Join-Path $script:RepoRoot 'Module/Regions/UWPApps/AIRemoval.ps1'
        $sourceMatches = @(Find-SourcePattern -Files @((Get-Item -LiteralPath $path)) -Pattern 'lol|shit|prob|maybe add|trash')

        $sourceMatches.Count | Should -Be 0
    }

    It 'keeps AIRemoval remote execution and privileged process calls bounded' {
        $path = Join-Path $script:RepoRoot 'Module/Regions/UWPApps/AIRemoval.ps1'
        $file = Get-Item -LiteralPath $path

        $remoteExecutionMatches = @(Find-SourcePattern -Files @($file) -Pattern 'Invoke-RestMethod|Invoke-WebRequest|\birm\b|\biex\b|\[scriptblock\]::Create|Set-ExecutionPolicy\s+Unrestricted|RemoteAIRemovalScriptUrl')
        $remoteExecutionMatches.Count | Should -Be 0

        $fileText = [System.IO.File]::ReadAllText($file.FullName)
        $fileText | Should -Not -Match 'WindowsWorkload\.TextRecognition\.Stx'
        $fileText | Should -Not -Match 'cmd\.exe\s+/d\s+/c'

        $nativeProcessPattern = '(^\s*(?:&\s*)?(sc|taskkill|takeown|icacls|dism)(?:\.exe)?\b)|(-FilePath\s+[''"](?:sc|taskkill|takeown|icacls|dism)\.exe[''"])'
        $nativeProcessMatches = @(
            Find-SourcePattern -Files @($file) -Pattern $nativeProcessPattern |
                Where-Object { $_.Text.TrimStart() -notlike '#*' }
        )
        foreach ($match in $nativeProcessMatches) {
            $match.Text | Should -Match 'Invoke-BaselineProcess|Invoke-AIRemovalNativeProcess|Invoke-AIRemovalDism'
            $match.Text | Should -Match 'TimeoutSeconds'
        }

        $runTrustedText = Get-FunctionText -Path $path -Name 'RunTrusted'
        $runTrustedText | Should -Match 'finally'
        $runTrustedText | Should -Match 'RestoreTrustedInstaller'
        $runTrustedText | Should -Match 'TrustedInstaller-.*complete\.json'
        $runTrustedText | Should -Match 'TrustedInstaller-.*error\.json'
        $runTrustedText | Should -Match 'did not report completion'
        $runTrustedText | Should -Match 'Failed to restore the TrustedInstaller service command'
        $restorePattern = [regex]::Escape("'config', 'TrustedInstaller', 'binPath=', " + '$originalTrustedInstallerBinPath')
        $runTrustedText | Should -Match $restorePattern

        $fileText | Should -Match 'Voice Access removal did not meet postconditions'
        $fileText | Should -Match 'Recall or Office AI scheduled tasks remained enabled after removal'
    }
}
