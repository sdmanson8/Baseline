# StartupManagerDialog.ps1
#
# Themed WPF dialog and Customizations-tab surface for the Startup-folder /
# Run-key enumerator and per-entry enable / disable primitives from
# Module/Regions/SystemTweaks/SystemTweaks.Startup.psm1. Equivalent to
# Task Manager's Startup tab: lists every Run / RunOnce / Startup-folder
# entry on the box, lets the user flip the StartupApproved bit per entry
# without ever deleting the underlying Run value.
#
# Public surface:
#   * Show-GuiStartupManagerDialog
#       Returns @{ Cancelled = [bool]; Changes = @( @{ EntryId; Enabled } ) }.
#       Cancelled=$true when the user closes via Cancel / Esc / X. Changes
#       lists entries the user toggled in this session (so callers can log
#       a summary, drive Restore-defaults later, etc.). Enable / Disable
#       happens on click — a per-entry checkbox round-trips through
#       Set-BaselineStartupEntryEnabled immediately, so a hard close
#       preserves the user's edits.
#
# Headless harness: when $Script:CurrentTheme is unset (test runner /
# unattended host) the dialog short-circuits and returns Cancelled=$true
# with an empty Changes list. RunOnce entries lack a StartupApproved key
# (per upstream Windows design) and render disabled - toggling them is a
# no-op rather than an error.

function Get-GuiStartupManagerEntries
{
	<#
		.SYNOPSIS
		Pure enumerator for startup entries used by the dialog and the
		Customizations tab.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject[]])]
	param ()

	$entries = @()
	try
	{
		if (Get-Command -Name 'Get-BaselineStartupEntries' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$entries = @(Get-BaselineStartupEntries)
		}
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'StartupManagerDialog.Enumerate'
		}
		$entries = @()
	}

	return @($entries)
}

