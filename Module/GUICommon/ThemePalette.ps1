<#
    .SYNOPSIS
#>
function Write-GuiCommonThemeRepairWarning
{
	param(
		[scriptblock]$WarningHandler,
		[string]$Context,
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message))
	{
		return
	}

	if ($WarningHandler)
	{
		& $WarningHandler -Context $Context -Message $Message
		return
	}

	Write-GuiCommonWarning ("GUI theme fallback [{0}]: {1}" -f $(if ([string]::IsNullOrWhiteSpace($Context)) { 'GUI' } else { $Context }), $Message)
}

<#
    .SYNOPSIS
#>
function Repair-GuiThemePalette
{
	param (
		[hashtable]$Theme,
		[string]$ThemeName = 'Dark',
		[hashtable[]]$ReferenceThemes = @(),
		[scriptblock]$WarningHandler
	)

	$repairedTheme = @{}
	if ($Theme)
	{
		foreach ($key in $Theme.Keys)
		{
			$repairedTheme[$key] = $Theme[$key]
		}
	}

	# Ensure core interactive colors always exist before downstream theme repair runs.
	$defaultColors = @{
		'TabHoverBg' = '#343C55'
		'TextPrimary' = '#F4F7FF'
		'FocusRing' = '#9ACAFF'
		'AccentBlue' = '#7CB7FF'
		'AccentHover' = '#9ACAFF'
		'AccentPress' = '#4D9CFF'
		'HeaderBg' = '#151824'
		'TextSecondary' = '#CDD6EA'
	}
	foreach ($key in $defaultColors.Keys)
	{
		if (-not $repairedTheme.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$repairedTheme[$key]))
		{
			$repairedTheme[$key] = $defaultColors[$key]
			Write-GuiCommonThemeRepairWarning -WarningHandler $WarningHandler -Context "Repair-GuiThemePalette/$ThemeName" -Message "Added missing color '$key' with $($defaultColors[$key])."
		}
	}

	$orderedReferenceThemes = [System.Collections.Generic.List[hashtable]]::new()
	foreach ($referenceTheme in @($ReferenceThemes))
	{
		if ($referenceTheme)
		{
			[void]$orderedReferenceThemes.Add($referenceTheme)
		}
	}

	$requiredKeys = [System.Collections.Generic.HashSet[string]]::new()
	foreach ($sourceTheme in $orderedReferenceThemes)
	{
		foreach ($key in $sourceTheme.Keys)
		{
			[void]$requiredKeys.Add([string]$key)
		}
	}

	foreach ($key in $requiredKeys)
	{
		$currentValue = if ($repairedTheme.ContainsKey($key)) { [string]$repairedTheme[$key] } else { $null }
		if (-not [string]::IsNullOrWhiteSpace($currentValue))
		{
			continue
		}

		$fallbackValue = $null
		foreach ($sourceTheme in $orderedReferenceThemes)
		{
			if ($sourceTheme.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$sourceTheme[$key]))
			{
				$fallbackValue = [string]$sourceTheme[$key]
				break
			}
		}
		if ([string]::IsNullOrWhiteSpace($fallbackValue))
		{
			$fallbackValue = '#7CB7FF'
		}

		$repairedTheme[$key] = $fallbackValue
		Write-GuiCommonThemeRepairWarning -WarningHandler $WarningHandler -Context "Repair-GuiThemePalette/$ThemeName" -Message "Filled missing color '$key' with $fallbackValue."
	}

	return $repairedTheme
}
