# Execution lifecycle orchestration: abort, view transitions, rollback, run setup, completion

	function Set-RunAbortDisposition
	{
		param (
			[string]$Disposition = $null
		)

		$resolvedDisposition = if ([string]::IsNullOrWhiteSpace([string]$Disposition))
		{
			$null
		}
		else
		{
			[string]$Disposition.Trim()
		}

		$Script:RunAbortDisposition = $resolvedDisposition
		if ($Script:RunState)
		{
			$Script:RunState['AbortDisposition'] = $resolvedDisposition
		}
	}

	function Get-RunAbortDisposition
	{
		$stateDisposition = $null
		if ($Script:RunState -and $Script:RunState.ContainsKey('AbortDisposition'))
		{
			$stateDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunState['AbortDisposition']))
			{
				$null
			}
			else
			{
				[string]$Script:RunState['AbortDisposition']
			}
		}

		$scriptDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition))
		{
			$null
		}
		else
		{
			[string]$Script:RunAbortDisposition
		}

		$resolvedDisposition = if (-not [string]::IsNullOrWhiteSpace([string]$stateDisposition))
		{
			$stateDisposition
		}
		else
		{
			$scriptDisposition
		}

		if ([string]::IsNullOrWhiteSpace([string]$resolvedDisposition))
		{
			return 'Return'
		}

		return [string]$resolvedDisposition
	}

	function Reset-RunAbortState
	{
		$Script:AbortRequested = $false
		Set-RunAbortDisposition -Disposition $null
	}

	function Build-WhatChangedSummaryText
	{
		<#
		.SYNOPSIS
			Builds the "What happened" summary string from execution insight counts.
		.DESCRIPTION
			Shared helper that eliminates duplicated whatChangedText construction
			between the Defaults-mode and standard/GameMode completion paths.
		#>
		param (
			[string]$OpeningLine,
			[string]$Noun,
			[object]$Insights,
			[int]$RestartPendingCount,
			[int]$NotRunCount,
			[string]$AlreadyDesiredPhrase,
			[string]$RestartPendingPhrase,
			[string]$NotApplicableSingularPhrase,
			[string]$NotApplicablePluralPhrase,
			[string]$PolicySkippedSingularPhrase,
			[string]$PolicySkippedPluralPhrase,
			[string]$RecoverableSingularPhrase = ' qualifies for a safe retry',
			[string]$RecoverablePluralPhrase = 's qualify for a safe retry',
			[string]$ManualSingularPhrase = ' still needs manual review',
			[string]$ManualPluralPhrase = 's still need manual review'
		)

		$text = $OpeningLine
		if ($Insights.AlreadyDesiredCount -gt 0)
		{
			$text += " $($Insights.AlreadyDesiredCount) $Noun$(if ($Insights.AlreadyDesiredCount -eq 1) { '' } else { 's' }) $AlreadyDesiredPhrase."
		}
		if ($RestartPendingCount -gt 0)
		{
			$text += " $RestartPendingCount $Noun$(if ($RestartPendingCount -eq 1) { '' } else { 's' }) $RestartPendingPhrase."
		}
		if ($Insights.NotApplicableCount -gt 0)
		{
			$text += " $($Insights.NotApplicableCount) $Noun$(if ($Insights.NotApplicableCount -eq 1) { $NotApplicableSingularPhrase } else { $NotApplicablePluralPhrase })."
		}
		if ($Insights.PolicySkippedCount -gt 0)
		{
			$text += " $($Insights.PolicySkippedCount) $Noun$(if ($Insights.PolicySkippedCount -eq 1) { $PolicySkippedSingularPhrase } else { $PolicySkippedPluralPhrase })."
		}
		if ($Insights.RecoverableFailedCount -gt 0)
		{
			$text += " $($Insights.RecoverableFailedCount) $Noun$(if ($Insights.RecoverableFailedCount -eq 1) { $RecoverableSingularPhrase } else { $RecoverablePluralPhrase })."
		}
		if ($Insights.ManualFailedCount -gt 0)
		{
			$text += " $($Insights.ManualFailedCount) $Noun$(if ($Insights.ManualFailedCount -eq 1) { $ManualSingularPhrase } else { $ManualPluralPhrase })."
		}
		if ($NotRunCount -gt 0)
		{
			$text += " $NotRunCount $Noun$(if ($NotRunCount -eq 1) { '' } else { 's' }) did not run."
		}
		return $text
	}

	function New-ExecutionViewHeader
	{
		param (
			[Parameter(Mandatory = $true)][string]$Title,
			[Parameter(Mandatory = $true)]$BrushConverter
		)

		$panel = New-Object System.Windows.Controls.StackPanel
		$panel.Orientation = 'Vertical'

		$heading = New-Object System.Windows.Controls.TextBlock
		$heading.Text = $Title
		$heading.FontSize = $Script:GuiLayout.FontSizeHeading
		$heading.FontWeight = [System.Windows.FontWeights]::Bold
		$heading.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$heading.Margin = [System.Windows.Thickness]::new(0,0,0,6)
		[void]($panel.Children.Add($heading))

		$subheading = New-Object System.Windows.Controls.TextBlock
		$subheading.Text = Get-UxLocalizedString -Key 'GuiExecutionSubheading' -Fallback 'Progress will appear here live. Please keep this window open until completion.'
		$subheading.FontSize = $Script:GuiLayout.FontSizeSubheading
		$subheading.TextWrapping = 'Wrap'
		$subheading.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$subheading.Margin = [System.Windows.Thickness]::new(0,0,0,12)
		[void]($panel.Children.Add($subheading))

		return $panel
	}

	function New-ExecutionViewProgressSection
	{
		param (
			[Parameter(Mandatory = $true)]$BrushConverter
		)

		$progressGrid = New-Object System.Windows.Controls.Grid
		$progressGrid.Margin = [System.Windows.Thickness]::new(0,0,0,12)
		$progressCol1 = New-Object System.Windows.Controls.ColumnDefinition
		$progressCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		$progressCol2 = New-Object System.Windows.Controls.ColumnDefinition
		$progressCol2.Width = [System.Windows.GridLength]::new($Script:GuiLayout.ProgressColumnWidth, [System.Windows.GridUnitType]::Pixel)
		[void]($progressGrid.ColumnDefinitions.Add($progressCol1))
		[void]($progressGrid.ColumnDefinitions.Add($progressCol2))

		$progressStack = New-Object System.Windows.Controls.StackPanel
		$progressStack.Orientation = 'Vertical'
		$progressStack.Margin = [System.Windows.Thickness]::new(0,0,12,0)
		[System.Windows.Controls.Grid]::SetColumn($progressStack, 0)

		$progressBar = New-Object System.Windows.Controls.ProgressBar
		$progressBar.Minimum = 0
		$progressBar.Maximum = 1
		$progressBar.Value = 0
		$progressBar.Height = $Script:GuiLayout.ProgressBarHeight
		$progressBar.MinWidth = $Script:GuiLayout.ProgressBarMinWidth
		$progressBar.IsIndeterminate = $false
		$progressBar.Margin = [System.Windows.Thickness]::new(0,0,0,6)
		$progressBar.HorizontalAlignment = 'Stretch'
		[void]($progressStack.Children.Add($progressBar))

		$progressText = New-Object System.Windows.Controls.TextBlock
		$progressText.FontSize = $Script:GuiLayout.FontSizeSubheading
		$progressText.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$progressText.Text = Get-UxExecutionPlaceholderText -Kind 'Preparing'
		$progressText.TextWrapping = 'NoWrap'
		$progressText.TextTrimming = 'CharacterEllipsis'
		$progressText.HorizontalAlignment = 'Stretch'
		[void]($progressStack.Children.Add($progressText))
		[void]($progressGrid.Children.Add($progressStack))

		$abortBtnHost = New-Object System.Windows.Controls.Border
		$abortBtnHost.Padding = [System.Windows.Thickness]::new(0)
		$abortBtnHost.HorizontalAlignment = 'Right'
		$abortBtnHost.VerticalAlignment = 'Top'
		[System.Windows.Controls.Grid]::SetColumn($abortBtnHost, 1)

		$abortBtn = New-Object System.Windows.Controls.Button
		$abortBtn.Content = Get-UxLocalizedString -Key 'GuiAbortButton' -Fallback 'Abort'
		$abortBtn.MinWidth = $Script:GuiLayout.ButtonAbortMinWidth
		$abortBtn.Height = $Script:GuiLayout.ButtonLargeHeight
		$abortBtn.Padding = [System.Windows.Thickness]::new(18,8,18,8)
		$abortBtn.HorizontalAlignment = 'Stretch'
		$abortBtn.VerticalAlignment = 'Top'
		$abortBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		$abortBtn.TabIndex = 0
		Register-GuiEventHandler -Source $abortBtn -EventName 'Click' -Handler { & $Script:PromptRunAbortFn }
		Set-ButtonChrome -Button $abortBtn -Variant 'Danger'
		$abortBtnHost.Child = $abortBtn
		[void]($progressGrid.Children.Add($abortBtnHost))

		return @{
			Grid        = $progressGrid
			ProgressBar = $progressBar
			ProgressText = $progressText
			AbortButton = $abortBtn
		}
	}

	function New-ExecutionViewLogBox
	{
		param (
			[Parameter(Mandatory = $true)]$BrushConverter
		)

		$logBox = New-Object System.Windows.Controls.RichTextBox
		$logBox.IsReadOnly = $true
		$logBox.VerticalScrollBarVisibility = 'Auto'
		$logBox.HorizontalScrollBarVisibility = 'Disabled'
		$logBox.BorderThickness = [System.Windows.Thickness]::new(0)
		$logBox.Padding = [System.Windows.Thickness]::new(12)
		$logBox.Background = $BrushConverter.ConvertFromString($Script:CurrentTheme.CardBg)
		$logBox.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$logBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
		$logBox.FontSize = $Script:GuiLayout.FontSizeSubheading
		$logBox.TabIndex = 1
		$flowDoc = New-Object System.Windows.Documents.FlowDocument
		$flowDoc.PagePadding = [System.Windows.Thickness]::new(0)
		$flowDoc.LineHeight = 1
		$logBox.Document = $flowDoc

		return $logBox
	}

	function Enter-ExecutionView
	{
		param ([string]$Title)

		$bc = New-SafeBrushConverter -Context 'Enter-ExecutionView'
		$Script:ExecutionPreviousContent = $ContentScroll.Content
		$Script:ExecutionPreviousScrollMode = $ContentScroll.VerticalScrollBarVisibility

		# Build the outer grid: header row (auto) + log row (fill)
		$outerGrid = New-Object System.Windows.Controls.Grid
		$outerGrid.Margin = [System.Windows.Thickness]::new(12)
		$rowHeader = New-Object System.Windows.Controls.RowDefinition
		$rowHeader.Height = [System.Windows.GridLength]::Auto
		$rowLog = New-Object System.Windows.Controls.RowDefinition
		$rowLog.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		[void]($outerGrid.RowDefinitions.Add($rowHeader))
		[void]($outerGrid.RowDefinitions.Add($rowLog))

		# Top section: heading + subheading + progress bar + abort button
		$topPanel = New-ExecutionViewHeader -Title $Title -BrushConverter $bc
		$progressSection = New-ExecutionViewProgressSection -BrushConverter $bc
		[void]($topPanel.Children.Add($progressSection.Grid))
		[System.Windows.Controls.Grid]::SetRow($topPanel, 0)
		[void]($outerGrid.Children.Add($topPanel))

		# Bottom section: scrollable rich log box
		$logBox = New-ExecutionViewLogBox -BrushConverter $bc
		[System.Windows.Controls.Grid]::SetRow($logBox, 1)
		[void]($outerGrid.Children.Add($logBox))

		# Swap content and assign execution state
		$ContentScroll.VerticalScrollBarVisibility = 'Disabled'
		$ContentScroll.Content = $outerGrid
		$Script:ExecutionLogBox = $logBox
		$Script:ExecutionLastConsoleAction = $null
		$Script:ExecutionProgressBar = $progressSection.ProgressBar
		$Script:ExecutionProgressText = $progressSection.ProgressText
		$Script:AbortRunButton = $progressSection.AbortButton
		Reset-RunAbortState
		$Script:ExecutionWorker = $null
		$Script:ExecutionRunspace = $null
		$Script:ExecutionRunPowerShell = $null
		$Script:ExecutionRunTimer = $null
		$Script:ExecutionTimerErrorShown = $false
		$Script:SuppressRunClosePrompt = $false
		$Script:BgPS = $null
		$Script:BgAsync = $null

		# Hide filter bar, tab bar, and expert-mode banner during execution
		$PrimaryTabs.Visibility = [System.Windows.Visibility]::Collapsed
		$HeaderBorder.Visibility = [System.Windows.Visibility]::Collapsed
		if ($ExpertModeBanner) { $ExpertModeBanner.Visibility = [System.Windows.Visibility]::Collapsed }
		# Hide bottom action buttons during execution
		if ($ActionButtonBar) { $ActionButtonBar.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($StatusText) { $StatusText.Visibility = [System.Windows.Visibility]::Collapsed }
		[void]($progressSection.AbortButton.Focus())
	}

	    function Exit-ExecutionView
	    {
			LogInfo "[Exit-ExecutionView] ENTERED - restoring GUI"
			$deferAbortReset = ($Script:AbortRequested -and (Get-RunAbortDisposition) -eq 'Return')
			$savedPreviousContent = $Script:ExecutionPreviousContent
	        $Script:ExecutionLogBox = $null
	        $Script:ExecutionLastConsoleAction = $null
	        $Script:ExecutionProgressBar = $null
	        $Script:ExecutionProgressText = $null
	        $Script:AbortRunButton = $null
	        $Script:ExecutionWorker = $null
        $Script:ExecutionRunspace = $null
        $Script:ExecutionRunPowerShell = $null
        $Script:ExecutionRunTimer = $null
        $Script:ExecutionTimerErrorShown = $false
	        $Script:BgPS = $null
	        $Script:BgAsync = $null
	        $Script:ExecutionPreviousContent = $null
	        $Script:ExecutionCurrentSummaryKey = $null
	        $Script:ExecutionMode = $null

	        # Restore the outer ScrollViewer scrolling mode
	        $ContentScroll.VerticalScrollBarVisibility = 'Auto'

        # Reset run state
        if ($Script:GuiState) { & $Script:GuiState.Set 'RunInProgress' $false } else { $Script:RunInProgress = $false }

        # Restore filter bar, tab bar, and expert-mode banner
        $PrimaryTabs.Visibility = [System.Windows.Visibility]::Visible
        $PrimaryTabs.IsEnabled = $true
        $HeaderBorder.Visibility = [System.Windows.Visibility]::Visible
        if ($ExpertModeBanner -and (Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-IsExpertModeUX))
        {
            $ExpertModeBanner.Visibility = [System.Windows.Visibility]::Visible
        }
        # Restore bottom action buttons
        if ($ActionButtonBar) { $ActionButtonBar.Visibility = [System.Windows.Visibility]::Visible }
        if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = [System.Windows.Visibility]::Visible; $BtnPreviewRun.IsEnabled = $true }
        if ($StatusText) { $StatusText.Visibility = [System.Windows.Visibility]::Visible }
        # Re-enable controls
        if ($BtnRun) { $BtnRun.Content = Get-UxRunActionLabel; $BtnRun.IsEnabled = $true }
        if ($BtnDefaults) { $BtnDefaults.IsEnabled = $true }
        Set-GuiActionButtonsEnabled -Enabled $true
        if ($ChkScan) { $ChkScan.IsEnabled = $true }
        if ($ChkTheme) { $ChkTheme.IsEnabled = $true }
        Set-SearchControlsEnabled -Enabled $true

        if ($Script:CurrentPrimaryTab)
        {
            try
            {
                Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
            }
            catch
            {
                LogError "[Exit-ExecutionView] Build-TabContent failed: $($_.Exception.Message)"
                if ($savedPreviousContent)
                {
                    $ContentScroll.Content = $savedPreviousContent
                }
            }
        }
        elseif ($savedPreviousContent)
        {
            $ContentScroll.Content = $savedPreviousContent
        }

			if ($deferAbortReset -and $Script:MainForm -and $Script:MainForm.Dispatcher)
			{
				try
				{
					$null = Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -PriorityUsage 'Pump' -Action {
						try { Reset-RunAbortState } catch { $null = $_ }
					}
				}
				catch
				{
					Reset-RunAbortState
				}
			}
			else
			{
				Reset-RunAbortState
			}

		LogInfo "[Exit-ExecutionView] COMPLETED - GUI restored"
    }

	function Copy-ExecutionTweakExtraArgs
	{
		param (
			$ExtraArgs
		)

		$copy = @{}
		if ($null -eq $ExtraArgs)
		{
			return $copy
		}

		if ($ExtraArgs -is [System.Collections.IDictionary])
		{
			foreach ($entry in $ExtraArgs.GetEnumerator())
			{
				$copy[[string]$entry.Key] = $entry.Value
			}
			return $copy
		}

		foreach ($property in $ExtraArgs.PSObject.Properties)
		{
			$copy[[string]$property.Name] = $property.Value
		}

		return $copy
	}

	function Resolve-InteractiveRunSelections
	{
		param (
			[object[]]$TweakList
		)

		$tweaks = @($TweakList | Where-Object { $_ })
		if ($tweaks.Count -eq 0)
		{
			return @()
		}

		$resolvedTweaks = [System.Collections.Generic.List[object]]::new()

		function New-ResolvedExecutionTweak
		{
			param (
				[Parameter(Mandatory = $true)]
				$SourceTweak,

				[Parameter(Mandatory = $true)]
				[hashtable]$ResolvedExtraArgs,

				[Parameter(Mandatory = $true)]
				[string]$SelectionLabel
			)

			if ($SourceTweak -is [System.Collections.IDictionary])
			{
				$resolvedTweak = @{}
				foreach ($entry in $SourceTweak.GetEnumerator())
				{
					$resolvedTweak[[string]$entry.Key] = $entry.Value
				}
				$resolvedTweak['ExtraArgs'] = $ResolvedExtraArgs
				$resolvedTweak['Selection'] = $SelectionLabel
				return $resolvedTweak
			}

			$resolvedTweak = [ordered]@{}
			foreach ($property in $SourceTweak.PSObject.Properties)
			{
				$resolvedTweak[[string]$property.Name] = $property.Value
			}
			$resolvedTweak['ExtraArgs'] = $ResolvedExtraArgs
			$resolvedTweak['Selection'] = $SelectionLabel
			return [pscustomobject]$resolvedTweak
		}

		foreach ($tweak in $tweaks)
		{
			[void]$resolvedTweaks.Add($tweak)
		}

		return @($resolvedTweaks)
	}

	function Get-ExecutionRollbackCommandList
	{
		param ([object[]]$Results)

		$commands = [System.Collections.Generic.List[string]]::new()
		$seenCommands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach ($result in @($Results | Where-Object { $_.Status -in @('Success', 'Restart pending') }))
		{
			$manifestEntry = Get-ManifestEntryByFunction -Manifest $Script:TweakManifest -Function ([string]$result.Function)
			if (-not $manifestEntry) { continue }

			$undoParam = Get-DirectUndoCommandForEntry -Entry $result -ManifestEntry $manifestEntry
			if ([string]::IsNullOrWhiteSpace([string]$undoParam)) { continue }

			$commandLine = '{0} -{1}' -f [string]$result.Function, [string]$undoParam
			if ($seenCommands.Add($commandLine))
			{
				[void]$commands.Add($commandLine)
			}
		}

		return @($commands)
	}

	function Export-ExecutionRollbackProfile
	{
		param (
			[Parameter(Mandatory = $true)][string]$FilePath,
			[object[]]$Results,
			[string]$Mode = 'Run',
			[string]$ProfileName = 'Rollback'
		)

		$rollbackCommands = @(Get-ExecutionRollbackCommandList -Results $Results)
		if ($rollbackCommands.Count -eq 0)
		{
			throw 'No directly undoable changes were available to export.'
		}

		$payload = [ordered]@{
			Schema = 'Baseline.RollbackProfile'
			SchemaVersion = 1
			Name = $ProfileName
			ExportedAt = (Get-Date).ToString('o')
			SourceMode = $Mode
			Entries = @($rollbackCommands)
		}

		[System.IO.File]::WriteAllText($FilePath, ($payload | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
		LogInfo ("Exported rollback profile with {0} command(s): {1}" -f $rollbackCommands.Count, $FilePath)
		return $rollbackCommands.Count
	}

	function Complete-GuiExecutionRun
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[int]$CompletedCount,
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null,
			[object[]]$ExecutionSummary,
			[string]$LogPath
		)

		$executionSummary = @($ExecutionSummary)
		$gameModeContext = Get-ExecutionGameModeContext
		$summaryPayload = GUIExecution\Get-GuiExecutionSummaryPayload -Results $executionSummary
		if ($Script:RunState)
		{
			$Script:RunState['SummaryPayload'] = $summaryPayload
		}
		$restartPendingCount = $summaryPayload.RestartPendingCount
		$appliedCount = $summaryPayload.AppliedCount
		$failedCount = $summaryPayload.FailedCount
		$skippedCount = $summaryPayload.SkippedCount
		$notApplicableCount = $summaryPayload.NotApplicableCount
		$notRunCount = $summaryPayload.NotRunCount
		# Use summary-derived processed count instead of RunState counter to avoid
		# mismatches when drain queue entries fail to update CompletedCount.
		$CompletedCount = $summaryPayload.TotalCount - $notRunCount
		$recoverableFailedResults = @($executionSummary | Where-Object {
			[string]$_.Status -eq 'Failed' -and (Test-GuiObjectField -Object $_ -FieldName 'IsRecoverable') -and [bool]$_.IsRecoverable
		})
		$executionInsights = Get-ExecutionSummaryInsights -Results $executionSummary -FatalError $FatalError
		$summaryCountsText = Get-ExecutionSummaryCountsText -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
		$summaryNextStepsText = Get-ExecutionSummaryNextStepsText -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
		$summaryCards = Get-ExecutionSummaryDialogCards -Mode $Mode -SummaryPayload $summaryPayload -Insights $executionInsights
		$shouldOfferLogReview = [bool]$executionInsights.NeedsLogReview
		$displayLogPath = if ($shouldOfferLogReview) { $LogPath } else { $null }

		if ($Mode -eq 'Defaults')
		{
			Sync-DefaultsControlsFromExecutionSummary -Results $executionSummary
			if ($Script:CurrentPrimaryTab)
			{
				Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
			}

			$finalLabel = if ($AbortedRun) { 'Aborted' } elseif ($FatalError) { 'Failed' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { 'Partially Complete' } else { 'Done' }
			& $Script:UpdateProgressFn -Completed $CompletedCount -Total $Script:TotalRunnableTweaks -CurrentAction $finalLabel

			if ($AbortedRun)
			{
				$rawRunAbortDisposition = if ($null -eq $Script:RunAbortDisposition) { '<null>' } else { [string]$Script:RunAbortDisposition }
				$runAbortDisposition = Get-RunAbortDisposition
				LogInfo ("[Complete-Defaults] AbortedRun=true, RunAbortDisposition={0}, EffectiveDisposition={1}" -f $rawRunAbortDisposition, $runAbortDisposition)
				Set-GuiStatusText -Text "Windows defaults restore aborted. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText" -Tone 'caution'

				if ($runAbortDisposition -eq 'Exit')
				{
					Close-GuiMainWindow -Reason 'Defaults restore abort disposition requested exit.'
				}
				else
				{
					Set-RunAbortDisposition -Disposition 'Return'
					Exit-ExecutionView
				}
				return
			}

			if ($FatalError)
			{
				Set-GuiStatusText -Text "Windows defaults restore failed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Open the summary for next steps." -Tone 'caution'
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
			{
				Set-GuiStatusText -Text "Windows defaults restore partially completed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Open the summary for next steps." -Tone 'caution'
			}
			elseif ($restartPendingCount -gt 0)
			{
				Set-GuiStatusText -Text "Windows defaults restored. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Restart required to finish restoring some items." -Tone 'danger'
			}
			else
			{
				Set-GuiStatusText -Text "Windows defaults restored. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText" -Tone 'success'
			}

			$dlgTitle = if ($FatalError) { 'Defaults Restore Failed' } elseif ($restartPendingCount -gt 0 -and $failedCount -eq 0 -and $notRunCount -eq 0) { 'Defaults Restore Restart Pending' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { 'Defaults Restore Partially Completed' } else { 'Defaults Restore Complete' }
			$whatChangedText = Build-WhatChangedSummaryText `
				-OpeningLine "What happened: $appliedCount item$(if ($appliedCount -eq 1) { '' } else { 's' }) restored to Windows defaults." `
				-Noun 'item' `
				-Insights $executionInsights `
				-RestartPendingCount $restartPendingCount `
				-NotRunCount $notRunCount `
				-AlreadyDesiredPhrase 'already matched the Windows default' `
				-RestartPendingPhrase 'still need a restart to finish restoring' `
				-NotApplicableSingularPhrase ' does not apply on this PC or this version of Windows' `
				-NotApplicablePluralPhrase 's do not apply on this PC or this version of Windows' `
				-PolicySkippedSingularPhrase ' is not supported by in-app restore' `
				-PolicySkippedPluralPhrase 's are not supported by in-app restore' `
				-RecoverableSingularPhrase ' qualifies for a safe restore retry' `
				-RecoverablePluralPhrase 's qualify for a safe restore retry' `
				-ManualSingularPhrase ' still needs manual follow-up' `
				-ManualPluralPhrase 's still need manual follow-up'
			$dlgMessage = if ($FatalError) {
				"$whatChangedText`n`nThe defaults restore stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
			}
			elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				"$whatChangedText`n`nWindows defaults restore partially completed.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			else {
				"$whatChangedText`n`nWindows defaults restored successfully.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$summaryNextStepsText))
			{
				$dlgMessage += "`n`nNext steps: $summaryNextStepsText"
			}
			$summaryButtons = @()
			if ($recoverableFailedResults.Count -gt 0) { $summaryButtons += 'Retry Safe Restore Failures' }
			if ($shouldOfferLogReview) { $summaryButtons += 'Open Detailed Log' }
			$summaryButtons += 'Close'
			$nextStep = Show-ExecutionSummaryDialog -Title $dlgTitle `
				-SummaryText $dlgMessage `
				-Results $executionSummary `
				-LogPath $displayLogPath `
				-SummaryCards $summaryCards `
				-Buttons $summaryButtons

			if ($nextStep -eq 'Retry Safe Restore Failures')
			{
				LogInfo ("Retrying safe defaults failures: Count={0}" -f $recoverableFailedResults.Count)
				Start-GuiExecutionRun -TweakList $recoverableFailedResults -Mode 'Defaults' -ExecutionTitle 'Retrying Safe Restore Failures'
				return
			}
			if ($nextStep -eq 'Open Detailed Log')
			{
				Exit-ExecutionView
				Show-LogDialog -LogPath $LogPath
				Set-ExecutionGameModeContext -Context $null
				return
			}

			Exit-ExecutionView
			Set-ExecutionGameModeContext -Context $null
			return
		}

		$finalLabel = if ($AbortedRun) { 'Aborted' } elseif ($FatalError) { 'Failed' } elseif ($failedCount -gt 0 -or $notRunCount -gt 0) { 'Partially Complete' } else { 'Done' }
		& $Script:UpdateProgressFn -Completed $CompletedCount -Total $Script:TotalRunnableTweaks -CurrentAction $finalLabel

		$statusMsg = if ($AbortedRun) {
			"Run aborted. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
		} elseif ($FatalError) {
			"Run failed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Open the summary for next steps."
		} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
			"Run partially completed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Open the summary for next steps."
		} elseif ($restartPendingCount -gt 0) {
			"Run complete. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Restart required to finish applying some items."
		} else {
			"Run complete. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
		}
			Set-GuiStatusText -Text $statusMsg -Tone $(if ($AbortedRun -or $FatalError -or $failedCount -gt 0 -or $notRunCount -gt 0) { 'caution' } elseif ($restartPendingCount -gt 0) { 'danger' } else { 'success' })

			if ($AbortedRun)
			{
				$rawRunAbortDisposition = if ($null -eq $Script:RunAbortDisposition) { '<null>' } else { [string]$Script:RunAbortDisposition }
				$runAbortDisposition = Get-RunAbortDisposition
				LogInfo ("[Complete-Run] AbortedRun=true, RunAbortDisposition={0}, EffectiveDisposition={1}" -f $rawRunAbortDisposition, $runAbortDisposition)
				if ($runAbortDisposition -eq 'Exit')
				{
					Close-GuiMainWindow -Reason 'Run abort disposition requested exit.'
				}
				else
				{
					Set-RunAbortDisposition -Disposition 'Return'
					Exit-ExecutionView
				}
				Set-ExecutionGameModeContext -Context $null
				return
			}

		$gameModeOperation = 'Apply'
		$gameModeUndoList = @()
		$dlgTitle = 'Run Complete'
		$dlgMsg = "Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
		$rollbackCommandList = @()

		try
		{
			$gameModeOperation = if ($gameModeContext -and (Test-GuiObjectField -Object $gameModeContext -FieldName 'Operation') -and -not [string]::IsNullOrWhiteSpace([string]$gameModeContext.Operation)) { [string]$gameModeContext.Operation } else { 'Apply' }
			if ($gameModeContext -and $gameModeOperation -ne 'Undo')
			{
				$gameModeUndoList = @(Get-GameModeUndoRunList -Results $executionSummary -ProfileName $gameModeContext.Profile)
			}

			$dlgTitle = if ($gameModeContext -and $gameModeOperation -eq 'Undo') {
				if ($FatalError) {
					'Game Mode Undo Failed'
				} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
					'Game Mode Undo Partially Completed'
				} elseif ($restartPendingCount -gt 0) {
					'Game Mode Undo Restart Pending'
				} else {
					'Game Mode Undo Complete'
				}
			} elseif ($FatalError) {
				'Run Failed'
			} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				'Run Partially Completed'
			} elseif ($restartPendingCount -gt 0) {
				'Run Complete (Restart Pending)'
			} else {
				'Run Complete'
			}
			$whatChangedOpeningLine = if ($gameModeContext -and $gameModeOperation -eq 'Undo') {
				"What happened: $appliedCount gaming change$(if ($appliedCount -eq 1) { '' } else { 's' }) rolled back successfully."
			} else {
				"What happened: $appliedCount tweak$(if ($appliedCount -eq 1) { '' } else { 's' }) applied successfully."
			}
			# Safe Mode: show human-readable list of what changed instead of technical summary
			$humanReadableSummary = $null
			if ((Test-IsSafeModeUX) -and -not ($gameModeContext -and $gameModeOperation -eq 'Undo'))
			{
				$humanReadableSummary = Get-UxHumanReadableSummary -Results $executionSummary
			}
			$whatChangedText = if ($humanReadableSummary)
			{
				"$whatChangedOpeningLine`n`n$humanReadableSummary"
			}
			else
			{
				Build-WhatChangedSummaryText `
					-OpeningLine $whatChangedOpeningLine `
					-Noun 'tweak' `
					-Insights $executionInsights `
					-RestartPendingCount $restartPendingCount `
					-NotRunCount $notRunCount `
					-AlreadyDesiredPhrase 'already matched the requested state' `
					-RestartPendingPhrase 'still need a restart to finish applying' `
					-NotApplicableSingularPhrase ' did not apply on this system' `
					-NotApplicablePluralPhrase 's did not apply on this system' `
					-PolicySkippedSingularPhrase ' was intentionally skipped by the current selection' `
					-PolicySkippedPluralPhrase 's were intentionally skipped by the current selection'
			}
			$gamingSummaryText = $null
			if ($gameModeContext)
			{
				$restartGuidance = if ($restartPendingCount -gt 0) {
					'Restart guidance: a reboot is recommended after this Game Mode run so graphics and overlay changes can fully settle.'
				}
				else {
					'Restart guidance: no restart-specific gaming actions were queued in this run.'
				}
				if ($gameModeOperation -eq 'Undo')
				{
					$gamingSummaryText = "Game Mode undo summary: profile $($gameModeContext.Profile) rollback finished.`n`n$restartGuidance`n`nYou can rerun Game Mode with a different profile whenever you want to rebuild the focused gaming workflow."
				}
				else
				{
					$decisionText = if ((Test-GuiObjectField -Object $gameModeContext -FieldName 'DecisionOverrides')) { Get-GameModeDecisionOverridesText -Overrides $gameModeContext.DecisionOverrides } else { 'none' }
					$undoOptionsLabel = if (Test-IsSafeModeUX) { 'Undo options' } else { 'Rollback options' }
					$rollbackText = if ($gameModeUndoList.Count -gt 0)
					{
						"{0}: {1} gaming change{2} can be undone directly from the post-run summary." -f $undoOptionsLabel, $gameModeUndoList.Count, $(if ($gameModeUndoList.Count -eq 1) { '' } else { 's' })
					}
					else
					{
						"$undoOptionsLabel`: no directly undoable gaming changes were applied in this run."
					}
					$gamingSummaryText = "Game Mode summary: profile $($gameModeContext.Profile) completed under the focused gaming workflow.`n`nDecision overrides: $decisionText.`n`n$restartGuidance`n`n$rollbackText"
					LogInfo ("Game Mode post-run summary: Profile={0}, Applied={1}, RestartPending={2}, DirectUndoEligible={3}, Decisions={4}" -f $gameModeContext.Profile, $appliedCount, $restartPendingCount, $gameModeUndoList.Count, $decisionText)
				}
			}

			$dlgMsg = if ($FatalError) {
				"$whatChangedText`n`nThe run stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
			} elseif ($failedCount -gt 0 -or $notRunCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks partially completed.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} elseif ($restartPendingCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks have finished running, but a restart is still recommended to finish applying some changes.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} elseif ($skippedCount -gt 0 -or $notApplicableCount -gt 0) {
				"$whatChangedText`n`nSelected tweaks have finished running.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			} else {
				"$whatChangedText`n`nSelected tweaks have finished running successfully.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$gamingSummaryText))
			{
				$dlgMsg += "`n`n$gamingSummaryText"
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$summaryNextStepsText))
			{
				$dlgMsg += "`n`nNext steps: $summaryNextStepsText"
			}
			if (-not ($gameModeContext -and $gameModeOperation -eq 'Undo'))
			{
				$rollbackCommandList = @(Get-ExecutionRollbackCommandList -Results $executionSummary)
			}

			# Auto-save last run for Undo Last Run feature
			if ($Mode -eq 'Run' -and $rollbackCommandList.Count -gt 0)
			{
				try
				{
					$lastRunPath = GUICommon\Get-GuiLastRunFilePath
					$lastRunPayload = @{
						Schema = 'Baseline.LastRun'
						Timestamp = (Get-Date -Format 'o')
						AppliedCount = $appliedCount
						RollbackCommands = $rollbackCommandList
					}
					[System.IO.File]::WriteAllText($lastRunPath, ($lastRunPayload | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
					$Script:LastRunProfile = [pscustomobject]$lastRunPayload
					if ($Script:BtnUndoLastRun) { $Script:BtnUndoLastRun.IsEnabled = $true }
					LogInfo ("Auto-saved last run profile with {0} rollback command(s)." -f $rollbackCommandList.Count)
				}
				catch
				{
					LogWarning ("Failed to auto-save last run profile: {0}" -f $_.Exception.Message)
				}
			}

			# Post-run snapshot comparison
			if ($Script:PreRunSnapshot)
			{
				try
				{
					$postRunSnapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest
					$snapshotComparison = Compare-SystemStateSnapshots -Before $Script:PreRunSnapshot -After $postRunSnapshot
					$summaryPayload | Add-Member -NotePropertyName 'SnapshotChangedCount' -NotePropertyValue $snapshotComparison.Changed.Count -Force
					$summaryPayload | Add-Member -NotePropertyName 'SnapshotComparison' -NotePropertyValue $snapshotComparison -Force
					if ($Script:RunState)
					{
						$Script:RunState['PostRunSnapshot'] = $postRunSnapshot
						$Script:RunState['SnapshotComparison'] = $snapshotComparison
					}
					LogInfo ("Post-run snapshot comparison: {0} changed, {1} unchanged, {2} added, {3} removed" -f $snapshotComparison.Changed.Count, $snapshotComparison.Unchanged.Count, $snapshotComparison.Added.Count, $snapshotComparison.Removed.Count)
				}
				catch
				{
					LogWarning ("Failed to capture post-run snapshot: {0}" -f $_.Exception.Message)
				}
			}
		}
		catch
		{
			LogError ("Failed to build execution summary details: {0}" -f $_.Exception.Message)
			# Fall through to show the summary dialog with whatever we have
		}

		while ($true)
		{
			$undoProfileActionLabel = Get-UxUndoProfileActionLabel
			$summaryButtons = @()
			if ($recoverableFailedResults.Count -gt 0)
			{
				$summaryButtons += 'Retry Safe Failures'
			}
			if ($gameModeContext -and $gameModeOperation -ne 'Undo' -and $gameModeUndoList.Count -gt 0)
			{
				$summaryButtons += 'Undo Game Mode Changes'
			}
			if ($rollbackCommandList.Count -gt 0)
			{
				$summaryButtons += $undoProfileActionLabel
			}
			if ($shouldOfferLogReview)
			{
				$summaryButtons += 'Open Detailed Log'
			}
			$summaryButtons += @('Close', 'Exit')

			$nextStep = Show-ExecutionSummaryDialog -Title $dlgTitle `
				-SummaryText $dlgMsg `
				-Results $executionSummary `
				-LogPath $displayLogPath `
				-SummaryCards $summaryCards `
				-Buttons $summaryButtons

			if ($nextStep -eq 'Retry Safe Failures')
			{
				LogInfo ("Retrying safe failures: Count={0}" -f $recoverableFailedResults.Count)
				Start-GuiExecutionRun -TweakList $recoverableFailedResults -Mode 'Run' -ExecutionTitle 'Retrying Safe Failures'
				return
			}
			if ($nextStep -eq 'Undo Game Mode Changes')
			{
				LogInfo ("Game Mode direct undo requested: Profile={0}, Actions={1}" -f $gameModeContext.Profile, $gameModeUndoList.Count)
				Start-GuiExecutionRun -TweakList $gameModeUndoList -Mode 'Run' -ExecutionTitle 'Undoing Game Mode Changes'
				return
			}
			if ($nextStep -eq $undoProfileActionLabel)
			{
				$profileLabel = if ($gameModeContext -and -not [string]::IsNullOrWhiteSpace([string]$gameModeContext.Profile))
				{
					'GameMode-{0}-Rollback' -f [string]$gameModeContext.Profile
				}
				else
				{
					'Baseline-Rollback'
				}
				$defaultRollbackFileName = '{0}-{1}.json' -f $profileLabel, (Get-Date -Format 'yyyyMMdd-HHmmss')
				$savePath = Show-GuiFileSaveDialog -Title $undoProfileActionLabel `
					-Filter 'JSON Files (*.json)|*.json|All Files (*.*)|*.*' `
					-DefaultExtension 'json' `
					-FileName $defaultRollbackFileName
				if ([string]::IsNullOrWhiteSpace([string]$savePath))
				{
					continue
				}

				try
				{
					$exportMode = if ($gameModeContext) { 'GameMode' } else { $Mode }
					$exportProfileName = if ($gameModeContext -and -not [string]::IsNullOrWhiteSpace([string]$gameModeContext.Profile))
					{
						'Rollback-{0}' -f [string]$gameModeContext.Profile
					}
					else
					{
						'Rollback'
					}
					$exportedCount = Export-ExecutionRollbackProfile -FilePath $savePath -Results $executionSummary -Mode $exportMode -ProfileName $exportProfileName
					Set-GuiStatusText -Text $(if (Test-IsSafeModeUX) { "Undo profile exported to $savePath" } else { "Rollback profile exported to $savePath" }) -Tone 'accent'
					[void](Show-ThemedDialog -Title $(if (Test-IsSafeModeUX) { 'Undo Profile Exported' } else { 'Rollback Profile Exported' }) -Message "Saved $exportedCount undo command(s) to:`n`n$savePath" -Buttons @('OK') -AccentButton 'OK')
				}
				catch
				{
					LogError ("Failed to export rollback profile: {0}" -f $_.Exception.Message)
					[void](Show-ThemedDialog -Title $undoProfileActionLabel -Message $(if (Test-IsSafeModeUX) { "Failed to export the undo profile.`n`n$($_.Exception.Message)" } else { "Failed to export rollback profile.`n`n$($_.Exception.Message)" }) -Buttons @('OK') -AccentButton 'OK')
				}

				continue
			}
			if ($nextStep -eq 'Open Detailed Log')
			{
				Exit-ExecutionView
				Show-LogDialog -LogPath $LogPath
				Set-ExecutionGameModeContext -Context $null
				return
			}

					if ($nextStep -eq 'Close')
					{
						Exit-ExecutionView
						$ChkScan.IsChecked = $true
						Invoke-GuiSystemScan
					}
					else
					{
						Close-GuiMainWindow -Reason 'Execution summary exit requested.'
					}

			break
		}
		Set-ExecutionGameModeContext -Context $null
	}

	function Start-GuiExecutionRun
	{
		param (
			[object[]]$TweakList,
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[string]$ExecutionTitle
		)

		$tweakList = @($TweakList)
		if ($tweakList.Count -eq 0) { return }
		if ($Mode -in @('Run', 'Defaults'))
		{
			$resolvedTweakList = Resolve-InteractiveRunSelections -TweakList $tweakList
			if ($null -eq $resolvedTweakList)
			{
				return
			}

			$tweakList = @($resolvedTweakList | Where-Object { $_ })
			if ($tweakList.Count -eq 0)
			{
				return
			}
		}

		Initialize-ExecutionSummary -SelectedTweaks $tweakList

		# Pre-flight checks (including restore point creation) already ran
		# and were confirmed via the Plan Summary dialog. Do not re-run.

		Set-ExecutionGameModeContext -Context $(if (Test-HasGameModeTweaks -TweakList $tweakList) {
			[pscustomobject]@{
				Profile = if ($tweakList[0].PSObject.Properties['GameModeProfile']) { [string]$tweakList[0].GameModeProfile } else { [string](Get-GameModeProfile) }
				Operation = if ($tweakList[0].PSObject.Properties['GameModeOperation']) { [string]$tweakList[0].GameModeOperation } else { 'Apply' }
				DecisionOverrides = (Get-GameModeDecisionOverrides)
			}
		}
		else {
			$null
		})
		if (Get-ExecutionGameModeContext)
		{
			LogInfo ("Game Mode execution context: Operation={0}, Profile={1}, Decisions={2}" -f (Get-ExecutionGameModeContext).Operation, (Get-ExecutionGameModeContext).Profile, (Get-GameModeDecisionOverridesText -Overrides (Get-ExecutionGameModeContext).DecisionOverrides))
		}
		$Script:PreExecutionErrorCount = $Global:Error.Count
		$Script:ExecutionMode = $Mode

		# Auto-capture pre-run snapshot
		try
		{
			$preRunSnapshot = New-SystemStateSnapshot -Manifest $Script:TweakManifest
			$Script:PreRunSnapshot = $preRunSnapshot
			$snapshotDir = Join-Path (Get-BaselineDataDirectory) 'Snapshots'
			if (-not (Test-Path $snapshotDir)) { New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null }
			Limit-SnapshotDirectory -Directory $snapshotDir -Keep 10
			$snapshotPath = Join-Path $snapshotDir ('PreRun-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
			Export-SystemStateSnapshot -Snapshot $preRunSnapshot -Path $snapshotPath
			LogInfo ("Pre-run snapshot saved: {0} entries captured to {1}" -f $preRunSnapshot.Entries.Count, $snapshotPath)
		}
		catch
		{
			LogWarning ("Failed to capture pre-run snapshot: {0}" -f $_.Exception.Message)
		}

		# Track this apply run in session statistics
		Add-SessionStatistic -Name 'ApplyRunCount'
		Update-SessionStatistics -Values @{ TweaksSelected = $tweakList.Count }

		Set-GuiStatusText -Text $(if ($Mode -eq 'Defaults') { 'Restoring Windows defaults...' } else { 'Running selected tweaks...' }) -Tone 'accent'
		$null = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'RenderRefresh' -Synchronous -Action {}

		Stop-Foreground
		if ($Mode -eq 'Defaults')
		{
			Save-GuiUndoSnapshot
		}

			if ($Script:GuiState) { & $Script:GuiState.Set 'RunInProgress' $true } else { $Script:RunInProgress = $true }
		$PrimaryTabs.IsEnabled = $false
		$BtnRun.Content = Get-UxLocalizedString -Key 'GuiPauseButton' -Fallback 'Pause'
		$BtnRun.IsEnabled = $true
		if ($BtnPreviewRun) { $BtnPreviewRun.IsEnabled = $false }
		$BtnDefaults.IsEnabled = $false
		Set-GuiActionButtonsEnabled -Enabled $false
		$ChkScan.IsEnabled = $false
		$ChkTheme.IsEnabled = $false
		Set-SearchControlsEnabled -Enabled $false
			Enter-ExecutionView -Title $ExecutionTitle
			Reset-RunAbortState

			$Script:TotalRunnableTweaks = $tweakList.Count
		$Script:CurrentTweakDisplayName = $null
		& $Script:UpdateProgressFn -Completed 0 -Total $Script:TotalRunnableTweaks -CurrentAction 'Starting...'

		$Script:RunState = [hashtable]::Synchronized(@{
			StartedAt        = (Get-Date)
			Paused           = $false
			AbortRequested   = $false
			AbortRequestedAt = [datetime]::MinValue
			Done             = $false
				AbortedRun       = $false
				AbortDisposition = $null
				CompletedCount   = 0
			ErrorCount       = 0
			FatalError       = $null
			ForceStopIssued  = $false
			CurrentTweak     = ''
			FailureDetails   = [System.Collections.ArrayList]::new()
			LogQueue         = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
			SkippedTweaks    = [hashtable]::Synchronized(@{})
			AppliedFunctions = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
			AppliedTweakMetadata = [System.Collections.ArrayList]::new()
			SummaryPayload   = $null
		})

		$Script:AppendLogFn = {
			param($Text, $Level = 'INFO')
			if (-not $Script:ExecutionLogBox -or -not $Script:ExecutionLogBox.Document) { return }
			$cleanText = ($Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
			if ([string]::IsNullOrWhiteSpace($cleanText)) { return }

			$bc = [System.Windows.Media.BrushConverter]::new()

			$para = New-Object System.Windows.Documents.Paragraph
			$para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
			$para.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
			$para.FontSize = $Script:GuiLayout.FontSizeSubheading

			$contentRun = New-Object System.Windows.Documents.Run
			$contentRun.Text = $cleanText
			$contentColor = switch ($Level.ToUpperInvariant())
			{
				'SUCCESS' { $Script:CurrentTheme.ToggleOn }
				'SKIP'    { $Script:CurrentTheme.TextMuted }
				'ERROR'   { $Script:CurrentTheme.CautionText }
				'WARNING' { $Script:CurrentTheme.RiskMediumBadge }
				default   { $Script:CurrentTheme.TextPrimary }
			}
			$contentRun.Foreground = $bc.ConvertFromString($contentColor)
			[void]($para.Inlines.Add($contentRun))
			[void]($Script:ExecutionLogBox.Document.Blocks.Add($para))
			$vO = $Script:ExecutionLogBox.VerticalOffset
			$vH = $Script:ExecutionLogBox.ViewportHeight
			$eH = $Script:ExecutionLogBox.ExtentHeight
			if (($vO + $vH) -ge ($eH - 30)) { $Script:ExecutionLogBox.ScrollToEnd() }
		}

			$Script:DrainEntry = {
				param($entry)
				switch ($entry.Kind)
				{
				'Log'
				{
					if (Test-ExecutionSkipMessage -Message $entry.Message)
					{
						$skipKey = if (-not [string]::IsNullOrWhiteSpace($Script:ExecutionCurrentSummaryKey)) { $Script:ExecutionCurrentSummaryKey } else { $null }
						if (-not [string]::IsNullOrWhiteSpace($skipKey))
						{
							$skipDetail = if ((Test-GuiObjectField -Object $entry -FieldName 'Message')) { [string]$entry.Message } else { 'Skipped because the system already matched the requested state.' }
							$Script:RunState['SkippedTweaks'][$skipKey] = $skipDetail
							Set-ExecutionSummaryStatus -Key $skipKey -Status 'Skipped' -Detail $skipDetail
						}
					}
				}
				'_TweakStarted'
				{
					$Script:RunState['CurrentTweak'] = $entry.Name
					$Script:ExecutionCurrentSummaryKey = if ((Test-GuiObjectField -Object $entry -FieldName 'Key')) { [string]$entry.Key } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($Script:ExecutionCurrentSummaryKey))
					{
						if ($Script:RunState['SkippedTweaks'].ContainsKey($Script:ExecutionCurrentSummaryKey))
						{
							$null = $Script:RunState['SkippedTweaks'].Remove($Script:ExecutionCurrentSummaryKey)
						}
						Set-ExecutionSummaryStatus -Key $Script:ExecutionCurrentSummaryKey -Status 'Running'
					}
					$Script:ExecutionLastConsoleAction = $null
					$Script:ExecutionCurrentStepIndex = if ((Test-GuiObjectField -Object $entry -FieldName 'StepIndex')) { [int]$entry.StepIndex } else { $null }
					$Script:ExecutionCurrentStepTotal = if ((Test-GuiObjectField -Object $entry -FieldName 'StepTotal')) { [int]$entry.StepTotal } else { $null }
					$progressLabel = $entry.Name
					$startProgress = if ($null -ne $Script:ExecutionCurrentStepIndex) { [int]$Script:ExecutionCurrentStepIndex - 1 } else { [int]$Script:RunState['CompletedCount'] }
					& $Script:UpdateProgressFn -Completed $startProgress -Total $Script:TotalRunnableTweaks -CurrentAction $progressLabel
				}
				'_TweakCompleted'
				{
					$completedStatus = if ([string]::IsNullOrWhiteSpace($entry.Status)) { 'success' } else { $entry.Status.ToLowerInvariant() }
					$completedName = ($entry.Name -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					$completedKey = if ((Test-GuiObjectField -Object $entry -FieldName 'Key')) { [string]$entry.Key } else { $null }
					$wasSkipped = $false
					$skipDetail = $null
					if ((Test-GuiObjectField -Object $entry -FieldName 'Count'))
					{
						$Script:RunState['CompletedCount'] = [int]$entry.Count
					}
					if (-not [string]::IsNullOrWhiteSpace($completedKey) -and $Script:RunState['SkippedTweaks'].ContainsKey($completedKey))
					{
						$wasSkipped = $true
						$skipDetail = [string]$Script:RunState['SkippedTweaks'][$completedKey]
						$null = $Script:RunState['SkippedTweaks'].Remove($completedKey)
					}
					if (-not [string]::IsNullOrWhiteSpace($completedName))
					{
						$resolvedOutcome = $null
						if ($wasSkipped)
						{
							$completedRecord = if (-not [string]::IsNullOrWhiteSpace($completedKey)) { $Script:ExecutionSummaryLookup[$completedKey] } else { $null }
							$resolvedOutcome = GUIExecution\Get-GuiExecutionOutcome -Status 'Skipped' -Detail $skipDetail -RequiresRestart $(if ($completedRecord -and (Test-GuiObjectField -Object $completedRecord -FieldName 'RequiresRestart')) { [bool]$completedRecord.RequiresRestart } else { $false })
							Set-ExecutionSummaryStatus -Key $completedKey -Status $resolvedOutcome -Detail $skipDetail
						}
						else
						{
							$completedRecord = if (-not [string]::IsNullOrWhiteSpace($completedKey)) { $Script:ExecutionSummaryLookup[$completedKey] } else { $null }
							$baseStatus = if ($completedStatus -eq 'success') { 'Success' } else { 'Failed' }
							$resolvedOutcome = GUIExecution\Get-GuiExecutionOutcome -Status $baseStatus -Detail $null -RequiresRestart $(if ($completedRecord -and (Test-GuiObjectField -Object $completedRecord -FieldName 'RequiresRestart')) { [bool]$completedRecord.RequiresRestart } else { $false })
							Set-ExecutionSummaryStatus -Key $completedKey -Status $resolvedOutcome
						}

						$completedRecord = if (-not [string]::IsNullOrWhiteSpace($completedKey)) { $Script:ExecutionSummaryLookup[$completedKey] } else { $null }
						if (-not $completedRecord)
						{
							$completedRecord = [pscustomobject]@{
								Name = $completedName
								Status = $resolvedOutcome
								Detail = if ($wasSkipped) { $skipDetail } else { $null }
								OutcomeState = $resolvedOutcome
								OutcomeReason = if ($wasSkipped) { $skipDetail } else { $null }
							}
						}

						$liveLogEntry = Get-ExecutionResultLiveLogEntry -Record $completedRecord
						if ($liveLogEntry -and -not [string]::IsNullOrWhiteSpace([string]$liveLogEntry.Message))
						{
							$completedStepIndex = if ((Test-GuiObjectField -Object $entry -FieldName 'StepIndex')) { [int]$entry.StepIndex } else { $null }
							$completedStepTotal = if ((Test-GuiObjectField -Object $entry -FieldName 'StepTotal')) { [int]$entry.StepTotal } else { $null }
							$logMessage = if ($null -ne $completedStepIndex -and $null -ne $completedStepTotal) {
								"[{0}/{1}] {2}" -f $completedStepIndex, $completedStepTotal, ([string]$liveLogEntry.Message)
							} else { [string]$liveLogEntry.Message }
							& $Script:AppendLogFn $logMessage $(if ((Test-GuiObjectField -Object $liveLogEntry -FieldName 'Level')) { [string]$liveLogEntry.Level } else { 'INFO' })
						}
					}
					if (-not [string]::IsNullOrWhiteSpace($completedKey))
					{
						$completedRecord = $Script:ExecutionSummaryLookup[$completedKey]
						if ($completedRecord -and $Script:RunState['AppliedTweakMetadata'])
						{
							$appliedMetadata = GUIExecution\New-GuiExecutionAppliedTweakMetadata -Result $completedRecord -Outcome ([string]$completedRecord.Status)
							if ($appliedMetadata)
							{
								[void]$Script:RunState['AppliedTweakMetadata'].Add($appliedMetadata)
							}
						}
					}
					$Script:ExecutionCurrentSummaryKey = $null
					$Script:ExecutionCurrentStepIndex = $null
					$Script:ExecutionCurrentStepTotal = $null
					$Script:ExecutionLastConsoleAction = $null
					$completedProgress = if ($null -ne $completedStepIndex) { [int]$completedStepIndex } else { [int]$Script:RunState['CompletedCount'] }
					& $Script:UpdateProgressFn -Completed $completedProgress -Total $Script:TotalRunnableTweaks -CurrentAction $completedName
				}
				'_TweakFailed'
				{
					$failedKey = if ((Test-GuiObjectField -Object $entry -FieldName 'Key')) { [string]$entry.Key } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($failedKey) -and $Script:RunState['SkippedTweaks'].ContainsKey($failedKey))
					{
						$null = $Script:RunState['SkippedTweaks'].Remove($failedKey)
					}
					if (-not [string]::IsNullOrWhiteSpace($entry.Name))
					{
						[void]$Script:RunState['FailureDetails'].Add([PSCustomObject]@{
							Name  = $entry.Name
							Error = if ((Test-GuiObjectField -Object $entry -FieldName 'Error')) { $entry.Error } else { $null }
						})
					}
					if (-not [string]::IsNullOrWhiteSpace($failedKey))
					{
						Set-ExecutionSummaryStatus -Key $failedKey -Status 'Failed' -Detail $(if ((Test-GuiObjectField -Object $entry -FieldName 'Error')) { [string]$entry.Error } else { $null })
					}
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $Script:RunState['CurrentTweak']
				}
				'_RunError'
				{
					$Script:RunState['FatalError'] = if ([string]::IsNullOrWhiteSpace($entry.Error)) { 'Unexpected fatal run error.' } else { [string]$entry.Error }
					& $Script:AppendLogFn ("Fatal run error: {0}" -f $Script:RunState['FatalError']) 'ERROR'
					$diagnosticText = if ((Test-GuiObjectField -Object $entry -FieldName 'Diagnostic')) { [string]$entry.Diagnostic } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($diagnosticText))
					{
						foreach ($diagnosticLine in @($diagnosticText -split "(`r`n|`n|`r)"))
						{
							if (-not [string]::IsNullOrWhiteSpace([string]$diagnosticLine))
							{
								& $Script:AppendLogFn $diagnosticLine 'ERROR'
							}
						}
					}
					LogError ("Fatal run error: {0}" -f $Script:RunState['FatalError'])
				}
				'_RunNotice'
				{
				}
				'ConsoleAction'
				{
					$cleanAct = ($entry.Action -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					$Script:ExecutionLastConsoleAction = $cleanAct
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $cleanAct
				}
				'ConsoleStatus'
				{
					$Script:ExecutionLastConsoleAction = $null
				}
				'ConsoleComplete'
				{
					$Script:ExecutionLastConsoleAction = $null
				}
				'_InteractiveSelectionRequest'
				{
					$responseState = if ((Test-GuiObjectField -Object $entry -FieldName 'ResponseState')) { $entry.ResponseState } else { $null }
					try
					{
						switch ([string]$entry.RequestType)
						{
							'ScheduledTasks'
							{
								$selectionArgs = @{
									CollectSelectionOnly = $true
								}
								$requestedMode = if ((Test-GuiObjectField -Object $entry -FieldName 'Mode')) { [string]$entry.Mode } else { $null }
								if ($requestedMode -in @('Enable', 'Disable'))
								{
									$selectionArgs[$requestedMode] = $true
								}
								else
								{
									throw "Unsupported ScheduledTasks selection mode '$requestedMode'."
								}
								if ((Test-GuiObjectField -Object $entry -FieldName 'SelectedNames') -and $null -ne $entry.SelectedNames)
								{
									$selectionArgs['SelectedTaskNames'] = @($entry.SelectedNames)
								}

								$selectionResult = ScheduledTasks @selectionArgs
								if ($responseState)
								{
									$responseState['Result'] = $selectionResult
								}
							}
							'UWPApps' # NOTE: string must match the function name in UWPApps.psm1
							{
								$selectionArgs = @{
									CollectSelectionOnly = $true
								}
								$requestedMode = if ((Test-GuiObjectField -Object $entry -FieldName 'Mode')) { [string]$entry.Mode } else { $null }
								if ($requestedMode -in @('Install', 'Uninstall'))
								{
									$selectionArgs[$requestedMode] = $true
								}
								else
								{
									throw "Unsupported UWPApps selection mode '$requestedMode'."
								}
								if ((Test-GuiObjectField -Object $entry -FieldName 'ForAllUsers') -and [bool]$entry.ForAllUsers)
								{
									$selectionArgs['ForAllUsers'] = $true
								}
								if ((Test-GuiObjectField -Object $entry -FieldName 'SelectedPackages') -and $null -ne $entry.SelectedPackages)
								{
									$selectionArgs['SelectedPackages'] = @($entry.SelectedPackages)
								}

								$selectionResult = UWPApps @selectionArgs
								if ($responseState)
								{
									$responseState['Result'] = $selectionResult
								}
							}
							'WindowsCapabilities'
							{
								$selectionArgs = @{
									CollectSelectionOnly = $true
								}
								$requestedMode = if ((Test-GuiObjectField -Object $entry -FieldName 'Mode')) { [string]$entry.Mode } else { $null }
								if ($requestedMode -in @('Install', 'Uninstall'))
								{
									$selectionArgs[$requestedMode] = $true
								}
								else
								{
									throw "Unsupported WindowsCapabilities selection mode '$requestedMode'."
								}
								if ((Test-GuiObjectField -Object $entry -FieldName 'SelectedNames') -and $null -ne $entry.SelectedNames)
								{
									$selectionArgs['SelectedCapabilityNames'] = @($entry.SelectedNames)
								}

								$selectionResult = WindowsCapabilities @selectionArgs
								if ($responseState)
								{
									$responseState['Result'] = $selectionResult
								}
							}
							'WindowsFeatures'
							{
								$selectionArgs = @{
									CollectSelectionOnly = $true
								}
								$requestedMode = if ((Test-GuiObjectField -Object $entry -FieldName 'Mode')) { [string]$entry.Mode } else { $null }
								if ($requestedMode -in @('Enable', 'Disable'))
								{
									$selectionArgs[$requestedMode] = $true
								}
								else
								{
									throw "Unsupported WindowsFeatures selection mode '$requestedMode'."
								}
								if ((Test-GuiObjectField -Object $entry -FieldName 'SelectedNames') -and $null -ne $entry.SelectedNames)
								{
									$selectionArgs['SelectedFeatureNames'] = @($entry.SelectedNames)
								}

								$selectionResult = WindowsFeatures @selectionArgs
								if ($responseState)
								{
									$responseState['Result'] = $selectionResult
								}
							}
							default
							{
								throw "Unsupported interactive selection request type '$([string]$entry.RequestType)'."
							}
						}
					}
					catch
					{
						if ($responseState)
						{
							$responseState['Error'] = $_.Exception.Message
						}
					}
					finally
					{
						if ($responseState)
						{
							$responseState['Done'] = $true
						}
					}
				}
				'_SubProgress'
				{
					$subAct = if ((Test-GuiObjectField -Object $entry -FieldName 'Action')) { $entry.Action } else { $null }
					$subPct = if ((Test-GuiObjectField -Object $entry -FieldName 'Percent')) { [int]$entry.Percent } else { -1 }
					$subComp = if ((Test-GuiObjectField -Object $entry -FieldName 'Completed')) { [int]$entry.Completed } else { 0 }
					$subTot = if ((Test-GuiObjectField -Object $entry -FieldName 'Total')) { [int]$entry.Total } else { 0 }
					if ($subPct -lt 0 -and $subTot -gt 0) { $subPct = [Math]::Round(($subComp / $subTot) * 100) }
					$detail = if ($subAct -and $subPct -ge 0) { "{0} ({1}%)" -f $subAct, $subPct }
						elseif ($subAct) { $subAct }
						elseif ($subPct -ge 0) { "{0}%" -f $subPct }
						else { $null }
					if ($detail)
					{
						& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $detail
					}
					}
				}
			}

			$Script:DrainExecutionQueueSafely = {
				$qEntry = $null
				while ($Script:RunState['LogQueue'].TryDequeue([ref]$qEntry))
				{
					try
					{
						& $Script:DrainEntry $qEntry
					}
					catch
					{
						$entryKind = if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Kind')) { [string]$qEntry.Kind } else { '<unknown>' }
						$entryName = if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Name')) { [string]$qEntry.Name } else { $null }
						$entryAction = if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Action')) { [string]$qEntry.Action } else { $null }
						$entryLabel = if (-not [string]::IsNullOrWhiteSpace($entryName)) { '{0}/{1}' -f $entryKind, $entryName }
							elseif (-not [string]::IsNullOrWhiteSpace($entryAction)) { '{0}/{1}' -f $entryKind, $entryAction }
							else { $entryKind }

						switch ($entryKind)
						{
							'_TweakStarted'
							{
								if (-not [string]::IsNullOrWhiteSpace($entryName))
								{
									$Script:RunState['CurrentTweak'] = $entryName
								}
								$Script:ExecutionCurrentSummaryKey = if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Key')) { [string]$qEntry.Key } else { $null }
							}
							'_TweakCompleted'
							{
								if ($qEntry -and (Test-GuiObjectField -Object $qEntry -FieldName 'Count'))
								{
									$Script:RunState['CompletedCount'] = [int]$qEntry.Count
								}
								if (-not [string]::IsNullOrWhiteSpace($entryName))
								{
									$Script:RunState['CurrentTweak'] = $entryName
								}
								$Script:ExecutionCurrentSummaryKey = $null
							}
							'_TweakFailed'
							{
								$Script:ExecutionCurrentSummaryKey = $null
							}
							'ConsoleAction'
							{
								if (-not [string]::IsNullOrWhiteSpace($entryAction))
								{
									$Script:ExecutionLastConsoleAction = $entryAction
								}
							}
							'ConsoleStatus'
							{
								$Script:ExecutionLastConsoleAction = $null
							}
							'ConsoleComplete'
							{
								$Script:ExecutionLastConsoleAction = $null
							}
						}

						LogError ("[Timer] Queue entry failed [{0}]: {1}" -f $entryLabel, $_.Exception.Message)
					}
					finally
					{
						$qEntry = $null
					}
				}
			}

			Set-Variable -Name 'GUIRunState' -Scope Global -Value $Script:RunState['LogQueue']
			Set-UILogHandler { param($entry) $Script:RunState['LogQueue'].Enqueue($entry) }

		LogInfo ("Starting tweak execution (mode: {0}, scenario: {1})" -f $Mode, $(if (Get-ExecutionGameModeContext) { 'Game' } else { 'Standard' }))

		$bgModuleDir   = Split-Path $PSScriptRoot -Parent
		$bgLoaderPath  = Join-Path $bgModuleDir 'Baseline.psm1'
		$bgRootDir     = Split-Path $bgModuleDir -Parent
		$bgLocDir      = Join-Path $bgRootDir 'Localizations'
		$bgUICulture   = $PSUICulture
		$bgLogFilePath = $Global:LogFilePath

		$Script:ExecutionWorker = GUIExecution\Start-GuiExecutionWorker `
			-RunState $Script:RunState `
			-TweakList $tweakList `
			-Mode $Mode `
			-LoaderPath $bgLoaderPath `
			-LocalizationDirectory $bgLocDir `
			-UICulture $bgUICulture `
			-LogFilePath $bgLogFilePath `
			-LogMode $(if (Get-ExecutionGameModeContext) { 'Game' } else { $null })
		$Script:BgPS = $Script:ExecutionWorker.PowerShell
		$Script:BgAsync = $Script:ExecutionWorker.AsyncResult
		$Script:ExecutionRunspace = $Script:ExecutionWorker.Runspace
		$Script:ExecutionRunPowerShell = $Script:ExecutionWorker.PowerShell

		$Script:ExecutionPumpTickFn = {
			try
			{
				if (-not $Script:RunInProgress -or -not $Script:RunState) { return }

				if ($Script:AbortRequested -and -not $Script:RunState['AbortRequested'])
				{
					$Script:RunState['AbortRequested'] = $true
					$Script:RunState['AbortRequestedAt'] = Get-Date
				}

				if (
					$Script:RunState['AbortRequested'] -and
					-not $Script:RunState['Done'] -and
					-not $Script:RunState['ForceStopIssued'] -and
					$Script:RunState['AbortRequestedAt'] -ne [datetime]::MinValue -and
					((Get-Date) - $Script:RunState['AbortRequestedAt']).TotalSeconds -ge 2
				)
				{
					$Script:RunState['ForceStopIssued'] = $true
					$Script:RunState['AbortedRun'] = $true
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_RunNotice'
						Level = 'WARNING'
						Message = 'Abort requested - stopping the current operation now.'
					})
					$bgPsToStop = $Script:BgPS
					if ($bgPsToStop)
					{
						GUIExecution\Request-GuiExecutionWorkerStop -PowerShellInstance $bgPsToStop
					}
				}

					& $Script:DrainExecutionQueueSafely

					$completed = [int]$Script:RunState['CompletedCount']
					if (-not $Script:RunState['Paused'])
					{
						$currentAction = if (-not [string]::IsNullOrWhiteSpace($Script:RunState['CurrentTweak'])) { $Script:RunState['CurrentTweak'] } else { Get-UxExecutionPlaceholderText -Kind 'Working' }
						& $Script:UpdateProgressFn -Completed $completed -Total $Script:TotalRunnableTweaks -CurrentAction $currentAction
					}

				if ($Script:BgAsync -and -not $Script:BgAsync.IsCompleted -and -not $Script:RunState['Done']) { return }

				# Do not complete the run while the abort dialog is showing to prevent stacked dialogs
				if ($Script:AbortDialogShowing) { return }

				if ($Script:ExecutionRunTimer)
				{
					try { $Script:ExecutionRunTimer.Stop() } catch { $null = $_ }
					try { $Script:ExecutionRunTimer.Dispose() } catch { $null = $_ }
				}

					& $Script:DrainExecutionQueueSafely

					GUIExecution\Complete-GuiExecutionWorker -Worker $Script:ExecutionWorker
				$Script:ExecutionWorker = $null
				$Script:ExecutionRunspace = $null
				$Script:ExecutionRunPowerShell = $null
				$Script:ExecutionRunTimer = $null
				$Script:BgPS = $null
				$Script:BgAsync = $null

				foreach ($fn in $Script:RunState['AppliedFunctions']) { [void]$Script:AppliedTweaks.Add($fn) }

				Clear-UILogHandler
				Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue
				if ($Script:GuiState) { & $Script:GuiState.Set 'RunInProgress' $false } else { $Script:RunInProgress = $false }
				$Script:CurrentTweakDisplayName = $null
				$PrimaryTabs.IsEnabled = $true
				$BtnRun.Content = Get-UxRunActionLabel
				$BtnRun.IsEnabled = $true
				if ($BtnPreviewRun) { $BtnPreviewRun.IsEnabled = $true }
				$BtnDefaults.IsEnabled = $true
				Set-GuiActionButtonsEnabled -Enabled $true
				$ChkScan.IsEnabled = $true
				$ChkTheme.IsEnabled = $true
				Set-SearchControlsEnabled -Enabled $true

				$completedCount = [int]$Script:RunState['CompletedCount']
				$abortedRun = $Script:RunState['AbortedRun']
				$fatalError = if ([string]::IsNullOrWhiteSpace($Script:RunState['FatalError'])) { $null } else { [string]$Script:RunState['FatalError'] }
				$logPath = $Global:LogFilePath
				LogInfo "[Timer] Run done. mode=$($Script:ExecutionMode), aborted=$abortedRun, disposition=$($Script:RunAbortDisposition), completed=$completedCount"
				Complete-ExecutionSummary -AbortedRun:$abortedRun -FatalError $fatalError
				$executionSummary = @(Get-ExecutionSummaryResults)
				try
				{
					Set-LogMode -Mode $(if (Get-ExecutionGameModeContext) { 'Game' } else { $null })
					Write-ExecutionSummaryToLog -Results $executionSummary -AbortedRun:$abortedRun -FatalError $fatalError

					# Update session statistics from execution results
					$guiSummaryPayload = GUIExecution\Get-GuiExecutionSummaryPayload -Results $executionSummary
					Add-SessionStatistic -Name 'SucceededCount' -Increment $guiSummaryPayload.SuccessCount
					Add-SessionStatistic -Name 'SucceededCount' -Increment $guiSummaryPayload.RestartPendingCount
					Add-SessionStatistic -Name 'FailedCount' -Increment $guiSummaryPayload.FailedCount
					Add-SessionStatistic -Name 'SkippedCount' -Increment ($guiSummaryPayload.SkippedCount + $guiSummaryPayload.NotApplicableCount + $guiSummaryPayload.NotRunCount)

					# Write audit trail record for this execution run
					try
					{
						$auditAction = if ($Script:ExecutionMode -eq 'Defaults') { 'DefaultsRestored' } else { 'RunCompleted' }
						$auditDuration = if ($Script:RunState['StartedAt']) { (Get-Date) - [datetime]$Script:RunState['StartedAt'] } else { $null }
						$auditParams = @{
							Action  = $auditAction
							Mode    = $Script:ExecutionMode
							Results = $guiSummaryPayload
						}
						if ($null -ne $auditDuration) { $auditParams['Duration'] = $auditDuration }
						Write-AuditRecord @auditParams
					}
					catch
					{
						LogWarning "[Timer] Write-AuditRecord failed: $($_.Exception.Message)"
					}

					Complete-GuiExecutionRun -Mode $Script:ExecutionMode `
						-CompletedCount $completedCount `
						-AbortedRun:$abortedRun `
						-FatalError $fatalError `
						-ExecutionSummary $executionSummary `
						-LogPath $logPath
				}
				catch
				{
					LogError "[Timer] Complete-GuiExecutionRun FAILED: $($_.Exception.Message)"
					LogError ("Complete-GuiExecutionRun failed: {0}" -f $_.Exception.Message)
					# Ensure the GUI is restored even if the completion handler fails
					try { Exit-ExecutionView } catch { $null = $_ }
				}
				finally
				{
					Clear-LogMode
				}
			}
			catch
			{
				if (-not $Script:ExecutionTimerErrorShown)
				{
					$Script:ExecutionTimerErrorShown = $true
					LogError "[Timer] OUTER CATCH: $($_.Exception.Message)"
					LogError ("Execution UI update failed: {0}" -f $_.Exception.Message)
					try { Set-GuiStatusText -Text 'Execution UI update failed. See the run log for details.' -Tone 'caution' } catch { $null = $_ }
					# Restore the GUI if the timer is already stopped or run is finished to prevent
					# the execution view from being permanently stuck.
					$timerStopped = (-not $Script:ExecutionRunTimer)
					$runFinished = ($Script:RunState -and $Script:RunState['Done'])
					if ($timerStopped -or $runFinished -or $Script:RunInProgress -eq $false -or $Script:AbortRequested)
					{
						try { Exit-ExecutionView } catch { $null = $_ }
					}
				}
			}
		}

		$runTimer = New-Object System.Windows.Threading.DispatcherTimer
		$runTimer.Interval = [TimeSpan]::FromMilliseconds(100)
		$runTimer.Add_Tick({
			& $Script:ExecutionPumpTickFn
		})
		$Script:ExecutionRunTimer = $runTimer
		$runTimer.Start()
		& $Script:ExecutionPumpTickFn
	}

	function Get-ActiveTweakRunList
	{
		$selectedTweaks = @(Get-SelectedTweakRunList)
		if (-not [bool]$Script:GameMode)
		{
			return $selectedTweaks
		}

		$allowlistLookup = @{}
		foreach ($allowlistFunction in @($Script:GameModeAllowlist))
		{
			$allowlistName = [string]$allowlistFunction
			if (-not [string]::IsNullOrWhiteSpace($allowlistName))
			{
				$allowlistLookup[$allowlistName] = $true
			}
		}

		$selectedGameModeScoped = @(
			$selectedTweaks | Where-Object {
				if (-not $_) { return $false }
				$selectedFunction = if ((Test-GuiObjectField -Object $_ -FieldName 'Function')) { [string]$_.Function } else { $null }
				if ([string]::IsNullOrWhiteSpace($selectedFunction)) { return $false }
				return $allowlistLookup.ContainsKey($selectedFunction)
			}
		)

		$gameModePlan = @(Get-GameModePlan)
		if ($gameModePlan.Count -eq 0)
		{
			return $selectedGameModeScoped
		}

		# Merge gaming-scoped manual selections with the active Game Mode plan.
		# If both contain the same function, Game Mode plan entry wins.
		$mergedRunList = [System.Collections.Generic.List[object]]::new()
		$indexByFunction = @{}

		foreach ($selectedEntry in $selectedGameModeScoped)
		{
			if (-not $selectedEntry)
			{
				continue
			}

			[void]$mergedRunList.Add($selectedEntry)

			$selectedFunction = if ((Test-GuiObjectField -Object $selectedEntry -FieldName 'Function')) { [string]$selectedEntry.Function } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($selectedFunction))
			{
				$indexByFunction[$selectedFunction] = $mergedRunList.Count - 1
			}
		}

		foreach ($planEntry in $gameModePlan)
		{
			if (-not $planEntry)
			{
				continue
			}

			$planFunction = if ((Test-GuiObjectField -Object $planEntry -FieldName 'Function')) { [string]$planEntry.Function } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($planFunction) -and $indexByFunction.ContainsKey($planFunction))
			{
				$mergedRunList[[int]$indexByFunction[$planFunction]] = $planEntry
				continue
			}

			[void]$mergedRunList.Add($planEntry)
			if (-not [string]::IsNullOrWhiteSpace($planFunction))
			{
				$indexByFunction[$planFunction] = $mergedRunList.Count - 1
			}
		}

		return @($mergedRunList)
	}

