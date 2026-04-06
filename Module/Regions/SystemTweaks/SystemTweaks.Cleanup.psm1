using module ..\..\Logging.psm1
using module ..\..\SharedHelpers.psm1

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
	# Write-Host: intentional — user-visible progress indicator
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

Export-ModuleMember -Function '*'
