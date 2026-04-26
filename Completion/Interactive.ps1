<#
    .SYNOPSIS
    Bootstraps an interactive Baseline session and provides tab completion for functions, arguments, and presets.

    .VERSION
    3.1.0 (beta)

    .DATE
    17.03.2026 - initial beta version
    21.03.2026 - Added GUI
    06.04.2026 - Major changes to the GUI, and added more features
    26.04.2026 - Minor Fixes

    .AUTHOR
    sdmanson8 - Copyright (c) 2026

    .DESCRIPTION
    Run the script once to register a global `Baseline` command in the current
    PowerShell session. The command supports the same headless function syntax as
    `Baseline.ps1` and also accepts preset names.

    .EXAMPLE
    .\Completion\Interactive.ps1

    .EXAMPLE
    Baseline -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal"

    .EXAMPLE
    Baseline -Preset Basic

    .EXAMPLE
    Baseline -GameModeProfile Competitive

    .EXAMPLE
    Baseline -ScenarioProfile Privacy

    .NOTES
    Use commas to separate function calls passed to `-Functions`. You can run the
    script directly or dot source it. The registered command and completers are
    added to the global session so they continue to work after the script exits.

    .LINK
    https://github.com/sdmanson8/Baseline
#>

#Requires -RunAsAdministrator

Clear-Host

$Script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$Script:ModuleRoot = Join-Path $Script:RepoRoot 'Module'
$Script:PresetRoot = Join-Path $Script:ModuleRoot 'Data\Presets'
$Script:LocalizationRoot = Join-Path $Script:RepoRoot 'Localizations'
$Script:ModuleManifestPath = Join-Path $Script:ModuleRoot 'Baseline.psd1'

if (-not (Test-Path -LiteralPath $Script:ModuleRoot -PathType Container))
{
    throw "Module directory not found under: $Script:RepoRoot"
}

if (-not (Test-Path -LiteralPath $Script:ModuleManifestPath -PathType Leaf))
{
    throw "Module manifest not found: $Script:ModuleManifestPath"
}

$Global:BaselineInteractiveRepoRoot = $Script:RepoRoot
$Global:BaselineInteractiveModuleRoot = $Script:ModuleRoot
$Global:BaselineInteractivePresetRoot = $Script:PresetRoot
$Global:BaselineInteractiveLocalizationRoot = $Script:LocalizationRoot

foreach ($functionName in @(
    'Baseline',
    'ConvertTo-BaselineInteractivePresetName',
    'Get-BaselineInteractivePresetCommandList',
    'Get-BaselineInteractivePresetNames'
))
{
    Remove-Item -Path ("Function:\global:{0}" -f $functionName) -Force -ErrorAction Ignore
}

function global:ConvertTo-BaselineInteractivePresetName
{
    param (
        [Parameter(Mandatory = $false)]
        [string]
        $PresetName
    )

    $normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Basic' } else { [string]$PresetName }
    $normalizedPresetName = [System.IO.Path]::GetFileNameWithoutExtension($normalizedPresetName.Trim())

    switch -Regex ($normalizedPresetName)
    {
        '^\s*minimal\s*$'               { return 'Minimal' }
        '^\s*balanced\s*$'              { return 'Balanced' }
        '^\s*(basic|safe)\s*$'          { return 'Basic' }
        '^\s*(advanced|aggressive)\s*$' { return 'Advanced' }
        default                         { return $normalizedPresetName }
    }
}

function global:Get-BaselineInteractivePresetNames
{
    $presetRoot = $Global:BaselineInteractivePresetRoot
    if (-not (Test-Path -LiteralPath $presetRoot -PathType Container))
    {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $presetRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.json', '.txt') } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Sort-Object -Unique
    )
}

