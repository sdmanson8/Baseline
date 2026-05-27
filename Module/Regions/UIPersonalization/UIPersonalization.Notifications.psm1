using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

#region Notifications

<#
	.SYNOPSIS
	Configures notification and sound settings.



.DESCRIPTION

Applies Baseline's notification and sound settings in GUI and headless runs.
	.PARAMETER Enable
	Enable notification sounds globally

	.PARAMETER Disable
	Disable notification sounds globally

	.EXAMPLE
	Set-NotificationSounds -Enable

	.EXAMPLE
	Set-NotificationSounds -Disable

	.NOTES
	Current user. Controls NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND setting.
#>
function Set-NotificationSounds
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
			Write-ConsoleStatus -Action "Enabling notification sounds"
			LogInfo "Enabling notification sounds globally"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable notification sounds: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling notification sounds"
			LogInfo "Disabling notification sounds globally"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable notification sounds: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show notifications on lock screen



.DESCRIPTION

Shows notifications on lock screen from Baseline's GUI flow.
	.PARAMETER Enable
	Show notifications while on lock screen

	.PARAMETER Disable
	Hide notifications from lock screen

	.EXAMPLE
	Set-LockScreenNotifications -Enable

	.EXAMPLE
	Set-LockScreenNotifications -Disable

	.NOTES
	Current user. Controls NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK setting.
#>
function Set-LockScreenNotifications
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
			Write-ConsoleStatus -Action "Enabling notifications on lock screen"
			LogInfo "Enabling notifications on lock screen"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable lock screen notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling notifications on lock screen"
			LogInfo "Disabling notifications on lock screen"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable lock screen notifications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show reminders and VoIP calls on lock screen



.DESCRIPTION

Shows reminders and VoIP calls on lock screen from Baseline's GUI flow.
	.PARAMETER Enable
	Show reminders and VoIP calls on lock screen

	.PARAMETER Disable
	Hide reminders and VoIP calls from lock screen

	.EXAMPLE
	Set-CriticalNotificationsOnLockScreen -Enable

	.EXAMPLE
	Set-CriticalNotificationsOnLockScreen -Disable

	.NOTES
	Current user. Controls NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK setting.
#>
function Set-CriticalNotificationsOnLockScreen
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
			Write-ConsoleStatus -Action "Enabling reminders and VoIP calls on lock screen"
			LogInfo "Enabling reminders and VoIP calls on lock screen"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable critical lock screen notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling reminders and VoIP calls on lock screen"
			LogInfo "Disabling reminders and VoIP calls on lock screen"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable critical lock screen notifications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	DST and clock change notifications



.DESCRIPTION

Applies the Baseline behavior for dST and clock change notifications.
	.PARAMETER Enable
	Show daylight saving time and clock change notifications

	.PARAMETER Disable
	Hide daylight saving time and clock change notifications

	.EXAMPLE
	Set-DSTNotifications -Enable

	.EXAMPLE
	Set-DSTNotifications -Disable

	.NOTES
	Current user. Controls DstNotification setting.
#>
function Set-DSTNotifications
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
			Write-ConsoleStatus -Action "Enabling DST and clock change notifications"
			LogInfo "Enabling daylight saving time and clock change notifications"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "DstNotification" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable DST notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling DST and clock change notifications"
			LogInfo "Disabling daylight saving time and clock change notifications"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" `
					-Name "DstNotification" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable DST notifications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	App capability access notifications



.DESCRIPTION

Applies the Baseline behavior for app capability access notifications.
	.PARAMETER Enable
	Show app capability access notifications in system tray

	.PARAMETER Disable
	Hide app capability access notifications

	.EXAMPLE
	Set-CapabilityAccessNotifications -Enable

	.EXAMPLE
	Set-CapabilityAccessNotifications -Disable

	.NOTES
	Current user. Controls visibility of app permission notifications.
#>
function Set-CapabilityAccessNotifications
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
			Write-ConsoleStatus -Action "Enabling app capability access notifications"
			LogInfo "Enabling app capability access notifications"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.CapabilityAccessNotification" `
					-Name "Enabled" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable capability access notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling app capability access notifications"
			LogInfo "Disabling app capability access notifications"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.CapabilityAccessNotification"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "Enabled" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable capability access notifications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Startup app notifications



.DESCRIPTION

Applies the Baseline behavior for startup app notifications.
	.PARAMETER Enable
	Show notifications for apps starting up

	.PARAMETER Disable
	Hide startup app notifications

	.EXAMPLE
	Set-StartupAppNotifications -Enable

	.EXAMPLE
	Set-StartupAppNotifications -Disable

	.NOTES
	Current user. Affects visibility of startup task notifications.
#>
function Set-StartupAppNotifications
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
			Write-ConsoleStatus -Action "Enabling startup app notifications"
			LogInfo "Enabling startup app notifications"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupTask" `
					-Name "Enabled" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable startup app notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling startup app notifications"
			LogInfo "Disabling startup app notifications"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupTask"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "Enabled" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable startup app notifications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Security and Maintenance notifications



.DESCRIPTION

Applies the Baseline behavior for security and Maintenance notifications.
	.PARAMETER Enable
	Show Security and Maintenance notifications

	.PARAMETER Disable
	Hide Security and Maintenance notifications

	.EXAMPLE
	Set-SecurityMaintenanceNotifications -Enable

	.EXAMPLE
	Set-SecurityMaintenanceNotifications -Disable

	.NOTES
	Current user. Affects visibility of security and system maintenance alerts.
#>
function Set-SecurityMaintenanceNotifications
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
			Write-ConsoleStatus -Action "Enabling Security and Maintenance notifications"
			LogInfo "Enabling Security and Maintenance notifications"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" `
					-Name "Enabled" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Security and Maintenance notifications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Security and Maintenance notifications"
			LogInfo "Disabling Security and Maintenance notifications"
			try
			{
				$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance"
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $path `
					-Name "Enabled" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Security and Maintenance notifications: $($_.Exception.Message)"
			}
		}
	}
}

#endregion Notifications
$ExportedFunctions = @(
    'Set-CapabilityAccessNotifications',
    'Set-CriticalNotificationsOnLockScreen',
    'Set-DSTNotifications',
    'Set-LockScreenNotifications',
    'Set-NotificationSounds',
    'Set-SecurityMaintenanceNotifications',
    'Set-StartupAppNotifications'
)
Export-ModuleMember -Function $ExportedFunctions