[xml]$XAML = @"
	<Window
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Name="Window"
		MinHeight="450" MinWidth="415"
		SizeToContent="Width" WindowStartupLocation="CenterScreen"
		TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True"
		FontFamily="Segoe UI" FontSize="12" ShowInTaskbar="True"
		Background="Transparent" WindowStyle="None" AllowsTransparency="True" Foreground="#262626">
		<Window.Resources>
			<Style TargetType="CheckBox">
				<Setter Property="IsChecked" Value="True"/>
			</Style>
			<Style TargetType="Button">
				<Setter Property="Margin" Value="20"/>
				<Setter Property="Padding" Value="10"/>
			</Style>
			<Style TargetType="Border">
				<Setter Property="Grid.Row" Value="1"/>
				<Setter Property="CornerRadius" Value="0"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
				<Setter Property="BorderBrush" Value="#000000"/>
			</Style>
			<Style TargetType="ScrollViewer">
				<Setter Property="HorizontalScrollBarVisibility" Value="Disabled"/>
				<Setter Property="BorderBrush" Value="#000000"/>
				<Setter Property="BorderThickness" Value="0, 1, 0, 1"/>
			</Style>
		</Window.Resources>
		<Border Name="RootBorder" CornerRadius="8">
			<Grid>
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>
				<Grid Grid.Row="0" Margin="10,8,10,8">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
					</Grid.ColumnDefinitions>
					<StackPanel Name="PanelSelectAll" Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
						<CheckBox Name="CheckBoxSelectAll" IsChecked="False" VerticalAlignment="Center" Margin="0,0,6,0"/>
						<TextBlock Name="TextBlockSelectAll" VerticalAlignment="Center"/>
					</StackPanel>
				</Grid>
				<Border>
					<ScrollViewer>
						<StackPanel Name="PanelContainer" Orientation="Vertical"/>
					</ScrollViewer>
				</Border>
				<Button Name="Button" Grid.Row="2"/>
			</Grid>
		</Border>
	</Window>
"@
