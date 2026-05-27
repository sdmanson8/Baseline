# DeploymentMediaBuilder.Unattend.ps1
# Offline autounattend generator helpers.

function Get-GuiDeploymentMediaUnattendOptionGroups
{
	[CmdletBinding()]
	param ()

	$bloatwareOptions = @()
	foreach ($entry in @(
		'Remove3DViewer|3D Viewer',
		'RemoveBingSearch|Bing Search',
		'RemoveCamera|Camera',
		'RemoveClipchamp|Clipchamp',
		'RemoveClock|Clock',
		'RemoveCopilot|Copilot',
		'RemoveCortana|Cortana',
		'RemoveDevHome|Dev Home',
		'RemoveFamily|Family',
		'RemoveFeedbackHub|Feedback Hub',
		'RemoveGetHelp|Get Help',
		'RemoveGetStarted|Get Started',
		'RemoveHandwriting|Handwriting',
		'RemoveInternetExplorer|Internet Explorer',
		'RemoveMailCalendar|Mail and Calendar',
		'RemoveMaps|Maps',
		'RemoveMathInputPanel|Math Input Panel',
		'RemoveMediaFeatures|Media Features',
		'RemoveMixedReality|Mixed Reality',
		'RemoveZuneVideo|Movies and TV',
		'RemoveNews|News',
		'RemoveOffice365|Microsoft 365',
		'RemoveOneDrive|OneDrive',
		'RemoveOneNote|OneNote',
		'RemoveOneSync|OneSync',
		'RemoveOutlook|Outlook for Windows',
		'RemovePaint|Paint',
		'RemovePaint3D|Paint 3D',
		'RemovePeople|People',
		'RemovePhotos|Photos',
		'RemovePowerAutomate|Power Automate',
		'RemovePowerShellISE|PowerShell ISE',
		'RemoveQuickAssist|Quick Assist',
		'RemoveRecall|Recall',
		'RemoveRdpClient|Remote Desktop client',
		'RemoveSkype|Skype',
		'RemoveSolitaire|Solitaire',
		'RemoveSpeech|Speech',
		'RemoveStickyNotes|Sticky Notes',
		'RemoveTeams|Teams',
		'RemoveToDo|Microsoft To Do',
		'RemoveVoiceRecorder|Voice Recorder',
		'RemoveWallet|Wallet',
		'RemoveWeather|Weather',
		'RemoveWindowsMediaPlayer|Windows Media Player',
		'RemoveWordPad|WordPad',
		'RemoveXboxApps|Xbox apps',
		'RemoveYourPhone|Phone Link'
	))
	{
		$parts = $entry -split '\|', 2
		$bloatwareOptions += @{ Key = $parts[0]; Label = $parts[1]; Kind = 'Bool'; Default = $false }
	}

	$groups = @(
		@{
			Name = 'Language and region'
			Options = @(
				@{ Key = 'LanguageSettings'; Label = 'Language settings'; Kind = 'Choice'; Default = 'Unattended'; Choices = @('Interactive', 'Unattended') },
				@{ Key = 'UILanguage'; Label = 'Image and UI language'; Kind = 'Text'; Default = 'en-US' },
				@{ Key = 'UserLocale'; Label = 'User locale'; Kind = 'Text'; Default = 'en-US' },
				@{ Key = 'KeyboardIdentifier'; Label = 'Keyboard identifier'; Kind = 'Text'; Default = '00000409' },
				@{ Key = 'GeoLocation'; Label = 'Geo location ID'; Kind = 'Text'; Default = '244' },
				@{ Key = 'TimeZoneSettings'; Label = 'Time zone'; Kind = 'Choice'; Default = 'Implicit'; Choices = @('Implicit', 'Explicit') },
				@{ Key = 'TimeZone'; Label = 'Explicit time zone ID'; Kind = 'Text'; Default = 'UTC' },
				@{ Key = 'ProcessorArchitectures'; Label = 'Processor architecture'; Kind = 'Choice'; Default = 'amd64'; Choices = @('amd64', 'x86', 'arm64') }
			)
		}
		@{
			Name = 'Windows setup'
			Options = @(
				@{ Key = 'EditionSettings'; Label = 'Windows edition'; Kind = 'Choice'; Default = 'Interactive'; Choices = @('Interactive', 'Firmware', 'Generic') },
				@{ Key = 'WindowsEdition'; Label = 'Generic edition key'; Kind = 'Choice'; Default = 'pro'; Choices = @('home', 'home_n', 'home_single', 'education', 'education_n', 'pro', 'pro_n', 'pro_education', 'pro_education_n', 'pro_workstations', 'pro_workstations_n', 'enterprise', 'enterprise_n') },
				@{ Key = 'ProductKey'; Label = 'Custom product key'; Kind = 'Text'; Default = '' },
				@{ Key = 'UseConfigurationSet'; Label = 'Use configuration set'; Kind = 'Bool'; Default = $false },
				@{ Key = 'PESettings'; Label = 'Windows PE settings'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Generate') },
				@{ Key = 'BypassRequirementsCheck'; Label = 'Bypass Windows 11 hardware checks'; Kind = 'Bool'; Default = $true },
				@{ Key = 'CompactOs'; Label = 'Compact OS'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Always', 'Never') },
				@{ Key = 'PartitionSettings'; Label = 'Disk partitioning'; Kind = 'Choice'; Default = 'Interactive'; Choices = @('Interactive', 'Unattended') },
				@{ Key = 'PartitionLayout'; Label = 'Partition layout'; Kind = 'Choice'; Default = 'Automatic'; Choices = @('Automatic', 'GPT', 'MBR') },
				@{ Key = 'RecoveryMode'; Label = 'Recovery partition'; Kind = 'Choice'; Default = 'Partition'; Choices = @('Partition', 'None') },
				@{ Key = 'InstallFromSettings'; Label = 'Install image selection'; Kind = 'Choice'; Default = 'Automatic'; Choices = @('Automatic', 'ImageIndex', 'ImageName') },
				@{ Key = 'InstallImageIndex'; Label = 'Install image index'; Kind = 'Text'; Default = '' },
				@{ Key = 'InstallImageName'; Label = 'Install image name'; Kind = 'Text'; Default = '' },
				@{ Key = 'Components'; Label = 'Additional unattend components'; Kind = 'Multiline'; Default = '' }
			)
		}
		@{
			Name = 'Accounts and OOBE'
			Options = @(
				@{ Key = 'ComputerNameSettings'; Label = 'Computer name'; Kind = 'Choice'; Default = 'Random'; Choices = @('Random', 'Custom') },
				@{ Key = 'ComputerName'; Label = 'Custom computer name'; Kind = 'Text'; Default = '' },
				@{ Key = 'AccountSettings'; Label = 'Account setup'; Kind = 'Choice'; Default = 'InteractiveMicrosoftAccount'; Choices = @('InteractiveMicrosoftAccount', 'InteractiveLocalAccount', 'UnattendedLocalAccount') },
				@{ Key = 'AccountName0'; Label = 'Local account name'; Kind = 'Text'; Default = '' },
				@{ Key = 'AccountDisplayName0'; Label = 'Display name'; Kind = 'Text'; Default = '' },
				@{ Key = 'AccountPassword0'; Label = 'Password'; Kind = 'Password'; Default = '' },
				@{ Key = 'AccountGroup0'; Label = 'Account group'; Kind = 'Choice'; Default = 'Administrators'; Choices = @('Administrators', 'Users') },
				@{ Key = 'AutoLogon'; Label = 'Auto logon'; Kind = 'Choice'; Default = 'None'; Choices = @('None', 'OwnAccount') },
				@{ Key = 'LockoutSettings'; Label = 'Account lockout'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'PasswordExpirationSettings'; Label = 'Password expiration'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Unlimited') },
				@{ Key = 'ProcessAuditSettings'; Label = 'Process creation audit'; Kind = 'Choice'; Default = 'Disabled'; Choices = @('Disabled', 'Enabled') },
				@{ Key = 'WifiSettings'; Label = 'Wi-Fi setup'; Kind = 'Choice'; Default = 'Interactive'; Choices = @('Interactive', 'Skip', 'Unattended') },
				@{ Key = 'WifiSsid'; Label = 'Wi-Fi SSID'; Kind = 'Text'; Default = '' },
				@{ Key = 'WifiKey'; Label = 'Wi-Fi key'; Kind = 'Password'; Default = '' },
				@{ Key = 'ExpressSettings'; Label = 'Express settings'; Kind = 'Choice'; Default = 'DisableAll'; Choices = @('Interactive', 'EnableAll', 'DisableAll') },
				@{ Key = 'BypassNetworkCheck'; Label = 'Bypass network requirement'; Kind = 'Bool'; Default = $false },
				@{ Key = 'KeepSensitiveFiles'; Label = 'Keep generated sensitive setup files'; Kind = 'Bool'; Default = $false },
				@{ Key = 'UseNarrator'; Label = 'Use Narrator during setup'; Kind = 'Bool'; Default = $false }
			)
		}
		@{
			Name = 'System policies'
			Options = @(
				@{ Key = 'EnableLongPaths'; Label = 'Enable long paths'; Kind = 'Bool'; Default = $false },
				@{ Key = 'EnableRemoteDesktop'; Label = 'Enable Remote Desktop'; Kind = 'Bool'; Default = $false },
				@{ Key = 'HardenSystemDriveAcl'; Label = 'Harden system drive ACL'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DeleteJunctions'; Label = 'Delete compatibility junctions'; Kind = 'Bool'; Default = $false },
				@{ Key = 'AllowPowerShellScripts'; Label = 'Allow PowerShell scripts'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableLastAccess'; Label = 'Disable last access timestamps'; Kind = 'Bool'; Default = $false },
				@{ Key = 'PreventAutomaticReboot'; Label = 'Prevent automatic reboot'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableSac'; Label = 'Disable Smart App Control'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableUac'; Label = 'Disable User Account Control'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableSmartScreen'; Label = 'Disable SmartScreen'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableSystemRestore'; Label = 'Disable System Restore'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableFastStartup'; Label = 'Disable Fast Startup'; Kind = 'Bool'; Default = $false },
				@{ Key = 'PreventDeviceEncryption'; Label = 'Prevent device encryption'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableCoreIsolation'; Label = 'Disable Core Isolation'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableAutomaticRestartSignOn'; Label = 'Disable automatic restart sign-on'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableWpbt'; Label = 'Disable WPBT execution'; Kind = 'Bool'; Default = $false }
			)
		}
		@{
			Name = 'Desktop and Explorer'
			Options = @(
				@{ Key = 'ClassicContextMenu'; Label = 'Classic context menu'; Kind = 'Bool'; Default = $false },
				@{ Key = 'LeftTaskbar'; Label = 'Left taskbar alignment'; Kind = 'Bool'; Default = $false },
				@{ Key = 'HideTaskViewButton'; Label = 'Hide Task View button'; Kind = 'Bool'; Default = $false },
				@{ Key = 'ShowFileExtensions'; Label = 'Show file extensions'; Kind = 'Bool'; Default = $false },
				@{ Key = 'ShowAllTrayIcons'; Label = 'Show all tray icons'; Kind = 'Bool'; Default = $false },
				@{ Key = 'HideFiles'; Label = 'Hidden files'; Kind = 'Choice'; Default = 'Hidden'; Choices = @('Hidden', 'ShowHidden', 'ShowHiddenAndSystem') },
				@{ Key = 'LaunchToThisPC'; Label = 'Open File Explorer to This PC'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableBingResults'; Label = 'Disable Bing results in search'; Kind = 'Bool'; Default = $false },
				@{ Key = 'TaskbarSearch'; Label = 'Taskbar search'; Kind = 'Choice'; Default = 'Box'; Choices = @('Hide', 'Icon', 'Box', 'Label') },
				@{ Key = 'StartPinsSettings'; Label = 'Start pins'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Empty') },
				@{ Key = 'StartTilesSettings'; Label = 'Start tiles'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Empty') },
				@{ Key = 'TaskbarIcons'; Label = 'Taskbar icons'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Empty') },
				@{ Key = 'DesktopIcons'; Label = 'Desktop icons'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Custom') },
				@{ Key = 'DesktopIconThisPC'; Label = 'Desktop icon: This PC'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DesktopIconUserFiles'; Label = 'Desktop icon: User files'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DesktopIconControlPanel'; Label = 'Desktop icon: Control Panel'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DesktopIconRecycleBin'; Label = 'Desktop icon: Recycle Bin'; Kind = 'Bool'; Default = $false },
				@{ Key = 'StartFolderSettings'; Label = 'Start folders'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Custom') },
				@{ Key = 'StartFolderDownloads'; Label = 'Start folder: Downloads'; Kind = 'Bool'; Default = $false },
				@{ Key = 'StartFolderDocuments'; Label = 'Start folder: Documents'; Kind = 'Bool'; Default = $false },
				@{ Key = 'StartFolderSettingsShortcut'; Label = 'Start folder: Settings'; Kind = 'Bool'; Default = $false },
				@{ Key = 'HideInfoTip'; Label = 'Hide Explorer info tips'; Kind = 'Bool'; Default = $false }
			)
		}
		@{
			Name = 'Edge and apps'
			Options = @(
				@{ Key = 'DisableAppSuggestions'; Label = 'Disable app suggestions'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableWidgets'; Label = 'Disable widgets'; Kind = 'Bool'; Default = $false },
				@{ Key = 'HideEdgeFre'; Label = 'Hide Edge first-run experience'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableEdgeStartupBoost'; Label = 'Disable Edge Startup Boost'; Kind = 'Bool'; Default = $false },
				@{ Key = 'MakeEdgeUninstallable'; Label = 'Make Edge uninstallable'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DeleteEdgeDesktopIcon'; Label = 'Delete Edge desktop icon'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisableWindowsUpdate'; Label = 'Disable Windows Update'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DisablePointerPrecision'; Label = 'Disable pointer precision'; Kind = 'Bool'; Default = $false },
				@{ Key = 'DeleteWindowsOld'; Label = 'Delete Windows.old'; Kind = 'Bool'; Default = $false },
				@{ Key = 'ShowEndTask'; Label = 'Show End Task on taskbar'; Kind = 'Bool'; Default = $false },
				@{ Key = 'VBoxGuestAdditions'; Label = 'Install VirtualBox Guest Additions'; Kind = 'Bool'; Default = $false },
				@{ Key = 'VMwareTools'; Label = 'Install VMware Tools'; Kind = 'Bool'; Default = $false },
				@{ Key = 'VirtIoGuestTools'; Label = 'Install VirtIO guest tools'; Kind = 'Bool'; Default = $false },
				@{ Key = 'ParallelsTools'; Label = 'Install Parallels Tools'; Kind = 'Bool'; Default = $false }
			)
		}
		@{
			Name = 'Appearance and input'
			Options = @(
				@{ Key = 'Effects'; Label = 'Visual effects'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Performance', 'Custom') },
				@{ Key = 'ControlAnimations'; Label = 'Animate controls'; Kind = 'Bool'; Default = $true },
				@{ Key = 'ListviewShadow'; Label = 'Show icon label shadows'; Kind = 'Bool'; Default = $true },
				@{ Key = 'ThumbnailsOrIcon'; Label = 'Show thumbnails instead of icons'; Kind = 'Bool'; Default = $true },
				@{ Key = 'DragFullWindows'; Label = 'Show window contents while dragging'; Kind = 'Bool'; Default = $true },
				@{ Key = 'FontSmoothing'; Label = 'Smooth screen fonts'; Kind = 'Bool'; Default = $true },
				@{ Key = 'WallpaperSettings'; Label = 'Wallpaper'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'SolidColor') },
				@{ Key = 'WallpaperColor'; Label = 'Wallpaper color'; Kind = 'Text'; Default = '#000000' },
				@{ Key = 'LockScreenSettings'; Label = 'Lock screen'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'ColorSettings'; Label = 'Color theme'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Custom') },
				@{ Key = 'SystemColorTheme'; Label = 'System color theme'; Kind = 'Choice'; Default = 'Dark'; Choices = @('Dark', 'Light') },
				@{ Key = 'AppsColorTheme'; Label = 'Apps color theme'; Kind = 'Choice'; Default = 'Dark'; Choices = @('Dark', 'Light') },
				@{ Key = 'AccentColor'; Label = 'Accent color'; Kind = 'Text'; Default = '#0078D4' },
				@{ Key = 'LockKeySettings'; Label = 'Lock key behavior'; Kind = 'Choice'; Default = 'Skip'; Choices = @('Skip', 'Configure') },
				@{ Key = 'CapsLockInitial'; Label = 'Caps Lock initial state'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'On', 'Off') },
				@{ Key = 'CapsLockBehavior'; Label = 'Caps Lock behavior'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'NumLockInitial'; Label = 'Num Lock initial state'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'On', 'Off') },
				@{ Key = 'NumLockBehavior'; Label = 'Num Lock behavior'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'ScrollLockInitial'; Label = 'Scroll Lock initial state'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'On', 'Off') },
				@{ Key = 'ScrollLockBehavior'; Label = 'Scroll Lock behavior'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'StickyKeysSettings'; Label = 'Sticky Keys'; Kind = 'Choice'; Default = 'Default'; Choices = @('Default', 'Disabled') },
				@{ Key = 'TurnOffSystemSounds'; Label = 'Turn off system sounds'; Kind = 'Bool'; Default = $false }
			)
		}
		@{
			Name = 'Bloatwares'
			Options = (@(
				@{ Key = 'Bloatwares'; Label = 'Selected bloatware IDs'; Kind = 'Multiline'; Default = '' }
			) + $bloatwareOptions)
		}
		@{
			Name = 'Scripts'
			Options = @(
				@{ Key = 'HidePowerShellWindows'; Label = 'Hide PowerShell windows'; Kind = 'Bool'; Default = $false },
				@{ Key = 'ScriptSettings'; Label = 'Script settings'; Kind = 'Choice'; Default = 'Custom'; Choices = @('Default', 'Custom') },
				@{ Key = 'RestartExplorer'; Label = 'Restart Explorer after scripts'; Kind = 'Bool'; Default = $false },
				@{ Key = 'SystemScript0'; Label = 'System script 1'; Kind = 'Multiline'; Default = '' },
				@{ Key = 'SystemScript1'; Label = 'System script 2'; Kind = 'Multiline'; Default = '' },
				@{ Key = 'DefaultUserScript0'; Label = 'Default user script 1'; Kind = 'Multiline'; Default = '' },
				@{ Key = 'UserOnceScript0'; Label = 'User once script 1'; Kind = 'Multiline'; Default = '' },
				@{ Key = 'FirstLogonScript0'; Label = 'First logon script 1'; Kind = 'Multiline'; Default = '' },
				@{ Key = 'AppLockerSettings'; Label = 'AppLocker'; Kind = 'Choice'; Default = 'Skip'; Choices = @('Skip', 'Audit', 'Enforce') }
			)
		}
	)

	return (Add-GuiDeploymentMediaUnattendOptionMetadata -Groups $groups)
}

function Get-GuiDeploymentMediaUnattendStateValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State,

		[Parameter(Mandatory = $true)]
		[string]$Key,

		[object]$Default = $null
	)

	if ($State.Contains($Key)) { return $State[$Key] }
	return $Default
}

function Test-GuiDeploymentMediaUnattendStateEnabled
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State,

		[Parameter(Mandatory = $true)]
		[string]$Key
	)

	return [bool](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $Key -Default $false)
}

function New-GuiDeploymentMediaUnattendChoice
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Label,

		[Parameter(Mandatory = $true)]
		[string]$Value,

		[string]$Description = ''
	)

	$advancedLabel = $Label
	if ($Label -ne $Value) { $advancedLabel = '{0} [{1}]' -f $Label, $Value }
	return [pscustomobject]@{
		Label         = $Label
		Value         = $Value
		AdvancedLabel = $advancedLabel
		Description   = $Description
	}
}

function ConvertTo-GuiDeploymentMediaUnattendChoiceItems
{
	[CmdletBinding()]
	param (
		[object[]]$Choices,
		[hashtable]$ChoiceLabels
	)

	$items = @()
	foreach ($choice in @($Choices))
	{
		if ($null -eq $choice) { continue }
		if ($choice -is [System.Collections.IDictionary] -and $choice.Contains('Value'))
		{
			$label = if ($choice.Contains('Label')) { [string]$choice.Label } else { [string]$choice.Value }
			$value = [string]$choice.Value
			$description = if ($choice.Contains('Description')) { [string]$choice.Description } else { '' }
			$items += New-GuiDeploymentMediaUnattendChoice -Label $label -Value $value -Description $description
			continue
		}
		if ($choice.PSObject.Properties['Value'])
		{
			$label = if ($choice.PSObject.Properties['Label']) { [string]$choice.Label } else { [string]$choice.Value }
			$value = [string]$choice.Value
			$description = if ($choice.PSObject.Properties['Description']) { [string]$choice.Description } else { '' }
			$items += New-GuiDeploymentMediaUnattendChoice -Label $label -Value $value -Description $description
			continue
		}

		$value = [string]$choice
		$label = $value
		if ($ChoiceLabels -and $ChoiceLabels.ContainsKey($value)) { $label = [string]$ChoiceLabels[$value] }
		$items += New-GuiDeploymentMediaUnattendChoice -Label $label -Value $value
	}
	return $items
}

function Get-GuiDeploymentMediaUnattendBloatwareCategory
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][string]$Key)

	switch ($Key)
	{
		{ $_ -in @('RemoveZuneVideo', 'RemoveCamera', 'RemoveClipchamp', 'RemoveClock', 'RemoveMaps', 'RemoveNews', 'RemovePaint', 'RemovePaint3D', 'RemovePhotos', 'RemoveSolitaire', 'RemoveStickyNotes', 'RemoveVoiceRecorder', 'RemoveWeather') } { return 'Media and consumer apps' }
		'RemoveXboxApps' { return 'Xbox apps' }
		{ $_ -in @('Remove3DViewer', 'RemoveHandwriting', 'RemoveInternetExplorer', 'RemoveMathInputPanel', 'RemoveMediaFeatures', 'RemoveMixedReality', 'RemovePowerShellISE', 'RemoveRdpClient', 'RemoveSpeech', 'RemoveWindowsMediaPlayer', 'RemoveWordPad') } { return 'Legacy components' }
		{ $_ -in @('RemoveOneDrive', 'RemoveTeams', 'RemoveOutlook', 'RemoveOffice365', 'RemoveOneNote', 'RemoveQuickAssist') } { return 'Enterprise-sensitive apps' }
		default { return 'Microsoft apps' }
	}
}

function Test-GuiDeploymentMediaUnattendRecommendedBloatware
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][string]$Key)

	return ($Key -in @(
		'RemoveBingSearch',
		'RemoveClipchamp',
		'RemoveCopilot',
		'RemoveCortana',
		'RemoveDevHome',
		'RemoveFeedbackHub',
		'RemoveGetStarted',
		'RemoveMixedReality',
		'RemoveNews',
		'RemoveOneNote',
		'RemovePeople',
		'RemoveSolitaire',
		'RemoveTeams',
		'RemoveToDo',
		'RemoveWallet',
		'RemoveWeather',
		'RemoveXboxApps',
		'RemoveYourPhone'
	))
}

function Get-GuiDeploymentMediaUnattendOptionMetadata
{
	[CmdletBinding()]
	param ()

	return @{
		LanguageSettings = @{
			Section      = 'Language'
			Description  = 'Choose whether setup should ask for language details or use this answer file.'
			ChoiceLabels = @{ Interactive = 'Ask during setup'; Unattended = 'Use answer file settings' }
		}
		UILanguage = @{
			Section     = 'Language'
			Description = 'Sets the Windows Setup and installed Windows display language.'
			Kind        = 'Choice'
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United States)' -Value 'en-US'
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United Kingdom)' -Value 'en-GB'
				New-GuiDeploymentMediaUnattendChoice -Label 'German (Germany)' -Value 'de-DE'
				New-GuiDeploymentMediaUnattendChoice -Label 'French (France)' -Value 'fr-FR'
				New-GuiDeploymentMediaUnattendChoice -Label 'Spanish (Spain)' -Value 'es-ES'
			)
		}
		UserLocale = @{
			Section     = 'Language'
			Description = 'Sets regional formatting for dates, numbers, and currency.'
			Kind        = 'Choice'
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United States)' -Value 'en-US'
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United Kingdom)' -Value 'en-GB'
				New-GuiDeploymentMediaUnattendChoice -Label 'English (South Africa)' -Value 'en-ZA'
				New-GuiDeploymentMediaUnattendChoice -Label 'German (Germany)' -Value 'de-DE'
				New-GuiDeploymentMediaUnattendChoice -Label 'French (France)' -Value 'fr-FR'
			)
		}
		KeyboardIdentifier = @{
			Section     = 'Region and keyboard'
			Description = 'Keyboard layout written to InputLocale in the answer file.'
			Kind        = 'Choice'
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United States) - QWERTY' -Value '00000409'
				New-GuiDeploymentMediaUnattendChoice -Label 'English (United Kingdom) - QWERTY' -Value '00000809'
				New-GuiDeploymentMediaUnattendChoice -Label 'English (South Africa) - QWERTY' -Value '00000409'
				New-GuiDeploymentMediaUnattendChoice -Label 'German (Germany)' -Value '00000407'
				New-GuiDeploymentMediaUnattendChoice -Label 'French (France)' -Value '0000040C'
			)
		}
		GeoLocation = @{
			Section     = 'Region and keyboard'
			Description = 'Country or region written as the Windows GeoID value.'
			Kind        = 'Choice'
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'United States' -Value '244'
				New-GuiDeploymentMediaUnattendChoice -Label 'South Africa' -Value '209'
				New-GuiDeploymentMediaUnattendChoice -Label 'United Kingdom' -Value '242'
				New-GuiDeploymentMediaUnattendChoice -Label 'Germany' -Value '94'
				New-GuiDeploymentMediaUnattendChoice -Label 'France' -Value '84'
			)
		}
		TimeZoneSettings = @{
			Section      = 'Region and keyboard'
			Description  = 'Use automatic time zone handling or write an explicit Windows time zone ID.'
			ChoiceLabels = @{ Implicit = 'Use Windows default'; Explicit = 'Specify time zone' }
		}
		TimeZone = @{
			Section     = 'Region and keyboard'
			Description = 'Windows time zone ID used when explicit time zone is selected.'
			Placeholder = 'UTC'
			DependsOn   = @(@{ Key = 'TimeZoneSettings'; Value = 'Explicit' })
		}
		ProcessorArchitectures = @{
			Section     = 'Advanced locale'
			Description = 'Processor architecture used for unattend component names.'
			AdvancedOnly = $true
			ChoiceLabels = @{ amd64 = '64-bit (x64)'; x86 = '32-bit (x86)'; arm64 = 'ARM64' }
		}
		EditionSettings = @{
			Section      = 'Edition and product key'
			Description  = 'Choose how Windows Setup selects the edition and product key.'
			ChoiceLabels = @{ Interactive = 'Ask during setup'; Firmware = 'Use firmware key'; Generic = 'Use generic edition key' }
		}
		WindowsEdition = @{
			Section     = 'Edition and product key'
			Description = 'Edition used when generating a generic installation key.'
			DependsOn   = @(@{ Key = 'EditionSettings'; Value = 'Generic' })
			ChoiceLabels = @{
				home = 'Windows Home'
				home_n = 'Windows Home N'
				home_single = 'Windows Home Single Language'
				education = 'Windows Education'
				education_n = 'Windows Education N'
				pro = 'Windows Pro'
				pro_n = 'Windows Pro N'
				pro_education = 'Windows Pro Education'
				pro_education_n = 'Windows Pro Education N'
				pro_workstations = 'Windows Pro for Workstations'
				pro_workstations_n = 'Windows Pro for Workstations N'
				enterprise = 'Windows Enterprise'
				enterprise_n = 'Windows Enterprise N'
			}
		}
		ProductKey = @{
			Section     = 'Edition and product key'
			Description = 'Optional 25-character product key. Leave blank to show setup UI when needed.'
			Placeholder = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
			AdvancedOnly = $true
		}
		UseConfigurationSet = @{ Section = 'Windows PE'; Description = 'Tell Windows Setup to use files from a configuration set.'; AdvancedOnly = $true }
		PESettings = @{ Section = 'Windows PE'; Description = 'Controls additional Windows PE setup settings.'; AdvancedOnly = $true; ChoiceLabels = @{ Default = 'Use Windows default'; Generate = 'Generate Windows PE settings' } }
		BypassRequirementsCheck = @{ Section = 'Hardware bypass'; Description = 'Allows Windows 11 setup on unsupported TPM, Secure Boot, CPU, RAM, or storage configurations.'; Risk = 'Medium'; Recommended = $true }
		CompactOs = @{ Section = 'Disk and partitioning'; Description = 'Controls Compact OS behavior during installation.'; AdvancedOnly = $true; ChoiceLabels = @{ Default = 'Use Windows default'; Always = 'Always enable'; Never = 'Never enable' } }
		PartitionSettings = @{ Section = 'Disk and partitioning'; Description = 'Choose whether disk partitioning is handled manually or by the answer file.'; ChoiceLabels = @{ Interactive = 'Ask during setup'; Unattended = 'Partition automatically' } }
		PartitionLayout = @{ Section = 'Disk and partitioning'; Description = 'Partition table used when unattended partitioning is selected.'; DependsOn = @(@{ Key = 'PartitionSettings'; Value = 'Unattended' }); ChoiceLabels = @{ Automatic = 'Automatic'; GPT = 'GPT / UEFI'; MBR = 'MBR / BIOS' } }
		RecoveryMode = @{ Section = 'Disk and partitioning'; Description = 'Controls whether setup creates a recovery partition.'; DependsOn = @(@{ Key = 'PartitionSettings'; Value = 'Unattended' }); ChoiceLabels = @{ Partition = 'Create recovery partition'; None = 'Do not create recovery partition' } }
		InstallFromSettings = @{ Section = 'Install image selection'; Description = 'Controls how setup selects the image inside install.wim or install.esd.'; ChoiceLabels = @{ Automatic = 'Automatic'; ImageIndex = 'By image index'; ImageName = 'By image name' } }
		InstallImageIndex = @{ Section = 'Install image selection'; Description = 'Numeric image index used when image index selection is enabled.'; Placeholder = '1'; DependsOn = @(@{ Key = 'InstallFromSettings'; Value = 'ImageIndex' }) }
		InstallImageName = @{ Section = 'Install image selection'; Description = 'Image name used when image name selection is enabled.'; Placeholder = 'Windows 11 Pro'; DependsOn = @(@{ Key = 'InstallFromSettings'; Value = 'ImageName' }) }
		Components = @{ Section = 'Advanced components'; Description = 'Raw additional unattend component XML. Use only when you need a component not modeled here.'; AdvancedOnly = $true }
		ComputerNameSettings = @{ Section = 'Computer identity'; Description = 'Use a generated computer name or provide a fixed name.'; ChoiceLabels = @{ Random = 'Generate automatically'; Custom = 'Use custom name' } }
		ComputerName = @{ Section = 'Computer identity'; Description = 'Custom computer name written during specialize.'; Placeholder = 'DESKTOP-DEPLOY01'; DependsOn = @(@{ Key = 'ComputerNameSettings'; Value = 'Custom' }) }
		AccountSettings = @{ Section = 'Account setup'; Description = 'Choose how Windows OOBE handles the first user account.'; ChoiceLabels = @{ InteractiveMicrosoftAccount = 'Microsoft account setup'; InteractiveLocalAccount = 'Local account setup'; UnattendedLocalAccount = 'Create local account automatically' } }
		AccountName0 = @{ Section = 'Account setup'; Description = 'Local account name created by the answer file.'; Placeholder = 'Admin'; DependsOn = @(@{ Key = 'AccountSettings'; Value = 'UnattendedLocalAccount' }) }
		AccountDisplayName0 = @{ Section = 'Account setup'; Description = 'Optional display name for the local account.'; Placeholder = 'Administrator'; DependsOn = @(@{ Key = 'AccountSettings'; Value = 'UnattendedLocalAccount' }) }
		AccountPassword0 = @{ Section = 'Account setup'; Description = 'Password for the unattended local account.'; DependsOn = @(@{ Key = 'AccountSettings'; Value = 'UnattendedLocalAccount' }) }
		AccountGroup0 = @{ Section = 'Account setup'; Description = 'Local group assigned to the created account.'; DependsOn = @(@{ Key = 'AccountSettings'; Value = 'UnattendedLocalAccount' }); AdvancedOnly = $true; ChoiceLabels = @{ Administrators = 'Administrators'; Users = 'Standard users' } }
		AutoLogon = @{ Section = 'Account setup'; Description = 'Optionally log on once with the created local account.'; DependsOn = @(@{ Key = 'AccountSettings'; Value = 'UnattendedLocalAccount' }); AdvancedOnly = $true; ChoiceLabels = @{ None = 'Do not auto logon'; OwnAccount = 'Auto logon once' } }
		LockoutSettings = @{ Section = 'Account policy'; Description = 'Controls local account lockout policy.'; AdvancedOnly = $true; ChoiceLabels = @{ Default = 'Use Windows default'; Disabled = 'Disable lockout policy' } }
		PasswordExpirationSettings = @{ Section = 'Account policy'; Description = 'Controls password expiration for local accounts.'; AdvancedOnly = $true; ChoiceLabels = @{ Default = 'Use Windows default'; Unlimited = 'Never expire' } }
		ProcessAuditSettings = @{ Section = 'Account policy'; Description = 'Controls process creation audit policy.'; AdvancedOnly = $true; ChoiceLabels = @{ Disabled = 'Disabled'; Enabled = 'Enabled' } }
		WifiSettings = @{ Section = 'Wi-Fi and OOBE'; Description = 'Choose whether Wi-Fi setup is shown, skipped, or configured unattended.'; ChoiceLabels = @{ Interactive = 'Ask during setup'; Skip = 'Skip Wi-Fi setup'; Unattended = 'Configure Wi-Fi automatically' } }
		WifiSsid = @{ Section = 'Wi-Fi and OOBE'; Description = 'Wireless network name used when unattended Wi-Fi is enabled.'; Placeholder = 'OfficeWiFi'; DependsOn = @(@{ Key = 'WifiSettings'; Value = 'Unattended' }) }
		WifiKey = @{ Section = 'Wi-Fi and OOBE'; Description = 'Wireless network key used when unattended Wi-Fi is enabled.'; DependsOn = @(@{ Key = 'WifiSettings'; Value = 'Unattended' }) }
		ExpressSettings = @{ Section = 'Privacy during OOBE'; Description = 'Controls Windows OOBE express privacy defaults.'; ChoiceLabels = @{ Interactive = 'Ask during setup'; EnableAll = 'Enable all recommended settings'; DisableAll = 'Disable all recommended settings' } }
		BypassNetworkCheck = @{ Section = 'Wi-Fi and OOBE'; Description = 'Allows local account setup without internet during OOBE.'; Risk = 'Low' }
		KeepSensitiveFiles = @{ Section = 'Privacy during OOBE'; Description = 'Keep temporary files that may contain setup secrets. Use only for controlled diagnostics.'; Risk = 'High'; AdvancedOnly = $true }
		UseNarrator = @{ Section = 'Wi-Fi and OOBE'; Description = 'Enable Narrator during setup.'; AdvancedOnly = $true }
		EnableLongPaths = @{ Section = 'System hardening'; Description = 'Enable Win32 long path support.' }
		EnableRemoteDesktop = @{ Section = 'Remote access'; Description = 'Enable Remote Desktop connections after installation.'; Risk = 'Medium' }
		HardenSystemDriveAcl = @{ Section = 'System hardening'; Description = 'Apply stricter ACL handling for the system drive.'; AdvancedOnly = $true }
		DeleteJunctions = @{ Section = 'Compatibility'; Description = 'Remove legacy compatibility junctions.'; AdvancedOnly = $true; Risk = 'Medium' }
		AllowPowerShellScripts = @{ Section = 'Compatibility'; Description = 'Allow PowerShell script execution during deployment workflows.'; AdvancedOnly = $true; Risk = 'Medium' }
		DisableLastAccess = @{ Section = 'System hardening'; Description = 'Disable NTFS last access timestamp updates.' }
		PreventAutomaticReboot = @{ Section = 'System hardening'; Description = 'Prevent setup or policy from automatically rebooting in selected paths.'; AdvancedOnly = $true }
		DisableSac = @{ Section = 'Security posture'; Description = 'Disable Smart App Control.'; AdvancedOnly = $true; Risk = 'Medium' }
		DisableUac = @{ Section = 'Security posture'; Description = 'Disable User Account Control. This materially reduces local elevation protections.'; Risk = 'High'; AdvancedOnly = $true }
		DisableSmartScreen = @{ Section = 'Security posture'; Description = 'Disable Microsoft Defender SmartScreen prompts.'; Risk = 'Medium' }
		DisableSystemRestore = @{ Section = 'Recovery posture'; Description = 'Disable System Restore.'; AdvancedOnly = $true; Risk = 'Medium' }
		DisableFastStartup = @{ Section = 'System hardening'; Description = 'Disable Fast Startup to make shutdown and boot behavior predictable.' }
		PreventDeviceEncryption = @{ Section = 'Security posture'; Description = 'Prevent automatic device encryption.'; Risk = 'Medium' }
		DisableCoreIsolation = @{ Section = 'Security posture'; Description = 'Disable Core Isolation memory protection.'; AdvancedOnly = $true; Risk = 'High' }
		DisableAutomaticRestartSignOn = @{ Section = 'Security posture'; Description = 'Disable automatic restart sign-on.'; AdvancedOnly = $true }
		DisableWpbt = @{ Section = 'Security posture'; Description = 'Disable Windows Platform Binary Table execution.'; AdvancedOnly = $true; Risk = 'Medium' }
		HideFiles = @{ Section = 'Explorer'; Description = 'Control hidden and protected operating system file visibility.'; ChoiceLabels = @{ Hidden = 'Keep hidden files hidden'; ShowHidden = 'Show hidden files'; ShowHiddenAndSystem = 'Show hidden and protected files' } }
		TaskbarSearch = @{ Section = 'Taskbar and Start'; Description = 'Controls the taskbar search entry point.'; ChoiceLabels = @{ Hide = 'Hidden'; Icon = 'Search icon'; Box = 'Search box'; Label = 'Search label' } }
		StartPinsSettings = @{ Section = 'Taskbar and Start'; Description = 'Controls pinned Start menu items.'; ChoiceLabels = @{ Default = 'Use Windows default'; Empty = 'Clear pins' } }
		StartTilesSettings = @{ Section = 'Taskbar and Start'; Description = 'Controls legacy Start tiles where applicable.'; ChoiceLabels = @{ Default = 'Use Windows default'; Empty = 'Clear tiles' } }
		TaskbarIcons = @{ Section = 'Taskbar and Start'; Description = 'Controls taskbar pinned icons.'; ChoiceLabels = @{ Default = 'Use Windows default'; Empty = 'Clear taskbar pins' } }
		DesktopIcons = @{ Section = 'Desktop icons'; Description = 'Choose whether to manage desktop icon visibility.'; ChoiceLabels = @{ Default = 'Use Windows default'; Custom = 'Customize icons' } }
		StartFolderSettings = @{ Section = 'Start folders'; Description = 'Choose whether to customize Start menu folders.'; ChoiceLabels = @{ Default = 'Use Windows default'; Custom = 'Customize folders' } }
		WallpaperSettings = @{ Section = 'Color and wallpaper'; Description = 'Choose whether to keep the default wallpaper or apply a solid color.'; ChoiceLabels = @{ Default = 'Use Windows default'; SolidColor = 'Use solid color' } }
		WallpaperColor = @{
			Section     = 'Color and wallpaper'
			Description = 'Solid wallpaper color used when solid color wallpaper is enabled.'
			Kind        = 'Choice'
			DependsOn   = @(@{ Key = 'WallpaperSettings'; Value = 'SolidColor' })
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'Black' -Value '#000000'
				New-GuiDeploymentMediaUnattendChoice -Label 'Dark gray' -Value '#202020'
				New-GuiDeploymentMediaUnattendChoice -Label 'Windows blue' -Value '#0078D4'
				New-GuiDeploymentMediaUnattendChoice -Label 'Slate' -Value '#334155'
			)
		}
		ColorSettings = @{ Section = 'Color and wallpaper'; Description = 'Choose whether to set system and app color theme values.'; ChoiceLabels = @{ Default = 'Use Windows default'; Custom = 'Customize color theme' } }
		SystemColorTheme = @{ Section = 'Color and wallpaper'; Description = 'System chrome color preference.'; DependsOn = @(@{ Key = 'ColorSettings'; Value = 'Custom' }); ChoiceLabels = @{ Dark = 'Dark'; Light = 'Light' } }
		AppsColorTheme = @{ Section = 'Color and wallpaper'; Description = 'App color preference.'; DependsOn = @(@{ Key = 'ColorSettings'; Value = 'Custom' }); ChoiceLabels = @{ Dark = 'Dark'; Light = 'Light' } }
		AccentColor = @{
			Section     = 'Color and wallpaper'
			Description = 'Windows accent color.'
			Kind        = 'Choice'
			DependsOn   = @(@{ Key = 'ColorSettings'; Value = 'Custom' })
			Choices     = @(
				New-GuiDeploymentMediaUnattendChoice -Label 'Windows blue' -Value '#0078D4'
				New-GuiDeploymentMediaUnattendChoice -Label 'Emerald' -Value '#10B981'
				New-GuiDeploymentMediaUnattendChoice -Label 'Slate' -Value '#64748B'
				New-GuiDeploymentMediaUnattendChoice -Label 'Violet' -Value '#7C3AED'
			)
		}
		LockKeySettings = @{ Section = 'Keyboard lock keys'; Description = 'Choose whether lock key behavior is configured.'; ChoiceLabels = @{ Skip = 'Do not configure'; Configure = 'Configure lock keys' } }
		AppLockerSettings = @{ Section = 'Application control'; Description = 'Controls generated AppLocker posture.'; AdvancedOnly = $true; ChoiceLabels = @{ Skip = 'Do not configure'; Audit = 'Audit only'; Enforce = 'Enforce rules' } }
		Bloatwares = @{ Section = 'Selected app removal preview'; Description = 'Read-only summary of apps selected for removal.'; Kind = 'GeneratedPreview'; AdvancedOnly = $false }
		HidePowerShellWindows = @{ Section = 'Script behavior'; Description = 'Run generated PowerShell setup steps with hidden windows.' }
		ScriptSettings = @{ Section = 'Script behavior'; Description = 'Controls whether custom setup scripts are included.'; ChoiceLabels = @{ Default = 'No custom scripts'; Custom = 'Use custom scripts' } }
		RestartExplorer = @{ Section = 'Script behavior'; Description = 'Restart Explorer after first-logon script changes.' }
		SystemScript0 = @{ Section = 'System scripts'; Description = 'Runs during specialize as SYSTEM.'; DependsOn = @(@{ Key = 'ScriptSettings'; Value = 'Custom' }); Risk = 'High'; AdvancedOnly = $true }
		SystemScript1 = @{ Section = 'System scripts'; Description = 'Second SYSTEM script, also run during specialize.'; DependsOn = @(@{ Key = 'ScriptSettings'; Value = 'Custom' }); Risk = 'High'; AdvancedOnly = $true }
		DefaultUserScript0 = @{ Section = 'User scripts'; Description = 'Stored for default-user customization metadata.'; DependsOn = @(@{ Key = 'ScriptSettings'; Value = 'Custom' }); Risk = 'Medium'; AdvancedOnly = $true }
		UserOnceScript0 = @{ Section = 'User scripts'; Description = 'Runs once for the first user session.'; DependsOn = @(@{ Key = 'ScriptSettings'; Value = 'Custom' }); Risk = 'High'; AdvancedOnly = $true }
		FirstLogonScript0 = @{ Section = 'User scripts'; Description = 'Runs as a first-logon command after setup completes.'; DependsOn = @(@{ Key = 'ScriptSettings'; Value = 'Custom' }); Risk = 'High'; AdvancedOnly = $true }
	}
}