function New-GuiStartupManagerEntryRow
{
	<#
		.SYNOPSIS
		Builds one flat startup-entry row.
	#>
	[CmdletBinding()]
	[OutputType([System.Windows.Controls.Border])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Entry,

		[Parameter(Mandatory = $true)]
		[object]$BrushConverter,

		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[System.Collections.Generic.List[object]]$ChangeList,

		[string]$RunOnceLabel = (Get-UxLocalizedString -Key 'GuiStartupManagerRunOnceNote' -Fallback 'RunOnce entry - not toggleable (Windows clears these on first run).'),
		[string]$FailedToggleFmt = (Get-UxLocalizedString -Key 'GuiStartupManagerToggleFailed' -Fallback 'Failed to toggle ''{0}''.')
	)

	$rowBorder = New-Object System.Windows.Controls.Border
	$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
	$rowBorder.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
	$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
	$rowBorder.Background = $BrushConverter.ConvertFromString($Theme.HeaderBg)
	$rowBorder.BorderBrush = $BrushConverter.ConvertFromString($Theme.BorderColor)
	$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)

	$rowGrid = New-Object System.Windows.Controls.Grid
	$colCheck = New-Object System.Windows.Controls.ColumnDefinition
	$colCheck.Width = [System.Windows.GridLength]::new(28)
	$colMain = New-Object System.Windows.Controls.ColumnDefinition
	$colMain.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
	[void]$rowGrid.ColumnDefinitions.Add($colCheck)
	[void]$rowGrid.ColumnDefinitions.Add($colMain)

	$cb = New-Object System.Windows.Controls.CheckBox
	$cb.VerticalAlignment = 'Center'
	$cb.IsChecked = [bool]$Entry.Enabled
	[System.Windows.Controls.Grid]::SetColumn($cb, 0)

	# RunOnce entries cannot be toggled via StartupApproved (no key exists for
	# them). Render them read-only so the UI never silently fails.
	$isToggleable = (-not [bool]$Entry.IsRunOnce) -and (-not [string]::IsNullOrWhiteSpace([string]$Entry.ApprovedKey))
	if (-not $isToggleable)
	{
		$cb.IsEnabled = $false
	}
	[void]$rowGrid.Children.Add($cb)

	$mainStack = New-Object System.Windows.Controls.StackPanel
	$mainStack.Orientation = 'Vertical'
	[System.Windows.Controls.Grid]::SetColumn($mainStack, 1)

	$nameBlock = New-Object System.Windows.Controls.TextBlock
	$nameBlock.Text = [string]$Entry.Name
	$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
	$nameBlock.FontSize = 13
	$nameBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextPrimary)
	[void]$mainStack.Children.Add($nameBlock)

	$metaParts = [System.Collections.Generic.List[string]]::new()
	if (-not [string]::IsNullOrWhiteSpace([string]$Entry.Source))
	{
		[void]$metaParts.Add(("Source: {0}" -f [string]$Entry.Source))
	}
	if (-not [string]::IsNullOrWhiteSpace([string]$Entry.Scope))
	{
		[void]$metaParts.Add(("Scope: {0}" -f [string]$Entry.Scope))
	}
	if ($metaParts.Count -gt 0)
	{
		$metaBlock = New-Object System.Windows.Controls.TextBlock
		$metaBlock.Text = [string]::Join('  •  ', @($metaParts))
		$metaBlock.FontSize = 10
		$metaBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextMuted)
		$metaBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		$metaBlock.TextWrapping = 'Wrap'
		[void]$mainStack.Children.Add($metaBlock)
	}

	$cmdBlock = New-Object System.Windows.Controls.TextBlock
	$cmdBlock.Text = [string]$Entry.Command
	$cmdBlock.FontSize = 11
	$cmdBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
	$cmdBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
	$cmdBlock.TextWrapping = 'Wrap'
	[void]$mainStack.Children.Add($cmdBlock)

	if (-not $isToggleable)
	{
		$noteBlock = New-Object System.Windows.Controls.TextBlock
		$noteBlock.Text = if ([bool]$Entry.IsRunOnce) { $RunOnceLabel } else { 'StartupApproved key unavailable - not toggleable.' }
		$noteBlock.FontSize = 10
		$noteBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextMuted)
		$noteBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		$noteBlock.TextWrapping = 'Wrap'
		[void]$mainStack.Children.Add($noteBlock)
	}

	[void]$rowGrid.Children.Add($mainStack)
	$rowBorder.Child = $rowGrid

	if ($isToggleable)
	{
		$entryRef = $Entry
		$cbRef = $cb
		$changeListRef = $ChangeList
		$failFmtRef = $FailedToggleFmt
		$cb.Add_Click({
			$desired = [bool]$cbRef.IsChecked
			$ok = $false
			try
			{
				if ($desired)
				{
					$ok = [bool](Set-BaselineStartupEntryEnabled -EntryId ([string]$entryRef.EntryId) -Enable)
				}
				else
				{
					$ok = [bool](Set-BaselineStartupEntryEnabled -EntryId ([string]$entryRef.EntryId) -Disable)
				}
			}
			catch
			{
				$ok = $false
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'StartupManagerDialog.Toggle'
				}
			}
			if (-not $ok)
			{
				# Snap back so the UI doesn't lie about state on a failed write.
				$cbRef.IsChecked = -not $desired
				if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
				{
					LogWarning ($failFmtRef -f [string]$entryRef.Name)
				}
				return
			}
			if ($null -ne $changeListRef)
			{
				$changeListRef.Add([pscustomobject]@{
					EntryId = [string]$entryRef.EntryId
					Enabled = $desired
				}) | Out-Null
			}
		}.GetNewClosure())
	}

	return $rowBorder
}

