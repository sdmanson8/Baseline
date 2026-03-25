using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region UI & Personalization

<#
    .SYNOPSIS
    Clearing of recent files on exit

    .DESCRIPTION
    Empties most recently used (MRU) items lists such as 'Recent Items' menu on the Start menu, jump lists, and shortcuts at the bottom of the 'File' menu in applications during every logout

    .PARAMETER Enable
    Enable the clearing of recent files on exit

    .PARAMETER Disable
    Disable the clearing of recent files on exit (default value)

    .EXAMPLE
    ClearRecentFiles -Enable

    .EXAMPLE
    ClearRecentFiles -Disable

    .NOTES
    Current user
#>
function ClearRecentFiles
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
			Write-ConsoleStatus -Action "Enabling the clearing of recent files on exit"
			LogInfo "Enabling the clearing of recent files on exit"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ClearRecentDocsOnExit" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable clearing of recent files on exit: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the clearing of recent files on exit"
			LogInfo "Disabling the clearing of recent files on exit"
			try
			{
				if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ClearRecentDocsOnExit" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable clearing of recent files on exit: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Recent files lists settings

    .DESCRIPTION
    Most recently used (MRU) items lists such as 'Recent Items' menu on the Start menu, jump lists, and shortcuts at the bottom of the 'File' menu in applications

    .PARAMETER Enable
    Enable the recent files lists (default value)

    .PARAMETER Disable
    Disable the recent files lists

    .EXAMPLE
    RecentFiles -Enable

    .EXAMPLE
    RecentFiles -Disable

    .NOTES
    Current user
#>
function RecentFiles
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
			Write-ConsoleStatus -Action "Enabling the recent files lists"
			LogInfo "Enabling the recent files lists"
			try
			{
				if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoRecentDocsHistory" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable recent files lists: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the recent files lists"
			LogInfo "Disabling the recent files lists"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoRecentDocsHistory" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable recent files lists: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show me suggested content in the Settings app

	.PARAMETER Hide
	Hide from me suggested content in the Settings app

	.PARAMETER Show
	Show me suggested content in the Settings app (default value)

	.EXAMPLE
	SettingsSuggestedContent -Hide

	.EXAMPLE
	SettingsSuggestedContent -Show

	.NOTES
	Current user
#>
function SettingsSuggestedContent
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling suggested content in the Settings app"
			LogInfo "Disabling suggested content in the Settings app"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-338393Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-353694Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-353696Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable suggested content in the Settings app: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling suggested content in the Settings app"
			LogInfo "Enabling suggested content in the Settings app"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-338393Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-353694Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-353696Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable suggested content in the Settings app: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Ways to get the most out of Windows and finish setting up this device

	.PARAMETER Disable
	Do not suggest ways to get the most out of Windows and finish setting up this device

	.PARAMETER Enable
	Suggest ways to get the most out of Windows and finish setting up this device (default value)

	.EXAMPLE
	WhatsNewInWindows -Disable

	.EXAMPLE
	WhatsNewInWindows -Enable

	.NOTES
	Current user
#>
function WhatsNewInWindows
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

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-Host 'Disabling "suggest ways to get the most out of Windows and finish setting up this device" - ' -NoNewline
			LogInfo 'Disabling "suggest ways to get the most out of Windows and finish setting up this device"'
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement -Name ScoobeSystemSettingEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError 'Failed to disable "suggest ways to get the most out of Windows and finish setting up this device": $($_.Exception.Message)'
			}
		}
		"Enable"
		{
			Write-Host 'Enabling "suggest ways to get the most out of Windows and finish setting up this device" - ' -NoNewline
			LogInfo 'Enabling "suggest ways to get the most out of Windows and finish setting up this device"'
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement -Name ScoobeSystemSettingEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError 'Failed to enable "suggest ways to get the most out of Windows and finish setting up this device": $($_.Exception.Message)'
			}
		}
	}
}

<#
	.SYNOPSIS
	Getting tip and suggestions when I use Windows

	.PARAMETER Enable
	Get tip and suggestions when using Windows (default value)

	.PARAMETER Disable
	Do not get tip and suggestions when I use Windows

	.EXAMPLE
	WindowsTips -Enable

	.EXAMPLE
	WindowsTips -Disable

	.NOTES
	Current user
#>
function WindowsTips
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent -Name DisableSoftLanding -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\CloudContent -Name DisableSoftLanding -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling tip and suggestions when I use Windows"
			LogInfo "Enabling tip and suggestions when I use Windows"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-338389Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows tips and suggestions: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling tip and suggestions when I use Windows"
			LogInfo "Disabling tip and suggestions when I use Windows"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-338389Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows tips and suggestions: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Windows welcome experiences after updates and occasionally when I sign in to highlight what's new and suggested

	.PARAMETER Hide
	Hide the Windows welcome experiences after updates and occasionally when I sign in to highlight what's new and suggested

	.PARAMETER Show
	Show the Windows welcome experiences after updates and occasionally when I sign in to highlight what's new and suggested (default value)

	.EXAMPLE
	WindowsWelcomeExperience -Hide

	.EXAMPLE
	WindowsWelcomeExperience -Show

	.NOTES
	Current user
#>
function WindowsWelcomeExperience
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
			Write-ConsoleStatus -Action "Enabling Windows welcome experience"
			LogInfo "Enabling Windows welcome experience"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-310093Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows welcome experience: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling Windows welcome experience"
			LogInfo "Disabling Windows welcome experience"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SubscribedContent-310093Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows welcome experience: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Notification area tray icons visibility in Windows

	.PARAMETER Enable
	Always show all notification area tray icons

	.PARAMETER Disable
	Allow Windows to hide inactive notification area tray icons (default value)

	.EXAMPLE
	TrayIcons -Enable

	.EXAMPLE
	TrayIcons -Disable

	.NOTES
	Current user
#>
function TrayIcons
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
			Write-ConsoleStatus -Action "Enabling all notification area tray icons"
			LogInfo "Enabling all notification area tray icons"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoAutoTrayNotify" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable all notification area tray icons: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling all notification area tray icons"
			LogInfo "Disabling all notification area tray icons"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoAutoTrayNotify" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoAutoTrayNotify" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable all notification area tray icons: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Allow or prevent changing Windows sound scheme

	.PARAMETER Enable
	Allow changing Windows sound scheme (default value)

	.PARAMETER Disable
	Prevent changing Windows sound scheme

	.EXAMPLE
	ChangingSoundScheme -Enable

	.EXAMPLE
	ChangingSoundScheme -Disable

	.NOTES
	Current user
#>
function ChangingSoundScheme
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
			Write-ConsoleStatus -Action "Enabling changing Windows sound scheme"
			LogInfo "Enabling changing Windows sound scheme"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingSoundScheme" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingSoundScheme" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable changing Windows sound scheme: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling changing Windows sound scheme"
			LogInfo "Disabling changing Windows sound scheme"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingSoundScheme" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable changing Windows sound scheme: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enhanced pointer precision (mouse acceleration) settings

	.PARAMETER Enable
	Enable enhanced pointer precision

	.PARAMETER Disable
	Disable enhanced pointer precision (default value)

	.EXAMPLE
	EnhPointerPrecision -Enable

	.EXAMPLE
	EnhPointerPrecision -Disable

	.NOTES
	Current user
#>
function EnhPointerPrecision
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
			Write-ConsoleStatus -Action "Enabling enhanced pointer precision"
			LogInfo "Enabling enhanced pointer precision"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Type String -Value "1" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Type String -Value "6" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Type String -Value "10" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable enhanced pointer precision: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling enhanced pointer precision"
			LogInfo "Disabling enhanced pointer precision"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Type String -Value "0" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Type String -Value "0" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Type String -Value "0" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable enhanced pointer precision: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File delete confirmation dialog in File Explorer

	.PARAMETER Enable
	Show confirmation dialog when deleting files

	.PARAMETER Disable
	Do not show confirmation dialog when deleting files (default value)

	.EXAMPLE
	FileDeleteConfirm -Enable

	.EXAMPLE
	FileDeleteConfirm -Disable

	.NOTES
	Current user
#>
function FileDeleteConfirm
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
			Write-ConsoleStatus -Action "Enabling confirmation dialog when deleting files"
			LogInfo "Enabling confirmation dialog when deleting files"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ConfirmFileDelete" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable file delete confirmation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling confirmation dialog when deleting files"
			LogInfo "Disabling confirmation dialog when deleting files"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ConfirmFileDelete" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ConfirmFileDelete" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable file delete confirmation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File operation progress details in File Explorer

	.PARAMETER Enable
	Show detailed file operation progress information

	.PARAMETER Disable
	Hide detailed file operation progress information

	.EXAMPLE
	FileOperationsDetails -Enable

	.EXAMPLE
	FileOperationsDetails -Disable

	.NOTES
	Current user
#>
function FileOperationsDetails
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
			Write-ConsoleStatus -Action "Enabling detailed file progress information"
			LogInfo "Enabling detailed file progress information"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable detailed file operation information: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling detailed file progress information"
			LogInfo "Disabling detailed file progress information"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable detailed file operation information: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enable or disable the Windows lock screen

	.PARAMETER Enable
	Enable the Windows lock screen (default value)

	.PARAMETER Disable
	Disable the Windows lock screen

	.EXAMPLE
	LockScreen -Enable

	.EXAMPLE
	LockScreen -Disable

	.NOTES
	Current user
