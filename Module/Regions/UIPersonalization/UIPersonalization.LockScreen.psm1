using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

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
					Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen"
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

Export-ModuleMember -Function '*'
