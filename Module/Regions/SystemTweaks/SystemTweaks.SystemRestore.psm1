<#
.SYNOPSIS
System Restore enable / allocation / restore-point throttle toggles.

.DESCRIPTION
Three independent functions that close the tracked gap:

  SystemRestoreProtection      Enable / Disable System Protection on the
                               system drive (the persistent equivalent of
                               clicking "Configure -> Turn on system protection"
                               in the System Properties UI).

  SystemRestoreAllocation      Set the shadow-copy max-size on C: as a
                               percentage (5 / 10 / 15 / 20). Wraps
                               vssadmin resize shadowstorage.

  SystemRestorePointFrequency  Enable clears the SystemRestorePointCreationFrequency
                               throttle (default 1440 minutes = once per 24h);
                               Disable removes the override and lets Windows
                               re-apply its built-in throttle.

The functions never modify VSS / srservice startup state -- Baseline pins
VSS to Manual via ServicesManual; srservice is left at the Windows default
Manual. If either has been set to Disabled by hand, Enable will surface the
failure rather than silently flipping the service back on.
#>

function SystemRestoreProtection
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$drive = $env:SystemDrive
	if ([string]::IsNullOrWhiteSpace($drive)) { $drive = 'C:' }
	$driveRoot = "$drive\"

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Enabling System Protection on $drive"
			LogInfo "Enabling System Protection on $drive"
			try
			{
				Enable-ComputerRestore -Drive $driveRoot -ErrorAction Stop | Out-Null
				$srpStatus = Get-CimInstance -ClassName SystemRestoreConfig -Namespace 'root\default' -ErrorAction Stop
				if (-not ($srpStatus -and $srpStatus.RPSessionInterval -eq 1))
				{
					throw "Enable-ComputerRestore returned but SystemRestoreConfig.RPSessionInterval is not 1 (System Protection still off)."
				}
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to enable System Protection on $drive`: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Disabling System Protection on $drive"
			LogInfo "Disabling System Protection on $drive"
			try
			{
				Disable-ComputerRestore -Drive $driveRoot -ErrorAction Stop | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to disable System Protection on $drive`: $($_.Exception.Message)"
			}
		}
	}
}
<#
    .SYNOPSIS
    Set System Restore shadow storage allocation.

    .DESCRIPTION
    Resizes the System Restore shadow storage area on the system drive to the percentage selected by the active parameter set.

    .PARAMETER Pct5
    Set shadow storage allocation to 5 percent.

    .PARAMETER Pct10
    Set shadow storage allocation to 10 percent.

    .PARAMETER Pct15
    Set shadow storage allocation to 15 percent.

    .PARAMETER Pct20
    Set shadow storage allocation to 20 percent.

    .EXAMPLE
    SystemRestoreAllocation -Pct10
#>
function SystemRestoreAllocation
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Pct5")]
		[switch]$Pct5,

		[Parameter(Mandatory = $true, ParameterSetName = "Pct10")]
		[switch]$Pct10,

		[Parameter(Mandatory = $true, ParameterSetName = "Pct15")]
		[switch]$Pct15,

		[Parameter(Mandatory = $true, ParameterSetName = "Pct20")]
		[switch]$Pct20
	)

	$pct = switch ($PSCmdlet.ParameterSetName) {
		'Pct5' { 5 }
		'Pct10' { 10 }
		'Pct15' { 15 }
		'Pct20' { 20 }
	}

	$drive = $env:SystemDrive
	if ([string]::IsNullOrWhiteSpace($drive)) { $drive = 'C:' }

	Write-ConsoleStatus -Action "Setting System Restore shadow-storage to $pct% on $drive"
	LogInfo "Setting System Restore shadow-storage to $pct% on $drive"
	try
	{
		$output = & vssadmin resize shadowstorage "/For=$drive" "/On=$drive" "/MaxSize=$pct%" 2>&1
		if ($LASTEXITCODE -ne 0)
		{
			throw "vssadmin exited $LASTEXITCODE`: $($output -join ' | ')"
		}
		Write-ConsoleStatus -Status success
	}
	catch
	{
		Write-ConsoleStatus -Status failed
		LogError "Failed to resize shadow storage to $pct% on $drive`: $($_.Exception.Message)"
	}
}
<#
    .SYNOPSIS
    Enable or disable the System Restore creation throttle override.

    .DESCRIPTION
    Clears or restores the SystemRestorePointCreationFrequency policy value so Baseline can allow or stop immediate restore point creation.

    .PARAMETER Enable
    Clear the restore point creation throttle.

    .PARAMETER Disable
    Restore the default throttled behavior.

    .EXAMPLE
    SystemRestorePointFrequency -Enable
#>
function SystemRestorePointFrequency
{
	param
	(
		[Parameter(Mandatory = $true, ParameterSetName = "Enable")]
		[switch]$Enable,

		[Parameter(Mandatory = $true, ParameterSetName = "Disable")]
		[switch]$Disable
	)

	$keyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'

	switch ($PSCmdlet.ParameterSetName)
	{
		"Enable"
		{
			Write-ConsoleStatus -Action "Clearing System Restore creation throttle"
			LogInfo "Clearing System Restore creation throttle (SystemRestorePointCreationFrequency = 0)"
			try
			{
				if (-not (Test-Path -LiteralPath $keyPath))
				{
					New-Item -Path $keyPath -Force -ErrorAction Stop | Out-Null
				}
				Set-RegistryValueSafe -Path $keyPath -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to clear System Restore creation throttle: $($_.Exception.Message)"
			}
		}
		"Disable"
		{
			Write-ConsoleStatus -Action "Restoring default System Restore creation throttle"
			LogInfo "Restoring default System Restore creation throttle (Windows default = 1440 minutes)"
			try
			{
				Remove-RegistryValueSafe -Path $keyPath -Name 'SystemRestorePointCreationFrequency' | Out-Null
				Write-ConsoleStatus -Status success
			}
			catch
			{
				Write-ConsoleStatus -Status failed
				LogError "Failed to remove SystemRestorePointCreationFrequency override: $($_.Exception.Message)"
			}
		}
	}
}

Export-ModuleMember -Function SystemRestoreProtection, SystemRestoreAllocation, SystemRestorePointFrequency
