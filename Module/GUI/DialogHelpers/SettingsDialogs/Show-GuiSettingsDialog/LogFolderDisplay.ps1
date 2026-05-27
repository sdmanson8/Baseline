$refreshLogFolderDisplay = {
			$expertEnabled = $chkAdvancedMode -and [bool]$chkAdvancedMode.IsChecked
			$effectiveDirectory = & $getEffectiveLogDirectory
			if ($txtLogFolderPath) { $txtLogFolderPath.Text = $effectiveDirectory }
			if ($btnLogFolderBrowse)
			{
				$btnLogFolderBrowse.Visibility = if ($expertEnabled) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			}
			if ($txtLogFolderHelper)
			{
				$txtLogFolderHelper.Text = if ($expertEnabled)
				{
					$settingsLogFolderExpertHelper
				}
				else
				{
					$settingsLogFolderEnableExpertHelper
				}
			}
		}.GetNewClosure()
