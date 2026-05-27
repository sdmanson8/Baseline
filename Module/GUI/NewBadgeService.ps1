$Script:NewBadgeBaseline = $null
$Script:NewBadgeAddedInVersions = $null
$Script:NewBadgeShowEnabled = $true

# Tracks which tweaks were "added in" a version newer than the highest the
# user has seen, so the row factory can paint a NEW badge. Baseline state
# lives in user prefs:
#   - HighestSeenAddedInVersion: highest AddedInVersion in the registry the
#     last time the user opened the GUI. Bumped after each upgrade.
#   - NewBadgeBaseline: the cutoff above which a tweak is "new". Reset to
#     the *previous* HighestSeen on upgrade, so anything tagged with a
#     version > previous-highest renders as new.
# Pristine first run gets baseline 0.0.0 (everything tagged is new).

function ConvertTo-NewBadgeVersion
{
	param ([string]$Raw)
	if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
	$trimmed = $Raw.Trim().TrimStart('v', 'V')
	$parsed = $null
	if ([System.Version]::TryParse($trimmed, [ref]$parsed)) { return $parsed }
	return $null
}

function Get-NewBadgeAddedInVersionsMap
{
	if ($null -ne $Script:NewBadgeAddedInVersions) { return $Script:NewBadgeAddedInVersions }
	$Script:NewBadgeAddedInVersions = @{}
	$dataPath = $null
	if ($Script:GuiExtractedRoot)
	{
		# Module/Data is a sibling of Module/GUI in the runtime layout.
		$candidate = Join-Path (Split-Path -Path $Script:GuiExtractedRoot -Parent) 'Data\AddedInVersions.json'
		if (Test-Path -LiteralPath $candidate) { $dataPath = $candidate }
	}
	if (-not $dataPath)
	{
		$candidate = Join-Path $PSScriptRoot '..\Data\AddedInVersions.json'
		if (Test-Path -LiteralPath $candidate) { $dataPath = (Resolve-Path -LiteralPath $candidate).Path }
	}
	if (-not $dataPath) { return $Script:NewBadgeAddedInVersions }
	try
	{
		$raw = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return $Script:NewBadgeAddedInVersions }
		$parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
		if (-not $parsed -or -not $parsed.Functions) { return $Script:NewBadgeAddedInVersions }
		foreach ($prop in $parsed.Functions.PSObject.Properties)
		{
			$version = ConvertTo-NewBadgeVersion -Raw ([string]$prop.Value)
			if ($version) { $Script:NewBadgeAddedInVersions[[string]$prop.Name] = $version }
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'NewBadgeService.PopulateAddedInVersions' }
	return $Script:NewBadgeAddedInVersions
}

function Initialize-NewBadgeService
{
	param ([string]$BaselineVersion)

	$map = Get-NewBadgeAddedInVersionsMap
	$Script:NewBadgeShowEnabled = [bool](Get-BaselineUserPreference -Key 'ShowNewBadges' -Default $true)

	$highestInRegistry = $null
	foreach ($v in $map.Values)
	{
		if ($null -eq $highestInRegistry -or $v -gt $highestInRegistry) { $highestInRegistry = $v }
	}

	$storedHighestRaw = [string](Get-BaselineUserPreference -Key 'HighestSeenAddedInVersion' -Default '')
	$storedBaselineRaw = [string](Get-BaselineUserPreference -Key 'NewBadgeBaseline' -Default '')
	$storedHighest = ConvertTo-NewBadgeVersion -Raw $storedHighestRaw
	$storedBaseline = ConvertTo-NewBadgeVersion -Raw $storedBaselineRaw

	if (-not $storedHighest -or -not $storedBaseline)
	{
		# Pristine state — treat every tagged tweak as new on first launch
		# so users discover features added before they installed.
		$Script:NewBadgeBaseline = [System.Version]::new(0, 0, 0)
		if ($highestInRegistry)
		{
			Set-BaselineUserPreference -Key 'HighestSeenAddedInVersion' -Value ($highestInRegistry.ToString())
		}
		Set-BaselineUserPreference -Key 'NewBadgeBaseline' -Value ($Script:NewBadgeBaseline.ToString())
		return
	}

	if ($highestInRegistry -and $highestInRegistry -gt $storedHighest)
	{
		# Effective upgrade — reveal what arrived between previous-highest
		# and current-highest, and re-enable the badge if user dismissed it.
		$Script:NewBadgeBaseline = $storedHighest
		Set-BaselineUserPreference -Key 'HighestSeenAddedInVersion' -Value ($highestInRegistry.ToString())
		Set-BaselineUserPreference -Key 'NewBadgeBaseline' -Value ($storedHighest.ToString())
		Set-BaselineUserPreference -Key 'ShowNewBadges' -Value $true
		$Script:NewBadgeShowEnabled = $true
		return
	}

	$Script:NewBadgeBaseline = $storedBaseline
}

function Test-IsTweakNew
{
	param ([string]$FunctionName)
	if (-not $Script:NewBadgeShowEnabled) { return $false }
	if ([string]::IsNullOrWhiteSpace($FunctionName)) { return $false }
	if ($null -eq $Script:NewBadgeAddedInVersions) { return $false }
	if (-not $Script:NewBadgeAddedInVersions.ContainsKey($FunctionName)) { return $false }
	$v = $Script:NewBadgeAddedInVersions[$FunctionName]
	if (-not $v) { return $false }
	$baseline = $Script:NewBadgeBaseline
	if (-not $baseline) { $baseline = [System.Version]::new(0, 0, 0) }
	return ($v -gt $baseline)
}
