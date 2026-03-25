using module .\Logging.psm1

function Show-ThemedDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[string]$Title,
		[string]$Message,
		[string[]]$Buttons = @('OK'),
		[string]$AccentButton = $null,
		[string]$DestructiveButton = $null
	)

	$bc = [System.Windows.Media.BrushConverter]::new()

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = 440
	$dlg.SizeToContent = 'Height'
	$dlg.ResizeMode = 'NoResize'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Background = $bc.ConvertFromString($Theme.WindowBg)
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$dlg.FontSize = 13
	$dlg.ShowInTaskbar = $false
	$dlg.WindowStyle = 'SingleBorderWindow'

	try
	{
		if ($OwnerWindow)
		{
			$dlg.Owner = $OwnerWindow
		}
	}
	catch
	{
		$null = $_
	}

	$outerStack = New-Object System.Windows.Controls.StackPanel

	$msgBorder = New-Object System.Windows.Controls.Border
	$msgBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
	$msgTb = New-Object System.Windows.Controls.TextBlock
	$msgTb.Text = $Message
	$msgTb.TextWrapping = 'Wrap'
	$msgTb.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$msgTb.FontSize = 13
	$msgTb.LineHeight = 20
	$msgBorder.Child = $msgTb
	$outerStack.Children.Add($msgBorder) | Out-Null

	$btnBorder = New-Object System.Windows.Controls.Border
	$btnBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
	$btnBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$btnBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$btnBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	$btnPanel = New-Object System.Windows.Controls.StackPanel
	$btnPanel.Orientation = 'Horizontal'
	$btnPanel.HorizontalAlignment = 'Right'

	$resultRef = @{
		Value = $(if ($Buttons -contains 'Close') { 'Close' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
		$btn.MinWidth = 112
		$btn.Height = 34
		$btn.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)

		if ($label -eq $AccentButton)
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Primary'
		}
		elseif ($label -eq $DestructiveButton)
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Danger'
		}
		else
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Secondary'
		}

		$btnLabel = $label
		$dlgRef = $dlg
		$resRef = $resultRef
		$btn.Add_Click({
			$resRef.Value = $btnLabel
			$dlgRef.Close()
		}.GetNewClosure())

		$btnPanel.Children.Add($btn) | Out-Null
	}

	$btnBorder.Child = $btnPanel
	$outerStack.Children.Add($btnBorder) | Out-Null
	$dlg.Content = $outerStack

	$dlg.ShowDialog() | Out-Null
	return $resultRef.Value
}

