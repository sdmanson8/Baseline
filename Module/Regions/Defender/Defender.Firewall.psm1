using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Configures Windows Firewall configuration.



.DESCRIPTION

Applies Baseline's Windows Firewall configuration in GUI and headless runs.
	.PARAMETER Enable
	Enable Windows Firewall (default value)

	.PARAMETER Disable
	Disable Windows Firewall

	.EXAMPLE
	Firewall -Enable

	.EXAMPLE
	Firewall -Disable

	.NOTES
	Current user
#>
function Firewall
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
			Write-ConsoleStatus -Action "Enabling Windows Firewall"
			LogInfo "Enabling Windows Firewall"
			try
			{
				Remove-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile" -Name "EnableFirewall" | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Windows Firewall: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Windows Firewall"
			LogInfo "Disabling Windows Firewall"
			try
			{
				If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile")) {
					New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile" -Force -ErrorAction Stop | Out-Null
				}
				Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile" -Name "EnableFirewall" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Windows Firewall: $($_.Exception.Message)"
			}
		}
	}
}

function WindowsFirewallLogging
{
	<#
		.SYNOPSIS
		Configure Windows Firewall logging.

		.DESCRIPTION
		Configures the current firewall profile to log to pfirewall.log with a
		larger size limit and dropped-connections logging enabled.

		.EXAMPLE
		WindowsFirewallLogging

		.NOTES
		Machine-wide

		Caution:
		Usually safe, but log file growth and storage policies should still be
		considered on managed systems.
	#>
	Write-ConsoleStatus -Action "Configuring Windows Firewall logging"
	LogInfo "Configuring Windows Firewall logging"
	try
	{
		# Apply per-profile (Domain / Private / Public) so traffic filtered on
		# any profile lands in its own log; enable both dropped and allowed
		# connection logging. windows_hardening.cmd only configured currentprofile
		# + dropped, leaving the other two profiles unaudited.
		$profiles = @('domainprofile', 'privateprofile', 'publicprofile')
		$logRoot  = '%systemroot%\system32\LogFiles\Firewall'

		foreach ($profile in $profiles)
		{
			$leaf    = ($profile -replace 'profile$', '')
			$logPath = "$logRoot\pfirewall_$leaf.log"
			netsh advfirewall set $profile logging filename $logPath | Out-Null
			netsh advfirewall set $profile logging maxfilesize 16384 | Out-Null
			netsh advfirewall set $profile logging droppedconnections enable | Out-Null
			netsh advfirewall set $profile logging allowedconnections enable | Out-Null
		}
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to configure Windows Firewall logging: $($_.Exception.Message)"
	}
}

