<#
.SYNOPSIS
Run the remaining legacy system/bootstrap optimizations.

.DESCRIPTION
Runs the old Performance Tuning system-only actions directly inside
Baseline by calling `Invoke-SystemOptimizations`.
The Advanced Startup shortcut is managed separately via
`AdvancedStartupShortcut -Enable/-Disable`.

.PARAMETER Modules
Optional subset of PerformanceTuning modules to execute.

.EXAMPLE
PerformanceTuning

.EXAMPLE
PerformanceTuning -Modules System

.NOTES
Current user
#>
function PerformanceTuning
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[ValidateSet('System')]
		[string[]]
		$Modules = @('System')
	)

	Write-ConsoleStatus -Action "Running Performance Tuning"
	LogInfo "Running Performance Tuning"

	$hadBlockingIssue = $false
	$hadWarning = $false
	$executedWork = $false

	foreach ($Module in $Modules)
	{
		switch ($Module)
		{
			'System'
			{
				$legacyCommand = Get-Command -Name 'Invoke-SystemOptimizations' -ErrorAction SilentlyContinue
				if ($legacyCommand)
				{
					try
					{
						& $legacyCommand | Out-Null
						$executedWork = $true
					}
					catch
					{
						$hadWarning = $true
						LogWarning "Legacy system optimization step reported a non-blocking issue: $($_.Exception.Message)"
					}
				}
				else
				{
					$hadWarning = $true
					LogWarning "Legacy system optimization entry point is not present in this build. Skipping that optional step."
				}

				$fallbackCommand = Get-Command -Name 'Invoke-AdditionalServiceOptimizations' -ErrorAction SilentlyContinue
				if ($fallbackCommand)
				{
					try
					{
						& $fallbackCommand
						$executedWork = $true
					}
					catch
					{
						$hadBlockingIssue = $true
						LogError "Performance Tuning fallback service optimizations failed: $($_.Exception.Message)"
					}
				}
				else
				{
					$hadWarning = $true
					LogWarning "Performance Tuning fallback service optimizations are unavailable in this build."
				}
			}
		}
	}

	if ($hadBlockingIssue)
	{
		Write-ConsoleStatus -Status failed
		return
	}

	if (-not $executedWork)
	{
		LogWarning "Performance Tuning did not apply any actionable steps on this system."
		Write-ConsoleStatus -Status warning
		return
	}

	if ($hadWarning)
	{
		Write-ConsoleStatus -Status warning
		return
	}

	Write-ConsoleStatus -Status success
}

<#
	.SYNOPSIS
	Enable or disable Adobe Network Block

	.PARAMETER Enable
	Enable Adobe Network Block

	.PARAMETER Disable
	Disable Adobe Network Block (default value)

	.EXAMPLE
	AdobeNetworkBlock -Enable

	.EXAMPLE
	AdobeNetworkBlock -Disable

	.NOTES
	Current user

	CAUTION:
	Blocking Adobe network access may:
	- Prevent license validation and activation
	- Disable Creative Cloud syncing
	- Break cloud-based features (Fonts, Libraries, AI tools, etc.)
	- Trigger subscription or account errors
	- Violate Adobe license terms depending on usage

	Use only if you understand the implications.
#>
function AdobeNetworkBlock
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$hosts = "$Env:SystemRoot\System32\drivers\etc\hosts"
	$hostsUrl = "https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Adobe Network Block"
			LogInfo "Enabling Adobe Network Block"
			try
			{
				if (Test-Path $hosts)
				{
					Copy-Item $hosts "$hosts.bak" -Force -ErrorAction Stop | Out-Null
					LogInfo "Backed up original hosts file to $hosts.bak"
				}
				Invoke-WebRequest $hostsUrl -OutFile $hosts -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop | Out-Null
				LogInfo "Downloaded and applied Adobe block list"
				ipconfig /flushdns 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "ipconfig returned exit code $LASTEXITCODE while flushing DNS"
				}
				LogInfo "Flushed DNS cache"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to enable Adobe Network Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Adobe Network Block"
			LogInfo "Disabling Adobe Network Block"
			try
			{
				if (Test-Path "$hosts.bak")
				{
					Remove-Item $hosts -Force -ErrorAction Stop | Out-Null
					Move-Item "$hosts.bak" $hosts -Force -ErrorAction Stop | Out-Null
					LogInfo "Restored original hosts file from backup"
				}
				ipconfig /flushdns 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "ipconfig returned exit code $LASTEXITCODE while flushing DNS"
				}
				LogInfo "Flushed DNS cache"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to disable Adobe Network Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Brave Debloat

.PARAMETER Enable
Enable Brave Debloat