function Show-ExecutionSummaryDialog
{
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Theme,

		[Parameter(Mandatory = $true)]
		[scriptblock]$ApplyButtonChrome,

		[object]$OwnerWindow,
		[object[]]$Results,
		[string]$Title = 'Execution Summary',
		[string]$SummaryText,
		[string]$LogPath,
		[string[]]$Buttons = @('Close')
	)

	$bc = [System.Windows.Media.BrushConverter]::new()
	$results = @($Results)

	$dlg = New-Object System.Windows.Window
	$dlg.Title = $Title
	$dlg.Width = 760
	$dlg.Height = 620
	$dlg.MinWidth = 680
	$dlg.MinHeight = 520
	$dlg.ResizeMode = 'CanResize'
	$dlg.WindowStartupLocation = 'CenterOwner'
	$dlg.Background = $bc.ConvertFromString($Theme.WindowBg)
	$dlg.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$dlg.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
	$dlg.FontSize = 13
	$dlg.ShowInTaskbar = $false
	$dlg.WindowStyle = 'SingleBorderWindow'

	try
	{
		if ($OwnerWindow)
		{
			$dlg.Owner = $OwnerWindow
		}
	}
	catch
	{
		$null = $_
	}

	$outerGrid = New-Object System.Windows.Controls.Grid
	$outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
	$outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
	$outerGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

	$headerBorder = New-Object System.Windows.Controls.Border
	$headerBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 16)
	$headerBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$headerBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
	[System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

	$headerStack = New-Object System.Windows.Controls.StackPanel
	$headerStack.Orientation = 'Vertical'

	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.Text = $Title
	$titleText.FontSize = 18
	$titleText.FontWeight = [System.Windows.FontWeights]::Bold
	$titleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
	$headerStack.Children.Add($titleText) | Out-Null

	if (-not [string]::IsNullOrWhiteSpace($SummaryText))
	{
		$summaryBlock = New-Object System.Windows.Controls.TextBlock
		$summaryBlock.Text = $SummaryText
		$summaryBlock.TextWrapping = 'Wrap'
		$summaryBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$summaryBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$headerStack.Children.Add($summaryBlock) | Out-Null
	}

	if (-not [string]::IsNullOrWhiteSpace($LogPath))
	{
		$logPathBlock = New-Object System.Windows.Controls.TextBlock
		$logPathBlock.Text = "Log file: $LogPath"
		$logPathBlock.TextWrapping = 'Wrap'
		$logPathBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
		$logPathBlock.Foreground = $bc.ConvertFromString($Theme.TextMuted)
		$logPathBlock.FontSize = 11
		$headerStack.Children.Add($logPathBlock) | Out-Null
	}

	$headerBorder.Child = $headerStack
	$outerGrid.Children.Add($headerBorder) | Out-Null

	$listScroll = New-Object System.Windows.Controls.ScrollViewer
	$listScroll.VerticalScrollBarVisibility = 'Auto'
	$listScroll.HorizontalScrollBarVisibility = 'Disabled'
	$listScroll.Margin = [System.Windows.Thickness]::new(0)
	[System.Windows.Controls.Grid]::SetRow($listScroll, 1)

	$listStack = New-Object System.Windows.Controls.StackPanel
	$listStack.Orientation = 'Vertical'
	$listStack.Margin = [System.Windows.Thickness]::new(18, 16, 18, 16)

	foreach ($result in $results)
	{
		$rowBorder = New-Object System.Windows.Controls.Border
		$rowBorder.Background = $bc.ConvertFromString($Theme.CardBg)
		$rowBorder.BorderBrush = $bc.ConvertFromString($Theme.CardBorder)
		$rowBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$rowBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$rowBorder.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
		$rowBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

		$rowStack = New-Object System.Windows.Controls.StackPanel
		$rowStack.Orientation = 'Vertical'

		$headerGrid = New-Object System.Windows.Controls.Grid
		$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
		$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

		$nameBlock = New-Object System.Windows.Controls.TextBlock
		$nameBlock.Text = [string]$result.Name
		$nameBlock.FontSize = 13
		$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
		$nameBlock.TextWrapping = 'Wrap'
		$nameBlock.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
		[System.Windows.Controls.Grid]::SetColumn($nameBlock, 0)
		$headerGrid.Children.Add($nameBlock) | Out-Null

		$statusBorder = New-Object System.Windows.Controls.Border
		$statusBorder.CornerRadius = [System.Windows.CornerRadius]::new(999)
		$statusBorder.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$statusBorder.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
		$statusBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$statusText = New-Object System.Windows.Controls.TextBlock
		$statusText.Text = [string]$result.Status
		$statusText.FontSize = 11
		$statusText.FontWeight = [System.Windows.FontWeights]::SemiBold

		switch ([string]$result.Status)
		{
			'Failed'
			{
				$statusBorder.Background = $bc.ConvertFromString($Theme.RiskHighBadgeBg)
				$statusBorder.BorderBrush = $bc.ConvertFromString($Theme.RiskHighBadge)
				$statusText.Foreground = $bc.ConvertFromString($Theme.RiskHighBadge)
			}
			'Preview'
			{
				$statusBorder.Background = $bc.ConvertFromString($Theme.StatusPillBg)
				$statusBorder.BorderBrush = $bc.ConvertFromString($Theme.StatusPillBorder)
				$statusText.Foreground = $bc.ConvertFromString($Theme.StatusPillText)
			}
			'Skipped'
			{
				$statusBorder.Background = $bc.ConvertFromString($Theme.TabBg)
				$statusBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
				$statusText.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
			}
			'Not Run'
			{
				$statusBorder.Background = $bc.ConvertFromString($Theme.TabBg)
				$statusBorder.BorderBrush = $bc.ConvertFromString($Theme.CautionBorder)
				$statusText.Foreground = $bc.ConvertFromString($Theme.CautionText)
			}
			default
			{
				$statusBorder.Background = $bc.ConvertFromString($Theme.LowRiskBadgeBg)
				$statusBorder.BorderBrush = $bc.ConvertFromString($Theme.LowRiskBadge)
				$statusText.Foreground = $bc.ConvertFromString($Theme.LowRiskBadge)
			}
		}

		$statusBorder.Child = $statusText
		[System.Windows.Controls.Grid]::SetColumn($statusBorder, 1)
		$headerGrid.Children.Add($statusBorder) | Out-Null
		$rowStack.Children.Add($headerGrid) | Out-Null

		$metaParts = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Category)) { $metaParts += [string]$result.Category }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Type)) { $metaParts += [string]$result.Type }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Selection)) { $metaParts += [string]$result.Selection }
		if (-not [string]::IsNullOrWhiteSpace([string]$result.Risk)) { $metaParts += ("{0} Risk" -f [string]$result.Risk) }
		if ($metaParts.Count -gt 0)
		{
			$metaBlock = New-Object System.Windows.Controls.TextBlock
			$metaBlock.Text = ($metaParts -join '  |  ')
			$metaBlock.TextWrapping = 'Wrap'
			$metaBlock.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
			$metaBlock.FontSize = 11
			$metaBlock.Foreground = $bc.ConvertFromString($Theme.TextMuted)
			$rowStack.Children.Add($metaBlock) | Out-Null
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$result.Detail))
		{
			$detailBlock = New-Object System.Windows.Controls.TextBlock
			$detailBlock.Text = [string]$result.Detail
			$detailBlock.TextWrapping = 'Wrap'
			$detailBlock.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
			$detailBlock.FontSize = 11
			$detailBlock.Foreground = $bc.ConvertFromString($(if ($result.Status -eq 'Failed' -or $result.Status -eq 'Not Run') { $Theme.CautionText } else { $Theme.TextSecondary }))
			$rowStack.Children.Add($detailBlock) | Out-Null
		}

		$rowBorder.Child = $rowStack
		$listStack.Children.Add($rowBorder) | Out-Null
	}

	if ($results.Count -eq 0)
	{
		$emptyBlock = New-Object System.Windows.Controls.TextBlock
		$emptyBlock.Text = 'No execution results are available for this run.'
		$emptyBlock.TextWrapping = 'Wrap'
		$emptyBlock.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$listStack.Children.Add($emptyBlock) | Out-Null
	}

	$listScroll.Content = $listStack
	$outerGrid.Children.Add($listScroll) | Out-Null

	$buttonBorder = New-Object System.Windows.Controls.Border
	$buttonBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
	$buttonBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
	$buttonBorder.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$buttonBorder.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
	[System.Windows.Controls.Grid]::SetRow($buttonBorder, 2)

	$buttonPanel = New-Object System.Windows.Controls.StackPanel
	$buttonPanel.Orientation = 'Horizontal'
	$buttonPanel.HorizontalAlignment = 'Right'

	$resultRef = @{
		Value = $(if ($Buttons -contains 'Close') { 'Close' } elseif ($Buttons.Count -gt 0) { $Buttons[0] } else { $null })
	}

	foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
		$btn.MinWidth = 112
		$btn.Height = 34
		$btn.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Padding = [System.Windows.Thickness]::new(16, 7, 16, 7)

		if ($label -eq 'Exit')
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Danger'
		}
		elseif ($label -eq 'Close')
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Primary'
		}
		else
		{
			& $ApplyButtonChrome -Button $btn -Variant 'Secondary'
		}

		$btnLabel = $label
		$dlgRef = $dlg
		$resRef = $resultRef
		$btn.Add_Click({
			$resRef.Value = $btnLabel
			$dlgRef.Close()
		}.GetNewClosure())
		$buttonPanel.Children.Add($btn) | Out-Null
	}

	$buttonBorder.Child = $buttonPanel
	$outerGrid.Children.Add($buttonBorder) | Out-Null
	$dlg.Content = $outerGrid

	$dlg.ShowDialog() | Out-Null
	return $resultRef.Value
}

