<#
    .SYNOPSIS
    Shared GUI scrollbar resources.
#>

function Get-GuiSharedScrollBarStyleXaml
{
	<# .SYNOPSIS Returns the shared Baseline scrollbar styles used by the main GUI and popups. #>
	param(
		[hashtable]$Theme = $null
	)

	$track = '#151824'
	$thumb = '#3A4561'
	$hover = '#4D5875'
	$active = '#5E6C8E'

	if ($Theme)
	{
		if ($Theme.ScrollBg) { $track = [string]$Theme.ScrollBg }
		if ($Theme.ScrollThumb) { $thumb = [string]$Theme.ScrollThumb }
		if ($Theme.ScrollThumbHover) { $hover = [string]$Theme.ScrollThumbHover }
		if ($Theme.ScrollThumbActive) { $active = [string]$Theme.ScrollThumbActive }
	}

	return @"
<SolidColorBrush x:Key="ScrollBarTrackBrush" Color="$track"/>
<SolidColorBrush x:Key="ScrollBarThumbBrush" Color="$thumb"/>
<SolidColorBrush x:Key="ScrollBarThumbHoverBrush" Color="$hover"/>
<SolidColorBrush x:Key="ScrollBarThumbActiveBrush" Color="$active"/>
<Style x:Key="BaselineScrollBarThumbStyle" TargetType="Thumb">
	<Setter Property="OverridesDefaultStyle" Value="True"/>
	<Setter Property="IsTabStop" Value="False"/>
	<Setter Property="Focusable" Value="False"/>
	<Setter Property="Background" Value="{DynamicResource ScrollBarThumbBrush}"/>
	<Setter Property="Template">
		<Setter.Value>
			<ControlTemplate TargetType="Thumb">
				<Border x:Name="ThumbBorder" Background="{TemplateBinding Background}" CornerRadius="4" Margin="2" Opacity="0.55"/>
				<ControlTemplate.Triggers>
					<Trigger Property="IsMouseOver" Value="True">
						<Setter TargetName="ThumbBorder" Property="Background" Value="{DynamicResource ScrollBarThumbHoverBrush}"/>
						<Setter TargetName="ThumbBorder" Property="Opacity" Value="0.85"/>
					</Trigger>
					<Trigger Property="IsDragging" Value="True">
						<Setter TargetName="ThumbBorder" Property="Background" Value="{DynamicResource ScrollBarThumbActiveBrush}"/>
						<Setter TargetName="ThumbBorder" Property="Opacity" Value="1.0"/>
					</Trigger>
				</ControlTemplate.Triggers>
			</ControlTemplate>
		</Setter.Value>
	</Setter>
</Style>
<Style x:Key="BaselineScrollBarRepeatButtonStyle" TargetType="RepeatButton">
	<Setter Property="OverridesDefaultStyle" Value="True"/>
	<Setter Property="Background" Value="Transparent"/>
	<Setter Property="IsTabStop" Value="False"/>
	<Setter Property="Focusable" Value="False"/>
	<Setter Property="Template">
		<Setter.Value>
			<ControlTemplate TargetType="RepeatButton">
				<Border Background="Transparent"/>
			</ControlTemplate>
		</Setter.Value>
	</Setter>
</Style>
<Style x:Key="BaselineScrollBarArrowButtonStyle" TargetType="RepeatButton">
	<Setter Property="OverridesDefaultStyle" Value="True"/>
	<Setter Property="Background" Value="Transparent"/>
	<Setter Property="IsTabStop" Value="False"/>
	<Setter Property="Focusable" Value="False"/>
	<Setter Property="Delay" Value="350"/>
	<Setter Property="Interval" Value="55"/>
	<Setter Property="Template">
		<Setter.Value>
			<ControlTemplate TargetType="RepeatButton">
				<Grid Background="Transparent" SnapsToDevicePixels="True">
					<Border x:Name="ArrowSurface" Background="{DynamicResource ScrollBarThumbHoverBrush}" CornerRadius="4" Opacity="0"/>
					<ContentPresenter x:Name="ArrowGlyph" HorizontalAlignment="Center" VerticalAlignment="Center" Opacity="0.38"/>
				</Grid>
				<ControlTemplate.Triggers>
					<Trigger Property="IsMouseOver" Value="True">
						<Setter TargetName="ArrowSurface" Property="Opacity" Value="0.16"/>
						<Setter TargetName="ArrowGlyph" Property="Opacity" Value="0.92"/>
					</Trigger>
					<Trigger Property="IsPressed" Value="True">
						<Setter TargetName="ArrowSurface" Property="Opacity" Value="0.24"/>
						<Setter TargetName="ArrowGlyph" Property="Opacity" Value="1.0"/>
					</Trigger>
					<Trigger Property="IsEnabled" Value="False">
						<Setter TargetName="ArrowGlyph" Property="Opacity" Value="0.14"/>
					</Trigger>
				</ControlTemplate.Triggers>
			</ControlTemplate>
		</Setter.Value>
	</Setter>
</Style>
<Style TargetType="ScrollBar">
	<Setter Property="Background" Value="{DynamicResource ScrollBarTrackBrush}"/>
	<Setter Property="Foreground" Value="{DynamicResource ScrollBarThumbBrush}"/>
	<Setter Property="BorderThickness" Value="0"/>
	<Setter Property="SnapsToDevicePixels" Value="True"/>
	<Style.Triggers>
		<Trigger Property="Orientation" Value="Vertical">
			<Setter Property="Width" Value="10"/>
			<Setter Property="MinWidth" Value="10"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="ScrollBar">
						<Grid Background="Transparent" SnapsToDevicePixels="True">
							<Grid.RowDefinitions>
								<RowDefinition Height="16"/>
								<RowDefinition Height="*"/>
								<RowDefinition Height="16"/>
							</Grid.RowDefinitions>
							<RepeatButton Grid.Row="0" Style="{StaticResource BaselineScrollBarArrowButtonStyle}" Command="ScrollBar.LineUpCommand">
								<Path Data="M 2 6 L 5 3 L 8 6" Stroke="{DynamicResource ScrollBarThumbBrush}" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
							</RepeatButton>
							<Border Grid.Row="1" Background="{TemplateBinding Background}" Opacity="0.30" CornerRadius="5" Margin="1,0"/>
							<Track Grid.Row="1" Name="PART_Track" IsDirectionReversed="True">
								<Track.DecreaseRepeatButton>
									<RepeatButton Style="{StaticResource BaselineScrollBarRepeatButtonStyle}" Command="ScrollBar.PageUpCommand"/>
								</Track.DecreaseRepeatButton>
								<Track.Thumb>
									<Thumb Style="{StaticResource BaselineScrollBarThumbStyle}" MinHeight="30"/>
								</Track.Thumb>
								<Track.IncreaseRepeatButton>
									<RepeatButton Style="{StaticResource BaselineScrollBarRepeatButtonStyle}" Command="ScrollBar.PageDownCommand"/>
								</Track.IncreaseRepeatButton>
							</Track>
							<RepeatButton Grid.Row="2" Style="{StaticResource BaselineScrollBarArrowButtonStyle}" Command="ScrollBar.LineDownCommand">
								<Path Data="M 2 3 L 5 6 L 8 3" Stroke="{DynamicResource ScrollBarThumbBrush}" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
							</RepeatButton>
						</Grid>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Trigger>
		<Trigger Property="Orientation" Value="Horizontal">
			<Setter Property="Height" Value="10"/>
			<Setter Property="MinHeight" Value="10"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="ScrollBar">
						<Grid Background="Transparent" SnapsToDevicePixels="True">
							<Grid.ColumnDefinitions>
								<ColumnDefinition Width="16"/>
								<ColumnDefinition Width="*"/>
								<ColumnDefinition Width="16"/>
							</Grid.ColumnDefinitions>
							<RepeatButton Grid.Column="0" Style="{StaticResource BaselineScrollBarArrowButtonStyle}" Command="ScrollBar.LineLeftCommand">
								<Path Data="M 6 2 L 3 5 L 6 8" Stroke="{DynamicResource ScrollBarThumbBrush}" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
							</RepeatButton>
							<Border Grid.Column="1" Background="{TemplateBinding Background}" Opacity="0.30" CornerRadius="5" Margin="0,1"/>
							<Track Grid.Column="1" Name="PART_Track" IsDirectionReversed="False">
								<Track.DecreaseRepeatButton>
									<RepeatButton Style="{StaticResource BaselineScrollBarRepeatButtonStyle}" Command="ScrollBar.PageLeftCommand"/>
								</Track.DecreaseRepeatButton>
								<Track.Thumb>
									<Thumb Style="{StaticResource BaselineScrollBarThumbStyle}" MinWidth="30"/>
								</Track.Thumb>
								<Track.IncreaseRepeatButton>
									<RepeatButton Style="{StaticResource BaselineScrollBarRepeatButtonStyle}" Command="ScrollBar.PageRightCommand"/>
								</Track.IncreaseRepeatButton>
							</Track>
							<RepeatButton Grid.Column="2" Style="{StaticResource BaselineScrollBarArrowButtonStyle}" Command="ScrollBar.LineRightCommand">
								<Path Data="M 3 2 L 6 5 L 3 8" Stroke="{DynamicResource ScrollBarThumbBrush}" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="8" Height="8" Stretch="Uniform"/>
							</RepeatButton>
						</Grid>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Trigger>
	</Style.Triggers>
</Style>
"@
}

