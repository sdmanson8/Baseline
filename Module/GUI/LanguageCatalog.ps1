# Shared language display catalog for the Baseline GUI.
# Returns the native/English display names for every supported locale and
# builds a sortable entry list filtered against the localization directory
# on disk. Consumed by BuildPrimaryTabs.ps1 (header language popup) and
# DialogHelpers.ps1 (settings dialog language picker) so the two stay in
# lockstep without duplicating the 124-entry map.

function Get-GuiLanguageDisplayData
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param()

	if ($Script:GuiLanguageDisplayDataCache) { return $Script:GuiLanguageDisplayDataCache }

	$Script:GuiLanguageDisplayDataCache = @{
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

	return $Script:GuiLanguageDisplayDataCache
}

function Get-GuiLanguageEntries
{
	[CmdletBinding()]
	[OutputType([System.Collections.ArrayList])]
	param(
		[string]$LocalizationDirectory
	)

	$langDisplayData = Get-GuiLanguageDisplayData
	$entries = New-Object System.Collections.ArrayList

	if ([string]::IsNullOrWhiteSpace([string]$LocalizationDirectory)) { return }
	if (-not (Test-Path -LiteralPath $LocalizationDirectory)) { return }

	# Locale JSON files live in per-language folders; the root JSON files are
	# metadata (locale-map, schema, exempt-keys) and must not appear in the picker.
	$languageFiles = @(
		Get-ChildItem -LiteralPath $LocalizationDirectory -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue |
			Where-Object { $langDisplayData.ContainsKey($_.BaseName) } |
			Sort-Object @{ Expression = { if ($langDisplayData.ContainsKey($_.BaseName)) { $langDisplayData[$_.BaseName].English } else { $_.BaseName } } }, BaseName
	)

	foreach ($jsonFile in $languageFiles)
	{
		$code = $jsonFile.BaseName
		$nativeName = if ($langDisplayData.ContainsKey($code)) { $langDisplayData[$code].Native } else { $code }
		$englishName = if ($langDisplayData.ContainsKey($code)) { $langDisplayData[$code].English } else { $code }
		[void]$entries.Add([pscustomobject]@{
			Code = $code
			DisplayName = $englishName
			NativeName = $nativeName
			EnglishName = $englishName
			SearchIndex = ("{0} {1} {2} {3}" -f $nativeName, $englishName, $code, ($code -replace '-', ' ')).ToLowerInvariant()
		})
	}

	return $entries
}