function global:Get-BaselineInteractivePresetCommandList
{
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $PresetName
    )

    $presetRoot = $Global:BaselineInteractivePresetRoot
    if (-not (Test-Path -LiteralPath $presetRoot -PathType Container))
    {
        throw "Preset directory was not found: $presetRoot"
    }

    $presetPath = $null
    if (Test-Path -LiteralPath $PresetName -PathType Leaf)
    {
        $presetPath = (Resolve-Path -LiteralPath $PresetName -ErrorAction Stop).Path
    }
    else
    {
        $normalizedPresetName = ConvertTo-BaselineInteractivePresetName -PresetName $PresetName
        foreach ($extension in @('.json', '.txt'))
        {
            $candidatePath = Join-Path -Path $presetRoot -ChildPath ("{0}{1}" -f $normalizedPresetName, $extension)
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf)
            {
                $presetPath = $candidatePath
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$presetPath))
    {
        throw "Preset file '$PresetName.json' or '$PresetName.txt' was not found under Module\Data\Presets."
    }

    $commandList = [System.Collections.Generic.List[string]]::new()
    $commandIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase))
    {
        $presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($presetData -and $presetData.PSObject.Properties['Entries'])
        {
            $rawEntries = @($presetData.Entries)
        }
        elseif ($presetData -is [System.Collections.IEnumerable] -and -not ($presetData -is [string]))
        {
            $rawEntries = @($presetData)
        }
        else
        {
            $rawEntries = @()
        }
    }
    else
    {
        $rawEntries = [System.IO.File]::ReadAllLines($presetPath)
    }

    foreach ($rawEntry in $rawEntries)
    {
        $commandLine = [string]$rawEntry
        if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }

        $trimmed = $commandLine.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

        $functionName = ($trimmed -split '\s+', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

        if ($commandIndex.ContainsKey($functionName))
        {
            $commandList[$commandIndex[$functionName]] = $trimmed
        }
        else
        {
            $commandIndex[$functionName] = $commandList.Count
            [void]$commandList.Add($trimmed)
        }
    }

    return $commandList.ToArray()
}

