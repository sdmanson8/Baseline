foreach ($label in $Buttons)
	{
		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = $label
		$btn.MinWidth = $Script:GuiLayout.ButtonMinWidth
		$btn.Height = $Script:GuiLayout.ButtonHeight
		$btn.Margin = [System.Windows.Thickness]::new(6, 4, 0, 4)
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
		if ($Buttons.Count -eq 1)
		{
			$btn.IsDefault = $true
		}
		if ($label -eq 'Close')
		{
			$btn.IsCancel = $true
		}

		$btnLabel = $label
		$dlgRef = $dlg
		$resRef = $resultRef
		$btn.Add_Click({
			$resRef.Value = $btnLabel
			$dlgRef.Close()
		}.GetNewClosure())
		[void]($buttonPanel.Children.Add($btn))
	}
