# Game Mode helper slice for Baseline.
# Extracted from Manifest.Helpers.ps1 - contains all Game Mode profile,
# allowlist, decision prompt, selection, and plan-building logic.
#
# Dependencies (from Manifest.Helpers.ps1, loaded first):
#   Get-TweakManifestEntryValue, Test-TweakManifestEntryField,
#   Import-TweakManifestFromData, Get-TweakManifestDefaultCommand,
#   Get-ManifestEntryByFunction

function Get-GameModeAllowlist
{
	<# .SYNOPSIS Returns the array of function names approved for Game Mode. #>
	return @(
		'GPUScheduling'
		'XboxGameBar'
		'XboxGameTips'
		'FullscreenOptimizations'
		'MultiplaneOverlay'
		'NetworkAdaptersSavePower'
		'PowerPlan'
		'SleepTimeout'
		'GameDVR'
		'WindowsGameMode'
		'MouseAcceleration'
		'NaglesAlgorithm'
	)
}

function Write-GameModeDataWarning
{
	<# .SYNOPSIS Writes a Game Mode data warning via LogWarning or Write-Warning. #>
	param ([string]$Message)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
	{
		LogWarning $Message
	}
	else
	{
		Write-Warning $Message
	}
}

function Read-GameModeJsonDataFile
{
	<# .SYNOPSIS Reads and parses a Game Mode JSON data file with error handling. #>
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[string]$Label = 'Game Mode data file'
	)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		Write-GameModeDataWarning "$Label not found: $Path"
		return $null
	}

	try
	{
		$jsonContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
	}
	catch
	{
		Write-GameModeDataWarning "Failed to read $Label '$Path': $($_.Exception.Message)"
		return $null
	}

	if ([string]::IsNullOrWhiteSpace($jsonContent))
	{
		Write-GameModeDataWarning "$Label '$Path' is empty."
		return $null
	}

	try
	{
		return ($jsonContent | ConvertFrom-Json -ErrorAction Stop)
	}
	catch
	{
		Write-GameModeDataWarning "Failed to parse $Label '$Path': $($_.Exception.Message)"
		return $null
	}
}

function Get-GameModeReviewedCrossCategoryAllowlist
{
	<# .SYNOPSIS Returns the subset of allowlist entries reviewed for cross-category use. #>
	return @(
		'NetworkAdaptersSavePower'
		'PowerPlan'
		'SleepTimeout'
	)
}

function Import-GameModeAllowlistData
{
	<# .SYNOPSIS Loads Game Mode allowlist metadata from JSON with caching. #>
	param ([string]$ModuleRoot, [switch]$Force)

	# Return cached data if available. Pass -Force to re-read from disk (e.g., after
	# a data file edit during the same session). All three Import-GameMode*Data
	# functions share this pattern.
	if ($null -ne $Script:CachedGameModeAllowlistData -and -not $Force)
	{
		return $Script:CachedGameModeAllowlistData
	}

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$dataDir = Join-Path (Join-Path $resolvedRoot 'Data') 'GameMode'
	$allowlistFile = Join-Path -Path $dataDir -ChildPath 'GameModeAllowlist.json'
	if (-not (Test-Path -LiteralPath $allowlistFile))
	{
		$Script:CachedGameModeAllowlistData = @{}
		return @{}
	}

	$data = Read-GameModeJsonDataFile -Path $allowlistFile -Label 'Game Mode allowlist'
	if (-not $data -or -not $data.Entries)
	{
		$Script:CachedGameModeAllowlistData = @{}
		return @{}
	}

	$lookup = @{}
	foreach ($entry in $data.Entries)
	{
		$fn = [string]$entry.Function
		if (-not [string]::IsNullOrWhiteSpace($fn))
		{
			$lookup[$fn] = $entry
		}
	}

	$Script:CachedGameModeAllowlistData = $lookup
	return $lookup
}

