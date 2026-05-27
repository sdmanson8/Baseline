# CLI / unattended-mode helpers for Baseline.
#
# These helpers exist so the launcher's CLI surface can be unit-tested without
# spinning up the full GUI/host pipeline. They intentionally hold no state and
# touch no global variables — every input is a parameter, every output is a
# returned value. The launcher (Bootstrap/Baseline.ps1) is the only thing that
# wires these helpers into actual side-effects (printing to console, exiting
# the process, etc.).
#
# Behavioural anchors come from the CLI/unattended section of todo.md:
#   - Config supplied without Apply must still be promoted rather than ignored.
#   - Unattended runs use structured exit codes and avoid modal prompts.
#   - tracked preset contract:
#     --apply / --no-gui / --apply-preset surface.

<#
    .SYNOPSIS
#>

function Resolve-BaselineCliIntent
{
	<#
		.SYNOPSIS
		Normalizes raw launcher parameter values into a single intent record
		the bootstrap can act on.

		.DESCRIPTION
		Takes a hashtable of parameter values (so this stays callable from a
		unit test without a [CmdletBinding] in scope) and returns an object
		describing what mode to enter, whether to apply, and any warnings or
		errors to surface to the user.

		Key normalizations:
		  - `-ConfigFile <path>` without `-Run/-Apply` is treated as Apply
		    (with a warning) so supplied automation input is never ignored.
		  - `-ApplyPreset <name>` implies Apply.
		  - `-ListPresets` short-circuits the rest; mode = ListPresets, exit 0.
		  - `-NoGui` forces headless mode even if no other intent flag was set.
		  - `-ConsoleGui` starts the local interactive console menu and never
		    promotes a preset into unattended apply.
		  - Conflicts (e.g. ListPresets + Apply) become Errors with a clear
		    explanation rather than ambiguous behaviour.

		Output object (pscustomobject):
		  Mode         : 'Gui' | 'Headless' | 'ConsoleGui' | 'ListPresets'
		  Apply        : [bool]
		  PresetName   : [string] (empty if not applicable)
		  ConfigPath   : [string] (empty if not applicable)
		  NoGui        : [bool]
		  Warnings     : string[]
		  Errors       : string[]
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[AllowNull()]
		[hashtable]$ParamValues
	)

	$values = if ($ParamValues) { $ParamValues } else { @{} }

	$get = {
		param($key, $default)
		if ($values.ContainsKey($key)) { return $values[$key] }
		return $default
	}.GetNewClosure()

	$listPresets = [bool](& $get 'ListPresets' $false)
	$noGui = [bool](& $get 'NoGui' $false)
	$consoleGui = [bool](& $get 'ConsoleGui' $false)
	$apply = [bool](& $get 'Apply' $false)
	$applyProfile = [bool](& $get 'ApplyProfile' $false)
	$dryRun = [bool](& $get 'DryRun' $false)
	$applyPresetName = [string](& $get 'ApplyPreset' '')
	$configPath = [string](& $get 'ConfigFile' '')
	if ([string]::IsNullOrWhiteSpace($configPath))
	{
		$configPath = [string](& $get 'ProfilePath' '')
	}
	$presetName = $applyPresetName
	if ([string]::IsNullOrWhiteSpace($presetName))
	{
		$presetName = [string](& $get 'Preset' '')
	}

	$warnings = [System.Collections.Generic.List[string]]::new()
	$errors = [System.Collections.Generic.List[string]]::new()

	if ($listPresets -and ($apply -or $applyProfile -or $configPath -or $presetName))
	{
		$errors.Add('-ListPresets cannot be combined with apply / config / preset arguments.')
	}
	if ($listPresets -and $consoleGui)
	{
		$errors.Add('-ListPresets cannot be combined with -ConsoleGui.')
	}

	if ($listPresets)
	{
		return [pscustomobject]@{
			Mode = 'ListPresets'
			Apply = $false
			PresetName = ''
			ConfigPath = ''
			NoGui = $true
			DryRun = $dryRun
			Warnings = @($warnings)
			Errors = @($errors)
		}
	}

	if ($consoleGui)
	{
		if ($noGui)
		{
			$errors.Add('-ConsoleGui cannot be combined with -NoGui. Use -ConsoleGui for the interactive console menu or -NoGui for unattended automation.')
		}
		if ($apply -or $applyProfile -or -not [string]::IsNullOrWhiteSpace($configPath))
		{
			$errors.Add('-ConsoleGui cannot be combined with apply/profile arguments. Use -NoGui for unattended profile automation.')
		}
		if (-not [string]::IsNullOrWhiteSpace($applyPresetName))
		{
			$errors.Add('-ConsoleGui cannot be combined with -ApplyPreset. Use -ConsoleGui -Preset <name> to preselect a preset in the console menu.')
		}

		return [pscustomobject]@{
			Mode = 'ConsoleGui'
			Apply = $false
			PresetName = $presetName
			ConfigPath = ''
			NoGui = $true
			DryRun = $dryRun
			Warnings = @($warnings)
			Errors = @($errors)
		}
	}

	$intentApply = $apply -or $applyProfile

	if (-not [string]::IsNullOrWhiteSpace($configPath) -and -not $intentApply -and -not $dryRun)
	{
		# -ConfigFile alone must not silently load and exit. We promote it to
		# Apply with a warning so the user can see what happened in the log.
		$intentApply = $true
		$warnings.Add(("Config file '{0}' supplied without -Apply/-Run; promoting to apply (use -DryRun to preview only)." -f $configPath))
	}

	if (-not [string]::IsNullOrWhiteSpace($presetName) -and -not $intentApply -and -not $dryRun)
	{
		$intentApply = $true
		$warnings.Add(("Preset '{0}' supplied without -Apply/-Run; promoting to apply (use -DryRun to preview only)." -f $presetName))
	}

	$mode = 'Gui'
	if ($noGui -or $intentApply -or $dryRun -or -not [string]::IsNullOrWhiteSpace($configPath) -or -not [string]::IsNullOrWhiteSpace($presetName))
	{
		$mode = 'Headless'
	}

	return [pscustomobject]@{
		Mode = $mode
		Apply = $intentApply
		PresetName = $presetName
		ConfigPath = $configPath
		NoGui = ($noGui -or $mode -eq 'Headless')
		DryRun = $dryRun
		Warnings = @($warnings)
		Errors = @($errors)
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselineHeadlessExitCode
{
	<#
		.SYNOPSIS
		Maps execution counters to the documented unattended exit codes.

		.DESCRIPTION
		Per todo.md (tracked preset contract):
		  0 = clean (all targets succeeded; no preflight failures)
		  1 = partial (at least one failure but at least one success)
		  2 = preflight fail (preflight blocked the run before any tweak applied)

		Inputs are non-negative integers. Negative values are treated as zero.
		Empty selection (no tweaks applied at all because nothing was selected)
		returns 0 with a separate `Reason` so the caller can log "no tweaks
		selected" — never block, never throw, never pop a dialog.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[int]$Total = 0,

		[Parameter()]
		[int]$Succeeded = 0,

		[Parameter()]
		[int]$Failed = 0,

		[Parameter()]
		[int]$PreflightFailed = 0,

		[Parameter()]
		[int]$Skipped = 0
	)

	if ($Total -lt 0) { $Total = 0 }
	if ($Succeeded -lt 0) { $Succeeded = 0 }
	if ($Failed -lt 0) { $Failed = 0 }
	if ($PreflightFailed -lt 0) { $PreflightFailed = 0 }
	if ($Skipped -lt 0) { $Skipped = 0 }

	if ($PreflightFailed -gt 0 -and $Succeeded -eq 0 -and $Failed -eq 0)
	{
		return [pscustomobject]@{
			ExitCode = 2
			Reason = 'preflight-failed'
		}
	}

	if ($Total -eq 0 -and $Succeeded -eq 0 -and $Failed -eq 0 -and $PreflightFailed -eq 0)
	{
		return [pscustomobject]@{
			ExitCode = 0
			Reason = 'no-tweaks-selected'
		}
	}

	if ($Failed -gt 0 -and $Succeeded -gt 0)
	{
		return [pscustomobject]@{
			ExitCode = 1
			Reason = 'partial'
		}
	}

	if ($Failed -gt 0 -and $Succeeded -eq 0)
	{
		return [pscustomobject]@{
			ExitCode = 1
			Reason = 'all-failed'
		}
	}

	return [pscustomobject]@{
		ExitCode = 0
		Reason = 'clean'
	}
}

