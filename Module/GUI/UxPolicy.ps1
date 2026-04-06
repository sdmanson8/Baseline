# Mode presentation helpers - Safe Mode gets beginner-focused wording while
# the existing full-detail views keep the original wording.
# The execution engine is the same in all views; these only change what the user sees.
#
# Centralized here because Safe Mode / Expert Mode branching was originally scattered across
# five different dialog and summary functions, and the wording kept diverging between them.
# Not a full policy framework - just the branches that were actually painful to keep consistent.

	function Test-IsSafeModeUX
	{
		return ([bool]$Script:SafeMode)
	}

	function Test-IsExpertModeUX
	{
		return ([bool]$Script:AdvancedMode)
	}

	function Get-UxOnboardingMode
	{
		if (Test-IsExpertModeUX)
		{
			return 'Expert'
		}
		if (Test-IsSafeModeUX)
		{
			return 'Safe'
		}

		return 'Standard'
	}

	function Get-UxLocalizedString
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Key,

			[Parameter(Mandatory = $true)]
			[string]$Fallback,

			[object[]]$FormatArgs = @()
		)

		$template = $Fallback
		$localizationSource = $Global:Localization
		if ($null -ne $localizationSource)
		{
			$candidate = $null
			if ($localizationSource -is [System.Collections.IDictionary] -and $localizationSource.Contains($Key))
			{
				$candidate = [string]$localizationSource[$Key]
			}
			elseif ($localizationSource.PSObject -and $localizationSource.PSObject.Properties[$Key])
			{
				$candidate = [string]$localizationSource.$Key
			}

			if (-not [string]::IsNullOrWhiteSpace($candidate))
			{
				$template = $candidate
			}
		}

		if ($FormatArgs.Count -gt 0)
		{
			return ($template -f $FormatArgs)
		}

		return $template
	}

	function Get-UxToggleStateLabel
	{
		param (
			[bool]$Enabled
		)

		if ($Enabled)
		{
			return (Get-UxLocalizedString -Key 'GuiToggleStateEnabled' -Fallback 'Enabled')
		}

		return (Get-UxLocalizedString -Key 'GuiToggleStateDisabled' -Fallback 'Disabled')
	}

	function Get-UxExecutionSummaryDialogStrings
	{
		return @{
			LogFilePrefix = (Get-UxLocalizedString -Key 'GuiExecutionSummaryLogFile' -Fallback 'Log file')
			ImpactSummary = (Get-UxLocalizedString -Key 'GuiPreviewImpactSummary' -Fallback 'Impact summary')
			AllResultsPrefix = (Get-UxLocalizedString -Key 'GuiPreviewStatusAll' -Fallback 'All')
			ExpandDetails = (Get-UxLocalizedString -Key 'GuiPreviewDetailClickExpand' -Fallback 'Click to expand details')
			CollapseDetails = (Get-UxLocalizedString -Key 'GuiPreviewDetailClickCollapse' -Fallback 'Click to collapse')
			ShowAllResultsFormat = (Get-UxLocalizedString -Key 'GuiPreviewShowAllResultsFormat' -Fallback 'Show all {0} results ({1} more)')
		}
	}

	function Get-UxExecutionPlaceholderText
	{
		param (
			[ValidateSet('Preparing', 'Working')]
			[string]$Kind = 'Preparing'
		)

		switch ($Kind)
		{
			'Working' { return (Get-UxLocalizedString -Key 'GuiExecutionWorking' -Fallback 'Working...') }
			default   { return (Get-UxLocalizedString -Key 'GuiExecutionPreparing' -Fallback 'Preparing...') }
		}
	}

	function Get-UxEmptyTabStateMessage
	{
		param (
			[bool]$IsSearchResultsTab,
			[string]$SearchQuery,
			[bool]$HasActiveFilters
		)

		$normalizedQuery = if ($null -eq $SearchQuery) { '' } else { [string]$SearchQuery }
		$hasQuery = -not [string]::IsNullOrWhiteSpace($normalizedQuery)

		if ($IsSearchResultsTab)
		{
			if (-not $hasQuery)
			{
				return (Get-UxLocalizedString -Key 'GuiEmptyStateSearchNoResults' -Fallback 'No tweaks are available across all tabs right now.')
			}

			if ($HasActiveFilters)
			{
				return (Get-UxLocalizedString -Key 'GuiEmptyStateSearchWithFilters' -Fallback "No tweaks match '{0}' with the active filters across all tabs." -FormatArgs @($normalizedQuery))
			}

			return (Get-UxLocalizedString -Key 'GuiEmptyStateSearchQueryOnly' -Fallback "No tweaks match '{0}' across all tabs." -FormatArgs @($normalizedQuery))
		}

		if ($HasActiveFilters)
		{
			if (-not $hasQuery)
			{
				return (Get-UxLocalizedString -Key 'GuiEmptyStateTabFiltersOnly' -Fallback 'No tweaks match the active filters in this tab.')
			}

			return (Get-UxLocalizedString -Key 'GuiEmptyStateTabSearchAndFilters' -Fallback "No tweaks match '{0}' with the active filters in this tab." -FormatArgs @($normalizedQuery))
		}

		if (-not $hasQuery)
		{
			return (Get-UxLocalizedString -Key 'GuiEmptyStateTabNoResults' -Fallback 'No tweaks are available in this tab right now.')
		}

		return (Get-UxLocalizedString -Key 'GuiEmptyStateTabQueryOnly' -Fallback "No tweaks match '{0}' in this tab." -FormatArgs @($normalizedQuery))
	}

	function Get-UxRecommendedPresetName
	{
		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return 'Advanced'
		}

		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return 'Minimal'
		}

		return 'Basic'
	}

	function Get-UxFirstRunPrimaryActionLabel
	{
		if ([bool]$Script:GameMode)
		{
			return 'Review Plan'
		}

		$recommendedPreset = Get-UxRecommendedPresetName
		return ("Start with {0}" -f (Get-UxPresetDisplayName -PresetName $recommendedPreset))
	}

	function Get-UxPresetLoadedStatusText
	{
		param ([string]$PresetName)

		$presetDisplayName = Get-UxPresetDisplayName -PresetName $PresetName
		$previewLabel = Get-UxPreviewButtonLabel
		return ("{0} loaded. Use {1} before applying it." -f $presetDisplayName, $previewLabel)
	}

	function Get-UxStartGuideButtonLabel
	{
		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return 'Quick Start'
		}

		return 'Start Guide'
	}

	function Get-UxHelpButtonLabel
	{
		return 'Help'
	}

	function Get-UxOpenHelpActionLabel
	{
		return 'Open Help'
	}

	function Get-UxPreviewButtonLabel
	{
		return (Get-UxLocalizedString -Key 'GuiBtnPreviewRun' -Fallback 'Preview Run')
	}

	function Get-UxFirstRunDialogTitle
	{
		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return 'Expert Quick Start'
		}

		return 'Welcome to Baseline'
	}

	function Get-UxHelpDialogTitle
	{
		return 'Help'
	}

	function Get-UxHelpDialogSubtitle
	{
		if ([bool]$Script:GameMode -and (Get-UxOnboardingMode) -eq 'Expert')
		{
			return 'Game Mode workflow and execution help'
		}

		switch (Get-UxOnboardingMode)
		{
			'Safe' { return 'Safe Mode guidance and first-run walkthrough' }
			'Expert' { return 'Advanced workflow and execution help' }
			default { return 'Baseline - usage guide' }
		}
	}

	function Get-UxExpertGameModeHelpSections
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$ProfileName,

			[Parameter(Mandatory = $true)]
			[string]$PreviewLabel,

			[Parameter(Mandatory = $true)]
			[string]$ApplyLabel
		)

		return [ordered]@{
			'Game Mode Workflow' = @(
				("Game Mode is active and using the {0} profile." -f $ProfileName)
				'Expert Mode keeps the full gaming workflow visible, including advanced options and risk metadata.'
				'While Game Mode is active, only the Gaming tab plan can be edited or run.'
			)
			'Profiles and Plan Building' = @(
				'Build Profile replaces the current Game Mode plan with a reviewed manifest-backed gaming selection.'
				'Casual, Competitive, Streaming, and Troubleshooting each target a different gaming workflow.'
				'Decision prompts and optional advanced selections refine the active profile before execution.'
			)
			$PreviewLabel = @(
				("{0} shows the active Game Mode plan, including risk, restart required, restore, category, and grouped gaming metadata." -f $PreviewLabel)
				'Use it to inspect the exact gaming actions before applying changes.'
			)
			$ApplyLabel = @(
				("{0} executes the active Game Mode plan only." -f $ApplyLabel)
				'Non-Gaming tabs stay out of scope until Game Mode is turned off.'
				'Outcome states per item: Success, Failed, Skipped, Already Applied.'
			)
			'Risk and Recovery' = @(
				'Risk, restart, direct-undo, and restore-point guidance come from the active plan metadata.'
				'Restore to Windows Defaults resets supported defaults. It is separate from direct undo and rollback export.'
				'Export Rollback Profile, when available after a run, includes only reversible-here undo commands.'
			)
			'Advanced Options' = @(
				'Advanced Options appear only after a profile is selected and only outside Safe Mode.'
				'They expose reviewed expert-only overrides that are not part of every profile by default.'
				'Troubleshooting-only entries stay labeled so diagnostic changes are easy to spot.'
			)
			'System Scan and Logs' = @(
				'System Scan can adjust Game Mode recommendation copy, but it does not change profile defaults automatically.'
				'Open Log shows the session output if you need exact failure or recovery details.'
			)
			'Import / Export / Session Restore' = @(
				'Export/Import saves and restores GUI selections for review, including the active Game Mode state.'
				'Restore Snapshot restores the last captured GUI state only. It does not execute changes.'
				'Turn off Game Mode to return to preset-based workflows.'
			)
		}
	}

	function Get-UxRunActionLabel
	{
		return (Get-UxLocalizedString -Key 'GuiBtnRun' -Fallback 'Run Tweaks')
	}

	function Get-UxPreviewButtonToolTip
	{
		if ([bool]$Script:GameMode)
		{
			switch (Get-UxOnboardingMode)
			{
				'Safe' { return 'Beginner preview for the active Game Mode plan. Review what will run before applying changes.' }
				'Expert' { return 'Expert preview for the active Game Mode plan, including risk, restart, and recovery details.' }
				default { return 'Preview the active Game Mode plan before running it.' }
			}
		}

		switch (Get-UxOnboardingMode)
		{
			'Safe' { return 'Beginner preview: shows what will change in plain language before you run tweaks.' }
			'Expert' { return 'Expert preview: shows full execution plan details, including risk and recovery guidance.' }
			default { return 'Preview what will run from your current selection without applying changes.' }
		}
	}

	function Get-UxRunActionToolTip
	{
		if ([bool]$Script:GameMode)
		{
			switch (Get-UxOnboardingMode)
			{
				'Safe' { return 'Runs the active Game Mode plan with beginner-safe flow. Preview Run is recommended first.' }
				'Expert' { return 'Runs the active Game Mode plan with expert-level scope. Preview Run is recommended first.' }
				default { return 'Runs the active Game Mode plan only.' }
			}
		}

		switch (Get-UxOnboardingMode)
		{
			'Safe' { return 'Applies the selected tweaks using beginner-focused safeguards.' }
			'Expert' { return 'Runs the selected tweaks with full expert scope and detailed execution handling.' }
			default { return 'Runs the currently selected tweaks.' }
		}
	}

	function Get-UxRunPathContext
	{
		if ($Script:GameMode -and [string]$Script:GameModeProfile -eq 'Troubleshooting')
		{
			return @{ Path = 'Troubleshooting'; Label = 'Troubleshoot'; Tone = 'caution' }
		}
		if ([bool]$Script:GameMode)
		{
			return @{ Path = 'GameMode'; Label = "Game: $([string]$Script:GameModeProfile)"; Tone = 'accent' }
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:ActivePresetName))
		{
			return @{ Path = 'Preset'; Label = [string]$Script:ActivePresetName; Tone = 'accent' }
		}
		if ($Script:ActiveScenarioNames -is [hashtable] -and $Script:ActiveScenarioNames.Count -gt 0)
		{
			$scenarioLabel = @($Script:ActiveScenarioNames.Keys | Sort-Object) -join ' + '
			return @{ Path = 'Scenario'; Label = "Scenario: $scenarioLabel"; Tone = 'accent' }
		}
		return @{ Path = 'Manual'; Label = 'Mode: Custom Selection'; Tone = 'accent' }
	}

	function Get-UxRunPathConfirmationMessage
	{
		param ([hashtable]$RunPathContext)
		$previewLabel = Get-UxPreviewButtonLabel

		switch ($RunPathContext.Path)
		{
			'Preset'
			{
				return "Apply $($RunPathContext.Label) preset? $previewLabel is recommended first."
			}
			'Troubleshooting'
			{
				return 'Run troubleshooting profile? This targets gaming-related settings only.'
			}
			'GameMode'
			{
				return "Apply $($RunPathContext.Label) profile? $previewLabel is recommended first."
			}
			default
			{
				return "Apply custom selection? This includes tweaks you selected individually. $previewLabel is strongly recommended."
			}
		}
	}

	function Get-UxUndoSelectionActionLabel
	{
		if ((Test-IsSafeModeUX) -or (Test-IsExpertModeUX))
		{
			return 'Undo Selection Change'
		}

		return 'Restore Snapshot'
	}

	function Get-UxUndoProfileActionLabel
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return 'Export Undo Profile'
		}

		return 'Export Rollback Profile'
	}

	function Get-UxScenarioHeading
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return 'Optional: Scenario Profiles'
		}

		return (Get-UxLocalizedString -Key 'GuiScenarioModesHeading' -Fallback 'Scenario Modes')
	}

	function Get-UxQuickStartSteps
	{
		$previewLabel = Get-UxPreviewButtonLabel
		$isGameModeActive = [bool]$Script:GameMode
		$gameModeProfile = if ([string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { 'Gaming' } else { [string]$Script:GameModeProfile }

		if ($isGameModeActive)
		{
			return @(
				("Game Mode is active and using the {0} profile." -f $gameModeProfile)
				("Review the gaming profile and selected gaming tweaks with {0}." -f $previewLabel)
				('Click {0} to apply the gaming plan.' -f (Get-UxRunActionLabel))
			)
		}

		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return @(
				'Load Advanced to start from the full expert preset, or customize individual tweaks.'
				("Click {0} to inspect risk, restart, and recovery details before applying anything." -f $previewLabel)
				('Click {0} to apply the reviewed selection.' -f (Get-UxRunActionLabel))
			)
		}

		return @(
			("Choose a preset - {0} is recommended for most users." -f (Get-UxRecommendedPresetName))
			("Click {0} to see what will change." -f $previewLabel)
			('Click {0} to apply.' -f (Get-UxRunActionLabel))
		)
	}

	function Get-UxUndoAndRestoreLines
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return @(
				("{0} restores the last preset or imported selection change in the GUI." -f (Get-UxUndoSelectionActionLabel))
				'Restore to Windows Defaults restores supported tweaks to their Windows defaults.'
				("{0}, when it appears after a run, saves reversible-here undo commands for supported changes." -f (Get-UxUndoProfileActionLabel))
				'Some destructive or one-way actions require manual recovery.'
			)
		}

		return @(
			'Restore Snapshot restores the last captured GUI state only. It does not execute tweaks.'
			'Restore to Windows Defaults restores supported tweaks to their Windows defaults.'
			'Export Rollback Profile, when it appears after a run, saves reversible-here undo commands only.'
			'Some destructive or one-way actions require manual recovery.'
		)
	}

	function Get-UxImportExportLines
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return @(
				'Export Settings saves the current GUI selection to a file.'
				'Import Settings restores a saved selection into the GUI for review before you apply it.'
			)
		}

		return @(
			'Export Settings saves the current GUI selection to a file.'
			'Import Settings restores a saved selection into the GUI for review before execution.'
		)
	}

	function Get-UxFirstRunWelcomeMessage
	{
		$onboardingMode = Get-UxOnboardingMode
		$previewLabel = Get-UxPreviewButtonLabel
		$runLabel = Get-UxRunActionLabel
		$isGameModeActive = [bool]$Script:GameMode
		$gameModeProfile = if ([string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { 'Gaming' } else { [string]$Script:GameModeProfile }
		$lines = [System.Collections.Generic.List[string]]::new()

		if ($isGameModeActive)
		{
			if ($onboardingMode -eq 'Expert')
			{
				[void]$lines.Add('Expert Mode is active with Game Mode enabled.')
				[void]$lines.Add('')
				[void]$lines.Add(("Game Mode is currently driving the {0} profile plan, so preset onboarding is skipped while it is active." -f $gameModeProfile))
				[void]$lines.Add('')
				[void]$lines.Add(([char]0x2022 + (" {0} to inspect gaming actions, risk, restart, and recovery guidance." -f $previewLabel)))
				[void]$lines.Add(([char]0x2022 + ' Use the Gaming tab controls to refine the active game profile plan.'))
				[void]$lines.Add(([char]0x2022 + ' Turn off Game Mode if you want to return to preset-based workflows.'))
				[void]$lines.Add('')
				[void]$lines.Add('Quick Start:')
				[void]$lines.Add(("1. Review the active {0} game profile plan" -f $gameModeProfile))
				[void]$lines.Add(("2. {0}" -f $previewLabel))
				[void]$lines.Add(("3. {0}" -f $runLabel))
			}
			else
			{
				[void]$lines.Add('Baseline helps you safely optimize Windows settings.')
				[void]$lines.Add('')
				[void]$lines.Add(("Game Mode is active and using the {0} profile." -f $gameModeProfile))
				[void]$lines.Add('')
				[void]$lines.Add(([char]0x2022 + " {0} shows what the game profile will change" -f $previewLabel))
				[void]$lines.Add([char]0x2022 + ' Undo reverses your last changes')
				[void]$lines.Add([char]0x2022 + ' Restore to Defaults resets supported settings')
				[void]$lines.Add('')
				[void]$lines.Add('Start Guide:')
				[void]$lines.Add(("1. Review the active {0} game profile" -f $gameModeProfile))
				[void]$lines.Add(("2. {0}" -f $previewLabel))
				[void]$lines.Add(("3. {0}" -f $runLabel))
			}

			return ($lines -join [Environment]::NewLine)
		}

		if ($onboardingMode -eq 'Expert')
		{
			[void]$lines.Add('Expert Mode unlocks all presets, including advanced and high-risk tweaks.')
			[void]$lines.Add('')
			[void]$lines.Add(([char]0x2022 + ' Advanced is the recommended starting point and loads the broadest selection.'))
			[void]$lines.Add(([char]0x2022 + " {0} shows the full execution plan, including risk, restart, and recovery guidance." -f $previewLabel))
			[void]$lines.Add(([char]0x2022 + ' Undo reverses your last run. Restore to Defaults resets supported settings.'))
			[void]$lines.Add('')
			[void]$lines.Add('Quick Start:')
			[void]$lines.Add('1. Start with Advanced or customize individual tweaks')
			[void]$lines.Add(('2. {0} to inspect the execution plan' -f $previewLabel))
			[void]$lines.Add(('3. {0}' -f $runLabel))
		}
		else
		{
			[void]$lines.Add('Baseline helps you safely optimize Windows settings.')
			[void]$lines.Add('')
			[void]$lines.Add('You can safely explore Baseline before applying changes.')
			[void]$lines.Add('')
			[void]$lines.Add(([char]0x2022 + " {0} shows what will change" -f $previewLabel))
			[void]$lines.Add([char]0x2022 + ' Undo reverses your last changes')
			[void]$lines.Add([char]0x2022 + ' Restore to Defaults resets supported settings')
			[void]$lines.Add('')
			[void]$lines.Add('Start Guide:')
			[void]$lines.Add('1. Choose a preset')
			[void]$lines.Add(('2. {0}' -f $previewLabel))
			[void]$lines.Add(('3. {0}' -f $runLabel))
		}

		return ($lines -join [Environment]::NewLine)
	}

	function Get-UxPresetDisplayName
	{
		param ([string]$PresetName)

		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			switch ($PresetName)
			{
				'Minimal' { return 'Quick Start' }
				'Basic'   { return 'Recommended' }
			}
		}

		return $PresetName
	}

	function Get-UxPresetEmphasisText
	{
		switch (Get-UxOnboardingMode)
		{
			'Safe'
			{
				return "Start here $([char]0x2014) Quick Start is recommended for your first run."
			}
			'Expert'
			{
				return 'Start with Advanced to load the full expert preset, or choose a narrower tier if you want less scope.'
			}
		}

		return 'Use these shortcuts to start from a sensible baseline before fine-tuning individual tweaks.'
	}

	function Get-UxPresetSummaryText
	{
		switch (Get-UxOnboardingMode)
		{
			'Safe'
			{
				return 'Quick Start includes privacy essentials. Recommended adds broader privacy and performance tweaks. More presets are available when you turn off Safe Mode.'
			}
			'Expert'
			{
				return 'Advanced is the expert starting point in Expert Mode and loads the broadest preset selection. Balanced and Basic remain available if you want a narrower scope; review Advanced carefully before running.'
			}
		}

		return 'Minimal is the safest start. Basic is the recommended default. Balanced widens the selection. Advanced is the expert preset and should be reviewed carefully.'
	}

	function Get-UxConfirmationMessage
	{
		param (
			[object]$Summary,
			[bool]$IsGameModeRun,
			[int]$AdvancedTierCount
		)

		$messageParts = @()
		$previewLabel = Get-UxPreviewButtonLabel

		# Prepend run-path context so the user knows which path they are on.
		$runPathContext = Get-UxRunPathContext
		$runPathIntro = Get-UxRunPathConfirmationMessage -RunPathContext $runPathContext
		if (-not [string]::IsNullOrWhiteSpace($runPathIntro) -and -not $IsGameModeRun)
		{
			$messageParts += $runPathIntro
		}

		if ($IsGameModeRun)
		{
			$messageParts += "Game Mode is preparing the $($Script:GameModeProfile) profile."
			if (Test-IsSafeModeUX)
			{
				$messageParts += 'Review the grouped gaming actions before you continue. Restore point recommended if this is your first time.'
			}
			else
			{
				$messageParts += 'Review the grouped gaming actions, restart notes, recovery guidance, and reversible-here coverage before you continue.'
			}
		}
		elseif ($Summary.RiskLevel -eq 'High')
		{
			if (Test-IsSafeModeUX)
			{
				$messageParts += 'This selection includes changes that may affect how some apps or features work.'
				$messageParts += ("A restore point will be created automatically. You can also use {0} to see exactly what will happen." -f $previewLabel)
			}
			else
			{
				$messageParts += 'This selection includes high-risk or manual recovery changes.'
				$messageParts += 'They may remove Windows features, affect update, network, gaming, or compatibility behavior, and be difficult to undo.'
			}
		}
		else
		{
			if (Test-IsSafeModeUX)
			{
				$messageParts += 'This selection includes some changes that may affect app compatibility.'
				$messageParts += ("Use {0} to see exactly what will change." -f $previewLabel)
			}
			else
			{
				$messageParts += 'This selection includes moderate-risk changes.'
				$messageParts += 'They may affect compatibility, workflow behavior, or system defaults.'
			}
		}

		if ($AdvancedTierCount -gt 0)
		{
			if (Test-IsExpertModeUX)
			{
				$messageParts += "$AdvancedTierCount Advanced-tier change$(if ($AdvancedTierCount -eq 1) { '' } else { 's' }) included."
			}
			else
			{
				$messageParts += 'This selection includes Advanced-tier changes.'
				$messageParts += 'Advanced is the expert preset and is intended for experienced users who are comfortable with the tradeoffs.'
			}
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Summary.RestoreRecommendation))
		{
			$messageParts += $Summary.RestoreRecommendation
		}

		if (-not (Test-IsSafeModeUX))
		{
			if ($Summary.RestorePointRecoveryCount -gt 0)
			{
				$messageParts += "$($Summary.RestorePointRecoveryCount) selected item$(if ($Summary.RestorePointRecoveryCount -eq 1) { '' } else { 's' }) - restore point recommended."
			}
			if ($Summary.ManualRecoveryCount -gt 0)
			{
				$messageParts += "$($Summary.ManualRecoveryCount) selected item$(if ($Summary.ManualRecoveryCount -eq 1) { '' } else { 's' }) require manual recovery if something goes wrong."
			}
		}

		if ($Summary.Categories.Count -gt 0 -and -not (Test-IsSafeModeUX))
		{
			$messageParts += "Categories touched: $($Summary.CategoryText)."
		}

		if (Test-IsSafeModeUX)
		{
			$messageParts += ("Tip: {0} lets you see every action before anything is applied." -f $previewLabel)
		}
		else
		{
			$messageParts += ("{0} lets you review the exact actions before they apply." -f $previewLabel)
		}

		return $messageParts
	}

	function Get-UxHumanReadableSummary
	{
		param ([object[]]$Results)

		$lines = [System.Collections.Generic.List[string]]::new()
		foreach ($result in @($Results))
		{
			if ([string]$result.Status -notin @('Success', 'Restart pending')) { continue }
			$name = [string]$result.Name
			if ([string]::IsNullOrWhiteSpace($name)) { continue }

			$line = switch ([string]$result.Type)
			{
				'Toggle'
				{
					$selection = [string]$result.Selection
					$isEnabled = ($selection -match '(?i)^(Enable|On|Yes|Activate)$')
					if ($isEnabled) { "Enabled $name" } else { "Disabled $name" }
				}
				'Action'
				{
					"Ran $name"
				}
				'Choice'
				{
					$selection = if ((Test-GuiObjectField -Object $result -FieldName 'Selection')) { [string]$result.Selection } else { '' }
					if (-not [string]::IsNullOrWhiteSpace($selection)) { "Set $name to $selection" } else { "Applied $name" }
				}
				default
				{
					"Applied $name"
				}
			}
			if (-not [string]::IsNullOrWhiteSpace($line))
			{
				[void]$lines.Add([string][char]0x2022 + " $line")
			}
		}

		if ($lines.Count -eq 0) { return $null }
		return ($lines -join [Environment]::NewLine)
	}

	function Get-UxPreviewSummaryParts
	{
		param (
			[object]$Summary,
			[bool]$IsGameModePreview,
			[int]$AlreadyDesiredCount,
			[int]$WillChangeCount,
			[int]$RequiresRestartCount,
			[int]$NotFullyRestorablePreviewCount,
			[int]$AdvancedTierCount,
			[object[]]$SelectedTweaks = @()
		)

		$noun = if ($IsGameModePreview) { 'gaming action' } else { 'tweak' }
		$nounPlural = if ($IsGameModePreview) { 'gaming actions' } else { 'tweaks' }
		$itemWord = if ($Summary.SelectedCount -eq 1) { $noun } else { $nounPlural }

		$summaryParts = @(
			$(if ($IsGameModePreview) {
				"This Game Mode preview lists the $($Summary.SelectedCount) selected $itemWord for the $($Script:GameModeProfile) profile."
			}
			else {
				"This preview lists the $($Summary.SelectedCount) selected $itemWord."
			}),
			'No changes were applied.'
		)

		if (Test-IsSafeModeUX)
		{
			# Safe Mode: simplified summary with only the most important numbers
			if ($WillChangeCount -gt 0)
			{
				$summaryParts += "$WillChangeCount $(if ($WillChangeCount -eq 1) { $noun } else { $nounPlural }) will change when you run $(if ($WillChangeCount -eq 1) { 'it' } else { 'them' })."
			}
			if ($AlreadyDesiredCount -gt 0)
			{
				$summaryParts += "$AlreadyDesiredCount already set - no action needed."
			}
			if ($Summary.HighRiskCount -gt 0)
			{
				$summaryParts += "$($Summary.HighRiskCount) high-risk change$(if ($Summary.HighRiskCount -eq 1) { '' } else { 's' }) - restore point recommended."
			}
			if ($RequiresRestartCount -gt 0)
			{
				$summaryParts += "Restart required after running."
			}
			if ($Summary.ShouldRecommendRestorePoint -and -not [string]::IsNullOrWhiteSpace([string]$Summary.RestoreRecommendation))
			{
				$summaryParts += [string]$Summary.RestoreRecommendation
			}
		}
		elseif (Test-IsExpertModeUX)
		{
			# Expert Mode: full detail — always show all metrics for completeness
			if ($AlreadyDesiredCount -gt 0)
			{
				$summaryParts += "$AlreadyDesiredCount $(if ($AlreadyDesiredCount -eq 1) { $noun } else { $nounPlural }) already set."
			}
			if ($WillChangeCount -gt 0)
			{
				$summaryParts += "$WillChangeCount $(if ($WillChangeCount -eq 1) { $noun } else { $nounPlural }) will change when you run $(if ($WillChangeCount -eq 1) { 'it' } else { 'them' })."
			}
			if ($AdvancedTierCount -gt 0)
			{
				$summaryParts += $(if ($AdvancedTierCount -eq 1) { "1 Advanced-tier $noun is included for experienced users." } else { "$AdvancedTierCount Advanced-tier $nounPlural are included for experienced users." })
			}
			if ($Summary.HighRiskCount -gt 0)
			{
				$summaryParts += "$($Summary.HighRiskCount) high-risk $(if ($Summary.HighRiskCount -eq 1) { $noun } else { $nounPlural }) selected."
			}
			if ($Summary.MediumRiskCount -gt 0)
			{
				$summaryParts += "$($Summary.MediumRiskCount) medium-risk $(if ($Summary.MediumRiskCount -eq 1) { $noun } else { $nounPlural }) selected."
			}
			if ($RequiresRestartCount -gt 0)
			{
				$summaryParts += "$RequiresRestartCount $(if ($RequiresRestartCount -eq 1) { $noun } else { $nounPlural }) - restart required after running."
			}
			if ($NotFullyRestorablePreviewCount -gt 0)
			{
				$summaryParts += "$NotFullyRestorablePreviewCount $(if ($NotFullyRestorablePreviewCount -eq 1) { $noun } else { $nounPlural }) require manual recovery."
			}
			if ($Summary.DirectUndoEligibleCount -gt 0)
			{
				$summaryParts += "$($Summary.DirectUndoEligibleCount) $(if ($Summary.DirectUndoEligibleCount -eq 1) { $noun } else { $nounPlural }) reversible here in Baseline."
			}
			if ($Summary.ShouldRecommendRestorePoint -and -not [string]::IsNullOrWhiteSpace([string]$Summary.RestoreRecommendation))
			{
				$summaryParts += [string]$Summary.RestoreRecommendation
			}
			if ($Summary.Categories.Count -gt 0)
			{
				$summaryParts += "Categories touched: $($Summary.CategoryText)."
			}
		}
		else
		{
			# Standard Mode: moderate detail — show nonzero metrics, skip zero-value recovery noise
			if ($AlreadyDesiredCount -gt 0)
			{
				$summaryParts += "$AlreadyDesiredCount $(if ($AlreadyDesiredCount -eq 1) { $noun } else { $nounPlural }) already set."
			}
			if ($WillChangeCount -gt 0)
			{
				$summaryParts += "$WillChangeCount $(if ($WillChangeCount -eq 1) { $noun } else { $nounPlural }) will change when you run $(if ($WillChangeCount -eq 1) { 'it' } else { 'them' })."
			}
			if ($Summary.HighRiskCount -gt 0)
			{
				$summaryParts += "$($Summary.HighRiskCount) high-risk $(if ($Summary.HighRiskCount -eq 1) { $noun } else { $nounPlural }) selected."
			}
			if ($AdvancedTierCount -gt 0)
			{
				$summaryParts += $(if ($AdvancedTierCount -eq 1) { "1 Advanced-tier $noun is included for experienced users." } else { "$AdvancedTierCount Advanced-tier $nounPlural are included for experienced users." })
			}
			if ($Summary.MediumRiskCount -gt 0)
			{
				$summaryParts += "$($Summary.MediumRiskCount) medium-risk $(if ($Summary.MediumRiskCount -eq 1) { $noun } else { $nounPlural }) selected."
			}
			if ($RequiresRestartCount -gt 0)
			{
				$summaryParts += "$RequiresRestartCount $(if ($RequiresRestartCount -eq 1) { $noun } else { $nounPlural }) - restart required after running."
			}
			if ($NotFullyRestorablePreviewCount -gt 0)
			{
				$summaryParts += "$NotFullyRestorablePreviewCount $(if ($NotFullyRestorablePreviewCount -eq 1) { $noun } else { $nounPlural }) require manual recovery."
			}
			if ($Summary.ShouldRecommendRestorePoint -and -not [string]::IsNullOrWhiteSpace([string]$Summary.RestoreRecommendation))
			{
				$summaryParts += [string]$Summary.RestoreRecommendation
			}
		}

		# Append restart-required tweak names when tweaks are provided
		if ($RequiresRestartCount -gt 0 -and @($SelectedTweaks).Count -gt 0)
		{
			$restartTweakNames = @($SelectedTweaks | Where-Object {
				(Test-GuiObjectField -Object $_ -FieldName 'RequiresRestart') -and [bool]$_.RequiresRestart
			} | ForEach-Object {
				$tweakName = if ((Test-GuiObjectField -Object $_ -FieldName 'Name') -and -not [string]::IsNullOrWhiteSpace([string]$_.Name)) { [string]$_.Name } else { $null }
				if ($tweakName) { $tweakName }
			})
			if ($restartTweakNames.Count -gt 0)
			{
				$restartSection = "These changes take effect after restart ($($restartTweakNames.Count) tweaks):"
				foreach ($rName in $restartTweakNames)
				{
					$restartSection += "`n" + [char]0x2022 + " $rName"
				}
				$summaryParts += $restartSection
			}
		}

		return $summaryParts
	}

	function Get-UxPreviewSummaryCards
	{
		# Safe Mode: compact set with friendly labels.
		# Standard Mode: core cards + conditional extras (hide zero-value recovery noise).
		# Expert Mode: full card set — always show all metrics for completeness.
		param (
			[object]$Summary,
			[int]$AlreadyDesiredCount,
			[int]$WillChangeCount,
			[int]$HighRiskPreviewCount,
			[int]$RequiresRestartCount,
			[int]$NotFullyRestorablePreviewCount,
			[int]$AdvancedTierCount
		)

		if (Test-IsSafeModeUX)
		{
			$cards = @(
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusSelected' -Fallback 'Selected')
					Value = $Summary.SelectedCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailTweaksInPreview' -Fallback 'Tweaks in this preview')
					Tone = 'Primary'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusWillChange' -Fallback 'Will change')
					Value = $WillChangeCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailActionsWillApply' -Fallback 'Actions that will apply')
					Tone = 'Success'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusAlreadySet' -Fallback 'Already set')
					Value = $AlreadyDesiredCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailNoActionNeeded' -Fallback 'No action needed')
					Tone = 'Muted'
				}
			)
			if ($HighRiskPreviewCount -gt 0)
			{
				$cards += [pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusHighRisk' -Fallback 'High risk')
					Value = $HighRiskPreviewCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailMayBeDifficultUndo' -Fallback 'May be difficult to undo')
					Tone = 'Danger'
				}
			}
			if ($RequiresRestartCount -gt 0)
			{
				$cards += [pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestart' -Fallback 'Restart')
					Value = $RequiresRestartCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailMayNeedReboot' -Fallback 'May need a reboot')
					Tone = 'Caution'
				}
			}
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestorePoint' -Fallback 'Restore point')
				Value = $(if ($Summary.ShouldRecommendRestorePoint) { (Get-UxLocalizedString -Key 'GuiPreviewYes' -Fallback 'Yes') } else { (Get-UxLocalizedString -Key 'GuiPreviewNo' -Fallback 'No') })
				Detail = $(if ($Summary.ShouldRecommendRestorePoint) { [string]$Summary.RestoreRecommendation } else { (Get-UxLocalizedString -Key 'GuiPreviewDetailRestoreNotNeeded' -Fallback 'Not needed for this selection.') })
				Tone = $(if ($Summary.ShouldRecommendRestorePoint) { if ($Summary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
			}
			return @($cards)
		}

		if (Test-IsExpertModeUX)
		{
			# Expert Mode: full card set — always show all metrics for completeness
			$cards = @(
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusSelected' -Fallback 'Selected')
					Value = $Summary.SelectedCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailTweaksInPreview' -Fallback 'Tweaks in this preview')
					Tone = 'Primary'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusAlreadySet' -Fallback 'Already set')
					Value = $AlreadyDesiredCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailNoOpSelections' -Fallback 'No-op selections')
					Tone = 'Muted'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusWillChange' -Fallback 'Will change')
					Value = $WillChangeCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailActionsWillApply' -Fallback 'Actions that will apply')
					Tone = 'Success'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusHighRisk' -Fallback 'High risk')
					Value = $HighRiskPreviewCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailMayBeDifficultUndo' -Fallback 'May be difficult to undo')
					Tone = 'Danger'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestartRequired' -Fallback 'Restart required')
					Value = $RequiresRestartCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailNeedsReboot' -Fallback 'Needs a reboot')
					Tone = 'Caution'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusReversibleHere' -Fallback 'Reversible here')
					Value = $Summary.DirectUndoEligibleCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailRolledBackInApp' -Fallback 'Can be rolled back in-app')
					Tone = 'Success'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusManualRecovery' -Fallback 'Manual recovery')
					Value = $NotFullyRestorablePreviewCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailOneWayOrPartialRollback' -Fallback 'One-way or partial rollback')
					Tone = 'Danger'
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestorePoint' -Fallback 'Restore point')
					Value = $(if ($Summary.ShouldRecommendRestorePoint) { (Get-UxLocalizedString -Key 'GuiPreviewYes' -Fallback 'Yes') } else { (Get-UxLocalizedString -Key 'GuiPreviewNo' -Fallback 'No') })
					Detail = $(if ($Summary.ShouldRecommendRestorePoint) { [string]$Summary.RestoreRecommendation } else { (Get-UxLocalizedString -Key 'GuiPreviewDetailRestoreNotRecommended' -Fallback 'Not recommended for this selection.') })
					Tone = $(if ($Summary.ShouldRecommendRestorePoint) { if ($Summary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
				}
				[pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusCategories' -Fallback 'Categories')
					Value = $Summary.Categories.Count
					Detail = $Summary.CategoryText
					Tone = 'Muted'
				}
			)
			if ($AdvancedTierCount -gt 0)
			{
				$cards += [pscustomobject]@{
					Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusAdvancedTier' -Fallback 'Advanced tier')
					Value = $AdvancedTierCount
					Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailExpertOnlyChanges' -Fallback 'Expert-only changes')
					Tone = 'Danger'
				}
			}
			return @($cards)
		}

		# Standard Mode: core cards + conditional extras — suppress zero-value recovery noise
		$cards = @(
			[pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusSelected' -Fallback 'Selected')
				Value = $Summary.SelectedCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailTweaksInPreview' -Fallback 'Tweaks in this preview')
				Tone = 'Primary'
			}
			[pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusAlreadySet' -Fallback 'Already set')
				Value = $AlreadyDesiredCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailNoOpSelections' -Fallback 'No-op selections')
				Tone = 'Muted'
			}
			[pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusWillChange' -Fallback 'Will change')
				Value = $WillChangeCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailActionsWillApply' -Fallback 'Actions that will apply')
				Tone = 'Success'
			}
		)
		if ($HighRiskPreviewCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusHighRisk' -Fallback 'High risk')
				Value = $HighRiskPreviewCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailMayBeDifficultUndo' -Fallback 'May be difficult to undo')
				Tone = 'Danger'
			}
		}
		if ($RequiresRestartCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestartRequired' -Fallback 'Restart required')
				Value = $RequiresRestartCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailNeedsReboot' -Fallback 'Needs a reboot')
				Tone = 'Caution'
			}
		}
		if ($Summary.DirectUndoEligibleCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusReversibleHere' -Fallback 'Reversible here')
				Value = $Summary.DirectUndoEligibleCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailRolledBackInApp' -Fallback 'Can be rolled back in-app')
				Tone = 'Success'
			}
		}
		if ($NotFullyRestorablePreviewCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusManualRecovery' -Fallback 'Manual recovery')
				Value = $NotFullyRestorablePreviewCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailOneWayOrPartialRollback' -Fallback 'One-way or partial rollback')
				Tone = 'Danger'
			}
		}
		$cards += [pscustomobject]@{
			Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusRestorePoint' -Fallback 'Restore point')
			Value = $(if ($Summary.ShouldRecommendRestorePoint) { (Get-UxLocalizedString -Key 'GuiPreviewYes' -Fallback 'Yes') } else { (Get-UxLocalizedString -Key 'GuiPreviewNo' -Fallback 'No') })
			Detail = $(if ($Summary.ShouldRecommendRestorePoint) { [string]$Summary.RestoreRecommendation } else { (Get-UxLocalizedString -Key 'GuiPreviewDetailRestoreNotRecommended' -Fallback 'Not recommended for this selection.') })
			Tone = $(if ($Summary.ShouldRecommendRestorePoint) { if ($Summary.RestoreRecommendationSeverity -eq 'StronglyRecommended') { 'Danger' } else { 'Caution' } } else { 'Muted' })
		}
		if ($AdvancedTierCount -gt 0)
		{
			$cards += [pscustomobject]@{
				Label = (Get-UxLocalizedString -Key 'GuiPreviewStatusAdvancedTier' -Fallback 'Advanced tier')
				Value = $AdvancedTierCount
				Detail = (Get-UxLocalizedString -Key 'GuiPreviewDetailExpertOnlyChanges' -Fallback 'Expert-only changes')
				Tone = 'Danger'
			}
		}
		return @($cards)
	}

	function Get-UxRestoreDefaultsConfirmation
	{
		if (Test-IsSafeModeUX)
		{
			return [pscustomobject]@{
				Title   = 'Restore to Windows Defaults'
				Message = "This will undo supported tweaks and return them to their original Windows settings.`n`nSome changes (like removed apps or one-way security settings) require manual recovery.`n`nWould you like to continue?"
				Buttons = @('Cancel', 'Restore Defaults')
				DestructiveButton = 'Restore Defaults'
			}
		}
		if (Test-IsExpertModeUX)
		{
			return [pscustomobject]@{
				Title   = 'Restore to Windows Defaults'
				Message = "Reset tweaks to Windows default values where supported.`n`nOS Hardening, permanent removals, and manual recovery actions will be skipped."
				Buttons = @('Cancel', 'Restore Defaults')
				DestructiveButton = 'Restore Defaults'
			}
		}
		return [pscustomobject]@{
			Title   = 'Restore to Windows Defaults'
			Message = "This will reset tweaks to their Windows default values where possible.`n`nNote: OS Hardening tweaks and other permanent changes cannot be reversed and will be skipped.`n`nAre you sure you want to continue?"
			Buttons = @('Cancel', 'Restore Defaults')
			DestructiveButton = 'Restore Defaults'
		}
	}

	function Get-UxPostRunNextStepsText
	{
		# Safe Mode only - returns $null for non-Safe views to fall through to the existing builder.
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[object]$SummaryPayload,
			[object]$Insights
		)

		if (-not (Test-IsSafeModeUX))
		{
			# Non-Safe views: delegate to the existing full-detail builder
			return $null
		}

		# Safe Mode: simplified next-steps
		$isRestore = ($Mode -eq 'Defaults')
		$steps = New-Object System.Collections.Generic.List[string]

		if ($SummaryPayload.RestartPendingCount -gt 0)
		{
			[void]$steps.Add($(if ($isRestore) { 'Restart required to finish restoring some items.' } else { 'Restart required to finish applying some changes.' }))
		}
		if ($Insights.RecoverableFailedCount -gt 0)
		{
			[void]$steps.Add("$($Insights.RecoverableFailedCount) item$(if ($Insights.RecoverableFailedCount -eq 1) { '' } else { 's' }) can be retried after following the suggested fix.")
		}
		if ($Insights.ManualFailedCount -gt 0)
		{
			[void]$steps.Add($(if ($isRestore) {
				"$($Insights.ManualFailedCount) item$(if ($Insights.ManualFailedCount -eq 1) { '' } else { 's' }) require manual recovery - open the log for details."
			} else {
				"$($Insights.ManualFailedCount) item$(if ($Insights.ManualFailedCount -eq 1) { '' } else { 's' }) require manual recovery - open the log for details."
			}))
		}
		if ($Insights.PackageFailedCount -gt 0)
		{
			$pkgText = if ($isRestore) {
				'Some apps may need to be reinstalled from the Microsoft Store.'
			} else {
				'Some app changes may need follow-up through the Microsoft Store.'
			}
			[void]$steps.Add($pkgText)
		}
		if ($Insights.NeedsLogReview)
		{
			[void]$steps.Add('Open the log if you want to see exactly what happened.')
		}

		$result = ($steps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
		if ([string]::IsNullOrWhiteSpace($result))
		{
			$result = if ($isRestore) { 'Defaults restore completed.' } else { 'Run completed successfully.' }
		}
		return $result
	}

	function Get-UxPostRunCountsText
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[object]$SummaryPayload,
			[object]$Insights
		)

		if (-not (Test-IsSafeModeUX))
		{
			return $null
		}

		$isRestore = ($Mode -eq 'Defaults')
		$parts = @()
		$appliedLabel = if ($isRestore) { 'Restored' } else { 'Applied' }
		$parts += "${appliedLabel}: $($SummaryPayload.AppliedCount)"
		if ($SummaryPayload.RestartPendingCount -gt 0) { $parts += "Restart required: $($SummaryPayload.RestartPendingCount)" }
		if ($Insights.AlreadyDesiredCount -gt 0) { $parts += "Already set: $($Insights.AlreadyDesiredCount)" }
		if ($Insights.NeedsAttentionCount -gt 0) { $parts += "Needs attention: $($Insights.NeedsAttentionCount)" }
		return (($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '. ') + '.'
	}

	function Get-UxHelpSections
	{
		$recommendedPreset = Get-UxRecommendedPresetName
		$applyLabel = Get-UxRunActionLabel
		$previewLabel = Get-UxPreviewButtonLabel
		$undoSelectionLabel = Get-UxUndoSelectionActionLabel
		$quickStartSteps = @(Get-UxQuickStartSteps)
		$undoAndRestoreLines = @(Get-UxUndoAndRestoreLines)
		$importExportLines = @(Get-UxImportExportLines)

		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			$isGameModeActive = [bool]$Script:GameMode
			$gameModeProfile = if ([string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { 'Gaming' } else { [string]$Script:GameModeProfile }

			$sections = [ordered]@{
				'Welcome - First Steps' = @(
					'You are running in Safe Mode, which hides advanced and risky tweaks so you can explore conservatively.'
					("$recommendedPreset is the recommended preset for most users and keeps the first run conservative.")
					("Use {0} to see exactly what will happen before anything is applied." -f $previewLabel)
					("$undoSelectionLabel lets you reverse the last preset or imported selection change if you change your mind.")
				)
				'Start Guide' = $quickStartSteps
				'Presets' = @(
					'Minimal is the recommended preset for most users and is the easiest place to begin.'
					'Basic adds a broader low-risk mix of cleanup, privacy, and usability changes after you review Minimal.'
					'Balanced and Advanced are for experienced users and become visible when Safe Mode is turned off.'
					'Clicking a preset replaces any previously loaded selection.'
					'Presets only update the GUI selection. They do not execute changes.'
				)
				$previewLabel = @(
					("{0} shows what would happen without applying any changes." -f $previewLabel)
					'Use it to check your selection before committing.'
				)
				'Apply Tweaks' = @(
					("$applyLabel applies the current GUI selection to your system.")
					'Expected results per tweak: Success, Failed, Skipped, Already Applied.'
					'Restart if prompted after the run completes.'
				)
				'Risk Levels' = @(
					'Low Risk: safe usability and quality-of-life changes.'
					'Medium Risk: may affect behavior or compatibility.'
					'High Risk: may be difficult to reverse - hidden while Safe Mode is on.'
				)
				'Undo and Restore' = $undoAndRestoreLines
				'Import / Export' = $importExportLines
				'Safe Mode' = @(
					'Safe Mode hides dangerous, hard-to-reverse, and removal-style tweaks.'
					'It is enabled by default on a fresh launch.'
					'Turning Safe Mode on clears any selections that would otherwise be hidden.'
				)
				'Expert Mode' = @(
					'Expert Mode reveals all tweaks including high-risk and advanced changes.'
					'Use it only if you understand the impact of each setting.'
					'Turning Expert Mode on disables Safe Mode.'
				)
			}

			if ($isGameModeActive)
			{
				$sections['Game Mode'] = @(
					("Game Mode is active and using the {0} profile." -f $gameModeProfile)
					'While Game Mode is active, only the Gaming tab plan can be edited or run.'
					'Choose a gaming profile to build a focused plan, then use Preview Run to inspect it.'
					'Turn off Game Mode to return to preset-based workflows.'
				)
			}

			$sections['Logs and Troubleshooting'] = @(
				'Open Log shows the session log for troubleshooting.'
				'If something fails, the log and execution summary have details.'
			)

			return $sections
		}

		if (Test-IsExpertModeUX)
		{
			$isGameModeActive = [bool]$Script:GameMode
			$gameModeProfile = if ([string]::IsNullOrWhiteSpace([string]$Script:GameModeProfile)) { 'Gaming' } else { [string]$Script:GameModeProfile }

			if ($isGameModeActive)
			{
				return (Get-UxExpertGameModeHelpSections -ProfileName $gameModeProfile -PreviewLabel $previewLabel -ApplyLabel $applyLabel)
			}

			$sections = [ordered]@{
				'Getting Started' = @(
					'All tweaks unselected on launch. Use presets or manual selection.'
					'Expert Mode: all tiers and risk levels are visible.'
					'Advanced is the recommended starting point when you want the broadest preset selection.'
				)
				'Presets' = @(
					'Minimal, Basic, Balanced, Advanced load from preset files.'
					'Advanced is the expert preset and should be reviewed with risk, restart, and recovery guidance in mind.'
					'Presets replace the current selection - they do not stack.'
					'Run Tweaks applies the current GUI selection.'
				)
				$previewLabel = @(
					("{0} shows the execution plan for the current selection, including risk, restart required, restore, and category metadata." -f $previewLabel)
				)
				'Run Tweaks' = @(
					'Executes selected items. Outcome states: Success, Failed, Skipped, Already Applied.'
				)
				'Risk Levels' = @(
					'Low: safe QoL changes. Medium: behavioral/compatibility impact. High: hard to reverse.'
					'Restart required: needs reboot to take full effect.'
				)
				'Restore to Windows Defaults' = @(
					'Resets supported defaults. Manual recovery items and OS Hardening items are skipped.'
					'Reversible here (post-run) is a separate recovery path.'
				)
				'Modes' = @(
					'Safe Mode: conservative filter - hides high-risk, removal, and manual recovery tweaks.'
					'Expert Mode: full visibility - all tweaks and metadata exposed.'
					'Safe and Expert are mutually exclusive visibility switches.'
				)
			}

			$sections['System Scan'] = @(
				'Refreshes current system state for supported tweaks.'
			)
			$sections['Import / Export / Session Restore'] = @(
				'Export/Import saves and restores GUI selections.'
				'Restore Snapshot restores last captured GUI state (no execution).'
				'Rollback Profile exports reversible-here undo commands only.'
			)
			$sections['Logs'] = @(
				'Open Log shows session output. Unmatched preset lines and failures are logged.'
			)

			return $sections
		}

		return [ordered]@{
			'Getting Started' = @(
				'The GUI opens with all tweaks unselected.'
				'Select tweaks manually or click a preset button to populate the current selection.'
				'Preset buttons do not run anything by themselves.'
			)
			'Presets' = @(
				'Minimal, Basic, Balanced, and Advanced load selections from their matching preset files.'
				'Basic is the recommended default for normal users.'
				'Balanced is for enthusiasts who understand moderate tradeoffs.'
				'Advanced is the expert preset for experienced users and recommends a restore point before continuing.'
				'Clicking a preset replaces any previously loaded selection - selections do not stack.'
				'Presets only update the GUI selection. They do not execute changes.'
				'Run Tweaks applies the current GUI selection.'
			)
			$previewLabel = @(
				("{0} shows what would execute from the current selection without applying any changes." -f $previewLabel)
				'It also shows risk, restart, restore, and category summary information.'
			)
			'Run Tweaks' = @(
				'Run Tweaks executes only the items currently selected in the GUI.'
				'Expected result states per tweak: Success, Failed, Skipped, Already Applied.'
			)
			'Risk Levels' = @(
				'Low Risk: generally safe usability and quality-of-life changes.'
				'Medium Risk: may affect behavior, compatibility, networking, or security posture.'
				'High Risk: may reduce compatibility, disable features, or be difficult to reverse.'
				'Restart required badge: the tweak requires a system restart to take full effect.'
			)
			'Restore to Windows Defaults' = @(
				'Restores supported default values only.'
				'Does not guarantee that every previous change can be undone.'
				'Some destructive or one-way actions require manual recovery.'
				'Reversible here, when available after a run, is a separate recovery path from restoring Windows defaults.'
			)
			'Safe Mode' = @(
				'Safe Mode hides dangerous, hard-to-reverse, and removal-style tweaks.'
				'It is the conservative visibility switch for people who want the safest view of the GUI.'
				'Safe Mode is enabled by default on a fresh launch.'
				'Turning Safe Mode on clears selections that would otherwise be hidden.'
			)
			'Expert Mode' = @(
				'Expert Mode reveals high-risk and advanced tweaks hidden by default.'
				'Use it only if you understand the impact of the settings being changed.'
				'Turning Expert Mode off clears hidden advanced selections from the current view.'
				'Safe Mode is the opposite visibility switch and keeps dangerous tweaks hidden instead.'
			)
			'System Scan' = @(
				'System Scan checks the current system state and refreshes supported tweak states in the GUI.'
			)
			'Import / Export / Session Restore' = @(
				'Export Settings saves the current GUI selection to a file.'
				'Import Settings restores a saved selection into the GUI for review before execution.'
				'Restore Snapshot restores the last captured GUI state only. It does not execute tweaks.'
				'Export Rollback Profile, when offered after a run, saves reversible-here undo commands only and is separate from Restore Snapshot or restoring Windows defaults.'
			)
			'Logs and Troubleshooting' = @(
				'Open Log opens the current session log for troubleshooting.'
				'If a preset line cannot be matched to a tweak it will be reported in the log.'
				'If a tweak fails, review the log and the execution summary for details.'
			)
		}
	}

	function Test-UxShouldSkipLowRiskConfirmation
	{
		# Expert Mode only: skip the full confirmation for medium-risk runs unless
		# high-risk items, restore-point recommendations, or Advanced-tier changes are present.
		param (
			[object]$Summary,
			[int]$AdvancedTierCount = 0
		)

		if (-not (Test-IsExpertModeUX)) { return $false }

		# Expert mode skips medium-risk confirmation dialog only
		if ($Summary.RiskLevel -eq 'High') { return $false }
		if ($Summary.ShouldRecommendRestorePoint) { return $false }
		if ($AdvancedTierCount -gt 0) { return $false }
		return $true
	}