function Get-GuiDeploymentMediaUnattendGroupMetadata
{
	[CmdletBinding()]
	param ()

	return @{
		'Language and region' = @{ DisplayName = 'Language & Region'; Description = 'Locale, keyboard, region, and architecture values.'; IconName = 'Language' }
		'Windows setup'       = @{ DisplayName = 'Windows Setup'; Description = 'Edition, product key, partitioning, and install image selection.'; IconName = 'WindowSettings' }
		'Accounts and OOBE'   = @{ DisplayName = 'Accounts & OOBE'; Description = 'Computer identity, account setup, Wi-Fi, and OOBE behavior.'; IconName = 'User' }
		'System policies'     = @{ DisplayName = 'Privacy & Security'; Description = 'Security posture, system hardening, recovery, and remote access.'; IconName = 'Shield' }
		'Desktop and Explorer'= @{ DisplayName = 'Desktop'; Description = 'Explorer, Start, taskbar, desktop icon, and folder preferences.'; IconName = 'Desktop' }
		'Edge and apps'       = @{ DisplayName = 'Apps'; Description = 'Edge, Windows features, app suggestions, and VM guest tools.'; IconName = 'AppsTab' }
		'Appearance and input'= @{ DisplayName = 'Appearance'; Description = 'Visual effects, wallpaper, color, keyboard locks, and accessibility.'; IconName = 'WindowSettings' }
		'Bloatwares'          = @{ DisplayName = 'App Removal'; Description = 'Search, select, and review built-in app removals.'; IconName = 'Delete' }
		'Scripts'             = @{ DisplayName = 'Scripts'; Description = 'Custom setup scripts and application-control options.'; IconName = 'Code' }
	}
}