function Import-GameModeAdvancedData
{
	<# .SYNOPSIS Loads Game Mode advanced options data from JSON with caching. #>
	param ([string]$ModuleRoot, [switch]$Force)

	if ($null -ne $Script:CachedGameModeAdvancedData -and -not $Force)
	{
		return $Script:CachedGameModeAdvancedData
	}

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$dataDir = Join-Path (Join-Path $resolvedRoot 'Data') 'GameMode'
	$advancedFile = Join-Path -Path $dataDir -ChildPath 'GameModeAdvanced.json'
	if (-not (Test-Path -LiteralPath $advancedFile))
	{
		$Script:CachedGameModeAdvancedData = @()
		return @()
	}

	$data = Read-GameModeJsonDataFile -Path $advancedFile -Label 'Game Mode advanced options'
	if (-not $data -or -not $data.Entries)
	{
		$Script:CachedGameModeAdvancedData = @()
		return @()
	}

	$Script:CachedGameModeAdvancedData = @($data.Entries)
	return @($data.Entries)
}

function Get-GameModeAdvancedFunctions
{
	<# .SYNOPSIS Returns AdvancedOnly function names from Game Mode advanced data. #>
	$entries = @(Import-GameModeAdvancedData)
	# Only return AdvancedOnly entries - these are excluded from the standard profile plan
	# and handled exclusively by the advanced options panel.
	# Non-AdvancedOnly entries (WindowsGameMode, XboxGameBar) remain in the standard plan
	# via allowlist/profile defaults and appear in the advanced panel only when not already
	# covered by the core plan for the current profile.
	return @(
		$entries |
			Where-Object { $_.PSObject.Properties['AdvancedOnly'] -and [bool]$_.AdvancedOnly } |
			ForEach-Object { [string]$_.Function } |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
	)
}

function Resolve-GameModeAllowlistToggleParam
{
	<# .SYNOPSIS Resolves the toggle parameter for an allowlist entry by profile. #>
	param (
		[object]$AllowlistEntry,
		[object]$ManifestEntry,
		[string]$ProfileName
	)

	if ($null -eq $AllowlistEntry -or [string]::IsNullOrWhiteSpace($ProfileName))
	{
		return $null
	}

	$applyValue = $null
	if ($AllowlistEntry.PSObject.Properties['ApplyValueByProfile'] -and
		$AllowlistEntry.ApplyValueByProfile.PSObject.Properties[$ProfileName])
	{
		$applyValue = $AllowlistEntry.ApplyValueByProfile.$ProfileName
	}

	if ($null -eq $applyValue)
	{
		return $null
	}

	# String value = direct param (e.g., "High" for PowerPlan Choice entries)
	if ($applyValue -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$applyValue))
	{
		return [string]$applyValue
	}

	# Boolean false = not included for this profile
	if (-not [bool]$applyValue)
	{
		return $null
	}

	# Boolean true = included; check for explicit choice value override
	if ($AllowlistEntry.PSObject.Properties['ApplyChoiceValueByProfile'] -and
		$AllowlistEntry.ApplyChoiceValueByProfile.PSObject.Properties[$ProfileName])
	{
		return [string]$AllowlistEntry.ApplyChoiceValueByProfile.$ProfileName
	}

	# Fall back to OffParam for Toggle entries.
	# For non-Toggle entries (Choice/Action) that reach here, OffParam may be null -
	# the cast to [string] produces an empty string, which callers treat as "no param override".
	return [string](Get-TweakManifestEntryValue -Entry $ManifestEntry -FieldName 'OffParam')
}

function Get-GameModeEntryScopeCategory
{
	<# .SYNOPSIS Returns the scope category from an entry's SourceRegion or Category. #>
	param (
		[object]$Entry
	)

	if ($null -eq $Entry)
	{
		return $null
	}

	$sourceRegion = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'SourceRegion')
	if (-not [string]::IsNullOrWhiteSpace($sourceRegion))
	{
		return $sourceRegion
	}

	$categoryName = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Category')
	if (-not [string]::IsNullOrWhiteSpace($categoryName))
	{
		return $categoryName
	}

	return $null
}

