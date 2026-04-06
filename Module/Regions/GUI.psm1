using module ..\Logging.psm1
using module ..\SharedHelpers.psm1
using module ..\GUICommon.psm1
using module ..\GUIExecution.psm1

# Extracted GUI scripts are dot-sourced into this module, so they resolve
# $Script: variables against GUI.psm1 rather than GUICommon.psm1.
$Script:GuiLayout = GUICommon\Get-GuiLayout

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
		[Parameter(Mandatory = $true)][System.Windows.DependencyProperty]$Property,
		[Parameter(Mandatory = $true)][object]$Value,
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

function Test-GuiObjectField
{
	param(
		[object]$Object,
		[string]$FieldName
	)

	if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($FieldName))
	{
		return $false
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return [bool]$Object.Contains($FieldName)
	}

	return [bool]($Object.PSObject -and $Object.PSObject.Properties[$FieldName])
}

function Get-GuiObjectField
{
	param(
		[object]$Object,
		[string]$FieldName
	)

	if (-not (Test-GuiObjectField -Object $Object -FieldName $FieldName))
	{
		return $null
	}

	if ($Object -is [System.Collections.IDictionary])
	{
		return $Object[$FieldName]
	}

	return $Object.$FieldName
}

function Get-GuiRuntimeFailureDetails
{
	param (
		[string]$Context = 'GUI',
		[System.Exception]$Exception,
		[string[]]$DebugTrail
	)

	$errorLines = New-Object System.Collections.Generic.List[string]
	[void]$errorLines.Add(("GUI event failed [{0}]: {1}" -f $(if ($Context) { $Context } else { 'GUI' }), $Exception.Message))
	[void]$errorLines.Add(("Exception type: {0}" -f $Exception.GetType().FullName))
	$errorRecord = $null
	try
	{
		if ($Exception.PSObject.Properties['ErrorRecord'])
		{
			$errorRecord = $Exception.ErrorRecord
		}
	}
	catch
	{
		$errorRecord = $null
	}
	if ($Exception.InnerException)
	{
		[void]$errorLines.Add(("Inner exception: {0}" -f $Exception.InnerException.Message))
	}
	if ($errorRecord)
	{
		if ($errorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace([string]$errorRecord.InvocationInfo.PositionMessage))
		{
			[void]$errorLines.Add('Invocation:')
			[void]$errorLines.Add($errorRecord.InvocationInfo.PositionMessage.Trim())
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$errorRecord.ScriptStackTrace))
		{
			[void]$errorLines.Add('Script stack trace:')
			[void]$errorLines.Add($errorRecord.ScriptStackTrace.Trim())
		}
		if ($null -ne $errorRecord.TargetObject)
		{
			$targetType = try { $errorRecord.TargetObject.GetType().FullName } catch { 'unknown' }
			[void]$errorLines.Add(("Target object type: {0}" -f $targetType))
		}
	}
	if ($Exception.StackTrace)
	{
		[void]$errorLines.Add('Stack trace:')
		[void]$errorLines.Add($Exception.StackTrace.Trim())
	}

	if ($DebugTrail -and $DebugTrail.Count -gt 0)
	{
		[void]$errorLines.Add('')
		[void]$errorLines.Add('Preset debug trail (most recent entries):')
		$startIndex = [Math]::Max(0, $DebugTrail.Count - 15)
		for ($i = $startIndex; $i -lt $DebugTrail.Count; $i++)
		{
			[void]$errorLines.Add($DebugTrail[$i])
		}
	}

	return ($errorLines -join [Environment]::NewLine)
}

