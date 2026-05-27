[string[]]$CheckedScheduledTasks = @(
		# Collects program telemetry information if opted-in to the Microsoft Customer Experience Improvement Program
		"MareBackup",

		# Collects program telemetry information if opted-in to the Microsoft Customer Experience Improvement Program
		"Microsoft Compatibility Appraiser",

		# Updates compatibility database
		"StartupAppTask",

		# This task collects and uploads autochk SQM data if opted-in to the Microsoft Customer Experience Improvement Program
		"Proxy",

		# If the user has consented to participate in the Windows Customer Experience Improvement Program, this job collects and sends usage data to Microsoft
		"Consolidator",

		# The USB CEIP (Customer Experience Improvement Program) task collects Universal Serial Bus related statistics and information about your machine and sends it to the Windows Device Connectivity engineering group at Microsoft
		"UsbCeip",

		# The Windows Disk Diagnostic reports general disk and system information to Microsoft for users participating in the Customer Experience Program
		"Microsoft-Windows-DiskDiagnosticDataCollector",

		# This task shows various Map related toasts
		"MapsToastTask",

		# This task checks for updates to maps which you have downloaded for offline use
		"MapsUpdateTask",

		# Initializes Family Safety monitoring and enforcement
		"FamilySafetyMonitor",

		# Synchronizes the latest settings with the Microsoft family features service
		"FamilySafetyRefreshTask",

		# XblGameSave Standby Task
		"XblGameSaveTask"
	)
	#endregion Variables

	#region Functions
	function Update-TelemetryServiceSelectionFromCheckbox
	{
			<#
			    .SYNOPSIS
			    Sync a task checkbox into the scheduled-task selection list.

			    .DESCRIPTION
			    Adds or removes the task stored in the checkbox Tag from the SelectedTasks collection based on the current check state.

			    .PARAMETER CheckBox
			    Checkbox control whose Tag contains the task payload.

			    .EXAMPLE
			    Update-TelemetryServiceSelectionFromCheckbox -CheckBox $checkBox
			#>
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$CheckBox
		)

		$Task = $CheckBox.Tag

		if ($CheckBox.IsChecked)
		{
			if ($null -ne $Task -and -not ($SelectedTasks | Where-Object -FilterScript {$_.TaskName -eq $Task.TaskName}))
			{
				[void]$SelectedTasks.Add($Task)
			}
		}
		else
		{
			if ($null -ne $Task)
			{
				$TaskToRemove = $SelectedTasks | Where-Object -FilterScript {$_.TaskName -eq $Task.TaskName} | Select-Object -First 1
				if ($null -ne $TaskToRemove)
				{
					[void]$SelectedTasks.Remove($TaskToRemove)
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
	    Checks scheduled task seed selected.

		#>

	function Test-ScheduledTaskSeedSelected
	{
		[CmdletBinding()]
		param
		(
			[Parameter(Mandatory = $true)]
			$Task
		)

		if ($SelectedTaskNamesProvided)
		{
			return [bool](@($SelectedTaskNames | Where-Object -FilterScript {$_ -eq $Task.TaskName}).Count -gt 0)
		}

		return [bool](@($CheckedScheduledTasks | Where-Object -FilterScript {$Task.TaskName -match $_}).Count -gt 0)
	}
