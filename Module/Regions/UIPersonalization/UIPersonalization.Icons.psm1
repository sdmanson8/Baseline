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
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn"
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
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons" -Name "29"
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
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates" -Name "ShortcutNameTemplate"
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
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
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
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbnailCache"
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
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisableThumbsDBOnNetworkFolders"
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
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	# Get MachineId
	$MachineId = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient", "MachineId", $null)
	if (-not $MachineId)
	{
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
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

Export-ModuleMember -Function '*'
