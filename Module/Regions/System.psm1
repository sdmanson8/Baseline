using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

# Sub-modules extracted for maintainability
$systemSubModuleRoot = Join-Path $PSScriptRoot 'System'
if (Test-Path $systemSubModuleRoot)
{
    foreach ($subModule in (Get-ChildItem -Path $systemSubModuleRoot -Filter '*.psm1' -File))
    {
        Import-Module $subModule.FullName -Force -Global
    }
}

#region System
<#
.SYNOPSIS
Create or remove the desktop shortcut that reboots into Advanced Startup.

.EXAMPLE
AdvancedStartupShortcut -Enable

.EXAMPLE
AdvancedStartupShortcut -Disable

.NOTES
Current user
#>
function AdvancedStartupShortcut {
    [CmdletBinding(DefaultParameterSetName = 'Enable')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
        [switch]$Enable,

        [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
        [switch]$Disable
    )

    $desktopPath = Get-AdvancedStartupDesktopDirectory
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        Write-ConsoleStatus -Action "Configuring Advanced Startup shortcut" -Status failed
        LogError 'Unable to resolve the Desktop directory for the Advanced Startup shortcut'
        return
    }

    $shortcutPath = Join-Path $desktopPath 'Advanced Startup (REBOOT).lnk'

    if ($Disable) {
        $hadIssue = $false
        Write-ConsoleStatus -Action "Removing Advanced Startup shortcut"

        foreach ($pathToRemove in @($shortcutPath, (Get-AdvancedStartupCommandPath))) {
            try {
                if (Test-Path -LiteralPath $pathToRemove) {
                    Remove-Item -LiteralPath $pathToRemove -Force -ErrorAction Stop
                    LogInfo "Removed Advanced Startup asset: $pathToRemove"
                }
            }
            catch {
                $hadIssue = $true
                LogWarning "Failed to remove Advanced Startup asset $pathToRemove : $_"
            }
        }

        if ($hadIssue) {
            Write-ConsoleStatus -Status warning
        }
        else {
            Write-ConsoleStatus -Status success
        }

        return
    }

    $hadIssue = $false
    Write-ConsoleStatus -Action "Creating Advanced Startup shortcut"

    try {
        if (-not (Enable-AdvancedStartupWindowsRecoveryEnvironment)) {
            $hadIssue = $true
        }

        $commandPath = Set-AdvancedStartupCommandFile
        $downloadsPath = Get-AdvancedStartupDownloadsDirectory
        $iconLocation = Get-AdvancedStartupIconLocation -DownloadsPath $downloadsPath

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = Get-AdvancedStartupShortcutArguments -CommandPath $commandPath
        $shortcut.WorkingDirectory = $env:WINDIR
        $shortcut.Description = 'Reboot directly into Advanced Startup options.'

        $iconPath = ($iconLocation -split ',', 2)[0].Trim()
        if (-not [string]::IsNullOrWhiteSpace($iconPath) -and (Test-Path -LiteralPath $iconPath)) {
            $shortcut.IconLocation = $iconLocation
        }

        $shortcut.Save()
        LogInfo 'Created Advanced Startup desktop shortcut'
    }
    catch {
        $hadIssue = $true
        LogWarning "Failed to create Advanced Startup shortcut: $_"
    }

    if ($hadIssue) {
        Write-ConsoleStatus -Status warning
    }
    else {
        Write-ConsoleStatus -Status success
    }
}

<#
	.SYNOPSIS
	Automatic installing suggested apps

	.PARAMETER Disable
	Turn off automatic installing suggested apps

	.PARAMETER Enable
	Turn on automatic installing suggested apps (default value)

	.EXAMPLE
	AppsSilentInstalling -Disable

	.EXAMPLE
	AppsSilentInstalling -Enable

	.NOTES
	Current user
