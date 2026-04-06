<#
    .SYNOPSIS
    Nightly wake-up for Automatic Maintenance and Windows Updates

    .PARAMETER Enable
    Enable the nightly wake-up for automatic maintenance and Windows updates (default value)

    .PARAMETER Disable
    Disable the nightly wake-up for automatic maintenance and Windows updates

    .EXAMPLE
    MaintenanceWakeUp -Enable

    .EXAMPLE
    MaintenanceWakeUp -Disable

    .NOTES
    Current user
#>
function MaintenanceWakeUp
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
			Write-ConsoleStatus -Action "Enabling Nightly wake-up for Automatic Maintenance and Windows Updates"
			LogInfo "Enabling Nightly wake-up for Automatic Maintenance and Windows Updates"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" | Out-Null
				}
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "WakeUp" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "WakeUp" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable nightly wake-up for maintenance and updates: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Nightly wake-up for Automatic Maintenance and Windows Updates"
			LogInfo "Disabling Nightly wake-up for Automatic Maintenance and Windows Updates"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name "WakeUp" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable nightly wake-up for maintenance and updates: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Manage the offering of Malicious Software Removal Tool through Windows Update settings

    .PARAMETER Enable
    Enable the offering of Malicious Software Removal Tool through Windows Update (default value)

    .PARAMETER Disable
    Disable the offering of Malicious Software Removal Tool through Windows Update

    .EXAMPLE
    UpdateMSRT -Enable

    .EXAMPLE
    UpdateMSRT -Disable

    .NOTES
    Current user
#>
function UpdateMSRT
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
			Write-ConsoleStatus -Action "Enabling Malicious Software Removal Tool through Windows Update"
			LogInfo "Enabling Offering of Malicious Software Removal Tool through Windows Update"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable MSRT through Windows Update: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Malicious Software Removal Tool through Windows Update"
			LogInfo "Disabling Offering of Malicious Software Removal Tool through Windows Update"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -Type DWord -Value 1 -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable MSRT through Windows Update: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to microphone settings

    .DESCRIPTION
    Note: This disables access using standard Windows API. Direct access to device will still be allowed.

    .PARAMETER Enable
    Enable access to microphone (default value)

    .PARAMETER Disable
    Disable access to microphone

    .EXAMPLE
    Microphone -Enable

    .EXAMPLE
    Microphone -Disable

    .NOTES
    Current user
#>
function Microphone
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
			Write-ConsoleStatus -Action "Enabling Access to use the microphone"
			LogInfo "Enabling Access to use the microphone"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMicrophone" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMicrophone" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable microphone access: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Access to use the microphone"
			LogInfo "Disabling Access to use the microphone"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessMicrophone" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable microphone access: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Configure the setting to receive updates for other Microsoft products via Windows Update

.PARAMETER Enable
Enable receiving updates for other Microsoft products via Windows Update

.PARAMETER Disable
Disable receiving updates for other Microsoft products via Windows Update (default value)

.EXAMPLE
UpdateMSProducts -Enable

.EXAMPLE
UpdateMSProducts -Disable

.NOTES
Current user
#>
function UpdateMSProducts
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
			Write-ConsoleStatus -Action "Enabling updates for other Microsoft products via Windows Update"
			LogInfo "Enabling updates for other Microsoft products via Windows Update"
			(New-Object -ComObject Microsoft.Update.ServiceManager).AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "") | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling updates for other Microsoft products via Windows Update"
			LogInfo "Disabling updates for other Microsoft products via Windows Update"
			If ((New-Object -ComObject Microsoft.Update.ServiceManager).Services | Where-Object { $_.ServiceID -eq "7971f918-a847-4430-9279-4a52d1efe18d"}) {
				(New-Object -ComObject Microsoft.Update.ServiceManager).RemoveService("7971f918-a847-4430-9279-4a52d1efe18d") | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
	}
}

<#
    .SYNOPSIS
    Updating of NTFS last access timestamps settings

    .PARAMETER Enable
    Enable updating of NTFS last access timestamps (default value)

    .PARAMETER Disable
    Disable updating of NTFS last access timestamps

    .EXAMPLE
    NTFSLastAccess -Enable

    .EXAMPLE
    NTFSLastAccess -Disable

    .NOTES
    Current user
