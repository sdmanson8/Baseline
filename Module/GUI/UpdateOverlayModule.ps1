# Baseline update overlay helpers for progress, update checks, and import flows.


<#
    .SYNOPSIS
#>

function Initialize-BaselineUpdateOverlay
{
	[CmdletBinding()]
	param ()

	if (-not $Script:CustomPBarContainer -or -not $Script:UpdateDialogOverlay) { return }
	$writeOverlayDebug = if ($Script:WriteBaselineUpdateOverlayDebugScript -is [scriptblock]) { $Script:WriteBaselineUpdateOverlayDebugScript } else { { param([string]$Message) } }
	$updateDialogOverlay = $Script:UpdateDialogOverlay
	& $writeOverlayDebug 'Initialize-BaselineUpdateOverlay started.'

	$progressBar = New-Object System.Windows.Controls.ProgressBar
	$progressBar.Minimum = 0
	$progressBar.Maximum = 100
	$progressBar.Value = 0
	$progressBar.Height = 10
	$progressBar.BorderThickness = [System.Windows.Thickness]::new(0)
	$progressBar.IsHitTestVisible = $false
	$progressBar.Focusable = $false
	$Script:CustomProgressBar = $progressBar
	$Script:CustomProgressHost = $progressBar
	$Script:CustomPBarContainer.Child = $progressBar
	$customProgressBar = $progressBar
	if (-not $Script:UpdateOverlayState)
	{
		$Script:UpdateOverlayState = [hashtable]::Synchronized(@{
			PrimaryAction = $null
			SecondaryAction = $null
			PrimaryCloses = $false
			SecondaryCloses = $true
		})
	}

	$overlayState = $Script:UpdateOverlayState
	$closeOverlayDirect = {
		param($eventArgs, [string]$Source = 'Direct')

		& $writeOverlayDebug ("Close requested via {0}; primaryCloses={1}; secondaryCloses={2}; overlayVisible={3}" -f $Source, [bool]$overlayState.PrimaryCloses, [bool]$overlayState.SecondaryCloses, $(if ($updateDialogOverlay) { [string]$updateDialogOverlay.Visibility } else { '<missing>' }))

		if ($eventArgs -and $eventArgs.PSObject.Properties['Handled'])
		{
			try { $eventArgs.Handled = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DirectClose.MarkHandled' }
		}
		$overlayState.PrimaryCloses = $false
		$overlayState.PrimaryAction = $null
		$overlayState.SecondaryCloses = $true
		$Script:UpdateOverlayPrimaryClickAction = $null
		$Script:UpdateCheckPrimaryClickEvent = $null
		$Script:UpdateCheckSecondaryClickEvent = $null
		if ($customProgressBar)
		{
			$customProgressBar.IsIndeterminate = $false
			$customProgressBar.Value = 0
		}
		if ($updateDialogOverlay)
		{
			$updateDialogOverlay.Visibility = [System.Windows.Visibility]::Collapsed
			$updateDialogOverlay.IsHitTestVisible = $false
		}
		& $writeOverlayDebug 'Overlay collapsed by direct close.'
	}.GetNewClosure()

	if ($Script:BtnDownloadYes -and -not $Script:UpdateOverlayPrimaryClickEvent)
	{
		$Script:UpdateOverlayPrimaryClickEvent = {
			param($sender, $eventArgs)

			if ([bool]$overlayState.PrimaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'PrimaryClick'
				return
			}

			& $writeOverlayDebug 'Primary click routed to primary action.'
			$action = $overlayState.PrimaryAction
			if ($action) { & $action $sender $eventArgs }
		}.GetNewClosure()
		$Script:BtnDownloadYes.Add_Click($Script:UpdateOverlayPrimaryClickEvent)
	}
	if ($Script:BtnDownloadYes -and -not $Script:UpdateOverlayPrimaryPreviewMouseDownEvent)
	{
		$Script:UpdateOverlayPrimaryPreviewMouseDownEvent = {
			param($sender, $eventArgs)

			& $writeOverlayDebug ("Primary preview mouse down; primaryCloses={0}" -f [bool]$overlayState.PrimaryCloses)
			if ([bool]$overlayState.PrimaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'PrimaryPreviewMouseDown'
			}
		}.GetNewClosure()
		$Script:BtnDownloadYes.Add_PreviewMouseLeftButtonDown($Script:UpdateOverlayPrimaryPreviewMouseDownEvent)
	}
	if ($Script:BtnDownloadYes -and -not $Script:UpdateOverlayPrimaryPreviewMouseUpEvent)
	{
		$Script:UpdateOverlayPrimaryPreviewMouseUpEvent = {
			param($sender, $eventArgs)

			& $writeOverlayDebug ("Primary preview mouse up; primaryCloses={0}" -f [bool]$overlayState.PrimaryCloses)
			if ([bool]$overlayState.PrimaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'PrimaryPreviewMouseUp'
			}
		}.GetNewClosure()
		$Script:BtnDownloadYes.Add_PreviewMouseLeftButtonUp($Script:UpdateOverlayPrimaryPreviewMouseUpEvent)
	}
	if ($updateDialogOverlay -and -not $Script:UpdateOverlayPreviewMouseDownEvent)
	{
		$Script:UpdateOverlayPreviewMouseDownEvent = {
			param($sender, $eventArgs)

			& $writeOverlayDebug ("Overlay preview mouse down; primaryCloses={0}" -f [bool]$overlayState.PrimaryCloses)
			if ([bool]$overlayState.PrimaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'OverlayPreviewMouseDown'
			}
		}.GetNewClosure()
		$updateDialogOverlay.Add_PreviewMouseLeftButtonDown($Script:UpdateOverlayPreviewMouseDownEvent)
	}
	if ($updateDialogOverlay -and -not $Script:UpdateOverlayPreviewMouseUpEvent)
	{
		$Script:UpdateOverlayPreviewMouseUpEvent = {
			param($sender, $eventArgs)

			& $writeOverlayDebug ("Overlay preview mouse up; primaryCloses={0}" -f [bool]$overlayState.PrimaryCloses)
			if ([bool]$overlayState.PrimaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'OverlayPreviewMouseUp'
			}
		}.GetNewClosure()
		$updateDialogOverlay.Add_PreviewMouseLeftButtonUp($Script:UpdateOverlayPreviewMouseUpEvent)
	}
	if ($Script:BtnDownloadNo -and -not $Script:UpdateOverlaySecondaryClickEvent)
	{
		$Script:UpdateOverlaySecondaryClickEvent = {
			param($sender, $eventArgs)

			if ([bool]$overlayState.SecondaryCloses)
			{
				& $closeOverlayDirect $eventArgs 'SecondaryClick'
				return
			}

			& $writeOverlayDebug 'Secondary click routed to secondary action.'
			$action = $overlayState.SecondaryAction
			if ($action) { & $action $sender $eventArgs }
		}.GetNewClosure()
		$Script:BtnDownloadNo.Add_Click($Script:UpdateOverlaySecondaryClickEvent)
	}
	& $writeOverlayDebug 'Initialize-BaselineUpdateOverlay completed.'
}

function Write-BaselineUpdateOverlayDebug
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Message
	)

	$envDebug = [System.Environment]::GetEnvironmentVariable('BASELINE_UPDATE_OVERLAY_DEBUG')
	$envEnabled = (-not [string]::IsNullOrWhiteSpace($envDebug)) -and $envDebug -notin @('0', 'false', 'False', 'off', 'Off')
	$debugEnabled = $envEnabled
	if (-not $debugEnabled -and (Get-Command -Name 'Get-BaselineDebugLogging' -CommandType Function -ErrorAction SilentlyContinue))
	{
		try { $debugEnabled = [bool](Get-BaselineDebugLogging) } catch {
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DebugTrace:catch171' -Severity Debug }
		 $debugEnabled = $false }
	}
	if (-not $debugEnabled) { return }

	$line = '[UpdateOverlay] {0}' -f $Message
	try { LogDebug $line } catch { Write-Warning "Failed to write update overlay debug entry: $($_.Exception.Message)" }
	try
	{
		$base = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { [System.IO.Path]::GetTempPath() } else { $env:LOCALAPPDATA }
		$dir = Join-Path $base 'Temp\Baseline'
		if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
		$path = Join-Path $dir 'update-overlay-debug.log'
		[System.IO.File]::AppendAllText($path, ('{0} {1}{2}' -f (Get-Date).ToString('o'), $line, [Environment]::NewLine), [System.Text.Encoding]::UTF8)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DebugTrace:catch185' -Severity Debug }

		$null = $_
	}
}
$Script:WriteBaselineUpdateOverlayDebugScript = ${function:Write-BaselineUpdateOverlayDebug}

