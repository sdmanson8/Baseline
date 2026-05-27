
<#
    .SYNOPSIS
#>

function Set-AppsActionControlsEnabled
{
	[CmdletBinding()]
	param (
		[bool]$Enabled = $true
	)

	$setControlEnabled = {
		param ([object]$Control)

		if (-not $Control) { return }
		try
		{
			$Control.IsEnabled = $Enabled
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Set-AppsActionControlsEnabled.ControlEnabled'
		}
	}.GetNewClosure()

	if ($Script:BtnUpdateAllApps) { $Script:BtnUpdateAllApps.IsEnabled = $Enabled }
	if ($Script:BtnRun -and $Script:AppsModeActive) { $Script:BtnRun.IsEnabled = $Enabled }
	if ($Script:AppsBulkActionButtons -is [System.Collections.IEnumerable])
	{
		foreach ($bulkButton in @($Script:AppsBulkActionButtons))
		{
			& $setControlEnabled $bulkButton
		}
	}
	if ($Script:AppsCategoryTabs)
	{
		& $setControlEnabled $Script:AppsCategoryTabs
	}
	if ($Script:CmbAppsStatusFilter)
	{
		& $setControlEnabled $Script:CmbAppsStatusFilter
	}
	if ($Script:BtnAppsSourceFilterAll)
	{
		& $setControlEnabled $Script:BtnAppsSourceFilterAll
	}
	if ($Script:BtnAppsSourceFilterWinGet)
	{
		& $setControlEnabled $Script:BtnAppsSourceFilterWinGet
	}
	if ($Script:BtnAppsSourceFilterChocolatey)
	{
		& $setControlEnabled $Script:BtnAppsSourceFilterChocolatey
	}
	if ($Script:BtnAppsViewCards)
	{
		& $setControlEnabled $Script:BtnAppsViewCards
	}
	if ($Script:BtnAppsViewList)
	{
		& $setControlEnabled $Script:BtnAppsViewList
	}
	if ($Script:BtnApplyQueuedActions)
	{
		& $setControlEnabled $Script:BtnApplyQueuedActions
	}
	if ($Script:BtnClearQueuedActions)
	{
		& $setControlEnabled $Script:BtnClearQueuedActions
	}
	if ($Script:AppsActionButtons -is [System.Collections.IEnumerable])
	{
		foreach ($actionButton in @($Script:AppsActionButtons))
		{
			& $setControlEnabled $actionButton
		}
	}
	if ($Script:AppsQueuedActionControls -is [System.Collections.IEnumerable])
	{
		foreach ($queuedControl in @($Script:AppsQueuedActionControls))
		{
			if (-not $queuedControl) { continue }
			foreach ($controlName in @('Install', 'Uninstall', 'DoNothing'))
			{
				if ($queuedControl.PSObject.Properties[$controlName] -and $queuedControl.$controlName)
				{
					& $setControlEnabled $queuedControl.$controlName
				}
			}
		}
	}
	if ($Script:AppsSelectionControls -is [System.Collections.IEnumerable])
	{
		foreach ($selectionControl in @($Script:AppsSelectionControls))
		{
			& $setControlEnabled $selectionControl
		}
	}
	if (Get-Command -Name 'Update-AppsSelectionSummary' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Update-AppsSelectionSummary
	}
}

<#
    .SYNOPSIS
#>

function Initialize-AppsSelectionState
{
	[CmdletBinding()]
	param ()

	if (-not ($Script:SelectedAppIds -is [System.Collections.Generic.HashSet[string]]))
	{
		$Script:SelectedAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}
	if (-not ($Script:AppsSelectionControls -is [System.Collections.Generic.List[object]]))
	{
		$Script:AppsSelectionControls = [System.Collections.Generic.List[object]]::new()
	}
	if (-not ($Script:AppsBulkActionButtons -is [System.Collections.Generic.List[object]]))
	{
		$Script:AppsBulkActionButtons = [System.Collections.Generic.List[object]]::new()
	}
	if ($null -eq $Script:AppsSelectionUiUpdating)
	{
		$Script:AppsSelectionUiUpdating = $false
	}
}

