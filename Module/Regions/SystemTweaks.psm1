using module ..\Logging.psm1
using module ..\SharedHelpers.psm1

#region System Tweaks

<#
.SYNOPSIS
Enable the LanmanWorkstation guest-auth Group Policy setting if it is not already defined.

.EXAMPLE
LanmanWorkstationGuestAuthPolicy

.NOTES
Machine-wide
#>
function LanmanWorkstationGuestAuthPolicy
{
	Write-ConsoleStatus -Action "Enabling LanmanWorkstation guest auth policy"
	LogInfo "Enabling LanmanWorkstation guest auth policy"

	$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"
	$valueName = "AllowInsecureGuestAuth"

	try
	{
		$existingPolicy = Get-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue
		if ($null -ne $existingPolicy)
		{
			LogInfo "LanmanWorkstation guest-auth policy already exists with value $($existingPolicy.$valueName). Leaving unchanged."
			Write-ConsoleStatus -Status success
			return
		}

		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation -Name $valueName -Type DWord -Value 1 | Out-Null
		LogInfo "Enabled LanmanWorkstation guest-auth policy for SMB client access"
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to enable LanmanWorkstation guest auth policy: $($_.Exception.Message)"
	}
}

<#
.SYNOPSIS
Run the remaining legacy system/bootstrap optimizations.

.DESCRIPTION
Runs the old Performance Tuning system-only actions directly inside
Baseline by calling `Invoke-SystemOptimizations`.
The Advanced Startup shortcut is managed separately via
`AdvancedStartupShortcut -Enable/-Disable`.

.PARAMETER Modules
Optional subset of PerformanceTuning modules to execute.

.EXAMPLE
PerformanceTuning

.EXAMPLE
PerformanceTuning -Modules System

.NOTES
Current user
#>
function PerformanceTuning
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $false)]
		[ValidateSet('System')]
		[string[]]
		$Modules = @('System')
	)

	try
	{
		foreach ($Module in $Modules)
		{
			switch ($Module)
			{
				'System'
				{
					Invoke-SystemOptimizations
				}
			}
		}
	}
	catch
	{
		Write-ConsoleStatus -Action "Running Performance Tuning" -Status failed
		LogError "Failed to execute Performance Tuning: $($_.Exception.Message)"
	}
}

function Set-SystemTweaksRegistryValue
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[object]$Value,

		[Parameter(Mandatory = $true)]
		[ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
		[string]$Type
	)

	if (-not (Test-Path -Path $Path))
	{
		New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
	}

	if ($null -ne (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue))
	{
		Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
	}
	else
	{
		New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
	}
}

function Remove-SystemTweaksRegistryValue
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Name
	)

	if ($null -eq (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue))
	{
		return $false
	}

	Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
	return $true
}

function Test-Windows11SmbDuplicateSidIssue
{
	param
	(
		[int]$LookbackDays = 30
	)

	try
	{
		$startTime = (Get-Date).AddDays(-1 * [math]::Abs($LookbackDays))
		$events = Get-WinEvent -FilterHashtable @{
			LogName   = "System"
			Id        = 6167
			StartTime = $startTime
		} -ErrorAction Stop | Where-Object {$_.Message -like "*partial mismatch in the machine ID*"}

		return (@($events).Count -gt 0)
	}
	catch
	{
		Remove-HandledErrorRecord -ErrorRecord $_
		LogInfo "Unable to query LSASS Event ID 6167: $($_.Exception.Message)"
		return $false
	}
}

<#
.SYNOPSIS
Repair the common Windows 11 SMB client/share issue introduced after updates.

.EXAMPLE
Repair-Windows11SMBUpdateIssue

