	foreach ($pKey in $PrimaryCategories.Keys)
	{
		if ([string]$pKey -eq 'Gaming')
		{
			continue
		}

		# Check if any tweaks exist for this primary tab
		$hasTweaks = $false
		$tweakCount = 0
		if ($pKey -eq 'Customizations')
		{
			$hasTweaks = $true
			$tweakCount = Get-GuiCustomizationsActionCardCount
		}
		else
		{
			$indexVariable = Get-Variable -Scope Script -Name TweakIndicesByPrimaryTab -ErrorAction SilentlyContinue
			$indicesByPrimaryTab = if ($indexVariable) { $indexVariable.Value } else { $null }
			if ($indicesByPrimaryTab -and $indicesByPrimaryTab.ContainsKey($pKey))
			{
				$hasTweaks = ($indicesByPrimaryTab[$pKey].Count -gt 0)
			}
			$tweakCount = Get-PrimaryTabVisibleTweakCount -PrimaryTab $pKey -SearchQuery ''
		}
		if (-not $hasTweaks) { continue }

		$tabItem = New-Object System.Windows.Controls.TabItem
		$tabIconName = Get-GuiPrimaryTabIconName -PrimaryTab $pKey
		$tabDisplayName = Get-LocalizedTabHeader -PrimaryTab $pKey
		if ($tabIconName)
		{
			$tabItem.Header = New-GuiLabeledIconContent -IconName $tabIconName -Text "$tabDisplayName ($tweakCount)" -IconSize 16 -Gap 6 -AllowTextOnlyFallback
		}
		else
		{
			$tabItem.Header = "$tabDisplayName ($tweakCount)"
		}
		$tabItem.Tag = $pKey
		$tabItem.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TextPrimary -Context 'BuildPrimaryTabs/Foreground'
		$tabItem.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TabBg -Context 'BuildPrimaryTabs/Background'
		$tabItem.Padding = [System.Windows.Thickness]::new(16, 6, 16, 6)
		[void]($PrimaryTabs.Items.Add($tabItem))
		Add-PrimaryTabHoverEffects -Tab $tabItem
	}
	Update-PrimaryTabVisuals

	$Script:FilterUiUpdating = $true
	try
	{
		# Risk Filter - ONLY use SelectedIndex (integer)
		if ($CmbRiskFilter)
		{
			$CmbRiskFilter.Items.Clear()
			$riskDisplayAll = Get-UxLocalizedString -Key 'GuiRiskAll' -Fallback 'All'
			$riskDisplayLow = Get-UxLocalizedString -Key 'GuiRiskLowShort' -Fallback 'Low'
			$riskDisplayMedium = Get-UxLocalizedString -Key 'GuiRiskMediumShort' -Fallback 'Medium'
			$riskDisplayHigh = Get-UxLocalizedString -Key 'GuiRiskHighShort' -Fallback 'High'
			$Script:RiskFilterInternalValues = @('All', 'Low', 'Medium', 'High')
			foreach ($riskOption in @($riskDisplayAll, $riskDisplayLow, $riskDisplayMedium, $riskDisplayHigh))
			{
				[void]$CmbRiskFilter.Items.Add($riskOption)
			}

			$idx = 0
				if ($Script:RiskFilter -and $Script:RiskFilterInternalValues)
				{
					$found = $Script:RiskFilterInternalValues.IndexOf([string]$Script:RiskFilter)
					if ($found -ge 0) { $idx = $found }
				}
			try {
				$CmbRiskFilter.SelectedIndex = [int]$idx
			} catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\BuildPrimaryTabs.ps1:68' -Severity Debug }

				$CmbRiskFilter.SelectedIndex = 0
			}
		}

		if ($CmbPlatformFilter)
		{
			Update-PlatformFilterList
		}

		# Category Filter (safe)
		if ($CmbCategoryFilter)
		{
			$idx = 0
			if ($Script:CategoryFilter -and $Script:CategoryFilterInternalValues)
			{
				$found = $Script:CategoryFilterInternalValues.IndexOf($Script:CategoryFilter)
				if ($found -ge 0) { $idx = $found }
			}
			try {
				$CmbCategoryFilter.SelectedIndex = [int]$idx
			} catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\BuildPrimaryTabs.ps1:89' -Severity Debug }

				$CmbCategoryFilter.SelectedIndex = 0
			}
		}

		# Checkboxes
		if ($ChkHideUnavailableItems) { try { $ChkHideUnavailableItems.IsChecked = [bool]$Script:HideUnavailableItems } catch { Write-GuiRuntimeWarning -Context 'FilterSync:HideUnavailableItems' -Message $_.Exception.Message } }
		if ($ChkScan)          { try { $ChkScan.IsChecked          = [bool]$Script:ScanEnabled } catch { Write-GuiRuntimeWarning -Context 'FilterSync:ScanEnabled' -Message $_.Exception.Message } }

		# Language selector button + popup
		if ($BtnLanguage -and $LanguagePopup -and $LanguageListPanel)
		{
			# Build display-name-to-code mapping from available JSON files.
			$Script:LanguageMap = [ordered]@{}
			$locDir = $Script:GuiLocalizationDirectoryPath
			# Language display: NativeName|EnglishName pairs for dual-line display
			$langDisplayData = @{
				'af'      = @{ Native = 'Afrikaans';           English = 'Afrikaans' }
				'am'      = @{ Native = 'Amharic';               English = 'Amharic' }
				'ar'      = @{ Native = 'Arabic';              English = 'Arabic' }
				'az'      = @{ Native = 'Azerbaijani';          English = 'Azerbaijani' }
				'be'      = @{ Native = 'Belarusian';          English = 'Belarusian' }
				'bg'      = @{ Native = 'Bulgarian';           English = 'Bulgarian' }
				'bn'      = @{ Native = 'Bengali';                English = 'Bengali' }
				'bs'      = @{ Native = 'Bosnian';            English = 'Bosnian' }
				'ca'      = @{ Native = 'Catalan';              English = 'Catalan' }
				'cs'      = @{ Native = 'Czech';             English = 'Czech' }
				'da'      = @{ Native = 'Danish';               English = 'Danish' }
				'de'      = @{ Native = 'German';             English = 'German' }
				'el'      = @{ Native = 'Greek';            English = 'Greek' }
				'en'      = @{ Native = 'English';             English = 'English' }
				'en-029'  = @{ Native = 'English (Caribbean)'; English = 'English (Caribbean)' }
				'en-AE'   = @{ Native = 'English (United Arab Emirates)'; English = 'English (United Arab Emirates)' }
				'en-AU'   = @{ Native = 'English (Australia)'; English = 'English (Australia)' }
				'en-BZ'   = @{ Native = 'English (Belize)';    English = 'English (Belize)' }
				'en-CA'   = @{ Native = 'English (Canada)';    English = 'English (Canada)' }
				'en-GB'   = @{ Native = 'English (United Kingdom)'; English = 'English (United Kingdom)' }
				'en-IE'   = @{ Native = 'English (Ireland)';   English = 'English (Ireland)' }
				'en-IN'   = @{ Native = 'English (India)';      English = 'English (India)' }
				'en-JM'   = @{ Native = 'English (Jamaica)';    English = 'English (Jamaica)' }
				'en-MV'   = @{ Native = 'English (Maldives)';   English = 'English (Maldives)' }
				'en-MY'   = @{ Native = 'English (Malaysia)';   English = 'English (Malaysia)' }
				'en-NZ'   = @{ Native = 'English (New Zealand)'; English = 'English (New Zealand)' }
				'en-PH'   = @{ Native = 'English (Philippines)'; English = 'English (Philippines)' }
				'en-SG'   = @{ Native = 'English (Singapore)';  English = 'English (Singapore)' }
				'en-TT'   = @{ Native = 'English (Trinidad & Tobago)'; English = 'English (Trinidad & Tobago)' }
				'en-US'   = @{ Native = 'English (United States)'; English = 'English (United States)' }
				'en-ZA'   = @{ Native = 'English (South Africa)'; English = 'English (South Africa)' }
				'en-ZW'   = @{ Native = 'English (Zimbabwe)';    English = 'English (Zimbabwe)' }
				'es'      = @{ Native = 'Spanish';             English = 'Spanish' }
				'es-MX'   = @{ Native = 'Spanish (Mexico)';    English = 'Spanish (Mexico)' }
				'et'      = @{ Native = 'Estonian';               English = 'Estonian' }
				'eu'      = @{ Native = 'Basque';             English = 'Basque' }
				'fa'      = @{ Native = 'Persian';               English = 'Persian' }
				'fi'      = @{ Native = 'Finnish';               English = 'Finnish' }
				'fil'     = @{ Native = 'Filipino';            English = 'Filipino' }
				'fr'      = @{ Native = 'French';            English = 'French' }
				'fr-CA'   = @{ Native = 'French (Canada)';   English = 'French (Canada)' }
				'ga'      = @{ Native = 'Irish';             English = 'Irish' }
				'gd'      = @{ Native = 'Scottish Gaelic';            English = 'Scottish Gaelic' }
				'gl'      = @{ Native = 'Galician';              English = 'Galician' }
				'gu'      = @{ Native = 'Gujarati';              English = 'Gujarati' }
				'he'      = @{ Native = 'Hebrew';               English = 'Hebrew' }
				'hi'      = @{ Native = 'Hindi';                English = 'Hindi' }
				'hr'      = @{ Native = 'Croatian';            English = 'Croatian' }
				'hu'      = @{ Native = 'Hungarian';              English = 'Hungarian' }
				'hy'      = @{ Native = 'Armenian';             English = 'Armenian' }
				'id'      = @{ Native = 'Indonesian';    English = 'Indonesian' }
				'is'      = @{ Native = 'Icelandic';            English = 'Icelandic' }
				'it'      = @{ Native = 'Italian';            English = 'Italian' }
				'ja'      = @{ Native = 'Japanese';               English = 'Japanese' }
				'ka'      = @{ Native = 'Georgian';             English = 'Georgian' }
				'kk'      = @{ Native = 'Kazakh';               English = 'Kazakh' }
				'km'      = @{ Native = 'Khmer';                 English = 'Khmer' }
				'kn'      = @{ Native = 'Kannada';                English = 'Kannada' }
				'ko'      = @{ Native = 'Korean';               English = 'Korean' }
				'lo'      = @{ Native = 'Lao';                 English = 'Lao' }
				'lt'      = @{ Native = 'Lithuanian';            English = 'Lithuanian' }
				'lv'      = @{ Native = 'Latvian';            English = 'Latvian' }
				'mk'      = @{ Native = 'Macedonian';          English = 'Macedonian' }
				'ml'      = @{ Native = 'Malayalam';              English = 'Malayalam' }
				'mr'      = @{ Native = 'Marathi';                English = 'Marathi' }
				'ms'      = @{ Native = 'Malay';       English = 'Malay' }
				'mt'      = @{ Native = 'Maltese';               English = 'Maltese' }
				'nb'      = @{ Native = 'Norwegian';        English = 'Norwegian' }
				'ne'      = @{ Native = 'Nepali';               English = 'Nepali' }
				'nl'      = @{ Native = 'Dutch';          English = 'Dutch' }
				'nl-BE'   = @{ Native = 'Dutch (Belgium)'; English = 'Dutch (Belgium)' }
				'nn'      = @{ Native = 'Norwegian Nynorsk';       English = 'Norwegian Nynorsk' }
				'pa'      = @{ Native = 'Punjabi';               English = 'Punjabi' }
				'pl'      = @{ Native = 'Polish';              English = 'Polish' }
				'pt'      = @{ Native = 'Portuguese';           English = 'Portuguese' }
				'pt-BR'   = @{ Native = 'Portuguese (Brazil)';  English = 'Portuguese (Brazil)' }
				'ro'      = @{ Native = 'Romanian';              English = 'Romanian' }
				'ru'      = @{ Native = 'Russian';             English = 'Russian' }
				'sk'      = @{ Native = 'Slovak';          English = 'Slovak' }
				'sl'      = @{ Native = 'Slovenian';         English = 'Slovenian' }
				'sq'      = @{ Native = 'Albanian';               English = 'Albanian' }
				'sr'      = @{ Native = 'Serbian';              English = 'Serbian' }
				'sv'      = @{ Native = 'Swedish';             English = 'Swedish' }
				'sw'      = @{ Native = 'Swahili';           English = 'Swahili' }
				'ta'      = @{ Native = 'Tamil';                English = 'Tamil' }
				'te'      = @{ Native = 'Telugu';               English = 'Telugu' }
				'th'      = @{ Native = 'Thai';                  English = 'Thai' }
				'tr'      = @{ Native = 'Turkish';              English = 'Turkish' }
				'uk'      = @{ Native = 'Ukrainian';          English = 'Ukrainian' }
				'ur'      = @{ Native = 'Urdu';                 English = 'Urdu' }
				'uz'      = @{ Native = "O'zbek";              English = 'Uzbek' }
				'vi'      = @{ Native = 'Vietnamese';          English = 'Vietnamese' }
				'zh-Hans' = @{ Native = 'Chinese (Simplified)';              English = 'Chinese (Simplified)' }
				'zh-Hant' = @{ Native = 'Chinese (Traditional)';              English = 'Chinese (Traditional)' }
				'as'      = @{ Native = 'Assamese';              English = 'Assamese' }
				'bn-BD'   = @{ Native = 'Bengali (Bangladesh)';     English = 'Bengali (Bangladesh)' }
				'ckb'     = @{ Native = 'Central Kurdish';       English = 'Central Kurdish' }
				'cy'      = @{ Native = 'Welsh';             English = 'Welsh' }
				'ha'      = @{ Native = 'Hausa';               English = 'Hausa' }
				'ig'      = @{ Native = 'Igbo';                English = 'Igbo' }
				'kok'     = @{ Native = 'Konkani';               English = 'Konkani' }
				'ky'      = @{ Native = 'Kyrgyz';            English = 'Kyrgyz' }
				'lb'      = @{ Native = 'Luxembourgish';      English = 'Luxembourgish' }
				'mi'      = @{ Native = 'Maori';        English = 'Maori' }
				'mn'      = @{ Native = 'Mongolian';              English = 'Mongolian' }
				'nso'     = @{ Native = 'Northern Sotho';    English = 'Northern Sotho' }
				'or'      = @{ Native = 'Odia';                English = 'Odia' }
				'pa-Arab' = @{ Native = 'Punjabi (Arabic)';               English = 'Punjabi (Arabic)' }
				'prs'     = @{ Native = 'Dari';                  English = 'Dari' }
				'ps'      = @{ Native = 'Pashto';                 English = 'Pashto' }
				'qu'      = @{ Native = 'Quechua';            English = 'Quechua' }
				'quc'     = @{ Native = "K'iche'";             English = "K'iche'" }
				'rw'      = @{ Native = 'Kinyarwanda';        English = 'Kinyarwanda' }
				'sd'      = @{ Native = 'Sindhi';                 English = 'Sindhi' }
				'si'      = @{ Native = 'Sinhala';                English = 'Sinhala' }
				'sr-Cyrl' = @{ Native = 'Serbian (Cyrillic)';              English = 'Serbian (Cyrillic)' }
				'ti'      = @{ Native = 'Tigrinya';                English = 'Tigrinya' }
				'tk'      = @{ Native = 'Turkmen';             English = 'Turkmen' }
				'tn'      = @{ Native = 'Setswana';            English = 'Setswana' }
				'tt'      = @{ Native = 'Tatar';               English = 'Tatar' }
				'ug'      = @{ Native = 'Uyghur';             English = 'Uyghur' }
				'wo'      = @{ Native = 'Wolof';               English = 'Wolof' }
				'xh'      = @{ Native = 'isiXhosa';            English = 'isiXhosa' }
				'yo'      = @{ Native = 'Yoruba';              English = 'Yoruba' }
				'zu'      = @{ Native = 'isiZulu';             English = 'isiZulu' }
			}
			# Build compat map for legacy code
			$langDisplayNames = @{}
			foreach ($ldKey in $langDisplayData.Keys) { $langDisplayNames[$ldKey] = $langDisplayData[$ldKey].English }

			$languageFiles = @()
			$languageEntries = New-Object System.Collections.ArrayList
			if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
			{
				# Locale JSON files live in per-language folders; the root JSON files are
				# metadata (locale-map, schema, exempt-keys) and must not appear in the picker.
				$languageFiles = @(
					Get-ChildItem -LiteralPath $locDir -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
						Where-Object { $langDisplayData.ContainsKey($_.BaseName) } |
						Sort-Object @{ Expression = { if ($langDisplayData.ContainsKey($_.BaseName)) { $langDisplayData[$_.BaseName].English } else { $_.BaseName } } }, BaseName
				)
			}

			foreach ($jsonFile in $languageFiles)
			{
				$code = $jsonFile.BaseName
				$nativeName = if ($langDisplayData.ContainsKey($code)) { $langDisplayData[$code].Native } else { $code }
				$englishName = if ($langDisplayData.ContainsKey($code)) { $langDisplayData[$code].English } else { $code }
				$displayName = $englishName
				$Script:LanguageMap[$displayName] = $code
				[void]$languageEntries.Add([pscustomobject]@{
					Code = $code
					DisplayName = $displayName
					NativeName = $nativeName
					EnglishName = $englishName
					SearchIndex = ("{0} {1} {2} {3}" -f $nativeName, $englishName, $code, ($code -replace '-', ' ')).ToLowerInvariant()
				})
			}

			$setLanguageSearchInputStyle = ${function:Set-LanguageSearchInputStyle}
			$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
			$getUxBilingualLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxBilingualLocalizedString'
			$setFilterControlStyleCapture = ${function:Set-FilterControlStyle}

			if (-not $getUxLocalizedStringCapture) { throw 'Get-UxLocalizedString not found.' }
			if (-not $getUxBilingualLocalizedStringCapture) { throw 'Get-UxBilingualLocalizedString not found.' }
			Set-Item -Path function:Get-UxBilingualLocalizedString -Value $getUxBilingualLocalizedStringCapture

			# Language change logic stays in Show-TweakGUI scope so the live WPF
			# controls remain available, but the click handlers invoke a concrete
			# command handle instead of a raw local variable.
			<#
			    .SYNOPSIS
			#>

			function Set-SelectedGuiLanguage
			{
				param([string]$langCode)
				$Script:SelectedLanguage = $langCode

				# 1. Load new localization strings
				$locDir = $Script:GuiLocalizationDirectoryPath
				if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
				{
					$Global:Localization = Import-BaselineLocalization -BaseDirectory $locDir -UICulture $langCode
					[void](Set-BaselineThreadCulture -UICulture $langCode)
					$env:BASELINE_LANGUAGE = $langCode
				}

				# 2. Clear the inline language search and update indicator
				if ($TxtLanguageSearch) { $TxtLanguageSearch.Text = '' }
				if ($TxtLanguageState) { $TxtLanguageState.Text = $langCode.ToUpperInvariant() }
				Set-LanguageSearchInputStyle
				$LanguagePopup.IsOpen = $false
				if ($BtnLanguage) { $BtnLanguage.IsChecked = $false }

				# 3. Refresh all header/toolbar localized strings
				Update-GuiLocalizationStrings

				# 4. Refresh tab headers with localized names
				Update-PrimaryTabHeaders

				# 5. Rebuild tab content
				$Script:FilterGeneration++
				Clear-TabContentCache
				if (-not [string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab))
				{
					Update-CurrentTabContent -SkipIdlePrebuild
				}

				# 6. Sync action buttons (respects execution-mode guard)
				Sync-UxActionButtonText

				# 7. Update run-path context label if available
				if (Get-Command -Name 'Update-RunPathContextLabel' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Update-RunPathContextLabel
				}

				LogInfo (& $getUxBilingualLocalizedStringCapture -Key 'GuiLogLanguageChanged' -Fallback 'Language changed to: {0}' -FormatArgs @($langCode))
			}

			$setSelectedGuiLanguageCommand = ${function:Set-SelectedGuiLanguage}
			$Script:SetSelectedGuiLanguageScript = $setSelectedGuiLanguageCommand
			$renderLanguageList = {
				param ([string]$FilterText = '')

				$currentCode = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
				if ($currentCode -eq 'en') { $currentCode = 'en-US' }
				$normalizedFilter = if ([string]::IsNullOrWhiteSpace([string]$FilterText)) { '' } else { ([string]$FilterText).Trim().ToLowerInvariant() }
				$LanguageListPanel.Children.Clear()

				$matchingEntries = if ([string]::IsNullOrWhiteSpace($normalizedFilter))
				{
					@($languageEntries)
				}
				else
				{
					@($languageEntries | Where-Object {
						$searchIndex = [string]$_.SearchIndex
						$searchIndex.IndexOf($normalizedFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
					})
				}

				if ($matchingEntries.Count -eq 0)
				{
					$emptyState = [System.Windows.Controls.TextBlock]::new()
					$emptyState.Text = (& $getUxLocalizedStringCapture -Key 'GuiLanguageSearchNoResults' -Fallback 'No languages found.')
					$emptyState.TextWrapping = 'Wrap'
					$emptyState.Margin = [System.Windows.Thickness]::new(10, 8, 10, 6)
					$emptyState.FontSize = 11
					$emptyState.HorizontalAlignment = 'Left'
					[void]$LanguageListPanel.Children.Add($emptyState)
					if ($setFilterControlStyleCapture) { & $setFilterControlStyleCapture }
					return
				}

				foreach ($entry in $matchingEntries)
				{
					$langBtn = [System.Windows.Controls.Button]::new()
					$langBtn.Tag = [string]$entry.Code
					$langBtn.Cursor = [System.Windows.Input.Cursors]::Hand
					$langBtn.HorizontalContentAlignment = 'Left'
					$langBtn.Padding = [System.Windows.Thickness]::new(12, 5, 12, 5)
					$langBtn.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
					$langBtn.Width = 240
					$langBtn.ClickMode = [System.Windows.Controls.ClickMode]::Press
					$langBtn.BorderThickness = [System.Windows.Thickness]::new(0)
					$langBtn.Background = [System.Windows.Media.Brushes]::Transparent

					# Dual-line content: Native name (bold) + English name (muted)
					$isActive = [string]$entry.Code -eq $currentCode
					$langStack = [System.Windows.Controls.StackPanel]::new()
					$langStack.Orientation = 'Vertical'
					$nativeBlock = [System.Windows.Controls.TextBlock]::new()
					$nativeBlock.Text = [string]$entry.NativeName
					$nativeBlock.FontSize = 12
					$nativeBlock.FontWeight = if ($isActive) { [System.Windows.FontWeights]::Bold } else { [System.Windows.FontWeights]::Normal }
					[void]$langStack.Children.Add($nativeBlock)
					if ([string]$entry.NativeName -ne [string]$entry.EnglishName)
					{
						$engBlock = [System.Windows.Controls.TextBlock]::new()
						$engBlock.Text = [string]$entry.EnglishName
						$engBlock.FontSize = 10
						$engBlock.Opacity = 0.6
						[void]$langStack.Children.Add($engBlock)
					}
					$langBtn.Content = $langStack

					$langBtn.Add_Click({
						param($buttonSender, $buttonEventArgs)
						$null = $buttonEventArgs
						& $setSelectedGuiLanguageCommand ([string]$buttonSender.Tag)
					})

					[void]$LanguageListPanel.Children.Add($langBtn)
				}

				if ($setFilterControlStyleCapture) { & $setFilterControlStyleCapture }
			}.GetNewClosure()

			if ($TxtLanguageSearch)
			{
				if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'GotKeyboardFocus' -Handler ({
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'LostKeyboardFocus' -Handler ({
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'TextChanged' -Handler ({
					if ($LanguageListPanel)
					{
						& $renderLanguageList -FilterText ([string]$TxtLanguageSearch.Text)
					}
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
			}

			if ($TxtLanguageState)
			{
				$currentLanguageCode = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
				$TxtLanguageState.Text = $currentLanguageCode.ToUpperInvariant()
			}

			$null = Register-GuiEventHandler -Source $LanguagePopup -EventName 'Opened' -Handler ({
				if ($TxtLanguageSearch)
				{
					if (-not [string]::IsNullOrWhiteSpace([string]$TxtLanguageSearch.Text))
					{
						$TxtLanguageSearch.Text = ''
					}
					else
					{
						& $renderLanguageList -FilterText ''
					}
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
					$null = $TxtLanguageSearch.Focus()
				}
				else
				{
					& $renderLanguageList -FilterText ''
				}
			}.GetNewClosure())
		}
	}
	finally
	{
		$Script:FilterUiUpdating = $false
	}
	Set-FilterControlStyle

	$Script:SuppressPrimaryTabSelectionChanged = $true
	$updateCurrentTabContentScript = ${function:Update-CurrentTabContent}
	$saveTabScrollOffsetScript = ${function:Save-CurrentTabScrollOffset}
		Register-GuiEventHandler -Source $PrimaryTabs -EventName 'SelectionChanged' -Handler ({
			param($tabEventSender, $e)
			if (-not $e) { return }
		if ($e.Source -ne $PrimaryTabs) { return }
		if ($Script:SuppressPrimaryTabSelectionChanged) { return }
		$skipIdlePrebuild = [bool]$Script:SkipIdlePrebuildOnNextPrimaryTabSelection
		$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = $false
		& $saveTabScrollOffsetScript
		$selected = $PrimaryTabs.SelectedItem
		if ($selected -and $selected.Tag)
		{
			if ([string]$selected.Tag -ne $Script:SearchResultsTabTag)
			{
				$Script:LastStandardPrimaryTab = [string]$selected.Tag
				}
				# Defer content build so the tab header switches immediately
				$null = Invoke-GuiDispatcherAction -Dispatcher $PrimaryTabs.Dispatcher -PriorityUsage 'DeferredContentBuild' -Action {
						try { & $updateCurrentTabContentScript -SkipIdlePrebuild:$skipIdlePrebuild }
						catch {
							$showFn = $Script:ShowGuiRuntimeFailureScript
							if ($showFn) { $null = & $showFn -Context 'PrimaryTabs/SelectionChanged' -Exception $_.Exception -ShowDialog }
							else { Write-Warning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'GUI event failed: PrimaryTabs/SelectionChanged') }
						}
				}
		}
	}) | Out-Null

	# Keep the desktop UI on a stable single-row tab strip so the primary
	# navigation does not reshuffle when Safe/Expert/Game Mode state changes.
	$Script:AdaptiveTabMode = 'tabs'
	$Script:SuppressDropdownSync = $false

	$adaptiveTabLayoutScript = {
		$availableTabWidth = if ($PrimaryTabHost -and $PrimaryTabHost.ActualWidth -gt 0)
		{
			[double]$PrimaryTabHost.ActualWidth
		}
		elseif ($Form.ActualWidth -gt 0)
		{
			[Math]::Max(0, [double]$Form.ActualWidth - 16)
		}
		else
		{
			0
		}
		if ($availableTabWidth -le 0) { return }

		$padding = if ($availableTabWidth -ge 1400)
		{
			[System.Windows.Thickness]::new(16, 6, 16, 6)
		}
		else
		{
			[System.Windows.Thickness]::new(8, 6, 8, 6)
		}

		foreach ($tabItem in $PrimaryTabs.Items)
		{
			if (-not ($tabItem -is [System.Windows.Controls.TabItem]))
			{
				continue
			}

			$tabItem.Padding = $padding
		}

		$Script:AdaptiveTabMode = 'tabs'
		if ($PrimaryTabDropdown)
		{
			$PrimaryTabDropdown.Visibility = [System.Windows.Visibility]::Collapsed
		}
		$PrimaryTabs.Visibility = [System.Windows.Visibility]::Visible

		# Keep the fixed one-row header strip visible and refresh the selected
		# tab's visual state after any width change.
		$selectedTab = $PrimaryTabs.SelectedItem
		if ($selectedTab -is [System.Windows.Controls.TabItem])
		{
			try { $selectedTab.BringIntoView() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildPrimaryTabs.AdaptiveTabLayout.BringIntoView' }
		}
	}
	$Script:AdaptiveTabLayoutScript = $adaptiveTabLayoutScript

	Register-GuiEventHandler -Source $Form -EventName 'SizeChanged' -Handler ({
		& $Script:AdaptiveTabLayoutScript
	}) | Out-Null

	# Select the startup tab now, then hydrate only that tab. Build-TabContent
	# owns GuiReady so the splash closes after foreground content is interactive.
	if (-not ($PrimaryTabs -is [System.Windows.Controls.TabControl]))
	{
		throw "PrimaryTabs is not a TabControl. Actual type: $($PrimaryTabs.GetType().FullName)"
	}

	$showGuiRuntimeFailureCapture = $Script:ShowGuiRuntimeFailureScript
	$updateCurrentTabContentScript = ${function:Update-CurrentTabContent}
	$startGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Start-GuiPerfScope'
	$stopGuiPerfScopeScript = Get-GuiFunctionCapture -Name 'Stop-GuiPerfScope'
	$startupHydratePrimaryTab = if (-not [string]::IsNullOrWhiteSpace([string]$Script:StartupHydratePrimaryTab)) { [string]$Script:StartupHydratePrimaryTab } else { 'Initial Setup' }
	$startupRestoreSessionPending = [bool]$Script:StartupRestoreSessionPending
	$initialTabBuildAction = {
		$__perf = if ($startGuiPerfScopeScript) { & $startGuiPerfScopeScript -Name 'BuildPrimaryTabs.InitialTabHydrate' } else { $null }
		try
		{
			& $updateCurrentTabContentScript -SkipIdlePrebuild
		}
		catch
		{
			if ($showGuiRuntimeFailureCapture) { $null = & $showGuiRuntimeFailureCapture -Context 'InitialTabBuild' -Exception $_.Exception -ShowDialog }
			else { Write-Warning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'GUI event failed: InitialTabBuild') }
		}
		finally
		{
			if ($stopGuiPerfScopeScript) { & $stopGuiPerfScopeScript -Scope $__perf }
		}
	}.GetNewClosure()

	if ($PrimaryTabs.Items.Count -gt 0)
	{
		try
		{
			$null = Invoke-GuiDispatcherAction -Dispatcher $PrimaryTabs.Dispatcher -PriorityUsage 'Immediate' -Action {
					try
					{
						$firstTab = if ($PrimaryTabs.Items.Count -gt 0) { $PrimaryTabs.Items[0] } else { $null }
						$selectedTab = if ($PrimaryTabs.SelectedItem) { $PrimaryTabs.SelectedItem } else { $null }
						$startupTargetTab = $null
						if (-not [string]::IsNullOrWhiteSpace($startupHydratePrimaryTab))
						{
							foreach ($tabItem in $PrimaryTabs.Items)
							{
								if (($tabItem -is [System.Windows.Controls.TabItem]) -and $tabItem.Tag -and ([string]$tabItem.Tag -eq $startupHydratePrimaryTab))
								{
									$startupTargetTab = $tabItem
									break
								}
							}
						}
						$targetTab = if ($startupTargetTab) { $startupTargetTab } elseif ($selectedTab) { $selectedTab } else { $firstTab }
						if ($null -eq $targetTab)
						{
							return
						}

						if ($PrimaryTabs.SelectedItem -ne $targetTab)
						{
							$PrimaryTabs.SelectedItem = $targetTab
						}

						if ($targetTab.Tag -and [string]$targetTab.Tag -ne $Script:SearchResultsTabTag)
						{
							$Script:LastStandardPrimaryTab = [string]$targetTab.Tag
						}

						if (-not $startupRestoreSessionPending)
						{
							$null = $PrimaryTabs.Dispatcher.BeginInvoke(
								[System.Action]$initialTabBuildAction,
								[System.Windows.Threading.DispatcherPriority]::Background
							)
						}
					}
					catch
					{
						if ($showGuiRuntimeFailureCapture) { $null = & $showGuiRuntimeFailureCapture -Context 'InitialTabBuild' -Exception $_.Exception -ShowDialog }
						else { Write-Warning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'GUI event failed: InitialTabBuild') }
					}
					finally
					{
						$Script:SuppressPrimaryTabSelectionChanged = $false
					}
				}
		}
		catch
		{
			$Script:SuppressPrimaryTabSelectionChanged = $false
			throw
		}
	}
	else
	{
		$Script:SuppressPrimaryTabSelectionChanged = $false
	}
