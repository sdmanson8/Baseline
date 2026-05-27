$Script:DetectCache = $null
$Script:DetectCacheDirty = $false
$Script:DetectCachePath = $null
$Script:DetectCacheVersion = $null

# Persistent cache of `$Tweak.Detect` results keyed by `$Tweak.Function`.
# Detect scriptblocks read live system state (registry, services, files) and
# can take 50-150 ms each — over 100+ rows that dominates the per-tab build
# time. Caching the most recent detection result on disk lets the next launch
# skip the live probe and paint tabs in <2 s. Cache is invalidated on app
# version change so detection logic updates take effect on first launch.

function Initialize-GuiDetectCache
{
	param ([string]$BaselineVersion)

	if ($Script:DetectCache) { return }

	$Script:DetectCacheVersion = if ($BaselineVersion) { [string]$BaselineVersion } else { 'unknown' }
	$baseDir = Join-Path $env:LOCALAPPDATA 'Baseline'
	$Script:DetectCachePath = Join-Path $baseDir 'detect-cache.json'
	$Script:DetectCache = @{}
	$Script:DetectCacheDirty = $false

	if (-not (Test-Path -LiteralPath $Script:DetectCachePath)) { return }

	try
	{
		$raw = [System.IO.File]::ReadAllText($Script:DetectCachePath, [System.Text.Encoding]::UTF8)
		if ([string]::IsNullOrWhiteSpace($raw)) { return }
		$parsed = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
		if (-not $parsed) { return }
		# Invalidate the entire cache when the app version changes — a
		# revised Detect scriptblock could now return different values for
		# the same system state, and serving stale results from the prior
		# version would mislead the user.
		if (([string]$parsed.version) -ne $Script:DetectCacheVersion) { return }
		if (-not $parsed.results) { return }
		foreach ($prop in $parsed.results.PSObject.Properties)
		{
			if ($null -ne $prop.Value) { $Script:DetectCache[[string]$prop.Name] = [bool]$prop.Value }
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DetectCache.Load.ParseJson' }
}

function Get-CachedDetection
{
	param ([string]$Function)
	if (-not $Function -or -not $Script:DetectCache) { return $null }
	if ($Script:DetectCache.ContainsKey($Function)) { return [bool]$Script:DetectCache[$Function] }
	return $null
}

function Set-CachedDetection
{
	param (
		[string]$Function,
		[bool]$Value
	)
	if (-not $Function -or -not $Script:DetectCache) { return }
	$existing = $null
	if ($Script:DetectCache.ContainsKey($Function)) { $existing = [bool]$Script:DetectCache[$Function] }
	if ($existing -ne $Value)
	{
		$Script:DetectCache[$Function] = $Value
		$Script:DetectCacheDirty = $true
	}
	elseif (-not $Script:DetectCache.ContainsKey($Function))
	{
		$Script:DetectCache[$Function] = $Value
		$Script:DetectCacheDirty = $true
	}
}

function Save-GuiDetectCache
{
	if (-not $Script:DetectCache -or -not $Script:DetectCachePath) { return }
	if (-not $Script:DetectCacheDirty) { return }
	try
	{
		$baseDir = Split-Path -Path $Script:DetectCachePath -Parent
		if (-not (Test-Path -LiteralPath $baseDir)) { $null = New-Item -Path $baseDir -ItemType Directory -Force }
		$results = New-Object System.Collections.Specialized.OrderedDictionary
		foreach ($key in ($Script:DetectCache.Keys | Sort-Object))
		{
			$results[$key] = [bool]$Script:DetectCache[$key]
		}
		$payload = [pscustomobject]@{
			version   = $Script:DetectCacheVersion
			savedAtUtc = ([DateTime]::UtcNow.ToString('o'))
			results   = $results
		}
		$json = $payload | ConvertTo-Json -Depth 4 -Compress
		[System.IO.File]::WriteAllText($Script:DetectCachePath, $json, [System.Text.Encoding]::UTF8)
		$Script:DetectCacheDirty = $false
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'DetectCache.Save.WriteJson' }
}
