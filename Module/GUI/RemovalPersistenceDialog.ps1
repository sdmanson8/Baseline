# RemovalPersistenceDialog.ps1
#
# Themed WPF dialog that surfaces removal-script persistence tasks
# registered under \Baseline\Persistence\ by the back-end at
# Module/SharedHelpers/RemovalPersistence.Helpers.ps1. Lets the user
# review which removal scripts are scheduled to re-run after Windows
# feature updates and remove individual entries when no longer wanted.
#
# Public surface:
#   * Show-GuiRemovalPersistenceDialog
#       Returns @{ Cancelled = [bool]; Removed = @( <name>, ... ) }.
#       Cancelled=$true when the user closes via Cancel / Esc / X. Removed
#       lists names the user removed in this session.
#
# Headless harness: when $Script:CurrentTheme is unset (test runner /
# unattended host) the dialog short-circuits and returns Cancelled=$true
# with an empty Removed list. Adding new persistence entries lives with
# the per-removal "Persist removal" toggle UX (separate slice) — this
# dialog only reviews / removes existing entries.

function Show-GuiRemovalPersistenceDialog
{
	<#
		.SYNOPSIS
		Themed WPF dialog for reviewing and removing persisted removal
		scripts (Baseline\Persistence\<Name> scheduled tasks).

		.DESCRIPTION
		Backed by Get-BaselineRemovalPersistenceTasks /
		Unregister-BaselineRemovalPersistenceTask. Per-row "Remove" button
		runs the unregister synchronously and refreshes the row state so a
		hard close still preserves the change. Returns
		@{ Cancelled = [bool]; Removed = @(...) }.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return @{ Cancelled = $true; Removed = @() }
	}

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'RemovalPersistenceDialog'

	$titleText      = Get-UxLocalizedString -Key 'GuiRemovalPersistenceTitle'    -Fallback 'Removal Persistence'
	$subtitleText   = Get-UxLocalizedString -Key 'GuiRemovalPersistenceSubtitle' -Fallback 'Review and remove scheduled tasks under \\Baseline\\Persistence\\ that re-run removal scripts after Windows feature updates re-add removed components.'
	$closeLabel     = Get-UxLocalizedString -Key 'GuiCloseButton'                -Fallback 'Close'
	$emptyLabel     = Get-UxLocalizedString -Key 'GuiRemovalPersistenceEmpty'    -Fallback 'No removal-persistence tasks are registered. Toggle "Persist removal" on a removal entry to add one.'
	$removeLabel    = Get-UxLocalizedString -Key 'GuiRemovalPersistenceRemove'   -Fallback 'Remove'
	$missingLabel   = Get-UxLocalizedString -Key 'GuiRemovalPersistenceMissing'  -Fallback 'Script file is missing — task will fail on next trigger.'
	$failedRemoveFmt = Get-UxLocalizedString -Key 'GuiRemovalPersistenceRemoveFailed' -Fallback 'Failed to remove ''{0}''.'

	$entries = @()
	try
	{
		if (Get-Command -Name 'Get-BaselineRemovalPersistenceTasks' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$entries = @(Get-BaselineRemovalPersistenceTasks)
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'RemovalPersistenceDialog.Enumerate'
		}
		$entries = @()
	}

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleText"
	Width="780" Height="600"
	MinWidth="640" MinHeight="440"
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
					<TextBlock Text="$titleText" VerticalAlignment="Center" FontSize="12" Foreground="$($theme.TextPrimary)"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$($theme.TextPrimary)" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<Border Grid.Row="1" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
					Padding="20,14,20,14">
				<StackPanel>
					<TextBlock Text="$titleText" FontSize="16" FontWeight="SemiBold" Foreground="$($theme.TextPrimary)"/>
					<TextBlock Text="$subtitleText" FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0" TextWrapping="Wrap"/>
				</StackPanel>
			</Border>

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,16,20,16">
				<StackPanel Name="RowsPanel" Orientation="Vertical"/>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
						<Button Name="BtnClose" Content="$closeLabel" Padding="20,6" FontSize="13"/>
					</StackPanel>
				</Grid>
			</Border>
		</Grid>
	</Border>
