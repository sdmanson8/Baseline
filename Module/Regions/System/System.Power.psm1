using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
    .SYNOPSIS
    Configures hibernation state management.



.DESCRIPTION

Applies Baseline's hibernation state management in GUI and headless runs.
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
				Write-ConsoleStatus -Status warning
				LogWarning "Hibernation was not disabled because Windows rejected the request: $($_.Exception.Message)"
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
				Write-ConsoleStatus -Status warning
				LogWarning "Hibernation was not enabled because Windows rejected the request: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Power plan



.DESCRIPTION

Applies the Baseline behavior for power plan.
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
		$Ultimate,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "CustomPower"
		)]
		[switch]
		$CustomPower
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
		"CustomPower"
		{
			# Custom power plan: duplicate the Ultimate Performance scheme
			# under a stable, recognisable GUID and rename it.
			# The GUID `57696e68-616e-6365-506f-776572000000` is used as the
			# canonical identifier so subsequent toggles can find the plan by
			# GUID alone.
			Write-ConsoleStatus -Action "Setting power plan to Custom Power Plan"
			LogInfo "Creating/activating Custom Power Plan"
			$ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
			$customPowerGuid = "57696e68-616e-6365-506f-776572000000"
			try
			{
				$existingPlans = POWERCFG /LIST 2>&1
				if ($existingPlans -notmatch [regex]::Escape($customPowerGuid))
				{
					if ($existingPlans -notmatch [regex]::Escape($ultimateGuid))
					{
						POWERCFG /DUPLICATESCHEME $ultimateGuid 2>&1 | Out-Null
					}
					POWERCFG /DUPLICATESCHEME $ultimateGuid $customPowerGuid 2>&1 | Out-Null
					POWERCFG -CHANGENAME $customPowerGuid "Custom Power Plan" "Optimized power plan for gaming and performance" 2>&1 | Out-Null
				}
				$verifyPlans = POWERCFG /LIST 2>&1
				if ($verifyPlans -match [regex]::Escape($customPowerGuid))
				{
					POWERCFG /SETACTIVE $customPowerGuid | Out-Null
					Write-ConsoleStatus -Status success
				}
				else
				{
					Write-ConsoleStatus -Status failed
					LogWarning "Failed to create Custom Power Plan; falling back to High Performance."
					POWERCFG /SETACTIVE SCHEME_MIN | Out-Null
				}
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Error creating Custom Power Plan: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Toggle Hybrid Sleep (combines sleep + hibernate).



.DESCRIPTION

Applies the Baseline behavior for toggle Hybrid Sleep (combines sleep + hibernate)..
	.PARAMETER Enable
	Enable Hybrid Sleep on AC and DC.

	.PARAMETER Disable
	Disable Hybrid Sleep on AC and DC.

	.NOTES
	Driven by powercfg subgroup SUB_SLEEP / setting HYBRIDSLEEP. See
	the power optimizations implementation for this setting.
	Hardware that does not support hybrid sleep will return a non-zero
	exit code from powercfg -- the function logs and continues rather
	than throwing because the surface is documented as best-effort.
#>
function HybridSleep
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]
		$Disable
	)

	$subgroup = "238c9fa8-0aad-41ed-83f4-97be242c8f20"  # SUB_SLEEP
	$setting  = "94ac6d29-73ce-41a6-809f-6363ba21b47e"  # HYBRIDSLEEP
	$value = if ($PSCmdlet.ParameterSetName -eq "Enable") { 1 } else { 0 }
	$displayName = if ($value -eq 1) { "Enabling Hybrid Sleep" } else { "Disabling Hybrid Sleep" }

	Write-ConsoleStatus -Action $displayName
	LogInfo $displayName
	try
	{
		Set-PowerSchemeSettingVisibility -SubgroupGuid $subgroup -SettingGuid $setting
		Set-PowerSchemeChoiceSetting -DisplayName 'Hybrid Sleep' -SubgroupGuid $subgroup -SettingGuid $setting -Value $value
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogWarning "HybridSleep not applied (may be unsupported on this hardware): $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Processor minimum state



.DESCRIPTION

Applies the Baseline behavior for processor minimum state.
	.PARAMETER Value
	Set the same processor minimum state on AC and DC.

	.PARAMETER ACValue
	Set the processor minimum state on AC power.

	.PARAMETER DCValue
	Set the processor minimum state on DC power.

	.EXAMPLE
	ProcessorMinimumState -ACValue 100 -DCValue 5

	.EXAMPLE
	ProcessorMinimumState -Value 50

	.NOTES
	Current user
#>

function ProcessorMinimumState
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor minimum state" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "893dee8e-2bef-41e0-89c6-b55d0929964c" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor minimum state" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "893dee8e-2bef-41e0-89c6-b55d0929964c" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	Processor maximum state



.DESCRIPTION

Applies the Baseline behavior for processor maximum state.
	.PARAMETER Value
	Set the same processor maximum state on AC and DC.

	.PARAMETER ACValue
	Set the processor maximum state on AC power.

	.PARAMETER DCValue
	Set the processor maximum state on DC power.

	.EXAMPLE
	ProcessorMaximumState -ACValue 100 -DCValue 100

	.EXAMPLE
	ProcessorMaximumState -Value 100

	.NOTES
	Current user
#>

function ProcessorMaximumState
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor maximum state" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "bc5038f7-23e0-4960-96da-33abaf5935ec" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor maximum state" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "bc5038f7-23e0-4960-96da-33abaf5935ec" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	Power throttling



.DESCRIPTION

Applies the Baseline behavior for power throttling.
	.PARAMETER Enable
	Enable power throttling (default value)

	.PARAMETER Disable
	Disable power throttling

	.EXAMPLE
	PowerThrottling -Enable

	.EXAMPLE
	PowerThrottling -Disable

	.NOTES
	Current user
#>
function PowerThrottling
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Power Throttling"
			LogInfo "Enabling Power Throttling"
			try
			{
				Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Type DWord -Value 0
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Power Throttling: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Power Throttling"
			LogInfo "Disabling Power Throttling"
			try
			{
				Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Type DWord -Value 1
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Power Throttling: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Processor performance increase threshold



.DESCRIPTION

Applies the Baseline behavior for processor performance increase threshold.
	.PARAMETER Value
	Set the same increase threshold on AC and DC.

	.PARAMETER ACValue
	Set the increase threshold on AC power.

	.PARAMETER DCValue
	Set the increase threshold on DC power.

	.EXAMPLE
	ProcessorPerformanceIncreaseThreshold -Value 10

	.NOTES
	Current user
#>
function ProcessorPerformanceIncreaseThreshold
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor performance increase threshold" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "06cadf0e-64ed-448a-8927-ce7bf90eb35d" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor performance increase threshold" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "06cadf0e-64ed-448a-8927-ce7bf90eb35d" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	Processor performance decrease threshold



.DESCRIPTION

Applies the Baseline behavior for processor performance decrease threshold.
	.PARAMETER Value
	Set the same decrease threshold on AC and DC.

	.PARAMETER ACValue
	Set the decrease threshold on AC power.

	.PARAMETER DCValue
	Set the decrease threshold on DC power.

	.EXAMPLE
	ProcessorPerformanceDecreaseThreshold -Value 8

	.NOTES
	Current user
#>
function ProcessorPerformanceDecreaseThreshold
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor performance decrease threshold" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor performance decrease threshold" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	Processor performance boost mode



.DESCRIPTION

Applies the Baseline behavior for processor performance boost mode.
	.PARAMETER Disabled
	Disable processor boost mode.

	.PARAMETER Enabled
	Enable processor boost mode.

	.PARAMETER Aggressive
	Use the aggressive boost mode.

	.PARAMETER SameAsEnabled
	Use the same behavior as Enabled.

	.PARAMETER SameAsAggressive
	Use the same behavior as Aggressive.

	.EXAMPLE
	ProcessorPerformanceBoostMode -Enabled

	.NOTES
	Current user
#>

function ProcessorPerformanceBoostMode
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disabled"
		)]
		[switch]
		$Disabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enabled"
		)]
		[switch]
		$Enabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Aggressive"
		)]
		[switch]
		$Aggressive,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SameAsEnabled"
		)]
		[switch]
		$SameAsEnabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SameAsAggressive"
		)]
		[switch]
		$SameAsAggressive
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disabled"
		{
			Write-ConsoleStatus -Action "Disabling Processor Performance Boost Mode"
			LogInfo "Disabling Processor Performance Boost Mode"
			try
			{
				Set-PowerSchemeSettingVisibility -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7"
				Set-PowerSchemeSettingValue -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7" -Value 0
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Processor Performance Boost Mode: $($_.Exception.Message)"
			}
		}
		"Enabled"
		{
			Write-ConsoleStatus -Action "Enabling Processor Performance Boost Mode"
			LogInfo "Enabling Processor Performance Boost Mode"
			try
			{
				Set-PowerSchemeSettingVisibility -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7"
				Set-PowerSchemeSettingValue -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7" -Value 1
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Processor Performance Boost Mode: $($_.Exception.Message)"
			}
		}
		"Aggressive"
		{
			Write-ConsoleStatus -Action "Setting Processor Performance Boost Mode to Aggressive"
			LogInfo "Setting Processor Performance Boost Mode to Aggressive"
			try
			{
				Set-PowerSchemeSettingVisibility -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7"
				Set-PowerSchemeSettingValue -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7" -Value 2
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Processor Performance Boost Mode to Aggressive: $($_.Exception.Message)"
			}
		}
		"SameAsEnabled"
		{
			Write-ConsoleStatus -Action "Setting Processor Performance Boost Mode to Same as Enabled"
			LogInfo "Setting Processor Performance Boost Mode to Same as Enabled"
			try
			{
				Set-PowerSchemeSettingVisibility -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7"
				Set-PowerSchemeSettingValue -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7" -Value 3
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Processor Performance Boost Mode to Same as Enabled: $($_.Exception.Message)"
			}
		}
		"SameAsAggressive"
		{
			Write-ConsoleStatus -Action "Setting Processor Performance Boost Mode to Same as Aggressive"
			LogInfo "Setting Processor Performance Boost Mode to Same as Aggressive"
			try
			{
				Set-PowerSchemeSettingVisibility -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7"
				Set-PowerSchemeSettingValue -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "be337238-0d82-4146-a960-4f3749d470c7" -Value 4
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Processor Performance Boost Mode to Same as Aggressive: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Processor energy performance preference



.DESCRIPTION

Applies the Baseline behavior for processor energy performance preference.
	.PARAMETER Value
	Set the same energy performance preference on AC and DC.

	.PARAMETER ACValue
	Set the energy performance preference on AC power.

	.PARAMETER DCValue
	Set the energy performance preference on DC power.

	.EXAMPLE
	ProcessorEnergyPerformancePreference -ACValue 0 -DCValue 50

	.NOTES
	Current user
#>
function ProcessorEnergyPerformancePreference
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor energy performance preference" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "processor energy performance preference" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "36687f9e-e3a5-4dbf-b1dc-15eb381c6863" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	CPU core parking minimum cores



.DESCRIPTION

Applies the Baseline behavior for cPU core parking minimum cores.
	.PARAMETER Value
	Set the same minimum core parking percentage on AC and DC power.

	.PARAMETER ACValue
	Set the minimum core parking percentage on AC power.

	.PARAMETER DCValue
	Set the minimum core parking percentage on DC power.

	.EXAMPLE
	ProcessorCoreParkingMinimumCores -ACValue 0 -DCValue 0

	.NOTES
	Current user
#>
function ProcessorCoreParkingMinimumCores
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "CPU Core Parking Minimum Cores" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "0cc5b647-c1df-4637-891a-dec35c318583" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "CPU Core Parking Minimum Cores" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "0cc5b647-c1df-4637-891a-dec35c318583" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	CPU core parking maximum cores



.DESCRIPTION

Applies the Baseline behavior for cPU core parking maximum cores.
	.PARAMETER Value
	Set the same maximum core parking percentage on AC and DC power.

	.PARAMETER ACValue
	Set the maximum core parking percentage on AC power.

	.PARAMETER DCValue
	Set the maximum core parking percentage on DC power.

	.EXAMPLE
	ProcessorCoreParkingMaximumCores -ACValue 100 -DCValue 100

	.NOTES
	Current user
#>
function ProcessorCoreParkingMaximumCores
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "CPU Core Parking Maximum Cores" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "ea062031-0e34-4ff1-9b6d-eb1059334028" -Value $Value
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "CPU Core Parking Maximum Cores" -SubgroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "ea062031-0e34-4ff1-9b6d-eb1059334028" -ACValue $ACValue -DCValue $DCValue
		}
	}
}