function Add-GuiDeploymentMediaUnattendOptionMetadata
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][object[]]$Groups)

	$metadata = Get-GuiDeploymentMediaUnattendOptionMetadata
	$groupMetadata = Get-GuiDeploymentMediaUnattendGroupMetadata
	foreach ($group in @($Groups))
	{
		$groupName = [string]$group.Name
		if ($groupMetadata.ContainsKey($groupName))
		{
			foreach ($groupProperty in @($groupMetadata[$groupName].Keys))
			{
				$group[$groupProperty] = $groupMetadata[$groupName][$groupProperty]
			}
		}
		if (-not $group.ContainsKey('DisplayName')) { $group['DisplayName'] = $groupName }

		foreach ($option in @($group.Options))
		{
			$key = [string]$option.Key
			if ($metadata.ContainsKey($key))
			{
				foreach ($property in @($metadata[$key].Keys))
				{
					$option[$property] = $metadata[$key][$property]
				}
			}
			if ($key -like 'Remove*')
			{
				$option['Section'] = Get-GuiDeploymentMediaUnattendBloatwareCategory -Key $key
				$option['Description'] = ('Remove {0} from the generated deployment plan where Windows supports removal.' -f [string]$option.Label)
				$option['Category'] = 'Bloatware'
				$option['Recommended'] = Test-GuiDeploymentMediaUnattendRecommendedBloatware -Key $key
				if (-not $option.ContainsKey('Risk')) { $option['Risk'] = 'Low' }
			}
			if (-not $option.ContainsKey('Section') -or [string]::IsNullOrWhiteSpace([string]$option['Section']))
			{
				$option['Section'] = [string]$group['DisplayName']
			}
			if ($option.ContainsKey('ChoiceLabels') -or $option.ContainsKey('Choices'))
			{
				$labels = if ($option.ContainsKey('ChoiceLabels')) { $option['ChoiceLabels'] } else { $null }
				$option['Choices'] = ConvertTo-GuiDeploymentMediaUnattendChoiceItems -Choices @($option['Choices']) -ChoiceLabels $labels
			}
		}
	}

	return $Groups
}

