using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Windows Defender Application Guard configuration

	.PARAMETER Enable
	Enable Windows Defender Application Guard optional feature

	.PARAMETER Disable
	Disable Windows Defender Application Guard optional feature (default value)

	.EXAMPLE
	DefenderAppGuard -Enable

	.EXAMPLE
	DefenderAppGuard -Disable

	.NOTES
	Current User
	Applicable since:
	- Windows 10 1709 (Enterprise)
	- Windows 10 1803 (Pro)
	Not applicable to Windows Server.
	Not supported on VMs or VDI environments.
#>
function DefenderAppGuard
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
			Write-ConsoleStatus -Action "Enabling Windows Defender Application Guard"
			LogInfo "Enabling Windows Defender Application Guard"
			$feature = Get-WindowsOptionalFeature -Online -FeatureName "Windows-Defender-ApplicationGuard" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

			if (-not $feature) {
				Write-ConsoleStatus -Status warning
				LogWarning "WDAG feature is not available on this system. Skipping."
			}
			elseif ($feature.State -eq "Disabled") {
				try {
					$null = Enable-WindowsOptionalFeature -Online `
	        			-FeatureName "Windows-Defender-ApplicationGuard" `
	        			-NoRestart `
	        			-ErrorAction Stop `
	        			-WarningAction SilentlyContinue
					Write-ConsoleStatus -Status success
				}
				catch {
					Write-ConsoleStatus -Status failed
					LogError "Failed to enable Windows Defender Application Guard: $($_.Exception.Message)"
					Remove-HandledErrorRecord -ErrorRecord $_
				}
			}
			else {
				Write-ConsoleStatus -Status success
				LogInfo "WDAG feature is already enabled."
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Defender Application Guard"
			LogInfo "Disabling Windows Defender Application Guard"
			# Check if feature exists without throwing error
			$feature = Get-WindowsOptionalFeature -Online -FeatureName "Windows-Defender-ApplicationGuard" -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

			if (-not $feature) {
				Write-ConsoleStatus -Status warning
				LogWarning "WDAG feature is not available on this system. Skipping."
			}
			elseif ($feature.State -ne "Disabled") {
				try {
					$null = Disable-WindowsOptionalFeature -Online `
	        			-FeatureName "Windows-Defender-ApplicationGuard" `
	        			-NoRestart `
	        			-ErrorAction Stop `
	        			-WarningAction SilentlyContinue
					Write-ConsoleStatus -Status success
				}
				catch {
					Write-ConsoleStatus -Status failed
					LogError "Failed to disable Windows Defender Application Guard: $($_.Exception.Message)"
					Remove-HandledErrorRecord -ErrorRecord $_
				}
			}
			else {
				Write-ConsoleStatus -Status success
				LogInfo "WDAG feature is already disabled."
			}
		}
	}
}

<#
	.SYNOPSIS
	Configure additional Defender Exploit Guard protections.

	.DESCRIPTION
	Updates Defender signatures, sets early launch related values, enables a set
	of ASR rules, and applies system-wide exploit mitigations.

	.EXAMPLE
	Set-DefenderExploitGuardPolicy

	.NOTES
	Machine-wide

	.CAUTION
	Advanced. Can block legitimate applications, Office automation, admin
	tooling, scripts, or line-of-business workflows depending on how they
	interact with Defender ASR and system mitigations.
