try
	{
		$startupSplashMaximized = $false
		if ($startupSplashHandle -is [hashtable] -and $startupSplashHandle.ContainsKey('WindowMaximized'))
		{
			$startupSplashMaximized = [bool]$startupSplashHandle['WindowMaximized']
		}
		if ($startupSplashMaximized)
		{
			if ($Form.IsSourceInitialized)
			{
				Set-GuiMainWindowWorkAreaMaximized -Window $Form -Maximized $true -PreserveRestoreBounds
			}
			else
			{
				$Script:MainWindowPendingWorkAreaMaximize = $true
			}
		}
		$Form.ShowInTaskbar = $true
		$Form.Opacity = 1
		if ($Form.WindowState -eq [System.Windows.WindowState]::Minimized)
		{
			$Form.WindowState = [System.Windows.WindowState]::Normal
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.StartupVisibility.Apply'
	}