function Add-GuiSharedScrollBarResources
{
	<# .SYNOPSIS Adds the shared Baseline scrollbar styles to a WPF resource owner. #>
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Target,

		[hashtable]$Theme = $null
	)

	if (-not $Target)
	{
		return $false
	}

	try
	{
		$resources = $null
		if ($Target -is [System.Windows.ResourceDictionary])
		{
			$resources = $Target
		}
		elseif ($Target.PSObject.Properties['Resources'])
		{
			$resources = $Target.Resources
		}

		if (-not $resources)
		{
			return $false
		}

		$styleXaml = Get-GuiSharedScrollBarStyleXaml -Theme $Theme
		[xml]$dictionaryXaml = @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
$styleXaml
</ResourceDictionary>
"@
		$reader = [System.Xml.XmlNodeReader]::new($dictionaryXaml)
		try
		{
			$dictionary = [System.Windows.Markup.XamlReader]::Load($reader)
		}
		finally
		{
			if ($reader) { $reader.Close() }
		}

		if (-not ($dictionary -is [System.Windows.ResourceDictionary]))
		{
			return $false
		}

		[void]$resources.MergedDictionaries.Add($dictionary)
		return $true
	}
	catch
	{
		try { Write-SwallowedException -ErrorRecord $_ -Source 'GUICommon.AddGuiSharedScrollBarResources' } catch { Write-Warning "Failed to log shared scrollbar resource failure: $($_.Exception.Message)" }
		return $false
	}
}