#>
function NTFSLastAccess
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
			Write-ConsoleStatus -Action "Enable Updating of NTFS last access timestamps"
			LogInfo "Enable Updating of NTFS last access timestamps"
			try
			{
				If ([System.Environment]::OSVersion.Version.Build -ge 17134) {
					fsutil behavior set DisableLastAccess 2 | Out-Null
				} Else {
					fsutil behavior set DisableLastAccess 0 | Out-Null
				}
				if ($LASTEXITCODE -ne 0)
				{
					throw "fsutil returned exit code $LASTEXITCODE"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable updating of NTFS last access timestamps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disable Updating of NTFS last access timestamps"
			LogInfo "Disable Updating of NTFS last access timestamps"
			try
			{
				fsutil behavior set DisableLastAccess 1 | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "fsutil returned exit code $LASTEXITCODE"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable updating of NTFS last access timestamps: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
NTFS paths with length over 260 characters settings

.PARAMETER Enable
Enable NTFS paths with length over 260 characters

.PARAMETER Disable
Disable NTFS paths with length over 260 characters (default value)

.EXAMPLE
NTFSLongPaths -Enable

.EXAMPLE
NTFSLongPaths -Disable

.NOTES
Current user
#>
function NTFSLongPaths
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
			Write-ConsoleStatus -Action "Enabling NTFS Long Paths"
			LogInfo "Enabling NTFS Long Paths"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable NTFS Long Paths: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling NTFS Long Paths"
			LogInfo "Disabling NTFS Long Paths"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable NTFS Long Paths: $($_.Exception.Message)"
			}
		}
	}
}


<#
    .SYNOPSIS
    Shared Experiences feature settings

    .PARAMETER Enable
    Enable the Shared Experiences feature

    .PARAMETER Disable
    Disable the Shared Experiences feature

    .EXAMPLE
    SharedExperiences -Enable

    .EXAMPLE
    SharedExperiences -Disable

    .NOTES
    Current user
#>
function SharedExperiences
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
			Write-ConsoleStatus -Action "Enabling Shared Experiences"
			LogInfo "Enabling Shared Experiences"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -Name "RomeSdkChannelUserAuthzPolicy" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Shared Experiences: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Shared Experiences"
			LogInfo "Disabling Shared Experiences"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -Name "RomeSdkChannelUserAuthzPolicy" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Shared Experiences: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The sign-in info to automatically finish setting up device after an update

	.PARAMETER Disable
	Do not use sign-in info to automatically finish setting up device after an update

	.PARAMETER Enable
	Use sign-in info to automatically finish setting up device after an update (default value)

	.EXAMPLE
	SigninInfo -Disable

	.EXAMPLE
	SigninInfo -Enable

	.NOTES
	Current user
#>
function SigninInfo
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name DisableAutomaticRestartSignOn -Force -ErrorAction Ignore
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name DisableAutomaticRestartSignOn -Type CLEAR

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sign-in info to automatically finish setting up device after an update"
			LogInfo "Disabling sign-in info to automatically finish setting up device after an update"
			try
			{
				$SID = (Get-CimInstance -ClassName Win32_UserAccount | Where-Object -FilterScript {$_.Name -eq $env:USERNAME}).SID
				if (-not (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$SID"))
				{
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$SID" -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$SID" -Name OptOut -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sign-in info after updates: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling sign-in info to automatically finish setting up device after an update"
			LogInfo "Enabling sign-in info to automatically finish setting up device after an update"
			try
			{
				$SID = (Get-CimInstance -ClassName Win32_UserAccount | Where-Object -FilterScript {$_.Name -eq $env:USERNAME}).SID
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$SID" -Name OptOut -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$SID" -Name "OptOut" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sign-in info after updates: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Sleep start menu and keyboard button feature settings

    .PARAMETER Enable
    Enable the Sleep start menu and keyboard button (default value)

    .PARAMETER Disable
    Disable the Sleep start menu and keyboard button

    .EXAMPLE
    SleepButton -Enable

    .EXAMPLE
    SleepButton -Disable

    .NOTES
    Current user
#>
function SleepButton
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
			Write-ConsoleStatus -Action "Enabling Sleep start menu and keyboard button"
			LogInfo "Enabling Sleep start menu and keyboard button"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowSleepOption" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 1 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 1 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Sleep Start menu and keyboard button: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Sleep start menu and keyboard button"
			LogInfo "Disabling Sleep start menu and keyboard button"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowSleepOption" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Sleep Start menu and keyboard button: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Superfetch service settings

    .PARAMETER Enable
    Enable the Superfetch service (default value)

    .PARAMETER Disable
    Disable the Superfetch service

    .EXAMPLE
    Superfetch -Enable

    .EXAMPLE
    Superfetch -Disable

    .NOTES
    Current user
#>
function Superfetch
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
			Write-ConsoleStatus -Action "Enabling Superfetch service"
			LogInfo "Enabling Superfetch service"
			try
			{
				Set-Service "SysMain" -StartupType Automatic -ErrorAction Stop | Out-Null
				Start-Service "SysMain" -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Superfetch service: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Superfetch service"
			LogInfo "Disabling Superfetch service"
			try
			{
				Stop-Service "SysMain" -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
				Set-Service "SysMain" -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Superfetch service: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Tailored experiences

	.PARAMETER Disable
	Do not let Microsoft use your diagnostic data for personalized tips, ads, and recommendations

	.PARAMETER Enable
	Let Microsoft use your diagnostic data for personalized tips, ads, and recommendations (default value)

	.EXAMPLE
	TailoredExperiences -Disable

	.EXAMPLE
	TailoredExperiences -Enable

	.NOTES
	Current user
#>
function TailoredExperiences
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
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\CloudContent -Name DisableTailoredExperiencesWithDiagnosticData -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\CloudContent -Name DisableTailoredExperiencesWithDiagnosticData -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Diagnostic data for personalized tips, ads, and recommendations"
			LogInfo "Disabling Diagnostic data for personalized tips, ads, and recommendations"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy -Name TailoredExperiencesWithDiagnosticDataEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable tailored experiences: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Diagnostic data for personalized tips, ads, and recommendations"
			LogInfo "Enabling Diagnostic data for personalized tips, ads, and recommendations"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy -Name TailoredExperiencesWithDiagnosticDataEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable tailored experiences: $($_.Exception.Message)"
			}
		}
	}
}


<#
    .SYNOPSIS
    UWP apps swap file settings

    .DESCRIPTION
    This disables creation and use of swapfile.sys and frees 256 MB of disk space. Swapfile.sys is used only by UWP apps.
	IMPORTANT: The tweak has no effect on the real swap in pagefile.sys.

    .PARAMETER Enable
    Enable the UWP apps swap file

    .PARAMETER Disable
    Disable the UWP apps swap file

    .EXAMPLE
    UWPSwapFile -Enable

    .EXAMPLE
    UWPSwapFile -Disable

    .NOTES
    Current user
#>
function UWPSwapFile
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
			Write-ConsoleStatus -Action "Enabling the UWP apps swap file"
			LogInfo "Enabling the UWP apps swap file"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "SwapfileControl" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "SwapfileControl" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the UWP apps swap file: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the UWP apps swap file"
			LogInfo "Disabling the UWP apps swap file"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "SwapfileControl" -Type Dword -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the UWP apps swap file: $($_.Exception.Message)"
			}
		}
	}
}


