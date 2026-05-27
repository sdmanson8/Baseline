using module ..\Logging.psm1
using module ..\GUICommon.psm1
using module ..\SharedHelpers.psm1


#region UWP apps

<#
.SYNOPSIS
Enable or disable Background Apps



.DESCRIPTION

Enables or disables Background Apps in GUI and headless runs.
.PARAMETER Enable
Enable Background Apps (default value)

.PARAMETER Disable
Disable Background Apps

.EXAMPLE
BackgroundApps -Enable

.EXAMPLE
BackgroundApps -Disable

.NOTES
Current user
#>
function BackgroundApps
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Background Apps"
			LogInfo "Enabling Background Apps"
			try
			{
				Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Background Apps: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Background Apps"
			LogInfo "Disabling Background Apps"
			try
			{
				Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Background Apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Install or uninstall Microsoft Copilot and related Windows AI components.

	.DESCRIPTION
	Calls the AIRemoval helper script to either restore or remove the
	Windows AI components associated with Copilot, then installs or removes the
	store Copilot app itself.

	.PARAMETER Install
	Install Microsoft Copilot and restore the AI components used by it.

	.PARAMETER Uninstall
	Uninstall Microsoft Copilot and remove the AI components used by it.

	.EXAMPLE
	Copilot -Install

	.EXAMPLE
	Copilot -Uninstall

	.NOTES
	Current user

	.NOTES
	Machine-wide
#>

function Copilot
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Install"
		)]
		[switch]
		$Install,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Uninstall"
		)]
		[switch]
		$Uninstall
	)

	$osInfo = Get-OSInfo
	switch ($PSCmdlet.ParameterSetName)
	{
		"Install"
		{
			Write-ConsoleStatus -Action "Installing Microsoft Copilot app"
			LogInfo "Installing Microsoft Copilot app and restoring related Windows AI components"
			if ($osInfo.IsWindowsServer)
			{
				LogWarning "Skipping Microsoft Copilot install because this Windows AI package flow is not applicable on Windows Server."
				Write-ConsoleStatus -Status warning
				return
			}

			try
			{
				# Store the log path in the environment for the helper process.
				[Environment]::SetEnvironmentVariable("AIREMOVAL_LOG", $global:LogFilePath, "Process")
				$global:LASTEXITCODE = 0
				& "$PSScriptRoot\UWPApps\AIRemoval.ps1" -nonInteractive -revertMode -AllOptions
				if (-not $?)
				{
					throw "AIRemoval restore mode did not complete successfully."
				}
				if ($LASTEXITCODE -ne 0)
				{
					throw "AIRemoval restore mode returned exit code $LASTEXITCODE."
				}

				Start-Sleep -Seconds 2
				$WingetCommand = Get-Command winget -ErrorAction SilentlyContinue
				if (-not $WingetCommand)
				{
					throw "winget is required to install the Copilot Store app, but it is not available on this system."
				}

				$WingetProcess = Invoke-BaselineProcess -FilePath $WingetCommand.Source -ArgumentList @('install', '-s', 'msstore', '-e', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--id', '9NHT9RB2F4HD') -TimeoutSeconds 1800
				if ($WingetProcess.ExitCode -ne 0)
				{
					throw "winget failed to install Microsoft Copilot with exit code $($WingetProcess.ExitCode)."
				}

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to install Microsoft Copilot and related Windows AI components: $($_.Exception.Message)"
				throw
			}
		}
		"Uninstall"
		{
			Write-ConsoleStatus -Action "Uninstalling Microsoft Copilot app"
			LogInfo "Uninstalling Microsoft Copilot app and related Windows AI components"
			if ($osInfo.IsWindowsServer)
			{
				LogWarning "Skipping Microsoft Copilot uninstall because this Windows AI package flow is not applicable on Windows Server."
				Write-ConsoleStatus -Status warning
				return
			}

			try
			{
				# Store the log path in the environment for the helper process.
				[Environment]::SetEnvironmentVariable("AIREMOVAL_LOG", $global:LogFilePath, "Process")
				$global:LASTEXITCODE = 0
				& "$PSScriptRoot\UWPApps\AIRemoval.ps1" -nonInteractive -AllOptions
				if (-not $?)
				{
					throw "AIRemoval removal mode did not complete successfully."
				}
				if ($LASTEXITCODE -ne 0)
				{
					throw "AIRemoval removal mode returned exit code $LASTEXITCODE."
				}

				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to uninstall Microsoft Copilot and related Windows AI components: $($_.Exception.Message)"
				throw
			}
		}
	}
}