<#
	.SYNOPSIS
	USB Hub Selective Suspend Timeout



.DESCRIPTION

Applies the Baseline behavior for uSB Hub Selective Suspend Timeout.
	.PARAMETER Value
	Set the same USB hub suspend timeout on AC and DC power.

	.PARAMETER ACValue
	Set the USB hub suspend timeout on AC power.

	.PARAMETER DCValue
	Set the USB hub suspend timeout on DC power.

	.EXAMPLE
	USBHubSelectiveSuspendTimeout -ACValue 0 -DCValue 1000

	.NOTES
	Current user
#>
function USBHubSelectiveSuspendTimeout
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[ValidateRange(0, 100000)]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100000)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[ValidateRange(0, 100000)]
		[int]
		$DCValue
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Value"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "USB Hub Selective Suspend Timeout" -SubgroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "0853a681-27c8-4100-a2fd-82013e970683" -Value $Value -MinValue 0 -MaxValue 100000 -Units "Milliseconds"
		}
		"Channels"
		{
			Set-PowerSchemeNumericRangeSetting -DisplayName "USB Hub Selective Suspend Timeout" -SubgroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "0853a681-27c8-4100-a2fd-82013e970683" -ACValue $ACValue -DCValue $DCValue -MinValue 0 -MaxValue 100000 -Units "Milliseconds"
		}
	}
}

