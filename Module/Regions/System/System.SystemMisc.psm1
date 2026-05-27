<#
	.SYNOPSIS
	Configures reserved storage management.



.DESCRIPTION

Applies Baseline's reserved storage management in GUI and headless runs.
	.PARAMETER Disable
	Disable and delete reserved storage after the next update installation

	.PARAMETER Enable
	Enable reserved storage after the next update installation

	.EXAMPLE
	ReservedStorage -Disable

	.EXAMPLE
	ReservedStorage -Enable

	.NOTES
	Current user
#>

function Stop-ReservedStorageWorkerAsync
{
	param
	(
		[AllowNull()]
		$PowerShell,

		[Parameter(Mandatory = $true)]
		[string]
		$Source
	)

	if (-not $PowerShell)
	{
		return $true
	}

	try
	{
		$stopResult = $PowerShell.BeginStop($null, $null)
		if ($stopResult -and $stopResult.AsyncWaitHandle -and $stopResult.AsyncWaitHandle.WaitOne(1000))
		{
			try { $PowerShell.EndStop($stopResult) }
			catch { LogWarning ("Reserved storage cleanup ({0}) PowerShell stop finalization failed: {1}" -f $Source, $_.Exception.Message) }
			return $true
		}
	}
	catch
	{
		LogWarning ("Reserved storage cleanup ({0}) PowerShell stop request failed: {1}" -f $Source, $_.Exception.Message)
	}

	return $false
}

function Close-ReservedStorageRunspace
{
	param
	(
		[AllowNull()]
		$Runspace,

		[bool]
		$Completed,

		[Parameter(Mandatory = $true)]
		[string]
		$Source
	)

	if (-not $Runspace)
	{
		return
	}

	try
	{
		if ($Completed)
		{
			$Runspace.Close()
			$Runspace.Dispose()
		}
		else
		{
			$Runspace.CloseAsync()
		}
	}
	catch
	{
		LogWarning ("Reserved storage cleanup ({0}) runspace dispose failed: {1}" -f $Source, $_.Exception.Message)
	}
}