#>
function LockScreen
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

	$OS = (Get-CimInstance Win32_OperatingSystem).Caption

	if ($OS -notlike "*Windows 11*")
	{
		#LogInfo "LockScreen skipped - Not Windows 11"
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the Windows lockscreen"
			LogInfo "Enabling the Windows lockscreen"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Windows lock screen: $($_.Exception.Message)"
			}
		}

		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Windows lockscreen"
			LogInfo "Disabling the Windows lockscreen"

			try
			{
				if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"))
				{
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Windows lock screen: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enable or disable the Windows 10 RS1-style lock screen task workaround.

	.DESCRIPTION
	On supported Windows 10 systems, registers or removes the scheduled task
	workaround used by this preset to keep the lock screen disabled.

	.PARAMETER Enable
	Enable the Windows lock screen on supported Windows 10 systems.

	.PARAMETER Disable
	Disable the Windows lock screen on supported Windows 10 systems.

	.EXAMPLE
	LockScreenRS1 -Enable

	.EXAMPLE
	LockScreenRS1 -Disable

	.NOTES
	Machine-wide
#>
function LockScreenRS1
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$OS = (Get-CimInstance Win32_OperatingSystem).Caption

	if ($OS -notlike "*Windows 10*")
	{
		#LogInfo "LockScreenRS1 skipped - Not Windows 10"
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the Windows lockscreen"
			LogInfo "Enabling the Windows lockscreen"
			try
			{
				$scheduledTask = Get-ScheduledTask -TaskName "Disable LockScreen" -ErrorAction Ignore
				if ($null -ne $scheduledTask)
				{
					Unregister-ScheduledTask -TaskName "Disable LockScreen" -Confirm:$false -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Windows lock screen scheduled task workaround: $($_.Exception.Message)"
			}
		}

		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Windows lockscreen"
			LogInfo "Disabling the Windows lockscreen"

			try
			{
				$service = New-Object -ComObject Schedule.Service
				$service.Connect()

				$task = $service.NewTask(0)
				$task.Settings.DisallowStartIfOnBatteries = $false

				$trigger = $task.Triggers.Create(9)
				$trigger = $task.Triggers.Create(11)
				$trigger.StateChange = 8

				$action = $task.Actions.Create(0)
				$action.Path = "reg.exe"
				$action.Arguments = "add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\SessionData /t REG_DWORD /v AllowLockScreen /d 0 /f"

				$service.GetFolder("\").RegisterTaskDefinition(
					"Disable LockScreen",
					$task,
					6,
					"NT AUTHORITY\SYSTEM",
					$null,
					4
				) | Out-Null

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Windows lock screen scheduled task workaround: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Lock screen blur effect

    .PARAMETER Enable
    Enable lock screen blur effect (default value)

    .PARAMETER Disable
    Disable lock screen blur effect

    .EXAMPLE
    LockScreenBlur -Enable

    .EXAMPLE
    LockScreenBlur -Disable

    .NOTES
    Current user
#>
# Lock screen Blur - Applicable since 1903
function LockScreenBlur
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
			Write-ConsoleStatus -Action "Enabling blurring of the lockscreen"
			LogInfo "Enabling blurring of the lockscreen"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableAcrylicBackgroundOnLogon" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Enabling blurring of the lockscreen"
			LogInfo "Enabling blurring of the lockscreen"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableAcrylicBackgroundOnLogon" -Type DWord -Value 1 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Show or hide network options on the lock screen

	.PARAMETER Enable
	Allow network selection from the lock screen (default value)

	.PARAMETER Disable
	Prevent network selection from the lock screen

	.EXAMPLE
	NetworkFromLockScreen -Enable

	.EXAMPLE
	NetworkFromLockScreen -Disable

	.NOTES
	Current user
#>
# Network options from Lock Screen
function NetworkFromLockScreen
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
			Write-ConsoleStatus -Action "Enabling the Network options on the lockscreen"
			LogInfo "Enabling the Network options on the lockscreen"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DontDisplayNetworkSelectionUI" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Network options on the lockscreen"
			LogInfo "Disabling the Network options on the lockscreen"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DontDisplayNetworkSelectionUI" -Type DWord -Value 1 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Shutdown option on the lock screen

	.PARAMETER Enable
	Allow shutdown from the lock screen (default value)

	.PARAMETER Disable
	Do not allow shutdown from the lock screen

	.EXAMPLE
	ShutdownFromLockScreen -Enable

	.EXAMPLE
	ShutdownFromLockScreen -Disable

	.NOTES
	Current user
#>
# Shutdown options from Lock Screen
function ShutdownFromLockScreen
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
			Write-ConsoleStatus -Action "Enabling the shutdown options on the lockscreen"
			LogInfo "Enabling the shutdown options on the lockscreen"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ShutdownWithoutLogon" -Type DWord -Value 1 | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the shutdown options on the lockscreen"
			LogInfo "Disabling the shutdown options on the lockscreen"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ShutdownWithoutLogon" -Type DWord -Value 0 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Play or disable Windows startup sound

	.PARAMETER Enable
	Play Windows startup sound

	.PARAMETER Disable
	Do not play Windows startup sound (default value)

	.EXAMPLE
	StartupSound -Enable

	.EXAMPLE
	StartupSound -Disable

	.NOTES
	Current user
#>
function StartupSound
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
			Write-ConsoleStatus -Action "Enabling Windows startup sound"
			LogInfo "Enabling Windows startup sound"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows startup sound: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows startup sound"
			LogInfo "Disabling Windows startup sound"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows startup sound: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Task Manager details view in Windows 10 and later

	.PARAMETER Enable
	Always show full details view in Task Manager

	.PARAMETER Disable
	Revert Task Manager to default summary view

	.EXAMPLE
	TaskManagerDetails -Enable

	.EXAMPLE
	TaskManagerDetails -Disable

	.NOTES
	Current user
	Anniversary Update workaround. The GPO used in DisableTaskManagerDetails has been broken in 1607 and fixed again in 1803
#>
function TaskManagerDetails
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
			Write-ConsoleStatus -Action "Enabling Task Manager detailed view"
			LogInfo "Enabling Task Manager detailed view"
			try
			{
				$taskmgr = Start-Process -WindowStyle Hidden -FilePath taskmgr.exe -PassThru -ErrorAction Stop
				$timeout = 30000
				$sleep = 100
				Do {
					Start-Sleep -Milliseconds $sleep
					$timeout -= $sleep
					$preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
				} Until ($preferences -or $timeout -le 0)
				Stop-Process $taskmgr -ErrorAction SilentlyContinue | Out-Null
				If ($preferences) {
					$preferences.Preferences[28] = 0
					Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -Type Binary -Value $preferences.Preferences -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Task Manager detailed view: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Task Manager detailed view"
			LogInfo "Disabling Task Manager detailed view"
			try
			{
				$preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
				If ($preferences) {
					$preferences.Preferences[28] = 1
					Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -Type Binary -Value $preferences.Preferences -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Task Manager detailed view: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Window title bar color adapts to the prevalent background color

	.PARAMETER Enable
	Enable title bar color to match prevalent background color

	.PARAMETER Disable
	Disable title bar color adaptation to background (default value)

	.EXAMPLE
	TitleBarColor -Enable

	.EXAMPLE
	TitleBarColor -Disable

	.NOTES
	Current user
#>
function TitleBarColor
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
			Write-ConsoleStatus -Action "Enabling title bar color adaptation to background"
			LogInfo "Enabling title bar color adaptation to background"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable title bar color adaptation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling title bar color adaptation to background"
			LogInfo "Disabling title bar color adaptation to background"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable title bar color adaptation: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows visual effects performance and appearance settings

	.PARAMETER Performance
	Adjust visual effects for best performance

	.PARAMETER Appearance
	Adjust visual effects for best appearance (default value)

	.EXAMPLE
	VisualFX -Performance

	.EXAMPLE
	VisualFX -Appearance

	.NOTES
	Current user
#>
function VisualFX
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Performance"
		)]
		[switch]
		$Performance,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Appearance"
		)]
		[switch]
		$Appearance
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Performance"
		# Adjusts visual effects for performance - Disables animations, transparency etc. but leaves font smoothing and miniatures enabled
		{
			Write-ConsoleStatus -Action "Adjusting visual effects for performance"
			LogInfo "Adjusting visual effects for performance"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Type String -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type String -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0)) -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 3 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to adjust visual effects for performance: $($_.Exception.Message)"
			}
		}
		"Appearance"
		# Adjusts visual effects for appearance
		{
			Write-ConsoleStatus -Action "Adjusting visual effects for appearance"
			LogInfo "Adjusting visual effects for appearance"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Type String -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type String -Value 400 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](158,30,7,128,18,0,0,0)) -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 3 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to adjust visual effects for appearance: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Title bar window shake

	.PARAMETER Enable
	When I grab a windows's title bar and shake it, minimize all other windows

	.PARAMETER Disable
	When I grab a windows's title bar and shake it, don't minimize all other windows (default value)

	.EXAMPLE
	AeroShaking -Enable

	.EXAMPLE
	AeroShaking -Disable

	.NOTES
	Current user
#>
function AeroShaking
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
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\Software\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoWindowMinimizingShortcuts -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Title bar window shake"
			LogInfo "Enabling Title bar window shake"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name DisallowShaking -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Title bar window shake: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Title bar window shake"
			LogInfo "Disabling Title bar window shake"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name DisallowShaking -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Title bar window shake: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The default app mode

	.PARAMETER Dark
	Set the default app mode to dark

	.PARAMETER Light
	Set the default app mode to light (default value)

	.EXAMPLE
	AppColorMode -Dark

	.EXAMPLE
	AppColorMode -Light

	.NOTES
	Current user
