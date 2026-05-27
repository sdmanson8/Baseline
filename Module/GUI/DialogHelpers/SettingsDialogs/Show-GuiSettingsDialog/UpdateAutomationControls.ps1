$refreshUpdateAutomationControls = {
			$automationEnabled = (-not $chkAutoCheckUpdates) -or [bool]$chkAutoCheckUpdates.IsChecked
			foreach ($control in @($cmbUpdateFrequency, $cmbUpdateBranch, $chkIncludePrereleaseUpdates))
			{
				if ($control)
				{
					$control.IsEnabled = $automationEnabled
					$control.ToolTip = $settingsUpdatesAutomationHelper
				}
			}
			foreach ($label in @($dlg.FindName('LblUpdateFrequency'), $dlg.FindName('LblUpdateBranch'), $txtUpdatesAutomationHelper))
			{
				if ($label)
				{
					$label.Opacity = if ($automationEnabled) { 1.0 } else { 0.55 }
					$label.ToolTip = $settingsUpdatesAutomationHelper
				}
			}
		}.GetNewClosure()
		$refreshUpdateDisplay = {
			& $refreshUpdateAutomationControls
			if ($txtUpdateLastCheckedValue)
			{
				if (Get-Command -Name 'Format-BaselineUpdateLastChecked' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$txtUpdateLastCheckedValue.Text = Format-BaselineUpdateLastChecked -LastCheckedUtc $settingsUpdateState.LastCheckedUtc -NeverText $settingsUpdateNeverChecked
				}
				else
				{
					$txtUpdateLastCheckedValue.Text = $settingsUpdateNeverChecked
				}
			}
			if ($txtUpdateCurrentVersionValue) { $txtUpdateCurrentVersionValue.Text = $currentVersionText }
			if ($txtUpdateBranchValue) { $txtUpdateBranchValue.Text = ([string](& $getCurrentUpdateBranch)).ToLowerInvariant() }
			if ($txtUpdateStatusValue)
			{
				$rawStatus = if ($chkAutoCheckUpdates -and -not [bool]$chkAutoCheckUpdates.IsChecked) { 'Disabled' } else { [string]$settingsUpdateState.Status }
				$txtUpdateStatusValue.Text = & $getUpdateStatusDisplay $rawStatus
			}
		}.GetNewClosure()
