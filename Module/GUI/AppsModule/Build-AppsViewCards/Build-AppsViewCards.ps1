foreach ($app in @($sortedCatalog))
	{
		if (-not $app)
		{
			continue
		}

		$selectionCheckBox = $null
		$primaryButton = $null
		$updateButton = $null
		$appCapture = $null
		$isInstalledCapture = $false

		$appState = Get-ApplicationExecutionState -Entry $app -WinGetInstalledCache $installedWingetCache -ChocolateyInstalledCache $installedChocolateyCache -WinGetUpdateCache $wingetUpdateCache -ChocolateyUpdateCache $chocolateyUpdateCache -PreferredSource $Script:AppsPackageSourcePreference
		$entityType = [string]$appState.EntityType
		$supportsExecution = [bool]$appState.SupportsExecution
		$isInstalled = [bool]$appState.IsInstalled
		$hasUpdateAvailable = [bool]$appState.UpdateAvailable
		if ($isInstalled) { $installedCount++ }
		if ($hasUpdateAvailable) { $updateAvailableCount++ }
		$selectionKeyCapture = [string]$appState.SelectionKey
		$appActionState = if (-not [string]::IsNullOrWhiteSpace($selectionKeyCapture)) { Get-AppActionState -Application $app -SelectionKey $selectionKeyCapture } else { $null }

		$statusLabel = if ($appActionState)
		{
			switch ([string]$appActionState.State)
			{
				'Queued' { (Get-UxLocalizedString -Key 'GuiAppsQueued' -Fallback 'Queued') }
				'Installing' { (Get-UxLocalizedString -Key 'GuiAppsInstalling' -Fallback 'Installing') }
				'Failed' { (Get-UxLocalizedString -Key 'GuiAppsFailed' -Fallback 'Failed') }
				default
				{
					switch ($appState.State)
					{
						'Installed' { (Get-UxLocalizedString -Key 'Status_Installed' -Fallback 'Installed') }
						'Update available' { (Get-UxLocalizedString -Key 'GuiAppsUpdateAvailable' -Fallback 'Update available') }
						'Unsupported' { (Get-UxLocalizedString -Key 'GuiAppsUnsupportedAction' -Fallback 'Unsupported') }
						default { (Get-UxLocalizedString -Key 'Status_NotInstalled' -Fallback 'Not Installed') }
					}
				}
			}
		}
		else
		{
			switch ($appState.State)
			{
				'Installed' { (Get-UxLocalizedString -Key 'Status_Installed' -Fallback 'Installed') }
				'Update available' { (Get-UxLocalizedString -Key 'GuiAppsUpdateAvailable' -Fallback 'Update available') }
				'Unsupported' { (Get-UxLocalizedString -Key 'GuiAppsUnsupportedAction' -Fallback 'Unsupported') }
				default { (Get-UxLocalizedString -Key 'Status_NotInstalled' -Fallback 'Not Installed') }
			}
		}
		if (-not $cacheReady -and $supportsExecution)
		{
			$statusLabel = (Get-UxLocalizedString -Key 'GuiAppsCacheRefreshRequired' -Fallback 'Installed status not scanned')
		}
		$statusForeground = if ($appActionState)
		{
			switch ([string]$appActionState.State)
			{
				'Queued' { $theme.AccentBlue }
				'Installing' { $theme.AccentBlue }
				'Failed' { $theme.CautionBorder }
				default
				{
					switch ($appState.State)
					{
						'Installed' { $theme.ToggleOn }
						'Update available' { $theme.AccentBlue }
						'Unsupported' { $theme.TextMuted }
						default { $theme.TextMuted }
					}
				}
			}
		}
		if (-not $cacheReady -and $supportsExecution)
		{
			$statusForeground = $theme.TextMuted
		}
		else
		{
			switch ($appState.State)
			{
				'Installed' { $theme.ToggleOn }
				'Update available' { $theme.AccentBlue }
				'Unsupported' { $theme.TextMuted }
				default { $theme.TextMuted }
			}
		}

		$primaryAction = if ($supportsExecution)
		{
			if ($isInstalled)
			{
				(Get-UxLocalizedString -Key 'Uninstall' -Fallback 'Uninstall')
			}
			else
			{
				(Get-UxLocalizedString -Key 'Install' -Fallback 'Install')
			}
		}
		else
		{
			(Get-UxLocalizedString -Key 'GuiAppsUnsupportedAction' -Fallback 'Unsupported')
		}
		$selectedSource = if ($appState -and $appState.PSObject.Properties['SelectedSource']) { [string]$appState.SelectedSource } else { $null }
		$selectedSourceLabel = switch ($selectedSource)
		{
			'winget' { (Get-UxLocalizedString -Key 'GuiAppsSourceWinGet' -Fallback 'WinGet') }
			'choco' { (Get-UxLocalizedString -Key 'GuiAppsSourceChocolatey' -Fallback 'Chocolatey') }
			'store' { (Get-UxLocalizedString -Key 'GuiAppsSourceStore' -Fallback 'Store') }
			'direct' { (Get-UxLocalizedString -Key 'GuiAppsSourceDirect' -Fallback 'Direct Download') }
			'command' { (Get-UxLocalizedString -Key 'GuiAppsSourceCommand' -Fallback 'Custom Command') }
			default { $null }
		}
		$selectedSourceTooltip = switch ($selectedSource)
		{
			'winget' { (Get-UxLocalizedString -Key 'GuiAppsSourceWinGetTip' -Fallback 'This app will use WinGet for the selected action.') }
			'choco' { (Get-UxLocalizedString -Key 'GuiAppsSourceChocolateyTip' -Fallback 'This app will use Chocolatey for the selected action.') }
			'store' { (Get-UxLocalizedString -Key 'GuiAppsSourceStoreTip' -Fallback 'This app opens the Microsoft Store for the selected action.') }
			'direct' { (Get-UxLocalizedString -Key 'GuiAppsSourceDirectTip' -Fallback 'This app uses a direct download route for the selected action.') }
			'command' { (Get-UxLocalizedString -Key 'GuiAppsSourceCommandTip' -Fallback 'This app uses a custom command route for the selected action.') }
			default { $null }
		}
		$statusTone = if ($appActionState)
		{
			switch ([string]$appActionState.State)
			{
				'Queued' { 'Primary' }
				'Installing' { 'Caution' }
				'Failed' { 'Danger' }
				default
				{
					switch ($appState.State)
					{
						'Installed' { 'Success' }
						'Update available' { 'Primary' }
						'Unsupported' { 'Muted' }
						default { 'Muted' }
					}
				}
			}
		}
		else
		{
			switch ($appState.State)
			{
				'Installed' { 'Success' }
				'Update available' { 'Primary' }
				'Unsupported' { 'Muted' }
				default { 'Muted' }
			}
		}
		$statusTooltip = if ($appActionState -and -not [string]::IsNullOrWhiteSpace([string]$appActionState.Message))
		{
			[string]$appActionState.Message
		}
		else
		{
			switch ([string]$appState.State)
			{
				'Installed' { (Get-UxLocalizedString -Key 'GuiAppsStatusInstalledTip' -Fallback 'This app is currently installed.') }
				'Update available' { (Get-UxLocalizedString -Key 'GuiAppsStatusUpdateAvailableTip' -Fallback 'An update is available for this app.') }
				'Unsupported' { (Get-UxLocalizedString -Key 'GuiAppsStatusUnsupportedTip' -Fallback 'This catalog entry does not support direct execution.') }
				default { (Get-UxLocalizedString -Key 'GuiAppsStatusNotInstalledTip' -Fallback 'This app is not currently installed.') }
			}
		}
		if (-not $cacheReady -and $supportsExecution)
		{
			$statusTooltip = $cacheRefreshPrompt
		}
		$isAppActionBusy = $appActionState -and @('Queued', 'Installing') -contains [string]$appActionState.State
		$appIconName = if (Get-Command -Name 'Get-GuiApplicationIconName' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Get-GuiApplicationIconName -Name $app.Name -SubCategory $app.SubCategory -Tags $app.Tags -SourceRegion $app.SourceRegion
		}
		else
		{
			'AppGeneric'
		}
		$appsViewModeLocal = if ([string]::IsNullOrWhiteSpace([string]$Script:AppsViewMode)) { 'Cards' } else { [string]$Script:AppsViewMode }
		$card = [System.Windows.Controls.Border]::new()
		if ($appsViewModeLocal -eq 'List')
		{
			$listWidthBinding = [System.Windows.Data.Binding]::new('ActualWidth')
			$listWidthBinding.Source = $Script:AppsWrapPanel
			$listWidthBinding.Mode = [System.Windows.Data.BindingMode]::OneWay
			$null = [System.Windows.Data.BindingOperations]::SetBinding($card, [System.Windows.Controls.Border]::WidthProperty, $listWidthBinding)
			$card.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
			$card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
			$card.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
		}
		else
		{
			$card.Width = 340
			$card.Margin = [System.Windows.Thickness]::new(8)
			$card.Padding = [System.Windows.Thickness]::new(16)
		}
		$card.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$card.Background = $bc.ConvertFromString($theme.CardBg)
		$card.BorderBrush = $bc.ConvertFromString($theme.CardBorder)
		$card.BorderThickness = [System.Windows.Thickness]::new(1)

		$stack = [System.Windows.Controls.StackPanel]::new()
		$stack.Orientation = 'Vertical'

		$headerGrid = [System.Windows.Controls.Grid]::new()
		$headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
		$headerGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
		$headerGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
		$headerGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::Auto
		$headerGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)

		if ($appIconName)
		{
			$appIcon = New-GuiIconTextBlock -IconName $appIconName -Size 18 -Foreground $bc.ConvertFromString($theme.AccentBlue) -VerticalAlignment 'Center'
			if ($appIcon)
			{
				$appIcon.Margin = [System.Windows.Thickness]::new(0, 1, 12, 0)
				[System.Windows.Controls.Grid]::SetColumn($appIcon, 0)
				[void]$headerGrid.Children.Add($appIcon)
			}
		}

		$title = [System.Windows.Controls.TextBlock]::new()
		$title.Text = [string]$app.Name
		$title.FontSize = 14
		$title.FontWeight = [System.Windows.FontWeights]::Bold
		$title.TextWrapping = 'Wrap'
		$title.Foreground = $bc.ConvertFromString($theme.TextPrimary)
		[System.Windows.Controls.Grid]::SetColumn($title, 1)
		[void]$headerGrid.Children.Add($title)
		[void]$stack.Children.Add($headerGrid)

		if (-not [string]::IsNullOrWhiteSpace([string]$app.SubCategory))
		{
			$subTitle = [System.Windows.Controls.TextBlock]::new()
			$subTitle.Text = [string]$app.SubCategory
			$subTitle.FontSize = 10
			$subTitle.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
			$subTitle.Foreground = $bc.ConvertFromString($theme.SectionLabel)
			[void]$stack.Children.Add($subTitle)
		}

		if (-not [string]::IsNullOrWhiteSpace($entityType) -and @('winget','choco') -notcontains $entityType)
		{
			$typeBadge = [System.Windows.Controls.TextBlock]::new()
			$typeBadge.Text = switch ($entityType)
			{
				'uwp' { (Get-UxLocalizedString -Key 'AppTypeBadgeUWP' -Fallback 'UWP app') }
				'feature' { (Get-UxLocalizedString -Key 'AppTypeBadgeFeature' -Fallback 'Windows feature') }
				'system' { (Get-UxLocalizedString -Key 'AppTypeBadgeSystem' -Fallback 'System component') }
				'store' { (Get-UxLocalizedString -Key 'AppTypeBadgeStore' -Fallback 'Microsoft Store') }
				'direct' { (Get-UxLocalizedString -Key 'AppTypeBadgeDirect' -Fallback 'Direct download') }
				'command' { (Get-UxLocalizedString -Key 'AppTypeBadgeCommand' -Fallback 'Command') }
				'placeholder' { (Get-UxLocalizedString -Key 'AppTypeBadgePlaceholder' -Fallback 'No install method') }
				default { [string]$entityType }
			}
			$typeBadge.FontSize = 9
			$typeBadge.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$typeBadge.Foreground = $bc.ConvertFromString($theme.TextMuted)
			[void]$stack.Children.Add($typeBadge)
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$app.Description))
		{
			$description = [System.Windows.Controls.TextBlock]::new()
			$description.Text = [string]$app.Description
			$description.TextWrapping = 'Wrap'
			$description.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$description.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			[void]$stack.Children.Add($description)
		}

		$metadataItems = [System.Collections.Generic.List[object]]::new()
		if (-not [string]::IsNullOrWhiteSpace($statusLabel))
		{
			[void]$metadataItems.Add([pscustomobject]@{
				Label = $statusLabel
				Tone = $statusTone
				ToolTip = $statusTooltip
			})
		}
		if (-not [string]::IsNullOrWhiteSpace($selectedSourceLabel))
		{
			[void]$metadataItems.Add([pscustomobject]@{
				Label = $selectedSourceLabel
				Tone = 'Primary'
				ToolTip = $selectedSourceTooltip
			})
		}
		if ($metadataItems.Count -gt 0)
		{
			$metadataPanel = GUICommon\New-DialogMetadataPillPanel -Theme $theme -Items $metadataItems
			if ($metadataPanel)
			{
				$metadataPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
				[void]$stack.Children.Add($metadataPanel)
			}
		}

			if ($supportsExecution)
			{
				$selectionRow = [System.Windows.Controls.DockPanel]::new()
				$selectionRow.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
				$selectionRow.LastChildFill = $false

				$selectionCheckBox = [System.Windows.Controls.CheckBox]::new()
				$selectionCheckBox.Content = (Get-UxLocalizedString -Key 'GuiAppsSelectLabel' -Fallback 'Select')
				$selectionCheckBox.Margin = [System.Windows.Thickness]::new(0)
				$selectionCheckBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
				$selectionCheckBox.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
				$selectionCheckBox.ToolTip = (Get-UxLocalizedString -Key 'GuiAppsSelectTooltip' -Fallback 'Include this app in bulk actions.')
				$selectionCheckBox.Foreground = $bc.ConvertFromString($theme.TextPrimary)
				$selectionCheckBox.Tag = $selectionKeyCapture
				$selectionCheckBox.IsChecked = [bool]($Script:SelectedAppIds -and $Script:SelectedAppIds.Contains($selectionKeyCapture))
				$selectionCheckBox.Add_Checked({
					if ($Script:AppsSelectionUiUpdating) { return }
					& $setAppSelectionStateCommand -SelectionKey $selectionKeyCapture -Selected $true
				}.GetNewClosure())
				$selectionCheckBox.Add_Unchecked({
					if ($Script:AppsSelectionUiUpdating) { return }
					& $setAppSelectionStateCommand -SelectionKey $selectionKeyCapture -Selected $false
				}.GetNewClosure())
				[System.Windows.Controls.DockPanel]::SetDock($selectionCheckBox, [System.Windows.Controls.Dock]::Right)
				[void]$selectionRow.Children.Add($selectionCheckBox)
				[void]$Script:AppsSelectionControls.Add($selectionCheckBox)
				[void]$stack.Children.Add($selectionRow)

			$buttonRow = [System.Windows.Controls.WrapPanel]::new()
			$buttonRow.Orientation = 'Horizontal'
			$buttonRow.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)

			$appCapture = $app
			$primaryActionKind = if ($isInstalled) { 'Uninstall' } else { 'Install' }
			$primaryActionRequiresCache = ($primaryActionKind -ne 'Install')
			$queuedActionForApp = Get-AppQueuedAction -AppId $selectionKeyCapture
			$primaryButton = [System.Windows.Controls.Button]::new()
			$primaryButton.Content = $primaryAction
			$primaryButton.MinWidth = 88
			$primaryButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
			$primaryButton.Cursor = [System.Windows.Input.Cursors]::Hand
			$primaryButton.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and (-not $isAppActionBusy) -and ((-not $primaryActionRequiresCache) -or $cacheReady)
			$appCardWinGetId = $null
			$appCardChocoId = $null
			if ($appCapture.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$appCapture.WinGetId))
			{
				$appCardWinGetId = [string]$appCapture.WinGetId
			}
			elseif ($appCapture.ExtraArgs -and $appCapture.ExtraArgs.PSObject.Properties['WinGetId'] -and -not [string]::IsNullOrWhiteSpace([string]$appCapture.ExtraArgs.WinGetId))
			{
				$appCardWinGetId = [string]$appCapture.ExtraArgs.WinGetId
			}
			if ($appCapture.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$appCapture.ChocoId))
			{
				$appCardChocoId = [string]$appCapture.ChocoId
			}
			elseif ($appCapture.ExtraArgs -and $appCapture.ExtraArgs.PSObject.Properties['ChocoId'] -and -not [string]::IsNullOrWhiteSpace([string]$appCapture.ExtraArgs.ChocoId))
			{
				$appCardChocoId = [string]$appCapture.ExtraArgs.ChocoId
			}
			$hasMultipleSources = (-not [string]::IsNullOrWhiteSpace($appCardWinGetId)) -and (-not [string]::IsNullOrWhiteSpace($appCardChocoId))

			$primaryButton.ToolTip = if ($primaryActionKind -eq 'Install')
			{
				if ($hasMultipleSources -and -not [string]::IsNullOrWhiteSpace($selectedSourceLabel))
				{
					(Get-UxLocalizedString -Key 'GuiAppsQueueInstallViaSourceTip' -Fallback ('Will install via {0} (preferred). It runs when you click Apply Changes.' -f $selectedSourceLabel))
				}
				else
				{
					(Get-UxLocalizedString -Key 'Tooltip_QueueInstallApplication' -Fallback 'Stage an install for this app. It runs when you click Apply Changes.')
				}
			}
			else
			{
				(Get-UxLocalizedString -Key 'Tooltip_QueueUninstallApplication' -Fallback 'Stage an uninstall for this app. It runs when you click Apply Changes.')
			}
			Set-ButtonChrome -Button $primaryButton -Variant 'Primary' -Compact
			$primaryButtonIcon = if ($primaryActionKind -eq 'Install') { 'ArrowDownload' } else { 'Delete' }
			Set-GuiButtonIconContent -Button $primaryButton -IconName $primaryButtonIcon -Text $primaryAction -IconSize 14 -Gap 6 -TextFontSize 11 -ToolTip $primaryButton.ToolTip
			[void]$Script:AppsActionButtons.Add($primaryButton)
			$capturedPrimaryAction = $primaryActionKind
			$primaryButton.Add_Click({
				param($buttonSender, $buttonEventArgs)
				$null = $buttonEventArgs
				try
				{
					$current = Get-AppQueuedAction -AppId $selectionKeyCapture
					$desired = if ($current -eq $capturedPrimaryAction) { 'DoNothing' } else { $capturedPrimaryAction }
					& $setAppQueuedActionCommand -AppId $selectionKeyCapture -Action $desired
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\AppsModule\Build-AppsViewCards\Build-AppsViewCards.ps1:393' -Severity Debug }

					$null = & $showGuiRuntimeFailureCommand -Context 'AppPrimaryButton' -Exception $_.Exception -ShowDialog
				}
			}.GetNewClosure())
			[void]$buttonRow.Children.Add($primaryButton)

			$updateButton = $null
			if ($isInstalled -or $hasUpdateAvailable)
			{
				$updateButton = [System.Windows.Controls.Button]::new()
				$updateButton.Content = (Get-UxLocalizedString -Key 'Update' -Fallback 'Update')
				$updateButton.MinWidth = 88
				$updateButton.Cursor = [System.Windows.Input.Cursors]::Hand
				$updateButton.IsEnabled = -not $isAppActionBusy
				$updateButton.ToolTip = if (-not [string]::IsNullOrWhiteSpace($selectedSourceLabel))
				{
					(Get-UxLocalizedString -Key 'GuiAppsQueueUpdateViaSourceTip' -Fallback ('Stage an update using {0}. It runs when you click Apply Changes.' -f $selectedSourceLabel))
				}
				else
				{
					(Get-UxLocalizedString -Key 'Tooltip_QueueUpdateApplication' -Fallback 'Stage an update for this app. It runs when you click Apply Changes.')
				}
				Set-ButtonChrome -Button $updateButton -Variant 'Secondary' -Compact
				Set-GuiButtonIconContent -Button $updateButton -IconName 'ArrowSync' -Text (Get-UxLocalizedString -Key 'Update' -Fallback 'Update') -IconSize 14 -Gap 6 -TextFontSize 11 -ToolTip $updateButton.ToolTip
				[void]$Script:AppsActionButtons.Add($updateButton)
				$updateButton.Add_Click({
					param($buttonSender, $buttonEventArgs)
					$null = $buttonEventArgs
					try
					{
						$current = Get-AppQueuedAction -AppId $selectionKeyCapture
						$desired = if ($current -eq 'Update') { 'DoNothing' } else { 'Update' }
						& $setAppQueuedActionCommand -AppId $selectionKeyCapture -Action $desired
					}
					catch
					{
						if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\AppsModule\Build-AppsViewCards\Build-AppsViewCards.ps1:428' -Severity Debug }

						$null = & $showGuiRuntimeFailureCommand -Context 'AppUpdateButton' -Exception $_.Exception -ShowDialog
					}
				}.GetNewClosure())
				[void]$buttonRow.Children.Add($updateButton)
			}

			[void]$stack.Children.Add($buttonRow)

			# Queued-state badge, shown only when this app has a staged action.
			$queuedBadge = [System.Windows.Controls.Border]::new()
			$queuedBadge.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$queuedBadge.CornerRadius = [System.Windows.CornerRadius]::new(4)
			$queuedBadge.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
			$queuedBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
			$queuedBadge.Visibility = [System.Windows.Visibility]::Collapsed
			$queuedBadgeText = [System.Windows.Controls.TextBlock]::new()
			$queuedBadgeText.FontSize = 11
			$queuedBadgeText.FontWeight = [System.Windows.FontWeights]::SemiBold
			$queuedBadgeText.Text = ''
			$queuedBadge.Child = $queuedBadgeText
			Set-GuiAppsQueuedBadgeChrome -Badge $queuedBadge -BadgeText $queuedBadgeText
			[void]$stack.Children.Add($queuedBadge)

			# Register controls so Sync-AppsQueuedActionControls can refresh button chrome
			# and badge visibility whenever the staged action for this app changes.
			if (-not [string]::IsNullOrWhiteSpace($selectionKeyCapture))
			{
				$Script:AppsQueuedActionControlMap[$selectionKeyCapture] = [pscustomobject]@{
					PrimaryButton     = $primaryButton
					PrimaryActionKind = $primaryActionKind
					UpdateButton      = $updateButton
					Badge             = $queuedBadge
					BadgeText         = $queuedBadgeText
				}
				[void]$Script:AppsQueuedActionControls.Add([pscustomobject]@{
					AppId = $selectionKeyCapture
				})
				Sync-AppsQueuedActionControls -AppId $selectionKeyCapture
			}
		}
		else
		{
			$unsupportedText = [System.Windows.Controls.TextBlock]::new()
			$unsupportedText.Text = (Get-UxLocalizedString -Key 'GuiAppsUnsupportedAction' -Fallback 'No install method available.')
			$unsupportedText.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
			$unsupportedText.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$unsupportedText.FontSize = 10
			$unsupportedText.Foreground = $bc.ConvertFromString($theme.TextMuted)
			[void]$stack.Children.Add($unsupportedText)
		}

		$card.Child = $stack

		if (Get-Command -Name 'Add-CardHoverEffects' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$focusSources = @()
			if ($selectionCheckBox) { $focusSources += $selectionCheckBox }
			if ($primaryButton) { $focusSources += $primaryButton }
			if ($updateButton) { $focusSources += $updateButton }
			if ($focusSources.Count -gt 0)
			{
				try { Add-CardHoverEffects -Card $card -FocusSources $focusSources } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.AddCardHoverEffects' }
			}
		}

		[void]$Script:AppsWrapPanel.Children.Add($card)
		if (($Script:AppsWrapPanel.Children.Count % 10) -eq 0)
		{
			try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.DispatcherYield' }
		}
	}
