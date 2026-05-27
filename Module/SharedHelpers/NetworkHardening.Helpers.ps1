# Networking surface-reduction helpers.
#
# Spec: todo.md "Networking surface reduction" --
#   IGMPLevel=0, DisableIPSourceRouting=2, EnableICMPRedirect=0,
#   TCP/IP DoS hardening (TcpMaxDataRetransmissions, KeepAliveTime,
#   PerformRouterDiscovery, EnableDeadGWDetect), RPC-over-TCP disable,
#   NetBIOS over TCP/IP disable, WinRM service stop + disable,
#   LLMNR + mDNS disable.
#
# Back-end helpers only; the manifest integration that exposes the toggles
# in OS Hardening is implemented in a separate slice.
#
#   * "Registry settings" -- a flat catalog of (path, name, type, value)
#     records that get applied via a single bulk apply / restore primitive.
#     Each setting backs its prior value up to a Baseline-owned key so the
#     restore can walk back.
#   * NetBIOS over TCP/IP -- per-adapter, since each network adapter has
#     its own NetbiosOptions value under
#     HKLM:\System\CurrentControlSet\Services\NetBT\Parameters\Interfaces.
#   * WinRM service -- service control, not registry, so it lives in its
#     own pair of functions.

function Get-BaselineNetworkHardeningRegistrySettings
{
	<#
		.SYNOPSIS
		Returns the canonical catalog of registry-only network hardening
		settings Baseline applies.

		.DESCRIPTION
		Each record carries Id, Path, Name, Type, Value, and Description so
		callers can render audit output without re-deriving the meaning.
		Order is stable so iterators get reproducible output.

		Settings:
		  * TCP/IP stack DoS hardening (Tcpip\Parameters)
		  * RPC-over-TCP / EPMap auth tightening
		  * LLMNR disable (DNSClient policy)
		  * mDNS disable (Dnscache parameters)
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param ()

	$tcpipParams = 'HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters'
	$dnsClientPolicy = 'HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient'
	$dnscacheParams = 'HKLM:\System\CurrentControlSet\Services\Dnscache\Parameters'
	$rpcPolicy = 'HKLM:\Software\Policies\Microsoft\Windows NT\Rpc'

	return @(
		[pscustomobject]@{ Id='IGMPLevel';                Path=$tcpipParams; Name='IGMPLevel';                Type='DWord'; Value=0; Description='Disable IGMP host membership reporting.' }
		[pscustomobject]@{ Id='DisableIPSourceRouting';   Path=$tcpipParams; Name='DisableIPSourceRouting';   Type='DWord'; Value=2; Description='Reject all IP source-routed packets (anti-spoofing).' }
		[pscustomobject]@{ Id='EnableICMPRedirect';       Path=$tcpipParams; Name='EnableICMPRedirect';       Type='DWord'; Value=0; Description='Ignore ICMP redirect messages (anti-MitM).' }
		[pscustomobject]@{ Id='TcpMaxDataRetransmissions';Path=$tcpipParams; Name='TcpMaxDataRetransmissions';Type='DWord'; Value=3; Description='Limit TCP retransmissions before connection abort.' }
		[pscustomobject]@{ Id='KeepAliveTime';            Path=$tcpipParams; Name='KeepAliveTime';            Type='DWord'; Value=300000; Description='Send TCP keep-alives every 5 minutes (default is 2 hours).' }
		[pscustomobject]@{ Id='PerformRouterDiscovery';   Path=$tcpipParams; Name='PerformRouterDiscovery';   Type='DWord'; Value=0; Description='Disable IRDP router discovery (anti-MitM).' }
		[pscustomobject]@{ Id='EnableDeadGWDetect';       Path=$tcpipParams; Name='EnableDeadGWDetect';       Type='DWord'; Value=0; Description='Disable dead-gateway detection (prevents unsolicited gateway switching).' }
		[pscustomobject]@{ Id='LlmnrDisable';             Path=$dnsClientPolicy; Name='EnableMulticast';      Type='DWord'; Value=0; Description='Disable LLMNR multicast name resolution.' }
		[pscustomobject]@{ Id='MdnsDisable';              Path=$dnscacheParams;  Name='EnableMDNS';           Type='DWord'; Value=0; Description='Disable mDNS multicast name resolution.' }
		[pscustomobject]@{ Id='RpcEpMapAuth';             Path=$rpcPolicy;       Name='EnableAuthEpResolution';Type='DWord'; Value=1; Description='Require RPC endpoint-mapper client authentication.' }
	)
}