#>
function AppColorMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Dark"
		)]
		[switch]
		$Dark,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Light"
		)]
		[switch]
		$Light
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Dark"
		{
			Write-ConsoleStatus -Action "Setting Apps to use Dark Mode"
			LogInfo "Setting Apps to use Dark Mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set app color mode to Dark: $($_.Exception.Message)"
			}
		}
		"Light"
		{
			Write-ConsoleStatus -Action "Setting Apps to use Light Mode"
			LogInfo "Setting Apps to use Light Mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set app color mode to Light: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Windows build number and edition display on desktop

    .PARAMETER Enable
    Enable the build number and edition display

    .PARAMETER Disable
    Disable the build number and edition display (default value)

    .EXAMPLE
    BuildNumberOnDesktop -Enable

    .EXAMPLE
    BuildNumberOnDesktop -Disable

    .NOTES
    Current user
#>
function BuildNumberOnDesktop
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
			Write-ConsoleStatus -Action "Enabling build number and edition display on the Desktop"
			LogInfo "Enabling build number and edition display on the Desktop"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "PaintDesktopVersion" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable build number and edition display on the Desktop: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling build number and edition display on the Desktop"
			LogInfo "Disabling build number and edition display on the Desktop"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "PaintDesktopVersion" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable build number and edition display on the Desktop: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Control Panel icons view

	.PARAMETER Category
	View the Control Panel icons by category (default value)

	.PARAMETER LargeIcons
	View the Control Panel icons by large icons

	.PARAMETER SmallIcons
	View the Control Panel icons by Small icons

	.EXAMPLE
	ControlPanelView -Category

	.EXAMPLE
	ControlPanelView -LargeIcons

	.EXAMPLE
	ControlPanelView -SmallIcons

	.NOTES
	Current user
#>
function ControlPanelView
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Category"
		)]
		[switch]
		$Category,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "LargeIcons"
		)]
		[switch]
		$LargeIcons,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SmallIcons"
		)]
		[switch]
		$SmallIcons
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ForceClassicControlPanel -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ForceClassicControlPanel -Type CLEAR | Out-Null

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Category"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Category"
			LogInfo "Setting Control Panel to be viewed by Category"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name AllItemsIconView -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name StartupPage -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Category: $($_.Exception.Message)"
			}
		}
		"LargeIcons"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Large Icons"
			LogInfo "Setting Control Panel to be viewed by Large Icons"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name AllItemsIconView -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name StartupPage -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Large Icons: $($_.Exception.Message)"
			}
		}
		"SmallIcons"
		{
			Write-ConsoleStatus -Action "Setting Control Panel to be viewed by Small Icons"
			LogInfo "Setting Control Panel to be viewed by Small Icons"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name AllItemsIconView -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name StartupPage -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Control Panel view to Small Icons: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Files and folders grouping in the Downloads folder

	.PARAMETER None
	Do not group files and folder in the Downloads folder

	.PARAMETER Default
	Group files and folder by date modified in the Downloads folder (default value)

	.EXAMPLE
	FolderGroupBy -None

	.EXAMPLE
	FolderGroupBy -Default

	.NOTES
	Current user
#>
function FolderGroupBy
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "None"
		)]
		[switch]
		$None,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"None"
		{
			Write-ConsoleStatus -Action "Enabling grouping of files and folder in the Downloads folder"
			LogInfo "Enabling grouping of files and folder in the Downloads folder"
			# Clear any Common Dialog views
			Get-ChildItem -Path "HKCU:\Software\Microsoft\Windows\Shell\Bags\*\Shell" -ErrorAction SilentlyContinue |
    		Where-Object { $_.PSChildName -eq "{885A186E-A440-4ADA-812B-DB871B942259}" } |
    		Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

			# https://learn.microsoft.com/en-us/windows/win32/properties/props-system-null
			if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}"))
			{
				New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Force | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name ColumnList -PropertyType String -Value "System.Null" -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name GroupBy -PropertyType String -Value "System.Null" -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name LogicalViewMode -PropertyType DWord -Value 1 -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name Name -PropertyType String -Value NoName -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name Order -PropertyType DWord -Value 0 -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name PrimaryProperty -PropertyType String -Value "System.ItemNameDisplay" -Force | Out-Null
			New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}\TopViews\{00000000-0000-0000-0000-000000000000}" -Name SortByList -PropertyType String -Value "prop:System.ItemNameDisplay" -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Disabling grouping of files and folder in the Downloads folder"
			LogInfo "Disabling grouping of files and folder in the Downloads folder"
			Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes\{885a186e-a440-4ada-812b-db871b942259}" -Recurse -Force -ErrorAction Ignore | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Enable or disable coloring of encrypted or compressed NTFS files (green for encrypted, blue for compressed)

.PARAMETER Enable
Enable coloring of encrypted or compressed NTFS files (default value)

.PARAMETER Disable
Disable coloring of encrypted or compressed NTFS files

.EXAMPLE
EncCompFilesColor -Enable

.EXAMPLE
EncCompFilesColor -Disable

.NOTES
Current user
#>
function EncCompFilesColor
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
			Write-ConsoleStatus -Action "Enabling coloring of encrypted or compressed NTFS files"
			LogInfo "Enabling coloring of encrypted or compressed NTFS files"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowEncryptCompressedColor" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable coloring of encrypted or compressed NTFS files: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling coloring of encrypted or compressed NTFS files"
			LogInfo "Disabling coloring of encrypted or compressed NTFS files"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowEncryptCompressedColor" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowEncryptCompressedColor" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable coloring of encrypted or compressed NTFS files: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable displaying full path in Explorer window title

.PARAMETER Enable
Enable displaying full path in Explorer title

.PARAMETER Disable
Disable displaying full path in Explorer title (default value)

.EXAMPLE
ExplorerTitleFullPath -Enable

.EXAMPLE
ExplorerTitleFullPath -Disable

.NOTES
Current user
#>
function ExplorerTitleFullPath
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
			Write-ConsoleStatus -Action "Enabling the display of full paths in Explorer title"
			LogInfo "Enabling the display of full paths in Explorer title"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable full paths in Explorer title: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the display of full paths in Explorer title"
			LogInfo "Disabling the display of full paths in Explorer title"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable full paths in Explorer title: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File Explorer mode

	.PARAMETER Disable
	Disable File Explorer compact mode (default value)

	.PARAMETER Enable
	Enable File Explorer compact mode

	.EXAMPLE
	FileExplorerCompactMode -Disable

	.EXAMPLE
	FileExplorerCompactMode -Enable

	.NOTES
	Current user
#>
function FileExplorerCompactMode
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
			Write-ConsoleStatus -Action "Disabling File Explorer compact mode"
			LogInfo "Disabling File Explorer compact mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name UseCompactMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable File Explorer compact mode: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling File Explorer compact mode"
			LogInfo "Enabling File Explorer compact mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name UseCompactMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable File Explorer compact mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	File name extensions

	.PARAMETER Show
	Show file name extensions

	.PARAMETER Hide
	Hide file name extensions (default value)

	.EXAMPLE
	FileExtensions -Show

	.EXAMPLE
	FileExtensions -Hide

	.NOTES
	Current user
#>
function FileExtensions
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
			Write-ConsoleStatus -Action "Enabling file name extensions"
			LogInfo "Enabling file name extensions"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show file name extensions: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling file name extensions"
			LogInfo "Disabling file name extensions"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide file name extensions: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The file transfer dialog box mode

	.PARAMETER Detailed
	Show the file transfer dialog box in the detailed mode

	.PARAMETER Compact
	Show the file transfer dialog box in the compact mode (default value)

	.EXAMPLE
	FileTransferDialog -Detailed

	.EXAMPLE
	FileTransferDialog -Compact

	.NOTES
	Current user
