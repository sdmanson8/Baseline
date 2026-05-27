using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1


<#
	.SYNOPSIS
	Ensure taskbar registry path.

	#>

function Ensure-UIPersonalizationTaskbarRegistryPath
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	if (-not (Test-Path -Path $Path))
	{
		New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
	}
}

<#
	.SYNOPSIS
	Configures taskbar and shell placement settings.



.DESCRIPTION

Applies Baseline's taskbar and shell placement settings in GUI and headless runs.
	.PARAMETER Left
	Set the taskbar alignment to the left

	.PARAMETER Center
	Set the taskbar alignment to the center (default value)

	.EXAMPLE
	Set-UIPersonalizationTaskbarAlignment -Center

	.EXAMPLE
	Set-UIPersonalizationTaskbarAlignment -Left

	.NOTES
	Current user
#>
function Set-UIPersonalizationTaskbarAlignment
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Left"
		)]
		[switch]
		$Left,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Center"
		)]
		[switch]
		$Center
	)

	$taskbarAdvancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Center"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Center"
			LogInfo "Setting the taskbar alignment to the Center"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "TaskbarAl" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the center: $($_.Exception.Message)"
			}
		}
		"Left"
		{
			Write-ConsoleStatus -Action "Setting the taskbar alignment to the Left"
			LogInfo "Setting the taskbar alignment to the Left"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "TaskbarAl" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set taskbar alignment to the left: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The widgets icon on the taskbar



.DESCRIPTION

Applies the Baseline behavior for the widgets icon on the taskbar.
	.PARAMETER Hide
	Hide the widgets icon on the taskbar

	.PARAMETER Show
	Show the widgets icon on the taskbar (default value)

	.EXAMPLE
	Set-UIPersonalizationTaskbarWidgets -Hide

	.EXAMPLE
	Set-UIPersonalizationTaskbarWidgets -Show

	.NOTES
	Current user
#>
function Set-UIPersonalizationTaskbarWidgets
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

	if (-not (Get-AppxPackage -Name MicrosoftWindows.Client.WebExperience -WarningAction SilentlyContinue))
	{
		LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests -Name value -Force -ErrorAction Ignore | Out-Null
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Dsh -Name AllowNewsAndInterests -Type CLEAR | Out-Null

	# UCPD driver blocks TaskbarDa registry writes from known executables.
	# Use copied PowerShell with guaranteed cleanup via shared helper.

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the widgets icon on the taskbar"
			LogInfo "Disabling the widgets icon on the taskbar"
			Invoke-UCPDBypassed -ScriptBlock {
				$path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}

				New-ItemProperty -Path $path -Name TaskbarDa -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the widgets icon on the taskbar"
			LogInfo "Enabling the widgets icon on the taskbar"
			Invoke-UCPDBypassed -ScriptBlock {
				$path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
				if (-not (Test-Path -Path $path))
				{
					New-Item -Path $path -Force -ErrorAction Stop | Out-Null
				}

				New-ItemProperty -Path $path -Name TaskbarDa -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
			}
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Search on the taskbar



.DESCRIPTION

Applies the Baseline behavior for search on the taskbar.
	.PARAMETER Hide
	Hide the search on the taskbar

	.PARAMETER SearchIcon
	Show the search icon on the taskbar

	.PARAMETER SearchBox
	Show the search box on the taskbar (default value)

	.EXAMPLE
	Set-UIPersonalizationTaskbarSearch -Hide

	.EXAMPLE
	Set-UIPersonalizationTaskbarSearch -SearchIcon

	.EXAMPLE
	Set-UIPersonalizationTaskbarSearch -SearchIconLabel

	.EXAMPLE
	Set-UIPersonalizationTaskbarSearch -SearchBox

	.NOTES
	Current user
#>

function Set-UIPersonalizationTaskbarSearch
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
			ParameterSetName = "SearchIcon"
		)]
		[switch]
		$SearchIcon,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchIconLabel"
		)]
		[switch]
		$SearchIconLabel,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "SearchBox"
		)]
		[switch]
		$SearchBox
	)

	$searchPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'

	# Remove all policies in order to make changes visible in UI only if it's possible
	Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Search\DisableSearch" `
		-Name "value" `
		-Value 0 `
		-Type DWord
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch, SearchOnTaskbarMode -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name DisableSearch -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name SearchOnTaskbarMode -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the search on the taskbar"
			LogInfo "Disabling the search on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchPath
				Set-RegistryValueSafe -Path $searchPath `
					-Name "SearchboxTaskbarMode" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide search on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIcon"
		{
			Write-ConsoleStatus -Action "Enabling the search icon on the taskbar"
			LogInfo "Enabling the search icon on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchPath
				Set-RegistryValueSafe -Path $searchPath `
					-Name "SearchboxTaskbarMode" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchIconLabel"
		{
			Write-ConsoleStatus -Action "Enabling the search icon label on the taskbar"
			LogInfo "Enabling the search icon label on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchPath
				Set-RegistryValueSafe -Path $searchPath `
					-Name "SearchboxTaskbarMode" `
					-Value 3 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search icon label on the taskbar: $($_.Exception.Message)"
			}
		}
		"SearchBox"
		{
			Write-ConsoleStatus -Action "Enabling the search box on the taskbar"
			LogInfo "Enabling the search box on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchPath
				Set-RegistryValueSafe -Path $searchPath `
					-Name "SearchboxTaskbarMode" `
					-Value 2 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the search box on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Search highlights



.DESCRIPTION

Applies the Baseline behavior for search highlights.
	.PARAMETER Hide
	Hide search highlights

	.PARAMETER Show
	Show search highlights (default value)

	.EXAMPLE
	Set-UIPersonalizationSearchHighlights -Hide

	.EXAMPLE
	Set-UIPersonalizationSearchHighlights -Show

	.NOTES
	Current user
#>
function Set-UIPersonalizationSearchHighlights
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

	$searchSettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name EnableDynamicContentInWSB -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling search highlights"
			LogInfo "Disabling search highlights"
			# Checking whether "Ask Copilot" and "Find results in Web" were disabled. They also disable Search Highlights automatically
			# We have to use GetValue() due to "Set-StrictMode -Version Latest"
			$BingSearchEnabled = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", $null))
			$DisableSearchBoxSuggestions = ([Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer", "DisableSearchBoxSuggestions", $null))
			if (($BingSearchEnabled -eq 1) -or ($DisableSearchBoxSuggestions -eq 1))
			{
				LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
			}
			else
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchSettingsPath
				Set-RegistryValueSafe -Path $searchSettingsPath `
					-Name "IsDynamicSearchBoxEnabled" `
					-Value 0 `
					-Type DWord

			}
			Write-ConsoleStatus -Status success
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling search highlights"
			LogInfo "Enabling search highlights"
			# Enable "Ask Copilot" and "Find results in Web" icons in Windows Search in order to enable Search Highlights
			Remove-RegistryValueSafe -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Search -Name BingSearchEnabled | Out-Null
			Remove-RegistryValueSafe -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name DisableSearchBoxSuggestions | Out-Null
			Ensure-UIPersonalizationTaskbarRegistryPath -Path $searchSettingsPath
			Set-RegistryValueSafe -Path $searchSettingsPath `
				-Name "IsDynamicSearchBoxEnabled" `
				-Value 1 `
				-Type DWord
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Task view button on the taskbar



.DESCRIPTION

Applies the Baseline behavior for task view button on the taskbar.
	.PARAMETER Hide
	Hide the Task view button on the taskbar

	.PARAMETER Show
	Show the Task View button on the taskbar (default value)

	.EXAMPLE
	Set-UIPersonalizationTaskViewButton -Hide

	.EXAMPLE
	Set-UIPersonalizationTaskViewButton -Show

	.NOTES
	Current user
#>
function Set-UIPersonalizationTaskViewButton
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

	$taskbarAdvancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-RegistryValueSafe -Path HKCU:\Software\Policies\Microsoft\Windows\Explorer, HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton | Out-Null
	Set-Policy -Scope User -Path Software\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\Explorer -Name HideTaskViewButton -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Hide"
		{
			Write-ConsoleStatus -Action "Disabling the Task view button on the taskbar"
			LogInfo "Disabling the Task view button on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "ShowTaskViewButton" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to hide the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
		"Show"
		{
			Write-ConsoleStatus -Action "Enabling the Task view button on the taskbar"
			LogInfo "Enabling the Task view button on the taskbar"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "ShowTaskViewButton" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to show the Task View button on the taskbar: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Combine taskbar buttons and hide labels



.DESCRIPTION

Applies the Baseline behavior for combine taskbar buttons and hide labels.
	.PARAMETER Always
	Combine taskbar buttons and always hide labels (default value)

	.PARAMETER Full
	Combine taskbar buttons and hide labels when taskbar is full

	.PARAMETER Never
	Combine taskbar buttons and never hide labels

	.EXAMPLE
	Set-UIPersonalizationTaskbarCombine -Always

	.EXAMPLE
	Set-UIPersonalizationTaskbarCombine -Full

	.EXAMPLE
	Set-UIPersonalizationTaskbarCombine -Never

	.NOTES
	Current user
#>

function Set-UIPersonalizationTaskbarCombine
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Always"
		)]
		[switch]
		$Always,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Full"
		)]
		[switch]
		$Full,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Never"
		)]
		[switch]
		$Never
	)

	$taskbarAdvancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-RegistryValueSafe -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoTaskGrouping -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Always"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and always hide labels"
			LogInfo "Combine taskbar buttons and always hide labels"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "TaskbarGlomLevel" `
					-Value 0 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to always combine taskbar buttons and hide labels: $($_.Exception.Message)"
			}
		}
		"Full"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and hide labels when taskbar is full"
			LogInfo "Combine taskbar buttons and hide labels when taskbar is full"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "TaskbarGlomLevel" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to combine taskbar buttons when the taskbar is full: $($_.Exception.Message)"
			}
		}
		"Never"
		{
			Write-ConsoleStatus -Action "Combine taskbar buttons and never hide labels"
			LogInfo "Combine taskbar buttons and never hide labels"
			try
			{
				Ensure-UIPersonalizationTaskbarRegistryPath -Path $taskbarAdvancedPath
				Set-RegistryValueSafe -Path $taskbarAdvancedPath `
					-Name "TaskbarGlomLevel" `
					-Value 2 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to never combine taskbar buttons and labels: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Unpin shortcuts from the taskbar



.DESCRIPTION

Applies the Baseline behavior for unpin shortcuts from the taskbar.
	.PARAMETER Edge
	Unpin Microsoft Edge shortcut from the taskbar

	.PARAMETER Store
	Unpin Microsoft Store from the taskbar

	.PARAMETER Outlook
	Unpin Outlook shortcut from the taskbar

	.PARAMETER Mail
	Unpin Mail shortcut from the taskbar

	.PARAMETER Copilot
	Unpin Copilot shortcut from the taskbar

	.PARAMETER Microsoft365
	Unpin Microsoft 365 shortcut from the taskbar

	.EXAMPLE
	Invoke-UIPersonalizationTaskbarShortcutUnpin -Shortcuts Edge, Store, Outlook, Mail, Copilot, Microsoft365

	.NOTES
	Current user
#>

function Invoke-UIPersonalizationTaskbarShortcutUnpin
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet("Edge", "Store", "Outlook", "Mail", "Copilot", "Microsoft365")]
		[string[]]
		$Shortcuts
	)

	$TaskbarPinnedPath = Join-Path $env:AppData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
	$IsARM64 = ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") -or
		($env:PROCESSOR_ARCHITEW6432 -eq "ARM64")
	if (-not $IsARM64)
	{
		try
		{
			$runtimeInfoType = [type]::GetType('System.Runtime.InteropServices.RuntimeInformation')
			$architectureType = [type]::GetType('System.Runtime.InteropServices.Architecture')
			if ($runtimeInfoType -and $architectureType)
			{
				$osArchitecture = $runtimeInfoType.GetProperty('OSArchitecture').GetValue($null, $null)
				$arm64Architecture = [System.Enum]::Parse($architectureType, 'Arm64')
				$IsARM64 = ($osArchitecture -eq $arm64Architecture)
			}
		}
		catch
		{
			Write-SwallowedException -ErrorRecord $_ -Source 'UIPersonalization.Taskbar.OSArchitecture' -Severity Debug
		}
	}
	$IsWindows10 = [System.Environment]::OSVersion.Version.Build -lt 22000
	# ARM64 and Windows 10 already needed the STA-runspace path (original condition).
	# AMD64 Windows 11 also needs it because direct COM shell verb calls silently do nothing on Win11 x64.
	$NeedsDeferredUnpin = $IsARM64 -or $IsWindows10 -or (-not $IsWindows10 -and -not $IsARM64)

	<#
	    .SYNOPSIS
	    Gets taskbar pinned items.

	#>

		. (Join-Path $PSScriptRoot 'Taskbar\Invoke-UIPersonalizationTaskbarShortcutUnpin\PinnedItemHelpers.ps1')

	$LocalizedString = [WinAPI.GetStrings]::GetString(5387)
	$AppsFolder = (New-Object -ComObject Shell.Application).NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")

	Write-ConsoleStatus -Action "Unpin taskbar apps"
	LogInfo "Unpin taskbar apps"
	$UnpinFailures = 0
	$UnpinMisses = 0

	# Always initialize the list; populated on ARM64 and Windows 10
	$DeferredUnpinNames = [System.Collections.Generic.List[string]]::new()

		. (Join-Path $PSScriptRoot 'Taskbar\Invoke-UIPersonalizationTaskbarShortcutUnpin\ShortcutUnpinWorkflow.ps1')

	# ARM64 and Windows 10: run COM unpin in a background STA runspace with timeout
	if ($NeedsDeferredUnpin -and $DeferredUnpinNames.Count -gt 0)
	{
		Invoke-UIPersonalizationARM64ShellUnpin -AppNames $DeferredUnpinNames.ToArray() -TimeoutSeconds 15
	}

	# Restart Explorer to apply taskbar changes
	try
	{
		Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
		Start-Sleep -Milliseconds 500
		[void](Invoke-UserLaunch -FilePath "explorer.exe" -Description "Explorer shell restart after taskbar unpin")
	}
	catch
	{
		LogWarning "Failed to restart Explorer after taskbar unpin: $($_.Exception.Message)"
	}

	if ($UnpinFailures -gt 0)
	{
		Write-ConsoleStatus -Status warning
	}
	else
	{
		Write-ConsoleStatus -Status success
	}
}

<#
	.SYNOPSIS
	End task in taskbar by right click



.DESCRIPTION

Applies the Baseline behavior for end task in taskbar by right click.
	.PARAMETER Enable
	Enable end task in taskbar by right click

	.PARAMETER Disable
	Disable end task in taskbar by right click (default value)

	.EXAMPLE
	Set-UIPersonalizationTaskbarEndTask -Enable

	.EXAMPLE
	Set-UIPersonalizationTaskbarEndTask -Disable

	.NOTES
	Current user
#>
function Set-UIPersonalizationTaskbarEndTask
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

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling 'End task in taskbar by right click'"
			LogInfo "Enabling 'End task in taskbar by right click'"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" `
					-Name "Set-UIPersonalizationTaskbarEndTask" `
					-Value 1 `
					-Type DWord
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'End task in taskbar by right click'"
			LogInfo "Disabling 'End task in taskbar by right click'"
			try
			{
				if (Get-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings -Name Set-UIPersonalizationTaskbarEndTask -ErrorAction SilentlyContinue)
				{
					Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "Set-UIPersonalizationTaskbarEndTask"
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable 'End task in taskbar by right click': $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Taskbar transparency/acrylic opacity slider



.DESCRIPTION

Applies the Baseline behavior for taskbar transparency/acrylic opacity slider.
	.PARAMETER Opacity
	Set taskbar acrylic opacity slider value (0-100)

	.EXAMPLE
	Set-TaskbarAcrylicOpacity -Opacity 50

	.NOTES
	Current user. Controls TaskbarAcrylicOpacity registry setting.
	Windows 11 only.
#>
function Set-TaskbarAcrylicOpacity
{
	param
	(
		[Parameter(
			Mandatory = $true
		)]
		[ValidateRange(0, 100)]
		[int]
		$Opacity
	)

	Write-ConsoleStatus -Action "Setting taskbar acrylic opacity to $Opacity%"
	LogInfo "Setting taskbar acrylic opacity to $Opacity%"
	try
	{
		# Convert percentage to Windows registry value (0-100)
		$registryValue = $Opacity

		Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
			-Name "TaskbarAcrylicOpacity" `
			-Value $registryValue `
			-Type DWord | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to set taskbar acrylic opacity: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Small taskbar icons (Windows 10 only)



.DESCRIPTION

Applies the Baseline behavior for small taskbar icons (Windows 10 only).
	.PARAMETER Enable
	Use small taskbar icons

	.PARAMETER Disable
	Use normal-sized taskbar icons

	.EXAMPLE
	Set-SmallTaskbarIcons -Enable

	.EXAMPLE
	Set-SmallTaskbarIcons -Disable

	.NOTES
	Current user. Windows 10 only. Controls TaskbarSmallIcons setting.
#>
function Set-SmallTaskbarIcons
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
			Write-ConsoleStatus -Action "Enabling small taskbar icons"
			LogInfo "Enabling small taskbar icons (Windows 10 only)"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TaskbarSmallIcons" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable small taskbar icons: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling small taskbar icons"
			LogInfo "Disabling small taskbar icons"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "TaskbarSmallIcons" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable small taskbar icons: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Alt+Tab filter to exclude Edge tabs



.DESCRIPTION

Applies the Baseline behavior for alt+Tab filter to exclude Edge tabs.
	.PARAMETER Enable
	Exclude Edge tabs from Alt+Tab switcher

	.PARAMETER Disable
	Include Edge tabs in Alt+Tab switcher

	.EXAMPLE
	Set-AltTabEdgeTabFilter -Enable

	.EXAMPLE
	Set-AltTabEdgeTabFilter -Disable

	.NOTES
	Current user. Controls MultiTaskingAltTabFilter setting.
#>
function Set-AltTabEdgeTabFilter
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
			Write-ConsoleStatus -Action "Excluding Edge tabs from Alt+Tab"
			LogInfo "Excluding Edge tabs from Alt+Tab switcher"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "MultiTaskingAltTabFilter" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set Alt+Tab Edge tab filter: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Including Edge tabs in Alt+Tab"
			LogInfo "Including Edge tabs in Alt+Tab switcher"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "MultiTaskingAltTabFilter" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to remove Alt+Tab Edge tab filter: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Battery percentage in the system tray (laptops only)



.DESCRIPTION

Applies the Baseline behavior for battery percentage in the system tray (laptops only).
	.PARAMETER Enable
	Show battery percentage on the tray battery icon

	.PARAMETER Disable
	Restore the default (icon only, no percentage)

	.EXAMPLE
	BatteryPercentage -Enable

	.EXAMPLE
	BatteryPercentage -Disable

	.NOTES
	Current user. Short-circuits with no registry write on machines without
	a battery (Win32_Battery returns null on desktops). Enable writes 1;
	Disable deletes the value so the toggle isn't stuck off.
#>
function BatteryPercentage
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$hasBattery = $false
	try
	{
		$battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop
		if ($battery) { $hasBattery = $true }
	}
	catch
	{
		Write-SwallowedException -ErrorRecord $_ -Source 'UIPersonalization.Taskbar.BatteryPercentage.Detect'
	}

	if (-not $hasBattery)
	{
		LogInfo "No battery detected; skipping battery percentage toggle"
		Write-ConsoleStatus -Action "Skipping battery percentage (no battery)"
		Write-ConsoleStatus -Status success
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Showing battery percentage in system tray"
			LogInfo "Enabling battery percentage in system tray"
			try
			{
				Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "IsBatteryPercentageEnabled" `
					-Value 1 `
					-Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable battery percentage: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Hiding battery percentage in system tray"
			LogInfo "Disabling battery percentage in system tray"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
					-Name "IsBatteryPercentageEnabled" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable battery percentage: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'BatteryPercentage',
    'Ensure-UIPersonalizationTaskbarRegistryPath',
    'Set-UIPersonalizationSearchHighlights',
    'Set-AltTabEdgeTabFilter',
    'Set-SmallTaskbarIcons',
    'Set-TaskbarAcrylicOpacity',
    'Set-UIPersonalizationTaskbarAlignment',
    'Set-UIPersonalizationTaskbarCombine',
    'Set-UIPersonalizationTaskbarEndTask',
    'Set-UIPersonalizationTaskbarSearch',
    'Set-UIPersonalizationTaskbarWidgets',
    'Set-UIPersonalizationTaskViewButton',
    'Invoke-UIPersonalizationTaskbarShortcutUnpin'
)
Export-ModuleMember -Function $ExportedFunctions
