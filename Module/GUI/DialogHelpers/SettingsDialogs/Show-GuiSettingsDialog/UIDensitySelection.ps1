if ($cmbUIDensity)
		{
			& $addComboItem $cmbUIDensity $settingsOptionDensityComfort 'Comfort'
			& $addComboItem $cmbUIDensity $settingsOptionDensityCompact 'Compact'
			& $addComboItem $cmbUIDensity $settingsOptionDensityHigh 'High Density'
			$selectedDensity = if ($Current.ContainsKey('UIDensity') -and -not [string]::IsNullOrWhiteSpace([string]$Current.UIDensity)) { [string]$Current.UIDensity } else { 'Comfort' }
			if (Get-Command -Name 'Normalize-BaselineUiDensity' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$selectedDensity = Normalize-BaselineUiDensity -Density $selectedDensity
			}
			& $selectComboByTag $cmbUIDensity $selectedDensity
		}
