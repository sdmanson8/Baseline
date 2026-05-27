# Review Mode helpers — pure diff and acceptance logic for the
# per-setting review banner pattern modelled on the tracked review mode.
#
# It uses `Compare-ConfigurationProfiles` (ConfigProfile.Helpers.ps1), which
# returns category buckets (OnlyInA / OnlyInB / Different / Same) that are
# perfect for a "two profiles compared" report but are awkward to bind to a
# row-per-setting UI. Review Mode needs a flat, ordered list keyed by entry
# Id with a single Action verb per row so the GUI can render one checkbox /
# accept-reject control per item.
#
# These review helpers provide:
#   - Compare-BaselineConfigForReview : produces the flat diff
#   - Get-BaselineConfigReviewSummary : Accept-All / Reject-All counts
#   - Resolve-BaselineConfigReviewDecisions : filters the diff to the
#     entries that should actually be applied given a set of decisions
#
# These are *pure* helpers. The GUI in Module/GUI/ReviewMode.ps1 (separate
# slice) wraps them with WPF and the execution orchestrator wires the
# accepted set into the existing apply pipeline.

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineReviewEntryKey
{
	<#
		.SYNOPSIS
		Returns the stable identity key for a config entry (Id → Function →
		Name fallback). Empty string when nothing is identifying.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter()][object]$Entry)

	if ($null -eq $Entry) { return '' }
	foreach ($field in @('Id', 'Function', 'Name'))
	{
		if ($Entry.PSObject -and $Entry.PSObject.Properties[$field])
		{
			$candidate = [string]$Entry.$field
			if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate.Trim() }
		}
	}
	return ''
}

<#
    .SYNOPSIS
#>

function ConvertTo-BaselineReviewValueText
{
	<#
		.SYNOPSIS
		Renders an entry's value (Param/Value/NumericValue/ACValue+DCValue)
		into a stable display string used both for change detection and for
		the per-row "Current → Imported" rendering.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ([Parameter()][object]$Entry)

	if ($null -eq $Entry) { return '' }
	# Don't wrap $Entry.PSObject.Properties in an if-expression — PowerShell
	# re-collects its enumerable result into an Object[], which destroys the
	# string-indexer (PSMemberInfoIntegratingCollection) we rely on for
	# property lookups.
	if (-not $Entry.PSObject) { return '' }
	$props = $Entry.PSObject.Properties

	$ac = $null
	$dc = $null
	if ($props['ACValue']) { $ac = [string]$Entry.ACValue }
	if ($props['DCValue']) { $dc = [string]$Entry.DCValue }
	if ($null -ne $ac -or $null -ne $dc)
	{
		if ($null -ne $ac -and $null -ne $dc -and $ac -eq $dc) { return $ac }
		$acPart = if ($null -ne $ac) { "AC:$ac" } else { '' }
		$dcPart = if ($null -ne $dc) { "DC:$dc" } else { '' }
		return ($acPart, $dcPart | Where-Object { $_ }) -join ';'
	}

	foreach ($field in @('Value', 'NumericValue', 'SelectedValue', 'Param'))
	{
		if (-not $props[$field]) { continue }
		$v = $Entry.$field
		# Skip a present-but-null field and fall through to the next candidate.
		# JSON-imported Toggle entries carry both `Param` (the real value) and
		# `Value: null`; treating null as "" would mask the Param and turn every
		# Toggle into a Same/Empty row.
		if ($null -eq $v) { continue }
		if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string]))
		{
			return (@($v | ForEach-Object { [string]$_ }) -join ',')
		}
		return [string]$v
	}
	return ''
}

<#
    .SYNOPSIS
#>

