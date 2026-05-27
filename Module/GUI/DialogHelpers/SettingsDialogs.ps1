

	<#
	    .SYNOPSIS
	#>

	function Show-RiskDecisionDialog
	{
		param(
			[string]$Title = 'Warning',
			[string]$Message,
			[object[]]$SummaryCards = @(),
			[string[]]$Buttons = @('Cancel', 'Preview Run', 'Run Anyway'),
			[string]$AccentButton = $null,
			[string]$DestructiveButton = $null
		)

		return (GUICommon\Show-GuiCommonRiskDecisionDialog `
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

	<#
	    .SYNOPSIS
	#>

function Show-GuiSettingsImportDialog
{
		param (
			[string]$AppName = 'Baseline'
		)

		$theme = $Script:CurrentTheme
		if (-not $theme)
		{
			return $null
		}

		$bc = New-SafeBrushConverter -Context 'DialogHelpers-ImportSettings'
		$windowTitle = Get-UxLocalizedString -Key 'GuiImportSettings' -Fallback 'Import Settings'
		$windowSubtitle = Get-UxLocalizedString -Key 'GuiImportSettingsSubtitle' -Fallback 'Choose where to load Baseline settings from.'
		$closeLabel = Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close'

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$windowTitle"
	Width="820" Height="560"
	MinWidth="680" MinHeight="480"
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

			<ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,18,20,18">
				<WrapPanel Name="CardPanel" HorizontalAlignment="Stretch"/>
			</ScrollViewer>

			<Border Grid.Row="3" Background="$($theme.HeaderBg)"
					BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
					Padding="20,10,20,10">
				<Grid>
					<Button Name="BtnCancel" Content="" HorizontalAlignment="Right" Padding="20,6" FontSize="13"/>
				</Grid>
			</Border>
		</Grid>
	</Border>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		$rootBorder = $dlg.FindName('RootBorder')
		if ($rootBorder)
		{
			$rootBorder.Background = $bc.ConvertFromString($theme.WindowBg)
			$rootBorder.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		}

		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		$cardPanel = $dlg.FindName('CardPanel')
		$btnCancel = $dlg.FindName('BtnCancel')
		$resultRef = @{ Value = $null }

		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
			$dlgCtx = New-Object System.Windows.Controls.ContextMenu
			$dlgCtxClose = New-Object System.Windows.Controls.MenuItem
			$dlgCtxClose.Header = $closeLabel
			$dlgCtxClose.InputGestureText = 'Alt+F4'
			$dlgCtxClose.FontWeight = [System.Windows.FontWeights]::Bold
			$dlgRefForContext = $dlg
			$dlgCtxClose.Add_Click({ $dlgRefForContext.Close() }.GetNewClosure())
			[void]$dlgCtx.Items.Add($dlgCtxClose)
			$dlgTitleBar.ContextMenu = $dlgCtx
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }

		$cardDefinitions = @(
			[pscustomobject]@{
				Token = 'Own'
				Title = (Get-UxLocalizedString -Key 'GuiImportSettingsOwnTitle' -Fallback 'Saved profile')
				Detail = (Get-UxLocalizedString -Key 'GuiImportSettingsOwnDetail' -Fallback ("Open a Baseline settings profile from the {0} settings folder." -f $AppName))
				Icon = 'Folder'
			}
			[pscustomobject]@{
				Token = 'Recommended'
				Title = (Get-UxLocalizedString -Key 'GuiImportSettingsRecommendedTitle' -Fallback 'Last run')
				Detail = (Get-UxLocalizedString -Key 'GuiImportSettingsRecommendedDetail' -Fallback 'Load the profile saved after Baseline finished its last run.')
				Icon = 'RestoreDefaults'
			}
			[pscustomobject]@{
				Token = 'Backup'
				Title = (Get-UxLocalizedString -Key 'GuiImportSettingsBackupTitle' -Fallback 'Session backup')
				Detail = (Get-UxLocalizedString -Key 'GuiImportSettingsBackupDetail' -Fallback 'Load the current session-state backup used for undo and restore.')
				Icon = 'Archive'
			}
			[pscustomobject]@{
				Token = 'Custom'
				Title = (Get-UxLocalizedString -Key 'GuiImportSettingsCustomTitle' -Fallback 'Custom file')
				Detail = (Get-UxLocalizedString -Key 'GuiImportSettingsCustomDetail' -Fallback 'Browse to any compatible Baseline settings JSON file.')
				Icon = 'Search'
			}
		)

		foreach ($cardDef in $cardDefinitions)
		{
			$button = New-Object System.Windows.Controls.Button
			$button.HorizontalAlignment = 'Stretch'
			$button.VerticalAlignment = 'Stretch'
			$button.MinWidth = 168
			$button.Width = 168
			$button.Height = 164
			$button.Margin = [System.Windows.Thickness]::new(0, 0, 12, 12)
			$button.Padding = [System.Windows.Thickness]::new(16, 14, 16, 14)
			$button.Cursor = [System.Windows.Input.Cursors]::Hand
			$button.HorizontalContentAlignment = 'Stretch'
			$button.VerticalContentAlignment = 'Stretch'
			Set-ButtonChrome -Button $button -Variant 'Subtle'

			$stack = New-Object System.Windows.Controls.StackPanel
			$stack.Orientation = 'Vertical'
			$stack.HorizontalAlignment = 'Stretch'
			$stack.VerticalAlignment = 'Stretch'

			if (Get-Command -Name 'New-GuiIconTextBlock' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$icon = New-GuiIconTextBlock -IconName ([string]$cardDef.Icon) -Size 26 -Foreground $bc.ConvertFromString($theme.AccentBlue) -VerticalAlignment 'Center'
				if ($icon)
				{
					$icon.HorizontalAlignment = 'Left'
					$icon.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
					[void]($stack.Children.Add($icon))
				}
			}

			$titleBlock = New-Object System.Windows.Controls.TextBlock
			$titleBlock.Text = [string]$cardDef.Title
			$titleBlock.FontSize = 14
			$titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$titleBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$titleBlock.TextWrapping = 'Wrap'
			$titleBlock.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
			[void]($stack.Children.Add($titleBlock))

			$detailBlock = New-Object System.Windows.Controls.TextBlock
			$detailBlock.Text = [string]$cardDef.Detail
			$detailBlock.FontSize = 11
			$detailBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$detailBlock.TextWrapping = 'Wrap'
			[void]($stack.Children.Add($detailBlock))

			$button.Content = $stack
			$buttonToken = [string]$cardDef.Token
			$dlgRef = $dlg
			$resRef = $resultRef
			$button.Add_Click({
				$resRef.Value = $buttonToken
				$dlgRef.Close()
			}.GetNewClosure())
			[void]($cardPanel.Children.Add($button))
		}

		if ($btnCancel)
		{
			$btnCancel.Content = $closeLabel
			Set-ButtonChrome -Button $btnCancel -Variant 'Primary' -Compact
			$btnCancel.IsDefault = $true
			$btnCancel.IsCancel = $true
			$btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
		}

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]

			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape)
			{
				$dlg.Close()
			}
		})

	[void]($dlg.ShowDialog())
	return $resultRef.Value
}

function Get-GuiBaselineStorageRoot
{
	$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
	if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
	if ([string]::IsNullOrWhiteSpace($localAppData)) { return $null }
	return ([System.IO.Path]::Combine($localAppData, 'Baseline'))
}

function Get-GuiBaselineTempStorageRoot
{
	$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
	if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
	if ([string]::IsNullOrWhiteSpace($localAppData)) { return $null }
	return ([System.IO.Path]::Combine($localAppData, 'Temp', 'Baseline'))
}

function Format-GuiStorageSize
{
	param ([Int64]$Bytes)

	if ($Bytes -lt 0) { $Bytes = 0 }
	$units = @('B', 'KB', 'MB', 'GB', 'TB')
	$value = [double]$Bytes
	$unitIndex = 0
	while (($value -ge 1024) -and ($unitIndex -lt ($units.Count - 1)))
	{
		$value = $value / 1024
		$unitIndex++
	}

	if ($unitIndex -eq 0) { return ('{0} {1}' -f [Int64]$value, $units[$unitIndex]) }
	return ('{0:N1} {1}' -f $value, $units[$unitIndex])
}

function Get-GuiDirectorySize
{
	param ([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Directory]::Exists($Path)) { return 0 }

	$total = [Int64]0
	foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue))
	{
		try { $total += [Int64]$file.Length } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SettingsDialogs.Get-GuiDirectorySize:catch296' -Severity Debug }
		 $null = $_ }
	}
	return $total
}

function Get-GuiBaselineStorageUsage
{
	$appDataRoot = Get-GuiBaselineStorageRoot
	$tempRoot = Get-GuiBaselineTempStorageRoot
	$appDataBytes = if ($appDataRoot) { Get-GuiDirectorySize -Path $appDataRoot } else { 0 }
	$tempBytes = if ($tempRoot) { Get-GuiDirectorySize -Path $tempRoot } else { 0 }
	return [pscustomobject]@{
		AppDataRoot = $appDataRoot
		TempRoot    = $tempRoot
		AppDataBytes = $appDataBytes
		TempBytes   = $tempBytes
		TotalBytes  = ([Int64]$appDataBytes + [Int64]$tempBytes)
	}
}

function Format-GuiBaselineStorageLocation
{
	param ([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
	$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
	if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
	if (-not [string]::IsNullOrWhiteSpace($localAppData))
	{
		$baselineRoot = [System.IO.Path]::Combine($localAppData, 'Baseline')
		if ([string]::Equals([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath($baselineRoot), [System.StringComparison]::OrdinalIgnoreCase))
		{
			return '%LOCALAPPDATA%\Baseline'
		}
		$tempRoot = [System.IO.Path]::Combine($localAppData, 'Temp', 'Baseline')
		if ([string]::Equals([System.IO.Path]::GetFullPath($Path), [System.IO.Path]::GetFullPath($tempRoot), [System.StringComparison]::OrdinalIgnoreCase))
		{
			return '%LOCALAPPDATA%\Temp\Baseline'
		}
	}
	return $Path
}

function Test-GuiPathInsideRoot
{
	param (
		[string]$Path,
		[string]$Root
	)

	if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
	$fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
	$fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
	return (
		[string]::Equals($fullPath, $fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
		$fullPath.StartsWith(($fullRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or
		$fullPath.StartsWith(($fullRoot + [System.IO.Path]::AltDirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
	)
}

function Remove-GuiStoragePath
{
	param (
		[string]$Path,
		[string]$Root
	)

	if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return 0 }
	if (-not (Test-GuiPathInsideRoot -Path $Path -Root $Root)) { return 0 }
	if (-not (Test-Path -LiteralPath $Path)) { return 0 }

	$removed = 0
	$item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
	if ($item.PSIsContainer)
	{
		foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue))
		{
			Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
			$removed++
		}
	}
	else
	{
		Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
		$removed = 1
	}

	return $removed
}

function Remove-GuiWorkingCache
{
	param ([string]$Root)

	if ([string]::IsNullOrWhiteSpace($Root)) { return 0 }
	$rcRoot = [System.IO.Path]::Combine($Root, 'RC')
	if (-not (Test-GuiPathInsideRoot -Path $rcRoot -Root $Root)) { return 0 }
	if (-not [System.IO.Directory]::Exists($rcRoot)) { return 0 }

	$activeExtractedRoot = ''
	if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiExtractedRoot))
	{
		try { $activeExtractedRoot = [System.IO.Path]::GetFullPath([string]$Script:GuiExtractedRoot) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SettingsDialogs.Remove-GuiWorkingCache:catch398' -Severity Debug }
		 $activeExtractedRoot = '' }
	}

	$removed = 0
	foreach ($child in @(Get-ChildItem -LiteralPath $rcRoot -Force -ErrorAction SilentlyContinue))
	{
		$childPath = [System.IO.Path]::GetFullPath([string]$child.FullName)
		if (
			-not [string]::IsNullOrWhiteSpace($activeExtractedRoot) -and
			($activeExtractedRoot.StartsWith(($childPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or
			[string]::Equals($activeExtractedRoot.TrimEnd('\', '/'), $childPath.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase))
		)
		{
			continue
		}

		try
		{
			Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
			$removed++
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ClearGuiBaselineStorageCache.ClearWorkingCache'
		}
	}

	return $removed
}

function Clear-GuiBaselineStorageCache
{
	param (
		[bool]$TemporaryCacheFiles,
		[bool]$WorkingFiles,
		[bool]$Logs,
		[bool]$AuditHistory,
		[bool]$SavedSessionState,
		[string]$LogDirectory
	)

	$appDataRoot = Get-GuiBaselineStorageRoot
	$tempRoot = Get-GuiBaselineTempStorageRoot
	if ([string]::IsNullOrWhiteSpace($appDataRoot) -or [string]::IsNullOrWhiteSpace($tempRoot)) { throw 'Baseline storage location is unavailable.' }

	$before = ([Int64](Get-GuiDirectorySize -Path $appDataRoot) + [Int64](Get-GuiDirectorySize -Path $tempRoot))
	$removed = 0

	if ($TemporaryCacheFiles)
	{
		$removed += Remove-GuiWorkingCache -Root $tempRoot
	}

	if ($WorkingFiles)
	{
		foreach ($path in @(
			[System.IO.Path]::Combine($tempRoot, '.hydrate.lock'),
			[System.IO.Path]::Combine($tempRoot, 'detect-cache.json')
		))
		{
			$removed += Remove-GuiStoragePath -Path $path -Root $tempRoot
		}
	}

	if ($Logs)
	{
		$removed += Remove-GuiStoragePath -Path ([System.IO.Path]::Combine($tempRoot, 'perf.log')) -Root $tempRoot
		$logRoots = New-Object System.Collections.Generic.List[string]
		$defaultLogRoot = [System.IO.Path]::Combine($tempRoot, 'Logs')
		if (-not [string]::IsNullOrWhiteSpace($defaultLogRoot)) { [void]$logRoots.Add($defaultLogRoot) }
		if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) { [void]$logRoots.Add([string]$LogDirectory) }
		$currentLogPath = if ($global:LogFilePath) { [System.IO.Path]::GetFullPath([string]$global:LogFilePath) } else { '' }
		foreach ($logRoot in @($logRoots | Select-Object -Unique))
		{
			if ([string]::IsNullOrWhiteSpace($logRoot) -or -not [System.IO.Directory]::Exists($logRoot)) { continue }
			foreach ($logFile in @(Get-ChildItem -LiteralPath $logRoot -Recurse -File -ErrorAction SilentlyContinue))
			{
				$logPath = [System.IO.Path]::GetFullPath([string]$logFile.FullName)
				if (-not [string]::IsNullOrWhiteSpace($currentLogPath) -and [string]::Equals($logPath, $currentLogPath, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
				Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
				$removed++
			}
		}
	}

	if ($AuditHistory)
	{
		$removed += Remove-GuiStoragePath -Path ([System.IO.Path]::Combine($appDataRoot, 'audit.jsonl')) -Root $appDataRoot
	}

	if ($SavedSessionState)
	{
		$removed += Remove-GuiStoragePath -Path ([System.IO.Path]::Combine($appDataRoot, 'UserState')) -Root $appDataRoot
	}

	$after = ([Int64](Get-GuiDirectorySize -Path $appDataRoot) + [Int64](Get-GuiDirectorySize -Path $tempRoot))
	return [pscustomobject]@{
		Removed = $removed
		Before = $before
		After = $after
	}
}

function Show-GuiClearCacheDialog
{
	param (
		[object]$Theme,
		[string]$Title,
		[string]$Message,
		[string]$TemporaryCacheFilesLabel,
		[string]$WorkingFilesLabel,
		[string]$LogsLabel,
		[string]$AuditHistoryLabel,
		[string]$SavedSessionStateLabel,
		[string]$SavedSessionStateDescription,
		[string]$CancelLabel,
		[string]$ClearSelectedLabel
	)

	$bc = New-SafeBrushConverter -Context 'DialogHelpers-ClearCache'
	$textPrimary = if ($Theme.TextPrimary) { [string]$Theme.TextPrimary } else { '#F4F7FF' }
	$textSecondary = if ($Theme.TextSecondary) { [string]$Theme.TextSecondary } else { '#B8C1D9' }
	$cardBg = if ($Theme.CardBg) { [string]$Theme.CardBg } else { [string]$Theme.PanelBg }
	$cardBorder = if ($Theme.CardBorder) { [string]$Theme.CardBorder } else { [string]$Theme.BorderColor }
	$titleXaml = [System.Security.SecurityElement]::Escape([string]$Title)
	$messageXaml = [System.Security.SecurityElement]::Escape([string]$Message)
	$temporaryCacheFilesLabelXaml = [System.Security.SecurityElement]::Escape([string]$TemporaryCacheFilesLabel)
	$workingFilesLabelXaml = [System.Security.SecurityElement]::Escape([string]$WorkingFilesLabel)
	$logsLabelXaml = [System.Security.SecurityElement]::Escape([string]$LogsLabel)
	$auditHistoryLabelXaml = [System.Security.SecurityElement]::Escape([string]$AuditHistoryLabel)
	$savedSessionStateLabelXaml = [System.Security.SecurityElement]::Escape([string]$SavedSessionStateLabel)
	$savedSessionStateDescriptionXaml = [System.Security.SecurityElement]::Escape([string]$SavedSessionStateDescription)
	$cancelLabelXaml = [System.Security.SecurityElement]::Escape([string]$CancelLabel)
	$clearSelectedLabelXaml = [System.Security.SecurityElement]::Escape([string]$ClearSelectedLabel)

	[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="$titleXaml"
	Width="520" Height="420"
	MinWidth="480" MinHeight="380"
	WindowStartupLocation="CenterOwner"
	ResizeMode="NoResize"
	FontSize="12"
	Background="Transparent"
	WindowStyle="None"
	AllowsTransparency="True">
	<Border Name="RootBorder" CornerRadius="8">
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="Auto"/>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>

			<Border Name="DlgTitleBar" Grid.Row="0" Background="$($Theme.HeaderBg)" CornerRadius="8,8,0,0" Padding="12,8,8,8">
				<Grid>
					<TextBlock Text="$titleXaml" VerticalAlignment="Center" FontSize="12" Foreground="$textPrimary"/>
					<Button Name="BtnDlgClose" Content="x" FontFamily="Arial" FontSize="12" Width="32" Height="28"
						Background="Transparent" Foreground="$textPrimary" BorderThickness="0" Cursor="Hand"
						HorizontalAlignment="Right" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</Grid>
			</Border>

			<StackPanel Grid.Row="1" Margin="22,18,22,18">
				<TextBlock Text="$titleXaml" FontSize="17" FontWeight="SemiBold" Foreground="$textPrimary" Margin="0,0,0,6"/>
				<TextBlock Text="$messageXaml" FontSize="12" Foreground="$textSecondary" TextWrapping="Wrap" Margin="0,0,0,18"/>
				<Border Background="$cardBg" BorderBrush="$cardBorder" BorderThickness="1" CornerRadius="6" Padding="14,12">
					<StackPanel>
						<CheckBox Name="ChkTemporaryCacheFiles" Content="$temporaryCacheFilesLabelXaml" IsChecked="True" Margin="0,0,0,10"/>
						<CheckBox Name="ChkWorkingFiles" Content="$workingFilesLabelXaml" IsChecked="True" Margin="0,0,0,10"/>
						<CheckBox Name="ChkLogs" Content="$logsLabelXaml" IsChecked="False" Margin="0,0,0,10"/>
						<CheckBox Name="ChkAuditHistory" Content="$auditHistoryLabelXaml" IsChecked="False" Margin="0,0,0,10"/>
						<CheckBox Name="ChkSavedSessionState" Content="$savedSessionStateLabelXaml" IsChecked="False" Margin="0,0,0,4"/>
						<TextBlock Text="$savedSessionStateDescriptionXaml" FontSize="11" Foreground="$textSecondary" TextWrapping="Wrap" Margin="22,0,0,0"/>
					</StackPanel>
				</Border>
			</StackPanel>

			<Border Grid.Row="2" Background="$($Theme.HeaderBg)" BorderBrush="$($Theme.BorderColor)" BorderThickness="0,1,0,0" Padding="20,12">
				<StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
					<Button Name="BtnCancel" Content="$cancelLabelXaml" Padding="20,7" Margin="0,0,10,0"/>
					<Button Name="BtnClearSelected" Content="$clearSelectedLabelXaml" Padding="24,8" FontWeight="SemiBold"/>
				</StackPanel>
			</Border>
		</Grid>
	</Border>
</Window>
"@

	$reader = [System.Xml.XmlNodeReader]::new($xaml)
	$dlg = [Windows.Markup.XamlReader]::Load($reader)
	if ($Form) { $dlg.Owner = $Form }

	$rootBorder = $dlg.FindName('RootBorder')
	if ($rootBorder)
	{
		$rootBorder.Background = $bc.ConvertFromString($Theme.WindowBg)
		$rootBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
	}
	[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

	$btnDlgClose = $dlg.FindName('BtnDlgClose')
	$dlgTitleBar = $dlg.FindName('DlgTitleBar')
	$btnCancel = $dlg.FindName('BtnCancel')
	$btnClearSelected = $dlg.FindName('BtnClearSelected')
	$chkTemporaryCacheFiles = $dlg.FindName('ChkTemporaryCacheFiles')
	$chkWorkingFiles = $dlg.FindName('ChkWorkingFiles')
	$chkLogs = $dlg.FindName('ChkLogs')
	$chkAuditHistory = $dlg.FindName('ChkAuditHistory')
	$chkSavedSessionState = $dlg.FindName('ChkSavedSessionState')
	$resultRef = @{ Value = $null }
	$applyButtonChrome = ${function:Set-ButtonChrome}

	foreach ($checkbox in @($chkTemporaryCacheFiles, $chkWorkingFiles, $chkLogs, $chkAuditHistory, $chkSavedSessionState))
	{
		if ($checkbox)
		{
			$checkbox.Foreground = $bc.ConvertFromString($textPrimary)
		}
	}

	$syncClearButton = {
		$hasDangerousSelection = (($chkLogs -and [bool]$chkLogs.IsChecked) -or ($chkAuditHistory -and [bool]$chkAuditHistory.IsChecked) -or ($chkSavedSessionState -and [bool]$chkSavedSessionState.IsChecked))
		if ($hasDangerousSelection)
		{
			& $applyButtonChrome -Button $btnClearSelected -Variant 'Danger'
		}
		else
		{
			& $applyButtonChrome -Button $btnClearSelected -Variant 'Primary'
		}
	}.GetNewClosure()

	if ($dlgTitleBar) { $dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure()) }
	if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
	if ($btnCancel)
	{
		& $applyButtonChrome -Button $btnCancel -Variant 'Secondary' -Compact
		$btnCancel.IsCancel = $true
		$btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
	}
	if ($btnClearSelected)
	{
		& $syncClearButton
		$btnClearSelected.Add_Click({
			$resultRef.Value = @{
				TemporaryCacheFiles = [bool]$chkTemporaryCacheFiles.IsChecked
				WorkingFiles = [bool]$chkWorkingFiles.IsChecked
				Logs = [bool]$chkLogs.IsChecked
				AuditHistory = [bool]$chkAuditHistory.IsChecked
				SavedSessionState = [bool]$chkSavedSessionState.IsChecked
			}
			$dlg.Close()
		}.GetNewClosure())
	}
	foreach ($dangerCheckbox in @($chkLogs, $chkAuditHistory, $chkSavedSessionState))
	{
		if ($dangerCheckbox)
		{
			$dangerCheckbox.Add_Checked({ & $syncClearButton }.GetNewClosure())
			$dangerCheckbox.Add_Unchecked({ & $syncClearButton }.GetNewClosure())
		}
	}

	[void](GUICommon\Show-GuiActivatedDialog -Window $dlg)
	return $resultRef.Value
}

	<#
	    .SYNOPSIS
	    Presents the unified Settings dialog and returns a hashtable of updated
	    preferences when the user clicks Save, or $null when cancelled.
	#>

function Show-GuiSettingsDialog
{
	param (
		[hashtable]$Current
	)

	$__perf = Start-GuiPerfScope -Name 'Show-GuiSettingsDialog.Open'
	$theme = $Script:CurrentTheme
	if (-not $theme)
	{
		Stop-GuiPerfScope -Scope $__perf -ExtraNote 'no-theme'
		return $null
	}

	if (-not $Current) { $Current = @{} }

	. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SettingsLocalizedTextAndCaptures.ps1')

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SettingsDialogXaml.ps1')

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\ThemedDialogBridge.ps1')

		$rootBorder = $dlg.FindName('RootBorder')
		if ($rootBorder)
		{
			$rootBorder.Background = ConvertTo-GuiBrush -Color $theme.WindowBg -Context 'DialogHelpers.ShowGuiSettingsDialog.WindowBg' -FallbackColor '#10131C'
			$rootBorder.BorderBrush = ConvertTo-GuiBrush -Color $theme.BorderColor -Context 'DialogHelpers.ShowGuiSettingsDialog.Border' -FallbackColor '#293044'
			$rootBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		}

		[void](GUICommon\Set-GuiWindowChromeTheme -Window $dlg -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))

		$dlgTitleBar = $dlg.FindName('DlgTitleBar')
		$btnDlgClose = $dlg.FindName('BtnDlgClose')
		$btnCancel = $dlg.FindName('BtnCancel')
		$btnSave = $dlg.FindName('BtnSave')
		$btnSettingsLanguage = $dlg.FindName('BtnSettingsLanguage')
		$txtSettingsLanguageDisplay = $dlg.FindName('TxtSettingsLanguageDisplay')
		$settingsLanguagePopup = $dlg.FindName('SettingsLanguagePopup')
		$txtSettingsLanguageSearch = $dlg.FindName('TxtSettingsLanguageSearch')
		$settingsLanguageListPanel = $dlg.FindName('SettingsLanguageListPanel')
		$cmbDefaultStartupMode = $dlg.FindName('CmbDefaultStartupMode')
		$chkRestoreLastSession = $dlg.FindName('ChkRestoreLastSession')
		$chkAutoScanOnLaunch = $dlg.FindName('ChkAutoScanOnLaunch')
		$chkHideUnavailableItems = $dlg.FindName('ChkHideUnavailableItems')
		$chkStartupRunInitialActions = $dlg.FindName('ChkStartupRunInitialActions')
		$chkStartupCheckWinGet = $dlg.FindName('ChkStartupCheckWinGet')
		$cmbStartupWinGetCheckFrequency = $dlg.FindName('CmbStartupWinGetCheckFrequency')
		$chkStartupCheckChocolatey = $dlg.FindName('ChkStartupCheckChocolatey')
		$cmbStartupChocolateyCheckFrequency = $dlg.FindName('CmbStartupChocolateyCheckFrequency')
		$chkAutoCheckUpdates = $dlg.FindName('ChkAutoCheckUpdates')
		$cmbUpdateFrequency = $dlg.FindName('CmbUpdateFrequency')
		$cmbUpdateBranch = $dlg.FindName('CmbUpdateBranch')
		$chkIncludePrereleaseUpdates = $dlg.FindName('ChkIncludePrereleaseUpdates')
		$txtUpdateLastCheckedValue = $dlg.FindName('TxtUpdateLastCheckedValue')
		$txtUpdateCurrentVersionValue = $dlg.FindName('TxtUpdateCurrentVersionValue')
		$txtUpdateBranchValue = $dlg.FindName('TxtUpdateBranchValue')
		$txtUpdateStatusValue = $dlg.FindName('TxtUpdateStatusValue')
		$txtUpdatesAutomationHelper = $dlg.FindName('TxtUpdatesAutomationHelper')
		$btnSettingsCheckNow = $dlg.FindName('BtnSettingsCheckNow')
		$cmbTheme = $dlg.FindName('CmbTheme')
		$cmbUIDensity = $dlg.FindName('CmbUIDensity')
		$chkSafeModeDefault = $dlg.FindName('ChkSafeModeDefault')
		$chkRequireRunConfirmation = $dlg.FindName('ChkRequireRunConfirmation')
		$chkPreviewBeforeRunDefault = $dlg.FindName('ChkPreviewBeforeRunDefault')
		$cmbAuditRetention = $dlg.FindName('CmbAuditRetention')
		$cmbPackageSource = $dlg.FindName('CmbPackageSource')
		$chkAppsSilentInstall = $dlg.FindName('ChkAppsSilentInstall')
		$chkAppsAutoUpdate = $dlg.FindName('ChkAppsAutoUpdate')
		$chkLoggingEnabled = $dlg.FindName('ChkLoggingEnabled')
		$chkDebugLogging = $dlg.FindName('ChkDebugLogging')
		$cmbLogLevel = $dlg.FindName('CmbLogLevel')
		$txtLogFolderPath = $dlg.FindName('TxtLogFolderPath')
		$txtLogFolderHelper = $dlg.FindName('TxtLogFolderHelper')
		$btnLogFolderBrowse = $dlg.FindName('BtnLogFolderBrowse')
		$btnOpenLogFolder = $dlg.FindName('BtnOpenLogFolder')
		$btnCopyLogFolderPath = $dlg.FindName('BtnCopyLogFolderPath')
		$btnClearOldLogs = $dlg.FindName('BtnClearOldLogs')
		$btnSettingsExportSupportBundle = $dlg.FindName('BtnSettingsExportSupportBundle')
		$chkAdvancedMode = $dlg.FindName('ChkAdvancedMode')
		$chkDesignMode = $dlg.FindName('ChkDesignMode')
		$txtStorageUsage = $dlg.FindName('TxtStorageUsage')
		$txtStorageLocation = $dlg.FindName('TxtStorageLocation')
		$btnRefreshStorageUsage = $dlg.FindName('BtnRefreshStorageUsage')
		$btnClearCache = $dlg.FindName('BtnClearCache')
		if ($chkDesignMode) { $chkDesignMode.IsEnabled = $true }
		$resultRef = @{ Value = $null }

		if (Get-Command -Name 'Set-GuiTabHeaderWithIcon' -CommandType Function -ErrorAction SilentlyContinue)
		{
			foreach ($tabDefinition in @(
				@{ Name = 'TabSettingsGeneral'; Icon = 'WindowSettings'; Text = $generalHeading }
				@{ Name = 'TabSettingsAppearance'; Icon = 'Theme'; Text = $appearanceHeading }
				@{ Name = 'TabSettingsSafety'; Icon = 'Shield'; Text = $safetyHeading }
				@{ Name = 'TabSettingsApps'; Icon = 'AppsTab'; Text = $appsHeading }
				@{ Name = 'TabSettingsLogging'; Icon = 'OpenLog'; Text = $loggingHeading }
				@{ Name = 'TabSettingsAdvanced'; Icon = 'Advanced'; Text = $advancedHeading }
			))
			{
				$tab = $dlg.FindName([string]$tabDefinition.Name)
				if ($tab)
				{
					Set-GuiTabHeaderWithIcon -Tab $tab -IconName ([string]$tabDefinition.Icon) -Text ([string]$tabDefinition.Text) -IconSize 14 -Gap 6
				}
			}
		}

		$settingsInputBgBrush = ConvertTo-GuiBrush -Color $surfaceControl -Context 'DialogHelpers.ShowGuiSettingsDialog.InputBg' -FallbackColor '#262D40'
		$settingsInputBorderBrush = ConvertTo-GuiBrush -Color $controlBorder -Context 'DialogHelpers.ShowGuiSettingsDialog.InputBorder' -FallbackColor '#293044'
		$settingsTextPrimaryBrush = ConvertTo-GuiBrush -Color $textPrimary -Context 'DialogHelpers.ShowGuiSettingsDialog.TextPrimary' -FallbackColor '#F4F7FF'
		$settingsTextSecondaryBrush = ConvertTo-GuiBrush -Color $textSecondary -Context 'DialogHelpers.ShowGuiSettingsDialog.TextSecondary' -FallbackColor '#B8C1D9'
		$settingsTextMutedBrush = ConvertTo-GuiBrush -Color $textMuted -Context 'DialogHelpers.ShowGuiSettingsDialog.TextMuted' -FallbackColor '#828AA2'
		$settingsAccentBrush = ConvertTo-GuiBrush -Color $accentBlue -Context 'DialogHelpers.ShowGuiSettingsDialog.Accent' -FallbackColor '#7CB7FF'
		$settingsSelectionBrush = ConvertTo-GuiBrush -Color $selectionSurface -Context 'DialogHelpers.ShowGuiSettingsDialog.Selection' -FallbackColor '#202638'

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SettingsSystemBrushes.ps1')

		$applySettingsComboItemTheme = {
			param ($item)
			if (-not $item -or -not ($item -is [System.Windows.Controls.ComboBoxItem])) { return }
			$item.Background = $settingsInputBgBrush
			$item.Foreground = $settingsTextPrimaryBrush
			$item.BorderBrush = $settingsInputBorderBrush
			$item.BorderThickness = [System.Windows.Thickness]::new(0)
			$item.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
			$item.Opacity = 1
			& $applySettingsSystemBrushes $item
		}.GetNewClosure()

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SettingsInputTheme.ps1')

		if ($btnSettingsLanguage)
		{
			& $applySettingsSystemBrushes $btnSettingsLanguage
			$btnSettingsLanguage.Background = $settingsInputBgBrush
			$btnSettingsLanguage.Foreground = $settingsTextPrimaryBrush
			$btnSettingsLanguage.BorderBrush = $settingsInputBorderBrush
			$btnSettingsLanguage.Opacity = 1
		}
		if ($txtSettingsLanguageDisplay) { $txtSettingsLanguageDisplay.Foreground = $settingsTextPrimaryBrush }
		& $applySettingsInputTheme $txtSettingsLanguageSearch
		foreach ($logFolderButton in @($btnLogFolderBrowse, $btnOpenLogFolder, $btnCopyLogFolderPath))
		{
			if ($logFolderButton) { Set-ButtonChrome -Button $logFolderButton -Variant 'Subtle' -Compact -Muted }
		}
		if ($btnClearOldLogs) { Set-ButtonChrome -Button $btnClearOldLogs -Variant 'DangerSubtle' -Compact }
		if ($btnRefreshStorageUsage) { Set-ButtonChrome -Button $btnRefreshStorageUsage -Variant 'Subtle' -Compact -Muted }
		if ($btnClearCache) { Set-ButtonChrome -Button $btnClearCache -Variant 'Secondary' -Compact }
		if ($btnSettingsCheckNow) { Set-ButtonChrome -Button $btnSettingsCheckNow -Variant 'Secondary' -Compact }
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SupportBundleExportLink.ps1')

		$addComboItem = {
			param ($combo, $label, $tag)
			if (-not $combo) { return }
			$ci = New-Object System.Windows.Controls.ComboBoxItem
			$ci.Content = $label
			$ci.Tag = $tag
			& $applySettingsComboItemTheme $ci
			[void]$combo.Items.Add($ci)
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\ComboSelectionHelpers.ps1')

		$formatLanguageDisplay = {
			param ($entry)
			$nativeName = [string]$entry.NativeName
			$englishName = [string]$entry.EnglishName
			if ([string]::IsNullOrWhiteSpace($nativeName) -or $nativeName -eq $englishName)
			{
				return $englishName
			}
			return ('{0} ({1})' -f $englishName, $nativeName)
		}

		$languageEntries = @(Get-GuiLanguageEntries -LocalizationDirectory $Script:GuiLocalizationDirectoryPath)
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LanguageStateInitialization.ps1')
		if ([string]::IsNullOrWhiteSpace($settingsLanguageState.Code) -or [string]$settingsLanguageState.Code -eq 'en') { $settingsLanguageState.Code = 'en-US' }

		$textPrimaryBrush = $settingsTextPrimaryBrush
		$textMutedBrush = $settingsTextMutedBrush
		$activeBrush = $settingsSelectionBrush
		$accentBrush = $settingsAccentBrush
		$hoverColor = $surfaceHover

		$languageUiState = @{ Render = $null }

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LanguageSelectionHandlers.ps1')

		$languageUiState.Render = $renderLanguageList

		& $updateLanguageButtonText
		& $renderLanguageList ''

		if ($txtSettingsLanguageSearch)
		{
			$txtSettingsLanguageSearch.Add_TextChanged({
				if ($languageUiState.Render)
				{
					& $languageUiState.Render ([string]$txtSettingsLanguageSearch.Text)
				}
			}.GetNewClosure())
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LanguagePopupHandlers.ps1')

		if ($cmbDefaultStartupMode)
		{
			& $addComboItem $cmbDefaultStartupMode $settingsOptionStartupSafe 'Safe'
			& $addComboItem $cmbDefaultStartupMode $settingsOptionStartupExpert 'Expert'
			& $selectComboByTag $cmbDefaultStartupMode ($(if ($Current.ContainsKey('DefaultStartupMode') -and -not [string]::IsNullOrWhiteSpace([string]$Current.DefaultStartupMode)) { [string]$Current.DefaultStartupMode } else { 'Safe' }))
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\UpdateSettingsControls.ps1')

		if ($cmbTheme)
		{
			& $addComboItem $cmbTheme $settingsOptionThemeSystem 'System'
			& $addComboItem $cmbTheme $settingsOptionThemeDark 'Dark'
			& $addComboItem $cmbTheme $settingsOptionThemeLight 'Light'
			& $selectComboByTag $cmbTheme ($(if ($Current.ContainsKey('Theme') -and -not [string]::IsNullOrWhiteSpace([string]$Current.Theme)) { [string]$Current.Theme } elseif ($Script:ThemePreference) { [string]$Script:ThemePreference } else { 'System' }))
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\UIDensitySelection.ps1')

		if ($cmbAuditRetention)
		{
			& $addComboItem $cmbAuditRetention $settingsOptionRetention30 30
			& $addComboItem $cmbAuditRetention $settingsOptionRetention90 90
			& $addComboItem $cmbAuditRetention $settingsOptionRetention180 180
			& $addComboItem $cmbAuditRetention $settingsOptionRetention365 365
			$selectedRetention = if ($Current.ContainsKey('AuditRetentionDays') -and $Current.AuditRetentionDays) { [int]$Current.AuditRetentionDays } else { 90 }
			& $selectComboByTag $cmbAuditRetention $selectedRetention
		}

		if ($cmbPackageSource)
		{
			& $addComboItem $cmbPackageSource $settingsOptionPackageAuto 'auto'
			& $addComboItem $cmbPackageSource $settingsOptionPackageWinGet 'winget'
			& $addComboItem $cmbPackageSource $settingsOptionPackageChocolatey 'choco'
			& $selectComboByTag $cmbPackageSource ($(if ($Current.ContainsKey('AppsPackageSourcePreference') -and -not [string]::IsNullOrWhiteSpace([string]$Current.AppsPackageSourcePreference)) { [string]$Current.AppsPackageSourcePreference } else { 'auto' }))
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LogLevelSelection.ps1')

		foreach ($settingsCombo in @($cmbDefaultStartupMode, $cmbStartupWinGetCheckFrequency, $cmbStartupChocolateyCheckFrequency, $cmbUpdateFrequency, $cmbUpdateBranch, $cmbTheme, $cmbUIDensity, $cmbAuditRetention, $cmbPackageSource, $cmbLogLevel))
		{
			& $applySettingsInputTheme $settingsCombo
		}

		if ($chkRestoreLastSession) { $chkRestoreLastSession.IsChecked = if ($Current.ContainsKey('RestoreLastSession')) { [bool]$Current.RestoreLastSession } else { $true } }
		if ($chkAutoScanOnLaunch) { $chkAutoScanOnLaunch.IsChecked = if ($Current.ContainsKey('AutoScanOnLaunch')) { [bool]$Current.AutoScanOnLaunch } else { $false } }
		if ($chkHideUnavailableItems) { $chkHideUnavailableItems.IsChecked = if ($Current.ContainsKey('HideUnavailableItems')) { [bool]$Current.HideUnavailableItems } else { $true } }
		if ($chkStartupRunInitialActions) { $chkStartupRunInitialActions.IsChecked = if ($Current.ContainsKey('StartupRunInitialActions')) { [bool]$Current.StartupRunInitialActions } else { $true } }
		if ($chkStartupCheckWinGet) { $chkStartupCheckWinGet.IsChecked = if ($Current.ContainsKey('StartupCheckWinGet')) { [bool]$Current.StartupCheckWinGet } else { $true } }
		if ($chkStartupCheckChocolatey) { $chkStartupCheckChocolatey.IsChecked = if ($Current.ContainsKey('StartupCheckChocolatey')) { [bool]$Current.StartupCheckChocolatey } else { $true } }
		foreach ($startupFrequencyCombo in @($cmbStartupWinGetCheckFrequency, $cmbStartupChocolateyCheckFrequency))
		{
			if ($startupFrequencyCombo)
			{
				& $addComboItem $startupFrequencyCombo $settingsOptionUpdateStartup 'Startup'
				& $addComboItem $startupFrequencyCombo $settingsOptionUpdateDaily 'Daily'
				& $addComboItem $startupFrequencyCombo $settingsOptionUpdateWeekly 'Weekly'
			}
		}
		$selectedStartupWinGetFrequency = if ($Current.ContainsKey('StartupWinGetCheckFrequency') -and -not [string]::IsNullOrWhiteSpace([string]$Current.StartupWinGetCheckFrequency)) { [string]$Current.StartupWinGetCheckFrequency } else { 'Startup' }
		$selectedStartupChocolateyFrequency = if ($Current.ContainsKey('StartupChocolateyCheckFrequency') -and -not [string]::IsNullOrWhiteSpace([string]$Current.StartupChocolateyCheckFrequency)) { [string]$Current.StartupChocolateyCheckFrequency } else { 'Startup' }
		if (Get-Command -Name 'ConvertTo-BaselineUpdateCheckFrequency' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$selectedStartupWinGetFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $selectedStartupWinGetFrequency
			$selectedStartupChocolateyFrequency = ConvertTo-BaselineUpdateCheckFrequency -Frequency $selectedStartupChocolateyFrequency
		}
		& $selectComboByTag $cmbStartupWinGetCheckFrequency $selectedStartupWinGetFrequency
		& $selectComboByTag $cmbStartupChocolateyCheckFrequency $selectedStartupChocolateyFrequency
		if ($chkAutoCheckUpdates) { $chkAutoCheckUpdates.IsChecked = if ($Current.ContainsKey('AutoCheckUpdates')) { [bool]$Current.AutoCheckUpdates } else { $true } }
		if ($chkIncludePrereleaseUpdates) { $chkIncludePrereleaseUpdates.IsChecked = if ($Current.ContainsKey('IncludePrereleaseUpdates')) { [bool]$Current.IncludePrereleaseUpdates } elseif ($Current.ContainsKey('IncludePrereleaseBuilds')) { [bool]$Current.IncludePrereleaseBuilds } else { $false } }
		if ($chkSafeModeDefault) { $chkSafeModeDefault.IsChecked = if ($Current.ContainsKey('SafeMode')) { [bool]$Current.SafeMode } else { $false } }
		if ($chkRequireRunConfirmation) { $chkRequireRunConfirmation.IsChecked = if ($Current.ContainsKey('RequireRunConfirmation')) { [bool]$Current.RequireRunConfirmation } else { $true } }
		if ($chkPreviewBeforeRunDefault) { $chkPreviewBeforeRunDefault.IsChecked = if ($Current.ContainsKey('PreviewBeforeRunDefault')) { [bool]$Current.PreviewBeforeRunDefault } else { $false } }
		if ($chkAppsSilentInstall) { $chkAppsSilentInstall.IsChecked = if ($Current.ContainsKey('AppsSilentInstall')) { [bool]$Current.AppsSilentInstall } else { $true } }
		if ($chkAppsAutoUpdate) { $chkAppsAutoUpdate.IsChecked = if ($Current.ContainsKey('AppsAutoUpdate')) { [bool]$Current.AppsAutoUpdate } else { $false } }
		if ($chkLoggingEnabled) { $chkLoggingEnabled.IsChecked = if ($Current.ContainsKey('LoggingEnabled')) { [bool]$Current.LoggingEnabled } else { $true } }
		if ($chkDebugLogging) { $chkDebugLogging.IsChecked = if ($Current.ContainsKey('DebugLoggingEnabled')) { [bool]$Current.DebugLoggingEnabled } else { $false } }
		if ($chkAdvancedMode) { $chkAdvancedMode.IsChecked = if ($Current.ContainsKey('AdvancedMode')) { [bool]$Current.AdvancedMode } else { $false } }
		if ($chkDesignMode) { $chkDesignMode.IsChecked = if ($Current.ContainsKey('DesignMode')) { [bool]$Current.DesignMode } else { [bool]$Script:DesignMode } }

		$settingsUpdateState = @{
			LastCheckedUtc = if ($Current.ContainsKey('UpdateLastCheckedUtc')) { $Current.UpdateLastCheckedUtc } else { $null }
			Status = if ($Current.ContainsKey('UpdateCheckStatus') -and -not [string]::IsNullOrWhiteSpace([string]$Current.UpdateCheckStatus)) { [string]$Current.UpdateCheckStatus } else { 'Not checked' }
			LatestVersion = if ($Current.ContainsKey('UpdateLatestVersion')) { [string]$Current.UpdateLatestVersion } else { '' }
			Message = ''
		}
		$currentVersionText = if ($Current.ContainsKey('CurrentVersion') -and -not [string]::IsNullOrWhiteSpace([string]$Current.CurrentVersion)) { [string]$Current.CurrentVersion } else { '0.0.0' }
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\UpdateStatusDisplay.ps1')
		$syncStartupSplashPackageManagerControls = {
			if ($cmbStartupWinGetCheckFrequency) { $cmbStartupWinGetCheckFrequency.IsEnabled = (-not $chkStartupCheckWinGet) -or [bool]$chkStartupCheckWinGet.IsChecked }
			if ($cmbStartupChocolateyCheckFrequency) { $cmbStartupChocolateyCheckFrequency.IsEnabled = (-not $chkStartupCheckChocolatey) -or [bool]$chkStartupCheckChocolatey.IsChecked }
		}.GetNewClosure()
		if ($chkStartupCheckWinGet)
		{
			$chkStartupCheckWinGet.Add_Checked({ & $syncStartupSplashPackageManagerControls }.GetNewClosure())
			$chkStartupCheckWinGet.Add_Unchecked({ & $syncStartupSplashPackageManagerControls }.GetNewClosure())
		}
		if ($chkStartupCheckChocolatey)
		{
			$chkStartupCheckChocolatey.Add_Checked({ & $syncStartupSplashPackageManagerControls }.GetNewClosure())
			$chkStartupCheckChocolatey.Add_Unchecked({ & $syncStartupSplashPackageManagerControls }.GetNewClosure())
		}
		& $syncStartupSplashPackageManagerControls
		$getUpdateBranchSelection = {
			$defaultUpdateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
			$branch = if ($cmbUpdateBranch -and $cmbUpdateBranch.SelectedItem -and $null -ne $cmbUpdateBranch.SelectedItem.Tag) { [string]$cmbUpdateBranch.SelectedItem.Tag } else { $defaultUpdateBranch }
			if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
			{
				$branch = ConvertTo-BaselineUpdateBranch -Branch $branch
			}
			return $branch
		}.GetNewClosure()
		$getCurrentUpdateBranch = {
			return [string](& $getUpdateBranchSelection)
		}.GetNewClosure()
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\UpdateAutomationControls.ps1')
		& $refreshUpdateDisplay
		if ($chkAutoCheckUpdates)
		{
			$chkAutoCheckUpdates.Add_Checked({ & $refreshUpdateDisplay }.GetNewClosure())
			$chkAutoCheckUpdates.Add_Unchecked({ & $refreshUpdateDisplay }.GetNewClosure())
		}
		if ($cmbUpdateBranch)
		{
			$cmbUpdateBranch.Add_SelectionChanged({ & $refreshUpdateDisplay }.GetNewClosure())
		}
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\UpdateCheckNowHandler.ps1')
		$settingsLogState = @{
			DefaultDirectory = $defaultLogDirectory
			CustomDirectory  = if ($Current.ContainsKey('LogFileDirectory') -and -not [string]::IsNullOrWhiteSpace([string]$Current.LogFileDirectory)) { [string]$Current.LogFileDirectory } else { '' }
		}
		$getEffectiveLogDirectory = {
			$expertEnabled = $chkAdvancedMode -and [bool]$chkAdvancedMode.IsChecked
			if ($expertEnabled -and -not [string]::IsNullOrWhiteSpace([string]$settingsLogState.CustomDirectory))
			{
				return [string]$settingsLogState.CustomDirectory
			}
			return [string]$settingsLogState.DefaultDirectory
		}.GetNewClosure()
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LogFolderDisplay.ps1')
		& $refreshLogFolderDisplay

		if ($chkAdvancedMode)
		{
			$chkAdvancedMode.Add_Checked({ & $refreshLogFolderDisplay }.GetNewClosure())
			$chkAdvancedMode.Add_Unchecked({ & $refreshLogFolderDisplay }.GetNewClosure())
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\LogFolderBrowseHandler.ps1')

		$getGuiBaselineStorageRoot = {
			$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
			if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
			if ([string]::IsNullOrWhiteSpace($localAppData)) { return $null }
			return ([System.IO.Path]::Combine($localAppData, 'Baseline'))
		}.GetNewClosure()

		$getGuiBaselineTempStorageRoot = {
			$localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
			if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
			if ([string]::IsNullOrWhiteSpace($localAppData)) { return $null }
			return ([System.IO.Path]::Combine($localAppData, 'Temp', 'Baseline'))
		}.GetNewClosure()

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\StorageSizeHelpers.ps1')

		$showGuiClearCacheDialog = ${function:Show-GuiClearCacheDialog}
		$showThemedDialog = $settingsShowThemedDialog

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\StorageUsageDisplay.ps1')
		& $refreshStorageDisplay

		if ($btnRefreshStorageUsage)
		{
			$btnRefreshStorageUsage.Add_Click({
				& $refreshStorageDisplay
			}.GetNewClosure())
		}

		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\ClearCacheHandler.ps1')

		if ($cmbDefaultStartupMode)
		{
			& $syncStartupMode -InitialLoad
			$cmbDefaultStartupMode.Add_SelectionChanged({
				& $syncStartupMode
			}.GetNewClosure())
		}

		if ($dlgTitleBar)
		{
			$dlgTitleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() }.GetNewClosure())
		}
		if ($btnDlgClose) { $btnDlgClose.Add_Click({ $dlg.Close() }.GetNewClosure()) }
		if ($btnCancel)
		{
			$btnCancel.Content = $cancelLabel
			Set-ButtonChrome -Button $btnCancel -Variant 'Secondary' -Compact
			$btnCancel.IsCancel = $true
			$btnCancel.Add_Click({ $dlg.Close() }.GetNewClosure())
		}
		. (Join-Path $PSScriptRoot 'SettingsDialogs\Show-GuiSettingsDialog\SaveSettingsHandler.ps1')

		$dlg.Add_KeyDown({
			$eventArgs = $args[1]
			if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape)
			{
				$dlg.Close()
			}
		})

		Stop-GuiPerfScope -Scope $__perf
		[void](GUICommon\Show-GuiActivatedDialog -Window $dlg)
		return $resultRef.Value
	}
