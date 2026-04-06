# Dialog helper functions: risk decision, help, and log viewer dialogs

	function Show-RiskDecisionDialog
	{
		param(
			[string]$Title = 'Warning',
			[string]$Message,
			[object[]]$SummaryCards = @(),
			[string[]]$Buttons = @('Cancel', 'Continue Anyway'),
			[string]$AccentButton = $null,
			[string]$DestructiveButton = $null
		)

		return (GUICommon\Show-RiskDecisionDialog `
			-Theme $Script:CurrentTheme `
			-ApplyButtonChrome ${function:Set-ButtonChrome} `
			-OwnerWindow $Form `
			-Title $Title `
			-Message $Message `
			-SummaryCards $SummaryCards `
			-Buttons $Buttons `
			-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
			-AccentButton $AccentButton `
			-DestructiveButton $DestructiveButton)
	}

	function Show-HelpDialog
	{
		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-AboutPanel'
		$helpDialogTitle = Get-UxHelpDialogTitle
		$helpDialogSubtitle = Get-UxHelpDialogSubtitle

		$sections = Get-UxHelpSections
		if ($null -eq $sections)
		{
			$sections = [ordered]@{
				'Start Guide' = @(Get-UxQuickStartSteps)
				'Undo and Restore' = @(Get-UxUndoAndRestoreLines)
				'Import / Export' = @(Get-UxImportExportLines)
			}
		}

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$helpDialogTitle"
	Width="$($Script:GuiLayout.HelpDialogWidth)" Height="$($Script:GuiLayout.HelpDialogHeight)"
	MinWidth="$($Script:GuiLayout.HelpDialogMinWidth)" MinHeight="$($Script:GuiLayout.HelpDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border CornerRadius="8" Background="$($theme.WindowBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1">
	<Border.Resources>
		<Style TargetType="ScrollBar">
			<Setter Property="Background" Value="$($theme.ScrollBg)"/>
			<Setter Property="Width" Value="6"/>
		</Style>
	</Border.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Text="$helpDialogTitle" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="&#xE106;" FontFamily="Segoe MDL2 Assets" FontSize="10" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<StackPanel>
				<TextBlock Text="$helpDialogTitle" FontSize="16" FontWeight="SemiBold"
						   Foreground="$($theme.TextPrimary)"/>
				<TextBlock Text="$helpDialogSubtitle"
						   FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0"/>
			</StackPanel>
		</Border>

		<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Disabled"
					  Padding="0,0,4,0">
			<StackPanel Name="ContentPanel" Margin="20,16,20,16"/>
		</ScrollViewer>

		<Border Grid.Row="3" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Button Name="BtnClose" Content="Close"
						HorizontalAlignment="Right"
						Padding="20,6" FontSize="13"/>
			</Grid>
		</Border>
	</Grid>
	</Border>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		# Wire help dialog title bar
		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		if ($dlgTitleBar) { $dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$panel = $dlg.FindName('ContentPanel')
		$btnClose = $dlg.FindName('BtnClose')

		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		$btnClose.IsDefault = $true
		$btnClose.IsCancel = $true

		foreach ($sectionTitle in $sections.Keys)
		{
			$heading = [System.Windows.Controls.TextBlock]::new()
			$heading.Text = $sectionTitle
			$heading.FontSize = $Script:GuiLayout.FontSizeSubheading
			$heading.FontWeight = [System.Windows.FontWeights]::SemiBold
			$heading.Foreground = $bc.ConvertFromString($theme.AccentBlue)
			$heading.Margin = [System.Windows.Thickness]::new(0, 12, 0, 4)
			[void]($panel.Children.Add($heading))
			$sep = [System.Windows.Controls.Separator]::new()
			$sep.Background = $bc.ConvertFromString($theme.BorderColor)
			$sep.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
			[void]($panel.Children.Add($sep))
			foreach ($line in $sections[$sectionTitle])
			{
				$row = [System.Windows.Controls.Grid]::new()
				$col1 = [System.Windows.Controls.ColumnDefinition]::new()
				$col1.Width = [System.Windows.GridLength]::new(14)
				$col2 = [System.Windows.Controls.ColumnDefinition]::new()
				$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				[void]($row.ColumnDefinitions.Add($col1))
				[void]($row.ColumnDefinitions.Add($col2))
				$row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

				$bullet = [System.Windows.Controls.TextBlock]::new()
				$bullet.Text = [char]0x2022
				$bullet.FontSize = $Script:GuiLayout.FontSizeSubheading
				$bullet.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$bullet.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
				[System.Windows.Controls.Grid]::SetColumn($bullet, 0)

				$text = [System.Windows.Controls.TextBlock]::new()
				$text.Text = $line
				$text.FontSize = $Script:GuiLayout.FontSizeSubheading
				$text.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				$text.TextWrapping = [System.Windows.TextWrapping]::Wrap
				[System.Windows.Controls.Grid]::SetColumn($text, 1)

				[void]($row.Children.Add($bullet))
				[void]($row.Children.Add($text))
				[void]($panel.Children.Add($row))
			}
		}

		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void]($dlg.ShowDialog())
	}

	function Show-FirstRunWelcomeDialog
	{
		param (
			[string]$RecommendedPreset,
			[string]$PrimaryActionLabel,
			[string]$WelcomeMessage,
			[string]$DialogTitle,
			[object]$ShowThemedDialogCapture,
			[scriptblock]$OpenHelpAction,
			[scriptblock]$ChooseRecommendedPresetAction,
			[hashtable]$Theme,
			[scriptblock]$ApplyButtonChrome,
			[object]$OwnerWindow,
			[bool]$UseDarkMode = $true
		)

		$chooseButton = if ([string]::IsNullOrWhiteSpace($PrimaryActionLabel)) { "Start with $RecommendedPreset" } else { $PrimaryActionLabel }
		$resolvedTitle = if ([string]::IsNullOrWhiteSpace($DialogTitle)) { 'Welcome to Baseline' } else { $DialogTitle }
		$choice = & $ShowThemedDialogCapture -Title $resolvedTitle `
			-Message $WelcomeMessage `
			-Buttons @('Close', 'Open Help', $chooseButton) `
			-AccentButton $chooseButton `
			-Theme $Theme `
			-ApplyButtonChrome $ApplyButtonChrome `
			-OwnerWindow $OwnerWindow `
			-UseDarkMode $UseDarkMode

		switch ($choice)
		{
			'Open Help'
			{
				if ($OpenHelpAction) { & $OpenHelpAction }
				break
			}
			default
			{
				if ($choice -eq $chooseButton -and $ChooseRecommendedPresetAction)
				{
					& $ChooseRecommendedPresetAction
				}
				break
			}
		}

		return $choice
	}

	function Show-LogDialog
	{
		param([string]$LogPath)

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'DialogHelpers-PresetWarning'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Log Viewer"
	Width="$($Script:GuiLayout.LogDialogWidth)" Height="$($Script:GuiLayout.LogDialogHeight)"
	MinWidth="$($Script:GuiLayout.LogDialogMinWidth)" MinHeight="$($Script:GuiLayout.LogDialogMinHeight)"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResizeWithGrip"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border CornerRadius="8" Background="$($theme.WindowBg)" BorderBrush="$($theme.BorderColor)" BorderThickness="1">
	<Border.Resources>
		<Style TargetType="ScrollBar">
			<Setter Property="Background" Value="$($theme.ScrollBg)"/>
			<Setter Property="Width" Value="6"/>
		</Style>
	</Border.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Name="DlgTitleBar" Grid.Row="0" Background="$($theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Text="Log Viewer" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
				<Button Name="BtnDlgClose" Content="&#xE106;" FontFamily="Segoe MDL2 Assets" FontSize="10" Width="32" Height="28"
					Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
					HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
			</Grid>
		</Border>

		<Border Grid.Row="1" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0">
					<TextBlock Text="Log Viewer" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtLogPath" FontSize="11"
							   Foreground="$($theme.TextMuted)" Margin="0,2,0,0"
							   TextTrimming="CharacterEllipsis"/>
				</StackPanel>
				<StackPanel Grid.Column="1" Orientation="Horizontal"
							VerticalAlignment="Center" HorizontalAlignment="Right">
					<Button Name="BtnRefresh" Content="Refresh" Margin="0,0,8,0"
							Padding="12,5" FontSize="12"/>
					<Button Name="BtnOpenExternal" Content="Open in Notepad"
							Padding="12,5" FontSize="12"/>
				</StackPanel>
			</Grid>
		</Border>

		<ScrollViewer Name="LogScroll" Grid.Row="2"
					  VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Auto"
					  Background="$($theme.SearchBg)"
					  Padding="0,0,4,0">
			<StackPanel Name="LogPanel" Margin="16,12,16,12"/>
		</ScrollViewer>

		<Border Grid.Row="3" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
					<Ellipse Width="8" Height="8" Fill="$($theme.LowRiskBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="success" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskHighBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="failed" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskMediumBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="skipped / warning" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.TextMuted)" Margin="0,0,5,0"/>
					<TextBlock Text="info" FontSize="11" Foreground="$($theme.TextMuted)"/>
				</StackPanel>
				<Button Name="BtnClose" Grid.Column="1" Content="Close"
						Padding="20,6" FontSize="13"/>
			</Grid>
		</Border>
	</Grid>
	</Border>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		# Wire log dialog title bar
		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		if ($dlgTitleBar) { $dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$logPanel = $dlg.FindName('LogPanel')
		$logScroll = $dlg.FindName('LogScroll')
		$txtLogPath = $dlg.FindName('TxtLogPath')
		$btnClose = $dlg.FindName('BtnClose')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnExternal = $dlg.FindName('BtnOpenExternal')

		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		Set-ButtonChrome -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
		Set-ButtonChrome -Button $btnExternal -Variant 'Subtle' -Compact -Muted
		$btnClose.IsCancel = $true

		$txtLogPath.Text = $LogPath

		$colorRules = @(
			@{ Pattern = '- success[!]?$';          Color = $theme.LowRiskBadge    }
			@{ Pattern = '- failed[!]?$';           Color = $theme.RiskHighBadge   }
			@{ Pattern = '- skipped[.]?$';          Color = $theme.RiskMediumBadge }
			@{ Pattern = '- already applied[.]?$';  Color = $theme.AccentBlue      }
			@{ Pattern = '\bERROR\b|\bFAIL\b';      Color = $theme.RiskHighBadge   }
			@{ Pattern = '\bWARN\b|\bWARNING\b';    Color = $theme.RiskMediumBadge }
			@{ Pattern = '^={3}';                   Color = $theme.AccentBlue      }
		)

		$logFontSizeLabel = $Script:GuiLayout.FontSizeLabel
		$logFontSizeSubheading = $Script:GuiLayout.FontSizeSubheading
		$loadLogContent = {
			$logPanel.Children.Clear()

			if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = "Log file not found:`n$LogPath"
				$tb.FontSize = $logFontSizeSubheading
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				[void]($logPanel.Children.Add($tb))
				return
			}

			try
			{
				$lines = [System.IO.File]::ReadAllLines($LogPath)
			}
			catch
			{
				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = "Failed to read log file: $($_.Exception.Message)"
				$tb.FontSize = $logFontSizeSubheading
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				[void]($logPanel.Children.Add($tb))
				return
			}

			foreach ($line in $lines)
			{
				$color = $theme.TextSecondary
				foreach ($rule in $colorRules)
				{
					if ($line -match $rule.Pattern)
					{
						$color = $rule.Color
						break
					}
				}

				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = $line
				$tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas, Courier New')
				$tb.FontSize = $logFontSizeLabel
				$tb.Foreground = $bc.ConvertFromString($color)
				$tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
				$tb.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
				[void]($logPanel.Children.Add($tb))
			}

			$logScroll.ScrollToEnd()
		}.GetNewClosure()

		& $loadLogContent

		Register-GuiEventHandler -Source $btnClose -EventName 'Click' -Handler { $dlg.Close() }
		Register-GuiEventHandler -Source $btnRefresh -EventName 'Click' -Handler ({
			& $loadLogContent
			$txtLogPath.Text = $LogPath
		}.GetNewClosure())
		Register-GuiEventHandler -Source $btnExternal -EventName 'Click' -Handler ({
			if ($LogPath -and (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				Start-Process -FilePath 'notepad.exe' -ArgumentList $LogPath -ErrorAction SilentlyContinue
			}
		}.GetNewClosure())
		Register-GuiEventHandler -Source $dlg -EventName 'KeyDown' -Handler {
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		}

		[void]($dlg.ShowDialog())
	}
	#endregion Themed Dialog