#>
function FileTransferDialog
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Detailed"
		)]
		[switch]
		$Detailed,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Compact"
		)]
		[switch]
		$Compact
	)

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Detailed"
		{
			Write-ConsoleStatus -Action "Enabling detailed view for file transfer dialog boxes"
			LogInfo "Enabling detailed view for file transfer dialog boxes"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager -Name EnthusiastMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable detailed view for file transfer dialog boxes: $($_.Exception.Message)"
			}
		}
		"Compact"
		{
			Write-ConsoleStatus -Action "Enabling compact view for file transfer dialog boxes"
			LogInfo "Enabling compact view for file transfer dialog boxes"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager -Name EnthusiastMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable compact view for file transfer dialog boxes: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	First sign-in animation after the upgrade

	.PARAMETER Disable
	Disable first sign-in animation after the upgrade

	.PARAMETER Enable
	Enable first sign-in animation after the upgrade (default value)

	.EXAMPLE
	FirstLogonAnimation -Disable

	.EXAMPLE
	FirstLogonAnimation -Enable

	.NOTES
	Current user
#>
function FirstLogonAnimation
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableFirstLogonAnimation -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableFirstLogonAnimation -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the first sign-in animation after upgrade"
			LogInfo "Disabling the first sign-in animation after upgrade"
			try
			{
				New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name EnableFirstLogonAnimation -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the first sign-in animation after upgrade: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the first sign-in animation after upgrade"
			LogInfo "Enabling the first sign-in animation after upgrade"
			try
			{
				New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name EnableFirstLogonAnimation -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the first sign-in animation after upgrade: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Folder merge conflicts

	.PARAMETER Show
	Show folder merge conflicts

	.PARAMETER Hide
	Hide folder merge conflicts (default value)

	.EXAMPLE
	MergeConflicts -Show

	.EXAMPLE
	MergeConflicts -Hide

	.NOTES
	Current user
#>
function MergeConflicts
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
			Write-ConsoleStatus -Action "Enabling folder merge conflicts"
			LogInfo "Enabling folder merge conflicts"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideMergeConflicts -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show folder merge conflicts: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling folder merge conflicts"
			LogInfo "Disabling folder merge conflicts"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideMergeConflicts -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide folder merge conflicts: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable launching folder windows in a separate process

.PARAMETER Enable
Enable launching folder windows in a separate process

.PARAMETER Disable
Disable launching folder windows in a separate process (default value)

.EXAMPLE
FldrSeparateProcess -Enable

.EXAMPLE
FldrSeparateProcess -Disable

.NOTES
Current user
#>
function FldrSeparateProcess
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
			Write-ConsoleStatus -Action "Enabling launching folder windows in a separate process"
			LogInfo "Enabling launching folder windows in a separate process"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SeparateProcess" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable separate folder windows: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling launching folder windows in a separate process"
			LogInfo "Disabling launching folder windows in a separate process"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SeparateProcess" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable separate folder windows: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Hidden files, folders, and drives

	.PARAMETER Enable
	Show hidden files, folders, and drives

	.PARAMETER Disable
	Do not show hidden files, folders, and drives (default value)

	.EXAMPLE
	HiddenItems -Enable

	.EXAMPLE
	HiddenItems -Disable

	.NOTES
	Current user
#>
function HiddenItems
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
			Write-ConsoleStatus -Action "Enabling Hidden files, folders, and drives"
			LogInfo "Enabling Hidden files, folders, and drives"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Hidden -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show hidden files, folders, and drives: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Hidden files, folders, and drives"
			LogInfo "Disabling Hidden files, folders, and drives"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Hidden -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide hidden files, folders, and drives: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Item check boxes

	.PARAMETER Disable
	Do not use item check boxes

	.PARAMETER Enable
	Use check item check boxes (default value)

	.EXAMPLE
	CheckBoxes -Disable

	.EXAMPLE
	CheckBoxes -Enable

	.NOTES
	Current user
#>
function CheckBoxes
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
			Write-ConsoleStatus -Action "Enabling item check boxes"
			LogInfo "Enabling item check boxes"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name AutoCheckSelect -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable item check boxes: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling item check boxes"
			LogInfo "Disabling item check boxes"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name AutoCheckSelect -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable item check boxes: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable item selection checkboxes in Explorer

.PARAMETER Enable
Enable item selection checkboxes

.PARAMETER Disable
Disable item selection checkboxes (default value)

.EXAMPLE
SelectCheckboxes -Enable

.EXAMPLE
SelectCheckboxes -Disable

.NOTES
Current user
#>
function SelectCheckboxes
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
			Write-ConsoleStatus -Action "Enabling item selection checkboxes in Explorer"
			LogInfo "Enabling item selection checkboxes in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "AutoCheckSelect" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable item selection checkboxes in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling item selection checkboxes in Explorer"
			LogInfo "Enabling item selection checkboxes in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "AutoCheckSelect" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable item selection checkboxes in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The quality factor of the JPEG desktop wallpapers

	.PARAMETER Max
	Set the quality factor of the JPEG desktop wallpapers to maximum

	.PARAMETER Default
	Set the quality factor of the JPEG desktop wallpapers to default (default value)

	.EXAMPLE
	JPEGWallpapersQuality -Max

	.EXAMPLE
	JPEGWallpapersQuality -Default

	.NOTES
	Current user
#>
function JPEGWallpapersQuality
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Max"
		)]
		[switch]
		$Max,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Max"
		{
			Write-ConsoleStatus -Action "Enabling the maximum quality factor of the JPEG desktop wallpapers"
			LogInfo "Enabling the maximum quality factor of the JPEG desktop wallpapers"
			try
			{
				New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -PropertyType DWord -Value 100 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the maximum JPEG desktop wallpaper quality: $($_.Exception.Message)"
			}
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Disabling the maximum quality factor of the JPEG desktop wallpapers"
			LogInfo "Disabling the maximum quality factor of the JPEG desktop wallpapers"
			try
			{
				if (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore the default JPEG desktop wallpaper quality: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable showing all folders in Explorer navigation pane

.PARAMETER Enable
Enable showing all folders in navigation pane

.PARAMETER Disable
Disable showing all folders in navigation pane (default value)

.EXAMPLE
NavPaneAllFolders -Enable

.EXAMPLE
NavPaneAllFolders -Disable

.NOTES
Current user
#>
function NavPaneAllFolders
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
			Write-ConsoleStatus -Action "Enabling all folders in the Explorer navigation pane"
			LogInfo "Enabling all folders in the Explorer navigation pane"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable all folders in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling all folders in the Explorer navigation pane"
			LogInfo "Disabling all folders in the Explorer navigation pane"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NavPaneShowAllFolders" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable all folders in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable showing Libraries in Explorer navigation pane

.PARAMETER Enable
Enable showing Libraries in navigation pane

.PARAMETER Disable
Disable showing Libraries in navigation pane (default value)

.EXAMPLE
NavPaneLibraries -Enable

.EXAMPLE
NavPaneLibraries -Disable

.NOTES
Current user
#>
function NavPaneLibraries
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
			Write-ConsoleStatus -Action "Enabling Libraries in the Explorer navigation pane"
			LogInfo "Enabling Libraries in the Explorer navigation pane"
			try
			{
				If (!(Test-Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}")) {
					New-Item -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Name "System.IsPinnedToNameSpaceTree" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Libraries in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Libraries in the Explorer navigation pane"
			LogInfo "Disabling Libraries in the Explorer navigation pane"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Name "System.IsPinnedToNameSpaceTree" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{031E4825-7B94-4dc3-B131-E946B44C8DD5}" -Name "System.IsPinnedToNameSpaceTree" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Libraries in the Explorer navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Expand to current folder in navigation pane

	.PARAMETER Disable
	Do not expand to open folder on navigation pane (default value)

	.PARAMETER Enable
	Expand to open folder on navigation pane

	.EXAMPLE
	NavigationPaneExpand -Disable

	.EXAMPLE
	NavigationPaneExpand -Enable

	.NOTES
	Current user
#>
function NavigationPaneExpand
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
			Write-ConsoleStatus -Action "Disabling expand to open folder on navigation pane"
			LogInfo "Disabling expand to open folder on navigation pane"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable expanding to the current folder in the navigation pane: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling expand to open folder on navigation pane"
			LogInfo "Enabling expand to open folder on navigation pane"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable expanding to the current folder in the navigation pane: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Sync provider notification in File Explorer

	.PARAMETER Hide
	Do not show sync provider notification within File Explorer

	.PARAMETER Show
	Show sync provider notification within File Explorer (default value)

	.EXAMPLE
	OneDriveFileExplorerAd -Hide

	.EXAMPLE
	OneDriveFileExplorerAd -Show

	.NOTES
	Current user
#>
function OneDriveFileExplorerAd
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling sync provider notification within File Explorer"
			LogInfo "Disabling sync provider notification within File Explorer"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSyncProviderNotifications -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide sync provider notification within File Explorer: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling sync provider notification within File Explorer"
			LogInfo "Enabling sync provider notification within File Explorer"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSyncProviderNotifications -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show sync provider notification within File Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Configure how to open File Explorer

	.PARAMETER ThisPC
	Open File Explorer to "This PC"

	.PARAMETER QuickAccess
	Open File Explorer to Quick access (default value)

	.PARAMETER Downloads
	Open File Explorer to Downloads

	.EXAMPLE
	OpenFileExplorerTo -ThisPC

	.EXAMPLE
	OpenFileExplorerTo -QuickAccess

	.EXAMPLE
	OpenFileExplorerTo -Downloads

	.NOTES
	Current user
#>
function OpenFileExplorerTo
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "ThisPC"
		)]
		[switch]
		$ThisPC,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "QuickAccess"
		)]
		[switch]
		$QuickAccess,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Downloads"
		)]
		[switch]
		$Downloads
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"ThisPC"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'This PC'"
			LogInfo "Setting File Explorer to open to 'This PC'"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name LaunchTo -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'This PC': $($_.Exception.Message)"
			}
		}
		"QuickAccess"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'Quick Access'"
			LogInfo "Setting File Explorer to open to 'Quick Access'"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name LaunchTo -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'Quick Access': $($_.Exception.Message)"
			}
		}
		"Downloads"
		{
			Write-ConsoleStatus -Action "Setting File Explorer to open to 'Downloads'"
			LogInfo "Setting File Explorer to open to 'Downloads'"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name LaunchTo -PropertyType DWord -Value 3 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set File Explorer to open to 'Downloads': $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	A different input method for each app window

	.PARAMETER Enable
	Let me use a different input method for each app window

	.PARAMETER Disable
	Do not use a different input method for each app window (default value)

	.EXAMPLE
	AppsLanguageSwitch -Enable

	.EXAMPLE
	AppsLanguageSwitch -Disable

	.NOTES
	Current user
#>
function AppsLanguageSwitch
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
			Write-ConsoleStatus -Action "Enabling a different input method for each app window"
			LogInfo "Enabling a different input method for each app window"
			try
			{
				Set-WinLanguageBarOption -UseLegacySwitchMode -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable a different input method for each app window: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling a different input method for each app window"
			LogInfo "Disabling a different input method for each app window"
			try
			{
				Set-WinLanguageBarOption -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable a different input method for each app window: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Show or hide protected operating system files

	.PARAMETER Enable
	Show protected operating system files

	.PARAMETER Disable
	Do not show protected operating system files (default value)

	.EXAMPLE
	SuperHiddenFiles -Enable

	.EXAMPLE
	SuperHiddenFiles -Disable

	.NOTES
	Current user
#>
function SuperHiddenFiles
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
			Write-ConsoleStatus -Action "Enabling 'Show protected operating system files'"
			LogInfo "Enabling 'Show protected operating system files'"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show protected operating system files: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'Show protected operating system files'"
			LogInfo "Disabling 'Show protected operating system files'"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide protected operating system files: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Print screen button usage

	.PARAMETER Enable
	Use the Print screen button to open screen snipping

	.PARAMETER Disable
	Do not use the Print screen button to open screen snipping (default value)

	.EXAMPLE
	PrtScnSnippingTool -Enable

	.EXAMPLE
	PrtScnSnippingTool -Disable

	.NOTES
	Current user
#>
function PrtScnSnippingTool
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
			Write-ConsoleStatus -Action "Enabling the Print screen button to open screen snipping"
			LogInfo "Enabling the Print screen button to open screen snipping"
			try
			{
				New-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name PrintScreenKeyForSnippingEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Print Screen for screen snipping: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Print screen button to open screen snipping"
			LogInfo "Disabling the Print screen button to open screen snipping"
			try
			{
				New-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name PrintScreenKeyForSnippingEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Print Screen for screen snipping: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Frequently used folders in Quick access

	.PARAMETER Hide
	Hide frequently used folders in Quick access

	.PARAMETER Show
	Show frequently used folders in Quick access (default value)

	.EXAMPLE
	QuickAccessFrequentFolders -Hide

	.EXAMPLE
	QuickAccessFrequentFolders -Show

	.NOTES
	Current user
#>
function QuickAccessFrequentFolders
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling frequently used folders in Quick access"
			LogInfo "Disabling frequently used folders in Quick access"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShowFrequent -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide frequently used folders in Quick access: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling frequently used folders in Quick access"
			LogInfo "Enabling frequently used folders in Quick access"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShowFrequent -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show frequently used folders in Quick access: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recently used files in Quick access

	.PARAMETER Hide
	Hide recently used files in Quick access

	.PARAMETER Show
	Show recently used files in Quick access (default value)

	.EXAMPLE
	QuickAccessRecentFiles -Hide

	.EXAMPLE
	QuickAccessRecentFiles -Show

	.NOTES
	Current user
#>
function QuickAccessRecentFiles
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoRecentDocsHistory -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoRecentDocsHistory -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name NoRecentDocsHistory -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling recently used files in Quick access"
			LogInfo "Disabling recently used files in Quick access"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShowRecent -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide recently used files in Quick access: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling recently used files in Quick access"
			LogInfo "Enabling recently used files in Quick access"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShowRecent -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show recently used files in Quick access: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable recently and frequently used item shortcuts in Explorer

.DESCRIPTION
Note: This is only a UI tweak to hide the shortcuts. In order to stop creating most recently used (MRU) items lists everywhere, use privacy tweak 'DisableRecentFiles' instead.

.PARAMETER Enable
Enable hiding recently and frequently used item shortcuts

.PARAMETER Disable
Disable hiding recently and frequently used item shortcuts (default value)

.EXAMPLE
RecentShortcuts -Enable

.EXAMPLE
RecentShortcuts -Disable

.NOTES
Current user
#>
function RecentShortcuts
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
			Write-ConsoleStatus -Action "Enabling recently and frequently used item shortcuts in Explorer"
			LogInfo "Enabling recently and frequently used item shortcuts in Explorer"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -ErrorAction Stop | Out-Null
				}
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable recent and frequent item shortcuts in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling recently and frequently used item shortcuts in Explorer"
			LogInfo "Disabling recently and frequently used item shortcuts in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable recent and frequent item shortcuts in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The recycle bin files delete confirmation dialog

	.PARAMETER Enable
	Display the recycle bin files delete confirmation dialog

	.PARAMETER Disable
	Do not display the recycle bin files delete confirmation dialog (default value)

	.EXAMPLE
	RecycleBinDeleteConfirmation -Enable

	.EXAMPLE
	RecycleBinDeleteConfirmation -Disable

	.NOTES
	Current user
#>
function RecycleBinDeleteConfirmation
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name ConfirmFileDelete -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name ConfirmFileDelete -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name ConfirmFileDelete -Type CLEAR | Out-Null

	$ShellState = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShellState

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the recycle bin files delete confirmation dialog"
			LogInfo "Enabling the recycle bin files delete confirmation dialog"
			try
			{
				$ShellState[4] = 51
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShellState -PropertyType Binary -Value $ShellState -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the recycle bin delete confirmation dialog: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the recycle bin files delete confirmation dialog"
			LogInfo "Disabling the recycle bin files delete confirmation dialog"
			try
			{
				$ShellState[4] = 55
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name ShellState -PropertyType Binary -Value $ShellState -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the recycle bin delete confirmation dialog: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable restoring previous folder windows at logon

.PARAMETER Enable
Enable restoring previous folder windows at logon

.PARAMETER Disable
Disable restoring previous folder windows at logon (default value)

.EXAMPLE
RestoreFldrWindows -Enable

.EXAMPLE
RestoreFldrWindows -Disable

.NOTES
Current user
#>
function RestoreFldrWindows
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
			Write-ConsoleStatus -Action "Enabling restoring previous folder windows at logon"
			LogInfo "Enabling restoring previous folder windows at logon"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PersistBrowsers" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable restoring previous folder windows at logon: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling restoring previous folder windows at logon"
			LogInfo "Disabling restoring previous folder windows at logon"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PersistBrowsers" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PersistBrowsers" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable restoring previous folder windows at logon: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Share context menu item

    .PARAMETER Enable
    Enable the Share context menu item (default value)

    .PARAMETER Disable
    Disable the Share context menu item

    .EXAMPLE
    ShareMenu -Enable

    .EXAMPLE
    ShareMenu -Disable

    .NOTES
    Current user
#>
function ShareMenu
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
			If (!(Test-Path "HKCR:")) {
				New-PSDrive -Name "HKCR" -PSProvider "Registry" -Root "HKEY_CLASSES_ROOT" | Out-Null
			}
			Write-ConsoleStatus -Action "Enabling the Share context menu item"
			LogInfo "Enabling the Share context menu item"
			try
			{
				New-Item -Path "HKCR:\*\shellex\ContextMenuHandlers\ModernSharing" -ErrorAction SilentlyContinue | Out-Null
				Set-ItemProperty -LiteralPath "HKCR:\*\shellex\ContextMenuHandlers\ModernSharing" -Name "(Default)" -Type String -Value "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Share context menu item: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			If (!(Test-Path "HKCR:")) {
				New-PSDrive -Name "HKCR" -PSProvider "Registry" -Root "HKEY_CLASSES_ROOT" | Out-Null
			}
			Write-ConsoleStatus -Action "Disabling the Share context menu item"
			LogInfo "Disabling the Share context menu item"
			try
			{
				if (Test-Path "HKCR:\*\shellex\ContextMenuHandlers\ModernSharing")
				{
					Remove-Item -LiteralPath "HKCR:\*\shellex\ContextMenuHandlers\ModernSharing" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Share context menu item: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Sharing Wizard in Explorer

.PARAMETER Enable
Enable Sharing Wizard

.PARAMETER Disable
Disable Sharing Wizard (default value)

.EXAMPLE
SharingWizard -Enable

.EXAMPLE
SharingWizard -Disable

.NOTES
Current user
#>
function SharingWizard
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
			Write-ConsoleStatus -Action "Enabling the Sharing Wizard in Explorer"
			LogInfo "Enabling the Sharing Wizard in Explorer"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Sharing Wizard in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the Sharing Wizard in Explorer"
			LogInfo "Disabling the Sharing Wizard in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Sharing Wizard in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Controls the display of shortcut arrow overlay on icons

	.PARAMETER Enable
	Show shortcut arrow overlay on icons (default value)

	.PARAMETER Disable
	Remove shortcut arrow overlay on icons

	.EXAMPLE
	ShortcutArrow -Enable

	.EXAMPLE
	ShortcutArrow -Disable

	.NOTES
	Current user
#>
function ShortcutArrow
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
			Write-ConsoleStatus -Action "Enabling the display of shortcut arrow overlay on icons"
			LogInfo "Enabling the display of shortcut arrow overlay on icons"
			try
			{
				if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons")
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" -Name "29" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the shortcut arrow overlay on icons: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the display of shortcut arrow overlay on icons"
			LogInfo "Disabling the display of shortcut arrow overlay on icons"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" -Name "29" -Type String -Value "%SystemRoot%\System32\imageres.dll,-1015" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the shortcut arrow overlay on icons: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The "- Shortcut" suffix adding to the name of the created shortcuts

	.PARAMETER Disable
	Do not add the "- Shortcut" suffix to the file name of created shortcuts

	.PARAMETER Enable
	Add the "- Shortcut" suffix to the file name of created shortcuts (default value)

	.EXAMPLE
	ShortcutsSuffix -Disable

	.EXAMPLE
	ShortcutsSuffix -Enable

	.NOTES
	Current user
#>
function ShortcutsSuffix
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

	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name link -Force -ErrorAction Ignore | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the '- Shortcut' suffix adding to the name of the created shortcuts"
			LogInfo "Disabling the '- Shortcut' suffix adding to the name of the created shortcuts"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates))
				{
					New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates -Name ShortcutNameTemplate -PropertyType String -Value "%s.lnk" -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the shortcut name suffix: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling the '- Shortcut' suffix adding to the name of the created shortcuts"
			LogInfo "Enabling the '- Shortcut' suffix adding to the name of the created shortcuts"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates -Name ShortcutNameTemplate -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates -Name ShortcutNameTemplate -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the shortcut name suffix: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows snapping

	.PARAMETER Disable
	When I snap a window, do not show what I can snap next to it

	.PARAMETER Enable
	When I snap a window, show what I can snap next to it (default value)

	.EXAMPLE
	SnapAssist -Disable

	.EXAMPLE
	SnapAssist -Enable

	.NOTES
	Current user
#>
function SnapAssist
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

	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WindowArrangementActive -PropertyType String -Value 1 -Force | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'show what I can snap next' When snapping windows"
			LogInfo "Disabling 'show what I can snap next' When snapping windows"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name SnapAssist -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 'show what I can snap next' when snapping windows: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'show what I can snap next' When snapping windows"
			LogInfo "Enabling 'show what I can snap next' When snapping windows"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name SnapAssist -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 'show what I can snap next' when snapping windows: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable sync provider notifications in Explorer

.PARAMETER Enable
Enable sync provider notifications

.PARAMETER Disable
Disable sync provider notifications (default value)

.EXAMPLE
SyncNotifications -Enable

.EXAMPLE
SyncNotifications -Disable

.NOTES
Current user
#>
function SyncNotifications
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
			Write-ConsoleStatus -Action "Enabling sync provider notifications in Explorer"
			LogInfo "Enabling sync provider notifications in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sync provider notifications in Explorer: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sync provider notifications in Explorer"
			LogInfo "Disabling sync provider notifications in Explorer"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sync provider notifications in Explorer: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The "This PC" icon on Desktop

	.PARAMETER Show
	Show the "This PC" icon on Desktop

	.PARAMETER Hide
	Hide the "This PC" icon on Desktop (default value)

	.EXAMPLE
	ThisPC -Show

	.EXAMPLE
	ThisPC -Hide

	.NOTES
	Current user
#>
function ThisPC
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
			Write-ConsoleStatus -Action "Enabling 'This PC' icon on Desktop"
			LogInfo "Enabling 'This PC' icon on Desktop"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel))
				{
					New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the 'This PC' icon on Desktop: $($_.Exception.Message)"
			}
		}
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling 'This PC' icon on Desktop"
			LogInfo "Disabling 'This PC' icon on Desktop"
			try
			{
				if ((Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the 'This PC' icon on Desktop: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Creation of thumbnail cache files

    .PARAMETER Enable
    Enable creation of thumbnail cache files

    .PARAMETER Disable
    Disable creation of thumbnail cache files (default value)

    .EXAMPLE
    ThumbnailCache -Enable

    .EXAMPLE
    ThumbnailCache -Disable

    .NOTES
    Current user
#>
function ThumbnailCache
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
			Write-ConsoleStatus -Action "Enabling the creation of thumbnail cache files"
			LogInfo "Enabling the creation of thumbnail cache files"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbnailCache" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbnailCache" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable thumbnail cache creation: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the creation of thumbnail cache files"
			LogInfo "Disabling the creation of thumbnail cache files"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbnailCache" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable thumbnail cache creation: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Show thumbnails instead of file extension icons

    .PARAMETER Enable
    Show thumbnails for files

    .PARAMETER Disable
    Show only file extension icons (default value)

    .EXAMPLE
    Thumbnails -Enable

    .EXAMPLE
    Thumbnails -Disable

    .NOTES
    Current user
#>
function Thumbnails
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
			Write-ConsoleStatus -Action "Enabling 'Show thumbnails instead of icons' for file extensions"
			LogInfo "Enabling 'Show thumbnails instead of icons' for file extensions"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "IconsOnly" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable thumbnails for file extensions: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling thumbnails, showing icons for file extensions instead"
			LogInfo "Disabling thumbnails, showing icons for file extensions instead"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "IconsOnly" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable thumbnails for file extensions: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Creation of Thumbs.db thumbnail cache files on network folders

    .PARAMETER Enable
    Enable creation of Thumbs.db cache on network folders

    .PARAMETER Disable
    Disable creation of Thumbs.db cache on network folders (default value)

    .EXAMPLE
    ThumbsDBOnNetwork -Enable

    .EXAMPLE
    ThumbsDBOnNetwork -Disable

    .NOTES
    Current user
#>
function ThumbsDBOnNetwork
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
			Write-ConsoleStatus -Action "Enabling the creation of 'Thumbs.db' cache on network folders"
			LogInfo "Enabling the creation of 'Thumbs.db' cache on network folders"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbsDBOnNetworkFolders" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbsDBOnNetworkFolders" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Thumbs.db cache on network folders: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the creation of 'Thumbs.db' cache on network folders"
			LogInfo "Disabling the creation of 'Thumbs.db' cache on network folders"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbsDBOnNetworkFolders" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Thumbs.db cache on network folders: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The default Windows mode

	.PARAMETER Dark
	Set the default Windows mode to dark

	.PARAMETER Light
	Set the default Windows mode to light (default value)

	.EXAMPLE
	WindowsColorScheme -Dark

	.EXAMPLE
	WindowsColorScheme -Light

	.NOTES
	Current user
#>
function WindowsColorMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Dark"
		)]
		[switch]
		$Dark,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Light"
		)]
		[switch]
		$Light
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Dark"
		{
			Write-ConsoleStatus -Action "Setting Windows to use Dark Mode"
			LogInfo "Setting Windows to use Dark Mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Windows color mode to Dark: $($_.Exception.Message)"
			}
		}
		"Light"
		{
			Write-ConsoleStatus -Action "Setting Windows to use Light Mode"
			LogInfo "Setting Windows to use Light Mode"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Windows color mode to Light: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Meet Now icon in the notification area

	.PARAMETER Hide
	Hide the Meet Now icon in the notification area

	.PARAMETER Show
	Show the Meet Now icon in the notification area (default value)

	.EXAMPLE
	MeetNow -Hide

	.EXAMPLE
	MeetNow -Show

	.NOTES
	Current user only
#>
function MeetNow
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name HideSCAMeetNow -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Meet Now icon in the notification area"
			LogInfo "Disabling the Meet Now icon in the notification area"
			try
			{
				$Script:MeetNow = $false
				$Settings = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -ErrorAction Stop
				$Settings[9] = 128
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -PropertyType Binary -Value $Settings -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Meet Now icon in the notification area: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Meet Now icon in the notification area"
			LogInfo "Enabling the Meet Now icon in the notification area"
			try
			{
				$Script:MeetNow = $true
				$Settings = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -ErrorAction Stop
				$Settings[9] = 0
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -PropertyType Binary -Value $Settings -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Meet Now icon in the notification area: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	News and Interests

	.PARAMETER Disable
	Disable "News and Interests" on the taskbar

	.PARAMETER Enable
	Enable "News and Interests" on the taskbar (default value)

	.EXAMPLE
	NewsInterests -Disable

	.EXAMPLE
	NewsInterests -Enable

	.NOTES
	https://forums.mydigitallife.net/threads/taskbarda-widgets-registry-change-is-now-blocked.88547/#post-1848877

	.NOTES
	Current user
#>
function NewsInterests
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable,

		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable
	)

	# Remove old policies silently
	$null = Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name EnableFeeds -Force -ErrorAction SilentlyContinue
	$null = Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Name value -Force -ErrorAction SilentlyContinue

	# Skip if Edge is not installed
	if (-not (Get-Package -Name "Microsoft Edge" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue))
	{
		LogInfo ($Localization.Skipped -f $MyInvocation.Line.Trim())
		return
	}

	# Get MachineId
	$MachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
	if (-not $MachineId)
	{
		LogInfo ($Localization.Skipped -f $MyInvocation.Line.Trim())
		return
	}

	# Add C# HashData type if missing
	if (-not ("WinAPI.Signature" -as [type]))
	{
		$Signature = @{
			Namespace          = "WinAPI"
			Name               = "Signature"
			Language           = "CSharp"
			CompilerParameters = $CompilerParameters
			MemberDefinition   = @"
[DllImport("Shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = false)]
public static extern int HashData(byte[] pbData, int cbData, byte[] piet, int outputLen);
"@
		}
		Add-Type @Signature | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'News and Interests' on the taskbar"
			LogInfo "Disabling 'News and Interests' on the taskbar"

			try
			{
				$null = {
					$Combined = $MachineId + '_' + 2
					$CharArray = $Combined.ToCharArray()
					[array]::Reverse($CharArray)
					$Reverse = -join $CharArray
					$bytesIn = [System.Text.Encoding]::Unicode.GetBytes($Reverse)
					$bytesOut = [byte[]]::new(4)
					[WinAPI.Signature]::HashData($bytesIn, 0x53, $bytesOut, $bytesOut.Count)
					$DWordData = [System.BitConverter]::ToUInt32($bytesOut,0)

					if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"))
					{
						New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force -ErrorAction Stop | Out-Null
					}

					New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" `
								 -Name "ShellFeedsTaskbarViewMode" -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
					New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" `
								 -Name "EnShellFeedsTaskbarViewMode" -PropertyType DWord -Value $DWordData -Force -ErrorAction Stop | Out-Null
				}.Invoke()

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Unable to fully update 'News and Interests' taskbar settings: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}

		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'News and Interests' on the taskbar"
			LogInfo "Enabling 'News and Interests' on the taskbar"

			try
			{
				$null = {
					$Combined = $MachineId + '_' + 0
					$CharArray = $Combined.ToCharArray()
					[array]::Reverse($CharArray)
					$Reverse = -join $CharArray
					$bytesIn = [System.Text.Encoding]::Unicode.GetBytes($Reverse)
					$bytesOut = [byte[]]::new(4)
					[WinAPI.Signature]::HashData($bytesIn, 0x53, $bytesOut, $bytesOut.Count)
					$DWordData = [System.BitConverter]::ToUInt32($bytesOut,0)

					if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"))
					{
						New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force -ErrorAction Stop | Out-Null
					}

					New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" `
								 -Name "ShellFeedsTaskbarViewMode" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
					New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" `
								 -Name "EnShellFeedsTaskbarViewMode" -PropertyType DWord -Value $DWordData -Force -ErrorAction Stop | Out-Null
				}.Invoke()

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Unable to fully update 'News and Interests' taskbar settings: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
	}
}

<#
	.SYNOPSIS
	Taskbar alignment

	.PARAMETER Left
	Set the taskbar alignment to the left

	.PARAMETER Center
	Set the taskbar alignment to the center (default value)

	.EXAMPLE
	TaskbarAlignment -Center

	.EXAMPLE
	TaskbarAlignment -Left

	.NOTES
	Current user
#>
function TaskbarAlignment
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Left"
		)]
		[switch]
		$Left,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Center"
		)]
		[switch]
		$Center
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Center"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Center"
			LogInfo "Setting the taskbar alignment to the Center"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarAl -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the center: $($_.Exception.Message)"
			}
		}
		"Left"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Left"
			LogInfo "Setting the taskbar alignment to the Left"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarAl -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the left: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The widgets icon on the taskbar

	.PARAMETER Hide
	Hide the widgets icon on the taskbar

	.PARAMETER Show
	Show the widgets icon on the taskbar (default value)

	.EXAMPLE
	TaskbarWidgets -Hide

	.EXAMPLE
	TaskbarWidgets -Show

	.NOTES
	Current user
#>
function TaskbarWidgets
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	if (-not (Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -WarningAction SilentlyContinue))
	{
		LogInfo ($Localization.Skipped -f $MyInvocation.Line.Trim())
		#LogWarning ($Localization.Skipped -f $MyInvocation.Line.Trim())
	}

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests -Name value -Force -ErrorAction Ignore | Out-Null
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Type CLEAR | Out-Null

	# We cannot set a value to TaskbarDa, having called any of APIs, except of copying powershell.exe (or any other tricks) with a different name, due to a UCPD driver tracks all executables to block the access to the registry
	Copy-Item -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Force | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the widgets icon on the taskbar"
			LogInfo "Disabling the widgets icon on the taskbar"
			& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Command {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 0 -Force} | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the widgets icon on the taskbar"
			LogInfo "Enabling the widgets icon on the taskbar"
			& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Command {New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarDa -PropertyType DWord -Value 1 -Force} | Out-Null
			Write-ConsoleStatus -Status success
		}
	}

	Remove-Item -Path "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_temp.exe" -Force | Out-Null
}

