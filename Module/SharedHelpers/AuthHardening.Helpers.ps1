# Authentication / domain hardening helpers.
#
# Spec: todo.md "Authentication / domain hardening" --
#   Kerberos SupportedEncryptionTypes (no DES/RC4),
#   RestrictSendingNTLMTraffic / RestrictReceivingNTLMTraffic
#   (audit-then-deny pattern),
#   LDAPClientIntegrity = 2,
#   Netlogon RequireSignOrSeal / RequireStrongKey /
#   SealSecureChannel / SignSecureChannel = 1,
#   SCRemoveOption = "1" (smart-card removal lock),
#   CWDIllegalInDllSearch = 0xFFFFFFFF, SafeDllSearchMode = 1,
#   PSLockdownPolicy = 4 (system-wide CLM -- flag as Caution).
#
# Back-end helpers only; the Tweaks JSON integration for OS Hardening
# toggle wiring is done in a separate slice.
#
# Each catalog entry carries Caution=$true for settings the operator must
# opt into deliberately:
#   * NTLM restrict values default to 1 (Audit). Going to 2 (Deny) on a
#     domain-joined box without first watching the audit channel is the
#     classic foot-gun that locks the machine off the network.
#   * PSLockdownPolicy = 4 forces system-wide Constrained Language Mode.
#     Many third-party PS tools break under CLM, so callers should let the
#     user opt in explicitly.

