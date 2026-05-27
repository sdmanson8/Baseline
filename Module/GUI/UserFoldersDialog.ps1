# UserFoldersDialog.ps1
#
# Themed WPF dialog for relocating the default user folders (Desktop /
# Documents / Downloads / Music / Pictures / Videos) with a browse picker
# per row. The dialog calls the backend UserFolders command one folder at
# a time so the content move happens before the shell path is redirected.

function Get-GuiUserFoldersEntries
{
	[CmdletBinding()]
	param ()

	$entries = @()
	try
	{
		if (Get-Command -Name 'Get-BaselineUserFolderDefinitions' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$definitions = @(Get-BaselineUserFolderDefinitions)
			foreach ($definition in $definitions)
			{
				if (-not $definition) { continue }
				$currentPath = if (Get-Command -Name 'Get-BaselineUserFolderCurrentPath' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Get-BaselineUserFolderCurrentPath -Folder ([string]$definition.Folder)
				}
				else
				{
					[string]$definition.DefaultPath
				}

				$entries += [pscustomobject]@{
					Folder      = [string]$definition.Folder
					DisplayName = [string]$definition.DisplayName
					CurrentPath = [string]$currentPath
					DefaultPath = [string]$definition.DefaultPath
				}
			}
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'UserFoldersDialog.Enumerate'
		}
		$entries = @()
	}

	return @($entries)
}

