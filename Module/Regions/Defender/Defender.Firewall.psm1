using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

<#
	.SYNOPSIS
	Windows Firewall configuration

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
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile" -Name "EnableFirewall" -Type DWord -Value 0 -ErrorAction Stop | Out-Null
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

<#
	.SYNOPSIS
	Configure Windows Firewall logging.

	.DESCRIPTION
	Configures the current firewall profile to log to pfirewall.log with a
	larger size limit and dropped-connections logging enabled.

	.EXAMPLE
	Set-WindowsFirewallLogging

	.NOTES
	Machine-wide

	.CAUTION
	Usually safe, but log file growth and storage policies should still be
	considered on managed systems.
#>
function Set-WindowsFirewallLogging
{
	Write-ConsoleStatus -Action "Configuring Windows Firewall logging"
	LogInfo "Configuring Windows Firewall logging"
	try
	{
		netsh advfirewall set currentprofile logging filename %systemroot%\system32\LogFiles\Firewall\pfirewall.log | Out-Null
		netsh advfirewall set currentprofile logging maxfilesize 4096 | Out-Null
		netsh advfirewall set currentprofile logging droppedconnections enable | Out-Null
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to configure Windows Firewall logging: $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
	Configure LOLBin outbound firewall block rules.

	.DESCRIPTION
	Adds outbound block rules for a large list of built-in Windows binaries that
	should not normally make network connections.

	.EXAMPLE
	Set-LOLBinFirewallRules

	.NOTES
	Machine-wide

	.CAUTION
	Advanced. Can break administrative scripts, installers, troubleshooting
	tools, or enterprise workflows that intentionally use these binaries.
#>
function Set-LOLBinFirewallRules
{
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
			$ruleName = "Block $(Split-Path $expandedProgram -Leaf) netconns"
			netsh advfirewall firewall add rule name="$ruleName" program="$expandedProgram" protocol=tcp dir=out enable=yes action=block profile=any | Out-Null
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

	if (-not $Script:DefenderEnabled)
	{
		LogWarning ($Localization.Skipped -f (Get-TweakSkipLabel $MyInvocation))
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

Export-ModuleMember -Function '*'