function Test-GameModeAllowlistEntryReviewed
{
	<# .SYNOPSIS Tests whether an entry is in the reviewed allowlist. #>
	param (
		[object]$Entry
	)

	if ($null -eq $Entry)
	{
		return $false
	}

	$functionName = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Function')
	if ([string]::IsNullOrWhiteSpace($functionName))
	{
		return $false
	}

	$scopeCategory = Get-GameModeEntryScopeCategory -Entry $Entry
	if ([string]::IsNullOrWhiteSpace($scopeCategory) -or $scopeCategory -eq 'Gaming')
	{
		return $true
	}

	return (@(Get-GameModeReviewedCrossCategoryAllowlist) -contains $functionName)
}

function Test-GameModeProfileDefaultEligible
{
	<# .SYNOPSIS Tests whether an entry qualifies for Game Mode profile defaults. #>
	param (
		[object]$Entry
	)

	if (-not (Test-GameModeAllowlistEntryReviewed -Entry $Entry))
	{
		return $false
	}

	$typeValue = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Type')
	if ($typeValue -ne 'Toggle')
	{
		return $false
	}

	$riskValue = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Risk')
	if ($riskValue -ne 'Low')
	{
		return $false
	}

	$safeValue = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Safe'
	if ($null -eq $safeValue -or -not [bool]$safeValue)
	{
		return $false
	}

	$workflowSensitivityValue = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'WorkflowSensitivity')
	if ([string]::IsNullOrWhiteSpace($workflowSensitivityValue))
	{
		$workflowSensitivityValue = 'Low'
	}

	return ($workflowSensitivityValue -eq 'Low')
}

function Test-GameModeManifestDefaultEnabled
{
	<# .SYNOPSIS Tests whether a manifest entry has Game Mode defaults enabled. #>
	param (
		[object]$Entry
	)

	if ($null -eq $Entry)
	{
		return $false
	}

	$gameModeDefaultValue = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'GameModeDefault'
	if ($null -ne $gameModeDefaultValue -and [bool]$gameModeDefaultValue)
	{
		return $true
	}

	$profileDefaults = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'GameModeDefaultByProfile'
	if ($null -eq $profileDefaults)
	{
		return $false
	}

	if ($profileDefaults -is [System.Collections.IDictionary])
	{
		foreach ($profileKey in $profileDefaults.Keys)
		{
			if ([bool]$profileDefaults[$profileKey])
			{
				return $true
			}
		}
	}
	elseif ($profileDefaults.PSObject)
	{
		foreach ($property in $profileDefaults.PSObject.Properties)
		{
			if ([bool]$property.Value)
			{
				return $true
			}
		}
	}

	return $false
}

function Import-GameModeProfileData
{
	<# .SYNOPSIS Loads Game Mode profile definitions from JSON with caching. #>
	param ([string]$ModuleRoot, [switch]$Force)

	if ($null -ne $Script:CachedGameModeProfileData -and -not $Force)
	{
		return $Script:CachedGameModeProfileData
	}

	$resolvedRoot = if ($ModuleRoot) { $ModuleRoot } else { $Script:SharedHelpersModuleRoot }
	$dataDir = Join-Path (Join-Path $resolvedRoot 'Data') 'GameMode'
	$profileFile = Join-Path -Path $dataDir -ChildPath 'GameModeProfiles.json'
	if (-not (Test-Path -LiteralPath $profileFile))
	{
		$Script:CachedGameModeProfileData = @()
		return @()
	}

	$data = Read-GameModeJsonDataFile -Path $profileFile -Label 'Game Mode profile definitions'
	if (-not $data -or -not $data.Entries)
	{
		$Script:CachedGameModeProfileData = @()
		return @()
	}

	$Script:CachedGameModeProfileData = @($data.Entries)
	return @($data.Entries)
}

function Get-GameModeProfileDefinitions
{
	<# .SYNOPSIS Returns cached Game Mode profile definitions. #>
	return @(Import-GameModeProfileData)
}

function Get-GameModeDecisionPromptKeyCatalog
{
	<# .SYNOPSIS Returns the array of valid decision prompt keys. #>
	return @(
		'GPUScheduling'
		'GameBar'
		'GameBarTips'
		'FullscreenOptimizations'
		'MultiplaneOverlay'
		'NetworkAdaptersSavePower'
		'GameDVR'
		'WindowsGameMode'
		'MouseAcceleration'
		'NaglesAlgorithm'
	)
}