</Window>
"@

	$reader = [System.Xml.XmlNodeReader]::new($xaml)
	$dlg = [Windows.Markup.XamlReader]::Load($reader)
	if ($Script:MainForm) { $dlg.Owner = $Script:MainForm }

	$rootBorder = $dlg.FindName('RootBorder')
	if ($rootBorder)
	{
		$rootBorder.Background = $bc.ConvertFromString($theme.WindowBg)
		$rootBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
		$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	}
	if (Get-Command -Name 'GUICommon\Set-GuiWindowChromeTheme' -ErrorAction SilentlyContinue)
	{
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
	}

	$dlgTitleBar = $dlg.FindName('DlgTitleBar')
	$btnDlgClose = $dlg.FindName('BtnDlgClose')
	$btnClose = $dlg.FindName('BtnClose')
	$rowsPanel = $dlg.FindName('RowsPanel')

	if ($dlgTitleBar)
	{
		$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
	}
	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
	if ($btnClose)
	{
		$btnClose.IsCancel = $true
		$btnClose.Add_Click({ $dlg.Close() }.GetNewClosure())
	}

	$state = @{
		Cancelled = $false
		Removed   = New-Object System.Collections.Generic.List[string]
	}

	if (@($entries).Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = $emptyLabel
		$emptyBlock.FontSize = 12
		$emptyBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
		[void]($rowsPanel.Children.Add($emptyBlock))
	}
	else
	{
		foreach ($entry in @($entries))
		{
			$rowBorder = New-Object System.Windows.Controls.Border
			$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
			$rowBorder.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
			$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
			$rowBorder.Background = $bc.ConvertFromString($theme.HeaderBg)
			$rowBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)

			$rowGrid = New-Object System.Windows.Controls.Grid
			$colMain = New-Object System.Windows.Controls.ColumnDefinition
			$colMain.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			$colAction = New-Object System.Windows.Controls.ColumnDefinition
			$colAction.Width = [System.Windows.GridLength]::new(96)
			[void]$rowGrid.ColumnDefinitions.Add($colMain)
			[void]$rowGrid.ColumnDefinitions.Add($colAction)

			$mainStack = New-Object System.Windows.Controls.StackPanel
			$mainStack.Orientation = 'Vertical'
			[System.Windows.Controls.Grid]::SetColumn($mainStack, 0)

			$nameBlock = New-Object System.Windows.Controls.TextBlock
			$nameBlock.Text = ('{0}  ·  {1}' -f [string]$entry.TaskName, [string]$entry.State)
			$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$nameBlock.FontSize = 13
			$nameBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			[void]$mainStack.Children.Add($nameBlock)

			$pathBlock = New-Object System.Windows.Controls.TextBlock
			$pathBlock.Text = [string]$entry.ScriptPath
			$pathBlock.FontSize = 11
			$pathBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$pathBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
			$pathBlock.TextWrapping = 'Wrap'
			[void]$mainStack.Children.Add($pathBlock)

			if (-not [bool]$entry.ScriptExists)
			{
				$missingBlock = New-Object System.Windows.Controls.TextBlock
				$missingBlock.Text = $missingLabel
				$missingBlock.FontSize = 10
				$missingBlock.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$missingBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
				$missingBlock.TextWrapping = 'Wrap'
				[void]$mainStack.Children.Add($missingBlock)
			}

			if (-not [string]::IsNullOrWhiteSpace([string]$entry.Description))
			{
				$descBlock = New-Object System.Windows.Controls.TextBlock
				$descBlock.Text = [string]$entry.Description
				$descBlock.FontSize = 10
				$descBlock.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$descBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
				$descBlock.TextWrapping = 'Wrap'
				[void]$mainStack.Children.Add($descBlock)
			}

			[void]$rowGrid.Children.Add($mainStack)

			$btnRemove = New-Object System.Windows.Controls.Button
			$btnRemove.Content = $removeLabel
			$btnRemove.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
			$btnRemove.VerticalAlignment = 'Center'
			$btnRemove.HorizontalAlignment = 'Right'
			[System.Windows.Controls.Grid]::SetColumn($btnRemove, 1)
			[void]$rowGrid.Children.Add($btnRemove)

			$rowBorder.Child = $rowGrid
			[void]($rowsPanel.Children.Add($rowBorder))

			$entryRef = $entry
			$rowBorderRef = $rowBorder
			$btnRef = $btnRemove
			$removedList = $state.Removed
			$failFmtRef = $failedRemoveFmt
			$btnRemove.Add_Click({
				$btnRef.IsEnabled = $false
				$ok = $false
				try
				{
					$ok = [bool](Unregister-BaselineRemovalPersistenceTask -Name ([string]$entryRef.TaskName) -RemoveScript)
				}
				catch
				{
					$ok = $false
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'RemovalPersistenceDialog.Unregister'
					}
				}
				if (-not $ok)
				{
					$btnRef.IsEnabled = $true
					if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
					{
						LogWarning ($failFmtRef -f [string]$entryRef.TaskName)
					}
					return
				}
				# Mark the row visually as removed without rebuilding the panel.
				$rowBorderRef.Opacity = 0.5
				$removedList.Add([string]$entryRef.TaskName) | Out-Null
			}.GetNewClosure())
		}
	}

	$dlg.Add_KeyDown({
		$eventArgs = $args[1]
		if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
	})

	[void]($dlg.ShowDialog())

	return @{
		Cancelled = [bool]$state.Cancelled
		Removed   = @($state.Removed.ToArray())
	}
}
