<#
	.SYNOPSIS
	Enable or disable Block Razer Software Installs

	.PARAMETER Enable
	Enable Block Razer Software Installs

	.PARAMETER Disable
	Disable Block Razer Software Installs (default value)

	.EXAMPLE
	RazerBlock -Enable

	.EXAMPLE
	RazerBlock -Disable

	.NOTES
	Current user

	CAUTION:
	Blocking Razer software installation may:
	- Prevent Razer Synapse from installing or updating
	- Disable RGB, macro, or device profile functionality
	- Stop firmware updates for Razer devices
	- Cause certain Razer peripherals to function with limited features

	Use only if you understand the implications.
#>
function RazerBlock
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$RazerPath = "C:\Windows\Installer\Razer"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Razer Software Block"
			LogInfo "Enabling Razer Software Block"
			try
			{
				# Registry changes
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				LogInfo "Set DriverSearching SearchOrderConfig to 0"
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" -Name "DisableCoInstallers" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				LogInfo "Set DisableCoInstallers to 1"

				# Block Razer installer directory
				if (Test-Path $RazerPath)
				{
					Remove-Item "$RazerPath\*" -Recurse -Force -ErrorAction Stop | Out-Null
					LogInfo "Cleared Razer installer directory"
				}
				else
				{
					New-Item -Path $RazerPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
					LogInfo "Created Razer installer directory"
				}

				icacls $RazerPath /deny "Everyone:(W)" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "icacls returned exit code $LASTEXITCODE while applying deny permissions to $RazerPath"
				}
				LogInfo "Set deny write permission on Razer directory"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to enable Razer Software Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Razer Software Block"
			LogInfo "Disabling Razer Software Block"
			try
			{
				# Restore registry values
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				LogInfo "Restored DriverSearching SearchOrderConfig to 1"
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" -Name "DisableCoInstallers" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				LogInfo "Restored DisableCoInstallers to 0"

				# Remove directory deny permission
				icacls $RazerPath /remove:d Everyone 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "icacls returned exit code $LASTEXITCODE while removing deny permissions from $RazerPath"
				}
				LogInfo "Removed deny write permission from Razer directory"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to disable Razer Software Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable S3 Sleep

.PARAMETER Enable
Enable S3 Sleep

.PARAMETER Disable
Disable S3 Sleep (default value)

.EXAMPLE
S3Sleep -Enable

.EXAMPLE
S3Sleep -Disable

.NOTES
Current user
#>
function S3Sleep
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
			Write-ConsoleStatus -Action "Enabling S3 Sleep"
			LogInfo "Enabling S3 Sleep"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable S3 Sleep: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling S3 Sleep"
			LogInfo "Disabling S3 Sleep"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable S3 Sleep: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable recommended Windows service startup configuration

.PARAMETER Enable
Apply recommended startup types to Windows services

.PARAMETER Disable
Restore Windows services to their original startup types (default value)

.EXAMPLE
ServicesManual -Enable

.EXAMPLE
ServicesManual -Disable