function Get-BaselineAuthHardeningSettings
{
	<#
		.SYNOPSIS
		Returns the canonical catalog of authentication / domain hardening
		registry settings Baseline applies.

		.DESCRIPTION
		Each record carries Id, Path, Name, Type, Value, Caution, and
		Description so callers can render audit output without re-deriving
		the meaning. Order is stable so iterators get reproducible output.

		Settings:
		  * Kerberos: SupportedEncryptionTypes = 0x18 (AES128 + AES256 only)
		  * NTLM: RestrictSending/Receiving = 1 (Audit) -- Caution
		  * LDAP: LDAPClientIntegrity = 2 (require signing)
		  * Netlogon: RequireSignOrSeal, RequireStrongKey,
		    SealSecureChannel, SignSecureChannel = 1
		  * Smart card: SCRemoveOption = "1" (lock workstation on removal)
		  * DLL search: SafeDllSearchMode = 1, CWDIllegalInDllSearch = 0xFFFFFFFF
		  * PowerShell: PSLockdownPolicy = 4 (CLM) -- Caution
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param ()

	$kerberos      = 'HKLM:\System\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
	$lsaMsv1_0     = 'HKLM:\System\CurrentControlSet\Control\Lsa\MSV1_0'
	$ldap          = 'HKLM:\System\CurrentControlSet\Services\LDAP'
	$netlogon      = 'HKLM:\System\CurrentControlSet\Services\Netlogon\Parameters'
	$winlogon      = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
	$sessionMgr    = 'HKLM:\System\CurrentControlSet\Control\Session Manager'
	$psPolicyKey   = 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'

	# CWDIllegalInDllSearch = 0xFFFFFFFF (all CWD-relative DLL search
	# disabled). PowerShell stores REG_DWORD as Int32, so the bit pattern
	# is conveyed as -1.
	$cwdIllegalAll = [int]-1

	return @(
		[pscustomobject]@{ Id='Kerberos.SupportedEncryptionTypes'; Path=$kerberos;   Name='SupportedEncryptionTypes';     Type='DWord';  Value=24;             Caution=$false; Description='Kerberos: allow AES128 + AES256 only (0x18). Disables DES and RC4.' }
		[pscustomobject]@{ Id='NTLM.RestrictSending';               Path=$lsaMsv1_0;  Name='RestrictSendingNTLMTraffic';   Type='DWord';  Value=1;              Caution=$true;  Description='NTLM: Audit outbound NTLM traffic (1=Audit). Step up to 2=Deny only after the audit log is clean.' }
		[pscustomobject]@{ Id='NTLM.RestrictReceiving';             Path=$lsaMsv1_0;  Name='RestrictReceivingNTLMTraffic'; Type='DWord';  Value=1;              Caution=$true;  Description='NTLM: Audit inbound NTLM traffic (1=Audit). Step up to 2=Deny only after the audit log is clean.' }
		[pscustomobject]@{ Id='LDAP.ClientIntegrity';               Path=$ldap;       Name='LDAPClientIntegrity';          Type='DWord';  Value=2;              Caution=$false; Description='LDAP: Require signing on all LDAP client traffic.' }
		[pscustomobject]@{ Id='Netlogon.RequireSignOrSeal';         Path=$netlogon;   Name='RequireSignOrSeal';            Type='DWord';  Value=1;              Caution=$false; Description='Netlogon: Require signed or sealed secure-channel traffic.' }
		[pscustomobject]@{ Id='Netlogon.RequireStrongKey';          Path=$netlogon;   Name='RequireStrongKey';             Type='DWord';  Value=1;              Caution=$false; Description='Netlogon: Require AES (strong session key) for the secure channel.' }
		[pscustomobject]@{ Id='Netlogon.SealSecureChannel';         Path=$netlogon;   Name='SealSecureChannel';            Type='DWord';  Value=1;              Caution=$false; Description='Netlogon: Encrypt all secure-channel traffic when supported.' }
		[pscustomobject]@{ Id='Netlogon.SignSecureChannel';         Path=$netlogon;   Name='SignSecureChannel';            Type='DWord';  Value=1;              Caution=$false; Description='Netlogon: Digitally sign all secure-channel traffic when supported.' }
		[pscustomobject]@{ Id='Winlogon.SCRemoveOption';            Path=$winlogon;   Name='ScRemoveOption';               Type='String'; Value='1';            Caution=$false; Description='Smart card: Lock the workstation on smart-card removal ("1"=Lock, REG_SZ).' }
		[pscustomobject]@{ Id='SessionManager.SafeDllSearchMode';   Path=$sessionMgr; Name='SafeDllSearchMode';            Type='DWord';  Value=1;              Caution=$false; Description='DLL search: Use the safe search order (system dirs before CWD).' }
		[pscustomobject]@{ Id='SessionManager.CWDIllegalInDllSearch';Path=$sessionMgr;Name='CWDIllegalInDllSearch';        Type='DWord';  Value=$cwdIllegalAll; Caution=$false; Description='DLL search: Block CWD-relative DLL load entirely (0xFFFFFFFF).' }
		[pscustomobject]@{ Id='PowerShell.LockdownPolicy';          Path=$psPolicyKey;Name='PSLockdownPolicy';             Type='DWord';  Value=4;              Caution=$true;  Description='PowerShell: Enforce system-wide Constrained Language Mode (4). Many third-party tools break under CLM.' }
	)
}

function Get-BaselineAuthHardeningBackupRoot
{
	<#
		.SYNOPSIS
		Returns the registry root where Baseline stores the original values
		of auth-hardening settings so the apply can be reversed.

		.DESCRIPTION
		Defaults to `HKLM:\Software\Baseline\AuthHardening`. Honours an
		override via `BASELINE_AUTHHARD_BACKUP_ROOT` so tests redirect to an
		HKCU sandbox.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_AUTHHARD_BACKUP_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}
	return 'HKLM:\Software\Baseline\AuthHardening'
}

function ConvertTo-BaselineAuthHardeningBackupKey
{
	<#
		.SYNOPSIS
		Converts a catalog Id (which contains '.') into a registry-safe
		backup key segment.

		.DESCRIPTION
		Catalog Ids use a dotted namespace ("Kerberos.SupportedEncryptionTypes")
		so the backup-key layout stays human-readable. Registry path syntax
		treats `.` as a literal character, but several Baseline tooling
		passes parse on `.`, so we normalise to `__` for backup-key segments.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Id
	)

	return ($Id -replace '\.', '__')
}