#>
function AppsSilentInstalling
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent -Name DisableWindowsConsumerFeatures -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\CloudContent -Name DisableWindowsConsumerFeatures -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Automatic installing of suggested apps"
			LogInfo "Disabling Automatic installing of suggested apps"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SilentInstalledAppsEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable automatic installing of suggested apps: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Automatic installing of suggested apps"
			LogInfo "Enabling Automatic installing of suggested apps"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager -Name SilentInstalledAppsEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable automatic installing of suggested apps: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The User Account Control (UAC) behavior

	.PARAMETER Never
	Never notify

	.PARAMETER Default
	Notify me only when apps try to make changes to my computer (default value)

	.EXAMPLE
	AdminApprovalMode -Never

	.EXAMPLE
	AdminApprovalMode -Default

	.NOTES
	Machine-wide
#>
function AdminApprovalMode
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Never"
		)]
		[switch]
		$Never,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	# Remove all policies in order to make changes visible in UI only if it's possible
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorUser -PropertyType DWord -Value 3 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableInstallerDetection -PropertyType DWord -Value 1 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ValidateAdminCodeSignatures -PropertyType DWord -Value 0 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableSecureUIAPaths -PropertyType DWord -Value 1 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableLUA -PropertyType DWord -Value 1 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name PromptOnSecureDesktop -PropertyType DWord -Value 1 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableVirtualization -PropertyType DWord -Value 1 -Force | Out-Null
	New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableUIADesktopToggle -PropertyType DWord -Value 1 -Force | Out-Null

	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name FilterAdministratorToken -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorUser -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableInstallerDetection -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ValidateAdminCodeSignatures -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableSecureUIAPaths -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableLUA -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name PromptOnSecureDesktop -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableVirtualization -Type CLEAR | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableUIADesktopToggle -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Never"
		{
			Write-ConsoleStatus -Action "Setting UAC to 'Never notify'"
			LogInfo "Setting UAC to 'Never notify'"
			try
			{
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set UAC to 'Never notify': $($_.Exception.Message)"
			}
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting UAC to 'Notify me only when apps try to make changes to my computer'"
			LogInfo "Setting UAC to 'Notify me only when apps try to make changes to my computer'"
			try
			{
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin -PropertyType DWord -Value 5 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set UAC to the default notification level: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	AutoPlay for all media and devices

	.PARAMETER Disable
	Don't use AutoPlay for all media and devices

	.PARAMETER Enable
	Use AutoPlay for all media and devices (default value)

	.EXAMPLE
	Autoplay -Disable

	.EXAMPLE
	Autoplay -Enable

	.NOTES
	Current user
#>
function Autoplay
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer, HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoDriveTypeAutoRun -Force -ErrorAction SilentlyContinue | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoDriveTypeAutoRun -Type CLEAR | Out-Null
	Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Explorer -Name NoDriveTypeAutoRun -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling AutoPlay for all media and devices"
			LogInfo "Disabling AutoPlay for all media and devices"
			New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers -Name DisableAutoplay -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling AutoPlay for all media and devices"
			LogInfo "Enabling AutoPlay for all media and devices"
			New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers -Name DisableAutoplay -PropertyType DWord -Value 0 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Stop error code when BSoD occurs

	.PARAMETER Enable
	Display Stop error code when BSoD occurs

	.PARAMETER Disable
	Do not display stop error code when BSoD occurs (default value)

	.EXAMPLE
	BSoDStopError -Enable

	.EXAMPLE
	BSoDStopError -Disable

	.NOTES
	Machine-wide
#>
function BSoDStopError
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
			Write-ConsoleStatus -Action "Enabling BSoD Stop Error"
			LogInfo "Enabling BSoD Stop Error"
			try
			{
				New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl -Name DisplayParameters -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable BSoD stop error details: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling BSoD Stop Error"
			LogInfo "Disabling BSoD Stop Error"
			try
			{
				New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl -Name DisplayParameters -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable BSoD stop error details: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Caps Lock

	.PARAMETER Disable
	Disable Caps Lock

	.PARAMETER Enable
	Enable Caps Lock (default value)

	.EXAMPLE
	CapsLock -Disable

	.EXAMPLE
	CapsLock -Enable

	.NOTES
	Machine-wide

#>
function CapsLock
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

	Remove-ItemProperty -Path "HKCU:\Keyboard Layout" -Name Attributes -Force -ErrorAction SilentlyContinue | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Caps Lock"
			LogInfo "Disabling Caps Lock"
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -PropertyType Binary -Value ([byte[]](0,0,0,0,0,0,0,0,2,0,0,0,0,0,58,0,0,0,0,0)) -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Caps Lock"
			LogInfo "Enabling Caps Lock"
			Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Override for default input method

	.PARAMETER English
	Override for default input method: English

	.PARAMETER Default
	Override for default input method: use language list (default value)

	.EXAMPLE
	InputMethod -English

	.EXAMPLE
	InputMethod -Default

	.NOTES
	Current user
#>
function InputMethod
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "English"
		)]
		[switch]
		$English,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Default"
		)]
		[switch]
		$Default
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"English"
		{
			Write-ConsoleStatus -Action "Setting override for default input method to English"
			LogInfo "Setting override for default input method to English"
			Set-WinDefaultInputMethodOverride -InputTip "0409:00000409" | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Default"
		{
			Write-ConsoleStatus -Action "Setting override for default input method to use language list"
			LogInfo "Setting override for default input method to use language list"
			Remove-ItemProperty -Path "HKCU:\Control Panel\International\User Profile" -Name InputMethodOverride -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Default terminal app

	.PARAMETER WindowsTerminal
	Set Windows Terminal as default terminal app to host the user interface for command-line applications

	.PARAMETER ConsoleHost
	Set Windows Console Host as default terminal app to host the user interface for command-line applications (default value)

	.EXAMPLE
	DefaultTerminalApp -WindowsTerminal

	.EXAMPLE
	DefaultTerminalApp -ConsoleHost

	.NOTES
	Current user
#>
function DefaultTerminalApp
{
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "WindowsTerminal"
		)]
		[switch]
		$WindowsTerminal,

		[Parameter(
			Mandatory = $true,
			ParameterSetName = "ConsoleHost"
		)]
		[switch]
		$ConsoleHost
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"WindowsTerminal"
		{
			if (Get-AppxPackage -Name Microsoft.WindowsTerminal -WarningAction SilentlyContinue)
			{
				Write-ConsoleStatus -Action "Setting Windows Terminal as default terminal app"
				LogInfo "Setting Windows Terminal as default terminal app"
				# Checking if the Terminal version supports such feature
				$TerminalVersion = (Get-AppxPackage -Name Microsoft.WindowsTerminal -WarningAction SilentlyContinue).Version
				if ([System.Version]$TerminalVersion -ge [System.Version]"1.11")
				{
					if (-not (Test-Path -Path "HKCU:\Console\%%Startup"))
					{
						New-Item -Path "HKCU:\Console\%%Startup" -Force -ErrorAction SilentlyContinue | Out-Null
					}

					# Find the current GUID of Windows Terminal
					$PackageFullName = (Get-AppxPackage -Name Microsoft.WindowsTerminal -WarningAction SilentlyContinue).PackageFullName
					Get-ChildItem -Path "HKLM:\SOFTWARE\Classes\PackagedCom\Package\$PackageFullName\Class" | ForEach-Object -Process {
						if ((Get-ItemPropertyValue -Path $_.PSPath -Name ServerId) -eq 0)
						{
							New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name DelegationConsole -PropertyType String -Value $_.PSChildName -Force -ErrorAction SilentlyContinue | Out-Null
						}

						if ((Get-ItemPropertyValue -Path $_.PSPath -Name ServerId) -eq 1)
						{
							New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name DelegationTerminal -PropertyType String -Value $_.PSChildName -Force -ErrorAction SilentlyContinue | Out-Null
						}
					}
				}
				Write-ConsoleStatus -Status success
			}
		}
		"ConsoleHost"
		{
			Write-ConsoleStatus -Action "Setting Windows Console Host as default terminal app"
			LogInfo "Setting Windows Console Host as default terminal app"
			New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name DelegationConsole -PropertyType String -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}" -Force -ErrorAction SilentlyContinue | Out-Null
			New-ItemProperty -Path "HKCU:\Console\%%Startup" -Name DelegationTerminal -PropertyType String -Value "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}" -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Help look up via F1

	.PARAMETER Disable
	Disable help lookup via F1

	.PARAMETER Enable
	Enable help lookup via F1 (default value)

	.EXAMPLE
	F1HelpPage -Disable

	.EXAMPLE
	F1HelpPage -Enable

	.NOTES
	Current user
#>
function F1HelpPage
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
			Write-ConsoleStatus -Action "Disabling help look up via F1"
			LogInfo "Disabling help look up via F1"
			if (-not (Test-Path -Path "HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64"))
			{
				New-Item -Path "HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64" -Force | Out-Null
			}
			New-ItemProperty -Path "HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64" -Name "(default)" -PropertyType String -Value "" -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling help look up via F1"
			LogInfo "Enabling help look up via F1"
			Remove-Item -Path "HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}" -Recurse -Force -ErrorAction Ignore | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Use the latest installed .NET runtime for all apps usage

	.PARAMETER Enable
	Use the latest installed .NET runtime for all apps

	.PARAMETER Disable
	Do not use the latest installed .NET runtime for all apps (default value)

	.EXAMPLE
	LatestInstalled.NET -Enable

	.EXAMPLE
	LatestInstalled.NET -Disable

	.NOTES
	Machine-wide
#>
function LatestInstalled.NET
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
			Write-ConsoleStatus -Action "Enabling the use of the latest installed .NET runtime for all apps"
			LogInfo "Enabling the use of the latest installed .NET runtime for all apps"
			New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\.NETFramework -Name OnlyUseLatestCLR -PropertyType DWord -Value 1 -Force | Out-Null
			New-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework -Name OnlyUseLatestCLR -PropertyType DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			# Write-Host: intentional — user-visible progress indicator
			Write-Host "Disabling the use of the latest installed .NET runtime for all apps -" -NoNewline
			LogInfo "Disabling the use of the latest installed .NET runtime for all apps"
			Remove-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\.NETFramework -Name OnlyUseLatestCLR -Force -ErrorAction Ignore | Out-Null
			Remove-ItemProperty -Path HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework -Name OnlyUseLatestCLR -Force -ErrorAction SilentlyContinue | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	How do you want to open this file prompt in Windows

	.PARAMETER Enable
	Show How do you want to open this file prompt

	.PARAMETER Disable
	Do not show How do you want to open this file prompt

	.EXAMPLE
	NewAppPrompt -Enable

	.EXAMPLE
	NewAppPrompt -Disable

	.NOTES
	Current user
#>
function NewAppPrompt
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
			Write-ConsoleStatus -Action "Enabling 'How do you want to open this file?' prompt"
			LogInfo "Enabling 'How do you want to open this file?' prompt"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoNewAppAlert" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the 'How do you want to open this file?' prompt: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling 'How do you want to open this file?' prompt"
			LogInfo "Disabling 'How do you want to open this file?' prompt"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoNewAppAlert" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the 'How do you want to open this file?' prompt: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Num Lock at startup

	.PARAMETER Enable
	Enable Num Lock at startup

	.PARAMETER Disable
	Disable Num Lock at startup (default value)

	.EXAMPLE
	NumLock -Enable

	.EXAMPLE
	NumLock -Disable

	.NOTES
	Current user
#>
function NumLock
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
			Write-ConsoleStatus -Action "Enabling Num Lock at startup"
			LogInfo "Enabling Num Lock at startup"
			New-ItemProperty -Path "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" -Name InitialKeyboardIndicators -PropertyType String -Value 2147483650 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Num Lock at startup"
			LogInfo "Disabling Num Lock at startup"
			New-ItemProperty -Path "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard" -Name InitialKeyboardIndicators -PropertyType String -Value 2147483648 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Desktop shortcut creation upon Microsoft Edge update

	.PARAMETER Channels
	List Microsoft Edge channels to prevent desktop shortcut creation upon its update

	.PARAMETER Disable
	Do not prevent desktop shortcut creation upon Microsoft Edge update (default value)

	.EXAMPLE
	PreventEdgeShortcutCreation -Channels Stable, Beta, Dev, Canary

	.EXAMPLE
	PreventEdgeShortcutCreation -Disable

	.NOTES
	Machine-wide
#>
function PreventEdgeShortcutCreation
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $false,
			ParameterSetName = "Channels"
		)]
		[ValidateSet("Stable", "Beta", "Dev", "Canary")]
		[string[]]
		$Channels,

		[Parameter(
			Mandatory = $false,
			ParameterSetName = "Disable"
		)]
		[switch]
		$Disable
	)

	if (-not (Get-Package -Name "Microsoft Edge" -ProviderName Programs -ErrorAction Ignore -WarningAction SilentlyContinue))
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
		return
	}

	if (-not (Test-Path -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate))
	{
		New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Force | Out-Null
	}

	foreach ($Channel in $Channels)
	{
		switch ($Channel)
		{
			Stable
			{
				Write-ConsoleStatus -Action "Preventing desktop shortcut creation for Microsoft Edge Stable Channel"
				LogInfo "Preventing desktop shortcut creation for Microsoft Edge Stable Channel"
				if (Get-Package -Name "Microsoft Edge" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
				{
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -PropertyType DWord -Value 0 -Force | Out-Null
					Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Type DWORD -Value 3 | Out-Null
					Write-ConsoleStatus -Status success
				}
			}
			Beta
			{
				if (Get-Package -Name "Microsoft Edge Beta" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
				{
					Write-ConsoleStatus -Action "Preventing desktop shortcut creation for Microsoft Edge Beta Channel"
					LogInfo "Preventing desktop shortcut creation for Microsoft Edge Beta Channel"
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}" -PropertyType DWord -Value 0 -Force | Out-Null
					Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}" -Type DWORD -Value 3 | Out-Null
					Write-ConsoleStatus -Status success
				}
			}
			Dev
			{
				if (Get-Package -Name "Microsoft Edge Dev" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
				{
					Write-ConsoleStatus -Action "Preventing desktop shortcut creation for Microsoft Edge Dev Channel"
					LogInfo "Preventing desktop shortcut creation for Microsoft Edge Dev Channel"
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}" -PropertyType DWord -Value 0 -Force | Out-Null
					Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}" -Type DWORD -Value 3 | Out-Null
					Write-ConsoleStatus -Status success
				}
			}
			Canary
			{
				if (Get-Package -Name "Microsoft Edge Canary" -ProviderName Programs -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
				{
					Write-ConsoleStatus -Action "Preventing desktop shortcut creation for Microsoft Edge Canary Channel"
					LogInfo "Preventing desktop shortcut creation for Microsoft Edge Canary Channel"
					New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}" -PropertyType DWord -Value 0 -Force | Out-Null
					Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}" -Type DWORD -Value 3 | Out-Null
					Write-ConsoleStatus -Status success
				}
			}
		}
	}

	if ($Disable)
	{
		$Names = @(
			"CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}",
			"CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}",
			"CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}",
			"CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}"
		)
		Write-ConsoleStatus -Action "Allowing desktop shortcut creation for Microsoft Edge upon update"
		LogInfo "Allowing desktop shortcut creation for Microsoft Edge upon update"
		Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate -Name $Names -Force -ErrorAction Ignore | Out-Null

		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Type CLEAR | Out-Null
		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}" -Type CLEAR | Out-Null
		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}" -Type CLEAR | Out-Null
		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\EdgeUpdate -Name "CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}" -Type CLEAR | Out-Null
		Write-ConsoleStatus -Status success
	}
}

