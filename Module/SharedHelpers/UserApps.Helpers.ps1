# User-added / custom External Software list helpers.
#
# Spec: todo.md "#18 User-added / custom External Software list" --
#   `%LOCALAPPDATA%\Baseline\UserApps\*.json` with the same schema as the
#   baked-in `Module/Data/AppsCategory/*.json`, plus a `Source = "User"`
#   field for provenance tracking. User entries can extend the catalog but
#   never override built-in IDs.
#
# Back-end helpers only: directory resolution, entry validation, on-disk
# loading, and merge-with-conflict detection.
# The catalog loader integration for External Software (including
# + Add custom app and Restore-defaults / Export-config flow) is implemented
# in a separate GUI slice.

function Get-BaselineUserAppsDirectory
{
	<#
		.SYNOPSIS
		Returns the canonical directory where Baseline reads user-added
		custom app definitions.

		.DESCRIPTION
		Defaults to `$env:LOCALAPPDATA\Baseline\UserApps`. Honours an
		override via `BASELINE_USER_APPS_DIR` so tests and unattended
		harnesses can redirect to a sandbox without touching LocalAppData.
		Falls back to a profile-relative path when LOCALAPPDATA is empty.

		.OUTPUTS
		[string] absolute directory path. The directory is not created here.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$override = $env:BASELINE_USER_APPS_DIR
	if (-not [string]::IsNullOrWhiteSpace($override))
	{
		return $override
	}

	$localAppData = $env:LOCALAPPDATA
	if ([string]::IsNullOrWhiteSpace($localAppData))
	{
		$userProfile = $env:USERPROFILE
		if ([string]::IsNullOrWhiteSpace($userProfile))
		{
			# Service-context fallback. Real callers will hit the LOCALAPPDATA
			# branch above; this is just so the function never returns $null.
			return 'C:\Baseline\UserApps'
		}
		$localAppData = Join-Path -Path $userProfile -ChildPath 'AppData\Local'
	}

	return (Join-Path -Path $localAppData -ChildPath 'Baseline\UserApps')
}

function Test-BaselineUserAppEntry
{
	<#
		.SYNOPSIS
		Validates a single user-app entry object against the minimum schema
		required for catalog integration.

		.DESCRIPTION
		Required: `Name` (non-empty string), at least one of
		`ExtraArgs.WinGetId` / `ExtraArgs.ChocoId` (non-empty string),
		`SubCategory` (non-empty string). When `Function` is present it must
		equal `"AppInstall"` -- user entries describe installable apps and
		Baseline rejects anything else for safety (a user supplying
		`Function = "Set-RegistryValueSafe"` could otherwise smuggle
		arbitrary registry writes through the catalog merge).

		Returns a structured result rather than just a bool so callers can
		surface what's wrong to the user without re-checking each field.

		.OUTPUTS
		[pscustomobject] with IsValid (bool), Errors (string[]) -- empty
		Errors when IsValid is true.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowNull()]
		[object]$Entry
	)

	$errors = [System.Collections.Generic.List[string]]::new()

	if ($null -eq $Entry)
	{
		$errors.Add('Entry is $null.')
		return [pscustomobject]@{ IsValid = $false; Errors = $errors.ToArray() }
	}

	$entryHash = $null
	if ($Entry -is [System.Collections.IDictionary])
	{
		$entryHash = @{}
		foreach ($k in $Entry.Keys)
		{
			$entryHash[[string]$k] = $Entry[$k]
		}
	}
	elseif ($Entry.PSObject)
	{
		$entryHash = @{}
		foreach ($prop in $Entry.PSObject.Properties)
		{
			$entryHash[$prop.Name] = $prop.Value
		}
	}
	else
	{
		$errors.Add("Entry is not a dictionary or object (type: $($Entry.GetType().FullName)).")
		return [pscustomobject]@{ IsValid = $false; Errors = $errors.ToArray() }
	}

	$nameValue = if ($entryHash.ContainsKey('Name')) { [string]$entryHash['Name'] } else { $null }
	if ([string]::IsNullOrWhiteSpace($nameValue))
	{
		$errors.Add("'Name' is required and must be a non-empty string.")
	}

	$subCategoryValue = if ($entryHash.ContainsKey('SubCategory')) { [string]$entryHash['SubCategory'] } else { $null }
	if ([string]::IsNullOrWhiteSpace($subCategoryValue))
	{
		$errors.Add("'SubCategory' is required and must be a non-empty string.")
	}

	if ($entryHash.ContainsKey('Function'))
	{
		$functionValue = [string]$entryHash['Function']
		if (-not [string]::IsNullOrWhiteSpace($functionValue) -and $functionValue -ne 'AppInstall')
		{
			$errors.Add("'Function' must be 'AppInstall' for user app entries (got: '$functionValue').")
		}
	}

	$winGetId = $null
	$chocoId = $null
	if ($entryHash.ContainsKey('ExtraArgs') -and $null -ne $entryHash['ExtraArgs'])
	{
		$extra = $entryHash['ExtraArgs']
		$extraHash = $null
		if ($extra -is [System.Collections.IDictionary])
		{
			$extraHash = @{}
			foreach ($k in $extra.Keys)
			{
				$extraHash[[string]$k] = $extra[$k]
			}
		}
		elseif ($extra.PSObject)
		{
			$extraHash = @{}
			foreach ($prop in $extra.PSObject.Properties)
			{
				$extraHash[$prop.Name] = $prop.Value
			}
		}

		if ($extraHash)
		{
			if ($extraHash.ContainsKey('WinGetId')) { $winGetId = [string]$extraHash['WinGetId'] }
			if ($extraHash.ContainsKey('ChocoId')) { $chocoId = [string]$extraHash['ChocoId'] }
		}
	}

	if ([string]::IsNullOrWhiteSpace($winGetId) -and [string]::IsNullOrWhiteSpace($chocoId))
	{
		$errors.Add("At least one of 'ExtraArgs.WinGetId' or 'ExtraArgs.ChocoId' is required.")
	}

	return [pscustomobject]@{
		IsValid = ($errors.Count -eq 0)
		Errors  = $errors.ToArray()
	}
}

