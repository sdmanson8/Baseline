using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Gaming

<#
	.SYNOPSIS
	Hardware-accelerated GPU scheduling

	.PARAMETER Enable
	Enable hardware-accelerated GPU scheduling

	.PARAMETER Disable
	Disable hardware-accelerated GPU scheduling (default value)

	.EXAMPLE
	GPUScheduling -Enable

	.EXAMPLE
	GPUScheduling -Disable

	.NOTES
	Only with a dedicated GPU and WDDM verion is 2.7 or higher. Restart needed

	.NOTES
	Current user
#>
function GPUScheduling
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
			Write-ConsoleStatus -Action "Enabling hardware-accelerated GPU scheduling"
			LogInfo "Enabling hardware-accelerated GPU scheduling"
			# Determining whether PC has an external graphics card
			$AdapterDACType = Get-CimInstance -ClassName CIM_VideoController | Where-Object -FilterScript {($_.AdapterDACType -ne "Internal") -and ($null -ne $_.AdapterDACType)}
			# Determining whether an OS is not installed on a virtual machine
			$ComputerSystemModel = (Get-CimInstance -ClassName CIM_ComputerSystem).Model -notmatch "Virtual"
			# Checking whether a WDDM verion is 2.7 or higher
			$WddmVersion_Min = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\FeatureSetUsage", "WddmVersion_Min", $null)

			if ($AdapterDACType -and ($ComputerSystemModel -notmatch "Virtual") -and ($WddmVersion_Min -ge 2700))
			{
				try
				{
					New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers -Name HwSchMode -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch
				{
					Write-ConsoleStatus -Status failed
					LogError "Failed to enable hardware-accelerated GPU scheduling: $($_.Exception.Message)"
				}
			}
			else
			{
				Write-ConsoleStatus -Status success
				LogWarning "Hardware-accelerated GPU scheduling is not supported on this system. Skipping."
			}
		}
		"Disable"
		{
			try
			{
				Write-ConsoleStatus -Action "Disabling hardware-accelerated GPU scheduling"
				LogInfo "Disabling hardware-accelerated GPU scheduling"
				New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers -Name HwSchMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable hardware-accelerated GPU scheduling: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Game Bar

	.PARAMETER Disable
	Disable Xbox Game Bar

	.PARAMETER Enable
	Enable Xbox Game Bar (default value)

	.EXAMPLE
	XboxGameBar -Disable

	.EXAMPLE
	XboxGameBar -Enable

	.NOTES
	To prevent popping up the "You'll need a new app to open this ms-gamingoverlay" warning, you need to disable the Xbox Game Bar app, even if you uninstalled it before

	.NOTES
	Current user
#>
function XboxGameBar
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
				$GameDvrPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
				$GameConfigStorePath = "HKCU:\System\GameConfigStore"
				Write-ConsoleStatus -Action "Disabling Xbox Game Bar"
				LogInfo "Disabling Xbox Game Bar"
				if (-not (Test-Path -Path $GameDvrPath))
				{
					New-Item -Path $GameDvrPath -Force -ErrorAction Stop | Out-Null
				}
				if (-not (Test-Path -Path $GameConfigStorePath))
				{
					New-Item -Path $GameConfigStorePath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameDvrPath -Name AppCaptureEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameConfigStorePath -Name GameDVR_Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Xbox Game Bar: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			try
			{
				$GameDvrPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
				$GameConfigStorePath = "HKCU:\System\GameConfigStore"
				Write-ConsoleStatus -Action "Enabling Xbox Game Bar"
				LogInfo "Enabling Xbox Game Bar"
				if (-not (Test-Path -Path $GameDvrPath))
				{
					New-Item -Path $GameDvrPath -Force -ErrorAction Stop | Out-Null
				}
				if (-not (Test-Path -Path $GameConfigStorePath))
				{
					New-Item -Path $GameConfigStorePath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameDvrPath -Name AppCaptureEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameConfigStorePath -Name GameDVR_Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Xbox Game Bar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Game Bar tips

	.PARAMETER Disable
	Disable Xbox Game Bar tips

	.PARAMETER Enable
	Enable Xbox Game Bar tips

	.EXAMPLE
	XboxGameTips -Disable

	.EXAMPLE
	XboxGameTips -Enable

	.NOTES
	Current user
#>
function XboxGameTips
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

	if (-not (Get-AppxPackage -Name Microsoft.GamingApp -WarningAction SilentlyContinue))
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			try
			{
				Write-ConsoleStatus -Action "Disabling Xbox Game Bar tips"
				LogInfo "Disabling Xbox Game Bar tips"
				New-ItemProperty -Path HKCU:\Software\Microsoft\GameBar -Name ShowStartupPanel -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Xbox Game Bar tips: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			try
			{
				Write-ConsoleStatus -Action "Enabling Xbox Game Bar tips"
				LogInfo "Enabling Xbox Game Bar tips"
				New-ItemProperty -Path HKCU:\Software\Microsoft\GameBar -Name ShowStartupPanel -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Xbox Game Bar tips: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Fullscreen Optimizations

.PARAMETER Enable
Enable Fullscreen Optimizations (default value)

.PARAMETER Disable
Disable Fullscreen Optimizations

.EXAMPLE
FullscreenOptimizations -Enable

.EXAMPLE
FullscreenOptimizations -Disable

.NOTES
Current user
#>
function FullscreenOptimizations
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Fullscreen Optimizations"
			LogInfo "Enabling Fullscreen Optimizations"
			try
			{
				Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Fullscreen Optimizations: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Fullscreen Optimizations"
			LogInfo "Disabling Fullscreen Optimizations"
			try
			{
				Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Fullscreen Optimizations: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Multiplane Overlay

.PARAMETER Enable
Enable Multiplane Overlay (default value)

.PARAMETER Disable
Disable Multiplane Overlay

.EXAMPLE
MultiplaneOverlay -Enable

.EXAMPLE
MultiplaneOverlay -Disable

.NOTES
Current user
#>
function MultiplaneOverlay
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
			Write-ConsoleStatus -Action "Enabling Multiplane Overlay"
			LogInfo "Enabling Multiplane Overlay"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Multiplane Overlay: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Multiplane Overlay"
			LogInfo "Disabling Multiplane Overlay"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -Type DWord -Value 5 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Multiplane Overlay: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Game DVR / Background Recording

.PARAMETER Enable
Enable Game DVR background recording (default value)

.PARAMETER Disable
Disable Game DVR background recording

.EXAMPLE
GameDVR -Enable

.EXAMPLE
GameDVR -Disable

.NOTES
Current user — composite toggle for background capture behavior.
Separate from Xbox Game Bar (overlay UI). This controls the recording engine.
#>
function GameDVR
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$GameConfigStorePath = "HKCU:\System\GameConfigStore"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Game DVR background recording"
			LogInfo "Enabling Game DVR background recording"
			try
			{
				if (-not (Test-Path -Path $GameConfigStorePath))
				{
					New-Item -Path $GameConfigStorePath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameConfigStorePath -Name "GameDVR_Enabled" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Remove-RegistryValueSafe -Path $GameConfigStorePath -Name "GameDVR_FSEBehaviorMode" | Out-Null
				Remove-RegistryValueSafe -Path $GameConfigStorePath -Name "GameDVR_EFSEFeatureFlags" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Game DVR background recording: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Game DVR background recording"
			LogInfo "Disabling Game DVR background recording"
			try
			{
				if (-not (Test-Path -Path $GameConfigStorePath))
				{
					New-Item -Path $GameConfigStorePath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameConfigStorePath -Name "GameDVR_Enabled" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameConfigStorePath -Name "GameDVR_FSEBehaviorMode" -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameConfigStorePath -Name "GameDVR_EFSEFeatureFlags" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Game DVR background recording: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Windows Game Mode

.PARAMETER Enable
Enable Windows Game Mode (default value)

.PARAMETER Disable
Disable Windows Game Mode

.EXAMPLE
WindowsGameMode -Enable

.EXAMPLE
WindowsGameMode -Disable

.NOTES
Current user
#>
function WindowsGameMode
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$GameBarPath = "HKCU:\Software\Microsoft\GameBar"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Windows Game Mode"
			LogInfo "Enabling Windows Game Mode"
			try
			{
				if (-not (Test-Path -Path $GameBarPath))
				{
					New-Item -Path $GameBarPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameBarPath -Name "AutoGameModeEnabled" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameBarPath -Name "AllowAutoGameMode" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows Game Mode: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Game Mode"
			LogInfo "Disabling Windows Game Mode"
			try
			{
				if (-not (Test-Path -Path $GameBarPath))
				{
					New-Item -Path $GameBarPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameBarPath -Name "AutoGameModeEnabled" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path $GameBarPath -Name "AllowAutoGameMode" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Game Mode: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable mouse acceleration (Enhance Pointer Precision)

.PARAMETER Enable
Enable mouse acceleration (default value)

.PARAMETER Disable
Disable mouse acceleration

.EXAMPLE
MouseAcceleration -Enable

.EXAMPLE
MouseAcceleration -Disable

.NOTES
Current user
#>
function MouseAcceleration
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$MousePath = "HKCU:\Control Panel\Mouse"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling mouse acceleration (Enhance Pointer Precision)"
			LogInfo "Enabling mouse acceleration"
			try
			{
				Set-ItemProperty -Path $MousePath -Name "MouseSpeed" -Value "1" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path $MousePath -Name "MouseThreshold1" -Value "6" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path $MousePath -Name "MouseThreshold2" -Value "10" -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable mouse acceleration: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling mouse acceleration (Enhance Pointer Precision)"
			LogInfo "Disabling mouse acceleration"
			try
			{
				Set-ItemProperty -Path $MousePath -Name "MouseSpeed" -Value "0" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path $MousePath -Name "MouseThreshold1" -Value "0" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path $MousePath -Name "MouseThreshold2" -Value "0" -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable mouse acceleration: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Nagle's Algorithm for active network adapters

.PARAMETER Enable
Enable Nagle's Algorithm (default value, lower throughput overhead)

.PARAMETER Disable
Disable Nagle's Algorithm (lower latency for multiplayer gaming)

.EXAMPLE
NaglesAlgorithm -Enable

.EXAMPLE
NaglesAlgorithm -Disable

.NOTES
Machine-level, applies to all active TCP/IP interfaces
#>
function NaglesAlgorithm
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$InterfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"

	# Get active adapter GUIDs from connected IP-enabled interfaces
	$activeGuids = @()
	try
	{
		$activeGuids = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
			Where-Object { $_.Status -eq 'Up' } |
			ForEach-Object {
				$adapter = $_
				Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
					ForEach-Object { $adapter.InterfaceGuid }
			} | Select-Object -Unique)
	}
	catch
	{
		LogWarning "Could not enumerate active network adapters: $($_.Exception.Message)"
	}

	if ($activeGuids.Count -eq 0)
	{
		LogWarning "No active physical network adapters found. Skipping Nagle's Algorithm tweak."
		Write-ConsoleStatus -Action "Skipping Nagle's Algorithm (no active adapters)" -Status success
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Nagle's Algorithm (restoring defaults)"
			LogInfo "Enabling Nagle's Algorithm on $($activeGuids.Count) active adapter(s)"
			$failed = $false
			foreach ($guid in $activeGuids)
			{
				$adapterPath = Join-Path $InterfacesPath $guid
				if (Test-Path -Path $adapterPath)
				{
					try
					{
						Remove-RegistryValueSafe -Path $adapterPath -Name "TcpAckFrequency" | Out-Null
						Remove-RegistryValueSafe -Path $adapterPath -Name "TCPNoDelay" | Out-Null
					}
					catch
					{
						$failed = $true
						LogError "Failed to restore Nagle's Algorithm on adapter $guid`: $($_.Exception.Message)"
					}
				}
			}
			if ($failed) { Write-ConsoleStatus -Status failed } else { Write-ConsoleStatus -Status success }
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Nagle's Algorithm for lower latency"
			LogInfo "Disabling Nagle's Algorithm on $($activeGuids.Count) active adapter(s)"
			$failed = $false
			foreach ($guid in $activeGuids)
			{
				$adapterPath = Join-Path $InterfacesPath $guid
				if (Test-Path -Path $adapterPath)
				{
					try
					{
						New-ItemProperty -Path $adapterPath -Name "TcpAckFrequency" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
						New-ItemProperty -Path $adapterPath -Name "TCPNoDelay" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
					}
					catch
					{
						$failed = $true
						LogError "Failed to disable Nagle's Algorithm on adapter $guid`: $($_.Exception.Message)"
					}
				}
			}
			if ($failed) { Write-ConsoleStatus -Status failed } else { Write-ConsoleStatus -Status success }
		}
	}
}

<#
	.SYNOPSIS
	Choose an app and set the "High performance" graphics performance for it

	.EXAMPLE
	Set-AppGraphicsPerformance

	.NOTES
	Works only with a dedicated GPU

	.NOTES
	Current user
#>
function Set-AppGraphicsPerformance
{
	if (Get-CimInstance -ClassName Win32_VideoController | Where-Object -FilterScript {($_.AdapterDACType -ne "Internal") -and ($null -ne $_.AdapterDACType)})
	{
		Write-ConsoleStatus -Action "Selecting an app to set the 'High performance' graphics performance"
		LogInfo "Selecting an app to set the 'High performance' graphics performance"
		do
		{
			$Choice = Show-Menu -Menu $Browse -Default 1 -AddSkip

			switch ($Choice)
			{
				$Browse
				{
					Add-Type -AssemblyName System.Windows.Forms
					$OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
					$OpenFileDialog.Filter = "*.exe|*.exe|{0} (*.*)|*.*" -f $Localization.AllFilesFilter
					$OpenFileDialog.InitialDirectory = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
					$OpenFileDialog.Multiselect = $false

					# Force move the open file dialog to the foreground
					$Focus = New-Object -TypeName System.Windows.Forms.Form -Property @{TopMost = $true}
					$OpenFileDialog.ShowDialog($Focus)

					if ($OpenFileDialog.FileName)
					{
						if (-not (Test-Path -Path HKCU:\Software\Microsoft\DirectX\UserGpuPreferences))
						{
							New-Item -Path HKCU:\Software\Microsoft\DirectX\UserGpuPreferences -Force | Out-Null
						}
						New-ItemProperty -Path HKCU:\Software\Microsoft\DirectX\UserGpuPreferences -Name $OpenFileDialog.FileName -PropertyType String -Value "GpuPreference=2;" -Force | Out-Null
					}
				}
				$Skip
				{
					LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
				}
				$KeyboardArrows {}
			}
		}
		until ($Choice -ne $KeyboardArrows)
		Write-ConsoleStatus -Status success
	}
}

Export-ModuleMember -Function '*'
