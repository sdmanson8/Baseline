<#
	.SYNOPSIS
	The "Process Creation" Event Viewer custom view

	.PARAMETER Enable
	Create the "Process Creation" custom view in the Event Viewer to log executed processes and their arguments

	.PARAMETER Disable
	Remove the "Process Creation" custom view in the Event Viewer (default value)

	.EXAMPLE
	EventViewerCustomView -Enable

	.EXAMPLE
	EventViewerCustomView -Disable

	.NOTES
	In order this feature to work events auditing and command line in process creation events will be enabled

	.NOTES
	Machine-wide
#>
function EventViewerCustomView
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
			Write-ConsoleStatus -Action "Creating the '$($Localization.EventViewerCustomViewName)' custom view in the Event Viewer to log executed processes and their arguments"
			LogInfo "Creating the '$($Localization.EventViewerCustomViewName)' custom view in the Event Viewer to log executed processes and their arguments"
			try
			{
				# Enable events auditing generated when a process is created (starts)
				auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "auditpol returned exit code $LASTEXITCODE" }

				# Include command line in process creation events
				New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit -Name ProcessCreationIncludeCmdLine_Enabled -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit -Name ProcessCreationIncludeCmdLine_Enabled -Type DWORD -Value 1 | Out-Null

				$XML = @"
<ViewerConfig>
	<QueryConfig>
		<QueryParams>
			<UserQuery />
		</QueryParams>
		<QueryNode>
			<Name>$($Localization.EventViewerCustomViewName)</Name>
			<Description>$($Localization.EventViewerCustomViewDescription)</Description>
			<QueryList>
				<Query Id="0" Path="Security">
					<Select Path="Security">*[System[(EventID=4688)]]</Select>
				</Query>
			</QueryList>
		</QueryNode>
	</QueryConfig>
</ViewerConfig>
"@

				if (-not (Test-Path -Path "$env:ProgramData\Microsoft\Event Viewer\Views"))
				{
					New-Item -Path "$env:ProgramData\Microsoft\Event Viewer\Views" -ItemType Directory -Force -ErrorAction Stop | Out-Null
				}

				# Save ProcessCreation.xml in the UTF-8 without BOM encoding
				Set-Content -Path "$env:ProgramData\Microsoft\Event Viewer\Views\ProcessCreation.xml" -Value $XML -Encoding Default -NoNewline -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to create the 'Process Creation' Event Viewer custom view: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Removing the '$($Localization.EventViewerCustomViewName)' custom view in the Event Viewer"
			LogInfo "Removing the '$($Localization.EventViewerCustomViewName)' custom view in the Event Viewer"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit -Name ProcessCreationIncludeCmdLine_Enabled -Type CLEAR | Out-Null
				Remove-Item -Path "$env:ProgramData\Microsoft\Event Viewer\Views\ProcessCreation.xml" -Force -ErrorAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to remove the 'Process Creation' Event Viewer custom view: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	Logging for all Windows PowerShell modules

	.PARAMETER Enable
	Enable logging for all Windows PowerShell modules

	.PARAMETER Disable
	Disable logging for all Windows PowerShell modules (default value)

	.EXAMPLE
	PowerShellModulesLogging -Enable

	.EXAMPLE
	PowerShellModulesLogging -Disable

	.NOTES
	Machine-wide