function Get-GuiDeploymentMediaUnattendDisplayValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$OptionLookup,

		[Parameter(Mandatory = $true)]
		[string]$Key,

		[object]$Value
	)

	$text = [string]$Value
	if ($OptionLookup.ContainsKey($Key))
	{
		$option = $OptionLookup[$Key]
		foreach ($choice in @($option.Choices))
		{
			if ($choice.PSObject.Properties['Value'] -and [string]$choice.Value -eq $text)
			{
				if ($choice.PSObject.Properties['Label']) { return [string]$choice.Label }
			}
		}
	}
	return $text
}

function Get-GuiDeploymentMediaUnattendWindowsEditionProductKey
{
	[CmdletBinding()]
	param ([string]$Edition)

	switch ($Edition)
	{
		'home' { return 'YTMG3-N6DKC-DKB77-7M9GH-8HVX7' }
		'home_n' { return '4CPRK-NM3K3-X6XXQ-RXX86-WXCHW' }
		'home_single' { return 'BT79Q-G7N6G-PGBYW-4YWX6-6F4BT' }
		'education' { return 'YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY' }
		'education_n' { return '84NGF-MHBT6-FXBX8-QWJK7-DRR8H' }
		'pro' { return 'VK7JG-NPHTM-C97JM-9MPGT-3V66T' }
		'pro_n' { return '2B87N-8KFHP-DKV6R-Y2C8J-PKCKT' }
		'pro_education' { return '8PTT6-RNW4C-6V7J2-C2D3X-MHBPB' }
		'pro_education_n' { return 'GJTYN-HDMQY-FRR76-HVGC7-QPF8P' }
		'pro_workstations' { return 'DXG7C-N36C4-C4HTG-X4T3X-2YV77' }
		'pro_workstations_n' { return 'WYPNQ-8C467-V2W6J-TX4WX-WT2RQ' }
		'enterprise' { return 'XGVPP-NMH47-7TTHJ-W3FW7-8HV2C' }
		'enterprise_n' { return 'WGGHN-J84D6-QYCPR-T7PJ7-X766F' }
		default { return '' }
	}
}

function New-GuiDeploymentMediaUnattendElement
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[System.Xml.XmlElement]$Parent,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[string]$Text = $null
	)

	$element = $Document.CreateElement($Name, 'urn:schemas-microsoft-com:unattend')
	if ($null -ne $Text) { $element.InnerText = $Text }
	[void]$Parent.AppendChild($element)
	return $element
}

function Set-GuiDeploymentMediaUnattendElementPathValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[System.Xml.XmlElement]$Parent,

		[Parameter(Mandatory = $true)]
		[string[]]$Path,

		[AllowNull()]
		[string]$Value = $null
	)

	$current = $Parent
	foreach ($name in $Path)
	{
		$child = $null
		foreach ($node in @($current.ChildNodes))
		{
			if ($node.LocalName -eq $name -and $node.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend')
			{
				$child = $node
				break
			}
		}
		if (-not $child)
		{
			$child = New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $current -Name $name
		}
		$current = $child
	}
	if ($PSBoundParameters.ContainsKey('Value'))
	{
		$current.InnerText = $Value
	}
	return $current
}

function Get-GuiDeploymentMediaUnattendSettingsElement
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[string]$Pass
	)

	foreach ($node in @($Document.DocumentElement.ChildNodes))
	{
		if ($node.LocalName -eq 'settings' -and $node.GetAttribute('pass') -eq $Pass)
		{
			return $node
		}
	}

	$settings = $Document.CreateElement('settings', 'urn:schemas-microsoft-com:unattend')
	[void]$settings.SetAttribute('pass', $Pass)
	[void]$Document.DocumentElement.AppendChild($settings)
	return $settings
}

function Get-GuiDeploymentMediaUnattendComponentElement
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[string]$Pass,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$Architecture
	)

	$settings = Get-GuiDeploymentMediaUnattendSettingsElement -Document $Document -Pass $Pass
	foreach ($node in @($settings.ChildNodes))
	{
		if ($node.LocalName -eq 'component' -and $node.GetAttribute('name') -eq $Name)
		{
			[void]$node.SetAttribute('processorArchitecture', $Architecture)
			return $node
		}
	}

	$component = $Document.CreateElement('component', 'urn:schemas-microsoft-com:unattend')
	[void]$component.SetAttribute('name', $Name)
	[void]$component.SetAttribute('processorArchitecture', $Architecture)
	[void]$component.SetAttribute('publicKeyToken', '31bf3856ad364e35')
	[void]$component.SetAttribute('language', 'neutral')
	[void]$component.SetAttribute('versionScope', 'nonSxS')
	[void]$settings.AppendChild($component)
	return $component
}

function Add-GuiDeploymentMediaUnattendRunSynchronousCommand
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[string]$Pass,

		[Parameter(Mandatory = $true)]
		[string]$CommandLine,

		[Parameter(Mandatory = $true)]
		[string]$Description,

		[Parameter(Mandatory = $true)]
		[string]$Architecture,

		[Parameter(Mandatory = $true)]
		[ref]$Order
	)

	$componentName = if ($Pass -eq 'windowsPE') { 'Microsoft-Windows-Setup' } else { 'Microsoft-Windows-Deployment' }
	$component = Get-GuiDeploymentMediaUnattendComponentElement -Document $Document -Pass $Pass -Name $componentName -Architecture $Architecture
	$container = Set-GuiDeploymentMediaUnattendElementPathValue -Document $Document -Parent $component -Path @('RunSynchronous')
	$command = New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $container -Name 'RunSynchronousCommand'
	[void]$command.SetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State', 'add')
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'Order' -Text ([string]$Order.Value))
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'Description' -Text $Description)
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'Path' -Text $CommandLine)
	$Order.Value = [int]$Order.Value + 1
}

function Add-GuiDeploymentMediaUnattendFirstLogonCommand
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[string]$CommandLine,

		[Parameter(Mandatory = $true)]
		[string]$Description,

		[Parameter(Mandatory = $true)]
		[string]$Architecture,

		[Parameter(Mandatory = $true)]
		[ref]$Order
	)

	$component = Get-GuiDeploymentMediaUnattendComponentElement -Document $Document -Pass 'oobeSystem' -Name 'Microsoft-Windows-Shell-Setup' -Architecture $Architecture
	$container = Set-GuiDeploymentMediaUnattendElementPathValue -Document $Document -Parent $component -Path @('FirstLogonCommands')
	$command = New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $container -Name 'SynchronousCommand'
	[void]$command.SetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State', 'add')
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'Order' -Text ([string]$Order.Value))
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'Description' -Text $Description)
	[void](New-GuiDeploymentMediaUnattendElement -Document $Document -Parent $command -Name 'CommandLine' -Text $CommandLine)
	$Order.Value = [int]$Order.Value + 1
}

function Add-GuiDeploymentMediaUnattendExtensions
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Xml.XmlDocument]$Document,

		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State
	)

	$extensionNs = 'https://schneegans.de/windows/unattend-generator/'
	$extensions = $Document.CreateElement('Extensions', $extensionNs)
	$generator = $Document.CreateElement('BaselineOfflineGenerator', $extensionNs)
	$options = $Document.CreateElement('Options', $extensionNs)
	[void]$generator.SetAttribute('SourceModel', 'Schneegans.Unattend.Configuration')
	[void]$generator.SetAttribute('Runtime', 'Offline')

	foreach ($key in @($State.Keys | Sort-Object))
	{
		$option = $Document.CreateElement('Option', $extensionNs)
		[void]$option.SetAttribute('name', [string]$key)
		$option.InnerText = [string]$State[$key]
		[void]$options.AppendChild($option)
	}

	[void]$generator.AppendChild($options)
	[void]$extensions.AppendChild($generator)
	[void]$Document.DocumentElement.AppendChild($extensions)
}