function Compare-BaselineConfigForReview
{
	<#
		.SYNOPSIS
		Per-setting diff between a Current state and an Imported config,
		flattened to one row per logical entry.

		.DESCRIPTION
		Each output element:
		  Id           : stable key (Id / Function / Name)
		  Function     : raw function name (echoed for convenience)
		  Type         : entry type if declared (Toggle/Choice/NumericRange/Date)
		  CurrentEntry : the matching entry from -Current ($null when missing)
		  ImportedEntry: the matching entry from -Imported ($null when missing)
		  CurrentValue : display string (empty when missing)
		  ImportedValue: display string (empty when missing)
		  Action       : 'Add' | 'Remove' | 'Change' | 'Same'
		  GatedBy      : echoed as-is from Imported.GatedBy when present —
		                 the GUI uses it to render a parent-toggle hint
		                 *without* disabling the row (the review trap).

		Order: Imported first, then Current-only entries appended at the end
		so the user reads the imported intent in its declared order.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter()][AllowNull()][object]$Current,
		[Parameter()][AllowNull()][object]$Imported
	)

	$currentEntries = @()
	if ($null -ne $Current -and $Current.PSObject -and $Current.PSObject.Properties['Entries'] -and $null -ne $Current.Entries)
	{
		$currentEntries = @($Current.Entries)
	}
	elseif ($Current -is [System.Collections.IEnumerable] -and -not ($Current -is [string]))
	{
		$currentEntries = @($Current)
	}

	$importedEntries = @()
	if ($null -ne $Imported -and $Imported.PSObject -and $Imported.PSObject.Properties['Entries'] -and $null -ne $Imported.Entries)
	{
		$importedEntries = @($Imported.Entries)
	}
	elseif ($Imported -is [System.Collections.IEnumerable] -and -not ($Imported -is [string]))
	{
		$importedEntries = @($Imported)
	}

	$currentIndex = [ordered]@{}
	foreach ($e in $currentEntries)
	{
		$key = ConvertTo-BaselineReviewEntryKey -Entry $e
		if ($key) { $currentIndex[$key] = $e }
	}

	$importedIndex = [ordered]@{}
	foreach ($e in $importedEntries)
	{
		$key = ConvertTo-BaselineReviewEntryKey -Entry $e
		if ($key) { $importedIndex[$key] = $e }
	}

	$rows = [System.Collections.Generic.List[object]]::new()
	$emittedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($key in $importedIndex.Keys)
	{
		$importedEntry = $importedIndex[$key]
		$currentEntry = if ($currentIndex.Contains($key)) { $currentIndex[$key] } else { $null }
		$importedValue = ConvertTo-BaselineReviewValueText -Entry $importedEntry
		$currentValue = ConvertTo-BaselineReviewValueText -Entry $currentEntry

		$action = if ($null -eq $currentEntry) { 'Add' }
			elseif ($currentValue -eq $importedValue) { 'Same' }
			else { 'Change' }

		$rows.Add([pscustomobject]@{
			Id            = $key
			Function      = if ($importedEntry.PSObject.Properties['Function']) { [string]$importedEntry.Function } else { $key }
			Type          = if ($importedEntry.PSObject.Properties['Type']) { [string]$importedEntry.Type } else { '' }
			CurrentEntry  = $currentEntry
			ImportedEntry = $importedEntry
			CurrentValue  = $currentValue
			ImportedValue = $importedValue
			Action        = $action
			GatedBy       = if ($importedEntry.PSObject.Properties['GatedBy']) { [string]$importedEntry.GatedBy } else { $null }
		})
		[void]$emittedKeys.Add($key)
	}

	foreach ($key in $currentIndex.Keys)
	{
		if ($emittedKeys.Contains($key)) { continue }
		$currentEntry = $currentIndex[$key]
		$rows.Add([pscustomobject]@{
			Id            = $key
			Function      = if ($currentEntry.PSObject.Properties['Function']) { [string]$currentEntry.Function } else { $key }
			Type          = if ($currentEntry.PSObject.Properties['Type']) { [string]$currentEntry.Type } else { '' }
			CurrentEntry  = $currentEntry
			ImportedEntry = $null
			CurrentValue  = (ConvertTo-BaselineReviewValueText -Entry $currentEntry)
			ImportedValue = ''
			Action        = 'Remove'
			GatedBy       = $null
		})
	}

	return ,@($rows.ToArray())
}

<#
    .SYNOPSIS
#>