function LOLBinFirewallRules
{
	<#
		.SYNOPSIS
		Configure LOLBin outbound firewall block rules.

		.DESCRIPTION
		Enable: adds outbound block rules for built-in Windows binaries that should
		not normally make network connections. All rules are tagged with the
		Baseline-LOLBin-Block group so removal is a single
		Remove-NetFirewallRule -Group call rather than a per-rule iteration.

		Disable: removes every rule in the Baseline-LOLBin-Block group, restoring
		default outbound behaviour for these binaries.

		.PARAMETER Enable
		Add the LOLBin outbound block rules.

		.PARAMETER Disable
		Remove every rule in the Baseline-LOLBin-Block group.

		.EXAMPLE
		LOLBinFirewallRules -Enable

		.EXAMPLE
		LOLBinFirewallRules -Disable

		.NOTES
		Machine-wide

		Caution:
		Advanced. Can break administrative scripts, installers, troubleshooting
		tools, or enterprise workflows that intentionally use these binaries.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Enable')]
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
		[switch]
		$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
		[switch]
		$Disable
	)

	$groupName = 'Baseline-LOLBin-Block'

	if ($PSCmdlet.ParameterSetName -eq 'Disable')
	{
		Write-ConsoleStatus -Action "Removing LOLBin firewall rules"
		LogInfo "Removing LOLBin firewall rules"
		try
		{
			# Remove-NetFirewallRule -Group is the only built-in way to delete a
			# whole rule group in one shot; netsh advfirewall has no group filter.
			Remove-NetFirewallRule -Group $groupName -ErrorAction SilentlyContinue
			Write-ConsoleStatus -Status success
		}
		catch
		{
			Write-ConsoleStatus -Status failed
			LogError "Failed to remove LOLBin firewall rules: $($_.Exception.Message)"
		}
		return
	}

	Write-ConsoleStatus -Action "Configuring LOLBin firewall rules"
	LogInfo "Configuring LOLBin firewall rules"
	try
	{
		$programs = @(
			'%programfiles(x86)%\\Microsoft Office\\root\\client\\AppVLP.exe',
			'%programfiles%\\Microsoft Office\\root\\client\\AppVLP.exe',
			'%systemroot%\\system32\\calc.exe',
			'%systemroot%\\SysWOW64\\calc.exe',
			'%systemroot%\\system32\\certutil.exe',
			'%systemroot%\\SysWOW64\\certutil.exe',
			'%systemroot%\\system32\\cmstp.exe',
			'%systemroot%\\SysWOW64\\cmstp.exe',
			'%systemroot%\\system32\\esentutl.exe',
			'%systemroot%\\SysWOW64\\esentutl.exe',
			'%systemroot%\\system32\\expand.exe',
			'%systemroot%\\SysWOW64\\expand.exe',
			'%systemroot%\\system32\\extrac32.exe',
			'%systemroot%\\SysWOW64\\extrac32.exe',
			'%systemroot%\\system32\\findstr.exe',
			'%systemroot%\\SysWOW64\\findstr.exe',
			'%systemroot%\\system32\\hh.exe',
			'%systemroot%\\SysWOW64\\hh.exe',
			'%systemroot%\\system32\\makecab.exe',
			'%systemroot%\\SysWOW64\\makecab.exe',
			'%systemroot%\\system32\\mshta.exe',
			'%systemroot%\\SysWOW64\\mshta.exe',
			'%systemroot%\\system32\\msiexec.exe',
			'%systemroot%\\SysWOW64\\msiexec.exe',
			'%systemroot%\\system32\\nltest.exe',
			'%systemroot%\\SysWOW64\\nltest.exe',
			'%systemroot%\\system32\\notepad.exe',
			'%systemroot%\\SysWOW64\\notepad.exe',
			'%systemroot%\\system32\\odbcconf.exe',
			'%systemroot%\\SysWOW64\\odbcconf.exe',
			'%systemroot%\\system32\\pcalua.exe',
			'%systemroot%\\SysWOW64\\pcalua.exe',
			'%systemroot%\\system32\\regasm.exe',
			'%systemroot%\\SysWOW64\\regasm.exe',
			'%systemroot%\\system32\\regsvr32.exe',
			'%systemroot%\\SysWOW64\\regsvr32.exe',
			'%systemroot%\\system32\\replace.exe',
			'%systemroot%\\SysWOW64\\replace.exe',
			'%systemroot%\\SysWOW64\\rpcping.exe',
			'%systemroot%\\system32\\rundll32.exe',
			'%systemroot%\\SysWOW64\\rundll32.exe',
			'%systemroot%\\system32\\SyncAppvPublishingServer.exe',
			'%systemroot%\\SysWOW64\\SyncAppvPublishingServer.exe',
			'%systemroot%\\system32\\wbem\\wmic.exe',
			'%systemroot%\\SysWOW64\\wbem\\wmic.exe'
		)

		foreach ($program in $programs)
		{
			$expandedProgram = [Environment]::ExpandEnvironmentVariables($program)
			$ruleName = "$groupName`: $(Split-Path $expandedProgram -Leaf)"
			# New-NetFirewallRule -Group tags every rule with the Baseline-LOLBin-Block
			# group so a single Remove-NetFirewallRule -Group call cleans them all up.
			New-NetFirewallRule -DisplayName $ruleName -Group $groupName -Direction Outbound -Action Block -Program $expandedProgram -Protocol TCP -Profile Any -Enabled True -ErrorAction Stop | Out-Null
		}

		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to configure LOLBin firewall rules: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Microsoft Defender Exploit Guard network protection



.DESCRIPTION

Applies the Baseline behavior for microsoft Defender Exploit Guard network protection.
	.PARAMETER Enable
	Enable Microsoft Defender Exploit Guard network protection

	.PARAMETER Disable
	Disable Microsoft Defender Exploit Guard network protection (default value)

	.EXAMPLE
	NetworkProtection -Enable

	.EXAMPLE
	NetworkProtection -Disable

	.NOTES
	Current user
#>
function NetworkProtection
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

	if (-not (Test-BaselineDefenderExecutionAvailable))
	{
		LogWarning ("Skipping {0}: {1}" -f (Get-TweakSkipLabel $MyInvocation), (Get-BaselineDefenderExecutionUnavailableReason))
		return
	}

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling Microsoft Defender Exploit Guard network protection"
			LogInfo "Enabling Microsoft Defender Exploit Guard network protection"
			try
			{
				Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable Microsoft Defender Exploit Guard network protection: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling Microsoft Defender Exploit Guard network protection"
			LogInfo "Disabling Microsoft Defender Exploit Guard network protection"
			try
			{
				Set-MpPreference -EnableNetworkProtection Disabled -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable Microsoft Defender Exploit Guard network protection: $($_.Exception.Message)"
			}
		}
	}
}
$ExportedFunctions = @(
    'Firewall',
    'LOLBinFirewallRules',
    'NetworkProtection',
    'WindowsFirewallLogging'
)
Export-ModuleMember -Function $ExportedFunctions
