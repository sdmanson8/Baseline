if ($cmbLogLevel)
		{
			& $addComboItem $cmbLogLevel $settingsLogLevelAll 'All'
			& $addComboItem $cmbLogLevel $settingsLogLevelError 'Error'
			& $addComboItem $cmbLogLevel $settingsLogLevelWarn 'Warn'
			& $addComboItem $cmbLogLevel $settingsLogLevelInfo 'Info'
			& $addComboItem $cmbLogLevel $settingsLogLevelDebug 'Debug'
			& $addComboItem $cmbLogLevel $settingsLogLevelTrace 'Trace'
			$selectedLogLevel = if ($Current.ContainsKey('LogLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Current.LogLevel)) { [string]$Current.LogLevel } else { 'All' }
			if (Get-Command -Name 'Normalize-GuiLogLevel' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$selectedLogLevel = Normalize-GuiLogLevel -Level $selectedLogLevel
			}
			& $selectComboByTag $cmbLogLevel $selectedLogLevel
		}
