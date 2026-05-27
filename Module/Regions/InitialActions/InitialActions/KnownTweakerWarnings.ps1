foreach ($Tweaker in $Tweakers.Keys)
	{
		if (Test-Path -Path $Tweakers[$Tweaker])
		{
			[void]$DetectedTweakers.Add([string]$Tweaker)
			if ($Tweakers[$Tweaker] -eq "HKCU:\Software\Win 10 Tweaker")
			{
				LogWarning (Get-BaselineBilingualString -Key 'Win10TweakerWarning' -Fallback 'Windows has been infected with a trojan via a Win 10 Tweaker backdoor. Reinstall Windows using only a genuine ISO image.')
			}
			else
			{
				LogWarning (Get-BaselineBilingualString -Key 'TweakerWarning' -Fallback 'The Windows stability may have been compromised by using {0}. Reinstall Windows using only a genuine ISO image.' -FormatArgs @($Tweaker))
			}
		}
	}
