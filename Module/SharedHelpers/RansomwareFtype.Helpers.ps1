# Ransomware file-association mitigation helpers.
#
# Spec: todo.md "Ransomware file-association mitigations" --
#   ftype redirection of risky scripting / autorun extensions to Notepad so
#   a double-click on a malicious payload opens the source instead of
#   executing it. Covers .bat .cmd .js .vbs .hta .wsf .reg .msc .rdg
#   .application .deploy. Includes the CVE-2020-0765 RDCMan mitigation
#   (.rdg neutering) since RDCMan files can carry executable payloads
#   through gateway-server fields.
#
# Mitigation surface:
#   1. For each extension, look up the ProgID at HKLM:\Software\Classes\<ext>
#   2. Save the original `(Default)` open command at
#      HKLM:\Software\Classes\<ProgID>\shell\open\command to a Baseline
#      backup key.
#   3. Overwrite that command to launch notepad.exe so double-clicks open
#      the source rather than executing.
#   4. Restore reads the backup and writes it back; if no backup exists
#      (e.g. mitigation was applied out-of-band), restore is a no-op and
#      surfaces a warning.
#
# Core helpers live here; the Tweaks JSON wiring that exposes this toggle
# in OS Hardening is handled in a separate slice.

function Get-BaselineRansomwareFtypeExtensions
{
	<#
		.SYNOPSIS
		Returns the canonical list of risky extensions Baseline mitigates.

		.DESCRIPTION
		The list covers the MITRE T1204.002 / windows_hardening.cmd
		consensus on extensions that are double-click-executable and have
		no day-to-day legitimate use for typical end-users. Server-only or
		dev-only extensions are not in the list -- callers can extend by
		passing -ExtraExtensions where supported.

		Order is stable and deterministic so callers iterating the list
		(progress reporting, audit logs) get reproducible output.

		.OUTPUTS
		[string[]] of leading-dot extensions in lowercase.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param ()

	return @(
		'.bat'
		'.cmd'
		'.js'
		'.vbs'
		'.hta'
		'.wsf'
		'.reg'
		'.msc'
		'.rdg'
		'.application'
		'.deploy'
	)
}

function Get-BaselineRansomwareFtypeClassesRoot
{
	<#
		.SYNOPSIS
		Returns the registry root where ftype/assoc data lives.

		.DESCRIPTION
		Defaults to `HKLM:\Software\Classes`. Honours an override via
		`BASELINE_FTYPE_CLASSES_ROOT` so tests can redirect to an
		HKCU sandbox subkey without touching machine-wide state.

		.OUTPUTS
		[string] PowerShell-style registry path with no trailing separator.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_FTYPE_CLASSES_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}

	return 'HKLM:\Software\Classes'
}

function Get-BaselineRansomwareFtypeBackupRoot
{
	<#
		.SYNOPSIS
		Returns the registry root where Baseline stores the original
		open-command so mitigation can be reversed.

		.DESCRIPTION
		Defaults to `HKLM:\Software\Baseline\RansomwareFtype`. Honours an
		override via `BASELINE_FTYPE_BACKUP_ROOT`. Each mitigated ProgID
		gets a subkey holding `(Default)` (= the original command) and a
		`MitigatedAt` ISO-8601 timestamp.

		.OUTPUTS
		[string] PowerShell-style registry path with no trailing separator.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_FTYPE_BACKUP_ROOT
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override.TrimEnd('\')
	}

	return 'HKLM:\Software\Baseline\RansomwareFtype'
}

