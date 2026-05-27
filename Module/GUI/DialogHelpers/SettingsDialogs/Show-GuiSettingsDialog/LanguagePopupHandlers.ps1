if ($settingsLanguagePopup)
		{
			$settingsLanguagePopup.Add_Opened({
				param ($popupSender, $popupArgs)
				$null = $popupSender
				$null = $popupArgs
				if ($txtSettingsLanguageSearch)
				{
					$txtSettingsLanguageSearch.Text = ''
					[void]$txtSettingsLanguageSearch.Focus()
				}
				if ($languageUiState.Render) { & $languageUiState.Render '' }
			}.GetNewClosure())
		}
