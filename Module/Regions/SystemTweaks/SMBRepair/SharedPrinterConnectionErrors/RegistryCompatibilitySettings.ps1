foreach ($registrySetting in @(
		@{ Path = $rpcPath; Name = "RpcUseNamedPipeProtocol"; Value = 1; Type = "DWord"; Description = "Enabled RPC named-pipe protocol for printer connections" },
		@{ Path = $rpcPath; Name = "RpcProtocols"; Value = 7; Type = "DWord"; Description = "Enabled RPC protocol bitmask 7 for printer connections" },
		@{ Path = $rpcPath; Name = "RpcListenerProtocols"; Value = 7; Type = "DWord"; Description = "Enabled RPC listener protocol bitmask 7 for printer connections" },
		@{ Path = $printControlPath; Name = "RpcAuthnLevelPrivacyEnabled"; Value = 0; Type = "DWord"; Description = "Relaxed RPC print authentication privacy" },
		@{ Path = $lsaPath; Name = "LmCompatibilityLevel"; Value = 1; Type = "DWord"; Description = "Set LAN Manager authentication level to 1" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled insecure guest auth for LanmanWorkstation" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "AllowsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled compatibility guest auth flag for LanmanWorkstation" },
		@{ Path = $lanmanWorkstationPolicyPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled insecure guest auth policy for LanmanWorkstation" },
		@{ Path = $lanmanServerParametersPath; Name = "SMB2"; Value = 1; Type = "DWord"; Description = "Enabled SMB2 server registry flag" },
		@{ Path = $lanmanServerParametersPath; Name = "AutoShareWks"; Value = 1; Type = "DWord"; Description = "Enabled workstation admin shares" },
		@{ Path = $dnsClientPolicyPath; Name = "EnableMulticast"; Value = 1; Type = "DWord"; Description = "Enabled LLMNR multicast name resolution" },
		@{ Path = $printersPolicyPath; Name = "PruningInterval"; Value = 0xFFFFFFFF; Type = "DWord"; Description = "Disabled printer pruning" },
		@{ Path = $pointAndPrintPath; Name = "Restricted"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print restrictions" },
		@{ Path = $pointAndPrintPath; Name = "TrustedServers"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print trusted-server restrictions" },
		@{ Path = $pointAndPrintPath; Name = "InForest"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print forest restrictions" },
		@{ Path = $pointAndPrintPath; Name = "NoWarningNoElevationOnInstall"; Value = 1; Type = "DWord"; Description = "Allowed printer installs without warning or elevation prompts" },
		@{ Path = $pointAndPrintPath; Name = "UpdatePromptSettings"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print update prompts" },
		@{ Path = $pointAndPrintPath; Name = "RestrictDriverInstallationToAdministrators"; Value = 0; Type = "DWord"; Description = "Allowed printer drivers to install without admin-only restrictions" }
	))
	{
		try
		{
			Set-SystemTweaksRegistryValue -Path $registrySetting.Path -Name $registrySetting.Name -Value $registrySetting.Value -Type $registrySetting.Type
			LogInfo $registrySetting.Description
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to set $($registrySetting.Name) at $($registrySetting.Path): $($_.Exception.Message)"
		}
	}

	try
	{
		if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue)
		{
			Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop | Out-Null
			LogInfo "SMB2 enabled via Set-SmbServerConfiguration"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable SMB2 via Set-SmbServerConfiguration: $($_.Exception.Message)"
	}

	try
	{
		if (Get-Command Set-SmbClientConfiguration -ErrorAction SilentlyContinue)
		{
			Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction Stop | Out-Null
			LogInfo "Enabled SMB client guest logons"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable SMB client guest logons: $($_.Exception.Message)"
	}

	try
	{
		if ((Get-Command Get-NetConnectionProfile -ErrorAction SilentlyContinue) -and (Get-Command Set-NetConnectionProfile -ErrorAction SilentlyContinue))
		{
			Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
				$profileAlias = $_.InterfaceAlias
				$profileCategory = $_.NetworkCategory
				LogInfo "Adapter: '$profileAlias' -> $profileCategory"

				if ($profileCategory -eq "Public")
				{
					Set-NetConnectionProfile -InterfaceAlias $profileAlias -NetworkCategory Private -ErrorAction Stop
					LogInfo "Changed '$profileAlias' Public -> Private"
				}
				else
				{
					LogInfo "'$profileAlias' already $profileCategory"
				}
			}
		}
		else
		{
			LogInfo "Get-NetConnectionProfile/Set-NetConnectionProfile not available on this system"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not check or update network profile: $($_.Exception.Message)"
	}

	try
	{
		if ((Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) -and (Get-Command Set-NetFirewallRule -ErrorAction SilentlyContinue))
		{
			$firewallRules = @(
				"@FirewallAPI.dll,-32752",
				"@FirewallAPI.dll,-28502"
			)

			$firewallProfiles = @(
				Get-NetConnectionProfile -ErrorAction SilentlyContinue |
					Select-Object -ExpandProperty NetworkCategory -Unique |
					ForEach-Object {
						switch ($_)
						{
							"Private" { "Private" }
							"DomainAuthenticated" { "Domain" }
							"Public" { "Public" }
						}
					}
			) | Where-Object { $_ } | Select-Object -Unique

			if (-not $firewallProfiles)
			{
				$firewallProfiles = @("Private", "Domain")
			}

			Set-NetFirewallRule -Group $firewallRules -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null
			Get-NetFirewallRule -Name FPS-SMB-In-TCP -ErrorAction SilentlyContinue |
				Set-NetFirewallRule -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null

			LogInfo "Enabled file and printer sharing firewall rules for profiles: $($firewallProfiles -join ', ')"
		}
		else
		{
			$netshPath = Join-Path $env:SystemRoot 'System32\netsh.exe'
			$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @('advfirewall', 'firewall', 'set', 'rule', 'group=File and Printer Sharing', 'new', 'enable=Yes') -TimeoutSeconds 120 -AllowedExitCodes @(0)
			$null = Invoke-BaselineProcess -FilePath $netshPath -ArgumentList @('advfirewall', 'firewall', 'set', 'rule', 'group=Network Discovery', 'new', 'enable=Yes') -TimeoutSeconds 120 -AllowedExitCodes @(0)
			LogInfo "File and printer sharing firewall rules enabled via netsh"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable file and printer sharing firewall rules: $($_.Exception.Message)"
	}

	try
	{
		if (Get-Command Get-Service -ErrorAction SilentlyContinue)
		{
			$netServices = @(
				"fdPHost",
				"FDResPub",
				"FDResSvc",
				"lmhosts",
				"SSDPSRV",
				"upnphost",
				"LanmanServer",
				"LanmanWorkstation"
			)

			foreach ($serviceName in $netServices)
			{
				$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
				if ($service)
				{
					$wasRunning = ($service.Status -eq "Running")
					Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
					if (-not $wasRunning)
					{
						Start-Service -Name $serviceName -ErrorAction SilentlyContinue
					}
					LogInfo "Service $serviceName - Automatic + $(if ($wasRunning) { 'Already running' } else { 'Started' })"
				}
				else
				{
					LogInfo "Service $serviceName not present on this OS"
				}
			}
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not configure network discovery services: $($_.Exception.Message)"
	}
