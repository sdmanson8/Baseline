# Theme palette definitions, fallback/repair, and brush conversion utilities

	$Script:DarkTheme = @{
		WindowBg      = "#0E111A"
		HeaderBg      = "#121624"
		PanelBg       = "#161A26"
		CardBg        = "#1E2433"
		TabBg         = "#00FFFFFF"
		TabActiveBg   = "#262D40"
		TabHoverBg    = "#202638"
		BorderColor   = "#2430445A"
		BorderStrong  = "#3C4A66"
		TextPrimary   = "#F4F7FF"
		TextSecondary = "#CDD6EA"
		TextMuted     = "#A3ADC6"
		TextDisabled  = "#7E89A8"
		AccentBlue    = "#7CB7FF"
		AccentHover   = "#9ACAFF"
		AccentPress   = "#4D9CFF"
		FocusRing     = "#9ACAFF"
		CautionBg     = "#14D6A84A"
		CautionBorder = "#4DD6A84A"
		CautionText   = "#D6A84A"
		ImpactBadge   = "#D6A84A"
		ImpactBadgeBg = "#1FD6A84A"
		LowRiskBadge     = "#35D07F"
		LowRiskBadgeBg   = "#1F35D07F"
		RiskMediumBadge   = "#D6A84A"
		RiskMediumBadgeBg = "#1FD6A84A"
		RiskHighBadge     = "#FF6B8A"
		RiskHighBadgeBg   = "#1FFF6B8A"
		DestructiveSubtleBorder = "#33FF6B8A"
		DestructiveSubtleHoverBg = "#10FF6B8A"
		DestructiveSubtlePressBg = "#18FF6B8A"
		DestructiveBg = "#B93D5B"
		DestructiveHover = "#D64B6D"
		SectionLabel  = "#7CB7FF"
		ScrollBg          = "#121624"
		ScrollThumb       = "#3A4561"
		ScrollThumbHover  = "#4D5875"
		ScrollThumbActive = "#5E6C8E"
		ToggleOn      = "#7CB7FF"
		ToggleOff     = "#586178"
		StateEnabled  = "#35D07F"
		StateDisabled = "#586178"
		SearchBg      = "#262D40"
		SearchBorder  = "#2430445A"
		SearchPlaceholder = "#8F99B2"
		InputBg       = "#262D40"
		InputHoverBg  = "#30384E"
		CardBorder    = "#354057"
		CardHoverBg   = "#252D40"
		SecondaryButtonBg = "#00FFFFFF"
		SecondaryButtonHoverBg = "#252D40"
		SecondaryButtonPressBg = "#262D40"
		SecondaryButtonBorder = "#1FFFFFFF"
		SecondaryButtonFg = "#B8C1D9"
		PresetPanelBg = "#1E2433"
		PresetPanelBorder = "#293044"
		StatusPillBg = "#202638"
		StatusPillBorder = "#293044"
		StatusPillText = "#B8C1D9"
		ActiveTabBorder = "#7CB7FF"
		ActiveTabIndicator = "#7CB7FF"
		StateAccent = "#B34FD1A5"
		StateAccentStrong = "#4FD1A5"
		ProgressGreen      = "#35D07F"
		ProgressGreenTrack = "#2A3146"
		LogBg = "#1E2433"
		LogDefault = "#F4F7FF"
		LogInfo = "#7CB7FF"
		LogDebug = "#C084FC"
		LogSuccess = "#35D07F"
		LogWarning = "#D6A84A"
		LogError = "#FF6B8A"
		SearchHighlightBg = "#FDE68A"
		SearchHighlightText = "#111827"
	}
	$Script:LightTheme = @{
		WindowBg      = "#F3F5F8"
		HeaderBg      = "#F7F8FA"
		PanelBg       = "#F3F5F8"
		CardBg        = "#FFFFFF"
		TabBg         = "#EEF2F7"
		TabActiveBg   = "#2563EB"
		TabHoverBg    = "#1D4ED8"
		BorderColor   = "#D8DEE8"
		BorderStrong  = "#B8C2D0"
		TextPrimary   = "#111827"
		TextSecondary = "#4B5563"
		TextMuted     = "#5F6B7A"
		TextDisabled  = "#6B7788"
		AccentBlue    = "#2563EB"
		AccentHover   = "#1D4ED8"
		AccentPress   = "#1E40AF"
		FocusRing     = "#1D4ED8"
		CautionBg     = "#FEE4E2"
		CautionBorder = "#FDA29B"
		CautionText   = "#B42318"
		ImpactBadge   = "#B42318"
		ImpactBadgeBg = "#FEE4E2"
		LowRiskBadge     = "#1F7A4C"
		LowRiskBadgeBg   = "#DDEDE5"
		RiskMediumBadge   = "#9A6700"
		RiskMediumBadgeBg = "#FFF3D0"
		RiskHighBadge     = "#B42318"
		RiskHighBadgeBg   = "#FEE4E2"
		DestructiveSubtleBorder = "#33B42318"
		DestructiveSubtleHoverBg = "#10B42318"
		DestructiveSubtlePressBg = "#18B42318"
		DestructiveBg = "#B42318"
		DestructiveHover = "#991B1B"
		SectionLabel  = "#2563EB"
		ScrollBg          = "#E8EDF4"
		ScrollThumb       = "#B4B6C2"
		ScrollThumbHover  = "#8D8FA0"
		ScrollThumbActive = "#6C6E80"
		ToggleOn      = "#2563EB"
		ToggleOff     = "#B02040"
		StateEnabled  = "#1F7A4C"
		StateDisabled = "#8B95A6"
		SearchBg      = "#FFFFFF"
		SearchBorder  = "#D8DEE8"
		SearchPlaceholder = "#7A8494"
		InputBg       = "#FFFFFF"
		InputHoverBg  = "#F6F8FB"
		CardBorder    = "#D8DEE8"
		CardHoverBg   = "#EEF2F7"
		SecondaryButtonBg = "#FFFFFF"
		SecondaryButtonHoverBg = "#F2F5FA"
		SecondaryButtonPressBg = "#E9EEF6"
		SecondaryButtonBorder = "#D8DEE8"
		SecondaryButtonFg = "#263248"
		PresetPanelBg = "#FFFFFF"
		PresetPanelBorder = "#D8DEE8"
		StatusPillBg = "#EEF4FF"
		StatusPillBorder = "#D7E5FF"
		StatusPillText = "#1D4ED8"
		ActiveTabBorder = "#2563EB"
		ActiveTabIndicator = "#2563EB"
		StateAccent = "#1F7A4C"
		StateAccentStrong = "#1F7A4C"
		ProgressGreen      = "#1F7A4C"
		ProgressGreenTrack = "#DDEDE5"
		LogBg = "#F7F8FA"
		LogDefault = "#1F2937"
		LogInfo = "#1D4ED8"
		LogDebug = "#6D28D9"
		LogSuccess = "#1F7A4C"
		LogWarning = "#9A6700"
		LogError = "#B42318"
		SearchHighlightBg = "#FDE68A"
		SearchHighlightText = "#111827"
	}

	$Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
	$Script:GuiRuntimeWarnings = [System.Collections.Generic.HashSet[string]]::new()

	<#
	    .SYNOPSIS
	#>

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
			try { $shouldLog = $Script:GuiThemeFallbackWarnings.Add($warningKey) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ThemeManagement.Write-GuiThemeFallbackWarning:catch180' -Severity Debug }
			 $shouldLog = $true }
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

	<#
	    .SYNOPSIS
	#>

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

		return '#7CB7FF'
	}

	<#
	    .SYNOPSIS
	#>

	function ConvertTo-GuiRgbColorTriplet
	{
		param ([object]$Color)

		$colorText = ([string]$Color).Trim()
		if ([string]::IsNullOrWhiteSpace($colorText)) { return $null }

		if ($colorText -match '^#(?<R>[0-9a-fA-F])(?<G>[0-9a-fA-F])(?<B>[0-9a-fA-F])$')
		{
			$rHex = $matches['R'] + $matches['R']
			$gHex = $matches['G'] + $matches['G']
			$bHex = $matches['B'] + $matches['B']
		}
		elseif ($colorText -match '^#(?<R>[0-9a-fA-F]{2})(?<G>[0-9a-fA-F]{2})(?<B>[0-9a-fA-F]{2})$')
		{
			$rHex = $matches['R']
			$gHex = $matches['G']
			$bHex = $matches['B']
		}
		elseif ($colorText -match '^#(?<A>[0-9a-fA-F]{2})(?<R>[0-9a-fA-F]{2})(?<G>[0-9a-fA-F]{2})(?<B>[0-9a-fA-F]{2})$')
		{
			$rHex = $matches['R']
			$gHex = $matches['G']
			$bHex = $matches['B']
		}
		else
		{
			return $null
		}

		return [pscustomobject]@{
			R = [int]([Convert]::ToByte($rHex, 16))
			G = [int]([Convert]::ToByte($gHex, 16))
			B = [int]([Convert]::ToByte($bHex, 16))
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiRelativeColorLuminance
	{
		param ([object]$Color)

		$rgb = if ($Color -and $Color.PSObject.Properties['R'] -and $Color.PSObject.Properties['G'] -and $Color.PSObject.Properties['B'])
		{
			$Color
		}
		else
		{
			ConvertTo-GuiRgbColorTriplet -Color $Color
		}
		if (-not $rgb) { return $null }

		$getLinearChannel = {
			param ([int]$Channel)

			$scaled = [double]$Channel / 255.0
			if ($scaled -le 0.03928)
			{
				return ($scaled / 12.92)
			}

			return [Math]::Pow((($scaled + 0.055) / 1.055), 2.4)
		}

		$r = & $getLinearChannel ([int]$rgb.R)
		$g = & $getLinearChannel ([int]$rgb.G)
		$b = & $getLinearChannel ([int]$rgb.B)

		return ((0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b))
	}

	<#
	    .SYNOPSIS
	#>

	function Get-GuiReadableForegroundColor
	{
		param (
			[object]$BackgroundColor,
			[string[]]$CandidateColors = @('#FFFFFF', '#111827')
		)

		if (-not $CandidateColors -or $CandidateColors.Count -eq 0)
		{
			$CandidateColors = @('#FFFFFF', '#111827')
		}

		$backgroundLuminance = Get-GuiRelativeColorLuminance -Color $BackgroundColor
		if ($null -eq $backgroundLuminance)
		{
			return [string]$CandidateColors[0]
		}

		$bestColor = $null
		$bestContrast = [double]::NegativeInfinity
		foreach ($candidateColor in @($CandidateColors))
		{
			if ([string]::IsNullOrWhiteSpace([string]$candidateColor)) { continue }

			$candidateLuminance = Get-GuiRelativeColorLuminance -Color $candidateColor
			if ($null -eq $candidateLuminance) { continue }

			$lighter = [Math]::Max([double]$backgroundLuminance, [double]$candidateLuminance)
			$darker = [Math]::Min([double]$backgroundLuminance, [double]$candidateLuminance)
			$contrast = ($lighter + 0.05) / ($darker + 0.05)
			if ($contrast -gt $bestContrast)
			{
				$bestContrast = $contrast
				$bestColor = [string]$candidateColor
			}
		}

		if ([string]::IsNullOrWhiteSpace($bestColor))
		{
			return [string]$CandidateColors[0]
		}

		return $bestColor
	}

	<#
	    .SYNOPSIS
	#>

	function Repair-GuiThemePaletteWithReferences
	{
		param (
			[hashtable]$Theme,
			[string]$ThemeName = 'Dark'
		)

		$primaryTheme = if ($ThemeName -eq 'Light') { $Script:LightTheme } else { $Script:DarkTheme }
		$secondaryTheme = if ($ThemeName -eq 'Light') { $Script:DarkTheme } else { $Script:LightTheme }
		$warningHandler = {
			param(
				[string]$Context,
				[string]$Message
			)

			Write-GuiThemeFallbackWarning -Context $Context -Message $Message
		}

		return (GUICommon\Repair-GuiThemePalette -Theme $Theme -ThemeName $ThemeName -ReferenceThemes @($primaryTheme, $secondaryTheme) -WarningHandler $warningHandler)
	}

	<#
	    .SYNOPSIS
	#>

	function Resolve-GuiThemeResourcePath
	{
		param (
			[ValidateSet('Dark', 'Light')]
			[string]$ThemeName
		)

		$themeRoot = if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiExtractedRoot))
		{
			[string]$Script:GuiExtractedRoot
		}
		else
		{
			$PSScriptRoot
		}

		return (Join-Path -Path $themeRoot -ChildPath ('Themes\{0}.xaml' -f $ThemeName))
	}

	<#
	    .SYNOPSIS
	#>

	function Import-GuiThemeResourceDictionary
	{
		param (
			[ValidateSet('Dark', 'Light')]
			[string]$ThemeName
		)

		$themePath = Resolve-GuiThemeResourcePath -ThemeName $ThemeName
		if (-not (Test-Path -LiteralPath $themePath -PathType Leaf))
		{
			throw "Theme resource dictionary not found: $themePath"
		}

		$reader = $null
		try
		{
			$reader = [System.Xml.XmlReader]::Create($themePath)
			$dictionary = [System.Windows.Markup.XamlReader]::Load($reader)
			if (-not ($dictionary -is [System.Windows.ResourceDictionary]))
			{
				throw "Theme resource file did not load as a ResourceDictionary: $themePath"
			}
			$dictionary['Baseline.ThemeDictionaryMarker'] = $ThemeName
			return $dictionary
		}
		finally
		{
			if ($reader) { $reader.Close() }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiThemeResources
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[object]$Target,
			[ValidateSet('Dark', 'Light')]
			[string]$ThemeName
		)

		if (-not $Target) { throw 'Cannot apply theme resources because the target is null.' }
		if (-not ($Target.PSObject.Properties['Resources'] -or $Target.GetType().GetProperty('Resources'))) { throw 'Cannot apply theme resources because the target has no Resources property.' }

		$resources = $Target.Resources
		if (-not $resources) { throw 'Cannot apply theme resources because the target Resources property is null.' }

		$oldThemeDictionaries = @(
			$resources.MergedDictionaries |
				Where-Object { $_ -is [System.Windows.ResourceDictionary] -and $_.Contains('Baseline.ThemeDictionaryMarker') }
		)
		foreach ($dict in $oldThemeDictionaries)
		{
			[void]$resources.MergedDictionaries.Remove($dict)
		}

		$newDictionary = Import-GuiThemeResourceDictionary -ThemeName $ThemeName
		[void]$resources.MergedDictionaries.Add($newDictionary)
		return $true
	}

	<#
	    .SYNOPSIS
	#>

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
			$brush = [System.Windows.Media.Brush]$converter.ConvertFromString($resolvedColor)
		}
		catch
		{
			Write-GuiThemeFallbackWarning -Context $Context -Message "Failed to convert '$resolvedColor' ($($_.Exception.Message)). Using $resolvedFallback."
			$resolvedColor = $resolvedFallback
			$cached = $Script:BrushCache[$resolvedColor]
			if ($cached) { return $cached }
			$brush = [System.Windows.Media.Brush]$converter.ConvertFromString($resolvedFallback)
		}

		if ($brush -and $brush.CanFreeze) { $brush.Freeze() }
		$Script:BrushCache[$resolvedColor] = $brush
		return $brush
	}

	<#
	    .SYNOPSIS
	#>

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
				if ($hit) { return [System.Windows.Media.Brush]$hit }
			}
			else
			{
				$key = $fallbackCapture
			}
			try
			{
				$brush = [System.Windows.Media.Brush]$rawConverter.ConvertFromString($key)
				if ($brush -and $brush.CanFreeze) { $brush.Freeze() }
				if ($brush) { $cacheRef[$key] = $brush }
				return [System.Windows.Media.Brush]$brush
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ThemeManagement.New-SafeBrushConverter:catch546' -Severity Debug }

				if ($fallbackCapture -and $fallbackCapture -ne $key)
				{
					$fb = $cacheRef[$fallbackCapture]
					if ($fb) { return [System.Windows.Media.Brush]$fb }
					try
					{
						$fb = [System.Windows.Media.Brush]$rawConverter.ConvertFromString($fallbackCapture)
						if ($fb -and $fb.CanFreeze) { $fb.Freeze() }
						if ($fb) { $cacheRef[$fallbackCapture] = $fb }
						return [System.Windows.Media.Brush]$fb
					}
					catch {
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ThemeManagement.New-SafeBrushConverter:catch559' -Severity Debug }
					 return $null }
				}
				return $null
			}
		}.GetNewClosure()
		return $converter
	}
