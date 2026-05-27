$guiResponsivenessWatchdog = $null
try
	{
		try
		{
			$guiResponsivenessWatchdog = Start-GuiResponsivenessWatchdog -Window $Form
			$Script:GuiResponsivenessWatchdog = $guiResponsivenessWatchdog
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.GuiResponsivenessWatchdog.Start' -Severity Warning
		}
		& $traceGuiStartup 'ShowDialog entering'
		[void]([System.Windows.Window]$Form).ShowDialog()
		& $traceGuiStartup 'ShowDialog returned'
	}
	catch
	{
		$errorLines = New-Object System.Collections.Generic.List[string]
		[void]$errorLines.Add("Failed to open WPF window. Form type: $($Form.GetType().FullName)")
		[void]$errorLines.Add("Apartment state: $([System.Threading.Thread]::CurrentThread.GetApartmentState())")
		[void]$errorLines.Add("Error: $($_.Exception.GetType().FullName): $($_.Exception.Message)")

		$innerException = $_.Exception.InnerException
		if ($innerException)
		{
			[void]$errorLines.Add("Inner exception: $($innerException.GetType().FullName): $($innerException.Message)")
			if (-not [string]::IsNullOrWhiteSpace([string]$innerException.StackTrace))
			{
				[void]$errorLines.Add("Inner stack trace:`n$($innerException.StackTrace.Trim())")
			}
		}

		throw ($errorLines -join [Environment]::NewLine)
	}
	finally
	{
		if ($guiResponsivenessWatchdog)
		{
			try { Stop-GuiResponsivenessWatchdog -Watchdog $guiResponsivenessWatchdog }
			catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.GuiResponsivenessWatchdog.Stop' -Severity Warning }
		}
		if ($Script:GuiResponsivenessWatchdog -eq $guiResponsivenessWatchdog)
		{
			$Script:GuiResponsivenessWatchdog = $null
		}
	}

	if ($startupSplashAbortWatchdog)
	{
		try
		{
			if ($startupSplashAbortWatchdog.PowerShell -and $startupSplashAbortWatchdog.AsyncResult -and $startupSplashAbortWatchdog.AsyncResult.IsCompleted)
			{
				$startupSplashAbortWatchdog.PowerShell.EndInvoke($startupSplashAbortWatchdog.AsyncResult)
			}
		}
		catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.StartupSplashAbortWatchdog.EndInvoke' }
		try { if ($startupSplashAbortWatchdog.PowerShell) { $startupSplashAbortWatchdog.PowerShell.Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.StartupSplashAbortWatchdog.PowerShellDispose' }
		try { if ($startupSplashAbortWatchdog.Runspace) { $startupSplashAbortWatchdog.Runspace.Close(); $startupSplashAbortWatchdog.Runspace.Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'Regions.GUI.StartupSplashAbortWatchdog.RunspaceDispose' }
	}
