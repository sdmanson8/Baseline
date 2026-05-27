using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1



<#
.SYNOPSIS
Configures insecure SMB guest authentication repair.

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


<#
.SYNOPSIS
Repair the common Windows 11 SMB client/share issue introduced after updates.



.DESCRIPTION

Applies the Baseline behavior for repair the common Windows 11 SMB client/share issue introduced after updates..
.EXAMPLE
Windows11SMBUpdateIssue

.NOTES
Current user
#>
function Windows11SMBUpdateIssue
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
			SMBGuestCompatibility -SuppressConsoleStatus
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



.DESCRIPTION

Applies the Baseline behavior for enable guest/no-prompt SMB compatibility on non-domain machines..
.EXAMPLE
SMBGuestCompatibility

.NOTES
Current user
#>
function SMBGuestCompatibility
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



.DESCRIPTION

Applies the Baseline behavior for preserve SMB file sharing, printer sharing, and Windows credential access..
.EXAMPLE
SMBSharingCompatibility

.NOTES
Current user
#>
function SMBSharingCompatibility
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


function Wait-SharedPrinterSpoolerServiceStatus
{
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Running', 'Stopped')]
		[string]$Status,

		[int]$TimeoutSeconds = 45
	)

	$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
	do
	{
		$service = Get-Service -Name Spooler -ErrorAction SilentlyContinue
		if (-not $service)
		{
			LogWarning "Print Spooler service was not found."
			return $false
		}

		if ([string]$service.Status -eq $Status)
		{
			LogInfo "Print Spooler: $Status"
			return $true
		}

		Start-Sleep -Milliseconds 500
	}
	while ((Get-Date) -lt $deadline)

	LogWarning "Print Spooler did not reach '$Status' within $TimeoutSeconds second(s)."
	return $false
}

function Stop-SharedPrinterSpoolerService
{
	param (
		[string]$Reason = 'printer repair'
	)

	$scExePath = Join-Path $env:SystemRoot 'System32\sc.exe'
	try
	{
		$service = Get-Service -Name Spooler -ErrorAction SilentlyContinue
		if (-not $service)
		{
			LogWarning "Print Spooler service was not found while stopping for $Reason."
			return $false
		}

		if ([string]$service.Status -eq 'Stopped')
		{
			LogInfo "Print Spooler already stopped for $Reason."
			return $true
		}

		$null = Invoke-BaselineProcess -FilePath $scExePath -ArgumentList @('stop', 'Spooler') -TimeoutSeconds 30 -AllowedExitCodes @(0, 1056, 1060, 1062)
		return (Wait-SharedPrinterSpoolerServiceStatus -Status Stopped -TimeoutSeconds 45)
	}
	catch
	{
		LogWarning "Could not stop the Print Spooler for ${Reason}: $($_.Exception.Message)"
		return $false
	}
}

