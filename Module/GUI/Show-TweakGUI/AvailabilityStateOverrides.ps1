foreach (
		$functionName in @(
			'ActiveHours'
			'DeliveryOptimization'
			'MaintenanceWakeUp'
			'RestartDeviceAfterUpdate'
			'RestartNotification'
			'SearchAppInStore'
			'BlockStoreSearchResults'
			'DownloadUpdatesOverMeteredConnection'
			'FeatureUpdateDeferral'
			'QualityUpdateDeferral'
			'StoreAppAutoDownload'
			'MapUpdates'
			'UpdateMSRT'
			'WindowsUpdateDisableAll'
			'WindowsUpdatePause'
			'WindowsUpdateSecurityOnlyMode'
			'UpdateNotificationLevel'
			'UpdateAutoDownload'
			'UpdateDriver'
			'UpdateMSProducts'
			'UpdateMicrosoftProducts'
			'UpdateRestart'
			'WindowsLatestUpdate'
			'WindowsUpdate'
		)
	)
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
		{
			[void]$Script:UpdatesPrimaryTabFunctions.Add([string]$functionName)
		}
	}

	<#
	    .SYNOPSIS
	    Resolves GUI primary tab for tweak.

		#>

	function Resolve-GuiPrimaryTabForTweak
	{
		param ([object]$Tweak)

		if (-not $Tweak)
		{
			return $null
		}

		$functionName = if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('Function')) { [string]$Tweak['Function'] } else { $null }
		}
		elseif ($Tweak.PSObject.Properties['Function']) { [string]$Tweak.Function }
		else { $null }

		if (-not [string]::IsNullOrWhiteSpace($functionName) -and $Script:UpdatesPrimaryTabFunctions -and $Script:UpdatesPrimaryTabFunctions.Contains($functionName))
		{
			return 'Updates'
		}

		$categoryName = if ($Tweak -is [System.Collections.IDictionary])
		{
			if ($Tweak.Contains('Category')) { [string]$Tweak['Category'] } else { $null }
		}
		elseif ($Tweak.PSObject.Properties['Category']) { [string]$Tweak.Category }
		else { $null }

		if ([string]::IsNullOrWhiteSpace($categoryName))
		{
			return $null
		}

		$categoryMap = if ($Script:CategoryToPrimary -is [hashtable]) { $Script:CategoryToPrimary } else { $null }

		if ($categoryMap -and $categoryMap.ContainsKey($categoryName))
		{
			return [string]$categoryMap[$categoryName]
		}

		return $categoryName
	}
