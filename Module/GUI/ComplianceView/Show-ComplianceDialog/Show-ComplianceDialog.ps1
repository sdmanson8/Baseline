$btnBrowse.Add_Click({
		$openDialog = New-Object Microsoft.Win32.OpenFileDialog
		$openDialog.Title = (& $getLocalizedString -Key 'GuiComplianceBrowseTitle' -Fallback 'Select Configuration Profile or Snapshot')
		$openDialog.Filter = 'JSON Files (*.json)|*.json|All Files (*.*)|*.*'
		$openDialog.DefaultExt = 'json'

		$dlgOwner = if ($Script:MainForm) { $Script:MainForm } else { $null }
		if ($openDialog.ShowDialog($dlgOwner) -eq $true)
		{
			$complianceState.FilePath = $openDialog.FileName
			$txtFilePath.Text = $openDialog.FileName
			$btnCheck.IsEnabled = $true
			$summaryLabel.Text = ''
			$resultsList.Children.Clear()
			$btnFixDrift.IsEnabled = $false
			$complianceState.Report = $null
		}
	}.GetNewClosure())

	# --- Check Compliance handler ---
	$btnCheck.Add_Click({
		$filePath = $complianceState.FilePath
		if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath -ErrorAction SilentlyContinue))
		{
			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiComplianceTitle' -Fallback 'Check Compliance') -Message (& $getLocalizedString -Key 'GuiComplianceSelectValid' -Fallback 'Please select a valid profile or snapshot file.') -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$resultsList.Children.Clear()
		$summaryLabel.Text = (& $getLocalizedString -Key 'GuiComplianceChecking' -Fallback 'Checking compliance...')
		# Flush dispatcher so 'Checking compliance...' renders before the blocking work.
		# Uses direct dispatcher call because .GetNewClosure() doesn't capture functions.
		try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'ComplianceView.ShowComplianceDialog.DispatcherYield' }

		try
		{
			$raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8 -ErrorAction Stop
			$profileData = $raw | ConvertFrom-BaselineJson -Depth 16 -ErrorAction Stop
			$complianceState.ProfileData = $profileData
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ComplianceView\Show-ComplianceDialog\Show-ComplianceDialog.ps1:41' -Severity Debug }

			$summaryLabel.Text = (& $getLocalizedString -Key 'GuiComplianceLoadFailed' -Fallback 'Failed to load profile.')
			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiComplianceTitle' -Fallback 'Check Compliance') -Message ((& $getLocalizedString -Key 'GuiComplianceLoadFailedDetail' -Fallback "Failed to read profile file.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
			return
		}

		$remoteContext = $null
		try
		{
			$remoteContext = Get-GuiRemoteTargetContext
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'ComplianceView.ShowComplianceDialog.GetRemoteTargetContext'
			$remoteContext = $null
		}

		if ($remoteContext -and $remoteContext.Connected -and $remoteContext.TargetComputers.Count -gt 0 -and $profileData.PSObject.Properties['Schema'] -and [string]$profileData.Schema -eq 'Baseline.ConfigProfile')
		{
			try
			{
				$remoteResults = @(Invoke-BaselineRemoteCompliance -ComputerName @($remoteContext.TargetComputers) -ProfilePath $filePath -Credential $remoteContext.Credential)
				$syntheticEntries = [System.Collections.Generic.List[object]]::new()
				$compliantCount = 0
				$driftedCount = 0
				foreach ($remoteResult in @($remoteResults))
				{
					if (-not $remoteResult) { continue }

					$remoteErrors = @()
					if ($remoteResult.PSObject.Properties['Errors'] -and $remoteResult.Errors)
					{
						$remoteErrors = @($remoteResult.Errors | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
					}

					$isCompliant = ($remoteResult.Compliant -eq $true) -and ($remoteErrors.Count -eq 0)
					if ($isCompliant)
					{
						$compliantCount++
					}
					else
					{
						$driftedCount++
					}

					[void]$syntheticEntries.Add([pscustomobject]@{
						Name         = [string]$remoteResult.ComputerName
						Status       = if ($isCompliant) { 'Compliant' } else { 'Drifted' }
						Detail       = if ($remoteErrors.Count -gt 0) { $remoteErrors -join '; ' } else { ('DriftedCount={0} | TotalChecked={1}' -f ([int]$remoteResult.DriftedCount), ([int]$remoteResult.TotalChecked)) }
						TotalChecked = [int]$remoteResult.TotalChecked
						DriftedCount = [int]$remoteResult.DriftedCount
						Errors       = @($remoteErrors)
					})
				}

				$report = [pscustomobject]@{
					Compliant = $compliantCount
					Drifted   = $driftedCount
					Unknown   = 0
					Entries   = @($syntheticEntries)
				}
				$complianceState.Report = $report
				$summaryLabel.Text = ((& $getLocalizedString -Key 'GuiComplianceSummaryFormat' -Fallback 'Compliant: {0} | Drifted: {1} | Unknown: {2}') -f $report.Compliant, $report.Drifted, $report.Unknown)
				$btnFixDrift.IsEnabled = $false
				$resultsList.Children.Clear()
				foreach ($entry in @($report.Entries))
				{
					if (-not $entry) { continue }

					$card = New-Object System.Windows.Controls.Border
					$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
					$card.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
					$card.CornerRadius = [System.Windows.CornerRadius]::new($layout.BorderRadiusSmall)
					$card.BorderThickness = [System.Windows.Thickness]::new(1)
					$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
					$card.Background = $bc.ConvertFromString($theme.PanelBg)

					$stack = New-Object System.Windows.Controls.StackPanel
					$stack.Orientation = 'Vertical'

					$title = New-Object System.Windows.Controls.TextBlock
					$title.Text = [string]$entry.Name
					$title.FontWeight = [System.Windows.FontWeights]::SemiBold
					$title.Foreground = $bc.ConvertFromString($theme.TextPrimary)
					[void]$stack.Children.Add($title)

					$detail = New-Object System.Windows.Controls.TextBlock
					$detail.Text = ("Status: {0} | {1}" -f [string]$entry.Status, [string]$entry.Detail)
					$detail.TextWrapping = 'Wrap'
					$detail.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					[void]$stack.Children.Add($detail)

					$card.Child = $stack
					[void]$resultsList.Children.Add($card)
				}

				$summaryLabel.Text = ("Remote compliance: Compliant targets {0} | Drifted targets {1}" -f $compliantCount, $driftedCount)
				return
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ComplianceView\Show-ComplianceDialog\Show-ComplianceDialog.ps1:141' -Severity Debug }

				$summaryLabel.Text = (& $getLocalizedString -Key 'GuiComplianceCheckFailed' -Fallback 'Compliance check failed.')
				Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiComplianceTitle' -Fallback 'Check Compliance') -Message ((& $getLocalizedString -Key 'GuiComplianceCheckFailedDetail' -Fallback "Compliance check failed.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
				return
			}
		}

		try
		{
			$report = Test-SystemCompliance -Profile $profileData -Manifest $Script:TweakManifest
			$complianceState.Report = $report
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\ComplianceView\Show-ComplianceDialog\Show-ComplianceDialog.ps1:154' -Severity Debug }

			$summaryLabel.Text = (& $getLocalizedString -Key 'GuiComplianceCheckFailed' -Fallback 'Compliance check failed.')
			Show-ThemedDialog -Title (& $getLocalizedString -Key 'GuiComplianceTitle' -Fallback 'Check Compliance') -Message ((& $getLocalizedString -Key 'GuiComplianceCheckFailedDetail' -Fallback "Compliance check failed.`n`n{0}") -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK'
			return
		}

		# Update summary
		$summaryLabel.Text = ((& $getLocalizedString -Key 'GuiComplianceSummaryFormat' -Fallback 'Compliant: {0} | Drifted: {1} | Unknown: {2}') -f $report.Compliant, $report.Drifted, $report.Unknown)

		# Enable Fix Drift only if drifted items exist
		$btnFixDrift.IsEnabled = ($report.Drifted -gt 0)

		# Populate results list
		$resultsList.Children.Clear()
		foreach ($entry in @($report.Entries))
		{
			if (-not $entry) { continue }

			$card = New-Object System.Windows.Controls.Border
			$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
			$card.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
			$card.CornerRadius = [System.Windows.CornerRadius]::new($layout.BorderRadiusSmall)
			$card.BorderThickness = [System.Windows.Thickness]::new(1)
			$card.BorderBrush = $bc.ConvertFromString($theme.BorderColor)
			$card.Background = $bc.ConvertFromString($theme.PanelBg)

			$cardGrid = New-Object System.Windows.Controls.Grid
			$col1 = New-Object System.Windows.Controls.ColumnDefinition
			$col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			$col2 = New-Object System.Windows.Controls.ColumnDefinition
			$col2.Width = [System.Windows.GridLength]::new(100)
			$col3 = New-Object System.Windows.Controls.ColumnDefinition
			$col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			[void]$cardGrid.ColumnDefinitions.Add($col1)
			[void]$cardGrid.ColumnDefinitions.Add($col2)
			[void]$cardGrid.ColumnDefinitions.Add($col3)

			$statusColor = switch ([string]$entry.Status)
			{
				'Compliant' { '#35D07F' }
				'Drifted'   { '#EF4444' }
				default     { '#9CA3AF' }
			}
			$statusGlyph = switch ([string]$entry.Status)
			{
				'Compliant' { [char]0xF299 }
				default     { [char]0xF36E }
			}

			# Name
			$nameGrid = New-Object System.Windows.Controls.Grid
			$nameGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
			$nameGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
			$nameGrid.ColumnDefinitions[0].Width = [System.Windows.GridLength]::Auto
			$nameGrid.ColumnDefinitions[1].Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
			[System.Windows.Controls.Grid]::SetColumn($nameGrid, 0)

			$nameIcon = New-Object System.Windows.Controls.TextBlock
			$nameIcon.Text = $statusGlyph
			$nameIcon.FontFamily = [System.Windows.Media.FontFamily]::new('FluentSystemIcons')
			$nameIcon.FontSize = 14
			$nameIcon.VerticalAlignment = 'Center'
			$nameIcon.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
			$nameIcon.Foreground = $bc.ConvertFromString($statusColor)
			[System.Windows.Controls.Grid]::SetColumn($nameIcon, 0)

			$nameBlock = New-Object System.Windows.Controls.TextBlock
			$nameBlock.Text = [string]$entry.Name
			$nameBlock.VerticalAlignment = 'Center'
			$nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
			$nameBlock.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			$nameBlock.TextTrimming = 'CharacterEllipsis'
			[System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

			# Status badge
			$statusBlock = New-Object System.Windows.Controls.TextBlock
			$statusBlock.Text = [string]$entry.Status
			$statusBlock.HorizontalAlignment = 'Center'
			$statusBlock.VerticalAlignment = 'Center'
			$statusBlock.FontWeight = [System.Windows.FontWeights]::Bold
			$statusBlock.Foreground = $bc.ConvertFromString($statusColor)
			[System.Windows.Controls.Grid]::SetColumn($statusBlock, 1)

			# Values: current vs desired
			$valuesBlock = New-Object System.Windows.Controls.TextBlock
			$desiredText = if ($null -ne $entry.DesiredState) { [string]$entry.DesiredState } else { '(null)' }
			$actualText = if ($null -ne $entry.ActualState) { [string]$entry.ActualState } else { '(null)' }
			$valuesBlock.Text = ((& $getLocalizedString -Key 'GuiComplianceCurrentDesiredFormat' -Fallback 'Current: {0} | Desired: {1}') -f $actualText, $desiredText)
			$valuesBlock.VerticalAlignment = 'Center'
			$valuesBlock.FontSize = $layout.FontSizeSmall
			$valuesBlock.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$valuesBlock.TextTrimming = 'CharacterEllipsis'
			$valuesBlock.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
			[System.Windows.Controls.Grid]::SetColumn($valuesBlock, 2)

			[void]$nameGrid.Children.Add($nameIcon)
			[void]$nameGrid.Children.Add($nameBlock)
			[void]$cardGrid.Children.Add($nameGrid)
			[void]$cardGrid.Children.Add($statusBlock)
			[void]$cardGrid.Children.Add($valuesBlock)
			$card.Child = $cardGrid
			[void]$resultsList.Children.Add($card)
		}

		if ($report.Entries.Count -eq 0)
		{
			$emptyLabel = New-Object System.Windows.Controls.TextBlock
			$emptyLabel.Text = (& $getLocalizedString -Key 'GuiComplianceNoEntries' -Fallback 'No entries found in the selected profile.')
			$emptyLabel.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$emptyLabel.HorizontalAlignment = 'Center'
			$emptyLabel.Margin = [System.Windows.Thickness]::new(0, 20, 0, 0)
			[void]$resultsList.Children.Add($emptyLabel)
		}
	}.GetNewClosure())
