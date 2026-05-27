$planRowItems = [System.Collections.Generic.List[object]]::new()

$typeBadgeBackground = $bc.ConvertFromString($theme.StatusPillBg)
$typeBadgeBorder = $bc.ConvertFromString($theme.StatusPillBorder)
$typeBadgeForeground = $bc.ConvertFromString($theme.StatusPillText)
$riskBadgeBackground = $bc.ConvertFromString($theme.RiskHighBadgeBg)
$riskBadgeBrush = $bc.ConvertFromString($theme.RiskHighBadge)
$restartBadgeBackground = $bc.ConvertFromString($theme.RiskMediumBadgeBg)
$restartBadgeBrush = $bc.ConvertFromString($theme.RiskMediumBadge)
$badgeCornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.PillCornerRadius)
$rowCornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.BorderRadiusSmall)
$tinyFontSize = [double]$Script:GuiLayout.FontSizeTiny
$highRiskLabel = Get-UxLocalizedString -Key 'GuiPlanHighRisk' -Fallback 'High Risk'
$restartLabel = Get-UxLocalizedString -Key 'GuiPlanRestart' -Fallback 'Restart'

foreach ($tweak in $sortedTweaks)
{
	$badgeItems = [System.Collections.Generic.List[object]]::new()

	$tweakType = if (Test-GuiObjectField -Object $tweak -FieldName 'Type') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Type') } else { '' }
	if (-not [string]::IsNullOrWhiteSpace($tweakType))
	{
		[void]($badgeItems.Add([pscustomobject]@{
					Text = $tweakType
					Background = $typeBadgeBackground
					BorderBrush = $typeBadgeBorder
					Foreground = $typeBadgeForeground
					CornerRadius = $badgeCornerRadius
					FontSize = $tinyFontSize
				}))
	}

	$tweakRisk = if (Test-GuiObjectField -Object $tweak -FieldName 'Risk') { [string](Get-GuiObjectField -Object $tweak -FieldName 'Risk') } else { $null }
	if ($tweakRisk -eq 'High')
	{
		[void]($badgeItems.Add([pscustomobject]@{
					Text = $highRiskLabel
					Background = $riskBadgeBackground
					BorderBrush = $riskBadgeBrush
					Foreground = $riskBadgeBrush
					CornerRadius = $badgeCornerRadius
					FontSize = $tinyFontSize
				}))
	}

	$needsRestart = (Test-GuiObjectField -Object $tweak -FieldName 'RequiresRestart') -and [bool](Get-GuiObjectField -Object $tweak -FieldName 'RequiresRestart')
	if ($needsRestart)
	{
		[void]($badgeItems.Add([pscustomobject]@{
					Text = ("{0} {1}" -f [char]0x21BB, $restartLabel)
					Background = $restartBadgeBackground
					BorderBrush = $restartBadgeBrush
					Foreground = $restartBadgeBrush
					CornerRadius = $badgeCornerRadius
					FontSize = $tinyFontSize
				}))
	}

	[void]($planRowItems.Add([pscustomobject]@{
				Name = [string]$tweak.Name
				Badges = [object[]]$badgeItems.ToArray()
				CardBackground = $brushCardBg
				CardBorder = $brushCardBorder
				TextForeground = $brushTextPrimary
				RowCornerRadius = $rowCornerRadius
			}))
}

$planRowsList = New-Object System.Windows.Controls.ListBox
$planRowsList.ItemsSource = $planRowItems
$planRowsList.BorderThickness = [System.Windows.Thickness]::new(0)
$planRowsList.Background = [System.Windows.Media.Brushes]::Transparent
$planRowsList.Focusable = $false
$planRowsList.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Stretch
$planRowsList.MaxHeight = [Math]::Max(260, ([double]$Script:GuiLayout.DialogLargeHeight - 360))
$planRowsList.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

[System.Windows.Controls.VirtualizingStackPanel]::SetIsVirtualizing($planRowsList, $true)
[System.Windows.Controls.VirtualizingStackPanel]::SetVirtualizationMode($planRowsList, [System.Windows.Controls.VirtualizationMode]::Recycling)
[System.Windows.Controls.ScrollViewer]::SetCanContentScroll($planRowsList, $true)
[System.Windows.Controls.ScrollViewer]::SetVerticalScrollBarVisibility($planRowsList, [System.Windows.Controls.ScrollBarVisibility]::Auto)
[System.Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($planRowsList, [System.Windows.Controls.ScrollBarVisibility]::Disabled)

$planRowsItemContainerStyle = New-Object -TypeName System.Windows.Style -ArgumentList ([System.Windows.Controls.ListBoxItem])
[void]($planRowsItemContainerStyle.Setters.Add((New-Object -TypeName System.Windows.Setter -ArgumentList ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty), ([System.Windows.HorizontalAlignment]::Stretch))))
[void]($planRowsItemContainerStyle.Setters.Add((New-Object -TypeName System.Windows.Setter -ArgumentList ([System.Windows.Controls.Control]::PaddingProperty), ([System.Windows.Thickness]::new(0)))))
[void]($planRowsItemContainerStyle.Setters.Add((New-Object -TypeName System.Windows.Setter -ArgumentList ([System.Windows.Controls.Control]::BackgroundProperty), ([System.Windows.Media.Brushes]::Transparent))))
$planRowsList.ItemContainerStyle = $planRowsItemContainerStyle

$planRowsTemplateXaml = @'
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
	<Border Background="{Binding CardBackground}" BorderBrush="{Binding CardBorder}" BorderThickness="1" CornerRadius="{Binding RowCornerRadius}" Padding="12,8,12,8" Margin="0,0,0,4">
		<Grid>
			<Grid.ColumnDefinitions>
				<ColumnDefinition Width="*"/>
				<ColumnDefinition Width="Auto"/>
			</Grid.ColumnDefinitions>
			<TextBlock Grid.Column="0" Text="{Binding Name}" Foreground="{Binding TextForeground}" FontWeight="Normal" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
			<ItemsControl Grid.Column="1" ItemsSource="{Binding Badges}" VerticalAlignment="Center">
				<ItemsControl.ItemsPanel>
					<ItemsPanelTemplate>
						<StackPanel Orientation="Horizontal"/>
					</ItemsPanelTemplate>
				</ItemsControl.ItemsPanel>
				<ItemsControl.ItemTemplate>
					<DataTemplate>
						<Border Background="{Binding Background}" BorderBrush="{Binding BorderBrush}" BorderThickness="1" CornerRadius="{Binding CornerRadius}" Padding="8,2,8,2" Margin="6,0,0,0">
							<TextBlock Text="{Binding Text}" FontSize="{Binding FontSize}" FontWeight="SemiBold" Foreground="{Binding Foreground}"/>
						</Border>
					</DataTemplate>
				</ItemsControl.ItemTemplate>
			</ItemsControl>
		</Grid>
	</Border>
</DataTemplate>
'@
$planRowsList.ItemTemplate = [System.Windows.Markup.XamlReader]::Parse($planRowsTemplateXaml)

[void]($bodyStack.Children.Add($planRowsList))
