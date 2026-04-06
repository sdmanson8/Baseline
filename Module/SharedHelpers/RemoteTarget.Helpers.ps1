# Remote targeting helper slice for Baseline.
# Provides multi-machine compliance checking and profile application over
# PowerShell Remoting (WinRM / PSSession). Each function accepts an array of
# computer names and operates in parallel per-session.
#
# Dependencies (loaded earlier in SharedHelpers.psm1):
#   Import-ConfigurationProfile       (ConfigProfile.Helpers.ps1)
#   Test-SystemCompliance              (Compliance.Helpers.ps1)
#   Import-TweakManifestFromData       (Manifest.Helpers.ps1)
#   Get-HeadlessPresetCommandList      (Preset.Helpers.ps1)

function Test-BaselineRemoteConnectivity
{
	<#
		.SYNOPSIS
		Tests WinRM connectivity for one or more remote computers.

		.DESCRIPTION
		Iterates over each computer name, calls Test-WSMan, and returns a
		per-machine result indicating whether the machine is reachable.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential
	)

	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($computer in @($ComputerName))
	{
		$entry = [pscustomobject]@{
			ComputerName = $computer
			Reachable    = $false
			Error        = $null
		}

		try
		{
			$wsmanParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }
			if ($Credential) { $wsmanParams.Credential = $Credential }

			$null = Test-WSMan @wsmanParams
			$entry.Reachable = $true
		}
		catch
		{
			$entry.Error = $_.Exception.Message
		}

		$results.Add($entry)
	}

	return @($results)
}

function Invoke-BaselineRemoteCompliance
{
	<#
		.SYNOPSIS
		Runs a Baseline compliance check against one or more remote machines.

		.DESCRIPTION
		For each computer, opens a PSSession, copies the profile and Baseline
		module files to a temporary directory, invokes the compliance check
		headlessly inside the session, collects results, and cleans up.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter(Mandatory)]
		[string]$ProfilePath,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential
	)

	if (-not (Test-Path -LiteralPath $ProfilePath))
	{
		throw "Profile file not found: $ProfilePath"
	}

	$moduleRoot = $Script:SharedHelpersModuleRoot
	$repoRoot   = $Script:SharedHelpersRepoRoot

	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($computer in @($ComputerName))
	{
		$entry = [pscustomobject]@{
			ComputerName = $computer
			Compliant    = $false
			DriftedCount = 0
			TotalChecked = 0
			Errors       = @()
		}

		$session = $null
		try
		{
			# Open remote session.
			$sessionParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }
			if ($Credential) { $sessionParams.Credential = $Credential }
			$session = New-PSSession @sessionParams

			# Create a temp staging directory on the remote machine.
			$remoteTempDir = Invoke-Command -Session $session -ScriptBlock {
				$dir = Join-Path ([System.IO.Path]::GetTempPath()) "Baseline_$([guid]::NewGuid().ToString('N'))"
				$null = New-Item -Path $dir -ItemType Directory -Force
				return $dir
			}

			# Copy profile file to the remote temp directory.
			$remoteProfilePath = Join-Path $remoteTempDir (Split-Path $ProfilePath -Leaf)
			Copy-Item -Path $ProfilePath -Destination $remoteProfilePath -ToSession $session -Force

			# Copy the Module directory to the remote temp directory.
			$remoteModuleDir = Join-Path $remoteTempDir 'Module'
			Copy-Item -Path $moduleRoot -Destination $remoteModuleDir -ToSession $session -Recurse -Force

			# Copy the Localizations directory (required by the module).
			$localizationsDir = Join-Path $repoRoot 'Localizations'
			if (Test-Path -LiteralPath $localizationsDir)
			{
				$remoteLocDir = Join-Path $remoteTempDir 'Localizations'
				Copy-Item -Path $localizationsDir -Destination $remoteLocDir -ToSession $session -Recurse -Force
			}

			# Run the compliance check on the remote machine.
			$remoteResult = Invoke-Command -Session $session -ArgumentList $remoteProfilePath, $remoteModuleDir -ScriptBlock {
				param ($profilePath, $moduleDir)

				$errors = [System.Collections.Generic.List[string]]::new()
				$report = $null

				try
				{
					# Import the SharedHelpers module from the staged directory.
					$sharedHelpersPath = Join-Path $moduleDir 'SharedHelpers.psm1'
					Import-Module -Name $sharedHelpersPath -Force -ErrorAction Stop

					# Load the profile.
					$profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
					$profile = $profileContent | ConvertFrom-Json -ErrorAction Stop

					# Load the manifest.
					$manifest = @(Import-TweakManifestFromData)
					if (-not $manifest -or $manifest.Count -eq 0)
					{
						$errors.Add('Failed to load tweak manifest on remote machine.')
					}
					else
					{
						$report = Test-SystemCompliance -Profile $profile -Manifest $manifest
					}
				}
				catch
				{
					$errors.Add($_.Exception.Message)
				}

				return @{
					Report = $report
					Errors = @($errors)
				}
			}

			# Process remote results.
			if ($remoteResult.Report)
			{
				$report = $remoteResult.Report
				$entry.TotalChecked = $report.TotalChecked
				$entry.DriftedCount = $report.Drifted
				$entry.Compliant    = ($report.Drifted -eq 0)
			}

			if ($remoteResult.Errors -and $remoteResult.Errors.Count -gt 0)
			{
				$entry.Errors = @($remoteResult.Errors)
			}

			# Clean up temp files on the remote machine.
			Invoke-Command -Session $session -ArgumentList $remoteTempDir -ScriptBlock {
				param ($dir)
				if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
			}
		}
		catch
		{
			$entry.Errors = @($_.Exception.Message)
		}
		finally
		{
			if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
		}

		$results.Add($entry)
	}

	return @($results)
}

