# Shared helper slice for Baseline -- system maintenance, RAM checks, and service management.

function Test-Windows11SmbDuplicateSidIssue
{
	<# .SYNOPSIS Checks Event ID 6167 for SMB duplicate SID issues in a lookback period. #>
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
		LogWarning "Unable to query LSASS Event ID 6167 (check inconclusive): $($_.Exception.Message)"
		return $false
	}
}

function Get-MinimumRecommendedMemoryCompressionRamGB
{
	<# .SYNOPSIS Returns the minimum RAM threshold (8 GB) for safe Memory Compression disable. #>
	return 8
}

function Invoke-AdditionalServiceOptimizations
{
	<# .SYNOPSIS Disables Memory Compression and optional services (PeerDist, diagnosticshub, RemoteRegistry). #>
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
		$totalRAMGB = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)
		$minimumRecommendedRamGB = Get-MinimumRecommendedMemoryCompressionRamGB
		if ($totalRAMGB -gt 0 -and $totalRAMGB -lt $minimumRecommendedRamGB)
		{
			LogWarning "Skipping Memory Compression disable - system has only ${totalRAMGB} GB RAM. Disabling on systems below ${minimumRecommendedRamGB} GB can degrade performance."
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
				$priorStartType = $service.StartType
				Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
				Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
				LogInfo "Disabled service $serviceName (was: $priorStartType)"
			}
			else
			{
				# Service not in SCM - fall back to direct registry write (service may be driver-only or partially installed).
				$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
				if (Test-Path -Path $registryPath)
				{
					LogWarning "Service $serviceName not found in SCM - disabling via registry fallback"
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