<#
    .SYNOPSIS
#>

function Get-BaselinePresetCatalog
{
	<#
		.SYNOPSIS
		Returns a deterministic catalog of presets shipped under
		Module/Data/Presets — the data behind --list-presets.

		.DESCRIPTION
		Walks the supplied preset directory, parses each `.json`/`.txt`
		preset, and returns a sorted array of {Name, EntryCount, Path}.
		Errors parsing a single preset are recorded in the entry's Error
		field rather than thrown — so a corrupt preset cannot break
		--list-presets output for the others.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$PresetDirectory
	)

	if (-not (Test-Path -LiteralPath $PresetDirectory -PathType Container))
	{
		throw "Preset directory not found: $PresetDirectory"
	}

	$out = [System.Collections.Generic.List[pscustomobject]]::new()
	$files = @(Get-ChildItem -LiteralPath $PresetDirectory -File | Where-Object { $_.Extension -in @('.json', '.txt') } | Sort-Object Name)
	foreach ($file in $files)
	{
		$entry = [pscustomobject]@{
			Name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
			EntryCount = 0
			Path = $file.FullName
			Error = $null
		}
		try
		{
			if ($file.Extension -eq '.json')
			{
				$raw = [System.IO.File]::ReadAllText($file.FullName)
				$data = $raw | ConvertFrom-Json -ErrorAction Stop
				if ($data -and $data.PSObject.Properties['Entries'] -and $data.Entries)
				{
					$entry.EntryCount = @($data.Entries).Count
				}
				if ($data -and $data.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$data.Name))
				{
					$entry.Name = [string]$data.Name
				}
			}
			else
			{
				$lines = [System.IO.File]::ReadAllLines($file.FullName)
				$nonEmpty = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not ($_.Trim().StartsWith('#')) })
				$entry.EntryCount = $nonEmpty.Count
			}
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CliMode.Helpers.Get-BaselinePresetCatalog:catch320' -Severity Debug }

			$entry.Error = $_.Exception.Message
		}
		$out.Add($entry)
	}

	return @($out)
}

