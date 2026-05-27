if ($btnDownloadBaseline)
		{
			# "Check for Update" has been moved to the Help menu. Hide the in-dialog button.
			$btnDownloadBaseline.Visibility = [System.Windows.Visibility]::Collapsed
			$btnDownloadBaseline.Content = $downloadLabel
			Set-ButtonChrome -Button $btnDownloadBaseline -Variant 'Primary' -Compact
			Register-GuiEventHandler -Source $btnDownloadBaseline -EventName 'Click' -Handler ({
				$btnDownloadBaseline.IsEnabled = $false
				$btnDownloadBaseline.Content = $downloadingLabel
				$btnClose.IsEnabled = $false

				if ($downloadProgressPanel)
				{
					$downloadProgressPanel.Visibility = [System.Windows.Visibility]::Visible
				}
				if ($downloadProgressBar)
				{
					$downloadProgressBar.Value = 0
				}
				if ($txtDownloadProgressPct)
				{
					$txtDownloadProgressPct.Text = '0%'
				}
				if ($txtDownloadProgressLabel)
				{
					$txtDownloadProgressLabel.Text = $downloadPreparingLabel
				}

				try
				{
					$destinationPath = Join-Path (Join-Path ([System.Environment]::GetFolderPath('UserProfile')) 'Downloads\Baseline') 'Baseline.exe'
					$destinationDirectory = Split-Path -Path $destinationPath -Parent
					if (-not (Test-Path -LiteralPath $destinationDirectory))
					{
						New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
					}

					if (Test-Path -LiteralPath $destinationPath)
					{
						Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
					}

					$releaseAsset = Get-BaselineLatestReleaseAssetUrl -Owner 'sdmanson8' -Repository 'Baseline' -AssetName 'Baseline.exe'
					$expectedBytes = if ($releaseAsset.PSObject.Properties['SizeBytes']) { [long]$releaseAsset.SizeBytes } else { 0L }

					$writePackageHelperWarningDefinition = (Get-Command -Name 'Write-PackageHelperWarning' -CommandType Function -ErrorAction Stop).Definition
					$setDownloadSecurityProtocolDefinition = (Get-Command -Name 'Set-DownloadSecurityProtocol' -CommandType Function -ErrorAction Stop).Definition
					$invokeDownloadFileDefinition = (Get-Command -Name 'Invoke-DownloadFile' -CommandType Function -ErrorAction Stop).Definition
					$downloadScript = @(
						$writePackageHelperWarningDefinition
						$setDownloadSecurityProtocolDefinition
						$invokeDownloadFileDefinition
						'param([string]$dlUri, [string]$dlPath)'
						'Invoke-DownloadFile -Uri $dlUri -OutFile $dlPath'
					) -join [System.Environment]::NewLine

					$runspace = [runspacefactory]::CreateRunspace()
					$runspace.Open()
					$downloadPowerShell = [powershell]::Create()
					$downloadPowerShell.Runspace = $runspace
					$null = $downloadPowerShell.AddScript($downloadScript).AddArgument([string]$releaseAsset.DownloadUrl).AddArgument([string]$destinationPath)
					$downloadHandle = $downloadPowerShell.BeginInvoke()

					$downloadTimer = [System.Windows.Threading.DispatcherTimer]::new()
					$downloadTimer.Interval = [System.TimeSpan]::FromMilliseconds(250)
					$downloadTimer.Add_Tick({
						if (Test-Path -LiteralPath $destinationPath)
						{
							$currentBytes = (Get-Item -LiteralPath $destinationPath).Length
							$pct = 0
							if ($expectedBytes -gt 0)
							{
								$pct = [int][Math]::Min(100, [Math]::Round(($currentBytes / $expectedBytes) * 100))
							}

							if ($downloadProgressBar)
							{
								$downloadProgressBar.Value = $pct
							}
							if ($txtDownloadProgressPct)
							{
								$txtDownloadProgressPct.Text = "$pct%"
							}

							if ($txtDownloadProgressLabel)
							{
								if ($expectedBytes -gt 0)
								{
									$currentMB = [Math]::Round($currentBytes / 1MB, 1)
									$totalMB = [Math]::Round($expectedBytes / 1MB, 1)
									$txtDownloadProgressLabel.Text = "${downloadProgressLabel} ($currentMB MB / $totalMB MB)"
								}
								else
								{
									$currentMB = [Math]::Round($currentBytes / 1MB, 1)
									$txtDownloadProgressLabel.Text = "${downloadProgressLabel} ($currentMB MB)"
								}
							}
						}

						if ($downloadHandle.IsCompleted)
						{
							$downloadTimer.Stop()
							try
							{
								$downloadPowerShell.EndInvoke($downloadHandle) | Out-Null
								if ($downloadProgressBar)
								{
									$downloadProgressBar.Value = 100
								}
								if ($txtDownloadProgressPct)
								{
									$txtDownloadProgressPct.Text = '100%'
								}
								if ($txtDownloadProgressLabel)
								{
									$txtDownloadProgressLabel.Text = $downloadCompleteLabel
								}

								$downloadMessage = (& $getBaselineBilingualString -Key 'GuiDownloadBaselineCompletedMessage' -Fallback 'Saved {0} ({1}) to:`n`n{2}' -FormatArgs @($releaseAsset.AssetName, $releaseAsset.TagName, $destinationPath))
								Show-ThemedDialog -Title $downloadCompletedTitle -Message $downloadMessage -Buttons @($okLabel) -AccentButton $okLabel
							}
							catch
							{
								if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\ContentDialogs\Show-HelpDialog\Show-HelpDialog.ps1:123' -Severity Debug }

								if ($downloadProgressBar)
								{
									$downloadProgressBar.Value = 0
								}
								if ($txtDownloadProgressPct)
								{
									$txtDownloadProgressPct.Text = $downloadFailedLabel
								}
								if ($txtDownloadProgressLabel)
								{
									$txtDownloadProgressLabel.Text = $downloadFailedLabel
								}

								$downloadErrorMessage = (& $getBaselineBilingualString -Key 'GuiDownloadBaselineFailedMessage' -Fallback 'Failed to download the latest Baseline.exe release asset.`n`n{0}' -FormatArgs @($_.Exception.Message))
								Show-ThemedDialog -Title $downloadFailedTitle -Message $downloadErrorMessage -Buttons @($okLabel) -AccentButton $okLabel
							}
							finally
							{
								$downloadPowerShell.Dispose()
								$runspace.Dispose()
								$btnDownloadBaseline.IsEnabled = $true
								$btnClose.IsEnabled = $true
								$btnDownloadBaseline.Content = $downloadLabel
							}
						}
					}.GetNewClosure())
					$downloadTimer.Start()
				}
				catch
				{
					if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'Module\GUI\DialogHelpers\ContentDialogs\Show-HelpDialog\Show-HelpDialog.ps1:153' -Severity Debug }

					$downloadErrorMessage = (& $getBaselineBilingualString -Key 'GuiDownloadBaselineFailedMessage' -Fallback 'Failed to download the latest Baseline.exe release asset.`n`n{0}' -FormatArgs @($_.Exception.Message))
					Show-ThemedDialog -Title $downloadFailedTitle -Message $downloadErrorMessage -Buttons @($okLabel) -AccentButton $okLabel
					$btnDownloadBaseline.IsEnabled = $true
					$btnClose.IsEnabled = $true
					$btnDownloadBaseline.Content = $downloadLabel
				}
			}.GetNewClosure())
			if ($StartUpdateCheck)
			{
				$dlg.Add_ContentRendered({
					try
					{
						$btnDownloadBaseline.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $btnDownloadBaseline))
					}
					catch { Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiReleaseStatusDialog.RaiseDownloadBaselineClick' }
				}.GetNewClosure())
			}
		}

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
				$col1.Width = [System.Windows.GridLength]::Auto
				$col2 = [System.Windows.Controls.ColumnDefinition]::new()
				$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				[void]($row.ColumnDefinitions.Add($col1))
				[void]($row.ColumnDefinitions.Add($col2))
				$row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

				$bullet = [System.Windows.Controls.TextBlock]::new()
				$bullet.Text = [char]0x2022
				$bullet.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
				$bullet.FontSize = $Script:GuiLayout.FontSizeSubheading
				$bullet.Foreground = $bc.ConvertFromString($theme.AccentBlue)
				$bullet.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
				$bullet.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
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