<#
    .SYNOPSIS
#>

function Initialize-AppsQueuedActionState
{
	<#
		.SYNOPSIS
		Lazily initialises the per-app queued-action dictionary.
		Keys are app IDs (case-insensitive); values are 'Install', 'Uninstall', or 'DoNothing'.
	#>
	[CmdletBinding()]
	param ()

	$appsQueuedActions = Get-Variable -Name 'AppsQueuedActions' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if (-not ($appsQueuedActions -is [System.Collections.Generic.Dictionary[string, string]]))
	{
		$Script:AppsQueuedActions = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}
	$appsQueuedActionControls = Get-Variable -Name 'AppsQueuedActionControls' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if (-not ($appsQueuedActionControls -is [System.Collections.Generic.List[object]]))
	{
		$Script:AppsQueuedActionControls = [System.Collections.Generic.List[object]]::new()
	}
	$appsQueuedActionControlMap = Get-Variable -Name 'AppsQueuedActionControlMap' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if (-not ($appsQueuedActionControlMap -is [System.Collections.Generic.Dictionary[string, object]]))
	{
		$Script:AppsQueuedActionControlMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}
	$appsQueuedActionUiUpdating = Get-Variable -Name 'AppsQueuedActionUiUpdating' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
	if ($null -eq $appsQueuedActionUiUpdating)
	{
		$Script:AppsQueuedActionUiUpdating = $false
	}
}

<#
    .SYNOPSIS
#>

function Get-GuiAppsQueuedBadgeColorSet
{
	[CmdletBinding()]
	param (
		[object]$Theme = $null
	)

	if (-not $Theme)
	{
		$Theme = Get-GuiCurrentTheme
	}

	$getThemeColor = {
		param (
			[object]$ThemeObject,
			[string]$Name
		)

		if (-not $ThemeObject) { return $null }
		if ($ThemeObject -is [hashtable])
		{
			if ($ThemeObject.ContainsKey($Name)) { return [string]$ThemeObject[$Name] }
			return $null
		}

		$property = $ThemeObject.PSObject.Properties[$Name]
		if ($property) { return [string]$property.Value }
		return $null
	}

	$backgroundColor = & $getThemeColor -ThemeObject $Theme -Name 'AccentBlue'
	if ([string]::IsNullOrWhiteSpace($backgroundColor))
	{
		$backgroundColor = '#3B82F6'
	}

	$candidateColors = [System.Collections.Generic.List[string]]::new()
	foreach ($candidateColor in @('#FFFFFF', '#111827', (& $getThemeColor -ThemeObject $Theme -Name 'WindowBg'), (& $getThemeColor -ThemeObject $Theme -Name 'TextPrimary')))
	{
		if ([string]::IsNullOrWhiteSpace([string]$candidateColor)) { continue }
		if (-not $candidateColors.Contains([string]$candidateColor))
		{
			[void]$candidateColors.Add([string]$candidateColor)
		}
	}

	$foregroundColor = Get-GuiReadableForegroundColor -BackgroundColor $backgroundColor -CandidateColors @($candidateColors)
	return [pscustomobject]@{
		Background = $backgroundColor
		Foreground = $foregroundColor
	}
}

<#
    .SYNOPSIS
#>

function Set-GuiAppsQueuedBadgeChrome
{
	[CmdletBinding()]
	param (
		[object]$Badge,
		[object]$BadgeText
	)

	if (-not $Badge -or -not $BadgeText) { return }

	$colors = Get-GuiAppsQueuedBadgeColorSet
	$Badge.Background = ConvertTo-GuiBrush -Color $colors.Background -Context 'AppsQueuedBadge.Background'
	$BadgeText.Foreground = ConvertTo-GuiBrush -Color $colors.Foreground -Context 'AppsQueuedBadge.Foreground'
}

