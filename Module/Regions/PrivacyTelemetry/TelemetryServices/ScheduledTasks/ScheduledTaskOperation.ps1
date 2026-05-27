function Invoke-ScheduledTasksOperation
	{
		param (
			[object[]]$TaskList
		)

		$ResolvedTaskList = @($TaskList | Where-Object { $_ })
		if ($ResolvedTaskList.Count -eq 0)
		{
			return
		}

		switch ($PSCmdlet.ParameterSetName)
		{
			"Enable"
			{
				$ResolvedTaskList | Enable-ScheduledTask
			}
			"Disable"
			{
				$ResolvedTaskList | Disable-ScheduledTask
			}
		}
	}

	<#
	    .SYNOPSIS
	    Runs check box select all click.

		#>

	function Invoke-TelemetryServiceSelectAllClick
	{
		$CheckBox = $_.Source

		if ($CheckBox.IsChecked)
		{
			$SelectedTasks.Clear()
			foreach ($Item in $PanelContainer.Children)
			{
				foreach ($Child in $Item.Children)
				{
					if ($Child -is [System.Windows.Controls.CheckBox])
					{
						$Child.IsChecked = $true
						[void]$SelectedTasks.Add($Child.Tag)
					}
				}
			}
		}
		else
		{
			$SelectedTasks.Clear()
			foreach ($Item in $PanelContainer.Children)
			{
				foreach ($Child in $Item.Children)
				{
					if ($Child -is [System.Windows.Controls.CheckBox])
					{
						$Child.IsChecked = $false
					}
				}
			}
		}

		if ($null -ne $Button)
		{
			$Button.IsEnabled = ($SelectedTasks.Count -gt 0)
		}
	}

	<#
	    .SYNOPSIS
	    Confirms scheduled tasks selection.

		#>

	function Confirm-ScheduledTasksSelection
	{
		$SelectedTaskList = @(Get-SelectedScheduledTaskList)
		$SelectionState.Confirmed = $true

		if ($CollectSelectionOnly)
		{
			$script:ScheduledTasksSelectionResult = [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedTaskNames = @(Get-SelectedScheduledTaskNames)
			}
			if ($null -ne $Window)
			{
				[void]$Window.Close()
			}
			return
		}

		foreach ($popupControl in @($Button, $CheckBoxSelectAll, $PanelContainer))
		{
			if ($null -ne $popupControl)
			{
				$popupControl.IsEnabled = $false
			}
		}

		$commandParameters = @{
			SelectedTaskNames = @(Get-SelectedScheduledTaskNames)
		}
		$commandParameters[$PSCmdlet.ParameterSetName] = $true

		if ($modulePath -and (Get-Command -Name 'Start-GuiPopupCommandAsync' -ErrorAction SilentlyContinue))
		{
			[void](GUICommon\Start-GuiPopupCommandAsync -Window $Form -ModulePath $modulePath -AdditionalModulePaths @($guiCommonPath) -CommandName 'ScheduledTasks' -CommandParameters $commandParameters)
			return
		}

		if ($null -ne $Window)
		{
			[void]$Window.Close()
		}

		Invoke-ScheduledTasksOperation -TaskList $SelectedTaskList
	}

	<#
	    .SYNOPSIS
	    Adds task control.

		#>

	function Add-TaskControl
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$Task
		)

		process
		{
			$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
			$CheckBox.Add_Click({Update-TelemetryServiceSelectionFromCheckbox -CheckBox $_.Source})
			$CheckBox.Tag = $Task

			$LabelPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$LabelPanel.Orientation = 'Horizontal'
			$LabelPanel.VerticalAlignment = 'Center'

			$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
			$TextBlock.Text = $Task.TaskName
			$TextBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			if ($Form -and $Form.Foreground) { $TextBlock.Foreground = $Form.Foreground }
			$TextBlock.VerticalAlignment = 'Center'
			[void]$LabelPanel.Children.Add($TextBlock)

			$tooltipText = if ([string]::IsNullOrWhiteSpace([string]$Task.TaskPath)) { [string]$Task.TaskName } else { "$($Task.TaskPath)$($Task.TaskName)" }
			$infoIcon = GUICommon\New-GuiPopupInfoIcon -TooltipText $tooltipText -Theme $Theme -UseDarkMode $UseDarkMode
			$infoPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$infoPanel.Orientation = 'Horizontal'
			$infoPanel.VerticalAlignment = 'Center'
			$infoPanel.HorizontalAlignment = 'Right'
			$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
			[void]$infoPanel.Children.Add($infoIcon)

			$rowPanel = New-Object -TypeName System.Windows.Controls.DockPanel
			$rowPanel.LastChildFill = $true
			$rowPanel.HorizontalAlignment = 'Stretch'
			$rowPanel.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)
			[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
			[void]$rowPanel.Children.Add($CheckBox)
			[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
			[void]$rowPanel.Children.Add($infoPanel)
			[void]$rowPanel.Children.Add($LabelPanel)
			[void]$PanelContainer.Children.Add($rowPanel)

			# If task checked add to the array list
			if (Test-ScheduledTaskSeedSelected -Task $Task)
			{
				[void]$SelectedTasks.Add($Task)
			}
			else
			{
				$CheckBox.IsChecked = $false
			}

			if ($null -ne $Button)
			{
				$Button.IsEnabled = ($SelectedTasks.Count -gt 0)
			}
		}
	}
	#endregion Functions

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			if (-not $CollectSelectionOnly)
			{
				Write-ConsoleStatus -Action "Enable Diagnostics Tracking Scheduled Tasks"
				LogInfo "Enabling Diagnostics Tracking Scheduled Tasks"
			}
			$State           = "Disabled"
			$ButtonContent   = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceEnable' -Fallback 'Enable'
		}
		"Disable"
		{
			if (-not $CollectSelectionOnly)
			{
				Write-ConsoleStatus -Action "Disable Diagnostics Tracking Scheduled Tasks"
				LogInfo "Disabling Diagnostics Tracking Scheduled Tasks"
			}
			$State           = "Ready"
			$ButtonContent   = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceDisable' -Fallback 'Disable'
		}
	}