<#
    .SYNOPSIS
    Location feature settings

    .PARAMETER Enable
    Enable the setting "Let websites provide locally relevant content by accessing my language list"

    .PARAMETER Disable
    Disable the setting "Let websites provide locally relevant content by accessing my language list"

    .EXAMPLE
    WebLangList -Enable

    .EXAMPLE
    WebLangList -Disable

    .NOTES
    Current user
#>
function WebLangList
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
			Write-ConsoleStatus -Action "Enabling websites to show relevant content by accessing my language list"
			LogInfo "Enabling websites to show relevant content by accessing my language list"
			try
			{
				if (Test-Path -Path "HKCU:\Control Panel\International\User Profile")
				{
					Remove-RegistryValueSafe -Path "HKCU:\Control Panel\International\User Profile" -Name "HttpAcceptLanguageOptOut" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable websites accessing the user's language list: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling websites to show relevant content by accessing my language list"
			LogInfo "Disabling websites to show relevant content by accessing my language list"
			try
			{
				Set-ItemProperty -Path "HKCU:\Control Panel\International\User Profile" -Name "HttpAcceptLanguageOptOut" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable websites accessing the user's language list: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Wi-Fi Sense configuration

	.PARAMETER Disable
	Disable Wi-Fi Sense to prevent automatic connection to open hotspots and sharing of Wi-Fi networks.

	.PARAMETER Enable
	Enable Wi-Fi Sense to allow automatic connection to open hotspots and sharing of Wi-Fi networks.

	.EXAMPLE
	WiFiSense -Disable

	.EXAMPLE
	WiFiSense -Enable

	.NOTES
	Current user
#>
function WiFiSense
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
			Write-ConsoleStatus -Action "Enabling Wi-Fi Sense to allow automatic connection to open hotspots and sharing of Wi-Fi networks"
			LogInfo "Enabling Wi-Fi Sense to allow automatic connection to open hotspots and sharing of Wi-Fi networks"
			If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting")) {
				New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Force | Out-Null
			}
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 1
			If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots")) {
				New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Force | Out-Null
			}
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 1 | Out-Null
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "WiFISenseAllowed" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Wi-Fi Sense to prevent automatic connection to open hotspots and sharing of Wi-Fi networks"
			LogInfo "Disabling Wi-Fi Sense to prevent automatic connection to open hotspots and sharing of Wi-Fi networks"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "WiFISenseAllowed" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Wi-Fi Sense: $($_.Exception.Message)"
			}
		}
	}
}


<#
    .SYNOPSIS
    Windows Update automatic downloads settings

    .PARAMETER Enable
    Enable Windows Update automatic downloads (default value)

    .PARAMETER Disable
    Disable Windows Update automatic downloads

    .EXAMPLE
    UpdateAutoDownload -Enable

    .EXAMPLE
    UpdateAutoDownload -Disable

    .NOTES
    Current user
#>
function UpdateAutoDownload
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
			Write-ConsoleStatus -Action "Enabling Automatic Windows Updates"
			LogInfo "Enabling Automatic Windows Updates"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Automatic Windows Updates: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Automatic Windows Updates"
			LogInfo "Disabling Automatic Windows Updates"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 2 -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Automatic Windows Updates: $($_.Exception.Message)"
			}
		}
	}
}

#endregion Privacy & Telemetry

Export-ModuleMember -Function '*'
