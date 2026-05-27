using module ..\Logging.psm1
using module ..\SharedHelpers.psm1


# Appx cmdlets fail with "The type initializer for '<Module>' threw an exception"
# in the minimal embedded runspace the Baseline launcher creates. Fall back to the
# WinRT PackageManager so presence checks still work. Returns $null when neither
# path produces a conclusive answer (caller should treat that as "unknown", not
# "missing", to avoid a false "Windows is broken" warning).
function Test-BaselineAppxPackagePresence
{
	<#
	    .SYNOPSIS
	    Check whether an Appx package is present.

	    .DESCRIPTION
	    Tries the Appx module first and falls back to the WinRT PackageManager so package presence checks still work when Appx cmdlets are unavailable.

	    .PARAMETER Name
	    Package identity name to look up.

	    .EXAMPLE
	    Test-BaselineAppxPackagePresence -Name 'Microsoft.WindowsStore'
	#>
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Name
	)

	try
	{
		[void](Initialize-BaselineWinRtRuntimeDependencies)
		Import-Module Appx -DisableNameChecking -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
		$package = Get-AppxPackage -Name $Name -WarningAction SilentlyContinue -ErrorAction Stop
		return [bool]$package
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Test-BaselineAppxPackagePresence:catch40' -Severity Debug }

		# Fall through to WinRT probe.
	}

	try
	{
		$packageManager = [Windows.Management.Deployment.PackageManager, Windows.Web, ContentType=WindowsRuntime]::new()
		$match = $packageManager.FindPackages() | Where-Object { $_.Id.Name -eq $Name } | Select-Object -First 1
		return [bool]$match
	}
	catch
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.Test-BaselineAppxPackagePresence:catch51' -Severity Debug }

		return $null
	}
}

function Start-BaselineInitialActionsSplashSystemStep
{
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$LoadingSplash = $Global:LoadingSplash
	)

	if (-not $Global:GUIMode -or -not $LoadingSplash -or -not $LoadingSplash.IsAlive)
	{
		return
	}

	$stepStates = $null
	if ($LoadingSplash -is [hashtable] -and $LoadingSplash.ContainsKey('StepStates'))
	{
		$stepStates = $LoadingSplash['StepStates']
	}

	if ($stepStates -is [System.Collections.IDictionary] -and $stepStates.Contains('system') -and [string]$stepStates['system'] -eq 'in_progress')
	{
		return
	}

	try
	{
		if (Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue)
		{
			Set-BootstrapLoadingSplashStep -Splash $LoadingSplash -StepId 'system' -Status 'in_progress' -SubAction ''
		}
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.SplashSystemStep'
	}
}