function Get-BaselineUserAppEntries
{
	<#
		.SYNOPSIS
		Loads and validates user-added app entries from the user-apps
		directory.

		.DESCRIPTION
		Reads every `*.json` file under the directory returned by
		Get-BaselineUserAppsDirectory (or the directory passed via -Path)
		and returns a flattened list of entries. Each file is expected to
		match the baked-in catalog shape: a top-level object with `Tab`
		(currently always `"Applications"` for the External Software tab)
		and `Entries` (an array of entry objects). Validation runs per
		entry; invalid entries are dropped with a `LogWarning` (or written
		to the warnings collector returned alongside the entries) so the
		whole file isn't lost when one entry has a typo.

		Each returned entry is annotated with `Source = "User"` and
		`SourceFile = <path>` so the merge step can keep provenance and
		Restore-defaults can know which entries came from the user.

		Returns silently with empty results when the directory does not
		exist -- a fresh install has no user-apps directory yet, that's
		not an error condition.

		.OUTPUTS
		[pscustomobject] with two members:
		  Entries  -- pscustomobject[] of validated entries
		  Warnings -- string[] of validation / parse warnings (empty
		              when nothing is wrong)
	#>
	[CmdletBinding()]
	param (
		[string]$Path
	)

	$directory = if (-not [string]::IsNullOrWhiteSpace($Path))
	{
		$Path
	}
	else
	{
		Get-BaselineUserAppsDirectory
	}

	$entries = [System.Collections.Generic.List[object]]::new()
	$warnings = [System.Collections.Generic.List[string]]::new()

	if (-not (Test-Path -LiteralPath $directory))
	{
		return [pscustomobject]@{ Entries = @(); Warnings = @() }
	}

	$jsonFiles = @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction SilentlyContinue)
	foreach ($file in $jsonFiles)
	{
		$raw = $null
		try
		{
			$raw = [System.IO.File]::ReadAllText($file.FullName)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserApps.Helpers.Get-BaselineUserAppEntries:catch242' -Severity Debug }

			$warnings.Add("Failed to read user app file '$($file.FullName)': $($_.Exception.Message)")
			continue
		}

		$parsed = $null
		try
		{
			$parsed = $raw | ConvertFrom-Json -ErrorAction Stop
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserApps.Helpers.Get-BaselineUserAppEntries:catch253' -Severity Debug }

			$warnings.Add("Failed to parse user app file '$($file.FullName)' as JSON: $($_.Exception.Message)")
			continue
		}

		# Tolerate either { Entries: [...] } shape or a bare top-level array.
		$rawEntries = $null
		if ($null -ne $parsed -and $parsed.PSObject -and $parsed.PSObject.Properties['Entries'])
		{
			$rawEntries = @($parsed.Entries)
		}
		elseif ($parsed -is [System.Collections.IEnumerable] -and $parsed -isnot [string])
		{
			$rawEntries = @($parsed)
		}
		else
		{
			$warnings.Add("User app file '$($file.FullName)' does not contain an 'Entries' array or a top-level array.")
			continue
		}

		foreach ($entry in $rawEntries)
		{
			$validation = Test-BaselineUserAppEntry -Entry $entry
			if (-not $validation.IsValid)
			{
				$entryName = if ($null -ne $entry -and $entry.PSObject -and $entry.PSObject.Properties['Name']) { [string]$entry.Name } else { '<unnamed>' }
				$warnings.Add("Skipping invalid user app entry '$entryName' in '$($file.FullName)': $($validation.Errors -join '; ')")
				continue
			}

			# Normalize to a pscustomobject so downstream code doesn't have
			# to handle hashtable-vs-pscustomobject. Carry through every
			# field on the input entry plus our provenance annotations.
			$normalized = [ordered]@{}
			if ($entry -is [System.Collections.IDictionary])
			{
				foreach ($k in $entry.Keys)
				{
					$normalized[[string]$k] = $entry[$k]
				}
			}
			else
			{
				foreach ($prop in $entry.PSObject.Properties)
				{
					$normalized[$prop.Name] = $prop.Value
				}
			}

			$normalized['Source'] = 'User'
			$normalized['SourceFile'] = $file.FullName

			$entries.Add([pscustomobject]$normalized)
		}
	}

	return [pscustomobject]@{
		Entries  = @($entries)
		Warnings = @($warnings)
	}
}

