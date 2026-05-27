	$Script:Controls = @{}
	# Function-name -> manifest-index map for linked-toggle lookups in closures
	$Script:FunctionToIndex = @{}
	$Script:Ctx.Data.Controls = $Script:Controls
	$Script:Ctx.Data.FunctionToIndex = $Script:FunctionToIndex
	for ($fti = 0; $fti -lt $Script:TweakManifest.Count; $fti++)
	{
		$Script:FunctionToIndex[$Script:TweakManifest[$fti].Function] = $fti
	}

	# Pre-seed every manifest entry with a value holder so the run loop works
	# even for tabs the user never visits. Build-TweakRow replaces these with
	# real WPF controls when a tab is first rendered, carrying the state forward.
	for ($si = 0; $si -lt $Script:TweakManifest.Count; $si++)
	{
		$st = $Script:TweakManifest[$si]
		$isVisible = $true
		if ($st.VisibleIf)
		{
			try { $isVisible = [bool](& $st.VisibleIf) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'BuildTweakControls.SeedControlVisibility.VisibleIf'; $isVisible = $false }
		}
			switch ($st.Type)
			{
				'Toggle' {
					$Script:Controls[$si] = [pscustomobject]@{ IsChecked = $false; IsEnabled = $isVisible }
				}
				'Action' {
					$Script:Controls[$si] = [pscustomobject]@{ IsChecked = $false; IsEnabled = $isVisible }
				}
				'Choice' {
					$Script:Controls[$si] = [pscustomobject]@{ SelectedIndex = [int]-1; IsEnabled = $isVisible }
				}
				'NumericRange' {
					$Script:Controls[$si] = [pscustomobject]@{ IsChecked = $false; IsEnabled = $isVisible }
				}
			}
		}

	# Pending linked states for tweaks whose target tab is not yet built
	$Script:PendingLinkedChecks   = [System.Collections.Generic.HashSet[string]]::new()
	$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
	$Script:ApplyingGuiPreset     = $false  # suppress linked sync while applying an explicit preset
	# Applied-this-session tracking for system scan
	$Script:AppliedTweaks = [System.Collections.Generic.HashSet[string]]::new()

		<#
		    .SYNOPSIS
		#>

		function Update-CurrentTabContent
		{
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
			param (
				[switch]$SkipIdlePrebuild
			)

			$__perf = Start-GuiPerfScope -Name 'UpdateCurrentTabContent' -Note ([string]$Script:CurrentPrimaryTab)
			try
			{
			if ($Script:AppsModeActive -or $Script:DeploymentMediaModeActive)
			{
				$startupSplash = $Global:LoadingSplash
				$startupSplashLive = $false
				if (Get-Command -Name 'Test-GuiStartupSplashLive' -CommandType Function -ErrorAction SilentlyContinue)
				{
					$startupSplashLive = [bool](Test-GuiStartupSplashLive -Splash $startupSplash)
				}
				$startupSplashReady = [bool]($startupSplash -is [hashtable] -and $startupSplash.ContainsKey('GuiReady') -and [bool]$startupSplash.GuiReady)
				if ($startupSplashLive -and -not $startupSplashReady)
				{
					$startupReadySignalScript = Get-Command -Name 'Invoke-GuiStartupReadySignal' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
					if ($startupReadySignalScript)
					{
						& $startupReadySignalScript
					}
				}
				return
			}

			if ($Script:GamingModeActive)
			{
				$targetTab = 'Gaming'
			}
			elseif ($Script:UpdatesModeActive)
			{
				$targetTab = 'Updates'
			}
			else
			{
				$activeSearchQuery = if ($null -eq $Script:SearchText) { '' } else { [string]$Script:SearchText }
				$activeSearchQuery = $activeSearchQuery.Trim()
				if (-not [string]::IsNullOrWhiteSpace($activeSearchQuery))
				{
					$targetTab = $Script:SearchResultsTabTag
				}
				else
				{
					if ($PrimaryTabs -and ($null -eq $PrimaryTabs.SelectedItem -or -not $PrimaryTabs.SelectedItem.Tag))
					{
						$resolvedSelection = $null
						$preferredTag = if (-not [string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab))
						{
							[string]$Script:CurrentPrimaryTab
						}
						elseif (-not [string]::IsNullOrWhiteSpace([string]$Script:LastStandardPrimaryTab))
						{
							[string]$Script:LastStandardPrimaryTab
						}
						else
						{
							$null
						}

						if ($preferredTag)
						{
							foreach ($tabItem in $PrimaryTabs.Items)
							{
								if (($tabItem -is [System.Windows.Controls.TabItem]) -and $tabItem.Tag -and ([string]$tabItem.Tag -eq $preferredTag))
								{
									$resolvedSelection = $tabItem
									break
								}
							}
						}

						if (-not $resolvedSelection)
						{
							foreach ($tabItem in $PrimaryTabs.Items)
							{
								if (($tabItem -is [System.Windows.Controls.TabItem]) -and $tabItem.Tag -and ([string]$tabItem.Tag -ne $Script:SearchResultsTabTag))
								{
									$resolvedSelection = $tabItem
									break
								}
							}
						}

						if ($resolvedSelection -and $PrimaryTabs.SelectedItem -ne $resolvedSelection)
						{
							$PrimaryTabs.SelectedItem = $resolvedSelection
						}
					}

					$targetTab = if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag)
					{
						[string]$PrimaryTabs.SelectedItem.Tag
					}
					elseif ($Script:CurrentPrimaryTab)
					{
						[string]$Script:CurrentPrimaryTab
					}
					else
					{
						$null
					}
				}
			}

			if ([string]::IsNullOrWhiteSpace($targetTab)) { return }
			$updatePlatformFilterListScript = if ($Script:UpdatePlatformFilterListScript) { $Script:UpdatePlatformFilterListScript } else { ${function:Update-PlatformFilterList} }
			$updateRiskFilterListScript = if ($Script:UpdateRiskFilterListScript) { $Script:UpdateRiskFilterListScript } else { ${function:Update-RiskFilterList} }
			$updateCategoryFilterListScript = if ($Script:UpdateCategoryFilterListScript) { $Script:UpdateCategoryFilterListScript } else { ${function:Update-CategoryFilterList} }
			$updatePrimaryTabHeadersScript = if ($Script:UpdatePrimaryTabHeadersScript) { $Script:UpdatePrimaryTabHeadersScript } else { ${function:Update-PrimaryTabHeaders} }
			$updatePrimaryTabVisualsScript = if ($Script:UpdatePrimaryTabVisualsScript) { $Script:UpdatePrimaryTabVisualsScript } else { ${function:Update-PrimaryTabVisuals} }
			$buildTabContentScript = if ($Script:BuildTabContentScript) { $Script:BuildTabContentScript } else { ${function:Build-TabContent} }
			if ($updatePlatformFilterListScript)
			{
				try
				{
					& $updatePlatformFilterListScript
				}
				catch
				{
					throw "Update-CurrentTabContent/UpdatePlatformFilterList for tab '$targetTab' failed: $($_.Exception.Message)"
				}
			}
			if ($updateRiskFilterListScript)
			{
				try
				{
					& $updateRiskFilterListScript
				}
				catch
				{
					throw "Update-CurrentTabContent/UpdateRiskFilterList for tab '$targetTab' failed: $($_.Exception.Message)"
				}
			}
			if ($updateCategoryFilterListScript)
			{
				try
				{
					& $updateCategoryFilterListScript -PrimaryTab $targetTab
				}
				catch
				{
					throw "Update-CurrentTabContent/UpdateCategoryFilterList for tab '$targetTab' failed: $($_.Exception.Message)"
				}
			}
			try
			{
				& $updatePrimaryTabHeadersScript
			}
			catch
			{
				throw "Update-CurrentTabContent/UpdatePrimaryTabHeaders for tab '$targetTab' failed: $($_.Exception.Message)"
			}
			try
			{
				& $updatePrimaryTabVisualsScript
			}
			catch
			{
				throw "Update-CurrentTabContent/UpdatePrimaryTabVisuals for tab '$targetTab' failed: $($_.Exception.Message)"
			}
			try
			{
				& $buildTabContentScript -PrimaryTab $targetTab -SkipIdlePrebuild:$SkipIdlePrebuild
			}
			catch
			{
				throw "Update-CurrentTabContent/BuildTabContent for tab '$targetTab' failed: $($_.Exception.Message)"
			}
			}
			finally
			{
				Stop-GuiPerfScope -Scope $__perf
			}
		}

	. (Join-Path $Script:GuiExtractedRoot 'ModeState.ps1')


	. (Join-Path $Script:GuiExtractedRoot 'PresetApplication.ps1')


	<#
	    .SYNOPSIS
	#>

	function Set-SecondaryActionGroupStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $Script:SecondaryActionGroupBorder) { return }
		$bc = New-SafeBrushConverter -Context 'Set-SecondaryActionGroupStyle'
		$Script:SecondaryActionGroupBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$Script:SecondaryActionGroupBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$Script:SecondaryActionGroupBorder.Opacity = 0.85
	}

	function Set-StaticButtonStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		Set-ButtonChrome -Button $Script:BtnRun -Variant 'Primary'
		if ($Script:BtnPreviewRun) { Set-ButtonChrome -Button $Script:BtnPreviewRun -Variant 'Preview' }
		Set-ButtonChrome -Button $Script:BtnDefaults -Variant 'DangerSubtle'
		if ($Script:BtnUpdateAllApps) { Set-ButtonChrome -Button $Script:BtnUpdateAllApps -Variant 'Secondary' -Compact }
		# Apps Source + View filters are RadioButtons styled by AppsFilterRadioStyle
		# (radio dials with checked-state animation). Set-ButtonChrome would
		# overwrite the template with a pill, so leave them alone here and in the
		# Update-* helpers below.
		if (Get-Command -Name 'Update-AppSourceFilterControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppSourceFilterControls
		}
		if (Get-Command -Name 'Update-AppsViewModeControls' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-AppsViewModeControls
		}
		if ($Script:BtnInstallSelectedApps) { Set-ButtonChrome -Button $Script:BtnInstallSelectedApps -Variant 'Subtle' -Compact }
		if ($Script:BtnUninstallSelectedApps) { Set-ButtonChrome -Button $Script:BtnUninstallSelectedApps -Variant 'DangerSubtle' -Compact }
		if ($Script:BtnUpdateSelectedApps) { Set-ButtonChrome -Button $Script:BtnUpdateSelectedApps -Variant 'Subtle' -Compact }
		if ($Script:BtnApplyQueuedActions) { Set-ButtonChrome -Button $Script:BtnApplyQueuedActions -Variant 'Primary' -Compact }
		if ($Script:BtnClearQueuedActions) { Set-ButtonChrome -Button $Script:BtnClearQueuedActions -Variant 'Subtle' -Compact -Muted }
		if ($Script:BtnScanInstalledApps) { Set-ButtonChrome -Button $Script:BtnScanInstalledApps -Variant 'Subtle' -Compact -Muted }
		if ($Script:BtnStartHere) { Set-ButtonChrome -Button $Script:BtnStartHere -Variant 'Subtle' -Compact -Muted }
		if ($Script:BtnHelp) { Set-ButtonChrome -Button $Script:BtnHelp -Variant 'Subtle' -Compact -Muted }
		if ($BtnLanguage) { Set-ButtonChrome -Button $BtnLanguage -Variant 'Subtle' -Compact -Muted }
		Set-ButtonChrome -Button $BtnLog -Variant 'Subtle' -Compact -Muted
		if ($BtnExportSettings) { Set-ButtonChrome -Button $BtnExportSettings -Variant 'Subtle' -Compact -Muted }
		if ($BtnImportSettings) { Set-ButtonChrome -Button $BtnImportSettings -Variant 'Subtle' -Compact -Muted }
		if ($Script:BtnRestoreSnapshot) { Set-ButtonChrome -Button $Script:BtnRestoreSnapshot -Variant 'Subtle' -Compact -Muted }
		Set-SecondaryActionGroupStyle
	}

	<#
	    .SYNOPSIS
	#>

	function Set-StaticControlTabOrder
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$tabIndex = 0
		foreach ($control in @(
			$Script:BtnHelp,
			$BtnLog,
			$ChkScan,
			$ChkTheme,
			$BtnLanguage,
			$Script:TxtSearch,
			$Script:BtnClearSearch,
			$CmbRiskFilter,
			$CmbCategoryFilter,
			$CmbPlatformFilter,
			$ChkHideUnavailableItems,
			$ChkSelectedOnly,
			$ChkHighRiskOnly,
			$ChkRestorableOnly,
			$ChkGamingOnly,
			$Script:BtnDefaults,
			$BtnExportSettings,
			$BtnImportSettings,
			$Script:BtnRestoreSnapshot,
			$Script:BtnPreviewRun,
			$Script:BtnRun,
			$Script:BtnUpdateAllApps,
			$Script:BtnAppsFilterToggle,
			$Script:AppsCategoryTabs,
			$CmbAppsStatusFilter,
			$Script:BtnAppsSourceFilterAll,
			$Script:BtnAppsSourceFilterWinGet,
			$Script:BtnAppsSourceFilterChocolatey,
			$Script:BtnInstallSelectedApps,
			$Script:BtnUninstallSelectedApps,
			$Script:BtnUpdateSelectedApps,
			$Script:BtnApplyQueuedActions,
			$Script:BtnClearQueuedActions,
			$Script:BtnScanInstalledApps
		))
		{
			if (-not $control) { continue }
			if ($control.PSObject.Properties['IsTabStop']) { $control.IsTabStop = $true }
			if ($control.PSObject.Properties['TabIndex'])
			{
				$control.TabIndex = $tabIndex
				$tabIndex++
			}
		}
	}

	. (Join-Path $Script:GuiExtractedRoot 'ContentManagement.ps1')


	. (Join-Path $Script:GuiExtractedRoot 'TweakRowFactory.ps1')
