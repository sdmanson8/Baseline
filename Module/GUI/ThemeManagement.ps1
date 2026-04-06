# Theme palette definitions, fallback/repair, and brush conversion utilities

	$Script:DarkTheme = @{
		WindowBg      = "#1E1E2E"
		HeaderBg      = "#181825"
		PanelBg       = "#1E1E2E"
		CardBg        = "#272B3A"
		TabBg         = "#2F3445"
		TabActiveBg   = "#3670B8"
		TabHoverBg    = "#3670B8"
		BorderColor   = "#4C556D"
		TextPrimary   = "#CDD6F4"
		TextSecondary = "#B6BED8"
		TextMuted     = "#828AA2"
		AccentBlue    = "#89B4FA"
		AccentHover   = "#74C7EC"
		AccentPress   = "#94E2D5"
		FocusRing     = "#C9DEFF"
		CautionBg     = "#3B2028"
		CautionBorder = "#F38BA8"
		CautionText   = "#F38BA8"
		ImpactBadge   = "#F38BA8"
		ImpactBadgeBg = "#3B2028"
		LowRiskBadge     = "#B8E6C1"
		LowRiskBadgeBg   = "#213326"
		RiskMediumBadge   = "#F9E2AF"
		RiskMediumBadgeBg = "#3B3020"
		RiskHighBadge     = "#F38BA8"
		RiskHighBadgeBg   = "#3B2028"
		DestructiveBg = "#C0325A"
		DestructiveHover = "#A6294E"
		SectionLabel  = "#89B4FA"
		ScrollBg      = "#313244"
		ScrollThumb   = "#585B70"
		ToggleOn      = "#A6E3A1"
		ToggleOff     = "#F38BA8"
		StateEnabled  = "#9FD6AA"
		StateDisabled = "#98A0B7"
		SearchBg      = "#313244"
		SearchBorder  = "#585B70"
		SearchPlaceholder = "#8188A0"
		InputBg       = "#313244"
		InputHoverBg  = "#383D52"
		CardBorder    = "#394256"
		CardHoverBg   = "#323A4E"
		SecondaryButtonBg = "#30374A"
		SecondaryButtonHoverBg = "#39415A"
		SecondaryButtonPressBg = "#262D3E"
		SecondaryButtonBorder = "#5F6984"
		SecondaryButtonFg = "#E5EAF7"
		PresetPanelBg = "#23283A"
		PresetPanelBorder = "#52607E"
		StatusPillBg = "#20385C"
		StatusPillBorder = "#5C86C7"
		StatusPillText = "#D6E7FF"
		ActiveTabBorder = "#89B4FA"
		ActiveTabIndicator = "#4ADE80"
	}
	$Script:LightTheme = @{
		WindowBg      = "#E4E8F0"
		HeaderBg      = "#D6DBE5"
		PanelBg       = "#E4E8F0"
		CardBg        = "#FFFFFF"
		TabBg         = "#D4D9E4"
		TabActiveBg   = "#3670B8"
		TabHoverBg    = "#3670B8"
		BorderColor   = "#A7B0C0"
		TextPrimary   = "#1A1C2E"
		TextSecondary = "#31384A"
		TextMuted     = "#646C7F"
		AccentBlue    = "#1550AA"
		AccentHover   = "#1A60C4"
		AccentPress   = "#104090"
		FocusRing     = "#0D63E0"
		CautionBg     = "#F5D0D0"
		CautionBorder = "#A02040"
		CautionText   = "#A02040"
		ImpactBadge   = "#A02040"
		ImpactBadgeBg = "#F5D0D0"
		LowRiskBadge     = "#245A2D"
		LowRiskBadgeBg   = "#DDEFD9"
		RiskMediumBadge   = "#7A5A00"
		RiskMediumBadgeBg = "#FFF3D0"
		RiskHighBadge     = "#A02040"
		RiskHighBadgeBg   = "#F5D0D0"
		DestructiveBg = "#C0304E"
		DestructiveHover = "#A02840"
		SectionLabel  = "#1550AA"
		ScrollBg      = "#D0D2DE"
		ScrollThumb   = "#A0A2AE"
		ToggleOn      = "#1A7A2A"
		ToggleOff     = "#B02040"
		StateEnabled  = "#2F6E38"
		StateDisabled = "#778096"
		SearchBg      = "#FFFFFF"
		SearchBorder  = "#98A2B4"
		SearchPlaceholder = "#7A8296"
		InputBg       = "#FFFFFF"
		InputHoverBg  = "#F5F8FD"
		CardBorder    = "#B2BBCB"
		CardHoverBg   = "#F2F6FC"
		SecondaryButtonBg = "#FFFFFF"
		SecondaryButtonHoverBg = "#F4F7FC"
		SecondaryButtonPressBg = "#E7EDF8"
		SecondaryButtonBorder = "#98A7BF"
		SecondaryButtonFg = "#263248"
		PresetPanelBg = "#FFFFFF"
		PresetPanelBorder = "#AAB7CC"
		StatusPillBg = "#E6F0FF"
		StatusPillBorder = "#8FAAD8"
		StatusPillText = "#0F4EA8"
		ActiveTabBorder = "#89B4FA"
		ActiveTabIndicator = "#22C55E"
	}

	$Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
	$Script:GuiRuntimeWarnings = [System.Collections.Generic.HashSet[string]]::new()

	function Write-GuiThemeFallbackWarning
	{
		param (
			[string]$Context,
			[string]$Message
		)

		if ([string]::IsNullOrWhiteSpace($Message)) { return }
		if ($Message -match 'Encountered an empty color value')
		{
			return
		}

		$warningKey = '{0}|{1}' -f $Context, $Message
		$shouldLog = $true
		if ($Script:GuiThemeFallbackWarnings)
		{
			try { $shouldLog = $Script:GuiThemeFallbackWarnings.Add($warningKey) } catch { $shouldLog = $true }
		}
		if (-not $shouldLog) { return }

		$warningText = "GUI theme fallback [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Message
		if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogWarning $warningText
		}
		else
		{
			Write-Warning $warningText
		}
	}

	function Get-GuiFallbackColor
	{
		param ([string]$FallbackColor)

		if (-not [string]::IsNullOrWhiteSpace($FallbackColor))
		{
			return [string]$FallbackColor
		}

		if ($Script:DarkTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:DarkTheme.AccentBlue))
		{
			return [string]$Script:DarkTheme.AccentBlue
		}

		return '#89B4FA'
	}

	function Repair-GuiThemePalette
	{
		param (
			[hashtable]$Theme,
			[string]$ThemeName = 'Dark'
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
			'TabHoverBg' = '#3670B8'
			'TextPrimary' = '#CDD6F4'
			'FocusRing' = '#C9DEFF'
			'AccentBlue' = '#89B4FA'
			'AccentHover' = '#74C7EC'
			'AccentPress' = '#94E2D5'
			'HeaderBg' = '#181825'
			'TextSecondary' = '#B6BED8'
		}
		foreach ($key in $defaultColors.Keys)
		{
			if (-not $repairedTheme.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$repairedTheme[$key]))
			{
				$repairedTheme[$key] = $defaultColors[$key]
				Write-GuiThemeFallbackWarning -Context "Repair-GuiThemePalette/$ThemeName" -Message "Added missing color '$key' with $($defaultColors[$key])."
			}
		}

		$primaryTheme = if ($ThemeName -eq 'Light') { $Script:LightTheme } else { $Script:DarkTheme }
		$secondaryTheme = if ($ThemeName -eq 'Light') { $Script:DarkTheme } else { $Script:LightTheme }
		$requiredKeys = [System.Collections.Generic.HashSet[string]]::new()
		foreach ($sourceTheme in @($primaryTheme, $secondaryTheme))
		{
			if (-not $sourceTheme) { continue }
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
			if ($primaryTheme -and $primaryTheme.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$primaryTheme[$key]))
			{
				$fallbackValue = [string]$primaryTheme[$key]
			}
			elseif ($secondaryTheme -and $secondaryTheme.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$secondaryTheme[$key]))
			{
				$fallbackValue = [string]$secondaryTheme[$key]
			}
			else
			{
				$fallbackValue = '#89B4FA'
			}

			$repairedTheme[$key] = $fallbackValue
			Write-GuiThemeFallbackWarning -Context "Repair-GuiThemePalette/$ThemeName" -Message "Filled missing color '$key' with $fallbackValue."
		}

		return $repairedTheme
	}

	function ConvertTo-GuiBrush
	{
		param (
			[object]$Color,
			[string]$Context = 'GUI',
			[string]$FallbackColor = $null
		)

		if (-not $Script:BrushCache) { $Script:BrushCache = @{} }

		$resolvedColor = [string]$Color
		if (-not [string]::IsNullOrWhiteSpace($resolvedColor))
		{
			$cached = $Script:BrushCache[$resolvedColor]
			if ($cached) { return $cached }
		}

		$resolvedFallback = Get-GuiFallbackColor -FallbackColor $FallbackColor

		if ([string]::IsNullOrWhiteSpace($resolvedColor))
		{
			Write-GuiThemeFallbackWarning -Context $Context -Message "Encountered an empty color value. Using $resolvedFallback."
			$resolvedColor = $resolvedFallback
			$cached = $Script:BrushCache[$resolvedColor]
			if ($cached) { return $cached }
		}

		$converter = $Script:SharedBrushConverter
		if (-not $converter) { $converter = [System.Windows.Media.BrushConverter]::new() }
		try
		{
			$brush = $converter.ConvertFromString($resolvedColor)
		}
		catch
		{
			Write-GuiThemeFallbackWarning -Context $Context -Message "Failed to convert '$resolvedColor' ($($_.Exception.Message)). Using $resolvedFallback."
			$resolvedColor = $resolvedFallback
			$cached = $Script:BrushCache[$resolvedColor]
			if ($cached) { return $cached }
			$brush = $converter.ConvertFromString($resolvedFallback)
		}

		if ($brush -and $brush.CanFreeze) { $brush.Freeze() }
		$Script:BrushCache[$resolvedColor] = $brush
		return $brush
	}

	function New-SafeBrushConverter
	{
		param (
			[string]$Context = 'GUI',
			[string]$FallbackColor = $null
		)

		# Return a lightweight converter that hits $Script:BrushCache directly,
		# bypassing the ScriptMethod dispatch overhead of the previous Add-Member approach.
		$fallbackCapture = Get-GuiFallbackColor -FallbackColor $FallbackColor
		$cacheRef = $Script:BrushCache
		$rawConverter = [System.Windows.Media.BrushConverter]::new()
		$converter = [pscustomobject]@{}
		$converter | Add-Member -MemberType ScriptMethod -Name ConvertFromString -Value {
			param ($Color)
			$key = [string]$Color
			if (-not [string]::IsNullOrWhiteSpace($key))
			{
				$hit = $cacheRef[$key]
				if ($hit) { return $hit }
			}
			else
			{
				$key = $fallbackCapture
			}
			try
			{
				$brush = $rawConverter.ConvertFromString($key)
				if ($brush -and $brush.CanFreeze) { $brush.Freeze() }
				if ($brush) { $cacheRef[$key] = $brush }
				return $brush
			}
			catch
			{
				if ($fallbackCapture -and $fallbackCapture -ne $key)
				{
					$fb = $cacheRef[$fallbackCapture]
					if ($fb) { return $fb }
					try
					{
						$fb = $rawConverter.ConvertFromString($fallbackCapture)
						if ($fb -and $fb.CanFreeze) { $fb.Freeze() }
						if ($fb) { $cacheRef[$fallbackCapture] = $fb }
						return $fb
					}
					catch { return $null }
				}
				return $null
			}
		}.GetNewClosure()
		return $converter
	}