.NOTES
Current user
#>
function Repair-Windows11SMBUpdateIssue
{
	Write-ConsoleStatus -Action "Repairing Windows 11 SMB post-update issue"

	$osInfo = Get-OSInfo
	if (-not $osInfo.IsWindows11)
	{
		LogInfo "Windows 11 SMB post-update repair not applicable on this OS"
		Write-ConsoleStatus -Status success
		return
	}

	LogInfo "Repairing Windows 11 SMB post-update issue"

	$hadIssue = $false
	$lanmanWorkstationPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation"
	$lanmanWorkstationParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
	$lanmanServerParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
	$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
	$policiesSystemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
	$mrxSmb20Path = "HKLM:\SYSTEM\CurrentControlSet\Services\MRxSmb20"
	$bowserPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Bowser"
	$guestPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"
	$guestPolicy = $null
	$guestParameter = $null
	$guestAuthEnabled = $false
	$partOfDomain = $false

	try
	{
		$partOfDomain = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
	}
	catch
	{
		LogInfo "Unable to determine domain membership: $($_.Exception.Message)"
	}

	try
	{
		if (Remove-SystemTweaksRegistryValue -Path $lanmanServerParametersPath -Name "SMB1")
		{
			LogInfo "Removed stale LanmanServer SMB1 override"
		}
		else
		{
			LogInfo "No stale LanmanServer SMB1 override found"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to clear LanmanServer SMB1 override: $($_.Exception.Message)"
	}

	try
	{
		$existingDependencies = @((Get-ItemProperty -Path $lanmanWorkstationPath -Name "DependOnService" -ErrorAction SilentlyContinue).DependOnService) |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
		$desiredDependencies = @()
		if (Test-Path -Path $bowserPath)
		{
			$desiredDependencies += "Bowser"
		}
		$desiredDependencies += "MRxSmb20", "NSI"

		$normalizedExisting = @($existingDependencies | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() })
		$normalizedDesired = @($desiredDependencies | ForEach-Object { $_.ToString().Trim().ToLowerInvariant() })

		$repairDependencies = $false
		if ($normalizedExisting.Count -ne $normalizedDesired.Count)
		{
			$repairDependencies = $true
		}
		elseif ($normalizedExisting -contains "mrxsmb10")
		{
			$repairDependencies = $true
		}
		elseif (Compare-Object -ReferenceObject $normalizedExisting -DifferenceObject $normalizedDesired)
		{
			$repairDependencies = $true
		}

		if ($repairDependencies)
		{
			Set-SystemTweaksRegistryValue -Path $lanmanWorkstationPath -Name "DependOnService" -Value $desiredDependencies -Type MultiString
			LogInfo "Repaired LanmanWorkstation dependencies to: $($desiredDependencies -join ', ')"
		}
		else
		{
			LogInfo "LanmanWorkstation dependencies already healthy"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to repair LanmanWorkstation dependencies: $($_.Exception.Message)"
	}

	try
	{
		$mrxSmb20Start = (Get-ItemProperty -Path $mrxSmb20Path -Name "Start" -ErrorAction SilentlyContinue).Start
		if ($null -eq $mrxSmb20Start -or [int]$mrxSmb20Start -ne 2)
		{
			Set-SystemTweaksRegistryValue -Path $mrxSmb20Path -Name "Start" -Value 2 -Type DWord
			LogInfo "Set MRxSmb20 redirector start type to Automatic"
		}
		else
		{
			LogInfo "MRxSmb20 redirector start type already correct"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to repair MRxSmb20 redirector start type: $($_.Exception.Message)"
	}

	try
	{
		if (Test-Path -Path $bowserPath)
		{
			$bowserStart = (Get-ItemProperty -Path $bowserPath -Name "Start" -ErrorAction SilentlyContinue).Start
			if ($null -eq $bowserStart -or [int]$bowserStart -ne 3)
			{
				Set-SystemTweaksRegistryValue -Path $bowserPath -Name "Start" -Value 3 -Type DWord
				LogInfo "Set Bowser start type to Manual"
			}
			else
			{
				LogInfo "Bowser start type already correct"
			}
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to repair Bowser start type: $($_.Exception.Message)"
	}

	try
	{
		$guestPolicy = Get-ItemProperty -Path $guestPolicyPath -Name "AllowInsecureGuestAuth" -ErrorAction SilentlyContinue
		$guestParameter = Get-ItemProperty -Path $lanmanWorkstationParametersPath -Name "AllowInsecureGuestAuth" -ErrorAction SilentlyContinue
		$guestAuthEnabled = (($null -ne $guestPolicy) -and ([int]$guestPolicy.AllowInsecureGuestAuth -eq 1)) -or `
			(($null -ne $guestParameter) -and ([int]$guestParameter.AllowInsecureGuestAuth -eq 1))

		if ($null -ne $guestPolicy)
		{
			LogInfo "Retained existing guest-auth policy value: $($guestPolicy.AllowInsecureGuestAuth)"
		}
		elseif ($null -ne $guestParameter)
		{
			LogInfo "Retained existing guest-auth parameter value: $($guestParameter.AllowInsecureGuestAuth)"
		}
		else
		{
			LogInfo "Guest-auth behavior remains managed externally or by existing policy"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to read existing SMB guest-auth configuration: $($_.Exception.Message)"
	}

	try
	{
		if (-not $partOfDomain)
		{
			$forceGuest = (Get-ItemProperty -Path $lsaPath -Name "forceguest" -ErrorAction SilentlyContinue).forceguest
			if ($null -eq $forceGuest -or [int]$forceGuest -ne 0)
			{
				Set-SystemTweaksRegistryValue -Path $lsaPath -Name "forceguest" -Value 0 -Type DWord
				LogInfo "Set local account sharing model to Classic"
			}
			else
			{
				LogInfo "Local account sharing model already set to Classic"
			}

			$latfp = (Get-ItemProperty -Path $policiesSystemPath -Name "LocalAccountTokenFilterPolicy" -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
			if ($null -eq $latfp -or [int]$latfp -ne 1)
			{
				Set-SystemTweaksRegistryValue -Path $policiesSystemPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
				LogInfo "Enabled LocalAccountTokenFilterPolicy for workgroup SMB administration"
			}
			else
			{
				LogInfo "LocalAccountTokenFilterPolicy already enabled"
			}
		}
		else
		{
			LogInfo "Skipped workgroup-only local account compatibility changes because this device is domain joined"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to apply local account SMB compatibility settings: $($_.Exception.Message)"
	}

	foreach ($signingSetting in @(
		@{ Path = $lanmanWorkstationParametersPath; Name = "RequireSecuritySignature"; Value = 0; Description = "Disabled required SMB client signing" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "EnableSecuritySignature";  Value = 1; Description = "Kept SMB client signing available" },
		@{ Path = $lanmanServerParametersPath;      Name = "RequireSecuritySignature"; Value = 0; Description = "Disabled required SMB server signing" },
		@{ Path = $lanmanServerParametersPath;      Name = "EnableSecuritySignature";  Value = 1; Description = "Kept SMB server signing available" }
	))
	{
		try
		{
			$existingValue = (Get-ItemProperty -Path $signingSetting.Path -Name $signingSetting.Name -ErrorAction SilentlyContinue).$($signingSetting.Name)
			if ($null -eq $existingValue -or [int]$existingValue -ne [int]$signingSetting.Value)
			{
				Set-SystemTweaksRegistryValue -Path $signingSetting.Path -Name $signingSetting.Name -Value $signingSetting.Value -Type DWord
				LogInfo $signingSetting.Description
			}
			else
			{
				LogInfo "$($signingSetting.Description) already configured"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to update $($signingSetting.Name): $($_.Exception.Message)"
		}
	}

	try
	{
		Set-SmbClientConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction Stop | Out-Null
		LogInfo "Applied SMB client signing compatibility settings"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to apply SMB client signing compatibility settings: $($_.Exception.Message)"
	}

	try
	{
		Set-SmbServerConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction Stop | Out-Null
		LogInfo "Applied SMB server signing compatibility settings"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to apply SMB server signing compatibility settings: $($_.Exception.Message)"
	}

	if ($guestAuthEnabled -or -not $partOfDomain)
	{
		try
		{
			Enable-SMBGuestCompatibility -SuppressConsoleStatus
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to enable SMB guest compatibility: $($_.Exception.Message)"
		}
	}

	if (Test-Windows11SmbDuplicateSidIssue)
	{
		$hadIssue = $true
		LogWarning 'Detected LSASS Event ID 6167 ("partial mismatch in the machine ID"). Microsoft documents this as the duplicate-SID SMB/Kerberos/NTLM authentication issue in KB5070568.'
		LogWarning "A permanent fix for that issue requires rebuilding affected devices with unique SIDs, or Microsoft Support's special Group Policy workaround. Registry and service repairs alone will not permanently resolve it."
	}
	else
	{
		LogInfo "No LSASS Event ID 6167 evidence found for the duplicate-SID SMB authentication issue"
	}

	if ($hadIssue)
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
Enable guest/no-prompt SMB compatibility on non-domain machines.

.EXAMPLE
Enable-SMBGuestCompatibility

.NOTES
Current user
#>
function Enable-SMBGuestCompatibility
{
	[CmdletBinding()]
	param
	(
		[switch]
		$SuppressConsoleStatus
	)

	if (-not $SuppressConsoleStatus)
	{
		Write-ConsoleStatus -Action "Enabling SMB guest compatibility"
	}
	LogInfo "Enabling SMB guest compatibility"

	$hadIssue = $false
	$partOfDomain = $false
	$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
	$policiesSystemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
	$lanmanWorkstationParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
	$guestPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"

	try
	{
		$partOfDomain = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
	}
	catch
	{
		LogInfo "Unable to determine domain membership for SMB guest compatibility: $($_.Exception.Message)"
	}

	if ($partOfDomain)
	{
		LogInfo "Skipped SMB guest compatibility because this device is domain joined"
		if (-not $SuppressConsoleStatus)
		{
			Write-ConsoleStatus -Status success
		}
		return
	}

	foreach ($guestSetting in @(
		@{ Path = $guestPolicyPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled guest-auth policy for SMB client access" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled guest-auth parameter for SMB client access" },
		@{ Path = $lsaPath; Name = "forceguest"; Value = 1; Type = "DWord"; Description = "Set local sharing model to Guest only" }
	))
	{
		try
		{
			$existingValue = (Get-ItemProperty -Path $guestSetting.Path -Name $guestSetting.Name -ErrorAction SilentlyContinue).$($guestSetting.Name)
			if ($null -eq $existingValue -or [int]$existingValue -ne [int]$guestSetting.Value)
			{
				Set-SystemTweaksRegistryValue -Path $guestSetting.Path -Name $guestSetting.Name `
					-Value $guestSetting.Value -Type $guestSetting.Type
				LogInfo $guestSetting.Description
			}
			else
			{
				LogInfo "$($guestSetting.Description) already configured"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to apply $($guestSetting.Name): $($_.Exception.Message)"
		}
	}

	try
	{
		$latfp = (Get-ItemProperty -Path $policiesSystemPath -Name "LocalAccountTokenFilterPolicy" -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
		if ($null -ne $latfp -and [int]$latfp -ne 0)
		{
			Set-SystemTweaksRegistryValue -Path $policiesSystemPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord
			LogInfo "Disabled LocalAccountTokenFilterPolicy to align with guest-only sharing"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to align LocalAccountTokenFilterPolicy with guest-only sharing: $($_.Exception.Message)"
	}

	try
	{
		Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction Stop | Out-Null
		LogInfo "Enabled SMB client guest logons"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable SMB client guest logons: $($_.Exception.Message)"
	}

	if ($hadIssue)
	{
		if (-not $SuppressConsoleStatus)
		{
			Write-ConsoleStatus -Status warning
		}
	}
	else
	{
		if (-not $SuppressConsoleStatus)
		{
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Preserve SMB file sharing, printer sharing, and Windows credential access.

.EXAMPLE
Set-SMBSharingCompatibility

.NOTES
Current user
#>
function Set-SMBSharingCompatibility
{
	Write-ConsoleStatus -Action "Preserving SMB and printer sharing compatibility"
	LogInfo "Preserving SMB and printer sharing compatibility"

	$hadIssue = $false

	foreach ($serviceName in @("LanmanServer", "LanmanWorkstation"))
	{
		try
		{
			$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

			if ($service)
			{
				Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
				Start-Service -Name $serviceName -ErrorAction SilentlyContinue
			}
			else
			{
				$hadIssue = $true
				LogWarning "Service $serviceName not found"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to preserve $serviceName compatibility: $($_.Exception.Message)"
		}
	}

	try
	{
		$smbConfiguration = Get-SmbServerConfiguration -ErrorAction Stop
		if (-not $smbConfiguration.EnableSMB2Protocol)
		{
			Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop | Out-Null
		}
		LogInfo "Ensured SMB2 server protocol remains enabled"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to ensure SMB2 server protocol: $($_.Exception.Message)"
	}

	foreach ($bindingComponent in @("ms_server", "ms_msclient"))
	{
		try
		{
			Enable-NetAdapterBinding -Name "*" -ComponentID $bindingComponent -ErrorAction Stop | Out-Null
			LogInfo "Enabled network adapter binding $bindingComponent"
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to enable network adapter binding $bindingComponent : $($_.Exception.Message)"
		}
	}

	try
	{
		$firewallRules = @(
			"@FirewallAPI.dll,-32752",
			"@FirewallAPI.dll,-28502"
		)

		$firewallProfiles = @(
			Get-NetConnectionProfile -ErrorAction SilentlyContinue |
				Select-Object -ExpandProperty NetworkCategory -Unique |
				ForEach-Object {
					switch ($_) {
						"Private" { "Private" }
						"DomainAuthenticated" { "Domain" }
						"Public" { "Public" }
					}
				}
		) | Where-Object { $_ } | Select-Object -Unique

		if (-not $firewallProfiles)
		{
			$firewallProfiles = @("Private", "Domain")
		}

		Set-NetFirewallRule -Group $firewallRules -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null
		Get-NetFirewallRule -Name FPS-SMB-In-TCP -ErrorAction SilentlyContinue |
			Set-NetFirewallRule -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null

		LogInfo "Enabled file and printer sharing firewall rules for profiles: $($firewallProfiles -join ', ')"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable file and printer sharing firewall rules: $($_.Exception.Message)"
	}

	try
	{
		$guestAuthPolicy = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
			-Name "AllowInsecureGuestAuth" -ErrorAction SilentlyContinue

		if ($null -ne $guestAuthPolicy)
		{
			LogInfo "Retained existing AllowInsecureGuestAuth value: $($guestAuthPolicy.AllowInsecureGuestAuth)"
		}
		else
		{
			LogInfo "AllowInsecureGuestAuth is managed externally or not set locally"
		}
	}
	catch
	{
		LogWarning "Failed to read AllowInsecureGuestAuth state: $($_.Exception.Message)"
	}

	if ($hadIssue)
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
Repair shared/network printer connection errors.

.DESCRIPTION
Applies common host-side fixes for shared and network printer failures, including RPC, SMB, Point and Print, spooler, TCP, and network discovery settings. Use on a print server or an affected client machine. Add -ClientMode to run the optional client-side cleanup path. A restart is required for the changes to fully apply.

.PARAMETER ClientMode
Run the optional client-side cleanup path in addition to the host/common printer repair steps.

.PARAMETER SkipSpoolerSpool
Skip deleting stale files from the print spool folder.

.EXAMPLE
Repair-SharedPrinterConnectionErrors

.EXAMPLE
Repair-SharedPrinterConnectionErrors -ClientMode

.EXAMPLE
Repair-SharedPrinterConnectionErrors -SkipSpoolerSpool

.NOTES
Machine-wide
Requires an elevated PowerShell session.
Medium risk.
Restart required.
#>
function Repair-SharedPrinterConnectionErrors
{
	[CmdletBinding()]
	param
	(
		[switch]
		$ClientMode,

		[switch]
		$SkipSpoolerSpool
	)

	Write-ConsoleStatus -Action "Repairing shared printer connection errors"
	LogInfo "Repairing shared printer connection errors"

	$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
	if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
	{
		LogError "Repair-SharedPrinterConnectionErrors requires an elevated PowerShell session."
		Write-ConsoleStatus -Status failed
		return
	}

	$osInfo = Get-OSInfo
	$hadIssue = $false
	$computerName = $env:COMPUTERNAME
	$partOfDomain = $false
	$rpcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC"
	$pointAndPrintPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
	$printersPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers"
	$printControlPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print"
	$lsaPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
	$lanmanWorkstationParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
	$lanmanWorkstationPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"
	$lanmanServerParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
	$dnsClientPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
	$tcpipParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
	$afdParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
	$sessionManagerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"

	LogInfo ("OS: {0} (build {1})" -f $osInfo.OSName, $osInfo.CurrentBuild)
	LogInfo ("Mode: {0}" -f $(if ($ClientMode) { "HOST + CLIENT" } else { "HOST ONLY (use -ClientMode for client cleanup)" }))
	LogInfo ("Host: {0}" -f $computerName)

	if (-not [string]::IsNullOrWhiteSpace($computerName) -and $computerName.Length -gt 15)
	{
		LogWarning "Computer name exceeds 15 characters. This can contribute to printer and network issues."
	}

	try
	{
		$partOfDomain = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
	}
	catch
	{
		LogInfo "Unable to determine domain membership: $($_.Exception.Message)"
	}

	LogInfo "Applying RPC, SMB, Point and Print, and printer pruning registry settings"
	foreach ($registrySetting in @(
		@{ Path = $rpcPath; Name = "RpcUseNamedPipeProtocol"; Value = 1; Type = "DWord"; Description = "Enabled RPC named-pipe protocol for printer connections" },
		@{ Path = $rpcPath; Name = "RpcProtocols"; Value = 7; Type = "DWord"; Description = "Enabled RPC protocol bitmask 7 for printer connections" },
		@{ Path = $rpcPath; Name = "RpcListenerProtocols"; Value = 7; Type = "DWord"; Description = "Enabled RPC listener protocol bitmask 7 for printer connections" },
		@{ Path = $printControlPath; Name = "RpcAuthnLevelPrivacyEnabled"; Value = 0; Type = "DWord"; Description = "Relaxed RPC print authentication privacy" },
		@{ Path = $lsaPath; Name = "LmCompatibilityLevel"; Value = 1; Type = "DWord"; Description = "Set LAN Manager authentication level to 1" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled insecure guest auth for LanmanWorkstation" },
		@{ Path = $lanmanWorkstationParametersPath; Name = "AllowsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled compatibility guest auth flag for LanmanWorkstation" },
		@{ Path = $lanmanWorkstationPolicyPath; Name = "AllowInsecureGuestAuth"; Value = 1; Type = "DWord"; Description = "Enabled insecure guest auth policy for LanmanWorkstation" },
		@{ Path = $lanmanServerParametersPath; Name = "SMB2"; Value = 1; Type = "DWord"; Description = "Enabled SMB2 server registry flag" },
		@{ Path = $lanmanServerParametersPath; Name = "AutoShareWks"; Value = 1; Type = "DWord"; Description = "Enabled workstation admin shares" },
		@{ Path = $dnsClientPolicyPath; Name = "EnableMulticast"; Value = 1; Type = "DWord"; Description = "Enabled LLMNR multicast name resolution" },
		@{ Path = $printersPolicyPath; Name = "PruningInterval"; Value = 0xFFFFFFFF; Type = "DWord"; Description = "Disabled printer pruning" },
		@{ Path = $pointAndPrintPath; Name = "Restricted"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print restrictions" },
		@{ Path = $pointAndPrintPath; Name = "TrustedServers"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print trusted-server restrictions" },
		@{ Path = $pointAndPrintPath; Name = "InForest"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print forest restrictions" },
		@{ Path = $pointAndPrintPath; Name = "NoWarningNoElevationOnInstall"; Value = 1; Type = "DWord"; Description = "Allowed printer installs without warning or elevation prompts" },
		@{ Path = $pointAndPrintPath; Name = "UpdatePromptSettings"; Value = 0; Type = "DWord"; Description = "Disabled Point and Print update prompts" },
		@{ Path = $pointAndPrintPath; Name = "RestrictDriverInstallationToAdministrators"; Value = 0; Type = "DWord"; Description = "Allowed printer drivers to install without admin-only restrictions" }
	))
	{
		try
		{
			Set-SystemTweaksRegistryValue -Path $registrySetting.Path -Name $registrySetting.Name -Value $registrySetting.Value -Type $registrySetting.Type
			LogInfo $registrySetting.Description
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to set $($registrySetting.Name) at $($registrySetting.Path): $($_.Exception.Message)"
		}
	}

	try
	{
		if (Get-Command Set-SmbServerConfiguration -ErrorAction SilentlyContinue)
		{
			Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction Stop | Out-Null
			LogInfo "SMB2 enabled via Set-SmbServerConfiguration"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable SMB2 via Set-SmbServerConfiguration: $($_.Exception.Message)"
	}

	try
	{
		if (Get-Command Set-SmbClientConfiguration -ErrorAction SilentlyContinue)
		{
			Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -RequireSecuritySignature $false -EnableSecuritySignature $true -Force -ErrorAction Stop | Out-Null
			LogInfo "Enabled SMB client guest logons"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable SMB client guest logons: $($_.Exception.Message)"
	}

	try
	{
		if ((Get-Command Get-NetConnectionProfile -ErrorAction SilentlyContinue) -and (Get-Command Set-NetConnectionProfile -ErrorAction SilentlyContinue))
		{
			Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
				$profileAlias = $_.InterfaceAlias
				$profileCategory = $_.NetworkCategory
				LogInfo "Adapter: '$profileAlias' -> $profileCategory"

				if ($profileCategory -eq "Public")
				{
					Set-NetConnectionProfile -InterfaceAlias $profileAlias -NetworkCategory Private -ErrorAction Stop
					LogInfo "Changed '$profileAlias' Public -> Private"
				}
				else
				{
					LogInfo "'$profileAlias' already $profileCategory"
				}
			}
		}
		else
		{
			LogInfo "Get-NetConnectionProfile/Set-NetConnectionProfile not available on this system"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not check or update network profile: $($_.Exception.Message)"
	}

	try
	{
		if ((Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) -and (Get-Command Set-NetFirewallRule -ErrorAction SilentlyContinue))
		{
			$firewallRules = @(
				"@FirewallAPI.dll,-32752",
				"@FirewallAPI.dll,-28502"
			)

			$firewallProfiles = @(
				Get-NetConnectionProfile -ErrorAction SilentlyContinue |
					Select-Object -ExpandProperty NetworkCategory -Unique |
					ForEach-Object {
						switch ($_)
						{
							"Private" { "Private" }
							"DomainAuthenticated" { "Domain" }
							"Public" { "Public" }
						}
					}
			) | Where-Object { $_ } | Select-Object -Unique

			if (-not $firewallProfiles)
			{
				$firewallProfiles = @("Private", "Domain")
			}

			Set-NetFirewallRule -Group $firewallRules -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null
			Get-NetFirewallRule -Name FPS-SMB-In-TCP -ErrorAction SilentlyContinue |
				Set-NetFirewallRule -Profile $firewallProfiles -Enabled True -ErrorAction Stop | Out-Null

			LogInfo "Enabled file and printer sharing firewall rules for profiles: $($firewallProfiles -join ', ')"
		}
		else
		{
			& netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null
			& netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes | Out-Null
			LogInfo "File and printer sharing firewall rules enabled via netsh"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Failed to enable file and printer sharing firewall rules: $($_.Exception.Message)"
	}

	try
	{
		if (Get-Command Get-Service -ErrorAction SilentlyContinue)
		{
			$netServices = @(
				"fdPHost",
				"FDResPub",
				"FDResSvc",
				"lmhosts",
				"SSDPSRV",
				"upnphost",
				"LanmanServer",
				"LanmanWorkstation"
			)

			foreach ($serviceName in $netServices)
			{
				$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
				if ($service)
				{
					$wasRunning = ($service.Status -eq "Running")
					Set-Service -Name $serviceName -StartupType Automatic -ErrorAction Stop
					if (-not $wasRunning)
					{
						Start-Service -Name $serviceName -ErrorAction SilentlyContinue
					}
					LogInfo "Service $serviceName - Automatic + $(if ($wasRunning) { 'Already running' } else { 'Started' })"
				}
				else
				{
					LogInfo "Service $serviceName not present on this OS"
				}
			}
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not configure network discovery services: $($_.Exception.Message)"
	}

	LogInfo "Refreshing DNS and NetBIOS caches"
	try
	{
		& ipconfig /flushdns | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "ipconfig returned exit code $LASTEXITCODE while flushing DNS"
		}
		LogInfo "DNS cache flushed"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "ipconfig /flushdns failed: $($_.Exception.Message)"
	}

	try
	{
		& nbtstat -R | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "nbtstat returned exit code $LASTEXITCODE while purging the NetBIOS cache"
		}
		LogInfo "NetBIOS cache purged (nbtstat -R)"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "nbtstat -R failed: $($_.Exception.Message)"
	}

	try
	{
		& nbtstat -RR | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "nbtstat returned exit code $LASTEXITCODE while re-registering NetBIOS names"
		}
		LogInfo "NetBIOS names re-registered (nbtstat -RR)"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "nbtstat -RR failed: $($_.Exception.Message)"
	}

	try
	{
		$nicConfigs = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue
		if ($nicConfigs)
		{
			foreach ($nic in $nicConfigs)
			{
				$result = Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 1 } -ErrorAction SilentlyContinue
				if ($result.ReturnValue -eq 0)
				{
					LogInfo "NetBIOS enabled on adapter: $($nic.Description)"
				}
				else
				{
					$hadIssue = $true
					LogWarning "NetBIOS set returned $($result.ReturnValue) on: $($nic.Description)"
				}
			}
		}
		elseif (Get-Command wmic -ErrorAction SilentlyContinue)
		{
			& wmic nicconfig where "(IPEnabled=TRUE)" call SetTcpipNetbios 1 | Out-Null
			if ($LASTEXITCODE -ne 0)
			{
				throw "wmic returned exit code $LASTEXITCODE while enabling NetBIOS"
			}
			LogInfo "NetBIOS over TCP/IP enabled via wmic"
		}
		else
		{
			LogInfo "NetBIOS enable skipped because the WMI and wmic paths were unavailable"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "NetBIOS enable failed: $($_.Exception.Message)"
	}

	LogInfo "Stopping the Print Spooler to clear stale jobs"
	try
	{
		Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not stop the Print Spooler: $($_.Exception.Message)"
	}
	Start-Sleep -Seconds 2

	if (-not $SkipSpoolerSpool)
	{
		try
		{
			$spoolPath = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
			$files = Get-ChildItem -Path $spoolPath -File -ErrorAction SilentlyContinue
			if ($files)
			{
				$files | Remove-Item -Force -ErrorAction SilentlyContinue
				LogInfo "Removed $($files.Count) stale spool files from $spoolPath"
			}
			else
			{
				LogInfo "Spool folder already clean"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not purge spool folder: $($_.Exception.Message)"
		}
	}
	else
	{
		LogInfo "Skipped spool folder purge (-SkipSpoolerSpool)"
	}

	try
	{
		Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
		Start-Service -Name Spooler -ErrorAction SilentlyContinue
		Start-Sleep -Seconds 2
		$spoolerStatus = (Get-Service -Name Spooler -ErrorAction Stop).Status
		LogInfo "Print Spooler: $spoolerStatus"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not restart spooler: $($_.Exception.Message)"
	}

	LogInfo "PendingFileRenameOperations cleanup"
	try
	{
		$pfro = Get-ItemProperty -Path $sessionManagerPath -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
		if ($pfro -and $pfro.PendingFileRenameOperations)
		{
			$entries = @($pfro.PendingFileRenameOperations)
			$filtered = @($entries | Where-Object { $_ -notmatch "spool" -and $_ -notmatch "print" })
			if ($filtered.Count -lt $entries.Count)
			{
				if ($filtered.Count -gt 0)
				{
					Set-ItemProperty -Path $sessionManagerPath -Name "PendingFileRenameOperations" -Value $filtered -Force
				}
				else
				{
					Remove-ItemProperty -Path $sessionManagerPath -Name "PendingFileRenameOperations" -Force -ErrorAction SilentlyContinue
				}
				LogInfo "Removed $($entries.Count - $filtered.Count) spooler-related PendingFileRename entries"
			}
			else
			{
				LogInfo "No spooler-related PendingFileRenameOperations found"
			}
		}
		else
		{
			LogInfo "PendingFileRenameOperations key not present -- OK"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not inspect PendingFileRenameOperations: $($_.Exception.Message)"
	}

	LogInfo "Audit print processor registrations"
	try
	{
		$envBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments"
		$envs = Get-ChildItem -Path $envBase -ErrorAction SilentlyContinue
		foreach ($env in $envs)
		{
			$ppPath = Join-Path $env.PSPath "Print Processors"
			if (Test-Path $ppPath)
			{
				$procs = Get-ChildItem $ppPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne "winprint" }
				foreach ($proc in $procs)
				{
					LogWarning "Non-standard print processor found: '$($proc.PSChildName)' under $($env.PSChildName)"
				}
			}
		}
		LogInfo "Print processor audit complete"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not audit print processors: $($_.Exception.Message)"
	}

	LogInfo "Stopping the Print Spooler for print provider cleanup"
	try
	{
		Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not stop the Print Spooler for print provider cleanup: $($_.Exception.Message)"
	}
	Start-Sleep -Seconds 2

	try
	{
		$csrPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers\Client Side Rendering Print Provider"
		if (Test-Path $csrPath)
		{
			$csrBackup = Join-Path $env:TEMP "CSR_PrintProvider_backup.reg"
			$csrNative = $csrPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
			& reg export $csrNative $csrBackup /y | Out-Null
			if ($LASTEXITCODE -ne 0)
			{
				throw "reg export returned exit code $LASTEXITCODE while backing up the CSR Print Provider key"
			}
			LogInfo "Backed up CSR key to $csrBackup"
			Remove-Item -Path $csrPath -Recurse -Force -ErrorAction Stop
			LogInfo "Deleted stale CSR Print Provider key (will be recreated by spooler)"
		}
		else
		{
			LogInfo "CSR Print Provider key not present -- nothing to clean"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not remove CSR key: $($_.Exception.Message)"
	}

	try
	{
		Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
		Start-Service -Name Spooler -ErrorAction SilentlyContinue
		Start-Sleep -Seconds 2
		$spoolerStatus = (Get-Service -Name Spooler -ErrorAction Stop).Status
		LogInfo "Print Spooler: $spoolerStatus"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not restart spooler after CSR cleanup: $($_.Exception.Message)"
	}

	LogInfo "mscms.dll copy to spooler driver directories"
	$src = Join-Path $env:SystemRoot "System32\mscms.dll"
	if (Test-Path $src)
	{
		$driverPaths = @(
			"$env:SystemRoot\System32\spool\drivers\x64\3",
			"$env:SystemRoot\System32\spool\drivers\x64\4",
			"$env:SystemRoot\System32\spool\drivers\W32X86\3",
			"$env:SystemRoot\System32\spool\drivers\arm64\3",
			"$env:SystemRoot\System32\spool\drivers\arm64\4"
		)

		foreach ($dp in $driverPaths)
		{
			if (Test-Path $dp)
			{
				$dest = Join-Path $dp "mscms.dll"
				try
				{
					Copy-Item -Path $src -Destination $dest -Force -ErrorAction Stop
					LogInfo "Copied mscms.dll -> $dp"
				}
				catch
				{
					$hadIssue = $true
					LogWarning "Could not copy mscms.dll to $dp : $($_.Exception.Message)"
				}
			}
			else
			{
				LogInfo "$dp does not exist on this OS -- skip"
			}
		}
	}
	else
	{
		$hadIssue = $true
		LogWarning "mscms.dll not found at $src -- skipping"
	}

	LogInfo "HKCU\\..\\Windows registry ACL"
	try
	{
		$regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
			"Software\Microsoft\Windows NT\CurrentVersion\Windows",
			[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
			[System.Security.AccessControl.RegistryRights]::ChangePermissions
		)

		if ($null -eq $regKey)
		{
			throw "Could not open HKCU registry key for ACL modification."
		}

		$acl = $regKey.GetAccessControl()
		$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		$systemAcc = (New-Object System.Security.Principal.SecurityIdentifier(
			[System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null
		)).Translate([System.Security.Principal.NTAccount]).Value

		foreach ($id in @($currentUser, $systemAcc))
		{
			$rule = New-Object System.Security.AccessControl.RegistryAccessRule(
				$id,
				[System.Security.AccessControl.RegistryRights]::FullControl,
				[System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
				[System.Security.AccessControl.PropagationFlags]::None,
				[System.Security.AccessControl.AccessControlType]::Allow
			)
			$acl.SetAccessRule($rule)
			LogInfo "FullControl on HKCU\\..\\Windows -> $id"
		}

		$regKey.SetAccessControl($acl)
		$regKey.Close()
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not set HKCU registry ACL: $($_.Exception.Message)"
	}

	LogInfo "TCP connection tuning (ephemeral ports, TIME_WAIT, backlog)"
	foreach ($tcpSetting in @(
		@{ Path = $tcpipParametersPath; Name = "MaxUserPort"; Value = 0xfffe; Type = "DWord"; Description = "Increased ephemeral port range to 65534" },
		@{ Path = $tcpipParametersPath; Name = "TcpTimedWaitDelay"; Value = 30; Type = "DWord"; Description = "Reduced TIME_WAIT to 30 seconds" },
		@{ Path = $tcpipParametersPath; Name = "TcpNumConnections"; Value = 0xfffffe; Type = "DWord"; Description = "Raised max concurrent TCP connections" },
		@{ Path = $tcpipParametersPath; Name = "TcpMaxDataRetransmissions"; Value = 5; Type = "DWord"; Description = "Set TCP retransmission limit to 5" },
		@{ Path = $afdParametersPath; Name = "EnableDynamicBacklog"; Value = 1; Type = "DWord"; Description = "Enabled dynamic backlog for AFD" },
		@{ Path = $afdParametersPath; Name = "MinimumDynamicBacklog"; Value = 32; Type = "DWord"; Description = "Set minimum AFD dynamic backlog to 32" },
		@{ Path = $afdParametersPath; Name = "MaximumDynamicBacklog"; Value = 4096; Type = "DWord"; Description = "Set maximum AFD dynamic backlog to 4096" },
		@{ Path = $afdParametersPath; Name = "DynamicBacklogGrowthDelta"; Value = 16; Type = "DWord"; Description = "Set AFD dynamic backlog growth delta to 16" }
	))
	{
		try
		{
			Set-SystemTweaksRegistryValue -Path $tcpSetting.Path -Name $tcpSetting.Name -Value $tcpSetting.Value -Type $tcpSetting.Type
			LogInfo $tcpSetting.Description
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to update $($tcpSetting.Name): $($_.Exception.Message)"
		}
	}

	LogInfo "TCP stack performance (auto-tuning, RSS, chimney)"
	try
	{
		& netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "netsh returned exit code $LASTEXITCODE while setting autotuninglevel"
		}
		LogInfo "TCP autotuninglevel = normal"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp autotuninglevel failed: $($_.Exception.Message)"
	}

	try
	{
		& netsh int tcp set global rss=enabled 2>&1 | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "netsh returned exit code $LASTEXITCODE while setting RSS"
		}
		LogInfo "TCP RSS = enabled"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp rss failed: $($_.Exception.Message)"
	}

	try
	{
		& netsh int tcp set global chimney=enabled 2>&1 | Out-Null
		if ($LASTEXITCODE -ne 0)
		{
			throw "netsh returned exit code $LASTEXITCODE while setting chimney"
		}
		LogInfo "TCP chimney = enabled"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "netsh tcp chimney failed (not supported on all hardware): $($_.Exception.Message)"
	}

	LogInfo "Shared printer audit"
	try
	{
		if (Get-Command Get-Printer -ErrorAction SilentlyContinue)
		{
			$printers = Get-Printer -ErrorAction SilentlyContinue
			$shared = $printers | Where-Object { $_.Shared }
			if ($shared)
			{
				LogInfo "Shared printers on this host:"
				$shared | ForEach-Object {
					LogInfo "  -> '$($_.Name)' share='$($_.ShareName)'"
				}
			}
			else
			{
				LogInfo "No printers are currently shared on this host."
			}
		}
		else
		{
			LogInfo "Get-Printer not available on this system"
		}
	}
	catch
	{
		$hadIssue = $true
		LogWarning "Could not enumerate printers: $($_.Exception.Message)"
	}

	if ($ClientMode)
	{
		LogInfo "Applying optional client-side printer cleanup"

		try
		{
			switch ($osInfo.CurrentBuild)
			{
				19041 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19042 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19043 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				19044 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord }
				18363 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "1921033356" -Value 0 -Type DWord }
				17763 { Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "3598754956" -Value 0 -Type DWord }
				22000 { LogInfo "Win11 21H2 - ensure the relevant printer update is installed." }
				default
				{
					if ($osInfo.CurrentBuild -ge 22621)
					{
						LogInfo "Win11 22H2+ - RPC Named Pipes fix is usually the main resolution for 0x7C."
					}
					else
					{
						LogWarning "Unrecognised build $($osInfo.CurrentBuild) - applying all known KIR values"
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "713073804" -Value 0 -Type DWord
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "1921033356" -Value 0 -Type DWord
						Set-SystemTweaksRegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides" -Name "3598754956" -Value 0 -Type DWord
					}
				}
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to apply client KIR values: $($_.Exception.Message)"
		}

		LogInfo "KIR reboot required for this change to take effect."

		LogInfo "Stopping the Print Spooler for client-side CSR cleanup"
		try
		{
			Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not stop the Print Spooler for client-side cleanup: $($_.Exception.Message)"
		}
		Start-Sleep -Seconds 2

		try
		{
			$clientCsrPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers\Client Side Rendering Print Provider"
			if (Test-Path $clientCsrPath)
			{
				$bak = Join-Path $env:TEMP "CSR_Client_backup.reg"
				$native = $clientCsrPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
				& reg export $native $bak /y | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "reg export returned exit code $LASTEXITCODE while backing up the client CSR Print Provider key"
				}
				Remove-Item -Path $clientCsrPath -Recurse -Force -ErrorAction Stop
				LogInfo "Deleted CSR Print Provider key on client (backed up to $bak)"
			}
			else
			{
				LogInfo "CSR key not present on client -- OK"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not remove client CSR key: $($_.Exception.Message)"
		}

		LogInfo "mscms.dll copy on client"
		$clientSrc = Join-Path $env:SystemRoot "System32\mscms.dll"
		if (Test-Path $clientSrc)
		{
			foreach ($f in @(
				"$env:SystemRoot\System32\spool\drivers\x64\3",
				"$env:SystemRoot\System32\spool\drivers\x64\4",
				"$env:SystemRoot\System32\spool\drivers\W32X86\3",
				"$env:SystemRoot\System32\spool\drivers\arm64\3",
				"$env:SystemRoot\System32\spool\drivers\arm64\4"
			))
			{
				if (Test-Path $f)
				{
					try
					{
						Copy-Item -Path $clientSrc -Destination (Join-Path $f "mscms.dll") -Force -ErrorAction Stop
						LogInfo "Copied mscms.dll -> $f"
					}
					catch
					{
						$hadIssue = $true
						LogWarning "Could not copy mscms.dll to $f : $($_.Exception.Message)"
					}
				}
			}
		}
		else
		{
			$hadIssue = $true
			LogWarning "mscms.dll not found at $clientSrc -- run sfc /scannow"
		}

		LogInfo "Client-side SFC system file check"
		try
		{
			$sfc = Start-Process -FilePath sfc.exe -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow -ErrorAction Stop
			if ($sfc.ExitCode -eq 0)
			{
				LogInfo "SFC completed -- no violations found"
			}
			else
			{
				LogWarning "SFC ExitCode $($sfc.ExitCode) -- check CBS.log for details"
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "SFC could not be run: $($_.Exception.Message)"
		}

		LogInfo "Final client spooler restart"
		try
		{
			Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not stop the Print Spooler for the final client restart: $($_.Exception.Message)"
		}
		Start-Sleep -Seconds 2

		try
		{
			Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
			Start-Service -Name Spooler -ErrorAction SilentlyContinue
			Start-Sleep -Seconds 2
			$spoolerStatus = (Get-Service -Name Spooler -ErrorAction Stop).Status
			LogInfo "Print Spooler: $spoolerStatus"
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Could not restart the Print Spooler on the client: $($_.Exception.Message)"
		}
	}

	LogInfo "Host SFC check (background)"
	try
	{
		Start-Process -FilePath sfc.exe -ArgumentList "/scannow" -WindowStyle Hidden -ErrorAction Stop | Out-Null
		LogInfo "SFC launched in background -- check CBS.log if issues persist after reboot"
	}
	catch
	{
		$hadIssue = $true
		LogWarning "SFC could not be launched: $($_.Exception.Message)"
	}

	LogWarning "Restart required to complete shared printer connection repairs."
	if ($hadIssue)
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
	Enable or disable Adobe Network Block

	.PARAMETER Enable
	Enable Adobe Network Block

	.PARAMETER Disable
	Disable Adobe Network Block (default value)

	.EXAMPLE
	AdobeNetworkBlock -Enable

	.EXAMPLE
	AdobeNetworkBlock -Disable

	.NOTES
	Current user

	CAUTION:
	Blocking Adobe network access may:
	- Prevent license validation and activation
	- Disable Creative Cloud syncing
	- Break cloud-based features (Fonts, Libraries, AI tools, etc.)
	- Trigger subscription or account errors
	- Violate Adobe license terms depending on usage

	Use only if you understand the implications.
#>
function AdobeNetworkBlock
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$hosts = "$Env:SystemRoot\System32\drivers\etc\hosts"
	$hostsUrl = "https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Adobe Network Block"
			LogInfo "Enabling Adobe Network Block"
			try
			{
				if (Test-Path $hosts)
				{
					Copy-Item $hosts "$hosts.bak" -Force -ErrorAction Stop | Out-Null
					LogInfo "Backed up original hosts file to $hosts.bak"
				}
				Invoke-WebRequest $hostsUrl -OutFile $hosts -UseBasicParsing -ErrorAction Stop | Out-Null
				LogInfo "Downloaded and applied Adobe block list"
				ipconfig /flushdns 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "ipconfig returned exit code $LASTEXITCODE while flushing DNS"
				}
				LogInfo "Flushed DNS cache"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to enable Adobe Network Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Adobe Network Block"
			LogInfo "Disabling Adobe Network Block"
			try
			{
				if (Test-Path "$hosts.bak")
				{
					Remove-Item $hosts -Force -ErrorAction Stop | Out-Null
					Move-Item "$hosts.bak" $hosts -Force -ErrorAction Stop | Out-Null
					LogInfo "Restored original hosts file from backup"
				}
				ipconfig /flushdns 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "ipconfig returned exit code $LASTEXITCODE while flushing DNS"
				}
				LogInfo "Flushed DNS cache"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to disable Adobe Network Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Brave Debloat

.PARAMETER Enable
Enable Brave Debloat

.PARAMETER Disable
Disable Brave Debloat (default value)

.EXAMPLE
BraveDebloat -Enable

.EXAMPLE
BraveDebloat -Disable

.NOTES
Current user
#>
function BraveDebloat
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$BravePath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Brave Debloat"
			LogInfo "Enabling Brave Debloat"
			if (-not (Test-Path $BravePath))
			{
				New-Item -Path $BravePath -Force -ErrorAction SilentlyContinue | Out-Null
			}
			Set-ItemProperty -Path $BravePath -Name "BraveRewardsDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveWalletDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveVPNDisabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveAIChatEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			Set-ItemProperty -Path $BravePath -Name "BraveStatsPingEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
			LogInfo "Brave debloat policies applied"
			Write-ConsoleStatus -Status success
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Brave Debloat"
			LogInfo "Disabling Brave Debloat"
			Remove-ItemProperty -Path $BravePath -Name "BraveRewardsDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveWalletDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveVPNDisabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveAIChatEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			Remove-ItemProperty -Path $BravePath -Name "BraveStatsPingEnabled" -Force -ErrorAction SilentlyContinue | Out-Null
			LogInfo "Brave debloat policies removed"
			Write-ConsoleStatus -Status success
		}
	}
}

<#
.SYNOPSIS
Enable or disable Cross-Device Resume

.PARAMETER Enable
Enable Cross-Device Resume (default value)

.PARAMETER Disable
Disable Cross-Device Resume

.EXAMPLE
CrossDeviceResume -Enable

.EXAMPLE
CrossDeviceResume -Disable

.NOTES
Current user
#>
function CrossDeviceResume
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

	$SupportedMessage = "Cross-Device Resume is only supported on Windows 11 24H2 build 26100.7705+ or 26H1 build 28000.1575+ and newer. Skipping."
	$IsCrossDeviceResumeSupported = Test-Windows11FeatureBranchSupport -Thresholds @(
		@{ DisplayVersion = "24H2"; Build = 26100; UBR = 7705 },
		@{ DisplayVersion = "26H1"; Build = 28000; UBR = 1575 }
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Cross-Device Resume"
			LogInfo "Enabling Cross-Device Resume"

			if (-not $IsCrossDeviceResumeSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				if (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name "IsResumeAllowed" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Cross-Device Resume: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Cross-Device Resume"
			LogInfo "Disabling Cross-Device Resume"

			if (-not $IsCrossDeviceResumeSupported)
			{
				Write-ConsoleStatus -Status success
				LogWarning $SupportedMessage
				return
			}

			try
			{
				if (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration")) {
					New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Name "IsResumeAllowed" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Cross-Device Resume: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Run Disk Cleanup on Drive C: and remove old Windows Updates

.EXAMPLE
DiskCleanup

.NOTES
Current user
#>
function DiskCleanup
{
	Write-ConsoleStatus -Action "Running Disk Cleanup"
	Write-Host "open in new window"
	LogInfo "Running Disk Cleanup"
	# Pass log file path to child process
	[Environment]::SetEnvironmentVariable("diskcleanup", $global:LogFilePath, "Process")

	$ScriptPath = Join-Path $PSScriptRoot "..\..\Assets\diskcleanup.ps1"
	$ScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)

	Start-Process powershell.exe `
		-ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
		-WindowStyle Hidden | Out-Null
}

<#
.SYNOPSIS
Enable or disable Explorer Automatic Folder Discovery

.PARAMETER Enable
Enable Explorer Automatic Folder Discovery

.PARAMETER Disable
Disable Explorer Automatic Folder Discovery (default value)

.EXAMPLE
ExplorerAutoDiscovery -Enable

.EXAMPLE
ExplorerAutoDiscovery -Disable

.NOTES
Current user
#>
function ExplorerAutoDiscovery
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

	$bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
	$bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
	$allFolders = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Explorer Automatic Folder Discovery"
			LogInfo "Enabling Explorer Automatic Folder Discovery"
			try
			{
				if (Test-Path $bags)
				{
					Remove-Item -Path $bags -Recurse -Force -ErrorAction Stop | Out-Null
				}
				if (Test-Path $bagMRU)
				{
					Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction Stop | Out-Null
				}
				LogInfo "Please sign out and back in, or restart your computer to apply the changes."
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Explorer Automatic Folder Discovery: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Explorer Automatic Folder Discovery"
			LogInfo "Disabling Explorer Automatic Folder Discovery"
			try
			{
				if (Test-Path $bags)
				{
					Remove-Item -Path $bags -Recurse -Force -ErrorAction Stop | Out-Null
				}
				if (Test-Path $bagMRU)
				{
					Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction Stop | Out-Null
				}

				if (-not (Test-Path $allFolders))
				{
					New-Item -Path $allFolders -Force -ErrorAction Stop | Out-Null
				}

				Set-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" -Type String -Force -ErrorAction Stop | Out-Null
				LogInfo "Please sign out and back in, or restart your computer to apply the changes."
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Explorer Automatic Folder Discovery: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Modern Standby fix

.PARAMETER Enable
Enable Modern Standby fix (default value)

.PARAMETER Disable
Disable Modern Standby fix

.EXAMPLE
StandbyFix -Enable

.EXAMPLE
StandbyFix -Disable

.NOTES
Current user
#>
function StandbyFix
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
			Write-ConsoleStatus -Action "Enabling Modern Standby fix"
			LogInfo "Enabling Modern Standby fix"
			try
			{
				if (-not (Test-Path -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9"))
				{
					New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Name "ACSettingIndex" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable the Modern Standby fix: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Modern Standby fix"
			LogInfo "Disabling Modern Standby fix"
			try
			{
				if ((Get-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Name "ACSettingIndex" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9" -Name "ACSettingIndex" -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable the Modern Standby fix: $($_.Exception.Message)"
			}
		}
	}
}

<#
	.SYNOPSIS
	Enable or disable Block Razer Software Installs

	.PARAMETER Enable
	Enable Block Razer Software Installs

	.PARAMETER Disable
	Disable Block Razer Software Installs (default value)

	.EXAMPLE
	RazerBlock -Enable

	.EXAMPLE
	RazerBlock -Disable

	.NOTES
	Current user

	CAUTION:
	Blocking Razer software installation may:
	- Prevent Razer Synapse from installing or updating
	- Disable RGB, macro, or device profile functionality
	- Stop firmware updates for Razer devices
	- Cause certain Razer peripherals to function with limited features

	Use only if you understand the implications.
#>
function RazerBlock
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$RazerPath = "C:\Windows\Installer\Razer"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Razer Software Block"
			LogInfo "Enabling Razer Software Block"
			try
			{
				# Registry changes
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				LogInfo "Set DriverSearching SearchOrderConfig to 0"
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" -Name "DisableCoInstallers" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				LogInfo "Set DisableCoInstallers to 1"

				# Block Razer installer directory
				if (Test-Path $RazerPath)
				{
					Remove-Item "$RazerPath\*" -Recurse -Force -ErrorAction Stop | Out-Null
					LogInfo "Cleared Razer installer directory"
				}
				else
				{
					New-Item -Path $RazerPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
					LogInfo "Created Razer installer directory"
				}

				icacls $RazerPath /deny "Everyone:(W)" 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "icacls returned exit code $LASTEXITCODE while applying deny permissions to $RazerPath"
				}
				LogInfo "Set deny write permission on Razer directory"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to enable Razer Software Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Razer Software Block"
			LogInfo "Disabling Razer Software Block"
			try
			{
				# Restore registry values
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				LogInfo "Restored DriverSearching SearchOrderConfig to 1"
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer" -Name "DisableCoInstallers" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				LogInfo "Restored DisableCoInstallers to 0"

				# Remove directory deny permission
				icacls $RazerPath /remove:d Everyone 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "icacls returned exit code $LASTEXITCODE while removing deny permissions from $RazerPath"
				}
				LogInfo "Removed deny write permission from Razer directory"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogError "Failed to disable Razer Software Block: $_"
				Write-ConsoleStatus -Status failed
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable S3 Sleep

.PARAMETER Enable
Enable S3 Sleep

.PARAMETER Disable
Disable S3 Sleep (default value)

.EXAMPLE
S3Sleep -Enable

.EXAMPLE
S3Sleep -Disable

.NOTES
Current user
#>
function S3Sleep
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
			Write-ConsoleStatus -Action "Enabling S3 Sleep"
			LogInfo "Enabling S3 Sleep"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable S3 Sleep: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling S3 Sleep"
			LogInfo "Disabling S3 Sleep"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable S3 Sleep: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable recommended Windows service startup configuration

.PARAMETER Enable
Apply recommended startup types to Windows services

.PARAMETER Disable
Restore Windows services to their original startup types (default value)

.EXAMPLE
ServicesManual -Enable

.EXAMPLE
ServicesManual -Disable

.NOTES
Current user
#>
function ServicesManual
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

	$services = @(
		@{ Name = "ALG";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppMgmt";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppReadiness";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AppVClient";                 StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "Appinfo";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "AssignedAccessManagerSvc";   StartupType = "Disabled";              OriginalType = "Manual" }
		@{ Name = "AudioEndpointBuilder";       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "AudioSrv";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "Audiosrv";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "AxInstSV";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BDESVC";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BITS";                       StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "BTAGService";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "BthAvctpSvc";                StartupType = "Automatic";             OriginalType = "Manual" }
		@{ Name = "CDPSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "COMSysApp";                  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "CertPropSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "CryptSvc";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "CscService";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DPS";                        StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DevQueryBroker";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DeviceAssociationService";   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "DeviceInstall";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Dhcp";                       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DiagTrack";                  StartupType = "Disabled";              OriginalType = "Automatic" }
		@{ Name = "DialogBlockingService";      StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "DispBrokerDesktopSvc";       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "DisplayEnhancementService";  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EFS";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EapHost";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "EventLog";                   StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "EventSystem";                StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "FDResPub";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "FontCache";                  StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "FrameServer";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "FrameServerMonitor";         StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "GraphicsPerfSvc";            StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "HvHost";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "IKEEXT";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "InstallService";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "InventorySvc";               StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "IpxlatCfgSvc";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "KeyIso";                     StartupType = "Automatic";             OriginalType = "Manual" }
		@{ Name = "KtmRm";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "LanmanServer";               StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "LanmanWorkstation";          StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "LicenseManager";             StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "LxpSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MSDTC";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MSiSCSI";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MapsBroker";                 StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "McpManagementService";       StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "MicrosoftEdgeElevationService"; StartupType = "Manual";             OriginalType = "Manual" }
		@{ Name = "NaturalAuthentication";      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcaSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcbService";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NcdAutoSetup";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NetSetupSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NetTcpPortSharing";          StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "Netman";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "NlaSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PcaSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "PeerDistSvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PerfHost";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PhoneSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PlugPlay";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "PolicyAgent";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Power";                      StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "PrintNotify";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "ProfSvc";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "PushToInstall";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "QWAVE";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RasAuto";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RasMan";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RemoteAccess";               StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "RemoteRegistry";             StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "RetailDemo";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RmSvc";                      StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "RpcLocator";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SCPolicySvc";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SCardSvr";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SDRSVC";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SEMgrSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SENS";                       StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SNMPTRAP";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SNMPTrap";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SSDPSRV";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SamSs";                      StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "ScDeviceEnum";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensorDataService";          StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensorService";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SensrSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SessionEnv";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "SharedAccess";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "ShellHWDetection";           StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SmsRouter";                  StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Spooler";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "SstpSvc";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "StiSvc";                     StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "StorSvc";                    StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "SysMain";                    StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TapiSrv";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TermService";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "Themes";                     StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TieringEngineService";       StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TokenBroker";                StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TrkWks";                     StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "TroubleshootingSvc";         StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "TrustedInstaller";           StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "UevAgentService";            StartupType = "Disabled";              OriginalType = "Disabled" }
		@{ Name = "UmRdpService";               StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "UserManager";                StartupType = "Automatic";             OriginalType = "Automatic" }
		@{ Name = "UsoSvc";                     StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "VSS";                        StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "VaultSvc";                   StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "W32Time";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WEPHOSTSVC";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WFDSConMgrSvc";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WMPNetworkSvc";              StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WManSvc";                    StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WPDBusEnum";                 StartupType = "Manual";                OriginalType = "Manual" }
		@{ Name = "WSAIFabricSvc";              StartupType = "Manual";                OriginalType = "Automatic" }
		@{ Name = "WSearch";                    StartupType = "AutomaticDelayedStart"; OriginalType = "Automatic" }
		@{ Name = "WalletService";              StartupType = "Manual";                OriginalType = "Manual" }
	)

	Write-ConsoleStatus -Action "Configuring Windows services"
	LogInfo "Configuring Windows services"

	foreach ($svc in $services)
	{
		$Name = $svc.Name

		if ($Enable)
		{
			$TargetType = $svc.StartupType
			LogInfo "Setting service $Name to $TargetType"
		}
		elseif ($Disable)
		{
			$TargetType = $svc.OriginalType
			LogInfo "Restoring service $Name to $TargetType"
		}

		try
		{
			$service = Get-Service -Name $Name -ErrorAction Stop

			# Handle AutomaticDelayedStart for Windows PowerShell < 7
			if (($PSVersionTable.PSVersion.Major -lt 7) -and
				($TargetType -eq "AutomaticDelayedStart"))
			{
				sc.exe config $Name start= delayed-auto 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0)
				{
					throw "sc.exe returned exit code $LASTEXITCODE while configuring service $Name"
				}
				LogInfo "Service $Name configured with delayed auto start"
			}
			else
			{
				$service | Set-Service -StartupType $TargetType -ErrorAction Stop | Out-Null
				LogInfo "Service $Name configured successfully"
			}
		}
		catch
		{
			if (
				$_.FullyQualifiedErrorId -like "*NoServiceFoundForGivenName*" -or
				$_.Exception.Message -like "*Cannot find any service with service name*"
			)
			{
				LogWarning "Service $Name was not found"
			}
			else
			{
				LogError "Failed to set service $Name : $($_.Exception.Message)"
			}
		}
	}

	LogInfo "Completed service configuration"
	Write-ConsoleStatus -Status success
}

<#
.SYNOPSIS
Enable or disable Teredo

.PARAMETER Enable
Enable Teredo (default value)

.PARAMETER Disable
Disable Teredo

.EXAMPLE
Teredo -Enable

.EXAMPLE
Teredo -Disable

.NOTES
Current user

.CAUTION
Teredo is an IPv6 tunneling protocol used for NAT traversal.
Disabling it may reduce network latency for some applications.
However, some games and peer-to-peer applications rely on Teredo for connectivity.
Xbox Live and certain multiplayer games may not function correctly without Teredo.
#>
function Teredo
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
			Write-ConsoleStatus -Action "Enabling Teredo"
			LogInfo "Enabling Teredo"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value 0 -Force -ErrorAction Stop | Out-Null
				netsh interface teredo set state default 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "netsh returned exit code $LASTEXITCODE" }
				LogInfo "Teredo enabled and set to default state"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Teredo: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Teredo"
			LogInfo "Disabling Teredo"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				netsh interface teredo set state disabled 2>$null | Out-Null
				if ($LASTEXITCODE -ne 0) { throw "netsh returned exit code $LASTEXITCODE" }
				LogInfo "Teredo disabled"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Teredo: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Enable or disable Windows Platform Binary Table (WPBT)

.PARAMETER Enable
Enable Windows Platform Binary Table (WPBT) (default value)

.PARAMETER Disable
Disable Windows Platform Binary Table (WPBT)

.EXAMPLE
WPBT -Enable

.EXAMPLE
WPBT -Disable

.NOTES
Current user
#>
function WPBT
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
			Write-ConsoleStatus -Action "Enabling Windows Platform Binary Table (WPBT)"
			LogInfo "Enabling Windows Platform Binary Table (WPBT)"
			try
			{
				if ((Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" -ErrorAction SilentlyContinue))
				{
					Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" -Force -ErrorAction Stop | Out-Null
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable WPBT: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Platform Binary Table (WPBT)"
			LogInfo "Disabling Windows Platform Binary Table (WPBT)"
			try
			{
				Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" -Type DWord -Value 1 -Force -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable WPBT: $($_.Exception.Message)"
			}
		}
	}
}

<#
.SYNOPSIS
Apply additional service-related optimizations from the legacy performance preset.

.EXAMPLE
Invoke-AdditionalServiceOptimizations

.NOTES
Current user
#>
function Invoke-AdditionalServiceOptimizations
{
	Write-ConsoleStatus -Action "Applying additional service optimizations"
	LogInfo "Applying additional service optimizations"

	$hadIssue = $false
	$memoryCompressionState = $null

	try
	{
		$memoryCompressionState = Get-MMAgent -ErrorAction Stop
	}
	catch
	{
		$memoryCompressionState = $null
	}

	if ($memoryCompressionState -and -not $memoryCompressionState.MemoryCompression)
	{
		LogInfo "Memory Compression already disabled"
	}
	else
	{
		try
		{
			Disable-MMAgent -mc -ErrorAction Stop | Out-Null

			$updatedMemoryCompressionState = Get-MMAgent -ErrorAction SilentlyContinue
			if ($updatedMemoryCompressionState -and -not $updatedMemoryCompressionState.MemoryCompression)
			{
				LogInfo "Disabled Memory Compression"
			}
			else
			{
				LogInfo "Requested Memory Compression disable"
			}
		}
		catch
		{
			$updatedMemoryCompressionState = Get-MMAgent -ErrorAction SilentlyContinue
			if ($updatedMemoryCompressionState -and -not $updatedMemoryCompressionState.MemoryCompression)
			{
				LogInfo "Memory Compression already disabled"
			}
			else
			{
				$hadIssue = $true
				LogWarning "Failed to disable Memory Compression: $($_.Exception.Message)"
			}
		}
	}

	$extraServices = @(
		"PeerDistSvc",
		"diagnosticshub.standardcollector.service",
		"RemoteRegistry"
	)

	foreach ($serviceName in $extraServices)
	{
		try
		{
			$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

			if ($service)
			{
				Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
				Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
			}
			else
			{
				$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
				if (Test-Path -Path $registryPath)
				{
					Set-ItemProperty -Path $registryPath -Name "Start" -Type DWord -Value 4 -Force -ErrorAction Stop | Out-Null
				}
				else
				{
					LogWarning "Service $serviceName not found"
				}
			}
		}
		catch
		{
			$hadIssue = $true
			LogWarning "Failed to disable $serviceName : $($_.Exception.Message)"
		}
	}

	if ($hadIssue)
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
Clean temporary files from the system.

.PARAMETER All
Clean all temporary directories and caches.

.PARAMETER Temp
Clean only TEMP folder.

.PARAMETER Cache
Clean only cache directories.

.PARAMETER Recycle
Empty the Recycle Bin.

.EXAMPLE
Invoke-CleanupOperation -All

.NOTES
Current user
#>
function Invoke-CleanupOperation
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "All")]
		[switch]$All,

		[Parameter(Mandatory = $true, ParameterSetName = "Temp")]
		[switch]$Temp,

		[Parameter(Mandatory = $true, ParameterSetName = "Cache")]
		[switch]$Cache,

		[Parameter(Mandatory = $true, ParameterSetName = "Recycle")]
		[switch]$Recycle
	)

	switch ($PSCmdlet.ParameterSetName)
	{
		"All"
		{
			LogInfo "Starting full cleanup operation"

			try
			{
				$downloads = (New-Object -ComObject Shell.Application).NameSpace("shell:Downloads").Self.Path
			}
			catch
			{
				$downloads = Join-Path $HOME "Downloads"
			}

			$cleanupPaths = @(
				@{ Path = "$env:TEMP\*"; Desc = "Windows TEMP" },
				@{ Path = "$env:SystemRoot\Temp\*"; Desc = "System TEMP" },
				@{ Path = "$env:LOCALAPPDATA\Temp\*"; Desc = "User TEMP" },
				@{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"; Desc = "Internet Cache" },
				@{ Path = "$env:LOCALAPPDATA\Temp\Low\*"; Desc = "Low Integrity TEMP" }
			)

			$leftoverFiles = @(
				(Join-Path $downloads "enable-photo-viewer.reg"),
				(Join-Path $downloads "ram-reducer.reg"),
				(Join-Path $downloads "bloatware.ps1"),
				"$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\startup.bat"
			)

			$cleaned = 0
			$failed = 0

			foreach ($item in $cleanupPaths)
			{
				try
				{
					if (Test-Path $item.Path)
					{
						Remove-Item -Path $item.Path -Force -Recurse -ErrorAction SilentlyContinue
						$cleaned++
					}
				}
				catch
				{
					$failed++
					LogWarning "Could not fully clean $($item.Desc): $($_.Exception.Message)"
				}
			}

			foreach ($leftoverFile in $leftoverFiles)
			{
				try
				{
					Remove-Item -Path $leftoverFile -Force -ErrorAction SilentlyContinue
				}
				catch
				{
					$failed++
					LogWarning "Could not remove leftover file $leftoverFile : $($_.Exception.Message)"
				}
			}

			LogInfo "Cleanup complete: $cleaned paths cleaned, $failed had issues"
			if ($failed -gt 0)
			{
				Write-ConsoleStatus -Action "Performing full cleanup" -Status warning
			}
			else
			{
				Write-ConsoleStatus -Action "Performing full cleanup" -Status success
			}
		}

		"Temp"
		{
			LogInfo "Cleaning TEMP folders"

			$tempPaths = @(
				"$env:TEMP\*",
				"$env:SystemRoot\Temp\*",
				"$env:LOCALAPPDATA\Temp\*"
			)

			$hadIssue = $false
			foreach ($path in $tempPaths)
			{
				try
				{
					if (Test-Path $path)
					{
						Remove-Item -Path $path -Force -Recurse -ErrorAction SilentlyContinue
					}
				}
				catch
				{
					$hadIssue = $true
					LogWarning "Error cleaning $path : $($_.Exception.Message)"
				}
			}

			if ($hadIssue)
			{
				Write-ConsoleStatus -Action "Cleaning TEMP folders" -Status warning
			}
			else
			{
				Write-ConsoleStatus -Action "Cleaning TEMP folders" -Status success
			}
		}

		"Cache"
		{
			LogInfo "Cleaning cache directories"

			$cachePaths = @(
				"$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*",
				"$env:APPDATA\Microsoft\Windows\INetCache\*",
				"$env:LOCALAPPDATA\Temp\Low\*"
			)

			$hadIssue = $false
			foreach ($path in $cachePaths)
			{
				try
				{
					if (Test-Path $path)
					{
						Remove-Item -Path $path -Force -Recurse -ErrorAction SilentlyContinue
					}
				}
				catch
				{
					$hadIssue = $true
					LogWarning "Error cleaning $path : $($_.Exception.Message)"
				}
			}

			if ($hadIssue)
			{
				Write-ConsoleStatus -Action "Cleaning cache directories" -Status warning
			}
			else
			{
				Write-ConsoleStatus -Action "Cleaning cache directories" -Status success
			}
		}

		"Recycle"
		{
			Write-ConsoleStatus -Action "Emptying Recycle Bin"
			LogInfo "Emptying Recycle Bin"

			try
			{
				Clear-RecycleBin -Force -ErrorAction Stop
				LogInfo "Recycle Bin emptied"
				Write-ConsoleStatus -Status success
			}
			catch
			{
				LogWarning "Failed to empty Recycle Bin: $($_.Exception.Message)"
				Write-ConsoleStatus -Status failed
			}
		}
	}
}

<#
.SYNOPSIS
Generate and display cleanup statistics.

.EXAMPLE
Get-CleanupStats

.NOTES
Current user
#>
function Get-CleanupStats
{
	Write-Host "`nCalculating cleanup size..." -ForegroundColor Cyan

	$paths = @(
		@{ Path = "$env:TEMP"; Desc = "User TEMP" },
		@{ Path = "$env:SystemRoot\Temp"; Desc = "System TEMP" },
		@{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Desc = "Internet Cache" }
	)

	$totalSize = 0
	$itemCount = 0
	$pathsWithContent = 0

	Write-Host "`nCleanup Space Calculator:" -ForegroundColor Green
	Write-Host "-----------------------------------------" -ForegroundColor Green

	foreach ($item in $paths)
	{
		try
		{
			if (Test-Path $item.Path)
			{
				$size = (Get-ChildItem -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue |
					Measure-Object -Property Length -Sum).Sum

				$count = (Get-ChildItem -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue |
					Measure-Object).Count

				if ($size -gt 0)
				{
					$sizeGB = [math]::Round($size / 1GB, 2)
					Write-Host ("{0}: {1} GB ({2} files)" -f $item.Desc, $sizeGB, $count) -ForegroundColor Yellow
					$totalSize += $size
					$itemCount += $count
					$pathsWithContent++
				}
			}
		}
		catch
		{
			LogWarning "Could not calculate size for $($item.Desc): $($_.Exception.Message)"
		}
	}

	Write-Host "-----------------------------------------" -ForegroundColor Green
	if ($pathsWithContent -eq 0)
	{
		Write-Host "No cleanup candidates found." -ForegroundColor Yellow
	}
	else
	{
		$totalGB = [math]::Round($totalSize / 1GB, 2)
		Write-Host ("TOTAL: {0} GB ({1} files)" -f $totalGB, $itemCount) -ForegroundColor Cyan
	}
	Write-Host "`n"
}

#endregion System Tweaks