function Set-BaselineAuthHardeningSettings
{
	<#
		.SYNOPSIS
		Applies the auth-hardening registry catalog with backup.

		.DESCRIPTION
		For each setting (or the explicit subset passed via -Settings):
		  1. Read the current value (if any) from the live key.
		  2. If a Baseline backup for that Id does not yet exist, write the
		     current state into the backup so the original survives a
		     re-apply that follows accidental drift.
		  3. Write the desired value via Set-RegistryValueSafe.

		Caution-flagged settings are skipped by default; pass
		-IncludeCaution to apply them.

		Returns one record per setting describing what changed. Honours
		-WhatIf via SupportsShouldProcess.

		.PARAMETER Settings
		Optional subset of catalog records (e.g. filtered by Id) to apply.
		Defaults to the full Get-BaselineAuthHardeningSettings list.

		.PARAMETER BackupRoot
		Optional override for the backup registry root.

		.PARAMETER IncludeCaution
		Apply settings flagged Caution=$true (NTLM restrict, PSLockdownPolicy).
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[string]$BackupRoot,
		[switch]$IncludeCaution
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$Settings = Get-BaselineAuthHardeningSettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineAuthHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		if ($setting.Caution -and -not $IncludeCaution)
		{
			$results.Add([pscustomobject]@{
				Id            = $setting.Id
				Path          = $setting.Path
				Name          = $setting.Name
				DesiredValue  = $setting.Value
				PreviousValue = $null
				PreviousExists= $false
				BackupCreated = $false
				Applied       = $false
				Skipped       = $true
				SkipReason    = 'Caution'
			}) | Out-Null
			continue
		}

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

		$backupKeyName = ConvertTo-BaselineAuthHardeningBackupKey -Id $setting.Id
		$backupKey = Join-Path -Path $BackupRoot -ChildPath $backupKeyName
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
			Skipped       = $false
			SkipReason    = $null
		}) | Out-Null
	}

	return $results.ToArray()
}

function Restore-BaselineAuthHardeningSettings
{
	<#
		.SYNOPSIS
		Restores the original values for previously-applied auth-hardening
		settings.

		.DESCRIPTION
		For each setting (or subset), reads the backup at
		`<BackupRoot>\<key>\Value` and writes it back to the live key. If
		the backup says the original did not exist (Existed=0), removes the
		live value instead. Removes the backup key on success so a
		subsequent apply will re-snapshot the now-restored state.

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
		$Settings = Get-BaselineAuthHardeningSettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineAuthHardeningBackupRoot
	}

	$results = New-Object System.Collections.Generic.List[object]

	foreach ($setting in $Settings)
	{
		$backupKeyName = ConvertTo-BaselineAuthHardeningBackupKey -Id $setting.Id
		$backupKey = Join-Path -Path $BackupRoot -ChildPath $backupKeyName
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
			Id              = $setting.Id
			Restored        = $restored
			Skipped         = $false
			SkipReason      = $null
			OriginalExisted = ($existed -eq 1)
		}) | Out-Null
	}

	return $results.ToArray()
}

function Get-BaselineAuthHardeningStatus
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
		decide whether a restore is safe, plus the Caution flag so UI can
		colour-code the row.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[pscustomobject[]]$Settings,
		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Settings') -or $null -eq $Settings -or $Settings.Count -eq 0)
	{
		$Settings = Get-BaselineAuthHardeningSettings
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineAuthHardeningBackupRoot
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

		$backupKeyName = ConvertTo-BaselineAuthHardeningBackupKey -Id $setting.Id
		$backupPresent = Test-Path -LiteralPath (Join-Path -Path $BackupRoot -ChildPath $backupKeyName)

		$results.Add([pscustomobject]@{
			Id            = $setting.Id
			Path          = $setting.Path
			Name          = $setting.Name
			DesiredValue  = $setting.Value
			CurrentValue  = $currentValue
			State         = $state
			Caution       = [bool]$setting.Caution
			BackupPresent = $backupPresent
		}) | Out-Null
	}

	return $results.ToArray()
}
