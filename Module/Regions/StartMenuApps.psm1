using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Start Menu Apps

<#
	.SYNOPSIS
	Most used apps in Start

	.PARAMETER Hide
	Hide most used Apps in Start (default value)

	.PARAMETER Show
	Show most used Apps in Start

	.EXAMPLE
	MostUsedStartApps -Hide

	.EXAMPLE
	MostUsedStartApps -Show

	.NOTES
	Current user
#>
function MostUsedStartApps
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name ShowOrHideMostUsedApps -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name ShowOrHideMostUsedApps -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name ShowOrHideMostUsedApps -Type CLEAR | Out-Null

	Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoStartMenuMFUprogramsList, NoInstrumentation -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoStartMenuMFUprogramsList -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoInstrumentation -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoStartMenuMFUprogramsList -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoInstrumentation -Type CLEAR | Out-Null

	if (Get-Process -Name Start11Srv, StartAllBackCfg, StartMenu -ErrorAction Ignore)
	{
		LogWarning ($Localization.CustomStartMenu, ($Localization.Skipped -f $MyInvocation.Line.Trim()) -join " ")

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			try
			{
				$StartSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
				Write-ConsoleStatus -Action "Hiding most used apps on Start"
				LogInfo "Hiding most used apps on Start"
				if (-not (Test-Path -Path $StartSettingsPath))
				{
					New-Item -Path $StartSettingsPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $StartSettingsPath -Name ShowFrequentList -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide most used apps on Start: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			try
			{
				$StartSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
				Write-ConsoleStatus -Action "Showing most used apps on Start"
				LogInfo "Showing most used apps on Start"
				if ((Test-Path -Path $StartSettingsPath) -and ($null -ne (Get-ItemProperty -Path $StartSettingsPath -Name ShowFrequentList -ErrorAction SilentlyContinue)))
				{
					Remove-ItemProperty -Path $StartSettingsPath -Name ShowFrequentList -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show most used apps on Start: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recently added apps on Start

	.PARAMETER Hide
	Hide recently added apps on Start

	.PARAMETER Show
	Show recently added apps in Start (default value)

	.EXAMPLE
	RecentlyAddedStartApps -Hide

	.EXAMPLE
	RecentlyAddedStartApps -Show

	.NOTES
	Current user
#>
function RecentlyAddedStartApps
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	# Remove all policies in order to make changes visible in UI
	Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecentlyAddedApps -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name HideRecentlyAddedApps -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecentlyAddedApps -Type CLEAR | Out-Null

	if (Get-Process -Name Start11Srv, StartAllBackCfg, StartMenu -ErrorAction Ignore)
	{
		LogWarning ($Localization.CustomStartMenu, ($Localization.Skipped -f $MyInvocation.Line.Trim()) -join " ")

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			try
			{
				$StartSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
				Write-ConsoleStatus -Action "Hiding recently added apps on Start"
				LogInfo "Hiding recently added apps on Start"
				if (-not (Test-Path -Path $StartSettingsPath))
				{
					New-Item -Path $StartSettingsPath -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path $StartSettingsPath -Name ShowRecentList -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide recently added apps on Start: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			try
			{
				$StartSettingsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
				Write-ConsoleStatus -Action "Showing recently added apps on Start"
				LogInfo "Showing recently added apps on Start"
				if ((Test-Path -Path $StartSettingsPath) -and ($null -ne (Get-ItemProperty -Path $StartSettingsPath -Name ShowRecentList -ErrorAction SilentlyContinue)))
				{
					Remove-ItemProperty -Path $StartSettingsPath -Name ShowRecentList -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show recently added apps on Start: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	All section with categories in Start

	.PARAMETER Hide
	Remove the All section with categories in Start

	.PARAMETER Show
	Show the All section with categories in Start (default value)

	.EXAMPLE
	StartMenuAllSectionCategories -Hide

	.EXAMPLE
	StartMenuAllSectionCategories -Show

	.NOTES
	Current user
#>
function StartMenuAllSectionCategories
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Hide"
		)]
		[switch]
		$Hide,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Show"
		)]
		[switch]
		$Show
	)

	$SupportedMessage = "Start menu All section categories is only supported on Windows 11 24H2 build 26100.7705+ or 26H1 build 28000.1575+ and newer. Skipping."
	$IsStartMenuAllSectionCategoriesSupported = Test-Windows11FeatureBranchSupport -Thresholds @(
		@{ DisplayVersion = "24H2"; Build = 26100; UBR = 7705 },
		@{ DisplayVersion = "26H1"; Build = 28000; UBR = 1575 }
	)

	if (-not $IsStartMenuAllSectionCategoriesSupported)
	{
		switch ($PSCmdlet.ParameterSetName)
		{
			"Hide"
			{
				Write-ConsoleStatus -Action "Hiding the All section with categories in Start"
				LogInfo "Hiding the All section with categories in Start"
			}
			"Show"
			{
				Write-ConsoleStatus -Action "Showing the All section with categories in Start"
				LogInfo "Showing the All section with categories in Start"
			}
		}

		Write-ConsoleStatus -Status success
		LogWarning $SupportedMessage
		return
	}

	if (Get-Process -Name Start11Srv, StartAllBackCfg, StartMenu -ErrorAction Ignore)
	{
		LogWarning ($Localization.CustomStartMenu, ($Localization.Skipped -f $MyInvocation.Line.Trim()) -join " ")

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			try
			{
				Write-ConsoleStatus -Action "Hiding the All section with categories in Start"
				LogInfo "Hiding the All section with categories in Start"
				Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoStartMenuMorePrograms -Type DWord -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the All section with categories in Start: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			try
			{
				Write-ConsoleStatus -Action "Showing the All section with categories in Start"
				LogInfo "Showing the All section with categories in Start"
				Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoStartMenuMorePrograms -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the All section with categories in Start: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Most used apps list in Start Menu

	.PARAMETER Enable
	Show most used apps list in Start Menu

	.PARAMETER Disable
	Hide most used apps list in Start Menu

	.EXAMPLE
	MostUsedApps -Enable

	.EXAMPLE
	MostUsedApps -Disable

	.NOTES
	Current user
#>
function MostUsedApps
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
			Write-ConsoleStatus -Action "Enabling most used apps list in Start Menu"
			LogInfo "Enabling most used apps list in Start Menu"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoStartMenuMFUprogramsList" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoStartMenuMFUprogramsList" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable most used apps in Start Menu: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling most used apps list in Start Menu"
			LogInfo "Disabling most used apps list in Start Menu"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoStartMenuMFUprogramsList" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable most used apps in Start Menu: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recently added apps list in Start Menu

	.PARAMETER Enable
	Show recently added apps list in Start Menu

	.PARAMETER Disable
	Hide recently added apps list in Start Menu

	.EXAMPLE
	RecentlyAddedApps -Enable

	.EXAMPLE
	RecentlyAddedApps -Disable

	.NOTES
	Current user
#>
function RecentlyAddedApps
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
			Write-ConsoleStatus -Action "Enabling recently added apps list in Start Menu"
			LogInfo "Enabling recently added apps list in Start Menu"
			try
			{
				if (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecentlyAddedApps" -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecentlyAddedApps" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable recently added apps in Start Menu: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling recently added apps list in Start Menu"
			LogInfo "Disabling recently added apps list in Start Menu"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecentlyAddedApps" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable recently added apps in Start Menu: $($_.Exception.Message)"
			}
		}
	}
}
