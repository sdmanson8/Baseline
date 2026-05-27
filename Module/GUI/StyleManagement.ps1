# Style helper utilities for Baseline UI themes and visual defaults.

<#
	    .SYNOPSIS
	#>

	function Set-GuiButtonChrome
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Primitives.ButtonBase]$Button,
			[ValidateSet('Primary', 'Preview', 'Danger', 'DangerSubtle', 'Secondary', 'Subtle', 'Selection', 'SegmentNeutral')]
			[string]$Variant = 'Secondary',
			[switch]$Compact,
			[switch]$Muted
		)

		if (-not $Button) { return }

		$bc = New-SafeBrushConverter -Context 'Set-ButtonChrome'
		$theme = $Script:CurrentTheme
		$getSafeColor = {
			param (
				[string]$ColorName,
				[string]$DefaultColor
			)

			if (-not $theme) { return $DefaultColor }

			$color = if ($theme.ContainsKey($ColorName)) { [string]$theme[$ColorName] } else { $null }
			if ([string]::IsNullOrWhiteSpace($color))
			{
				return $DefaultColor
			}

			return $color
		}.GetNewClosure()
		$borderThickness = 1
		$hoverBorder = $null
		switch ($Variant)
		{
			'Selection'
			{
				$normalBg     = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$hoverBg      = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$pressBg      = & $getSafeColor -ColorName 'AccentPress' -DefaultColor '#2563EB'
				$normalBorder = & $getSafeColor -ColorName 'ActiveTabIndicator' -DefaultColor '#7CB7FF'
				$foreground   = '#FFFFFF'
				$borderThickness = 2
			}
			'Primary'
			{
				$normalBg     = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$hoverBg      = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$pressBg      = & $getSafeColor -ColorName 'AccentPress' -DefaultColor '#2563EB'
				$normalBorder = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$foreground   = '#FFFFFF'
			}
			'Preview'
			{
				$normalBg     = '#00FFFFFF'
				$hoverBg      = & $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#1E2433'
				$pressBg      = & $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D40'
				$normalBorder = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$foreground   = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$hoverBorder  = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
			}
			'Danger'
			{
				$normalBg     = & $getSafeColor -ColorName 'DestructiveBg' -DefaultColor '#C0325A'
				$hoverBg      = & $getSafeColor -ColorName 'DestructiveHover' -DefaultColor '#A6294E'
				$pressBg      = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
				$normalBorder = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
				$foreground   = '#FFFFFF'
			}
			'DangerSubtle'
			{
				$normalBg     = '#00FFFFFF'
				$hoverBg      = & $getSafeColor -ColorName 'DestructiveSubtleHoverBg' -DefaultColor '#14FF6B8A'
				$pressBg      = & $getSafeColor -ColorName 'DestructiveSubtlePressBg' -DefaultColor '#24FF6B8A'
				$normalBorder = & $getSafeColor -ColorName 'DestructiveSubtleBorder' -DefaultColor '#59FF6B8A'
				$foreground   = & $getSafeColor -ColorName 'RiskHighBadge' -DefaultColor '#FF6B8A'
				$hoverBorder  = $foreground
			}
			'Subtle'
			{
				if ($Muted)
				{
					$normalBg     = '#00FFFFFF'
					$hoverBg      = & $getSafeColor -ColorName 'TabHoverBg' -DefaultColor '#202638'
					$pressBg      = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#262D40'
					$normalBorder = & $getSafeColor -ColorName 'BorderColor' -DefaultColor '#293044'
					$foreground   = & $getSafeColor -ColorName 'TextMuted' -DefaultColor '#8F99B2'
				}
				else
				{
					$normalBg     = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#262D40'
					$hoverBg      = & $getSafeColor -ColorName 'TabHoverBg' -DefaultColor '#202638'
					$pressBg      = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#262D40'
					$normalBorder = & $getSafeColor -ColorName 'BorderColor' -DefaultColor '#293044'
					$foreground   = & $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#F4F7FF'
				}
			}
			'SegmentNeutral'
			{
				$normalBg     = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#262D40'
				$hoverBg      = & $getSafeColor -ColorName 'TabHoverBg' -DefaultColor '#202638'
				$pressBg      = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#262D40'
				$normalBorder = & $getSafeColor -ColorName 'BorderColor' -DefaultColor '#293044'
				$foreground   = & $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#F4F7FF'
			}
			default
			{
				$normalBg     = & $getSafeColor -ColorName 'SecondaryButtonBg' -DefaultColor '#00FFFFFF'
				$hoverBg      = & $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#1E2433'
				$pressBg      = & $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D40'
				$normalBorder = & $getSafeColor -ColorName 'SecondaryButtonBorder' -DefaultColor '#293044'
				$foreground   = & $getSafeColor -ColorName 'SecondaryButtonFg' -DefaultColor '#B8C1D9'
			}
		}
		if ([string]::IsNullOrWhiteSpace($hoverBorder)) { $hoverBorder = $normalBorder }

		$cornerRadius = if ($Compact) { 5 } else { 6 }
		$paddingValue = if ($Button.Padding -and ($Button.Padding.Left -ne 0 -or $Button.Padding.Top -ne 0 -or $Button.Padding.Right -ne 0 -or $Button.Padding.Bottom -ne 0)) {
			$Button.Padding
		} elseif ($Compact) {
			[System.Windows.Thickness]::new(10, 4, 10, 4)
		} else {
			[System.Windows.Thickness]::new(12, 6, 12, 6)
		}

		$normalBgBrush = $bc.ConvertFromString($normalBg)
		$hoverBgBrush = $bc.ConvertFromString($hoverBg)
		$pressBgBrush = $bc.ConvertFromString($pressBg)
		$normalBorderBrush = $bc.ConvertFromString($normalBorder)
		$hoverBorderBrush = $bc.ConvertFromString($hoverBorder)
		$focusBorderBrush = $bc.ConvertFromString((& $getSafeColor -ColorName 'FocusRing' -DefaultColor '#9ACAFF'))
		$foregroundBrush = $bc.ConvertFromString($foreground)

		$Button.Foreground = $foregroundBrush
		$Button.Background = $normalBgBrush
		$Button.BorderBrush = $normalBorderBrush
		$Button.BorderThickness = New-SafeThickness -Uniform $borderThickness
		$Button.FocusVisualStyle = $null
		$Button.Cursor = [System.Windows.Input.Cursors]::Hand
		$Button.Template = $null

		$buttonType = $Button.GetType()
		$tmpl = New-Object System.Windows.Controls.ControlTemplate($buttonType)
		$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$bd.Name = 'Bd'
		$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new($cornerRadius))
		$bd.SetValue([System.Windows.Controls.Border]::PaddingProperty, $paddingValue)
		$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $normalBgBrush)
		$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $normalBorderBrush)
		$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, (New-SafeThickness -Uniform $borderThickness))
		$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
		$bd.AppendChild($cp)
		$tmpl.VisualTree = $bd

		$hoverTrigger = New-Object System.Windows.Trigger
		$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
		$hoverTrigger.Value = $true
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $hoverBgBrush -TargetName 'Bd')))
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $hoverBorderBrush -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($hoverTrigger))
		$focusTrigger = New-Object System.Windows.Trigger
		$focusTrigger.Property = [System.Windows.UIElement]::IsKeyboardFocusedProperty
		$focusTrigger.Value = $true
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')))
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderThicknessProperty) -Value (New-SafeThickness -Uniform 2) -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($focusTrigger))
		$pressTrigger = New-Object System.Windows.Trigger
		$pressTrigger.Property = [System.Windows.Controls.Primitives.ButtonBase]::IsPressedProperty
		$pressTrigger.Value = $true
		[void]($pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $pressBgBrush -TargetName 'Bd')))
		[void]($pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $hoverBorderBrush -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($pressTrigger))
		$disabledTrigger = New-Object System.Windows.Trigger
		$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
		$disabledTrigger.Value = $false
		[void]($disabledTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::OpacityProperty) -Value 0.55 -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($disabledTrigger))
		if ($Button -is [System.Windows.Controls.Primitives.ToggleButton])
		{
			# Keep checked ToggleButtons in their declared variant chrome instead of
			# overriding them with the generic pressed/focus styling. Without this,
			# neutral segmented selections (e.g. Source=All, View=Cards) lose their
			# pill silhouette and read like plain text.
			$checkedTrigger = New-Object System.Windows.Trigger
			$checkedTrigger.Property = [System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty
			$checkedTrigger.Value = $true
			[void]($checkedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $normalBgBrush -TargetName 'Bd')))
			[void]($checkedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $normalBorderBrush -TargetName 'Bd')))
			[void]($checkedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderThicknessProperty) -Value (New-SafeThickness -Uniform $borderThickness) -TargetName 'Bd')))
			[void]($tmpl.Triggers.Add($checkedTrigger))
		}
		$Button.Template = $tmpl
	}

	<#
	    .SYNOPSIS
	#>

	function Set-WindowCaptionButtonStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Button]$Button,
			[ValidateSet('Standard', 'Close')]
			[string]$Variant = 'Standard'
		)

		if (-not $Button) { return }

		$bc = New-SafeBrushConverter -Context 'Set-WindowCaptionButtonStyle'
		$theme = $Script:CurrentTheme
		$getSafeColor = {
			param (
				[string]$ColorName,
				[string]$DefaultColor
			)

			if (-not $theme) { return $DefaultColor }

			$color = if ($theme.ContainsKey($ColorName)) { [string]$theme[$ColorName] } else { $null }
			if ([string]::IsNullOrWhiteSpace($color))
			{
				return $DefaultColor
			}

			return $color
		}.GetNewClosure()

		$foreground = & $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#F4F7FF'
		$normalBgBrush = [System.Windows.Media.Brushes]::Transparent
		$hoverBg = if ($Variant -eq 'Close') {
			& $getSafeColor -ColorName 'DestructiveHover' -DefaultColor '#A6294E'
		} else {
			& $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#343C55'
		}
		$pressBg = if ($Variant -eq 'Close') {
			& $getSafeColor -ColorName 'DestructiveBg' -DefaultColor '#C0325A'
		} else {
			& $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#202638'
		}
		$hoverForeground = if ($Variant -eq 'Close') { '#FFFFFF' } else { $foreground }

		$foregroundBrush = $bc.ConvertFromString($foreground)
		$hoverForegroundBrush = $bc.ConvertFromString($hoverForeground)
		$hoverBgBrush = $bc.ConvertFromString($hoverBg)
		$pressBgBrush = $bc.ConvertFromString($pressBg)
		$focusBorderBrush = $bc.ConvertFromString((& $getSafeColor -ColorName 'FocusRing' -DefaultColor '#9ACAFF'))

		$Button.Foreground = $foregroundBrush
		$Button.Background = $normalBgBrush
		$Button.BorderBrush = [System.Windows.Media.Brushes]::Transparent
		$Button.BorderThickness = New-SafeThickness -Uniform 0
		$Button.FocusVisualStyle = $null
		$Button.Cursor = [System.Windows.Input.Cursors]::Hand
		$Button.Padding = New-SafeThickness -Uniform 0
		$Button.Template = $null

		$tmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
		$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$bd.Name = 'CaptionBd'
		$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $normalBgBrush)
		$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, [System.Windows.Media.Brushes]::Transparent)
		$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, (New-SafeThickness -Uniform 0))
		$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
		$bd.SetValue([System.Windows.Controls.Border]::SnapsToDevicePixelsProperty, $true)

		$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::ContentSourceProperty, 'Content')
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::RecognizesAccessKeyProperty, $true)
		$bd.AppendChild($cp)
		$tmpl.VisualTree = $bd

		$hoverTrigger = New-Object System.Windows.Trigger
		$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
		$hoverTrigger.Value = $true
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $hoverBgBrush -TargetName 'CaptionBd')))
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $hoverForegroundBrush)))
		[void]($tmpl.Triggers.Add($hoverTrigger))

		$focusTrigger = New-Object System.Windows.Trigger
		$focusTrigger.Property = [System.Windows.UIElement]::IsKeyboardFocusedProperty
		$focusTrigger.Value = $true
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'CaptionBd')))
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderThicknessProperty) -Value (New-SafeThickness -Uniform 1) -TargetName 'CaptionBd')))
		[void]($tmpl.Triggers.Add($focusTrigger))

		$pressTrigger = New-Object System.Windows.Trigger
		$pressTrigger.Property = [System.Windows.Controls.Primitives.ButtonBase]::IsPressedProperty
		$pressTrigger.Value = $true
		[void]($pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $pressBgBrush -TargetName 'CaptionBd')))
		[void]($pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $hoverForegroundBrush)))
		[void]($tmpl.Triggers.Add($pressTrigger))

		$disabledTrigger = New-Object System.Windows.Trigger
		$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
		$disabledTrigger.Value = $false
		[void]($disabledTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::OpacityProperty) -Value 0.45 -TargetName 'CaptionBd')))
		[void]($tmpl.Triggers.Add($disabledTrigger))

		$Button.Template = $tmpl
	}

	<#
	    .SYNOPSIS
	#>

	function Set-HeaderToggleStyle
	{
		param (
			[System.Windows.Controls.CheckBox]$CheckBox,
			[ValidateSet('Default', 'Mode', 'Theme')]
			[string]$Palette = 'Default'
		)

		if (-not $CheckBox) { return }

		$existingMargin = $CheckBox.Margin
		$theme = $Script:CurrentTheme

		# Helper to ensure a color is a valid hex string
		$ensureHexColor = {
			param($Color, $Default = '#7CB7FF')
			if ([string]::IsNullOrWhiteSpace($Color)) { return $Default }
			if ($Color -match '^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $Color }
			return $Default
		}

		$trackOffBg = $null
		$trackOffBorder = $null
		$trackOnBg = $null
		$trackOnBorder = $null
		$thumbOffFill = '#FFFFFF'
		$thumbOnFill = '#FFFFFF'
		$hoverOffBorder = $null
		$hoverOnBorder = $null
		$focusBorder  = & $ensureHexColor $theme.FocusRing      '#9ACAFF'

		switch ($Palette)
		{
			'Mode'
			{
				$trackOffBg = & $ensureHexColor $theme.ToggleOff '#B02040'
				$trackOffBorder = $trackOffBg
				$trackOnBg = '#FFFFFF'
				$trackOnBorder = & $ensureHexColor $theme.ToggleOn '#1A7A2A'
				$thumbOffFill = '#FFFFFF'
				$thumbOnFill = & $ensureHexColor $theme.ToggleOn '#1A7A2A'
				$hoverOffBorder = $trackOffBorder
				$hoverOnBorder = $trackOnBorder
				break
			}
			'Theme'
			{
				$lightSurface = & $ensureHexColor $(if ($Script:LightTheme) { $Script:LightTheme.CardBg } else { $null }) '#FFFFFF'
				$lightBorder = & $ensureHexColor $(if ($Script:LightTheme) { $Script:LightTheme.BorderColor } else { $null }) '#A7B0C0'
				$lightAccent = & $ensureHexColor $(if ($Script:LightTheme) { $Script:LightTheme.AccentBlue } else { $null }) '#1550AA'
				$darkSurface = & $ensureHexColor $(if ($Script:DarkTheme) { $Script:DarkTheme.CardBg } else { $null }) '#202638'
				$darkBorder = & $ensureHexColor $(if ($Script:DarkTheme) { $Script:DarkTheme.BorderColor } else { $null }) '#293044'

				$trackOffBg = $darkSurface
				$trackOffBorder = $darkBorder
				$trackOnBg = $lightSurface
				$trackOnBorder = $lightAccent
				$thumbOffFill = '#FFFFFF'
				$thumbOnFill = $lightAccent
				$hoverOffBorder = $focusBorder
				$hoverOnBorder = $lightAccent
				break
			}
			default
			{
				$trackOffBg = & $ensureHexColor $theme.SearchBorder '#6B7280'
				$trackOffBorder = & $ensureHexColor $theme.BorderColor '#6B7280'
				$trackOnBg = & $ensureHexColor $theme.AccentBlue '#3B82F6'
				$trackOnBorder = & $ensureHexColor $theme.ActiveTabBorder '#3B82F6'
				$thumbOffFill = '#FFFFFF'
				$thumbOnFill = '#FFFFFF'
				$hoverOffBorder = & $ensureHexColor $theme.AccentHover '#60A5FA'
				$hoverOnBorder = $hoverOffBorder
			}
		}

		if (-not $Script:HeaderToggleTemplates)
		{
			$Script:HeaderToggleTemplates = @{}
		}
		if (-not $Script:HeaderToggleTemplateLoadFailures)
		{
			$Script:HeaderToggleTemplateLoadFailures = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
		}

		$templateCacheKey = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f `
			$Script:CurrentThemeName, `
			$Palette, `
			$trackOffBg, `
			$trackOffBorder, `
			$trackOnBg, `
			$trackOnBorder, `
			$thumbOffFill, `
			$thumbOnFill, `
			$focusBorder

		if (
			-not $Script:HeaderToggleTemplates.ContainsKey($templateCacheKey) -and
			-not $Script:HeaderToggleTemplateLoadFailures.Contains($templateCacheKey)
		)
		{
			$templateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type CheckBox}">
    <Grid SnapsToDevicePixels="True">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <ContentPresenter Grid.Column="0"
                          Margin="0,0,10,0"
                          VerticalAlignment="Center"
                          RecognizesAccessKey="True"
                          ContentSource="Content" />

        <Border x:Name="SwitchTrack"
                Grid.Column="1"
                Width="42"
                Height="24"
                CornerRadius="12"
                Background="$trackOffBg"
                BorderBrush="$trackOffBorder"
                BorderThickness="1"
                VerticalAlignment="Center">
            <Grid Margin="2">
                <Ellipse x:Name="SwitchThumb"
                         Width="18"
                         Height="18"
                         Fill="$thumbOffFill"
                         HorizontalAlignment="Left"
                         VerticalAlignment="Center" />
            </Grid>
        </Border>
    </Grid>

    <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="SwitchTrack" Property="Background" Value="$trackOnBg" />
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$trackOnBorder" />
            <Setter TargetName="SwitchThumb" Property="Fill" Value="$thumbOnFill" />
            <Setter TargetName="SwitchThumb" Property="HorizontalAlignment" Value="Right" />
        </Trigger>
        <MultiTrigger>
            <MultiTrigger.Conditions>
                <Condition Property="IsChecked" Value="False" />
                <Condition Property="IsMouseOver" Value="True" />
            </MultiTrigger.Conditions>
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$hoverOffBorder" />
        </MultiTrigger>
        <MultiTrigger>
            <MultiTrigger.Conditions>
                <Condition Property="IsChecked" Value="True" />
                <Condition Property="IsMouseOver" Value="True" />
            </MultiTrigger.Conditions>
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$hoverOnBorder" />
        </MultiTrigger>
        <Trigger Property="IsKeyboardFocused" Value="True">
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$focusBorder" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="SwitchTrack" Property="Opacity" Value="0.55" />
            <Setter Property="Opacity" Value="0.65" />
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
			$templateReader = $null
			try {
				$templateReader = New-Object System.Xml.XmlNodeReader ([xml]$templateXaml)
				$Script:HeaderToggleTemplates[$templateCacheKey] = [System.Windows.Markup.XamlReader]::Load($templateReader)
			}
			catch {
				$Script:HeaderToggleTemplates[$templateCacheKey] = $null
				[void]$Script:HeaderToggleTemplateLoadFailures.Add($templateCacheKey)
				Write-GuiRuntimeWarning -Context 'Set-HeaderToggleStyle' -Message ("Failed to load header toggle template '{0}': {1}" -f $templateCacheKey, $_.Exception.Message)
				Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-HeaderToggleStyle.LoadTemplate'
			}
			finally {
				if ($templateReader)
				{
					try { $templateReader.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-HeaderToggleStyle.TemplateReaderDispose' }
				}
			}
		}

		try {
			$bc = New-SafeBrushConverter -Context 'Set-HeaderToggleStyle'
			$headerToggleTemplate = if ($Script:HeaderToggleTemplates.ContainsKey($templateCacheKey)) { $Script:HeaderToggleTemplates[$templateCacheKey] } else { $null }
			if ($headerToggleTemplate)
			{
				$CheckBox.Template = $headerToggleTemplate
			}
			$CheckBox.Cursor = [System.Windows.Input.Cursors]::Hand
			$CheckBox.FocusVisualStyle = $null
			$CheckBox.Background = [System.Windows.Media.Brushes]::Transparent
			$CheckBox.BorderBrush = [System.Windows.Media.Brushes]::Transparent
			$CheckBox.BorderThickness = [System.Windows.Thickness]::new(0)
			$CheckBox.Padding = [System.Windows.Thickness]::new(0)
			$CheckBox.Margin = $existingMargin
			$CheckBox.MinHeight = 24
			$CheckBox.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center
			$CheckBox.Foreground = $bc.ConvertFromString($(if ($Palette -eq 'Theme') { $theme.TextPrimary } else { $theme.TextSecondary }))
		}
		catch {
			Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-HeaderToggleStyle.ApplyChrome'
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-HeaderToggleControlsStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		try
		{
			if ($ChkTheme) { Set-HeaderToggleStyle -CheckBox $ChkTheme -Palette Theme }
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-HeaderToggleControlsStyle.ApplyChrome'
		}
	}

	function Update-WindowMinWidthFromHeader
	{
		<#
		.SYNOPSIS Re-measures the header row and raises MinWidth so toggle controls are never clipped.
		#>
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		try
		{
			if (-not $HeaderBorder -or $HeaderBorder.ActualWidth -le 0) { return }
			$headerGrid = $HeaderBorder.Child
			if (-not ($headerGrid -is [System.Windows.Controls.Grid]) -or $headerGrid.Children.Count -eq 0) { return }
			$topRow = $headerGrid.Children[0]
			if (-not ($topRow -is [System.Windows.Controls.Grid])) { return }
			$topRow.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
			$neededWidth = $topRow.DesiredSize.Width + 56  # header padding (32) + safety margin (24)
			$workArea = if (Get-Command -Name 'Get-GuiMainWindowWorkArea' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Get-GuiMainWindowWorkArea -Window $Form
			}
			else
			{
				$systemWorkArea = [System.Windows.SystemParameters]::WorkArea
				[pscustomobject]@{
					Left   = [double]$systemWorkArea.Left
					Top    = [double]$systemWorkArea.Top
					Width  = [double]$systemWorkArea.Width
					Height = [double]$systemWorkArea.Height
				}
			}
			$workAreaWidth = [double]$workArea.Width
			$workAreaLeft = [double]$workArea.Left
			$clampedMinWidth = [Math]::Min([Math]::Ceiling($neededWidth), $workAreaWidth)
			if ($clampedMinWidth -gt $Form.MinWidth -or [double]$Form.MinWidth -gt $workAreaWidth)
			{
				$Form.MinWidth = $clampedMinWidth
			}
			if ($Form.Width -gt $workAreaWidth)
			{
				$Form.Width = $workAreaWidth
			}
			$maxLeft = $workAreaLeft + $workAreaWidth - [double]$Form.Width
			if ($Form.Left -lt $workAreaLeft)
			{
				$Form.Left = $workAreaLeft
			}
			elseif ($Form.Left -gt $maxLeft)
			{
				$Form.Left = $maxLeft
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-WindowMinWidthFromHeader' }
	}

	<#
	    .SYNOPSIS
	#>

	function Update-HeaderModeStateText
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$lightEnabled = if ($ChkTheme) { ($ChkTheme.IsChecked -eq $true) } else { ($Script:CurrentThemeName -eq 'Light') }
		$themeMenuLabel = if ($lightEnabled) { (Get-UxLocalizedString -Key 'GuiMenuViewSwitchToDarkMode' -Fallback 'Switch to Dark Mode') } else { (Get-UxLocalizedString -Key 'GuiMenuViewSwitchToLightMode' -Fallback 'Switch to Light Mode') }
		if ($Script:MenuViewTheme)
		{
			try { $Script:MenuViewTheme.IsChecked = $lightEnabled } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-HeaderModeStateText.SyncMenuViewTheme' }
			$Script:MenuViewTheme.Header = $themeMenuLabel
		}

		if ($TitleBarText -and $Form)
		{
			try
			{
				$windowTitle = Get-UxLocalizedString -Key 'GuiMainWindowTitleFormat' -Fallback 'Baseline | Utility for {0}' -FormatArgs @((Get-OSInfo).OSName)
				$Form.Title = $windowTitle
				$TitleBarText.Text = $windowTitle
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-HeaderModeStateText.UpdateMainFormTitle'
			}
		}
		if ($TxtThemeState)
		{
			$bc = New-SafeBrushConverter -Context 'Update-HeaderModeStateText'
			$themeLabel = if ($lightEnabled) { (Get-UxLocalizedString -Key 'GuiThemeLight' -Fallback 'Theme: Light') } else { (Get-UxLocalizedString -Key 'GuiThemeDark' -Fallback 'Theme: Dark') }
			$TxtThemeState.Text = $themeLabel
			$TxtThemeState.Foreground = $bc.ConvertFromString($(if ($lightEnabled) { $Script:CurrentTheme.AccentBlue } else { $Script:CurrentTheme.TextMuted }))
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiMenuBarLocalization
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if ($Script:MenuFile)                    { $Script:MenuFile.Header                    = (Get-UxLocalizedString -Key 'GuiMenuFile' -Fallback '_File') }
		if ($Script:MenuActions)                 { $Script:MenuActions.Header                 = (Get-UxLocalizedString -Key 'GuiMenuActions' -Fallback '_Actions') }
		if ($Script:MenuView)                    { $Script:MenuView.Header                    = (Get-UxLocalizedString -Key 'GuiMenuView' -Fallback '_View') }
		if ($Script:MenuTools)                   { $Script:MenuTools.Header                   = (Get-UxLocalizedString -Key 'GuiMenuTools' -Fallback '_Tools') }
		if ($Script:MenuHelp)                    { $Script:MenuHelp.Header                    = (Get-UxLocalizedString -Key 'GuiMenuHelp' -Fallback '_Help') }
		if ($Script:MenuActionsConnectToComputer){ $Script:MenuActionsConnectToComputer.Header = (Get-UxLocalizedString -Key 'GuiMenuActionsConnectToComputer' -Fallback 'Connect to Computer...') }
		if ($Script:MenuActionsDisconnect)       { $Script:MenuActionsDisconnect.Header       = (Get-UxLocalizedString -Key 'GuiMenuActionsDisconnect' -Fallback 'Disconnect') }
		if ($Script:MenuFileImportSettings)      { $Script:MenuFileImportSettings.Header      = (Get-UxLocalizedString -Key 'GuiMenuFileImportSettings' -Fallback 'Import Settings...') }
		if ($Script:MenuFileExportSettings)      { $Script:MenuFileExportSettings.Header      = (Get-UxLocalizedString -Key 'GuiMenuFileExportSettings' -Fallback 'Export Settings...') }
		if ($Script:MenuFileSettings)            { $Script:MenuFileSettings.Header            = (Get-UxLocalizedString -Key 'GuiMenuFileSettings' -Fallback 'Settings...') }
		if ($Script:MenuFileAuditSettings)       { $Script:MenuFileAuditSettings.Header       = (Get-UxLocalizedString -Key 'GuiMenuFileAuditSettings' -Fallback 'Audit Settings...') }
		if ($Script:MenuFileExportConfigProfile) { $Script:MenuFileExportConfigProfile.Header = (Get-UxLocalizedString -Key 'GuiMenuFileExportConfigProfile' -Fallback 'Export Config Profile...') }
		if ($Script:MenuFileExportSystemState)   { $Script:MenuFileExportSystemState.Header   = (Get-UxLocalizedString -Key 'GuiMenuFileExportSystemState' -Fallback 'Export System State...') }
		if ($Script:MenuActionsPreviewRun)       { $Script:MenuActionsPreviewRun.Header       = (Get-UxLocalizedString -Key 'GuiMenuActionsPreviewRun' -Fallback 'Preview Run') }
		if ($Script:MenuActionsRunTweaks)        { $Script:MenuActionsRunTweaks.Header        = (Get-UxLocalizedString -Key 'GuiMenuActionsRunTweaks' -Fallback 'Run Tweaks') }
		if ($Script:MenuActionsUndoLastRun)      { $Script:MenuActionsUndoLastRun.Header      = (Get-UxLocalizedString -Key 'GuiMenuActionsUndoLastRun' -Fallback 'Undo Last Run') }
		if ($Script:MenuActionsRestoreDefaults)  { $Script:MenuActionsRestoreDefaults.Header  = (Get-UxLocalizedString -Key 'GuiMenuActionsRestoreDefaults' -Fallback 'Restore Defaults') }
		if ($Script:MenuActionsCheckCompliance)  { $Script:MenuActionsCheckCompliance.Header  = (Get-UxLocalizedString -Key 'GuiMenuActionsCheckCompliance' -Fallback 'Check Compliance...') }
		if ($Script:MenuActionsScanSystem)       { $Script:MenuActionsScanSystem.Header       = (Get-UxLocalizedString -Key 'GuiMenuActionsScanSystem' -Fallback 'Scan System') }
		if ($Script:MenuActionsAuditLog)         { $Script:MenuActionsAuditLog.Header         = (Get-UxLocalizedString -Key 'GuiMenuActionsAuditLog' -Fallback 'Audit Log...') }
		if ($Script:MenuViewFilters)             { $Script:MenuViewFilters.Header             = (Get-UxLocalizedString -Key 'GuiMenuViewFilters' -Fallback 'Show Filters Panel') }
		if ($Script:MenuViewLogsPanel)           { $Script:MenuViewLogsPanel.Header           = (Get-UxLocalizedString -Key 'GuiMenuViewOpenLogs' -Fallback 'Open Logs') }
		Update-HeaderModeStateText
		if ($Script:MenuToolsAppsManager)        { $Script:MenuToolsAppsManager.Header        = (Get-UxLocalizedString -Key 'GuiMenuToolsAppsManager' -Fallback 'Apps Manager') }
		if ($Script:MenuToolsUpdateAllApps)      { $Script:MenuToolsUpdateAllApps.Header      = (Get-UxLocalizedString -Key 'GuiMenuToolsUpdateAllApps' -Fallback 'Update All Applications') }
		if ($Script:MenuToolsDeveloperDiagnostics){ $Script:MenuToolsDeveloperDiagnostics.Header = (New-GuiLabeledIconContent -IconName 'Code' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnostics' -Fallback 'Developer Diagnostics') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsDeveloperDiagnosticsGenerateReport){ $Script:MenuToolsDeveloperDiagnosticsGenerateReport.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsGenerateReport' -Fallback 'Generate Test Report') }
		if ($Script:MenuToolsDeveloperDiagnosticsSourceQuality){ $Script:MenuToolsDeveloperDiagnosticsSourceQuality.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsSourceQuality' -Fallback 'Run Source Quality Guards') }
		if ($Script:MenuToolsDeveloperDiagnosticsUnitTests){ $Script:MenuToolsDeveloperDiagnosticsUnitTests.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsUnitTests' -Fallback 'Run Unit Tests') }
		if ($Script:MenuToolsDeveloperDiagnosticsGuiComposition){ $Script:MenuToolsDeveloperDiagnosticsGuiComposition.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsGuiComposition' -Fallback 'Run GUI Composition Tests') }
		if ($Script:MenuToolsDeveloperDiagnosticsOpenLatestReport){ $Script:MenuToolsDeveloperDiagnosticsOpenLatestReport.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsOpenLatestReport' -Fallback 'Open Latest Test Report') }
		if ($Script:MenuToolsDeveloperDiagnosticsCopyCommands){ $Script:MenuToolsDeveloperDiagnosticsCopyCommands.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsCopyCommands' -Fallback 'Copy PowerShell Commands') }
		if ($Script:MenuToolsDeveloperDiagnosticsIntegrationTests){ $Script:MenuToolsDeveloperDiagnosticsIntegrationTests.Header = (Get-UxLocalizedString -Key 'GuiMenuToolsDeveloperDiagnosticsIntegrationTests' -Fallback 'Run Integration Tests...') }
		if ($Script:MenuToolsExportSupportBundle){ $Script:MenuToolsExportSupportBundle.Header = (New-GuiLabeledIconContent -IconName 'Archive' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsExportSupportBundle' -Fallback 'Export Support Bundle...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsApproveRemoteTargets){ $Script:MenuToolsApproveRemoteTargets.Header = (New-GuiLabeledIconContent -IconName 'Shield' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsApproveRemoteTargets' -Fallback 'Approve Target List...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsSaveRemoteApprovalPolicy){ $Script:MenuToolsSaveRemoteApprovalPolicy.Header = (New-GuiLabeledIconContent -IconName 'Document' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsSaveRemoteApprovalPolicy' -Fallback 'Save Remote Approval Policy...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsLoadRemoteApprovalPolicy){ $Script:MenuToolsLoadRemoteApprovalPolicy.Header = (New-GuiLabeledIconContent -IconName 'Document' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsLoadRemoteApprovalPolicy' -Fallback 'Load Remote Approval Policy...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsRemoteConsole) { $Script:MenuToolsRemoteConsole.Header = (New-GuiLabeledIconContent -IconName 'WindowConsole' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsRemoteConsole' -Fallback 'Remote Console...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuToolsRemoteSessionStatus){ $Script:MenuToolsRemoteSessionStatus.Header = (New-GuiLabeledIconContent -IconName 'PhoneDesktop' -Text (Get-UxLocalizedString -Key 'GuiMenuToolsRemoteSessionStatus' -Fallback 'Remote Session Status...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuHelpHelp)                { $Script:MenuHelpHelp.Header                = (Get-UxLocalizedString -Key 'GuiMenuHelpHelp' -Fallback 'Help') }
		if ($Script:MenuHelpStartGuide)          { $Script:MenuHelpStartGuide.Header          = (Get-UxLocalizedString -Key 'GuiMenuHelpStartGuide' -Fallback 'Quick Start') }
		if ($Script:MenuHelpReadme)               { $Script:MenuHelpReadme.Header               = (New-GuiLabeledIconContent -IconName 'Document' -Text (Get-UxLocalizedString -Key 'GuiMenuHelpReadme' -Fallback 'Readme') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuHelpFAQ)                  { $Script:MenuHelpFAQ.Header                  = (New-GuiLabeledIconContent -IconName 'Help' -Text (Get-UxLocalizedString -Key 'GuiMenuHelpFAQ' -Fallback 'FAQ') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuHelpChangelog)           { $Script:MenuHelpChangelog.Header           = (Get-UxLocalizedString -Key 'GuiMenuHelpChangelog' -Fallback 'Changelog') }
		if ($Script:MenuHelpCheckForUpdate)      { $Script:MenuHelpCheckForUpdate.Header      = (Get-UxLocalizedString -Key 'GuiMenuHelpCheckForUpdate' -Fallback 'Check for Updates...') }
		if ($Script:MenuHelpReleaseStatus)       { $Script:MenuHelpReleaseStatus.Header       = (New-GuiLabeledIconContent -IconName 'WindowSettings' -Text (Get-UxLocalizedString -Key 'GuiMenuHelpReleaseStatus' -Fallback 'Release Status...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuHelpTroubleshooting)     { $Script:MenuHelpTroubleshooting.Header     = (New-GuiLabeledIconContent -IconName 'Toolbox' -Text (Get-UxLocalizedString -Key 'GuiMenuHelpTroubleshooting' -Fallback 'Troubleshooting Guide...') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
		if ($Script:MenuHelpAbout)               { $Script:MenuHelpAbout.Header               = (New-GuiLabeledIconContent -IconName 'Help' -Text (Get-UxLocalizedString -Key 'GuiMenuHelpAbout' -Fallback 'About Baseline') -IconSize 12 -Gap 6 -TextFontSize 12 -AllowTextOnlyFallback) }
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiMenuBarTheme
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $Script:MainMenuBar) { return }
		$theme = $Script:CurrentTheme
		if (-not $theme) { return }
		$bc = New-SafeBrushConverter -Context 'Update-GuiMenuBarTheme'
		$resources = $Script:MainMenuBar.Resources
		if (-not $resources) { return }
		$setMenuBrushResource = {
			param(
				[string]$Key,
				[string]$ColorValue
			)

			$resolvedBrush = $bc.ConvertFromString($ColorValue)
			if (-not $resolvedBrush) { return }

			$existingBrush = $resources[$Key]
			if ($existingBrush -is [System.Windows.Media.SolidColorBrush] -and $resolvedBrush -is [System.Windows.Media.SolidColorBrush])
			{
				$targetColor = $resolvedBrush.Color
				if ($existingBrush.Color -ne $targetColor)
				{
					if ($existingBrush.IsFrozen)
					{
						$replacement = [System.Windows.Media.SolidColorBrush]::new($targetColor)
						if ($replacement.CanFreeze) { $replacement.Freeze() }
						$resources[$Key] = $replacement
					}
					else
					{
						$existingBrush.Color = $targetColor
					}
				}
				return
			}

			$resources[$Key] = $resolvedBrush
		}.GetNewClosure()
		try
		{
			& $setMenuBrushResource -Key 'MenuBarBackground'  -ColorValue $theme.HeaderBg
			& $setMenuBrushResource -Key 'MenuBarBorder'      -ColorValue $theme.BorderColor
			& $setMenuBrushResource -Key 'MenuBarForeground'  -ColorValue $theme.TextPrimary
			& $setMenuBrushResource -Key 'MenuBarHoverBg'     -ColorValue $theme.TabHoverBg
			& $setMenuBrushResource -Key 'MenuBarHoverFg'     -ColorValue $theme.TextPrimary
			& $setMenuBrushResource -Key 'MenuSubmenuBg'      -ColorValue $theme.CardBg
			& $setMenuBrushResource -Key 'MenuSubmenuBorder'  -ColorValue $theme.BorderColor
			& $setMenuBrushResource -Key 'MenuSeparatorBrush' -ColorValue $theme.BorderColor
		}
		catch
		{
			try { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Menu bar theme update failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-GuiMenuBarTheme.LogWarning' }
		}
		if ($Script:MenuBarBorder)
		{
			try
			{
				$Script:MenuBarBorder.Background = $bc.ConvertFromString($theme.HeaderBg)
				$Script:MenuBarBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			}
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-GuiMenuBarTheme.UpdateMenuBarBorder' }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiScrollBarTheme
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$border = $Script:WindowBorder
		if (-not $border) { $border = $Script:MainWindowRootBorder }
		if (-not $border) { return }
		$resources = $border.Resources
		if (-not $resources) { return }
		$theme = $Script:CurrentTheme
		if (-not $theme) { return }
		$bc = New-SafeBrushConverter -Context 'Update-GuiScrollBarTheme'

		$setBrush = {
			param(
				[string]$Key,
				[string]$ColorValue
			)
			if ([string]::IsNullOrWhiteSpace([string]$ColorValue)) { return }
			$resolvedBrush = $bc.ConvertFromString($ColorValue)
			if (-not $resolvedBrush) { return }
			$existing = $resources[$Key]
			if ($existing -is [System.Windows.Media.SolidColorBrush] -and $resolvedBrush -is [System.Windows.Media.SolidColorBrush])
			{
				$targetColor = $resolvedBrush.Color
				if ($existing.Color -ne $targetColor)
				{
					if ($existing.IsFrozen)
					{
						$replacement = [System.Windows.Media.SolidColorBrush]::new($targetColor)
						if ($replacement.CanFreeze) { $replacement.Freeze() }
						$resources[$Key] = $replacement
					}
					else
					{
						$existing.Color = $targetColor
					}
				}
				return
			}
			$resources[$Key] = $resolvedBrush
		}.GetNewClosure()

		try
		{
			& $setBrush -Key 'ScrollBarTrackBrush'       -ColorValue $theme.ScrollBg
			& $setBrush -Key 'ScrollBarThumbBrush'       -ColorValue $theme.ScrollThumb
			& $setBrush -Key 'ScrollBarThumbHoverBrush'  -ColorValue $(if ($theme.ScrollThumbHover)  { $theme.ScrollThumbHover }  else { $theme.ScrollThumb })
			& $setBrush -Key 'ScrollBarThumbActiveBrush' -ColorValue $(if ($theme.ScrollThumbActive) { $theme.ScrollThumbActive } else { $theme.ScrollThumb })
			# Tokens consumed by AppsFilterRadioStyle (MainWindow.xaml). Kept in
			# this resource-push path so the radio dials track the active theme.
			& $setBrush -Key 'RadioForeground'   -ColorValue $theme.TextPrimary
			& $setBrush -Key 'RadioRingNormal'   -ColorValue $theme.BorderColor
			& $setBrush -Key 'RadioRingHover'    -ColorValue $(if ($theme.AccentHover) { $theme.AccentHover } else { $theme.AccentBlue })
			& $setBrush -Key 'RadioRingChecked'  -ColorValue $theme.AccentBlue
			& $setBrush -Key 'RadioDotFill'      -ColorValue $theme.AccentBlue
		}
		catch
		{
			try { LogWarning (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Scrollbar theme update failed') } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-GuiScrollBarTheme.LogWarning' }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiDuplicateActionVisibility
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$collapsed = [System.Windows.Visibility]::Collapsed
		foreach ($control in @(
			$Script:BtnExportSettings,
			$Script:BtnImportSettings,
			$Script:BtnExportConfigProfile,
			$Script:BtnExportSystemState,
			$Script:BtnCheckCompliance,
			$Script:BtnAuditLog
		))
		{
			if ($control) { $control.Visibility = $collapsed }
		}

		if ($BtnLog) { $BtnLog.Visibility = $collapsed }
	}

	<#
	    .SYNOPSIS
	#>

	function Update-GuiLocalizationStrings
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		# Buttons
		if ($Script:BtnStartHere)
		{
			Set-GuiButtonIconContent -Button $Script:BtnStartHere -IconName 'QuickStart' -Text (Get-UxStartGuideButtonLabel) -ToolTip (Get-UxLocalizedString -Key 'GuiActionStartGuideTooltip' -Fallback 'Open the getting started guide.')
		}
		if ($Script:BtnHelp)
		{
			Set-GuiButtonIconContent -Button $Script:BtnHelp -IconName 'Help' -Text (Get-UxLocalizedString -Key 'GuiBtnHelp' -Fallback 'Help') -ToolTip (Get-UxLocalizedString -Key 'GuiActionOpenHelpTooltip' -Fallback 'Open help and usage guidance.')
		}
		if ($BtnLog)
		{
			Set-GuiButtonIconContent -Button $BtnLog -IconName 'OpenLog' -Text (Get-UxLocalizedString -Key 'GuiBtnLog' -Fallback 'Open Log') -ToolTip (Get-UxLocalizedString -Key 'GuiActionLogTooltip' -Fallback 'Open the detailed execution log.')
		}
		if ($Script:BtnClearSearch)
		{
			Set-GuiButtonIconContent -Button $Script:BtnClearSearch -IconName 'Clear' -Text '' -ToolTip (Get-UxLocalizedString -Key 'GuiActionClearSearchTooltip' -Fallback 'Clear search text and active filters.') -IconSize 14 -Gap 0 -TextFontSize 11
		}
		if ($BtnLanguage)
		{
			Set-GuiButtonIconContent -Button $BtnLanguage -IconName 'Language' -Text (Get-UxLocalizedString -Key 'GuiBtnLanguage' -Fallback 'Language') -ToolTip (Get-UxLocalizedString -Key 'GuiBtnLanguageTooltip' -Fallback 'Change language') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($TitleBarText -and $Form)
		{
			$windowTitle = Get-UxLocalizedString -Key 'GuiMainWindowTitleFormat' -Fallback 'Baseline | Utility for {0}' -FormatArgs @((Get-OSInfo).OSName)
			$Form.Title = $windowTitle
			$TitleBarText.Text = $windowTitle
		}
		if ($ScanLabel)
		{
			$ScanLabel.Text = (Get-UxLocalizedString -Key 'GuiSystemScanButton' -Fallback 'System Scan')
		}
		if ($Script:NavModeTweaks)
		{
			$tweaksTip = (Get-UxLocalizedString -Key 'Nav_OptimizeTooltip' -Fallback "Configure Windows system behavior.`nStage changes, preview the plan, then apply in a controlled run.")
			Set-GuiButtonIconContent -Button $Script:NavModeTweaks -IconName 'SystemTab' -Text (Get-UxLocalizedString -Key 'Nav_Optimize' -Fallback 'System Tweaks') -ToolTip $tweaksTip -IconSize 14 -Gap 6 -TextFontSize 11
			[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($Script:NavModeTweaks, 350)
			[System.Windows.Controls.ToolTipService]::SetShowDuration($Script:NavModeTweaks, 15000)
		}
		if ($Script:NavModeGaming)
		{
			$gamingTip = (Get-UxLocalizedString -Key 'GuiGameModeIntro' -Fallback 'Choose a gaming profile, review the gaming plan, then run it.')
			Set-GuiButtonIconContent -Button $Script:NavModeGaming -IconName 'Games' -Text (Get-UxLocalizedString -Key 'GuiTabGaming' -Fallback 'Gaming') -ToolTip $gamingTip -IconSize 14 -Gap 6 -TextFontSize 11
			[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($Script:NavModeGaming, 350)
			[System.Windows.Controls.ToolTipService]::SetShowDuration($Script:NavModeGaming, 15000)
		}
		if ($Script:NavModeApps)
		{
			$appsTip = (Get-UxLocalizedString -Key 'Nav_SoftwareAndAppsTooltip' -Fallback "Install, update, or uninstall applications via WinGet or Chocolatey.`nQueue actions across many apps, then Apply Changes as a batch.")
			Set-GuiButtonIconContent -Button $Script:NavModeApps -IconName 'AppsTab' -Text (Get-UxLocalizedString -Key 'Nav_SoftwareAndApps' -Fallback 'Software & Apps') -ToolTip $appsTip -IconSize 14 -Gap 6 -TextFontSize 11
			[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($Script:NavModeApps, 350)
			[System.Windows.Controls.ToolTipService]::SetShowDuration($Script:NavModeApps, 15000)
		}
		if ($Script:NavModeUpdates)
		{
			$updatesTip = (Get-UxLocalizedString -Key 'Nav_WindowsUpdatesTooltip' -Fallback "Scan, download, and install Windows updates from a dedicated workflow.")
			Set-GuiButtonIconContent -Button $Script:NavModeUpdates -IconName 'ArrowSync' -Text (Get-UxLocalizedString -Key 'Nav_WindowsUpdates' -Fallback 'Windows Updates') -ToolTip $updatesTip -IconSize 14 -Gap 6 -TextFontSize 11
			[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($Script:NavModeUpdates, 350)
			[System.Windows.Controls.ToolTipService]::SetShowDuration($Script:NavModeUpdates, 15000)
		}
		if ($Script:NavModeDeploymentMedia)
		{
			$deploymentMediaTip = (Get-UxLocalizedString -Key 'Nav_DeploymentMediaTooltip' -Fallback "Deployment Media Builder / Windows Setup Builder.`nDetect editions, preview the plan, then create the selected output.")
			Set-GuiButtonIconContent -Button $Script:NavModeDeploymentMedia -IconName 'WindowSettings' -Text (Get-UxLocalizedString -Key 'Nav_DeploymentMedia' -Fallback 'Windows Setup Builder') -ToolTip $deploymentMediaTip -IconSize 14 -Gap 6 -TextFontSize 11
			[System.Windows.Controls.ToolTipService]::SetInitialShowDelay($Script:NavModeDeploymentMedia, 350)
			[System.Windows.Controls.ToolTipService]::SetShowDuration($Script:NavModeDeploymentMedia, 15000)
		}
		if ($Script:ModeSubtitle)
		{
			$modeSubtitleKey = if ($Script:GamingModeActive) { 'GuiGameModeHeader' } elseif ($Script:UpdatesModeActive) { 'Nav_WindowsUpdatesSubtitle' } elseif ($Script:DeploymentMediaModeActive) { 'Nav_DeploymentMediaSubtitle' } elseif ($Script:AppsModeActive) { 'Nav_SoftwareAndAppsSubtitle' } else { 'Nav_OptimizeSubtitle' }
			$modeSubtitleFallback = if ($Script:GamingModeActive) { 'Game Mode' } elseif ($Script:UpdatesModeActive) { 'Manage Windows Update' } elseif ($Script:DeploymentMediaModeActive) { 'Build Windows setup media' } elseif ($Script:AppsModeActive) { 'Manage installed applications' } else { 'Configure system behavior' }
			$Script:ModeSubtitle.Text = (Get-UxLocalizedString -Key $modeSubtitleKey -Fallback $modeSubtitleFallback)
			$Script:ModeSubtitle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		}
		if (Get-Command -Name 'Sync-GuiDeploymentMediaBuilderViewText' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Sync-GuiDeploymentMediaBuilderViewText
		}
		if ($Script:BtnUpdateAllApps)
		{
			Set-GuiButtonIconContent -Button $Script:BtnUpdateAllApps -IconName 'ArrowSync' -Text (Get-UxLocalizedString -Key 'GuiUpdateAllApps' -Fallback 'Update All Installed') -ToolTip (Get-UxLocalizedString -Key 'Tooltip_UpdateAllApplications' -Fallback 'Update all installed applications. You will be asked to confirm.') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($Script:BtnInstallSelectedApps)
		{
			Set-GuiButtonIconContent -Button $Script:BtnInstallSelectedApps -IconName 'ArrowDownload' -Text (Get-UxLocalizedString -Key 'GuiAppsQueueInstall' -Fallback 'Queue Install') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsQueueInstallTip' -Fallback 'Stage installs for every checked app. They run when you click Apply Changes.') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($Script:BtnUninstallSelectedApps)
		{
			Set-GuiButtonIconContent -Button $Script:BtnUninstallSelectedApps -IconName 'Delete' -Text (Get-UxLocalizedString -Key 'GuiAppsQueueUninstall' -Fallback 'Queue Uninstall') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsQueueUninstallTip' -Fallback 'Stage uninstalls for every checked app. They run when you click Apply Changes.') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($Script:BtnUpdateSelectedApps)
		{
			Set-GuiButtonIconContent -Button $Script:BtnUpdateSelectedApps -IconName 'ArrowSync' -Text (Get-UxLocalizedString -Key 'GuiAppsQueueUpdate' -Fallback 'Queue Update') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsQueueUpdateTip' -Fallback 'Stage updates for every checked app. They run when you click Apply Changes.') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($Script:BtnScanInstalledApps)
		{
			Set-GuiButtonIconContent -Button $Script:BtnScanInstalledApps -IconName 'Search' -Text (Get-UxLocalizedString -Key 'GuiAppsScanInstalledApps' -Fallback 'Scan Installed Apps') -ToolTip (Get-UxLocalizedString -Key 'GuiAppsScanInstalledAppsTip' -Fallback 'Scan installed apps to update install status.') -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($Script:AppsSourceLabel)
		{
			$Script:AppsSourceLabel.Text = (Get-UxLocalizedString -Key 'GuiAppsSourceLabel' -Fallback 'Source') + ':'
		}
		if (Get-Command -Name 'Update-AppSourceFilterControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppSourceFilterControls
		}
		if ($Script:AppsViewModeLabel)
		{
			$Script:AppsViewModeLabel.Text = (Get-UxLocalizedString -Key 'GuiAppsViewModeLabel' -Fallback 'View') + ':'
		}
		if ($Script:BtnAppsViewCards)
		{
			$Script:BtnAppsViewCards.ToolTip = (Get-UxLocalizedString -Key 'GuiAppsViewModeCardsTip' -Fallback 'Show apps as a grid of cards.')
		}
		if ($Script:BtnAppsViewList)
		{
			$Script:BtnAppsViewList.ToolTip = (Get-UxLocalizedString -Key 'GuiAppsViewModeListTip' -Fallback 'Show apps in a vertical list.')
		}
		if (Get-Command -Name 'Update-AppsViewModeControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppsViewModeControls
		}

		# Search area
		if ($Script:SearchLabel)          { $Script:SearchLabel.Text = (Get-UxLocalizedString -Key 'GuiSearchLabel' -Fallback 'Search') }
		if ($Script:TxtSearchPlaceholder) { $Script:TxtSearchPlaceholder.Text = (Get-UxLocalizedString -Key 'GuiSearchPlaceholder' -Fallback 'Search by name, tag, category, or package ID...') }
		if ($TxtLanguageSearch)
		{
			$TxtLanguageSearch.ToolTip = (Get-UxLocalizedString -Key 'GuiLanguageSearchTooltip' -Fallback 'Search available languages')
		}
		if ($TxtLanguageSearchPlaceholder)
		{
			$TxtLanguageSearchPlaceholder.Text = (Get-UxLocalizedString -Key 'GuiLanguageSearchPlaceholder' -Fallback 'Search languages...')
		}
		if ($Script:AppsStatusLabel)
		{
			$Script:AppsStatusLabel.Text = (Get-UxLocalizedString -Key 'GuiAppsStatusFilterLabel' -Fallback 'Installed') + ':'
		}
		if ($Script:CmbAppsStatusFilter)
		{
			$Script:CmbAppsStatusFilter.ToolTip = (Get-UxLocalizedString -Key 'GuiAppsStatusFilterTooltip' -Fallback 'Filter applications by installed or update-available status.')
		}

		# Checkboxes
		if ($ChkTheme) { $ChkTheme.Content = (Get-UxLocalizedString -Key 'GuiChkLightMode' -Fallback 'Light Mode') }
		if ($Script:ChkSelectedOnly)
		{
			$Script:ChkSelectedOnly.Content = (Get-UxLocalizedString -Key 'GuiChkSelectedOnly' -Fallback 'Selected only')
			$Script:ChkSelectedOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkSelectedOnlyTip' -Fallback 'Show only tweaks that are currently selected in the GUI.')
		}
		if ($Script:ChkHighRiskOnly)
		{
			$Script:ChkHighRiskOnly.Content = (Get-UxLocalizedString -Key 'GuiChkHighRiskOnly' -Fallback 'High-risk only')
			$Script:ChkHighRiskOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkHighRiskOnlyTip' -Fallback 'Show only high-risk tweaks.')
		}
		if ($Script:ChkRestorableOnly)
		{
			$Script:ChkRestorableOnly.Content = (Get-UxLocalizedString -Key 'GuiChkRestorableOnly' -Fallback 'Restorable only')
			$Script:ChkRestorableOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkRestorableOnlyTip' -Fallback 'Hide tweaks that require manual recovery.')
		}
		if ($Script:ChkGamingOnly)
		{
			$Script:ChkGamingOnly.Content = (Get-UxLocalizedString -Key 'GuiChkGamingOnly' -Fallback 'Gaming-related')
			$Script:ChkGamingOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkGamingOnlyTip' -Fallback 'Show tweaks that relate to gaming performance, compatibility, or gaming quality-of-life.')
		}

		if (Get-Command -Name 'Update-AppsSelectionSummary' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppsSelectionSummary
		}
		if (Get-Command -Name 'Update-AppPackageSourcePreferenceControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppPackageSourcePreferenceControls
		}
		if (Get-Command -Name 'Update-AppSourceFilterControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppSourceFilterControls
		}

		# Filter labels
		if ($Script:RiskFilterLabel)     { $Script:RiskFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiRiskFilterLabel' -Fallback 'Risk') }
		if ($Script:CategoryFilterLabel) { $Script:CategoryFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiCategoryFilterLabel' -Fallback 'Category') }
		if ($Script:ViewFilterLabel)     { $Script:ViewFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiViewLabel' -Fallback 'View') }

		# Filter toggle button (preserve arrow direction)
		if ($Script:BtnFilterToggle)
		{
			$filtersText = (Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters')
			$arrow = if ($Script:FilterOptionsPanel -and $Script:FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Visible) { [char]0x25BE } else { [char]0x25B8 }
			$Script:BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$filtersText $arrow" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$filtersText $arrow" }
			)
		}

		# Apps filter toggle button
		if ($Script:BtnAppsFilterToggle)
		{
			$appsFiltersText = (Get-UxLocalizedString -Key 'GuiBtnAppsFilterToggle' -Fallback 'Filter')
			$appsArrow = if ($Script:AppsFilterOptionsPanel -and $Script:AppsFilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Visible) { [char]0x25BE } else { [char]0x25B8 }
			$Script:BtnAppsFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$appsFiltersText $appsArrow" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$appsFiltersText $appsArrow" }
			)
		}

		# Bottom bar - skip Run/Preview (handled by Sync-UxActionButtonText with execution guards)
		if ($Script:BtnDefaults -and -not (& $Script:TestGuiRunInProgressScript))
		{
			Set-GuiButtonIconContent -Button $Script:BtnDefaults -IconName 'RestoreDefaults' -Text (Get-UxLocalizedString -Key 'GuiBtnRestoreAllTweaksRecorded' -Fallback 'Restore all tweaks to default values') -ToolTip (Get-UxLocalizedString -Key 'GuiActionRestoreDefaultsTooltipRecorded' -Fallback 'Restore supported settings to recorded default values.')
		}
		if ($Script:BtnExportSettings)
		{
			$Script:BtnExportSettings.Content = (Get-UxLocalizedString -Key 'GuiFooterExportSettings' -Fallback 'Export Settings')
			$Script:BtnExportSettings.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportSettingsTooltip' -Fallback 'Export the current GUI selections to a JSON profile.')
		}
		if ($Script:BtnImportSettings)
		{
			$Script:BtnImportSettings.Content = (Get-UxLocalizedString -Key 'GuiFooterImportSettings' -Fallback 'Import Settings')
			$Script:BtnImportSettings.ToolTip = (Get-UxLocalizedString -Key 'GuiActionImportSettingsTooltip' -Fallback 'Import a saved JSON profile and restore the selected GUI state.')
		}
		if ($Script:BtnRestoreSnapshot)
		{
			$Script:BtnRestoreSnapshot.Content = (Get-UxUndoSelectionActionLabel)
			$Script:BtnRestoreSnapshot.ToolTip = (Get-UxLocalizedString -Key 'GuiActionUndoSelectionTooltip' -Fallback 'Restore the last captured UI snapshot before an import or preset change.')
		}
		if ($Script:BtnExportSystemState)
		{
			$Script:BtnExportSystemState.Content = (Get-UxLocalizedString -Key 'GuiFooterExportSystemState' -Fallback 'Export System State')
			$Script:BtnExportSystemState.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportStateTooltip' -Fallback 'Capture a snapshot of current system settings and save to a JSON file.')
		}
		if ($Script:BtnExportConfigProfile)
		{
			$Script:BtnExportConfigProfile.Content = (Get-UxLocalizedString -Key 'GuiFooterExportConfigProfile' -Fallback 'Export Config Profile')
			$Script:BtnExportConfigProfile.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportProfileTooltip' -Fallback 'Export current tweak selections as a portable configuration profile.')
		}
		if ($Script:BtnExportFirstLogonCommand)
		{
			$Script:BtnExportFirstLogonCommand.Content = (Get-UxLocalizedString -Key 'GuiFooterExportFirstLogonCommand' -Fallback 'Export First-Logon Command')
			$Script:BtnExportFirstLogonCommand.ToolTip = (Get-UxLocalizedString -Key 'GuiActionExportFirstLogonTooltip' -Fallback 'Export an autounattend FirstLogonCommands XML snippet that runs Baseline with a saved configuration profile.')
		}
		if ($Script:BtnUndoLastRun)
		{
			$Script:BtnUndoLastRun.Content = (Get-UxLocalizedString -Key 'GuiFooterUndoLastRun' -Fallback 'Undo Last Run')
			$Script:BtnUndoLastRun.ToolTip = (Get-UxLocalizedString -Key 'GuiActionUndoLastRunTooltip' -Fallback 'Reverse the changes from your most recent run')
		}
		if ($Script:BtnCheckCompliance)
		{
			$Script:BtnCheckCompliance.Content = (Get-UxLocalizedString -Key 'GuiFooterCheckCompliance' -Fallback 'Check Compliance')
			$Script:BtnCheckCompliance.ToolTip = (Get-UxLocalizedString -Key 'GuiActionComplianceTooltip' -Fallback 'Check current system state against a saved profile or snapshot for compliance drift.')
		}
		if ($Script:BtnAuditLog)
		{
			$Script:BtnAuditLog.Content = (Get-UxLocalizedString -Key 'GuiFooterAuditLog' -Fallback 'Audit Log')
			$Script:BtnAuditLog.ToolTip = (Get-UxLocalizedString -Key 'GuiActionAuditTooltip' -Fallback 'View the audit trail of all Baseline execution runs and compliance checks.')
		}
		if ($Script:TxtUpdateDescription) { $Script:TxtUpdateDescription.Text = (Get-UxLocalizedString -Key 'GuiUpdateDialogDescription' -Fallback 'A new version of Baseline is available from GitHub. Do you want to download and extract it now?') }
		if ($Script:TxtDownloadProgressLabel -and [string]::IsNullOrWhiteSpace([string]$Script:TxtDownloadProgressLabel.Text))
		{
			$Script:TxtDownloadProgressLabel.Text = (Get-UxLocalizedString -Key 'GuiUpdateDialogReady' -Fallback 'Ready to download.')
		}
		if ($Script:BtnDownloadNo) { $Script:BtnDownloadNo.Content = (Get-UxLocalizedString -Key 'GuiBtnCancel' -Fallback 'Cancel') }
		if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.Content = (Get-UxLocalizedString -Key 'GuiUpdateDialogDownload' -Fallback 'Download Update') }

		# Expert mode banner
		if ($Script:ExpertModeBanner -and $Script:ExpertModeBanner.Child -is [System.Windows.Controls.TextBlock])
		{
			$Script:ExpertModeBanner.Child.Text = (Get-UxLocalizedString -Key 'GuiExpertModeBanner' -Fallback 'Expert Mode enabled - advanced tweaks visible')
		}

		# Update mode/theme state indicators
		Update-HeaderModeStateText

		# Top menu bar labels
		if (Get-Command -Name 'Update-GuiMenuBarLocalization' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiMenuBarLocalization
		}
	}

	#region Themed Dialog
	<#
	    .SYNOPSIS
	#>

	function Show-ThemedDialog
	{
		param(
			[string]$Title,
			[string]$Message,
			[string[]]$Buttons = @('OK'),
			[string]$AccentButton = $null,
			[string]$DestructiveButton = $null
		)

		return (GUICommon\Show-GuiCommonThemedDialog `
			-Theme $Script:CurrentTheme `
			-ApplyButtonChrome ${function:Set-ButtonChrome} `
			-OwnerWindow $Form `
			-Title $Title `
			-Message $Message `
			-Buttons $Buttons `
			-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
			-AccentButton $AccentButton `
			-DestructiveButton $DestructiveButton)
	}

	<#
	    .SYNOPSIS
	#>

	function Set-SearchInputStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $TxtSearch) { return }
		$bc = New-SafeBrushConverter -Context 'Set-SearchInputStyle'
		$TxtSearch.Background = $bc.ConvertFromString($(if ($TxtSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.InputHoverBg } else { $Script:CurrentTheme.SearchBg }))
		$TxtSearch.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$TxtSearch.BorderBrush = $bc.ConvertFromString($(if ($TxtSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.FocusRing } else { $Script:CurrentTheme.SearchBorder }))
		$TxtSearch.BorderThickness = [System.Windows.Thickness]::new($(if ($TxtSearch.IsKeyboardFocusWithin) { 2 } else { 1 }))
		$TxtSearch.CaretBrush = $bc.ConvertFromString($Script:CurrentTheme.AccentBlue)
		if ($SearchLabel)
		{
			$SearchLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		}
		Sync-GuiSearchInputChrome
	}

	<#
	    .SYNOPSIS
	#>

	function Sync-GuiSearchInputChrome
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$searchBox = if ($Script:TxtSearch) { $Script:TxtSearch } elseif ($TxtSearch) { $TxtSearch } else { $null }
		if (-not $searchBox) { return }

		$isSearchEmpty = [string]::IsNullOrWhiteSpace([string]$searchBox.Text)
		$bc = New-SafeBrushConverter -Context 'Sync-GuiSearchInputChrome'
		$placeholder = if ($Script:TxtSearchPlaceholder) { $Script:TxtSearchPlaceholder } elseif ($TxtSearchPlaceholder) { $TxtSearchPlaceholder } else { $null }
		if ($placeholder)
		{
			$placeholder.Foreground = $bc.ConvertFromString($Script:CurrentTheme.SearchPlaceholder)
			$placeholder.Visibility = if ($isSearchEmpty) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
		$clearButton = if ($Script:BtnClearSearch) { $Script:BtnClearSearch } elseif ($BtnClearSearch) { $BtnClearSearch } else { $null }
		if ($clearButton)
		{
			$clearButton.Visibility = if ($isSearchEmpty) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			Set-ButtonChrome -Button $clearButton -Variant 'Subtle' -Compact -Muted
			Set-GuiButtonIconContent -Button $clearButton -IconName 'Clear' -Text '' -ToolTip (Get-UxLocalizedString -Key 'GuiActionClearSearchTooltip' -Fallback 'Clear search text and active filters.') -IconSize 14 -Gap 0 -TextFontSize 11 -Foreground $clearButton.Foreground
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-LanguageSearchInputStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $TxtLanguageSearch) { return }
		$bc = New-SafeBrushConverter -Context 'Set-LanguageSearchInputStyle'
		$TxtLanguageSearch.Background = $bc.ConvertFromString($(if ($TxtLanguageSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.InputHoverBg } else { $Script:CurrentTheme.SearchBg }))
		$TxtLanguageSearch.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$TxtLanguageSearch.BorderBrush = $bc.ConvertFromString($(if ($TxtLanguageSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.FocusRing } else { $Script:CurrentTheme.SearchBorder }))
		$TxtLanguageSearch.BorderThickness = [System.Windows.Thickness]::new($(if ($TxtLanguageSearch.IsKeyboardFocusWithin) { 2 } else { 1 }))
		$TxtLanguageSearch.CaretBrush = $bc.ConvertFromString($Script:CurrentTheme.AccentBlue)
		if ($TxtLanguageSearchPlaceholder)
		{
			$TxtLanguageSearchPlaceholder.Foreground = $bc.ConvertFromString($Script:CurrentTheme.SearchPlaceholder)
			$TxtLanguageSearchPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($TxtLanguageSearch.Text)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
	}

	<#
	    .SYNOPSIS
	#>

	function New-GuiChoiceComboTemplate
	{
		param (
			[System.Windows.Media.Brush]$PopupBgBrush,
			[System.Windows.Media.Brush]$HoverBgBrush,
			[System.Windows.Media.Brush]$ActiveBorderBrush,
			[System.Windows.Media.Brush]$TextPrimaryBrush,
			[System.Windows.Media.Brush]$TextSecondaryBrush
		)

		$newTemplatedParentBinding = {
			param (
				[string]$Path,
				[switch]$TwoWay
			)

			$binding = if ([string]::IsNullOrWhiteSpace($Path))
			{
				New-Object System.Windows.Data.Binding
			}
			else
			{
				New-Object System.Windows.Data.Binding($Path)
			}
			$binding.RelativeSource = New-Object System.Windows.Data.RelativeSource([System.Windows.Data.RelativeSourceMode]::TemplatedParent)
			if ($TwoWay)
			{
				$binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
			}
			return $binding
		}.GetNewClosure()

		$template = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.ComboBox])

		$rootGrid = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Grid])
		$rootGrid.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)
		$rootGrid.SetBinding([System.Windows.Documents.TextElement]::ForegroundProperty, (& $newTemplatedParentBinding -Path 'Foreground'))

		$comboRoot = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$comboRoot.Name = 'ComboRoot'
		$comboRoot.SetBinding([System.Windows.Controls.Border]::BackgroundProperty, (& $newTemplatedParentBinding -Path 'Background'))
		$comboRoot.SetBinding([System.Windows.Controls.Border]::BorderBrushProperty, (& $newTemplatedParentBinding -Path 'BorderBrush'))
		$comboRoot.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
		$comboRoot.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
		$comboRoot.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)
		$rootGrid.AppendChild($comboRoot)

		$contentSite = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$contentSite.Name = 'ContentSite'
		$contentSite.SetValue([System.Windows.FrameworkElement]::MarginProperty, [System.Windows.Thickness]::new(10, 4, 28, 4))
		$contentSite.SetBinding([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, (& $newTemplatedParentBinding -Path 'HorizontalContentAlignment'))
		$contentSite.SetBinding([System.Windows.FrameworkElement]::VerticalAlignmentProperty, (& $newTemplatedParentBinding -Path 'VerticalContentAlignment'))
		$contentSite.SetBinding([System.Windows.Controls.ContentPresenter]::ContentProperty, (& $newTemplatedParentBinding -Path 'SelectionBoxItem'))
		$contentSite.SetBinding([System.Windows.Controls.ContentPresenter]::ContentTemplateProperty, (& $newTemplatedParentBinding -Path 'SelectionBoxItemTemplate'))
		$contentSite.SetBinding([System.Windows.Controls.ContentPresenter]::ContentTemplateSelectorProperty, (& $newTemplatedParentBinding -Path 'ItemTemplateSelector'))
		$contentSite.SetBinding([System.Windows.Controls.ContentPresenter]::ContentStringFormatProperty, (& $newTemplatedParentBinding -Path 'SelectionBoxItemStringFormat'))
		$contentSite.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, $TextPrimaryBrush)
		$contentSite.SetValue([System.Windows.UIElement]::IsHitTestVisibleProperty, $false)
		$contentSite.SetValue([System.Windows.Controls.ContentPresenter]::RecognizesAccessKeyProperty, $true)
		$contentSite.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)
		$rootGrid.AppendChild($contentSite)

		$toggleTemplate = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Primitives.ToggleButton])
		$toggleBorder = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$toggleBorder.SetValue([System.Windows.Controls.Border]::BackgroundProperty, [System.Windows.Media.Brushes]::Transparent)
		$toggleBorder.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, [System.Windows.Media.Brushes]::Transparent)
		$toggleBorder.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(0))
		$toggleBorder.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)
		$toggleTemplate.VisualTree = $toggleBorder

		$toggleButton = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Primitives.ToggleButton])
		$toggleButton.Name = 'ToggleButton'
		$toggleButton.SetValue([System.Windows.UIElement]::FocusableProperty, $false)
		$toggleButton.SetValue([System.Windows.Controls.Primitives.ButtonBase]::ClickModeProperty, [System.Windows.Controls.ClickMode]::Press)
		$toggleButton.SetValue([System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Media.Brushes]::Transparent)
		$toggleButton.SetValue([System.Windows.Controls.Control]::BorderBrushProperty, [System.Windows.Media.Brushes]::Transparent)
		$toggleButton.SetValue([System.Windows.Controls.Control]::BorderThicknessProperty, [System.Windows.Thickness]::new(0))
		$toggleButton.SetValue([System.Windows.Controls.Control]::TemplateProperty, $toggleTemplate)
		$toggleButton.SetBinding([System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty, (& $newTemplatedParentBinding -Path 'IsDropDownOpen' -TwoWay))
		$toggleButton.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
		$toggleButton.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Stretch)
		$rootGrid.AppendChild($toggleButton)

		$chevron = New-Object System.Windows.FrameworkElementFactory([System.Windows.Shapes.Path])
		$chevron.SetValue([System.Windows.FrameworkElement]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Right)
		$chevron.SetValue([System.Windows.FrameworkElement]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
		$chevron.SetValue([System.Windows.FrameworkElement]::MarginProperty, [System.Windows.Thickness]::new(0, 0, 10, 0))
		$chevron.SetValue([System.Windows.Shapes.Path]::DataProperty, [System.Windows.Media.Geometry]::Parse('M 0 0 L 4 4 L 8 0'))
		$chevron.SetBinding([System.Windows.Shapes.Path]::StrokeProperty, (& $newTemplatedParentBinding -Path 'Foreground'))
		$chevron.SetValue([System.Windows.Shapes.Path]::StrokeThicknessProperty, [double]1.6)
		$chevron.SetValue([System.Windows.Shapes.Shape]::StrokeStartLineCapProperty, [System.Windows.Media.PenLineCap]::Round)
		$chevron.SetValue([System.Windows.Shapes.Shape]::StrokeEndLineCapProperty, [System.Windows.Media.PenLineCap]::Round)
		$chevron.SetValue([System.Windows.Shapes.Path]::StretchProperty, [System.Windows.Media.Stretch]::Fill)
		$chevron.SetValue([System.Windows.FrameworkElement]::WidthProperty, [double]8)
		$chevron.SetValue([System.Windows.FrameworkElement]::HeightProperty, [double]4)
		$chevron.SetValue([System.Windows.UIElement]::IsHitTestVisibleProperty, $false)
		$rootGrid.AppendChild($chevron)

		$popup = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Primitives.Popup])
		$popup.Name = 'Popup'
		$popup.SetValue([System.Windows.Controls.Primitives.Popup]::PlacementProperty, [System.Windows.Controls.Primitives.PlacementMode]::Bottom)
		$popup.SetValue([System.Windows.Controls.Primitives.Popup]::AllowsTransparencyProperty, $true)
		$popup.SetValue([System.Windows.UIElement]::FocusableProperty, $false)
		$popup.SetValue([System.Windows.Controls.Primitives.Popup]::PopupAnimationProperty, [System.Windows.Controls.Primitives.PopupAnimation]::Slide)
		$popup.SetBinding([System.Windows.Controls.Primitives.Popup]::IsOpenProperty, (& $newTemplatedParentBinding -Path 'IsDropDownOpen' -TwoWay))
		$popup.SetBinding([System.Windows.Controls.Primitives.Popup]::PlacementTargetProperty, (& $newTemplatedParentBinding))
		$popup.SetBinding([System.Windows.FrameworkElement]::WidthProperty, (& $newTemplatedParentBinding -Path 'ActualWidth'))

		$popupBorder = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$popupBorder.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $PopupBgBrush)
		$popupBorder.SetBinding([System.Windows.Controls.Border]::BorderBrushProperty, (& $newTemplatedParentBinding -Path 'BorderBrush'))
		$popupBorder.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
		$popupBorder.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
		$popupBorder.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)

		$scrollViewer = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ScrollViewer])
		$scrollViewer.SetValue([System.Windows.FrameworkElement]::MarginProperty, [System.Windows.Thickness]::new(4, 6, 4, 6))
		$scrollViewer.SetValue([System.Windows.UIElement]::SnapsToDevicePixelsProperty, $true)

		$itemsPresenter = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ItemsPresenter])
		$itemsPresenter.SetValue([System.Windows.Input.KeyboardNavigation]::DirectionalNavigationProperty, [System.Windows.Input.KeyboardNavigationMode]::Contained)
		$scrollViewer.AppendChild($itemsPresenter)
		$popupBorder.AppendChild($scrollViewer)
		$popup.AppendChild($popupBorder)
		$rootGrid.AppendChild($popup)

		$template.VisualTree = $rootGrid

		$hoverTrigger = New-Object System.Windows.Trigger
		$hoverTrigger.Property = [System.Windows.Controls.ComboBox]::IsMouseOverProperty
		$hoverTrigger.Value = $true
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $HoverBgBrush -TargetName 'ComboRoot')))
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $ActiveBorderBrush -TargetName 'ComboRoot')))
		[void]($template.Triggers.Add($hoverTrigger))

		$focusTrigger = New-Object System.Windows.Trigger
		$focusTrigger.Property = [System.Windows.Controls.ComboBox]::IsKeyboardFocusWithinProperty
		$focusTrigger.Value = $true
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $HoverBgBrush -TargetName 'ComboRoot')))
		[void]($focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $ActiveBorderBrush -TargetName 'ComboRoot')))
		[void]($template.Triggers.Add($focusTrigger))

		$openTrigger = New-Object System.Windows.Trigger
		$openTrigger.Property = [System.Windows.Controls.ComboBox]::IsDropDownOpenProperty
		$openTrigger.Value = $true
		[void]($openTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $HoverBgBrush -TargetName 'ComboRoot')))
		[void]($openTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $ActiveBorderBrush -TargetName 'ComboRoot')))
		[void]($template.Triggers.Add($openTrigger))

		$disabledTrigger = New-Object System.Windows.Trigger
		$disabledTrigger.Property = [System.Windows.Controls.ComboBox]::IsEnabledProperty
		$disabledTrigger.Value = $false
		[void]($disabledTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $TextSecondaryBrush)))
		[void]($template.Triggers.Add($disabledTrigger))

		return $template
	}

	<#
	    .SYNOPSIS
	#>

	function Set-ChoiceComboStyle
	{
		param ([System.Windows.Controls.ComboBox]$Combo)
		if (-not $Combo) { return }

		$theme = $Script:CurrentTheme

		# Helper to ensure a color is a valid hex string
		$ensureHexColor = {
			param($Color, $Default = '#7CB7FF')
			if ([string]::IsNullOrWhiteSpace($Color)) { return $Default }
			if ($Color -match '^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $Color }
			return $Default
		}

		$inputBg       = & $ensureHexColor $theme.InputBg       '#2A3146'
		$textPrimary   = & $ensureHexColor $theme.TextPrimary   '#F4F7FF'
		$textSecondary = & $ensureHexColor $theme.TextSecondary '#CDD6EA'
		$borderBrush   = & $ensureHexColor $(if ($theme.BorderStrong) { [string]$theme.BorderStrong } elseif ($theme.SearchBorder) { [string]$theme.SearchBorder } else { $theme.BorderColor }) '#585B70'
		$hoverBg       = & $ensureHexColor $theme.InputHoverBg  $(if ($theme.CardHoverBg) { [string]$theme.CardHoverBg } else { '#343C55' })
		$popupBg       = & $ensureHexColor $(if ($theme.CardBg) { [string]$theme.CardBg } else { $inputBg }) $inputBg
		$selectionBg   = & $ensureHexColor $(if ($theme.StatusPillBg) { [string]$theme.StatusPillBg } elseif ($theme.TabActiveBg) { [string]$theme.TabActiveBg } else { $hoverBg }) '#202638'
		$activeBorder  = & $ensureHexColor $theme.ActiveTabBorder '#7CB7FF'
		$inputBgBrush = ConvertTo-GuiBrush -Color $inputBg -Context 'Set-ChoiceComboStyle/InputBg'
		$textPrimaryBrush = ConvertTo-GuiBrush -Color $textPrimary -Context 'Set-ChoiceComboStyle/TextPrimary'
		$textSecondaryBrush = ConvertTo-GuiBrush -Color $textSecondary -Context 'Set-ChoiceComboStyle/TextSecondary'
		$borderBrushValue = ConvertTo-GuiBrush -Color $borderBrush -Context 'Set-ChoiceComboStyle/Border'
		$hoverBgBrush = ConvertTo-GuiBrush -Color $hoverBg -Context 'Set-ChoiceComboStyle/HoverBg'
		$popupBgBrush = ConvertTo-GuiBrush -Color $popupBg -Context 'Set-ChoiceComboStyle/PopupBg'
		$selectionBgBrush = ConvertTo-GuiBrush -Color $selectionBg -Context 'Set-ChoiceComboStyle/SelectionBg'
		$activeBorderBrush = ConvertTo-GuiBrush -Color $activeBorder -Context 'Set-ChoiceComboStyle/ActiveBorder'
		$comboTemplateKey = @(
			[string]$Script:CurrentThemeName,
			$inputBg,
			$textPrimary,
			$textSecondary,
			$borderBrush,
			$hoverBg,
			$popupBg,
			$selectionBg,
			$activeBorder
		) -join '|'

		if (-not $Script:ChoiceComboTemplate -or $Script:ChoiceComboTemplateTheme -ne $comboTemplateKey)
		{
			$Script:ChoiceComboTemplate = New-GuiChoiceComboTemplate `
				-PopupBgBrush $popupBgBrush `
				-HoverBgBrush $hoverBgBrush `
				-ActiveBorderBrush $activeBorderBrush `
				-TextPrimaryBrush $textPrimaryBrush `
				-TextSecondaryBrush $textSecondaryBrush
			$Script:ChoiceComboTemplateTheme = $comboTemplateKey
		}

		# Apply the template and styles (with error swallowing)
		try {
			$Combo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = [System.Windows.Media.Brush]$popupBgBrush
			$Combo.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = [System.Windows.Media.Brush]$textPrimaryBrush
			$Combo.Resources[[System.Windows.SystemColors]::ControlBrushKey] = [System.Windows.Media.Brush]$inputBgBrush
			$Combo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = [System.Windows.Media.Brush]$textPrimaryBrush
			$Combo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = [System.Windows.Media.Brush]$selectionBgBrush
			$Combo.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = [System.Windows.Media.Brush]$textPrimaryBrush
			$Combo.Resources[[System.Windows.SystemColors]::MenuBrushKey] = [System.Windows.Media.Brush]$popupBgBrush
			$Combo.Resources[[System.Windows.SystemColors]::MenuTextBrushKey] = [System.Windows.Media.Brush]$textPrimaryBrush
			$newComboBoxItemTemplateBinding = {
				param ([string]$Path)

				$binding = New-Object System.Windows.Data.Binding($Path)
				$binding.RelativeSource = New-Object System.Windows.Data.RelativeSource([System.Windows.Data.RelativeSourceMode]::TemplatedParent)
				return $binding
			}

			$itemStyle = New-Object System.Windows.Style([System.Windows.Controls.ComboBoxItem])
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $popupBgBrush)))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $textPrimaryBrush)))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ([System.Windows.Media.Brushes]::Transparent))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value ([System.Windows.Thickness]::new(0)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value ([System.Windows.Thickness]::new(10, 4, 10, 4)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty) -Value ([System.Windows.HorizontalAlignment]::Stretch))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.FrameworkElement]::MinHeightProperty) -Value ([double]28))))
			$itemTemplate = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.ComboBoxItem])
			$itemRoot = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
			$itemRoot.Name = 'ItemRoot'
			$itemRoot.SetValue([System.Windows.Controls.Border]::BackgroundProperty, [System.Windows.Media.Brush]$popupBgBrush)
			$itemRoot.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, [System.Windows.Media.Brushes]::Transparent)
			$itemRoot.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(0))
			$itemRoot.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(10, 4, 10, 4))
			$itemRoot.SetValue([System.Windows.Controls.Border]::SnapsToDevicePixelsProperty, $true)
			$itemPresenter = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
			$itemPresenter.Name = 'ItemContentSite'
			$itemPresenter.SetBinding([System.Windows.Controls.ContentPresenter]::ContentProperty, (& $newComboBoxItemTemplateBinding -Path 'Content'))
			$itemPresenter.SetBinding([System.Windows.Controls.ContentPresenter]::ContentTemplateProperty, (& $newComboBoxItemTemplateBinding -Path 'ContentTemplate'))
			$itemPresenter.SetBinding([System.Windows.Controls.ContentPresenter]::ContentTemplateSelectorProperty, (& $newComboBoxItemTemplateBinding -Path 'ContentTemplateSelector'))
			$itemPresenter.SetBinding([System.Windows.Controls.ContentPresenter]::ContentStringFormatProperty, (& $newComboBoxItemTemplateBinding -Path 'ContentStringFormat'))
			$itemPresenter.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Stretch)
			$itemPresenter.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
			$itemPresenter.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, $textPrimaryBrush)
			$itemRoot.AppendChild($itemPresenter)
			$itemTemplate.VisualTree = $itemRoot
			$itemHoverTemplateTrigger = New-Object System.Windows.Trigger
			$itemHoverTemplateTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsMouseOverProperty
			$itemHoverTemplateTrigger.Value = $true
			[void]($itemHoverTemplateTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $hoverBgBrush -TargetName 'ItemRoot')))
			[void]($itemTemplate.Triggers.Add($itemHoverTemplateTrigger))
			$itemSelectedTemplateTrigger = New-Object System.Windows.Trigger
			$itemSelectedTemplateTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsSelectedProperty
			$itemSelectedTemplateTrigger.Value = $true
			[void]($itemSelectedTemplateTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $selectionBgBrush -TargetName 'ItemRoot')))
			[void]($itemSelectedTemplateTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $activeBorderBrush -TargetName 'ItemRoot')))
			[void]($itemSelectedTemplateTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderThicknessProperty) -Value ([System.Windows.Thickness]::new(1)) -TargetName 'ItemRoot')))
			[void]($itemTemplate.Triggers.Add($itemSelectedTemplateTrigger))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::TemplateProperty) -Value $itemTemplate)))
			$hoverTrigger = New-Object System.Windows.Trigger
			$hoverTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsMouseOverProperty
			$hoverTrigger.Value = $true
			[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $hoverBgBrush)))
			[void]($itemStyle.Triggers.Add($hoverTrigger))
			$selectedTrigger = New-Object System.Windows.Trigger
			$selectedTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsSelectedProperty
			$selectedTrigger.Value = $true
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value $selectionBgBrush)))
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value $textPrimaryBrush)))
			[void]($itemStyle.Triggers.Add($selectedTrigger))
			$Combo.ItemContainerStyle = $itemStyle
			$Combo.Background = [System.Windows.Media.Brush]$inputBgBrush
			$Combo.Foreground = [System.Windows.Media.Brush]$textPrimaryBrush
			$Combo.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, [System.Windows.Media.Brush]$textPrimaryBrush)
			$Combo.BorderBrush = [System.Windows.Media.Brush]$borderBrushValue
			$Combo.BorderThickness = [System.Windows.Thickness]::new(1)
			if ($Script:ChoiceComboTemplate -and $Script:ChoiceComboTemplateTheme -eq $comboTemplateKey)
			{
				$Combo.OverridesDefaultStyle = $true
				$Combo.Template = $Script:ChoiceComboTemplate
			}
			else
			{
				$Combo.OverridesDefaultStyle = $false
				$Combo.ClearValue([System.Windows.Controls.Control]::TemplateProperty)
			}
			$Combo.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
			$Combo.MinWidth = 190
			$Combo.Height = 30
			try { [void]$Combo.ApplyTemplate() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-ChoiceComboStyle.ApplyTemplate' }
		}
		catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-ChoiceComboStyle:catch1566' -Severity Debug }

			# Silently ignore any remaining errors - the combo will still work
			return
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Update-ChoiceComboStyles
	{
		if (-not $Script:Controls) { return }

		$entries = if ($Script:Controls -is [System.Collections.IDictionary])
		{
			@($Script:Controls.Values)
		}
		else
		{
			@($Script:Controls)
		}

		foreach ($entry in $entries)
		{
			$combo = $null
			if ($entry -is [System.Windows.Controls.ComboBox])
			{
				$combo = $entry
			}
			elseif ((Test-GuiObjectField -Object $entry -FieldName 'ComboBox') -and ($entry.ComboBox -is [System.Windows.Controls.ComboBox]))
			{
				$combo = $entry.ComboBox
			}

			if (-not $combo) { continue }

			try
			{
				Set-ChoiceComboStyle -Combo $combo
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Update-ChoiceComboStyles.SetChoiceComboStyle'
			}
		}
	}

	<#
	    .SYNOPSIS
	#>

	function Set-FilterControlStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$bc = New-SafeBrushConverter -Context 'Set-FilterControlStyle'
		$sharedFilterLabelFontSize = 12
		$sharedFilterLabelFontWeight = [System.Windows.FontWeights]::SemiBold
		if ($RiskFilterLabel) { $RiskFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CategoryFilterLabel) { $CategoryFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($Script:AppsStatusLabel)
		{
			$Script:AppsStatusLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			$Script:AppsStatusLabel.FontSize = $sharedFilterLabelFontSize
			$Script:AppsStatusLabel.FontWeight = $sharedFilterLabelFontWeight
		}
		if ($Script:AppsSourceLabel)
		{
			$Script:AppsSourceLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			$Script:AppsSourceLabel.FontSize = $sharedFilterLabelFontSize
			$Script:AppsSourceLabel.FontWeight = $sharedFilterLabelFontWeight
		}
		if ($Script:AppsViewModeLabel)
		{
			$Script:AppsViewModeLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			$Script:AppsViewModeLabel.FontSize = $sharedFilterLabelFontSize
			$Script:AppsViewModeLabel.FontWeight = $sharedFilterLabelFontWeight
		}
		if ($Script:AppsFilterViewDivider) { $Script:AppsFilterViewDivider.Background = $bc.ConvertFromString($Script:CurrentTheme.BorderColor) }
		if ($Script:AppsActionSeparator1) { $Script:AppsActionSeparator1.Background = $bc.ConvertFromString($Script:CurrentTheme.BorderColor) }
		if ($ChkSelectedOnly) { $ChkSelectedOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkHighRiskOnly) { $ChkHighRiskOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkRestorableOnly) { $ChkRestorableOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkGamingOnly) { $ChkGamingOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($BtnFilterToggle) { $BtnFilterToggle.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($Script:BtnAppsFilterToggle) { $Script:BtnAppsFilterToggle.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CmbRiskFilter) { Set-ChoiceComboStyle -Combo $CmbRiskFilter }
		if ($CmbCategoryFilter) { Set-ChoiceComboStyle -Combo $CmbCategoryFilter }
		if ($CmbPlatformFilter) { Set-ChoiceComboStyle -Combo $CmbPlatformFilter }
		if ($CmbAppsStatusFilter) { Set-ChoiceComboStyle -Combo $CmbAppsStatusFilter }
		Update-ChoiceComboStyles
		if ($Script:CmbDeploymentMediaDetectedEdition) { Set-ChoiceComboStyle -Combo $Script:CmbDeploymentMediaDetectedEdition }
		if ($Script:CmbDeploymentMediaOutputMode) { Set-ChoiceComboStyle -Combo $Script:CmbDeploymentMediaOutputMode }
		if ($TxtLanguageState) { $TxtLanguageState.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($LanguagePopupBorder)
		{
			$LanguagePopupBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.InputBg)
			$LanguagePopupBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.SearchBorder)
		}
		if ($TxtLanguageSearch) { Set-LanguageSearchInputStyle }
		if ($LanguageListPanel)
		{
			foreach ($child in $LanguageListPanel.Children)
			{
				if ($child -is [System.Windows.Controls.Button])
				{
					$child.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				}
				elseif ($child -is [System.Windows.Controls.TextBlock])
				{
					$child.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				}
			}
		}
		if ($PrimaryTabDropdown) { Set-ChoiceComboStyle -Combo $PrimaryTabDropdown }
	}

	<#
	    .SYNOPSIS
	#>

	function Set-SearchControlsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		if ($Script:TxtSearch) { $Script:TxtSearch.IsEnabled = $Enabled }
		if ($Script:BtnClearSearch) { $Script:BtnClearSearch.IsEnabled = $Enabled }
		if ($CmbRiskFilter) { $CmbRiskFilter.IsEnabled = $Enabled }
		if ($CmbCategoryFilter) { $CmbCategoryFilter.IsEnabled = $Enabled }
		if ($CmbPlatformFilter) { $CmbPlatformFilter.IsEnabled = $Enabled }
		if ($ChkSelectedOnly) { $ChkSelectedOnly.IsEnabled = $Enabled }
		if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsEnabled = $Enabled }
		if ($ChkRestorableOnly) { $ChkRestorableOnly.IsEnabled = $Enabled }
		if ($ChkGamingOnly) { $ChkGamingOnly.IsEnabled = $Enabled }
		Set-SearchInputStyle
	}

	<#
	    .SYNOPSIS
	#>

	function Set-GuiActionButtonsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		$isRemoteConnected = $false
		$remoteTargetContext = $null
		if (Get-Command -Name 'Test-GuiRemoteTargetConnected' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { $isRemoteConnected = [bool](Test-GuiRemoteTargetConnected) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-GuiActionButtonsEnabled:catch1720' -Severity Debug }
			 $isRemoteConnected = $false }
		}
		if (Get-Command -Name 'Get-GuiRemoteTargetContext' -CommandType Function -ErrorAction SilentlyContinue)
		{
			try { $remoteTargetContext = Get-GuiRemoteTargetContext } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-GuiActionButtonsEnabled:catch1724' -Severity Debug }
			 $remoteTargetContext = $null }
		}
		$isRemoteApprovalReady = $false
		if ($isRemoteConnected -and (Get-Command -Name 'Test-GuiRemoteTargetApproval' -CommandType Function -ErrorAction SilentlyContinue) -and $remoteTargetContext)
		{
			try { $isRemoteApprovalReady = [bool](Test-GuiRemoteTargetApproval -ComputerName @($remoteTargetContext.TargetComputers)) } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'StyleManagement.Set-GuiActionButtonsEnabled:catch1729' -Severity Debug }
			 $isRemoteApprovalReady = $false }
		}
		if ($Script:BtnDefaults) { $Script:BtnDefaults.IsEnabled = $Enabled }
		if ($Script:BtnExportSettings) { $Script:BtnExportSettings.IsEnabled = $Enabled }
		if ($Script:BtnImportSettings) { $Script:BtnImportSettings.IsEnabled = $Enabled }
		if ($Script:BtnRestoreSnapshot) { $Script:BtnRestoreSnapshot.IsEnabled = ($Enabled -and $null -ne $Script:UiSnapshotUndo) }
		if ($Script:BtnExportSystemState) { $Script:BtnExportSystemState.IsEnabled = $Enabled }
		if ($Script:BtnExportConfigProfile) { $Script:BtnExportConfigProfile.IsEnabled = $Enabled }
		if ($Script:BtnExportFirstLogonCommand) { $Script:BtnExportFirstLogonCommand.IsEnabled = $Enabled }
		if ($Script:MenuFileSettings) { $Script:MenuFileSettings.IsEnabled = $Enabled }
		if ($Script:MenuFileAuditSettings) { $Script:MenuFileAuditSettings.IsEnabled = $Enabled }
		if ($Script:MenuToolsExportSupportBundle) { $Script:MenuToolsExportSupportBundle.IsEnabled = $Enabled }
		if (Get-Command -Name 'Update-GuiDeveloperDiagnosticsMenuState' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-GuiDeveloperDiagnosticsMenuState
		}
		if ($Script:MenuToolsApproveRemoteTargets) { $Script:MenuToolsApproveRemoteTargets.IsEnabled = ($Enabled -and $isRemoteConnected) }
		if ($Script:MenuToolsSaveRemoteApprovalPolicy) { $Script:MenuToolsSaveRemoteApprovalPolicy.IsEnabled = ($Enabled -and $isRemoteConnected -and $isRemoteApprovalReady) }
		if ($Script:MenuToolsLoadRemoteApprovalPolicy) { $Script:MenuToolsLoadRemoteApprovalPolicy.IsEnabled = ($Enabled -and $isRemoteConnected) }
		if ($Script:MenuToolsRemoteConsole) { $Script:MenuToolsRemoteConsole.IsEnabled = $Enabled }
		if ($Script:MenuToolsRemoteSessionStatus) { $Script:MenuToolsRemoteSessionStatus.IsEnabled = $Enabled }
		if ($Script:MenuHelpReleaseStatus) { $Script:MenuHelpReleaseStatus.IsEnabled = $Enabled }
		if ($Script:MenuHelpTroubleshooting) { $Script:MenuHelpTroubleshooting.IsEnabled = $Enabled }
		if ($Script:BtnUndoLastRun) { $Script:BtnUndoLastRun.IsEnabled = $Enabled }
		if ($Script:BtnCheckCompliance) { $Script:BtnCheckCompliance.IsEnabled = $Enabled }
		if ($Script:BtnAuditLog) { $Script:BtnAuditLog.IsEnabled = $Enabled }
		if ($Script:MenuActionsConnectToComputer) { $Script:MenuActionsConnectToComputer.IsEnabled = $Enabled }
		if ($Script:MenuActionsDisconnect) { $Script:MenuActionsDisconnect.IsEnabled = ($Enabled -and $isRemoteConnected) }
	}
