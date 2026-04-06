# GUI context hashtable ($Script:Ctx) - groups $Script: variables by category.
# Loaded first in Show-TweakGUI. Direct $Script: access still works everywhere.

	function New-GuiContext
	{
		param ([hashtable]$Overrides = @{})

		$ctx = @{
			Theme = @{
				Current          = $null
				CurrentName      = 'Dark'
				Dark             = $null
				Light            = $null
				BrushCache       = @{}
				BrushConverter   = $null
				CardShadow       = $null
				FallbackWarnings = @{}
				RuntimeWarnings  = @{}
				CurrentTone      = 'muted'
			}
			Data = @{
				TweakManifest         = $null
				Controls              = $null
				FunctionToIndex       = $null
				DetectScriptblocks    = $null
				VisibleIfScriptblocks = $null
				ManifestLoaded        = $false
				GameModeAllowlist     = @()
				SearchHaystacks       = $null
			}
			Run = @{
				InProgress     = $false
				AbortRequested = $false
				RunState       = $null
				ExecutionMode  = $null
				TotalRunnable  = 0
			}
			Filter = @{
				Risk           = 'All'
				Category       = 'All'
				SelectedOnly   = $false
				HighRiskOnly   = $false
				RestorableOnly = $false
				GamingOnly     = $false
				SafeMode       = $false
				AdvancedMode   = $false
				SearchText     = ''
				UiUpdating     = $false
			}
			GameMode = @{
				Active                = $false
				Profile               = $null
				Plan                  = @()
				CorePlan              = @()
				ControlSyncInProgress = $false
				DecisionOverrides     = @{}
				AdvancedSelections    = @{}
				PreviousPrimaryTab    = $null
				Allowlist             = @()
				ExecutionContext       = $null
			}
			UI = @{
				MainForm              = $null
				StatusText            = $null
				ExecutionLogBox       = $null
				ProgressBar           = $null
				ProgressText          = $null
				PresetBadge           = $null
				CurrentPrimaryTab     = $null
				LastStandardPrimaryTab = $null
			}
			Services = @{
				UpdateProgressFn = $null
				AppendLogFn      = $null
				DrainEntry       = $null
				DrainQueueSafely = $null
				ForceCloseFn     = $null
				RequestAbortFn   = $null
				PromptAbortFn    = $null
			}
			Config = @{
				ModuleBasePath      = $null
				ExtractedRoot       = $null
				PresetDirectoryPath = $null
				DisplayVersion      = $null
			}
			Mode = @{
				Safe     = $false
				Expert   = $false
				Game     = $false
				Scenario = $null
			}
			Preset = @{
				StatusMessage = $null
				ActiveName    = $null
				IsScenario    = $false
			}
			State = @{
				UndoSnapshot   = $null
				LastRunProfile = $null
			}
		}

		foreach ($key in $Overrides.Keys)
		{
			if ($ctx.ContainsKey($key) -and $Overrides[$key] -is [hashtable])
			{
				foreach ($subKey in $Overrides[$key].Keys)
				{
					$ctx[$key][$subKey] = $Overrides[$key][$subKey]
				}
			}
		}

		return $ctx
	}

	function Get-GuiContext
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Path,
			[hashtable]$Context = $Script:Ctx
		)

		if ($null -eq $Context -or [string]::IsNullOrWhiteSpace($Path))
		{
			return $null
		}

		$pathParts = $Path.Split('.', 2)
		$categoryName = $pathParts[0]

		if (-not $Context.ContainsKey($categoryName))
		{
			return $null
		}

		if ($pathParts.Count -eq 1)
		{
			return $Context[$categoryName]
		}

		$category = $Context[$categoryName]
		if ($category -isnot [hashtable])
		{
			return $null
		}

		$fieldName = $pathParts[1]
		if (-not $category.ContainsKey($fieldName))
		{
			return $null
		}

		return $category[$fieldName]
	}

	function Set-GuiContext
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$Path,
			[AllowNull()]
			$Value,
			[hashtable]$Context = $Script:Ctx
		)

		if ($null -eq $Context)
		{
			throw 'Context cannot be null.'
		}

		$pathParts = $Path.Split('.', 2)
		if (
			$pathParts.Count -ne 2 -or
			[string]::IsNullOrWhiteSpace($pathParts[0]) -or
			[string]::IsNullOrWhiteSpace($pathParts[1])
		)
		{
			throw 'Path must use Category.Field format.'
		}

		$categoryName = $pathParts[0]
		if (-not $Context.ContainsKey($categoryName))
		{
			throw ("Unknown context category: {0}" -f $categoryName)
		}

		$category = $Context[$categoryName]
		if ($category -isnot [hashtable])
		{
			throw ("Context category '{0}' is not a hashtable." -f $categoryName)
		}

		$category[$pathParts[1]] = $Value
		return $Value
	}

	# --- AS-2: Mirror mutable UI state inside $Script:Ctx ---
	# These keep backward compat - old $Script: variables still work everywhere.
	# The Ctx mirrors provide a single structured place for future callers.

	function Sync-GuiContextFromScriptState
	{
		<# .SYNOPSIS Copies current $Script: mode/preset variables into $Script:Ctx. #>
		if (-not $Script:Ctx) { return }

		# Mode state - read through Get-GuiMode accessor
		if (-not $Script:Ctx.ContainsKey('Mode'))
		{
			$Script:Ctx['Mode'] = @{ Safe = $false; Expert = $false; Game = $false; Scenario = $null }
		}
		$modeSnapshot = Get-GuiMode
		$Script:Ctx.Mode.Safe   = $modeSnapshot.Safe
		$Script:Ctx.Mode.Expert = $modeSnapshot.Expert
		$Script:Ctx.Mode.Game   = $modeSnapshot.Game

		# GameMode detail
		$Script:Ctx.GameMode.Active  = $modeSnapshot.Game
		$Script:Ctx.GameMode.Profile = $Script:GameModeProfile
		$Script:Ctx.GameMode.Plan    = @($Script:GameModePlan)

		# Filter flag
		$Script:Ctx.Filter.UiUpdating = [bool]$Script:FilterUiUpdating

		# Preset state - read active preset through accessor
		if (-not $Script:Ctx.ContainsKey('Preset'))
		{
			$Script:Ctx['Preset'] = @{ StatusMessage = $null; ActiveName = $null; IsScenario = $false }
		}
		$Script:Ctx.Preset.StatusMessage = $Script:PresetStatusMessage
		$Script:Ctx.Preset.ActiveName    = Get-GuiActivePreset
		$Script:Ctx.Preset.IsScenario    = ($Script:ActiveScenarioNames -is [hashtable] -and $Script:ActiveScenarioNames.Count -gt 0)
	}

	function Get-GuiMode
	{
		<# .SYNOPSIS Returns a snapshot of the current GUI mode flags. #>
		return @{
			Safe   = [bool]$Script:SafeMode
			Expert = [bool]$Script:AdvancedMode
			Game   = [bool]$Script:GameMode
		}
	}

	function Test-GuiModeActive
	{
		<# .SYNOPSIS Tests whether a specific GUI mode is active. #>
		param (
			[Parameter(Mandatory = $true)]
			[ValidateSet('Safe', 'Expert', 'Game')]
			[string]$Mode
		)

		switch ($Mode)
		{
			'Safe'   { return [bool]$Script:SafeMode }
			'Expert' { return [bool]$Script:AdvancedMode }
			'Game'   { return [bool]$Script:GameMode }
		}
		return $false
	}

	# --- AS-4: Canonical mode transition function ---

	function Set-GuiMode
	{
		<#
		.SYNOPSIS Formalizes GUI mode state with built-in mutual exclusion.
		.DESCRIPTION
			Safe and Expert are mutually exclusive view modes.
			Game mode is orthogonal (can combine with Safe/Expert/Standard).
			This updates both $Script:Ctx.Mode and the legacy $Script: variables.
		#>
		param (
			[ValidateSet('Safe', 'Expert', 'Standard')]
			[string]$ViewMode,
			[bool]$GameMode = [bool]$Script:GameMode
		)

		# Safe and Expert are mutually exclusive
		if (-not $Script:Ctx.ContainsKey('Mode'))
		{
			$Script:Ctx['Mode'] = @{ Safe = $false; Expert = $false; Game = $false; Scenario = $null }
		}
		$Script:Ctx.Mode.Safe   = ($ViewMode -eq 'Safe')
		$Script:Ctx.Mode.Expert = ($ViewMode -eq 'Expert')
		$Script:Ctx.Mode.Game   = $GameMode

		# Keep legacy $Script: variables in sync
		$Script:SafeMode     = $Script:Ctx.Mode.Safe
		$Script:AdvancedMode = $Script:Ctx.Mode.Expert
		$Script:GameMode     = $Script:Ctx.Mode.Game
	}

	# --- AS-5: Accessor functions for frequently-accessed $Script: state ---
	# These reduce the GUI coordination surface by providing a single read path
	# for state that many files previously accessed via raw $Script: variables.

	function Get-GuiActivePreset { return $Script:ActivePresetName }

	# Test-GuiRunInProgress is defined at module scope in GUI.psm1 so Show-TweakGUI
	# can capture it once for deferred WPF handlers and dispatcher callbacks.

	function Get-GuiCurrentTheme { return $Script:CurrentTheme }

	function Get-GuiCurrentThemeName { return $Script:CurrentThemeName }

	function Get-GuiStatusToneColor
	{
		param (
			[string]$Tone = 'accent'
		)

		$theme = Get-GuiCurrentTheme
		switch ($Tone)
		{
			'success' { return $theme.ToggleOn }
			'caution' { return $theme.CautionText }
			'danger'  { return $theme.RiskMediumBadge }
			'accent'  { return $theme.AccentBlue }
			'muted'   { return $theme.TextSecondary }
			default   { return $theme.AccentBlue }
		}
	}

	function Invoke-GuiDispatcherAction
	{
		param (
			[object]$Dispatcher,
			[Parameter(Mandatory = $true)]
			[scriptblock]$Action,
			[string]$PriorityUsage = 'DeferredContentBuild',
			[switch]$Synchronous
		)

		# Dispatcher can be null during early init or when the window is closing.
		# WPF doesn't have a single "is this dispatcher alive" check - we have to probe
		# each property individually because not all WPF objects expose all shutdown flags.
		if ($null -eq $Dispatcher) { return $false }
		if ((Test-GuiObjectField -Object $Dispatcher -FieldName 'HasShutdownStarted') -and [bool]$Dispatcher.HasShutdownStarted) { return $false }
		if ((Test-GuiObjectField -Object $Dispatcher -FieldName 'HasShutdownFinished') -and [bool]$Dispatcher.HasShutdownFinished) { return $false }
		if ($null -eq $Dispatcher.PSObject.Methods['BeginInvoke'] -or $null -eq $Dispatcher.PSObject.Methods['Invoke']) { return $false }

		if ($Dispatcher.PSObject.Methods['CheckAccess'] -and $Dispatcher.CheckAccess())
		{
			& $Action
			return $true
		}

		$priority = switch ($PriorityUsage)
		{
			'Pump'          { [System.Windows.Threading.DispatcherPriority]::Background }
			'RenderRefresh' { [System.Windows.Threading.DispatcherPriority]::Render }
			'Immediate'     { [System.Windows.Threading.DispatcherPriority]::Send }
			'IdleFinalize'  { [System.Windows.Threading.DispatcherPriority]::ApplicationIdle }
			default         { [System.Windows.Threading.DispatcherPriority]::Loaded }
		}

		if ($Synchronous)
		{
			$Dispatcher.Invoke([System.Action]$Action, $priority)
			return $true
		}

		$null = $Dispatcher.BeginInvoke([System.Action]$Action, $priority)
		return $true
	}

	function Set-GuiStatusText
	{
		param (
			[string]$Text,
			[string]$Tone = 'accent'
		)

		$Script:CurrentStatusTone = if ([string]::IsNullOrWhiteSpace([string]$Tone)) { 'accent' } else { [string]$Tone }
		$color = Get-GuiStatusToneColor -Tone $Script:CurrentStatusTone

		if ($Script:GuiState)
		{
			& $Script:GuiState.SetBatch @{
				StatusText       = [string]$Text
				StatusForeground = [string]$color
			}
		}
		else
		{
			# GuiState isn't wired yet - write directly. This path stays because early-init
			# status updates (manifest load, theme apply) fire before ObservableState is ready.
			if ($StatusText)
			{
				$StatusText.Text = [string]$Text
				$StatusText.Visibility = if ([string]::IsNullOrWhiteSpace([string]$Text)) { 'Collapsed' } else { 'Visible' }
				if ($Script:SharedBrushConverter -and $color)
				{
					$StatusText.Foreground = $Script:SharedBrushConverter.ConvertFromString([string]$color)
				}
			}
		}
	}

	# --- Phase 2: Consolidated accessors for state migrated into $Script:Ctx ---

	function Get-GuiCurrentPrimaryTab { return $Script:Ctx.UI.CurrentPrimaryTab }
	function Set-GuiCurrentPrimaryTab { param($Tab) $Script:Ctx.UI.CurrentPrimaryTab = $Tab }
	function Get-GuiLastStandardPrimaryTab { return $Script:Ctx.UI.LastStandardPrimaryTab }
	function Set-GuiLastStandardPrimaryTab { param($Tab) $Script:Ctx.UI.LastStandardPrimaryTab = $Tab }
	function Get-GuiCurrentStatusTone { return $Script:Ctx.Theme.CurrentTone }
	function Set-GuiCurrentStatusTone { param([string]$Tone) $Script:Ctx.Theme.CurrentTone = $Tone }

