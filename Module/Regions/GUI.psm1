using module ..\Logging.psm1
using module ..\Helpers.psm1

<#
	.SYNOPSIS
	WPF-based GUI that replaces the preset file (Win10_11Util.ps1).

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

#region Tweak Manifest
$Script:TweakManifest = @(

	# ── Initial Setup ────────────────────────────────────────────────
	@{ Name = "Check and Install WinGet";                  Category = "Initial Setup";       Function = "CheckWinGet";                     Type = "Action"; Default = $true;  WinDefault = $true;  Description = "Ensure WinGet package manager is installed"; Caution = $false; Scannable = $false }
	@{ Name = "Install/Update PowerShell 7";               Category = "Initial Setup";       Function = "Update-Powershell";               Type = "Action"; Default = $true;  WinDefault = $false; Description = "Install the latest PowerShell 7 release"; Caution = $false; LinkedWith = "Powershell7Telemetry"; Scannable = $false }
	@{ Name = "Lanman Workstation Guest Auth Policy";      Category = "Initial Setup";       Function = "LanmanWorkstationGuestAuthPolicy"; Type = "Action"; Default = $true;  WinDefault = $false; Description = "Enable the LanmanWorkstation guest-auth Group Policy setting"; Caution = $false }
	@{ Name = "Hide About this Picture on Desktop";        Category = "Initial Setup";       Function = "Update-DesktopRegistry";          Type = "Action"; Default = $true;  WinDefault = $false; Description = "Remove the Spotlight 'About this picture' icon from the desktop"; Caution = $false }

	# ── OS Hardening ─────────────────────────────────────────────────
	@{ Name = "Block Remote Commands";                     Category = "OS Hardening";        Function = "Disable-RemoteCommands";          Type = "Action"; Default = $true;  WinDefault = $false; Description = "Block remote command execution"; Caution = $false }
	@{ Name = "Prevent Wireless Exploitation";             Category = "OS Hardening";        Function = "Suspend-AirstrikeAttack";         Type = "Action"; Default = $true;  WinDefault = $false; Description = "Prevent local Windows wireless exploitation"; Caution = $false }
	@{ Name = "Disable SMBv3 Compression";                 Category = "OS Hardening";        Function = "Disable-SMBv3Compression";        Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable SMBv3 compression to mitigate CVE-2020-0796"; Caution = $false }
	@{ Name = "Harden MS Office";                          Category = "OS Hardening";        Function = "Protect-MSOffice";                Type = "Action"; Default = $false; WinDefault = $false; Description = "Harden MS Office security settings"; Caution = $true; CautionReason = "Can affect macros, Office automation, downloaded Office documents, and workflows that rely on active content or permissive Outlook trust behavior." }
	@{ Name = "General OS Hardening";                      Category = "OS Hardening";        Function = "Protect-OS";                      Type = "Action"; Default = $false; WinDefault = $false; Description = "Perform general OS hardening"; Caution = $true; CautionReason = "Changes authentication, networking, shell, and smart card related policy values. Review carefully in environments with legacy authentication, specialized networking, or smart-card workflows." }
	@{ Name = "Prevent Remote DLL Hijacking";              Category = "OS Hardening";        Function = "Set-DLLHijackingPrevention";      Type = "Action"; Default = $true;  WinDefault = $false; Description = "Prevent remote DLL hijacking"; Caution = $false }
	@{ Name = "Disable IPv6";                              Category = "OS Hardening";        Function = "Disable-IPv6";                    Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable IPv6 protocol"; Caution = $false }
	@{ Name = "Disable TCP Timestamps";                    Category = "OS Hardening";        Function = "Disable-TCPTimestamps";           Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable TCP timestamps to reduce network fingerprinting"; Caution = $false }
	@{ Name = "Enable Biometrics Anti-Spoofing";           Category = "OS Hardening";        Function = "Enable-BiometricsAntiSpoofing";   Type = "Action"; Default = $true;  WinDefault = $false; Description = "Enable biometrics anti-spoofing protection"; Caution = $false }
	@{ Name = "Ensure Registry Paths Exist";               Category = "OS Hardening";        Function = "Update-RegistryPaths";            Type = "Action"; Default = $true;  WinDefault = $false; Description = "Create required registry paths before setting properties"; Caution = $false }
	@{ Name = "Disable AutoRun";                           Category = "OS Hardening";        Function = "Disable-AutoRun";                 Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable AutoRun for all media"; Caution = $false }
	@{ Name = "Disable AES Ciphers";                       Category = "OS Hardening";        Function = "Disable-AESCiphers";              Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable weak AES ciphers"; Caution = $false }
	@{ Name = "Disable RC2 and RC4 Ciphers";               Category = "OS Hardening";        Function = "Disable-RC2RC4Ciphers";           Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable RC2 and RC4 ciphers"; Caution = $false }
	@{ Name = "Disable Triple DES Cipher";                 Category = "OS Hardening";        Function = "Disable-TripleDESCipher";         Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable Triple DES cipher"; Caution = $false }
	@{ Name = "Disable Weak Hash Algorithms";              Category = "OS Hardening";        Function = "Disable-HashAlgorithms";          Type = "Action"; Default = $true;  WinDefault = $false; Description = "Disable specified weak hash algorithms"; Caution = $false }
	@{ Name = "Configure Key Exchange Algorithms";         Category = "OS Hardening";        Function = "Update-KeyExchanges";             Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure secure key exchange algorithms"; Caution = $false }
	@{ Name = "Configure SSL/TLS Protocols";               Category = "OS Hardening";        Function = "Update-Protocols";                Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure secure SSL/TLS protocols"; Caution = $false }
	@{ Name = "Configure Cipher Suites";                   Category = "OS Hardening";        Function = "Update-CipherSuites";             Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure secure cipher suites"; Caution = $false }
	@{ Name = "Configure Strong .NET Authentication";      Category = "OS Hardening";        Function = "Update-DotNetStrongAuth";         Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure strong .NET authentication"; Caution = $false }
	@{ Name = "Configure Event Log Sizes";                 Category = "OS Hardening";        Function = "Update-EventLogSize";             Type = "Action"; Default = $true;  WinDefault = $false; Description = "Increase event log sizes for better auditing"; Caution = $false }
	@{ Name = "Harden Adobe Reader";                       Category = "OS Hardening";        Function = "Update-AdobereaderDCSTIG";        Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure Adobe Reader security settings"; Caution = $true; CautionReason = "Can affect Adobe update behavior, cloud/share integrations, and document handling features that depend on less restrictive Reader settings." }
	@{ Name = "Harden Office Links";                       Category = "OS Hardening";        Function = "Protect-MSOfficeLinks";           Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure Office link update hardening"; Caution = $true; CautionReason = "Can affect documents or mail workflows that intentionally rely on automatic external link refresh behavior." }
	@{ Name = "Harden WinRM";                              Category = "OS Hardening";        Function = "Protect-WinRM";                   Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure WinRM hardening"; Caution = $false }
	@{ Name = "Reduce RPC Surface";                        Category = "OS Hardening";        Function = "Protect-RPCSurface";              Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure RPC surface reduction"; Caution = $true; CautionReason = "Can break remote task scheduling, remote service control, and management products that depend on those RPC paths." }
	@{ Name = "Harden ClickOnce Trust Prompts";            Category = "OS Hardening";        Function = "Protect-ClickOnce";               Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure ClickOnce trust prompt hardening"; Caution = $true; CautionReason = "Aggressive. Can break ClickOnce-based installers, updates, or internal applications that depend on trust prompts." }
	@{ Name = "Filesystem Performance Settings";           Category = "OS Hardening";        Function = "Protect-FileSystemPerformance";   Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure filesystem performance settings"; Caution = $false }

	# ── Privacy & Telemetry ──────────────────────────────────────────
	@{ Name = "Connected User Experiences (DiagTrack)";    Category = "Privacy & Telemetry"; Function = "DiagTrackService";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Connected User Experiences and Telemetry service"; Caution = $false; Detect = { (Get-Service DiagTrack -EA SilentlyContinue).StartType -ne "Disabled" } }
	@{ Name = "Diagnostic Data Level";                     Category = "Privacy & Telemetry"; Function = "DiagnosticDataLevel";             Type = "Choice"; Options = @("Minimal","Default"); Default = "Minimal"; WinDefault = "Default"; Description = "Set diagnostic data collection level"; Caution = $false }
	@{ Name = "Windows Error Reporting";                   Category = "Privacy & Telemetry"; Function = "ErrorReporting";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows Error Reporting"; Caution = $false }
	@{ Name = "Feedback Frequency";                        Category = "Privacy & Telemetry"; Function = "FeedbackFrequency";               Type = "Choice"; Options = @("Never","Automatically"); Default = "Never"; WinDefault = "Automatically"; Description = "How often Windows asks for feedback"; Caution = $false }
	@{ Name = "Diagnostics Tracking Tasks";                Category = "Privacy & Telemetry"; Function = "ScheduledTasks";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Diagnostics tracking scheduled tasks"; Caution = $false }
	@{ Name = "Malicious Software Removal Tool (MSRT)";   Category = "Privacy & Telemetry"; Function = "UpdateMSRT";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Offering of MSRT through Windows Update"; Caution = $false }
	@{ Name = "Driver Updates via Windows Update";         Category = "Privacy & Telemetry"; Function = "UpdateDriver";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Offering of drivers through Windows Update"; Caution = $false }
	@{ Name = "Microsoft Product Updates";                 Category = "Privacy & Telemetry"; Function = "UpdateMSProducts";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Receive updates for other Microsoft products via Windows Update"; Caution = $false }
	@{ Name = "Windows Update Auto Downloads";             Category = "Privacy & Telemetry"; Function = "UpdateAutoDownload";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows Update automatic downloads"; Caution = $false }
	@{ Name = "Auto Restart After Update";                 Category = "Privacy & Telemetry"; Function = "UpdateRestart";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Automatic restart after Windows Update"; Caution = $false }
	@{ Name = "Maintenance Wake-up";                       Category = "Privacy & Telemetry"; Function = "MaintenanceWakeUp";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Nightly wake-up for Automatic Maintenance"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" -Name MaintenanceDisabled -EA SilentlyContinue).MaintenanceDisabled -ne 1 } }
	@{ Name = "Shared Experiences";                        Category = "Privacy & Telemetry"; Function = "SharedExperiences";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Shared Experiences across devices"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP" -Name RomeSdkChannelUserAuthzPolicy -EA SilentlyContinue).RomeSdkChannelUserAuthzPolicy -eq 1 } }
	@{ Name = "Clipboard History";                         Category = "Privacy & Telemetry"; Function = "ClipboardHistory";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Clipboard History"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Clipboard" -Name EnableClipboardHistory -EA SilentlyContinue).EnableClipboardHistory -eq 1 } }
	@{ Name = "Superfetch Service";                        Category = "Privacy & Telemetry"; Function = "Superfetch";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Superfetch (SysMain) service"; Caution = $false; Detect = { (Get-Service SysMain -EA SilentlyContinue).StartType -ne "Disabled" } }
	@{ Name = "NTFS Long Paths";                           Category = "Privacy & Telemetry"; Function = "NTFSLongPaths";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "NTFS paths with length over 260 characters"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -EA SilentlyContinue).LongPathsEnabled -eq 1 } }
	@{ Name = "NTFS Last Access Timestamps";               Category = "Privacy & Telemetry"; Function = "NTFSLastAccess";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Updating of NTFS last access timestamps"; Caution = $false }
	@{ Name = "Sleep Button";                              Category = "Privacy & Telemetry"; Function = "SleepButton";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Sleep start menu and keyboard button"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name ShowSleepOption -EA SilentlyContinue).ShowSleepOption -eq 1 } }
	@{ Name = "Display and Sleep Timeouts";                Category = "Privacy & Telemetry"; Function = "SleepTimeout";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Display and sleep mode timeouts"; Caution = $false }
	@{ Name = "Fast Startup";                              Category = "Privacy & Telemetry"; Function = "FastStartup";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows Fast Startup"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -EA SilentlyContinue).HiberbootEnabled -eq 1 } }
	@{ Name = "Auto Reboot on Crash (BSOD)";              Category = "Privacy & Telemetry"; Function = "AutoRebootOnCrash";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Automatic reboot on crash"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name AutoReboot -EA SilentlyContinue).AutoReboot -eq 1 } }
	@{ Name = "Sign-in Info After Update";                 Category = "Privacy & Telemetry"; Function = "SigninInfo";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Use sign-in info to finish setting up after update"; Caution = $false; Detect = { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\$sid" -Name OptOut -EA SilentlyContinue).OptOut -ne 1 } }
	@{ Name = "Language List Access for Websites";         Category = "Privacy & Telemetry"; Function = "LanguageListAccess";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Let websites access language list"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\International\User Profile" -Name HttpAcceptLanguageOptOut -EA SilentlyContinue).HttpAcceptLanguageOptOut -ne 1 } }
	@{ Name = "Advertising ID";                            Category = "Privacy & Telemetry"; Function = "AdvertisingID";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Personalized ads using advertising ID"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name Enabled -EA SilentlyContinue).Enabled -eq 1 } }
	@{ Name = "Windows Welcome Experience";                Category = "Privacy & Telemetry"; Function = "WindowsWelcomeExperience";        Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Windows welcome experiences after updates"; Caution = $false }
	@{ Name = "Lock Screen Widgets";                       Category = "Privacy & Telemetry"; Function = "LockWidgets";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows Web Experience Pack (widgets and lock screen)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarDa -EA SilentlyContinue).TaskbarDa -ne 0 } }
	@{ Name = "Windows Tips";                              Category = "Privacy & Telemetry"; Function = "WindowsTips";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Tips and suggestions when using Windows"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name SoftLandingEnabled -EA SilentlyContinue).SoftLandingEnabled -ne 0 } }
	@{ Name = "Settings Suggested Content";                Category = "Privacy & Telemetry"; Function = "SettingsSuggestedContent";        Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Suggested content in Settings app"; Caution = $false }
	@{ Name = "Silent App Installing";                     Category = "Privacy & Telemetry"; Function = "AppsSilentInstalling";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Automatic installing of suggested apps"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name SilentInstalledAppsEnabled -EA SilentlyContinue).SilentInstalledAppsEnabled -ne 0 } }
	@{ Name = "What's New in Windows";                     Category = "Privacy & Telemetry"; Function = "WhatsNewInWindows";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Suggestions to get the most out of Windows"; Caution = $false }
	@{ Name = "Tailored Experiences";                      Category = "Privacy & Telemetry"; Function = "TailoredExperiences";             Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Microsoft diagnostic data for personalized tips"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name TailoredExperiencesWithDiagnosticDataEnabled -EA SilentlyContinue).TailoredExperiencesWithDiagnosticDataEnabled -ne 0 } }
	@{ Name = "Bing Search in Start Menu";                 Category = "Privacy & Telemetry"; Function = "BingSearch";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Bing search results in Start Menu"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name BingSearchEnabled -EA SilentlyContinue).BingSearchEnabled -ne 0 } }
	@{ Name = "Start Menu Recommendations/Tips";           Category = "Privacy & Telemetry"; Function = "StartRecommendationsTips";        Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Recommendations for tips, shortcuts, new apps in Start"; Caution = $false }
	@{ Name = "Start Menu Account Notifications";          Category = "Privacy & Telemetry"; Function = "StartAccountNotifications";       Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Microsoft account notifications on Start Menu"; Caution = $false }
	@{ Name = "WiFi Sense";                                Category = "Privacy & Telemetry"; Function = "WiFiSense";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "WiFi Sense hotspot sharing"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name Value -EA SilentlyContinue).Value -ne 0 } }
	@{ Name = "Web Search in System Search";               Category = "Privacy & Telemetry"; Function = "WebSearch";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Web search integration in system search"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name CortanaConsent -EA SilentlyContinue).CortanaConsent -ne 0 } }
	@{ Name = "Activity History";                          Category = "Privacy & Telemetry"; Function = "ActivityHistory";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Activity history tracking across devices"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableActivityFeed -EA SilentlyContinue).EnableActivityFeed -ne 0 } }
	@{ Name = "Device Sensors";                            Category = "Privacy & Telemetry"; Function = "Sensors";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Accelerometer, gyroscope, and ambient light sensor"; Caution = $false }
	@{ Name = "Location Services";                         Category = "Privacy & Telemetry"; Function = "LocationService";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Device location access for apps"; Caution = $false }
	@{ Name = "Automatic Map Updates";                     Category = "Privacy & Telemetry"; Function = "MapUpdates";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Automatic updates for offline maps"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\Maps" -Name AutoUpdateEnabled -EA SilentlyContinue).AutoUpdateEnabled -eq 1 } }
	@{ Name = "Web Language Sync";                         Category = "Privacy & Telemetry"; Function = "WebLangList";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Synchronization of preferred web languages"; Caution = $false }
	@{ Name = "Camera Access";                             Category = "Privacy & Telemetry"; Function = "Camera";                          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Camera access for apps"; Caution = $false }
	@{ Name = "Microphone Access";                         Category = "Privacy & Telemetry"; Function = "Microphone";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Microphone access for apps"; Caution = $false }
	@{ Name = "WAP Push Messaging";                        Category = "Privacy & Telemetry"; Function = "WAPPush";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "WAP Push messaging from carriers"; Caution = $false; Detect = { (Get-Service dmwappushservice -EA SilentlyContinue).StartType -ne "Disabled" } }
	@{ Name = "Clear Recent Files on Logout";              Category = "Privacy & Telemetry"; Function = "ClearRecentFiles";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Automatic clearing of recent files on logout"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ClearRecentDocsOnExit -EA SilentlyContinue).ClearRecentDocsOnExit -eq 1 } }
	@{ Name = "Recent Files Tracking";                     Category = "Privacy & Telemetry"; Function = "RecentFiles";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Tracking of recently accessed files"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoRecentDocsHistory -EA SilentlyContinue).NoRecentDocsHistory -ne 1 } }
	@{ Name = "UWP Voice Activation";                      Category = "Privacy & Telemetry"; Function = "UWPVoiceActivation";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Voice activation access from UWP apps"; Caution = $false }
	@{ Name = "UWP Notifications";                         Category = "Privacy & Telemetry"; Function = "UWPNotifications";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Notification access from UWP apps"; Caution = $false }
	@{ Name = "UWP Account Info";                          Category = "Privacy & Telemetry"; Function = "UWPAccountInfo";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Account info access from UWP apps"; Caution = $false }
	@{ Name = "UWP Contacts";                              Category = "Privacy & Telemetry"; Function = "UWPContacts";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Contacts access from UWP apps"; Caution = $false }
	@{ Name = "UWP Calendar";                              Category = "Privacy & Telemetry"; Function = "UWPCalendar";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Calendar access from UWP apps"; Caution = $false }
	@{ Name = "UWP Phone Calls";                           Category = "Privacy & Telemetry"; Function = "UWPPhoneCalls";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Phone call access from UWP apps"; Caution = $false }
	@{ Name = "UWP Call History";                           Category = "Privacy & Telemetry"; Function = "UWPCallHistory";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Call history access from UWP apps"; Caution = $false }
	@{ Name = "UWP Email";                                 Category = "Privacy & Telemetry"; Function = "UWPEmail";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Email access from UWP apps"; Caution = $false }
	@{ Name = "UWP Tasks";                                 Category = "Privacy & Telemetry"; Function = "UWPTasks";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Tasks access from UWP apps"; Caution = $false }
	@{ Name = "UWP Messaging";                             Category = "Privacy & Telemetry"; Function = "UWPMessaging";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Messaging access from UWP apps"; Caution = $false }
	@{ Name = "UWP Radios (Bluetooth)";                    Category = "Privacy & Telemetry"; Function = "UWPRadios";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Radios (Bluetooth) access from UWP apps"; Caution = $false }
	@{ Name = "UWP Other Devices";                         Category = "Privacy & Telemetry"; Function = "UWPOtherDevices";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Other devices access from UWP apps"; Caution = $false }
	@{ Name = "UWP Diagnostic Info";                       Category = "Privacy & Telemetry"; Function = "UWPDiagInfo";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Diagnostic info access from UWP apps"; Caution = $false }
	@{ Name = "UWP File System";                           Category = "Privacy & Telemetry"; Function = "UWPFileSystem";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "File system access from UWP apps"; Caution = $false }
	@{ Name = "UWP Swap File";                             Category = "Privacy & Telemetry"; Function = "UWPSwapFile";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "UWP apps swap file (swapfile.sys)"; Caution = $false }
	@{ Name = "PowerShell 7 Telemetry";                    Category = "Privacy & Telemetry"; Function = "Powershell7Telemetry";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "PowerShell 7 telemetry collection"; Caution = $false; LinkedWith = "Update-Powershell" }

	# ── System Tweaks ────────────────────────────────────────────────
	@{ Name = "Cross-Device Resume";                       Category = "System Tweaks";       Function = "CrossDeviceResume";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Cross-Device Resume (24H2+)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name IsResumeAllowed -EA SilentlyContinue).IsResumeAllowed -eq 1 } }
	@{ Name = "Multiplane Overlay";                        Category = "System Tweaks";       Function = "MultiplaneOverlay";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Multiplane Overlay"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name OverlayTestMode -EA SilentlyContinue).OverlayTestMode -ne 5 } }
	@{ Name = "Modern Standby Fix";                        Category = "System Tweaks";       Function = "StandbyFix";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Modern Standby fix"; Caution = $false }
	@{ Name = "S3 Sleep";                                  Category = "System Tweaks";       Function = "S3Sleep";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "S3 Sleep mode"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name PlatformAoAcOverride -EA SilentlyContinue).PlatformAoAcOverride -eq 0 } }
	@{ Name = "Explorer Automatic Folder Discovery";       Category = "System Tweaks";       Function = "ExplorerAutoDiscovery";           Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Explorer automatic folder type discovery"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" -Name FolderType -EA SilentlyContinue).FolderType -ne "NotSpecified" } }
	@{ Name = "Windows Platform Binary Table (WPBT)";     Category = "System Tweaks";       Function = "WPBT";                            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "WPBT ACPI table"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name DisableWpbtExecution -EA SilentlyContinue).DisableWpbtExecution -ne 1 } }
	@{ Name = "Disk Cleanup";                              Category = "System Tweaks";       Function = "DiskCleanup";                     Type = "Action"; Default = $true;  WinDefault = $false; Description = "Run Disk Cleanup"; Caution = $false }
	@{ Name = "Services Manual Startup";                   Category = "System Tweaks";       Function = "ServicesManual";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Apply recommended startup types to Windows services"; Caution = $false }
	@{ Name = "Adobe Network Block";                       Category = "System Tweaks";       Function = "AdobeNetworkBlock";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Block Adobe network access"; Caution = $true; CautionReason = "Blocking Adobe network access may prevent license validation, disable Creative Cloud syncing, break cloud-based features, trigger subscription errors, and may violate Adobe license terms." }
	@{ Name = "Razer Software Block";                      Category = "System Tweaks";       Function = "RazerBlock";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Block Razer software installation"; Caution = $true; CautionReason = "May prevent Razer Synapse from installing/updating, disable RGB/macro/device profile functionality, stop firmware updates, and cause limited peripheral features." }
	@{ Name = "Brave Debloat";                             Category = "System Tweaks";       Function = "BraveDebloat";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Disable Brave rewards, wallet, VPN, AI chat"; Caution = $true; CautionReason = "Disables Brave rewards, wallet, VPN, and AI chat features permanently. Only use if you want to remove those features completely." }
	@{ Name = "Fullscreen Optimizations";                  Category = "System Tweaks";       Function = "FullscreenOptimizations";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Fullscreen Optimizations"; Caution = $true; CautionReason = "Disabling Fullscreen Optimizations may reduce gaming performance in some applications. Use only for troubleshooting."; Detect = { (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_DXGIHonorFSEWindowsCompatible -EA SilentlyContinue).GameDVR_DXGIHonorFSEWindowsCompatible -ne 1 } }
	@{ Name = "Teredo";                                    Category = "System Tweaks";       Function = "Teredo";                          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Teredo IPv6 tunneling protocol"; Caution = $true; CautionReason = "Teredo is an IPv6 tunneling protocol needed for NAT traversal. Disabling it may break Xbox Live and certain peer-to-peer applications."; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name DisabledComponents -EA SilentlyContinue).DisabledComponents -ne 255 } }

	# ── UI & Personalization ─────────────────────────────────────────
	@{ Name = "Explorer Title Full Path";                  Category = "UI & Personalization"; Function = "ExplorerTitleFullPath";           Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Full directory path in Explorer title bar"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name FullPath -EA SilentlyContinue).FullPath -eq 1 } }
	@{ Name = "Nav Pane All Folders";                      Category = "UI & Personalization"; Function = "NavPaneAllFolders";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "All folders in Explorer navigation pane"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneShowAllFolders -EA SilentlyContinue).NavPaneShowAllFolders -eq 1 } }
	@{ Name = "Nav Pane Libraries";                        Category = "UI & Personalization"; Function = "NavPaneLibraries";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Libraries in Explorer navigation pane"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneShowLibraries -EA SilentlyContinue).NavPaneShowLibraries -eq 1 } }
	@{ Name = "Folder Separate Process";                   Category = "UI & Personalization"; Function = "FldrSeparateProcess";             Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Launch folder windows in separate process"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SeparateProcess -EA SilentlyContinue).SeparateProcess -eq 1 } }
	@{ Name = "Restore Folder Windows at Logon";           Category = "UI & Personalization"; Function = "RestoreFldrWindows";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Restore previous folder windows at logon"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name PersistBrowsers -EA SilentlyContinue).PersistBrowsers -eq 1 } }
	@{ Name = "Encrypted/Compressed File Color";           Category = "UI & Personalization"; Function = "EncCompFilesColor";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Coloring of encrypted/compressed NTFS files"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowEncryptCompressedColor -EA SilentlyContinue).ShowEncryptCompressedColor -eq 1 } }
	@{ Name = "Sharing Wizard";                            Category = "UI & Personalization"; Function = "SharingWizard";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Sharing Wizard"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SharingWizardOn -EA SilentlyContinue).SharingWizardOn -ne 0 } }
	@{ Name = "Item Selection Checkboxes";                 Category = "UI & Personalization"; Function = "SelectCheckboxes";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Item selection checkboxes in Explorer"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name AutoCheckSelect -EA SilentlyContinue).AutoCheckSelect -eq 1 } }
	@{ Name = "Sync Provider Notifications";               Category = "UI & Personalization"; Function = "SyncNotifications";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Sync provider notifications"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSyncProviderNotifications -EA SilentlyContinue).ShowSyncProviderNotifications -eq 1 } }
	@{ Name = "Recent Shortcuts in Explorer";              Category = "UI & Personalization"; Function = "RecentShortcuts";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Recently/frequently used item shortcuts"; Caution = $false }
	@{ Name = "Build Number on Desktop";                   Category = "UI & Personalization"; Function = "BuildNumberOnDesktop";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Windows build number on desktop"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name PaintDesktopVersion -EA SilentlyContinue).PaintDesktopVersion -eq 1 } }
	@{ Name = "Share Context Menu";                        Category = "UI & Personalization"; Function = "ShareMenu";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "'Share' context menu item"; Caution = $false }
	@{ Name = "Thumbnails";                                Category = "UI & Personalization"; Function = "Thumbnails";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "File thumbnails (vs extension icons)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name IconsOnly -EA SilentlyContinue).IconsOnly -ne 1 } }
	@{ Name = "Thumbnail Cache";                           Category = "UI & Personalization"; Function = "ThumbnailCache";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Thumbnail cache files"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisableThumbnailCache -EA SilentlyContinue).DisableThumbnailCache -ne 1 } }
	@{ Name = "Thumbs.db on Network";                      Category = "UI & Personalization"; Function = "ThumbsDBOnNetwork";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Thumbs.db on network folders"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisableThumbsDBOnNetworkFolders -EA SilentlyContinue).DisableThumbsDBOnNetworkFolders -ne 1 } }
	@{ Name = "This PC on Desktop";                        Category = "UI & Personalization"; Function = "ThisPC";                          Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $false; Description = "'This PC' icon on Desktop"; Caution = $false }
	@{ Name = "Item Check Boxes";                          Category = "UI & Personalization"; Function = "CheckBoxes";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Use item check boxes"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name AutoCheckSelect -EA SilentlyContinue).AutoCheckSelect -eq 1 } }
	@{ Name = "Hidden Files and Folders";                  Category = "UI & Personalization"; Function = "HiddenItems";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Show hidden files, folders, and drives"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -EA SilentlyContinue).Hidden -eq 1 } }
	@{ Name = "Protected OS Files";                        Category = "UI & Personalization"; Function = "SuperHiddenFiles";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Protected operating system files"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSuperHidden -EA SilentlyContinue).ShowSuperHidden -eq 1 } }
	@{ Name = "File Extensions";                           Category = "UI & Personalization"; Function = "FileExtensions";                  Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $false; Description = "File name extensions"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideFileExt -EA SilentlyContinue).HideFileExt -ne 1 } }
	@{ Name = "Folder Merge Conflicts";                    Category = "UI & Personalization"; Function = "MergeConflicts";                  Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $false; Description = "Show folder merge conflicts"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideMergeConflicts -EA SilentlyContinue).HideMergeConflicts -ne 1 } }
	@{ Name = "Open File Explorer To";                     Category = "UI & Personalization"; Function = "OpenFileExplorerTo";              Type = "Choice"; Options = @("ThisPC","QuickAccess","Downloads"); DisplayOptions = @("This PC","Quick Access","Downloads"); Default = "ThisPC"; WinDefault = "QuickAccess"; Description = "Default File Explorer location"; Caution = $false }
	@{ Name = "File Explorer Compact Mode";                Category = "UI & Personalization"; Function = "FileExplorerCompactMode";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "File Explorer compact mode"; Caution = $false }
	@{ Name = "OneDrive File Explorer Ad";                 Category = "UI & Personalization"; Function = "OneDriveFileExplorerAd";          Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Sync provider notification in File Explorer"; Caution = $false }
	@{ Name = "Snap Assist";                               Category = "UI & Personalization"; Function = "SnapAssist";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Show what to snap next to a window"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name SnapAssist -EA SilentlyContinue).SnapAssist -ne 0 } }
	@{ Name = "File Transfer Dialog";                      Category = "UI & Personalization"; Function = "FileTransferDialog";              Type = "Choice"; Options = @("Detailed","Compact"); Default = "Detailed"; WinDefault = "Compact"; Description = "File transfer dialog box mode"; Caution = $false }
	@{ Name = "Recycle Bin Delete Confirmation";           Category = "UI & Personalization"; Function = "RecycleBinDeleteConfirmation";    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Recycle Bin delete confirmation dialog"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ConfirmFileDelete -EA SilentlyContinue).ConfirmFileDelete -eq 1 } }
	@{ Name = "Quick Access Recent Files";                 Category = "UI & Personalization"; Function = "QuickAccessRecentFiles";          Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Recently used files in Quick access"; Caution = $false }
	@{ Name = "Quick Access Frequent Folders";             Category = "UI & Personalization"; Function = "QuickAccessFrequentFolders";      Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Frequently used folders in Quick access"; Caution = $false }
	@{ Name = "Meet Now Icon";                             Category = "UI & Personalization"; Function = "MeetNow";                         Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Meet Now icon in notification area"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name HideSCAMeetNow -EA SilentlyContinue).HideSCAMeetNow -ne 1 } }
	@{ Name = "News and Interests";                        Category = "UI & Personalization"; Function = "NewsInterests";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "News and Interests on the taskbar"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name ShellFeedsTaskbarViewMode -EA SilentlyContinue).ShellFeedsTaskbarViewMode -ne 2 } }
	@{ Name = "Taskbar Alignment";                         Category = "UI & Personalization"; Function = "TaskbarAlignment";                Type = "Choice"; Options = @("Left","Center"); Default = "Left"; WinDefault = "Center"; Description = "Taskbar alignment"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarAl -EA SilentlyContinue).TaskbarAl -ne 1 } }
	@{ Name = "Taskbar Widgets";                           Category = "UI & Personalization"; Function = "TaskbarWidgets";                  Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Widgets icon on the taskbar"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarDa -EA SilentlyContinue).TaskbarDa -ne 0 } }
	@{ Name = "Taskbar Search";                            Category = "UI & Personalization"; Function = "TaskbarSearch";                   Type = "Choice"; Options = @("Hide","SearchIcon","SearchBox"); Default = "Hide"; WinDefault = "SearchBox"; Description = "Search on the taskbar"; Caution = $false }
	@{ Name = "Search Highlights";                         Category = "UI & Personalization"; Function = "SearchHighlights";                Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Search highlights"; Caution = $false }
	@{ Name = "Task View Button";                          Category = "UI & Personalization"; Function = "TaskViewButton";                  Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Task View button on taskbar"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowTaskViewButton -EA SilentlyContinue).ShowTaskViewButton -ne 0 } }
	@{ Name = "Taskbar Button Combine";                    Category = "UI & Personalization"; Function = "TaskbarCombine";                  Type = "Choice"; Options = @("Always","Full","Never"); Default = "Always"; WinDefault = "Always"; Description = "Combine taskbar buttons mode"; Caution = $false }
	@{ Name = "Unpin Taskbar Shortcuts";                   Category = "UI & Personalization"; Function = "UnpinTaskbarShortcuts";           Type = "Action"; Default = $true;  WinDefault = $false; Description = "Unpin Edge, Store, Outlook, Mail, Copilot, Microsoft 365"; Caution = $false; ExtraArgs = @{ Shortcuts = @('Edge','Store','Outlook','Mail','Copilot','Microsoft365') } }
	@{ Name = "End Task in Taskbar Right-Click";           Category = "UI & Personalization"; Function = "TaskbarEndTask";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "End task via taskbar right-click"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name TaskbarEndTask -EA SilentlyContinue).TaskbarEndTask -eq 1 } }
	@{ Name = "Control Panel View";                        Category = "UI & Personalization"; Function = "ControlPanelView";                Type = "Choice"; Options = @("LargeIcons","SmallIcons","Category"); DisplayOptions = @("Large Icons","Small Icons","Category"); Default = "LargeIcons"; WinDefault = "Category"; Description = "Control Panel icons view"; Caution = $false }
	@{ Name = "Windows Color Mode";                        Category = "UI & Personalization"; Function = "WindowsColorMode";                Type = "Choice"; Options = @("Dark","Light"); Default = "Dark"; WinDefault = "Light"; Description = "Default Windows color mode"; Caution = $false }
	@{ Name = "App Color Mode";                            Category = "UI & Personalization"; Function = "AppColorMode";                    Type = "Choice"; Options = @("Dark","Light"); Default = "Dark"; WinDefault = "Light"; Description = "Default app color mode"; Caution = $false }
	@{ Name = "First Logon Animation";                     Category = "UI & Personalization"; Function = "FirstLogonAnimation";             Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "First sign-in animation after upgrade"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name EnableFirstLogonAnimation -EA SilentlyContinue).EnableFirstLogonAnimation -ne 0 } }
	@{ Name = "JPEG Wallpaper Quality";                    Category = "UI & Personalization"; Function = "JPEGWallpapersQuality";           Type = "Choice"; Options = @("Max","Default"); Default = "Max"; WinDefault = "Default"; Description = "JPEG desktop wallpaper quality factor"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -EA SilentlyContinue).JPEGImportQuality -eq 100 } }
	@{ Name = "Shortcut Suffix";                           Category = "UI & Personalization"; Function = "ShortcutsSuffix";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "'- Shortcut' suffix on new shortcuts"; Caution = $false }
	@{ Name = "Shortcut Arrow Icon";                       Category = "UI & Personalization"; Function = "ShortcutArrow";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Shortcut icon arrow overlay"; Caution = $false }
	@{ Name = "PrtScn Opens Snipping Tool";                Category = "UI & Personalization"; Function = "PrtScnSnippingTool";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Print Screen opens Snipping Tool"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name PrintScreenKeyForSnippingEnabled -EA SilentlyContinue).PrintScreenKeyForSnippingEnabled -eq 1 } }
	@{ Name = "Per-App Input Method";                      Category = "UI & Personalization"; Function = "AppsLanguageSwitch";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Different input method per app window"; Caution = $false }
	@{ Name = "Aero Shake";                                Category = "UI & Personalization"; Function = "AeroShaking";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Shake title bar to minimize other windows"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name DisallowShaking -EA SilentlyContinue).DisallowShaking -ne 1 } }
	@{ Name = "Downloads Folder Grouping";                 Category = "UI & Personalization"; Function = "FolderGroupBy";                   Type = "Choice"; Options = @("None","Default"); Default = "None"; WinDefault = "Default"; Description = "File grouping in Downloads folder"; Caution = $false }
	@{ Name = "Navigation Pane Auto Expand";               Category = "UI & Personalization"; Function = "NavigationPaneExpand";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Expand to open folder on navigation pane"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name NavPaneExpandToCurrentFolder -EA SilentlyContinue).NavPaneExpandToCurrentFolder -eq 1 } }
	@{ Name = "Start Menu Recommended Section";            Category = "UI & Personalization"; Function = "StartRecommendedSection";         Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Recommended section in Start Menu (Enterprise/Education)"; Caution = $false }

	# ── OneDrive ─────────────────────────────────────────────────────
	@{ Name = "OneDrive";                                  Category = "OneDrive";            Function = "OneDrive";                        Type = "Choice"; Options = @("Install","Uninstall"); Default = "Uninstall"; WinDefault = "Install"; Description = "OneDrive installation state"; Caution = $false }

	# ── System ───────────────────────────────────────────────────────
	@{ Name = "Lock Screen";                               Category = "System";              Function = "LockScreen";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Lock screen"; Caution = $false; VisibleIf = { ((Get-OSInfo).OSName -like "*Windows 11*") }; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreen -EA SilentlyContinue).NoLockScreen -ne 1 } }
	@{ Name = "Lock Screen (RS1)";                         Category = "System";              Function = "LockScreenRS1";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Lock screen (since 1903)"; Caution = $false; VisibleIf = { ((Get-OSInfo).OSName -like "*Windows 10*") }; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableLockScreen -EA SilentlyContinue).DisableLockScreen -ne 1 } }
	@{ Name = "Network on Lock Screen";                    Category = "System";              Function = "NetworkFromLockScreen";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Network options from Lock Screen"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DontDisplayNetworkSelectionUI -EA SilentlyContinue).DontDisplayNetworkSelectionUI -ne 1 } }
	@{ Name = "Shutdown on Lock Screen";                   Category = "System";              Function = "ShutdownFromLockScreen";           Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Shutdown options from Lock Screen"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name ShutdownWithoutLogon -EA SilentlyContinue).ShutdownWithoutLogon -eq 1 } }
	@{ Name = "Lock Screen Blur";                          Category = "System";              Function = "LockScreenBlur";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Lock screen blur effect (since 1903)"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableAcrylicBackgroundOnLogon -EA SilentlyContinue).DisableAcrylicBackgroundOnLogon -ne 1 } }
	@{ Name = "Task Manager Details";                      Category = "System";              Function = "TaskManagerDetails";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Task Manager details view"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name Preferences -EA SilentlyContinue) -ne $null } }
	@{ Name = "File Operations Details";                   Category = "System";              Function = "FileOperationsDetails";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "File operations details"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name EnthusiastMode -EA SilentlyContinue).EnthusiastMode -eq 1 } }
	@{ Name = "File Delete Confirmation";                  Category = "System";              Function = "FileDeleteConfirm";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "File delete confirmation dialog"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name ConfirmFileDelete -EA SilentlyContinue).ConfirmFileDelete -eq 1 } }
	@{ Name = "All Tray Icons";                            Category = "System";              Function = "TrayIcons";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Show all tray icons"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoAutoTrayNotify -EA SilentlyContinue).NoAutoTrayNotify -ne 1 } }
	@{ Name = "Search App in Store for Unknown Ext.";     Category = "System";              Function = "SearchAppInStore";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Search for app in store for unknown extensions"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoUseStoreOpenWith -EA SilentlyContinue).NoUseStoreOpenWith -ne 1 } }
	@{ Name = "New App Prompt";                            Category = "System";              Function = "NewAppPrompt";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "'How do you want to open this file?' prompt"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name NoNewAppAlert -EA SilentlyContinue).NoNewAppAlert -ne 1 } }
	@{ Name = "Recently Added Apps (Start)";               Category = "System";              Function = "RecentlyAddedApps";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "'Recently added' list from the Start Menu"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name HideRecentlyAddedApps -EA SilentlyContinue).HideRecentlyAddedApps -ne 1 } }
	@{ Name = "Most Used Apps (Start)";                    Category = "System";              Function = "MostUsedApps";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "'Most used' apps list from the Start Menu"; Caution = $false }
	@{ Name = "Visual Effects";                            Category = "System";              Function = "VisualFX";                         Type = "Choice"; Options = @("Performance","Appearance"); Default = "Performance"; WinDefault = "Appearance"; Description = "Visual effects mode"; Caution = $false }
	@{ Name = "Title Bar Color";                           Category = "System";              Function = "TitleBarColor";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Title bar color from background"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\DWM" -Name ColorPrevalence -EA SilentlyContinue).ColorPrevalence -eq 1 } }
	@{ Name = "Enhanced Pointer Precision";                Category = "System";              Function = "EnhPointerPrecision";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Enhanced pointer precision (mouse acceleration)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name MouseSpeed -EA SilentlyContinue).MouseSpeed -eq 1 } }
	@{ Name = "Startup Sound";                             Category = "System";              Function = "StartupSound";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Play Windows Startup sound"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name DisableStartupSound -EA SilentlyContinue).DisableStartupSound -ne 1 } }
	@{ Name = "Changing Sound Scheme";                     Category = "System";              Function = "ChangingSoundScheme";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Allow changing sound scheme"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoChangingSoundScheme -EA SilentlyContinue).NoChangingSoundScheme -ne 1 } }
	@{ Name = "Verbose Startup/Shutdown Messages";         Category = "System";              Function = "VerboseStatus";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Verbose startup/shutdown status messages"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name VerboseStatus -EA SilentlyContinue).VerboseStatus -eq 1 } }
	@{ Name = "Storage Sense";                             Category = "System";              Function = "StorageSense";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Storage Sense"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -EA SilentlyContinue)."01" -eq 1 } }
	@{ Name = "Hibernation";                               Category = "System";              Function = "Hibernation";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Hibernation"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name HibernateEnabled -EA SilentlyContinue).HibernateEnabled -eq 1 } }
	@{ Name = "Win32 Long Path Limit";                     Category = "System";              Function = "Win32LongPathLimit";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows 260 character path limit"; Caution = $false }
	@{ Name = "BSoD Stop Error Code";                      Category = "System";              Function = "BSoDStopError";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Display stop error code on BSoD"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name DisplayParameters -EA SilentlyContinue).DisplayParameters -eq 1 } }
	@{ Name = "Admin Approval Mode (UAC)";                 Category = "System";              Function = "AdminApprovalMode";                Type = "Choice"; Options = @("Never","Default"); Default = "Default"; WinDefault = "Default"; Description = "UAC notification level"; Caution = $false }
	@{ Name = "Delivery Optimization";                     Category = "System";              Function = "DeliveryOptimization";             Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Delivery Optimization"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name DODownloadMode -EA SilentlyContinue).DODownloadMode -ne 99 } }
	@{ Name = "Windows Manage Default Printer";            Category = "System";              Function = "WindowsManageDefaultPrinter";      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Let Windows manage default printer"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows" -Name LegacyDefaultPrinterMode -EA SilentlyContinue).LegacyDefaultPrinterMode -ne 1 } }
	@{ Name = "Windows Features";                          Category = "System";              Function = "WindowsFeatures";                  Type = "Choice"; Options = @("Disable","Enable"); Default = $null; WinDefault = "Enable"; Description = "Manage Windows features via dialog"; Caution = $false }
	@{ Name = "Windows Capabilities";                      Category = "System";              Function = "WindowsCapabilities";              Type = "Choice"; Options = @("Uninstall","Install"); Default = $null; WinDefault = "Install"; Description = "Manage optional features via dialog"; Caution = $false }
	@{ Name = "Current Network Profile";                   Category = "System";              Function = "CurrentNetwork";                   Type = "Choice"; Options = @("Private","Public"); Default = "Private"; WinDefault = "Public"; Description = "Current network profile type"; Caution = $false }
	@{ Name = "Unknown Networks Profile";                  Category = "System";              Function = "UnknownNetworks";                  Type = "Choice"; Options = @("Private","Public"); Default = "Private"; WinDefault = "Public"; Description = "Unknown network profile type"; Caution = $false }
	@{ Name = "Network Devices Auto Install";              Category = "System";              Function = "NetDevicesAutoInst";               Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Automatic installation of network devices"; Caution = $false }
	@{ Name = "Home Groups";                               Category = "System";              Function = "HomeGroups";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Home Groups services"; Caution = $false }
	@{ Name = "SMB 1.0 Protocol";                          Category = "System";              Function = "SMB1";                             Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Obsolete SMB 1.0 protocol"; Caution = $false }
	@{ Name = "File and Printer Sharing (SMB Server)";    Category = "System";              Function = "SMBServer";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "File and printer sharing"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name SMB2 -EA SilentlyContinue).SMB2 -ne 0 } }
	@{ Name = "Repair Windows 11 SMB Issue";               Category = "System";              Function = "Repair-Windows11SMBUpdateIssue";   Type = "Action"; Default = $true;  WinDefault = $false; Description = "Repair common Windows 11 SMB client/share issue"; Caution = $false }
	@{ Name = "SMB Sharing Compatibility";                 Category = "System";              Function = "Set-SMBSharingCompatibility";      Type = "Action"; Default = $true;  WinDefault = $false; Description = "Preserve SMB file/printer sharing and credentials"; Caution = $false }
	@{ Name = "SMB Guest Compatibility";                   Category = "System";              Function = "Enable-SMBGuestCompatibility";     Type = "Action"; Default = $true;  WinDefault = $false; Description = "Enable guest/no-prompt SMB compatibility"; Caution = $false }
	@{ Name = "NetBIOS over TCP/IP";                       Category = "System";              Function = "NetBIOS";                          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "NetBIOS over TCP/IP"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue) -ne $null } }
	@{ Name = "LLMNR Protocol";                            Category = "System";              Function = "LLMNR";                            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Link-Local Multicast Name Resolution"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name EnableMulticast -EA SilentlyContinue).EnableMulticast -ne 0 } }
	@{ Name = "Client for Microsoft Networks";             Category = "System";              Function = "MSNetClient";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Client for Microsoft Networks"; Caution = $false }
	@{ Name = "QoS Packet Scheduler";                      Category = "System";              Function = "QoS";                              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Quality of Service packet scheduler"; Caution = $false }
	@{ Name = "NCSI Probe";                                Category = "System";              Function = "NCSIProbe";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Network Connectivity Status Indicator"; Caution = $false }
	@{ Name = "Internet Connection Sharing";               Category = "System";              Function = "ConnectionSharing";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Internet Connection Sharing (hotspot)"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name NC_ShowSharedAccessUI -EA SilentlyContinue).NC_ShowSharedAccessUI -ne 0 } }
	@{ Name = "Updates for Other MS Products";             Category = "System";              Function = "UpdateMicrosoftProducts";          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Receive updates for other Microsoft products"; Caution = $false }
	@{ Name = "Restart Required Notification";             Category = "System";              Function = "RestartNotification";              Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $false; Description = "Notify when restart is required for updates"; Caution = $false }
	@{ Name = "Restart After Update";                      Category = "System";              Function = "RestartDeviceAfterUpdate";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Restart as soon as possible to finish updating"; Caution = $false }
	@{ Name = "Active Hours";                              Category = "System";              Function = "ActiveHours";                      Type = "Choice"; Options = @("Automatically","Manually"); Default = "Manually"; WinDefault = "Manually"; Description = "Active hours adjustment"; Caution = $false }
	@{ Name = "Get Latest Updates ASAP";                   Category = "System";              Function = "WindowsLatestUpdate";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Get latest updates as soon as available"; Caution = $false }
	@{ Name = "Power Plan";                                Category = "System";              Function = "PowerPlan";                        Type = "Choice"; Options = @("High","Balanced"); Default = "High"; WinDefault = "Balanced"; Description = "Power plan selection"; Caution = $false }
	@{ Name = "Network Adapters Save Power";               Category = "System";              Function = "NetworkAdaptersSavePower";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Allow network adapters to save power"; Caution = $false }
	@{ Name = "Default Input Method";                      Category = "System";              Function = "InputMethod";                      Type = "Choice"; Options = @("English","Default"); Default = "English"; WinDefault = "Default"; Description = "Override default input method"; Caution = $false }
	@{ Name = "Latest .NET Runtime for All Apps";          Category = "System";              Function = "LatestInstalled.NET";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Use latest installed .NET runtime for all apps"; Caution = $false }
	@{ Name = "Recommended Troubleshooting";               Category = "System";              Function = "RecommendedTroubleshooting";      Type = "Choice"; Options = @("Automatically","Default"); Default = "Default"; WinDefault = "Default"; Description = "Troubleshooter behavior"; Caution = $false }
	@{ Name = "Reserved Storage";                          Category = "System";              Function = "ReservedStorage";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Reserved storage after next update"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name ShippedWithReserves -EA SilentlyContinue).ShippedWithReserves -eq 1 } }
	@{ Name = "F1 Help Lookup";                            Category = "System";              Function = "F1HelpPage";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Help lookup via F1 key"; Caution = $false }
	@{ Name = "Num Lock at Startup";                       Category = "System";              Function = "NumLock";                          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Num Lock on at startup"; Caution = $false; Detect = { (Get-ItemProperty "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" -Name InitialKeyboardIndicators -EA SilentlyContinue).InitialKeyboardIndicators -match "2" } }
	@{ Name = "Caps Lock";                                 Category = "System";              Function = "CapsLock";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Caps Lock key"; Caution = $false; Detect = { -not ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -EA SilentlyContinue)."Scancode Map") } }
	@{ Name = "Sticky Keys (5x Shift)";                   Category = "System";              Function = "StickyShift";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Press Shift 5 times for Sticky Keys"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -EA SilentlyContinue).Flags -ne 506 } }
	@{ Name = "AutoPlay";                                  Category = "System";              Function = "Autoplay";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "AutoPlay for media and devices"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -EA SilentlyContinue).DisableAutoplay -ne 1 } }
	@{ Name = "Save Restartable Apps";                     Category = "System";              Function = "SaveRestartableApps";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Auto save and restart apps on sign-in"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name RestartApps -EA SilentlyContinue).RestartApps -eq 1 } }
	@{ Name = "Network Discovery";                         Category = "System";              Function = "NetworkDiscovery";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Network Discovery and File/Printer Sharing"; Caution = $false; Detect = { (Get-NetFirewallRule -DisplayGroup "Network Discovery" -EA SilentlyContinue | Where-Object Enabled -eq True | Select-Object -First 1) -ne $null } }
	@{ Name = "Default Terminal App";                      Category = "System";              Function = "DefaultTerminalApp";               Type = "Choice"; Options = @("WindowsTerminal","ConsoleHost"); DisplayOptions = @("Windows Terminal","Console Host"); Default = "WindowsTerminal"; WinDefault = "ConsoleHost"; Description = "Default terminal application"; Caution = $false }
	@{ Name = "Performance Tuning";                        Category = "System";              Function = "PerformanceTuning";                Type = "Action"; Default = $true;  WinDefault = $false; Description = "Run legacy system/bootstrap optimizations"; Caution = $false }
	@{ Name = "Prevent Edge Shortcut Creation";            Category = "System";              Function = "PreventEdgeShortcutCreation";      Type = "Action"; Default = $true;  WinDefault = $false; Description = "Prevent Edge desktop shortcut on update"; Caution = $false; ExtraArgs = @{ Channels = @('Stable','Beta','Dev','Canary') } }
	@{ Name = "Registry Backup";                           Category = "System";              Function = "RegistryBackup";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Registry backup to RegBack folder"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name EnablePeriodicBackup -EA SilentlyContinue).EnablePeriodicBackup -eq 1 } }

	# ── Advanced Startup ─────────────────────────────────────────────
	@{ Name = "Advanced Startup Desktop Shortcut";         Category = "System";              Function = "AdvancedStartupShortcut";          Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Desktop shortcut that reboots into Advanced Startup"; Caution = $false }

	# ── Start Menu ───────────────────────────────────────────────────
	@{ Name = "Start Layout";                              Category = "Start Menu";          Function = "StartLayout";                      Type = "Choice"; Options = @("Default","ShowMorePins","ShowMoreRecommendations"); DisplayOptions = @("Default","Show More Pins","Show More Recommendations"); Default = "ShowMorePins"; WinDefault = "Default"; Description = "Start menu layout"; Caution = $false }

	# ── UWP Apps ─────────────────────────────────────────────────────
	@{ Name = "Copilot App";                               Category = "UWP Apps";            SubCategory = "App Management"; Function = "Copilot"; Type = "Choice"; Options = @("Install","Uninstall"); Default = $null; WinDefault = "Install"; Description = "Microsoft AI assistant integration. Uninstall removes Copilot and all Windows AI features. Install restores them and installs Copilot from the Microsoft Store."; Caution = $false }
	@{ Name = "UWP Apps (Bulk)";                           Category = "UWP Apps";            SubCategory = "App Management"; Function = "UWPApps"; Type = "Choice"; Options = @("Uninstall","Install"); Default = "Uninstall"; WinDefault = "Install"; Description = "Apply action to all selected apps. A GUI selection window will appear to choose specific apps."; Caution = $true; CautionReason = "Uninstall: A selection dialog shows all installed UWP app bundles. Excluded from removal: Edge, Windows Store, Terminal, Notepad, WSL, media codecs, drivers. Some apps (e.g. Xbox Identity Provider, Gaming Services) cannot be reinstalled from the Store if uninstalled.`nInstall: A selection dialog shows missing apps that can be restored (Outlook, Calculator, Camera, Photos, Gaming Services, Phone Link, Dolby Access, Voice Recorder). Uses multiple fallback methods." }
	@{ Name = "Cortana Autostart";                         Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "CortanaAutostart";  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Cortana autostart"; Caution = $false }
	@{ Name = "New Outlook";                               Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "NewOutlook";        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "New Outlook app"; Caution = $false }
	@{ Name = "Background Apps";                           Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "BackgroundApps";  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Background Apps"; Caution = $true; CautionReason = "Disabling Background Apps prevents apps from running in the background and may affect notifications, updates, and sync functionality." }
	@{ Name = "Notifications";                             Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "Notifications";   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Notification Tray/Calendar"; Caution = $true; CautionReason = "Disabling Notifications completely turns off Windows notifications. You will not receive app alerts, system warnings, reminders, or calendar events. The notification tray and calendar flyout will not function." }
	@{ Name = "Edge Debloat";                              Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "EdgeDebloat";      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Edge debloat Group Policy settings"; Caution = $true; CautionReason = "Enforces multiple Group Policy settings that affect Edge functionality system-wide including telemetry, personalization, shopping assistant, collections, rewards, and Copilot sidebar." }
	@{ Name = "Revert Start Menu (24H2)";                  Category = "UWP Apps";            SubCategory = "Tweaks"; Function = "RevertStartMenu";  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Revert to original Start Menu from 24H2"; Caution = $true; CautionReason = "Aggressive. Reverting the Start Menu may break future Windows updates that depend on the new layout and requires additional tooling." }

	# ── Gaming ───────────────────────────────────────────────────────
	@{ Name = "Xbox Game Bar";                             Category = "Gaming";              Function = "XboxGameBar";                      Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Xbox Game Bar"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name AppCaptureEnabled -EA SilentlyContinue).AppCaptureEnabled -ne 0 } }
	@{ Name = "Xbox Game Bar Tips";                        Category = "Gaming";              Function = "XboxGameTips";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Xbox Game Bar tips"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name ShowStartupPanel -EA SilentlyContinue).ShowStartupPanel -ne 0 } }
	@{ Name = "GPU Scheduling";                            Category = "Gaming";              Function = "GPUScheduling";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Hardware-accelerated GPU scheduling"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name HwSchMode -EA SilentlyContinue).HwSchMode -eq 2 } }

	# ── Security ─────────────────────────────────────────────────────
	@{ Name = "Network Protection";                        Category = "Security";            Function = "NetworkProtection";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Defender Exploit Guard network protection"; Caution = $false; Detect = { try { (Get-MpPreference -EA Stop).EnableNetworkProtection -eq 1 } catch { $false } } }
	@{ Name = "PUA Detection";                             Category = "Security";            Function = "PUAppsDetection";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Potentially unwanted application detection"; Caution = $false }
	@{ Name = "Defender Sandbox";                          Category = "Security";            Function = "DefenderSandbox";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Sandboxing for Microsoft Defender"; Caution = $false; Detect = { [System.Environment]::GetEnvironmentVariable("MP_FORCE_USE_SANDBOX","Machine") -eq "1" } }
	@{ Name = "Dismiss MS Account Offer";                  Category = "Security";            Function = "DismissMSAccount";                 Type = "Action"; Default = $true;  WinDefault = $false; Description = "Dismiss Defender MS account sign-in offer"; Caution = $false }
	@{ Name = "Dismiss SmartScreen Filter Offer";          Category = "Security";            Function = "DismissSmartScreenFilter";         Type = "Action"; Default = $true;  WinDefault = $false; Description = "Dismiss Defender SmartScreen filter offer"; Caution = $false }
	@{ Name = "Event Viewer Custom View";                  Category = "Security";            Function = "EventViewerCustomView";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Process Creation custom view in Event Viewer"; Caution = $false }
	@{ Name = "PowerShell Module Logging";                 Category = "Security";            Function = "PowerShellModulesLogging";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Logging for all PowerShell modules"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name EnableModuleLogging -EA SilentlyContinue).EnableModuleLogging -eq 1 } }
	@{ Name = "PowerShell Script Logging";                 Category = "Security";            Function = "PowerShellScriptsLogging";         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Logging for all PowerShell scripts"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name EnableScriptBlockLogging -EA SilentlyContinue).EnableScriptBlockLogging -eq 1 } }
	@{ Name = "Apps SmartScreen";                          Category = "Security";            Function = "AppsSmartScreen";                  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "SmartScreen marks downloaded files as unsafe"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableSmartScreen -EA SilentlyContinue).EnableSmartScreen -ne 0 } }
	@{ Name = "Save Zone Information";                     Category = "Security";            Function = "SaveZoneInformation";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Mark downloaded files as unsafe (Zone.Identifier)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name SaveZoneInformation -EA SilentlyContinue).SaveZoneInformation -ne 2 } }
	@{ Name = "Windows Script Host";                       Category = "Security";            Function = "WindowsScriptHost";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Windows Script Host (.js/.vbs execution)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name Enabled -EA SilentlyContinue).Enabled -ne 0 } }
	@{ Name = "Import Exploit Protection Policy";          Category = "Security";            Function = "Import-ExploitProtectionPolicy";   Type = "Action"; Default = $false; WinDefault = $false; Description = "Import the Exploit Protection policy"; Caution = $true; CautionReason = "Aggressive. Imports a downloaded mitigation policy that can change exploit protection behavior for applications across the system." }
	@{ Name = "Defender Exploit Guard Policy";             Category = "Security";            Function = "Set-DefenderExploitGuardPolicy";   Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure additional Defender Exploit Guard policies"; Caution = $true; CautionReason = "Aggressive. Can block legitimate applications, Office automation, admin tooling, scripts, or line-of-business workflows." }
	@{ Name = "LOLBin Firewall Rules";                     Category = "Security";            Function = "Set-LOLBinFirewallRules";          Type = "Action"; Default = $false; WinDefault = $false; Description = "Configure LOLBin outbound firewall block rules"; Caution = $true; CautionReason = "Aggressive. Can break administrative scripts, installers, troubleshooting tools, or enterprise workflows that intentionally use these binaries." }
	@{ Name = "Windows Firewall Logging";                  Category = "Security";            Function = "Set-WindowsFirewallLogging";       Type = "Action"; Default = $true;  WinDefault = $false; Description = "Configure Windows Firewall logging"; Caution = $false }
	@{ Name = "Windows Sandbox";                           Category = "Security";            Function = "WindowsSandbox";                   Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Windows Sandbox (Pro/Enterprise/Education)"; Caution = $false; Detect = { (Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -EA SilentlyContinue).State -eq "Enabled" } }
	@{ Name = "DNS over HTTPS";                            Category = "Security";            Function = "DNSoverHTTPS";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "DNS-over-HTTPS for IPv4"; Caution = $false }
	@{ Name = "Local Security Authority Protection";      Category = "Security";            Function = "LocalSecurityAuthority";           Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "LSA protection to prevent code injection"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RunAsPPL -EA SilentlyContinue).RunAsPPL -ge 1 } }
	@{ Name = "Sharing Mapped Drives";                     Category = "Security";            Function = "SharingMappedDrives";              Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Sharing mapped drives between users"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLinkedConnections -EA SilentlyContinue).EnableLinkedConnections -eq 1 } }
	@{ Name = "Firewall";                                  Category = "Security";            Function = "Firewall";                         Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Windows Firewall"; Caution = $false; Detect = { (Get-NetFirewallProfile -EA SilentlyContinue | Where-Object Enabled -eq True | Select-Object -First 1) -ne $null } }
	@{ Name = "Defender Tray Icon";                        Category = "Security";            Function = "DefenderTrayIcon";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Windows Defender SysTray icon"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows Defender Security Center\Systray" -Name HideSystray -EA SilentlyContinue).HideSystray -ne 1 } }
	@{ Name = "Defender Cloud";                            Category = "Security";            Function = "DefenderCloud";                    Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Windows Defender Cloud protection"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name SpynetReporting -EA SilentlyContinue).SpynetReporting -ne 0 } }
	@{ Name = "Core Isolation Memory Integrity";           Category = "Security";            Function = "CIMemoryIntegrity";                Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Core Isolation Memory Integrity (HVCI)"; Caution = $false; Detect = { (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name Enabled -EA SilentlyContinue).Enabled -eq 1 } }
	@{ Name = "Defender Application Guard";                Category = "Security";            Function = "DefenderAppGuard";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Windows Defender Application Guard"; Caution = $false }
	@{ Name = "Account Protection Warning";                Category = "Security";            Function = "AccountProtectionWarn";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Account Protection warning in Defender"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows Security Health\State" -Name AccountProtection_MicrosoftAccount_Disconnected -EA SilentlyContinue).AccountProtectionWarn -ne 1 } }
	@{ Name = "Download File Blocking";                    Category = "Security";            Function = "DownloadBlocking";                 Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $true;  Description = "Blocking of downloaded files (zone info)"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name SaveZoneInformation -EA SilentlyContinue).SaveZoneInformation -ne 2 } }
	@{ Name = "F8 Boot Menu";                              Category = "Security";            Function = "F8BootMenu";                       Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "F8 boot menu options"; Caution = $false; Detect = { (bcdedit /enum "{current}" 2>$null) -match "bootmenupolicy.*legacy" } }
	@{ Name = "Boot Recovery";                             Category = "Security";            Function = "BootRecovery";                     Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $true;  Description = "Automatic recovery mode during boot"; Caution = $false; Detect = { (bcdedit /enum "{current}" 2>$null) -match "recoveryenabled.*Yes" } }
	@{ Name = "DEP OptOut";                                Category = "Security";            Function = "DEPOptOut";                        Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $false; WinDefault = $false; Description = "Data Execution Prevention policy (OptOut)"; Caution = $false }

	# ── Context Menu ─────────────────────────────────────────────────
	@{ Name = "MSI Extract Context Menu";                  Category = "Context Menu";        Function = "MSIExtractContext";                Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $false; Description = "'Extract all' in MSI context menu"; Caution = $false; Detect = { Test-Path "Registry::HKEY_CLASSES_ROOT\Msi.Package\shell\Extract" } }
	@{ Name = "CAB Install Context Menu";                  Category = "Context Menu";        Function = "CABInstallContext";                Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $false; Description = "'Install' in CAB context menu"; Caution = $false; Detect = { Test-Path "Registry::HKEY_CLASSES_ROOT\CABFolder\Shell\runas" } }
	@{ Name = "Edit with Clipchamp";                       Category = "Context Menu";        Function = "EditWithClipchampContext";         Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Edit with Clipchamp' context menu"; Caution = $false }
	@{ Name = "Edit with Photos";                          Category = "Context Menu";        Function = "EditWithPhotosContext";             Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Edit with Photos' context menu"; Caution = $false }
	@{ Name = "Edit with Paint";                           Category = "Context Menu";        Function = "EditWithPaintContext";              Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Edit with Paint' context menu"; Caution = $false }
	@{ Name = "Print CMD Context Menu";                    Category = "Context Menu";        Function = "PrintCMDContext";                   Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Print' in .bat/.cmd context menu"; Caution = $false }
	@{ Name = "Compressed Folder in New Menu";             Category = "Context Menu";        Function = "CompressedFolderNewContext";       Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Compressed (zipped) Folder' in New menu"; Caution = $false }
	@{ Name = "Multiple Invoke Context Menu";              Category = "Context Menu";        Function = "MultipleInvokeContext";            Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Open/Print/Edit for 15+ selected items"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name MultipleInvokePromptMinimum -EA SilentlyContinue).MultipleInvokePromptMinimum -ge 15 } }
	@{ Name = "Store in Open With Dialog";                 Category = "Context Menu";        Function = "UseStoreOpenWith";                 Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "'Look for an app in the Microsoft Store' in Open With"; Caution = $false }
	@{ Name = "Open in Windows Terminal";                  Category = "Context Menu";        Function = "OpenWindowsTerminalContext";       Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $true;  Description = "'Open in Windows Terminal' context menu"; Caution = $false; Detect = { Test-Path "Registry::HKEY_CLASSES_ROOT\Directory\shell\OpenWTHere" } }
	@{ Name = "Windows Terminal as Admin Default";         Category = "Context Menu";        Function = "OpenWindowsTerminalAdminContext";  Type = "Toggle"; OnParam = "Enable";  OffParam = "Disable"; Default = $true;  WinDefault = $false; Description = "Open Windows Terminal as admin by default"; Caution = $false }

	# ── Taskbar Clock ────────────────────────────────────────────────
	@{ Name = "Seconds on Taskbar Clock";                  Category = "Taskbar Clock";       Function = "SecondsInSystemClock";             Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $false; Description = "Seconds on the taskbar clock"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowSecondsInSystemClock -EA SilentlyContinue).ShowSecondsInSystemClock -eq 1 } }
	@{ Name = "Clock in Notification Center";              Category = "Taskbar Clock";       Function = "ClockInNotificationCenter";        Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $false; Description = "Time in Notification Center"; Caution = $false; Detect = { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name ShowClock -EA SilentlyContinue).ShowClock -ne 0 } }

	# ── Cursors ──────────────────────────────────────────────────────
	@{ Name = "Cursors";                                   Category = "Cursors";             Function = "Install-Cursors";                  Type = "Choice"; Options = @("Default","Dark","Light"); Default = "Default"; WinDefault = "Default"; Description = "Cursor theme selection"; Caution = $false }

	# ── Start Menu Apps ──────────────────────────────────────────────
	@{ Name = "Recently Added Apps in Start";              Category = "Start Menu";          Function = "RecentlyAddedStartApps";           Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Recently added apps in Start"; Caution = $false }
	@{ Name = "Most Used Apps in Start";                   Category = "Start Menu";          Function = "MostUsedStartApps";                Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $false; WinDefault = $true;  Description = "Most used apps in Start"; Caution = $false }
	@{ Name = "Start Menu All Section Categories";         Category = "Start Menu";          Function = "StartMenuAllSectionCategories";    Type = "Toggle"; OnParam = "Show";    OffParam = "Hide";    Default = $true;  WinDefault = $true;  Description = "All section with categories in Start (24H2+)"; Caution = $false }
)
#endregion Tweak Manifest

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
	param (
		[Parameter(Mandatory = $false)]
		[System.Object]
		$StartupSplash
	)

	Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

	# Primary category tabs (top tier)
	$PrimaryCategories = [ordered]@{
		"Initial Setup"       = @()
		"OS Hardening"        = @()
		"Privacy & Telemetry" = @()
		"System Tweaks"       = @()
		"UI & Personalization" = @()
		"OneDrive"            = @()
		"System"              = @("System","Start Menu","Start Menu Apps")
		"UWP Apps"            = @("UWP Apps")
		"Gaming"              = @()
		"Security"            = @()
		"Context Menu"        = @()
		"Taskbar Clock"       = @()
		"Cursors"             = @()
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

	#region Console window helpers
	# SW_ constants
	$SW_HIDE    = 0
	$SW_SHOW    = 5

	# Ensure the console interop type is available (same type used by Show-LoadingSplash)
	if (-not ('SplashConsoleHide' -as [type]))
	{
		Add-Type -Name 'SplashConsoleHide' -Namespace '' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
	}

	function Get-ConsoleHandle
	{
		return [SplashConsoleHide]::GetConsoleWindow()
	}

	function Hide-ConsoleWindow
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$hwnd = Get-ConsoleHandle
		if ($hwnd -ne [System.IntPtr]::Zero)
		{
			[SplashConsoleHide]::ShowWindow($hwnd, $SW_HIDE) | Out-Null
		}
	}

	function Show-ConsoleWindow
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$hwnd = Get-ConsoleHandle
		if ($hwnd -ne [System.IntPtr]::Zero)
		{
			[SplashConsoleHide]::ShowWindow($hwnd, $SW_SHOW) | Out-Null
			# Use the Helpers interop type for SetForegroundWindow
			try
			{
				Initialize-ForegroundWindowInterop
				[WinAPI.ForegroundWindow]::SetForegroundWindow($hwnd) | Out-Null
			}
			catch { $null = $_ }
		}
	}

	function Close-ConsoleWindow
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$hwnd = Get-ConsoleHandle
		if ($hwnd -ne [System.IntPtr]::Zero)
		{
			[SplashConsoleHide]::ShowWindow($hwnd, $SW_HIDE) | Out-Null
		}
	}
	#endregion Console window helpers

	#region Theme colors
	$Script:DarkTheme = @{
		WindowBg      = "#1E1E2E"
		HeaderBg      = "#181825"
		PanelBg       = "#1E1E2E"
		CardBg        = "#2A2A3C"
		TabBg         = "#313244"
		TabActiveBg   = "#45475A"
		TabHoverBg    = "#585B70"
		BorderColor   = "#45475A"
		TextPrimary   = "#CDD6F4"
		TextSecondary = "#A6ADC8"
		TextMuted     = "#6C7086"
		AccentBlue    = "#89B4FA"
		AccentHover   = "#74C7EC"
		AccentPress   = "#94E2D5"
		CautionBg     = "#3B2028"
		CautionBorder = "#F38BA8"
		CautionText   = "#F38BA8"
		ImpactBadge   = "#F38BA8"
		ImpactBadgeBg = "#3B2028"
		DestructiveBg = "#8B2252"
		DestructiveHover = "#A6294E"
		SectionLabel  = "#89B4FA"
		ScrollBg      = "#313244"
		ScrollThumb   = "#585B70"
		ToggleOn      = "#A6E3A1"
		ToggleOff     = "#F38BA8"
	}
	$Script:LightTheme = @{
		WindowBg      = "#C8CAD6"
		HeaderBg      = "#B8BAC6"
		PanelBg       = "#C8CAD6"
		CardBg        = "#D4D6E2"
		TabBg         = "#AAACB8"
		TabActiveBg   = "#9A9CA8"
		TabHoverBg    = "#8A8C98"
		BorderColor   = "#9A9CA8"
		TextPrimary   = "#1E2030"
		TextSecondary = "#3A3C50"
		TextMuted     = "#5A5C70"
		AccentBlue    = "#1550AA"
		AccentHover   = "#1A60C4"
		AccentPress   = "#104090"
		CautionBg     = "#D8AAAA"
		CautionBorder = "#880020"
		CautionText   = "#880020"
		ImpactBadge   = "#880020"
		ImpactBadgeBg = "#D8AAAA"
		DestructiveBg = "#880020"
		DestructiveHover = "#660018"
		SectionLabel  = "#1550AA"
		ScrollBg      = "#AAACB8"
		ScrollThumb   = "#8A8C98"
		ToggleOn      = "#226622"
		ToggleOff     = "#880020"
	}
	$Script:CurrentTheme = $Script:DarkTheme
	#endregion Theme colors

	#region Themed Dialog
	# Show a dark-themed WPF dialog that matches the main GUI, replacing
	# the stock Windows MessageBox which looks out of place.
	# Returns the string label of the button the user clicked.
	function Show-ThemedDialog
	{
		param(
			[string]$Title,
			[string]$Message,
			[string[]]$Buttons = @('OK'),
			[string]$AccentButton = $null,   # which button gets accent styling
			[string]$DestructiveButton = $null # which button gets red/destructive styling
		)

		$bc = [System.Windows.Media.BrushConverter]::new()
		$theme = $Script:CurrentTheme

		$dlg = New-Object System.Windows.Window
		$dlg.Title                  = $Title
		$dlg.Width                  = 440
		$dlg.SizeToContent          = 'Height'
		$dlg.ResizeMode             = 'NoResize'
		$dlg.WindowStartupLocation  = 'CenterOwner'
		$dlg.Background             = $bc.ConvertFromString($theme.WindowBg)
		$dlg.Foreground             = $bc.ConvertFromString($theme.TextPrimary)
		$dlg.FontFamily             = [System.Windows.Media.FontFamily]::new('Segoe UI')
		$dlg.FontSize               = 13
		$dlg.ShowInTaskbar          = $false
		$dlg.WindowStyle            = 'SingleBorderWindow'

		# Try to set owner to main window
		try { $dlg.Owner = $Form } catch { $null = $_ }

		$outerStack = New-Object System.Windows.Controls.StackPanel

		# Message area
		$msgBorder = New-Object System.Windows.Controls.Border
		$msgBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
		$msgTb = New-Object System.Windows.Controls.TextBlock
		$msgTb.Text         = $Message
		$msgTb.TextWrapping = 'Wrap'
		$msgTb.Foreground   = $bc.ConvertFromString($theme.TextPrimary)
		$msgTb.FontSize     = 13
		$msgTb.LineHeight   = 20
		$msgBorder.Child = $msgTb
		$outerStack.Children.Add($msgBorder) | Out-Null

		# Button bar
		$btnBorder = New-Object System.Windows.Controls.Border
		$btnBorder.Background = $bc.ConvertFromString($theme.HeaderBg)
		$btnBorder.Padding    = [System.Windows.Thickness]::new(16, 12, 16, 12)
		$btnPanel = New-Object System.Windows.Controls.StackPanel
		$btnPanel.Orientation       = 'Horizontal'
		$btnPanel.HorizontalAlignment = 'Right'

		$resultRef = @{ Value = $null }

		foreach ($label in $Buttons)
		{
			$btn = New-Object System.Windows.Controls.Button
			$btn.Content  = $label
			$btn.MinWidth = 90
			$btn.Height   = 32
			$btn.Margin   = [System.Windows.Thickness]::new(6, 0, 0, 0)
			$btn.Cursor   = [System.Windows.Input.Cursors]::Hand

			# Template for rounded buttons
			$tmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
			$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
			$bd.Name = 'Bd'
			$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(5))
			$bd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(14, 6, 14, 6))
			$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
			$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
			$cp.SetValue([System.Windows.Controls.ContentPresenter]::VerticalAlignmentProperty, [System.Windows.VerticalAlignment]::Center)
			$bd.AppendChild($cp)
			$tmpl.VisualTree = $bd
			$btn.Template = $tmpl

			if ($label -eq $AccentButton)
			{
				$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($theme.AccentBlue))
				$btn.Foreground = $bc.ConvertFromString($theme.HeaderBg)
				$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
			}
			elseif ($label -eq $DestructiveButton)
			{
				$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($theme.DestructiveBg))
				$btn.Foreground = $bc.ConvertFromString('#FFFFFF')
				$btn.FontWeight = [System.Windows.FontWeights]::SemiBold
			}
			else
			{
				$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($theme.TabBg))
				$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $bc.ConvertFromString($theme.BorderColor))
				$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
				$btn.Foreground = $bc.ConvertFromString($theme.TextPrimary)
			}

			$btnLabel = $label
			$dlgRef = $dlg
			$resRef = $resultRef
			$btn.Add_Click({
				$resRef.Value = $btnLabel
				$dlgRef.Close()
			}.GetNewClosure())

			$btnPanel.Children.Add($btn) | Out-Null
		}

		$btnBorder.Child = $btnPanel
		$outerStack.Children.Add($btnBorder) | Out-Null
		$dlg.Content = $outerStack

		$dlg.ShowDialog() | Out-Null

		return $resultRef.Value
	}
	#endregion Themed Dialog

	#region XAML template
	[xml]$XAML = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Name="MainWindow"
	Title="WinUtil &#x2014; Windows Optimization &amp; Hardening"
	MinWidth="820" MinHeight="560"
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
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="*"/>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="Auto"/>
				</Grid.ColumnDefinitions>
				<TextBlock Name="TitleText" Grid.Column="0"
					FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
				<Button Name="BtnLog" Grid.Column="1" Content="Open Log"
					FontSize="11" Margin="0,0,12,0" Padding="10,4" Cursor="Hand" VerticalAlignment="Center"/>
				<StackPanel Grid.Column="2" Orientation="Horizontal" Margin="0,0,12,0" VerticalAlignment="Center" Visibility="Collapsed">
					<TextBlock Text="System Scan" VerticalAlignment="Center" Margin="0,0,6,0"
						Name="ScanLabel" FontSize="11"/>
					<CheckBox Name="ChkScan" VerticalAlignment="Center"/>
				</StackPanel>
				<StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
					<CheckBox Name="ChkTheme" VerticalAlignment="Center" Content="Light Mode"/>
				</StackPanel>
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
				<Button Name="BtnDefaults" Grid.Column="0" Content="Restore to Windows Defaults"
					FontSize="13" Margin="4" Padding="16,8" Cursor="Hand"/>
				<TextBlock Name="StatusText" Grid.Column="1" VerticalAlignment="Center"
					FontSize="12" Margin="8,0" TextWrapping="Wrap"/>
				<Button Name="BtnRun" Grid.Column="2" Content="Run Tweaks"
					FontSize="13" Margin="4" Padding="20,8" Cursor="Hand" FontWeight="SemiBold"/>
			</Grid>
		</Border>
	</Grid>
</Window>
"@
	#endregion XAML template

	$Form = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XAML))

	# Size the window to 85% of the screen working area so it fits any resolution
	# without being full-screen. Falls back to safe defaults if the call fails.
	try
	{
		$workArea = [System.Windows.SystemParameters]::WorkArea
		$targetW  = [Math]::Round($workArea.Width  * 0.85)
		$targetH  = [Math]::Round($workArea.Height * 0.85)
		$Form.Width  = [Math]::Max($targetW, 820)
		$Form.Height = [Math]::Max($targetH, 560)
	}
	catch
	{
		$Form.Width  = 1100
		$Form.Height = 720
	}
	$HeaderBorder  = $Form.FindName("HeaderBorder")
	$TitleText     = $Form.FindName("TitleText")
	$PrimaryTabs   = $Form.FindName("PrimaryTabs")
	$ContentBorder = $Form.FindName("ContentBorder")
	$ContentScroll = $Form.FindName("ContentScroll")
	$BottomBorder  = $Form.FindName("BottomBorder")
	$StatusText    = $Form.FindName("StatusText")
	$BtnRun        = $Form.FindName("BtnRun")
	$BtnDefaults   = $Form.FindName("BtnDefaults")
	$ChkTheme      = $Form.FindName("ChkTheme")
	$BtnLog        = $Form.FindName("BtnLog")
	$ChkScan       = $Form.FindName("ChkScan")
	$ScanLabel     = $Form.FindName("ScanLabel")
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

	# Set the window title to include OS name
	try { $Form.Title = "WinUtil Script for $((Get-OSInfo).OSName)" } catch { $null = $_ }
	$TitleText.Text = $Form.Title

	#region Helper: Apply theme
	function Set-GUITheme
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([hashtable]$Theme)
		$Script:CurrentTheme = $Theme
		$bc = [System.Windows.Media.BrushConverter]::new()

		$Form.Background  = $bc.ConvertFromString($Theme.WindowBg)
		$Form.Foreground  = $bc.ConvertFromString($Theme.TextPrimary)
		$HeaderBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		$ContentBorder.Background = $bc.ConvertFromString($Theme.PanelBg)
		$BottomBorder.Background = $bc.ConvertFromString($Theme.HeaderBg)
		$TitleText.Foreground = $bc.ConvertFromString($Theme.TextPrimary)
		$StatusText.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$ScanLabel.Foreground = $bc.ConvertFromString($Theme.TextSecondary)
		$ChkTheme.Foreground = $bc.ConvertFromString($Theme.TextSecondary)

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

		# Build a richer tooltip that explains what the tweak does and how the
		# Standard preset will treat it.
		$richText = if ([string]::IsNullOrWhiteSpace($TooltipText)) {
			"This option changes a Windows setting."
		} else {
			$TooltipText.Trim()
		}
		if ($Tweak)
		{
			$standardHint = switch ($Tweak.Type)
			{
				'Toggle' { if ([bool]$Tweak.Default) { 'Standard preset: selected' } else { 'Standard preset: not selected' } }
				'Action' { if ([bool]$Tweak.Default) { 'Standard preset: selected' } else { 'Standard preset: not selected' } }
				'Choice' {
					if ([string]::IsNullOrWhiteSpace([string]$Tweak.Default)) { 'Standard preset: no automatic choice' }
					else { "Standard preset: $($Tweak.Default)" }
				}
				default { $null }
			}

			switch ($Tweak.Type)
			{
				'Toggle' {
					$onLabel  = if ($Tweak.OnParam)  { $Tweak.OnParam  } else { 'Enable' }
					$offLabel = if ($Tweak.OffParam) { $Tweak.OffParam } else { 'Disable' }
					$richText += "`n`nIf checked: $onLabel`nIf unchecked: $offLabel"
				}
				'Choice' {
					$displayOpts = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } else { $Tweak.Options }
					$optList = ($displayOpts -join ', ')
					$richText += "`n`nAvailable choices: $optList"
					if ($Tweak.WinDefault) { $richText += "`nWindows default: $($Tweak.WinDefault)" }
				}
				'Action' {
					$richText += "`n`nIf checked: this action runs when you click Run Tweaks`nIf unchecked: this action is skipped"
				}
			}

			if ($standardHint)
			{
				$richText += "`n$standardHint"
			}

			if ($Tweak.Caution -and $Tweak.CautionReason)
			{
				$richText += "`n`nWhy this needs care: $($Tweak.CautionReason)"
			}
		}

		$icon = New-Object System.Windows.Controls.TextBlock
		$icon.Text = [char]0x24D8  # ⓘ
		$icon.FontSize = 14
		$icon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		$icon.VerticalAlignment = "Center"
		$icon.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
		$icon.Cursor = [System.Windows.Input.Cursors]::Help

		$tip = New-Object System.Windows.Controls.ToolTip
		$tip.Content = $richText
		$tip.MaxWidth = 400
		$icon.ToolTip = $tip
		return $icon
	}

	function New-ImpactBadge
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ()
		$border = New-Object System.Windows.Controls.Border
		$border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.ImpactBadgeBg)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(3)
		$border.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
		$border.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
		$border.VerticalAlignment = "Center"

		$txt = New-Object System.Windows.Controls.TextBlock
		$txt.Text = "Impact"
		$txt.FontSize = 10
		$txt.FontWeight = [System.Windows.FontWeights]::SemiBold
		$txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.ImpactBadge)

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
		$lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.SectionLabel)
		$lbl.Margin = [System.Windows.Thickness]::new(12, 16, 0, 6)
		return $lbl
	}

	function New-CautionSection
	{
		[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
		param ([array]$CautionTweaks)
		if ($CautionTweaks.Count -eq 0) { return $null }
		$bc = [System.Windows.Media.BrushConverter]::new()

		$border = New-Object System.Windows.Controls.Border
		$border.Background = $bc.ConvertFromString($Script:CurrentTheme.CautionBg)
		$border.BorderBrush = $bc.ConvertFromString($Script:CurrentTheme.CautionBorder)
		$border.BorderThickness = [System.Windows.Thickness]::new(1)
		$border.CornerRadius = [System.Windows.CornerRadius]::new(6)
		$border.Margin = [System.Windows.Thickness]::new(8, 12, 8, 4)
		$border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

		$stack = New-Object System.Windows.Controls.StackPanel
		$stack.Orientation = "Vertical"

		$header = New-Object System.Windows.Controls.TextBlock
		$header.Text = "CAUTION"
		$header.FontSize = 12
		$header.FontWeight = [System.Windows.FontWeights]::Bold
		$header.Foreground = $bc.ConvertFromString($Script:CurrentTheme.CautionText)
		$header.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
		$stack.Children.Add($header) | Out-Null

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

			$stack.Children.Add($item) | Out-Null
		}

		$border.Child = $stack
		return $border
	}

	function Add-ExecutionLogLine
	{
		param (
			[string]$Text,
			[string]$Level = 'INFO'
		)

		if ([string]::IsNullOrWhiteSpace($Text) -or -not $Script:ExecutionLogBox) { return }

		$timestamp = Get-Date -Format 'HH:mm:ss'
		$line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Text
		$Script:ExecutionLogBox.AppendText($line + [Environment]::NewLine)
		# Only auto-scroll if the user hasn't scrolled up
		$vertOff = $Script:ExecutionLogBox.VerticalOffset
		$vpH     = $Script:ExecutionLogBox.ViewportHeight
		$extH    = $Script:ExecutionLogBox.ExtentHeight
		if (($vertOff + $vpH) -ge ($extH - 30))
		{
			$Script:ExecutionLogBox.ScrollToEnd()
		}
		$Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
	}

	# Scriptblock variable so .GetNewClosure() closures (timer, drainEntry) capture it correctly.
	# Named functions are NOT captured by GetNewClosure — only variables are.
	$updateProgressFn = {
		param (
			[int]$Completed,
			[int]$Total,
			[string]$CurrentAction,
			[bool]$Indeterminate = $false,   # kept for call-site compat; ignored once Total > 0
			# Sub-task progress (e.g. a download inside a tweak function)
			[int]$SubCompleted  = -1,
			[int]$SubTotal      = -1,
			[string]$SubAction  = $null,
			[bool]$ClearSub     = $false
		)

		if ($Script:ExecutionProgressBar)
		{
			if ($Total -gt 0)
			{
				# Always show real fill once we know the total
				$Script:ExecutionProgressBar.IsIndeterminate = $false
				$Script:ExecutionProgressBar.Maximum = $Total
				$Script:ExecutionProgressBar.Value   = [Math]::Min($Completed, $Total)
			}
			else
			{
				# Pre-run: no total yet — show indeterminate stripe
				$Script:ExecutionProgressBar.IsIndeterminate = $true
			}
		}

		if ($Script:ExecutionProgressText)
		{
			if ($Total -gt 0)
			{
				$Script:ExecutionProgressText.Text = "{0}/{1} completed" -f $Completed, $Total
				if (-not [string]::IsNullOrWhiteSpace($CurrentAction))
				{
					$Script:ExecutionProgressText.Text += " - $CurrentAction"
				}
			}
			else
			{
				$Script:ExecutionProgressText.Text = if ($CurrentAction) { $CurrentAction } else { "Preparing run..." }
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
				# Unknown total — show indeterminate sub-bar
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
			[System.Windows.Threading.DispatcherPriority]::Background,
			[System.Windows.Threading.DispatcherOperationCallback]{
				param($state)
				$state.Continue = $false
				return $null
			},
			$frame
		)
		[System.Windows.Threading.Dispatcher]::PushFrame($frame)
	}

	function Request-RunAbort
	{
		if (-not $Script:RunInProgress -or $Script:AbortRequested) { return }

		# Set the flag immediately so the next Invoke-GuiEvents cycle picks it up.
		# No confirmation dialog — it was slowing things down and blocking the UI.
		$Script:AbortRequested = $true
		if ($Script:AbortRunButton)
		{
			$Script:AbortRunButton.Content = "Aborting..."
			$Script:AbortRunButton.IsEnabled = $false
		}
		$StatusText.Text = "Abort requested. Will stop after the current step finishes."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
		Add-ExecutionLogLine -Text 'Abort requested by user - will stop after current step.' -Level 'WARNING'
	}

	function Enter-ExecutionView
	{
		param ([string]$Title)

		$bc = [System.Windows.Media.BrushConverter]::new()
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
		$progressCol2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
		$progressGrid.ColumnDefinitions.Add($progressCol1) | Out-Null
		$progressGrid.ColumnDefinitions.Add($progressCol2) | Out-Null

		$progressStack = New-Object System.Windows.Controls.StackPanel
		$progressStack.Orientation = 'Vertical'
		[System.Windows.Controls.Grid]::SetColumn($progressStack, 0)

		$progressBar = New-Object System.Windows.Controls.ProgressBar
		$progressBar.Minimum = 0
		$progressBar.Maximum = 1
		$progressBar.Value = 0
		$progressBar.Height = 16
		$progressBar.Margin = [System.Windows.Thickness]::new(0,0,12,4)
		$progressStack.Children.Add($progressBar) | Out-Null

		# Sub-task progress bar (shown only when a tweak function reports its own progress)
		$subProgressBar = New-Object System.Windows.Controls.ProgressBar
		$subProgressBar.Minimum = 0
		$subProgressBar.Maximum = 100
		$subProgressBar.Value = 0
		$subProgressBar.Height = 8
		$subProgressBar.Margin = [System.Windows.Thickness]::new(0,0,12,2)
		$subProgressBar.Opacity = 0.75
		$subProgressBar.Visibility = [System.Windows.Visibility]::Collapsed
		$progressStack.Children.Add($subProgressBar) | Out-Null

		$subProgressText = New-Object System.Windows.Controls.TextBlock
		$subProgressText.FontSize = 11
		$subProgressText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.AccentBlue)
		$subProgressText.Margin = [System.Windows.Thickness]::new(0,0,0,2)
		$subProgressText.Visibility = [System.Windows.Visibility]::Collapsed
		$progressStack.Children.Add($subProgressText) | Out-Null

		$progressText = New-Object System.Windows.Controls.TextBlock
		$progressText.FontSize = 12
		$progressText.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
		$progressText.Text = 'Preparing run...'
		$progressStack.Children.Add($progressText) | Out-Null
		$progressGrid.Children.Add($progressStack) | Out-Null

		$abortBtn = New-Object System.Windows.Controls.Button
		$abortBtn.Content = 'Abort'
		$abortBtn.Padding = [System.Windows.Thickness]::new(14,8,14,8)
		$abortBtn.Margin = [System.Windows.Thickness]::new(8,0,0,0)
		$abortBtn.Cursor = [System.Windows.Input.Cursors]::Hand
		[System.Windows.Controls.Grid]::SetColumn($abortBtn, 1)
		$abortBtn.Add_Click({ Request-RunAbort }.GetNewClosure())
		$progressGrid.Children.Add($abortBtn) | Out-Null

		$topPanel.Children.Add($progressGrid) | Out-Null
		$outerGrid.Children.Add($topPanel) | Out-Null

		# Bottom section: scrollable log box (fills remaining space)
		$logBox = New-Object System.Windows.Controls.TextBox
		$logBox.IsReadOnly = $true
		$logBox.AcceptsReturn = $true
		$logBox.TextWrapping = 'Wrap'
		$logBox.VerticalScrollBarVisibility = 'Auto'
		$logBox.HorizontalScrollBarVisibility = 'Disabled'
		$logBox.BorderThickness = [System.Windows.Thickness]::new(0)
		$logBox.Padding = [System.Windows.Thickness]::new(12)
		$logBox.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
		$logBox.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$logBox.FontFamily = 'Consolas'
		$logBox.FontSize = 12
		[System.Windows.Controls.Grid]::SetRow($logBox, 1)
		$outerGrid.Children.Add($logBox) | Out-Null

		# Disable outer ScrollViewer scrolling — the logBox handles its own
		$ContentScroll.VerticalScrollBarVisibility = 'Disabled'
		$ContentScroll.Content = $outerGrid
		$Script:ExecutionLogBox = $logBox
		$Script:ExecutionLastConsoleAction = $null
		$Script:ExecutionProgressBar = $progressBar
		$Script:ExecutionProgressText = $progressText
		$Script:ExecutionSubProgressBar = $subProgressBar
		$Script:ExecutionSubProgressText = $subProgressText
		$Script:ExecutionProgressIndeterminate = $true
		$Script:AbortRunButton = $abortBtn
		$Script:AbortRequested = $false
		& $updateProgressFn -Completed 0 -Total 0 -CurrentAction 'Preparing run...' -Indeterminate $true
	}

	function Exit-ExecutionView
	{
		$Script:ExecutionLogBox = $null
		$Script:ExecutionLastConsoleAction = $null
		$Script:ExecutionProgressBar = $null
		$Script:ExecutionProgressText = $null
		$Script:ExecutionSubProgressBar = $null
		$Script:ExecutionSubProgressText = $null
		$Script:ExecutionProgressIndeterminate = $false
		$Script:AbortRunButton = $null
		$Script:AbortRequested = $false
		$Script:ExecutionPreviousContent = $null

		# Restore the outer ScrollViewer scrolling mode
		$ContentScroll.VerticalScrollBarVisibility = 'Auto'

		if ($Script:CurrentPrimaryTab)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	}

	function Invoke-GuiSystemScan
	{
		$Script:ScanEnabled = $true
		$StatusText.Text = "Scanning system state..."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		$Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

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
	# Applied-this-session tracking for system scan
	$Script:AppliedTweaks = [System.Collections.Generic.HashSet[string]]::new()
	function New-PresetButton
	{
		param(
			[string]$Label,
			[string]$BackgroundColor = $null
		)

		$bc = [System.Windows.Media.BrushConverter]::new()
		$button = New-Object System.Windows.Controls.Button
		$button.Content = $Label
		$button.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
		$button.Margin = [System.Windows.Thickness]::new(4, 0, 4, 0)
		$button.MinWidth = 170
		$button.Cursor = [System.Windows.Input.Cursors]::Hand
		$button.FontSize = 12
		$button.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)

		$tmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
		$bd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$bd.Name = "Bd"
		$bd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(4))
		$bd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(18, 10, 18, 10))
		$bd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($(if ($BackgroundColor) { $BackgroundColor } else { $Script:CurrentTheme.TabBg })))
		$bd.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $bc.ConvertFromString($Script:CurrentTheme.BorderColor))
		$bd.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
		$cp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$cp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$bd.AppendChild($cp)
		$tmpl.VisualTree = $bd
		$button.Template = $tmpl

		return $button
	}
	$syncLinkedState = {
		param (
			[string]$TargetFunction,
			[bool]$IsChecked
		)

		if ([string]::IsNullOrWhiteSpace($TargetFunction)) { return }

		$fidx = $Script:FunctionToIndex[$TargetFunction]
		if ($null -eq $fidx) { return }

		$tctl = $Script:Controls[$fidx]
		if ($null -ne $tctl -and $tctl.PSObject.Properties["IsChecked"])
		{
			$tctl.IsChecked = $IsChecked
		}

		if ($IsChecked)
		{
			$Script:PendingLinkedUnchecks.Remove($TargetFunction) | Out-Null
			$Script:PendingLinkedChecks.Add($TargetFunction) | Out-Null
		}
		else
		{
			$Script:PendingLinkedChecks.Remove($TargetFunction) | Out-Null
			$Script:PendingLinkedUnchecks.Add($TargetFunction) | Out-Null
		}
	}

	function Build-TweakRow
	{
		param ([int]$Index, [hashtable]$Tweak)
		$bc = [System.Windows.Media.BrushConverter]::new()
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
				$card.Margin = [System.Windows.Thickness]::new(8, 3, 8, 3)
				$card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

				$grid = New-Object System.Windows.Controls.Grid
				$col1 = New-Object System.Windows.Controls.ColumnDefinition
				$col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
				$col2 = New-Object System.Windows.Controls.ColumnDefinition
				$col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
				$grid.ColumnDefinitions.Add($col1) | Out-Null
				$grid.ColumnDefinitions.Add($col2) | Out-Null

				# Left side: name + description + info icon
				$leftStack = New-Object System.Windows.Controls.StackPanel
				$leftStack.Orientation = "Vertical"
				$leftStack.VerticalAlignment = "Center"
				[System.Windows.Controls.Grid]::SetColumn($leftStack, 0)

				$nameRow = New-Object System.Windows.Controls.StackPanel
				$nameRow.Orientation = "Horizontal"

				$cb = New-Object System.Windows.Controls.CheckBox
				$cb.VerticalAlignment = "Center"
				$cb.IsChecked = [bool]$Tweak.Default
				$cb.Tag = $Index
				$cb.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameRow.Children.Add($cb) | Out-Null

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 13
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameTxt.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
				$nameRow.Children.Add($nameTxt) | Out-Null

				$nameRow.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameRow.Children.Add((New-ImpactBadge)) | Out-Null
				}

				$leftStack.Children.Add($nameRow) | Out-Null

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = if ($Tweak.Description) { $Tweak.Description } else { "Turns this feature on when checked and off when unchecked." }
				$descTxt.FontSize = 11
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				$descTxt.Margin = [System.Windows.Thickness]::new(24, 2, 8, 0)
				$descTxt.TextWrapping = "Wrap"
				$leftStack.Children.Add($descTxt) | Out-Null

				# Status label showing Enabled/Disabled
				$statusLbl = New-Object System.Windows.Controls.TextBlock
				$statusLbl.FontSize = 11
				$statusLbl.Margin = [System.Windows.Thickness]::new(24, 4, 0, 0)
				# Capture colors as local strings; avoids empty-string error if $Script:CurrentTheme is null at closure-invocation time
				$onColorCapture  = if ($Script:CurrentTheme -and $Script:CurrentTheme.ToggleOn)  { $Script:CurrentTheme.ToggleOn  } else { '#A6E3A1' }
				$offColorCapture = if ($Script:CurrentTheme -and $Script:CurrentTheme.ToggleOff) { $Script:CurrentTheme.ToggleOff } else { '#F38BA8' }
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

				$leftStack.Children.Add($statusLbl) | Out-Null

				# Wire up checkbox change to update status label (uses captured local color strings)
				$statusLblCapture = $statusLbl
				$cb.Add_Checked({
					$statusLblCapture.Text = "Enabled"
					$statusLblCapture.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($onColorCapture)
				}.GetNewClosure())
				$cb.Add_Unchecked({
					$statusLblCapture.Text = "Disabled"
					$statusLblCapture.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($offColorCapture)
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

				$grid.Children.Add($leftStack) | Out-Null

				$card.Child = $grid
				# Preserve user's checked state if this control was already built on a previous tab visit
				if ($Script:Controls.ContainsKey($Index)) {
					$cb.IsChecked = $Script:Controls[$Index].IsChecked
				}
				if ($Tweak.LinkedWith)
				{
					# Sync the linked tweak after the row has restored its final checked state.
					& $syncLinkedState $Tweak.LinkedWith ([bool]$cb.IsChecked)
				}
				$Script:Controls[$Index] = $cb
				return $card
			}
			"Choice"
			{
				$card = New-Object System.Windows.Controls.Border
				$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
				$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
				$card.Margin = [System.Windows.Thickness]::new(8, 3, 8, 3)
				$card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

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

				$nameRow = New-Object System.Windows.Controls.StackPanel
				$nameRow.Orientation = "Horizontal"

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 13
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameRow.Children.Add($nameTxt) | Out-Null

				$nameRow.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameRow.Children.Add((New-ImpactBadge)) | Out-Null
				}

				$leftStack.Children.Add($nameRow) | Out-Null

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = $Tweak.Description
				$descTxt.FontSize = 11
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextMuted)
				$descTxt.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
				$descTxt.TextWrapping = "Wrap"
				$leftStack.Children.Add($descTxt) | Out-Null

				$grid.Children.Add($leftStack) | Out-Null

				# Right: ComboBox
				$combo = New-Object System.Windows.Controls.ComboBox
				$combo.MinWidth = 160
				$combo.VerticalAlignment = "Center"
				$combo.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
				$combo.Tag = $Index

				$displayOpts = if ($Tweak.DisplayOptions) { $Tweak.DisplayOptions } else { $Tweak.Options }
				$defaultIdx = -1
				for ($oi = 0; $oi -lt $Tweak.Options.Count; $oi++)
				{
					$combo.Items.Add($displayOpts[$oi]) | Out-Null
					if ($Tweak.Options[$oi] -eq $Tweak.Default) { $defaultIdx = $oi }
				}
				$combo.SelectedIndex = $defaultIdx

				[System.Windows.Controls.Grid]::SetColumn($combo, 1)
				$grid.Children.Add($combo) | Out-Null

				$card.Child = $grid
				# Preserve user's selection if this control was already built on a previous tab visit
				if ($Script:Controls.ContainsKey($Index)) {
					$combo.SelectedIndex = $Script:Controls[$Index].SelectedIndex
				}
				$Script:Controls[$Index] = $combo
				return $card
			}
			"Action"
			{
				$card = New-Object System.Windows.Controls.Border
				$card.Background = $bc.ConvertFromString($Script:CurrentTheme.CardBg)
				$card.CornerRadius = [System.Windows.CornerRadius]::new(6)
				$card.Margin = [System.Windows.Thickness]::new(8, 3, 8, 3)
				$card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)

				$nameRow = New-Object System.Windows.Controls.StackPanel
				$nameRow.Orientation = "Horizontal"

				$cb = New-Object System.Windows.Controls.CheckBox
				$cb.VerticalAlignment = "Center"
				# Apply pending linked-toggle state
				$initAct = [bool]$Tweak.Default
				if ($Script:PendingLinkedChecks.Contains($Tweak.Function))   { $initAct = $true;  $Script:PendingLinkedChecks.Remove($Tweak.Function)   | Out-Null }
				elseif ($Script:PendingLinkedUnchecks.Contains($Tweak.Function)) { $initAct = $false; $Script:PendingLinkedUnchecks.Remove($Tweak.Function) | Out-Null }
				$cb.IsChecked = $initAct
				$cb.Tag = $Index
				$cb.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameRow.Children.Add($cb) | Out-Null

				$nameTxt = New-Object System.Windows.Controls.TextBlock
				$nameTxt.Text = $Tweak.Name
				$nameTxt.FontSize = 13
				$nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
				$nameTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
				$nameTxt.VerticalAlignment = "Center"
				$nameTxt.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
				$nameRow.Children.Add($nameTxt) | Out-Null

				$nameRow.Children.Add((New-InfoIcon -TooltipText $Tweak.Description -Tweak $Tweak)) | Out-Null

				if ($Tweak.Caution)
				{
					$nameRow.Children.Add((New-ImpactBadge)) | Out-Null
				}

				$descTxt = New-Object System.Windows.Controls.TextBlock
				$descTxt.Text = if ($Tweak.Description) { $Tweak.Description } else { "Runs this action one time when selected." }
				$descTxt.FontSize = 11
				$descTxt.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)
				$descTxt.Margin = [System.Windows.Thickness]::new(24, 2, 8, 0)
				$descTxt.TextWrapping = "Wrap"
				$nameRowWithDesc = New-Object System.Windows.Controls.StackPanel
				$nameRowWithDesc.Orientation = "Vertical"
				$nameRowWithDesc.Children.Add($nameRow) | Out-Null
				$nameRowWithDesc.Children.Add($descTxt) | Out-Null

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

				$card.Child = $nameRowWithDesc
				# Preserve user's checked state if this control was already built on a previous tab visit
				if ($Script:Controls.ContainsKey($Index)) {
					$cb.IsChecked = $Script:Controls[$Index].IsChecked
				}
				if ($Tweak.LinkedWith)
				{
					# Sync the linked tweak after the row has restored its final checked state.
					& $syncLinkedState $Tweak.LinkedWith ([bool]$cb.IsChecked)
				}
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

	function Build-TabContent
	{
		param ([string]$PrimaryTab)
		$Script:CurrentPrimaryTab = $PrimaryTab
		$bc = [System.Windows.Media.BrushConverter]::new()

		# Gather all manifest indexes for this primary tab
		$catTweaks = [ordered]@{}
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$t = $Script:TweakManifest[$i]
			$primTab = $CategoryToPrimary[$t.Category]
			if ($primTab -ne $PrimaryTab) { continue }

			# Determine sub-category
			$subCat = if ($t.SubCategory) { $t.SubCategory } elseif ($t.Category -ne $PrimaryTab) { $t.Category } else { "" }
			if (-not $catTweaks.Contains($subCat)) { $catTweaks[$subCat] = @() }
			$catTweaks[$subCat] += $i
		}

		$mainPanel = New-Object System.Windows.Controls.StackPanel
		$mainPanel.Orientation = "Vertical"
		$mainPanel.Background = $bc.ConvertFromString($Script:CurrentTheme.PanelBg)

		$presetHeader = New-Object System.Windows.Controls.TextBlock
		$presetHeader.Text = 'Recommended Selections:'
		$presetHeader.FontSize = 13
		$presetHeader.Foreground = $bc.ConvertFromString($Script:CurrentTheme.AccentHover)
		$presetHeader.Margin = [System.Windows.Thickness]::new(12, 12, 12, 6)
		$mainPanel.Children.Add($presetHeader) | Out-Null

		$presetBar = New-Object System.Windows.Controls.WrapPanel
		$presetBar.Orientation = 'Horizontal'
		$presetBar.Margin = [System.Windows.Thickness]::new(8, 0, 8, 8)

		$btnStandard = New-PresetButton -Label 'Standard' -BackgroundColor $Script:CurrentTheme.TabActiveBg
		$manifestRef = $Script:TweakManifest
		$controlsRef = $Script:Controls
		$pendingChecksRef = $Script:PendingLinkedChecks
		$pendingUnchecksRef = $Script:PendingLinkedUnchecks
		$statusTextRef = $StatusText
		$currentThemeRef = $Script:CurrentTheme
		$btnStandard.Add_Click({
			$pendingChecksRef.Clear()
			$pendingUnchecksRef.Clear()
			$Script:ScanEnabled = $false

			for ($pi = 0; $pi -lt $manifestRef.Count; $pi++)
			{
				$tweak = $manifestRef[$pi]
				$ctl = $controlsRef[$pi]
				if (-not $ctl) { continue }

				$isVisible = $true
				if ($tweak.VisibleIf)
				{
					try { $isVisible = [bool](& $tweak.VisibleIf) } catch { $isVisible = $false }
				}
				$ctl.IsEnabled = $isVisible
				if (-not $isVisible)
				{
					if ($ctl.PSObject.Properties['IsChecked']) { $ctl.IsChecked = $false }
					elseif ($ctl.PSObject.Properties['SelectedIndex']) { $ctl.SelectedIndex = -1 }
					continue
				}

				switch ($tweak.Type)
				{
					'Toggle'
					{
						$ctl.IsChecked = [bool]$tweak.Default
					}
					'Action'
					{
						$ctl.IsChecked = [bool]$tweak.Default
					}
					'Choice'
					{
						$ctl.SelectedIndex = [array]::IndexOf($tweak.Options, $tweak.Default)
					}
				}
			}

			$statusTextRef.Text = 'Standard selections loaded.'
			$statusTextRef.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($currentThemeRef.AccentBlue)
		}.GetNewClosure())
		$presetBar.Children.Add($btnStandard) | Out-Null

		$btnScan = New-PresetButton -Label 'System Scan' -BackgroundColor $Script:CurrentTheme.TabBg
		$chkScanRef = $ChkScan
		$btnScan.Add_Click({
			$chkScanRef.IsChecked = $true
		}.GetNewClosure())
		$presetBar.Children.Add($btnScan) | Out-Null

		$mainPanel.Children.Add($presetBar) | Out-Null

		# Collect all manifest indexes for this tab (for Select/Unselect All)
		$allTabIndexes = @()
		foreach ($subKey in $catTweaks.Keys) { $allTabIndexes += $catTweaks[$subKey] }

		# Select All / Unselect All buttons
		$selectionBar = New-Object System.Windows.Controls.WrapPanel
		$selectionBar.Orientation = "Horizontal"
		$selectionBar.Margin = [System.Windows.Thickness]::new(8, 8, 8, 2)

		$btnSelectAll = New-Object System.Windows.Controls.Button
		$btnSelectAll.Content = "Select All"
		$btnSelectAll.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
		$btnSelectAll.Margin = [System.Windows.Thickness]::new(2, 2, 2, 2)
		$btnSelectAll.Cursor = [System.Windows.Input.Cursors]::Hand
		$btnSelectAll.FontSize = 11
		$btnSelectAll.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$selAllTmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
		$selAllBd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$selAllBd.Name = "Bd"
		$selAllBd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(4))
		$selAllBd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(12, 4, 12, 4))
		$selAllBd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($Script:CurrentTheme.TabBg))
		$selAllCp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$selAllCp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$selAllBd.AppendChild($selAllCp)
		$selAllTmpl.VisualTree = $selAllBd
		$btnSelectAll.Template = $selAllTmpl

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

		$btnUnselectAll = New-Object System.Windows.Controls.Button
		$btnUnselectAll.Content = "Unselect All"
		$btnUnselectAll.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
		$btnUnselectAll.Margin = [System.Windows.Thickness]::new(2, 2, 2, 2)
		$btnUnselectAll.Cursor = [System.Windows.Input.Cursors]::Hand
		$btnUnselectAll.FontSize = 11
		$btnUnselectAll.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextPrimary)
		$unselAllTmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
		$unselAllBd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
		$unselAllBd.Name = "Bd"
		$unselAllBd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(4))
		$unselAllBd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(12, 4, 12, 4))
		$unselAllBd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($Script:CurrentTheme.TabBg))
		$unselAllCp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
		$unselAllCp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
		$unselAllBd.AppendChild($unselAllCp)
		$unselAllTmpl.VisualTree = $unselAllBd
		$btnUnselectAll.Template = $unselAllTmpl

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

		# Build all sub-sections
		foreach ($subKey in $catTweaks.Keys)
		{
			$indexes = $catTweaks[$subKey]

			if ($subKey -ne "" -and $catTweaks.Count -gt 1)
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
	}
	#endregion

	# Activate the main window normally on first show so it appears in front once ready.
	$Form.ShowActivated = $true
	$Script:RunInProgress = $false

	# Hide the console immediately — it will only reappear when Run Tweaks is clicked
	Hide-ConsoleWindow

	$Form.Add_Closing({
		param($windowSource, $e)
		if ($Script:RunInProgress)
		{
			$e.Cancel = $true
			Request-RunAbort
		}
	})

	#region Build primary tabs
	foreach ($pKey in $PrimaryCategories.Keys)
	{
		# Check if any tweaks exist for this primary tab
		$hasTweaks = $false
		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			if ($CategoryToPrimary[$Script:TweakManifest[$i].Category] -eq $pKey) { $hasTweaks = $true; break }
		}
		if (-not $hasTweaks) { continue }

		$tabItem = New-Object System.Windows.Controls.TabItem
		$tabItem.Header = $pKey
		$tabItem.Tag = $pKey
		$tabItem.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.TextPrimary)
		$tabItem.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.TabBg)
		$tabItem.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
		$PrimaryTabs.Items.Add($tabItem) | Out-Null
	}

	$PrimaryTabs.Add_SelectionChanged({
		$e = $args[1]
		if ($e.Source -ne $PrimaryTabs) { return }
		$selected = $PrimaryTabs.SelectedItem
		if ($selected -and $selected.Tag)
		{
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

	#region Theme toggle handler
	$ChkTheme.Add_Checked({
		Set-GUITheme -Theme $Script:LightTheme
	})
	$ChkTheme.Add_Unchecked({
		Set-GUITheme -Theme $Script:DarkTheme
	})
	#endregion

	#region Button handlers
	$BtnRun.Add_Click({
		$Global:Error.Clear()
		$StatusText.Text = "Running selected tweaks..."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.AccentBlue)
		$Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

		Stop-Foreground
		$Script:RunInProgress = $true
		$PrimaryTabs.IsEnabled = $false
		$BtnRun.IsEnabled = $false
		$BtnDefaults.IsEnabled = $false
		$ChkScan.IsEnabled = $false
		$ChkTheme.IsEnabled = $false
		Enter-ExecutionView -Title 'Running Selected Tweaks'
		$Script:AbortRequested = $false

		# Build a plain-data snapshot of tweaks to run.
		# WPF control references cannot cross the runspace boundary, so we capture only values.
		$tweakList = [System.Collections.Generic.List[hashtable]]::new()
		for ($ri = 0; $ri -lt $Script:TweakManifest.Count; $ri++)
		{
			$rt   = $Script:TweakManifest[$ri]
			$rctl = $Script:Controls[$ri]
			if (-not $rctl -or -not $rctl.IsEnabled) { continue }
			switch ($rt.Type)
			{
				'Toggle'
				{
					if ($rctl.IsChecked)
					{
						$tweakList.Add(@{ Name=$rt.Name; Function=$rt.Function; Type='Toggle'; OnParam=$rt.OnParam; ExtraArgs=$null })
					}
				}
				'Choice'
				{
					$selIdx = $rctl.SelectedIndex
					if ($selIdx -ge 0)
					{
						$tweakList.Add(@{ Name=$rt.Name; Function=$rt.Function; Type='Choice'; Value=$rt.Options[$selIdx]; ExtraArgs=$rt.ExtraArgs })
					}
				}
				'Action'
				{
					if ($rctl.IsChecked)
					{
						$tweakList.Add(@{ Name=$rt.Name; Function=$rt.Function; Type='Action'; ExtraArgs=$rt.ExtraArgs })
					}
				}
			}
		}
		$totalRunnableTweaks = $tweakList.Count
		$Script:CurrentTweakDisplayName = $null
		& $updateProgressFn -Completed 0 -Total $totalRunnableTweaks -CurrentAction 'Preparing run...' -Indeterminate ($totalRunnableTweaks -gt 0)

		# Shared state for cross-thread communication.
		# LogQueue receives PSCustomObject entries from the background thread;
		# the DispatcherTimer drains it on the UI thread.
		$runState = [hashtable]::Synchronized(@{
			AbortRequested   = $false
			AbortRequestedAt = [datetime]::MinValue
			Done             = $false
			AbortedRun       = $false
			CompletedCount   = 0
			QueuedCompletedCount = 0
			ErrorCount       = 0
			ForceStopIssued  = $false
			CurrentTweak     = ''
			LogQueue         = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
			AppliedFunctions = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
		})

		# Log-append helper — called on the UI thread only (DispatcherTimer tick).
		# Uses only $Script: variables so no $Form closure capture is needed.
		$appendLogFn = {
			param($Text, $Level = 'INFO')
			if (-not $Script:ExecutionLogBox) { return }
			$cleanText = ($Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
			if ([string]::IsNullOrWhiteSpace($cleanText)) { return }
			$Script:ExecutionLogBox.AppendText(("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $cleanText) + [Environment]::NewLine)
			$vO = $Script:ExecutionLogBox.VerticalOffset
			$vH = $Script:ExecutionLogBox.ViewportHeight
			$eH = $Script:ExecutionLogBox.ExtentHeight
			if (($vO + $vH) -ge ($eH - 30)) { $Script:ExecutionLogBox.ScrollToEnd() }
		}

		# Queue-entry drain helper — processes a single entry dequeued from $runState['LogQueue'].
		# GetNewClosure captures $appendLogFn, $updateProgressFn, $runState, $totalRunnableTweaks.
		# Named functions are NOT captured by GetNewClosure — only variables are.
		$drainEntry = {
			param($entry)
			switch ($entry.Kind)
			{
				'Log'
				{
					return
				}
				'_TweakStarted'
				{
					$runState['CurrentTweak'] = $entry.Name
					$Script:ExecutionLastConsoleAction = $null
					# Clear any leftover sub-progress from the previous tweak
					& $updateProgressFn -Completed $runState['CompletedCount'] -Total $totalRunnableTweaks -CurrentAction $entry.Name -ClearSub $true
				}
				'_TweakCompleted'
				{
					$completedStatus = if ([string]::IsNullOrWhiteSpace($entry.Status)) { 'success' } else { $entry.Status.ToLowerInvariant() }
					$completedName = ($entry.Name -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					if ($entry.PSObject.Properties['Count'])
					{
						$runState['QueuedCompletedCount'] = [int]$entry.Count
					}
					if (-not [string]::IsNullOrWhiteSpace($completedName))
					{
						& $appendLogFn "$completedName - $completedStatus" $(if ($completedStatus -eq 'failed') { 'ERROR' } elseif ($completedStatus -eq 'warning') { 'WARNING' } else { 'INFO' })
					}
					$Script:ExecutionLastConsoleAction = $null
					# Clear sub-progress on tweak completion and advance main bar
					& $updateProgressFn -Completed $runState['QueuedCompletedCount'] -Total $totalRunnableTweaks -CurrentAction $completedName -ClearSub $true
				}
				'_TweakFailed'
				{
					if (-not [string]::IsNullOrWhiteSpace($entry.Error))
					{
						& $appendLogFn ("[ERROR] {0}" -f $entry.Error) 'ERROR'
					}
					LogError ("Failed to execute {0}: {1}" -f $entry.Name, $entry.Error)
					& $updateProgressFn -Completed $runState['CompletedCount'] -Total $totalRunnableTweaks -CurrentAction $runState['CurrentTweak'] -Indeterminate ($runState['CompletedCount'] -lt $totalRunnableTweaks)
				}
				'_RunError'
				{
					& $appendLogFn "Fatal run error: $($entry.Error)" 'ERROR'
					LogError "Fatal run error: $($entry.Error)"
				}
				'_RunNotice'
				{
					$noticeLevel = if ([string]::IsNullOrWhiteSpace($entry.Level)) { 'WARNING' } else { $entry.Level.ToUpperInvariant() }
					& $appendLogFn $entry.Message $noticeLevel
				}
				'ConsoleAction'
				{
					$cleanAct = ($entry.Action -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					$Script:ExecutionLastConsoleAction = $cleanAct
					& $updateProgressFn -Completed $runState['CompletedCount'] -Total $totalRunnableTweaks -CurrentAction $cleanAct -Indeterminate ($runState['CompletedCount'] -lt $totalRunnableTweaks)
				}
				'ConsoleStatus'
				{
					$mStat = switch ($entry.Status) {
						'success' { 'success' }
						'warning' { 'warning' }
						default { 'failed' }
					}
					$fb = if ($Script:ExecutionLastConsoleAction) { $Script:ExecutionLastConsoleAction } `
					      elseif ($runState['CurrentTweak']) { $runState['CurrentTweak'] } else { $null }
					& $appendLogFn (if ($fb) { "$fb - $mStat" } else { $mStat }) $(if ($mStat -eq 'failed') { 'ERROR' } elseif ($mStat -eq 'warning') { 'WARNING' } else { 'INFO' })
					$Script:ExecutionLastConsoleAction = $null
				}
				'ConsoleComplete'
				{
					$mStat = switch ($entry.Status) {
						'success' { 'success' }
						'warning' { 'warning' }
						default { 'failed' }
					}
					$cleanAct = ($entry.Action -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
					& $appendLogFn "$cleanAct - $mStat" $(if ($mStat -eq 'failed') { 'ERROR' } elseif ($mStat -eq 'warning') { 'WARNING' } else { 'INFO' })
					$Script:ExecutionLastConsoleAction = $null
				}
				'_SubProgress'
				{
					# A tweak function reporting its own internal progress (e.g. a download).
					# Fields: Action (string), Completed (int), Total (int), Percent (int, optional)
					$subAct   = if ($entry.PSObject.Properties['Action'])    { $entry.Action }    else { $null }
					$subComp  = if ($entry.PSObject.Properties['Completed']) { [int]$entry.Completed } else { 0 }
					$subTot   = if ($entry.PSObject.Properties['Total'])     { [int]$entry.Total }     else { 0 }
					$subPct   = if ($entry.PSObject.Properties['Percent'])   { [int]$entry.Percent }   else { -1 }
					# If caller supplied Percent but no Total, synthesise a 100-point scale
					if ($subTot -le 0 -and $subPct -ge 0)
					{
						$subComp = $subPct
						$subTot  = 100
					}
					& $updateProgressFn `
						-Completed $runState['QueuedCompletedCount'] `
						-Total     $totalRunnableTweaks `
						-SubCompleted $subComp `
						-SubTotal     $subTot `
						-SubAction    $subAct
				}
			}
		}.GetNewClosure()

		# Register the main-session UILogHandler so any LogInfo/LogError on the UI thread
		# before the background runspace starts are also queued (silently ignored by drain).
		Set-UILogHandler { param($entry) $runState['LogQueue'].Enqueue($entry) }

		LogInfo "Starting tweak execution (mode: Run)"

		# Background runspace — initialize it like the normal script path, then execute tweaks.
		# The UI thread remains free, so the Abort button and all controls respond instantly.
		$bgModuleDir   = Split-Path $PSScriptRoot -Parent   # Module/
		$bgLoaderPath  = Join-Path $bgModuleDir 'Win10_11Util.psm1'
		$bgRootDir     = Split-Path $bgModuleDir -Parent
		$bgLocDir      = Join-Path $bgRootDir 'Localizations'
		$bgUICulture   = $PSUICulture
		$bgLogFilePath = $Global:LogFilePath

		$bgRunspace = [runspacefactory]::CreateRunspace()
		$bgRunspace.ApartmentState = 'STA'
		$bgRunspace.ThreadOptions  = 'ReuseThread'
		$bgRunspace.Open()
		$bgRunspace.SessionStateProxy.SetVariable('runState',      $runState)
		$bgRunspace.SessionStateProxy.SetVariable('tweakList',     $tweakList)
		$bgRunspace.SessionStateProxy.SetVariable('bgLoaderPath',  $bgLoaderPath)
		$bgRunspace.SessionStateProxy.SetVariable('bgLocDir',      $bgLocDir)
		$bgRunspace.SessionStateProxy.SetVariable('bgUICulture',   $bgUICulture)
		$bgRunspace.SessionStateProxy.SetVariable('bgLogFilePath', $bgLogFilePath)
		# Expose the log queue as $Global:GUIRunState so Report-TweakProgress (called from
		# inside tweak functions) can enqueue _SubProgress messages without needing a direct
		# reference to $runState.
		$bgRunspace.SessionStateProxy.SetVariable('GUIRunState',   $runState['LogQueue'])

		$bgPS = [powershell]::Create().AddScript({
			try
			{
				# Match the normal script initialization as closely as possible.
				$Global:GUIMode = $true
				try
				{
					Import-LocalizedData -BindingVariable Global:Localization -UICulture $bgUICulture -BaseDirectory $bgLocDir -FileName Win10_11Util -ErrorAction Stop
				}
				catch
				{
					Import-LocalizedData -BindingVariable Global:Localization -UICulture en-US -BaseDirectory $bgLocDir -FileName Win10_11Util
				}

				Import-Module $bgLoaderPath -Force -Global -ErrorAction Stop
				$global:LogFilePath = $bgLogFilePath
				Set-LogFile -Path $bgLogFilePath
				# Wire log handler — must only enqueue, never touch WPF from background thread
				Set-UILogHandler { param($entry) $runState['LogQueue'].Enqueue($entry) }

				$missingFunctions = @(
					$tweakList |
						ForEach-Object { $_.Function } |
						Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
						Select-Object -Unique |
						Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) }
				)
				if ($missingFunctions.Count -gt 0)
				{
					throw ("Required tweak functions were not loaded: {0}" -f ($missingFunctions -join ', '))
				}

				foreach ($tweak in $tweakList)
				{
					if ($runState['AbortRequested']) { $runState['AbortedRun'] = $true; break }
					$runState['CurrentTweak'] = $tweak.Name
					$runState['LogQueue'].Enqueue([PSCustomObject]@{
						Kind = '_TweakStarted'
						Name = $tweak.Name
					})
					try
					{
						$tweakCommand = Get-Command -Name $tweak.Function -ErrorAction SilentlyContinue
						if (-not $tweakCommand)
						{
							throw "The tweak function '$($tweak.Function)' is not available in the current session."
						}

						switch ($tweak.Type)
						{
							'Toggle'
							{
								$splat = @{ $tweak.OnParam = $true }
								& $tweakCommand @splat
							}
							'Choice'
							{
								$splat = @{ $tweak.Value = $true }
								if ($tweak.ExtraArgs)
								{
									$tweak.ExtraArgs.GetEnumerator() | ForEach-Object { $splat[$_.Key] = $_.Value }
								}
								& $tweakCommand @splat
							}
							'Action'
							{
								if ($tweak.ExtraArgs) { $argSplat = $tweak.ExtraArgs; & $tweakCommand @argSplat }
								else { & $tweakCommand }
							}
						}
						$runState['AppliedFunctions'].Add($tweak.Function)
						$runState['CompletedCount'] = [int]$runState['CompletedCount'] + 1
						$runState['LogQueue'].Enqueue([PSCustomObject]@{
							Kind   = '_TweakCompleted'
							Name   = $tweak.Name
							Status = 'success'
							Count  = $runState['CompletedCount']
						})
					}
					catch
					{
						$runState['LogQueue'].Enqueue([PSCustomObject]@{
							Kind  = '_TweakFailed'
							Name  = $tweak.Name
							Error = $_.Exception.Message
						})
						$runState['ErrorCount'] = [int]$runState['ErrorCount'] + 1
						$runState['CompletedCount'] = [int]$runState['CompletedCount'] + 1
						$runState['LogQueue'].Enqueue([PSCustomObject]@{
							Kind   = '_TweakCompleted'
							Name   = $tweak.Name
							Status = 'failed'
							Count  = $runState['CompletedCount']
						})
					}
				}

				if (-not $runState['AbortedRun'])
				{
					PostActions
					Errors
				}
				else
				{
					LogWarning "Run aborted by user before all selected tweaks finished."
				}
				Stop-Foreground
			}
			catch
			{
				$runState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind  = '_RunError'
					Error = $_.Exception.Message
				})
			}
			finally
			{
				$runState['Done'] = $true
			}
		})
		$bgPS.Runspace = $bgRunspace
		$bgAsync = $bgPS.BeginInvoke()

		# DispatcherTimer fires every 100 ms on the UI thread.
		# Drains the log queue and updates the progress bar while tweaks run in background.
		# The UI never blocks, so Abort and all other controls respond instantly.
		$runTimer = New-Object System.Windows.Threading.DispatcherTimer
		$runTimer.Interval = [TimeSpan]::FromMilliseconds(100)
		$runTimer.Add_Tick({
			# Propagate the UI-thread abort flag into shared state so the background runspace stops.
			if ($Script:AbortRequested -and -not $runState['AbortRequested'])
			{
				$runState['AbortRequested'] = $true
				$runState['AbortRequestedAt'] = Get-Date
			}

			# If a running tweak does not yield after an abort request, stop the background pipeline.
			if (
				$runState['AbortRequested'] -and
				-not $runState['Done'] -and
				-not $runState['ForceStopIssued'] -and
				$runState['AbortRequestedAt'] -ne [datetime]::MinValue -and
				((Get-Date) - $runState['AbortRequestedAt']).TotalSeconds -ge 2
			)
			{
				$runState['ForceStopIssued'] = $true
				$runState['AbortedRun'] = $true
				$runState['LogQueue'].Enqueue([PSCustomObject]@{
					Kind = '_RunNotice'
					Level = 'WARNING'
					Message = 'Abort requested - stopping the current operation now.'
				})
				try { $bgPS.Stop() } catch { $null = $_ }
			}

			# Drain the log queue
			$qEntry = $null
			while ($runState['LogQueue'].TryDequeue([ref]$qEntry)) { & $drainEntry $qEntry }

			# Pulse progress bar with latest completed count
			if ($runState['CurrentTweak'])
			{
				$displayCompleted = [Math]::Max([int]$runState['QueuedCompletedCount'], [int]$runState['CompletedCount'])
				& $updateProgressFn -Completed $displayCompleted -Total $totalRunnableTweaks -CurrentAction $runState['CurrentTweak']
			}

			if (-not $bgAsync.IsCompleted -and -not $runState['Done']) { return }

			# === Background run finished ===
			$runTimer.Stop()

			# Final drain — cover any entries enqueued between the last Tick and Done = $true
			$qEntry = $null
			while ($runState['LogQueue'].TryDequeue([ref]$qEntry)) { & $drainEntry $qEntry }

			# Clean up background runspace resources
			try { $bgPS.EndInvoke($bgAsync) } catch { $null = $_ }
			try { $bgPS.Dispose() } catch { $null = $_ }
			try { $bgRunspace.Close(); $bgRunspace.Dispose() } catch { $null = $_ }

			# Transfer applied-function tracking to the main session's set
			foreach ($fn in $runState['AppliedFunctions']) { $Script:AppliedTweaks.Add($fn) | Out-Null }

			# Restore UI state
			Clear-UILogHandler
			$Script:RunInProgress = $false
			$Script:CurrentTweakDisplayName = $null
			$PrimaryTabs.IsEnabled = $true
			$BtnRun.IsEnabled = $true
			$BtnDefaults.IsEnabled = $true
			$ChkScan.IsEnabled = $true
			$ChkTheme.IsEnabled = $true

			$completedCount = [Math]::Max([int]$runState['QueuedCompletedCount'], [int]$runState['CompletedCount'])
			$abortedRun     = $runState['AbortedRun']
			$logPath = $Global:LogFilePath
			$stats   = Get-LogStatistics

			& $updateProgressFn -Completed $completedCount -Total $totalRunnableTweaks -CurrentAction (if ($abortedRun) { 'Aborted' } else { 'Completed' }) -Indeterminate $false
			$StatusText.Text = if ($abortedRun) {
				"Run aborted. Completed $completedCount of $totalRunnableTweaks. Errors: $($stats.ErrorCount). Choose whether to return to tweaks or exit."
			} else {
				"Run complete. Completed $completedCount of $totalRunnableTweaks. Errors: $($stats.ErrorCount). Choose whether to return to tweaks or exit."
			}
			$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($abortedRun) { $Script:CurrentTheme.CautionText } else { $Script:CurrentTheme.ToggleOn }))

			$dlgTitle = if ($abortedRun) { 'Run Aborted' } else { 'Run Complete' }
			$dlgMsg = if ($abortedRun) {
				"The run was aborted.`n`nCompleted $completedCount of $totalRunnableTweaks tweaks. Errors: $($stats.ErrorCount)."
			} else {
				"Selected tweaks have finished running.`n`nCompleted $completedCount of $totalRunnableTweaks. Errors: $($stats.ErrorCount)."
			}
			if ($logPath) { $dlgMsg += "`n`nLog file:`n$logPath" }

			$nextStep = Show-ThemedDialog -Title $dlgTitle -Message $dlgMsg `
				-Buttons @('Return to Tweaks', 'Exit') `
				-AccentButton 'Return to Tweaks'

			if ($nextStep -eq 'Return to Tweaks')
			{
				Exit-ExecutionView
				$ChkScan.IsChecked = $true
				Invoke-GuiSystemScan
			}
			else
			{
				$Form.Close()
			}
		}.GetNewClosure())
		$runTimer.Start()
	})

	$BtnDefaults.Add_Click({
		# Confirmation dialog for destructive action
		$result = Show-ThemedDialog -Title 'Restore to Windows Defaults' `
			-Message "This will reset ALL tweaks to their Windows default values.`n`nThis is a destructive action that undoes all customizations.`nAre you sure you want to continue?" `
			-Buttons @('Cancel', 'Restore Defaults') `
			-DestructiveButton 'Restore Defaults'
		if ($result -ne 'Restore Defaults') { return }

		$StatusText.Text = "Resetting to Windows defaults..."
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.CautionText)
		$Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

		Stop-Foreground

		$Script:RunInProgress = $true
		$Form.Dispatcher.Invoke([Action]{ $Form.WindowState = [System.Windows.WindowState]::Minimized }, [System.Windows.Threading.DispatcherPriority]::Render)
		$Form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})

		LogInfo "Starting tweak execution (mode: Defaults)"

		for ($i = 0; $i -lt $Script:TweakManifest.Count; $i++)
		{
			$t = $Script:TweakManifest[$i]
			$ctl = $Script:Controls[$i]
			if (-not $ctl) { continue }

			try
			{
				switch ($t.Type)
				{
					"Toggle"
					{
						$param = if ($t.WinDefault) { $t.OnParam } else { $t.OffParam }
						$splat = @{ $param = $true }
						& $t.Function @splat
					}
					"Choice"
					{
						if (-not [string]::IsNullOrEmpty($t.WinDefault))
						{
							$splat = @{ $t.WinDefault = $true }
							if ($t.ExtraArgs)
							{
								foreach ($key in $t.ExtraArgs.Keys) { $splat[$key] = $t.ExtraArgs[$key] }
							}
							& $t.Function @splat
						}
					}
					"Action"
					{
						if ($t.WinDefault)
						{
							if ($t.ExtraArgs) { $argSplat = $t.ExtraArgs; & $t.Function @argSplat }
							else { & $t.Function }
						}
					}
				}
			}
			catch
			{
				LogError ("Failed to execute {0}: {1}" -f $t.Function, $_.Exception.Message)
			}
		}

		Stop-Foreground

		PostActions
		Errors

		# Restore GUI
		$Script:RunInProgress = $false
		$Form.Dispatcher.Invoke([Action]{
			$Form.WindowState = [System.Windows.WindowState]::Normal
			$Form.Activate() | Out-Null
		}, [System.Windows.Threading.DispatcherPriority]::Render)

		# Reset all controls to Windows defaults after run
		foreach ($ctlKey in $Script:Controls.Keys)
		{
			$ctl = $Script:Controls[$ctlKey]
			$twk = $Script:TweakManifest[$ctlKey]
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

		$logPath2 = $Global:LogFilePath
		if ($logPath2 -and (Test-Path -LiteralPath $logPath2 -ErrorAction SilentlyContinue))
		{
			$StatusText.Text = "Windows defaults restored.  Log: $logPath2"
		}
		else
		{
			$StatusText.Text = "Windows defaults restored."
		}
		$StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:CurrentTheme.ToggleOn)

		if ($Script:CurrentPrimaryTab)
		{
			Build-TabContent -PrimaryTab $Script:CurrentPrimaryTab
		}
	})

	$BtnLog.Add_Click({
		$logPath = $Global:LogFilePath
		if ($logPath -and (Test-Path -LiteralPath $logPath -ErrorAction SilentlyContinue))
		{
			Start-Process -FilePath "notepad.exe" -ArgumentList $logPath -ErrorAction SilentlyContinue
		}
		else
		{
			Show-ThemedDialog -Title 'Open Log' -Message "Log file not found.`n$logPath" -Buttons @('OK') -AccentButton 'OK'
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

	# Run button styling
	$runTmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
	$runBorder = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$runBorder.Name = "Bd"
	$runBorder.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
	$runBorder.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(20, 8, 20, 8))
	$runBorder.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($Script:CurrentTheme.AccentBlue))
	$runCp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$runCp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$runBorder.AppendChild($runCp)
	$runTmpl.VisualTree = $runBorder
	$BtnRun.Template = $runTmpl
	$BtnRun.Foreground = $bc.ConvertFromString($Script:CurrentTheme.HeaderBg)

	# Defaults button styling (destructive red)
	$defTmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
	$defBorder = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$defBorder.Name = "Bd"
	$defBorder.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(6))
	$defBorder.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(16, 8, 16, 8))
	$defBorder.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($Script:CurrentTheme.DestructiveBg))
	$defBorder.SetValue([System.Windows.Controls.Border]::BorderBrushProperty, $bc.ConvertFromString($Script:CurrentTheme.CautionBorder))
	$defBorder.SetValue([System.Windows.Controls.Border]::BorderThicknessProperty, [System.Windows.Thickness]::new(1))
	$defCp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$defCp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$defBorder.AppendChild($defCp)
	$defTmpl.VisualTree = $defBorder
	$BtnDefaults.Template = $defTmpl
	$BtnDefaults.Foreground = $bc.ConvertFromString("#FFFFFF")

	# Log button styling (subtle, matches header)
	$logTmpl = New-Object System.Windows.Controls.ControlTemplate([System.Windows.Controls.Button])
	$logBd = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Border])
	$logBd.Name = "Bd"
	$logBd.SetValue([System.Windows.Controls.Border]::CornerRadiusProperty, [System.Windows.CornerRadius]::new(4))
	$logBd.SetValue([System.Windows.Controls.Border]::PaddingProperty, [System.Windows.Thickness]::new(10, 4, 10, 4))
	$logBd.SetValue([System.Windows.Controls.Border]::BackgroundProperty, $bc.ConvertFromString($Script:CurrentTheme.TabBg))
	$logCp = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.ContentPresenter])
	$logCp.SetValue([System.Windows.Controls.ContentPresenter]::HorizontalAlignmentProperty, [System.Windows.HorizontalAlignment]::Center)
	$logBd.AppendChild($logCp)
	$logTmpl.VisualTree = $logBd
	$BtnLog.Template = $logTmpl
	$BtnLog.Foreground = $bc.ConvertFromString($Script:CurrentTheme.TextSecondary)

	# Apply initial theme
	Set-GUITheme -Theme $Script:DarkTheme

	# Hide the console — only shown during Run Tweaks execution
	Hide-ConsoleWindow

	$startupSplashCleanup = $null

	function Close-StartupSplashWindow
	{
		if (-not $StartupSplash) { return $false }

		try
		{
			if ($StartupSplash -is [hashtable])
			{
				if ($StartupSplash.IsAlive -and $StartupSplash.Dispatcher -and (-not $StartupSplash.Dispatcher.HasShutdownStarted))
				{
					$StartupSplash.Dispatcher.Invoke([Action]{
						if ($StartupSplash.Window)
						{
							try { $StartupSplash.Window.Hide() } catch { $null = $_ }
							try { $StartupSplash.Window.Close() } catch { $null = $_ }
						}
						# Clear the flag here so the caller's wait-loop exits immediately
						# rather than spinning until the Closed event fires asynchronously.
						$StartupSplash.IsAlive = $false
					})
					return $true
				}
			}
			else
			{
				if ($StartupSplash.Dispatcher -and (-not $StartupSplash.Dispatcher.HasShutdownStarted))
				{
					$StartupSplash.Dispatcher.Invoke([Action]{ $StartupSplash.Hide(); $StartupSplash.Close() })
					return $true
				}
			}
		}
		catch { $null = $_ }

		return $false
	}

	# Keep the splash visible until the main window is fully prepared, then close
	# it immediately before showing the finished GUI.
	if ($StartupSplash)
	{
		try
		{
			if ($StartupSplash -is [hashtable])
			{
				# Runspace-based splash (from Show-BootstrapLoadingSplash)
				if ($StartupSplash.IsAlive)
				{
					$null = Close-StartupSplashWindow

					$closeDeadline = [datetime]::UtcNow.AddSeconds(2)
					while ($StartupSplash.IsAlive -and [datetime]::UtcNow -lt $closeDeadline)
					{
						Start-Sleep -Milliseconds 50
					}

					if ($StartupSplash.IsAlive -and $StartupSplash.Dispatcher -and (-not $StartupSplash.Dispatcher.HasShutdownStarted))
					{
						try { $StartupSplash.Dispatcher.InvokeShutdown() } catch { $null = $_ }
					}
				}
				# Defer runspace cleanup until after the GUI closes so the splash-to-GUI
				# transition is immediate instead of waiting on runspace teardown.
				$startupSplashCleanup = {
					try { $StartupSplash._PowerShell.EndInvoke($StartupSplash._AsyncResult) } catch { $null = $_ }
					try { $StartupSplash._PowerShell.Dispose() } catch { $null = $_ }
					try { $StartupSplash._Runspace.Close(); $StartupSplash._Runspace.Dispose() } catch { $null = $_ }
				}.GetNewClosure()
			}
			else
			{
				# Legacy Window splash (from Show-LoadingSplash)
				if (-not $StartupSplash.Dispatcher.HasShutdownStarted)
				{
					Close-StartupSplashWindow
				}
			}
		}
		catch { $null = $_ }
	}

	# Safety net: if the splash is still alive when the main window finishes rendering,
	# close it now. Capture $StartupSplash explicitly — closure variable, not nested-function scope.
	$_splashRef = $StartupSplash
	$Form.Add_ContentRendered({
		if (-not $_splashRef) { return }
		try
		{
			if ($_splashRef -is [hashtable])
			{
				if ($_splashRef.IsAlive -and $_splashRef.Dispatcher -and (-not $_splashRef.Dispatcher.HasShutdownStarted))
				{
					$_splashRef.Dispatcher.Invoke([Action]{
						if ($_splashRef.Window)
						{
							try { $_splashRef.Window.Hide() } catch { $null = $_ }
							try { $_splashRef.Window.Close() } catch { $null = $_ }
						}
						$_splashRef.IsAlive = $false
					})
				}
			}
			else
			{
				if ($_splashRef.Dispatcher -and (-not $_splashRef.Dispatcher.HasShutdownStarted))
				{
					$_splashRef.Dispatcher.Invoke([Action]{ $_splashRef.Hide(); $_splashRef.Close() })
				}
			}
		}
		catch { $null = $_ }
	}.GetNewClosure())

	# Show the GUI
	$Form.ShowDialog() | Out-Null
	if ($startupSplashCleanup)
	{
		& $startupSplashCleanup
	}

	LogInfo "GUI closed"
}
#endregion GUI Builder

#region Loading Splash
<#
	.SYNOPSIS
	Show a WPF loading splash window in a separate STA runspace.

	.DESCRIPTION
	Creates a dark-themed WPF splash window in its own STA thread with a
	message loop so it stays responsive while the main thread is blocked.
	Returns a synchronized hashtable with Window, Dispatcher, and cleanup
	handles. Call the Dispatcher to close the window when done.

	.OUTPUTS
	hashtable  A synchronized hashtable with keys: Window, Dispatcher,
	           IsReady, IsAlive, _PowerShell, _AsyncResult, _Runspace.

	.EXAMPLE
	$splash = Show-LoadingSplash
	InitialActions
	$splash.Dispatcher.Invoke([Action]{ $splash.Window.Close() })
#>
function Show-LoadingSplash
{
	[CmdletBinding()]
	[OutputType([hashtable])]
	param ()

	# Hide the console window immediately — before anything else loads
	try
	{
		if (-not ('SplashConsoleHide' -as [type]))
		{
			Add-Type -Name 'SplashConsoleHide' -Namespace '' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
		}
		$consoleHwnd = [SplashConsoleHide]::GetConsoleWindow()
		if ($consoleHwnd -ne [System.IntPtr]::Zero)
		{
			[SplashConsoleHide]::ShowWindow($consoleHwnd, 0) | Out-Null  # SW_HIDE = 0
		}
	}
	catch { $null = $_ }

	$syncHash = [hashtable]::Synchronized(@{
		Window     = $null
		Dispatcher = $null
		IsReady    = $false
		IsAlive    = $false
	})

	$rs = [runspacefactory]::CreateRunspace()
	$rs.ApartmentState = 'STA'
	$rs.ThreadOptions  = 'ReuseThread'
	$rs.Open()
	$rs.SessionStateProxy.SetVariable('syncHash', $syncHash)

	$ps = [powershell]::Create().AddScript({
		Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

		[xml]$splashXAML = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	Title="WinUtil Script"
	Width="520" Height="260"
	ResizeMode="CanMinimize"
	WindowStartupLocation="CenterScreen"
	Background="#1E1E2E"
	Foreground="#CDD6F4"
	FontFamily="Segoe UI"
	ShowInTaskbar="True">
	<Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<StackPanel Grid.Row="0" VerticalAlignment="Center" HorizontalAlignment="Center">
			<TextBlock Text="WinUtil Script" FontSize="22" FontWeight="Bold"
				Foreground="#CDD6F4" HorizontalAlignment="Center" Margin="0,0,0,6"/>
			<TextBlock Text="Windows Optimization &amp; Hardening"
				FontSize="13" Foreground="#A6ADC8"
				HorizontalAlignment="Center" Margin="0,0,0,24"/>
			<TextBlock Name="StatusText" Text="Please wait &#x2014; running startup checks..."
				FontSize="14" Foreground="#89B4FA"
				HorizontalAlignment="Center"/>
		</StackPanel>
		<Border Grid.Row="1" Background="#181825" Padding="12,8">
			<TextBlock FontSize="11" Foreground="#6C7086" HorizontalAlignment="Center"
				Text="This window will close automatically when ready."/>
		</Border>
	</Grid>
</Window>
"@

		$splash = [Windows.Markup.XamlReader]::Load(
			(New-Object System.Xml.XmlNodeReader $splashXAML)
		)

		$syncHash.Window     = $splash
		$syncHash.Dispatcher = $splash.Dispatcher
		$syncHash.IsReady    = $true
		$syncHash.IsAlive    = $true

		$splash.Add_Closed({ $syncHash.IsAlive = $false })

		# ShowDialog() runs the WPF message loop — keeps the window responsive
		$splash.ShowDialog() | Out-Null
	})

	$ps.Runspace = $rs
	$asyncResult = $ps.BeginInvoke()

	# Wait for the splash to be ready (window created and message loop running)
	$timeout = [datetime]::UtcNow.AddSeconds(10)
	while (-not $syncHash.IsReady -and [datetime]::UtcNow -lt $timeout)
	{
		Start-Sleep -Milliseconds 50
	}

	# Try to set OS name in title and bring to foreground
	if ($syncHash.IsAlive -and $syncHash.Dispatcher)
	{
		try
		{
			$osName = (Get-OSInfo).OSName
			$syncHash.Dispatcher.Invoke([Action]{
				$syncHash.Window.Title = "WinUtil Script for $osName"
			})
		}
		catch { $null = $_ }

		try
		{
			$syncHash.Dispatcher.Invoke([Action]{
				$syncHash.Window.Topmost = $true
				$syncHash.Window.Activate() | Out-Null
				$syncHash.Window.Topmost = $false
			})
		}
		catch { $null = $_ }
	}

	$syncHash._PowerShell  = $ps
	$syncHash._AsyncResult = $asyncResult
	$syncHash._Runspace    = $rs

	return $syncHash
}
#endregion Loading Splash

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
	    Report-TweakProgress -Action "Downloading installer" -Completed $i -Total $chunks.Count
	    # ... download chunk ...
	}
#>
function Report-TweakProgress
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
	# SessionStateProxy.SetVariable — it is not a global, just a session variable.
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

Export-ModuleMember -Function 'Show-TweakGUI', 'Show-LoadingSplash', 'Report-TweakProgress'