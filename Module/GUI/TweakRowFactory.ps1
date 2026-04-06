	# Pre-computed shared resources for card hover effects.
	# Frozen DropShadowEffect instances are reused across all cards in the same
	# theme, avoiding per-card object allocation and WPF effect re-composition.
	$Script:CardHoverResources = $null

	function Get-CardHoverResources
	{
		$themeName = if ($Script:CurrentThemeName) { $Script:CurrentThemeName } else { 'Dark' }
		if ($Script:CardHoverResources -and $Script:CardHoverResources.ThemeName -eq $themeName)
		{
			return $Script:CardHoverResources
		}
		$bc = New-SafeBrushConverter -Context 'Get-CardHoverResources'
		$isLight = ($Script:CurrentTheme -eq $Script:LightTheme)
		$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
		$shadow.Color = [System.Windows.Media.Colors]::Black
		$shadow.Direction = 270
		$shadow.ShadowDepth = if ($isLight) { 2 } else { 1 }
		$shadow.Opacity = if ($isLight) { 0.09 } else { 0.18 }
		$shadow.BlurRadius = if ($isLight) { 8 } else { 10 }
		if ($shadow.CanFreeze) { $shadow.Freeze() }
		$Script:CardHoverResources = @{
			ThemeName      = $themeName
			Shadow         = $shadow
			DefaultBg      = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
			HoverBg        = $bc.ConvertFromString($Script:CurrentTheme.CardHoverBg)
			PressBg        = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
			DefaultBorder  = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
			HoverBorder    = $bc.ConvertFromString($Script:CurrentTheme.AccentHover)
			FocusBorder    = $bc.ConvertFromString($Script:CurrentTheme.FocusRing)
			Thickness1     = [System.Windows.Thickness]::new(1)
			Thickness2     = [System.Windows.Thickness]::new(2)
		}
		return $Script:CardHoverResources
	}

	function Add-CardHoverEffects
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Border]$Card,
			[object[]]$FocusSources = @()
		)
		if (-not $Card) { return }
		$setGuiControlPropertyCapture = ${function:Set-GuiControlProperty}
		$invokeGuiSafeActionCapture = ${function:Invoke-GuiSafeAction}
		$res = Get-CardHoverResources
		$defaultBg = $res.DefaultBg
		$hoverBg = $res.HoverBg
		$defaultBorder = $res.DefaultBorder
		$hoverBorder = $res.HoverBorder
		$focusBorder = $res.FocusBorder
		$thickness1 = $res.Thickness1
		$thickness2 = $res.Thickness2

		# Check for left accent border info stored on the card Tag by New-TweakRowCard
		$accentInfo = if ($Card.Tag -is [hashtable] -and $Card.Tag.ContainsKey('AccentBrush')) { $Card.Tag } else { $null }
		if ($accentInfo)
		{
			$defaultBorder = $accentInfo.AccentBrush
			$thickness1 = $accentInfo.AccentThickness
			$thickness2 = $accentInfo.AccentThicknessFocus
		}

		$updateChrome = {
			$hasFocus = $false
			foreach ($focusSource in $FocusSources)
			{
				if ($focusSource -and $focusSource.IsKeyboardFocusWithin)
				{
					$hasFocus = $true
					break
				}
			}
			# Direct property assignment avoids Set-GuiControlProperty overhead on
			# hot-path hover/focus events.  Border always has these properties.
			$Card.Background = if ($Card.IsMouseOver) { $hoverBg } else { $defaultBg }
			if ($hasFocus)
			{
				$Card.BorderBrush = $focusBorder
				$Card.BorderThickness = $thickness2
			}
			elseif ($Card.IsMouseOver)
			{
				$Card.BorderBrush = $hoverBorder
				$Card.BorderThickness = $thickness1
			}
			else
			{
				$Card.BorderBrush = $defaultBorder
				$Card.BorderThickness = $thickness1
			}
		}.GetNewClosure()
		$Card.BorderBrush = $defaultBorder
		$Card.BorderThickness = $thickness1
		$Card.Effect = $res.Shadow
		$Card.Cursor = [System.Windows.Input.Cursors]::Hand
		# Attach hover/focus handlers directly to avoid Invoke-GuiSafeAction
		# overhead on these high-frequency visual-only events.
		$Card.Add_MouseEnter({ try { & $updateChrome } catch {} }.GetNewClosure())
		$Card.Add_MouseLeave({ try { & $updateChrome } catch {} }.GetNewClosure())
		$pressBg = $res.PressBg
		$pressHandler = {
			$Card.Background = $pressBg
		}.GetNewClosure()
		$Card.Add_PreviewMouseLeftButtonDown({ try { & $pressHandler } catch {} }.GetNewClosure())
		$Card.Add_PreviewMouseLeftButtonUp({ try { & $updateChrome } catch {} }.GetNewClosure())
		foreach ($focusSource in $FocusSources)
		{
			if (-not $focusSource) { continue }
			$focusSource.Add_GotKeyboardFocus({ try { & $updateChrome } catch {} }.GetNewClosure())
			$focusSource.Add_LostKeyboardFocus({ try { & $updateChrome } catch {} }.GetNewClosure())
		}
		try { & $updateChrome } catch {}
	}

	function Ensure-PendingLinkedStateCollections
	{
		if (-not ($Script:PendingLinkedChecks -is [System.Collections.Generic.HashSet[string]]))
		{
			$Script:PendingLinkedChecks = [System.Collections.Generic.HashSet[string]]::new()
		}
		if (-not ($Script:PendingLinkedUnchecks -is [System.Collections.Generic.HashSet[string]]))
		{
			$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
		}
	}

	$syncLinkedState = {
		param (
			[string]$TargetFunction,
			[bool]$IsChecked
		)

		if ([string]::IsNullOrWhiteSpace($TargetFunction)) { return }
		if ($Script:ApplyingGuiPreset) { return }
		Ensure-PendingLinkedStateCollections

		$fidx = $Script:FunctionToIndex[$TargetFunction]
		if ($null -eq $fidx) { return }

		$tctl = $Script:Controls[$fidx]
		if ($null -ne $tctl -and $tctl.PSObject.Properties["IsChecked"])
		{
			$tctl.IsChecked = $IsChecked
		}

		if ($IsChecked)
		{
			if ($Script:PendingLinkedUnchecks) { [void]$Script:PendingLinkedUnchecks.Remove($TargetFunction) }
			if ($Script:PendingLinkedChecks) { [void]$Script:PendingLinkedChecks.Add($TargetFunction) }
		}
		else
		{
			if ($Script:PendingLinkedChecks) { [void]$Script:PendingLinkedChecks.Remove($TargetFunction) }
			if ($Script:PendingLinkedUnchecks) { [void]$Script:PendingLinkedUnchecks.Add($TargetFunction) }
		}
	}

	function Test-TweakRowVisible
	{
		param ([object]$Tweak)

		if (-not $Tweak.VisibleIf)
		{
			return $true
		}

		try
		{
			return [bool](& $Tweak.VisibleIf)
		}
		catch
		{
			return $false
		}
	}

	# Pre-computed CornerRadius shared across all tweak row cards.
	$Script:CardCornerRadius6 = [System.Windows.CornerRadius]::new(6)
	# Pre-computed Thickness values reused across all tweak row cards to avoid
	# per-row allocations.  Thickness is immutable in WPF so sharing is safe.
	$Script:T = @{
		Zero           = [System.Windows.Thickness]::new(0)
		CheckBoxRight  = [System.Windows.Thickness]::new(0, 0, 10, 0)
		ComboLeft      = [System.Windows.Thickness]::new(14, 0, 0, 0)
		StatusRow      = [System.Windows.Thickness]::new(28, 0, 0, 0)
		BadgePad       = [System.Windows.Thickness]::new(5, 1, 5, 1)
		AccentBorder   = [System.Windows.Thickness]::new(3, 1, 1, 1)
		AccentFocus    = [System.Windows.Thickness]::new(3, 2, 2, 2)
		DescIndent     = [System.Windows.Thickness]::new(28, 1, 6, 0)
		MetaIndent     = [System.Windows.Thickness]::new(28, 6, 0, 0)
		BlastIndent    = [System.Windows.Thickness]::new(28, 4, 6, 0)
		WhyIndent      = [System.Windows.Thickness]::new(28, 2, 0, 0)
		DescFlush      = [System.Windows.Thickness]::new(0, 1, 0, 0)
		MetaFlush      = [System.Windows.Thickness]::new(0, 6, 0, 0)
		BlastFlush     = [System.Windows.Thickness]::new(0, 4, 0, 0)
		WhyFlush       = [System.Windows.Thickness]::new(0, 2, 0, 0)
	}

	function New-TweakRowCard
	{
		param (
			[object]$BrushConverter,
			[System.Windows.Thickness]$Margin,
			[System.Windows.Thickness]$Padding,
			[object]$Tweak = $null
		)

		$card = New-Object System.Windows.Controls.Border
		$res = Get-CardHoverResources
		$card.Background = $res.DefaultBg
		$card.CornerRadius = $Script:CardCornerRadius6
		$card.Margin = $Margin
		$card.Padding = $Padding

		# Apply left accent border for high-risk or caution tweaks
		$isHighRisk = $Tweak -and (Test-GuiObjectField -Object $Tweak -FieldName 'Risk') -and ([string]$Tweak.Risk -eq 'High')
		$isCaution = $Tweak -and (Test-GuiObjectField -Object $Tweak -FieldName 'Caution') -and ($Tweak.Caution -eq $true)
		$isMediumRisk = $Tweak -and (Test-GuiObjectField -Object $Tweak -FieldName 'Risk') -and ([string]$Tweak.Risk -eq 'Medium')
		if ($isHighRisk -or $isCaution)
		{
			$accentBrush = $BrushConverter.ConvertFromString($Script:CurrentTheme.CautionBorder)
			$card.Tag = @{ AccentBrush = $accentBrush; AccentThickness = $Script:T.AccentBorder; AccentThicknessFocus = $Script:T.AccentFocus }
		}
		elseif ($isMediumRisk)
		{
			$accentBrush = $BrushConverter.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
			$card.Tag = @{ AccentBrush = $accentBrush; AccentThickness = $Script:T.AccentBorder; AccentThicknessFocus = $Script:T.AccentFocus }
		}

		return $card
	}

	function New-TweakNamePanel
	{
		param (
			[object]$Tweak,
			[object]$BrushConverter,
			[switch]$UseWrapPanel
		)

		$namePanel = if ($UseWrapPanel)
		{
			New-Object System.Windows.Controls.WrapPanel
		}
		else
		{
			New-Object System.Windows.Controls.StackPanel
		}
		$namePanel.Orientation = 'Horizontal'
		$namePanel.VerticalAlignment = 'Center'

		$nameText = New-Object System.Windows.Controls.TextBlock
		$nameText.Text = $Tweak.Name
		$nameText.FontSize = $Script:GuiLayout.FontSizeSubheading
		$nameText.FontWeight = [System.Windows.FontWeights]::SemiBold
		$nameText.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$nameText.VerticalAlignment = 'Center'
		$nameText.Margin = $Script:T.Zero

		# Build a quick-glance dependency tooltip for the tweak name
		$nameTipParts = [System.Collections.Generic.List[string]]::new()
		$impactField = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Impact') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Impact)) { [string]$Tweak.Impact } else { $null }
		if ($impactField) { [void]$nameTipParts.Add("Impact: $impactField") }
		$whyField = if ((Test-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) { [string]$Tweak.WhyThisMatters } else { $null }
		if ($whyField) { [void]$nameTipParts.Add($whyField) }
		$recoveryField = if ((Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.RecoveryLevel)) { [string]$Tweak.RecoveryLevel } else { $null }
		if ($recoveryField)
		{
			$recoveryLabel = switch ($recoveryField)
			{
				'Direct'       { 'Directly reversible' }
				'RestorePoint' { 'Restore point recovery' }
				'Manual'       { 'Manual recovery' }
				'DefaultsOnly' { 'Defaults-only recovery' }
				default        { $recoveryField }
			}
			[void]$nameTipParts.Add("Recovery: $recoveryLabel")
		}
		if ((Test-GuiObjectField -Object $Tweak -FieldName 'RequiresRestart') -and [bool]$Tweak.RequiresRestart)
		{
			[void]$nameTipParts.Add(([char]0x21BB).ToString() + ' Restart required')
		}
		if ($nameTipParts.Count -gt 0)
		{
			$nameText.ToolTip = $nameTipParts -join "`n"
		}

		# Attach visualization state to tweak for tooltip display
		if ($RowContext -and $RowContext.Metadata)
		{
			$Tweak | Add-Member -MemberType NoteProperty -Name '_StateLabel' -Value ([string]$RowContext.Metadata.StateLabel) -Force
			$Tweak | Add-Member -MemberType NoteProperty -Name '_MatchesDesired' -Value ([bool]$RowContext.Metadata.MatchesDesired) -Force
		}
		[void]($namePanel.Children.Add($nameText))
		[void]($namePanel.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)))
		if ($Tweak.Caution)
		{
			[void]($namePanel.Children.Add((New-ImpactBadge)))
		}

		return $namePanel
	}

	function New-TweakHeaderBadgesPanel
	{
		param (
			[object]$Tweak,
			[object]$Metadata,
			[object]$BrushConverter,
			[System.Windows.Thickness]$BadgeSpacing
		)

		$badgesPanel = New-Object System.Windows.Controls.StackPanel
		$badgesPanel.Orientation = 'Horizontal'
		$badgesPanel.VerticalAlignment = 'Center'
		$badgesPanel.HorizontalAlignment = 'Right'

		$typeBadge = GUICommon\New-DialogMetadataPill -Theme $Script:CurrentTheme -Label $Metadata.TypeLabel -Tone $Metadata.TypeTone -ToolTip 'Type of tweak'
		if ($typeBadge)
		{
			$typeBadge.Margin = $BadgeSpacing
			[void]($badgesPanel.Children.Add($typeBadge))
		}
		if ([bool]$Tweak.RequiresRestart)
		{
			$restartBadge = New-Object System.Windows.Controls.TextBlock
			$restartBadge.Text = [char]0x21BB + ' Restart'
			$restartBadge.FontSize = $Script:GuiLayout.FontSizeSmall
			$restartBadge.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
			$restartBadge.Background = $BrushConverter.ConvertFromString($Script:CurrentTheme.TabActiveBg)
			$restartBadge.Padding = $Script:T.BadgePad
			$restartBadge.Margin = $BadgeSpacing
			$restartBadge.VerticalAlignment = 'Center'
			[void]($badgesPanel.Children.Add($restartBadge))
		}
		$riskBadge = New-RiskBadge -Level $Tweak.Risk
		if ($riskBadge)
		{
			$riskBadge.Margin = $BadgeSpacing
			[void]($badgesPanel.Children.Add($riskBadge))
		}
		if ($Metadata.TroubleshootingOnly)
		{
			$troubleshootingBadge = New-TroubleshootingOnlyBadge
			if ($troubleshootingBadge)
			{
				$troubleshootingBadge.Margin = $BadgeSpacing
				[void]($badgesPanel.Children.Add($troubleshootingBadge))
			}
		}
		if ((Test-GuiObjectField -Object $Tweak -FieldName 'Restorable') -and $null -ne $Tweak.Restorable -and -not [bool]$Tweak.Restorable)
		{
			$restorableBadge = GUICommon\New-DialogMetadataPill -Theme $Script:CurrentTheme -Label 'Manual recovery' -Tone 'Danger' -ToolTip 'This change cannot be fully rolled back automatically.'
			if ($restorableBadge)
			{
				$restorableBadge.Margin = $BadgeSpacing
				[void]($badgesPanel.Children.Add($restorableBadge))
			}
		}
		if ((Test-IsSafeModeUX) -and (Test-GuiObjectField -Object $Tweak -FieldName 'PresetTier') -and [string]$Tweak.PresetTier -eq 'Minimal')
		{
			$recommendedBadge = GUICommon\New-DialogMetadataPill -Theme $Script:CurrentTheme -Label 'Recommended' -Tone 'Success' -ToolTip 'Included in the recommended Quick Start preset'
			if ($recommendedBadge)
			{
				$recommendedBadge.Margin = $BadgeSpacing
				[void]($badgesPanel.Children.Add($recommendedBadge))
			}
		}

		return $badgesPanel
	}

	function Add-TweakMetadataDetails
	{
		param (
			[System.Windows.Controls.Panel]$Container,
			[object]$Tweak,
			[object]$RowContext,
			[string]$DescriptionText,
			[string]$DescriptionColor,
			[System.Windows.Thickness]$DescriptionMargin,
			[System.Windows.Thickness]$MetadataMargin,
			[System.Windows.Thickness]$BlastMargin
		)

		$descriptionTextBlock = New-Object System.Windows.Controls.TextBlock
		$descriptionTextBlock.Text = $DescriptionText
		$descriptionTextBlock.FontSize = $Script:GuiLayout.FontSizeSmall
		$descriptionTextBlock.Foreground = $RowContext.BrushConverter.ConvertFromString($DescriptionColor)
		$descriptionTextBlock.Margin = $DescriptionMargin
		$descriptionTextBlock.TextWrapping = 'Wrap'
		[void]($Container.Children.Add($descriptionTextBlock))

		# Show CautionReason inline on the tweak row for High-risk items so the
		# consequence text is visible by default without expanding the caution section.
		if ([string]$Tweak.Risk -eq 'High' -and [bool]$Tweak.Caution -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.CautionReason))
		{
			$cautionColor = if ($Script:CurrentTheme -and $Script:CurrentTheme.CautionText) { $Script:CurrentTheme.CautionText } else { '#E5A84B' }
			$cautionInline = New-Object System.Windows.Controls.TextBlock
			$cautionInline.TextWrapping = 'Wrap'
			$cautionInline.Margin = $DescriptionMargin
			$cautionInline.FontSize = $Script:GuiLayout.FontSizeSmall
			$cautionInline.FontWeight = [System.Windows.FontWeights]::Medium
			$cautionInline.Foreground = $RowContext.BrushConverter.ConvertFromString($cautionColor)

			$cautionIcon = New-Object System.Windows.Documents.Run
			$cautionIcon.Text = ([char]0x26A0).ToString() + ' '
			[void]($cautionInline.Inlines.Add($cautionIcon))

			$cautionText = New-Object System.Windows.Documents.Run
			$cautionText.Text = [string]$Tweak.CautionReason
			[void]($cautionInline.Inlines.Add($cautionText))

			[void]($Container.Children.Add($cautionInline))
		}

		try
		{
			$detailMetaPanel = New-TweakMetadataChipPanel -Metadata $RowContext.Metadata -IncludeType:$false -IncludeState:$true -IncludeRestart:$false -IncludeRestorable:$false -IncludeRecoveryLevel:$true -UseCompactRecoveryLevelLabel:$RowContext.UseCompactRecoveryLevelLabel -IncludeScenarioTags:$true
		}
		catch
		{
			throw "Add-TweakMetadataDetails/MetadataChips failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		if ($detailMetaPanel)
		{
			$detailMetaPanel.Margin = $MetadataMargin
			[void]($Container.Children.Add($detailMetaPanel))
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$RowContext.Metadata.BlastRadius))
		{
			$blastText = New-Object System.Windows.Controls.TextBlock
			$blastText.Text = [string]$RowContext.Metadata.BlastRadius
			$blastText.TextWrapping = 'Wrap'
			$blastText.Margin = $BlastMargin
			$blastText.FontSize = $Script:GuiLayout.FontSizeSmall
			$blastText.Foreground = $RowContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
			[void]($Container.Children.Add($blastText))
		}
	}

	function Add-TweakWhyBlockDetails
	{
		param (
			[System.Windows.Controls.Panel]$Container,
			[object]$Tweak,
			[int]$LeftIndent = 0,
			[System.Windows.Thickness]$RowMargin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		)

		$whyBlock = New-WhyThisMattersButton -Tweak $Tweak -LeftIndent $LeftIndent
		if (-not $whyBlock)
		{
			return $null
		}

		$whyRow = New-Object System.Windows.Controls.Grid
		[void]($whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		$whyRow.Margin = $RowMargin
		[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
		[void]($whyRow.Children.Add($whyBlock))
		[void]($Container.Children.Add($whyRow))
		if ($whyBlock.Tag)
		{
			[void]($Container.Children.Add($whyBlock.Tag))
		}

		return $whyBlock
	}

	function Get-GameModePlanEntryForTweak
	{
		param ([object]$Tweak)

		$currentPlan = Get-GameModePlan
		if (-not [bool]$Script:GameMode -or -not $currentPlan -or @($currentPlan).Count -eq 0)
		{
			return $null
		}

		foreach ($planEntry in @($currentPlan))
		{
			if ($planEntry -and (Test-GuiObjectField -Object $planEntry -FieldName 'Function') -and [string]$planEntry.Function -eq [string]$Tweak.Function)
			{
				return $planEntry
			}
		}

		return $null
	}

	function Get-ToggleInitialCheckedState
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			$planToggle = if ((Test-GuiObjectField -Object $planMatch -FieldName 'ToggleParam')) { [string]$planMatch.ToggleParam } elseif ((Test-GuiObjectField -Object $planMatch -FieldName 'Selection')) { [string]$planMatch.Selection } else { $null }
			return (-not [string]::IsNullOrWhiteSpace($planToggle) -and [string]$planToggle -eq [string]$Tweak.OnParam)
		}

		# Explicit preset selections must survive tab rebuilds even when the target
		# tab has not been materialized into live controls yet.
		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Toggle')
		{
			return ([string]$explicitSelection.State -eq 'On')
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		return $false
	}

	function Get-ActionInitialCheckedState
	{
		param (
			[int]$Index,
			[object]$Tweak
		)

		$planMatch = Get-GameModePlanEntryForTweak -Tweak $Tweak
		if ($planMatch)
		{
			return $true
		}

		$explicitSelection = Get-GuiExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
		if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Action')
		{
			return [bool]$explicitSelection.Run
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'IsChecked'))
		{
			return [bool]$placeholder.IsChecked
		}

		return $false
	}

	function Get-ChoiceInitialSelectedIndex
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object[]]$ChoiceOptions = @(),
			[object]$RowContext = $null
		)

		if ($RowContext -and (Test-GuiObjectField -Object $RowContext -FieldName 'GetExplicitSelectionDefinition') -and $RowContext.GetExplicitSelectionDefinition)
		{
			$explicitSelection = & $RowContext.GetExplicitSelectionDefinition -FunctionName ([string]$Tweak.Function)
			if ($explicitSelection -and [string]$explicitSelection.Type -eq 'Choice' -and -not [string]::IsNullOrWhiteSpace([string]$explicitSelection.Value))
			{
				$explicitIndex = [array]::IndexOf($ChoiceOptions, [string]$explicitSelection.Value)
				if ($explicitIndex -ge 0)
				{
					return $explicitIndex
				}
			}
		}

		$placeholder = $Script:Controls[$Index]
		if ($placeholder -and (Test-GuiObjectField -Object $placeholder -FieldName 'SelectedIndex'))
		{
			return [int]$placeholder.SelectedIndex
		}

		return -1
	}

	function Apply-PendingLinkedToggleState
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[string]$FunctionName
		)

		Ensure-PendingLinkedStateCollections

		if ($Script:PendingLinkedChecks -and $Script:PendingLinkedChecks.Contains($FunctionName))
		{
			$CheckBox.IsChecked = $true
			[void]($Script:PendingLinkedChecks.Remove($FunctionName))
		}
		elseif ($Script:PendingLinkedUnchecks -and $Script:PendingLinkedUnchecks.Contains($FunctionName))
		{
			$CheckBox.IsChecked = $false
			[void]($Script:PendingLinkedUnchecks.Remove($FunctionName))
		}
	}

	function New-ToggleLikeCheckBox
	{
		param (
			[int]$Index,
			[bool]$InitialChecked,
			[object]$BrushConverter
		)

		$checkBox = New-Object System.Windows.Controls.CheckBox
		$checkBox.VerticalAlignment = 'Center'
		$checkBox.Margin = $Script:T.CheckBoxRight
		$checkBox.IsChecked = $InitialChecked
		$checkBox.Tag = $Index
		$checkBox.Foreground = $BrushConverter.ConvertFromString($Script:CurrentTheme.TextPrimary)
		return $checkBox
	}

	function New-ToggleLikeHeaderGrid
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[object]$Tweak,
			[object]$RowContext
		)

		$headerGrid = New-Object System.Windows.Controls.Grid
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))

		[System.Windows.Controls.Grid]::SetColumn($CheckBox, 0)
		[void]($headerGrid.Children.Add($CheckBox))

		try
		{
			$nameRow = New-TweakNamePanel -Tweak $Tweak -BrushConverter $RowContext.BrushConverter -UseWrapPanel
		}
		catch
		{
			throw "New-ToggleLikeHeaderGrid/NamePanel failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		[System.Windows.Controls.Grid]::SetColumn($nameRow, 1)
		[void]($headerGrid.Children.Add($nameRow))

		try
		{
			$badgesPanel = New-TweakHeaderBadgesPanel -Tweak $Tweak -Metadata $RowContext.Metadata -BrushConverter $RowContext.BrushConverter -BadgeSpacing $RowContext.BadgeSpacing
		}
		catch
		{
			throw "New-ToggleLikeHeaderGrid/Badges failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		[System.Windows.Controls.Grid]::SetColumn($badgesPanel, 2)
		[void]($headerGrid.Children.Add($badgesPanel))

		return $headerGrid
	}

	function New-ChoiceHeaderGrid
	{
		param (
			[object]$Tweak,
			[object]$RowContext
		)

		$nameRow = New-Object System.Windows.Controls.Grid
		[void]($nameRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($nameRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))

		$nameInner = New-TweakNamePanel -Tweak $Tweak -BrushConverter $RowContext.BrushConverter
		[System.Windows.Controls.Grid]::SetColumn($nameInner, 0)
		[void]($nameRow.Children.Add($nameInner))

		$choiceBadgesPanel = New-TweakHeaderBadgesPanel -Tweak $Tweak -Metadata $RowContext.Metadata -BrushConverter $RowContext.BrushConverter -BadgeSpacing $RowContext.BadgeSpacing
		[System.Windows.Controls.Grid]::SetColumn($choiceBadgesPanel, 1)
		[void]($nameRow.Children.Add($choiceBadgesPanel))

		return $nameRow
	}

	function New-ToggleStatusRow
	{
		param (
			[object]$Tweak,
			[System.Windows.Controls.CheckBox]$CheckBox,
			[object]$RowContext
		)

		$statusRow = New-Object System.Windows.Controls.Grid
		[void]($statusRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($statusRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		$statusRow.Margin = $Script:T.StatusRow

		$statusLabel = New-Object System.Windows.Controls.TextBlock
		$statusLabel.FontSize = $Script:GuiLayout.FontSizeSmall
		$statusLabel.FontWeight = [System.Windows.FontWeights]::Medium
		$statusLabel.VerticalAlignment = 'Center'
		[System.Windows.Controls.Grid]::SetColumn($statusLabel, 0)

		$onColor = if ($Script:CurrentTheme -and $Script:CurrentTheme.StateEnabled) { $Script:CurrentTheme.StateEnabled } else { '#9FD6AA' }
		$offColor = if ($Script:CurrentTheme -and $Script:CurrentTheme.StateDisabled) { $Script:CurrentTheme.StateDisabled } else { '#98A0B7' }
		if ($CheckBox.IsChecked)
		{
			$statusLabel.Text = Get-UxToggleStateLabel -Enabled $true
			$statusLabel.Foreground = $RowContext.BrushConverter.ConvertFromString($onColor)
		}
		else
		{
			$statusLabel.Text = Get-UxToggleStateLabel -Enabled $false
			$statusLabel.Foreground = $RowContext.BrushConverter.ConvertFromString($offColor)
		}

		if ($Script:ScanEnabled -and $Tweak.Detect)
		{
			try
			{
				$detectedOn = [bool](& $Tweak.Detect)
				$onLabel = if ($Tweak.OnParam) { $Tweak.OnParam } else { Get-UxToggleStateLabel -Enabled $true }
				$offLabel = if ($Tweak.OffParam) { $Tweak.OffParam } else { Get-UxToggleStateLabel -Enabled $false }
				if ($detectedOn -eq [bool]$Tweak.Default)
				{
					$stateWord = if ($detectedOn) { "Already $onLabel" } else { "Already $offLabel" }
					$statusLabel.Text = $stateWord
					$statusLabel.Foreground = $RowContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextMuted)
				}
				else
				{
					$stateWord = if ($detectedOn) { $onLabel } else { $offLabel }
					$statusLabel.Text = $stateWord
				}
			}
			catch
			{
				$statusLabel.Text = 'Detection failed'
				$statusLabel.Foreground = $RowContext.BrushConverter.ConvertFromString($Script:CurrentTheme.CautionText)
				Write-GuiRuntimeWarning -Context 'Build-TweakRow/Detect' -Message ("Detect failed for tweak '{0}' ({1}): {2}" -f [string]$Tweak.Name, [string]$Tweak.Function, $_.Exception.Message)
			}
		}

		[void]($statusRow.Children.Add($statusLabel))
		$whyBlock = New-WhyThisMattersButton -Tweak $Tweak
		if ($whyBlock)
		{
			[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
			[void]($statusRow.Children.Add($whyBlock))
		}

		return [pscustomobject]@{
			Row         = $statusRow
			StatusLabel = $statusLabel
			WhyBlock    = $whyBlock
			OnColor     = $onColor
			OffColor    = $offColor
		}
	}

	function Register-ToggleStatusHandlers
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[object]$StatusContext,
			[object]$RowContext
		)

		$statusLabelCapture = $StatusContext.StatusLabel
		$onColorCapture = $StatusContext.OnColor
		$offColorCapture = $StatusContext.OffColor
		$convertBrushCapture = $RowContext.ConvertBrushCapture
		$labelEnabled  = Get-UxToggleStateLabel -Enabled $true
		$labelDisabled = Get-UxToggleStateLabel -Enabled $false
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Checked' -Handler ({
			if ($statusLabelCapture)
			{
				$statusLabelCapture.Text = $labelEnabled
				$statusLabelCapture.Foreground = & $convertBrushCapture -Color $onColorCapture -Context 'Build-TweakRow/StatusEnabled'
			}
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Unchecked' -Handler ({
			if ($statusLabelCapture)
			{
				$statusLabelCapture.Text = $labelDisabled
				$statusLabelCapture.Foreground = & $convertBrushCapture -Color $offColorCapture -Context 'Build-TweakRow/StatusDisabled'
			}
		}.GetNewClosure())
	}

	function Register-GuiLinkedToggleHandlers
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[string]$LinkedFunction,
			[scriptblock]$SyncLinkedStateCapture
		)

		if ([string]::IsNullOrWhiteSpace($LinkedFunction))
		{
			return
		}

		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Checked' -Handler ({
			& $SyncLinkedStateCapture $LinkedFunction $true
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Unchecked' -Handler ({
			& $SyncLinkedStateCapture $LinkedFunction $false
		}.GetNewClosure())
	}

	function Register-GuiToggleExplicitSelectionHandlers
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[string]$FunctionName,
			[object]$RowContext
		)

		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Checked' -Handler ({
			$currentExplicitDefinition = & $RowContext.GetExplicitSelectionDefinition -FunctionName $FunctionName
			if ($currentExplicitDefinition -and [string]$currentExplicitDefinition.Type -eq 'Toggle')
			{
				& $RowContext.SetExplicitSelectionDefinition -FunctionName $FunctionName -Definition ([pscustomobject]@{
					Function = $FunctionName
					Type = 'Toggle'
					State = 'On'
					Source = if ((Test-GuiObjectField -Object $currentExplicitDefinition -FieldName 'Source')) { [string]$currentExplicitDefinition.Source } else { 'Preset' }
				})
			}
			if ($RowContext.SyncGameModePlanFromControlsScript)
			{
				& $RowContext.SyncGameModePlanFromControlsScript
			}
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Unchecked' -Handler ({
			$currentExplicitDefinition = & $RowContext.GetExplicitSelectionDefinition -FunctionName $FunctionName
			if ($currentExplicitDefinition -and [string]$currentExplicitDefinition.Type -eq 'Toggle')
			{
				& $RowContext.SetExplicitSelectionDefinition -FunctionName $FunctionName -Definition ([pscustomobject]@{
					Function = $FunctionName
					Type = 'Toggle'
					State = 'Off'
					Source = if ((Test-GuiObjectField -Object $currentExplicitDefinition -FieldName 'Source')) { [string]$currentExplicitDefinition.Source } else { 'Preset' }
				})
			}
			else
			{
				& $RowContext.RemoveExplicitSelectionDefinition -FunctionName $FunctionName
			}
			if ($RowContext.SyncGameModePlanFromControlsScript)
			{
				& $RowContext.SyncGameModePlanFromControlsScript
			}
		}.GetNewClosure())
	}

	function Register-GuiActionSelectionHandlers
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[string]$FunctionName,
			[object]$RowContext
		)

		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Checked' -Handler ({
			$currentExplicitDefinition = & $RowContext.GetExplicitSelectionDefinition -FunctionName $FunctionName
			if ($currentExplicitDefinition -and [string]$currentExplicitDefinition.Type -eq 'Action')
			{
				& $RowContext.SetExplicitSelectionDefinition -FunctionName $FunctionName -Definition ([pscustomobject]@{
					Function = $FunctionName
					Type = 'Action'
					Run = $true
					Source = if ((Test-GuiObjectField -Object $currentExplicitDefinition -FieldName 'Source')) { [string]$currentExplicitDefinition.Source } else { 'Preset' }
				})
			}
			if ($RowContext.SyncGameModePlanFromControlsScript)
			{
				& $RowContext.SyncGameModePlanFromControlsScript
			}
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Unchecked' -Handler ({
			& $RowContext.RemoveExplicitSelectionDefinition -FunctionName $FunctionName
			if ($RowContext.SyncGameModePlanFromControlsScript)
			{
				& $RowContext.SyncGameModePlanFromControlsScript
			}
		}.GetNewClosure())
	}

	function Register-GuiChoiceSelectionHandler
	{
		param (
			[System.Windows.Controls.ComboBox]$ComboBox,
			[string]$FunctionName,
			[object[]]$ChoiceOptions,
			[object]$RowContext
		)

		$comboRef = $ComboBox
		$null = Register-GuiEventHandler -Source $ComboBox -EventName 'SelectionChanged' -Handler ({
			$currentExplicitDefinition = & $RowContext.GetExplicitSelectionDefinition -FunctionName $FunctionName
			if ($comboRef.SelectedIndex -ge 0)
			{
				if ($currentExplicitDefinition -and [string]$currentExplicitDefinition.Type -eq 'Choice' -and $comboRef.SelectedIndex -lt $ChoiceOptions.Count)
				{
					& $RowContext.SetExplicitSelectionDefinition -FunctionName $FunctionName -Definition ([pscustomobject]@{
						Function = $FunctionName
						Type = 'Choice'
						Value = [string]$ChoiceOptions[$comboRef.SelectedIndex]
						Source = if ((Test-GuiObjectField -Object $currentExplicitDefinition -FieldName 'Source')) { [string]$currentExplicitDefinition.Source } else { 'Preset' }
					})
				}
			}
			elseif ($currentExplicitDefinition)
			{
				& $RowContext.RemoveExplicitSelectionDefinition -FunctionName $FunctionName
			}
			if ($RowContext.SyncGameModePlanFromControlsScript)
			{
				& $RowContext.SyncGameModePlanFromControlsScript
			}
		}.GetNewClosure())
	}

	function Finalize-ToggleLikeRow
	{
		param (
			[System.Windows.Controls.Border]$Card,
			[object]$ChildContent,
			[System.Windows.Controls.CheckBox]$CheckBox,
			[object]$Tweak,
			[int]$Index,
			[object]$RowContext
		)

		try { $Card.Child = $ChildContent } catch { throw "Finalize/SetChild: $($_.Exception.Message)" }
		try { Add-CardHoverEffects -Card $Card -FocusSources @($CheckBox) } catch { throw "Finalize/HoverEffects: $($_.Exception.Message)" }
		if ($Tweak.LinkedWith)
		{
			try { & $RowContext.SyncLinkedState $Tweak.LinkedWith ([bool]$CheckBox.IsChecked) } catch { throw "Finalize/SyncLinked: $($_.Exception.Message)" }
		}
		try { $Card.Opacity = if ($CheckBox.IsChecked) { 1.0 } else { 0.7 } } catch { throw "Finalize/Opacity: $($_.Exception.Message)" }
		$cardRef = $Card
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Checked' -Handler ({ $cardRef.Opacity = 1.0 }.GetNewClosure())
		$null = Register-GuiEventHandler -Source $CheckBox -EventName 'Unchecked' -Handler ({ $cardRef.Opacity = 0.7 }.GetNewClosure())
		$Script:Controls[$Index] = $CheckBox
		return $Card
	}

	function New-ToggleTweakRow
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object]$RowContext
		)

		$card = New-TweakRowCard -BrushConverter $RowContext.BrushConverter -Margin $RowContext.RowCardMargin -Padding $RowContext.RowCardPadding -Tweak $Tweak
		$leftStack = New-Object System.Windows.Controls.StackPanel
		$leftStack.Orientation = 'Vertical'
		$leftStack.VerticalAlignment = 'Center'

		$checkBox = New-ToggleLikeCheckBox -Index $Index -InitialChecked (Get-ToggleInitialCheckedState -Index $Index -Tweak $Tweak) -BrushConverter $RowContext.BrushConverter
		Apply-PendingLinkedToggleState -CheckBox $checkBox -FunctionName ([string]$Tweak.Function)
		[void]($leftStack.Children.Add((New-ToggleLikeHeaderGrid -CheckBox $checkBox -Tweak $Tweak -RowContext $RowContext)))

		$statusContext = New-ToggleStatusRow -Tweak $Tweak -CheckBox $checkBox -RowContext $RowContext
		[void]($leftStack.Children.Add($statusContext.Row))
		Add-TweakMetadataDetails -Container $leftStack -Tweak $Tweak -RowContext $RowContext -DescriptionText $(if ($Tweak.Description) { $Tweak.Description } else { 'Turns this feature on when checked and off when unchecked.' }) -DescriptionColor $Script:CurrentTheme.TextSecondary -DescriptionMargin $Script:T.DescIndent -MetadataMargin $Script:T.MetaIndent -BlastMargin $Script:T.BlastIndent
		if ($statusContext.WhyBlock -and $statusContext.WhyBlock.Tag)
		{
			[void]($leftStack.Children.Add($statusContext.WhyBlock.Tag))
		}

		Register-ToggleStatusHandlers -CheckBox $checkBox -StatusContext $statusContext -RowContext $RowContext
		Register-GuiToggleExplicitSelectionHandlers -CheckBox $checkBox -FunctionName ([string]$Tweak.Function) -RowContext $RowContext
		Register-GuiLinkedToggleHandlers -CheckBox $checkBox -LinkedFunction ([string]$Tweak.LinkedWith) -SyncLinkedStateCapture $RowContext.SyncLinkedState
		return Finalize-ToggleLikeRow -Card $card -ChildContent $leftStack -CheckBox $checkBox -Tweak $Tweak -Index $Index -RowContext $RowContext
	}

	function New-ChoiceTweakRow
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object]$RowContext
		)

		$card = New-TweakRowCard -BrushConverter $RowContext.BrushConverter -Margin $RowContext.RowCardMargin -Padding $RowContext.RowCardPadding -Tweak $Tweak
		$grid = New-Object System.Windows.Controls.Grid
		[void]($grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))

		$leftStack = New-Object System.Windows.Controls.StackPanel
		$leftStack.Orientation = 'Vertical'
		$leftStack.VerticalAlignment = 'Center'
		[System.Windows.Controls.Grid]::SetColumn($leftStack, 0)
		[void]($leftStack.Children.Add((New-ChoiceHeaderGrid -Tweak $Tweak -RowContext $RowContext)))
		Add-TweakMetadataDetails -Container $leftStack -Tweak $Tweak -RowContext $RowContext -DescriptionText ([string]$Tweak.Description) -DescriptionColor $Script:CurrentTheme.TextMuted -DescriptionMargin $Script:T.DescFlush -MetadataMargin $Script:T.MetaFlush -BlastMargin $Script:T.BlastFlush
		[void](Add-TweakWhyBlockDetails -Container $leftStack -Tweak $Tweak -LeftIndent 0 -RowMargin $Script:T.WhyFlush)
		[void]($grid.Children.Add($leftStack))

		$combo = New-Object System.Windows.Controls.ComboBox
		$combo.MinWidth = $Script:GuiLayout.ComboBoxMinWidth
		$combo.VerticalAlignment = 'Center'
		$combo.Margin = $Script:T.ComboLeft
		$combo.Tag = $Index
		Set-ChoiceComboStyle -Combo $combo

		$displayOptions = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } elseif ($Tweak.Options) { $Tweak.Options } else { @() }
		$choiceOptions = if ($Tweak.Options) { [object[]]@($Tweak.Options) } else { [object[]]@() }
		for ($optionIndex = 0; $optionIndex -lt $choiceOptions.Count; $optionIndex++)
		{
			[void]($combo.Items.Add($displayOptions[$optionIndex]))
		}

		$initialSelectedIndex = Get-ChoiceInitialSelectedIndex -Index $Index -Tweak $Tweak -ChoiceOptions $choiceOptions -RowContext $RowContext
		[int]$selectedIndex = $initialSelectedIndex
		if ($selectedIndex -lt -1) { $selectedIndex = -1 }
		if ($selectedIndex -ge $combo.Items.Count) { $selectedIndex = -1 }
		$combo.SelectedIndex = [int]$selectedIndex

		Register-GuiChoiceSelectionHandler -ComboBox $combo -FunctionName ([string]$Tweak.Function) -ChoiceOptions $choiceOptions -RowContext $RowContext
		[System.Windows.Controls.Grid]::SetColumn($combo, 1)
		[void]($grid.Children.Add($combo))

		$card.Child = $grid
		Add-CardHoverEffects -Card $card -FocusSources @($combo)
		$Script:Controls[$Index] = $combo
		return $card
	}

	function New-ActionTweakRow
	{
		param (
			[int]$Index,
			[object]$Tweak,
			[object]$RowContext
		)

		$card = New-TweakRowCard -BrushConverter $RowContext.BrushConverter -Margin $RowContext.RowCardMargin -Padding $RowContext.RowCardPadding -Tweak $Tweak
		$checkBox = New-ToggleLikeCheckBox -Index $Index -InitialChecked (Get-ActionInitialCheckedState -Index $Index -Tweak $Tweak) -BrushConverter $RowContext.BrushConverter
		Apply-PendingLinkedToggleState -CheckBox $checkBox -FunctionName ([string]$Tweak.Function)

		$nameRowWithDescription = New-Object System.Windows.Controls.StackPanel
		$nameRowWithDescription.Orientation = 'Vertical'
		try
		{
			[void]($nameRowWithDescription.Children.Add((New-ToggleLikeHeaderGrid -CheckBox $checkBox -Tweak $Tweak -RowContext $RowContext)))
		}
		catch
		{
			throw "New-ActionTweakRow/Header failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		try
		{
			$restorePointHint = if ([string]$Tweak.Function -eq 'CreateRestorePoint') { 'Recommended before applying changes' } else { $null }
			$descriptionText = if ($restorePointHint) { $restorePointHint } elseif ($Tweak.Description) { $Tweak.Description } else { 'Runs this action one time when selected.' }
			Add-TweakMetadataDetails -Container $nameRowWithDescription -Tweak $Tweak -RowContext $RowContext -DescriptionText $descriptionText -DescriptionColor $(if ($restorePointHint) { $Script:CurrentTheme.AccentBlue } else { $Script:CurrentTheme.TextSecondary }) -DescriptionMargin $Script:T.DescIndent -MetadataMargin $Script:T.MetaIndent -BlastMargin $Script:T.BlastIndent
		}
		catch
		{
			throw "New-ActionTweakRow/Metadata failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		try
		{
			[void](Add-TweakWhyBlockDetails -Container $nameRowWithDescription -Tweak $Tweak -LeftIndent 28 -RowMargin $Script:T.WhyIndent)
		}
		catch
		{
			throw "New-ActionTweakRow/WhyBlock failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}

		try
		{
			Register-GuiLinkedToggleHandlers -CheckBox $checkBox -LinkedFunction ([string]$Tweak.LinkedWith) -SyncLinkedStateCapture $RowContext.SyncLinkedState
			Register-GuiActionSelectionHandlers -CheckBox $checkBox -FunctionName ([string]$Tweak.Function) -RowContext $RowContext
		}
		catch
		{
			throw "New-ActionTweakRow/RegisterHandlers failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
		try
		{
			return Finalize-ToggleLikeRow -Card $card -ChildContent $nameRowWithDescription -CheckBox $checkBox -Tweak $Tweak -Index $Index -RowContext $RowContext
		}
		catch
		{
			throw "New-ActionTweakRow/Finalize failed for tweak '$([string]$Tweak.Name)': $($_.Exception.Message)"
		}
	}

	function Build-TweakRow
	{
		param ([int]$Index, [object]$Tweak, [object]$BrushConverter = $null)

		if (-not (Test-TweakRowVisible -Tweak $Tweak))
		{
			return $null
		}

		# Cache shared row context parts that are identical for every row.
		if (-not $Script:RowContextShared -or $Script:RowContextSharedTheme -ne $Script:CurrentThemeName)
		{
			$Script:RowContextShared = @{
				ConvertBrushCapture               = Get-GuiRuntimeCommand -Name 'ConvertTo-GuiBrush' -CommandType 'Function'
				GetExplicitSelectionDefinition    = ${function:Get-GuiExplicitSelectionDefinition}
				SetExplicitSelectionDefinition    = ${function:Set-GuiExplicitSelectionDefinition}
				RemoveExplicitSelectionDefinition = ${function:Remove-GuiExplicitSelectionDefinition}
				SyncGameModePlanFromControlsScript = ${function:Sync-GameModePlanFromGamingControls}
				RowCardMargin                     = [System.Windows.Thickness]::new(8, 2, 8, 2)
				RowCardPadding                    = [System.Windows.Thickness]::new(10, 6, 10, 6)
				BadgeSpacing                      = [System.Windows.Thickness]::new(2, 0, 0, 0)
				SyncLinkedState                   = $syncLinkedState
				FallbackBrushConverter            = New-SafeBrushConverter -Context 'Build-TweakRow'
			}
			$Script:RowContextSharedTheme = $Script:CurrentThemeName
		}
		$shared = $Script:RowContextShared
		$rowContext = [pscustomobject]@{
			BrushConverter                    = if ($BrushConverter) { $BrushConverter } else { $shared.FallbackBrushConverter }
			ConvertBrushCapture               = $shared.ConvertBrushCapture
			GetExplicitSelectionDefinition    = $shared.GetExplicitSelectionDefinition
			SetExplicitSelectionDefinition    = $shared.SetExplicitSelectionDefinition
			RemoveExplicitSelectionDefinition = $shared.RemoveExplicitSelectionDefinition
			SyncGameModePlanFromControlsScript = $shared.SyncGameModePlanFromControlsScript
			Metadata                          = Get-TweakVisualMetadata -Tweak $Tweak -StateSource $Script:Controls[$Index]
			UseCompactRecoveryLevelLabel      = ([string]$Tweak.Category -eq 'Initial Setup')
			RowCardMargin                     = $shared.RowCardMargin
			RowCardPadding                    = $shared.RowCardPadding
			BadgeSpacing                      = $shared.BadgeSpacing
			SyncLinkedState                   = $shared.SyncLinkedState
		}

		switch ($Tweak.Type)
		{
			'Toggle' { return New-ToggleTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
			'Choice' { return New-ChoiceTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
			'Action' { return New-ActionTweakRow -Index $Index -Tweak $Tweak -RowContext $rowContext }
		}

		return $null
	}
	#endregion

