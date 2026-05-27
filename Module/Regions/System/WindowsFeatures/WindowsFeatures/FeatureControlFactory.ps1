function Add-FeatureControl
	{
		[CmdletBinding()]
		param
		(
			[Parameter(
				Mandatory = $true,
				ValueFromPipeline = $true
			)]
			[ValidateNotNull()]
			$Feature
		)

		process
		{
			$CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
			$CheckBox.Add_Click({Update-FeatureSelectionFromCheckbox -CheckBox $_.Source})
			$CheckBox.Tag = $Feature
			$CheckBox.VerticalAlignment = 'Center'
			$CheckBox.Margin = [System.Windows.Thickness]::new(10, 10, 5, 10)

			$FeatureLabel = Get-FeatureFriendlyName -FeatureName $Feature.FeatureName -DisplayName $Feature.DisplayName
			$tooltipText = if (-not [string]::IsNullOrWhiteSpace($Feature.Description))
			{
				[string]$Feature.Description
			}
			elseif (-not [string]::IsNullOrWhiteSpace($Feature.DisplayName))
			{
				"Windows feature: $($Feature.DisplayName)"
			}
			else
			{
				"Windows feature: $FeatureLabel"
			}

			$LabelPanel = New-Object -TypeName System.Windows.Controls.StackPanel
			$LabelPanel.Orientation = 'Horizontal'
			$LabelPanel.VerticalAlignment = 'Center'
			$LabelPanel.HorizontalAlignment = 'Stretch'

			$TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
			$TextBlock.Text = $FeatureLabel
			$TextBlock.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
			if ($Form -and $Form.Foreground) { $TextBlock.Foreground = $Form.Foreground }
			$TextBlock.VerticalAlignment = 'Center'
			$TextBlock.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
			[void]$LabelPanel.Children.Add($TextBlock)

			$infoIcon = New-FeatureInfoIcon -TooltipText $tooltipText

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

			if (Test-FeatureSeedSelected -Feature $Feature)
			{
				[void]$SelectedFeatures.Add($Feature)
			}
			else
			{
				$CheckBox.IsChecked = $false
			}

			if ($null -ne $Button)
			{
				$Button.IsEnabled = ($SelectedFeatures.Count -gt 0)
			}
		}
	}
	#endregion Functions

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			$State           = @("Disabled", "DisablePending")
			$ButtonContent   = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceEnable' -Fallback 'Enable'
			$ButtonAdd_Click = {
				param
				(
					[object[]]
					$FeatureList
				)

				EnableButton -FeatureList $FeatureList
			}
		}
		"Disable"
		{
			$State           = @("Enabled", "EnablePending")
			$ButtonContent   = GUICommon\Get-GuiPopupLocalizedString -Key 'GuiChoiceDisable' -Fallback 'Disable'
			$ButtonAdd_Click = {
				param
				(
					[object[]]
					$FeatureList
				)

				DisableButton -FeatureList $FeatureList
			}
		}
	}
