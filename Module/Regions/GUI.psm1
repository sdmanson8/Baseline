using module ..\Logging.psm1
using module ..\SharedHelpers.psm1
using module ..\GUICommon.psm1
using module ..\GUIExecution.psm1

function New-SafeThickness
{
	param(
		[double]$Left = 0,
		[double]$Top = 0,
		[double]$Right = 0,
		[double]$Bottom = 0,
		[Nullable[double]]$Uniform = $null
	)

	if ($null -ne $Uniform)
	{
		return [System.Windows.Thickness]::new([double]$Uniform)
	}

	return [System.Windows.Thickness]::new($Left, $Top, $Right, $Bottom)
}

function New-WpfSetter
{
	param(
		[Parameter(Mandatory)][System.Windows.DependencyProperty]$Property,
		[Parameter(Mandatory)][object]$Value,
		[string]$TargetName
	)

	$setter = New-Object System.Windows.Setter
	$setter.Property = $Property
	$setter.Value = $Value
	if (-not [string]::IsNullOrWhiteSpace($TargetName))
	{
		$setter.TargetName = $TargetName
	}

	return $setter
}

function Show-GuiRuntimeFailure
{
	param (
		[string]$Context = 'GUI',
		[System.Exception]$Exception,
		[switch]$ShowDialog
	)

	if (-not $Exception) { return $null }

	$errorLines = New-Object System.Collections.Generic.List[string]
	[void]$errorLines.Add(("GUI event failed [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Exception.Message))
	[void]$errorLines.Add(("Exception type: {0}" -f $Exception.GetType().FullName))
	if ($Exception.InnerException)
	{
		[void]$errorLines.Add(("Inner exception: {0}" -f $Exception.InnerException.Message))
	}
	if ($Exception.StackTrace)
	{
		[void]$errorLines.Add('Stack trace:')
		[void]$errorLines.Add($Exception.StackTrace.Trim())
	}

	$errorText = ($errorLines -join [Environment]::NewLine)
	if (Get-Command -Name 'LogError' -CommandType Function -ErrorAction SilentlyContinue)
	{
		LogError $errorText
	}
	else
	{
		Write-Warning $errorText
	}

	if ($ShowDialog -and $Script:MainForm -and $Script:CurrentTheme)
	{
		try
		{
			$noopButtonChrome = [scriptblock]::Create('param($Button, $Variant)')
			GUICommon\Show-ThemedDialog `
				-Theme $Script:CurrentTheme `
				-ApplyButtonChrome $noopButtonChrome `
				-OwnerWindow $Script:MainForm `
				-Title 'GUI Error' `
				-Message $errorText `
				-Buttons @('OK') `
				-AccentButton 'OK' | Out-Null
		}
		catch
		{
			$null = $_
		}
	}

	return $errorText
}

function Write-GuiPresetDebug
{
	param (
		[string]$Context = 'GUI',
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return }

	$debugText = "GUI preset debug [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Message
	try
	{
		if (-not $Script:GuiPresetDebugTrail)
		{
			$Script:GuiPresetDebugTrail = [System.Collections.Generic.List[string]]::new()
		}
		$trailEntry = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $debugText
		[void]$Script:GuiPresetDebugTrail.Add($trailEntry)
		while ($Script:GuiPresetDebugTrail.Count -gt 100)
		{
			$Script:GuiPresetDebugTrail.RemoveAt(0)
		}

		if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogWarning -Message $debugText -ShowConsole
		}
		else
		{
			Write-Warning $debugText
		}
	}
	catch
	{
		try
		{
			Write-Warning $debugText
		}
		catch
		{
			$null = $_
		}
	}
}

$Script:GuiPresetDebugScript = ${function:Write-GuiPresetDebug}

<#
	.SYNOPSIS
	WPF-based GUI that replaces the preset file (Baseline.ps1).

	.DESCRIPTION
	Builds a modern two-tier tabbed WPF window from a tweak manifest.
	Each tweak is presented with clear Enable/Disable visual state,
	info icons for descriptions, and grouped caution warnings per tab.
	The GUI stays open for multiple runs and supports light/dark themes.

	.NOTES
	Tweak types
	  Toggle  – Enable/Disable or Show/Hide parameter pair
	  Choice  – Multiple named parameter sets (combo box)
	  Action  – No parameters; checkbox means "run this"

	Manifest field reference
	  Name            Display text
	  Category        Primary tab name
	  SubCategory     Secondary tab name (optional)
	  Function        PowerShell function to invoke
	  Type            Toggle | Choice | Action
	  OnParam         Parameter name for the "on" / positive state   (Toggle only)
	  OffParam        Parameter name for the "off" / negative state  (Toggle only)
	  Options         [string[]] of available parameter names        (Choice only)
	  DisplayOptions  [string[]] of friendly display names           (Choice only)
	  Default         $true/$false (Toggle/Action) or string (Choice)
	  WinDefault      The Windows-default value ($true/$false or string)
	  Description     Info tooltip text
	  Caution         $true if the tweak carries a CAUTION warning
	  CautionReason   Explanation of why this tweak is cautioned
	  ExtraArgs       Hashtable of additional arguments
	  Scannable       $true (default) if system-scan can detect state; $false to always allow re-run
#>

#region Detect & Visibility Scriptblocks
# Detect scriptblocks keyed by Function name (cannot be stored in JSON).
# Used by system-scan to determine current on/off state of a tweak.
$Script:DetectScriptblocks = @{
	'DiagTrackService' = { (Get-Service DiagTrack -EA SilentlyContinue).StartType -ne "Disabled" }
	'MaintenanceWakeUp' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name MaintenanceDisabled -EA SilentlyContinue).MaintenanceDisabled -ne 1 }
	'SharedExperiences' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -Name RomeSdkChannelUserAuthzPolicy -EA SilentlyContinue).RomeSdkChannelUserAuthzPolicy -eq 1 }
	'ClipboardHistory' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Clipboard" -Name EnableClipboardHistory -EA SilentlyContinue).EnableClipboardHistory -eq 1 }
	'Superfetch' = { (Get-Service SysMain -EA SilentlyContinue).StartType -ne "Disabled" }
	'NTFSLongPaths' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -EA SilentlyContinue).LongPathsEnabled -eq 1 }
	'SleepButton' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name ShowSleepOption -EA SilentlyContinue).ShowSleepOption -eq 1 }
	'FastStartup' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -EA SilentlyContinue).HiberbootEnabled -eq 1 }
	'AutoRebootOnCrash' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name AutoReboot -EA SilentlyContinue).AutoReboot -eq 1 }
	'SigninInfo' = { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$sid" -Name OptOut -EA SilentlyContinue).OptOut -ne 1 }
	'LanguageListAccess' = { (Get-ItemProperty "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -EA SilentlyContinue).HttpAcceptLanguageOptOut -ne 1 }
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
	'NetworkFromLockScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DontDisplayNetworkSelectionUI -EA SilentlyContinue).DontDisplayNetworkSelectionUI -ne 1 }
	'ShutdownFromLockScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name ShutdownWithoutLogon -EA SilentlyContinue).ShutdownWithoutLogon -eq 1 }
	'LockScreenBlur' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableAcrylicBackgroundOnLogon -EA SilentlyContinue).DisableAcrylicBackgroundOnLogon -ne 1 }
	'TaskManagerDetails' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name Preferences -EA SilentlyContinue) -ne $null }
	'FileOperationsDetails' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name EnthusiastMode -EA SilentlyContinue).EnthusiastMode -eq 1 }
	'FileDeleteConfirm' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ConfirmFileDelete -EA SilentlyContinue).ConfirmFileDelete -eq 1 }
	'TrayIcons' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoAutoTrayNotify -EA SilentlyContinue).NoAutoTrayNotify -ne 1 }
	'SearchAppInStore' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoUseStoreOpenWith -EA SilentlyContinue).NoUseStoreOpenWith -ne 1 }
	'NewAppPrompt' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoNewAppAlert -EA SilentlyContinue).NoNewAppAlert -ne 1 }
	'RecentlyAddedApps' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name HideRecentlyAddedApps -EA SilentlyContinue).HideRecentlyAddedApps -ne 1 }
	'TitleBarColor' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\DWM" -Name ColorPrevalence -EA SilentlyContinue).ColorPrevalence -eq 1 }
	'EnhPointerPrecision' = { (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name MouseSpeed -EA SilentlyContinue).MouseSpeed -eq 1 }
	'StartupSound' = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name DisableStartupSound -EA SilentlyContinue).DisableStartupSound -ne 1 }
	'ChangingSoundScheme' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoChangingSoundScheme -EA SilentlyContinue).NoChangingSoundScheme -ne 1 }
	'VerboseStatus' = { (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name VerboseStatus -EA SilentlyContinue).VerboseStatus -eq 1 }
	'StorageSense' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -EA SilentlyContinue)."01" -eq 1 }
	'Hibernation' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name HibernateEnabled -EA SilentlyContinue).HibernateEnabled -eq 1 }
	'BSoDStopError' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name DisplayParameters -EA SilentlyContinue).DisplayParameters -eq 1 }
	'DeliveryOptimization' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name DODownloadMode -EA SilentlyContinue).DODownloadMode -ne 99 }
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
	'RegistryBackup' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name EnablePeriodicBackup -EA SilentlyContinue).EnablePeriodicBackup -eq 1 }
	'XboxGameBar' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name AppCaptureEnabled -EA SilentlyContinue).AppCaptureEnabled -ne 0 }
	'XboxGameTips' = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name ShowStartupPanel -EA SilentlyContinue).ShowStartupPanel -ne 0 }
	'GPUScheduling' = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name HwSchMode -EA SilentlyContinue).HwSchMode -eq 2 }
	'NetworkProtection' = { try { (Get-MpPreference -EA Stop).EnableNetworkProtection -eq 1 } catch { $false } }
	'DefenderSandbox' = { [System.Environment]::GetEnvironmentVariable("MP_FORCE_USE_SANDBOX","Machine") -eq "1" }
	'PowerShellModulesLogging' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name EnableModuleLogging -EA SilentlyContinue).EnableModuleLogging -eq 1 }
	'PowerShellScriptsLogging' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name EnableScriptBlockLogging -EA SilentlyContinue).EnableScriptBlockLogging -eq 1 }
	'AppsSmartScreen' = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableSmartScreen -EA SilentlyContinue).EnableSmartScreen -ne 0 }
	'SaveZoneInformation' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name SaveZoneInformation -EA SilentlyContinue).SaveZoneInformation -ne 2 }
	'WindowsScriptHost' = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name Enabled -EA SilentlyContinue).Enabled -ne 0 }
	'WindowsSandbox' = { (Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -EA SilentlyContinue).State -eq "Enabled" }
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
}

# VisibleIf scriptblocks keyed by Function name.
# Controls OS-specific tweak visibility (e.g. Win10 vs Win11).
$Script:VisibleIfScriptblocks = @{
	'LockScreen' = { ((Get-OSInfo).OSName -like "*Windows 11*") }
	'LockScreenRS1' = { ((Get-OSInfo).OSName -like "*Windows 10*") }
}
#endregion Detect & Visibility Scriptblocks

$Script:TweakManifest = @()
$Script:ManifestLoadedFromData = $false

#region GUI Builder
<#
	.SYNOPSIS
	Show the WPF tweak-selection GUI and execute selected tweaks.

	.DESCRIPTION
	Builds a modern two-tier tabbed WPF window from $Script:TweakManifest.
	The GUI stays open after each run so further changes can be made.
	Supports dark/light themes, system-scan to skip already-applied tweaks,
	info icons, caution sections, and linked toggles (PS7 ↔ telemetry).

	.EXAMPLE
	Show-TweakGUI
#>
function Show-TweakGUI
{
	[CmdletBinding()]
	param ()

	if (-not $Script:ManifestLoadedFromData)
	{
		try
		{
			$Script:TweakManifest = Import-TweakManifestFromData `
				-DetectScriptblocks $Script:DetectScriptblocks `
				-VisibleIfScriptblocks $Script:VisibleIfScriptblocks
			Test-TweakManifestIntegrity -Manifest $Script:TweakManifest
		}
		catch
		{
			Write-Warning ("Failed to load tweak metadata from Module/Data: {0}" -f $_.Exception.Message)
			return
		}
		finally
		{
			$Script:ManifestLoadedFromData = $true
		}
	}

	Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

	if (-not $Script:ExplicitPresetSelections) {
		$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}

	$Script:GuiModuleBasePath = $null
	$Script:GuiPresetDirectoryPath = $null

	try { $Script:GuiModuleBasePath = $MyInvocation.MyCommand.Module.ModuleBase } catch {}
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent $PSCommandPath } catch {}
	}
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
	}
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		try { $Script:GuiModuleBasePath = Split-Path -Parent $PSScriptRoot } catch {}
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		$Script:GuiPresetDirectoryPath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Data\Presets'
	}

	# Primary category tabs (top tier)
	$PrimaryCategories = [ordered]@{
		"Initial Setup"        = @()
		"Privacy & Telemetry"  = @()
		"Security"             = @("Security", "OS Hardening")
		"System"               = @("System", "System Tweaks", "Start Menu", "Start Menu Apps")
		"UI & Personalization" = @("UI & Personalization", "Taskbar", "Taskbar Clock", "Cursors")
		"UWP Apps"             = @("UWP Apps", "OneDrive")
		"Gaming"               = @()
		"Context Menu"         = @()
	}

	# Map manifest categories to primary tabs
	$CategoryToPrimary = @{}
	foreach ($prim in $PrimaryCategories.Keys)
	{
		$subs = $PrimaryCategories[$prim]
		if ($subs.Count -eq 0)
		{
			$CategoryToPrimary[$prim] = $prim
		}
		else
		{
			foreach ($s in $subs) { $CategoryToPrimary[$s] = $prim }
		}
	}
	# Ensure all manifest categories map somewhere
	foreach ($t in $Script:TweakManifest)
	{
		if (-not $CategoryToPrimary.ContainsKey($t.Category))
		{
			$CategoryToPrimary[$t.Category] = $t.Category
		}
	}

	#region Theme colors
	$Script:DarkTheme = @{
		WindowBg      = "#1E1E2E"
		HeaderBg      = "#181825"
		PanelBg       = "#1E1E2E"
		CardBg        = "#272B3A"
		TabBg         = "#2F3445"
		TabActiveBg   = "#223B60"
		TabHoverBg    = "#3B455E"
		BorderColor   = "#4C556D"
		TextPrimary   = "#CDD6F4"
		TextSecondary = "#B6BED8"
		TextMuted     = "#828AA2"
		AccentBlue    = "#89B4FA"
		AccentHover   = "#74C7EC"
		AccentPress   = "#94E2D5"
		FocusRing     = "#C9DEFF"
		CautionBg     = "#3B2028"
		CautionBorder = "#F38BA8"
		CautionText   = "#F38BA8"
		ImpactBadge   = "#F38BA8"
		ImpactBadgeBg = "#3B2028"
		LowRiskBadge     = "#B8E6C1"
		LowRiskBadgeBg   = "#213326"
		RiskMediumBadge   = "#F9E2AF"
		RiskMediumBadgeBg = "#3B3020"
		RiskHighBadge     = "#F38BA8"
		RiskHighBadgeBg   = "#3B2028"
		DestructiveBg = "#C0325A"
		DestructiveHover = "#A6294E"
		SectionLabel  = "#89B4FA"
		ScrollBg      = "#313244"
		ScrollThumb   = "#585B70"
		ToggleOn      = "#A6E3A1"
		ToggleOff     = "#F38BA8"
		StateEnabled  = "#9FD6AA"
		StateDisabled = "#98A0B7"
		SearchBg      = "#313244"
		SearchBorder  = "#585B70"
		SearchPlaceholder = "#8188A0"
		InputBg       = "#313244"
		InputHoverBg  = "#383D52"
		CardBorder    = "#394256"
		CardHoverBg   = "#323A4E"
		SecondaryButtonBg = "#30374A"
		SecondaryButtonHoverBg = "#39415A"
		SecondaryButtonPressBg = "#262D3E"
		SecondaryButtonBorder = "#5F6984"
		SecondaryButtonFg = "#E5EAF7"
		PresetPanelBg = "#23283A"
		PresetPanelBorder = "#52607E"
		StatusPillBg = "#20385C"
		StatusPillBorder = "#5C86C7"
		StatusPillText = "#D6E7FF"
		ActiveTabBorder = "#89B4FA"
	}
	$Script:LightTheme = @{
		WindowBg      = "#E4E8F0"
		HeaderBg      = "#D6DBE5"
		PanelBg       = "#E4E8F0"
		CardBg        = "#FFFFFF"
		TabBg         = "#D4D9E4"
		TabActiveBg   = "#FFFFFF"
		TabHoverBg    = "#EDF2FA"
		BorderColor   = "#A7B0C0"
		TextPrimary   = "#1A1C2E"
		TextSecondary = "#31384A"
		TextMuted     = "#646C7F"
		AccentBlue    = "#1550AA"
		AccentHover   = "#1A60C4"
		AccentPress   = "#104090"
		FocusRing     = "#0D63E0"
		CautionBg     = "#F5D0D0"
		CautionBorder = "#A02040"
		CautionText   = "#A02040"
		ImpactBadge   = "#A02040"
		ImpactBadgeBg = "#F5D0D0"
		LowRiskBadge     = "#245A2D"
		LowRiskBadgeBg   = "#DDEFD9"
		RiskMediumBadge   = "#7A5A00"
		RiskMediumBadgeBg = "#FFF3D0"
		RiskHighBadge     = "#A02040"
		RiskHighBadgeBg   = "#F5D0D0"
		DestructiveBg = "#C0304E"
		DestructiveHover = "#A02840"
		SectionLabel  = "#1550AA"
		ScrollBg      = "#D0D2DE"
		ScrollThumb   = "#A0A2AE"
		ToggleOn      = "#1A7A2A"
		ToggleOff     = "#B02040"
		StateEnabled  = "#2F6E38"
		StateDisabled = "#778096"
		SearchBg      = "#FFFFFF"
		SearchBorder  = "#98A2B4"
		SearchPlaceholder = "#7A8296"
		InputBg       = "#FFFFFF"
		InputHoverBg  = "#F5F8FD"
		CardBorder    = "#B2BBCB"
		CardHoverBg   = "#F2F6FC"
		SecondaryButtonBg = "#FFFFFF"
		SecondaryButtonHoverBg = "#F4F7FC"
		SecondaryButtonPressBg = "#E7EDF8"
		SecondaryButtonBorder = "#98A7BF"
		SecondaryButtonFg = "#263248"
		PresetPanelBg = "#FFFFFF"
		PresetPanelBorder = "#AAB7CC"
		StatusPillBg = "#E6F0FF"
		StatusPillBorder = "#8FAAD8"
		StatusPillText = "#0F4EA8"
		ActiveTabBorder = "#1550AA"
	}

	$Script:GuiThemeFallbackWarnings = [System.Collections.Generic.HashSet[string]]::new()
	$Script:GuiRuntimeWarnings = [System.Collections.Generic.HashSet[string]]::new()

	function Write-GuiThemeFallbackWarning
	{
		param (
			[string]$Context,
			[string]$Message
		)

		if ([string]::IsNullOrWhiteSpace($Message)) { return }
		if ($Message -match 'Encountered an empty color value')
		{
			return
		}

		$warningKey = '{0}|{1}' -f $Context, $Message
		$shouldLog = $true
		if ($Script:GuiThemeFallbackWarnings)
		{
			try { $shouldLog = $Script:GuiThemeFallbackWarnings.Add($warningKey) } catch { $shouldLog = $true }
		}
		if (-not $shouldLog) { return }

		$warningText = "GUI theme fallback [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Message
		if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogWarning $warningText
		}
		else
		{
			Write-Warning $warningText
		}
	}

	function Get-GuiFallbackColor
	{
		param ([string]$FallbackColor)

		if (-not [string]::IsNullOrWhiteSpace($FallbackColor))
		{
			return [string]$FallbackColor
		}

		if ($Script:DarkTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:DarkTheme.AccentBlue))
		{
			return [string]$Script:DarkTheme.AccentBlue
		}

		return '#89B4FA'
	}

	function Repair-GuiThemePalette
	{
		param (
			[hashtable]$Theme,
			[string]$ThemeName = 'Dark'
		)

		$repairedTheme = @{}
		if ($Theme)
		{
			foreach ($key in $Theme.Keys)
			{
				$repairedTheme[$key] = $Theme[$key]
			}
		}

		# Ensure core interactive colors always exist before downstream theme repair runs.
		$defaultColors = @{
			'TabHoverBg' = '#3B455E'
			'TextPrimary' = '#CDD6F4'
			'FocusRing' = '#C9DEFF'
			'AccentBlue' = '#3B82F6'
			'AccentHover' = '#60A5FA'
			'AccentPress' = '#2563EB'
			'HeaderBg' = '#1F2937'
			'TextSecondary' = '#9CA3AF'
		}
		foreach ($key in $defaultColors.Keys)
		{
			if (-not $repairedTheme.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$repairedTheme[$key]))
			{
				$repairedTheme[$key] = $defaultColors[$key]
				Write-GuiThemeFallbackWarning -Context "Repair-GuiThemePalette/$ThemeName" -Message "Added missing color '$key' with $($defaultColors[$key])."
			}
		}

		$primaryTheme = if ($ThemeName -eq 'Light') { $Script:LightTheme } else { $Script:DarkTheme }
		$secondaryTheme = if ($ThemeName -eq 'Light') { $Script:DarkTheme } else { $Script:LightTheme }
		$requiredKeys = [System.Collections.Generic.HashSet[string]]::new()
		foreach ($sourceTheme in @($primaryTheme, $secondaryTheme))
		{
			if (-not $sourceTheme) { continue }
			foreach ($key in $sourceTheme.Keys)
			{
				[void]$requiredKeys.Add([string]$key)
			}
		}

		foreach ($key in $requiredKeys)
		{
			$currentValue = if ($repairedTheme.ContainsKey($key)) { [string]$repairedTheme[$key] } else { $null }
			if (-not [string]::IsNullOrWhiteSpace($currentValue))
			{
				continue
			}

			$fallbackValue = $null
			if ($primaryTheme -and $primaryTheme.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$primaryTheme[$key]))
			{
				$fallbackValue = [string]$primaryTheme[$key]
			}
			elseif ($secondaryTheme -and $secondaryTheme.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$secondaryTheme[$key]))
			{
				$fallbackValue = [string]$secondaryTheme[$key]
			}
			else
			{
				$fallbackValue = '#89B4FA'
			}

			$repairedTheme[$key] = $fallbackValue
			Write-GuiThemeFallbackWarning -Context "Repair-GuiThemePalette/$ThemeName" -Message "Filled missing color '$key' with $fallbackValue."
		}

		return $repairedTheme
	}

	function ConvertTo-GuiBrush
	{
		param (
			[object]$Color,
			[string]$Context = 'GUI',
			[string]$FallbackColor = $null
		)

		$resolvedFallback = if (-not [string]::IsNullOrWhiteSpace([string]$FallbackColor))
		{
			[string]$FallbackColor
		}
		elseif ($Script:DarkTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:DarkTheme.AccentBlue))
		{
			[string]$Script:DarkTheme.AccentBlue
		}
		else
		{
			'#89B4FA'
		}

		$emitThemeWarning = {
			param ([string]$WarningMessage)

			if ([string]::IsNullOrWhiteSpace($WarningMessage)) { return }

			$warningKey = '{0}|{1}' -f $Context, $WarningMessage
			$shouldLog = $true
			if ($Script:GuiThemeFallbackWarnings)
			{
				try { $shouldLog = $Script:GuiThemeFallbackWarnings.Add($warningKey) } catch { $shouldLog = $true }
			}
			if (-not $shouldLog) { return }

			$warningText = "GUI theme fallback [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $WarningMessage
			if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
			{
				LogWarning $warningText
			}
			else
			{
				Write-Warning $warningText
			}
		}.GetNewClosure()

		$resolvedColor = [string]$Color
		if ([string]::IsNullOrWhiteSpace($resolvedColor))
		{
			& $emitThemeWarning "Encountered an empty color value. Using $resolvedFallback."
			$resolvedColor = $resolvedFallback
		}

		$innerConverter = [System.Windows.Media.BrushConverter]::new()
		try
		{
			return $innerConverter.ConvertFromString($resolvedColor)
		}
		catch
		{
			& $emitThemeWarning "Failed to convert '$resolvedColor' ($($_.Exception.Message)). Using $resolvedFallback."
			return $innerConverter.ConvertFromString($resolvedFallback)
		}
	}

	function New-SafeBrushConverter
	{
		param (
			[string]$Context = 'GUI',
			[string]$FallbackColor = $null
		)

		$contextCapture = if ([string]::IsNullOrWhiteSpace($Context)) { 'GUI' } else { $Context }
		$getGuiFallbackColorScript = ${function:Get-GuiFallbackColor}
		$fallbackCapture = & $getGuiFallbackColorScript -FallbackColor $FallbackColor
		$convertBrushScript = ${function:ConvertTo-GuiBrush}
		$converter = [pscustomobject]@{}
		$scriptMethod = {
			param ($Color)
			return (& $convertBrushScript -Color $Color -Context $contextCapture -FallbackColor $fallbackCapture)
		}.GetNewClosure()
		$converter | Add-Member -MemberType ScriptMethod -Name ConvertFromString -Value $scriptMethod
		return $converter
	}

	function Write-GuiRuntimeWarning
	{
		param (
			[string]$Context,
			[string]$Message
		)

		if ([string]::IsNullOrWhiteSpace($Message)) { return }
		if ($Message -match 'Argument types do not match')
		{
			return
		}

		$warningKey = '{0}|{1}' -f $Context, $Message
		$shouldLog = $true
		if ($Script:GuiRuntimeWarnings)
		{
			try { $shouldLog = $Script:GuiRuntimeWarnings.Add($warningKey) } catch { $shouldLog = $true }
		}
		if (-not $shouldLog) { return }

		$warningText = "GUI runtime safeguard [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Message
		if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogWarning $warningText
		}
		else
		{
			Write-Warning $warningText
		}
	}

	function Set-GuiControlProperty
	{
		param (
			[object]$Control,
			[string]$PropertyName,
			[object]$Value,
			[string]$Context = 'GUI'
		)

		if (-not $Control -or [string]::IsNullOrWhiteSpace($PropertyName)) { return $false }

		$property = $null
		try { $property = $Control.PSObject.Properties[$PropertyName] } catch { $property = $null }
		if (-not $property)
		{
			return $false
		}

		try
		{
			$Control.$PropertyName = $Value
			return $true
		}
		catch
		{
			if ($_.Exception.Message -notlike '*Argument types do not match*')
			{
				$warningMessage = "Failed to set property '{0}' on {1}: {2}" -f `
					$PropertyName, `
					$(try { $Control.GetType().Name } catch { 'unknown' }), `
					$_.Exception.Message

				$warningKey = '{0}|{1}' -f $Context, $warningMessage
				$shouldLog = $true
				if ($Script:GuiRuntimeWarnings)
				{
					try { $shouldLog = $Script:GuiRuntimeWarnings.Add($warningKey) } catch { $shouldLog = $true }
				}
				if ($shouldLog)
				{
					$warningText = "GUI runtime safeguard [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $warningMessage
					if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
					{
						LogWarning $warningText
					}
					else
					{
						Write-Warning $warningText
					}
				}
			}
			return $false
		}
	}

	function Show-GuiRuntimeFailure
	{
		param (
			[string]$Context = 'GUI',
			[System.Exception]$Exception,
			[switch]$ShowDialog
		)

		if (-not $Exception) { return $null }

		$errorLines = New-Object System.Collections.Generic.List[string]
		[void]$errorLines.Add(("GUI event failed [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Exception.Message))
		[void]$errorLines.Add(("Exception type: {0}" -f $Exception.GetType().FullName))
		if ($Exception.InnerException)
		{
			[void]$errorLines.Add(("Inner exception: {0}" -f $Exception.InnerException.Message))
		}
		if ($Exception.StackTrace)
		{
			[void]$errorLines.Add('Stack trace:')
			[void]$errorLines.Add($Exception.StackTrace.Trim())
		}

		if ($Script:GuiPresetDebugTrail -and $Script:GuiPresetDebugTrail.Count -gt 0)
		{
			[void]$errorLines.Add('')
			[void]$errorLines.Add('Preset debug trail (most recent entries):')
			$startIndex = [Math]::Max(0, $Script:GuiPresetDebugTrail.Count - 15)
			for ($i = $startIndex; $i -lt $Script:GuiPresetDebugTrail.Count; $i++)
			{
				[void]$errorLines.Add($Script:GuiPresetDebugTrail[$i])
			}
		}

		$errorText = ($errorLines -join [Environment]::NewLine)
		if (Get-Command -Name 'LogError' -CommandType Function -ErrorAction SilentlyContinue)
		{
			LogError $errorText
		}
		else
		{
			Write-Warning $errorText
		}

		if ($ShowDialog -and $Script:MainForm)
		{
			try
			{
				Show-ThemedDialog -Title 'GUI Error' -Message $errorText -Buttons @('OK') -AccentButton 'OK' | Out-Null
			}
			catch
			{
				$null = $_
			}
		}

		return $errorText
	}

	function Invoke-GuiSafeAction
	{
		param (
			[scriptblock]$Action,
			[string]$Context = 'GUI',
			[switch]$ShowDialog
		)

		if (-not $Action) { return }

		try
		{
			& $Action
		}
		catch
		{
			$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
			if ($showGuiRuntimeFailureScript)
			{
				$null = & $showGuiRuntimeFailureScript -Context $Context -Exception $_.Exception -ShowDialog:$ShowDialog
			}
			else
			{
				Write-Warning ("GUI event failed [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $_.Exception.Message)
			}
		}
	}

	$Script:ShowGuiRuntimeFailureScript = ${function:Show-GuiRuntimeFailure}

	$Script:DarkTheme = Repair-GuiThemePalette -Theme $Script:DarkTheme -ThemeName 'Dark'
	$Script:LightTheme = Repair-GuiThemePalette -Theme $Script:LightTheme -ThemeName 'Light'
	$Script:CurrentTheme = $Script:DarkTheme
	#endregion Theme colors

	function Set-ButtonChrome
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Button]$Button,
			[ValidateSet('Primary', 'Danger', 'Secondary', 'Subtle')]
			[string]$Variant = 'Secondary',
			[switch]$Compact,
			[switch]$Muted
		)

		if (-not $Button) { return }

		$bc = New-SafeBrushConverter -Context 'Set-ButtonChrome'
		$theme = $Script:CurrentTheme
		$getSafeColor = {
			param (
				[string]$ColorName,
				[string]$DefaultColor
			)

			if (-not $theme) { return $DefaultColor }

			$color = if ($theme.ContainsKey($ColorName)) { [string]$theme[$ColorName] } else { $null }
			if ([string]::IsNullOrWhiteSpace($color))
			{
				return $DefaultColor
			}

			return $color
		}.GetNewClosure()
		switch ($Variant)
		{
			'Primary'
			{
				$normalBg     = & $getSafeColor -ColorName 'AccentBlue' -DefaultColor '#3B82F6'
				$hoverBg      = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$pressBg      = & $getSafeColor -ColorName 'AccentPress' -DefaultColor '#2563EB'
				$normalBorder = & $getSafeColor -ColorName 'AccentHover' -DefaultColor '#60A5FA'
				$foreground   = & $getSafeColor -ColorName 'HeaderBg' -DefaultColor '#1F2937'
			}
			'Danger'
			{
				$normalBg     = & $getSafeColor -ColorName 'DestructiveBg' -DefaultColor '#C0325A'
				$hoverBg      = & $getSafeColor -ColorName 'DestructiveHover' -DefaultColor '#A6294E'
				$pressBg      = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
				$normalBorder = & $getSafeColor -ColorName 'CautionBorder' -DefaultColor '#F38BA8'
				$foreground   = '#FFFFFF'
			}
			'Subtle'
			{
				$normalBg     = & $getSafeColor -ColorName 'TabBg' -DefaultColor '#2F3445'
				$hoverBg      = & $getSafeColor -ColorName 'TabHoverBg' -DefaultColor '#3B455E'
				$pressBg      = & $getSafeColor -ColorName 'TabActiveBg' -DefaultColor '#223B60'
				$normalBorder = & $getSafeColor -ColorName 'BorderColor' -DefaultColor '#4C556D'
				$foreground   = if ($Muted) {
					& $getSafeColor -ColorName 'TextSecondary' -DefaultColor '#9CA3AF'
				} else {
					& $getSafeColor -ColorName 'TextPrimary' -DefaultColor '#CDD6F4'
				}
			}
			default
			{
				$normalBg     = & $getSafeColor -ColorName 'SecondaryButtonBg' -DefaultColor '#30374A'
				$hoverBg      = & $getSafeColor -ColorName 'SecondaryButtonHoverBg' -DefaultColor '#39415A'
				$pressBg      = & $getSafeColor -ColorName 'SecondaryButtonPressBg' -DefaultColor '#262D3E'
				$normalBorder = & $getSafeColor -ColorName 'SecondaryButtonBorder' -DefaultColor '#5F6984'
				$foreground   = & $getSafeColor -ColorName 'SecondaryButtonFg' -DefaultColor '#E5EAF7'
			}
		}

		$cornerRadius = if ($Compact) { 5 } else { 6 }
		$paddingValue = if ($Button.Padding -and ($Button.Padding.Left -ne 0 -or $Button.Padding.Top -ne 0 -or $Button.Padding.Right -ne 0 -or $Button.Padding.Bottom -ne 0)) {
			$Button.Padding
		} elseif ($Compact) {
			[System.Windows.Thickness]::new(10, 4, 10, 4)
		} else {
			[System.Windows.Thickness]::new(12, 6, 12, 6)
		}

		$normalBgBrush = $bc.ConvertFromString($normalBg)
		$hoverBgBrush = $bc.ConvertFromString($hoverBg)
		$pressBgBrush = $bc.ConvertFromString($pressBg)
		$normalBorderBrush = $bc.ConvertFromString($normalBorder)
		$focusBorderBrush = $bc.ConvertFromString((& $getSafeColor -ColorName 'FocusRing' -DefaultColor '#C9DEFF'))
		$foregroundBrush = $bc.ConvertFromString($foreground)

		$Button.Foreground = $foregroundBrush
		$Button.Background = $normalBgBrush
		$Button.BorderBrush = $normalBorderBrush
		$Button.BorderThickness = New-SafeThickness -Uniform 1
		$Button.FocusVisualStyle = $null
		$Button.Cursor = [System.Windows.Input.Cursors]::Hand
		$Button.Template = $null

		$tmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
		$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$bd.Name = 'Bd'
		$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new($cornerRadius))
		$bd.SetValue([System.Windows.Controls.Border]::PaddingProperty, $paddingValue)
		$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $normalBgBrush)
		$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $normalBorderBrush)
		$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, (New-SafeThickness -Uniform 1))
		$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
		$bd.AppendChild($cp)
		$tmpl.VisualTree = $bd

		$hoverTrigger = New-Object System.Windows.Trigger
		$hoverTrigger.Property = [System.Windows.UIElement]::IsMouseOverProperty
		$hoverTrigger.Value = $true
		$hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $hoverBgBrush -TargetName 'Bd')) | Out-Null
		$hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')) | Out-Null
		$tmpl.Triggers.Add($hoverTrigger) | Out-Null

		$focusTrigger = New-Object System.Windows.Trigger
		$focusTrigger.Property = [System.Windows.UIElement]::IsKeyboardFocusedProperty
		$focusTrigger.Value = $true
		$focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')) | Out-Null
		$focusTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderThicknessProperty) -Value (New-SafeThickness -Uniform 2) -TargetName 'Bd')) | Out-Null
		$tmpl.Triggers.Add($focusTrigger) | Out-Null

		$pressTrigger = New-Object System.Windows.Trigger
		$pressTrigger.Property = [System.Windows.Controls.Primitives.ButtonBase]::IsPressedProperty
		$pressTrigger.Value = $true
		$pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BackgroundProperty) -Value $pressBgBrush -TargetName 'Bd')) | Out-Null
		$pressTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::BorderBrushProperty) -Value $focusBorderBrush -TargetName 'Bd')) | Out-Null
		$tmpl.Triggers.Add($pressTrigger) | Out-Null

		$disabledTrigger = New-Object System.Windows.Trigger
		$disabledTrigger.Property = [System.Windows.UIElement]::IsEnabledProperty
		$disabledTrigger.Value = $false
		$disabledTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Border]::OpacityProperty) -Value 0.55 -TargetName 'Bd')) | Out-Null
		$tmpl.Triggers.Add($disabledTrigger) | Out-Null

		$Button.Template = $tmpl
	}

	function Set-HeaderToggleStyle
	{
		param ([System.Windows.Controls.CheckBox]$CheckBox)

		if (-not $CheckBox) { return }

		$theme = $Script:CurrentTheme

		# Helper to ensure a color is a valid hex string
		$ensureHexColor = {
			param($Color, $Default = '#89B4FA')
			if ([string]::IsNullOrWhiteSpace($Color)) { return $Default }
			if ($Color -match '^#[0-9A-Fa-f]{6}$|^#[0-9A-Fa-f]{8}$') { return $Color }
			return $Default
		}

		$trackOffBg   = & $ensureHexColor $theme.SearchBorder   '#6B7280'
		$trackOffBorder = & $ensureHexColor $theme.BorderColor  '#6B7280'
		$trackOnBg    = & $ensureHexColor $theme.AccentBlue     '#3B82F6'
		$trackOnBorder = & $ensureHexColor $theme.ActiveTabBorder '#3B82F6'
		$thumbFill    = '#FFFFFF'
		$hoverBorder  = & $ensureHexColor $theme.AccentHover    '#60A5FA'
		$focusBorder  = & $ensureHexColor $theme.FocusRing      '#C9DEFF'

		if (-not $Script:HeaderToggleTemplate -or $Script:HeaderToggleTemplateTheme -ne $Script:CurrentThemeName)
		{
			$templateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type CheckBox}">
    <Grid SnapsToDevicePixels="True">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <Border x:Name="SwitchTrack"
                Width="42"
                Height="24"
                CornerRadius="12"
                Background="$trackOffBg"
                BorderBrush="$trackOffBorder"
                BorderThickness="1"
                VerticalAlignment="Center">
            <Grid Margin="2">
                <Ellipse x:Name="SwitchThumb"
                         Width="18"
                         Height="18"
                         Fill="$thumbFill"
                         HorizontalAlignment="Left"
                         VerticalAlignment="Center" />
            </Grid>
        </Border>

        <ContentPresenter Grid.Column="1"
                          Margin="10,0,0,0"
                          VerticalAlignment="Center"
                          RecognizesAccessKey="True"
                          ContentSource="Content" />
    </Grid>

    <ControlTemplate.Triggers>
        <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="SwitchTrack" Property="Background" Value="$trackOnBg" />
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$trackOnBorder" />
            <Setter TargetName="SwitchThumb" Property="HorizontalAlignment" Value="Right" />
        </Trigger>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$hoverBorder" />
        </Trigger>
        <Trigger Property="IsKeyboardFocused" Value="True">
            <Setter TargetName="SwitchTrack" Property="BorderBrush" Value="$focusBorder" />
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="SwitchTrack" Property="Opacity" Value="0.55" />
            <Setter Property="Opacity" Value="0.65" />
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
			try {
				$templateReader = New-Object System.Xml.XmlNodeReader ([xml]$templateXaml)
				$Script:HeaderToggleTemplate = [System.Windows.Markup.XamlReader]::Load($templateReader)
				$Script:HeaderToggleTemplateTheme = $Script:CurrentThemeName
			}
			catch {
				# Silently ignore XAML errors
				return
			}
		}

		try {
			$bc = New-SafeBrushConverter -Context 'Set-HeaderToggleStyle'
			$CheckBox.Template = $Script:HeaderToggleTemplate
			$CheckBox.Cursor = [System.Windows.Input.Cursors]::Hand
			$CheckBox.FocusVisualStyle = $null
			$CheckBox.Background = [System.Windows.Media.Brushes]::Transparent
			$CheckBox.BorderBrush = [System.Windows.Media.Brushes]::Transparent
			$CheckBox.BorderThickness = [System.Windows.Thickness]::new(0)
			$CheckBox.Padding = [System.Windows.Thickness]::new(0)
			$CheckBox.Margin = [System.Windows.Thickness]::new(0)
			$CheckBox.MinHeight = 24
			$CheckBox.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center
			$CheckBox.Foreground = $bc.ConvertFromString($theme.TextSecondary)
		}
		catch {
			# Silent fallback
		}
	}

	function Set-HeaderToggleControlsStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if ($ChkAdvancedMode) { Set-HeaderToggleStyle -CheckBox $ChkAdvancedMode }
		if ($ChkTheme) { Set-HeaderToggleStyle -CheckBox $ChkTheme }
	}

	#region Themed Dialog
	function Show-ThemedDialog
	{
		param(
			[string]$Title,
			[string]$Message,
			[string[]]$Buttons = @('OK'),
			[string]$AccentButton = $null,
			[string]$DestructiveButton = $null
		)

		return (GUICommon\Show-ThemedDialog `
			-Theme $Script:CurrentTheme `
			-ApplyButtonChrome ${function:Set-ButtonChrome} `
			-OwnerWindow $Form `
			-Title $Title `
			-Message $Message `
			-Buttons $Buttons `
			-AccentButton $AccentButton `
			-DestructiveButton $DestructiveButton)
	}

	function Show-ExecutionSummaryDialog
	{
		param(
			[object[]]$Results,
			[string]$Title = 'Execution Summary',
			[string]$SummaryText,
			[string]$LogPath,
			[string[]]$Buttons = @('Close')
		)

		return (GUICommon\Show-ExecutionSummaryDialog `
			-Theme $Script:CurrentTheme `
			-ApplyButtonChrome ${function:Set-ButtonChrome} `
			-OwnerWindow $Form `
			-Results $Results `
			-Title $Title `
			-SummaryText $SummaryText `
			-LogPath $LogPath `
			-Buttons $Buttons)
	}

	function Show-HelpDialog
	{
		$theme = $Script:CurrentTheme
		$bc = [System.Windows.Media.BrushConverter]::new()

		$sections = [ordered]@{
			'Getting Started' = @(
				'The GUI opens with all tweaks unselected.'
				'Select tweaks manually or click a preset button to populate the current selection.'
				'Preset buttons do not run anything by themselves.'
			)
			'Presets' = @(
				'Minimal, Safe, Balanced, and Aggressive load selections from their matching preset files.'
				'Clicking a preset replaces any previously loaded preset selection - selections do not stack.'
				'Presets only update the GUI selection. They do not execute changes.'
				'Run Tweaks applies the current GUI selection.'
			)
			'Preview Run' = @(
				'Preview Run shows what would execute from the current selection without applying any changes.'
			)
			'Run Tweaks' = @(
				'Run Tweaks executes only the items currently selected in the GUI.'
				'Expected result states per tweak: Success, Failed, Skipped, Already Applied.'
			)
			'Risk Levels' = @(
				'Low Risk: generally safe usability and quality-of-life changes.'
				'Medium Risk: may affect behavior, compatibility, networking, or security posture.'
				'High Risk: may reduce compatibility, disable features, or be difficult to reverse.'
				'Restart Required badge: the tweak requires a system restart to take full effect.'
			)
			'Restore to Windows Defaults' = @(
				'Restores supported default values only.'
				'Does not guarantee that every previous change can be undone.'
				'Some destructive or one-way actions are not fully restorable.'
			)
			'Advanced Mode' = @(
				'Advanced Mode reveals high-risk and advanced tweaks hidden by default.'
				'Use it only if you understand the impact of the settings being changed.'
			)
			'System Scan' = @(
				'System Scan checks the current system state and refreshes supported tweak states in the GUI.'
			)
			'Import / Export / Session Restore' = @(
				'Export Settings saves the current GUI selection to a file.'
				'Import Settings restores a saved selection into the GUI for review before execution.'
				'Restore Snapshot restores the last captured GUI state only. It does not execute tweaks.'
			)
			'Logs and Troubleshooting' = @(
				'Open Log opens the current session log for troubleshooting.'
				'If a preset line cannot be matched to a tweak it will be reported in the log.'
				'If a tweak fails, review the log and the execution summary for details.'
			)
		}

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Help"
	Width="580" Height="620"
	MinWidth="420" MinHeight="400"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResize"
	Background="$($theme.WindowBg)"
	BorderBrush="$($theme.BorderColor)"
	BorderThickness="1">
	<Window.Resources>
		<Style TargetType="ScrollBar">
			<Setter Property="Background" Value="$($theme.ScrollBg)"/>
			<Setter Property="Width" Value="6"/>
		</Style>
	</Window.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Grid.Row="0" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<StackPanel>
				<TextBlock Text="Help" FontSize="16" FontWeight="SemiBold"
						   Foreground="$($theme.TextPrimary)"/>
				<TextBlock Text="Baseline - usage guide"
						   FontSize="12" Foreground="$($theme.TextMuted)" Margin="0,2,0,0"/>
			</StackPanel>
		</Border>

		<ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Disabled"
					  Padding="0,0,4,0">
			<StackPanel Name="ContentPanel" Margin="20,16,20,16"/>
		</ScrollViewer>

		<Border Grid.Row="2" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Button Name="BtnClose" Content="Close"
						HorizontalAlignment="Right"
						Padding="20,6" FontSize="13"/>
			</Grid>
		</Border>
	</Grid>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		$panel = $dlg.FindName('ContentPanel')
		$btnClose = $dlg.FindName('BtnClose')

		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact

		foreach ($sectionTitle in $sections.Keys)
		{
			$heading = [System.Windows.Controls.TextBlock]::new()
			$heading.Text = $sectionTitle
			$heading.FontSize = 12
			$heading.FontWeight = [System.Windows.FontWeights]::SemiBold
			$heading.Foreground = $bc.ConvertFromString($theme.AccentBlue)
			$heading.Margin = [System.Windows.Thickness]::new(0, 12, 0, 4)
			$panel.Children.Add($heading) | Out-Null

			$sep = [System.Windows.Controls.Separator]::new()
			$sep.Background = $bc.ConvertFromString($theme.BorderColor)
			$sep.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
			$panel.Children.Add($sep) | Out-Null

			foreach ($line in $sections[$sectionTitle])
			{
				$row = [System.Windows.Controls.Grid]::new()
				$col1 = [System.Windows.Controls.ColumnDefinition]::new()
				$col1.Width = [System.Windows.GridLength]::new(14)
				$col2 = [System.Windows.Controls.ColumnDefinition]::new()
				$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				$row.ColumnDefinitions.Add($col1) | Out-Null
				$row.ColumnDefinitions.Add($col2) | Out-Null
				$row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

				$bullet = [System.Windows.Controls.TextBlock]::new()
				$bullet.Text = [char]0x2022
				$bullet.FontSize = 12
				$bullet.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$bullet.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
				[System.Windows.Controls.Grid]::SetColumn($bullet, 0)

				$text = [System.Windows.Controls.TextBlock]::new()
				$text.Text = $line
				$text.FontSize = 12
				$text.Foreground = $bc.ConvertFromString($theme.TextSecondary)
				$text.TextWrapping = [System.Windows.TextWrapping]::Wrap
				[System.Windows.Controls.Grid]::SetColumn($text, 1)

				$row.Children.Add($bullet) | Out-Null
				$row.Children.Add($text) | Out-Null
				$panel.Children.Add($row) | Out-Null
			}
		}

		$btnClose.Add_Click({ $dlg.Close() })
		$dlg.Add_KeyDown({
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		$dlg.ShowDialog() | Out-Null
	}

	function Show-LogDialog
	{
		param([string]$LogPath)

		$theme = $Script:CurrentTheme
		$bc = [System.Windows.Media.BrushConverter]::new()

		[xml]$xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="Log Viewer"
	Width="780" Height="640"
	MinWidth="500" MinHeight="300"
	WindowStartupLocation="CenterOwner"
	ResizeMode="CanResize"
	Background="$($theme.WindowBg)"
	BorderBrush="$($theme.BorderColor)"
	BorderThickness="1">
	<Window.Resources>
		<Style TargetType="ScrollBar">
			<Setter Property="Background" Value="$($theme.ScrollBg)"/>
			<Setter Property="Width" Value="6"/>
		</Style>
	</Window.Resources>
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>

		<Border Grid.Row="0" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,0,0,1"
				Padding="20,14,20,14">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0">
					<TextBlock Text="Log Viewer" FontSize="16" FontWeight="SemiBold"
							   Foreground="$($theme.TextPrimary)"/>
					<TextBlock Name="TxtLogPath" FontSize="11"
							   Foreground="$($theme.TextMuted)" Margin="0,2,0,0"
							   TextTrimming="CharacterEllipsis"/>
				</StackPanel>
				<StackPanel Grid.Column="1" Orientation="Horizontal"
							VerticalAlignment="Center" HorizontalAlignment="Right">
					<Button Name="BtnRefresh" Content="Refresh" Margin="0,0,8,0"
							Padding="12,5" FontSize="12"/>
					<Button Name="BtnOpenExternal" Content="Open in Notepad"
							Padding="12,5" FontSize="12"/>
				</StackPanel>
			</Grid>
		</Border>

		<ScrollViewer Name="LogScroll" Grid.Row="1"
					  VerticalScrollBarVisibility="Auto"
					  HorizontalScrollBarVisibility="Auto"
					  Background="$($theme.SearchBg)"
					  Padding="0,0,4,0">
			<StackPanel Name="LogPanel" Margin="16,12,16,12"/>
		</ScrollViewer>

		<Border Grid.Row="2" Background="$($theme.HeaderBg)"
				BorderBrush="$($theme.BorderColor)" BorderThickness="0,1,0,0"
				Padding="20,10,20,10">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
					<Ellipse Width="8" Height="8" Fill="$($theme.LowRiskBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="success" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskHighBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="failed" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.RiskMediumBadge)" Margin="0,0,5,0"/>
					<TextBlock Text="skipped / warning" FontSize="11" Foreground="$($theme.TextMuted)" Margin="0,0,14,0"/>
					<Ellipse Width="8" Height="8" Fill="$($theme.TextMuted)" Margin="0,0,5,0"/>
					<TextBlock Text="info" FontSize="11" Foreground="$($theme.TextMuted)"/>
				</StackPanel>
				<Button Name="BtnClose" Grid.Column="1" Content="Close"
						Padding="20,6" FontSize="13"/>
			</Grid>
		</Border>
	</Grid>
</Window>
"@

		$reader = [System.Xml.XmlNodeReader]::new($xaml)
		$dlg = [Windows.Markup.XamlReader]::Load($reader)
		$dlg.Owner = $Form

		$logPanel = $dlg.FindName('LogPanel')
		$logScroll = $dlg.FindName('LogScroll')
		$txtLogPath = $dlg.FindName('TxtLogPath')
		$btnClose = $dlg.FindName('BtnClose')
		$btnRefresh = $dlg.FindName('BtnRefresh')
		$btnExternal = $dlg.FindName('BtnOpenExternal')

		Set-ButtonChrome -Button $btnClose -Variant 'Primary' -Compact
		Set-ButtonChrome -Button $btnRefresh -Variant 'Subtle' -Compact -Muted
		Set-ButtonChrome -Button $btnExternal -Variant 'Subtle' -Compact -Muted

		$txtLogPath.Text = $LogPath

		$colorRules = @(
			@{ Pattern = '- success[!]?$';          Color = $theme.LowRiskBadge    }
			@{ Pattern = '- failed[!]?$';           Color = $theme.RiskHighBadge   }
			@{ Pattern = '- skipped[.]?$';          Color = $theme.RiskMediumBadge }
			@{ Pattern = '- already applied[.]?$';  Color = $theme.AccentBlue      }
			@{ Pattern = '\bERROR\b|\bFAIL\b';      Color = $theme.RiskHighBadge   }
			@{ Pattern = '\bWARN\b|\bWARNING\b';    Color = $theme.RiskMediumBadge }
			@{ Pattern = '^={3}';                   Color = $theme.AccentBlue      }
		)

		$loadLogContent = {
			$logPanel.Children.Clear()

			if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = "Log file not found:`n$LogPath"
				$tb.FontSize = 12
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				$logPanel.Children.Add($tb) | Out-Null
				return
			}

			try
			{
				$lines = [System.IO.File]::ReadAllLines($LogPath)
			}
			catch
			{
				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = "Failed to read log file: $($_.Exception.Message)"
				$tb.FontSize = 12
				$tb.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
				$logPanel.Children.Add($tb) | Out-Null
				return
			}

			foreach ($line in $lines)
			{
				$color = $theme.TextSecondary
				foreach ($rule in $colorRules)
				{
					if ($line -match $rule.Pattern)
					{
						$color = $rule.Color
						break
					}
				}

				$tb = [System.Windows.Controls.TextBlock]::new()
				$tb.Text = $line
				$tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas, Courier New')
				$tb.FontSize = 11
				$tb.Foreground = $bc.ConvertFromString($color)
				$tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
				$tb.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
				$logPanel.Children.Add($tb) | Out-Null
			}

			$logScroll.ScrollToEnd()
		}.GetNewClosure()

		& $loadLogContent

		$btnClose.Add_Click({ $dlg.Close() })
		$btnRefresh.Add_Click({
			& $loadLogContent
			$txtLogPath.Text = $LogPath
		}.GetNewClosure())
		$btnExternal.Add_Click({
			if ($LogPath -and (Test-Path -LiteralPath $LogPath -ErrorAction SilentlyContinue))
			{
				Start-Process -FilePath 'notepad.exe' -ArgumentList $LogPath -ErrorAction SilentlyContinue
			}
		}.GetNewClosure())
		$dlg.Add_KeyDown({
			param($s, $e)
			if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $dlg.Close() }
		})

		$dlg.ShowDialog() | Out-Null
	}
	#endregion Themed Dialog

	# 980x640 keeps the header actions, filter row, primary tabs, and bottom
	# action strip readable without controls crowding into each other.
	$guiWindowMinWidth = 980
	$guiWindowMinHeight = 640

	#region XAML template
	[xml]$XAML = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Name="MainWindow"
	Title="Baseline | Windows Utility - Windows Optimization &amp; Hardening"
	MinWidth="$guiWindowMinWidth" MinHeight="$guiWindowMinHeight"
	WindowStartupLocation="CenterScreen"
	FontFamily="Segoe UI" FontSize="13"
	ShowInTaskbar="True">
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<!-- Header -->
		<Border Name="HeaderBorder" Grid.Row="0" Padding="16,10">
			<Grid>
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>
				<Grid Grid.Row="0">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<TextBlock Name="TitleText" Grid.Column="0"
						FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
					<Button Name="BtnHelp" Grid.Column="1" Content="Help"
						FontSize="11" Margin="0,0,12,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
					<Button Name="BtnLog" Grid.Column="2" Content="Open Log"
						FontSize="11" Margin="0,0,12,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
					<StackPanel Grid.Column="3" Orientation="Horizontal" Margin="0,0,12,0" VerticalAlignment="Center" Visibility="Collapsed">
						<TextBlock Text="System Scan" VerticalAlignment="Center" Margin="0,0,6,0"
							Name="ScanLabel" FontSize="11"/>
						<CheckBox Name="ChkScan" VerticalAlignment="Center"/>
					</StackPanel>
					<StackPanel Grid.Column="4" Orientation="Horizontal" Margin="0,0,12,0" VerticalAlignment="Center">
						<CheckBox Name="ChkAdvancedMode" VerticalAlignment="Center" Content="Advanced Mode"/>
					</StackPanel>
					<StackPanel Grid.Column="5" Orientation="Horizontal" VerticalAlignment="Center">
						<CheckBox Name="ChkTheme" VerticalAlignment="Center" Content="Light Mode"/>
					</StackPanel>
				</Grid>
				<Grid Grid.Row="1" Margin="0,10,0,0">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<TextBlock Name="SearchLabel" Grid.Column="0" Text="Quick Filter" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
					<Grid Grid.Column="1" Margin="0,0,8,0">
						<TextBox Name="TxtSearch" Height="30" Padding="10,4" VerticalContentAlignment="Center"/>
						<TextBlock Name="TxtSearchPlaceholder" Text="Filter by name, tag, or category..."
							Margin="12,0,36,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
					</Grid>
					<Button Name="BtnClearSearch" Grid.Column="2" Content="Clear" FontSize="11" Padding="12,4" Cursor="Hand" Height="30"/>
				</Grid>
				<WrapPanel Grid.Row="2" Margin="0,8,0,0" Orientation="Horizontal" VerticalAlignment="Center">
					<TextBlock Name="RiskFilterLabel" Text="Risk" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
					<ComboBox Name="CmbRiskFilter" Width="138" Height="30" Margin="0,0,16,0" VerticalContentAlignment="Center"/>
					<TextBlock Name="CategoryFilterLabel" Text="Category" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
					<ComboBox Name="CmbCategoryFilter" Width="220" Height="30" VerticalContentAlignment="Center"/>
				</WrapPanel>
			</Grid>
		</Border>
		<!-- Primary tab bar -->
		<TabControl Name="PrimaryTabs" Grid.Row="1"
			Margin="8,4,8,0" Padding="2"/>
		<!-- Content area (filled by tab selection) -->
		<Border Name="ContentBorder" Grid.Row="2" Margin="8,0,8,0">
			<ScrollViewer Name="ContentScroll" VerticalScrollBarVisibility="Auto"
				HorizontalScrollBarVisibility="Disabled"/>
		</Border>
		<!-- Bottom bar -->
		<Border Name="BottomBorder" Grid.Row="3" Padding="8">
			<Grid>
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<WrapPanel Name="ActionButtonBar" Grid.Column="0" Margin="0,0,8,0"
					VerticalAlignment="Center" HorizontalAlignment="Left">
					<Button Name="BtnDefaults" Content="Restore to Windows Defaults"
						FontSize="13" Margin="4" Padding="16,8" Cursor="Hand"/>
				</WrapPanel>
				<TextBlock Name="StatusText" Grid.Column="1" VerticalAlignment="Center"
					FontSize="12" Margin="8,0" TextWrapping="Wrap"/>
				<StackPanel Name="BottomActionBar" Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right">
					<Button Name="BtnPreviewRun" Content="Preview Run"
						FontSize="12" Margin="4" Padding="16,10" Cursor="Hand" FontWeight="SemiBold"/>
					<Button Name="BtnRun" Content="Run Tweaks"
						FontSize="14" Margin="4" Padding="24,10" Cursor="Hand" FontWeight="Bold"/>
				</StackPanel>
			</Grid>
		</Border>
	</Grid>