<#
	.SYNOPSIS
	Quality of Service (QoS) packet scheduler configuration on all network interfaces

	.PARAMETER Enable
	Enable QoS packet scheduler on all installed network interfaces (default value)

	.PARAMETER Disable
	Disable QoS packet scheduler on all installed network interfaces

	.EXAMPLE
	QoS -Enable

	.EXAMPLE
	QoS -Disable

	.NOTES
	Current user
#>
function QoS
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
			Write-ConsoleStatus -Action "Enabling Quality of Service (QoS)"
			LogInfo "Enabling Quality of Service (QoS)"
			Enable-NetAdapterBinding -Name "*" -ComponentID "ms_pacer" | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Quality of Service (QoS)"
			LogInfo "Disabling Quality of Service (QoS)"
			Disable-NetAdapterBinding -Name "*" -ComponentID "ms_pacer" | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Back up the system registry to %SystemRoot%\System32\config\RegBack folder when PC restarts and create a RegIdleBackup in the Task Scheduler task to manage subsequent backups

	.PARAMETER Enable
	Back up the system registry to %SystemRoot%\System32\config\RegBack folder

	.PARAMETER Disable
	Do not back up the system registry to %SystemRoot%\System32\config\RegBack folder (default value)

	.EXAMPLE
	RegistryBackup -Enable

	.EXAMPLE
	RegistryBackup -Disable

	.NOTES
	Machine-wide