<#
    .SYNOPSIS
#>

function Sync-AppsQueuedActionControls
{
	<#
		.SYNOPSIS
		Updates the queued-action radio buttons so they match the pending queue state.
	#>
	[CmdletBinding()]
	param (
		[string]$AppId
	)

	Initialize-AppsQueuedActionState
	if ($Script:AppsQueuedActionUiUpdating) { return }

	$controlPairs = @()
	if (-not [string]::IsNullOrWhiteSpace($AppId))
	{
		$controlSet = $null
		if ($Script:AppsQueuedActionControlMap.TryGetValue([string]$AppId, [ref]$controlSet))
		{
			$controlPairs = @([pscustomobject]@{
				AppId = [string]$AppId
				Controls = $controlSet
			})
		}
	}
	else
	{
		foreach ($pair in @($Script:AppsQueuedActionControlMap.GetEnumerator()))
		{
			if (-not $pair.Value) { continue }
			$controlPairs += [pscustomobject]@{
				AppId = [string]$pair.Key
				Controls = $pair.Value
			}
		}
	}

	if ($controlPairs.Count -eq 0) { return }

	$Script:AppsQueuedActionUiUpdating = $true
	try
	{
		foreach ($pair in @($controlPairs))
		{
			$action = Get-AppQueuedAction -AppId $pair.AppId
			$controls = $pair.Controls
			if (-not $controls) { continue }

			try
			{
				# Legacy radio-style controls (kept for backwards compatibility).
				if ($controls.PSObject.Properties['Install'] -and $controls.Install -and $controls.Install -is [System.Windows.Controls.Primitives.ToggleButton])
				{
					$controls.Install.IsChecked = ([string]$action -eq 'Install')
				}
				if ($controls.PSObject.Properties['Uninstall'] -and $controls.Uninstall -and $controls.Uninstall -is [System.Windows.Controls.Primitives.ToggleButton])
				{
					$controls.Uninstall.IsChecked = ([string]$action -eq 'Uninstall')
				}
				if ($controls.PSObject.Properties['DoNothing'] -and $controls.DoNothing -and $controls.DoNothing -is [System.Windows.Controls.Primitives.ToggleButton])
				{
					$controls.DoNothing.IsChecked = ([string]$action -eq 'DoNothing')
				}

				# Card primary/update button chrome + queued badge.
				$primaryButton = if ($controls.PSObject.Properties['PrimaryButton']) { $controls.PrimaryButton } else { $null }
				$updateButton  = if ($controls.PSObject.Properties['UpdateButton'])  { $controls.UpdateButton }  else { $null }
				$primaryKind   = if ($controls.PSObject.Properties['PrimaryActionKind']) { [string]$controls.PrimaryActionKind } else { '' }
				$badge         = if ($controls.PSObject.Properties['Badge']) { $controls.Badge } else { $null }
				$badgeText     = if ($controls.PSObject.Properties['BadgeText']) { $controls.BadgeText } else { $null }

				if ($primaryButton)
				{
					$primaryQueued = ($primaryKind -and [string]$action -eq $primaryKind)
					$primaryVariant = if ($primaryQueued) { 'Subtle' } else { 'Primary' }
					try { Set-ButtonChrome -Button $primaryButton -Variant $primaryVariant -Compact } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.SetButtonChrome.Primary' }
				}
				if ($updateButton)
				{
					$updateQueued = ([string]$action -eq 'Update')
					$updateVariant = if ($updateQueued) { 'Subtle' } else { 'Secondary' }
					try { Set-ButtonChrome -Button $updateButton -Variant $updateVariant -Compact } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.SetButtonChrome.Update' }
				}
				if ($badge -and $badgeText)
				{
					if ([string]$action -eq 'DoNothing' -or [string]::IsNullOrWhiteSpace([string]$action))
					{
						$badge.Visibility = [System.Windows.Visibility]::Collapsed
					}
					else
					{
						$badgeLabel = switch ([string]$action)
						{
							'Install'   { (Get-UxLocalizedString -Key 'GuiAppsQueuedInstall'   -Fallback 'Queued: Install') }
							'Uninstall' { (Get-UxLocalizedString -Key 'GuiAppsQueuedUninstall' -Fallback 'Queued: Uninstall') }
							'Update'    { (Get-UxLocalizedString -Key 'GuiAppsQueuedUpdate'    -Fallback 'Queued: Update') }
							default     { (Get-UxLocalizedString -Key 'GuiAppsQueued' -Fallback 'Queued') }
						}
						Set-GuiAppsQueuedBadgeChrome -Badge $badge -BadgeText $badgeText
						$badgeText.Text = $badgeLabel
						$badge.Visibility = [System.Windows.Visibility]::Visible
					}
				}
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'SelectionQueueState.Sync-AppsQueuedActionControls:catch354' -Severity Debug }

				$null = $_
			}
		}
	}
	finally
	{
		$Script:AppsQueuedActionUiUpdating = $false
	}
}