function Get-BaselineFtypeAssociation
{
	<#
		.SYNOPSIS
		Resolves the ProgID and current open-command for a single extension.

		.DESCRIPTION
		Mirrors what the legacy `assoc` + `ftype` console commands return:
		walks `<ClassesRoot>\<Extension>` to read the `(Default)` ProgID
		and then `<ClassesRoot>\<ProgID>\shell\open\command` to read the
		`(Default)` invocation string. Either branch may be missing (no
		ProgID registered, or ProgID points to a key without an open verb)
		-- the caller gets back a record with the missing fields set to
		`$null` rather than an exception.

		.PARAMETER Extension
		Leading-dot extension in any case. Lowercased before use.

		.PARAMETER ClassesRoot
		Optional override; defaults to Get-BaselineRansomwareFtypeClassesRoot.

		.OUTPUTS
		[pscustomobject] with Extension, ProgID, OpenCommand, ProgIDExists,
		OpenCommandExists fields.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Extension,

		[string]$ClassesRoot
	)

	if (-not $PSBoundParameters.ContainsKey('ClassesRoot') -or [string]::IsNullOrWhiteSpace($ClassesRoot))
	{
		$ClassesRoot = Get-BaselineRansomwareFtypeClassesRoot
	}

	$ext = $Extension.ToLowerInvariant()
	if (-not $ext.StartsWith('.'))
	{
		$ext = '.' + $ext
	}

	$extKey = Join-Path -Path $ClassesRoot -ChildPath $ext
	$progId = $null
	$progIdExists = $false
	if (Test-Path -LiteralPath $extKey)
	{
		try
		{
			$item = Get-ItemProperty -LiteralPath $extKey -ErrorAction Stop
			if ($item.PSObject.Properties['(default)'])
			{
				$progId = [string]$item.'(default)'
			}
			elseif ($item.PSObject.Properties['(Default)'])
			{
				$progId = [string]$item.'(Default)'
			}
			if (-not [string]::IsNullOrWhiteSpace($progId))
			{
				$progIdExists = $true
			}
			else
			{
				$progId = $null
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RansomwareFtype.Helpers.Get-BaselineFtypeAssociation:catch190' -Severity Debug }

			$progId = $null
		}
	}

	$openCommand = $null
	$openCommandExists = $false
	if ($progIdExists)
	{
		$commandKey = Join-Path -Path (Join-Path -Path (Join-Path -Path $ClassesRoot -ChildPath $progId) -ChildPath 'shell\open') -ChildPath 'command'
		if (Test-Path -LiteralPath $commandKey)
		{
			try
			{
				$item = Get-ItemProperty -LiteralPath $commandKey -ErrorAction Stop
				if ($item.PSObject.Properties['(default)'])
				{
					$openCommand = [string]$item.'(default)'
				}
				elseif ($item.PSObject.Properties['(Default)'])
				{
					$openCommand = [string]$item.'(Default)'
				}
				if (-not [string]::IsNullOrWhiteSpace($openCommand))
				{
					$openCommandExists = $true
				}
				else
				{
					$openCommand = $null
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'RansomwareFtype.Helpers.Get-BaselineFtypeAssociation:catch223' -Severity Debug }

				$openCommand = $null
			}
		}
	}

	return [pscustomobject]@{
		Extension         = $ext
		ProgID            = $progId
		ProgIDExists      = $progIdExists
		OpenCommand       = $openCommand
		OpenCommandExists = $openCommandExists
	}
}

function Get-BaselineRansomwareFtypeNotepadCommand
{
	<#
		.SYNOPSIS
		Returns the canonical Notepad open-command string Baseline writes
		when mitigating a ProgID.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	return '%SystemRoot%\System32\notepad.exe "%1"'
}