<#
    .SYNOPSIS
#>

function Show-BaselineUpdateOverlay
{
	[CmdletBinding()]
	param (
		[string]$Title = (Get-UxLocalizedString -Key 'GuiUpdateDialogTitle' -Fallback 'Update Baseline'),
		[string]$Description = (Get-UxLocalizedString -Key 'GuiUpdateDialogDescription' -Fallback 'A new version of Baseline is available from GitHub. Do you want to download and extract it now?'),
		[string]$StatusText = (Get-UxLocalizedString -Key 'GuiUpdateDialogReady' -Fallback 'Ready to download.'),
		[string]$ProgressPct = '0%',
		[string]$PrimaryButtonText = (Get-UxLocalizedString -Key 'GuiUpdateDialogDownload' -Fallback 'Download Update'),
		[string]$SecondaryButtonText = (Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Cancel'),
		[bool]$ShowButtons = $true,
		[bool]$ShowProgressPct = $true,
		[bool]$PrimaryButtonCloses = $false,
		[bool]$SecondaryButtonCloses = $true,
		[switch]$Indeterminate
	)

	$writeOverlayDebug = if ($Script:WriteBaselineUpdateOverlayDebugScript -is [scriptblock]) { $Script:WriteBaselineUpdateOverlayDebugScript } else { { param([string]$Message) } }
	if ($Script:UpdateDialogOverlay)
	{
		$Script:UpdateDialogOverlay.Visibility = [System.Windows.Visibility]::Visible
		$Script:UpdateDialogOverlay.IsHitTestVisible = $true
	}
	& $writeOverlayDebug ("Show overlay: title='{0}'; primary='{1}'; showButtons={2}; primaryCloses={3}; secondaryCloses={4}" -f $Title, $PrimaryButtonText, [bool]$ShowButtons, [bool]$PrimaryButtonCloses, [bool]$SecondaryButtonCloses)
	if ($Script:CustomProgressBar)
	{
		$Script:CustomProgressBar.IsIndeterminate = [bool]$Indeterminate
		$Script:CustomProgressBar.Value = 0
	}
	if ($Script:UpdateOverlayState)
	{
		$Script:UpdateOverlayState.PrimaryCloses = [bool]$PrimaryButtonCloses
		$Script:UpdateOverlayState.SecondaryCloses = [bool]$SecondaryButtonCloses
		if ($PrimaryButtonCloses)
		{
			$primaryCloseAction = New-BaselineUpdateOverlayCloseAction
			$Script:UpdateOverlayState.PrimaryAction = $primaryCloseAction
			$Script:UpdateOverlayPrimaryClickAction = $primaryCloseAction
			$Script:UpdateCheckPrimaryClickEvent = $primaryCloseAction
		}
	}
	if ($Script:TxtOverlayTitle) { $Script:TxtOverlayTitle.Text = [string]$Title }
	if ($Script:TxtUpdateDescription) { $Script:TxtUpdateDescription.Text = [string]$Description }
	if ($Script:TxtDownloadProgressLabel) { $Script:TxtDownloadProgressLabel.Text = [string]$StatusText }
	if ($Script:TxtDownloadProgressPct)
	{
		$Script:TxtDownloadProgressPct.Text = [string]$ProgressPct
		$Script:TxtDownloadProgressPct.Visibility = if ($ShowProgressPct) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
	}
	if ($Script:BtnDownloadYes)
	{
		$Script:BtnDownloadYes.Content = [string]$PrimaryButtonText
		$Script:BtnDownloadYes.Visibility = if ($ShowButtons) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		$Script:BtnDownloadYes.IsEnabled = [bool]$ShowButtons
		$Script:BtnDownloadYes.IsDefault = $false
		$Script:BtnDownloadYes.IsCancel = $false
		if ($PrimaryButtonCloses)
		{
			try { [void]$Script:BtnDownloadYes.Focus() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.ShowOverlay.FocusPrimaryClose' }
		}
	}
	if ($Script:BtnDownloadNo)
	{
		$Script:BtnDownloadNo.Content = [string]$SecondaryButtonText
		$Script:BtnDownloadNo.Visibility = if ($ShowButtons) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		$Script:BtnDownloadNo.IsEnabled = [bool]$ShowButtons
	}
}

function New-BaselineUpdateOverlayCloseAction
{
	[CmdletBinding()]
	[OutputType([scriptblock])]
	param ()

	$writeOverlayDebug = if ($Script:WriteBaselineUpdateOverlayDebugScript -is [scriptblock]) { $Script:WriteBaselineUpdateOverlayDebugScript } else { { param([string]$Message) } }
	$updateDialogOverlay = $Script:UpdateDialogOverlay
	$customProgressBar = $Script:CustomProgressBar
	$overlayState = $Script:UpdateOverlayState
	$downloadStartEvent = $Script:DownloadStartEvent
	return {
		param($sender, $eventArgs)

		if ($eventArgs -and $eventArgs.PSObject.Properties['Handled'])
		{
			try { $eventArgs.Handled = $true } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.CloseAction.MarkHandled' }
		}
		& $writeOverlayDebug ("Close action invoked; overlayVisible={0}" -f $(if ($updateDialogOverlay) { [string]$updateDialogOverlay.Visibility } else { '<missing>' }))

		$Script:UpdateCheckPrimaryClickEvent = $null
		$Script:UpdateCheckSecondaryClickEvent = $null
		$Script:UpdateOverlayPrimaryClickAction = $downloadStartEvent
		if ($overlayState)
		{
			$overlayState.PrimaryCloses = $false
			$overlayState.PrimaryAction = $downloadStartEvent
		}
		if ($customProgressBar)
		{
			$customProgressBar.IsIndeterminate = $false
			$customProgressBar.Value = 0
		}
		if ($updateDialogOverlay)
		{
			$updateDialogOverlay.Visibility = [System.Windows.Visibility]::Collapsed
			$updateDialogOverlay.IsHitTestVisible = $false
		}
		& $writeOverlayDebug 'Overlay collapsed by close action.'
	}.GetNewClosure()
}

<#
    .SYNOPSIS
#>

function Show-BaselineUpdateCheckDialog
{
	[CmdletBinding()]
	param ()

	$writeOverlayDebug = if ($Script:WriteBaselineUpdateOverlayDebugScript -is [scriptblock]) { $Script:WriteBaselineUpdateOverlayDebugScript } else { { param([string]$Message) } }
	& $writeOverlayDebug 'Show-BaselineUpdateCheckDialog started.'
	$title = (Get-UxLocalizedString -Key 'GuiUpdateDialogTitle' -Fallback 'Update Baseline')
	$checkingDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckDescription' -Fallback 'Checking GitHub releases for a newer Baseline version.')
	$checkingStatus = (Get-UxLocalizedString -Key 'GuiUpdateCheckStatus' -Fallback 'Checking for updates...')
	$downloadUpdateLabel = (Get-UxLocalizedString -Key 'GuiUpdateDialogDownload' -Fallback 'Download Update')
	$closeLabel = (Get-UxLocalizedString -Key 'GuiCloseButton' -Fallback 'Close')
	$upToDateDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckUpToDateDescription' -Fallback 'Baseline is already up to date.')
	$upToDateStatus = (Get-UxLocalizedString -Key 'GuiUpdateCheckUpToDateStatus' -Fallback 'Already up to date.')
	$availableDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckAvailableDescription' -Fallback 'A newer version of Baseline is available on GitHub Releases.')
	$availableStatus = (Get-UxLocalizedString -Key 'GuiUpdateCheckAvailableStatus' -Fallback 'Update available.')
	$errorDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckFailedDescription' -Fallback 'Unable to check for updates right now.')
	$offlineDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckOfflineDescription' -Fallback 'Unable to check for updates because the network is offline.')
	$offlineStatus = (Get-UxLocalizedString -Key 'GuiUpdateCheckOfflineStatus' -Fallback 'Skipped (offline).')
	$currentVersion = '0.0.0'
	$Script:PendingUpdateDownloadUri = $null
	$Script:PendingUpdateArchivePath = $null
	$Script:PendingUpdateReleaseTag = $null
	$hideBaselineUpdateOverlayAction = New-BaselineUpdateOverlayCloseAction
	$startBaselineDownloadAction = ${function:Start-BaselineDownload}
	$showSingleCloseButton = {
		if ($Script:BtnDownloadNo)
		{
			$Script:BtnDownloadNo.Visibility = [System.Windows.Visibility]::Collapsed
			$Script:BtnDownloadNo.IsEnabled = $false
		}
	}
	$setUpdateCheckPrimaryClickEvent = {
		param ([scriptblock]$Handler)

		if (-not $Script:BtnDownloadYes) { return }

		$Script:UpdateCheckPrimaryClickEvent = $Handler
		$Script:UpdateOverlayPrimaryClickAction = $Script:UpdateCheckPrimaryClickEvent
		if ($Script:UpdateOverlayState)
		{
			$Script:UpdateOverlayState.PrimaryCloses = $false
			$Script:UpdateOverlayState.PrimaryAction = $Script:UpdateCheckPrimaryClickEvent
		}
	}
	$setUpdateCheckCloseClickEvent = {
		param ([scriptblock]$Handler)

		if (-not $Script:BtnDownloadNo) { return }

		$Script:UpdateCheckSecondaryClickEvent = $Handler
		$Script:UpdateOverlaySecondaryClickAction = $Script:UpdateCheckSecondaryClickEvent
		if ($Script:UpdateOverlayState)
		{
			$Script:UpdateOverlayState.SecondaryCloses = $true
			$Script:UpdateOverlayState.SecondaryAction = $Script:UpdateCheckSecondaryClickEvent
		}
	}
	$wireCloseButtons = {
		& $writeOverlayDebug 'Wiring single close button actions.'
		$Script:UpdateCheckPrimaryClickEvent = $hideBaselineUpdateOverlayAction.GetNewClosure()
		$Script:UpdateOverlayPrimaryClickAction = $Script:UpdateCheckPrimaryClickEvent
		if ($Script:UpdateOverlayState)
		{
			$Script:UpdateOverlayState.PrimaryCloses = $true
			$Script:UpdateOverlayState.PrimaryAction = $Script:UpdateCheckPrimaryClickEvent
		}
		& $setUpdateCheckCloseClickEvent $hideBaselineUpdateOverlayAction
	}

	try
	{
		$currentVersion = [string](Get-BaselineDisplayVersion)
	}
	catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.LoadCurrentVersion' }

	Show-BaselineUpdateOverlay -Title $title -Description $checkingDescription -StatusText $checkingStatus -ShowButtons:$false -ShowProgressPct:$false -Indeterminate

	try
	{
		$includePrerelease = $false
		$updateBranch = if (Get-Command -Name 'Get-BaselineDefaultUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue) { Get-BaselineDefaultUpdateBranch } else { 'Stable' }
		if (Get-Command -Name 'Get-BaselineUpdateSettings' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$updateSettings = Get-BaselineUpdateSettings
			$includePrerelease = if ($updateSettings -and $updateSettings.PSObject.Properties['IncludePrereleaseBuilds']) { [bool]$updateSettings.IncludePrereleaseBuilds } else { $false }
			if ($updateSettings -and $updateSettings.PSObject.Properties['UpdateBranch'] -and -not [string]::IsNullOrWhiteSpace([string]$updateSettings.UpdateBranch))
			{
				$updateBranch = [string]$updateSettings.UpdateBranch
			}
		}
		if (Get-Command -Name 'ConvertTo-BaselineUpdateBranch' -CommandType Function -ErrorAction SilentlyContinue)
		{
			$updateBranch = ConvertTo-BaselineUpdateBranch -Branch $updateBranch
		}
		$checkResult = Invoke-BaselineUpdateCheck -CurrentVersion $currentVersion -UpdateBranch $updateBranch -IncludePrerelease:$includePrerelease
		& $writeOverlayDebug ("Update check completed: status='{0}'; updateAvailable={1}; latest='{2}'" -f [string]$checkResult.Status, [bool]$checkResult.IsUpdateAvailable, [string]$checkResult.LatestVersion)
		$release = $checkResult.Release
		if ([string]$checkResult.Status -eq 'Skipped (offline)')
		{
			Show-BaselineUpdateOverlay -Title $title -Description $offlineDescription -StatusText $offlineStatus -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
			& $showSingleCloseButton
			& $wireCloseButtons
			return
		}
		if ([string]$checkResult.Status -eq 'Failed')
		{
			$errorStatus = if ([string]::IsNullOrWhiteSpace([string]$checkResult.Message)) { $errorDescription } else { [string]$checkResult.Message }
			Show-BaselineUpdateOverlay -Title $title -Description $errorDescription -StatusText $errorStatus -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
			& $showSingleCloseButton
			& $wireCloseButtons
			return
		}
		if (-not $release -or -not [bool]$checkResult.IsUpdateAvailable)
		{
			$latestText = if ([string]::IsNullOrWhiteSpace([string]$checkResult.LatestVersion)) { [string]$currentVersion } else { [string]$checkResult.LatestVersion }
			Show-BaselineUpdateOverlay -Title $title -Description $upToDateDescription -StatusText ($upToDateStatus -f $latestText) -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
			& $showSingleCloseButton
			& $wireCloseButtons
			return
		}

		$latestTag = [string]$release.tag_name
		$releaseAssetPattern = if (Get-Command -Name 'Get-BaselineUpdateAssetPattern' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Get-BaselineUpdateAssetPattern -Branch $updateBranch
		}
		else
		{
			if ([string]::Equals($updateBranch, 'Beta', [System.StringComparison]::OrdinalIgnoreCase))
			{
				'Baseline-*-beta.zip'
			}
			else
			{
				'Baseline-*-stable.zip'
			}
		}

		$releaseAsset = $release.assets | Where-Object { $_.name -like $releaseAssetPattern } | Select-Object -First 1
		if ($releaseAsset)
		{
			$releaseAssetName = [System.IO.Path]::GetFileName([string]$releaseAsset.name)
			if ([string]::IsNullOrWhiteSpace($releaseAssetName))
			{
				LogWarning ('Update {0} found but matching release asset has no file name; skipping.' -f $latestTag)
				Show-BaselineUpdateOverlay -Title $title -Description $errorDescription -StatusText ($availableStatus -f $latestTag) -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
				& $showSingleCloseButton
				& $wireCloseButtons
				return
			}
			$releaseAssetDownloadUri = [string]$releaseAsset.browser_download_url
			if ([string]::IsNullOrWhiteSpace($releaseAssetDownloadUri))
			{
				LogWarning ('Update {0} found but matching release asset {1} has no download URL; skipping.' -f $latestTag, $releaseAssetName)
				Show-BaselineUpdateOverlay -Title $title -Description $errorDescription -StatusText ($availableStatus -f $latestTag) -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
				& $showSingleCloseButton
				& $wireCloseButtons
				return
			}
			$Script:PendingUpdateDownloadUri = $releaseAssetDownloadUri
			$Script:PendingUpdateArchivePath = Join-Path ([System.IO.Path]::GetTempPath()) $releaseAssetName
			$Script:PendingUpdateReleaseTag = $latestTag
			$resolvedDownloadUri = [string]$Script:PendingUpdateDownloadUri
			$resolvedArchivePath = [string]$Script:PendingUpdateArchivePath
			$resolvedDownloadAction = $startBaselineDownloadAction
			$availableDescription = (Get-UxLocalizedString -Key 'GuiUpdateCheckAvailableDescription' -Fallback 'A newer version of Baseline is available on GitHub Releases.') -f $latestTag
			$availableStatus = (Get-UxLocalizedString -Key 'GuiUpdateCheckAvailableStatus' -Fallback 'Update available: {0}.') -f $latestTag
			Show-BaselineUpdateOverlay -Title $title -Description $availableDescription -StatusText $availableStatus -PrimaryButtonText $downloadUpdateLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$false
			$downloadReleaseAction = {
				try
				{
					if ([string]::IsNullOrWhiteSpace($resolvedDownloadUri) -or [string]::IsNullOrWhiteSpace($resolvedArchivePath))
					{
						LogWarning 'Resolved update download action is missing the release asset URL or archive path.'
						return
					}
					if ($resolvedDownloadAction)
					{
						& $resolvedDownloadAction -Uri $resolvedDownloadUri -DestinationPath $resolvedArchivePath
					}
					else
					{
						LogWarning 'Start-BaselineDownload not available; update download action was skipped.'
					}
				}
				catch
				{
					Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.StartResolvedReleaseDownload'
				}
			}.GetNewClosure()
			& $setUpdateCheckPrimaryClickEvent $downloadReleaseAction
			& $setUpdateCheckCloseClickEvent $hideBaselineUpdateOverlayAction
			return
		}

		Show-BaselineUpdateOverlay -Title $title -Description $errorDescription -StatusText ($availableStatus -f $latestTag) -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
		& $showSingleCloseButton
		& $wireCloseButtons
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.Show-BaselineUpdateCheckDialog:catch476' -Severity Debug }

		& $writeOverlayDebug ("Update check failed: {0}" -f $_.Exception.Message)
		Show-BaselineUpdateOverlay -Title $title -Description $errorDescription -StatusText $_.Exception.Message -PrimaryButtonText $closeLabel -SecondaryButtonText $closeLabel -ShowButtons:$true -ShowProgressPct:$false -PrimaryButtonCloses:$true
		& $showSingleCloseButton
		& $wireCloseButtons
	}
}

<#
    .SYNOPSIS
#>

function Show-BaselineImportOverlay
{
	[CmdletBinding()]
	param (
		[string]$Title = (Get-UxLocalizedString -Key 'GuiImportSettings' -Fallback 'Import Settings'),
		[string]$Description = (Get-UxLocalizedString -Key 'GuiImportSettingsOverlayDescription' -Fallback 'Loading the selected settings profile.'),
		[string]$StatusText = (Get-UxLocalizedString -Key 'GuiImportSettingsPreparing' -Fallback 'Preparing import...')
	)

	Show-BaselineUpdateOverlay -Title $Title -Description $Description -StatusText $StatusText -ShowButtons:$false -ShowProgressPct:$false -Indeterminate
}

function Hide-BaselineUpdateOverlay
{
	[CmdletBinding()]
	param ()

	$closeAction = New-BaselineUpdateOverlayCloseAction
	& $closeAction
}

<#
    .SYNOPSIS
#>

function Start-BaselineDownload
{
	param (
		[string]$Uri,
		[string]$DestinationPath
	)

	LogInfo (Get-UxBilingualLocalizedString -Key 'GuiLogStartBackgroundDownload' -Fallback 'Starting background download from {0}' -FormatArgs @($Uri))

	if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.IsEnabled = $false }
	if ($Script:BtnDownloadNo) { $Script:BtnDownloadNo.IsEnabled = $false }
	if ($Script:CustomProgressBar)
	{
		$Script:CustomProgressBar.IsIndeterminate = $false
		$Script:CustomProgressBar.Value = 0
	}
	if ($Script:TxtDownloadProgressPct) { $Script:TxtDownloadProgressPct.Text = "0%" }
	if ($Script:TxtDownloadProgressLabel) { $Script:TxtDownloadProgressLabel.Text = (Get-UxLocalizedString -Key 'GuiStatusDownloadConnecting' -Fallback 'Connecting to GitHub...') }

	$downloadProgressTemplate = (Get-UxLocalizedString -Key 'GuiStatusDownloadProgressFormat' -Fallback 'Downloading... {0} MB / {1} MB')
	$downloadProgressNoTotalTemplate = (Get-UxLocalizedString -Key 'GuiStatusDownloadProgressNoTotalFormat' -Fallback 'Downloading... {0} MB')
	$downloadCompleteText = (Get-UxLocalizedString -Key 'GuiStatusDownloadComplete' -Fallback 'Download complete.')
	$userAgent = 'Baseline'
	try { $userAgent = "Baseline/$(Get-BaselineDisplayVersion)" } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.StartBaselineDownload.UserAgent' }
	if (Get-Command -Name 'Set-DownloadSecurityProtocol' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { Set-DownloadSecurityProtocol } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.StartBaselineDownload.SecurityProtocol' }
	}

	$syncHash = [hashtable]::Synchronized(@{
		ProgressPct = 0
		Status      = (Get-UxLocalizedString -Key 'GuiStatusDownloadInitializing' -Fallback 'Initializing...')
		IsIndeterminate = $false
		IsComplete  = $false
		Error       = $null
	})

	$runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
	$runspace.Open()
	$ps = [System.Management.Automation.PowerShell]::Create()
	$ps.Runspace = $runspace

	[void]$ps.AddScript({
		param($DownloadUri, $Path, $Sync, $ProgressTemplate, $ProgressNoTotalTemplate, $CompleteText, $UserAgent)
		$response = $null
		$responseStream = $null
		$targetStream = $null
		try
		{
			$webRequest = [System.Net.WebRequest]::Create($DownloadUri)
			if ($webRequest -is [System.Net.HttpWebRequest])
			{
				$webRequest.UserAgent = $UserAgent
				$webRequest.Timeout = 300000
			}
			$response = $webRequest.GetResponse()
			$totalBytes = $response.ContentLength
			$Sync.IsIndeterminate = ($totalBytes -le 0)
			if ($totalBytes -gt 0)
			{
				$Sync.Status = $ProgressTemplate -f 0, ([math]::Round($totalBytes / 1MB, 2))
			}
			else
			{
				$Sync.Status = $ProgressNoTotalTemplate -f 0
			}

			$responseStream = $response.GetResponseStream()
			$targetStream = [System.IO.File]::Create($Path)

			$buffer = New-Object byte[] 65536
			$totalRead = 0

			do
			{
				$read = $responseStream.Read($buffer, 0, $buffer.Length)
				if ($read -gt 0)
				{
					$targetStream.Write($buffer, 0, $read)
					$totalRead += $read
					if ($totalBytes -gt 0)
					{
						$Sync.ProgressPct = [math]::Round(($totalRead / $totalBytes) * 100)
						$mbRead = [math]::Round($totalRead / 1MB, 2)
						$mbTotal = [math]::Round($totalBytes / 1MB, 2)
						$Sync.Status = $ProgressTemplate -f $mbRead, $mbTotal
					}
					else
					{
						$mbRead = [math]::Round($totalRead / 1MB, 2)
						$Sync.Status = $ProgressNoTotalTemplate -f $mbRead
					}
				}
			}
			while ($read -gt 0)

			$Sync.IsComplete = $true
			$Sync.Status = $CompleteText
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.Start-BaselineDownload:catch583' -Severity Debug }

			$Sync.Error = $_.Exception.Message
			$Sync.IsComplete = $true
		}
		finally
		{
			if ($targetStream) { $targetStream.Dispose() }
			if ($responseStream) { $responseStream.Dispose() }
			if ($response) { $response.Dispose() }
		}
	}).AddArgument($Uri).AddArgument($DestinationPath).AddArgument($syncHash).AddArgument($downloadProgressTemplate).AddArgument($downloadProgressNoTotalTemplate).AddArgument($downloadCompleteText).AddArgument($userAgent)

	$asyncResult = $ps.BeginInvoke()

	$timer = [System.Windows.Threading.DispatcherTimer]::new()
	$timer.Interval = [TimeSpan]::FromMilliseconds(50)
	$Script:UpdateDownloadTimer = $timer
	$Script:UpdateDownloadPowerShell = $ps
	$Script:UpdateDownloadRunspace = $runspace
	$Script:UpdateDownloadAsyncResult = $asyncResult
	$Script:UpdateDownloadSyncHash = $syncHash

	$timer.Add_Tick({
		if ($syncHash.Error)
		{
			$timer.Stop()
			$Script:UpdateDownloadTimer = $null
			$Script:UpdateDownloadSyncHash = $null
			if ($Script:TxtDownloadProgressLabel) { $Script:TxtDownloadProgressLabel.Text = (Get-UxLocalizedString -Key 'GuiStatusDownloadFailedFormat' -Fallback 'Download failed: {0}' -FormatArgs @($syncHash.Error)) }
			if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.Content = (Get-UxLocalizedString -Key 'GuiStatusDownloadRetry' -Fallback 'Retry') }
			if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.IsEnabled = $true }
			if ($Script:BtnDownloadNo) { $Script:BtnDownloadNo.IsEnabled = $true }
			try { if ($asyncResult) { [void]$ps.EndInvoke($asyncResult) } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.EndInvoke' }
			try { $ps.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.DisposePowerShell' }
			try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.DisposeRunspace' }
			$Script:UpdateDownloadPowerShell = $null
			$Script:UpdateDownloadRunspace = $null
			$Script:UpdateDownloadAsyncResult = $null
			return
		}

		if ($Script:CustomProgressBar)
		{
			$Script:CustomProgressBar.IsIndeterminate = [bool]$syncHash.IsIndeterminate
			if (-not [bool]$syncHash.IsIndeterminate) { $Script:CustomProgressBar.Value = $syncHash.ProgressPct }
		}
		if ($Script:TxtDownloadProgressPct) { $Script:TxtDownloadProgressPct.Text = "$($syncHash.ProgressPct)%" }
		if ($Script:TxtDownloadProgressLabel) { $Script:TxtDownloadProgressLabel.Text = $syncHash.Status }

		if ($syncHash.IsComplete -and -not $syncHash.Error)
		{
			$timer.Stop()
			$Script:UpdateDownloadTimer = $null
			$Script:UpdateDownloadSyncHash = $null
			if ($Script:CustomProgressBar)
			{
				$Script:CustomProgressBar.IsIndeterminate = $false
				$Script:CustomProgressBar.Value = 100
			}
			if ($Script:TxtDownloadProgressPct) { $Script:TxtDownloadProgressPct.Text = "100%" }
			if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.Content = (Get-UxLocalizedString -Key 'GuiStatusDownloadExtractRestart' -Fallback 'Extract & Restart') }
			if ($Script:BtnDownloadYes) { $Script:BtnDownloadYes.IsEnabled = $true }
			if ($Script:BtnDownloadNo) { $Script:BtnDownloadNo.IsEnabled = $true }

			$Script:UpdateOverlayPrimaryClickAction = $Script:DownloadExtractEvent
			if ($Script:UpdateOverlayState)
			{
				$Script:UpdateOverlayState.PrimaryCloses = $false
				$Script:UpdateOverlayState.PrimaryAction = $Script:DownloadExtractEvent
			}

			try { if ($asyncResult) { [void]$ps.EndInvoke($asyncResult) } } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.EndInvoke' }
			try { $ps.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.DisposePowerShell' }
			try { $runspace.Dispose() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'UpdateOverlayModule.DownloadCleanup.DisposeRunspace' }
			$Script:UpdateDownloadPowerShell = $null
			$Script:UpdateDownloadRunspace = $null
			$Script:UpdateDownloadAsyncResult = $null
		}
	}.GetNewClosure())

	$timer.Start()
}