function New-GuiUserFoldersEntryRow
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Entry,

		[Parameter(Mandatory = $true)]
		[object]$Theme,

		[Parameter(Mandatory = $true)]
		[object]$BrushConverter,

		[Parameter(Mandatory = $true)]
		[System.Collections.Generic.List[object]]$StateList
	)

	$folderName = [string]$Entry.DisplayName
	$currentPath = [string]$Entry.CurrentPath
	$defaultPath = [string]$Entry.DefaultPath

	$card = New-Object System.Windows.Controls.Border
	$card.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
	$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

	$stack = New-Object System.Windows.Controls.StackPanel
	$stack.Orientation = 'Vertical'
	$card.Child = $stack

	$headerRow = New-Object System.Windows.Controls.StackPanel
	$headerRow.Orientation = 'Horizontal'
	$headerRow.VerticalAlignment = 'Center'
	[void]$stack.Children.Add($headerRow)

	$checkBox = New-Object System.Windows.Controls.CheckBox
	$checkBox.Content = $folderName
	$checkBox.VerticalAlignment = 'Center'
	$checkBox.FontSize = 13
	$checkBox.FontWeight = [System.Windows.FontWeights]::SemiBold
	$checkBox.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
	[void]$headerRow.Children.Add($checkBox)

	$currentPathText = New-Object System.Windows.Controls.TextBlock
	$currentPathText.Text = (Get-UxLocalizedString -Key 'CurrentUserFolderLocation' -Fallback 'The current "{0}" folder location: "{1}".' -FormatArgs @($folderName, $currentPath))
	$currentPathText.TextWrapping = 'Wrap'
	$currentPathText.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
	$currentPathText.VerticalAlignment = 'Center'
	[void]$headerRow.Children.Add($currentPathText)

	$detailsGrid = New-Object System.Windows.Controls.Grid
	$detailsGrid.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
	$detailsGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
	$detailsGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
	$detailsGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
	$detailsGrid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new())
	$detailsGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
	$detailsGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(92)
	$detailsGrid.ColumnDefinitions[2].Width = [System.Windows.GridLength]::new(92)
	$detailsGrid.ColumnDefinitions[3].Width = [System.Windows.GridLength]::new(98)
	[void]$stack.Children.Add($detailsGrid)

	$pathBox = New-Object System.Windows.Controls.TextBox
	$pathBox.IsReadOnly = $true
	$pathBox.IsEnabled = $false
	$pathBox.FontSize = 12
	$pathBox.VerticalContentAlignment = 'Center'
	$pathBox.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$pathBox.Text = ''
	[void][System.Windows.Controls.Grid]::SetColumn($pathBox, 0)
	[void]$detailsGrid.Children.Add($pathBox)

	$browseButton = New-Object System.Windows.Controls.Button
	$browseButton.Content = 'Browse...'
	$browseButton.IsEnabled = $false
	$browseButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	[void][System.Windows.Controls.Grid]::SetColumn($browseButton, 1)
	[void]$detailsGrid.Children.Add($browseButton)

	$defaultButton = New-Object System.Windows.Controls.Button
	$defaultButton.Content = 'Restore default'
	$defaultButton.IsEnabled = $false
	$defaultButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	[void][System.Windows.Controls.Grid]::SetColumn($defaultButton, 2)
	[void]$detailsGrid.Children.Add($defaultButton)

	$statusText = New-Object System.Windows.Controls.TextBlock
	$statusText.Text = 'Not selected'
	$statusText.Foreground = $BrushConverter.ConvertFromString($Theme.TextMuted)
	$statusText.VerticalAlignment = 'Center'
	$statusText.TextTrimming = 'CharacterEllipsis'
	[void][System.Windows.Controls.Grid]::SetColumn($statusText, 3)
	[void]$detailsGrid.Children.Add($statusText)

	$state = [pscustomobject]@{
		Folder      = $folderName
		DisplayName = $folderName
		CurrentPath = $currentPath
		DefaultPath = $defaultPath
		Mode        = $null
		SelectedPath = $null
		Completed   = $false
		CheckBox    = $checkBox
		PathBox     = $pathBox
		BrowseButton = $browseButton
		DefaultButton = $defaultButton
		StatusText  = $statusText
		Card        = $card
	}
	[void]$StateList.Add($state)

	$syncControls = {
		$enabled = [bool]$checkBox.IsChecked -and -not [bool]$state.Completed
		$pathBox.IsEnabled = $enabled
		$browseButton.IsEnabled = $enabled
		$defaultButton.IsEnabled = $enabled
		if (-not $enabled -and -not $state.Completed)
		{
			$statusText.Text = 'Not selected'
			$statusText.Foreground = $BrushConverter.ConvertFromString($Theme.TextMuted)
		}
	}.GetNewClosure()

	$checkBox.Add_Checked({
		$state.Mode = if ($state.Mode) { $state.Mode } else { 'Custom' }
		& $syncControls
	}.GetNewClosure())
	$checkBox.Add_Unchecked({
		if ($state.Completed) { return }
		$state.Mode = $null
		$state.SelectedPath = $null
		$pathBox.Text = ''
		& $syncControls
	}.GetNewClosure())

	$browseButton.Add_Click({
		if (-not $checkBox.IsChecked)
		{
			$checkBox.IsChecked = $true
		}
		if (-not (Get-Command -Name 'Show-GuiFolderPickerDialog' -CommandType Function -ErrorAction SilentlyContinue))
		{
			return
		}

		$initialDirectory = if (-not [string]::IsNullOrWhiteSpace([string]$pathBox.Text) -and (Test-Path -LiteralPath ([string]$pathBox.Text))) {
			[string]$pathBox.Text
		}
		elseif (Test-Path -LiteralPath $state.CurrentPath)
		{
			[string]$state.CurrentPath
		}
		else
		{
			[string]$state.DefaultPath
		}

		$selectedPath = Show-GuiFolderPickerDialog -Description (Get-UxLocalizedString -Key 'FolderSelect' -Fallback 'Select a folder') -InitialDirectory $initialDirectory
		if (-not [string]::IsNullOrWhiteSpace([string]$selectedPath))
		{
			$state.Mode = 'Custom'
			$state.SelectedPath = [string]$selectedPath
			$pathBox.Text = [string]$selectedPath
			$statusText.Text = 'Custom destination selected'
			$statusText.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
			& $syncControls
		}
	}.GetNewClosure())

	$defaultButton.Add_Click({
		if (-not $checkBox.IsChecked)
		{
			$checkBox.IsChecked = $true
		}
		$state.Mode = 'Default'
		$state.SelectedPath = [string]$state.DefaultPath
		$pathBox.Text = [string]$state.DefaultPath
		$statusText.Text = 'Restore default selected'
		$statusText.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
		& $syncControls
	}.GetNewClosure())

	$state.Card = $card
	& $syncControls

	return $card
}