#>
function RegistryBackup
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
			Write-ConsoleStatus -Action "Enabling registry backup to RegBack folder 'C:\Windows\System32\config\RegBack'"
			LogInfo "Enabling registry backup to RegBack folder 'C:\Windows\System32\config\RegBack'"
			New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name EnablePeriodicBackup -Type DWord -Value 1 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling registry backup to RegBack folder 'C:\Windows\System32\config\RegBack'"
			LogInfo "Disabling registry backup to RegBack folder 'C:\Windows\System32\config\RegBack'"
			Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name EnablePeriodicBackup -Force -ErrorAction Ignore | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

function StickyShift
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
			Write-ConsoleStatus -Action "Disabling Sticky Shift"
			LogInfo "Disabling Sticky Shift"
			New-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -PropertyType String -Value 506 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Sticky Shift"
			LogInfo "Enabling Sticky Shift"
			New-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -PropertyType String -Value 510 -Force | Out-Null
			Write-ConsoleStatus -Status success
		}
	}
}

<#
	.SYNOPSIS
	Storage Sense

	.PARAMETER Enable
	Turn on Storage Sense

	.PARAMETER Disable
	Turn off Storage Sense

	.EXAMPLE
	StorageSense -Enable

	.EXAMPLE
	StorageSense -Disable

	.NOTES
	Current user