function Add-GuiStartupManagerRowsToPanel
{
	<#
		.SYNOPSIS
		Appends flat startup rows to a panel.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.Panel]$Panel,

		[object[]]$Entries,

		[Parameter(Mandatory = $true)]
		[object]$BrushConverter,

		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[System.Collections.Generic.List[object]]$ChangeList,

		[string]$EmptyLabel = (Get-UxLocalizedString -Key 'GuiStartupManagerEmpty' -Fallback 'No startup entries detected on this system.'),
		[string]$RunOnceLabel = (Get-UxLocalizedString -Key 'GuiStartupManagerRunOnceNote' -Fallback 'RunOnce entry - not toggleable (Windows clears these on first run).'),
		[string]$FailedToggleFmt = (Get-UxLocalizedString -Key 'GuiStartupManagerToggleFailed' -Fallback 'Failed to toggle ''{0}''.')
	)

	if (-not $Panel) { return }

	if ($null -eq $Entries -or @($Entries).Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = $EmptyLabel
		$emptyBlock.FontSize = 12
		$emptyBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
		[void]($Panel.Children.Add($emptyBlock))
		return
	}

	foreach ($entry in @($Entries))
	{
		[void]($Panel.Children.Add((New-GuiStartupManagerEntryRow -Entry $entry -BrushConverter $BrushConverter -Theme $Theme -ChangeList $ChangeList -RunOnceLabel $RunOnceLabel -FailedToggleFmt $FailedToggleFmt)))
	}
}