#>
function PowerShellModulesLogging
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
			Write-ConsoleStatus -Action "Enabling logging for all Windows PowerShell modules"
			LogInfo "Enabling logging for all Windows PowerShell modules"
			try
			{
				if (-not (Test-Path -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames))
				{
					New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging -Name EnableModuleLogging -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames -Name * -PropertyType String -Value * -Force -ErrorAction Stop | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging -Name EnableModuleLogging -Type DWORD -Value 1 | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames -Name * -Type SZ -Value * | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable PowerShell module logging: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling logging for all Windows PowerShell modules"
			LogInfo "Disabling logging for all Windows PowerShell modules"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" | Out-Null
				Remove-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames -Name * -Force -ErrorAction SilentlyContinue | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging -Name EnableModuleLogging -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable PowerShell module logging: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Logging for all PowerShell scripts input to the Windows PowerShell event log

	.PARAMETER Enable
	Enable logging for all PowerShell scripts input to the Windows PowerShell event log

	.PARAMETER Disable
	Disable logging for all PowerShell scripts input to the Windows PowerShell event log (default value)

	.EXAMPLE
	PowerShellScriptsLogging -Enable

	.EXAMPLE
	PowerShellScriptsLogging -Disable

	.NOTES
	Machine-wide
#>
function PowerShellScriptsLogging
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
			Write-ConsoleStatus -Action "Enabling logging for all PowerShell scripts input to the Windows PowerShell event log"
			LogInfo "Enabling logging for all PowerShell scripts input to the Windows PowerShell event log"
			try
			{
				if (-not (Test-Path -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging))
				{
					New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging -Name EnableScriptBlockLogging -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging -Name EnableScriptBlockLogging -Type DWORD -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable PowerShell script block logging: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling logging for all PowerShell scripts input to the Windows PowerShell event log"
			LogInfo "Disabling logging for all PowerShell scripts input to the Windows PowerShell event log"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" | Out-Null
				Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging -Name EnableScriptBlockLogging -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable PowerShell script block logging: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Detection for potentially unwanted applications

	.PARAMETER Enable
	Enable detection for potentially unwanted applications and block them

	.PARAMETER Disable
	Disable detection for potentially unwanted applications and block them (default value)

	.EXAMPLE
	PUAppsDetection -Enable

	.EXAMPLE
	PUAppsDetection -Disable

	.NOTES
	Current user
#>
function PUAppsDetection
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

	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling detection for potentially unwanted applications and blocking them"
			LogInfo "Enabling detection for potentially unwanted applications and blocking them"
			try
			{
				Set-MpPreference -PUAProtection Enabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable detection for potentially unwanted applications: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling detection for potentially unwanted applications and blocking them"
			LogInfo "Disabling detection for potentially unwanted applications and blocking them"
			try
			{
				Set-MpPreference -PUAProtection Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable detection for potentially unwanted applications: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	The Attachment Manager

	.PARAMETER Disable
	Microsoft Defender SmartScreen doesn't marks downloaded files from the Internet as unsafe

	.PARAMETER Enable
	Microsoft Defender SmartScreen marks downloaded files from the Internet as unsafe (default value)

	.EXAMPLE
	SaveZoneInformation -Disable

	.EXAMPLE
	SaveZoneInformation -Enable

	.NOTES
	Current user
#>
function SaveZoneInformation
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
	Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name "SaveZoneInformation" | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments -Name SaveZoneInformation -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling marking downloaded files from the Internet as unsafe"
			LogInfo "Disabling marking downloaded files from the Internet as unsafe"
			try
			{
				if (-not (Test-Path -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments))
				{
					New-Item -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments -Name SaveZoneInformation -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Attachments -Name SaveZoneInformation -Type DWORD -Value 1 | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable saving zone information on downloaded files: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling marking downloaded files from the Internet as unsafe"
			LogInfo "Enabling marking downloaded files from the Internet as unsafe"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments" -Name "SaveZoneInformation" | Out-Null
				Set-Policy -Scope User -Path Software\Microsoft\Windows\CurrentVersion\Policies\Attachments -Name SaveZoneInformation -Type CLEAR | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable saving zone information on downloaded files: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Sharing mapped drives between elevated and standard user sessions

	.PARAMETER Enable
	Enable sharing mapped drives between users

	.PARAMETER Disable
	Disable sharing mapped drives between users (default value)

	.EXAMPLE
	SharingMappedDrives -Enable

	.EXAMPLE
	SharingMappedDrives -Disable

	.NOTES
	Current user
#>
function SharingMappedDrives
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
			Write-ConsoleStatus -Action "Enabling sharing mapped drives between users"
			LogInfo "Enabling sharing mapped drives between users"
			try
			{
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLinkedConnections" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable sharing mapped drives between users: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling sharing mapped drives between users"
			LogInfo "Disabling sharing mapped drives between users"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLinkedConnections" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable sharing mapped drives between users: $($_.Exception.Message)"
			}
		}
	}
}


<#
	.SYNOPSIS
	Windows Sandbox

	.PARAMETER Disable
	Disable Windows Sandbox (default value)

	.PARAMETER Enable
	Enable Windows Sandbox

	.EXAMPLE
	WindowsSandbox -Disable

	.EXAMPLE
	WindowsSandbox -Enable

	.NOTES
	Current user
#>
function WindowsSandbox
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

	$FeatureName = "Containers-DisposableClientVM"

	# Get Windows edition from registry instead of WinAPI
	$Edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName

	if (($Edition -notmatch "Pro") -and ($Edition -notmatch "Enterprise") -and ($Edition -notmatch "Education"))
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))

		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Sandbox"
			LogInfo "Disabling Windows Sandbox"
			$Feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

			if (-not $Feature)
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Windows Sandbox feature is not available on this system. Skipping."
				return
			}

			if ($Feature.State -in @("Disabled", "DisablePending"))
			{
				Write-ConsoleStatus -Status success
				LogInfo "Windows Sandbox is already disabled."
				return
			}

			try
			{
				Disable-WindowsOptionalFeature -FeatureName $FeatureName -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Sandbox: $($_.Exception.Message)"
				Remove-HandledErrorRecord -ErrorRecord $_
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Windows Sandbox"
			LogInfo "Enabling Windows Sandbox"
			$Feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

			if (-not $Feature)
			{
				Write-ConsoleStatus -Status warning
				LogWarning "Windows Sandbox feature is not available on this system. Skipping."
				return
			}

			if ($Feature.State -in @("Enabled", "EnablePending"))
			{
				Write-ConsoleStatus -Status success
				LogInfo "Windows Sandbox is already enabled."
				return
			}

			# Checking whether x86 virtualization is enabled in the firmware
			if ((Get-CimInstance -ClassName CIM_Processor).VirtualizationFirmwareEnabled -or (Get-CimInstance -ClassName CIM_ComputerSystem).HypervisorPresent)
			{
				try
				{
					Enable-WindowsOptionalFeature -FeatureName $FeatureName -All -Online -NoRestart -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch
				{
					Write-ConsoleStatus -Status failed
					LogError "Failed to enable Windows Sandbox: $($_.Exception.Message)"
					Remove-HandledErrorRecord -ErrorRecord $_
				}
			}
			else
			{
				Write-ConsoleStatus -Status failed
				LogError $Localization.EnableHardwareVT
				LogError ($Localization.RestartFunction -f (Get-TweakSkipLabel $MyInvocation))
			}
		}
	}
}

<#
	.SYNOPSIS
	Windows Script Host

	.PARAMETER Disable
	Disable Windows Script Host

	.PARAMETER Enable
	Enable Windows Script Host (default value)

	.EXAMPLE
	WindowsScriptHost -Disable

	.EXAMPLE
	WindowsScriptHost -Enable

	.NOTES
	Blocks WSH from executing .js and .vbs files

	.NOTES
	Current user
#>
function WindowsScriptHost
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
			Write-ConsoleStatus -Action "Disabling Windows Script Host"
			LogInfo "Disabling Windows Script Host"
			# Checking whether any scheduled tasks were created before, because they rely on Windows Host running vbs files
			Get-ScheduledTask -TaskName SoftwareDistribution, Temp, "Windows Cleanup", "Windows Cleanup Notification" -ErrorAction SilentlyContinue | ForEach-Object -Process {
				# Skip if a scheduled task exists
				if ($_.State -eq "Ready")
				{
					LogInfo ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
					Write-ConsoleStatus -Status success
					break
				}
			}

			try
			{
				if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows Script Host\Settings"))
				{
					New-Item -Path "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Force -ErrorAction Stop | Out-Null
				}
				New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name Enabled -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Script Host: $($_.Exception.Message)"
			}
		}
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Windows Script Host"
			LogInfo "Enabling Windows Script Host"
			try
			{
				Remove-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name "Enabled" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows Script Host: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