function Test-GameModeProfileDefaultSelection
{
	<# .SYNOPSIS Tests whether an entry is selected by default for a profile. #>
	param (
		[object]$Entry,
		[string]$ProfileName
	)

	if ($null -eq $Entry -or [string]::IsNullOrWhiteSpace($ProfileName))
	{
		return $false
	}

	if (-not (Test-GameModeProfileDefaultEligible -Entry $Entry))
	{
		return $false
	}

	$profileDefaults = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'GameModeDefaultByProfile'
	if ($null -ne $profileDefaults)
	{
		if ($profileDefaults -is [System.Collections.IDictionary] -and $profileDefaults.Contains($ProfileName))
		{
			return [bool]$profileDefaults[$ProfileName]
		}
		if ($profileDefaults.PSObject -and $profileDefaults.PSObject.Properties[$ProfileName])
		{
			return [bool]$profileDefaults.$ProfileName
		}
	}

	$gameModeDefaultValue = Get-TweakManifestEntryValue -Entry $Entry -FieldName 'GameModeDefault'
	if ($null -ne $gameModeDefaultValue)
	{
		return [bool]$gameModeDefaultValue
	}

	return $false
}

function Resolve-GameModeDecisionToggleParam
{
	<# .SYNOPSIS Resolves a toggle parameter based on a decision choice. #>
	param (
		[object]$Entry,
		[string]$DecisionChoice
	)

	if ($null -eq $Entry -or [string]::IsNullOrWhiteSpace($DecisionChoice))
	{
		return $null
	}

	$normalizedChoice = [string]$DecisionChoice
	$decisionPromptKey = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'DecisionPromptKey')
	$onParam = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'OnParam')
	$offParam = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'OffParam')

	switch ($decisionPromptKey)
	{
		'GPUScheduling'
		{
			if ($normalizedChoice -eq 'Enable') { return $onParam }
			return $null
		}
		'FullscreenOptimizations'
		{
			if ($normalizedChoice -eq 'Disable') { return $offParam }
			return $null
		}
		'MultiplaneOverlay'
		{
			if ($normalizedChoice -eq 'Disable') { return $offParam }
			return $null
		}
		'NetworkAdaptersSavePower'
		{
			if ($normalizedChoice -eq 'Disable') { return $offParam }
			return $null
		}
		default
		{
			switch ($normalizedChoice)
			{
				'Enable' { return $onParam }
				'Disable' { return $offParam }
				default { return $null }
			}
		}
	}
}

function Test-GameModeDecisionPromptRequired
{
	<# .SYNOPSIS Tests whether a decision prompt is required for a profile. #>
	param (
		[object]$Entry,
		[string]$ProfileName
	)

	if ($null -eq $Entry)
	{
		return $false
	}

	$decisionPromptKey = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'DecisionPromptKey')
	switch ($decisionPromptKey)
	{
		'GPUScheduling' { return $true }
		'GameBar' { return $true }
		'GameBarTips' { return $true }
		'FullscreenOptimizations' { return ($ProfileName -eq 'Troubleshooting') }
		'MultiplaneOverlay' { return ($ProfileName -eq 'Troubleshooting') }
		'NetworkAdaptersSavePower' { return ($ProfileName -eq 'Troubleshooting') }
		default { return $false }
	}
}