function Get-BaselineConfigReviewSummary
{
	<#
		.SYNOPSIS
		Returns aggregate counts for the Review Mode banner — Total, Add,
		Remove, Change, Same — so the GUI can render "Accept all 12
		changes" / "5 unchanged" without re-walking the rows itself.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ([Parameter()][AllowNull()][object[]]$Diff)

	$rows = if ($null -eq $Diff) { @() } else { @($Diff) }
	$add    = 0
	$remove = 0
	$change = 0
	$same   = 0
	foreach ($row in $rows)
	{
		if (-not $row -or -not $row.PSObject.Properties['Action']) { continue }
		switch ([string]$row.Action)
		{
			'Add'    { $add++ }
			'Remove' { $remove++ }
			'Change' { $change++ }
			'Same'   { $same++ }
		}
	}
	return [pscustomobject]@{
		Total       = $rows.Count
		Add         = $add
		Remove      = $remove
		Change      = $change
		Same        = $same
		Actionable  = $add + $remove + $change
	}
}

<#
    .SYNOPSIS
#>

function Resolve-BaselineConfigReviewDecisions
{
	<#
		.SYNOPSIS
		Given a diff and a set of per-row decisions ({ Id; Decision }),
		returns the entries that should actually be applied.

		.DESCRIPTION
		-Decisions is a hashtable / ordered dictionary / array of
		`[pscustomobject]@{ Id = '...'; Decision = 'Accept' | 'Reject' }`.
		-DefaultDecision sets the verdict for any row not mentioned
		('Reject' by default — fail-safe). 'Same' rows are filtered out
		regardless because re-applying a no-op produces noise without
		value, and the original implementation does the same.

		Returns:
		  Accepted : @(ImportedEntry, ...) — the array the orchestrator
		             feeds to its existing apply pipeline. Order is
		             preserved from the diff and reviewed separately from
		             order, then current-only).
		  Rejected : @(Id, ...) — informational; the GUI uses this for
		             the "12 of 18 applied" footer.
		  Skipped  : @(Id, ...) — 'Same' rows that were dropped because
		             they would be a no-op.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()][AllowNull()][object[]]$Diff,
		[Parameter()][AllowNull()][object]$Decisions,
		[Parameter()]
		[ValidateSet('Accept', 'Reject')]
		[string]$DefaultDecision = 'Reject'
	)

	$decisionMap = @{}
	if ($null -ne $Decisions)
	{
		if ($Decisions -is [System.Collections.IDictionary])
		{
			foreach ($k in $Decisions.Keys)
			{
				$decisionMap[[string]$k] = [string]$Decisions[$k]
			}
		}
		elseif ($Decisions -is [System.Collections.IEnumerable] -and -not ($Decisions -is [string]))
		{
			foreach ($d in $Decisions)
			{
				if (-not $d) { continue }
				if ($d.PSObject.Properties['Id'] -and $d.PSObject.Properties['Decision'])
				{
					$decisionMap[[string]$d.Id] = [string]$d.Decision
				}
			}
		}
	}

	$accepted = [System.Collections.Generic.List[object]]::new()
	$rejected = [System.Collections.Generic.List[string]]::new()
	$skipped  = [System.Collections.Generic.List[string]]::new()

	foreach ($row in @($Diff))
	{
		if (-not $row) { continue }
		$id = [string]$row.Id
		$action = [string]$row.Action

		if ($action -eq 'Same')
		{
			$skipped.Add($id)
			continue
		}

		$verdict = if ($decisionMap.ContainsKey($id)) { $decisionMap[$id] } else { $DefaultDecision }
		if ($verdict -eq 'Accept')
		{
			# Add/Change → use the Imported entry. Remove → still emit the
			# imported "absent" intent by sending a synthetic entry with
			# no Param so the orchestrator's apply pipeline (which uses the
			# existing Param semantics) treats it as a reset.
			$emit = if ($null -ne $row.ImportedEntry) { $row.ImportedEntry } else {
				[pscustomobject]@{ Id = $id; Function = $row.Function; Action = 'Remove' }
			}
			$accepted.Add($emit)
		}
		else
		{
			$rejected.Add($id)
		}
	}

	return [pscustomobject]@{
		Accepted = @($accepted.ToArray())
		Rejected = @($rejected.ToArray())
		Skipped  = @($skipped.ToArray())
	}
}
