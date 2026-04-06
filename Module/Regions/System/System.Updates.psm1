using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Active hours

	.PARAMETER Automatically
	Automatically adjust active hours for me based on daily usage

	.PARAMETER Manually
	Manually adjust active hours for me based on daily usage (default value)

	.EXAMPLE
	ActiveHours -Automatically

	.EXAMPLE
	ActiveHours -Manually

	.NOTES
	Machine-wide
#>
function ActiveHours
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatically"
		)]
		[switch]
		$Automatically,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Manually"
		)]
		[switch]
		$Manually
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoRebootWithLoggedOnUsers, AlwaysAutoRebootAtScheduledTime -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name NoAutoRebootWithLoggedOnUsers -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AlwaysAutoRebootAtScheduledTime -Type CLEAR | Out-Null

	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursEnd, ActiveHoursStart, SetActiveHours -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursEnd -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursStart -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name SetActiveHours -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Automatically"
		{
			Write-ConsoleStatus -Action "Automatically adjusting active hours for me based on daily usage"
			LogInfo "Automatically adjusting active hours for me based on daily usage"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name SmartActiveHoursState -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Manually"
		{
			Write-ConsoleStatus -Action "Manually adjusting active hours for me based on daily usage"
			LogInfo "Manually adjusting active hours for me based on daily usage"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name SmartActiveHoursState -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Windows latest updates

	.PARAMETER Disable
	Do not get the latest updates as soon as they're available (default value)

	.PARAMETER Enable
	Get the latest updates as soon as they're available

	.EXAMPLE
	WindowsLatestUpdate -Disable

	.EXAMPLE
	WindowsLatestUpdate -Enable

	.NOTES
	Machine-wide
#>
function WindowsLatestUpdate
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name AllowOptionalContent, SetAllowOptionalContent -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name AllowOptionalContent -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name SetAllowOptionalContent -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling getting the latest updates as soon as they're available"
			LogInfo "Disabling getting the latest updates as soon as they're available"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name IsContinuousInnovationOptedIn -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling getting the latest updates as soon as they're available"
			LogInfo "Enabling getting the latest updates as soon as they're available"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name IsContinuousInnovationOptedIn -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Restart as soon as possible to finish updating

	.PARAMETER Enable
	Restart as soon as possible to finish updating

	.PARAMETER Disable
	Don't restart as soon as possible to finish updating (default value)

	.EXAMPLE
	DeviceRestartAfterUpdate -Enable

	.EXAMPLE
	DeviceRestartAfterUpdate -Disable

	.NOTES
	Machine-wide
#>
function RestartDeviceAfterUpdate
{
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursEnd, ActiveHoursStart, SetActiveHours -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursEnd -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name ActiveHoursStart -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name SetActiveHours -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling restart as soon as possible to finish updating"
			LogInfo "Enabling restart as soon as possible to finish updating"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name IsExpedited -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling restart as soon as possible to finish updating"
			LogInfo "Disabling restart as soon as possible to finish updating"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name IsExpedited -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Notification when your PC requires a restart to finish updating

	.PARAMETER Show
	Notify me when a restart is required to finish updating

	.PARAMETER Hide
	Do not notify me when a restart is required to finish updating (default value)

	.EXAMPLE
	RestartNotification -Show

	.EXAMPLE
	RestartNotification -Hide

	.NOTES
	Machine-wide
#>
function RestartNotification
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name SetAutoRestartNotificationDisable -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate -Name SetAutoRestartNotificationDisable -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Show"
		{
			Write-ConsoleStatus -Action "Showing notification when your PC requires a restart to finish updating"
			LogInfo "Showing notification when your PC requires a restart to finish updating"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name RestartNotificationsAllowed2 -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Hiding notification when your PC requires a restart to finish updating"
			LogInfo "Hiding notification when your PC requires a restart to finish updating"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name RestartNotificationsAllowed2 -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Restart apps after signing in

	.PARAMETER Enable
	Automatically saving my restartable apps and restart them when I sign back in

	.PARAMETER Disable
	Turn off automatically saving my restartable apps and restart them when I sign back in (default value)

	.EXAMPLE
	SaveRestartableApps -Enable

	.EXAMPLE
	SaveRestartableApps -Disable

	.NOTES
	Current user
#>
function SaveRestartableApps
{
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
			Write-ConsoleStatus -Action "Enabling saving restartable apps and restarting them after signing in"
			LogInfo "Enabling saving restartable apps and restarting them after signing in"
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name RestartApps -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling saving restartable apps and restarting them after signing in"
			LogInfo "Disabling saving restartable apps and restarting them after signing in"
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name RestartApps -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Recommended troubleshooter preferences

	.PARAMETER Automatically
	Run troubleshooter automatically, then notify me

	.PARAMETER Default
	Ask me before running troubleshooter (default value)

	.EXAMPLE
	RecommendedTroubleshooting -Automatically

	.EXAMPLE
	RecommendedTroubleshooting -Default

	.NOTES
	In order this feature to work Windows level of diagnostic data gathering will be set to "Optional diagnostic data" and the error reporting feature will be turned on

	.NOTES
	Machine-wide
#>
function RecommendedTroubleshooting
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatically"
		)]
		[switch]
		$Automatically,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -Force -ErrorAction SilentlyContinue | Out-Null
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection -Name MaxTelemetryAllowed -Force -ErrorAction SilentlyContinue | Out-Null
	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack -Name ShowedToastAtLevel -Force -ErrorAction SilentlyContinue | Out-Null

	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -Type CLEAR | Out-Null

	# Turn on Windows Error Reporting
	Get-ScheduledTask -TaskName QueueReporting -ErrorAction SilentlyContinue | Enable-ScheduledTask | Out-Null
	Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\Windows Error Reporting" -Name Disabled -Force -ErrorAction SilentlyContinue | Out-Null

	Get-Service -Name WerSvc | Set-Service -StartupType Manual | Out-Null
	Get-Service -Name WerSvc | Start-Service | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Automatically"
		{
			Write-ConsoleStatus -Action "Setting troubleshooter preferences to automatically run"
			LogInfo "Setting troubleshooter preferences to automatically run"
			if (-not (Test-Path -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation))
			{
				New-Item -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation -Force | Out-Null
			}
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation -Name UserPreference -PropertyType DWord -Value 3 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting troubleshooter preferences to ask before running"
			LogInfo "Setting troubleshooter preferences to ask before running"
			if (-not (Test-Path -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation))
			{
				New-Item -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation -Force | Out-Null
			}
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsMitigation -Name UserPreference -PropertyType DWord -Value 2 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Search for apps in Microsoft Store from Open with dialog

	.PARAMETER Enable
	Allow searching for apps in Microsoft Store from Open with dialog

	.PARAMETER Disable
	Prevent searching for apps in Microsoft Store from Open with dialog

	.EXAMPLE
	SearchAppInStore -Enable

	.EXAMPLE
	SearchAppInStore -Disable

	.NOTES
	Current user
#>
function SearchAppInStore
{
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
			Write-ConsoleStatus -Action "Enabling searching for apps in Microsoft Store from Open with dialog"
			LogInfo "Enabling searching for apps in Microsoft Store from Open with dialog"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoUseStoreOpenWith" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable searching for apps in Microsoft Store from Open with dialog: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling searching for apps in Microsoft Store from Open with dialog"
			LogInfo "Disabling searching for apps in Microsoft Store from Open with dialog"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoUseStoreOpenWith" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable searching for apps in Microsoft Store from Open with dialog: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Receive updates for other Microsoft products

	.PARAMETER Enable
	Receive updates for other Microsoft products

	.PARAMETER Disable
	Do not receive updates for other Microsoft products (default value)

	.EXAMPLE
	UpdateMicrosoftProducts -Enable

	.EXAMPLE
	UpdateMicrosoftProducts -Disable

	.NOTES
	Current user
#>
function UpdateMicrosoftProducts
{
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AllowMUUpdateService -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AllowMUUpdateService -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling receiving updates for other Microsoft products"
			LogInfo "Enabling receiving updates for other Microsoft products"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name AllowMUUpdateService -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling receiving updates for other Microsoft products"
			LogInfo "Disabling receiving updates for other Microsoft products"
			Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name AllowMUUpdateService -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

Export-ModuleMember -Function '*'