<#
	.SYNOPSIS
	USB selective suspend setting



.DESCRIPTION

Applies the Baseline behavior for uSB selective suspend setting.
	.PARAMETER Disabled
	Disable USB selective suspend.

	.PARAMETER Enabled
	Enable USB selective suspend (default value).

	.EXAMPLE
	USBSelectiveSuspend -Disabled

	.NOTES
	Current user
#>
function USBSelectiveSuspend
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disabled"
		)]
		[switch]
		$Disabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enabled"
		)]
		[switch]
		$Enabled
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disabled"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "USB selective suspend setting" -SubgroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -Value 0
		}
		"Enabled"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "USB selective suspend setting" -SubgroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -Value 1
		}
	}
}

<#
	.SYNOPSIS
	Intel(R) Graphics Power Plan



.DESCRIPTION

Applies the Baseline behavior for intel(R) Graphics Power Plan.
	.PARAMETER MaximumBatteryLife
	Use the maximum battery life power plan.

	.PARAMETER Balanced
	Use the balanced power plan (default value).

	.PARAMETER MaximumPerformance
	Use the maximum performance power plan.

	.EXAMPLE
	IntelGraphicsPowerPlan -Balanced

	.NOTES
	Current user
#>
function IntelGraphicsPowerPlan
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "MaximumBatteryLife"
		)]
		[switch]
		$MaximumBatteryLife,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Balanced"
		)]
		[switch]
		$Balanced,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "MaximumPerformance"
		)]
		[switch]
		$MaximumPerformance
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"MaximumBatteryLife"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "Intel(R) Graphics Power Plan" -SubgroupGuid "44f3beca-a7c0-460e-9df2-bb8b99e0cba6" -SettingGuid "3619c3f2-afb2-4afc-b0e9-e7fef372de36" -Value 0
		}
		"Balanced"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "Intel(R) Graphics Power Plan" -SubgroupGuid "44f3beca-a7c0-460e-9df2-bb8b99e0cba6" -SettingGuid "3619c3f2-afb2-4afc-b0e9-e7fef372de36" -Value 1
		}
		"MaximumPerformance"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "Intel(R) Graphics Power Plan" -SubgroupGuid "44f3beca-a7c0-460e-9df2-bb8b99e0cba6" -SettingGuid "3619c3f2-afb2-4afc-b0e9-e7fef372de36" -Value 2
		}
	}
}