function Invoke-GuiCustomizationsStartupManagerAction
{
	[CmdletBinding()]
	param ()

	if (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if (Test-GuiRunInProgress) { return }
	}

	try
	{
		$startupManagerDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiStartupManagerDialog' -CommandType 'Function'
		if (-not $startupManagerDialogCommand)
		{
			throw 'Startup Manager dialog command is not available.'
		}
		$null = & $startupManagerDialogCommand
	}
	catch
	{
		LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to open Startup Manager')
		[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiStartupManagerTitle' -Fallback 'Startup Manager') -Message ("Failed to open Startup Manager.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Invoke-GuiCustomizationsUserFoldersAction
{
	[CmdletBinding()]
	param ()

	if (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if (Test-GuiRunInProgress) { return }
	}

	try
	{
		$userFoldersDialogCommand = Get-GuiRuntimeCommand -Name 'Show-GuiUserFoldersDialog' -CommandType 'Function'
		if (-not $userFoldersDialogCommand)
		{
			throw 'User Folders dialog command is not available.'
		}
		$null = & $userFoldersDialogCommand
	}
	catch
	{
		LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'Failed to open user folders')
		[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiUserFoldersTitle' -Fallback 'User Folders') -Message ("Failed to open user folders.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function Invoke-GuiCustomizationsWslInstallAction
{
	[CmdletBinding()]
	param ()

	if (Get-Command -Name 'Test-GuiRunInProgress' -CommandType Function -ErrorAction SilentlyContinue)
	{
		if (Test-GuiRunInProgress) { return }
	}

	try
	{
		$showWslInstallDialogCommand = Get-GuiRuntimeCommand -Name 'Show-WslInstallDialog' -CommandType 'Function'
		$invokeWslInstallFlowCommand = Get-GuiRuntimeCommand -Name 'Invoke-BaselineWslInstallFlow' -CommandType 'Function'
		if (-not $showWslInstallDialogCommand -or -not $invokeWslInstallFlowCommand)
		{
			throw 'WSL install helpers are not available.'
		}

		$selectedDistro = & $showWslInstallDialogCommand
		if (-not $selectedDistro) { return }
		$alias = if ($selectedDistro.PSObject.Properties.Name -contains 'Alias') { [string]$selectedDistro.Alias } else { [string]$selectedDistro }
		$label = if ($selectedDistro.PSObject.Properties.Name -contains 'Distribution') { [string]$selectedDistro.Distribution } else { $alias }
		$result = & $invokeWslInstallFlowCommand -Alias $alias

		if ($result -and $result.Succeeded)
		{
			LogInfo ("WSL install flow completed for {0}." -f $label)
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiWslInstallTitle' -Fallback 'Install WSL') -Message ("Installed {0} and completed the post-install WSL update steps." -f $label) -Buttons @('OK') -AccentButton 'OK')
		}
		else
		{
			$failureReason = if ($result -and $result.Reason) { [string]$result.Reason } else { 'Unknown failure.' }
			LogError ("WSL install flow failed for {0}: {1}" -f $label, $failureReason)
			[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiWslInstallTitle' -Fallback 'Install WSL') -Message ("WSL install for {0} did not complete.`n`n{1}" -f $label, $failureReason) -Buttons @('OK') -AccentButton 'OK')
		}
	}
	catch
	{
		LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix 'WSL install launcher failed')
		[void](Show-ThemedDialog -Title (Get-UxLocalizedString -Key 'GuiWslInstallTitle' -Fallback 'Install WSL') -Message ("Failed to launch the WSL installer.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
	}
}

function New-GuiCustomizationsActionCard
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[Parameter(Mandatory = $true)]
		[string]$Description,

		[Parameter(Mandatory = $true)]
		[string]$ButtonText,

		[Parameter(Mandatory = $true)]
		[scriptblock]$Action,

		[Parameter(Mandatory = $true)]
		[object]$Theme,

		[Parameter(Mandatory = $true)]
		[object]$BrushConverter
	)

	$card = New-Object System.Windows.Controls.Border
	$card.Background = $BrushConverter.ConvertFromString($Theme.CardBg)
	$card.BorderBrush = $BrushConverter.ConvertFromString($Theme.CardBorder)
	$card.BorderThickness = [System.Windows.Thickness]::new(1)
	$card.CornerRadius = [System.Windows.CornerRadius]::new($Script:GuiLayout.CardCornerRadius)
	$card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
	$card.Margin = [System.Windows.Thickness]::new(8, 0, 8, 8)

	$grid = New-Object System.Windows.Controls.Grid
	$textColumn = New-Object System.Windows.Controls.ColumnDefinition
	$textColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
	$buttonColumn = New-Object System.Windows.Controls.ColumnDefinition
	$buttonColumn.Width = [System.Windows.GridLength]::Auto
	[void]$grid.ColumnDefinitions.Add($textColumn)
	[void]$grid.ColumnDefinitions.Add($buttonColumn)

	$textStack = New-Object System.Windows.Controls.StackPanel
	$textStack.Orientation = 'Vertical'
	[System.Windows.Controls.Grid]::SetColumn($textStack, 0)

	$titleBlock = New-Object System.Windows.Controls.TextBlock
	$titleBlock.Text = $Title
	$titleBlock.FontSize = 13
	$titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
	$titleBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextPrimary)
	[void]$textStack.Children.Add($titleBlock)

	$descriptionBlock = New-Object System.Windows.Controls.TextBlock
	$descriptionBlock.Text = $Description
	$descriptionBlock.FontSize = 11
	$descriptionBlock.Foreground = $BrushConverter.ConvertFromString($Theme.TextSecondary)
	$descriptionBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
	$descriptionBlock.Margin = [System.Windows.Thickness]::new(0, 2, 12, 0)
	[void]$textStack.Children.Add($descriptionBlock)

	[void]$grid.Children.Add($textStack)

	$button = New-Object System.Windows.Controls.Button
	$button.Content = $ButtonText
	$button.MinWidth = 104
	$button.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
	$button.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$button.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
	[System.Windows.Controls.Grid]::SetColumn($button, 1)
	[void]$grid.Children.Add($button)
	Register-GuiEventHandler -Source $button -EventName 'Click' -Handler $Action | Out-Null

	$card.Child = $grid
	return $card
}

function New-GuiStartupManagerTabContent
{
	<#
		.SYNOPSIS
		Builds the Customizations-tab content surface for startup entries.
	#>
	[CmdletBinding()]
	[OutputType([System.Windows.Controls.Panel])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return $null
	}

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'StartupManagerTabContent'
	$entries = @(Get-GuiStartupManagerEntries)
	$entryCountText = if ($entries.Count -eq 1) { '1 startup entry' } else { '{0} startup entries' -f $entries.Count }

	$mainPanel = New-TabContentMainPanel -BrushConverter $bc
	$mainPanel.Margin = [System.Windows.Thickness]::new(0)

	$actionSectionTitle = New-Object System.Windows.Controls.TextBlock
	$actionSectionTitle.Text = Get-UxLocalizedString -Key 'GuiCustomizationsActionsTitle' -Fallback 'Tweak utilities'
	$actionSectionTitle.FontSize = 13
	$actionSectionTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
	$actionSectionTitle.Foreground = $bc.ConvertFromString($theme.TextPrimary)
	$actionSectionTitle.Margin = [System.Windows.Thickness]::new(8, 8, 8, 8)
	[void]($mainPanel.Children.Add($actionSectionTitle))

	foreach ($definition in @(Get-GuiCustomizationsActionCardDefinitions))
	{
		$title = Get-UxLocalizedString -Key ([string]$definition.TitleKey) -Fallback ([string]$definition.TitleFallback)
		$description = Get-UxLocalizedString -Key ([string]$definition.DescriptionKey) -Fallback ([string]$definition.DescriptionFallback)
		if ([bool]$definition.AppendEntryCount)
		{
			$description = "{0} {1}" -f $description, $entryCountText
		}
		[void]($mainPanel.Children.Add((New-GuiCustomizationsActionCard `
			-Title $title `
			-Description $description `
			-ButtonText (Get-UxLocalizedString -Key ([string]$definition.ButtonKey) -Fallback ([string]$definition.ButtonFallback)) `
			-Action ([scriptblock]$definition.Action) `
			-Theme $theme `
			-BrushConverter $bc)))
	}

	return $mainPanel
}

function Show-GuiStartupManagerDialog
{
	<#
		.SYNOPSIS
		Themed WPF dialog for managing Windows startup entries
		(Run / RunOnce / Startup folder) per-row.

		.DESCRIPTION
		Backed by Get-BaselineStartupEntries / Set-BaselineStartupEntryEnabled.
		Per-row checkbox state mirrors the StartupApproved bit Task Manager's
		Startup tab also flips. Runs the toggle synchronously so a hard
		close still preserves the change. Returns
		@{ Cancelled = [bool]; Changes = @(...) }.
	#>
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	if (-not $Script:CurrentTheme)
	{
		return @{ Cancelled = $true; Changes = @() }
	}

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'StartupManagerDialog'

	$titleText      = Get-UxLocalizedString -Key 'GuiStartupManagerTitle'    -Fallback 'Startup Manager'
	$subtitleText   = Get-UxLocalizedString -Key 'GuiStartupManagerSubtitle' -Fallback 'Enable or disable Run / RunOnce / Startup folder entries. Toggling here flips the same StartupApproved bit Task Manager uses; the underlying entry is never deleted.'
	$closeLabel     = Get-UxLocalizedString -Key 'GuiCloseButton'            -Fallback 'Close'
	$emptyLabel     = Get-UxLocalizedString -Key 'GuiStartupManagerEmpty'    -Fallback 'No startup entries detected on this system.'
	$runOnceLabel   = Get-UxLocalizedString -Key 'GuiStartupManagerRunOnceNote' -Fallback 'RunOnce entry — not toggleable (Windows clears these on first run).'
	$failedToggleFmt = Get-UxLocalizedString -Key 'GuiStartupManagerToggleFailed' -Fallback 'Failed to toggle ''{0}''.'

	$entries = @(Get-GuiStartupManagerEntries)

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
		Changes   = New-Object System.Collections.Generic.List[object]
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
	Add-GuiStartupManagerRowsToPanel -Panel $rowsPanel -Entries $entries -BrushConverter $bc -Theme $theme -ChangeList $state.Changes -EmptyLabel $emptyLabel -RunOnceLabel $runOnceLabel -FailedToggleFmt $failedToggleFmt
	}

	$dlg.Add_KeyDown({
		$eventArgs = $args[1]
		if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
	})

	[void]($dlg.ShowDialog())

	return @{
		Cancelled = [bool]$state.Cancelled
		Changes   = @($state.Changes.ToArray())
	}
}