function Get-GameModeDecisionPromptDefinition
{
	<# .SYNOPSIS Builds a decision prompt object with message and buttons. #>
	param (
		[object]$Entry,
		[string]$ProfileName
	)

	if ($null -eq $Entry -or [string]::IsNullOrWhiteSpace($ProfileName))
	{
		return $null
	}

	$isTroubleshootingOnly = [bool](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'TroubleshootingOnly')
	if ($isTroubleshootingOnly -and $ProfileName -ne 'Troubleshooting')
	{
		return $null
	}

	if (-not (Test-GameModeDecisionPromptRequired -Entry $Entry -ProfileName $ProfileName))
	{
		return $null
	}

	$decisionPromptKey = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'DecisionPromptKey')
	if ([string]::IsNullOrWhiteSpace($decisionPromptKey))
	{
		return $null
	}

	$promptMessage = switch ($decisionPromptKey)
	{
		'GPUScheduling' { 'Choose how Game Mode should handle hardware-accelerated GPU scheduling. Enable it if you want the gaming profile to make that graphics change now, or leave Windows default behavior in place.'; break }
		'GameBar' { 'Choose how Game Mode should handle Xbox Game Bar. Keep it enabled if you rely on Win+G capture, overlays, or controller-friendly launch flows.'; break }
		'GameBarTips' { 'Choose how Game Mode should handle Xbox Game Bar tips. Disabling tips removes onboarding prompts for experienced players.'; break }
		'FullscreenOptimizations' { 'Choose whether to keep Fullscreen Optimizations at the Windows default or disable it for this troubleshooting run. Disabling is for stubborn compatibility, latency, or focus issues, not a general FPS recommendation.'; break }
		'MultiplaneOverlay' { 'Choose whether to keep Multiplane Overlay at the Windows default or disable it for this troubleshooting run. Disabling is most useful for flicker, overlay glitches, or display composition problems.'; break }
		'NetworkAdaptersSavePower' { 'Choose whether to disable network adapter power saving for this troubleshooting run. Only use the disable path if you are chasing wake-from-idle reconnect delays or brief network stalls during gaming.'; break }
		default { 'Choose how Game Mode should handle this gaming setting.' }
	}

	$buttonSet = switch ($decisionPromptKey)
	{
		'GPUScheduling' { @('Enable', 'Leave default', 'Skip') }
		'FullscreenOptimizations' { @('Keep default', 'Disable', 'Skip') }
		'MultiplaneOverlay' { @('Keep default', 'Disable', 'Skip') }
		'NetworkAdaptersSavePower' { @('Keep default', 'Disable', 'Skip') }
		default { @('Enable', 'Disable', 'Skip') }
	}

	$accentButton = switch ($decisionPromptKey)
	{
		'GPUScheduling' { 'Enable' }
		'GameBar' { 'Enable' }
		'GameBarTips' { 'Disable' }
		'FullscreenOptimizations' { 'Keep default' }
		'MultiplaneOverlay' { 'Keep default' }
		'NetworkAdaptersSavePower' { 'Keep default' }
		default { 'Enable' }
	}

	return [pscustomobject]@{
		Key = $decisionPromptKey
		Function = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Function')
		Name = [string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Name')
		Title = "Game Mode | $([string](Get-TweakManifestEntryValue -Entry $Entry -FieldName 'Name'))"
		Message = $promptMessage
		Buttons = @($buttonSet)
		AccentButton = $accentButton
		DestructiveButton = 'Disable'
	}
}

function Get-GameModeDecisionPromptDefinitions
{
	<# .SYNOPSIS Returns all decision prompts for a Game Mode profile. #>
	param (
		[array]$Manifest,
		[string]$ProfileName,
		[string[]]$Allowlist
	)

	if ([string]::IsNullOrWhiteSpace($ProfileName))
	{
		LogWarning "Get-GameModeDecisionPromptDefinitions called with blank ProfileName"
		return @()
	}

	if (-not $Manifest)
	{
		$Manifest = @(Import-TweakManifestFromData)
	}
	if (-not $Manifest)
	{
		LogWarning "Get-GameModeDecisionPromptDefinitions: manifest is empty after import"
		return @()
	}

	$effectiveAllowlist = @($Allowlist)
	if ($effectiveAllowlist.Count -eq 0)
	{
		$effectiveAllowlist = @(Get-GameModeAllowlist)
	}

	$allowlistLookup = @{}
	for ($i = 0; $i -lt $effectiveAllowlist.Count; $i++)
	{
		$allowlistLookup[[string]$effectiveAllowlist[$i]] = $i
	}

	$promptDefinitions = [System.Collections.Generic.List[object]]::new()
	$seenPromptKeys = @{}
	$allowedEntries = @(
		$Manifest |
			Where-Object {
				$allowlistLookup.ContainsKey([string](Get-TweakManifestEntryValue -Entry $_ -FieldName 'Function'))
			} |
			Sort-Object @{ Expression = { $allowlistLookup[[string](Get-TweakManifestEntryValue -Entry $_ -FieldName 'Function')] } }
	)

	foreach ($entry in @($allowedEntries))
	{
		if ($null -eq $entry) { continue }
		if (-not (Test-GameModeAllowlistEntryReviewed -Entry $entry)) { continue }

		$promptDefinition = Get-GameModeDecisionPromptDefinition -Entry $entry -ProfileName $ProfileName
		if ($null -eq $promptDefinition) { continue }
		if ($seenPromptKeys.ContainsKey([string]$promptDefinition.Key)) { continue }

		$seenPromptKeys[[string]$promptDefinition.Key] = $true
		[void]$promptDefinitions.Add($promptDefinition)
	}

	return @($promptDefinitions)
}

