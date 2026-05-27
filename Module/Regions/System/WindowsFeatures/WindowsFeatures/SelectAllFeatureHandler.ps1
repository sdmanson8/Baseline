function Invoke-FeatureSelectAllClick
	{
		$CheckBox = $_.Source

		if ($CheckBox.IsChecked)
		{
			$SelectedFeatures.Clear()
			foreach ($Item in $PanelContainer.Children)
			{
				foreach ($Child in $Item.Children)
				{
					if ($Child -is [System.Windows.Controls.CheckBox])
					{
						$Child.IsChecked = $true
						[void]$SelectedFeatures.Add($Child.Tag)
					}
				}
			}
		}
		else
		{
			$SelectedFeatures.Clear()
			foreach ($Item in $PanelContainer.Children)
			{
				foreach ($Child in $Item.Children)
				{
					if ($Child -is [System.Windows.Controls.CheckBox])
					{
						$Child.IsChecked = $false
					}
				}
			}
		}

		if ($null -ne $Button)
		{
			$Button.IsEnabled = ($SelectedFeatures.Count -gt 0)
		}
	}

	<#
	    .SYNOPSIS
	    Runs disable button.

		#>

	function DisableButton
	{
		param
		(
			[object[]]
			$FeatureList = @(Get-SelectedFeatureList)
		)

		try
		{
			$ResolvedFeatureList = @($FeatureList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Disabling Windows features"
			LogInfo "Disabling Windows features"
			LogInfo "Windows features selected for disable: $($ResolvedFeatureList.Count)"

			if ($ResolvedFeatureList.Count -eq 0)
			{
				LogInfo "No Windows features were selected for disable. Skipping."
				Write-ConsoleStatus -Status success
				return
			}

			foreach ($Feature in $ResolvedFeatureList)
			{
				LogInfo "Disabling Windows feature: $($Feature.FeatureName)"
				Invoke-SilencedProgress {
					Disable-WindowsOptionalFeature -FeatureName $Feature.FeatureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				}
				LogInfo "Disabled Windows feature: $($Feature.FeatureName)"
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to disable Windows features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	<#
	    .SYNOPSIS
	    Runs enable button.

		#>

	function EnableButton
	{
		param
		(
			[object[]]
			$FeatureList = @(Get-SelectedFeatureList)
		)

		try
		{
			$ResolvedFeatureList = @($FeatureList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Enabling Windows features"
			LogInfo "Enabling Windows features"
			LogInfo "Windows features selected for enable: $($ResolvedFeatureList.Count)"

			if ($ResolvedFeatureList.Count -eq 0)
			{
				LogInfo "No Windows features were selected for enable. Skipping."
				Write-ConsoleStatus -Status success
				return
			}

			foreach ($Feature in $ResolvedFeatureList)
			{
				LogInfo "Enabling Windows feature: $($Feature.FeatureName)"
				Invoke-SilencedProgress {
					Enable-WindowsOptionalFeature -FeatureName $Feature.FeatureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				}
				LogInfo "Enabled Windows feature: $($Feature.FeatureName)"
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to enable Windows features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	<#
	    .SYNOPSIS
	    Confirms windows features selection.

		#>

	function Confirm-WindowsFeaturesSelection
	{
		$SelectedFeatureList = @(Get-SelectedFeatureList)
		$SelectionState.Confirmed = $true

		if ($CollectSelectionOnly)
		{
			$script:WindowsFeaturesSelectionResult = [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedFeatureNames = @(Get-SelectedFeatureNames)
			}
			if ($null -ne $Window)
			{
				[void]$Window.Close()
			}
			return
		}

		foreach ($popupControl in @($Button, $CheckBoxSelectAll, $PanelContainer))
		{
			if ($null -ne $popupControl)
			{
				$popupControl.IsEnabled = $false
			}
		}

		$commandParameters = @{
			SelectedFeatureNames = @(Get-SelectedFeatureNames)
		}
		$commandParameters[$PSCmdlet.ParameterSetName] = $true

		if ($modulePath -and (Get-Command -Name 'Start-GuiPopupCommandAsync' -ErrorAction SilentlyContinue))
		{
			[void](GUICommon\Start-GuiPopupCommandAsync -Window $Form -ModulePath $modulePath -AdditionalModulePaths @($guiCommonPath) -CommandName 'WindowsFeatures' -CommandParameters $commandParameters)
			return
		}

		if ($null -ne $Window)
		{
			[void]$Window.Close()
		}

		& $ButtonAdd_Click -FeatureList $SelectedFeatureList
	}

	# Friendly display names for features whose DisplayName is empty or is just the internal name
	$FeatureFriendlyNames = @{
		'LegacyComponents'                       = 'Legacy Components'
		'MicrosoftWindowsPowerShellV2'            = 'PowerShell 2.0 Engine'
		'MicrosoftWindowsPowershellV2Root'        = 'PowerShell 2.0'
		'Printing-XPSServices-Features'           = 'Microsoft XPS Document Writer'
		'Recall'                                  = 'Recall'
		'WorkFolders-Client'                      = 'Work Folders Client'
		'MediaPlayback'                           = 'Media Features'
		'Containers-DisposableClientVM'           = 'Windows Sandbox'
		'Windows-Defender-ApplicationGuard'       = 'Windows Defender Application Guard'
		'Microsoft-Hyper-V-All'                   = 'Hyper-V'
		'VirtualMachinePlatform'                  = 'Virtual Machine Platform'
		'HypervisorPlatform'                      = 'Windows Hypervisor Platform'
		'Microsoft-Windows-Subsystem-Linux'       = 'Windows Subsystem for Linux'
		'Printing-PrintToPDFServices-Features'    = 'Microsoft Print to PDF'
		'NetFx3'                                  = '.NET Framework 3.5'
		'TelnetClient'                            = 'Telnet Client'
		'TFTP'                                    = 'TFTP Client'
		'SMB1Protocol'                            = 'SMB 1.0/CIFS File Sharing'
		'SearchEngine-Client-Package'             = 'Windows Search'
		'SmbDirect'                               = 'SMB Direct'
		'DirectPlay'                              = 'DirectPlay'
	}

	<#
	    .SYNOPSIS
	    Gets feature friendly name.

		#>

	function Get-FeatureFriendlyName
	{
		param ([string]$FeatureName, [string]$DisplayName)

		if (-not [string]::IsNullOrWhiteSpace($DisplayName))
		{
			return $DisplayName
		}

		if ($FeatureFriendlyNames.ContainsKey($FeatureName))
		{
			return $FeatureFriendlyNames[$FeatureName]
		}

		return $FeatureName
	}
