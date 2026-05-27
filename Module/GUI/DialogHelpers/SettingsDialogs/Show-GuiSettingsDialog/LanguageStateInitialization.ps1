$settingsLanguageState = @{
			Code = if ($Current.ContainsKey('Language') -and -not [string]::IsNullOrWhiteSpace([string]$Current.Language))
			{
				[string]$Current.Language
			}
			elseif ($Script:SelectedLanguage)
			{
				[string]$Script:SelectedLanguage
			}
			else
			{
				'en'
			}
		}
