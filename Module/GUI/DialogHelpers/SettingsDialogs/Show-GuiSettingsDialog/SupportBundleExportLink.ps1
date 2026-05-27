if ($btnSettingsExportSupportBundle)
		{
			if ($btnSettingsExportSupportBundle.Content -is [System.Windows.Controls.TextBlock])
			{
				$btnSettingsExportSupportBundle.Content.Text = $openExportBundleButtonLabel
			}
			else
			{
				$btnSettingsExportSupportBundle.Content = $openExportBundleButtonLabel
			}
			$btnSettingsExportSupportBundle.Cursor = [System.Windows.Input.Cursors]::Hand
			$btnSettingsExportSupportBundle.Foreground = $settingsAccentBrush
			$btnSettingsExportSupportBundle.Background = [System.Windows.Media.Brushes]::Transparent
			$btnSettingsExportSupportBundle.BorderBrush = [System.Windows.Media.Brushes]::Transparent
			$btnSettingsExportSupportBundle.BorderThickness = [System.Windows.Thickness]::new(0)
			$btnSettingsExportSupportBundle.Padding = [System.Windows.Thickness]::new(0)
			$exportBundleMenuItem = $Script:MenuToolsExportSupportBundle
			$btnSettingsExportSupportBundle.IsEnabled = [bool]($exportBundleMenuItem -and $exportBundleMenuItem.IsEnabled)
			$btnSettingsExportSupportBundle.Add_Click({
				if (-not $exportBundleMenuItem) { return }
				try
				{
					$eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent)
					$exportBundleMenuItem.RaiseEvent($eventArgs)
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'DialogHelpers.ShowGuiSettingsDialog.ExportSupportBundleShortcut'
				}
			}.GetNewClosure())
		}
