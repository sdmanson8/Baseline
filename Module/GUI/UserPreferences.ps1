$Script:UserPreferencesPath = $null
$Script:UserPreferencesData = $null
$Script:UserPreferencesDirty = $false

# Lightweight JSON pref store keyed by string. Used by the startup
# orchestrator to remember one-shot completions (initial backup done,
# script migration done) and the NEW-badge baseline across launches.
# Distinct from Baseline-last-session.json which tracks transient GUI
# state — these prefs persist forever and are only written when changed.

function Get-BaselineUserPreferencesPath
{
	if ($Script:UserPreferencesPath) { return $Script:UserPreferencesPath }
	$baseDir = Join-Path $env:LOCALAPPDATA 'Baseline'
	$profileDir = Join-Path $baseDir 'UserState'
	$profileDir = Join-Path $profileDir 'Profiles'
	$Script:UserPreferencesPath = Join-Path $profileDir 'Baseline-user-prefs.json'
	return $Script:UserPreferencesPath
}

function Initialize-BaselineUserPreferences
{
	if ($null -ne $Script:UserPreferencesData) { return }
	$Script:UserPreferencesData = @{}
	$Script:UserPreferencesDirty = $false
	$path = Get-BaselineUserPreferencesPath
	if (-not (Test-Path -LiteralPath $path)) { return }
	try
	{
		$raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return }
		$parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
		if (-not $parsed -or -not $parsed.Values) { return }
		foreach ($prop in $parsed.Values.PSObject.Properties)
		{
			$Script:UserPreferencesData[[string]$prop.Name] = $prop.Value
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'UserPreferences.Initialize.LoadJson' }
}

function Get-BaselineUserPreference
{
	param (
		[Parameter(Mandatory = $true)][string]$Key,
		[object]$Default = $null
	)
	Initialize-BaselineUserPreferences
	if ($Script:UserPreferencesData.ContainsKey($Key))
	{
		return $Script:UserPreferencesData[$Key]
	}
	return $Default
}

function Set-BaselineUserPreference
{
	param (
		[Parameter(Mandatory = $true)][string]$Key,
		[object]$Value
	)
	Initialize-BaselineUserPreferences
	$existing = $null
	if ($Script:UserPreferencesData.ContainsKey($Key)) { $existing = $Script:UserPreferencesData[$Key] }
	if ($existing -ne $Value)
	{
		$Script:UserPreferencesData[$Key] = $Value
		$Script:UserPreferencesDirty = $true
		Save-BaselineUserPreferences
	}
}

function Normalize-GuiLogLevel
{
	param (
		[AllowNull()]
		[object]$Level,
		[string]$Default = 'All'
	)

	$defaultValue = if ([string]::IsNullOrWhiteSpace($Default)) { 'All' } else { [string]$Default }
	$value = if ($null -eq $Level) { '' } else { ([string]$Level).Trim() }
	if ([string]::IsNullOrWhiteSpace($value))
	{
		$value = $defaultValue
	}

	switch ($value.ToLowerInvariant())
	{
		'all' { return 'All' }
		'trace' { return 'Trace' }
		'debug' { return 'Debug' }
		'info' { return 'Info' }
		'information' { return 'Info' }
		'warn' { return 'Warn' }
		'warning' { return 'Warn' }
		'error' { return 'Error' }
		default
		{
			if ($value -ne $defaultValue)
			{
				return (Normalize-GuiLogLevel -Level $defaultValue -Default 'All')
			}

			return 'All'
		}
	}
}

function Save-BaselineUserPreferences
{
	if ($null -eq $Script:UserPreferencesData) { return }
	if (-not $Script:UserPreferencesDirty) { return }
	try
	{
		$path = Get-BaselineUserPreferencesPath
		$dir = Split-Path -Path $path -Parent
		if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }
		$values = New-Object System.Collections.Specialized.OrderedDictionary
		foreach ($key in ($Script:UserPreferencesData.Keys | Sort-Object))
		{
			$values[$key] = $Script:UserPreferencesData[$key]
		}
		$payload = [pscustomobject]@{
			Schema        = 'Baseline.UserPreferences'
			SchemaVersion = 1
			SavedAtUtc    = ([DateTime]::UtcNow.ToString('o'))
			Values        = $values
		}
		$json = $payload | ConvertTo-Json -Depth 6
		[System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)
		$Script:UserPreferencesDirty = $false
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'UserPreferences.Save.WriteJson' }
}