function New-GuiDeploymentMediaUnattendXmlDocument
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State
	)

	$document = New-Object System.Xml.XmlDocument
	$declaration = $document.CreateXmlDeclaration('1.0', 'utf-8', $null)
	[void]$document.AppendChild($declaration)
	$root = $document.CreateElement('unattend', 'urn:schemas-microsoft-com:unattend')
	[void]$root.SetAttribute('xmlns', 'urn:schemas-microsoft-com:unattend')
	[void]$root.SetAttribute('xmlns:wcm', 'http://schemas.microsoft.com/WMIConfig/2002/State')
	[void]$document.AppendChild($root)

	foreach ($pass in @('offlineServicing', 'windowsPE', 'generalize', 'specialize', 'auditSystem', 'auditUser', 'oobeSystem'))
	{
		[void](Get-GuiDeploymentMediaUnattendSettingsElement -Document $document -Pass $pass)
	}

	$architecture = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'ProcessorArchitectures' -Default 'amd64')
	if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = 'amd64' }
	$uiLanguage = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'UILanguage' -Default 'en-US')
	if ([string]::IsNullOrWhiteSpace($uiLanguage)) { $uiLanguage = 'en-US' }
	$userLocale = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'UserLocale' -Default $uiLanguage)
	if ([string]::IsNullOrWhiteSpace($userLocale)) { $userLocale = $uiLanguage }
	$keyboardIdentifier = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'KeyboardIdentifier' -Default $userLocale)
	if ([string]::IsNullOrWhiteSpace($keyboardIdentifier)) { $keyboardIdentifier = $userLocale }

	$winPeIntl = Get-GuiDeploymentMediaUnattendComponentElement -Document $document -Pass 'windowsPE' -Name 'Microsoft-Windows-International-Core-WinPE' -Architecture $architecture
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $winPeIntl -Path @('UILanguage') -Value $uiLanguage)
	$setup = Get-GuiDeploymentMediaUnattendComponentElement -Document $document -Pass 'windowsPE' -Name 'Microsoft-Windows-Setup' -Architecture $architecture
	$productKey = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'ProductKey' -Default '')
	if ([string]::IsNullOrWhiteSpace($productKey) -and ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'EditionSettings' -Default 'Interactive')) -eq 'Generic')
	{
		$productKey = Get-GuiDeploymentMediaUnattendWindowsEditionProductKey -Edition ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'WindowsEdition' -Default 'pro'))
	}
	$willShowUi = 'OnError'
	if ([string]::IsNullOrWhiteSpace($productKey)) { $willShowUi = 'Always' }
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $setup -Path @('UserData', 'ProductKey', 'Key') -Value $productKey)
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $setup -Path @('UserData', 'ProductKey', 'WillShowUI') -Value $willShowUi)
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $setup -Path @('UserData', 'AcceptEula') -Value 'true')
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $setup -Path @('UseConfigurationSet') -Value ([string]([bool](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'UseConfigurationSet' -Default $false))).ToLowerInvariant())

	$oobeIntl = Get-GuiDeploymentMediaUnattendComponentElement -Document $document -Pass 'oobeSystem' -Name 'Microsoft-Windows-International-Core' -Architecture $architecture
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $oobeIntl -Path @('InputLocale') -Value $keyboardIdentifier)
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $oobeIntl -Path @('SystemLocale') -Value $userLocale)
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $oobeIntl -Path @('UILanguage') -Value $uiLanguage)
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $oobeIntl -Path @('UserLocale') -Value $userLocale)

	$shellSetup = Get-GuiDeploymentMediaUnattendComponentElement -Document $document -Pass 'oobeSystem' -Name 'Microsoft-Windows-Shell-Setup' -Architecture $architecture
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('OOBE', 'ProtectYourPC') -Value '3')
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('OOBE', 'HideEULAPage') -Value 'true')
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('OOBE', 'HideWirelessSetupInOOBE') -Value 'true')
	$hideOnlineAccount = (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'BypassNetworkCheck')
	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountSettings' -Default 'InteractiveMicrosoftAccount') -ne 'InteractiveMicrosoftAccount') { $hideOnlineAccount = $true }
	[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('OOBE', 'HideOnlineAccountScreens') -Value ([string]$hideOnlineAccount).ToLowerInvariant())

	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'TimeZoneSettings' -Default 'Implicit') -eq 'Explicit')
	{
		$timeZone = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'TimeZone' -Default '')
		if (-not [string]::IsNullOrWhiteSpace($timeZone))
		{
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('TimeZone') -Value $timeZone)
		}
	}

	$specializeShell = Get-GuiDeploymentMediaUnattendComponentElement -Document $document -Pass 'specialize' -Name 'Microsoft-Windows-Shell-Setup' -Architecture $architecture
	$computerName = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'ComputerName' -Default '')
	if (-not [string]::IsNullOrWhiteSpace($computerName))
	{
		[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $specializeShell -Path @('ComputerName') -Value $computerName)
	}

	$accountMode = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountSettings' -Default 'InteractiveMicrosoftAccount')
	$accountName = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountName0' -Default '')
	if ($accountMode -eq 'UnattendedLocalAccount' -and -not [string]::IsNullOrWhiteSpace($accountName))
	{
		$accounts = Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('UserAccounts', 'LocalAccounts')
		$localAccount = New-GuiDeploymentMediaUnattendElement -Document $document -Parent $accounts -Name 'LocalAccount'
		[void]$localAccount.SetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State', 'add')
		[void](New-GuiDeploymentMediaUnattendElement -Document $document -Parent $localAccount -Name 'Name' -Text $accountName)
		[void](New-GuiDeploymentMediaUnattendElement -Document $document -Parent $localAccount -Name 'Group' -Text ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountGroup0' -Default 'Administrators')))
		$displayName = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountDisplayName0' -Default '')
		if (-not [string]::IsNullOrWhiteSpace($displayName)) { [void](New-GuiDeploymentMediaUnattendElement -Document $document -Parent $localAccount -Name 'DisplayName' -Text $displayName) }
		$passwordValue = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountPassword0' -Default '')
		if (-not [string]::IsNullOrEmpty($passwordValue))
		{
			$password = New-GuiDeploymentMediaUnattendElement -Document $document -Parent $localAccount -Name 'Password'
			[void](New-GuiDeploymentMediaUnattendElement -Document $document -Parent $password -Name 'Value' -Text $passwordValue)
			[void](New-GuiDeploymentMediaUnattendElement -Document $document -Parent $password -Name 'PlainText' -Text 'true')
		}
		if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AutoLogon' -Default 'None') -eq 'OwnAccount')
		{
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('AutoLogon', 'Username') -Value $accountName)
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('AutoLogon', 'Enabled') -Value 'true')
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('AutoLogon', 'LogonCount') -Value '1')
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('AutoLogon', 'Password', 'Value') -Value $passwordValue)
			[void](Set-GuiDeploymentMediaUnattendElementPathValue -Document $document -Parent $shellSetup -Path @('AutoLogon', 'Password', 'PlainText') -Value 'true')
		}
	}

	$peOrder = 1
	if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'BypassRequirementsCheck')
	{
		foreach ($commandLine in @(
			'reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f',
			'reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f',
			'reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f',
			'reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f',
			'reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f'
		))
		{
			Add-GuiDeploymentMediaUnattendRunSynchronousCommand -Document $document -Pass 'windowsPE' -CommandLine $commandLine -Description 'Bypass Windows setup requirement check' -Architecture $architecture -Order ([ref]$peOrder)
		}
	}

	$specializeOrder = 1
	$specializeCommands = @(
		@{ Key = 'BypassNetworkCheck'; Description = 'Bypass network requirement'; Command = 'reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f' },
		@{ Key = 'EnableLongPaths'; Description = 'Enable long paths'; Command = 'reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f' },
		@{ Key = 'DisableLastAccess'; Description = 'Disable last access timestamps'; Command = 'fsutil.exe behavior set disableLastAccess 1' },
		@{ Key = 'DisableUac'; Description = 'Disable User Account Control'; Command = 'reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f' },
		@{ Key = 'DisableSmartScreen'; Description = 'Disable SmartScreen'; Command = 'reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v SmartScreenEnabled /t REG_SZ /d Off /f' },
		@{ Key = 'DisableFastStartup'; Description = 'Disable Fast Startup'; Command = 'reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f' },
		@{ Key = 'PreventDeviceEncryption'; Description = 'Prevent device encryption'; Command = 'reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\BitLocker" /v PreventDeviceEncryption /t REG_DWORD /d 1 /f' },
		@{ Key = 'EnableRemoteDesktop'; Description = 'Enable Remote Desktop'; Command = 'reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f' },
		@{ Key = 'DisableWindowsUpdate'; Description = 'Disable Windows Update'; Command = 'reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f' }
	)
	foreach ($entry in $specializeCommands)
	{
		if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key ([string]$entry.Key))
		{
			Add-GuiDeploymentMediaUnattendRunSynchronousCommand -Document $document -Pass 'specialize' -CommandLine ([string]$entry.Command) -Description ([string]$entry.Description) -Architecture $architecture -Order ([ref]$specializeOrder)
		}
	}

	$firstLogonOrder = 1
	$firstLogonCommands = @(
		@{ Key = 'ClassicContextMenu'; Description = 'Enable classic context menu'; Command = 'reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /f' },
		@{ Key = 'LeftTaskbar'; Description = 'Use left taskbar alignment'; Command = 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f' },
		@{ Key = 'HideTaskViewButton'; Description = 'Hide Task View button'; Command = 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f' },
		@{ Key = 'ShowFileExtensions'; Description = 'Show file extensions'; Command = 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f' },
		@{ Key = 'LaunchToThisPC'; Description = 'Open File Explorer to This PC'; Command = 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v LaunchTo /t REG_DWORD /d 1 /f' },
		@{ Key = 'DisableBingResults'; Description = 'Disable Bing results in search'; Command = 'reg.exe add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f' },
		@{ Key = 'DisableWidgets'; Description = 'Disable widgets'; Command = 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f' },
		@{ Key = 'DisableEdgeStartupBoost'; Description = 'Disable Edge Startup Boost'; Command = 'reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /t REG_DWORD /d 0 /f' },
		@{ Key = 'HideEdgeFre'; Description = 'Hide Edge first-run experience'; Command = 'reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f' },
		@{ Key = 'DeleteEdgeDesktopIcon'; Description = 'Delete Edge desktop icon'; Command = 'cmd.exe /c del /f /q "%PUBLIC%\Desktop\Microsoft Edge.lnk"' },
		@{ Key = 'TurnOffSystemSounds'; Description = 'Turn off system sounds'; Command = 'reg.exe add "HKCU\AppEvents\Schemes" /ve /d ".None" /f' }
	)
	foreach ($entry in $firstLogonCommands)
	{
		if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key ([string]$entry.Key))
		{
			Add-GuiDeploymentMediaUnattendFirstLogonCommand -Document $document -CommandLine ([string]$entry.Command) -Description ([string]$entry.Description) -Architecture $architecture -Order ([ref]$firstLogonOrder)
		}
	}

	$searchMode = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'TaskbarSearch' -Default 'Box')
	$searchValue = switch ($searchMode) { 'Hide' { '0' } 'Icon' { '1' } 'Label' { '3' } default { '2' } }
	Add-GuiDeploymentMediaUnattendFirstLogonCommand -Document $document -CommandLine ('reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d {0} /f' -f $searchValue) -Description 'Configure taskbar search' -Architecture $architecture -Order ([ref]$firstLogonOrder)

	$hideFiles = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'HideFiles' -Default 'Hidden')
	if ($hideFiles -eq 'ShowHidden' -or $hideFiles -eq 'ShowHiddenAndSystem')
	{
		Add-GuiDeploymentMediaUnattendFirstLogonCommand -Document $document -CommandLine 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f' -Description 'Show hidden files' -Architecture $architecture -Order ([ref]$firstLogonOrder)
	}
	if ($hideFiles -eq 'ShowHiddenAndSystem')
	{
		Add-GuiDeploymentMediaUnattendFirstLogonCommand -Document $document -CommandLine 'reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSuperHidden /t REG_DWORD /d 1 /f' -Description 'Show protected system files' -Architecture $architecture -Order ([ref]$firstLogonOrder)
	}

	foreach ($scriptKey in @('SystemScript0', 'SystemScript1'))
	{
		$scriptText = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $scriptKey -Default '')
		if (-not [string]::IsNullOrWhiteSpace($scriptText))
		{
			Add-GuiDeploymentMediaUnattendRunSynchronousCommand -Document $document -Pass 'specialize' -CommandLine ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f ($scriptText -replace '"', '\"')) -Description $scriptKey -Architecture $architecture -Order ([ref]$specializeOrder)
		}
	}
	foreach ($scriptKey in @('FirstLogonScript0', 'UserOnceScript0'))
	{
		$scriptText = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $scriptKey -Default '')
		if (-not [string]::IsNullOrWhiteSpace($scriptText))
		{
			Add-GuiDeploymentMediaUnattendFirstLogonCommand -Document $document -CommandLine ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f ($scriptText -replace '"', '\"')) -Description $scriptKey -Architecture $architecture -Order ([ref]$firstLogonOrder)
		}
	}

	Add-GuiDeploymentMediaUnattendExtensions -Document $document -State $State
	return $document
}

function Save-GuiDeploymentMediaUnattendXml
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State,

		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	$targetDirectory = [System.IO.Path]::GetDirectoryName($Path)
	if (-not [string]::IsNullOrWhiteSpace($targetDirectory))
	{
		[void][System.IO.Directory]::CreateDirectory($targetDirectory)
	}

	$document = New-GuiDeploymentMediaUnattendXmlDocument -State $State
	$settings = New-Object System.Xml.XmlWriterSettings
	$settings.Encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
	$settings.Indent = $true
	$settings.IndentChars = '  '
	$settings.NewLineChars = "`r`n"
	$settings.OmitXmlDeclaration = $false
	$writer = [System.Xml.XmlWriter]::Create($Path, $settings)
	try
	{
		$document.Save($writer)
	}
	finally
	{
		$writer.Close()
	}
}

function Show-GuiDeploymentMediaUnattendSaveDialog
{
	[CmdletBinding()]
	param ()

	$dialog = New-Object Microsoft.Win32.SaveFileDialog
	$dialog.Filter = 'Answer files (*.xml)|*.xml'
	$dialog.FileName = 'autounattend.xml'
	$dialog.OverwritePrompt = $true
	if ($dialog.ShowDialog($Script:MainForm) -eq $true)
	{
		return $dialog.FileName
	}
	return $null
}

function Get-GuiDeploymentMediaUnattendGeneratorState
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Controls
	)

	$state = [ordered]@{}
	foreach ($key in @($Controls.Keys | Sort-Object))
	{
		$entry = $Controls[$key]
		$control = $entry.Control
		switch ([string]$entry.Kind)
		{
			'Bool' { $state[$key] = [bool]$control.IsChecked }
			'Choice'
			{
				$value = $control.SelectedValue
				if ($null -eq $value)
				{
					$selectedItem = $control.SelectedItem
					if ($selectedItem -and $selectedItem.PSObject.Properties['Value']) { $value = $selectedItem.Value }
					else { $value = $selectedItem }
				}
				$state[$key] = [string]$value
			}
			'Password' { $state[$key] = [string]$control.Password }
			'GeneratedPreview'
			{
				$rawValue = ''
				if ($control.Tag -is [System.Collections.IDictionary] -and $control.Tag.Contains('RawValue')) { $rawValue = [string]$control.Tag['RawValue'] }
				$state[$key] = $rawValue
			}
			default { $state[$key] = [string]$control.Text }
		}
	}
	return $state
}

function New-GuiDeploymentMediaUnattendOptionControl
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Option
	)

	switch ([string]$Option.Kind)
	{
		'Bool'
		{
			$control = New-Object System.Windows.Controls.CheckBox
			$control.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
			$control.IsChecked = [bool]$Option.Default
			return $control
		}
		'Choice'
		{
			$control = New-Object System.Windows.Controls.ComboBox
			$control.MinWidth = 260
			$control.DisplayMemberPath = 'Label'
			$control.SelectedValuePath = 'Value'
			foreach ($choice in @($Option.Choices)) { [void]$control.Items.Add($choice) }
			$control.SelectedValue = [string]$Option.Default
			if ($control.SelectedIndex -lt 0 -and $control.Items.Count -gt 0) { $control.SelectedIndex = 0 }
			if (Get-Command -Name 'Set-ChoiceComboStyle' -CommandType Function -ErrorAction SilentlyContinue)
			{
				Set-ChoiceComboStyle -Combo $control
			}
			return $control
		}
		'Password'
		{
			$control = New-Object System.Windows.Controls.PasswordBox
			$control.MinWidth = 260
			$control.Password = [string]$Option.Default
			if ($Option.ContainsKey('Placeholder')) { $control.ToolTip = [string]$Option.Placeholder }
			return $control
		}
		'Multiline'
		{
			$control = New-Object System.Windows.Controls.TextBox
			$control.MinWidth = 360
			$control.MinHeight = 72
			$control.AcceptsReturn = $true
			$control.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$control.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
			$control.Text = [string]$Option.Default
			if ($Option.ContainsKey('Placeholder')) { $control.ToolTip = [string]$Option.Placeholder }
			return $control
		}
		'GeneratedPreview'
		{
			$control = New-Object System.Windows.Controls.TextBox
			$control.MinWidth = 360
			$control.MinHeight = 82
			$control.AcceptsReturn = $true
			$control.TextWrapping = [System.Windows.TextWrapping]::Wrap
			$control.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
			$control.IsReadOnly = $true
			$control.Text = 'No app removals selected.'
			$control.Tag = @{ RawValue = ''; Labels = @() }
			return $control
		}
		default
		{
			$control = New-Object System.Windows.Controls.TextBox
			$control.MinWidth = 260
			$control.Text = [string]$Option.Default
			if ($Option.ContainsKey('Placeholder')) { $control.ToolTip = [string]$Option.Placeholder }
			return $control
		}
	}
}

function ConvertTo-GuiDeploymentMediaUnattendBrush
{
	[CmdletBinding()]
	param (
		[hashtable]$Theme,
		[object]$BrushConverter,
		[string]$Name,
		[string]$Default
	)

	$color = $Default
	if ($Theme -and $Theme.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Theme[$Name]))
	{
		$color = [string]$Theme[$Name]
	}
	return $BrushConverter.ConvertFromString($color)
}

function New-GuiSectionHeader
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[string]$Description = '',
		[hashtable]$Theme,
		[object]$BrushConverter
	)

	$stack = New-Object System.Windows.Controls.StackPanel
	$stack.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)

	$titleBlock = New-Object System.Windows.Controls.TextBlock
	$titleBlock.Text = $Title
	$titleBlock.FontSize = 16
	$titleBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
	$titleBlock.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextPrimary' -Default '#F3F6FB'
	[void]$stack.Children.Add($titleBlock)

	if (-not [string]::IsNullOrWhiteSpace($Description))
	{
		$descriptionBlock = New-Object System.Windows.Controls.TextBlock
		$descriptionBlock.Text = $Description
		$descriptionBlock.FontSize = 11
		$descriptionBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
		$descriptionBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$descriptionBlock.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextMuted' -Default '#8F99B2'
		[void]$stack.Children.Add($descriptionBlock)
	}

	return $stack
}

function New-GuiSettingCard
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Title,

		[string]$Description = '',
		[hashtable]$Theme,
		[object]$BrushConverter
	)

	$card = New-Object System.Windows.Controls.Border
	$card.CornerRadius = [System.Windows.CornerRadius]::new(7)
	$card.BorderThickness = [System.Windows.Thickness]::new(1)
	$card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
	$card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	$card.Background = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'CardBg' -Default '#202638'
	$card.BorderBrush = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'BorderColor' -Default '#293044'

	$stack = New-Object System.Windows.Controls.StackPanel
	$heading = New-Object System.Windows.Controls.TextBlock
	$heading.Text = $Title
	$heading.FontSize = 13
	$heading.FontWeight = [System.Windows.FontWeights]::SemiBold
	$heading.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextPrimary' -Default '#F3F6FB'
	[void]$stack.Children.Add($heading)

	if (-not [string]::IsNullOrWhiteSpace($Description))
	{
		$desc = New-Object System.Windows.Controls.TextBlock
		$desc.Text = $Description
		$desc.Margin = [System.Windows.Thickness]::new(0, 2, 0, 10)
		$desc.FontSize = 11
		$desc.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$desc.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextMuted' -Default '#8F99B2'
		[void]$stack.Children.Add($desc)
	}

	$card.Child = $stack
	return @{ Border = $card; Content = $stack }
}

function New-GuiUnattendTabStripItem
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Key,

		[Parameter(Mandatory = $true)]
		[string]$Label,

		[string]$IconName,

		[hashtable]$Theme,
		[object]$BrushConverter
	)

	$tab = New-Object System.Windows.Controls.Border
	$tab.Tag = $Key
	$tab.Margin = [System.Windows.Thickness]::new(0, 0, 4, 0)
	$tab.Padding = [System.Windows.Thickness]::new(14, 8, 14, 0)
	$tab.CornerRadius = [System.Windows.CornerRadius]::new(4, 4, 0, 0)
	$tab.Cursor = [System.Windows.Input.Cursors]::Hand
	$tab.Background = [System.Windows.Media.Brushes]::Transparent
	$tab.BorderThickness = [System.Windows.Thickness]::new(0)

	$stack = New-Object System.Windows.Controls.StackPanel
	$labelRow = New-Object System.Windows.Controls.StackPanel
	$labelRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
	$labelRow.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$normalForeground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextMuted' -Default '#8F99B2'
	$icon = $null
	if (-not [string]::IsNullOrWhiteSpace($IconName) -and (Get-Command -Name 'New-GuiIconTextBlock' -CommandType Function -ErrorAction SilentlyContinue))
	{
		$icon = New-GuiIconTextBlock -IconName $IconName -Size 13 -Foreground $normalForeground -VerticalAlignment 'Center'
		if ($icon)
		{
			$icon.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
			[void]$labelRow.Children.Add($icon)
		}
	}
	$text = New-Object System.Windows.Controls.TextBlock
	$text.Text = $Label
	$text.FontSize = 12
	$text.FontWeight = [System.Windows.FontWeights]::Normal
	$text.Foreground = $normalForeground
	$text.TextWrapping = [System.Windows.TextWrapping]::NoWrap
	[void]$labelRow.Children.Add($text)
	[void]$stack.Children.Add($labelRow)

	$underline = New-Object System.Windows.Controls.Border
	$underline.Height = 3
	$underline.Margin = [System.Windows.Thickness]::new(0, 7, 0, 0)
	$underline.CornerRadius = [System.Windows.CornerRadius]::new(2)
	$underline.Background = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'AccentBlue' -Default '#2563EB'
	$underline.Visibility = [System.Windows.Visibility]::Hidden
	[void]$stack.Children.Add($underline)

	$tab.Child = $stack
	return @{ Key = $Key; Border = $tab; Text = $text; Icon = $icon; Underline = $underline }
}