function Get-BaselineNetworkHardeningBackupRoot
{
	<#
		.SYNOPSIS
		Returns the registry root where Baseline stores the original values
		of network-hardening settings so the apply can be reversed.

		.DESCRIPTION
		Defaults to `HKLM:\Software\Baseline\NetworkHardening`. Honours an
		override via `BASELINE_NETHARD_BACKUP_ROOT` so tests redirect to an
		HKCU sandbox.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_NETHARD_BACKUP_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}
	return 'HKLM:\Software\Baseline\NetworkHardening'
}

function Set-BaselineNetworkHardeningRegistrySettings
{
	<#
		.SYNOPSIS
		Applies the network-hardening registry catalog with backup.

		.DESCRIPTION
		For each setting (or the explicit subset passed via -Settings):
		  1. Read the current value (if any) from the live key.
		  2. If a Baseline backup for that Id does not yet exist, write the
		     current state into the backup so the original survives a
		     re-apply that follows accidental drift.
		  3. Write the desired value via Set-RegistryValueSafe.

		Returns one record per setting describing what changed. Honours
		-WhatIf via SupportsShouldProcess.

		.PARAMETER Settings
		Optional subset of catalog records (e.g. filtered by Id) to apply.
		Defaults to the full Get-BaselineNetworkHardeningRegistrySettings list.

		.PARAMETER BackupRoot
		Optional override for the backup registry root.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$Settings = Get-BaselineNetworkHardeningRegistrySettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		$currentValue = $null
		$currentExists = $false
		if (Test-Path -LiteralPath $setting.Path)
		{
			$item = Get-ItemProperty -LiteralPath $setting.Path -ErrorAction SilentlyContinue
			if ($item -and $item.PSObject.Properties[$setting.Name])
			{
				$currentValue = $item.PSObject.Properties[$setting.Name].Value
				$currentExists = $true
			}
		}

		$backupKey = Join-Path -Path $BackupRoot -ChildPath $setting.Id
		$backupCreated = $false
		if (-not (Test-Path -LiteralPath $backupKey))
		{
			if ($PSCmdlet.ShouldProcess($backupKey, "Snapshot original value for $($setting.Id)"))
			{
				if ($currentExists)
				{
					Set-RegistryValueSafe -Path $backupKey -Name 'Value' -Value $currentValue -Type $setting.Type | Out-Null
					Set-RegistryValueSafe -Path $backupKey -Name 'Existed' -Value 1 -Type 'DWord' | Out-Null
				}
				else
				{
					if (-not (Test-Path -LiteralPath $backupKey))
					{
						New-Item -Path $backupKey -Force | Out-Null
					}
					Set-RegistryValueSafe -Path $backupKey -Name 'Existed' -Value 0 -Type 'DWord' | Out-Null
				}
				Set-RegistryValueSafe -Path $backupKey -Name 'Path' -Value $setting.Path -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'ValueName' -Value $setting.Name -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'OriginalType' -Value $setting.Type -Type 'String' | Out-Null
				Set-RegistryValueSafe -Path $backupKey -Name 'AppliedAt' -Value ([DateTime]::UtcNow.ToString('o')) -Type 'String' | Out-Null
				$backupCreated = $true
			}
		}

		$applied = $false
		if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", "Set $($setting.Id) = $($setting.Value)"))
		{
			$applied = [bool](Set-RegistryValueSafe -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type)
		}

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Path          = $setting.Path
			Name          = $setting.Name
			DesiredValue  = $setting.Value
			PreviousValue = $currentValue
			PreviousExists= $currentExists
			BackupCreated = $backupCreated
			Applied       = $applied
		}) | Out-Null
	}

	return $results.ToArray()
}

