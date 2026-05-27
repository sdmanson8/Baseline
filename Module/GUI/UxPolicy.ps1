# Mode presentation helpers - Safe Mode gets beginner-focused wording while
# the existing full-detail views keep the original wording.
# The execution engine is the same in all views; these only change what the user sees.
#
# Centralized here because Safe Mode / Expert Mode branching was originally scattered across
# five different dialog and summary functions, and the wording kept diverging between them.
# Not a full policy framework - just the branches that were actually painful to keep consistent.

	<#
	    .SYNOPSIS
	#>
function Test-IsDesignModeUX
{
	return ([bool]$Script:DesignMode)
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

	<#
	    .SYNOPSIS
	#>

function Get-UxLocalizedString
{
	param (
			[Parameter(Mandatory = $true)]
			[string]$Key,

			[Parameter(Mandatory = $true)]
			[AllowEmptyString()]
			[string]$Fallback,

			[object[]]$FormatArgs = @()
		)

		# GUI callers pass Fallback as the required display text. Use it whenever
		# the active locale does not provide a non-empty value so controls never
		# receive blank labels from incomplete translation packs.
		$localizationSource = $Global:Localization
		$cacheVariable = Get-Variable -Name 'UxLocalizedStringTemplateCache' -Scope Script -ErrorAction SilentlyContinue
		$cacheSourceVariable = Get-Variable -Name 'UxLocalizedStringTemplateCacheSource' -Scope Script -ErrorAction SilentlyContinue
		$cacheSource = if ($cacheSourceVariable) { $cacheSourceVariable.Value } else { $null }
		if (-not $cacheVariable -or -not ($cacheVariable.Value -is [hashtable]) -or -not [object]::ReferenceEquals($cacheSource, $localizationSource))
		{
			$Script:UxLocalizedStringTemplateCache = @{}
			$Script:UxLocalizedStringTemplateCacheSource = $localizationSource
		}

		$cacheKey = [string]::Concat($Key, [char]0, $Fallback)
		if ($Script:UxLocalizedStringTemplateCache.ContainsKey($cacheKey))
		{
			$template = [string]$Script:UxLocalizedStringTemplateCache[$cacheKey]
		}
		else
		{
			$template = $Fallback
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

			$Script:UxLocalizedStringTemplateCache[$cacheKey] = $template
		}

		if ($FormatArgs.Count -gt 0)
		{
			return ($template -f $FormatArgs)
		}

	return $template
}

	<#
	    .SYNOPSIS
	#>

function Get-UxMainWindowTitleText
{
	$osName = 'Windows'
	try
	{
		$osInfo = Get-OSInfo
		if ($osInfo -and -not [string]::IsNullOrWhiteSpace([string]$osInfo.OSName))
		{
			$osName = [string]$osInfo.OSName
		}
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'UxPolicy.GetUxMainWindowTitleText.LoadOSInfo' }

	if (Test-IsDesignModeUX)
	{
		return ('Baseline (Design Mode - not applying changes) | Utility for {0}' -f $osName)
	}

	return (Get-UxLocalizedString -Key 'GuiMainWindowTitleFormat' -Fallback 'Baseline | Utility for {0}' -FormatArgs @($osName))
}

	<#
	    .SYNOPSIS
	#>

	function Get-UxString
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Key,

			[Parameter(Mandatory = $true)]
			[AllowEmptyString()]
			[string]$Fallback,

			[object[]]$FormatArgs = @()
		)

		return (Get-UxLocalizedString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxBilingualLocalizedString
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Key,

			[Parameter(Mandatory = $true)]
			[AllowEmptyString()]
			[string]$Fallback,

			[object[]]$FormatArgs = @(),

			[string]$Separator = ' | '
		)

		return (Get-BaselineBilingualString -Key $Key -Fallback $Fallback -FormatArgs $FormatArgs -Separator $Separator)
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function Get-UxFirstRunPrimaryActionLabel
	{
		if ([bool]$Script:GameMode)
		{
			return (Get-UxLocalizedString -Key 'GuiFirstRunReviewPlan' -Fallback 'Review Plan')
		}

		$recommendedPreset = Get-UxRecommendedPresetName
		return (Get-UxLocalizedString -Key 'GuiFirstRunStartWith' -Fallback 'Start with {0}' -FormatArgs @((Get-UxPresetDisplayName -PresetName $recommendedPreset)))
	}

	function Get-UxPresetLoadedStatusText
	{
		param ([string]$PresetName)

		$presetDisplayName = Get-UxPresetDisplayName -PresetName $PresetName
		$previewLabel = Get-UxPreviewButtonLabel
		return (Get-UxLocalizedString -Key 'GuiPresetLoadedStatus' -Fallback '{0} loaded. Use {1} before applying it.' -FormatArgs @($presetDisplayName, $previewLabel))
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxStartGuideButtonLabel
	{
		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return (Get-UxLocalizedString -Key 'GuiStartGuideQuickStartLabel' -Fallback 'Quick Start')
		}

		return (Get-UxLocalizedString -Key 'GuiStartGuideLabel' -Fallback 'Start Guide')
	}

	function Get-UxHelpButtonLabel
	{
		return (Get-UxLocalizedString -Key 'GuiHelpBtnLabel' -Fallback 'Help')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxOpenHelpActionLabel
	{
		return (Get-UxLocalizedString -Key 'GuiOpenHelpActionLabel' -Fallback 'Open Help')
	}

	function Get-UxPreviewButtonLabel
	{
		return (Get-UxLocalizedString -Key 'GuiBtnPreviewRun' -Fallback 'Preview Run')
	}

	function Get-UxFirstRunDialogTitle
	{
		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return (Get-UxLocalizedString -Key 'GuiFirstRunDialogTitleExpert' -Fallback 'Expert Quick Start')
		}

		return (Get-UxLocalizedString -Key 'GuiFirstRunDialogTitle' -Fallback 'Welcome to Baseline')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxHelpDialogTitle
	{
		return (Get-UxLocalizedString -Key 'GuiHelpDialogTitle' -Fallback 'Help')
	}

	function Get-UxHelpDialogSubtitle
	{
		$subtitle = $null
		if ([bool]$Script:GameMode -and (Get-UxOnboardingMode) -eq 'Expert')
		{
			$subtitle = (Get-UxLocalizedString -Key 'GuiHelpSubtitleGameModeExpert' -Fallback 'Game Mode workflow and execution help')
		}
		else
		{
			switch (Get-UxOnboardingMode)
			{
				'Safe' { $subtitle = (Get-UxLocalizedString -Key 'GuiHelpSubtitleSafe' -Fallback 'Safe Mode guidance and first-run walkthrough') }
				'Expert' { $subtitle = (Get-UxLocalizedString -Key 'GuiHelpSubtitleExpert' -Fallback 'Advanced workflow and execution help') }
				default { $subtitle = (Get-UxLocalizedString -Key 'GuiHelpSubtitle' -Fallback 'Baseline - usage guide') }
			}
		}

		$displayVersion = if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiDisplayVersion))
		{
			[string]$Script:GuiDisplayVersion
		}
		elseif (Get-Command -Name 'Get-BaselineDisplayVersion' -ErrorAction SilentlyContinue)
		{
			try { [string](Get-BaselineDisplayVersion) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UxPolicy.Get-UxHelpDialogSubtitle:catch360' -Severity Debug }
			 $null }
		}
		else
		{
			$null
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$displayVersion))
		{
			return ('{0} - {1}' -f $subtitle, $displayVersion)
		}

		return $subtitle
	}

	<#
	    .SYNOPSIS
	#>

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
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeSection' -Fallback 'Game Mode Workflow') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeActive' -Fallback 'Game Mode is active and using the {0} profile.' -FormatArgs @($ProfileName))
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeVisible' -Fallback 'Expert Mode keeps the full gaming workflow visible, including advanced options and risk metadata.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeOnlyGaming' -Fallback 'While Game Mode is active, only the Gaming tab plan can be edited or run.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeProfilesSection' -Fallback 'Profiles and Plan Building') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeBuildProfile' -Fallback 'Build Profile replaces the current Game Mode plan with a reviewed manifest-backed gaming selection.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeProfileTypes' -Fallback 'Casual, Competitive, Streaming, and Troubleshooting each target a different gaming workflow.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeDecisions' -Fallback 'Decision prompts and optional advanced selections refine the active profile before execution.')
			)
			$PreviewLabel = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModePreview' -Fallback '{0} shows the active Game Mode plan, including risk, restart required, restore, category, and grouped gaming metadata.' -FormatArgs @($PreviewLabel))
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModePreviewUse' -Fallback 'Use it to inspect the exact gaming actions before applying changes.')
			)
			$ApplyLabel = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeApply' -Fallback '{0} executes the active Game Mode plan only.' -FormatArgs @($ApplyLabel))
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeNonGaming' -Fallback 'Non-Gaming tabs stay out of scope until Game Mode is turned off.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeOutcomes' -Fallback 'Outcome states per item: Success, Failed, Skipped, Already Applied.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeRiskSection' -Fallback 'Risk and Recovery') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeRiskMeta' -Fallback 'Risk, restart, direct-undo, and restore-point guidance come from the active plan metadata.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeRestoreDefaultsRecorded' -Fallback 'Restore Defaults resets supported recorded defaults. It is separate from direct undo and rollback export.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeRollbackExport' -Fallback 'Export Rollback Profile, when available after a run, includes only reversible-here undo commands.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeAdvancedSection' -Fallback 'Advanced Options') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeAdvancedAfter' -Fallback 'Advanced Options appear only after a profile is selected and only outside Safe Mode.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeAdvancedOverrides' -Fallback 'They expose reviewed expert-only overrides that are not part of every profile by default.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeAdvancedTroubleshoot' -Fallback 'Troubleshooting-only entries stay labeled so diagnostic changes are easy to spot.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeScanSection' -Fallback 'System Scan and Logs') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeScanAdjust' -Fallback 'System Scan can adjust Game Mode recommendation copy, but it does not change profile defaults automatically.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeLogOpen' -Fallback 'Open Log shows the session output if you need exact failure or recovery details.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeIESection' -Fallback 'Import / Export / Session Restore') = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeIEExport' -Fallback 'Export/Import saves and restores GUI selections for review, including the active Game Mode state.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeIESnapshot' -Fallback 'Restore Snapshot restores the last captured GUI state only. It does not execute changes.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertGameModeIETurnOff' -Fallback 'Turn off Game Mode to return to preset-based workflows.')
			)
		}
	}

	<#
	    .SYNOPSIS
	#>

