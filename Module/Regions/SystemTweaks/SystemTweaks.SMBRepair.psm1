using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1


<#
.SYNOPSIS
Enable or disable insecure SMB guest authentication.

.DESCRIPTION
Controls the LanmanWorkstation AllowInsecureGuestAuth Group Policy setting.
Guest auth was disabled by default in Windows 10 1709+ because it is a known
lateral-movement vector. Enable only if you have legacy NAS/SMB shares that
require guest access.

.PARAMETER Enable
Allow insecure guest authentication for SMB connections.

.PARAMETER Disable
Block insecure guest authentication (secure default, recommended).

.EXAMPLE
LanmanWorkstationGuestAuthPolicy -Disable

.EXAMPLE
LanmanWorkstationGuestAuthPolicy -Enable

.NOTES
Machine-wide
#>
function LanmanWorkstationGuestAuthPolicy
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$action = if ($Enable) { "Enabling" } else { "Disabling" }
	$completedAction = if ($Enable) { "Enabled" } else { "Disabled" }
	$value  = if ($Enable) { 1 }          else { 0 }

	Write-ConsoleStatus -Action "$action LanmanWorkstation guest auth policy"
	LogInfo "$action LanmanWorkstation guest auth policy"

	$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"
	$valueName = "AllowInsecureGuestAuth"

	try
	{
		Set-Policy -Scope Computer -Path SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation -Name $valueName -Type DWord -Value $value | Out-Null
		LogInfo "$completedAction LanmanWorkstation guest-auth policy (AllowInsecureGuestAuth = $value)"
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to configure LanmanWorkstation guest auth policy: $($_.Exception.Message)"
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

	return Remove-RegistryValueSafe -Path $Path -Name $Name
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

	if (-not ($Global:BaselinePostActionRequirements -is [hashtable]))
	{
		$Global:BaselinePostActionRequirements = @{}
	}
	$Global:BaselinePostActionRequirements['EnsureSmbGuestAuth'] = $true

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

	if (-not ($Global:BaselinePostActionRequirements -is [hashtable]))
	{
		$Global:BaselinePostActionRequirements = @{}
	}
	$Global:BaselinePostActionRequirements['EnsurePrintManagementConsole'] = $true
	$Global:BaselinePostActionRequirements['EnsureSmbGuestAuth'] = $true

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

Export-ModuleMember -Function '*'
