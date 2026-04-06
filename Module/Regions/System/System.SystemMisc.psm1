<#
	.SYNOPSIS
	Reserved storage

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
						$storagePs.Stop()
						throw 'Set-WindowsReservedStorageState timed out after 30 seconds'
					}
					$storagePs.EndInvoke($storageAr)
				}
				finally
				{
					if ($storagePs) { try { $storagePs.Dispose() } catch { $null = $_ } }
					if ($storageRs) { try { $storageRs.Close(); $storageRs.Dispose() } catch { $null = $_ } }
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
						$storagePs.Stop()
						throw 'Set-WindowsReservedStorageState timed out after 30 seconds'
					}
					$storagePs.EndInvoke($storageAr)
				}
				finally
				{
					if ($storagePs) { try { $storagePs.Dispose() } catch { $null = $_ } }
					if ($storageRs) { try { $storageRs.Close(); $storageRs.Dispose() } catch { $null = $_ } }
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
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
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
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
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

Export-ModuleMember -Function '*'