function Restore-BaselineNetworkHardeningRegistrySettings
{
	<#
		.SYNOPSIS
		Restores the original values for previously-applied network-hardening
		settings.

		.DESCRIPTION
		For each setting (or subset), reads the backup at
		`<BackupRoot>\<Id>\Value` and writes it back to the live key. If the
		backup says the original did not exist (Existed=0), removes the live
		value instead. Removes the backup key on success so a subsequent
		apply will re-snapshot the now-restored state.

		Returns one record per setting describing the outcome.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$Settings = Get-BaselineNetworkHardeningRegistrySettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		$backupKey = Join-Path -Path $BackupRoot -ChildPath $setting.Id
		if (-not (Test-Path -LiteralPath $backupKey))
		{
			$results.Add([pscustomobject]@{
				Id         = $setting.Id
				Restored   = $false
				Skipped    = $true
				SkipReason = 'NoBackup'
			}) | Out-Null
			continue
		}

		$backupItem = Get-ItemProperty -LiteralPath $backupKey -ErrorAction SilentlyContinue
		$existed = 0
		if ($backupItem -and $backupItem.PSObject.Properties['Existed'])
		{
			$existed = [int]$backupItem.Existed
		}
		$originalValue = $null
		if ($existed -eq 1 -and $backupItem.PSObject.Properties['Value'])
		{
			$originalValue = $backupItem.Value
		}

		$restored = $false
		if ($PSCmdlet.ShouldProcess("$($setting.Path)\$($setting.Name)", "Restore $($setting.Id)"))
		{
			if ($existed -eq 1)
			{
				Set-RegistryValueSafe -Path $setting.Path -Name $setting.Name -Value $originalValue -Type $setting.Type | Out-Null
			}
			else
			{
				if (Test-Path -LiteralPath $setting.Path)
				{
					Remove-RegistryValueSafe -Path $setting.Path -Name $setting.Name | Out-Null
				}
			}
			Remove-Item -LiteralPath $backupKey -Recurse -Force -ErrorAction SilentlyContinue
			$restored = $true
		}

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Restored      = $restored
			Skipped       = $false
			SkipReason    = $null
			OriginalExisted = ($existed -eq 1)
		}) | Out-Null
	}

	return $results.ToArray()
}

function Get-BaselineNetworkHardeningRegistryStatus
{
	<#
		.SYNOPSIS
		Reports per-setting hardening status across the catalog.

		.DESCRIPTION
		Classifies each setting as one of:
		  * Hardened -- live value matches the desired value.
		  * Drift -- live value present but differs from the desired value.
		  * NotSet -- live value missing.
		Also notes whether a Baseline backup is present so callers can
		decide whether a restore is safe.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$Settings = Get-BaselineNetworkHardeningRegistrySettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]
	foreach ($setting in $Settings)
	{
		$currentValue = $null
		$currentExists = $false
		if (Test-Path -LiteralPath $setting.Path)
		{
			$item = Get-ItemProperty -LiteralPath $setting.Path -ErrorAction SilentlyContinue
			if ($item -and $item.PSObject.Properties[$setting.Name])
			{
				$currentValue = $item.PSObject.Properties[$setting.Name].Value
				$currentExists = $true
			}
		}

		$state = if (-not $currentExists) { 'NotSet' }
				 elseif ($currentValue -eq $setting.Value) { 'Hardened' }
				 else { 'Drift' }

		$backupPresent = Test-Path -LiteralPath (Join-Path -Path $BackupRoot -ChildPath $setting.Id)

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Path          = $setting.Path
			Name          = $setting.Name
			DesiredValue  = $setting.Value
			CurrentValue  = $currentValue
			State         = $state
			BackupPresent = $backupPresent
		}) | Out-Null
	}

	return $results.ToArray()
}

