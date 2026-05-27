if ($osInfo.IsWindowsServer)
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingSecurityCenterChecksOnWindowsServer' -Fallback 'Skipping SecurityCenter2 antivirus checks on Windows Server.')
	}
	else
	{
		try
		{
			$SecurityCenterProducts = @(Get-CimInstance -ClassName AntiVirusProduct -Namespace root/SecurityCenter2 -ErrorAction Stop)
			$SecurityCenterAvailable = $true
			if (-not $SecurityCenterProducts)
			{
				LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
			}
		}
		catch [Microsoft.Management.Infrastructure.CimException]
		{
			LogWarning (Get-BaselineBilingualString -Key 'GuiPreflightWMIFailed' -Fallback 'CIM/WMI query failed: {0}' -FormatArgs @($_.Exception.Message))
			LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
		}
	}
