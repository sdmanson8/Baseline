[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="880" Height="660"
	MinWidth="760" MinHeight="560"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	FontFamily="Segoe UI"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Window.Resources>
		<SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="$surfaceControl"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="$textPrimary"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="$surfaceControl"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="$textPrimary"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="$selectionSurface"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="$textPrimary"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.MenuBrushKey}" Color="$surfaceControl"/>
		<SolidColorBrush x:Key="{x:Static SystemColors.MenuTextBrushKey}" Color="$textPrimary"/>
$scrollBarStyleXaml
		<Style TargetType="TextBlock" x:Key="SectionHeading">
			<Setter Property="FontSize" Value="14"/>
			<Setter Property="FontWeight" Value="SemiBold"/>
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="Margin" Value="0,0,0,4"/>
		</Style>
		<Style TargetType="TextBlock" x:Key="SectionSubtitle">
			<Setter Property="FontSize" Value="11"/>
			<Setter Property="Foreground" Value="$textMuted"/>
			<Setter Property="Margin" Value="0,0,0,16"/>
			<Setter Property="TextWrapping" Value="Wrap"/>
		</Style>
		<Style TargetType="TextBlock" x:Key="FieldLabel">
			<Setter Property="FontSize" Value="12"/>
			<Setter Property="FontWeight" Value="Medium"/>
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="Margin" Value="0,0,0,6"/>
		</Style>
		<Style TargetType="TextBlock" x:Key="HelperText">
			<Setter Property="FontSize" Value="11"/>
			<Setter Property="Foreground" Value="$textMuted"/>
			<Setter Property="Margin" Value="0,4,0,0"/>
			<Setter Property="TextWrapping" Value="Wrap"/>
		</Style>
		<Style TargetType="CheckBox" x:Key="SettingsCheck">
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="FontSize" Value="12"/>
			<Setter Property="FontWeight" Value="Medium"/>
			<Setter Property="Margin" Value="0,0,0,10"/>
			<Style.Triggers>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Foreground" Value="$textSecondary"/>
					<Setter Property="Opacity" Value="1"/>
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style TargetType="{x:Type ComboBoxItem}" x:Key="SettingsComboItem">
			<Setter Property="Background" Value="$surfaceControl"/>
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="Padding" Value="10,4"/>
			<Setter Property="HorizontalContentAlignment" Value="Stretch"/>
			<Setter Property="MinHeight" Value="28"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ComboBoxItem}">
						<Border x:Name="ItemRoot"
								Background="{TemplateBinding Background}"
								BorderBrush="{TemplateBinding BorderBrush}"
								BorderThickness="{TemplateBinding BorderThickness}"
								Padding="{TemplateBinding Padding}"
								SnapsToDevicePixels="True">
							<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
											  VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
											  TextElement.Foreground="{TemplateBinding Foreground}"/>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="ItemRoot" Property="Background" Value="$surfaceHover"/>
							</Trigger>
							<Trigger Property="IsSelected" Value="True">
								<Setter TargetName="ItemRoot" Property="Background" Value="$selectionSurface"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
			<Style.Triggers>
				<Trigger Property="IsMouseOver" Value="True">
					<Setter Property="Background" Value="$surfaceHover"/>
					<Setter Property="Foreground" Value="$textPrimary"/>
				</Trigger>
				<Trigger Property="IsSelected" Value="True">
					<Setter Property="Background" Value="$selectionSurface"/>
					<Setter Property="Foreground" Value="$textPrimary"/>
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style TargetType="ComboBox" x:Key="SettingsCombo">
			<Setter Property="Width" Value="320"/>
			<Setter Property="HorizontalAlignment" Value="Left"/>
			<Setter Property="Margin" Value="0,0,0,18"/>
			<Setter Property="Padding" Value="10,4"/>
			<Setter Property="MinHeight" Value="30"/>
			<Setter Property="Background" Value="$surfaceControl"/>
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="BorderBrush" Value="$controlBorder"/>
			<Setter Property="BorderThickness" Value="1"/>
			<Setter Property="Opacity" Value="1"/>
			<Setter Property="OverridesDefaultStyle" Value="True"/>
			<Setter Property="ItemContainerStyle" Value="{StaticResource SettingsComboItem}"/>
			<Setter Property="TextElement.Foreground" Value="$textPrimary"/>
			<Setter Property="HorizontalContentAlignment" Value="Left"/>
			<Setter Property="VerticalContentAlignment" Value="Center"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="{x:Type ComboBox}">
						<Grid SnapsToDevicePixels="True" TextElement.Foreground="{TemplateBinding Foreground}">
							<Border x:Name="ComboRoot"
									Background="{TemplateBinding Background}"
									BorderBrush="{TemplateBinding BorderBrush}"
									BorderThickness="{TemplateBinding BorderThickness}"
									CornerRadius="4"
									SnapsToDevicePixels="True"/>
							<ToggleButton x:Name="DropDownToggle"
										  Focusable="False"
										  ClickMode="Press"
										  Background="Transparent"
										  BorderBrush="Transparent"
										  BorderThickness="0"
										  HorizontalAlignment="Stretch"
										  VerticalAlignment="Stretch"
										  IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
								<ToggleButton.Template>
									<ControlTemplate TargetType="{x:Type ToggleButton}">
										<Border Background="Transparent"/>
									</ControlTemplate>
								</ToggleButton.Template>
							</ToggleButton>
							<ContentPresenter x:Name="ContentSite"
											  Margin="{TemplateBinding Padding}"
											  HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
											  VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
											  TextElement.Foreground="{TemplateBinding Foreground}"
											  Content="{TemplateBinding SelectionBoxItem}"
											  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
											  ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
											  ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
											  IsHitTestVisible="False"
											  RecognizesAccessKey="True"/>
							<Path x:Name="Arrow"
								  HorizontalAlignment="Right"
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
								  IsHitTestVisible="False"/>
							<Popup x:Name="Popup"
								   Placement="Bottom"
								   PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}"
								   AllowsTransparency="True"
								   Focusable="False"
								   IsOpen="{TemplateBinding IsDropDownOpen}"
								   PopupAnimation="Slide">
								<Border MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
										Background="$surfaceControl"
										BorderBrush="$controlBorder"
										BorderThickness="1"
										CornerRadius="6"
										SnapsToDevicePixels="True">
									<ScrollViewer Margin="4,6,4,6" MaxHeight="260" SnapsToDevicePixels="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
										<ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
									</ScrollViewer>
								</Border>
							</Popup>
						</Grid>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="ComboRoot" Property="Background" Value="$surfaceHover"/>
								<Setter TargetName="ComboRoot" Property="BorderBrush" Value="$activeBorder"/>
							</Trigger>
							<Trigger Property="IsKeyboardFocusWithin" Value="True">
								<Setter TargetName="ComboRoot" Property="Background" Value="$surfaceHover"/>
								<Setter TargetName="ComboRoot" Property="BorderBrush" Value="$activeBorder"/>
							</Trigger>
							<Trigger Property="IsDropDownOpen" Value="True">
								<Setter TargetName="ComboRoot" Property="Background" Value="$surfaceHover"/>
								<Setter TargetName="ComboRoot" Property="BorderBrush" Value="$activeBorder"/>
							</Trigger>
							<Trigger Property="IsEnabled" Value="False">
								<Setter Property="Foreground" Value="$textSecondary"/>
								<Setter TargetName="ComboRoot" Property="Background" Value="$surfaceControl"/>
								<Setter TargetName="ComboRoot" Property="BorderBrush" Value="$controlBorder"/>
								<Setter TargetName="Arrow" Property="Stroke" Value="$textSecondary"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
			<Style.Triggers>
				<Trigger Property="IsKeyboardFocusWithin" Value="True">
					<Setter Property="Background" Value="$surfaceHover"/>
					<Setter Property="BorderBrush" Value="$activeBorder"/>
				</Trigger>
				<Trigger Property="IsDropDownOpen" Value="True">
					<Setter Property="Background" Value="$surfaceHover"/>
					<Setter Property="BorderBrush" Value="$activeBorder"/>
				</Trigger>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Background" Value="$surfaceControl"/>
					<Setter Property="Foreground" Value="$textSecondary"/>
					<Setter Property="Opacity" Value="1"/>
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style TargetType="TextBox" x:Key="SettingsTextBox">
			<Setter Property="HorizontalAlignment" Value="Left"/>
			<Setter Property="Margin" Value="0,0,0,18"/>
			<Setter Property="Padding" Value="8,6"/>
			<Setter Property="MinHeight" Value="30"/>
			<Setter Property="Background" Value="$surfaceControl"/>
			<Setter Property="Foreground" Value="$textPrimary"/>
			<Setter Property="BorderBrush" Value="$controlBorder"/>
			<Setter Property="BorderThickness" Value="1"/>
			<Setter Property="CaretBrush" Value="$textPrimary"/>
			<Setter Property="SelectionBrush" Value="$selectionSurface"/>
			<Setter Property="Opacity" Value="1"/>
			<Style.Triggers>
				<Trigger Property="IsKeyboardFocusWithin" Value="True">
					<Setter Property="Background" Value="$surfaceHover"/>
					<Setter Property="BorderBrush" Value="$activeBorder"/>
				</Trigger>
				<Trigger Property="IsEnabled" Value="False">
					<Setter Property="Background" Value="$surfaceControl"/>
					<Setter Property="Foreground" Value="$textSecondary"/>
					<Setter Property="Opacity" Value="1"/>
				</Trigger>
			</Style.Triggers>
		</Style>
		<Style TargetType="TabItem">
			<Setter Property="Padding" Value="18,10"/>
			<Setter Property="Margin" Value="0,0,4,0"/>
			<Setter Property="FontSize" Value="13"/>
			<Setter Property="FontWeight" Value="Normal"/>
			<Setter Property="Foreground" Value="$textMuted"/>
			<Setter Property="Background" Value="Transparent"/>
			<Setter Property="Cursor" Value="Hand"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="TabItem">
						<Border Name="TabRoot"
								Background="{TemplateBinding Background}"
								BorderBrush="Transparent"
								BorderThickness="0,0,0,3"
								Padding="{TemplateBinding Padding}"
								CornerRadius="4,4,0,0"
								SnapsToDevicePixels="True">
							<ContentPresenter ContentSource="Header"
											  HorizontalAlignment="Center"
											  VerticalAlignment="Center"
											  TextElement.Foreground="{TemplateBinding Foreground}"
											  TextElement.FontWeight="{TemplateBinding FontWeight}"
											  RecognizesAccessKey="True"/>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter Property="Foreground" Value="$textPrimary"/>
								<Setter TargetName="TabRoot" Property="Background" Value="$tabHoverBg"/>
							</Trigger>
							<Trigger Property="IsSelected" Value="True">
								<Setter Property="Foreground" Value="$textPrimary"/>
								<Setter Property="FontWeight" Value="SemiBold"/>
								<Setter TargetName="TabRoot" Property="Background" Value="$cardBg"/>
								<Setter TargetName="TabRoot" Property="BorderBrush" Value="$activeBorder"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
	</Window.Resources>
	<Border Name="RootBorder" CornerRadius="8">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>

			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="14,8,8,8" Cursor="Arrow">
				<Grid>
					<TextBlock Text="$windowTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<Border Grid.Row="1" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
					Padding="24,16,24,16">
				<StackPanel>
					<TextBlock Text="$windowTitle" FontSize="18" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$windowSubtitle" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,4,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<TabControl Name="SettingsTabs" Grid.Row="2" Margin="20,14,20,14"
						Background="Transparent" BorderThickness="0" Padding="0">

				<TabItem Name="TabSettingsGeneral" Header="$generalHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsGeneralSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsGeneralSubtitle"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblLanguage" Text="$settingsLanguageLabel"/>
								<Grid Width="360" HorizontalAlignment="Left" Margin="0,0,0,18">
									<ToggleButton Name="BtnSettingsLanguage" Height="30" Padding="10,4" Cursor="Hand"
											HorizontalContentAlignment="Stretch" VerticalContentAlignment="Center"
											Background="$surfaceControl" Foreground="$textPrimary"
											BorderBrush="$controlBorder" BorderThickness="1">
										<ToggleButton.Template>
											<ControlTemplate TargetType="{x:Type ToggleButton}">
												<Border x:Name="LangBtnBorder" CornerRadius="4"
														Background="{TemplateBinding Background}"
														BorderBrush="{TemplateBinding BorderBrush}"
														BorderThickness="{TemplateBinding BorderThickness}"
														Padding="{TemplateBinding Padding}">
													<ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
																	  VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
												</Border>
												<ControlTemplate.Triggers>
													<Trigger Property="IsMouseOver" Value="True">
														<Setter TargetName="LangBtnBorder" Property="Background" Value="$surfaceHover"/>
														<Setter TargetName="LangBtnBorder" Property="BorderBrush" Value="$activeBorder"/>
													</Trigger>
													<Trigger Property="IsChecked" Value="True">
														<Setter TargetName="LangBtnBorder" Property="Background" Value="$surfaceHover"/>
														<Setter TargetName="LangBtnBorder" Property="BorderBrush" Value="$activeBorder"/>
													</Trigger>
												</ControlTemplate.Triggers>
											</ControlTemplate>
										</ToggleButton.Template>
										<Grid>
											<Grid.ColumnDefinitions>
												<ColumnDefinition Width="*"/>
												<ColumnDefinition Width="Auto"/>
											</Grid.ColumnDefinitions>
											<TextBlock Name="TxtSettingsLanguageDisplay" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Left" TextTrimming="CharacterEllipsis" Foreground="$textPrimary" Text=""/>
											<Path Grid.Column="1" Margin="8,0,2,0" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0" Stroke="$textPrimary" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stretch="Fill" Width="8" Height="4" IsHitTestVisible="False"/>
										</Grid>
									</ToggleButton>
									<Popup Name="SettingsLanguagePopup" StaysOpen="True" Placement="Bottom" PlacementTarget="{Binding ElementName=BtnSettingsLanguage}" AllowsTransparency="True" IsOpen="{Binding IsChecked, ElementName=BtnSettingsLanguage, Mode=TwoWay}">
										<Border Background="$cardBg" BorderBrush="$controlBorder" BorderThickness="1" CornerRadius="6" Padding="6">
											<StackPanel Width="360">
												<TextBox Name="TxtSettingsLanguageSearch" Height="28" Padding="10,4" Margin="0,0,0,6" VerticalContentAlignment="Center"
														Background="$surfaceControl" Foreground="$textPrimary"
														BorderBrush="$controlBorder" BorderThickness="1" CaretBrush="$textPrimary"/>
												<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" MaxHeight="320">
													<StackPanel Name="SettingsLanguageListPanel"/>
												</ScrollViewer>
											</StackPanel>
										</Border>
									</Popup>
								</Grid>
								<TextBlock Style="{StaticResource HelperText}" Text="$settingsLanguageHelper"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblDefaultStartupMode" Text="$settingsStartupModeLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbDefaultStartupMode"/>

								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,4,0,18" Opacity="0.35"/>

								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkRestoreLastSession" Content="$settingsRestoreLastSessionLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkAutoScanOnLaunch" Content="$settingsAutoScanOnLaunchLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkHideUnavailableItems" Content="$settingsHideUnavailableLabel"/>

								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,12,0,20" Opacity="0.35"/>

								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsStartupSplashSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsStartupSplashSubtitle"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkStartupRunInitialActions" Content="$settingsStartupRunInitialActionsLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkStartupCheckWinGet" Content="$settingsStartupCheckWinGetLabel"/>
								<TextBlock Style="{StaticResource FieldLabel}" Name="LblStartupWinGetCheckFrequency" Text="$settingsStartupWinGetCheckFrequencyLabel" Margin="22,0,0,4"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbStartupWinGetCheckFrequency" Width="320" HorizontalAlignment="Left" Margin="22,0,0,12"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkStartupCheckChocolatey" Content="$settingsStartupCheckChocolateyLabel"/>
								<TextBlock Style="{StaticResource FieldLabel}" Name="LblStartupChocolateyCheckFrequency" Text="$settingsStartupChocolateyCheckFrequencyLabel" Margin="22,0,0,4"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbStartupChocolateyCheckFrequency" Width="320" HorizontalAlignment="Left" Margin="22,0,0,12"/>
								<TextBlock Style="{StaticResource HelperText}" Text="$settingsStartupSplashHelper" Margin="0,0,0,14"/>

								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,12,0,20" Opacity="0.35"/>

								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsUpdatesSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsUpdatesSubtitle"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkAutoCheckUpdates" Content="$settingsAutoCheckUpdatesLabel"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblUpdateFrequency" Text="$settingsUpdateFrequencyLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbUpdateFrequency"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblUpdateBranch" Text="$settingsUpdateBranchLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbUpdateBranch" Width="520"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkIncludePrereleaseUpdates" Content="$settingsIncludePrereleaseLabel"/>

								<TextBlock Style="{StaticResource HelperText}" Name="TxtUpdatesAutomationHelper" Text="$settingsUpdatesAutomationHelper" Margin="0,0,0,14"/>

								<Grid Margin="0,6,0,20" Width="420" HorizontalAlignment="Left">
									<Grid.ColumnDefinitions>
										<ColumnDefinition Width="150"/>
										<ColumnDefinition Width="*"/>
									</Grid.ColumnDefinitions>
									<Grid.RowDefinitions>
										<RowDefinition Height="Auto"/>
										<RowDefinition Height="Auto"/>
										<RowDefinition Height="Auto"/>
										<RowDefinition Height="Auto"/>
									</Grid.RowDefinitions>
									<TextBlock Grid.Row="0" Grid.Column="0" Style="{StaticResource FieldLabel}" Text="$settingsLastCheckedLabel"/>
									<TextBlock Grid.Row="0" Grid.Column="1" Name="TxtUpdateLastCheckedValue" Foreground="$textPrimary" Margin="0,0,0,6" Text=""/>
									<TextBlock Grid.Row="1" Grid.Column="0" Style="{StaticResource FieldLabel}" Text="$settingsCurrentVersionLabel"/>
									<TextBlock Grid.Row="1" Grid.Column="1" Name="TxtUpdateCurrentVersionValue" Foreground="$textPrimary" Margin="0,0,0,6" Text=""/>
									<TextBlock Grid.Row="2" Grid.Column="0" Style="{StaticResource FieldLabel}" Text="$settingsCurrentBranchLabel"/>
									<TextBlock Grid.Row="2" Grid.Column="1" Name="TxtUpdateBranchValue" Foreground="$textPrimary" Margin="0,0,0,6" Text=""/>
									<TextBlock Grid.Row="3" Grid.Column="0" Style="{StaticResource FieldLabel}" Text="$settingsUpdateStatusLabel"/>
									<TextBlock Grid.Row="3" Grid.Column="1" Name="TxtUpdateStatusValue" Foreground="$textPrimary" Margin="0,0,0,6" Text=""/>
								</Grid>
								<Button Name="BtnSettingsCheckNow" Content="$settingsCheckNowLabel" Width="120" Height="30" Margin="0,8,0,0" HorizontalAlignment="Left" Cursor="Hand"/>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>

				<TabItem Name="TabSettingsAppearance" Header="$appearanceHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsAppearanceSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsAppearanceSubtitle"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblTheme" Text="$settingsThemeLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbTheme"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblUIDensity" Text="$settingsUiDensityLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbUIDensity"/>
								<TextBlock Style="{StaticResource HelperText}" Text="$settingsUiDensityHelper"/>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>

				<TabItem Name="TabSettingsSafety" Header="$safetyHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsRunBehaviorSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsRunBehaviorSubtitle"/>

								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkSafeModeDefault" Content="$settingsSafeModeDefaultLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkRequireRunConfirmation" Content="$settingsRequireRunConfirmationLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkPreviewBeforeRunDefault" Content="$settingsPreviewBeforeRunLabel"/>

								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,12,0,20" Opacity="0.35"/>

								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsAuditRetentionSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsAuditRetentionSubtitle"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblAuditRetention" Text="$settingsAuditRetentionLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbAuditRetention"/>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>

				<TabItem Name="TabSettingsApps" Header="$appsHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsAppsSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsAppsSubtitle"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblPackageSource" Text="$settingsPackageSourceLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbPackageSource"/>
								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,4,0,18" Opacity="0.35"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkAppsSilentInstall" Content="$settingsAppsSilentInstallLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkAppsAutoUpdate" Content="$settingsAppsAutoUpdateLabel"/>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>

				<TabItem Name="TabSettingsLogging" Header="$loggingHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsLoggingSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsLoggingSubtitle"/>

								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkLoggingEnabled" Content="$settingsLoggingEnabledLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkDebugLogging" Content="$settingsDebugLoggingLabel"/>
								<TextBlock Style="{StaticResource HelperText}" Text="$debugExportHint"/>
								<Button Name="BtnSettingsExportSupportBundle" Margin="0,6,0,0" HorizontalAlignment="Left" Padding="0" Background="Transparent" BorderBrush="Transparent" BorderThickness="0" Cursor="Hand">
									<TextBlock FontSize="11" Foreground="$accentBlue" Text="$openExportBundleButtonLabel" TextDecorations="Underline"/>
								</Button>

								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,8,0,20" Opacity="0.35"/>

								<TextBlock Style="{StaticResource FieldLabel}" Name="LblLogLevel" Text="$settingsLogLevelLabel"/>
								<ComboBox Style="{StaticResource SettingsCombo}" Name="CmbLogLevel"/>
								<TextBlock Style="{StaticResource FieldLabel}" Name="LblLogFolderPath" Text="$settingsLogFolderLabel"/>
								<Grid Width="600" HorizontalAlignment="Left" Margin="0,0,0,10">
									<Grid.ColumnDefinitions>
										<ColumnDefinition Width="*"/>
										<ColumnDefinition Width="Auto"/>
									</Grid.ColumnDefinitions>
									<Border Grid.Column="0"
											Background="$surfaceControl"
											BorderBrush="$controlBorder"
											BorderThickness="1"
											CornerRadius="4"
											MinHeight="30"
											Padding="8,6">
										<TextBlock Name="TxtLogFolderPath"
												   Foreground="$textPrimary"
												   TextTrimming="CharacterEllipsis"
												   VerticalAlignment="Center"/>
									</Border>
									<Button Grid.Column="1" Name="BtnLogFolderBrowse" Content="..." Width="36" Height="30" Margin="8,0,0,0" Visibility="Collapsed"/>
								</Grid>
								<StackPanel Orientation="Horizontal" Margin="0,0,0,8">
									<Button Name="BtnOpenLogFolder" Content="$settingsOpenLogFolderLabel" Padding="12,6" Margin="0,0,8,0"/>
									<Button Name="BtnCopyLogFolderPath" Content="$settingsCopyLogFolderPathLabel" Padding="12,6" Margin="0,0,8,0"/>
									<Button Name="BtnClearOldLogs" Content="$settingsClearOldLogsLabel" Padding="12,6"/>
								</StackPanel>
								<TextBlock Style="{StaticResource HelperText}" Name="TxtLogFolderHelper" Text="$settingsLogFolderDefaultHelper"/>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>

				<TabItem Name="TabSettingsAdvanced" Header="$advancedHeading">
					<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Margin="0,8,0,0">
						<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="0">
							<StackPanel Margin="24,20,24,20" MaxWidth="640" HorizontalAlignment="Left">
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsAdvancedSection"/>
								<TextBlock Style="{StaticResource SectionSubtitle}" Text="$settingsAdvancedSubtitle"/>

								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkAdvancedMode" Content="$settingsAdvancedModeLabel"/>
								<CheckBox Style="{StaticResource SettingsCheck}" Name="ChkDesignMode" Content="$settingsDesignModeLabel"/>
								<TextBlock Style="{StaticResource HelperText}" Text="$settingsDesignModeHelper"/>
								<Border Background="$($theme.BorderColor)" Height="1" Margin="0,16,0,18" Opacity="0.35"/>
								<TextBlock Style="{StaticResource SectionHeading}" Text="$settingsStorageCacheSectionXaml"/>
								<TextBlock Name="TxtStorageUsage" FontSize="12" Foreground="$textPrimary" Margin="0,8,0,4"/>
								<TextBlock Name="TxtStorageLocation" FontSize="11" Foreground="$textSecondary" TextTrimming="CharacterEllipsis" Margin="0,0,0,12"/>
								<StackPanel Orientation="Horizontal">
									<Button Name="BtnRefreshStorageUsage" Content="$settingsStorageRefreshLabel" Padding="12,6" Margin="0,0,8,0"/>
									<Button Name="BtnClearCache" Content="$settingsClearCacheLabel" Padding="12,6"/>
								</StackPanel>
							</StackPanel>
						</ScrollViewer>
					</Border>
				</TabItem>
			</TabControl>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="24,14,24,14">
				<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
					<Button Name="BtnCancel" Content="" Padding="22,8" FontSize="13" Margin="0,0,12,0"/>
					<Button Name="BtnSave" Content="" Padding="32,10" FontSize="14" FontWeight="SemiBold"/>
				</StackPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@