<#
    .SYNOPSIS
#>

function Format-BaselinePresetCatalog
{
	<#
		.SYNOPSIS
		Formats a preset catalog for `--list-presets` output.

		.DESCRIPTION
		Emits one line per preset with a 2-column "name + entry count" layout,
		padded to align. Catalog entries with an Error field render as
		"<Name>  (error: ...)" so corrupt presets are still visible to the
		operator. Returns a single multi-line string ready for Write-Host.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Catalog
	)

	if (-not $Catalog -or $Catalog.Count -eq 0)
	{
		return 'No presets available.'
	}

	$nameWidth = 0
	foreach ($entry in $Catalog)
	{
		if (-not $entry) { continue }
		$len = [string]$entry.Name
		if ($len.Length -gt $nameWidth) { $nameWidth = $len.Length }
	}
	if ($nameWidth -lt 8) { $nameWidth = 8 }

	$lines = [System.Collections.Generic.List[string]]::new()
	$lines.Add(('{0}  {1}' -f 'PRESET'.PadRight($nameWidth), 'TWEAK COUNT'))
	$lines.Add(('{0}  {1}' -f ('-' * $nameWidth), '-----------'))
	foreach ($entry in $Catalog)
	{
		if (-not $entry) { continue }
		$name = [string]$entry.Name
		if ($entry.Error)
		{
			$lines.Add(('{0}  (error: {1})' -f $name.PadRight($nameWidth), [string]$entry.Error))
		}
		else
		{
			$lines.Add(('{0}  {1}' -f $name.PadRight($nameWidth), [int]$entry.EntryCount))
		}
	}

	return ($lines -join [Environment]::NewLine)
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineCliLogPath
{
	<#
		.SYNOPSIS
		Resolves the `-LogPath` CLI override into an absolute log file path.

		.DESCRIPTION
		Returns the absolute path Baseline should write its session log to,
		given an optional user override and the default path the bootstrap
		would otherwise have used.

		Behaviour:
		  - Empty/whitespace `RequestedPath` → return DefaultPath unchanged
		    with UsedDefault=$true.
		  - Directory-shaped input (ends with `\`/`/`, or already exists as
		    a directory) → join with the DefaultFileName from the bootstrap.
		  - File-shaped input → use verbatim.
		  - Relative paths are resolved against the current working directory
		    (`$PWD`) so unattended runs that pass `--log .\run.log` land
		    where the operator expects.
		  - If the parent directory cannot be created (locked, illegal name,
		    UNC failure), fall back to DefaultPath and surface a warning so
		    the operator can see what happened in the launch trace + log.

		Output object:
		  ResolvedPath : [string]   absolute path the logger should use
		  UsedDefault  : [bool]     true when the override was empty or fell back
		  Warning      : [string]   non-null when the override was rejected
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$RequestedPath,

		[Parameter(Mandatory = $true)]
		[string]$DefaultPath,

		[Parameter(Mandatory = $true)]
		[string]$DefaultFileName,

		[Parameter()]
		[string]$WorkingDirectory
	)

	if ([string]::IsNullOrWhiteSpace($RequestedPath))
	{
		return [pscustomobject]@{
			ResolvedPath = $DefaultPath
			UsedDefault  = $true
			Warning      = $null
		}
	}

	$cwd = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { (Get-Location).ProviderPath } else { $WorkingDirectory }
	$candidate = $RequestedPath.Trim()

	# Treat trailing separators or an existing directory as a folder request.
	$looksLikeDirectory = $candidate.EndsWith('\') -or $candidate.EndsWith('/')
	$absoluteCandidate = $candidate
	try
	{
		if (-not [System.IO.Path]::IsPathRooted($absoluteCandidate))
		{
			$absoluteCandidate = [System.IO.Path]::Combine($cwd, $absoluteCandidate)
		}
		$absoluteCandidate = [System.IO.Path]::GetFullPath($absoluteCandidate)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CliMode.Helpers.Resolve-BaselineCliLogPath:catch463' -Severity Debug }

		return [pscustomobject]@{
			ResolvedPath = $DefaultPath
			UsedDefault  = $true
			Warning      = ("Ignoring -LogPath '{0}': {1}. Falling back to default log path." -f $RequestedPath, $_.Exception.Message)
		}
	}

	if (-not $looksLikeDirectory -and [System.IO.Directory]::Exists($absoluteCandidate))
	{
		$looksLikeDirectory = $true
	}

	if ($looksLikeDirectory)
	{
		$absoluteCandidate = [System.IO.Path]::Combine($absoluteCandidate.TrimEnd([char]'\', [char]'/'), $DefaultFileName)
	}

	$parent = [System.IO.Path]::GetDirectoryName($absoluteCandidate)
	if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent))
	{
		try
		{
			[void][System.IO.Directory]::CreateDirectory($parent)
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'CliMode.Helpers.Resolve-BaselineCliLogPath:catch489' -Severity Debug }

			return [pscustomobject]@{
				ResolvedPath = $DefaultPath
				UsedDefault  = $true
				Warning      = ("Ignoring -LogPath '{0}': cannot create parent directory '{1}' ({2}). Falling back to default log path." -f $RequestedPath, $parent, $_.Exception.Message)
			}
		}
	}

	return [pscustomobject]@{
		ResolvedPath = $absoluteCandidate
		UsedDefault  = $false
		Warning      = $null
	}
}
