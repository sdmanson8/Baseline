# Shared helper slice for Win10_11Util.

function Update-ProcessPathFromRegistry
{
	$MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
	$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
	$env:Path = (@($MachinePath, $UserPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ";"
}

function Resolve-WinGetExecutable
{
	Update-ProcessPathFromRegistry

	$WingetCommand = Get-Command -Name winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source -ErrorAction SilentlyContinue
	if (-not [string]::IsNullOrWhiteSpace($WingetCommand))
	{
		return $WingetCommand
	}

	$CandidatePaths = @(
		(Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe")
		(Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\winget.exe")
	) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

	return ($CandidatePaths | Select-Object -First 1)
}

function Get-WinGetVersion
{
	$WingetPath = Resolve-WinGetExecutable
	if (-not $WingetPath)
	{
		return $null
	}

	try
	{
		$WingetVersion = & $WingetPath --version 2>$null
		if ($LASTEXITCODE -eq 0)
		{
			$ResolvedVersion = [string]($WingetVersion | Select-Object -First 1)
			if (-not [string]::IsNullOrWhiteSpace($ResolvedVersion))
			{
				return $ResolvedVersion.Trim()
			}
		}
	}
	catch
	{
		return $null
	}

	return $null
}

function Invoke-DownloadFile
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]
		$Uri,

		[Parameter(Mandatory = $true)]
		[string]
		$OutFile,

		[int]
		$MaxAttempts = 3
	)

	try
	{
		[Net.ServicePointManager]::SecurityProtocol = `
			[Net.SecurityProtocolType]::Tls12 -bor `
			[Net.SecurityProtocolType]::Tls11 -bor `
			[Net.SecurityProtocolType]::Tls
	}
	catch
	{
	}

	$attemptErrors = [System.Collections.Generic.List[string]]::new()
	for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++)
	{
		try
		{
			Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
			if (Test-Path -LiteralPath $OutFile)
			{
				return
			}
		}
		catch
		{
			$attemptErrors.Add("attempt ${attempt}: $($_.Exception.Message)")
			Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
			Start-Sleep -Seconds ([Math]::Min($attempt * 2, 5))
		}
	}

	try
	{
		$webClient = New-Object System.Net.WebClient
		$webClient.Headers['User-Agent'] = 'Win10_11Util'
		$webClient.DownloadFile($Uri, $OutFile)
		if (Test-Path -LiteralPath $OutFile)
		{
			return
		}
	}
	catch
	{
		$attemptErrors.Add("webclient fallback: $($_.Exception.Message)")
		Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
	}

	throw ("Failed to download '{0}'. {1}" -f $Uri, ($attemptErrors -join ' | '))
}

function Get-OneDriveSetupPath
{
	$preferredPaths = @()

	if ([Environment]::Is64BitOperatingSystem)
	{
		$preferredPaths += Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'
		$preferredPaths += Join-Path $env:SystemRoot 'Sysnative\OneDriveSetup.exe'

		if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles))
		{
			$preferredPaths += Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDriveSetup.exe'
		}

		if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)}))
		{
			$preferredPaths += Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDriveSetup.exe'
			$preferredPaths += Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'
		}
	}
	else
	{
		$preferredPaths += Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'
	}

	$preferredPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function ConvertTo-NormalizedVersion
{
	param
	(
		[AllowNull()]
		[string]
		$Version
	)

	if ([string]::IsNullOrWhiteSpace($Version))
	{
		return $null
	}

	$Match = [regex]::Match($Version.Trim(), "\d+(?:\.\d+){1,3}")
	if (-not $Match.Success)
	{
		return $null
	}

	$Parts = $Match.Value.Split(".")
	while ($Parts.Count -lt 4)
	{
		$Parts += "0"
	}
	if ($Parts.Count -gt 4)
	{
		$Parts = $Parts[0..3]
	}

	try
	{
		return [System.Version]($Parts -join ".")
	}
	catch
	{
		return $null
	}
}

function Get-InstalledVCRedistVersion
{
	param
	(
		[ValidateSet("x86", "x64")]
		[string]
		$Architecture
	)

	$RegistryPaths = @(
		"HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture",
		"HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture"
	)

	foreach ($RegistryPath in $RegistryPaths)
	{
		try
		{
			$Runtime = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
		}
		catch
		{
			continue
		}

		if ($Runtime.Installed -eq 1)
		{
			return ConvertTo-NormalizedVersion -Version $Runtime.Version
		}
	}

	return $null
}

function Get-InstalledDotNetRuntimeVersion
{
	param
	(
		[ValidateRange(1, 99)]
		[int]
		$MajorVersion
	)

	$RegistryPaths = @(
		"HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App",
		"HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
		"HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App",
		"HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"
	)

	$InstalledVersions = foreach ($RegistryPath in $RegistryPaths)
	{
		if (-not (Test-Path -Path $RegistryPath))
		{
			continue
		}

		Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue | ForEach-Object {
			ConvertTo-NormalizedVersion -Version $_.PSChildName
		}
	}

	$InstalledVersions = $InstalledVersions |
		Where-Object -FilterScript {$null -ne $_ -and $_.Major -eq $MajorVersion} |
		Sort-Object -Descending -Unique

	if ($InstalledVersions)
	{
		return $InstalledVersions[0]
	}

	return $null
}

function Get-LatestDotNetRuntimeRelease
{
	param
	(
		[ValidateRange(1, 99)]
		[int]
		$MajorVersion
	)

	$ReleaseMetadataUri = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$MajorVersion.0/releases.json"
	$ReleaseMetadata = Invoke-RestMethod -Uri $ReleaseMetadataUri -UseBasicParsing
	$LatestReleaseVersion = [string]$ReleaseMetadata."latest-release"
	$Release = $null

	if (-not [string]::IsNullOrWhiteSpace($LatestReleaseVersion))
	{
		$Release = $ReleaseMetadata.releases | Where-Object -FilterScript {$_."release-version" -eq $LatestReleaseVersion} | Select-Object -First 1
	}

	if ($null -eq $Release)
	{
		$Release = $ReleaseMetadata.releases | Select-Object -First 1
	}

	if ($null -eq $Release -or $null -eq $Release.runtime)
	{
		return $null
	}

	$RuntimeFile = $Release.runtime.files | Where-Object -FilterScript {$_.name -eq "dotnet-runtime-win-x64.exe"} | Select-Object -First 1
	$DownloadUrl = [string]$RuntimeFile.url

	if ([string]::IsNullOrWhiteSpace($DownloadUrl))
	{
		return $null
	}

	$DownloadUri = [uri]$DownloadUrl

	[pscustomobject]@{
		Version     = ConvertTo-NormalizedVersion -Version $Release.runtime.version
		DownloadUrl = $DownloadUrl
		FileName    = [System.IO.Path]::GetFileName($DownloadUri.AbsolutePath)
		SourceHost  = $DownloadUri.GetLeftPart([System.UriPartial]::Authority)
		MetadataUri = $ReleaseMetadataUri
	}
}

function Install-VCRedist
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Redistributables"
		)]
		[ValidateSet("2015_2022_x86", "2015_2022_x64")]
		[string[]]
		$Redistributables
	)

	$vcredistVersion = $null

	try
	{
		$Parameters = @{
			Uri             = "https://raw.githubusercontent.com/ScoopInstaller/Extras/refs/heads/master/bucket/vcredist2022.json"
			UseBasicParsing = $true
		}
		$vcredistVersion = ConvertTo-NormalizedVersion -Version (Invoke-RestMethod @Parameters).version
	}
	catch [System.Net.WebException]
	{
		LogWarning "Unable to determine the latest Visual C++ Redistributable version. Installed packages will be left unchanged unless missing."
	}

	$DownloadsFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"

	foreach ($Redistributable in $Redistributables)
	{
		switch ($Redistributable)
		{
			2015_2022_x86
			{
				$DisplayName = "Visual C++ Redistributable (2015 - 2022) x86"
				$InstalledVersion = Get-InstalledVCRedistVersion -Architecture "x86"
				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $vcredistVersion)
				{
					$ShouldInstall = $vcredistVersion -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing it."
				}
				elseif ($null -ne $vcredistVersion)
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $vcredistVersion."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing $DisplayName"
					LogInfo "Installing $DisplayName"

					$Parameters = @{
						Uri             = "https://aka.ms/vs/17/release/VC_redist.x86.exe"
						OutFile         = "$DownloadsFolder\VC_redist.x86.exe"
						UseBasicParsing = $true
					}
					Invoke-WebRequest @Parameters

					$VCx86Process = Start-Process -FilePath "$DownloadsFolder\VC_redist.x86.exe" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($VCx86Process.ExitCode -ne 0) { throw "VC_redist.x86.exe returned exit code $($VCx86Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\VC_redist.x86.exe",
						"$env:TEMP\dd_vcredist_x86_*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f "https://download.visualstudio.microsoft.com")
					LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install ${DisplayName}: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
			2015_2022_x64
			{
				$DisplayName = "Visual C++ Redistributable (2015 - 2022) x64"
				$InstalledVersion = Get-InstalledVCRedistVersion -Architecture "x64"
				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $vcredistVersion)
				{
					$ShouldInstall = $vcredistVersion -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing it."
				}
				elseif ($null -ne $vcredistVersion)
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $vcredistVersion."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing $DisplayName"
					LogInfo "Installing $DisplayName"

					$Parameters = @{
						Uri             = "https://aka.ms/vs/17/release/VC_redist.x64.exe"
						OutFile         = "$DownloadsFolder\VC_redist.x64.exe"
						UseBasicParsing = $true
					}
					Invoke-WebRequest @Parameters

					$VCx64Process = Start-Process -FilePath "$DownloadsFolder\VC_redist.x64.exe" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($VCx64Process.ExitCode -ne 0) { throw "VC_redist.x64.exe returned exit code $($VCx64Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\VC_redist.x64.exe",
						"$env:TEMP\dd_vcredist_amd64_*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f "https://download.visualstudio.microsoft.com")
					LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install ${DisplayName}: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
		}
	}
}

function Install-DotNetRuntimes
{
	[CmdletBinding()]
	param
	(
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Runtimes"
		)]
		[ValidateSet("NET8x64", "NET9x64")]
		[string[]]
		$Runtimes
	)

	$DownloadsFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name "{374DE290-123F-4565-9164-39C4925E467B}"

	foreach ($Runtime in $Runtimes)
	{
		switch ($Runtime)
		{
			NET8x64
			{
				$DisplayName = ".NET 8 x64"
				$InstalledVersion = Get-InstalledDotNetRuntimeVersion -MajorVersion 8
				$NET8Version = $null
				$NET8DownloadUrl = $null
				$NET8FileName = $null
				$NET8SourceHost = "https://builds.dotnet.microsoft.com"

				try
				{
					$NET8Release = Get-LatestDotNetRuntimeRelease -MajorVersion 8
					if ($null -ne $NET8Release)
					{
						$NET8Version = $NET8Release.Version
						$NET8DownloadUrl = $NET8Release.DownloadUrl
						$NET8FileName = $NET8Release.FileName
						$NET8SourceHost = $NET8Release.SourceHost
					}
				}
				catch [System.Net.WebException]
				{
					if ($null -ne $InstalledVersion)
					{
						LogWarning "Unable to determine the latest $DisplayName version. Detected installed version $InstalledVersion, so the install will be skipped."
					}
					else
					{
						LogError ($Localization.NoResponse -f "https://builds.dotnet.microsoft.com")
						LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
						Write-ConsoleStatus -Action "Installing $DisplayName"
						Write-ConsoleStatus -Status failed

						return
					}
				}

				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $NET8Version)
				{
					$ShouldInstall = $NET8Version -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $NET8Version)
				{
					LogError "Unable to determine the latest $DisplayName version."
					Write-ConsoleStatus -Action "Installing $DisplayName"
					Write-ConsoleStatus -Status failed
					return
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing version $NET8Version."
				}
				else
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $NET8Version."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing .NET $NET8Version x64"
					LogInfo "Installing .NET $NET8Version x64"

					$Parameters = @{
						Uri             = $NET8DownloadUrl
						OutFile         = "$DownloadsFolder\$NET8FileName"
						UseBasicParsing = $true
					}
					Invoke-WebRequest @Parameters

					$NET8Process = Start-Process -FilePath "$DownloadsFolder\$NET8FileName" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($NET8Process.ExitCode -ne 0) { throw "$NET8FileName returned exit code $($NET8Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\$NET8FileName",
						"$env:TEMP\Microsoft_.NET_Runtime*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f $NET8SourceHost)
					LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install .NET $NET8Version x64: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
			NET9x64
			{
				$DisplayName = ".NET 9 x64"
				$InstalledVersion = Get-InstalledDotNetRuntimeVersion -MajorVersion 9
				$NET9Version = $null
				$NET9DownloadUrl = $null
				$NET9FileName = $null
				$NET9SourceHost = "https://builds.dotnet.microsoft.com"

				try
				{
					$NET9Release = Get-LatestDotNetRuntimeRelease -MajorVersion 9
					if ($null -ne $NET9Release)
					{
						$NET9Version = $NET9Release.Version
						$NET9DownloadUrl = $NET9Release.DownloadUrl
						$NET9FileName = $NET9Release.FileName
						$NET9SourceHost = $NET9Release.SourceHost
					}
				}
				catch [System.Net.WebException]
				{
					if ($null -ne $InstalledVersion)
					{
						LogWarning "Unable to determine the latest $DisplayName version. Detected installed version $InstalledVersion, so the install will be skipped."
					}
					else
					{
						LogError ($Localization.NoResponse -f "https://builds.dotnet.microsoft.com")
						LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
						Write-ConsoleStatus -Action "Installing $DisplayName"
						Write-ConsoleStatus -Status failed

						return
					}
				}

				$ShouldInstall = $null -eq $InstalledVersion

				if ($null -ne $InstalledVersion -and $null -ne $NET9Version)
				{
					$ShouldInstall = $NET9Version -gt $InstalledVersion
				}

				if (-not $ShouldInstall)
				{
					LogInfo "$DisplayName already installed (version $InstalledVersion)."
					Write-ConsoleStatus -Action "Checking $DisplayName"
					Write-ConsoleStatus -Status success
					continue
				}

				if ($null -eq $NET9Version)
				{
					LogError "Unable to determine the latest $DisplayName version."
					Write-ConsoleStatus -Action "Installing $DisplayName"
					Write-ConsoleStatus -Status failed
					return
				}

				if ($null -eq $InstalledVersion)
				{
					LogInfo "$DisplayName not detected. Installing version $NET9Version."
				}
				else
				{
					LogInfo "$DisplayName version $InstalledVersion detected. Updating to $NET9Version."
				}

				try
				{
					Write-ConsoleStatus -Action "Installing .NET $NET9Version x64"
					LogInfo "Installing .NET $NET9Version x64"

					$Parameters = @{
						Uri             = $NET9DownloadUrl
						OutFile         = "$DownloadsFolder\$NET9FileName"
						UseBasicParsing = $true
					}
					Invoke-WebRequest @Parameters

					$NET9Process = Start-Process -FilePath "$DownloadsFolder\$NET9FileName" -ArgumentList "/install /passive /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
					if ($NET9Process.ExitCode -ne 0) { throw "$NET9FileName returned exit code $($NET9Process.ExitCode)" }

					$Paths = @(
						"$DownloadsFolder\$NET9FileName",
						"$env:TEMP\Microsoft_.NET_Runtime*.log"
					)
					Get-ChildItem -Path $Paths -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
					Write-ConsoleStatus -Status success
				}
				catch [System.Net.WebException]
				{
					LogError ($Localization.NoResponse -f $NET9SourceHost)
					LogError ($Localization.RestartFunction -f $MyInvocation.Line.Trim())
					Write-ConsoleStatus -Status failed

					return
				}
				catch
				{
					LogError "Failed to install .NET $NET9Version x64: $($_.Exception.Message)"
					Write-ConsoleStatus -Status failed
					continue
				}
			}
		}
	}
}
