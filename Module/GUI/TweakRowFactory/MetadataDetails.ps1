
	<#
	    .SYNOPSIS
	#>
	function Set-TweakSearchHighlightedTextBlock
	{
		param (
			[System.Windows.Controls.TextBlock]$TextBlock,
			[string]$Text,
			[object]$BrushConverter
		)

		if (-not $TextBlock) { return }
		$query = if ($null -ne $Script:SearchText) { [string]$Script:SearchText.Trim() } else { '' }
		if ([string]::IsNullOrWhiteSpace($query) -or [string]::IsNullOrWhiteSpace($Text))
		{
			$TextBlock.Text = [string]$Text
			return
		}

		$comparison = [System.StringComparison]::OrdinalIgnoreCase
		$startIndex = 0
		$matchIndex = ([string]$Text).IndexOf($query, $startIndex, $comparison)
		if ($matchIndex -lt 0)
		{
			$TextBlock.Text = [string]$Text
			return
		}

		$TextBlock.Inlines.Clear()
		$highlightBg = if ($Script:CurrentTheme -and $Script:CurrentTheme.SearchHighlightBg) { [string]$Script:CurrentTheme.SearchHighlightBg } else { '#FDE68A' }
		$highlightFg = if ($Script:CurrentTheme -and $Script:CurrentTheme.SearchHighlightText) { [string]$Script:CurrentTheme.SearchHighlightText } else { '#111827' }
		$highlightBgBrush = $BrushConverter.ConvertFromString($highlightBg)
		$highlightFgBrush = $BrushConverter.ConvertFromString($highlightFg)
		while ($matchIndex -ge 0)
		{
			if ($matchIndex -gt $startIndex)
			{
				$prefix = New-Object System.Windows.Documents.Run
				$prefix.Text = ([string]$Text).Substring($startIndex, $matchIndex - $startIndex)
				[void]($TextBlock.Inlines.Add($prefix))
			}

			$matchRun = New-Object System.Windows.Documents.Run
			$matchRun.Text = ([string]$Text).Substring($matchIndex, $query.Length)
			$matchRun.Background = $highlightBgBrush
			$matchRun.Foreground = $highlightFgBrush
			$matchRun.FontWeight = [System.Windows.FontWeights]::SemiBold
			[void]($TextBlock.Inlines.Add($matchRun))

			$startIndex = $matchIndex + $query.Length
			if ($startIndex -ge ([string]$Text).Length) { break }
			$matchIndex = ([string]$Text).IndexOf($query, $startIndex, $comparison)
		}

		if ($startIndex -lt ([string]$Text).Length)
		{
			$suffix = New-Object System.Windows.Documents.Run
			$suffix.Text = ([string]$Text).Substring($startIndex)
			[void]($TextBlock.Inlines.Add($suffix))
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Get-CardHoverResources
	{
		$themeName = if ($Script:CurrentThemeName) { $Script:CurrentThemeName } else { 'Dark' }
		if ($Script:CardHoverResources -and $Script:CardHoverResources.ThemeName -eq $themeName)
		{
			return $Script:CardHoverResources
		}
		$bc = New-SafeBrushConverter -Context 'Get-CardHoverResources'
		$isLight = ($Script:CurrentTheme -eq $Script:LightTheme)
		$shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
		$shadow.Color = [System.Windows.Media.Colors]::Black
		$shadow.Direction = 270
		$shadow.ShadowDepth = 0
		$shadow.Opacity = if ($isLight) { 0.04 } else { 0.18 }
		$shadow.BlurRadius = if ($isLight) { 8 } else { 18 }
		if ($shadow.CanFreeze) { $shadow.Freeze() }
		$Script:CardHoverResources = @{
			ThemeName      = $themeName
			Shadow         = $shadow
			DefaultBg      = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
			HoverBg        = $bc.ConvertFromString($Script:CurrentTheme.CardHoverBg)
			PressBg        = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
			DefaultBorder  = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
			HoverBorder    = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
			FocusBorder    = $bc.ConvertFromString($Script:CurrentTheme.FocusRing)
			Thickness1     = if ($isLight) { $Script:T.CardBorder } else { $Script:T.RowDivider }
			Thickness2     = if ($isLight) { $Script:T.CardBorderFocus } else { $Script:T.RowDividerFocus }
		}
		return $Script:CardHoverResources
	}

	<#
	    .SYNOPSIS
	#>

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
		$Card.Add_MouseEnter({ try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_MouseEnter' } }.GetNewClosure())
		$Card.Add_MouseLeave({ try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_MouseLeave' } }.GetNewClosure())
		$pressBg = $res.PressBg
		$pressHandler = {
			$Card.Background = $pressBg
		}.GetNewClosure()
		$Card.Add_PreviewMouseLeftButtonDown({ try { & $pressHandler } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_PreviewMouseLeftButtonDown' } }.GetNewClosure())
		$Card.Add_PreviewMouseLeftButtonUp({ try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_PreviewMouseLeftButtonUp' } }.GetNewClosure())
		foreach ($focusSource in $FocusSources)
		{
			if (-not $focusSource) { continue }
			$focusSource.Add_GotKeyboardFocus({ try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_GotKeyboardFocus' } }.GetNewClosure())
			$focusSource.Add_LostKeyboardFocus({ try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.Add_LostKeyboardFocus' } }.GetNewClosure())
		}
		try { & $updateChrome } catch { Write-SwallowedException -ErrorRecord $_ -Source 'TweakRowFactory.Build-TweakRowCard.UpdateChrome' }
	}

	<#
	    .SYNOPSIS
	#>

	function Get-CompatibilityBadgeInfo
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[AllowNull()]
			[string]$Label
		)

		if ([string]::IsNullOrWhiteSpace($Label))
		{
			return $null
		}

		switch ([string]$Label.Trim())
		{
			'Windows10Only'
			{
				return [pscustomobject]@{
					Label = Get-UxString -Key 'GuiCompatibilityBadgeWindows10Only' -Fallback 'Windows 10 only'
					Tone = 'Primary'
					ToolTip = Get-UxString -Key 'GuiCompatibilityBadgeTooltipWindows10Only' -Fallback 'This item targets Windows 10 only.'
				}
			}
			'Windows11Only'
			{
				return [pscustomobject]@{
					Label = Get-UxString -Key 'GuiCompatibilityBadgeWindows11Only' -Fallback 'Windows 11 only'
					Tone = 'Primary'
					ToolTip = Get-UxString -Key 'GuiCompatibilityBadgeTooltipWindows11Only' -Fallback 'This item targets Windows 11 only.'
				}
			}
			'ServerOnly'
			{
				return [pscustomobject]@{
					Label = Get-UxString -Key 'GuiCompatibilityBadgeServerOnly' -Fallback 'Server only'
					Tone = 'Primary'
					ToolTip = Get-UxString -Key 'GuiCompatibilityBadgeTooltipServerOnly' -Fallback 'This item targets Server only.'
				}
			}
			'ClientOnly'
			{
				return [pscustomobject]@{
					Label = Get-UxString -Key 'GuiCompatibilityBadgeClientOnly' -Fallback 'Client only'
					Tone = 'Primary'
					ToolTip = Get-UxString -Key 'GuiCompatibilityBadgeTooltipClientOnly' -Fallback 'This item targets Client only.'
				}
			}
			default
			{
				return $null
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Add-TweakScenarioTagsToDetailsPanel
	{
		param (
			[System.Windows.Controls.Border]$DetailsHost,
			[object]$RowContext
		)

		if (-not $DetailsHost -or -not $RowContext -or -not $RowContext.Metadata) { return }
		if (-not (Test-GuiObjectField -Object $RowContext.Metadata -FieldName 'ScenarioTags') -or -not $RowContext.Metadata.ScenarioTags) { return }

		$contentStack = if ($DetailsHost.Child -is [System.Windows.Controls.StackPanel])
		{
			$DetailsHost.Child
		}
		else
		{
			$existingChild = $DetailsHost.Child
			$stack = [System.Windows.Controls.StackPanel]::new()
			$stack.Orientation = 'Vertical'
			if ($existingChild)
			{
				$DetailsHost.Child = $null
				[void]($stack.Children.Add($existingChild))
			}
			$DetailsHost.Child = $stack
			$stack
		}

		$scenarioTags = @($RowContext.Metadata.ScenarioTags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
		if ($scenarioTags.Count -eq 0) { return }

		$tagBackground = if ($Script:CurrentTheme -and $Script:CurrentTheme.TabActiveBg) { [string]$Script:CurrentTheme.TabActiveBg } else { '#262D40' }
		$tagBorder = if ($Script:CurrentTheme -and $Script:CurrentTheme.AccentBlue) { [string]$Script:CurrentTheme.AccentBlue } else { '#7CB7FF' }
		$tagForeground = if ($Script:CurrentTheme -and $Script:CurrentTheme.AccentHover) { [string]$Script:CurrentTheme.AccentHover } else { '#9ACAFF' }
		$scenarioTagToolTip = Get-UxString -Key 'GuiTweakChipTooltipScenarioTag' -Fallback 'Scenario tag'
		$moreTagsToolTip = Get-UxString -Key 'GuiTweakChipTooltipMoreTags' -Fallback 'Additional scenario tags are present in the manifest.'
		$moreTagsFormat = Get-UxString -Key 'GuiTweakChipMoreFormat' -Fallback '+{0} more'

		$tagsPanel = [System.Windows.Controls.WrapPanel]::new()
		$tagsPanel.Orientation = 'Horizontal'
		$tagsPanel.HorizontalAlignment = 'Left'
		$tagsPanel.Margin = [System.Windows.Thickness]::new(0, 7, 0, -5)

		$addTagPill = {
			param (
				[string]$Label,
				[string]$ToolTip
			)

			if ([string]::IsNullOrWhiteSpace($Label)) { return }

			$pill = [System.Windows.Controls.Border]::new()
			$pill.Background = $RowContext.BrushConverter.ConvertFromString($tagBackground)
			$pill.BorderBrush = $RowContext.BrushConverter.ConvertFromString($tagBorder)
			$pill.BorderThickness = [System.Windows.Thickness]::new(1)
			$pill.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
			$pill.Margin = [System.Windows.Thickness]::new(0, 0, 6, 5)
			$pill.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
			$pill.VerticalAlignment = 'Center'
			$pill.ToolTip = $ToolTip

			$text = [System.Windows.Controls.TextBlock]::new()
			$text.Text = $Label
			$text.FontSize = $RowContext.DetailFontSize
			$text.LineHeight = $RowContext.DetailLineHeight
			$text.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
			$text.FontWeight = [System.Windows.FontWeights]::SemiBold
			$text.Foreground = $RowContext.BrushConverter.ConvertFromString($tagForeground)
			$pill.Child = $text
			[void]($tagsPanel.Children.Add($pill))
		}

		foreach ($tag in @($scenarioTags | Select-Object -First 4))
		{
			& $addTagPill -Label ([string]$tag) -ToolTip $scenarioTagToolTip
		}
		if ($scenarioTags.Count -gt 4)
		{
			& $addTagPill -Label ($moreTagsFormat -f ($scenarioTags.Count - 4)) -ToolTip $moreTagsToolTip
		}

		if ($tagsPanel.Children.Count -eq 0) { return }
		[void]($contentStack.Children.Add($tagsPanel))
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

		$descriptionTextBlock = [System.Windows.Controls.TextBlock]::new()
		Set-TweakSearchHighlightedTextBlock -TextBlock $descriptionTextBlock -Text $DescriptionText -BrushConverter $RowContext.BrushConverter
		$descriptionTextBlock.FontSize = $RowContext.DetailFontSize
		$descriptionTextBlock.LineHeight = $RowContext.DetailLineHeight
		$descriptionTextBlock.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
		$descriptionTextBlock.Foreground = $RowContext.BrushConverter.ConvertFromString($DescriptionColor)
		$descriptionTextBlock.Margin = $DescriptionMargin
		$descriptionTextBlock.TextWrapping = 'Wrap'
		[void]($Container.Children.Add($descriptionTextBlock))

		# Show CautionReason inline on the tweak row for High-risk items so the
		# consequence text is visible by default without expanding the caution section.
		if ([string]$Tweak.Risk -eq 'High' -and [bool]$Tweak.Caution -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.CautionReason))
		{
			$cautionColor = if ($Script:CurrentTheme -and $Script:CurrentTheme.CautionText) { $Script:CurrentTheme.CautionText } else { '#E5A84B' }
			$cautionInline = [System.Windows.Controls.TextBlock]::new()
			$cautionInline.TextWrapping = 'Wrap'
			$cautionInline.Margin = $DescriptionMargin
			$cautionInline.FontSize = $RowContext.DetailFontSize
			$cautionInline.LineHeight = $RowContext.DetailLineHeight
			$cautionInline.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
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
			$detailMetaPanel = New-TweakMetadataChipPanel -Metadata $RowContext.Metadata -IncludeType:$false -IncludeState:$false -IncludeRestart:$false -IncludeRestorable:$false -IncludeRecoveryLevel:$true -UseCompactRecoveryLevelLabel:$RowContext.UseCompactRecoveryLevelLabel -IncludeScenarioTags:$false
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

		if (-not [bool]$RowContext.Metadata.MatchesDesired -and -not [string]::IsNullOrWhiteSpace([string]$RowContext.Metadata.BlastRadius))
		{
			$blastText = [System.Windows.Controls.TextBlock]::new()
			$blastText.Text = [string]$RowContext.Metadata.BlastRadius
			$blastText.TextWrapping = 'Wrap'
			$blastText.Margin = $BlastMargin
			$blastText.FontSize = $RowContext.DetailFontSize
			$blastText.LineHeight = $RowContext.DetailLineHeight
			$blastText.LineStackingStrategy = [System.Windows.LineStackingStrategy]::BlockLineHeight
			$blastText.Foreground = $RowContext.BrushConverter.ConvertFromString($Script:CurrentTheme.TextSecondary)
			[void]($Container.Children.Add($blastText))
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Add-TweakWhyBlockDetails
	{
		param (
			[System.Windows.Controls.Panel]$Container,
			[object]$Tweak,
			[object]$RowContext = $null,
			[int]$LeftIndent = 0,
			[System.Windows.Thickness]$RowMargin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		)

		if ((Test-GuiObjectField -Object $Tweak -FieldName '_RowDetailsPanel') -and $Tweak._RowDetailsPanel)
		{
			return $null
		}

		$whyBlock = New-WhyThisMattersButton -Tweak $Tweak -LeftIndent $LeftIndent
		if (-not $whyBlock)
		{
			return $null
		}

		$whyRow = [System.Windows.Controls.Grid]::new()
		[void]($whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })))
		[void]($whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto })))
		$whyRow.Margin = $RowMargin
		[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
		[void]($whyRow.Children.Add($whyBlock))
		[void]($Container.Children.Add($whyRow))
		if ($whyBlock.Tag)
		{
			if ($RowContext)
			{
				Add-TweakScenarioTagsToDetailsPanel -DetailsHost $whyBlock.Tag -RowContext $RowContext
			}
			[void]($Container.Children.Add($whyBlock.Tag))
		}

		return $whyBlock
	}

