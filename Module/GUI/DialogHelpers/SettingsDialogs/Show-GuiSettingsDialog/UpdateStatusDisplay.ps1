$getUpdateStatusDisplay = {
			param ([string]$Status)
			switch ([string]$Status)
			{
				'Up to date' { return $settingsUpdateStatusUpToDate }
				'Update available' { return $settingsUpdateStatusAvailable }
				'Failed' { return $settingsUpdateStatusFailed }
				'Skipped (offline)' { return $settingsUpdateStatusOffline }
				'Disabled' { return $settingsUpdateStatusDisabled }
				default { return $settingsUpdateStatusNotChecked }
			}
		}.GetNewClosure()
