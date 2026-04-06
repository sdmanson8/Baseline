# Safe Mode / Expert Mode state toggle functions.
# Dot-sourced inside Show-TweakGUI.
#
# Single unified toggle: ChkSafeMode checked = Safe Mode, unchecked = Expert Mode.
# The toggle label updates dynamically to reflect the active mode.

	function Set-SafeModeState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)

		$previousState = Test-GuiModeActive -Mode 'Safe'
		$advancedWasEnabled = Test-GuiModeActive -Mode 'Expert'
		$Script:FilterUiUpdating = $true
		try
		{
			Set-GuiMode -ViewMode $(if ($Enabled) { 'Safe' } else { 'Standard' })
			if ($ChkSafeMode)
			{
				$ChkSafeMode.IsChecked = $Enabled
				$ChkSafeMode.Content = 'Safe Mode'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		if (($previousState -eq $Enabled) -and -not ($Enabled -and $advancedWasEnabled))
		{
			return
		}

		$clearedCount = 0
		if ($Enabled)
		{
			$clearedCount = & $Script:ClearInvisibleSelectionStateScript
		}

		$message = if ($Enabled)
		{
			'Safe Mode enabled. Dangerous and hard-to-reverse tweaks are hidden.'
		}
		elseif ($clearedCount -gt 0)
		{
			"Safe Mode disabled. $clearedCount hidden safe selection$(if ($clearedCount -eq 1) { '' } else { 's' }) were cleared."
		}
		else
		{
			'Safe Mode disabled. Original view restored.'
		}

		Invoke-GuiStateTransition `
			-Context 'SafeMode' `
			-StatusMessage $message `
			-StatusTone $(if ($Enabled) { 'success' } else { 'muted' }) `
			-ClearCache `
			-RebuildTab `
			-SyncActionButton `
			-UpdatePresetBadge `
			-UpdateModeText

		if ($ExpertModeBanner)
		{
			$ExpertModeBanner.Visibility = 'Collapsed'
		}

		if (Get-Command -Name 'Update-WindowMinWidthFromHeader' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-WindowMinWidthFromHeader
		}
	}

	function Set-AdvancedModeState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)

		$previousState = Test-GuiModeActive -Mode 'Expert'
		$safeWasEnabled = Test-GuiModeActive -Mode 'Safe'
		$Script:FilterUiUpdating = $true
		try
		{
			Set-GuiMode -ViewMode $(if ($Enabled) { 'Expert' } else { 'Standard' })
			if ($ChkSafeMode)
			{
				$ChkSafeMode.IsChecked = $false
				$ChkSafeMode.Content = 'Safe Mode'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		if (($previousState -eq $Enabled) -and -not ($Enabled -and $safeWasEnabled))
		{
			return
		}

		$clearedCount = 0
		if (-not $Enabled)
		{
			$clearedCount = & $Script:ClearInvisibleSelectionStateScript
		}

		$message = if ($Enabled)
		{
			'Expert Mode enabled. High-risk and advanced tweaks are now visible.'
		}
		elseif ($clearedCount -gt 0)
		{
			"Expert Mode disabled. $clearedCount hidden advanced selection$(if ($clearedCount -eq 1) { '' } else { 's' }) were cleared."
		}
		else
		{
			'Expert Mode disabled. High-risk and advanced tweaks are hidden again.'
		}

		Invoke-GuiStateTransition `
			-Context 'ExpertMode' `
			-StatusMessage $message `
			-StatusTone $(if ($Enabled) { 'success' } else { 'muted' }) `
			-ClearCache `
			-RebuildTab `
			-SyncActionButton `
			-UpdatePresetBadge `
			-UpdateModeText

		if ($ExpertModeBanner)
		{
			$ExpertModeBanner.Visibility = if ($Enabled) { 'Visible' } else { 'Collapsed' }
		}

		if (Get-Command -Name 'Update-WindowMinWidthFromHeader' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-WindowMinWidthFromHeader
		}
	}