function Merge-GameModeSelectionState
{
	<# .SYNOPSIS Merges manifest entries, overrides, and decisions into selection state. #>
	param (
		[array]$Manifest,
		[string]$ProfileName,
		[hashtable]$DecisionOverrides = @{},
		[string[]]$Allowlist
	)

	if (-not $Manifest -or [string]::IsNullOrWhiteSpace($ProfileName))
	{
		return [ordered]@{}
	}

	$effectiveAllowlist = @($Allowlist)
	if ($effectiveAllowlist.Count -eq 0)
	{
		$effectiveAllowlist = @(Get-GameModeAllowlist)
	}

	$allowlistLookup = @{}
	for ($i = 0; $i -lt $effectiveAllowlist.Count; $i++)
	{
		$allowlistLookup[[string]$effectiveAllowlist[$i]] = $i
	}

	$selectionState = [ordered]@{}
	$allowedEntries = @(
		$Manifest |
			Where-Object {
				$allowlistLookup.ContainsKey([string](Get-TweakManifestEntryValue -Entry $_ -FieldName 'Function'))
			} |
			Sort-Object @{ Expression = { $allowlistLookup[[string](Get-TweakManifestEntryValue -Entry $_ -FieldName 'Function')] } }
	)

	$allowlistData = Import-GameModeAllowlistData

	foreach ($entry in $allowedEntries)
	{
		if ($null -eq $entry) { continue }
		if (-not (Test-GameModeAllowlistEntryReviewed -Entry $entry)) { continue }

		$functionName = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'Function')
		if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

		# Check for allowlist override data (cross-category entries)
		$allowlistOverride = if ($allowlistData.ContainsKey($functionName)) { $allowlistData[$functionName] } else { $null }

		# TroubleshootingOnly - allowlist override takes precedence over manifest
		$isTroubleshootingOnly = if ($null -ne $allowlistOverride -and $allowlistOverride.PSObject.Properties['TroubleshootingOnly']) {
			[bool]$allowlistOverride.TroubleshootingOnly
		} else {
			[bool](Get-TweakManifestEntryValue -Entry $entry -FieldName 'TroubleshootingOnly')
		}
		if ($isTroubleshootingOnly -and $ProfileName -ne 'Troubleshooting')
		{
			continue
		}

		$decisionPromptKey = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'DecisionPromptKey')
		$decisionChoice = $null
		if (-not [string]::IsNullOrWhiteSpace($decisionPromptKey) -and $DecisionOverrides -and $DecisionOverrides.ContainsKey($decisionPromptKey))
		{
			$decisionChoice = [string]$DecisionOverrides[$decisionPromptKey]
		}

		$toggleParam = $null
		$selectionSource = $null
		if (-not [string]::IsNullOrWhiteSpace($decisionChoice))
		{
			$toggleParam = Resolve-GameModeDecisionToggleParam -Entry $entry -DecisionChoice $decisionChoice
			if (-not [string]::IsNullOrWhiteSpace($toggleParam))
			{
				$selectionSource = 'DecisionOverride'
			}
		}

		# Profile default: use allowlist override for cross-category entries, manifest for core entries
		if ([string]::IsNullOrWhiteSpace($toggleParam))
		{
			if ($null -ne $allowlistOverride)
			{
				$toggleParam = Resolve-GameModeAllowlistToggleParam -AllowlistEntry $allowlistOverride -ManifestEntry $entry -ProfileName $ProfileName
				if (-not [string]::IsNullOrWhiteSpace($toggleParam))
				{
					$selectionSource = 'AllowlistDefault'
				}
			}
			elseif (Test-GameModeProfileDefaultSelection -Entry $entry -ProfileName $ProfileName)
			{
				$toggleParam = [string](Get-TweakManifestEntryValue -Entry $entry -FieldName 'OnParam')
				if (-not [string]::IsNullOrWhiteSpace($toggleParam))
				{
					$selectionSource = 'ProfileDefault'
				}
			}
		}

		if ([string]::IsNullOrWhiteSpace($toggleParam))
		{
			continue
		}

		$selectionState[$functionName] = [pscustomobject]@{
			Entry            = $entry
			Function         = $functionName
			Profile          = [string]$ProfileName
			ToggleParam      = $toggleParam
			SelectionSource  = if ([string]::IsNullOrWhiteSpace($selectionSource)) { 'ProfileDefault' } else { $selectionSource }
			DecisionPromptKey = $decisionPromptKey
			DecisionChoice   = $decisionChoice
			AllowlistOrder   = if ($allowlistLookup.ContainsKey($functionName)) { [int]$allowlistLookup[$functionName] } else { 999 }
		}
	}

	return $selectionState
}

