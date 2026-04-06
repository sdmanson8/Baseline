using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
    .SYNOPSIS
    Access to account info from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to account info from UWP apps

    .PARAMETER Disable
    Disable access to account info from UWP apps

    .EXAMPLE
    UWPAccountInfo -Enable

    .EXAMPLE
    UWPAccountInfo -Disable

    .NOTES
    Current user
#>
function UWPAccountInfo
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
			Write-ConsoleStatus -Action "Enabling access to account info from UWP apps"
			LogInfo "Enabling access to account info from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessAccountInfo" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessAccountInfo" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to account info from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to account info from UWP apps"
			LogInfo "Disabling access to account info from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessAccountInfo" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to account info from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to calendar from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to calendar from UWP apps

    .PARAMETER Disable
    Disable access to calendar from UWP apps

    .EXAMPLE
    UWPCalendar -Enable

    .EXAMPLE
    UWPCalendar -Disable

    .NOTES
    Current user
#>
function UWPCalendar
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
			Write-ConsoleStatus -Action "Enabling access to calendar from UWP apps"
			LogInfo "Enabling access to calendar from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCalendar" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCalendar" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to calendar from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to calendar from UWP apps"
			LogInfo "Disabling access to calendar from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCalendar" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to calendar from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to call history from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to call history from UWP apps

    .PARAMETER Disable
    Disable access to call history from UWP apps

    .EXAMPLE
    UWPCallHistory -Enable

    .EXAMPLE
    UWPCallHistory -Disable

    .NOTES
    Current user
#>
function UWPCallHistory
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
			Write-ConsoleStatus -Action "Enabling access to call history from UWP apps"
			LogInfo "Enabling access to call history from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCallHistory" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCallHistory" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to call history from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to call history from UWP apps"
			LogInfo "Disabling access to call history from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCallHistory" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to call history from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to contacts from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to contacts from UWP apps

    .PARAMETER Disable
    Disable access to contacts from UWP apps

    .EXAMPLE
    UWPContacts -Enable

    .EXAMPLE
    UWPContacts -Disable

    .NOTES
    Current user
#>
function UWPContacts
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
			Write-ConsoleStatus -Action "Enabling access to contacts from UWP apps"
			LogInfo "Enabling access to contacts from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessContacts" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessContacts" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to contacts from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to contacts from UWP apps"
			LogInfo "Disabling access to contacts from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessContacts" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to contacts from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to diagnostic information from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to diagnostic information from UWP apps

    .PARAMETER Disable
    Disable access to diagnostic information from UWP apps

    .EXAMPLE
    UWPDiagInfo -Enable

    .EXAMPLE
    UWPDiagInfo -Disable

    .NOTES
    Current user
#>
function UWPDiagInfo
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
			Write-ConsoleStatus -Action "Enabling access to diagnostic information from UWP apps"
			LogInfo "Enabling access to diagnostic information from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsGetDiagnosticInfo" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsGetDiagnosticInfo" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to diagnostic information from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to diagnostic information from UWP apps"
			LogInfo "Disabling access to diagnostic information from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsGetDiagnosticInfo" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to diagnostic information from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to email from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to email from UWP apps

    .PARAMETER Disable
    Disable access to email from UWP apps

    .EXAMPLE
    UWPEmail -Enable

    .EXAMPLE
    UWPEmail -Disable

    .NOTES
    Current user
#>
function UWPEmail
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
			Write-ConsoleStatus -Action "Enabling access to email from UWP apps"
			LogInfo "Enabling access to email from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessEmail" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessEmail" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to email from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to email from UWP apps"
			LogInfo "Disabling access to email from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessEmail" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to email from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to libraries and file system from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to libraries and file system from UWP apps

    .PARAMETER Disable
    Disable access to libraries and file system from UWP apps

    .EXAMPLE
    UWPFileSystem -Enable

    .EXAMPLE
    UWPFileSystem -Disable

    .NOTES
    Current user
#>
function UWPFileSystem
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
			Write-ConsoleStatus -Action "Enabling access to libraries and the file system from UWP apps"
			LogInfo "Enabling access to libraries and the file system from UWP apps"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\documentsLibrary" -Name "Value" -Type String -Value "Allow" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\picturesLibrary" -Name "Value" -Type String -Value "Allow" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\videosLibrary" -Name "Value" -Type String -Value "Allow" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\broadFileSystemAccess" -Name "Value" -Type String -Value "Allow" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to libraries and the file system from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to libraries and the file system from UWP apps"
			LogInfo "Disabling access to libraries and the file system from UWP apps"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\documentsLibrary" -Name "Value" -Type String -Value "Deny" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\picturesLibrary" -Name "Value" -Type String -Value "Deny" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\videosLibrary" -Name "Value" -Type String -Value "Deny" -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\broadFileSystemAccess" -Name "Value" -Type String -Value "Deny" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to libraries and the file system from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to messaging (SMS, MMS) from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to messaging (SMS, MMS) from UWP apps

    .PARAMETER Disable
    Disable access to messaging (SMS, MMS) from UWP apps

    .EXAMPLE
    UWPMessaging -Enable

    .EXAMPLE
    UWPMessaging -Disable

    .NOTES
    Current user
