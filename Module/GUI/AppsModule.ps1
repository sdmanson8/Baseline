
# App-focused helpers used by the Baseline GUI.

# Keep this explicit order so catalog, state, and chrome helpers load before orchestration entrypoints.
$appsModuleSplitRoot = Join-Path $PSScriptRoot 'AppsModule'
. (Join-Path $appsModuleSplitRoot 'CatalogHelpers.ps1')
. (Join-Path $appsModuleSplitRoot 'SelectionQueueState.ps1')
. (Join-Path $appsModuleSplitRoot 'ProgressNavChrome.ps1')

function Start-AppsModuleQueuedActionAsync
{
	<#
		.SYNOPSIS
		Applies the per-app queued actions (Install / Uninstall) in a single pass.

		.DESCRIPTION
		Reads $Script:AppsQueuedActions, groups apps by requested action, and
		dispatches one Start-AppsModuleBatchActionAsync call per action type.
		Install and uninstall batches are sequenced so the app action runspace has
		time to finish, refresh caches, and return to an idle state before the next
		group begins. The queue is cleared after the last group finishes.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
	[CmdletBinding()]
	param ()

	Initialize-AppsQueuedActionState

	if ($Script:AppsQueuedActions.Count -eq 0) { return }
	if ($Script:AppsOperationInProgress -or $Script:AppsCacheRefreshInProgress) { return }

	$startAppsModuleBatchActionAsyncCommand = Get-GuiRuntimeCommand -Name 'Start-AppsModuleBatchActionAsync' -CommandType 'Function'
	$clearAppsQueuedActionsCommand = Get-GuiRuntimeCommand -Name 'Clear-AppsQueuedActions' -CommandType 'Function'
	if (-not $startAppsModuleBatchActionAsyncCommand) { throw 'Start-AppsModuleBatchActionAsync not found.' }
	if (-not $clearAppsQueuedActionsCommand) { throw 'Clear-AppsQueuedActions not found.' }

	$catalog = if (Get-Command -Name 'Get-LoadedBaselineApplicationsCatalog' -CommandType Function -ErrorAction SilentlyContinue) { @(Get-LoadedBaselineApplicationsCatalog) } else { @($Script:BaselineApplicationsCatalog) }
	if (-not $catalog) { return }

	$installApps   = [System.Collections.Generic.List[object]]::new()
	$uninstallApps = [System.Collections.Generic.List[object]]::new()
	$updateApps    = [System.Collections.Generic.List[object]]::new()
	foreach ($app in @($catalog))
	{
		if (-not $app) { continue }
		$appId = Get-ApplicationCatalogIdentityKey -Entry $app
		switch ((Get-AppQueuedAction -AppId $appId))
		{
			'Install'   { [void]$installApps.Add($app) }
			'Uninstall' { [void]$uninstallApps.Add($app) }
			'Update'    { [void]$updateApps.Add($app) }
		}
	}

	$taskQueue = [System.Collections.Generic.List[object]]::new()
	if ($installApps.Count -gt 0)
	{
		[void]$taskQueue.Add([pscustomobject]@{ Action = 'Install'; Apps = @($installApps) })
	}
	if ($uninstallApps.Count -gt 0)
	{
		[void]$taskQueue.Add([pscustomobject]@{ Action = 'Uninstall'; Apps = @($uninstallApps) })
	}
	if ($updateApps.Count -gt 0)
	{
		[void]$taskQueue.Add([pscustomobject]@{ Action = 'Update'; Apps = @($updateApps) })
	}

	if ($taskQueue.Count -eq 0)
	{
		& $clearAppsQueuedActionsCommand
		return
	}

	$applyState = [pscustomobject]@{
		Tasks = @($taskQueue)
		Index = 0
		Active = $false
		Timer = $null
	}
	$getUxBilingualLocalizedStringCapture = Get-GuiFunctionCapture -Name 'Get-UxBilingualLocalizedString'
	if (-not $getUxBilingualLocalizedStringCapture) { throw 'Get-UxBilingualLocalizedString not found.' }

	$applyTick = {
		try
		{
			if ($Script:AppsOperationInProgress -or $Script:AppsCacheRefreshInProgress)
			{
				return
			}

			if ($applyState.Active)
			{
				$applyState.Active = $false
				$applyState.Index++
			}

			if ($applyState.Index -ge $applyState.Tasks.Count)
			{
				try { $applyState.Timer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsModuleQueuedActionAsync.TimerStop' }
				$applyState.Timer = $null
				& $clearAppsQueuedActionsCommand
				return
			}

			$currentTask = $applyState.Tasks[$applyState.Index]
			if (-not $currentTask) { return }

			$action = [string]$currentTask.Action
			$apps = @($currentTask.Apps)
			if ($apps.Count -eq 0)
			{
				$applyState.Index++
				return
			}

			$applyState.Active = $true
			& $startAppsModuleBatchActionAsyncCommand -Action $action -SelectedApps $apps
		}
		catch
		{
			LogError (Format-BaselineErrorForLog -ErrorObject $_ -Prefix (& $getUxBilingualLocalizedStringCapture -Key 'GuiLogExecutionAppQueueStateFailed' -Fallback 'Failed to apply queued app actions'))
			try { $applyState.Timer.Stop() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsModuleQueuedActionAsync.TimerStop' }
			$applyState.Timer = $null
			& $clearAppsQueuedActionsCommand
		}
	}.GetNewClosure()

	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(250)
	$timer.Add_Tick($applyTick)
	$applyState.Timer = $timer
	$timer.Start()
	& $applyTick
}

<#
    .SYNOPSIS
#>

function Build-AppsViewCards
{
	[CmdletBinding()]
	param ()

	if (-not $Script:AppsWrapPanel) { return }

	$bc = New-SafeBrushConverter -Context 'Build-AppsViewCards'
	$theme = Get-GuiCurrentTheme
	Initialize-AppsSelectionState
	$packageManagerAvailabilityState = $null
	if (Get-Command -Name 'Get-AppsPackageManagerAvailabilityState' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try
		{
			$packageManagerAvailabilityState = Get-AppsPackageManagerAvailabilityState
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards:catch158' -Severity Debug }

			$packageManagerAvailabilityState = $null
		}
	}
	if (Get-Command -Name 'Update-AppsPackageManagerBanner' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Update-AppsPackageManagerBanner -AvailabilityState $packageManagerAvailabilityState } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.UpdateAppsPackageManagerBanner' }
	}
	$renderSignature = $null
	if (Get-Command -Name 'Get-AppsViewRenderSignature' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$renderSignature = Get-AppsViewRenderSignature -PackageManagerAvailabilityState $packageManagerAvailabilityState
		if ($Script:AppsWrapPanel.Children.Count -gt 0 -and $Script:AppsViewBuildSignature -eq $renderSignature)
		{
			if (Get-Command -Name 'Update-AppsCategoryTabCounts' -CommandType Function -ErrorAction SilentlyContinue)
			{
				try { Update-AppsCategoryTabCounts } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.UpdateAppsCategoryTabCountsCached' }
			}
			Sync-AppsQueuedActionControls
			Update-AppsSelectionSummary
			return
		}
	}
	$Script:AppsWrapPanel.Children.Clear()
	$appsViewModeActive = if ([string]::IsNullOrWhiteSpace([string]$Script:AppsViewMode)) { 'Cards' } else { [string]$Script:AppsViewMode }
	if ($appsViewModeActive -eq 'List')
	{
		$Script:AppsWrapPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
		$Script:AppsWrapPanel.ItemWidth = [double]::NaN
		$Script:AppsWrapPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
		$Script:AppsWrapPanel.Margin = [System.Windows.Thickness]::new(10, 10, 10, 10)
	}
	else
	{
		$Script:AppsWrapPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
		$Script:AppsWrapPanel.ItemWidth = [double]::NaN
		$Script:AppsWrapPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
		$Script:AppsWrapPanel.Margin = [System.Windows.Thickness]::new(10)
	}
	if ($Script:AppsActionButtons -is [System.Collections.Generic.List[object]])
	{
		$Script:AppsActionButtons.Clear()
	}
	else
	{
		$Script:AppsActionButtons = [System.Collections.Generic.List[object]]::new()
	}
	if ($Script:AppsSelectionControls -is [System.Collections.Generic.List[object]])
	{
		$Script:AppsSelectionControls.Clear()
	}
	else
	{
		$Script:AppsSelectionControls = [System.Collections.Generic.List[object]]::new()
	}
	if ($Script:AppsQueuedActionControls -is [System.Collections.Generic.List[object]])
	{
		$Script:AppsQueuedActionControls.Clear()
	}
	else
	{
		$Script:AppsQueuedActionControls = [System.Collections.Generic.List[object]]::new()
	}
	if ($Script:AppsQueuedActionControlMap -is [System.Collections.Generic.Dictionary[string, object]])
	{
		$Script:AppsQueuedActionControlMap.Clear()
	}
	else
	{
		$Script:AppsQueuedActionControlMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}

	Update-AppCategoryFilterList
	Update-AppStatusFilterList
	if (Get-Command -Name 'Update-AppsCategoryTabCounts' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Update-AppsCategoryTabCounts } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Build-AppsViewCards.UpdateAppsCategoryTabCounts' }
	}
	$allCatalog = @(Get-BaselineApplicationsCatalog)
	$activeSearchQuery = if ($Script:AppsModeActive) { [string]$Script:AppsSearchText } else { [string]$Script:SearchText }
	$catalog = @(Get-AppsCatalogItemsBySearchStatusAndSourceFilters -SearchQuery $activeSearchQuery)

	# Per Apps Filter spec: if a previously selected app has been hidden by the
	# current filter combination, drop it from the selection set so bulk actions
	# only operate on what the user can actually see.
	if ($Script:SelectedAppIds -and $Script:SelectedAppIds.Count -gt 0)
	{
		$visibleKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
		foreach ($visibleEntry in $catalog)
		{
			if (-not $visibleEntry) { continue }
			$visibleKey = Get-ApplicationCatalogIdentityKey -Entry $visibleEntry
			if (-not [string]::IsNullOrWhiteSpace([string]$visibleKey))
			{
				[void]$visibleKeys.Add([string]$visibleKey)
			}
		}
		$stale = @($Script:SelectedAppIds | Where-Object { -not $visibleKeys.Contains([string]$_) })
		if ($stale.Count -gt 0)
		{
			foreach ($staleKey in $stale)
			{
				[void]$Script:SelectedAppIds.Remove([string]$staleKey)
			}
			if (Get-Command -Name 'Update-AppsSelectionSummary' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Update-AppsSelectionSummary
			}
		}
	}
	$cacheReady = [bool]($Script:AppsViewLoaded -and -not $Script:AppsViewDirty)
	$installedCacheSnapshot = Get-ApplicationCacheSnapshot -CacheState $Script:InstalledAppsCache
	$installedWingetCache = $installedCacheSnapshot.WinGet
	$installedChocolateyCache = $installedCacheSnapshot.Chocolatey
	$wingetUpdateCache = $installedCacheSnapshot.WinGetUpdates
	$chocolateyUpdateCache = $installedCacheSnapshot.ChocolateyUpdates
	$cacheRefreshPrompt = if (Get-Command -Name 'Get-AppsCacheRefreshPromptText' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Get-AppsCacheRefreshPromptText
	}
	else
	{
		(Get-UxLocalizedString -Key 'GuiAppsCacheRefreshRequired' -Fallback 'Installed status not scanned')
	}
	$setAppSelectionStateCommand = Get-GuiRuntimeCommand -Name 'Set-AppSelectionState' -CommandType 'Function'
	$setAppQueuedActionCommand = Get-GuiRuntimeCommand -Name 'Set-AppQueuedAction' -CommandType 'Function'
	$startAppsModuleActionAsyncCommand = Get-GuiRuntimeCommand -Name 'Start-AppsModuleActionAsync' -CommandType 'Function'
	$showGuiRuntimeFailureCommand = Get-GuiFunctionCapture -Name 'Invoke-GuiRuntimeFailureReport'
	if (-not $setAppSelectionStateCommand) { throw 'Set-AppSelectionState not found.' }
	if (-not $setAppQueuedActionCommand) { throw 'Set-AppQueuedAction not found.' }
	if (-not $startAppsModuleActionAsyncCommand) { throw 'Start-AppsModuleActionAsync not found.' }
	if (-not $showGuiRuntimeFailureCommand) { throw 'Invoke-GuiRuntimeFailureReport not found.' }

	if ($allCatalog.Count -eq 0)
	{
		$emptyState = [System.Windows.Controls.Border]::new()
		$emptyState.Margin = [System.Windows.Thickness]::new(12)
		$emptyState.Padding = [System.Windows.Thickness]::new(18)
		$emptyState.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$emptyState.Background = $bc.ConvertFromString($theme.CardBg)
		$emptyState.BorderBrush = $bc.ConvertFromString($theme.CardBorder)
		$emptyState.BorderThickness = [System.Windows.Thickness]::new(1)
		$emptyState.Child = [System.Windows.Controls.TextBlock]::new()
		$emptyState.Child.Text = (Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoPackageBackedApplications' -Fallback 'No package-backed applications were found.')
		$emptyState.Child.TextWrapping = 'Wrap'
		$emptyState.Child.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		[void]$Script:AppsWrapPanel.Children.Add($emptyState)
		$emptySummaryText = (Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoPackageBackedApplications' -Fallback 'No package-backed applications were found.')
		if ($Script:TxtAppsProgressText) { $Script:TxtAppsProgressText.Text = $emptySummaryText }
		$Script:AppsViewBuildSignature = $renderSignature
		Update-AppsSelectionSummary
		return
	}

	if ($catalog.Count -eq 0)
	{
		$emptyMessage = if ($activeStatusFilter -eq 'Installed')
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoInstalled' -Fallback 'No installed applications match the current filters.')
		}
		elseif ($activeStatusFilter -eq 'NotInstalled')
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoNotInstalled' -Fallback 'Every application in the current filters is already installed.')
		}
		elseif ($activeStatusFilter -eq 'UpdateAvailable')
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoUpdates' -Fallback 'No updates are available for the current filters.')
		}
		elseif (-not [string]::IsNullOrWhiteSpace([string]$activeSearchQuery) -and ($Script:AppsCategoryFilter -and $Script:AppsCategoryFilter -ne 'All'))
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateSearchAndCategory' -Fallback 'No apps match your search in the selected category.')
		}
		elseif (-not [string]::IsNullOrWhiteSpace([string]$activeSearchQuery))
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateSearch' -Fallback 'No apps match your search.')
		}
		elseif ($Script:AppsCategoryFilter -and $Script:AppsCategoryFilter -ne 'All')
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoCategoryMatches' -Fallback 'No applications match the selected category.')
		}
		else
		{
			(Get-UxLocalizedString -Key 'GuiAppsEmptyStateNoPackageBackedApplications' -Fallback 'No package-backed applications were found.')
		}
		$emptyState = [System.Windows.Controls.Border]::new()
		$emptyState.Margin = [System.Windows.Thickness]::new(12)
		$emptyState.Padding = [System.Windows.Thickness]::new(18)
		$emptyState.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$emptyState.Background = $bc.ConvertFromString($theme.CardBg)
		$emptyState.BorderBrush = $bc.ConvertFromString($theme.CardBorder)
		$emptyState.BorderThickness = [System.Windows.Thickness]::new(1)
		$emptyState.Child = [System.Windows.Controls.TextBlock]::new()
		$emptyState.Child.Text = $emptyMessage
		$emptyState.Child.TextWrapping = 'Wrap'
		$emptyState.Child.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		[void]$Script:AppsWrapPanel.Children.Add($emptyState)
		if ($Script:TxtAppsProgressText)
		{
			$installedCount = 0
			$updateAvailableCount = 0
			foreach ($entry in @($allCatalog))
			{
				if (-not $entry) { continue }
				$appState = Get-ApplicationExecutionState -Entry $entry -WinGetInstalledCache $installedWingetCache -ChocolateyInstalledCache $installedChocolateyCache -WinGetUpdateCache $wingetUpdateCache -ChocolateyUpdateCache $chocolateyUpdateCache -PreferredSource $Script:AppsPackageSourcePreference
				if ($appState.IsInstalled)
				{
					$installedCount++
				}
				if ($appState.UpdateAvailable)
				{
					$updateAvailableCount++
				}
			}
			$summaryText = if ($updateAvailableCount -gt 0)
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryWithUpdates' -Fallback 'Installed: {0}/{1} | Updates available: {2} | Showing: 0/{1}'), $installedCount, $allCatalog.Count, $updateAvailableCount)
			}
			else
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummary' -Fallback 'Installed: {0}/{1} | Showing: 0/{1}'), $installedCount, $allCatalog.Count)
			}
			$Script:TxtAppsProgressText.Text = $summaryText
		}
		$Script:AppsViewBuildSignature = $renderSignature
		Update-AppsSelectionSummary
		return
	}

	$sortedCatalog = @($catalog | Sort-Object SubCategory, Name)
	$buildProgressLabel = [string]::Format(
		(Get-UxLocalizedString -Key 'GuiAppsLoadingCatalog' -Fallback 'Loading {0}...'),
		(Get-UxLocalizedString -Key 'Category_SoftwareApps_Title' -Fallback 'Software & Apps')
	)
	$installedCount = 0
	$updateAvailableCount = 0
	if ($Script:TxtAppsProgressText -and $buildProgressLabel)
	{
		$Script:TxtAppsProgressText.Text = $buildProgressLabel
	}

		. (Join-Path $PSScriptRoot 'AppsModule\Build-AppsViewCards\Build-AppsViewCards.ps1')

	if (-not $cacheReady)
	{
		if ($Script:TxtAppsProgressText)
		{
			$Script:TxtAppsProgressText.Text = $cacheRefreshPrompt
		}
		Update-AppsSelectionSummary
		return
	}

	if ($Script:TxtAppsProgressText)
	{
		$filterActive = ($Script:AppsCategoryFilter -and $Script:AppsCategoryFilter -ne 'All') -or ($activeStatusFilter -and $activeStatusFilter -ne 'All')
		$summaryText = if ($filterActive)
		{
			if ($updateAvailableCount -gt 0)
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryFilteredWithUpdates' -Fallback 'Installed: {0}/{1} | Updates available: {2} | Showing: {3}/{1}'), $installedCount, $allCatalog.Count, $updateAvailableCount, $catalog.Count)
			}
			else
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryFiltered' -Fallback 'Installed: {0}/{1} | Showing: {2}/{1}'), $installedCount, $allCatalog.Count, $catalog.Count)
			}
		}
		else
		{
			if ($updateAvailableCount -gt 0)
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryAllWithUpdates' -Fallback 'Installed: {0}/{1} | Updates available: {2}'), $installedCount, $allCatalog.Count, $updateAvailableCount)
			}
			else
			{
				[string]::Format((Get-UxLocalizedString -Key 'AppStatusSummaryAll' -Fallback 'Installed: {0}/{1}'), $installedCount, $allCatalog.Count)
			}
		}
		$Script:TxtAppsProgressText.Text = $summaryText
	}
	$Script:AppsViewBuildSignature = $renderSignature
	Update-AppsSelectionSummary
}

