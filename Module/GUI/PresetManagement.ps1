# Preset button builders, selection state, policy checks, and tab-level preset application

# Keep this explicit order so metadata and path helpers load before selection-state helpers.
$Script:PresetManagementRoot = $PSScriptRoot
$presetManagementSplitRoot = Join-Path $Script:PresetManagementRoot 'PresetManagement'
. (Join-Path $presetManagementSplitRoot 'PresetMetadata.ps1')
. (Join-Path $presetManagementSplitRoot 'PresetPaths.ps1')
. (Join-Path $presetManagementSplitRoot 'PresetSelectionState.ps1')

	<#
	    .SYNOPSIS
	#>

	function New-PresetButton
	{
		param(
			[object]$Label,
			[ValidateSet('Primary', 'Danger', 'DangerSubtle', 'Secondary', 'Subtle')]
			[string]$Variant = 'Secondary',
			[switch]$Compact,
			[switch]$Muted
		)

		$button = New-Object System.Windows.Controls.Button
		$button.Content = $Label
		$button.Padding = if ($Compact) { [System.Windows.Thickness]::new(10, 4, 10, 4) } else { [System.Windows.Thickness]::new(12, 6, 12, 6) }
		$button.Margin = [System.Windows.Thickness]::new(3, 0, 3, 0)
		$button.FontSize = 11
		Set-ButtonChrome -Button $button -Variant $Variant -Compact:$Compact -Muted:$Muted
		return $button
	}

	<#
	    .SYNOPSIS
	#>

	function New-PresetButtonContent
	{
		param(
			[Parameter(Mandatory = $true)]
			[string]$PrimaryText,
			[string]$SecondaryText
		)

		if ([string]::IsNullOrWhiteSpace($SecondaryText))
		{
			return $PrimaryText
		}

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'
		$stack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

		$primary = New-Object System.Windows.Controls.TextBlock
		$primary.Text = $PrimaryText
		$primary.TextAlignment = [System.Windows.TextAlignment]::Center
		$primary.FontWeight = [System.Windows.FontWeights]::SemiBold
		$primary.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		[void]($stack.Children.Add($primary))

		$secondary = New-Object System.Windows.Controls.TextBlock
		$secondary.Text = $SecondaryText
		$secondary.TextAlignment = [System.Windows.TextAlignment]::Center
		$secondary.FontSize = 9
		$secondary.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
		$secondary.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		[void]($stack.Children.Add($secondary))

		return $stack
	}

	<#
	    .SYNOPSIS
	#>

	function New-WhyThisMattersButton
	{
		<#
		.SYNOPSIS
		Returns a secondary outline button that toggles a hint border, or $null if no hint text.
		The caller must add the returned .Tag (Border) to the parent layout.
		#>
			param (
				[object]$Tweak,
				[int]$LeftIndent = 28
			)

		$whyThisMatters = Get-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters'
		$hintText = if ($Tweak -and -not [string]::IsNullOrWhiteSpace([string]$whyThisMatters)) {
			[string]$whyThisMatters
		} else { $null }
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersButton'
		if (-not $Script:WhyThisMattersButtonTemplate)
		{
			$linkTemplateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type Button}">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="5"
            Padding="{TemplateBinding Padding}"
            SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center"
                          VerticalAlignment="Center"
                          RecognizesAccessKey="True" />
    </Border>
</ControlTemplate>
'@
			$linkTemplateReader = New-Object System.Xml.XmlNodeReader ([xml]$linkTemplateXaml)
			$Script:WhyThisMattersButtonTemplate = [System.Windows.Markup.XamlReader]::Load($linkTemplateReader)
		}

		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$btn.FontSize = 10
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$btn.Background = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderThickness = [System.Windows.Thickness]::new(0)
		$btn.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$btn.Cursor = [System.Windows.Input.Cursors]::Hand
		$btn.VerticalAlignment = 'Center'
		$btn.HorizontalAlignment = 'Right'
		$btn.FocusVisualStyle = $null
		$btn.ToolTip = (Get-UxLocalizedString -Key 'GuiWhyThisMattersTooltip' -Fallback 'Show why this tweak matters')
		$btn.Template = $Script:WhyThisMattersButtonTemplate

		# Expandable hint border (stored in Tag for caller to add to layout)
		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)
		$hintBorder.Margin = [System.Windows.Thickness]::new($LeftIndent, 3, 8, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock

		$btn.Tag = $hintBorder

		$btnRef = $btn
		$borderRef = $hintBorder
		$hoverBg = $bc.ConvertFromString($Script:CurrentTheme.TabHoverBg)
		$pressBg = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$normalFg = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$activeFg = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$detailsLabel = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$hideDetailsLabel = Get-UxLocalizedString -Key 'GuiHideDetails' -Fallback 'Hide details'
		$null = Register-GuiEventHandler -Source $btn -EventName 'MouseEnter' -Handler ({
			$btnRef.Background = $hoverBg
			$btnRef.Foreground = $activeFg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'MouseLeave' -Handler ({
			$btnRef.Background = [System.Windows.Media.Brushes]::Transparent
			$btnRef.Foreground = $normalFg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'PreviewMouseLeftButtonDown' -Handler ({
			$btnRef.Background = $pressBg
		}.GetNewClosure())
		$null = Register-GuiEventHandler -Source $btn -EventName 'Click' -Handler ({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$btnRef.Content = if ($isVisible) { $detailsLabel } else { $hideDetailsLabel }
			$btnRef.Foreground = if ($isVisible) { $normalFg } else { $activeFg }
		}.GetNewClosure())

		return $btn
	}

	<#
	    .SYNOPSIS
	#>

	function New-WhyThisMattersBlock
	{
		param (
			[object]$Tweak,
			[int]$LeftIndent = 0
		)

		$whyThisMatters = Get-GuiObjectField -Object $Tweak -FieldName 'WhyThisMatters'
		$hintText = if ($Tweak -and -not [string]::IsNullOrWhiteSpace([string]$whyThisMatters)) {
			[string]$whyThisMatters
		}
		else {
			$null
		}
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersToggle'
		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'
		$stack.Margin = [System.Windows.Thickness]::new($LeftIndent, 6, 8, 0)

		$toggle = New-PresetButton -Label (Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details') -Variant 'Subtle' -Compact -Muted
		$toggle.Margin = [System.Windows.Thickness]::new(0)
		$toggle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
		$toggle.ToolTip = (Get-UxLocalizedString -Key 'GuiWhyThisMattersTooltip' -Fallback 'Show why this tweak matters')
		[void]($stack.Children.Add($toggle))
		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
		$hintBorder.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock
		[void]($stack.Children.Add($hintBorder))
		$toggleRef = $toggle
		$borderRef = $hintBorder
		$detailsLabel = Get-UxLocalizedString -Key 'GuiDetailsButton' -Fallback 'Details'
		$hideDetailsLabel = Get-UxLocalizedString -Key 'GuiHideDetails' -Fallback 'Hide details'
		$null = Register-GuiEventHandler -Source $toggle -EventName 'Click' -Handler ({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$toggleRef.Content = if ($isVisible) { $detailsLabel } else { $hideDetailsLabel }
		}.GetNewClosure())

		return $stack
	}

