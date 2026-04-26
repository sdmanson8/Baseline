using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Taskbar Clock

<#
	.SYNOPSIS
	Time in Notification Center

	.PARAMETER Show
	Show time in Notification Center

	.PARAMETER Hide
	Hide time in Notification Center (default value)

	.EXAMPLE
	ClockInNotificationCenter -Show

	.EXAMPLE
	ClockInNotificationCenter -Hide

	.NOTES
	Current user
#>
function ClockInNotificationCenter
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Show"
		{
			try
			{
				Write-ConsoleStatus -Action "Showing time in Notification Center"
				LogInfo "Showing time in Notification Center"
				Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowClockInNotificationCenter' -Value 1 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show time in Notification Center: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			try
			{
				Write-ConsoleStatus -Action "Hiding time in Notification Center"
				LogInfo "Hiding time in Notification Center"
				Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowClockInNotificationCenter' -Value 0 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide time in Notification Center: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Seconds on the taskbar clock

	.PARAMETER Show
	Show seconds on the taskbar clock

	.PARAMETER Hide
	Hide seconds on the taskbar clock (default value)

	.EXAMPLE
	SecondsInSystemClock -Show

	.EXAMPLE
	SecondsInSystemClock -Hide

	.NOTES
	Current user
#>
function SecondsInSystemClock
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Show"
		{
			try
			{
				Write-ConsoleStatus -Action "Showing seconds on the taskbar clock"
				LogInfo "Showing seconds on the taskbar clock"
				Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSecondsInSystemClock' -Value 1 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show seconds on the taskbar clock: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			try
			{
				Write-ConsoleStatus -Action "Hiding seconds on the taskbar clock"
				LogInfo "Hiding seconds on the taskbar clock"
				Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSecondsInSystemClock' -Value 0 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide seconds on the taskbar clock: $($_.Exception.Message)"
			}
		}
	}
}

#endregion Taskbar Clock

Export-ModuleMember -Function '*'