<#
    .SYNOPSIS
#>

function Start-AppsCacheRefresh
{
	[CmdletBinding()]
	param ()

	$scanEntryTrace = Join-Path $env:TEMP 'Baseline-ScanEntry-trace.txt'
	try { "$([DateTime]::UtcNow.ToString('o'))`tStart-AppsCacheRefresh entered (InProgress={0})" -f $Script:AppsCacheRefreshInProgress | Out-File -FilePath $scanEntryTrace -Append -Encoding UTF8 -Force } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.WriteEntryTrace' }

	if ($Script:AppsCacheRefreshInProgress)
	{
		if (Get-Command -Name 'LogInfo' -CommandType Function, Alias -ErrorAction SilentlyContinue)
		{
			LogInfo 'Installed app scan is already running.'
		}
		return
	}

	$Script:AppsCacheRefreshInProgress = $true
	Set-AppsActionControlsEnabled -Enabled $false
	if (Get-Command -Name 'LogInfo' -CommandType Function, Alias -ErrorAction SilentlyContinue)
	{
		LogInfo 'Scanning installed apps...'
	}
	$runspace = $null
	$ps = $null
	try
	{
	# Resolve every localized label here on the UI thread. The background
	# runspace does NOT have Get-UxLocalizedString / Get-UxBilingualLocalizedString
	# (they live in Module/GUI/UxPolicy.ps1 and aren't imported by
	# Regions\Applications.psm1), so calling them inside the scriptblock throws
	# "The term 'Get-UxLocalizedString' is not recognized" on the very first
	# line - the runspace errors out, the timer flips to the failure path, and
	# the user sees the Scan button grey out and come right back with zero
	# progress rendered.
	$phaseWinGetInstalled = Get-UxLocalizedString -Key 'Progress_CheckingInstallStatus' -Fallback 'Checking installation status...'
	$phaseChocolateyInstalled = Get-UxLocalizedString -Key 'GuiAppsCacheRefreshScanningChocolateyInstalled' -Fallback 'Checking Chocolatey installation status...'
	$phaseWinGetUpdates = Get-UxLocalizedString -Key 'Progress_WinGet_CheckingUpdates' -Fallback 'Checking for WinGet updates...'
	$phaseChocolateyUpdates = Get-UxLocalizedString -Key 'GuiAppsCacheRefreshScanningChocolateyUpdates' -Fallback 'Checking Chocolatey update availability...'
	$phaseComplete = Get-UxLocalizedString -Key 'GuiAppsCacheRefreshComplete' -Fallback 'Installed apps scanned.'
	$syncHash = [hashtable]::Synchronized(@{
		Completed    = 0
		Total        = 4
		CurrentAction = $phaseWinGetInstalled
		PhaseWinGetInstalled = $phaseWinGetInstalled
		PhaseChocolateyInstalled = $phaseChocolateyInstalled
		PhaseWinGetUpdates = $phaseWinGetUpdates
		PhaseChocolateyUpdates = $phaseChocolateyUpdates
		PhaseComplete = $phaseComplete
		Warnings     = [System.Collections.Generic.List[string]]::new()
		IsComplete   = $false
		Error        = $null
	})
	if ($Script:TxtAppsProgressText)
	{
		$initialProgressText = Set-SharedProgressBarState -ProgressBar $Script:AppsProgressBar -ProgressText $Script:TxtAppsProgressText -Completed $syncHash.Completed -Total $syncHash.Total -CurrentAction $syncHash.CurrentAction -PassThruText
		$Script:TxtAppsProgressText.Text = $initialProgressText
	}

	$appModulePath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Regions\Applications.psm1'
	$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
	$runspace.Open()
	$ps = [System.Management.Automation.PowerShell]::Create()
	$ps.Runspace = $runspace
	$appsGetApplicationCacheSnapshotCommand = Get-Command 'Get-ApplicationCacheSnapshot' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$appsSetSharedProgressBarStateCommand = Get-Command 'Set-SharedProgressBarState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$appsGetUxLocalizedStringCommand = Get-Command 'Get-UxLocalizedString' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$appsBuildAppsViewCardsCommand = Get-Command 'Build-AppsViewCards' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$appsLogInfoCommand = Get-Command 'LogInfo' -CommandType Function, Alias -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $appsLogInfoCommand)
	{
		$appsLogInfoCommand = Get-Command 'Write-BaselineInfo' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	}
	# LogError is exported as an alias for Write-BaselineError (Logging.psm1);
	# without -CommandType Function,Alias this lookup always misses and throws
	# 'LogError not found.' from the guard below - surfaces as GUI-GENERIC-001
	# when the user clicks Scan Installed Apps.
	$appsLogErrorCommand = Get-Command 'LogError' -CommandType Function, Alias -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $appsLogErrorCommand)
	{
		$appsLogErrorCommand = Get-Command 'Write-BaselineError' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	}
	$appsFormatBaselineErrorForLogCommand = Get-Command 'Format-BaselineErrorForLog' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$appsSetActionControlsEnabledCommand = Get-Command 'Set-AppsActionControlsEnabled' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1

	if (-not $appsGetApplicationCacheSnapshotCommand) { throw 'Get-ApplicationCacheSnapshot not found.' }
	if (-not $appsSetSharedProgressBarStateCommand) { throw 'Set-SharedProgressBarState not found.' }
	if (-not $appsGetUxLocalizedStringCommand) { throw 'Get-UxLocalizedString not found.' }
	if (-not $appsBuildAppsViewCardsCommand) { throw 'Build-AppsViewCards not found.' }
	if (-not $appsLogErrorCommand) { throw 'LogError not found.' }
	if (-not $appsFormatBaselineErrorForLogCommand) { throw 'Format-BaselineErrorForLog not found.' }
	if (-not $appsSetActionControlsEnabledCommand) { throw 'Set-AppsActionControlsEnabled not found.' }

	$null = $ps.AddScript({
		param ($ModulePath, $Sync)
		$scanTracePath = Join-Path $env:TEMP 'Baseline-ScanWorker-trace.txt'
		function Write-ScanTrace { param([string]$Message) try { "$([DateTime]::UtcNow.ToString('o'))`t$Message" | Out-File -FilePath $scanTracePath -Append -Encoding UTF8 -Force } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Write-ScanTrace:catch542' -Severity Debug }
		 $null = $_ } }
		Write-ScanTrace "--- scan worker start ---"
		Write-ScanTrace ("ModulePath={0} exists={1}" -f $ModulePath, (Test-Path $ModulePath))
		try
		{
		Write-ScanTrace "Import-Module Applications.psm1 START"
		Import-Module -Force -Global -DisableNameChecking -WarningAction SilentlyContinue -Name $ModulePath
		Write-ScanTrace "Import-Module Applications.psm1 DONE"
		$wingetCache = @{}
		$chocolateyCache = @{}
		$wingetUpdateCache = @{}
		$chocolateyUpdateCache = @{}
		$Sync.Total = 4
		$Sync.Completed = 0
		$Sync.CurrentAction = $Sync.PhaseWinGetInstalled
		try
		{
			$Sync.CurrentAction = $Sync.PhaseWinGetInstalled
			Write-ScanTrace "Get-InstalledAppCache START"
			$wingetCache = Get-InstalledAppCache
			Write-ScanTrace ("Get-InstalledAppCache DONE count={0}" -f (@($wingetCache.Keys).Count))
		}
		catch
		{
			Write-ScanTrace ("Get-InstalledAppCache FAILED: {0}" -f $_.Exception.Message)
			[void]$Sync.Warnings.Add(("WinGet installed-cache scan failed: {0}" -f $_.Exception.Message))
		}
		finally
		{
			$Sync.Completed = 1
		}
		try
		{
			$Sync.CurrentAction = $Sync.PhaseChocolateyInstalled
			Write-ScanTrace "Get-InstalledChocolateyAppCache START"
			$chocolateyCache = Get-InstalledChocolateyAppCache
			Write-ScanTrace ("Get-InstalledChocolateyAppCache DONE count={0}" -f (@($chocolateyCache.Keys).Count))
		}
		catch
		{
			Write-ScanTrace ("Get-InstalledChocolateyAppCache FAILED: {0}" -f $_.Exception.Message)
			[void]$Sync.Warnings.Add(("Chocolatey installed-cache scan failed: {0}" -f $_.Exception.Message))
		}
		finally
		{
			$Sync.Completed = 2
		}
		try
		{
			$Sync.CurrentAction = $Sync.PhaseWinGetUpdates
			Write-ScanTrace "Get-AvailableAppUpdateCache START"
			$wingetUpdateCache = Get-AvailableAppUpdateCache
			Write-ScanTrace ("Get-AvailableAppUpdateCache DONE count={0}" -f (@($wingetUpdateCache.Keys).Count))
		}
		catch
		{
			Write-ScanTrace ("Get-AvailableAppUpdateCache FAILED: {0}" -f $_.Exception.Message)
			[void]$Sync.Warnings.Add(("WinGet update-cache scan failed: {0}" -f $_.Exception.Message))
		}
		finally
		{
			$Sync.Completed = 3
		}
		try
		{
			$Sync.CurrentAction = $Sync.PhaseChocolateyUpdates
			Write-ScanTrace "Get-AvailableChocolateyUpdateCache START"
			$chocolateyUpdateCache = Get-AvailableChocolateyUpdateCache
			Write-ScanTrace ("Get-AvailableChocolateyUpdateCache DONE count={0}" -f (@($chocolateyUpdateCache.Keys).Count))
		}
		catch
		{
			Write-ScanTrace ("Get-AvailableChocolateyUpdateCache FAILED: {0}" -f $_.Exception.Message)
			[void]$Sync.Warnings.Add(("Chocolatey update-cache scan failed: {0}" -f $_.Exception.Message))
		}
		finally
		{
			$Sync.Completed = 4
		}
		$Sync.CurrentAction = $Sync.PhaseComplete
		Write-ScanTrace "--- scan worker complete ---"
		[pscustomobject]@{
			WinGet = $wingetCache
			Chocolatey = $chocolateyCache
			WinGetUpdates = $wingetUpdateCache
			ChocolateyUpdates = $chocolateyUpdateCache
		}
		}
		catch
		{
			Write-ScanTrace ("FATAL CATCH type={0} msg={1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
			if ($_.ScriptStackTrace) { Write-ScanTrace ("ScriptStackTrace: {0}" -f [string]$_.ScriptStackTrace) }
			if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) { Write-ScanTrace ("PositionMessage: {0}" -f [string]$_.InvocationInfo.PositionMessage) }
			$Sync.Error = ("{0}: {1}`n{2}" -f $_.Exception.GetType().FullName, $_.Exception.Message, [string]$_.ScriptStackTrace)
			[void]$Sync.Warnings.Add(("Scan worker fatal: {0}" -f $_.Exception.Message))
			throw
		}
	}).AddArgument($appModulePath).AddArgument($syncHash)

	$asyncResult = $ps.BeginInvoke()
	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(100)

	# Pre-capture UI references and apps module scope as locals.
	# GetNewClosure() rebinds the tick scriptblock to a new module whose
	# $Script: scope is empty, so $Script:AppsProgressBar etc. would resolve
	# to $null inside the tick. We snapshot them here so the closure captures
	# them as regular locals.
	$tickProgressBar = $Script:AppsProgressBar
	$tickProgressText = $Script:TxtAppsProgressText
	$appsScriptScope = $ExecutionContext.SessionState.Module
	$timer.Add_Tick({
		if ($syncHash.Error)
		{
			$timer.Stop()
			& $appsSetSharedProgressBarStateCommand -ProgressBar $tickProgressBar -ProgressText $tickProgressText -Completed 0 -Total 1 -CurrentAction (& $appsGetUxLocalizedStringCommand -Key 'GuiAppsCacheRefreshFailed' -Fallback 'Failed to scan installed applications.') -PassThruText | Out-Null
			& $appsLogErrorCommand (& $appsGetUxLocalizedStringCommand -Key 'Progress_Error' -Fallback 'Error: {0}' -FormatArgs @([string]$syncHash.Error))
			& $appsScriptScope { $Script:AppsCacheRefreshInProgress = $false }
			& $appsSetActionControlsEnabledCommand -Enabled $true
			try { $ps.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.DisposePowerShell' }
			try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.DisposeRunspace' }
			return
		}

		if ($tickProgressBar -or $tickProgressText)
		{
			$progressText = & $appsSetSharedProgressBarStateCommand -ProgressBar $tickProgressBar -ProgressText $tickProgressText -Completed $syncHash.Completed -Total $syncHash.Total -CurrentAction $syncHash.CurrentAction -PassThruText
		}

		if (-not $asyncResult.IsCompleted)
		{
			return
		}

		$timer.Stop()
		try
		{
			$cacheResult = @($ps.EndInvoke($asyncResult))
			$cachePayload = if ($cacheResult.Count -gt 0) { $cacheResult[0] } else { $null }
			$resolvedCache = if ($cachePayload -is [psobject])
			{
				& $appsGetApplicationCacheSnapshotCommand -CacheState $cachePayload
			}
			elseif ($cachePayload -is [hashtable])
			{
				[pscustomobject]@{
					WinGet = $cachePayload
					Chocolatey = @{}
					WinGetUpdates = @{}
					ChocolateyUpdates = @{}
				}
			}
			else
			{
				[pscustomobject]@{
					WinGet = @{}
					Chocolatey = @{}
					WinGetUpdates = @{}
					ChocolateyUpdates = @{}
				}
			}
			# Write results back into the host module's script scope so the
			# rest of the GUI (which does live in that scope) sees them.
			& $appsScriptScope {
				param ($cache)
				$Script:InstalledAppsCache = $cache
				$Script:AppsViewLoaded = $true
				$Script:AppsViewDirty = $false
			} $resolvedCache
			& $appsSetSharedProgressBarStateCommand -ProgressBar $tickProgressBar -ProgressText $tickProgressText -Completed $syncHash.Total -Total $syncHash.Total -CurrentAction $syncHash.CurrentAction | Out-Null
			if ($appsLogInfoCommand)
			{
				& $appsLogInfoCommand ([string]$syncHash.PhaseComplete)
			}
			if ($syncHash.Warnings -and $syncHash.Warnings.Count -gt 0)
			{
				foreach ($warning in $syncHash.Warnings)
				{
					if (Get-Command -Name 'LogWarning' -ErrorAction SilentlyContinue)
					{
						try { LogWarning $warning } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.LogWarning' }
					}
				}
			}
			& $appsBuildAppsViewCardsCommand
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh:catch728' -Severity Debug }

			& $appsScriptScope {
				$Script:InstalledAppsCache = [pscustomobject]@{
					WinGet = @{}
					Chocolatey = @{}
					WinGetUpdates = @{}
					ChocolateyUpdates = @{}
				}
				$Script:AppsViewLoaded = $false
				$Script:AppsViewDirty = $true
			}
			$progressText = & $appsSetSharedProgressBarStateCommand -ProgressBar $tickProgressBar -ProgressText $tickProgressText -Completed 0 -Total 1 -CurrentAction (& $appsGetUxLocalizedStringCommand -Key 'GuiAppsCacheRefreshFailed' -Fallback 'Failed to scan installed applications.') -PassThruText
			$cacheRefreshErrorPrefix = & $appsGetUxLocalizedStringCommand -Key 'GuiAppsCacheRefreshFailed' -Fallback 'Failed to scan installed applications.'
			& $appsLogErrorCommand (& $appsFormatBaselineErrorForLogCommand -ErrorObject $_ -Prefix $cacheRefreshErrorPrefix)
		}
		finally
		{
			& $appsScriptScope { $Script:AppsCacheRefreshInProgress = $false }
			& $appsSetActionControlsEnabledCommand -Enabled $true
			try { $ps.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.DisposePowerShell' }
			try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.DisposeRunspace' }
		}
	}.GetNewClosure())
	$timer.Start()
	}
	catch
	{
		$Script:AppsCacheRefreshInProgress = $false
		try { Set-AppsActionControlsEnabled -Enabled $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.SetupFailureEnableControls' }
		try { if ($ps) { $ps.Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.SetupFailureDisposePowerShell' }
		try { if ($runspace) { $runspace.Dispose() } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'AppsModule.Start-AppsCacheRefresh.SetupFailureDisposeRunspace' }
		throw
	}
}

<#
    .SYNOPSIS
#>

function Start-AppsModuleActionAsync
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall', 'Update', 'UpdateAll')]
		[string]$Action,

		[string]$WinGetId,

		[string]$ChocoId,

		[string]$DisplayName,

		[object]$Application,

		[string]$PreferredSource = $null
	)

	$resolvedWinGetId = $WinGetId
	$resolvedChocoId = $ChocoId
	$resolvedDisplayName = $DisplayName
	if ($Application)
	{
		if ([string]::IsNullOrWhiteSpace([string]$resolvedDisplayName) -and $Application.PSObject.Properties['Name'])
		{
			$resolvedDisplayName = [string]$Application.Name
		}
		if ([string]::IsNullOrWhiteSpace([string]$resolvedWinGetId) -and $Application.PSObject.Properties['WinGetId'])
		{
			$resolvedWinGetId = [string]$Application.WinGetId
		}
		if ([string]::IsNullOrWhiteSpace([string]$resolvedChocoId) -and $Application.PSObject.Properties['ChocoId'])
		{
			$resolvedChocoId = [string]$Application.ChocoId
		}
	}
	Initialize-AppPackageSourcePreferenceState
	$resolvedPreferredSource = ConvertTo-AppPackageSourcePreference -Source $(if ([string]::IsNullOrWhiteSpace([string]$PreferredSource)) { $Script:AppsPackageSourcePreference } else { $PreferredSource })

	$appModulePath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Regions\Applications.psm1'
	$bgUICulture = if ([string]::IsNullOrWhiteSpace([string]$Script:SelectedLanguage)) { 'en' } else { [string]$Script:SelectedLanguage }
	Start-GuiAppExecutionRun `
		-Action $Action `
		-LoaderPath $appModulePath `
		-LocalizationDirectory $Script:GuiLocalizationDirectoryPath `
		-UICulture $bgUICulture `
		-LogFilePath $Global:LogFilePath `
		-WinGetId $resolvedWinGetId `
		-ChocoId $resolvedChocoId `
		-DisplayName $resolvedDisplayName `
		-Application $Application `
		-PreferredSource $resolvedPreferredSource `
		-PackageManagerAvailabilityState $Script:AppsPackageManagerAvailabilityState
}

<#
    .SYNOPSIS
#>

function Start-AppsModuleBatchActionAsync
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Install', 'Uninstall', 'Update')]
		[string]$Action,

		[object[]]$SelectedApps = @(),

		[string]$PreferredSource = $null
	)

	Initialize-AppsSelectionState
	if (-not $SelectedApps -or $SelectedApps.Count -eq 0)
	{
		$SelectedApps = @(Get-SelectedAppsCatalogItems)
	}
	else
	{
		$SelectedApps = @($SelectedApps | Where-Object { $_ })
	}

	Initialize-AppPackageSourcePreferenceState
	$resolvedPreferredSource = ConvertTo-AppPackageSourcePreference -Source $(if ([string]::IsNullOrWhiteSpace([string]$PreferredSource)) { $Script:AppsPackageSourcePreference } else { $PreferredSource })

	if ($SelectedApps.Count -eq 0)
	{
		return
	}

	$appModulePath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Regions\Applications.psm1'
	$bgUICulture = if ([string]::IsNullOrWhiteSpace([string]$Script:SelectedLanguage)) { 'en' } else { [string]$Script:SelectedLanguage }
	Start-GuiAppExecutionRun `
		-Action $Action `
		-LoaderPath $appModulePath `
		-LocalizationDirectory $Script:GuiLocalizationDirectoryPath `
		-UICulture $bgUICulture `
		-LogFilePath $Global:LogFilePath `
		-SelectedApps @($SelectedApps) `
		-PreferredSource $resolvedPreferredSource `
		-PackageManagerAvailabilityState $Script:AppsPackageManagerAvailabilityState
}
