$selectComboByTag = {
			param ($combo, $tag)
			if (-not $combo) { return }
			for ($i = 0; $i -lt $combo.Items.Count; $i++)
			{
				if ([string]$combo.Items[$i].Tag -eq [string]$tag)
				{
					$combo.SelectedIndex = $i
					return
				}
			}
			if ($combo.Items.Count -gt 0) { $combo.SelectedIndex = 0 }
		}