#>
function StorageSense
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

	# Remove all policies in order to make changes visible in UI only if it's possible
	Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense -Name AllowStorageSenseGlobal -Force -ErrorAction Ignore | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\StorageSense -Name AllowStorageSenseGlobal -Type CLEAR | Out-Null

	if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy))
	{
		New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -ItemType Directory -Force | Out-Null
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Storage Sense"
			LogInfo "Enabling Storage Sense"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01 -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 04 -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 2048 -PropertyType DWord -Value 30 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Storage Sense: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Storage Sense"
			LogInfo "Disabling Storage Sense"
			try
			{
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01 -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 04 -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 2048 -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Storage Sense: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Verbose startup and shutdown status messages

	.PARAMETER Enable
	Show detailed status messages during startup and shutdown

	.PARAMETER Disable
	Hide detailed status messages during startup and shutdown (default value)

	.EXAMPLE
	VerboseStatus -Enable

	.EXAMPLE
	VerboseStatus -Disable

	.NOTES
	Current user
#>
function VerboseStatus
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
			Write-ConsoleStatus -Action "Enabling verbose Shutdown/Startup status messages"
			LogInfo "Enabling verbose Shutdown/Startup status messages"
			try
			{
				If ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
					Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				} Else {
					Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -ErrorAction SilentlyContinue | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable verbose startup and shutdown status messages: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling verbose Shutdown/Startup status messages"
			LogInfo "Disabling verbose Shutdown/Startup status messages"
			try
			{
				If ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
					Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -ErrorAction SilentlyContinue | Out-Null
				} Else {
					Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable verbose startup and shutdown status messages: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Windows 260 character path limit

	.PARAMETER Disable
	Disable the Windows 260 character path limit

	.PARAMETER Enable
	Enable the Windows 260 character path limit (default value)

	.EXAMPLE
	Win32LongPathLimit -Disable

	.EXAMPLE
	Win32LongPathLimit -Enable

	.NOTES
	Machine-wide
#>
function Win32LongPathLimit
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
			Write-ConsoleStatus -Action "Disabling Windows 260 character path limit"
			LogInfo "Disabling Windows 260 character path limit"
			try
			{
				New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Windows 260 character path limit: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Windows 260 character path limit"
			LogInfo "Enabling Windows 260 character path limit"
			try
			{
				New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Windows 260 character path limit: $($_.Exception.Message)"
			}
		}
	}
}


Export-ModuleMember -Function '*'