function Set-BaselineRansomwareFtypeMitigation
{
	<#
		.SYNOPSIS
		Applies the Notepad-redirect mitigation to a single extension.

		.DESCRIPTION
		1. Resolves the ProgID for the extension via Get-BaselineFtypeAssociation.
		2. If a ProgID exists with an open command, copies the original
		   command into the backup root keyed by ProgID (skipping the copy
		   if a backup is already present so repeated runs do not overwrite
		   the genuine original with the Notepad command).
		3. Writes the canonical Notepad command to the ProgID's open
		   command key.

		Returns a record describing what changed so callers can audit.
		Honours -WhatIf / -Confirm.

		.PARAMETER Extension
		Leading-dot extension to mitigate.

		.PARAMETER ClassesRoot
		Override for the Classes registry root (test sandbox).

		.PARAMETER BackupRoot
		Override for the backup registry root (test sandbox).
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Extension,

		[string]$ClassesRoot,

		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('ClassesRoot') -or [string]::IsNullOrWhiteSpace($ClassesRoot))
	{
		$ClassesRoot = Get-BaselineRansomwareFtypeClassesRoot
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineRansomwareFtypeBackupRoot
	}

	$assoc = Get-BaselineFtypeAssociation -Extension $Extension -ClassesRoot $ClassesRoot

	$result = [ordered]@{
		Extension      = $assoc.Extension
		ProgID         = $assoc.ProgID
		Mitigated      = $false
		BackupCreated  = $false
		AlreadyMitigated = $false
		Skipped        = $false
		SkipReason     = $null
	}

	if (-not $assoc.ProgIDExists)
	{
		$result.Skipped = $true
		$result.SkipReason = 'NoProgID'
		return [pscustomobject]$result
	}

	$notepadCommand = Get-BaselineRansomwareFtypeNotepadCommand
	if ($assoc.OpenCommandExists -and $assoc.OpenCommand -eq $notepadCommand)
	{
		$result.AlreadyMitigated = $true
		return [pscustomobject]$result
	}

	$progIdBackupKey = Join-Path -Path $BackupRoot -ChildPath $assoc.ProgID
	$backupExists = Test-Path -LiteralPath $progIdBackupKey
	if (-not $backupExists -and $assoc.OpenCommandExists)
	{
		if ($PSCmdlet.ShouldProcess($progIdBackupKey, 'Create Baseline ftype backup'))
		{
			Set-RegistryValueSafe -Path $progIdBackupKey -Name '(default)' -Value $assoc.OpenCommand -Type 'String' | Out-Null
			Set-RegistryValueSafe -Path $progIdBackupKey -Name 'MitigatedAt' -Value ([DateTime]::UtcNow.ToString('o')) -Type 'String' | Out-Null
			Set-RegistryValueSafe -Path $progIdBackupKey -Name 'Extension' -Value $assoc.Extension -Type 'String' | Out-Null
			$result.BackupCreated = $true
		}
	}

	$commandKey = Join-Path -Path (Join-Path -Path (Join-Path -Path $ClassesRoot -ChildPath $assoc.ProgID) -ChildPath 'shell\open') -ChildPath 'command'
	if ($PSCmdlet.ShouldProcess($commandKey, "Redirect $($assoc.Extension) to Notepad"))
	{
		Set-RegistryValueSafe -Path $commandKey -Name '(default)' -Value $notepadCommand -Type 'String' | Out-Null
		$result.Mitigated = $true
	}

	return [pscustomobject]$result
}

function Restore-BaselineRansomwareFtypeMitigation
{
	<#
		.SYNOPSIS
		Restores the original open-command for a single mitigated extension.

		.DESCRIPTION
		Looks up the ProgID for the extension, reads the backup at
		`<BackupRoot>\<ProgID>\(default)`, and writes it back to
		`<ClassesRoot>\<ProgID>\shell\open\command`. Removes the backup
		key on success so a subsequent mitigation will re-snapshot the
		(now-restored) original.

		If no backup exists (mitigation never applied, or applied out of
		band by another tool) the function returns a record with
		Restored=$false and SkipReason='NoBackup'.

		.PARAMETER Extension
		Leading-dot extension to restore.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[string]$Extension,

		[string]$ClassesRoot,

		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('ClassesRoot') -or [string]::IsNullOrWhiteSpace($ClassesRoot))
	{
		$ClassesRoot = Get-BaselineRansomwareFtypeClassesRoot
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineRansomwareFtypeBackupRoot
	}

	$assoc = Get-BaselineFtypeAssociation -Extension $Extension -ClassesRoot $ClassesRoot

	$result = [ordered]@{
		Extension  = $assoc.Extension
		ProgID     = $assoc.ProgID
		Restored   = $false
		Skipped    = $false
		SkipReason = $null
	}

	if (-not $assoc.ProgIDExists)
	{
		$result.Skipped = $true
		$result.SkipReason = 'NoProgID'
		return [pscustomobject]$result
	}

	$progIdBackupKey = Join-Path -Path $BackupRoot -ChildPath $assoc.ProgID
	if (-not (Test-Path -LiteralPath $progIdBackupKey))
	{
		$result.Skipped = $true
		$result.SkipReason = 'NoBackup'
		return [pscustomobject]$result
	}

	$backupItem = Get-ItemProperty -LiteralPath $progIdBackupKey -ErrorAction SilentlyContinue
	$originalCommand = $null
	if ($backupItem)
	{
		if ($backupItem.PSObject.Properties['(default)'])
		{
			$originalCommand = [string]$backupItem.'(default)'
		}
		elseif ($backupItem.PSObject.Properties['(Default)'])
		{
			$originalCommand = [string]$backupItem.'(Default)'
		}
	}
	if ([string]::IsNullOrWhiteSpace($originalCommand))
	{
		$result.Skipped = $true
		$result.SkipReason = 'EmptyBackup'
		return [pscustomobject]$result
	}

	$commandKey = Join-Path -Path (Join-Path -Path (Join-Path -Path $ClassesRoot -ChildPath $assoc.ProgID) -ChildPath 'shell\open') -ChildPath 'command'
	if ($PSCmdlet.ShouldProcess($commandKey, "Restore original command for $($assoc.Extension)"))
	{
		Set-RegistryValueSafe -Path $commandKey -Name '(default)' -Value $originalCommand -Type 'String' | Out-Null
		Remove-Item -LiteralPath $progIdBackupKey -Recurse -Force -ErrorAction SilentlyContinue
		$result.Restored = $true
	}

	return [pscustomobject]$result
}