.PARAMETER Disable
Disable Brave Debloat (default value)

.EXAMPLE
BraveDebloat -Enable

.EXAMPLE
BraveDebloat -Disable

.NOTES
Current user
#>
function BraveDebloat
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$BravePath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Brave Debloat"
			LogInfo "Enabling Brave Debloat"
			if (-not (Test-Path $BravePath))
			{
				New-Item -Path $BravePath -Force -ErrorAction SilentlyContinue | Out-Null
			}
			Set-ItemProperty -Path $BravePath -Name "BraveRewardsDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveWalletDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveVPNDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveAIChatEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveStatsPingEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			LogInfo "Brave debloat policies applied"
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Brave Debloat"
			LogInfo "Disabling Brave Debloat"
			Remove-ItemProperty -Path $BravePath -Name "BraveRewardsDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveWalletDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveVPNDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveAIChatEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveStatsPingEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			LogInfo "Brave debloat policies removed"
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Enable or disable Cross-Device Resume

.PARAMETER Enable
Enable Cross-Device Resume (default value)

.PARAMETER Disable
Disable Cross-Device Resume

.EXAMPLE
CrossDeviceResume -Enable

.EXAMPLE
CrossDeviceResume -Disable

.NOTES
Current user
#>
function CrossDeviceResume
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

	$SupportedMessage = "Cross-Device Resume is only supported on Windows 11 24H2 build 26100.7705+ or 26H1 build 28000.1575+ and newer. Skipping."
	$IsCrossDeviceResumeSupported = Test-Windows11FeatureBranchSupport -Thresholds @(
		@{ DisplayVersion = "24H2"; Build = 26100; UBR = 7705 },
		@{ DisplayVersion = "26H1"; Build = 28000; UBR = 1575 }
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Cross-Device Resume"
			LogInfo "Enabling Cross-Device Resume"

			if (-not $IsCrossDeviceResumeSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				if (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name "IsResumeAllowed" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Cross-Device Resume: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Cross-Device Resume"
			LogInfo "Disabling Cross-Device Resume"

			if (-not $IsCrossDeviceResumeSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				if (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name "IsResumeAllowed" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Cross-Device Resume: $($_.Exception.Message)"
			}
		}
	}
}


<#
.SYNOPSIS
Enable or disable Explorer Automatic Folder Discovery

.PARAMETER Enable
Enable Explorer Automatic Folder Discovery

.PARAMETER Disable
Disable Explorer Automatic Folder Discovery (default value)

.EXAMPLE
ExplorerAutoDiscovery -Enable

.EXAMPLE
ExplorerAutoDiscovery -Disable

.NOTES
Current user
#>
function ExplorerAutoDiscovery
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

	$bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
	$bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
	$allFolders = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Explorer Automatic Folder Discovery"
			LogInfo "Enabling Explorer Automatic Folder Discovery"
			try
			{
				if (Test-Path $bags)
				{
					Remove-Item -Path $bags -Recurse -Force -ErrorAction Stop | Out-Null
				}
				if (Test-Path $bagMRU)
				{
					Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction Stop | Out-Null
				}
				LogInfo "Please sign out and back in, or restart your computer to apply the changes."
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Explorer Automatic Folder Discovery: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Explorer Automatic Folder Discovery"
			LogInfo "Disabling Explorer Automatic Folder Discovery"
			try
			{
				if (Test-Path $bags)
				{
					Remove-Item -Path $bags -Recurse -Force -ErrorAction Stop | Out-Null
				}
				if (Test-Path $bagMRU)
				{
					Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction Stop | Out-Null
				}

				if (-not (Test-Path $allFolders))
				{
					New-Item -Path $allFolders -Force -ErrorAction Stop | Out-Null
				}

				Set-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" -Type String -Force -ErrorAction Stop | Out-Null
				LogInfo "Please sign out and back in, or restart your computer to apply the changes."
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Explorer Automatic Folder Discovery: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Modern Standby fix

.PARAMETER Enable
Enable Modern Standby fix (default value)

.PARAMETER Disable
Disable Modern Standby fix

.EXAMPLE
StandbyFix -Enable

.EXAMPLE
StandbyFix -Disable

.NOTES
Current user
#>
function StandbyFix
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
			Write-ConsoleStatus -Action "Enabling Modern Standby fix"
			LogInfo "Enabling Modern Standby fix"
			try
			{
				if (-not (Test-Path -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9"))
				{
					New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Name "ACSettingIndex" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Modern Standby fix: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Modern Standby fix"
			LogInfo "Disabling Modern Standby fix"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Name "ACSettingIndex" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Modern Standby fix: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
