foreach ($result in $displayResults)
	{
		if ($isPreviewMode)
		{
			$sectionLabel = if ($hasPreviewGroups -and (Test-GuiCommonObjectField -Object $result -FieldName 'PreviewGroupHeader') -and -not [string]::IsNullOrWhiteSpace([string]$result.PreviewGroupHeader)) {
				[string]$result.PreviewGroupHeader
			}
			elseif ([string]::IsNullOrWhiteSpace([string]$result.Status)) {
				'Will change'
			}
			else {
				[string]$result.Status
			}
			if ($sectionLabel -ne $lastPreviewSection)
			{
				$sectionHeader = New-Object System.Windows.Controls.TextBlock
				$sectionHeader.Text = $sectionLabel.ToUpperInvariant()
				$sectionHeader.FontSize = $Script:GuiLayout.FontSizeLabel
				$sectionHeader.FontWeight = [System.Windows.FontWeights]::Bold
				$sectionHeader.Foreground = $preBrushSectionLabel
				$sectionHeader.Margin = [System.Windows.Thickness]::new(0, $(if ($null -eq $lastPreviewSection) { 0 } else { 8 }), 0, 8)
				[void]($listStack.Children.Add($sectionHeader))
				$lastPreviewSection = $sectionLabel
			}
		}

		# Determine the status category for filtering and left-border color
		$cardStatusCategory = switch ([string]$result.Status)
		{
			'Success'         { 'Success'; break }
			'Skipped'         { 'Skipped'; break }
			'Not applicable'  { 'Skipped'; break }
			'Not Run'         { 'Skipped'; break }
			'Restart pending' { 'Restart pending'; break }
			'Failed'          { 'Failed'; break }
			default           { 'Success' }
		}

		$leftBorderColor = switch ($cardStatusCategory)
		{
			'Success'         { $bc.ConvertFromString($Theme.LowRiskBadge); break }
			'Skipped'         { $bc.ConvertFromString($Theme.BorderColor); break }
			'Failed'          { $bc.ConvertFromString($Theme.RiskHighBadge); break }
			'Restart pending' { $bc.ConvertFromString($Theme.RiskMediumBadge); break }
			default           { $bc.ConvertFromString($Theme.LowRiskBadge) }
		}

		$rowBorder = New-Object System.Windows.Controls.Border
		$rowBorder.Background = $preBrushCardBg
		$rowBorder.BorderBrush = $preBrushCardBorder
		$rowBorder.BorderThickness = [System.Windows.Thickness]::new(3, 1, 1, 1)
		$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
		$rowBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
		$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
		$rowBorder.Cursor = [System.Windows.Input.Cursors]::Hand

		# Color the left border by status category
		$rowBorder.BorderBrush = $leftBorderColor

		$rowStack = New-Object System.Windows.Controls.StackPanel
		$rowStack.Orientation = 'Vertical'

		$headerGrid = New-Object System.Windows.Controls.Grid
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })))
		$nameBlock = New-Object System.Windows.Controls.TextBlock
		$nameBlock.Text = [string]$result.Name
		$nameBlock.FontSize = 13
		$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
		$nameBlock.TextWrapping = 'Wrap'
		$nameBlock.Foreground = $preBrushTextPrimary
		[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
		[void]($headerGrid.Children.Add($nameBlock))
		$statusBorder = New-Object System.Windows.Controls.Border
		$statusBorder.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
		$statusBorder.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$statusBorder.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
		$statusBorder.BorderThickness = $preThickness1
		$statusText = New-Object System.Windows.Controls.TextBlock
		$statusText.Text = [string]$result.Status
		$statusText.FontSize = $Script:GuiLayout.FontSizeLabel
		$statusText.FontWeight = [System.Windows.FontWeights]::SemiBold

		$statusKey = [string]$result.Status
		$statusBrushSet = if ($preStatusBrushes.ContainsKey($statusKey)) { $preStatusBrushes[$statusKey] } else { $preDefaultStatusBrushes }
		$statusBorder.Background = $statusBrushSet.Bg
		$statusBorder.BorderBrush = $statusBrushSet.Border
		$statusText.Foreground = $statusBrushSet.Fg

		$statusBorder.Child = $statusText
		[System.Windows.Controls.Grid]::SetColumn($statusBorder, 1)
		[void]($headerGrid.Children.Add($statusBorder))
		[void]($rowStack.Children.Add($headerGrid))
		$metaParts = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Category)) { $metaParts += [string]$result.Category }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Selection)) { $metaParts += [string]$result.Selection }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Risk)) { $metaParts += ("{0} Risk" -f [string]$result.Risk) }
		if ($metaParts.Count -gt 0)
		{
			$metaBlock = New-Object System.Windows.Controls.TextBlock
			$metaBlock.Text = ($metaParts -join '  |  ')
			$metaBlock.TextWrapping = 'Wrap'
			$metaBlock.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
			$metaBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$metaBlock.Foreground = $preBrushTextMuted
			[void]($rowStack.Children.Add($metaBlock))
		}

		$chipItems = New-Object System.Collections.Generic.List[object]
		$typeLabel = $null
		$typeTone = 'Muted'
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'TypeBadgeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeBadgeLabel))
		{
			$typeLabel = [string]$result.TypeBadgeLabel
		}
		elseif ((Test-GuiCommonObjectField -Object $result -FieldName 'TypeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeLabel))
		{
			$typeLabel = [string]$result.TypeLabel
		}
		elseif ((Test-GuiCommonObjectField -Object $result -FieldName 'Type') -and -not [string]::IsNullOrWhiteSpace([string]$result.Type))
		{
			$typeLabel = [string]$result.Type
		}
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'TypeTone') -and -not [string]::IsNullOrWhiteSpace([string]$result.TypeTone))
		{
			$typeTone = [string]$result.TypeTone
		}
		elseif ($typeLabel -eq 'Uninstall / Remove')
		{
			$typeTone = 'Danger'
		}
		elseif ($typeLabel -eq 'Toggle')
		{
			$typeTone = 'Success'
		}
		elseif ($typeLabel -eq 'Choice')
		{
			$typeTone = 'Primary'
		}
		if (-not [string]::IsNullOrWhiteSpace($typeLabel))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $typeLabel
				Tone = $typeTone
				ToolTip = 'Type of tweak'
			})
		}

		$currentState = $null
		$currentStateTone = 'Muted'
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'CurrentState') -and -not [string]::IsNullOrWhiteSpace([string]$result.CurrentState))
		{
			$currentState = [string]$result.CurrentState
		}
		elseif ((Test-GuiCommonObjectField -Object $result -FieldName 'StateLabel') -and -not [string]::IsNullOrWhiteSpace([string]$result.StateLabel))
		{
			$currentState = [string]$result.StateLabel
		}
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'CurrentStateTone') -and -not [string]::IsNullOrWhiteSpace([string]$result.CurrentStateTone))
		{
			$currentStateTone = [string]$result.CurrentStateTone
		}
		elseif ($currentState -eq 'Enabled')
		{
			$currentStateTone = 'Success'
		}
		elseif ($currentState -eq 'Custom')
		{
			$currentStateTone = 'Primary'
		}
		if (-not [string]::IsNullOrWhiteSpace($currentState))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $currentState
				Tone = $currentStateTone
				ToolTip = 'Current state in the GUI'
			})
		}

		$outcomeState = $null
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'OutcomeState') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeState))
		{
			$outcomeState = [string]$result.OutcomeState
		}
		if (-not [string]::IsNullOrWhiteSpace($outcomeState))
		{
			$outcomeTone = switch -Regex ($outcomeState)
			{
				'^(Success|Already in desired state|Already at Windows default|Not applicable|Not applicable on this system)$' { 'Success'; break }
				'^(Restart pending|Failed and recoverable)$' { 'Caution'; break }
				'^(Skipped by preset or selection|Not supported by in-app restore)$' { 'Muted'; break }
				'^(Failed and manual intervention required|Not run)$' { 'Danger'; break }
				default { 'Muted' }
			}
			[void]$chipItems.Add([pscustomobject]@{
				Label = $outcomeState
				Tone = $outcomeTone
				ToolTip = 'Normalized execution outcome'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'FailureCategory') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCategory))
		{
			$failureCategory = [string]$result.FailureCategory
			$failureTone = switch -Regex ($failureCategory)
			{
				'^(Access denied|Reboot required|Missing dependency|Blocked by current system state|Network/download failure|Partial success|Manual intervention required|Unsupported OS/build)$' { 'Caution'; break }
				'^(Unsupported environment|Skipped by preset policy|Not supported by in-app restore)$' { 'Muted'; break }
				'^(Already in desired state|Not applicable|Not run)$' { 'Success'; break }
				default { 'Muted' }
			}
			[void]$chipItems.Add([pscustomobject]@{
				Label = $failureCategory
				Tone = $failureTone
				ToolTip = 'Failure category'
			})
		}

		if ([string]$result.Status -eq 'Failed' -and (Test-GuiCommonObjectField -Object $result -FieldName 'RetryAvailability') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryAvailability))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$result.RetryAvailability
				Tone = $(if ((Test-GuiCommonObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { 'Caution' } else { 'Danger' })
				ToolTip = 'Retry policy for this failure'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'FailureCode') -and -not [string]::IsNullOrWhiteSpace([string]$result.FailureCode))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$result.FailureCode
				Tone = 'Muted'
				ToolTip = 'Machine-readable failure code'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'RequiresRestart') -and [bool]$result.RequiresRestart)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Restart required'
				Tone = 'Caution'
				ToolTip = 'This change requires a restart to take effect.'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'TroubleshootingOnly') -and [bool]$result.TroubleshootingOnly)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Troubleshooting only'
				Tone = 'Caution'
				ToolTip = 'Use this only when diagnosing game compatibility, overlay, or display issues.'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'Restorable') -and $null -ne $result.Restorable -and -not [bool]$result.Restorable)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Manual recovery'
				Tone = 'Danger'
				ToolTip = 'This change cannot be fully rolled back automatically.'
			})
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryLevel))
		{
			$recoveryLevelLabel = [string]$result.RecoveryLevel
			$recoveryTone = switch ($recoveryLevelLabel)
			{
				'Direct' { 'Success'; break }
				'DefaultsOnly' { 'Primary'; break }
				'RestorePoint' { 'Caution'; break }
				'Manual' { 'Danger'; break }
				default { 'Muted' }
			}
				[void]$chipItems.Add([pscustomobject]@{
					Label = "Recovery: $recoveryLevelLabel"
					Tone = $recoveryTone
					ToolTip = 'Recommended recovery path for this tweak.'
				})
		}

		$scenarioTags = @()
		if ((Test-GuiCommonObjectField -Object $result -FieldName 'ScenarioTags') -and $result.ScenarioTags)
		{
			$scenarioTags = @($result.ScenarioTags)
		}
		elseif ((Test-GuiCommonObjectField -Object $result -FieldName 'Tags') -and $result.Tags)
		{
			$scenarioTags = @($result.Tags)
		}
		if ($scenarioTags.Count -gt 0)
		{
			foreach ($scenarioTag in @($scenarioTags | Select-Object -First 4))
			{
				if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
				[void]$chipItems.Add([pscustomobject]@{
					Label = [string]$scenarioTag
					Tone = 'Muted'
					ToolTip = 'Scenario tag'
				})
			}
			if ($scenarioTags.Count -gt 4)
			{
				[void]$chipItems.Add([pscustomobject]@{
					Label = "+$($scenarioTags.Count - 4) more"
					Tone = 'Muted'
					ToolTip = 'Additional scenario tags are present in the manifest.'
				})
			}
		}

		if ($chipItems.Count -gt 0)
		{
			$chipRow = New-Object System.Windows.Controls.Border
			$chipRow.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$chipRow.Child = (New-DialogMetadataPillPanel -Theme $Theme -Items $chipItems)
			[void]($rowStack.Children.Add($chipRow))
		}

		# -- Expandable detail section (collapsed by default) --
		$detailStack = New-Object System.Windows.Controls.StackPanel
		$detailStack.Orientation = 'Vertical'
		$detailStack.Visibility = [System.Windows.Visibility]::Collapsed

		# Expand/collapse hint text
		$expandDetailsText = if ($Strings.ContainsKey('ExpandDetails')) { [string]$Strings.ExpandDetails } else { 'Click to expand details' }
		$collapseDetailsText = if ($Strings.ContainsKey('CollapseDetails')) { [string]$Strings.CollapseDetails } else { 'Click to collapse' }
		$expandHint = New-Object System.Windows.Controls.TextBlock
		$expandHint.Text = [char]0x25BC + '  ' + $expandDetailsText
		$expandHint.FontSize = $Script:GuiLayout.FontSizeSmall
		$expandHint.Foreground = $preBrushTextMuted
		$expandHint.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$expandHint.HorizontalAlignment = 'Left'

		# Check if there are any details worth expanding
		$hasExpandableContent = (
			(-not [string]::IsNullOrWhiteSpace([string]$result.ReasonIncluded)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.OutcomeReason) -and (
				[string]$result.Status -in @('Failed', 'Skipped', 'Restart pending', 'Not Run', 'Not applicable') -or
				((Test-GuiCommonObjectField -Object $result -FieldName 'OutcomeState') -and [string]$result.OutcomeState -in @('Already in desired state', 'Already at Windows default', 'Not applicable on this system', 'Skipped by preset or selection', 'Not supported by in-app restore', 'Failed and recoverable', 'Failed and manual intervention required'))
			)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.Detail)) -or
			((Test-GuiCommonObjectField -Object $result -FieldName 'RecoveryHint') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryHint)) -or
			((Test-GuiCommonObjectField -Object $result -FieldName 'RetryReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryReason)) -or
			(-not [string]::IsNullOrWhiteSpace([string]$result.BlastRadius))
		)

		if ($hasExpandableContent)
		{
			[void]($rowStack.Children.Add($expandHint))

			# Wire click-to-expand on the card border
			$capturedDetailStack = $detailStack
			$capturedExpandHint = $expandHint
			$rowBorder.Add_MouseLeftButtonUp({
				if ($capturedDetailStack.Visibility -eq [System.Windows.Visibility]::Collapsed)
				{
					$capturedDetailStack.Visibility = [System.Windows.Visibility]::Visible
					$capturedExpandHint.Text = [string]([char]0x25B2) + '  ' + $collapseDetailsText
				}
				else
				{
					$capturedDetailStack.Visibility = [System.Windows.Visibility]::Collapsed
					$capturedExpandHint.Text = [string]([char]0x25BC) + '  ' + $expandDetailsText
				}
			}.GetNewClosure())
		}

		# All detail content goes into $detailStack instead of $rowStack
		if (-not [string]::IsNullOrWhiteSpace([string]$result.ReasonIncluded))
		{
			$reasonSeparator = New-Object System.Windows.Controls.Separator
			$reasonSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($reasonSeparator))
			$reasonHeader = New-Object System.Windows.Controls.TextBlock
			$reasonHeader.Text = (& $L 'GuiCommonWhyIncluded' 'WHY INCLUDED')
			$reasonHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$reasonHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$reasonHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($reasonHeader))
			$reasonBlock = New-Object System.Windows.Controls.TextBlock
			$reasonBlock.Text = [string]$result.ReasonIncluded
			$reasonBlock.TextWrapping = 'Wrap'
			$reasonBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$reasonBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$reasonBlock.Foreground = $preBrushTextSecondary
			[void]($detailStack.Children.Add($reasonBlock))
		}

		$outcomeReasonStatus = if ((Test-GuiCommonObjectField -Object $result -FieldName 'Status')) { [string]$result.Status } else { '' }
		$outcomeReasonState = if ((Test-GuiCommonObjectField -Object $result -FieldName 'OutcomeState')) { [string]$result.OutcomeState } else { '' }
		$showOutcomeReason = (
			$outcomeReasonStatus -in @('Failed', 'Skipped', 'Restart pending', 'Not Run', 'Not applicable') -or
			$outcomeReasonState -in @('Already in desired state', 'Already at Windows default', 'Not applicable on this system', 'Skipped by preset or selection', 'Not supported by in-app restore', 'Failed and recoverable', 'Failed and manual intervention required')
		)

		if ($showOutcomeReason -and (Test-GuiCommonObjectField -Object $result -FieldName 'OutcomeReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.OutcomeReason))
		{
			$outcomeReasonSeparator = New-Object System.Windows.Controls.Separator
			$outcomeReasonSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($outcomeReasonSeparator))
			$outcomeReasonHeader = New-Object System.Windows.Controls.TextBlock
			$outcomeReasonHeader.Text = (& $L 'GuiCommonWhyThisHappened' 'WHY THIS HAPPENED')
			$outcomeReasonHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$outcomeReasonHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$outcomeReasonHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($outcomeReasonHeader))
			$outcomeReasonBlock = New-Object System.Windows.Controls.TextBlock
			$outcomeReasonBlock.Text = [string]$result.OutcomeReason
			$outcomeReasonBlock.TextWrapping = 'Wrap'
			$outcomeReasonBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$outcomeReasonBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$outcomeReasonBlock.Foreground = $(if ($result.Status -eq 'Failed' -or $result.Status -eq 'Not Run') { $preBrushTextPrimary } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($outcomeReasonBlock))
		}

		if ([string]$result.Status -eq 'Failed' -and (Test-GuiCommonObjectField -Object $result -FieldName 'RetryReason') -and -not [string]::IsNullOrWhiteSpace([string]$result.RetryReason))
		{
			$retrySeparator = New-Object System.Windows.Controls.Separator
			$retrySeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($retrySeparator))
			$retryHeader = New-Object System.Windows.Controls.TextBlock
			$retryHeader.Text = (& $L 'GuiCommonRetryPolicy' 'RETRY POLICY')
			$retryHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$retryHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$retryHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($retryHeader))
			$retryBlock = New-Object System.Windows.Controls.TextBlock
			$retryBlock.Text = [string]$result.RetryReason
			$retryBlock.TextWrapping = 'Wrap'
			$retryBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$retryBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$retryBlock.Foreground = $(if ((Test-GuiCommonObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($retryBlock))
		}

		if ((Test-GuiCommonObjectField -Object $result -FieldName 'RecoveryHint') -and -not [string]::IsNullOrWhiteSpace([string]$result.RecoveryHint))
		{
			$hintSeparator = New-Object System.Windows.Controls.Separator
			$hintSeparator.Margin = [System.Windows.Thickness]::new(0, 8, 0, 8)
			[void]($detailStack.Children.Add($hintSeparator))
			$hintHeader = New-Object System.Windows.Controls.TextBlock
			$hintHeader.Text = (& $L 'GuiCommonRecoveryHint' 'RECOVERY HINT')
			$hintHeader.FontSize = $Script:GuiLayout.FontSizeSmall
			$hintHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$hintHeader.Foreground = $preBrushSectionLabel
			[void]($detailStack.Children.Add($hintHeader))
			$hintBlock = New-Object System.Windows.Controls.TextBlock
			$hintBlock.Text = [string]$result.RecoveryHint
			$hintBlock.TextWrapping = 'Wrap'
			$hintBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$hintBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$hintBlock.Foreground = $(if ((Test-GuiCommonObjectField -Object $result -FieldName 'IsRecoverable') -and [bool]$result.IsRecoverable) { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($hintBlock))
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$result.BlastRadius))
		{
			$blastBlock = New-Object System.Windows.Controls.TextBlock
			$blastBlock.Text = [string]$result.BlastRadius
			$blastBlock.TextWrapping = 'Wrap'
			$blastBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$blastBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$blastBlock.Foreground = $preBrushTextSecondary
			[void]($detailStack.Children.Add($blastBlock))
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$result.Detail))
		{
			$detailBlock = New-Object System.Windows.Controls.TextBlock
			$detailBlock.Text = [string]$result.Detail
			$detailBlock.TextWrapping = 'Wrap'
			$detailBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$detailBlock.FontSize = $Script:GuiLayout.FontSizeLabel
			$detailBlock.Foreground = $(if ($result.Status -eq 'Failed' -or $result.Status -eq 'Not Run') { $preBrushCautionText } else { $preBrushTextSecondary })
			[void]($detailStack.Children.Add($detailBlock))
		}

		# Add the collapsible detail panel to the card
		if ($hasExpandableContent)
		{
			[void]($rowStack.Children.Add($detailStack))
		}

		$rowBorder.Child = $rowStack
		[void]($listStack.Children.Add($rowBorder))

		# Track card for status filter bar
		[void]$allResultCards.Add($rowBorder)
		[void]$allResultStatusMap.Add($cardStatusCategory)

		$resultIndex++

		# After the initial batch, stop building cards and insert a
		# "Show all" button so the dialog opens fast for large result sets.
		if ($resultIndex -eq $initialBatchLimit -and $totalResultCount -gt $initialBatchLimit)
		{
			break
		}
	}