function Get-GuiSettingsProfileDirectory
{
	param (
		[string]$AppName = 'Baseline'
	)

	$baseDir = if ($env:LOCALAPPDATA)
	{
		Join-Path $env:LOCALAPPDATA "$AppName\Profiles"
	}
	else
	{
		Join-Path $env:TEMP "$AppName\Profiles"
	}

	try
	{
		if (-not (Test-Path -LiteralPath $baseDir))
		{
			New-Item -ItemType Directory -Path $baseDir -Force -ErrorAction Stop | Out-Null
		}
	}
	catch
	{
		$null = $_
	}

	return $baseDir
}

function Get-GuiSessionStatePath
{
	param (
		[string]$AppName = 'Baseline'
	)

	return (Join-Path (Get-GuiSettingsProfileDirectory -AppName $AppName) "$AppName-last-session.json")
}

function Save-GuiSessionStateDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,

		[string]$AppName = 'Baseline'
	)

	try
	{
		$sessionState = [ordered]@{
			Schema = "$AppName.GuiSession"
			SchemaVersion = 1
			SavedAt = (Get-Date).ToString('o')
			State = $Snapshot
		}
		($sessionState | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath (Get-GuiSessionStatePath -AppName $AppName) -Encoding UTF8 -Force
		LogInfo "Saved GUI session state."
		return $true
	}
	catch
	{
		LogWarning "Failed to save GUI session state: $($_.Exception.Message)"
		return $false
	}
}

