if (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue)
	{
		try
		{
			(Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess | Out-Null
		}
		catch [Microsoft.Management.Infrastructure.CimException]
		{
			LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
		}
	}
	else
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_MicrosoftDefenderPreferenceCmdletsUnavailable' -Fallback 'Microsoft Defender preference cmdlets are not available on this OS.')
	}