function Update-GuiDeploymentMediaUnattendTabVisuals
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$TabItems,

		[Parameter(Mandatory = $true)]
		[string]$SelectedKey,

		[hashtable]$Theme,
		[object]$BrushConverter
	)

	$selectedBackground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'CardBg' -Default '#FFFFFF'
	$selectedForeground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextPrimary' -Default '#111827'
	$normalForeground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextMuted' -Default '#6B7280'
	foreach ($key in @($TabItems.Keys))
	{
		$item = $TabItems[$key]
		$isSelected = ([string]$key -eq [string]$SelectedKey)
		$item.Border.Background = if ($isSelected) { $selectedBackground } else { [System.Windows.Media.Brushes]::Transparent }
		$item.Text.Foreground = if ($isSelected) { $selectedForeground } else { $normalForeground }
		$item.Text.FontWeight = if ($isSelected) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal }
		if ($item.Icon) { $item.Icon.Foreground = if ($isSelected) { $selectedForeground } else { $normalForeground } }
		$item.Underline.Visibility = if ($isSelected) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Hidden }
	}
}

function New-GuiSettingRow
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Option,

		[Parameter(Mandatory = $true)]
		[object]$Control,

		[hashtable]$Theme,
		[object]$BrushConverter
	)

	$row = New-Object System.Windows.Controls.Border
	$row.Padding = [System.Windows.Thickness]::new(0, 8, 0, 8)
	$row.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
	$row.BorderBrush = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'BorderColor' -Default '#293044'

	$toolTipParts = @()
	if ($Option.ContainsKey('Description') -and -not [string]::IsNullOrWhiteSpace([string]$Option.Description))
	{
		$toolTipParts += [string]$Option.Description
	}
	if ($Option.ContainsKey('Risk') -and -not [string]::IsNullOrWhiteSpace([string]$Option.Risk))
	{
		$toolTipParts += ('Risk: {0}' -f [string]$Option.Risk)
	}
	$settingToolTip = [string]::Join([Environment]::NewLine, [string[]]$toolTipParts)
	if (-not [string]::IsNullOrWhiteSpace($settingToolTip))
	{
		$row.ToolTip = $settingToolTip
	}

	$grid = New-Object System.Windows.Controls.Grid
	$labelColumn = New-Object System.Windows.Controls.ColumnDefinition
	$labelColumn.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
	$valueColumn = New-Object System.Windows.Controls.ColumnDefinition
	$valueColumn.Width = New-Object System.Windows.GridLength(300)
	[void]$grid.ColumnDefinitions.Add($labelColumn)
	[void]$grid.ColumnDefinitions.Add($valueColumn)

	$labelStack = New-Object System.Windows.Controls.StackPanel
	$labelStack.Margin = [System.Windows.Thickness]::new(0, 0, 16, 0)
	if (-not [string]::IsNullOrWhiteSpace($settingToolTip)) { $labelStack.ToolTip = $settingToolTip }
	$labelLine = New-Object System.Windows.Controls.StackPanel
	$labelLine.Orientation = [System.Windows.Controls.Orientation]::Horizontal
	$label = New-Object System.Windows.Controls.TextBlock
	$label.Text = [string]$Option.Label
	$label.FontSize = 12
	$label.FontWeight = [System.Windows.FontWeights]::SemiBold
	$label.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextPrimary' -Default '#F3F6FB'
	$label.TextWrapping = [System.Windows.TextWrapping]::Wrap
	[void]$labelLine.Children.Add($label)

	if ($Option.ContainsKey('Risk') -and -not [string]::IsNullOrWhiteSpace([string]$Option.Risk))
	{
		$risk = New-Object System.Windows.Controls.TextBlock
		$risk.Text = ('Risk: {0}' -f [string]$Option.Risk)
		$risk.FontSize = 10
		$risk.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$risk.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$risk.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'CautionText' -Default '#F59E0B'
		$risk.ToolTip = ('This setting can affect setup behavior. Risk: {0}' -f [string]$Option.Risk)
		[void]$labelLine.Children.Add($risk)
	}
	[void]$labelStack.Children.Add($labelLine)

	if ($Option.ContainsKey('Description') -and -not [string]::IsNullOrWhiteSpace([string]$Option.Description))
	{
		$description = New-Object System.Windows.Controls.TextBlock
		$description.Text = [string]$Option.Description
		$description.FontSize = 11
		$description.Margin = [System.Windows.Thickness]::new(0, 3, 0, 0)
		$description.TextWrapping = [System.Windows.TextWrapping]::Wrap
		$description.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $Theme -BrushConverter $BrushConverter -Name 'TextMuted' -Default '#8F99B2'
		[void]$labelStack.Children.Add($description)
	}

	[System.Windows.Controls.Grid]::SetColumn($labelStack, 0)
	[void]$grid.Children.Add($labelStack)
	$Control.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	if (-not [string]::IsNullOrWhiteSpace($settingToolTip))
	{
		if ($null -eq $Control.ToolTip -or [string]::IsNullOrWhiteSpace([string]$Control.ToolTip))
		{
			$Control.ToolTip = $settingToolTip
		}
		else
		{
			$Control.ToolTip = ('{0}{1}{2}' -f [string]$Control.ToolTip, [Environment]::NewLine, $settingToolTip)
		}
	}
	[System.Windows.Controls.Grid]::SetColumn($Control, 1)
	[void]$grid.Children.Add($Control)

	$row.Child = $grid
	return $row
}

function Get-GuiDeploymentMediaUnattendControlEntryValue
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][hashtable]$Entry)

	$control = $Entry.Control
	switch ([string]$Entry.Kind)
	{
		'Bool' { return [bool]$control.IsChecked }
		'Choice'
		{
			if ($null -ne $control.SelectedValue) { return [string]$control.SelectedValue }
			$item = $control.SelectedItem
			if ($item -and $item.PSObject.Properties['Value']) { return [string]$item.Value }
			return [string]$item
		}
		'Password' { return [string]$control.Password }
		'GeneratedPreview'
		{
			if ($control.Tag -is [System.Collections.IDictionary] -and $control.Tag.Contains('RawValue')) { return [string]$control.Tag['RawValue'] }
			return ''
		}
		default { return [string]$control.Text }
	}
}

function Set-GuiDeploymentMediaUnattendControlEntryValue
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Entry,

		[AllowNull()]
		[object]$Value
	)

	$control = $Entry.Control
	switch ([string]$Entry.Kind)
	{
		'Bool' { $control.IsChecked = [bool]$Value }
		'Choice'
		{
			$control.SelectedValue = [string]$Value
			if ($control.SelectedIndex -lt 0 -and $control.Items.Count -gt 0) { $control.SelectedIndex = 0 }
		}
		'Password' { $control.Password = [string]$Value }
		'GeneratedPreview' { }
		default { $control.Text = [string]$Value }
	}
}

function Set-GuiDeploymentMediaUnattendChoiceDisplayMode
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Controls,

		[bool]$ShowAdvanced
	)

	$displayMember = if ($ShowAdvanced) { 'AdvancedLabel' } else { 'Label' }
	foreach ($entry in @($Controls.Values))
	{
		if ([string]$entry.Kind -eq 'Choice')
		{
			$entry.Control.DisplayMemberPath = $displayMember
			try { $entry.Control.Items.Refresh() } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.UnattendGenerator.RefreshChoiceDisplay' -Severity Debug }
		}
	}
}

function Update-GuiUnattendControlDependencies
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Controls,

		[bool]$ShowAdvanced
	)

	$state = Get-GuiDeploymentMediaUnattendGeneratorState -Controls $Controls
	foreach ($entry in @($Controls.Values))
	{
		$option = $entry.Option
		$isVisible = $true
		if ($option.ContainsKey('AdvancedOnly') -and [bool]$option.AdvancedOnly -and -not $ShowAdvanced)
		{
			$isVisible = $false
		}
		if ($entry.Row)
		{
			$entry.Row.Visibility = if ($isVisible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}

		$isEnabled = $true
		if ($option.ContainsKey('DependsOn'))
		{
			foreach ($dependency in @($option.DependsOn))
			{
				$dependencyKey = [string]$dependency.Key
				$actual = if ($state.Contains($dependencyKey)) { [string]$state[$dependencyKey] } else { '' }
				$expected = @($dependency.Value)
				if (-not ($expected -contains $actual))
				{
					$isEnabled = $false
					break
				}
			}
		}

		if ($entry.Control)
		{
			$entry.Control.IsEnabled = $isEnabled
		}
		if ($entry.Row)
		{
			$entry.Row.Opacity = if ($isEnabled) { 1.0 } else { 0.48 }
		}
	}
}

function Update-GuiDeploymentMediaBloatwarePreview
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][hashtable]$Controls)

	if (-not $Controls.ContainsKey('Bloatwares')) { return }
	$selectedKeys = @()
	$selectedLabels = @()
	foreach ($key in @($Controls.Keys | Sort-Object))
	{
		if ($key -notlike 'Remove*') { continue }
		$entry = $Controls[$key]
		if ([bool]$entry.Control.IsChecked)
		{
			$selectedKeys += $key
			$selectedLabels += [string]$entry.Option.Label
		}
	}

	$preview = $Controls['Bloatwares'].Control
	if ($selectedLabels.Count -eq 0)
	{
		$preview.Text = 'No app removals selected.'
	}
	else
	{
		$preview.Text = "Selected for removal:`r`n- " + ($selectedLabels -join "`r`n- ")
	}
	$preview.Tag = @{ RawValue = ($selectedKeys -join ';'); Labels = $selectedLabels }
}

function Test-GuiDeploymentMediaUnattendGeneratorState
{
	[CmdletBinding()]
	param ([Parameter(Mandatory = $true)][System.Collections.IDictionary]$State)

	$errors = New-Object System.Collections.Generic.List[string]
	$warnings = New-Object System.Collections.Generic.List[string]
	$languagePattern = '^[a-z]{2,3}-[A-Z]{2}$'
	foreach ($key in @('UILanguage', 'UserLocale'))
	{
		$value = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $key -Default '')
		if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch $languagePattern)
		{
			[void]$errors.Add(('{0} must be a valid language tag such as en-US.' -f $key))
		}
	}

	$productKey = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'ProductKey' -Default '')
	if (-not [string]::IsNullOrWhiteSpace($productKey) -and $productKey -notmatch '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$')
	{
		[void]$errors.Add('Custom product key must use the XXXXX-XXXXX-XXXXX-XXXXX-XXXXX format.')
	}

	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'TimeZoneSettings' -Default 'Implicit') -eq 'Explicit' -and [string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'TimeZone' -Default '')))
	{
		[void]$errors.Add('Explicit time zone requires a Windows time zone ID.')
	}

	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountSettings' -Default 'InteractiveMicrosoftAccount') -eq 'UnattendedLocalAccount' -and [string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountName0' -Default '')))
	{
		[void]$errors.Add('Unattended local account setup requires an account name.')
	}

	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'WifiSettings' -Default 'Interactive') -eq 'Unattended')
	{
		if ([string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'WifiSsid' -Default ''))) { [void]$errors.Add('Unattended Wi-Fi setup requires an SSID.') }
		if ([string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'WifiKey' -Default ''))) { [void]$errors.Add('Unattended Wi-Fi setup requires a network key.') }
	}

	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'InstallFromSettings' -Default 'Automatic') -eq 'ImageIndex')
	{
		$imageIndex = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'InstallImageIndex' -Default '')
		if ($imageIndex -notmatch '^[1-9][0-9]*$') { [void]$errors.Add('Install image index must be a positive number.') }
	}
	if ([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'InstallFromSettings' -Default 'Automatic') -eq 'ImageName' -and [string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'InstallImageName' -Default '')))
	{
		[void]$errors.Add('Install image name is required when selecting an image by name.')
	}

	foreach ($colorKey in @('WallpaperColor', 'AccentColor'))
	{
		$color = [string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $colorKey -Default '')
		if (-not [string]::IsNullOrWhiteSpace($color) -and $color -notmatch '^#[0-9A-Fa-f]{6}$')
		{
			[void]$errors.Add(('{0} must be a six-digit hex color.' -f $colorKey))
		}
	}

	if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'BypassRequirementsCheck') { [void]$warnings.Add('Bypass Windows 11 hardware checks is enabled.') }
	if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'DisableUac') { [void]$warnings.Add('User Account Control is disabled.') }
	if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'DisableWindowsUpdate') { [void]$warnings.Add('Windows Update is disabled.') }
	if (Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key 'KeepSensitiveFiles') { [void]$warnings.Add('Sensitive generated setup files will be kept.') }
	foreach ($scriptKey in @('SystemScript0', 'SystemScript1', 'DefaultUserScript0', 'UserOnceScript0', 'FirstLogonScript0'))
	{
		if (-not [string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $scriptKey -Default '')))
		{
			[void]$warnings.Add(('Custom script field {0} will run or be embedded during setup.' -f $scriptKey))
		}
	}

	return [pscustomobject]@{
		IsValid  = ($errors.Count -eq 0)
		Errors   = @($errors)
		Warnings = @($warnings)
	}
}

function Get-GuiDeploymentMediaUnattendSummary
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$State,

		[Parameter(Mandatory = $true)]
		[hashtable]$OptionLookup
	)

	$lines = New-Object System.Collections.Generic.List[string]
	$language = Get-GuiDeploymentMediaUnattendDisplayValue -OptionLookup $OptionLookup -Key 'UILanguage' -Value (Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'UILanguage' -Default 'en-US')
	$editionMode = Get-GuiDeploymentMediaUnattendDisplayValue -OptionLookup $OptionLookup -Key 'EditionSettings' -Value (Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'EditionSettings' -Default 'Interactive')
	$edition = Get-GuiDeploymentMediaUnattendDisplayValue -OptionLookup $OptionLookup -Key 'WindowsEdition' -Value (Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'WindowsEdition' -Default 'pro')
	$account = Get-GuiDeploymentMediaUnattendDisplayValue -OptionLookup $OptionLookup -Key 'AccountSettings' -Value (Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'AccountSettings' -Default 'InteractiveMicrosoftAccount')
	$partitioning = Get-GuiDeploymentMediaUnattendDisplayValue -OptionLookup $OptionLookup -Key 'PartitionSettings' -Value (Get-GuiDeploymentMediaUnattendStateValue -State $State -Key 'PartitionSettings' -Default 'Interactive')
	[void]$lines.Add(('Language: {0}' -f $language))
	[void]$lines.Add(('Edition: {0} ({1})' -f $editionMode, $edition))
	[void]$lines.Add(('Account setup: {0}' -f $account))
	[void]$lines.Add(('Disk partitioning: {0}' -f $partitioning))

	$securityKeys = @('BypassRequirementsCheck', 'BypassNetworkCheck', 'EnableRemoteDesktop', 'DisableSmartScreen', 'DisableUac', 'DisableWindowsUpdate', 'PreventDeviceEncryption', 'DisableCoreIsolation')
	$securitySelected = @($securityKeys | Where-Object { Test-GuiDeploymentMediaUnattendStateEnabled -State $State -Key $_ }).Count
	$bloatwareSelected = @($State.Keys | Where-Object { ([string]$_) -like 'Remove*' -and [bool]$State[$_] }).Count
	$scriptSelected = @('SystemScript0', 'SystemScript1', 'DefaultUserScript0', 'UserOnceScript0', 'FirstLogonScript0' | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-GuiDeploymentMediaUnattendStateValue -State $State -Key $_ -Default '')) }).Count
	[void]$lines.Add(('Security changes: {0} selected' -f $securitySelected))
	[void]$lines.Add(('Built-in app removals: {0} selected' -f $bloatwareSelected))
	[void]$lines.Add(('Custom scripts: {0} populated' -f $scriptSelected))
	return @($lines)
}