function Get-BaselineRansomwareFtypeStatus
{
	<#
		.SYNOPSIS
		Reports per-extension mitigation status across the canonical list.

		.DESCRIPTION
		For each extension returned by Get-BaselineRansomwareFtypeExtensions
		(or the explicit -Extensions list), inspects the current open-command
		and the presence of a Baseline backup to classify state as one of:
		  * Mitigated -- open command currently points at notepad.exe AND a
		    Baseline backup exists.
		  * MitigatedNoBackup -- command points at notepad.exe but no backup
		    is present (out-of-band mitigation; reverting is unsafe).
		  * Original -- command does not point at notepad.exe and no backup
		    is present.
		  * Unregistered -- no ProgID is registered for the extension.

		.OUTPUTS
		[pscustomobject[]] one record per inspected extension.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[string[]]$Extensions,

		[string]$ClassesRoot,

		[string]$BackupRoot
	)

	if (-not $PSBoundParameters.ContainsKey('Extensions') -or $null -eq $Extensions -or $Extensions.Count -eq 0)
	{
		$Extensions = Get-BaselineRansomwareFtypeExtensions
	}
	if (-not $PSBoundParameters.ContainsKey('ClassesRoot') -or [string]::IsNullOrWhiteSpace($ClassesRoot))
	{
		$ClassesRoot = Get-BaselineRansomwareFtypeClassesRoot
	}
	if (-not $PSBoundParameters.ContainsKey('BackupRoot') -or [string]::IsNullOrWhiteSpace($BackupRoot))
	{
		$BackupRoot = Get-BaselineRansomwareFtypeBackupRoot
	}

	$notepadCommand = Get-BaselineRansomwareFtypeNotepadCommand
	$results = New-Object System.Collections.Generic.List[object]

	foreach ($extension in $Extensions)
	{
		$assoc = Get-BaselineFtypeAssociation -Extension $extension -ClassesRoot $ClassesRoot
		$state = 'Unregistered'
		$backupPresent = $false

		if ($assoc.ProgIDExists)
		{
			$progIdBackupKey = Join-Path -Path $BackupRoot -ChildPath $assoc.ProgID
			$backupPresent = Test-Path -LiteralPath $progIdBackupKey

			if ($assoc.OpenCommandExists -and $assoc.OpenCommand -eq $notepadCommand)
			{
				if ($backupPresent) { $state = 'Mitigated' }
				else { $state = 'MitigatedNoBackup' }
			}
			else
			{
				$state = 'Original'
			}
		}

		$results.Add([pscustomobject]@{
			Extension     = $assoc.Extension
			ProgID        = $assoc.ProgID
			OpenCommand   = $assoc.OpenCommand
			BackupPresent = $backupPresent
			State         = $state
		}) | Out-Null
	}

	return $results.ToArray()
}
