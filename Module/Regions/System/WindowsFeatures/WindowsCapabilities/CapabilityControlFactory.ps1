function Add-CapabilityControl
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$Capability
		)

		process
		{
			$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
			$CheckBox.Add_Click({Update-CapabilitySelectionFromCheckbox -CheckBox $_.Source})
			$CheckBox.Tag = $Capability
			$CheckBox.VerticalAlignment = 'Center'
			$CheckBox.Margin = [System.Windows.Thickness]::new(10, 10, 5, 10)

			$CapabilityLabel = Get-CapabilityFriendlyName -Name $Capability.Name -DisplayName $Capability.DisplayName
			$tooltipText = if (-not [string]::IsNullOrWhiteSpace($Capability.Description))
			{
				[string]$Capability.Description
			}
			elseif (-not [string]::IsNullOrWhiteSpace($Capability.DisplayName))
			{
				"Optional feature: $($Capability.DisplayName)"
			}
			else
			{
				"Optional feature: $CapabilityLabel"
			}

			$LabelPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$LabelPanel.Orientation = 'Horizontal'
			$LabelPanel.VerticalAlignment = 'Center'
			$LabelPanel.HorizontalAlignment = 'Stretch'

			$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
			$TextBlock.Text = $CapabilityLabel
			$TextBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			if ($Form -and $Form.Foreground) { $TextBlock.Foreground = $Form.Foreground }
			$TextBlock.VerticalAlignment = 'Center'
			$TextBlock.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
			[void]$LabelPanel.Children.Add($TextBlock)

			$infoIcon = New-CapabilityInfoIcon -TooltipText $tooltipText

			$rowPanel = New-Object -TypeName System.Windows.Controls.DockPanel
			$rowPanel.LastChildFill = $true
			$rowPanel.HorizontalAlignment = 'Stretch'
			$rowPanel.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)

			[System.Windows.Controls.DockPanel]::SetDock($CheckBox, [System.Windows.Controls.Dock]::Left)
			[void]$rowPanel.Children.Add($CheckBox)

			$infoPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$infoPanel.Orientation = 'Horizontal'
			$infoPanel.VerticalAlignment = 'Center'
			$infoPanel.HorizontalAlignment = 'Right'
			$infoPanel.Margin = [System.Windows.Thickness]::new(8, 0, 10, 0)
			[void]$infoPanel.Children.Add($infoIcon)

			[System.Windows.Controls.DockPanel]::SetDock($infoPanel, [System.Windows.Controls.Dock]::Right)
			[void]$rowPanel.Children.Add($infoPanel)

			[void]$rowPanel.Children.Add($LabelPanel)
			[void]$PanelContainer.Children.Add($rowPanel)

			if (Test-CapabilitySeedSelected -Capability $Capability)
			{
				[void]$SelectedCapabilities.Add($Capability)
			}
			else
			{
				$CheckBox.IsChecked = $false
			}

			if ($null -ne $Button)
			{
				$Button.IsEnabled = ($SelectedCapabilities.Count -gt 0)
			}
		}
	}