function Update-GuiDeploymentMediaUnattendReviewPanel
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Controls,

		[Parameter(Mandatory = $true)]
		[hashtable]$OptionLookup,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.TextBlock]$SummaryText,

		[Parameter(Mandatory = $true)]
		[System.Windows.Controls.TextBlock]$ValidationText
	)

	Update-GuiDeploymentMediaBloatwarePreview -Controls $Controls
	$state = Get-GuiDeploymentMediaUnattendGeneratorState -Controls $Controls
	$summary = Get-GuiDeploymentMediaUnattendSummary -State $state -OptionLookup $OptionLookup
	$validation = Test-GuiDeploymentMediaUnattendGeneratorState -State $state
	$SummaryText.Text = ($summary -join "`r`n")
	if (-not $validation.IsValid)
	{
		$ValidationText.Text = "Validation errors:`r`n- " + (@($validation.Errors) -join "`r`n- ")
	}
	elseif (@($validation.Warnings).Count -gt 0)
	{
		$ValidationText.Text = "Warnings:`r`n- " + (@($validation.Warnings) -join "`r`n- ")
	}
	else
	{
		$ValidationText.Text = 'Ready to generate. No validation errors or warnings.'
	}
	return $validation
}

function Get-GuiDeploymentMediaUnattendPresetChoices
{
	[CmdletBinding()]
	param ()

	return @(
		New-GuiDeploymentMediaUnattendChoice -Label 'Default' -Value 'Default'
		New-GuiDeploymentMediaUnattendChoice -Label 'Clean personal install' -Value 'CleanPersonal'
		New-GuiDeploymentMediaUnattendChoice -Label 'Technician install' -Value 'Technician'
		New-GuiDeploymentMediaUnattendChoice -Label 'Enterprise-safe' -Value 'EnterpriseSafe'
		New-GuiDeploymentMediaUnattendChoice -Label 'VM install' -Value 'VM'
		New-GuiDeploymentMediaUnattendChoice -Label 'Maximum privacy' -Value 'MaximumPrivacy'
		New-GuiDeploymentMediaUnattendChoice -Label 'Custom' -Value 'Custom'
	)
}

function Apply-GuiDeploymentMediaUnattendPreset
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Preset,

		[Parameter(Mandatory = $true)]
		[hashtable]$Controls
	)

	if ($Preset -eq 'Custom') { return }
	foreach ($entry in @($Controls.Values))
	{
		if ($entry.Option.ContainsKey('Default'))
		{
			Set-GuiDeploymentMediaUnattendControlEntryValue -Entry $entry -Value $entry.Option.Default
		}
	}

	$overrides = @{}
	switch ($Preset)
	{
		'CleanPersonal'
		{
			$overrides = @{
				BypassRequirementsCheck = $true
				ExpressSettings = 'DisableAll'
				ClassicContextMenu = $true
				ShowFileExtensions = $true
				DisableWidgets = $true
				DisableBingResults = $true
				HideEdgeFre = $true
				TaskbarSearch = 'Icon'
			}
		}
		'Technician'
		{
			$overrides = @{
				BypassRequirementsCheck = $true
				EnableLongPaths = $true
				ShowFileExtensions = $true
				LaunchToThisPC = $true
				KeepSensitiveFiles = $false
				ProcessAuditSettings = 'Enabled'
			}
		}
		'EnterpriseSafe'
		{
			$overrides = @{
				BypassRequirementsCheck = $false
				DisableUac = $false
				DisableWindowsUpdate = $false
				DisableSmartScreen = $false
				KeepSensitiveFiles = $false
				ExpressSettings = 'Interactive'
			}
		}
		'VM'
		{
			$overrides = @{
				BypassRequirementsCheck = $true
				BypassNetworkCheck = $true
				VBoxGuestAdditions = $true
				VMwareTools = $true
				VirtIoGuestTools = $true
				ShowFileExtensions = $true
			}
		}
		'MaximumPrivacy'
		{
			$overrides = @{
				BypassRequirementsCheck = $true
				BypassNetworkCheck = $true
				ExpressSettings = 'DisableAll'
				DisableWidgets = $true
				DisableBingResults = $true
				DisableAppSuggestions = $true
				HideEdgeFre = $true
				DisableEdgeStartupBoost = $true
				DeleteEdgeDesktopIcon = $true
				MakeEdgeUninstallable = $true
			}
		}
	}

	foreach ($key in @($Controls.Keys))
	{
		if ($key -like 'Remove*' -and [string]$Controls[$key].Kind -eq 'Bool')
		{
			$shouldSelect = ($Preset -in @('CleanPersonal', 'MaximumPrivacy') -and [bool]$Controls[$key].Option.Recommended)
			Set-GuiDeploymentMediaUnattendControlEntryValue -Entry $Controls[$key] -Value $shouldSelect
		}
	}
	foreach ($key in @($overrides.Keys))
	{
		if ($Controls.ContainsKey($key))
		{
			Set-GuiDeploymentMediaUnattendControlEntryValue -Entry $Controls[$key] -Value $overrides[$key]
		}
	}
	Update-GuiDeploymentMediaBloatwarePreview -Controls $Controls
}

