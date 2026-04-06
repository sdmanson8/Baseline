using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Client for Microsoft Networks configuration on all network interfaces

	.PARAMETER Enable
	Enable Client for Microsoft Networks on all installed network interfaces (default value)

	.PARAMETER Disable
	Disable Client for Microsoft Networks on all installed network interfaces

	.EXAMPLE
	MSNetClient -Enable

	.EXAMPLE
	MSNetClient -Disable

	.NOTES
	Current user
#>
function MSNetClient
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
			Write-ConsoleStatus -Action "Enabling Microsoft Network clients on all installed network interfaces"
			LogInfo "Enabling Microsoft Network clients on all installed network interfaces"
			Enable-NetAdapterBinding -Name "*" -ComponentID "ms_msclient" | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Microsoft Network clients on all installed network interfaces"
			LogInfo "Disabling Microsoft Network clients on all installed network interfaces"
			Disable-NetAdapterBinding -Name "*" -ComponentID "ms_msclient" | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Set current network profile category

	.PARAMETER Private
	Set current network profile to Private

	.PARAMETER Public
	Set current network profile to Public

	.EXAMPLE
	CurrentNetwork -Private

	.EXAMPLE
	CurrentNetwork -Public

	.NOTES
	Current user
#>
function CurrentNetwork
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Private"
		)]
		[switch]
		$Private,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Public"
		)]
		[switch]
		$Public
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Private"
		{
			Write-ConsoleStatus -Action "Setting current network profile to Private"
			LogInfo "Setting current network profile to Private"
			try
			{
				Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Failed to set network profile to Private: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
		"Public"
		{
			Write-ConsoleStatus -Action "Setting current network profile to Public"
			LogInfo "Setting current network profile to Public"
			try
			{
				Set-NetConnectionProfile -NetworkCategory Public -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Failed to set network profile to Public: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
	}
}

<#
	.SYNOPSIS
	Delivery Optimization

	.PARAMETER Disable
	Turn off Delivery Optimization

	.PARAMETER Enable
	Turn on Delivery Optimization (default value)

	.EXAMPLE
	DeliveryOptimization -Disable

	.EXAMPLE
	DeliveryOptimization -Enable

	.NOTES
	Current user
#>
function DeliveryOptimization
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
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization -Name DODownloadMode -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization -Name DODownloadMode -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Delivery Optimization"
			LogInfo "Disabling Delivery Optimization"
			try
			{
				$DeliveryOptimizationSettingsPath = "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings"
				if (-not (Test-Path -Path $DeliveryOptimizationSettingsPath))
				{
					New-Item -Path $DeliveryOptimizationSettingsPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $DeliveryOptimizationSettingsPath -Name DownloadMode -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
					if (Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction Ignore)
				{
					& {
						$temp = [Console]::Out
						[Console]::SetOut([System.IO.StreamWriter]::Null)
						try {
							Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
						} finally {
							[Console]::SetOut($temp)
						}
					} *>$null
				}
				else
				{
					LogInfo "Delete-DeliveryOptimizationCache cmdlet is not available on this OS. Skipping cache cleanup."
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Delivery Optimization: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Delivery Optimization"
			LogInfo "Enabling Delivery Optimization"
			try
			{
				New-ItemProperty -Path Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings -Name DownloadMode -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Delivery Optimization: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	SMB Server file and printer sharing configuration

	.PARAMETER Enable
	Enable SMB Server file and printer sharing

	.PARAMETER Disable
	Disable SMB Server file and printer sharing

	.EXAMPLE
	SMBServer -Enable

	.EXAMPLE
	SMBServer -Disable

	.NOTES
	Current user
	Disabling prevents file and printer sharing but allows client connections
	Do not disable if using Docker with shared drives as it uses SMB internally
#>
function SMBServer
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
			Write-ConsoleStatus -Action "Enabling SMB Server file and printer sharing"
			LogInfo "Enabling SMB Server file and printer sharing"
			Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force | Out-Null
			Enable-NetAdapterBinding -Name "*" -ComponentID "ms_server" | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling SMB Server file and printer sharing"
			LogInfo "Disabling SMB Server file and printer sharing"
			Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null
			Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force | Out-Null
			Disable-NetAdapterBinding -Name "*" -ComponentID "ms_server" | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	HomeGroup services configuration

	.PARAMETER Enable
	Enable HomeGroup services

	.PARAMETER Disable
	Disable HomeGroup services (default value)

	.EXAMPLE
	HomeGroups -Enable

	.EXAMPLE
	HomeGroups -Disable

	.NOTES
	Current user
	Not applicable since 1803
	Not applicable to Server
#>
function HomeGroups
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
    		Write-ConsoleStatus -Action "Enabling HomeGroup services"
    		LogInfo "Enabling HomeGroup services"

    		# Check if services exist before attempting to modify them
    		$listenerExists = Get-Service "HomeGroupListener" -ErrorAction SilentlyContinue
    		$providerExists = Get-Service "HomeGroupProvider" -ErrorAction SilentlyContinue

    		if ($listenerExists) {
       		 	Set-Service "HomeGroupListener" -StartupType Manual -ErrorAction SilentlyContinue 2>&1 | Out-Null
    		}

    		if ($providerExists) {
        		Set-Service "HomeGroupProvider" -StartupType Manual -ErrorAction SilentlyContinue 2>&1 | Out-Null
        		Start-Service "HomeGroupProvider" -ErrorAction SilentlyContinue 2>&1 | Out-Null
    	}
    		Write-ConsoleStatus -Status success
		}
		"Disable"
		{
    		Write-ConsoleStatus -Action "Disabling HomeGroup services"
    		LogInfo "Disabling HomeGroup services"

   	 		# Check if services exist before attempting to modify them
    		$listenerExists = Get-Service "HomeGroupListener" -ErrorAction SilentlyContinue
    		$providerExists = Get-Service "HomeGroupProvider" -ErrorAction SilentlyContinue

    		If ($listenerExists) {
        	Stop-Service "HomeGroupListener" -ErrorAction SilentlyContinue 2>&1 | Out-Null
        	Set-Service "HomeGroupListener" -StartupType Disabled -ErrorAction SilentlyContinue 2>&1 | Out-Null
    		}

    		If ($providerExists) {
        	Stop-Service "HomeGroupProvider" -ErrorAction SilentlyContinue 2>&1 | Out-Null
        	Set-Service "HomeGroupProvider" -StartupType Disabled -ErrorAction SilentlyContinue 2>&1 | Out-Null
    		}
    		Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Internet Connection Sharing (ICS) configuration, e.g., mobile hotspot

	.PARAMETER Enable
	Allow Internet Connection Sharing

	.PARAMETER Disable
	Prevent Internet Connection Sharing (default value)

	.EXAMPLE
	ConnectionSharing -Enable

	.EXAMPLE
	ConnectionSharing -Disable

	.NOTES
	Current user
#>
function ConnectionSharing
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
			Write-ConsoleStatus -Action "Enabling Internet Connection Sharing (ICS)"
			LogInfo "Enabling Internet Connection Sharing (ICS)"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name "NC_ShowSharedAccessUI" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Internet Connection Sharing (ICS)"
			LogInfo "Disabling Internet Connection Sharing (ICS)"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name "NC_ShowSharedAccessUI" -Type DWord -Value 0 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Link-Local Multicast Name Resolution (LLMNR) protocol configuration

	.PARAMETER Enable
	Enable LLMNR protocol (default value)

	.PARAMETER Disable
	Disable LLMNR protocol

	.EXAMPLE
	LLMNR -Enable

	.EXAMPLE
	LLMNR -Disable

	.NOTES
	Current user
#>
function LLMNR
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
			Write-ConsoleStatus -Action "Enabling Link-Local Multicast Name Resolution (LLMNR) protocol"
			LogInfo "Enabling Link-Local Multicast Name Resolution (LLMNR) protocol"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Link-Local Multicast Name Resolution (LLMNR) protocol"
			LogInfo "Disabling Link-Local Multicast Name Resolution (LLMNR) protocol"
			If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient")) {
				New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force | Out-Null
			}
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Type DWord -Value 0 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Network Connectivity Status Indicator (NCSI) active probe configuration

	.PARAMETER Enable
	Enable NCSI active probe (default value)

	.PARAMETER Disable
	Disable NCSI active probe to reduce certain zero-click attack exposure

	.EXAMPLE
	NCSIProbe -Enable

	.EXAMPLE
	NCSIProbe -Disable

	.NOTES
	Current user
	Disabling may reduce OS ability to detect internet connectivity
	See https://github.com/Disassembler0/Win10-Initial-Setup-Script/pull/111 for details
#>
function NCSIProbe
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
			Write-ConsoleStatus -Action "Enabling Network Connectivity Status Indicator (NCSI) active probe"
			LogInfo "Enabling Network Connectivity Status Indicator (NCSI) active probe"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -Name "NoActiveProbe" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Network Connectivity Status Indicator (NCSI) active probe"
			LogInfo "Disabling Network Connectivity Status Indicator (NCSI) active probe"
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" -Name "NoActiveProbe" -Type DWord -Value 1 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	NetBIOS over TCP/IP configuration on installed network interfaces

	.PARAMETER Enable
	Enable NetBIOS over TCP/IP on all installed network interfaces

	.PARAMETER Disable
	Disable NetBIOS over TCP/IP on all installed network interfaces

	.EXAMPLE
	NetBIOS -Enable

	.EXAMPLE
	NetBIOS -Disable

	.NOTES
	Current user
#>
function NetBIOS
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
			Write-ConsoleStatus -Action "Enabling NetBIOS over TCP/IP"
			LogInfo "Enabling NetBIOS over TCP/IP"
			Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\services\NetBT\Parameters\Interfaces\Tcpip*" -Name "NetbiosOptions" -Type DWord -Value 0 | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling NetBIOS over TCP/IP"
			LogInfo "Disabling NetBIOS over TCP/IP"
			Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\services\NetBT\Parameters\Interfaces\Tcpip*" -Name "NetbiosOptions" -Type DWord -Value 2 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Network adapters power management

	.PARAMETER Disable
	Do not allow the computer to turn off the network adapters to save power

	.PARAMETER Enable
	Allow the computer to turn off the network adapters to save power (default value)

	.EXAMPLE
	NetworkAdaptersSavePower -Disable

	.EXAMPLE
	NetworkAdaptersSavePower -Enable

	.NOTES
	It isn't recommended to turn off for laptops

	.NOTES
	Current user
#>
function NetworkAdaptersSavePower
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

	# Checking whether there's an adapter that has AllowComputerToTurnOffDevice property to manage
	$Adapters = Get-NetAdapter -Physical | Where-Object -FilterScript {$_.MacAddress} | Get-NetAdapterPowerManagement | Where-Object -FilterScript {$_.AllowComputerToTurnOffDevice -ne "Unsupported"}
	if (-not $Adapters)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	$PhysicalAdaptersStatusUp = @(Get-NetAdapter -Physical | Where-Object -FilterScript {($_.Status -eq "Up") -and $_.MacAddress})

	# Checking whether PC is currently connected to a Wi-Fi network
	# NetConnectionStatus 2 is Wi-Fi
	$InterfaceIndex = (Get-CimInstance -ClassName Win32_NetworkAdapter -Namespace root/CIMV2 | Where-Object -FilterScript {$_.NetConnectionStatus -eq 2}).InterfaceIndex
	if (Get-NetAdapter -Physical | Where-Object -FilterScript {($_.Status -eq "Up") -and ($_.PhysicalMediaType -eq "Native 802.11") -and ($_.InterfaceIndex -eq $InterfaceIndex)})
	{
		# Get currently connected Wi-Fi network SSID
		$SSID = (Get-NetConnectionProfile).Name
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'allowing the computer to turn off the network adapters to save power'"
			LogInfo "Disabling 'allowing the computer to turn off the network adapters to save power'"
			foreach ($Adapter in $Adapters)
			{
				$Adapter.AllowComputerToTurnOffDevice = "Disabled"
				$Adapter | Set-NetAdapterPowerManagement | Out-Null
				Write-ConsoleStatus -Status success
			}
		}
		"Enable"
		{
			foreach ($Adapter in $Adapters)
			{
				Write-ConsoleStatus -Action "Enabling 'allowing the computer to turn off the network adapters to save power' for adapter '$($Adapter.Name)'"
				LogInfo "Enabling 'allowing the computer to turn off the network adapters to save power' for adapter '$($Adapter.Name)'"
				$Adapter.AllowComputerToTurnOffDevice = "Enabled"
				$Adapter | Set-NetAdapterPowerManagement | Out-Null
				Write-ConsoleStatus -Status success
			}
		}
	}

	# All network adapters are turned into "Disconnected" for few seconds, so we need to wait a bit to let them up
	# Otherwise functions below will indicate that there is no the Internet connection
	if ($PhysicalAdaptersStatusUp)
	{
		# If Wi-Fi network was used
		if ($SSID)
		{
			#Write-Verbose -Message $SSID -Verbose
			# Connect to it
			netsh wlan connect name="$SSID" 2>$null | Out-Null
			if ($LASTEXITCODE -ne 0)
			{
				LogWarning "Failed to reconnect to Wi-Fi network '$SSID' after adapter changes. netsh exit code: $LASTEXITCODE"
			}
		}

		while
		(
			Get-NetAdapter -Physical -Name $PhysicalAdaptersStatusUp.Name | Where-Object -FilterScript {($_.Status -eq "Disconnected") -and $_.MacAddress} | Out-Null
		)
		{
			Start-Sleep -Seconds 2
		}
	}
}

<#
	.SYNOPSIS
	Automatic installation of network devices

	.PARAMETER Enable
	Allow automatic installation of network devices (default value)

	.PARAMETER Disable
	Prevent automatic installation of network devices

	.EXAMPLE
	NetDevicesAutoInst -Enable

	.EXAMPLE
	NetDevicesAutoInst -Disable

	.NOTES
	Current user
#>
function NetDevicesAutoInst
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
			Write-ConsoleStatus -Action "Enabling automatic installation of network devices"
			LogInfo "Enabling automatic installation of network devices"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private" -Name "AutoSetup" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling automatic installation of network devices"
			LogInfo "Disabling automatic installation of network devices"
			If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private")) {
				New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private" -Force | Out-Null
			}
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private" -Name "AutoSetup" -Type DWord -Value 0 | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Network Discovery File and Printers Sharing

	.PARAMETER Enable
	Enable "Network Discovery" and "File and Printers Sharing" for workgroup networks

	.PARAMETER Disable
	Disable "Network Discovery" and "File and Printers Sharing" for workgroup networks (default value)

	.EXAMPLE
	NetworkDiscovery -Enable

	.EXAMPLE
	NetworkDiscovery -Disable

	.NOTES
	Current user
#>
function NetworkDiscovery
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

	$FirewallRules = @(
		# File and printer sharing
		"@FirewallAPI.dll,-32752",

		# Network discovery
		"@FirewallAPI.dll,-28502"
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Network Discovery and File and Printers Sharing"
			LogInfo "Enabling Network Discovery and File and Printers Sharing"
			try
			{
				Set-NetFirewallRule -Group $FirewallRules -Profile Private -Enabled True -ErrorAction Stop | Out-Null
				Set-NetFirewallRule -Profile Private -Name FPS-SMB-In-TCP -Enabled True -ErrorAction Stop | Out-Null
				Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Failed to enable Network Discovery and File and Printers Sharing: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Network Discovery and File and Printers Sharing"
			LogInfo "Disabling Network Discovery and File and Printers Sharing"
			Set-NetFirewallRule -Group $FirewallRules -Profile Private -Enabled False | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Set network category for unidentified networks

	.PARAMETER Private
	Set unidentified networks to Private profile

	.PARAMETER Public
	Set unidentified networks to Public profile (default value)

	.EXAMPLE
	UnknownNetworks -Private

	.EXAMPLE
	UnknownNetworks -Public

	.NOTES
	Current user
#>
function UnknownNetworks
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Private"
		)]
		[switch]
		$Private,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Public"
		)]
		[switch]
		$Public
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Private"
		{
			Write-ConsoleStatus -Action "Setting unidentified networks to Private profile"
			LogInfo "Setting unidentified networks to Private profile"
			If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24")) {
				New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24" -Force | Out-Null
			}
			Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24" -Name "Category" -Type DWord -Value 1 | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Public"
		{
			Write-ConsoleStatus -Action "Setting unidentified networks to Public profile"
			LogInfo "Setting unidentified networks to Public profile"
			Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24" -Name "Category" -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	SMB 1.0 protocol configuration

	.PARAMETER Enable
	Enable SMB 1.0 protocol

	.PARAMETER Disable
	Disable SMB 1.0 protocol (default value)

	.EXAMPLE
	SMB1 -Enable

	.EXAMPLE
	SMB1 -Disable

	.NOTES
	Current user
#>
function SMB1
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
			Write-ConsoleStatus -Action "Enabling SMB 1.0 protocol"
			LogInfo "Enabling SMB 1.0 protocol"
			$null = Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction SilentlyContinue 2>&1
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling SMB 1.0 protocol"
			LogInfo "Disabling SMB 1.0 protocol"
			$null = Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue 2>&1
			Write-ConsoleStatus -Status success
		}
	}
}

Export-ModuleMember -Function '*'