function Get-UxRunActionLabel
{
	if (Test-IsDesignModeUX)
	{
		return 'Save Config...'
	}

	return (Get-UxLocalizedString -Key 'GuiBtnRun' -Fallback 'Run Tweaks')
}

	function Get-UxPreviewButtonToolTip
	{
		if ([bool]$Script:GameMode)
		{
			switch (Get-UxOnboardingMode)
			{
				'Safe' { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipSafeGame' -Fallback 'Beginner preview for the active Game Mode plan. Review what will run before applying changes.') }
				'Expert' { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipExpertGame' -Fallback 'Expert preview for the active Game Mode plan, including risk, restart, and recovery details.') }
				default { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipDefaultGame' -Fallback 'Preview the active Game Mode plan before running it.') }
			}
		}

		switch (Get-UxOnboardingMode)
		{
			'Safe' { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipSafe' -Fallback 'Beginner preview: shows what will change in plain language before you run tweaks.') }
			'Expert' { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipExpert' -Fallback 'Expert preview: shows full execution plan details, including risk and recovery guidance.') }
			default { return (Get-UxLocalizedString -Key 'GuiPreviewTooltipDefault' -Fallback 'Preview what will run from your current selection without applying changes.') }
		}
	}

	<#
	    .SYNOPSIS
	#>

function Get-UxRunActionToolTip
{
	if (Test-IsDesignModeUX)
	{
		return 'Saves the current GUI selections to a config file without applying changes.'
	}

	if ([bool]$Script:GameMode)
	{
		$previewLabel = Get-UxPreviewButtonLabel
			switch (Get-UxOnboardingMode)
			{
				'Safe' { return (Get-UxLocalizedString -Key 'GuiRunTooltipSafeGame' -Fallback 'Runs the active Game Mode plan with beginner-safe flow. {0} is recommended first.' -FormatArgs @($previewLabel)) }
				'Expert' { return (Get-UxLocalizedString -Key 'GuiRunTooltipExpertGame' -Fallback 'Runs the active Game Mode plan with expert-level scope. {0} is recommended first.' -FormatArgs @($previewLabel)) }
				default { return (Get-UxLocalizedString -Key 'GuiRunTooltipDefaultGame' -Fallback 'Runs the active Game Mode plan only.') }
			}
		}

		switch (Get-UxOnboardingMode)
		{
			'Safe' { return (Get-UxLocalizedString -Key 'GuiRunTooltipSafe' -Fallback 'Applies the selected tweaks using beginner-focused safeguards.') }
			'Expert' { return (Get-UxLocalizedString -Key 'GuiRunTooltipExpert' -Fallback 'Runs the selected tweaks with full expert scope and detailed execution handling.') }
			default { return (Get-UxLocalizedString -Key 'GuiRunTooltipDefault' -Fallback 'Runs the currently selected tweaks.') }
		}
	}

	<#
	    .SYNOPSIS
	#>

function Get-UxRunPathContext
{
	if (Test-IsDesignModeUX)
	{
		return @{ Path = 'DesignMode'; Label = 'Design Mode'; Tone = 'accent' }
	}

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
		return @{ Path = 'Manual'; Label = (Get-UxLocalizedString -Key 'GuiModeCustomSelection' -Fallback 'Mode: Custom Selection'); Tone = 'accent' }
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxRunPathConfirmationMessage
	{
		param ([hashtable]$RunPathContext)
		$previewLabel = Get-UxPreviewButtonLabel

		switch ($RunPathContext.Path)
		{
			'Preset'
			{
				return (Get-UxLocalizedString -Key 'GuiRunPathConfirmPreset' -Fallback 'Apply {0} preset? {1} is recommended first.' -FormatArgs @($RunPathContext.Label, $previewLabel))
			}
			'Troubleshooting'
			{
				return (Get-UxLocalizedString -Key 'GuiRunPathConfirmTroubleshooting' -Fallback 'Run troubleshooting profile? This targets gaming-related settings only.')
			}
			'GameMode'
			{
				return (Get-UxLocalizedString -Key 'GuiRunPathConfirmGameMode' -Fallback 'Apply {0} profile? {1} is recommended first.' -FormatArgs @($RunPathContext.Label, $previewLabel))
			}
			default
			{
				return (Get-UxLocalizedString -Key 'GuiRunPathConfirmCustom' -Fallback 'Apply custom selection? This includes tweaks you selected individually. {0} is strongly recommended.' -FormatArgs @($previewLabel))
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxUndoSelectionActionLabel
	{
		if ((Test-IsSafeModeUX) -or (Test-IsExpertModeUX))
		{
			return (Get-UxLocalizedString -Key 'GuiUndoSelectionChange' -Fallback 'Undo Selection Change')
		}

		return (Get-UxLocalizedString -Key 'GuiRestoreSnapshot' -Fallback 'Restore Snapshot')
	}

	function Get-UxUndoProfileActionLabel
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return (Get-UxLocalizedString -Key 'GuiExportUndoProfile' -Fallback 'Export Undo Profile')
		}

		return (Get-UxLocalizedString -Key 'GuiExportRollbackProfile' -Fallback 'Export Rollback Profile')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxScenarioHeading
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return (Get-UxLocalizedString -Key 'GuiScenarioHeadingSafe' -Fallback 'Optional: Scenario Profiles')
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
				(Get-UxLocalizedString -Key 'GuiQuickStepGameModeActive' -Fallback 'Game Mode is active and using the {0} profile.' -FormatArgs @($gameModeProfile))
				(Get-UxLocalizedString -Key 'GuiQuickStepGameModeReview' -Fallback 'Review the gaming profile and selected gaming tweaks with {0}.' -FormatArgs @($previewLabel))
				(Get-UxLocalizedString -Key 'GuiQuickStepGameModeApply' -Fallback 'Click {0} to apply the gaming plan.' -FormatArgs @((Get-UxRunActionLabel)))
			)
		}

		if ((Get-UxOnboardingMode) -eq 'Expert')
		{
			return @(
				(Get-UxLocalizedString -Key 'GuiQuickStepExpertLoad' -Fallback 'Load Advanced to start from the full expert preset, or customize individual tweaks.')
				(Get-UxLocalizedString -Key 'GuiQuickStepExpertPreview' -Fallback 'Click {0} to inspect risk, restart, and recovery details before applying anything.' -FormatArgs @($previewLabel))
				(Get-UxLocalizedString -Key 'GuiQuickStepExpertApply' -Fallback 'Click {0} to apply the reviewed selection.' -FormatArgs @((Get-UxRunActionLabel)))
			)
		}

		return @(
			(Get-UxLocalizedString -Key 'GuiQuickStepDefaultPreset' -Fallback 'Choose a preset - {0} is recommended for most users.' -FormatArgs @((Get-UxRecommendedPresetName)))
			(Get-UxLocalizedString -Key 'GuiQuickStepDefaultPreview' -Fallback 'Click {0} to see what will change.' -FormatArgs @($previewLabel))
			(Get-UxLocalizedString -Key 'GuiQuickStepDefaultApply' -Fallback 'Click {0} to apply.' -FormatArgs @((Get-UxRunActionLabel)))
	)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxHelpGettingStartedLines
	{
		param (
			[Parameter(Mandatory)]
			[string]$Mode
		)

		switch ($Mode)
		{
			'Safe' {
				return @(
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedSafeMain' -Fallback 'Use Start Guide on the main screen when you want the first-run walkthrough.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedSafePreview' -Fallback 'Use Preview Run before applying anything so you can review the impact first.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedSafeHelp' -Fallback 'Use Help when you want reference material instead of the guided setup flow.')
				)
			}
			'Expert' {
				return @(
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedExpertMain' -Fallback 'Use Start Guide on the main screen if you want the guided setup workflow.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedExpertTabs' -Fallback 'Otherwise jump directly to the tab you need and review the selection there.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedExpertHelp' -Fallback 'Use Help for reference topics, logs, and recovery guidance.')
				)
			}
			default {
				return @(
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedStdMain' -Fallback 'Use Start Guide on the main screen for the guided onboarding flow.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedStdPreview' -Fallback 'Preview Run lets you review what will change before you apply it.')
					(Get-UxLocalizedString -Key 'GuiHelpGettingStartedStdHelp' -Fallback 'Use Help later when you need to rediscover the available workflows.')
				)
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxUndoAndRestoreLines
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return @(
				(Get-UxLocalizedString -Key 'GuiUndoRestoreSafeUndo' -Fallback '{0} restores the last preset or imported selection change in the GUI.' -FormatArgs @((Get-UxUndoSelectionActionLabel)))
				(Get-UxLocalizedString -Key 'GuiUndoRestoreSafeDefaultsRecorded' -Fallback 'Restore Defaults restores supported tweaks to recorded default values.')
				(Get-UxLocalizedString -Key 'GuiUndoRestoreSafeRollback' -Fallback '{0}, when it appears after a run, saves reversible-here undo commands for supported changes.' -FormatArgs @((Get-UxUndoProfileActionLabel)))
				(Get-UxLocalizedString -Key 'GuiUndoRestoreSafeManual' -Fallback 'Some destructive or one-way actions require manual recovery.')
			)
		}

		return @(
			(Get-UxLocalizedString -Key 'GuiUndoRestoreStdSnapshot' -Fallback 'Restore Snapshot restores the last captured GUI state only. It does not execute tweaks.')
			(Get-UxLocalizedString -Key 'GuiUndoRestoreStdDefaultsRecorded' -Fallback 'Restore Defaults restores supported tweaks to recorded default values.')
			(Get-UxLocalizedString -Key 'GuiUndoRestoreStdRollback' -Fallback 'Export Rollback Profile, when it appears after a run, saves reversible-here undo commands only.')
			(Get-UxLocalizedString -Key 'GuiUndoRestoreStdManual' -Fallback 'Some destructive or one-way actions require manual recovery.')
		)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxImportExportLines
	{
		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			return @(
				(Get-UxLocalizedString -Key 'GuiImportExportSafeExport' -Fallback 'Export Settings saves the current GUI selection to a file.')
				(Get-UxLocalizedString -Key 'GuiImportExportSafeImport' -Fallback 'Import Settings restores a saved selection into the GUI for review before you apply it.')
			)
		}

		return @(
			(Get-UxLocalizedString -Key 'GuiImportExportStdExport' -Fallback 'Export Settings saves the current GUI selection to a file.')
			(Get-UxLocalizedString -Key 'GuiImportExportStdImport' -Fallback 'Import Settings restores a saved selection into the GUI for review before execution.')
		)
	}

	<#
	    .SYNOPSIS
	#>

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
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModeIntro' -Fallback 'Expert Mode is active with Game Mode enabled.'))
				[void]$lines.Add('')
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModePlan' -Fallback 'Game Mode is currently driving the {0} profile plan, so preset onboarding is skipped while it is active.' -FormatArgs @($gameModeProfile)))
				[void]$lines.Add('')
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModePreview' -Fallback '{0} to inspect gaming actions, risk, restart, and recovery guidance.' -FormatArgs @($previewLabel))))
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModeRefine' -Fallback 'Use the Gaming tab controls to refine the active game profile plan.')))
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModeOff' -Fallback 'Turn off Game Mode if you want to return to preset-based workflows.')))
				[void]$lines.Add('')
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeQuickStartLabel' -Fallback 'Quick Start:'))
				[void]$lines.Add(("1. " + (Get-UxLocalizedString -Key 'GuiWelcomeExpertGameModeStep1' -Fallback 'Review the active {0} game profile plan' -FormatArgs @($gameModeProfile))))
				[void]$lines.Add(("2. {0}" -f $previewLabel))
				[void]$lines.Add(("3. {0}" -f $runLabel))
			}
			else
			{
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeBaselineHelps' -Fallback 'Baseline helps you safely optimize Windows settings.'))
				[void]$lines.Add('')
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiQuickStepGameModeActive' -Fallback 'Game Mode is active and using the {0} profile.' -FormatArgs @($gameModeProfile)))
				[void]$lines.Add('')
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeGameModePreviewShows' -Fallback '{0} shows what the game profile will change' -FormatArgs @($previewLabel))))
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeUndoReverses' -Fallback 'Undo reverses your last changes')))
				[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeRestoreDefaults' -Fallback 'Restore to Defaults resets supported settings')))
				[void]$lines.Add('')
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeStartGuideLabel' -Fallback 'Start Guide:'))
				[void]$lines.Add(("1. " + (Get-UxLocalizedString -Key 'GuiWelcomeGameModeStep1' -Fallback 'Review the active {0} game profile' -FormatArgs @($gameModeProfile))))
				[void]$lines.Add(("2. {0}" -f $previewLabel))
				[void]$lines.Add(("3. {0}" -f $runLabel))
			}

			return ($lines -join [Environment]::NewLine)
		}

		if ($onboardingMode -eq 'Expert')
		{
			[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeExpertUnlocks' -Fallback 'Expert Mode unlocks all presets, including advanced and high-risk tweaks.'))
			[void]$lines.Add('')
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertAdvanced' -Fallback 'Advanced is the recommended starting point and loads the broadest selection.')))
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertPreview' -Fallback '{0} shows the full execution plan, including risk, restart, and recovery guidance.' -FormatArgs @($previewLabel))))
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertUndoRestore' -Fallback 'Undo reverses your last run. Restore to Defaults resets supported settings.')))
			[void]$lines.Add('')
			[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeQuickStartLabel' -Fallback 'Quick Start:'))
			[void]$lines.Add(('1. ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertStep1' -Fallback 'Start with Advanced or customize individual tweaks')))
			[void]$lines.Add(('2. ' + (Get-UxLocalizedString -Key 'GuiWelcomeExpertStep2' -Fallback '{0} to inspect the execution plan' -FormatArgs @($previewLabel))))
			[void]$lines.Add(('3. {0}' -f $runLabel))
		}
		else
		{
			[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeBaselineHelps' -Fallback 'Baseline helps you safely optimize Windows settings.'))
			[void]$lines.Add('')
			[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeExplore' -Fallback 'You can safely explore Baseline before applying changes.'))
			[void]$lines.Add('')
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomePreviewShows' -Fallback '{0} shows what will change' -FormatArgs @($previewLabel))))
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeUndoReverses' -Fallback 'Undo reverses your last changes')))
			[void]$lines.Add(([char]0x2022 + ' ' + (Get-UxLocalizedString -Key 'GuiWelcomeRestoreDefaults' -Fallback 'Restore to Defaults resets supported settings')))
			[void]$lines.Add('')
			[void]$lines.Add((Get-UxLocalizedString -Key 'GuiWelcomeStartGuideLabel' -Fallback 'Start Guide:'))
			[void]$lines.Add(('1. ' + (Get-UxLocalizedString -Key 'GuiWelcomeDefaultStep1' -Fallback 'Choose a preset')))
			[void]$lines.Add(('2. {0}' -f $previewLabel))
			[void]$lines.Add(('3. {0}' -f $runLabel))
		}

		return ($lines -join [Environment]::NewLine)
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxPresetDisplayName
	{
		param ([string]$PresetName)

		if ((Get-UxOnboardingMode) -eq 'Safe')
		{
			switch ($PresetName)
			{
				'Minimal' { return (Get-UxLocalizedString -Key 'GuiPresetQuickStart' -Fallback 'Quick Start') }
				'Basic'   { return (Get-UxLocalizedString -Key 'GuiPresetRecommended' -Fallback 'Recommended') }
			}
		}

		return $PresetName
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxPresetEmphasisText
	{
		switch (Get-UxOnboardingMode)
		{
			'Safe'
			{
				$qsLabel = Get-UxLocalizedString -Key 'GuiPresetQuickStart' -Fallback 'Quick Start'
				return (Get-UxLocalizedString -Key 'GuiPresetStartHereEmphasis' -Fallback '{0} is recommended for your first run.' -FormatArgs @($qsLabel))
			}
			'Expert'
			{
				return (Get-UxLocalizedString -Key 'GuiPresetEmphasisExpert' -Fallback 'Start with Advanced to load the full expert preset, or choose a narrower tier if you want less scope.')
			}
		}

		return (Get-UxLocalizedString -Key 'GuiPresetEmphasisDefault' -Fallback 'Use these shortcuts to start from a sensible baseline before fine-tuning individual tweaks.')
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxPresetSummaryText
	{
		switch (Get-UxOnboardingMode)
		{
			'Safe'
			{
				return (Get-UxLocalizedString -Key 'GuiPresetSummarySafe' -Fallback 'Quick Start includes privacy essentials. Recommended adds broader privacy and performance tweaks. More presets are available when you turn off Safe Mode.')
			}
			'Expert'
			{
				return (Get-UxLocalizedString -Key 'GuiPresetSummaryExpert' -Fallback 'Advanced is the expert starting point in Expert Mode and loads the broadest preset selection. Balanced and Basic remain available if you want a narrower scope; review Advanced carefully before running.')
			}
		}

		return (Get-UxLocalizedString -Key 'GuiPresetSummaryDefault' -Fallback 'Minimal is the safest start. Basic is the recommended default. Balanced widens the selection. Advanced is the expert preset and should be reviewed carefully.')
	}

	<#
	    .SYNOPSIS
	#>

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
			$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmGameModePreparing' -Fallback 'Game Mode is preparing the {0} profile.' -FormatArgs @($Script:GameModeProfile))
			if (Test-IsSafeModeUX)
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmGameModeSafeReview' -Fallback 'Review the grouped gaming actions before you continue. Restore point recommended if this is your first time.')
			}
			else
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmGameModeExpertReview' -Fallback 'Review the grouped gaming actions, restart notes, recovery guidance, and reversible-here coverage before you continue.')
			}
		}
		elseif ($Summary.RiskLevel -eq 'High')
		{
			if (Test-IsSafeModeUX)
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmHighRiskSafe' -Fallback 'This selection includes changes that may affect how some apps or features work.')
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmHighRiskSafeRestore' -Fallback 'A restore point will be created automatically. You can also use {0} to see exactly what will happen.' -FormatArgs @($previewLabel))
			}
			else
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmHighRiskExpert' -Fallback 'This selection includes high-risk or manual recovery changes.')
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmHighRiskExpertDetail' -Fallback 'They may remove Windows features, affect update, network, gaming, or compatibility behavior, and be difficult to undo.')
			}
		}
		else
		{
			if (Test-IsSafeModeUX)
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmMediumRiskSafe' -Fallback 'This selection includes some changes that may affect app compatibility.')
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmMediumRiskSafePreview' -Fallback 'Use {0} to see exactly what will change.' -FormatArgs @($previewLabel))
			}
			else
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmMediumRiskExpert' -Fallback 'This selection includes moderate-risk changes.')
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmMediumRiskExpertDetail' -Fallback 'They may affect compatibility, workflow behavior, or system defaults.')
			}
		}

		if ($AdvancedTierCount -gt 0)
		{
			if (Test-IsExpertModeUX)
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmAdvancedTierExpert' -Fallback '{0} Advanced-tier change{1} included.' -FormatArgs @($AdvancedTierCount, $(if ($AdvancedTierCount -eq 1) { '' } else { 's' })))
			}
			else
			{
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmAdvancedTierStd' -Fallback 'This selection includes Advanced-tier changes.')
				$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmAdvancedTierStdDetail' -Fallback 'Advanced is the expert preset and is intended for experienced users who are comfortable with the tradeoffs.')
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
			$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmTipSafe' -Fallback 'Tip: {0} lets you see every action before anything is applied.' -FormatArgs @($previewLabel))
		}
		else
		{
			$messageParts += (Get-UxLocalizedString -Key 'GuiConfirmTipStd' -Fallback '{0} lets you review the exact actions before they apply.' -FormatArgs @($previewLabel))
		}

		return $messageParts
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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
		$validationMatrix = $null
		try
		{
			if (Get-Command -Name 'Get-BaselineValidationMatrixSummary' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$validationMatrix = Get-BaselineValidationMatrixSummary
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'UxPolicy.GetUxExecutionSummary.LoadValidationMatrix'
			$validationMatrix = $null
		}
		$currentOS = $null
		try
		{
			if (Get-Command -Name 'Get-OSInfo' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$currentOS = Get-OSInfo
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'UxPolicy.GetUxExecutionSummary.LoadOSInfo'
			$currentOS = $null
		}
		$serverValidationWarning = $null
		if ($currentOS -and $currentOS.IsWindowsServer)
		{
			if ($validationMatrix -and $validationMatrix.ServerValidationSummary)
			{
				$serverValidationWarning = if ([bool]$validationMatrix.ServerCIOnly) {
					('Server validation outside CI remains CI only: {0}.' -f [string]$validationMatrix.ServerValidationSummary)
				}
				else
				{
					('Server validation outside CI is covered: {0}.' -f [string]$validationMatrix.ServerValidationSummary)
				}
			}
			else
			{
				$serverValidationWarning = 'Server validation outside CI is not recorded in the current matrix.'
			}
		}

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
			# Expert Mode: full detail - always show all metrics for completeness
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
			# Standard Mode: moderate detail - show nonzero metrics, skip zero-value recovery noise
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
		if ($serverValidationWarning)
		{
			$summaryParts += $serverValidationWarning
		}

		return $summaryParts
	}

	<#
	    .SYNOPSIS
	#>

	function Get-UxPreviewSummaryCards
	{
		# Safe Mode: compact set with friendly labels.
		# Standard Mode: core cards + conditional extras (hide zero-value recovery noise).
		# Expert Mode: full card set - always show all metrics for completeness.
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
			# Expert Mode: full card set - always show all metrics for completeness
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

		# Standard Mode: core cards + conditional extras - suppress zero-value recovery noise
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

	<#
	    .SYNOPSIS
	#>

	function Get-UxRestoreDefaultsConfirmation
	{
		$restoreTitle = Get-UxLocalizedString -Key 'GuiRestoreDefaultsTitleRecorded' -Fallback 'Restore Defaults'
		$cancelLabel = Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel'
		$restoreBtn = Get-UxLocalizedString -Key 'GuiRestoreDefaultsBtn' -Fallback 'Restore Defaults'
		if (Test-IsSafeModeUX)
		{
			return [pscustomobject]@{
				Title   = $restoreTitle
				Message = (Get-UxLocalizedString -Key 'GuiRestoreDefaultsSafeMsgRecorded' -Fallback "This will undo supported tweaks and return them to recorded default values where supported.`n`nSome changes (like removed apps or one-way security settings) require manual recovery.`n`nWould you like to continue?")
				Buttons = @($cancelLabel, $restoreBtn)
				DestructiveButton = $restoreBtn
			}
		}
		if (Test-IsExpertModeUX)
		{
			return [pscustomobject]@{
				Title   = $restoreTitle
				Message = (Get-UxLocalizedString -Key 'GuiRestoreDefaultsExpertMsgRecorded' -Fallback "Reset tweaks to recorded default values where supported.`n`nOS Hardening, permanent removals, and manual recovery actions will be skipped.")
				Buttons = @($cancelLabel, $restoreBtn)
				DestructiveButton = $restoreBtn
			}
		}
		return [pscustomobject]@{
			Title   = $restoreTitle
			Message = (Get-UxLocalizedString -Key 'GuiRestoreDefaultsStdMsgRecorded' -Fallback "This will reset tweaks to recorded default values where supported.`n`nNote: OS Hardening tweaks and other permanent changes cannot be reversed and will be skipped.`n`nAre you sure you want to continue?")
			Buttons = @($cancelLabel, $restoreBtn)
			DestructiveButton = $restoreBtn
		}
	}

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function Get-UxRemoteManagementHelpLines
	{
		param (
			[ValidateSet('Safe', 'Standard', 'Expert')]
			[string]$Mode = 'Standard'
		)

		$lines = [System.Collections.Generic.List[string]]::new()
		[void]$lines.Add((Get-UxLocalizedString -Key 'GuiHelpRemoteCliPreview' -Fallback 'Remote management currently uses PowerShell Remoting through the CLI only. The GUI does not yet provide a remote connection or session workflow.'))

		switch ($Mode)
		{
			'Safe'
			{
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiHelpRemoteSafeSingleTarget' -Fallback 'Treat remote use as an admin-reviewed lab workflow: connect explicitly, validate one machine first, and prefer read-only compliance checks before apply runs.'))
			}
			'Expert'
			{
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiHelpRemoteExpertRequirements' -Fallback 'Enterprise readiness still requires an explicit connection layer, reusable session tracking, visible target context, per-machine execution reporting, and aggregated remote logs.'))
			}
			default
			{
				[void]$lines.Add((Get-UxLocalizedString -Key 'GuiHelpRemoteStandardRequirements' -Fallback 'Before using remote targeting, verify WinRM, firewall access, credentials, and managed-device policy constraints.'))
			}
		}

		[void]$lines.Add((Get-UxLocalizedString -Key 'GuiHelpRemoteManagedDevices' -Fallback 'Managed, work, school, or domain-enrolled devices should be reviewed with the appropriate admin team before remote runs.'))
		return @($lines)
	}

	<#
	    .SYNOPSIS
	#>

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
				(Get-UxLocalizedString -Key 'GuiHelpSectionWelcome' -Fallback 'Welcome - First Steps') = @(
					(Get-UxLocalizedString -Key 'GuiHelpSafeRunningInSafeMode' -Fallback 'You are running in Safe Mode, which hides advanced and risky tweaks so you can explore conservatively.')
					(Get-UxLocalizedString -Key 'GuiHelpSafeRecommendedPreset' -Fallback '{0} is the recommended preset for most users and keeps the first run conservative.' -FormatArgs @($recommendedPreset))
					(Get-UxLocalizedString -Key 'GuiHelpSafeUsePreview' -Fallback 'Use {0} to see exactly what will happen before anything is applied.' -FormatArgs @($previewLabel))
					(Get-UxLocalizedString -Key 'GuiHelpSafeUndoSelection' -Fallback '{0} lets you reverse the last preset or imported selection change if you change your mind.' -FormatArgs @($undoSelectionLabel))
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionStartGuide' -Fallback 'Start Guide') = @(Get-UxHelpGettingStartedLines -Mode 'Safe')
				(Get-UxLocalizedString -Key 'GuiHelpSectionPresets' -Fallback 'Presets') = @(
					(Get-UxLocalizedString -Key 'GuiHelpSafePresetMinimal' -Fallback 'Minimal is the recommended preset for most users and is the easiest place to begin.')
					(Get-UxLocalizedString -Key 'GuiHelpSafePresetBasic' -Fallback 'Basic adds a broader low-risk mix of cleanup, privacy, and usability changes after you review Minimal.')
					(Get-UxLocalizedString -Key 'GuiHelpSafePresetAdvanced' -Fallback 'Balanced and Advanced are for experienced users and become visible when Safe Mode is turned off.')
					(Get-UxLocalizedString -Key 'GuiHelpPresetReplace' -Fallback 'Clicking a preset replaces any previously loaded selection.')
					(Get-UxLocalizedString -Key 'GuiHelpPresetNoExec' -Fallback 'Presets only update the GUI selection. They do not execute changes.')
				)
				$previewLabel = @(
					(Get-UxLocalizedString -Key 'GuiHelpPreviewShows' -Fallback '{0} shows what would happen without applying any changes.' -FormatArgs @($previewLabel))
					(Get-UxLocalizedString -Key 'GuiHelpPreviewCheck' -Fallback 'Use it to check your selection before committing.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionApply' -Fallback 'Apply Tweaks') = @(
					(Get-UxLocalizedString -Key 'GuiHelpApplyAction' -Fallback '{0} applies the current GUI selection to your system.' -FormatArgs @($applyLabel))
					(Get-UxLocalizedString -Key 'GuiHelpApplyResults' -Fallback 'Expected results per tweak: Success, Failed, Skipped, Already Applied.')
					(Get-UxLocalizedString -Key 'GuiHelpApplyRestart' -Fallback 'Restart if prompted after the run completes.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionRiskLevels' -Fallback 'Risk Levels') = @(
					(Get-UxLocalizedString -Key 'GuiHelpRiskLow' -Fallback 'Low Risk: safe usability and quality-of-life changes.')
					(Get-UxLocalizedString -Key 'GuiHelpRiskMedium' -Fallback 'Medium Risk: may affect behavior or compatibility.')
					(Get-UxLocalizedString -Key 'GuiHelpRiskHigh' -Fallback 'High Risk: may be difficult to reverse - hidden while Safe Mode is on.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionUndoRestore' -Fallback 'Undo and Restore') = $undoAndRestoreLines
				(Get-UxLocalizedString -Key 'GuiHelpSectionImportExport' -Fallback 'Import / Export') = $importExportLines
				(Get-UxLocalizedString -Key 'GuiHelpSectionSafeMode' -Fallback 'Safe Mode') = @(
					(Get-UxLocalizedString -Key 'GuiHelpSafeModeHides' -Fallback 'Safe Mode hides dangerous, hard-to-reverse, and removal-style tweaks.')
					(Get-UxLocalizedString -Key 'GuiHelpSafeModeDefault' -Fallback 'It is enabled by default on a fresh launch.')
					(Get-UxLocalizedString -Key 'GuiHelpSafeModeClears' -Fallback 'Turning Safe Mode on clears any selections that would otherwise be hidden.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionExpertMode' -Fallback 'Expert Mode') = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertReveals' -Fallback 'Expert Mode reveals all tweaks including high-risk and advanced changes.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertUseOnly' -Fallback 'Use it only if you understand the impact of each setting.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertDisablesSafe' -Fallback 'Turning Expert Mode on disables Safe Mode.')
				)
			}

			if ($isGameModeActive)
			{
				$sections[(Get-UxLocalizedString -Key 'GuiHelpSectionGameMode' -Fallback 'Game Mode')] = @(
					(Get-UxLocalizedString -Key 'GuiQuickStepGameModeActive' -Fallback 'Game Mode is active and using the {0} profile.' -FormatArgs @($gameModeProfile))
					(Get-UxLocalizedString -Key 'GuiHelpGameModeOnlyGaming' -Fallback 'While Game Mode is active, only the Gaming tab plan can be edited or run.')
					(Get-UxLocalizedString -Key 'GuiHelpGameModeChooseProfile' -Fallback 'Choose a gaming profile to build a focused plan, then use {0} to inspect it.' -FormatArgs @($previewLabel))
					(Get-UxLocalizedString -Key 'GuiHelpGameModeTurnOff' -Fallback 'Turn off Game Mode to return to preset-based workflows.')
				)
			}

			$sections[(Get-UxLocalizedString -Key 'GuiHelpSectionLogs' -Fallback 'Logs and Troubleshooting')] = @(
				(Get-UxLocalizedString -Key 'GuiHelpLogOpen' -Fallback 'Open Log shows the session log for troubleshooting.')
				(Get-UxLocalizedString -Key 'GuiHelpLogDetails' -Fallback 'If something fails, the log and execution summary have details.')
			)
			$sections[(Get-UxLocalizedString -Key 'GuiHelpSectionRemoteManagement' -Fallback 'Remote Management')] = @(Get-UxRemoteManagementHelpLines -Mode 'Safe')

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
				(Get-UxLocalizedString -Key 'GuiHelpExpertSectionGettingStarted' -Fallback 'Quick Start') = @(Get-UxHelpGettingStartedLines -Mode 'Expert')
				(Get-UxLocalizedString -Key 'GuiHelpSectionPresets' -Fallback 'Presets') = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertPresetList' -Fallback 'Minimal, Basic, Balanced, Advanced load from preset files.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertAdvancedReview' -Fallback 'Advanced is the expert preset and should be reviewed with risk, restart, and recovery guidance in mind.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertPresetReplace' -Fallback 'Presets replace the current selection - they do not stack.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertRunApplies' -Fallback ('{0} applies the current GUI selection.' -f (Get-UxRunActionLabel)))
				)
				$previewLabel = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertPreviewPlan' -Fallback '{0} shows the execution plan for the current selection, including risk, restart required, restore, and category metadata.' -FormatArgs @($previewLabel))
				)
				(Get-UxLocalizedString -Key 'GuiHelpExpertSectionRunTweaks' -Fallback (Get-UxRunActionLabel)) = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertRunOutcomes' -Fallback 'Executes selected items. Outcome states: Success, Failed, Skipped, Already Applied.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpSectionRiskLevels' -Fallback 'Risk Levels') = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertRiskLow' -Fallback 'Low: safe QoL changes. Medium: behavioral/compatibility impact. High: hard to reverse.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertRiskRestart' -Fallback 'Restart required: needs reboot to take full effect.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpExpertSectionRestoreDefaultsRecorded' -Fallback 'Restore Defaults') = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertRestoreResets' -Fallback 'Resets supported defaults. Manual recovery items and OS Hardening items are skipped.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertRestoreReversible' -Fallback 'Reversible here (post-run) is a separate recovery path.')
				)
				(Get-UxLocalizedString -Key 'GuiHelpExpertSectionModes' -Fallback 'Modes') = @(
					(Get-UxLocalizedString -Key 'GuiHelpExpertModeSafe' -Fallback 'Safe Mode: conservative filter - hides high-risk, removal, and manual recovery tweaks.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertModeExpert' -Fallback 'Expert Mode: full visibility - all tweaks and metadata exposed.')
					(Get-UxLocalizedString -Key 'GuiHelpExpertModeExclusive' -Fallback 'Safe and Expert are mutually exclusive visibility switches.')
				)
			}

			$sections[(Get-UxLocalizedString -Key 'GuiHelpExpertSectionScan' -Fallback 'System Scan')] = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertScanRefresh' -Fallback 'Refreshes current system state for supported tweaks.')
			)
			$sections[(Get-UxLocalizedString -Key 'GuiHelpExpertSectionImportExport' -Fallback 'Import / Export / Session Restore')] = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertIEExport' -Fallback 'Export/Import saves and restores GUI selections.')
				(Get-UxLocalizedString -Key 'GuiHelpExpertIESnapshot' -Fallback 'Restore Snapshot restores last captured GUI state (no execution).')
				(Get-UxLocalizedString -Key 'GuiHelpExpertIERollback' -Fallback 'Rollback Profile exports reversible-here undo commands only.')
			)
			$sections[(Get-UxLocalizedString -Key 'GuiHelpExpertSectionLogs' -Fallback 'Logs')] = @(
				(Get-UxLocalizedString -Key 'GuiHelpExpertLogShows' -Fallback 'Open Log shows session output. Unmatched preset lines and failures are logged.')
			)
			$sections[(Get-UxLocalizedString -Key 'GuiHelpSectionRemoteManagement' -Fallback 'Remote Management')] = @(Get-UxRemoteManagementHelpLines -Mode 'Expert')

			return $sections
		}

		return [ordered]@{
			(Get-UxLocalizedString -Key 'GuiHelpStdSectionGettingStarted' -Fallback 'Quick Start') = @(Get-UxHelpGettingStartedLines -Mode 'Standard')
			(Get-UxLocalizedString -Key 'GuiHelpSectionPresets' -Fallback 'Presets') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetList' -Fallback 'Minimal, Basic, Balanced, and Advanced load selections from their matching preset files.')
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetBasicRec' -Fallback 'Basic is the recommended default for normal users.')
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetBalanced' -Fallback 'Balanced is for enthusiasts who understand moderate tradeoffs.')
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetAdvanced' -Fallback 'Advanced is the expert preset for experienced users and recommends a restore point before continuing.')
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetReplace' -Fallback 'Clicking a preset replaces any previously loaded selection - selections do not stack.')
				(Get-UxLocalizedString -Key 'GuiHelpStdPresetNoExec2' -Fallback 'Presets only update the GUI selection. They do not execute changes.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRunApplies' -Fallback ('{0} applies the current GUI selection.' -f (Get-UxRunActionLabel)))
			)
			$previewLabel = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdPreviewShows' -Fallback '{0} shows what would execute from the current selection without applying any changes.' -FormatArgs @($previewLabel))
				(Get-UxLocalizedString -Key 'GuiHelpStdPreviewMeta' -Fallback 'It also shows risk, restart, restore, and category summary information.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpStdSectionRunTweaks' -Fallback (Get-UxRunActionLabel)) = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdRunExec' -Fallback ('{0} executes only the items currently selected in the GUI.' -f (Get-UxRunActionLabel)))
				(Get-UxLocalizedString -Key 'GuiHelpStdRunOutcomes' -Fallback 'Expected result states per tweak: Success, Failed, Skipped, Already Applied.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpSectionRiskLevels' -Fallback 'Risk Levels') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdRiskLow' -Fallback 'Low Risk: generally safe usability and quality-of-life changes.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRiskMedium' -Fallback 'Medium Risk: may affect behavior, compatibility, networking, or security posture.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRiskHigh' -Fallback 'High Risk: may reduce compatibility, disable features, or be difficult to reverse.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRiskRestart' -Fallback 'Restart required badge: the tweak requires a system restart to take full effect.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpStdSectionRestoreDefaultsRecorded' -Fallback 'Restore Defaults') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdRestoreSupported' -Fallback 'Restores supported default values only.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRestoreNoGuarantee' -Fallback 'Does not guarantee that every previous change can be undone.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRestoreManual' -Fallback 'Some destructive or one-way actions require manual recovery.')
				(Get-UxLocalizedString -Key 'GuiHelpStdRestoreReversibleRecorded' -Fallback 'Reversible here, when available after a run, is a separate recovery path from restoring recorded default values.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpSectionSafeMode' -Fallback 'Safe Mode') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdSafeModeHides' -Fallback 'Safe Mode hides dangerous, hard-to-reverse, and removal-style tweaks.')
				(Get-UxLocalizedString -Key 'GuiHelpStdSafeModeConservative' -Fallback 'It is the conservative visibility switch for people who want the safest view of the GUI.')
				(Get-UxLocalizedString -Key 'GuiHelpStdSafeModeDefault' -Fallback 'Safe Mode is enabled by default on a fresh launch.')
				(Get-UxLocalizedString -Key 'GuiHelpStdSafeModeClears' -Fallback 'Turning Safe Mode on clears selections that would otherwise be hidden.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpSectionExpertMode' -Fallback 'Expert Mode') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdExpertReveals' -Fallback 'Expert Mode reveals high-risk and advanced tweaks hidden by default.')
				(Get-UxLocalizedString -Key 'GuiHelpStdExpertUseOnly' -Fallback 'Use it only if you understand the impact of the settings being changed.')
				(Get-UxLocalizedString -Key 'GuiHelpStdExpertClears' -Fallback 'Turning Expert Mode off clears hidden advanced selections from the current view.')
				(Get-UxLocalizedString -Key 'GuiHelpStdExpertOpposite' -Fallback 'Safe Mode is the opposite visibility switch and keeps dangerous tweaks hidden instead.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpStdSectionScan' -Fallback 'System Scan') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdScanChecks' -Fallback 'System Scan checks the current system state and refreshes supported tweak states in the GUI.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpStdSectionImportExport' -Fallback 'Import / Export / Session Restore') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdIEExport' -Fallback 'Export Settings saves the current GUI selection to a file.')
				(Get-UxLocalizedString -Key 'GuiHelpStdIEImport' -Fallback 'Import Settings restores a saved selection into the GUI for review before execution.')
				(Get-UxLocalizedString -Key 'GuiHelpStdIESnapshot' -Fallback 'Restore Snapshot restores the last captured GUI state only. It does not execute tweaks.')
				(Get-UxLocalizedString -Key 'GuiHelpStdIERollbackRecorded' -Fallback 'Export Rollback Profile, when offered after a run, saves reversible-here undo commands only and is separate from Restore Snapshot or restoring recorded defaults.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpSectionLogs' -Fallback 'Logs and Troubleshooting') = @(
				(Get-UxLocalizedString -Key 'GuiHelpStdLogOpen' -Fallback 'Open Log opens the current session log for troubleshooting.')
				(Get-UxLocalizedString -Key 'GuiHelpStdLogPreset' -Fallback 'If a preset line cannot be matched to a tweak it will be reported in the log.')
				(Get-UxLocalizedString -Key 'GuiHelpStdLogFail' -Fallback 'If a tweak fails, review the log and the execution summary for details.')
			)
			(Get-UxLocalizedString -Key 'GuiHelpSectionRemoteManagement' -Fallback 'Remote Management') = @(Get-UxRemoteManagementHelpLines -Mode 'Standard')
		}
	}

	<#
	    .SYNOPSIS
	#>

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