</Window>
"@
	#endregion XAML template

	$Form = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XAML))
	$Script:MainForm = $Form

	# Size the window to 85% of the screen working area so it fits any resolution
	# without being full-screen. Falls back to safe defaults if the call fails.
	try
	{
		$workArea = [System.Windows.SystemParameters]::WorkArea
		$targetW  = [Math]::Round($workArea.Width  * 0.85)
		$targetH  = [Math]::Round($workArea.Height * 0.85)
		$Form.MinWidth = $guiWindowMinWidth
		$Form.MinHeight = $guiWindowMinHeight
		$Form.Width  = [Math]::Max($targetW, $guiWindowMinWidth)
		$Form.Height = [Math]::Max($targetH, $guiWindowMinHeight)
	}
	catch
	{
		$Form.MinWidth = $guiWindowMinWidth
		$Form.MinHeight = $guiWindowMinHeight
		$Form.Width  = [Math]::Max(1100, $guiWindowMinWidth)
		$Form.Height = [Math]::Max(720, $guiWindowMinHeight)
	}
	$HeaderBorder  = $Form.FindName("HeaderBorder")
	$TitleText     = $Form.FindName("TitleText")
	$PrimaryTabs   = $Form.FindName("PrimaryTabs")
	$ContentBorder = $Form.FindName("ContentBorder")
	$ContentScroll = $Form.FindName("ContentScroll")
	$BottomBorder  = $Form.FindName("BottomBorder")
	$StatusText    = $Form.FindName("StatusText")
	$ActionButtonBar = $Form.FindName("ActionButtonBar")
	$BtnPreviewRun = $Form.FindName("BtnPreviewRun")
	$BtnRun        = $Form.FindName("BtnRun")
	$BtnDefaults   = $Form.FindName("BtnDefaults")
	$BtnExportSettings = $null
	$BtnImportSettings = $null
	$BtnRestoreSnapshot = $null
	$ChkTheme      = $Form.FindName("ChkTheme")
	$ChkAdvancedMode = $Form.FindName("ChkAdvancedMode")
	$BtnHelp       = $Form.FindName("BtnHelp")
	$BtnLog        = $Form.FindName("BtnLog")
	$ChkScan       = $Form.FindName("ChkScan")
	$ScanLabel     = $Form.FindName("ScanLabel")
	$SearchLabel   = $Form.FindName("SearchLabel")
	$TxtSearch     = $Form.FindName("TxtSearch")
	$TxtSearchPlaceholder = $Form.FindName("TxtSearchPlaceholder")
	$BtnClearSearch = $Form.FindName("BtnClearSearch")
	$RiskFilterLabel = $Form.FindName("RiskFilterLabel")
	$CategoryFilterLabel = $Form.FindName("CategoryFilterLabel")
	$CmbRiskFilter = $Form.FindName("CmbRiskFilter")
	$CmbCategoryFilter = $Form.FindName("CmbCategoryFilter")
	$Script:ExecutionLogBox = $null
	$Script:ExecutionPreviousContent = $null
	$Script:ExecutionLastConsoleAction = $null
	$Script:ExecutionProgressBar = $null
	$Script:ExecutionProgressText = $null
	$Script:ExecutionProgressIndeterminate = $false
	$Script:ExecutionSubProgressBar = $null
	$Script:ExecutionSubProgressText = $null
	$Script:AbortRunButton = $null
	$Script:AbortRequested = $false
	$Script:ExecutionWorker = $null
	$Script:ExecutionRunspace = $null
	$Script:ExecutionRunPowerShell = $null
		$Script:ExecutionRunTimer = $null
		$Script:RunAbortDisposition = $null
		$Script:ExecutionMode = $null
		$Script:SuppressRunClosePrompt = $false
		$Script:ExecutionTimerErrorShown = $false
	$Script:AbortDialogShowing = $false
	$Script:BgPS = $null
	$Script:BgAsync = $null
	$Script:SearchText = ''
	$Script:SearchResultsTabTag = '__SEARCH_RESULTS__'
	$Script:LastStandardPrimaryTab = $null
	$Script:TabScrollOffsets = @{}
	$Script:CurrentThemeName = 'Dark'
	$Script:UiSnapshotUndo = $null
	$Script:PresetStatusMessage = $null
	$Script:PresetStatusTone = 'info'
	$Script:PresetStatusBadge = $null
	$Script:SecondaryActionGroupBorder = $null
	$Script:GuiUnhandledExceptionHooked = $false
	$Script:GuiUnhandledExceptionHandler = $null
	$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
		[System.StringComparer]::OrdinalIgnoreCase
	)

	if (-not $Script:GuiUnhandledExceptionHooked -and $Form -and $Form.Dispatcher)
	{
		$Script:GuiUnhandledExceptionHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
			param($unusedSender, $e)

			try
			{
				$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript
				if ($showGuiRuntimeFailureScript)
				{
					$null = & $showGuiRuntimeFailureScript -Context 'WPF Dispatcher' -Exception $e.Exception -ShowDialog
				}
				else
				{
					Write-Warning ("GUI event failed [WPF Dispatcher]: {0}" -f $e.Exception.Message)
				}
			}
			catch
			{
				$null = $_
			}

			$e.Handled = $true
		}

		try
		{
			$Form.Dispatcher.add_UnhandledException($Script:GuiUnhandledExceptionHandler)
			$Script:GuiUnhandledExceptionHooked = $true
		}
		catch
		{
			$null = $_
		}
	}
	$Script:RiskFilter = 'All'
	$Script:CategoryFilter = 'All'
	$Script:AdvancedMode = $false
	$Script:FilterUiUpdating = $false
	$Script:ExecutionSummaryRecords = @()
	$Script:ExecutionSummaryLookup = @{}
	$Script:ExecutionCurrentSummaryKey = $null
	$Script:GuiDisplayVersion = Get-BaselineDisplayVersion

	# Set the window title to include OS name and version
	try
	{
		$formTitle = "Baseline | Windows Utility for $((Get-OSInfo).OSName)"
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiDisplayVersion))
		{
			$formTitle = "{0} {1}" -f $formTitle, $Script:GuiDisplayVersion
		}
		$Form.Title = $formTitle
	}
	catch { $null = $_ }
	$TitleText.Text = $Form.Title

	function Update-PrimaryTabVisuals
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$bc = New-SafeBrushConverter -Context 'Update-PrimaryTabVisuals'
		foreach ($tab in $PrimaryTabs.Items)
		{
			if (-not ($tab -is [System.Windows.Controls.TabItem])) { continue }
			$tab.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
			$tab.Padding = [System.Windows.Thickness]::new(14, 7, 14, 7)
			if ($tab -eq $PrimaryTabs.SelectedItem)
			{
				$tab.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
				$tab.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$tab.FontWeight = [System.Windows.FontWeights]::Bold
				$tab.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.ActiveTabBorder)
				$tab.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 4)
			}
			else
			{
				$tab.Background = $bc.ConvertFromString($Script:CurrentTheme.TabBg)
				$tab.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				$tab.FontWeight = [System.Windows.FontWeights]::Normal
				$tab.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.BorderColor)
			}
		}
	}

	function Add-PrimaryTabHoverEffects
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([System.Windows.Controls.TabItem]$Tab)
		if (-not $Tab) { return }
		$setGuiControlPropertyScript = ${function:Set-GuiControlProperty}
		$invokeGuiSafeActionScript = ${function:Invoke-GuiSafeAction}
		$newSafeBrushConverterScript = ${function:New-SafeBrushConverter}
		$updatePrimaryTabVisualsScript = ${function:Update-PrimaryTabVisuals}

		$mouseEnterHandler = {
			if ($Tab -eq $PrimaryTabs.SelectedItem) { return }
			$bc = & $newSafeBrushConverterScript -Context 'Add-PrimaryTabHoverEffects/MouseEnter'

			$hoverBgColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.TabHoverBg)) { [string]$Script:CurrentTheme.TabHoverBg } else { '#3B455E' }
			$textPrimaryColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.TextPrimary)) { [string]$Script:CurrentTheme.TextPrimary } else { '#CDD6F4' }
			$focusRingColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.FocusRing)) { [string]$Script:CurrentTheme.FocusRing } else { '#C9DEFF' }

			& $setGuiControlPropertyScript -Control $Tab -PropertyName 'Background' -Value ($bc.ConvertFromString($hoverBgColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/Background' | Out-Null
			& $setGuiControlPropertyScript -Control $Tab -PropertyName 'Foreground' -Value ($bc.ConvertFromString($textPrimaryColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/Foreground' | Out-Null
			& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderBrush' -Value ($bc.ConvertFromString($focusRingColor)) -Context 'Add-PrimaryTabHoverEffects/MouseEnter/BorderBrush' | Out-Null
		}.GetNewClosure()
		$Tab.Add_MouseEnter({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/MouseEnter' -Action $mouseEnterHandler
		}.GetNewClosure())

		$refreshTabVisualsHandler = {
			& $updatePrimaryTabVisualsScript
		}.GetNewClosure()
		$Tab.Add_MouseLeave({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/MouseLeave' -Action $refreshTabVisualsHandler
		}.GetNewClosure())

		$gotFocusHandler = {
			if ($Tab -eq $PrimaryTabs.SelectedItem) { return }
			$bc = & $newSafeBrushConverterScript -Context 'Add-PrimaryTabHoverEffects/GotFocus'
			$focusRingColor = if ($Script:CurrentTheme -and -not [string]::IsNullOrWhiteSpace([string]$Script:CurrentTheme.FocusRing)) { [string]$Script:CurrentTheme.FocusRing } else { '#C9DEFF' }
			& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderBrush' -Value ($bc.ConvertFromString($focusRingColor)) -Context 'Add-PrimaryTabHoverEffects/GotFocus/BorderBrush' | Out-Null
			& $setGuiControlPropertyScript -Control $Tab -PropertyName 'BorderThickness' -Value (New-SafeThickness -Bottom 3) -Context 'Add-PrimaryTabHoverEffects/GotFocus/BorderThickness' | Out-Null
		}.GetNewClosure()
		$Tab.Add_GotKeyboardFocus({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/GotFocus' -Action $gotFocusHandler
		}.GetNewClosure())

		$Tab.Add_LostKeyboardFocus({
			& $invokeGuiSafeActionScript -Context 'Add-PrimaryTabHoverEffects/LostFocus' -Action $refreshTabVisualsHandler
		}.GetNewClosure())
	}

	function Get-PrimaryTabItem
	{
		param ([string]$Tag)
		foreach ($tab in $PrimaryTabs.Items)
		{
			if (($tab -is [System.Windows.Controls.TabItem]) -and ([string]$tab.Tag -eq $Tag))
			{
				return $tab
			}
		}
		return $null
	}

	function Initialize-SearchResultsTab
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$searchTab = Get-PrimaryTabItem -Tag $Script:SearchResultsTabTag
		if ($searchTab) { return $searchTab }

		$bc = New-SafeBrushConverter -Context 'Initialize-SearchResultsTab'
		$searchTab = New-Object System.Windows.Controls.TabItem
		$searchTab.Header = 'Search Results'
		$searchTab.Tag = $Script:SearchResultsTabTag
		$searchTab.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$searchTab.Background = $bc.ConvertFromString($Script:CurrentTheme.TabBg)
		$searchTab.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
		$PrimaryTabs.Items.Add($searchTab) | Out-Null
		Add-PrimaryTabHoverEffects -Tab $searchTab
		Update-PrimaryTabVisuals
		return $searchTab
	}

	function Remove-SearchResultsTab
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$searchTab = Get-PrimaryTabItem -Tag $Script:SearchResultsTabTag
		if ($searchTab)
		{
			$PrimaryTabs.Items.Remove($searchTab)
			Update-PrimaryTabVisuals
		}
	}

	function Update-SearchResultsTabState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$searchQuery = if ($null -eq $Script:SearchText) { '' } else { $Script:SearchText.Trim() }
		if (-not [string]::IsNullOrWhiteSpace($searchQuery))
		{
			$selectedTag = if ($PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) { [string]$PrimaryTabs.SelectedItem.Tag } else { $null }
			if ($selectedTag -and $selectedTag -ne $Script:SearchResultsTabTag)
			{
				$Script:LastStandardPrimaryTab = $selectedTag
			}

			$searchTab = Initialize-SearchResultsTab
			if ($PrimaryTabs.SelectedItem -ne $searchTab)
			{
				$PrimaryTabs.SelectedItem = $searchTab
				return
			}

			if ($Script:CurrentPrimaryTab)
			{
				Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
			}
			return
		}

		$searchTab = Get-PrimaryTabItem -Tag $Script:SearchResultsTabTag
		$wasSearchTabSelected = $false
		if ($searchTab)
		{
			$wasSearchTabSelected = ($PrimaryTabs.SelectedItem -eq $searchTab)
			Remove-SearchResultsTab
		}

		if ($wasSearchTabSelected -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			$restoreTag = $Script:LastStandardPrimaryTab
			if (-not $restoreTag -or -not (Get-PrimaryTabItem -Tag $restoreTag))
			{
				foreach ($tab in $PrimaryTabs.Items)
				{
					if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
					{
						$restoreTag = [string]$tab.Tag
						break
					}
				}
			}

			$restoreTab = if ($restoreTag) { Get-PrimaryTabItem -Tag $restoreTag } else { $null }
			if ($restoreTab -and $PrimaryTabs.SelectedItem -ne $restoreTab)
			{
				$PrimaryTabs.SelectedItem = $restoreTab
				return
			}
		}

		if ($Script:CurrentPrimaryTab -and $Script:CurrentPrimaryTab -ne $Script:SearchResultsTabTag)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	}

	function Set-SearchInputStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $TxtSearch) { return }
		$bc = New-SafeBrushConverter -Context 'Set-SearchInputStyle'
		$TxtSearch.Background = $bc.ConvertFromString($(if ($TxtSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.InputHoverBg } else { $Script:CurrentTheme.SearchBg }))
		$TxtSearch.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$TxtSearch.BorderBrush = $bc.ConvertFromString($(if ($TxtSearch.IsKeyboardFocusWithin) { $Script:CurrentTheme.FocusRing } else { $Script:CurrentTheme.SearchBorder }))
		$TxtSearch.BorderThickness = [System.Windows.Thickness]::new($(if ($TxtSearch.IsKeyboardFocusWithin) { 2 } else { 1 }))
		$TxtSearch.CaretBrush = $bc.ConvertFromString($Script:CurrentTheme.AccentBlue)
		$SearchLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		if ($TxtSearchPlaceholder)
		{
			$TxtSearchPlaceholder.Foreground = $bc.ConvertFromString($Script:CurrentTheme.SearchPlaceholder)
			$TxtSearchPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($TxtSearch.Text)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
		if ($BtnClearSearch)
		{
			$BtnClearSearch.Visibility = if ([string]::IsNullOrWhiteSpace($TxtSearch.Text)) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			Set-ButtonChrome -Button $BtnClearSearch -Variant 'Subtle' -Compact -Muted
		}
	}

	function Add-CardHoverEffects
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.Controls.Border]$Card,
			[object[]]$FocusSources = @()
		)
		if (-not $Card) { return }
		$setGuiControlPropertyCapture = ${function:Set-GuiControlProperty}.GetNewClosure()
		$invokeGuiSafeActionCapture = ${function:Invoke-GuiSafeAction}.GetNewClosure()
		$bc = New-SafeBrushConverter -Context 'Add-CardHoverEffects'
		$defaultBg = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$hoverBg = $bc.ConvertFromString($Script:CurrentTheme.CardHoverBg)
		$defaultBorder = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
		$hoverBorder = $bc.ConvertFromString($Script:CurrentTheme.AccentHover)
		$focusBorder = $bc.ConvertFromString($Script:CurrentTheme.FocusRing)
		$updateChrome = {
			$hasFocus = $false
			foreach ($focusSource in $FocusSources)
			{
				if ($focusSource -and $focusSource.IsKeyboardFocusWithin)
			{
					$hasFocus = $true
					break
				}
			}
			& $setGuiControlPropertyCapture -Control $Card -PropertyName 'Background' -Value ($(if ($Card.IsMouseOver) { $hoverBg } else { $defaultBg })) -Context 'Add-CardHoverEffects/Background' | Out-Null
			if ($hasFocus)
			{
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderBrush' -Value $focusBorder -Context 'Add-CardHoverEffects/FocusBorderBrush' | Out-Null
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderThickness' -Value ([System.Windows.Thickness]::new(2)) -Context 'Add-CardHoverEffects/FocusBorderThickness' | Out-Null
			}
			elseif ($Card.IsMouseOver)
			{
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderBrush' -Value $hoverBorder -Context 'Add-CardHoverEffects/HoverBorderBrush' | Out-Null
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderThickness' -Value ([System.Windows.Thickness]::new(1)) -Context 'Add-CardHoverEffects/HoverBorderThickness' | Out-Null
			}
			else
			{
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderBrush' -Value $defaultBorder -Context 'Add-CardHoverEffects/DefaultBorderBrush' | Out-Null
				& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderThickness' -Value ([System.Windows.Thickness]::new(1)) -Context 'Add-CardHoverEffects/DefaultBorderThickness' | Out-Null
			}
		}.GetNewClosure()
		& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderBrush' -Value $defaultBorder -Context 'Add-CardHoverEffects/InitialBorderBrush' | Out-Null
		& $setGuiControlPropertyCapture -Control $Card -PropertyName 'BorderThickness' -Value ([System.Windows.Thickness]::new(1)) -Context 'Add-CardHoverEffects/InitialBorderThickness' | Out-Null
		$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
		$shadow.Color = [System.Windows.Media.Colors]::Black
		$shadow.Direction = 270
		$shadow.ShadowDepth = if ($Script:CurrentTheme -eq $Script:LightTheme) { 2 } else { 1 }
		$shadow.Opacity = if ($Script:CurrentTheme -eq $Script:LightTheme) { 0.09 } else { 0.18 }
		$shadow.BlurRadius = if ($Script:CurrentTheme -eq $Script:LightTheme) { 8 } else { 10 }
		$Card.Effect = $shadow
		$Card.Cursor = [System.Windows.Input.Cursors]::Hand
		$Card.Add_MouseEnter({
			& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/MouseEnter' -Action $updateChrome
		}.GetNewClosure())
		$Card.Add_MouseLeave({
			& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/MouseLeave' -Action $updateChrome
		}.GetNewClosure())
		$pressBg = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$pressHandler = {
			& $setGuiControlPropertyCapture -Control $Card -PropertyName 'Background' -Value $pressBg -Context 'Add-CardHoverEffects/MouseDown/Background' | Out-Null
		}.GetNewClosure()
		$Card.Add_PreviewMouseLeftButtonDown({
			& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/MouseDown' -Action $pressHandler
		}.GetNewClosure())
		$Card.Add_PreviewMouseLeftButtonUp({
			& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/MouseUp' -Action $updateChrome
		}.GetNewClosure())
		foreach ($focusSource in $FocusSources)
		{
			if (-not $focusSource) { continue }
			$focusSource.Add_GotKeyboardFocus({
				& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/GotFocus' -Action $updateChrome
			}.GetNewClosure())
			$focusSource.Add_LostKeyboardFocus({
				& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/LostFocus' -Action $updateChrome
			}.GetNewClosure())
		}
		& $invokeGuiSafeActionCapture -Context 'Add-CardHoverEffects/Initialize' -Action $updateChrome
	}

	function Set-ChoiceComboStyle
	{
		param ([System.Windows.Controls.ComboBox]$Combo)
		if (-not $Combo) { return }

		$theme = $Script:CurrentTheme
		$bc = New-SafeBrushConverter -Context 'Set-ChoiceComboStyle'

		# Helper to ensure a color is a valid hex string
		$ensureHexColor = {
			param($Color, $Default = '#89B4FA')
			if ([string]::IsNullOrWhiteSpace($Color)) { return $Default }
			if ($Color -match '^#[0-9A-Fa-f]{6}$|^#[0-9A-Fa-f]{8}$') { return $Color }
			return $Default
		}

		$inputBg       = & $ensureHexColor $theme.InputBg       '#313244'
		$textPrimary   = & $ensureHexColor $theme.TextPrimary   '#CDD6F4'
		$borderBrush   = & $ensureHexColor $theme.SearchBorder  '#585B70'
		$hoverBg       = & $ensureHexColor $theme.CardHoverBg   '#323A4E'
		$activeBg      = & $ensureHexColor $theme.TabActiveBg   '#223B60'
		$activeBorder  = & $ensureHexColor $theme.ActiveTabBorder '#89B4FA'

		if (-not $Script:ChoiceComboTemplate -or $Script:ChoiceComboTemplateTheme -ne $Script:CurrentThemeName)
		{
			$comboTemplateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type ComboBox}">
    <Grid SnapsToDevicePixels="True"
          TextElement.Foreground="{TemplateBinding Foreground}">
        <Border Background="$inputBg"
                BorderBrush="$borderBrush"
                BorderThickness="1"
                CornerRadius="6"
                SnapsToDevicePixels="True" />

        <ContentPresenter x:Name="ContentSite"
                          Margin="{TemplateBinding Padding}"
                          HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                          VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                          Content="{TemplateBinding SelectionBoxItem}"
                          ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                          ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                          ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                          IsHitTestVisible="False"
                          RecognizesAccessKey="True"
                          SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}" />

        <ToggleButton x:Name="ToggleButton"
                      Focusable="False"
                      ClickMode="Press"
                      Background="Transparent"
                      BorderBrush="Transparent"
                      BorderThickness="0"
                      IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"
                      HorizontalAlignment="Stretch"
                      VerticalAlignment="Stretch">
            <ToggleButton.Template>
                <ControlTemplate TargetType="{x:Type ToggleButton}">
                    <Border Background="Transparent"
                            BorderBrush="Transparent"
                            BorderThickness="0"
                            SnapsToDevicePixels="True" />
                </ControlTemplate>
            </ToggleButton.Template>
        </ToggleButton>

        <Path HorizontalAlignment="Right"
              VerticalAlignment="Center"
              Margin="0,0,10,0"
              Data="M 0 0 L 4 4 L 8 0"
              Stroke="{TemplateBinding Foreground}"
              StrokeThickness="1.6"
              StrokeStartLineCap="Round"
              StrokeEndLineCap="Round"
              Stretch="Fill"
              Width="8"
              Height="4"
              IsHitTestVisible="False" />

        <Popup x:Name="Popup"
               Placement="Bottom"
               AllowsTransparency="True"
               Focusable="False"
               IsOpen="{TemplateBinding IsDropDownOpen}"
               PopupAnimation="Slide"
               PlacementTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}">
            <Border Width="{Binding PlacementTarget.ActualWidth, RelativeSource={RelativeSource AncestorType={x:Type Popup}}}"
                    Background="$inputBg"
                    BorderBrush="$borderBrush"
                    BorderThickness="1"
                    CornerRadius="6"
                    SnapsToDevicePixels="True">
                <ScrollViewer Margin="4,6,4,6"
                              SnapsToDevicePixels="True">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" />
                </ScrollViewer>
            </Border>
        </Popup>
    </Grid>