<#
    .SYNOPSIS
#>

function Get-QueuedAppsProfileActions
{
	<#
		.SYNOPSIS
		Builds a portable list of queued app actions for configuration profiles.
	#>
	[CmdletBinding()]
	param ()

	Initialize-AppsQueuedActionState

	$catalog = if (Get-Command -Name 'Get-LoadedBaselineApplicationsCatalog' -CommandType Function -ErrorAction SilentlyContinue) { @(Get-LoadedBaselineApplicationsCatalog) } else { @(Get-BaselineApplicationsCatalog) }
	if ($catalog.Count -eq 0 -or $Script:AppsQueuedActions.Count -eq 0)
	{
		return @()
	}

	$profileActions = [System.Collections.Generic.List[object]]::new()
	foreach ($app in @($catalog))
	{
		if (-not $app) { continue }

		$appId = Get-ApplicationCatalogIdentityKey -Entry $app
		$action = Get-AppQueuedAction -AppId $appId
		if ([string]::IsNullOrWhiteSpace([string]$action) -or $action -eq 'DoNothing')
		{
			continue
		}

		$profileActions.Add([ordered]@{
			AppId = [string]$appId
			Action = [string]$action
			Name = if ($app.PSObject.Properties['Name']) { [string]$app.Name } else { $null }
			WinGetId = if ($app.PSObject.Properties['WinGetId']) { [string]$app.WinGetId } else { $null }
			ChocoId = if ($app.PSObject.Properties['ChocoId']) { [string]$app.ChocoId } else { $null }
		}) | Out-Null
	}

	return @($profileActions)
}

<#
    .SYNOPSIS
#>

function Set-AppQueuedAction
{
	<#
		.SYNOPSIS
		Records the desired action for a single app in the pending queue.

		.DESCRIPTION
		Sets the per-app queued action to Install, Uninstall, or DoNothing.
		Setting DoNothing (the default) removes the entry so the queue stays
		clean and only explicitly requested changes are applied.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$AppId,

		[Parameter(Mandatory)]
		[ValidateSet('Install', 'Uninstall', 'Update', 'DoNothing')]
		[string]$Action
	)

	Initialize-AppsQueuedActionState
	$normalizedId = [string]$AppId.Trim()
	if ([string]::IsNullOrWhiteSpace($normalizedId)) { return }

	if ($Action -eq 'DoNothing')
	{
		[void]$Script:AppsQueuedActions.Remove($normalizedId)
	}
	else
	{
		$Script:AppsQueuedActions[$normalizedId] = $Action
	}

	Sync-AppsQueuedActionControls -AppId $normalizedId
	Update-AppsSelectionSummary
}

<#
    .SYNOPSIS
#>