function Get-BaselineNetBiosInterfacesRoot
{
	<#
		.SYNOPSIS
		Returns the registry root that holds per-adapter NetBT settings.

		.DESCRIPTION
		Defaults to
		`HKLM:\System\CurrentControlSet\Services\NetBT\Parameters\Interfaces`.
		Honours `BASELINE_NETBT_INTERFACES_ROOT` for tests.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_NETBT_INTERFACES_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}
	return 'HKLM:\System\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
}

function Disable-BaselineNetBiosOverTcpip
{
	<#
		.SYNOPSIS
		Disables NetBIOS over TCP/IP across all enumerated adapter interfaces.

		.DESCRIPTION
		Walks `<InterfacesRoot>\Tcpip_*` subkeys, snapshots each adapter's
		current `NetbiosOptions` value into the per-adapter backup, and
		writes `NetbiosOptions = 2` (Disable). NetbiosOptions values:
		  0 = use NetBIOS setting from DHCP
		  1 = enable NetBIOS over TCP/IP
		  2 = disable NetBIOS over TCP/IP

		Returns one record per interface.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[string]$InterfacesRoot,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('InterfacesRoot') -or [string]::IsNullOrWhiteSpace($InterfacesRoot))
	{
		$InterfacesRoot = Get-BaselineNetBiosInterfacesRoot
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]
	if (-not (Test-Path -LiteralPath $InterfacesRoot))
	{
		return $results.ToArray()
	}

	$adapterBackupRoot = Join-Path -Path $BackupRoot -ChildPath 'NetBiosOverTcpip'
	$adapters = Get-ChildItem -LiteralPath $InterfacesRoot -ErrorAction SilentlyContinue |
		Where-Object { $_.PSChildName -like 'Tcpip_*' }

	foreach ($adapter in $adapters)
	{
		$adapterPath = $adapter.PSPath
		$psPath = (Get-Item -LiteralPath $adapterPath).PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', 'Registry::'

		$item = Get-ItemProperty -LiteralPath $psPath -ErrorAction SilentlyContinue
		$currentValue = $null
		$currentExists = $false
		if ($item -and $item.PSObject.Properties['NetbiosOptions'])
		{
			$currentValue = [int]$item.NetbiosOptions
			$currentExists = $true
		}

		$adapterId = $adapter.PSChildName
		$adapterBackupKey = Join-Path -Path $adapterBackupRoot -ChildPath $adapterId
		$backupCreated = $false
		if (-not (Test-Path -LiteralPath $adapterBackupKey))
		{
			if ($PSCmdlet.ShouldProcess($adapterBackupKey, "Snapshot NetbiosOptions for $adapterId"))
			{
				if ($currentExists)
				{
					Set-RegistryValueSafe -Path $adapterBackupKey -Name 'Value' -Value $currentValue -Type 'DWord' | Out-Null
					Set-RegistryValueSafe -Path $adapterBackupKey -Name 'Existed' -Value 1 -Type 'DWord' | Out-Null
				}
				else
				{
					if (-not (Test-Path -LiteralPath $adapterBackupKey))
					{
						New-Item -Path $adapterBackupKey -Force | Out-Null
					}
					Set-RegistryValueSafe -Path $adapterBackupKey -Name 'Existed' -Value 0 -Type 'DWord' | Out-Null
				}
				$backupCreated = $true
			}
		}

		$applied = $false
		if ($PSCmdlet.ShouldProcess("$psPath\NetbiosOptions", "Set NetbiosOptions=2 (disable) for $adapterId"))
		{
			$applied = [bool](Set-RegistryValueSafe -Path $psPath -Name 'NetbiosOptions' -Value 2 -Type 'DWord')
		}

		$results.Add([pscustomobject]@{
			AdapterId     = $adapterId
			PreviousValue = $currentValue
			PreviousExists= $currentExists
			BackupCreated = $backupCreated
			Applied       = $applied
		}) | Out-Null
	}

	return $results.ToArray()
}

