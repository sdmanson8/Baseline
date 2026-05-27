function Invoke-CapabilitySelectAllClick
	{
		$CheckBox = $_.Source

		if ($CheckBox.IsChecked)
		{
			$SelectedCapabilities.Clear()
			foreach ($Item in $PanelContainer.Children)
			{
				foreach ($Child in $Item.Children)
				{
					if ($Child -is [System.Windows.Controls.CheckBox])
					{
						$Child.IsChecked = $true
						[void]$SelectedCapabilities.Add($Child.Tag)
					}
				}
			}
		}
		else
		{
			$SelectedCapabilities.Clear()
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
			$Button.IsEnabled = ($SelectedCapabilities.Count -gt 0)
		}
	}

	<#
	    .SYNOPSIS
	    Runs uninstall button.

		#>

	function UninstallButton
	{
		param
		(
			[object[]]
			$CapabilityList = @(Get-SelectedCapabilityList)
		)

		try
		{
			$ResolvedCapabilityList = @($CapabilityList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Uninstalling optional features"
			LogInfo "Uninstalling optional features"
			LogInfo "Optional features selected for uninstall: $($ResolvedCapabilityList.Count)"

			if ($ResolvedCapabilityList.Count -eq 0)
			{
				LogInfo "No optional features were selected for removal. Skipping."
				Write-ConsoleStatus -Status success
				return
			}

			$AvailableCapabilityNames = (Get-WindowsCapability -Online -ErrorAction Stop).Name

			$CapabilitiesToRemove = @(
				$ResolvedCapabilityList | Where-Object -FilterScript {$_.Name -in $AvailableCapabilityNames}
			)

			if (-not $CapabilitiesToRemove)
			{
				throw "None of the selected optional features are currently available for removal."
			}

			foreach ($Capability in $CapabilitiesToRemove)
			{
				LogInfo "Uninstalling optional feature: $($Capability.Name)"
				Invoke-SilencedProgress {
					Invoke-WindowsCapabilityDismOperation -Operation Uninstall -Name $Capability.Name -TimeoutSeconds $CapabilityOperationTimeoutSeconds | Out-Null
				}
				LogInfo "Uninstalled optional feature: $($Capability.Name)"
			}

			if ([string]$ResolvedCapabilityList.Name -match "Browser.InternetExplorer")
			{
				#LogWarning $Localization.RestartWarning
			}
				Write-ConsoleStatus -Status success
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			LogError "Failed to uninstall optional features: $($_.Exception.Message)"
			Write-ConsoleStatus -Status failed
		}
	}

	<#
	    .SYNOPSIS
	    Runs install button.

		#>

	function InstallButton
	{
		param
		(
			[object[]]
			$CapabilityList = @(Get-SelectedCapabilityList)
		)

		try
		{
			$ResolvedCapabilityList = @($CapabilityList | Where-Object { $_ })

			Write-ConsoleStatus -Action "Installing optional features"
			LogInfo "Installing optional features"
			LogInfo "Optional features selected for install: $($ResolvedCapabilityList.Count)"

			if ($ResolvedCapabilityList.Count -eq 0)
			{
				LogInfo "No optional features were selected for installation. Skipping."
				Write-ConsoleStatus -Status success
				return
			}

			$AvailableCapabilityNames = (Get-WindowsCapability -Online -ErrorAction Stop).Name

			$CapabilitiesToInstall = @(
				$ResolvedCapabilityList | Where-Object -FilterScript {$_.Name -in $AvailableCapabilityNames}
			)

			if (-not $CapabilitiesToInstall)
			{
				throw "None of the selected optional features are currently available for installation."
			}

			foreach ($Capability in $CapabilitiesToInstall)
			{
				LogInfo "Installing optional feature: $($Capability.Name)"
				Invoke-SilencedProgress {
					Invoke-WindowsCapabilityDismOperation -Operation Install -Name $Capability.Name -TimeoutSeconds $CapabilityOperationTimeoutSeconds | Out-Null
				}
				LogInfo "Installed optional feature: $($Capability.Name)"
			}

			if ([string]$ResolvedCapabilityList.Name -match "Browser.InternetExplorer")
			{
				#LogWarning $Localization.RestartWarning
			}
		}
		catch
		{
			Remove-HandledErrorRecord -ErrorRecord $_
			if ($_.Exception -is [System.Runtime.InteropServices.COMException])
			{
				LogError ($Localization.NoResponse -f "http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice")
				LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))
			}
			else
			{
				LogError "Failed to install optional features: $($_.Exception.Message)"
			}
			Write-ConsoleStatus -Status failed
			return
		}
			Write-ConsoleStatus -Status success
	}

	<#
	    .SYNOPSIS
	    Confirms windows capabilities selection.

		#>

	function Confirm-WindowsCapabilitiesSelection
	{
		$SelectedCapabilityList = @(Get-SelectedCapabilityList)
		$SelectionState.Confirmed = $true

		if ($CollectSelectionOnly)
		{
			$script:WindowsCapabilitiesSelectionResult = [PSCustomObject]@{
				Mode = $PSCmdlet.ParameterSetName
				SelectedCapabilityNames = @(Get-SelectedCapabilityNames)
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
			SelectedCapabilityNames = @(Get-SelectedCapabilityNames)
		}
		$commandParameters[$PSCmdlet.ParameterSetName] = $true

		if ($modulePath -and (Get-Command -Name 'Start-GuiPopupCommandAsync' -ErrorAction SilentlyContinue))
		{
			[void](GUICommon\Start-GuiPopupCommandAsync -Window $Form -ModulePath $modulePath -AdditionalModulePaths @($sharedHelpersPath, $guiCommonPath) -CommandName 'WindowsCapabilities' -CommandParameters $commandParameters)
			return
		}

		if ($null -ne $Window)
		{
			[void]$Window.Close()
		}

		& $ButtonAdd_Click -CapabilityList $SelectedCapabilityList
	}