function Get-AppQueuedAction
{
	<#
		.SYNOPSIS
		Returns the queued action for an app (Install, Uninstall, or DoNothing).
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$AppId
	)

	Initialize-AppsQueuedActionState
	$normalizedId = [string]$AppId.Trim()
	if ([string]::IsNullOrWhiteSpace($normalizedId))
	{
		return 'DoNothing'
	}
	$value = $null
	if ($Script:AppsQueuedActions.TryGetValue($normalizedId, [ref]$value))
	{
		return $value
	}
	return 'DoNothing'
}

<#
    .SYNOPSIS
#>

function Clear-AppsQueuedActions
{
	<#
		.SYNOPSIS
		Clears all pending queued app actions without touching the selection state.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[CmdletBinding()]
	param ()

	Initialize-AppsQueuedActionState
	$Script:AppsQueuedActions.Clear()
	Sync-AppsQueuedActionControls
	Update-AppsSelectionSummary
}

<#
    .SYNOPSIS
#>

function Get-SelectedAppsCatalogItems
{
	[CmdletBinding()]
	param ()

	Initialize-AppsSelectionState

	if (-not $Script:SelectedAppIds -or $Script:SelectedAppIds.Count -eq 0)
	{
		return @()
	}

	$catalog = if (Get-Command -Name 'Get-LoadedBaselineApplicationsCatalog' -CommandType Function -ErrorAction SilentlyContinue) { @(Get-LoadedBaselineApplicationsCatalog) } else { @(Get-BaselineApplicationsCatalog) }
	if ($catalog.Count -eq 0)
	{
		return @()
	}

	return @(
		$catalog |
			Where-Object {
				if (-not $_)
				{
					$false
				}
				else
				{
					$selectionKey = Get-ApplicationCatalogIdentityKey -Entry $_
					-not [string]::IsNullOrWhiteSpace($selectionKey) -and $Script:SelectedAppIds.Contains([string]$selectionKey)
				}
			}
	)
}

<#
    .SYNOPSIS
#>

