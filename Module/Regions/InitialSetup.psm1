using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Initial Setup

<#
	.SYNOPSIS
	Create a restore point for the system drive before changes are applied.

	.DESCRIPTION
	Ensures System Restore is available on the system drive, temporarily allows
	immediate restore point creation, creates a restore point named for the
	current Windows version, and restores the prior System Restore state.

	.EXAMPLE
	CreateRestorePoint

	.NOTES
	Machine-wide
#>
function CreateRestorePoint
{
	LogInfo "Creating Restore Point"
	# Write-Host: intentional — user-visible progress indicator
	Write-Host "Creating System Restore Point - " -NoNewline
	$restoreSystemProtection = $false
	$createdSuccessfully = $false
	try
	{
		# Ensure the Volume Shadow Copy service is running — both Checkpoint-Computer
		# and the WMI fallback depend on it. On VMs or hardened systems it may be
		# set to Manual/Disabled and not started.
		try
		{
			$vssSvc = Get-Service -Name VSS -ErrorAction Stop
			if ($vssSvc.Status -ne 'Running')
			{
				LogInfo "Starting Volume Shadow Copy (VSS) service (was $($vssSvc.Status))."
				if ($vssSvc.StartType -eq 'Disabled')
				{
					Set-Service -Name VSS -StartupType Manual -ErrorAction Stop
				}
				Start-Service -Name VSS -ErrorAction Stop
			}
		}
		catch
		{
			LogWarning "Could not ensure VSS service is running: $($_.Exception.Message)"
		}

		$SystemDriveUniqueID = (Get-Volume | Where-Object -FilterScript {$_.DriveLetter -eq "$($env:SystemDrive[0])"}).UniqueID
		$SystemProtection = ((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients" -ErrorAction Ignore)."{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}") | Where-Object -FilterScript {$_ -match [regex]::Escape($SystemDriveUniqueID)}

		if ($null -eq $SystemProtection)
		{
			# Verify whether System Protection is actually disabled before attempting to enable it,
			# because the SPP\Clients registry check can return null on newer Windows 11 builds
			# even when System Protection is already on.
			$srpEnabled = $false
			try
			{
				$srpStatus = Get-CimInstance -ClassName SystemRestoreConfig -Namespace 'root\default' -ErrorAction Stop
				if ($srpStatus -and $srpStatus.RPSessionInterval -eq 1) { $srpEnabled = $true }
			}
			catch {
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.CreateRestorePoint:catch65' -Severity Debug }
			 $srpEnabled = $false }

			if (-not $srpEnabled)
			{
				$restoreSystemProtection = $true
				Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
			}
		}

		# Never skip creating a restore point
		New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null

		$osName = (Get-OSInfo).OSName
		$displayVersion = Get-BaselineDisplayVersion

		$restorePointDescription = "Baseline | Utility for $osName"
		if (-not [string]::IsNullOrWhiteSpace([string]$displayVersion))
		{
			$restorePointDescription = "$restorePointDescription $displayVersion"
		}

		# Try Checkpoint-Computer in a background job with a timeout to prevent hanging
		$checkpointSucceeded = $false
		$restorePointTimeoutSeconds = 120
		try
		{
			$job = Start-Job -ScriptBlock {
				param ($Desc)
				Checkpoint-Computer -Description $Desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
			} -ArgumentList $restorePointDescription
			$finished = $job | Wait-Job -Timeout $restorePointTimeoutSeconds
			if ($finished)
			{
				$job | Receive-Job -ErrorAction Stop | Out-Null
				$checkpointSucceeded = $true
			}
			else
			{
				$job | Stop-Job -ErrorAction SilentlyContinue
				LogWarning "Checkpoint-Computer timed out after $restorePointTimeoutSeconds seconds. Trying WMI fallback."
			}
			$job | Remove-Job -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			LogWarning "Checkpoint-Computer failed: $($_.Exception.Message). Trying WMI fallback."
			if ($job) { $job | Remove-Job -Force -ErrorAction SilentlyContinue }
		}

		if (-not $checkpointSucceeded)
		{
			try
			{
				$sr = [wmiclass]'\\.\root\default:SystemRestore'
				$result = $sr.CreateRestorePoint($restorePointDescription, 12, 100)
				if ($result.ReturnValue -ne 0)
				{
					throw "WMI SystemRestore.CreateRestorePoint failed with return code $($result.ReturnValue)"
				}
				$checkpointSucceeded = $true
			}
			catch
			{
				throw "Restore point creation failed: $($_.Exception.Message)"
			}
		}

		try
		{
			$restorePoints = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object -FilterScript { $_.Description -eq $restorePointDescription })
			if (-not $restorePoints)
			{
				throw "Restore point '$restorePointDescription' was not found after creation."
			}
		}
		finally
		{
			# Revert the System Restore checkpoint creation frequency to 1440 minutes
			New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 1440 -Force -ErrorAction Stop | Out-Null

			# Turn off System Protection for the system drive if it was turned off before without deleting the existing restore points
			if ($restoreSystemProtection)
			{
				LogInfo "Disabling System Restore again"
				Disable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop | Out-Null
			}
		}
		Write-ConsoleStatus -Status success
		$createdSuccessfully = $true
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to create a restore point: $($_.Exception.Message)"
	}

	return $createdSuccessfully
}
<#
	.SYNOPSIS
	Check whether WinGet is installed and install it if needed.

	.DESCRIPTION
	Validates that WinGet is present and functional. If it is missing or broken,
	the function downloads a bootstrap installer script, executes it, and
	validates the WinGet installation again before continuing.

	.EXAMPLE
	CheckWinGet

	.NOTES
	Machine-wide
#>
function CheckWinGet
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$LoadingSplash = $Global:LoadingSplash
	)

	$startupSplashUpdateCommand = Get-Command -Name 'Set-BootstrapLoadingSplashState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$resetWinGetAvailabilityCommand = Get-Command -Name 'Reset-WinGetAvailabilityState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$updateStartupSplashState = {
		param(
			[switch]$Indeterminate,
			[switch]$HideProgressBar
		)

		if (-not $LoadingSplash -or -not $startupSplashUpdateCommand)
		{
			return
		}

		try
		{
			& $startupSplashUpdateCommand -Splash $LoadingSplash -Indeterminate:$Indeterminate -HideProgressBar:$HideProgressBar | Out-Null
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.CheckWinGet:catch204' -Severity Debug }

			$null = $_
		}
	}.GetNewClosure()

	$installerMetadata = Get-WinGetBootstrapInstallerMetadata
	$installerVersion = [string]$installerMetadata.Version
	$installerSha256 = [string]$installerMetadata.Sha256
	$installerArguments = @(Get-WinGetBootstrapInstallerArguments)
	$installerPath = $null
	$stdoutLog = $null
	$stderrLog = $null
	$stdoutLines = @()
	$stderrLines = @()
	$wingetLogScope = 'Winget'

	try
	{
		$osInfo = Get-OSInfo
		$osVersion = $osInfo.DisplayVersion
		$currentBuild = $osInfo.CurrentBuild
		$osName = $osInfo.OSName

		LogInfo "Detected OS: $osName (Build $currentBuild, Release $osVersion)"

		$checkingStatusText = Get-BaselineLocalizedString -Key 'Progress_CheckingInstallStatus' -Fallback 'Checking installation status...'
		Write-ConsoleStatus -Action $checkingStatusText -Scope 'PackageManager'
		& $updateStartupSplashState -Indeterminate

		$wingetVersion = Get-WinGetVersion
		if ($wingetVersion)
		{
			$resolvedWingetPath = Resolve-WinGetExecutable
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_CheckingPackageManager' -Fallback 'Checking {0}' -FormatArgs @('WinGet')) -Scope $wingetLogScope
			if (-not [string]::IsNullOrWhiteSpace([string]$resolvedWingetPath))
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_ResolvedPackageManagerExecutable' -Fallback 'Resolved {0} executable: {1}' -FormatArgs @('WinGet', $resolvedWingetPath)) -Scope $wingetLogScope
			}
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerAlreadyInstalled' -Fallback '{0} is already installed and working. Version: {1}' -FormatArgs @('WinGet', $wingetVersion)) -Scope $wingetLogScope
			Write-ConsoleStatus -Status success
			& $updateStartupSplashState -Indeterminate
			return
		}

		LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerNotFunctional' -Fallback '{0} not found or not functional' -FormatArgs @('WinGet')) -Scope $wingetLogScope
		$installStatusText = Get-BaselineLocalizedString -Key 'Progress_Installing' -Fallback 'Installing {0}...' -FormatArgs @('WinGet')
		Write-ConsoleStatus -Action $installStatusText -Scope $wingetLogScope
		& $updateStartupSplashState -Indeterminate

		try
		{
			$installerUrl = [string]$installerMetadata.Uri
			$installerPath = Join-Path $env:TEMP ("Baseline-WinGetBootstrap-{0}.ps1" -f $installerVersion)
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_DownloadingPackageManagerInstaller' -Fallback 'Downloading {0} installer from {1}' -FormatArgs @('WinGet', $installerUrl)) -Scope $wingetLogScope
			Invoke-DownloadFile -Uri $installerUrl -OutFile $installerPath

			if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -eq 0)
			{
				throw "Baseline WinGet bootstrap download failed or produced an empty file at $installerPath"
			}

			& $updateStartupSplashState -Indeterminate
			$null = Assert-FileHash `
				-Path $installerPath `
				-ExpectedSha256 $installerSha256 `
				-Label ([string]$installerMetadata.Label)
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerDownloadVerified' -Fallback 'Download and SHA-256 verification completed for {0} v{1}' -FormatArgs @('WinGet', $installerVersion)) -Scope $wingetLogScope

			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_ExecutingInstallerScript' -Fallback 'Executing installer script...') -Scope $wingetLogScope
			& $updateStartupSplashState -Indeterminate

			$process = Invoke-BaselineProcess -FilePath 'powershell.exe' -ArgumentList (@(
				'-NoProfile',
				'-ExecutionPolicy', 'Bypass',
				'-File', $installerPath
			) + $installerArguments) -TimeoutSeconds 1800 -CaptureOutput

			$stdoutLines = @()
			if (-not [string]::IsNullOrWhiteSpace([string]$process.StandardOutput))
			{
				$stdoutLines = @(([string]$process.StandardOutput -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
				foreach ($stdoutLine in $stdoutLines)
				{
					LogInfo "Baseline WinGet bootstrap: $stdoutLine" -Scope $wingetLogScope
				}
			}

			$stderrLines = @()
			if (-not [string]::IsNullOrWhiteSpace([string]$process.StandardError))
			{
				$stderrLines = @(([string]$process.StandardError -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
				foreach ($stderrLine in $stderrLines)
				{
					LogError "Baseline WinGet bootstrap: $stderrLine" -Scope $wingetLogScope
				}
			}

			$installerCompletedSuccessfully = ($process.ExitCode -eq 0 -or $null -eq $process.ExitCode)
			$installerReportedErrors = ($stderrLines.Count -gt 0)
			if ($installerCompletedSuccessfully -and -not $installerReportedErrors)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerInstallerScriptCompletedSuccessfully' -Fallback '{0} installer script completed successfully' -FormatArgs @('WinGet')) -Scope $wingetLogScope
			}
			elseif ($installerCompletedSuccessfully -and $installerReportedErrors)
			{
				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerInstallerScriptReportedErrors' -Fallback '{0} installer script reported errors despite a zero exit code. Running validation before accepting the install.' -FormatArgs @('WinGet')) -Scope $wingetLogScope
			}
			else
			{
				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerInstallerScriptReportedExitCode' -Fallback '{0} installer script reported exit code: {1}' -FormatArgs @('WinGet', $process.ExitCode)) -Scope $wingetLogScope
			}

			Start-Sleep -Seconds 5
			$wingetVersion = Get-WinGetVersion
			if ($wingetVersion)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerValidationSucceeded' -Fallback '{0} validation succeeded. Version: {1}' -FormatArgs @('WinGet', $wingetVersion)) -Scope $wingetLogScope
				Write-ConsoleStatus -Status success
				& $updateStartupSplashState -Indeterminate
				return
			}

			if ($installerCompletedSuccessfully -and -not $installerReportedErrors)
			{
				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerInstallationCompletedButUnavailable' -Fallback '{0} installation completed, but {1} is not available in the current session yet. A new session may be required.' -FormatArgs @('WinGet', 'winget.exe')) -Scope $wingetLogScope
				Write-ConsoleStatus -Status success
				& $updateStartupSplashState -Indeterminate
				return
			}

			$validationFailureMessage = if ($installerReportedErrors)
			{
				"WinGet installer reported errors and winget.exe is still unavailable. First error: $([string]$stderrLines[0].Trim())"
			}
			else
			{
				Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerInstallationFailedValidation' -Fallback '{0} installation failed validation after the installer completed.' -FormatArgs @('WinGet')
			}
			throw $validationFailureMessage
		}
		catch
		{
			LogError (Get-BaselineBilingualString -Key 'Bootstrap_ErrorDuringPackageManagerInstallation' -Fallback 'Error during {0} installation: {1}' -FormatArgs @('WinGet', $_)) -Scope $wingetLogScope
			$repairStatusText = Get-BaselineLocalizedString -Key 'Progress_WinGet_Updating' -Fallback 'Updating WinGet...'
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_AttemptingPackageManagerRepair' -Fallback 'Attempting {0} repair via {1}...' -FormatArgs @('WinGet', 'Microsoft.WinGet.Client')) -Scope $wingetLogScope
			Write-ConsoleStatus -Action $repairStatusText -Scope $wingetLogScope
			& $updateStartupSplashState -Indeterminate

			try
			{
				Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
				Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
				Install-Module Microsoft.WinGet.Client -Force -ErrorAction Stop | Out-Null
				Import-Module Microsoft.WinGet.Client -ErrorAction Stop
				Repair-WinGetPackageManager -ErrorAction Stop
				Start-Sleep -Seconds 3
				$wingetVersion = Get-WinGetVersion
				if ($wingetVersion)
				{
					LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerRepairSucceeded' -Fallback '{0} repair succeeded. Version: {1}' -FormatArgs @('WinGet', $wingetVersion)) -Scope $wingetLogScope
					Write-ConsoleStatus -Status success
					& $updateStartupSplashState -Indeterminate
					return
				}

				LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerRepairCompletedButUnavailable' -Fallback '{0} repair completed but {1} still not resolvable in this session.' -FormatArgs @('WinGet', 'winget.exe')) -Scope $wingetLogScope
				Write-ConsoleStatus -Status success
				& $updateStartupSplashState -Indeterminate
			}
			catch
			{
				LogError (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerRepairFailed' -Fallback '{0} repair also failed: {1}' -FormatArgs @('WinGet', $_)) -Scope $wingetLogScope
				Write-ConsoleStatus -Status failed
				& $updateStartupSplashState -Indeterminate
			}
			return
		}
	}
	finally
	{
		if ($installerPath -and (Test-Path -LiteralPath $installerPath))
		{
			Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
		}
		if ($stdoutLog -and (Test-Path -LiteralPath $stdoutLog))
		{
			Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue
		}
		if ($stderrLog -and (Test-Path -LiteralPath $stderrLog))
		{
			Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue
		}

		if ($resetWinGetAvailabilityCommand)
		{
			try
			{
				& $resetWinGetAvailabilityCommand | Out-Null
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.CheckWinGet:catch404' -Severity Debug }

				$null = $_
			}
		}
	}
}

<#
	.SYNOPSIS
	Check WinGet and Chocolatey together during startup and bootstrap whichever package managers are missing.



.DESCRIPTION

Applies the Baseline behavior for check WinGet and Chocolatey together during startup and bootstrap whichever package managers are missing..
	.NOTES
	Startup-only helper used by InitialActions.
#>
function Initialize-PackageManagersBootstrap
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[object]
		$LoadingSplash = $Global:LoadingSplash,

		[Parameter(Mandatory = $false)]
		[bool]
		$IncludeWinGet = $true,

		[Parameter(Mandatory = $false)]
		[bool]
		$IncludeChocolatey = $true
	)

	$startupSplashUpdateCommand = Get-Command -Name 'Set-BootstrapLoadingSplashState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$resetWinGetAvailabilityCommand = Get-Command -Name 'Reset-WinGetAvailabilityState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$resetChocolateyAvailabilityCommand = Get-Command -Name 'Reset-ChocolateyAvailabilityState' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$updateStartupSplashState = {
		param(
			[switch]$Indeterminate,
			[switch]$HideProgressBar
		)

		if (-not $LoadingSplash -or -not $startupSplashUpdateCommand)
		{
			return
		}

		try
		{
			& $startupSplashUpdateCommand -Splash $LoadingSplash -Indeterminate:$Indeterminate -HideProgressBar:$HideProgressBar | Out-Null
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.Initialize-PackageManagersBootstrap:catch455' -Severity Debug }

			$null = $_
		}
	}.GetNewClosure()
	$startupSplashStepCommand = Get-Command -Name 'Set-BootstrapLoadingSplashStep' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -First 1
	$updateStartupSplashStep = {
		param(
			[string]$StepId,
			[string]$Status,
			[string]$SubAction = ''
		)

		if (-not $LoadingSplash -or -not $startupSplashStepCommand)
		{
			return
		}

		try
		{
			& $startupSplashStepCommand -Splash $LoadingSplash -StepId $StepId -Status $Status -SubAction $SubAction | Out-Null
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.Initialize-PackageManagersBootstrap:catch477' -Severity Debug }

			$null = $_
		}
	}.GetNewClosure()

	$moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
	$loggingModulePath = Join-Path $moduleRoot 'Logging.psm1'
	$sharedHelpersModulePath = Join-Path $moduleRoot 'SharedHelpers.psm1'
	$logFilePath = if ($Global:LogFilePath) { [string]$Global:LogFilePath } else { $null }
	$results = [System.Collections.Generic.List[object]]::new()
	$jobs = @()
	$bootstrapTimeoutSeconds = 900
	$jobStartedAt = @{}
	$packageManagerLogScope = 'PackageManager'
	$wingetLogScope = 'Winget'
	$chocolateyLogScope = 'Chocolatey'

	$jobScriptBlock = {
		param(
			[string]$PackageManager,
			[string]$LoggingModulePath,
			[string]$SharedHelpersModulePath,
			[string]$LogFilePath,
			[int]$TimeoutSeconds
		)

	Import-Module -Name $LoggingModulePath -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
	Import-Module -Name $SharedHelpersModulePath -Force -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
		if (-not [string]::IsNullOrWhiteSpace($LogFilePath))
		{
			Set-LogFile -Path $LogFilePath
		}

		switch ($PackageManager)
		{
			'WinGet' { Invoke-WinGetBootstrap -TimeoutSeconds $TimeoutSeconds }
			'Chocolatey' { Invoke-ChocolateyBootstrap -TimeoutSeconds $TimeoutSeconds }
			default { throw "Unsupported package manager '$PackageManager'." }
		}
	}

	try
	{
		$checkingStatusText = Get-BaselineLocalizedString -Key 'Progress_CheckingInstallStatus' -Fallback 'Checking installation status...'
		Write-ConsoleStatus -Action $checkingStatusText -Scope $packageManagerLogScope
		& $updateStartupSplashState -Indeterminate

		if (-not $IncludeWinGet -and -not $IncludeChocolatey)
		{
			LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerStartupChecksSkippedByPreference' -Fallback 'Package manager startup checks skipped by user preference.') -Scope $packageManagerLogScope
			Write-ConsoleStatus -Status success
			return @($results)
		}

		if ($IncludeWinGet)
		{
			& $updateStartupSplashStep -StepId 'winget' -Status 'in_progress' -SubAction ''
			$wingetVersion = Get-WinGetVersion
			if ($wingetVersion)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerAlreadyInstalled' -Fallback '{0} is already installed and working. Version: {1}' -FormatArgs @('WinGet', $wingetVersion)) -Scope $wingetLogScope
				[void]$results.Add([pscustomobject]@{
					PackageManager = 'WinGet'
					Available      = $true
					Installed      = $false
					Repaired       = $false
					Version        = [string]$wingetVersion
					Success        = $true
					Error          = $null
				})
			}
			else
			{
				try
				{
					$newJob = Start-Job -Name 'WinGetBootstrap' -ScriptBlock $jobScriptBlock -ArgumentList @('WinGet', $loggingModulePath, $sharedHelpersModulePath, $logFilePath, $bootstrapTimeoutSeconds)
					$jobs += $newJob
					$jobStartedAt[$newJob.Id] = Get-Date
				}
				catch
				{
					LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_FailedToStartPackageManagerBootstrapJob' -Fallback 'Failed to start {0} bootstrap job: {1}' -FormatArgs @('WinGet', $_.Exception.Message)) -Scope $wingetLogScope
					[void]$results.Add([pscustomobject]@{
						PackageManager = 'WinGet'
						Available      = $false
						Installed      = $false
						Repaired       = $false
						Version        = $null
						Success        = $false
						Error          = $_.Exception.Message
					})
				}
			}
		}

		if ($IncludeChocolatey)
		{
			$chocolateyVersion = Get-ChocolateyVersion
			& $updateStartupSplashStep -StepId 'chocolatey' -Status 'in_progress' -SubAction ''
			if ($chocolateyVersion)
			{
				LogInfo (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerAlreadyInstalled' -Fallback '{0} is already installed and working. Version: {1}' -FormatArgs @('Chocolatey', $chocolateyVersion)) -Scope $chocolateyLogScope
				[void]$results.Add([pscustomobject]@{
					PackageManager = 'Chocolatey'
					Available      = $true
					Installed      = $false
					Repaired       = $false
					Version        = [string]$chocolateyVersion
					Success        = $true
					Error          = $null
				})
			}
			else
			{
				try
				{
					$newJob = Start-Job -Name 'ChocolateyBootstrap' -ScriptBlock $jobScriptBlock -ArgumentList @('Chocolatey', $loggingModulePath, $sharedHelpersModulePath, $logFilePath, $bootstrapTimeoutSeconds)
					$jobs += $newJob
					$jobStartedAt[$newJob.Id] = Get-Date
				}
				catch
				{
					LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_FailedToStartPackageManagerBootstrapJob' -Fallback 'Failed to start {0} bootstrap job: {1}' -FormatArgs @('Chocolatey', $_.Exception.Message)) -Scope $chocolateyLogScope
					[void]$results.Add([pscustomobject]@{
						PackageManager = 'Chocolatey'
						Available      = $false
						Installed      = $false
						Repaired       = $false
						Version        = $null
						Success        = $false
						Error          = $_.Exception.Message
					})
				}
			}
		}

		if ($jobs.Count -gt 0)
		{
			$installStatusText = if ($jobs.Count -gt 1)
			{
				Get-BaselineLocalizedString -Key 'Progress_InstallingPackageManagers' -Fallback 'Installing WinGet and Chocolatey...'
			}
			else
			{
				Get-BaselineLocalizedString -Key 'Progress_Installing' -Fallback 'Installing {0}...' -FormatArgs @([string]$jobs[0].Name.Replace('Bootstrap', ''))
			}

			Write-ConsoleStatus -Action $installStatusText -Scope $packageManagerLogScope
			& $updateStartupSplashState -Indeterminate

			while ($jobs.Count -gt 0)
			{
				$null = Wait-Job -Job $jobs -Any -Timeout 1
				foreach ($runningJob in @($jobs | Where-Object { $_.State -eq 'Running' }))
				{
					$jobStartTime = if ($jobStartedAt.ContainsKey($runningJob.Id)) { [datetime]$jobStartedAt[$runningJob.Id] } else { Get-Date }
					if (((Get-Date) - $jobStartTime).TotalSeconds -ge ($bootstrapTimeoutSeconds + 30))
					{
						LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerBootstrapJobTimedOut' -Fallback "Package manager bootstrap job '{0}' timed out after {1} seconds. Baseline will stop waiting and continue startup." -FormatArgs @($runningJob.Name, ($bootstrapTimeoutSeconds + 30))) -Scope $packageManagerLogScope
						try { Stop-Job -Job $runningJob -Force -ErrorAction SilentlyContinue } catch {
							if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.Initialize-PackageManagersBootstrap:catch627' -Severity Debug }
						 $null = $_ }
						[void]$results.Add([pscustomobject]@{
							PackageManager = [string]$runningJob.Name.Replace('Bootstrap', '')
							Available      = $false
							Installed      = $false
							Repaired       = $false
							Version        = $null
							Success        = $false
							Error          = ("Timed out after {0} seconds." -f ($bootstrapTimeoutSeconds + 30))
						})
					}
				}
				$completedJobs = @($jobs | Where-Object { $_.State -ne 'Running' })
				foreach ($completedJob in @($completedJobs))
				{
					try
					{
						$jobResult = Receive-Job -Job $completedJob -ErrorAction Stop | Select-Object -First 1
						if ($jobResult)
						{
							[void]$results.Add($jobResult)
						}
					}
					catch
					{
						LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerBootstrapJobDidNotReturnResult' -Fallback "Package manager bootstrap job '{0}' did not return a result: {1}" -FormatArgs @($completedJob.Name, $_.Exception.Message)) -Scope $packageManagerLogScope
						[void]$results.Add([pscustomobject]@{
							PackageManager = [string]$completedJob.Name.Replace('Bootstrap', '')
							Available      = $false
							Installed      = $false
							Repaired       = $false
							Version        = $null
							Success        = $false
							Error          = $_.Exception.Message
						})
					}
					finally
					{
						if ($jobStartedAt.ContainsKey($completedJob.Id))
						{
							$null = $jobStartedAt.Remove($completedJob.Id)
						}
						Remove-Job -Job $completedJob -Force -ErrorAction SilentlyContinue
					}
				}

				$jobs = @($jobs | Where-Object { $_.State -eq 'Running' })
				if ($jobs.Count -gt 0)
				{
					& $updateStartupSplashState -Indeterminate
				}
			}
		}

		$failedResults = @($results | Where-Object { -not [bool]$_.Success })
		if ($failedResults.Count -gt 0)
		{
			Write-ConsoleStatus -Status failed
			foreach ($failedResult in @($failedResults))
			{
				$packageManagerName = [string]$failedResult.PackageManager
				$failureText = if (-not [string]::IsNullOrWhiteSpace([string]$failedResult.Error))
				{
					$failedResult.Error
				}
					else
					{
						(Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerBootstrapDidNotCompleteSuccessfully' -Fallback '{0} bootstrap did not complete successfully.' -FormatArgs @($packageManagerName))
					}
				LogWarning $failureText -Scope $packageManagerLogScope
			}
		}
		else
		{
			Write-ConsoleStatus -Status success
		}

		return @($results)
	}
	catch
	{
		LogWarning (Get-BaselineBilingualString -Key 'Bootstrap_PackageManagerStartupBootstrapFailedUnexpectedly' -Fallback 'Package manager startup bootstrap failed unexpectedly: {0}' -FormatArgs @($_.Exception.Message)) -Scope $packageManagerLogScope
		Write-ConsoleStatus -Status failed
		return @($results)
	}
	finally
	{
		if ($IncludeWinGet -and $resetWinGetAvailabilityCommand)
		{
			try
			{
				& $resetWinGetAvailabilityCommand | Out-Null
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.Initialize-PackageManagersBootstrap:catch720' -Severity Debug }

				$null = $_
			}
		}

		if ($IncludeChocolatey -and $resetChocolateyAvailabilityCommand)
		{
			try
			{
				& $resetChocolateyAvailabilityCommand | Out-Null
			}
			catch
			{
				if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'InitialSetup.Initialize-PackageManagersBootstrap:catch732' -Severity Debug }

				$null = $_
			}
		}

		if ($startupSplashStepCommand -and $IncludeChocolatey)
		{
			& $updateStartupSplashStep -StepId 'chocolatey' -Status 'completed' -SubAction ''
		}
		elseif ($startupSplashStepCommand -and $IncludeWinGet)
		{
			& $updateStartupSplashStep -StepId 'winget' -Status 'completed' -SubAction ''
		}
		else
		{
			& $updateStartupSplashState -Indeterminate
		}
	}
}

<#
	.SYNOPSIS
	Install or update to the latest PowerShell 7 release.

	.DESCRIPTION
	Uses WinGet to install the latest stable PowerShell 7 release. If WinGet is
	unavailable or the install fails, downloads the official Microsoft MSI and
	verifies the Authenticode signer before running it.

	.EXAMPLE
	UpdatePowershell

	.NOTES
	Machine-wide
#>
function UpdatePowershell
{
	Write-ConsoleStatus -Action "Installing/Updating PowerShell 7"
	LogInfo "Installing/Updating PowerShell 7"
	try
	{
		$WingetPath = Resolve-WinGetExecutable
		$wingetSucceeded = $false
		if (-not [string]::IsNullOrWhiteSpace([string]$WingetPath))
		{
			LogInfo "Using winget executable: $WingetPath"
		}

		if ($WingetPath)
		{
			$process = Invoke-BaselineProcess -FilePath $WingetPath `
				-ArgumentList @('install', '--id', 'Microsoft.PowerShell', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--silent') `
				-TimeoutSeconds 1800 `
				-AllowedExitCodes @(0, -1978335189)
			if ($process.ExitCode -in 0, -1978335189)
			{
				$wingetSucceeded = $true
			}
			else
			{
				LogWarning "winget install returned exit code $($process.ExitCode), falling back to MSI installer"
			}
		}

		if (-not $WingetPath -or -not $wingetSucceeded)
		{
			$installerPath = $null
			try
			{
				LogInfo "Downloading the official PowerShell MSI package from GitHub"
				$installerUri = Resolve-PowerShellInstallerUri
				$installerFileName = Split-Path -Path $installerUri -Leaf
				$installerPath = Join-Path $env:TEMP $installerFileName
				Invoke-DownloadFile -Uri $installerUri -OutFile $installerPath
				$null = Assert-AuthenticodeSignature -Path $installerPath -AllowedSubjects @('CN=Microsoft Corporation')
				$process = Invoke-BaselineProcess -FilePath 'msiexec.exe' `
					-ArgumentList @('/i', $installerPath, '/qn', '/norestart') `
					-TimeoutSeconds 1800 `
					-AllowedExitCodes @(0, 3010)
				if ($process.ExitCode -notin 0, 3010)
				{
					throw "msiexec returned exit code $($process.ExitCode)"
				}
			}
			finally
			{
				if ($installerPath -and (Test-Path -LiteralPath $installerPath))
				{
					Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
				}
			}
		}

		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to install/update PowerShell 7: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Refresh the current process PATH from the machine and user environment blocks.


.DESCRIPTION

Applies the Baseline behavior for refresh the current process PATH from the machine and user environment blocks..
#>
#endregion Initial Setup
$ExportedFunctions = @(
    'CheckWinGet',
    'CreateRestorePoint',
    'Initialize-PackageManagersBootstrap',
    'UpdatePowershell'
)
Export-ModuleMember -Function $ExportedFunctions
