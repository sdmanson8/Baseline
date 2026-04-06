using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Hibernation

	.PARAMETER Disable
	Disable hibernation

	.PARAMETER Enable
	Enable hibernation (default value)

	.EXAMPLE
	Hibernation -Enable

	.EXAMPLE
	Hibernation -Disable

	.NOTES
	It isn't recommended to turn off for laptops

	.NOTES
	Current user
#>
function Hibernation
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Hibernation"
			LogInfo "Disabling Hibernation"
			try
			{
				POWERCFG /HIBERNATE OFF 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable hibernation: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Hibernation"
			LogInfo "Enabling Hibernation"
			try
			{
				POWERCFG /HIBERNATE ON 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable hibernation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Power plan

	.PARAMETER High
	Set power plan on "High performance"

	.PARAMETER Balanced
	Set power plan on "Balanced" (default value)

	.EXAMPLE
	PowerPlan -High

	.EXAMPLE
	PowerPlan -Balanced

	.NOTES
	It isn't recommended to turn on for laptops

	.NOTES
	Current user
#>
function PowerPlan
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "High"
		)]
		[switch]
		$High,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Balanced"
		)]
		[switch]
		$Balanced,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Ultimate"
		)]
		[switch]
		$Ultimate
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings -Name ActivePowerScheme -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Power\PowerSettings -Name ActivePowerScheme -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"High"
		{
			Write-ConsoleStatus -Action "Setting power plan to High Performance"
			LogInfo "Setting power plan to High Performance"
			POWERCFG /SETACTIVE SCHEME_MIN | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Balanced"
		{
			Write-ConsoleStatus -Action "Setting power plan to Balanced"
			LogInfo "Setting power plan to Balanced"
			POWERCFG /SETACTIVE SCHEME_BALANCED | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Ultimate"
		{
			Write-ConsoleStatus -Action "Setting power plan to Ultimate Performance"
			LogInfo "Setting power plan to Ultimate Performance"
			# Ultimate Performance GUID: e9a42b02-d5df-448d-aa00-03f14749eb61
			$ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
			$existingPlans = POWERCFG /LIST 2>&1
			if ($existingPlans -match $ultimateGuid)
			{
				POWERCFG /SETACTIVE $ultimateGuid | Out-Null
				Write-ConsoleStatus -Status success
			}
			else
			{
				# Attempt to unhide/create Ultimate Performance plan
				LogInfo "Ultimate Performance plan not found, attempting to create it"
				$duplicateOutput = POWERCFG /DUPLICATESCHEME $ultimateGuid 2>&1
				$createdPlans = POWERCFG /LIST 2>&1
				if ($createdPlans -match $ultimateGuid)
				{
					POWERCFG /SETACTIVE $ultimateGuid | Out-Null
					Write-ConsoleStatus -Status success
				}
				else
				{
					Write-ConsoleStatus -Status failed
					LogWarning "Ultimate Performance plan is not available on this system. Falling back to High Performance."
					POWERCFG /SETACTIVE SCHEME_MIN | Out-Null
				}
			}
		}
	}
}

Export-ModuleMember -Function '*'
