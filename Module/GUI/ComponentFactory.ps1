# WPF component factory functions: info icons, badges, status pills, scenario tags

	<#
	    .SYNOPSIS
	#>

	function Build-InfoIconTooltipContent
	{
		param (
			[string]$TooltipText,
			[object]$Tweak
		)

		$bc = New-SafeBrushConverter -Context 'New-InfoIcon'
		$theme = $Script:CurrentTheme

		$stackPanel = New-Object System.Windows.Controls.StackPanel
		$stackPanel.Margin = [System.Windows.Thickness]::new(4, 3, 4, 3)
		$stackPanel.MaxWidth = $Script:GuiLayout.TooltipMaxWidth

		# Description (bold)
		$tb = New-Object System.Windows.Controls.TextBlock
		$tb.Text = if ([string]::IsNullOrWhiteSpace($TooltipText)) { Get-UxString -Key 'GuiTooltipDefaultText' -Fallback 'This option changes a Windows setting.' } else { $TooltipText.Trim() }
		$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$tb.FontWeight = [System.Windows.FontWeights]::SemiBold
		$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeSubheading' -Default 12
		[void]($stackPanel.Children.Add($tb))
		# Detail text
		$detailText = Get-GuiObjectField -Object $Tweak -FieldName 'Detail'
		if (-not [string]::IsNullOrWhiteSpace([string]$detailText))
		{
			$detailValue = [string]$detailText
			if (Test-GuiObjectField -Object $Tweak -FieldName 'DetailKey')
			{
				$detailValue = Get-UxString -Key ([string]$Tweak.DetailKey) -Fallback $detailValue
			}
			else
			{
				$whyRawForDetail = if ((Test-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) { [string]$Tweak.WhyThisMatters } else { $null }
				if ($whyRawForDetail -and (Test-GuiObjectField -Object $Tweak -FieldName 'WhyKey') -and ($detailValue -eq $whyRawForDetail))
				{
					$detailValue = Get-UxString -Key ([string]$Tweak.WhyKey) -Fallback $detailValue
				}
			}
			$tb = New-Object System.Windows.Controls.TextBlock
			$tb.Text = $detailValue.Trim()
			$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
			$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			[void]($stackPanel.Children.Add($tb))
		}

		if ($Tweak)
		{
			# Separator
			$sep = New-Object System.Windows.Controls.Separator
			$sep.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
			[void]($stackPanel.Children.Add($sep))
			$addSectionHeader = {
				param([string]$Text)
				$section = New-Object System.Windows.Controls.TextBlock
				$section.Text = $Text.ToUpperInvariant()
				$section.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeSmall' -Default 10
				$section.FontWeight = [System.Windows.FontWeights]::Bold
				$section.Foreground = $bc.ConvertFromString($theme.SectionLabel)
				$section.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
				[void]($stackPanel.Children.Add($section))
			}

			# Toggle / Choice / Action lines
			& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionBehavior' -Fallback 'Behavior')
			switch ($Tweak.Type)
			{
				'Toggle' {
					$onLabel  = if ($Tweak.OnParam)  { Get-UxString -Key "GuiToggleFallback$($Tweak.OnParam)" -Fallback $Tweak.OnParam  } else { Get-UxString -Key 'GuiToggleFallbackEnable'  -Fallback 'Enable'  }
					$offLabel = if ($Tweak.OffParam) { Get-UxString -Key "GuiToggleFallback$($Tweak.OffParam)" -Fallback $Tweak.OffParam } else { Get-UxString -Key 'GuiToggleFallbackDisable' -Fallback 'Disable' }
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailCheckedToggle' -Fallback 'Checked: {0}' -FormatArgs @($onLabel))
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailUncheckedToggle' -Fallback 'Unchecked: {0}' -FormatArgs @($offLabel))
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
				}
				'Choice' {
					$displayOpts = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } else { $Tweak.Options }
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailChoices' -Fallback 'Choices: {0}' -FormatArgs @(($displayOpts -join ', ')))
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
				}
				'Date' {
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailDateChecked' -Fallback 'Checked: pause updates starting on the selected date')
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailDateUnchecked' -Fallback 'Unchecked: pause updates are cleared')
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
				}
				'Action' {
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailActionChecked' -Fallback 'Checked: this action runs when you click {0}' -FormatArgs @((Get-UxRunActionLabel)))
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailActionUnchecked' -Fallback 'Unchecked: this action is skipped')
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]($stackPanel.Children.Add($tb))
				}
			}

			# Current state indicator
			$stateLabel = Get-GuiObjectField -Object $Tweak -FieldName '_StateLabel'
			$matchesDesired = if ((Test-GuiObjectField -Object $Tweak -FieldName '_MatchesDesired')) { [bool]$Tweak._MatchesDesired } else { $false }
			$visualStateCacheVariable = Get-Variable -Name 'TweakVisualStateByFunction' -Scope Script -ErrorAction SilentlyContinue
			if ([string]::IsNullOrWhiteSpace([string]$stateLabel) -and $visualStateCacheVariable -and ($visualStateCacheVariable.Value -is [hashtable]))
			{
				$visualStateKey = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Function') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Function))
				{
					[string]$Tweak.Function
				}
				else
				{
					[string][System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Tweak)
				}
				$tweakVisualStateByFunction = $visualStateCacheVariable.Value
				if ($tweakVisualStateByFunction.ContainsKey($visualStateKey))
				{
					$visualState = $tweakVisualStateByFunction[$visualStateKey]
					$stateLabel = [string]$visualState.StateLabel
					$matchesDesired = [bool]$visualState.MatchesDesired
				}
			}
			if (-not [string]::IsNullOrWhiteSpace([string]$stateLabel))
			{
				$sepState = New-Object System.Windows.Controls.Separator
				$sepState.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepState))
				& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionCurrentState' -Fallback 'Current State')
				$stateRow = New-Object System.Windows.Controls.TextBlock
				$stateRow.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$stateRow.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				if ($matchesDesired)
				{
					$stateRow.Text = (Get-UxLocalizedString -Key 'GuiDetailNoChangeNeeded' -Fallback ("{0} {1} no change needed" -f $stateLabel, ([char]0x2014)))
					$stateRow.Foreground = $bc.ConvertFromString($theme.LowRiskBadge)
				}
				else
				{
					$stateRow.Text = (Get-UxLocalizedString -Key 'GuiDetailWillChange' -Fallback ("Will change {0} not currently at desired state" -f ([char]0x2014)))
					$stateRow.Foreground = $bc.ConvertFromString($theme.AccentBlue)
				}
				[void]($stackPanel.Children.Add($stateRow))
			}

			$winDefaultDesc = Get-GuiObjectField -Object $Tweak -FieldName 'WinDefaultDesc'
			$winDefaultValue = Get-GuiObjectField -Object $Tweak -FieldName 'WinDefault'
			$winDefRaw = if (-not [string]::IsNullOrWhiteSpace([string]$winDefaultDesc)) {
				[string]$winDefaultDesc
			} elseif ($null -ne $winDefaultValue -and -not [string]::IsNullOrWhiteSpace([string]$winDefaultValue)) {
				[string]$winDefaultValue
			} else {
				$null
			}
			$winDefText = if ($winDefRaw -and (Test-GuiObjectField -Object $Tweak -FieldName 'WinDefaultKey')) {
				Get-UxString -Key ([string]$Tweak.WinDefaultKey) -Fallback $winDefRaw
			} else { $winDefRaw }
			if ($winDefText)
			{
				$sepDefault = New-Object System.Windows.Controls.Separator
				$sepDefault.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepDefault))
				& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionDefaultReference' -Fallback 'Default reference')
				$tb = New-Object System.Windows.Controls.TextBlock
				$tb.Text = $winDefText
				$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$tb.Foreground = $bc.ConvertFromString($theme.TextMuted)
				[void]($stackPanel.Children.Add($tb))
			}

			$sepRisk = New-Object System.Windows.Controls.Separator
			$sepRisk.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
			[void]($stackPanel.Children.Add($sepRisk))
			& $addSectionHeader (Get-UxLocalizedString -Key 'GuiRiskLevelLabel' -Fallback 'Risk')
			$riskLevel = if ([string]::IsNullOrWhiteSpace($Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
			$riskRow = New-Object System.Windows.Controls.StackPanel
			$riskRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
			$riskLbl = New-Object System.Windows.Controls.TextBlock
			$riskLbl.Text = (Get-UxLocalizedString -Key 'GuiRiskLevelLabel' -Fallback 'Level: ')
			$riskLbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
			$riskLbl.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
			[void]($riskRow.Children.Add($riskLbl))
			$riskVal = New-Object System.Windows.Controls.TextBlock
			$riskVal.Text = if ($riskLevel -eq 'Low') { (Get-UxLocalizedString -Key 'GuiRiskLow' -Fallback 'Low Risk') } elseif ($riskLevel -eq 'High') { (Get-UxLocalizedString -Key 'GuiRiskHigh' -Fallback 'High Risk') } else { (Get-UxLocalizedString -Key 'GuiRiskMedium' -Fallback 'Medium Risk') }
			$riskVal.FontWeight = [System.Windows.FontWeights]::SemiBold
			$riskVal.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
			if ($riskLevel -eq 'High')
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
			}
			elseif ($riskLevel -eq 'Medium')
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.RiskMediumBadge)
			}
			else
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.LowRiskBadge)
			}
			[void]($riskRow.Children.Add($riskVal))
			[void]($stackPanel.Children.Add($riskRow))
			# Caution reason
			if ($Tweak.Caution -and $Tweak.CautionReason)
			{
				$tb = New-Object System.Windows.Controls.TextBlock
				$tb.Text = (Get-UxLocalizedString -Key 'GuiDetailWhyNeedsCare' -Fallback 'Why this needs care: {0}' -FormatArgs @($Tweak.CautionReason))
				$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$tb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
				[void]($stackPanel.Children.Add($tb))
			}

			# Restore row
			if (Test-GuiObjectField -Object $Tweak -FieldName 'Restorable')
			{
				$sep2 = New-Object System.Windows.Controls.Separator
				$sep2.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
				[void]($stackPanel.Children.Add($sep2))
				$restoreRow = New-Object System.Windows.Controls.StackPanel
				$restoreRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal

				$lbl = New-Object System.Windows.Controls.TextBlock
				$lbl.Text = (Get-UxLocalizedString -Key 'GuiRestoreLabel' -Fallback 'Restore: ')
				$lbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$lbl.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				[void]($restoreRow.Children.Add($lbl))
				$val = New-Object System.Windows.Controls.TextBlock
				$val.FontWeight = [System.Windows.FontWeights]::SemiBold
				$val.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				if ($Tweak.Restorable)
				{
					$val.Text = (Get-UxLocalizedString -Key 'GuiRestorePossible' -Fallback 'Possible')
					$val.Foreground = $bc.ConvertFromString($theme.ToggleOn)
				}
				else
				{
					$val.Text = (Get-UxLocalizedString -Key 'GuiRestoreNotPossible' -Fallback 'Not possible - this change is permanent')
					$val.Foreground = $bc.ConvertFromString($theme.ToggleOff)
				}
				[void]($restoreRow.Children.Add($val))
				[void]($stackPanel.Children.Add($restoreRow))
			}

			# Impact level
			$impactLevel = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Impact') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Impact)) { [string]$Tweak.Impact } else { $null }
			if ($impactLevel)
			{
				$sepImpact = New-Object System.Windows.Controls.Separator
				$sepImpact.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepImpact))
				& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionImpact' -Fallback 'Impact')
				$impactRow = New-Object System.Windows.Controls.StackPanel
				$impactRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
				$impactLbl = New-Object System.Windows.Controls.TextBlock
				$impactLbl.Text = (Get-UxLocalizedString -Key 'GuiDetailLevelLabel' -Fallback 'Level: ')
				$impactLbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$impactLbl.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				[void]($impactRow.Children.Add($impactLbl))
				$impactVal = New-Object System.Windows.Controls.TextBlock
				$impactVal.Text = $impactLevel
				$impactVal.FontWeight = [System.Windows.FontWeights]::SemiBold
				$impactVal.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$impactVal.Foreground = $bc.ConvertFromString($(
					if ($impactLevel -eq 'High') { $theme.RiskHighBadge }
					elseif ($impactLevel -eq 'Medium') { $theme.RiskMediumBadge }
					else { $theme.LowRiskBadge }
				))
				[void]($impactRow.Children.Add($impactVal))
				[void]($stackPanel.Children.Add($impactRow))
			}

			# WhyThisMatters (shown separately from the Detail text above)
			$whyRaw = if ((Test-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) { [string]$Tweak.WhyThisMatters } else { $null }
			$whyText = if ($whyRaw -and (Test-GuiObjectField -Object $Tweak -FieldName 'WhyKey')) { Get-UxString -Key ([string]$Tweak.WhyKey) -Fallback $whyRaw } else { $whyRaw }
			$detailAlready = if ((Test-GuiObjectField -Object $Tweak -FieldName 'Detail') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.Detail)) { [string]$Tweak.Detail } else { $null }
			if ($whyText -and $whyText -ne $detailAlready)
			{
				$sepWhy = New-Object System.Windows.Controls.Separator
				$sepWhy.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepWhy))
				& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionWhyThisMatters' -Fallback 'Why This Matters')
				$whyTb = New-Object System.Windows.Controls.TextBlock
				$whyTb.Text = $whyText.Trim()
				$whyTb.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$whyTb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$whyTb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				[void]($stackPanel.Children.Add($whyTb))
			}

			# Recovery level
			$recoveryLevel = if ((Test-GuiObjectField -Object $Tweak -FieldName 'RecoveryLevel') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.RecoveryLevel)) { [string]$Tweak.RecoveryLevel } else { $null }
			if ($recoveryLevel)
			{
				$sepRecovery = New-Object System.Windows.Controls.Separator
				$sepRecovery.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepRecovery))
				& $addSectionHeader (Get-UxLocalizedString -Key 'GuiSectionRecovery' -Fallback 'Recovery')
				$recoveryRow = New-Object System.Windows.Controls.StackPanel
				$recoveryRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
				$recoveryLbl = New-Object System.Windows.Controls.TextBlock
				$recoveryLbl.Text = (Get-UxLocalizedString -Key 'GuiDetailRecoveryLabel' -Fallback 'Recovery: ')
				$recoveryLbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$recoveryLbl.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				[void]($recoveryRow.Children.Add($recoveryLbl))
				$recoveryVal = New-Object System.Windows.Controls.TextBlock
				$recoveryVal.FontWeight = [System.Windows.FontWeights]::SemiBold
				$recoveryVal.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$recoveryVal.Text = switch ($recoveryLevel)
				{
					'Direct'       { Get-UxString -Key 'GuiRecoveryDirect'       -Fallback 'Directly reversible' }
					'RestorePoint' { Get-UxString -Key 'GuiRecoveryRestorePoint' -Fallback 'Restore point recovery' }
					'Manual'       { Get-UxString -Key 'GuiRecoveryManual'       -Fallback 'Manual recovery' }
					'DefaultsOnly' { Get-UxString -Key 'GuiRecoveryDefaultsOnly' -Fallback 'Defaults-only recovery' }
					default        { $recoveryLevel }
				}
				$recoveryVal.Foreground = $bc.ConvertFromString($(
					if ($recoveryLevel -eq 'Direct') { $theme.ToggleOn }
					elseif ($recoveryLevel -eq 'Manual') { $theme.RiskHighBadge }
					else { $theme.RiskMediumBadge }
				))
				[void]($recoveryRow.Children.Add($recoveryVal))
				[void]($stackPanel.Children.Add($recoveryRow))
			}

			# RequiresRestart indicator
			if ((Test-GuiObjectField -Object $Tweak -FieldName 'RequiresRestart') -and [bool]$Tweak.RequiresRestart)
			{
				$sepRestart = New-Object System.Windows.Controls.Separator
				$sepRestart.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				[void]($stackPanel.Children.Add($sepRestart))
				$restartTb = New-Object System.Windows.Controls.TextBlock
				$restartTb.Text = ([char]0x21BB).ToString() + ' ' + (Get-UxString -Key 'GuiRestartRequiredDetail' -Fallback 'Restart required for this change to take effect')
				$restartTb.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
				$restartTb.FontWeight = [System.Windows.FontWeights]::SemiBold
				$restartTb.Foreground = $bc.ConvertFromString($theme.RiskMediumBadge)
				[void]($stackPanel.Children.Add($restartTb))
			}
		}

		return $stackPanel
	}

	<#
	    .SYNOPSIS
	#>

	function New-InfoIcon
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$TooltipText,
			[object]$Tweak
		)

		$theme = $Script:CurrentTheme

		$icon = [System.Windows.Controls.TextBlock]::new()
		$icon.Text = [char]0x24D8  # info icon
		$icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI Symbol')
		$icon.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeSection' -Default 14
		$icon.Foreground = ConvertTo-GuiBrush -Color $theme.AccentBlue -Context 'New-InfoIcon'
		$icon.VerticalAlignment = "Center"
		$icon.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$icon.Cursor = [System.Windows.Input.Cursors]::Help

		$tip = [System.Windows.Controls.ToolTip]::new()
		$tip.MaxWidth = 360
		$tip.Padding = [System.Windows.Thickness]::new(8, 6, 8, 6)
		$tip.Background = ConvertTo-GuiBrush -Color $theme.CardBg -Context 'New-InfoIcon'
		$tip.Foreground = ConvertTo-GuiBrush -Color $theme.TextPrimary -Context 'New-InfoIcon'
		$tip.BorderBrush = ConvertTo-GuiBrush -Color $theme.CardBorder -Context 'New-InfoIcon'
		$tip.BorderThickness = [System.Windows.Thickness]::new(1)
		$tip.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Custom
		$tip.HasDropShadow = $true
		$tip.StaysOpen = $true
		if (-not $Script:InfoIconPopupCallback)
		{
			$Script:InfoIconPopupCallback = [System.Windows.Controls.Primitives.CustomPopupPlacementCallback]{
				param (
					[System.Windows.Size]$popupSize,
					[System.Windows.Size]$targetSize,
					[System.Windows.Point]$offset
				)
				$hGap = 12; $vGap = 8
				return @(
					[System.Windows.Controls.Primitives.CustomPopupPlacement]::new([System.Windows.Point]::new(($targetSize.Width + $hGap), $vGap), [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Horizontal),
					[System.Windows.Controls.Primitives.CustomPopupPlacement]::new([System.Windows.Point]::new((-$popupSize.Width - $hGap), $vGap), [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Horizontal),
					[System.Windows.Controls.Primitives.CustomPopupPlacement]::new([System.Windows.Point]::new(($targetSize.Width + $hGap), (-$popupSize.Height + $targetSize.Height - $vGap)), [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical),
					[System.Windows.Controls.Primitives.CustomPopupPlacement]::new([System.Windows.Point]::new((-$popupSize.Width - $hGap), (-$popupSize.Height + $targetSize.Height - $vGap)), [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical)
				)
			}
		}
		$tip.CustomPopupPlacementCallback = $Script:InfoIconPopupCallback

		# Lazy-build tooltip content on first hover - defers the (relatively
		# expensive) rich-content construction until the user actually hovers.
		# The $contentBuilt hashtable acts as a one-shot flag; once set, the
		# ToolTipOpening handler becomes a no-op for subsequent hovers.
		$tooltipTextCapture = $TooltipText
		$tweakCapture = $Tweak
		$buildContentScript = ${function:Build-InfoIconTooltipContent}
		$tipRef = $tip
		$contentBuilt = @{ Done = $false }
		$null = Register-GuiEventHandler -Source $icon -EventName 'ToolTipOpening' -Handler ({
			if (-not $contentBuilt.Done)
			{
				$contentBuilt.Done = $true
				$tipRef.Content = & $buildContentScript -TooltipText $tooltipTextCapture -Tweak $tweakCapture
			}
		}.GetNewClosure())
		$icon.ToolTip = $tip

		$null = Register-GuiEventHandler -Source $icon -EventName 'MouseLeave' -Handler ({
			if ($tipRef.IsOpen) { $tipRef.IsOpen = $false }
		}.GetNewClosure())

		return $icon
	}

	<#
	    .SYNOPSIS
	#>

	function New-ImpactBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$border = [System.Windows.Controls.Border]::new()
		$border.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ImpactBadgeBg -Context 'New-ImpactBadge/Background'
		$border.BorderBrush = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ImpactBadgeBg -Context 'New-ImpactBadge/BorderBrush'
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(3)
		$border.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$border.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$border.VerticalAlignment = "Center"

		$txt = [System.Windows.Controls.TextBlock]::new()
		$txt.Text = (Get-UxLocalizedString -Key 'GuiImpactBadge' -Fallback 'Impact')
		$txt.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeSmall' -Default 10
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$txt.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ImpactBadge -Context 'New-ImpactBadge/Foreground'

		$border.Child = $txt
		return $border
	}

	<#
	    .SYNOPSIS
	#>

	function New-RiskBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Level)
		$bc = New-SafeBrushConverter -Context 'New-RiskBadge'
		$border = [System.Windows.Controls.Border]::new()
		$border.CornerRadius = [System.Windows.CornerRadius]::new(4)
		$border.Padding = [System.Windows.Thickness]::new(7, 2, 7, 2)
		$border.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$border.VerticalAlignment = "Center"
		$border.BorderThickness = [System.Windows.Thickness]::new(1)

		$txt = [System.Windows.Controls.TextBlock]::new()
		$txt.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeSmall' -Default 10
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$riskLevel = if ([string]::IsNullOrWhiteSpace($Level)) { 'Low' } else { [string]$Level }

		if ($riskLevel -eq 'High')
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadgeBg)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadge)
			$txt.Text = (Get-UxLocalizedString -Key 'GuiRiskHigh' -Fallback 'High Risk')
		}
		elseif ($riskLevel -eq 'Medium')
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadgeBg)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
			$txt.Text = (Get-UxLocalizedString -Key 'GuiRiskMedium' -Fallback 'Medium Risk')
		}
		else
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadgeBg)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadge)
			$txt.Text = (Get-UxLocalizedString -Key 'GuiRiskLow' -Fallback 'Low Risk')
		}

		$border.Child = $txt
		return $border
	}

	<#
	    .SYNOPSIS
	#>

	function New-TroubleshootingOnlyBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		return (GUICommon\New-DialogMetadataPill `
			-Theme $Script:CurrentTheme `
			-Label (Get-UxLocalizedString -Key 'GuiTroubleshootingOnly' -Fallback 'Troubleshooting only') `
			-Tone 'Caution' `
			-ToolTip 'Use this only when diagnosing game compatibility, overlay, or display issues.')
	}

	function New-StatusPill
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Text)
		if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
		$bc = New-SafeBrushConverter -Context 'New-StatusPill'
		$border = [System.Windows.Controls.Border]::new()
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.StatusPillBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.StatusPillBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
		$border.Margin = [System.Windows.Thickness]::new(12, 8, 12, 0)
		$border.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$border.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

		$txt = [System.Windows.Controls.TextBlock]::new()
		$txt.Text = $Text
		$txt.FontSize = GUICommon\Get-GuiCommonSafeFontSize -Key 'FontSizeLabel' -Default 11
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.StatusPillText)
		$border.Child = $txt
		return $border
	}

	<#
	    .SYNOPSIS
	#>

	function Format-TweakScenarioTag
	{
		param ([string]$Tag)

		if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }

		$normalized = [string]$Tag.Trim().ToLowerInvariant()

		# Technical abbreviations and brand names - never translated
		switch ($normalized)
		{
			'uwp'      { return 'UWP' }
			'ui'       { return 'UI' }
			'gpu'      { return 'GPU' }
			'os'       { return 'OS' }
			'smb'      { return 'SMB' }
			'dns'      { return 'DNS' }
			'cpu'      { return 'CPU' }
			'api'      { return 'API' }
			'.net'     { return '.NET' }
			'onedrive' { return 'OneDrive' }
			'xbox'     { return 'Xbox' }
			'adobe'    { return 'Adobe' }
			'nvidia'   { return 'NVIDIA' }
			'hdr'      { return 'HDR' }
			'ipv6'     { return 'IPv6' }
			'uac'      { return 'UAC' }
			'rpc'      { return 'RPC' }
		}

		# Build locale key from tag: "quality-of-life" -> "GuiTagQualityOfLife"
		$words = ($normalized -replace '[-_.]+', ' ').Trim() -split '\s+'
		$camelWords = $words | ForEach-Object { if ($_.Length -gt 0) { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) } }
		$locKey = 'GuiTag' + ($camelWords -join '')
		$englishFallback = $words -join ' ' | ForEach-Object { [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($_) }
		return (Get-UxLocalizedString -Key $locKey -Fallback ([string]$englishFallback))
	}
