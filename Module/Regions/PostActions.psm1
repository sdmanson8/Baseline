using module ..\Logging.psm1
using module ..\SharedHelpers.psm1


#region Post Actions
function PostActions
{
	<#
		.SYNOPSIS
		Run the post-change refresh and cleanup actions after tweaks finish.

		.DESCRIPTION
		Refreshes shell state, applies any generated Local Group Policy text files,
		cleans up temporary policy files, restores previously opened folders where
		possible, and performs the extra post-run fixes expected by this preset.

		.EXAMPLE
		PostActions
	#>
	Write-ConsoleStatus -Action "Performing post actions"
	LogInfo "Performing post actions"

	<#
	    .SYNOPSIS
	    Gets post action requirement.

		#>
	function Get-PostActionRequirement
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Name
		)

		if (-not ($Global:BaselinePostActionRequirements -is [hashtable]))
		{
			return $false
		}

		if (-not $Global:BaselinePostActionRequirements.ContainsKey($Name))
		{
			return $false
		}

		return [bool]$Global:BaselinePostActionRequirements[$Name]
	}

	<#
	    .SYNOPSIS
	    Runs post action step.

		#>

	function Invoke-PostActionStep
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Action,

			[Parameter(Mandatory = $true)]
			[scriptblock]$ScriptBlock,

			[switch]$ContinueOnFailure
		)

		Write-ConsoleStatus -Action $Action
		LogInfo $Action

		try
		{
			& $ScriptBlock
			Write-ConsoleStatus -Status success
		}
		catch
		{
			if ($ContinueOnFailure)
			{
				Remove-HandledErrorRecord -ErrorRecord $_
				LogWarning "$Action was skipped: $($_.Exception.Message)"
				Write-ConsoleStatus -Status warning
				return
			}

			Write-ConsoleStatus -Status failed
			throw
		}
	}

	<#
	    .SYNOPSIS
	    Runs post action process.

		#>

	function Invoke-PostActionProcess
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$FilePath,

			[string[]]$ArgumentList,

			[Parameter(Mandatory = $true)]
			[string]$Description,

			[int]$TimeoutSeconds = 120,

			[string]$StandardOutputPath,

			[string]$StandardErrorPath
		)

		$processSplat = @{
			FilePath    = $FilePath
			WindowStyle = 'Hidden'
			PassThru    = $true
			ErrorAction = 'Stop'
		}

		if ($ArgumentList)
		{
			$processSplat['ArgumentList'] = $ArgumentList
		}

		if (-not [string]::IsNullOrWhiteSpace($StandardOutputPath))
		{
			$processSplat['RedirectStandardOutput'] = $StandardOutputPath
		}

		if (-not [string]::IsNullOrWhiteSpace($StandardErrorPath))
		{
			$processSplat['RedirectStandardError'] = $StandardErrorPath
		}

		$process = Start-Process @processSplat
		try
		{
			if (-not $process.WaitForExit($TimeoutSeconds * 1000))
			{
				try
				{
					Stop-BaselineProcessTree -Process $process -Source 'PostActions.ProcessTimeout'
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PostActions.Invoke-PostActionProcess:catch147' -Severity Debug }

					# Ignore cleanup failures after a timeout.
				}

				throw "$Description timed out after $TimeoutSeconds seconds"
			}

			$process.Refresh()
			$exitCode = try { $process.ExitCode } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PostActions.Invoke-PostActionProcess:catch156' -Severity Debug }
			 $null }
			if ($null -ne $exitCode -and $exitCode -ne 0)
			{
				throw "$Description returned exit code $exitCode"
			}
		}
		finally
		{
			try
			{
				$process.Dispose()
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'PostActions.Invoke-PostActionProcess:catch168' -Severity Debug }

				# Ignore process disposal failures.
			}
		}
	}

	<#
	    .SYNOPSIS
	    Runs post action power shell process.

		#>

	function Invoke-PostActionPowerShellProcess
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string]$Description,

			[Parameter(Mandatory = $true)]
			[string]$ScriptContent,

			[int]$TimeoutSeconds = 120
		)

		$processToken = [guid]::NewGuid().ToString('N')
		$standardOutputPath = Join-Path $env:TEMP "Baseline-$processToken-postaction.stdout.txt"
		$standardErrorPath = Join-Path $env:TEMP "Baseline-$processToken-postaction.stderr.txt"
		$scriptPath = Join-Path $env:TEMP "Baseline-$processToken-postaction.ps1"
		$powershellProcessPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

		try
		{
			Set-Content -LiteralPath $scriptPath -Value $ScriptContent -Encoding UTF8 -Force -ErrorAction Stop
			Invoke-PostActionProcess -FilePath $powershellProcessPath `
				-ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) `
				-Description $Description `
				-TimeoutSeconds $TimeoutSeconds `
				-StandardOutputPath $standardOutputPath `
				-StandardErrorPath $standardErrorPath

			if (Test-Path -LiteralPath $standardOutputPath)
			{
				return [string](Get-Content -LiteralPath $standardOutputPath -Raw -ErrorAction SilentlyContinue)
			}

			return $null
		}
		finally
		{
			Remove-Item -LiteralPath $standardOutputPath, $standardErrorPath, $scriptPath -Force -ErrorAction Ignore | Out-Null
		}
	}

		. (Join-Path $PSScriptRoot 'PostActions\PostActions\PostActions.ps1')
}
#endregion Post Actions
$ExportedFunctions = @(
    'PostActions'
)
Export-ModuleMember -Function $ExportedFunctions