#region InitialActions
function InitialActions
{
	<#
		.SYNOPSIS
		Run the shared startup checks and runtime setup used before applying tweaks.

		.DESCRIPTION
		Prepares the Baseline session by clearing previous errors, unblocking
		script files, setting network and compiler prerequisites, and initializing
		the runtime helpers used by other region modules.

		.PARAMETER Warning
		Show the warning prompt during startup checks.

		.PARAMETER SkipWinGetCheck
		Skip the GUI splash WinGet availability/bootstrap check.

		.PARAMETER SkipChocolateyCheck
		Skip the GUI splash Chocolatey availability/bootstrap check.

		.EXAMPLE
		InitialActions
	#>
	param
	(
		[Parameter(Mandatory = $false)]
		[switch]
		$Warning,

		[Parameter(Mandatory = $false)]
		[switch]
		$SkipWinGetCheck,

		[Parameter(Mandatory = $false)]
		[switch]
		$SkipChocolateyCheck
	)

	$osInfo = Get-OSInfo
	$osName = $osInfo.OSName
	$displayVersion = Get-BaselineDisplayVersion

	$startupLabel = Get-BaselineStartupLabel -OSName $osName -DisplayVersion $displayVersion

	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_Starting' -Fallback 'Starting {0}' -FormatArgs @($startupLabel)) -addGap

	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_BeginningInitialChecks' -Fallback 'Beginning Initial Checks:')

	Start-BaselineInitialActionsSplashSystemStep

	# Clear the $Error variable
	$Global:Error.Clear()

	# Unblock all files in the script folder by removing the Zone.Identifier alternate data stream with a value of "3"
	Get-ChildItem -Path $PSScriptRoot\..\ -File -Recurse -Force | Unblock-File

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

	# Progress bar can significantly impact cmdlet performance
	# https://github.com/PowerShell/PowerShell/issues/2138
	$Script:ProgressPreference = "SilentlyContinue"

	# https://github.com/PowerShell/PowerShell/issues/21070
	$Script:CompilerParameters = [System.CodeDom.Compiler.CompilerParameters]::new("System.dll")
	$Script:CompilerParameters.TempFiles = [System.CodeDom.Compiler.TempFileCollection]::new($env:TEMP, $false)
	$Script:CompilerParameters.GenerateInMemory = $true
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\ShellStringWinApi.ps1')
	if (-not ("WinAPI.GetStrings" -as [type]))
	{
		Add-Type @Signature
	}

		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\ForegroundWindowWinApi.ps1')

	if (-not ("WinAPI.ForegroundWindow" -as [type]))
	{
		Add-Type @Signature | Out-Null
	}

	# Checking whether the logged-in user is an admin
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingAdmin' -Fallback 'Checking whether the logged-in user is an admin')
	$CurrentUserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name | Split-Path -Leaf
	$LoginUserName = $null
	try
	{
		$LoginUserName = (Get-CimInstance -ClassName Win32_Process -Filter "name='explorer.exe'" | Invoke-CimMethod -MethodName GetOwner | Select-Object -First 1).User
	}
	catch
	{
		LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_UnableToDetermineLoggedInUserFromExplorer' -Fallback 'Unable to determine the logged-in user from explorer.exe: {0}' -FormatArgs @($_.Exception.Message))
	}

	if ($CurrentUserName -ne $LoginUserName)
	{
		LogWarning (Get-BaselineBilingualString -Key 'LoggedInUserNotAdmin' -Fallback "The logged-on user doesn't have admin rights.")
	}

	$IsAdmin = ([System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

	# Checking whether the script was run in PowerShell ISE or VS Code
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingHostEnvironment' -Fallback 'Checking whether the script was run in PowerShell ISE or VS Code')
	if (Test-BaselineUnsupportedHost -HostName $Host.Name -TermProgram $env:TERM_PROGRAM)
	{
		LogWarning (Get-BaselineBilingualString -Key 'UnsupportedHost' -Fallback "The script doesn't support running via {0}." -FormatArgs @($Host.Name.Replace('Host', '')))
	}

	# Checking whether Windows was broken by 3rd party harmful tweakers, trojans, or custom Windows images
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingWindowsIntegrity' -Fallback 'Checking whether Windows was broken by 3rd party harmful tweakers, trojans, or custom Windows images')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\KnownTweakerDetectionMap.ps1')
	$DetectedTweakers = New-Object System.Collections.Generic.List[string]
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\KnownTweakerWarnings.ps1')

		# Checking whether Windows was broken by 3rd party harmful tweakers, trojans, or custom Windows images
		# These probes are advisory only and must never block startup on restricted or unsupported systems.
		$MuiCacheProperties = @()
		if (Test-Path -Path "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache")
		{
			try
			{
				$MuiCacheProperties = (Get-ItemProperty -Path "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache" -ErrorAction SilentlyContinue).PSObject.Properties
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.InitialActions:catch202' -Severity Debug }

				$MuiCacheProperties = @()
			}
		}

		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\OptionalProbeInvoker.ps1')

		$AutoSettingsPS = & $InvokeOptionalProbe {
			Get-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" | Where-Object -FilterScript {$_.Property -match "AutoSettingsPS"}
		}
		$Flibustier = & $InvokeOptionalProbe {
			Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\.NETFramework\Performance" -Name *flibustier
		}
		$Winpilot = & $InvokeOptionalProbe {
			$MuiCacheProperties | Where-Object -FilterScript {$_.Value -eq "Winpilot"}
		}
		$Bloatynosy = & $InvokeOptionalProbe {
			$MuiCacheProperties | Where-Object -FilterScript {$_.Value -eq "BloatynosyNue"}
		}
		$XdAntiSpy = & $InvokeOptionalProbe {
			$MuiCacheProperties | Where-Object -FilterScript {$_.Value -eq "xd-AntiSpy"}
		}
		$ModernTweaker = & $InvokeOptionalProbe {
			$MuiCacheProperties | Where-Object -FilterScript {$_.Value -eq "Modern Tweaker"}
		}
		$KernelOS = & $InvokeOptionalProbe {
			Get-CimInstance -Namespace root/CIMV2/power -ClassName Win32_PowerPlan | Where-Object -FilterScript {$_.ElementName -match "KernelOS"}
		}
		$ChlorideOS = & $InvokeOptionalProbe {
			Get-Volume | Where-Object -FilterScript {$_.FileSystemLabel -eq "ChlorideOS"}
		}

		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\AdditionalTweakerDetectionMap.ps1')
	foreach ($Tweaker in $Tweakers.Keys)
	{
		if ($Tweakers[$Tweaker])
		{
			[void]$DetectedTweakers.Add([string]$Tweaker)
			LogWarning (Get-BaselineBilingualString -Key 'TweakerWarning' -Fallback 'The Windows stability may have been compromised by using {0}. Reinstall Windows using only a genuine ISO image.' -FormatArgs @($Tweaker))
		}
	}

	$Global:BaselineHostTaint = Resolve-BaselineHostTaintAssessment -DetectedTweakerNames $DetectedTweakers
	if ($Global:BaselineHostTaint.Level -eq 'Blocked')
	{
		foreach ($Url in $Global:BaselineHostTaint.AdvisoryUrls)
		{
			LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_HostTaintAdvisoryUrl' -Fallback 'See: {0}' -FormatArgs @([string]$Url))
		}
	}

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\HarmfulTweakerNetworkCleanup.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }

	# Checking whether Windows Feature Experience Pack was removed by harmful tweakers
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingFeatureExperiencePack' -Fallback 'Checking whether Windows Feature Experience Pack was removed by harmful tweakers')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\FeatureExperiencePackPresenceCheck.ps1')

	# Checking whether EventLog service is running
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingEventLogService' -Fallback 'Checking whether EventLog service is running')
	if ((Get-Service -Name EventLog).Status -eq "Stopped")
	{
		LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @([WinAPI.GetStrings]::GetString(22029)))
	}

	# Checking whether the Microsoft Store being an important system component was removed
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingMicrosoftStore' -Fallback 'Checking whether the Microsoft Store being an important system component was removed')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\MicrosoftStorePresenceCheck.ps1')

	#region Defender checks
	# Checking whether necessary Microsoft Defender components exists
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingDefenderComponents' -Fallback 'Checking whether necessary Microsoft Defender components exists')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\RequiredWindowsFiles.ps1')
	foreach ($File in $Files)
	{
		if (-not (Test-Path -Path $File))
		{
			LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @($File))
		}
	}

	# Checking whether Windows Security Settings page was hidden from UI
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingSecurityPageVisibility' -Fallback 'Checking whether Windows Security Settings page was hidden from UI')
	if ([Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer", "SettingsPageVisibility", $null) -match "hide:windowsdefender")
	{
		LogWarning (Get-BaselineBilingualString -Key 'WindowsComponentBroken' -Fallback '{0} is broken or removed from Windows. Reinstall Windows using only a genuine ISO image.' -FormatArgs @('Microsoft Defender'))
	}

	# Checking whether WMI is corrupted
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingWmi' -Fallback 'Checking whether WMI is corrupted')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\DefenderWmiHealthCheck.ps1')

	# Check Microsoft Defender state
	$SecurityCenterProducts = @()
	$SecurityCenterAvailable = $false
	$Script:DefenderServices = $false
	$Script:DefenderProductState = $false
	$Script:AntiSpywareEnabled = $false
	$Script:RealtimeMonitoringEnabled = $false
	$Script:BehaviorMonitoringEnabled = $false

		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\SecurityCenterAntivirusProducts.ps1')

	# Checking services
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingServices' -Fallback 'Checking services')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\DefenderServiceHealth.ps1')

	$Script:DefenderServices = Test-BaselineDefenderServicesHealthy -Services $Services

	# Checking Get-MpPreference cmdlet
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingGetMpPreference' -Fallback 'Checking Get-MpPreference cmdlet')
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\DefenderPreferenceHealthCheck.ps1')

	# Check Microsoft Defender state
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingMicrosoftDefenderState' -Fallback 'Checking Microsoft Defender state')
	$DefenderState = $null
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\DefenderPolicyState.ps1')

	if (Get-Command -Name 'Set-BaselineDefenderExecutionAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$defenderExecutionAvailability = Resolve-BaselineDefenderExecutionAvailability
		Set-BaselineDefenderExecutionAvailability -Available ([bool]$defenderExecutionAvailability.Available) -UnavailableReason ([string]$defenderExecutionAvailability.Reason)
		if (-not $defenderExecutionAvailability.Available)
		{
			LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_DefenderExecutionUnavailable' -Fallback 'Microsoft Defender command surface is unavailable: {0}' -FormatArgs @([string]$defenderExecutionAvailability.Reason))
		}
		elseif (-not $Script:DefenderEnabled)
		{
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_DefenderHealthNotFullyEnabled' -Fallback 'Microsoft Defender command surface is available, but Defender is not reported as the active fully enabled antivirus. Defender-backed actions will run and report command failures directly if Windows rejects them.')
		}
	}
	if (Get-Command -Name 'Set-BaselineDefenderComponentAvailability' -CommandType Function -ErrorAction SilentlyContinue)
	{
		$defenderComponentAvailability = Resolve-BaselineDefenderComponentAvailability
		Set-BaselineDefenderComponentAvailability -Available ([bool]$defenderComponentAvailability.Available) -UnavailableReason ([string]$defenderComponentAvailability.Reason)
		if (-not $defenderComponentAvailability.Available)
		{
			LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_DefenderComponentsUnavailable' -Fallback 'Microsoft Defender components are unavailable: {0}' -FormatArgs @([string]$defenderComponentAvailability.Reason))
		}
	}
	#endregion Defender checks

	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingBaselinePolicyToolExists' -Fallback 'Checking whether Baseline policy tool exists in the Assets folder')
	try
	{
		$null = Resolve-BaselinePolicyToolPath
	}
	catch
	{
		LogWarning $_.Exception.Message
	}

	# Enable back the SysMain service if it was disabled by harmful tweakers
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingSysMain' -Fallback 'Enable back the SysMain service if it was disabled by harmful tweakers')
	if ($IsAdmin -and ((Get-Service -Name SysMain).Status -eq "Stopped"))
	{
		Get-Service -Name SysMain | Set-Service -StartupType Automatic | Out-Null
		Get-Service -Name SysMain | Start-Service | Out-Null
	}
	elseif ((Get-Service -Name SysMain).Status -eq "Stopped")
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingSysMainRecoveryNotElevated' -Fallback 'Skipping SysMain recovery because Baseline is not running elevated.')
	}

	# Automatically manage paging file size for all drives
	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingPagingFile' -Fallback 'Automatically manage paging file size for all drives')
	if ($IsAdmin -and (-not (Get-CimInstance -ClassName CIM_ComputerSystem).AutomaticManagedPageFile))
	{
		Get-CimInstance -ClassName CIM_ComputerSystem | Set-CimInstance -Property @{AutomaticManagedPageFile = $true} | Out-Null
	}
	elseif (-not (Get-CimInstance -ClassName CIM_ComputerSystem).AutomaticManagedPageFile)
	{
		LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_SkippingPagingFileRemediationNotElevated' -Fallback 'Skipping automatic paging file remediation because Baseline is not running elevated.')
	}

	# PowerShell 5.1 (7.5 too) interprets 8.3 file name literally, if an environment variable contains a non-Latin word
	# https://github.com/PowerShell/PowerShell/issues/21070
	foreach ($temporaryPolicyFile in @((Join-Path $env:TEMP 'Computer.txt'), (Join-Path $env:TEMP 'User.txt')))
	{
		if (Test-Path -LiteralPath $temporaryPolicyFile)
		{
			Remove-Item -LiteralPath $temporaryPolicyFile -Force -ErrorAction Ignore
		}
	}

	$Global:BaselinePostActionRequirements = @{
		EnsurePrintManagementConsole = $false
		EnsureSmbGuestAuth = $false
	}

	# Save all opened folders in order to restore them after File Explorer restart
	try
	{
		$Script:OpenedFolders = {
			(New-Object -ComObject Shell.Application).Windows() |
				ForEach-Object { $_.Document.Folder.Self.Path }
		}.Invoke()
	}
	catch [System.Management.Automation.PropertyNotFoundException]
	{
		if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialActions.InitialActions:catch404' -Severity Debug }

		$Script:OpenedFolders = @()
	}
	if ($env:BASELINE_EMBEDDED_HOST -ne '1' -and (Test-InteractiveHost))
	{
		Clear-Host
	}

	$Script:Browse = Get-LocalizedShellString -ResourceId 9015 -Fallback 'Browse'
	$Script:No = Get-LocalizedShellString -ResourceId 33232 -Fallback 'No' -StripAccelerators
	$Script:Yes = Get-LocalizedShellString -ResourceId 33224 -Fallback 'Yes' -StripAccelerators
	$Script:KeyboardArrows = Get-BaselineBilingualString -Key 'KeyboardArrows' -Fallback 'Please use the arrow keys {0} and {1} on your keyboard to select your answer' -FormatArgs @([System.Char]::ConvertFromUtf32(0x2191), [System.Char]::ConvertFromUtf32(0x2193))
	$Script:Skip = Get-LocalizedShellString -ResourceId 16956 -Fallback 'Skip'

	Write-Information -MessageData "Baseline | Windows Utility" -InformationAction Continue

	# Display a warning message about whether a user has customized the preset file
		. (Join-Path $PSScriptRoot 'InitialActions\InitialActions\StartupWarningAndSplashFinalization.ps1')

	LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_InitialChecksFinished' -Fallback 'Initial Checks finished, continuing with Main Script') -addGap
	if ($env:BASELINE_EMBEDDED_HOST -ne '1' -and (Test-InteractiveHost))
	{
		Clear-Host
	}
}
#endregion InitialActions
$ExportedFunctions = @(
    'InitialActions',
    'Test-BaselineAppxPackagePresence'
)
Export-ModuleMember -Function $ExportedFunctions
