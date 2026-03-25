using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region Start menu

<#
	.SYNOPSIS
	Bing search in Start Menu

	.PARAMETER Disable
	Disable Bing search in Start Menu

	.PARAMETER Enable
	Enable Bing search in Start Menu (default value)

	.EXAMPLE
	BingSearch -Disable

	.EXAMPLE
	BingSearch -Enable

	.NOTES
	Current user
#>
function BingSearch
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

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Bing search in Start Menu"
			LogInfo "Disabling Bing search in Start Menu"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer))
				{
					New-Item -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null

				Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -Type DWORD -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Bing search in Start Menu: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Bing search in Start Menu"
			LogInfo "Enabling Bing search in Start Menu"
			try
			{
				if (Test-Path -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer)
				{
					Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -Force -ErrorAction Stop | Out-Null
				}
				Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Bing search in Start Menu: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Microsoft account-related notifications on Start Menu

	.PARAMETER Hide
	Do not show Microsoft account-related notifications on Start Menu in Start menu

	.PARAMETER Show
	Show Microsoft account-related notifications on Start Menu in Start menu (default value)

	.EXAMPLE
	StartAccountNotifications -Hide

	.EXAMPLE
	StartAccountNotifications -Show

	.NOTES
	Current user
#>
function StartAccountNotifications
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

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling Microsoft account-related notifications on Start Menu in Start menu"
			LogInfo "Disabling Microsoft account-related notifications on Start Menu in Start menu"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_AccountNotifications -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide Microsoft account-related notifications in Start menu: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling Microsoft account-related notifications on Start Menu in Start menu"
			LogInfo "Enabling Microsoft account-related notifications on Start Menu in Start menu"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_AccountNotifications -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_AccountNotifications -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show Microsoft account-related notifications in Start menu: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recommendations for tips, shortcuts, new apps, and more in Start menu

	.PARAMETER Hide
	Do not show recommendations for tips, shortcuts, new apps, and more in Start menu

	.PARAMETER Show
	Show recommendations for tips, shortcuts, new apps, and more in Start menu (default value)

	.EXAMPLE
	StartRecommendationsTips -Hide

	.EXAMPLE
	StartRecommendationsTips -Show

	.NOTES
	Current user
#>
function StartRecommendationsTips
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

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling Recommendations for tips, shortcuts, new apps, and more in Start menu"
			LogInfo "Disabling Recommendations for tips, shortcuts, new apps, and more in Start menu"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_IrisRecommendations -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide Start menu recommendations for tips, shortcuts, new apps, and more: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling Recommendations for tips, shortcuts, new apps, and more in Start menu"
			LogInfo "Enabling Recommendations for tips, shortcuts, new apps, and more in Start menu"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_IrisRecommendations -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_IrisRecommendations -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show Start menu recommendations for tips, shortcuts, new apps, and more: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Web Search functionality in the Start Menu

	.PARAMETER Disable
	Disable Web Search in the Start Menu

	.PARAMETER Enable
	Enable Web Search in the Start Menu (default value)

	.EXAMPLE
	WebSearch -Disable

	.EXAMPLE
	WebSearch -Enable

	.NOTES
	Current user
#>
function WebSearch
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
			Write-ConsoleStatus -Action "Enabling Web Search in the Start Menu"
			LogInfo "Enabling Web Search in the Start Menu"
			try
			{
				if (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")
				{
					Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -ErrorAction Stop | Out-Null
					Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				}
				if (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")
				{
					Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Web Search in the Start Menu: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Web Search in the Start Menu"
			LogInfo "Disabling Web Search in the Start Menu"
			try
			{
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Web Search in the Start Menu: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Configure Start layout

	.PARAMETER Default
	Show default Start layout (default value)

	.PARAMETER ShowMorePins
	Show more pins on Start

	.PARAMETER ShowMoreRecommendations
	Show more recommendations on Start

	.EXAMPLE
	StartLayout -Default

	.EXAMPLE
	StartLayout -ShowMorePins

	.EXAMPLE
	StartLayout -ShowMoreRecommendations

	.NOTES
	Current user
#>
function StartLayout
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "ShowMorePins"
		)]
		[switch]
		$ShowMorePins,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "ShowMoreRecommendations"
		)]
		[switch]
		$ShowMoreRecommendations
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Default"
		{
			Write-ConsoleStatus -Action "Setting default Start layout"
			LogInfo "Setting default Start layout"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_Layout -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set the default Start layout: $($_.Exception.Message)"
			}
		}
		"ShowMorePins"
		{
			Write-ConsoleStatus -Action "Showing more pins on Start"
			LogInfo "Showing more pins on Start"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_Layout -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show more pins on Start: $($_.Exception.Message)"
			}
		}
		"ShowMoreRecommendations"
		{
			Write-ConsoleStatus -Action "Showing more recommendations on Start"
			LogInfo "Showing more recommendations on Start"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Start_Layout -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show more recommendations on Start: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Recommended section in Start Menu

	.PARAMETER Hide
	Remove Recommended section in Start Menu

	.PARAMETER Show
	Do not remove Recommended section in Start Menu

	.EXAMPLE
	StartRecommendedSection -Hide

	.EXAMPLE
	StartRecommendedSection -Show

	.NOTES
	Current user
#>
function StartRecommendedSection
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

	# We cannot call [WinAPI.Winbrand]::BrandingFormatString("%WINDOWS_LONG%") here per this approach does not show a localized Windows edition name
	# Windows 11 Home not supported
	if ((Get-ComputerInfo).WindowsProductName -match "Home")
	{
		LogInfo ($Localization.Skipped -f $MyInvocation.Line.Trim())
	}

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Recommended section in the Start Menu"
			LogInfo "Disabling the Recommended section in the Start Menu"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer))
				{
					New-Item -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Force -ErrorAction Stop | Out-Null
				}
				if (-not (Test-Path -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education))
				{
					New-Item -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education -Name IsEducationEnvironment -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null

				Set-Policy -Scope User -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -Type DWORD -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Recommended section in the Start Menu: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Recommended section in the Start Menu"
			LogInfo "Enabling the Recommended section in the Start Menu"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -Force -ErrorAction Stop | Out-Null
				}
				if (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education -Name IsEducationEnvironment -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education -Name IsEducationEnvironment -Force -ErrorAction Stop | Out-Null
				}
				if (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start -Name HideRecommendedSection -ErrorAction SilentlyContinue)
				{
					Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start -Name HideRecommendedSection -Force -ErrorAction Stop | Out-Null
				}
				Set-Policy -Scope User -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideRecommendedSection -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Recommended section in the Start Menu: $($_.Exception.Message)"
			}
		}
	}
}
