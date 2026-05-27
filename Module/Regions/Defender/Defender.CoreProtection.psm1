<#
	.SYNOPSIS
	Configures account protection warning configuration.



.DESCRIPTION

Applies Baseline's account protection warning configuration in GUI and headless runs.
	.PARAMETER Enable
	Enable account protection warning for Microsoft accounts

	.PARAMETER Disable
	Disable account protection warning for Microsoft accounts

	.EXAMPLE
	AccountProtectionWarn -Enable

	.EXAMPLE
	AccountProtectionWarn -Disable

	.NOTES
	Current user
#>
function AccountProtectionWarn
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
			Write-ConsoleStatus -Action "Enabling account protection warning for Microsoft accounts"
			LogInfo "Enabling account protection warning for Microsoft accounts"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable account protection warnings: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling account protection warning for Microsoft accounts"
			LogInfo "Disabling account protection warning for Microsoft accounts"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows Security Health\State")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows Security Health\State" -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable account protection warnings: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Microsoft Defender SmartScreen



.DESCRIPTION

Applies the Baseline behavior for microsoft Defender SmartScreen.
	.PARAMETER Disable
	Disable apps and files checking within Microsoft Defender SmartScreen

	.PARAMETER Enable
	Enable apps and files checking within Microsoft Defender SmartScreen (default value)

	.EXAMPLE
	AppsSmartScreen -Disable

	.EXAMPLE
	AppsSmartScreen -Enable

	.NOTES
	Machine-wide