function Read-GuiSessionStateDocument
{
	param (
		[string]$AppName = 'Baseline',
		[string]$ExpectedSchema = 'Baseline.GuiSettings'
	)

	$sessionPath = Get-GuiSessionStatePath -AppName $AppName
	if (-not (Test-Path -LiteralPath $sessionPath))
	{
		return $null
	}

	try
	{
		$raw = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 -ErrorAction Stop
		$sessionPayload = $raw | ConvertFrom-Json -ErrorAction Stop
	}
	catch
	{
		LogWarning "Failed to read GUI session state: $($_.Exception.Message)"
		return $null
	}

	$snapshot = if ($sessionPayload.PSObject.Properties['State']) { $sessionPayload.State } else { $sessionPayload }
	if (
		-not $snapshot -or
		($snapshot.PSObject.Properties['Schema'] -and [string]$snapshot.Schema -ne $ExpectedSchema) -or
		-not $snapshot.PSObject.Properties['Controls']
	)
	{
		LogWarning 'The saved GUI session state is invalid and was ignored.'
		return $null
	}

	return $snapshot
}

function Show-GuiSettingsSaveDialog
{
	param (
		[string]$AppName = 'Baseline'
	)

	$saveDialog = New-Object Microsoft.Win32.SaveFileDialog
	$saveDialog.Filter = "$AppName Settings (*.json)|*.json|All Files (*.*)|*.*"
	$saveDialog.InitialDirectory = Get-GuiSettingsProfileDirectory -AppName $AppName
	$saveDialog.FileName = "$AppName-settings-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')

	if ($saveDialog.ShowDialog() -eq $true)
	{
		return $saveDialog.FileName
	}

	return $null
}

function Show-GuiSettingsOpenDialog
{
	param (
		[string]$AppName = 'Baseline'
	)

	$openDialog = New-Object Microsoft.Win32.OpenFileDialog
	$openDialog.Filter = "$AppName Settings (*.json)|*.json|All Files (*.*)|*.*"
	$openDialog.InitialDirectory = Get-GuiSettingsProfileDirectory -AppName $AppName
	$openDialog.Multiselect = $false

	if ($openDialog.ShowDialog() -eq $true)
	{
		return $openDialog.FileName
	}

	return $null
}

function Write-GuiSettingsProfileDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[object]$Snapshot,

		[Parameter(Mandatory = $true)]
		[string]$FilePath
	)

	($Snapshot | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $FilePath -Encoding UTF8 -Force
	return $true
}

function Read-GuiSettingsProfileDocument
{
	param (
		[Parameter(Mandatory = $true)]
		[string]$FilePath,

		[string]$ExpectedSchema = 'Baseline.GuiSettings'
	)

	$raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
	$parsedProfile = $raw | ConvertFrom-Json -ErrorAction Stop
	$snapshot = if ($parsedProfile.PSObject.Properties['State']) { $parsedProfile.State } else { $parsedProfile }

	if (
		-not $snapshot -or
		($snapshot.PSObject.Properties['Schema'] -and [string]$snapshot.Schema -ne $ExpectedSchema) -or
		-not $snapshot.PSObject.Properties['Controls']
	)
	{
		throw 'The selected file does not contain a valid Baseline settings profile.'
	}

	return $snapshot
}

Export-ModuleMember -Function @(
	'Show-ThemedDialog'
	'Show-ExecutionSummaryDialog'
	'Get-GuiSettingsProfileDirectory'
	'Get-GuiSessionStatePath'
	'Save-GuiSessionStateDocument'
	'Read-GuiSessionStateDocument'
	'Show-GuiSettingsSaveDialog'
	'Show-GuiSettingsOpenDialog'
	'Write-GuiSettingsProfileDocument'
	'Read-GuiSettingsProfileDocument'
)
