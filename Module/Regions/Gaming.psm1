using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Gaming

<#
	.SYNOPSIS
	Hardware-accelerated GPU scheduling



.DESCRIPTION

Applies the Baseline behavior for hardware-accelerated GPU scheduling.
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
			# Use the shared Test-IsVirtualMachine helper so production and tests agree.
			$IsVirtualMachine = Test-IsVirtualMachine
			# Checking whether a WDDM verion is 2.7 or higher
			$WddmVersion_Min = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\FeatureSetUsage", "WddmVersion_Min", $null)

			if ($AdapterDACType -and (-not $IsVirtualMachine) -and ($WddmVersion_Min -ge 2700))
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
	Processor scheduling preference



.DESCRIPTION

Applies the Baseline behavior for processor scheduling preference.
	.PARAMETER Programs
	Prioritize foreground programs (default value)

	.PARAMETER BackgroundServices
	Prioritize background services

	.EXAMPLE
	Win32PrioritySeparation -Programs

	.EXAMPLE
	Win32PrioritySeparation -BackgroundServices

	.NOTES
	Machine-wide
#>
function Win32PrioritySeparation
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Programs"
		)]
		[switch]
		$Programs,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "BackgroundServices"
		)]
		[switch]
		$BackgroundServices
	)

	$PriorityControlPath = "HKLM:\System\CurrentControlSet\Control\PriorityControl"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Programs"
		{
			Write-ConsoleStatus -Action "Setting processor scheduling to programs"
			LogInfo "Setting processor scheduling to programs"
			try
			{
				Set-RegistryValueSafe -Path $PriorityControlPath -Name "Win32PrioritySeparation" -Value 38 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set processor scheduling to programs: $($_.Exception.Message)"
			}
		}
		"BackgroundServices"
		{
			Write-ConsoleStatus -Action "Setting processor scheduling to background services"
			LogInfo "Setting processor scheduling to background services"
			try
			{
				Set-RegistryValueSafe -Path $PriorityControlPath -Name "Win32PrioritySeparation" -Value 24 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set processor scheduling to background services: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	System responsiveness tuning



.DESCRIPTION

Applies the Baseline behavior for system responsiveness tuning.
	.PARAMETER Enable
	Reduce background task interference by lowering system responsiveness

	.PARAMETER Disable
	Restore default system responsiveness

	.EXAMPLE
	SystemResponsiveness -Enable

	.EXAMPLE
	SystemResponsiveness -Disable

	.NOTES
	Machine-wide
#>
function SystemResponsiveness
{
	[CmdletBinding()]
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

	$SystemProfilePath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Optimizing system responsiveness for games"
			LogInfo "Optimizing system responsiveness for games"
			try
			{
				Set-RegistryValueSafe -Path $SystemProfilePath -Name "SystemResponsiveness" -Value 10 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to optimize system responsiveness for games: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default system responsiveness"
			LogInfo "Restoring default system responsiveness"
			try
			{
				Set-RegistryValueSafe -Path $SystemProfilePath -Name "SystemResponsiveness" -Value 20 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore default system responsiveness: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	CPU priority for games



.DESCRIPTION

Applies the Baseline behavior for cPU priority for games.
	.PARAMETER Enable
	Give games higher CPU priority

	.PARAMETER Disable
	Restore the default CPU priority

	.EXAMPLE
	GamingCpuPriority -Enable

	.EXAMPLE
	GamingCpuPriority -Disable

	.NOTES
	Machine-wide
#>
function GamingCpuPriority
{
	[CmdletBinding()]
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

	$GamesPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Increasing CPU priority for games"
			LogInfo "Increasing CPU priority for games"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "Priority" -Value 6 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to increase CPU priority for games: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default CPU priority for games"
			LogInfo "Restoring default CPU priority for games"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "Priority" -Value 2 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore default CPU priority for games: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Scheduling category for games



.DESCRIPTION

Applies the Baseline behavior for scheduling category for games.
	.PARAMETER Enable
	Set the game scheduling category to High

	.PARAMETER Disable
	Restore the default Medium scheduling category

	.EXAMPLE
	GamingSchedulingCategory -Enable

	.EXAMPLE
	GamingSchedulingCategory -Disable

	.NOTES
	Machine-wide
#>
function GamingSchedulingCategory
{
	[CmdletBinding()]
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

	$GamesPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Setting scheduling category for games to High"
			LogInfo "Setting scheduling category for games to High"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "Scheduling Category" -Value "High" -Type String | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set scheduling category for games to High: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default scheduling category for games"
			LogInfo "Restoring default scheduling category for games"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "Scheduling Category" -Value "Medium" -Type String | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore default scheduling category for games: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	GPU priority for games



.DESCRIPTION

Applies the Baseline behavior for gPU priority for games.
	.PARAMETER Enable
	Give games higher GPU priority

	.PARAMETER Disable
	Restore the default GPU priority

	.EXAMPLE
	GamingGpuPriority -Enable

	.EXAMPLE
	GamingGpuPriority -Disable

	.NOTES
	Machine-wide
#>
function GamingGpuPriority
{
	[CmdletBinding()]
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

	$GamesPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Increasing GPU priority for games"
			LogInfo "Increasing GPU priority for games"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "GPU Priority" -Value 8 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to increase GPU priority for games: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default GPU priority for games"
			LogInfo "Restoring default GPU priority for games"
			try
			{
				Set-RegistryValueSafe -Path $GamesPath -Name "GPU Priority" -Value 2 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore default GPU priority for games: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Game Bar



.DESCRIPTION

Applies the Baseline behavior for xbox Game Bar.
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



.DESCRIPTION

Applies the Baseline behavior for xbox Game Bar tips.
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
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\GameBar" -Name ShowStartupPanel -Type DWord -Value 0 | Out-Null
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
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\GameBar" -Name ShowStartupPanel -Type DWord -Value 1 | Out-Null
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



.DESCRIPTION

Enables or disables Fullscreen Optimizations in GUI and headless runs.
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
				Set-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 0 | Out-Null
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
				Set-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 1 | Out-Null
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



.DESCRIPTION

Enables or disables Multiplane Overlay in GUI and headless runs.
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
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -Type DWord -Value 5 -Force -ErrorAction Stop | Out-Null
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



.DESCRIPTION

Enables or disables Game DVR / Background Recording in GUI and headless runs.
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



.DESCRIPTION

Enables or disables Windows Game Mode in GUI and headless runs.
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
	DirectX flip model optimizations for windowed games



.DESCRIPTION

Applies the Baseline behavior for directX flip model optimizations for windowed games.
	.PARAMETER Enable
	Enable the DirectX flip presentation model optimizations

	.PARAMETER Disable
	Disable the DirectX flip presentation model optimizations

	.EXAMPLE
	DirectXFlipModel -Enable

	.EXAMPLE
	DirectXFlipModel -Disable

	.NOTES
	Current user
#>
function DirectXFlipModel
{
	[CmdletBinding()]
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

	$DirectXPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling DirectX flip model optimizations for windowed games"
			LogInfo "Enabling DirectX flip model optimizations for windowed games"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "SwapEffectUpgradeEnable" -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable DirectX flip model optimizations for windowed games: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling DirectX flip model optimizations for windowed games"
			LogInfo "Disabling DirectX flip model optimizations for windowed games"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "SwapEffectUpgradeEnable" -Value 0 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable DirectX flip model optimizations for windowed games: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Variable Refresh Rate optimizations



.DESCRIPTION

Applies the Baseline behavior for variable Refresh Rate optimizations.
	.PARAMETER Enable
	Enable VRR optimizations

	.PARAMETER Disable
	Disable VRR optimizations

	.EXAMPLE
	DirectXVrrOptimizations -Enable

	.EXAMPLE
	DirectXVrrOptimizations -Disable

	.NOTES
	Current user
#>
function DirectXVrrOptimizations
{
	[CmdletBinding()]
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

	$DirectXPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling VRR optimizations"
			LogInfo "Enabling VRR optimizations"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "VRROptimizeEnable" -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable VRR optimizations: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling VRR optimizations"
			LogInfo "Disabling VRR optimizations"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "VRROptimizeEnable" -Value 0 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable VRR optimizations: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Auto HDR



.DESCRIPTION

Applies the Baseline behavior for auto HDR.
	.PARAMETER Enable
	Enable Auto HDR

	.PARAMETER Disable
	Disable Auto HDR

	.EXAMPLE
	DirectXAutoHdr -Enable

	.EXAMPLE
	DirectXAutoHdr -Disable

	.NOTES
	Current user
#>
function DirectXAutoHdr
{
	[CmdletBinding()]
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

	$DirectXPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Auto HDR"
			LogInfo "Enabling Auto HDR"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "AutoHDREnable" -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Auto HDR: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Auto HDR"
			LogInfo "Disabling Auto HDR"
			try
			{
				Set-RegistryCompositeStringValue -Path $DirectXPath -Name "DirectXUserGlobalSettings" -CompositeStringKey "AutoHDREnable" -Value 0 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Auto HDR: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Legacy NVIDIA sharpening



.DESCRIPTION

Applies the Baseline behavior for legacy NVIDIA sharpening.
	.PARAMETER Enable
	Enable the legacy NVIDIA sharpening flag

	.PARAMETER Disable
	Disable the legacy NVIDIA sharpening flag

	.EXAMPLE
	NvidiaSharpening -Enable

	.EXAMPLE
	NvidiaSharpening -Disable

	.NOTES
	Machine-wide
#>
function NvidiaSharpening
{
	[CmdletBinding()]
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

	$NvidiaPath = "HKLM:\Software\NVIDIA Corporation\Global\FTS"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling legacy NVIDIA sharpening"
			LogInfo "Enabling legacy NVIDIA sharpening"
			try
			{
				Set-RegistryValueSafe -Path $NvidiaPath -Name "EnableGR535" -Value 0 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable legacy NVIDIA sharpening: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling legacy NVIDIA sharpening"
			LogInfo "Disabling legacy NVIDIA sharpening"
			try
			{
				Set-RegistryValueSafe -Path $NvidiaPath -Name "EnableGR535" -Value 1 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable legacy NVIDIA sharpening: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable mouse acceleration (Enhance Pointer Precision)



.DESCRIPTION

Enables or disables mouse acceleration (Enhance Pointer Precision) in GUI and headless runs.
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
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseSpeed" -Value "1" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseThreshold1" -Value "6" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseThreshold2" -Value "10" -Force -ErrorAction Stop | Out-Null
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
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseSpeed" -Value "0" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseThreshold1" -Value "0" -Force -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath $MousePath -Name "MouseThreshold2" -Value "0" -Force -ErrorAction Stop | Out-Null
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



.DESCRIPTION

Enables or disables Nagle's Algorithm for active network adapters in GUI and headless runs.
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
	Network throttling for multimedia traffic



.DESCRIPTION

Applies the Baseline behavior for network throttling for multimedia traffic.
	.PARAMETER Enable
	Keep Windows multimedia network throttling enabled (default value)

	.PARAMETER Disable
	Disable Windows multimedia network throttling

	.EXAMPLE
	NetworkThrottling -Enable

	.EXAMPLE
	NetworkThrottling -Disable

	.NOTES
	Machine-wide
#>
function NetworkThrottling
{
	[CmdletBinding()]
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

	$SystemProfilePath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling network throttling"
			LogInfo "Enabling network throttling"
			try
			{
				Set-RegistryValueSafe -Path $SystemProfilePath -Name "NetworkThrottlingIndex" -Value 10 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable network throttling: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling network throttling"
			LogInfo "Disabling network throttling"
			try
			{
				Set-RegistryValueSafe -Path $SystemProfilePath -Name "NetworkThrottlingIndex" -Value -1 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable network throttling: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Game Bar controller access



.DESCRIPTION

Applies the Baseline behavior for game Bar controller access.
	.PARAMETER Enable
	Allow an Xbox or compatible controller to open Game Bar with the Xbox button

	.PARAMETER Disable
	Prevent controller-triggered Game Bar opening

	.EXAMPLE
	GameBarController -Enable

	.EXAMPLE
	GameBarController -Disable

	.NOTES
	Current user
#>
function GameBarController
{
	[CmdletBinding()]
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

	$GameBarPath = "HKCU:\Software\Microsoft\GameBar"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Game Bar controller access"
			LogInfo "Enabling Game Bar controller access"
			try
			{
				if (-not (Test-Path -Path $GameBarPath))
				{
					New-Item -Path $GameBarPath -Force -ErrorAction Stop | Out-Null
				}
				Remove-RegistryValueSafe -Path $GameBarPath -Name "UseNexusForGameBarEnabled" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Game Bar controller access: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Game Bar controller access"
			LogInfo "Disabling Game Bar controller access"
			try
			{
				if (-not (Test-Path -Path $GameBarPath))
				{
					New-Item -Path $GameBarPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $GameBarPath -Name "UseNexusForGameBarEnabled" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Game Bar controller access: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Desktop composition effects



.DESCRIPTION

Applies the Baseline behavior for desktop composition effects.
	.PARAMETER Enable
	Enable desktop composition effects

	.PARAMETER Disable
	Disable desktop composition effects

	.EXAMPLE
	DesktopComposition -Enable

	.EXAMPLE
	DesktopComposition -Disable

	.NOTES
	Current user
#>
function DesktopComposition
{
	[CmdletBinding()]
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

	$DwmPath = "HKCU:\Software\Microsoft\Windows\DWM"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling desktop composition effects"
			LogInfo "Enabling desktop composition effects"
			try
			{
				Remove-RegistryValueSafe -Path $DwmPath -Name "CompositionPolicy" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable desktop composition effects: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling desktop composition effects"
			LogInfo "Disabling desktop composition effects"
			try
			{
				New-ItemProperty -Path $DwmPath -Name "CompositionPolicy" -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable desktop composition effects: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Live Auth Manager



.DESCRIPTION

Applies the Baseline behavior for xbox Live Auth Manager.
	.PARAMETER Disabled
	Disable Xbox Live Auth Manager

	.PARAMETER Manual
	Set Xbox Live Auth Manager to Manual (default value)

	.PARAMETER Automatic
	Set Xbox Live Auth Manager to Automatic

	.EXAMPLE
	XboxAuthManager -Disabled

	.EXAMPLE
	XboxAuthManager -Manual

	.EXAMPLE
	XboxAuthManager -Automatic

	.NOTES
	Machine-wide
#>

function XboxAuthManager
{
	[CmdletBinding(DefaultParameterSetName = "Manual")]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disabled"
		)]
		[switch]
		$Disabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Manual"
		)]
		[switch]
		$Manual,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatic"
		)]
		[switch]
		$Automatic
	)

	$ServiceName = "XblAuthManager"
	$DisplayName = "Xbox Live Auth Manager"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disabled"
		{
			Write-ConsoleStatus -Action "Disabling $DisplayName"
			LogInfo "Disabling $DisplayName"
			try
			{
				Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable ${DisplayName}: $($_.Exception.Message)"
			}
		}
		"Manual"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Manual"
			LogInfo "Setting $DisplayName to Manual"
			try
			{
				Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Manual: $($_.Exception.Message)"
			}
		}
		"Automatic"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Automatic"
			LogInfo "Setting $DisplayName to Automatic"
			try
			{
				Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Automatic: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Live Game Save



.DESCRIPTION

Applies the Baseline behavior for xbox Live Game Save.
	.PARAMETER Disabled
	Disable Xbox Live Game Save

	.PARAMETER Manual
	Set Xbox Live Game Save to Manual (default value)

	.PARAMETER Automatic
	Set Xbox Live Game Save to Automatic

	.EXAMPLE
	XboxGameSave -Disabled

	.EXAMPLE
	XboxGameSave -Manual

	.EXAMPLE
	XboxGameSave -Automatic

	.NOTES
	Machine-wide
#>

function XboxGameSave
{
	[CmdletBinding(DefaultParameterSetName = "Manual")]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disabled"
		)]
		[switch]
		$Disabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Manual"
		)]
		[switch]
		$Manual,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatic"
		)]
		[switch]
		$Automatic
	)

	$ServiceName = "XblGameSave"
	$DisplayName = "Xbox Live Game Save"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disabled"
		{
			Write-ConsoleStatus -Action "Disabling $DisplayName"
			LogInfo "Disabling $DisplayName"
			try
			{
				Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable ${DisplayName}: $($_.Exception.Message)"
			}
		}
		"Manual"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Manual"
			LogInfo "Setting $DisplayName to Manual"
			try
			{
				Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Manual: $($_.Exception.Message)"
			}
		}
		"Automatic"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Automatic"
			LogInfo "Setting $DisplayName to Automatic"
			try
			{
				Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Automatic: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Xbox Live Networking Service



.DESCRIPTION

Applies the Baseline behavior for xbox Live Networking Service.
	.PARAMETER Disabled
	Disable Xbox Live Networking Service

	.PARAMETER Manual
	Set Xbox Live Networking Service to Manual (default value)

	.PARAMETER Automatic
	Set Xbox Live Networking Service to Automatic

	.EXAMPLE
	XboxNetworking -Disabled

	.EXAMPLE
	XboxNetworking -Manual

	.EXAMPLE
	XboxNetworking -Automatic

	.NOTES
	Machine-wide
#>

function XboxNetworking
{
	[CmdletBinding(DefaultParameterSetName = "Manual")]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disabled"
		)]
		[switch]
		$Disabled,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Manual"
		)]
		[switch]
		$Manual,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Automatic"
		)]
		[switch]
		$Automatic
	)

	$ServiceName = "XboxNetApiSvc"
	$DisplayName = "Xbox Live Networking Service"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disabled"
		{
			Write-ConsoleStatus -Action "Disabling $DisplayName"
			LogInfo "Disabling $DisplayName"
			try
			{
				Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable ${DisplayName}: $($_.Exception.Message)"
			}
		}
		"Manual"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Manual"
			LogInfo "Setting $DisplayName to Manual"
			try
			{
				Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Manual: $($_.Exception.Message)"
			}
		}
		"Automatic"
		{
			Write-ConsoleStatus -Action "Setting $DisplayName to Automatic"
			LogInfo "Setting $DisplayName to Automatic"
			try
			{
				Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set $DisplayName to Automatic: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Set the "High performance" graphics-performance preference for an executable.

	.DESCRIPTION
	Writes `GpuPreference=2;` under
	`HKCU\Software\Microsoft\DirectX\UserGpuPreferences` keyed by the
	executable's full path. Returns `$true` on success, `$false` when the
	preference was not written (no dedicated GPU, no path supplied in
	non-interactive host, registry write failed). Skips silently on
	integrated-only graphics — the preference has no effect there.

	.PARAMETER AppPath
	Full path to the executable. When provided, the function writes the
	registry value directly with no UI. Intended for GUI / scripted callers.
	When omitted, the function falls back to the legacy interactive
		console-host menu + Win32 OpenFileDialog (preserves console-mode
	behaviour); skipped on non-interactive hosts.

	.EXAMPLE
	Set-AppGraphicsPerformance -AppPath 'C:\Games\game.exe'

	.NOTES
	Per-user (HKCU). Requires a dedicated GPU; integrated-only systems
	short-circuit before any registry write.
#>
function Set-AppGraphicsPerformance
{
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $false)]
		[string]$AppPath
	)

	$dedicatedAdapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
		Where-Object -FilterScript { ($_.AdapterDACType -ne 'Internal') -and ($null -ne $_.AdapterDACType) } |
		Select-Object -First 1
	if (-not $dedicatedAdapter)
	{
		LogInfo 'Set-AppGraphicsPerformance: skipped — no dedicated GPU detected'
		return $false
	}

	$gpuPrefPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'

	if (-not [string]::IsNullOrWhiteSpace($AppPath))
	{
		if (-not $PSCmdlet.ShouldProcess($AppPath, 'Set GpuPreference=2 (High performance)'))
		{
			return $false
		}
		try
		{
			if (-not (Test-Path -LiteralPath $gpuPrefPath))
			{
				New-Item -Path $gpuPrefPath -Force -ErrorAction Stop | Out-Null
			}
			Set-RegistryValueSafe -Path $gpuPrefPath -Name $AppPath -Value 'GpuPreference=2;' -Type String | Out-Null
			LogInfo "Set-AppGraphicsPerformance: high-performance preference set for '$AppPath'"
			return $true
		}
		catch
		{
			LogError "Set-AppGraphicsPerformance: failed to write GPU preference for '$AppPath': $($_.Exception.Message)"
			return $false
		}
	}

	if (-not (Test-InteractiveHost))
	{
		LogWarning 'Set-AppGraphicsPerformance: -AppPath was not supplied and the host is non-interactive; nothing to do'
		return $false
	}

	Write-ConsoleStatus -Action "Selecting an app to set the 'High performance' graphics performance"
	LogInfo "Selecting an app to set the 'High performance' graphics performance"
	do
	{
		$Choice = Show-Menu -Menu $Script:Browse -Default 1 -AddSkip

		switch ($Choice)
		{
			$Script:Browse
			{
				Add-Type -AssemblyName System.Windows.Forms
				$OpenFileDialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
				$OpenFileDialog.Filter = '*.exe|*.exe|All files (*.*)|*.*'
				$OpenFileDialog.InitialDirectory = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
				$OpenFileDialog.Multiselect = $false

				$null = $OpenFileDialog.ShowDialog()

				if ($OpenFileDialog.FileName)
				{
					$null = Set-AppGraphicsPerformance -AppPath $OpenFileDialog.FileName
				}
			}
			$Script:Skip
			{
				LogWarning (Get-BaselineBilingualString -Key 'Skipped' -Fallback 'Skipped {0}' -FormatArgs @((Get-TweakSkipLabel $MyInvocation)))
			}
			$Script:KeyboardArrows {}
		}
	}
	until ($Choice -ne $Script:KeyboardArrows)
	Write-ConsoleStatus -Status success
	return $true
}

<#
	.SYNOPSIS
	Manifest entry point for the per-app high-performance graphics preference.

	.DESCRIPTION
	Bare-noun wrapper used by the GUI manifest runner. The implementation
	lives in Set-AppGraphicsPerformance so console callers and tests can share
	the same registry-write path.
#>
function AppGraphicsPerformance
{
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([bool])]
	param (
		[Parameter(Mandatory = $false)]
		[string]$AppPath
	)

	if (-not [string]::IsNullOrWhiteSpace([string]$AppPath) -and -not $PSCmdlet.ShouldProcess($AppPath, 'Set per-app high-performance graphics preference'))
	{
		return $false
	}

	return (Set-AppGraphicsPerformance -AppPath $AppPath)
}
$ExportedFunctions = @(
    'AppGraphicsPerformance',
    'DesktopComposition',
    'DirectXAutoHdr',
    'DirectXFlipModel',
    'DirectXVrrOptimizations',
    'FullscreenOptimizations',
    'GameBarController',
    'GameDVR',
    'GamingCpuPriority',
    'GamingGpuPriority',
    'GamingSchedulingCategory',
    'GPUScheduling',
    'MouseAcceleration',
    'MultiplaneOverlay',
    'NaglesAlgorithm',
    'NetworkThrottling',
    'NvidiaSharpening',
    'Set-AppGraphicsPerformance',
    'SystemResponsiveness',
    'Win32PrioritySeparation',
    'WindowsGameMode',
    'XboxAuthManager',
    'XboxGameBar',
    'XboxGameSave',
    'XboxGameTips',
    'XboxNetworking'
)
Export-ModuleMember -Function $ExportedFunctions
