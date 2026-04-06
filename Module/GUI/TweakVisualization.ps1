# Tweak visualization helpers: visual metadata, chip panels, section headers, caution sections, execution log, file-save dialog

	function Get-TweakVisualMetadata
	{
		param (
			[object]$Tweak,
			[object]$StateSource
		)

		if (-not $Tweak) { return $null }

		$source = if ($StateSource) { $StateSource } else { $Tweak }
		$typeKind = if (-not [string]::IsNullOrWhiteSpace([string]$Tweak.Type)) { [string]$Tweak.Type } else { 'Action' }
		$isRemoval = Test-TweakRemovalOperation -Tweak $Tweak
		$isPackageOperation = Test-TweakPackageOperation -Tweak $Tweak

		$typeLabel = if ($isPackageOperation)
		{
			switch ($typeKind)
			{
				'Action' { 'Package / app setup' }
				default { 'Package / app change' }
			}
		}
		else
		{
			switch ($typeKind)
			{
				'Toggle' { 'Toggle' }
				'Choice' { if ($isRemoval) { 'Uninstall / Remove' } else { 'Choice' } }
				'Action' { if ($isRemoval) { 'Uninstall / Remove' } else { 'Action' } }
				default { if ($isRemoval) { 'Uninstall / Remove' } else { $typeKind } }
			}
		}

		$typeTone = switch ($typeLabel)
		{
			'Package / app setup' { if ([string]$Tweak.Risk -eq 'High') { 'Danger' } else { 'Caution' } }
			'Package / app change' { if ($isRemoval -or [string]$Tweak.Risk -eq 'High') { 'Danger' } else { 'Caution' } }
			'Uninstall / Remove' { 'Danger' }
			'Toggle' { 'Success' }
			'Choice' { 'Primary' }
			'Action' { 'Muted' }
			default { 'Muted' }
		}
		$typeBadgeLabel = switch ($typeLabel)
		{
			'Package / app setup' { 'Package setup' }
			'Package / app change' { 'Package change' }
			'Toggle' { 'Toggle setting' }
			'Choice' { 'Choice option' }
			'Action' { 'One-time action' }
			'Uninstall / Remove' { 'Remove / uninstall' }
			default { $typeLabel }
		}

		$stateLabel = $null
		$stateTone = 'Muted'
		$stateDetail = $null
		$matchesDesired = $false

		switch ($typeKind)
		{
			'Toggle'
			{
				$defaultOn = if (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'Default') } else { $false }
				$currentOn = if (Test-GuiObjectField -Object $source -FieldName 'IsChecked') { [bool](Get-GuiObjectField -Object $source -FieldName 'IsChecked') } elseif (Test-GuiObjectField -Object $source -FieldName 'CurrentValue') { [bool](Get-GuiObjectField -Object $source -FieldName 'CurrentValue') } else { $defaultOn }

				if ($currentOn -eq $defaultOn)
				{
					$stateLabel = 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = 'Already set to the manifest default.'
				}
				elseif ($currentOn)
				{
					$stateLabel = 'Enabled'
					$stateTone = 'Success'
					$stateDetail = 'Enabled in the current selection.'
				}
				else
				{
					$stateLabel = 'Disabled'
					$stateTone = 'Muted'
					$stateDetail = 'Disabled in the current selection.'
				}
			}
			'Choice'
			{
				$displayOpts = if ($Tweak.DisplayOptions) { @($Tweak.DisplayOptions) } else { @($Tweak.Options) }
				$selectedIndex = if (Test-GuiObjectField -Object $source -FieldName 'SelectedIndex') { [int](Get-GuiObjectField -Object $source -FieldName 'SelectedIndex') } else { -1 }
				$selectedValue = if ($selectedIndex -ge 0 -and $selectedIndex -lt $displayOpts.Count) { [string]$displayOpts[$selectedIndex] } else { $null }
				$defaultIndex = -1
				if ((Test-GuiObjectField -Object $Tweak -FieldName 'Default') -and $Tweak.Options)
				{
					$defaultIndex = [array]::IndexOf(@($Tweak.Options), $Tweak.Default)
				}
				$defaultValue = if ($defaultIndex -ge 0 -and $defaultIndex -lt $displayOpts.Count) { [string]$displayOpts[$defaultIndex] } elseif (Test-GuiObjectField -Object $Tweak -FieldName 'Default') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'Default') } else { $null }

				if ($selectedIndex -lt 0)
				{
					$stateLabel = 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = 'No explicit choice selected.'
				}
				elseif (($defaultIndex -ge 0 -and $selectedIndex -eq $defaultIndex) -or ([string]$selectedValue -eq [string]$defaultValue))
				{
					$stateLabel = 'Already set'
					$stateTone = 'Muted'
					$matchesDesired = $true
					$stateDetail = if ($selectedValue) { "Already set to the manifest default: $selectedValue." } else { 'Already set to the manifest default.' }
				}
				else
				{
					$stateLabel = 'Custom'
					$stateTone = 'Primary'
					$stateDetail = if ($selectedValue) { "Current choice: $selectedValue." } else { 'A non-default choice is selected.' }
				}
			}
			'Action'
			{
				$isSelected = if (Test-GuiObjectField -Object $source -FieldName 'IsChecked') { [bool](Get-GuiObjectField -Object $source -FieldName 'IsChecked') } else { $false }
				if ($isSelected)
				{
					$stateLabel = 'Queued'
					$stateTone = 'Primary'
					$stateDetail = ('This one-time action will run when you click {0}.' -f (Get-UxRunActionLabel))
				}
				else
				{
					$stateLabel = 'Idle'
					$stateTone = 'Muted'
					$stateDetail = 'This one-time action is not selected.'
				}
			}
		}

		$scenarioTags = New-Object System.Collections.Generic.List[string]
		foreach ($scenarioTag in @($Tweak.ScenarioTags))
		{
			if ([string]::IsNullOrWhiteSpace([string]$scenarioTag)) { continue }
			$normalizedScenarioTag = Format-TweakScenarioTag -Tag $scenarioTag
			if ([string]::IsNullOrWhiteSpace($normalizedScenarioTag)) { continue }
			if ($scenarioTags -contains $normalizedScenarioTag) { continue }
			[void]$scenarioTags.Add($normalizedScenarioTag)
		}
		foreach ($tag in @($Tweak.Tags))
		{
			$formattedTag = Format-TweakScenarioTag -Tag $tag
			if ([string]::IsNullOrWhiteSpace($formattedTag)) { continue }
			if ($scenarioTags -contains $formattedTag) { continue }
			[void]$scenarioTags.Add($formattedTag)
		}

		$scenarioSignals = @(Get-TweakScenarioSignals -Tweak $Tweak)
		foreach ($signal in $scenarioSignals)
		{
			if ([string]::IsNullOrWhiteSpace([string]$signal)) { continue }
			if ($scenarioTags -contains $signal) { continue }
			[void]$scenarioTags.Add([string]$signal)
		}

		$focusGroup = Get-TweakFocusGroup -Tweak $Tweak -ScenarioSignals $scenarioSignals
		$reasonIncluded = Get-TweakInclusionReason -Tweak $Tweak -FocusGroup $focusGroup -ScenarioSignals $scenarioSignals
		$blastRadius = Get-TweakBlastRadiusText -Tweak $Tweak -TypeLabel $typeLabel -ScenarioTags @($scenarioTags) -MatchesDesired $matchesDesired

		return [pscustomobject]@{
			TypeKind = $typeKind
			TypeLabel = $typeLabel
			TypeBadgeLabel = $typeBadgeLabel
			TypeTone = $typeTone
			StateLabel = $stateLabel
			StateTone = $stateTone
			StateDetail = $stateDetail
			MatchesDesired = $matchesDesired
			ScenarioTags = @($scenarioTags)
			FocusGroup = $focusGroup
			ReasonIncluded = $reasonIncluded
			BlastRadius = $blastRadius
			IsRemoval = $isRemoval
			RecoveryLevel = if (Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') { [string](Get-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') } else { $null }
			TroubleshootingOnly = if (Test-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly') { [bool](Get-GuiObjectField -Object $Tweak -FieldName 'TroubleshootingOnly') } else { $false }
		}
	}

		function New-TweakMetadataChipPanel
		{
			param(
				[object]$Metadata,
				[bool]$IncludeType = $true,
				[bool]$IncludeState = $true,
				[bool]$IncludeRestart = $true,
				[bool]$IncludeRestorable = $true,
				[bool]$IncludeRecoveryLevel = $true,
				[bool]$UseCompactRecoveryLevelLabel = $false,
				[bool]$IncludeScenarioTags = $false,
				[int]$MaxScenarioTags = 4,
				[bool]$IncludeTroubleshooting = $true
			)

		if (-not $Metadata) { return $null }

		$panel = New-Object System.Windows.Controls.WrapPanel
		$panel.Orientation = 'Horizontal'
		$panel.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$panel.HorizontalAlignment = 'Stretch'

		$chipItems = New-Object System.Collections.Generic.List[object]
		$typeBadgeText = if ((Test-GuiObjectField -Object $Metadata -FieldName 'TypeBadgeLabel') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.TypeBadgeLabel)) { [string]$Metadata.TypeBadgeLabel } else { [string]$Metadata.TypeLabel }
		if ($IncludeType -and -not [string]::IsNullOrWhiteSpace($typeBadgeText))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = $typeBadgeText
				Tone = if ((Test-GuiObjectField -Object $Metadata -FieldName 'TypeTone') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.TypeTone)) { [string]$Metadata.TypeTone } else { 'Muted' }
				ToolTip = 'Type of tweak'
			})
		}

		if ($IncludeState -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateLabel))
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = [string]$Metadata.StateLabel
				Tone = if ((Test-GuiObjectField -Object $Metadata -FieldName 'StateTone') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateTone)) { [string]$Metadata.StateTone } else { 'Muted' }
				ToolTip = if ((Test-GuiObjectField -Object $Metadata -FieldName 'StateDetail') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.StateDetail)) { [string]$Metadata.StateDetail } else { 'Current state in the GUI' }
			})
		}

		if ($IncludeRestart -and (Test-GuiObjectField -Object $Metadata -FieldName 'RequiresRestart') -and [bool]$Metadata.RequiresRestart)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Restart required'
				Tone = 'Caution'
				ToolTip = 'This change requires a restart to take effect.'
			})
		}

		if ($IncludeRestorable -and (Test-GuiObjectField -Object $Metadata -FieldName 'Restorable') -and $null -ne $Metadata.Restorable -and -not [bool]$Metadata.Restorable)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Manual recovery'
				Tone = 'Danger'
				ToolTip = 'This change cannot be fully rolled back automatically.'
			})
		}

		if ($IncludeRecoveryLevel -and (Test-GuiObjectField -Object $Metadata -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Metadata.RecoveryLevel))
		{
			$recoveryLevelLabel = [string]$Metadata.RecoveryLevel
			$recoveryTone = switch ($recoveryLevelLabel)
			{
				'Direct' { 'Success'; break }
				'DefaultsOnly' { 'Primary'; break }
				'RestorePoint' { 'Caution'; break }
				'Manual' { 'Danger'; break }
				default { 'Muted' }
				}
				[void]$chipItems.Add([pscustomobject]@{
					Label = $(if ($UseCompactRecoveryLevelLabel) { $recoveryLevelLabel } else { "Recovery: $recoveryLevelLabel" })
					Tone = $recoveryTone
					ToolTip = 'Recommended recovery path for this tweak.'
				})
			}

		if ($IncludeTroubleshooting -and (Test-GuiObjectField -Object $Metadata -FieldName 'TroubleshootingOnly') -and [bool]$Metadata.TroubleshootingOnly)
		{
			[void]$chipItems.Add([pscustomobject]@{
				Label = 'Troubleshooting only'
				Tone = 'Caution'
				ToolTip = 'Use this only when diagnosing game compatibility, overlay, or display issues.'
			})
		}

		if ($IncludeScenarioTags -and (Test-GuiObjectField -Object $Metadata -FieldName 'ScenarioTags') -and $Metadata.ScenarioTags)
		{
			$scenarioTags = @($Metadata.ScenarioTags)
			foreach ($tag in @($scenarioTags | Select-Object -First $MaxScenarioTags))
			{
				if ([string]::IsNullOrWhiteSpace([string]$tag)) { continue }
				[void]$chipItems.Add([pscustomobject]@{
					Label = [string]$tag
					Tone = 'Muted'
					ToolTip = 'Scenario tag'
				})
			}
			if ($scenarioTags.Count -gt $MaxScenarioTags)
			{
				[void]$chipItems.Add([pscustomobject]@{
					Label = "+$($scenarioTags.Count - $MaxScenarioTags) more"
					Tone = 'Muted'
					ToolTip = 'Additional scenario tags are present in the manifest.'
				})
			}
		}

		foreach ($chip in $chipItems)
		{
			[void]($panel.Children.Add((GUICommon\New-DialogMetadataPill `
				-Theme $Script:CurrentTheme `
				-Label $chip.Label `
				-Tone $chip.Tone `
				-ToolTip $chip.ToolTip)))
		}

		if ($panel.Children.Count -eq 0)
		{
			return $null
		}

		return $panel
	}

	function New-SectionHeader
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Text)
		$lbl = New-Object System.Windows.Controls.TextBlock
		$lbl.Text = $Text.ToUpper()
		$lbl.FontSize = 11
		$lbl.FontWeight = [System.Windows.FontWeights]::Bold
		$lbl.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.SectionLabel -Context 'New-SectionHeader/Foreground'
		$lbl.Margin = [System.Windows.Thickness]::new(12, 12, 0, 6)
		return $lbl
	}

	function New-SearchResultsSummary
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Query,
			[int]$MatchCount
		)

		$bc = New-SafeBrushConverter -Context 'New-SearchResultsSummary'

		# Use AccentBlue as the banner background for a distinctive inline look.
		$accentBlue = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.AccentBlue)) { [string]$Script:CurrentTheme.AccentBlue } else { '#3B82F6' }

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($accentBlue)
		$border.BorderBrush = $bc.ConvertFromString($accentBlue)
		$border.BorderThickness = [System.Windows.Thickness]::new(0)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$border.Margin = [System.Windows.Thickness]::new(8, 10, 8, 6)
		$border.Padding = [System.Windows.Thickness]::new(16, 10, 16, 10)

		# Horizontal layout: text on the left, clear button on the right.
		$grid = New-Object System.Windows.Controls.Grid
		$colText = New-Object System.Windows.Controls.ColumnDefinition
		$colText.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
		[void]($grid.ColumnDefinitions.Add($colText))
		$colBtn = New-Object System.Windows.Controls.ColumnDefinition
		$colBtn.Width = [System.Windows.GridLength]::Auto
		[void]($grid.ColumnDefinitions.Add($colBtn))

		$textStack = New-Object System.Windows.Controls.StackPanel
		$textStack.Orientation = 'Vertical'
		$textStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		[System.Windows.Controls.Grid]::SetColumn($textStack, 0)

		$matchWord = if ($MatchCount -eq 1) { 'result' } else { 'results' }
		$summaryText = "Showing $MatchCount $matchWord for '$Query'"
		$searchIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Search' -Text $summaryText -IconSize 16 -Gap 8 -TextFontSize 13 -Foreground ($bc.ConvertFromString('#FFFFFF')) -AllowTextOnlyFallback -Bold } else { $null }
		if ($searchIconContent)
		{
			$searchIconContent.Margin = [System.Windows.Thickness]::new(0)
			[void]($textStack.Children.Add($searchIconContent))
		}
		else
		{
			$summary = New-Object System.Windows.Controls.TextBlock
			$summary.Text = $summaryText
			$summary.TextWrapping = 'Wrap'
			$summary.FontSize = 13
			$summary.FontWeight = [System.Windows.FontWeights]::SemiBold
			$summary.Foreground = $bc.ConvertFromString('#FFFFFF')
			[void]($textStack.Children.Add($summary))
		}
		[void]($grid.Children.Add($textStack))

		# "Clear" button to dismiss search results inline.
		$clearBtn = New-Object System.Windows.Controls.Button
		$clearIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Clear' -Text 'Clear' -IconSize 14 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback } else { $null }
		$clearBtn.Content = if ($clearIconContent) { $clearIconContent } else { 'Clear' }
		$clearBtn.FontSize = 12
		$clearBtn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$clearBtn.Foreground = $bc.ConvertFromString($accentBlue)
		$clearBtn.Background = $bc.ConvertFromString('#FFFFFF')
		$clearBtn.BorderThickness = [System.Windows.Thickness]::new(0)
		$clearBtn.Padding = [System.Windows.Thickness]::new(14, 5, 14, 5)
		$clearBtn.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
		$clearBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		$clearBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		[System.Windows.Controls.Grid]::SetColumn($clearBtn, 1)

		# When clicked, clear the search text box to dismiss the inline results.
		# Capture $TxtSearch from the parent scope so the closure resolves correctly.
		$searchBox = $TxtSearch
		Register-GuiEventHandler -Source $clearBtn -EventName 'Click' -Handler ({
			if ($searchBox) { $searchBox.Text = '' ; [void]($searchBox.Focus()) }
		}.GetNewClosure()) | Out-Null
		[void]($grid.Children.Add($clearBtn))

		$border.Child = $grid
		return $border
	}

	function New-CautionSection
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([array]$CautionTweaks)
		if ($CautionTweaks.Count -eq 0) { return $null }
		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersBlock'

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CautionBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CautionBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$border.Margin = [System.Windows.Thickness]::new(8, 10, 8, 6)
		$border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = "Vertical"

		$headerGrid = New-Object System.Windows.Controls.Grid
		$headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		$headerStack = New-Object System.Windows.Controls.StackPanel
		$headerStack.Orientation = 'Vertical'
		[System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

		$cautionIconContent = if (Get-Command -Name 'New-GuiLabeledIconContent' -CommandType Function -ErrorAction SilentlyContinue) { New-GuiLabeledIconContent -IconName 'Warning' -Text 'CAUTION' -IconSize 14 -Gap 6 -TextFontSize 12 -Foreground (ConvertTo-GuiBrush -Color $Script:CurrentTheme.CautionText -Context 'New-CautionSection/Header') -AllowTextOnlyFallback -Bold } else { $null }
		if ($cautionIconContent)
		{
			[void]($headerStack.Children.Add($cautionIconContent))
		}
		else
		{
			$header = New-Object System.Windows.Controls.TextBlock
			$header.Text = "CAUTION"
			$header.FontSize = 12
			$header.FontWeight = [System.Windows.FontWeights]::Bold
			$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
			[void]($headerStack.Children.Add($header))
		}
		$summary = New-Object System.Windows.Controls.TextBlock
		$summary.Text = "$($CautionTweaks.Count) tweak$(if ($CautionTweaks.Count -eq 1) { '' } else { 's' }) need extra care in this section."
		$summary.FontSize = 11
		$summary.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$summary.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		[void]($headerStack.Children.Add($summary))
		[void]($headerGrid.Children.Add($headerStack))
		$toggleButton = New-Object System.Windows.Controls.Button
		$toggleButton.Content = Get-UxLocalizedString -Key 'GuiShowDetails' -Fallback 'Show details'
		$toggleButton.FontSize = 11
		$toggleButton.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$toggleButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$toggleButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		Set-ButtonChrome -Button $toggleButton -Variant 'Subtle' -Compact
		[System.Windows.Controls.Grid]::SetColumn($toggleButton, 1)
		[void]($headerGrid.Children.Add($toggleButton))
		[void]($stack.Children.Add($headerGrid))
		$getUxLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxLocalizedString'
		$detailsPanel = New-Object System.Windows.Controls.StackPanel
		$detailsPanel.Orientation = 'Vertical'
		$detailsPanel.Visibility = [System.Windows.Visibility]::Collapsed

		foreach ($ct in $CautionTweaks)
		{
			$reason = if ($ct.CautionReason) { $ct.CautionReason } else { "This tweak may have unintended side effects. Use with care." }
			$item = New-Object System.Windows.Controls.TextBlock
			$item.TextWrapping = "Wrap"
			$item.Margin = [System.Windows.Thickness]::new(0, 2, 0, 4)
			$item.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)

			$bold = New-Object System.Windows.Documents.Run
			$bold.Text = "$($ct.Name): "
			$bold.FontWeight = [System.Windows.FontWeights]::SemiBold
			$bold.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
			[void]($item.Inlines.Add($bold))
			$desc = New-Object System.Windows.Documents.Run
			$desc.Text = $reason
			[void]($item.Inlines.Add($desc))
			[void]($detailsPanel.Children.Add($item))
		}

		Register-GuiEventHandler -Source $toggleButton -EventName 'Click' -Handler ({
			$showDetails = ($detailsPanel.Visibility -ne [System.Windows.Visibility]::Visible)
			$detailsPanel.Visibility = if ($showDetails) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			$toggleButton.Content = if ($showDetails) {
				& $getUxLocalizedStringCapture -Key 'GuiHideDetails' -Fallback 'Hide details'
			}
			else {
				& $getUxLocalizedStringCapture -Key 'GuiShowDetails' -Fallback 'Show details'
			}
		}.GetNewClosure()) | Out-Null

		[void]($stack.Children.Add($detailsPanel))
		$border.Child = $stack
		return $border
	}

		function Add-ExecutionLogLine
		{
		param (
			[string]$Text,
			[string]$Level = 'INFO'
		)

		if ([string]::IsNullOrWhiteSpace($Text) -or -not $Script:ExecutionLogBox -or -not $Script:ExecutionLogBox.Document) { return }

		$bc = New-SafeBrushConverter -Context 'Add-ExecutionLogLine'
		$timestamp = Get-Date -Format 'HH:mm:ss'

		$para = New-Object System.Windows.Documents.Paragraph
		$para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
		$para.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
		$para.FontSize = 12

		$tsRun = New-Object System.Windows.Documents.Run
		$tsRun.Text = "[$timestamp] "
		$tsRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($para.Inlines.Add($tsRun))
		# Icon glyph prefix for log level
		$logIconKind = switch ($Level.ToUpperInvariant())
		{
			'ERROR'   { 'Failed' }
			'WARNING' { 'Warning' }
			'SUCCESS' { 'Success' }
			'SKIP'    { 'Skipped' }
			default   { 'Info' }
		}
		$logIconGlyph = if (Get-Command -Name 'Get-GuiIconGlyph' -CommandType Function -ErrorAction SilentlyContinue) { Get-GuiIconGlyph -Name $logIconKind } else { $null }
		if ((Get-Command -Name 'Test-GuiIconsAvailable' -CommandType Function -ErrorAction SilentlyContinue) -and (Test-GuiIconsAvailable) -and $logIconGlyph)
		{
			$iconRun = New-Object System.Windows.Documents.Run
			$iconRun.Text = "$logIconGlyph "
			$iconRun.FontFamily = $Script:GuiIconFontFamily
			$iconRun.FontSize = 12
			$logIconColor = switch ($Level.ToUpperInvariant())
			{
				'ERROR'   { $Script:CurrentTheme.CautionText }
				'WARNING' { $Script:CurrentTheme.RiskMediumBadge }
				'SUCCESS' { $Script:CurrentTheme.LowRiskBadge }
				default   { $Script:CurrentTheme.TextMuted }
			}
			$iconRun.Foreground = $bc.ConvertFromString($logIconColor)
			[void]($para.Inlines.Add($iconRun))
		}
		$levelRun = New-Object System.Windows.Documents.Run
		$levelRun.Text = "[$($Level.ToUpperInvariant())] "
		$levelRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		[void]($para.Inlines.Add($levelRun))
		$contentRun = New-Object System.Windows.Documents.Run
		$contentRun.Text = $Text
		$contentColor = switch ($Level.ToUpperInvariant())
		{
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
		if (($vO + $vH) -ge ($eH - 30))
		{
			$Script:ExecutionLogBox.ScrollToEnd()
		}
			$null = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'RenderRefresh' -Synchronous -Action {}
		}

		function Test-ExecutionSkipMessage
		{
			param(
				[string]$Message
			)

			if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

			return ($Message -match '(?i)\bskipping\b|\bskipped\b|\bnot applicable\b|\bnot supported\b|\bunsupported\b')
		}

	function Show-GuiFileSaveDialog
	{
		param (
			[string]$Title = 'Save File',
			[string]$Filter = 'All Files (*.*)|*.*',
			[string]$DefaultExtension = 'json',
			[string]$FileName = 'Baseline-export.json'
		)

		$saveDialog = New-Object Microsoft.Win32.SaveFileDialog
		$saveDialog.Title = $Title
		$saveDialog.Filter = $Filter
		$saveDialog.DefaultExt = $DefaultExtension
		$saveDialog.AddExtension = $true
		$saveDialog.FileName = $FileName
		$saveDialog.InitialDirectory = GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline'

		$owner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($saveDialog.ShowDialog($owner) -eq $true)
		{
			return $saveDialog.FileName
		}

		return $null
	}