function global:Baseline
{
    [CmdletBinding(DefaultParameterSetName = 'Functions')]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Functions')]
        [string[]]
        $Functions,

        [Parameter(Mandatory = $true, ParameterSetName = 'Preset')]
        [string]
        $Preset,

        [Parameter(Mandatory = $true, ParameterSetName = 'GameMode')]
        [ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
        [string]
        $GameModeProfile,

        [Parameter(Mandatory = $false, ParameterSetName = 'GameMode')]
        [hashtable]
        $GameModeDecisionOverrides = @{},

        [Parameter(Mandatory = $true, ParameterSetName = 'Scenario')]
        [ValidateSet('Workstation', 'Privacy', 'Recovery')]
        [string]
        $ScenarioProfile
    )

    $resolvedFunctions = @()
    if ($PSCmdlet.ParameterSetName -eq 'Preset')
    {
        $resolvedFunctions = @(Get-BaselineInteractivePresetCommandList -PresetName $Preset)
        if (-not $resolvedFunctions -or $resolvedFunctions.Count -eq 0)
        {
            throw "Preset '$Preset' did not resolve to any commands."
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'GameMode')
    {
        $resolvedFunctions = @(Get-GameModeProfileCommandList -ProfileName $GameModeProfile -DecisionOverrides $GameModeDecisionOverrides)
        if (-not $resolvedFunctions -or $resolvedFunctions.Count -eq 0)
        {
            throw "Game Mode profile '$GameModeProfile' did not resolve to any commands."
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Scenario')
    {
        $resolvedFunctions = @(Get-ScenarioProfileCommandList -ProfileName $ScenarioProfile)
        if (-not $resolvedFunctions -or $resolvedFunctions.Count -eq 0)
        {
            throw "Scenario profile '$ScenarioProfile' did not resolve to any commands."
        }
    }
    else
    {
        $resolvedFunctions = @($Functions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    if (-not $resolvedFunctions -or $resolvedFunctions.Count -eq 0)
    {
        throw 'No functions were provided.'
    }

    if ($Global:Error)
    {
        $Global:Error.Clear()
    }

    $Global:BaselineHeadlessCommands = @($resolvedFunctions)

    foreach ($functionCall in $resolvedFunctions)
    {
        # Validate and invoke via AST parsing instead of Invoke-Expression.
        $tokens = $null
        $parseErrors = $null
        $commandAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $functionCall, [ref]$tokens, [ref]$parseErrors
        )

        $stmts = $commandAst.EndBlock.Statements
        if ($parseErrors.Count -gt 0 -or
            $stmts.Count -ne 1 -or
            $stmts[0] -isnot [System.Management.Automation.Language.PipelineAst] -or
            $stmts[0].PipelineElements.Count -ne 1 -or
            $stmts[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandAst])
        {
            throw "Invalid command format '$functionCall' - only simple function calls are allowed."
        }

        $commandElement = $stmts[0].PipelineElements[0]
        $fnName = $commandElement.GetCommandName()
        $resolvedCmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
        if (-not $resolvedCmd)
        {
            throw "Unknown function '$fnName'. Only functions loaded by the Baseline module are allowed."
        }

        $commandArgs = @($commandElement.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.SafeGetValue() })
        if ($commandArgs.Count -gt 0)
        {
            & $resolvedCmd @commandArgs
        }
        else
        {
            & $resolvedCmd
        }
    }

    Invoke-Command -ScriptBlock { PostActions; Errors }
}

$Host.UI.RawUI.WindowTitle = 'Baseline | Utility'

Remove-Module -Name Baseline -Force -ErrorAction Ignore
Import-Module -Name $Script:ModuleManifestPath -PassThru -Force -Global | Out-Null

$Global:Localization = Import-BaselineLocalization -BaseDirectory $Script:LocalizationRoot -UICulture $PSUICulture

$osName = (Get-OSInfo).OSName
$Host.UI.RawUI.WindowTitle = "Baseline | Utility for $osName"

# Run the mandatory startup checks before enabling tab completion.
InitialActions

# Register tab completion for the -Functions parameter so users can complete
# function names and their common arguments.
$functionCompleter = {
    param
    (
        $commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
    )

    $module = Get-Module -Name Baseline | Select-Object -First 1
    if (-not $module)
    {
        return
    }

    $commands = @($module.ExportedCommands.Keys | Sort-Object -Unique)
    foreach ($command in $commands)
    {
        $commandInfo = Get-Command -Name $command -ErrorAction SilentlyContinue
        if (-not $commandInfo)
        {
            continue
        }

        $parameterMetadata = @($commandInfo.ParameterSets.Parameters | Where-Object { $null -eq $_.Attributes.AliasNames })
        $parameterNames = @($parameterMetadata.Name | Sort-Object -Unique)

        if ($command -eq 'OneDrive')
        {
            $commandInfo.Name | Where-Object { $_ -like "*$wordToComplete*" }

            foreach ($parameterName in $parameterNames)
            {
                if ($parameterName -eq 'AllUsers')
                {
                    "OneDrive -Install -$parameterName" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            continue
        }

        if ($command -eq 'UnpinTaskbarShortcuts')
        {
            foreach ($parameterName in $parameterNames)
            {
                if ($parameterName -ne 'Shortcuts')
                {
                    continue
                }

                $validValues = @($parameterMetadata | Where-Object Name -eq $parameterName | ForEach-Object { $_.Attributes.ValidValues } | Select-Object -Unique)
                foreach ($validValue in $validValues)
                {
                    "UnpinTaskbarShortcuts -$parameterName $validValue" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }

                if ($validValues.Count -gt 1)
                {
                    "UnpinTaskbarShortcuts -$parameterName $($validValues -join ', ')" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            continue
        }

        if ($command -eq 'UninstallUWPApps')
        {
            $commandInfo.Name | Where-Object { $_ -like "*$wordToComplete*" }

            foreach ($parameterName in $parameterNames)
            {
                if ($parameterName -eq 'ForAllUsers')
                {
                    "UninstallUWPApps -$parameterName" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            continue
        }

        if ($command -eq 'Install-VCRedist')
        {
            foreach ($parameterName in $parameterNames)
            {
                if ($parameterName -ne 'Redistributables')
                {
                    continue
                }

                $validValues = @($parameterMetadata | Where-Object Name -eq $parameterName | ForEach-Object { $_.Attributes.ValidValues } | Select-Object -Unique)
                foreach ($validValue in $validValues)
                {
                    "Install-VCRedist -$parameterName $validValue" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }

                if ($validValues.Count -gt 1)
                {
                    "Install-VCRedist -$parameterName $($validValues -join ', ')" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            continue
        }

        if ($command -eq 'Install-DotNetRuntimes')
        {
            foreach ($parameterName in $parameterNames)
            {
                if ($parameterName -ne 'Runtimes')
                {
                    continue
                }

                $validValues = @($parameterMetadata | Where-Object Name -eq $parameterName | ForEach-Object { $_.Attributes.ValidValues } | Select-Object -Unique)
                foreach ($validValue in $validValues)
                {
                    "Install-DotNetRuntimes -$parameterName $validValue" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }

                if ($validValues.Count -gt 1)
                {
                    "Install-DotNetRuntimes -$parameterName $($validValues -join ', ')" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            continue
        }

        if ($command -eq 'DNSoverHTTPS')
        {
            $commandInfo.Name | Where-Object { $_ -like "*$wordToComplete*" }

            $validValues = @()
            try
            {
                $validValues = @((Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers -ErrorAction Stop).PSChildName) |
                    Where-Object { $_ -notmatch ':' }
            }
            catch
            {
                $validValues = @()
            }

            foreach ($validValue in $validValues)
            {
                foreach ($secondaryValue in $validValues)
                {
                    if ($validValue -eq $secondaryValue) { continue }
                    "DNSoverHTTPS -Enable -PrimaryDNS $validValue -SecondaryDNS $secondaryValue" |
                        Where-Object { $_ -like "*$wordToComplete*" } |
                        ForEach-Object { "`"$_`"" }
                }
            }

            'DNSoverHTTPS -Disable' | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object { "`"$_`"" }
            continue
        }

        if ($command -eq 'Set-Policy')
        {
            continue
        }

        $commandInfo.Name | Where-Object { $_ -like "*$wordToComplete*" }

        foreach ($parameterName in $parameterNames)
        {
            "$command -$parameterName" |
                Where-Object { $_ -like "*$wordToComplete*" } |
                ForEach-Object { "`"$_`"" }
        }
    }
}

Register-ArgumentCompleter -CommandName 'Baseline' -ParameterName 'Functions' -ScriptBlock $functionCompleter
Register-ArgumentCompleter -CommandName 'Baseline' -ParameterName 'Preset' -ScriptBlock {
    param
    (
        $commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
    )

    foreach ($presetName in @(Get-BaselineInteractivePresetNames))
    {
        if ($presetName -like "*$wordToComplete*")
        {
            $presetName
        }
    }
}

Register-ArgumentCompleter -CommandName 'Baseline' -ParameterName 'GameModeProfile' -ScriptBlock {
    param
    (
        $commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
    )

    foreach ($profileName in @(Get-GameModeProfileDefinitions | ForEach-Object { [string]$_.Name }))
    {
        if ($profileName -like "*$wordToComplete*")
        {
            $profileName
        }
    }
}

Register-ArgumentCompleter -CommandName 'Baseline' -ParameterName 'ScenarioProfile' -ScriptBlock {
    param
    (
        $commandName,
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
    )

    foreach ($profileName in @(Get-ScenarioProfileDefinitions | ForEach-Object { [string]$_.Name }))
    {
        if ($profileName -like "*$wordToComplete*")
        {
            $profileName
        }
    }
}

Write-Information -MessageData '' -InformationAction Continue
Write-Host 'Interactive Baseline session ready.' -ForegroundColor DarkYellow
Write-Verbose -Message 'Baseline -Functions <tab>' -Verbose
Write-Verbose -Message 'Baseline -Functions temp<tab>' -Verbose
Write-Verbose -Message 'Baseline -Preset <tab>' -Verbose
Write-Verbose -Message 'Baseline -Preset Basic' -Verbose
Write-Verbose -Message 'Baseline -GameModeProfile <tab>' -Verbose
Write-Verbose -Message 'Baseline -GameModeProfile Competitive' -Verbose
Write-Verbose -Message 'Baseline -ScenarioProfile <tab>' -Verbose
Write-Verbose -Message 'Baseline -ScenarioProfile Workstation' -Verbose
Write-Verbose -Message 'Baseline -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", "UninstallUWPApps -ForAllUsers"' -Verbose
Write-Verbose -Message 'Baseline -Functions "Set-Association -ProgramPath ""%ProgramFiles%\Notepad++\notepad++.exe"" -Extension .txt -Icon ""%ProgramFiles%\Notepad++\notepad++.exe,0"""' -Verbose
Write-Information -MessageData '' -InformationAction Continue