function Update-AppsSelectionSummary
{
	[CmdletBinding()]
	param ()

	foreach ($controlVariableName in @('TxtAppSelectionStatus', 'BtnInstallSelectedApps', 'BtnUninstallSelectedApps', 'BtnUpdateSelectedApps', 'BtnScanInstalledApps', 'BtnApplyQueuedActions', 'BtnClearQueuedActions'))
	{
		if (-not (Get-Variable -Name $controlVariableName -Scope Script -ErrorAction SilentlyContinue))
		{
			Set-Variable -Name $controlVariableName -Scope Script -Value $null
		}
	}

	if (-not $Script:TxtAppSelectionStatus -and -not $Script:BtnInstallSelectedApps -and -not $Script:BtnUninstallSelectedApps -and -not $Script:BtnUpdateSelectedApps -and -not $Script:BtnScanInstalledApps -and -not $Script:BtnApplyQueuedActions -and -not $Script:BtnClearQueuedActions)
	{
		return
	}

	Initialize-AppsSelectionState

	$selectedApps = @(Get-SelectedAppsCatalogItems)
	$selectedCount = $selectedApps.Count
	Initialize-AppsQueuedActionState
	$queuedCount = if ($Script:AppsQueuedActions) { $Script:AppsQueuedActions.Count } else { 0 }
	$theme = Get-GuiCurrentTheme
	if (-not $theme)
	{
		$theme = $Script:CurrentTheme
	}
	$bc = New-SafeBrushConverter -Context 'Update-AppsSelectionSummary'

	if ($Script:TxtAppSelectionStatus)
	{
		$selectionLabel = switch ($selectedCount)
		{
			0 { (Get-UxLocalizedString -Key 'GuiAppsNoSelection' -Fallback '0 selected') }
			1 { (Get-UxLocalizedString -Key 'GuiAppsSingleSelected' -Fallback '1 selected') }
			default { (Get-UxLocalizedString -Key 'GuiAppsMultipleSelected' -Fallback '{0} selected' -FormatArgs @($selectedCount)) }
		}
		if ($queuedCount -gt 0)
		{
			$queuedLabel = if ($queuedCount -eq 1)
			{
				(Get-UxLocalizedString -Key 'GuiAppsQueuedSingle' -Fallback '1 queued change')
			}
			else
			{
				(Get-UxLocalizedString -Key 'GuiAppsQueuedMultiple' -Fallback '{0} queued changes' -FormatArgs @($queuedCount))
			}
			$selectionLabel = '{0} | {1}' -f $selectionLabel, $queuedLabel
		}
		$Script:TxtAppSelectionStatus.Text = $selectionLabel
		if ($Script:TxtAppSelectionStatus.PSObject.Properties['FontWeight'])
		{
			$Script:TxtAppSelectionStatus.FontWeight = $(if ($selectedCount -gt 0) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal })
		}
		if ($theme)
		{
			$Script:TxtAppSelectionStatus.Foreground = $bc.ConvertFromString($(if ($selectedCount -gt 0) { $theme.AccentBlue } else { $theme.TextSecondary }))
		}
	}

		$cacheReady = [bool]($Script:AppsViewLoaded -and -not $Script:AppsViewDirty)
		$installDisabledTooltip = if ($Script:AppsOperationInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionBusyTooltip' -Fallback 'Wait for the current app action to finish before starting another one.')
		}
		elseif ($Script:AppsCacheRefreshInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionRefreshTooltip' -Fallback 'Wait for the app catalog to finish scanning before selecting actions.')
		}
		elseif ($selectedCount -eq 0)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionSelectTooltip' -Fallback 'Select at least one app to enable this action.')
		}
		else
		{
			$null
		}
		$catalogActionDisabledTooltip = if ($Script:AppsOperationInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionBusyTooltip' -Fallback 'Wait for the current app action to finish before starting another one.')
		}
		elseif ($Script:AppsCacheRefreshInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionRefreshTooltip' -Fallback 'Wait for the app catalog to finish scanning before selecting actions.')
		}
		elseif ($selectedCount -eq 0)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionSelectTooltip' -Fallback 'Select at least one app to enable this action.')
		}
		elseif (-not $cacheReady)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionCatalogRequiredTooltip' -Fallback 'Scan installed apps before uninstalling or updating.')
		}
		else
		{
			$null
		}
		$scanDisabledTooltip = if ($Script:AppsOperationInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionBusyTooltip' -Fallback 'Wait for the current app action to finish before starting another one.')
		}
		elseif ($Script:AppsCacheRefreshInProgress)
		{
			(Get-UxLocalizedString -Key 'GuiAppsActionRefreshTooltip' -Fallback 'Wait for the app catalog to finish scanning before selecting actions.')
		}
		else
		{
			$null
		}

		if ($Script:BtnInstallSelectedApps)
		{
			$Script:BtnInstallSelectedApps.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and ($selectedCount -gt 0)
			$Script:BtnInstallSelectedApps.ToolTip = if ($installDisabledTooltip) { $installDisabledTooltip } else { (Get-UxLocalizedString -Key 'GuiAppsQueueInstallTip' -Fallback 'Stage installs for every checked app. They run when you click Apply Changes.') }
		}
		if ($Script:BtnUninstallSelectedApps)
		{
			$Script:BtnUninstallSelectedApps.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and $cacheReady -and ($selectedCount -gt 0)
			$Script:BtnUninstallSelectedApps.ToolTip = if ($catalogActionDisabledTooltip) { $catalogActionDisabledTooltip } else { (Get-UxLocalizedString -Key 'GuiAppsQueueUninstallTip' -Fallback 'Stage uninstalls for every checked app. They run when you click Apply Changes.') }
		}
		if ($Script:BtnUpdateSelectedApps)
		{
			$Script:BtnUpdateSelectedApps.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and $cacheReady -and ($selectedCount -gt 0)
			$Script:BtnUpdateSelectedApps.ToolTip = if ($catalogActionDisabledTooltip) { $catalogActionDisabledTooltip } else { (Get-UxLocalizedString -Key 'GuiAppsQueueUpdateTip' -Fallback 'Stage updates for every checked app. They run when you click Apply Changes.') }
		}
		if ($Script:BtnScanInstalledApps)
		{
			$Script:BtnScanInstalledApps.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress)
			$Script:BtnScanInstalledApps.ToolTip = if ($scanDisabledTooltip) { $scanDisabledTooltip } else { (Get-UxLocalizedString -Key 'GuiAppsScanInstalledAppsTip' -Fallback 'Scan installed apps to update install status.') }
		}
		if ($Script:BtnApplyQueuedActions)
		{
			$Script:BtnApplyQueuedActions.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and ($queuedCount -gt 0)
			$Script:BtnApplyQueuedActions.ToolTip = if ($queuedCount -eq 0)
			{
				(Get-UxLocalizedString -Key 'GuiAppsApplyQueuedEmptyTip' -Fallback 'Queue an install or uninstall action first.')
			}
			elseif ($Script:AppsOperationInProgress -or $Script:AppsCacheRefreshInProgress)
			{
				(Get-UxLocalizedString -Key 'GuiAppsActionBusyTooltip' -Fallback 'Wait for the current app action to finish before starting another one.')
			}
			else
			{
				(Get-UxLocalizedString -Key 'GuiAppsApplyQueuedTip' -Fallback 'Apply queued install and uninstall changes.')
			}
		}
		if ($Script:BtnClearQueuedActions)
		{
			$Script:BtnClearQueuedActions.IsEnabled = (-not $Script:AppsOperationInProgress) -and (-not $Script:AppsCacheRefreshInProgress) -and (($queuedCount -gt 0) -or ($selectedCount -gt 0))
			$Script:BtnClearQueuedActions.ToolTip = if ($queuedCount -eq 0 -and $selectedCount -eq 0)
			{
				(Get-UxLocalizedString -Key 'GuiAppsResetEmptyTip' -Fallback 'Nothing to reset.')
			}
			elseif ($Script:AppsOperationInProgress -or $Script:AppsCacheRefreshInProgress)
			{
				(Get-UxLocalizedString -Key 'GuiAppsActionBusyTooltip' -Fallback 'Wait for the current app action to finish before starting another one.')
			}
			else
			{
				(Get-UxLocalizedString -Key 'GuiAppsResetTip' -Fallback 'Clear all queued changes and checked applications.')
			}
		}
	}