function Restore-BaselineNetBiosOverTcpip
{
	<#
		.SYNOPSIS
		Restores per-adapter NetbiosOptions from Baseline backups.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[string]$InterfacesRoot,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('InterfacesRoot') -or [string]::IsNullOrWhiteSpace($InterfacesRoot))
	{
		$InterfacesRoot = Get-BaselineNetBiosInterfacesRoot
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]
	$adapterBackupRoot = Join-Path -Path $BackupRoot -ChildPath 'NetBiosOverTcpip'
	if (-not (Test-Path -LiteralPath $adapterBackupRoot))
	{
		return $results.ToArray()
	}

	$adapters = Get-ChildItem -LiteralPath $adapterBackupRoot -ErrorAction SilentlyContinue
	foreach ($adapter in $adapters)
	{
		$adapterId = $adapter.PSChildName
		$backupItem = Get-ItemProperty -LiteralPath $adapter.PSPath -ErrorAction SilentlyContinue
		$existed = 0
		if ($backupItem -and $backupItem.PSObject.Properties['Existed'])
		{
			$existed = [int]$backupItem.Existed
		}
		$originalValue = $null
		if ($existed -eq 1 -and $backupItem.PSObject.Properties['Value'])
		{
			$originalValue = [int]$backupItem.Value
		}

		$adapterPath = Join-Path -Path $InterfacesRoot -ChildPath $adapterId
		$restored = $false
		if (Test-Path -LiteralPath $adapterPath)
		{
			if ($PSCmdlet.ShouldProcess("$adapterPath\NetbiosOptions", "Restore NetbiosOptions for $adapterId"))
			{
				if ($existed -eq 1)
				{
					Set-RegistryValueSafe -Path $adapterPath -Name 'NetbiosOptions' -Value $originalValue -Type 'DWord' | Out-Null
				}
				else
				{
					Remove-RegistryValueSafe -Path $adapterPath -Name 'NetbiosOptions' | Out-Null
				}
				Remove-Item -LiteralPath $adapter.PSPath -Recurse -Force -ErrorAction SilentlyContinue
				$restored = $true
			}
		}

		$results.Add([pscustomobject]@{
			AdapterId    = $adapterId
			Restored     = $restored
			OriginalExisted = ($existed -eq 1)
		}) | Out-Null
	}

	return $results.ToArray()
}

function Get-BaselineWinRMServiceBackupKey
{
	<#
		.SYNOPSIS
		Returns the registry key under the network-hardening backup root that
		holds the WinRM service's prior startup state.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ([string]$BackupRoot)

	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}
	return (Join-Path -Path $BackupRoot -ChildPath 'WinRMService')
}

function Disable-BaselineWinRMService
{
	<#
		.SYNOPSIS
		Stops the WinRM service and disables its startup type, with backup.

		.DESCRIPTION
		Looks up the current WinRM service via the supplied
		-ServiceLookup scriptblock (defaults to Get-Service WinRM), records
		its StartType + Status into the backup key, then issues the
		caller-supplied apply scriptblocks. Designed for testability:
		the production callsite uses live cmdlets; the tests pass mocks.

		If no -ServiceLookup is provided, defaults call Get-Service /
		Set-Service / Stop-Service directly. If WinRM is not installed the
		function returns a record with Skipped=$true.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[scriptblock]$ServiceLookup,
		[scriptblock]$StopAction,
		[scriptblock]$DisableAction,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}
	$backupKey = Get-BaselineWinRMServiceBackupKey -BackupRoot $BackupRoot

	$service = $null
	try
	{
		if ($ServiceLookup)
		{
			$service = & $ServiceLookup
		}
		else
		{
			$service = Get-Service -Name 'WinRM' -ErrorAction Stop
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'NetworkHardening.Helpers.Disable-BaselineWinRMService:catch604' -Severity Debug }

		return [pscustomobject]@{
			Found      = $false
			Skipped    = $true
			SkipReason = 'NotInstalled'
			Stopped    = $false
			Disabled   = $false
		}
	}

	if (-not $service)
	{
		return [pscustomobject]@{
			Found      = $false
			Skipped    = $true
			SkipReason = 'NotInstalled'
			Stopped    = $false
			Disabled   = $false
		}
	}

	$priorStartType = [string]$service.StartType
	$priorStatus    = [string]$service.Status

	if (-not (Test-Path -LiteralPath $backupKey))
	{
		if ($PSCmdlet.ShouldProcess($backupKey, 'Snapshot WinRM service prior state'))
		{
			Set-RegistryValueSafe -Path $backupKey -Name 'PriorStartType' -Value $priorStartType -Type 'String' | Out-Null
			Set-RegistryValueSafe -Path $backupKey -Name 'PriorStatus' -Value $priorStatus -Type 'String' | Out-Null
			Set-RegistryValueSafe -Path $backupKey -Name 'CapturedAt' -Value ([DateTime]::UtcNow.ToString('o')) -Type 'String' | Out-Null
		}
	}

	$stopped = $false
	if ($priorStatus -ne 'Stopped' -and $PSCmdlet.ShouldProcess('Service WinRM', 'Stop'))
	{
		if ($StopAction) { & $StopAction $service } else { Stop-Service -Name 'WinRM' -Force -ErrorAction SilentlyContinue }
		$stopped = $true
	}

	$disabled = $false
	if ($priorStartType -ne 'Disabled' -and $PSCmdlet.ShouldProcess('Service WinRM', 'Set startup type Disabled'))
	{
		if ($DisableAction) { & $DisableAction $service } else { Set-Service -Name 'WinRM' -StartupType Disabled -ErrorAction SilentlyContinue }
		$disabled = $true
	}

	return [pscustomobject]@{
		Found          = $true
		Skipped        = $false
		SkipReason     = $null
		Stopped        = $stopped
		Disabled       = $disabled
		PriorStartType = $priorStartType
		PriorStatus    = $priorStatus
	}
}

