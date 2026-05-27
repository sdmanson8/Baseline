
	<#
	    .SYNOPSIS
	#>

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

	<#
	    .SYNOPSIS
	#>

	function New-ExecutionViewProgressSection
	{
		param (
			[Parameter(Mandatory = $true)]$BrushConverter,
			[bool]$ShowAbortButton = $true
		)

		$progressGrid = New-Object System.Windows.Controls.Grid
		$progressGrid.Margin = [System.Windows.Thickness]::new(0,0,0,12)
		$progressCol1 = New-Object System.Windows.Controls.ColumnDefinition
		$progressCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		$progressCol2 = New-Object System.Windows.Controls.ColumnDefinition
		$progressCol2.Width = if ($ShowAbortButton)
		{
			[System.Windows.GridLength]::new($Script:GuiLayout.ProgressColumnWidth, [System.Windows.GridUnitType]::Pixel)
		}
		else
		{
			[System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Pixel)
		}
		[void]($progressGrid.ColumnDefinitions.Add($progressCol1))
		[void]($progressGrid.ColumnDefinitions.Add($progressCol2))

		$progressStack = New-Object System.Windows.Controls.StackPanel
		$progressStack.Orientation = 'Vertical'
		$progressStack.Margin = if ($ShowAbortButton) { [System.Windows.Thickness]::new(0,0,12,0) } else { [System.Windows.Thickness]::new(0) }
		[System.Windows.Controls.Grid]::SetColumn($progressStack, 0)

		$progressBar = New-Object System.Windows.Controls.ProgressBar
		$progressBar.Minimum = 0
		$progressBar.Maximum = 1
		$progressBar.Value = 0
		$progressBar.Height = [double]$Script:GuiLayout.ProgressBarHeight
		$progressBar.MinHeight = [double]$Script:GuiLayout.ProgressBarHeight
		$progressBar.MinWidth = [double]$Script:GuiLayout.ProgressBarMinWidth
		$progressBar.HorizontalAlignment = 'Stretch'
		$progressBar.VerticalAlignment = 'Center'
		$progressBar.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ProgressGreen -Context 'ExecutionView.ProgressBar.Foreground'
		$progressBar.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ProgressGreenTrack -Context 'ExecutionView.ProgressBar.Background'
		$progressBar.BorderThickness = [System.Windows.Thickness]::new(0)
		$progressBar.Template = New-ExecutionProgressBarTemplate
		$progressHost = $progressBar
		$progressHost.Margin = [System.Windows.Thickness]::new(0,0,0,6)
		[void]($progressStack.Children.Add($progressHost))

		$progressText = New-Object System.Windows.Controls.TextBlock
		$progressText.FontSize = $Script:GuiLayout.FontSizeSubheading
		$progressText.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$progressText.Text = Get-UxExecutionPlaceholderText -Kind 'Preparing'
		$progressText.TextWrapping = 'NoWrap'
		$progressText.TextTrimming = 'CharacterEllipsis'
		$progressText.HorizontalAlignment = 'Stretch'
		[void]($progressStack.Children.Add($progressText))
		[void]($progressGrid.Children.Add($progressStack))

		$abortBtn = $null
		if ($ShowAbortButton)
		{
			$abortBtnHost = New-Object System.Windows.Controls.Border
			$abortBtnHost.Padding = [System.Windows.Thickness]::new(0)
			$abortBtnHost.Margin = [System.Windows.Thickness]::new(0, -6, 0, 0)
			$abortBtnHost.HorizontalAlignment = 'Right'
			$abortBtnHost.VerticalAlignment = 'Top'
			[System.Windows.Controls.Grid]::SetColumn($abortBtnHost, 1)

			$abortBtn = New-Object System.Windows.Controls.Button
			$abortBtn.Content = Get-UxLocalizedString -Key 'GuiAbortButton' -Fallback 'Abort'
			$abortBtn.MinWidth = $Script:GuiLayout.ButtonAbortMinWidth
			$abortBtn.Height = ([double]$Script:GuiLayout.ProgressBarHeight + 12)
			$abortBtn.Padding = [System.Windows.Thickness]::new(16,4,16,4)
			$abortBtn.HorizontalAlignment = 'Stretch'
			$abortBtn.VerticalAlignment = 'Top'
			$abortBtn.Cursor = [System.Windows.Input.Cursors]::Hand
			$abortBtn.TabIndex = 0
			Register-GuiEventHandler -Source $abortBtn -EventName 'Click' -Handler { & $Script:PromptRunAbortFn }
			Set-ButtonChrome -Button $abortBtn -Variant 'Danger'
			$abortBtnHost.Child = $abortBtn
			[void]($progressGrid.Children.Add($abortBtnHost))
		}

		return @{
			Grid        = $progressGrid
			ProgressHost = $progressHost
			ProgressBar = $progressBar
			ProgressText = $progressText
			AbortButton = $abortBtn
		}
	}

	<#
	    .SYNOPSIS
	#>

	function New-ExecutionProgressBarTemplate
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		return New-GuiExecutionProgressBarTemplate
	}

	<#
	    .SYNOPSIS
	#>

	function New-ExecutionViewLogBox
	{
		param (
			[Parameter(Mandatory = $true)]$BrushConverter
		)

		$logBox = New-Object System.Windows.Controls.RichTextBox
		$logBox.IsReadOnly = $true
		$logBox.VerticalScrollBarVisibility = 'Auto'
		$logBox.HorizontalScrollBarVisibility = 'Disabled'
		$logBox.BorderThickness = [System.Windows.Thickness]::new(1)
		$logBox.Padding = [System.Windows.Thickness]::new(12)
		$logBg = if ($Script:CurrentTheme -and $Script:CurrentTheme.ContainsKey('LogBg') -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.LogBg)) { [string]$Script:CurrentTheme.LogBg } else { [string]$Script:CurrentTheme.CardBg }
		$logBox.Background = $BrushConverter.ConvertFromString($logBg)
		$logBox.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$logBox.BorderBrush = $BrushConverter.ConvertFromString($Script:CurrentTheme.CardBorder)
		$logBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
		$logBox.FontSize = $Script:GuiLayout.FontSizeSubheading
		$logBox.TabIndex = 1
		$flowDoc = New-Object System.Windows.Documents.FlowDocument
		$flowDoc.PagePadding = [System.Windows.Thickness]::new(0)
		$flowDoc.LineHeight = 1
		$logBox.Document = $flowDoc

		return $logBox
	}

	<#
	    .SYNOPSIS
	#>

	function Enter-ExecutionView
	{
		param (
			[string]$Title,
			[bool]$ShowAbortButton = $true
		)

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
		$progressSection = New-ExecutionViewProgressSection -BrushConverter $bc -ShowAbortButton:$ShowAbortButton
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
		if ($Script:UpdateGuiBackToTopButtonScript)
		{
			try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionView.Enter.UpdateBackToTopButton' }
		}
		$Script:ExecutionLogBox = $logBox
		$Script:ExecutionLastConsoleAction = $null
		$Script:ExecutionProgressHost = $progressSection.ProgressHost
		$Script:ExecutionProgressBar = $progressSection.ProgressBar
		$Script:ExecutionProgressText = $progressSection.ProgressText
		$Script:ExecutionLastProgressCompleted = -1
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
		$Script:ExecutionPreviousFooterVisibility = @{
			ActionButtonBar = if ($ActionButtonBar) { $ActionButtonBar.Visibility } else { $null }
			BtnRun = if ($BtnRun) { $BtnRun.Visibility } else { $null }
			BtnDefaults = if ($BtnDefaults) { $BtnDefaults.Visibility } else { $null }
			BtnPreviewRun = if ($BtnPreviewRun) { $BtnPreviewRun.Visibility } else { $null }
			StatusText = if ($StatusText) { $StatusText.Visibility } else { $null }
		}

		# Hide filter bar, tab bar, and expert-mode banner during execution
		$PrimaryTabs.Visibility = [System.Windows.Visibility]::Collapsed
		$HeaderBorder.Visibility = [System.Windows.Visibility]::Collapsed
		if ($ExpertModeBanner) { $ExpertModeBanner.Visibility = [System.Windows.Visibility]::Collapsed }
		# Hide bottom action buttons during execution
		if ($ActionButtonBar) { $ActionButtonBar.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($BtnRun) { $BtnRun.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($BtnDefaults) { $BtnDefaults.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($StatusText) { $StatusText.Visibility = [System.Windows.Visibility]::Collapsed }
		if ($progressSection.AbortButton)
		{
			[void]($progressSection.AbortButton.Focus())
		}
		elseif ($logBox)
		{
			[void]($logBox.Focus())
		}
	}

	    <#
	        .SYNOPSIS
	    #>

	    function Exit-ExecutionView
	    {
			LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionViewEntered' -Fallback '[Exit-ExecutionView] ENTERED - restoring GUI')
			$deferAbortReset = ($Script:AbortRequested -and (Get-RunAbortDisposition) -eq 'Return')
			$savedPreviousContent = $Script:ExecutionPreviousContent
	        $Script:ExecutionLogBox = $null
	        $Script:ExecutionLastConsoleAction = $null
	        $Script:ExecutionProgressHost = $null
	        $Script:ExecutionProgressBar = $null
	        $Script:ExecutionProgressText = $null
	        $Script:AbortRunButton = $null
	        $Script:ExecutionLastProgressCompleted = -1
	        $Script:ExecutionWorker = $null
        $Script:ExecutionRunspace = $null
        $Script:ExecutionRunPowerShell = $null
        $Script:ExecutionRunTimer = $null
        $Script:ExecutionTimerErrorShown = $false
	        $Script:BgPS = $null
	        $Script:BgAsync = $null
	        $Script:ExecutionPreviousContent = $null
	        $previousFooterVisibility = $Script:ExecutionPreviousFooterVisibility
	        $Script:ExecutionPreviousFooterVisibility = $null
	        $Script:ExecutionCurrentSummaryKey = $null
	        $Script:ExecutionMode = $null

	        # Restore the outer ScrollViewer scrolling mode
	        $ContentScroll.VerticalScrollBarVisibility = 'Auto'

        # Reset run state
        if ($Script:GuiState) { & $Script:GuiState.Set 'RunInProgress' $false } else { $Script:RunInProgress = $false }

        # Restore filter bar, tab bar, and expert-mode banner
        if ($PrimaryTabs)
        {
            $PrimaryTabs.Visibility = [System.Windows.Visibility]::Visible
            if ((Test-GuiObjectField -Object $PrimaryTabs -FieldName 'IsEnabled'))
            {
                $PrimaryTabs.IsEnabled = $true
            }
        }
        if ($HeaderBorder) { $HeaderBorder.Visibility = [System.Windows.Visibility]::Visible }
        if ($ExpertModeBanner -and (Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-IsExpertModeUX))
        {
            $ExpertModeBanner.Visibility = [System.Windows.Visibility]::Visible
        }
        # Restore bottom action buttons
        if ($ActionButtonBar) { $ActionButtonBar.Visibility = if ($previousFooterVisibility -and $previousFooterVisibility.ActionButtonBar) { $previousFooterVisibility.ActionButtonBar } else { [System.Windows.Visibility]::Visible } }
        if ($BtnRun) { $BtnRun.Visibility = if ($previousFooterVisibility -and $previousFooterVisibility.BtnRun) { $previousFooterVisibility.BtnRun } else { [System.Windows.Visibility]::Visible } }
        if ($BtnDefaults) { $BtnDefaults.Visibility = if ($previousFooterVisibility -and $previousFooterVisibility.BtnDefaults) { $previousFooterVisibility.BtnDefaults } else { [System.Windows.Visibility]::Visible } }
        if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = if ($previousFooterVisibility -and $previousFooterVisibility.BtnPreviewRun) { $previousFooterVisibility.BtnPreviewRun } else { [System.Windows.Visibility]::Visible } }
        if ($StatusText) { $StatusText.Visibility = if ($previousFooterVisibility -and $previousFooterVisibility.StatusText) { $previousFooterVisibility.StatusText } else { [System.Windows.Visibility]::Visible } }
        # Re-enable controls
        if ($BtnDefaults) { $BtnDefaults.IsEnabled = $true }
        Set-GuiActionButtonsEnabled -Enabled $true
        if (Get-Command -Name 'Update-GuiScopedRunActionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Update-GuiScopedRunActionAvailability
        }
        if ($ChkScan) { $ChkScan.IsEnabled = $true }
        if ($ChkTheme) { $ChkTheme.IsEnabled = $true }
        Set-SearchControlsEnabled -Enabled $true
        if (Get-Command -Name 'Sync-UxActionButtonText' -CommandType Function -ErrorAction SilentlyContinue)
        {
            Sync-UxActionButtonText
        }
        elseif ($BtnRun)
        {
            $BtnRun.Content = Get-UxRunActionLabel
        }

        if ($Script:CurrentPrimaryTab)
        {
            try
            {
                Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
            }
            catch
            {
                LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionViewBuildTabContentFailed' -Fallback '[Exit-ExecutionView] Build-TabContent failed'))
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
		if ($Script:UpdateGuiBackToTopButtonScript)
		{
			try { & $Script:UpdateGuiBackToTopButtonScript } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionView.Exit.UpdateBackToTopButton' }
		}

			if ($deferAbortReset -and $Script:MainForm -and $Script:MainForm.Dispatcher)
			{
				try
				{
					$null = Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -PriorityUsage 'Pump' -Action {
						try { Reset-RunAbortState } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionView.Exit-ExecutionView:catch359' -Severity Debug }
						 $null = $_ }
					}
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'ExecutionView.Exit-ExecutionView:catch362' -Severity Debug }

					Reset-RunAbortState
				}
			}
			else
			{
				Reset-RunAbortState
			}

		LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogExecutionViewCompleted' -Fallback '[Exit-ExecutionView] COMPLETED - GUI restored')
    }
