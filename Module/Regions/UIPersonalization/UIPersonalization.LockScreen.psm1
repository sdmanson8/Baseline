using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Configures Windows lock screen settings.



.DESCRIPTION

Applies Baseline's Windows lock screen settings in GUI and headless runs.
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

	$isWindows11 = $false
	if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -ErrorAction SilentlyContinue)
	{
		$isWindows11 = [bool](Get-BaselineSystemPlatformInfo).IsWindows11
	}
	else
	{
		$isWindows11 = (Get-CimInstance Win32_OperatingSystem).Caption -like "*Windows 11*"
	}

	if (-not $isWindows11)
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
				Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" `
					-Name "NoLockScreen" `
					-Value 1 `
					-Type DWord
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

	$isWindows10 = $false
	if (Get-Command -Name 'Get-BaselineSystemPlatformInfo' -ErrorAction SilentlyContinue)
	{
		$isWindows10 = [bool](Get-BaselineSystemPlatformInfo).IsWindows10
	}
	else
	{
		$isWindows10 = (Get-CimInstance Win32_OperatingSystem).Caption -like "*Windows 10*"
	}

	if (-not $isWindows10)
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

<#
    .SYNOPSIS
    Runs lock screen blur.

    #>
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
			Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
				-Name "DisableAcrylicBackgroundOnLogon" `
				-Value 1 `
				-Type DWord
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

<#
    .SYNOPSIS
    Runs network from lock screen.

    #>
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
			Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
				-Name "DontDisplayNetworkSelectionUI" `
				-Value 1 `
				-Type DWord
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

<#
    .SYNOPSIS
    Runs shutdown from lock screen.

    #>
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
			Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
				-Name "ShutdownWithoutLogon" `
				-Value 1 `
				-Type DWord
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling the shutdown options on the lockscreen"
			LogInfo "Disabling the shutdown options on the lockscreen"
			Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
				-Name "ShutdownWithoutLogon" `
				-Value 0 `
				-Type DWord
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Block the camera shortcut on the Windows lock screen.

	.DESCRIPTION
	Sets HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization\NoLockScreenCamera = 1
	when -Enable is passed (i.e. enable the policy that blocks the lock-screen
	camera). -Disable removes the policy value.

	.PARAMETER Enable
	Block the lock-screen camera shortcut.

	.PARAMETER Disable
	Restore Windows default behaviour (camera shortcut allowed).

	.EXAMPLE
	LockScreenCamera -Enable

	.EXAMPLE
	LockScreenCamera -Disable

	.NOTES
	Machine-wide
#>
function LockScreenCamera
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'

	switch ($PSCmdlet.ParameterSetName)
	{
		'Enable'
		{
			Write-ConsoleStatus -Action 'Blocking the lock-screen camera shortcut'
			LogInfo 'Blocking the lock-screen camera shortcut'
			try
			{
				if (-not (Test-Path -Path $policyPath))
				{
					New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $policyPath -Name 'NoLockScreenCamera' -Value 1 -Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to block the lock-screen camera: $($_.Exception.Message)"
			}
		}
		'Disable'
		{
			Write-ConsoleStatus -Action 'Restoring lock-screen camera default'
			LogInfo 'Restoring lock-screen camera default'
			try
			{
				Remove-RegistryValueSafe -Path $policyPath -Name 'NoLockScreenCamera'
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore lock-screen camera default: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Block convenience-PIN logon for domain accounts.

	.DESCRIPTION
	Sets HKLM:\SOFTWARE\Policies\Microsoft\Windows\System\AllowDomainPINLogon = 0
	(disable convenience PIN sign-in for domain users) when -Enable is passed.
	-Disable removes the policy value, restoring the Windows default of allowing
	the policy state to be controlled by Group Policy / Hello-for-Business.

	.PARAMETER Enable
	Block convenience-PIN logon for domain users.

	.PARAMETER Disable
	Remove the policy value.

	.EXAMPLE
	BlockDomainPINLogon -Enable

	.EXAMPLE
	BlockDomainPINLogon -Disable

	.NOTES
	Machine-wide
#>
function BlockDomainPINLogon
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'

	switch ($PSCmdlet.ParameterSetName)
	{
		'Enable'
		{
			Write-ConsoleStatus -Action 'Blocking convenience-PIN logon for domain accounts'
			LogInfo 'Blocking convenience-PIN logon for domain accounts'
			try
			{
				if (-not (Test-Path -Path $policyPath))
				{
					New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $policyPath -Name 'AllowDomainPINLogon' -Value 0 -Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to block domain PIN logon: $($_.Exception.Message)"
			}
		}
		'Disable'
		{
			Write-ConsoleStatus -Action 'Restoring domain PIN logon default'
			LogInfo 'Restoring domain PIN logon default'
			try
			{
				Remove-RegistryValueSafe -Path $policyPath -Name 'AllowDomainPINLogon'
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore domain PIN logon default: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'BlockDomainPINLogon',
    'LockScreen',
    'LockScreenBlur',
    'LockScreenCamera',
    'LockScreenRS1',
    'NetworkFromLockScreen',
    'ShutdownFromLockScreen'
)
Export-ModuleMember -Function $ExportedFunctions