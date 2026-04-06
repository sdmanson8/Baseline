# GUI session state, undo snapshots, and settings profile management

	function Resolve-GuiModePreference
	{
		param (
			[bool]$SafeMode,
			[bool]$AdvancedMode
		)

		if ($SafeMode)
		{
			return [pscustomobject]@{
				SafeMode = $true
				AdvancedMode = $false
			}
		}

		if ($AdvancedMode)
		{
			return [pscustomobject]@{
				SafeMode = $false
				AdvancedMode = $true
			}
		}

		return [pscustomobject]@{
			SafeMode = $true
			AdvancedMode = $false
		}
	}

	function Save-GuiUndoSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$Script:UiSnapshotUndo = Get-GuiSettingsSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
	}

	function Get-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$themeName = if ($ChkTheme) {
			if ($ChkTheme.IsChecked) { 'Light' } else { 'Dark' }
		}
		elseif ($Script:CurrentThemeName) {
			[string]$Script:CurrentThemeName
		}
		else {
			'Dark'
		}

		$searchText = if ($TxtSearch) { [string]$TxtSearch.Text } elseif ($null -ne $Script:SearchText) { [string]$Script:SearchText } else { '' }
		# System scan is transient machine state. Persisting it across launches can silently
		# re-run expensive detection work during startup, so session snapshots always store it off.
		$scanEnabled = $false
		$currentPrimaryTab = if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}

		$snapshot = [ordered]@{
			Schema = 'Baseline.GuiSettings'
			SchemaVersion = 9
			SavedAt = (Get-Date).ToString('o')
			Theme = $themeName
			Language = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
			SearchText = $searchText
			ScanEnabled = $scanEnabled
			AdvancedMode = [bool]$Script:AdvancedMode
			SafeMode = [bool]$Script:SafeMode
			GameMode = [bool]$Script:GameMode
			GameModeProfile = if ($Script:GameModeProfile) { [string]$Script:GameModeProfile } else { $null }
			GameModeCorePlan = @($Script:GameModeCorePlan)
			GameModePlan = @($Script:GameModePlan)
			GameModeDecisionOverrides = Convert-JsonManifestValue $Script:GameModeDecisionOverrides
			GameModeAdvancedSelections = Convert-JsonManifestValue $Script:GameModeAdvancedSelections
			GameModePreviousPrimaryTab = if ($Script:GameModePreviousPrimaryTab) { [string]$Script:GameModePreviousPrimaryTab } else { $null }
			RiskFilter = if ($Script:RiskFilter) { [string]$Script:RiskFilter } else { 'All' }
			CategoryFilter = if ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
			SelectedOnlyFilter = [bool]$Script:SelectedOnlyFilter
			HighRiskOnlyFilter = [bool]$Script:HighRiskOnlyFilter
			RestorableOnlyFilter = [bool]$Script:RestorableOnlyFilter
			GamingOnlyFilter = [bool]$Script:GamingOnlyFilter
			CurrentPrimaryTab = $currentPrimaryTab
			LastStandardPrimaryTab = if ($Script:LastStandardPrimaryTab) { [string]$Script:LastStandardPrimaryTab } else { $null }
			ExplicitSelections = @($Script:ExplicitPresetSelections)
			ExplicitSelectionDefinitions = @(
				$Script:ExplicitPresetSelectionDefinitions.GetEnumerator() |
					Sort-Object Key |
					ForEach-Object {
						Copy-GuiExplicitSelectionDefinition -Definition $_.Value -FunctionName ([string]$_.Key)
					}
			)
			Controls = $null
		}

		$controlList = [System.Collections.Generic.List[pscustomobject]]::new($Script:TweakManifest.Count)
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			$entry = [ordered]@{
				Index = $i
				Function = $manifest.Function
				Type = $manifest.Type
			}

			switch ($manifest.Type)
			{
				'Choice'
				{
					$selectedIndex = -1
					if ($control -and (Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						$selectedIndex = [int]$control.SelectedIndex
					}
					$selectedValue = $null
					if ($selectedIndex -ge 0 -and $selectedIndex -lt $manifest.Options.Count)
					{
						$selectedValue = [string]$manifest.Options[$selectedIndex]
					}
					$entry.SelectedIndex = [int]$selectedIndex
					$entry.SelectedValue = $selectedValue
				}
				default
				{
					$entry.IsChecked = if ($control -and (Test-GuiObjectField -Object $control -FieldName 'IsChecked')) { [bool]$control.IsChecked } else { $false }
				}
			}

			$controlList.Add([pscustomobject]$entry)
		}

		$snapshot.Controls = $controlList.ToArray()
		return [pscustomobject]$snapshot
	}

	function Restore-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[Parameter(Mandatory = $true)]
			[object]
			$Snapshot
		)

		if (-not $Snapshot)
		{
			throw "No GUI settings snapshot was supplied."
		}

		Clear-TabContentCache

		$controlStates = @{}
		if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Controls'))
		{
			foreach ($entry in @($Snapshot.Controls))
			{
				if ($entry -and (Test-GuiObjectField -Object $entry -FieldName 'Function'))
				{
					$controlStates[[string]$entry.Function] = $entry
				}
			}
		}

		Initialize-GuiSelectionStateStores
		$Script:ExplicitPresetSelections.Clear()
		$Script:ExplicitPresetSelectionDefinitions.Clear()
		if ((Test-GuiObjectField -Object $Snapshot -FieldName 'ExplicitSelectionDefinitions') -and $null -ne $Snapshot.ExplicitSelectionDefinitions)
		{
			foreach ($selectionDefinition in @($Snapshot.ExplicitSelectionDefinitions))
			{
				$functionName = if ($selectionDefinition -and (Test-GuiObjectField -Object $selectionDefinition -FieldName 'Function')) { [string]$selectionDefinition.Function } else { $null }
				if (-not [string]::IsNullOrWhiteSpace($functionName))
				{
					Set-GuiExplicitSelectionDefinition -FunctionName $functionName -Definition $selectionDefinition
				}
			}
		}
		elseif ((Test-GuiObjectField -Object $Snapshot -FieldName 'ExplicitSelections'))
		{
			foreach ($functionName in @($Snapshot.ExplicitSelections))
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
				{
					[void]$Script:ExplicitPresetSelections.Add([string]$functionName)
				}
			}
		}

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			if (-not $control) { continue }

			$state = $controlStates[$manifest.Function]
			if (-not $state) { continue }

			switch ($manifest.Type)
			{
				'Choice'
				{
					if ((Test-GuiObjectField -Object $control -FieldName 'SelectedIndex'))
					{
						$selectedIndex = -1
						if ($manifest.Options -and (Test-GuiObjectField -Object $state -FieldName 'SelectedValue') -and -not [string]::IsNullOrWhiteSpace([string]$state.SelectedValue))
						{
							$selectedIndex = [array]::IndexOf(@($manifest.Options), [string]$state.SelectedValue)
						}
						if ($selectedIndex -lt 0 -and (Test-GuiObjectField -Object $state -FieldName 'SelectedIndex'))
						{
							$selectedIndex = [int]$state.SelectedIndex
						}
						$optCount = if ($manifest.Options) { $manifest.Options.Count } else { 0 }
						if ($selectedIndex -ge $optCount) { $selectedIndex = -1 }
						[int]$idx = $selectedIndex
						$control.SelectedIndex = $idx
					}
				}
				default
				{
					if ((Test-GuiObjectField -Object $control -FieldName 'IsChecked'))
					{
						$control.IsChecked = [bool]$state.IsChecked
					}
				}
			}
		}

		$desiredTheme = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Theme')) { [string]$Snapshot.Theme } else { 'Dark' }
		# System scan must be rerun explicitly for the current machine state instead of being
		# replayed from a saved session.
		$desiredScan  = $false
		$desiredLanguage = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'Language') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.Language)) { [string]$Snapshot.Language } else { $null }
		$desiredSearch = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SearchText')) { [string]$Snapshot.SearchText } else { '' }
		$desiredSafe = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SafeMode')) { [bool]$Snapshot.SafeMode } else { $false }
		$desiredAdvanced = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'AdvancedMode')) { [bool]$Snapshot.AdvancedMode } else { $false }
		$desiredGameMode = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameMode')) { [bool]$Snapshot.GameMode } else { $false }
		$desiredGameModeProfile = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeProfile')) { [string]$Snapshot.GameModeProfile } else { $null }
		$desiredGameModeCorePlan = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeCorePlan')) { @($Snapshot.GameModeCorePlan) } else { @() }
		$desiredGameModePlan = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModePlan')) { @($Snapshot.GameModePlan) } else { @() }
		$desiredGameModeDecisionOverrides = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeDecisionOverrides') -and $null -ne $Snapshot.GameModeDecisionOverrides) { Convert-JsonManifestValue $Snapshot.GameModeDecisionOverrides } else { @{} }
		$desiredGameModeAdvancedSelections = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModeAdvancedSelections') -and $null -ne $Snapshot.GameModeAdvancedSelections) { Convert-JsonManifestValue $Snapshot.GameModeAdvancedSelections } else { @{} }
		$desiredGameModePreviousPrimaryTab = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GameModePreviousPrimaryTab')) { [string]$Snapshot.GameModePreviousPrimaryTab } else { $null }
		$desiredModePreference = Resolve-GuiModePreference -SafeMode $desiredSafe -AdvancedMode $desiredAdvanced
		$desiredSafe = [bool]$desiredModePreference.SafeMode
		$desiredAdvanced = [bool]$desiredModePreference.AdvancedMode
		$desiredRisk = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RiskFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.RiskFilter)) { [string]$Snapshot.RiskFilter } else { 'All' }
		$desiredCategory = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'CategoryFilter') -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.CategoryFilter)) { [string]$Snapshot.CategoryFilter } else { 'All' }
		$desiredSelectedOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'SelectedOnlyFilter')) { [bool]$Snapshot.SelectedOnlyFilter } else { $false }
		$desiredHighRiskOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'HighRiskOnlyFilter')) { [bool]$Snapshot.HighRiskOnlyFilter } else { $false }
		$desiredRestorableOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'RestorableOnlyFilter')) { [bool]$Snapshot.RestorableOnlyFilter } else { $false }
		$desiredGamingOnly = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'GamingOnlyFilter')) { [bool]$Snapshot.GamingOnlyFilter } else { $false }
		$desiredTab   = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'CurrentPrimaryTab')) { [string]$Snapshot.CurrentPrimaryTab } else { $null }
		$desiredLast  = if ((Test-GuiObjectField -Object $Snapshot -FieldName 'LastStandardPrimaryTab')) { [string]$Snapshot.LastStandardPrimaryTab } else { $null }

		if ($desiredLast)
		{
			$Script:LastStandardPrimaryTab = $desiredLast
		}
		if (-not [string]::IsNullOrWhiteSpace($desiredGameModePreviousPrimaryTab))
		{
			$Script:GameModePreviousPrimaryTab = $desiredGameModePreviousPrimaryTab
		}

		if ($ChkTheme)
		{
			if ($desiredTheme -eq 'Light' -and -not $ChkTheme.IsChecked)
			{
				$ChkTheme.IsChecked = $true
			}
			elseif ($desiredTheme -ne 'Light' -and $ChkTheme.IsChecked)
			{
				$ChkTheme.IsChecked = $false
			}
		}
		else
		{
			if ($desiredTheme -eq 'Light')
			{
				Set-GUITheme -Theme $Script:LightTheme
			}
			else
			{
				Set-GUITheme -Theme $Script:DarkTheme
			}
		}

		# Restore saved language preference.
        if ($desiredLanguage)
        {
            $Script:SelectedLanguage = $desiredLanguage
            $locDir = $Script:GuiLocalizationDirectoryPath
            if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
            {
                $Global:Localization = Import-BaselineLocalization -BaseDirectory $locDir -UICulture $desiredLanguage
            }
        }

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:ScanEnabled = $desiredScan
			$Script:EnvironmentRecommendationData = $null
			$Script:EnvironmentSummaryText = $null
			if ($ChkScan)
			{
				if ($ChkScan.IsChecked -ne $desiredScan)
				{
					$ChkScan.IsChecked = $desiredScan
				}
			}

			$Script:SafeMode = $desiredSafe
			$Script:AdvancedMode = $desiredAdvanced
			if ($ChkSafeMode)
			{
				$ChkSafeMode.IsChecked = $desiredSafe
				$ChkSafeMode.Content = 'Safe Mode'
			}

			$Script:GameMode = $desiredGameMode
			$Script:GameModeProfile = if ([string]::IsNullOrWhiteSpace($desiredGameModeProfile)) { $null } else { $desiredGameModeProfile }
			$Script:GameModeCorePlan = @($desiredGameModeCorePlan)
			$Script:GameModePlan = @($desiredGameModePlan)
			$Script:GameModeDecisionOverrides = @{}
			foreach ($overrideKey in @($desiredGameModeDecisionOverrides.Keys))
			{
				if ([string]::IsNullOrWhiteSpace([string]$overrideKey)) { continue }
				$Script:GameModeDecisionOverrides[[string]$overrideKey] = [string]$desiredGameModeDecisionOverrides[$overrideKey]
			}
			$Script:GameModeAdvancedSelections = @{}
			foreach ($advSelKey in @($desiredGameModeAdvancedSelections.Keys))
			{
				if ([string]::IsNullOrWhiteSpace([string]$advSelKey)) { continue }
				$Script:GameModeAdvancedSelections[[string]$advSelKey] = [bool]$desiredGameModeAdvancedSelections[$advSelKey]
			}
			if ($ChkGameMode)
			{
				if ([bool]$ChkGameMode.IsChecked -ne $desiredGameMode)
				{
					$ChkGameMode.IsChecked = $desiredGameMode
				}
			}

			$Script:RiskFilter = $desiredRisk
			if ($CmbRiskFilter)
			{
				if ($CmbRiskFilter.Items.Contains($desiredRisk))
				{
					$found = $CmbRiskFilter.Items.IndexOf($desiredRisk)
					if ($found -ge 0) { $CmbRiskFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbRiskFilter.SelectedIndex = $idx
					$Script:RiskFilter = 'All'
				}
			}

			$Script:SelectedOnlyFilter = $desiredSelectedOnly
			if ($ChkSelectedOnly) { $ChkSelectedOnly.IsChecked = $desiredSelectedOnly }
			$Script:HighRiskOnlyFilter = $desiredHighRiskOnly
			if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsChecked = $desiredHighRiskOnly }
			$Script:RestorableOnlyFilter = $desiredRestorableOnly
			if ($ChkRestorableOnly) { $ChkRestorableOnly.IsChecked = $desiredRestorableOnly }
			$Script:GamingOnlyFilter = $desiredGamingOnly
			if ($ChkGamingOnly) { $ChkGamingOnly.IsChecked = $desiredGamingOnly }
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		$Script:SearchText = $desiredSearch
		if ($TxtSearch)
		{
			if ($TxtSearch.Text -ne $desiredSearch)
			{
				$TxtSearch.Text = $desiredSearch
			}
		}

		Update-SearchResultsTabState

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:CategoryFilter = $desiredCategory
			if ($CmbCategoryFilter)
			{
				if ($CmbCategoryFilter.Items.Contains($desiredCategory))
				{
					$found = $CmbCategoryFilter.Items.IndexOf($desiredCategory)
					if ($found -ge 0) { $CmbCategoryFilter.SelectedIndex = [int]$found }
				}
				else
				{
					[int]$idx = 0
					$CmbCategoryFilter.SelectedIndex = $idx
					$Script:CategoryFilter = 'All'
				}
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		Update-CategoryFilterList -PrimaryTab $(if ($desiredSearch) { $Script:SearchResultsTabTag } else { $desiredTab })
		Update-SearchResultsTabState

		if ([string]::IsNullOrWhiteSpace($desiredSearch) -and $desiredTab)
		{
			if ($desiredTab -eq $Script:SearchResultsTabTag)
			{
				$restoreTag = if ($desiredLast) { $desiredLast } else { $Script:LastStandardPrimaryTab }
				$restoreTab = if ($restoreTag) { Get-PrimaryTabItem -Tag $restoreTag } else { $null }
				if (-not $restoreTab)
				{
					foreach ($tab in $PrimaryTabs.Items)
					{
						if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
						{
							$restoreTab = $tab
							break
						}
					}
				}
				if ($restoreTab -and $PrimaryTabs.SelectedItem -ne $restoreTab)
				{
					$PrimaryTabs.SelectedItem = $restoreTab
				}
			}
			else
			{
				$targetTab = Get-PrimaryTabItem -Tag $desiredTab
				if ($targetTab -and $PrimaryTabs.SelectedItem -ne $targetTab)
				{
					$PrimaryTabs.SelectedItem = $targetTab
				}
			}
		}

		# Invalidate tab content cache so the preset panel rebuilds with the
		# restored Safe Mode / Advanced Mode state instead of reusing stale
		# cached content that was built with the default mode values.
		$Script:FilterGeneration++
		if ($Script:ClearTabContentCacheScript) { & $Script:ClearTabContentCacheScript }

		Update-CurrentTabContent
		Update-HeaderModeStateText
		if ($TxtLanguageState -and -not [string]::IsNullOrWhiteSpace([string]$Script:SelectedLanguage))
		{
			$TxtLanguageState.Text = ([string]$Script:SelectedLanguage).ToUpperInvariant()
		}
		if (Get-Command -Name 'Update-GuiLocalizationStrings' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiLocalizationStrings
		}
		if (Get-Command -Name 'Update-PrimaryTabHeaders' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-PrimaryTabHeaders
		}
		if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-UxActionButtonText
		}
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
	}

	function Restore-GuiSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $Script:UiSnapshotUndo)
		{
			return $false
		}

		$redoSnapshot = Get-GuiSettingsSnapshot
		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
		}
		catch
		{
			try
			{
				Restore-GuiSettingsSnapshot -Snapshot $redoSnapshot
			}
			catch { $null = $_ }
			throw "Failed to restore the previous GUI snapshot: $($_.Exception.Message)"
		}

		$Script:UiSnapshotUndo = $redoSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
		return $true
	}

	function Get-GuiSettingsProfileDirectory
	{
		param ()
		return (GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline')
	}

	function Get-GuiSessionStatePath
	{
		param ()
		return (GUICommon\Get-GuiSessionStatePath -AppName 'Baseline')
	}

	function Get-GuiFirstRunWelcomeMarkerPath
	{
		param ()
		return (Join-Path (Get-GuiSettingsProfileDirectory) 'Baseline-first-run-welcome.txt')
	}

	function Test-GuiFirstRunWelcomePending
	{
		param ()
		return (-not (Test-Path -LiteralPath (Get-GuiFirstRunWelcomeMarkerPath)))
	}

	function Complete-GuiFirstRunWelcome
	{
		param ()

		$markerPath = Get-GuiFirstRunWelcomeMarkerPath
		$markerDirectory = Split-Path -Parent $markerPath
		try
		{
			if (-not (Test-Path -LiteralPath $markerDirectory))
			{
				[void](New-Item -ItemType Directory -Path $markerDirectory -Force -ErrorAction Stop)
			}

			(Get-Date).ToString('o') | Set-Content -LiteralPath $markerPath -Encoding UTF8 -Force
			return $true
		}
		catch
		{
			LogWarning "Failed to persist first-run welcome state: $($_.Exception.Message)"
			return $false
		}
	}

	function Import-GuiLastRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiLastRunFilePath
		if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue))
		{
			return $null
		}

		try
		{
			return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json)
		}
		catch
		{
			LogWarning "Failed to load last run profile: $($_.Exception.Message)"
			return $null
		}
	}

	function Clear-GuiLastRunProfile
	{
		param ()

		$path = GUICommon\Get-GuiLastRunFilePath
		if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)
		{
			try
			{
				Remove-Item -LiteralPath $path -Force -ErrorAction Stop
			}
			catch
			{
				LogWarning "Failed to remove last run profile: $($_.Exception.Message)"
			}
		}
		$Script:LastRunProfile = $null
	}

	function Save-GuiSessionState
	{
		param ()
		return (GUICommon\Save-GuiSessionStateDocument -Snapshot (Get-GuiSettingsSnapshot) -AppName 'Baseline')
	}

	function Restore-GuiSessionState
	{
		param ()

		$snapshot = GUICommon\Read-GuiSessionStateDocument -AppName 'Baseline' -ExpectedSchema 'Baseline.GuiSettings'
		if (-not $snapshot)
		{
			return $false
		}

		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $snapshot
			LogInfo "Restored previous GUI session state."
			return $true
		}
		catch
		{
			LogWarning "Failed to restore GUI session state: $($_.Exception.Message)"
			return $false
		}
	}

	function Export-GuiSettingsProfile
	{
		param ()

		$snapshot = Get-GuiSettingsSnapshot
		$savePath = GUICommon\Show-GuiSettingsSaveDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($savePath))
		{
			return $false
		}

		try
		{
			[void](GUICommon\Write-GuiSettingsProfileDocument -Snapshot $snapshot -FilePath $savePath)
			LogInfo "Exported GUI settings to $savePath"
			Set-GuiStatusText -Text "Settings exported to $savePath" -Tone 'accent'
			return $true
		}
		catch
		{
			LogError "Failed to export GUI settings: $($_.Exception.Message)"
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiExportSettings' -Fallback 'Export Settings') -Message "Failed to export settings.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK')
			return $false
		}
	}

	function Import-GuiSettingsProfile
	{
		param ()

		$openPath = GUICommon\Show-GuiSettingsOpenDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($openPath))
		{
			return $false
		}

		try
		{
			$snapshot = GUICommon\Read-GuiSettingsProfileDocument -FilePath $openPath -ExpectedSchema 'Baseline.GuiSettings'
		}
		catch
		{
			LogError "Failed to read GUI settings profile: $($_.Exception.Message)"
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiImportSettings' -Fallback 'Import Settings') -Message "Failed to read the selected profile.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK')
			return $false
		}

		Save-GuiUndoSnapshot
		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $snapshot
			Set-GuiStatusText -Text "Settings imported from $openPath" -Tone 'accent'
			LogInfo "Imported GUI settings from $openPath"
			Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
			return $true
		}
		catch
		{
			LogError "Failed to import GUI settings: $($_.Exception.Message)"
			if ($Script:UiSnapshotUndo)
			{
				try
				{
					Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
				}
				catch { $null = $_ }
			}
			$Script:UiSnapshotUndo = $null
			Set-GuiActionButtonsEnabled -Enabled (-not (& $Script:TestGuiRunInProgressScript))
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiImportSettings' -Fallback 'Import Settings') -Message "Failed to import settings.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK')
			return $false
		}
	}
