# ──────────────────────────────────────────────────────────────────
# StyleManagement.ps1
# Theme / styling helpers extracted from Show-TweakGUI (GUI.psm1).
# Dot-sourced inside Show-TweakGUI so all $Script: and local UI
# variables remain in scope.
# ──────────────────────────────────────────────────────────────────

	function Set-ButtonChrome
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Primitives.ButtonBase]$Button,
			[ValidateSet('Primary', 'Preview', 'Danger', 'DangerSubtle', 'Secondary', 'Subtle', 'Selection')]
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
		switch ($Variant)
		{
			'Selection'
			{
				$normalBg     = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$hoverBg      = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$pressBg      = & $getSafeColor -ColorName 'AccentPress' -DefaultColor '#2563EB'
				$normalBorder = & $getSafeColor -ColorName 'ActiveTabIndicator' -DefaultColor '#4ADE80'
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
				$normalBg     = & $getSafeColor -ColorName 'SecondaryButtonBg' -DefaultColor '#30374A'
				$hoverBg      = & $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#39415A'
				$pressBg      = & $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D3E'
				$normalBorder = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$foreground   = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
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
				$normalBg     = & $getSafeColor -ColorName 'SecondaryButtonBg' -DefaultColor '#30374A'
				$hoverBg      = & $getSafeColor -ColorName 'DestructiveHover' -DefaultColor '#A6294E'
				$pressBg      = & $getSafeColor -ColorName 'DestructiveBg' -DefaultColor '#C0325A'
				$normalBorder = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
				$foreground   = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
			}
			'Subtle'
			{
				$normalBg     = & $getSafeColor -ColorName 'TabBg' -DefaultColor '#2F3445'
				$hoverBg      = & $getSafeColor -ColorName 'TabHoverBg' -DefaultColor '#3670B8'
				$pressBg      = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#3670B8'
				$normalBorder = & $getSafeColor -ColorName 'BorderColor' -DefaultColor '#4C556D'
				$foreground   = if ($Muted) {
					& $getSafeColor -ColorName 'TextSecondary' -DefaultColor '#9CA3AF'
				} else {
					& $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#CDD6F4'
				}
			}
			default
			{
				$normalBg     = & $getSafeColor -ColorName 'SecondaryButtonBg' -DefaultColor '#30374A'
				$hoverBg      = & $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#39415A'
				$pressBg      = & $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D3E'
				$normalBorder = & $getSafeColor -ColorName 'SecondaryButtonBorder' -DefaultColor '#5F6984'
				$foreground   = & $getSafeColor -ColorName 'SecondaryButtonFg' -DefaultColor '#E5EAF7'
			}
		}

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
		$focusBorderBrush = $bc.ConvertFromString((& $getSafeColor -ColorName 'FocusRing' -DefaultColor '#C9DEFF'))
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
		[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')))
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
		[void]($pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($pressTrigger))
		$disabledTrigger = New-Object System.Windows.Trigger
		$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
		$disabledTrigger.Value = $false
		[void]($disabledTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::OpacityProperty) -Value 0.55 -TargetName 'Bd')))
		[void]($tmpl.Triggers.Add($disabledTrigger))
		if ($Button -is [System.Windows.Controls.Primitives.ToggleButton])
		{
			$checkedTrigger = New-Object System.Windows.Trigger
			$checkedTrigger.Property = [System.Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty
			$checkedTrigger.Value = $true
			[void]($checkedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $pressBgBrush -TargetName 'Bd')))
			[void]($checkedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')))
			[void]($tmpl.Triggers.Add($checkedTrigger))
		}
		$Button.Template = $tmpl
	}

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

		$foreground = & $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#CDD6F4'
		$normalBgBrush = [System.Windows.Media.Brushes]::Transparent
		$hoverBg = if ($Variant -eq 'Close') {
			& $getSafeColor -ColorName 'DestructiveHover' -DefaultColor '#A6294E'
		} else {
			& $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#39415A'
		}
		$pressBg = if ($Variant -eq 'Close') {
			& $getSafeColor -ColorName 'DestructiveBg' -DefaultColor '#C0325A'
		} else {
			& $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D3E'
		}
		$hoverForeground = if ($Variant -eq 'Close') { '#FFFFFF' } else { $foreground }

		$foregroundBrush = $bc.ConvertFromString($foreground)
		$hoverForegroundBrush = $bc.ConvertFromString($hoverForeground)
		$hoverBgBrush = $bc.ConvertFromString($hoverBg)
		$pressBgBrush = $bc.ConvertFromString($pressBg)
		$focusBorderBrush = $bc.ConvertFromString((& $getSafeColor -ColorName 'FocusRing' -DefaultColor '#C9DEFF'))

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
			param($Color, $Default = '#89B4FA')
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
		$focusBorder  = & $ensureHexColor $theme.FocusRing      '#C9DEFF'

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
				$darkSurface = & $ensureHexColor $(if ($Script:DarkTheme) { $Script:DarkTheme.CardBg } else { $null }) '#272B3A'
				$darkBorder = & $ensureHexColor $(if ($Script:DarkTheme) { $Script:DarkTheme.BorderColor } else { $null }) '#4C556D'

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
			}
			finally {
				if ($templateReader)
				{
					try { $templateReader.Dispose() } catch { $null = $_ }
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
			# Silent fallback
		}
	}

	function Set-HeaderToggleControlsStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if ($ChkSafeMode) { Set-HeaderToggleStyle -CheckBox $ChkSafeMode -Palette Mode }
		if ($ChkTheme) { Set-HeaderToggleStyle -CheckBox $ChkTheme -Palette Theme }
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
			$workArea = [System.Windows.SystemParameters]::WorkArea
			$clampedMinWidth = [Math]::Min([Math]::Ceiling($neededWidth), $workArea.Width)
			if ($clampedMinWidth -gt $Form.MinWidth)
			{
				$Form.MinWidth = $clampedMinWidth
			}
			if ($Form.Width -gt $workArea.Width)
			{
				$Form.Width = $workArea.Width
			}
		}
		catch { <# non-fatal #> }
	}

	function Update-HeaderModeStateText
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$bc = New-SafeBrushConverter -Context 'Update-HeaderModeStateText'
		$safeEnabled = [bool]$Script:SafeMode
		$advancedEnabled = [bool]$Script:AdvancedMode
		if ($TxtAdvancedModeState)
		{
			if ($advancedEnabled)
			{
				$TxtAdvancedModeState.Text = (Get-UxLocalizedString -Key 'GuiExpertModeOn' -Fallback 'Expert Mode: On')
			}
			else
			{
				$TxtAdvancedModeState.Text = ''
			}
			$TxtAdvancedModeState.Foreground = $bc.ConvertFromString($(if ($advancedEnabled) { $Script:CurrentTheme.ToggleOn } else { $Script:CurrentTheme.TextMuted }))
		}
		if ($ChkSafeMode)
		{
			$ChkSafeMode.Content = (Get-UxLocalizedString -Key 'GuiChkSafeMode' -Fallback 'Safe Mode')
		}
		if ($TxtThemeState)
		{
			$lightEnabled = if ($ChkTheme) { ($ChkTheme.IsChecked -eq $true) } else { ($Script:CurrentThemeName -eq 'Light') }
			$themeLabel = if ($lightEnabled) { (Get-UxLocalizedString -Key 'GuiThemeLight' -Fallback 'Theme: Light') } else { (Get-UxLocalizedString -Key 'GuiThemeDark' -Fallback 'Theme: Dark') }
			$TxtThemeState.Text = $themeLabel
			$TxtThemeState.Foreground = $bc.ConvertFromString($(if ($lightEnabled) { $Script:CurrentTheme.AccentBlue } else { $Script:CurrentTheme.TextMuted }))
		}
	}

	function Update-GuiLocalizationStrings
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		# Buttons
		if ($BtnStartHere)
		{
			Set-GuiButtonIconContent -Button $BtnStartHere -IconName 'QuickStart' -Text (Get-UxLocalizedString -Key 'GuiBtnStartHere' -Fallback 'Start Guide') -ToolTip 'Open the getting started guide.'
		}
		if ($BtnHelp)
		{
			Set-GuiButtonIconContent -Button $BtnHelp -IconName 'Help' -Text (Get-UxLocalizedString -Key 'GuiBtnHelp' -Fallback 'Help') -ToolTip 'Open help and usage guidance.'
		}
		if ($BtnLog)
		{
			Set-GuiButtonIconContent -Button $BtnLog -IconName 'OpenLog' -Text (Get-UxLocalizedString -Key 'GuiBtnLog' -Fallback 'Open Log') -ToolTip 'Open the detailed execution log.'
		}
		if ($BtnClearSearch)
		{
			Set-GuiButtonIconContent -Button $BtnClearSearch -IconName 'Clear' -Text (Get-UxLocalizedString -Key 'GuiBtnClearSearch' -Fallback 'Clear') -ToolTip 'Clear search text and active filters.' -IconSize 14 -Gap 6 -TextFontSize 11
		}
		if ($BtnLanguage)
		{
			Set-GuiButtonIconContent -Button $BtnLanguage -IconName 'Language' -Text (Get-UxLocalizedString -Key 'GuiBtnLanguage' -Fallback 'Language') -ToolTip (Get-UxLocalizedString -Key 'GuiBtnLanguageTooltip' -Fallback 'Change language') -IconSize 14 -Gap 6 -TextFontSize 11
		}

		# Search area
		if ($SearchLabel)          { $SearchLabel.Text = (Get-UxLocalizedString -Key 'GuiSearchLabel' -Fallback 'Quick Filter') }
		if ($TxtSearchPlaceholder) { $TxtSearchPlaceholder.Text = (Get-UxLocalizedString -Key 'GuiSearchPlaceholder' -Fallback 'Filter by name, tag, or category...') }
		if ($TxtLanguageSearch)
		{
			$TxtLanguageSearch.ToolTip = (Get-UxLocalizedString -Key 'GuiLanguageSearchTooltip' -Fallback 'Search available languages')
		}
		if ($TxtLanguageSearchPlaceholder)
		{
			$TxtLanguageSearchPlaceholder.Text = (Get-UxLocalizedString -Key 'GuiLanguageSearchPlaceholder' -Fallback 'Search languages...')
		}

		# Checkboxes
		if ($ChkTheme) { $ChkTheme.Content = (Get-UxLocalizedString -Key 'GuiChkLightMode' -Fallback 'Light Mode') }
		if ($ChkSelectedOnly)
		{
			$ChkSelectedOnly.Content = (Get-UxLocalizedString -Key 'GuiChkSelectedOnly' -Fallback 'Selected only')
			$ChkSelectedOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkSelectedOnlyTip' -Fallback 'Show only tweaks that are currently selected in the GUI.')
		}
		if ($ChkHighRiskOnly)
		{
			$ChkHighRiskOnly.Content = (Get-UxLocalizedString -Key 'GuiChkHighRiskOnly' -Fallback 'High-risk only')
			$ChkHighRiskOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkHighRiskOnlyTip' -Fallback 'Show only high-risk tweaks.')
		}
		if ($ChkRestorableOnly)
		{
			$ChkRestorableOnly.Content = (Get-UxLocalizedString -Key 'GuiChkRestorableOnly' -Fallback 'Restorable only')
			$ChkRestorableOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkRestorableOnlyTip' -Fallback 'Hide tweaks that require manual recovery.')
		}
		if ($ChkGamingOnly)
		{
			$ChkGamingOnly.Content = (Get-UxLocalizedString -Key 'GuiChkGamingOnly' -Fallback 'Gaming-related')
			$ChkGamingOnly.ToolTip = (Get-UxLocalizedString -Key 'GuiChkGamingOnlyTip' -Fallback 'Show tweaks that relate to gaming performance, compatibility, or gaming quality-of-life.')
		}

		# Filter labels
		if ($RiskFilterLabel)     { $RiskFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiRiskFilterLabel' -Fallback 'Risk') }
		if ($CategoryFilterLabel) { $CategoryFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiCategoryFilterLabel' -Fallback 'Category') }
		if ($ViewFilterLabel)     { $ViewFilterLabel.Text = (Get-UxLocalizedString -Key 'GuiViewLabel' -Fallback 'View') }

		# Filter toggle button (preserve arrow direction)
		if ($BtnFilterToggle)
		{
			$filtersText = (Get-UxLocalizedString -Key 'GuiBtnFilterToggle' -Fallback 'Filters')
			$arrow = if ($FilterOptionsPanel -and $FilterOptionsPanel.Visibility -eq [System.Windows.Visibility]::Visible) { [char]0x25BE } else { [char]0x25B8 }
			$BtnFilterToggle.Content = $(
				$fc = if ($Script:HasLabeledIconContent) { New-GuiLabeledIconContent -IconName 'Filter' -Text "$filtersText $arrow" -IconSize 14 -Gap 6 -TextFontSize 11 -AllowTextOnlyFallback } else { $null }
				if ($fc) { $fc } else { "$filtersText $arrow" }
			)
		}

		# Bottom bar - skip Run/Preview (handled by Sync-UxActionButtonText with execution guards)
		if ($BtnDefaults -and -not (& $Script:TestGuiRunInProgressScript))
		{
			Set-GuiButtonIconContent -Button $BtnDefaults -IconName 'RestoreDefaults' -Text (Get-UxLocalizedString -Key 'GuiBtnDefaults' -Fallback 'Restore to Windows Defaults') -ToolTip 'Restore supported settings to Windows defaults.'
		}

		# Expert mode banner
		if ($ExpertModeBanner -and $ExpertModeBanner.Child -is [System.Windows.Controls.TextBlock])
		{
			$ExpertModeBanner.Child.Text = (Get-UxLocalizedString -Key 'GuiExpertModeBanner' -Fallback 'EXPERT MODE — all presets and advanced tweaks are available')
		}

		# Update mode/theme state indicators
		Update-HeaderModeStateText
	}

	#region Themed Dialog
	function Show-ThemedDialog
	{
		param(
			[string]$Title,
			[string]$Message,
			[string[]]$Buttons = @('OK'),
			[string]$AccentButton = $null,
			[string]$DestructiveButton = $null
		)

		return (GUICommon\Show-ThemedDialog `
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
		if ($TxtSearchPlaceholder)
		{
			$TxtSearchPlaceholder.Foreground = $bc.ConvertFromString($Script:CurrentTheme.SearchPlaceholder)
			$TxtSearchPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($TxtSearch.Text)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
		if ($BtnClearSearch)
		{
			$BtnClearSearch.Visibility = if ([string]::IsNullOrWhiteSpace($TxtSearch.Text)) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			Set-ButtonChrome -Button $BtnClearSearch -Variant 'Subtle' -Compact -Muted
		}
	}

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

	function Set-ChoiceComboStyle
	{
		param ([System.Windows.Controls.ComboBox]$Combo)
		if (-not $Combo) { return }

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'Set-ChoiceComboStyle'

		# Helper to ensure a color is a valid hex string
		$ensureHexColor = {
			param($Color, $Default = '#89B4FA')
			if ([string]::IsNullOrWhiteSpace($Color)) { return $Default }
			if ($Color -match '^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $Color }
			return $Default
		}

		$inputBg       = & $ensureHexColor $theme.InputBg       '#313244'
		$textPrimary   = & $ensureHexColor $theme.TextPrimary   '#CDD6F4'
		$borderBrush   = & $ensureHexColor $theme.SearchBorder  '#585B70'
		$hoverBg       = & $ensureHexColor $theme.CardHoverBg   '#323A4E'
		$activeBg      = & $ensureHexColor $theme.TabActiveBg   '#3670B8'
		$activeBorder  = & $ensureHexColor $theme.ActiveTabBorder '#89B4FA'
		if (-not $Script:ChoiceComboTemplateLoadFailures)
		{
			$Script:ChoiceComboTemplateLoadFailures = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
		}
		$comboTemplateFailedForTheme = $Script:ChoiceComboTemplateLoadFailures.Contains($Script:CurrentThemeName)

		if (
			-not $comboTemplateFailedForTheme -and
			(-not $Script:ChoiceComboTemplate -or $Script:ChoiceComboTemplateTheme -ne $Script:CurrentThemeName)
		)
		{
			$comboTemplateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type ComboBox}">
    <Grid SnapsToDevicePixels="True"
          TextElement.Foreground="{TemplateBinding Foreground}">
        <Border Background="$inputBg"
                BorderBrush="$borderBrush"
                BorderThickness="1"
                CornerRadius="6"
                SnapsToDevicePixels="True" />

        <ContentPresenter x:Name="ContentSite"
                          Margin="{TemplateBinding Padding}"
                          HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                          VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                          Content="{TemplateBinding SelectionBoxItem}"
                          ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                          ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                          ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                          IsHitTestVisible="False"
                          RecognizesAccessKey="True"
                          SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}" />

        <ToggleButton x:Name="ToggleButton"
                      Focusable="False"
                      ClickMode="Press"
                      Background="Transparent"
                      BorderBrush="Transparent"
                      BorderThickness="0"
                      IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"
                      HorizontalAlignment="Stretch"
                      VerticalAlignment="Stretch">
            <ToggleButton.Template>
                <ControlTemplate TargetType="{x:Type ToggleButton}">
                    <Border Background="Transparent"
                            BorderBrush="Transparent"
                            BorderThickness="0"
                            SnapsToDevicePixels="True" />
                </ControlTemplate>
            </ToggleButton.Template>
        </ToggleButton>

        <Path HorizontalAlignment="Right"
              VerticalAlignment="Center"
              Margin="0,0,10,0"
              Data="M 0 0 L 4 4 L 8 0"
              Stroke="{TemplateBinding Foreground}"
              StrokeThickness="1.6"
              StrokeStartLineCap="Round"
              StrokeEndLineCap="Round"
              Stretch="Fill"
              Width="8"
              Height="4"
              IsHitTestVisible="False" />

        <Popup x:Name="Popup"
               Placement="Bottom"
               AllowsTransparency="True"
               Focusable="False"
               IsOpen="{TemplateBinding IsDropDownOpen}"
               PopupAnimation="Slide"
               PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}">
            <Border Width="{Binding PlacementTarget.ActualWidth, RelativeSource={RelativeSource AncestorType={x:Type Popup}}}"
                    Background="$inputBg"
                    BorderBrush="$borderBrush"
                    BorderThickness="1"
                    CornerRadius="6"
                    SnapsToDevicePixels="True">
                <ScrollViewer Margin="4,6,4,6"
                              SnapsToDevicePixels="True">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" />
                </ScrollViewer>
            </Border>
        </Popup>
    </Grid>
</ControlTemplate>
"@
			$comboTemplateReader = $null
			try {
				$comboTemplateReader = New-Object System.Xml.XmlNodeReader ([xml]$comboTemplateXaml)
				$Script:ChoiceComboTemplate = [System.Windows.Markup.XamlReader]::Load($comboTemplateReader)
				$Script:ChoiceComboTemplateTheme = $Script:CurrentThemeName
			}
			catch {
				$Script:ChoiceComboTemplate = $null
				$Script:ChoiceComboTemplateTheme = $null
				[void]$Script:ChoiceComboTemplateLoadFailures.Add($Script:CurrentThemeName)
				Write-GuiRuntimeWarning -Context 'Set-ChoiceComboStyle' -Message ("Failed to load combo box template for theme '{0}': {1}" -f $Script:CurrentThemeName, $_.Exception.Message)
			}
			finally {
				if ($comboTemplateReader)
				{
					try { $comboTemplateReader.Dispose() } catch { $null = $_ }
				}
			}
		}

		# Apply the template and styles (with error swallowing)
		try {
			$Combo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $bc.ConvertFromString($activeBg)
			$Combo.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::MenuBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::MenuTextBrushKey] = $bc.ConvertFromString($textPrimary)

			$itemStyle = New-Object System.Windows.Style([System.Windows.Controls.ComboBoxItem])
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($inputBg)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value ($bc.ConvertFromString($textPrimary)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($borderBrush)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value ([System.Windows.Thickness]::new(0)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value ([System.Windows.Thickness]::new(10, 4, 10, 4)))))
			[void]($itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty) -Value ([System.Windows.HorizontalAlignment]::Stretch))))
			$hoverTrigger = New-Object System.Windows.Trigger
			$hoverTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsMouseOverProperty
			$hoverTrigger.Value = $true
			[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($hoverBg)))))
			[void]($hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($activeBorder)))))
			[void]($itemStyle.Triggers.Add($hoverTrigger))
			$selectedTrigger = New-Object System.Windows.Trigger
			$selectedTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsSelectedProperty
			$selectedTrigger.Value = $true
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($activeBg)))))
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value ($bc.ConvertFromString($textPrimary)))))
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($activeBorder)))))
			[void]($selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value ([System.Windows.Thickness]::new(1.5, 0, 0, 0)))))
			[void]($itemStyle.Triggers.Add($selectedTrigger))
			$Combo.ItemContainerStyle = $itemStyle
			$Combo.Background = $bc.ConvertFromString($inputBg)
			$Combo.Foreground = $bc.ConvertFromString($textPrimary)
			$Combo.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, $bc.ConvertFromString($textPrimary))
			$Combo.BorderBrush = $bc.ConvertFromString($borderBrush)
			$Combo.BorderThickness = [System.Windows.Thickness]::new(1)
			if ($Script:ChoiceComboTemplate -and $Script:ChoiceComboTemplateTheme -eq $Script:CurrentThemeName)
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
		}
		catch {
			# Silently ignore any remaining errors - the combo will still work
			return
		}
	}

	function Set-FilterControlStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$bc = New-SafeBrushConverter -Context 'Set-FilterControlStyle'
		if ($RiskFilterLabel) { $RiskFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CategoryFilterLabel) { $CategoryFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkSelectedOnly) { $ChkSelectedOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkHighRiskOnly) { $ChkHighRiskOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkRestorableOnly) { $ChkRestorableOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkGamingOnly) { $ChkGamingOnly.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkSafeMode) { $ChkSafeMode.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkGameMode) { $ChkGameMode.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($BtnFilterToggle) { $BtnFilterToggle.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CmbRiskFilter) { Set-ChoiceComboStyle -Combo $CmbRiskFilter }
		if ($CmbCategoryFilter) { Set-ChoiceComboStyle -Combo $CmbCategoryFilter }
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

	function Set-SearchControlsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		if ($TxtSearch) { $TxtSearch.IsEnabled = $Enabled }
		if ($BtnClearSearch) { $BtnClearSearch.IsEnabled = $Enabled }
		if ($CmbRiskFilter) { $CmbRiskFilter.IsEnabled = $Enabled }
		if ($CmbCategoryFilter) { $CmbCategoryFilter.IsEnabled = $Enabled }
		if ($ChkSelectedOnly) { $ChkSelectedOnly.IsEnabled = $Enabled }
		if ($ChkHighRiskOnly) { $ChkHighRiskOnly.IsEnabled = $Enabled }
		if ($ChkRestorableOnly) { $ChkRestorableOnly.IsEnabled = $Enabled }
		if ($ChkGamingOnly) { $ChkGamingOnly.IsEnabled = $Enabled }
		if ($ChkSafeMode) { $ChkSafeMode.IsEnabled = $Enabled }
		if ($ChkGameMode) { $ChkGameMode.IsEnabled = $Enabled }
		Set-SearchInputStyle
	}

	function Set-GuiActionButtonsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		if ($BtnDefaults) { $BtnDefaults.IsEnabled = $Enabled }
		if ($BtnExportSettings) { $BtnExportSettings.IsEnabled = $Enabled }
		if ($BtnImportSettings) { $BtnImportSettings.IsEnabled = $Enabled }
		if ($BtnRestoreSnapshot) { $BtnRestoreSnapshot.IsEnabled = ($Enabled -and $null -ne $Script:UiSnapshotUndo) }
	}