#>
function UWPMessaging
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
			Write-ConsoleStatus -Action "Enabling access to messaging (SMS, MMS) from UWP apps"
			LogInfo "Enabling access to messaging (SMS, MMS) from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMessaging" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMessaging" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to messaging from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to messaging (SMS, MMS) from UWP apps"
			LogInfo "Disabling access to messaging (SMS, MMS) from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMessaging" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to messaging from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to notifications from UWP (Universal Windows Platform) apps

    .PARAMETER Enable
    Enable access to notifications from UWP apps

    .PARAMETER Disable
    Disable access to notifications from UWP apps

    .EXAMPLE
    UWPNotifications -Enable

    .EXAMPLE
    UWPNotifications -Disable

    .NOTES
    Current user
#>
function UWPNotifications
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
			Write-ConsoleStatus -Action "Enabling access to notifications from UWP apps"
			LogInfo "Enabling access to notifications from UWP apps"
			try
			{
				if (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")
				{
					$property = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessNotifications" -ErrorAction Ignore
					if ($null -ne $property)
					{
						Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessNotifications" | Out-Null
					}
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to notifications from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to notifications from UWP apps"
			LogInfo "Disabling access to notifications from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessNotifications" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to notifications from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to other devices (unpaired, beacons, TVs etc.) from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to other devices (unpaired, beacons, TVs etc.) from UWP apps

    .PARAMETER Disable
    Disable access to other devices (unpaired, beacons, TVs etc.) from UWP apps

    .EXAMPLE
    UWPOtherDevices -Enable

    .EXAMPLE
    UWPOtherDevices -Disable

    .NOTES
    Current user
#>
function UWPOtherDevices
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
			Write-ConsoleStatus -Action "Enabling access to other devices (unpaired, beacons, TVs etc.) from UWP apps"
			LogInfo "Enabling access to other devices (unpaired, beacons, TVs etc.) from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsSyncWithDevices" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsSyncWithDevices" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to other devices from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to other devices (unpaired, beacons, TVs etc.) from UWP apps"
			LogInfo "Disabling access to other devices (unpaired, beacons, TVs etc.) from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsSyncWithDevices" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to other devices from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to phone calls from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to phone calls from UWP apps

    .PARAMETER Disable
    Disable access to phone calls from UWP apps

    .EXAMPLE
    UWPPhoneCalls -Enable

    .EXAMPLE
    UWPPhoneCalls -Disable

    .NOTES
    Current user
#>
function UWPPhoneCalls
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
			Write-ConsoleStatus -Action "Enabling access to phone calls from UWP apps"
			LogInfo "Enabling access to phone calls from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessPhone" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessPhone" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to phone calls from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to phone calls from UWP apps"
			LogInfo "Disabling access to phone calls from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessPhone" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to phone calls from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to radios (e.g. Bluetooth) from UWP (Universal Windows Platform) apps settings

    .PARAMETER Enable
    Enable access to radios (e.g. Bluetooth) from UWP apps

    .PARAMETER Disable
    Disable access to radios (e.g. Bluetooth) from UWP apps

    .EXAMPLE
    UWPRadios -Enable

    .EXAMPLE
    UWPRadios -Disable

    .NOTES
    Current user
#>
function UWPRadios
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
			Write-ConsoleStatus -Action "Enabling access to radios (e.g. Bluetooth) from UWP apps"
			LogInfo "Enabling access to radios (e.g. Bluetooth) from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessRadios" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessRadios" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to radios from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to radios (e.g. Bluetooth) from UWP apps"
			LogInfo "Disabling access to radios (e.g. Bluetooth) from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessRadios" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to radios from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to tasks from UWP (Universal Windows Platform) apps

    .PARAMETER Enable
    Enable access to tasks from UWP apps

    .PARAMETER Disable
    Disable access to tasks from UWP apps

    .EXAMPLE
    UWPTasks -Enable

    .EXAMPLE
    UWPTasks -Disable

    .NOTES
    Current user
#>
function UWPTasks
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
			Write-ConsoleStatus -Action "Enabling access to tasks from UWP apps"
			LogInfo "Enabling access to tasks from UWP apps"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessTasks" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessTasks" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable access to tasks from UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to tasks from UWP apps"
			LogInfo "Disabling access to tasks from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessTasks" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable access to tasks from UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to voice activation from UWP (Universal Windows Platform) apps

    .PARAMETER Enable
    Enable access to voice activation from UWP apps

    .PARAMETER Disable
    Disable access to voice activation from UWP apps

    .EXAMPLE
    UWPVoiceActivation -Enable

    .EXAMPLE
    UWPVoiceActivation -Disable

    .NOTES
    Current user
#>
function UWPVoiceActivation
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
			Write-ConsoleStatus -Action "Enabling access to voice activation from UWP apps"
			LogInfo "Enabling access to voice activation from UWP apps"
			try
			{
				Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsActivateWithVoice" -ErrorAction SilentlyContinue | Out-Null
				Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsActivateWithVoiceAboveLock" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable voice activation for UWP apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling access to voice activation from UWP apps"
			LogInfo "Disabling access to voice activation from UWP apps"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsActivateWithVoice" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsActivateWithVoiceAboveLock" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable voice activation for UWP apps: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