<#
    .SYNOPSIS
#>

function Set-AppSelectionState
{
	[CmdletBinding()]
	param (
		[Alias('WinGetId', 'AppKey', 'ApplicationId')]
		[string]$SelectionKey,

		[bool]$Selected = $false
	)

	if ([string]::IsNullOrWhiteSpace($SelectionKey))
	{
		return
	}

	Initialize-AppsSelectionState
	$normalizedId = [string]$SelectionKey.Trim()
	if ($Selected)
	{
		[void]$Script:SelectedAppIds.Add($normalizedId)
	}
	else
	{
		[void]$Script:SelectedAppIds.Remove($normalizedId)
	}

	Update-AppsSelectionSummary
}

<#
    .SYNOPSIS
#>

function Clear-AppSelectionState
{
	[CmdletBinding()]
	param ()

	Initialize-AppsSelectionState

	if ($Script:AppsSelectionUiUpdating)
	{
		return
	}

	$Script:AppsSelectionUiUpdating = $true
	try
	{
		$Script:SelectedAppIds.Clear()
		foreach ($selectionControl in @($Script:AppsSelectionControls))
		{
			if ($selectionControl)
			{
				try { $selectionControl.IsChecked = $false } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Clear-AppSelectionState.SelectionControlIsCheckedFalse' }
			}
		}
	}
	finally
	{
		$Script:AppsSelectionUiUpdating = $false
	}

	Update-AppsSelectionSummary
}
