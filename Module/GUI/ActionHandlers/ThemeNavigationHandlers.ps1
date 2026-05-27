
	#region Theme toggle handler
	Register-GuiEventHandler -Source $ChkTheme -EventName 'Checked' -Handler ({
		if ($Script:ThemeUiUpdating) { return }
		Invoke-CapturedFunction -Name 'Apply-BaselineThemePreference' -Parameters @{ Preference = 'Light' }
	}) | Out-Null
	Register-GuiEventHandler -Source $ChkTheme -EventName 'Unchecked' -Handler ({
		if ($Script:ThemeUiUpdating) { return }
		Invoke-CapturedFunction -Name 'Apply-BaselineThemePreference' -Parameters @{ Preference = 'Dark' }
	}) | Out-Null
	if ($NavModeTweaks)
	{
		Register-GuiEventHandler -Source $NavModeTweaks -EventName 'Checked' -Handler ({
			if ($Script:SuppressNavModeSelectionChanged) { return }
			if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiGamingMode -Enable:$false
			}
			if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiUpdatesMode -Enable:$false
			}
			if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiDeploymentMediaMode -Enable:$false
			}
			Set-GuiAppsMode -Enable:$false
		}) | Out-Null
	}
	if ($NavModeGaming)
	{
		Register-GuiEventHandler -Source $NavModeGaming -EventName 'Checked' -Handler ({
			if ($Script:SuppressNavModeSelectionChanged) { return }
			if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiGamingMode -Enable:$true
			}
		}) | Out-Null
	}
	if ($NavModeApps)
	{
		Register-GuiEventHandler -Source $NavModeApps -EventName 'Checked' -Handler ({
			if ($Script:SuppressNavModeSelectionChanged) { return }
			if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiGamingMode -Enable:$false -SkipContentRestore
			}
			if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiUpdatesMode -Enable:$false
			}
			if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiDeploymentMediaMode -Enable:$false
			}
			Set-GuiAppsMode -Enable:$true
		}) | Out-Null
	}
	if ($NavModeUpdates)
	{
		Register-GuiEventHandler -Source $NavModeUpdates -EventName 'Checked' -Handler ({
			if ($Script:SuppressNavModeSelectionChanged) { return }
			if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiGamingMode -Enable:$false -SkipContentRestore
			}
			if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiDeploymentMediaMode -Enable:$false
			}
			if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiUpdatesMode -Enable:$true
			}
		}) | Out-Null
	}
	if ($NavModeDeploymentMedia)
	{
		Register-GuiEventHandler -Source $NavModeDeploymentMedia -EventName 'Checked' -Handler ({
			if ($Script:SuppressNavModeSelectionChanged) { return }
			if (Get-Command -Name 'Set-GuiGamingMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiGamingMode -Enable:$false -SkipContentRestore
			}
			if (Get-Command -Name 'Set-GuiUpdatesMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiUpdatesMode -Enable:$false
			}
			Set-GuiAppsMode -Enable:$false
			if (Get-Command -Name 'Set-GuiDeploymentMediaMode' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-GuiDeploymentMediaMode -Enable:$true
			}
		}) | Out-Null
	}
	#endregion
