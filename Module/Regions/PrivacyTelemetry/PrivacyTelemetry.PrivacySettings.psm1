#region Privacy & Telemetry

<#
    .SYNOPSIS
    Configures privacy and telemetry settings.



.DESCRIPTION

Applies Baseline's privacy and telemetry settings in GUI and headless runs.
    .PARAMETER Hide
    Do not show Activity History-related notifications in Task View

    .PARAMETER Show
    Show Activity History-related notifications in Task View

    .EXAMPLE
    ActivityHistory -Enable

    .EXAMPLE
    ActivityHistory -Disable

    .NOTES
    Current user
#>
function ActivityHistory
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
			Write-ConsoleStatus -Action "Enabling Activity History related notifications in Task View"
			LogInfo "Enabling Activity History-related notifications in Task View"
			try
			{
				Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -ErrorAction SilentlyContinue | Out-Null
				Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -ErrorAction SilentlyContinue | Out-Null
				Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Activity History notifications in Task View: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Activity History related notifications in Task View"
			LogInfo "Disabling Activity History-related notifications in Task View"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Activity History notifications in Task View: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The permission for apps to show me personalized ads by using my advertising ID



.DESCRIPTION

Applies the Baseline behavior for the permission for apps to show me personalized ads by using my advertising ID.
	.PARAMETER Disable
	Do not let apps show me personalized ads by using my advertising ID

	.PARAMETER Enable
	Let apps show me personalized ads by using my advertising ID (default value)

	.EXAMPLE
	AdvertisingID -Disable

	.EXAMPLE
	AdvertisingID -Enable

	.NOTES
	Current user
#>
function AdvertisingID
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo -Name DisabledByGroupPolicy -Force -ErrorAction Ignore
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name DisabledByGroupPolicy -Type CLEAR

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling apps showing personalized ads by using advertising ID"
			LogInfo "Disabling apps showing personalized ads by using advertising ID"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -Type DWord -Value 0 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable personalized ads by using advertising ID: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling apps showing personalized ads by using advertising ID"
			LogInfo "Enabling apps showing personalized ads by using advertising ID"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable personalized ads by using advertising ID: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Automatic reboot on crash (BSOD) settings



.DESCRIPTION

Applies the Baseline behavior for automatic reboot on crash (BSOD) settings.
    .PARAMETER Enable
    Enable automatic reboot on crash

    .PARAMETER Disable
    Disable automatic reboot on crash (default value)

    .EXAMPLE
    AutoRebootOnCrash -Enable

    .EXAMPLE
    AutoRebootOnCrash -Disable

    .NOTES
    Current user
#>
function AutoRebootOnCrash
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
			Write-ConsoleStatus -Action "Enabling Automatically reboot on BSOD"
			LogInfo "Enabling Automatically reboot on BSOD"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "AutoReboot" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable automatic reboot on BSOD: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Automatically reboot on BSOD"
			LogInfo "Disabling Automatically reboot on BSOD"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "AutoReboot" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable automatic reboot on BSOD: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Automatic restart after Windows Update installation settings

    .DESCRIPTION
    IMPORTANT: This tweak is experimental and should be used with caution
    It works by registering a dummy debugger for MusNotification.exe, which effectively blocks the restart prompt executable from running. This prevents the system from scheduling the automatic restart after a Windows Update installation, potentially avoiding unwanted restarts.

    .PARAMETER Enable
    Enable automatic restart after Windows Update installation (default value)

    .PARAMETER Disable
    Disable automatic restart after Windows Update installation

    .EXAMPLE
    UpdateRestart -Enable

    .EXAMPLE
    UpdateRestart -Disable

    .NOTES
    Current user
#>

function UpdateRestart
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
			Write-ConsoleStatus -Action "Enabling Automatic restart after Windows Update"
			LogInfo "Enabling Automatic restart after Windows Update"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe" -Name "Debugger" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe" -Name "Debugger" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable automatic restart after Windows Update: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Automatic restart after Windows Update"
			LogInfo "Disabling Automatic restart after Windows Update"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe" -Name "Debugger" -Type String -Value "cmd.exe" -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable automatic restart after Windows Update: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Online speech recognition



.DESCRIPTION

Applies the Baseline behavior for online speech recognition.
	.PARAMETER Enable
	Enable online speech recognition

	.PARAMETER Disable
	Disable online speech recognition

	.EXAMPLE
	OnlineSpeechRecognition -Enable

	.EXAMPLE
	OnlineSpeechRecognition -Disable

	.NOTES
	Current user
#>
function OnlineSpeechRecognition
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

	$onlineSpeechPrivacyPath = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling online speech recognition"
			LogInfo "Enabling online speech recognition"
			try
			{
				if (-not (Test-Path -Path $onlineSpeechPrivacyPath))
				{
					New-Item -Path $onlineSpeechPrivacyPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $onlineSpeechPrivacyPath -Name HasAccepted -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable online speech recognition: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling online speech recognition"
			LogInfo "Disabling online speech recognition"
			try
			{
				if (-not (Test-Path -Path $onlineSpeechPrivacyPath))
				{
					New-Item -Path $onlineSpeechPrivacyPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $onlineSpeechPrivacyPath -Name HasAccepted -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable online speech recognition: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Narrator online services



.DESCRIPTION

Applies the Baseline behavior for narrator online services.
	.PARAMETER Enable
	Enable Narrator online services

	.PARAMETER Disable
	Disable Narrator online services

	.EXAMPLE
	NarratorOnlineServices -Enable

	.EXAMPLE
	NarratorOnlineServices -Disable

	.NOTES
	Current user
#>
function NarratorOnlineServices
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

	$narratorPath = 'HKCU:\Software\Microsoft\Narrator\NoRoam'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Narrator online services"
			LogInfo "Enabling Narrator online services"
			try
			{
				Remove-ItemProperty -Path $narratorPath -Name OnlineServicesEnabled -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Narrator online services: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Narrator online services"
			LogInfo "Disabling Narrator online services"
			try
			{
				if (-not (Test-Path -Path $narratorPath))
				{
					New-Item -Path $narratorPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $narratorPath -Name OnlineServicesEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Narrator online services: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Narrator scripting support



.DESCRIPTION

Applies the Baseline behavior for narrator scripting support.
	.PARAMETER Enable
	Enable Narrator scripting support

	.PARAMETER Disable
	Disable Narrator scripting support

	.EXAMPLE
	NarratorScriptingSupport -Enable

	.EXAMPLE
	NarratorScriptingSupport -Disable

	.NOTES
	Current user
#>
function NarratorScriptingSupport
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

	$narratorPath = 'HKCU:\Software\Microsoft\Narrator\NoRoam'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Narrator scripting support"
			LogInfo "Enabling Narrator scripting support"
			try
			{
				Remove-ItemProperty -Path $narratorPath -Name ScriptingEnabled -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Narrator scripting support: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Narrator scripting support"
			LogInfo "Disabling Narrator scripting support"
			try
			{
				if (-not (Test-Path -Path $narratorPath))
				{
					New-Item -Path $narratorPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $narratorPath -Name ScriptingEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Narrator scripting support: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Inking and typing personalization



.DESCRIPTION

Applies the Baseline behavior for inking and typing personalization.
	.PARAMETER Enable
	Enable inking and typing personalization

	.PARAMETER Disable
	Disable inking and typing personalization

	.EXAMPLE
	InkingAndTypingPersonalization -Enable

	.EXAMPLE
	InkingAndTypingPersonalization -Disable

	.NOTES
	Current user
#>
function InkingAndTypingPersonalization
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

	$inkingTypingPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling inking and typing personalization"
			LogInfo "Enabling inking and typing personalization"
			try
			{
				if (-not (Test-Path -Path $inkingTypingPath))
				{
					New-Item -Path $inkingTypingPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $inkingTypingPath -Name Value -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable inking and typing personalization: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling inking and typing personalization"
			LogInfo "Disabling inking and typing personalization"
			try
			{
				if (-not (Test-Path -Path $inkingTypingPath))
				{
					New-Item -Path $inkingTypingPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $inkingTypingPath -Name Value -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable inking and typing personalization: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Search history on this device



.DESCRIPTION

Applies the Baseline behavior for search history on this device.
	.PARAMETER Enable
	Enable search history on this device

	.PARAMETER Disable
	Disable search history on this device

	.EXAMPLE
	DeviceSearchHistory -Enable

	.EXAMPLE
	DeviceSearchHistory -Disable

	.NOTES
	Current user
#>
function DeviceSearchHistory
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

	$searchSettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling search history on this device"
			LogInfo "Enabling search history on this device"
			try
			{
				Remove-ItemProperty -Path $searchSettingsPath -Name IsDeviceSearchHistoryEnabled -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable search history on this device: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling search history on this device"
			LogInfo "Disabling search history on this device"
			try
			{
				if (-not (Test-Path -Path $searchSettingsPath))
				{
					New-Item -Path $searchSettingsPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $searchSettingsPath -Name IsDeviceSearchHistoryEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable search history on this device: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Cloud content search



.DESCRIPTION

Applies the Baseline behavior for cloud content search.
	.PARAMETER Enable
	Enable cloud content search for Microsoft and work/school accounts

	.PARAMETER Disable
	Disable cloud content search for Microsoft and work/school accounts

	.EXAMPLE
	CloudContentSearch -Enable

	.EXAMPLE
	CloudContentSearch -Disable

	.NOTES
	Current user
#>
function CloudContentSearch
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

	$searchSettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling cloud content search"
			LogInfo "Enabling cloud content search"
			try
			{
				Remove-ItemProperty -Path $searchSettingsPath -Name IsMSACloudSearchEnabled -Force -ErrorAction SilentlyContinue | Out-Null
				Remove-ItemProperty -Path $searchSettingsPath -Name IsAADCloudSearchEnabled -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable cloud content search: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling cloud content search"
			LogInfo "Disabling cloud content search"
			try
			{
				if (-not (Test-Path -Path $searchSettingsPath))
				{
					New-Item -Path $searchSettingsPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $searchSettingsPath -Name IsMSACloudSearchEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $searchSettingsPath -Name IsAADCloudSearchEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable cloud content search: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Block Workplace Join and AAD device join messages



.DESCRIPTION

Applies the Baseline behavior for block Workplace Join and AAD device join messages.
	.PARAMETER Enable
	Block Workplace Join and AAD device join messages

	.PARAMETER Disable
	Allow Workplace Join and AAD device join messages

	.EXAMPLE
	WorkplaceJoinMessages -Enable

	.EXAMPLE
	WorkplaceJoinMessages -Disable

	.NOTES
	Machine-wide and current user
#>
function WorkplaceJoinMessages
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

	$workplaceJoinMachinePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
	$workplaceJoinUserPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Blocking Workplace Join messages"
			LogInfo "Blocking Workplace Join messages"
			try
			{
				if (-not (Test-Path -Path $workplaceJoinMachinePath))
				{
					New-Item -Path $workplaceJoinMachinePath -Force -ErrorAction Stop | Out-Null
				}
				if (-not (Test-Path -Path $workplaceJoinUserPath))
				{
					New-Item -Path $workplaceJoinUserPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $workplaceJoinMachinePath -Name BlockAADWorkplaceJoin -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $workplaceJoinUserPath -Name BlockAADWorkplaceJoin -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to block Workplace Join messages: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Unblocking Workplace Join messages"
			LogInfo "Unblocking Workplace Join messages"
			try
			{
				Remove-ItemProperty -Path $workplaceJoinMachinePath -Name BlockAADWorkplaceJoin -Force -ErrorAction SilentlyContinue | Out-Null
				Remove-ItemProperty -Path $workplaceJoinUserPath -Name BlockAADWorkplaceJoin -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to unblock Workplace Join messages: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Prevent BitLocker auto encryption



.DESCRIPTION

Applies the Baseline behavior for prevent BitLocker auto encryption.
	.PARAMETER Enable
	Prevent BitLocker auto encryption

	.PARAMETER Disable
	Allow BitLocker auto encryption

	.EXAMPLE
	BitLockerAutoEncryption -Enable

	.EXAMPLE
	BitLockerAutoEncryption -Disable

	.NOTES
	Machine-wide
#>
function BitLockerAutoEncryption
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

	$bitLockerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Preventing BitLocker auto encryption"
			LogInfo "Preventing BitLocker auto encryption"
			try
			{
				if (-not (Test-Path -Path $bitLockerPath))
				{
					New-Item -Path $bitLockerPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $bitLockerPath -Name PreventDeviceEncryption -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to prevent BitLocker auto encryption: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Allowing BitLocker auto encryption"
			LogInfo "Allowing BitLocker auto encryption"
			try
			{
				if (-not (Test-Path -Path $bitLockerPath))
				{
					New-Item -Path $bitLockerPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $bitLockerPath -Name PreventDeviceEncryption -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to allow BitLocker auto encryption: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Automatic Map Updates settings and scripting



.DESCRIPTION

Applies the Baseline behavior for automatic Map Updates settings and scripting.
    .PARAMETER Enable
    Enable automatic map updates

    .PARAMETER Disable
    Disable automatic map updates

    .EXAMPLE
    MapUpdates -Enable

    .EXAMPLE
    MapUpdates -Disable

    .NOTES
    Current user
#>
function MapUpdates
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
			Write-ConsoleStatus -Action "Enabling automatic map updates"
			LogInfo "Enabling automatic map updates for the current user"
			try
			{
				if (Test-Path -Path "HKLM:\SYSTEM\Maps")
				{
					Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable automatic map updates: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling automatic map updates"
			LogInfo "Disabling automatic map updates for the current user"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable automatic map updates: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Access to camera

    .DESCRIPTION
    Note: This disables access using standard Windows API. Direct access to device will still be allowed.

    .PARAMETER Enable
    Enable access to camera (default value)

    .PARAMETER Disable
    Disable access to camera

    .EXAMPLE
    Camera -Enable

    .EXAMPLE
    Camera -Disable

    .NOTES
    Current user
#>

function Camera
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
			Write-ConsoleStatus -Action "Enabling Access to use the camera"
			LogInfo "Enabling Access to use the camera"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCamera" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCamera" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable camera access: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Access to use the camera"
			LogInfo "Disabling Access to use the camera"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessCamera" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable camera access: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Clipboard History feature settings



.DESCRIPTION

Applies the Baseline behavior for clipboard History feature settings.
    .PARAMETER Enable
    Enable the Clipboard History feature

    .PARAMETER Disable
    Disable the Clipboard History feature (default value)

    .EXAMPLE
    ClipboardHistory -Enable

    .EXAMPLE
    ClipboardHistory -Disable

    .NOTES
    Current user
#>
function ClipboardHistory
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

	$isServer = $false
	if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -ErrorAction SilentlyContinue)
	{
		$isServer = [bool](Get-BaselineSystemPlatformInfo).IsServer
	}
	else
	{
		$isServer = ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)
	}

	if ($isServer)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Clipboard History"
			LogInfo "Enabling Clipboard History"
			try
			{
				$ClipboardPath = "HKCU:\Software\Microsoft\Clipboard"
				if (-not (Test-Path -Path $ClipboardPath))
				{
					New-Item -Path $ClipboardPath -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $ClipboardPath -Name "EnableClipboardHistory" -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Clipboard History: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Clipboard History"
			LogInfo "Disabling Clipboard History"
			try
			{
				$ClipboardPath = "HKCU:\Software\Microsoft\Clipboard"
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -ErrorAction Stop | Out-Null
				}
				if ((Test-Path -Path $ClipboardPath) -and ($null -ne (Get-ItemProperty -Path $ClipboardPath -Name "EnableClipboardHistory" -ErrorAction SilentlyContinue)))
				{
					Remove-RegistryValueSafe -Path $ClipboardPath -Name "EnableClipboardHistory" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Clipboard History: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	Controls sensor-related features, such as screen auto-rotation



.DESCRIPTION

Applies the Baseline behavior for controls sensor-related features, such as screen auto-rotation.
	.PARAMETER Disable
	Disable sensor-related features, such as screen auto-rotation

	.PARAMETER Enable
	Enable sensor-related features, such as screen auto-rotation (default value)

	.EXAMPLE
	Sensors -Disable

	.EXAMPLE
	Sensors -Enable

	.NOTES
	Current user
#>
function Sensors
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
			Write-ConsoleStatus -Action "Enabling sensor-related features, such as screen auto-rotation"
			LogInfo "Enabling sensor-related features, such as screen auto-rotation"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableSensors" -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableSensors" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sensor-related features: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sensor-related features, such as screen auto-rotation"
			LogInfo "Disabling sensor-related features, such as screen auto-rotation"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableSensors" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sensor-related features: $($_.Exception.Message)"
			}
		}
	}
}


<#
    .SYNOPSIS
    Display and sleep mode timeouts



.DESCRIPTION

Applies the Baseline behavior for display and sleep mode timeouts.
    .PARAMETER Enable
    Enable the display and sleep mode timeouts (default value)

    .PARAMETER Disable
    Disable the display and sleep mode timeouts

    .EXAMPLE
    SleepTimeout -Enable

    .EXAMPLE
    SleepTimeout -Disable

    .NOTES
    Current user
#>
function SleepTimeout
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
			Write-ConsoleStatus -Action "Enabling sleep mode timeouts"
			LogInfo "Enabling sleep mode timeouts"
			try
			{
				powercfg /X monitor-timeout-ac 10 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X monitor-timeout-dc 5 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X standby-timeout-ac 30 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X standby-timeout-dc 15 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sleep mode timeouts: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sleep mode timeouts"
			LogInfo "Disabling sleep mode timeouts"
			try
			{
				powercfg /X monitor-timeout-ac 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X monitor-timeout-dc 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X standby-timeout-ac 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				powercfg /X standby-timeout-dc 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "powercfg returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sleep mode timeouts: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Offering of drivers through Windows Update settings

    .DESCRIPTION
    This script enables or disables the Offering of drivers through Windows Update

    IMPORTANT NOTE:
    This does not work properly if you use a driver intended for another hardware model
    For example, Intel I219-V on Windows Server works only with the I219-LM driver
    Therefore, Windows Update will repeatedly try and fail to install the I219-V driver indefinitely,
    even if you use this tweak

    .PARAMETER Enable
    Enable the Offering of drivers through Windows Update (default value)

    .PARAMETER Disable
    Disable the Offering of drivers through Windows Update

    .EXAMPLE
    UpdateDriver -Enable

    .EXAMPLE
    UpdateDriver -Disable

    .NOTES
    Current user
#>

function UpdateDriver
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
			Write-ConsoleStatus -Action "Enabling Offering of drivers through Windows Update"
			LogInfo "Enabling Offering of drivers through Windows Update"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" | Out-Null
				}
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "SearchOrderConfig" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "SearchOrderConfig" | Out-Null
				}
				if ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable offering of drivers through Windows Update: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Offering of drivers through Windows Update"
			LogInfo "Disabling Offering of drivers through Windows Update"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1 -ErrorAction Stop
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 0 -ErrorAction Stop
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1 -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable offering of drivers through Windows Update: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Fast Startup feature settings



.DESCRIPTION

Applies the Baseline behavior for fast Startup feature settings.
    .PARAMETER Enable
    Enable the Fast Startup feature (default value)

    .PARAMETER Disable
    Disable the Fast Startup feature

    .EXAMPLE
    FastStartup -Enable

    .EXAMPLE
    FastStartup -Disable

    .NOTES
    Current user
#>
function FastStartup
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
			Write-ConsoleStatus -Action "Enabling Fast Startup"
			LogInfo "Enabling Fast Startup"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Fast Startup: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Fast Startup"
			LogInfo "Disabling Fast Startup"
			try
			{
				Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Fast Startup: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The feedback frequency



.DESCRIPTION

Applies the Baseline behavior for the feedback frequency.
	.PARAMETER Never
	Change the feedback frequency to "Never"

	.PARAMETER Automatically
	Change feedback frequency to "Automatically" (default value)

	.EXAMPLE
	FeedbackFrequency -Never

	.EXAMPLE
	FeedbackFrequency -Automatically

	.NOTES
	Current user
#>
function FeedbackFrequency
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Never"
		)]
		[switch]
		$Never,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatically"
		)]
		[switch]
		$Automatically
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name DoNotShowFeedbackNotifications -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name DoNotShowFeedbackNotifications -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Never"
		{
			Write-ConsoleStatus -Action "Set Feedback Frequency to Never"
			LogInfo "Setting Feedback Frequency to Never"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Microsoft\Siuf\Rules))
				{
					New-Item -Path HKCU:\Software\Microsoft\Siuf\Rules -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name NumberOfSIUFInPeriod -Type DWord -Value 0 | Out-Null
				if ((Get-ItemProperty -Path HKCU:\Software\Microsoft\Siuf\Rules -Name PeriodInNanoSeconds -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Feedback Frequency to Never: $($_.Exception.Message)"
			}
		}
		"Automatically"
		{
			Write-ConsoleStatus -Action "Set Feedback Frequency to Automatic"
			LogInfo "Setting Feedback Frequency to Automatic"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" | Out-Null
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Feedback Frequency to Automatic: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The provision to websites a locally relevant content by accessing my language list



.DESCRIPTION

Applies the Baseline behavior for the provision to websites a locally relevant content by accessing my language list.
	.PARAMETER Disable
	Do not let websites show me locally relevant content by accessing my language list

	.PARAMETER Enable
	Let websites show me locally relevant content by accessing my language list (default value)

	.EXAMPLE
	LanguageListAccess -Disable

	.EXAMPLE
	LanguageListAccess -Enable

	.NOTES
	Current user
#>
function LanguageListAccess
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
			Write-ConsoleStatus -Action "Disabling websites showing locally relevant content by accessing language list"
			LogInfo "Disabling websites showing locally relevant content by accessing language list"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable language list access for websites: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling websites to show locally relevant content by accessing language list"
			LogInfo "Enabling websites to show locally relevant content by accessing language list"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -ErrorAction SilentlyContinue))
				{
					Remove-RegistryValueSafe -Path "HKCU:\Control Panel\International\User Profile" -Name "HttpAcceptLanguageOptOut" | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable language list access for websites: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Location feature settings and scripting



.DESCRIPTION

Applies the Baseline behavior for location feature settings and scripting.
    .PARAMETER Enable
    Enable the location feature

    .PARAMETER Disable
    Disable the location feature

    .EXAMPLE
    LocationService -Enable

    .EXAMPLE
    LocationService -Disable

    .NOTES
    Current user
#>
function LocationService
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
			Write-ConsoleStatus -Action "Enabling location features"
			LogInfo "Enabling the location feature for the current user"
			try
			{
				if (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors")
				{
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" | Out-Null
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" | Out-Null
				}
				Set-Service -Name "lfsvc" -StartupType Manual -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable location features: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling location features"
			LogInfo "Disabling the location feature for the current user"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Stop-Service -Name "lfsvc" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
				Set-Service -Name "lfsvc" -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable location features: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Enable or disable the Windows Web Experience Pack (used for widgets and lock screen features)



.DESCRIPTION

Enables or disables the Windows Web Experience Pack (used for widgets and lock screen features) in GUI and headless runs.
    .PARAMETER Enable
    Install or re-register the Windows Web Experience Pack

    .PARAMETER Disable
    Uninstall the Windows Web Experience Pack

    .EXAMPLE
    LockWidgets -Enable

    .EXAMPLE
    LockWidgets -Disable

    .NOTES
    Affects the current user
#>
function LockWidgets {
    param (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = "Disable"
        )]
        [switch] $Disable,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = "Enable"
        )]
        [switch] $Enable
    )

    switch ($PSCmdlet.ParameterSetName) {
        "Enable" {
            Write-ConsoleStatus -Action "Enabling Windows Web Experience Pack"
            LogInfo "Enabling Windows Web Experience Pack"
            Invoke-SilencedProgress {
                Get-AppxPackage -AllUsers *WebExperience* -WarningAction SilentlyContinue | ForEach-Object {
                    Add-AppxPackage -Register "$($_.InstallLocation)\AppXManifest.xml" -DisableDevelopmentMode
                } | Out-Null
            }
            # Write-Host: intentional - user-visible progress indicator
            Write-Host " success!" -ForegroundColor Green
        }

        "Disable" {
            Write-ConsoleStatus -Action "Disabling Windows Web Experience Pack"
            LogInfo "Disabling Windows Web Experience Pack"
            Invoke-SilencedProgress {
                Get-AppxPackage *WebExperience* -WarningAction SilentlyContinue | Remove-AppxPackage | Out-Null
            }
            # Write-Host: intentional - user-visible progress indicator
            Write-Host " success!" -ForegroundColor Green
        }
    }
}

<#
	.SYNOPSIS
	Remote Assistance



.DESCRIPTION

Applies the Baseline behavior for remote Assistance.
	.PARAMETER Enable
	Allow remote assistance connections

	.PARAMETER Disable
	Disable remote assistance connections

	.EXAMPLE
	Set-RemoteAssistance -Enable

	.EXAMPLE
	Set-RemoteAssistance -Disable

	.NOTES
	Computer policy. Controls the fAllowToGetHelp registry setting.
#>
function Set-RemoteAssistance
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
			Write-ConsoleStatus -Action "Enabling Remote Assistance"
			LogInfo "Enabling Remote Assistance connections"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" `
					-Name "fAllowToGetHelp" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Remote Assistance: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Remote Assistance"
			LogInfo "Disabling Remote Assistance connections"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" `
					-Name "fAllowToGetHelp" `
					-Value 0 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Remote Assistance: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'ActivityHistory',
    'AdvertisingID',
    'AutoRebootOnCrash',
    'BitLockerAutoEncryption',
    'Camera',
    'ClipboardHistory',
    'CloudContentSearch',
    'DeviceSearchHistory',
    'FastStartup',
    'FeedbackFrequency',
    'InkingAndTypingPersonalization',
    'LanguageListAccess',
    'LocationService',
    'LockWidgets',
    'MapUpdates',
    'NarratorOnlineServices',
    'NarratorScriptingSupport',
    'OnlineSpeechRecognition',
    'Sensors',
    'Set-RemoteAssistance',
    'SleepTimeout',
    'UpdateDriver',
    'UpdateRestart',
    'WorkplaceJoinMessages'
)
Export-ModuleMember -Function $ExportedFunctions