#>
function Set-DefenderExploitGuardPolicy
{
	Write-ConsoleStatus -Action "Configuring Defender Exploit Guard policies"
	LogInfo "Configuring Defender Exploit Guard policies"
	try
	{
		$mpCmdRunPath = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
		if (Test-Path $mpCmdRunPath)
		{
			& $mpCmdRunPath -SignatureUpdate | Out-Null
		}

		if (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Windows Defender"))
		{
			New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows Defender" -Force -ErrorAction Stop | Out-Null
		}
		Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows Defender" -Name "PassiveMode" -Value 2 -ErrorAction Stop | Out-Null

		if (!(Test-Path "HKLM:\SYSTEM\CurrentControlSet\Policies\EarlyLaunch"))
		{
			New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\EarlyLaunch" -Force -ErrorAction Stop | Out-Null
		}
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\EarlyLaunch" -Name "DriverLoadPolicy" -Value 3 -ErrorAction Stop | Out-Null

		$rules = @(
			'D1E49AAC-8F56-4280-B9BA-993A6D77B4F2',
			'D4F940AB-401B-4EFC-AADC-AD5F3C50688A',
			'75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84',
			'92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B',
			'3B576869-A4EC-4529-8536-B80A7769E899',
			'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550',
			'01443614-CD74-433A-B99E-2ECDC07BFC25',
			'C1DB55AB-C21A-4637-BB3F-A12568109D35',
			'9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2',
			'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4'
		)
		$actions = @('Enabled') * $rules.Count

		Set-MpPreference -AttackSurfaceReductionRules_Ids $rules -AttackSurfaceReductionRules_Actions $actions -ErrorAction Stop | Out-Null
		Set-ProcessMitigation -System -Enable DEP,EmulateAtlThunks,BottomUp,HighEntropy,SEHOP,SEHOPTelemetry,TerminateOnError -ErrorAction Stop | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to configure Defender Exploit Guard policies: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Core Isolation Memory Integrity (Hypervisor-Enforced Code Integrity)

	.PARAMETER Enable
	Enable Memory Integrity (HVCI)

	.PARAMETER Disable
	Disable Memory Integrity (HVCI)

	.EXAMPLE
	CIMemoryIntegrity -Enable

	.EXAMPLE
	CIMemoryIntegrity -Disable

	.NOTES
	Current User
	Applicable since Windows 10 version 1803.
	May cause compatibility issues with old drivers and antivirus software.
#>
function CIMemoryIntegrity
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
			Write-ConsoleStatus -Action "Enabling Core Isolation Memory Integrity (HVCI)"
			LogInfo "Enabling Core Isolation Memory Integrity (HVCI)"
			try
			{
				If (!(Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity")) {
					New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Type DWord -Value 1 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Core Isolation Memory Integrity: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Core Isolation Memory Integrity (HVCI)"
			LogInfo "Disabling Core Isolation Memory Integrity (HVCI)"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Core Isolation Memory Integrity: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Import the Microsoft Defender Exploit Protection policy.

	.DESCRIPTION
	Downloads the Microsoft demo Exploit Protection policy XML, imports it with
	Set-ProcessMitigation, and removes the temporary file.

	.EXAMPLE
	Import-ExploitProtectionPolicy

	.NOTES
	Machine-wide

	.CAUTION
	Advanced. Imports a downloaded mitigation policy that can change exploit
	protection behavior for applications across the system.
#>
function Import-ExploitProtectionPolicy
{
	Write-ConsoleStatus -Action "Importing Exploit Protection policy"
	LogInfo "Importing Exploit Protection policy"
	try
	{
		$policyPath = Join-Path $env:TEMP "ProcessMitigation.xml"
		Invoke-WebRequest -Uri "https://demo.wd.microsoft.com/Content/ProcessMitigation.xml" -OutFile $policyPath -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
		Set-ProcessMitigation -PolicyFilePath $policyPath -ErrorAction Stop | Out-Null
		Remove-Item -Path $policyPath -Force -ErrorAction SilentlyContinue | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to import Exploit Protection policy: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Local Security Authority protection

	.PARAMETER Enable
	Enable Local Security Authority protection to prevent code injection without UEFI lock

	.PARAMETER Disable
	Disable Local Security Authority protection

	.EXAMPLE
	LocalSecurityAuthority -Enable

	.EXAMPLE
	LocalSecurityAuthority -Disable

	.NOTES
	https://learn.microsoft.com/en-us/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection

	.NOTES
	Machine-wide
#>
function LocalSecurityAuthority
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
	Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "RunAsPPL" | Out-Null
	Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\System -Name RunAsPPL -Type CLEAR | Out-Null

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Local Security Authority protection to prevent code injection without UEFI lock"
			LogInfo "Enabling Local Security Authority protection to prevent code injection without UEFI lock"
			# Checking whether x86 virtualization is enabled in the firmware
			if ((Get-CimInstance -ClassName CIM_Processor).VirtualizationFirmwareEnabled)
			{
				try
				{
					New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name RunAsPPL -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
					New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name RunAsPPLBoot -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch
				{
					Write-ConsoleStatus -Status failed
					LogError "Failed to enable Local Security Authority protection: $($_.Exception.Message)"
				}
			}
			else
			{
				try
				{
					# Determining whether Hyper-V is enabled
					if ((Get-CimInstance -ClassName CIM_ComputerSystem).HypervisorPresent)
					{
						New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name RunAsPPL -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
						New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name RunAsPPLBoot -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
						Write-ConsoleStatus -Status success
					}
				}
				catch [System.Exception]
				{
					Write-ConsoleStatus -Status failed
					LogError $Localization.EnableHardwareVT
				}
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Local Security Authority protection"
			LogInfo "Disabling Local Security Authority protection"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" | Out-Null
				Remove-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPLBoot" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Local Security Authority protection: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enables or disables Data Execution Prevention (DEP) policy

	.PARAMETER Enable
	Sets DEP to OptIn (default for most apps) (default value)

	.PARAMETER Disable
	Sets DEP to OptOut (allows all apps without DEP)

	.EXAMPLE
	DEPOptOut -Enable

	.EXAMPLE
	DEPOptOut -Disable

	.NOTES
	Current user
#>
function DEPOptOut
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
			Write-ConsoleStatus -Action "Disabling Data Execution Prevention (DEP) policy to OptIn"
			LogInfo "Disabling Data Execution Prevention (DEP) policy to OptIn"
			try
			{
				# Setting Data Execution Prevention (DEP) policy to OptIn...
				bcdedit /set `{current`} nx OptIn 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "bcdedit returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set DEP policy to OptIn: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Data Execution Prevention (DEP) policy to OptOut"
			LogInfo "Disabling Data Execution Prevention (DEP) policy to OptOut"
			try
			{
				# Setting Data Execution Prevention (DEP) policy to OptOut...
				bcdedit /set `{current`} nx OptOut 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "bcdedit returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to set DEP policy to OptOut: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enables or disables automatic recovery mode during boot

	.PARAMETER Enable
	Enable automatic recovery mode on startup errors (default value)

	.PARAMETER Disable
	Disable automatic recovery mode on startup errors

	.EXAMPLE
	BootRecovery -Enable

	.EXAMPLE
	BootRecovery -Disable

	.NOTES
	Current user
#>
function BootRecovery
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
			Write-ConsoleStatus -Action "Enabling automatic recovery mode on startup errors"
			LogInfo "Enabling automatic recovery mode on startup errors"
			try
			{
				# This allows the boot process to automatically enter recovery mode when it detects startup errors (default behavior)
				bcdedit /deletevalue `{current`} BootStatusPolicy 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					$bootStatusPolicy = (bcdedit /enum `{current`} 2>$null | Out-String)
					if ($bootStatusPolicy -match "BootStatusPolicy")
					{
						throw "bcdedit returned exit code $LASTEXITCODE"
					}
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable automatic recovery mode during boot: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling automatic recovery mode on startup errors"
			LogInfo "Disabling automatic recovery mode on startup errors"
			try
			{
				bcdedit /set `{current`} BootStatusPolicy IgnoreAllFailures 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "bcdedit returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable automatic recovery mode during boot: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enables or disables the F8 boot menu on startup

	.PARAMETER Enable
	Enable the legacy F8 boot menu

	.PARAMETER Disable
	Disable the legacy F8 boot menu (default value)

	.EXAMPLE
	F8BootMenu -Enable

	.EXAMPLE
	F8BootMenu -Disable

	.NOTES
	Current user
#>
function F8BootMenu
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
			Write-ConsoleStatus -Action "Enabling legacy F8 boot menu"
			LogInfo "Enabling legacy F8 boot menu"
			try
			{
				bcdedit /set `{current`} BootMenuPolicy Legacy 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "bcdedit returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the legacy F8 boot menu: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling legacy F8 boot menu"
			LogInfo "Disabling legacy F8 boot menu"
			try
			{
				bcdedit /set `{current`} BootMenuPolicy Standard 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "bcdedit returned exit code $LASTEXITCODE" }
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the legacy F8 boot menu: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function '*'
