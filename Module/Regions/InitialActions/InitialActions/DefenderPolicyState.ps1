if ($SecurityCenterAvailable)
	{
		$DefenderProduct = $SecurityCenterProducts | Where-Object { $_.instanceGuid -eq "{D68DDC3A-831F-4fae-9E44-DA132C1ACF46}" } | Select-Object -First 1
		if ($DefenderProduct -and ($null -ne $DefenderProduct.productState))
		{
			try
			{
				$DefenderState = Get-BaselineDefenderProductStateCode -ProductState $DefenderProduct.productState
			}
			catch
			{
				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_UnableToParseDefenderProductState' -Fallback 'Unable to parse Microsoft Defender product state: {0}' -FormatArgs @($_.Exception.Message))
			}
		}
	}
	else
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_MicrosoftDefenderSecurityCenterStateUnavailable' -Fallback 'Microsoft Defender Security Center product state is not available on this OS.')
	}

	if (Test-BaselineDefenderActiveByProductState -StateCode $DefenderState)
	{
		# Defender is a currently used AV. Continue...
		$Script:DefenderProductState = $true

		# Checking whether Microsoft Defender was turned off via GPO
		if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender", "DisableAntiSpyware", $null) -eq 1)
		{
			$Script:AntiSpywareEnabled = $false
		}
		else
		{
			$Script:AntiSpywareEnabled = $true
		}

		# Checking whether Microsoft Defender was turned off via GPO
		if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection", "DisableRealtimeMonitoring", $null) -eq 1)
		{
			$Script:RealtimeMonitoringEnabled = $false
		}
		else
		{
			$Script:RealtimeMonitoringEnabled = $true
		}

		# Checking whether Microsoft Defender was turned off via GPO
		if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection", "DisableBehaviorMonitoring", $null) -eq 1)
		{
			$Script:BehaviorMonitoringEnabled = $false
		}
		else
		{
			$Script:BehaviorMonitoringEnabled = $true
		}
	}
	else
	{
		$Script:DefenderProductState = $false
		$Script:AntiSpywareEnabled = $false
		$Script:RealtimeMonitoringEnabled = $false
		$Script:BehaviorMonitoringEnabled = $false
	}

	if (Test-BaselineDefenderFullyEnabled -ServicesRunning $Script:DefenderServices -ProductStateActive $Script:DefenderProductState -AntiSpywareEnabled $Script:AntiSpywareEnabled -RealtimeMonitoringEnabled $Script:RealtimeMonitoringEnabled -BehaviorMonitoringEnabled $Script:BehaviorMonitoringEnabled)
	{
		# Defender is enabled
		$Script:DefenderEnabled = $true

		switch ((Get-MpPreference).EnableControlledFolderAccess)
		{
			"1"
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_DisablingControlledFolderAccess' -Fallback 'Disabling Controlled folder access')
				$Script:ControlledFolderAccess = $true
				if ($IsAdmin)
				{
					Set-MpPreference -EnableControlledFolderAccess Disabled | Out-Null
				}
				else
				{
					LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingControlledFolderAccessRemediationNotElevated' -Fallback 'Skipping Controlled folder access remediation because Baseline is not running elevated.')
				}

				Start-Process -FilePath "windowsdefender://RansomwareProtection" | Out-Null
			}
			"0"
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_ControlledFolderAccessAlreadyDisabled' -Fallback 'Controlled folder access has already been disabled')
				$Script:ControlledFolderAccess = $false
			}
			default
			{
				$Script:ControlledFolderAccess = $false
			}
		}
	}
	else
	{
		$Script:DefenderEnabled = $false
		$Script:ControlledFolderAccess = $false
	}
