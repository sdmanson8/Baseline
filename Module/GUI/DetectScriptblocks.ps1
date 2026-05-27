#region Detect & Visibility Scriptblocks
# Detect scriptblocks keyed by Function name (cannot be stored in JSON).
# Used by system-scan to determine current on/off state of a tweak.

function Invoke-GuiDetectScriptblock
{
	param (
		[scriptblock]$Detect,
		[object]$DefaultValue = $false
	)

	if ($Script:DesignMode)
	{
		return $DefaultValue
	}

	if (-not $Detect)
	{
		return $DefaultValue
	}

	return (& {
		Set-StrictMode -Off
		& $Detect
	})
}

function Get-GuiDetectMpPreference
{
	try
	{
		return (Get-MpPreference -EA Stop)
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.Get-GuiDetectMpPreference:catch34' -Severity Debug }

		return $null
	}
}

function Get-GuiDetectWindowsOptionalFeatureState
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$FeatureName,

		[int]$TimeoutSeconds = 8,

		[string]$DismPath = $null
	)

	if ([string]::IsNullOrWhiteSpace($FeatureName))
	{
		return $null
	}

	if ($TimeoutSeconds -le 0)
	{
		$TimeoutSeconds = 8
	}

	if ([string]::IsNullOrWhiteSpace($DismPath))
	{
		$dismCandidates = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$env:SystemRoot))
		{
			if ([System.Environment]::Is64BitOperatingSystem -and -not [System.Environment]::Is64BitProcess)
			{
				$dismCandidates += (Join-Path $env:SystemRoot 'Sysnative\dism.exe')
			}
			$dismCandidates += (Join-Path $env:SystemRoot 'System32\dism.exe')
		}

		$DismPath = @($dismCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)[0]
		if ([string]::IsNullOrWhiteSpace($DismPath))
		{
			$DismPath = 'dism.exe'
		}
	}

	$process = $null
	try
	{
		$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$startInfo.FileName = $DismPath
		$startInfo.Arguments = '/Online /Get-FeatureInfo /FeatureName:{0} /English' -f $FeatureName
		$startInfo.UseShellExecute = $false
		$startInfo.CreateNoWindow = $true
		$startInfo.RedirectStandardOutput = $true
		$startInfo.RedirectStandardError = $true

		$process = [System.Diagnostics.Process]::new()
		$process.StartInfo = $startInfo
		if (-not $process.Start())
		{
			return $null
		}

		if (-not $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000))
		{
			try { $process.Kill() } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.Get-GuiDetectWindowsOptionalFeatureState:catch101' -Severity Debug }
			 }
			return $null
		}

		$output = $process.StandardOutput.ReadToEnd()
		$null = $process.StandardError.ReadToEnd()
		if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output))
		{
			return $null
		}

		$stateMatch = [regex]::Match($output, '(?im)^\s*State\s*:\s*(?<State>[^\r\n]+?)\s*$')
		if (-not $stateMatch.Success)
		{
			return $null
		}

		return [string]$stateMatch.Groups['State'].Value.Trim()
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.WindowsOptionalFeatureState'
		}
		return $null
	}
	finally
	{
		if ($process)
		{
			try { $process.Dispose() } catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.Get-GuiDetectWindowsOptionalFeatureState:catch132' -Severity Debug }
			 }
		}
	}
}

