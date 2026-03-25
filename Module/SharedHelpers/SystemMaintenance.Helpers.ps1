# Shared helper slice for Baseline.

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