function Show-GuiDeploymentMediaUnattendGeneratorDialog
{
	[CmdletBinding()]
	param (
		[System.Windows.Controls.TextBox]$TargetTextBox
	)

	$theme = $Script:CurrentTheme
	$bc = New-SafeBrushConverter -Context 'DeploymentMediaBuilderView.UnattendGenerator'
	$window = New-Object System.Windows.Window
	$window.Title = 'Create autounattend.xml'
	$workArea = [System.Windows.SystemParameters]::WorkArea
	$window.Width = [Math]::Min([double]940, [Math]::Max([double]760, [double]($workArea.Width - 96)))
	$window.Height = [Math]::Min([double]640, [Math]::Max([double]520, [double]($workArea.Height - 96)))
	$window.MinWidth = 760
	$window.MinHeight = 520
	$window.MaxWidth = [Math]::Max([double]$window.MinWidth, [double]($workArea.Width - 48))
	$window.MaxHeight = [Math]::Max([double]$window.MinHeight, [double]($workArea.Height - 48))
	$window.SizeToContent = [System.Windows.SizeToContent]::Manual
	$window.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip
	$window.WindowState = [System.Windows.WindowState]::Normal
	$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
	if ($theme)
	{
		$window.Background = $bc.ConvertFromString([string]$theme.WindowBg)
		$window.Foreground = $bc.ConvertFromString([string]$theme.TextPrimary)
	}
	if ((Test-Path -Path Variable:\Script:MainForm) -and $Script:MainForm)
	{
		$window.Owner = $Script:MainForm
		$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
		$window.ShowInTaskbar = $false
	}
	$roundedWindow = $null
	if ($theme -and (Get-Command -Name 'GUICommon\ConvertTo-RoundedWindow' -ErrorAction SilentlyContinue) -and (Get-Command -Name 'GUICommon\Complete-RoundedWindow' -ErrorAction SilentlyContinue))
	{
		$roundedWindow = GUICommon\ConvertTo-RoundedWindow -Window $window -Theme $theme
	}
	if (Get-Command -Name 'GUICommon\Set-GuiWindowChromeTheme' -ErrorAction SilentlyContinue)
	{
		[void](GUICommon\Set-GuiWindowChromeTheme -Window $window -UseDarkMode ($Script:CurrentThemeName -eq 'Dark'))
	}

	$root = New-Object System.Windows.Controls.Grid
	$root.Margin = [System.Windows.Thickness]::new(14)
	foreach ($height in @([System.Windows.GridLength]::Auto, [System.Windows.GridLength]::Auto, (New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)), [System.Windows.GridLength]::Auto))
	{
		$row = New-Object System.Windows.Controls.RowDefinition
		$row.Height = $height
		[void]$root.RowDefinitions.Add($row)
	}

	$header = New-Object System.Windows.Controls.Grid
	$header.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	$headerTitleColumn = New-Object System.Windows.Controls.ColumnDefinition
	$headerTitleColumn.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
	$headerActionColumn = New-Object System.Windows.Controls.ColumnDefinition
	$headerActionColumn.Width = [System.Windows.GridLength]::Auto
	[void]$header.ColumnDefinitions.Add($headerTitleColumn)
	[void]$header.ColumnDefinitions.Add($headerActionColumn)
	[System.Windows.Controls.Grid]::SetRow($header, 0)
	[void]$root.Children.Add($header)

	$titleStack = New-Object System.Windows.Controls.StackPanel
	$title = New-Object System.Windows.Controls.TextBlock
	$title.Text = 'Offline autounattend.xml generator'
	$title.FontSize = 17
	$title.FontWeight = [System.Windows.FontWeights]::SemiBold
	$title.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'TextPrimary' -Default '#F3F6FB'
	[void]$titleStack.Children.Add($title)
	$subtitle = New-Object System.Windows.Controls.TextBlock
	$subtitle.Text = 'Build a local answer file with friendly setup options, validation, and a final review.'
	$subtitle.FontSize = 11
	$subtitle.Margin = [System.Windows.Thickness]::new(0, 3, 0, 0)
	$subtitle.TextWrapping = [System.Windows.TextWrapping]::Wrap
	$subtitle.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'TextMuted' -Default '#8F99B2'
	[void]$titleStack.Children.Add($subtitle)
	[System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
	[void]$header.Children.Add($titleStack)

	$headerActions = New-Object System.Windows.Controls.StackPanel
	$headerActions.Orientation = [System.Windows.Controls.Orientation]::Horizontal
	$headerActions.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
	$headerActions.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$presetLabel = New-Object System.Windows.Controls.TextBlock
	$presetLabel.Text = 'Preset'
	$presetLabel.FontSize = 11
	$presetLabel.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$presetLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$presetLabel.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'TextMuted' -Default '#8F99B2'
	[void]$headerActions.Children.Add($presetLabel)
	$presetCombo = New-Object System.Windows.Controls.ComboBox
	$presetCombo.MinWidth = 190
	$presetCombo.DisplayMemberPath = 'Label'
	$presetCombo.SelectedValuePath = 'Value'
	foreach ($preset in @(Get-GuiDeploymentMediaUnattendPresetChoices)) { [void]$presetCombo.Items.Add($preset) }
	$presetCombo.SelectedValue = 'Default'
	if (Get-Command -Name 'Set-ChoiceComboStyle' -CommandType Function -ErrorAction SilentlyContinue) { Set-ChoiceComboStyle -Combo $presetCombo }
	[void]$headerActions.Children.Add($presetCombo)
	$advancedModeCheckBox = New-Object System.Windows.Controls.CheckBox
	$advancedModeCheckBox.Content = 'Advanced mode'
	$advancedModeCheckBox.Margin = [System.Windows.Thickness]::new(14, 0, 0, 0)
	$advancedModeCheckBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
	$advancedModeCheckBox.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'TextSecondary' -Default '#C7D0E0'
	$advancedModeCheckBox.ToolTip = 'Show advanced-only settings and raw XML/internal values beside friendly labels.'
	$startInAdvancedMode = $false
	if (Get-Command -Name 'Test-IsExpertModeUX' -CommandType Function -ErrorAction SilentlyContinue)
	{
		try { $startInAdvancedMode = [bool](Test-IsExpertModeUX) } catch { Write-SwallowedException -ErrorRecord $_ -Source 'DeploymentMediaBuilderView.UnattendGenerator.ResolveExpertMode' -Severity Debug }
	}
	elseif ((Test-Path -Path Variable:\Script:AdvancedMode) -and $Script:AdvancedMode)
	{
		$startInAdvancedMode = $true
	}
	$advancedModeCheckBox.IsChecked = $startInAdvancedMode
	[void]$headerActions.Children.Add($advancedModeCheckBox)
	[System.Windows.Controls.Grid]::SetColumn($headerActions, 1)
	[void]$header.Children.Add($headerActions)

	$tabScroll = New-Object System.Windows.Controls.ScrollViewer
	$tabScroll.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
	$tabScroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
	$tabScroll.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
	[System.Windows.Controls.Grid]::SetRow($tabScroll, 1)
	[void]$root.Children.Add($tabScroll)

	$tabPanel = New-Object System.Windows.Controls.StackPanel
	$tabPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
	$tabScroll.Content = $tabPanel

	$contentHost = New-Object System.Windows.Controls.Grid
	$contentHost.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
	[System.Windows.Controls.Grid]::SetRow($contentHost, 2)
	[void]$root.Children.Add($contentHost)

	$groups = @(Get-GuiDeploymentMediaUnattendOptionGroups)
	$appsGroup = @($groups | Where-Object { [string]$_.Name -eq 'Edge and apps' } | Select-Object -First 1)
	$bloatwareGroup = @($groups | Where-Object { [string]$_.Name -eq 'Bloatwares' } | Select-Object -First 1)
	if ($appsGroup.Count -gt 0 -and $bloatwareGroup.Count -gt 0)
	{
		$appsGroup[0]['Options'] = @($appsGroup[0].Options) + @($bloatwareGroup[0].Options)
		$appsGroup[0]['Description'] = 'Edge, Windows features, app suggestions, VM guest tools, and built-in app removals.'
		$groups = @($groups | Where-Object { [string]$_.Name -ne 'Bloatwares' })
	}
	$controls = @{}
	$optionLookup = @{}
	$pages = @{}
	$tabItems = @{}
	$initialPageKey = ''
	$bloatwareSearchBox = $null
	$bloatwareRecommendedButton = $null
	$bloatwareSelectAllButton = $null
	$bloatwareClearButton = $null

	foreach ($group in $groups)
	{
		$groupKey = [string]$group.Name
		$groupLabel = if ($group.ContainsKey('DisplayName')) { [string]$group.DisplayName } else { $groupKey }
		$groupIconName = if ($group.ContainsKey('IconName')) { [string]$group.IconName } else { '' }
		$tabItem = New-GuiUnattendTabStripItem -Key $groupKey -Label $groupLabel -IconName $groupIconName -Theme $theme -BrushConverter $bc
		$tabItems[$groupKey] = $tabItem
		[void]$tabPanel.Children.Add($tabItem.Border)
		if ([string]::IsNullOrWhiteSpace($initialPageKey)) { $initialPageKey = $groupKey }

		$scroll = New-Object System.Windows.Controls.ScrollViewer
		$scroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
		$scroll.Visibility = [System.Windows.Visibility]::Collapsed
		$pageStack = New-Object System.Windows.Controls.StackPanel
		$pageStack.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
		$pageDescriptionText = if ($group.ContainsKey('Description')) { [string]$group.Description } else { '' }
		[void]$pageStack.Children.Add((New-GuiSectionHeader -Title $groupLabel -Description $pageDescriptionText -Theme $theme -BrushConverter $bc))

		$hasBloatwarePreview = (@($group.Options) | Where-Object { [string]$_.Key -eq 'Bloatwares' }).Count -gt 0
		if ($hasBloatwarePreview)
		{
			$bloatwareTools = New-Object System.Windows.Controls.WrapPanel
			$bloatwareTools.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
			$bloatwareSearchBox = New-Object System.Windows.Controls.TextBox
			$bloatwareSearchBox.MinWidth = 220
			$bloatwareSearchBox.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
			$bloatwareSearchBox.ToolTip = 'Search built-in app names.'
			$bloatwareSearchBox.Text = ''
			[void]$bloatwareTools.Children.Add($bloatwareSearchBox)
			$bloatwareRecommendedButton = New-PresetButton -Label 'Select recommended' -Variant 'Secondary' -Compact
			$bloatwareRecommendedButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
			$bloatwareSelectAllButton = New-PresetButton -Label 'Select all' -Variant 'Subtle' -Compact
			$bloatwareSelectAllButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
			$bloatwareClearButton = New-PresetButton -Label 'Clear all' -Variant 'Subtle' -Compact
			$bloatwareClearButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
			foreach ($toolButton in @($bloatwareRecommendedButton, $bloatwareSelectAllButton, $bloatwareClearButton)) { [void]$bloatwareTools.Children.Add($toolButton) }
			[void]$pageStack.Children.Add($bloatwareTools)
		}

		$sectionCards = @{}
		foreach ($option in @($group.Options))
		{
			$key = [string]$option.Key
			$optionLookup[$key] = $option
			$section = if ($option.ContainsKey('Section')) { [string]$option.Section } else { $groupLabel }
			if (-not $sectionCards.ContainsKey($section))
			{
				$card = New-GuiSettingCard -Title $section -Theme $theme -BrushConverter $bc
				$sectionCards[$section] = $card
				[void]$pageStack.Children.Add($card.Border)
			}
			$control = New-GuiDeploymentMediaUnattendOptionControl -Option $option
			$row = New-GuiSettingRow -Option $option -Control $control -Theme $theme -BrushConverter $bc
			[void]$sectionCards[$section].Content.Children.Add($row)
			$controls[$key] = @{ Kind = [string]$option.Kind; Control = $control; Option = $option; Row = $row; GroupKey = $groupKey }
		}

		$scroll.Content = $pageStack
		$pages[$groupKey] = $scroll
		[void]$contentHost.Children.Add($scroll)
	}

	$reviewTabItem = New-GuiUnattendTabStripItem -Key 'Review' -Label 'Review XML' -IconName 'PreviewRun' -Theme $theme -BrushConverter $bc
	$tabItems['Review'] = $reviewTabItem
	[void]$tabPanel.Children.Add($reviewTabItem.Border)

	$reviewScroll = New-Object System.Windows.Controls.ScrollViewer
	$reviewScroll.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
	$reviewScroll.Visibility = [System.Windows.Visibility]::Collapsed
	$reviewStack = New-Object System.Windows.Controls.StackPanel
	$reviewStack.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	[void]$reviewStack.Children.Add((New-GuiSectionHeader -Title 'Review XML' -Description 'Generated summary and validation for the selected answer-file options.' -Theme $theme -BrushConverter $bc))
	$summaryCard = New-GuiSettingCard -Title 'Generated summary' -Theme $theme -BrushConverter $bc
	$summaryText = New-Object System.Windows.Controls.TextBlock
	$summaryText.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
	$summaryText.FontSize = 12
	$summaryText.TextWrapping = [System.Windows.TextWrapping]::Wrap
	$summaryText.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'TextPrimary' -Default '#F3F6FB'
	[void]$summaryCard.Content.Children.Add($summaryText)
	[void]$reviewStack.Children.Add($summaryCard.Border)
	$validationCard = New-GuiSettingCard -Title 'Validation' -Theme $theme -BrushConverter $bc
	$validationText = New-Object System.Windows.Controls.TextBlock
	$validationText.FontSize = 12
	$validationText.TextWrapping = [System.Windows.TextWrapping]::Wrap
	$validationText.Foreground = ConvertTo-GuiDeploymentMediaUnattendBrush -Theme $theme -BrushConverter $bc -Name 'CautionText' -Default '#F59E0B'
	[void]$validationCard.Content.Children.Add($validationText)
	[void]$reviewStack.Children.Add($validationCard.Border)
	$reviewScroll.Content = $reviewStack
	$pages['Review'] = $reviewScroll
	[void]$contentHost.Children.Add($reviewScroll)

	$footer = New-Object System.Windows.Controls.StackPanel
	$footer.Orientation = [System.Windows.Controls.Orientation]::Horizontal
	$footer.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
	[System.Windows.Controls.Grid]::SetRow($footer, 3)
	[void]$root.Children.Add($footer)

	$useXmlButton = New-PresetButton -Label 'Import existing XML' -Variant 'Secondary' -Compact
	$useXmlButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$previewButton = New-PresetButton -Label 'Preview' -Variant 'Secondary' -Compact
	$previewButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$saveButton = New-PresetButton -Label 'Generate XML' -Variant 'Primary'
	$saveButton.Padding = [System.Windows.Thickness]::new(18, 7, 18, 7)
	$saveButton.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
	$closeButton = New-PresetButton -Label 'Close' -Variant 'Subtle' -Compact
	if (Get-Command -Name 'Set-GuiButtonIconContent' -CommandType Function -ErrorAction SilentlyContinue)
	{
		Set-GuiButtonIconContent -Button $useXmlButton -IconName 'Document' -Text 'Import existing XML' -ToolTip 'Select an existing autounattend.xml file.' -IconSize 14 -Gap 6 -TextFontSize 11
		Set-GuiButtonIconContent -Button $previewButton -IconName 'PreviewRun' -Text 'Preview' -ToolTip 'Review the generated summary and validation.' -IconSize 14 -Gap 6 -TextFontSize 11
		Set-GuiButtonIconContent -Button $saveButton -IconName 'Document' -Text 'Generate XML' -ToolTip 'Generate and save autounattend.xml from the selected options.' -IconSize 14 -Gap 6 -TextFontSize 12
		Set-GuiButtonIconContent -Button $closeButton -IconName 'Clear' -Text 'Close' -ToolTip 'Close the generator.' -IconSize 14 -Gap 6 -TextFontSize 11
	}
	foreach ($button in @($useXmlButton, $previewButton, $saveButton, $closeButton)) { [void]$footer.Children.Add($button) }

	$applyBloatwareSearchScript = {
		if (-not $bloatwareSearchBox) { return }
		$query = ([string]$bloatwareSearchBox.Text).Trim().ToLowerInvariant()
		foreach ($key in @($controls.Keys))
		{
			if ($key -notlike 'Remove*') { continue }
			$entry = $controls[$key]
			$haystack = ('{0} {1}' -f [string]$entry.Option.Label, [string]$entry.Option.Section).ToLowerInvariant()
			$entry.Row.Visibility = if ([string]::IsNullOrWhiteSpace($query) -or $haystack.Contains($query)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
	}.GetNewClosure()

	$updateReviewPanelScript = ${function:Update-GuiDeploymentMediaUnattendReviewPanel}
	$setChoiceDisplayModeScript = ${function:Set-GuiDeploymentMediaUnattendChoiceDisplayMode}
	$updateDependenciesScript = ${function:Update-GuiUnattendControlDependencies}
	$updateBloatwarePreviewScript = ${function:Update-GuiDeploymentMediaBloatwarePreview}
	$applyPresetScript = ${function:Apply-GuiDeploymentMediaUnattendPreset}
	$testStateScript = ${function:Test-GuiDeploymentMediaUnattendGeneratorState}
	$refreshReviewScript = {
		& $updateReviewPanelScript -Controls $controls -OptionLookup $optionLookup -SummaryText $summaryText -ValidationText $validationText
	}.GetNewClosure()

	$tabState = @{ SelectedKey = '' }
	$updateTabVisualsScript = ${function:Update-GuiDeploymentMediaUnattendTabVisuals}
	$refreshGeneratorStateScript = {
		$showAdvanced = [bool]$advancedModeCheckBox.IsChecked
		& $setChoiceDisplayModeScript -Controls $controls -ShowAdvanced:$showAdvanced
		& $updateDependenciesScript -Controls $controls -ShowAdvanced:$showAdvanced
		& $updateBloatwarePreviewScript -Controls $controls
		& $applyBloatwareSearchScript
		if ([string]$tabState.SelectedKey -eq 'Review')
		{
			[void](& $refreshReviewScript)
		}
	}.GetNewClosure()

	$selectPageScript = {
		param ([string]$Key)

		if ([string]::IsNullOrWhiteSpace($Key)) { return }
		$tabState.SelectedKey = $Key
		foreach ($pageKey in @($pages.Keys))
		{
			$pages[$pageKey].Visibility = if ($pageKey -eq $tabState.SelectedKey) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
		}
		& $updateTabVisualsScript -TabItems $tabItems -SelectedKey $tabState.SelectedKey -Theme $theme -BrushConverter $bc
		if ([string]$tabState.SelectedKey -eq 'Review') { [void](& $refreshReviewScript) }
	}.GetNewClosure()

	$selectReviewPageScript = {
		& $selectPageScript -Key 'Review'
	}.GetNewClosure()

	foreach ($tabItemEntry in @($tabItems.Values))
	{
		$tabKey = [string]$tabItemEntry.Key
		Register-GuiEventHandler -Source $tabItemEntry.Border -EventName 'MouseLeftButtonUp' -Handler ({ & $selectPageScript -Key $tabKey }.GetNewClosure()) | Out-Null
	}
	Register-GuiEventHandler -Source $advancedModeCheckBox -EventName 'Checked' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
	Register-GuiEventHandler -Source $advancedModeCheckBox -EventName 'Unchecked' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
	Register-GuiEventHandler -Source $presetCombo -EventName 'SelectionChanged' -Handler ({
		if ($presetCombo.SelectedValue)
		{
			& $applyPresetScript -Preset ([string]$presetCombo.SelectedValue) -Controls $controls
			& $refreshGeneratorStateScript
		}
	}.GetNewClosure()) | Out-Null

	foreach ($entry in @($controls.Values))
	{
		switch ([string]$entry.Kind)
		{
			'Bool'
			{
				Register-GuiEventHandler -Source $entry.Control -EventName 'Checked' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
				Register-GuiEventHandler -Source $entry.Control -EventName 'Unchecked' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
			}
			'Choice'
			{
				Register-GuiEventHandler -Source $entry.Control -EventName 'SelectionChanged' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
			}
			'Password'
			{
				Register-GuiEventHandler -Source $entry.Control -EventName 'PasswordChanged' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
			}
			'GeneratedPreview' { }
			default
			{
				Register-GuiEventHandler -Source $entry.Control -EventName 'TextChanged' -Handler ({ & $refreshGeneratorStateScript }.GetNewClosure()) | Out-Null
			}
		}
	}

	if ($bloatwareSearchBox)
	{
		Register-GuiEventHandler -Source $bloatwareSearchBox -EventName 'TextChanged' -Handler ({ & $applyBloatwareSearchScript }.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $bloatwareRecommendedButton -EventName 'Click' -Handler ({
			foreach ($key in @($controls.Keys))
			{
				if ($key -like 'Remove*') { $controls[$key].Control.IsChecked = [bool]$controls[$key].Option.Recommended }
			}
			& $refreshGeneratorStateScript
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $bloatwareSelectAllButton -EventName 'Click' -Handler ({
			foreach ($key in @($controls.Keys)) { if ($key -like 'Remove*') { $controls[$key].Control.IsChecked = $true } }
			& $refreshGeneratorStateScript
		}.GetNewClosure()) | Out-Null
		Register-GuiEventHandler -Source $bloatwareClearButton -EventName 'Click' -Handler ({
			foreach ($key in @($controls.Keys)) { if ($key -like 'Remove*') { $controls[$key].Control.IsChecked = $false } }
			& $refreshGeneratorStateScript
		}.GetNewClosure()) | Out-Null
	}

	$initialShowAdvanced = [bool]$advancedModeCheckBox.IsChecked
	& $setChoiceDisplayModeScript -Controls $controls -ShowAdvanced:$initialShowAdvanced
	& $updateDependenciesScript -Controls $controls -ShowAdvanced:$initialShowAdvanced
	& $updateBloatwarePreviewScript -Controls $controls
	[void](& $refreshReviewScript)
	if (-not [string]::IsNullOrWhiteSpace($initialPageKey)) { & $selectPageScript -Key $initialPageKey }

	$saveDialogScript = ${function:Show-GuiDeploymentMediaUnattendSaveDialog}
	$getStateScript = ${function:Get-GuiDeploymentMediaUnattendGeneratorState}
	$saveXmlScript = ${function:Save-GuiDeploymentMediaUnattendXml}
	$fileDialogScript = ${function:Show-GuiDeploymentMediaBuilderFileDialog}
	Register-GuiEventHandler -Source $useXmlButton -EventName 'Click' -Handler ({
		$path = & $fileDialogScript -Filter 'Answer files (*.xml)|*.xml'
		if ($path -and $TargetTextBox)
		{
			$TargetTextBox.Text = $path
			$window.Close()
		}
	}.GetNewClosure()) | Out-Null
	Register-GuiEventHandler -Source $previewButton -EventName 'Click' -Handler ({
		[void](& $refreshReviewScript)
		& $selectReviewPageScript
	}.GetNewClosure()) | Out-Null
	Register-GuiEventHandler -Source $saveButton -EventName 'Click' -Handler ({
		try
		{
			$state = & $getStateScript -Controls $controls
			$validation = & $testStateScript -State $state
			if (-not $validation.IsValid)
			{
				[void](& $refreshReviewScript)
				& $selectReviewPageScript
				[void](Show-ThemedDialog -Title 'Generate autounattend.xml' -Message ("Fix validation errors before generating XML.`n`n{0}" -f (@($validation.Errors) -join "`n")) -Buttons @('OK') -AccentButton 'OK')
				return
			}
			$path = & $saveDialogScript
			if (-not $path) { return }
			& $saveXmlScript -State $state -Path $path
			if ($TargetTextBox) { $TargetTextBox.Text = $path }
			$window.Close()
		}
		catch
		{
			Write-GuiDeploymentMediaBuilderErrorLog -ErrorRecord $_ -Prefix 'Offline autounattend.xml generation failed' -Source 'DeploymentMediaBuilderView.UnattendGenerator.LogError'
			[void](Show-ThemedDialog -Title 'Create autounattend.xml' -Message ("autounattend.xml generation failed.`n`n{0}" -f $_.Exception.Message) -Buttons @('OK') -AccentButton 'OK')
		}
	}.GetNewClosure()) | Out-Null
	Register-GuiEventHandler -Source $closeButton -EventName 'Click' -Handler ({ $window.Close() }.GetNewClosure()) | Out-Null

	if ($roundedWindow)
	{
		[void](GUICommon\Complete-RoundedWindow -Window $window -ContentElement $root -RoundBorder $roundedWindow.RoundBorder -DockPanel $roundedWindow.DockPanel)
	}
	else
	{
		$window.Content = $root
	}
	[void]$window.ShowDialog()
}