<#
	.SYNOPSIS
	Video Playback Quality Bias



.DESCRIPTION

Applies the Baseline behavior for video Playback Quality Bias.
	.PARAMETER PowerSavingBias
	Prefer battery life over video playback smoothness.

	.PARAMETER PerformanceBias
	Prefer smoother video playback.

	.EXAMPLE
	MultimediaVideoPlaybackQualityBias -PerformanceBias

	.NOTES
	Current user
#>
function MultimediaVideoPlaybackQualityBias
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "PowerSavingBias"
		)]
		[switch]
		$PowerSavingBias,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "PerformanceBias"
		)]
		[switch]
		$PerformanceBias
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"PowerSavingBias"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "Video Playback Quality Bias" -SubgroupGuid "9596fb26-9850-41fd-ac3e-f7c3c00afd4b" -SettingGuid "10778347-1370-4ee0-8bbd-33bdacaade49" -Value 0
		}
		"PerformanceBias"
		{
			Set-PowerSchemeChoiceSetting -DisplayName "Video Playback Quality Bias" -SubgroupGuid "9596fb26-9850-41fd-ac3e-f7c3c00afd4b" -SettingGuid "10778347-1370-4ee0-8bbd-33bdacaade49" -Value 1
		}
	}
}

<#
    .SYNOPSIS
    Sets power scheme setting visibility.

    #>