<#
	.SYNOPSIS
	Cortana autostarting



.DESCRIPTION

Applies the Baseline behavior for cortana autostarting.
	.PARAMETER Disable
	Disable Cortana autostarting

	.PARAMETER Enable
	Enable Cortana autostarting

	.EXAMPLE
	CortanaAutostart -Disable

	.EXAMPLE
	CortanaAutostart -Enable

	.NOTES
	Current user
#>
function CortanaAutostart
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable
	)

	if (-not (Get-AppxPackage -Name Microsoft.549981C3F5F10 -WarningAction SilentlyContinue))
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	try
	{
		if (-not (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId"))
		{
			New-Item -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Force -ErrorAction Stop | Out-Null
		}
	}
	catch
	{
		$actionText = if ($PSCmdlet.ParameterSetName -eq "Disable") { "Disabling Cortana autostarting" } else { "Enabling Cortana autostarting" }
		Write-ConsoleStatus -Action $actionText
		Write-ConsoleStatus -Status failed
		LogError "Failed to create Cortana startup registry key: $($_.Exception.Message)"
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Cortana autostarting"
			LogInfo "Disabling Cortana autostarting"
			try
			{
				New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Name State -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Cortana autostarting: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Cortana autostarting"
			LogInfo "Enabling Cortana autostarting"
			try
			{
				New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Name State -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Cortana autostarting: $($_.Exception.Message)"
			}
		}
	}
}

<#
    .SYNOPSIS
    Enable or disable the Baseline Edge debloat policy set.

    .DESCRIPTION
    Applies or removes the Edge and EdgeUpdate policy values Baseline uses to suppress consumer features, first-run prompts, and bundled extras.

    .PARAMETER Enable
    Apply the Baseline Edge debloat policy set.

    .PARAMETER Disable
    Remove the Baseline Edge debloat policy set.

    .EXAMPLE
    EdgeDebloat -Enable
#>
function EdgeDebloat
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
	$EdgeUpdatePath = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
	$EdgeBlocklistPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Edge Debloat"
			LogInfo "Enabling Edge Debloat"

			# Create paths if they don't exist
			if (-not (Test-Path $EdgeUpdatePath))
			{
				New-Item -Path $EdgeUpdatePath -Force -ErrorAction SilentlyContinue | Out-Null
			}
			if (-not (Test-Path $EdgePath))
			{
				New-Item -Path $EdgePath -Force -ErrorAction SilentlyContinue | Out-Null
			}
			if (-not (Test-Path $EdgeBlocklistPath))
			{
				New-Item -Path $EdgeBlocklistPath -Force -ErrorAction SilentlyContinue | Out-Null
			}

			Set-ItemProperty -LiteralPath $EdgeUpdatePath -Name "CreateDesktopShortcutDefault" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "PersonalizationReportingEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgeBlocklistPath -Name "1" -Type String -Value "ofefcgjbeghpigppfmkologfjadafddi" -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "ShowRecommendationsEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "HideFirstRunExperience" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "DefaultBrowserSettingsCampaignEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "UserFeedbackAllowed" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "ConfigureDoNotTrack" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "AlternateErrorPagesEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "EdgeCollectionsEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "EdgeShoppingAssistantEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "MicrosoftEdgeInsiderPromotionEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "ShowMicrosoftRewards" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "WebWidgetAllowed" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "DiagnosticData" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "EdgeAssetDeliveryServiceEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath $EdgePath -Name "WalletDonationEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null

			LogInfo "Edge debloat policies applied"
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Edge Debloat"
			LogInfo "Disabling Edge Debloat"

			Remove-ItemProperty -Path $EdgeUpdatePath -Name "CreateDesktopShortcutDefault" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "PersonalizationReportingEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgeBlocklistPath -Name "1" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "ShowRecommendationsEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "HideFirstRunExperience" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "DefaultBrowserSettingsCampaignEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "UserFeedbackAllowed" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "ConfigureDoNotTrack" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "AlternateErrorPagesEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "EdgeCollectionsEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "EdgeShoppingAssistantEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "MicrosoftEdgeInsiderPromotionEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "ShowMicrosoftRewards" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "WebWidgetAllowed" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "DiagnosticData" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "EdgeAssetDeliveryServiceEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $EdgePath -Name "WalletDonationEnabled" -Force -ErrorAction SilentlyContinue | Out-Null

			LogInfo "Edge debloat policies removed"
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Remove Microsoft Edge (Legacy and Chromium) while preserving EdgeWebView2.

.DESCRIPTION
Detects and removes Microsoft Edge installations including Legacy UWP Edge,
Chromium-based Edge, and EdgeUpdate components. EdgeWebView2 is intentionally
preserved (required by other apps).

Action-type entry -- one-way destructive operation. Backs up HKCU UserChoice
ProgId/Hash for .html/.htm/.xml/.pdf so a non-Edge default browser preference
survives the removal. Installs an OpenWebSearch protocol redirect (via
ie_to_edge_stub.exe) and a logon-triggered repair scheduled task so links that
still resolve through MSEdgeHTM are forwarded to the user's actual default
browser.

.PARAMETER Remove
Trigger the one-way Edge removal flow.

.NOTES
Logs at %ProgramData%\Baseline\Logs\EdgeRemovalLog.txt; stub + redirect at
%ProgramData%\Baseline\OpenWebSearch.
#>
function EdgeRemoval
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Remove")]
		[switch]$Remove
	)

	Write-ConsoleStatus -Action "Removing Microsoft Edge"
	LogInfo "Starting Microsoft Edge removal (preserves EdgeWebView2)"

	$logFolder = Join-Path $env:ProgramData 'Baseline\Logs'
	$logFile   = Join-Path $logFolder 'EdgeRemovalLog.txt'
	$scriptsDir = Join-Path $env:ProgramData 'Baseline\OpenWebSearch'

	if (-not (Test-Path $logFolder))
	{
		New-Item -ItemType Directory -Path $logFolder -Force -ErrorAction SilentlyContinue | Out-Null
	}
	<#
	    .SYNOPSIS
	    Write a line to the Edge removal log.

	    .DESCRIPTION
	    Appends a timestamped message to the Edge removal log file and mirrors the same text into the main Baseline log.

	    .PARAMETER Message
	    Text to append to the Edge removal log.

	    .EXAMPLE
	    Write-EdgeRemovalLog -Message 'Stopping Edge-related processes'
	#>
	function Write-EdgeRemovalLog
	{
		param([string]$Message)
		try
		{
			if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 512000)
			{
				Remove-Item $logFile -Force -ErrorAction SilentlyContinue
				$ts0 = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
				"$ts0 - Log rotated - previous log exceeded 500KB" | Out-File -FilePath $logFile
			}
			$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
			"$ts - $Message" | Out-File -FilePath $logFile -Append
		}
		catch
		{
			if (Get-Command -Name 'Write-SwallowedException' -CommandType Function -ErrorAction SilentlyContinue) { Write-SwallowedException -ErrorRecord $_ -Source 'UWPApps.Write-EdgeRemovalLog:catch488' -Severity Debug }

			# Logging must never break removal flow
		}
		LogInfo $Message
	}
	<#
	    .SYNOPSIS
	    Return the CBS package names for legacy Edge.

	    .DESCRIPTION
	    Reads the Component Based Servicing package list and returns the package names that identify the legacy UWP Edge payload.

	    .EXAMPLE
	    Get-LegacyEdgePackages
	#>
	function Get-LegacyEdgePackages
	{
		$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
		return Get-ChildItem -Path $regPath -Name -ErrorAction SilentlyContinue |
			Where-Object { $_ -match 'Microsoft-Windows-Internet-Browser-Package' -and $_ -match '~~' }
	}
	<#
	    .SYNOPSIS
	    Return whether the legacy Edge package is installed.

	    .DESCRIPTION
	    Queries the legacy Edge CBS packages and uses DISM package info to determine whether any package is still installed.

	    .EXAMPLE
	    Test-LegacyEdgeInstalled
	#>
		. (Join-Path $PSScriptRoot 'UWPApps\EdgeRemoval\EdgeDetectionHelpers.ps1')
	<#
	    .SYNOPSIS
	    Uninstall Chromium-based Edge and EdgeUpdate.

	    .DESCRIPTION
	    Runs the available Edge uninstall commands, stops related processes, and removes EdgeUpdate to finish the Chromium Edge cleanup.

	    .EXAMPLE
	    Remove-ChromiumEdge
	#>
		. (Join-Path $PSScriptRoot 'UWPApps\EdgeRemoval\ChromiumEdgeRemoval.ps1')

	# --- Main flow ---
	try
	{
		$userChoiceBackup = Backup-UserChoiceAssociations

		Write-EdgeRemovalLog 'Checking for Edge installations'
		$legacyInstalled = Test-LegacyEdgeInstalled
		$chromiumInstalled = Test-ChromiumEdgeInstalled

		if (-not $legacyInstalled -and -not $chromiumInstalled)
		{
			Write-EdgeRemovalLog 'No Edge installations detected; skipping removal'
		}

		# Stash ie_to_edge_stub.exe BEFORE removal so we can install the redirect afterward
		if ($chromiumInstalled)
		{
			Write-EdgeRemovalLog 'Locating ie_to_edge_stub.exe before Edge removal'
			$stubPath = $null
			$stubLocations = @("$env:ProgramData\ie_to_edge_stub.exe", "$env:Public\ie_to_edge_stub.exe")
			foreach ($loc in $stubLocations)
			{
				if (Test-Path $loc) { $stubPath = $loc; Write-EdgeRemovalLog "Found stub at $loc"; break }
			}
			if (-not $stubPath)
			{
				$found = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge" -Filter 'ie_to_edge_stub.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
				if ($found) { $stubPath = $found.FullName; Write-EdgeRemovalLog "Found stub at $stubPath" }
				else { Write-EdgeRemovalLog 'ie_to_edge_stub.exe not found in any location' }
			}
			if ($stubPath)
			{
				New-Item -ItemType Directory -Path $scriptsDir -Force -ErrorAction SilentlyContinue | Out-Null
				Copy-Item $stubPath (Join-Path $scriptsDir 'ie_to_edge_stub.exe') -Force -ErrorAction SilentlyContinue
				Write-EdgeRemovalLog "Cached ie_to_edge_stub.exe to $scriptsDir"
			}
		}

		$removedSomething = $false
		if ($legacyInstalled)
		{
			Write-EdgeRemovalLog 'Legacy Edge detected; proceeding with removal'
			Stop-EdgeProcesses
			Remove-LegacyEdge
			$removedSomething = $true
		}
		if ($chromiumInstalled)
		{
			Write-EdgeRemovalLog 'Chromium Edge detected; proceeding with removal'
			Stop-EdgeProcesses
			Remove-ChromiumEdge
			$removedSomething = $true
		}

		if ($removedSomething)
		{
			Write-EdgeRemovalLog 'Cleaning up Microsoft Edge folders (preserves EdgeWebView)'
			$edgeFolders = Get-ChildItem -Path "$env:SystemDrive\Program Files (x86)\Microsoft" -Directory -ErrorAction SilentlyContinue |
				Where-Object { ($_.Name -like '*Edge*' -or $_.Name -like '*Temp*') -and $_.Name -notlike '*EdgeWebView*' }
			if ($edgeFolders)
			{
				Write-EdgeRemovalLog "Found $($edgeFolders.Count) Edge-related folder(s) to remove"
				$edgeFolders | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
			}
			Remove-EdgeShortcuts
			Remove-EdgeRegistryKeys
			Remove-AdditionalEdgeFolders
		}

		# Redirect MSEdgeHTM via stub so existing UserChoice associations still resolve
		$cachedStub = Join-Path $scriptsDir 'ie_to_edge_stub.exe'
		if (Test-Path $cachedStub)
		{
			reg.exe add 'HKCR\MSEdgeHTM\shell\open\command' /f /ve /d "`"$cachedStub`" %1" 2>&1 | Out-Null
			Write-EdgeRemovalLog 'Redirected MSEdgeHTM to ie_to_edge_stub.exe'
		}
		else
		{
			reg.exe delete 'HKCR\MSEdgeHTM' /f 2>&1 | Out-Null
			Write-EdgeRemovalLog 'Removed MSEdgeHTM (stub not available)'
		}

		Install-EdgeProtocolRedirect

		Write-EdgeRemovalLog 'Removing Edge scheduled tasks'
		try
		{
			$edgeTasks = Get-ScheduledTask -TaskName '*Edge*' -ErrorAction SilentlyContinue
			if ($edgeTasks)
			{
				foreach ($task in $edgeTasks)
				{
					if ($task.TaskName -eq 'EdgeRemoval' -or $task.TaskName -eq 'OpenWebSearchRepair') { continue }
					Write-EdgeRemovalLog "Found Edge scheduled task: $($task.TaskName)"
					try
					{
						Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
						Write-EdgeRemovalLog "Deleted scheduled task $($task.TaskName)"
					}
					catch
					{
						Write-EdgeRemovalLog "Failed to delete $($task.TaskName): $($_.Exception.Message)"
					}
				}
			}
			else
			{
				Write-EdgeRemovalLog 'No Edge scheduled tasks found'
			}
		}
		catch
		{
			Write-EdgeRemovalLog "Failed to enumerate scheduled tasks: $($_.Exception.Message)"
		}

		Restore-UserChoiceAssociations -Backup $userChoiceBackup

		Write-EdgeRemovalLog 'Edge removal completed'
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-EdgeRemovalLog "Edge removal failed: $($_.Exception.Message)"
		Write-ConsoleStatus -Status failed
		LogError "Edge removal failed: $($_.Exception.Message)"
	}
}

<#
.SYNOPSIS
Enable or disable New Outlook



.DESCRIPTION

Enables or disables New Outlook in GUI and headless runs.
.PARAMETER Enable
Enable New Outlook

.PARAMETER Disable
Disable New Outlook

.EXAMPLE
NewOutlook -Enable

.EXAMPLE
NewOutlook -Disable

.NOTES
Current user
#>
function NewOutlook
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Enable"
		)]
		[switch]
		$Enable,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling New Outlook"
			LogInfo "Enabling New Outlook"
			Set-ItemProperty -LiteralPath "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Preferences" -Name "UseNewOutlook" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General" -Name "HideNewOutlookToggle" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Options\General" -Name "DoNewOutlookAutoMigration" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Preferences" -Name "NewOutlookMigrationUserSetting" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling New Outlook"
			LogInfo "Disabling New Outlook"
			Set-ItemProperty -LiteralPath "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Preferences" -Name "UseNewOutlook" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General" -Name "HideNewOutlookToggle" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Options\General" -Name "DoNewOutlookAutoMigration" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-RegistryValueSafe -Path "HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Preferences" -Name "NewOutlookMigrationUserSetting" | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
    .SYNOPSIS
    Enable or disable the notification tray and calendar flyout.

    .DESCRIPTION
    Toggles the Explorer policy and toast notification setting Baseline uses to control Notification Center availability.

    .PARAMETER Enable
    Turn the notification tray and calendar flyout on.

    .PARAMETER Disable
    Turn the notification tray and calendar flyout off.

    .EXAMPLE
    Notifications -Disable
#>
function Notifications
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Notification Tray/Calendar"
			LogInfo "Enabling Notification Tray/Calendar"
			Remove-RegistryValueSafe -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableNotificationCenter" | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Notification Tray/Calendar"
			LogInfo "Disabling Notification Tray/Calendar"
			if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer"))
			{
				New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force -ErrorAction SilentlyContinue | Out-Null
			}
			Set-ItemProperty -LiteralPath "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableNotificationCenter" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
    .SYNOPSIS
    Enable or disable the reverted Windows 11 Start Menu layout.

    .DESCRIPTION
    Toggles the supported Start Menu feature ID on eligible Windows 11 builds and keeps the temporary tool under the Baseline temp folder.

    .PARAMETER Enable
    Apply the reverted Start Menu feature toggle.

    .PARAMETER Disable
    Remove the reverted Start Menu feature toggle.

    .EXAMPLE
    RevertStartMenu -Enable
#>
function RevertStartMenu
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$baselineStartMenuToolUrl = "https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip"
	$featureId = "47205210"
	$tempDir = "$env:TEMP\BaselineStartMenuTool"
	$SupportedMessage = "Revert Start Menu is only supported on Windows 11 24H2 build 26100.7019+ or 26H1 build 28000.1575+ and newer. Skipping."
	$DownloadFailedMessage = "Unable to download Baseline Start Menu tool from GitHub. Skipping Revert Start Menu."
	$IsRevertStartMenuSupported = Test-Windows11FeatureBranchSupport -Thresholds @(
		@{ DisplayVersion = "24H2"; Build = 26100; UBR = 7019 },
		@{ DisplayVersion = "26H1"; Build = 28000; UBR = 1575 }
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Revert Start Menu"
			LogInfo "Enabling Revert Start Menu"

			if (-not $IsRevertStartMenuSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				# Create temp directory
				if (Test-Path $tempDir)
				{
					Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
				}
				New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

				$zipPath = "$tempDir\BaselineStartMenuTool.zip"
				Invoke-WebRequest $baselineStartMenuToolUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop | Out-Null
				LogInfo "Downloaded Baseline Start Menu tool"

				Expand-Archive $zipPath -DestinationPath $tempDir -Force -ErrorAction Stop | Out-Null
				LogInfo "Prepared Baseline Start Menu tool"

				$baselineStartMenuToolExe = "$tempDir\ViVeTool.exe"
				if (-not (Test-Path $baselineStartMenuToolExe))
				{
					throw "Baseline Start Menu tool was not found after preparation"
				}
				$baselineStartMenuToolProcess = Invoke-BaselineProcess -FilePath $baselineStartMenuToolExe -ArgumentList @('/disable', "/id:$featureId") -TimeoutSeconds 300
				if ($baselineStartMenuToolProcess.ExitCode -ne 0)
				{
					throw "Baseline Start Menu tool returned exit code $($baselineStartMenuToolProcess.ExitCode)"
				}
				LogInfo "Applied Baseline Start Menu setting to disable feature $featureId"

				# Cleanup
				Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
				LogInfo "Cleaned up temporary files"
				LogInfo $Localization.RestartWarning
				Write-ConsoleStatus -Status success
			}
			catch
			{
				if ($_.Exception.Message -match 'github\.com|remote name could not be resolved|The remote server returned an error|Unable to connect|connection could not be established')
				{
					LogWarning "$DownloadFailedMessage Error: $($_.Exception.Message)"
					# Write-Host: intentional -- user-visible progress indicator
					Write-Host "skipped!" -ForegroundColor Yellow
				}
				else
				{
					LogError "Failed to enable Revert Start Menu: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
				}
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Revert Start Menu"
			LogInfo "Disabling Revert Start Menu"

			if (-not $IsRevertStartMenuSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				# Create temp directory
				if (Test-Path $tempDir)
				{
					Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
				}
				New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

				$zipPath = "$tempDir\BaselineStartMenuTool.zip"
				Invoke-WebRequest $baselineStartMenuToolUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop | Out-Null
				LogInfo "Downloaded Baseline Start Menu tool"

				Expand-Archive $zipPath -DestinationPath $tempDir -Force -ErrorAction Stop | Out-Null
				LogInfo "Prepared Baseline Start Menu tool"

				$baselineStartMenuToolExe = "$tempDir\ViVeTool.exe"
				if (-not (Test-Path $baselineStartMenuToolExe))
				{
					throw "Baseline Start Menu tool was not found after preparation"
				}
				$baselineStartMenuToolProcess = Invoke-BaselineProcess -FilePath $baselineStartMenuToolExe -ArgumentList @('/enable', "/id:$featureId") -TimeoutSeconds 300
				if ($baselineStartMenuToolProcess.ExitCode -ne 0)
				{
					throw "Baseline Start Menu tool returned exit code $($baselineStartMenuToolProcess.ExitCode)"
				}
				LogInfo "Applied Baseline Start Menu setting to enable feature $featureId"

				# Cleanup
				Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
				LogInfo "Cleaned up temporary files"
				LogInfo $Localization.RestartWarning
				Write-ConsoleStatus -Status success
			}
			catch
			{
					$revertDisableError = $_.Exception.Message
					if ($revertDisableError -match 'github\.com|remote name could not be resolved|The remote server returned an error|Unable to connect|connection could not be established')
					{
						LogWarning ("{0} Error: {1}" -f $DownloadFailedMessage, $revertDisableError)
						# Write-Host: intentional -- user-visible progress indicator
						Write-Host "skipped!" -ForegroundColor Yellow
					}
					else
					{
						LogError ("Failed to disable Revert Start Menu: {0}" -f $revertDisableError)
						Write-ConsoleStatus -Status failed
					}
			}
		}
	}
}

<#
	.SYNOPSIS

	.DESCRIPTION
	Returns true for Windows security shell packages that Baseline must never
	offer or pass to Remove-AppxPackage from the generic UWP removal flow.
#>
function Test-UWPAppsProtectedPackage
{
	[CmdletBinding()]
	param
	(
		[string]
		$PackageName
	)

	if ([string]::IsNullOrWhiteSpace($PackageName))
	{
		return $false
	}

	$baseName = ([string]$PackageName).Split('_')[0]
	$protectedNames = @(
		"Microsoft.SecHealthUI",
		"Microsoft.Windows.SecHealthUI",
		"Microsoft.Windows.SecurityHealth",
		"Microsoft.WindowsSecurityHealth"
	)

	foreach ($protectedName in $protectedNames)
	{
		if ($baseName.Equals($protectedName, [System.StringComparison]::OrdinalIgnoreCase))
		{
			return $true
		}
	}

	return $false
}

<#
	.SYNOPSIS
	Install or uninstall UWP apps by using the graphical app picker.

	.DESCRIPTION
	Opens a graphical app picker that lists installable or removable Microsoft
	Store and inbox UWP packages, then applies the selected action.

	.PARAMETER Install
	Open the app picker and install the selected UWP apps.

	.PARAMETER Uninstall
	Open the app picker and uninstall the selected UWP apps.

	.PARAMETER ForAllUsers
	Apply the selected install or uninstall action for all users where supported.

	.EXAMPLE
	UWPApps -Install

	.EXAMPLE
	UWPApps -Uninstall

	.NOTES
	Current user

	.NOTES
	Use `-ForAllUsers` for machine-wide package provisioning changes where supported
#>

function UWPApps
{
	[CmdletBinding(DefaultParameterSetName = "None")]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Install")]
		[switch]
		$Install,

		[Parameter(Mandatory = $true, ParameterSetName = "Uninstall")]
		[switch]
		$Uninstall,

		[Parameter(Mandatory = $false)]
		[switch]
		$ForAllUsers,

		[Parameter(Mandatory = $false)]
		[string[]]
		$SelectedPackages,

		[Parameter(Mandatory = $false)]
		[switch]
		$CollectSelectionOnly,

		[Parameter(Mandatory = $false)]
		[switch]
		$NonInteractive
	)

	[void](Initialize-BaselineWinRtRuntimeDependencies)
	$script:UWPAppsSelectionResult = $null
	$script:UWPAppsSelectionSeed = if ($null -ne $SelectedPackages) { @($SelectedPackages) } else { @() }
	$script:UWPAppsExecutionResult = $null
	$SelectedPackagesProvided = $PSBoundParameters.ContainsKey('SelectedPackages')
		. (Join-Path $PSScriptRoot 'UWPApps\UWPApps\ModulePathResolution.ps1')
	$guiCommonPath = Resolve-UWPAppsGuiCommonPath -StartPath $modulePath

	<#
	    .SYNOPSIS
	    Request GUI UWP apps selection.

		#>

		. (Join-Path $PSScriptRoot 'UWPApps\UWPApps\GuiUwpAppsSelection.ps1')
		$setUWPAppsPickerSurface = ${function:Set-UWPAppsPickerSurface}

		$__baselineExtractedPartDidReturn = $false
		$__baselineExtractedPartHasReturnValue = $false
		$__baselineExtractedPartReturnValue = $null
		. (Join-Path $PSScriptRoot 'UWPApps\UWPApps\UwpAppsParameterSetExecution.ps1')
		if ($__baselineExtractedPartDidReturn) { if ($__baselineExtractedPartHasReturnValue) { return $__baselineExtractedPartReturnValue }; return }
}

#endregion UWP apps
$ExportedFunctions = @(
    'BackgroundApps',
    'Copilot',
    'CortanaAutostart',
    'EdgeDebloat',
    'EdgeRemoval',
    'NewOutlook',
    'Notifications',
    'RevertStartMenu',
    'Test-UWPAppsProtectedPackage',
    'UWPApps'
)
Export-ModuleMember -Function $ExportedFunctions