function Show-GuiUserFoldersDialog
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return @{ Cancelled = $true; Changes = @(); Errors = @() }
	}

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'UserFoldersDialog'

	$titleText = 'User Folders'
	$subtitleText = 'Choose a destination for each default user folder. Existing files are moved before the shell path changes. Restore default only updates the registry pointer and never moves files back.'
	$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'
	$applyLabel = 'Apply Selected'
	$emptyLabel = 'No user folders were detected on this system.'

	$rowStates = New-Object 'System.Collections.Generic.List[object]'
	$entries = @(Get-GuiUserFoldersEntries)

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleText"
	Width="920" Height="680"
	MinWidth="760" MinHeight="520"
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
						<TextBlock Name="TxtFooterStatus" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="$($theme.TextMuted)" Text="Ready"/>
						<Button Name="BtnClose" Content="$closeLabel" Padding="20,6" FontSize="13" Margin="0,0,8,0"/>
						<Button Name="BtnApply" Content="$applyLabel" Padding="20,6" FontSize="13"/>
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

	$rowsPanel = $dlg.FindName('RowsPanel')
	$footerStatus = $dlg.FindName('TxtFooterStatus')
	$btnDlgClose = $dlg.FindName('BtnDlgClose')
	$btnClose = $dlg.FindName('BtnClose')
	$btnApply = $dlg.FindName('BtnApply')
	$changeList = New-Object 'System.Collections.Generic.List[object]'
	$errorList = New-Object 'System.Collections.Generic.List[object]'

	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
	if ($btnClose)
	{
		$btnClose.Add_Click({
			$dlg.Tag = [pscustomobject]@{
				Cancelled = ($changeList.Count -eq 0 -and $errorList.Count -eq 0)
				Changes   = @($changeList)
				Errors    = @($errorList)
			}
			$dlg.Close()
		}.GetNewClosure())
	}
	if ($btnApply)
	{
		$btnApply.Add_Click({
			if ($footerStatus) { $footerStatus.Text = 'Applying selected changes...' }
			$hadError = $false
			foreach ($rowState in @($rowStates))
			{
				if (-not $rowState -or $rowState.Completed) { continue }
				if (-not [bool]$rowState.CheckBox.IsChecked) { continue }
				if ([string]::IsNullOrWhiteSpace([string]$rowState.Mode)) { continue }

				try
				{
					$result = if ([string]$rowState.Mode -eq 'Default')
					{
						UserFolders -Folder ([string]$rowState.Folder) -Default
					}
					else
					{
						UserFolders -Folder ([string]$rowState.Folder) -Path ([string]$rowState.SelectedPath)
					}
					[void]$changeList.Add($result)
					$rowState.Completed = $true
					$rowState.CheckBox.IsEnabled = $false
					$rowState.PathBox.IsEnabled = $false
					$rowState.BrowseButton.IsEnabled = $false
					$rowState.DefaultButton.IsEnabled = $false
					$rowState.Card.Opacity = 0.74
					$rowState.StatusText.Text = 'Applied'
					$rowState.StatusText.Foreground = $bc.ConvertFromString('#2E7D32')
				}
				catch
				{
					$hadError = $true
					[void]$errorList.Add([pscustomobject]@{
						Folder = [string]$rowState.Folder
						Error  = $_.Exception.Message
					})
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
					{
						Write-SwallowedException -ErrorRecord $_ -Source 'UserFoldersDialog.Apply'
					}
					$rowState.StatusText.Text = ('Failed: {0}' -f $_.Exception.Message)
					$rowState.StatusText.Foreground = $bc.ConvertFromString('#D13438')
				}
			}

			if ($footerStatus)
			{
				if ($hadError)
				{
					$footerStatus.Text = 'Completed with errors.'
				}
				elseif ($changeList.Count -gt 0)
				{
					$footerStatus.Text = 'Applied.'
				}
				else
				{
					$footerStatus.Text = 'No changes selected.'
				}
			}

			if (-not $hadError -and $changeList.Count -gt 0)
			{
				$dlg.Tag = [pscustomobject]@{
					Cancelled = $false
					Changes   = @($changeList)
					Errors    = @($errorList)
				}
				$dlg.DialogResult = $true
				$dlg.Close()
			}
		}.GetNewClosure())
	}

	$rows = @($entries)
	if ($rows.Count -eq 0)
	{
		$emptyText = New-Object System.Windows.Controls.TextBlock
		$emptyText.Text = $emptyLabel
		$emptyText.Foreground = $bc.ConvertFromString($theme.TextMuted)
		$emptyText.TextWrapping = 'Wrap'
		$emptyText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
		[void]$rowsPanel.Children.Add($emptyText)
	}
	else
	{
		foreach ($entry in $rows)
		{
			$rowCard = New-GuiUserFoldersEntryRow -Entry $entry -Theme $theme -BrushConverter $bc -StateList $rowStates
			[void]$rowsPanel.Children.Add($rowCard)
		}
	}

	$result = $dlg.ShowDialog()
	if ($dlg.Tag -is [pscustomobject])
	{
		return @{
			Cancelled = [bool]$dlg.Tag.Cancelled
			Changes   = @($dlg.Tag.Changes)
			Errors    = @($dlg.Tag.Errors)
		}
	}

	return @{
		Cancelled = ($result -ne $true)
		Changes   = @()
		Errors    = @()
	}
}