function Set-PowerSchemeSettingVisibility
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$SubgroupGuid,

		[Parameter(Mandatory = $true)]
		[string]
		$SettingGuid
	)

	Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$SubgroupGuid\$SettingGuid" -Name "Attributes" -Type DWord -Value 0
}

<#
    .SYNOPSIS
    Sets power scheme numeric range setting.

    #>

function Set-PowerSchemeNumericRangeSetting
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$DisplayName,

		[Parameter(Mandatory = $true)]
		[string]
		$SubgroupGuid,

		[Parameter(Mandatory = $true)]
		[string]
		$SettingGuid,

		[int]
		$MinValue = 0,

		[int]
		$MaxValue = 100,

		[string]
		$Units = "%",

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Value"
		)]
		[Alias("NumericValue")]
		[int]
		$Value,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[int]
		$ACValue,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channels"
		)]
		[int]
		$DCValue
	)

	$desiredValue = if ($PSCmdlet.ParameterSetName -eq "Channels")
	{
		[ordered]@{
			ACValue = $ACValue
			DCValue = $DCValue
		}
	}
	else
	{
		$Value
	}

	Write-ConsoleStatus -Action "Setting $DisplayName"
	LogInfo "Setting $DisplayName"
	foreach ($candidateValue in @($Value, $ACValue, $DCValue))
	{
		if ($null -ne $candidateValue -and (($candidateValue -lt $MinValue) -or ($candidateValue -gt $MaxValue)))
		{
			Write-ConsoleStatus -Status failed
			LogError "Failed to set ${DisplayName}: Value $candidateValue is outside the supported range of $MinValue to $MaxValue."
			return
		}
	}

	try
	{
		Set-PowerSchemeSettingVisibility -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
		Set-PowerSchemeSettingValue -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -Value $desiredValue -Units $Units
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status warning
		LogWarning "Skipped setting ${DisplayName} because Windows rejected the power setting request: $($_.Exception.Message)"
	}
}

<#
    .SYNOPSIS
    Sets power scheme choice setting.

    #>

function Set-PowerSchemeChoiceSetting
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$DisplayName,

		[Parameter(Mandatory = $true)]
		[string]
		$SubgroupGuid,

		[Parameter(Mandatory = $true)]
		[string]
		$SettingGuid,

		[Parameter(Mandatory = $true)]
		[int]
		$Value
	)

	Write-ConsoleStatus -Action "Setting $DisplayName"
	LogInfo "Setting $DisplayName"
	try
	{
		Set-PowerSchemeSettingVisibility -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
		Set-PowerSchemeSettingValue -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -Value $Value
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status warning
		LogWarning "Skipped setting ${DisplayName} because Windows rejected the power setting request: $($_.Exception.Message)"
	}
}

Export-ModuleMember -Function 'Hibernation', 'HybridSleep', 'PowerPlan', 'ProcessorMinimumState', 'ProcessorMaximumState', 'PowerThrottling', 'ProcessorPerformanceIncreaseThreshold', 'ProcessorPerformanceDecreaseThreshold', 'ProcessorPerformanceBoostMode', 'ProcessorEnergyPerformancePreference', 'ProcessorCoreParkingMinimumCores', 'ProcessorCoreParkingMaximumCores', 'USBHubSelectiveSuspendTimeout', 'USBSelectiveSuspend', 'IntelGraphicsPowerPlan', 'MultimediaVideoPlaybackQualityBias'