function Merge-BaselineUserAppEntries
{
	<#
		.SYNOPSIS
		Merges user-added app entries into the built-in catalog list,
		dropping user entries whose WinGetId / ChocoId / Name collides
		with a built-in entry.

		.DESCRIPTION
		User entries can extend the catalog but never override built-in
		IDs (per todo.md #18 spec). Conflict detection is by:
		  - exact `Name` match (case-insensitive), or
		  - exact `ExtraArgs.WinGetId` match (case-insensitive), or
		  - exact `ExtraArgs.ChocoId` match (case-insensitive).
		When a user entry collides, it is dropped and a warning is emitted.

		Built-in entries are emitted first, user entries are appended, so
		any code that takes "first match wins" sees the built-in shape.

		.OUTPUTS
		[pscustomobject] with two members:
		  Entries  -- pscustomobject[] of merged entries (built-ins first)
		  Warnings -- string[] of conflict warnings (empty when none)
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[object[]]$BuiltInEntries,

		[Parameter(Mandatory)]
		[AllowEmptyCollection()]
		[object[]]$UserEntries
	)

	$warnings = [System.Collections.Generic.List[string]]::new()
	$result = [System.Collections.Generic.List[object]]::new()

	$names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$winGetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$chocoIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	$resolveField = {
		param ($entry, $fieldName)
		if ($null -eq $entry) { return $null }
		if ($entry -is [System.Collections.IDictionary])
		{
			if ($entry.Contains($fieldName)) { return $entry[$fieldName] }
			return $null
		}
		if ($entry.PSObject -and $entry.PSObject.Properties[$fieldName]) { return $entry.$fieldName }
		return $null
	}

	$resolveExtraArgsField = {
		param ($entry, $fieldName)
		$extra = & $resolveField $entry 'ExtraArgs'
		if ($null -eq $extra) { return $null }
		return (& $resolveField $extra $fieldName)
	}

	foreach ($entry in @($BuiltInEntries))
	{
		if ($null -eq $entry) { continue }
		$result.Add($entry)

		$name = [string](& $resolveField $entry 'Name')
		if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$names.Add($name) }

		$winGetId = [string](& $resolveExtraArgsField $entry 'WinGetId')
		if (-not [string]::IsNullOrWhiteSpace($winGetId)) { [void]$winGetIds.Add($winGetId) }

		$chocoId = [string](& $resolveExtraArgsField $entry 'ChocoId')
		if (-not [string]::IsNullOrWhiteSpace($chocoId)) { [void]$chocoIds.Add($chocoId) }
	}

	foreach ($entry in @($UserEntries))
	{
		if ($null -eq $entry) { continue }

		$name = [string](& $resolveField $entry 'Name')
		$winGetId = [string](& $resolveExtraArgsField $entry 'WinGetId')
		$chocoId = [string](& $resolveExtraArgsField $entry 'ChocoId')

		$conflictReason = $null
		if (-not [string]::IsNullOrWhiteSpace($name) -and $names.Contains($name))
		{
			$conflictReason = "Name '$name' already exists in built-in catalog"
		}
		elseif (-not [string]::IsNullOrWhiteSpace($winGetId) -and $winGetIds.Contains($winGetId))
		{
			$conflictReason = "WinGetId '$winGetId' already exists in built-in catalog"
		}
		elseif (-not [string]::IsNullOrWhiteSpace($chocoId) -and $chocoIds.Contains($chocoId))
		{
			$conflictReason = "ChocoId '$chocoId' already exists in built-in catalog"
		}

		if ($conflictReason)
		{
			$displayName = if (-not [string]::IsNullOrWhiteSpace($name)) { $name } else { '<unnamed>' }
			$warnings.Add("Dropping user app '$displayName': $conflictReason. Built-in entries cannot be overridden.")
			continue
		}

		$result.Add($entry)

		# Track this user entry's identifiers so two user entries with the
		# same Name / WinGetId also collide (we keep the first).
		if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$names.Add($name) }
		if (-not [string]::IsNullOrWhiteSpace($winGetId)) { [void]$winGetIds.Add($winGetId) }
		if (-not [string]::IsNullOrWhiteSpace($chocoId)) { [void]$chocoIds.Add($chocoId) }
	}

	return [pscustomobject]@{
		Entries  = @($result)
		Warnings = @($warnings)
	}
}

