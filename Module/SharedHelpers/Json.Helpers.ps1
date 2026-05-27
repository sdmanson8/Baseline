<#
    .SYNOPSIS
    JSON parsing helpers for Baseline's Windows PowerShell 5.1 runtime.

    .DESCRIPTION
    Baseline targets Windows PowerShell 5.1, but several call sites still
    want to state an explicit JSON nesting cap in code. This wrapper accepts
    -Depth unconditionally and forwards it only when the underlying cmdlet
    exposes that parameter.
#>

function ConvertFrom-BaselineJson
{
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0, Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$InputObject,

        [int]$Depth = 16,

        [switch]$AsHashtable,

        [switch]$NoEnumerate
    )

    process
    {
        $params = @{ InputObject = $InputObject }
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ErrorAction'))
        {
            $params['ErrorAction'] = $PSCmdlet.MyInvocation.BoundParameters['ErrorAction']
        }

        $convertFromJsonCommand = Microsoft.PowerShell.Core\Get-Command -Name 'ConvertFrom-Json' -CommandType Cmdlet -ErrorAction Stop
        if ($convertFromJsonCommand.Parameters.ContainsKey('Depth'))
        {
            $params['Depth'] = $Depth
        }

        if ($AsHashtable -and $convertFromJsonCommand.Parameters.ContainsKey('AsHashtable'))  { $params['AsHashtable']  = $true }
        if ($NoEnumerate -and $convertFromJsonCommand.Parameters.ContainsKey('NoEnumerate'))  { $params['NoEnumerate']  = $true }

        Microsoft.PowerShell.Utility\ConvertFrom-Json @params
    }
}