function Get-GameModeSelectionSet
{
	<# .SYNOPSIS Returns the sorted selection set for a profile. #>
	param (
		[array]$Manifest,
		[string]$ProfileName,
		[hashtable]$DecisionOverrides = @{},
		[string[]]$Allowlist
	)

	$selectionState = Merge-GameModeSelectionState -Manifest $Manifest -ProfileName $ProfileName -DecisionOverrides $DecisionOverrides -Allowlist $Allowlist
	if (-not $selectionState -or $selectionState.Count -eq 0)
	{
		return @()
	}

	return @(
		$selectionState.Values |
			Sort-Object @{ Expression = { [int]$_.AllowlistOrder } }, @{ Expression = { [string]$_.Function } }
	)
}

function Get-GameModeDecisionOverridesText
{
	<# .SYNOPSIS Formats decision overrides as readable text. #>
	param ([hashtable]$Overrides)

	if (-not $Overrides -or $Overrides.Count -eq 0)
	{
		return 'none'
	}

	$pairs = foreach ($key in @($Overrides.Keys | Sort-Object))
	{
		if ([string]::IsNullOrWhiteSpace([string]$key)) { continue }
		$value = [string]$Overrides[$key]
		if ([string]::IsNullOrWhiteSpace($value)) { continue }
		'{0}={1}' -f [string]$key, $value
	}

	if (@($pairs).Count -eq 0)
	{
		return 'none'
	}

	return (@($pairs) -join '; ')
}

