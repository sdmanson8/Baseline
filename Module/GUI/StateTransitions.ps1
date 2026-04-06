# Shared state-transition orchestration for GUI mode and preset changes.
# Dot-sourced inside Show-TweakGUI after GuiContext.ps1.
#
# AS-3: Collapses duplicate orchestration patterns found in ModeState.ps1
# and PresetApplication.ps1. Each mode/preset toggle follows the same
# sequence: save undo -> apply state -> clear cache -> rebuild tab -> status.

	function Invoke-GuiStateTransition
	{
		<#
		.SYNOPSIS Executes the common steps for any GUI mode or preset state change.
		.DESCRIPTION
			Provides a single orchestration path for the repeating pattern:
			1. Save undo snapshot
			2. Execute caller-specific state change logic
			3. Clear tab content cache
			4. Rebuild the current tab
			5. Sync action button text
			6. Set status message
		.PARAMETER Context
			Label for logging / debugging: 'Preset', 'Mode', 'GameMode'.
		.PARAMETER ApplyState
			Scriptblock containing the unique state-change logic for this transition.
		.PARAMETER StatusMessage
			Text shown in the status bar after the transition completes.
		.PARAMETER StatusTone
			Tone passed to Set-GuiStatusText (accent, success, caution, muted, danger).
		.PARAMETER SaveUndo
			When set, saves an undo snapshot before applying state.
		.PARAMETER ClearCache
			When set, clears the tab content cache after applying state.
		.PARAMETER RebuildTab
			When set, rebuilds the current tab content after applying state.
		.PARAMETER UpdatePresetBadge
			When set, also updates the $Script:PresetStatusBadge text.
		.PARAMETER SyncActionButton
			When set, synchronizes the Run action button label.
		.PARAMETER UpdateModeText
			When set, refreshes the header mode-state indicator.
		#>
		param (
			[string]$Context = 'Unknown',
			[scriptblock]$ApplyState,
			[string]$StatusMessage,
			[string]$StatusTone = 'accent',
			[switch]$SaveUndo,
			[switch]$ClearCache,
			[switch]$RebuildTab,
			[switch]$UpdatePresetBadge,
			[switch]$SyncActionButton,
			[switch]$UpdateModeText
		)

		# Uses $Script: late-bind captures set during initialization in GUI.psm1.

		# 1. Save undo state
		if ($SaveUndo -and $Script:SaveGuiUndoSnapshotScript)
		{
			& $Script:SaveGuiUndoSnapshotScript
		}

		# 2. Execute the caller-specific state change
		if ($ApplyState)
		{
			& $ApplyState
		}

		# 3. Clear tab cache
		if ($ClearCache -and $Script:ClearTabContentCacheScript)
		{
			$Script:FilterGeneration++
			& $Script:ClearTabContentCacheScript
		}

		# 4. Rebuild current tab
		if ($RebuildTab -and $Script:UpdateCurrentTabContentScript)
		{
			# Flush pending input events (hover, scroll, click) before the
			# expensive rebuild so the UI doesn't feel frozen.
			try
			{
				[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
					[action]{}, [System.Windows.Threading.DispatcherPriority]::Input)
			}
			catch { <# non-fatal #> }

			& $Script:UpdateCurrentTabContentScript -SkipIdlePrebuild
			if (Get-Command -Name 'Sync-ActivePresetButtonChrome' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Sync-ActivePresetButtonChrome
			}
		}

		# 5. Sync action button text
		if ($SyncActionButton -and $Script:SyncUxActionButtonTextScript)
		{
			& $Script:SyncUxActionButtonTextScript
		}

		# 6. Update header mode text
		if ($UpdateModeText -and $Script:UpdateHeaderModeStateTextScript)
		{
			& $Script:UpdateHeaderModeStateTextScript
		}

		# 7. Set status message and badge
		if (-not [string]::IsNullOrWhiteSpace($StatusMessage))
		{
			$Script:PresetStatusMessage = $StatusMessage
			if ($UpdatePresetBadge -and $Script:PresetStatusBadge -and $Script:PresetStatusBadge.Child -is [System.Windows.Controls.TextBlock])
			{
				$Script:PresetStatusBadge.Child.Text = $StatusMessage
			}
			Set-GuiStatusText -Text $StatusMessage -Tone $(if ([string]::IsNullOrWhiteSpace($StatusTone)) { 'accent' } else { $StatusTone })
		}

		# 8. Keep Ctx mirrors in sync
		if (Get-Command -Name 'Sync-GuiContextFromScriptState' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-GuiContextFromScriptState
		}
	}