function Save-BaselineUserAppEntriesFromProfile
{
	<#
		.SYNOPSIS
		Restores inlined user-app catalog entries from an imported
		configuration profile to the local user-apps directory.

		.DESCRIPTION
		Reads the `UserApps` array from a parsed profile document (produced by
		`Import-ConfigurationProfile`) and writes each validated entry as its
		own JSON file under `Get-BaselineUserAppsDirectory`. Each file uses
		the same single-entry catalog shape `+ Add custom app` writes:
		`{ Tab: 'Applications', Entries: [<entry>] }`, UTF-8 (no BOM) via
		`[System.IO.File]::WriteAllText`.

		Skips any entry that collides with an existing user-app file by
		Name / WinGetId / ChocoId (case-insensitive). Existing user entries
		win — re-importing the same profile is a no-op rather than a
		clobber. Returns a structured result so callers can summarize what
		landed.

		.PARAMETER Profile
		The parsed profile document (with a `UserApps` member). Profiles
		exported before SchemaVersion 3 lack this field; this function
		treats that as zero entries to import.

		.PARAMETER Directory
		Optional override for the target directory. Defaults to
		`Get-BaselineUserAppsDirectory`.

		.OUTPUTS
		[pscustomobject] with members:
		  Imported -- string[] of entry names that were written
		  Skipped  -- pscustomobject[] @{ Name; Reason } for collisions / invalid entries
		  Failed   -- pscustomobject[] @{ Name; Reason } for I/O failures
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	param (
		[Parameter(Mandatory)]
		[object]$Profile,

		[string]$Directory
	)

	$imported = [System.Collections.Generic.List[string]]::new()
	$skipped = [System.Collections.Generic.List[object]]::new()
	$failed = [System.Collections.Generic.List[object]]::new()

	$profileUserApps = @()
	if ($Profile -and $Profile.PSObject -and $Profile.PSObject.Properties['UserApps'] -and $null -ne $Profile.UserApps)
	{
		$profileUserApps = @($Profile.UserApps)
	}

	if (@($profileUserApps).Count -eq 0)
	{
		return [pscustomobject]@{
			Imported = @()
			Skipped  = @()
			Failed   = @()
		}
	}

	if ([string]::IsNullOrWhiteSpace($Directory))
	{
		$Directory = Get-BaselineUserAppsDirectory
	}
	if (-not (Test-Path -LiteralPath $Directory))
	{
		[void](New-Item -Path $Directory -ItemType Directory -Force)
	}

	# Build collision sets from existing user-app entries already on disk.
	$existing = Get-BaselineUserAppEntries -Path $Directory
	$existingNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$existingWinGetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$existingChocoIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($existingEntry in @($existing.Entries))
	{
		if ($null -eq $existingEntry) { continue }
		$existingName = if ($existingEntry.PSObject.Properties['Name']) { [string]$existingEntry.Name } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($existingName)) { [void]$existingNames.Add($existingName) }
		if ($existingEntry.PSObject.Properties['ExtraArgs'] -and $null -ne $existingEntry.ExtraArgs)
		{
			$ea = $existingEntry.ExtraArgs
			if ($ea.PSObject.Properties['WinGetId']) { $w = [string]$ea.WinGetId; if (-not [string]::IsNullOrWhiteSpace($w)) { [void]$existingWinGetIds.Add($w) } }
			if ($ea.PSObject.Properties['ChocoId']) { $c = [string]$ea.ChocoId; if (-not [string]::IsNullOrWhiteSpace($c)) { [void]$existingChocoIds.Add($c) } }
		}
	}

	$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
	$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

	foreach ($profileEntry in $profileUserApps)
	{
		if ($null -eq $profileEntry) { continue }

		$entryName = $null
		if ($profileEntry.PSObject -and $profileEntry.PSObject.Properties['Name']) { $entryName = [string]$profileEntry.Name }
		if ([string]::IsNullOrWhiteSpace($entryName))
		{
			$skipped.Add([pscustomobject]@{ Name = '<unnamed>'; Reason = 'Entry has no Name field.' })
			continue
		}

		$validation = Test-BaselineUserAppEntry -Entry $profileEntry
		if (-not $validation.IsValid)
		{
			$skipped.Add([pscustomobject]@{ Name = $entryName; Reason = ($validation.Errors -join '; ') })
			continue
		}

		# Collision detection by Name / WinGetId / ChocoId.
		$winGetId = $null
		$chocoId = $null
		if ($profileEntry.PSObject.Properties['ExtraArgs'] -and $null -ne $profileEntry.ExtraArgs)
		{
			$ea = $profileEntry.ExtraArgs
			if ($ea.PSObject.Properties['WinGetId']) { $winGetId = [string]$ea.WinGetId }
			if ($ea.PSObject.Properties['ChocoId']) { $chocoId = [string]$ea.ChocoId }
		}

		if ($existingNames.Contains($entryName))
		{
			$skipped.Add([pscustomobject]@{ Name = $entryName; Reason = "An entry named '$entryName' already exists in the user-apps directory." })
			continue
		}
		if (-not [string]::IsNullOrWhiteSpace($winGetId) -and $existingWinGetIds.Contains($winGetId))
		{
			$skipped.Add([pscustomobject]@{ Name = $entryName; Reason = "WinGetId '$winGetId' already exists in the user-apps directory." })
			continue
		}
		if (-not [string]::IsNullOrWhiteSpace($chocoId) -and $existingChocoIds.Contains($chocoId))
		{
			$skipped.Add([pscustomobject]@{ Name = $entryName; Reason = "ChocoId '$chocoId' already exists in the user-apps directory." })
			continue
		}

		# Sanitize Name into a filesystem-safe slug.
		$builder = New-Object System.Text.StringBuilder
		foreach ($ch in $entryName.ToCharArray())
		{
			if ($invalidChars -contains $ch -or $ch -eq ' ') { [void]$builder.Append('_') }
			else { [void]$builder.Append($ch) }
		}
		$slug = $builder.ToString().Trim('_')
		if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'imported-app' }
		$baseName = $slug + '.json'
		$candidate = Join-Path -Path $Directory -ChildPath $baseName
		if (Test-Path -LiteralPath $candidate)
		{
			$suffix = 2
			do
			{
				$candidate = Join-Path -Path $Directory -ChildPath ('{0}-{1}.json' -f $slug, $suffix)
				$suffix++
			}
			while ((Test-Path -LiteralPath $candidate) -and $suffix -lt 1000)
		}

		try
		{
			# Strip Source / SourceFile if present (defensive — exporter already
			# does this, but profiles authored by hand or by older tooling might
			# carry runtime annotations).
			$saveEntry = [ordered]@{}
			foreach ($prop in $profileEntry.PSObject.Properties)
			{
				if ($prop.Name -eq 'Source' -or $prop.Name -eq 'SourceFile') { continue }
				$saveEntry[$prop.Name] = $prop.Value
			}

			$payload = [pscustomobject]@{
				Tab     = 'Applications'
				Entries = @([pscustomobject]$saveEntry)
			}
			$json = $payload | ConvertTo-Json -Depth 6
			[System.IO.File]::WriteAllText($candidate, $json, $utf8NoBom)
			$imported.Add($entryName)

			# Track this name / id so two profile entries with the same key
			# don't both write — the second hits the collision branch above.
			[void]$existingNames.Add($entryName)
			if (-not [string]::IsNullOrWhiteSpace($winGetId)) { [void]$existingWinGetIds.Add($winGetId) }
			if (-not [string]::IsNullOrWhiteSpace($chocoId)) { [void]$existingChocoIds.Add($chocoId) }
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UserApps.Helpers.Save-BaselineUserAppEntriesFromProfile:catch624' -Severity Debug }

			$failed.Add([pscustomobject]@{ Name = $entryName; Reason = $_.Exception.Message })
		}
	}

	return [pscustomobject]@{
		Imported = @($imported)
		Skipped  = @($skipped)
		Failed   = @($failed)
	}
}