function Get-GameModeProfilePlan
{
	<# .SYNOPSIS Builds the execution plan with metadata for a Game Mode profile. #>
	param (
		[array]$Manifest,
		[ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
		[string]$ProfileName,
		[hashtable]$DecisionOverrides = @{},
		[string[]]$Allowlist
	)

	if (-not $Manifest)
	{
		$Manifest = @(Import-TweakManifestFromData)
	}
	if (-not $Manifest -or [string]::IsNullOrWhiteSpace($ProfileName))
	{
		return @()
	}

	$plan = [System.Collections.Generic.List[object]]::new()
	foreach ($selection in @(Get-GameModeSelectionSet -Manifest $Manifest -ProfileName $ProfileName -DecisionOverrides $DecisionOverrides -Allowlist $Allowlist))
	{
		if (-not $selection -or -not $selection.Entry) { continue }

		$functionName = [string]$selection.Function
		$toggleParam = [string]$selection.ToggleParam
		if ([string]::IsNullOrWhiteSpace($functionName) -or [string]::IsNullOrWhiteSpace($toggleParam))
		{
			continue
		}

		$reasonIncluded = switch ([string]$selection.SelectionSource)
		{
			'DecisionOverride'
			{
				"Included by Game Mode ($ProfileName) after you chose the '$([string]$selection.DecisionChoice)' path."
				break
			}
			default
			{
				"Included by Game Mode ($ProfileName) as part of the profile default plan."
				break
			}
		}

		[void]$plan.Add([pscustomobject]@{
			Entry = $selection.Entry
			Function = $functionName
			Name = [string](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'Name')
			Category = [string](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'Category')
			Profile = [string]$ProfileName
			ToggleParam = $toggleParam
			Command = ('{0} -{1}' -f $functionName, $toggleParam)
			SelectionSource = [string]$selection.SelectionSource
			DecisionPromptKey = [string]$selection.DecisionPromptKey
			DecisionChoice = [string]$selection.DecisionChoice
			ReasonIncluded = $reasonIncluded
			Risk = [string](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'Risk')
			Restorable = Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'Restorable'
			RecoveryLevel = [string](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'RecoveryLevel')
			RequiresRestart = [bool](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'RequiresRestart')
			GamingPreviewGroup = [string](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'GamingPreviewGroup')
			TroubleshootingOnly = [bool](Get-TweakManifestEntryValue -Entry $selection.Entry -FieldName 'TroubleshootingOnly')
			AllowlistOrder = [int]$selection.AllowlistOrder
		})
	}

	return @($plan)
}

function Get-GameModeProfileCommandList
{
	<# .SYNOPSIS Extracts the command list from a Game Mode profile plan. #>
	param (
		[array]$Manifest,
		[ValidateSet('Casual', 'Competitive', 'Streaming', 'Troubleshooting')]
		[string]$ProfileName,
		[hashtable]$DecisionOverrides = @{},
		[string[]]$Allowlist
	)

	return @(
		Get-GameModeProfilePlan -Manifest $Manifest -ProfileName $ProfileName -DecisionOverrides $DecisionOverrides -Allowlist $Allowlist |
			ForEach-Object { [string]$_.Command } |
			Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
	)
}

function Resolve-ValidatedGameModeDecisionOverrides
{
	<# .SYNOPSIS Validates and normalizes Game Mode decision overrides. #>
	param (
		[string]$ProfileName,
		[hashtable]$DecisionOverrides = @{},
		[array]$Manifest,
		[string[]]$Allowlist
	)

	if (-not $DecisionOverrides -or $DecisionOverrides.Count -eq 0)
	{
		return @{}
	}

	$promptDefinitions = @(Get-GameModeDecisionPromptDefinitions -Manifest $Manifest -ProfileName $ProfileName -Allowlist $Allowlist)
	$promptLookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($promptDefinition in $promptDefinitions)
	{
		if ($promptDefinition -and -not [string]::IsNullOrWhiteSpace([string]$promptDefinition.Key))
		{
			$promptLookup[[string]$promptDefinition.Key] = $promptDefinition
		}
	}

	$normalizedOverrides = @{}
	foreach ($overrideKey in @($DecisionOverrides.Keys))
	{
		$keyText = [string]$overrideKey
		if ([string]::IsNullOrWhiteSpace($keyText))
		{
			throw "Game Mode decision overrides cannot use a blank key."
		}

		if (-not $promptLookup.ContainsKey($keyText))
		{
			$validKeys = @($promptLookup.Keys | Sort-Object)
			throw "Game Mode decision override '$keyText' is not valid for profile '$ProfileName'. Valid keys: $($validKeys -join ', ')."
		}

		$valueText = [string]$DecisionOverrides[$overrideKey]
		if ([string]::IsNullOrWhiteSpace($valueText))
		{
			throw "Game Mode decision override '$keyText' cannot be blank."
		}

		$validChoices = @($promptLookup[$keyText].Buttons)
		$matchedChoice = $validChoices | Where-Object { [string]$_ -ieq $valueText } | Select-Object -First 1
		if (-not $matchedChoice)
		{
			throw "Game Mode decision override '$keyText' has invalid choice '$valueText'. Valid choices: $($validChoices -join ', ')."
		}

		$normalizedOverrides[[string]$promptLookup[$keyText].Key] = [string]$matchedChoice
	}

	return $normalizedOverrides
}
