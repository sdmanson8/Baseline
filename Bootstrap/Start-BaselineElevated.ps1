<#
    .SYNOPSIS
    Launch Baseline with elevation when the current process is not already elevated.

    .DESCRIPTION
    This helper relaunches the Baseline entrypoint through the Windows elevation
    prompt so the main app can continue with admin-required actions.

    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Bootstrap\Start-BaselineElevated.ps1

    .NOTES
    This script is intended for end-user startup flow, not for direct system
    administration.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    .SYNOPSIS
#>

function New-BaselineLauncherArgumentList
{
    param(
        [string[]]$ForwardedArguments = @()
    )

    $argumentList = [System.Collections.Generic.List[string]]::new()
    foreach ($forwardedArgument in $ForwardedArguments)
    {
        [void]$argumentList.Add([string]$forwardedArgument)
    }

    return $argumentList.ToArray()
}

<#
    .SYNOPSIS
#>

function Start-BaselineElevated
{
    param(
        [string[]]$ForwardedArguments = @()
    )

    # Resolve the shipped launcher relative to the repo root.
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $launcherPath = Join-Path $repoRoot 'Baseline.exe'

    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf))
    {
        throw "Baseline.exe was not found next to the launcher helper: $launcherPath"
    }

    $argumentList = New-BaselineLauncherArgumentList -ForwardedArguments $ForwardedArguments
    $process = Start-Process -FilePath $launcherPath -Verb RunAs -ArgumentList $argumentList -PassThru -ErrorAction Stop

    if ($null -eq $process)
    {
        # Surface a clear failure if the elevation handoff does not start.
        throw 'Failed to start the elevated Baseline launcher process.'
    }
}

Start-BaselineElevated -ForwardedArguments $ForwardedArguments
