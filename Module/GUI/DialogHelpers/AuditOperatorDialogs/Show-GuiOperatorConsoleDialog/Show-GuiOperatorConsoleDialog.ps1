[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="940" Height="680"
	MinWidth="780" MinHeight="600"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="FluentSystemIcons"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>

			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
				<Grid>
					<TextBlock Text="$windowTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<Border Grid.Row="1" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
					Padding="20,14,20,14">
				<StackPanel>
					<TextBlock Name="TxtDialogTitle" Text="$windowTitle" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtDialogSubtitle" Text="$windowSubtitle"
							   FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,16,20,16">
				<Grid>
					<Grid.RowDefinitions>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
						<RowDefinition Height="Auto"/>
					</Grid.RowDefinitions>

					<!-- Caps -->
					<Border Grid.Row="0" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="14,12,14,12" Margin="0,0,0,12">
						<Grid>
							<Grid.ColumnDefinitions>
								<ColumnDefinition Width="*"/>
								<ColumnDefinition Width="*"/>
							</Grid.ColumnDefinitions>
							<StackPanel Grid.Column="0">
								<TextBlock Text="Per-run target cap" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
								<TextBox Name="TxtMaxTargets" Margin="0,4,8,0" Padding="6,4,6,4"/>
							</StackPanel>
							<StackPanel Grid.Column="1">
								<TextBlock Text="Max concurrent targets" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
								<TextBox Name="TxtMaxConcurrent" Margin="0,4,0,0" Padding="6,4,6,4"/>
							</StackPanel>
						</Grid>
					</Border>

					<!-- Change window -->
					<Border Grid.Row="1" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="14,12,14,12" Margin="0,0,0,12">
						<StackPanel>
							<TextBlock Text="Change window" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
							<TextBlock Name="TxtChangeWindowHint" Text="Comma-separated days (Mon,Tue,...) and HH:mm start/end. Empty = always allowed." Foreground="$($theme.TextMuted)" TextWrapping="Wrap" Margin="0,2,0,6"/>
							<Grid>
								<Grid.ColumnDefinitions>
									<ColumnDefinition Width="2*"/>
									<ColumnDefinition Width="*"/>
									<ColumnDefinition Width="*"/>
								</Grid.ColumnDefinitions>
								<TextBox Name="TxtChangeDays" Margin="0,0,8,0" Padding="6,4,6,4"/>
								<TextBox Name="TxtChangeStart" Grid.Column="1" Margin="0,0,8,0" Padding="6,4,6,4"/>
								<TextBox Name="TxtChangeEnd" Grid.Column="2" Padding="6,4,6,4"/>
							</Grid>
							<TextBlock Name="TxtChangeWindowState" Text="" Foreground="$($theme.TextSecondary)" Margin="0,8,0,0" TextWrapping="Wrap"/>
						</StackPanel>
					</Border>

					<!-- Allow/Deny -->
					<Border Grid.Row="2" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="14,12,14,12" Margin="0,0,0,12">
						<Grid>
							<Grid.ColumnDefinitions>
								<ColumnDefinition Width="*"/>
								<ColumnDefinition Width="*"/>
								<ColumnDefinition Width="*"/>
							</Grid.ColumnDefinitions>
							<StackPanel Grid.Column="0">
								<TextBlock Text="Allowed targets (one per line, empty = all)" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
								<TextBox Name="TxtAllowedTargets" Margin="0,4,8,0" Padding="6,4,6,4" Height="80" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
							</StackPanel>
							<StackPanel Grid.Column="1">
								<TextBlock Text="Denied targets (one per line)" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
								<TextBox Name="TxtDeniedTargets" Margin="0,4,8,0" Padding="6,4,6,4" Height="80" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
							</StackPanel>
							<StackPanel Grid.Column="2">
								<TextBlock Text="Denied functions (one per line)" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
								<TextBox Name="TxtDeniedFunctions" Margin="0,4,0,0" Padding="6,4,6,4" Height="80" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
							</StackPanel>
						</Grid>
					</Border>

					<!-- Kill switch -->
					<Border Grid.Row="3" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="14,12,14,12" Margin="0,0,0,12">
						<StackPanel>
							<TextBlock Text="Kill switch" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
							<TextBlock Name="TxtKillSwitchPath" Text="" Foreground="$($theme.TextMuted)" Margin="0,2,0,6" TextWrapping="Wrap"/>
							<TextBlock Name="TxtKillSwitchState" Text="" Foreground="$($theme.TextSecondary)" Margin="0,0,0,8" TextWrapping="Wrap"/>
							<WrapPanel>
								<Button Name="BtnKillEngage" Content="" Margin="0,0,8,0" Padding="14,6"/>
								<Button Name="BtnKillClear" Content="" Padding="14,6"/>
							</WrapPanel>
						</StackPanel>
					</Border>

					<!-- Decision -->
					<Border Grid.Row="4" Background="$($theme.InputBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1" CornerRadius="6" Padding="14,12,14,12">
						<StackPanel>
							<TextBlock Text="Current policy decision" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
							<TextBlock Name="TxtDecisionTargets" Text="" Foreground="$($theme.TextMuted)" Margin="0,2,0,6" TextWrapping="Wrap"/>
							<TextBlock Name="TxtDecisionSummary" Text="" FontFamily="Consolas, Menlo, monospace" Foreground="$($theme.TextPrimary)" TextWrapping="Wrap"/>
						</StackPanel>
					</Border>
				</Grid>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<WrapPanel HorizontalAlignment="Right">
					<Button Name="BtnEvaluate" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnSavePolicy" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnLoadPolicy" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnRefresh" Content="" Margin="0,0,8,0" Padding="16,6" FontSize="13"/>
					<Button Name="BtnClose" Content="" Padding="16,6" FontSize="13"/>
				</WrapPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@