function Start-SharedPrinterSpoolerService
{
	param (
		[string]$Reason = 'printer repair'
	)

	$scExePath = Join-Path $env:SystemRoot 'System32\sc.exe'
	try
	{
		$null = Invoke-BaselineProcess -FilePath $scExePath -ArgumentList @('config', 'Spooler', 'start=', 'auto') -TimeoutSeconds 30 -AllowedExitCodes @(0)
		$service = Get-Service -Name Spooler -ErrorAction SilentlyContinue
		if ($service -and [string]$service.Status -eq 'Running')
		{
			LogInfo "Print Spooler already running after $Reason."
			return $true
		}

		$null = Invoke-BaselineProcess -FilePath $scExePath -ArgumentList @('start', 'Spooler') -TimeoutSeconds 30 -AllowedExitCodes @(0, 1056)
		return (Wait-SharedPrinterSpoolerServiceStatus -Status Running -TimeoutSeconds 45)
	}
	catch
	{
		LogWarning "Could not start the Print Spooler after ${Reason}: $($_.Exception.Message)"
		return $false
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

.PARAMETER RunSystemFileCheck
Run a bounded SFC repair scan after printer-specific repair steps.

.EXAMPLE
SharedPrinterConnectionErrors

.EXAMPLE
SharedPrinterConnectionErrors -ClientMode

.EXAMPLE
SharedPrinterConnectionErrors -SkipSpoolerSpool

.NOTES
Machine-wide
Requires an elevated PowerShell session.
Medium risk.
Restart required.
#>

function SharedPrinterConnectionErrors
{
	[CmdletBinding()]
	param
	(
		[switch]
		$ClientMode,

		[switch]
		$SkipSpoolerSpool,

		[switch]
		$RunSystemFileCheck
	)

	Write-ConsoleStatus -Action "Repairing shared printer connection errors"
	LogInfo "Repairing shared printer connection errors"

	$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
	if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
	{
		LogError "SharedPrinterConnectionErrors requires an elevated PowerShell session."
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
		. (Join-Path $PSScriptRoot 'SMBRepair\SharedPrinterConnectionErrors\RegistryCompatibilitySettings.ps1')

	LogInfo "Refreshing DNS and NetBIOS caches"
		. (Join-Path $PSScriptRoot 'SMBRepair\SharedPrinterConnectionErrors\NetworkCacheFlush.ps1')

	LogInfo "Stopping the Print Spooler to clear stale jobs"
	if (-not (Stop-SharedPrinterSpoolerService -Reason 'clearing stale print jobs'))
	{
		$hadIssue = $true
	}

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

	if (-not (Start-SharedPrinterSpoolerService -Reason 'stale print job cleanup'))
	{
		$hadIssue = $true
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
					Set-ItemProperty -LiteralPath $sessionManagerPath -Name "PendingFileRenameOperations" -Value $filtered -Force
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
	if (-not (Stop-SharedPrinterSpoolerService -Reason 'print provider cleanup'))
	{
		$hadIssue = $true
	}

	try
	{
		$csrPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers\Client Side Rendering Print Provider"
		if (Test-Path $csrPath)
		{
			$csrBackup = Join-Path $env:TEMP "CSR_PrintProvider_backup.reg"
			$csrNative = $csrPath -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\'
			$regExePath = Join-Path $env:SystemRoot 'System32\reg.exe'
			$null = Invoke-BaselineProcess -FilePath $regExePath -ArgumentList @('export', $csrNative, $csrBackup, '/y') -TimeoutSeconds 120 -AllowedExitCodes @(0)
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

	if (-not (Start-SharedPrinterSpoolerService -Reason 'print provider cleanup'))
	{
		$hadIssue = $true
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
		. (Join-Path $PSScriptRoot 'SMBRepair\SharedPrinterConnectionErrors\PrinterRegistryAclRepair.ps1')

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
		. (Join-Path $PSScriptRoot 'SMBRepair\SharedPrinterConnectionErrors\TcpCompatibilitySettings.ps1')

	LogInfo "Shared printer audit"
		. (Join-Path $PSScriptRoot 'SMBRepair\SharedPrinterConnectionErrors\SharedPrinterDiscovery.ps1')

	if ($RunSystemFileCheck)
	{
		LogInfo "Host SFC check"
		try
		{
			$null = Invoke-BaselineProcess -FilePath "$env:SystemRoot\System32\sfc.exe" -ArgumentList @('/scannow') -TimeoutSeconds 1800 -AllowedExitCodes @(0)
			LogInfo "SFC completed successfully"
		}
		catch
		{
			$hadIssue = $true
			LogWarning "SFC did not complete successfully: $($_.Exception.Message)"
		}
	}
	else
	{
		LogInfo "Skipped host SFC check during shared printer repair. Use -RunSystemFileCheck when a full system file repair scan is explicitly required."
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
$ExportedFunctions = @(
    'LanmanWorkstationGuestAuthPolicy',
    'SharedPrinterConnectionErrors',
    'SMBGuestCompatibility',
    'SMBSharingCompatibility',
    'Windows11SMBUpdateIssue'
)
Export-ModuleMember -Function $ExportedFunctions
