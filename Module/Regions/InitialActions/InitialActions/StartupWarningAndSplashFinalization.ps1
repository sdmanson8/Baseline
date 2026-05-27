if ($Warning)
	{
		# Get the name of a preset (e.g Bootstrap/Baseline.ps1) regardless if it was named
		# $_.File has no EndsWith() method
		[string]$PresetName = ((Get-PSCallStack).Position | Where-Object -FilterScript {$_.File}).File | Where-Object -FilterScript {$_.EndsWith(".ps1")}
		LogWarning (Get-BaselineBilingualString -Key 'CustomizationWarning' -Fallback 'Have you customized every function in the {0} preset file before running Baseline | Windows Utility?' -FormatArgs @("`"$PresetName`""))
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_ShowingMainMenuWaitingForInput' -Fallback 'Showing Main Menu, waiting for input')

		do
		{
			$Choice = Show-Menu -Menu @($Script:Yes, $Script:No) -Default 2

			switch ($Choice)
			{
				$Script:Yes
				{
					continue
				}
				$Script:No
				{
					Invoke-Item -Path $PresetName
					Start-Sleep -Seconds 5
				}
				$Script:KeyboardArrows {}
			}
		}
		until ($Choice -ne $Script:KeyboardArrows)
	}
