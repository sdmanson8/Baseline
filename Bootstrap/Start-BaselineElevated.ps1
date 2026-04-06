[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-BaselineLauncherArgumentList
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$ForwardedArguments = @()
    )

    $argumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-WindowStyle'
        'Hidden'
        '-STA'
        '-File'
        $ScriptPath
    ))
    {
        [void]$argumentList.Add($argument)
    }

    foreach ($forwardedArgument in $ForwardedArguments)
    {
        [void]$argumentList.Add([string]$forwardedArgument)
    }

    return $argumentList.ToArray()
}

function Start-BaselineElevated
{
    param(
        [string[]]$ForwardedArguments = @()
    )

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $scriptPath = Join-Path $repoRoot 'Baseline.ps1'

    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf))
    {
        throw "Baseline.ps1 was not found next to the launcher helper: $scriptPath"
    }

    $argumentList = New-BaselineLauncherArgumentList -ScriptPath $scriptPath -ForwardedArguments $ForwardedArguments
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList $argumentList -PassThru -ErrorAction Stop

    if ($null -eq $process)
    {
        throw 'Failed to start the elevated Baseline PowerShell process.'
    }
}

Start-BaselineElevated -ForwardedArguments $ForwardedArguments
