if ($osInfo.IsWindowsServer)
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingDefenderWmiHealthCheckOnWindowsServer' -Fallback 'Skipping Microsoft Defender WMI health check on Windows Server.')
	}
	else
	{
		try
		{
			Get-CimInstance -ClassName MSFT_MpComputerStatus -Namespace root/Microsoft/Windows/Defender -ErrorAction Stop | Out-Null
		}
		catch [Microsoft.Management.Infrastructure.CimException]
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogWarning (Get-BaselineBilingualString -Key 'GuiPreflightWMIFailed' -Fallback 'CIM/WMI query failed: {0}' -FormatArgs @($_.Exception.Message))
			LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
		}
	}