$Script:DetectScriptblocks = @{
	'DiagTrackService' = { (Get-Service DiagTrack -EA SilentlyContinue).StartType -ne "Disabled" }
	'MaintenanceWakeUp' = {
		$maintenancePowerManagement = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name AUPowerManagement -EA SilentlyContinue).AUPowerManagement
		$wakeUp = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name WakeUp -EA SilentlyContinue).WakeUp
		(($maintenancePowerManagement -ne 0) -or ($wakeUp -ne 0))
	}
	'SharedExperiences' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -Name RomeSdkChannelUserAuthzPolicy -EA SilentlyContinue).RomeSdkChannelUserAuthzPolicy -eq 1 }
	'ClipboardHistory' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Clipboard" -Name EnableClipboardHistory -EA SilentlyContinue).EnableClipboardHistory -eq 1 }
	'Superfetch' = { (Get-Service SysMain -EA SilentlyContinue).StartType -ne "Disabled" }
	'Win32LongPathLimit' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -EA SilentlyContinue).LongPathsEnabled -eq 1 }
	'SleepButton' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name ShowSleepOption -EA SilentlyContinue).ShowSleepOption -eq 1 }
	'FastStartup' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -EA SilentlyContinue).HiberbootEnabled -eq 1 }
	'AutoRebootOnCrash' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name AutoReboot -EA SilentlyContinue).AutoReboot -eq 1 }
	'SigninInfo' = { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$sid" -Name OptOut -EA SilentlyContinue).OptOut -ne 1 }
	'LanguageListAccess' = { (Get-ItemProperty "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -EA SilentlyContinue).HttpAcceptLanguageOptOut -ne 1 }
	'OnlineSpeechRecognition' = {
		$setting = Get-ItemProperty "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" -Name HasAccepted -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['HasAccepted'])
		{
			return $true
		}

		$setting.HasAccepted -ne 0
	}
	'NarratorOnlineServices' = {
		$setting = Get-ItemProperty "HKCU:\Software\Microsoft\Narrator\NoRoam" -Name OnlineServicesEnabled -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['OnlineServicesEnabled'])
		{
			return $true
		}

		$setting.OnlineServicesEnabled -ne 0
	}
	'NarratorScriptingSupport' = {
		$setting = Get-ItemProperty "HKCU:\Software\Microsoft\Narrator\NoRoam" -Name ScriptingEnabled -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['ScriptingEnabled'])
		{
			return $true
		}

		$setting.ScriptingEnabled -ne 0
	}
	'InkingAndTypingPersonalization' = {
		$setting = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization" -Name Value -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['Value'])
		{
			return $true
		}

		$setting.Value -ne 0
	}
	'DeviceSearchHistory' = {
		$setting = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name IsDeviceSearchHistoryEnabled -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['IsDeviceSearchHistoryEnabled'])
		{
			return $true
		}

		$setting.IsDeviceSearchHistoryEnabled -ne 0
	}
	'CloudContentSearch' = {
		$settings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -EA SilentlyContinue
		if (-not $settings)
		{
			return $true
		}

		$msaEnabled = -not $settings.PSObject.Properties['IsMSACloudSearchEnabled'] -or $settings.IsMSACloudSearchEnabled -ne 0
		$aadEnabled = -not $settings.PSObject.Properties['IsAADCloudSearchEnabled'] -or $settings.IsAADCloudSearchEnabled -ne 0
		$msaEnabled -and $aadEnabled
	}
	'WorkplaceJoinMessages' = {
		$machineSetting = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" -Name BlockAADWorkplaceJoin -EA SilentlyContinue
		$userSetting = Get-ItemProperty "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" -Name BlockAADWorkplaceJoin -EA SilentlyContinue

		if (-not $machineSetting -or -not $userSetting)
		{
			return $false
		}
		if (-not $machineSetting.PSObject.Properties['BlockAADWorkplaceJoin'] -or -not $userSetting.PSObject.Properties['BlockAADWorkplaceJoin'])
		{
			return $false
		}

		($machineSetting.BlockAADWorkplaceJoin -eq 1) -and ($userSetting.BlockAADWorkplaceJoin -eq 1)
	}
	'BitLockerAutoEncryption' = {
		$setting = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker" -Name PreventDeviceEncryption -EA SilentlyContinue
		if (-not $setting -or -not $setting.PSObject.Properties['PreventDeviceEncryption'])
		{
			return $false
		}

		$setting.PreventDeviceEncryption -eq 1
	}
	'AdvertisingID' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -EA SilentlyContinue).Enabled -eq 1 }
	'LockWidgets' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarDa -EA SilentlyContinue).TaskbarDa -ne 0 }
	'WindowsTips' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name SoftLandingEnabled -EA SilentlyContinue).SoftLandingEnabled -ne 0 }
	'AppsSilentInstalling' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name SilentInstalledAppsEnabled -EA SilentlyContinue).SilentInstalledAppsEnabled -ne 0 }
	'TailoredExperiences' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name TailoredExperiencesWithDiagnosticDataEnabled -EA SilentlyContinue).TailoredExperiencesWithDiagnosticDataEnabled -ne 0 }
	'BingSearch' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name BingSearchEnabled -EA SilentlyContinue).BingSearchEnabled -ne 0 }
	'WiFiSense' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name Value -EA SilentlyContinue).Value -ne 0 }
	'WebSearch' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name CortanaConsent -EA SilentlyContinue).CortanaConsent -ne 0 }
	'ActivityHistory' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableActivityFeed -EA SilentlyContinue).EnableActivityFeed -ne 0 }
	'MapUpdates' = { (Get-ItemProperty "HKLM:\SYSTEM\Maps" -Name AutoUpdateEnabled -EA SilentlyContinue).AutoUpdateEnabled -eq 1 }
	'WAPPush' = { (Get-Service dmwappushservice -EA SilentlyContinue).StartType -ne "Disabled" }
	'ClearRecentFiles' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ClearRecentDocsOnExit -EA SilentlyContinue).ClearRecentDocsOnExit -eq 1 }
	'RecentFiles' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoRecentDocsHistory -EA SilentlyContinue).NoRecentDocsHistory -ne 1 }
	'CrossDeviceResume' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name IsResumeAllowed -EA SilentlyContinue).IsResumeAllowed -eq 1 }
	'MultiplaneOverlay' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name OverlayTestMode -EA SilentlyContinue).OverlayTestMode -ne 5 }
	'S3Sleep' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name PlatformAoAcOverride -EA SilentlyContinue).PlatformAoAcOverride -eq 0 }
	'ExplorerAutoDiscovery' = { (Get-ItemProperty "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" -Name FolderType -EA SilentlyContinue).FolderType -ne "NotSpecified" }
	'WPBT' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name DisableWpbtExecution -EA SilentlyContinue).DisableWpbtExecution -ne 1 }
	'FullscreenOptimizations' = { (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_DXGIHonorFSEWindowsCompatible -EA SilentlyContinue).GameDVR_DXGIHonorFSEWindowsCompatible -ne 1 }
	'Teredo' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -EA SilentlyContinue).DisabledComponents -ne 255 }
	'ExplorerTitleFullPath' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name FullPath -EA SilentlyContinue).FullPath -eq 1 }
	'NavPaneAllFolders' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneShowAllFolders -EA SilentlyContinue).NavPaneShowAllFolders -eq 1 }
	'NavPaneLibraries' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneShowLibraries -EA SilentlyContinue).NavPaneShowLibraries -eq 1 }
	'FldrSeparateProcess' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SeparateProcess -EA SilentlyContinue).SeparateProcess -eq 1 }
	'RestoreFldrWindows' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name PersistBrowsers -EA SilentlyContinue).PersistBrowsers -eq 1 }
	'EncCompFilesColor' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowEncryptCompressedColor -EA SilentlyContinue).ShowEncryptCompressedColor -eq 1 }
	'SharingWizard' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SharingWizardOn -EA SilentlyContinue).SharingWizardOn -ne 0 }
	'SelectCheckboxes' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name AutoCheckSelect -EA SilentlyContinue).AutoCheckSelect -eq 1 }
	'SyncNotifications' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSyncProviderNotifications -EA SilentlyContinue).ShowSyncProviderNotifications -eq 1 }
	'BuildNumberOnDesktop' = { (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name PaintDesktopVersion -EA SilentlyContinue).PaintDesktopVersion -eq 1 }
	'Thumbnails' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name IconsOnly -EA SilentlyContinue).IconsOnly -ne 1 }
	'ThumbnailCache' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisableThumbnailCache -EA SilentlyContinue).DisableThumbnailCache -ne 1 }
	'ThumbsDBOnNetwork' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisableThumbsDBOnNetworkFolders -EA SilentlyContinue).DisableThumbsDBOnNetworkFolders -ne 1 }
	'CheckBoxes' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name AutoCheckSelect -EA SilentlyContinue).AutoCheckSelect -eq 1 }
	'HiddenItems' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -EA SilentlyContinue).Hidden -eq 1 }
	'SuperHiddenFiles' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSuperHidden -EA SilentlyContinue).ShowSuperHidden -eq 1 }
	'FileExtensions' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideFileExt -EA SilentlyContinue).HideFileExt -ne 1 }
	'MergeConflicts' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideMergeConflicts -EA SilentlyContinue).HideMergeConflicts -ne 1 }
	'SnapAssist' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SnapAssist -EA SilentlyContinue).SnapAssist -ne 0 }
	'RecycleBinDeleteConfirmation' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ConfirmFileDelete -EA SilentlyContinue).ConfirmFileDelete -eq 1 }
	'MeetNow' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name HideSCAMeetNow -EA SilentlyContinue).HideSCAMeetNow -ne 1 }
	'NewsInterests' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name ShellFeedsTaskbarViewMode -EA SilentlyContinue).ShellFeedsTaskbarViewMode -ne 2 }
	'TaskbarAlignment' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarAl -EA SilentlyContinue).TaskbarAl -ne 1 }
	'TaskbarWidgets' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarDa -EA SilentlyContinue).TaskbarDa -ne 0 }
	'TaskViewButton' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowTaskViewButton -EA SilentlyContinue).ShowTaskViewButton -ne 0 }
	'TaskbarEndTask' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name TaskbarEndTask -EA SilentlyContinue).TaskbarEndTask -eq 1 }
	'FirstLogonAnimation' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name EnableFirstLogonAnimation -EA SilentlyContinue).EnableFirstLogonAnimation -ne 0 }
	'JPEGWallpapersQuality' = { (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -EA SilentlyContinue).JPEGImportQuality -eq 100 }
	'PrtScnSnippingTool' = { (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name PrintScreenKeyForSnippingEnabled -EA SilentlyContinue).PrintScreenKeyForSnippingEnabled -eq 1 }
	'AeroShaking' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisallowShaking -EA SilentlyContinue).DisallowShaking -ne 1 }
	'NavigationPaneExpand' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneExpandToCurrentFolder -EA SilentlyContinue).NavPaneExpandToCurrentFolder -eq 1 }
	'LockScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreen -EA SilentlyContinue).NoLockScreen -ne 1 }
	'LockScreenRS1' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableLockScreen -EA SilentlyContinue).DisableLockScreen -ne 1 }
	'LockScreenCamera' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreenCamera -EA SilentlyContinue).NoLockScreenCamera -eq 1 }
	'BlockDomainPINLogon' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name AllowDomainPINLogon -EA SilentlyContinue).AllowDomainPINLogon -eq 0 }
	'MountManagerAutoMount' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\MountMgr" -Name NoAutoMount -EA SilentlyContinue).NoAutoMount -eq 1 }
	'NetworkFromLockScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DontDisplayNetworkSelectionUI -EA SilentlyContinue).DontDisplayNetworkSelectionUI -ne 1 }
	'ShutdownFromLockScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name ShutdownWithoutLogon -EA SilentlyContinue).ShutdownWithoutLogon -eq 1 }
	'AdminApprovalMode' = {
		$systemPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -EA SilentlyContinue
		$consentPromptBehaviorAdmin = if ($systemPolicy -and $systemPolicy.PSObject.Properties['ConsentPromptBehaviorAdmin']) { [int]$systemPolicy.ConsentPromptBehaviorAdmin } else { 5 }
		$promptOnSecureDesktop = if ($systemPolicy -and $systemPolicy.PSObject.Properties['PromptOnSecureDesktop']) { [int]$systemPolicy.PromptOnSecureDesktop } else { 1 }

		switch ("$consentPromptBehaviorAdmin|$promptOnSecureDesktop")
		{
			'1|1' { return 'PromptForCredentials' }
			'2|1' { return 'AlwaysNotify' }
			'5|1' { return 'Default' }
			'5|0' { return 'NoDim' }
			'0|0' { return 'Never' }
			default { return $null }
		}
	}
	'LockScreenBlur' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableAcrylicBackgroundOnLogon -EA SilentlyContinue).DisableAcrylicBackgroundOnLogon -ne 1 }
	'TaskManagerDetails' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name Preferences -EA SilentlyContinue) -ne $null }
	'FileOperationsDetails' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name EnthusiastMode -EA SilentlyContinue).EnthusiastMode -eq 1 }
	'FileDeleteConfirm' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ConfirmFileDelete -EA SilentlyContinue).ConfirmFileDelete -eq 1 }
	'TrayIcons' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoAutoTrayNotify -EA SilentlyContinue).NoAutoTrayNotify -ne 1 }
	'SearchAppInStore' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoUseStoreOpenWith -EA SilentlyContinue).NoUseStoreOpenWith -ne 1 }
	'BlockStoreSearchResults' = {
		$storeDbPath = Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db'
		if (-not (Test-Path -LiteralPath $storeDbPath))
		{
			return $false
		}

		$acl = Get-Acl -LiteralPath $storeDbPath -EA SilentlyContinue
		if (-not $acl)
		{
			return $false
		}

		foreach ($rule in @($acl.Access))
		{
			try
			{
				$identitySid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.BlockStoreSearchResults.LoadIdentitySid'
				$identitySid = $rule.IdentityReference.Value
			}

			if (
				$identitySid -eq 'S-1-1-0' -and
				$rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
				(($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -ne 0)
			)
			{
				return $true
			}
		}

		return $false
	}
	'NewAppPrompt' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoNewAppAlert -EA SilentlyContinue).NoNewAppAlert -ne 1 }
	'RecentlyAddedApps' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name HideRecentlyAddedApps -EA SilentlyContinue).HideRecentlyAddedApps -ne 1 }
	'TitleBarColor' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\DWM" -Name ColorPrevalence -EA SilentlyContinue).ColorPrevalence -eq 1 }
	'EnhPointerPrecision' = { (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name MouseSpeed -EA SilentlyContinue).MouseSpeed -eq 1 }
	'StartupSound' = {
		$bootAnimationSound = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name DisableStartupSound -EA SilentlyContinue).DisableStartupSound
		$editionOverrideSound = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides" -Name UserSetting_DisableStartupSound -EA SilentlyContinue).UserSetting_DisableStartupSound
		($bootAnimationSound -ne 1 -and $editionOverrideSound -ne 1)
	}
	'ChangingSoundScheme' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoChangingSoundScheme -EA SilentlyContinue).NoChangingSoundScheme -ne 1 }
	'SoundDuckingPreference' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Multimedia\Audio" -Name UserDuckingPreference -EA SilentlyContinue).UserDuckingPreference -eq 3 }
	'NarratorAudioDucking' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Narrator\NoRoam" -Name DuckAudio -EA SilentlyContinue).DuckAudio -eq 1 }
	'SpeechOneCoreVoiceActivation' = { (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\SpeechOneCore\Settings" -Name AgentActivationEnabled -EA SilentlyContinue).AgentActivationEnabled -eq 1 }
	'AccessibilityActivationSounds' = { (Get-ItemProperty "HKCU:\Control Panel\Accessibility" -Name 'Sound on Activation' -EA SilentlyContinue).'Sound on Activation' -eq 1 }
	'AccessibilityWarningSounds' = { (Get-ItemProperty "HKCU:\Control Panel\Accessibility" -Name 'Warning Sounds' -EA SilentlyContinue).'Warning Sounds' -eq 1 }
	'VerboseStatus' = { (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name VerboseStatus -EA SilentlyContinue).VerboseStatus -eq 1 }
	'StorageSense' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -EA SilentlyContinue)."01" -eq 1 }
	'Hibernation' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name HibernateEnabled -EA SilentlyContinue).HibernateEnabled -eq 1 }
	'BSoDStopError' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name DisplayParameters -EA SilentlyContinue).DisplayParameters -eq 1 }
	'ActiveHours' = {
		$settings = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -EA SilentlyContinue
		($settings -and ($settings.SmartActiveHoursState -eq 0))
	}
	'DeliveryOptimization' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name DODownloadMode -EA SilentlyContinue).DODownloadMode -ne 99 }
	'DownloadUpdatesOverMeteredConnection' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name AllowAutoWindowsUpdateDownloadOverMeteredNetwork -EA SilentlyContinue).AllowAutoWindowsUpdateDownloadOverMeteredNetwork -eq 1 }
	'RestartDeviceAfterUpdate' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name IsExpedited -EA SilentlyContinue).IsExpedited -eq 1 }
	'RestartNotification' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name RestartNotificationsAllowed2 -EA SilentlyContinue).RestartNotificationsAllowed2 -eq 1 }
	'UpdateNotificationLevel' = {
		$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
		$policy = Get-ItemProperty $policyPath -Name SetUpdateNotificationLevel -EA SilentlyContinue
		if (-not $policy -or -not $policy.PSObject.Properties['SetUpdateNotificationLevel'])
		{
			return 'Default'
		}

		switch ([int]$policy.SetUpdateNotificationLevel)
		{
			0 { return 'All' }
			1 { return 'RestartOnly' }
			2 { return 'Off' }
			default { return 'Default' }
		}
	}
	'FeatureUpdateDeferral' = {
		$settings = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -EA SilentlyContinue
		($settings -and $settings.DeferFeatureUpdates -eq 1 -and $settings.DeferFeatureUpdatesPeriodInDays -eq 365)
	}
	'QualityUpdateDeferral' = {
		$settings = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -EA SilentlyContinue
		($settings -and $settings.DeferQualityUpdates -eq 1 -and $settings.DeferQualityUpdatesPeriodInDays -in @(4, 7))
	}
	'StoreAppAutoDownload' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name AutoDownload -EA SilentlyContinue).AutoDownload -eq 4 }
	'WindowsUpdatePause' = {
		$settings = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -EA SilentlyContinue
		$pauseFeature = if ($settings -and $settings.PauseFeatureUpdatesStartTime) { [string]$settings.PauseFeatureUpdatesStartTime } else { $null }
		$pauseQuality = if ($settings -and $settings.PauseQualityUpdatesStartTime) { [string]$settings.PauseQualityUpdatesStartTime } else { $null }
		$pauseGeneral = if ($settings -and $settings.PauseUpdatesStartTime) { [string]$settings.PauseUpdatesStartTime } else { $null }
		$pausedFeature = if ($settings -and $settings.PausedFeatureDate) { [string]$settings.PausedFeatureDate } else { $null }
		$pausedQuality = if ($settings -and $settings.PausedQualityDate) { [string]$settings.PausedQualityDate } else { $null }
		-not [string]::IsNullOrWhiteSpace($pauseFeature) -or
		-not [string]::IsNullOrWhiteSpace($pauseQuality) -or
		-not [string]::IsNullOrWhiteSpace($pauseGeneral) -or
		-not [string]::IsNullOrWhiteSpace($pausedFeature) -or
		-not [string]::IsNullOrWhiteSpace($pausedQuality)
	}
	'WindowsUpdateSecurityOnlyMode' = {
		$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
		$windowsUpdatePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
		$deviceMetadataPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
		$driverSearchingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
		$policyAuOptions = (Get-ItemProperty $policyPath -Name AUOptions -EA SilentlyContinue).AUOptions
		$branchReadiness = (Get-ItemProperty $windowsUpdatePath -Name BranchReadinessLevel -EA SilentlyContinue).BranchReadinessLevel
		$deferFeature = (Get-ItemProperty $windowsUpdatePath -Name DeferFeatureUpdates -EA SilentlyContinue).DeferFeatureUpdates
		$deferFeatureDays = (Get-ItemProperty $windowsUpdatePath -Name DeferFeatureUpdatesPeriodInDays -EA SilentlyContinue).DeferFeatureUpdatesPeriodInDays
		$deferQuality = (Get-ItemProperty $windowsUpdatePath -Name DeferQualityUpdates -EA SilentlyContinue).DeferQualityUpdates
		$deferQualityDays = (Get-ItemProperty $windowsUpdatePath -Name DeferQualityUpdatesPeriodInDays -EA SilentlyContinue).DeferQualityUpdatesPeriodInDays
		$preventMetadata = (Get-ItemProperty $deviceMetadataPath -Name PreventDeviceMetadataFromNetwork -EA SilentlyContinue).PreventDeviceMetadataFromNetwork
		$searchOrder = (Get-ItemProperty $driverSearchingPath -Name SearchOrderConfig -EA SilentlyContinue).SearchOrderConfig
		$excludeDrivers = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name ExcludeWUDriversInQualityUpdate -EA SilentlyContinue).ExcludeWUDriversInQualityUpdate
		$restartDebugger = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MusNotification.exe" -Name Debugger -EA SilentlyContinue).Debugger
		($policyAuOptions -eq 2 -and
		$branchReadiness -eq 20 -and
		$deferFeature -eq 1 -and
		$deferFeatureDays -eq 365 -and
		$deferQuality -eq 1 -and
		$deferQualityDays -eq 4 -and
		$preventMetadata -eq 1 -and
		$searchOrder -eq 0 -and
		$excludeDrivers -eq 1 -and
		[string]$restartDebugger -eq 'cmd.exe')
	}
	'WindowsManageDefaultPrinter' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -EA SilentlyContinue).LegacyDefaultPrinterMode -ne 1 }
	'SMBServer' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name SMB2 -EA SilentlyContinue).SMB2 -ne 0 }
	'NetBIOS' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue) -ne $null }
	'LLMNR' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -EA SilentlyContinue).EnableMulticast -ne 0 }
	'ConnectionSharing' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name NC_ShowSharedAccessUI -EA SilentlyContinue).NC_ShowSharedAccessUI -ne 0 }
	'ReservedStorage' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name ShippedWithReserves -EA SilentlyContinue).ShippedWithReserves -eq 1 }
	'NumLock' = { (Get-ItemProperty "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" -Name InitialKeyboardIndicators -EA SilentlyContinue).InitialKeyboardIndicators -match "2" }
	'CapsLock' = { -not ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -EA SilentlyContinue)."Scancode Map") }
	'StickyShift' = { (Get-ItemProperty "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -EA SilentlyContinue).Flags -ne 506 }
	'Autoplay' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -EA SilentlyContinue).DisableAutoplay -ne 1 }
	'SaveRestartableApps' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name RestartApps -EA SilentlyContinue).RestartApps -eq 1 }
	'NetworkDiscovery' = { (Get-NetFirewallRule -DisplayGroup "Network Discovery" -EA SilentlyContinue | Where-Object Enabled -eq True | Select-Object -First 1) -ne $null }
	'RegistryBackup' = {
		$periodicBackupEnabled = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name EnablePeriodicBackup -EA SilentlyContinue).EnablePeriodicBackup -eq 1
		$autoRegBackupTask = $false
			try
			{
				$autoRegBackupTask = [bool](Get-ScheduledTask -TaskName 'AutoRegBackup' -ErrorAction SilentlyContinue)
			}
			catch
			{
				Write-SwallowedException -ErrorRecord $_ -Source 'DetectScriptblocks.RegistryBackup.LoadAutoRegBackupTask'
				$autoRegBackupTask = $false
			}
		($periodicBackupEnabled -and $autoRegBackupTask)
	}
	'XboxGameBar' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name AppCaptureEnabled -EA SilentlyContinue).AppCaptureEnabled -ne 0 }
	'XboxGameTips' = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name ShowStartupPanel -EA SilentlyContinue).ShowStartupPanel -ne 0 }
	'GPUScheduling' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name HwSchMode -EA SilentlyContinue).HwSchMode -eq 2 }
	'GameDVR' = { (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA SilentlyContinue).GameDVR_Enabled -ne 0 }
	'WindowsGameMode' = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name AutoGameModeEnabled -EA SilentlyContinue).AutoGameModeEnabled -ne 0 }
	'MouseAcceleration' = { (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name MouseSpeed -EA SilentlyContinue).MouseSpeed -ne "0" }
	'NaglesAlgorithm' = { -not ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*" -Name TCPNoDelay -EA SilentlyContinue).TCPNoDelay -contains 1) }
	'NetworkProtection' = { $mpPreference = Get-GuiDetectMpPreference; $mpPreference -and $mpPreference.EnableNetworkProtection -eq 1 }
	'DefenderSandbox' = { [System.Environment]::GetEnvironmentVariable("MP_FORCE_USE_SANDBOX","Machine") -eq "1" }
	'DefenderScanCPULimit' = { $mpPreference = Get-GuiDetectMpPreference; $mpPreference -and $mpPreference.ScanAvgCPULoadFactor -le 25 }
	'DefenderSignatureUpdateInterval' = { $mpPreference = Get-GuiDetectMpPreference; if (-not $mpPreference) { $false } else { $i = $mpPreference.SignatureUpdateInterval; ($i -ge 1 -and $i -le 1) } }
	'PowerShellModulesLogging' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name EnableModuleLogging -EA SilentlyContinue).EnableModuleLogging -eq 1 }
	'PowerShellScriptsLogging' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name EnableScriptBlockLogging -EA SilentlyContinue).EnableScriptBlockLogging -eq 1 }
	'AppsSmartScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableSmartScreen -EA SilentlyContinue).EnableSmartScreen -ne 0 }
	'SaveZoneInformation' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name SaveZoneInformation -EA SilentlyContinue).SaveZoneInformation -ne 2 }
	'WindowsScriptHost' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name Enabled -EA SilentlyContinue).Enabled -ne 0 }
	'WindowsSandbox' = { (Get-GuiDetectWindowsOptionalFeatureState -FeatureName 'Containers-DisposableClientVM') -eq 'Enabled' }
	'LocalSecurityAuthority' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -EA SilentlyContinue).RunAsPPL -ge 1 }
	'SharingMappedDrives' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLinkedConnections -EA SilentlyContinue).EnableLinkedConnections -eq 1 }
	'Firewall' = { (Get-NetFirewallProfile -EA SilentlyContinue | Where-Object Enabled -eq True | Select-Object -First 1) -ne $null }
	'DefenderTrayIcon' = { (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows Defender Security Center\Systray" -Name HideSystray -EA SilentlyContinue).HideSystray -ne 1 }
	'DefenderCloud' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name SpynetReporting -EA SilentlyContinue).SpynetReporting -ne 0 }
	'CIMemoryIntegrity' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name Enabled -EA SilentlyContinue).Enabled -eq 1 }
	'AccountProtectionWarn' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows Security Health\State" -Name AccountProtection_MicrosoftAccount_Disconnected -EA SilentlyContinue).AccountProtectionWarn -ne 1 }
	'DownloadBlocking' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name SaveZoneInformation -EA SilentlyContinue).SaveZoneInformation -ne 2 }
	'F8BootMenu' = { (bcdedit /enum "{current}" 2>$null) -match "bootmenupolicy.*legacy" }
	'BootRecovery' = { (bcdedit /enum "{current}" 2>$null) -match "recoveryenabled.*Yes" }
	'MSIExtractContext' = { Test-Path "Registry::HKEY_CLASSES_ROOT\Msi.Package\shell\Extract" }
	'CABInstallContext' = { Test-Path "Registry::HKEY_CLASSES_ROOT\CABFolder\Shell\runas" }
	'MultipleInvokeContext' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name MultipleInvokePromptMinimum -EA SilentlyContinue).MultipleInvokePromptMinimum -ge 15 }
	'OpenWindowsTerminalContext' = { Test-Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\OpenWTHere" }
	'SecondsInSystemClock' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSecondsInSystemClock -EA SilentlyContinue).ShowSecondsInSystemClock -eq 1 }
	'ClockInNotificationCenter' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowClock -EA SilentlyContinue).ShowClock -ne 0 }
	'NetworkThrottling' = { (Get-ItemProperty "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name NetworkThrottlingIndex -EA SilentlyContinue).NetworkThrottlingIndex -ne -1 }
	'GameBarController' = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name UseNexusForGameBarEnabled -EA SilentlyContinue).UseNexusForGameBarEnabled -ne 0 }
	'DesktopComposition' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\DWM" -Name CompositionPolicy -EA SilentlyContinue).CompositionPolicy -ne 0 }
	'XboxAuthManager' = { (Get-Service XblAuthManager -EA SilentlyContinue).StartType -ne "Disabled" }
	'XboxGameSave' = { (Get-Service XblGameSave -EA SilentlyContinue).StartType -ne "Disabled" }
	'XboxNetworking' = { (Get-Service XboxNetApiSvc -EA SilentlyContinue).StartType -ne "Disabled" }
}

# VisibleIf scriptblocks keyed by Function name.
# Controls OS-specific tweak visibility (e.g. Win10 vs Win11).
$Script:VisibleIfScriptblocks = @{
	# Hidden in the GUI; preset and headless paths still resolve the manifest entry.
	'CheckWinGet' = { $false }
	'LockScreen' = { ((Get-OSInfo).OSName -like "*Windows 11*") }
	'LockScreenRS1' = { ((Get-OSInfo).OSName -like "*Windows 10*") }
}
#endregion Detect & Visibility Scriptblocks
