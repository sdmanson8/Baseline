
	. (Join-Path $Script:GuiExtractedRoot 'TweakVisualization.ps1')

		    # Scriptblock stored in Script: scope so all closures and timer ticks can access it directly.
    # Simple: takes completed count, total count, and what's currently running.
    $Script:UpdateProgressFn = {
        param (
            [int]$Completed,
            [int]$Total,
            [string]$CurrentAction,
            [int]$SubCompleted = -1,
            [int]$SubTotal = 0,
            [string]$SubAction = $null,
            [switch]$ClearSub
        )

        if ($Script:ExecutionProgressBar -or $Script:ExecutionProgressText)
        {
            $Script:ExecutionProgressIndeterminate = ($Total -le 0)
            if ($Script:ExecutionProgressIndeterminate)
            {
                $Script:ExecutionLastProgressCompleted = -1
            }
            elseif ($null -ne $Script:ExecutionLastProgressCompleted -and $Completed -lt [int]$Script:ExecutionLastProgressCompleted)
            {
                return
            }
            else
            {
                $Script:ExecutionLastProgressCompleted = $Completed
            }
            Set-SharedProgressBarState -ProgressBar $Script:ExecutionProgressBar -ProgressText $Script:ExecutionProgressText -Completed $Completed -Total $Total -CurrentAction $CurrentAction -Indeterminate:($Script:ExecutionProgressIndeterminate)
        }

		# Sub-progress bar (downloads, installs, etc. reported by tweak functions)
		if ($Script:ExecutionSubProgressBar)
		{
			if ($ClearSub)
			{
				$Script:ExecutionSubProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
				if ($Script:ExecutionSubProgressText) { $Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Collapsed }
			}
			elseif ($SubTotal -gt 0)
			{
				$Script:ExecutionSubProgressBar.Visibility  = [System.Windows.Visibility]::Visible
				$Script:ExecutionSubProgressBar.Maximum     = $SubTotal
				$Script:ExecutionSubProgressBar.Value       = [Math]::Min($SubCompleted, $SubTotal)
				$Script:ExecutionSubProgressBar.IsIndeterminate = $false
				if ($Script:ExecutionSubProgressText)
				{
					$Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Visible
					$pct = [Math]::Round(($SubCompleted / $SubTotal) * 100)
					$Script:ExecutionSubProgressText.Text = if ($SubAction) { "$SubAction  ($pct%)" } else { "$pct%" }
				}
			}
			elseif ($SubCompleted -ge 0 -and $SubTotal -le 0)
			{
				# Unknown total - show indeterminate sub-bar
				$Script:ExecutionSubProgressBar.Visibility = [System.Windows.Visibility]::Visible
				$Script:ExecutionSubProgressBar.IsIndeterminate = $true
				if ($Script:ExecutionSubProgressText)
				{
					$Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Visible
					$Script:ExecutionSubProgressText.Text = if ($SubAction) { $SubAction } else { Get-UxExecutionPlaceholderText -Kind 'Working' }
				}
			}
		}

		# Sync observable state for progress subscribers
		if ($Script:GuiState -and $Total -gt 0)
		{
			& $Script:GuiState.SetBatch @{
				ProgressCompleted = $Completed
				ProgressTotal     = $Total
				ProgressAction    = $CurrentAction
			}
		}
	}

		<#
		    .SYNOPSIS
		#>

		function Invoke-GuiEvents
		{
			$frame = New-Object System.Windows.Threading.DispatcherFrame
			$scheduled = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'Pump' -Action {
				$frame.Continue = $false
			}
			if ($scheduled)
			{
				[System.Windows.Threading.Dispatcher]::PushFrame($frame)
			}
		}

		function Close-GuiMainWindow
		{
			param (
				[string]$Reason = 'GUI close requested.'
			)

			Write-Host ("[Close-GuiMainWindow] {0}" -f $Reason)
			if ($Script:MainForm)
			{
				try { $Script:MainForm.Close() } catch { Write-GuiRuntimeWarning -Context 'Close-GuiMainWindow' -Message ("Failed to close main form: {0}" -f $_.Exception.Message) }
			}
		}

		$Script:ForceCloseExecutionFn = {
			Set-RunAbortDisposition -Disposition 'Exit'
			$timerToStop = $Script:ExecutionRunTimer
			$workerToStop = $Script:ExecutionWorker

			Clear-UILogHandler
			Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue

			if ($Script:RunState)
			{
				$Script:RunState['AbortRequested'] = $true
				$Script:RunState['AbortRequestedAt'] = Get-Date
				$Script:RunState['AbortedRun'] = $true
				$Script:RunState['Done'] = $true
			}

			if ($timerToStop)
			{
				try { $timerToStop.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyledControlsSetup.ForceCloseExecutionFn.TimerStop' }
			}

			$Script:SuppressRunClosePrompt = $true

			if ($workerToStop)
			{
				GUIExecution\Stop-GuiExecutionWorkerAsync -Worker $workerToStop
			}

			$Script:ExecutionRunTimer = $null
			$Script:ExecutionWorker = $null
			$Script:ExecutionRunPowerShell = $null
			$Script:ExecutionRunspace = $null
			$Script:BgPS = $null
			$Script:BgAsync = $null
			$Script:RunInProgress = $false

			if ($Script:GuiResponsivenessWatchdog)
			{
				$watchdogToStop = $Script:GuiResponsivenessWatchdog
				$Script:GuiResponsivenessWatchdog = $null
				try { Stop-GuiResponsivenessWatchdog -Watchdog $watchdogToStop } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyledControlsSetup.ForceCloseExecutionFn.StopResponsivenessWatchdog' }
			}

			if ($Script:MainForm)
			{
				try
				{
					$null = Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -PriorityUsage 'Immediate' -Action {
	                try { Close-GuiMainWindow -Reason 'ForceCloseExecutionFn requested immediate exit.' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyledControlsSetup.ForceCloseExecutionFn.CloseMainWindow' }
	                try
	                {
	                        if ([System.Windows.Application]::Current)
                        {
                                [System.Windows.Application]::Current.Shutdown()
                        }
                }
                catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyledControlsSetup.ForceCloseExecutionFn.ShutdownApplication' }
	        }
				}
				catch
				{
					try { Close-GuiMainWindow -Reason 'ForceCloseExecutionFn fallback close.' } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyledControlsSetup.ForceCloseExecutionFn.FallbackCloseMainWindow' }
				}
			}

		$Script:ForceCloseCompleted = $true
	}

		$Script:RequestRunAbortFn = {
			param(
				[switch]$ExitNow
			)

			if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

			if ($ExitNow)
			{
				Set-RunAbortDisposition -Disposition 'Exit'
			}
			elseif ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition))
			{
				Set-RunAbortDisposition -Disposition 'Return'
			}

			$Script:AbortRequested = $true
			if ($Script:AbortRunButton)
			{
				$Script:AbortRunButton.Content = (Get-UxLocalizedString -Key 'GuiStatusAborting' -Fallback 'Aborting...')
				$Script:AbortRunButton.IsEnabled = $false
			}
			if ($BtnRun)
			{
				$BtnRun.Content = if ($ExitNow) { (Get-UxLocalizedString -Key 'GuiStatusExiting' -Fallback 'Exiting...') } else { (Get-UxLocalizedString -Key 'GuiStatusStopping' -Fallback 'Stopping...') }
				$BtnRun.IsEnabled = $false
			}
			Set-GuiStatusText -Text $(if ($ExitNow) { (Get-UxLocalizedString -Key 'GuiStatusExitRequested' -Fallback '') } else { (Get-UxLocalizedString -Key 'GuiStatusAbortRequested' -Fallback '') }) -Tone 'caution'
			LogWarning (Get-UxBilingualLocalizedString -Key 'GuiLogAbortRequestedByUser' -Fallback 'Abort requested by user - stopping the current operation now.')

		if ($Script:RunState)
		{
			$Script:RunState['AbortRequested'] = $true
			$Script:RunState['AbortRequestedAt'] = Get-Date
			$Script:RunState['AbortedRun'] = $true
			$Script:RunState['Paused'] = $true
		}

			if ($Script:ExecutionPumpTickFn)
			{
				try
				{
					& $Script:ExecutionPumpTickFn
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'StyledControls.RequestRunAbort.PumpTick'
				}
			}

			if ($ExitNow)
			{
				LogWarning (Get-UxBilingualLocalizedString -Key 'GuiLogExitRequestedByUser' -Fallback 'Exit requested by user - closing Baseline now.')
				& $Script:ForceCloseExecutionFn
				return
			}
	}

	$Script:PromptRunAbortFn = {
		if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

		$abortPromptPausedRun = $false
		$abortPromptPreviousPaused = $false
		if ($Script:RunState)
		{
			$abortPromptPreviousPaused = [bool]$Script:RunState['Paused']
			$Script:RunState['Paused'] = $true
			$abortPromptPausedRun = $true
		}

		$Script:AbortDialogShowing = $true
		try
		{
			$abortTitle = Get-UxLocalizedString -Key 'GuiAbortRunTitle' -Fallback 'Abort Run'
			$abortQuestion = Get-UxLocalizedString -Key 'GuiAbortRunQuestion' -Fallback 'Stop the current run now?'
			$abortDetail = Get-UxLocalizedString -Key 'GuiAbortRunDetail' -Fallback 'Return to Tweaks aborts the run and keeps the app open. Exit Now force-stops the run and closes Baseline immediately.'
			$abortBtnReturn = Get-UxLocalizedString -Key 'GuiAbortReturnToTweaks' -Fallback 'Return to Tweaks'
			$abortBtnExit = Get-UxLocalizedString -Key 'GuiAbortExitNow' -Fallback 'Exit Now'
			$abortBtnCancel = Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel'
			$choice = Show-ThemedDialog -Title $abortTitle `
			-Message "$abortQuestion`n`n$abortDetail" `
			-Buttons @($abortBtnReturn, $abortBtnExit, $abortBtnCancel) `
			-AccentButton $abortBtnReturn `
			-DestructiveButton $abortBtnExit
			Write-Host ("Abort dialog choice: '{0}'" -f $(if ($null -eq $choice) { '<null>' } else { [string]$choice }))
		}
		finally
		{
			$Script:AbortDialogShowing = $false
		}

		if (-not $Script:RunInProgress)
		{
			# Run completed while the dialog was open - nothing to abort
			return
		}

			switch ($choice)
			{
				{ $_ -eq $abortBtnReturn }
				{
					Set-RunAbortDisposition -Disposition 'Return'
					& $Script:RequestRunAbortFn
				}
				{ $_ -eq $abortBtnExit }
				{
					Set-RunAbortDisposition -Disposition 'Exit'
					& $Script:RequestRunAbortFn -ExitNow
				}
				default
				{
					if ($abortPromptPausedRun -and $Script:RunState -and -not $Script:AbortRequested)
					{
						$Script:RunState['Paused'] = $abortPromptPreviousPaused
					}
					Set-RunAbortDisposition -Disposition $null
				}
			}
		}