function Invoke-BaselineRemoteApply
{
	<#
		.SYNOPSIS
		Applies a Baseline configuration profile to one or more remote machines.

		.DESCRIPTION
		For each computer, opens a PSSession, copies the profile and Baseline
		module files to a temporary directory, resolves the profile entries to
		headless commands, executes them inside the remote session, and collects
		per-machine results.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string[]]$ComputerName,

		[Parameter(Mandatory)]
		[string]$ProfilePath,

		[Parameter()]
		[System.Management.Automation.PSCredential]$Credential
	)

	if (-not (Test-Path -LiteralPath $ProfilePath))
	{
		throw "Profile file not found: $ProfilePath"
	}

	$moduleRoot = $Script:SharedHelpersModuleRoot
	$repoRoot   = $Script:SharedHelpersRepoRoot

	$results = [System.Collections.Generic.List[pscustomobject]]::new()

	foreach ($computer in @($ComputerName))
	{
		$entry = [pscustomobject]@{
			ComputerName = $computer
			Applied      = $false
			AppliedCount = 0
			FailedCount  = 0
			Errors       = @()
		}

		$session = $null
		try
		{
			# Open remote session.
			$sessionParams = @{ ComputerName = $computer; ErrorAction = 'Stop' }
			if ($Credential) { $sessionParams.Credential = $Credential }
			$session = New-PSSession @sessionParams

			# Create a temp staging directory on the remote machine.
			$remoteTempDir = Invoke-Command -Session $session -ScriptBlock {
				$dir = Join-Path ([System.IO.Path]::GetTempPath()) "Baseline_$([guid]::NewGuid().ToString('N'))"
				$null = New-Item -Path $dir -ItemType Directory -Force
				return $dir
			}

			# Copy profile file to the remote temp directory.
			$remoteProfilePath = Join-Path $remoteTempDir (Split-Path $ProfilePath -Leaf)
			Copy-Item -Path $ProfilePath -Destination $remoteProfilePath -ToSession $session -Force

			# Copy the Module directory to the remote temp directory.
			$remoteModuleDir = Join-Path $remoteTempDir 'Module'
			Copy-Item -Path $moduleRoot -Destination $remoteModuleDir -ToSession $session -Recurse -Force

			# Copy the Localizations directory (required by the module).
			$localizationsDir = Join-Path $repoRoot 'Localizations'
			if (Test-Path -LiteralPath $localizationsDir)
			{
				$remoteLocDir = Join-Path $remoteTempDir 'Localizations'
				Copy-Item -Path $localizationsDir -Destination $remoteLocDir -ToSession $session -Recurse -Force
			}

			# Copy the Baseline.ps1 entry script for headless execution.
			$baselineScript = Join-Path $repoRoot 'Baseline.ps1'
			if (Test-Path -LiteralPath $baselineScript)
			{
				Copy-Item -Path $baselineScript -Destination $remoteTempDir -ToSession $session -Force
			}

			# Run the profile application on the remote machine.
			$remoteResult = Invoke-Command -Session $session -ArgumentList $remoteProfilePath, $remoteModuleDir, $remoteTempDir -ScriptBlock {
				param ($profilePath, $moduleDir, $baseDir)

				$errors = [System.Collections.Generic.List[string]]::new()
				$appliedCount = 0
				$failedCount  = 0

				try
				{
					# Import the SharedHelpers module from the staged directory.
					$sharedHelpersPath = Join-Path $moduleDir 'SharedHelpers.psm1'
					Import-Module -Name $sharedHelpersPath -Force -ErrorAction Stop

					# Import the main Baseline module.
					$baselineModulePath = Join-Path $moduleDir 'Baseline.psd1'
					if (Test-Path -LiteralPath $baselineModulePath)
					{
						Import-Module -Name $baselineModulePath -Force -ErrorAction Stop
					}

					# Load the profile.
					$profileContent = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
					$profile = $profileContent | ConvertFrom-Json -ErrorAction Stop

					# Extract entries from the profile and build headless command list.
					$profileEntries = @()
					if ($profile.PSObject.Properties['Entries'] -and $profile.Entries)
					{
						$profileEntries = @($profile.Entries)
					}

					foreach ($profileEntry in @($profileEntries))
					{
						if (-not $profileEntry) { continue }

						$functionName = $null
						$paramValue   = $null
						$entryType    = 'Toggle'

						if ($profileEntry.PSObject.Properties['Function'])
						{
							$functionName = [string]$profileEntry.Function
						}
						if ($profileEntry.PSObject.Properties['Type'])
						{
							$entryType = [string]$profileEntry.Type
						}

						if ([string]::IsNullOrWhiteSpace($functionName)) { continue }

						# Resolve the parameter to pass.
						switch ($entryType)
						{
							'Choice'
							{
								if ($profileEntry.PSObject.Properties['Value'] -and
									-not [string]::IsNullOrWhiteSpace([string]$profileEntry.Value))
								{
									$paramValue = [string]$profileEntry.Value
								}
							}
							default
							{
								if ($profileEntry.PSObject.Properties['Param'] -and
									-not [string]::IsNullOrWhiteSpace([string]$profileEntry.Param))
								{
									$paramValue = [string]$profileEntry.Param
								}
							}
						}

						# Execute the function.
						try
						{
							if ($paramValue)
							{
								$cmd = Get-Command -Name $functionName -ErrorAction SilentlyContinue
								if ($cmd)
								{
									& $functionName -$paramValue
									$appliedCount++
								}
								else
								{
									$failedCount++
									$errors.Add("Command not found: $functionName")
								}
							}
							else
							{
								$cmd = Get-Command -Name $functionName -ErrorAction SilentlyContinue
								if ($cmd)
								{
									& $functionName
									$appliedCount++
								}
								else
								{
									$failedCount++
									$errors.Add("Command not found: $functionName")
								}
							}
						}
						catch
						{
							$failedCount++
							$errors.Add("Failed to apply $functionName : $($_.Exception.Message)")
						}
					}
				}
				catch
				{
					$errors.Add($_.Exception.Message)
				}

				return @{
					AppliedCount = $appliedCount
					FailedCount  = $failedCount
					Errors       = @($errors)
				}
			}

			# Process remote results.
			$entry.AppliedCount = $remoteResult.AppliedCount
			$entry.FailedCount  = $remoteResult.FailedCount
			$entry.Applied      = ($remoteResult.FailedCount -eq 0 -and $remoteResult.AppliedCount -gt 0)

			if ($remoteResult.Errors -and $remoteResult.Errors.Count -gt 0)
			{
				$entry.Errors = @($remoteResult.Errors)
			}

			# Clean up temp files on the remote machine.
			Invoke-Command -Session $session -ArgumentList $remoteTempDir -ScriptBlock {
				param ($dir)
				if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
			}
		}
		catch
		{
			$entry.Errors = @($_.Exception.Message)
		}
		finally
		{
			if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
		}

		$results.Add($entry)
	}

	return @($results)
}
