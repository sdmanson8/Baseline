try
		{
			$DefenderServiceNames = if ($osInfo.IsWindowsServer)
			{
				@("WinDefend", "wscsvc")
		}
		else
		{
			@("WinDefend", "SecurityHealthService", "wscsvc")
		}

			$Services = Get-Service -Name $DefenderServiceNames -ErrorAction Stop
			if ($IsAdmin -and (-not $osInfo.IsWindowsServer) -and ($Services.Name -contains "SecurityHealthService"))
			{
				Get-Service -Name SecurityHealthService -ErrorAction Stop | Start-Service | Out-Null
			}
		}
	catch [Microsoft.PowerShell.Commands.ServiceCommandException]
	{
		Remove-HandledErrorRecord -ErrorRecord $_
		$Services = @()
		LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
	}