#>
function AppsSmartScreen
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
			Write-ConsoleStatus -Action "Disabling apps and files checking within Microsoft Defender SmartScreen"
			LogInfo "Disabling apps and files checking within Microsoft Defender SmartScreen"
			try
			{
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name SmartScreenEnabled -PropertyType String -Value Off -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Microsoft Defender SmartScreen for apps and files: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling apps and files checking within Microsoft Defender SmartScreen"
			LogInfo "Enabling apps and files checking within Microsoft Defender SmartScreen"
			try
			{
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name SmartScreenEnabled -PropertyType String -Value Warn -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Microsoft Defender SmartScreen for apps and files: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	Windows Defender Cloud-delivered protection configuration



.DESCRIPTION

Applies the Baseline behavior for windows Defender Cloud-delivered protection configuration.
	.PARAMETER Enable
	Enable Windows Defender cloud protection (MAPS reporting and automatic sample submission default behavior) (default value)

	.PARAMETER Disable
	Disable Windows Defender cloud protection (disable MAPS reporting and prevent automatic sample submission)

	.EXAMPLE
	DefenderCloud -Enable

	.EXAMPLE
	DefenderCloud -Disable

	.NOTES
	Current user
#>
function DefenderCloud
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
			Write-ConsoleStatus -Action "Enabling Windows Defender Cloud"
			LogInfo "Enabling Windows Defender Cloud"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpynetReporting" | Out-Null
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows Defender Cloud protection: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Defender Cloud"
			LogInfo "Disabling Windows Defender Cloud"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpynetReporting" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Defender Cloud protection: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	Sandboxing for Microsoft Defender



.DESCRIPTION

Applies the Baseline behavior for sandboxing for Microsoft Defender.
	.PARAMETER Enable
	Enable sandboxing for Microsoft Defender

	.PARAMETER Disable
	Disable sandboxing for Microsoft Defender (default value)

	.EXAMPLE
	DefenderSandbox -Enable

	.EXAMPLE
	DefenderSandbox -Disable

	.NOTES
	Machine-wide
#>
function DefenderSandbox
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

	if (-not (Test-BaselineDefenderComponentAvailable))
	{
		LogWarning ("Skipping {0}: {1}" -f (Get-TweakSkipLabel $MyInvocation), (Get-BaselineDefenderComponentUnavailableReason))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling sandboxing for Microsoft Defender"
			LogInfo "Enabling sandboxing for Microsoft Defender"
			try
			{
				& "$env:SystemRoot\System32\setx.exe" /M MP_FORCE_USE_SANDBOX 1 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "setx.exe returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sandboxing for Microsoft Defender: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sandboxing for Microsoft Defender"
			LogInfo "Disabling sandboxing for Microsoft Defender"
			try
			{
				& "$env:SystemRoot\System32\setx.exe" /M MP_FORCE_USE_SANDBOX 0 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "setx.exe returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sandboxing for Microsoft Defender: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Cap Microsoft Defender's CPU usage during scheduled scans.



.DESCRIPTION

Applies the Baseline behavior for cap Microsoft Defender's CPU usage during scheduled scans..
	.PARAMETER Enable
	Cap Defender scan CPU usage at 25% via Set-MpPreference -ScanAvgCPULoadFactor 25.

	.PARAMETER Disable
	Restore Defender's default scan CPU cap (50%) via Set-MpPreference -ScanAvgCPULoadFactor 50.

	.EXAMPLE
	DefenderScanCPULimit -Enable

	.EXAMPLE
	DefenderScanCPULimit -Disable

	.NOTES
	Machine-wide
#>
function DefenderScanCPULimit
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

	if (-not (Test-BaselineDefenderExecutionAvailable))
	{
		LogWarning ("Skipping {0}: {1}" -f (Get-TweakSkipLabel $MyInvocation), (Get-BaselineDefenderExecutionUnavailableReason))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		'Enable'
		{
			Write-ConsoleStatus -Action 'Capping Defender scheduled-scan CPU at 25%'
			LogInfo 'Capping Defender scheduled-scan CPU at 25%'
			try
			{
				Set-MpPreference -ScanAvgCPULoadFactor 25 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to cap Defender scan CPU usage: $($_.Exception.Message)"
			}
		}
		'Disable'
		{
			Write-ConsoleStatus -Action 'Restoring Defender default scan CPU cap (50%)'
			LogInfo 'Restoring Defender default scan CPU cap (50%)'
			try
			{
				Set-MpPreference -ScanAvgCPULoadFactor 50 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore Defender scan CPU cap: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Microsoft Defender signature-definition update interval.



.DESCRIPTION

Applies the Baseline behavior for microsoft Defender signature-definition update interval..
	.PARAMETER Enable
	Check for Defender signature updates every hour
	(Set-MpPreference -SignatureUpdateInterval 1).

	.PARAMETER Disable
	Restore the default signature-update interval (0 = managed by Windows Update,
	typically every 8 hours).

	.EXAMPLE
	DefenderSignatureUpdateInterval -Enable

	.EXAMPLE
	DefenderSignatureUpdateInterval -Disable

	.NOTES
	Machine-wide
#>
function DefenderSignatureUpdateInterval
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

	if (-not (Test-BaselineDefenderExecutionAvailable))
	{
		LogWarning ("Skipping {0}: {1}" -f (Get-TweakSkipLabel $MyInvocation), (Get-BaselineDefenderExecutionUnavailableReason))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		'Enable'
		{
			Write-ConsoleStatus -Action 'Checking Defender signatures hourly'
			LogInfo 'Checking Defender signatures hourly'
			try
			{
				Set-MpPreference -SignatureUpdateInterval 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Defender signature update interval: $($_.Exception.Message)"
			}
		}
		'Disable'
		{
			Write-ConsoleStatus -Action 'Restoring default Defender signature update interval'
			LogInfo 'Restoring default Defender signature update interval'
			try
			{
				Set-MpPreference -SignatureUpdateInterval 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to restore Defender signature update interval: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows Defender notification area (system tray) icon configuration



.DESCRIPTION

Applies the Baseline behavior for windows Defender notification area (system tray) icon configuration.
	.PARAMETER Enable
	Show Windows Defender (Windows Security) system tray icon (default value)

	.PARAMETER Disable
	Hide Windows Defender (Windows Security) system tray icon

	.EXAMPLE
	DefenderTrayIcon -Enable

	.EXAMPLE
	DefenderTrayIcon -Disable

	.NOTES
	Current User
#>
function DefenderTrayIcon
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
			Write-ConsoleStatus -Action "Enabling Windows Defender SysTray icon"
			LogInfo "Enabling Windows Defender SysTray icon"
			Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" | Out-Null
			If ([System.Environment]::OSVersion.Version.Build -eq 14393) {
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsDefender" -Type ExpandString -Value "`"%ProgramFiles%\Windows Defender\MSASCuiL.exe`"" | Out-Null
			} ElseIf ([System.Environment]::OSVersion.Version.Build -ge 15063 -And [System.Environment]::OSVersion.Version.Build -le 17134) {
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -Type ExpandString -Value "%ProgramFiles%\Windows Defender\MSASCuiL.exe" | Out-Null
			} ElseIf ([System.Environment]::OSVersion.Version.Build -ge 17763) {
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -Type ExpandString -Value "%windir%\system32\SecurityHealthSystray.exe" | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Defender SysTray icon"
			LogInfo "Disabling Windows Defender SysTray icon"
			If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray")) {
				New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Force | Out-Null
			}
			Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" -Type DWord -Value 1 | Out-Null
			If ([System.Environment]::OSVersion.Version.Build -eq 14393) {
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsDefender" | Out-Null
			} ElseIf ([System.Environment]::OSVersion.Version.Build -ge 15063) {
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
	}
}


<#
	.SYNOPSIS
	Dismiss the Windows Security warning about not signing in with a Microsoft account.

	.DESCRIPTION
	Sets the Windows Security Health state value that suppresses the Account
	Protection prompt about signing in with a Microsoft account.

	.EXAMPLE
	DismissMSAccount

	.NOTES
	Current user
#>
function DismissMSAccount
{
	Write-ConsoleStatus -Action "Dismissing Microsoft Defender offer in the Windows Security about signing in Microsoft account"
	LogInfo "Dismissing Microsoft Defender offer in the Windows Security about signing in Microsoft account"
	try
	{
		Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows Security Health\State" -Name AccountProtection_MicrosoftAccount_Disconnected -Type DWord -Value 1 | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to dismiss the Microsoft account warning in Windows Security: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Dismiss the Windows Security warning about Microsoft Edge SmartScreen.

	.DESCRIPTION
	Sets the Windows Security Health state value that marks the Edge SmartScreen
	warning as dismissed.

	.EXAMPLE
	DismissSmartScreenFilter

	.NOTES
	Current user
#>
function DismissSmartScreenFilter
{
	Write-ConsoleStatus -Action "Disabling the SmartScreen filter for Microsoft Edge"
	LogInfo "Disabling the SmartScreen filter for Microsoft Edge"
	try
	{
		Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows Security Health\State" -Name AppAndBrowser_EdgeSmartScreenOff -Type DWord -Value 0 | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to dismiss the Edge SmartScreen warning in Windows Security: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	DNS-over-HTTPS provider presets and custom DNS-over-HTTPS configuration



.DESCRIPTION

Applies the Baseline behavior for dNS-over-HTTPS provider presets and custom DNS-over-HTTPS configuration.
	.PARAMETER Enable
	Enable DNS-over-HTTPS with a custom known server pair

	.PARAMETER Google
	Enable DNS-over-HTTPS using Google Public DNS

	.PARAMETER Cloudflare
	Enable DNS-over-HTTPS using Cloudflare DNS

	.PARAMETER CloudflareMalware
	Enable DNS-over-HTTPS using Cloudflare Malware protection DNS

	.PARAMETER CloudflareMalwareAdult
	Enable DNS-over-HTTPS using Cloudflare Malware + Adult protection DNS

	.PARAMETER Quad9
	Enable DNS-over-HTTPS using Quad9 DNS

	.PARAMETER AdGuardAdsTrackers
	Enable DNS-over-HTTPS using AdGuard Ads + Trackers protection DNS

	.PARAMETER AdGuardAdsTrackersMalwareAdult
	Enable DNS-over-HTTPS using AdGuard Ads + Trackers + Malware + Adult protection DNS

	.PARAMETER OpenDNS
	Enable DNS-over-HTTPS using OpenDNS

	.PARAMETER Disable
	Disable DNS-over-HTTPS (default value)

	.EXAMPLE
	DNSoverHTTPS -Enable -PrimaryDNS 1.0.0.1 -SecondaryDNS 1.1.1.1

	.EXAMPLE
	DNSoverHTTPS -Google

	.EXAMPLE
	DNSoverHTTPS -Disable

	.NOTES
	Custom manual configuration can target any known DNS-over-HTTPS server in the Windows DoH registry, including IPv6 addresses.

	.NOTES
	Machine-wide
#>

function DNSoverHTTPS
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
			ParameterSetName = "Google"
		)]
		[switch]
		$Google,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Cloudflare"
		)]
		[switch]
		$Cloudflare,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "CloudflareMalware"
		)]
		[switch]
		$CloudflareMalware,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "CloudflareMalwareAdult"
		)]
		[switch]
		$CloudflareMalwareAdult,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Quad9"
		)]
		[switch]
		$Quad9,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "AdGuardAdsTrackers"
		)]
		[switch]
		$AdGuardAdsTrackers,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "AdGuardAdsTrackersMalwareAdult"
		)]
		[switch]
		$AdGuardAdsTrackersMalwareAdult,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "OpenDNS"
		)]
		[switch]
		$OpenDNS,

		[Parameter(
			Mandatory = $false,
			ParameterSetName = "Enable"
		)]
		[ValidateScript({
			$knownServers = @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers' -ErrorAction Stop | ForEach-Object { [string]$_.PSChildName })
			($knownServers -contains $_) -and ($_ -ne $SecondaryDNS)
		})]
		[string]
		$PrimaryDNS,

		[Parameter(
			Mandatory = $false,
			ParameterSetName = "Enable"
		)]
		[ValidateScript({
			$knownServers = @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers' -ErrorAction Stop | ForEach-Object { [string]$_.PSChildName })
			($knownServers -contains $_) -and ($_ -ne $PrimaryDNS)
		})]
		[string]
		$SecondaryDNS,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	$providerConfigurations = @{
		Google = [pscustomobject]@{
			DisplayName = 'Google'
			ServerAddresses = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844')
		}
		Cloudflare = [pscustomobject]@{
			DisplayName = 'Cloudflare'
			ServerAddresses = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001')
		}
		CloudflareMalware = [pscustomobject]@{
			DisplayName = 'Cloudflare (Malware)'
			ServerAddresses = @('1.1.1.2', '1.0.0.2', '2606:4700:4700::1112', '2606:4700:4700::1002')
		}
		CloudflareMalwareAdult = [pscustomobject]@{
			DisplayName = 'Cloudflare (Malware+Adult)'
			ServerAddresses = @('1.1.1.3', '1.0.0.3', '2606:4700:4700::1113', '2606:4700:4700::1003')
		}
		Quad9 = [pscustomobject]@{
			DisplayName = 'Quad9'
			ServerAddresses = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9')
		}
		AdGuardAdsTrackers = [pscustomobject]@{
			DisplayName = 'AdGuard (Ads+Trackers)'
			ServerAddresses = @('94.140.14.14', '94.140.15.15', '2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff')
		}
		AdGuardAdsTrackersMalwareAdult = [pscustomobject]@{
			DisplayName = 'AdGuard (Ads+Trackers+Malware+Adult)'
			ServerAddresses = @('94.140.14.15', '94.140.15.16', '2a10:50c0::bad1:ff', '2a10:50c0::bad2:ff')
		}
		OpenDNS = [pscustomobject]@{
			DisplayName = 'OpenDNS'
			ServerAddresses = @('208.67.222.222', '208.67.220.220', '2620:119:35::35', '2620:119:53::53')
		}
	}

	<#
	    .SYNOPSIS
	    Gets DNS over HTTPS adapter targets.

		#>

	function Get-DnsOverHttpsAdapterTargets
	{
		param ([bool]$HypervisorPresent)

		if ($HypervisorPresent)
		{
			return @(
				Get-NetRoute -AddressFamily IPv4 |
					Where-Object -FilterScript { $_.DestinationPrefix -eq '0.0.0.0/0' } |
					Get-NetAdapter
			)
		}

		return @(Get-NetAdapter -Physical)
	}

	<#
	    .SYNOPSIS
	    Gets DNS over HTTPS server configuration.

		#>

	function Get-DnsOverHttpsServerConfiguration
	{
		param ([string]$ParameterSetName)

		if ($ParameterSetName -eq 'Enable')
		{
			return [pscustomobject]@{
				DisplayName = 'custom DNS servers'
				ServerAddresses = @($PrimaryDNS, $SecondaryDNS)
			}
		}

		if ($providerConfigurations.ContainsKey($ParameterSetName))
		{
			return $providerConfigurations[$ParameterSetName]
		}

		return $null
	}

	<#
	    .SYNOPSIS
	    Sets DNS over HTTPS interface registry values.

		#>

	function Set-DnsOverHttpsInterfaceRegistryValues
	{
		param (
			[string[]]$InterfaceGuids,
			[string[]]$ServerAddresses
		)

		foreach ($InterfaceGuid in @($InterfaceGuids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
		{
			foreach ($serverAddress in @($ServerAddresses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
			{
				$serverPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$serverAddress"
				if (-not (Test-Path -Path $serverPath))
				{
					New-Item -Path $serverPath -Force -ErrorAction Stop | Out-Null
				}

				New-ItemProperty -Path $serverPath -Name DohFlags -PropertyType QWord -Value 5 -Force -ErrorAction Stop | Out-Null
			}
		}
	}

	$computerSystem = Get-CimInstance -ClassName CIM_ComputerSystem
	$interfaceGuids = @(
		Get-DnsOverHttpsAdapterTargets -HypervisorPresent ([bool]$computerSystem.HypervisorPresent) |
			ForEach-Object { $_.InterfaceGuid }
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			try
			{
				Write-ConsoleStatus -Action "Disabling DNS-over-HTTPS"
				LogInfo "Disabling DNS-over-HTTPS"

				# Configure DNS servers automatically.
				Get-DnsOverHttpsAdapterTargets -HypervisorPresent ([bool]$computerSystem.HypervisorPresent) |
					Set-DnsClientServerAddress -ResetServerAddresses -ErrorAction Stop | Out-Null

				foreach ($InterfaceGuid in @($interfaceGuids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
				{
					# Clear the static NameServer registry value so Windows fully reverts to DHCP DNS.
					Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$InterfaceGuid" -Name "NameServer" -Value "" -ErrorAction SilentlyContinue | Out-Null
					Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
				}

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable DNS-over-HTTPS: $($_.Exception.Message)"
				return
			}
		}
		default
		{
			$serverConfiguration = Get-DnsOverHttpsServerConfiguration -ParameterSetName $PSCmdlet.ParameterSetName
			if ($null -eq $serverConfiguration -or @($serverConfiguration.ServerAddresses).Count -eq 0)
			{
				throw "Unsupported DNS-over-HTTPS parameter set '$($PSCmdlet.ParameterSetName)'."
			}

			$actionLabel = if ($PSCmdlet.ParameterSetName -eq 'Enable') { 'custom DNS servers' } else { [string]$serverConfiguration.DisplayName }

			try
			{
				Write-ConsoleStatus -Action ("Enabling DNS-over-HTTPS for {0}" -f $actionLabel)
				LogInfo ("Enabling DNS-over-HTTPS for {0}" -f $actionLabel)

				$adapterTargets = @(Get-DnsOverHttpsAdapterTargets -HypervisorPresent ([bool]$computerSystem.HypervisorPresent))
				if ($adapterTargets.Count -eq 0)
				{
					throw 'No network adapters were found to configure DNS-over-HTTPS.'
				}

				$adapterTargets | Set-DnsClientServerAddress -ServerAddresses $serverConfiguration.ServerAddresses -ErrorAction Stop | Out-Null
				Set-DnsOverHttpsInterfaceRegistryValues -InterfaceGuids $interfaceGuids -ServerAddresses $serverConfiguration.ServerAddresses
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError ("Failed to configure DNS-over-HTTPS for {0}: {1}" -f $actionLabel, $_.Exception.Message)
				return
			}
		}
	}

	try
	{
		Clear-DnsClientCache -ErrorAction Stop
	}
	catch
	{
		LogWarning "Failed to clear the DNS client cache after updating DNS-over-HTTPS settings: $($_.Exception.Message)"
		Remove-HandledErrorRecord -ErrorRecord $_
	}

	try
	{
		Register-DnsClient -ErrorAction Stop
	}
	catch [Microsoft.Management.Infrastructure.CimException]
	{
		if ($_.Exception.Message -match "not covered by a more specific error code")
		{
			LogWarning "DNS client registration returned a generic error after updating DNS-over-HTTPS settings. The DNS server changes were applied, but dynamic DNS registration may require reconnecting the adapter or restarting Windows."
			Remove-HandledErrorRecord -ErrorRecord $_
		}
		else
		{
			LogError "Failed to register the DNS client after updating DNS-over-HTTPS settings: $($_.Exception.Message)"
		}
	}
	catch
	{
		LogWarning "Failed to register the DNS client after updating DNS-over-HTTPS settings: $($_.Exception.Message)"
		Remove-HandledErrorRecord -ErrorRecord $_
	}
}

<#
	.SYNOPSIS
	Blocks or allows file downloads from the internet



.DESCRIPTION

Applies the Baseline behavior for blocks or allows file downloads from the internet.
	.PARAMETER Enable
	Enable blocking of file downloads (default value)

	.PARAMETER Disable
	Disable blocking of file downloads

	.EXAMPLE
	DownloadBlocking -Enable

	.EXAMPLE
	DownloadBlocking -Disable

	.NOTES
	Current user
#>
function DownloadBlocking
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
			Write-ConsoleStatus -Action "Enabling blocking of file downloads from the internet"
			LogInfo "Enabling blocking of file downloads from the internet"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name "SaveZoneInformation" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable download blocking: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling blocking of file downloads from the internet"
			LogInfo "Disabling blocking of file downloads from the internet"
			try
			{
				If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name "SaveZoneInformation" -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable download blocking: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'AccountProtectionWarn',
    'AppsSmartScreen',
    'DefenderCloud',
    'DefenderSandbox',
    'DefenderScanCPULimit',
    'DefenderSignatureUpdateInterval',
    'DefenderTrayIcon',
    'DismissMSAccount',
    'DismissSmartScreenFilter',
    'DNSoverHTTPS',
    'DownloadBlocking'
)
Export-ModuleMember -Function $ExportedFunctions