</ControlTemplate>
"@
			try {
				$comboTemplateReader = New-Object System.Xml.XmlNodeReader ([xml]$comboTemplateXaml)
				$Script:ChoiceComboTemplate = [System.Windows.Markup.XamlReader]::Load($comboTemplateReader)
				$Script:ChoiceComboTemplateTheme = $Script:CurrentThemeName
			}
			catch {
				# Silently ignore XAML errors – the control will fall back to default style
				return
			}
		}

		# Apply the template and styles (with error swallowing)
		try {
			$Combo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::WindowTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $bc.ConvertFromString($activeBg)
			$Combo.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $bc.ConvertFromString($textPrimary)
			$Combo.Resources[[System.Windows.SystemColors]::MenuBrushKey] = $bc.ConvertFromString($inputBg)
			$Combo.Resources[[System.Windows.SystemColors]::MenuTextBrushKey] = $bc.ConvertFromString($textPrimary)

			$itemStyle = New-Object System.Windows.Style([System.Windows.Controls.ComboBoxItem])
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($inputBg)))) | Out-Null
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value ($bc.ConvertFromString($textPrimary)))) | Out-Null
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($borderBrush)))) | Out-Null
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderThicknessProperty) -Value ([System.Windows.Thickness]::new(0)))) | Out-Null
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::PaddingProperty) -Value ([System.Windows.Thickness]::new(10, 4, 10, 4)))) | Out-Null
			$itemStyle.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::HorizontalContentAlignmentProperty) -Value ([System.Windows.HorizontalAlignment]::Stretch))) | Out-Null

			$hoverTrigger = New-Object System.Windows.Trigger
			$hoverTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsMouseOverProperty
			$hoverTrigger.Value = $true
			$hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($hoverBg)))) | Out-Null
			$hoverTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($activeBorder)))) | Out-Null
			$itemStyle.Triggers.Add($hoverTrigger) | Out-Null

			$selectedTrigger = New-Object System.Windows.Trigger
			$selectedTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsSelectedProperty
			$selectedTrigger.Value = $true
			$selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BackgroundProperty) -Value ($bc.ConvertFromString($activeBg)))) | Out-Null
			$selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::ForegroundProperty) -Value ($bc.ConvertFromString($textPrimary)))) | Out-Null
			$selectedTrigger.Setters.Add((New-WpfSetter -Property ([System.Windows.Controls.Control]::BorderBrushProperty) -Value ($bc.ConvertFromString($activeBorder)))) | Out-Null
			$itemStyle.Triggers.Add($selectedTrigger) | Out-Null

			$Combo.ItemContainerStyle = $itemStyle
			$Combo.OverridesDefaultStyle = $true
			$Combo.Background = $bc.ConvertFromString($inputBg)
			$Combo.Foreground = $bc.ConvertFromString($textPrimary)
			$Combo.SetValue([System.Windows.Documents.TextElement]::ForegroundProperty, $bc.ConvertFromString($textPrimary))
			$Combo.BorderBrush = $bc.ConvertFromString($borderBrush)
			$Combo.BorderThickness = [System.Windows.Thickness]::new(1)
			$Combo.Template = $Script:ChoiceComboTemplate
			$Combo.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
			$Combo.MinWidth = 190
			$Combo.Height = 30
		}
		catch {
			# Silently ignore any remaining errors – the combo will still work
			return
		}
	}

	function Set-FilterControlStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$bc = New-SafeBrushConverter -Context 'Set-FilterControlStyle'
		if ($RiskFilterLabel) { $RiskFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CategoryFilterLabel) { $CategoryFilterLabel.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($ChkAdvancedMode) { $ChkAdvancedMode.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary) }
		if ($CmbRiskFilter) { Set-ChoiceComboStyle -Combo $CmbRiskFilter }
		if ($CmbCategoryFilter) { Set-ChoiceComboStyle -Combo $CmbCategoryFilter }
	}

	function Test-TweakVisibleInCurrentMode
	{
		param (
			[hashtable]$Tweak,
			[int]$LeftIndent = 28
		)
		if (-not $Tweak) { return $false }
		if ($Script:AdvancedMode) { return $true }

		$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
		if ($riskLevel -eq 'High') { return $false }

		$tagValues = @($Tweak.Tags | ForEach-Object { [string]$_ })
		if ($tagValues -contains 'advanced') { return $false }

		return $true
	}

	function Get-AvailableCategoryFilters
	{
		param ([string]$PrimaryTab)

		$categorySet = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
		$isSearchContext = ($PrimaryTab -eq $Script:SearchResultsTabTag)
		foreach ($tweak in $Script:TweakManifest)
		{
			if (-not (Test-TweakVisibleInCurrentMode -Tweak $tweak)) { continue }
			$owningPrimary = $CategoryToPrimary[$tweak.Category]
			if (-not $isSearchContext -and $owningPrimary -ne $PrimaryTab) { continue }
			if ([string]::IsNullOrWhiteSpace([string]$tweak.Category)) { continue }
			[void]$categorySet.Add([string]$tweak.Category)
		}

		return @($categorySet)
	}

	function Update-CategoryFilterList
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$PrimaryTab)
		if (-not $CmbCategoryFilter) { return }

		$targetTab = if (-not [string]::IsNullOrWhiteSpace($PrimaryTab)) {
			$PrimaryTab
		}
		elseif ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}

		$currentValue = if ($CmbCategoryFilter.SelectedItem) { [string]$CmbCategoryFilter.SelectedItem } elseif ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
		$values = if ($targetTab) { @(Get-AvailableCategoryFilters -PrimaryTab $targetTab) } else { @() }

		$Script:FilterUiUpdating = $true
		try
		{
			$CmbCategoryFilter.Items.Clear()
			[void]$CmbCategoryFilter.Items.Add('All')
			foreach ($value in $values)
			{
				[void]$CmbCategoryFilter.Items.Add($value)
			}

			if ($currentValue -and $currentValue -ne 'All' -and $values -contains $currentValue)
			{
				$CmbCategoryFilter.SelectedItem = $currentValue
				$Script:CategoryFilter = $currentValue
			}
			else
			{
				$CmbCategoryFilter.SelectedIndex = 0
				$Script:CategoryFilter = 'All'
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	function Test-TweakMatchesCurrentFilters
	{
		param (
			[hashtable]$Tweak,
			[string]$PrimaryTab,
			[string]$SearchQuery,
			[bool]$IsSearchResultsTab = $false
		)

		if (-not (Test-TweakVisibleInCurrentMode -Tweak $Tweak)) { return $false }

		$owningPrimary = $CategoryToPrimary[$Tweak.Category]
		if (-not $IsSearchResultsTab -and $owningPrimary -ne $PrimaryTab) { return $false }

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:RiskFilter) -and $Script:RiskFilter -ne 'All')
		{
			$riskLevel = if ([string]::IsNullOrWhiteSpace([string]$Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
			if ($riskLevel -ne $Script:RiskFilter) { return $false }
		}

		if (-not [string]::IsNullOrWhiteSpace([string]$Script:CategoryFilter) -and $Script:CategoryFilter -ne 'All')
		{
			if ([string]$Tweak.Category -ne [string]$Script:CategoryFilter) { return $false }
		}

		$effectiveQuery = if ($null -eq $SearchQuery) { '' } else { $SearchQuery.Trim() }
		if (-not [string]::IsNullOrWhiteSpace($effectiveQuery))
		{
			$searchParts = @(
				$Tweak.Name,
				$Tweak.Description,
				$Tweak.Detail,
				$Tweak.WhyThisMatters,
				$Tweak.Category,
				$Tweak.SubCategory,
				$Tweak.Function,
				$owningPrimary,
				$Tweak.Risk,
				$Tweak.PresetTier,
				($Tweak.Tags -join ' '),
				$(if ($Tweak.Safe) { 'safe' } else { 'not-safe' }),
				$(if ($Tweak.Impact) { 'impact' } else { 'standard' }),
				$(if ($Tweak.RequiresRestart) { 'restart reboot requires-restart' } else { 'no-restart' })
			)
			$haystack = ($searchParts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
			if ($haystack -notmatch [regex]::Escape($effectiveQuery))
			{
				return $false
			}
		}

		return $true
	}

	function Set-SearchControlsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		if ($TxtSearch) { $TxtSearch.IsEnabled = $Enabled }
		if ($BtnClearSearch) { $BtnClearSearch.IsEnabled = $Enabled }
		if ($CmbRiskFilter) { $CmbRiskFilter.IsEnabled = $Enabled }
		if ($CmbCategoryFilter) { $CmbCategoryFilter.IsEnabled = $Enabled }
		if ($ChkAdvancedMode) { $ChkAdvancedMode.IsEnabled = $Enabled }
		Set-SearchInputStyle
	}

	function Set-GuiActionButtonsEnabled
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)
		if ($BtnDefaults) { $BtnDefaults.IsEnabled = $Enabled }
		if ($BtnExportSettings) { $BtnExportSettings.IsEnabled = $Enabled }
		if ($BtnImportSettings) { $BtnImportSettings.IsEnabled = $Enabled }
		if ($BtnRestoreSnapshot) { $BtnRestoreSnapshot.IsEnabled = ($Enabled -and $null -ne $Script:UiSnapshotUndo) }
	}

	function Save-GuiUndoSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$Script:UiSnapshotUndo = Get-GuiSettingsSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not $Script:RunInProgress)
	}

	function Get-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$themeName = if ($ChkTheme) {
			if ($ChkTheme.IsChecked) { 'Light' } else { 'Dark' }
		}
		elseif ($Script:CurrentThemeName) {
			[string]$Script:CurrentThemeName
		}
		else {
			'Dark'
		}

		$searchText = if ($TxtSearch) { [string]$TxtSearch.Text } elseif ($null -ne $Script:SearchText) { [string]$Script:SearchText } else { '' }
		$scanEnabled = if ($ChkScan) { [bool]$ChkScan.IsChecked } else { [bool]$Script:ScanEnabled }
		$currentPrimaryTab = if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}

		$snapshot = [ordered]@{
			Schema = 'Baseline.GuiSettings'
			SchemaVersion = 2
			SavedAt = (Get-Date).ToString('o')
			Theme = $themeName
			SearchText = $searchText
			ScanEnabled = $scanEnabled
			AdvancedMode = [bool]$Script:AdvancedMode
			RiskFilter = if ($Script:RiskFilter) { [string]$Script:RiskFilter } else { 'All' }
			CategoryFilter = if ($Script:CategoryFilter) { [string]$Script:CategoryFilter } else { 'All' }
			CurrentPrimaryTab = $currentPrimaryTab
			LastStandardPrimaryTab = if ($Script:LastStandardPrimaryTab) { [string]$Script:LastStandardPrimaryTab } else { $null }
			ExplicitSelections = @($Script:ExplicitPresetSelections)
			Controls = @()
		}

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			$entry = [ordered]@{
				Index = $i
				Function = $manifest.Function
				Type = $manifest.Type
			}

			switch ($manifest.Type)
			{
				'Choice'
				{
					$selectedIndex = -1
					if ($control -and $control.PSObject.Properties['SelectedIndex'])
					{
						$selectedIndex = [int]$control.SelectedIndex
					}
					$selectedValue = $null
					if ($selectedIndex -ge 0 -and $selectedIndex -lt $manifest.Options.Count)
					{
						$selectedValue = [string]$manifest.Options[$selectedIndex]
					}
					$entry.SelectedIndex = $selectedIndex
					$entry.SelectedValue = $selectedValue
				}
				default
				{
					$entry.IsChecked = if ($control -and $control.PSObject.Properties['IsChecked']) { [bool]$control.IsChecked } else { $false }
				}
			}

			$snapshot.Controls += [pscustomobject]$entry
		}

		return [pscustomobject]$snapshot
	}

	function Restore-GuiSettingsSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[Parameter(Mandatory = $true)]
			[object]
			$Snapshot
		)

		if (-not $Snapshot)
		{
			throw "No GUI settings snapshot was supplied."
		}

		$controlStates = @{}
		if ($Snapshot.PSObject.Properties['Controls'])
		{
			foreach ($entry in @($Snapshot.Controls))
			{
				if ($entry -and $entry.PSObject.Properties['Function'])
				{
					$controlStates[[string]$entry.Function] = $entry
				}
			}
		}

		$Script:ExplicitPresetSelections.Clear()
		if ($Snapshot.PSObject.Properties['ExplicitSelections'])
		{
			foreach ($functionName in @($Snapshot.ExplicitSelections))
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$functionName))
				{
					[void]$Script:ExplicitPresetSelections.Add([string]$functionName)
				}
			}
		}

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$manifest = $Script:TweakManifest[$i]
			$control = $Script:Controls[$i]
			if (-not $control) { continue }

			$state = $controlStates[$manifest.Function]
			if (-not $state) { continue }

			switch ($manifest.Type)
			{
				'Choice'
				{
					if ($control.PSObject.Properties['SelectedIndex'])
					{
						$selectedIndex = -1
						if ($state.PSObject.Properties['SelectedValue'] -and -not [string]::IsNullOrWhiteSpace([string]$state.SelectedValue))
						{
							$selectedIndex = [array]::IndexOf($manifest.Options, [string]$state.SelectedValue)
						}
						if ($selectedIndex -lt 0 -and $state.PSObject.Properties['SelectedIndex'])
						{
							$selectedIndex = [int]$state.SelectedIndex
						}
						if ($selectedIndex -ge $manifest.Options.Count) { $selectedIndex = -1 }
						$control.SelectedIndex = $selectedIndex
					}
				}
				default
				{
					if ($control.PSObject.Properties['IsChecked'])
					{
						$control.IsChecked = [bool]$state.IsChecked
					}
				}
			}
		}

		$desiredTheme = if ($Snapshot.PSObject.Properties['Theme']) { [string]$Snapshot.Theme } else { 'Dark' }
		$desiredScan  = if ($Snapshot.PSObject.Properties['ScanEnabled']) { [bool]$Snapshot.ScanEnabled } else { $false }
		$desiredSearch = if ($Snapshot.PSObject.Properties['SearchText']) { [string]$Snapshot.SearchText } else { '' }
		$desiredAdvanced = if ($Snapshot.PSObject.Properties['AdvancedMode']) { [bool]$Snapshot.AdvancedMode } else { $false }
		$desiredRisk = if ($Snapshot.PSObject.Properties['RiskFilter'] -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.RiskFilter)) { [string]$Snapshot.RiskFilter } else { 'All' }
		$desiredCategory = if ($Snapshot.PSObject.Properties['CategoryFilter'] -and -not [string]::IsNullOrWhiteSpace([string]$Snapshot.CategoryFilter)) { [string]$Snapshot.CategoryFilter } else { 'All' }
		$desiredTab   = if ($Snapshot.PSObject.Properties['CurrentPrimaryTab']) { [string]$Snapshot.CurrentPrimaryTab } else { $null }
		$desiredLast  = if ($Snapshot.PSObject.Properties['LastStandardPrimaryTab']) { [string]$Snapshot.LastStandardPrimaryTab } else { $null }

		if ($desiredLast)
		{
			$Script:LastStandardPrimaryTab = $desiredLast
		}

		if ($ChkTheme)
		{
			if ($desiredTheme -eq 'Light' -and -not $ChkTheme.IsChecked)
			{
				$ChkTheme.IsChecked = $true
			}
			elseif ($desiredTheme -ne 'Light' -and $ChkTheme.IsChecked)
			{
				$ChkTheme.IsChecked = $false
			}
		}
		else
		{
			if ($desiredTheme -eq 'Light')
			{
				Set-GUITheme -Theme $Script:LightTheme
			}
			else
			{
				Set-GUITheme -Theme $Script:DarkTheme
			}
		}

		$Script:ScanEnabled = $desiredScan
		if ($ChkScan)
		{
			if ($ChkScan.IsChecked -ne $desiredScan)
			{
				$ChkScan.IsChecked = $desiredScan
			}
		}

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:AdvancedMode = $desiredAdvanced
			if ($ChkAdvancedMode)
			{
				if ([bool]$ChkAdvancedMode.IsChecked -ne $desiredAdvanced)
				{
					$ChkAdvancedMode.IsChecked = $desiredAdvanced
				}
			}

			$Script:RiskFilter = $desiredRisk
			if ($CmbRiskFilter)
			{
				if ($CmbRiskFilter.Items.Contains($desiredRisk))
				{
					$CmbRiskFilter.SelectedItem = $desiredRisk
				}
				else
				{
					$CmbRiskFilter.SelectedIndex = 0
					$Script:RiskFilter = 'All'
				}
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		$Script:SearchText = $desiredSearch
		if ($TxtSearch)
		{
			if ($TxtSearch.Text -ne $desiredSearch)
			{
				$TxtSearch.Text = $desiredSearch
			}
		}

		Update-SearchResultsTabState
		Update-CategoryFilterList -PrimaryTab $(if ($desiredSearch) { $Script:SearchResultsTabTag } else { $desiredTab })

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:CategoryFilter = $desiredCategory
			if ($CmbCategoryFilter)
			{
				if ($CmbCategoryFilter.Items.Contains($desiredCategory))
				{
					$CmbCategoryFilter.SelectedItem = $desiredCategory
				}
				else
				{
					$CmbCategoryFilter.SelectedIndex = 0
					$Script:CategoryFilter = 'All'
				}
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}

		Update-SearchResultsTabState

		if ([string]::IsNullOrWhiteSpace($desiredSearch) -and $desiredTab)
		{
			if ($desiredTab -eq $Script:SearchResultsTabTag)
			{
				$restoreTag = if ($desiredLast) { $desiredLast } else { $Script:LastStandardPrimaryTab }
				$restoreTab = if ($restoreTag) { Get-PrimaryTabItem -Tag $restoreTag } else { $null }
				if (-not $restoreTab)
				{
					foreach ($tab in $PrimaryTabs.Items)
					{
						if (($tab -is [System.Windows.Controls.TabItem]) -and $tab.Tag -and ([string]$tab.Tag -ne $Script:SearchResultsTabTag))
						{
							$restoreTab = $tab
							break
						}
					}
				}
				if ($restoreTab -and $PrimaryTabs.SelectedItem -ne $restoreTab)
				{
					$PrimaryTabs.SelectedItem = $restoreTab
				}
			}
			else
			{
				$targetTab = Get-PrimaryTabItem -Tag $desiredTab
				if ($targetTab -and $PrimaryTabs.SelectedItem -ne $targetTab)
				{
					$PrimaryTabs.SelectedItem = $targetTab
				}
			}
		}

		Set-GuiActionButtonsEnabled -Enabled (-not $Script:RunInProgress)
	}

	function Restore-GuiSnapshot
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		if (-not $Script:UiSnapshotUndo)
		{
			return $false
		}

		$redoSnapshot = Get-GuiSettingsSnapshot
		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
		}
		catch
		{
			try
			{
				Restore-GuiSettingsSnapshot -Snapshot $redoSnapshot
			}
			catch { $null = $_ }
			throw "Failed to restore the previous GUI snapshot: $($_.Exception.Message)"
		}

		$Script:UiSnapshotUndo = $redoSnapshot
		Set-GuiActionButtonsEnabled -Enabled (-not $Script:RunInProgress)
		return $true
	}

	function Get-GuiSettingsProfileDirectory
	{
		param ()
		return (GUICommon\Get-GuiSettingsProfileDirectory -AppName 'Baseline')
	}

	function Get-GuiSessionStatePath
	{
		param ()
		return (GUICommon\Get-GuiSessionStatePath -AppName 'Baseline')
	}

	function Save-GuiSessionState
	{
		param ()
		return (GUICommon\Save-GuiSessionStateDocument -Snapshot (Get-GuiSettingsSnapshot) -AppName 'Baseline')
	}

	function Restore-GuiSessionState
	{
		param ()

		$snapshot = GUICommon\Read-GuiSessionStateDocument -AppName 'Baseline' -ExpectedSchema 'Baseline.GuiSettings'
		if (-not $snapshot)
		{
			return $false
		}

		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $snapshot
			LogInfo "Restored previous GUI session state."
			return $true
		}
		catch
		{
			LogWarning "Failed to restore GUI session state: $($_.Exception.Message)"
			return $false
		}
	}

	function Export-GuiSettingsProfile
	{
		param ()

		$snapshot = Get-GuiSettingsSnapshot
		$savePath = GUICommon\Show-GuiSettingsSaveDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($savePath))
		{
			return $false
		}

		try
		{
			GUICommon\Write-GuiSettingsProfileDocument -Snapshot $snapshot -FilePath $savePath | Out-Null
			LogInfo "Exported GUI settings to $savePath"
			$StatusText.Text = "Settings exported to $savePath"
			$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
			return $true
		}
		catch
		{
			LogError "Failed to export GUI settings: $($_.Exception.Message)"
			Show-ThemedDialog -Title 'Export Settings' -Message "Failed to export settings.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK' | Out-Null
			return $false
		}
	}

	function Import-GuiSettingsProfile
	{
		param ()

		$openPath = GUICommon\Show-GuiSettingsOpenDialog -AppName 'Baseline'
		if ([string]::IsNullOrWhiteSpace($openPath))
		{
			return $false
		}

		try
		{
			$snapshot = GUICommon\Read-GuiSettingsProfileDocument -FilePath $openPath -ExpectedSchema 'Baseline.GuiSettings'
		}
		catch
		{
			LogError "Failed to read GUI settings profile: $($_.Exception.Message)"
			Show-ThemedDialog -Title 'Import Settings' -Message "Failed to read the selected profile.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK' | Out-Null
			return $false
		}

		Save-GuiUndoSnapshot
		try
		{
			Restore-GuiSettingsSnapshot -Snapshot $snapshot
			$StatusText.Text = "Settings imported from $openPath"
			$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
			LogInfo "Imported GUI settings from $openPath"
			Set-GuiActionButtonsEnabled -Enabled (-not $Script:RunInProgress)
			return $true
		}
		catch
		{
			LogError "Failed to import GUI settings: $($_.Exception.Message)"
			if ($Script:UiSnapshotUndo)
			{
				try
				{
					Restore-GuiSettingsSnapshot -Snapshot $Script:UiSnapshotUndo
				}
				catch { $null = $_ }
			}
			$Script:UiSnapshotUndo = $null
			Set-GuiActionButtonsEnabled -Enabled (-not $Script:RunInProgress)
			Show-ThemedDialog -Title 'Import Settings' -Message "Failed to import settings.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK' | Out-Null
			return $false
		}
	}

	#region Helper: Apply theme
		function Set-GUITheme
		{
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
			param ([hashtable]$Theme)
			$themeRepairName = 'Dark'
			if ($Theme -eq $Script:LightTheme)
			{
				$Script:CurrentThemeName = 'Light'
				$themeRepairName = 'Light'
			}
			elseif ($Theme -eq $Script:DarkTheme)
			{
				$Script:CurrentThemeName = 'Dark'
				$themeRepairName = 'Dark'
			}
			else
			{
				$Script:CurrentThemeName = 'Custom'
			}
			$Theme = Repair-GuiThemePalette -Theme $Theme -ThemeName $themeRepairName
			$Script:CurrentTheme = $Theme
			$bc = New-SafeBrushConverter -Context 'Set-GUITheme'

		$Form.Background  = $bc.ConvertFromString($Theme.WindowBg)
		$Form.Foreground  = $bc.ConvertFromString($Theme.TextPrimary)
		$HeaderBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		$ContentBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$BottomBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		$TitleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
		$StatusText.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$ScanLabel.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		Set-HeaderToggleControlsStyle
		Set-SearchInputStyle
		Set-FilterControlStyle
		Set-StaticButtonStyle
		Update-PrimaryTabVisuals

		# Rebuild content for current tab to pick up colors
		if ($null -ne $Script:CurrentPrimaryTab)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	}
	#endregion


	#region Helper: Create styled controls
	function New-InfoIcon
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$TooltipText,
			[hashtable]$Tweak
		)

		$bc = New-SafeBrushConverter -Context 'New-InfoIcon'
		$theme = $Script:CurrentTheme

		$stackPanel = New-Object System.Windows.Controls.StackPanel
		$stackPanel.Margin = [System.Windows.Thickness]::new(4, 3, 4, 3)
		$stackPanel.MaxWidth = 320

		# Description (bold)
		$tb = New-Object System.Windows.Controls.TextBlock
		$tb.Text = if ([string]::IsNullOrWhiteSpace($TooltipText)) { 'This option changes a Windows setting.' } else { $TooltipText.Trim() }
		$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$tb.FontWeight = [System.Windows.FontWeights]::SemiBold
		$tb.FontSize = 12
		$stackPanel.Children.Add($tb) | Out-Null

		# Detail text
		if ($Tweak -and $Tweak.ContainsKey('Detail') -and -not [string]::IsNullOrWhiteSpace($Tweak.Detail))
		{
			$tb = New-Object System.Windows.Controls.TextBlock
			$tb.Text = $Tweak.Detail.Trim()
			$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$tb.FontSize = 11
			$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
			$stackPanel.Children.Add($tb) | Out-Null
		}

		if ($Tweak)
		{
			# Separator
			$sep = New-Object System.Windows.Controls.Separator
			$sep.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
			$stackPanel.Children.Add($sep) | Out-Null

			$addSectionHeader = {
				param([string]$Text)
				$section = New-Object System.Windows.Controls.TextBlock
				$section.Text = $Text.ToUpperInvariant()
				$section.FontSize = 10
				$section.FontWeight = [System.Windows.FontWeights]::Bold
				$section.Foreground = $bc.ConvertFromString($theme.SectionLabel)
				$section.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)
				$stackPanel.Children.Add($section) | Out-Null
			}

			# Toggle / Choice / Action lines
			& $addSectionHeader 'Behavior'
			switch ($Tweak.Type)
			{
				'Toggle' {
					$onLabel  = if ($Tweak.OnParam)  { $Tweak.OnParam  } else { 'Enable' }
					$offLabel = if ($Tweak.OffParam) { $Tweak.OffParam } else { 'Disable' }
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = "Checked: $onLabel"
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					$stackPanel.Children.Add($tb) | Out-Null
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = "Unchecked: $offLabel"
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					$stackPanel.Children.Add($tb) | Out-Null
				}
				'Choice' {
					$displayOpts = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } else { $Tweak.Options }
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = "Choices: $($displayOpts -join ', ')"
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					$stackPanel.Children.Add($tb) | Out-Null
				}
				'Action' {
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = 'Checked: this action runs when you click Run Tweaks'
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					$stackPanel.Children.Add($tb) | Out-Null
					$tb = New-Object System.Windows.Controls.TextBlock
					$tb.Text = 'Unchecked: this action is skipped'
					$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
					$tb.FontSize = 11
					$tb.Foreground = $bc.ConvertFromString($theme.TextSecondary)
					$stackPanel.Children.Add($tb) | Out-Null
				}
			}

			$winDefText = if ($Tweak.ContainsKey('WinDefaultDesc') -and -not [string]::IsNullOrWhiteSpace($Tweak.WinDefaultDesc)) {
				$Tweak.WinDefaultDesc
			} elseif ($Tweak.ContainsKey('WinDefault') -and $null -ne $Tweak.WinDefault -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WinDefault)) {
				[string]$Tweak.WinDefault
			} else {
				$null
			}
			if ($winDefText)
			{
				$sepDefault = New-Object System.Windows.Controls.Separator
				$sepDefault.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
				$stackPanel.Children.Add($sepDefault) | Out-Null
				& $addSectionHeader 'Default'
				$tb = New-Object System.Windows.Controls.TextBlock
				$tb.Text = $winDefText
				$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$tb.FontSize = 11
				$tb.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$stackPanel.Children.Add($tb) | Out-Null
			}

			$sepRisk = New-Object System.Windows.Controls.Separator
			$sepRisk.Margin = [System.Windows.Thickness]::new(0, 6, 0, 6)
			$stackPanel.Children.Add($sepRisk) | Out-Null
			& $addSectionHeader 'Risk'
			$riskLevel = if ([string]::IsNullOrWhiteSpace($Tweak.Risk)) { 'Low' } else { [string]$Tweak.Risk }
			$riskRow = New-Object System.Windows.Controls.StackPanel
			$riskRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
			$riskLbl = New-Object System.Windows.Controls.TextBlock
			$riskLbl.Text = 'Level: '
			$riskLbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
			$riskLbl.FontSize = 11
			$riskRow.Children.Add($riskLbl) | Out-Null
			$riskVal = New-Object System.Windows.Controls.TextBlock
			$riskVal.Text = if ($riskLevel -eq 'Low') { 'Low Risk' } elseif ($riskLevel -eq 'High') { 'High Risk' } else { 'Medium Risk' }
			$riskVal.FontWeight = [System.Windows.FontWeights]::SemiBold
			$riskVal.FontSize = 11
			if ($riskLevel -eq 'High')
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.RiskHighBadge)
			}
			elseif ($riskLevel -eq 'Medium')
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.RiskMediumBadge)
			}
			else
			{
				$riskVal.Foreground = $bc.ConvertFromString($theme.LowRiskBadge)
			}
			$riskRow.Children.Add($riskVal) | Out-Null
			$stackPanel.Children.Add($riskRow) | Out-Null

			# Caution reason
			if ($Tweak.Caution -and $Tweak.CautionReason)
			{
				$tb = New-Object System.Windows.Controls.TextBlock
				$tb.Text = "Why this needs care: $($Tweak.CautionReason)"
				$tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
				$tb.FontSize = 11
				$tb.Foreground = $bc.ConvertFromString($theme.CautionText)
				$tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
				$stackPanel.Children.Add($tb) | Out-Null
			}

			# Restore row
			if ($Tweak.ContainsKey('Restorable'))
			{
				$sep2 = New-Object System.Windows.Controls.Separator
				$sep2.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
				$stackPanel.Children.Add($sep2) | Out-Null

				$restoreRow = New-Object System.Windows.Controls.StackPanel
				$restoreRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal

				$lbl = New-Object System.Windows.Controls.TextBlock
				$lbl.Text = 'Restore: '
				$lbl.Foreground = $bc.ConvertFromString($theme.TextMuted)
				$lbl.FontSize = 11
				$restoreRow.Children.Add($lbl) | Out-Null

				$val = New-Object System.Windows.Controls.TextBlock
				$val.FontWeight = [System.Windows.FontWeights]::SemiBold
				$val.FontSize = 11
				if ($Tweak.Restorable)
				{
					$val.Text = 'Possible'
					$val.Foreground = $bc.ConvertFromString($theme.ToggleOn)
				}
				else
				{
					$val.Text = 'Not possible - this change is permanent'
					$val.Foreground = $bc.ConvertFromString($theme.ToggleOff)
				}
				$restoreRow.Children.Add($val) | Out-Null
				$stackPanel.Children.Add($restoreRow) | Out-Null
			}
		}

		$icon = New-Object System.Windows.Controls.TextBlock
		$icon.Text = [char]0x24D8  # ⓘ
		$icon.FontSize = 14
		$icon.Foreground = $bc.ConvertFromString($theme.AccentBlue)
		$icon.VerticalAlignment = "Center"
		$icon.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$icon.Cursor = [System.Windows.Input.Cursors]::Help

		$tip = New-Object System.Windows.Controls.ToolTip
		$tip.Content = $stackPanel
		$tip.MaxWidth = 360
		$tip.Padding = [System.Windows.Thickness]::new(8, 6, 8, 6)
		$tip.Background = $bc.ConvertFromString($theme.CardBg)
		$tip.Foreground = $bc.ConvertFromString($theme.TextPrimary)
		$tip.BorderBrush = $bc.ConvertFromString($theme.CardBorder)
		$tip.BorderThickness = [System.Windows.Thickness]::new(1)
		$tip.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Custom
		$tip.HasDropShadow = $true
		$tip.StaysOpen = $true
		$tip.CustomPopupPlacementCallback = {
			param (
				[System.Windows.Size]$popupSize,
				[System.Windows.Size]$targetSize,
				[System.Windows.Point]$offset
			)

			$horizontalGap = 12
			$verticalGap = 8
			$belowPoint = [System.Windows.Point]::new(($targetSize.Width + $horizontalGap), $verticalGap)
			$leftBelowPoint = [System.Windows.Point]::new((-$popupSize.Width - $horizontalGap), $verticalGap)
			$abovePoint = [System.Windows.Point]::new(($targetSize.Width + $horizontalGap), (-$popupSize.Height + $targetSize.Height - $verticalGap))
			$leftAbovePoint = [System.Windows.Point]::new((-$popupSize.Width - $horizontalGap), (-$popupSize.Height + $targetSize.Height - $verticalGap))

			return @(
				[System.Windows.Controls.Primitives.CustomPopupPlacement]::new($belowPoint, [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Horizontal),
				[System.Windows.Controls.Primitives.CustomPopupPlacement]::new($leftBelowPoint, [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Horizontal),
				[System.Windows.Controls.Primitives.CustomPopupPlacement]::new($abovePoint, [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical),
				[System.Windows.Controls.Primitives.CustomPopupPlacement]::new($leftAbovePoint, [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical)
			)
		}.GetNewClosure()
		$icon.ToolTip = $tip

		# Close tooltip when mouse leaves the icon
		$icon.Add_MouseLeave({
			if ($tip.IsOpen) { $tip.IsOpen = $false }
		}.GetNewClosure())

		return $icon
	}

	function New-ImpactBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$border = New-Object System.Windows.Controls.Border
		$border.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ImpactBadgeBg -Context 'New-ImpactBadge/Background'
		$border.CornerRadius = [System.Windows.CornerRadius]::new(3)
		$border.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$border.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$border.VerticalAlignment = "Center"

		$txt = New-Object System.Windows.Controls.TextBlock
		$txt.Text = "Impact"
		$txt.FontSize = 10
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$txt.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.ImpactBadge -Context 'New-ImpactBadge/Foreground'

		$border.Child = $txt
		return $border
	}

	function New-RiskBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Level)
		$bc = New-SafeBrushConverter -Context 'New-RiskBadge'
		$border = New-Object System.Windows.Controls.Border
		$border.CornerRadius = [System.Windows.CornerRadius]::new(4)
		$border.Padding = [System.Windows.Thickness]::new(7, 2, 7, 2)
		$border.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$border.VerticalAlignment = "Center"
		$border.BorderThickness = [System.Windows.Thickness]::new(1)

		$txt = New-Object System.Windows.Controls.TextBlock
		$txt.FontSize = 10
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$riskLevel = if ([string]::IsNullOrWhiteSpace($Level)) { 'Low' } else { [string]$Level }

		if ($riskLevel -eq 'High')
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadge)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskHighBadge)
			$txt.Text = "High Risk"
		}
		elseif ($riskLevel -eq 'Medium')
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
			$txt.Text = "Medium Risk"
		}
		else
		{
			$border.Background = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadgeBg)
			$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadge)
			$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.LowRiskBadge)
			$txt.Text = "Low Risk"
		}

		$border.Child = $txt
		return $border
	}

	function New-StatusPill
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Text)
		if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
		$bc = New-SafeBrushConverter -Context 'New-StatusPill'
		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.StatusPillBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.StatusPillBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(999)
		$border.Margin = [System.Windows.Thickness]::new(12, 8, 12, 0)
		$border.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$border.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

		$txt = New-Object System.Windows.Controls.TextBlock
		$txt.Text = $Text
		$txt.FontSize = 11
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$txt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.StatusPillText)
		$border.Child = $txt
		return $border
	}

	function New-SectionHeader
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$Text)
		$lbl = New-Object System.Windows.Controls.TextBlock
		$lbl.Text = $Text.ToUpper()
		$lbl.FontSize = 11
		$lbl.FontWeight = [System.Windows.FontWeights]::Bold
		$lbl.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.SectionLabel -Context 'New-SectionHeader/Foreground'
		$lbl.Margin = [System.Windows.Thickness]::new(12, 16, 0, 6)
		return $lbl
	}

	function New-SearchResultsSummary
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Query,
			[int]$MatchCount
		)

		$bc = New-SafeBrushConverter -Context 'New-SectionHeaderCard'
		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.ActiveTabBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(8)
		$border.Margin = [System.Windows.Thickness]::new(8, 12, 8, 6)
		$border.Padding = [System.Windows.Thickness]::new(16, 14, 16, 14)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'

		$heading = New-Object System.Windows.Controls.TextBlock
		$heading.Text = 'SEARCH RESULTS'
		$heading.FontSize = 11
		$heading.FontWeight = [System.Windows.FontWeights]::Bold
		$heading.Foreground = $bc.ConvertFromString($Script:CurrentTheme.SectionLabel)
		$heading.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
		$stack.Children.Add($heading) | Out-Null

		$summary = New-Object System.Windows.Controls.TextBlock
		$summary.Text = "Showing $MatchCount tweak $(if ($MatchCount -eq 1) { 'match' } else { 'matches' }) for '$Query' across all tabs."
		$summary.TextWrapping = 'Wrap'
		$summary.FontSize = 13
		$summary.FontWeight = [System.Windows.FontWeights]::SemiBold
		$summary.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$stack.Children.Add($summary) | Out-Null

		$hint = New-Object System.Windows.Controls.TextBlock
		$hint.Text = 'Clear the search box to return to the normal tab view.'
		$hint.TextWrapping = 'Wrap'
		$hint.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$hint.FontSize = 11
		$hint.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$stack.Children.Add($hint) | Out-Null

		$border.Child = $stack
		return $border
	}

	function New-CautionSection
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([array]$CautionTweaks)
		if ($CautionTweaks.Count -eq 0) { return $null }
		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersBlock'

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CautionBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CautionBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$border.Margin = [System.Windows.Thickness]::new(8, 12, 8, 4)
		$border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = "Vertical"

		$headerGrid = New-Object System.Windows.Controls.Grid
		$headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
		$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
		$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

		$headerStack = New-Object System.Windows.Controls.StackPanel
		$headerStack.Orientation = 'Vertical'
		[System.Windows.Controls.Grid]::SetColumn($headerStack, 0)

		$header = New-Object System.Windows.Controls.TextBlock
		$header.Text = "CAUTION"
		$header.FontSize = 12
		$header.FontWeight = [System.Windows.FontWeights]::Bold
		$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
		$headerStack.Children.Add($header) | Out-Null

		$summary = New-Object System.Windows.Controls.TextBlock
		$summary.Text = "$($CautionTweaks.Count) tweak$(if ($CautionTweaks.Count -eq 1) { '' } else { 's' }) need extra care in this section."
		$summary.FontSize = 11
		$summary.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$summary.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		$headerStack.Children.Add($summary) | Out-Null

		$headerGrid.Children.Add($headerStack) | Out-Null

		$toggleButton = New-Object System.Windows.Controls.Button
		$toggleButton.Content = 'Show details'
		$toggleButton.FontSize = 11
		$toggleButton.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
		$toggleButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$toggleButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
		Set-ButtonChrome -Button $toggleButton -Variant 'Subtle' -Compact
		[System.Windows.Controls.Grid]::SetColumn($toggleButton, 1)
		$headerGrid.Children.Add($toggleButton) | Out-Null

		$stack.Children.Add($headerGrid) | Out-Null

		$detailsPanel = New-Object System.Windows.Controls.StackPanel
		$detailsPanel.Orientation = 'Vertical'
		$detailsPanel.Visibility = [System.Windows.Visibility]::Collapsed

		foreach ($ct in $CautionTweaks)
		{
			$reason = if ($ct.CautionReason) { $ct.CautionReason } else { "This tweak may have unintended side effects. Use with care." }
			$item = New-Object System.Windows.Controls.TextBlock
			$item.TextWrapping = "Wrap"
			$item.Margin = [System.Windows.Thickness]::new(0, 2, 0, 4)
			$item.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)

			$bold = New-Object System.Windows.Documents.Run
			$bold.Text = "$($ct.Name): "
			$bold.FontWeight = [System.Windows.FontWeights]::SemiBold
			$bold.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
			$item.Inlines.Add($bold) | Out-Null

			$desc = New-Object System.Windows.Documents.Run
			$desc.Text = $reason
			$item.Inlines.Add($desc) | Out-Null

			$detailsPanel.Children.Add($item) | Out-Null
		}

		$toggleButton.Add_Click({
			$showDetails = ($detailsPanel.Visibility -ne [System.Windows.Visibility]::Visible)
			$detailsPanel.Visibility = if ($showDetails) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
			$toggleButton.Content = if ($showDetails) { 'Hide details' } else { 'Show details' }
		}.GetNewClosure())

		$stack.Children.Add($detailsPanel) | Out-Null

		$border.Child = $stack
		return $border
	}

		function Add-ExecutionLogLine
		{
		param (
			[string]$Text,
			[string]$Level = 'INFO'
		)

		if ([string]::IsNullOrWhiteSpace($Text) -or -not $Script:ExecutionLogBox -or -not $Script:ExecutionLogBox.Document) { return }

		$bc = New-SafeBrushConverter -Context 'Add-ExecutionLogLine'
		$timestamp = Get-Date -Format 'HH:mm:ss'

		$para = New-Object System.Windows.Documents.Paragraph
		$para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
		$para.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
		$para.FontSize = 12

		$tsRun = New-Object System.Windows.Documents.Run
		$tsRun.Text = "[$timestamp] "
		$tsRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$para.Inlines.Add($tsRun) | Out-Null

		$levelRun = New-Object System.Windows.Documents.Run
		$levelRun.Text = "[$($Level.ToUpperInvariant())] "
		$levelRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
		$para.Inlines.Add($levelRun) | Out-Null

		$contentRun = New-Object System.Windows.Documents.Run
		$contentRun.Text = $Text
		$contentColor = switch ($Level.ToUpperInvariant())
		{
			'ERROR'   { $Script:CurrentTheme.CautionText }
			'WARNING' { $Script:CurrentTheme.RiskMediumBadge }
			default   { $Script:CurrentTheme.TextPrimary }
		}
		$contentRun.Foreground = $bc.ConvertFromString($contentColor)
		$para.Inlines.Add($contentRun) | Out-Null

		$Script:ExecutionLogBox.Document.Blocks.Add($para) | Out-Null

		$vO = $Script:ExecutionLogBox.VerticalOffset
		$vH = $Script:ExecutionLogBox.ViewportHeight
		$eH = $Script:ExecutionLogBox.ExtentHeight
		if (($vO + $vH) -ge ($eH - 30))
		{
			$Script:ExecutionLogBox.ScrollToEnd()
		}
			$Form.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
		}

		function Test-ExecutionSkipMessage
		{
			param(
				[string]$Message
			)

			if ([string]::IsNullOrWhiteSpace($Message)) { return $false }

			return ($Message -match '(?i)\bskipping\b|\bskipped\b')
		}

		    # Scriptblock stored in Script: scope so all closures and timer ticks can access it directly.
    # Simple: takes completed count, total count, and what's currently running.
    $Script:UpdateProgressFn = {
        param (
            [int]$Completed,
            [int]$Total,
            [string]$CurrentAction,
            [int]$SubCompleted = -1,
            [int]$SubTotal = 0,
            [string]$SubAction = $null,
            [switch]$ClearSub
        )

        if ($Script:ExecutionProgressBar)
        {
            if ($Total -gt 0)
            {
                $Script:ExecutionProgressBar.Maximum = $Total
                $Script:ExecutionProgressIndeterminate = ($Completed -le 0 -and $CurrentAction -notin @('Done', 'Aborted'))
                $Script:ExecutionProgressBar.IsIndeterminate = $Script:ExecutionProgressIndeterminate
                $Script:ExecutionProgressBar.Value   = [Math]::Min($Completed, $Total)
            }
            else
            {
                $Script:ExecutionProgressIndeterminate = $false
                $Script:ExecutionProgressBar.IsIndeterminate = $false
                $Script:ExecutionProgressBar.Value = 0
            }
        }

        if ($Script:ExecutionProgressText)
        {
            if ($Total -gt 0)
            {
                $pct = [Math]::Round(($Completed / $Total) * 100)
                $text = "{0}/{1} ({2}%)" -f $Completed, $Total, $pct
                if (-not [string]::IsNullOrWhiteSpace($CurrentAction))
                {
                    $text += " - $CurrentAction"
                }
                $Script:ExecutionProgressText.Text = $text
            }
            else
            {
                $Script:ExecutionProgressText.Text = if ($CurrentAction) { $CurrentAction } else { 'Preparing...' }
            }
        }

		# Sub-progress bar (downloads, installs, etc. reported by tweak functions)
		if ($Script:ExecutionSubProgressBar)
		{
			if ($ClearSub)
			{
				$Script:ExecutionSubProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
				if ($Script:ExecutionSubProgressText) { $Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Collapsed }
			}
			elseif ($SubTotal -gt 0)
			{
				$Script:ExecutionSubProgressBar.Visibility  = [System.Windows.Visibility]::Visible
				$Script:ExecutionSubProgressBar.Maximum     = $SubTotal
				$Script:ExecutionSubProgressBar.Value       = [Math]::Min($SubCompleted, $SubTotal)
				$Script:ExecutionSubProgressBar.IsIndeterminate = $false
				if ($Script:ExecutionSubProgressText)
				{
					$Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Visible
					$pct = [Math]::Round(($SubCompleted / $SubTotal) * 100)
					$Script:ExecutionSubProgressText.Text = if ($SubAction) { "$SubAction  ($pct%)" } else { "$pct%" }
				}
			}
			elseif ($SubCompleted -ge 0 -and $SubTotal -le 0)
			{
				# Unknown total - show indeterminate sub-bar
				$Script:ExecutionSubProgressBar.Visibility = [System.Windows.Visibility]::Visible
				$Script:ExecutionSubProgressBar.IsIndeterminate = $true
				if ($Script:ExecutionSubProgressText)
				{
					$Script:ExecutionSubProgressText.Visibility = [System.Windows.Visibility]::Visible
					$Script:ExecutionSubProgressText.Text = if ($SubAction) { $SubAction } else { "Working..." }
				}
			}
		}
	}

	function Invoke-GuiEvents
	{
		$frame = New-Object System.Windows.Threading.DispatcherFrame
$null = $Form.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherOperationCallback]{
                param($state)
                $state.Continue = $false
                return $null
        },
        [System.Windows.Threading.DispatcherPriority]::Background,
        $frame
)
		[System.Windows.Threading.Dispatcher]::PushFrame($frame)
	}

	$Script:ForceCloseExecutionFn = {
		$timerToStop = $Script:ExecutionRunTimer
		$workerToStop = $Script:ExecutionWorker

		Clear-UILogHandler
		Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue

		if ($Script:RunState)
		{
			$Script:RunState['AbortRequested'] = $true
			$Script:RunState['AbortRequestedAt'] = Get-Date
			$Script:RunState['AbortedRun'] = $true
			$Script:RunState['Done'] = $true
		}

		if ($timerToStop)
		{
			try { $timerToStop.Stop() } catch { $null = $_ }
		}

		$Script:ExecutionRunTimer = $null
		$Script:ExecutionWorker = $null
		$Script:ExecutionRunPowerShell = $null
		$Script:ExecutionRunspace = $null
		$Script:BgPS = $null
		$Script:BgAsync = $null
		$Script:RunInProgress = $false
		$Script:SuppressRunClosePrompt = $true

		if ($Script:MainForm)
		{
			try
			{
$null = $Script:MainForm.Dispatcher.BeginInvoke(
        [System.Action]{
                try { $Script:MainForm.Close() } catch { $null = $_ }
                try
                {
                        if ([System.Windows.Application]::Current)
                        {
                                [System.Windows.Application]::Current.Shutdown()
                        }
                }
                catch { $null = $_ }
        },
        [System.Windows.Threading.DispatcherPriority]::Send
)
			}
			catch
			{
				try { $Script:MainForm.Close() } catch { $null = $_ }
			}
		}

		if ($workerToStop)
		{
			GUIExecution\Stop-GuiExecutionWorkerAsync -Worker $workerToStop
		}
	}

	$Script:RequestRunAbortFn = {
		param(
			[switch]$ExitNow
		)

		if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

		$Script:AbortRequested = $true
		if ($Script:AbortRunButton)
		{
			$Script:AbortRunButton.Content = "Aborting..."
			$Script:AbortRunButton.IsEnabled = $false
		}
		if ($BtnRun)
		{
			$BtnRun.Content = if ($ExitNow) { "Exiting..." } else { "Stopping..." }
			$BtnRun.IsEnabled = $false
		}
		$StatusText.Text = if ($ExitNow) { "Exit requested. Closing Baseline now..." } else { "Abort requested. Waiting for the current step to stop..." }
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
		LogWarning 'Abort requested by user - waiting for the current step to stop.'

		if ($Script:RunState)
		{
			$Script:RunState['AbortRequested'] = $true
			$Script:RunState['AbortRequestedAt'] = Get-Date
			$Script:RunState['AbortedRun'] = $true
		}

		if ($ExitNow)
		{
			LogWarning 'Exit requested by user - closing Baseline now.'
			& $Script:ForceCloseExecutionFn
			return
		}
	}

	$Script:PromptRunAbortFn = {
		if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

		$Script:AbortDialogShowing = $true
		try
		{
			$choice = Show-ThemedDialog -Title 'Abort Run' `
			-Message "Stop the current run now?`n`nReturn to Tweaks aborts the run and keeps the app open. Exit Now force-stops the run and closes Baseline immediately." `
			-Buttons @('Return to Tweaks', 'Exit Now', 'Cancel') `
			-AccentButton 'Return to Tweaks' `
			-DestructiveButton 'Exit Now'
			Write-Host ("Abort dialog choice: '{0}'" -f $(if ($null -eq $choice) { '<null>' } else { [string]$choice }))
		}
		finally
		{
			$Script:AbortDialogShowing = $false
		}

		if (-not $Script:RunInProgress)
		{
			# Run completed while the dialog was open — nothing to abort
			return
		}

		switch ($choice)
		{
			'Return to Tweaks'
			{
				$Script:RunAbortDisposition = 'Return'
				& $Script:RequestRunAbortFn
			}
			'Exit Now'
			{
				$Script:RunAbortDisposition = 'Exit'
				& $Script:RequestRunAbortFn -ExitNow
			}
			default
			{
				$Script:RunAbortDisposition = $null
			}
		}
	}

   function Enter-ExecutionView
    {
        param ([string]$Title)

	        $bc = New-SafeBrushConverter -Context 'Enter-ExecutionView'
        $Script:ExecutionPreviousContent = $ContentScroll.Content
        $Script:ExecutionPreviousScrollMode = $ContentScroll.VerticalScrollBarVisibility

        # Use a Grid so the header/progress stay fixed and only the log scrolls
        $outerGrid = New-Object System.Windows.Controls.Grid
        $outerGrid.Margin = [System.Windows.Thickness]::new(12)
        $rowHeader = New-Object System.Windows.Controls.RowDefinition
        $rowHeader.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
        $rowLog = New-Object System.Windows.Controls.RowDefinition
        $rowLog.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $outerGrid.RowDefinitions.Add($rowHeader) | Out-Null
        $outerGrid.RowDefinitions.Add($rowLog) | Out-Null

        # Top section: heading + subheading + progress bar + abort button
        $topPanel = New-Object System.Windows.Controls.StackPanel
        $topPanel.Orientation = 'Vertical'
        [System.Windows.Controls.Grid]::SetRow($topPanel, 0)

        $heading = New-Object System.Windows.Controls.TextBlock
        $heading.Text = $Title
        $heading.FontSize = 18
        $heading.FontWeight = [System.Windows.FontWeights]::Bold
        $heading.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
        $heading.Margin = [System.Windows.Thickness]::new(0,0,0,6)
        $topPanel.Children.Add($heading) | Out-Null

        $subheading = New-Object System.Windows.Controls.TextBlock
        $subheading.Text = "Progress will appear here live. Please keep this window open until completion."
        $subheading.FontSize = 12
        $subheading.TextWrapping = "Wrap"
        $subheading.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
        $subheading.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        $topPanel.Children.Add($subheading) | Out-Null

        $progressGrid = New-Object System.Windows.Controls.Grid
        $progressGrid.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        $progressCol1 = New-Object System.Windows.Controls.ColumnDefinition
        $progressCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $progressCol2 = New-Object System.Windows.Controls.ColumnDefinition
        $progressCol2.Width = [System.Windows.GridLength]::new(124, [System.Windows.GridUnitType]::Pixel)
        $progressGrid.ColumnDefinitions.Add($progressCol1) | Out-Null
        $progressGrid.ColumnDefinitions.Add($progressCol2) | Out-Null

        $progressStack = New-Object System.Windows.Controls.StackPanel
        $progressStack.Orientation = 'Vertical'
        $progressStack.Margin = [System.Windows.Thickness]::new(0,0,12,0)
        [System.Windows.Controls.Grid]::SetColumn($progressStack, 0)

        # Single progress bar - determinate, 0 to Total
        $progressBar = New-Object System.Windows.Controls.ProgressBar
        $progressBar.Minimum = 0
        $progressBar.Maximum = 1
        $progressBar.Value = 0
        $progressBar.Height = 18
        $progressBar.MinWidth = 200
        $progressBar.IsIndeterminate = $false
        $progressBar.Margin = [System.Windows.Thickness]::new(0,0,0,6)
        $progressBar.HorizontalAlignment = 'Stretch'
        $progressStack.Children.Add($progressBar) | Out-Null

        # Single status line: "3/12 - Installing PowerShell 7"
        $progressText = New-Object System.Windows.Controls.TextBlock
        $progressText.FontSize = 12
        $progressText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
        $progressText.Text = 'Preparing...'
        $progressText.TextWrapping = 'NoWrap'
        $progressText.TextTrimming = 'CharacterEllipsis'
        $progressText.HorizontalAlignment = 'Stretch'
        $progressStack.Children.Add($progressText) | Out-Null
        $progressGrid.Children.Add($progressStack) | Out-Null

        $abortBtnHost = New-Object System.Windows.Controls.Border
        $abortBtnHost.Padding = [System.Windows.Thickness]::new(0)
        $abortBtnHost.HorizontalAlignment = 'Right'
        $abortBtnHost.VerticalAlignment = 'Top'
        [System.Windows.Controls.Grid]::SetColumn($abortBtnHost, 1)

        $abortBtn = New-Object System.Windows.Controls.Button
        $abortBtn.Content = 'Abort'
        $abortBtn.MinWidth = 104
        $abortBtn.Height = 40
        $abortBtn.Padding = [System.Windows.Thickness]::new(18,8,18,8)
        $abortBtn.HorizontalAlignment = 'Stretch'
        $abortBtn.VerticalAlignment = 'Top'
        $abortBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $abortBtn.TabIndex = 0
        $abortBtn.Add_Click({ & $Script:PromptRunAbortFn })
        Set-ButtonChrome -Button $abortBtn -Variant 'Danger'
        $abortBtnHost.Child = $abortBtn
        $progressGrid.Children.Add($abortBtnHost) | Out-Null

        $topPanel.Children.Add($progressGrid) | Out-Null
        $outerGrid.Children.Add($topPanel) | Out-Null

        # Bottom section: scrollable rich log box (fills remaining space)
        $logBox = New-Object System.Windows.Controls.RichTextBox
        $logBox.IsReadOnly = $true
        $logBox.VerticalScrollBarVisibility = 'Auto'
        $logBox.HorizontalScrollBarVisibility = 'Disabled'
        $logBox.BorderThickness = [System.Windows.Thickness]::new(0)
        $logBox.Padding = [System.Windows.Thickness]::new(12)
        $logBox.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
        $logBox.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
        $logBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
        $logBox.FontSize = 12
        $logBox.TabIndex = 1
        $flowDoc = New-Object System.Windows.Documents.FlowDocument
        $flowDoc.PagePadding = [System.Windows.Thickness]::new(0)
        $flowDoc.LineHeight = 1
        $logBox.Document = $flowDoc
        [System.Windows.Controls.Grid]::SetRow($logBox, 1)
        $outerGrid.Children.Add($logBox) | Out-Null

        # Disable outer ScrollViewer scrolling - the logBox handles its own
        $ContentScroll.VerticalScrollBarVisibility = 'Disabled'
        $ContentScroll.Content = $outerGrid
        $Script:ExecutionLogBox = $logBox
        $Script:ExecutionLastConsoleAction = $null
        $Script:ExecutionProgressBar = $progressBar
        $Script:ExecutionProgressText = $progressText
        $Script:AbortRunButton = $abortBtn
        $Script:AbortRequested = $false
        $Script:RunAbortDisposition = $null
        $Script:ExecutionWorker = $null
        $Script:ExecutionRunspace = $null
        $Script:ExecutionRunPowerShell = $null
        $Script:ExecutionRunTimer = $null
        $Script:ExecutionTimerErrorShown = $false
        $Script:SuppressRunClosePrompt = $false
        $Script:BgPS = $null
        $Script:BgAsync = $null
        # Hide filter bar and tab bar during execution
        $PrimaryTabs.Visibility = [System.Windows.Visibility]::Collapsed
        $HeaderBorder.Visibility = [System.Windows.Visibility]::Collapsed
        # Hide bottom action buttons during execution
        if ($ActionButtonBar) { $ActionButtonBar.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($StatusText) { $StatusText.Visibility = [System.Windows.Visibility]::Collapsed }
        $abortBtn.Focus() | Out-Null
    }

	    function Exit-ExecutionView
	    {
			Write-Host "[Exit-ExecutionView] ENTERED - restoring GUI"
	        $Script:ExecutionLogBox = $null
	        $Script:ExecutionLastConsoleAction = $null
        $Script:ExecutionProgressBar = $null
        $Script:ExecutionProgressText = $null
        $Script:AbortRunButton = $null
        $Script:AbortRequested = $false
        $Script:RunAbortDisposition = $null
        $Script:ExecutionWorker = $null
        $Script:ExecutionRunspace = $null
        $Script:ExecutionRunPowerShell = $null
        $Script:ExecutionRunTimer = $null
        $Script:ExecutionTimerErrorShown = $false
	        $Script:BgPS = $null
	        $Script:BgAsync = $null
	        $Script:ExecutionPreviousContent = $null
	        $Script:ExecutionCurrentSummaryKey = $null
	        $Script:ExecutionMode = $null

	        # Restore the outer ScrollViewer scrolling mode
	        $ContentScroll.VerticalScrollBarVisibility = 'Auto'

        # Reset run state
        $Script:RunInProgress = $false

        # Restore filter bar and tab bar
        $PrimaryTabs.Visibility = [System.Windows.Visibility]::Visible
        $PrimaryTabs.IsEnabled = $true
        $HeaderBorder.Visibility = [System.Windows.Visibility]::Visible
        # Restore bottom action buttons
        if ($ActionButtonBar) { $ActionButtonBar.Visibility = [System.Windows.Visibility]::Visible }
        if ($BtnPreviewRun) { $BtnPreviewRun.Visibility = [System.Windows.Visibility]::Visible; $BtnPreviewRun.IsEnabled = $true }
        if ($StatusText) { $StatusText.Visibility = [System.Windows.Visibility]::Visible }
        # Re-enable controls
        if ($BtnRun) { $BtnRun.Content = 'Run Tweaks'; $BtnRun.IsEnabled = $true }
        if ($BtnDefaults) { $BtnDefaults.IsEnabled = $true }
        Set-GuiActionButtonsEnabled -Enabled $true
        if ($ChkScan) { $ChkScan.IsEnabled = $true }
        if ($ChkTheme) { $ChkTheme.IsEnabled = $true }
        Set-SearchControlsEnabled -Enabled $true

        if ($Script:CurrentPrimaryTab)
        {
            Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
        }
		Write-Host "[Exit-ExecutionView] COMPLETED - GUI restored"
    }

	function Invoke-GuiSystemScan
	{
		$Script:ScanEnabled = $true
		$StatusText.Text = "Scanning system state..."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		$Form.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

		$matchCount = 0
		$scannable  = 0
		$sessionApplied = 0

		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			if ($sctl) { $sctl.IsEnabled = $true }
		}

		for ($si = 0; $si -lt $Script:TweakManifest.Count; $si++)
		{
			$st   = $Script:TweakManifest[$si]
			$sctl = $Script:Controls[$si]

			if (-not $sctl) { continue }

			if ($Script:AppliedTweaks.Contains($st.Function))
			{
				$sctl.IsEnabled = $false
				if ($sctl.PSObject.Properties['IsChecked']) { $sctl.IsChecked = $false }
				$matchCount++
				$sessionApplied++
				continue
			}

			if ($st.Scannable -eq $false -or -not $st.Detect) { continue }
			$scannable++

			$currentlyOn = $false
			try { $currentlyOn = [bool](& $st.Detect) } catch { $currentlyOn = $false }

			if ($currentlyOn -eq [bool]$st.Default)
			{
				$sctl.IsEnabled = $false
				if ($sctl.PSObject.Properties['IsChecked']) { $sctl.IsChecked = $false }
				$matchCount++
			}
		}

		$scanMsg = if ($sessionApplied -gt 0) {
			"Scan complete - $matchCount tweaks disabled, including $sessionApplied already run in this session."
		} elseif ($matchCount -gt 0) {
			"Scan complete - $matchCount of $scannable tweaks already match their configured state."
		} else {
			"Scan complete - $scannable tweaks checked, none already applied."
		}

		$StatusText.Text = $scanMsg
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)

		if ($Script:CurrentPrimaryTab) { Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab }
	}

	function Get-SelectedTweakRunList
	{
		$selectedTweaks = [System.Collections.Generic.List[hashtable]]::new()

		for ($ri = 0; $ri -lt $Script:TweakManifest.Count; $ri++)
		{
			$rt = $Script:TweakManifest[$ri]
			$rctl = $Script:Controls[$ri]
			if (-not $rctl -or -not $rctl.IsEnabled) { continue }

				switch ($rt.Type)
				{
					'Toggle'
					{
						if ($rctl.IsChecked)
						{
							$selectedParam = $rt.OnParam
							if ([string]::IsNullOrWhiteSpace([string]$selectedParam)) { continue }
							$selectedTweaks.Add(@{
								Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Toggle'
							Category  = $rt.Category
							Risk      = $rt.Risk
							RequiresRestart = [bool]$rt.RequiresRestart
							Selection = [string]$selectedParam
							OnParam   = [string]$selectedParam
							ExtraArgs = $null
						})
					}
				}
				'Choice'
				{
					$selIdx = $rctl.SelectedIndex
					if ($selIdx -ge 0)
					{
						$displayOpts = if ($rt.DisplayOptions) { $rt.DisplayOptions } else { $rt.Options }
						$selectedTweaks.Add(@{
							Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Choice'
							Category  = $rt.Category
							Risk      = $rt.Risk
							RequiresRestart = [bool]$rt.RequiresRestart
							Selection = [string]$displayOpts[$selIdx]
							Value     = $rt.Options[$selIdx]
							ExtraArgs = $rt.ExtraArgs
						})
					}
				}
				'Action'
				{
					if ($rctl.IsChecked)
					{
						$selectedTweaks.Add(@{
							Key       = [string]$ri
							Index     = $ri
							Name      = $rt.Name
							Function  = $rt.Function
							Type      = 'Action'
							Category  = $rt.Category
							Risk      = $rt.Risk
							RequiresRestart = [bool]$rt.RequiresRestart
							Selection = if ($rt.Name) { [string]$rt.Name } else { 'Run action' }
							ExtraArgs = $rt.ExtraArgs
						})
					}
				}
			}
		}

		return $selectedTweaks
	}

	function Get-WindowsDefaultRunList
	{
		$defaultTweaks = [System.Collections.Generic.List[hashtable]]::new()

		for ($ri = 0; $ri -lt $Script:TweakManifest.Count; $ri++)
		{
			$rt = $Script:TweakManifest[$ri]
			$rctl = $Script:Controls[$ri]
			if (-not $rctl) { continue }
			if ($null -ne $rt.Restorable -and -not $rt.Restorable) { continue }

			switch ($rt.Type)
			{
				'Toggle'
				{
					$defaultParam = if ([bool]$rt.WinDefault) { $rt.OnParam } else { $rt.OffParam }
					if ([string]::IsNullOrWhiteSpace([string]$defaultParam)) { continue }

					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Toggle'
						Category        = $rt.Category
						Risk            = $rt.Risk
						RequiresRestart = [bool]$rt.RequiresRestart
						Selection       = if ([bool]$rt.WinDefault) { 'Windows default: Enabled' } else { 'Windows default: Disabled' }
						OnParam         = $defaultParam
						WinDefault      = [bool]$rt.WinDefault
						ExtraArgs       = $null
					})
				}
				'Choice'
				{
					if ([string]::IsNullOrWhiteSpace([string]$rt.WinDefault)) { continue }
					$defaultIndex = [array]::IndexOf($rt.Options, $rt.WinDefault)
					if ($defaultIndex -lt 0) { continue }

					$displayOpts = if ($rt.DisplayOptions) { $rt.DisplayOptions } else { $rt.Options }
					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Choice'
						Category        = $rt.Category
						Risk            = $rt.Risk
						RequiresRestart = [bool]$rt.RequiresRestart
						Selection       = "Windows default: $([string]$displayOpts[$defaultIndex])"
						Value           = $rt.Options[$defaultIndex]
						WinDefault      = [string]$rt.WinDefault
						WinDefaultIndex = $defaultIndex
						ExtraArgs       = $rt.ExtraArgs
					})
				}
				'Action'
				{
					if (-not $rt.WinDefault) { continue }

					$defaultTweaks.Add(@{
						Key             = [string]$ri
						Index           = $ri
						Name            = $rt.Name
						Function        = $rt.Function
						Type            = 'Action'
						Category        = $rt.Category
						Risk            = $rt.Risk
						RequiresRestart = [bool]$rt.RequiresRestart
						Selection       = 'Run Windows default action'
						WinDefault      = [bool]$rt.WinDefault
						ExtraArgs       = $rt.ExtraArgs
					})
				}
			}
		}

		return $defaultTweaks
	}

	function Confirm-HighRiskTweakRun
	{
		param ([object[]]$SelectedTweaks)

		$highRiskTweaks = @(
			@($SelectedTweaks) |
				Where-Object { $_ -and [string]$_.Risk -eq 'High' }
		)
		if ($highRiskTweaks.Count -eq 0) { return $true }

		$preview = @($highRiskTweaks | Select-Object -First 10)
		$listText = if ($preview.Count -gt 0) {
			($preview | ForEach-Object { "- [{0}] {1}" -f [string]$_.Category, [string]$_.Name }) -join "`n"
		} else {
			'- Review the selected tweaks before continuing.'
		}
		if ($highRiskTweaks.Count -gt $preview.Count)
		{
			$listText += "`n- and $($highRiskTweaks.Count - $preview.Count) more..."
		}

		$message = "You selected $($highRiskTweaks.Count) high-risk tweak$(if ($highRiskTweaks.Count -eq 1) { '' } else { 's' }).`n`nThese changes may be destructive, aggressive, or harder to undo.`n`nHigh-risk selections:`n$listText"
		$choice = Show-ThemedDialog -Title 'Confirm High-Risk Tweaks' `
			-Message $message `
			-Buttons @('Cancel', 'Run High-Risk Tweaks') `
			-DestructiveButton 'Run High-Risk Tweaks'

		return ($choice -eq 'Run High-Risk Tweaks')
	}

	function Get-ExecutionPreviewResults
	{
		param ([object[]]$SelectedTweaks)

		$previewResults = New-Object System.Collections.ArrayList
		$order = 0
		foreach ($tweak in @($SelectedTweaks))
		{
			$order++
			$actionDesc = switch ([string]$tweak.Type)
			{
				'Toggle' { "Set {0}" -f $(if ($tweak.OnParam) { [string]$tweak.OnParam } else { 'Enabled' }) }
				'Choice' { "Apply setting: {0}" -f [string]$tweak.Selection }
				'Action' { "Run one-time action" }
				default  { [string]$tweak.Selection }
			}
			$detailParts = @("Preview only. No changes were applied.", "Action: $actionDesc")
			if ([bool]$tweak.RequiresRestart)
			{
				$detailParts += 'May require a restart after the real run.'
			}
			if ([string]$tweak.Risk -eq 'High')
			{
				$detailParts += 'High-risk tweak. Review carefully before running.'
			}

			[void]$previewResults.Add([PSCustomObject]@{
				Key             = [string]$tweak.Key
				Order           = $order
				Name            = [string]$tweak.Name
				Category        = [string]$tweak.Category
				Risk            = [string]$tweak.Risk
				Type            = [string]$tweak.Type
				Selection       = [string]$tweak.Selection
				RequiresRestart = [bool]$tweak.RequiresRestart
				Status          = 'Preview'
				Detail          = ($detailParts -join ' ')
			})
		}

		return @($previewResults | Sort-Object Order)
	}

	function Write-ExecutionPreviewToLog
	{
		param ([object[]]$Results)

		$results = @($Results)
		$selectedCount = $results.Count
		$highRiskCount = @($results | Where-Object Risk -eq 'High').Count
		$restartCount = @($results | Where-Object RequiresRestart).Count

		LogInfo "Preview summary: Selected=$selectedCount, HighRisk=$highRiskCount, RequiresRestart=$restartCount. No changes were applied."

		foreach ($result in $results)
		{
			$selectionLabel = if ([string]::IsNullOrWhiteSpace([string]$result.Selection)) { '' } else { " | $($result.Selection)" }
			$detailSuffix = if ([string]::IsNullOrWhiteSpace([string]$result.Detail)) { '' } else { " | $($result.Detail)" }
			LogInfo ("Preview item | [{0}] {1}{2}{3}" -f $result.Category, $result.Name, $selectionLabel, $detailSuffix)
		}
	}

	function Initialize-ExecutionSummary
	{
		param ([object[]]$SelectedTweaks)

		$Script:ExecutionSummaryRecords = New-Object System.Collections.ArrayList
		$Script:ExecutionSummaryLookup = @{}
		$Script:ExecutionCurrentSummaryKey = $null

		$order = 0
		foreach ($tweak in @($SelectedTweaks))
		{
			$order++
			$record = [PSCustomObject]@{
				Key       = [string]$tweak.Key
				Order     = $order
				Name      = [string]$tweak.Name
				Category  = [string]$tweak.Category
				Risk      = [string]$tweak.Risk
				Type      = [string]$tweak.Type
				Selection = [string]$tweak.Selection
				Status    = 'Pending'
				Detail    = $null
			}
			[void]$Script:ExecutionSummaryRecords.Add($record)
			$Script:ExecutionSummaryLookup[[string]$tweak.Key] = $record
		}
	}

	function Set-ExecutionSummaryStatus
	{
		param (
			[string]$Key,
			[string]$Status,
			[string]$Detail = $null
		)

		if ([string]::IsNullOrWhiteSpace($Key)) { return }
		$record = $Script:ExecutionSummaryLookup[$Key]
		if (-not $record) { return }

		$record.Status = $Status
		if (-not [string]::IsNullOrWhiteSpace($Detail))
		{
			$record.Detail = $Detail.Trim()
		}
		elseif ($Status -eq 'Success')
		{
			$record.Detail = $null
		}
		elseif ($Status -eq 'Skipped' -and [string]::IsNullOrWhiteSpace([string]$record.Detail))
		{
			$record.Detail = 'Skipped because the system already matched the requested state.'
		}
	}

	function Complete-ExecutionSummary
	{
		param (
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null
		)

		foreach ($record in @($Script:ExecutionSummaryRecords))
		{
			if ($record.Status -in @('Pending', 'Running'))
			{
				$record.Status = 'Not Run'
				if ([string]::IsNullOrWhiteSpace([string]$record.Detail))
				{
					$record.Detail = if ($AbortedRun) {
						'Run was aborted before this tweak completed.'
					}
					elseif (-not [string]::IsNullOrWhiteSpace($FatalError)) {
						'Run stopped before this tweak could complete because of a fatal error.'
					}
					else {
						'This tweak did not produce a final result.'
					}
				}
			}
		}
	}

	function Get-ExecutionSummaryResults
	{
		return @($Script:ExecutionSummaryRecords | Sort-Object Order)
	}

	function Write-ExecutionSummaryToLog
	{
		param (
			[object[]]$Results,
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null
		)

		$results = @($Results)
		$successCount = @($results | Where-Object Status -eq 'Success').Count
		$failedCount = @($results | Where-Object Status -eq 'Failed').Count
		$skippedCount = @($results | Where-Object Status -eq 'Skipped').Count
		$notRunCount = @($results | Where-Object Status -eq 'Not Run').Count

		$summaryLine = "Execution summary: Success=$successCount, Failed=$failedCount, Skipped=$skippedCount, NotRun=$notRunCount."
		if ($AbortedRun)
		{
			LogWarning "$summaryLine Run aborted by user."
		}
		elseif (-not [string]::IsNullOrWhiteSpace($FatalError))
		{
			LogError "$summaryLine Fatal error: $FatalError"
		}
		elseif ($failedCount -gt 0 -or $notRunCount -gt 0)
		{
			LogWarning $summaryLine
		}
		else
		{
			LogInfo $summaryLine
		}

		foreach ($result in $results)
		{
			$detailSuffix = if ([string]::IsNullOrWhiteSpace([string]$result.Detail)) { '' } else { " | $($result.Detail)" }
			$selectionLabel = if ([string]::IsNullOrWhiteSpace([string]$result.Selection)) { '' } else { " | $($result.Selection)" }
			$line = "Run summary | $($result.Status) | [$($result.Category)] $($result.Name)$selectionLabel$detailSuffix"
			switch ($result.Status)
			{
				'Failed' { LogError $line }
				'Skipped' { LogWarning $line }
				'Not Run' { LogWarning $line }
				default { LogInfo $line }
			}
		}
	}

	function Sync-DefaultsControlsFromExecutionSummary
	{
		param ([object[]]$Results)

		foreach ($result in @($Results | Where-Object Status -eq 'Success'))
		{
			if ([string]::IsNullOrWhiteSpace([string]$result.Key)) { continue }

			$ctlKey = [int]$result.Key
			$ctl = $Script:Controls[$ctlKey]
			$twk = $Script:TweakManifest[$ctlKey]
			if (-not $ctl -or -not $twk) { continue }

			if ($ctl.PSObject.Properties['IsChecked'])
			{
				$ctl.IsChecked = [bool]$twk.WinDefault
			}
			elseif ($ctl.PSObject.Properties['SelectedIndex'])
			{
				$winDefIdx = [array]::IndexOf($twk.Options, $twk.WinDefault)
				if ($winDefIdx -ge 0) { $ctl.SelectedIndex = $winDefIdx }
			}
		}
	}

	function Complete-GuiExecutionRun
	{
		param (
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[int]$CompletedCount,
			[bool]$AbortedRun = $false,
			[string]$FatalError = $null,
			[object[]]$ExecutionSummary,
			[string]$LogPath
		)

		$executionSummary = @($ExecutionSummary)
		$successCount = @($executionSummary | Where-Object Status -eq 'Success').Count
		$failedCount = @($executionSummary | Where-Object Status -eq 'Failed').Count
		$skippedCount = @($executionSummary | Where-Object Status -eq 'Skipped').Count
		$notRunCount = @($executionSummary | Where-Object Status -eq 'Not Run').Count

		if ($Mode -eq 'Defaults')
		{
			$summaryCountsText = "Success: $successCount. Failed: $failedCount. Skipped: $skippedCount."
			if ($notRunCount -gt 0) { $summaryCountsText += " Not run: $notRunCount." }

			Sync-DefaultsControlsFromExecutionSummary -Results $executionSummary
			if ($Script:CurrentPrimaryTab)
			{
				Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
			}

			$finalLabel = if ($AbortedRun) { 'Aborted' } elseif ($FatalError) { 'Failed' } elseif ($failedCount -gt 0) { 'Done With Errors' } else { 'Done' }
			& $Script:UpdateProgressFn -Completed $CompletedCount -Total $Script:TotalRunnableTweaks -CurrentAction $finalLabel

			if ($AbortedRun)
			{
				$rawRunAbortDisposition = if ($null -eq $Script:RunAbortDisposition) { '<null>' } else { [string]$Script:RunAbortDisposition }
				$runAbortDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition)) { 'Return' } else { [string]$Script:RunAbortDisposition }
				Write-Host ("[Complete-Defaults] AbortedRun=true, RunAbortDisposition={0}, EffectiveDisposition={1}" -f $rawRunAbortDisposition, $runAbortDisposition)
				$StatusText.Text = "Windows defaults restore aborted. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
				$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)

				if ($runAbortDisposition -eq 'Exit')
				{
					$Script:MainForm.Close()
				}
				else
				{
					Exit-ExecutionView
				}
				return
			}

			if ($FatalError)
			{
				$StatusText.Text = "Windows defaults restore failed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Review the summary dialog or log file."
				$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
			}
			elseif ($failedCount -gt 0)
			{
				$StatusText.Text = "Windows defaults restore finished with errors. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Review the summary dialog or log file."
				$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
			}
			else
			{
				$StatusText.Text = "Windows defaults restored. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
				$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.ToggleOn)
			}

			if ($FatalError -or $failedCount -gt 0 -or $notRunCount -gt 0)
			{
				$dlgTitle = if ($FatalError) { 'Defaults Restore Failed' } else { 'Defaults Restore Finished With Errors' }
				$dlgMessage = if ($FatalError) {
					"The defaults restore stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
				}
				else {
					"Windows defaults restore finished with errors.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
				}
				Show-ExecutionSummaryDialog -Title $dlgTitle `
					-SummaryText $dlgMessage `
					-Results $executionSummary `
					-LogPath $LogPath `
					-Buttons @('Close') | Out-Null
			}

			Exit-ExecutionView
			return
		}

		$summaryCountsText = "Success: $successCount. Failed: $failedCount. Skipped: $skippedCount."
		if ($notRunCount -gt 0) { $summaryCountsText += " Not run: $notRunCount." }

		$finalLabel = if ($AbortedRun) { 'Aborted' } elseif ($FatalError) { 'Failed' } elseif ($failedCount -gt 0) { 'Done With Errors' } else { 'Done' }
		& $Script:UpdateProgressFn -Completed $CompletedCount -Total $Script:TotalRunnableTweaks -CurrentAction $finalLabel

		$StatusText.Text = if ($AbortedRun) {
			"Run aborted. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
		} elseif ($FatalError) {
			"Run failed. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Review the summary dialog or log file."
		} elseif ($failedCount -gt 0) {
			"Run finished with errors. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText Review the summary dialog or log file."
		} else {
			"Run complete. Completed $CompletedCount of $Script:TotalRunnableTweaks. $summaryCountsText"
		}
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($AbortedRun -or $FatalError -or $failedCount -gt 0) { $Script:CurrentTheme.CautionText } else { $Script:CurrentTheme.ToggleOn }))

		if ($AbortedRun)
		{
			$rawRunAbortDisposition = if ($null -eq $Script:RunAbortDisposition) { '<null>' } else { [string]$Script:RunAbortDisposition }
			$runAbortDisposition = if ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition)) { 'Return' } else { [string]$Script:RunAbortDisposition }
			Write-Host ("[Complete-Run] AbortedRun=true, RunAbortDisposition={0}, EffectiveDisposition={1}" -f $rawRunAbortDisposition, $runAbortDisposition)
			if ($runAbortDisposition -eq 'Exit')
			{
				$Script:MainForm.Close()
			}
			else
			{
				Exit-ExecutionView
			}
			return
		}

		$dlgTitle = if ($FatalError) {
			'Run Failed'
		} elseif ($failedCount -gt 0) {
			'Run Finished With Errors'
		} else {
			'Run Complete'
		}
		$dlgMsg = if ($FatalError) {
			"The run stopped because of an unexpected error.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText`n`nFatal error:`n$FatalError"
		} elseif ($failedCount -gt 0) {
			"Selected tweaks finished running with errors.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
		} elseif ($skippedCount -gt 0) {
			"Selected tweaks have finished running.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
		} else {
			"Selected tweaks have finished running successfully.`n`nCompleted $CompletedCount of $Script:TotalRunnableTweaks.`n$summaryCountsText"
		}
		$nextStep = Show-ExecutionSummaryDialog -Title $dlgTitle `
			-SummaryText $dlgMsg `
			-Results $executionSummary `
			-LogPath $LogPath `
			-Buttons @('Close', 'Exit')

		if ($nextStep -eq 'Close')
		{
			Exit-ExecutionView
			$ChkScan.IsChecked = $true
			Invoke-GuiSystemScan
		}
		else
		{
			$Script:MainForm.Close()
		}
	}

	function Start-GuiExecutionRun
	{
		param (
			[object[]]$TweakList,
			[ValidateSet('Run', 'Defaults')]
			[string]$Mode,
			[string]$ExecutionTitle
		)

		$tweakList = @($TweakList)
		if ($tweakList.Count -eq 0) { return }

		Initialize-ExecutionSummary -SelectedTweaks $tweakList
		$Global:Error.Clear()
		$Script:ExecutionMode = $Mode

		$StatusText.Text = if ($Mode -eq 'Defaults') { 'Restoring Windows defaults...' } else { 'Running selected tweaks...' }
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
			$Form.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

		Stop-Foreground
		if ($Mode -eq 'Defaults')
		{
			Save-GuiUndoSnapshot
		}

		$Script:RunInProgress = $true
		$PrimaryTabs.IsEnabled = $false
		$BtnRun.Content = 'Pause'
		$BtnRun.IsEnabled = $true
		if ($BtnPreviewRun) { $BtnPreviewRun.IsEnabled = $false }
		$BtnDefaults.IsEnabled = $false
		Set-GuiActionButtonsEnabled -Enabled $false
		$ChkScan.IsEnabled = $false
		$ChkTheme.IsEnabled = $false
		Set-SearchControlsEnabled -Enabled $false
		Enter-ExecutionView -Title $ExecutionTitle
		$Script:AbortRequested = $false

		$Script:TotalRunnableTweaks = $tweakList.Count
		$Script:CurrentTweakDisplayName = $null
		& $Script:UpdateProgressFn -Completed 0 -Total $Script:TotalRunnableTweaks -CurrentAction 'Starting...'

		$Script:RunState = [hashtable]::Synchronized(@{
			Paused           = $false
			AbortRequested   = $false
			AbortRequestedAt = [datetime]::MinValue
			Done             = $false
			AbortedRun       = $false
			CompletedCount   = 0
			ErrorCount       = 0
			FatalError       = $null
			ForceStopIssued  = $false
			CurrentTweak     = ''
			FailureDetails   = [System.Collections.ArrayList]::new()
			LogQueue         = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
			SkippedTweaks    = [hashtable]::Synchronized(@{})
			AppliedFunctions = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
		})

		$Script:AppendLogFn = {
			param($Text, $Level = 'INFO')
			if (-not $Script:ExecutionLogBox -or -not $Script:ExecutionLogBox.Document) { return }
			$cleanText = ($Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
			if ([string]::IsNullOrWhiteSpace($cleanText)) { return }

			$bc = [System.Windows.Media.BrushConverter]::new()
			$timestamp = Get-Date -Format 'HH:mm:ss'

			$para = New-Object System.Windows.Documents.Paragraph
			$para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
			$para.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
			$para.FontSize = 12

			$tsRun = New-Object System.Windows.Documents.Run
			$tsRun.Text = "[$timestamp] "
			$tsRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
			$para.Inlines.Add($tsRun) | Out-Null

			$contentRun = New-Object System.Windows.Documents.Run
			$contentRun.Text = $cleanText
			$contentColor = switch ($Level.ToUpperInvariant())
			{
				'SUCCESS' { $Script:CurrentTheme.ToggleOn }
				'SKIP'    { $Script:CurrentTheme.TextMuted }
				'ERROR'   { $Script:CurrentTheme.CautionText }
				'WARNING' { $Script:CurrentTheme.RiskMediumBadge }
				default   { $Script:CurrentTheme.TextPrimary }
			}
			$contentRun.Foreground = $bc.ConvertFromString($contentColor)
			$para.Inlines.Add($contentRun) | Out-Null

			$Script:ExecutionLogBox.Document.Blocks.Add($para) | Out-Null

			$vO = $Script:ExecutionLogBox.VerticalOffset
			$vH = $Script:ExecutionLogBox.ViewportHeight
			$eH = $Script:ExecutionLogBox.ExtentHeight
			if (($vO + $vH) -ge ($eH - 30)) { $Script:ExecutionLogBox.ScrollToEnd() }
		}

		$Script:DrainEntry = {
			param($entry)
			switch ($entry.Kind)
			{
				'Log'
				{
					if (Test-ExecutionSkipMessage -Message $entry.Message)
					{
						$skipKey = if (-not [string]::IsNullOrWhiteSpace($Script:ExecutionCurrentSummaryKey)) { $Script:ExecutionCurrentSummaryKey } else { $null }
						if (-not [string]::IsNullOrWhiteSpace($skipKey))
						{
							$skipDetail = if ($entry.PSObject.Properties['Message']) { [string]$entry.Message } else { 'Skipped because the system already matched the requested state.' }
							$Script:RunState['SkippedTweaks'][$skipKey] = $skipDetail
							Set-ExecutionSummaryStatus -Key $skipKey -Status 'Skipped' -Detail $skipDetail
						}
						return
					}
				}
				'_TweakStarted'
				{
					$Script:RunState['CurrentTweak'] = $entry.Name
					$Script:ExecutionCurrentSummaryKey = if ($entry.PSObject.Properties['Key']) { [string]$entry.Key } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($Script:ExecutionCurrentSummaryKey))
					{
						if ($Script:RunState['SkippedTweaks'].ContainsKey($Script:ExecutionCurrentSummaryKey))
						{
							$null = $Script:RunState['SkippedTweaks'].Remove($Script:ExecutionCurrentSummaryKey)
						}
						Set-ExecutionSummaryStatus -Key $Script:ExecutionCurrentSummaryKey -Status 'Running'
					}
					$Script:ExecutionLastConsoleAction = $null
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $entry.Name
				}
				'_TweakCompleted'
				{
					$completedStatus = if ([string]::IsNullOrWhiteSpace($entry.Status)) { 'success' } else { $entry.Status.ToLowerInvariant() }
					$completedName = ($entry.Name -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					$completedKey = if ($entry.PSObject.Properties['Key']) { [string]$entry.Key } else { $null }
					$wasSkipped = $false
					$skipDetail = $null
					if ($entry.PSObject.Properties['Count'])
					{
						$Script:RunState['CompletedCount'] = [int]$entry.Count
					}
					if (-not [string]::IsNullOrWhiteSpace($completedKey) -and $Script:RunState['SkippedTweaks'].ContainsKey($completedKey))
					{
						$wasSkipped = $true
						$skipDetail = [string]$Script:RunState['SkippedTweaks'][$completedKey]
						$null = $Script:RunState['SkippedTweaks'].Remove($completedKey)
					}
					if (-not [string]::IsNullOrWhiteSpace($completedName))
					{
						if ($wasSkipped)
						{
							& $Script:AppendLogFn ("{0} - skipped" -f $completedName) 'SKIP'
						}
						else
						{
							$displayStatus = if ($completedStatus -eq 'success') { 'success' } else { 'failed' }
							$completedLevel = if ($displayStatus -eq 'failed') { 'ERROR' } else { 'SUCCESS' }
							& $Script:AppendLogFn ("{0} - {1}!" -f $completedName, $displayStatus) $completedLevel
						}
					}
					if (-not [string]::IsNullOrWhiteSpace($completedKey))
					{
						if ($wasSkipped)
						{
							Set-ExecutionSummaryStatus -Key $completedKey -Status 'Skipped' -Detail $skipDetail
						}
						elseif ($completedStatus -eq 'success')
						{
							Set-ExecutionSummaryStatus -Key $completedKey -Status 'Success'
						}
						else
						{
							Set-ExecutionSummaryStatus -Key $completedKey -Status 'Failed'
						}
					}
					$Script:ExecutionCurrentSummaryKey = $null
					$Script:ExecutionLastConsoleAction = $null
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $completedName
				}
				'_TweakFailed'
				{
					$failedKey = if ($entry.PSObject.Properties['Key']) { [string]$entry.Key } else { $null }
					if (-not [string]::IsNullOrWhiteSpace($failedKey) -and $Script:RunState['SkippedTweaks'].ContainsKey($failedKey))
					{
						$null = $Script:RunState['SkippedTweaks'].Remove($failedKey)
					}
					if (-not [string]::IsNullOrWhiteSpace($entry.Name))
					{
						[void]$Script:RunState['FailureDetails'].Add([PSCustomObject]@{
							Name  = $entry.Name
							Error = if ($entry.PSObject.Properties['Error']) { $entry.Error } else { $null }
						})
					}
					if (-not [string]::IsNullOrWhiteSpace($failedKey))
					{
						Set-ExecutionSummaryStatus -Key $failedKey -Status 'Failed' -Detail $(if ($entry.PSObject.Properties['Error']) { [string]$entry.Error } else { $null })
					}
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $Script:RunState['CurrentTweak']
				}
				'_RunError'
				{
					$Script:RunState['FatalError'] = if ([string]::IsNullOrWhiteSpace($entry.Error)) { 'Unexpected fatal run error.' } else { [string]$entry.Error }
					LogError "Fatal run error: $($entry.Error)"
				}
				'_RunNotice'
				{
				}
				'ConsoleAction'
				{
					$cleanAct = ($entry.Action -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					$Script:ExecutionLastConsoleAction = $cleanAct
					& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $cleanAct
				}
				'ConsoleStatus'
				{
					$Script:ExecutionLastConsoleAction = $null
				}
				'ConsoleComplete'
				{
					$Script:ExecutionLastConsoleAction = $null
				}
				'_SubProgress'
				{
					$subAct = if ($entry.PSObject.Properties['Action']) { $entry.Action } else { $null }
					$subPct = if ($entry.PSObject.Properties['Percent']) { [int]$entry.Percent } else { -1 }
					$subComp = if ($entry.PSObject.Properties['Completed']) { [int]$entry.Completed } else { 0 }
					$subTot = if ($entry.PSObject.Properties['Total']) { [int]$entry.Total } else { 0 }
					if ($subPct -lt 0 -and $subTot -gt 0) { $subPct = [Math]::Round(($subComp / $subTot) * 100) }
					$detail = if ($subAct -and $subPct -ge 0) { "{0} ({1}%)" -f $subAct, $subPct }
						elseif ($subAct) { $subAct }
						elseif ($subPct -ge 0) { "{0}%" -f $subPct }
						else { $null }
					if ($detail)
					{
						& $Script:UpdateProgressFn -Completed $Script:RunState['CompletedCount'] -Total $Script:TotalRunnableTweaks -CurrentAction $detail
					}
				}
			}
		}

		Set-Variable -Name 'GUIRunState' -Scope Global -Value $Script:RunState['LogQueue']
		Set-UILogHandler { param($entry) $Script:RunState['LogQueue'].Enqueue($entry) }

		LogInfo "Starting tweak execution (mode: $Mode)"

		$bgModuleDir   = Split-Path $PSScriptRoot -Parent
		$bgLoaderPath  = Join-Path $bgModuleDir 'Baseline.psm1'
		$bgRootDir     = Split-Path $bgModuleDir -Parent
		$bgLocDir      = Join-Path $bgRootDir 'Localizations'
		$bgUICulture   = $PSUICulture
		$bgLogFilePath = $Global:LogFilePath

		$Script:ExecutionWorker = GUIExecution\Start-GuiExecutionWorker `
			-RunState $Script:RunState `
			-TweakList $tweakList `
			-Mode $Mode `
			-LoaderPath $bgLoaderPath `
			-LocalizationDirectory $bgLocDir `
			-UICulture $bgUICulture `
			-LogFilePath $bgLogFilePath
		$Script:BgPS = $Script:ExecutionWorker.PowerShell
		$Script:BgAsync = $Script:ExecutionWorker.AsyncResult
		$Script:ExecutionRunspace = $Script:ExecutionWorker.Runspace
		$Script:ExecutionRunPowerShell = $Script:ExecutionWorker.PowerShell

		$Script:ExecutionPumpTickFn = {
			try
			{
				if (-not $Script:RunInProgress -or -not $Script:RunState) { return }

				if ($Script:AbortRequested -and -not $Script:RunState['AbortRequested'])
				{
					$Script:RunState['AbortRequested'] = $true
					$Script:RunState['AbortRequestedAt'] = Get-Date
				}

				if (
					$Script:RunState['AbortRequested'] -and
					-not $Script:RunState['Done'] -and
					-not $Script:RunState['ForceStopIssued'] -and
					$Script:RunState['AbortRequestedAt'] -ne [datetime]::MinValue -and
					((Get-Date) - $Script:RunState['AbortRequestedAt']).TotalSeconds -ge 2
				)
				{
					$Script:RunState['ForceStopIssued'] = $true
					$Script:RunState['AbortedRun'] = $true
					$Script:RunState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_RunNotice'
						Level = 'WARNING'
						Message = 'Abort requested - stopping the current operation now.'
					})
					$bgPsToStop = $Script:BgPS
					if ($bgPsToStop)
					{
						GUIExecution\Request-GuiExecutionWorkerStop -PowerShellInstance $bgPsToStop
					}
				}

				$qEntry = $null
				while ($Script:RunState['LogQueue'].TryDequeue([ref]$qEntry))
				{
					& $Script:DrainEntry $qEntry
					$qEntry = $null
				}

				$completed = [int]$Script:RunState['CompletedCount']
				$currentAction = if (-not [string]::IsNullOrWhiteSpace($Script:RunState['CurrentTweak'])) { $Script:RunState['CurrentTweak'] } else { 'Working...' }
				& $Script:UpdateProgressFn -Completed $completed -Total $Script:TotalRunnableTweaks -CurrentAction $currentAction

				if ($Script:BgAsync -and -not $Script:BgAsync.IsCompleted -and -not $Script:RunState['Done']) { return }

				# Do not complete the run while the abort dialog is showing to prevent stacked dialogs
				if ($Script:AbortDialogShowing) { return }

				if ($Script:ExecutionRunTimer)
				{
					try { $Script:ExecutionRunTimer.Stop() } catch { $null = $_ }
					try { $Script:ExecutionRunTimer.Dispose() } catch { $null = $_ }
				}

				$qEntry = $null
				while ($Script:RunState['LogQueue'].TryDequeue([ref]$qEntry))
				{
					& $Script:DrainEntry $qEntry
					$qEntry = $null
				}

				GUIExecution\Complete-GuiExecutionWorker -Worker $Script:ExecutionWorker
				$Script:ExecutionWorker = $null
				$Script:ExecutionRunspace = $null
				$Script:ExecutionRunPowerShell = $null
				$Script:ExecutionRunTimer = $null
				$Script:BgPS = $null
				$Script:BgAsync = $null

				foreach ($fn in $Script:RunState['AppliedFunctions']) { $Script:AppliedTweaks.Add($fn) | Out-Null }

				Clear-UILogHandler
				Remove-Variable -Name 'GUIRunState' -Scope Global -ErrorAction SilentlyContinue
				$Script:RunInProgress = $false
				$Script:CurrentTweakDisplayName = $null
				$PrimaryTabs.IsEnabled = $true
				$BtnRun.Content = 'Run Tweaks'
				$BtnRun.IsEnabled = $true
				if ($BtnPreviewRun) { $BtnPreviewRun.IsEnabled = $true }
				$BtnDefaults.IsEnabled = $true
				Set-GuiActionButtonsEnabled -Enabled $true
				$ChkScan.IsEnabled = $true
				$ChkTheme.IsEnabled = $true
				Set-SearchControlsEnabled -Enabled $true

				$completedCount = [int]$Script:RunState['CompletedCount']
				$abortedRun = $Script:RunState['AbortedRun']
				$fatalError = if ([string]::IsNullOrWhiteSpace($Script:RunState['FatalError'])) { $null } else { [string]$Script:RunState['FatalError'] }
				$logPath = $Global:LogFilePath
				Write-Host "[Timer] Run done. mode=$($Script:ExecutionMode), aborted=$abortedRun, disposition=$($Script:RunAbortDisposition), completed=$completedCount"
				Complete-ExecutionSummary -AbortedRun:$abortedRun -FatalError $fatalError
				$executionSummary = @(Get-ExecutionSummaryResults)
				Write-ExecutionSummaryToLog -Results $executionSummary -AbortedRun:$abortedRun -FatalError $fatalError
				try
				{
					Complete-GuiExecutionRun -Mode $Script:ExecutionMode `
						-CompletedCount $completedCount `
						-AbortedRun:$abortedRun `
						-FatalError $fatalError `
						-ExecutionSummary $executionSummary `
						-LogPath $logPath
				}
				catch
				{
					Write-Host "[Timer] Complete-GuiExecutionRun FAILED: $($_.Exception.Message)"
					LogError ("Complete-GuiExecutionRun failed: {0}" -f $_.Exception.Message)
					# Ensure the GUI is restored even if the completion handler fails
					try { Exit-ExecutionView } catch { $null = $_ }
				}
			}
			catch
			{
				if (-not $Script:ExecutionTimerErrorShown)
				{
					$Script:ExecutionTimerErrorShown = $true
					Write-Host "[Timer] OUTER CATCH: $($_.Exception.Message)"
					LogError ("Execution UI update failed: {0}" -f $_.Exception.Message)
					try { $StatusText.Text = "Execution UI update failed. See the run log for details." } catch { $null = $_ }
					try { $StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText) } catch { $null = $_ }
					# Last resort: restore GUI if it's still in execution view
					if ($Script:RunInProgress -eq $false -or $Script:AbortRequested)
					{
						try { Exit-ExecutionView } catch { $null = $_ }
					}
				}
			}
		}

		$runTimer = New-Object System.Windows.Threading.DispatcherTimer
		$runTimer.Interval = [TimeSpan]::FromMilliseconds(100)
		$runTimer.Add_Tick({
			& $Script:ExecutionPumpTickFn
		})
		$Script:ExecutionRunTimer = $runTimer
		$runTimer.Start()
		& $Script:ExecutionPumpTickFn
	}
	#endregion

	#region Build controls for a set of tweaks
	$Script:Controls = @{}
	# Function-name → manifest-index map for linked-toggle lookups in closures
	$Script:FunctionToIndex = @{}
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
			try { $isVisible = [bool](& $st.VisibleIf) } catch { $isVisible = $false }
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
				$Script:Controls[$si] = [pscustomobject]@{ SelectedIndex = -1; IsEnabled = $isVisible }
			}
		}
	}

	# Pending linked states for tweaks whose target tab is not yet built
	$Script:PendingLinkedChecks   = [System.Collections.Generic.HashSet[string]]::new()
	$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
	$Script:ApplyingGuiPreset     = $false  # suppress linked sync while applying an explicit preset
	# Applied-this-session tracking for system scan
	$Script:AppliedTweaks = [System.Collections.Generic.HashSet[string]]::new()
	function New-PresetButton
	{
		param(
			[string]$Label,
			[ValidateSet('Primary', 'Danger', 'Secondary', 'Subtle')]
			[string]$Variant = 'Secondary',
			[switch]$Compact,
			[switch]$Muted
		)

		$button = New-Object System.Windows.Controls.Button
		$button.Content = $Label
		$button.Padding = if ($Compact) { [System.Windows.Thickness]::new(10, 4, 10, 4) } else { [System.Windows.Thickness]::new(12, 6, 12, 6) }
		$button.Margin = [System.Windows.Thickness]::new(3, 0, 3, 0)
		$button.FontSize = 11
		Set-ButtonChrome -Button $button -Variant $Variant -Compact:$Compact -Muted:$Muted
		return $button
	}

	function New-WhyThisMattersButton
	{
		<#
		.SYNOPSIS
		Returns a secondary outline button that toggles a hint border, or $null if no hint text.
		The caller must add the returned .Tag (Border) to the parent layout.
		#>
			param (
				[hashtable]$Tweak,
				[int]$LeftIndent = 28
			)

		$hintText = if ($Tweak -and $Tweak.ContainsKey('WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) {
			[string]$Tweak.WhyThisMatters
		} else { $null }
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersButton'
		if (-not $Script:WhyThisMattersButtonTemplate)
		{
			$linkTemplateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type Button}">
    <Border Background="{TemplateBinding Background}"
            BorderBrush="{TemplateBinding BorderBrush}"
            BorderThickness="{TemplateBinding BorderThickness}"
            CornerRadius="5"
            Padding="{TemplateBinding Padding}"
            SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center"
                          VerticalAlignment="Center"
                          RecognizesAccessKey="True" />
    </Border>
</ControlTemplate>
'@
			$linkTemplateReader = New-Object System.Xml.XmlNodeReader ([xml]$linkTemplateXaml)
			$Script:WhyThisMattersButtonTemplate = [System.Windows.Markup.XamlReader]::Load($linkTemplateReader)
		}

		$btn = New-Object System.Windows.Controls.Button
		$btn.Content = 'Why this matters'
		$btn.FontSize = 10
		$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
		$btn.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$btn.Background = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
		$btn.BorderThickness = [System.Windows.Thickness]::new(0)
		$btn.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$btn.Cursor = [System.Windows.Input.Cursors]::Hand
		$btn.VerticalAlignment = 'Center'
		$btn.HorizontalAlignment = 'Right'
		$btn.FocusVisualStyle = $null
		$btn.Template = $Script:WhyThisMattersButtonTemplate

		# Expandable hint border (stored in Tag for caller to add to layout)
		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.ActiveTabBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)
		$hintBorder.Margin = [System.Windows.Thickness]::new($LeftIndent, 3, 8, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock

		$btn.Tag = $hintBorder

		$btnRef = $btn
		$borderRef = $hintBorder
		$hoverBg = $bc.ConvertFromString($Script:CurrentTheme.TabHoverBg)
		$pressBg = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$normalFg = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$activeFg = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$btn.Add_MouseEnter({
			$btnRef.Background = $hoverBg
			$btnRef.Foreground = $activeFg
		}.GetNewClosure())
		$btn.Add_MouseLeave({
			$btnRef.Background = [System.Windows.Media.Brushes]::Transparent
			$btnRef.Foreground = $normalFg
		}.GetNewClosure())
		$btn.Add_PreviewMouseLeftButtonDown({
			$btnRef.Background = $pressBg
		}.GetNewClosure())
		$btn.Add_Click({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$btnRef.Content = if ($isVisible) { 'Why this matters' } else { 'Hide' }
			$btnRef.Foreground = if ($isVisible) { $normalFg } else { $activeFg }
		}.GetNewClosure())

		return $btn
	}

	function New-WhyThisMattersBlock
	{
		param (
			[hashtable]$Tweak,
			[int]$LeftIndent = 0
		)

		$hintText = if ($Tweak -and $Tweak.ContainsKey('WhyThisMatters') -and -not [string]::IsNullOrWhiteSpace([string]$Tweak.WhyThisMatters)) {
			[string]$Tweak.WhyThisMatters
		}
		else {
			$null
		}
		if ([string]::IsNullOrWhiteSpace($hintText)) { return $null }

		$bc = New-SafeBrushConverter -Context 'New-WhyThisMattersToggle'
		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = 'Vertical'
		$stack.Margin = [System.Windows.Thickness]::new($LeftIndent, 6, 8, 0)

		$toggle = New-PresetButton -Label 'Why this matters' -Variant 'Subtle' -Compact -Muted
		$toggle.Margin = [System.Windows.Thickness]::new(0)
		$toggle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
		$stack.Children.Add($toggle) | Out-Null

		$hintBorder = New-Object System.Windows.Controls.Border
		$hintBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
		$hintBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.ActiveTabBorder)
		$hintBorder.BorderThickness = [System.Windows.Thickness]::new(1)
		$hintBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$hintBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
		$hintBorder.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
		$hintBorder.Visibility = [System.Windows.Visibility]::Collapsed

		$hintTextBlock = New-Object System.Windows.Controls.TextBlock
		$hintTextBlock.Text = $hintText
		$hintTextBlock.TextWrapping = 'Wrap'
		$hintTextBlock.FontSize = 11
		$hintTextBlock.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$hintBorder.Child = $hintTextBlock
		$stack.Children.Add($hintBorder) | Out-Null

		$toggleRef = $toggle
		$borderRef = $hintBorder
		$toggle.Add_Click({
			$isVisible = ($borderRef.Visibility -eq [System.Windows.Visibility]::Visible)
			$borderRef.Visibility = if ($isVisible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
			$toggleRef.Content = if ($isVisible) { 'Why this matters' } else { 'Hide why this matters' }
		}.GetNewClosure())

		return $stack
	}

	function Get-PrimaryTabManifestIndexes
	{
		param ([string]$PrimaryTab)

		$indexes = @()
		if ([string]::IsNullOrWhiteSpace($PrimaryTab)) { return $indexes }

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			if ($CategoryToPrimary[$Script:TweakManifest[$i].Category] -eq $PrimaryTab)
			{
				$indexes += $i
			}
		}

		return $indexes
	}

	function Get-PresetTierRank
	{
		param ([string]$Tier)

		$normalizedTier = if ([string]::IsNullOrWhiteSpace($Tier)) { 'Safe' } else { [string]$Tier }
		switch -Regex ($normalizedTier.Trim())
		{
			'^\s*(aggressive|advanced)\s*$' { return 4 }
			'^\s*balanced\s*$'              { return 3 }
			'^\s*safe\s*$'                  { return 2 }
			'^\s*minimal\s*$'               { return 1 }
			default                         { return 2 }
		}
	}

	function ConvertTo-GuiPresetName
	{
		param ([string]$PresetName)

		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Safe' } else { [string]$PresetName }
		switch -Regex ($normalizedPresetName.Trim())
		{
			'^\s*minimal\s*$'               { return 'Minimal' }
			'^\s*balanced\s*$'              { return 'Balanced' }
			'^\s*safe\s*$'                  { return 'Safe' }
			'^\s*(advanced|aggressive)\s*$' { return 'Aggressive' }
			default                         { return 'Safe' }
		}
	}

	function Initialize-GuiSelectionStateStores
	{
		if (-not $Script:ExplicitPresetSelections)
		{
			$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
				[System.StringComparer]::OrdinalIgnoreCase
			)
		}
	}

	function Resolve-GuiPresetFilePath
	{
		param([Parameter(Mandatory)][string]$PresetName)

		if ([string]::IsNullOrWhiteSpace($PresetName)) { return $null }

		$candidateRoots = @()
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiPresetDirectoryPath))
		{
			$candidateRoots += $Script:GuiPresetDirectoryPath
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
		{
			$candidateRoots += (Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Data\Presets')
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$PSScriptRoot))
		{
			$candidateRoots += (Join-Path -Path $PSScriptRoot -ChildPath 'Data\Presets')
			$candidateRoots += (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Data\Presets')
		}

		foreach ($root in $candidateRoots | Select-Object -Unique)
		{
			if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }

			$jsonPath = Join-Path -Path $root -ChildPath ("{0}.json" -f $PresetName)
			if (Test-Path -LiteralPath $jsonPath -PathType Leaf -ErrorAction SilentlyContinue)
			{
				return $jsonPath
			}

			$path = Join-Path -Path $root -ChildPath ("{0}.txt" -f $PresetName)
			if (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue)
			{
				return $path
			}
		}

		return $null
	}

	function Get-GuiPresetEntries
	{
		param([Parameter(Mandatory)][string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$presetPath = Resolve-GuiPresetFilePath -PresetName $PresetName
		if ([string]::IsNullOrWhiteSpace([string]$presetPath))
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Preset '{0}' could not be resolved to a JSON or TXT file." -f $PresetName)
			}
			throw "Preset file '$PresetName.json' or '$PresetName.txt' was not found under Data\Presets."
		}

		if ($writeGuiPresetDebugScript)
		{
			$presetFormat = if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase)) { 'JSON' } else { 'Text' }
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Loading preset '{0}' from '{1}' ({2})." -f $PresetName, $presetPath, $presetFormat)
		}

		$entries = New-Object System.Collections.Generic.List[object]
		$addParsedLine = {
			param([string]$Line)

			$trimmed = ([string]$Line).Trim()
			if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
			if ($trimmed.StartsWith('#')) { return }

			$parts = @($trimmed -split '\s+', 2)
			$functionName = $parts[0].Trim()
			if ([string]::IsNullOrWhiteSpace($functionName)) { return }

			$argumentText = ''
			if ($parts.Count -gt 1) { $argumentText = $parts[1].Trim() }

			$entries.Add([pscustomobject]@{
				FunctionName = $functionName
				ArgumentText = $argumentText
				RawLine      = $trimmed
			}) | Out-Null
		}

		if ([System.IO.Path]::GetExtension($presetPath).Equals('.json', [System.StringComparison]::OrdinalIgnoreCase))
		{
			$presetData = Get-Content -LiteralPath $presetPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
			$rawEntries = [System.Collections.Generic.List[object]]::new()
			if ($presetData -and $presetData.PSObject.Properties['Entries'])
			{
				foreach ($e in $presetData.Entries) { if ($null -ne $e) { [void]$rawEntries.Add($e) } }
			}
			elseif ($presetData -is [System.Collections.IEnumerable] -and -not ($presetData -is [string]))
			{
				foreach ($e in $presetData) { if ($null -ne $e) { [void]$rawEntries.Add($e) } }
			}

			foreach ($rawEntry in $rawEntries)
			{
				if ($null -eq $rawEntry) { continue }

				if ($rawEntry -is [string])
				{
					& $addParsedLine $rawEntry
					continue
				}

				$commandLine = $null
				if ($rawEntry.PSObject.Properties['Command'] -and -not [string]::IsNullOrWhiteSpace([string]$rawEntry.Command))
				{
					$commandLine = [string]$rawEntry.Command
				}
				else
				{
					$functionName = $null
					if ($rawEntry.PSObject.Properties['Function']) { $functionName = [string]$rawEntry.Function }
					$typeName = $null
					if ($rawEntry.PSObject.Properties['Type']) { $typeName = [string]$rawEntry.Type }

					switch -Regex ($typeName)
					{
						'^Toggle$'
						{
							$state = $null
							if ($rawEntry.PSObject.Properties['State']) { $state = [string]$rawEntry.State } elseif ($rawEntry.PSObject.Properties['Value']) { $state = [string]$rawEntry.Value }
							if ($state -match '^(?i:on|true|1)$')
							{
								$commandLine = '{0} -Enable' -f $functionName
							}
							elseif ($state -match '^(?i:off|false|0)$')
							{
								$commandLine = '{0} -Disable' -f $functionName
							}
							elseif ($functionName)
							{
								$commandLine = $functionName
							}
						}
						'^Choice$'
						{
							$choiceValue = $null
							if ($rawEntry.PSObject.Properties['Value']) { $choiceValue = [string]$rawEntry.Value } elseif ($rawEntry.PSObject.Properties['SelectedValue']) { $choiceValue = [string]$rawEntry.SelectedValue }
							if (-not [string]::IsNullOrWhiteSpace($choiceValue) -and $functionName)
							{
								$commandLine = '{0} -{1}' -f $functionName, $choiceValue
							}
						}
						'^Action$'
						{
							if ($functionName)
							{
								$commandLine = $functionName
							}
						}
						default
						{
							if ($functionName)
							{
								$commandLine = $functionName
							}
						}
					}
				}

				& $addParsedLine $commandLine
			}
		}
		else
		{
			foreach ($rawLine in [System.IO.File]::ReadAllLines($presetPath))
			{
				& $addParsedLine $rawLine
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetEntries' -Message ("Loaded {0} preset entr{1} from '{2}'." -f $entries.Count, $(if ($entries.Count -eq 1) { 'y' } else { 'ies' }), $presetPath)
		}

		return ,($entries.ToArray())
	}

	function Set-GuiPresetSelection
	{
		param([Parameter(Mandatory)][string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Received preset request '{0}' on current tab '{1}'." -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
		}
		if ([string]::IsNullOrWhiteSpace([string]$Script:CurrentPrimaryTab) -or $Script:CurrentPrimaryTab -eq $Script:SearchResultsTabTag)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Ignoring preset '{0}' because there is no active primary tab or the search-results tab is selected." -f $PresetName)
			}
			return
		}

		$setTabPresetScript = ${function:Set-TabPreset}
		if (-not $setTabPresetScript)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Could not dispatch preset '{0}' because Set-TabPreset is unavailable." -f $PresetName)
			}
			return
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Dispatching preset '{0}' to Set-TabPreset for tab '{1}'." -f $PresetName, $Script:CurrentPrimaryTab)
		}
		try
		{
			& $setTabPresetScript -PrimaryTab $Script:CurrentPrimaryTab -PresetTier $PresetName
		}
		catch
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Set-TabPreset failed for preset '{0}' on tab '{1}': {2}" -f $PresetName, $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }), $_.Exception.Message)
			}
			throw
		}
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-GuiPresetSelection' -Message ("Completed preset dispatch for '{0}'." -f $PresetName)
		}
	}

	function Test-TweakMatchesPresetTier
	{
		param (
			[hashtable]$Tweak,
			[string]$Tier
		)

		if (-not $Tweak) { return $false }
		$getPresetTierRankScript = ${function:Get-PresetTierRank}
		if (-not $getPresetTierRankScript) { return $false }
		return ((& $getPresetTierRankScript -Tier $Tweak.PresetTier) -le (& $getPresetTierRankScript -Tier $Tier))
	}

	function Get-GuiPresetCommandsPath
	{
		param ([string]$PresetName)

		$convertToGuiPresetNameScript = ${function:ConvertTo-GuiPresetName}
		$normalizedPresetName = if ($convertToGuiPresetNameScript)
		{
			& $convertToGuiPresetNameScript -PresetName $PresetName
		}
		else
		{
			if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Safe' } else { [string]$PresetName }
		}
		$presetDirectory = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath 'Data\Presets'
		if (-not (Test-Path -LiteralPath $presetDirectory))
		{
			return $null
		}

		$jsonPath = Join-Path -Path $presetDirectory -ChildPath ("{0}.json" -f $normalizedPresetName)
		if (Test-Path -LiteralPath $jsonPath)
		{
			return $jsonPath
		}

		$candidatePath = Join-Path -Path $presetDirectory -ChildPath ("{0}.txt" -f $normalizedPresetName)
		if (Test-Path -LiteralPath $candidatePath)
		{
			return $candidatePath
		}

		return $null
	}

	function Import-GuiPresetSelectionMap
	{
		param ([string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$getGuiPresetCommandsPathScript = ${function:Get-GuiPresetCommandsPath}
		$presetCommandsPath = $null
		if ($getGuiPresetCommandsPathScript)
		{
			$presetCommandsPath = & $getGuiPresetCommandsPathScript -PresetName $PresetName
		}
		if ([string]::IsNullOrWhiteSpace($presetCommandsPath) -or -not (Test-Path -LiteralPath $presetCommandsPath))
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Preset '{0}' resolved to no file path." -f $PresetName)
			}
			return [pscustomobject]@{
				Path = $null
				Entries = @{}
				UnmatchedEntries = @()
			}
		}

		$manifestByFunction = @{}
		foreach ($tweak in $Script:TweakManifest)
		{
			if ($tweak -and -not [string]::IsNullOrWhiteSpace([string]$tweak.Function))
			{
				$manifestByFunction[[string]$tweak.Function] = $tweak
			}
		}

		$selectionMap = @{}
		$unmatchedEntries = [System.Collections.Generic.List[object]]::new()
		$lineNumber = 0
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Parsing preset map for '{0}' from '{1}'." -f $PresetName, $presetCommandsPath)
		}
		$presetEntryList = Get-GuiPresetEntries -PresetName $PresetName
		if ($null -eq $presetEntryList) { $presetEntryList = @() }
		foreach ($presetEntry in $presetEntryList)
		{
			$lineNumber++
			$commandLine = ''
			if ($presetEntry.PSObject.Properties['RawLine'] -and -not [string]::IsNullOrWhiteSpace([string]$presetEntry.RawLine)) { $commandLine = [string]$presetEntry.RawLine }
			if ([string]::IsNullOrWhiteSpace($commandLine))
			{
				$commandLine = '{0} {1}' -f [string]$presetEntry.FunctionName, [string]$presetEntry.ArgumentText
			}
			$commandLine = $commandLine.Trim()
			if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.StartsWith('#'))
			{
				continue
			}

			$tokens = @($commandLine -split '\s+')
			if ($tokens.Count -eq 0) { continue }

			$functionName = [string]$tokens[0]
			if (-not $manifestByFunction.ContainsKey($functionName))
			{
				$reason = "No manifest entry matches '$functionName'."
				[void]$unmatchedEntries.Add([pscustomobject]@{
					LineNumber = $lineNumber
					Command = $commandLine
					Function = $functionName
					Reason = $reason
				})
				if ($writeGuiPresetDebugScript)
				{
					& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason)
				}
				continue
			}

			$tweak = $manifestByFunction[$functionName]
			$argName = $null
			if ($tokens.Count -gt 1 -and $tokens[1].StartsWith('-')) { $argName = $tokens[1].Substring(1) }
			$matchedEntry = $null
			$reason = $null
			$debugMessage = $null

			switch ($tweak.Type)
			{
				'Toggle'
				{
					$state = $null
					if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam) -and $argName -eq [string]$tweak.OnParam)
					{
						$state = 'On'
					}
					elseif (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam) -and $argName -eq [string]$tweak.OffParam)
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Enable')
					{
						$state = 'On'
					}
					elseif ($argName -eq 'Disable' -or $argName -eq 'Hide')
					{
						$state = 'Off'
					}
					elseif ($argName -eq 'Show')
					{
						$state = 'On'
					}

					if ($state)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Toggle'
							State = $state
						}
						$debugMessage = "Line {0}: {1} -> Toggle {2}." -f $lineNumber, $commandLine, $state
					}
					else
					{
						$expectedArgs = [System.Collections.Generic.List[string]]::new()
						if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OnParam)) { [void]$expectedArgs.Add("-$([string]$tweak.OnParam)") }
						if (-not [string]::IsNullOrWhiteSpace([string]$tweak.OffParam)) { [void]$expectedArgs.Add("-$([string]$tweak.OffParam)") }
						if (-not ($expectedArgs -contains '-Enable')) { [void]$expectedArgs.Add('-Enable') }
						if (-not ($expectedArgs -contains '-Disable')) { [void]$expectedArgs.Add('-Disable') }
						if (-not ($expectedArgs -contains '-Show')) { [void]$expectedArgs.Add('-Show') }
						if (-not ($expectedArgs -contains '-Hide')) { [void]$expectedArgs.Add('-Hide') }

						$reason = if ([string]::IsNullOrWhiteSpace($argName))
						{
							"Missing toggle argument. Expected one of: $($expectedArgs -join ', ')."
						}
						else
						{
							"Toggle argument '-$argName' does not map to '$functionName'. Expected one of: $($expectedArgs -join ', ')."
						}

						[void]$unmatchedEntries.Add([pscustomobject]@{
							LineNumber = $lineNumber
							Command = $commandLine
							Function = $functionName
							Reason = $reason
						})
						$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
					}
				}
				'Choice'
				{
					$optList = if ($null -ne $tweak.Options -and $tweak.Options -is [System.Collections.IEnumerable] -and -not ($tweak.Options -is [string])) { [string[]]$tweak.Options } elseif ($null -ne $tweak.Options) { [string[]]@([string]$tweak.Options) } else { [string[]]@() }
					if (-not [string]::IsNullOrWhiteSpace([string]$argName) -and $optList -contains $argName)
					{
						$matchedEntry = [pscustomobject]@{
							Function = $functionName
							Type = 'Choice'
							Value = $argName
						}
						$debugMessage = "Line {0}: {1} -> Choice '{2}'." -f $lineNumber, $commandLine, $argName
					}
					else
					{
						$availableOptions = [string[]]($optList | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
						$reason = if ([string]::IsNullOrWhiteSpace([string]$argName))
						{
							"Missing choice value. Expected one of: $($availableOptions -join ', ')."
						}
						else
						{
							"Choice value '$argName' does not match '$functionName'. Expected one of: $($availableOptions -join ', ')."
						}

						[void]$unmatchedEntries.Add([pscustomobject]@{
							LineNumber = $lineNumber
							Command = $commandLine
							Function = $functionName
							Reason = $reason
						})
						$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
					}
				}
				'Action'
				{
					$matchedEntry = [pscustomobject]@{
						Function = $functionName
						Type = 'Action'
						Run = $true
					}
					$debugMessage = "Line {0}: {1} -> Action run." -f $lineNumber, $commandLine
				}
				default
				{
					$reason = "Unsupported tweak type '$($tweak.Type)'."
					[void]$unmatchedEntries.Add([pscustomobject]@{
						LineNumber = $lineNumber
						Command = $commandLine
						Function = $functionName
						Reason = $reason
					})
					$debugMessage = "Line {0}: {1} -> no match ({2})." -f $lineNumber, $commandLine, $reason
				}
			}

			if ($matchedEntry)
			{
				$selectionMap[$functionName] = $matchedEntry
			}

			if ($writeGuiPresetDebugScript -and $debugMessage)
			{
				& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message $debugMessage
			}
		}

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Import-GuiPresetSelectionMap' -Message ("Completed preset map parse for '{0}'. Matched={1}, Unmatched={2}." -f $PresetName, $selectionMap.Count, $unmatchedEntries.Count)
		}

		$unmatchedArray = [object[]]$unmatchedEntries.ToArray()
		return [pscustomobject]@{
			Path = $presetCommandsPath
			Entries = $selectionMap
			UnmatchedEntries = $unmatchedArray
		}
	}

	function Get-GuiPresetDefinition
	{
		param ([string]$PresetName)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		$convertToGuiPresetNameScript = ${function:ConvertTo-GuiPresetName}
		$importGuiPresetSelectionMapScript = ${function:Import-GuiPresetSelectionMap}
		$normalizedPresetName = if ([string]::IsNullOrWhiteSpace($PresetName)) { 'Safe' } else { [string]$PresetName }
		if ($convertToGuiPresetNameScript)
		{
			$normalizedPresetName = [string](& $convertToGuiPresetNameScript -PresetName $PresetName)
		}
		$presetSelectionData = $null
		if ($importGuiPresetSelectionMapScript)
		{
			$presetSelectionData = & $importGuiPresetSelectionMapScript -PresetName $normalizedPresetName
		}
		if (-not $presetSelectionData)
		{
			$presetSelectionData = [pscustomobject]@{
				Path = $null
				Entries = @{}
				UnmatchedEntries = ([object[]]@())
			}
		}
		$explicitSelections = @{}
		if ($presetSelectionData -and $presetSelectionData.PSObject.Properties['Entries']) { $explicitSelections = $presetSelectionData.Entries }
		$unmatchedEntries = [object[]]@()
		if ($presetSelectionData -and $presetSelectionData.PSObject.Properties['UnmatchedEntries'] -and $null -ne $presetSelectionData.UnmatchedEntries) { $unmatchedEntries = [object[]]$presetSelectionData.UnmatchedEntries }
		$sourcePath = $null
		if ($presetSelectionData -and $presetSelectionData.PSObject.Properties['Path']) { $sourcePath = [string]$presetSelectionData.Path }
		$selectionMode = 'Tier'
		if (-not [string]::IsNullOrWhiteSpace($sourcePath)) { $selectionMode = 'Explicit' }

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Get-GuiPresetDefinition' -Message ("Resolved preset '{0}' -> normalized '{1}', mode={2}, source='{3}', entries={4}, unmatched={5}." -f $PresetName, $normalizedPresetName, $selectionMode, $(if ($sourcePath) { $sourcePath } else { '<none>' }), $explicitSelections.Count, $unmatchedEntries.Count)
		}

		return [pscustomobject]@{
			Name = $normalizedPresetName
			Tier = $normalizedPresetName
			SelectionMode = $selectionMode
			Entries = $explicitSelections
			UnmatchedEntries = $unmatchedEntries
			SourcePath = $sourcePath
		}
	}

	function Set-FilterSelections
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[string]$Risk = 'All',
			[string]$Category = 'All'
		)

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:RiskFilter = if ([string]::IsNullOrWhiteSpace($Risk)) { 'All' } else { $Risk }
			if ($CmbRiskFilter)
			{
				if ($CmbRiskFilter.Items.Contains($Script:RiskFilter))
				{
					$CmbRiskFilter.SelectedItem = $Script:RiskFilter
				}
				else
				{
					$CmbRiskFilter.SelectedIndex = 0
					$Script:RiskFilter = 'All'
				}
			}

			$Script:CategoryFilter = if ([string]::IsNullOrWhiteSpace($Category)) { 'All' } else { $Category }
			if ($CmbCategoryFilter)
			{
				if ($CmbCategoryFilter.Items.Contains($Script:CategoryFilter))
				{
					$CmbCategoryFilter.SelectedItem = $Script:CategoryFilter
				}
				else
				{
					$CmbCategoryFilter.SelectedIndex = 0
					$Script:CategoryFilter = 'All'
				}
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	function Set-AdvancedModeState
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([bool]$Enabled)

		$Script:FilterUiUpdating = $true
		try
		{
			$Script:AdvancedMode = $Enabled
			if ($ChkAdvancedMode)
			{
				$ChkAdvancedMode.IsChecked = $Enabled
			}
		}
		finally
		{
			$Script:FilterUiUpdating = $false
		}
	}

	function Set-TabPreset
	{
		param (
			[string]$PrimaryTab,
			[string]$PresetTier
		)

		$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
		if ($Script:GuiPresetDebugScript) { $writeGuiPresetDebugScript = $Script:GuiPresetDebugScript }
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Begin preset apply: tab='{0}', requestedPreset='{1}'." -f $(if ($PrimaryTab) { $PrimaryTab } else { '<none>' }), $(if ($PresetTier) { $PresetTier } else { '<none>' }))
		}

		if ([string]::IsNullOrWhiteSpace($PrimaryTab) -or $PrimaryTab -eq $Script:SearchResultsTabTag)
		{
			if ($writeGuiPresetDebugScript)
			{
				& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Ignoring preset '{0}' because the primary tab is empty or search results are selected." -f $PresetTier)
			}
			return
		}

		$convertToGuiPresetNameScript = ${function:ConvertTo-GuiPresetName}
		$getGuiPresetDefinitionScript = ${function:Get-GuiPresetDefinition}
		$saveGuiUndoSnapshotScript = ${function:Save-GuiUndoSnapshot}
		$setAdvancedModeStateScript = ${function:Set-AdvancedModeState}
		$updateCategoryFilterListScript = ${function:Update-CategoryFilterList}
		$setFilterSelectionsScript = ${function:Set-FilterSelections}
		$testTweakMatchesPresetTierScript = ${function:Test-TweakMatchesPresetTier}
		$syncLinkedStateCapture = $syncLinkedState

		$normalizedPresetTier = & $convertToGuiPresetNameScript -PresetName $PresetTier
		$presetDefinition = & $getGuiPresetDefinitionScript -PresetName $normalizedPresetTier
		$usesExplicitPreset = ($presetDefinition.SelectionMode -eq 'Explicit')
		$presetEntries = @{}
		if ($usesExplicitPreset -and $presetDefinition.Entries) { $presetEntries = $presetDefinition.Entries }
		$unmatchedPresetEntries = [object[]]@()
		if ($usesExplicitPreset -and $presetDefinition.PSObject.Properties['UnmatchedEntries'] -and $null -ne $presetDefinition.UnmatchedEntries) { $unmatchedPresetEntries = [object[]]$presetDefinition.UnmatchedEntries }
		Write-Host "[Set-TabPreset] mode=$($presetDefinition.SelectionMode), usesExplicit=$usesExplicitPreset, entriesType=$($presetEntries.GetType().Name), entriesCount=$($presetEntries.Count), hasUpdatePowershell=$($null -ne $presetEntries['Update-Powershell']), source=$($presetDefinition.SourcePath)"
		if ($presetEntries.Count -gt 0) { Write-Host "[Set-TabPreset] keys: $($presetEntries.Keys -join ', ')" }

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Resolved preset apply: tab='{0}', normalizedPreset='{1}', mode={2}, source='{3}', entries={4}, unmatched={5}." -f $PrimaryTab, $presetDefinition.Name, $presetDefinition.SelectionMode, $(if ($presetDefinition.SourcePath) { $presetDefinition.SourcePath } else { '<none>' }), $presetEntries.Count, $unmatchedPresetEntries.Count)
		}

		& $saveGuiUndoSnapshotScript
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Saved undo snapshot for preset '{0}'." -f $presetDefinition.Name)
		}

		# Defensive state initialization for callback paths where script-scope stores may not exist yet.
		if (-not $Script:ExplicitPresetSelections)
		{
			$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
				[System.StringComparer]::OrdinalIgnoreCase
			)
		}
		if (-not $Script:PendingLinkedChecks)
		{
			$Script:PendingLinkedChecks = [System.Collections.Generic.HashSet[string]]::new()
		}
		if (-not $Script:PendingLinkedUnchecks)
		{
			$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
		}

		$Script:ExplicitPresetSelections.Clear()
		$Script:PendingLinkedChecks.Clear()
		$Script:PendingLinkedUnchecks.Clear()
		if ($usesExplicitPreset)
		{
			foreach ($presetFunction in @($presetEntries.Keys))
			{
				if (-not [string]::IsNullOrWhiteSpace([string]$presetFunction))
				{
					[void]$Script:ExplicitPresetSelections.Add([string]$presetFunction)
				}
			}
		}
		$Script:ScanEnabled = $false
		if ($ChkScan -and $ChkScan.IsChecked)
		{
			$ChkScan.IsChecked = $false
		}

		$previousApplyingGuiPreset = $Script:ApplyingGuiPreset
		$Script:ApplyingGuiPreset = $usesExplicitPreset
		try
		{
		$advancedModeWasEnabled = [bool]$Script:AdvancedMode
		if ($presetDefinition.Name -eq 'Aggressive' -and -not $advancedModeWasEnabled)
		{
			& $setAdvancedModeStateScript -Enabled $true
		}

		& $updateCategoryFilterListScript -PrimaryTab $PrimaryTab
		& $setFilterSelectionsScript -Risk 'All' -Category 'All'

		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Reset shared UI state for preset '{0}'." -f $presetDefinition.Name)
		}

		$selectedCount = 0
		$processedCount = 0
		$visibleCount = 0
		$hiddenCount = 0
		$controlMissingCount = 0
		$toggleCount = 0
		$choiceCount = 0
		$actionCount = 0
		$stateChangeCount = 0
		foreach ($index in 0..($Script:TweakManifest.Count - 1))
		{
			$processedCount++
			$tweak = $Script:TweakManifest[$index]
			$control = $Script:Controls[$index]
			if (-not $control)
			{
				$controlMissingCount++
				continue
			}
			$isVisible = $true
			if ($tweak.VisibleIf)
			{
				try { $isVisible = [bool](& $tweak.VisibleIf) } catch { $isVisible = $false }
			}
			if ($isVisible)
			{
				$visibleCount++
			}
			else
			{
				$hiddenCount++
			}
			if ($control.PSObject.Properties['IsEnabled'])
			{
				$control.IsEnabled = $isVisible
			}
			if (-not $isVisible)
			{
				if ($control.PSObject.Properties['IsChecked'])
				{
					$control.IsChecked = $false
				}
				elseif ($control.PSObject.Properties['SelectedIndex'])
				{
					$control.SelectedIndex = -1
				}
				continue
			}

			switch ($tweak.Type)
			{
				'Toggle'
				{
					$toggleCount++
					$presetEntry = $null
					if ($usesExplicitPreset -and $null -ne $presetEntries[$tweak.Function]) { $presetEntry = $presetEntries[$tweak.Function] }
					if ($usesExplicitPreset)
					{
						$includeInPreset = ($isVisible -and $null -ne $presetEntry)
						$targetChecked = ($includeInPreset -and [string]$presetEntry.State -eq 'On')
					}
					else
					{
						$includeInPreset = ($isVisible -and (& $testTweakMatchesPresetTierScript -Tweak $tweak -Tier $presetDefinition.Tier))
						$targetChecked = ($includeInPreset -and [bool]$tweak.Default)
					}
					$currentChecked = $false
					if ($control.PSObject.Properties['IsChecked']) { $currentChecked = [bool]$control.IsChecked }
					if ($currentChecked -ne [bool]$targetChecked) { $stateChangeCount++ }
					if ($control.PSObject.Properties['IsChecked'])
					{
						$control.IsChecked = $targetChecked
					}
					Write-Host "[Preset-Toggle] $($tweak.Function) -> targetChecked=$targetChecked, includeInPreset=$includeInPreset, controlType=$($control.GetType().Name), hasIsChecked=$($null -ne $control.PSObject.Properties['IsChecked'])"
					if ($includeInPreset)
					{
						if ($usesExplicitPreset)
						{
							[void]$Script:ExplicitPresetSelections.Add([string]$tweak.Function)
							$selectedCount++
						}
						elseif ($targetChecked)
						{
							$selectedCount++
						}
					}
					if ($tweak.LinkedWith -and $syncLinkedStateCapture)
					{
						& $syncLinkedStateCapture $tweak.LinkedWith $targetChecked
					}
				}
				'Action'
				{
					$actionCount++
					$presetEntry = $null
					if ($usesExplicitPreset -and $null -ne $presetEntries[$tweak.Function]) { $presetEntry = $presetEntries[$tweak.Function] }
					if ($usesExplicitPreset)
					{
						$includeInPreset = ($isVisible -and $null -ne $presetEntry -and [bool]$presetEntry.Run)
						$targetChecked = $includeInPreset
					}
					else
					{
						$includeInPreset = ($isVisible -and (& $testTweakMatchesPresetTierScript -Tweak $tweak -Tier $presetDefinition.Tier))
						$targetChecked = ($includeInPreset -and [bool]$tweak.Default)
					}
					$currentChecked = $false
					if ($control.PSObject.Properties['IsChecked']) { $currentChecked = [bool]$control.IsChecked }
					if ($currentChecked -ne [bool]$targetChecked) { $stateChangeCount++ }
					if ($control.PSObject.Properties['IsChecked'])
					{
						$control.IsChecked = $targetChecked
					}
					Write-Host "[Preset-Action] $($tweak.Function) -> targetChecked=$targetChecked, includeInPreset=$includeInPreset, controlType=$($control.GetType().Name), hasIsChecked=$($null -ne $control.PSObject.Properties['IsChecked'])"
					if ($targetChecked) { $selectedCount++ }
					if ($tweak.LinkedWith -and $syncLinkedStateCapture)
					{
						& $syncLinkedStateCapture $tweak.LinkedWith $targetChecked
					}
				}
				'Choice'
				{
					$choiceCount++
					$targetSelectedIndex = -1
					$choiceOptions = [object[]]@()
					if ($null -eq $tweak.Options)
					{
						$choiceOptions = [object[]]@()
					}
					elseif ($tweak.Options -is [System.Array])
					{
						$choiceOptions = [object[]]$tweak.Options
					}
					elseif ($tweak.Options -is [System.Collections.IEnumerable] -and -not ($tweak.Options -is [string]))
					{
						$coList = [System.Collections.Generic.List[object]]::new()
						foreach ($o in $tweak.Options) { [void]$coList.Add($o) }
						$choiceOptions = [object[]]$coList.ToArray()
					}
					else
					{
						$choiceOptions = [object[]]@([string]$tweak.Options)
					}

					$presetEntry = $null
					if ($usesExplicitPreset -and $null -ne $presetEntries[$tweak.Function]) { $presetEntry = $presetEntries[$tweak.Function] }
					if ($usesExplicitPreset)
					{
						$includeInPreset = ($isVisible -and $null -ne $presetEntry)
						if ($includeInPreset)
						{
							$targetSelectedIndex = [array]::IndexOf($choiceOptions, [string]$presetEntry.Value)
						}
					}
					else
					{
						$includeInPreset = ($isVisible -and (& $testTweakMatchesPresetTierScript -Tweak $tweak -Tier $presetDefinition.Tier))
						if ($includeInPreset)
						{
							$targetSelectedIndex = [array]::IndexOf($choiceOptions, $tweak.Default)
						}
					}
					if ($targetSelectedIndex -ge $choiceOptions.Count) { $targetSelectedIndex = -1 }
					$currentSelectedIndex = -1
					if ($control.PSObject.Properties['SelectedIndex']) { $currentSelectedIndex = [int]$control.SelectedIndex }
					if ($currentSelectedIndex -ne [int]$targetSelectedIndex) { $stateChangeCount++ }
					if ($control.PSObject.Properties['SelectedIndex'])
					{
						$control.SelectedIndex = $targetSelectedIndex
					}
					if ($targetSelectedIndex -ge 0) { $selectedCount++ }
				}
			}
		}

		if ($usesExplicitPreset -and $unmatchedPresetEntries.Count -gt 0)
		{
			foreach ($unmatchedEntry in $unmatchedPresetEntries)
			{
				$warningText = "Preset '{0}' skipped line {1}: {2} [{3}]" -f `
					$presetDefinition.Name, `
					$unmatchedEntry.LineNumber, `
					$unmatchedEntry.Command, `
					$unmatchedEntry.Reason
				if (Get-Command -Name 'LogWarning' -CommandType Function -ErrorAction SilentlyContinue)
				{
					LogWarning $warningText
				}
				else
				{
					Write-Warning $warningText
				}
			}
		}

		$skippedEntrySuffix = if ($usesExplicitPreset -and $unmatchedPresetEntries.Count -gt 0)
		{
			" - $($unmatchedPresetEntries.Count) preset entr$(if ($unmatchedPresetEntries.Count -eq 1) { 'y' } else { 'ies' }) skipped; see log."
		}
		else
		{
			''
		}

		$Script:PresetStatusMessage = "Preset applied: $($presetDefinition.Name) ($selectedCount tweaks selected)$skippedEntrySuffix"
		$StatusText.Text = $Script:PresetStatusMessage
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($usesExplicitPreset -and $unmatchedPresetEntries.Count -gt 0) { $Script:CurrentTheme.CautionText } else { $Script:CurrentTheme.AccentBlue }))
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Status updated for preset '{0}': selected={1}, processed={2}, visible={3}, hidden={4}, missingControls={5}, toggles={6}, choices={7}, actions={8}, stateChanges={9}." -f $presetDefinition.Name, $selectedCount, $processedCount, $visibleCount, $hiddenCount, $controlMissingCount, $toggleCount, $choiceCount, $actionCount, $stateChangeCount)
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Updating primary tab visuals after preset '{0}'." -f $presetDefinition.Name)
		}
		Update-PrimaryTabVisuals
		if ($writeGuiPresetDebugScript)
		{
			& $writeGuiPresetDebugScript -Context 'Set-TabPreset' -Message ("Completed preset apply for '{0}' on tab '{1}'." -f $presetDefinition.Name, $PrimaryTab)
		}
		}
		finally
		{
			$Script:ApplyingGuiPreset = $previousApplyingGuiPreset
		}
	}

	function Set-SecondaryActionGroupStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $Script:SecondaryActionGroupBorder) { return }
		$bc = New-SafeBrushConverter -Context 'Set-SecondaryActionGroupStyle'
		$Script:SecondaryActionGroupBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.HeaderBg)
		$Script:SecondaryActionGroupBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.BorderColor)
	}

	function Set-StaticButtonStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		Set-ButtonChrome -Button $BtnRun -Variant 'Primary'
		if ($BtnPreviewRun) { Set-ButtonChrome -Button $BtnPreviewRun -Variant 'Secondary' }
		Set-ButtonChrome -Button $BtnDefaults -Variant 'Danger'
		if ($BtnHelp) { Set-ButtonChrome -Button $BtnHelp -Variant 'Subtle' -Compact -Muted }
		Set-ButtonChrome -Button $BtnLog -Variant 'Subtle' -Compact -Muted
		if ($BtnExportSettings) { Set-ButtonChrome -Button $BtnExportSettings -Variant 'Subtle' -Compact -Muted }
		if ($BtnImportSettings) { Set-ButtonChrome -Button $BtnImportSettings -Variant 'Subtle' -Compact -Muted }
		if ($BtnRestoreSnapshot) { Set-ButtonChrome -Button $BtnRestoreSnapshot -Variant 'Subtle' -Compact -Muted }
		Set-SecondaryActionGroupStyle
	}

	function Set-StaticControlTabOrder
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()

		$tabIndex = 0
		foreach ($control in @(
			$BtnHelp,
			$BtnLog,
			$ChkScan,
			$ChkAdvancedMode,
			$ChkTheme,
			$TxtSearch,
			$BtnClearSearch,
			$CmbRiskFilter,
			$CmbCategoryFilter,
			$BtnDefaults,
			$BtnExportSettings,
			$BtnImportSettings,
			$BtnRestoreSnapshot,
			$BtnPreviewRun,
			$BtnRun
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

	function Save-CurrentTabScrollOffset
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $ContentScroll -or -not $Script:CurrentPrimaryTab) { return }
		$Script:TabScrollOffsets[$Script:CurrentPrimaryTab] = [double]$ContentScroll.VerticalOffset
	}

	function Restore-CurrentTabScrollOffset
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([string]$TabKey)
		if (-not $ContentScroll -or [string]::IsNullOrWhiteSpace($TabKey)) { return }
		$offset = if ($Script:TabScrollOffsets.ContainsKey($TabKey)) { [double]$Script:TabScrollOffsets[$TabKey] } else { 0 }
