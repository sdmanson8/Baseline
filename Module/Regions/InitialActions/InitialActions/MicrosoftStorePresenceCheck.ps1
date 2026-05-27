if ($osInfo.IsWindowsServer)
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_MicrosoftStoreNotApplicable' -Fallback 'Microsoft Store presence check is not applicable on Windows Server.')
	}
	else
	{
		$storePresent = Test-BaselineAppxPackagePresence -Name 'Microsoft.WindowsStore'
		if ($storePresent -eq $false)
		{
			LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Store'))
		}
	}