function ReservedStorage
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
			try
			{
				Write-ConsoleStatus -Action "Disabling reserved storage"
				LogInfo "Disabling reserved storage"
				if (-not (Get-Command -Name Set-WindowsReservedStorageState -ErrorAction Ignore))
				{
					LogWarning "Reserved storage cmdlet is not available on this OS. Skipping."
					Write-ConsoleStatus -Status success
					return
				}
				$storageRs = $null
				$storagePs = $null
				$storageCompleted = $false
				try
				{
					$storageRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
					$storageRs.Open()
					$storagePs = [System.Management.Automation.PowerShell]::Create()
					$storagePs.Runspace = $storageRs
					[void]$storagePs.AddScript('Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop -WarningAction SilentlyContinue')
					$storageAr = $storagePs.BeginInvoke()
					if (-not $storageAr.AsyncWaitHandle.WaitOne(30000))
					{
						[void](Stop-ReservedStorageWorkerAsync -PowerShell $storagePs -Source 'disable')
						throw 'Set-WindowsReservedStorageState timed out after 30 seconds'
					}
					$storageCompleted = $true
					$storagePs.EndInvoke($storageAr)
				}
				finally
				{
					if ($storagePs) { try { $storagePs.Dispose() } catch { LogWarning ("Reserved storage cleanup (disable) PowerShell dispose failed: " + $_.Exception.Message) } }
					Close-ReservedStorageRunspace -Runspace $storageRs -Completed:$storageCompleted -Source 'disable'
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				if ($_.Exception -is [System.Runtime.InteropServices.COMException] -or $_.Exception.InnerException -is [System.Runtime.InteropServices.COMException])
				{
					LogError ($Localization.ReservedStorageIsInUse -f (Get-TweakSkipLabel $MyInvocation))
				}
				else
				{
					LogError "Failed to disable reserved storage: $($_.Exception.Message)"
				}
			}
		}
		"Enable"
		{
			try
			{
				Write-ConsoleStatus -Action "Enabling reserved storage"
				LogInfo "Enabling reserved storage"
				if (-not (Get-Command -Name Set-WindowsReservedStorageState -ErrorAction Ignore))
				{
					LogWarning "Reserved storage cmdlet is not available on this OS. Skipping."
					Write-ConsoleStatus -Status success
					return
				}
				$storageRs = $null
				$storagePs = $null
				$storageCompleted = $false
				try
				{
					$storageRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
					$storageRs.Open()
					$storagePs = [System.Management.Automation.PowerShell]::Create()
					$storagePs.Runspace = $storageRs
					[void]$storagePs.AddScript('Set-WindowsReservedStorageState -State Enabled -ErrorAction Stop -WarningAction SilentlyContinue')
					$storageAr = $storagePs.BeginInvoke()
					if (-not $storageAr.AsyncWaitHandle.WaitOne(30000))
					{
						[void](Stop-ReservedStorageWorkerAsync -PowerShell $storagePs -Source 'enable')
						throw 'Set-WindowsReservedStorageState timed out after 30 seconds'
					}
					$storageCompleted = $true
					$storagePs.EndInvoke($storageAr)
				}
				finally
				{
					if ($storagePs) { try { $storagePs.Dispose() } catch { LogWarning ("Reserved storage cleanup (enable) PowerShell dispose failed: " + $_.Exception.Message) } }
					Close-ReservedStorageRunspace -Runspace $storageRs -Completed:$storageCompleted -Source 'enable'
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable reserved storage: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The shortcut to start Sticky Keys

	.PARAMETER Disable
	Turn off Sticky keys by pressing the Shift key 5 times

	.PARAMETER Enable
	Turn on Sticky keys by pressing the Shift key 5 times (default value)

	.EXAMPLE
	StickyShift -Disable

	.EXAMPLE
	StickyShift -Enable

	.NOTES
	Current user
#>

<#
	.SYNOPSIS
	Windows manages my default printer



.DESCRIPTION

Applies the Baseline behavior for windows manages my default printer.
	.PARAMETER Disable
	Do not let Windows manage my default printer

	.PARAMETER Enable
	Let Windows manage my default printer (default value)

	.EXAMPLE
	WindowsManageDefaultPrinter -Disable

	.EXAMPLE
	WindowsManageDefaultPrinter -Enable

	.NOTES
	Current user
#>
function WindowsManageDefaultPrinter
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

	Set-Policy -Scope User -Path "Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'Let Windows manage my default printer'"
			LogInfo "Disabling 'Let Windows manage my default printer'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 'Let Windows manage my default printer': $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'Let Windows manage my default printer'"
			LogInfo "Enabling 'Let Windows manage my default printer'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -Type DWord -Value 0 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 'Let Windows manage my default printer': $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Prefer IPv4 over IPv6



.DESCRIPTION

Applies the Baseline behavior for prefer IPv4 over IPv6.
	.PARAMETER Enable
	Set IPv4 as preferred over IPv6 using prefix policy table

	.PARAMETER Disable
	Disable IPv4 preference over IPv6 (restore default)

	.EXAMPLE
	Set-IPv4Preference -Enable

	.EXAMPLE
	Set-IPv4Preference -Disable

	.NOTES
	Current user. Distinct from full IPv6 disable - uses prefix policy table.
#>
function Set-IPv4Preference
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
			Write-ConsoleStatus -Action "Preferring IPv4 over IPv6"
			LogInfo "Preferring IPv4 over IPv6 using prefix policy table"
			try
			{
				& netsh.exe int ipv6 set prefix ::/0 45 "IPv4" -ErrorAction Stop
				& netsh.exe int ipv6 set prefix ::ffff:0:0/96 35 "IPv4" -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set IPv4 preference: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default IPv4/IPv6 preference"
			LogInfo "Restoring default IPv4/IPv6 preference"
			try
			{
				& netsh.exe int ipv6 set prefix ::/0 40 -ErrorAction Stop
				& netsh.exe int ipv6 set prefix ::ffff:0:0/96 35 -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore IPv4/IPv6 preference: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	UTC clock for Linux dual-boot



.DESCRIPTION

Applies the Baseline behavior for uTC clock for Linux dual-boot.
	.PARAMETER Enable
	Set system clock to UTC for Linux dual-boot compatibility

	.PARAMETER Disable
	Set system clock to local time (default Windows behavior)

	.EXAMPLE
	Set-UTCClockForLinuxDualBoot -Enable

	.EXAMPLE
	Set-UTCClockForLinuxDualBoot -Disable

	.NOTES
	Computer policy. For systems dual-booting Windows and Linux.
#>
function Set-UTCClockForLinuxDualBoot
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
			Write-ConsoleStatus -Action "Setting system clock to UTC for Linux dual-boot"
			LogInfo "Setting system clock to UTC for Linux dual-boot compatibility"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" `
					-Name "RealTimeIsUniversal" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set UTC clock: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Setting system clock to local time"
			LogInfo "Setting system clock to local time (default Windows behavior)"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" `
					-Name "RealTimeIsUniversal" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore local time clock: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Services pipe timeout



.DESCRIPTION

Applies the Baseline behavior for services pipe timeout.
	.PARAMETER Reduce
	Reduce Services pipe timeout from 60000ms to 30000ms

	.PARAMETER Restore
	Restore Services pipe timeout to default 60000ms

	.EXAMPLE
	Set-ServicesPipeTimeout -Reduce

	.EXAMPLE
	Set-ServicesPipeTimeout -Restore

	.NOTES
	Computer policy. Affects system service communication timeout.
#>
function Set-ServicesPipeTimeout
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Reduce"
		)]
		[switch]
		$Reduce,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Restore"
		)]
		[switch]
		$Restore
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Reduce"
		{
			Write-ConsoleStatus -Action "Reducing Services pipe timeout to 30000ms"
			LogInfo "Reducing Services pipe timeout from 60000ms to 30000ms"
			try
			{
				Set-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
					-Name "ServicesPipeTimeout" `
					-Value 30000 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to reduce Services pipe timeout: $($_.Exception.Message)"
			}
		}
		"Restore"
		{
			Write-ConsoleStatus -Action "Restoring Services pipe timeout to 60000ms"
			LogInfo "Restoring Services pipe timeout to default 60000ms"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
					-Name "ServicesPipeTimeout" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore Services pipe timeout: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Print Spooler service toggle



.DESCRIPTION

Applies the Baseline behavior for print Spooler service toggle.
	.PARAMETER Enable
	Enable Print Spooler service (auto-start)

	.PARAMETER Disable
	Disable Print Spooler service (manual start only)

	.EXAMPLE
	Set-PrintSpooler -Enable

	.EXAMPLE
	Set-PrintSpooler -Disable

	.NOTES
	Computer policy. Recommended to disable when not printing regularly.
#>
function Set-PrintSpooler
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
			Write-ConsoleStatus -Action "Enabling Print Spooler service"
			LogInfo "Enabling Print Spooler service with automatic start"
			try
			{
				Get-Service -Name "spooler" -ErrorAction Stop | Set-Service -StartupType Automatic -ErrorAction Stop
				Get-Service -Name "spooler" -ErrorAction Stop | Start-Service -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Print Spooler service: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Print Spooler service"
			LogInfo "Disabling Print Spooler service to manual start"
			try
			{
				Get-Service -Name "spooler" -ErrorAction Stop | Stop-Service -Force -ErrorAction Stop
				Get-Service -Name "spooler" -ErrorAction Stop | Set-Service -StartupType Manual -ErrorAction Stop
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Print Spooler service: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'ReservedStorage',
    'Set-IPv4Preference',
    'Set-PrintSpooler',
    'Set-ServicesPipeTimeout',
    'Set-UTCClockForLinuxDualBoot',
    'WindowsManageDefaultPrinter'
)
Export-ModuleMember -Function $ExportedFunctions