$null = $ContentScroll.Dispatcher.BeginInvoke(
        [System.Action]{
                try { $ContentScroll.ScrollToVerticalOffset($offset) } catch { $null = $_ }
        },
        [System.Windows.Threading.DispatcherPriority]::Render
)
	}
	$syncLinkedState = {
		param (
			[string]$TargetFunction,
			[bool]$IsChecked
		)

		if ([string]::IsNullOrWhiteSpace($TargetFunction)) { return }
		if ($Script:ApplyingGuiPreset) { return }

		$fidx = $Script:FunctionToIndex[$TargetFunction]
		if ($null -eq $fidx) { return }

		$tctl = $Script:Controls[$fidx]
		if ($null -ne $tctl -and $tctl.PSObject.Properties["IsChecked"])
		{
			$tctl.IsChecked = $IsChecked
		}

		if ($IsChecked)
		{
			if ($Script:PendingLinkedUnchecks) { $Script:PendingLinkedUnchecks.Remove($TargetFunction) | Out-Null }
			if ($Script:PendingLinkedChecks) { $Script:PendingLinkedChecks.Add($TargetFunction) | Out-Null }
		}
		else
		{
			if ($Script:PendingLinkedChecks) { $Script:PendingLinkedChecks.Remove($TargetFunction) | Out-Null }
			if ($Script:PendingLinkedUnchecks) { $Script:PendingLinkedUnchecks.Add($TargetFunction) | Out-Null }
		}
	}

		function Build-TweakRow
		{
			param ([int]$Index, [hashtable]$Tweak)
			$bc = New-SafeBrushConverter -Context 'Build-TweakRow'
		$rowCardMargin = [System.Windows.Thickness]::new(8, 1, 8, 1)
		$rowCardPadding = [System.Windows.Thickness]::new(10, 5, 10, 5)
		$badgeSpacing = [System.Windows.Thickness]::new(2, 0, 0, 0)
		if ($Tweak.VisibleIf)
		{
			try
			{
				if (-not [bool](& $Tweak.VisibleIf)) { return $null }
			}
				catch
				{
					return $null
				}
			}

			switch ($Tweak.Type)
			{
			"Toggle"
			{
				$card = New-Object System.Windows.Controls.Border
				$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
				$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
				$card.Margin = $rowCardMargin
				$card.Padding = $rowCardPadding

				$leftStack = New-Object System.Windows.Controls.StackPanel
				$leftStack.Orientation = "Vertical"
				$leftStack.VerticalAlignment = "Center"

				$headerGrid = New-Object System.Windows.Controls.Grid
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

					$cb = New-Object System.Windows.Controls.CheckBox
					$cb.VerticalAlignment = "Center"
					$cb.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
					# Get placeholder state if available
					$placeholder = $Script:Controls[$Index]
					$initialChecked = $false
					if ($placeholder -and $placeholder.PSObject.Properties['IsChecked']) {
						$initialChecked = [bool]$placeholder.IsChecked
					}
					$cb.IsChecked = $initialChecked
					$cb.Tag = $Index
					$cb.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
					[System.Windows.Controls.Grid]::SetColumn($cb, 0)
				$headerGrid.Children.Add($cb) | Out-Null

				$nameRow = New-Object System.Windows.Controls.WrapPanel
				$nameRow.Orientation = "Horizontal"
				$nameRow.VerticalAlignment = "Center"
				[System.Windows.Controls.Grid]::SetColumn($nameRow, 1)

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 12
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameTxt.Margin = [System.Windows.Thickness]::new(0)
				$nameRow.Children.Add($nameTxt) | Out-Null

				$nameRow.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameRow.Children.Add((New-ImpactBadge)) | Out-Null
				}

				$headerGrid.Children.Add($nameRow) | Out-Null

				# Badges panel — right-aligned in title row
				$badgesPanel = New-Object System.Windows.Controls.StackPanel
				$badgesPanel.Orientation = 'Horizontal'
				$badgesPanel.VerticalAlignment = 'Center'
				$badgesPanel.HorizontalAlignment = 'Right'
				[System.Windows.Controls.Grid]::SetColumn($badgesPanel, 2)
				if ([bool]$Tweak.RequiresRestart)
				{
					$restartBadge = New-Object System.Windows.Controls.TextBlock
					$restartBadge.Text = [char]0x21BB + ' Restart'
					$restartBadge.FontSize = 10
					$restartBadge.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
					$restartBadge.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
					$restartBadge.Padding = [System.Windows.Thickness]::new(5, 1, 5, 1)
					$restartBadge.Margin = $badgeSpacing
					$restartBadge.VerticalAlignment = 'Center'
					$badgesPanel.Children.Add($restartBadge) | Out-Null
				}
				$riskBadge = New-RiskBadge -Level $Tweak.Risk
				if ($riskBadge)
				{
					$riskBadge.Margin = $badgeSpacing
					$badgesPanel.Children.Add($riskBadge) | Out-Null
				}
				$headerGrid.Children.Add($badgesPanel) | Out-Null

				$leftStack.Children.Add($headerGrid) | Out-Null

				# Status + Why This Matters row
				$statusRow = New-Object System.Windows.Controls.Grid
				$statusRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
				$statusRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
				$statusRow.Margin = [System.Windows.Thickness]::new(28, 0, 0, 0)

				# Status label showing Enabled/Disabled — left-aligned
				$statusLbl = New-Object System.Windows.Controls.TextBlock
				$statusLbl.FontSize = 10
				$statusLbl.FontWeight = [System.Windows.FontWeights]::Medium
				$statusLbl.VerticalAlignment = 'Center'
				[System.Windows.Controls.Grid]::SetColumn($statusLbl, 0)
				$onColorCapture  = if ($Script:CurrentTheme -and $Script:CurrentTheme.StateEnabled)  { $Script:CurrentTheme.StateEnabled  } else { '#9FD6AA' }
				$offColorCapture = if ($Script:CurrentTheme -and $Script:CurrentTheme.StateDisabled) { $Script:CurrentTheme.StateDisabled } else { '#98A0B7' }
				# Apply pending linked-toggle state (target built after source was already checked)
				if ($Script:PendingLinkedChecks.Contains($Tweak.Function))
				{
					$cb.IsChecked = $true
					$Script:PendingLinkedChecks.Remove($Tweak.Function) | Out-Null
				}
				elseif ($Script:PendingLinkedUnchecks.Contains($Tweak.Function))
				{
					$cb.IsChecked = $false
					$Script:PendingLinkedUnchecks.Remove($Tweak.Function) | Out-Null
				}
				if ($cb.IsChecked)
				{
					$statusLbl.Text = "Enabled"
					$statusLbl.Foreground = $bc.ConvertFromString($onColorCapture)
				}
				else
				{
					$statusLbl.Text = "Disabled"
					$statusLbl.Foreground = $bc.ConvertFromString($offColorCapture)
				}

				# If scan is active and this tweak has a Detect block, show real system state
				if ($Script:ScanEnabled -and $Tweak.Detect)
				{
					try
					{
						$detectedOn = [bool](& $Tweak.Detect)
						$onLabel  = if ($Tweak.OnParam)  { $Tweak.OnParam  } else { 'Enabled' }
						$offLabel = if ($Tweak.OffParam) { $Tweak.OffParam } else { 'Disabled' }
						if ($detectedOn -eq [bool]$Tweak.Default)
						{
							$stateWord = if ($detectedOn) { "Already $onLabel" } else { "Already $offLabel" }
							$statusLbl.Text = $stateWord
							$statusLbl.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
						}
						else
						{
							$stateWord = if ($detectedOn) { $onLabel } else { $offLabel }
							$statusLbl.Text = $stateWord
						}
					}
					catch { }
				}

				$statusRow.Children.Add($statusLbl) | Out-Null

				# Why This Matters button — right-aligned
				$whyBlock = New-WhyThisMattersButton -Tweak $Tweak
				if ($whyBlock)
				{
					[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
					$statusRow.Children.Add($whyBlock) | Out-Null
				}

				$leftStack.Children.Add($statusRow) | Out-Null

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = if ($Tweak.Description) { $Tweak.Description } else { "Turns this feature on when checked and off when unchecked." }
				$descTxt.FontSize = 10
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				$descTxt.Margin = [System.Windows.Thickness]::new(28, 1, 6, 0)
				$descTxt.TextWrapping = "Wrap"
				$leftStack.Children.Add($descTxt) | Out-Null

				# Add expandable hint content from Why This Matters button
				if ($whyBlock -and $whyBlock.Tag)
				{
					$leftStack.Children.Add($whyBlock.Tag) | Out-Null
				}

					# Wire up checkbox change to update status label (uses captured local color strings)
					$statusLblCapture = $statusLbl
					$convertBrushCapture = ${function:ConvertTo-GuiBrush}.GetNewClosure()
					$cb.Add_Checked({
						if ($statusLblCapture) {
							$statusLblCapture.Text = "Enabled"
							$statusLblCapture.Foreground = & $convertBrushCapture -Color $onColorCapture -Context 'Build-TweakRow/StatusEnabled'
						}
					}.GetNewClosure())
					$cb.Add_Unchecked({
						if ($statusLblCapture) {
							$statusLblCapture.Text = "Disabled"
							$statusLblCapture.Foreground = & $convertBrushCapture -Color $offColorCapture -Context 'Build-TweakRow/StatusDisabled'
						}
					}.GetNewClosure())
					$functionCapture = [string]$Tweak.Function
					$cb.Add_Checked({
						if ($Script:ExplicitPresetSelections) {
							[void]$Script:ExplicitPresetSelections.Add($functionCapture)
						}
					}.GetNewClosure())
					$cb.Add_Unchecked({
						if ($Script:ExplicitPresetSelections) {
							$Script:ExplicitPresetSelections.Remove($functionCapture) | Out-Null
						}
					}.GetNewClosure())
					# Wire linked toggles (e.g. PS7 install → PS7 telemetry)
					if ($Tweak.LinkedWith)
					{
					$linkedFuncCapture = $Tweak.LinkedWith
					$syncLinkedStateCapture = $syncLinkedState
					$cb.Add_Checked({
						& $syncLinkedStateCapture $linkedFuncCapture $true
					}.GetNewClosure())
					$cb.Add_Unchecked({
						& $syncLinkedStateCapture $linkedFuncCapture $false
					}.GetNewClosure())
				}

				$card.Child = $leftStack
				Add-CardHoverEffects -Card $card -FocusSources @($cb)
				if ($Tweak.LinkedWith)
				{
					# Sync the linked tweak after the row has restored its final checked state.
					& $syncLinkedState $Tweak.LinkedWith ([bool]$cb.IsChecked)
				}
				# Dim unchecked rows
				$card.Opacity = if ($cb.IsChecked) { 1.0 } else { 0.7 }
				$cardRef = $card
				$cb.Add_Checked({ $cardRef.Opacity = 1.0 }.GetNewClosure())
				$cb.Add_Unchecked({ $cardRef.Opacity = 0.7 }.GetNewClosure())
				$Script:Controls[$Index] = $cb
				return $card
			}
			"Choice"
			{
				$card = New-Object System.Windows.Controls.Border
				$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
				$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
				$card.Margin = $rowCardMargin
				$card.Padding = $rowCardPadding

				$grid = New-Object System.Windows.Controls.Grid
				$col1 = New-Object System.Windows.Controls.ColumnDefinition
				$col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				$col2 = New-Object System.Windows.Controls.ColumnDefinition
				$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
				$grid.ColumnDefinitions.Add($col1) | Out-Null
				$grid.ColumnDefinitions.Add($col2) | Out-Null

				# Left: name + description
				$leftStack = New-Object System.Windows.Controls.StackPanel
				$leftStack.Orientation = "Vertical"
				$leftStack.VerticalAlignment = "Center"
				[System.Windows.Controls.Grid]::SetColumn($leftStack, 0)

				$nameRow = New-Object System.Windows.Controls.Grid
				$nameRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
				$nameRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

				$nameInner = New-Object System.Windows.Controls.StackPanel
				$nameInner.Orientation = "Horizontal"
				[System.Windows.Controls.Grid]::SetColumn($nameInner, 0)

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 12
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameInner.Children.Add($nameTxt) | Out-Null

				$nameInner.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameInner.Children.Add((New-ImpactBadge)) | Out-Null
				}
				$nameRow.Children.Add($nameInner) | Out-Null

				# Badges panel — right-aligned
				$choiceBadgesPanel = New-Object System.Windows.Controls.StackPanel
				$choiceBadgesPanel.Orientation = 'Horizontal'
				$choiceBadgesPanel.VerticalAlignment = 'Center'
				$choiceBadgesPanel.HorizontalAlignment = 'Right'
				[System.Windows.Controls.Grid]::SetColumn($choiceBadgesPanel, 1)
				if ([bool]$Tweak.RequiresRestart)
				{
					$restartBadge = New-Object System.Windows.Controls.TextBlock
					$restartBadge.Text = [char]0x21BB + ' Restart'
					$restartBadge.FontSize = 10
					$restartBadge.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
					$restartBadge.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
					$restartBadge.Padding = [System.Windows.Thickness]::new(5, 1, 5, 1)
					$restartBadge.Margin = $badgeSpacing
					$restartBadge.VerticalAlignment = 'Center'
					$choiceBadgesPanel.Children.Add($restartBadge) | Out-Null
				}
				$riskBadge = New-RiskBadge -Level $Tweak.Risk
				if ($riskBadge)
				{
					$riskBadge.Margin = $badgeSpacing
					$choiceBadgesPanel.Children.Add($riskBadge) | Out-Null
				}
				$nameRow.Children.Add($choiceBadgesPanel) | Out-Null

				$leftStack.Children.Add($nameRow) | Out-Null

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = $Tweak.Description
				$descTxt.FontSize = 10
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
				$descTxt.Margin = [System.Windows.Thickness]::new(0, 1, 0, 0)
				$descTxt.TextWrapping = "Wrap"
				$leftStack.Children.Add($descTxt) | Out-Null

					$whyBlock = New-WhyThisMattersButton -Tweak $Tweak -LeftIndent 0
					if ($whyBlock)
					{
						$whyRow = New-Object System.Windows.Controls.Grid
						$whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
						$whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
						$whyRow.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
						[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
						$whyRow.Children.Add($whyBlock) | Out-Null
						$leftStack.Children.Add($whyRow) | Out-Null
						if ($whyBlock.Tag)
						{
							$leftStack.Children.Add($whyBlock.Tag) | Out-Null
						}
					}

				$grid.Children.Add($leftStack) | Out-Null

				# Right: ComboBox
				$combo = New-Object System.Windows.Controls.ComboBox
				$combo.MinWidth = 220
				$combo.VerticalAlignment = "Center"
				$combo.Margin = [System.Windows.Thickness]::new(14, 0, 0, 0)
				$combo.Tag = $Index
				Set-ChoiceComboStyle -Combo $combo

					$displayOpts = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } else { $Tweak.Options }
					for ($oi = 0; $oi -lt $Tweak.Options.Count; $oi++)
				{
					$combo.Items.Add($displayOpts[$oi]) | Out-Null
					}
					# Get placeholder state if available
					$placeholder = $Script:Controls[$Index]
					$initialSelectedIndex = -1
					if ($placeholder -and $placeholder.PSObject.Properties['SelectedIndex']) {
						$initialSelectedIndex = [int]$placeholder.SelectedIndex
					}
					$combo.SelectedIndex = $initialSelectedIndex
					$choiceFunctionCapture = [string]$Tweak.Function
					$comboRef = $combo
					$combo.Add_SelectionChanged({
						if ($comboRef.SelectedIndex -ge 0) {
							if ($Script:ExplicitPresetSelections) {
								[void]$Script:ExplicitPresetSelections.Add($choiceFunctionCapture)
							}
						} else {
							if ($Script:ExplicitPresetSelections) {
								$Script:ExplicitPresetSelections.Remove($choiceFunctionCapture) | Out-Null
							}
						}
					}.GetNewClosure())

					[System.Windows.Controls.Grid]::SetColumn($combo, 1)
					$grid.Children.Add($combo) | Out-Null

				$card.Child = $grid
				Add-CardHoverEffects -Card $card -FocusSources @($combo)
				$Script:Controls[$Index] = $combo
				return $card
			}
			"Action"
			{
				$card = New-Object System.Windows.Controls.Border
				$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
				$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
				$card.Margin = $rowCardMargin
				$card.Padding = $rowCardPadding

				$headerGrid = New-Object System.Windows.Controls.Grid
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
				$headerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null

					$cb = New-Object System.Windows.Controls.CheckBox
					$cb.VerticalAlignment = "Center"
					$cb.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
					# Get placeholder state if available
					$placeholder = $Script:Controls[$Index]
					$initialChecked = $false
					if ($placeholder -and $placeholder.PSObject.Properties['IsChecked']) {
						$initialChecked = [bool]$placeholder.IsChecked
					}
					if ($Script:PendingLinkedChecks -and $Script:PendingLinkedChecks.Contains($Tweak.Function))   { $initialChecked = $true;  $Script:PendingLinkedChecks.Remove($Tweak.Function)   | Out-Null }
					elseif ($Script:PendingLinkedUnchecks -and $Script:PendingLinkedUnchecks.Contains($Tweak.Function)) { $initialChecked = $false; $Script:PendingLinkedUnchecks.Remove($Tweak.Function) | Out-Null }
					Write-Host "[Build-Action] $($Tweak.Function) -> initialChecked=$initialChecked, placeholderFound=$($null -ne $placeholder), pendingCheck=$($Script:PendingLinkedChecks -and $Script:PendingLinkedChecks.Contains($Tweak.Function)), pendingUncheck=$($Script:PendingLinkedUnchecks -and $Script:PendingLinkedUnchecks.Contains($Tweak.Function))"
					$cb.IsChecked = $initialChecked
				$cb.Tag = $Index
				$cb.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				[System.Windows.Controls.Grid]::SetColumn($cb, 0)
				$headerGrid.Children.Add($cb) | Out-Null

				$nameRow = New-Object System.Windows.Controls.WrapPanel
				$nameRow.Orientation = "Horizontal"
				$nameRow.VerticalAlignment = "Center"
				[System.Windows.Controls.Grid]::SetColumn($nameRow, 1)

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 12
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameTxt.Margin = [System.Windows.Thickness]::new(0)
				$nameRow.Children.Add($nameTxt) | Out-Null

				$nameRow.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameRow.Children.Add((New-ImpactBadge)) | Out-Null
				}
				$headerGrid.Children.Add($nameRow) | Out-Null

				# Badges panel — right-aligned in title row
				$badgesPanel = New-Object System.Windows.Controls.StackPanel
				$badgesPanel.Orientation = 'Horizontal'
				$badgesPanel.VerticalAlignment = 'Center'
				$badgesPanel.HorizontalAlignment = 'Right'
				[System.Windows.Controls.Grid]::SetColumn($badgesPanel, 2)
				if ([bool]$Tweak.RequiresRestart)
				{
					$restartBadge = New-Object System.Windows.Controls.TextBlock
					$restartBadge.Text = [char]0x21BB + ' Restart'
					$restartBadge.FontSize = 10
					$restartBadge.Foreground = $bc.ConvertFromString($Script:CurrentTheme.RiskMediumBadge)
					$restartBadge.Background = $bc.ConvertFromString($Script:CurrentTheme.TabActiveBg)
					$restartBadge.Padding = [System.Windows.Thickness]::new(5, 1, 5, 1)
					$restartBadge.Margin = $badgeSpacing
					$restartBadge.VerticalAlignment = 'Center'
					$badgesPanel.Children.Add($restartBadge) | Out-Null
				}
				$riskBadge = New-RiskBadge -Level $Tweak.Risk
				if ($riskBadge)
				{
					$riskBadge.Margin = $badgeSpacing
					$badgesPanel.Children.Add($riskBadge) | Out-Null
				}
				$headerGrid.Children.Add($badgesPanel) | Out-Null

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = if ($Tweak.Description) { $Tweak.Description } else { "Runs this action one time when selected." }
				$descTxt.FontSize = 10
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				$descTxt.Margin = [System.Windows.Thickness]::new(28, 1, 6, 0)
				$descTxt.TextWrapping = "Wrap"
				$nameRowWithDesc = New-Object System.Windows.Controls.StackPanel
				$nameRowWithDesc.Orientation = "Vertical"
				$nameRowWithDesc.Children.Add($headerGrid) | Out-Null
				$nameRowWithDesc.Children.Add($descTxt) | Out-Null

					$whyBlock = New-WhyThisMattersButton -Tweak $Tweak -LeftIndent 28
					if ($whyBlock)
					{
						$whyRow = New-Object System.Windows.Controls.Grid
						$whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })) | Out-Null
						$whyRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto) })) | Out-Null
						$whyRow.Margin = [System.Windows.Thickness]::new(28, 2, 0, 0)
						[System.Windows.Controls.Grid]::SetColumn($whyBlock, 1)
						$whyRow.Children.Add($whyBlock) | Out-Null
						$nameRowWithDesc.Children.Add($whyRow) | Out-Null
						if ($whyBlock.Tag)
						{
							$nameRowWithDesc.Children.Add($whyBlock.Tag) | Out-Null
						}
					}

				# Wire linked toggles for Action type
					if ($Tweak.LinkedWith)
					{
						$linkedFuncCapture = $Tweak.LinkedWith
						$syncLinkedStateCapture = $syncLinkedState
						$cb.Add_Checked({
						& $syncLinkedStateCapture $linkedFuncCapture $true
					}.GetNewClosure())
					$cb.Add_Unchecked({
							& $syncLinkedStateCapture $linkedFuncCapture $false
						}.GetNewClosure())
					}
					$actionFunctionCapture = [string]$Tweak.Function
					$cb.Add_Checked({
						if ($Script:ExplicitPresetSelections) {
							[void]$Script:ExplicitPresetSelections.Add($actionFunctionCapture)
						}
					}.GetNewClosure())
					$cb.Add_Unchecked({
						if ($Script:ExplicitPresetSelections) {
							$Script:ExplicitPresetSelections.Remove($actionFunctionCapture) | Out-Null
						}
					}.GetNewClosure())

					$card.Child = $nameRowWithDesc
				Add-CardHoverEffects -Card $card -FocusSources @($cb)
				if ($Tweak.LinkedWith)
				{
					# Sync the linked tweak after the row has restored its final checked state.
					& $syncLinkedState $Tweak.LinkedWith ([bool]$cb.IsChecked)
				}
				# Dim unchecked rows
				$card.Opacity = if ($cb.IsChecked) { 1.0 } else { 0.7 }
				$cardRef = $card
				$cb.Add_Checked({ $cardRef.Opacity = 1.0 }.GetNewClosure())
				$cb.Add_Unchecked({ $cardRef.Opacity = 0.7 }.GetNewClosure())
				$Script:Controls[$Index] = $cb
				return $card
			}
		}
		return $null
	}
	#endregion

	#region Build tab content for a primary category
	$Script:CurrentPrimaryTab = $null
	$Script:SubTabControls = @{}

	function Update-MainContentPanelWidth
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param (
			[System.Windows.FrameworkElement]$Panel
		)

		if (-not $Panel -or -not $ContentScroll) { return }

		$viewportWidth = [double]$ContentScroll.ViewportWidth
		if ($viewportWidth -le 0)
		{
			$viewportWidth = [double]$ContentScroll.ActualWidth
		}
		if ($viewportWidth -le 0) { return }

		$horizontalPadding = 24
		$targetWidth = [Math]::Max(0, ($viewportWidth - $horizontalPadding))
		$Panel.Width = $targetWidth
		$Panel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
	}

			function Build-TabContent
			{
				param ([string]$PrimaryTab)
				$Script:CurrentPrimaryTab = $PrimaryTab
				$bc = New-SafeBrushConverter -Context 'Build-TabContent'
				$isSearchResultsTab = ($PrimaryTab -eq $Script:SearchResultsTabTag)
			$searchQuery = $Script:SearchText
			if ($null -eq $searchQuery) { $searchQuery = '' }
		$searchQuery = $searchQuery.Trim()

		# Gather visible manifest indexes for this tab, or all tabs when the search-results view is active.
		$catTweaks = [ordered]@{}
		$matchCount = 0
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$t = $Script:TweakManifest[$i]
			$primTab = $CategoryToPrimary[$t.Category]
			if (-not (Test-TweakMatchesCurrentFilters -Tweak $t -PrimaryTab $PrimaryTab -SearchQuery $searchQuery -IsSearchResultsTab:$isSearchResultsTab))
			{
				continue
			}

			# Determine sub-category relative to the tweak's owning primary tab.
			$effectivePrimaryTab = if ($isSearchResultsTab) { $primTab } else { $PrimaryTab }
			$subCat = if ($t.SubCategory) { $t.SubCategory } elseif ($t.Category -ne $effectivePrimaryTab) { $t.Category } else { "" }
			$groupKey = if ($isSearchResultsTab)
			{
				if ([string]::IsNullOrWhiteSpace($subCat)) { $primTab } else { "{0} | {1}" -f $primTab, $subCat }
			}
			else
			{
				$subCat
			}

			if (-not $catTweaks.Contains($groupKey)) { $catTweaks[$groupKey] = @() }
			$catTweaks[$groupKey] += $i
			$matchCount++
		}

		$mainPanel = New-Object System.Windows.Controls.StackPanel
		$mainPanel.Orientation = "Vertical"
		$mainPanel.Background = $bc.ConvertFromString($Script:CurrentTheme.PanelBg)
		$mainPanel.Margin = [System.Windows.Thickness]::new(0)
		$mainPanel.HorizontalAlignment = 'Stretch'

		if ($isSearchResultsTab)
		{
			$mainPanel.Children.Add((New-SearchResultsSummary -Query $searchQuery -MatchCount $matchCount)) | Out-Null
		}
		else
		{
			$presetPanel = New-Object System.Windows.Controls.Border
			$presetPanel.Background = $bc.ConvertFromString($Script:CurrentTheme.PresetPanelBg)
			$presetPanel.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.PresetPanelBorder)
			$presetPanel.BorderThickness = [System.Windows.Thickness]::new(1)
			$presetPanel.CornerRadius = [System.Windows.CornerRadius]::new(10)
			$presetPanel.Margin = [System.Windows.Thickness]::new(8, 12, 8, 8)
			$presetPanel.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)

			$presetPanelStack = New-Object System.Windows.Controls.StackPanel
			$presetPanelStack.Orientation = 'Vertical'

			$presetHeader = New-Object System.Windows.Controls.TextBlock
			$presetHeader.Text = 'Recommended Selections'
			$presetHeader.FontSize = 14
			$presetHeader.FontWeight = [System.Windows.FontWeights]::Bold
			$presetHeader.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
			$presetPanelStack.Children.Add($presetHeader) | Out-Null

			$presetSubheading = New-Object System.Windows.Controls.TextBlock
			$presetSubheading.Text = 'Use these shortcuts to start from a sensible baseline before fine-tuning individual tweaks.'
			$presetSubheading.FontSize = 11
			$presetSubheading.TextWrapping = 'Wrap'
			$presetSubheading.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
			$presetSubheading.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
			$presetPanelStack.Children.Add($presetSubheading) | Out-Null

			$presetBar = New-Object System.Windows.Controls.WrapPanel
			$presetBar.Orientation = 'Horizontal'
			$presetBar.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)

			# Capture preset functions before creating buttons
			$writeGuiPresetDebugScript = ${function:Write-GuiPresetDebug}
			$setGuiPresetSelectionScript = ${function:Set-GuiPresetSelection}
			$showGuiRuntimeFailureScript = $Script:ShowGuiRuntimeFailureScript

			# Minimal
			$btnMinimal = New-PresetButton -Label 'Minimal' -Variant 'Secondary'
			$btnMinimal.ToolTip = 'Selects a small set of safe housekeeping tweaks with no risk. Good starting point.'
			$btnMinimal.Add_Click({
				try {
					& $writeGuiPresetDebugScript -Context 'Build-TabContent/Preset/Minimal' -Message ("Preset button clicked. CurrentPrimaryTab='{0}', requestedPreset='Minimal'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
					& $setGuiPresetSelectionScript -PresetName 'Minimal'
				}
				catch {
					if ($showGuiRuntimeFailureScript) {
						& $showGuiRuntimeFailureScript -Context 'Build-TabContent/Preset/Minimal' -Exception $_.Exception -ShowDialog
					} else {
						Write-Warning "GUI event failed [Build-TabContent/Preset/Minimal]: $($_.Exception.Message)"
					}
				}
			}.GetNewClosure())
			$presetBar.Children.Add($btnMinimal) | Out-Null

			# Safe (Primary)
			$btnSafe = New-PresetButton -Label 'Safe' -Variant 'Primary'
			$btnSafe.ToolTip = 'Selects all low-risk tweaks broadly recommended for most users.'
			$btnSafe.Add_Click({
				try {
					& $writeGuiPresetDebugScript -Context 'Build-TabContent/Preset/Safe' -Message ("Preset button clicked. CurrentPrimaryTab='{0}', requestedPreset='Safe'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
					& $setGuiPresetSelectionScript -PresetName 'Safe'
				}
				catch {
					if ($showGuiRuntimeFailureScript) {
						& $showGuiRuntimeFailureScript -Context 'Build-TabContent/Preset/Safe' -Exception $_.Exception -ShowDialog
					} else {
						Write-Warning "GUI event failed [Build-TabContent/Preset/Safe]: $($_.Exception.Message)"
					}
				}
			}.GetNewClosure())
			$presetBar.Children.Add($btnSafe) | Out-Null

			# Balanced
			$btnBalanced = New-PresetButton -Label 'Balanced' -Variant 'Secondary'
			$btnBalanced.ToolTip = 'Selects all Safe tweaks plus medium-risk tweaks with broad benefit. Excludes app-specific and opinionated changes.'
			$btnBalanced.Add_Click({
				try {
					& $writeGuiPresetDebugScript -Context 'Build-TabContent/Preset/Balanced' -Message ("Preset button clicked. CurrentPrimaryTab='{0}', requestedPreset='Balanced'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
					& $setGuiPresetSelectionScript -PresetName 'Balanced'
				}
				catch {
					if ($showGuiRuntimeFailureScript) {
						& $showGuiRuntimeFailureScript -Context 'Build-TabContent/Preset/Balanced' -Exception $_.Exception -ShowDialog
					} else {
						Write-Warning "GUI event failed [Build-TabContent/Preset/Balanced]: $($_.Exception.Message)"
					}
				}
			}.GetNewClosure())
			$presetBar.Children.Add($btnBalanced) | Out-Null

			# Aggressive (Danger)
			$btnAggressive = New-PresetButton -Label 'Aggressive' -Variant 'Danger'
			$btnAggressive.ToolTip = 'Selects all tweaks including high-risk changes. Recommended for advanced users only.'
			$btnAggressive.Add_Click({
				try {
					& $writeGuiPresetDebugScript -Context 'Build-TabContent/Preset/Aggressive' -Message ("Preset button clicked. CurrentPrimaryTab='{0}', requestedPreset='Aggressive'." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
					& $setGuiPresetSelectionScript -PresetName 'Aggressive'
				}
				catch {
					if ($showGuiRuntimeFailureScript) {
						& $showGuiRuntimeFailureScript -Context 'Build-TabContent/Preset/Aggressive' -Exception $_.Exception -ShowDialog
					} else {
						Write-Warning "GUI event failed [Build-TabContent/Preset/Aggressive]: $($_.Exception.Message)"
					}
				}
			}.GetNewClosure())
			$presetBar.Children.Add($btnAggressive) | Out-Null

			# System Scan
			$btnScan = New-PresetButton -Label 'System Scan' -Variant 'Secondary'
			$btnScan.ToolTip = 'Scans your system and recommends tweaks based on detected configuration.'
			$chkScanRef = $ChkScan
			$btnScan.Add_Click({
				try {
					& $writeGuiPresetDebugScript -Context 'Build-TabContent/Preset/SystemScan' -Message ("Preset button clicked. CurrentPrimaryTab='{0}', enabling system scan." -f $(if ($Script:CurrentPrimaryTab) { $Script:CurrentPrimaryTab } else { '<none>' }))
					$chkScanRef.IsChecked = $true
					$Script:PresetStatusMessage = 'System scan enabled.'
				}
				catch {
					if ($showGuiRuntimeFailureScript) {
						& $showGuiRuntimeFailureScript -Context 'Build-TabContent/Preset/SystemScan' -Exception $_.Exception -ShowDialog
					} else {
						Write-Warning "GUI event failed [Build-TabContent/Preset/SystemScan]: $($_.Exception.Message)"
					}
				}
			}.GetNewClosure())
			$presetBar.Children.Add($btnScan) | Out-Null

			$presetPanelStack.Children.Add($presetBar) | Out-Null

			$Script:PresetStatusBadge = New-StatusPill -Text $Script:PresetStatusMessage
			if ($Script:PresetStatusBadge)
			{
				$presetPanelStack.Children.Add($Script:PresetStatusBadge) | Out-Null
			}

			$presetPanel.Child = $presetPanelStack
			$mainPanel.Children.Add($presetPanel) | Out-Null
		}

		if ($catTweaks.Count -eq 0)
		{
			$emptyState = New-Object System.Windows.Controls.Border
			$emptyState.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
			$emptyState.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CardBorder)
			$emptyState.BorderThickness = [System.Windows.Thickness]::new(1)
			$emptyState.CornerRadius = [System.Windows.CornerRadius]::new(8)
			$emptyState.Margin = [System.Windows.Thickness]::new(8, 12, 8, 8)
			$emptyState.Padding = [System.Windows.Thickness]::new(20, 18, 20, 18)
			$emptyText = New-Object System.Windows.Controls.TextBlock
			$emptyText.Text = if ($isSearchResultsTab) { "No tweaks match '$searchQuery' across all tabs." } else { "No tweaks match '$searchQuery' in this tab." }
			$emptyText.TextWrapping = 'Wrap'
			$emptyText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
			$emptyState.Child = $emptyText
			$mainPanel.Children.Add($emptyState) | Out-Null
		}

		# Collect all manifest indexes for this tab (for Select/Unselect All)
		$allTabIndexes = @()
		foreach ($subKey in $catTweaks.Keys) { $allTabIndexes += $catTweaks[$subKey] }

		if ($allTabIndexes.Count -gt 0)
		{
			# Select All / Unselect All buttons
			$selectionBar = New-Object System.Windows.Controls.WrapPanel
			$selectionBar.Orientation = "Horizontal"
			$selectionBar.Margin = [System.Windows.Thickness]::new(8, 8, 8, 2)

			$btnSelectAll = New-PresetButton -Label 'Select All' -Variant 'Subtle' -Compact

			$capturedIndexesSA = [int[]]$allTabIndexes
			$controlsRefSA = $Script:Controls
			$btnSelectAll.Add_Click({
				foreach ($idx in $capturedIndexesSA)
				{
					$ctl = $controlsRefSA[$idx]
					if ($ctl -and $ctl.IsEnabled -and $ctl.PSObject.Properties['IsChecked'])
					{
						$ctl.IsChecked = $true
					}
				}
			}.GetNewClosure())
			$selectionBar.Children.Add($btnSelectAll) | Out-Null

			$btnUnselectAll = New-PresetButton -Label 'Unselect All' -Variant 'Subtle' -Compact

			$capturedIndexesUA = [int[]]$allTabIndexes
			$controlsRefUA = $Script:Controls
			$btnUnselectAll.Add_Click({
				foreach ($idx in $capturedIndexesUA)
				{
					$ctl = $controlsRefUA[$idx]
					if ($ctl -and $ctl.IsEnabled -and $ctl.PSObject.Properties['IsChecked'])
					{
						$ctl.IsChecked = $false
					}
				}
			}.GetNewClosure())
			$selectionBar.Children.Add($btnUnselectAll) | Out-Null

			$mainPanel.Children.Add($selectionBar) | Out-Null
		}

		# Build all sub-sections
		foreach ($subKey in $catTweaks.Keys)
		{
			$indexes = $catTweaks[$subKey]

			if ($isSearchResultsTab -or ($subKey -ne "" -and $catTweaks.Count -gt 1))
			{
				$mainPanel.Children.Add((New-SectionHeader -Text $subKey)) | Out-Null
			}

			# Collect caution tweaks for this section
			$cautionTweaks = @()
			foreach ($idx in $indexes)
			{
				if ($Script:TweakManifest[$idx].Caution) { $cautionTweaks += $Script:TweakManifest[$idx] }
			}

			# Build individual tweak rows
			foreach ($idx in $indexes)
			{
				$row = Build-TweakRow -Index $idx -Tweak $Script:TweakManifest[$idx]
				if ($row) { $mainPanel.Children.Add($row) | Out-Null }
			}

			# Add caution section at bottom of each section
			$cautionSection = New-CautionSection -CautionTweaks $cautionTweaks
			if ($cautionSection) { $mainPanel.Children.Add($cautionSection) | Out-Null }
		}

		$ContentScroll.Content = $mainPanel
		Update-MainContentPanelWidth -Panel $mainPanel
		Restore-CurrentTabScrollOffset -TabKey $PrimaryTab
	}
	#endregion

	$Script:RunInProgress = $false

	$Form.Add_Closing({
		param($windowSource, $e)
		if ($Script:SuppressRunClosePrompt) { return }
		if ($Script:RunInProgress)
		{
			$e.Cancel = $true
			# Trigger the abort prompt if user attempts to close while running
			& $Script:PromptRunAbortFn
		}
	})

	#region Build primary tabs
	foreach ($pKey in $PrimaryCategories.Keys)
	{
		# Check if any tweaks exist for this primary tab
		$hasTweaks = $false
		$tweakCount = 0
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			if ($CategoryToPrimary[$Script:TweakManifest[$i].Category] -eq $pKey)
			{
				$hasTweaks = $true
				$tweakCount++
			}
		}
		if (-not $hasTweaks) { continue }

		$tabItem = New-Object System.Windows.Controls.TabItem
		$tabItem.Header = "$pKey ($tweakCount)"
		$tabItem.Tag = $pKey
		$tabItem.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TextPrimary -Context 'BuildPrimaryTabs/Foreground'
		$tabItem.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TabBg -Context 'BuildPrimaryTabs/Background'
		$tabItem.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
		$PrimaryTabs.Items.Add($tabItem) | Out-Null
		Add-PrimaryTabHoverEffects -Tab $tabItem
	}
	Update-PrimaryTabVisuals

	$Script:FilterUiUpdating = $true
	try
	{
		if ($CmbRiskFilter)
		{
			$CmbRiskFilter.Items.Clear()
			foreach ($riskOption in @('All', 'Low', 'Medium', 'High'))
			{
				[void]$CmbRiskFilter.Items.Add($riskOption)
			}
			$CmbRiskFilter.SelectedItem = $Script:RiskFilter
		}
		if ($ChkAdvancedMode)
		{
			$ChkAdvancedMode.IsChecked = $Script:AdvancedMode
		}
	}
	finally
	{
		$Script:FilterUiUpdating = $false
	}
	Set-FilterControlStyle

	$PrimaryTabs.Add_SelectionChanged({
		$e = $args[1]
		if ($e.Source -ne $PrimaryTabs) { return }
		Save-CurrentTabScrollOffset
		$selected = $PrimaryTabs.SelectedItem
		if ($selected -and $selected.Tag)
		{
			if ([string]$selected.Tag -ne $Script:SearchResultsTabTag)
			{
				$Script:LastStandardPrimaryTab = [string]$selected.Tag
			}
			Update-CategoryFilterList -PrimaryTab ([string]$selected.Tag)
			Update-PrimaryTabVisuals
			Build-TabContent -PrimaryTab $selected.Tag
		}
	})

	# Build the initial tab while the startup splash is still visible so the main
	# window only appears once real content is ready.
	if ($PrimaryTabs.Items.Count -gt 0)
	{
		$PrimaryTabs.SelectedIndex = 0
	}
	#endregion

	# Linked-toggle wiring is handled inline in Build-TweakRow (supports lazy tab building).

	$refreshVisibleContent = {
		if ($Script:RunInProgress -or $Script:FilterUiUpdating) { return }
		$targetTab = if ($PrimaryTabs -and $PrimaryTabs.SelectedItem -and $PrimaryTabs.SelectedItem.Tag) {
			[string]$PrimaryTabs.SelectedItem.Tag
		}
		elseif ($Script:CurrentPrimaryTab) {
			[string]$Script:CurrentPrimaryTab
		}
		else {
			$null
		}
		Update-CategoryFilterList -PrimaryTab $targetTab
		Update-SearchResultsTabState
	}

	Set-SearchInputStyle
	Set-FilterControlStyle
	$TxtSearch.Text = $Script:SearchText
	$TxtSearch.Add_GotKeyboardFocus({
		Set-SearchInputStyle
	})
	$TxtSearch.Add_LostKeyboardFocus({
		Set-SearchInputStyle
	})
	$TxtSearch.Add_TextChanged({
		if ($Script:RunInProgress) { return }
		$Script:SearchText = $TxtSearch.Text
		Set-SearchInputStyle
		Update-SearchResultsTabState
	})
	$CmbRiskFilter.Add_SelectionChanged({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:RiskFilter = if ($CmbRiskFilter.SelectedItem) { [string]$CmbRiskFilter.SelectedItem } else { 'All' }
		& $refreshVisibleContent
	})
	$CmbCategoryFilter.Add_SelectionChanged({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:CategoryFilter = if ($CmbCategoryFilter.SelectedItem) { [string]$CmbCategoryFilter.SelectedItem } else { 'All' }
		Update-SearchResultsTabState
	})
	$ChkAdvancedMode.Add_Checked({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:AdvancedMode = $true
		$Script:PresetStatusMessage = 'Advanced Mode enabled. High-risk and advanced tweaks are now visible.'
		$StatusText.Text = $Script:PresetStatusMessage
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		& $refreshVisibleContent
	})
	$ChkAdvancedMode.Add_Unchecked({
		if ($Script:FilterUiUpdating -or $Script:RunInProgress) { return }
		$Script:AdvancedMode = $false
		$Script:PresetStatusMessage = 'Advanced Mode disabled. High-risk and advanced tweaks are hidden again.'
		$StatusText.Text = $Script:PresetStatusMessage
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.TextSecondary)
		& $refreshVisibleContent
	})
	$BtnClearSearch.Add_Click({
		$TxtSearch.Text = ''
		$TxtSearch.Focus() | Out-Null
	})
	$ContentScroll.Add_ScrollChanged({
		if ($Script:RunInProgress) { return }
		Save-CurrentTabScrollOffset
	})
	$ContentScroll.Add_SizeChanged({
		if ($ContentScroll.Content -is [System.Windows.FrameworkElement])
		{
			Update-MainContentPanelWidth -Panel $ContentScroll.Content
		}
	})

	#region Theme toggle handler
	$ChkTheme.Add_Checked({
		Set-GUITheme -Theme $Script:LightTheme
	})
	$ChkTheme.Add_Unchecked({
		Set-GUITheme -Theme $Script:DarkTheme
	})
	#endregion

	#region Button handlers
		$BtnPreviewRun.Add_Click({
		if ($Script:RunInProgress) { return }

		$tweakList = Get-SelectedTweakRunList
		if ($tweakList.Count -eq 0)
		{
			Show-ThemedDialog -Title 'Preview Run' `
				-Message 'Select at least one tweak before previewing a run.' `
				-Buttons @('OK') `
				-AccentButton 'OK' | Out-Null
			return
		}

		$previewResults = @(Get-ExecutionPreviewResults -SelectedTweaks $tweakList)
		Write-ExecutionPreviewToLog -Results $previewResults

		$selectedCount = $previewResults.Count
		$highRiskCount = @($previewResults | Where-Object Risk -eq 'High').Count
		$restartCount = @($previewResults | Where-Object RequiresRestart).Count
		$summaryParts = @(
			"This preview lists the $selectedCount selected tweak$(if ($selectedCount -eq 1) { '' } else { 's' }).",
			'No changes were applied.'
		)
		if ($highRiskCount -gt 0)
		{
			$summaryParts += "$highRiskCount high-risk tweak$(if ($highRiskCount -eq 1) { '' } else { 's' }) selected."
		}
		if ($restartCount -gt 0)
		{
			$summaryParts += "$restartCount tweak$(if ($restartCount -eq 1) { '' } else { 's' }) may require a restart after the real run."
		}

		Show-ExecutionSummaryDialog -Title 'Preview Run' `
			-SummaryText ($summaryParts -join ' ') `
			-Results $previewResults `
			-LogPath $Global:LogFilePath `
			-Buttons @('Close') | Out-Null

		$StatusText.Text = "Previewed $selectedCount tweak$(if ($selectedCount -eq 1) { '' } else { 's' }). No changes were applied."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
	})

		$BtnRun.Add_Click({
			if ($Script:RunInProgress -and $Script:RunState)
			{
				if ($Script:RunState['Paused'])
				{
					$Script:RunState['Paused'] = $false
					$BtnRun.Content = "Pause"
					$StatusText.Text = if ($Script:ExecutionMode -eq 'Defaults') { 'Restoring Windows defaults...' } else { 'Running selected tweaks...' }
					$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
				}
				else
				{
					$Script:RunState['Paused'] = $true
					$BtnRun.Content = "Resume"
					$StatusText.Text = "Run paused..."
					$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
				}
				return
			}

			$tweakList = Get-SelectedTweakRunList
			if ($tweakList.Count -eq 0)
			{
			Show-ThemedDialog -Title 'Run Tweaks' `
				-Message 'Select at least one tweak before starting a run.' `
				-Buttons @('OK') `
				-AccentButton 'OK' | Out-Null
			return
		}
			if (-not (Confirm-HighRiskTweakRun -SelectedTweaks $tweakList))
			{
				return
			}

			Start-GuiExecutionRun -TweakList $tweakList -Mode 'Run' -ExecutionTitle 'Running Selected Tweaks'
		})

	$BtnDefaults.Add_Click({
		# Confirmation dialog for destructive action
		$result = Show-ThemedDialog -Title 'Restore to Windows Defaults' `
			-Message "This will reset tweaks to their Windows default values where possible.`n`nNote: OS Hardening tweaks and other permanent changes cannot be reversed and will be skipped.`n`nAre you sure you want to continue?" `
			-Buttons @('Cancel', 'Restore Defaults') `
			-DestructiveButton 'Restore Defaults'
		if ($result -ne 'Restore Defaults') { return }

			$defaultsTweakList = Get-WindowsDefaultRunList
			if ($defaultsTweakList.Count -eq 0)
			{
				Show-ThemedDialog -Title 'Restore to Windows Defaults' `
					-Message 'No restorable tweaks with Windows default actions are currently available.' `
					-Buttons @('OK') `
					-AccentButton 'OK' | Out-Null
				return
			}

			Start-GuiExecutionRun -TweakList $defaultsTweakList -Mode 'Defaults' -ExecutionTitle 'Restoring Windows Defaults'
		})

	$BtnHelp.Add_Click({
		Show-HelpDialog
		$StatusText.Text = 'Help opened.'
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
	})

	$BtnLog.Add_Click({
		$logPath = $Global:LogFilePath
		if ($logPath -and (Test-Path -LiteralPath $logPath -ErrorAction SilentlyContinue))
		{
			Show-LogDialog -LogPath $logPath
		}
		else
		{
			Show-ThemedDialog -Title 'Open Log' `
				-Message "Log file not found.`n$logPath" `
				-Buttons @('OK') -AccentButton 'OK' | Out-Null
		}
	})
	#endregion Button handlers

	#region System scan toggle
	$ChkScan.Add_Checked({ Invoke-GuiSystemScan })
	$ChkScan.Add_Unchecked({
		$Script:ScanEnabled = $false
		foreach ($si in $Script:Controls.Keys)
		{
			$sctl = $Script:Controls[$si]
			if ($sctl) { $sctl.IsEnabled = $true }
		}
		$StatusText.Text = ""
		if ($Script:CurrentPrimaryTab) { Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab }
	})
	#endregion

	# Style buttons directly
	$bc = [System.Windows.Media.BrushConverter]::new()

	# Settings profile buttons live alongside the defaults action so users can
	# export, import, and roll back the current GUI state.
	$secondaryActionGroup = New-Object System.Windows.Controls.Border
	$secondaryActionGroup.Margin = [System.Windows.Thickness]::new(8, 4, 0, 4)
	$secondaryActionGroup.Padding = [System.Windows.Thickness]::new(6, 4, 6, 4)
	$secondaryActionGroup.CornerRadius = [System.Windows.CornerRadius]::new(8)
	$secondaryActionGroup.BorderThickness = [System.Windows.Thickness]::new(1)
	$secondaryActionGroup.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$secondaryActionBar = New-Object System.Windows.Controls.WrapPanel
	$secondaryActionBar.Orientation = 'Horizontal'
	$secondaryActionGroup.Child = $secondaryActionBar
	$Script:SecondaryActionGroupBorder = $secondaryActionGroup
	$ActionButtonBar.Children.Add($secondaryActionGroup) | Out-Null

	$BtnExportSettings = New-PresetButton -Label 'Export Settings' -Variant 'Subtle' -Compact -Muted
	$BtnExportSettings.ToolTip = 'Export the current GUI selections to a JSON profile.'
	$secondaryActionBar.Children.Add($BtnExportSettings) | Out-Null

	$BtnImportSettings = New-PresetButton -Label 'Import Settings' -Variant 'Subtle' -Compact -Muted
	$BtnImportSettings.ToolTip = 'Import a saved JSON profile and restore the selected GUI state.'
	$secondaryActionBar.Children.Add($BtnImportSettings) | Out-Null

	$BtnRestoreSnapshot = New-PresetButton -Label 'Restore Snapshot' -Variant 'Subtle' -Compact -Muted
	$BtnRestoreSnapshot.ToolTip = 'Restore the last captured UI snapshot before an import or preset change.'
	$secondaryActionBar.Children.Add($BtnRestoreSnapshot) | Out-Null

	$BtnExportSettings.Add_Click({
		$null = Export-GuiSettingsProfile
	})

	$BtnImportSettings.Add_Click({
		$null = Import-GuiSettingsProfile
	})

	$BtnRestoreSnapshot.Add_Click({
		try
		{
			if (-not (Restore-GuiSnapshot))
			{
				Show-ThemedDialog -Title 'Restore Snapshot' -Message 'No previous GUI snapshot has been captured yet.' -Buttons @('OK') -AccentButton 'OK' | Out-Null
				return
			}
		}
		catch
		{
			LogError "Failed to restore GUI snapshot: $($_.Exception.Message)"
			Show-ThemedDialog -Title 'Restore Snapshot' -Message "Failed to restore the previous snapshot.`n`n$($_.Exception.Message)" -Buttons @('OK') -AccentButton 'OK' | Out-Null
			return
		}

		$StatusText.Text = 'Previous GUI snapshot restored.'
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		LogInfo 'Restored previous GUI snapshot'
	})

	# Apply initial theme
	Set-GUITheme -Theme $Script:DarkTheme
	Set-StaticButtonStyle
	Set-StaticControlTabOrder
	Set-GuiActionButtonsEnabled -Enabled $true

	$restoredGuiSession = Restore-GuiSessionState
	if ($restoredGuiSession)
	{
		$StatusText.Text = 'Previous session restored.'
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
	}

	$closeLoadingSplashCapture = ${function:Close-LoadingSplashWindow}.GetNewClosure()
	$hideConsoleWindowCapture = ${function:Hide-ConsoleWindow}.GetNewClosure()
	$startupPresentationCompleted = $false
	$Form.Add_ContentRendered({
		if ($startupPresentationCompleted) { return }
		$startupPresentationCompleted = $true

		try
		{
			$loadingSplash = Get-Variable -Name 'LoadingSplash' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
			if ($loadingSplash)
			{
				$null = & $closeLoadingSplashCapture -Splash $loadingSplash -DisposeResources
				$Global:LoadingSplash = $null
			}
		}
		catch
		{
			$null = $_
		}

		try
		{
			& $hideConsoleWindowCapture
		}
		catch
		{
			$null = $_
		}
	}.GetNewClosure())

	# Activate the main window only when it is about to be shown.
	$Form.ShowActivated = $true
	Initialize-WpfWindowForeground -Window $Form

	# Show the GUI
	$Form.ShowDialog() | Out-Null

	$saveChoice = GUICommon\Show-ThemedDialog `
		-Theme $Script:CurrentTheme `
		-ApplyButtonChrome ${function:Set-ButtonChrome} `
		-OwnerWindow $null `
		-Title 'Save Session' `
		-Message 'Do you want to save your current selections for next launch?' `
		-Buttons @('Save', 'Discard') `
		-AccentButton 'Save'
	if ($saveChoice -eq 'Save')
	{
		$null = Save-GuiSessionState
	}

	LogInfo "GUI closed"
}
#endregion GUI Builder

#region Report-TweakProgress
<#
	.SYNOPSIS
	Reports sub-task progress from inside a tweak function back to the GUI progress bar.

	.DESCRIPTION
	Intended to be called from tweak functions that run in the background runspace during a
	GUI-mode execution.  The function enqueues a '_SubProgress' message into $Global:GUIRunState
	(set automatically by the GUI run loop).  The DispatcherTimer on the UI thread picks it up
	and updates the secondary progress bar below the main tweak progress bar.

	If the script is not running in GUI mode or $Global:GUIRunState is not set the call is a
	no-op, so it is safe to leave in tweak functions even when they are run headlessly.

	.PARAMETER Action
	Short label shown next to the percentage, e.g. "Downloading WinGet installer".

	.PARAMETER Completed
	Number of units completed.  Used together with -Total.

	.PARAMETER Total
	Total number of units.  When provided with -Completed the bar fills proportionally.

	.PARAMETER Percent
	0-100 percentage.  Use this instead of -Completed/-Total when only a percentage is available.

	.EXAMPLE
	# Inside a tweak function that downloads a file in chunks:
	for ($i = 0; $i -lt $chunks.Count; $i++)
	{
	    Write-TweakProgress -Action "Downloading installer" -Completed $i -Total $chunks.Count
	    # ... download chunk ...
	}
#>
function Write-TweakProgress
{
	[CmdletBinding()]
	param (
		[string]$Action    = $null,
		[int]   $Completed = 0,
		[int]   $Total     = 0,
		[int]   $Percent   = -1
	)

	if (-not $Global:GUIMode) { return }
	# $GUIRunState is the ConcurrentQueue injected directly by the GUI run loop via
	# SessionStateProxy.SetVariable - it is not a global, just a session variable.
	$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction SilentlyContinue
	if (-not $queue) { return }

	$queue.Enqueue([PSCustomObject]@{
		Kind      = '_SubProgress'
		Action    = $Action
		Completed = $Completed
		Total     = $Total
		Percent   = $Percent
	})
}
#endregion Report-TweakProgress

Set-Alias -Name Report-TweakProgress -Value Write-TweakProgress -Scope Script
Export-ModuleMember -Function 'Show-TweakGUI', 'Write-TweakProgress' -Alias 'Report-TweakProgress'