<#
	.SYNOPSIS
	Search on the taskbar

	.PARAMETER Hide
	Hide the search on the taskbar

	.PARAMETER SearchIcon
	Show the search icon on the taskbar

	.PARAMETER SearchBox
	Show the search box on the taskbar (default value)

	.EXAMPLE
	TaskbarSearch -Hide

	.EXAMPLE
	TaskbarSearch -SearchIcon

	.EXAMPLE
	TaskbarSearch -SearchIconLabel

	.EXAMPLE
	TaskbarSearch -SearchBox

	.NOTES
	Current user
#>
function TaskbarSearch
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchIcon"
		)]
		[switch]
		$SearchIcon,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchIconLabel"
		)]
		[switch]
		$SearchIconLabel,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchBox"
		)]
		[switch]
		$SearchBox
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Search\DisableSearch -Name value -PropertyType DWord -Value 0 -Force -ErrorAction Ignore | Out-Null
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch, SearchOnTaskbarMode -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name SearchOnTaskbarMode -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the search on the taskbar"
			LogInfo "Disabling the search on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide search on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIcon"
		{
			Write-ConsoleStatus -Action "Enabling the search icon on the taskbar"
			LogInfo "Enabling the search icon on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIconLabel"
		{
			Write-ConsoleStatus -Action "Enabling the search icon label on the taskbar"
			LogInfo "Enabling the search icon label on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 3 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon label on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchBox"
		{
			Write-ConsoleStatus -Action "Enabling the search box on the taskbar"
			LogInfo "Enabling the search box on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search box on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Search highlights

	.PARAMETER Hide
	Hide search highlights

	.PARAMETER Show
	Show search highlights (default value)

	.EXAMPLE
	SearchHighlights -Hide

	.EXAMPLE
	SearchHighlights -Show

	.NOTES
	Current user
#>
function SearchHighlights
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling search highlights"
			LogInfo "Disabling search highlights"
			# Checking whether "Ask Copilot" and "Find results in Web" were disabled. They also disable Search Highlights automatically
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			$BingSearchEnabled = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", $null))
			$DisableSearchBoxSuggestions = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer", "DisableSearchBoxSuggestions", $null))
			if (($BingSearchEnabled -eq 1) -or ($DisableSearchBoxSuggestions -eq 1))
			{
				LogInfo ($Localization.Skipped -f $MyInvocation.Line.Trim())
			}
			else
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings -Name IsDynamicSearchBoxEnabled -PropertyType DWord -Value 0 -Force | Out-Null

			}
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling search highlights"
			LogInfo "Enabling search highlights"
			# Enable "Ask Copilot" and "Find results in Web" icons in Windows Search in order to enable Search Highlights
			Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name BingSearchEnabled -Force -ErrorAction Ignore | Out-Null
			Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -Force -ErrorAction Ignore | Out-Null
			New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings -Name IsDynamicSearchBoxEnabled -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Task view button on the taskbar

	.PARAMETER Hide
	Hide the Task view button on the taskbar

	.PARAMETER Show
	Show the Task View button on the taskbar (default value)

	.EXAMPLE
	TaskViewButton -Hide

	.EXAMPLE
	TaskViewButton -Show

	.NOTES
	Current user
#>
function TaskViewButton
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Task view button on the taskbar"
			LogInfo "Disabling the Task view button on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Task view button on the taskbar"
			LogInfo "Enabling the Task view button on the taskbar"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Combine taskbar buttons and hide labels

	.PARAMETER Always
	Combine taskbar buttons and always hide labels (default value)

	.PARAMETER Full
	Combine taskbar buttons and hide labels when taskbar is full

	.PARAMETER Never
	Combine taskbar buttons and never hide labels

	.EXAMPLE
	TaskbarCombine -Always

	.EXAMPLE
	TaskbarCombine -Full

	.EXAMPLE
	TaskbarCombine -Never

	.NOTES
	Current user
#>
function TaskbarCombine
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Always"
		)]
		[switch]
		$Always,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Full"
		)]
		[switch]
		$Full,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Never"
		)]
		[switch]
		$Never
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Always"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and always hide labels"
			LogInfo "Combine taskbar buttons and always hide labels"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to always combine taskbar buttons and hide labels: $($_.Exception.Message)"
			}
		}
		"Full"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and hide labels when taskbar is full"
			LogInfo "Combine taskbar buttons and hide labels when taskbar is full"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to combine taskbar buttons when the taskbar is full: $($_.Exception.Message)"
			}
		}
		"Never"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and never hide labels"
			LogInfo "Combine taskbar buttons and never hide labels"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to never combine taskbar buttons and labels: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Unpin shortcuts from the taskbar

	.PARAMETER Edge
	Unpin Microsoft Edge shortcut from the taskbar

	.PARAMETER Store
	Unpin Microsoft Store from the taskbar

	.PARAMETER Outlook
	Unpin Outlook shortcut from the taskbar

	.PARAMETER Mail
	Unpin Mail shortcut from the taskbar

	.PARAMETER Copilot
	Unpin Copilot shortcut from the taskbar

	.PARAMETER Microsoft365
	Unpin Microsoft 365 shortcut from the taskbar

	.EXAMPLE
	UnpinTaskbarShortcuts -Shortcuts Edge, Store, Outlook, Mail, Copilot, Microsoft365

	.NOTES
	Current user
