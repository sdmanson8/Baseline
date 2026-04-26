<#
	.SYNOPSIS
	Accounts protection warning configuration

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
				Set-ItemProperty "HKCU:\Software\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
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

	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

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
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpynetReporting" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Type DWord -Value 2 -ErrorAction Stop | Out-Null
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

	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

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
	Windows Defender notification area (system tray) icon configuration

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
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsDefender" -Type ExpandString -Value "`"%ProgramFiles%\Windows Defender\MSASCuiL.exe`"" | Out-Null
			} ElseIf ([System.Environment]::OSVersion.Version.Build -ge 15063 -And [System.Environment]::OSVersion.Version.Build -le 17134) {
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -Type ExpandString -Value "%ProgramFiles%\Windows Defender\MSASCuiL.exe" | Out-Null
			} ElseIf ([System.Environment]::OSVersion.Version.Build -ge 17763) {
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -Type ExpandString -Value "%windir%\system32\SecurityHealthSystray.exe" | Out-Null
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
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" -Type DWord -Value 1 | Out-Null
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
	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	Write-ConsoleStatus -Action "Dismissing Microsoft Defender offer in the Windows Security about signing in Microsoft account"
	LogInfo "Dismissing Microsoft Defender offer in the Windows Security about signing in Microsoft account"
	try
	{
		Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows Security Health\State' -Name 'AccountProtection_MicrosoftAccount_Disconnected' -Value 1 -Type DWord | Out-Null
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
	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	Write-ConsoleStatus -Action "Disabling the SmartScreen filter for Microsoft Edge"
	LogInfo "Disabling the SmartScreen filter for Microsoft Edge"
	try
	{
		Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows Security Health\State' -Name 'AppAndBrowser_EdgeSmartScreenOff' -Value 0 -Type DWord | Out-Null
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
	DNS-over-HTTPS for IPv4

	.PARAMETER Enable
	Enable DNS-over-HTTPS for IPv4

	.PARAMETER Disable
	Disable DNS-over-HTTPS for IPv4 (default value)

	.EXAMPLE
	DNSoverHTTPS -Enable -PrimaryDNS 1.0.0.1 -SecondaryDNS 1.1.1.1

	.EXAMPLE
	DNSoverHTTPS -Disable

	.NOTES
	The valid IPv4 addresses: 1.0.0.1, 1.1.1.1, 149.112.112.112, 8.8.4.4, 8.8.8.8, 9.9.9.9

	.LINK
	https://docs.microsoft.com/en-us/windows-server/networking/dns/doh-client-support

	.LINK
	https://www.comss.ru/page.php?id=7315

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

		[Parameter(Mandatory = $false)]
		[ValidateScript({
			# Isolate IPv4 IP addresses and check whether $PrimaryDNS is not equal to $SecondaryDNS
			((@((Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers).PSChildName) | Where-Object -FilterScript {($_ -as [IPAddress]).AddressFamily -ne "InterNetworkV6"}) -contains $_) -and ($_ -ne $SecondaryDNS)
		})]
		[string]
		$PrimaryDNS,

		[Parameter(Mandatory = $false)]
		[ValidateScript({
			# Isolate IPv4 IP addresses and check whether $PrimaryDNS is not equal to $SecondaryDNS
			((@((Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers).PSChildName) | Where-Object -FilterScript {($_ -as [IPAddress]).AddressFamily -ne "InterNetworkV6"}) -contains $_) -and ($_ -ne $PrimaryDNS)
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

	# Determining whether Hyper-V is enabled
	# After enabling Hyper-V feature a virtual switch breing created, so we need to use different method to isolate the proper adapter
	if (-not (Get-CimInstance -ClassName CIM_ComputerSystem).HypervisorPresent)
	{
		$InterfaceGuids = @((Get-NetAdapter -Physical).InterfaceGuid)
	}
	else
	{
		$InterfaceGuids = @((Get-NetRoute -AddressFamily IPv4 | Where-Object -FilterScript {$_.DestinationPrefix -eq "0.0.0.0/0"} | Get-NetAdapter).InterfaceGuid)
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling DNS-over-HTTPS for IPv4"
			LogInfo "Enabling DNS-over-HTTPS for IPv4"
			# Set a primary and secondary DNS servers
			if ((Get-CimInstance -ClassName CIM_ComputerSystem).HypervisorPresent)
			{
				Get-NetRoute | Where-Object -FilterScript {$_.DestinationPrefix -eq "0.0.0.0/0"} | Get-NetAdapter | Set-DnsClientServerAddress -ServerAddresses $PrimaryDNS, $SecondaryDNS | Out-Null
			}
			else
			{
				Get-NetAdapter -Physical | Get-NetIPInterface -AddressFamily IPv4 | Set-DnsClientServerAddress -ServerAddresses $PrimaryDNS, $SecondaryDNS | Out-Null
			}

			foreach ($InterfaceGuid in $InterfaceGuids)
			{
				if (-not (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$PrimaryDNS"))
				{
					New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$PrimaryDNS" -Force | Out-Null
				}
				if (-not (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$SecondaryDNS"))
				{
					New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$SecondaryDNS" -Force | Out-Null
				}
				# Encrypted preffered, unencrypted allowed
				New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$PrimaryDNS" -Name DohFlags -PropertyType QWord -Value 5 -Force | Out-Null
				New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh\$SecondaryDNS" -Name DohFlags -PropertyType QWord -Value 5 -Force | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling DNS-over-HTTPS for IPv4"
			LogInfo "Disabling DNS-over-HTTPS for IPv4"
			# Determining whether Hyper-V is enabled
			if (-not (Get-CimInstance -ClassName CIM_ComputerSystem).HypervisorPresent)
			{
				# Configure DNS servers automatically
				Get-NetAdapter -Physical | Set-DnsClientServerAddress -ResetServerAddresses | Out-Null
			}
			else
			{
				# Configure DNS servers automatically
				Get-NetRoute | Where-Object -FilterScript {$_.DestinationPrefix -eq "0.0.0.0/0"} | Get-NetAdapter | Set-DnsClientServerAddress -ResetServerAddresses | Out-Null
			}

			foreach ($InterfaceGuid in $InterfaceGuids)
			{
				# Clear the static NameServer registry value so Windows fully reverts to DHCP DNS
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$InterfaceGuid" -Name "NameServer" -Value "" -ErrorAction SilentlyContinue | Out-Null
				Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$InterfaceGuid\DohInterfaceSettings\Doh" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
			}
			Write-ConsoleStatus -Status success
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
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name "SaveZoneInformation" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
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

Export-ModuleMember -Function '*'