function Restore-BaselineWinRMService
{
	<#
		.SYNOPSIS
		Restores the WinRM service to its captured prior startup type and
		status.

		.DESCRIPTION
		Reads the snapshot written by Disable-BaselineWinRMService and
		issues the caller-supplied apply scriptblocks. If no snapshot
		exists, returns Skipped=$true with SkipReason='NoBackup' rather
		than guessing a default.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[scriptblock]$RestoreStartTypeAction,
		[scriptblock]$StartAction,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineNetworkHardeningBackupRoot
	}
	$backupKey = Get-BaselineWinRMServiceBackupKey -BackupRoot $BackupRoot

	if (-not (Test-Path -LiteralPath $backupKey))
	{
		return [pscustomobject]@{
			Restored   = $false
			Skipped    = $true
			SkipReason = 'NoBackup'
		}
	}

	$item = Get-ItemProperty -LiteralPath $backupKey -ErrorAction SilentlyContinue
	$priorStartType = if ($item -and $item.PSObject.Properties['PriorStartType']) { [string]$item.PriorStartType } else { $null }
	$priorStatus    = if ($item -and $item.PSObject.Properties['PriorStatus'])    { [string]$item.PriorStatus }    else { $null }

	if ([string]::IsNullOrWhiteSpace($priorStartType))
	{
		return [pscustomobject]@{
			Restored   = $false
			Skipped    = $true
			SkipReason = 'EmptyBackup'
		}
	}

	$startTypeRestored = $false
	if ($PSCmdlet.ShouldProcess('Service WinRM', "Set startup type $priorStartType"))
	{
		if ($RestoreStartTypeAction) { & $RestoreStartTypeAction $priorStartType } else { Set-Service -Name 'WinRM' -StartupType $priorStartType -ErrorAction SilentlyContinue }
		$startTypeRestored = $true
	}

	$started = $false
	if ($priorStatus -eq 'Running' -and $PSCmdlet.ShouldProcess('Service WinRM', 'Start'))
	{
		if ($StartAction) { & $StartAction } else { Start-Service -Name 'WinRM' -ErrorAction SilentlyContinue }
		$started = $true
	}

	Remove-Item -LiteralPath $backupKey -Recurse -Force -ErrorAction SilentlyContinue

	return [pscustomobject]@{
		Restored          = $true
		Skipped           = $false
		SkipReason        = $null
		PriorStartType    = $priorStartType
		PriorStatus       = $priorStatus
		StartTypeRestored = $startTypeRestored
		Started           = $started
	}
}