function Show-GuiRuntimeFailure
{
	param (
		[string]$Context = 'GUI',
		[System.Exception]$Exception,
		[switch]$ShowDialog,
		[string[]]$DebugTrail
	)

	if (-not $Exception) { return $null }

	$errorText = Get-GuiRuntimeFailureDetails -Context $Context -Exception $Exception -DebugTrail $DebugTrail
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
			$friendlyError = Get-BaselineErrorInfo -Exception $Exception -Context $Context
			$friendlyTitle = if ($friendlyError -and $friendlyError.PSObject.Properties['Title']) { [string]$friendlyError.Title } else { 'GUI Error' }
			$friendlyMessage = Format-BaselineErrorDialogMessage -ErrorInfo $friendlyError -LogPath $Global:LogFilePath -IncludeLogPath
			$noopButtonChrome = [scriptblock]::Create('param($Button, $Variant)')
			GUICommon\Show-ThemedDialog `
				-Theme $Script:CurrentTheme `
				-ApplyButtonChrome $noopButtonChrome `
				-OwnerWindow $Script:MainForm `
				-Title $friendlyTitle `
				-Message $friendlyMessage `
				-Buttons @('OK') `
				-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
				-AccentButton 'OK'
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

		# Debug trail is kept in memory for diagnostics only — not written to the log file.
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

function Write-GuiRuntimeWarning
{
	param (
		[string]$Context,
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) { return }

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
	  Toggle  - Enable/Disable or Show/Hide parameter pair
	  Choice  - Multiple named parameter sets (combo box)
	  Action  - No parameters; checkbox means "run this"

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
	'GameDVR' = { (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA SilentlyContinue).GameDVR_Enabled -ne 0 }
	'WindowsGameMode' = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name AutoGameModeEnabled -EA SilentlyContinue).AutoGameModeEnabled -ne 0 }
	'MouseAcceleration' = { (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name MouseSpeed -EA SilentlyContinue).MouseSpeed -ne "0" }
	'NaglesAlgorithm' = { -not ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*" -Name TCPNoDelay -EA SilentlyContinue).TCPNoDelay -contains 1) }
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

# Defined at module scope so Show-TweakGUI can capture them once for deferred
# WPF event handlers and dispatcher callbacks.
function Test-IsSafeModeUX { return ([bool]$Script:SafeMode) }
function Test-IsExpertModeUX { return ([bool]$Script:AdvancedMode) }
function Test-GuiRunInProgress { return [bool]$Script:RunInProgress }

#region GUI Builder
<#
	.SYNOPSIS
	Show the WPF tweak-selection GUI and execute selected tweaks.

	.DESCRIPTION
	Builds a modern two-tier tabbed WPF window from $Script:TweakManifest.
	The GUI stays open after each run so further changes can be made.
	Supports dark/light themes, system-scan to skip already-applied tweaks,
	info icons, caution sections, and linked toggles (PS7 <-> telemetry).

	.EXAMPLE
	Show-TweakGUI
#>
function Show-TweakGUI
{
	[CmdletBinding()]
	param ()

	# Enable per-monitor DPI awareness before any WPF objects are created
	# so the window renders at native resolution on high-DPI displays.
	try { GUICommon\Initialize-GuiDpiAwareness } catch { <# non-fatal #> }

	# --- Extracted function groups (dot-sourced to reduce file size) ---
	$Script:GuiExtractedRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'GUI'

	# Context Object and Observable State must load first - other GUI files reference $Script:Ctx
	. (Join-Path $Script:GuiExtractedRoot 'GuiContext.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'StateTransitions.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ObservableState.ps1')
	$Script:Ctx = New-GuiContext
	$Script:Ctx.Config.ExtractedRoot = $Script:GuiExtractedRoot

	. (Join-Path $Script:GuiExtractedRoot 'UxPolicy.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'SessionState.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PreviewBuilders.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ExecutionSummary.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PresetManagement.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'GameModeUI.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'GameModeState.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PreflightChecks.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'PlanSummaryPanel.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ExecutionOrchestration.ps1')


	if (-not $Script:ManifestLoadedFromData)
	{
		try
		{
			$Script:TweakManifest = Import-TweakManifestFromData `
				-DetectScriptblocks $Script:DetectScriptblocks `
				-VisibleIfScriptblocks $Script:VisibleIfScriptblocks
			Test-TweakManifestIntegrity -Manifest $Script:TweakManifest
			$Script:ManifestLoadedFromData = $true
			$Script:Ctx.Data.TweakManifest = $Script:TweakManifest
			$Script:Ctx.Data.ManifestLoaded = $true
		}
		catch
		{
			Write-Warning ("Failed to load tweak metadata from Module/Data: {0}" -f $_.Exception.Message)
			return
		}
	}

	Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

	if (-not $Script:ExplicitPresetSelections) {
		$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	}
	if (-not $Script:ExplicitPresetSelectionDefinitions) {
		$Script:ExplicitPresetSelectionDefinitions = @{}
	}

	$Script:GuiModuleBasePath = $null
	$Script:GuiPresetDirectoryPath = $null
	$Script:GuiLocalizationDirectoryPath = $null

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
	if ([string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		Write-Warning "GUI module base path could not be resolved - preset directory will not be available"
	}

	if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiModuleBasePath))
	{
		$Script:GuiPresetDirectoryPath = Join-Path -Path $Script:GuiModuleBasePath -ChildPath 'Data\Presets'
		$Script:GuiLocalizationDirectoryPath = Resolve-BaselineLocalizationDirectory -BasePath $Script:GuiModuleBasePath
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

	# Pre-compute search haystacks once so Test-TweakMatchesCurrentFilters never
	# rebuilds them on every keystroke.  All fields are static tweak metadata.
	$Script:TweakSearchHaystacks = @{}
	for ($__hi = 0; $__hi -lt $Script:TweakManifest.Count; $__hi++)
	{
		$__t = $Script:TweakManifest[$__hi]
		if (-not $__t) { continue }
		$__owning = if ($CategoryToPrimary.ContainsKey([string]$__t.Category)) { $CategoryToPrimary[[string]$__t.Category] } else { [string]$__t.Category }
		$__sb = [System.Text.StringBuilder]::new(256)
		foreach ($__p in @([string]$__t.Name, [string]$__t.Description, [string]$__t.Detail, [string]$__t.WhyThisMatters,
		                    [string]$__t.Category, [string]$__t.SubCategory, [string]$__t.Function, $__owning,
		                    [string]$__t.Risk, [string]$__t.PresetTier))
		{
			if (-not [string]::IsNullOrWhiteSpace($__p)) { [void]$__sb.Append($__p); [void]$__sb.Append(' ') }
		}
		if ($__t.Tags) { $__tags = $__t.Tags -join ' '; if ($__tags) { [void]$__sb.Append($__tags); [void]$__sb.Append(' ') } }
		[void]$__sb.Append($(if ($__t.Safe) { 'safe' } else { 'not-safe' }))
		[void]$__sb.Append(' ')
		[void]$__sb.Append($(if ($__t.Impact) { 'impact' } else { 'standard' }))
		[void]$__sb.Append(' ')
		[void]$__sb.Append($(if ($__t.RequiresRestart) { 'restart reboot requires-restart' } else { 'no-restart' }))
		$Script:TweakSearchHaystacks[$__hi] = $__sb.ToString()
	}
	Remove-Variable -Name __hi, __t, __owning, __sb, __p, __tags -ErrorAction SilentlyContinue

	# --- Phase 2 extractions (after WPF assemblies are loaded) ---
	. (Join-Path $Script:GuiExtractedRoot 'ThemeManagement.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'IconRegistry.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'IconFactory.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'TweakAnalysis.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ComponentFactory.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'FilteringLogic.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'SystemScan.ps1')

	# Write-GuiRuntimeWarning is defined at module scope (before Show-TweakGUI) so it is visible from Dispatcher.BeginInvoke closures and .GetNewClosure() scriptblocks.

	. (Join-Path $Script:GuiExtractedRoot 'EventInfrastructure.ps1')


	$Script:GuiEventHandlerStore = [System.Collections.Generic.List[object]]::new()
	$Script:GuiRuntimeCommandCache = @{}
	$Script:GuiFunctionCaptureCache = @{}
	$Script:ShowGuiRuntimeFailureScript = ${function:Show-ScopedGuiRuntimeFailure}
	$Script:TestGuiRunInProgressScript = ${function:Test-GuiRunInProgress}
	$Script:NewSafeBrushConverterScript = ${function:New-SafeBrushConverter}
	if ($Script:ShowGuiRuntimeFailureScript -isnot [scriptblock]) { throw "Show-ScopedGuiRuntimeFailure capture did not resolve to a scriptblock." }
	if ($Script:TestGuiRunInProgressScript -isnot [scriptblock]) { throw "Test-GuiRunInProgress capture did not resolve to a scriptblock." }
	if ($Script:NewSafeBrushConverterScript -isnot [scriptblock]) { throw "New-SafeBrushConverter capture did not resolve to a scriptblock." }

	$Script:DarkTheme = Repair-GuiThemePalette -Theme $Script:DarkTheme -ThemeName 'Dark'
	$Script:LightTheme = Repair-GuiThemePalette -Theme $Script:LightTheme -ThemeName 'Light'
	$Script:CurrentTheme = $Script:DarkTheme
	$Script:BrushCache = @{}
	$Script:SharedBrushConverter = [System.Windows.Media.BrushConverter]::new()
	$Script:SharedCardShadow = $null

	# Sync context - theme (read-only after init)
	$Script:Ctx.Theme.Dark = $Script:DarkTheme
	$Script:Ctx.Theme.Light = $Script:LightTheme
	$Script:Ctx.Theme.Current = $Script:CurrentTheme
	$Script:Ctx.Theme.CurrentName = 'Dark'
	$Script:Ctx.Theme.BrushConverter = $Script:SharedBrushConverter
	$Script:Ctx.Theme.BrushCache = $Script:BrushCache
	#endregion Theme colors

	Initialize-GuiIconSystem -ModuleRoot $Script:GuiModuleBasePath

	. (Join-Path $Script:GuiExtractedRoot 'StyleManagement.ps1')


	#region Themed Dialog

	. (Join-Path $Script:GuiExtractedRoot 'ExecutionSummaryDialog.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'DiffView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'ComplianceView.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'AuditView.ps1')


	# --- Dialog and tab management extractions (after XAML controls are available) ---
	. (Join-Path $Script:GuiExtractedRoot 'DialogHelpers.ps1')
	. (Join-Path $Script:GuiExtractedRoot 'TabManagement.ps1')

	$guiWindowMinWidth  = $Script:GuiLayout.WindowMinWidth
	$guiWindowMinHeight = $Script:GuiLayout.WindowMinHeight

	#region XAML template
	[xml]$XAML = @"
	<Window
		xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
		xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		Name="MainWindow"
		Title="Baseline | Utility for Windows"
	MinWidth="$guiWindowMinWidth" MinHeight="$guiWindowMinHeight"
	WindowStartupLocation="CenterScreen"
	FontFamily="Segoe UI" FontSize="13"
	ShowInTaskbar="True"
	WindowStyle="None"
	AllowsTransparency="True"
	Background="Transparent"
	ResizeMode="CanResizeWithGrip">
	<Border Name="WindowBorder" CornerRadius="8" Background="#1E1E2E" BorderBrush="#333346" BorderThickness="1" Margin="0">
	<Grid>
		<!-- Custom title bar -->
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
		</Grid.RowDefinitions>
		<Border Name="TitleBar" Grid.Row="0" Background="#181825" CornerRadius="8,8,0,0" Padding="12,8,8,8" Cursor="Arrow">
			<Grid>
				<TextBlock Name="TitleBarText" Text="Baseline | Utility for Windows" VerticalAlignment="Center" FontSize="12" Foreground="#CDD6F4"/>
				<StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
					<Button Name="BtnMinimize" Content="&#xE949;" FontFamily="Segoe MDL2 Assets" FontSize="10" Width="36" Height="28" Background="Transparent" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
					<Button Name="BtnMaximize" Content="&#xE739;" FontFamily="Segoe MDL2 Assets" FontSize="10" Width="36" Height="28" Background="Transparent" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
					<Button Name="BtnClose" Content="&#xE106;" FontFamily="Segoe MDL2 Assets" FontSize="10" Width="36" Height="28" Background="Transparent" Foreground="#CDD6F4" BorderThickness="0" Cursor="Hand" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
				</StackPanel>
			</Grid>
		</Border>
	<Grid Grid.Row="1">
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
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
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<TextBlock Name="TitleText" Grid.Column="0"
						FontSize="18" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,12,0"
						TextTrimming="CharacterEllipsis"/>
					<Button Name="BtnStartHere" Grid.Column="2" Content="Start Guide"
						FontSize="11" Margin="0,0,8,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
					<Button Name="BtnHelp" Grid.Column="3" Content="Help"
						FontSize="11" Margin="0,0,12,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
					<Button Name="BtnLog" Grid.Column="4" Content="Open Log"
						FontSize="11" Margin="0,0,12,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
					<StackPanel Grid.Column="5" Orientation="Horizontal" Margin="0,0,12,0" VerticalAlignment="Center" Visibility="Collapsed">
						<TextBlock Text="System Scan" VerticalAlignment="Center" Margin="0,0,6,0"
							Name="ScanLabel" FontSize="11"/>
						<CheckBox Name="ChkScan" VerticalAlignment="Center"/>
					</StackPanel>
					<!-- Separator between actions and state toggles -->
					<Border Name="HeaderSeparator" Grid.Column="6" Width="1" Height="28"
						Margin="4,0,14,0" VerticalAlignment="Center" Opacity="0.4"/>
					<StackPanel Grid.Column="7" Orientation="Vertical" Margin="0,0,18,0" VerticalAlignment="Center">
						<StackPanel Orientation="Horizontal">
							<CheckBox Name="ChkSafeMode" VerticalAlignment="Center" Content="Safe Mode" Margin="0,0,14,0"/>
							<CheckBox Name="ChkGameMode" Visibility="Collapsed"/>
						</StackPanel>
						<TextBlock Name="TxtAdvancedModeState" Margin="2,4,0,0" FontSize="10" Text="" ToolTip="Saved with your GUI session and restored on next launch."/>
					</StackPanel>
					<StackPanel Grid.Column="8" Orientation="Vertical" VerticalAlignment="Center" Margin="0,0,18,0">
						<CheckBox Name="ChkTheme" VerticalAlignment="Center" Content="Light Mode"/>
						<TextBlock Name="TxtThemeState" Margin="2,4,0,0" FontSize="10" Text="Theme: Dark" ToolTip="Saved with your GUI session and restored on next launch."/>
					</StackPanel>
					<StackPanel Grid.Column="9" Orientation="Vertical" VerticalAlignment="Center" Margin="0,0,4,0">
						<Button Name="BtnLanguage" Padding="8,4" Cursor="Hand" VerticalAlignment="Center" ToolTip="Change language" Content="Language"/>
						<Popup Name="LanguagePopup" StaysOpen="False" Placement="Bottom" PlacementTarget="{Binding ElementName=BtnLanguage}" AllowsTransparency="True">
							<Border Name="LanguagePopupBorder" BorderThickness="1" CornerRadius="6" Padding="6">
								<StackPanel Width="208">
									<Grid Margin="0,0,0,6">
										<TextBox Name="TxtLanguageSearch" Height="28" Padding="10,4" VerticalContentAlignment="Center" ToolTip="Search available languages"/>
										<TextBlock Name="TxtLanguageSearchPlaceholder" Text="Search languages..."
											Margin="12,0,28,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
									</Grid>
									<ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="320">
										<StackPanel Name="LanguageListPanel"/>
									</ScrollViewer>
								</StackPanel>
							</Border>
						</Popup>
						<TextBlock Name="TxtLanguageState" Margin="2,4,0,0" FontSize="10" Text="" ToolTip="Saved with your GUI session and restored on next launch."/>
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
				<StackPanel Grid.Row="2" Margin="0,8,0,0" Orientation="Vertical">
					<Button Name="BtnFilterToggle" Content="Filters &#x25B8;" HorizontalAlignment="Left"
						FontSize="11" Padding="8,3" Cursor="Hand" Background="Transparent" BorderThickness="0"/>
					<WrapPanel Name="FilterOptionsPanel" Margin="0,6,0,0" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
						<TextBlock Name="RiskFilterLabel" Text="Risk" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
						<ComboBox Name="CmbRiskFilter" Width="138" Height="30" Margin="0,0,16,0" VerticalContentAlignment="Center"/>
						<TextBlock Name="CategoryFilterLabel" Text="Category" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
						<ComboBox Name="CmbCategoryFilter" Width="220" Height="30" Margin="0,0,16,0" VerticalContentAlignment="Center"/>
						<TextBlock Name="ViewFilterLabel" Text="View" Margin="0,0,10,0" VerticalAlignment="Center" FontSize="11"/>
						<CheckBox Name="ChkSelectedOnly" Content="Selected only" Margin="0,0,14,0" VerticalAlignment="Center" FontSize="11" ToolTip="Show only tweaks that are currently selected in the GUI."/>
						<CheckBox Name="ChkHighRiskOnly" Content="High-risk only" Margin="0,0,14,0" VerticalAlignment="Center" FontSize="11" ToolTip="Show only high-risk tweaks."/>
						<CheckBox Name="ChkRestorableOnly" Content="Restorable only" Margin="0,0,14,0" VerticalAlignment="Center" FontSize="11" ToolTip="Hide tweaks that require manual recovery."/>
						<CheckBox Name="ChkGamingOnly" Content="Gaming-related" VerticalAlignment="Center" FontSize="11" ToolTip="Show tweaks that relate to gaming performance, compatibility, or gaming quality-of-life."/>
					</WrapPanel>
				</StackPanel>
			</Grid>
		</Border>
		<!-- Primary tab bar -->
			<Grid Name="PrimaryTabHost" Grid.Row="1" Margin="8,4,8,0">
				<!-- Primary tab row -->
				<TabControl Name="PrimaryTabs" Padding="0">
					<TabControl.Template>
						<ControlTemplate TargetType="TabControl">
							<ScrollViewer Name="PrimaryTabHeaderScroll"
								HorizontalScrollBarVisibility="Auto"
								VerticalScrollBarVisibility="Disabled"
								CanContentScroll="False"
								Focusable="False">
								<StackPanel Name="HeaderPanel"
									Orientation="Horizontal"
									IsItemsHost="True"/>
							</ScrollViewer>
						</ControlTemplate>
					</TabControl.Template>
					<TabControl.Resources>
						<Style TargetType="TabItem">
						<Setter Property="Template">
							<Setter.Value>
								<ControlTemplate TargetType="TabItem">
									<Border Background="{TemplateBinding Background}"
											BorderBrush="{TemplateBinding BorderBrush}"
											BorderThickness="{TemplateBinding BorderThickness}"
											Padding="{TemplateBinding Padding}"
											Margin="1,0"
											SnapsToDevicePixels="True"
											Cursor="Hand">
										<ContentPresenter
											ContentSource="Header"
											HorizontalAlignment="Center"
											VerticalAlignment="Center"
											TextBlock.Foreground="{TemplateBinding Foreground}"
											TextBlock.FontWeight="{TemplateBinding FontWeight}"/>
									</Border>
								</ControlTemplate>
							</Setter.Value>
						</Setter>
						</Style>
					</TabControl.Resources>
				</TabControl>
				<!-- Legacy narrow-mode picker kept hidden; the desktop UI stays on a fixed tab row. -->
				<ComboBox Name="PrimaryTabDropdown" Visibility="Collapsed"
					HorizontalAlignment="Left" Width="280" Height="32" MaxDropDownHeight="300"
					VerticalContentAlignment="Center" FontSize="13"/>
			</Grid>
		<!-- Expert Mode banner (visible only in Expert Mode) -->
		<Border Name="ExpertModeBanner" Grid.Row="2" Visibility="Collapsed" Padding="6,4" Margin="8,0,8,0">
			<TextBlock Text="EXPERT MODE &#x2014; all presets and advanced tweaks are available"
				FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center"
				Padding="12,2"/>
		</Border>
		<!-- Content area (filled by tab selection) -->
		<Border Name="ContentBorder" Grid.Row="3" Margin="8,0,8,4">
			<ScrollViewer Name="ContentScroll" VerticalScrollBarVisibility="Auto"
				HorizontalScrollBarVisibility="Disabled"/>
		</Border>
		<!-- Bottom bar -->
		<Border Name="BottomBorder" Grid.Row="4" Padding="10,14,10,8" BorderThickness="0,1,0,0">
			<Grid>
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>
				<Grid Grid.Row="0">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<StackPanel Name="ActionButtonBar" Grid.Column="0"
						Orientation="Vertical" VerticalAlignment="Top" HorizontalAlignment="Left">
						<Button Name="BtnDefaults" Content="Restore to Windows Defaults"
							FontSize="11" Margin="4,0,4,0" Padding="12,6" Cursor="Hand"/>
					</StackPanel>
					<WrapPanel Name="BottomActionBar" Grid.Column="1"
						Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
						<Button Name="BtnPreviewRun" Content="Preview Run"
							FontSize="13" Margin="4" Padding="18,10" Cursor="Hand" FontWeight="SemiBold" MinWidth="160"/>
						<Button Name="BtnRun" Content="Run Tweaks"
							FontSize="15" Margin="4" Padding="28,12" Cursor="Hand" FontWeight="Bold" MinWidth="170"/>
					</WrapPanel>
				</Grid>
				<Grid Grid.Row="1" Margin="0,10,0,0">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*"/>
						<ColumnDefinition Width="Auto"/>
					</Grid.ColumnDefinitions>
					<TextBlock Name="StatusText" Grid.Column="0" VerticalAlignment="Center"
						FontSize="12" Margin="4,0,16,0" TextWrapping="Wrap" Visibility="Collapsed"/>
					<TextBlock Name="RunPathContextLabel" Grid.Column="1" HorizontalAlignment="Right"
						VerticalAlignment="Center" FontSize="11" Margin="4,0,8,0" Visibility="Collapsed"/>
				</Grid>
			</Grid>
		</Border>
	</Grid>
</Grid>
</Border>
</Window>
"@
	#endregion XAML template

	$loadedForm = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XAML))

	if (-not ($loadedForm -is [System.Windows.Window]))
	{
		throw "XAML root did not load as System.Windows.Window. Actual type: $($loadedForm.GetType().FullName)"
	}

	[System.Windows.Window]$Form = $loadedForm
	$Script:MainForm = $Form

	# Size the window to 85% of the screen working area so it fits any resolution
	# without being full-screen. Falls back to safe defaults if the call fails.
	try
	{
		$workArea = [System.Windows.SystemParameters]::WorkArea
		$widthRatio = if ($workArea.Width -ge 2560) { 0.55 } elseif ($workArea.Width -ge 1920) { 0.65 } else { 0.85 }
		$targetW  = [Math]::Round($workArea.Width  * $widthRatio)
		$targetH  = [Math]::Round($workArea.Height * 0.85)
		$maxW = [Math]::Min(1400, $workArea.Width)

		# On small screens, clamp MinWidth to the available work area
		$effectiveMinW = [Math]::Min($guiWindowMinWidth, $workArea.Width)
		$effectiveMinH = [Math]::Min($guiWindowMinHeight, $workArea.Height)

		$Form.MinWidth  = $effectiveMinW
		$Form.MinHeight = $effectiveMinH
		$Form.Width  = [Math]::Min([Math]::Max($targetW, $effectiveMinW), $maxW)
		$Form.Height = [Math]::Min([Math]::Max($targetH, $effectiveMinH), $workArea.Height)
	}
	catch
	{
		$Form.MinWidth = $guiWindowMinWidth
		$Form.MinHeight = $guiWindowMinHeight
		$Form.Width  = [Math]::Max(940, $guiWindowMinWidth)
		$Form.Height = [Math]::Max(720, $guiWindowMinHeight)
	}
	$HeaderBorder    = $Form.FindName("HeaderBorder")
	$HeaderSeparator = $Form.FindName("HeaderSeparator")
	$TitleText       = $Form.FindName("TitleText")
	$WindowBorder  = $Form.FindName("WindowBorder")
	$TitleBar      = $Form.FindName("TitleBar")
	$TitleBarText  = $Form.FindName("TitleBarText")
	$BtnMinimize   = $Form.FindName("BtnMinimize")
	$BtnMaximize   = $Form.FindName("BtnMaximize")
	$BtnClose      = $Form.FindName("BtnClose")

	# Wire custom title bar: drag, minimize, maximize, close
	if ($TitleBar)
	{
		$TitleBar.Add_MouseLeftButtonDown({
			if ($_.ClickCount -eq 2)
			{
				if ($Form.WindowState -eq [System.Windows.WindowState]::Maximized)
				{
					$Form.WindowState = [System.Windows.WindowState]::Normal
				}
				else
				{
					$Form.WindowState = [System.Windows.WindowState]::Maximized
				}
			}
			else
			{
				$Form.DragMove()
			}
		})
	}
	if ($BtnMinimize) { $BtnMinimize.Add_Click({ $Form.WindowState = [System.Windows.WindowState]::Minimized }) }
	if ($BtnMaximize)
	{
		$BtnMaximize.Add_Click({
			if ($Form.WindowState -eq [System.Windows.WindowState]::Maximized)
			{
				$Form.WindowState = [System.Windows.WindowState]::Normal
			}
			else
			{
				$Form.WindowState = [System.Windows.WindowState]::Maximized
			}
		})
	}
	if ($BtnClose) { $BtnClose.Add_Click({ $Form.Close() }) }

	# Adjust border radius when maximized (no rounding needed when filling screen)
	$Form.Add_StateChanged({
		if ($Form.WindowState -eq [System.Windows.WindowState]::Maximized)
		{
			$WindowBorder.CornerRadius = [System.Windows.CornerRadius]::new(0)
			$WindowBorder.Margin = [System.Windows.Thickness]::new(7)
			if ($TitleBar) { $TitleBar.CornerRadius = [System.Windows.CornerRadius]::new(0) }
		}
		else
		{
			$WindowBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
			$WindowBorder.Margin = [System.Windows.Thickness]::new(0)
			if ($TitleBar) { $TitleBar.CornerRadius = [System.Windows.CornerRadius]::new(8, 8, 0, 0) }
		}
	})
	$PrimaryTabs   = $Form.FindName("PrimaryTabs")
	$PrimaryTabDropdown = $Form.FindName("PrimaryTabDropdown")
	$PrimaryTabHost = $Form.FindName("PrimaryTabHost")
	$ContentBorder = $Form.FindName("ContentBorder")
	$ContentScroll = $Form.FindName("ContentScroll")
	$ExpertModeBanner = $Form.FindName("ExpertModeBanner")
	$BottomBorder  = $Form.FindName("BottomBorder")
	$StatusText    = $Form.FindName("StatusText")
	$Script:StatusTextControl = $StatusText
	$ActionButtonBar = $Form.FindName("ActionButtonBar")
	$BtnPreviewRun = $Form.FindName("BtnPreviewRun")
	$BtnRun        = $Form.FindName("BtnRun")
	$Script:RunPathContextLabel = $Form.FindName("RunPathContextLabel")
	$BtnDefaults   = $Form.FindName("BtnDefaults")
	$BtnExportSettings = $null
	$BtnImportSettings = $null
	$BtnRestoreSnapshot = $null
	$ChkTheme      = $Form.FindName("ChkTheme")
	$BtnLanguage   = $Form.FindName("BtnLanguage")
	$LanguagePopup = $Form.FindName("LanguagePopup")
	$LanguagePopupBorder = $Form.FindName("LanguagePopupBorder")
	$TxtLanguageSearch = $Form.FindName("TxtLanguageSearch")
	$TxtLanguageSearchPlaceholder = $Form.FindName("TxtLanguageSearchPlaceholder")
	$LanguageListPanel = $Form.FindName("LanguageListPanel")
	$TxtLanguageState = $Form.FindName("TxtLanguageState")
	$ChkSafeMode   = $Form.FindName("ChkSafeMode")
	$ChkGameMode   = $Form.FindName("ChkGameMode")
	$TxtAdvancedModeState = $Form.FindName("TxtAdvancedModeState")
	$TxtThemeState = $Form.FindName("TxtThemeState")
	$BtnStartHere  = $Form.FindName("BtnStartHere")
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
	$ChkSelectedOnly = $Form.FindName("ChkSelectedOnly")
	$ChkHighRiskOnly = $Form.FindName("ChkHighRiskOnly")
	$ChkRestorableOnly = $Form.FindName("ChkRestorableOnly")
	$ChkGamingOnly = $Form.FindName("ChkGamingOnly")
	$BtnFilterToggle = $Form.FindName("BtnFilterToggle")
	$FilterOptionsPanel = $Form.FindName("FilterOptionsPanel")
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
		$Script:ForceCloseCompleted = $false
		$Script:ExecutionTimerErrorShown = $false
	$Script:AbortDialogShowing = $false
	$Script:BgPS = $null
	$Script:BgAsync = $null
	$Script:SearchText = ''
	$Script:SearchResultsTabTag = '__SEARCH_RESULTS__'
	$Script:LastStandardPrimaryTab = $null
	$Script:TabScrollOffsets = @{}
	$Script:TabContentCache = @{}
	$Script:CategoryFilterListCache = @{}
	$Script:LastCategoryFilterPopulateKey = $null
	$Script:FilterGeneration = 0
	$Script:SearchRefreshTimer = $null
	$Script:SearchRefreshDelayMs = $Script:GuiLayout.SearchRefreshDelayMs
	$Script:CurrentThemeName = 'Dark'
	$Script:UiSnapshotUndo = $null
	$Script:PresetStatusMessage = $null
	$Script:PresetStatusTone = 'info'
	$Script:PresetStatusBadge = $null
	$Script:EnvironmentRecommendationData = $null
	$Script:EnvironmentSummaryText = $null
	$Script:SecondaryActionGroupBorder = $null
	$previousGuiUnhandledExceptionHooked = [bool]$Script:GuiUnhandledExceptionHooked
	$previousGuiUnhandledExceptionHandler = $Script:GuiUnhandledExceptionHandler
	$previousGuiDispatcher = if ($Script:MainForm -and $Script:MainForm.Dispatcher)
	{
		$Script:MainForm.Dispatcher
	}
	elseif ($Form -and $Form.Dispatcher)
	{
		$Form.Dispatcher
	}
	else
	{
		$null
	}

	if ($previousGuiUnhandledExceptionHooked -and $previousGuiUnhandledExceptionHandler -and $previousGuiDispatcher)
	{
		try
		{
			$previousGuiDispatcher.remove_UnhandledException($previousGuiUnhandledExceptionHandler)
		}
		catch
		{
			$null = $_
		}
	}

	$Script:GuiUnhandledExceptionHooked = $false
	$Script:GuiUnhandledExceptionHandler = $null
	$Script:ExplicitPresetSelections = [System.Collections.Generic.HashSet[string]]::new(
		[System.StringComparer]::OrdinalIgnoreCase
	)
	$Script:ExplicitPresetSelectionDefinitions = @{}

	$Script:GuiDispatcherHandlingError = $false
	if (-not $Script:GuiUnhandledExceptionHooked -and $Form -and $Form.Dispatcher)
	{
		$Script:GuiUnhandledExceptionHandler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
			param($unusedSender, $e)

			if ($Script:GuiDispatcherHandlingError)
			{
				$e.Handled = $true
				return
			}
			$Script:GuiDispatcherHandlingError = $true

			$isFatal = $false
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

				# Treat critical .NET exceptions as fatal - do not suppress them
				$ex = $e.Exception
				$isFatal = $ex -is [System.StackOverflowException] -or
					$ex -is [System.OutOfMemoryException] -or
					$ex -is [System.AccessViolationException] -or
					$ex -is [System.InvalidProgramException]
			}
			catch
			{
				# If our own handler fails, the original exception must not be swallowed
				$isFatal = $true
			}
			finally
			{
				$Script:GuiDispatcherHandlingError = $false
			}

			$e.Handled = -not $isFatal
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
	$Script:SelectedOnlyFilter = $false
	$Script:HighRiskOnlyFilter = $false
	$Script:RestorableOnlyFilter = $false
	$Script:GamingOnlyFilter = $false
	$Script:SafeMode = $true
	$Script:AdvancedMode = $false

	# Auto-detect language from system UI culture. Session restore may override this.
	$Script:SelectedLanguage = $null
	$cultureToFileMap = @{ 'zh-cn' = 'zh-Hans'; 'zh-sg' = 'zh-Hans'; 'zh-tw' = 'zh-Hant'; 'zh-hk' = 'zh-Hant'; 'zh-mo' = 'zh-Hant' }
	$uiCultureLower = $PSUICulture.ToLower()
	$autoLangCandidates = @()
	if ($cultureToFileMap.ContainsKey($uiCultureLower)) { $autoLangCandidates += $cultureToFileMap[$uiCultureLower] }
	$autoLangCandidates += @($uiCultureLower, ($PSUICulture -split '-')[0].ToLower())
	$locDirInit = $Script:GuiLocalizationDirectoryPath
	foreach ($candidate in $autoLangCandidates)
	{
		if (-not [string]::IsNullOrWhiteSpace([string]$locDirInit) -and (Test-Path -LiteralPath (Join-Path $locDirInit "$candidate.json") -PathType Leaf))
		{
			$Script:SelectedLanguage = $candidate
			break
		}
	}
	if (-not $Script:SelectedLanguage) { $Script:SelectedLanguage = 'en' }
	Initialize-GameModeState
	$Script:FilterUiUpdating = $false
	$Script:ExecutionSummaryRecords = @()
	$Script:ExecutionSummaryLookup = @{}
	$Script:ExecutionCurrentSummaryKey = $null
	$Script:GuiDisplayVersion = Get-BaselineDisplayVersion

		# Keep the native window title concise while the in-app header carries the display version.
		$headerTitle = $Form.Title
		try
		{
			$windowTitle = "Baseline | Utility for $((Get-OSInfo).OSName)"
			$Form.Title = $windowTitle
			if ($TitleBarText) { $TitleBarText.Text = $windowTitle }
			$headerTitle = $windowTitle
			if (-not [string]::IsNullOrWhiteSpace([string]$Script:GuiDisplayVersion))
			{
				$headerTitle = "{0} {1}" -f $headerTitle, $Script:GuiDisplayVersion
			}
		}
		catch { Write-GuiRuntimeWarning -Context 'WindowTitle' -Message $_.Exception.Message }
		$TitleText.Text = $headerTitle


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
			$Script:BrushCache = @{}
			$Script:SharedCardShadow = $null
			$Script:CardHoverResources = $null
			$bc = New-SafeBrushConverter -Context 'Set-GUITheme'

		$Form.Foreground  = $bc.ConvertFromString($Theme.TextPrimary)
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $Form -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
		if ($WindowBorder) { $WindowBorder.Background = $bc.ConvertFromString($Theme.WindowBg); $WindowBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor) }
		if ($TitleBar) { $TitleBar.Background = $bc.ConvertFromString($Theme.HeaderBg) }
		if ($TitleBarText) { $TitleBarText.Foreground = $bc.ConvertFromString($Theme.TextPrimary) }
		if ($BtnMinimize) { Set-WindowCaptionButtonStyle -Button $BtnMinimize }
		if ($BtnMaximize) { Set-WindowCaptionButtonStyle -Button $BtnMaximize }
		if ($BtnClose) { Set-WindowCaptionButtonStyle -Button $BtnClose -Variant 'Close' }
		$HeaderBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		if ($HeaderSeparator) { $HeaderSeparator.Background = $bc.ConvertFromString($Theme.BorderColor) }
		$ContentBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		if ($ExpertModeBanner)
		{
			$ExpertModeBanner.Background = $bc.ConvertFromString($Theme.CautionBg)
			$bannerText = $ExpertModeBanner.Child
			if ($bannerText) { $bannerText.Foreground = $bc.ConvertFromString($Theme.CautionText) }
		}
		$BottomBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$BottomBorder.BorderBrush = $bc.ConvertFromString($Theme.BorderColor)
		$TitleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
		$ScanLabel.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$currentStatusText = ''
		if ($Script:GuiState)
		{
			try { $currentStatusText = [string](& $Script:GuiState.Get 'StatusText') } catch { $currentStatusText = '' }
		}
		elseif ($StatusText)
		{
			$currentStatusText = [string]$StatusText.Text
		}
		Set-GuiStatusText -Text $currentStatusText -Tone $(if ($Script:CurrentStatusTone) { [string]$Script:CurrentStatusTone } else { 'muted' })
		Set-HeaderToggleControlsStyle
		Set-SearchInputStyle
		Set-FilterControlStyle
		Set-StaticButtonStyle
		Update-PrimaryTabVisuals

		# Rebuild content for current tab to pick up new theme colors.
		$Script:FilterGeneration++
		Clear-TabContentCache
		if ($null -ne $Script:CurrentPrimaryTab)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab -SkipIdlePrebuild
		}
		Update-HeaderModeStateText
		if (Get-Command -Name 'Update-RunPathContextLabel' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Update-RunPathContextLabel
		}
	}
	#endregion


	#region Helper: Create styled controls

	. (Join-Path $Script:GuiExtractedRoot 'TweakVisualization.ps1')

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
				$Script:ExecutionProgressText.Text = if ($CurrentAction) { $CurrentAction } else { Get-UxExecutionPlaceholderText -Kind 'Preparing' }
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
					$Script:ExecutionSubProgressText.Text = if ($SubAction) { $SubAction } else { Get-UxExecutionPlaceholderText -Kind 'Working' }
				}
			}
		}

		# Sync observable state for progress subscribers
		if ($Script:GuiState -and $Total -gt 0)
		{
			& $Script:GuiState.SetBatch @{
				ProgressCompleted = $Completed
				ProgressTotal     = $Total
				ProgressAction    = $CurrentAction
			}
		}
	}

		function Invoke-GuiEvents
		{
			$frame = New-Object System.Windows.Threading.DispatcherFrame
			$scheduled = Invoke-GuiDispatcherAction -Dispatcher $Form.Dispatcher -PriorityUsage 'Pump' -Action {
				$frame.Continue = $false
			}
			if ($scheduled)
			{
				[System.Windows.Threading.Dispatcher]::PushFrame($frame)
			}
		}

		function Close-GuiMainWindow
		{
			param (
				[string]$Reason = 'GUI close requested.'
			)

			Write-Host ("[Close-GuiMainWindow] {0}" -f $Reason)
			if ($Script:MainForm)
			{
				try { $Script:MainForm.Close() } catch { Write-GuiRuntimeWarning -Context 'Close-GuiMainWindow' -Message ("Failed to close main form: {0}" -f $_.Exception.Message) }
			}
		}

		$Script:ForceCloseExecutionFn = {
			Set-RunAbortDisposition -Disposition 'Exit'
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
				try { $timerToStop.Dispose() } catch { $null = $_ }
			}

			$Script:SuppressRunClosePrompt = $true

			if ($workerToStop)
			{
				GUIExecution\Stop-GuiExecutionWorkerAsync -Worker $workerToStop
			}

			$Script:ExecutionRunTimer = $null
			$Script:ExecutionWorker = $null
			$Script:ExecutionRunPowerShell = $null
			$Script:ExecutionRunspace = $null
			$Script:BgPS = $null
			$Script:BgAsync = $null
			$Script:RunInProgress = $false

			if ($Script:MainForm)
			{
				try
				{
					$null = Invoke-GuiDispatcherAction -Dispatcher $Script:MainForm.Dispatcher -PriorityUsage 'Immediate' -Action {
	                try { Close-GuiMainWindow -Reason 'ForceCloseExecutionFn requested immediate exit.' } catch { $null = $_ }
	                try
	                {
	                        if ([System.Windows.Application]::Current)
                        {
                                [System.Windows.Application]::Current.Shutdown()
                        }
                }
                catch { $null = $_ }
	        }
				}
				catch
				{
					try { Close-GuiMainWindow -Reason 'ForceCloseExecutionFn fallback close.' } catch { $null = $_ }
				}
			}

		$Script:ForceCloseCompleted = $true
	}

		$Script:RequestRunAbortFn = {
			param(
				[switch]$ExitNow
			)

			if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

			if ($ExitNow)
			{
				Set-RunAbortDisposition -Disposition 'Exit'
			}
			elseif ([string]::IsNullOrWhiteSpace([string]$Script:RunAbortDisposition))
			{
				Set-RunAbortDisposition -Disposition 'Return'
			}

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
		Set-GuiStatusText -Text $(if ($ExitNow) { "Exit requested. Closing Baseline now..." } else { "Abort requested. Waiting for the current step to stop..." }) -Tone 'caution'
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
			# Run completed while the dialog was open - nothing to abort
			return
		}

			switch ($choice)
			{
				'Return to Tweaks'
				{
					Set-RunAbortDisposition -Disposition 'Return'
					& $Script:RequestRunAbortFn
				}
				'Exit Now'
				{
					Set-RunAbortDisposition -Disposition 'Exit'
					& $Script:RequestRunAbortFn -ExitNow
				}
				default
				{
					Set-RunAbortDisposition -Disposition $null
				}
			}
		}


	#endregion


	#region Build controls for a set of tweaks
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
				$Script:Controls[$si] = [pscustomobject]@{ SelectedIndex = [int]-1; IsEnabled = $isVisible }
			}
		}
	}

	# Pending linked states for tweaks whose target tab is not yet built
	$Script:PendingLinkedChecks   = [System.Collections.Generic.HashSet[string]]::new()
	$Script:PendingLinkedUnchecks = [System.Collections.Generic.HashSet[string]]::new()
	$Script:ApplyingGuiPreset     = $false  # suppress linked sync while applying an explicit preset
	# Applied-this-session tracking for system scan
	$Script:AppliedTweaks = [System.Collections.Generic.HashSet[string]]::new()

		function Update-CurrentTabContent
		{
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
			param (
				[switch]$SkipIdlePrebuild
			)

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

			if ([string]::IsNullOrWhiteSpace($targetTab)) { return }
			$updateCategoryFilterListScript = if ($Script:UpdateCategoryFilterListScript) { $Script:UpdateCategoryFilterListScript } else { ${function:Update-CategoryFilterList} }
			$updatePrimaryTabVisualsScript = if ($Script:UpdatePrimaryTabVisualsScript) { $Script:UpdatePrimaryTabVisualsScript } else { ${function:Update-PrimaryTabVisuals} }
			$buildTabContentScript = if ($Script:BuildTabContentScript) { $Script:BuildTabContentScript } else { ${function:Build-TabContent} }
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

	. (Join-Path $Script:GuiExtractedRoot 'ModeState.ps1')


	. (Join-Path $Script:GuiExtractedRoot 'PresetApplication.ps1')


	function Set-SecondaryActionGroupStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		if (-not $Script:SecondaryActionGroupBorder) { return }
		$bc = New-SafeBrushConverter -Context 'Set-SecondaryActionGroupStyle'
		$Script:SecondaryActionGroupBorder.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$Script:SecondaryActionGroupBorder.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.BorderColor)
		$Script:SecondaryActionGroupBorder.Opacity = 0.7
	}

	function Set-StaticButtonStyle
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		Set-ButtonChrome -Button $BtnRun -Variant 'Primary'
		if ($BtnPreviewRun) { Set-ButtonChrome -Button $BtnPreviewRun -Variant 'Preview' }
		Set-ButtonChrome -Button $BtnDefaults -Variant 'DangerSubtle'
		if ($BtnStartHere) { Set-ButtonChrome -Button $BtnStartHere -Variant 'Subtle' -Compact -Muted }
		if ($BtnHelp) { Set-ButtonChrome -Button $BtnHelp -Variant 'Subtle' -Compact -Muted }
		if ($BtnLanguage) { Set-ButtonChrome -Button $BtnLanguage -Variant 'Subtle' -Compact -Muted }
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
			$ChkSafeMode,
			$ChkTheme,
			$BtnLanguage,
			$TxtSearch,
			$BtnClearSearch,
			$CmbRiskFilter,
			$CmbCategoryFilter,
			$ChkSelectedOnly,
			$ChkHighRiskOnly,
			$ChkRestorableOnly,
			$ChkGamingOnly,
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

	. (Join-Path $Script:GuiExtractedRoot 'ContentManagement.ps1')


	. (Join-Path $Script:GuiExtractedRoot 'TweakRowFactory.ps1')


	#region Build tab content for a primary category
	$Script:CurrentPrimaryTab = $null
	$Script:SubTabControls = @{}


	. (Join-Path $Script:GuiExtractedRoot 'PresetUI.ps1')


	function Add-TabSectionsToPanel
	{
		param ([object]$BuildContext)

		foreach ($subKey in $BuildContext.CategoryTweaks.Keys)
		{
			try
			{
				$indexes = $BuildContext.CategoryTweaks[$subKey]
			}
			catch
			{
				throw "Build-TabContent/ResolveSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
			}

			$showSectionHeader = $BuildContext.IsSearchResultsTab -or ($BuildContext.CategoryTweaks.Count -gt 1) -or ([string]$subKey -ne 'General')
			if ($showSectionHeader)
			{
				try
				{
					[void]($BuildContext.MainPanel.Children.Add((New-SectionHeader -Text $subKey)))
				}
				catch
				{
					throw "Build-TabContent/SectionHeader for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
				}
			}

			try
			{
				$cautionTweaksList = [System.Collections.Generic.List[object]]::new()
				foreach ($index in $indexes)
				{
					if ($Script:TweakManifest[$index].Caution)
					{
						$cautionTweaksList.Add($Script:TweakManifest[$index])
					}
				}
				$cautionTweaks = $cautionTweaksList
			}
			catch
			{
				throw "Build-TabContent/CollectCautionTweaks for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
			}

			foreach ($index in $indexes)
			{
				try
				{
					$tweak = $Script:TweakManifest[$index]
				}
				catch
				{
					throw "Build-TabContent/ResolveTweak for tab '$($BuildContext.PrimaryTab)' at index $index failed: $($_.Exception.Message)"
				}

				try
				{
					$row = Build-TweakRow -Index $index -Tweak $tweak -BrushConverter $BuildContext.BrushConverter
				}
				catch
				{
					throw "Build-TabContent/Row for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
				}

				if ($row)
				{
					try
					{
						[void]($BuildContext.MainPanel.Children.Add($row))
					}
					catch
					{
						throw "Build-TabContent/AddRow for tab '$($BuildContext.PrimaryTab)' failed at index $index ($([string]$tweak.Type) / $([string]$tweak.Function) / $([string]$tweak.Name)): $($_.Exception.Message)"
					}
				}
			}

			try
			{
				$cautionSection = New-CautionSection -CautionTweaks $cautionTweaks
			}
			catch
			{
				throw "Build-TabContent/CautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
			}

			if ($cautionSection)
			{
				try
				{
					[void]($BuildContext.MainPanel.Children.Add($cautionSection))
				}
				catch
				{
					throw "Build-TabContent/AddCautionSection for tab '$($BuildContext.PrimaryTab)' section '$([string]$subKey)' failed: $($_.Exception.Message)"
				}
			}
		}
	}

	function Save-TabContentCacheEntry
	{
		param (
			[object]$BuildContext,
			[int[]]$AllTabIndexes,
			[switch]$CacheOnly
		)

		if (-not $CacheOnly)
		{
			$ContentScroll.Content = $BuildContext.MainPanel
		}
		$controlRefs = @{}
		foreach ($index in @($AllTabIndexes))
		{
			if ($Script:Controls.ContainsKey($index) -and $Script:Controls[$index])
			{
				$controlRefs[[int]$index] = $Script:Controls[$index]
			}
		}
		$Script:TabContentCache[$BuildContext.PrimaryTab] = @{
			Panel = $BuildContext.MainPanel
			ControlRefs = $controlRefs
			PresetStatusBadge = $Script:PresetStatusBadge
			FilterGeneration = $Script:FilterGeneration
		}
	}

	# Helper for Dispatcher.BeginInvoke tab pre-builds. Uses [scriptblock]::Create()
	# to embed $Tag as a string literal — PowerShell scriptblocks use dynamic scoping
	# so function parameters do not survive past the function return. The block is then
	# re-bound to this module so $Script: variables and sibling functions
	# (Build-TabContent, Test-GuiRunInProgress, etc.) remain resolvable.
	function New-TabPreBuildAction
	{
		param ([string]$Tag)
		$safe = $Tag -replace "'", "''"
		$sb = [scriptblock]::Create(@"
try
{
	if (-not (Test-GuiRunInProgress) -and -not (`$Script:TabContentCache -and `$Script:TabContentCache.ContainsKey('$safe')))
	{
		Build-TabContent -PrimaryTab '$safe' -BackgroundBuild
	}
}
catch { Write-GuiRuntimeWarning -Context 'TabPreBuild:$safe' -Message `$_.Exception.Message }
"@)
		$mod = $ExecutionContext.SessionState.Module
		if ($mod) { $sb = $mod.NewBoundScriptBlock($sb) }
		return $sb
	}

	function Build-TabContent
	{
		param (
			[string]$PrimaryTab,
			[switch]$BackgroundBuild,
			[switch]$SkipIdlePrebuild
		)

		if (-not $BackgroundBuild)
		{
			$Script:CurrentPrimaryTab = $PrimaryTab
			$Script:PresetStatusBadge = $null
			if (Restore-CachedTabContent -PrimaryTab $PrimaryTab)
			{
				return
			}
		}
		elseif ($Script:TabContentCache.ContainsKey($PrimaryTab))
		{
			return
		}

		try
		{
			$buildContext = New-TabContentBuildContext -PrimaryTab $PrimaryTab
		}
		catch
		{
			throw "Build-TabContent/Preamble for tab '$PrimaryTab' failed: $($_.Exception.Message)"
		}

		Add-TabContentLeadPanel -BuildContext $buildContext

		$activeFilterItems = Get-ActiveTabFilterItems -BuildContext $buildContext
		if ($activeFilterItems.Count -gt 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-ActiveFiltersBanner -BuildContext $buildContext -ActiveFilterItems $activeFilterItems)))
			}
			catch
			{
				Write-GuiRuntimeWarning -Context 'Build-TabContent/ActiveFiltersBanner' -Message ("Active filters banner failed for tab '{0}': {1}" -f $PrimaryTab, $_.Exception.Message)
			}
		}

		if ($buildContext.CategoryTweaks.Count -eq 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-EmptyTabStateCard -BuildContext $buildContext -HasActiveFilters:($activeFilterItems.Count -gt 0))))
			}
			catch
			{
				throw "Build-TabContent/EmptyState for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
		}

		try
		{
			$allTabIndexes = Get-TabContentIndexArray -CategoryTweaks $buildContext.CategoryTweaks
		}
		catch
		{
			throw "Build-TabContent/CollectTabIndexes for tab '$PrimaryTab' failed: $($_.Exception.Message)"
		}

		if ($allTabIndexes.Count -gt 0)
		{
			try
			{
				[void]($buildContext.MainPanel.Children.Add((New-TabSelectionBar -AllTabIndexes $allTabIndexes)))
			}
			catch
			{
				throw "Build-TabContent/SelectionBar for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
		}

		# Suspend WPF layout passes while adding tweak rows to avoid
		# expensive per-child Measure/Arrange cycles.
		$panelSuspended = $false
		try
		{
			if ($buildContext.MainPanel -is [System.Windows.FrameworkElement])
			{
				$buildContext.MainPanel.BeginInit()
				$panelSuspended = $true
			}
		}
		catch { <# BeginInit not critical — continue without suspension #> }

		Add-TabSectionsToPanel -BuildContext $buildContext

		if ($panelSuspended)
		{
			try { $buildContext.MainPanel.EndInit() } catch { <# non-fatal #> }
		}

		try
		{
			Save-TabContentCacheEntry -BuildContext $buildContext -AllTabIndexes $allTabIndexes -CacheOnly:$BackgroundBuild
		}
		catch
		{
			throw "Build-TabContent/AssignContent for tab '$PrimaryTab' failed: $($_.Exception.Message)"
		}

		if (-not $BackgroundBuild)
		{
			try
			{
				Update-MainContentPanelWidth -Panel $buildContext.MainPanel
			}
			catch
			{
				throw "Build-TabContent/UpdatePanelWidth for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}
			try
			{
				Restore-CurrentTabScrollOffset -TabKey $PrimaryTab
			}
			catch
			{
				throw "Build-TabContent/RestoreScrollOffset for tab '$PrimaryTab' failed: $($_.Exception.Message)"
			}

			# Schedule pre-builds for uncached tabs at idle priority so first-visit
			# switches are instant instead of waiting for on-demand construction.
			if (-not $SkipIdlePrebuild -and $PrimaryTabs -and $PrimaryTabs.Dispatcher)
			{
				$searchTag = $Script:SearchResultsTabTag
				foreach ($tabItem in $PrimaryTabs.Items)
				{
					if (-not ($tabItem -is [System.Windows.Controls.TabItem]) -or -not $tabItem.Tag) { continue }
					$tabTag = [string]$tabItem.Tag
					if ($tabTag -eq $PrimaryTab -or $tabTag -eq $searchTag) { continue }
					if ($Script:TabContentCache -and $Script:TabContentCache.ContainsKey($tabTag)) { continue }
					# Use a helper function (instead of .GetNewClosure()) to capture $tabTag
					# per-iteration while preserving the scope chain so that Build-TabContent
					# and its dependencies (New-TabContentBuildContext, etc.) remain resolvable.
					$preBuildAction = New-TabPreBuildAction -Tag $tabTag
					$null = $PrimaryTabs.Dispatcher.BeginInvoke(
						[System.Action]$preBuildAction,
						[System.Windows.Threading.DispatcherPriority]::ApplicationIdle
					)
				}
			}
		}
	}
	#endregion

	$Script:RunInProgress = $false

	# --- Observable State: reactive UI bindings ---
	$Script:GuiState = New-ObservableState -Dispatcher $Form.Dispatcher -InitialValues @{
		StatusText       = ''
		StatusForeground = (Get-GuiCurrentTheme).TextSecondary
		RunInProgress    = $false
		ProgressCompleted = 0
		ProgressTotal    = 0
		ProgressAction   = ''
		RiskFilter           = $Script:RiskFilter
		CategoryFilter       = $Script:CategoryFilter
		SelectedOnlyFilter   = $Script:SelectedOnlyFilter
		HighRiskOnlyFilter   = $Script:HighRiskOnlyFilter
		RestorableOnlyFilter = $Script:RestorableOnlyFilter
		GamingOnlyFilter     = $Script:GamingOnlyFilter
	}

	# Subscriber: StatusText -> $StatusText.Text
	& $Script:GuiState.Subscribe 'StatusText' {
		param ($newValue)
		if ($StatusText)
		{
			$StatusText.Text = [string]$newValue
			$StatusText.Visibility = if ([string]::IsNullOrWhiteSpace([string]$newValue)) { 'Collapsed' } else { 'Visible' }
		}
	}

	# Subscriber: StatusForeground -> $StatusText.Foreground (color string -> WPF brush)
	& $Script:GuiState.Subscribe 'StatusForeground' {
		param ($newValue)
		if ($StatusText -and $newValue -and $Script:SharedBrushConverter)
		{
			try { $StatusText.Foreground = $Script:SharedBrushConverter.ConvertFromString([string]$newValue) }
			catch { Write-GuiRuntimeWarning -Context 'GuiState/StatusForeground' -Message $_.Exception.Message }
		}
	}

	# Subscriber: RunInProgress -> sync to $Script: and context
	& $Script:GuiState.Subscribe 'RunInProgress' {
		param ($newValue)
		$Script:RunInProgress = [bool]$newValue
		if ($Script:Ctx) { $Script:Ctx.Run.InProgress = [bool]$newValue }
	}

	# Sync context - UI references
	$Script:Ctx.UI.MainForm = $Form
	$Script:Ctx.UI.StatusText = $StatusText
	$Script:Ctx.Run.InProgress = $false

		Register-GuiEventHandler -Source $Form -EventName 'Closing' -Handler ({
			param($windowSource, $e)
			if ($Script:SuppressRunClosePrompt) { return }
			if ($Script:AbortRequested -and (Get-RunAbortDisposition) -eq 'Return')
			{
				$e.Cancel = $true
				return
			}
			if (& $Script:TestGuiRunInProgressScript)
			{
				$e.Cancel = $true
			# Trigger the abort prompt if user attempts to close while running
			& $Script:PromptRunAbortFn
			return
		}

		# Show Save Session dialog while the main window is still alive to avoid
		# the long delay caused by WPF teardown / GC when spawning a new window
		# after ShowDialog() has returned.
		if (-not $Script:ForceCloseCompleted)
		{
			$saveChoice = GUICommon\Show-ThemedDialog `
				-Theme $Script:CurrentTheme `
				-ApplyButtonChrome ${function:Set-ButtonChrome} `
				-OwnerWindow $windowSource `
				-Title 'Save Session' `
				-Message 'Do you want to save your current selections for next launch?' `
				-Buttons @('Save', 'Discard') `
				-UseDarkMode ($Script:CurrentThemeName -eq 'Dark') `
				-AccentButton 'Save'
			if ($saveChoice -eq 'Save')
			{
				$null = Save-GuiSessionState
			}
		}
	}) | Out-Null

		Register-GuiEventHandler -Source $Form -EventName 'Closed' -Handler ({
			param($closedSender, $e)

			$dispatcher = if ($closedSender -and $closedSender.Dispatcher)
			{
				$closedSender.Dispatcher
			}
			elseif ($Script:MainForm -and $Script:MainForm.Dispatcher)
			{
				$Script:MainForm.Dispatcher
			}
			else
			{
				$null
			}

			if ($Script:GuiUnhandledExceptionHooked -and $Script:GuiUnhandledExceptionHandler -and $dispatcher)
			{
				try
				{
					$dispatcher.remove_UnhandledException($Script:GuiUnhandledExceptionHandler)
				}
				catch
				{
					$null = $_
				}
			}

			if ($Script:SearchRefreshTimer)
			{
				try { $Script:SearchRefreshTimer.Stop() } catch { $null = $_ }
				$Script:SearchRefreshTimer = $null
			}

			Clear-GuiWindowRuntimeState

			$Script:GuiUnhandledExceptionHooked = $false
			$Script:GuiUnhandledExceptionHandler = $null
			if ($Script:MainForm -eq $closedSender)
			{
				$Script:MainForm = $null
			}
		}) | Out-Null

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
		$tabIconName = Get-GuiPrimaryTabIconName -PrimaryTab $pKey
		$tabDisplayName = Get-LocalizedTabHeader -PrimaryTab $pKey
		if ($tabIconName)
		{
			$tabItem.Header = New-GuiLabeledIconContent -IconName $tabIconName -Text "$tabDisplayName ($tweakCount)" -IconSize 16 -Gap 6 -AllowTextOnlyFallback
		}
		else
		{
			$tabItem.Header = "$tabDisplayName ($tweakCount)"
		}
		$tabItem.Tag = $pKey
		$tabItem.Foreground = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TextPrimary -Context 'BuildPrimaryTabs/Foreground'
		$tabItem.Background = ConvertTo-GuiBrush -Color $Script:CurrentTheme.TabBg -Context 'BuildPrimaryTabs/Background'
		$tabItem.Padding = [System.Windows.Thickness]::new(16, 6, 16, 6)
		[void]($PrimaryTabs.Items.Add($tabItem))
		Add-PrimaryTabHoverEffects -Tab $tabItem
	}
	Update-PrimaryTabVisuals

	$Script:FilterUiUpdating = $true
	try
	{
		# Risk Filter - ONLY use SelectedIndex (integer)
		if ($CmbRiskFilter)
		{
			$CmbRiskFilter.Items.Clear()
			foreach ($riskOption in @('All', 'Low', 'Medium', 'High'))
			{
				[void]$CmbRiskFilter.Items.Add($riskOption)
			}

			$idx = 0
			if ($Script:RiskFilter)
			{
				$found = $CmbRiskFilter.Items.IndexOf($Script:RiskFilter)
				if ($found -ge 0) { $idx = $found }
			}
			try {
				$CmbRiskFilter.SelectedIndex = [int]$idx
			} catch {
				$CmbRiskFilter.SelectedIndex = 0
			}
		}

		# Category Filter (safe)
		if ($CmbCategoryFilter)
		{
			$idx = 0
			if ($Script:CategoryFilter)
			{
				$found = $CmbCategoryFilter.Items.IndexOf($Script:CategoryFilter)
				if ($found -ge 0) { $idx = $found }
			}
			try {
				$CmbCategoryFilter.SelectedIndex = [int]$idx
			} catch {
				$CmbCategoryFilter.SelectedIndex = 0
			}
		}

		# Checkboxes
		if ($ChkSafeMode)      { try { $ChkSafeMode.IsChecked      = [bool]$Script:SafeMode } catch { Write-GuiRuntimeWarning -Context 'FilterSync:SafeMode' -Message $_.Exception.Message } }
		if ($ChkGameMode)      { try { $ChkGameMode.IsChecked      = [bool]$Script:GameMode } catch { Write-GuiRuntimeWarning -Context 'FilterSync:GameMode' -Message $_.Exception.Message } }
		if ($ChkScan)          { try { $ChkScan.IsChecked          = [bool]$Script:ScanEnabled } catch { Write-GuiRuntimeWarning -Context 'FilterSync:ScanEnabled' -Message $_.Exception.Message } }

		# Language selector button + popup
		if ($BtnLanguage -and $LanguagePopup -and $LanguageListPanel)
		{
			# Build display-name-to-code mapping from available JSON files.
			$Script:LanguageMap = [ordered]@{}
			$locDir = $Script:GuiLocalizationDirectoryPath
			$langDisplayNames = @{
				'af' = 'Afrikaans'; 'ar' = 'Arabic'; 'bg' = 'Bulgarian'; 'bn' = 'Bengali'
				'cs' = 'Czech'; 'da' = 'Danish'; 'de' = 'Deutsch'; 'el' = 'Greek'
				'en' = 'English'; 'es' = 'Spanish'; 'et' = 'Estonian'; 'fa' = 'Persian'
				'fi' = 'Finnish'; 'fil' = 'Filipino'; 'fr' = 'French'; 'he' = 'Hebrew'
				'hi' = 'Hindi'; 'hr' = 'Croatian'; 'hu' = 'Hungarian'; 'id' = 'Indonesian'
				'it' = 'Italian'; 'ja' = 'Japanese'; 'ko' = 'Korean'; 'lt' = 'Lithuanian'
				'lv' = 'Latvian'; 'ms' = 'Malay'; 'nb' = 'Norwegian'; 'nl' = 'Dutch'
				'nl-BE' = 'Dutch (Belgium)'; 'pl' = 'Polish'; 'pt' = 'Portuguese'
				'pt-BR' = 'Portuguese (Brazil)'; 'ro' = 'Romanian'; 'ru' = 'Russian'
				'sk' = 'Slovak'; 'sl' = 'Slovenian'; 'sr' = 'Serbian'; 'sv' = 'Swedish'
				'sw' = 'Swahili'; 'th' = 'Thai'; 'tr' = 'Turkish'; 'uk' = 'Ukrainian'
				'ur' = 'Urdu'; 'vi' = 'Vietnamese'
				'zh-Hans' = 'Chinese (Simplified)'; 'zh-Hant' = 'Chinese (Traditional)'
			}

			$languageFiles = @()
			$languageEntries = New-Object System.Collections.ArrayList
			if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
			{
				$languageFiles = @(Get-ChildItem -LiteralPath $locDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
			}

			foreach ($jsonFile in $languageFiles)
			{
				$code = $jsonFile.BaseName
				$displayName = if ($langDisplayNames.ContainsKey($code)) { $langDisplayNames[$code] } else { $code }
				$Script:LanguageMap[$displayName] = $code
				[void]$languageEntries.Add([pscustomobject]@{
					Code = $code
					DisplayName = $displayName
					SearchIndex = ("{0} {1} {2}" -f $displayName, $code, ($code -replace '-', ' ')).ToLowerInvariant()
				})
			}

			$setLanguageSearchInputStyle = ${function:Set-LanguageSearchInputStyle}
			$setFilterControlStyleCapture = ${function:Set-FilterControlStyle}
			$renderLanguageList = {
				param ([string]$FilterText = '')

				$currentCode = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
				$normalizedFilter = if ([string]::IsNullOrWhiteSpace([string]$FilterText)) { '' } else { ([string]$FilterText).Trim().ToLowerInvariant() }
				$LanguageListPanel.Children.Clear()

				$matchingEntries = if ([string]::IsNullOrWhiteSpace($normalizedFilter))
				{
					@($languageEntries)
				}
				else
				{
					@($languageEntries | Where-Object { [string]$_.SearchIndex -like "*$normalizedFilter*" })
				}

				if ($matchingEntries.Count -eq 0)
				{
					$emptyState = [System.Windows.Controls.TextBlock]::new()
					$emptyState.Text = (Get-UxLocalizedString -Key 'GuiLanguageSearchNoResults' -Fallback 'No languages found.')
					$emptyState.TextWrapping = 'Wrap'
					$emptyState.Margin = [System.Windows.Thickness]::new(10, 8, 10, 6)
					$emptyState.FontSize = 11
					$emptyState.HorizontalAlignment = 'Left'
					[void]$LanguageListPanel.Children.Add($emptyState)
					if ($setFilterControlStyleCapture) { & $setFilterControlStyleCapture }
					return
				}

				foreach ($entry in $matchingEntries)
				{
					$langBtn = [System.Windows.Controls.Button]::new()
					$langBtn.Content = [string]$entry.DisplayName
					$langBtn.Tag = [string]$entry.Code
					$langBtn.Cursor = [System.Windows.Input.Cursors]::Hand
					$langBtn.HorizontalContentAlignment = 'Left'
					$langBtn.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
					$langBtn.Margin = [System.Windows.Thickness]::new(0, 1, 0, 1)
					$langBtn.FontSize = 12
					$langBtn.Width = 200
					$langBtn.BorderThickness = [System.Windows.Thickness]::new(0)
					$langBtn.Background = [System.Windows.Media.Brushes]::Transparent
					$langBtn.FontWeight = if ([string]$entry.Code -eq $currentCode) { [System.Windows.FontWeights]::Bold } else { [System.Windows.FontWeights]::Normal }

					$langBtn.Add_Click({
						param($sender, $e)
						$langCode = [string]$sender.Tag
						$Script:SelectedLanguage = $langCode

						# 1. Load new localization strings
						$locDir = $Script:GuiLocalizationDirectoryPath
						if (-not [string]::IsNullOrWhiteSpace([string]$locDir))
						{
							$Global:Localization = Import-BaselineLocalization -BaseDirectory $locDir -UICulture $langCode
						}

						# 2. Clear the inline language search and update indicator
						if ($TxtLanguageSearch) { $TxtLanguageSearch.Text = '' }
						if ($TxtLanguageState) { $TxtLanguageState.Text = $langCode.ToUpperInvariant() }
						if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
						$LanguagePopup.IsOpen = $false

						# 3. Refresh all header/toolbar localized strings
						Update-GuiLocalizationStrings

						# 4. Refresh tab headers with localized names
						Update-PrimaryTabHeaders

						# 5. Rebuild tab content (mirrors theme change pattern)
						$Script:FilterGeneration++
						Clear-TabContentCache
						if ($null -ne $Script:CurrentPrimaryTab)
						{
							Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab -SkipIdlePrebuild
						}

						# 6. Sync action buttons (respects execution-mode guard)
						Sync-UxActionButtonText

						# 7. Update run-path context label if available
						if (Get-Command -Name 'Update-RunPathContextLabel' -CommandType Function -ErrorAction SilentlyContinue)
						{
							Update-RunPathContextLabel
						}

						LogInfo "Language changed to: $($sender.Content) ($langCode)"
					}.GetNewClosure())

					[void]$LanguageListPanel.Children.Add($langBtn)
				}

				Set-FilterControlStyle
			}.GetNewClosure()

			if ($TxtLanguageSearch)
			{
				if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'GotKeyboardFocus' -Handler ({
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'LostKeyboardFocus' -Handler ({
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
				$null = Register-GuiEventHandler -Source $TxtLanguageSearch -EventName 'TextChanged' -Handler ({
					& $renderLanguageList -FilterText $TxtLanguageSearch.Text
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
				}.GetNewClosure())
			}

			& $renderLanguageList -FilterText $(if ($TxtLanguageSearch) { $TxtLanguageSearch.Text } else { '' })
			if ($TxtLanguageState)
			{
				$currentLanguageCode = if ($Script:SelectedLanguage) { [string]$Script:SelectedLanguage } else { 'en' }
				$TxtLanguageState.Text = $currentLanguageCode.ToUpperInvariant()
			}

			# Open popup when the language button is clicked.
			$null = Register-GuiEventHandler -Source $BtnLanguage -EventName 'Click' -Handler ({
				$LanguagePopup.IsOpen = -not $LanguagePopup.IsOpen
				if ($LanguagePopup.IsOpen -and $TxtLanguageSearch)
				{
					if (-not [string]::IsNullOrWhiteSpace([string]$TxtLanguageSearch.Text))
					{
						$TxtLanguageSearch.Text = ''
					}
					else
					{
						& $renderLanguageList -FilterText ''
					}
					if ($setLanguageSearchInputStyle) { & $setLanguageSearchInputStyle }
					$null = $TxtLanguageSearch.Focus()
				}
			}.GetNewClosure())
		}
	}
	finally
	{
		$Script:FilterUiUpdating = $false
	}
	Set-FilterControlStyle

	$Script:SuppressPrimaryTabSelectionChanged = $true
	$updateCurrentTabContentScript = ${function:Update-CurrentTabContent}
	$saveTabScrollOffsetScript = ${function:Save-CurrentTabScrollOffset}
		Register-GuiEventHandler -Source $PrimaryTabs -EventName 'SelectionChanged' -Handler ({
			param($tabEventSender, $e)
			if (-not $e) { return }
		if ($e.Source -ne $PrimaryTabs) { return }
		if ($Script:SuppressPrimaryTabSelectionChanged) { return }
		$skipIdlePrebuild = [bool]$Script:SkipIdlePrebuildOnNextPrimaryTabSelection
		$Script:SkipIdlePrebuildOnNextPrimaryTabSelection = $false
		& $saveTabScrollOffsetScript
		$selected = $PrimaryTabs.SelectedItem
		if ($selected -and $selected.Tag)
		{
			if ([string]$selected.Tag -ne $Script:SearchResultsTabTag)
			{
				$Script:LastStandardPrimaryTab = [string]$selected.Tag
				}
				# Defer content build so the tab header switches immediately
				$null = Invoke-GuiDispatcherAction -Dispatcher $PrimaryTabs.Dispatcher -PriorityUsage 'DeferredContentBuild' -Action {
						try { & $updateCurrentTabContentScript -SkipIdlePrebuild:$skipIdlePrebuild }
						catch {
							$showFn = $Script:ShowGuiRuntimeFailureScript
							if ($showFn) { $null = & $showFn -Context 'PrimaryTabs/SelectionChanged' -Exception $_.Exception -ShowDialog }
							else { Write-Warning ("GUI event failed [PrimaryTabs/SelectionChanged]: {0}" -f $_.Exception.Message) }
						}
				}
		}
	}) | Out-Null

	# Keep the desktop UI on a stable single-row tab strip so the primary
	# navigation does not reshuffle when Safe/Expert/Game Mode state changes.
	$Script:AdaptiveTabMode = 'tabs'
	$Script:SuppressDropdownSync = $false

	$adaptiveTabLayoutScript = {
		$availableTabWidth = if ($PrimaryTabHost -and $PrimaryTabHost.ActualWidth -gt 0)
		{
			[double]$PrimaryTabHost.ActualWidth
		}
		elseif ($Form.ActualWidth -gt 0)
		{
			[Math]::Max(0, [double]$Form.ActualWidth - 16)
		}
		else
		{
			0
		}
		if ($availableTabWidth -le 0) { return }

		$padding = if ($availableTabWidth -ge 1400)
		{
			[System.Windows.Thickness]::new(16, 6, 16, 6)
		}
		else
		{
			[System.Windows.Thickness]::new(8, 6, 8, 6)
		}

		foreach ($tabItem in $PrimaryTabs.Items)
		{
			if (-not ($tabItem -is [System.Windows.Controls.TabItem]))
			{
				continue
			}

			$tabItem.Padding = $padding
		}

		$Script:AdaptiveTabMode = 'tabs'
		if ($PrimaryTabDropdown)
		{
			$PrimaryTabDropdown.Visibility = [System.Windows.Visibility]::Collapsed
		}
		$PrimaryTabs.Visibility = [System.Windows.Visibility]::Visible

		# Keep the fixed one-row header strip visible and refresh the selected
		# tab's visual state after any width change.
		$selectedTab = $PrimaryTabs.SelectedItem
		if ($selectedTab -is [System.Windows.Controls.TabItem])
		{
			try { $selectedTab.BringIntoView() } catch { }
		}
	}
	$Script:AdaptiveTabLayoutScript = $adaptiveTabLayoutScript

	Register-GuiEventHandler -Source $Form -EventName 'SizeChanged' -Handler ({
		& $Script:AdaptiveTabLayoutScript
	}) | Out-Null

	# Build the initial tab while the startup splash is still visible so the main
	# window only appears once real content is ready.
	if (-not ($PrimaryTabs -is [System.Windows.Controls.TabControl]))
	{
		throw "PrimaryTabs is not a TabControl. Actual type: $($PrimaryTabs.GetType().FullName)"
	}

	if ($PrimaryTabs.Items.Count -gt 0)
	{
		$showGuiRuntimeFailureCapture = $Script:ShowGuiRuntimeFailureScript
		try
		{
			$null = Invoke-GuiDispatcherAction -Dispatcher $PrimaryTabs.Dispatcher -PriorityUsage 'IdleFinalize' -Action {
					try
					{
						$firstTab = if ($PrimaryTabs.Items.Count -gt 0) { $PrimaryTabs.Items[0] } else { $null }
						$selectedTab = if ($PrimaryTabs.SelectedItem) { $PrimaryTabs.SelectedItem } else { $null }
						$targetTab = if ($selectedTab) { $selectedTab } else { $firstTab }
						if ($null -eq $targetTab)
						{
							return
						}

						if ($null -eq $selectedTab -and $PrimaryTabs.SelectedItem -ne $targetTab)
						{
							$PrimaryTabs.SelectedItem = $targetTab
						}

						if ($targetTab.Tag -and [string]$targetTab.Tag -ne $Script:SearchResultsTabTag)
						{
							$Script:LastStandardPrimaryTab = [string]$targetTab.Tag
						}

						Update-CurrentTabContent
					}
					catch
					{
						if ($showGuiRuntimeFailureCapture) { $null = & $showGuiRuntimeFailureCapture -Context 'InitialTabBuild' -Exception $_.Exception -ShowDialog }
						else { Write-Warning ("GUI event failed [InitialTabBuild]: {0}" -f $_.Exception.Message) }
					}
					finally
					{
						$Script:SuppressPrimaryTabSelectionChanged = $false
					}
				}
		}
		catch
		{
			$Script:SuppressPrimaryTabSelectionChanged = $false
			throw
		}
	}
	else
	{
		$Script:SuppressPrimaryTabSelectionChanged = $false
	}
	#endregion

	# Linked-toggle wiring is handled inline in Build-TweakRow (supports lazy tab building).

	$Script:ClearTabContentCacheScript = ${function:Clear-TabContentCache}
	$Script:UpdateCategoryFilterListScript = ${function:Update-CategoryFilterList}
	$Script:UpdateSearchResultsTabStateScript = ${function:Update-SearchResultsTabState}

	$refreshVisibleContent = {
		if ((& $Script:TestGuiRunInProgressScript) -or $Script:FilterUiUpdating) { return }
		# Bump the filter generation so stale tab caches are evicted on next visit
		# without the cost of clearing and rebuilding all tabs up front.
		$Script:FilterGeneration++
		# When search text is active, use the search sentinel tag so category
		# filters reflect cross-tab results.  Fall back to the selected real tab.
		$hasSearchText = -not [string]::IsNullOrWhiteSpace([string]$Script:SearchText)
		$targetTab = if ($hasSearchText) {
			$Script:SearchResultsTabTag
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
		# Only invalidate the current tab and search results for immediate rebuild.
		# Other tabs carry a stale FilterGeneration and will be evicted lazily.
		if ($targetTab) { & $Script:ClearTabContentCacheScript $targetTab }
		if ($Script:SearchResultsTabTag -and $targetTab -ne $Script:SearchResultsTabTag)
		{
			& $Script:ClearTabContentCacheScript $Script:SearchResultsTabTag
		}
		& $Script:UpdateCategoryFilterListScript -PrimaryTab $targetTab
		& $Script:UpdateSearchResultsTabStateScript
	}

	# Search-only refresh: keeps regular tab caches so returning from search is instant.
	# Only the search-results tab entry is cleared; regular tabs were built without a
	# search filter and remain correct once search is cleared.
	$refreshSearchContent = {
		if ((& $Script:TestGuiRunInProgressScript) -or $Script:FilterUiUpdating) { return }
		# Only evict search-related category filter cache entries; regular tab
		# entries remain valid since the search query doesn't affect their content.
		if ($Script:CategoryFilterListCache -and $Script:SearchResultsTabTag)
		{
			$staleKeys = @($Script:CategoryFilterListCache.Keys | Where-Object { [string]$_ -and ([string]$_).StartsWith("$($Script:SearchResultsTabTag)|") })
			foreach ($sk in $staleKeys) { [void]$Script:CategoryFilterListCache.Remove($sk) }
		}
		if ($Script:LastCategoryFilterPopulateKey -and $Script:SearchResultsTabTag -and $Script:LastCategoryFilterPopulateKey.StartsWith("$($Script:SearchResultsTabTag)|"))
		{
			$Script:LastCategoryFilterPopulateKey = $null
		}
		if ($Script:TabContentCache -and $Script:SearchResultsTabTag -and $Script:TabContentCache.ContainsKey($Script:SearchResultsTabTag))
		{
			[void]$Script:TabContentCache.Remove($Script:SearchResultsTabTag)
		}
		# When search text is active, use the search sentinel tag so category
		# filters reflect cross-tab results (inline banner replaces the old
		# Search Results tab).  Fall back to the selected real tab otherwise.
		$hasSearchText = -not [string]::IsNullOrWhiteSpace([string]$Script:SearchText)
		$targetTab = if ($hasSearchText) {
			$Script:SearchResultsTabTag
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
		& $Script:UpdateCategoryFilterListScript -PrimaryTab $targetTab
		& $Script:UpdateSearchResultsTabStateScript
	}

	# Subscribers: filter state -> sync $Script: variables and refresh UI
	$refreshVisibleContentCapture = $refreshVisibleContent
	foreach ($filterProp in @('RiskFilter', 'CategoryFilter', 'SelectedOnlyFilter', 'HighRiskOnlyFilter', 'RestorableOnlyFilter', 'GamingOnlyFilter'))
	{
		$propCapture = $filterProp
		& $Script:GuiState.Subscribe $filterProp {
			param ($newValue)
			Set-Variable -Name $propCapture -Value $newValue -Scope Script
			& $refreshVisibleContentCapture
		}.GetNewClosure()
	}

	. (Join-Path $Script:GuiExtractedRoot 'SearchFilterHandlers.ps1')

	. (Join-Path $Script:GuiExtractedRoot 'ActionHandlers.ps1')


	# Late-bind function captures for handlers that run from WPF event contexts
	# where Show-TweakGUI's local scope isn't on the call chain.
	$Script:ClearTabContentCacheScript = ${function:Clear-TabContentCache}
	$Script:BuildTabContentScript = ${function:Build-TabContent}
	$Script:UpdateCurrentTabContentScript = ${function:Update-CurrentTabContent}
	$Script:UpdatePrimaryTabVisualsScript = ${function:Update-PrimaryTabVisuals}
	$Script:SaveGuiUndoSnapshotScript = ${function:Save-GuiUndoSnapshot}
	$Script:GetPrimaryTabItemScript = ${function:Get-PrimaryTabItem}
	$Script:ClearGameModePlanScript = ${function:Clear-GameModePlan}
	$Script:SetGameModeProfileScript = ${function:Set-GameModeProfile}
	$Script:ResetGameModeStateScript = ${function:Reset-GameModeState}
	$Script:BuildGameModePlanScript = ${function:Build-GameModePlan}
	$Script:BuildGameModeAdvancedPlanEntriesScript = ${function:Build-GameModeAdvancedPlanEntries}
	$Script:GetGameModeProfileDefaultSelectionScript = (Get-Item function:Get-GameModeProfileDefaultSelection -ErrorAction Stop).ScriptBlock
	$Script:GetGamingPreviewGroupSortOrderScript = (Get-Item function:Get-GamingPreviewGroupSortOrder -ErrorAction Stop).ScriptBlock
	$Script:NewGameModeComparisonPanelScript = ${function:New-GameModeComparisonPanel}
	$Script:SyncGameModeContextStateScript = ${function:Sync-GameModeContextState}
	$Script:SyncGameModePlanToGamingControlsScript = ${function:Sync-GameModePlanToGamingControls}
	$Script:UpdateGameModeStatusTextScript = ${function:Update-GameModeStatusText}
	$Script:ShowThemedDialogScript = ${function:Show-ThemedDialog}
	$Script:ShowSelectedTweakPreviewScript = ${function:Show-SelectedTweakPreview}
	$Script:GetUxRunActionLabelScript = ${function:Get-UxRunActionLabel}
	$Script:UpdateRunPathContextLabelScript = ${function:Update-RunPathContextLabel}
	$Script:InvokeGuiStateTransitionScript = ${function:Invoke-GuiStateTransition}
	$Script:SyncUxActionButtonTextScript = ${function:Sync-UxActionButtonText}
	$Script:ClearInvisibleSelectionStateScript = ${function:Clear-InvisibleSelectionState}
	$Script:UpdateHeaderModeStateTextScript = ${function:Update-HeaderModeStateText}

	# Apply initial theme
	Set-GUITheme -Theme $Script:DarkTheme
	Set-StaticButtonStyle

	# Wire icon content for primary action buttons
	if ($BtnPreviewRun) { Set-GuiButtonIconContent -Button $BtnPreviewRun -IconName 'PreviewRun'      -Text 'Preview Run'                 -ToolTip 'Review what will change before applying tweaks.' }
	if ($BtnRun)        { Set-GuiButtonIconContent -Button $BtnRun        -IconName 'RunTweaks'       -Text 'Run Tweaks'                  -ToolTip 'Apply the current selections.' }
	if ($BtnDefaults)   { Set-GuiButtonIconContent -Button $BtnDefaults   -IconName 'RestoreDefaults' -Text 'Restore to Windows Defaults' -ToolTip 'Restore supported settings to Windows defaults.' }
	if ($BtnLog)        { Set-GuiButtonIconContent -Button $BtnLog        -IconName 'OpenLog'         -Text 'Open Log'                    -ToolTip 'Open the detailed execution log.' }
	if ($BtnStartHere)  { Set-GuiButtonIconContent -Button $BtnStartHere  -IconName 'QuickStart'     -Text 'Start Guide'                 -ToolTip 'Open the getting started guide.' }
	if ($BtnHelp)       { Set-GuiButtonIconContent -Button $BtnHelp       -IconName 'Help'           -Text 'Help'                        -ToolTip 'Open help and usage guidance.' }
	if ($BtnLanguage)   { Set-GuiButtonIconContent -Button $BtnLanguage   -IconName 'Language'       -Text 'Language'                    -ToolTip 'Change language' -IconSize 14 -Gap 6 -TextFontSize 11 }
	if ($BtnClearSearch) { Set-GuiButtonIconContent -Button $BtnClearSearch -IconName 'Clear'         -Text 'Clear'                       -ToolTip 'Clear search text and active filters.' -IconSize 14 -Gap 6 -TextFontSize 11 }

	Set-StaticControlTabOrder
	Set-GuiActionButtonsEnabled -Enabled $true

	$restoredGuiSession = Restore-GuiSessionState
	Update-GuiLocalizationStrings
	Update-PrimaryTabHeaders
	if ($TxtLanguageState -and -not [string]::IsNullOrWhiteSpace([string]$Script:SelectedLanguage))
	{
		$TxtLanguageState.Text = ([string]$Script:SelectedLanguage).ToUpperInvariant()
	}
	Sync-UxActionButtonText
	if ($restoredGuiSession)
	{
		Set-GuiStatusText -Text 'Previous session restored.' -Tone 'accent'
	}

	# Resolve all first-run dependencies ONCE, here, while module scope is valid.
	$firstRunDialogDispatcher = if ($Form -and $Form.Dispatcher) { $Form.Dispatcher } else { $null }
	$closeLoadingSplashBlock = (Get-Item function:Close-LoadingSplashWindow -ErrorAction Stop).ScriptBlock
	$hideConsoleWindowBlock  = (Get-Item function:Hide-ConsoleWindow -ErrorAction Stop).ScriptBlock
	$showThemedDialogBlock   = (Get-Item function:Show-ThemedDialog -ErrorAction Stop).ScriptBlock
	$showWelcomeDialogBlock  = (Get-Item function:Show-FirstRunWelcomeDialog -ErrorAction Stop).ScriptBlock
	$completeWelcomeBlock    = (Get-Item function:Complete-GuiFirstRunWelcome -ErrorAction Stop).ScriptBlock
	$firstRunTheme           = $Script:CurrentTheme
	$firstRunApplyButtonChrome = ${function:Set-ButtonChrome}
	$firstRunOwnerWindow     = $Form
	$firstRunUseDarkMode     = ($Script:CurrentThemeName -eq 'Dark')

	if ($closeLoadingSplashBlock -isnot [scriptblock]) { throw "Close-LoadingSplashWindow did not resolve to a scriptblock." }
	if ($hideConsoleWindowBlock  -isnot [scriptblock]) { throw "Hide-ConsoleWindow did not resolve to a scriptblock." }
	if ($showThemedDialogBlock   -isnot [scriptblock]) { throw "Show-ThemedDialog did not resolve to a scriptblock." }
	if ($showWelcomeDialogBlock  -isnot [scriptblock]) { throw "Show-FirstRunWelcomeDialog did not resolve to a scriptblock." }
	if ($completeWelcomeBlock    -isnot [scriptblock]) { throw "Complete-GuiFirstRunWelcome did not resolve to a scriptblock." }

	$firstRunShowHelpDialogCommand = Get-Command 'Show-HelpDialog' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$firstRunSetGuiPresetSelectionCommand = Get-Command 'Set-GuiPresetSelection' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$firstRunSetGuiStatusTextCommand = Get-Command 'Set-GuiStatusText' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$getRecommendedPresetNameCommand = Get-Command 'Get-UxRecommendedPresetName' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$getFirstRunMarkerPathCommand = Get-Command 'Get-GuiFirstRunWelcomeMarkerPath' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1

	if (-not $firstRunSetGuiPresetSelectionCommand)   { throw "Set-GuiPresetSelection not found." }
	if (-not $firstRunSetGuiStatusTextCommand)        { throw "Set-GuiStatusText not found." }
	if (-not $getRecommendedPresetNameCommand){ throw "Get-UxRecommendedPresetName not found." }
	if (-not $getFirstRunMarkerPathCommand)   { throw "Get-GuiFirstRunWelcomeMarkerPath not found." }

	$firstRunMarkerPath = & $getFirstRunMarkerPathCommand
	if ([string]::IsNullOrWhiteSpace($firstRunMarkerPath))
	{
		throw "Get-GuiFirstRunWelcomeMarkerPath returned an empty path."
	}

	$firstRunMarkerDirectory = Split-Path -Path $firstRunMarkerPath -Parent
	if ([string]::IsNullOrWhiteSpace($firstRunMarkerDirectory))
	{
		throw "First-run marker directory could not be derived from path: $firstRunMarkerPath"
	}

	if (-not (Test-Path -LiteralPath $firstRunMarkerDirectory))
	{
		$null = New-Item -ItemType Directory -Path $firstRunMarkerDirectory -Force -ErrorAction Stop
	}

	$shouldShowFirstRunWelcome = -not (Test-Path -LiteralPath $firstRunMarkerPath)
	$firstRunRecommendedPreset = & $getRecommendedPresetNameCommand
	$firstRunPrimaryActionLabel = Get-UxFirstRunPrimaryActionLabel
	$firstRunWelcomeMessage = Get-UxFirstRunWelcomeMessage
	$firstRunDialogTitle = Get-UxFirstRunDialogTitle
	$firstRunPresetLoadedStatusText = Get-UxPresetLoadedStatusText -PresetName $firstRunRecommendedPreset

	$startupPresentationCompleted = $false
	Register-GuiEventHandler -Source $Form -EventName 'ContentRendered' -Handler ({
		if ($startupPresentationCompleted) { return }
		$startupPresentationCompleted = $true

		# Run initial adaptive tab layout check now that the window has its actual size
		if ($Script:AdaptiveTabLayoutScript) { & $Script:AdaptiveTabLayoutScript }

		try
		{
			$loadingSplash = Get-Variable -Name 'LoadingSplash' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
			if ($loadingSplash)
			{
				$null = & $closeLoadingSplashBlock -Splash $loadingSplash -DisposeResources
				$Global:LoadingSplash = $null
			}
		}
		catch
		{
			$null = $_
		}

		try
		{
			& $hideConsoleWindowBlock
		}
		catch
		{
			$null = $_
		}

		# Adjust MinWidth based on the header's actual measured width so the
		# Light Mode toggle is never clipped regardless of DPI or resolution.
		try
		{
			if ($HeaderBorder -and $HeaderBorder.ActualWidth -gt 0 -and $HeaderBorder.Child -is [System.Windows.Controls.Grid])
			{
				$topRow = $HeaderBorder.Child.Children[0]
				if ($topRow -is [System.Windows.Controls.Grid])
				{
					$topRow.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
					$neededWidth = $topRow.DesiredSize.Width + 56
					if ($neededWidth -gt $Form.MinWidth) { $Form.MinWidth = [Math]::Ceiling($neededWidth) }
				}
			}
		}
		catch { <# non-fatal #> }

		if (-not $shouldShowFirstRunWelcome)
		{
			return
		}

		# Recheck concrete marker path in case another path created it during startup.
		if (Test-Path -LiteralPath $firstRunMarkerPath)
		{
			return
		}

		try
		{
			$openHelpAction = {
				if ($firstRunShowHelpDialogCommand)
				{
					if ($firstRunDialogDispatcher -and $firstRunDialogDispatcher.PSObject.Methods['BeginInvoke'])
					{
						$showHelpDialogAction = {
							& $firstRunShowHelpDialogCommand
						}.GetNewClosure()
						$null = $firstRunDialogDispatcher.BeginInvoke(
							[System.Action]$showHelpDialogAction,
							[System.Windows.Threading.DispatcherPriority]::ApplicationIdle
						)
					}
					else
					{
						& $firstRunShowHelpDialogCommand
					}
				}
			}.GetNewClosure()

			$chooseRecommendedPresetAction = {
				$presetToApply = $firstRunRecommendedPreset
				& $firstRunSetGuiPresetSelectionCommand -PresetName $presetToApply
				& $firstRunSetGuiStatusTextCommand -Text $firstRunPresetLoadedStatusText -Tone 'accent'
			}.GetNewClosure()

			$dialogResult = & $showWelcomeDialogBlock `
				-RecommendedPreset $firstRunRecommendedPreset `
				-PrimaryActionLabel $firstRunPrimaryActionLabel `
				-WelcomeMessage $firstRunWelcomeMessage `
				-DialogTitle $firstRunDialogTitle `
				-ShowThemedDialogCapture $showThemedDialogBlock `
				-OpenHelpAction $openHelpAction `
				-ChooseRecommendedPresetAction $chooseRecommendedPresetAction `
				-Theme $firstRunTheme `
				-ApplyButtonChrome $firstRunApplyButtonChrome `
				-OwnerWindow $firstRunOwnerWindow `
				-UseDarkMode $firstRunUseDarkMode

			if ($dialogResult)
			{
				# Do NOT call Complete-GuiFirstRunWelcome here.
				# Write the marker directly using the already-validated concrete path.
				if (-not (Test-Path -LiteralPath $firstRunMarkerDirectory))
				{
					$null = New-Item -ItemType Directory -Path $firstRunMarkerDirectory -Force -ErrorAction Stop
				}

				Set-Content -LiteralPath $firstRunMarkerPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8 -Force
			}
		}
		catch
		{
			throw "First-run welcome failed: $($_.Exception.Message)"
		}
	}.GetNewClosure()) | Out-Null

	# Activate the main window only when it is about to be shown.
	$Form.ShowActivated = $true
	Initialize-WpfWindowForeground -Window $Form

	# Set Preview Run as the default-focused action so it feels like the natural next step.
	if ($BtnPreviewRun) { $BtnPreviewRun.Focusable = $true }

	# Show the GUI
	try
	{
		[void]([System.Windows.Window]$Form).ShowDialog()
	}
	catch
	{
		$errorLines = New-Object System.Collections.Generic.List[string]
		[void]$errorLines.Add("Failed to open WPF window. Form type: $($Form.GetType().FullName)")
		[void]$errorLines.Add("Apartment state: $([System.Threading.Thread]::CurrentThread.GetApartmentState())")
		[void]$errorLines.Add("Error: $($_.Exception.GetType().FullName): $($_.Exception.Message)")

		$innerException = $_.Exception.InnerException
		if ($innerException)
		{
			[void]$errorLines.Add("Inner exception: $($innerException.GetType().FullName): $($innerException.Message)")
			if (-not [string]::IsNullOrWhiteSpace([string]$innerException.StackTrace))
			{
				[void]$errorLines.Add("Inner stack trace:`n$($innerException.StackTrace.Trim())")
			}
		}

		throw ($errorLines -join [Environment]::NewLine)
	}

	LogInfo "GUI closed"

	# Write local-only session summary to the log file at end of GUI session
	Write-SessionSummaryToLog
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
	$queue = Get-Variable -Name 'GUIRunState' -ValueOnly -ErrorAction Ignore
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