.NOTES
Current user
#>
function ServicesManual
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

	$services = @(
		@{ Name = "ALG";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppMgmt";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppReadiness";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppVClient";                 StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "Appinfo";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AssignedAccessManagerSvc";   StartupType = "Disabled";              OriginalType = "Manual" }
		@{ Name = "AudioEndpointBuilder";       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "AudioSrv";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "AxInstSV";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BDESVC";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BITS";                       StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "BTAGService";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BthAvctpSvc";                StartupType = "Automatic";             OriginalType = "Manual" }
		@{ Name = "CDPSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "COMSysApp";                  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "CertPropSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "CryptSvc";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "CscService";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DPS";                        StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DevQueryBroker";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DeviceAssociationService";   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DeviceInstall";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Dhcp";                       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DiagTrack";                  StartupType = "Disabled";              OriginalType = "Automatic" }
		@{ Name = "DialogBlockingService";      StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "DispBrokerDesktopSvc";       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DisplayEnhancementService";  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EFS";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EapHost";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EventLog";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "EventSystem";                StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "FDResPub";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "FontCache";                  StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "FrameServer";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "FrameServerMonitor";         StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "GraphicsPerfSvc";            StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "HvHost";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "IKEEXT";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "InstallService";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "InventorySvc";               StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "IpxlatCfgSvc";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "KeyIso";                     StartupType = "Automatic";             OriginalType = "Manual" }
		@{ Name = "KtmRm";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "LanmanServer";               StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "LanmanWorkstation";          StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "LicenseManager";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "LxpSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MSDTC";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MSiSCSI";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MapsBroker";                 StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "McpManagementService";       StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MicrosoftEdgeElevationService"; StartupType = "Manual";             OriginalType = "Manual" }
		@{ Name = "NaturalAuthentication";      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcaSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcbService";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcdAutoSetup";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NetSetupSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NetTcpPortSharing";          StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "Netman";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NlaSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PcaSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "PeerDistSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PerfHost";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PhoneSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PlugPlay";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PolicyAgent";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Power";                      StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "PrintNotify";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "ProfSvc";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "PushToInstall";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "QWAVE";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RasAuto";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RasMan";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RemoteAccess";               StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "RemoteRegistry";             StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "RetailDemo";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RmSvc";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RpcLocator";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SCPolicySvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SCardSvr";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SDRSVC";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SEMgrSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SENS";                       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SNMPTRAP";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SSDPSRV";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SamSs";                      StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "ScDeviceEnum";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensorDataService";          StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensorService";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensrSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SessionEnv";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SharedAccess";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "ShellHWDetection";           StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SmsRouter";                  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Spooler";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SstpSvc";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "StiSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "StorSvc";                    StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "SysMain";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TapiSrv";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TermService";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Themes";                     StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TieringEngineService";       StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TokenBroker";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TrkWks";                     StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TroubleshootingSvc";         StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TrustedInstaller";           StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "UevAgentService";            StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "UmRdpService";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "UserManager";                StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "UsoSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "VSS";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "VaultSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "W32Time";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WEPHOSTSVC";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WFDSConMgrSvc";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WMPNetworkSvc";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WManSvc";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WPDBusEnum";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WSAIFabricSvc";              StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "WSearch";                    StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "WalletService";              StartupType = "Manual";                OriginalType = "Manual" }
	)

	Write-ConsoleStatus -Action "Configuring Windows services"
	LogInfo "Configuring Windows services"

	foreach ($svc in $services)
	{
		$Name = $svc.Name

		if ($Enable)
		{
			$TargetType = $svc.StartupType
			LogInfo "Setting service $Name to $TargetType"
		}
		elseif ($Disable)
		{
			$TargetType = $svc.OriginalType
			LogInfo "Restoring service $Name to $TargetType"
		}

		try
		{
			$service = Get-Service -Name $Name -ErrorAction Stop

			# Handle AutomaticDelayedStart for Windows PowerShell < 7
			if (($PSVersionTable.PSVersion.Major -lt 7) -and
				($TargetType -eq "AutomaticDelayedStart"))
			{
				sc.exe config $Name start= delayed-auto 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "sc.exe returned exit code $LASTEXITCODE while configuring service $Name"
				}
				LogInfo "Service $Name configured with delayed auto start"
			}
			else
			{
				$service | Set-Service -StartupType $TargetType -ErrorAction Stop | Out-Null
				LogInfo "Service $Name configured successfully"
			}
		}
		catch
		{
			if (
				$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*" -or
				$_.Exception.Message -like "*Cannot find any service with service name*"
			)
			{
				LogWarning "Service $Name was not found"
			}
			else
			{
				LogError "Failed to set service $Name : $($_.Exception.Message)"
			}
		}
	}

	LogInfo "Completed service configuration"
	Write-ConsoleStatus -Status success
}

<#
.SYNOPSIS
Enable or disable Teredo

.PARAMETER Enable
Enable Teredo (default value)

.PARAMETER Disable
Disable Teredo

.EXAMPLE
Teredo -Enable

.EXAMPLE
Teredo -Disable

.NOTES
Current user

.CAUTION
Teredo is an IPv6 tunneling protocol used for NAT traversal.
Disabling it may reduce network latency for some applications.
However, some games and peer-to-peer applications rely on Teredo for connectivity.
Xbox Live and certain multiplayer games may not function correctly without Teredo.
#>
function Teredo
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
			Write-ConsoleStatus -Action "Enabling Teredo"
			LogInfo "Enabling Teredo"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				netsh interface teredo set state default 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "netsh returned exit code $LASTEXITCODE" }
				LogInfo "Teredo enabled and set to default state"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Teredo: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Teredo"
			LogInfo "Disabling Teredo"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				netsh interface teredo set state disabled 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "netsh returned exit code $LASTEXITCODE" }
				LogInfo "Teredo disabled"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Teredo: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Windows Platform Binary Table (WPBT)

.PARAMETER Enable
Enable Windows Platform Binary Table (WPBT) (default value)

.PARAMETER Disable
Disable Windows Platform Binary Table (WPBT)

.EXAMPLE
WPBT -Enable

.EXAMPLE
WPBT -Disable

.NOTES
Current user
#>
function WPBT
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
			Write-ConsoleStatus -Action "Enabling Windows Platform Binary Table (WPBT)"
			LogInfo "Enabling Windows Platform Binary Table (WPBT)"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable WPBT: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Platform Binary Table (WPBT)"
			LogInfo "Disabling Windows Platform Binary Table (WPBT)"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable WPBT: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
