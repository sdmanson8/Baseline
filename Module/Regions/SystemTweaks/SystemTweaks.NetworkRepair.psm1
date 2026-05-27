using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Reset the Windows network stack on explicit user request.

	.DESCRIPTION
	Runs the standard network stack reset sequence with visible status and
	exit-code enforcement. This is an explicit repair action, not a background
	fallback.

	.EXAMPLE
	NetworkStackReset
#>
function NetworkStackReset
{
	[CmdletBinding()]
	param()

	$netshPath = Join-Path $env:SystemRoot 'System32\netsh.exe'
	$steps = @(
		@{
			Label = 'Resetting Winsock catalog'
			Arguments = @('winsock', 'reset')
		},
		@{
			Label = 'Resetting WinHTTP proxy'
			Arguments = @('winhttp', 'reset', 'proxy')
		},
		@{
			Label = 'Resetting TCP/IP stack'
			Arguments = @('int', 'ip', 'reset')
		}
	)

	Write-ConsoleStatus -Action 'Resetting Windows network stack'
	LogInfo 'Resetting Windows network stack'

	try
	{
		$failedSteps = [System.Collections.Generic.List[object]]::new()
		foreach ($step in $steps)
		{
			LogInfo ([string]$step.Label)
			try
			{
				$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @($step.Arguments) -TimeoutSeconds 300 -AllowedExitCodes @(0)
			}
			catch
			{
				[void]$failedSteps.Add([pscustomobject]@{
					Label = [string]$step.Label
					Error = $_.Exception.Message
				})
				LogWarning "Network stack reset step '$($step.Label)' did not complete: $($_.Exception.Message)"
			}
		}

		LogWarning 'Restart required to complete the network stack reset.'
		if ($failedSteps.Count -gt 0)
		{
			LogWarning "Network stack reset completed with $($failedSteps.Count) step(s) that Windows rejected."
			Write-ConsoleStatus -Status warning
		}
		else
		{
			Write-ConsoleStatus -Status success
		}
	}
	catch
	{
		LogError "Network stack reset failed: $($_.Exception.Message)"
		Write-ConsoleStatus -Status failed
	}
}

$ExportedFunctions = @(
	'NetworkStackReset'
)
Export-ModuleMember -Function $ExportedFunctions