#>
function UnpinTaskbarShortcuts
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet("Edge", "Store", "Outlook", "Mail", "Copilot", "Microsoft365")]
		[string[]]
		$Shortcuts
	)

	$TaskbarPinnedPath = Join-Path $env:AppData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
	$IsARM64 = ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") -or
		($env:PROCESSOR_ARCHITEW6432 -eq "ARM64") -or
		([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64)
	$IsWindows10 = [System.Environment]::OSVersion.Version.Build -lt 22000
	# ARM64 and Windows 10 already needed the STA-runspace path (original condition).
	# AMD64 Windows 11 also needs it — direct COM shell verb calls silently do nothing on Win11 x64.
	$NeedsDeferredUnpin = $IsARM64 -or $IsWindows10 -or (-not $IsWindows10 -and -not $IsARM64)

	function Get-TaskbarPinnedItems
	{
		if (-not (Test-Path -Path $TaskbarPinnedPath))
		{
			return @()
		}

		$TaskbarShell = (New-Object -ComObject Shell.Application).NameSpace($TaskbarPinnedPath)
		if ($null -eq $TaskbarShell)
		{
			return @()
		}

		return @($TaskbarShell.Items())
	}

	function Get-TaskbarPinnedMatches
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$Patterns
		)

		$NormalizedPatterns = @($Patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		if ($NormalizedPatterns.Count -eq 0)
		{
			return @()
		}

		return @(Get-TaskbarPinnedItems | Where-Object {
			$ItemName = $_.Name
			foreach ($Pattern in $NormalizedPatterns)
			{
				if ($ItemName -match $Pattern)
				{
					return $true
				}
			}

			return $false
		})
	}

	function Invoke-TaskbarUnpin
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		$verbCandidates = @($LocalizedString, 'Unpin from taskbar', 'Von Taskleiste losen', 'Desanclar de la barra de tareas') |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
			Select-Object -Unique

		$unpinVerb = $ShellItem.Verbs() | Where-Object {
			$verbName = (($_.Name -replace '&', '').Trim())
			($verbCandidates -contains $verbName) -or
			($verbName -like '*Unpin*') -or
			($verbName -like '*taskbar*')
		} | Select-Object -First 1

		if ($unpinVerb)
		{
			try
			{
				$unpinVerb.DoIt()
				return $true
			}
			catch [System.UnauthorizedAccessException]
			{
				LogWarning "Taskbar unpin verb was denied for '$($ShellItem.Name)'."
				return $false
			}
			catch
			{
				LogWarning "Taskbar unpin verb failed for '$($ShellItem.Name)': $($_.Exception.Message)"
				return $false
			}
		}

		return $false
	}

	function Remove-TaskbarPinnedLink
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		try
		{
			if ([string]::IsNullOrWhiteSpace($ShellItem.Path) -or -not (Test-Path -LiteralPath $ShellItem.Path))
			{
				return $false
			}

			Remove-Item -LiteralPath $ShellItem.Path -Force -ErrorAction Stop
			LogInfo "Removed taskbar pinned shortcut file '$($ShellItem.Name)' as fallback."
			return $true
		}
		catch
		{
			LogWarning "Taskbar shortcut fallback removal failed for '$($ShellItem.Name)': $($_.Exception.Message)"
			return $false
		}
	}

	function Invoke-TaskbarUnpinWithFallback
	{
		param
		(
			[Parameter(Mandatory = $true)]
			$ShellItem
		)

		if (Invoke-TaskbarUnpin -ShellItem $ShellItem)
		{
			return $true
		}

		return (Remove-TaskbarPinnedLink -ShellItem $ShellItem)
	}

	function Remove-TaskbarPinnedLinksByPattern
	{
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$Patterns
		)

		if (-not (Test-Path -Path $TaskbarPinnedPath))
		{
			return $false
		}

		$RemovedAny = $false
		$LinkFiles = Get-ChildItem -Path $TaskbarPinnedPath -Filter "*.lnk" -ErrorAction SilentlyContinue
		foreach ($LinkFile in $LinkFiles)
		{
			$MatchesPattern = $false
			foreach ($Pattern in $Patterns)
			{
				if ($LinkFile.Name -like $Pattern)
				{
					$MatchesPattern = $true
					break
				}
			}

			if (-not $MatchesPattern)
			{
				continue
			}

			try
			{
				Remove-Item -LiteralPath $LinkFile.FullName -Force -ErrorAction Stop
				LogInfo "Removed taskbar pinned shortcut file '$($LinkFile.Name)' by filename fallback."
				$RemovedAny = $true
			}
			catch
			{
				LogWarning "Filename fallback removal failed for '$($LinkFile.Name)': $($_.Exception.Message)"
			}
		}

		return $RemovedAny
	}

	function Invoke-ARM64ShellUnpin
	{
		<#
			.SYNOPSIS
			ARM64 fallback: Unpin apps using COM shell verb in an in-process STA runspace with timeout.
			On ARM64, direct COM calls can hang so we run them on a background thread.
		#>
		param
		(
			[Parameter(Mandatory = $true)]
			[string[]]$AppNames,

			[int]$TimeoutSeconds = 15
		)

		$Runspace = [runspacefactory]::CreateRunspace()
		$Runspace.ApartmentState = "STA"
		$Runspace.Open()

		$PS = [powershell]::Create()
		$PS.Runspace = $Runspace

		$null = $PS.AddScript({
			param ($Names, $PinnedPath)
			$Shell = New-Object -ComObject Shell.Application
			$AppsFolder = $Shell.NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
			$Pinned = $Shell.NameSpace($PinnedPath)

			$VerbCandidates = @('Unpin from taskbar', 'Von Taskleiste losen', 'Desanclar de la barra de tareas',
				'Detacher de la barre des taches', 'Rimuovi dalla barra delle applicazioni')

			$Items = @()
			if ($Pinned) { $Items += @($Pinned.Items()) }
			if ($AppsFolder) { $Items += @($AppsFolder.Items()) }

			foreach ($Name in $Names)
			{
				$MatchingItems = @($Items | Where-Object { $_.Name -match $Name })
				foreach ($Item in $MatchingItems)
				{
					$UnpinVerb = $Item.Verbs() | Where-Object {
						$VerbName = (($_.Name -replace '&', '').Trim())
						($VerbCandidates -contains $VerbName) -or ($VerbName -match 'Unpin.*taskbar') -or ($VerbName -match 'taskbar.*unpin')
					} | Select-Object -First 1

					if ($UnpinVerb)
					{
						try { $UnpinVerb.DoIt() } catch {}
					}
				}
			}
		}).AddArgument($AppNames).AddArgument($TaskbarPinnedPath)

		$AsyncResult = $PS.BeginInvoke()

		if (-not $AsyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)))
		{
			LogWarning "ARM64 shell unpin timed out after $TimeoutSeconds seconds."
		}
		else
		{
			try { $PS.EndInvoke($AsyncResult) } catch {}
		}

		$PS.Dispose()
		$Runspace.Dispose()
	}

	# Extract the localized "Unpin from taskbar" string from shell32.dll
	$LocalizedString = [WinAPI.GetStrings]::GetString(5387)
	$AppsFolder = (New-Object -ComObject Shell.Application).NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")

	Write-ConsoleStatus -Action "Unpin taskbar apps"
	LogInfo "Unpin taskbar apps"
	$UnpinFailures = 0
	$UnpinMisses = 0

	# Always initialize the list; populated on ARM64 and Windows 10
	$DeferredUnpinNames = [System.Collections.Generic.List[string]]::new()

	foreach ($Shortcut in $Shortcuts)
	{
		switch ($Shortcut)
		{
			Mail
			{
				$MailPatterns = @('^Mail$', 'Mail and Calendar', 'Outlook \(new\)', 'Outlook for Windows')
				$MailFallbackPatterns = @('Mail*.lnk', '*Outlook*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					$DeferredUnpinNames.Add('^Mail$')
					$DeferredUnpinNames.Add('Mail and Calendar')
					$DeferredUnpinNames.Add('Outlook \(new\)')
					$DeferredUnpinNames.Add('Outlook for Windows')
				}
				else
				{
					$MailItems = @(
						Get-TaskbarPinnedMatches -Patterns $MailPatterns
						$AppsFolder.Items() | Where-Object {
							$_.Name -match 'Mail' -or
							$_.Name -match 'Outlook \(new\)' -or
							$_.Name -match 'Outlook for Windows'
						}
					) | Select-Object -Unique

					if ($MailItems)
					{
						$MailItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Mail' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $MailFallbackPatterns
					}
				}
			}
			Edge
			{
				$EdgeFallbackPatterns = @('Microsoft Edge*.lnk', 'Edge*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Edge')
				}
				else
				{
					$EdgeItems = @(Get-TaskbarPinnedMatches -Patterns @('Microsoft Edge', '^Edge$'))
					if ($EdgeItems)
					{
						$EdgeItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Edge' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $EdgeFallbackPatterns
					}
				}
			}
			Store
			{
				$StoreFallbackPatterns = @('Microsoft Store*.lnk', '*Store*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					$DeferredUnpinNames.Add('Microsoft Store')
				}
				else
				{
					$StoreItems = @(
						Get-TaskbarPinnedMatches -Patterns @('Microsoft Store', '^Store$')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -eq "Microsoft Store" -or
							$_.Name -eq "Store"
						}
					) | Select-Object -Unique
					if ($StoreItems)
					{
						$StoreItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Store' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $StoreFallbackPatterns
					}
				}
			}
			Outlook
			{
				$OutlookPatterns = @('Outlook', 'Mail and Calendar')
				$OutlookFallbackPatterns = @('*Outlook*.lnk', 'Mail*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					$DeferredUnpinNames.Add('Outlook')
					$DeferredUnpinNames.Add('Mail and Calendar')
				}
				else
				{
					$OutlookItems = @(
						Get-TaskbarPinnedMatches -Patterns $OutlookPatterns
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Outlook' -or
							$_.Name -eq 'Mail and Calendar'
						}
					) | Select-Object -Unique
					if ($OutlookItems)
					{
						$OutlookItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Outlook' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $OutlookFallbackPatterns
					}
				}
			}
			Copilot
			{
				# Disable the dedicated Copilot taskbar button
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -PropertyType DWord -Value 0 -Force | Out-Null

				# Disable Copilot companion in taskbar search
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarCompanion" -PropertyType DWord -Value 0 -Force | Out-Null

				$CopilotPinPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins"

				if (-not (Test-Path -Path $CopilotPinPath))
				{
					New-Item -Path $CopilotPinPath -Force | Out-Null
				}

				New-ItemProperty -Path $CopilotPinPath -Name "CopilotPWAPin" -PropertyType DWord -Value 0 -Force | Out-Null
				New-ItemProperty -Path $CopilotPinPath -Name "RecallPin" -PropertyType DWord -Value 0 -Force | Out-Null

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns @('*Copilot*.lnk', '*Recall*.lnk')
					$DeferredUnpinNames.Add('Copilot')
				}
				else
				{
					$CopilotItems = @(
						Get-TaskbarPinnedMatches -Patterns @('Copilot', 'Recall')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match 'Copilot'
						}
					) | Select-Object -Unique
					if ($CopilotItems)
					{
						$CopilotItems | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Copilot' was not found."
						$UnpinMisses++
					}
				}
			}
			Microsoft365
			{
				$Microsoft365FallbackPatterns = @('*Microsoft 365*.lnk', '*Office*.lnk')

				if ($NeedsDeferredUnpin)
				{
					$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					$DeferredUnpinNames.Add('Microsoft 365')
					$DeferredUnpinNames.Add('^Office$')
				}
				else
				{
					$Microsoft365Items = @(
						Get-TaskbarPinnedMatches -Patterns @('Microsoft 365', 'Office')
						$AppsFolder.Items() | Where-Object -FilterScript {
							$_.Name -match "Microsoft 365" -or
							$_.Name -match "Office"
						}
					) | Select-Object -Unique

					if ($Microsoft365Items)
					{
						$Microsoft365Items | ForEach-Object {
							if (-not (Invoke-TaskbarUnpinWithFallback -ShellItem $_))
							{
								$UnpinFailures++
							}
						}
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
					else
					{
						LogInfo "Taskbar shortcut target 'Microsoft365' was not found."
						$UnpinMisses++
						$null = Remove-TaskbarPinnedLinksByPattern -Patterns $Microsoft365FallbackPatterns
					}
				}
			}
		}
	}

	# ARM64 and Windows 10: run COM unpin in a background STA runspace with timeout
	if ($NeedsDeferredUnpin -and $DeferredUnpinNames.Count -gt 0)
	{
		Invoke-ARM64ShellUnpin -AppNames $DeferredUnpinNames.ToArray() -TimeoutSeconds 15
	}

	# Restart Explorer to apply taskbar changes
	try
	{
		Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
		Start-Process "explorer.exe" -ErrorAction SilentlyContinue
	}
	catch
	{
		LogWarning "Failed to restart Explorer after taskbar unpin: $($_.Exception.Message)"
	}

	if ($UnpinFailures -gt 0)
	{
		Write-ConsoleStatus -Status warning
	}
	else
	{
		Write-ConsoleStatus -Status success
	}
}

<#
	.SYNOPSIS
	End task in taskbar by right click

	.PARAMETER Enable
	Enable end task in taskbar by right click

	.PARAMETER Disable
	Disable end task in taskbar by right click (default value)

	.EXAMPLE
	TaskbarEndTask -Enable

	.EXAMPLE
	TaskbarEndTask -Disable

	.NOTES
	Current user
#>
function TaskbarEndTask
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

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'End task in taskbar by right click'"
			LogInfo "Enabling 'End task in taskbar by right click'"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name TaskbarEndTask -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'End task in taskbar by right click'"
			LogInfo "Disabling 'End task in taskbar by right click'"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name TaskbarEndTask -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name TaskbarEndTask -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
	}
}
